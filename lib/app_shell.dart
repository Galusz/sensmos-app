import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'theme.dart';
import 'l10n.dart';
import 'services/push_service.dart';
import 'services/node_service.dart';
import 'screens/nodes/nodes_screen.dart';
import 'screens/wallet/wallet_screen.dart';
import 'screens/settings/settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  StreamSubscription? _fcmSub;
  OverlayEntry? _bell;
  Timer? _bellTimer;

  @override
  void initState() {
    super.initState();
    // Po wejściu do panelu rozprowadź token FCM na nody (fire-and-forget)
    final push = context.read<PushService>();
    final nodes = context.read<NodeService>();
    push.init().then((t) {
      if (t != null) push.syncToNodes(nodes);
    });
    // Powiadomienie gdy apka na pierwszym planie → dzwoneczek (treść jest w skrzynce)
    try {
      _fcmSub = FirebaseMessaging.onMessage.listen((_) => _showBell());
    } catch (_) {}
  }

  @override
  void dispose() {
    _fcmSub?.cancel();
    _bellTimer?.cancel();
    _bell?.remove();
    super.dispose();
  }

  void _showBell() {
    _bellTimer?.cancel();
    _bell?.remove();
    final top = MediaQuery.of(context).padding.top + 8;
    _bell = OverlayEntry(
      builder: (_) => Positioned(
        top: top,
        right: 12,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.teal.withValues(alpha: 0.4)),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.notifications_active, color: AppTheme.teal, size: 20),
              const SizedBox(width: 10),
              Text(tr('Nowe powiadomienie\nsprawdź skrzynkę noda'),
                  style: const TextStyle(color: AppTheme.text, fontSize: 12, height: 1.3)),
            ]),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_bell!);
    _bellTimer = Timer(const Duration(seconds: 4), () {
      _bell?.remove();
      _bell = null;
    });
  }

  final _screens = const [
    NodesScreen(),
    WalletScreen(),
    SettingsScreen(),
  ];

  final _items = const [
    (Icons.sensors_outlined, Icons.sensors, 'Nody'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'Portfel'),
    (Icons.settings_outlined, Icons.settings, 'Ustawienia'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppTheme.surface,
        indicatorColor: AppTheme.teal.withValues(alpha: 0.15),
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _items.map((e) => NavigationDestination(
          icon:         Icon(e.$1, color: AppTheme.muted),
          selectedIcon: Icon(e.$2, color: AppTheme.teal),
          label: tr(e.$3),
        )).toList(),
      ),
    );
  }
}
