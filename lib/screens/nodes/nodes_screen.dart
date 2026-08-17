import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FontFeature;
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
import '../../services/pairing_service.dart';
import '../../util/pair_gate.dart';
import '../../widgets/news_section.dart';
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
  final _paired = <String, bool>{}; // czy TEN telefon ma klucz do noda (tunel bez niego nie ruszy)
  int _tick = 0;                    // licznik ticków pollingu (saldo rzadziej niż status online)
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
      // Saldo to DRUGIE, niezależne źródło tej samej liczby co w Portfelu. Bez tego po claimie
      // kafel trzymał kwotę sprzed operacji aż do pull-to-refresh albo restartu apki.
      // Co 3. tick (30 s) — saldo nie potrzebuje granulacji statusu online.
      if (++_tick % 3 == 0) _fetchBalance();
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
    // Stała kolejność po ID. BE sortuje po last_ping, więc kafle skakały przy każdym
    // odświeżeniu i nie dało się trafić w ten, który się chciało otworzyć.
    out.sort((a, b) => a.id.compareTo(b.id));
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

  String? _searching;   // device_id noda, dla którego trwa szukanie po mDNS

  // Odnalezienie noda w LAN po fakcie. Potrzebne, gdy onboarding poszedł po LTE:
  // telefon nigdy nie był z nodem w jednej sieci, więc nie miał skąd wziąć IP,
  // a późniejszy powrót na WiFi sam z siebie tego nie naprawia.
  Future<void> _findLocally(String id) async {
    setState(() => _searching = id);
    final ble = context.read<BleService>();
    final ns  = context.read<NodeService>();
    final short = id.length >= 6 ? id.substring(0, 6) : id;
    String? ip;
    try {
      ip = await ble.discoverByHostname(
          hostname: 'sensmos-$short', timeout: const Duration(seconds: 12));
    } catch (e) {
      Log.w('nodes', 'mDNS $short: $e');
    }
    if (!mounted) return;
    setState(() => _searching = null);

    if (ip == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppTheme.amber,
        duration: const Duration(seconds: 6),
        content: Text(
            tr('Nie znaleziono noda w tej sieci. Upewnij się, że telefon jest '
               'w tej samej sieci WiFi co node.'),
            style: const TextStyle(color: Colors.black)),
      ));
      return;
    }

    final pin = await _askPin();
    if (pin == null || !mounted) return;
    await ns.saveNode(ip, pin, id);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr('Node znaleziony: %s', [ip!]))));
  }

  Future<String?> _askPin() async {
    final ctrl = TextEditingController(text: '123456');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Podaj PIN noda')),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(labelText: tr('PIN noda')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Anuluj'))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(tr('Zapisz'))),
        ],
      ),
    );
  }

  // Komunikat „czemu ten node zarabia inaczej". Bez tego user widział spadek nagród
  // i nie miał jak się dowiedzieć, że zabrakło potwierdzenia GPS.
  Widget _geoNotice(bool ghost) {
    final color = ghost ? const Color(0xFF3B82F6) : const Color(0xFFFF4444);
    final text = ghost
        ? tr('Tryb prywatny — node nie jest pokazywany na mapie i zarabia w obniżonej '
             'stawce, bo nie współtworzy publicznego pokrycia sieci.')
        : tr('Brak potwierdzonej lokalizacji GPS — ten node prawie nie zarabia. '
             'Podejdź do niego z telefonem i ustaw lokalizację.');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ghost ? Icons.visibility_off_outlined : Icons.location_off, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text,
            style: TextStyle(color: color, fontSize: 12, height: 1.35))),
      ]),
    );
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

  // Zapomnij node WYLACZNIE lokalnie — nie rusza BE. Dla wpisow, ktorych nie da sie
  // skasowac z sieci, bo naleza do innego portfela (zmiana tozsamosci, cudza plytka).
  Future<void> _forgetLocally(String id) async {
    final short = id.length > 8 ? '${id.substring(0, 8)}…' : id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Usunąć z aplikacji?')),
        content: Text(tr('Node %s zniknie z tej listy. W sieci SENSMOS zostaje bez zmian — '
                         'nie należy do Twojego portfela, więc nie możesz go stamtąd usunąć.', [short])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Anuluj'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Usuń z aplikacji'), style: const TextStyle(color: Color(0xFFFF6666)))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    context.read<CoreBloc>().add(NodeRemoved(id));
    setState(() { _expanded.remove(id); _online.remove(id); _nodeData.remove(id); });
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Usunięto z aplikacji: %s', [short]))));
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
      if (!_identityOk(j, n.id)) {
        _identityMismatch(n.id, j);
        setState(() { _online[n.id] = false; _nodeData.remove(n.id); });
        return;
      }
      setState(() { _online[n.id] = true; _nodeData[n.id] = j; _nodeErr.remove(n.id); });
    } catch (_) {
      if (mounted && _online[n.id] != false) setState(() => _online[n.id] = false);
    }
  }

  // Czy pod tym adresem stoi TEN node. Po przeflashowaniu płytka dostaje nową tożsamość,
  // a stary wpis lokalny nadal wskazuje to samo IP — bez tego sprawdzenia apka uznawała
  // osierocony node za żywy i wysyłała komendy do zupełnie innego urządzenia.
  bool _identityOk(Map<String, dynamic> j, String expectedId) {
    final got = j['device_id']?.toString() ?? '';
    return got.isEmpty || got == expectedId;   // starsze FW bez pola → nie blokuj
  }

  void _identityMismatch(String id, Map<String, dynamic> j) {
    final got = j['device_id']?.toString() ?? '?';
    _nodeErr[id] = tr('Pod tym adresem jest inny node (%s) — ta płytka została przeflashowana '
                      'i ma nową tożsamość.', [got.length >= 8 ? got.substring(0, 8) : got]);
  }

  Future<bool> _tryInfo(String ip, String id, String pin) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await http.get(Uri.parse('http://$ip/info'),
            headers: {'Authorization': 'Bearer $pin'}).timeout(const Duration(seconds: 6));
        if (!mounted) return true;
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        if (!_identityOk(j, id)) {
          _identityMismatch(id, j);
          setState(() { _online[id] = false; _nodeData.remove(id); });
          return false;   // bez retry: to nie jest problem łączności
        }
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
                    // Aktualności pod portfelem, nad listą nodów. Gdy nie ma wpisów, widget
                    // ma zerowy rozmiar i niczego tu nie przesuwa. Adres portfela decyduje
                    // o wpisach celowanych (kraj / wersja FW / konkretne portfele).
                    NewsSection(owner: state.wallet?.address),
                    ...list.map(_buildCard),
                  ],
                ),
              ),
      );
    });
  }

  // RemoteTerminal (on-demand tunel + PIN gate) jest dopiero od FW > 0.70 — na starszych ukryj wejście.
  bool _fwGt(dynamic fw, double min) {
    // Wersja bywa z sufiksem gałęzi ('0.80-lora6', '0.80-fsk3') — double.tryParse zwracał wtedy
    // null i node z LoRy wyglądał na starszy niż 0.70, więc integracje były dla niego zablokowane
    // mimo firmware 0.80. Bierzemy sam prefiks major.minor.
    final m = RegExp(r'^\d+\.\d+').firstMatch(fw?.toString() ?? '');
    final v = m == null ? null : double.tryParse(m.group(0)!);
    return v != null && v > min;
  }

  Future<void> _loadKinds(String id) async {
    final k = await IntegrationStore.enabledKinds(id);
    final p = await PairingService().hasAccess(id);
    if (mounted) setState(() { _kinds[id] = k; _paired[id] = p; });
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
    final paired = _paired[id] == true;
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
              // Warunki wstępne wprost przy wyborze. FW jest twardy (blokuje), parowanie tylko
              // uprzedza — da się je zrobić po dodaniu, byle w sieci noda.
              subtitle: (k.needsTunnel && !fwOk)
                  ? Text(tr('Wymaga FW > 0.70'), style: const TextStyle(color: AppTheme.amber, fontSize: 12))
                  : (k.needsTunnel && !paired)
                      ? Text(tr('Wymaga sparowania noda — tylko w jego sieci WiFi'),
                          style: const TextStyle(color: AppTheme.amber, fontSize: 12))
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
    if (!mounted) return;   // sheet mógł się zamknąć razem z ekranem — dalej idzie context
    // Parowanie ZARAZ po wyborze, póki user jest w sieci noda — a jest, bo integracje dodaje się
    // zwykle tuż po onboardingu, w domu. Odłożenie tego do pierwszego użycia znaczy, że o wymogu
    // dowie się z wakacji, gdzie klucza nie ma jak zapisać (kanał jest wyłącznie lokalny).
    if (chosen.needsTunnel && _paired[id] != true) {
      if (_online[id] == true) {
        await ensurePaired(context, id);
        if (!mounted) return;
        setState(() => _paired[id] = true);
        _loadKinds(id);   // stan z magazynu — ensurePaired mogło zostać anulowane
      } else {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.card,
            title: Text(tr('Wymagane sparowanie'), style: const TextStyle(color: AppTheme.text)),
            content: Text(
              tr('Ta integracja otwiera tunel do Twojej sieci, a zgodę na to daje sam node — nie nasz '
                 'serwer. Trzeba zapisać w nim klucz, będąc w tej samej sieci WiFi: '
                 'Ustawienia noda → Zdalny dostęp.\n\nIntegrację dodam już teraz, ale połączy się '
                 'dopiero po sparowaniu.'),
              style: const TextStyle(color: AppTheme.muted)),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Rozumiem'))),
            ],
          ),
        );
        if (!mounted) return;
      }
    }
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
              // Ghost = niebieski, jak na mapie (tam blue to node bez potwierdzonej
              // pozycji publicznej). Stan łączności nie ginie — jest wypisany tekstem
              // w linijce pod spodem.
              Container(width: 10, height: 10, decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: be?['ghost'] == true ? const Color(0xFF3B82F6) : healthColor)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ID na pierwszym planie — to ono identyfikuje node jednoznacznie,
                // a miejscowość bywa ta sama dla kilku sztuk albo pusta.
                // Ikonki stanu w prawym rogu TEJ linii, a nie w głównym rzędzie —
                // tam konkurowały o szerokość z badge'em i strzałką i nic się nie mieściło.
                // ID + firmware jako JEDEN Text z elipsą wewnątrz Expanded. Wcześniej były
                // to dwa Texty w zagnieżdżonym Row — przy ciasnym kafelku ten Row przepełniał
                // się i malował po ikonach, które przez to siedziały na napisie „fw 0.79".
                // Text z ellipsis nie wyjdzie poza swój box niezależnie od szerokości.
                Row(children: [
                  Expanded(child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: id.substring(0, id.length >= 8 ? 8 : id.length).toUpperCase(),
                          style: const TextStyle(color: AppTheme.text, fontWeight: FontWeight.w600,
                              fontSize: 14, letterSpacing: 0.6)),
                      TextSpan(text: '   fw ${be?['firmware'] ?? '?'}',
                          style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                    ]),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  )),
                  if (be != null && be['geo_state'] != 'gps')
                    const Padding(padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.location_off, size: 15, color: Color(0xFFFF4444))),
                  if (be?['ghost'] == true)
                    const Padding(padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.visibility_off_outlined, size: 15, color: Color(0xFF3B82F6))),
                ]),
                // Linia 2: miejscowość z lewej, znacznik sieci z prawej. Badge zszedł
                // z głównego rzędu — tam zabierał szerokość wszystkim trzem liniom naraz
                // i to on wypychał ikony na tekst pierwszej linii.
                Row(children: [
                  Expanded(child: Text(name,
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  _reachBadge(localReachable, saved != null),
                ]),
                Text(healthText, style: TextStyle(color: healthColor, fontSize: 11),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
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
              // Statystyki. Elastyczne, bo na wąskich ekranach (starsze telefony) sztywne
              // odstępy + Spacer wypychały „Pełne ID / Kopiuj" poza kartę.
              Row(children: [
                Expanded(child: _stat('Scarcity', _scarcity[id] ?? '—')),
                Expanded(child: _stat(tr('Sąsiedzi'), _beData[id]?['neighbors'] ?? '—')),
                Expanded(child: _stat(tr('Promień'), _beData[id]?['radius'] ?? '—')),
                const SizedBox(width: 8),
                // Wcześniej sama ikonka kopiowania obok trzech opisanych statystyk —
                // nie było wiadomo, czego dotyczy. Teraz podpisana jak reszta.
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: id));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(tr('ID skopiowane: %s', [id])), duration: const Duration(seconds: 2)));
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(tr('Pełne ID'),
                          style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                      const SizedBox(height: 2),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(tr('Kopiuj'), style: const TextStyle(
                            color: AppTheme.teal, fontSize: 13, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 4),
                        const Icon(Icons.copy, size: 14, color: AppTheme.teal),
                      ]),
                    ]),
                  ),
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
              // Ostrzeżenie zostaje na karcie, a nie znika razem z bottom-sheetem — user widzi je
              // za każdym razem, gdy jest w domu, a nie dopiero gdy tunel odmówi z wakacji.
              if (_paired[id] != true && (_kinds[id]?.isNotEmpty ?? false)) Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(tr('Node niesparowany — tunel nie ruszy. Sparuj, będąc w jego sieci WiFi.'),
                    style: const TextStyle(color: AppTheme.amber, fontSize: 11)),
              ),
              const SizedBox(height: 14),
              // Dwie ROZNE operacje, wiec dwa osobne przyciski obok siebie:
              //   z sieci  — kasuje w BE, wymaga podpisu portfelem WLASCICIELA
              //   z listy  — czysci tylko lokalny wpis w tej apce, BE nietkniete
              // Bez tego drugiego porzucony node (zmieniona tozsamosc, inny portfel)
              // zostawal na liscie na zawsze, bo pierwszego nie da sie wykonac.
              Row(children: [
                // FittedBox zamiast ellipsis: „Remove from network" ma się zmniejszyć,
                // a nie zostać przycięte do „Remov…" (bez tego etykieta traci sens).
                Expanded(child: OutlinedButton.icon(
                  onPressed: () => _deleteFromNetwork(id),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('Usuń z sieci'), maxLines: 1)),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: const Color(0xFFFF6666),
                      side: const BorderSide(color: Color(0x55FF6666))),
                )),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(
                  onPressed: saved == null ? null : () => _forgetLocally(id),
                  icon: const Icon(Icons.playlist_remove, size: 16),
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('Usuń z listy'), maxLines: 1)),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: AppTheme.amber,
                      side: BorderSide(color: AppTheme.amber.withOpacity(0.35))),
                )),
              ]),
              const SizedBox(height: 16),

              // ── Sieć lokalna (tylko w domu) ──
              _groupLabel(Icons.wifi, tr('Sieć lokalna (tylko w sieci noda)')),
              // Adres IP wprost, z kopiowaniem — potrzebny wszędzie tam, gdzie wpisuje się
              // go ręcznie (np. integracja w Home Assistancie), a dotąd nigdzie go nie było.
              if (saved != null && saved.ip.isNotEmpty) ...[
                const SizedBox(height: 6),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: saved.ip));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        duration: const Duration(seconds: 2),
                        content: Text(tr('Skopiowano %s', [saved.ip]))));
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      const Icon(Icons.lan_outlined, size: 14, color: AppTheme.muted),
                      const SizedBox(width: 6),
                      Text('${tr('Adres IP')}:  ',
                          style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                      Text(saved.ip, style: const TextStyle(
                          color: AppTheme.text, fontSize: 13,
                          fontFeatures: [FontFeature.tabularFigures()])),
                      const SizedBox(width: 6),
                      const Icon(Icons.copy, size: 13, color: AppTheme.teal),
                    ]),
                  ),
                ),
              ],
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
                // Dlaczego node zarabia mało albo wcale — wprost, zamiast samej ikonki.
                // Oba powody mogą wystąpić naraz i wtedy oba są pokazywane: brak GPS
                // jest ważniejszy (kosztuje więcej), więc idzie pierwszy.
                if (be != null && be['geo_state'] != null && be['geo_state'] != 'gps') ...[
                  const SizedBox(height: 10),
                  _geoNotice(false),
                ],
                if (be?['ghost'] == true) ...[
                  const SizedBox(height: 8),
                  _geoNotice(true),
                ],
                if (be != null && be['geo_state'] != 'gps') ...[
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
              ] else _localLocked(saved != null, id),
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

  // Nagłówek sekcji zawija się zamiast uciekać poza kartę — „SIEĆ LOKALNA (TYLKO W SIECI
  // NODA)" po angielsku jest długie i na wąskim ekranie nie mieści się w jednej linii.
  Widget _groupLabel(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 13, color: AppTheme.muted)),
          const SizedBox(width: 6),
          Expanded(child: Text(text.toUpperCase(),
              style: const TextStyle(color: AppTheme.muted, fontSize: 10.5, letterSpacing: 0.6, fontWeight: FontWeight.w600))),
        ]);

  Widget _localLocked(bool hasLocal, [String? id]) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppTheme.muted.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.wifi_off, size: 16, color: AppTheme.muted),
            const SizedBox(width: 8),
            Expanded(child: Text(
              hasLocal
                  ? tr('Połącz telefon z siecią WiFi noda, żeby zobaczyć encje i zmienić ustawienia.')
                  : tr('Ten node nie ma zapisanego adresu IP — apka zna go tylko z chmury. '
                       'Połącz telefon z siecią noda i wyszukaj go lokalnie.'),
              style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
          ]),
          // Typowy przypadek: atestacja poszła po LTE, więc telefon nigdy nie widział
          // noda w LAN i nie było czego zapisać. Sam powrót na WiFi tego nie naprawia —
          // trzeba go raz odnaleźć po mDNS.
          if (!hasLocal && id != null) ...[
            const SizedBox(height: 6),
            SizedBox(width: double.infinity, child: TextButton.icon(
              onPressed: _searching == id ? null : () => _findLocally(id),
              icon: _searching == id
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.teal))
                  : const Icon(Icons.travel_explore, size: 18),
              label: Text(_searching == id
                  ? tr('Szukam w sieci...')
                  : tr('Wyszukaj noda w tej sieci')),
              style: TextButton.styleFrom(foregroundColor: AppTheme.teal),
            )),
          ],
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
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
        const SizedBox(height: 2),
        // scaleDown zamiast ucinania: „200.0 km" ma się zmieścić, a nie zamienić w „200…"
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(value, maxLines: 1,
              style: const TextStyle(color: AppTheme.text, fontSize: 14, fontWeight: FontWeight.w500))),
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
