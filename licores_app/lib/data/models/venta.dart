import 'model_helpers.dart';
import 'venta_enums.dart';

class Venta {
  const Venta({
    required this.id,
    required this.tipo,
    required this.subtotal,
    required this.descuento,
    required this.total,
    required this.metodoPago,
    required this.estado,
    this.clienteId,
    this.fecha,
    this.notas,
    this.createdAt,
  });

  final String id;
  final TipoVenta tipo;
  final String? clienteId;
  final DateTime? fecha;
  final num subtotal;
  final num descuento;
  final num total;
  final MetodoPago metodoPago;
  final EstadoVenta estado;
  final String? notas;
  final DateTime? createdAt;

  factory Venta.fromJson(Map<String, dynamic> json) {
    return Venta(
      id: json['id'] as String,
      tipo: TipoVenta.fromJson(json['tipo']),
      clienteId: json['cliente_id'] as String?,
      fecha: parseDateTime(json['fecha']),
      subtotal: parseNum(json['subtotal']),
      descuento: parseNum(json['descuento']),
      total: parseNum(json['total']),
      metodoPago: MetodoPago.fromJson(json['metodo_pago']),
      estado: EstadoVenta.fromJson(json['estado']),
      notas: json['notas'] as String?,
      createdAt: parseDateTime(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tipo': tipo.value,
      'cliente_id': clienteId,
      'fecha': fecha?.toIso8601String(),
      'subtotal': subtotal,
      'descuento': descuento,
      'total': total,
      'metodo_pago': metodoPago.value,
      'estado': estado.value,
      'notas': notas,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
