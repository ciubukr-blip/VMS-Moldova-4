import 'package:flutter/material.dart';

/// Paletă discretă, inspirată de aplicațiile financiare moderne:
/// fundal gri foarte deschis, carduri albe rotunjite, un singur albastru
/// de accent și culori pastelate pentru evidențieri.
class AppColors {
  static const background = Color(0xFFF3F5F8);
  static const surface = Colors.white;
  static const tile = Color(0xFFEEF2F8); // fundalul pătratelor cu icon
  static const primary = Color(0xFF3557C8); // albastru calm
  static const primarySoft = Color(0xFFE6ECFA);
  static const text = Color(0xFF111827);
  static const textMuted = Color(0xFF6B7280);
  static const textFaint = Color(0xFF9CA3AF);
  static const divider = Color(0xFFE7EAF0);

  static const green = Color(0xFF1E7B4A);
  static const greenSoft = Color(0xFFE5F5EC);
  static const red = Color(0xFFB4372F);
  static const redSoft = Color(0xFFFCEBEA);
  static const amber = Color(0xFF9A5B00);
  static const amberSoft = Color(0xFFFFF3DD);
  static const teal = Color(0xFF2A8C82);
  static const tealSoft = Color(0xFFE2F3F1);

  // seriile din grafice (nuanțe atenuate)
  static const term91 = Color(0xFF2A9D8F);
  static const term182 = Color(0xFF3557C8);
  static const term364 = Color(0xFFD9784A);

  static Color forTerm(int days) => days <= 120 ? term91 : days <= 250 ? term182 : term364;
}

class AppTheme {
  static ThemeData light() {
    const font = 'Inter';
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
      brightness: Brightness.light,
    );
    const t = TextTheme(
      headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text, letterSpacing: -0.2),
      titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text),
      titleSmall: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.text),
      bodyLarge: TextStyle(fontSize: 14, color: AppColors.text),
      bodyMedium: TextStyle(fontSize: 13, color: AppColors.text),
      bodySmall: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textMuted),
    );
    final radius = BorderRadius.circular(14);
    return ThemeData(
      useMaterial3: true,
      fontFamily: font,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: t,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontFamily: font, fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primarySoft,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontFamily: font,
              fontSize: 11.5,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textMuted,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              size: 22,
              color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textMuted,
            )),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        labelStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        helperStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: AppColors.primary, width: 1.2)),
        errorBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: AppColors.red)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primarySoft,
        side: const BorderSide(color: AppColors.divider),
        labelStyle: const TextStyle(fontFamily: font, fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        showCheckmark: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          textStyle: const TextStyle(fontFamily: font, fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: const TextStyle(fontFamily: font, fontSize: 13.5, fontWeight: FontWeight.w600)),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        titleTextStyle: TextStyle(fontFamily: font, fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text),
        subtitleTextStyle: TextStyle(fontFamily: font, fontSize: 12, color: AppColors.textMuted),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
