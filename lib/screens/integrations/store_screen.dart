import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import '../../config.dart';
import '../../theme.dart';
import '../../l10n.dart';
import '../../core/core_bloc.dart';
import '../../services/wallet_service.dart';
import '../../services/store_crypto.dart';
import '../../services/store_relay.dart';
import 'store_recovery_screen.dart';

/// Store — pakiet miejsca u innych właścicieli nodów i panel plików.
/// Klucz główny powstaje z podpisu portfela przy wejściu na ekran i żyje tylko w tym ekranie.
class StoreScreen extends StatefulWidget {
  final String deviceId, label;
  const StoreScreen({super.key, required this.deviceId, required this.label});
  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  static const int maxDownloadMb = 256;   // pobranie na telefon idzie przez pamięć (SAF bez strumienia)

  StoreRelay? _relay;
  Uint8List? _kek, _recovery;
  Map<String, dynamic>? _pkg;          // {sellers, limit_b, used_b, daily, recovery}
  Map<String, dynamic>? _capacity;     // gdy nie ma pakietu: wolne miejsce w sieci
  List<Map<String, dynamic>> _items = const [];
  String? _error, _busy; double? _progress;

  @override
  void initState() { super.initState(); _init(); }
  @override
  void dispose() { _relay?.dispose(); super.dispose(); }

