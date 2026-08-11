import 'model_helpers.dart';
import 'venta_enums.dart';

/// Deuda informal de una venta al público: alguien se llevó la mercancía
/// y quedó debiendo. El deudor se identifica solo por su nombre, sin
/// ficha de cliente.
class FiadoPublico {
  const FiadoPublico({
    required this.id,
    required this.ventaId,
    required this.deudorNombre,
    required this.totalVenta,
    required this.totalPagado,
    required this.saldo,
    required this.estado,
    this.deudorTelefono,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String ventaId;
  final String deudorNombre;
  final String? deudorTelefono;
  final num totalVenta;
  final num totalPagado;
  final num saldo;
  final EstadoCobro estado;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory FiadoPublico.fromJson(Map<String, dynamic> json) {
    return FiadoPublico(
      id: json['id'] as String,
      ventaId: json['venta_id'] as String,
      deudorNombre: json['deudor_nombre'] as String? ?? '',
      deudorTelefono: json['deudor_telefono'] as String?,
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
      'deudor_nombre': deudorNombre,
      'deudor_telefono': deudorTelefono,
      'total_venta': totalVenta,
      'total_pagado': totalPagado,
      'saldo': saldo,
      'estado': estado.value,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

/// Fila de la vista `estado_cuenta_fiados`: la deuda de una persona
/// sumada sobre todas sus ventas fiadas.
class CuentaFiado {
  const CuentaFiado({
    required this.deudorClave,
    required this.deudorNombre,
    required this.numVentas,
    required this.totalFiado,
    required this.totalPagado,
    required this.deudaPendiente,
    this.deudorTelefono,
    this.ultimaVenta,
  });

  /// Nombre normalizado (minúsculas, sin espacios sobrantes). Es la clave
  /// que agrupa las ventas de una misma persona.
  final String deudorClave;
  final String deudorNombre;
  final String? deudorTelefono;
  final int numVentas;
  final num totalFiado;
  final num totalPagado;
  final num deudaPendiente;
  final DateTime? ultimaVenta;

  bool get tieneDeuda => deudaPendiente > 0;

  factory CuentaFiado.fromJson(Map<String, dynamic> json) {
    return CuentaFiado(
      deudorClave: json['deudor_clave'] as String? ?? '',
      deudorNombre: json['deudor_nombre'] as String? ?? '',
      deudorTelefono: json['deudor_telefono'] as String?,
      numVentas: parseInt(json['num_ventas']),
      totalFiado: parseNum(json['total_fiado']),
      totalPagado: parseNum(json['total_pagado']),
      deudaPendiente: parseNum(json['deuda_pendiente']),
      ultimaVenta: parseDateTime(json['ultima_venta']),
    );
  }
}
