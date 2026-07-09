import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/node.dart';
import 'ble_service.dart';

class NodeService {
  DeviceNode? _activeNode;
  String?     _activePin;
  List<SavedNode> _nodes = [];

  DeviceNode?     get node  => _activeNode;
  List<SavedNode> get nodes => List.unmodifiable(_nodes);
  bool get connected => _activeNode != null;
  bool get online    => _activeNode?.online ?? false;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> _saveList() async {
    final p = await _prefs;
    await p.setString('sensmos_nodes',
        jsonEncode(_nodes.map((n) => n.toJson()).toList()));
  }

  Future<void> _loadList() async {
    final p = await _prefs;
    final raw = p.getString('sensmos_nodes');
    if (raw == null || raw.isEmpty) { _nodes = []; return; }
    try {
      _nodes = (jsonDecode(raw) as List)
          .map((j) => SavedNode.fromJson(j as Map<String,dynamic>))
          .toList();
    } catch (_) { _nodes = []; }
  }

  Future<DeviceNode?> loadSaved({BleService? bleService}) async {
    await _loadList();
    if (_nodes.isEmpty) return null;
    final p = await _prefs;
    final activeId = p.getString('sensmos_active_node') ?? _nodes.first.id;
    final saved = _nodes.firstWhere((n) => n.id == activeId,
        orElse: () => _nodes.first);
    _activePin = saved.pin;
    return _tryConnect(saved, bleService: bleService);
  }

  Future<DeviceNode?> _tryConnect(SavedNode s, {BleService? bleService}) async {
    try {
      await http.get(Uri.parse('http://${s.ip}/info'))
          .timeout(const Duration(seconds: 3));
      _activeNode = DeviceNode(deviceId: s.id, ip: s.ip, online: true, label: s.label);
      return _activeNode;
    } catch (_) {}
    if (bleService != null && s.hostname.isNotEmpty) {
      try {
        final newIp = await bleService.discoverByHostname(
            hostname: s.hostname, timeout: const Duration(seconds: 8));
        if (newIp != null) {
          s.ip = newIp;
          await _saveList();
          _activeNode = DeviceNode(deviceId: s.id, ip: newIp, online: true, label: s.label);
          return _activeNode;
        }
      } catch (_) {}
    }
    _activeNode = DeviceNode(deviceId: s.id, ip: s.ip, online: false, label: s.label);
    return _activeNode;
  }

  Future<DeviceNode?> setActive(String deviceId, {BleService? bleService}) async {
    final s = _nodes.firstWhere((n) => n.id == deviceId);
    final p = await _prefs;
    await p.setString('sensmos_active_node', deviceId);
    _activePin = s.pin;
    return _tryConnect(s, bleService: bleService);
  }

  Future<void> addNode(String ip, String pin, String deviceId, {String? label, String? mac}) async {
    final short = deviceId.length >= 6
        ? deviceId.substring(0,6).toLowerCase() : deviceId.toLowerCase();
    final hn  = 'sensmos-$short.local';
    final idx = _nodes.indexWhere((n) => n.id == deviceId);
    final s   = SavedNode(id: deviceId, ip: ip, pin: pin, hostname: hn,
        label: label ?? 'Node',
        mac: mac ?? (idx >= 0 ? _nodes[idx].mac : ''));   // nie gub MAC przy update bez mac
    if (idx >= 0) _nodes[idx] = s; else _nodes.add(s);
    await _saveList();
    final p = await _prefs;
    await p.setString('sensmos_active_node', deviceId);
    _activePin  = pin;
    _activeNode = DeviceNode(deviceId: deviceId, ip: ip, online: true, label: s.label);
  }

