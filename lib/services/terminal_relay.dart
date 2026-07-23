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

  Completer<void>? _auth;
  Completer<SSHSocket>? _open;

  TerminalRelay({required this.deviceId, required this.owner, required this.signMessage});

  String get _wsUrl => '${Config.beUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://')}/v1/term';

  /// Połącz i uwierzytelnij jako właściciel noda. Rzuca przy odmowie/timeout.
  Future<void> connect() async {
    _auth = Completer<void>();
    _ch = WebSocketChannel.connect(Uri.parse(_wsUrl));
    _ch!.stream.listen(_onMessage,
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

  void _send(Map<String, dynamic> m) => _ch?.sink.add(jsonEncode(m));

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
        _events.add('state:$st:${m['msg'] ?? ''}');
        if (st == 'open') {
          _sock = _RelaySocket(
            onSend: (data) => _send({'type': 'data', 'd': base64Encode(data)}),
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
    _events.add('error:$msg');
    if (_auth != null && !_auth!.isCompleted) _auth!.completeError(Exception(msg));
    if (_open != null && !_open!.isCompleted) _open!.completeError(Exception(msg));
  }

  void dispose() {
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

  _RelaySocket({required this.onSend, required this.onClose}) {
    _outgoing.stream.listen(onSend);
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
    if (!_incoming.isClosed) _incoming.close();
    if (!_outgoing.isClosed) _outgoing.close();
    if (!_done.isCompleted) _done.complete();
  }
}
