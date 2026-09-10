import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as cg;
import 'package:flutter_test/flutter_test.dart';
import 'package:sensmos_store/sensmos_store.dart';

/// Skrzynka właściciela: pakuje każdy, otwiera wyłącznie właściciel.
/// Bez tego testu nie da się odróżnić działającego pakowania od takiego, które zwraca śmieci —
/// a błąd wyszedłby dopiero przy próbie odzyskania pliku, czyli najgorzej jak można.
void main() {
  final sig  = Uint8List.fromList(List.generate(65, (i) => i));
  final sig2 = Uint8List.fromList(List.generate(65, (i) => i + 1));

  test('ta sama sygnatura daje tę samą skrzynkę', () async {
    final a = await (await StoreCrypto.boxKeyPair(sig)).extractPublicKey();
    final b = await (await StoreCrypto.boxKeyPair(sig)).extractPublicKey();
    expect(StoreCrypto.pubHex(a), StoreCrypto.pubHex(b));
    final c = await (await StoreCrypto.boxKeyPair(sig2)).extractPublicKey();
    expect(StoreCrypto.pubHex(a), isNot(StoreCrypto.pubHex(c)));
  });

  test('pakowanie i odpakowanie klucza pliku', () async {
    final box = await StoreCrypto.boxKeyPair(sig);
    final pub = await box.extractPublicKey();
    final dek = StoreCrypto.randomBytes(32);
    final wrapped = await StoreCrypto.wrapDek(dek, pub);
    expect((jsonDecode(wrapped) as Map).containsKey('x'), isTrue);
    expect(await StoreCrypto.unwrapDek(wrapped, box), dek);
  });

  test('klucz publiczny przenosi się przez hex', () async {
    final box = await StoreCrypto.boxKeyPair(sig);
    final pub = await box.extractPublicKey();
    final dek = StoreCrypto.randomBytes(32);
    // Tak dostanie go serwer i archiwizator: sam ciąg znaków, nic więcej.
    final wrapped = await StoreCrypto.wrapDek(dek, StoreCrypto.pubFromHex(StoreCrypto.pubHex(pub)));
    expect(await StoreCrypto.unwrapDek(wrapped, box), dek);
  });

  test('cudza skrzynka nie otwiera', () async {
    final mine = await StoreCrypto.boxKeyPair(sig);
    final other = await StoreCrypto.boxKeyPair(sig2);
    final wrapped = await StoreCrypto.wrapDek(StoreCrypto.randomBytes(32), await mine.extractPublicKey());
    expect(() => StoreCrypto.unwrapDek(wrapped, other), throwsA(anything));
  });

  test('każde pakowanie inne, choć klucz ten sam', () async {
    final pub = await (await StoreCrypto.boxKeyPair(sig)).extractPublicKey();
    final dek = StoreCrypto.randomBytes(32);
    expect(await StoreCrypto.wrapDek(dek, pub), isNot(await StoreCrypto.wrapDek(dek, pub)));
  });

  test('nazwa idzie kluczem pliku', () {
    final dek = StoreCrypto.randomBytes(32);
    final enc = StoreCrypto.encryptName(dek, 'zdjęcia z wakacji.zip');
    expect(StoreCrypto.decryptName(dek, enc), 'zdjęcia z wakacji.zip');
    expect(StoreCrypto.decryptName(StoreCrypto.randomBytes(32), enc), '?');
  });

  test('treść podpisu rekordu jest jednoznaczna', () {
    final p = StoreCrypto.metaPayload(v: 1, oid: 'ab' * 12, owner: 'cd' * 32, size: 5,
        sha256hex: 'ef' * 32, blocks: ['11' * 32, '22' * 32],
        createdAt: '2026-09-09T10:00:00.000Z', wrappedKey: 'WK', nameEnc: 'NE');
    expect(p.split('|').length, 9);
    expect(p.startsWith('sensmos:store:meta:v1|'), isTrue);
  });
}
