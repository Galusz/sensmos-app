import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as cg;
import 'package:flutter_test/flutter_test.dart';
import 'package:sensmos_app/services/device_pairing.dart';
import 'package:sensmos_store/sensmos_store.dart';

/// Parowanie komputera z kontem. Testujemy to, na czym ono stoi: paczkę otwiera WYŁĄCZNIE ten
/// komputer i wyłącznie z tym kodem, a serwer — który zna sam skrót kodu — nie ma czym jej otworzyć.
void main() {
  const label = 'sensmos:pair:v1';

  test('kod sprowadzony do postaci kanonicznej — spacje, myślniki i małe litery nie psują', () {
    expect(DevicePairing.normalize('abc2-3xy z'), 'ABC23XYZ');
    expect(DevicePairing.rendezvous('abc2-3xy z'), DevicePairing.rendezvous('ABC23XYZ'));
  });

  test('skrót kodu nie zdradza kodu i jest inny dla innego kodu', () {
    final a = DevicePairing.rendezvous('ABC23XYZ');
    final b = DevicePairing.rendezvous('ABC23XY2');
    expect(a.length, 32);
    expect(a, isNot(b));
    expect(a.contains('ABC'), isFalse);
  });

  test('paczkę otwiera komputer swoim kluczem i tym samym kodem', () async {
    final pc = await cg.X25519().newKeyPair();
    final pub = await pc.extractPublicKey();
    const kod = 'ABC23XYZ4KMN';
    final tresc = utf8.encode(jsonEncode({'token': 'smt_test', 'scopes': ['store.use']}));

    final sealed = await StoreCrypto.sealTo(
        StoreCrypto.pubFromHex(StoreCrypto.pubHex(pub)), Uint8List.fromList(tresc),
        label: label, extra: utf8.encode(kod));

    final out = await StoreCrypto.openSealed(sealed, pc, label: label, extra: utf8.encode(kod));
    expect(jsonDecode(utf8.decode(out))['token'], 'smt_test');
  });

  test('zły kod nie otwiera paczki, mimo poprawnego klucza prywatnego', () async {
    final pc = await cg.X25519().newKeyPair();
    final pub = await pc.extractPublicKey();
    final sealed = await StoreCrypto.sealTo(
        StoreCrypto.pubFromHex(StoreCrypto.pubHex(pub)), Uint8List.fromList(utf8.encode('x')),
        label: label, extra: utf8.encode('ABC23XYZ4KMN'));

    expect(
      () => StoreCrypto.openSealed(sealed, pc, label: label, extra: utf8.encode('ABC23XYZ4KMP')),
      throwsA(anything),
    );
  });

  test('cudzy klucz prywatny nie otwiera paczki, mimo znajomości kodu', () async {
    final pc = await cg.X25519().newKeyPair();
    final obcy = await cg.X25519().newKeyPair();
    final pub = await pc.extractPublicKey();
    const kod = 'ABC23XYZ4KMN';
    final sealed = await StoreCrypto.sealTo(
        StoreCrypto.pubFromHex(StoreCrypto.pubHex(pub)), Uint8List.fromList(utf8.encode('x')),
        label: label, extra: utf8.encode(kod));

    expect(
      () => StoreCrypto.openSealed(sealed, obcy, label: label, extra: utf8.encode(kod)),
      throwsA(anything),
    );
  });

  test('ziarno skrzynki: parowanie musi uzywac boxFromSeed, nie boxKeyPair', () async {
    final sig = StoreCrypto.randomBytes(65);          // udawany podpis portfela
    final seed = StoreCrypto.boxSeed(sig);

    final zTelefonu = await StoreCrypto.boxKeyPair(sig);
    final zZiarna = await StoreCrypto.boxFromSeed(seed);
    expect(StoreCrypto.pubHex(await zZiarna.extractPublicKey()),
           StoreCrypto.pubHex(await zTelefonu.extractPublicKey()),
           reason: 'komputer z ziarna ma wyprowadzic TE SAMA skrzynke co telefon');

    // Pomylka, ktora zdarzyla sie naprawde: ziarno podane tam, gdzie oczekiwany jest podpis.
    // Wychodzi inny klucz, a widac to dopiero jako niezgodny MAC przy pierwszym odczycie.
    final zle = await StoreCrypto.boxKeyPair(seed);
    expect(StoreCrypto.pubHex(await zle.extractPublicKey()),
           isNot(StoreCrypto.pubHex(await zTelefonu.extractPublicKey())));
  });

  test('etykieta oddziela zastosowania — kluczem pliku nie otworzysz paczki parowania', () async {
    final pc = await cg.X25519().newKeyPair();
    final pub = await pc.extractPublicKey();
    final sealed = await StoreCrypto.sealTo(
        StoreCrypto.pubFromHex(StoreCrypto.pubHex(pub)), Uint8List.fromList(utf8.encode('x')),
        label: label, extra: const []);

    expect(
      () => StoreCrypto.openSealed(sealed, pc, label: 'sensmos:store:dek:v1'),
      throwsA(anything),
    );
  });
}
