import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The JusticeLand palette.
///
/// Deeper and cooler than the website's, on purpose: a phone is held at arm's
/// length in worse light than a desk monitor, and the extra contrast is what
/// keeps a lawyer card legible outdoors. Everything else — the gold accent,
/// the navy authority — is the same brand, which is why a client who used the
/// site recognises the app.
class AppColors {
  const AppColors._();

  static const Color primary = Color(0xFF0B1F3A); // deep navy
  static const Color primaryLight = Color(0xFF1B3A66);
  static const Color primaryDark = Color(0xFF06142A);

  static const Color secondary = Color(0xFF0F172A); // slate 900
  static const Color secondaryLight = Color(0xFF334155);

  static const Color accent = Color(0xFFD4A017); // premium gold
  static const Color accentSoft = Color(0xFFF6EDD3);

  static const Color surface = Color(0xFFFFFFFF);
  static const Color muted = Color(0xFFF8FAFC); // page background
  static const Color ink = Color(0xFF0F172A); // foreground text

  static const Color success = Color(0xFF22C55E); // 'online' green
  static const Color successSoft = Color(0xFFECFDF5);
  static const Color warning = Color(0xFFB45309);
  static const Color warningSoft = Color(0xFFFFFBEB);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerSoft = Color(0xFFFEF2F2);
  static const Color info = Color(0xFF2563EB);

  /// `text-ink/60` in the web app. Flutter has no alpha-in-token trick, so the
  /// common steps are named once here instead of being re-derived per screen.
  static Color inkAt(double opacity) => ink.withOpacity(opacity);
  static const Color inkStrong = ink;
  static Color get inkMuted => ink.withOpacity(0.62);
  static Color get inkFaint => ink.withOpacity(0.45);
  static Color get border => ink.withOpacity(0.10);
  static Color get borderStrong => ink.withOpacity(0.16);
}

/// Typography mirrors the site: Lora for display headings, Inter for the rest.
/// Both are declared in pubspec-free fashion (Google Fonts are not bundled), so
/// the app falls back to the platform sans if the fonts are not added — the
/// hierarchy still reads correctly.
class AppText {
  const AppText._();

  static const String display = 'Lora';
  static const String sans = 'Inter';
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: AppColors.ink,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.danger,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.muted,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontFamily: AppText.display,
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),

      textTheme: base.textTheme
          .apply(
            bodyColor: AppColors.ink,
            displayColor: AppColors.ink,
            fontFamily: AppText.sans,
          )
          .copyWith(
            displayLarge: const TextStyle(
              fontFamily: AppText.display,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              height: 1.15,
              color: AppColors.ink,
            ),
            headlineMedium: const TextStyle(
              fontFamily: AppText.display,
              fontSize: 24,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: AppColors.ink,
            ),
            titleLarge: const TextStyle(
              fontFamily: AppText.display,
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
            titleMedium: const TextStyle(
              fontFamily: AppText.sans,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
            bodyMedium: TextStyle(
              fontFamily: AppText.sans,
              fontSize: 14,
              height: 1.5,
              color: AppColors.ink.withOpacity(0.75),
            ),
            bodySmall: TextStyle(
              fontFamily: AppText.sans,
              fontSize: 12.5,
              color: AppColors.ink.withOpacity(0.55),
            ),
            labelLarge: const TextStyle(
              fontFamily: AppText.sans,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),

      cardTheme: CardTheme(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppColors.border),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: TextStyle(color: AppColors.ink.withOpacity(0.38), fontSize: 14),
        labelStyle: TextStyle(color: AppColors.ink.withOpacity(0.6), fontSize: 14),
        border: _fieldBorder(AppColors.border),
        enabledBorder: _fieldBorder(AppColors.border),
        focusedBorder: _fieldBorder(AppColors.primary, width: 1.6),
        errorBorder: _fieldBorder(AppColors.danger),
        focusedErrorBorder: _fieldBorder(AppColors.danger, width: 1.6),
        errorStyle: const TextStyle(fontSize: 12.5, color: AppColors.danger),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: const TextStyle(
            fontFamily: AppText.sans,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(0, 50),
          side: BorderSide(color: AppColors.borderStrong),
          textStyle: const TextStyle(
            fontFamily: AppText.sans,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primary.withOpacity(0.10),
        side: BorderSide(color: AppColors.border),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      dividerTheme: DividerThemeData(color: AppColors.border, thickness: 1, space: 1),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.ink.withOpacity(0.45),
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11.5),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.secondary,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      dialogTheme: DialogTheme(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
