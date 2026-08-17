import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../../services/wallet_service.dart';
import '../../services/terminal_relay.dart';
import '../../util/pair_gate.dart';
import '../../services/integrations/http_over_tunnel.dart';
import '../../services/integrations/home_integration.dart';
import '../../services/integrations/ha_integration.dart';
import '../../services/integrations/integration_store.dart';
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
  // Sparkline: historia z HA pobierana RAZ na wejście (tunel jest wąski), potem dokładamy
  // wartości z pollingu — wykres żyje bez dodatkowych requestów.
  final Map<String, List<double>> _hist = {};
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

      // Klucz parowania — bez niego node odmówi otwarcia tunelu. Jednorazowo wymaga bycia
      // w tej samej sieci WiFi co node (patrz pair_gate); potem leży w bezpiecznym magazynie.
      if (!mounted) return;
      final acc = await ensurePaired(context, widget.deviceId);
      if (!mounted) return;
      if (!acc.ok) { Navigator.pop(context); return; }

      final relay = TerminalRelay(
        deviceId: widget.deviceId,
        owner: wallet.address,
        signMessage: (m) => context.read<WalletService>().signMessage(m),
        pairKey: acc.key,
        legacy: acc.legacy,
      );
      _relay = relay;
      _evSub = relay.events.listen(_onRelayEvent);
      await relay.connect();
      if (!mounted) return;
      if (!relay.nodeOnline) {
        setState(() { _phase = _Phase.error; _status = tr('Node jest offline — wróci gdy odzyska sieć.'); });
        return;
      }

      final sock = await relay.openTunnel(binding.host, binding.port);
      _http = HttpOverTunnel(sock, '${binding.host}:${binding.port}');
      _ha = HaIntegration(binding.token);

      final ok = await _ha!.ping(_http!);
      if (!ok) throw Exception(tr('HA nie odpowiada — sprawdź adres i token'));

      if (!mounted) return;
      setState(() { _phase = _Phase.ready; _status = ''; });
      await _refreshNow();
      _loadHistory();   // w tle — wykresy dorysują się same, panel nie czeka
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
      setState(() {
        for (final t in things) {
          _states[t.id] = t;
          // dokładaj do sparkline tylko realne zmiany wartości (inaczej płaska linia z pollingu)
          final v = t.numeric;
          final h = _hist[t.id];
          if (v != null && h != null && (h.isEmpty || h.last != v)) {
            h.add(v);
            if (h.length > 60) h.removeAt(0);
          }
        }
      });
    } catch (_) {/* pojedynczy poll może paść — następny naprawi */}
    finally { _polling = false; }
  }

  /// Historia dla kafelków typu chart — sekwencyjnie (tunel serializuje i tak), błąd = brak wykresu.
  Future<void> _loadHistory() async {
    final ha = _ha, http = _http, binding = _binding;
    if (ha == null || http == null || binding == null) return;
    for (final t in binding.tiles.where((t) => t.type == TileType.chart)) {
      if (_hist.containsKey(t.thingId)) continue;
      try {
        final h = await ha.history(http, t.thingId);
        if (!mounted) return;
        setState(() => _hist[t.thingId] = h.toList());
      } catch (_) { _hist[t.thingId] = []; }
    }
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

  /// Button: bezstanowa akcja (script/scene/…). Krótki feedback, bo encja nie zmienia stanu.
  Future<void> _fire(Tile tile) async {
    final ha = _ha, http = _http;
    if (ha == null || http == null) return;
    try {
      await ha.fire(http, tile.thingId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${tile.label} — ${tr('uruchomiono')}'),
            duration: const Duration(seconds: 1)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('Nie udało się uruchomić'))));
      }
    }
  }

  /// Wybór typu kafelka — proponujemy sensowny domyślny, ale user decyduje.
  Future<TileType?> _pickType(TileType initial, {required bool controllable, required bool numeric}) async {
    // Nie pokazujemy typów, które dla danej encji nie mają sensu (switch dla czujnika temperatury).
    final opts = <TileType>[
      if (numeric) TileType.chart,
      TileType.sensor,
      if (controllable) TileType.toggle,
      if (controllable) TileType.light,
      TileType.button,
    ];
    return showDialog<TileType>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Typ kafelka'), style: const TextStyle(color: AppTheme.text, fontSize: 16)),
        children: [
          for (final o in opts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, o),
              child: Row(children: [
                Icon(_typeIcon(o), size: 18, color: o == initial ? AppTheme.teal : AppTheme.muted),
                const SizedBox(width: 12),
                Text(_typeLabel(o),
                    style: TextStyle(color: o == initial ? AppTheme.teal : AppTheme.text)),
              ]),
            ),
        ],
      ),
    );
  }

  static IconData _typeIcon(TileType t) => switch (t) {
        TileType.chart  => Icons.show_chart,
        TileType.sensor => Icons.speed,
        TileType.toggle => Icons.toggle_on_outlined,
        TileType.light  => Icons.lightbulb_outline,
        TileType.button => Icons.touch_app_outlined,
      };

  static String _typeLabel(TileType t) => switch (t) {
        TileType.chart  => tr('Wykres'),
        TileType.sensor => tr('Odczyt'),
        TileType.toggle => tr('Przełącznik'),
        TileType.light  => tr('Światło'),
        TileType.button => tr('Przycisk'),
      };

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
    if (!mounted) return;
    final type = await _pickType(ha.suggest(picked),
        controllable: picked.controllable, numeric: picked.numeric != null);
    if (type == null) return;
    binding.tiles.add(Tile(thingId: picked.id, type: type, label: picked.name));
    await IntegrationStore.save(widget.deviceId, binding);
    if (!mounted) return;
    setState(() {});
    _refreshNow();
    _loadHistory();
  }

  /// Zmiana typu istniejącego kafelka (tryb edycji) — bez usuwania i dodawania od nowa.
  Future<void> _changeType(Tile t) async {
    final binding = _binding;
    if (binding == null) return;
    final st = _states[t.thingId];
    final type = await _pickType(t.type,
        controllable: st?.controllable ?? true, numeric: st?.numeric != null);
    if (type == null || type == t.type) return;
    final i = binding.tiles.indexOf(t);
    if (i < 0) return;
    binding.tiles[i] = Tile(thingId: t.thingId, type: type, label: t.label);
    await IntegrationStore.save(widget.deviceId, binding);
    if (!mounted) return;
    setState(() {});
    _loadHistory();
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
        // Tytuł agnostyczny wobec integracji (HomeIntegration to interfejs — HA jest pierwszym
        // adapterem, nie jedynym). Podtytuł niesie to, co realnie identyfikuje: rodzaj integracji
        // + skrót device_id. Miasto pomijamy — nie odróżnia dwóch nodów w tej samej miejscowości.
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Dashboard', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            Text('HA · ${widget.deviceId.length >= 8 ? widget.deviceId.substring(0, 8) : widget.deviceId}',
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.muted, fontFamily: 'monospace', letterSpacing: 0.3)),
          ],
        ),
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

  // Ikona wg device_class (dokładniejsza), potem wg domeny. Bez tego wszystko wygląda tak samo.
  static IconData _entityIcon(Tile t, Thing? st) {
    switch (st?.deviceClass) {
      case 'temperature': return Icons.thermostat;
      case 'humidity':    return Icons.water_drop_outlined;
      case 'power':
      case 'energy':      return Icons.bolt;
      case 'battery':     return Icons.battery_full;
      case 'pressure':    return Icons.compress;
      case 'illuminance': return Icons.wb_sunny_outlined;
      case 'motion':      return Icons.directions_run;
      case 'door':
      case 'window':      return Icons.sensor_door_outlined;
      case 'co2':
      case 'pm25':        return Icons.air;
    }
    return switch (st?.kind) {
      'light'  => Icons.lightbulb_outline,
      'switch' => Icons.power_settings_new,
      'fan'    => Icons.mode_fan_off,
      'lock'   => Icons.lock_outline,
      'cover'  => Icons.blinds_outlined,
      'climate'=> Icons.ac_unit,
      'script' || 'scene' || 'button' || 'input_button' => Icons.play_arrow_rounded,
      'automation' => Icons.smart_toy_outlined,
      _ => _typeIcon(t.type),
    };
  }

  Widget _tile(Tile t) {
    final st = _states[t.thingId];
    final on = st?.on ?? false;
    // Światło świeci na bursztynowo, reszta sterowalnych na teal — kolor niesie stan, nie dekorację.
    final accent = t.type == TileType.light ? AppTheme.amber : AppTheme.teal;
    final active = (t.type == TileType.light || t.type == TileType.toggle) && on;

    return GestureDetector(
      onTap: _editing
          ? () => _renameTile(t)
          : (t.type == TileType.button ? () => _fire(t) : null),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active ? Color.alphaBlend(accent.withOpacity(0.10), AppTheme.card) : AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? accent.withOpacity(0.45) : Colors.transparent),
        ),
        child: Stack(children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Icon(_entityIcon(t, st), size: 16, color: active ? accent : AppTheme.muted),
                const SizedBox(width: 6),
                Expanded(child: Text(t.label,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.text, fontWeight: FontWeight.w500, fontSize: 13))),
              ]),
              _tileBody(t, st, accent, on),
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
          if (_editing)
            Positioned(
              bottom: -6, right: -6,
              child: IconButton(
                tooltip: tr('Typ kafelka'),
                icon: Icon(_typeIcon(t.type), color: AppTheme.muted, size: 18),
                onPressed: () => _changeType(t),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _tileBody(Tile t, Thing? st, Color accent, bool on) {
    switch (t.type) {
      case TileType.toggle:
      case TileType.light:
        return Align(
          alignment: Alignment.centerLeft,
          child: Switch(
            value: on,
            activeThumbColor: accent,
            onChanged: (_editing || st == null) ? null : (v) => _toggle(t, v),
          ),
        );
      case TileType.button:
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.teal.withOpacity(_editing ? 0.06 : 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.play_arrow_rounded, size: 16, color: _editing ? AppTheme.muted : AppTheme.teal),
              const SizedBox(width: 5),
              Text(tr('Uruchom'),
                  style: TextStyle(color: _editing ? AppTheme.muted : AppTheme.teal,
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        );
      case TileType.chart:
        final h = _hist[t.thingId];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          _value(st, fontSize: 17),
          const SizedBox(height: 4),
          SizedBox(
            height: 22,
            width: double.infinity,
            child: (h == null)
                ? const SizedBox()                       // historia jeszcze leci
                : (h.length < 2)
                    ? Text(tr('brak historii'),
                        style: const TextStyle(color: AppTheme.muted, fontSize: 10))
                    : CustomPaint(painter: _Sparkline(h, AppTheme.teal)),
          ),
        ]);
      case TileType.sensor:
        return _value(st, fontSize: 20);
    }
  }

  Widget _value(Thing? st, {required double fontSize}) {
    final v = st?.state ?? '—';
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: [
        TextSpan(text: v, style: TextStyle(
            color: AppTheme.teal, fontWeight: FontWeight.w600, fontSize: fontSize)),
        if (st?.unit != null)
          TextSpan(text: ' ${st!.unit}', style: const TextStyle(
              color: AppTheme.muted, fontWeight: FontWeight.w500, fontSize: 11)),
      ]),
    );
  }
}

/// Sparkline — świadomie bez fl_chart: kilka linii CustomPaint zamiast ciężkiego wykresu,
/// który i tak byłby nieczytelny na kafelku 150×22 px.
class _Sparkline extends CustomPainter {
  final List<double> data;
  final Color color;
  _Sparkline(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    var lo = data.first, hi = data.first;
    for (final v in data) { if (v < lo) lo = v; if (v > hi) hi = v; }
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : (hi - lo);   // płaska seria → linia w połowie
    final dx = size.width / (data.length - 1);
    final pts = [
      for (var i = 0; i < data.length; i++)
        Offset(i * dx, size.height - ((data[i] - lo) / span) * size.height),
    ];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) { line.lineTo(p.dx, p.dy); }
    // delikatne wypełnienie pod linią — daje głębię bez rozpraszania
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withOpacity(0.12));
    canvas.drawPath(line, Paint()
      ..color = color.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(pts.last, 2.0, Paint()..color = color);   // „teraz"
  }

  @override
  bool shouldRepaint(_Sparkline old) => old.data.length != data.length || old.data.last != data.last;
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
