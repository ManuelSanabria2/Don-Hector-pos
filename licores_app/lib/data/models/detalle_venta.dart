import 'model_helpers.dart';

class DetalleVenta {
  const DetalleVenta({
    required this.id,
    required this.ventaId,
    required this.productoId,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
    this.createdAt,
  });

  final String id;
  final String ventaId;
  final String productoId;
  final int cantidad;
  final num precioUnitario;
  final num subtotal;
  final DateTime? createdAt;

  factory DetalleVenta.fromJson(Map<String, dynamic> json) {
    return DetalleVenta(
      id: json['id'] as String,
      ventaId: json['venta_id'] as String,
      productoId: json['producto_id'] as String,
      cantidad: parseInt(json['cantidad']),
      precioUnitario: parseNum(json['precio_unitario']),
      subtotal: parseNum(json['subtotal']),
      createdAt: parseDateTime(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'venta_id': ventaId,
      'producto_id': productoId,
      'cantidad': cantidad,
      'precio_unitario': precioUnitario,
      'subtotal': subtotal,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
