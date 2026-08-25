import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'wallet_service.dart';

/// PushService — token FCM rejestrowany w BE (przebudowa 2026-08-24).
/// Jedno źródło prawdy: BE trzyma tokeny per wallet (podpis właściciela), wysyła
/// wszystkie powiadomienia — zarówno te z akcji nodów, jak i alerty o padzie noda
/// (LoRa awaryjne), których martwy node z definicji sam nie wyśle.
/// Stara ścieżka (token na nodzie przez POST /config) wycofana z apki; stare FW
/// dokleja token z NVS jako fallback i BE go użyje, dopóki wallet nie ma rejestracji.
class PushService {
  String? _token;
  bool _inited = false;
  WalletService? _wallet;   // do re-rejestracji przy rotacji tokenu
  DateTime? _registeredAt;

  String? get token => _token;
  bool get registered => _registeredAt != null;

  /// Inicjalizacja po Firebase.initializeApp(). Zwraca token (lub null).
  Future<String?> init() async {
    if (_inited) return _token;
    _inited = true;
    final fm = FirebaseMessaging.instance;
    try {
      await fm.requestPermission(alert: true, badge: true, sound: true);
      _token = await fm.getToken();
      fm.onTokenRefresh.listen((t) {
        _token = t;
        final w = _wallet;
        if (w != null) registerToBackend(w);   // rotacja tokenu → cicha re-rejestracja
      });
    } catch (_) {
      _token = null;
    }
    return _token;
  }

  /// Rejestracja tokenu w BE podpisem walleta. BE odzyskuje adres z podpisu
  /// (ethers.verifyMessage), więc nie da się zapisać tokenu na cudzy wallet.
  Future<bool> registerToBackend(WalletService wallet) async {
    _wallet = wallet;
    final tok = _token;
    if (tok == null || tok.isEmpty) return false;
    try {
      final ts = (DateTime.now().millisecondsSinceEpoch / 1000).round();
      final sig = await wallet.signMessage('sensmos:push:$tok:$ts');
      final res = await http
          .post(Uri.parse('${Config.beUrl}/v1/nodes/push-token'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'token': tok, 'ts': ts, 'sig': sig,
                                'app_version': Config.appVersion}))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        _registeredAt = DateTime.now();
        return true;
      }
    } catch (_) {}
    return false;
  }
}
