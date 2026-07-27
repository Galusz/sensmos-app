import 'http_over_tunnel.dart';

/// Typ kafelka na dashboardzie. UWAGA: zapisywany na dysk jako INDEKS (Tile.toJson),
/// więc KOLEJNOŚĆ jest częścią formatu — nowe typy dopisujemy WYŁĄCZNIE na końcu,
/// inaczej istniejące dashboardy zmieniłyby typy kafelków po aktualizacji apki.
enum TileType {
  toggle,   // 0 — przełącznik (switch/input_boolean/fan)
  sensor,   // 1 — odczyt liczbowy/tekstowy
  light,    // 2 — światło: jak toggle, ale kafelek się rozświetla gdy ON
  button,   // 3 — akcja bezstanowa (script/scene/button/automation): tap = odpal
  chart,    // 4 — sensor + sparkline z historii
}

/// Generyczna "rzecz" z lokalnej integracji (encja HA, item openHAB, …). Adapter mapuje
/// swój model API na to; UI (kafelki) rendruje wyłącznie z tego — nic nie wie o HA.
class Thing {
  final String id;
  final String name;
  final String kind; // domena/typ: light/switch/sensor/...
  final String? deviceClass; // HA device_class (temperature/humidity/power/…) — do ikony
  final String? state; // surowa wartość ("on", "23.4", ...)
  final String? unit;
  final bool controllable; // czy da się sterować (toggle)
  final bool on; // dla sterowalnych: aktualny stan on/off
  Thing({
    required this.id,
    required this.name,
    required this.kind,
    this.deviceClass,
    this.state,
    this.unit,
    this.controllable = false,
    this.on = false,
  });

  /// Wartość liczbowa albo null (sensory tekstowe/niedostępne) — dla wykresu i formatowania.
  double? get numeric => double.tryParse((state ?? '').replaceAll(',', '.'));

  // Do cache'u katalogu encji na dysku — bez state/on (zmienne, nie cache'ujemy).
  Map<String, dynamic> toJson() =>
      {'id': id, 'n': name, 'k': kind, 'u': unit, 'c': controllable, 'd': deviceClass};
  static Thing fromJson(Map<String, dynamic> j) => Thing(
        id: j['id'] as String,
        name: (j['n'] as String?) ?? (j['id'] as String),
        kind: (j['k'] as String?) ?? '',
        deviceClass: j['d'] as String?,
        unit: j['u'] as String?,
        controllable: (j['c'] as bool?) ?? false,
      );
}

/// Kafelek na dashboardzie usera (konfig zapisany lokalnie).
class Tile {
  final String thingId;
  final TileType type;
  String label; // edytowalna — user zmienia nazwę (encje HA mają nazwy z czapy)
  Tile({required this.thingId, required this.type, required this.label});
  Map<String, dynamic> toJson() => {'id': thingId, 't': type.index, 'l': label};
  static Tile fromJson(Map<String, dynamic> j) {
    // Nieznany indeks (config zapisany NOWSZĄ apką niż zainstalowana) → sensor zamiast wyjątku,
    // który wywaliłby cały dashboard.
    final i = (j['t'] as int?) ?? TileType.sensor.index;
    return Tile(
      thingId: j['id'] as String,
      type: (i >= 0 && i < TileType.values.length) ? TileType.values[i] : TileType.sensor,
      label: (j['l'] as String?) ?? (j['id'] as String),
    );
  }
}

/// Cienki szew: to jest JEDYNE miejsce zależne od konkretnej integracji. Reszta apki
/// (transport, kafelki, builder, polling, PIN) jest agnostyczna. HA = pierwszy adapter;
/// kolejne (openHAB, …) to nowa implementacja tego interfejsu — zero FW, zero zmian w UI.
abstract class HomeIntegration {
  String get name;
  Future<bool> ping(HttpOverTunnel c); // test połączenia/auth
  Future<List<Thing>> discover(HttpOverTunnel c); // pełna lista (picker)
  Future<List<Thing>> refresh(HttpOverTunnel c, List<String> ids); // stany kafelków (dashboard)
  Future<void> actuate(HttpOverTunnel c, String thingId, bool on); // toggle
  Future<void> fire(HttpOverTunnel c, String thingId); // akcja bezstanowa (button): script/scene/…
  /// Ostatnie wartości liczbowe encji (najstarsza → najnowsza) do sparkline. Pusta lista =
  /// brak historii/nienumeryczna. Wołane RZADKO (raz na wejście w panel), nie w pollingu.
  Future<List<double>> history(HttpOverTunnel c, String thingId, {Duration span});
  TileType suggest(Thing t); // sugerowany typ kafelka dla encji
}
