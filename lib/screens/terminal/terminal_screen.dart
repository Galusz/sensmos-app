import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../../services/wallet_service.dart';
import '../../services/terminal_relay.dart';
import '../../services/pairing_service.dart';
import '../../util/pair_gate.dart';

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
  bool _paired = false;
  bool _legacy = false;   // node na FW ≤0.81 — tunel starą ścieżką (tryb przejściowy)
  Uint8List? _pairKey;
  bool _savePass = false;

  // Zapamiętane pola formularza — PER NODE, bo każdy stoi w innej sieci i celujesz w co innego.
  // Hasło NIGDY nie idzie do SharedPreferences: to zwykły plik XML w katalogu apki. Ląduje
  // w tym samym szyfrowanym magazynie co klucze parowania i tylko za zgodą użytkownika.
  static const _formPrefix = 'term_form_';
  static const _passPrefix = 'term_pass_';
  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  void initState() {
    super.initState();
    _loadForm();
    _connect();
  }

  Future<void> _loadForm() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('$_formPrefix${widget.deviceId}');
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        if (j['host'] is String) _host.text = j['host'] as String;
        if (j['port'] is String) _port.text = j['port'] as String;
        if (j['user'] is String) _user.text = j['user'] as String;
        _savePass = j['savePass'] == true;
      }
      if (_savePass) {
        _pass.text = await _secure.read(key: '$_passPrefix${widget.deviceId}') ?? '';
      }
      if (mounted) setState(() {});
    } catch (_) {/* brak zapamiętanych wartości to nie błąd — zostają domyślne */}
  }

  /// Zapis DOPIERO po udanym połączeniu. Zapisywanie przy każdej próbie utrwaliłoby literówki
  /// — np. domyślne 192.168.1.1, pod którym w Twojej sieci nic nie stoi — i apka podsuwałaby
  /// je przy każdym wejściu.
  Future<void> _saveForm() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('$_formPrefix${widget.deviceId}', jsonEncode({
        'host': _host.text.trim(),
        'port': _port.text.trim(),
        'user': _user.text.trim(),
        'savePass': _savePass,
      }));
      final k = '$_passPrefix${widget.deviceId}';
      if (_savePass) {
        await _secure.write(key: k, value: _pass.text);
      } else {
        await _secure.delete(key: k);   // odznaczone = kasujemy też to, co zapisaliśmy wcześniej
      }
    } catch (_) {}
  }

  Future<void> _connect() async {
    _relay?.dispose(); _relay = null;   // retry: bez tego każda próba zostawia martwy WS + dubluje listener
    setState(() { _phase = _Phase.connecting; _status = tr('Łączę z relayem…'); });
    try {
      final wallet = await context.read<WalletService>().load();
      if (wallet == null) throw Exception(tr('Brak portfela w apce'));

      // Klucz MUSI być wczytany przed budową relaya — on go dostaje przez konstruktor
      // i bez niego openTunnel od razu odmówi. Brak klucza nie jest tu błędem: ekran
      // pokaże kartę „niesparowany" z przyciskiem parowania.
      final svc = PairingService();
      _pairKey = await svc.keyFor(widget.deviceId);
      _legacy  = await svc.isLegacy(widget.deviceId);
      _paired  = _pairKey != null || _legacy;

      final relay = TerminalRelay(
        deviceId: widget.deviceId,
        owner: wallet.address,
        signMessage: (m) => context.read<WalletService>().signMessage(m),
        pairKey: _pairKey,
        legacy: _legacy,
      );
      _relay = relay;                   // track wcześnie → dispose posprząta też gdy connect rzuci
      relay.events.listen(_onEvent);
      await relay.connect();
      if (!mounted) return;
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

  /// Parowanie: klucz trafia do noda po LAN, z pominięciem naszego serwera. Dopiero on
  /// uprawnia do otwarcia tunelu — backend sam z siebie tego nie zrobi.
  Future<void> _doPair() async {
    final acc = await ensurePaired(context, widget.deviceId);
    if (!mounted) return;
    // Żywy relay musi dostać dostęp, inaczej openTunnel dalej odmawia.
    _relay?.pairKey = acc.key;
    _relay?.legacy  = acc.legacy;
    setState(() {
      _pairKey = acc.key;
      _legacy  = acc.legacy;
      _paired  = acc.ok;
      if (acc.ok) _status = tr('Node sparowany — możesz się połączyć.');
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
      _saveForm();   // fire-and-forget: połączenie działa, więc te wartości warto zapamiętać
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
    // JEDEN sposób wyjścia: BACK. Zamyka sesję SSH, tunel na nodzie i relay (patrz dispose),
    // więc firmware oddaje ~27 kB heapu — potrzebne monitorom. Osobny przycisk „Rozłącz"
    // wyglądał identycznie, a zostawiał tunel zamknięty, ale ekran i WS żywe; przy dwóch
    // kontrolkach od tego samego lepiej zostawić tę, którą użytkownik i tak zna.
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: Text('${tr('Terminal')} · $short')),
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
          // Tylko gdy czegoś brakuje. Potwierdzanie „sparowany" przy każdym wejściu to szum —
          // o wymogu user dowiaduje się przy dodawaniu integracji, tu zostaje sama droga wyjścia.
          if (!_paired) ...[
            Card(
              color: AppTheme.card,
              child: ListTile(
                leading: const Icon(Icons.vpn_key_outlined, color: AppTheme.amber),
                title: Text(tr('Node niesparowany'), style: const TextStyle(color: AppTheme.text)),
                subtitle: Text(
                  tr('Zdalny dostęp wymaga jednorazowego sparowania w tej samej sieci WiFi co node.'),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
                trailing: FilledButton(
                  onPressed: _doPair,
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.teal, foregroundColor: Colors.black),
                  child: Text(tr('Sparuj')),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          _field(_host, tr('Host w sieci noda'), Icons.lan_outlined, hint: '192.168.1.1'),
          Row(children: [
            Expanded(flex: 2, child: _field(_port, tr('Port'), Icons.tag, keyboard: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(flex: 3, child: _field(_user, tr('Użytkownik SSH'), Icons.person_outline)),
          ]),
          _field(_pass, tr('Hasło SSH'), Icons.lock_outline, obscure: true),
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
          const SizedBox(height: 8),
          Text(
            tr('SSH jest szyfrowany end-to-end — node i nasze serwery przekazują tylko zaszyfrowane bajty.'),
            style: const TextStyle(color: AppTheme.muted, fontSize: 11.5),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _paired ? _startSession : null,
            icon: const Icon(Icons.terminal),
            label: Text(tr('Połącz')),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.teal, foregroundColor: Colors.black),
          ),
          if (!_paired) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(tr('Najpierw sparuj node powyżej.'),
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
