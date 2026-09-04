import 'model_helpers.dart';

/// Un movimiento del saldo a favor ("rebate") que un proveedor otorga por
/// cumplir metas de compra. Ese saldo no es plata: solo se canjea en
/// mercancía del mismo proveedor.
///
/// El signo lo pone [tipo], no el monto: [monto] siempre es positivo.
class RebateProveedor {
  const RebateProveedor({
    required this.id,
    required this.proveedorId,
    this.nombreProveedor,
    required this.fecha,
    required this.tipo,
    required this.monto,
    this.compraId,
    this.notas,
    this.anulado = false,
    this.createdAt,
  });

  /// El proveedor reconoce la bonificación.
  static const String tipoAcumulacion = 'acumulacion';

  /// Corrección a favor del negocio.
  static const String tipoAjuste = 'ajuste';

  /// Se consumió comprando mercancía.
  static const String tipoCanje = 'canje';

  /// El proveedor lo caducó sin usarse.
  static const String tipoVencimiento = 'vencimiento';

  final String id;
  final String proveedorId;
  final String? nombreProveedor;
  final DateTime fecha;
  final String tipo;
  final num monto;
  final String? compraId;
  final String? notas;
  final bool anulado;
  final DateTime? createdAt;

  /// Cuánto mueve el saldo: positivo si lo suma, negativo si lo consume.
  num get montoConSigno =>
      tipo == tipoCanje || tipo == tipoVencimiento ? -monto : monto;

  String get tipoLegible {
    switch (tipo) {
      case tipoAcumulacion:
        return 'Acumulación';
      case tipoAjuste:
        return 'Ajuste';
      case tipoCanje:
        return 'Canje';
      case tipoVencimiento:
        return 'Vencimiento';
      default:
        return tipo;
    }
  }

  factory RebateProveedor.fromJson(Map<String, dynamic> json) {
    String? provName;
    final prov = json['proveedores'];
    if (prov is Map) {
      provName = prov['nombre'] as String?;
    } else {
      provName = json['nombre_proveedor'] as String?;
    }

    return RebateProveedor(
      id: json['id'] as String? ?? '',
      proveedorId: json['proveedor_id'] as String? ?? '',
      nombreProveedor: provName,
      fecha: parseRequiredDate(json['fecha']),
      tipo: json['tipo'] as String? ?? tipoAcumulacion,
      monto: parseNum(json['monto']),
      compraId: json['compra_id'] as String?,
      notas: json['notas'] as String?,
      anulado: json['anulado'] as bool? ?? false,
      createdAt: parseDateTime(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'proveedor_id': proveedorId,
      'fecha': dateOnly(fecha),
      'tipo': tipo,
      'monto': monto,
      'compra_id': compraId,
      'notas': notas,
      'anulado': anulado,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}

/// Fila de la vista `saldos_rebates_proveedor`: el saldo vivo de un
/// proveedor y de qué se compone.
class SaldoRebateProveedor {
  const SaldoRebateProveedor({
    required this.proveedorId,
    required this.proveedor,
    required this.acumulado,
    required this.ajustado,
    required this.canjeado,
    required this.vencido,
    required this.saldo,
  });

  final String proveedorId;
  final String proveedor;
  final num acumulado;
  final num ajustado;
  final num canjeado;
  final num vencido;
  final num saldo;

  bool get tieneSaldo => saldo > 0;

  factory SaldoRebateProveedor.fromJson(Map<String, dynamic> json) {
    return SaldoRebateProveedor(
      proveedorId: json['proveedor_id'] as String? ?? '',
      proveedor: json['proveedor'] as String? ?? 'Sin nombre',
      acumulado: parseNum(json['acumulado']),
      ajustado: parseNum(json['ajustado']),
      canjeado: parseNum(json['canjeado']),
      vencido: parseNum(json['vencido']),
      saldo: parseNum(json['saldo']),
    );
  }
}
