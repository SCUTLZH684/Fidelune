import 'package:flutter/material.dart';

class FideluneColors {
  static const bg = Color(0xFF0D1117);
  static const surface = Color(0xFF161B22);
  static const surfaceElevated = Color(0xFF1F2630);
  static const border = Color(0xFF30363D);
  static const textPrimary = Color(0xFFF0F6FC);
  static const textSecondary = Color(0xFF9EAAB8);
  static const emerald = Color(0xFF2ECC71);
  static const amber = Color(0xFFF39C12);
  static const coral = Color(0xFFE74C3C);
  static const sky = Color(0xFF58A6FF);
}

ThemeData buildFideluneTheme() {
  const scheme = ColorScheme.dark(
    primary: FideluneColors.sky,
    secondary: FideluneColors.emerald,
    surface: FideluneColors.surface,
    error: FideluneColors.coral,
    onPrimary: Color(0xFF06101B),
    onSurface: FideluneColors.textPrimary,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: FideluneColors.bg,
    cardTheme: CardThemeData(
      color: FideluneColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: FideluneColors.border, width: 1),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: FideluneColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: FideluneColors.surface,
      indicatorColor: FideluneColors.sky.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final active = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: active ? FideluneColors.textPrimary : FideluneColors.textSecondary,
        );
      }),
    ),
    dividerColor: FideluneColors.border,
  );
}
