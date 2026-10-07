import 'package:flutter/material.dart';

class TarotTheme {
  static const Color darkBackground = Color(0xFF0A0A0A);
  static const Color gothicRed = Color(0xFF4A0404);
  static const Color goldAccent = Color(0xFFD4AF37);
  static const Color cardShadow = Colors.black87;

  static ThemeData get gothicTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Almendra',
      scaffoldBackgroundColor: darkBackground,
      colorScheme: ColorScheme.fromSeed(
        seedColor: gothicRed,
        primary: gothicRed,
        secondary: goldAccent,
        surface: darkBackground,
        brightness: Brightness.dark,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: goldAccent,
          fontSize: 32,
          fontWeight: FontWeight.bold,
          letterSpacing: 2.0,
        ),
        bodyLarge: TextStyle(
          color: Colors.white,
          fontSize: 18,
        ),
        bodyMedium: TextStyle(
          color: Colors.white70,
          fontSize: 16,
        ),
        labelLarge: TextStyle(
          color: goldAccent,
          fontSize: 20,
          fontStyle: FontStyle.italic,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: goldAccent,
          side: const BorderSide(color: goldAccent, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(0),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Almendra',
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: goldAccent,
        elevation: 0,
      ),
    );
  }
}

