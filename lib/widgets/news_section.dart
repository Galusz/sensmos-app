import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../theme.dart';
import '../l10n.dart';

/// Aktualności — kafle z panelu admina (BE: /v1/news, edycja w /monitor/ → 📰 News).
///
/// Każde pole jest opcjonalne i renderujemy TYLKO to, co przyszło, w stałej kolejności
/// tytuł → opis → zdjęcie. Sam tytuł = pogrubiona linia, sam opis = akapit, samo zdjęcie
/// = obrazek. Pusty wpis nie powstanie (pilnuje tego CHECK w bazie).
///
/// Nic nie zajmuje miejsca, dopóki nie ma treści: przy błędzie sieci, pustej liście albo
/// w trakcie ładowania widget zwraca zerowy rozmiar. Aktualności nie są na tyle ważne,
/// żeby pokazywać spinner nad listą nodów.
/// [owner] — adres portfela; serwer wybiera po nim wpisy celowane (kraj / wersja FW /
/// konkretne portfele). Bez adresu przychodzą wyłącznie wpisy nietargetowane.
class NewsSection extends StatefulWidget {
  final String? owner;
  const NewsSection({super.key, this.owner});

  @override
  State<NewsSection> createState() => _NewsSectionState();
}

class _NewsSectionState extends State<NewsSection> {
  // Cache per portfel: widget siedzi w IndexedStack i bywa przebudowywany, a aktualności
  // zmieniają się raz na tygodnie. Kluczem MUSI być adres — po zmianie portfela ten sam
  // cache pokazywałby wpisy celowane w poprzedniego właściciela.
  static final Map<String, List<_NewsItem>> _cache = {};
  String get _key => widget.owner?.toLowerCase() ?? '';
  List<_NewsItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _items = _cache[_key] ?? const [];
    if (!_cache.containsKey(_key)) _load();
  }

  @override
  void didUpdateWidget(NewsSection old) {
    super.didUpdateWidget(old);
    // Portfel pojawia się już po pierwszym renderze (wczytanie z magazynu), więc bez tego
    // wpisy celowane nie doszłyby aż do restartu apki.
    if (old.owner != widget.owner) {
      _items = _cache[_key] ?? const [];
      if (!_cache.containsKey(_key)) {
        _load();
      } else {
        setState(() {});
      }
    }
  }

  Future<void> _load() async {
    final key = _key;
    try {
      final uri = Uri.parse('${Config.beUrl}/v1/news')
          .replace(queryParameters: key.isEmpty ? null : {'owner': key});
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return;
      final list = (jsonDecode(res.body) as Map<String, dynamic>)['news'] as List? ?? [];
      final parsed = list.map((e) => _NewsItem.fromJson(e as Map<String, dynamic>)).toList();
      _cache[key] = parsed;
      if (mounted && key == _key) setState(() => _items = parsed);
    } catch (_) {/* cisza — brak aktualności nie jest błędem, o którym warto meldować */}
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final it in _items) _tile(it),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _tile(_NewsItem it) {
    final title = it.pick(it.title);
    final body = it.pick(it.body);
    final hasImage = it.imageUrl != null;
    // Kolejność: data → tytuł → opis → zdjęcie. Odstęp dokładamy TYLKO między obecnymi
    // elementami — inaczej kafel z samym tytułem miałby pod spodem pustą przestrzeń
    // po nieistniejącym opisie.
    final children = <Widget>[];
    if (it.publishedAt != null) {
      children.add(Text(_fmtDate(it.publishedAt!),
          style: const TextStyle(color: AppTheme.muted, fontSize: 11)));
    }
    if (title != null) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 6));
      children.add(Text(title,
          style: const TextStyle(
              color: AppTheme.text, fontSize: 14.5, fontWeight: FontWeight.w700)));
    }
    if (body != null) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 6));
      children.add(Text(body,
          style: const TextStyle(color: AppTheme.muted, fontSize: 13, height: 1.35)));
    }
    if (hasImage) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 10));
      children.add(ClipRRect(
        borderRadius: BorderRadius.circular(8),
        // fitWidth + szerokość wymuszona: zdjęcie ZAWSZE wypełnia kafel na całą szerokość,
        // niezależnie od tego, czy oryginał jest większy czy mniejszy. Bez `width` małe
        // zdjęcie zostawałoby w swoim rozmiarze i wisiało przy lewej krawędzi.
        // maxHeight tnie skrajnie wysokie kadry (pionowy screenshot potrafiłby zająć
        // pół ekranu) — ClipRRect przycina nadmiar zamiast go skalować.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: Image.network(
            '${Config.beUrl}${it.imageUrl}',
            width: double.infinity,
            fit: BoxFit.fitWidth,
            // Zdjęcia nie ma jak zwalidować przed pobraniem — gdy padnie, kafel ma zostać
            // z samym tekstem, a nie pokazać ikonę zepsutego obrazka.
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            loadingBuilder: (ctx, child, progress) =>
                progress == null ? child : const SizedBox(height: 2),
          ),
        ),
      ));
    }
    if (it.linkUrl != null) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 10));
      children.add(InkWell(
        onTap: () => launchUrl(Uri.parse(it.linkUrl!), mode: LaunchMode.externalApplication),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(it.linkText(),
                  style: const TextStyle(
                      color: AppTheme.teal, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.open_in_new, size: 14, color: AppTheme.teal),
          ]),
        ),
      ));
    }

    return Card(
      color: AppTheme.card,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year}';
  }
}

class _NewsItem {
  final Map<String, String> title;
  final Map<String, String> body;
  final Map<String, String> linkLabel;
  final String? imageUrl;
  final String? linkUrl;
  final DateTime? publishedAt;

  _NewsItem({required this.title, required this.body, required this.linkLabel,
             this.imageUrl, this.linkUrl, this.publishedAt});

  factory _NewsItem.fromJson(Map<String, dynamic> j) => _NewsItem(
        title: _map(j['title']),
        body: _map(j['body']),
        linkLabel: _map(j['link_label']),
        imageUrl: j['image_url'] as String?,
        linkUrl: j['link_url'] as String?,
        publishedAt: DateTime.tryParse(j['published_at']?.toString() ?? ''),
      );

  /// Podpis linku, a gdy go nie ma — sama domena. User ma widzieć, DOKĄD go wyślemy,
  /// zanim kliknie; „Zobacz więcej" bez wskazania celu to zła praktyka.
  String linkText() {
    final l = pick(linkLabel);
    if (l != null) return l;
    return Uri.tryParse(linkUrl ?? '')?.host ?? (linkUrl ?? '');
  }

  static Map<String, String> _map(dynamic v) {
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val.toString()));
    }
    return const {};
  }

  /// Język usera → EN → cokolwiek jest. Ta sama kolejność co w tr(): wpis dopisany tylko
  /// po angielsku ma się pokazać wszystkim, a nie zniknąć Niemcowi czy Brazylijczykowi.
  String? pick(Map<String, String> m) {
    if (m.isEmpty) return null;
    return m[L10n.lang] ?? m['en'] ?? m.values.first;
  }
}
