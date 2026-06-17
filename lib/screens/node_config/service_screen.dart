import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import '../../theme.dart';
import '../../services/ble_service.dart';
import '../../services/node_service.dart';
import '../../services/wallet_service.dart';
import '../../l10n.dart';

/// Tryb serwisowy (Bluetooth) — zmiana WiFi i odzyskanie portfela bez sieci.
/// Node przechodzi w BLE (przez /node/ble_mode albo przyciskiem), apka łączy
/// się po BLE i wykonuje akcje serwisowe.
class ServiceScreen extends StatefulWidget {
  final SavedNode node;
  const ServiceScreen({super.key, required this.node});

  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

enum _Phase { idle, entering, scanning, connected, working, error }

class _ServiceScreenState extends State<ServiceScreen> {
  _Phase _phase = _Phase.idle;
  String _status = '';
  String? _error;
  String? _info;

  BleService get _ble => context.read<BleService>();

  @override
  void dispose() {
    if (_phase == _Phase.connected || _phase == _Phase.working) {
      _ble.disconnect();
    }
    super.dispose();
  }

  Future<void> _enterBleMode() async {
    setState(() {
      _phase = _Phase.entering; _error = null; _info = null;
      _status = tr('Przełączam node w tryb Bluetooth…');
    });

    // Spróbuj przez sieć; jeśli node nieosiągalny — user użyje przycisku 3s
    try {
      await http.post(Uri.parse('http://${widget.node.ip}/node/ble_mode'),
          headers: {'Authorization': 'Bearer ${widget.node.pin}'})
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      setState(() => _status = tr(
          'Node nieosiągalny po sieci — przytrzymaj przycisk na nodzie 3 s, '
          'aż wejdzie w tryb Bluetooth…'));
    }

    // Skanuj BLE: SENSMOS-<6 znaków device_id>
    setState(() { _phase = _Phase.scanning; });
    await Future.delayed(const Duration(seconds: 4));
    final shortId = widget.node.id.length >= 6
        ? widget.node.id.substring(0, 6) : widget.node.id;
    final target = 'SENSMOS-${shortId.toUpperCase()}';

    BluetoothDevice? device;
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    StreamSubscription? sub;
    try {
      while (device == null && DateTime.now().isBefore(deadline)) {
        final found = Completer<BluetoothDevice?>();
        sub = _ble.scan(timeout: const Duration(seconds: 10)).listen((rs) {
          for (final r in rs) {
            final n = r.advertisementData.advName.isNotEmpty
                ? r.advertisementData.advName : r.device.platformName;
            if (n.toUpperCase() == target && !found.isCompleted) {
              found.complete(r.device);
            }
          }
        });
        device = await found.future
            .timeout(const Duration(seconds: 11), onTimeout: () => null);
        await sub.cancel();
        await _ble.stopScan();
      }
    } catch (_) {
      await sub?.cancel();
    }

    if (device == null) {
      setState(() {
        _phase = _Phase.error;
        _error = tr('Nie znalazłem noda przez Bluetooth.\n'
            'Upewnij się, że jest w trybie serwisowym (przycisk 3 s).');
      });
      return;
    }

    try {
      await _ble.connect(device);
      final auth = await _ble.sendCommand({'cmd': 'auth', 'pin': widget.node.pin});
      if (auth['status'] != 'ok') throw Exception(tr('Błędny PIN'));
      setState(() { _phase = _Phase.connected; _status = ''; });
    } catch (e) {
      try { await _ble.disconnect(); } catch (_) {}
      setState(() {
        _phase = _Phase.error;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _changeWifi() async {
    final res = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _WifiDialog(),
    );
    if (res == null) return;
    setState(() { _phase = _Phase.working; _status = tr('Zapisuję WiFi…'); });
    try {
      final r = await _ble.wifiSet(res.$1, res.$2);
      if (r['status'] != 'ok') throw Exception(r['msg'] ?? tr('błąd'));
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _info = tr('WiFi zapisane — node restartuje się i łączy z siecią.');
      });
      await _ble.disconnect();
    } catch (e) {
      setState(() {
        _phase = _Phase.error;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _recoverWallet() async {
    final wallet = context.read<WalletService>();
    setState(() { _phase = _Phase.working; _status = tr('Pobieram kopię z noda…'); });
    try {
      final r = await _ble.walletRestore();
      final blob = r['blob'] as String?;
      if (r['status'] != 'ok' || blob == null || blob.isEmpty) {
        throw Exception(r['msg'] == 'no_backup'
            ? tr('Ten node nie ma kopii portfela') : tr('Brak kopii'));
      }
      final w = await wallet.importEncrypted(blob, widget.node.pin);
      if (!mounted) return;
      setState(() {
        _phase = _Phase.connected;
        _info = tr('Portfel odzyskany: %s', [w.short]);
      });
    } catch (e) {
      setState(() {
        _phase = _Phase.connected;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Tryb serwisowy'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _intro(),
          const SizedBox(height: 16),
          if (_phase == _Phase.idle || _phase == _Phase.error)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.teal,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _enterBleMode,
              icon: const Icon(Icons.bluetooth_searching, color: Colors.black),
              label: Text(tr('Wejdź w tryb serwisowy'),
                  style: const TextStyle(color: Colors.black, fontSize: 15)),
            ),
          if (_phase == _Phase.entering ||
              _phase == _Phase.scanning ||
              _phase == _Phase.working) ...[
            const Center(child: CircularProgressIndicator(color: AppTheme.teal)),
            const SizedBox(height: 12),
            Center(
                child: Text(_status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.muted, fontSize: 13))),
          ],
          if (_phase == _Phase.connected) ...[
            _actionTile(Icons.wifi, tr('Zmień sieć WiFi'),
                tr('wpisz nowe SSID i hasło — node przełączy się'), _changeWifi),
            _actionTile(Icons.restore, tr('Odzyskaj portfel z noda'),
                tr('pobierz kopię portfela na ten telefon'), _recoverWallet),
          ],
          if (_info != null) ...[
            const SizedBox(height: 16),
            _banner(_info!, AppTheme.teal, Icons.check_circle),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            _banner(_error!, AppTheme.red, Icons.error_outline),
          ],
        ],
      ),
    );
  }

  Widget _intro() => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Po co tryb serwisowy?'),
                  style: const TextStyle(
                      color: AppTheme.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                  tr('Zmiana WiFi i odzyskiwanie portfela działają tylko przez '
                  'Bluetooth (bliskość fizyczna). Node przejdzie w tryb BLE — '
                  'jeśli jest nieosiągalny po sieci, przytrzymaj przycisk na '
                  'nodzie ok. 3 s.'),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
            ],
          ),
        ),
      );

