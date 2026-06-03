import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/categoria.dart';
import '../../data/models/producto.dart';
import '../../data/repositories/inventario_repository.dart';

final inventarioBusquedaProvider = StateProvider.autoDispose<String>((ref) {
  return '';
});

final inventarioCategoriaProvider = StateProvider.autoDispose<String?>((ref) {
  return null;
});

final inventarioCategoriasProvider =
    FutureProvider.autoDispose<List<Categoria>>((ref) async {
      final list = await ref.watch(inventarioRepositoryProvider).listarCategorias();
      list.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
      return list;
    });

final inventarioProductosProvider = FutureProvider.autoDispose<List<Producto>>((
  ref,
) async {
  final busqueda = ref.watch(inventarioBusquedaProvider);
  final categoriaId = ref.watch(inventarioCategoriaProvider);

  final list = await ref
      .watch(inventarioRepositoryProvider)
      .getProductos(busqueda: busqueda, categoriaId: categoriaId);
  list.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
  return list;
});

final stockBajoProvider = StreamProvider.autoDispose<List<Producto>>((ref) {
  return ref.watch(inventarioRepositoryProvider).watchStockBajo();
});
