import 'model_helpers.dart';
import 'venta_enums.dart';

/// Pago parcial o total sobre una venta fiada al público.
class AbonoFiado {
  const AbonoFiado({
    required this.id,
    required this.fiadoId,
    required this.monto,
    required this.metodoPago,
    this.fecha,
    this.notas,
  });

  final String id;
  final String fiadoId;
  final num monto;
  final MetodoPago metodoPago;
  final DateTime? fecha;
  final String? notas;

  factory AbonoFiado.fromJson(Map<String, dynamic> json) {
    return AbonoFiado(
      id: json['id'] as String,
      fiadoId: json['fiado_id'] as String,
      monto: parseNum(json['monto']),
      metodoPago: MetodoPago.fromJson(json['metodo_pago']),
      fecha: parseDateTime(json['fecha']),
      notas: json['notas'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fiado_id': fiadoId,
      'monto': monto,
      'metodo_pago': metodoPago.value,
      'fecha': fecha?.toIso8601String(),
      'notas': notas,
    };
  }
}
