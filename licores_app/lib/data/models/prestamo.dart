import 'model_helpers.dart';
import 'venta_enums.dart';

/// Tipo de acreedor. Es informativo: no cambia el comportamiento contable.
enum TipoPrestamo {
  banco('banco', 'Banco o entidad'),
  prestamista('prestamista', 'Prestamista'),
  familiar('familiar', 'Familiar o conocido'),
  otro('otro', 'Otro');

  const TipoPrestamo(this.value, this.label);

  final String value;
  final String label;

  static TipoPrestamo fromJson(Object? value) {
    return TipoPrestamo.values.firstWhere(
      (item) => item.value == value,
      orElse: () => TipoPrestamo.prestamista,
    );
  }
}

/// Plata que el negocio recibió prestada y debe devolver.
///
/// Es un pasivo, no un ingreso: recibirlo sube el efectivo pero no la
/// utilidad, y devolverlo baja el efectivo pero tampoco la utilidad. Solo
/// el interés es un gasto real (ver [interesPagado]).
class Prestamo {
  const Prestamo({
    required this.id,
    required this.acreedor,
    required this.tipo,
    required this.monto,
    required this.capitalPagado,
    required this.saldo,
    required this.interesPagado,
    required this.metodoPago,
    required this.estado,
    this.tasaInteres,
    this.fecha,
    this.notas,
    this.createdAt,
  });

  final String id;
  final String acreedor;
  final TipoPrestamo tipo;

  /// Capital recibido (sin intereses).
  final num monto;
  final num capitalPagado;
  final num saldo;

  /// Intereses pagados hasta hoy. No baja el saldo: es el costo del crédito.
  final num interesPagado;

  /// Cómo entró la plata a la caja.
  final MetodoPago metodoPago;
  final EstadoCobro estado;
  final num? tasaInteres;
  final DateTime? fecha;
  final String? notas;
  final DateTime? createdAt;

  bool get estaPagado => saldo <= 0;

  factory Prestamo.fromJson(Map<String, dynamic> json) {
    return Prestamo(
      id: json['id'] as String,
      acreedor: json['acreedor'] as String? ?? '',
      tipo: TipoPrestamo.fromJson(json['tipo']),
      monto: parseNum(json['monto']),
      capitalPagado: parseNum(json['capital_pagado']),
      saldo: parseNum(json['saldo']),
      interesPagado: parseNum(json['interes_pagado']),
      metodoPago: MetodoPago.fromJson(json['metodo_pago']),
      estado: EstadoCobro.fromJson(json['estado']),
      tasaInteres:
          json['tasa_interes'] == null ? null : parseNum(json['tasa_interes']),
      fecha: parseDateTime(json['fecha']),
      notas: json['notas'] as String?,
      createdAt: parseDateTime(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'acreedor': acreedor,
      'tipo': tipo.value,
      'monto': monto,
      'capital_pagado': capitalPagado,
      'saldo': saldo,
      'interes_pagado': interesPagado,
      'metodo_pago': metodoPago.value,
      'estado': estado.value,
      'tasa_interes': tasaInteres,
      'fecha': fecha?.toIso8601String(),
      'notas': notas,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
