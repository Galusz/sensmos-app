import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// Szyfrowanie Store — wszystko dzieje się na telefonie, serwer i sprzedawcy widzą szyfrogram.
///
/// Klucz główny (KEK) NIE jest nigdzie zapisany: wyprowadzany na żądanie z podpisu portfela nad
/// stałym komunikatem `sensmos:store:v1`. Podpis secp256k1 w web3dart jest deterministyczny
/// (RFC 6979, sprawdzone tool/sig_det.dart), więc ten sam portfel = ten sam klucz, na każdym
/// urządzeniu. Ledger podpisuje tak samo — to ten sam interfejs, inny podpisujący.
///
/// Każdy plik ma własny losowy klucz (DEK), zapakowany DWA razy: kluczem głównym i kluczem
/// odzyskiwania (24 słowa BIP39 pokazane raz). Utrata portfela ≠ utrata plików, jeśli są słowa.
///
/// Układ szyfrogramu:  [sól 8 B][ramka…]  ramka = AES-256-GCM(DEK, nonce = sól‖nr, aad = nr)
/// nad ≤1 MiB jawnego tekstu, czyli ≤1 MiB + 16 B tagu. Nonce z licznika: żadnej powtórki
/// w obrębie pliku, sól losowa per plik. AAD z numerem ramki blokuje przestawianie ramek.
class StoreCrypto {
  static const int chunk = 1024 * 1024;       // jawny tekst na ramkę
  static const int tag = 16, nonceLen = 12, saltLen = 8;
  static const int frame = chunk + tag;       // ramka szyfrogramu
  static const int block = 10 * 1024 * 1024;  // blok dowodowy backendu (skróty nad szyfrogramem)

  static final _rng = Random.secure();
  static Uint8List randomBytes(int n) => Uint8List.fromList(List.generate(n, (_) => _rng.nextInt(256)));

  // ── klucz główny z podpisu ──
  static Uint8List kekFromSignature(Uint8List sig) =>
      _hkdf(Uint8List.fromList(sha256.convert(sig).bytes), utf8.encode('sensmos:store:kek:v1'), 32);

  static Uint8List _hkdf(Uint8List ikm, List<int> info, int len) {
    final prk = Hmac(sha256, List.filled(32, 0)).convert(ikm).bytes;      // extract, sól zerowa
    final out = <int>[]; var t = <int>[]; var i = 1;
    while (out.length < len) {
      t = Hmac(sha256, prk).convert([...t, ...info, i++]).bytes;             // expand
      out.addAll(t);
    }
    return Uint8List.fromList(out.sublist(0, len));
  }

  // ── AES-256-GCM na małych rzeczach (klucze, nazwy) ──
  static GCMBlockCipher _gcm(bool enc, Uint8List key, Uint8List nonce, Uint8List aad) =>
      GCMBlockCipher(AESEngine())..init(enc, AEADParameters(KeyParameter(key), tag * 8, nonce, aad));

  /// base64( nonce ‖ szyfrogram ‖ tag )
  static String seal(Uint8List key, Uint8List plain, {String aad = ''}) {
    final nonce = randomBytes(nonceLen);
    final ct = _gcm(true, key, nonce, Uint8List.fromList(utf8.encode(aad))).process(plain);
    return base64Encode([...nonce, ...ct]);
  }

  static Uint8List open(Uint8List key, String sealed, {String aad = ''}) {
    final b = base64Decode(sealed);
    final nonce = Uint8List.fromList(b.sublist(0, nonceLen));
    return _gcm(false, key, nonce, Uint8List.fromList(utf8.encode(aad)))
        .process(Uint8List.fromList(b.sublist(nonceLen)));
  }

  /// Klucz pliku zapakowany dwa razy → JSON {"k": kluczem głównym, "r": kluczem odzyskiwania}.
  static String wrapDek(Uint8List dek, Uint8List kek, Uint8List? recovery) => jsonEncode({
        'k': seal(kek, dek, aad: 'dek'),
        if (recovery != null) 'r': seal(recovery, dek, aad: 'dek'),
      });

  static Uint8List unwrapDek(String wrapped, Uint8List kek) =>
      open(kek, (jsonDecode(wrapped) as Map)['k'] as String, aad: 'dek');

  static String encryptName(Uint8List kek, String name) =>
      seal(kek, Uint8List.fromList(utf8.encode(name)), aad: 'name');
  static String decryptName(Uint8List kek, String? enc) {
    if (enc == null || enc.isEmpty) return '';
    try { return utf8.decode(open(kek, enc, aad: 'name')); } catch (_) { return '?'; }
  }

