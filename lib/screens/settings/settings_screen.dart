import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../l10n.dart';
import 'nodes_location_screen.dart';
import 'push_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Ustawienia'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Nody
          _section(tr('Nody')),
          Card(child: Column(children: [
            _tile(
              context,
              icon: Icons.location_on_outlined,
              title: tr('Lokalizacja nodów'),
              sub: tr('współrzędne wszystkich urządzeń'),
              builder: (_) => const NodesLocationScreen(),
            ),
            const Divider(color: AppTheme.border, height: 1),
            _tile(
              context,
              icon: Icons.notifications_outlined,
              title: tr('Powiadomienia'),
              sub: tr('token push, włącz/wyłącz na nodach'),
              builder: (_) => const PushScreen(),
            ),
          ])),

          const SizedBox(height: 16),

          // Aplikacja
          _section(tr('Aplikacja')),
          Card(child: Column(children: [
            ListTile(
              leading: const Icon(Icons.info_outline, color: AppTheme.muted),
              title: Text(tr('Wersja'), style: const TextStyle(color: AppTheme.text)),
              trailing: const Text('1.2.3',
                  style: TextStyle(color: AppTheme.muted, fontSize: 13)),
            ),
            const Divider(color: AppTheme.border, height: 1),
            const ListTile(
              leading: Icon(Icons.code, color: AppTheme.muted),
              title: Text('Sensmos Network',
                  style: TextStyle(color: AppTheme.text)),
              subtitle: Text('sensmos.com',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12)),
            ),
          ])),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String sub,
    required WidgetBuilder builder,
  }) =>
      ListTile(
        leading: Icon(icon, color: AppTheme.teal),
        title: Text(title, style: const TextStyle(color: AppTheme.text)),
        subtitle: Text(sub,
            style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.muted),
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: builder)),
      );

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label.toUpperCase(),
            style: const TextStyle(
                color: AppTheme.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1)),
      );
}
