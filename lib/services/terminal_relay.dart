import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:dartssh2/dartssh2.dart';
import '../config.dart';

/// RemoteTerminal — most apka↔BE(/v1/term)↔node.
/// Owner-auth podpisem portfela; otwiera tunel TCP na nodzie (np. 192.168.1.1:22) i wystawia
/// [SSHSocket] dla dartssh2. Node to głupia rura — cała krypto SSH jest tu (E2E), BE/node nie
/// widzą haseł SSH. Jeden WS na żywotność ekranu: connect() → setRemote()/openTunnel().
class TerminalRelay {
  final String deviceId;
  final String owner;
  final Future<String> Function(String message) signMessage;

  WebSocketChannel? _ch;
  _RelaySocket? _sock;
  bool _authed = false;
  bool nodeOnline = false;
  bool remoteEnabled = false;

  final _events = StreamController<String>.broadcast(); // "state:<st>:<msg>" / "error:<msg>"
  Stream<String> get events => _events.stream;
  StreamSubscription? _sub;
  void _emit(String s) { if (!_events.isClosed) _events.add(s); }

  Completer<void>? _auth;
  Completer<SSHSocket>? _open;

  TerminalRelay({required this.deviceId, required this.owner, required this.signMessage});

  String get _wsUrl => '${Config.beUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://')}/v1/term';

  /// Połącz i uwierzytelnij jako właściciel noda. Rzuca przy odmowie/timeout.
  Future<void> connect() async {
    _auth = Completer<void>();
    _ch = WebSocketChannel.connect(Uri.parse(_wsUrl));
    _sub = _ch!.stream.listen(_onMessage,
        onError: (e) => _fail('connection error: $e'), onDone: () => _fail('connection closed'));
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sig = await signMessage('sensmos:term:$deviceId:$ts');
    _send({'type': 'auth', 'device_id': deviceId, 'owner': owner, 'ts': ts, 'sig': sig});
    await _auth!.future.timeout(const Duration(seconds: 12),
        onTimeout: () => throw Exception('auth timeout'));
  }

  /// Włącz/wyłącz remote access na nodzie (opt-in; przy ON node jest mniej wybierany do monitorów).
  void setRemote(bool on) {
    if (!_authed) return;
    _send({'type': 'cfg', 'enable': on});
    remoteEnabled = on;
  }

  /// Otwórz tunel TCP do ip:port na LAN-ie noda; zwraca SSHSocket dla SSHClient.
  Future<SSHSocket> openTunnel(String ip, int port) async {
    if (!_authed) throw Exception('not authenticated');
    _open = Completer<SSHSocket>();
    _send({'type': 'open', 'ip': ip, 'port': port});
    return _open!.future.timeout(const Duration(seconds: 20),
        onTimeout: () => throw Exception('tunnel open timeout'));
  }

  // sink bywa zamknięty (dispose/rozłączenie), a dartssh2 przy zamykaniu dopina jeszcze
  // pakiet „disconnect" → add po close rzucał „Cannot add event after closing" i wywalał apkę
  void _send(Map<String, dynamic> m) { try { _ch?.sink.add(jsonEncode(m)); } catch (_) {} }

  void _onMessage(dynamic raw) {
    Map<String, dynamic> m;
    try { m = jsonDecode(raw as String) as Map<String, dynamic>; } catch (_) { return; }
    switch (m['type']) {
      case 'auth':
        if (m['ok'] == true) {
          _authed = true;
          nodeOnline = m['online'] == true;
          remoteEnabled = m['remote'] == true;
          if (_auth != null && !_auth!.isCompleted) _auth!.complete();
        } else {
          _fail('auth: ${m['error'] ?? 'denied'}');
        }
        break;
      case 'tun_state':
        final st = m['st'] ?? '';
        _emit('state:$st:${m['msg'] ?? ''}');
        if (st == 'open') {
          _sock = _RelaySocket(
            // chunk już ≤1024B (chunkowanie + paceowanie robi _RelaySocket._pumpOut) — node dekoduje
            // do bufora TUN_CHUNK=1024B; pace chroni przed przepełnieniem s_toLan przy długiej linii
            onSend: (chunk) => _send({'type': 'data', 'd': base64Encode(chunk)}),
            onClose: () => _send({'type': 'close'}),
          );
          if (_open != null && !_open!.isCompleted) _open!.complete(_sock!);
        } else if (st == 'closed' || st == 'error') {
          _sock?.remoteClosed();
          if (_open != null && !_open!.isCompleted) {
            _open!.completeError(Exception('tunnel $st: ${m['msg'] ?? ''}'));
          }
        }
        break;
      case 'tun_data':
        final d = m['d'];
        if (d is String && _sock != null) {
          try { _sock!.feed(base64Decode(d)); } catch (_) {}
        }
        break;
    }
  }

  void _fail(String msg) {
    _emit('down:$msg');   // FATALNE: transport/auth padł (odróżnia od błędów pojedynczej operacji)
    if (_auth != null && !_auth!.isCompleted) _auth!.completeError(Exception(msg));
    if (_open != null && !_open!.isCompleted) _open!.completeError(Exception(msg));
  }

  void dispose() {
    try { _sub?.cancel(); } catch (_) {}   // NAJPIERW — inaczej onDone woła _fail po zamknięciu _events (crash)
    try { _sock?.destroy(); } catch (_) {}
    try { _ch?.sink.close(); } catch (_) {}
    if (!_events.isClosed) _events.close();
  }
}

