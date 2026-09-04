import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../../services/integrations/integration_store.dart';

/// Edytor zakładki „Panel LAN" — PEŁNY EKRAN, nie popup: trzy pola w AlertDialogu tłoczyły
/// się na wąskim telefonie, a klawiatura zasłaniała przyciski.
class LanPanelEditScreen extends StatefulWidget {
  final String deviceId;
  final LanPanel? existing;
  /// true = „połączenie jednorazowe": otwieramy panel, ale nie dopisujemy go do listy.
  final bool oneOff;
  const LanPanelEditScreen(
      {super.key, required this.deviceId, this.existing, this.oneOff = false});

  @override
  State<LanPanelEditScreen> createState() => _LanPanelEditScreenState();
}

class _LanPanelEditScreenState extends State<LanPanelEditScreen> {
  late final _host = TextEditingController(text: widget.existing?.host ?? '');
  late final _port = TextEditingController(text: '${widget.existing?.port ?? 80}');
  late final _name = TextEditingController(text: widget.existing?.name ?? '');

  @override
  void dispose() {
    for (final c in [_host, _port, _name]) { c.dispose(); }
    super.dispose();
  }

  /// [connect] = po zapisaniu od razu otwórz panel. Zapis bez otwierania zostaje w menu
  /// górnym — główny przycisk robi to, po co user tu wszedł, czyli łączy.
  void _finish({required bool connect}) {
    final host = _host.text.trim();
    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Podaj adres w LAN.'))));
      return;
    }
    Navigator.pop(context, (
      LanPanel(
        name: _name.text.trim().isEmpty ? host : _name.text.trim(),
        host: host,
        port: int.tryParse(_port.text.trim()) ?? 80,
      ),
      connect,
      widget.oneOff,
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          title: Text(widget.oneOff
              ? tr('Połączenie jednorazowe')
              : (widget.existing == null ? tr('Dodaj panel') : tr('Edytuj panel'))),
          actions: [
            if (!widget.oneOff)
              TextButton(
                onPressed: () => _finish(connect: false),
                child: Text(tr('Zapisz'), style: const TextStyle(color: AppTheme.teal)),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              tr('Panel WWW w sieci noda — router, drukarka, Pi-hole. Otworzysz go stąd '
                  'z dowolnego miejsca, przez tunel.'),
              style: const TextStyle(color: AppTheme.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            _field(_host, tr('Adres w LAN'), Icons.lan_outlined, hint: '192.168.1.1'),
            _field(_port, tr('Port'), Icons.tag, keyboard: TextInputType.number, hint: '80'),
            _field(_name, tr('Nazwa'), Icons.label_outline, hint: 'Router'),
            const SizedBox(height: 8),
            Text(
              tr('Tylko HTTP. Ciężkie panele (UniFi, HA) nie zadziałają — tunel jest wolny.'),
              style: const TextStyle(color: AppTheme.amber, fontSize: 11.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _finish(connect: true),
              icon: const Icon(Icons.open_in_browser),
              label: Text(tr('Połącz')),
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.teal, foregroundColor: Colors.black),
            ),
          ],
        ),
      );

  Widget _field(TextEditingController c, String label, IconData icon,
          {String? hint, TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: keyboard ?? TextInputType.url,
          style: const TextStyle(color: AppTheme.text),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: AppTheme.muted),
            hintText: hint,
            hintStyle: const TextStyle(color: AppTheme.muted),
            prefixIcon: Icon(icon, color: AppTheme.muted, size: 20),
            filled: true,
            fillColor: AppTheme.card,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      );
}
