import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const paper = Color(0xFFFCFAF6);
  static const canvas = Color(0xFFF3EEE5);
  static const panel = Color(0xFFFFFCF7);
  static const panelMuted = Color(0xFFF6F0E7);
  static const ink = Color(0xFF20211E);
  static const mutedInk = Color(0xFF6B6A63);
  static const border = Color(0xFFE2D8C8);
  static const borderStrong = Color(0xFFB4A897);
  static const brass = Color(0xFFC7772B);
  static const brassSoft = Color(0xFFF4E1CD);
  static const ready = Color(0xFF2F6B59);
  static const readySoft = Color(0xFFE7F1EC);
  static const active = Color(0xFF2F5D7C);
  static const activeSoft = Color(0xFFE8F0F6);
  static const warning = Color(0xFFB86A1F);
  static const warningSoft = Color(0xFFF8ECDD);
  static const error = Color(0xFF9B3E2C);
  static const errorSoft = Color(0xFFF8E8E3);
  static const advancedBg = Color(0xFF232622);
  static const advancedPanel = Color(0xFF2B2F2B);
  static const advancedBorder = Color(0xFF3E463F);
  static const advancedText = Color(0xFFF4EFE7);
  static const advancedMuted = Color(0xFFB8B1A6);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: AppColors.brass,
      secondary: AppColors.ready,
      surface: AppColors.panel,
      error: AppColors.error,
    ),
    scaffoldBackgroundColor: AppColors.canvas,
  );

  final textTheme = GoogleFonts.instrumentSansTextTheme(base.textTheme).copyWith(
    displayLarge: GoogleFonts.fraunces(
      fontSize: 44,
      height: 0.98,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    ),
    headlineLarge: GoogleFonts.fraunces(
      fontSize: 34,
      height: 1.02,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    ),
    headlineMedium: GoogleFonts.instrumentSans(
      fontSize: 24,
      height: 1.15,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    ),
    headlineSmall: GoogleFonts.instrumentSans(
      fontSize: 20,
      height: 1.2,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    ),
    titleLarge: GoogleFonts.instrumentSans(
      fontSize: 18,
      height: 1.25,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    ),
    titleMedium: GoogleFonts.instrumentSans(
      fontSize: 14,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: AppColors.ink,
    ),
    bodyLarge: GoogleFonts.instrumentSans(
      fontSize: 16,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: AppColors.ink,
    ),
    bodyMedium: GoogleFonts.instrumentSans(
      fontSize: 14,
      height: 1.45,
      fontWeight: FontWeight.w400,
      color: AppColors.ink,
    ),
    bodySmall: GoogleFonts.instrumentSans(
      fontSize: 12,
      height: 1.35,
      fontWeight: FontWeight.w500,
      color: AppColors.mutedInk,
    ),
    labelLarge: GoogleFonts.instrumentSans(
      fontSize: 13,
      height: 1.2,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    ),
  );

  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: AppColors.border),
  );

  return base.copyWith(
    textTheme: textTheme,
    dividerColor: AppColors.border,
    cardColor: AppColors.panel,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brass,
        foregroundColor: AppColors.paper,
        textStyle: GoogleFonts.instrumentSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.ink,
        textStyle: GoogleFonts.instrumentSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.paper,
      hintStyle: GoogleFonts.instrumentSans(
        fontSize: 14,
        color: AppColors.mutedInk,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: AppColors.brass, width: 1.4),
      ),
      border: inputBorder,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.ready.withValues(alpha: 0.36);
        }
        return AppColors.border;
      }),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.ready;
        }
        return AppColors.paper;
      }),
    ),
  );
}
