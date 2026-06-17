import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme.dart';
import '../../l10n.dart';

// ══════════════════════════════════════════════════════════════
// Scripts Screen — lista skryptów użytkownika na nodzie
// ══════════════════════════════════════════════════════════════

class ScriptsScreen extends StatefulWidget {
  final String ip;
  final String pin;

  const ScriptsScreen({super.key, required this.ip, required this.pin});

  @override
  State<ScriptsScreen> createState() => _ScriptsScreenState();
}

class _ScriptsScreenState extends State<ScriptsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _nodeScripts = [];
  int _nodeMax = 2;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, String> get _h => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.pin}',
      };

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http
          .get(Uri.parse('http://${widget.ip}/config/scripts'), headers: _h)
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _nodeScripts = List<Map<String, dynamic>>.from(j['scripts'] ?? []);
        _nodeMax = j['max'] as int? ?? 2;
      });
    } catch (e) {
      if (mounted) _snack(tr('Błąd: %s', [e]), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await http
          .delete(
            Uri.parse(
                'http://${widget.ip}/config/scripts?id=${Uri.encodeQueryComponent(id)}'),
            headers: _h,
          )
          .timeout(const Duration(seconds: 5));
      await _load();
    } catch (e) {
      if (mounted) _snack(tr('Błąd: %s', [e]), error: true);
    }
  }

  Future<void> _save(Map<String, dynamic> script) async {
    try {
      final res = await http
          .post(
            Uri.parse('http://${widget.ip}/config/scripts'),
            headers: _h,
            body: jsonEncode(script),
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

  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    final script = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
          builder: (_) => ScriptEditorScreen(existing: existing)),
    );
    if (script != null) _save(script);
  }

  void _confirmDelete(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title:
            Text(tr('Usuń skrypt'), style: const TextStyle(color: AppTheme.text)),
        content: Text(tr('Usunąć "%s"?', [id]),
            style: const TextStyle(color: AppTheme.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('Anuluj'))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _delete(id);
            },
            child: Text(tr('Usuń'), style: const TextStyle(color: AppTheme.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Skrypty')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: _nodeScripts.length < _nodeMax
          ? FloatingActionButton.small(
              backgroundColor: AppTheme.teal,
              onPressed: () => _openEditor(),
              child: const Icon(Icons.add, color: Colors.black),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.teal))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _badge(
                    tr('Skrypty wykonywane lokalnie na nodzie — uruchamiane przez '
                        'akcje wiadomości.'),
                    '${_nodeScripts.length}/$_nodeMax'),
                const SizedBox(height: 14),
                if (_nodeScripts.isEmpty)
                  _Empty(tr('Brak skryptów. Dodaj przyciskiem +'))
                else
                  ..._nodeScripts.map((s) => _NodeScriptCard(
                        script: s,
                        onEdit: () => _openEditor(existing: s),
                        onDelete: () => _confirmDelete(s['id'] as String? ?? ''),
                      )),
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  Widget _badge(String text, String label) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 13))),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.teal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label,
                style: const TextStyle(color: AppTheme.teal, fontSize: 12)),
          ),
        ],
      );
}

// ══════════════════════════════════════════════════════════════
// Karta skryptu
// ══════════════════════════════════════════════════════════════

class _NodeScriptCard extends StatelessWidget {
  final Map<String, dynamic> script;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _NodeScriptCard(
      {required this.script, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final id = script['id'] as String? ?? '?';
    final steps = script['steps'] as List? ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                    color: AppTheme.purple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: const Icon(Icons.code, color: AppTheme.purple, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(id,
                    style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 14,
                        fontFamily: 'monospace')),
              ),
              _chip(tr('Kroki: %s', [steps.length]), AppTheme.purple),
            ]),
            if (steps.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...steps.asMap().entries.map((e) =>
                  _stepSummary(e.key + 1, e.value as Map<String, dynamic>)),
            ],
            const SizedBox(height: 6),
            const Divider(color: AppTheme.border, height: 1),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined,
                    size: 16, color: AppTheme.muted),
                label: Text(tr('Edytuj'),
                    style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline,
                    size: 16, color: AppTheme.red),
                label: Text(tr('Usuń'),
                    style: const TextStyle(color: AppTheme.red, fontSize: 13)),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _stepSummary(int n, Map<String, dynamic> step) {
    final action = step['action'] as String? ?? '?';
    final cond = step['if'] as String? ?? '';
    final cd = step['cooldown_s']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            margin: const EdgeInsets.only(right: 6, top: 1),
            decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(3)),
            child: Text('$n',
                style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
          ),
          _actionChip(action),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (cond.isNotEmpty)
                  Text('if $cond',
                      style: const TextStyle(
                          color: AppTheme.teal,
                          fontSize: 12,
                          fontFamily: 'monospace'),
                      softWrap: true),
                if (cd.isNotEmpty)
                  Text('cd: ${cd}s',
                      style: const TextStyle(
                          color: AppTheme.muted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11)),
      );

  Widget _actionChip(String action) {
    final color = _actionColor(action);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4)),
      child: Text(action, style: TextStyle(color: color, fontSize: 11)),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text,
              style: const TextStyle(color: AppTheme.muted, fontSize: 14)),
        ),
      );
}

