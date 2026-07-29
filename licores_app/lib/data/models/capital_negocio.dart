import 'model_helpers.dart';

class CapitalNegocio {
  const CapitalNegocio({
    required this.id,
    required this.efectivoInicial,
    required this.valorInventarioInicial,
    this.notas,
    required this.fechaRegistro,
    this.fechaCorte,
    this.createdAt,
  });

  final String id;
  final num efectivoInicial;
  final num valorInventarioInicial;
  final String? notas;
  final DateTime fechaRegistro;

  /// Instante del conteo físico de caja: el efectivo real acumula
  /// flujos a partir de este momento.
  final DateTime? fechaCorte;
  final DateTime? createdAt;

  num get capitalTotal => efectivoInicial + valorInventarioInicial;

  factory CapitalNegocio.fromJson(Map<String, dynamic> json) {
    return CapitalNegocio(
      id: json['id'] as String? ?? '',
      efectivoInicial: parseNum(json['efectivo_inicial']),
      valorInventarioInicial: parseNum(json['valor_inventario_inicial']),
      notas: json['notas'] as String?,
      fechaRegistro: parseRequiredDate(json['fecha_registro']),
      fechaCorte: parseDateTime(json['fecha_corte']),
      createdAt: parseDateTime(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'efectivo_inicial': efectivoInicial,
      'valor_inventario_inicial': valorInventarioInicial,
      'notas': notas,
      'fecha_registro': dateOnly(fechaRegistro),
      'fecha_corte': fechaCorte?.toUtc().toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
