import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import '../../theme.dart';
import '../../config.dart';
import '../../core/core_bloc.dart';
import '../../services/wallet_service.dart';
import '../../l10n.dart';

/// Panel Emergency (model v2): podgląd noda w trybie LoRa + komenda awaryjna.
/// Dane z BE: GET /v1/nodes/:id/emergency (ostatnie wartości E1, kto usłyszał, statusy
/// komend). Komenda ≤8 znaków, podpisana portfelem ownera (sensmos:loracmd:...) — BE
/// koduje ją seedem noda i zleca nadanie najbliższemu przekaźnikowi. Wszystko best-effort:
/// cadencja beaconu ~4 min, więc odświeżamy co 30 s i pokazujemy wiek danych, nie „live".
class EmergencyScreen extends StatefulWidget {
  final String deviceId;   // pełne 64-hex
  final String name;       // nazwa/alias do nagłówka
  const EmergencyScreen({super.key, required this.deviceId, required this.name});
  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  Map<String, dynamic>? _data;
  String? _err;
  bool _sending = false;
  Timer? _timer;
  final _cmdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cmdCtrl.dispose();
    super.dispose();
  }

  String? get _owner => context.read<CoreBloc>().state.wallet?.address;

  Future<void> _fetch() async {
    final owner = _owner;
    if (owner == null) return;
    try {
      final res = await http.get(
        Uri.parse('${Config.beUrl}/v1/nodes/${widget.deviceId}/emergency?owner=$owner'),
        headers: {'X-App-Key': 'sensmos2025'},
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        throw Exception((jsonDecode(res.body) as Map)['error'] ?? 'HTTP ${res.statusCode}');
      }
      if (!mounted) return;
      setState(() { _data = jsonDecode(res.body) as Map<String, dynamic>; _err = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = e.toString());
    }
  }

  String _ago(int secs) {
    if (secs < 60) return '${secs}s';
    if (secs < 3600) return '${(secs / 60).floor()}m';
    if (secs < 86400) return '${(secs / 3600).floor()}h';
    return '${(secs / 86400).floor()}d';
  }

  // Hasło do portfela (gdy pod hasłem i zablokowany) — inline, jak w portfelu.
  Future<String?> _askPassword() => showDialog<String>(
    context: context,
    builder: (ctx) {
      final ctrl = TextEditingController();
      return AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Odblokuj portfel'), style: const TextStyle(color: AppTheme.text, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          style: const TextStyle(color: AppTheme.text),
          decoration: InputDecoration(hintText: tr('Podaj hasło, aby odblokować portfel.')),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Anuluj'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(tr('Odblokuj'))),
        ],
      );
    },
  );

  Future<void> _send() async {
    if (_sending) return;                       // double-tap: drugi klik odpada od ręki
    final cmd = _cmdCtrl.text.trim();
    if (cmd.isEmpty || cmd.length > 8 || !RegExp(r'^[\x21-\x7e]+$').hasMatch(cmd)) {
      _snack(tr('Wpisz komendę: 1-8 znaków ASCII, bez spacji'));
      return;
    }
    // Pole czyści się OD RAZU (nie po odpowiedzi): ponowna TA SAMA komenda wymaga
    // świadomego wpisania od nowa — koniec przypadkowych dubli z dwóch tapnięć.
    _cmdCtrl.clear();
    setState(() => _sending = true);
    final owner = _owner;
    if (owner == null) { setState(() => _sending = false); return; }
    final wallet = context.read<WalletService>();

    // Aktuacja = podpis portfela. Portfel pod hasłem i zablokowany → najpierw hasło.
    if (!await wallet.isUnlocked()) {
      final pw = await _askPassword();
      if (pw == null || pw.isEmpty) { if (mounted) setState(() => _sending = false); return; }
      try { await wallet.unlock(pw); }
      catch (_) { _snack(tr('Złe hasło')); if (mounted) setState(() => _sending = false); return; }
    }

    try {
      final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
      final sig = await wallet.signMessage('sensmos:loracmd:${widget.deviceId}:$cmd:$ts');
      final res = await http.post(
        Uri.parse('${Config.beUrl}/v1/nodes/${widget.deviceId}/lora_cmd'),
        headers: {'Content-Type': 'application/json', 'X-App-Key': 'sensmos2025'},
        body: jsonEncode({'owner': owner, 'cmd': cmd, 'ts': ts, 'sig': sig}),
      ).timeout(const Duration(seconds: 10));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && j['queued'] == true) {
        _cmdCtrl.clear();
        _snack(tr('Komenda w kolejce — poleci przez najbliższy przekaźnik'));
        _fetch();
      } else if (res.statusCode == 429) {
        final waitMin = (((j['retry_after_s'] ?? 0) as num) / 60).ceil();
        _snack(tr('Limit komend wyczerpany — spróbuj za ~%s min', ['$waitMin']));
        _fetch();
      } else {
        _snack('${j['error'] ?? 'HTTP ${res.statusCode}'}');
      }
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _stateChip(String state) {
    final (label, color) = switch (state) {
      'acked'  => (tr('ODEBRANA przez node'), Colors.green),
      'sent'   => (tr('wysłana'), Colors.amber),
      'failed' => (tr('nieudana'), Colors.red),
      _        => (tr('w kolejce'), AppTheme.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final vals = (d?['vals'] as Map?) ?? const {};
    final eids = (d?['eids'] as List?) ?? const [];
    final cmds = (d?['cmds'] as List?) ?? const [];
    final emergAgo = d?['emerg_ago_s'] as int?;
    final pingAgo = d?['ping_ago_s'] as int?;
    final heardBy = (d?['heard_by'] ?? '').toString();
    // JEDNO źródło prawdy o łączności: żywa mapa WS z BE (to samo, na co patrzy banner
    // na karcie noda). Wcześniej próg wieku pingu dawał ~minuty rozjazdu między ekranami.
    final wsOnline = d?['ws_online'] == true;
    final loraMode = !wsOnline && d != null;
    // Limit komend (BE egzekwuje; tu tylko licznik) — airtime LoRa jest wspólny, nie czat.
    final lim = d?['cmd_limit'] as Map?;
    final limUsed = (lim?['used'] as num?)?.toInt() ?? 0;
    final limMax = (lim?['max'] as num?)?.toInt() ?? 4;
    final limFull = limUsed >= limMax;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        title: Row(children: [
          Icon(Icons.cell_tower, color: Colors.amber.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('${tr('Panel Emergency')} · ${widget.name}',
              style: const TextStyle(fontSize: 16), overflow: TextOverflow.ellipsis)),
        ]),
      ),
      body: GestureDetector(
        // Tap poza polem = schowaj klawiaturę/focus (standardowy unfocus).
        onTap: () => FocusScope.of(context).unfocus(),
        child: RefreshIndicator(
        onRefresh: _fetch,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Status ──
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  loraMode
                      ? tr('Node bez internetu — nadaje przez LoRa')
                      : tr('Node ma łączność z serwerem (WS)'),
                  style: TextStyle(
                      color: loraMode ? Colors.amber.shade700 : Colors.green, fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                // Świeżość ramki: emergency nadaje co ~4 min; dużo starsza ramka przy braku
                // WS = jeszcze się uzbraja (2 min) albo nikt go nie słyszy.
                if (emergAgo != null)
                  Text(tr('Ostatnia ramka %s temu · usłyszał %s', [_ago(emergAgo), heardBy]),
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                if (loraMode && (emergAgo == null || emergAgo > 600))
                  Text(tr('Tryb LoRa uzbraja się ~2 min po padzie; ramka leci co ~4 min'),
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                if (emergAgo == null && !loraMode)
                  Text(tr('Brak ramek emergency — czekam na pierwszy beacon'),
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                if (pingAgo != null)
                  Text(tr('Ostatni kontakt WS: %s temu', [_ago(pingAgo)]),
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                if (_err != null)
                  Text(_err!, style: const TextStyle(color: Colors.red, fontSize: 11)),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Encje awaryjne ──
            Text(tr('Encje awaryjne'),
                style: const TextStyle(color: AppTheme.text, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (eids.isEmpty)
              Text(tr('Nie wybrano encji awaryjnych (Ustawienia noda → LoRa awaryjne)'),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            ...eids.map((eid) {
              final v = vals[eid];
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(children: [
                  Expanded(child: Text(eid.toString().replaceFirst(RegExp(r'^(pub|own)\.'), ''),
                      style: const TextStyle(color: AppTheme.text, fontSize: 13))),
                  Text(v?.toString() ?? '—',
                      style: TextStyle(
                          color: v != null ? Colors.amber.shade700 : AppTheme.muted,
                          fontSize: 15, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                  if (v != null && emergAgo != null) ...[
                    const SizedBox(width: 8),
                    Text(tr('odebrano %s temu', [_ago(emergAgo)]),
                        style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
                  ],
                ]),
              );
            }),
            const SizedBox(height: 16),

            // ── Komenda ──
            Text(tr('Komenda do noda'),
                style: const TextStyle(color: AppTheme.text, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(tr('Max 8 znaków. Node przekaże ją do inboxu, MQTT/HA i webhooka (jeśli ustawiony).'),
                style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _cmdCtrl,
                  // Wyłączone (nie tylko szary guzik): przy limicie/online focus zostawał
                  // uwięziony w polu po odświeżeniu stanu — disabled zdejmuje go sam.
                  enabled: loraMode && !limFull,
                  maxLength: 8,
                  style: const TextStyle(color: AppTheme.text, fontFamily: 'monospace'),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\x21-\x7e]'))],
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'water_of',
                    hintStyle: const TextStyle(color: AppTheme.muted),
                    filled: true,
                    fillColor: AppTheme.card,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppTheme.border)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Aktywny tylko w trybie LoRa: przy żywym WS komenda radiowa nie ma sensu
              // (normalne kanały działają), a skaner i tak nie campuje wtedy na domowym.
              FilledButton.icon(
                onPressed: (_sending || !loraMode || limFull) ? null : _send,
                style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade700),
                icon: _sending
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send, size: 16),
                label: Text(tr('Wyślij przez LoRa')),
              ),
            ]),
            const SizedBox(height: 4),
            Text(tr('Komendy w tej godzinie: %s/%s — airtime LoRa jest wspólny', ['$limUsed', '$limMax']),
                style: TextStyle(
                    color: limFull ? Colors.amber.shade700 : AppTheme.muted, fontSize: 11)),
            if (!loraMode)
              Text(tr('Komenda LoRa jest dostępna, gdy node straci łączność z serwerem'),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
            const SizedBox(height: 16),

            // ── Historia komend ──
            if (cmds.isNotEmpty) ...[
              Text(tr('Historia komend'),
                  style: const TextStyle(color: AppTheme.text, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...cmds.map((c) {
                final m = c as Map;
                final created = DateTime.tryParse((m['created_at'] ?? '').toString());
                final ago = created != null
                    ? _ago(DateTime.now().difference(created).inSeconds) : '?';
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(children: [
                    Text(m['cmd'].toString(),
                        style: const TextStyle(color: AppTheme.text, fontFamily: 'monospace',
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 10),
                    _stateChip(m['state'].toString()),
                    const Spacer(),
                    Text(tr('%s temu', [ago]),
                        style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                  ]),
                );
              }),
            ],
          ],
        ),
      ),
      ),
    );
  }
}
