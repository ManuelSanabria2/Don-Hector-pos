import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/categoria.dart';
import '../models/producto.dart';
import 'supabase_providers.dart';

final inventarioRepositoryProvider = Provider<InventarioRepository>((ref) {
  return InventarioRepository(ref.watch(supabaseClientProvider));
});

class InventarioRepository {
  const InventarioRepository(this._client);

  final SupabaseClient _client;

  Future<List<Categoria>> listarCategorias() async {
    final rows = await _client.from('categorias').select().order('nombre');
    return rows.map(Categoria.fromJson).toList();
  }

  Future<List<Producto>> getProductos({
    String? busqueda,
    String? categoriaId,
  }) async {
    var query = _client.from('productos').select().eq('activo', true);

    final trimmedSearch = busqueda?.trim();
    if (trimmedSearch != null && trimmedSearch.isNotEmpty) {
      query = query.ilike('nombre', '%$trimmedSearch%');
    }

    if (categoriaId != null && categoriaId.isNotEmpty) {
      query = query.eq('categoria_id', categoriaId);
    }

    final rows = await query.order('nombre');
    return rows.map(Producto.fromJson).toList();
  }

  Future<Producto?> getProductoPorBarcode(String codigo) async {
    final row = await _client
        .from('productos')
        .select()
        .eq('codigo_barras', codigo)
        .maybeSingle();

    return row == null ? null : Producto.fromJson(row);
  }

  Future<void> upsertProducto(Producto p) async {
    final values = _withoutNulls(p.toJson());
    if ((values['id'] as String?)?.isEmpty ?? false) {
      values.remove('id');
    }

    await _client.from('productos').upsert(values);
  }

  Future<void> toggleActivo(String id, bool activo) async {
    await _client.from('productos').update({'activo': activo}).eq('id', id);
  }

  Stream<List<Producto>> watchStockBajo() {
    return _client
        .from('productos')
        .stream(primaryKey: ['id'])
        .eq('activo', true)
        .order('nombre')
        .map(
          (rows) => rows
              .map(Producto.fromJson)
              .where((producto) => producto.stockBajo)
              .toList(),
        );
  }
}

Map<String, dynamic> _withoutNulls(Map<String, dynamic> values) {
  return Map.fromEntries(values.entries.where((entry) => entry.value != null));
}
