import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/owner_token_service.dart';
import '../services/wallet_service.dart';
import '../theme.dart';
import '../l10n.dart';

/// Zapewnia token ownera do tuneli — pyta o hasło portfela najwyżej RAZ.
///
/// Pierwsze wejście w tunel: jeśli portfel jest pod hasłem, pokazujemy jedno okno, wydajemy
/// token i zapisujemy go w bezpiecznym magazynie. Każde następne wejście (także z widgetu
/// na pulpicie) idzie już samym tokenem, przy zamkniętym portfelu.
///
/// Zwraca token albo null, gdy user anulował hasło lub BE odmówił — wtedy ekran spada na
/// starą ścieżkę z podpisem, więc nic nie przestaje działać.
Future<String?> ensureOwnerToken(BuildContext context, String owner, {String? label}) async {
  final wallet = context.read<WalletService>();
  final svc = OwnerTokenService();

  final cached = await svc.cached(owner);
  if (cached != null) return cached;

  // Wydanie wymaga podpisu, więc tu i tylko tu może paść pytanie o hasło.
  if (!await wallet.isUnlocked()) {
    if (!context.mounted) return null;
    final pw = await _askPassword(context);
    if (pw == null || pw.isEmpty) return null;
    try {
      await wallet.unlock(pw);
    } catch (e) {
      if (context.mounted) _toast(context, tr('Błędne hasło portfela.'));
      return null;
    }
  }

  try {
    return await svc.issue(owner, wallet, label: label);
  } catch (e) {
    // Brak tokenu nie jest błędem krytycznym — relay podpisze się po staremu.
    return null;
  }
}

Future<String?> _askPassword(BuildContext context) => showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text(tr('Odblokuj portfel'), style: const TextStyle(color: AppTheme.text, fontSize: 16)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              style: const TextStyle(color: AppTheme.text),
              decoration: InputDecoration(hintText: tr('Podaj hasło, aby odblokować portfel.')),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: 10),
            Text(
              tr('Pytamy ostatni raz: apka zapamięta osobny klucz dostępu do tuneli, więc portfel może zostać zamknięty.'),
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Anuluj'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(tr('Odblokuj'))),
          ],
        );
      },
    );

void _toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
