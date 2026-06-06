import 'package:flutter/material.dart';

abstract final class AppColors {
  // Fondos y superficies: Café/Madera profunda ultra oscura y tonos orgánicos cálidos
  static const Color negro = Color(0xFF0F0B08);      // Fondo base oscuro (cálido/madera quemada)
  static const Color superficie = Color(0xFF171310); // Superficie principal (tarjetas, contenedores)
  static const Color superficie2 = Color(0xFF221D19); // Elevación secundaria
  static const Color crema = Color(0xFF2E2721);       // Tono arcilla/madera intermedia
  static const Color gris = Color(0xFF52483E);        // Gris neutro cálido para textos secundarios desactivados
  
  // Bordes delgados elegantes
  static const Color borde = Color(0xFF2A231E);
  static const Color bordeMd = Color(0xFF42372F);
  
  // Acentos de la Bodega Clásica
  static const Color ambar = Color(0xFFC78038);      // Acento principal: Cobre cálido / Ámbar añejo
  static const Color ambarCl = Color(0xFFDF9E5B);    // Ámbar claro para hovers/estados activos
  static const Color ambarOs = Color(0xFF91541D);    // Ámbar oscuro para prensados/sombras

  static const Color verde = Color(0xFF4F6851);      // Acento secundario: Verde Oliva / Bosque orgánico
  static const Color rojo = Color(0xFF9E4B3F);       // Alertas/Eliminaciones: Siena/Terracota quemado

  // Tintas y tipografía de alto contraste (Vintage Paper whites)
  static const Color blanco = Color(0xFFF7F2E8);     // Blanco crema / papel antiguo para textos legibles
  static const Color blancoD = Color(0xFFCFBCA6);    // Blanco arena desaturado para subtítulos y etiquetas
}
