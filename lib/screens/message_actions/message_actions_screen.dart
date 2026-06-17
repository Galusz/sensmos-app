import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme.dart';
import '../../l10n.dart';

const _kMaxSlots = 3;

class MessageActionsScreen extends StatefulWidget {
  final String ip;
  final String pin;

  const MessageActionsScreen({super.key, required this.ip, required this.pin});

  @override
  State<MessageActionsScreen> createState() => _MessageActionsScreenState();
}

class _MessageActionsScreenState extends State<MessageActionsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _actions = [];

  Map<String, String> get _h => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.pin}',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http
          .get(Uri.parse('http://${widget.ip}/config/messages'), headers: _h)
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _actions = List<Map<String, dynamic>>.from(j['message_actions'] ?? []);
      });
    } catch (e) {
      if (mounted) _snack(tr('Błąd ładowania: %s', [e]), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(String messageId) async {
    try {
      await http
          .delete(
            Uri.parse(
                'http://${widget.ip}/config/messages?id=${Uri.encodeQueryComponent(messageId)}'),
            headers: _h,
          )
          .timeout(const Duration(seconds: 5));
      await _load();
    } catch (e) {
      if (mounted) _snack(tr('Błąd: %s', [e]), error: true);
    }
  }

  Future<void> _save(Map<String, dynamic> action) async {
    try {
      final res = await http
          .post(
            Uri.parse('http://${widget.ip}/config/messages'),
            headers: _h,
            body: jsonEncode(action),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        await _load();
      } else {
        final msg = (jsonDecode(res.body) as Map<String, dynamic>)['error']
                as String? ??
            tr('Błąd');
        if (mounted) _snack(msg, error: true);
      }
    } catch (e) {
      if (mounted) _snack(tr('Błąd: %s', [e]), error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.red : null,
    ));
  }

  void _showAdd({Map<String, dynamic>? existing}) {
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ActionDialog(existing: existing),
    ).then((a) {
      if (a != null) _save(a);
    });
  }

  void _confirmDelete(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title:
            Text(tr('Usuń akcję'), style: const TextStyle(color: AppTheme.text)),
        content: Text(tr('Usunąć akcję dla "%s"?', [id]),
            style: const TextStyle(color: AppTheme.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('Anuluj'))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _delete(id);
            },
            child:
                Text(tr('Usuń'), style: const TextStyle(color: AppTheme.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Akcje')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: _actions.length < _kMaxSlots
          ? FloatingActionButton.small(
              backgroundColor: AppTheme.teal,
              onPressed: _showAdd,
              child: const Icon(Icons.add, color: Colors.black),
            )
          : null,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.teal))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _header(),
                const SizedBox(height: 12),
                if (_actions.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        tr('Brak akcji. Dodaj przyciskiem +'),
                        style: const TextStyle(
                            color: AppTheme.muted, fontSize: 13),
                      ),
                    ),
                  )
                else
                  ..._actions.map((a) => _ActionCard(
                        action: a,
                        onEdit: () => _showAdd(existing: a),
                        onDelete: () => _confirmDelete(
                            a['message_id'] as String? ?? ''),
                      )),
                const SizedBox(height: 80),
                _helpCard(),
              ],
            ),
    );
  }

  Widget _header() => Row(
        children: [
          Expanded(
            child: Text(
              tr('Automatyczne akcje wykonywane gdy node odbierze wiadomość '
                  'o podanym ID (lub "*" dla wszystkich).'),
              style: const TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.teal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('${_actions.length}/$_kMaxSlots',
                style: const TextStyle(
                    color: AppTheme.teal, fontSize: 12)),
          ),
        ],
      );

  Widget _helpCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('JAK TO DZIAŁA'),
                  style: const TextStyle(
                      color: AppTheme.muted,
                      fontSize: 11,
                      letterSpacing: 0.8)),
              const SizedBox(height: 6),
              _helpRow(Icons.tag, 'message_id',
                  tr('ID wiadomości triggera — "alarm", "update", "*" = wszystkie')),
              _helpRow(Icons.notifications_active, 'push',
                  tr('powiadomienie na telefon (tytuł/treść; {{from}}, {{payload}})')),
              _helpRow(Icons.webhook, 'webhook',
                  tr('URL do wywołania HTTP POST z payloadem wiadomości')),
              _helpRow(Icons.storage, 'prefix',
                  tr('Zapisz encje z payloadu jako {prefix}.entity_id na nodzie')),
              _helpRow(Icons.code, 'script',
                  tr('ID skryptu do uruchomienia przy odebraniu wiadomości')),
            ],
          ),
        ),
      );

  Widget _helpRow(IconData icon, String title, String desc) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: AppTheme.purple),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 13,
                          fontFamily: 'monospace')),
                  const SizedBox(height: 3),
                  Text(desc,
                      style: const TextStyle(
                          color: AppTheme.muted, fontSize: 12),
                      softWrap: true),
                ],
              ),
            ),
          ],
        ),
      );
}

