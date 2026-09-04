import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../theme.dart';
import '../../l10n.dart';

/// Zmiana PIN-u noda — PEŁNY EKRAN, dwa pola: obecny i nowy.
///
/// Wcześniej było to okienko z jednym polem („nowy PIN"), a uwierzytelniało się PIN-em
/// ZAPISANYM w telefonie. Gdy ten się rozjechał — bo user zmienił PIN z innego telefonu albo
/// node został przeflashowany i wrócił do domyślnego — node odbijał `403 invalid_pin`, apka
/// pokazywała gołe „Error 403", a user wpadał w pętlę: żeby zmienić PIN, musi znać PIN.
/// Z polem „obecny PIN" (wstępnie wypełnionym zapisanym) wychodzi z tego bez usuwania noda
/// z listy.
class ChangePinScreen extends StatefulWidget {
  final String nodeIp;
  final String currentPin;   // to, co apka ma zapisane — punkt wyjścia, nie wyrocznia
  const ChangePinScreen({super.key, required this.nodeIp, required this.currentPin});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  late final _old = TextEditingController(text: widget.currentPin);
  final _new = TextEditingController();
  bool _showOld = false, _showNew = false, _busy = false;
  String? _error;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final oldPin = _old.text.trim(), newPin = _new.text.trim();
    if (newPin.length < 4) {
      setState(() => _error = tr('Nowy PIN musi mieć co najmniej 4 znaki.'));
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final res = await http
          .post(Uri.parse('http://${widget.nodeIp}/config'),
              headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $oldPin'},
              body: jsonEncode({'pin': newPin}))
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (res.statusCode == 200) {
        Navigator.pop(context, newPin);
        return;
      }
      // Kody rozróżniamy, bo każdy znaczy co innego i wymaga innej reakcji użytkownika.
      setState(() {
        _busy = false;
        _error = switch (res.statusCode) {
          403 => tr('Zły obecny PIN. Jeśli zmieniałeś go z innego telefonu, wpisz tamten; '
                    'po przeflashowaniu noda PIN wraca do 123456.'),
          429 => tr('Za dużo prób — node blokuje zmianę na 30 sekund.'),
          _   => tr('Node odrzucił zmianę (HTTP %s).', [res.statusCode]),
        };
      });
    } catch (_) {
      if (!mounted) return;
      // Node jest osiągalny tylko po LAN — najczęstszy powód to telefon w innej sieci.
      setState(() {
        _busy = false;
        _error = tr('Nie widzę noda pod %s — połącz telefon z tą samą siecią WiFi.', [widget.nodeIp]);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(title: Text(tr('Zmień PIN'))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              tr('PIN chroni lokalne API noda: ustawienia, skrypty, MQTT i tryb serwisowy. '
                 'Zmiana działa tylko w sieci noda.'),
              style: const TextStyle(color: AppTheme.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            _field(_old, tr('Obecny PIN'), Icons.lock_outline, _showOld,
                () => setState(() => _showOld = !_showOld)),
            _field(_new, tr('Nowy PIN (min. 4 znaki)'), Icons.vpn_key_outlined, _showNew,
                () => setState(() => _showNew = !_showNew)),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(color: AppTheme.red, fontSize: 13)),
            ],
            const SizedBox(height: 8),
            Text(
              tr('Po zmianie inne telefony z tym nodem zachowają stary PIN — trzeba go tam '
                 'poprawić w tym samym miejscu.'),
              style: const TextStyle(color: AppTheme.amber, fontSize: 11.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(_busy ? tr('Zapisywanie...') : tr('Zapisz')),
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.teal, foregroundColor: Colors.black),
            ),
          ],
        ),
      );

  Widget _field(TextEditingController c, String label, IconData icon, bool show, VoidCallback toggle) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: !show,
          keyboardType: TextInputType.number,
          inputFormatters: [LengthLimitingTextInputFormatter(15)],   // tyle przyjmuje firmware
          style: const TextStyle(color: AppTheme.text, letterSpacing: 2),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: AppTheme.muted),
            prefixIcon: Icon(icon, color: AppTheme.muted, size: 20),
            suffixIcon: IconButton(
              icon: Icon(show ? Icons.visibility_off : Icons.visibility,
                  color: AppTheme.muted, size: 20),
              onPressed: toggle,
            ),
            filled: true,
            fillColor: AppTheme.card,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      );
}
