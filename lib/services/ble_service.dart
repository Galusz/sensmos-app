import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../l10n.dart';
import 'attest_service.dart';

class BleService {
  BluetoothDevice?         _device;
  BluetoothCharacteristic? _charWrite;
  BluetoothCharacteristic? _charRead;
  StreamSubscription?      _notifySub;
  final _responses = StreamController<Map<String, dynamic>>.broadcast();

  /// Obserwacje z powietrza — do raportu ceremonii trust
  String? get remoteId   => _device?.remoteId.str;
  String? get remoteName => _device?.platformName;
  Future<int?> readRssi() async {
    try { return await _device?.readRssi(); } catch (_) { return null; }
  }

  Future<bool> isAvailable() async {
    if (!await FlutterBluePlus.isSupported) return false;
    return await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
  }

  Future<void> turnOn() async {
    try { await FlutterBluePlus.turnOn(); } catch (_) {}
  }

  Stream<List<ScanResult>> scan({Duration timeout = const Duration(seconds: 10)}) {
    final ctrl = StreamController<List<ScanResult>>.broadcast();
    FlutterBluePlus.startScan(timeout: timeout);
    final sub = FlutterBluePlus.scanResults.listen((r) {
      ctrl.add(r.where((x) {
        final n = x.advertisementData.advName.isNotEmpty
            ? x.advertisementData.advName : x.device.platformName;
        return n.startsWith(Config.bleNamePrefix);
      }).toList());
    });
    ctrl.onCancel = () { sub.cancel(); FlutterBluePlus.stopScan(); };
    return ctrl.stream;
  }

  Future<void> stopScan() async => FlutterBluePlus.stopScan();

  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    try { await device.clearGattCache(); } catch (_) {}
    await device.connect(timeout: const Duration(seconds: 15));
    try { await device.requestMtu(512); } catch (_) {}

    final services = await device.discoverServices();
    BluetoothService? svc;
    for (final s in services) {
      if (s.uuid.toString().toLowerCase() == Config.bleServiceUuid.toLowerCase()) {
        svc = s; break;
      }
    }
    if (svc == null) throw Exception(tr('Brak usługi SENSMOS'));

    for (final ch in svc.characteristics) {
      final u = ch.uuid.toString().toLowerCase();
      if (u == Config.bleCharWrite.toLowerCase()) _charWrite = ch;
      if (u == Config.bleCharRead.toLowerCase())  _charRead  = ch;
    }
    if (_charWrite == null) throw Exception('Brak char WRITE');
    if (_charRead  == null) throw Exception('Brak char READ');

