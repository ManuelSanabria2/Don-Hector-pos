import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
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

  Future<String> upsertProducto(Producto p) async {
    final values = _withoutNulls(p.toJson());
    
    // El stock_actual se maneja exclusivamente a traves de la RPC ajustar_stock para mantener la auditoria
    values.remove('stock_actual');

    final isNew = (values['id'] as String?)?.isEmpty ?? true;
    
    if (isNew) {
      values.remove('id');
      final response = await _client
          .from('productos')
          .insert(values)
          .select('id')
          .single();
      return response['id'] as String;
    } else {
      final response = await _client
          .from('productos')
          .upsert(values)
          .select('id')
          .single();
      return response['id'] as String;
    }
  }

  Future<void> ajustarStock({
    required String productoId,
    required int cantidad,
    required String tipo,
    required String motivo,
  }) async {
    await _client.rpc('ajustar_stock', params: {
      'p_producto_id': productoId,
      'p_cantidad': cantidad,
      'p_tipo': tipo,
      'p_motivo': motivo,
    });
  }

  Future<void> toggleActivo(String id, bool activo) async {
    await _client.from('productos').update({'activo': activo}).eq('id', id);
  }

  Future<void> deleteProducto(String id) async {
    await _client.from('productos').delete().eq('id', id);
  }

  /// Los mas vendidos a MAYORISTAS dentro de un dia, para el acceso
  /// rapido en la pestana de venta. [dia] null = dia de hoy.
  ///
  /// El rango se calcula en hora local y se manda en UTC, como el
  /// resto de consultas por fecha del proyecto, para que "hoy" sea el
  /// dia del negocio y no el dia UTC.
  Future<List<Producto>> getProductosMasVendidosMayoristaDia({
    DateTime? dia,
    int limit = 10,
  }) async {
    final base = dia ?? DateTime.now();
    final desde = DateTime(base.year, base.month, base.day);
    final hasta = desde.add(const Duration(days: 1));

    final rows = await _client.rpc(
      'productos_mas_vendidos_mayorista_dia',
      params: {
        'p_desde': desde.toUtc().toIso8601String(),
        'p_hasta': hasta.toUtc().toIso8601String(),
        'p_limit': limit,
      },
    ) as List<dynamic>;

    return rows
        .map((row) => Producto.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<List<Producto>> getProductosTurbo() async {
    final rows = await _client
        .from('productos')
        .select()
        .eq('activo', true)
        .eq('en_turbo', true)
        .order('orden_turbo', ascending: true)
        .order('nombre', ascending: true);
    return rows.map(Producto.fromJson).toList();
  }

  Future<void> setProductoTurbo(String productoId, bool enTurbo) async {
    await _client.rpc('set_producto_turbo', params: {
      'p_producto_id': productoId,
      'p_en_turbo': enTurbo,
    });
  }

  Future<void> actualizarOrdenTurbo(List<String> idsEnOrden) async {
    await _client.rpc('actualizar_orden_turbo', params: {
      'p_ids': idsEnOrden,
    });
  }

  /// Comprime la imagen, la sube a Storage y actualiza productos.imagen_url.
  /// Devuelve la URL publica.
  Future<String> subirImagenProducto({
    required String productoId,
    required Uint8List bytes,
  }) async {
    final jpgBytes = await compute(_comprimirImagen, bytes);

    final urlAnterior = await _client
        .from('productos')
        .select('imagen_url')
        .eq('id', productoId)
        .maybeSingle();

    final path = '$productoId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from('productos').uploadBinary(
          path,
          jpgBytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );

    final url = _client.storage.from('productos').getPublicUrl(path);
    await _client.from('productos').update({'imagen_url': url}).eq('id', productoId);

    // Borrado best-effort del objeto anterior para no acumular huerfanos.
    final vieja = urlAnterior?['imagen_url'] as String?;
    const marcador = '/object/public/productos/';
    final idx = vieja?.indexOf(marcador) ?? -1;
    if (vieja != null && idx != -1) {
      final oldPath = Uri.decodeComponent(vieja.substring(idx + marcador.length));
      try {
        await _client.storage.from('productos').remove([oldPath]);
      } catch (_) {}
    }

    return url;
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

// Top-level para poder ejecutarse en un isolate via compute().
Uint8List _comprimirImagen(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  const maxLado = 600;
  img.Image imagen = decoded;
  if (decoded.width > maxLado || decoded.height > maxLado) {
    imagen = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: maxLado)
        : img.copyResize(decoded, height: maxLado);
  }

  return Uint8List.fromList(img.encodeJpg(imagen, quality: 80));
}