  Future<void> removeNode(String deviceId) async {
    _nodes.removeWhere((n) => n.id == deviceId);
    await _saveList();
    if (_activeNode?.deviceId == deviceId) {
      _activeNode = null; _activePin = null;
      final p = await _prefs;
      if (_nodes.isNotEmpty) {
        await p.setString('sensmos_active_node', _nodes.first.id);
        _activePin  = _nodes.first.pin;
        _activeNode = DeviceNode(deviceId: _nodes.first.id,
            ip: _nodes.first.ip, online: false, label: _nodes.first.label);
      } else {
        await p.remove('sensmos_active_node');
      }
    }
  }

  Future<void> disconnect() async { _activeNode = null; _activePin = null; }
  Future<void> saveNode(String ip, String pin, String deviceId, {String? mac}) =>
      addNode(ip, pin, deviceId, mac: mac);

  /// Backfill MAC dla nodów dodanych starą apką: /info (FW ≥ 0.47) zwraca ble_mac,
  /// lista uzupełnia się sama przy odświeżaniu — restore ID działa bez re-onboardingu.
  Future<void> updateNodeMac(String deviceId, String mac) async {
    if (mac.isEmpty) return;
    final idx = _nodes.indexWhere((n) => n.id == deviceId);
    if (idx < 0 || _nodes[idx].mac.toUpperCase() == mac.toUpperCase()) return;
    final old = _nodes[idx];
    _nodes[idx] = SavedNode(id: old.id, ip: old.ip, pin: old.pin,
        hostname: old.hostname, label: old.label, mac: mac.toUpperCase());
    await _saveList();
  }

  /// Node zapisany wcześniej z tym samym BLE MAC (ten sam sprzęt po reflashu) —
  /// kandydat do odtworzenia device_id przy ponownym dodawaniu.
  SavedNode? findByMac(String? mac) {
    if (mac == null || mac.isEmpty) return null;
    final m = mac.toUpperCase();
    for (final n in _nodes) {
      if (n.mac.toUpperCase() == m) return n;
    }
    return null;
  }

  String? get activePin => _activePin;

  /// Zaktualizuj zapisany PIN noda po zmianie na firmware
  Future<void> updateNodePin(String deviceId, String newPin) async {
    final idx = _nodes.indexWhere((n) => n.id == deviceId);
    if (idx < 0) return;
    final old = _nodes[idx];
    _nodes[idx] = SavedNode(
        id: old.id, ip: old.ip, pin: newPin,
        hostname: old.hostname, label: old.label, mac: old.mac);
    await _saveList();
    if (_activeNode?.deviceId == deviceId) _activePin = newPin;
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_activePin != null) 'Authorization': 'Bearer $_activePin',
  };

  Future<Map<String,dynamic>> walletBalance() async =>
      jsonDecode((await http.get(Uri.parse('http://${_activeNode!.ip}/wallet/balance'),
          headers: _headers)).body);
  Future<Map<String,dynamic>> walletProof() async =>
      jsonDecode((await http.get(Uri.parse('http://${_activeNode!.ip}/wallet/proof'),
          headers: _headers)).body);
  Future<bool> setConfig(Map<String,dynamic> cfg) async =>
      (await http.post(Uri.parse('http://${_activeNode!.ip}/config'),
          headers: _headers, body: jsonEncode(cfg))).statusCode == 200;
  Future<Map<String,dynamic>> getConfig() async =>
      jsonDecode((await http.get(Uri.parse('http://${_activeNode!.ip}/config'),
          headers: _headers)).body);
}

class SavedNode {
  final String id, pin, hostname, label;
  final String mac;   // BLE MAC z onboardingu — pozwala rozpoznać ten sam sprzęt po reflashu
  String ip;
  SavedNode({required this.id, required this.ip, required this.pin,
      required this.hostname, required this.label, this.mac = ''});
  factory SavedNode.fromJson(Map<String,dynamic> j) => SavedNode(
      id: j['id']??'', ip: j['ip']??'', pin: j['pin']??'',
      hostname: j['hostname']??'', label: j['label']??'Node', mac: j['mac']??'');
  Map<String,dynamic> toJson() =>
      {'id':id,'ip':ip,'pin':pin,'hostname':hostname,'label':label,'mac':mac};
}
