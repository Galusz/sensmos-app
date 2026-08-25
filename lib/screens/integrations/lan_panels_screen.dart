import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../../services/integrations/integration_store.dart';
import 'lan_web_screen.dart';

/// Plugin „Panel LAN" — zakładki do paneli WWW w sieci noda (router, drukarka, Pi-hole…),
/// otwierane przez tunel z dowolnego miejsca. Ten ekran = konfiguracja + lista.
/// Tylko HTTP i lekkie panele — ciężkie SPA (UniFi/HA/Proxmox) przez tunel nie pojadą.
class LanPanelsScreen extends StatefulWidget {
  final String deviceId;
  final String label;
  /// true = otwarto jako konfigurację przy dodawaniu pluginu (Navigator.pop(true) po zapisie).
  final bool configMode;
  const LanPanelsScreen(
      {super.key, required this.deviceId, required this.label, this.configMode = false});

  @override
  State<LanPanelsScreen> createState() => _LanPanelsScreenState();
}

class _LanPanelsScreenState extends State<LanPanelsScreen> {
  List<LanPanel> _panels = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    IntegrationStore.lanPanels(widget.deviceId).then((p) {
      if (mounted) setState(() { _panels = p; _loading = false; });
    });
  }

  Future<void> _addOrEdit([LanPanel? existing]) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final host = TextEditingController(text: existing?.host ?? '');
    final port = TextEditingController(text: '${existing?.port ?? 80}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(existing == null ? tr('Dodaj panel') : tr('Edytuj panel'),
            style: const TextStyle(color: AppTheme.text)),
        // Adres PIERWSZY (to on jest obowiązkowy — z IP wpisanym w „Nazwę" zapis kończył
        // się cichym niczym); SizedBox daje TextFieldom skończoną szerokość w AlertDialog.
        content: SizedBox(
          width: 320,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _field(host, tr('Adres w LAN'), hint: '192.168.1.1'),
            _field(port, tr('Port'), hint: '80', number: true),
            _field(name, tr('Nazwa'), hint: 'Router'),
            const SizedBox(height: 6),
            Text(tr('Tylko HTTP. Ciężkie panele (UniFi, HA) nie zadziałają — tunel jest wolny.'),
                style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Anuluj'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.teal),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Zapisz'), style: const TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    if (saved != true) return;
    var h = host.text.trim().replaceFirst(RegExp(r'^https?://'), '').split('/').first;
    // Ratunek: adres wpisany w polu „Nazwa" (wygląda jak IP/host) — bierzemy go stamtąd.
    if (h.isEmpty) {
      final n = name.text.trim().replaceFirst(RegExp(r'^https?://'), '').split('/').first;
      if (n.contains('.') && !n.contains(' ')) h = n;
    }
    // Adres z doklejonym portem ("192.168.1.1:8080") — rozdziel.
    if (h.contains(':')) {
      final parts = h.split(':');
      h = parts[0];
      if (int.tryParse(parts[1]) != null) port.text = parts[1];
    }
    if (h.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('Podaj adres w LAN')), backgroundColor: AppTheme.red));
      }
      return;
    }
    setState(() {
      if (existing != null) {
        existing.name = name.text.trim().isEmpty ? h : name.text.trim();
        existing.host = h;
        existing.port = int.tryParse(port.text.trim()) ?? 80;
      } else {
        _panels.add(LanPanel(
            name: name.text.trim().isEmpty ? h : name.text.trim(),
            host: h,
            port: int.tryParse(port.text.trim()) ?? 80));
      }
    });
    await IntegrationStore.saveLanPanels(widget.deviceId, _panels);
  }

  Widget _field(TextEditingController c, String label, {String? hint, bool number = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: TextField(
          controller: c,
          keyboardType: number ? TextInputType.number : TextInputType.url,
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
  Widget build(BuildContext context) {
    // W trybie konfiguracji systemowe „wstecz" też ma podpiąć plugin, jeśli user dodał
    // choć jeden panel — bez tego dodanie kończyło się niczym, gdy ominął „Gotowe".
    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text('${tr('Panel LAN')} · ${widget.label}'),
        actions: [
          if (widget.configMode && _panels.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Gotowe'), style: const TextStyle(color: AppTheme.teal)),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.teal,
        onPressed: _addOrEdit,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.teal))
          : _panels.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr('Dodaj panele WWW z sieci noda (router, drukarka, Pi-hole…) — '
                          'otworzysz je stąd z dowolnego miejsca, przez tunel.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.muted, fontSize: 13),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _panels.length,
                  itemBuilder: (_, i) {
                    final p = _panels[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.language, color: AppTheme.teal),
                        title: Text(p.name, style: const TextStyle(color: AppTheme.text)),
                        subtitle: Text('http://${p.host}:${p.port}',
                            style: const TextStyle(
                                color: AppTheme.muted, fontSize: 12, fontFamily: 'monospace')),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppTheme.muted, size: 20),
                          onPressed: () async {
                            setState(() => _panels.removeAt(i));
                            await IntegrationStore.saveLanPanels(widget.deviceId, _panels);
                          },
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => LanWebScreen(
                                  deviceId: widget.deviceId, panel: p)),
                        ),
                        onLongPress: () => _addOrEdit(p),
                      ),
                    );
                  },
                ),
    );
    if (!widget.configMode) return scaffold;
    // Tryb konfiguracji: systemowe „wstecz" podpina plugin, jeśli jest choć jeden panel —
    // wcześniej dodanie kończyło się niczym, gdy user ominął przycisk „Gotowe".
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _panels.isNotEmpty);
      },
      child: scaffold,
    );
  }
}
