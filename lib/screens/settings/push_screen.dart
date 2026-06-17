import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import '../../theme.dart';
import '../../l10n.dart';
import '../../services/node_service.dart';
import '../../services/push_service.dart';

class PushScreen extends StatefulWidget {
  const PushScreen({super.key});

  @override
  State<PushScreen> createState() => _PushScreenState();
}

class _PushScreenState extends State<PushScreen> {
  late final List<SavedNode> _nodes;
  final _tokenCtrl = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  final Map<String, String> _tokens = {}; // deviceId → token na nodzie

  @override
  void initState() {
    super.initState();
    _nodes = context.read<NodeService>().nodes;
    _load();
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    for (final n in _nodes) {
      try {
        final res = await http.get(
          Uri.parse('http://${n.ip}/config'),
          headers: {'Authorization': 'Bearer ${n.pin}'},
        ).timeout(const Duration(seconds: 4));
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        _tokens[n.id] = (j['push_token'] ?? '').toString();
      } catch (_) {
        _tokens[n.id] = '';
      }
    }
    if (mounted) {
      // prefill: żywy token FCM z PushService; fallback — token z noda
      final fcm = context.read<PushService>().token;
      final existing = _tokens.values.firstWhere(
          (t) => t.isNotEmpty, orElse: () => '');
      _tokenCtrl.text = (fcm != null && fcm.isNotEmpty) ? fcm : existing;
      setState(() => _loading = false);
    }
  }

  Future<void> _applyToAll(String token) async {
    setState(() => _busy = true);
    int ok = 0;
    for (final n in _nodes) {
      try {
        final res = await http
            .post(Uri.parse('http://${n.ip}/config'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer ${n.pin}',
                },
                body: jsonEncode({'push_token': token}))
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          ok++;
          _tokens[n.id] = token;
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Zapisano na %s/%s nodach', [ok, _nodes.length]))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Powiadomienia'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.teal))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _infoBanner(),
                const SizedBox(height: 16),
                Text(tr('TOKEN PUSH (FCM)'),
                    style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 11,
                        letterSpacing: 0.8)),
                const SizedBox(height: 6),
                TextField(
                  controller: _tokenCtrl,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(
                      color: AppTheme.text,
                      fontSize: 13,
                      fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppTheme.surface,
                    hintText: tr('wklej token FCM…'),
                    hintStyle:
                        const TextStyle(color: AppTheme.muted, fontSize: 13),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.paste,
                          color: AppTheme.muted, size: 20),
                      onPressed: () async {
                        final d = await Clipboard.getData('text/plain');
                        if (d?.text != null) _tokenCtrl.text = d!.text!;
                      },
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppTheme.border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppTheme.border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppTheme.teal)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.teal,
                          padding: const EdgeInsets.symmetric(vertical: 13)),
                      onPressed: _busy || _tokenCtrl.text.trim().isEmpty
                          ? null
                          : () => _applyToAll(_tokenCtrl.text.trim()),
                      icon: const Icon(Icons.notifications_active,
                          color: Colors.black, size: 18),
                      label: Text(tr('Włącz na nodach'),
                          style: const TextStyle(color: Colors.black)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.red,
                        side: const BorderSide(color: AppTheme.red),
                        padding: const EdgeInsets.symmetric(
                            vertical: 13, horizontal: 14)),
                    onPressed: _busy
                        ? null
                        : () {
                            _tokenCtrl.clear();
                            _applyToAll('');
                          },
                    icon: const Icon(Icons.notifications_off, size: 18),
                    label: Text(tr('Wyłącz')),
                  ),
                ]),
                const SizedBox(height: 24),
                Text(tr('STAN NA NODACH'),
                    style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 11,
                        letterSpacing: 0.8)),
                const SizedBox(height: 8),
                ..._nodes.map(_nodeRow),
              ],
            ),
    );
  }

  Widget _nodeRow(SavedNode n) {
    final token = _tokens[n.id] ?? '';
    final on = token.length > 10;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
            on ? Icons.notifications_active : Icons.notifications_off_outlined,
            color: on ? AppTheme.teal : AppTheme.muted),
        title: Text(n.label, style: const TextStyle(color: AppTheme.text)),
        subtitle: Text(
            on ? tr('włączone · %s…', [token.substring(0, 12)]) : tr('wyłączone'),
            style: TextStyle(
                color: on ? AppTheme.teal : AppTheme.muted, fontSize: 12)),
      ),
    );
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
                tr('Token FCM jest pobierany automatycznie i rozsyłany na nody przy '
                    'starcie aplikacji. To pole pokazuje aktualny token — możesz go '
                    'też ręcznie wymusić na nodach. Node przekazuje go do backendu, '
                    'który wysyła powiadomienia.'),
                style: const TextStyle(color: AppTheme.text, fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      );
}
