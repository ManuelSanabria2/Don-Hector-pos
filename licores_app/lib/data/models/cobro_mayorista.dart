import 'model_helpers.dart';
import 'venta_enums.dart';

class CobroMayorista {
  const CobroMayorista({
    required this.id,
    required this.ventaId,
    required this.clienteId,
    required this.totalVenta,
    required this.totalPagado,
    required this.saldo,
    required this.estado,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String ventaId;
  final String clienteId;
  final num totalVenta;
  final num totalPagado;
  final num saldo;
  final EstadoCobro estado;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory CobroMayorista.fromJson(Map<String, dynamic> json) {
    return CobroMayorista(
      id: json['id'] as String,
      ventaId: json['venta_id'] as String,
      clienteId: json['cliente_id'] as String,
      totalVenta: parseNum(json['total_venta']),
      totalPagado: parseNum(json['total_pagado']),
      saldo: parseNum(json['saldo']),
      estado: EstadoCobro.fromJson(json['estado']),
      createdAt: parseDateTime(json['created_at']),
      updatedAt: parseDateTime(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'venta_id': ventaId,
      'cliente_id': clienteId,
      'total_venta': totalVenta,
      'total_pagado': totalPagado,
      'saldo': saldo,
      'estado': estado.value,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}
