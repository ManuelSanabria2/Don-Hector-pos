import 'model_helpers.dart';
import 'venta_enums.dart';

/// Cuota pagada de un préstamo.
///
/// Se separa en dos partes porque contablemente valen cosas distintas:
/// [abonoCapital] baja la deuda y sale de la caja, pero no es un gasto;
/// [interes] sí es un gasto real y se registra como tal en `gastos`.
class PagoPrestamo {
  const PagoPrestamo({
    required this.id,
    required this.prestamoId,
    required this.abonoCapital,
    required this.interes,
    required this.monto,
    required this.metodoPago,
    this.fecha,
    this.notas,
  });

  final String id;
  final String prestamoId;
  final num abonoCapital;
  final num interes;

  /// Lo que efectivamente salió de la caja: abono + interés.
  final num monto;
  final MetodoPago metodoPago;
  final DateTime? fecha;
  final String? notas;

  factory PagoPrestamo.fromJson(Map<String, dynamic> json) {
    return PagoPrestamo(
      id: json['id'] as String,
      prestamoId: json['prestamo_id'] as String,
      abonoCapital: parseNum(json['abono_capital']),
      interes: parseNum(json['interes']),
      monto: parseNum(json['monto']),
      metodoPago: MetodoPago.fromJson(json['metodo_pago']),
      fecha: parseDateTime(json['fecha']),
      notas: json['notas'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'prestamo_id': prestamoId,
      'abono_capital': abonoCapital,
      'interes': interes,
      'monto': monto,
      'metodo_pago': metodoPago.value,
      'fecha': fecha?.toIso8601String(),
      'notas': notas,
    };
  }
}
