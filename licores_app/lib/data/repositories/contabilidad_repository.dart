import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/model_helpers.dart';
import '../models/producto.dart';
import '../models/utilidad_producto.dart';

import 'supabase_providers.dart';

final contabilidadRepositoryProvider = Provider<ContabilidadRepository>((ref) {
  return ContabilidadRepository(ref.watch(supabaseClientProvider));
});

class ContabilidadRepository {
  const ContabilidadRepository(this._client);

  final SupabaseClient _client;

  /// Límite superior exclusivo para rangos por timestamptz: el inicio
  /// del día siguiente a [end], para no perder el último segundo del día.
  static DateTime _finExclusivo(DateTime end) {
    return DateTime(end.year, end.month, end.day).add(const Duration(days: 1));
  }

  /// Efectivo que debería haber en caja, calculado en la base de datos:
  /// conteo físico registrado en capital_negocio.fecha_corte más/menos
  /// todos los flujos de efectivo posteriores.
  Future<num> getEfectivoReal() async {
    final result = await _client.rpc('calcular_efectivo_real');
    return (result as num?) ?? 0;
  }

  Future<Map<String, dynamic>> getResumenDia(DateTime fecha) async {
    final start = DateTime(fecha.year, fecha.month, fecha.day);
    final end = start.add(const Duration(days: 1));

    final rows = await _client
        .from('ventas')
        .select('tipo,total')
        .eq('estado', 'completada')
        .gte('fecha', start.toUtc().toIso8601String())
        .lt('fecha', end.toUtc().toIso8601String());

    num totalVentas = 0;
    num ventasPublico = 0;
    num ventasMayorista = 0;

    for (final row in rows) {
      final total = row['total'] as num? ?? 0;
      totalVentas += total;

      if (row['tipo'] == 'mayorista') {
        ventasMayorista += total;
      } else {
        ventasPublico += total;
      }
    }

    return {
      'dia': start.toIso8601String(),
      'num_ventas': rows.length,
      'total_ventas': totalVentas,
      'ventas_publico': ventasPublico,
      'ventas_mayorista': ventasMayorista,
    };
  }