/// SSHSocket na kanale relay: bajty SSH klienta → tun_data(app→LAN); tun_data(LAN→app) → strumień.
class _RelaySocket implements SSHSocket {
  final void Function(List<int> data) onSend;
  final void Function() onClose;
  final _incoming = StreamController<Uint8List>();
  final _outgoing = StreamController<List<int>>();
  final _done = Completer<void>();

  StreamSubscription? _outSub;
  final _outBuf = <int>[];
  bool _pumping = false, _closed = false;

  _RelaySocket({required this.onSend, required this.onClose}) {
    _outSub = _outgoing.stream.listen((data) { _outBuf.addAll(data); _pumpOut(); });
  }

  // Paceowanie app→LAN: dartssh2 zrzuca długą linię/paste jako kilka KB naraz. Node dekoduje do
  // bufora s_toLan (głęb. 6) i pisze do LAN — blast >6 chunków przepełnia go szybciej niż zdąży
  // zapisać → drop → SSH MAC fail → serwer wypisuje „Error" i rozłącza. Wysyłamy po 1024B z
  // mikro-oddechem, żeby node zdrenował do LAN między chunkami (małe wpisy i tak lecą od razu).
  Future<void> _pumpOut() async {
    if (_pumping) return;
    _pumping = true;
    while (_outBuf.isNotEmpty && !_closed) {
      final n = _outBuf.length < 1024 ? _outBuf.length : 1024;
      final chunk = Uint8List.fromList(_outBuf.sublist(0, n));
      _outBuf.removeRange(0, n);
      onSend(chunk);
      if (_outBuf.isNotEmpty) await Future.delayed(const Duration(milliseconds: 3));
    }
    _pumping = false;
  }

  void feed(Uint8List data) { if (!_incoming.isClosed) _incoming.add(data); }
  void remoteClosed() => _finish();

  @override
  Stream<Uint8List> get stream => _incoming.stream;
  @override
  StreamSink<List<int>> get sink => _outgoing.sink;
  @override
  Future<void> get done => _done.future;
  @override
  Future<void> close() { onClose(); _finish(); return _done.future; }
  @override
  void destroy() { onClose(); _finish(); }

  void _finish() {
    _closed = true;      // zatrzymaj pompę pace
    _outSub?.cancel();   // stop pompowania wychodzących; NIE zamykamy _outgoing — dartssh2 przy teardown
    _outSub = null;      // bywa dopina jeszcze pakiet, a add-after-close = crash. Reszta idzie w próżnię.
    _outBuf.clear();
    if (!_incoming.isClosed) _incoming.close();
    if (!_done.isCompleted) _done.complete();
  }
}
