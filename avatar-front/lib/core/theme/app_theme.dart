/// ДИЗАЙН-ТОКЕНЫ И ТЕМА «АВАТАР» (зона Коли → после 20.09 зона Артёма).
///
/// Минимальный жизнеспособный набор токенов: бренд-цвета из брендбука
/// (синий #1D5BA6, жёлтый #F5E326), типографика и темы виджетов M3.
/// Когда придёт полноценный UI-кит Коли (AppButton/AppCard/StatusChip),
/// экраны переводятся на него без смены токенов.
library;

import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color brandBlue = Color(0xFF1D5BA6);
  static const Color brandYellow = Color(0xFFF5E326);
  static const Color background = Color(0xFFF4F6FA);
  static const Color error = Color(0xFFC62828);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFB26A00);
}

abstract final class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandBlue,
      primary: AppColors.brandBlue,
      secondary: AppColors.brandYellow,
      error: AppColors.error,
      surface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.brandBlue,
        foregroundColor: Colors.white,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brandBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF323232),
        contentTextStyle: TextStyle(color: Colors.white),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.brandYellow,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