// ══════════════════════════════════════════════════════════════
// Editor Screen
// ══════════════════════════════════════════════════════════════

const _kMaxSteps = 4;

// report usunięte — to akcja tylko dla BE
const _kActions = [
  'webhook', 'push', 'send', 'calc', 'ping', 'fetch', 'aggregate',
];

Color _actionColor(String a) => switch (a) {
      'report' => AppTheme.teal,
      'webhook' => AppTheme.blue,
      'push' => AppTheme.amber,
      'send' => AppTheme.purple,
      'calc' => AppTheme.muted,
      'ping' => AppTheme.red,
      'fetch' => AppTheme.blue,
      'aggregate' => AppTheme.muted,
      _ => AppTheme.muted,
    };

// Stan jednego kroku
class _StepData {
  String action;
  String func; // aggregate

  final TextEditingController condCtrl;
  final TextEditingController cooldownCtrl;
  final Map<String, TextEditingController> _fields;

  _StepData({
    this.action = 'webhook',
    this.func = 'avg',
    String condition = '',
    String cooldown = '300',
    Map<String, String> fields = const {},
  })  : condCtrl = TextEditingController(text: condition),
        cooldownCtrl = TextEditingController(text: cooldown),
        _fields = {
          for (final e in fields.entries)
            e.key: TextEditingController(text: e.value)
        };

  TextEditingController ctrl(String key, [String def = '']) =>
      _fields.putIfAbsent(key, () => TextEditingController(text: def));

  void dispose() {
    condCtrl.dispose();
    cooldownCtrl.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
  }

  Map<String, dynamic> buildData() {
    switch (action) {
      case 'webhook':
        return {
          'url': ctrl('url').text.trim(),
          if (ctrl('body').text.trim().isNotEmpty)
            'body': ctrl('body').text.trim(),
        };
      case 'push':
        return {
          'title': ctrl('push_title').text.trim(),
          'body': ctrl('push_body').text.trim(),
        };
      case 'send':
        return {
          'to': ctrl('to').text.trim(),
          'message_id': ctrl('msg_id').text.trim(),
          if (ctrl('payload').text.trim().isNotEmpty)
            'payload': ctrl('payload').text.trim(),
        };
      case 'calc':
        return {
          'expr': ctrl('expr').text.trim(),
          'store': ctrl('store').text.trim(),
        };
      case 'ping':
        return {
          'host': ctrl('host').text.trim(),
          'timeout_ms': int.tryParse(ctrl('timeout').text) ?? 1000,
          if (ctrl('store').text.trim().isNotEmpty)
            'store': ctrl('store').text.trim(),
        };
      case 'fetch':
        return {
          'url': ctrl('url').text.trim(),
          if (ctrl('path').text.trim().isNotEmpty)
            'path': ctrl('path').text.trim(),
          'store': ctrl('store').text.trim(),
        };
      case 'aggregate':
        return {
          'entity': ctrl('entity').text.trim(),
          'func': func,
          'samples': int.tryParse(ctrl('samples').text) ?? 10,
          'store': ctrl('store').text.trim(),
        };
      default:
        return {};
    }
  }

  Map<String, dynamic> toJson() => {
        if (condCtrl.text.trim().isNotEmpty) 'if': condCtrl.text.trim(),
        'action': action,
        'cooldown_s': int.tryParse(cooldownCtrl.text) ?? 300,
        'data': buildData(),
      };

