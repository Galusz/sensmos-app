import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import '../../theme.dart';
import '../../core/core_bloc.dart';
import '../../core/core_state.dart';
import '../../core/core_event.dart';
import '../../services/wallet_service.dart';
import '../../services/node_service.dart';
import '../node_config/node_config_screen.dart';
import '../node_config/trust_screen.dart';
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
  List<Map<String,dynamic>> _myBeNodes = [];            // WSZYSTKIE nody walleta wg BE (tez duchy)
  bool _beOpen = false;                                 // sekcja zwinieta domyslnie (drugorzedna)
  final _beRowOpen = <String>{};                        // rozwiniete wiersze (dopiero tam kosz)
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
    _fetchMyBeNodes();
  }

  // Moje nody wg BE (po owner wallet) — źródło prawdy o sieci: pokazuje też nody,
  // których nie ma na lokalnej liście (reinstall apki, duch po wymianie płytki)
  Future<void> _fetchMyBeNodes() async {
    final owner = context.read<CoreBloc>().state.wallet?.address;
    if (owner == null) return;
    try {
      final res = await http.get(
        Uri.parse('${Config.beUrl}/v1/nodes/by-owner/$owner'),
        headers: const {'X-App-Key': 'sensmos2025'},
      ).timeout(const Duration(seconds: 6));
      final j = jsonDecode(res.body) as Map<String,dynamic>;
      if (mounted) setState(() =>
          _myBeNodes = List<Map<String,dynamic>>.from(j['nodes'] ?? []));
    } catch (e) { print('[MyBeNodes] BŁĄD $e'); }
  }

  Future<void> _deleteFromNetwork(Map<String,dynamic> n) async {
    final id = n['device_id'] as String;
    final short = id.length > 8 ? '${id.substring(0,8)}…' : id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Usunąć node z sieci?')),
        content: Text(tr(
            'Node %s i WSZYSTKIE jego dane zostaną trwale usunięte z SENSMOS. '
            'Możesz go później dodać ponownie (onboarding przez Bluetooth). '
            'Zarobione GALU pozostają na Twoim wallecie.', [short])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Anuluj'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
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
      final sig = await wallet.signMessage('sensmos:delete:$id:$ts');
      final res = await http.delete(
        Uri.parse('${Config.beUrl}/v1/nodes/$id'),
        headers: {'Content-Type': 'application/json', 'X-App-Key': 'sensmos2025'},
        body: jsonEncode({'owner': owner, 'ts': ts, 'sig': sig}),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        throw Exception(jsonDecode(res.body)['error'] ?? res.statusCode);
      }
      if (!mounted) return;
      // Jeśli node był też na lokalnej liście — usuń i stamtąd
      final ns = context.read<NodeService>();
      if (ns.nodes.any((x) => x.id == id)) {
        context.read<CoreBloc>().add(NodeRemoved(id));
      }
      _fetchMyBeNodes();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Node usunięty z sieci'))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Błąd usuwania: %s', [e.toString()])),
          backgroundColor: const Color(0xFFFF4444)));
    }
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
          'balance':   balance['available'] != null
              ? (double.tryParse(balance['available'].toString())?.toStringAsFixed(2) ?? '—')
              : '—',
          'located':   device['located'] == true,   // czy node ma pozycję (BE = źródło prawdy)
          'last_ping': device['last_ping'],          // zdrowie noda wg chmury (niezależne od lokalnej sieci)
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
        if (bal != null) setState(() => _balance = double.tryParse(bal.toString())?.toStringAsFixed(2) ?? bal.toString());
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
  int get _totalNodes   => context.read<NodeService>().nodes.length;
  int get _reportingCount => context.read<NodeService>().nodes
      .where((n) { final s = _beSecs(n.id); return s != null && s < 3600; }).length;

  // Ile temu node raportował do chmury (last_ping) — niezależne od tego czy telefon jest w sieci noda
  double? _beSecs(String id) {
    final lp = _beData[id]?['last_ping'];
    if (lp == null) return null;
    try {
      return (DateTime.now().millisecondsSinceEpoch
          - DateTime.parse(lp).millisecondsSinceEpoch) / 1000;
    } catch (_) { return null; }
  }
  String _ago(num secs) {
    if (secs < 60)    return tr('przed chwilą');
    if (secs < 3600)  return '${(secs/60).floor()}m';
    if (secs < 86400) return '${(secs/3600).floor()}h';
    return '${(secs/86400).floor()}d';
  }

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
        body: nodes.isEmpty && _myBeNodes.isEmpty ? _buildEmpty() :
          RefreshIndicator(
            onRefresh: _refresh,
            color: AppTheme.teal,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildGlobalStats(),
                const SizedBox(height: 16),
                ...nodes.map((n) => _buildCard(n)),
                ..._buildMyBeSection(nodes),
              ],
            ),
          ),
      );
    });
  }

  // ── Moje nody w sieci (BE, po wallecie) ───────────────────
  // Kompaktowa, domyslnie zwinieta (mniej wazna niz lokalna lista wyzej).
  // Kosz dopiero po rozwinieciu wiersza — destrukcja nie na pierwszym tapnieciu.
  List<Widget> _buildMyBeSection(List<SavedNode> localNodes) {
    if (_myBeNodes.isEmpty) return const [];
    final localIds = localNodes.map((n) => n.id).toSet();

    final rows = <Widget>[];
    if (_beOpen) {
      for (final n in _myBeNodes) {
        final id     = n['device_id'] as String;
        final short  = id.length > 8 ? id.substring(0, 8) : id;
        final status = n['status'] as String? ?? '?';
        final color  = status == 'online' ? AppTheme.teal
                     : status == 'offline' ? Colors.amber.shade700 : AppTheme.muted;
        final openRow = _beRowOpen.contains(id);

        rows.add(InkWell(
          onTap: () => setState(() =>
              openRow ? _beRowOpen.remove(id) : _beRowOpen.add(id)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(children: [
              Icon(Icons.circle, color: color, size: 9),
              const SizedBox(width: 10),
              Text('sensmos-$short',
                  style: const TextStyle(color: AppTheme.text, fontSize: 13.5)),
              const Spacer(),
              Icon(openRow ? Icons.expand_less : Icons.expand_more,
                  color: AppTheme.muted, size: 17),
            ]),
          ),
        ));

        if (openRow) {
          final onList = localIds.contains(id);
          final secs   = n['seconds_since_ping'];
          final ago    = secs == null ? '—' : _ago(double.tryParse(secs.toString()) ?? 0);
          final label  = status == 'online' ? tr('online')
                       : status == 'offline' ? '${tr('cisza')} $ago' : tr('nieaktywny');
          rows.add(Padding(
            padding: const EdgeInsets.fromLTRB(33, 0, 14, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  '${n['city'] ?? '—'} · fw ${n['firmware'] ?? '?'} · $label'
                  '${onList ? '' : ' · ${tr('brak w tej apce')}'}'
                  '${n['trusted'] == true ? ' · ✓' : ''}',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11.5)),
              Row(children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: id));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(tr('ID skopiowane: %s', [id])),
                        duration: const Duration(seconds: 2)));
                  },
                  icon: const Icon(Icons.copy, size: 13, color: AppTheme.muted),
                  label: Text(tr('Kopiuj ID'),
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _deleteFromNetwork(n),
                  icon: const Icon(Icons.delete_forever,
                      size: 15, color: Color(0xFFFF4444)),
                  label: Text(tr('Usuń z sieci'),
                      style: const TextStyle(color: Color(0xFFFF4444), fontSize: 12)),
                ),
              ]),
            ]),
          ));
        }
      }
    }

    return [
      const SizedBox(height: 16),
      Card(
        child: Column(children: [
          InkWell(
            onTap: () => setState(() => _beOpen = !_beOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(children: [
                const Icon(Icons.cloud_outlined, color: AppTheme.muted, size: 15),
                const SizedBox(width: 8),
                Text(tr('Moje nody w sieci'),
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12.5)),
                const SizedBox(width: 6),
                Text('(${_myBeNodes.length})',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                const Spacer(),
                Icon(_beOpen ? Icons.expand_less : Icons.expand_more,
                    color: AppTheme.muted, size: 17),
              ]),
            ),
          ),
          ...rows,
        ]),
      ),
    ];
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
        _globalStat(Icons.sensors,    '$_reportingCount/$_totalNodes', tr('Raportują')),
        _divider(),
        _globalStat(Icons.data_usage, totalEntities > 0
            ? '$totalEntities' : '—', tr('Encje')),
        _divider(),
        // Portfel apki (nie saldo z noda). Brak portfela → czerwony ! + import.
        context.read<CoreBloc>().state.wallet == null
            ? _importWalletStat()
            : _globalStat(Icons.account_balance_wallet_outlined,
                _balance ?? _beData.values.firstOrNull?['balance'] ?? '—', tr('GALU saldo'),
                valueColor: const Color(0xFFE89B3F)),
      ]),
    );
  }

  Widget _importWalletStat() => Expanded(child: InkWell(
        onTap: _importWallet,
        child: Column(children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF4444), size: 20),
          const SizedBox(height: 4),
          Text(tr('Importuj portfel'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFF4444),
                  fontSize: 12, fontWeight: FontWeight.bold)),
          Text(tr('brak portfela'),
              style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
        ]),
      ));

  Future<void> _importWallet() async {
    final ctrl = TextEditingController();
    final pk = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Importuj portfel'), style: const TextStyle(color: AppTheme.text)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Wklej klucz prywatny (np. z MetaMask). Rób to tylko na swoim telefonie.'),
              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          const SizedBox(height: 10),
          TextField(controller: ctrl, autofocus: true, maxLines: 2,
            style: const TextStyle(color: AppTheme.text, fontSize: 13, fontFamily: 'monospace'),
            decoration: const InputDecoration(hintText: '0x…', hintStyle: TextStyle(color: AppTheme.muted))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Anuluj'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.teal),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(tr('Importuj'), style: const TextStyle(color: Colors.black))),
        ],
      ),
    );
    if (pk == null || pk.isEmpty || !mounted) return;
    final ws = context.read<WalletService>();
    final bloc = context.read<CoreBloc>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final w = await ws.restore(pk);
      bloc.add(WalletImported());
      messenger.showSnackBar(SnackBar(content: Text(tr('Portfel zaimportowany: %s',
          ['${w.address.substring(0,6)}…${w.address.substring(w.address.length-4)}']))));
      if (mounted) setState(() {});
    } catch (_) {
      messenger.showSnackBar(SnackBar(
          content: Text(tr('Nieprawidłowy klucz prywatny')),
          backgroundColor: const Color(0xFFFF4444)));
    }
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
    // Zdrowie z chmury (last_ping) — niezależne od łączności lokalnej (online = telefon sięga noda po IP)
    final beSecs      = _beSecs(n.id);
    final healthColor = beSecs == null ? AppTheme.muted
        : beSecs < 3600 ? AppTheme.teal : Colors.amber.shade700;
    final healthText  = beSecs == null ? tr('brak danych z chmury')
        : beSecs < 3600 ? '${tr('raportuje')} ${_ago(beSecs)}'
        : '${tr('cisza')} ${_ago(beSecs)}';

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
                  shape: BoxShape.circle, color: healthColor)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(
                      color: AppTheme.text,
                      fontWeight: FontWeight.w500, fontSize: 14)),
                  Text(n.ip, style: const TextStyle(
                      color: AppTheme.muted, fontSize: 12)),
                  Text(healthText, style: TextStyle(
                      color: healthColor, fontSize: 11)),
                ],
              )),
              // Łączność lokalna — czy telefon jest w sieci noda (można konfigurować), NIE zdrowie noda
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (online == true ? AppTheme.teal : AppTheme.muted).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(online == true ? Icons.wifi : Icons.wifi_off, size: 12,
                      color: online == true ? AppTheme.teal : AppTheme.muted),
                  const SizedBox(width: 4),
                  Text(online == null ? '…' : online ? tr('W sieci') : tr('Zdalnie'),
                    style: TextStyle(fontSize: 11,
                        color: online == true ? AppTheme.teal : AppTheme.muted)),
                ]),
              ),
              if (_beData[n.id]?['located'] == false) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.location_off, size: 13, color: Colors.amber.shade700)),
              ],
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
                if (_beData[n.id]?['located'] == false) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withOpacity(0.35))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.location_off, color: Colors.amber.shade700, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          tr('Brak lokalizacji — node niewidoczny na mapie i nie nalicza nagród.'),
                          style: TextStyle(color: Colors.amber.shade700, fontSize: 13,
                              fontWeight: FontWeight.w500))),
                      ]),
                      const SizedBox(height: 8),
                      if (online == true)
                        SizedBox(width: double.infinity, child: TextButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => TrustScreen(node: n))),
                          icon: const Icon(Icons.add_location_alt, size: 18),
                          label: Text(tr('Ustaw lokalizację')),
                          style: TextButton.styleFrom(foregroundColor: AppTheme.teal),
                        ))
                      else
                        Text(tr('Połącz się z siecią noda, aby ustawić lokalizację.'),
                            style: TextStyle(color: Colors.amber.shade700, fontSize: 12)),
                    ])),
                ],
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
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16, color: AppTheme.muted),
                      tooltip: tr('Kopiuj ID'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: n.id));
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(tr('ID skopiowane: %s', [n.id])),
                            duration: const Duration(seconds: 2)));
                      },
                    ),
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

                // Akcje wymagają lokalnego dostępu do noda (telefon w tej samej sieci co node)
                if (online == true) Row(children: [
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
                ]) else Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.muted.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    const Icon(Icons.wifi_off, size: 16, color: AppTheme.muted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      tr('Połącz się z siecią WiFi noda, aby zobaczyć encje i zmienić ustawienia.'),
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
                  ]),
                ),
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
