/// ДИЗАЙН-ТОКЕНЫ И ТЕМА «АВАТАР».
///
/// Бренд-цвета из брендбука (синий #1D5BA6, жёлтый #F5E326) + нейтральная
/// шкала, радиусы, отступы и темы виджетов M3. Экраны берут цвета ТОЛЬКО
/// отсюда — никаких «магических» Color(0xFF…) в фичах.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AppColors {
  // Бренд.
  static const Color brandBlue = Color(0xFF1D5BA6);
  static const Color brandBlueDeep = Color(0xFF113B72);
  static const Color brandBlueSoft = Color(0xFFE8F0FB);
  static const Color brandYellow = Color(0xFFF5E326);
  static const Color brandYellowSoft = Color(0xFFFDF8C9);

  // Нейтральная шкала.
  static const Color ink = Color(0xFF0F1B2D);
  static const Color inkSoft = Color(0xFF334155);
  static const Color muted = Color(0xFF64748B);
  static const Color faint = Color(0xFF94A3B8);
  static const Color border = Color(0xFFE2E8F0);
  static const Color background = Color(0xFFF3F5F9);
  static const Color surface = Colors.white;
  static const Color surfaceAlt = Color(0xFFF8FAFC);

  // Семантика.
  static const Color error = Color(0xFFC62828);
  static const Color errorSoft = Color(0xFFFDECEC);
  static const Color success = Color(0xFF1F8A4C);
  static const Color successSoft = Color(0xFFE6F5EC);
  static const Color warning = Color(0xFFB26A00);
  static const Color warningSoft = Color(0xFFFFF4DE);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2468BC), brandBlue, brandBlueDeep],
    stops: [0, 0.45, 1],
  );
}

abstract final class AppRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
}

abstract final class AppShadows {
  /// Мягкая «карточная» тень: едва заметная, но отрывает поверхность от фона.
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0A0F1B2D), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0F0F1B2D), blurRadius: 16, offset: Offset(0, 6)),
  ];

  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x291D5BA6), blurRadius: 24, offset: Offset(0, 10)),
  ];
}

abstract final class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandBlue,
      primary: AppColors.brandBlue,
      onPrimary: Colors.white,
      secondary: AppColors.brandYellow,
      onSecondary: AppColors.ink,
      secondaryContainer: AppColors.brandBlueSoft,
      onSecondaryContainer: AppColors.brandBlueDeep,
      error: AppColors.error,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.muted,
      outline: AppColors.faint,
      outlineVariant: AppColors.border,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = base.textTheme
        .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink)
        .copyWith(
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: AppColors.ink),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: AppColors.ink),
          titleLarge: base.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: AppColors.ink),
          titleMedium: base.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
              color: AppColors.ink),
          bodyMedium: base.textTheme.bodyMedium
              ?.copyWith(height: 1.35, color: AppColors.ink),
          bodySmall: base.textTheme.bodySmall
              ?.copyWith(height: 1.35, color: AppColors.muted),
        );

    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: color, width: width),
        );

    final buttonShape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md));
    const buttonText = TextStyle(
        fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.1);

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      dividerTheme:
          const DividerThemeData(color: AppColors.border, thickness: 1),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: Color(0x330F1B2D),
        centerTitle: false,
        titleSpacing: 20,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brandBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.faint,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brandBlue,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: const BorderSide(color: AppColors.border, width: 1.5),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brandBlue,
          shape: buttonShape,
          textStyle: buttonText.copyWith(fontSize: 14),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.brandBlue,
        foregroundColor: Colors.white,
        elevation: 3,
        highlightElevation: 6,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        extendedTextStyle: buttonText,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: inputBorder(AppColors.border),
        enabledBorder: inputBorder(AppColors.border),
        focusedBorder: inputBorder(AppColors.brandBlue, 2),
        errorBorder: inputBorder(AppColors.error),
        focusedErrorBorder: inputBorder(AppColors.error, 2),
        hintStyle: const TextStyle(color: AppColors.faint),
        labelStyle: const TextStyle(color: AppColors.muted),
        floatingLabelStyle: const TextStyle(
            color: AppColors.brandBlue, fontWeight: FontWeight.w600),
        helperStyle: const TextStyle(color: AppColors.muted),
        prefixIconColor: AppColors.muted,
        suffixIconColor: AppColors.muted,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.brandBlue,
        disabledColor: AppColors.border,
        checkmarkColor: Colors.white,
        showCheckmark: false,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.inkSoft,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.brandYellow,
        elevation: 0,
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? AppColors.ink
                : AppColors.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.ink
                : AppColors.muted,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl)),
        titleTextStyle: const TextStyle(
          color: AppColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        contentTextStyle: const TextStyle(
            color: AppColors.inkSoft, fontSize: 15, height: 1.4),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.muted,
        titleTextStyle: TextStyle(
            color: AppColors.ink, fontSize: 15, fontWeight: FontWeight.w600),
        subtitleTextStyle:
            TextStyle(color: AppColors.muted, fontSize: 13, height: 1.35),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brandBlue,
        circularTrackColor: AppColors.brandBlueSoft,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
