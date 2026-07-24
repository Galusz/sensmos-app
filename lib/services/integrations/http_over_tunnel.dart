import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';

/// Odpowiedź HTTP z tunelu.
class HttpResp {
  final int status;
  final Map<String, String> headers;
  final Uint8List body;
  HttpResp(this.status, this.headers, this.body);
  String get text => utf8.decode(body, allowMalformed: true);
  dynamic get json => jsonDecode(text);
}

/// Minimalny klient HTTP/1.1 na bajtowym streamie tunelu (SSHSocket z TerminalRelay).
/// Node to głupia rura — my mówimy HTTP end-to-end. Request/response, keep-alive (jeden socket),
/// requesty serializowane (jeden naraz). Obsługa Content-Length i Transfer-Encoding: chunked.
class HttpOverTunnel {
  final SSHSocket _sock;
  final String host; // wartość nagłówka Host (np. "192.168.1.10:8123")
  final List<int> _buffer = [];
  final List<void Function()> _waiters = [];
  StreamSubscription? _sub;
  bool _closed = false;
  Future<void> _lock = Future.value();

  HttpOverTunnel(this._sock, this.host) {
    _sub = _sock.stream.listen(
      (chunk) { _buffer.addAll(chunk); _wake(); },
      onDone: () { _closed = true; _wake(); },
      onError: (_) { _closed = true; _wake(); },
    );
  }

  void _wake() {
    final w = List.of(_waiters);
    _waiters.clear();
    for (final f in w) f();
  }

  Future<void> _waitData() {
    final c = Completer<void>();
    _waiters.add(c.complete);
    return c.future;
  }

  int _find(List<int> pat) {
    for (int i = 0; i + pat.length <= _buffer.length; i++) {
      var ok = true;
      for (int j = 0; j < pat.length; j++) {
        if (_buffer[i + j] != pat[j]) { ok = false; break; }
      }
      if (ok) return i;
    }
    return -1;
  }

  Future<Uint8List> _readN(int n) async {
    while (_buffer.length < n) {
      if (_closed) throw Exception('tunel zamknięty w trakcie odczytu');
      await _waitData();
    }
    final out = Uint8List.fromList(_buffer.sublist(0, n));
    _buffer.removeRange(0, n);
    return out;
  }

  Future<String> _readLine() async {
    const crlf = [13, 10];
    while (true) {
      final i = _find(crlf);
      if (i >= 0) {
        final line = utf8.decode(_buffer.sublist(0, i), allowMalformed: true);
        _buffer.removeRange(0, i + 2);
        return line;
      }
      if (_closed) throw Exception('tunel zamknięty (linia)');
      await _waitData();
    }
  }

  /// Wykonaj request. Serializowany — kolejne czekają w kolejce na tym samym sockecie.
  Future<HttpResp> request(String method, String path,
      {Map<String, String>? headers, String? body}) {
    final done = Completer<HttpResp>();
    _lock = _lock.then((_) async {
      try {
        done.complete(await _doRequest(method, path, headers, body));
      } catch (e) {
        if (!done.isCompleted) done.completeError(e);
      }
    });
    return done.future;
  }

  Future<HttpResp> _doRequest(
      String method, String path, Map<String, String>? headers, String? body) async {
    if (_closed) throw Exception('tunel zamknięty');
    final bodyBytes = body != null ? utf8.encode(body) : const <int>[];
    final h = <String, String>{
      'Host': host,
      'Connection': 'keep-alive',
      'Accept': 'application/json',
      if (headers != null) ...headers,
    };
    if (bodyBytes.isNotEmpty) h['Content-Length'] = bodyBytes.length.toString();

    final sb = StringBuffer()..write('$method $path HTTP/1.1\r\n');
    h.forEach((k, v) => sb.write('$k: $v\r\n'));
    sb.write('\r\n');
    _sock.sink.add(utf8.encode(sb.toString()));
    if (bodyBytes.isNotEmpty) _sock.sink.add(bodyBytes);

    // status line: "HTTP/1.1 200 OK"
    final statusLine = await _readLine();
    final sp = statusLine.split(' ');
    final status = sp.length > 1 ? (int.tryParse(sp[1]) ?? 0) : 0;

    // nagłówki
    final respHeaders = <String, String>{};
    while (true) {
      final line = await _readLine();
      if (line.isEmpty) break;
      final ci = line.indexOf(':');
      if (ci > 0) {
        respHeaders[line.substring(0, ci).trim().toLowerCase()] = line.substring(ci + 1).trim();
      }
    }

    // body
    Uint8List bodyOut;
    final te = respHeaders['transfer-encoding'];
    if (te != null && te.toLowerCase().contains('chunked')) {
      final acc = BytesBuilder();
      while (true) {
        final sizeLine = await _readLine();
        final size = int.tryParse(sizeLine.split(';').first.trim(), radix: 16) ?? 0;
        if (size == 0) { await _readLine(); break; } // trailer CRLF
        acc.add(await _readN(size));
        await _readN(2); // CRLF po chunku
      }
      bodyOut = acc.toBytes();
    } else {
      final cl = int.tryParse(respHeaders['content-length'] ?? '');
      bodyOut = (cl != null && cl > 0) ? await _readN(cl) : Uint8List(0);
    }
    return HttpResp(status, respHeaders, bodyOut);
  }

  void close() {
    _closed = true;
    try { _sub?.cancel(); } catch (_) {}
    try { _sock.close(); } catch (_) {}
  }
}
