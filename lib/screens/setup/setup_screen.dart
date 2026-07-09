import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import '../../theme.dart';
import '../../config.dart';
import '../../core/core_bloc.dart';
import '../../services/wallet_service.dart';
import '../../core/core_event.dart';
import '../../services/ble_service.dart';
import '../../services/node_service.dart';
import '../../services/attest_service.dart';
import '../../l10n.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override State<SetupScreen> createState() => _SetupScreenState();
}

enum _Step { scan, form, connecting, done }

class _SetupScreenState extends State<SetupScreen> {
  _Step   _step     = _Step.scan;
  String? _error;
  String  _status   = '';
  bool    _scanning = false;
  final   _results  = <ScanResult>[];
  ScanResult? _selected;

  final _ssidCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pinCtrl  = TextEditingController(text: '123456');
  String? _nodeIp;
  String  _authDeviceId = '';
  int     _countdown = 0;
  bool    _waitingReset = false;
  int     _doneCountdown = 3;

  // Odtwarzanie ID (FW ≥ 0.46): user wybiera z selektora offline'owy node swojego
  // walleta (lista z BE — działa też po reinstalacji apki) i ta płytka przejmuje jego
  // device_id. Tylko offline wg BE — nadpisanie ID żywego noda odcięłoby go od sieci
  // (zmiana pubkey → jego identify odrzucany).
  SavedNode? _restoreFrom;
  bool       _restoreId = false;
  List<SavedNode> _restoreCandidates = [];

  late final BleService _ble = context.read<BleService>();

  // Kandydaci do odtworzenia = WSZYSTKIE offline (>1h) fizyczne nody TEGO walleta wg BE
  // („z systemu" — działa też po reinstalacji apki, gdy lokalna lista przepadła).
  // BE niedostępny → puste (zostaje ew. MAC-match z lokalnej listy).
  Future<void> _loadRestoreCandidates() async {
    final ns = context.read<NodeService>();
    final owner = context.read<CoreBloc>().state.wallet?.address;
    if (owner == null) return;
    final out = <SavedNode>[];
    try {
      final res = await http.get(
        Uri.parse('${Config.beUrl}/v1/nodes/by-owner/$owner'),
        headers: const {'X-App-Key': 'sensmos2025'},
      ).timeout(const Duration(seconds: 6));
      final list = (jsonDecode(res.body) as Map<String,dynamic>)['nodes'] as List? ?? [];
      for (final raw in list) {
        final n = raw as Map<String,dynamic>;
        final id = n['device_id']?.toString() ?? '';
        if (id.length < 8) continue;
        if ((n['kind']?.toString() ?? 'real') != 'real') continue;   // virtualne nie są ESP
        final secs = (n['seconds_since_ping'] as num?)?.toDouble();
        if (secs != null && secs < 3600) continue;                   // żywy → nie nadpisuj
        final local = ns.nodes.where((x) => x.id == id).toList();
        out.add(local.isNotEmpty ? local.first
            : SavedNode(id: id, ip: '', pin: '', hostname: '',
                label: 'Node ${id.substring(0, 6)}'));
      }
    } catch (_) { /* BE niedostępny → tylko MAC-match */ }
    if (mounted) setState(() => _restoreCandidates = out);
  }

  @override
  void initState() { super.initState(); _startScan(); }

