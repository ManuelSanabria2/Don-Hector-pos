import 'model_helpers.dart';

class Producto {
  const Producto({
    required this.id,
    required this.nombre,
    required this.precioPublico,
    required this.precioMayorista,
    required this.costo,
    required this.stockActual,
    required this.stockMinimo,
    this.categoriaId,
    this.descripcion,
    this.unidad,
    this.imagenUrl,
    this.codigoBarras,
    this.activo,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String nombre;
  final String? categoriaId;
  final String? descripcion;
  final num precioPublico;
  final num precioMayorista;
  final num costo;
  final int stockActual;
  final int stockMinimo;
  final String? unidad;
  final String? imagenUrl;
  final String? codigoBarras;
  final bool? activo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get stockBajo => stockActual < stockMinimo;

  factory Producto.fromJson(Map<String, dynamic> json) {
    return Producto(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
      categoriaId: json['categoria_id'] as String?,
      descripcion: json['descripcion'] as String?,
      precioPublico: parseNum(json['precio_publico']),
      precioMayorista: parseNum(json['precio_mayorista']),
      costo: parseNum(json['costo']),
      stockActual: parseInt(json['stock_actual']),
      stockMinimo: parseInt(json['stock_minimo'], 5),
      unidad: json['unidad'] as String?,
      imagenUrl: json['imagen_url'] as String?,
      codigoBarras: json['codigo_barras'] as String?,
      activo: json['activo'] as bool?,
      createdAt: parseDateTime(json['created_at']),
      updatedAt: parseDateTime(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'categoria_id': categoriaId,
      'descripcion': descripcion,
      'precio_publico': precioPublico,
      'precio_mayorista': precioMayorista,
      'costo': costo,
      'stock_actual': stockActual,
      'stock_minimo': stockMinimo,
      'unidad': unidad,
      'imagen_url': imagenUrl,
      'codigo_barras': codigoBarras,
      'activo': activo,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}
