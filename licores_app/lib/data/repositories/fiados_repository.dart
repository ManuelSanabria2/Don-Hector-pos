import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/abono_fiado.dart';
import '../models/fiado_publico.dart';
import '../models/venta_enums.dart';
import 'supabase_providers.dart';

final fiadosRepositoryProvider = Provider<FiadosRepository>((ref) {
  return FiadosRepository(ref.watch(supabaseClientProvider));
});

class FiadosRepository {
  const FiadosRepository(this._client);

  final SupabaseClient _client;

  /// Deuda de cada persona, sumada sobre todas sus ventas fiadas.
  Future<List<CuentaFiado>> getEstadoCuentaFiados() async {
    final rows = await _client.from('estado_cuenta_fiados').select();
    return rows.map(CuentaFiado.fromJson).toList();
  }

  /// Ventas fiadas de una persona. [deudorNombre] se normaliza igual que
  /// en la base (minúsculas, sin espacios sobrantes) para que "Juan" y
  /// "  juan  " caigan en la misma cuenta.
  Future<List<FiadoPublico>> getFiadosDeDeudor(String deudorNombre) async {
    final clave = deudorNombre.trim().toLowerCase();
    final rows = await _client
        .from('fiados_publico')
        .select()
        .eq('anulado', false)
        .order('created_at', ascending: false);

    return rows
        .map(FiadoPublico.fromJson)
        .where((f) => f.deudorNombre.trim().toLowerCase() == clave)
        .toList();
  }

  Future<List<AbonoFiado>> getAbonosDeFiado(String fiadoId) async {
    final rows = await _client
        .from('abonos_fiados')
        .select()
        .eq('fiado_id', fiadoId)
        .eq('anulado', false)
        .order('fecha', ascending: false);
    return rows.map(AbonoFiado.fromJson).toList();
  }

  /// Abona a la deuda de una persona. El reparto entre sus ventas
  /// pendientes (de la más antigua a la más nueva) lo hace la base en una
  /// sola transacción, y rechaza montos que superen la deuda total.
  Future<void> registrarAbono({
    required String deudorNombre,
    required num monto,
    MetodoPago metodoPago = MetodoPago.efectivo,
    String? notas,
  }) async {
    await _client.rpc('registrar_abono_fiado', params: {
      'p_deudor_nombre': deudorNombre,
      'p_monto': monto,
      'p_metodo_pago': metodoPago.value,
      'p_notas': notas,
    });
  }
}
