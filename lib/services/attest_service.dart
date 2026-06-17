import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'ble_service.dart';

/// Dowody ceremonii trust — pola odpowiedzi trust_sign + przebieg rund.
class TrustEvidence {
  final List<Map<String, dynamic>> rounds; // {c, r, t_ms}
  final String nonce;
  final String bleMac;
  final String efuseMac;
  final String roundsDigest;
  final int uptimeS;
  final String sigEsp;
  final String pubkeyEsp;

  TrustEvidence({
    required this.rounds,
    required this.nonce,
    required this.bleMac,
    required this.efuseMac,
    required this.roundsDigest,
    required this.uptimeS,
    required this.sigEsp,
    required this.pubkeyEsp,
  });
}

/// AttestService — ceremonia trust przez BLE (W2).
/// seed z BE → rundy timing przez BLE → podpis atestu przez node →
/// krzyżowa weryfikacja na BE → devices.trusted.
class AttestService {
  static const _kToken = 'sensmos_app_token';

  /// Token instalacji aplikacji (do rate-limitów; docelowo Play Integrity)
  Future<String> appToken() async {
    final p = await SharedPreferences.getInstance();
    var t = p.getString(_kToken);
    if (t == null || t.isEmpty) {
      final rnd = Random.secure();
      t = List.generate(32, (_) => rnd.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      await p.setString(_kToken, t);
    }
    return t;
  }

  String _randomChallenge() {
    final rnd = Random.secure();
    return List.generate(16, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Pobierz seed ceremonii z BE. null = BE niedostępny / odmowa.
  Future<Map<String, dynamic>?> fetchSeed(String deviceId, String owner) async {
    try {
      final res = await http
          .post(Uri.parse('${Config.beUrl}/v1/attest/seed'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'device_id': deviceId,
                'owner': owner,
                'app_token': await appToken(),
              }))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Przeprowadź ceremonię przez aktywne połączenie BLE (po auth).
  /// resume=true → node po podpisie wraca do trybu WiFi (re-atestacja).
  Future<TrustEvidence> runCeremony({
    required BleService ble,
    required String seed,
    required String owner,
    int rounds = 3,
    bool resume = false,
  }) async {
    final roundLog = <Map<String, dynamic>>[];
    for (var i = 0; i < rounds; i++) {
      final c = _randomChallenge();
      final sw = Stopwatch()..start();
      final resp = await ble.sendCommand(
        {'cmd': 'trust_round', 'c': c},
        timeout: const Duration(seconds: 5),
      );
      sw.stop();
      final r = resp['r'] as String?;
      if (resp['status'] != 'ok' || r == null) {
        throw Exception('trust_round failed: ${resp['msg'] ?? resp}');
      }
      roundLog.add({'c': c, 'r': r, 't_ms': sw.elapsedMilliseconds});
    }

    final sign = await ble.sendCommand(
      {
        'cmd': 'trust_sign',
        'seed': seed,
        'owner': owner,
        if (resume) 'resume': true,
      },
      timeout: const Duration(seconds: 10),
    );
    if (sign['status'] != 'ok' || sign['sig'] == null) {
      throw Exception('trust_sign failed: ${sign['msg'] ?? sign}');
    }

    return TrustEvidence(
      rounds: roundLog,
      nonce: sign['n'] as String,
      bleMac: sign['bm'] as String,
      efuseMac: sign['em'] as String,
      roundsDigest: sign['rd'] as String,
      uptimeS: (sign['up'] as num).toInt(),
      sigEsp: sign['sig'] as String,
      pubkeyEsp: sign['pk'] as String,
    );
  }

  /// Kanoniczny atest — DOKŁADNIE ten string podpisał node i weryfikuje BE.
  String canonicalAttest({
    required String deviceId,
    required String owner,
    required String seed,
    required TrustEvidence ev,
  }) =>
      '{"v":1,"device_id":"$deviceId","owner":"$owner",'
      '"seed":"$seed","nonce":"${ev.nonce}","ble_mac":"${ev.bleMac}",'
      '"efuse_mac":"${ev.efuseMac}","rounds":"${ev.roundsDigest}",'
      '"uptime_s":${ev.uptimeS}}';

  /// Wyślij dowody do BE. Zwraca (sukces, komunikat).
  Future<(bool, String)> submit({
    required String deviceId,
    required String owner,
    required String seed,
    required TrustEvidence ev,
    required String sigWallet,
    required String bleName,
    required String bleMac,
    int? rssi,
  }) async {
    try {
      final res = await http
          .post(Uri.parse('${Config.beUrl}/v1/attest/verify'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'device_id': deviceId,
                'owner': owner,
                'seed': seed,
                'nonce': ev.nonce,
                'ble_mac': ev.bleMac,
                'efuse_mac': ev.efuseMac,
                'rounds_digest': ev.roundsDigest,
                'uptime_s': ev.uptimeS,
                'sig_esp': ev.sigEsp,
                'pubkey': ev.pubkeyEsp,
                'sig_wallet': sigWallet,
                'app_report': {
                  'ble_name': bleName,
                  'ble_mac': bleMac,
                  'rssi': rssi,
                  'rounds': ev.rounds,
                },
              }))
          .timeout(const Duration(seconds: 10));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && j['trusted'] == true) {
        return (true, 'trusted');
      }
      return (false, (j['error'] ?? 'verification_failed').toString());
    } catch (e) {
      return (false, 'network: $e');
    }
  }

  /// Status zaufania z BE.
  Future<Map<String, dynamic>?> status(String deviceId) async {
    try {
      final res = await http
          .get(Uri.parse('${Config.beUrl}/v1/attest/status/$deviceId'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
