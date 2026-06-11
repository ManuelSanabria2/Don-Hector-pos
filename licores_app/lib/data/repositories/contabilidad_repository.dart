import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_providers.dart';

final contabilidadRepositoryProvider = Provider<ContabilidadRepository>((ref) {
  return ContabilidadRepository(ref.watch(supabaseClientProvider));
});

class ContabilidadRepository {
  const ContabilidadRepository(this._client);

  final SupabaseClient _client;

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

  Future<num> getTotalGastosRango(DateTime start, DateTime end) async {
    final rows = await _client
        .from('gastos')
        .select('monto')
        .gte('fecha', start.toUtc().toIso8601String())
        .lte('fecha', end.toUtc().toIso8601String());
    return rows.fold<num>(0, (sum, row) => sum + ((row['monto'] as num?) ?? 0));
  }

  Future<num> getTotalVentasRango(DateTime start, DateTime end) async {
    final rows = await _client
        .from('ventas')
        .select('total')
        .eq('estado', 'completada')
        .gte('fecha', start.toUtc().toIso8601String())
        .lte('fecha', end.toUtc().toIso8601String());
    return rows.fold<num>(0, (sum, row) => sum + ((row['total'] as num?) ?? 0));
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

  Future<List<Map<String, dynamic>>> getVentasPorDia(DateTime fecha) async {
    final start = DateTime(fecha.year, fecha.month, fecha.day);
    final end = start.add(const Duration(days: 1));

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
          notas
        ''')
        .eq('estado', 'completada')
        .gte('fecha', start.toUtc().toIso8601String())
        .lt('fecha', end.toUtc().toIso8601String())
        .order('fecha', ascending: false);

    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> eliminarVenta(String id) async {
    await _client.rpc('eliminar_venta', params: {'p_venta_id': id});
  }
}

