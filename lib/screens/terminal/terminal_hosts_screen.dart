import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../../services/integrations/integration_store.dart';
import '../../services/integrations/ssh_secrets.dart';
import 'terminal_screen.dart';
import 'ssh_host_edit_screen.dart';

/// Plugin „Zdalny terminal" — lista zapisanych połączeń SSH w sieci noda, jak zakładki
/// paneli LAN. Wcześniej terminal pamiętał tylko ostatni adres, więc druga maszyna w tej
/// samej sieci znaczyła przepisywanie IP z głowy.
///
/// „V" przy wpisie = cel widgetu na pulpicie: stuknięcie w widget otwiera od razu ten host,
/// bez pytania o node. Jeden cel na całą apkę — widget ma być skrótem, nie kolejnym menu.
class TerminalHostsScreen extends StatefulWidget {
  final String deviceId;
  final String label;
  /// true = otwarto jako konfigurację przy dodawaniu pluginu (Navigator.pop(true) po zapisie).
  final bool configMode;
  const TerminalHostsScreen(
      {super.key, required this.deviceId, required this.label, this.configMode = false});

  @override
  State<TerminalHostsScreen> createState() => _TerminalHostsScreenState();
}

class _TerminalHostsScreenState extends State<TerminalHostsScreen> {
  List<SshHost> _hosts = [];
  String? _widgetSlug;      // slug celu widgetu, jeśli wskazuje na TEN node
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Przeniesienie starego, pojedynczego celu na listę — apka do niedawna pamiętała tylko
  /// ostatnio używany adres (`term_form_<node>`) i jedno hasło do niego. Robimy to RAZ,
  /// przy pierwszym wejściu na pustą listę, i sprzątamy stare klucze.
  Future<void> _importLegacyEntry() async {
    if (_hosts.isNotEmpty) return;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('term_form_${widget.deviceId}');
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final host = (j['host'] as String?)?.trim() ?? '';
      if (host.isEmpty) return;
      final h = SshHost(
        name: '',
        host: host,
        port: int.tryParse('${j['port'] ?? 22}') ?? 22,
        user: (j['user'] as String?)?.trim().isNotEmpty == true ? j['user'] as String : 'root',
      );
      await IntegrationStore.saveSshHosts(widget.deviceId, [h]);
      final pw = await SshSecrets.readLegacy(widget.deviceId);
      if (pw != null && pw.isNotEmpty) await SshSecrets.write(widget.deviceId, h.slug, pw);
      await SshSecrets.dropLegacy(widget.deviceId);
      await p.remove('term_form_${widget.deviceId}');
    } catch (_) {/* nieczytelny stary wpis to nie powód, żeby ekran nie wstał */}
  }

  Future<void> _load() async {
    var hosts = await IntegrationStore.sshHosts(widget.deviceId);
    if (hosts.isEmpty) {
      await _importLegacyEntry();
      hosts = await IntegrationStore.sshHosts(widget.deviceId);
    }
    final target = await IntegrationStore.widgetTermTarget();
    if (!mounted) return;
    setState(() {
      _hosts = hosts;
      _widgetSlug = (target != null && target.$1 == widget.deviceId) ? target.$2 : null;
      _loading = false;
    });
  }

  Future<void> _addOrEdit([SshHost? existing]) async {
    final res = await Navigator.push<(SshHost, bool)>(
      context,
      MaterialPageRoute(
          builder: (_) => SshHostEditScreen(deviceId: widget.deviceId, existing: existing)),
    );
    if (res == null) return;
    await _load();
    if (res.$2 && mounted) _open(res.$1);
  }

  /// Cel z hasłem → prosto w sesję. Bez hasła → TEN SAM ekran co przy „+" (nazwa u góry,
  /// hasło z podglądem, „Połącz"), żeby nie było dwóch różnych formularzy na to samo.
  Future<void> _open(SshHost? h) async {
    if (h != null) {
      final pw = await SshSecrets.read(widget.deviceId, h.slug);
      if (!mounted) return;
      if (pw == null || pw.isEmpty) { await _addOrEdit(h); return; }
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => TerminalScreen(deviceId: widget.deviceId, label: widget.label, host: h)),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text('${tr('Terminal')} · ${widget.label}'),
        actions: [
          if (widget.configMode)
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
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_hosts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
                    child: Text(
                      tr('Dodaj maszyny z sieci noda (serwer, NAS, Raspberry) — otworzysz je '
                          'stąd z dowolnego miejsca, przez tunel.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.muted, fontSize: 13),
                    ),
                  ),
                for (final h in _hosts)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.dns_outlined, color: AppTheme.teal),
                      title: Text(h.title, style: const TextStyle(color: AppTheme.text)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${h.user}@${h.host}:${h.port}',
                              style: const TextStyle(
                                  color: AppTheme.muted, fontSize: 12, fontFamily: 'monospace')),
                          if (_widgetSlug == h.slug)
                            Text(tr('Cel widgetu na pulpicie'),
                                style: const TextStyle(color: AppTheme.teal, fontSize: 11)),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppTheme.muted, size: 20),
                        onPressed: () async {
                          final list = List<SshHost>.from(_hosts)..removeWhere((e) => e.slug == h.slug);
                          await IntegrationStore.saveSshHosts(widget.deviceId, list);
                          if (_widgetSlug == h.slug) {
                            await IntegrationStore.setWidgetTermTarget(null, null);
                          }
                          await SshSecrets.forget(widget.deviceId, h.slug);
                          await _load();
                        },
                      ),
                      onTap: () => _open(h),
                      onLongPress: () => _addOrEdit(h),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _open(null),
                  icon: const Icon(Icons.terminal, size: 18),
                  label: Text(tr('Połączenie jednorazowe')),
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.muted),
                ),
                const SizedBox(height: 70),
              ],
            ),
    );
    if (!widget.configMode) return scaffold;
    // Jak w panelach LAN: systemowe „wstecz" też podpina plugin — inaczej dodanie kończy
    // się niczym, gdy user ominie „Gotowe".
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, true);
      },
      child: scaffold,
    );
  }
}
