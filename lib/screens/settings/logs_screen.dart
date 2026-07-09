import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme.dart';
import '../../log.dart';
import '../../l10n.dart';

/// Podgląd wewnętrznych logów aplikacji (błędy sieci/nodów itd.).
class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  Color _color(String level) => switch (level) {
        'E' => AppTheme.red,
        'W' => Colors.amber,
        _   => AppTheme.muted,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Logi')),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: tr('Kopiuj'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: Log.dump()));
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('Skopiowano logi'))));
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: tr('Wyczyść'),
            onPressed: Log.clear,
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: Log.notifier,
        builder: (context, _, __) {
          final items = Log.entries;
          if (items.isEmpty) {
            return Center(
                child: Text(tr('Brak logów'),
                    style: const TextStyle(color: AppTheme.muted)));
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) =>
                const Divider(color: AppTheme.border, height: 1),
            itemBuilder: (context, i) {
              final e = items[i];
              final c = _color(e.level);
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${e.time} ',
                        style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 11,
                            fontFamily: 'monospace')),
                    Container(
                      margin: const EdgeInsets.only(right: 8, top: 1),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                          color: c.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(e.level,
                          style: TextStyle(
                              color: c,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.tag,
                              style: const TextStyle(
                                  color: AppTheme.text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          Text(e.msg,
                              style: const TextStyle(
                                  color: AppTheme.muted,
                                  fontSize: 12,
                                  fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
