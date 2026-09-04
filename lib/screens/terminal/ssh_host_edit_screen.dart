import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../../services/integrations/integration_store.dart';
import '../../services/integrations/ssh_secrets.dart';

/// Edytor zapisanego połączenia SSH — PEŁNY EKRAN, nie popup.
///
/// Ma dokładnie te same pola co formularz połączenia jednorazowego (adres, port, użytkownik,
/// hasło + „zapamiętaj"), plus nazwę. Wcześniej lista zapisywała sam adres i nazwę, więc
/// zapamiętane hasło z sesji nie miało się gdzie podłączyć.
class SshHostEditScreen extends StatefulWidget {
  final String deviceId;
  final SshHost? existing;
  const SshHostEditScreen({super.key, required this.deviceId, this.existing});

  @override
  State<SshHostEditScreen> createState() => _SshHostEditScreenState();
}

class _SshHostEditScreenState extends State<SshHostEditScreen> {
  late final _host = TextEditingController(text: widget.existing?.host ?? '');
  late final _port = TextEditingController(text: '${widget.existing?.port ?? 22}');
  late final _user = TextEditingController(text: widget.existing?.user ?? 'root');
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  final _pass = TextEditingController();
  bool _savePass = false;
  bool _showPass = false;
  bool _isWidgetTarget = false;   // ten cel otwiera widget „Terminal" bez pytania
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ex = widget.existing;
    if (ex != null) {
      final pw = await SshSecrets.read(widget.deviceId, ex.slug);
      if (pw != null && pw.isNotEmpty) { _pass.text = pw; _savePass = true; }
      final t = await IntegrationStore.widgetTermTarget();
      _isWidgetTarget = t != null && t.$1 == widget.deviceId && t.$2 == ex.slug;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in [_host, _port, _user, _name, _pass]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save({bool connect = false}) async {
    final host = _host.text.trim();
    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Podaj adres w sieci noda.'))));
      return;
    }
    final h = SshHost(
      name: _name.text.trim(),
      host: host,
      port: int.tryParse(_port.text.trim()) ?? 22,
      user: _user.text.trim().isEmpty ? 'root' : _user.text.trim(),
    );
    final list = await IntegrationStore.sshHosts(widget.deviceId);
    final ex = widget.existing;
    // Zmiana adresu/portu/usera zmienia slug — stary sekret przestaje być czyjkolwiek.
    if (ex != null && ex.slug != h.slug) await SshSecrets.forget(widget.deviceId, ex.slug);
    list.removeWhere((e) => e.slug == h.slug || (ex != null && e.slug == ex.slug));
    list.add(h);
    await IntegrationStore.saveSshHosts(widget.deviceId, list);

    if (_savePass && _pass.text.isNotEmpty) {
      await SshSecrets.write(widget.deviceId, h.slug, _pass.text);
    } else {
      await SshSecrets.forget(widget.deviceId, h.slug);
    }

    // Cel widgetu jest jeden na całą apkę: włączenie tutaj przejmuje go poprzedniemu,
    // wyłączenie czyści tylko wtedy, gdy wskazywał na TEN cel.
    final t = await IntegrationStore.widgetTermTarget();
    final wasThis = t != null && t.$1 == widget.deviceId &&
        (t.$2 == h.slug || (ex != null && t.$2 == ex.slug));
    if (_isWidgetTarget) {
      await IntegrationStore.setWidgetTermTarget(widget.deviceId, h.slug);
    } else if (wasThis) {
      await IntegrationStore.setWidgetTermTarget(null, null);
    }
    if (mounted) Navigator.pop(context, (h, connect));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(widget.existing == null ? tr('Nowe połączenie') : tr('Edytuj połączenie')),
        actions: [
          TextButton(
            onPressed: () => _save(),
            child: Text(tr('Zapisz'), style: const TextStyle(color: AppTheme.teal)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.teal))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  tr('Maszyna w sieci noda — otworzysz ją stąd z dowolnego miejsca, przez tunel.'),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12.5),
                ),
                const SizedBox(height: 16),
                _field(_host, tr('Host w sieci noda'), Icons.lan_outlined, hint: '192.168.1.1'),
                Row(children: [
                  Expanded(flex: 2, child: _field(_port, tr('Port'), Icons.tag, keyboard: TextInputType.number)),
                  const SizedBox(width: 10),
                  Expanded(flex: 3, child: _field(_user, tr('Użytkownik SSH'), Icons.person_outline)),
                ]),
                _field(_pass, tr('Hasło SSH'), Icons.lock_outline, obscure: !_showPass, suffix: IconButton(
                  icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility,
                      color: AppTheme.muted, size: 20),
                  onPressed: () => setState(() => _showPass = !_showPass),
                )),
                InkWell(
                  onTap: () => setState(() => _savePass = !_savePass),
                  child: Row(children: [
                    Checkbox(
                      value: _savePass,
                      onChanged: (v) => setState(() => _savePass = v ?? false),
                      activeColor: AppTheme.teal,
                      checkColor: Colors.black,
                      visualDensity: VisualDensity.compact,
                    ),
                    Expanded(
                      child: Text(tr('Zapamiętaj hasło na tym telefonie'),
                          style: const TextStyle(color: AppTheme.muted, fontSize: 12.5)),
                    ),
                  ]),
                ),
                const SizedBox(height: 6),
                _field(_name, tr('Nazwa'), Icons.label_outline, hint: 'NAS'),
                // Ten sam przełącznik co przy Home Assistant — zamiast ptaszka na liście,
                // po którym nie było widać, co właściwie robi.
                Card(
                  color: AppTheme.card,
                  child: SwitchListTile(
                    value: _isWidgetTarget,
                    activeColor: AppTheme.teal,
                    onChanged: (v) => setState(() => _isWidgetTarget = v),
                    title: Text(tr('Cel widgetu „Terminal"'),
                        style: const TextStyle(color: AppTheme.text, fontSize: 14)),
                    subtitle: Text(
                        tr('Widget na pulpicie otworzy od razu to połączenie, bez pytania.'),
                        style: const TextStyle(color: AppTheme.muted, fontSize: 11.5)),
                    secondary: const Icon(Icons.widgets_outlined, color: AppTheme.muted),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('SSH jest szyfrowany end-to-end — node i nasze serwery przekazują tylko '
                      'zaszyfrowane bajty.'),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11.5),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => _save(connect: true),
                  icon: const Icon(Icons.terminal),
                  label: Text(tr('Połącz')),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.teal, foregroundColor: Colors.black),
                ),
              ],
            ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon,
          {String? hint, bool obscure = false, TextInputType? keyboard, Widget? suffix}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: obscure,
          keyboardType: keyboard,
          style: const TextStyle(color: AppTheme.text),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: AppTheme.muted),
            hintText: hint,
            hintStyle: const TextStyle(color: AppTheme.muted),
            prefixIcon: Icon(icon, color: AppTheme.muted, size: 20),
            suffixIcon: suffix,
            filled: true,
            fillColor: AppTheme.card,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      );
}
