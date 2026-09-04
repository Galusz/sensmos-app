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

/// Zakładka „Panel LAN" — panel WWW w sieci noda otwierany przez tunel.
class LanPanel {
  String name;
  String host;   // IP/host w LAN noda
  int port;
  LanPanel({required this.name, required this.host, this.port = 80});

  Map<String, dynamic> toJson() => {'name': name, 'host': host, 'port': port};
  static LanPanel fromJson(Map<String, dynamic> j) => LanPanel(
        name: (j['name'] as String?) ?? '',
        host: (j['host'] as String?) ?? '',
        port: (j['port'] as int?) ?? 80,
      );
}

/// Zapisany cel SSH — jak zakładka „Panel LAN", tylko dla terminala.
/// Hasło NIE jest częścią wpisu: leży (opcjonalnie) w bezpiecznym magazynie pod kluczem
/// `term_pass_<node>_<host>:<port>:<user>`, żeby każdy host miał swoje.
class SshHost {
  String name;
  String host;
  int port;
  String user;
  SshHost({required this.name, required this.host, this.port = 22, this.user = 'root'});

  /// Klucz sekretu i tożsamość wpisu — host+port+user, bo pod jednym adresem bywa kilka kont.
  String get slug => '$host:$port:$user';
  String get title => name.trim().isNotEmpty ? name.trim() : '$user@$host';

  Map<String, dynamic> toJson() => {'name': name, 'host': host, 'port': port, 'user': user};
  static SshHost fromJson(Map<String, dynamic> j) => SshHost(
        name: (j['name'] as String?) ?? '',
        host: (j['host'] as String?) ?? '',
        port: (j['port'] as int?) ?? 22,
        user: (j['user'] as String?) ?? 'root',
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

  // ── Panel LAN: zakładki paneli WWW w sieci noda (per node) ──
  // Tylko HTTP — tunel mówi czystym HTTP/1.1 end-to-end (HttpOverTunnel), TLS do hosta
  // w LAN nie przejdzie. Ciężkie SPA (UniFi/HA/Proxmox) też nie — patrz plugin-y API.
  static String _lanKey(String nodeId) => 'lan_panels_$nodeId';

  static Future<List<LanPanel>> lanPanels(String nodeId) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_lanKey(nodeId));
    if (s == null) return [];
    try {
      return (jsonDecode(s) as List)
          .map((e) => LanPanel.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveLanPanels(String nodeId, List<LanPanel> panels) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_lanKey(nodeId), jsonEncode(panels.map((e) => e.toJson()).toList()));
  }

  // ── Terminal: zapisane cele SSH (per node) ──
  // Terminal długo pamiętał tylko OSTATNI cel, więc druga maszyna w tej samej sieci
  // znaczyła przepisywanie adresu z głowy. Lista działa jak zakładki paneli LAN.
  static String _sshKey(String nodeId) => 'ssh_hosts_$nodeId';

  static Future<List<SshHost>> sshHosts(String nodeId) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_sshKey(nodeId));
    if (s == null) return [];
    try {
      return (jsonDecode(s) as List)
          .map((e) => SshHost.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveSshHosts(String nodeId, List<SshHost> hosts) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_sshKey(nodeId), jsonEncode(hosts.map((e) => e.toJson()).toList()));
  }

  /// Dopisz albo odśwież wpis po udanym połączeniu (po slugu — bez duplikatów).
  static Future<void> rememberSshHost(String nodeId, SshHost h) async {
    final list = await sshHosts(nodeId);
    final i = list.indexWhere((e) => e.slug == h.slug);
    if (i >= 0) {
      if (h.name.trim().isNotEmpty) list[i].name = h.name;
    } else {
      list.add(h);
    }
    await saveSshHosts(nodeId, list);
  }

  // ── Cel widgetu na pulpicie (jeden na rodzaj) ──
  // Widget ma być skrótem „w jedno miejsce", więc trzymamy który node (a dla terminala
  // także który host) ma się otworzyć bez pytania. Brak celu = apka pyta jak dotąd.
  static const _kWidgetHa = 'widget_target_ha';       // node_id
  static const _kWidgetTerm = 'widget_target_term';   // "node_id|host:port:user"

  static Future<String?> widgetHaTarget() async =>
      (await SharedPreferences.getInstance()).getString(_kWidgetHa);

  static Future<void> setWidgetHaTarget(String? nodeId) async {
    final p = await SharedPreferences.getInstance();
    if (nodeId == null) { await p.remove(_kWidgetHa); } else { await p.setString(_kWidgetHa, nodeId); }
  }

  /// Zwraca (nodeId, slug) albo null.
  static Future<(String, String)?> widgetTermTarget() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kWidgetTerm);
    if (raw == null || !raw.contains('|')) return null;
    final i = raw.indexOf('|');
    return (raw.substring(0, i), raw.substring(i + 1));
  }

  static Future<void> setWidgetTermTarget(String? nodeId, String? slug) async {
    final p = await SharedPreferences.getInstance();
    if (nodeId == null || slug == null) { await p.remove(_kWidgetTerm); }
    else { await p.setString(_kWidgetTerm, '$nodeId|$slug'); }
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