  // ── kod odzyskiwania: 32 B losowe ↔ 24 słowa BIP39 ──
  static (Uint8List key, String words) newRecovery() {
    final key = randomBytes(32);
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return (key, bip39.entropyToMnemonic(hex));
  }

  static Uint8List recoveryFromWords(String words) {
    final hex = bip39.mnemonicToEntropy(words.trim().toLowerCase().split(RegExp(r'\s+')).join(' '));
    return Uint8List.fromList(List.generate(hex.length ~/ 2, (i) => int.parse(hex.substring(2 * i, 2 * i + 2), radix: 16)));
  }

  // ── strumień pliku ──
  static int cipherSize(int plain) => plain <= 0 ? saltLen : saltLen + plain + tag * ((plain + chunk - 1) ~/ chunk);

  static Uint8List _nonce(Uint8List salt, int idx) {
    final n = Uint8List(nonceLen)..setRange(0, saltLen, salt);
    ByteData.view(n.buffer).setUint32(saltLen, idx);
    return n;
  }
  static Uint8List _aad(int idx) => Uint8List(4)..buffer.asByteData().setUint32(0, idx);

  /// Szyfruje plik spod `srcPath` do pliku tymczasowego. Zwraca (ścieżka szyfrogramu, skróty
  /// bloków 10 MiB hex). Dwa przebiegi: najpierw szyfr na dysk, potem skróty — bo `put` musi
  /// znać skróty ZANIM wyśle pierwszy bajt, a plik może być większy niż pamięć telefonu.
  ///
  /// Pracuje na ŚCIEŻKACH, nie na strumieniach, żeby dało się ją odpalić w `Isolate.run`:
  /// AES-GCM w czystym Darcie na wątku głównym zamraża UI (ANR na MIUI już przy zdjęciu).
  static Future<(String, List<String>)> encryptPathToTemp(String srcPath, Uint8List dek) async {
    final dir = await Directory.systemTemp.createTemp('sensmos-store-');
    final out = File('${dir.path}/enc.bin');
    final sink = out.openWrite();
    final salt = randomBytes(saltLen);
    sink.add(salt);
    final src = await File(srcPath).open();
    var idx = 0;
    try {
      final total = await src.length();
      for (var off = 0; off < total; off += chunk) {
        final plain = await src.read(min(chunk, total - off));
        sink.add(_gcm(true, dek, _nonce(salt, idx), _aad(idx)).process(plain));
        idx++;
      }
    } finally { await src.close(); }
    await sink.close();
    return (out.path, await blockHashes(out));
  }

  /// Uruchomienie w izolacie Z TEGO miejsca, nie z ekranu: domknięcie utworzone w metodzie
  /// State łapie kontekst razem z `this` (State jest nieprzesyłalny → „object is unsendable").
  /// Tu jest tylko ścieżka i klucz.
  static Future<(String, List<String>)> encryptInIsolate(String srcPath, Uint8List dek) =>
      Isolate.run(() => encryptPathToTemp(srcPath, dek));
  static Future<Uint8List> decryptInIsolate(String encPath, Uint8List dek) =>
      Isolate.run(() => decryptPath(encPath, dek));

  static Future<List<String>> blockHashes(File f) async {
    final raf = await f.open();
    final out = <String>[];
    try {
      final total = await raf.length();
      for (var off = 0; off < total; off += block) {
        await raf.setPosition(off);
        out.add(sha256.convert(await raf.read(min(block, total - off))).toString());
      }
    } finally { await raf.close(); }
    return out;
  }

  /// Odszyfrowuje plik szyfrogramu do pamięci (pobieranie na telefon — limit rozmiaru pilnuje
  /// ekran). Zły tag = wyjątek, nigdy cicho zepsute dane. Też do `Isolate.run`.
  static Future<Uint8List> decryptPath(String encPath, Uint8List dek) async {
    final data = await File(encPath).readAsBytes();
    if (data.length < saltLen) throw const FormatException('too short');
    final salt = Uint8List.sublistView(data, 0, saltLen);
    final out = BytesBuilder(copy: false);
    var off = saltLen, idx = 0;
    while (off < data.length) {
      final n = min(frame, data.length - off);
      out.add(_gcm(false, dek, _nonce(salt, idx), _aad(idx)).process(Uint8List.sublistView(data, off, off + n)));
      off += n; idx++;
    }
    return out.takeBytes();
  }
}
