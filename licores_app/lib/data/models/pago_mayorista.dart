import 'model_helpers.dart';
import 'venta_enums.dart';

class PagoMayorista {
  const PagoMayorista({
    required this.id,
    required this.cobroId,
    required this.monto,
    required this.metodoPago,
    this.fecha,
    this.notas,
  });

  final String id;
  final String cobroId;
  final num monto;
  final MetodoPago metodoPago;
  final DateTime? fecha;
  final String? notas;

  factory PagoMayorista.fromJson(Map<String, dynamic> json) {
    return PagoMayorista(
      id: json['id'] as String,
      cobroId: json['cobro_id'] as String,
      monto: parseNum(json['monto']),
      metodoPago: MetodoPago.fromJson(json['metodo_pago']),
      fecha: parseDateTime(json['fecha']),
      notas: json['notas'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cobro_id': cobroId,
      'monto': monto,
      'metodo_pago': metodoPago.value,
      'fecha': fecha?.toIso8601String(),
      'notas': notas,
    };
  }
}
