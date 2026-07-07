import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../../core/core_bloc.dart';
import '../../core/core_event.dart';
import '../../services/wallet_service.dart';
import '../node/node_manager_screen.dart';

/// Ekran powitalny (welcome). Nowy start (dodaj node) — albo, jeśli już
/// korzystałeś z SENSMOS: wyszukaj swoje nody w WiFi lub zaimportuj portfel.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  void _openNodeManager(BuildContext context, int tab) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => NodeManagerScreen(initialTab: tab)));
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
    // Wszystko wyłuskane PRZED await; WalletImported (przełącza ekran → dispose) na końcu.
    final ws = context.read<WalletService>();
    final messenger = ScaffoldMessenger.of(context);
    final bloc = context.read<CoreBloc>();
    try {
      final w = await ws.restore(pk);
      messenger.showSnackBar(SnackBar(content: Text(
          tr('Portfel zaimportowany: %s',
             ['${w.address.substring(0,6)}…${w.address.substring(w.address.length-4)}']))));
      bloc.add(WalletImported());
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const Text('SENSMOS',
                  style: TextStyle(
                      color: AppTheme.teal,
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4)),
              const SizedBox(height: 12),
              Text(tr('Twoje urządzenia. Twoje dane. Twoja sieć.'),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 15)),
              const SizedBox(height: 40),
              _bullet(Icons.sensors, tr('Podłącz czujnik i monitoruj okolicę')),
              _bullet(Icons.lan_outlined, tr('Monitoruj sieć i internet')),
              _bullet(Icons.swap_horiz, tr('Wymieniaj dane z sąsiadami')),
              _bullet(Icons.notifications_active, tr('Alerty na telefon')),
              const SizedBox(height: 32),

              // ── Nowy start ──
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openNodeManager(context, 0),
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

              const SizedBox(height: 28),
              Row(children: [
                const Expanded(child: Divider(color: AppTheme.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(tr('Korzystałeś już z SENSMOS?'),
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                ),
                const Expanded(child: Divider(color: AppTheme.border)),
              ]),
              const SizedBox(height: 16),

              // ── Powracający ──
              _secondary(
                icon: Icons.wifi_find,
                label: tr('Wyszukaj moje nody w sieci WiFi'),
                onTap: () => _openNodeManager(context, 1),
              ),
              const SizedBox(height: 12),
              _secondary(
                icon: Icons.download_outlined,
                label: tr('Importuj portfel'),
                onTap: () => _importWallet(context),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _secondary(
          {required IconData icon, required String label, required VoidCallback onTap}) =>
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.text,
            side: const BorderSide(color: AppTheme.border),
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.centerLeft,
          ),
          icon: Icon(icon, size: 20, color: AppTheme.muted),
          label: Text(label, style: const TextStyle(fontSize: 14)),
        ),
      );

  Widget _bullet(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Icon(icon, color: AppTheme.purple, size: 22),
          const SizedBox(width: 14),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: AppTheme.text, fontSize: 14))),
        ]),
      );
}
