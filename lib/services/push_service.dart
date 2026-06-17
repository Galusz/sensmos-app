import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'node_service.dart';

/// PushService — token FCM + propagacja na nody.
/// Token (telefonu) zapisywany na każdym nodzie (POST /config push_token);
/// node przekazuje go do BE przy akcji push, BE wysyła FCM.
class PushService {
  String? _token;
  bool _inited = false;

  String? get token => _token;

  /// Inicjalizacja po Firebase.initializeApp(). Zwraca token (lub null).
  Future<String?> init() async {
    if (_inited) return _token;
    _inited = true;
    final fm = FirebaseMessaging.instance;
    try {
      await fm.requestPermission(alert: true, badge: true, sound: true);
      _token = await fm.getToken();
      fm.onTokenRefresh.listen((t) => _token = t);
    } catch (_) {
      _token = null;
    }
    return _token;
  }

  /// Wyślij token na wszystkie zapisane nody. Zwraca liczbę nodów OK.
  Future<int> syncToNodes(NodeService nodes, {String? override}) async {
    final tok = override ?? _token;
    if (tok == null || tok.isEmpty) return 0;
    int ok = 0;
    for (final n in nodes.nodes) {
      try {
        final res = await http
            .post(Uri.parse('http://${n.ip}/config'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer ${n.pin}',
                },
                body: '{"push_token":"$tok"}')
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) ok++;
      } catch (_) {}
    }
    return ok;
  }
}
