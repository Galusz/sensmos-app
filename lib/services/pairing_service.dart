import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../l10n.dart';

/// Parowanie telefon↔node — klucz, którego BACKEND NIGDY NIE WIDZI.
///
/// Po co: kanał WS BE↔node jest szyfrowany, ale kluczem, który BE potrafi odtworzyć dla
/// każdego noda (ECDH z jego pubkeya). Uwierzytelnia więc „to nasz serwer", a nie „właściciel
/// się zgodził" — przejęty backend mógł otworzyć tunel do cudzego LAN-u i firmware nie miał
/// jak tego odróżnić od prawdziwego żądania.
///
/// Klucz powstaje TUTAJ, w telefonie, i jedzie do noda **wyłącznie po LAN** (POST /node/pair
/// za PIN-em). To jedyna droga, której backend nie widzi — telefon i node są wtedy fizycznie
/// w tej samej sieci. Dlatego parowanie wymaga bycia w domu; to nie niedogodność, tylko
/// cały mechanizm.
///
/// Klucz = uprawnienie. Sparowany node pozwala otworzyć tunel, niesparowany odmawia; nie ma
/// osobnego przełącznika „remote on/off" (był, nazywał się remote_ok — i okazał się atrapą,
/// bo przestawiał go sam backend).
class PairingService {
  static const _prefix = 'pairkey_';
  static const _keyLen = 32;

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String _slot(String deviceId) => '$_prefix$deviceId';

  /// Klucz dla noda albo null, jeśli nie sparowany na TYM telefonie.
  Future<Uint8List?> keyFor(String deviceId) async {
    final hex = await _storage.read(key: _slot(deviceId));
    if (hex == null || hex.length != _keyLen * 2) return null;
    return _fromHex(hex);
  }

  /// Czy z tym nodem da się otworzyć tunel z tego telefonu (jest klucz parowania).
  Future<bool> hasAccess(String deviceId) async =>
      (await _storage.read(key: _slot(deviceId)))?.length == _keyLen * 2;

  /// Zapomnij zapisany dostęp bez pytania noda — używane, gdy node okazał się już
  /// zaktualizowany i stara ścieżka przestała działać.
  Future<void> forget(String deviceId) => _storage.delete(key: _slot(deviceId));

  /// Sparuj: wygeneruj klucz, wyślij do noda po LAN, zapisz lokalnie.
  /// Zwraca null przy sukcesie albo komunikat błędu.
  Future<String?> pair(String deviceId, String nodeIp, String pin) async {
    final key = _randomKey();
    try {
      final res = await http
          .post(Uri.parse('http://$nodeIp/node/pair'),
              headers: {'Authorization': 'Bearer $pin', 'Content-Type': 'application/json'},
              body: jsonEncode({'key': _toHex(key)}))
          .timeout(const Duration(seconds: 6));
      // Komunikaty tłumaczymy TUTAJ: kod HTTP wklejony w string dałby klucz, którego w mapie
      // nigdy nie ma (każdy kod to inny klucz), więc leci jako argument %s.
      if (res.statusCode == 403) return tr('Zły PIN noda.');
      // 404 = firmware sprzed 0.82 nie zna /node/pair. Tunel wymaga dziś FW ≥1.01, więc to
      // nie jest przypadek do obsłużenia — to prośba o aktualizację noda.
      if (res.statusCode == 404) return tr('Node ma za stare oprogramowanie — zaktualizuj je.');
      if (res.statusCode != 200) return tr('Node odrzucił parowanie (HTTP %s).', [res.statusCode]);
    } catch (e) {
      // Najczęstszy powód: telefon jest w innej sieci niż node (LTE albo inne WiFi).
      return tr('Nie widzę noda w tej sieci — połącz telefon z tym samym WiFi co node.');
    }
    // Zapis lokalny DOPIERO po potwierdzeniu z noda: inaczej apka myślałaby, że jest sparowana,
    // a node by o tym nie wiedział i każdy tunel odbijałby się o „bad proof".
    await _storage.write(key: _slot(deviceId), value: _toHex(key));
    return null;
  }

  /// Rozparuj: skasuj klucze na nodzie i lokalnie. Zwraca null przy sukcesie.
  Future<String?> unpair(String deviceId, String nodeIp, String pin) async {
    try {
      final res = await http.delete(Uri.parse('http://$nodeIp/node/pair'),
          headers: {'Authorization': 'Bearer $pin'}).timeout(const Duration(seconds: 6));
      if (res.statusCode == 403) return tr('Zły PIN noda.');
      // 404 = stare firmware (tryb legacy) — nie ma czego kasować na nodzie, czyścimy lokalnie.
      if (res.statusCode != 200 && res.statusCode != 404) {
        return tr('Node odrzucił żądanie (HTTP %s).', [res.statusCode]);
      }
    } catch (e) {
      return tr('Nie widzę noda w tej sieci — połącz telefon z tym samym WiFi co node.');
    }
    await _storage.delete(key: _slot(deviceId));
    return null;
  }

  /// Ile kluczy widzi node (do UI „sparowany"). null = nie udało się zapytać.
  Future<int?> remoteKeyCount(String nodeIp, String pin) async {
    try {
      final res = await http.get(Uri.parse('http://$nodeIp/node/pair'),
          headers: {'Authorization': 'Bearer $pin'}).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      return (jsonDecode(res.body) as Map<String, dynamic>)['keys'] as int?;
    } catch (_) {
      return null;
    }
  }

  /// Zapomnij klucz TYLKO w telefonie (np. przy usuwaniu noda z listy) — node zachowa swój,
  /// więc inne sparowane telefony działają dalej.
  Future<void> forgetLocal(String deviceId) => _storage.delete(key: _slot(deviceId));

  /// Dowód otwarcia tunelu. Ciąg MUSI być bajt w bajt taki sam jak w firmware
  /// (ws_client.cpp on_tun_open), inaczej HMAC się nie zgodzi i node odmówi.
  static String proof(Uint8List key, String deviceId, String ip, int port, int ts) {
    final msg = 'sensmos-tun-open|$deviceId|$ip|$port|$ts';
    return Hmac(sha256, key).convert(utf8.encode(msg)).toString();
  }

  static Uint8List _randomKey() {
    // Random.secure() — kryptograficzny generator systemu. Zwykły Random() byłby przewidywalny
    // i cały mechanizm stałby się ozdobą.
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(_keyLen, (_) => r.nextInt(256)));
  }

  static String _toHex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _fromHex(String h) => Uint8List.fromList(List<int>.generate(
      h.length ~/ 2, (i) => int.parse(h.substring(i * 2, i * 2 + 2), radix: 16)));
}
