import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as c;
import 'package:pointycastle/export.dart';

/// Szyfrowanie tunelu (v2) — musi być bajt w bajt zgodne z FW `src/tunnel.cpp`.
///
/// Po co: do 1.00 bajty tunelu szły przez BE jawnie (base64 w JSON-ie). Dla SSH nie miało to
/// znaczenia — BE widział szyfrogram SSH — ale panel HA i panele LAN to zwykły HTTP, więc przez
/// serwer przechodził token HA i treść stron. Klucz parowania powstaje w telefonie i jedzie do
/// noda WYŁĄCZNIE po LAN, więc BE go nie zna i poznać nie może: idealny materiał na klucz sesji.
///
/// Ramka: `[seq u64 BE][nonce 12][ciphertext][tag 16]` — narzut 36 B na porcję 1 KB (+3,5%).
///
/// Nonce jest LOSOWY, nie licznikowy. Klucz sesji wyprowadza się z klucza parowania, więc jest
/// TEN SAM we wszystkich sesjach i po restarcie noda; licznik od zera powtórzyłby parę
/// (klucz, nonce), a w GCM powtórka kompromituje klucz uwierzytelniania. 96 bitów losowości
/// daje granicę urodzinową ~2^48 porcji — nieosiągalną przy 100 porcjach na sekundę.
///
/// `seq` jest jawny i wchodzi do AAD: chroni przed powtórzeniem i przestawieniem porcji przez
/// serwer. Odbiorca wymaga ściśle rosnącego; dziury są dozwolone, bo porcja mogła zginąć przy
/// backpressure i zostać zaszyfrowana od nowa z kolejnym numerem.
class TunnelCrypto {
  static const int seqLen = 8, nonceLen = 12, tagLen = 16;
  static const int overhead = seqLen + nonceLen + tagLen;   // 36
  static const int dirToApp = 0;   // node → apka
  static const int dirToLan = 1;   // apka → node

  final Uint8List _key;            // 32 B — AES-256
  final int _ts;                   // znacznik z `open`, wchodzi do AAD
  final _rnd = Random.secure();
  int _seqTx = 0;
  int _seqRx = -1;

  TunnelCrypto._(this._key, this._ts);

  /// Klucz sesji = SHA256(klucz_parowania ‖ "sensmos-tun-v2"). Liczony lokalnie po obu
  /// stronach, nic się nie wymienia. Etykieta oddziela go od HMAC-a dowodu przy otwarciu —
  /// ten sam sekret, dwa zastosowania, zero wspólnych stanów.
  factory TunnelCrypto(Uint8List pairKey, int ts) {
    final k = c.sha256.convert([...pairKey, ...'sensmos-tun-v2'.codeUnits]).bytes;
    return TunnelCrypto._(Uint8List.fromList(k), ts);
  }

  Uint8List _aad(int dir, int seq) {
    final b = BytesBuilder();
    b.add('tun2'.codeUnits);
    b.add(_u32(_ts));
    b.addByte(dir);
    b.add(_u64(seq));
    return b.toBytes();
  }

  static Uint8List _u32(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.big);
  static Uint8List _u64(int v) =>
      Uint8List(8)..buffer.asByteData().setUint64(0, v, Endian.big);

  GCMBlockCipher _gcm(bool encrypt, Uint8List nonce, Uint8List aad) =>
      GCMBlockCipher(AESEngine())
        ..init(encrypt, AEADParameters(KeyParameter(_key), tagLen * 8, nonce, aad));

  /// Bajty do noda → gotowa ramka.
  Uint8List seal(Uint8List plain) {
    final seq = _seqTx++;
    final nonce = Uint8List.fromList(List<int>.generate(nonceLen, (_) => _rnd.nextInt(256)));
    final body = _gcm(true, nonce, _aad(dirToLan, seq)).process(plain);   // ct ‖ tag
    return Uint8List.fromList([..._u64(seq), ...nonce, ...body]);
  }

  /// Ramka od noda → bajty do LAN-u. Rzuca przy złym tagu albo powtórzonym `seq` —
  /// wołający MUSI wtedy zerwać sesję, a nie zignorować porcję: cicha dziura w strumieniu
  /// i tak zabije SSH na MAC-u, a w panelu HTTP zostawi uciętą odpowiedź.
  Uint8List open(Uint8List frame) {
    if (frame.length <= overhead) throw StateError('tunnel frame too short');
    final seq = ByteData.sublistView(frame, 0, seqLen).getUint64(0, Endian.big);
    if (seq <= _seqRx) throw StateError('tunnel frame replayed or reordered');
    final nonce = Uint8List.sublistView(frame, seqLen, seqLen + nonceLen);
    final body  = Uint8List.sublistView(frame, seqLen + nonceLen);
    final plain = _gcm(false, nonce, _aad(dirToApp, seq)).process(body);
    _seqRx = seq;
    return plain;
  }
}
