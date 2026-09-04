import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/node_service.dart';
import '../services/pairing_service.dart';
import '../theme.dart';
import '../l10n.dart';
import 'pin_gate.dart';

/// Zapewnia, że node jest sparowany z TYM telefonem; zwraca klucz albo null.
///
/// Parowanie wymaga bycia w tej samej sieci WiFi co node — i to nie jest niedogodność,
/// tylko sedno mechanizmu. Klucz jedzie do noda kanałem, którego backend nie widzi
/// (lokalne HTTP), więc przejęty serwer nie może go podłożyć ani odczytać, a co za tym
/// idzie — nie otworzy tunelu do cudzego LAN-u.
///
/// Zastępuje dawny przełącznik „remote access" (szedł przez backend, czyli przez tego,
/// przed kim miał chronić).
/// Wynik bramki: klucz, tryb zgodności ze starym firmwarem, albo nic.
class PairAccess {
  /// Klucz parowania. null w trybie zgodności — stare FW nie ma czym go przyjąć.
  final Uint8List? key;

  /// TRYB PRZEJŚCIOWY (do usunięcia ok. miesiąc po wydaniu): node na FW ≤0.81, tunel
  const PairAccess({this.key});

  /// Czy da się otworzyć tunel — kluczem albo po staremu.
  bool get ok => key != null;
}

Future<PairAccess> ensurePaired(BuildContext context, String deviceId) async {
  // NodeService czytamy PRZED pierwszym await — sięganie po BuildContext za async gapem
  // jest niepoprawne (widget mógł już zniknąć) i analizator słusznie to zgłasza.
  SavedNode? node;
  for (final n in context.read<NodeService>().nodes) {
    if (n.id == deviceId) { node = n; break; }
  }

  final svc = PairingService();
  final existing = await svc.keyFor(deviceId);
  if (existing != null) return PairAccess(key: existing);

  if (node == null) {
    if (context.mounted) _toast(context, tr('Nie znam tego noda na tym telefonie.'));
    return const PairAccess();
  }

  if (!context.mounted) return const PairAccess();
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.card,
      title: Text(tr('Sparuj node'), style: const TextStyle(color: AppTheme.text)),
      content: Text(
        tr('Zdalny dostęp wymaga jednorazowego sparowania: telefon zapisze w nodzie tajny klucz, '
           'którego nasz serwer nigdy nie zobaczy. Bez niego nikt — łącznie z nami — nie otworzy '
           'tunelu do Twojej sieci.\n\nMusisz być teraz w tej samej sieci WiFi co node.'),
        style: const TextStyle(color: AppTheme.muted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Anuluj'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sparuj'))),
      ],
    ),
  );
  if (go != true) return const PairAccess();

  if (!context.mounted) return const PairAccess();
  if (!await confirmNodePin(context, deviceId)) return const PairAccess();

  final err = await svc.pair(deviceId, node.ip, node.pin);
  if (!context.mounted) return const PairAccess();
  if (err != null) { _toast(context, err); return const PairAccess(); }   // serwis zwraca już przetłumaczone

  // Tryb zgodności celowo NIE mówi userowi nic innego: z jego punktu widzenia node jest
  // gotowy do pracy, a tego, na jakim firmwarze stoi, i tak sam nie zmieni.
  _toast(context, tr('Node sparowany.'));
  return PairAccess(key: await svc.keyFor(deviceId));
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
