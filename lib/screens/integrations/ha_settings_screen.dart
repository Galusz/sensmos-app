import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../../services/integrations/integration_store.dart';

/// Ustawienia integracji Home Assistant dla noda: host:port + long-lived token.
/// Sam dashboard (kafelki) budujesz na żywo w Panelu HA — tu tylko połączenie.
class HaSettingsScreen extends StatefulWidget {
  final String deviceId;
  final String label;
  const HaSettingsScreen({super.key, required this.deviceId, required this.label});

  @override
  State<HaSettingsScreen> createState() => _HaSettingsScreenState();
}

class _HaSettingsScreenState extends State<HaSettingsScreen> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '8123');
  final _token = TextEditingController();
  HaBinding? _existing;
  bool _loading = true;
  bool _showToken = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await IntegrationStore.load(widget.deviceId);
    if (!mounted) return;
    setState(() {
      _existing = b;
      if (b != null) {
        _host.text = b.host;
        _port.text = b.port.toString();
        _token.text = b.token;
      }
      _loading = false;
    });
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 8123;
    final token = _token.text.trim();
    if (host.isEmpty || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Podaj host i token'))));
      return;
    }
    final b = _existing ?? HaBinding(host: host, port: port, token: token);
    b.host = host;
    b.port = port;
    b.token = token;
    await IntegrationStore.save(widget.deviceId, b);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    await IntegrationStore.remove(widget.deviceId);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: Text(tr('Home Assistant'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.teal))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  tr('Podłącz HA w sieci noda przez tunel. Użyj wewnętrznego adresu HTTP (np. 192.168.1.10:8123) — tunel i tak szyfruje.'),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12.5),
                ),
                const SizedBox(height: 16),
                _field(_host, tr('Host HA (IP w sieci noda)'), Icons.home_outlined, hint: '192.168.1.10'),
                _field(_port, tr('Port'), Icons.tag, keyboard: TextInputType.number),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _token,
                    obscureText: !_showToken,
                    maxLines: 1,
                    style: const TextStyle(color: AppTheme.text),
                    decoration: InputDecoration(
                      labelText: tr('Long-lived token'),
                      labelStyle: const TextStyle(color: AppTheme.muted),
                      prefixIcon: const Icon(Icons.key_outlined, color: AppTheme.muted, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility,
                            color: AppTheme.muted, size: 20),
                        tooltip: _showToken ? tr('Ukryj') : tr('Pokaż'),
                        onPressed: () => setState(() => _showToken = !_showToken),
                      ),
                      filled: true,
                      fillColor: AppTheme.card,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Token wygenerujesz w HA: Profil → Long-Lived Access Tokens.'),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11.5),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(tr('Zapisz')),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.teal, foregroundColor: Colors.black),
                ),
                if (_existing != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(tr('Usuń integrację')),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF6666),
                        side: const BorderSide(color: Color(0x55FF6666))),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon,
      {String? hint, bool obscure = false, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: keyboard,
        style: const TextStyle(color: AppTheme.text),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: AppTheme.muted),
          prefixIcon: Icon(icon, color: AppTheme.muted, size: 20),
          filled: true,
          fillColor: AppTheme.card,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}
