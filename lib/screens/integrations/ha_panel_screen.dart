import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../../services/wallet_service.dart';
import '../../services/terminal_relay.dart';
import '../../services/integrations/http_over_tunnel.dart';
import '../../services/integrations/home_integration.dart';
import '../../services/integrations/ha_integration.dart';
import '../../services/integrations/integration_store.dart';
import '../../util/pin_gate.dart';
import 'ha_settings_screen.dart';

enum _Phase { connecting, ready, error }

/// Panel HA — „bieda-NabuCasa": 1 tunel do HA w LAN noda, REST API + polling, natywne kafelki.
/// Live editor: ołówek → tryb edycji na żywym widoku (dodaj/usuń kafelek). Zero FW.
class HaPanelScreen extends StatefulWidget {
  final String deviceId;
  final String label;
  const HaPanelScreen({super.key, required this.deviceId, required this.label});

  @override
  State<HaPanelScreen> createState() => _HaPanelScreenState();
}

class _HaPanelScreenState extends State<HaPanelScreen> {
  _Phase _phase = _Phase.connecting;
  String _status = '';
  TerminalRelay? _relay;
  HttpOverTunnel? _http;
  HaIntegration? _ha;
  HaBinding? _binding;
  StreamSubscription? _evSub;
  Timer? _poll;
  bool _editing = false;
  bool _polling = false;
  final Map<String, Thing> _states = {};
  List<Thing>? _allThings; // cache pełnej listy encji (picker) — pobrana raz na sesję (throttle tunelu)

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    // retry: posprzątaj poprzednią próbę (inaczej stary relay/listener/timer wiszą i dublują się)
    _poll?.cancel(); _poll = null;
    _evSub?.cancel(); _evSub = null;
    _http?.close(); _http = null;
    _relay?.dispose(); _relay = null;
    _allThings = null; // świeże połączenie = świeża lista encji
    setState(() { _phase = _Phase.connecting; _status = tr('Łączę z HA…'); });
    try {
      final binding = await IntegrationStore.load(widget.deviceId);
      if (binding == null || binding.host.isEmpty || binding.token.isEmpty) {
        // brak konfiguracji → do ustawień
        if (!mounted) return;
        final saved = await Navigator.push<bool>(context, MaterialPageRoute(
            builder: (_) => HaSettingsScreen(deviceId: widget.deviceId, label: widget.label)));
        if (saved == true) { _connect(); } else if (mounted) Navigator.pop(context);
        return;
      }
      _binding = binding;

      final wallet = await context.read<WalletService>().load();
      if (wallet == null) throw Exception(tr('Brak portfela w apce'));
      final relay = TerminalRelay(
        deviceId: widget.deviceId,
        owner: wallet.address,
        signMessage: (m) => context.read<WalletService>().signMessage(m),
      );
      _relay = relay;
      _evSub = relay.events.listen(_onRelayEvent);
      await relay.connect();
      if (!mounted) return;
      if (!relay.nodeOnline) {
        setState(() { _phase = _Phase.error; _status = tr('Node jest offline — wróci gdy odzyska sieć.'); });
        return;
      }
      // dostęp do LAN = PIN-gate (jak terminal); jeśli już włączony, nie pytamy ponownie.
      // confirmNodePin ponawia zły PIN wewnątrz dialogu; false = user ANULOWAŁ → wyjście z panelu
      // (a nie error→retry→PIN, co dawało pętlę).
      if (!relay.remoteEnabled) {
        if (!await confirmNodePin(context, widget.deviceId)) {
          if (mounted) Navigator.pop(context);
          return;
        }
        relay.setRemote(true);
      }

      final sock = await relay.openTunnel(binding.host, binding.port);
      _http = HttpOverTunnel(sock, '${binding.host}:${binding.port}');
      _ha = HaIntegration(binding.token);

      final ok = await _ha!.ping(_http!);
      if (!ok) throw Exception(tr('HA nie odpowiada — sprawdź adres i token'));

      if (!mounted) return;
      setState(() { _phase = _Phase.ready; _status = ''; });
      await _refreshNow();
      _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refreshNow());
    } catch (e) {
      if (!mounted) return;
      setState(() { _phase = _Phase.error; _status = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  void _onRelayEvent(String ev) {
    if (!mounted) return;
    if (ev.startsWith('down:')) {
      setState(() { _phase = _Phase.error; _status = tr('Połączenie zerwane — dotknij „Spróbuj ponownie".'); });
    }
  }

  Future<void> _refreshNow() async {
    final ha = _ha, http = _http, binding = _binding;
    if (ha == null || http == null || binding == null || _polling) return;
    final ids = binding.tiles.map((t) => t.thingId).toList();
    if (ids.isEmpty) return;
    _polling = true;
    try {
      final things = await ha.refresh(http, ids);
      if (!mounted) return;
      setState(() { for (final t in things) _states[t.id] = t; });
    } catch (_) {/* pojedynczy poll może paść — następny naprawi */}
    finally { _polling = false; }
  }

  Future<void> _toggle(Tile tile, bool on) async {
    final ha = _ha, http = _http;
    if (ha == null || http == null) return;
    final cur = _states[tile.thingId];
    if (cur != null) {
      setState(() => _states[tile.thingId] = Thing(
          id: cur.id, name: cur.name, kind: cur.kind, state: on ? 'on' : 'off',
          unit: cur.unit, controllable: cur.controllable, on: on)); // optymistycznie
    }
    try {
      await ha.actuate(http, tile.thingId, on);
    } catch (_) {}
    await _refreshNow();
  }

  Future<void> _addTile() async {
    final ha = _ha, http = _http, binding = _binding;
    if (ha == null || http == null || binding == null) return;
    // 1) natychmiast z cache DYSKOWEGO (jeśli jest) — bez sieci. 2) inaczej pobierz raz + zapisz.
    _allThings ??= await IntegrationStore.loadEntities(widget.deviceId);
    if (_allThings == null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: AppTheme.teal)),
      );
      try {
        _allThings = await ha.discover(http);
        await IntegrationStore.saveEntities(widget.deviceId, _allThings!);
      } catch (_) {
        if (mounted) Navigator.pop(context);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('Nie udało się pobrać encji'))));
        return;
      }
      if (mounted) Navigator.pop(context);
    }
    if (!mounted) return;
    final picked = await Navigator.push<Thing>(context, MaterialPageRoute(
        builder: (_) => _EntityPickerScreen(all: _allThings!, onRefresh: _refetchEntities)));
    if (picked == null) return;
    binding.tiles.add(Tile(thingId: picked.id, type: ha.suggest(picked), label: picked.name));
    await IntegrationStore.save(widget.deviceId, binding);
    if (!mounted) return;
    setState(() {});
    _refreshNow();
  }

  // Odśwież katalog encji z HA (na żądanie z pickera) + zapisz do cache dyskowego.
  Future<List<Thing>> _refetchEntities() async {
    final ha = _ha, http = _http;
    if (ha == null || http == null) return _allThings ?? [];
    final fresh = await ha.discover(http);
    _allThings = fresh;
    await IntegrationStore.saveEntities(widget.deviceId, fresh);
    return fresh;
  }

  Future<void> _renameTile(Tile t) async {
    final ctrl = TextEditingController(text: t.label);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Nazwa kafelka'), style: const TextStyle(color: AppTheme.text)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppTheme.text),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: Text(tr('Anuluj'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(tr('OK'))),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    setState(() => t.label = name.trim());
    if (_binding != null) await IntegrationStore.save(widget.deviceId, _binding!);
  }

  Future<void> _removeTile(Tile tile) async {
    final binding = _binding;
    if (binding == null) return;
    binding.tiles.removeWhere((t) => t.thingId == tile.thingId && t.label == tile.label);
    await IntegrationStore.save(widget.deviceId, binding);
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _poll?.cancel();
    _evSub?.cancel();
    _http?.close();
    _relay?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text('${tr('Panel HA')} · ${widget.label}'),
        actions: [
          if (_phase == _Phase.ready)
            IconButton(
              icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
              tooltip: _editing ? tr('Gotowe') : tr('Edytuj'),
              onPressed: () => setState(() => _editing = !_editing),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: tr('Ustawienia HA'),
            onPressed: () async {
              final saved = await Navigator.push<bool>(context, MaterialPageRoute(
                  builder: (_) => HaSettingsScreen(deviceId: widget.deviceId, label: widget.label)));
              if (saved == true) _connect();
            },
          ),
        ],
      ),
      body: switch (_phase) {
        _Phase.connecting => _center(const CircularProgressIndicator(color: AppTheme.teal)),
        _Phase.error => _errorView(),
        _Phase.ready => _dashboard(),
      },
    );
  }

  Widget _center(Widget w) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          w,
          if (_status.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 16),
                child: Text(_status, style: const TextStyle(color: AppTheme.muted))),
        ]),
      );

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: AppTheme.amber, size: 40),
            const SizedBox(height: 12),
            Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.text)),
            const SizedBox(height: 20),
            FilledButton(onPressed: _connect, child: Text(tr('Spróbuj ponownie'))),
          ]),
        ),
      );

  Widget _dashboard() {
    final tiles = _binding?.tiles ?? [];
    if (tiles.isEmpty && !_editing) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.dashboard_customize_outlined, color: AppTheme.muted, size: 40),
          const SizedBox(height: 12),
          Text(tr('Pusty dashboard'), style: const TextStyle(color: AppTheme.text)),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => setState(() => _editing = true),
            icon: const Icon(Icons.add),
            label: Text(tr('Dodaj kafelek')),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.teal, foregroundColor: Colors.black),
          ),
        ]),
      );
    }
    return GridView.count(
      padding: const EdgeInsets.all(12),
      crossAxisCount: 2,
      childAspectRatio: 1.7,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: [
        for (final t in tiles) _tile(t),
        if (_editing) _addCard(),
      ],
    );
  }

  Widget _addCard() => InkWell(
        onTap: _addTile,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.muted.withOpacity(0.4), style: BorderStyle.solid),
          ),
          child: const Center(child: Icon(Icons.add, color: AppTheme.muted, size: 28)),
        ),
      );

  Widget _tile(Tile t) {
    final st = _states[t.thingId];
    return GestureDetector(
      onTap: _editing ? () => _renameTile(t) : null, // w edycji: tap = zmień nazwę
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12)),
        child: Stack(children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Expanded(child: Text(t.label,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.text, fontWeight: FontWeight.w500, fontSize: 13))),
                if (_editing) const Icon(Icons.edit, color: AppTheme.muted, size: 14),
              ]),
              if (t.type == TileType.toggle)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Switch(
                    value: st?.on ?? false,
                    activeThumbColor: AppTheme.teal,
                    onChanged: (_editing || st == null) ? null : (v) => _toggle(t, v),
                  ),
                )
              else
                Text(
                  st == null ? '—' : '${st.state ?? '—'}${st.unit != null ? ' ${st.unit}' : ''}',
                  style: const TextStyle(color: AppTheme.teal, fontWeight: FontWeight.w600, fontSize: 20),
                ),
            ],
          ),
          if (_editing)
            Positioned(
              top: -4, right: -4,
              child: IconButton(
                icon: const Icon(Icons.remove_circle, color: Color(0xFFFF6666), size: 20),
                onPressed: () => _removeTile(t),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Picker encji HA — pełnoekranowy (Scaffold sam ogarnia klawiaturę, koniec nachodzenia na
/// status bar). Lista z wyszukiwarką (to jest ta „wyszukiwarka encji") + odświeżanie katalogu.
class _EntityPickerScreen extends StatefulWidget {
  final List<Thing> all;
  final Future<List<Thing>> Function() onRefresh;
  const _EntityPickerScreen({required this.all, required this.onRefresh});
  @override
  State<_EntityPickerScreen> createState() => _EntityPickerScreenState();
}

class _EntityPickerScreenState extends State<_EntityPickerScreen> {
  late List<Thing> _all = widget.all;
  String _q = '';
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final fresh = await widget.onRefresh();
      if (mounted) setState(() => _all = fresh);
    } catch (_) {}
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final items = q.isEmpty
        ? _all
        : _all.where((t) => t.name.toLowerCase().contains(q) || t.id.toLowerCase().contains(q)).toList();
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(tr('Dodaj kafelek')),
        actions: [
          IconButton(
            icon: _refreshing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.teal))
                : const Icon(Icons.refresh),
            tooltip: tr('Odśwież encje z HA'),
            onPressed: _refreshing ? null : _refresh,
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            autofocus: true,
            style: const TextStyle(color: AppTheme.text),
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              hintText: tr('Szukaj encji…'),
              prefixIcon: const Icon(Icons.search, color: AppTheme.muted),
              filled: true, fillColor: AppTheme.card,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final t = items[i];
              return ListTile(
                title: Text(t.name, style: const TextStyle(color: AppTheme.text)),
                subtitle: Text(t.id, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                trailing: Icon(t.controllable ? Icons.toggle_on_outlined : Icons.speed,
                    color: AppTheme.muted, size: 20),
                onTap: () => Navigator.pop(context, t),
              );
            },
          ),
        ),
      ]),
    );
  }
}