// ── Karta akcji ───────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final Map<String, dynamic> action;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ActionCard(
      {required this.action, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final mid = action['message_id'] as String? ?? '?';
    final webhook = action['webhook'] as String? ?? '';
    final prefix = action['prefix'] as String? ?? '';
    final script = action['script'] as String? ?? '';
    final push = action['push'] as Map<String, dynamic>?;
    final pushTitle = push?['title'] as String? ?? '';
    final pushBody = push?['body'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      color: AppTheme.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.alt_route,
                      color: AppTheme.amber, size: 16),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppTheme.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(mid,
                      style: const TextStyle(
                          color: AppTheme.amber,
                          fontSize: 13,
                          fontFamily: 'monospace')),
                ),
              ],
            ),
            if (webhook.isNotEmpty ||
                prefix.isNotEmpty ||
                script.isNotEmpty ||
                pushTitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              if (webhook.isNotEmpty) _row(Icons.webhook, webhook, AppTheme.teal),
              if (prefix.isNotEmpty)
                _row(Icons.storage, 'prefix: $prefix', AppTheme.purple),
              if (script.isNotEmpty)
                _row(Icons.code, 'script: $script', AppTheme.blue),
              if (pushTitle.isNotEmpty)
                _row(
                    Icons.notifications_outlined,
                    'push: $pushTitle'
                        '${pushBody.isNotEmpty ? '  -  $pushBody' : ''}',
                    AppTheme.muted),
            ],
            const SizedBox(height: 8),
            const Divider(color: AppTheme.border, height: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined,
                      size: 14, color: AppTheme.muted),
                  label: Text(tr('Edytuj'),
                      style: const TextStyle(
                          color: AppTheme.muted, fontSize: 12)),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline,
                      size: 14, color: AppTheme.red),
                  label: Text(tr('Usuń'),
                      style: const TextStyle(
                          color: AppTheme.red, fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text, Color color) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 13, color: color),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  style: TextStyle(color: color, fontSize: 12),
                  softWrap: true),
            ),
          ],
        ),
      );
}

// ── Dialog dodawania / edycji ──────────────────────────────────

class _ActionDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _ActionDialog({this.existing});

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _midCtrl;
  late final TextEditingController _webhookCtrl;
  late final TextEditingController _prefixCtrl;
  late final TextEditingController _scriptCtrl;
  late final TextEditingController _pushTitleCtrl;
  late final TextEditingController _pushBodyCtrl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final push = e?['push'] as Map<String, dynamic>?;
    _midCtrl = TextEditingController(text: e?['message_id'] as String? ?? '');
    _webhookCtrl =
        TextEditingController(text: e?['webhook'] as String? ?? '');
    _prefixCtrl =
        TextEditingController(text: e?['prefix'] as String? ?? '');
    _scriptCtrl =
        TextEditingController(text: e?['script'] as String? ?? '');
    _pushTitleCtrl =
        TextEditingController(text: push?['title'] as String? ?? '');
    _pushBodyCtrl =
        TextEditingController(text: push?['body'] as String? ?? '');
  }

  @override
  void dispose() {
    _midCtrl.dispose();
    _webhookCtrl.dispose();
    _prefixCtrl.dispose();
    _scriptCtrl.dispose();
    _pushTitleCtrl.dispose();
    _pushBodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      backgroundColor: AppTheme.card,
      title: Text(isEdit ? tr('Edytuj akcję') : tr('Nowa akcja'),
          style: const TextStyle(color: AppTheme.text, fontSize: 16)),
      content: SizedBox(
        width: 320,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _lbl('MESSAGE ID *'),
                _tf(_midCtrl,
                    hint: tr('alarm, update, * (wszystkie)'),
                    required: true,
                    mono: true),
                const SizedBox(height: 12),
                _lbl(tr('POWIADOMIENIE')),
                _tf(_pushTitleCtrl,
                    hint: tr('Tytuł — np. Od {from}'),
                    onChanged: (_) => setState(() {})),
                const SizedBox(height: 8),
                _tf(_pushBodyCtrl,
                    hint: tr('Treść — np. {message}'),
                    enabled: _pushTitleCtrl.text.trim().isNotEmpty),
                const SizedBox(height: 12),
                _lbl('WEBHOOK URL'),
                _tf(_webhookCtrl, hint: 'https://...'),
                const SizedBox(height: 12),
                _lbl('ENTITY PREFIX'),
                _tf(_prefixCtrl, hint: tr('msg  →  zapisze jako msg.*')),
                const SizedBox(height: 12),
                _lbl('SCRIPT ID'),
                _tf(_scriptCtrl,
                    hint: tr('ID skryptu do uruchomienia'), mono: true),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Anuluj'))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.teal),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final pushTitle = _pushTitleCtrl.text.trim();
              final pushBody = _pushBodyCtrl.text.trim();
              Navigator.pop(context, {
                'message_id': _midCtrl.text.trim(),
                if (pushTitle.isNotEmpty || pushBody.isNotEmpty)
                  'push': {'title': pushTitle, 'body': pushBody},
                if (_webhookCtrl.text.trim().isNotEmpty)
                  'webhook': _webhookCtrl.text.trim(),
                if (_prefixCtrl.text.trim().isNotEmpty)
                  'prefix': _prefixCtrl.text.trim(),
                if (_scriptCtrl.text.trim().isNotEmpty)
                  'script': _scriptCtrl.text.trim(),
              });
            }
          },
          child:
              Text(tr('Zapisz'), style: const TextStyle(color: Colors.black)),
        ),
      ],
    );
  }

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t,
            style: const TextStyle(
                color: AppTheme.muted, fontSize: 11, letterSpacing: 0.8)),
      );

  Widget _tf(TextEditingController ctrl,
      {String? hint, bool required = false, bool mono = false,
      bool enabled = true, void Function(String)? onChanged}) =>
      TextFormField(
        controller: ctrl,
        enabled: enabled,
        onChanged: onChanged,
        style: TextStyle(
            color: enabled ? AppTheme.text : AppTheme.muted,
            fontSize: 13,
            fontFamily: mono ? 'monospace' : null),
        decoration: InputDecoration(
          filled: true,
          fillColor: enabled ? AppTheme.surface : AppTheme.bg,
          hintText: hint,
          hintStyle:
              const TextStyle(color: AppTheme.muted, fontSize: 12),
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
              horizontal: 10, vertical: 10),
          isDense: true,
        ),
        validator: required
            ? (v) => (v == null || v.isEmpty) ? tr('Wymagane') : null
            : null,
      );
}