  Future<void> _init() async {
    try {
      final owner = context.read<CoreBloc>().state.wallet?.address;
      if (owner == null) throw Exception(tr('Portfel wymagany'));
      final wallet = context.read<WalletService>();
      // Klucz główny z podpisu stałego komunikatu — deterministyczny, nigdzie nie zapisywany.
      final sig = await wallet.signMessage('sensmos:store:v1');
      _kek = StoreCrypto.kekFromSignature(_hex(sig));
      _relay = StoreRelay(owner: owner, signMessage: wallet.signMessage);
      await _relay!.connect();
      await _loadPackage();
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
  }

  Uint8List _hex(String h) {
    final s = h.startsWith('0x') ? h.substring(2) : h;
    return Uint8List.fromList(List.generate(s.length ~/ 2, (i) => int.parse(s.substring(2 * i, 2 * i + 2), radix: 16)));
  }

  Future<void> _loadPackage() async {
    final r = await _relay!.package();
    if (r['ok'] != true) {
      // Bez pakietu: pokaż, ile miejsca ma sieć, i daj wykupić.
      try {
        final c = await http.get(Uri.parse('${Config.beUrl}/v1/store/capacity'));
        _capacity = jsonDecode(c.body) as Map<String, dynamic>;
      } catch (_) {}
      if (mounted) setState(() { _pkg = null; _error = r['error']?.toString(); });
      return;
    }
    _pkg = r;
    await _ensureRecovery();
    await _refresh();
  }

  /// Klucz odzyskiwania: 24 słowa pokazane raz; sam klucz leży przy pakiecie ZAPAKOWANY kluczem
  /// głównym, więc nowy telefon z tym samym portfelem pakuje kolejne pliki bez pytania o słowa.
  Future<void> _ensureRecovery() async {
    final wrapped = _pkg?['recovery'] as String?;
    if (wrapped != null && wrapped.isNotEmpty) {
      try { _recovery = StoreCrypto.open(_kek!, wrapped, aad: 'recovery'); } catch (_) { _recovery = null; }
      return;
    }
    final (key, words) = StoreCrypto.newRecovery();
    if (!mounted) return;
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => StoreRecoveryScreen(words: words)));
    if (ok != true) return;                       // bez potwierdzenia nie pakujemy — następne wejście pokaże nowe
    final r = await _relay!.package(recovery: StoreCrypto.seal(_kek!, key, aad: 'recovery'));
    if (r['ok'] == true) { _pkg = r; _recovery = key; }
  }

  Future<void> _refresh() async {
    final l = await _relay!.list();
    if (!mounted) return;
    setState(() {
      _items = ((l['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _pkg = {...?_pkg, 'used_b': l['used_b'], 'limit_b': l['limit_b'], 'daily': l['daily'], 'sellers': l['sellers']};
      _error = null;
    });
  }

  Future<void> _buy() => _run(tr('Wykupuję pakiet…'), () async {
    final r = await _relay!.package();
    if (r['ok'] != true) throw Exception(r['error']);
    _pkg = r; await _ensureRecovery(); await _refresh();
  });

  Future<void> _grow() => _run(tr('Dokupuję…'), () async {
    final r = await _relay!.package(addGb: 1);
    if (r['ok'] != true) throw Exception(r['error']);
    _pkg = r; await _refresh();
  });

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles();
    final f = picked?.files.single;
    if (f == null || f.path == null) return;
    if (f.size <= 0) { _snack(tr('Plik jest pusty')); return; }
    final path = f.path!;
    await _run(tr('Szyfrowanie…'), () async {
      final dek = StoreCrypto.randomBytes(32);
      // AES w czystym Darcie → osobny izolat, inaczej UI stoi (ANR na MIUI już przy zdjęciu).
      final (encPath, blocks) = await Isolate.run(() => StoreCrypto.encryptPathToTemp(path, dek));
      final enc = File(encPath);
      try {
        _setBusy(tr('Wysyłanie…'));
        final size = await enc.length();
        await _relay!.put(cipher: enc, size: size, blocks: blocks,
            wrappedKey: StoreCrypto.wrapDek(dek, _kek!, _recovery),
            nameEnc: StoreCrypto.encryptName(_kek!, f.name),
            onProgress: (s) => _setProgress(s / size));
      } finally { try { await enc.parent.delete(recursive: true); } catch (_) {} }
      await _refresh();
    });
  }

  Future<void> _download(Map<String, dynamic> it) async {
    final size = (it['size_b'] as num).toInt();
    if (size > maxDownloadMb * 1024 * 1024) { _snack(tr('Za duży plik do pobrania na telefon (limit %s MB)', [maxDownloadMb])); return; }
    final name = StoreCrypto.decryptName(_kek!, it['name_enc'] as String?);
    await _run(tr('Pobieranie…'), () async {
      final dir = await Directory.systemTemp.createTemp('sensmos-store-');
      final enc = File('${dir.path}/dl.bin');
      try {
        await _relay!.get(it['id'] as String, enc, onProgress: (g) => _setProgress(g / size));
        _setBusy(tr('Odszyfrowywanie…'));
        final dek = StoreCrypto.unwrapDek(it['wrapped_key'] as String, _kek!);
        final encPath = enc.path;
        final plain = await Isolate.run(() => StoreCrypto.decryptPath(encPath, dek));
        final path = await FilePicker.platform.saveFile(fileName: name.isEmpty ? 'file' : name, bytes: plain);
        if (path != null) _snack(tr('Pobrano: %s', [name]));
      } finally { try { await dir.delete(recursive: true); } catch (_) {} }
    });
  }

  Future<void> _delete(Map<String, dynamic> it) async {
    final name = StoreCrypto.decryptName(_kek!, it['name_enc'] as String?);
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.card,
      title: Text(tr('Usunąć %s?', [name]), style: const TextStyle(color: AppTheme.text)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Anuluj'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Usuń'))),
      ]));
    if (ok != true) return;
    await _run(null, () async { await _relay!.del(it['id'] as String); await _refresh(); });
  }

  // ── stan/UI ──
  Future<void> _run(String? label, Future<void> Function() body) async {
    setState(() { _busy = label; _progress = null; _error = null; });
    try { await body(); } catch (e) { if (mounted) setState(() => _error = '$e'); }
    if (mounted) setState(() { _busy = null; _progress = null; });
  }
  void _setBusy(String s) { if (mounted) setState(() { _busy = s; _progress = null; }); }
  void _setProgress(double p) { if (mounted) setState(() => _progress = p.clamp(0, 1)); }
  void _snack(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }
  String _gb(num b) => (b / 1073741824).toStringAsFixed(b >= 1073741824 ? 1 : 2);
  String _mb(num b) => b >= 1048576 ? '${(b / 1048576).toStringAsFixed(1)} MB' : '${(b / 1024).toStringAsFixed(0)} KB';

  @override
  Widget build(BuildContext context) {
    final ready = _relay != null && _kek != null;
    return Scaffold(
      appBar: AppBar(title: Text('${tr('Dysk')} · ${widget.label}')),
      floatingActionButton: (_pkg != null && _busy == null)
          ? FloatingActionButton.extended(onPressed: _upload, backgroundColor: AppTheme.teal,
              icon: const Icon(Icons.upload_file, color: Colors.black),
              label: Text(tr('Dodaj plik'), style: const TextStyle(color: Colors.black)))
          : null,
      body: !ready && _error == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (_pkg != null) _packageCard() else _capacityCard(),
              if (_busy != null) ...[
                const SizedBox(height: 12),
                Text(_busy!, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: _progress, color: AppTheme.teal, backgroundColor: AppTheme.surface),
              ],
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: const TextStyle(color: AppTheme.amber, fontSize: 12))),
              const SizedBox(height: 16),
              if (_pkg != null) ...[
                if (_items.isEmpty) Text(tr('Brak plików'), style: const TextStyle(color: AppTheme.muted)),
                for (final it in _items) _fileTile(it),
                const SizedBox(height: 72),
              ],
            ]),
    );
  }

  Widget _card(List<Widget> children) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children));

  Widget _packageCard() {
    final limit = (_pkg!['limit_b'] as num?) ?? 0, used = (_pkg!['used_b'] as num?) ?? 0;
    final daily = (_pkg!['daily'] as num?) ?? 0, sellers = (_pkg!['sellers'] as List?)?.length ?? 0;
    return _card([
      Text(tr('Pakiet %s GB · zajęte %s GB', [_gb(limit), _gb(used)]),
          style: const TextStyle(color: AppTheme.text, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      LinearProgressIndicator(value: limit > 0 ? (used / limit).clamp(0, 1).toDouble() : 0,
          color: AppTheme.teal, backgroundColor: AppTheme.surface),
      const SizedBox(height: 8),
      Text(tr('%s GALU na dobę · kopii: %s', [daily.toStringAsFixed(1), sellers]),
          style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
      const SizedBox(height: 10),
      OutlinedButton.icon(onPressed: _busy == null ? _grow : null,
          icon: const Icon(Icons.add, size: 16),
          label: Text(tr('Dokup 1 GB (+%s GALU/dobę)', [(0.1 * sellers).toStringAsFixed(1)])),
          style: OutlinedButton.styleFrom(foregroundColor: AppTheme.teal)),
    ]);
  }

  Widget _capacityCard() {
    final c = _capacity;
    final free = (c?['free_packages'] as num?)?.toInt() ?? 0;
    return _card([
      Text(tr('Miejsce w sieci'), style: const TextStyle(color: AppTheme.text, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      if (c != null) ...[
        Text(tr('Sprzedawców online: %s', [c['sellers_online']]), style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        Text(tr('Wolnych pakietów: %s', [free]), style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        if (c['test_mode'] == true)
          Text(tr('Tryb testowy'), style: const TextStyle(color: AppTheme.amber, fontSize: 12)),
      ],
      const SizedBox(height: 10),
      if (free > 0 || c?['test_mode'] == true)
        FilledButton(onPressed: _busy == null ? _buy : null,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.teal),
            child: Text(tr('Wykup pakiet %s GB (%s GALU/dobę)', [c?['package_gb'] ?? 10, c?['daily_galu'] ?? 2])))
      else
        Text(tr('Brak wolnego miejsca — wróć później'), style: const TextStyle(color: AppTheme.amber)),
    ]);
  }

  Widget _fileTile(Map<String, dynamic> it) {
    final name = StoreCrypto.decryptName(_kek!, it['name_enc'] as String?);
    final copies = (it['copies'] as num?)?.toInt() ?? 0;
    final created = DateTime.tryParse('${it['created_at']}')?.toLocal();
    return Card(
      color: AppTheme.card, margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.insert_drive_file_outlined, color: AppTheme.teal),
        title: Text(name.isEmpty ? (it['id'] as String).substring(0, 8) : name,
            style: const TextStyle(color: AppTheme.text), overflow: TextOverflow.ellipsis),
        subtitle: Text('${_mb(it['size_b'] as num)} · ${tr('kopii: %s', [copies])}'
            '${created != null ? ' · ${created.day}.${created.month.toString().padLeft(2, '0')}' : ''}',
            style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        trailing: const Icon(Icons.download, color: AppTheme.muted, size: 20),
        onTap: _busy == null ? () => _download(it) : null,
        onLongPress: _busy == null ? () => _delete(it) : null,
      ),
    );
  }
}
