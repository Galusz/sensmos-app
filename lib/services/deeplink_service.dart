import 'package:flutter/services.dart';

/// Skróty z widgetu na pulpicie: `sensmos://open?kind=ha|term|app`.
///
/// Widget nie zna żadnych sekretów — otwiera tylko apkę pod adresem, a co dalej, decyduje
/// już apka (który node, czy jest sparowany, czy ma token ownera).
class DeepLinkService {
  static const _ch = MethodChannel('sensmos/deeplink');

  /// Adres, z którym apka wstała (albo null). Zwracany JEDEN raz.
  static Future<String?> initial() async {
    try {
      return await _ch.invokeMethod<String>('getInitial');
    } catch (_) {
      return null;   // iOS / brak kanału — skróty są androidowe
    }
  }

  /// Kolejne stuknięcia w widget, gdy apka już żyje.
  static void listen(void Function(String link) onLink) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'link' && call.arguments is String) onLink(call.arguments as String);
      return null;
    });
  }

  /// `sensmos://open?kind=ha` → 'ha'. Zwraca null dla obcych adresów.
  static String? kindOf(String link) {
    final u = Uri.tryParse(link);
    if (u == null || u.scheme != 'sensmos') return null;
    return u.queryParameters['kind'] ?? 'app';
  }
}
