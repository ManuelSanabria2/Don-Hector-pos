import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cliente_mayorista.dart';
import '../models/cobro_mayorista.dart';
import '../models/pago_mayorista.dart';
import '../models/venta_enums.dart';
import 'supabase_providers.dart';

final mayoristasRepositoryProvider = Provider<MayoristasRepository>((ref) {
  return MayoristasRepository(ref.watch(supabaseClientProvider));
});

class MayoristasRepository {
  const MayoristasRepository(this._client);

  final SupabaseClient _client;

  Future<List<ClienteMayorista>> getClientes() async {
    final rows = await _client
        .from('clientes_mayoristas')
        .select()
        .eq('activo', true)
        .order('nombre');
    return rows.map(ClienteMayorista.fromJson).toList();
  }

  Future<void> upsertCliente(ClienteMayorista c) async {
    final values = _withoutNulls(c.toJson());
    if ((values['id'] as String?)?.isEmpty ?? false) {
      values.remove('id');
    }

    await _client.from('clientes_mayoristas').upsert(values);
  }

  Future<List<CobroMayorista>> getCobrosCliente(String clienteId) async {
    final rows = await _client
        .from('cobros_mayoristas')
        .select()
        .eq('cliente_id', clienteId)
        .order('created_at', ascending: false);
    return rows.map(CobroMayorista.fromJson).toList();
  }

  Future<List<Map<String, dynamic>>> getVentasProductosCliente(String clienteId) async {
    final rows = await _client
        .from('detalle_ventas')
        .select('''
          venta_id,
          producto_id,
          cantidad,
          precio_unitario,
          productos (nombre, categoria_id),
          cobros_mayoristas (
            id,
            cliente_id,
            total_venta,
            total_pagado,
            saldo,
            estado,
            created_at,
            ventas (fecha, tipo, metodo_pago, estado)
          )
        ''')
        .eq('cobros_mayoristas.cliente_id', clienteId)
        .order('cobros_mayoristas.created_at', ascending: false);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> getEstadoCuentaMayoristas() async {
    final rows = await _client.from('estado_cuenta_mayoristas').select();
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> registrarPago(PagoMayorista pago) async {
    final values = _withoutNulls(pago.toJson());
    if ((values['id'] as String?)?.isEmpty ?? false) {
      values.remove('id');
    }

    await _client.from('pagos_mayoristas').insert(values);
  }

  Future<void> registrarPagoCliente({
    required String clienteId,
    required num monto,
    required MetodoPago metodoPago,
    String? notas,
  }) async {
    var restante = monto;
    final cobros = await getCobrosCliente(clienteId);
    final pendientes =
        cobros
            .where(
              (cobro) => cobro.estado != EstadoCobro.pagado && cobro.saldo > 0,
            )
            .toList()
          ..sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return aDate.compareTo(bDate);
          });

    for (final cobro in pendientes) {
      if (restante <= 0) break;

      final abono = restante > cobro.saldo ? cobro.saldo : restante;
      await registrarPago(
        PagoMayorista(
          id: '',
          cobroId: cobro.id,
          monto: abono,
          metodoPago: metodoPago,
          notas: notas,
        ),
      );
      restante -= abono;
    }
  }
}

Map<String, dynamic> _withoutNulls(Map<String, dynamic> values) {
  return Map.fromEntries(values.entries.where((entry) => entry.value != null));
}
