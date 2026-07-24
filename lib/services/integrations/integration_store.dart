import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_integration.dart';

/// Powiązanie noda z lokalną integracją (na teraz: HA) — host/port/token + kafelki dashboardu.
/// Trzymane lokalnie per node_id. Token wrażliwy — dostęp do panelu i tak PIN-gate'owany.
class HaBinding {
  String host;
  int port;
  String token;
  List<Tile> tiles;
  HaBinding({required this.host, required this.port, required this.token, List<Tile>? tiles})
      : tiles = tiles ?? [];

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'token': token,
        'tiles': tiles.map((t) => t.toJson()).toList(),
      };

  static HaBinding fromJson(Map<String, dynamic> j) => HaBinding(
        host: (j['host'] as String?) ?? '',
        port: (j['port'] as int?) ?? 8123,
        token: (j['token'] as String?) ?? '',
        tiles: ((j['tiles'] as List?) ?? [])
            .map((e) => Tile.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class IntegrationStore {
  static String _key(String nodeId) => 'ha_binding_$nodeId';

  static Future<HaBinding?> load(String nodeId) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key(nodeId));
    if (s == null) return null;
    try {
      return HaBinding.fromJson((jsonDecode(s) as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String nodeId, HaBinding b) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key(nodeId), jsonEncode(b.toJson()));
  }

  static Future<void> remove(String nodeId) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key(nodeId));
  }

  /// Zbiór node_id które mają skonfigurowaną integrację (do pokazania przycisku na karcie).
  static Future<Set<String>> boundNodeIds() async {
    final p = await SharedPreferences.getInstance();
    const pfx = 'ha_binding_';
    return p.getKeys().where((k) => k.startsWith(pfx)).map((k) => k.substring(pfx.length)).toSet();
  }

  // ── Cache katalogu encji (picker) — na dysku, żeby otwierać natychmiast, nie ciągnąć
  // za każdym razem całego /api/states przez throttlowany tunel. Odświeżany na żądanie. ──
  static String _entKey(String nodeId) => 'ha_entities_$nodeId';

  static Future<void> saveEntities(String nodeId, List<Thing> things) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_entKey(nodeId), jsonEncode(things.map((t) => t.toJson()).toList()));
  }

  static Future<List<Thing>?> loadEntities(String nodeId) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_entKey(nodeId));
    if (s == null) return null;
    try {
      return (jsonDecode(s) as List)
          .map((e) => Thing.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return null;
    }
  }

  // ── Podpięte integracje per node (opt-in: terminal, ha, …) ──
  static String _kindsKey(String nodeId) => 'integrations_$nodeId';

  static Future<Set<String>> enabledKinds(String nodeId) async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_kindsKey(nodeId)) ?? const []).toSet();
  }

  static Future<void> setKind(String nodeId, String kind, bool on) async {
    final p = await SharedPreferences.getInstance();
    final set = (p.getStringList(_kindsKey(nodeId)) ?? const []).toSet();
    if (on) {
      set.add(kind);
    } else {
      set.remove(kind);
    }
    await p.setStringList(_kindsKey(nodeId), set.toList());
  }
}
