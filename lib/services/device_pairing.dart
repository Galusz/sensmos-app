import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'package:sensmos_store/sensmos_store.dart';
import 'wallet_service.dart';

/// Parowanie URZĄDZENIA z kontem — strona telefonu.
///
/// Nie mylić z `pairing_service.dart`: tamto paruje telefon z NODEM po LAN-ie i klucza
/// nigdy nie widzi backend. Tu chodzi o wpuszczenie komputera na konto.
///
/// Komputer pokazuje kod i czeka. Człowiek przepisuje kod tutaj (albo skanuje QR z TYM SAMYM
/// kodem — to nie jest drugi kanał, tylko wygodniejszy sposób wpisania tych samych znaków).
/// Telefon odczytuje z serwera, kto się zgłosił, wydaje token o zaznaczonym zakresie i odkłada go
/// ZAPIECZĘTOWANY kluczem publicznym tego komputera.
///
/// Serwer jest wyłącznie skrzynką kontaktową: dostaje SKRÓT kodu, nigdy sam kod, a paczki nie ma
/// czym otworzyć — kod wchodzi do wyprowadzenia klucza szyfrującego, więc podmiana klucza po
/// drodze nic nie daje.
class DevicePairing {
  /// Etykieta oddzielająca to zastosowanie od pakowania kluczy plików.
  static const _label = 'sensmos:pair:v1';

  /// Alfabet kodu bez znaków, które ludzie mylą przy przepisywaniu: zero i O, jedynka oraz I i L.
  static const alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

  /// Do porównań i do kryptografii bierzemy postać kanoniczną, żeby spacje, myślniki i małe litery
  /// nie decydowały o tym, czy parowanie się uda.
  static String normalize(String code) =>
      code.toUpperCase().split('').where(alphabet.contains).join();

  /// Skrót kodu — to jedyne, co widzi serwer.
  static String rendezvous(String code) =>
      sha256.convert(utf8.encode('sensmos:pair:${normalize(code)}')).toString().substring(0, 32);

  /// Kto czeka pod tym kodem. Zwraca `{name, pub}` albo rzuca z powodem po ludzku.
  static Future<Map<String, dynamic>> lookup(String code) async {
    final r = await http.get(Uri.parse('${Config.beUrl}/v1/pair/${rendezvous(code)}'))
        .timeout(const Duration(seconds: 12));
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200 || m['ok'] != true) {
      throw Exception(m['error'] ?? 'unknown or expired code');
    }
    return m;
  }

  /// Wydaje token o zaznaczonym zakresie i odkłada go zapieczętowanego dla tego komputera.
  ///
  /// `readFiles` dokłada do paczki ziarno skrzynki, czyli prawo ODCZYTU plików. Bez niego komputer
  /// wyśle plik i zobaczy listę, ale nie odczyta żadnej nazwy ani treści — nawet własnej wysyłki
  /// po restarcie. To nie jest niedoróbka, tylko sens tego przełącznika.
  static Future<void> pair({
    required String code,
    required String owner,
    required WalletService wallet,
    required String deviceName,
    required List<String> scopes,
    required bool readFiles,
  }) async {
    final info = await lookup(code);

    // Zakresy wchodzą w PODPISYWANY komunikat — inaczej dałoby się cudzym podpisem wyprosić
    // szerszy token, niż właściciel widział na ekranie.
    final sorted = [...scopes]..sort();
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sig = await wallet.signMessage('sensmos:ownertoken:issue:$ts:${sorted.join(',')}');
    final res = await http.post(
      Uri.parse('${Config.beUrl}/v1/nodes/owner-token'),
      headers: const {'Content-Type': 'application/json', 'X-App-Key': Config.appKey},
      body: jsonEncode({'owner': owner, 'ts': ts, 'sig': sig,
                        'label': deviceName, 'scopes': sorted}),
    ).timeout(const Duration(seconds: 15));
    final tok = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || tok['token'] == null) {
      throw Exception(tok['error'] ?? 'could not issue a token');
    }

    final payload = <String, dynamic>{
      'be': Config.beUrl,
      'owner': owner,
      'token': tok['token'],
      'scopes': sorted,
    };
    // Publiczna połowa skrzynki jedzie ZAWSZE — bez niej urządzenie nie ma czym zaszyfrować
    // wysyłki, nawet jeśli nie wolno mu niczego odczytać. To jest właśnie sedno: pisać można
    // kluczem publicznym, czytać dopiero prywatnym.
    final sigBox = await wallet.signMessage('sensmos:store:v1');
    final seed = StoreCrypto.boxSeed(_bytes(sigBox));
    final para = await StoreCrypto.boxKeyPair(_bytes(sigBox));
    payload['box_pub'] = StoreCrypto.pubHex(await para.extractPublicKey());
    if (readFiles) {
      // Ziarno, nie gotowa para: komputer wyprowadzi z niego tę samą skrzynkę tym samym kodem,
      // co telefon, więc nie ma dwóch sposobów liczenia jednego klucza.
      payload['box_seed'] = _hex(seed);
    }

    final sealed = await StoreCrypto.sealTo(
      StoreCrypto.pubFromHex(info['pub'] as String),
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      label: _label,
      extra: utf8.encode(normalize(code)),
    );

    final put = await http.post(
      Uri.parse('${Config.beUrl}/v1/pair/seal'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'rendezvous': rendezvous(code), 'blob': sealed}),
    ).timeout(const Duration(seconds: 15));
    final done = jsonDecode(put.body) as Map<String, dynamic>;
    if (put.statusCode != 200 || done['ok'] != true) {
      throw Exception(done['error'] ?? 'could not hand the token over');
    }
  }

  static String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _bytes(String hexOr0x) {
    final s = hexOr0x.startsWith('0x') ? hexOr0x.substring(2) : hexOr0x;
    return Uint8List.fromList(
        List.generate(s.length ~/ 2, (i) => int.parse(s.substring(2 * i, 2 * i + 2), radix: 16)));
  }
}
