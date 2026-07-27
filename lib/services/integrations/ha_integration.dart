import 'dart:convert';
import 'home_integration.dart';
import 'http_over_tunnel.dart';

/// Adapter Home Assistant — REST API (`/api/...`) z long-lived tokenem (Bearer).
/// Request/response, więc chodzi na JEDNYM tunelu (polling zamiast live-WS). Zero FW.
class HaIntegration implements HomeIntegration {
  final String token;
  HaIntegration(this.token);

  @override
  String get name => 'Home Assistant';

  Map<String, String> get _auth => {'Authorization': 'Bearer $token'};

  // Domeny które realnie da się przełączać usługą turn_on/turn_off.
  static const _switchable = {'light', 'switch', 'input_boolean', 'fan', 'automation', 'script', 'siren'};
  // Domeny bezstanowe: „odpal i zapomnij" — trzymanie ich jako przełącznika jest mylące
  // (script pokazywałby się jako włączony przez ułamek sekundy działania).
  static const _fireable = {'script', 'scene', 'button', 'input_button'};

  Thing _fromState(Map<String, dynamic> s) {
    final id = s['entity_id'] as String;
    final domain = id.contains('.') ? id.split('.').first : id;
    final attrs = (s['attributes'] as Map?)?.cast<String, dynamic>() ?? const {};
    final name = (attrs['friendly_name'] ?? id).toString();
    final unit = attrs['unit_of_measurement']?.toString();
    final state = s['state']?.toString();
    final controllable = _switchable.contains(domain);
    return Thing(
      id: id,
      name: name,
      kind: domain,
      deviceClass: attrs['device_class']?.toString(),
      state: state,
      unit: unit,
      controllable: controllable,
      on: state == 'on',
    );
  }

  @override
  Future<bool> ping(HttpOverTunnel c) async {
    final r = await c.request('GET', '/api/', headers: _auth);
    return r.status == 200; // /api/ z ważnym tokenem → {"message":"API running."}
  }

  @override
  Future<List<Thing>> discover(HttpOverTunnel c) async {
    final r = await c.request('GET', '/api/states', headers: _auth);
    if (r.status != 200) throw Exception('HA HTTP ${r.status}');
    final list = (r.json as List).cast<Map<String, dynamic>>();
    final things = list.map(_fromState).toList();
    things.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return things;
  }

  @override
  Future<List<Thing>> refresh(HttpOverTunnel c, List<String> ids) async {
    // Per-encja (małe payloady → omija throttle tunelu). Serializowane przez HttpOverTunnel.
    final out = <Thing>[];
    for (final id in ids) {
      try {
        final r = await c.request('GET', '/api/states/$id', headers: _auth);
        if (r.status == 200) out.add(_fromState(r.json as Map<String, dynamic>));
      } catch (_) {/* pojedyncza encja może zniknąć — pomiń */}
    }
    return out;
  }

  @override
  Future<void> actuate(HttpOverTunnel c, String thingId, bool on) async {
    final domain = thingId.contains('.') ? thingId.split('.').first : thingId;
    final svc = on ? 'turn_on' : 'turn_off';
    await c.request('POST', '/api/services/$domain/$svc',
        headers: {..._auth, 'Content-Type': 'application/json'},
        body: jsonEncode({'entity_id': thingId}));
  }

  @override
  Future<void> fire(HttpOverTunnel c, String thingId) async {
    final domain = thingId.contains('.') ? thingId.split('.').first : thingId;
    // Każda domena ma swój czasownik — `button.press` nie zna turn_on, `automation` chce trigger.
    final svc = switch (domain) {
      'button' || 'input_button' => 'press',
      'automation' => 'trigger',
      _ => 'turn_on', // script, scene
    };
    await c.request('POST', '/api/services/$domain/$svc',
        headers: {..._auth, 'Content-Type': 'application/json'},
        body: jsonEncode({'entity_id': thingId}));
  }

  @override
  Future<List<double>> history(HttpOverTunnel c, String thingId,
      {Duration span = const Duration(hours: 6)}) async {
    // minimal_response + no_attributes = kilkukrotnie mniejszy payload (idzie przez tunel noda).
    final from = DateTime.now().toUtc().subtract(span).toIso8601String();
    final r = await c.request(
      'GET',
      '/api/history/period/$from?filter_entity_id=$thingId&minimal_response&no_attributes',
      headers: _auth,
    );
    if (r.status != 200) return const [];
    final outer = r.json;
    if (outer is! List || outer.isEmpty) return const [];
    final series = outer.first;
    if (series is! List) return const [];
    final vals = <double>[];
    for (final p in series) {
      final v = double.tryParse(((p as Map?)?['state'] ?? '').toString().replaceAll(',', '.'));
      if (v != null) vals.add(v);
    }
    // Sparkline na kafelku ~150px — więcej niż 60 punktów to i tak niewidoczny szum.
    if (vals.length <= 60) return vals;
    final step = vals.length / 60;
    return [for (var i = 0; i < 60; i++) vals[(i * step).floor()]];
  }

  @override
  TileType suggest(Thing t) {
    if (_fireable.contains(t.kind)) return TileType.button;
    if (t.kind == 'light') return TileType.light;
    if (t.controllable) return TileType.toggle;
    // Liczbowy sensor → od razu wykres (to on najbardziej zyskuje na trendzie).
    if (t.numeric != null) return TileType.chart;
    return TileType.sensor;
  }
}
