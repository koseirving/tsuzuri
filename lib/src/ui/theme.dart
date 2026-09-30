import 'package:flutter/material.dart';

/// 紙と墨、くすんだ藍、差し色に金木犀。
abstract final class TsuzuriColors {
  static const paper = Color(0xFFF7F5F0);
  static const card = Color(0xFFFFFEFB);
  static const ink = Color(0xFF2B2A28);
  static const sub = Color(0xFF6E6A61);
  static const line = Color(0xFFE4DFD4);
  static const indigo = Color(0xFF3E5A73);
  static const osmanthus = Color(0xFFD9892B);
  static const highlight = Color(0xFFF6E3C6);
}

ThemeData tsuzuriTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: TsuzuriColors.indigo,
    primary: TsuzuriColors.indigo,
    secondary: TsuzuriColors.osmanthus,
    surface: TsuzuriColors.paper,
    onSurface: TsuzuriColors.ink,
  );
  const body = TextStyle(fontSize: 17, height: 1.8, color: TsuzuriColors.ink, letterSpacing: 0.3);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: TsuzuriColors.paper,
    appBarTheme: const AppBarTheme(
      backgroundColor: TsuzuriColors.paper,
      foregroundColor: TsuzuriColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: TsuzuriColors.ink, letterSpacing: 1),
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontSize: 22, height: 1.5, fontWeight: FontWeight.w600, color: TsuzuriColors.ink, letterSpacing: 1),
      titleMedium: TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w600, color: TsuzuriColors.ink),
      bodyLarge: body,
      bodyMedium: TextStyle(fontSize: 15, height: 1.7, color: TsuzuriColors.ink),
      bodySmall: TextStyle(fontSize: 13, height: 1.6, color: TsuzuriColors.sub),
      labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.5),
    ),
    cardTheme: const CardThemeData(
      color: TsuzuriColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: TsuzuriColors.line),
      ),
    ),
    dividerTheme: const DividerThemeData(color: TsuzuriColors.line, space: 1),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: TsuzuriColors.card,
      border: OutlineInputBorder(borderSide: BorderSide(color: TsuzuriColors.line)),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: TsuzuriColors.line)),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: TsuzuriColors.paper,
      indicatorColor: TsuzuriColors.highlight,
      elevation: 0,
    ),
  );
}
