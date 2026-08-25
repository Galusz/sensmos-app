import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../../services/push_service.dart';
import '../../services/wallet_service.dart';

/// Powiadomienia — token FCM rejestrowany w SENSMOS podpisem walleta (przebudowa
/// 2026-08-24). Jedna rejestracja obsługuje wszystkie nody właściciela; działa też
/// alert o padzie noda (LoRa awaryjne), którego martwy node sam by nie wysłał.
class PushScreen extends StatefulWidget {
  const PushScreen({super.key});

  @override
  State<PushScreen> createState() => _PushScreenState();
}

class _PushScreenState extends State<PushScreen> {
  bool _busy = false;
  String? _result;

  @override
  Widget build(BuildContext context) {
    final push = context.read<PushService>();
    final token = push.token ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(tr('Powiadomienia'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _infoBanner(),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(
                  push.registered
                      ? Icons.notifications_active
                      : (token.isEmpty
                          ? Icons.notifications_off_outlined
                          : Icons.notifications_none),
                  color: push.registered ? AppTheme.teal : AppTheme.muted),
              title: Text(
                  push.registered
                      ? tr('Zarejestrowane w SENSMOS')
                      : (token.isEmpty
                          ? tr('Brak tokenu FCM (usługi Google niedostępne?)')
                          : tr('Niezarejestrowane')),
                  style: const TextStyle(color: AppTheme.text, fontSize: 14)),
              subtitle: token.isEmpty
                  ? null
                  : Text('${token.substring(0, token.length > 24 ? 24 : token.length)}…',
                      style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 11,
                          fontFamily: 'monospace')),
              trailing: token.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.copy, color: AppTheme.muted, size: 18),
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: token)),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.teal,
                padding: const EdgeInsets.symmetric(vertical: 13)),
            onPressed: _busy || token.isEmpty ? null : _register,
            icon: const Icon(Icons.sync, color: Colors.black, size: 18),
            label: Text(_busy ? tr('Rejestrowanie...') : tr('Zarejestruj ponownie'),
                style: const TextStyle(color: Colors.black)),
          ),
          if (_result != null) ...[
            const SizedBox(height: 10),
            Text(_result!,
                style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Future<void> _register() async {
    setState(() { _busy = true; _result = null; });
    final ok = await context
        .read<PushService>()
        .registerToBackend(context.read<WalletService>());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = ok
          ? tr('Token zarejestrowany — powiadomienia aktywne na tym urządzeniu.')
          : tr('Rejestracja nie powiodła się — sprawdź internet i spróbuj ponownie.');
    });
  }

  Widget _infoBanner() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppTheme.amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.amber.withValues(alpha: 0.3))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: AppTheme.amber, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr('Powiadomienia rejestrują się automatycznie przy starcie aplikacji — '
                    'jedna rejestracja obejmuje wszystkie Twoje nody (akcje skryptów, '
                    'wiadomości, alarm o utracie łączności przez LoRa). '
                    'Wyłączysz je w systemowych ustawieniach powiadomień.'),
                style: const TextStyle(color: AppTheme.text, fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      );
}
