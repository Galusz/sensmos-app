import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme.dart';
import 'l10n.dart';
import 'services/push_service.dart';
import 'services/wallet_service.dart';
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
  // Skrzynka powiadomień (decyzja 2026-08-25): push nie znika po kilku sekundach —
  // dzwoneczek wisi na wierzchu ekranu, klik pokazuje treści. Ostatnie 20 w prefsach.
  final List<Map<String, dynamic>> _inbox = [];
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _loadInbox();
    // Po wejściu do panelu zarejestruj token FCM w BE podpisem walleta (fire-and-forget).
    // Przebudowa 2026-08-24: tokeny mieszkają w BE, nie na nodach — dzięki temu BE umie
    // powiadomić także o MARTWYM nodzie (LoRa awaryjne), a rotacja tokenu nie wymaga LAN.
    final push = context.read<PushService>();
    final wallet = context.read<WalletService>();
    push.init().then((t) {
      if (t != null) push.registerToBackend(wallet);
    });
    try {
      _fcmSub = FirebaseMessaging.onMessage.listen(_onPush);
    } catch (_) {}
  }

  @override
  void dispose() {
    _fcmSub?.cancel();
    super.dispose();
  }

  Future<void> _loadInbox() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('push_inbox');
      if (raw != null) {
        _inbox.addAll(List<Map<String, dynamic>>.from(jsonDecode(raw)));
      }
      _unread = p.getInt('push_unread') ?? 0;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveInbox() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('push_inbox', jsonEncode(_inbox));
      await p.setInt('push_unread', _unread);
    } catch (_) {}
  }

  void _onPush(RemoteMessage m) {
    final title = m.notification?.title ?? '';
    final body  = m.notification?.body ?? '';
    if (title.isEmpty && body.isEmpty) return;
    setState(() {
      _inbox.insert(0, {
        't': title, 'b': body, 'ts': DateTime.now().millisecondsSinceEpoch,
      });
      while (_inbox.length > 20) _inbox.removeLast();
      _unread++;
    });
    _saveInbox();
  }

  String _agoTs(int ts) {
    final s = (DateTime.now().millisecondsSinceEpoch - ts) ~/ 1000;
    if (s < 60) return tr('przed chwilą');
    if (s < 3600) return '${s ~/ 60}m';
    if (s < 86400) return '${s ~/ 3600}h';
    return '${s ~/ 86400}d';
  }

  void _openInbox() {
    setState(() => _unread = 0);
    _saveInbox();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
            child: Row(children: [
              const Icon(Icons.notifications, color: AppTheme.teal, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('Powiadomienia'),
                    style: const TextStyle(
                        color: AppTheme.text, fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              if (_inbox.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() => _inbox.clear());
                    _saveInbox();
                    Navigator.pop(ctx);
                  },
                  child: Text(tr('Wyczyść'),
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                ),
            ]),
          ),
          if (_inbox.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(tr('Brak powiadomień'),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: _inbox.length,
                separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 12),
                itemBuilder: (_, i) {
                  final n = _inbox[i];
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(n['t'] ?? '',
                            style: const TextStyle(
                                color: AppTheme.text, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Text(_agoTs(n['ts'] ?? 0),
                          style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                    ]),
                    if ((n['b'] ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(n['b'],
                            style: const TextStyle(
                                color: AppTheme.muted, fontSize: 12, height: 1.4)),
                      ),
                  ]);
                },
              ),
            ),
        ]),
      ),
    );
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
      body: Stack(children: [
        IndexedStack(index: _index, children: _screens),
        // Dzwoneczek na wierzchu — teal z licznikiem gdy są nieprzeczytane, przygaszony
        // gdy skrzynka ma tylko przeczytane; klik = skrzynka z treściami.
        if (_unread > 0 || _inbox.isNotEmpty)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: Material(
              color: AppTheme.card,
              shape: CircleBorder(side: BorderSide(
                  color: _unread > 0 ? AppTheme.teal : AppTheme.border, width: 1)),
              elevation: 6,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _openInbox,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Stack(clipBehavior: Clip.none, children: [
                    Icon(_unread > 0 ? Icons.notifications_active : Icons.notifications_none,
                        color: _unread > 0 ? AppTheme.teal : AppTheme.muted, size: 22),
                    if (_unread > 0)
                      Positioned(
                        right: -4, top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                              color: AppTheme.red, borderRadius: BorderRadius.circular(8)),
                          child: Text('$_unread',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
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
