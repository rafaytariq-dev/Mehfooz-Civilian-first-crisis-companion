/// Mehfooz Design System — Colors, Typography, Themes.
///
/// Brand tokens from the CIRO spec:
///   Brand red:    #D62828 (emergency)
///   Brand green:  #2A9D8F (safe/verified)
///   Brand amber:  #E9C46A (caution)
///   Background:   #F5F1E8 (warm off-white)
///   Text primary: #1B1B1B

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Colors ───

class MColors {
  MColors._();

  // Brand
  static const red = Color(0xFFD62828);
  static const green = Color(0xFF2A9D8F);
  static const amber = Color(0xFFE9C46A);
  static const background = Color(0xFFF5F1E8);
  static const textPrimary = Color(0xFF1B1B1B);
  static const textSecondary = Color(0xFF6B6B6B);
  static const surface = Colors.white;
  static const divider = Color(0xFFE0DCCC);

  // Severity
  static const severity1 = Color(0xFF81C784); // minor — green
  static const severity2 = Color(0xFFAED581); // localized — lime
  static const severity3 = Color(0xFFE9C46A); // significant — amber
  static const severity4 = Color(0xFFFF8A65); // severe — orange
  static const severity5 = Color(0xFFD62828); // life-threatening — red

  static Color severityColor(int severity) {
    switch (severity) {
      case 1:
        return severity1;
      case 2:
        return severity2;
      case 3:
        return severity3;
      case 4:
        return severity4;
      case 5:
        return severity5;
      default:
        return severity3;
    }
  }

  // Map polygon overlay (severity-based)
  static Color severityPolygon(int severity) =>
      severityColor(severity).withValues(alpha: 0.3);

  // Urgency
  static const sos = Color(0xFFD62828);
  static const urgencyHigh = Color(0xFFFF6B35);
  static const urgencyMed = Color(0xFFE9C46A);
  static const urgencyLow = Color(0xFF2A9D8F);
}

// ─── Typography ───

class MTypography {
  MTypography._();

  // English
  static TextStyle headlineEn(BuildContext context) =>
      GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: MColors.textPrimary,
      );

  static TextStyle titleEn(BuildContext context) =>
      GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: MColors.textPrimary,
      );

  static TextStyle bodyEn(BuildContext context) =>
      GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: MColors.textPrimary,
      );

  static TextStyle captionEn(BuildContext context) =>
      GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: MColors.textSecondary,
      );

  static TextStyle buttonEn(BuildContext context) =>
      GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      );
}

// ─── Theme ───

class MTheme {
  MTheme._();

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: MColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: MColors.red,
        primary: MColors.red,
        secondary: MColors.green,
        tertiary: MColors.amber,
        surface: MColors.surface,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        brightness: Brightness.light,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: MColors.surface,
        foregroundColor: MColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: MColors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: MColors.surface,
        elevation: 2,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: MColors.red,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: MColors.red,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MColors.red,
          side: const BorderSide(color: MColors.red, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: MColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: MColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: MColors.red, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: MColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: MColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }
}

// ─── Spacing ───

class MSpacing {
  MSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

// ─── Radius ───

class MRadius {
  MRadius._();

  static const card = 16.0;
  static const fab = 28.0;
  static const chip = 20.0;
  static const sheet = 24.0;
}
