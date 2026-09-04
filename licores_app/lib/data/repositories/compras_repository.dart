import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../models/proveedor.dart';
import '../models/compra_inventario.dart';
import '../models/detalle_compra.dart';
import '../models/model_helpers.dart';
import '../models/rebate_proveedor.dart';
import 'supabase_providers.dart';

final comprasRepositoryProvider = Provider<ComprasRepository>((ref) {
  return ComprasRepository(ref.watch(supabaseClientProvider));
});

class ComprasRepository {
  const ComprasRepository(this._client);

  final SupabaseClient _client;

  Future<List<Proveedor>> getProveedores() async {
    final rows = await _client
        .from('proveedores')
        .select()
        .eq('activo', true)
        .order('nombre');
    return rows.map(Proveedor.fromJson).toList();
  }

  Future<void> upsertProveedor(Proveedor p) async {
    final map = _withoutNulls(p.toJson());
    if (map['id'] == '') map.remove('id');
    await _client.from('proveedores').upsert(map);
  }

  Future<void> desactivarProveedor(String id) async {
    await _client.from('proveedores').update({'activo': false}).eq('id', id);
  }

  Future<List<CompraInventario>> getCompras({
    DateTime? desde,
    DateTime? hasta,
    bool incluirAnuladas = false,
  }) async {
    var query = _client.from('compras_inventario').select('*, proveedores(nombre)');

    if (!incluirAnuladas) {
      query = query.eq('anulado', false);
    }

    if (desde != null) {
      query = query.gte('fecha', dateOnly(desde)!);
    }

    if (hasta != null) {
      query = query.lte('fecha', dateOnly(hasta)!);
    }

    final rows = await query.order('fecha', ascending: false);
    return rows.map(CompraInventario.fromJson).toList();
  }

  Future<CompraInventario> getCompraConDetalle(String compraId) async {
    final row = await _client
        .from('compras_inventario')
        .select('*, proveedores(nombre), lineas:detalle_compras(*, productos(nombre))')
        .eq('id', compraId)
        .single();
    return CompraInventario.fromJson(row);
  }

  Future<String> registrarCompra({
    String? proveedorId,
    required DateTime fecha,
    required String metodoPago,
    String? notas,
    required List<DetalleCompra> lineas,
    num ajuste = 0,
    num valorDeuda = 0,
    String metodoPagoContado = 'efectivo',
  }) async {
    final result = await _client.rpc(
      'registrar_compra',
      params: {
        'p_proveedor_id': proveedorId,
        'p_fecha': dateOnly(fecha),
        'p_metodo_pago': metodoPago,
        'p_notas': notas,
        'p_items': lineas.map((l) => {
          'producto_id': l.productoId,
          'cantidad': l.cantidad,
          'costo_unitario': l.costoUnitario,
        }).toList(),
        'p_ajuste': ajuste,
        'p_valor_deuda': valorDeuda,
        'p_metodo_pago_contado': metodoPagoContado,
      },
    );

    return result as String;
  }

  Future<void> anularCompra(String compraId, {String? motivo}) async {
    await _client.rpc(
      'anular_compra',
      params: {
        'p_compra_id': compraId,
        'p_motivo': motivo,
      },
    );
  }

  Future<num> getTotalComprasRango(DateTime desde, DateTime hasta) async {
    final rows = await _client
        .from('compras_inventario')
        .select('total')
        .eq('anulado', false)
        .gte('fecha', dateOnly(desde)!)
        .lte('fecha', dateOnly(hasta)!);

    final sum = rows.fold<num>(0, (prev, element) => prev + parseNum(element['total']));
    return sum;
  }

  /// Registra un pago (total o parcial) de la deuda de una compra a
  /// crédito. El trigger de pagos_compras descuenta el monto de
  /// compras_inventario.valor_deuda.
  Future<void> registrarPagoCompra({
    required String compraId,
    required num monto,
    required String metodoPago,
    String? notas,
  }) async {
    final timestamp = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await _client.from('pagos_compras').insert({
      'compra_id': compraId,
      'monto': monto,
      'metodo_pago': metodoPago,
      'notas': notas ?? 'Pago registrado el $timestamp',
    });
  }