  Widget _actionTile(IconData icon, String title, String sub, VoidCallback onTap) =>
      Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(icon, color: AppTheme.teal),
          title: Text(title, style: const TextStyle(color: AppTheme.text)),
          subtitle: Text(sub,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, color: AppTheme.muted),
          onTap: onTap,
        ),
      );

  Widget _banner(String text, Color color, IconData icon) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text, style: TextStyle(color: color, fontSize: 13))),
        ]),
      );
}

class _WifiDialog extends StatefulWidget {
  const _WifiDialog();
  @override
  State<_WifiDialog> createState() => _WifiDialogState();
}

class _WifiDialogState extends State<_WifiDialog> {
  final _ssid = TextEditingController();
  final _pass = TextEditingController();

  @override
  void dispose() {
    _ssid.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.card,
      title: Text(tr('Nowa sieć WiFi'), style: const TextStyle(color: AppTheme.text)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ssid,
            autofocus: true,
            style: const TextStyle(color: AppTheme.text),
            decoration: InputDecoration(labelText: tr('Nazwa sieci (SSID)'),
                labelStyle: const TextStyle(color: AppTheme.muted)),
          ),
          TextField(
            controller: _pass,
            obscureText: true,
            style: const TextStyle(color: AppTheme.text),
            decoration: InputDecoration(labelText: tr('Hasło'),
                labelStyle: const TextStyle(color: AppTheme.muted)),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Anuluj'))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.teal),
          onPressed: () {
            if (_ssid.text.trim().isNotEmpty) {
              Navigator.pop(context, (_ssid.text.trim(), _pass.text));
            }
          },
          child: Text(tr('Zapisz'), style: const TextStyle(color: Colors.black)),
        ),
      ],
    );
  }
}
