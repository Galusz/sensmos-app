import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import '../../config.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../../core/core_bloc.dart';

/// Plugin „Raport łącza" (2026-08-25) — pierwszy plugin bez tunelu: historia zaników
/// internetu z wd_outages (WS-watchdog noda) z podziałem winy ISP/serwer. Sedno:
/// „Kopiuj raport" = tekstowy dowód do reklamacji u dostawcy internetu.
class LinkReportScreen extends StatefulWidget {
  final String deviceId;
  final String label;
  const LinkReportScreen({super.key, required this.deviceId, required this.label});

  @override
  State<LinkReportScreen> createState() => _LinkReportScreenState();
}

class _LinkReportScreenState extends State<LinkReportScreen> {
  int _days = 30;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _episodes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final owner = context.read<CoreBloc>().state.wallet?.address;
      if (owner == null) throw Exception(tr('Brak portfela w apce'));
      final res = await http.get(Uri.parse(
        '${Config.beUrl}/v1/nodes/${widget.deviceId}/outages?days=$_days&owner=$owner',
      )).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _summary = (j['summary'] as Map?)?.cast<String, dynamic>();
        _episodes = List<Map<String, dynamic>>.from(j['episodes'] ?? []);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = '$e'; });
    }
  }

  String _dur(num s) {
    final t = s.round();
    if (t < 60) return '${t}s';
    if (t < 3600) return '${t ~/ 60}m ${t % 60}s';
    return '${t ~/ 3600}h ${(t % 3600) ~/ 60}m';
  }

  String _two(int n) => n.toString().padLeft(2, '0');
  String _when(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    return '${_two(d.day)}.${_two(d.month)} ${_two(d.hour)}:${_two(d.minute)}';
  }

  // Tekstowy raport do schowka — załącznik do reklamacji u dostawcy.
  String _reportText() {
    final s = _summary ?? {};
    final b = StringBuffer()
      ..writeln('SENSMOS — ${tr('Raport łącza')} (${widget.label})')
      ..writeln('${tr('Okres')}: ${tr('ostatnie %s dni', ['$_days'])}')
      ..writeln('${tr('Przerwy w dostępie do internetu')}: ${s['isp_count'] ?? 0}')
      ..writeln('${tr('Łączny czas bez internetu')}: ${_dur(s['isp_total_s'] ?? 0)}')
      ..writeln('${tr('Najdłuższa przerwa')}: ${_dur(s['longest_s'] ?? 0)}')
      ..writeln('${tr('Pomiar niezależny, 24/7, stempel czasu NTP')} — sensmos.com')
      ..writeln('');
    for (final e in _episodes.where((e) => e['blame'] == 'isp')) {
      b.writeln('${_when('${e['started_at']}')}  ·  ${_dur(e['total_s'] ?? 0)}');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary ?? {};
    return Scaffold(
      appBar: AppBar(title: Text('${tr('Łącze')} · ${widget.label}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.teal))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Card(child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!, style: const TextStyle(color: AppTheme.red, fontSize: 13)),
                  )),
                Row(children: [
                  for (final d in [7, 30, 90])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(tr('%s dni', ['$d'])),
                        selected: _days == d,
                        selectedColor: AppTheme.teal.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                            color: _days == d ? AppTheme.teal : AppTheme.muted, fontSize: 12),
                        onSelected: (_) { setState(() => _days = d); _load(); },
                      ),
                    ),
                ]),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('Twój internet (wina dostawcy)'),
                          style: const TextStyle(color: AppTheme.muted, fontSize: 11, letterSpacing: 0.8)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: _stat('${s['isp_count'] ?? 0}', tr('przerw'))),
                        Expanded(child: _stat(_dur(s['isp_total_s'] ?? 0), tr('bez internetu'))),
                        Expanded(child: _stat(_dur(s['longest_s'] ?? 0), tr('najdłuższa'))),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        tr('Pozostałe %s przerw to chwilowe prace po stronie SENSMOS — nie liczą się do raportu.',
                            ['${(s['count'] ?? 0) - (s['isp_count'] ?? 0)}']),
                        style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.teal),
                  onPressed: _episodes.isEmpty ? null : () {
                    Clipboard.setData(ClipboardData(text: _reportText()));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(tr('Raport skopiowany — wklej go do reklamacji'))));
                  },
                  icon: const Icon(Icons.copy, color: Colors.black, size: 18),
                  label: Text(tr('Kopiuj raport'), style: const TextStyle(color: Colors.black)),
                ),
                const SizedBox(height: 16),
                if (_episodes.isEmpty && _error == null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(tr('Brak zaników w tym okresie — łącze działało bez przerw. 🎉'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                  ),
                for (final e in _episodes)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                          e['blame'] == 'isp' ? Icons.wifi_off : Icons.cloud_off,
                          size: 20,
                          color: e['blame'] == 'isp' ? AppTheme.red : AppTheme.muted),
                      title: Text('${_when('${e['started_at']}')}  ·  ${_dur(e['total_s'] ?? 0)}',
                          style: const TextStyle(color: AppTheme.text, fontSize: 13)),
                      subtitle: Text(
                          e['blame'] == 'isp'
                              ? tr('internet nie działał (wina dostawcy)')
                              : tr('serwis SENSMOS — nie liczy się do raportu'),
                          style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                      trailing: (e['restarts'] ?? 0) > 0
                          ? const Icon(Icons.restart_alt, size: 16, color: AppTheme.amber)
                          : null,
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _stat(String v, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(v, style: const TextStyle(
              color: AppTheme.text, fontSize: 17, fontWeight: FontWeight.w700)),
          Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
        ],
      );
}
