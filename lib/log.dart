import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lekki logger w aplikacji: bufor pierścieniowy trzymany w pamięci i zapisywany
/// (z opóźnieniem) do SharedPreferences, żeby przetrwał restart. Podgląd w
/// Ustawienia → Logi. UI słucha [notifier], żeby odświeżać się na żywo.
class LogEntry {
  final DateTime t;
  final String level;   // 'E' | 'W' | 'I'
  final String tag;
  final String msg;
  LogEntry(this.level, this.tag, this.msg) : t = DateTime.now();
  LogEntry._(this.t, this.level, this.tag, this.msg);

  Map<String, dynamic> toJson() =>
      {'t': t.millisecondsSinceEpoch, 'l': level, 'g': tag, 'm': msg};
  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry._(
        DateTime.fromMillisecondsSinceEpoch(j['t'] ?? 0),
        j['l'] ?? 'I', j['g'] ?? '', j['m'] ?? '');

  String get time {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
  }

  String get line => '$time [$level] $tag: $msg';
}

class Log {
  static const _max = 300;
  static const _key = 'app_logs';
  static final List<LogEntry> _buf = [];
  static final ValueNotifier<int> notifier = ValueNotifier(0);
  static Timer? _saveTimer;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null || raw.isEmpty) return;
      _buf
        ..clear()
        ..addAll((jsonDecode(raw) as List)
            .map((j) => LogEntry.fromJson(j as Map<String, dynamic>)));
    } catch (_) {}
  }

  static void e(String tag, String msg) => _add('E', tag, msg);
  static void w(String tag, String msg) => _add('W', tag, msg);
  static void i(String tag, String msg) => _add('I', tag, msg);

  static void _add(String level, String tag, String msg) {
    _buf.add(LogEntry(level, tag, msg));
    if (_buf.length > _max) _buf.removeRange(0, _buf.length - _max);
    notifier.value++;
    _persistSoon();
    if (kDebugMode) debugPrint('[$level] $tag: $msg');
  }

  /// Najnowsze na górze.
  static List<LogEntry> get entries => _buf.reversed.toList(growable: false);

  static String dump() => _buf.map((e) => e.line).join('\n');

  static Future<void> clear() async {
    _buf.clear();
    notifier.value++;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key);
    } catch (_) {}
  }

  // Zapis odroczony (koalescencja) — nie pisze do dysku przy każdej linii.
  static void _persistSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () async {
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString(_key,
            jsonEncode(_buf.map((e) => e.toJson()).toList()));
      } catch (_) {}
    });
  }
}
