import 'model_helpers.dart';

class DetalleCompra {
  const DetalleCompra({
    required this.id,
    required this.compraId,
    required this.productoId,
    required this.cantidad,
    required this.costoUnitario,
    required this.subtotal,
    this.nombreProducto,
  });

  final String id;
  final String compraId;
  final String productoId;
  final int cantidad;
  final num costoUnitario;
  final num subtotal;
  final String? nombreProducto;

  factory DetalleCompra.fromJson(Map<String, dynamic> json) {
    String? name;
    if (json['productos'] != null && json['productos'] is Map) {
      name = json['productos']['nombre'] as String?;
    } else {
      name = json['nombre_producto'] as String?;
    }

    return DetalleCompra(
      id: json['id'] as String? ?? '',
      compraId: json['compra_id'] as String? ?? '',
      productoId: json['producto_id'] as String? ?? '',
      cantidad: parseInt(json['cantidad']),
      costoUnitario: parseNum(json['costo_unitario']),
      subtotal: parseNum(json['subtotal']),
      nombreProducto: name,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'compra_id': compraId,
      'producto_id': productoId,
      'cantidad': cantidad,
      'costo_unitario': costoUnitario,
      'subtotal': subtotal,
      if (nombreProducto != null) 'nombre_producto': nombreProducto,
    };
  }
}
