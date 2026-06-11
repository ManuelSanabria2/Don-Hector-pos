import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/categoria_gasto.dart';
import '../../data/models/gasto.dart';
import '../../data/repositories/gastos_repository.dart';

final categoriasGastoProvider = FutureProvider<List<CategoriaGasto>>((ref) {
  final repo = ref.watch(gastosRepositoryProvider);
  return repo.listarCategorias();
});

final selectedCategoriaGastoProvider = StateProvider<String?>((ref) => null);

final gastosDelMesProvider = FutureProvider<List<Gasto>>((ref) async {
  final repo = ref.watch(gastosRepositoryProvider);
  final selectedCat = ref.watch(selectedCategoriaGastoProvider);
  
  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1);
  final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

  return repo.getGastos(
    desde: startOfMonth,
    hasta: endOfMonth,
    categoriaId: selectedCat,
  );
});
