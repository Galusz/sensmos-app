// Kontrola formatu ramki tunelu v2 — uruchamiane ręcznie, nie wchodzi do apki.
//
//   dart run tool/tuncheck.dart                  → wypisuje wektor testowy (JSON)
//   dart run tool/tuncheck.dart --open <hex>     → otwiera ramkę zrobioną przez drugą stronę
//
// Sens: format ma trzy niezależne implementacje (Dart w apce, C w firmware, Node w BE tylko
// dla koperty). Jeśli Dart i Node zgadzają się co do bajta, układ jest jednoznaczny i firmware
// ma się do czego dopasować — a błąd endianu czy kolejności w AAD wychodzi tu, a nie na sprzęcie.
import 'dart:convert';
import 'dart:typed_data';
import '../lib/services/tunnel_crypto.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
Uint8List unhex(String s) => Uint8List.fromList(
    List<int>.generate(s.length ~/ 2, (i) => int.parse(s.substring(i * 2, i * 2 + 2), radix: 16)));

void main(List<String> args) {
  // Deterministyczny klucz parowania, żeby wektor dało się porównać co do bajta.
  final pairKey = Uint8List.fromList(List<int>.generate(32, (i) => i));
  const ts = 1757000000;

  if (args.length == 2 && args[0] == '--open') {
    // Ramka OD NODA (dir=0) — dokładnie ta ścieżka, którą apka czyta na żywo.
    final plain = TunnelCrypto(pairKey, ts).open(unhex(args[1]));
    print('otwarte: ${utf8.decode(plain)}');
    return;
  }

  final plain = Uint8List.fromList(utf8.encode('SSH-2.0-Sensmos test payload'));
  final frame = TunnelCrypto(pairKey, ts).seal(plain);   // dir=1 (apka → LAN)
  print(jsonEncode({
    'pairKey': hex(pairKey),
    'ts': ts,
    'plain': hex(plain),
    'frame': hex(frame),
  }));
}
