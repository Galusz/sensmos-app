import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme.dart';
import '../../l10n.dart';

class EntitiesScreen extends StatefulWidget {
  final String ip;
  final String pin;
  const EntitiesScreen({super.key, required this.ip, required this.pin});
  @override State<EntitiesScreen> createState() => _EntitiesScreenState();
}

class _EntitiesScreenState extends State<EntitiesScreen> {
  bool   _loading = true;
  String? _error;
  List<dynamic> _pub  = [];
  List<dynamic> _own  = [];
  List<dynamic> _pool = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.get(
        Uri.parse('http://${widget.ip}/data/status'),
        headers: {'Authorization': 'Bearer ${widget.pin}'},
      ).timeout(const Duration(seconds: 5));
      final j = jsonDecode(res.body) as Map<String,dynamic>;
      setState(() {
        _pub     = j['pub']  as List? ?? [];
        _own     = j['own']  as List? ?? [];
        _pool    = j['pool'] as List? ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Encje')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.teal))
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('Błąd: %s', [_error]),
                      style: const TextStyle(color: AppTheme.red))))
              : _pub.isEmpty && _own.isEmpty && _pool.isEmpty
                  ? Center(child: Text(tr('Brak encji'),
                      style: const TextStyle(color: AppTheme.muted)))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_pub.isNotEmpty) ...[
                          _sectionHeader('${tr('Publiczne')} (pub.*)', _pub.length),
                          ..._pub.map(_buildTile),
                          const SizedBox(height: 16),
                        ],
                        if (_own.isNotEmpty) ...[
                          _sectionHeader('${tr('Własne')} (own.*)', _own.length),
                          ..._own.map(_buildTile),
                          const SizedBox(height: 16),
                        ],
                        if (_pool.isNotEmpty) ...[
                          _sectionHeader(
                              '${tr('Zewnętrzne')} (sub./get./msg.)', _pool.length),
                          ..._pool.map(_buildTile),
                        ],
                      ],
                    ),
    );
  }

  Widget _sectionHeader(String label, int count) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Text(label.toUpperCase(),
          style: const TextStyle(color: AppTheme.muted,
              fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: AppTheme.teal.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8)),
        child: Text('$count',
            style: const TextStyle(color: AppTheme.teal, fontSize: 11)),
      ),
    ]),
  );

  Widget _buildTile(dynamic e) {
    final id    = e['entity_id']?.toString() ?? '?';
    final val   = e['value']?.toString() ?? '—';
    final unit  = e['unit']?.toString() ?? '';
    final age   = e['age_s'] as int? ?? 0;
    final local = e['local'] as bool? ?? false;

    final ageStr = age < 60 ? '${age}s'
        : age < 3600 ? '${age ~/ 60}min'
        : '${age ~/ 3600}h';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
              color: AppTheme.teal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(_entityIcon(id), color: AppTheme.teal, size: 20),
        ),
        title: Text(id,
            style: const TextStyle(
                color: AppTheme.text, fontSize: 14, fontFamily: 'monospace')),
        subtitle: Text(tr('Wiek: %s', [ageStr]) + (local ? '  •  ${tr('lokalna')}' : ''),
            style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        trailing: Text('$val${unit.isNotEmpty ? ' $unit' : ''}',
            style: const TextStyle(
                color: AppTheme.teal,
                fontSize: 15, fontWeight: FontWeight.bold)),
      ),
    );
  }

  IconData _entityIcon(String id) {
    final s = id.toLowerCase();
    if (s.contains('temp'))    return Icons.thermostat_outlined;
    if (s.contains('hum'))     return Icons.water_drop_outlined;
    if (s.contains('volt') || s.contains('bat')) return Icons.battery_5_bar;
    if (s.contains('signal') || s.contains('rssi')) return Icons.signal_wifi_4_bar;
    if (s.contains('press'))   return Icons.compress;
    if (s.contains('co2') || s.contains('gas')) return Icons.air;
    if (s.contains('light') || s.contains('lux')) return Icons.light_mode_outlined;
    return Icons.sensors;
  }
}
