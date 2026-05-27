import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/categoria_gasto.dart';
import '../models/gasto.dart';
import 'supabase_providers.dart';

final gastosRepositoryProvider = Provider<GastosRepository>((ref) {
  return GastosRepository(ref.watch(supabaseClientProvider));
});

class GastosRepository {
  const GastosRepository(this._client);

  final SupabaseClient _client;

  Future<List<CategoriaGasto>> listarCategorias() async {
    final rows = await _client
        .from('categorias_gasto')
        .select()
        .order('nombre');
    return rows.map(CategoriaGasto.fromJson).toList();
  }

  Future<List<Gasto>> getGastos({DateTime? desde, DateTime? hasta}) async {
    var query = _client.from('gastos').select();

    if (desde != null) {
      query = query.gte('fecha', _dateOnly(desde));
    }

    if (hasta != null) {
      query = query.lte('fecha', _dateOnly(hasta));
    }

    final rows = await query.order('fecha', ascending: false);
    return rows.map(Gasto.fromJson).toList();
  }

  Future<void> upsertGasto(Gasto g) async {
    final map = _withoutNulls(g.toJson());
    if (map['id'] == '') map.remove('id');
    await _client.from('gastos').upsert(map);
  }

  Future<void> deleteGasto(String id) async {
    await _client.from('gastos').delete().eq('id', id);
  }
}

String _dateOnly(DateTime value) {
  return value.toIso8601String().split('T').first;
}

Map<String, dynamic> _withoutNulls(Map<String, dynamic> values) {
  return Map.fromEntries(values.entries.where((entry) => entry.value != null));
}
