import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

abstract final class AppTheme {
  static final ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.negro,
    cardColor: AppColors.superficie,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.ambar,
      secondary: AppColors.verde,
      surface: AppColors.superficie,
      onPrimary: Color(0xFF0A0800),
      onSurface: AppColors.blanco,
    ),
    dividerColor: AppColors.borde,
    textTheme: TextTheme(
      // Titulares de módulo
      headlineLarge: GoogleFonts.cormorantGaramond(
        fontWeight: FontWeight.w300,
        fontSize: 48,
        fontStyle: FontStyle.italic,
        color: AppColors.blanco,
      ),
      headlineMedium: GoogleFonts.cormorantGaramond(
        fontWeight: FontWeight.w400,
        fontSize: 28,
        color: AppColors.blanco,
      ),
      // Nombres de producto
      titleMedium: GoogleFonts.cormorantGaramond(
        fontWeight: FontWeight.w400,
        fontSize: 17,
        color: AppColors.blanco,
      ),
      // Valores numéricos
      bodyLarge: GoogleFonts.cormorantGaramond(
        fontWeight: FontWeight.w400,
        fontSize: 14,
        color: AppColors.blanco,
      ),
      bodyMedium: GoogleFonts.cormorantGaramond(
        fontWeight: FontWeight.w400,
        fontSize: 13,
        color: AppColors.blanco,
      ),
      bodySmall: GoogleFonts.cormorantGaramond(
        fontWeight: FontWeight.w300,
        fontSize: 11,
        color: AppColors.blancoD,
      ),
      // Etiquetas
      labelLarge: GoogleFonts.cormorantGaramond(
        fontWeight: FontWeight.w500,
        fontSize: 11,
        letterSpacing: 2.0,
        color: AppColors.blancoD,
      ),
      labelSmall: GoogleFonts.cormorantGaramond(
        fontWeight: FontWeight.w300,
        fontSize: 10,
        letterSpacing: 2.0,
        color: AppColors.blancoD,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.borde, width: 1),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.ambar, width: 1),
      ),
      hintStyle: GoogleFonts.cormorantGaramond(color: AppColors.gris, fontSize: 13),
      labelStyle: GoogleFonts.cormorantGaramond(
        color: AppColors.blancoD,
        fontSize: 10,
        letterSpacing: 2.0,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.ambar,
        foregroundColor: const Color(0xFF0A0800),
        textStyle: GoogleFonts.cormorantGaramond(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          letterSpacing: 2.0,
        ),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.blanco,
        side: const BorderSide(color: AppColors.borde, width: 1),
        textStyle: GoogleFonts.cormorantGaramond(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          letterSpacing: 2.0,
        ),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      ),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.superficie,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: AppColors.borde, width: 1),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.negro,
      elevation: 0,
      titleTextStyle: GoogleFonts.cormorantGaramond(
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w300,
        fontSize: 24,
        color: AppColors.blanco,
      ),
      iconTheme: const IconThemeData(color: AppColors.blanco),
    ),
  );
}