  // ==========================================================
  // REBATES DE PROVEEDOR
  //
  // El saldo a favor no se guarda en un campo: se deriva de los
  // movimientos, igual que los cobros de mayoristas. El canje NO se
  // registra por aquí — lo inserta registrar_compra cuando la compra
  // va con metodo_pago 'rebate', para que descontar el saldo y meter
  // la mercancía sean la misma transacción.
  // ==========================================================

  /// Saldo de rebate de cada proveedor activo, con el detalle de cómo
  /// se compone.
  Future<List<SaldoRebateProveedor>> getSaldosRebates() async {
    final rows = await _client
        .from('saldos_rebates_proveedor')
        .select()
        .order('saldo', ascending: false);
    return rows.map(SaldoRebateProveedor.fromJson).toList();
  }

  /// Saldo disponible de un solo proveedor, para validar un canje
  /// antes de intentarlo.
  Future<num> getSaldoRebate(String proveedorId) async {
    final saldo = await _client.rpc(
      'saldo_rebate_proveedor',
      params: {'p_proveedor_id': proveedorId},
    );
    return parseNum(saldo);
  }

  /// Movimientos del saldo, del más reciente al más viejo. Sin
  /// [proveedorId] trae los de todos los proveedores.
  Future<List<RebateProveedor>> getMovimientosRebate({
    String? proveedorId,
    bool incluirAnulados = false,
  }) async {
    var query =
        _client.from('rebates_proveedor').select('*, proveedores(nombre)');

    if (proveedorId != null) {
      query = query.eq('proveedor_id', proveedorId);
    }

    if (!incluirAnulados) {
      query = query.eq('anulado', false);
    }

    final rows = await query
        .order('fecha', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(RebateProveedor.fromJson).toList();
  }

  /// Registra que el proveedor reconoció una bonificación (o una
  /// corrección, o que la caducó). El canje va por registrarCompra.
  Future<void> registrarMovimientoRebate({
    required String proveedorId,
    required num monto,
    required String tipo,
    DateTime? fecha,
    String? notas,
  }) async {
    await _client.from('rebates_proveedor').insert({
      'proveedor_id': proveedorId,
      'monto': monto,
      'tipo': tipo,
      'fecha': dateOnly(fecha ?? DateTime.now()),
      'notas': notas,
    });
  }

  /// Corrige una compra que se registró como pagada con plata cuando en
  /// realidad se canjeó con el saldo de rebate del proveedor.
  ///
  /// Es la salida para cuando anular y volver a registrar no se puede
  /// porque la mercancía ya se vendió y el stock no alcanza para
  /// revertirla. Solo cambia el origen de fondos: no toca stock,
  /// costos ni el detalle de la compra.
  ///
  /// Devuelve el saldo de rebate que le queda al proveedor.
  Future<num> convertirCompraARebate(String compraId, {String? notas}) async {
    final saldo = await _client.rpc(
      'convertir_compra_a_rebate',
      params: {
        'p_compra_id': compraId,
        'p_notas': notas,
      },
    );
    return parseNum(saldo);
  }

  /// Anulación lógica, como el resto del proyecto: el movimiento se
  /// marca y el saldo se recalcula sin él.
  Future<void> anularMovimientoRebate(String id) async {
    await _client
        .from('rebates_proveedor')
        .update({'anulado': true}).eq('id', id);
  }

  Future<num> getTotalPagosComprasRango(
    DateTime start,
    DateTime end, {
    String? metodoPago,
  }) async {
    final endExclusivo =
        DateTime(end.year, end.month, end.day).add(const Duration(days: 1));
    var query = _client
        .from('pagos_compras')
        .select('monto')
        .eq('anulado', false)
        .gte('fecha', start.toUtc().toIso8601String())
        .lt('fecha', endExclusivo.toUtc().toIso8601String());
    if (metodoPago != null) {
      query = query.eq('metodo_pago', metodoPago);
    }
    final rows = await query;
    return rows.fold<num>(0, (sum, row) => sum + parseNum(row['monto']));
  }
}

Map<String, dynamic> _withoutNulls(Map<String, dynamic> values) {
  return Map.fromEntries(values.entries.where((entry) => entry.value != null));
}
