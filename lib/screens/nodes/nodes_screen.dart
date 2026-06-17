import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import '../../theme.dart';
import '../../core/core_bloc.dart';
import '../../core/core_state.dart';
import '../../services/node_service.dart';
import '../node_config/node_config_screen.dart';
import '../../config.dart';
import '../entities/entities_screen.dart';
import '../setup/setup_screen.dart';
import '../node/node_manager_screen.dart';
import '../../l10n.dart';

class NodesScreen extends StatefulWidget {
  const NodesScreen({super.key});
  @override State<NodesScreen> createState() => _NodesScreenState();
}

class _NodesScreenState extends State<NodesScreen> {
  final _expanded  = <String, bool>{};
  final _online    = <String, bool>{};
  final _nodeData  = <String, Map<String,dynamic>>{};
  final _scarcity  = <String, String>{};
  final _beData    = <String, Map<String,dynamic>>{};  // dane z BE per node
  String? _balance;

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    final ns = context.read<NodeService>();
    for (final n in ns.nodes) {
      _fetchNode(n.ip, n.id, n.pin);
      _fetchBeData(n.id);
    }
    // Pobierz saldo GALU z pierwszego dostępnego noda
    if (ns.nodes.isNotEmpty) _fetchBalance(ns.nodes.first.ip, ns.nodes.first.pin);
  }

  Future<void> _fetchBeData(String deviceId) async {
    try {
      final res = await http.get(
        Uri.parse('${Config.beUrl}/v1/nodes/$deviceId'),
      ).timeout(const Duration(seconds: 5));
      final j = jsonDecode(res.body) as Map<String,dynamic>;
      final entities = j['entities'] as List? ?? [];
      final device   = j['device']   as Map<String,dynamic>? ?? {};
      final balance  = j['balance']  as Map<String,dynamic>? ?? {};

      String scarcity = '—';
      if (entities.isNotEmpty) {
        final mult = entities.first['scarcity_mult'];
        if (mult != null) scarcity = double.tryParse(mult.toString())?.toStringAsFixed(3) ?? '—';
      }

      if (mounted) setState(() {
        _scarcity[deviceId] = scarcity;
        _beData[deviceId] = {
          'neighbors': device['neighbor_count']?.toString() ?? '0',
          'radius':    device['radius_km'] != null
              ? '${double.tryParse(device['radius_km'].toString())?.toStringAsFixed(1)} km'
              : '—',
          'balance':   balance['available']?.toString() ?? '—',
        };
      });
    } catch (e) { print('[BeData] BŁĄD $e'); }
  }

  Future<void> _fetchBalance(String ip, String pin) async {
    try {
      final res = await http.get(Uri.parse('http://$ip/wallet/balance'),
          headers: {'Authorization': 'Bearer $pin'})
          .timeout(const Duration(seconds: 5));
      final j = jsonDecode(res.body) as Map<String,dynamic>;
      if (mounted) {
        final bal = j['available'] ?? j['total_earned'];
        if (bal != null) setState(() => _balance = double.tryParse(bal.toString())?.toStringAsFixed(1) ?? bal.toString());
      }
    } catch (_) {}
  }

  Future<void> _fetchNode(String ip, String id, String pin) async {
    try {
      final res = await http.get(Uri.parse('http://$ip/info'),
          headers: {'Authorization': 'Bearer $pin'})
          .timeout(const Duration(seconds: 3));
      if (!mounted) return;
      final j = jsonDecode(res.body) as Map<String,dynamic>;
      setState(() { _online[id] = true; _nodeData[id] = j; });
    } catch (_) {
      if (mounted) setState(() => _online[id] = false);
    }
  }

  // Statystyki globalne
  int get _onlineCount  => _online.values.where((v) => v).length;
  int get _totalNodes   => context.read<NodeService>().nodes.length;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CoreBloc, CoreState>(builder: (context, state) {
      final ns    = context.read<NodeService>();
      final nodes = ns.nodes;

      return Scaffold(
        appBar: AppBar(
          title: Text(tr('Panel')),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refresh, tooltip: tr('Odśwież')),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: tr('Dodaj node'),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => const NodeManagerScreen()))),
          ],
        ),
        body: nodes.isEmpty ? _buildEmpty() :
          RefreshIndicator(
            onRefresh: _refresh,
            color: AppTheme.teal,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildGlobalStats(),
                const SizedBox(height: 16),
                ...nodes.map((n) => _buildCard(n)),
              ],
            ),
          ),
      );
    });
  }

  // ── Statystyki globalne ───────────────────────────────────
  Widget _buildGlobalStats() {
    int totalEntities = 0;
    for (final d in _nodeData.values) {
      totalEntities += (d['entity_count'] as int? ?? d['buffer_count'] as int? ?? 0);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        _globalStat(Icons.sensors,    '$_onlineCount/$_totalNodes', 'Online'),

        _divider(),
        _globalStat(Icons.data_usage, totalEntities > 0
            ? '$totalEntities' : '—', tr('Encje')),
        _divider(),
        _globalStat(Icons.account_balance_wallet_outlined,
            _balance ?? _beData.values.firstOrNull?['balance'] ?? '—', tr('GALU saldo'),
            valueColor: const Color(0xFFE89B3F)),
      ]),
    );
  }

  Widget _globalStat(IconData icon, String value, String label, {Color? valueColor}) =>
    Expanded(child: Column(children: [
      Icon(icon, color: AppTheme.teal, size: 20),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(
          color: valueColor ?? AppTheme.text, fontSize: 16, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
    ]));

  Widget _divider() => Container(
      width: 1, height: 40, color: AppTheme.border,
      margin: const EdgeInsets.symmetric(horizontal: 8));

  // ── Karta noda ────────────────────────────────────────────
  Widget _buildCard(SavedNode n) {
    final online   = _online[n.id];
    final expanded = _expanded[n.id] ?? false;
    final data     = _nodeData[n.id];
    final name     = n.label.isNotEmpty && n.label != 'Node'
        ? n.label
        : 'sensmos-${n.id.length >= 6 ? n.id.substring(0,6) : n.id}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: AppTheme.border,
            width: 1)),
      child: Column(children: [
        // Header
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() => _expanded[n.id] = !expanded);
            if (!expanded) {
              _fetchNode(n.ip, n.id, n.pin);
              _fetchBeData(n.id);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Container(width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online == null ? AppTheme.muted
                      : online ? AppTheme.teal : Colors.red.shade400)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(
                      color: AppTheme.text,
                      fontWeight: FontWeight.w500, fontSize: 14)),
                  Text(n.ip, style: const TextStyle(
                      color: AppTheme.muted, fontSize: 12)),
                ],
              )),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (online == true ? AppTheme.teal : AppTheme.muted)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
                child: Text(
                  online == null ? '...' : online ? 'Online' : 'Offline',
                  style: TextStyle(fontSize: 11,
                      color: online == true ? AppTheme.teal : AppTheme.muted)),
              ),
              const SizedBox(width: 8),
              Icon(expanded ? Icons.expand_less : Icons.expand_more,
                  color: AppTheme.muted, size: 20),
            ]),
          ),
        ),

        // Rozwinięta część
        if (expanded) ...[
          const Divider(color: AppTheme.border, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (online == true && data != null) ...[
                  Row(children: [
                    _stat('Scarcity',  _scarcity[n.id] ?? '—'),
                    const SizedBox(width: 16),
                    _stat(tr('Sąsiedzi'), _beData[n.id]?['neighbors'] ?? '—'),
                    const SizedBox(width: 16),
                    _stat(tr('Promień'),  _beData[n.id]?['radius']    ?? '—'),
                    const SizedBox(width: 16),
                    _stat(tr('Encje'),
                        (data['entity_count'] ?? data['buffer_count'] ?? '—').toString()),
                  ]),
                  const SizedBox(height: 14),
                ] else if (online == true) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(color: AppTheme.teal,
                        backgroundColor: AppTheme.border)),
                  const SizedBox(height: 8),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(tr('Node niedostępny'),
                        style: const TextStyle(color: AppTheme.muted, fontSize: 13))),
                  const SizedBox(height: 8),
                ],

                // Przyciski — zawsze aktywne
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(
                          builder: (_) => EntitiesScreen(
                              ip: n.ip, pin: n.pin)));
                    },
                    icon: const Icon(Icons.sensors, size: 16),
                    label: Text(tr('Encje')),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.teal,
                        side: const BorderSide(color: AppTheme.teal)),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(
                          builder: (_) => NodeConfigScreen(node: n)));
                    },
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: Text(tr('Ustawienia')),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.text,
                        side: const BorderSide(color: AppTheme.border)),
                  )),
                ]),
              ],
            ),
          ),
        ],
      ]),
    );
  }

  Widget _stat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(
          color: AppTheme.text, fontSize: 14, fontWeight: FontWeight.w500)),
    ],
  );

  Widget _buildEmpty() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.sensors_off, color: AppTheme.muted, size: 48),
      const SizedBox(height: 16),
      Text(tr('Brak nodów'), style: const TextStyle(color: AppTheme.text, fontSize: 16)),
      const SizedBox(height: 8),
      Text(tr('Dodaj node przez BLE'),
          style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SetupScreen())),
        icon: const Icon(Icons.add),
        label: Text(tr('Dodaj node')),
        style: FilledButton.styleFrom(
            backgroundColor: AppTheme.teal, foregroundColor: AppTheme.bg),
      ),
    ]),
  );
}
