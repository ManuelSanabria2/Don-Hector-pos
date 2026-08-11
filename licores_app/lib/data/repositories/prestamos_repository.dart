import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/model_helpers.dart';
import '../models/pago_prestamo.dart';
import '../models/prestamo.dart';
import '../models/venta_enums.dart';
import 'supabase_providers.dart';

final prestamosRepositoryProvider = Provider<PrestamosRepository>((ref) {
  return PrestamosRepository(ref.watch(supabaseClientProvider));
});

class PrestamosRepository {
  const PrestamosRepository(this._client);

  final SupabaseClient _client;

  /// Límite superior exclusivo para rangos por timestamptz.
  static DateTime _finExclusivo(DateTime end) {
    return DateTime(end.year, end.month, end.day).add(const Duration(days: 1));
  }

  Future<List<Prestamo>> getPrestamos() async {
    final rows = await _client
        .from('prestamos')
        .select()
        .eq('anulado', false)
        .order('fecha', ascending: false);
    return rows.map(Prestamo.fromJson).toList();
  }

  Future<List<PagoPrestamo>> getPagosDePrestamo(String prestamoId) async {
    final rows = await _client
        .from('pagos_prestamos')
        .select()
        .eq('prestamo_id', prestamoId)
        .eq('anulado', false)
        .order('fecha', ascending: false);
    return rows.map(PagoPrestamo.fromJson).toList();
  }

  Future<void> registrarPrestamo({
    required String acreedor,
    required TipoPrestamo tipo,
    required num monto,
    MetodoPago metodoPago = MetodoPago.efectivo,
    num? tasaInteres,
    String? notas,
  }) async {
    await _client.from('prestamos').insert({
      'acreedor': acreedor.trim(),
      'tipo': tipo.value,
      'monto': monto,
      'metodo_pago': metodoPago.value,
      'tasa_interes': tasaInteres,
      'notas': notas,
    });
  }

  /// Registra una cuota. Los triggers recalculan el saldo del préstamo y
  /// crean el gasto por la parte de interés.
  Future<void> registrarPago({
    required String prestamoId,
    required num abonoCapital,
    required num interes,
    MetodoPago metodoPago = MetodoPago.efectivo,
    String? notas,
  }) async {
    await _client.from('pagos_prestamos').insert({
      'prestamo_id': prestamoId,
      'abono_capital': abonoCapital,
      'interes': interes,
      'metodo_pago': metodoPago.value,
      'notas': notas,
    });
  }

  /// Anulación lógica de una cuota. El trigger devuelve el saldo y anula
  /// el gasto de interés asociado.
  Future<void> anularPago(String pagoId) async {
    await _client
        .from('pagos_prestamos')
        .update({'anulado': true}).eq('id', pagoId);
  }

  Future<void> anularPrestamo(String prestamoId) async {
    await _client
        .from('prestamos')
        .update({'anulado': true}).eq('id', prestamoId);
  }

  Future<num> getTotalPrestamosPendiente() async {
    final rows = await _client
        .from('prestamos')
        .select('saldo')
        .eq('anulado', false);
    return rows.fold<num>(0, (sum, row) => sum + parseNum(row['saldo']));
  }

  /// Movimientos de caja del rango: lo recibido en préstamos y lo abonado
  /// a capital, ambos solo en efectivo.
  ///
  /// El interés no va aquí: ya sale de la caja como gasto, y contarlo de
  /// nuevo lo restaría dos veces.
  Future<Map<String, num>> getMovimientosEfectivoRango(
    DateTime start,
    DateTime end,
  ) async {
    final desde = DateTime(start.year, start.month, start.day)
        .toUtc()
        .toIso8601String();
    final hasta = _finExclusivo(end).toUtc().toIso8601String();

    final recibidos = await _client
        .from('prestamos')
        .select('monto')
        .eq('anulado', false)
        .eq('metodo_pago', 'efectivo')
        .gte('fecha', desde)
        .lt('fecha', hasta);

    final abonos = await _client
        .from('pagos_prestamos')
        .select('abono_capital')
        .eq('anulado', false)
        .eq('metodo_pago', 'efectivo')
        .gte('fecha', desde)
        .lt('fecha', hasta);

    return {
      'recibido': recibidos.fold<num>(0, (s, r) => s + parseNum(r['monto'])),
      'abonado_capital':
          abonos.fold<num>(0, (s, r) => s + parseNum(r['abono_capital'])),
    };
  }
}
