/// Node — sparowany ESP32
class DeviceNode {
  final String deviceId;
  final String ip;
  final String? city;
  final String? firmware;
  final bool online;
  final String? label;

  const DeviceNode({
    required this.deviceId,
    required this.ip,
    this.city,
    this.firmware,
    this.online = false,
    this.label,
  });

  String get short => deviceId.length > 8 ? '${deviceId.substring(0, 8)}...' : deviceId;

  factory DeviceNode.fromInfo(Map<String, dynamic> j, String ip) => DeviceNode(
        deviceId: j['device_id'] ?? '',
        ip: ip,
        city: j['city'],
        firmware: j['version'] ?? j['firmware'],
        online: true,
      );
}
