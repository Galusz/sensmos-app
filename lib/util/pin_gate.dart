import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../theme.dart';
import '../l10n.dart';
import '../services/node_service.dart';

/// PIN-gate: otwarcie dostępu do LAN noda (remote access / panel HA) wymaga PIN-u zapisanego
/// przy onboardingu — ochrona na wypadek zgubionego telefonu (złodziej ma apkę+portfel, ale
/// PIN-u nie zna). Brak zapisanego PIN-u (node znany tylko z BE) → przepuszczamy, bo własność
/// pilnuje i tak podpis portfela (tunel owner-only).
///
/// Zwraca true dopiero po POPRAWNYM PIN-ie. Zły PIN → ponawia W dialogu (toast), NIE zamyka —
/// dzięki temu nie ma pętli „error→retry→PIN". Anuluj → false (wołający decyduje: wyjście/status).
Future<bool> confirmNodePin(BuildContext context, String deviceId) async {
  String? expected;
  for (final n in context.read<NodeService>().nodes) {
    if (n.id == deviceId) {
      expected = n.pin;
      break;
    }
  }
  if (expected == null || expected.isEmpty) return true;

  while (true) {
    final ctrl = TextEditingController();
    final entered = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Podaj PIN noda'), style: const TextStyle(color: AppTheme.text)),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(color: AppTheme.text),
          decoration: const InputDecoration(hintText: 'PIN'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: Text(tr('Anuluj'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(tr('OK'))),
        ],
      ),
    );
    if (entered == null) return false; // Anuluj
    if (entered == expected) return true; // OK
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Zły PIN')), duration: const Duration(seconds: 2)));
    }
    // pętla: pokaż dialog ponownie (bez wychodzenia z ekranu)
  }
}
