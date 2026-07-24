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
import '../../services/ble_service.dart';
import '../../log.dart';
import '../node_config/node_config_screen.dart';
import '../node_config/trust_screen.dart';
import '../node_config/service_screen.dart';
import '../../config.dart';
import '../entities/entities_screen.dart';
import '../setup/setup_screen.dart';
import '../node/node_manager_screen.dart';
import '../terminal/terminal_screen.dart';
import '../integrations/ha_panel_screen.dart';
import '../integrations/ha_settings_screen.dart';
import '../../services/integrations/integration_kind.dart';
import '../../services/integrations/integration_store.dart';
import '../../l10n.dart';

/// Panel — JEDNA lista nodów, źródło prawdy = BE (owned by wallet), działa wszędzie.
/// Lokalny wpis (IP/PIN) dopina się po device_id → odblokowuje akcje LOKALNE (tylko w sieci noda).
/// Akcje dzielą się na „Dostępne zawsze" (przez BE/relay: terminal, statystyki, usuń)
/// i „Sieć lokalna" (encje, ustawienia, lokalizacja — wyszarzone poza LAN-em).
class NodesScreen extends StatefulWidget {
  const NodesScreen({super.key});
  @override
  State<NodesScreen> createState() => _NodesScreenState();
}

class _NodesScreenState extends State<NodesScreen> {
  final _expanded = <String, bool>{};
  final _online = <String, bool>{}; // LOKALNA osiągalność (telefon w sieci noda)
  final _nodeData = <String, Map<String, dynamic>>{}; // /info z noda (entity_count itd.)
  final _scarcity = <String, String>{};
  final _beData = <String, Map<String, dynamic>>{}; // /v1/nodes/:id (sąsiedzi/promień/saldo)
  final _kinds = <String, Set<String>>{}; // podpięte integracje per node (opt-in)
  List<Map<String, dynamic>> _myBeNodes = []; // WSZYSTKIE nody walleta wg BE — PRYMARNE źródło
  final _nodeErr = <String, String>{};
  String? _balance;
  BleService? _bleRef;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    // częste odświeżanie statusu online (ws_online z BE = żywy WS, nie próg 10 min)
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      _fetchMyBeNodes();
      _probeAllLocal();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bleRef = context.read<BleService>();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final ns = context.read<NodeService>();
    _fetchMyBeNodes();
    _probeAllLocal();
    _pruneStale();
    _fetchBalance();
    for (final n in ns.nodes) { _fetchBeData(n.id); }
  }

  // ── merge BE (prymarne) + lokalne wpisy (IP/PIN) → jedna lista ──
  List<_UnifiedNode> _merged() {
    final ns = context.read<NodeService>();
    final localById = {for (final s in ns.nodes) s.id: s};
    final out = <_UnifiedNode>[];
    final seen = <String>{};
    for (final be in _myBeNodes) {
      final id = be['device_id'] as String;
      seen.add(id);
      out.add(_UnifiedNode(id: id, be: be, saved: localById[id]));
    }
    // lokalne, których BE (jeszcze) nie zwrócił — nie chowamy
    for (final s in ns.nodes) {
      if (!seen.contains(s.id)) out.add(_UnifiedNode(id: s.id, be: null, saved: s));
    }
    return out;
  }

  Future<void> _pruneStale() async {
    final ns = context.read<NodeService>();
    final coreBloc = context.read<CoreBloc>();
    final byIp = <String, List<SavedNode>>{};
    for (final n in ns.nodes) {
      if (n.ip.isEmpty) continue;
      byIp.putIfAbsent(n.ip, () => []).add(n);
    }
    for (final group in byIp.values.where((g) => g.length > 1)) {
      final ping = <String, DateTime?>{};
      for (final n in group) {
        try {
          final res = await http.get(Uri.parse('${Config.beUrl}/v1/nodes/${n.id}'))
              .timeout(const Duration(seconds: 5));
          final dev = (jsonDecode(res.body) as Map<String, dynamic>)['device']
              as Map<String, dynamic>? ?? {};
          ping[n.id] = DateTime.tryParse(dev['last_ping']?.toString() ?? '');
        } catch (_) { ping[n.id] = null; }
      }
      SavedNode? winner;
      for (final n in group) {
        final p = ping[n.id];
        if (p == null) continue;
        if (winner == null || p.isAfter(ping[winner.id]!)) winner = n;
      }
      if (winner == null) continue;
      final now = DateTime.now().toUtc();
      if (now.difference(ping[winner.id]!.toUtc()) > const Duration(minutes: 10)) continue;
      for (final n in group) {
        if (n.id == winner.id) continue;
        final p = ping[n.id];
        final stale = p == null || now.difference(p.toUtc()) > const Duration(hours: 1);
        if (!stale) continue;
        coreBloc.add(NodeRemoved(n.id));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
              tr('Usunięto nieaktywny wpis %s (node po reflashu)', [n.id.substring(0, 8)]))));
        }
      }
    }
  }

  Future<void> _fetchMyBeNodes() async {
    final owner = context.read<CoreBloc>().state.wallet?.address;
    if (owner == null) return;
    try {
      final res = await http.get(
        Uri.parse('${Config.beUrl}/v1/nodes/by-owner/$owner'),
        headers: const {'X-App-Key': 'sensmos2025'},
      ).timeout(const Duration(seconds: 6));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (mounted) setState(() => _myBeNodes = List<Map<String, dynamic>>.from(j['nodes'] ?? []));
    } catch (e) { Log.w('nodes', 'by-owner: $e'); }
  }

  Future<void> _deleteFromNetwork(String id) async {
    final short = id.length > 8 ? '${id.substring(0, 8)}…' : id;
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
              child: Text(tr('Usuń permanentnie'), style: const TextStyle(color: Color(0xFFFF4444)))),
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
      if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? res.statusCode);
      if (!mounted) return;
      final ns = context.read<NodeService>();
      if (ns.nodes.any((x) => x.id == id)) context.read<CoreBloc>().add(NodeRemoved(id));
      _fetchMyBeNodes();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Node usunięty z sieci'))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Błąd usuwania: %s', [e.toString()])),
          backgroundColor: const Color(0xFFFF4444)));
    }
  }

  Future<void> _fetchBeData(String deviceId) async {
    try {
      final res = await http.get(Uri.parse('${Config.beUrl}/v1/nodes/$deviceId'))
          .timeout(const Duration(seconds: 5));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final entities = j['entities'] as List? ?? [];
      final device = j['device'] as Map<String, dynamic>? ?? {};
      final balance = j['balance'] as Map<String, dynamic>? ?? {};
      String scarcity = '—';
      if (entities.isNotEmpty) {
        final mult = entities.first['scarcity_mult'];
        if (mult != null) scarcity = double.tryParse(mult.toString())?.toStringAsFixed(3) ?? '—';
      }
      if (mounted) setState(() {
        _scarcity[deviceId] = scarcity;
        _beData[deviceId] = {
          'neighbors': device['neighbor_count']?.toString() ?? '0',
          'radius': device['radius_km'] != null
              ? '${double.tryParse(device['radius_km'].toString())?.toStringAsFixed(1)} km' : '—',
          'balance': balance['available'] != null
              ? (double.tryParse(balance['available'].toString())?.toStringAsFixed(2) ?? '—') : '—',
          'located': device['located'] == true,
        };
      });
    } catch (e) { Log.w('nodes', 'beData: $e'); }
  }

  // 0.73: saldo z BE wprost (publiczne, po adresie właściciela) — koniec proxy przez noda.
  Future<void> _fetchBalance() async {
    final addr = context.read<CoreBloc>().state.wallet?.address;
    if (addr == null) return;
    try {
      final res = await http.get(Uri.parse('${Config.beUrl}/v1/wallet/$addr'))
          .timeout(const Duration(seconds: 6));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (mounted) {
        final bal = j['available'] ?? j['total_earned'];
        if (bal != null) setState(() => _balance = double.tryParse(bal.toString())?.toStringAsFixed(2) ?? bal.toString());
      }
    } catch (_) {}
  }

  // Sprawdź LOKALNĄ osiągalność (telefon w sieci noda) — na rozwinięcie karty.
  Future<void> _probeLocal(SavedNode n) async {
    if (await _tryInfo(n.ip, n.id, n.pin)) return;
    final short = n.id.length >= 6 ? n.id.substring(0, 6).toLowerCase() : n.id.toLowerCase();
    String? fresh;
    try {
      fresh = await _bleRef?.discoverByHostname(hostname: 'sensmos-$short.local', timeout: const Duration(seconds: 5));
    } catch (e) { Log.w('node', 'mDNS sensmos-$short: $e'); }
    if (fresh != null && fresh.isNotEmpty && fresh != n.ip) {
      if (mounted) await context.read<NodeService>().updateNodeIp(n.id, fresh);
      if (await _tryInfo(fresh, n.id, n.pin)) return;
    }
    if (mounted) setState(() => _online[n.id] = false);
  }

  void _probeAllLocal() {
    for (final n in context.read<NodeService>().nodes) { _probeLocalQuick(n); }
  }

  // Lekki, okresowy test osiągalności lokalnej (bez mDNS/retry) — żeby badge „W tej sieci"/„Zdalnie"
  // odświeżał się sam z pollingu, a nie dopiero po rozwinięciu karty.
  Future<void> _probeLocalQuick(SavedNode n) async {
    if (n.ip.isEmpty) { if (mounted && _online[n.id] != false) setState(() => _online[n.id] = false); return; }
    try {
      final res = await http.get(Uri.parse('http://${n.ip}/info'),
          headers: {'Authorization': 'Bearer ${n.pin}'}).timeout(const Duration(seconds: 3));
      if (!mounted) return;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() { _online[n.id] = true; _nodeData[n.id] = j; _nodeErr.remove(n.id); });
    } catch (_) {
      if (mounted && _online[n.id] != false) setState(() => _online[n.id] = false);
    }
  }

  Future<bool> _tryInfo(String ip, String id, String pin) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await http.get(Uri.parse('http://$ip/info'),
            headers: {'Authorization': 'Bearer $pin'}).timeout(const Duration(seconds: 6));
        if (!mounted) return true;
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() { _online[id] = true; _nodeData[id] = j; _nodeErr.remove(id); });
        return true;
      } catch (e) {
        Log.w('node', '/info $ip: ${e.toString().split('\n').first}');
        _nodeErr[id] = _simpleErr(e);
        if (attempt == 0) await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    return false;
  }

  String _simpleErr(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('timeout')) return tr('Nie odpowiada (offline?)');
    if (s.contains('socketexception') || s.contains('refused') ||
        s.contains('unreachable') || s.contains('failed host')) return tr('Poza siecią');
    if (s.contains('formatexception')) return tr('Błędna odpowiedź noda');
    return tr('Niedostępny');
  }

  // ── stan noda z chmury (ws_online = żywy WS; fallback last_ping) ──
  double? _beSecs(Map<String, dynamic>? be) {
    final s = be?['seconds_since_ping'];
    if (s == null) return null;
    return double.tryParse(s.toString());
  }
  String _ago(num secs) {
    if (secs < 60) return tr('przed chwilą');
    if (secs < 3600) return '${(secs / 60).floor()}m';
    if (secs < 86400) return '${(secs / 3600).floor()}h';
    return '${(secs / 86400).floor()}d';
  }

  int get _totalNodes => _myBeNodes.length;
  int get _reportingCount => _myBeNodes.where((n) => n['ws_online'] == true || (n['status'] == 'online')).length;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CoreBloc, CoreState>(builder: (context, state) {
      final list = _merged();
      return Scaffold(
        appBar: AppBar(
          title: Text(tr('Panel')),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: tr('Odśwież')),
            IconButton(icon: const Icon(Icons.add), tooltip: tr('Dodaj node'),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NodeManagerScreen()))),
          ],
        ),
        body: list.isEmpty
            ? _buildEmpty()
            : RefreshIndicator(
                onRefresh: _refresh,
                color: AppTheme.teal,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildGlobalStats(),
                    if (state.wallet == null) _noWalletBanner(),
                    const SizedBox(height: 16),
                    ...list.map(_buildCard),
                  ],
                ),
              ),
      );
    });
  }

  // RemoteTerminal (on-demand tunel + PIN gate) jest dopiero od FW > 0.70 — na starszych ukryj wejście.
  bool _fwGt(dynamic fw, double min) {
    final v = double.tryParse(fw?.toString() ?? '');
    return v != null && v > min;
  }

  Future<void> _loadKinds(String id) async {
    final k = await IntegrationStore.enabledKinds(id);
    if (mounted) setState(() => _kinds[id] = k);
  }

  // Rząd integracji: podpięte (tap → otwórz, long-press → odepnij) + „Dodaj".
  Widget _integrationsRow(String id, String name, Map<String, dynamic>? be, bool wsOnline) {
    final enabled = _kinds[id] ?? const <String>{};
    final fwOk = _fwGt(be?['firmware'], 0.70);
    final canOpen = wsOnline && context.read<CoreBloc>().state.wallet != null && fwOk;
    final hasAddable = IntegrationKind.values.any((k) => !enabled.contains(k.id));
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final kid in enabled)
        if (IntegrationKindX.fromId(kid) case final k?)
          OutlinedButton.icon(
            onPressed: canOpen ? () => _openIntegration(k, id, name) : null,
            onLongPress: () => _removeIntegration(id, k),
            icon: Icon(k.icon, size: 16),
            label: Text(tr(k.labelKey)),
            style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.teal,
                side: BorderSide(color: AppTheme.teal.withOpacity(0.5))),
          ),
      // „Dodaj" tylko gdy jest jeszcze co dodać (wszystko podpięte → chowamy)
      if (hasAddable)
        OutlinedButton.icon(
          onPressed: () => _addIntegration(id, name, be),
          icon: const Icon(Icons.add, size: 16),
          label: Text(tr('Dodaj')),
          style: OutlinedButton.styleFrom(foregroundColor: AppTheme.muted),
        ),
    ]);
  }

  void _openIntegration(IntegrationKind k, String id, String name) {
    final screen = switch (k) {
      IntegrationKind.terminal => TerminalScreen(deviceId: id, label: name),
      IntegrationKind.homeAssistant => HaPanelScreen(deviceId: id, label: name),
    };
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _addIntegration(String id, String name, Map<String, dynamic>? be) async {
    final fwOk = _fwGt(be?['firmware'], 0.70);
    final enabled = _kinds[id] ?? const <String>{};
    final addable = IntegrationKind.values.where((k) => !enabled.contains(k.id)).toList();
    final chosen = await showModalBottomSheet<IntegrationKind>(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(tr('Dodaj integrację'),
                style: const TextStyle(color: AppTheme.text, fontWeight: FontWeight.w600, fontSize: 15)),
          ),
          for (final k in addable)
            ListTile(
              leading: Icon(k.icon, color: AppTheme.teal),
              title: Text(tr(k.labelKey), style: const TextStyle(color: AppTheme.text)),
              subtitle: (k.needsTunnel && !fwOk)
                  ? Text(tr('Wymaga FW > 0.70'), style: const TextStyle(color: AppTheme.amber, fontSize: 12))
                  : null,
              enabled: !(k.needsTunnel && !fwOk),
              onTap: () => Navigator.pop(context, k),
            ),
          if (addable.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr('Wszystko już podpięte'), style: const TextStyle(color: AppTheme.muted)),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (chosen == null) return;
    if (chosen.needsConfig) {
      final saved = await Navigator.push<bool>(context, MaterialPageRoute(
          builder: (_) => HaSettingsScreen(deviceId: id, label: name)));
      if (saved != true) return; // anulował konfigurację → nie podpinaj
    }
    await IntegrationStore.setKind(id, chosen.id, true);
    await _loadKinds(id);
  }

  Future<void> _removeIntegration(String id, IntegrationKind k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Odpiąć integrację?'), style: const TextStyle(color: AppTheme.text)),
        content: Text(tr(k.labelKey), style: const TextStyle(color: AppTheme.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Anuluj'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Odepnij'))),
        ],
      ),
    );
    if (ok != true) return;
    await IntegrationStore.setKind(id, k.id, false);
    if (k == IntegrationKind.homeAssistant) await IntegrationStore.remove(id); // wyczyść binding HA
    await _loadKinds(id);
  }

  // ── Karta noda (zunifikowana) ──
  Widget _buildCard(_UnifiedNode u) {
    final be = u.be;
    final saved = u.saved;
    final id = u.id;
    final expanded = _expanded[id] ?? false;
    final name = (saved?.label.isNotEmpty == true && saved?.label != 'Node')
        ? saved!.label
        : (be?['city']?.toString().isNotEmpty == true
            ? be!['city'] as String
            : 'sensmos-${id.length >= 6 ? id.substring(0, 6) : id}');

    // Stan z chmury: ws_online (żywy WS) najpewniejszy; inaczej last_ping.
    final wsOnline = be?['ws_online'] == true;
    final secs = _beSecs(be);
    final healthColor = wsOnline ? AppTheme.teal
        : (secs != null && secs < 3600) ? Colors.amber.shade700 : AppTheme.muted;
    // „online" = żywe połączenie WS. Gdy node jest cichy (>3 min bez sygnału mimo połączenia)
    // dopisujemy kiedy ostatnio się odezwał — żeby „online" nie było gołym twierdzeniem.
    final healthText = wsOnline
        ? (secs != null && secs > 180 ? '${tr('online')} · ${_ago(secs)}' : tr('online'))
        : secs != null ? '${tr('cisza')} ${_ago(secs)}' : tr('brak danych z chmury');

    // Osiągalność lokalna (do akcji lokalnych)
    final localReachable = _online[id] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppTheme.border, width: 1)),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() => _expanded[id] = !expanded);
            if (!expanded) {
              _fetchBeData(id);
              _loadKinds(id);
              if (saved != null) _probeLocal(saved);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: healthColor)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(color: AppTheme.text, fontWeight: FontWeight.w500, fontSize: 14)),
                Text('${id.substring(0, id.length >= 8 ? 8 : id.length)} · fw ${be?['firmware'] ?? '?'}',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                Text(healthText, style: TextStyle(color: healthColor, fontSize: 11)),
              ])),
              // Reachability lokalna: „W tej sieci" (akcje lokalne) / „Zdalnie"
              _reachBadge(localReachable, saved != null),
              if (be?['located'] == false) ...[
                const SizedBox(width: 6),
                Icon(Icons.location_off, size: 15, color: Colors.amber.shade700),
              ],
              const SizedBox(width: 8),
              Icon(expanded ? Icons.expand_less : Icons.expand_more, color: AppTheme.muted, size: 20),
            ]),
          ),
        ),
        if (expanded) ...[
          const Divider(color: AppTheme.border, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // statystyki
              Row(children: [
                _stat('Scarcity', _scarcity[id] ?? '—'),
                const SizedBox(width: 16),
                _stat(tr('Sąsiedzi'), _beData[id]?['neighbors'] ?? '—'),
                const SizedBox(width: 16),
                _stat(tr('Promień'), _beData[id]?['radius'] ?? '—'),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16, color: AppTheme.muted),
                  tooltip: tr('Kopiuj ID'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: id));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(tr('ID skopiowane: %s', [id])), duration: const Duration(seconds: 2)));
                  },
                ),
              ]),
              const SizedBox(height: 14),

              // ── Integracje (opt-in: user dodaje tylko to, czego potrzebuje) ──
              _groupLabel(Icons.extension_outlined, tr('Integracje')),
              const SizedBox(height: 8),
              _integrationsRow(id, name, be, wsOnline),
              if (!wsOnline) Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(tr('Integracje wymagają noda online (połączonego z chmurą).'),
                    style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
              ),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                onPressed: () => _deleteFromNetwork(id),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: Text(tr('Usuń node z sieci')),
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6666),
                    side: const BorderSide(color: Color(0x55FF6666))),
              )),
              const SizedBox(height: 16),

              // ── Sieć lokalna (tylko w domu) ──
              _groupLabel(Icons.wifi, tr('Sieć lokalna (tylko w sieci noda)')),
              const SizedBox(height: 8),
              if (saved != null && localReachable) ...[
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => EntitiesScreen(ip: saved.ip, pin: saved.pin))),
                    icon: const Icon(Icons.sensors, size: 16),
                    label: Text(tr('Encje')),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.teal, side: const BorderSide(color: AppTheme.teal)),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => NodeConfigScreen(node: saved))),
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: Text(tr('Ustawienia')),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.text, side: const BorderSide(color: AppTheme.border)),
                  )),
                ]),
                if (be?['located'] == false) ...[
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: TextButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrustScreen(node: saved))),
                    icon: const Icon(Icons.add_location_alt, size: 18),
                    label: Text(tr('Ustaw lokalizację (BLE + GPS)')),
                    style: TextButton.styleFrom(foregroundColor: Colors.amber.shade700),
                  )),
                ],
                if (context.read<CoreBloc>().state.wallet == null) ...[
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: TextButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceScreen(node: saved))),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: Text(tr('Importuj portfel z noda')),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF6666)),
                  )),
                ],
              ] else _localLocked(saved != null),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _reachBadge(bool localReachable, bool hasLocal) {
    final label = localReachable ? tr('W tej sieci') : tr('Zdalnie');
    final color = localReachable ? AppTheme.teal : AppTheme.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(localReachable ? Icons.wifi : Icons.public, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ]),
    );
  }

  Widget _groupLabel(IconData icon, String text) => Row(children: [
        Icon(icon, size: 13, color: AppTheme.muted),
        const SizedBox(width: 6),
        Text(text.toUpperCase(),
            style: const TextStyle(color: AppTheme.muted, fontSize: 10.5, letterSpacing: 0.6, fontWeight: FontWeight.w600)),
      ]);

  Widget _localLocked(bool hasLocal) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppTheme.muted.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          const Icon(Icons.wifi_off, size: 16, color: AppTheme.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(
            hasLocal
                ? tr('Połącz telefon z siecią WiFi noda, żeby zobaczyć encje i zmienić ustawienia.')
                : tr('Ten node nie jest dodany lokalnie — połącz się z jego siecią i dodaj go, by konfigurować.'),
            style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
        ]),
      );

  // ── Statystyki globalne ──
  Widget _buildGlobalStats() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
      child: Row(children: [
        _globalStat(Icons.sensors, '$_reportingCount/$_totalNodes', tr('Online')),
        _divider(),
        _globalStat(Icons.location_on_outlined,
            '${_myBeNodes.where((n) => n['located'] == true).length}', tr('Z lokalizacją')),
        _divider(),
        context.read<CoreBloc>().state.wallet == null
            ? _importWalletStat()
            : _globalStat(Icons.account_balance_wallet_outlined,
                _balance ?? _beData.values.firstOrNull?['balance'] ?? '—', tr('GALU saldo'),
                valueColor: const Color(0xFFE89B3F)),
      ]),
    );
  }

  Widget _importWalletStat() => Expanded(child: Column(children: [
        const Icon(Icons.account_balance_wallet_outlined, color: AppTheme.muted, size: 20),
        const SizedBox(height: 4),
        const Text('—', style: TextStyle(color: AppTheme.muted, fontSize: 16, fontWeight: FontWeight.bold)),
        Text(tr('brak portfela'), style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      ]));

  Widget _noWalletBanner() => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFF4444).withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFF4444).withOpacity(0.35)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF4444), size: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Aplikacja nie ma przypisanego portfela'),
                style: const TextStyle(color: Color(0xFFFF4444), fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(tr('Zaimportuj go z klucza (zakladka Portfel) lub z noda '
                    '(rozwin swoj node ponizej -> Importuj portfel z noda).'),
                style: const TextStyle(color: AppTheme.muted, fontSize: 12.5, height: 1.35)),
          ])),
        ]),
      );

  Widget _globalStat(IconData icon, String value, String label, {Color? valueColor}) =>
      Expanded(child: Column(children: [
        Icon(icon, color: AppTheme.teal, size: 20),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: valueColor ?? AppTheme.text, fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      ]));

  Widget _divider() => Container(width: 1, height: 40, color: AppTheme.border, margin: const EdgeInsets.symmetric(horizontal: 8));

  Widget _stat(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: AppTheme.text, fontSize: 14, fontWeight: FontWeight.w500)),
      ]);

  Widget _buildEmpty() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.sensors_off, color: AppTheme.muted, size: 48),
          const SizedBox(height: 16),
          Text(tr('Brak nodów'), style: const TextStyle(color: AppTheme.text, fontSize: 16)),
          const SizedBox(height: 8),
          Text(tr('Dodaj node przez BLE'), style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SetupScreen())),
            icon: const Icon(Icons.add),
            label: Text(tr('Dodaj node')),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.teal, foregroundColor: AppTheme.bg),
          ),
        ]),
      );
}

class _UnifiedNode {
  final String id;
  final Map<String, dynamic>? be;
  final SavedNode? saved;
  _UnifiedNode({required this.id, this.be, this.saved});
}
