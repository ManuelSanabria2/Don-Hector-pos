import 'package:flutter/material.dart';

abstract final class AppColors {
  // Fondos y superficies: Gris oscuro más claro y acentos azul claro
  static const Color negro = Color(0xFF24282F);      // Gris oscuro más claro (fondo base premium)
  static const Color superficie = Color(0xFF33373E); // Color sólido (antes blanco translúcido con 7% de opacidad)
  static const Color superficie2 = Color(0xFF40454D); // Color sólido (antes blanco translúcido con 13% de opacidad)
  static const Color crema = Color(0xFF50545C);       // Color sólido (antes tono translúcido medio)
  static const Color gris = Color(0xFF9098A0);        // Gris claro para textos secundarios

  // Sin bordes para los recuadros
  static const Color borde = Colors.transparent;       // Completamente transparente
  static const Color bordeMd = Colors.transparent;     // Completamente transparente

  // Acentos Azul Claro Elegante
  static const Color ambar = Color(0xFF64B5F6);      // Acento principal: Azul claro elegante
  static const Color ambarCl = Color(0xFF90CAF9);    // Azul más claro para hovers/activos
  static const Color ambarOs = Color(0xFF1E88E5);    // Azul oscuro para sombras/prensados

  static const Color verde = Color(0xFF81C784);      // Verde claro/pastel
  static const Color rojo = Color(0xFFE57373);       // Rojo claro/pastel

  // Tintas de alto contraste
  static const Color blanco = Color(0xFFF0F4F8);     // Blanco frío para alta legibilidad
  static const Color blancoD = Color(0xFFB0BEC5);    // Blanco azulado desaturado para textos secundarios
}
