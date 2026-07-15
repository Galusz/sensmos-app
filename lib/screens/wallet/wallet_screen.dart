import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import '../../theme.dart';
import '../../config.dart';
import '../../l10n.dart';
import '../../core/core_bloc.dart';
import '../../core/core_state.dart';
import '../../core/core_event.dart';
import '../../services/wallet_service.dart';
import '../../services/eth_service.dart';
import '../../services/node_service.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _loading = true;
  bool _busy = false;
  bool _keysOpen = false;
  String? _address;

  // saldo z BE (GALU, human)
  double _available = 0;
  double _pending = 0;
  double _earned = 0;
  double _deposited = 0;
  double _claimed = 0;
  double _claimPending = 0;   // hold claim-intent (wypłata w toku, czeka na event on-chain)
  double _depositPending = 0; // wpłata potwierdzona on-chain, czeka aż listener BE zaksięguje event Deposited

  // saldo on-chain (wei)
  BigInt _dhv = BigInt.zero;
  BigInt _matic = BigInt.zero;

  EthService get _eth => context.read<EthService>();

  @override
  void initState() {
    super.initState();
    _address = context.read<CoreBloc>().state.wallet?.address;
    _load();
  }

  Future<void> _load() async {
    final addr = _address;
    if (addr == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    await _loadBe(addr);
    await Future.wait([_loadChain(addr), _loadPending(addr)]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadBe(String addr) async {
    try {
      final res = await http
          .get(Uri.parse('${Config.beUrl}/v1/wallet/$addr'))
          .timeout(const Duration(seconds: 6));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      _available = _d(j['available']);
      _earned = _d(j['total_earned']);
      _deposited = _d(j['total_deposited']);
      _claimed = _d(j['claimed_galu']);
      _claimPending = _d(j['claim_pending']);
    } catch (_) {}
  }

  // v9: „Do odebrania" = cumulative (lifetime entitlement z /proof) − odebrane − w toku.
  Future<void> _loadPending(String addr) async {
    try {
      final res = await http
          .get(Uri.parse('${Config.beUrl}/v1/wallet/$addr/proof'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) {
        _pending = 0;
        return;
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final cumulative = _d(j['cumulative']);
      _pending =
          (cumulative - _claimed - _claimPending).clamp(0, double.infinity).toDouble();
    } catch (_) {
      _pending = 0;
    }
  }

  Future<void> _loadChain(String addr) async {
    try {
      final r = await Future.wait([
        _eth.tokenBalance(addr),
        _eth.maticBalance(addr),
      ]);
      _dhv = r[0];
      _matic = r[1];
    } catch (_) {}
  }

  double _d(dynamic v) =>
      v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.red : null,
    ));
  }

  // ── Deposit ─────────────────────────────────────────────────
  Future<void> _deposit() async {
    final pk = context.read<CoreBloc>().state.wallet?.privateKeyHex;
    final amount = await _amountDialog(tr('Wpłać GALU na nody'), _dhvHuman());
    if (amount == null || pk == null) return;
    final wei = _toWei(amount);
    if (wei <= BigInt.zero) return;
    if (wei > _dhv) {
      _snack(tr('Za mało GALU w portfelu'), error: true);
      return;
    }

    setState(() => _busy = true);
    final depBefore = _deposited;   // do wykrycia zaksięgowania wpłaty przez listener BE
    try {
      final allowance = await _eth.allowance(_address!);
      if (allowance < wei) {
        _snack(tr('Zatwierdzanie GALU (approve)…'));
        final ah = await _eth.approve(pk, wei);
        final aok = await _eth.waitReceipt(ah);
        if (!aok) {
          _snack(tr('Approve nie powiodło się'), error: true);
          return;
        }
      }
      _snack(tr('Wpłacanie…'));
      final h = await _eth.deposit(pk, wei);
      final ok = await _eth.waitReceipt(h);
      _snack(ok ? tr('Wpłacono %s GALU', [amount]) : tr('Deposit zrewertowany'),
          error: !ok);
      await _load();
      // Wpłata potwierdzona on-chain, ale saldo kredytuje dopiero listener BE z eventu Deposited
      // (~15-30 s). „Wpłata w toku" + odpytujemy BE aż total_deposited urośnie o tę kwotę.
      // NIC nie doliczamy sami — kwota zawsze z BE (blokada RPC nie doda GALU, napis by tylko wisiał).
      if (ok && mounted) {
        final amtNum = _d(amount);
        setState(() => _depositPending = amtNum);
        for (int i = 0; i < 8 && mounted; i++) {
          await Future.delayed(const Duration(seconds: 5));
          await _loadBe(_address!);
          if (_deposited >= depBefore + amtNum - 0.01) break;
          if (mounted) setState(() {});
        }
        if (mounted) setState(() => _depositPending = 0);
      }
    } catch (e) {
      _snack(tr('Błąd: %s', [e]), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Claim ───────────────────────────────────────────────────
  // Dwufazowy: podpisany claim-intent do BE (hold → available spada OD RAZU, proof w
  // odpowiedzi), potem tx na kontrakt. Finalizuje event on-chain; brak tx → BE zwalnia
  // hold do 2h. Fallback na stary GET /proof gdy intent niedostępny (stary BE/offline).
  Future<void> _claim() async {
    final addr = _address;
    final pk = context.read<CoreBloc>().state.wallet?.privateKeyHex;
    if (addr == null || pk == null) return;

    setState(() => _busy = true);
    try {
      http.Response res;
      bool viaIntent = false;
      try {
        final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final sig =
            _eth.signIntent(pk, 'sensmos-claim:${addr.toLowerCase()}:$ts');
        res = await http
            .post(Uri.parse(
                '${Config.beUrl}/v1/wallet/${addr.toLowerCase()}/claim-intent'),
                headers: const {'Content-Type': 'application/json'},
                body: jsonEncode({'ts': ts, 'sig': sig}))
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 401) throw Exception('intent rejected');
        if (res.statusCode == 200) viaIntent = true;
      } catch (_) {
        res = await http
            .get(Uri.parse('${Config.beUrl}/v1/wallet/$addr/proof'))
            .timeout(const Duration(seconds: 8));
      }
      if (res.statusCode != 200) {
        final msg = (jsonDecode(res.body) as Map)['error'] ?? tr('Brak nagród');
        _snack('$msg', error: true);
        return;
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final cumulativeWei = BigInt.parse(j['cumulativeWei'].toString());
      final proof = (j['proof'] as List).map((e) => e.toString()).toList();

      // claim-intent zdjął już z available na BE (hold) → pokaż OD RAZU (available spada,
      // „do odebrania"→0, „wypłata w toku"→kwota), nie czekając na potwierdzenie tx on-chain (~20-30 s).
      if (viaIntent) {
        await _loadBe(addr);
        await _loadPending(addr);
        if (mounted) setState(() {});
      }

      // Cumulative: jeśli już odebrano całość (claimedTotal >= cumulative) — nic do claim.
      final already = await _eth.claimedTotal(addr);
      if (already >= cumulativeWei) {
        _snack(tr('Wszystko już odebrane'));
        return;
      }

      _snack(tr('Odbieranie nagród…'));
      final h = await _eth.claim(pk, cumulativeWei, proof);
      final ok = await _eth.waitReceipt(h);
      _snack(ok ? tr('Odebrano nagrody') : tr('Claim zrewertowany'), error: !ok);
      await _load();
    } catch (e) {
      _snack(tr('Błąd: %s', [e]), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Eksport klucza (PIN noda) ───────────────────────────────
  Future<void> _exportKey() async {
    final nodes = context.read<NodeService>().nodes;
    if (nodes.isEmpty) {
      _snack(tr('Brak nodów — eksport wymaga PIN-u noda'), error: true);
      return;
    }

    final entered = await _pinDialog();
    if (entered == null) return;

    // Weryfikacja PIN-u przeciw DOWOLNEMU z nodów (pierwszy 200 = OK)
    bool ok = false;
    bool anyReachable = false;
    for (final n in nodes) {
      try {
        final res = await http.get(
          Uri.parse('http://${n.ip}/config'),
          headers: {'Authorization': 'Bearer $entered'},
        ).timeout(const Duration(seconds: 4));
        anyReachable = true;
        if (res.statusCode == 200) {
          ok = true;
          break;
        }
      } catch (_) {}
    }
    if (!anyReachable) {
      _snack(tr('Brak połączenia z żadnym nodem'), error: true);
      return;
    }
    if (!ok) {
      _snack(tr('Błędny PIN'), error: true);
      return;
    }
    if (!mounted) return;

    final pk = context.read<CoreBloc>().state.wallet?.privateKeyHex;
    if (pk == null) return;
    _showKeyDialog(pk);
  }

  // ── UI ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Portfel')),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _busy ? null : _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.teal))
          : BlocBuilder<CoreBloc, CoreState>(
              builder: (context, state) {
                return Stack(children: [
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _addressCard(state.wallet?.address ?? '—'),
                      const SizedBox(height: 16),
                      _balanceCard(),
                      const SizedBox(height: 16),
                      _actions(),
                      const SizedBox(height: 16),
                      _onchainCard(),
                      const SizedBox(height: 16),
                      _keysSection(),
                    ],
                  ),
                  if (_busy)
                    Container(
                      color: Colors.black54,
                      child: const Center(
                          child: CircularProgressIndicator(
                              color: AppTheme.teal)),
                    ),
                ]);
              },
            ),
    );
  }

  Widget _addressCard(String addr) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('ADRES PORTFELA'),
                  style: const TextStyle(
                      color: AppTheme.muted,
                      fontSize: 11,
                      letterSpacing: 0.8)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Text(addr,
                      style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 13,
                          fontFamily: 'monospace')),
                ),
                IconButton(
                  icon: const Icon(Icons.copy,
                      size: 18, color: AppTheme.muted),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: addr));
                    _snack(tr('Adres skopiowany'));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.qr_code,
                      size: 20, color: AppTheme.teal),
                  onPressed: () => _showReceive(addr),
                ),
              ]),
            ],
          ),
        ),
      );

  Widget _balanceCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('SALDO W SIECI (GALU)'),
                  style: const TextStyle(
                      color: AppTheme.muted,
                      fontSize: 11,
                      letterSpacing: 0.8)),
              const SizedBox(height: 12),
              _bigRow(tr('Do wydania na nody'), _available, AppTheme.teal),
              const Divider(color: AppTheme.border, height: 20),
              _smallRow(tr('Zarobione (nagrody)'), _earned),
              _smallRow(tr('Wpłacone (Twój kapitał)'), _deposited),
              if (_depositPending > 0) _smallRow(tr('Wpłata w toku'), _depositPending),
              const Divider(color: AppTheme.border, height: 20),
              _smallRow(tr('Do odebrania (claim)'), _pending),
              if (_claimPending > 0) _smallRow(tr('Wypłata w toku'), _claimPending),
              _smallRow(tr('Odebrano'), _claimed),
            ],
          ),
        ),
      );

  Widget _bigRow(String label, double v, Color c) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: AppTheme.text, fontSize: 14)),
          Text(v.toStringAsFixed(3),
              style: TextStyle(
                  color: c, fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      );

  Widget _smallRow(String label, double v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
            Text(v.toStringAsFixed(3),
                style: const TextStyle(color: AppTheme.text, fontSize: 13)),
          ],
        ),
      );

  Widget _actions() => Row(children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.teal,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _busy ? null : _claim,
            icon: const Icon(Icons.download, color: Colors.black, size: 18),
            label: Text(tr('Odbierz (Claim)'),
                style: const TextStyle(color: Colors.black)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.teal,
                side: const BorderSide(color: AppTheme.teal),
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _busy ? null : _deposit,
            icon: const Icon(Icons.upload, size: 18),
            label: Text(tr('Wpłać (Deposit)')),
          ),
        ),
      ]);

  Widget _onchainCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('SALDO ON-CHAIN (Polygon)'),
                  style: const TextStyle(
                      color: AppTheme.muted,
                      fontSize: 11,
                      letterSpacing: 0.8)),
              const SizedBox(height: 12),
              _smallRow(tr('GALU w portfelu'), _weiToDouble(_dhv)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(tr('MATIC (gas)'),
                        style: const TextStyle(
                            color: AppTheme.muted, fontSize: 13)),
                    Text(_weiToDouble(_matic).toStringAsFixed(4),
                        style: TextStyle(
                            color: _matic == BigInt.zero
                                ? AppTheme.red
                                : AppTheme.text,
                            fontSize: 13)),
                  ],
                ),
              ),
              if (_matic == BigInt.zero) ...[
                const SizedBox(height: 6),
                Text(
                    tr('Brak MATIC — transakcje (claim/deposit) wymagają gazu. '
                        'Wpłać MATIC na adres portfela (QR powyżej).'),
                    style: const TextStyle(color: AppTheme.amber, fontSize: 12)),
              ],
            ],
          ),
        ),
      );

  // Klucz portfela — zwinięte pod jeden kafel (zaawansowane, rzadko potrzebne)
  Widget _keysSection() => Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.vpn_key_outlined, color: AppTheme.muted),
            title: Text(tr('Klucz portfela (zaawansowane)'),
                style: const TextStyle(color: AppTheme.text)),
            subtitle: Text(tr('import / eksport klucza prywatnego'),
                style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            trailing: Icon(_keysOpen ? Icons.expand_less : Icons.expand_more,
                color: AppTheme.muted),
            onTap: () => setState(() => _keysOpen = !_keysOpen),
          ),
          if (_keysOpen) ...[
            const Divider(color: AppTheme.border, height: 1),
            _exportTile(),
            _importTile(),
          ],
        ]),
      );

  Widget _exportTile() => ListTile(
        leading: const Icon(Icons.key_outlined, color: AppTheme.amber),
        title: Text(tr('Eksportuj klucz (MetaMask)'),
            style: const TextStyle(color: AppTheme.text)),
        subtitle: Text(tr('wymaga PIN-u dowolnego Twojego noda'),
            style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.muted),
        onTap: _busy ? null : _exportKey,
      );

  Widget _importTile() => ListTile(
        leading: const Icon(Icons.download_outlined, color: AppTheme.amber),
        title: Text(tr('Importuj klucz prywatny'),
            style: const TextStyle(color: AppTheme.text)),
        subtitle: Text(tr('wklej klucz z MetaMask (0x… lub 64 hex)'),
            style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.muted),
        onTap: _busy ? null : _importKey,
      );

  Future<void> _importKey() async {
    final ctrl = TextEditingController();
    final pk = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Importuj klucz prywatny'),
            style: const TextStyle(color: AppTheme.text)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Wklej klucz prywatny (np. z MetaMask). Rób to tylko na swoim telefonie.'),
              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          const SizedBox(height: 10),
          TextField(controller: ctrl, autofocus: true, maxLines: 2,
            style: const TextStyle(color: AppTheme.text, fontSize: 13, fontFamily: 'monospace'),
            decoration: const InputDecoration(hintText: '0x…',
                hintStyle: TextStyle(color: AppTheme.muted))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Anuluj'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amber),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(tr('Importuj'), style: const TextStyle(color: Colors.black))),
        ],
      ),
    );
    if (pk == null || pk.isEmpty) return;

    // Waliduj + policz adres BEZ zapisu (podglad przed nadpisaniem)
    final ws = context.read<WalletService>();
    String newAddr;
    try {
      newAddr = await ws.addressOf(pk);
    } catch (_) {
      _snack(tr('Nieprawidłowy klucz prywatny'), error: true);
      return;
    }

    final current = context.read<CoreBloc>().state.wallet?.address;
    final sameWallet = current != null && current.toLowerCase() == newAddr.toLowerCase();

    if (!sameWallet && current != null) {
      // Inny wallet niz obecny owner nodow — ostrzez o konsekwencjach
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text(tr('Inny portfel'), style: const TextStyle(color: AppTheme.text)),
          content: Text(tr(
              'Importujesz INNY portfel (%s) niż obecny (%s).\n\n'
              'Twoje nody pozostaną przypisane do obecnego portfela, dopóki nie dodasz ich '
              'ponownie przez Bluetooth (to zmieni właściciela i wymaga ponownej weryfikacji — '
              'bez resetu urządzenia). Zarobione GALU zostają przy portfelu, który je zarobił.',
              [_shortAddr(newAddr), _shortAddr(current)]),
              style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Anuluj'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amber),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Zaimportuj mimo to'), style: const TextStyle(color: Colors.black))),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busy = true);
    try {
      await ws.restore(pk);
      if (!mounted) return;
      context.read<CoreBloc>().add(WalletImported());
      _snack(sameWallet
          ? tr('Portfel zaimportowany — Twoje nody działają dalej')
          : tr('Portfel zaimportowany: %s', [_shortAddr(newAddr)]));
    } catch (e) {
      if (mounted) _snack(tr('Błąd importu: %s', [e.toString()]), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _shortAddr(String a) => a.length > 12 ? '${a.substring(0,6)}…${a.substring(a.length-4)}' : a;

  // ── Dialogi ─────────────────────────────────────────────────
  Future<String?> _amountDialog(String title, double maxHuman) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(title, style: const TextStyle(color: AppTheme.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.text, fontSize: 18),
              decoration: const InputDecoration(
                hintText: '0.0',
                hintStyle: TextStyle(color: AppTheme.muted),
                suffixText: 'GALU',
                suffixStyle: TextStyle(color: AppTheme.muted),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => ctrl.text = maxHuman.toStringAsFixed(6),
              child: Text(
                  tr('Dostępne: %s (MAX)', [maxHuman.toStringAsFixed(4)]),
                  style: const TextStyle(color: AppTheme.teal, fontSize: 12)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Anuluj'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.teal),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(tr('Dalej'), style: const TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Future<String?> _pinDialog() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('PIN noda'), style: const TextStyle(color: AppTheme.text)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(
              color: AppTheme.text, fontSize: 18, letterSpacing: 2),
          decoration: const InputDecoration(
            hintText: 'PIN',
            hintStyle: TextStyle(color: AppTheme.muted),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Anuluj'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.teal),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(tr('Odblokuj'),
                style: const TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _showKeyDialog(String pk) {
    // Kanoniczne 64 hex (32 bajty). web3dart potrafi zwrócić 66 znaków z wiodącym
    // bajtem 00 (klucz z najwyższym bitem = 1, ~50% przypadków) albo <64 (wiodące
    // zero) — MetaMask wymaga dokładnie 64. Obetnij nadmiar / dopełnij zerami.
    final k = pk.length > 64 ? pk.substring(pk.length - 64) : pk.padLeft(64, '0');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Klucz prywatny'),
            style: const TextStyle(color: AppTheme.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppTheme.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(
                  tr('⚠️ Nigdy nikomu nie pokazuj tego klucza. Kto go ma, '
                      'kontroluje portfel i wszystkie GALU.'),
                  style: const TextStyle(color: AppTheme.red, fontSize: 12)),
            ),
            const SizedBox(height: 12),
            SelectableText('0x$k',
                style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 12,
                    fontFamily: 'monospace')),
            const SizedBox(height: 8),
            Text(
                tr('MetaMask → Importuj konto → Private Key → wklej.'),
                style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '0x$k'));
              _snack(tr('Klucz skopiowany'));
            },
            child: Text(tr('Kopiuj')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.teal),
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Zamknij'),
                style: const TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _showReceive(String addr) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('Odbiór MATIC / GALU'),
                style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(tr('Wyślij MATIC na ten adres (gas na transakcje)'),
                style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12)),
              child: QrImageView(
                  data: addr, size: 200, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 16),
            SelectableText(addr,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 12,
                    fontFamily: 'monospace')),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.teal,
                  side: const BorderSide(color: AppTheme.teal)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: addr));
                _snack(tr('Adres skopiowany'));
              },
              icon: const Icon(Icons.copy, size: 16),
              label: Text(tr('Kopiuj adres')),
            ),
          ],
        ),
      ),
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────
  double _dhvHuman() => _weiToDouble(_dhv);

  double _weiToDouble(BigInt wei) =>
      wei / BigInt.from(10).pow(18);

  BigInt _toWei(String amount) {
    final parts = amount.replaceAll(',', '.').split('.');
    final whole = parts[0].isEmpty ? '0' : parts[0];
    var frac = parts.length > 1 ? parts[1] : '';
    if (frac.length > 18) frac = frac.substring(0, 18);
    frac = frac.padRight(18, '0');
    try {
      return BigInt.parse(whole) * BigInt.from(10).pow(18) + BigInt.parse(frac);
    } catch (_) {
      return BigInt.zero;
    }
  }
}
