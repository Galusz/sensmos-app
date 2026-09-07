import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme.dart';
import '../../l10n.dart';

/// Kod odzyskiwania Store — 24 słowa pokazane RAZ, przy zakładaniu pakietu. Osobny ekran,
/// nie popup: 24 słowa w dialogu wychodzą poza obszar i nie da się ich spokojnie przepisać.
class StoreRecoveryScreen extends StatefulWidget {
  final String words;
  const StoreRecoveryScreen({super.key, required this.words});
  @override
  State<StoreRecoveryScreen> createState() => _StoreRecoveryScreenState();
}

class _StoreRecoveryScreenState extends State<StoreRecoveryScreen> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final words = widget.words.split(' ');
    return Scaffold(
      appBar: AppBar(title: Text(tr('Kod odzyskiwania'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr('Zapisz te 24 słowa na papierze. Bez portfela i bez nich pliki są nie do odzyskania. Serwer ich nie zna.'),
            style: const TextStyle(color: AppTheme.muted, height: 1.4)),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < words.length; i++)
              Container(
                width: 150,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  SizedBox(width: 26, child: Text('${i + 1}.', style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
                  Expanded(child: Text(words[i], style: const TextStyle(color: AppTheme.text, fontFamily: 'monospace'))),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () { Clipboard.setData(ClipboardData(text: widget.words)); },
          icon: const Icon(Icons.copy, size: 16), label: Text(tr('Kopiuj')),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _saved, onChanged: (v) => setState(() => _saved = v ?? false),
          title: Text(tr('Zapisałem te słowa'), style: const TextStyle(color: AppTheme.text)),
          activeColor: AppTheme.teal, controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _saved ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.teal),
          child: Text(tr('Dalej')),
        ),
      ]),
    );
  }
}