    await _notifySub?.cancel();
    _notifySub = _charRead!.onValueReceived.listen((bytes) {
      if (bytes.isEmpty) return;
      try { _responses.add(jsonDecode(utf8.decode(bytes)) as Map<String,dynamic>); }
      catch (_) {}
    });
    await _charRead!.setNotifyValue(true);
    await Future.delayed(const Duration(milliseconds: 300));
    print('[BLE] Połączono i gotowy do komunikacji');
  }

  Future<Map<String,dynamic>> sendCommand(Map<String,dynamic> cmd, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_charWrite == null) throw Exception(tr('Nie połączono'));
    final expected = cmd['cmd'];
    final completer = Completer<Map<String,dynamic>>();

    late StreamSubscription sub;
    sub = _responses.stream.listen((j) {
      if (j['cmd'] == expected && !completer.isCompleted) {
        completer.complete(j);
        sub.cancel();
      }
    }, onError: (e) {
      if (!completer.isCompleted) completer.completeError(e);
    }, onDone: () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('BLE rozłączone: $expected'));
      }
    });

    Future.delayed(timeout, () {
      if (!completer.isCompleted) {
        sub.cancel();
        completer.completeError(TimeoutException('Timeout: $expected'));
      }
    });

    await _charWrite!.write(utf8.encode(jsonEncode(cmd)), withoutResponse: false);
    print('[BLE] → $expected');
    return completer.future;
  }

  // ── Tryb serwisowy: status/backup/recovery portfela + zmiana WiFi ──
  Future<Map<String, dynamic>> walletStatus() =>
      sendCommand({'cmd': 'wallet_status'}, timeout: const Duration(seconds: 6));

  Future<Map<String, dynamic>> walletRestore() =>
      sendCommand({'cmd': 'wallet_restore'}, timeout: const Duration(seconds: 8));

  Future<Map<String, dynamic>> wifiSet(String ssid, String password) =>
      sendCommand({'cmd': 'wifi_set', 'ssid': ssid, 'password': password},
          timeout: const Duration(seconds: 8));

  Future<String> setupNode({
    required String pin,
    required String ownerAddress,
    required String walletSignature,
    required String nonce,
    required String deviceId,
    required String backendUrl,
    required String wifiSsid,
    required String wifiPassword,
    AttestService? attest,
    Future<String> Function(String message)? signAttest,
    String? walletBlob,
    String? walletAddr,
    String? gpsLat,   // GPS telefonu (przy nodzie) → atest v2 (lokalizacja + trust naraz)
    String? gpsLon,
  }) async {
    // ── Ceremonia trust — PRZED register (register restartuje node) ──
    String? seed;
    TrustEvidence? trustEv;
    final obsMac  = remoteId  ?? '';
    final obsName = remoteName ?? '';
    int? obsRssi;
    if (attest != null && signAttest != null) {
      print('[Setup] Trust: pobieram seed z BE...');
      final seedResp = await attest.fetchSeed(deviceId, ownerAddress);
      if (seedResp != null) {
        seed = seedResp['seed'] as String?;
        final nRounds = (seedResp['rounds'] as num?)?.toInt() ?? 3;
        obsRssi = await readRssi();
        try {
          trustEv = await attest.runCeremony(
              ble: this, seed: seed!, owner: ownerAddress, rounds: nRounds,
              gpsLat: gpsLat, gpsLon: gpsLon);
          print('[Setup] Trust: ceremonia OK (${trustEv.rounds.length} rund)');
        } catch (e) {
          print('[Setup] Trust: ceremonia nieudana: $e');
          trustEv = null;
        }
      } else {
        print('[Setup] Trust: BE niedostępny — pomijam (re-atestacja później)');
      }
    }

    // Backup portfela na node PRZED register (register restartuje node)
    if (walletBlob != null && walletBlob.isNotEmpty) {
      try {
        final b = await sendCommand({
          'cmd': 'wallet_backup',
          'blob': walletBlob,
          'addr': walletAddr ?? '',
        }, timeout: const Duration(seconds: 6));
        print('[Setup] Backup portfela: ${b['status']}');
      } catch (e) {
        print('[Setup] Backup portfela nieudany: $e');
      }
    }

    print('[Setup] 1/5 Wysyłam register przez BLE...');
    final regResp = await sendCommand({
      'cmd':         'register',
      'owner':       ownerAddress,
      'sig_wallet':  walletSignature,
      'backend_url': backendUrl,
      'ssid':        wifiSsid,
      'password':    wifiPassword,
    }, timeout: const Duration(seconds: 12));
    print('[Setup] 1/5 Register OK — sig_esp: ${(regResp['sig_esp'] as String?)?.substring(0,16) ?? 'BRAK'}...');

    print('[Setup] 2/5 Rozłączam BLE (node restartuje się)...');
    await disconnect();
    print('[Setup] 2/5 BLE rozłączone');

    // Szukaj KONKRETNEGO noda po hostname (sensmos-<6 znaków device_id>) —
    // przy wielu nodach w sieci ogólne skanowanie łapie pierwszy z brzegu
    final shortId = deviceId.length >= 6 ? deviceId.substring(0, 6).toLowerCase() : '';
    print('[Setup] 3/5 Szukam noda sensmos-$shortId przez mDNS (30s)...');
    String? ip;
    if (shortId.isNotEmpty) {
      ip = await discoverByHostname(
          hostname: 'sensmos-$shortId', timeout: const Duration(seconds: 30));
    }
    ip ??= await discoverNodeMdns(timeout: const Duration(seconds: 10));
    if (ip == null) {
      print('[Setup] 3/5 BŁĄD: mDNS nie znalazł noda');
      throw Exception(tr('Node nie pojawił się w sieci.\nSprawdź SSID i hasło WiFi.'));
    }
    print('[Setup] 3/5 Node znaleziony: $ip');

    print('[Setup] 4/5 Rejestruję w backendzie: ${Config.beUrl}/v1/register');
    if (regResp['sig_esp'] != null) {
      try {
        final message = '{"device_id":"$deviceId","owner":"$ownerAddress",'
            '"nonce":"$nonce","ts":0}';
        final beRes = await http.post(
          Uri.parse('${Config.beUrl}/v1/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'message':    message,
            'sig_esp':    regResp['sig_esp'],
            'sig_wallet': walletSignature,
            'pubkey':     regResp['pubkey_esp'],
            'proof':      regResp['proof'],
          }),
        ).timeout(const Duration(seconds: 8));
        print('[Setup] 4/5 BE: ' + beRes.statusCode.toString() + ' ' + beRes.body);
        if (beRes.statusCode != 200 && beRes.statusCode != 409) {
          throw Exception('rejestracja_backend_niedostepny');
        }
      } catch (e) {
        print('[Setup] 4/5 BE BLAD: ' + e.toString());
        throw Exception('rejestracja_backend_niedostepny');
      }
    }

    // ── Trust: submit dowodów (po /v1/register — device już w DB) ──
    if (attest != null && signAttest != null && trustEv != null && seed != null) {
      try {
        final canonical = attest.canonicalAttest(
            deviceId: deviceId, owner: ownerAddress, seed: seed, ev: trustEv);
        final sigWallet = await signAttest(canonical);
        final (ok, msg) = await attest.submit(
          deviceId: deviceId, owner: ownerAddress, seed: seed,
          ev: trustEv, sigWallet: sigWallet,
          bleName: obsName, bleMac: obsMac, rssi: obsRssi,
        );
        print('[Setup] Trust: ${ok ? "node zaufany ✓" : "weryfikacja: $msg"}');
      } catch (e) {
        print('[Setup] Trust submit error: $e');
      }
    }

    await Future.delayed(const Duration(seconds: 2));
    try {
      await http.post(Uri.parse('http://$ip/node/confirm'),
          headers: {'Authorization': 'Bearer $pin'})
          .timeout(const Duration(seconds: 5));
      print('[Setup] 5/5 /node/confirm OK — node potwierdzony!');
    } catch (e) {
      print('[Setup] confirm error: $e');
    }

    return ip;
  }


  // mDNS — pierwszy znaleziony node
  Future<String?> discoverNodeMdns({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final results = await discoverAllNodes(timeout: timeout);
    return results.isEmpty ? null : results.first['ip'];
  }

  // mDNS — wszyscy znalezieni nodowie
  Future<List<Map<String,String>>> discoverAllNodes({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final mdns    = MDnsClient();
    final results = <Map<String,String>>[];
    final seen    = <String>{};
    print('[mDNS] Start skanowania _sensmos._tcp.local (timeout: ${timeout.inSeconds}s)');
    try {
      await mdns.start();
      print('[mDNS] Socket otwarty');
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        await for (final ptr in mdns.lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer('_sensmos._tcp.local'))) {
          await for (final srv in mdns.lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName))) {
            await for (final a in mdns.lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target))) {
              final ip = a.address.address;
              if (!seen.contains(ip)) {
                seen.add(ip);
                results.add({'ip': ip, 'hostname': srv.target});
                print('[mDNS] Znaleziono: $ip (${srv.target})');
              } else {
                print('[mDNS] Duplikat: $ip (pominięto)');
              }
            }
          }
        }
        if (results.isNotEmpty) break;
        await Future.delayed(const Duration(seconds: 2));
      }
    } catch (e) { print('[mDNS] BŁĄD: ' + e.toString()); } finally { mdns.stop(); print('[mDNS] Stop. Znaleziono: ${results.length}'); }
    return results;
  }

  // mDNS — konkretny hostname
  Future<String?> discoverByHostname({
    required String hostname,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final target = hostname.endsWith('.local') ? hostname : '$hostname.local';
    final mdns   = MDnsClient(rawDatagramSocketFactory:
        (dynamic host, int port, {bool reuseAddress=true, bool reusePort=true, int ttl=1}) =>
            RawDatagramSocket.bind(host, port, reuseAddress: reuseAddress, reusePort: false, ttl: ttl));
    String? ip;
    try {
      await mdns.start();
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline) && ip == null) {
        await for (final a in mdns.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(target))) {
          ip = a.address.address; break;
        }
        if (ip == null) await Future.delayed(const Duration(seconds: 1));
      }
    } catch (e) { print('[mDNS] $e'); } finally { mdns.stop(); }
    return ip;
  }

  Future<void> disconnect() async {
    await _notifySub?.cancel(); _notifySub = null;
    try { await _device?.disconnect(); } catch (_) {}
    _device = null; _charWrite = null; _charRead = null;
  }

  void dispose() { _notifySub?.cancel(); _responses.close(); }
}
