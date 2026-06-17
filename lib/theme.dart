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
      );

  // Status node → kolor
  static Color statusColor(String s) => switch (s) {
        'online'  => teal,
        'recent'  => amber,
        'offline' => red,
        _         => muted,
      };
}
