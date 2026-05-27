import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/carrito_item.dart';
import '../models/venta_enums.dart';
import 'supabase_providers.dart';

final posRepositoryProvider = Provider<PosRepository>((ref) {
  return PosRepository(ref.watch(supabaseClientProvider));
});

class PosRepository {
  const PosRepository(this._client);

  final SupabaseClient _client;

  Future<String> registrarVenta({
    required TipoVenta tipo,
    required MetodoPago metodoPago,
    required List<CarritoItem> items,
    String? clienteId,
    num descuento = 0,
    String? notas,
  }) async {
    final result = await _client.rpc(
      'registrar_venta',
      params: {
        'p_tipo': tipo.value,
        'p_cliente_id': clienteId,
        'p_metodo_pago': metodoPago.value,
        'p_descuento': descuento,
        'p_notas': notas,
        'p_items': items.map((item) => item.toJson()).toList(),
      },
    );

    return result as String;
  }
}
