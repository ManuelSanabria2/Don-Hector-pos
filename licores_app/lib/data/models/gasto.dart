import 'model_helpers.dart';

class Gasto {
  const Gasto({
    required this.id,
    required this.descripcion,
    required this.monto,
    required this.fecha,
    this.categoriaId,
    this.notas,
    this.createdAt,
    this.anulado = false,
    this.metodoPago = 'efectivo',
  });

  final String id;
  final String descripcion;
  final num monto;
  final String? categoriaId;
  final DateTime fecha;
  final String? notas;
  final DateTime? createdAt;
  final bool anulado;
  final String metodoPago;

  factory Gasto.fromJson(Map<String, dynamic> json) {
    return Gasto(
      id: json['id'] as String,
      descripcion: json['descripcion'] as String,
      monto: parseNum(json['monto']),
      categoriaId: json['categoria_id'] as String?,
      fecha: parseRequiredDate(json['fecha']),
      notas: json['notas'] as String?,
      createdAt: parseDateTime(json['created_at']),
      anulado: json['anulado'] as bool? ?? false,
      metodoPago: json['metodo_pago'] as String? ?? 'efectivo',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'descripcion': descripcion,
      'monto': monto,
      'categoria_id': categoriaId,
      'fecha': dateOnly(fecha),
      'notas': notas,
      'created_at': createdAt?.toIso8601String(),
      'anulado': anulado,
      'metodo_pago': metodoPago,
    };
  }
}
