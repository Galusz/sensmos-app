import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme.dart';
import '../../l10n.dart';
import '../../services/node_service.dart';

/// MQTT (FW 0.90): node publikuje status/encje/wiadomości do LOKALNEGO brokera
/// (Mosquitto/HA). Ustawienie noda, nie integracja — hasło idzie tylko po LAN do NVS.
class MqttScreen extends StatefulWidget {
  final SavedNode node;
  final String pin;
  const MqttScreen({super.key, required this.node, required this.pin});

  @override
  State<MqttScreen> createState() => _MqttScreenState();
}

class _MqttScreenState extends State<MqttScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _on = false;
  bool _connected = false;
  String _err = '';
  int _tx = 0;
  final _host = TextEditingController();
  final _port = TextEditingController(text: '1883');
  final _user = TextEditingController();
  final _pass = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http
          .get(Uri.parse('http://${widget.node.ip}/node/mqtt'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 404) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = tr('Ten node nie obsługuje MQTT — zaktualizuj firmware do 0.90 lub nowszego.');
        });
        return;
      }
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _on = j['on'] == true;
        _connected = j['connected'] == true;
        _err = (j['err'] ?? '').toString();
        _tx = (j['tx'] as num?)?.toInt() ?? 0;
        if ((j['host'] ?? '').toString().isNotEmpty) {
          _host.text = j['host'].toString();
        }
        if (j['port'] != null) _port.text = j['port'].toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = tr('Nie można połączyć z nodem: %s', [e]);
      });
    }
  }

  Future<void> _save() async {
    final host = _host.text.trim();
    if (_on && host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Podaj adres brokera')), backgroundColor: AppTheme.red));
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await http
          .post(Uri.parse('http://${widget.node.ip}/node/mqtt'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${widget.pin}',
              },
              body: jsonEncode({
                'on': _on,
                'host': host,
                'port': int.tryParse(_port.text.trim()) ?? 1883,
                'user': _user.text.trim(),
                'pass': _pass.text,
              }))
          .timeout(const Duration(seconds: 6));
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('Zapisano — node łączy się z brokerem'))));
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('Błąd %s', [res.statusCode])), backgroundColor: AppTheme.red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('Błąd: %s', [e])), backgroundColor: AppTheme.red));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('MQTT (lokalny broker)'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!,
                          style: const TextStyle(color: AppTheme.red, fontSize: 13)),
                    ),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.circle,
                            size: 12,
                            color: _connected
                                ? const Color(0xFF44CC66)
                                : (_on ? AppTheme.amber : AppTheme.muted)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _connected
                                ? tr('Połączony z brokerem · wysłano %s wiadomości', ['$_tx'])
                                : (_on
                                    ? tr('Łączenie... %s', [_err.isEmpty ? '' : '($_err)'])
                                    : tr('Wyłączone')),
                            style: const TextStyle(color: AppTheme.text, fontSize: 13),
                          ),
                        ),
                        IconButton(
                            icon: const Icon(Icons.refresh, color: AppTheme.muted),
                            onPressed: _load),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Node publikuje do brokera w Twojej sieci: status (online/offline), '
                      'diagnostykę, encje (z auto-wykryciem w Home Assistant) i wiadomości. '
                      'Działa też bez internetu — temat net/wan mówi, czy internet w domu żyje.'),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Card(
                  child: SwitchListTile(
                    title: Text(tr('Włączone'), style: const TextStyle(color: AppTheme.text)),
                    value: _on,
                    activeColor: AppTheme.teal,
                    onChanged: (v) => setState(() => _on = v),
                  ),
                ),
                const SizedBox(height: 8),
                _field(_host, tr('Adres brokera (IP w LAN)'), hint: '192.168.1.10'),
                _field(_port, tr('Port'), hint: '1883', number: true),
                _field(_user, tr('Użytkownik (opcjonalnie)')),
                _field(_pass, tr('Hasło (opcjonalnie)'), obscure: true),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.teal),
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? tr('Zapisywanie...') : tr('Zapisz'),
                      style: const TextStyle(color: Colors.black)),
                ),
              ],
            ),
    );
  }

  Widget _field(TextEditingController c, String label,
          {String? hint, bool number = false, bool obscure = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          obscureText: obscure,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          style: const TextStyle(color: AppTheme.text, fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: AppTheme.muted, fontSize: 13),
            hintText: hint,
            hintStyle: const TextStyle(color: AppTheme.muted),
          ),
        ),
      );

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }
}
