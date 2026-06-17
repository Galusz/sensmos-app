/// Dane mapy — node z lokalizacją i scoringiem
class MapNode {
  final String deviceId;
  final double lat;
  final double lon;
  final String? city;
  final String status;
  final double balance;
  final double bestMult;
  final List<String> types;

  const MapNode({
    required this.deviceId,
    required this.lat,
    required this.lon,
    this.city,
    this.status = 'idle',
    this.balance = 0,
    this.bestMult = 1,
    this.types = const [],
  });

  factory MapNode.fromJson(Map<String, dynamic> j) => MapNode(
        deviceId: j['device_id'] ?? '',
        lat: double.tryParse('${j['lat']}') ?? 0,
        lon: double.tryParse('${j['lon']}') ?? 0,
        city: j['city'],
        status: j['status'] ?? 'idle',
        balance: double.tryParse('${j['balance']}') ?? 0,
        bestMult: double.tryParse('${j['best_mult']}') ?? 1,
        types: (j['types'] as List?)?.map((e) => '$e').toList() ?? [],
      );
}
