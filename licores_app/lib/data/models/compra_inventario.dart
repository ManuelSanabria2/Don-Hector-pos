import 'detalle_compra.dart';
import 'model_helpers.dart';

class CompraInventario {
  const CompraInventario({
    required this.id,
    this.proveedorId,
    this.nombreProveedor,
    required this.fecha,
    required this.total,
    required this.metodoPago,
    this.notas,
    required this.anulado,
    this.createdAt,
    this.lineas = const [],
    this.ajuste = 0,
    this.valorDeuda = 0,
  });

  final String id;
  final String? proveedorId;
  final String? nombreProveedor;
  final DateTime fecha;
  final num total;
  final String metodoPago;
  final String? notas;
  final bool anulado;
  final DateTime? createdAt;
  final List<DetalleCompra> lineas;
  final num ajuste;
  final num valorDeuda;

  factory CompraInventario.fromJson(Map<String, dynamic> json) {
    String? provName;
    if (json['proveedores'] != null && json['proveedores'] is Map) {
      provName = json['proveedores']['nombre'] as String?;
    } else {
      provName = json['nombre_proveedor'] as String?;
    }

    final rawLineas = json['lineas'] as List<dynamic>?;
    final List<DetalleCompra> parsedLineas = rawLineas != null
        ? rawLineas.map((item) => DetalleCompra.fromJson(item as Map<String, dynamic>)).toList()
        : const [];

    return CompraInventario(
      id: json['id'] as String? ?? '',
      proveedorId: json['proveedor_id'] as String?,
      nombreProveedor: provName,
      fecha: parseRequiredDate(json['fecha']),
      total: parseNum(json['total']),
      metodoPago: json['metodo_pago'] as String? ?? 'efectivo',
      notas: json['notas'] as String?,
      anulado: json['anulado'] as bool? ?? false,
      createdAt: parseDateTime(json['created_at']),
      lineas: parsedLineas,
      ajuste: parseNum(json['ajuste']),
      valorDeuda: parseNum(json['valor_deuda']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'proveedor_id': proveedorId,
      if (nombreProveedor != null) 'nombre_proveedor': nombreProveedor,
      'fecha': dateOnly(fecha),
      'total': total,
      'metodo_pago': metodoPago,
      'notas': notas,
      'anulado': anulado,
      'created_at': createdAt?.toIso8601String(),
      'lineas': lineas.map((l) => l.toJson()).toList(),
      'ajuste': ajuste,
      'valor_deuda': valorDeuda,
    };
  }
}
