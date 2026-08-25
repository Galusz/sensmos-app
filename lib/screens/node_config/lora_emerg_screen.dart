import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme.dart';
import '../../l10n.dart';
import '../../services/node_service.dart';

/// LoRa awaryjne (FW 0.91): wybór ≤4 encji, które przy padzie internetu node dokleja
/// do beaconu LoRa. Sąsiedni node/brama odsyła je do sieci — właściciel dostaje push
/// z ostatnimi wartościami, o ile ktoś noda usłyszał.
class LoraEmergScreen extends StatefulWidget {
  final SavedNode node;
  final String pin;
  const LoraEmergScreen({super.key, required this.node, required this.pin});

  @override
  State<LoraEmergScreen> createState() => _LoraEmergScreenState();
}

class _LoraEmergScreenState extends State<LoraEmergScreen> {
  static const int _max = 4;
  bool _loading = true;
  bool _saving = false;
  bool _noRadio = false;
  String? _error;
  bool _active = false;
  final Set<String> _selected = {};
  // [{entity_id, value, unit}] — pub + own z /data/status
  final List<Map<String, String>> _entities = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cfg = await http
          .get(Uri.parse('http://${widget.node.ip}/node/lora_emerg'))
          .timeout(const Duration(seconds: 5));
      if (cfg.statusCode == 404) {
        // endpoint istnieje tylko w buildach z radiem LoRa
        if (mounted) setState(() { _loading = false; _noRadio = true; });
        return;
      }
      if (cfg.statusCode == 200) {
        final j = jsonDecode(cfg.body) as Map<String, dynamic>;
        _active = j['active'] == true;
        for (final e in (j['eids'] as List? ?? const [])) {
          _selected.add(e.toString());
        }
      }
      final data = await http
          .get(Uri.parse('http://${widget.node.ip}/data/status'),
              headers: {'Authorization': 'Bearer ${widget.pin}'})
          .timeout(const Duration(seconds: 5));
      if (data.statusCode == 200) {
        final j = jsonDecode(data.body) as Map<String, dynamic>;
        for (final bucket in ['pub', 'own']) {
          for (final e in (j[bucket] as List? ?? const [])) {
            final m = e as Map<String, dynamic>;
            final id = (m['entity_id'] ?? '').toString();
            if (id.isEmpty) continue;
            _entities.add({
              'entity_id': id,
              'value': (m['value'] ?? '').toString(),
              'unit': (m['unit'] ?? '').toString(),
            });
          }
        }
      }
      // wybrane wcześniej encje, których teraz nie ma na liście (np. czujnik odpięty) —
      // pokazujemy, żeby dało się je odznaczyć
      for (final s in _selected) {
        if (!_entities.any((e) => e['entity_id'] == s)) {
          _entities.add({'entity_id': s, 'value': '', 'unit': ''});
        }
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = tr('Nie można połączyć z nodem: %s', [e]);
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final res = await http
          .post(Uri.parse('http://${widget.node.ip}/node/lora_emerg'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${widget.pin}',
              },
              body: jsonEncode({'eids': _selected.toList()}))
          .timeout(const Duration(seconds: 6));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.statusCode == 200
            ? tr('Zapisano — node nada te encje przy awarii')
            : tr('Błąd %s', [res.statusCode])),
        backgroundColor: res.statusCode == 200 ? null : AppTheme.red,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('Błąd: %s', [e])), backgroundColor: AppTheme.red));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('LoRa awaryjne'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _noRadio
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr('Ten node nie obsługuje trybu awaryjnego — wymaga firmware 0.91+ '
                          'na płytce z radiem LoRa (SX1262, wariant -lora).'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.muted),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_error != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_error!,
                              style: const TextStyle(color: AppTheme.red, fontSize: 13)),
                        ),
                      ),
                    if (_active)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            const Icon(Icons.warning_amber, color: AppTheme.amber),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                  tr('TRYB AWARYJNY AKTYWNY — node nadaje te encje przez LoRa'),
                                  style: const TextStyle(
                                      color: AppTheme.amber, fontSize: 13)),
                            ),
                          ]),
                        ),
                      ),
                    Text(
                      tr('Gdy node straci internet, dołączy wybrane encje (max %s) do ramki '
                          'radiowej LoRa. Jeśli usłyszy go sąsiedni node albo brama, dostaniesz '
                          'powiadomienie z ostatnimi wartościami — mimo że Twój dom jest offline.',
                          ['$_max']),
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    if (_entities.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(tr('Node nie ma jeszcze żadnych encji.'),
                              style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                        ),
                      ),
                    ..._entities.map((e) {
                      final id = e['entity_id']!;
                      final sel = _selected.contains(id);
                      final v = e['value']!.isEmpty
                          ? ''
                          : ' · ${e['value']}${e['unit']!.isEmpty ? '' : ' ${e['unit']}'}';
                      return Card(
                        child: CheckboxListTile(
                          value: sel,
                          activeColor: AppTheme.teal,
                          title: Text(id,
                              style: const TextStyle(
                                  color: AppTheme.text,
                                  fontSize: 14,
                                  fontFamily: 'monospace')),
                          subtitle: v.isEmpty
                              ? null
                              : Text(v,
                                  style: const TextStyle(
                                      color: AppTheme.muted, fontSize: 12)),
                          onChanged: (on) {
                            setState(() {
                              if (on == true) {
                                if (_selected.length >= _max) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                      content: Text(tr('Maksymalnie %s encje', ['$_max']))));
                                  return;
                                }
                                _selected.add(id);
                              } else {
                                _selected.remove(id);
                              }
                            });
                          },
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.teal),
                      onPressed: _saving ? null : _save,
                      child: Text(
                          _saving
                              ? tr('Zapisywanie...')
                              : tr('Zapisz (%s/%s)', ['${_selected.length}', '$_max']),
                          style: const TextStyle(color: Colors.black)),
                    ),
                  ],
                ),
    );
  }
}
