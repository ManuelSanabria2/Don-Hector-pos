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
      headlineLarge: GoogleFonts.libreBaskerville(
        fontWeight: FontWeight.bold,
        fontSize: 38,
        color: AppColors.blanco,
      ),
      headlineMedium: GoogleFonts.libreBaskerville(
        fontWeight: FontWeight.bold,
        fontSize: 26,
        color: AppColors.blanco,
      ),
      headlineSmall: GoogleFonts.libreBaskerville(
        fontWeight: FontWeight.bold,
        fontSize: 22,
        color: AppColors.blanco,
      ),
      // Nombres de producto / Títulos de tarjetas
      titleLarge: GoogleFonts.libreBaskerville(
        fontWeight: FontWeight.bold,
        fontSize: 20,
        color: AppColors.blanco,
      ),
      titleMedium: GoogleFonts.libreBaskerville(
        fontWeight: FontWeight.bold,
        fontSize: 18,
        color: AppColors.blanco,
      ),
      titleSmall: GoogleFonts.libreBaskerville(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: AppColors.blanco,
      ),
      // Valores numéricos y texto de cuerpo (usamos Fira Mono para legibilidad y alineación de números)
      bodyLarge: GoogleFonts.firaMono(
        fontWeight: FontWeight.normal,
        fontSize: 18,
        color: AppColors.blanco,
      ),
      bodyMedium: GoogleFonts.firaMono(
        fontWeight: FontWeight.normal,
        fontSize: 16,
        color: AppColors.blanco,
      ),
      bodySmall: GoogleFonts.firaMono(
        fontWeight: FontWeight.normal,
        fontSize: 16,
        color: AppColors.blancoD,
      ),
      // Etiquetas / Botones
      labelLarge: GoogleFonts.firaMono(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        letterSpacing: 1.0,
        color: AppColors.blancoD,
      ),
      labelMedium: GoogleFonts.firaMono(
        fontWeight: FontWeight.normal,
        fontSize: 15,
        letterSpacing: 1.0,
        color: AppColors.blancoD,
      ),
      labelSmall: GoogleFonts.firaMono(
        fontWeight: FontWeight.normal,
        fontSize: 13,
        letterSpacing: 1.0,
        color: AppColors.blancoD,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.borde, width: 1.5),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.ambar, width: 2),
      ),
      hintStyle: GoogleFonts.firaMono(color: AppColors.gris, fontSize: 17),
      labelStyle: GoogleFonts.firaMono(
        color: AppColors.blancoD,
        fontSize: 16,
        letterSpacing: 1.0,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.ambar,
        foregroundColor: const Color(0xFF0A0800),
        textStyle: GoogleFonts.firaMono(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.blanco,
        side: const BorderSide(color: AppColors.borde, width: 1.5),
        textStyle: GoogleFonts.firaMono(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      ),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.superficie,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: AppColors.borde, width: 1.5),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.negro,
      elevation: 0,
      titleTextStyle: GoogleFonts.libreBaskerville(
        fontStyle: FontStyle.normal,
        fontWeight: FontWeight.bold,
        fontSize: 24,
        color: AppColors.blanco,
      ),
      iconTheme: const IconThemeData(color: AppColors.blanco, size: 28),
    ),
  );
}
