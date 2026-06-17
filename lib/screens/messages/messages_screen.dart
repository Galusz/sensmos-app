import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme.dart';
import '../../l10n.dart';

class MessagesScreen extends StatefulWidget {
  final String ip;
  final String pin;

  const MessagesScreen({super.key, required this.ip, required this.pin});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _messages = [];
  int _total = 0;
  int _max = 6;

  Map<String, String> get _h => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.pin}',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http
          .get(Uri.parse('http://${widget.ip}/message/inbox'), headers: _h)
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(j['messages'] ?? []);
        _total = j['inbox_count'] as int? ?? _messages.length;
        _max = j['inbox_max'] as int? ?? 6;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Błąd: %s', [e])),
          backgroundColor: AppTheme.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ackAll() async {
    try {
      await http
          .post(
            Uri.parse('http://${widget.ip}/message/ack'),
            headers: _h,
            body: jsonEncode({}),
          )
          .timeout(const Duration(seconds: 5));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Błąd: %s', [e])),
          backgroundColor: AppTheme.red,
        ));
      }
    }
  }

  int get _unread => _messages.where((m) => m['read'] == false).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(tr('Odebrane')),
            if (_unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: AppTheme.teal,
                    borderRadius: BorderRadius.circular(10)),
                child: Text('$_unread',
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.teal))
          : Column(
              children: [
                _statusBar(),
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Text(
                            tr('Brak wiadomości w skrzynce.'),
                            style: const TextStyle(
                                color: AppTheme.muted, fontSize: 13),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) =>
                              _MessageCard(msg: _messages[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _statusBar() => Container(
        color: AppTheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.inbox, size: 14, color: AppTheme.muted),
            const SizedBox(width: 6),
            Text('$_total/$_max',
                style: const TextStyle(
                    color: AppTheme.muted, fontSize: 12)),
            if (_unread > 0) ...[
              const SizedBox(width: 6),
              Text(tr('· %s nieprzeczytanych', [_unread]),
                  style: const TextStyle(
                      color: AppTheme.teal, fontSize: 12)),
            ],
            const Spacer(),
            if (_messages.isNotEmpty)
              GestureDetector(
                onTap: _ackAll,
                child: Text(tr('Wyczyść'),
                    style: const TextStyle(color: AppTheme.red, fontSize: 12)),
              ),
          ],
        ),
      );
}

// ── Karta wiadomości ───────────────────────────────────────────

class _MessageCard extends StatelessWidget {
  final Map<String, dynamic> msg;
  const _MessageCard({required this.msg});

  @override
  Widget build(BuildContext context) {
    final from = msg['from'] as String? ?? '?';
    final mid = msg['message_id'] as String? ?? '?';
    final payload = msg['payload'] as String? ?? '';
    final isRead = msg['read'] as bool? ?? true;
    final fromShort =
        from.length > 8 ? '${from.substring(0, 8)}…' : from;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: AppTheme.teal
                      .withValues(alpha: isRead ? 0.06 : 0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.mail_outline,
                  color: isRead ? AppTheme.muted : AppTheme.teal,
                  size: 18),
            ),
            if (!isRead)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                      color: AppTheme.teal,
                      shape: BoxShape.circle),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                mid,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: isRead ? AppTheme.muted : AppTheme.text,
                    fontSize: 13,
                    fontWeight: isRead
                        ? FontWeight.normal
                        : FontWeight.w600),
              ),
            ),
            Text(tr('od: %s', [fromShort]),
                style: const TextStyle(
                    color: AppTheme.muted, fontSize: 12)),
          ],
        ),
        subtitle: payload.isNotEmpty
            ? Text(
                payload.length > 120
                    ? '${payload.substring(0, 120)}…'
                    : payload,
                style: const TextStyle(
                    color: AppTheme.muted, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        onTap: () => _showPayload(context, mid, from, payload),
      ),
    );
  }

  void _showPayload(
      BuildContext context, String mid, String from, String payload) {
    String formatted = payload;
    try {
      final j = jsonDecode(payload);
      formatted = const JsonEncoder.withIndent('  ').convert(j);
    } catch (_) {}

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(mid,
            style: const TextStyle(
                color: AppTheme.text,
                fontSize: 14,
                fontFamily: 'monospace')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('od: %s', [from]),
                  style: const TextStyle(
                      color: AppTheme.muted, fontSize: 12)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(6)),
                child: SelectableText(
                  formatted.isEmpty ? tr('(brak payloadu)') : formatted,
                  style: const TextStyle(
                      color: AppTheme.teal,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Zamknij'))),
        ],
      ),
    );
  }
}
