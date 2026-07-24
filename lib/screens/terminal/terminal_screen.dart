import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../../services/wallet_service.dart';
import '../../services/terminal_relay.dart';
import '../../util/pin_gate.dart';

/// RemoteTerminal — zdalny terminal do LAN-u noda przez tunel. Node = głupia rura, SSH E2E w apce.
/// Bierze device_id + etykietę (NIE SavedNode) — działa też dla nodów widocznych tylko z BE
/// (bez lokalnego wpisu), bo tunel idzie przez relay, nie po lokalnej sieci.
class TerminalScreen extends StatefulWidget {
  final String deviceId;
  final String label;
  const TerminalScreen({super.key, required this.deviceId, required this.label});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

enum _Phase { connecting, form, session, error }

class _TerminalScreenState extends State<TerminalScreen> {
  _Phase _phase = _Phase.connecting;
  String _status = '';
  TerminalRelay? _relay;
  SSHClient? _ssh;
  SSHSession? _session;
  Timer? _resizeDebounce;
  int _rw = 0, _rh = 0;

  final _terminal = Terminal(maxLines: 10000);
  final _host = TextEditingController(text: '192.168.1.1');
  final _port = TextEditingController(text: '22');
  final _user = TextEditingController(text: 'root');
  final _pass = TextEditingController();
  bool _remoteOn = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    _relay?.dispose(); _relay = null;   // retry: bez tego każda próba zostawia martwy WS + dubluje listener
    setState(() { _phase = _Phase.connecting; _status = tr('Łączę z relayem…'); });
    try {
      final wallet = await context.read<WalletService>().load();
      if (wallet == null) throw Exception(tr('Brak portfela w apce'));
      final relay = TerminalRelay(
        deviceId: widget.deviceId,
        owner: wallet.address,
        signMessage: (m) => context.read<WalletService>().signMessage(m),
      );
      _relay = relay;                   // track wcześnie → dispose posprząta też gdy connect rzuci
      relay.events.listen(_onEvent);
      await relay.connect();
      if (!mounted) return;
      _remoteOn = relay.remoteEnabled;
      if (!relay.nodeOnline) {
        // node nie ma żywego połączenia z chmurą — bez niego tunel nie ruszy
        setState(() { _phase = _Phase.error; _status = tr('Node jest offline — nie połączysz się z nim, dopóki nie wróci do sieci.'); });
        return;
      }
      setState(() { _phase = _Phase.form; _status = ''; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _phase = _Phase.error; _status = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  void _onEvent(String ev) {
    if (!mounted) return;
    // "down:<msg>" = transport/auth PADŁ (fatalne) → ekran błędu z „Spróbuj ponownie".
    // Bez tego sesyjny widok (sam TerminalView, brak paska statusu) wisi w miejscu i user
    // myśli, że apka zamarła — nie wie, że trzeba wyjść i wejść od nowa.
    if (ev.startsWith('down:')) {
      setState(() { _phase = _Phase.error; _status = tr('Połączenie zerwane — dotknij „Spróbuj ponownie".'); });
    } else if (ev.startsWith('error:')) {
      setState(() => _status = ev.substring(6));
    } else if (ev.startsWith('state:')) {
      final parts = ev.split(':');
      final st = parts.length > 1 ? parts[1] : '';
      if (st == 'error' || st == 'closed') {
        setState(() => _status = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : 'tunnel $st');
      }
    }
  }

  Future<void> _toggleRemote(bool on) async {
    if (on && !await confirmNodePin(context, widget.deviceId)) {
      if (!mounted) return;
      setState(() => _status = tr('Zły PIN — remote access nie włączony'));
      return;
    }
    _relay?.setRemote(on);
    if (!mounted) return;
    setState(() {
      _remoteOn = on;
      _status = on
          ? tr('Remote access WŁĄCZONY — ten node będzie rzadziej wybierany do monitorów')
          : tr('Remote access wyłączony');
    });
  }

  Future<void> _startSession() async {
    final relay = _relay;
    if (relay == null) return;
    final ip = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 22;
    if (ip.isEmpty) return;
    setState(() { _phase = _Phase.connecting; _status = tr('Otwieram tunel → %s:%s…', [ip, port]); });
    try {
      final socket = await relay.openTunnel(ip, port);
      final ssh = SSHClient(
        socket,
        username: _user.text.trim().isEmpty ? 'root' : _user.text.trim(),
        onPasswordRequest: () => _pass.text,
      );
      _ssh = ssh;
      final session = await ssh.shell(
        pty: SSHPtyConfig(width: _terminal.viewWidth, height: _terminal.viewHeight),
      );
      _session = session;
      _terminal.onOutput = (data) => session.write(utf8.encode(data));
      // Dynamiczny resize (htop skaluje się do ekranu). Debounce 300ms — chowanie klawiatury sypie
      // serią resize, wysyłamy tylko końcowy (jeden SIGWINCH zamiast lawiny).
      _terminal.onResize = (w, h, pw, ph) {
        if (w <= 0 || h <= 0) return;
        _rw = w; _rh = h;
        _resizeDebounce?.cancel();
        _resizeDebounce = Timer(const Duration(milliseconds: 300),
            () { try { _session?.resizeTerminal(_rw, _rh); } catch (_) {} });
      };
      session.stdout.listen((d) => _terminal.write(utf8.decode(d, allowMalformed: true)));
      session.stderr.listen((d) => _terminal.write(utf8.decode(d, allowMalformed: true)));
      session.done.then((_) {
        if (mounted && _phase == _Phase.session) {
          setState(() { _status = tr('Sesja zakończona'); _phase = _Phase.form; });
        }
      });
      if (!mounted) return;
      setState(() { _phase = _Phase.session; _status = ''; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _phase = _Phase.form; _status = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  void _disconnect() {
    try { _ssh?.close(); } catch (_) {}
    _ssh = null;
    setState(() { _phase = _Phase.form; _status = tr('Rozłączono'); });
  }

  @override
  void dispose() {
    _resizeDebounce?.cancel();
    try { _ssh?.close(); } catch (_) {}
    _relay?.dispose();
    _host.dispose(); _port.dispose(); _user.dispose(); _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final short = widget.deviceId.length > 8 ? widget.deviceId.substring(0, 8) : widget.deviceId;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text('${tr('Terminal')} · $short'),
        actions: [
          if (_phase == _Phase.session)
            IconButton(icon: const Icon(Icons.link_off), tooltip: tr('Rozłącz'), onPressed: _disconnect),
        ],
      ),
      body: switch (_phase) {
        _Phase.connecting => _center(const CircularProgressIndicator(color: AppTheme.teal)),
        _Phase.error => _errorView(),
        _Phase.form => _formView(),
        _Phase.session => _sessionView(),
      },
    );
  }

  Widget _center(Widget w) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          w,
          if (_status.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_status, style: const TextStyle(color: AppTheme.muted)),
          ),
        ]),
      );

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: AppTheme.amber, size: 40),
            const SizedBox(height: 12),
            Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.text)),
            const SizedBox(height: 20),
            FilledButton(onPressed: _connect, child: Text(tr('Spróbuj ponownie'))),
          ]),
        ),
      );

  Widget _formView() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: AppTheme.card,
            child: SwitchListTile(
              value: _remoteOn,
              onChanged: _toggleRemote,
              activeThumbColor: AppTheme.teal,
              title: Text(tr('Remote access na nodzie'), style: const TextStyle(color: AppTheme.text)),
              subtitle: Text(
                tr('Pozwala łączyć się z urządzeniami w sieci noda. Włączony node jest rzadziej wybierany do monitorów.'),
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
              secondary: const Icon(Icons.vpn_key_outlined, color: AppTheme.teal),
            ),
          ),
          const SizedBox(height: 8),
          _field(_host, tr('Host w sieci noda'), Icons.lan_outlined, hint: '192.168.1.1'),
          Row(children: [
            Expanded(flex: 2, child: _field(_port, tr('Port'), Icons.tag, keyboard: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(flex: 3, child: _field(_user, tr('Użytkownik SSH'), Icons.person_outline)),
          ]),
          _field(_pass, tr('Hasło SSH'), Icons.lock_outline, obscure: true),
          const SizedBox(height: 8),
          Text(
            tr('SSH jest szyfrowany end-to-end — node i nasze serwery przekazują tylko zaszyfrowane bajty.'),
            style: const TextStyle(color: AppTheme.muted, fontSize: 11.5),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _remoteOn ? _startSession : null,
            icon: const Icon(Icons.terminal),
            label: Text(tr('Połącz')),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.teal, foregroundColor: Colors.black),
          ),
          if (!_remoteOn) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(tr('Najpierw włącz remote access powyżej.'),
                style: const TextStyle(color: AppTheme.amber, fontSize: 12)),
          ),
          if (_status.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(_status, style: const TextStyle(color: AppTheme.muted, fontSize: 12.5)),
          ),
        ],
      );

  Widget _sessionView() => Container(
        color: const Color(0xFF05070B),
        child: SafeArea(
          child: TerminalView(
            _terminal,
            textStyle: const TerminalStyle(fontSize: 13, fontFamily: 'monospace'),
            padding: const EdgeInsets.all(8),
          ),
        ),
      );

  Widget _field(TextEditingController c, String label, IconData icon,
          {bool obscure = false, String? hint, TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          controller: c,
          obscureText: obscure,
          keyboardType: keyboard,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(color: AppTheme.text),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            hintStyle: const TextStyle(color: AppTheme.muted),
            labelStyle: const TextStyle(color: AppTheme.muted),
            prefixIcon: Icon(icon, color: AppTheme.muted, size: 20),
            filled: true,
            fillColor: AppTheme.card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      );
}
