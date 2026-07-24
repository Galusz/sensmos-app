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
  TileType suggest(Thing t) => t.controllable ? TileType.toggle : TileType.sensor;
}
