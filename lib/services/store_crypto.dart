import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show RootIsolateToken;
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cg;
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter/services.dart' show BackgroundIsolateBinaryMessenger;
import 'package:pointycastle/export.dart';

/// Szyfrowanie Store — wszystko dzieje się na telefonie, serwer i sprzedawcy widzą szyfrogram.
///
/// Klucz główny (KEK) NIE jest nigdzie zapisany: wyprowadzany na żądanie z podpisu portfela nad
/// stałym komunikatem `sensmos:store:v1`. Podpis secp256k1 w web3dart jest deterministyczny
/// (RFC 6979, sprawdzone tool/sig_det.dart), więc ten sam portfel = ten sam klucz, na każdym
/// urządzeniu. Ledger podpisuje tak samo — to ten sam interfejs, inny podpisujący.
///
/// Każdy plik ma własny losowy klucz (DEK), zapakowany kluczem głównym. Portfel JEST kluczem:
/// jego zaszyfrowana kopia leży na nodzie (odzysk po PIN), osobnej ścieżki odzyskiwania nie ma.
///
/// Układ szyfrogramu:  [sól 8 B][ramka…]  ramka = AES-256-GCM(DEK, nonce = sól‖nr, aad = nr)
/// nad ≤1 MiB jawnego tekstu, czyli ≤1 MiB + 16 B tagu. Nonce z licznika: żadnej powtórki
/// w obrębie pliku, sól losowa per plik. AAD z numerem ramki blokuje przestawianie ramek.
///
/// Ramki pliku liczy NATYWNE AES systemu (cryptography_flutter: na Androidzie javax.crypto,
/// sprzętowe) — czysty Dart robił kilka MB/s i film szyfrował się minutami. Drobiazgi (klucz
/// pliku, nazwa) zostają w pointycastle: są małe i potrzebują synchronicznego API w build().
/// Ten sam algorytm i układ bajtów, więc pliki wgrane wcześniej otwierają się bez zmian.
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

  /// Klucz pliku zapakowany kluczem głównym → JSON {"k": …}.
  static String wrapDek(Uint8List dek, Uint8List kek) => jsonEncode({'k': seal(kek, dek, aad: 'dek')});

  static Uint8List unwrapDek(String wrapped, Uint8List kek) =>
      open(kek, (jsonDecode(wrapped) as Map)['k'] as String, aad: 'dek');

  static String encryptName(Uint8List kek, String name) =>
      seal(kek, Uint8List.fromList(utf8.encode(name)), aad: 'name');
  static String decryptName(Uint8List kek, String? enc) {
    if (enc == null || enc.isEmpty) return '';
    try { return utf8.decode(open(kek, enc, aad: 'name')); } catch (_) { return '?'; }
  }

  // ── strumień pliku ──
  static int cipherSize(int plain) => plain <= 0 ? saltLen : saltLen + plain + tag * ((plain + chunk - 1) ~/ chunk);

  static Uint8List _nonce(Uint8List salt, int idx) {
    final n = Uint8List(nonceLen)..setRange(0, saltLen, salt);
    ByteData.view(n.buffer).setUint32(saltLen, idx);
    return n;
  }
  static Uint8List _aad(int idx) => Uint8List(4)..buffer.asByteData().setUint32(0, idx);

  static final _aes = cg.AesGcm.with256bits(nonceLength: nonceLen);

  /// Szyfruje plik spod `srcPath` do pliku tymczasowego. Zwraca (ścieżka szyfrogramu, skróty
  /// bloków 10 MiB hex). Dwa przebiegi: najpierw szyfr na dysk, potem skróty — bo `put` musi
  /// znać skróty ZANIM wyśle pierwszy bajt, a plik może być większy niż pamięć telefonu.
  ///
  /// Pracuje na ŚCIEŻKACH, nie na strumieniach, żeby dało się ją odpalić w `Isolate.run`.
  static Future<(String, List<String>)> encryptPathToTemp(String srcPath, Uint8List dek) async {
    final dir = await Directory.systemTemp.createTemp('sensmos-store-');
    final out = File('${dir.path}/enc.bin');
    final sink = out.openWrite();
    final salt = randomBytes(saltLen);
    sink.add(salt);
    final key = cg.SecretKey(dek);
    final src = await File(srcPath).open();
    var idx = 0;
    try {
      final total = await src.length();
      for (var off = 0; off < total; off += chunk) {
        final plain = await src.read(min(chunk, total - off));
        final box = await _aes.encrypt(plain, secretKey: key, nonce: _nonce(salt, idx), aad: _aad(idx));
        sink.add(box.cipherText);
        sink.add(box.mac.bytes);
        idx++;
      }
    } finally { await src.close(); }
    await sink.close();
    return (out.path, await blockHashes(out));
  }

  /// Izolat Z TEGO miejsca, nie z ekranu: domknięcie utworzone w metodzie State łapie `this`
  /// (State jest nieprzesyłalny → „object is unsendable"). Natywne AES idzie kanałem do
  /// platformy, a kanał w izolacie tła trzeba najpierw zarejestrować tokenem izolatu głównego.
  static Future<(String, List<String>)> encryptInIsolate(String srcPath, Uint8List dek) {
    final token = RootIsolateToken.instance!;
    return Isolate.run(() { _initIsolate(token); return encryptPathToTemp(srcPath, dek); });
  }
  static Future<Uint8List> decryptInIsolate(String encPath, Uint8List dek) {
    final token = RootIsolateToken.instance!;
    return Isolate.run(() { _initIsolate(token); return decryptPath(encPath, dek); });
  }
  static void _initIsolate(RootIsolateToken token) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    FlutterCryptography.enable();
  }

  static Future<List<String>> blockHashes(File f) async {
    final raf = await f.open();
    final out = <String>[];
    final h = cg.Sha256();
    try {
      final total = await raf.length();
      for (var off = 0; off < total; off += block) {
        await raf.setPosition(off);
        final d = await h.hash(await raf.read(min(block, total - off)));
        out.add(d.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join());
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
    final key = cg.SecretKey(dek);
    final out = BytesBuilder(copy: false);
    var off = saltLen, idx = 0;
    while (off < data.length) {
      final n = min(frame, data.length - off);
      if (n <= tag) throw const FormatException('truncated frame');
      final box = cg.SecretBox(Uint8List.sublistView(data, off, off + n - tag),
          nonce: _nonce(salt, idx), mac: cg.Mac(Uint8List.sublistView(data, off + n - tag, off + n)));
      out.add(await _aes.decrypt(box, secretKey: key, aad: _aad(idx)));
      off += n; idx++;
    }
    return out.takeBytes();
  }
}
