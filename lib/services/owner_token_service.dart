import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../l10n.dart';
import 'wallet_service.dart';

/// Token ownera — jedno podpisanie zamiast podpisywania KAŻDEGO wejścia w tunel.
///
/// Po co: tunel (SSH / panel HA / panel LAN) uwierzytelniał się świeżym podpisem portfela.
/// User z hasłem na portfelu musiał je wpisywać przy każdym wejściu — albo trzymać portfel
/// odblokowany na stałe. To drugie już raz kosztowało kogoś środki, więc lepiej mieć sekret
/// o wąskim zakresie: token otwiera wyłącznie tunel i nie rusza portfela.
///
/// Wydanie: JEDEN podpis `sensmos:ownertoken:issue:<ts>` → BE zwraca `smt_…` (u siebie trzyma
/// tylko sha256). Token leży w bezpiecznym magazynie pod adresem portfela i od tej chwili
/// portfel może zostać zamknięty.
///
/// Czego token NIE robi: nie zastępuje klucza parowania (dowód HMAC dalej liczy telefon,
/// a sprawdza node), nie autoryzuje niczego w portfelu i nie omija dziennej opłaty za tunel.
class OwnerTokenService {
  static const _prefix = 'ownertok_';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String _slot(String owner) => '$_prefix${owner.toLowerCase()}';

  /// Token z magazynu albo null. Nie gada z siecią.
  Future<String?> cached(String owner) async {
    final t = await _storage.read(key: _slot(owner));
    return (t != null && t.startsWith('smt_')) ? t : null;
  }

  /// Wydaje nowy token — WYMAGA odblokowanego portfela (podpis). Zapis lokalny dopiero po
  /// potwierdzeniu z BE, żeby nie zostać z tokenem, którego serwer nie zna.
  Future<String> issue(String owner, WalletService wallet, {String? label}) async {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sig = await wallet.signMessage('sensmos:ownertoken:issue:$ts');
    final res = await http.post(
      Uri.parse('${Config.beUrl}/v1/nodes/owner-token'),
      headers: const {'Content-Type': 'application/json', 'X-App-Key': 'sensmos2025'},
      body: jsonEncode({'owner': owner, 'ts': ts, 'sig': sig, if (label != null) 'label': label}),
    ).timeout(const Duration(seconds: 12));
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || j['token'] == null) {
      throw Exception(j['error'] ?? tr('Nie udało się wydać tokenu dostępu.'));
    }
    final token = j['token'] as String;
    await _storage.write(key: _slot(owner), value: token);
    return token;
  }

  /// Zapomnij token lokalnie (np. BE odrzucił go jako odwołany).
  Future<void> forget(String owner) => _storage.delete(key: _slot(owner));

  /// Lista aktywnych tokenów właściciela (do ekranu ustawień). Wymaga podpisu.
  Future<List<Map<String, dynamic>>> list(String owner, WalletService wallet) async {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sig = await wallet.signMessage('sensmos:ownertoken:list:$ts');
    final res = await http.post(
      Uri.parse('${Config.beUrl}/v1/nodes/owner-token/list'),
      headers: const {'Content-Type': 'application/json', 'X-App-Key': 'sensmos2025'},
      body: jsonEncode({'owner': owner, 'ts': ts, 'sig': sig}),
    ).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return [];
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['tokens'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  /// Odwołuje WSZYSTKIE tokeny właściciela (np. „zgubiłem telefon") i czyści lokalny.
  Future<int> revokeAll(String owner, WalletService wallet) async {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sig = await wallet.signMessage('sensmos:ownertoken:revoke:$ts');
    final res = await http.post(
      Uri.parse('${Config.beUrl}/v1/nodes/owner-token/revoke'),
      headers: const {'Content-Type': 'application/json', 'X-App-Key': 'sensmos2025'},
      body: jsonEncode({'owner': owner, 'ts': ts, 'sig': sig}),
    ).timeout(const Duration(seconds: 12));
    await forget(owner);
    if (res.statusCode != 200) return 0;
    return ((jsonDecode(res.body) as Map<String, dynamic>)['revoked'] as num?)?.toInt() ?? 0;
  }
}