  Future<List<Map<String, dynamic>>> getProductosMasVendidos({
    int limit = 10,
  }) async {
    final rows = await _client
        .from('productos_mas_vendidos')
        .select()
        .limit(limit);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> getEstadoCuentaMayoristas() async {
    final rows = await _client.from('estado_cuenta_mayoristas').select();
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> getResumenVentasUltimos7Dias() async {
    final rows = await _client
        .from('resumen_ventas_dia')
        .select()
        .limit(7);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<num> getTotalGastosRango(
    DateTime start,
    DateTime end, {
    String? metodoPago,
  }) async {
    var query = _client
        .from('gastos')
        .select('monto')
        .eq('anulado', false)
        .gte('fecha', dateOnly(start)!)
        .lte('fecha', dateOnly(end)!);
    if (metodoPago != null) {
      query = query.eq('metodo_pago', metodoPago);
    }
    final rows = await query;
    return rows.fold<num>(0, (sum, row) => sum + ((row['monto'] as num?) ?? 0));
  }

  Future<num> getTotalVentasRango(DateTime start, DateTime end) async {
    final rows = await _client
        .from('ventas')
        .select('total')
        .eq('estado', 'completada')
        .gte('fecha', start.toUtc().toIso8601String())
        .lt('fecha', _finExclusivo(end).toUtc().toIso8601String());
    return rows.fold<num>(0, (sum, row) => sum + ((row['total'] as num?) ?? 0));
  }

  Future<num> getTotalComprasEfectivoRango(DateTime start, DateTime end) async {
    final rows = await _client
        .from('compras_inventario')
        .select('total')
        .eq('anulado', false)
        .eq('metodo_pago', 'efectivo')
        .gte('fecha', dateOnly(start)!)
        .lte('fecha', dateOnly(end)!);
    return rows.fold<num>(0, (sum, row) => sum + parseNum(row['total']));
  }

  Future<num> getCogsRango(DateTime start, DateTime end) async {
    final result = await _client.rpc(
      'cogs_rango',
      params: {
        'p_start': start.toUtc().toIso8601String(),
        'p_end': end.toUtc().toIso8601String(),
      },
    );
    return (result as num?) ?? 0;
  }

  /// Utilidad de cada [productos] en el rango, a partir de las líneas de venta.
  ///
  /// El desglose por producto no existe en SQL (`cogs_rango` solo devuelve el
  /// costo total), así que se traen las líneas de los productos pedidos y se
  /// agrupan en Dart. Son pocos productos y rangos cortos, de modo que el
  /// volumen de filas es pequeño.
  Future<List<UtilidadProducto>> getUtilidadPorProductoRango(
    DateTime start,
    DateTime end,
    List<Producto> productos,
  ) async {
    if (productos.isEmpty) return [];

    final rows = await _client
        .from('detalle_ventas')
        .select('''
          producto_id,
          cantidad,
          precio_unitario,
          costo_unitario_historico,
          ventas!inner ( fecha, estado )
        ''')
        .inFilter('producto_id', productos.map((p) => p.id).toList())
        .eq('ventas.estado', 'completada')
        .gte('ventas.fecha', start.toUtc().toIso8601String())
        .lt('ventas.fecha', _finExclusivo(end).toUtc().toIso8601String());

    return agruparUtilidadPorProducto(
      productos,
      rows.map((row) => Map<String, dynamic>.from(row)).toList(),
    );
  }

  Future<List<Map<String, dynamic>>> getVentasPorDia(DateTime fecha) {
    return getVentasRango(fecha, fecha);
  }

  /// Ventas completadas entre [start] y [end], ambos días incluidos.
  Future<List<Map<String, dynamic>>> getVentasRango(
    DateTime start,
    DateTime end,
  ) async {
    final desde = DateTime(start.year, start.month, start.day);

    final rows = await _client
        .from('ventas')
        .select('''
          id,
          fecha,
          subtotal,
          descuento,
          total,
          metodo_pago,
          tipo,
          estado,
          cliente_id,
          notas,
          clientes_mayoristas (
            nombre
          )
        ''')
        .eq('estado', 'completada')
        .gte('fecha', desde.toUtc().toIso8601String())
        .lt('fecha', _finExclusivo(end).toUtc().toIso8601String())
        .order('fecha', ascending: false);

    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  /// Líneas de una venta puntual, con el nombre del producto.
  Future<List<Map<String, dynamic>>> getItemsDeVenta(String ventaId) async {
    final rows = await _client
        .from('detalle_ventas')
        .select('''
          cantidad,
          precio_unitario,
          subtotal,
          productos (
            nombre
          )
        ''')
        .eq('venta_id', ventaId)
        .order('created_at');

    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> eliminarVenta(String id, {String? motivo}) async {
    await _client.rpc('anular_venta', params: {
      'p_venta_id': id,
      'p_motivo': motivo,
    });
  }

  Future<Map<String, num>> getVentasPorMetodoPagoRango(DateTime start, DateTime end) async {
    final rows = await _client
        .from('ventas')
        .select('metodo_pago, total, tipo')
        .eq('estado', 'completada')
        .gte('fecha', start.toUtc().toIso8601String())
        .lt('fecha', _finExclusivo(end).toUtc().toIso8601String());

    num efectivo = 0;
    num transferencias = 0;
    num efectivoPublico = 0;
    num transferenciasPublico = 0;
    // Desglose de transferencias al público por destino.
    num nequiPublico = 0;
    num bancolombiaPublico = 0;
    // Ventas fiadas: mercancía entregada sin recibir plata todavía.
    num fiadoPublico = 0;

    for (final row in rows) {
      final total = row['total'] as num? ?? 0;
      final metodo = row['metodo_pago'] as String? ?? '';
      final tipo = row['tipo'] as String? ?? '';

      if (metodo == 'efectivo') {
        efectivo += total;
        if (tipo == 'publico') {
          efectivoPublico += total;
        }
      } else if (metodo == 'credito' && tipo == 'publico') {
        // Fiado: no es dinero recibido, así que no entra ni a efectivo ni
        // a transferencias. Entra a caja cuando la persona abona.
        // (El crédito mayorista se deja como estaba para no alterar las
        // métricas que ya dependen de ese conteo.)
        fiadoPublico += total;
      } else {
        transferencias += total;
        if (tipo == 'publico') {
          transferenciasPublico += total;
          if (metodo == 'nequi') {
            nequiPublico += total;
          } else if (metodo == 'transferencia') {
            bancolombiaPublico += total;
          }
        }
      }
    }

    return {
      'efectivo': efectivo,
      'transferencias': transferencias,
      'efectivo_publico': efectivoPublico,
      'transferencias_publico': transferenciasPublico,
      'nequi_publico': nequiPublico,
      'bancolombia_publico': bancolombiaPublico,
      'fiado_publico': fiadoPublico,
    };
  }

  /// Abonos de fiados al público en el rango, separados por método. El
  /// dinero de un fiado entra a caja aquí, no en la venta.
  Future<Map<String, num>> getAbonosFiadosPorMetodoPagoRango(
    DateTime start,
    DateTime end,
  ) async {
    final rows = await _client
        .from('abonos_fiados')
        .select('metodo_pago, monto')
        .eq('anulado', false)
        .gte('fecha', start.toUtc().toIso8601String())
        .lt('fecha', _finExclusivo(end).toUtc().toIso8601String());

    num efectivo = 0;
    num transferencias = 0;

    for (final row in rows) {
      final monto = row['monto'] as num? ?? 0;
      final metodo = row['metodo_pago'] as String? ?? '';
      if (metodo == 'efectivo') {
        efectivo += monto;
      } else {
        transferencias += monto;
      }
    }

    return {'efectivo': efectivo, 'transferencias': transferencias};
  }

  /// Deuda total pendiente de fiados al público.
  Future<num> getTotalFiadosPendiente() async {
    final rows = await _client
        .from('estado_cuenta_fiados')
        .select('deuda_pendiente');
    return rows.fold<num>(0, (sum, row) => sum + parseNum(row['deuda_pendiente']));
  }

  Future<Map<String, num>> getAbonosPorMetodoPagoRango(DateTime start, DateTime end) async {
    final rows = await _client
        .from('pagos_mayoristas')
        .select('metodo_pago, monto')
        .eq('anulado', false)
        .gte('fecha', start.toUtc().toIso8601String())
        .lt('fecha', _finExclusivo(end).toUtc().toIso8601String());

    num efectivo = 0;
    num transferencias = 0;
    num nequi = 0;
    num bancolombia = 0;

    for (final row in rows) {
      final monto = row['monto'] as num? ?? 0;
      final metodo = row['metodo_pago'] as String? ?? '';

      if (metodo == 'efectivo') {
        efectivo += monto;
      } else {
        transferencias += monto;
        if (metodo == 'nequi') {
          nequi += monto;
        } else if (metodo == 'transferencia') {
          bancolombia += monto;
        }
      }
    }

    return {
      'efectivo': efectivo,
      'transferencias': transferencias,
      'nequi': nequi,
      'bancolombia': bancolombia,
    };
  }

  Future<num> getDeudaTotalCompras() async {
    final rows = await _client
        .from('compras_inventario')
        .select('valor_deuda')
        .eq('anulado', false)
        .eq('metodo_pago', 'credito');

    return rows.fold<num>(0, (sum, row) => sum + parseNum(row['valor_deuda']));
  }
}

