import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Jedna flaga, dwa ekrany: X na karcie Storage ją chowa, przełącznik w Ustawieniach przywraca.
/// Notifier zamiast gołego prefa, bo ekran nodów żyje w stosie zakładek — powrót z Ustawień
/// nie odpala initState ani odświeżenia, więc sam z siebie nowej wartości by nie odczytał.
class StoreCardPref {
  static const _key = 'store_card_hidden';
  static final hidden = ValueNotifier<bool>(false);

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      hidden.value = p.getBool(_key) ?? false;
    } catch (_) {}
  }

  static Future<void> set(bool v) async {
    hidden.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, v);
    } catch (_) {}
  }
}
