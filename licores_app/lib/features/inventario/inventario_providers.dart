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
    FutureProvider.autoDispose<List<Categoria>>((ref) {
      return ref.watch(inventarioRepositoryProvider).listarCategorias();
    });

final inventarioProductosProvider = FutureProvider.autoDispose<List<Producto>>((
  ref,
) {
  final busqueda = ref.watch(inventarioBusquedaProvider);
  final categoriaId = ref.watch(inventarioCategoriaProvider);

  return ref
      .watch(inventarioRepositoryProvider)
      .getProductos(busqueda: busqueda, categoriaId: categoriaId);
});

final stockBajoProvider = StreamProvider.autoDispose<List<Producto>>((ref) {
  return ref.watch(inventarioRepositoryProvider).watchStockBajo();
});
