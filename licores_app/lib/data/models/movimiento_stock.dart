import 'model_helpers.dart';

class MovimientoStock {
  const MovimientoStock({
    required this.id,
    required this.productoId,
    required this.tipo,
    required this.cantidad,
    required this.stockAntes,
    required this.stockDespues,
    this.motivo,
    this.referenciaId,
    this.createdAt,
  });

  final String id;
  final String productoId;
  final String tipo;
  final int cantidad;
  final int stockAntes;
  final int stockDespues;
  final String? motivo;
  final String? referenciaId;
  final DateTime? createdAt;

  factory MovimientoStock.fromJson(Map<String, dynamic> json) {
    return MovimientoStock(
      id: json['id'] as String,
      productoId: json['producto_id'] as String,
      tipo: json['tipo'] as String,
      cantidad: parseInt(json['cantidad']),
      stockAntes: parseInt(json['stock_antes']),
      stockDespues: parseInt(json['stock_despues']),
      motivo: json['motivo'] as String?,
      referenciaId: json['referencia_id'] as String?,
      createdAt: parseDateTime(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'producto_id': productoId,
      'tipo': tipo,
      'cantidad': cantidad,
      'stock_antes': stockAntes,
      'stock_despues': stockDespues,
      'motivo': motivo,
      'referencia_id': referenciaId,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
