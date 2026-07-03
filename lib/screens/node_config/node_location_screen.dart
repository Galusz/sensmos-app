import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../../config.dart';

/// App-proof geo: apka pobiera GPS telefonu (jesteś przy nodzie = dowód) i wysyła
/// go do noda. Pozycji NIE ustawia się ręcznie — backend nakłada losowy fuzz
/// prywatności (~200–800 m), więc nikt nie zna dokładnej pozycji ani nie wrzuci
/// pinu sąsiadowi. Miasto liczy backend z pozycji.
class NodeLocationScreen extends StatefulWidget {
  final String ip;
  final String pin;
  final String? title;

  const NodeLocationScreen(
      {super.key, required this.ip, required this.pin, this.title});

  @override
  State<NodeLocationScreen> createState() => _NodeLocationScreenState();
}

class _NodeLocationScreenState extends State<NodeLocationScreen> {
  double? _gpsLat;
  double? _gpsLon;
  double? _accuracy;
  bool _fuzz = true;
  bool _saving = false;
  bool _gettingGps = false;
  String? _deviceId;
  String? _fw;
  bool?   _ghost;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  // Ghost wymaga FW ≥ 0.25 (starsze nie forwardują location_mode → cicha porażka)
  bool get _fwSupportsGhost {
    final v = _fw;
    if (v == null) return false;
    final p = v.split('.');
    final major = int.tryParse(p.isNotEmpty ? p[0] : '0') ?? 0;
    final minor = int.tryParse(p.length > 1 ? p[1] : '0') ?? 0;
    return major > 0 || (major == 0 && minor >= 25);
  }

  Future<void> _loadState() async {
    try {
      final info = await http
          .get(Uri.parse('http://${widget.ip}/info'))
          .timeout(const Duration(seconds: 4));
      final j = jsonDecode(info.body) as Map<String, dynamic>;
      _deviceId = j['device_id'] as String?;
      if (mounted) setState(() => _fw = (j['version'] ?? j['firmware']) as String?);
      if (_deviceId != null) {
        final be = await http
            .get(Uri.parse('${Config.beUrl}/v1/nodes/$_deviceId'))
            .timeout(const Duration(seconds: 5));
        final bj = jsonDecode(be.body) as Map<String, dynamic>;
        final src = (bj['device']?['location_source'] ?? '').toString();
        if (mounted) setState(() => _ghost = src == 'ghost');
      }
    } catch (_) { if (mounted) setState(() => _ghost ??= false); }
  }

  Future<void> _setGhost(bool on) async {
    try {
      final res = await http
          .post(Uri.parse('http://${widget.ip}/config'),
              headers: _h,
              body: jsonEncode({'location_mode': on ? 'ghost' : 'public'}))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        if (mounted) setState(() => _ghost = on);
        _snack(on
            ? tr('Tryb prywatny włączony — node ukryty z mapy i nagród')
            : tr('Tryb prywatny wyłączony'));
      } else {
        _snack(tr('Błąd %s', [res.statusCode]), error: true);
      }
    } catch (e) {
      _snack(tr('Błąd: %s', [e]), error: true);
    }
  }

  Map<String, String> get _h => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.pin}',
      };

  Future<void> _useGps() async {
    setState(() => _gettingGps = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack(tr('Włącz lokalizację (GPS) w telefonie'), error: true);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _snack(tr('Brak zgody na lokalizację'), error: true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _gpsLat = pos.latitude;
        _gpsLon = pos.longitude;
        _accuracy = pos.accuracy;
      });
      _snack(tr('Pozycja GPS pobrana ✓'));
    } catch (e) {
      _snack(tr('Błąd GPS: %s', [e]), error: true);
    } finally {
      if (mounted) setState(() => _gettingGps = false);
    }
  }

  Future<void> _save() async {
    if (_gpsLat == null || _gpsLon == null) {
      _snack(tr('Najpierw pobierz pozycję GPS'), error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await http
          .post(Uri.parse('http://${widget.ip}/config'),
              headers: _h,
              body: jsonEncode({
                'gps_lat': _gpsLat!.toStringAsFixed(6),
                'gps_lon': _gpsLon!.toStringAsFixed(6),
                'fuzz': _fuzz,
              }))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        if (mounted) {
          _snack(tr('Lokalizacja potwierdzona i zapisana'));
          Navigator.pop(context, true);
        }
      } else {
        _snack(tr('Błąd %s', [res.statusCode]), error: true);
      }
    } catch (e) {
      _snack(tr('Błąd: %s', [e]), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.red : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hasGps = _gpsLat != null && _gpsLon != null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? tr('Lokalizacja'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
              tr('Stań przy nodzie i pobierz pozycję GPS — to potwierdza, że node '
                  'jest naprawdę tutaj. Miasto uzupełni się samo.'),
              style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.teal,
                side: const BorderSide(color: AppTheme.teal),
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _gettingGps ? null : _useGps,
            icon: _gettingGps
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.teal))
                : const Icon(Icons.my_location),
            label: Text(hasGps
                ? tr('Pobierz GPS ponownie')
                : tr('Pobierz moją pozycję (GPS)')),
          ),
          const SizedBox(height: 20),
          if (hasGps)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('POZYCJA GPS'),
                      style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 11,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  Text(
                    '${_gpsLat!.toStringAsFixed(6)}, ${_gpsLon!.toStringAsFixed(6)}',
                    style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                  if (_accuracy != null) ...[
                    const SizedBox(height: 4),
                    Text(tr('dokładność ±%s m', [_accuracy!.round()]),
                        style: const TextStyle(
                            color: AppTheme.teal, fontSize: 12)),
                  ],
                ],
              ),
            )
          else
            Text(tr('Brak pozycji — naciśnij przycisk powyżej.'),
                style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: SwitchListTile(
              value: _fuzz,
              onChanged: (v) => setState(() => _fuzz = v),
              activeColor: AppTheme.teal,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              title: Text(tr('Rozmycie prywatności'),
                  style: const TextStyle(color: AppTheme.text, fontSize: 14)),
              subtitle: Text(
                  _fuzz
                      ? tr('Na mapie ~200–800 m od prawdziwej pozycji (losowo)')
                      : tr('Na mapie dokładny adres noda'),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: SwitchListTile(
              value: _ghost ?? false,
              onChanged: (!_fwSupportsGhost || _ghost == null)
                  ? null
                  : (v) => _setGhost(v),
              activeColor: AppTheme.teal,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              secondary: const Icon(Icons.visibility_off_outlined,
                  color: AppTheme.muted),
              title: Text(tr('Tryb prywatny (ghost)'),
                  style: const TextStyle(color: AppTheme.text, fontSize: 14)),
              subtitle: Text(
                  _fwSupportsGhost
                      ? tr('Ukryty z mapy, 0 nagród. Dane działają lokalnie; za subskrypcje płacisz.')
                      : tr('Wymaga firmware 0.25+ — zaktualizuj node.'),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.teal,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: (_saving || !hasGps) ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.save, color: Colors.black),
            label: Text(tr('Zapisz lokalizację'),
                style: const TextStyle(color: Colors.black, fontSize: 15)),
          ),
        ],
      ),
    );
  }
}
