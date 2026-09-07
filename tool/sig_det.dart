// Czy personal_sign w web3dart jest deterministyczny (RFC 6979)? Ten sam komunikat, ten sam klucz,
// dwa podpisy — musza byc identyczne, inaczej klucz szyfrowania Store nie odtworzy sie.
import 'dart:typed_data';
import 'package:web3dart/web3dart.dart';
import 'package:web3dart/crypto.dart';
void main() {
  final priv = EthPrivateKey.fromHex('0x' + '11' * 32);
  final msg = Uint8List.fromList('sensmos:store:v1'.codeUnits);
  final a = bytesToHex(priv.signPersonalMessageToUint8List(msg));
  final b = bytesToHex(priv.signPersonalMessageToUint8List(msg));
  final c = bytesToHex(EthPrivateKey.fromHex('0x' + '11' * 32).signPersonalMessageToUint8List(msg));
  print('deterministic: ${a == b && b == c}  (${a.substring(0, 16)}…)');
}
