import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../../core/core_bloc.dart';
import '../../core/core_event.dart';
import '../../services/wallet_service.dart';
import '../node/node_manager_screen.dart';

/// Ekran powitalny (welcome). Dwie sciezki: dodaj node (tworzy nowy portfel
/// przy pierwszym nodzie) albo zaimportuj istniejacy portfel (np. z MetaMask).
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  void _addNode(BuildContext context) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const NodeManagerScreen()));
  }

  Future<void> _importWallet(BuildContext context) async {
    final ctrl = TextEditingController();
    final pk = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Importuj portfel'),
            style: const TextStyle(color: AppTheme.text)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Wklej klucz prywatny (np. z MetaMask). Rób to tylko na swoim telefonie.'),
              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          const SizedBox(height: 10),
          TextField(controller: ctrl, autofocus: true, maxLines: 2,
            style: const TextStyle(color: AppTheme.text, fontSize: 13, fontFamily: 'monospace'),
            decoration: const InputDecoration(hintText: '0x…',
                hintStyle: TextStyle(color: AppTheme.muted))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Anuluj'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.teal),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(tr('Importuj'), style: const TextStyle(color: Colors.black))),
        ],
      ),
    );
    if (pk == null || pk.isEmpty) return;
    final ws = context.read<WalletService>();
    final messenger = ScaffoldMessenger.of(context);
    final bloc = context.read<CoreBloc>();
    try {
      final w = await ws.restore(pk);
      bloc.add(WalletImported());
      messenger.showSnackBar(SnackBar(content: Text(
          tr('Portfel zaimportowany: %s',
             ['${w.address.substring(0,6)}…${w.address.substring(w.address.length-4)}']))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
          content: Text(tr('Nieprawidłowy klucz prywatny')),
          backgroundColor: const Color(0xFFFF4444)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Text('SENSMOS',
                  style: TextStyle(
                      color: AppTheme.teal,
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4)),
              const SizedBox(height: 12),
              Text(tr('Twoje urządzenia. Twoje dane. Twoja sieć.'),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 15)),
              const SizedBox(height: 48),
              _bullet(Icons.sensors, tr('Podłącz czujnik i monitoruj okolicę')),
              _bullet(Icons.swap_horiz, tr('Wymieniaj dane z sąsiadami')),
              _bullet(Icons.notifications_active, tr('Alerty na telefon')),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _addNode(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.teal,
                    foregroundColor: AppTheme.bg,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(tr('Dodaj node'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 4),
              Text(tr('tworzy nowy portfel'),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                  textAlign: TextAlign.center),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _importWallet(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.text,
                    side: const BorderSide(color: AppTheme.border),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.download_outlined),
                  label: Text(tr('Importuj portfel'),
                      style: const TextStyle(fontSize: 15)),
                ),
              ),
              const SizedBox(height: 8),
              Text(tr('masz już portfel (np. w MetaMask)? odzyskaj dostęp do swoich nodów'),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bullet(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Icon(icon, color: AppTheme.purple, size: 22),
          const SizedBox(width: 14),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: AppTheme.text, fontSize: 14))),
        ]),
      );
}
