import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../../services/integrations/integration_store.dart';
import 'lan_web_screen.dart';
import 'lan_panel_edit_screen.dart';

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

  Future<void> _addOrEdit({LanPanel? existing, bool oneOff = false}) async {
    final res = await Navigator.push<(LanPanel, bool, bool)>(
      context,
      MaterialPageRoute(
          builder: (_) => LanPanelEditScreen(
              deviceId: widget.deviceId, existing: existing, oneOff: oneOff)),
    );
    if (res == null) return;
    final (panel, connect, wasOneOff) = res;
    if (!wasOneOff) {
      final list = List<LanPanel>.from(_panels);
      if (existing != null) list.removeWhere((e) => e.host == existing.host && e.port == existing.port);
      list.removeWhere((e) => e.host == panel.host && e.port == panel.port);
      list.add(panel);
      await IntegrationStore.saveLanPanels(widget.deviceId, list);
      if (mounted) setState(() => _panels = list);
    }
    if (connect && mounted) _open(panel);
  }

  void _open(LanPanel p) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LanWebScreen(deviceId: widget.deviceId, panel: p)),
      );

  @override
  Widget build(BuildContext context) {
    // W trybie konfiguracji systemowe „wstecz" też ma podpiąć plugin, jeśli user dodał
    // choć jeden panel — bez tego dodanie kończyło się niczym, gdy ominął „Gotowe".
    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text('${tr('HTTP w LAN')} · ${widget.label}'),
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
        onPressed: () => _addOrEdit(),
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
                  // +1: żółta notka pod listą — uczciwe zarządzanie oczekiwaniami, żeby
                  // „nie działa mi UniFi/kamera" nie wracało jako zgłoszenie błędu.
                  itemCount: _panels.length + 1,
                  itemBuilder: (_, i) {
                    if (i == _panels.length) {
                      return Column(children: [
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _addOrEdit(oneOff: true),
                          icon: const Icon(Icons.open_in_browser, size: 18),
                          label: Text(tr('Połączenie jednorazowe')),
                          style: OutlinedButton.styleFrom(foregroundColor: AppTheme.muted),
                        ),
                        Padding(
                        padding: const EdgeInsets.fromLTRB(8, 14, 8, 80),
                        child: Text(
                          tr('Uwaga: to lekka wersja proxy, nie pełny tunel — jedno połączenie '
                              'naraz, bez WebSocketów i strumieni. Proste panele HTTP zadziałają, '
                              'ciężkie aplikacje nie.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.amber, fontSize: 11),
                        ),
                      )]);
                    }
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
                        onLongPress: () => _addOrEdit(existing: p),
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