  static _StepData fromJson(Map<String, dynamic> j) {
    final action = j['action'] as String? ?? 'webhook';
    final cond = j['if'] as String? ?? '';
    final cd = j['cooldown_s']?.toString() ?? '300';
    final data = j['data'] as Map<String, dynamic>? ?? {};

    final fields = <String, String>{};
    switch (action) {
      case 'webhook':
        fields['url'] = data['url'] as String? ?? '';
        fields['body'] = data['body'] as String? ?? '';
        break;
      case 'push':
        fields['push_title'] = data['title'] as String? ?? '';
        fields['push_body'] = data['body'] as String? ?? '';
        break;
      case 'send':
        fields['to'] = data['to'] as String? ?? '';
        fields['msg_id'] = data['message_id'] as String? ?? '';
        fields['payload'] = data['payload'] as String? ?? '';
        break;
      case 'calc':
        fields['expr'] = data['expr'] as String? ?? '';
        fields['store'] = data['store'] as String? ?? '';
        break;
      case 'ping':
        fields['host'] = data['host'] as String? ?? '';
        fields['timeout'] = (data['timeout_ms'] ?? 1000).toString();
        fields['store'] = data['store'] as String? ?? '';
        break;
      case 'fetch':
        fields['url'] = data['url'] as String? ?? '';
        fields['path'] = data['path'] as String? ?? '';
        fields['store'] = data['store'] as String? ?? '';
        break;
      case 'aggregate':
        fields['entity'] = data['entity'] as String? ?? '';
        fields['samples'] = (data['samples'] ?? 10).toString();
        fields['store'] = data['store'] as String? ?? '';
        break;
    }

    return _StepData(
      action: _kActions.contains(action) ? action : 'webhook',
      func: data['func'] as String? ?? 'avg',
      condition: cond,
      cooldown: cd,
      fields: fields,
    );
  }
}

class ScriptEditorScreen extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const ScriptEditorScreen({super.key, this.existing});

  @override
  State<ScriptEditorScreen> createState() => _ScriptEditorScreenState();
}

class _ScriptEditorScreenState extends State<ScriptEditorScreen> {
  late final List<_StepData> _steps;
  late final String? _existingId;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _existingId = e?['id'] as String?;

