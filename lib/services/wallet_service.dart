import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:web3dart/web3dart.dart';
import 'package:web3dart/crypto.dart';
import '../config.dart';
import '../l10n.dart';
import '../models/wallet.dart';

/// WalletService — generowanie, przechowywanie, podpis (opcja C).
/// Klucz w secure storage telefonu (Keychain/Keystore).
/// Backup do ESP NVS robi NodeService osobno.
class WalletService {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Czy wallet już istnieje
  Future<bool> exists() async {
    return await _storage.read(key: Config.kWalletKey) != null;
  }

  /// Wczytaj istniejący wallet
  Future<AppWallet?> load() async {
    final pk = await _storage.read(key: Config.kWalletKey);
    final addr = await _storage.read(key: Config.kWalletAddr);
    if (pk == null || addr == null) return null;
    return AppWallet(address: addr, privateKeyHex: pk);
  }

  /// Stwórz nowy wallet (przy pierwszym uruchomieniu — niewidoczne dla usera)
  Future<AppWallet> create() async {
    final rng = Random.secure();
    final priv = EthPrivateKey.createRandom(rng);
    final addr = priv.address.hexEip55;
    // Kanoniczne 64 hex z liczby klucza. web3dart (encodeBigInt, ze znakiem) zapisuje
    // klucz jako 33 bajty (wiodący 00 gdy najwyższy bit = 1, ~50% przypadków) lub <32
    // (wiodące zero); przez privateKeyInt dostajemy zawsze dokładnie 32 bajty — inaczej
    // MetaMask odrzuca import ("couldn't import that private key").
    final pkHex = priv.privateKeyInt.toRadixString(16).padLeft(64, '0');

    await _storage.write(key: Config.kWalletKey, value: pkHex);
    await _storage.write(key: Config.kWalletAddr, value: addr);

    return AppWallet(address: addr, privateKeyHex: pkHex);
  }

  /// Podpisz wiadomość kluczem walleta (personal_sign)
  Future<String> signMessage(String message) async {
    final pk = await _storage.read(key: Config.kWalletKey);
    if (pk == null) throw Exception('Brak walleta');
    final priv = EthPrivateKey.fromHex(pk);
    final sig = priv.signPersonalMessageToUint8List(
      Uint8List.fromList(message.codeUnits),
    );
    return bytesToHex(sig, include0x: true);
  }

  /// Zapisz wallet z surowego klucza (po recovery z noda)
  // Adres z klucza BEZ zapisu do storage — podglad przed nadpisaniem walleta.
  Future<String> addressOf(String privateKeyHex) async {
    final clean = privateKeyHex.trim();
    var pk = clean.startsWith('0x') ? clean.substring(2) : clean;
    pk = pk.length > 64 ? pk.substring(pk.length - 64) : pk.padLeft(64, '0');
    return EthPrivateKey.fromHex(pk).address.hexEip55;
  }

  Future<AppWallet> restore(String privateKeyHex) async {
    final clean = privateKeyHex.trim();
    var pk = clean.startsWith('0x') ? clean.substring(2) : clean;
    // Normalizuj do 64 hex: obetnij wiodący bajt znaku (00) albo dopełnij zerami.
    pk = pk.length > 64 ? pk.substring(pk.length - 64) : pk.padLeft(64, '0');
    final priv = EthPrivateKey.fromHex(pk);
    final addr = priv.address.hexEip55;
    await _storage.write(key: Config.kWalletKey, value: pk);
    await _storage.write(key: Config.kWalletAddr, value: addr);
    return AppWallet(address: addr, privateKeyHex: pk);
  }

  /// Zaszyfruj klucz prywatny PIN-em noda → blob do kopii na ESP NVS.
  /// blob = base64(salt[16] || iv[12] || ciphertext+tag). AES-GCM, klucz=PBKDF2.
  Future<String?> exportEncrypted(String pin) async {
    final pk = await _storage.read(key: Config.kWalletKey);
    if (pk == null) return null;
    final salt = _randomBytes(16);
    final iv = _randomBytes(12);
    final key = _deriveKey(pin, salt);
    final gcm = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final ct = gcm.process(Uint8List.fromList(utf8.encode(pk)));
    return base64.encode(Uint8List.fromList([...salt, ...iv, ...ct]));
  }

  /// Odszyfruj blob z noda PIN-em i zapisz wallet. Rzuca przy złym PIN-ie.
  Future<AppWallet> importEncrypted(String blob, String pin) async {
    final raw = base64.decode(blob);
    if (raw.length < 28 + 16) throw Exception('Uszkodzona kopia');
    final salt = Uint8List.fromList(raw.sublist(0, 16));
    final iv = Uint8List.fromList(raw.sublist(16, 28));
    final ct = Uint8List.fromList(raw.sublist(28));
    final key = _deriveKey(pin, salt);
    final gcm = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final Uint8List pt;
    try {
      pt = gcm.process(ct); // InvalidCipherText przy złym PIN-ie/tagu
    } catch (_) {
      throw Exception(tr('Błędny PIN lub uszkodzona kopia'));
    }
    return restore(utf8.decode(pt));
  }

  Uint8List _deriveKey(String pin, Uint8List salt) {
    final d = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, 100000, 32));
    return d.process(Uint8List.fromList(utf8.encode(pin)));
  }

  Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  /// Usuń wallet (reset)
  Future<void> wipe() async {
    await _storage.delete(key: Config.kWalletKey);
    await _storage.delete(key: Config.kWalletAddr);
  }
}
