import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

abstract final class AppTheme {
  static final ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.negro,
    cardColor: AppColors.superficie,
    canvasColor: AppColors.superficie,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.ambar,
      secondary: AppColors.verde,
      surface: AppColors.superficie,
      onPrimary: Color(0xFF16181A),
      onSurface: AppColors.blanco,
    ),
    dividerColor: AppColors.borde,
    textTheme: TextTheme(
      // Titulares de módulo con Lora (serifa clásica y orgánica)
      headlineLarge: GoogleFonts.lora(
        fontWeight: FontWeight.bold,
        fontSize: 34,
        color: AppColors.blanco,
      ),
      headlineMedium: GoogleFonts.lora(
        fontWeight: FontWeight.bold,
        fontSize: 24,
        color: AppColors.blanco,
      ),
      headlineSmall: GoogleFonts.lora(
        fontWeight: FontWeight.bold,
        fontSize: 20,
        color: AppColors.blanco,
      ),
      // Nombres de producto / Títulos de tarjetas
      titleLarge: GoogleFonts.lora(
        fontWeight: FontWeight.bold,
        fontSize: 18,
        color: AppColors.blanco,
      ),
      titleMedium: GoogleFonts.lora(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: AppColors.blanco,
      ),
      titleSmall: GoogleFonts.lora(
        fontWeight: FontWeight.bold,
        fontSize: 14,
        color: AppColors.blanco,
      ),
      // Valores numéricos y texto de cuerpo con Outfit para legibilidad táctil
      bodyLarge: GoogleFonts.outfit(
        fontWeight: FontWeight.normal,
        fontSize: 16,
        color: AppColors.blanco,
      ),
      bodyMedium: GoogleFonts.outfit(
        fontWeight: FontWeight.normal,
        fontSize: 14,
        color: AppColors.blanco,
      ),
      bodySmall: GoogleFonts.outfit(
        fontWeight: FontWeight.normal,
        fontSize: 12,
        color: AppColors.blancoD,
      ),
      // Etiquetas / Botones
      labelLarge: GoogleFonts.outfit(
        fontWeight: FontWeight.bold,
        fontSize: 14,
        letterSpacing: 0.5,
        color: AppColors.blancoD,
      ),
      labelMedium: GoogleFonts.outfit(
        fontWeight: FontWeight.normal,
        fontSize: 13,
        letterSpacing: 0.5,
        color: AppColors.blancoD,
      ),
      labelSmall: GoogleFonts.outfit(
        fontWeight: FontWeight.normal,
        fontSize: 11,
        letterSpacing: 0.5,
        color: AppColors.blancoD,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.superficie2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.circular(14),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.ambar, width: 1.0),
        borderRadius: BorderRadius.circular(14),
      ),
      hintStyle: GoogleFonts.outfit(color: AppColors.gris, fontSize: 15),
      labelStyle: GoogleFonts.outfit(
        color: AppColors.blancoD,
        fontSize: 14,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.ambar,
        foregroundColor: const Color(0xFF24282F),
        elevation: 0,
        shadowColor: Colors.transparent,
        textStyle: GoogleFonts.outfit(
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.blanco,
        side: const BorderSide(color: AppColors.borde, width: 1.0),
        textStyle: GoogleFonts.outfit(
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.superficie,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide.none,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: Colors.transparent,
        selectedBackgroundColor: AppColors.ambar.withOpacity(0.2),
        selectedForegroundColor: AppColors.ambar,
        foregroundColor: AppColors.blancoD,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.negro,
      elevation: 0,
      titleTextStyle: GoogleFonts.lora(
        fontStyle: FontStyle.normal,
        fontWeight: FontWeight.bold,
        fontSize: 22,
        color: AppColors.blanco,
      ),
      iconTheme: const IconThemeData(color: AppColors.blanco, size: 24),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.superficie2,
      contentTextStyle: GoogleFonts.outfit(color: AppColors.blanco, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