  Future<void> _startScan() async {
    setState(() { _scanning = true; _error = null; _results.clear(); });
    if (!await _ble.isAvailable()) {
      await _ble.turnOn();
      if (!await _ble.isAvailable()) {
        setState(() { _error = tr('Włącz Bluetooth'); _scanning = false; }); return;
      }
    }
    _ble.scan(timeout: const Duration(seconds: 12)).listen(
      (r) { if (mounted) setState(() { _results..clear()..addAll(r); }); },
    );
    await Future.delayed(const Duration(seconds: 12));
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connect(ScanResult r) async {
    await _ble.stopScan();
    setState(() {
      _selected = r; _step = _Step.form; _error = null;
      _restoreFrom = null; _restoreId = false;
    });
    _loadRestoreCandidates();   // async — selektor doładuje się w tle
  }


  Future<void> _startResetCountdown() async {
    setState(() { _waitingReset = true; _countdown = 60; });
    while (_countdown > 0 && mounted) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) setState(() => _countdown--);
    }
    if (mounted) setState(() { _waitingReset = false; _step = _Step.scan; });
  }

  Future<void> _doSetup() async {
    if (_ssidCtrl.text.trim().isEmpty) {
      setState(() => _error = tr('Wpisz nazwę sieci WiFi')); return;
    }
    // Przechwyć serwisy przed awaitami (bezpieczny BuildContext)
    final walletService = context.read<WalletService>();
    final attestService = context.read<AttestService>();
    final nodeService   = context.read<NodeService>();
    final coreBloc      = context.read<CoreBloc>();
    final navigator     = Navigator.of(context);

    setState(() { _step = _Step.connecting; _error = null; _status = tr('Łączenie przez BLE...'); });

    try {
      // 1. Połącz BLE + auth → nonce
      setState(() => _status = tr('Łączenie z nodem...'));
      await _ble.connect(_selected!.device);

      final nodePin = _pinCtrl.text.trim().isNotEmpty ? _pinCtrl.text.trim() : '123456';
      setState(() => _status = tr('Autoryzacja BLE...'));
      final authResp = await _ble.sendCommand({'cmd': 'auth', 'pin': nodePin});
      final nonce = authResp['nonce'] as String? ?? '';
      _authDeviceId = authResp['device_id'] as String? ?? '';
      if (nonce.isEmpty) throw Exception(tr('Brak nonce — aktualizuj firmware'));

      // Odtworzenie poprzedniego ID (FW ≥ 0.46): MUSI być przed register — sig/proof
      // noda budowane z jego device_id. Stary FW odpowie błędem → jedziemy z nowym ID.
      if (_restoreFrom != null && _restoreId && _restoreFrom!.id != _authDeviceId) {
        setState(() => _status = tr('Odtwarzam poprzednie ID noda...'));
        try {
          final r = await _ble.sendCommand(
              {'cmd': 'set_device_id', 'id': _restoreFrom!.id},
              timeout: const Duration(seconds: 6));
          if (r['status'] == 'ok') {
            _authDeviceId = (r['device_id'] as String?) ?? _restoreFrom!.id;
            print('[Setup] ID odtworzone: ${_authDeviceId.substring(0, 8)}…');
          } else {
            print('[Setup] set_device_id odrzucone: ${r['error']} — kontynuuję z nowym ID');
          }
        } catch (e) {
          print('[Setup] set_device_id niedostępne (stary FW?): $e — kontynuuję z nowym ID');
        }
      }

      // 2. Rozstrzygnięcie portfela: istniejący / recovery / nowy
      setState(() => _status = tr('Sprawdzam portfel...'));
      final hasWallet = await walletService.exists();
      Map<String, dynamic> wstatus = {};
      try { wstatus = await _ble.walletStatus(); } catch (_) {}
      final nodeHasBackup = wstatus['has_backup'] == true;

      String ownerAddress;
      String? walletBlob;  // kopia do wysłania na node (jeśli go jeszcze nie ma)

      if (hasWallet) {
        ownerAddress = (await walletService.load())!.address;
        if (!nodeHasBackup) {
          walletBlob = await walletService.exportEncrypted(nodePin);
        }
      } else if (nodeHasBackup) {
        setState(() => _status = tr('Odzyskiwanie portfela z noda...'));
        final r = await _ble.walletRestore();
        final blob = r['blob'] as String?;
        if (blob == null || blob.isEmpty) throw Exception(tr('Brak kopii na nodzie'));
        final w = await walletService.importEncrypted(blob, nodePin);
        ownerAddress = w.address;
      } else {
        setState(() => _status = tr('Tworzę nowy portfel...'));
        final w = await walletService.create();
        ownerAddress = w.address;
        walletBlob = await walletService.exportEncrypted(nodePin);
      }

      setState(() => _status = tr('Podpisywanie challenge...'));
      final sigWallet = await walletService.signMessage(nonce);

      // GPS telefonu (jesteś fizycznie przy nodzie) → ceremonia v2 = trust + lokalizacja naraz.
      // Best-effort: brak/odmowa GPS → node zaufany, ale niebieski (GPS dograsz później).
      String? gpsLat, gpsLon;
      try {
        setState(() => _status = tr('Pobieram pozycję GPS...'));
        if (await Geolocator.isLocationServiceEnabled()) {
          var perm = await Geolocator.checkPermission();
          if (perm == LocationPermission.denied) {
            perm = await Geolocator.requestPermission();
          }
          if (perm != LocationPermission.denied &&
              perm != LocationPermission.deniedForever) {
            final pos = await Geolocator.getCurrentPosition(
                    desiredAccuracy: LocationAccuracy.high)
                .timeout(const Duration(seconds: 12));
            gpsLat = pos.latitude.toStringAsFixed(6);
            gpsLon = pos.longitude.toStringAsFixed(6);
          }
        }
      } catch (_) { /* brak GPS → node niebieski, GPS dograsz później */ }

      setState(() => _status = tr('Łączę z WiFi przez node...'));
      _nodeIp = await _ble.setupNode(
        pin:             nodePin,
        ownerAddress:    ownerAddress,
        walletSignature: sigWallet,
        nonce:           nonce,
        deviceId:        _authDeviceId,
        backendUrl:      Config.nodeBackendUrl,
        wifiSsid:        _ssidCtrl.text.trim(),
        wifiPassword:    _passCtrl.text,
        attest:          attestService,
        signAttest:      walletService.signMessage,
        walletBlob:      walletBlob,
        walletAddr:      ownerAddress,
        gpsLat:          gpsLat,
        gpsLon:          gpsLon,
      );

      setState(() => _status = tr('Łączę z nodem przez sieć...'));
      // /node/confirm już wysłany w setupNode → watchdog wyłączony
      await nodeService.saveNode(_nodeIp!, nodePin, _authDeviceId);

      setState(() { _step = _Step.done; _doneCountdown = 3; });
      for (int i = 3; i >= 0; i--) {
        if (!mounted) return;
        setState(() => _doneCountdown = i);
        if (i == 0) break;
        await Future.delayed(const Duration(seconds: 1));
      }
      coreBloc.add(NodeConnected());
      navigator.popUntil((r) => r.isFirst);

    } catch (e) {
      final msg = e.toString()
          .replaceAll('Exception: ', '')
          .replaceAll('TimeoutException: ', '');
      try { await _ble.disconnect(); } catch (_) {}
      // Błąd BE = watchdog zresetuje node za ~60s
      if (msg.contains('rejestracja_backend_niedostepny')) {
        print('[Setup] BE niedostepny — countdown reset');
        _startResetCountdown();
      } else {
        setState(() { _step = _Step.form; _error = msg; _status = ''; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: _step != _Step.done,
        title: Text(tr('Podłącz urządzenie')),
        actions: [
          if (_step == _Step.scan)
            IconButton(
              icon: _scanning
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.teal))
                  : const Icon(Icons.refresh),
              onPressed: _scanning ? null : _startScan,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: switch (_step) {
          _Step.scan       => _buildScan(),
          _Step.form       => _buildForm(),
          _Step.connecting => _buildConnecting(),
          _Step.done       => _buildDone(),
        },
      ),
    );
  }

  // ── SCAN ─────────────────────────────────────────────────
  Widget _buildScan() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(children: [
        Icon(Icons.bluetooth_searching, color: _scanning ? AppTheme.teal : AppTheme.muted),
        const SizedBox(width: 10),
        Text(_scanning ? tr('Szukam...') : tr('Znalezione urządzenia'),
            style: const TextStyle(color: AppTheme.text, fontSize: 15)),
      ]),
      if (_error != null) ...[const SizedBox(height: 8),
        Text(_error!, style: const TextStyle(color: AppTheme.red))],
      const SizedBox(height: 16),
      Expanded(
        child: _results.isEmpty
            ? Center(child: Text(
                _scanning ? tr('Skanowanie...') : tr('Brak urządzeń.\nUpewnij się że node jest w trybie konfiguracji.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.muted)))
            : ListView.builder(
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final r = _results[i];
                  final name = r.advertisementData.advName.isNotEmpty
                      ? r.advertisementData.advName : r.device.platformName;
                  return Card(child: ListTile(
                    leading: const Icon(Icons.sensors, color: AppTheme.teal),
                    title: Text(name, style: const TextStyle(color: AppTheme.text)),
                    subtitle: Text('RSSI ${r.rssi} dBm', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right, color: AppTheme.muted),
                    onTap: () => _connect(r),
                  ));
                }),
      ),
    ],
  );

  // ── FORM ─────────────────────────────────────────────────
  Widget _buildForm() {
    final name = _selected?.advertisementData.advName.isNotEmpty == true
        ? _selected!.advertisementData.advName : _selected?.device.platformName ?? 'Node';
    return SingleChildScrollView(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(child: ListTile(
          leading: const Icon(Icons.sensors, color: AppTheme.teal),
          title: Text(name, style: const TextStyle(color: AppTheme.text)),
          subtitle: Text(tr('Podaj dane WiFi'), style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        )),
        const SizedBox(height: 20),
        _field(tr('Nazwa sieci WiFi (SSID)'), Icons.wifi, _ssidCtrl),
        const SizedBox(height: 12),
        _field(tr('Hasło WiFi'), Icons.lock_outline, _passCtrl, obscure: true),
        const SizedBox(height: 12),
        _field(tr('PIN noda (zapisany w urządzeniu)'), Icons.pin_outlined, _pinCtrl, type: TextInputType.number),
        if (_restoreFrom != null || _restoreCandidates.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            decoration: BoxDecoration(
              color: AppTheme.teal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.teal.withOpacity(0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('To istniejący node po reflashu? Odtwórz jego ID'),
                  style: const TextStyle(color: AppTheme.teal, fontSize: 13)),
              DropdownButtonFormField<SavedNode?>(
                value: _restoreId ? _restoreFrom : null,
                isExpanded: true,
                dropdownColor: AppTheme.card,
                decoration: const InputDecoration(border: InputBorder.none),
                items: [
                  DropdownMenuItem<SavedNode?>(value: null,
                      child: Text(tr('Nie — zarejestruj jako nowy node'),
                          style: const TextStyle(color: AppTheme.muted, fontSize: 13))),
                  // MAC-match + wszystkie OFFLINE nody z listy (bez duplikatów)
                  ...{
                    if (_restoreFrom != null) _restoreFrom!.id: _restoreFrom!,
                    for (final n in _restoreCandidates) n.id: n,
                  }.values.map((n) => DropdownMenuItem<SavedNode?>(value: n,
                      child: Text('${n.label} · ${n.id.substring(0, 8)}…',
                          style: const TextStyle(color: AppTheme.text, fontSize: 13)))),
                ],
                onChanged: (v) => setState(() { _restoreFrom = v; _restoreId = v != null; }),
              ),
              if (_restoreId && _restoreFrom != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(tr('Node zachowa swoje ID i historię w sieci (wymaga FW 0.46+)'),
                      style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                ),
            ]),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.red.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: AppTheme.red, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_error!, style: const TextStyle(color: AppTheme.red, fontSize: 13))),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.amber.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.amber.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.location_on_outlined, color: AppTheme.amber, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
                    tr('Zaraz poprosimy o lokalizację (GPS) — potwierdza, że node jest '
                        'fizycznie tutaj. Bez niej node działa, ale zarabia znacznie mniej.'),
                    style: const TextStyle(
                        color: AppTheme.amber, fontSize: 12, height: 1.35))),
          ]),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _doSetup,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.teal, foregroundColor: AppTheme.bg,
              padding: const EdgeInsets.symmetric(vertical: 16)),
          child: Text(tr('Konfiguruj'), style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        TextButton(
          onPressed: () => setState(() { _step = _Step.scan; _startScan(); }),
          child: Text(tr('← Wróć do skanowania'), style: const TextStyle(color: AppTheme.muted)),
        ),
      ],
    ));
  }

  // ── CONNECTING ───────────────────────────────────────────
  Widget _buildConnecting() {
    if (_waitingReset) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Stack(alignment: Alignment.center, children: [
            SizedBox(width: 80, height: 80,
              child: CircularProgressIndicator(
                value: _countdown / 60,
                strokeWidth: 6,
                color: AppTheme.red,
                backgroundColor: AppTheme.border,
              )),
            Text('$_countdown',
                style: const TextStyle(color: AppTheme.text,
                    fontSize: 24, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 24),
          Text(tr('Nie udało się zarejestrować noda'),
              style: const TextStyle(color: AppTheme.red, fontSize: 15,
                  fontWeight: FontWeight.w500),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(tr('Urządzenie się resetuje — zaczekaj i spróbuj ponownie.'),
              style: const TextStyle(color: AppTheme.muted, fontSize: 13),
              textAlign: TextAlign.center),
        ]),
      ));
    }
    return Center(
    child: Padding(padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(color: AppTheme.teal),
        const SizedBox(height: 24),
        Text(_status, style: const TextStyle(color: AppTheme.text, fontSize: 15),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(tr('Może potrwać do 30 sekund'),
            style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
      ]),
    ),
  );
  }

  // ── DONE ─────────────────────────────────────────────────
  Widget _buildDone() => Center(
    child: Padding(padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppTheme.teal.withOpacity(0.12), shape: BoxShape.circle),
          child: const Icon(Icons.check, color: AppTheme.teal, size: 48)),
        const SizedBox(height: 20),
        Text(tr('Gotowe!'), style: const TextStyle(color: AppTheme.text, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        if (_nodeIp != null) Text('Node: $_nodeIp', style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () {
              context.read<CoreBloc>().add(NodeConnected());
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          style: FilledButton.styleFrom(
              backgroundColor: AppTheme.teal, foregroundColor: AppTheme.bg,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14)),
          child: Text(
            _doneCountdown > 0
                ? tr('Przejdź do panelu (%s)', [_doneCountdown])
                : tr('Przejdź do panelu'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ]),
    ),
  );

  TextField _field(String label, IconData icon, TextEditingController ctrl,
      {bool obscure = false, TextInputType? type}) =>
    TextField(
      controller: ctrl, obscureText: obscure, keyboardType: type,
      style: const TextStyle(color: AppTheme.text),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(color: AppTheme.muted),
        prefixIcon: Icon(icon, color: AppTheme.muted),
        filled: true, fillColor: AppTheme.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.border)),
      ),
    );

  @override
  void dispose() {
    _ssidCtrl.dispose(); _passCtrl.dispose(); _pinCtrl.dispose();
    _ble.stopScan();
    super.dispose();
  }
}