    if (e != null) {
      final rawSteps = e['steps'] as List? ?? [];
      _steps = rawSteps.isEmpty
          ? [_StepData()]
          : rawSteps
              .map((s) => _StepData.fromJson(s as Map<String, dynamic>))
              .toList();
    } else {
      _steps = [_StepData()];
    }
  }

  @override
  void dispose() {
    for (final s in _steps) {
      s.dispose();
    }
    super.dispose();
  }

  String _genId() => 'u_${DateTime.now().millisecondsSinceEpoch % 99999}';

  void _save() {
    final id = _existingId ?? _genId();
    final script = {
      'id': id,
      'steps': _steps.map((s) => s.toJson()).toList(),
    };
    Navigator.pop(context, script);
  }

  void _addStep() {
    if (_steps.length >= _kMaxSteps) return;
    setState(() => _steps.add(_StepData()));
  }

  void _removeStep(int i) {
    if (_steps.length <= 1) return;
    setState(() {
      _steps[i].dispose();
      _steps.removeAt(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = _existingId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? tr('Edytuj skrypt') : tr('Nowy skrypt')),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(tr('Zapisz'),
                style: const TextStyle(color: AppTheme.teal, fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_existingId != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                const Text('ID: ',
                    style: TextStyle(color: AppTheme.muted, fontSize: 13)),
                Expanded(
                  child: Text(_existingId!,
                      style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 13,
                          fontFamily: 'monospace')),
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          ..._steps.asMap().entries.map((e) => _StepCard(
                index: e.key,
                data: e.value,
                onRemove: _steps.length > 1 ? () => _removeStep(e.key) : null,
                onChanged: () => setState(() {}),
              )),
          const SizedBox(height: 8),
          if (_steps.length < _kMaxSteps)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.teal,
                side: const BorderSide(color: AppTheme.teal),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _addStep,
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr('Dodaj krok (%s/%s)', [_steps.length, _kMaxSteps]),
                  style: const TextStyle(fontSize: 14)),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Karta pojedynczego kroku
// ══════════════════════════════════════════════════════════════

class _StepCard extends StatefulWidget {
  final int index;
  final _StepData data;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;

  const _StepCard({
    required this.index,
    required this.data,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  State<_StepCard> createState() => _StepCardState();
}

class _StepCardState extends State<_StepCard> {
  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Nagłówek kroku ───────────────────────────────
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(4)),
                child: Text(tr('KROK %s', [widget.index + 1]),
                    style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 11,
                        letterSpacing: 0.8)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: d.action,
                  isExpanded: true,
                  dropdownColor: AppTheme.surface,
                  style: TextStyle(
                      color: _actionColor(d.action),
                      fontSize: 14,
                      fontFamily: 'monospace'),
                  decoration: _decor(),
                  items: _kActions
                      .map((a) => DropdownMenuItem(
                            value: a,
                            child: Text(a,
                                style: TextStyle(
                                    color: _actionColor(a),
                                    fontFamily: 'monospace')),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => d.action = v);
                      widget.onChanged();
                    }
                  },
                ),
              ),
              if (widget.onRemove != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon:
                      const Icon(Icons.close, size: 20, color: AppTheme.muted),
                  onPressed: widget.onRemove,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ]),
            const SizedBox(height: 12),

            // ── Warunek + cooldown ────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _lbl(tr('WARUNEK (opcjonalnie)')),
                      TextFormField(
                        controller: d.condCtrl,
                        style: const TextStyle(
                            color: AppTheme.teal,
                            fontSize: 13,
                            fontFamily: 'monospace'),
                        decoration:
                            _decor().copyWith(hintText: 'pub.grid_v < 180'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 88,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _lbl('COOLDOWN s'),
                      TextFormField(
                        controller: d.cooldownCtrl,
                        style: const TextStyle(
                            color: AppTheme.text, fontSize: 14),
                        decoration: _decor(),
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Pola specyficzne dla akcji ─────────────────────
            _buildActionFields(d),
          ],
        ),
      ),
    );
  }

  Widget _buildActionFields(_StepData d) {
    switch (d.action) {
      case 'webhook':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tf(d, 'url', 'URL', 'https://...'),
            const SizedBox(height: 10),
            _tf(d, 'body', tr('BODY TEMPLATE (opcjonalnie)'), '{}'),
          ],
        );

      case 'push':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tf(d, 'push_title', tr('TYTUŁ'), 'Alert!'),
            const SizedBox(height: 10),
            _tf(d, 'push_body', tr('TREŚĆ'), tr('Wartość: {{pub.grid_v}}')),
          ],
        );

      case 'send':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tf(d, 'to', tr('DEVICE ID ODBIORCY'), ''),
            const SizedBox(height: 10),
            _row2(
              _tf(d, 'msg_id', 'MESSAGE ID', 'alert'),
              _tf(d, 'payload', tr('PAYLOAD (opc.)'), '{}'),
            ),
          ],
        );

      case 'calc':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tf(d, 'expr', tr('WYRAŻENIE'), 'pub.grid_v * 1.1', entity: true),
            const SizedBox(height: 10),
            _tf(d, 'store', tr('ZAPISZ DO'), 'tmp.result'),
          ],
        );

      case 'ping':
        return _row2(
          _tf(d, 'host', 'HOST', '8.8.8.8'),
          _tf(d, 'store', tr('ZAPISZ DO (opc.)'), 'tmp.ping'),
        );

      case 'fetch':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tf(d, 'url', 'URL', 'http://...'),
            const SizedBox(height: 10),
            _row2(
              _tf(d, 'path', tr('JSON PATH (opc.)'), 'temperature'),
              _tf(d, 'store', tr('ZAPISZ DO'), 'tmp.result'),
            ),
          ],
        );

      case 'aggregate':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row2(
              _tf(d, 'entity', tr('ENCJA'), 'pub.grid_v', entity: true),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _lbl(tr('FUNKCJA')),
                DropdownButtonFormField<String>(
                  initialValue: d.func,
                  isExpanded: true,
                  dropdownColor: AppTheme.surface,
                  style: const TextStyle(color: AppTheme.text, fontSize: 14),
                  decoration: _decor(),
                  items: ['avg', 'min', 'max', 'sum']
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (v) => setState(() => d.func = v!),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            _row2(
              _tf(d, 'samples', tr('PRÓBKI'), '10'),
              _tf(d, 'store', tr('ZAPISZ DO'), 'tmp.agg'),
            ),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _row2(Widget a, Widget b) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: 8),
          Expanded(child: b),
        ],
      );

  Widget _tf(_StepData d, String key, String label, String? hint,
          {bool entity = false}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _lbl(label),
          TextFormField(
            controller: d.ctrl(key),
            style: TextStyle(
                color: entity ? AppTheme.teal : AppTheme.text,
                fontSize: 13,
                fontFamily: entity ? 'monospace' : null),
            decoration: _decor().copyWith(hintText: hint),
          ),
        ],
      );

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(t,
            style: const TextStyle(
                color: AppTheme.muted, fontSize: 11, letterSpacing: 0.8)),
      );

  InputDecoration _decor() => InputDecoration(
        filled: true,
        fillColor: AppTheme.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.teal)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 12),
        isDense: true,
      );
}
