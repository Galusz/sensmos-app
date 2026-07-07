import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import '../../theme.dart';
import '../../l10n.dart';
import '../../config.dart';
import '../../services/node_service.dart';
import '../../services/wallet_service.dart';
import '../../core/core_bloc.dart';
import '../../core/core_event.dart';
import '../scripts/scripts_screen.dart';
import '../message_actions/message_actions_screen.dart';
import '../messages/messages_screen.dart';
import 'trust_screen.dart';
import 'service_screen.dart';

class NodeConfigScreen extends StatefulWidget {
  final SavedNode node;
  const NodeConfigScreen({super.key, required this.node});

  @override
  State<NodeConfigScreen> createState() => _NodeConfigScreenState();
}

class _NodeConfigScreenState extends State<NodeConfigScreen> {
  String? _city;
  String? _fw;
  String? _pinOverride;

  SavedNode get node => widget.node;
  String get pin => _pinOverride ?? widget.node.pin;
  String get _short =>
      node.id.length > 8 ? '${node.id.substring(0, 8)}...' : node.id;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final res = await http
          .get(Uri.parse('http://${node.ip}/info'))
          .timeout(const Duration(seconds: 4));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _city = j['city'] as String?;
        _fw = (j['version'] ?? j['firmware']) as String?;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Ustawienia noda'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.sensors, color: AppTheme.teal),
              title: Text(_city ?? node.label,
                  style: const TextStyle(color: AppTheme.text)),
              subtitle: Text('$_short · FW ${_fw ?? "?"}',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            ),
          ),
          const SizedBox(height: 12),
          _tile(
            icon: Icons.inbox_outlined,
            title: tr('Odebrane'),
            sub: tr('odebrane wiadomości na nodzie'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => MessagesScreen(ip: node.ip, pin: pin)),
            ),
          ),
          _tile(
            icon: Icons.alt_route,
            title: tr('Akcje'),
            sub: tr('akcje na odebrane wiadomości (webhook, encje)'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => MessageActionsScreen(ip: node.ip, pin: pin)),
            ),
          ),
          _tile(
            icon: Icons.code,
            title: tr('Skrypty'),
            sub: tr('automatyzacje noda'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ScriptsScreen(ip: node.ip, pin: pin)),
            ),
          ),
          _tile(
            icon: Icons.location_on_outlined,
            title: tr('Lokalizacja i weryfikacja'),
            sub: tr('ceremonia BLE + GPS — ustawia pozycję i potwierdza urządzenie'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TrustScreen(node: node)),
            ),
          ),
          _tile(
            icon: Icons.webhook_outlined,
            title: tr('Integracja (webhook)'),
            sub: tr('URL wywoływany przy zdarzeniach noda'),
            onTap: _editIntegration,
          ),
          _tile(
            icon: Icons.vpn_key_outlined,
            title: tr('Zmień PIN'),
            sub: tr('PIN dostępu do noda'),
            onTap: _changePin,
          ),
          _tile(
            icon: Icons.bluetooth_searching,
            title: tr('Tryb serwisowy (Bluetooth)'),
            sub: tr('zmiana WiFi / odzyskiwanie portfela'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ServiceScreen(node: node)),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFF2A2A2A)),
          const SizedBox(height: 8),
          ListTile(
            leading:
                const Icon(Icons.delete_outline, color: Color(0xFFFF4444)),
            title: Text(tr('Usuń node z listy'),
                style: const TextStyle(color: Color(0xFFFF4444))),
            subtitle: Text(tr('Usuwa node tylko z tej apki'),
                style: const TextStyle(color: Color(0xFF888888), fontSize: 12)),
            onTap: () {
              context.read<CoreBloc>().add(NodeRemoved(node.id));
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
          ListTile(
            leading:
                const Icon(Icons.delete_forever, color: Color(0xFFFF4444)),
            title: Text(tr('Usuń node z sieci (permanentnie)'),
                style: const TextStyle(color: Color(0xFFFF4444))),
            subtitle: Text(
                tr('Kasuje node i wszystkie jego dane z SENSMOS. Nieodwracalne — node nie zarejestruje się ponownie bez factory resetu. Zarobione GALU zostają na Twoim wallecie.'),
                style: const TextStyle(color: Color(0xFF888888), fontSize: 12)),
            onTap: _deleteFromNetwork,
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFromNetwork() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Usunąć node z sieci?')),
        content: Text(tr(
            'Node %s i WSZYSTKIE jego dane zostaną trwale usunięte z SENSMOS. '
            'Ta tożsamość nie będzie mogła się ponownie zarejestrować. '
            'Zarobione GALU pozostają na Twoim wallecie.', [_short])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Anuluj'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Usuń permanentnie'),
                  style: const TextStyle(color: Color(0xFFFF4444)))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final owner = context.read<CoreBloc>().state.wallet?.address;
      final wallet = context.read<WalletService>();
      if (owner == null) throw Exception(tr('Brak walleta'));
      final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
      final sig = await wallet.signMessage('sensmos:delete:${node.id}:$ts');
      final res = await http.delete(
        Uri.parse('${Config.beUrl}/v1/nodes/${node.id}'),
        headers: {'Content-Type': 'application/json', 'X-App-Key': 'sensmos2025'},
        body: jsonEncode({'owner': owner, 'ts': ts, 'sig': sig}),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        final err = jsonDecode(res.body)['error'] ?? res.statusCode;
        throw Exception('$err');
      }
      if (!mounted) return;
      context.read<CoreBloc>().add(NodeRemoved(node.id));
      Navigator.of(context).popUntil((r) => r.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Node usunięty z sieci'))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Błąd usuwania: %s', [e.toString()])),
          backgroundColor: const Color(0xFFFF4444)));
    }
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) =>
      Card(
        child: ListTile(
          leading: Icon(icon, color: AppTheme.purple),
          title: Text(title, style: const TextStyle(color: AppTheme.text)),
          subtitle: sub.isEmpty
              ? null
              : Text(sub,
                  style:
                      const TextStyle(color: AppTheme.muted, fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, color: AppTheme.muted),
          onTap: onTap,
        ),
      );

  Future<void> _editIntegration() async {
    final messenger = ScaffoldMessenger.of(context);
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $pin',
    };

    // Pobierz aktualny URL
    String current = '';
    try {
      final res = await http
          .get(Uri.parse('http://${node.ip}/config'), headers: headers)
          .timeout(const Duration(seconds: 5));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      current = (j['integration_url'] ?? '').toString();
    } catch (_) {}
    if (!mounted) return;

    final ctrl = TextEditingController(text: current);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Integracja (webhook)'),
            style: const TextStyle(color: AppTheme.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                tr('Node POST-uje tu zdarzenia (message_received, batch_sent, '
                    'sub_received, ws_connected). Puste = wyłączone.'),
                style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              style: const TextStyle(
                  color: AppTheme.text, fontSize: 13, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: 'https://...',
                hintStyle: TextStyle(color: AppTheme.muted),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Anuluj'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.teal),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(tr('Zapisz'), style: const TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    if (url == null) return; // anulowane (pusty string = świadome wyłączenie)

    try {
      final res = await http
          .post(Uri.parse('http://${node.ip}/config'),
              headers: headers, body: jsonEncode({'integration_url': url}))
          .timeout(const Duration(seconds: 5));
      messenger.showSnackBar(SnackBar(
        content: Text(res.statusCode == 200
            ? (url.isEmpty ? tr('Integracja wyłączona') : tr('Webhook zapisany'))
            : tr('Błąd %s', [res.statusCode])),
        backgroundColor: res.statusCode == 200 ? null : AppTheme.red,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(tr('Błąd: %s', [e])), backgroundColor: AppTheme.red));
    }
  }

  Future<void> _changePin() async {
    final messenger = ScaffoldMessenger.of(context);
    final nodeService = context.read<NodeService>();
    final ctrl = TextEditingController();
    final newPin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Zmień PIN'), style: const TextStyle(color: AppTheme.text)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 12,
          style: const TextStyle(
              color: AppTheme.text, fontSize: 18, letterSpacing: 2),
          decoration: InputDecoration(
            labelText: tr('Nowy PIN (min. 4 cyfry)'),
            labelStyle: const TextStyle(color: AppTheme.muted),
            counterStyle: const TextStyle(color: AppTheme.muted),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Anuluj'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.teal),
            onPressed: () {
              if (ctrl.text.trim().length >= 4) {
                Navigator.pop(ctx, ctrl.text.trim());
              }
            },
            child: Text(tr('Zapisz'), style: const TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    if (newPin == null) return;

    try {
      final res = await http
          .post(Uri.parse('http://${node.ip}/config'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $pin',
              },
              body: jsonEncode({'pin': newPin}))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        await nodeService.updateNodePin(node.id, newPin);
        if (mounted) setState(() => _pinOverride = newPin);
        messenger
            .showSnackBar(SnackBar(content: Text(tr('PIN zmieniony'))));
      } else {
        messenger.showSnackBar(SnackBar(
            content: Text(tr('Błąd %s', [res.statusCode])),
            backgroundColor: AppTheme.red));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(tr('Błąd: %s', [e])), backgroundColor: AppTheme.red));
    }
  }
}
