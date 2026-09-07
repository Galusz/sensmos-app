import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';

/// Klient Store dla kupującego: WS /v1/store, ślepa rura jak terminal (terminal_relay.dart).
/// Uwierzytelnienie podpisem portfela nad `sensmos:store:<ts>`; sterowanie JSON-em, dane ramką
/// binarną [sid u16][bajty]. Serwer nie zna klucza — dostaje i oddaje szyfrogram.
///
/// Wysyłka idzie przez `sink.addStream`, bo tylko tak gniazdo dart:io przenosi backpressure
/// z TCP na nasz strumień: plik większy niż RAM telefonu nie zbiera się w buforze.
class StoreRelay {
  final String owner;                                       // lower-case, tak porównuje BE
  final Future<String> Function(String message) signMessage;
  StoreRelay({required String owner, required this.signMessage}) : owner = owner.toLowerCase();

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  final _waiting = <String, Completer<Map<String, dynamic>>>{};   // typ odpowiedzi → oczekujący
  IOSink? _getSink; int _getSid = -1, _getBytes = 0;
  void Function(int)? _getProgress;
  Completer<Map<String, dynamic>>? _getDone;
  final _events = StreamController<String>.broadcast();
  Stream<String> get events => _events.stream;

  String get _wsUrl => '${Config.beUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://')}/v1/store';

  Future<void> connect() async {
    _ch = WebSocketChannel.connect(Uri.parse(_wsUrl));
    _sub = _ch!.stream.listen(_onMessage, onError: (e) => _fail('$e'), onDone: () => _fail('connection closed'));
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sig = await signMessage('sensmos:store:$ts');
    final r = await _ask('auth', {'type': 'auth', 'owner': owner, 'ts': ts, 'sig': sig});
    if (r['ok'] != true) throw Exception(r['error'] ?? 'auth denied');
  }

  Future<Map<String, dynamic>> package({int addGb = 0, String? recovery}) =>
      _ask('package', {'type': 'package', if (addGb > 0) 'add_gb': addGb, if (recovery != null) 'recovery': recovery});
  Future<Map<String, dynamic>> list() => _ask('list', {'type': 'list'});
  Future<Map<String, dynamic>> del(String id) => _ask('del', {'type': 'del', 'object_id': id});

  /// Wysyłka: `put` z metadanymi, potem ramki z pliku szyfrogramu, `put_end`, czekamy na `put_state`.
  Future<Map<String, dynamic>> put({required File cipher, required int size, required List<String> blocks,
      required String wrappedKey, required String nameEnc, void Function(int sent)? onProgress}) async {
    final r = await _ask('put', {'type': 'put', 'size': size, 'blocks': blocks, 'wrapped_key': wrappedKey, 'name_enc': nameEnc});
    if (r['ok'] != true) throw Exception(r['error'] ?? 'put refused');
    final sid = r['sid'] as int;
    var sent = 0;
    Stream<List<int>> frames() async* {
      await for (final part in cipher.openRead()) {
        for (var off = 0; off < part.length; off += 256 * 1024) {
          final n = part.length - off < 256 * 1024 ? part.length - off : 256 * 1024;
          final f = Uint8List(2 + n)..buffer.asByteData().setUint16(0, sid);
          f.setRange(2, 2 + n, part, off);
          sent += n; onProgress?.call(sent);
          yield f;
        }
      }
    }
    final state = _expect('put_state');
    await _ch!.sink.addStream(frames());
    _send({'type': 'put_end', 'sid': sid});
    final st = await state.timeout(const Duration(minutes: 10));
    if (st['st'] != 'ok') throw Exception(st['msg'] ?? 'put failed');
    return st;
  }

  /// Pobranie szyfrogramu do pliku `out`. Zwraca metadane (rozmiar, klucz zapakowany, nazwa).
  Future<Map<String, dynamic>> get(String id, File out, {void Function(int got)? onProgress}) async {
    final r = await _ask('get', {'type': 'get', 'object_id': id});
    if (r['ok'] != true) throw Exception(r['error'] ?? 'get refused');
    _getSid = r['sid'] as int; _getBytes = 0; _getProgress = onProgress;
    _getSink = out.openWrite();
    _getDone = Completer();
    final end = await _getDone!.future.timeout(const Duration(minutes: 10));
    await _getSink?.close(); _getSink = null; _getSid = -1;
    if (end['error'] != null) throw Exception(end['error']);
    return {...r, 'bytes': _getBytes};
  }

  // ── plumbing ──
  Future<Map<String, dynamic>> _ask(String type, Map<String, dynamic> m) { final f = _expect(type); _send(m); return f; }
  Future<Map<String, dynamic>> _expect(String type) {
    final c = Completer<Map<String, dynamic>>(); _waiting[type] = c;
    return c.future.timeout(const Duration(seconds: 60), onTimeout: () { _waiting.remove(type); throw TimeoutException(type); });
  }
  void _send(Map<String, dynamic> m) { try { _ch?.sink.add(jsonEncode(m)); } catch (_) {} }

  void _onMessage(dynamic raw) {
    if (raw is! String) {
      final b = raw as List<int>;
      if (b.length < 2) return;
      final sid = (b[0] << 8) | b[1];
      if (sid == _getSid && _getSink != null) {
        _getSink!.add(b.sublist(2)); _getBytes += b.length - 2; _getProgress?.call(_getBytes);
      }
      return;
    }
    Map<String, dynamic> m;
    try { m = jsonDecode(raw) as Map<String, dynamic>; } catch (_) { return; }
    final t = m['type'] as String? ?? '';
    if (t == 'get_end') { _getDone?.complete(m); _getDone = null; return; }
    final c = _waiting.remove(t);
    if (c != null && !c.isCompleted) c.complete(m);
  }

  void _fail(String msg) {
    if (!_events.isClosed) _events.add('down:$msg');
    for (final c in _waiting.values) { if (!c.isCompleted) c.completeError(Exception(msg)); }
    _waiting.clear();
    if (_getDone != null && !_getDone!.isCompleted) _getDone!.complete({'error': msg});
  }

  void dispose() {
    try { _sub?.cancel(); } catch (_) {}
    try { _ch?.sink.close(); } catch (_) {}
    try { _getSink?.close(); } catch (_) {}
    if (!_events.isClosed) _events.close();
  }
}
