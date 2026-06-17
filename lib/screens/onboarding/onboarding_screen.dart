import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../node/node_manager_screen.dart';

/// Ekran powitalny (welcome). NIE tworzy portfela — portfel powstaje lub
/// jest odzyskiwany dopiero przy dodawaniu noda przez BLE.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  void _connect(BuildContext context) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const NodeManagerScreen()));
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
                  onPressed: () => _connect(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.teal,
                    foregroundColor: AppTheme.bg,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.bluetooth),
                  label: Text(tr('Połącz node'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                tr('Portfel powstaje przy pierwszym nodzie albo jest odzyskiwany '
                'z noda przez Bluetooth.'),
                style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                textAlign: TextAlign.center,
              ),
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
