import 'package:flutter/material.dart';

/// SENSMOS — dark theme
class AppTheme {
  static const bg      = Color(0xFF0A0D12);
  static const surface = Color(0xFF111520);
  static const card    = Color(0xFF161C2A);
  static const teal    = Color(0xFF00E5B0);
  static const purple  = Color(0xFF8B7FFF);
  static const amber   = Color(0xFFF5A623);
  static const red     = Color(0xFFFF4757);
  static const blue    = Color(0xFF3A7BD5);
  static const text    = Color(0xFFC8D0E8);
  static const muted   = Color(0xFF5A6380);
  static const border  = Color(0x1F6384FF);

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        primaryColor: teal,
        colorScheme: const ColorScheme.dark(
          primary: teal,
          secondary: purple,
          surface: surface,
          error: red,
        ),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: surface,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: card,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: border, width: 1),
          ),
        ),
        // Jednolite przyciski w całej apce: wysokość 48, ten sam kształt/rozmiar czcionki.
        // Dzięki temu nie ma już różnych wysokości (30/40/…) rozsianych po ekranach.
        filledButtonTheme: FilledButtonThemeData(style: _btn()),
        elevatedButtonTheme: ElevatedButtonThemeData(style: _btn()),
        outlinedButtonTheme: OutlinedButtonThemeData(
            style: _btn().copyWith(side: WidgetStatePropertyAll(
                const BorderSide(color: border)))),
        textButtonTheme: TextButtonThemeData(style: _btn(pad: 12)),
        // Jednolite pola tekstowe w CAŁEJ apce: ten sam fill/label/ikony i to samo teal-owe
        // podświetlenie na focusie. Wcześniej każdy TextField miał własną dekorację → różne
        // kolory/ramki/podświetlenia. Pola mogą nadpisać label/icon, resztę dziedziczą stąd.
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: card,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          hintStyle: const TextStyle(color: muted),
          labelStyle: const TextStyle(color: muted),
          floatingLabelStyle: const TextStyle(color: teal),
          prefixIconColor: muted,
          suffixIconColor: muted,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: teal, width: 1.5)),
        ),
        textSelectionTheme: const TextSelectionThemeData(cursorColor: teal, selectionColor: border),
      );

  static ButtonStyle _btn({double pad = 14}) => ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
        padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: pad)),
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10))),
      );

  // Status node → kolor
  static Color statusColor(String s) => switch (s) {
        'online'  => teal,
        'recent'  => amber,
        'offline' => red,
        _         => muted,
      };
}
