import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// Paletă discretă, inspirată de aplicațiile financiare moderne:
/// fundal gri foarte deschis, carduri albe rotunjite, un singur albastru
/// de accent și culori pastelate pentru evidențieri.
class AppColors {
  static const background = Color(0xFFE9EDF4); // gri-albăstrui, puțin mai închis: cardurile albe ies în evidență
  static const surface = Colors.white;
  static const tile = Color(0xFFEEF2F8); // fundalul pătratelor cu icon
  static const primary = Color(0xFF2B59D9); // albastru: selecții și acțiuni
  static const primarySoft = Color(0xFFE8EEFC);
  static const primaryLine = Color(0xFFC9D6F5);
  static const text = Color(0xFF0F172A);
  static const textMuted = Color(0xFF64748B);
  static const textFaint = Color(0xFF94A3B8);
  static const divider = Color(0xFFE3E8F0); // și conturul fin al cardurilor
  static const track = Color(0xFFEEF1F6); // fundalul selectoarelor și al barelor

  static const green = Color(0xFF15803D); // câștiguri, încasări
  static const greenSoft = Color(0xFFDCFCE7);
  static const red = Color(0xFFB4372F);
  static const redSoft = Color(0xFFFCEBEA);
  static const amber = Color(0xFFA16207); // ocru: obligațiuni (OS)
  static const amberSoft = Color(0xFFFBF0DC);
  static const teal = Color(0xFF0F766E); // verde petrol: bonuri (BT)
  static const tealSoft = Color(0xFFE0F2EF);

  // seriile din grafice (nuanțe atenuate)
  static const term91 = Color(0xFF2A9D8F);
  static const term182 = Color(0xFF3557C8);
  static const term364 = Color(0xFFD9784A);

  static Color forTerm(int days) => days <= 120 ? term91 : days <= 250 ? term182 : term364;

  /// Culorile obligațiunilor pe termen (ani).
  static Color forBondYears(int years) => switch (years) {
        2 => term91,
        3 => term182,
        5 => term364,
        7 => const Color(0xFF8E5AC8),
        _ => const Color(0xFFC2477A),
      };
}

/// Nuanțe pastel pentru o secțiune (BT = mentă, OS = caisă): butonul ales,
/// sublinierea filei, anul ales și banda de sus a cardurilor.
class SectionPalette {
  final Color text; // text pe fundal pastel
  final Color soft; // fundalul opțiunii selectate
  final Color line; // banda de sus a cardului
  final Color underline; // sublinierea filei active
  final Color wash; // fundalul cipului selectat
  const SectionPalette({required this.text, required this.soft, required this.line, required this.underline, required this.wash});

  static const bills = SectionPalette(
    text: Color(0xFF0F766E),
    soft: Color(0xFFE0F2EF),
    line: Color(0xFFA7D7CF),
    underline: Color(0xFF5EB3A6),
    wash: Color(0xFFEFF8F6),
  );
  static const bonds = SectionPalette(
    text: Color(0xFFA16207),
    soft: Color(0xFFFBF0DC),
    line: Color(0xFFEBCB8F),
    underline: Color(0xFFD9A54A),
    wash: Color(0xFFFDF7EC),
  );
}

class AppTheme {
  /// Cifre cu lățime egală: sumele și procentele se aliniază pe coloane.
  static const _tnum = [FontFeature.tabularFigures()];

  static ThemeData light() {
    const font = 'Inter';
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
      brightness: Brightness.light,
    );
    const t = TextTheme(
      headlineSmall: TextStyle(fontFeatures: _tnum, fontSize: 21, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.2),
      titleLarge: TextStyle(fontFeatures: _tnum, fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text),
      titleMedium: TextStyle(fontFeatures: _tnum, fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text),
      titleSmall: TextStyle(fontFeatures: _tnum, fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.text),
      bodyLarge: TextStyle(fontFeatures: _tnum, fontSize: 14, color: AppColors.text),
      bodyMedium: TextStyle(fontFeatures: _tnum, fontSize: 13, color: AppColors.text),
      bodySmall: TextStyle(fontFeatures: _tnum, fontSize: 11.5, color: AppColors.textMuted),
      labelLarge: TextStyle(fontFeatures: _tnum, fontSize: 13, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(fontFeatures: _tnum, fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall: TextStyle(fontFeatures: _tnum, fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textMuted),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppColors.divider)),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: AppColors.divider,
        elevation: 1,
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
        fillColor: AppColors.track,
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
        side: const BorderSide(color: Color(0xFFDCE2EC)),
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
