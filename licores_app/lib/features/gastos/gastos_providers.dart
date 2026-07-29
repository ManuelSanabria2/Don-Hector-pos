import 'package:flutter/material.dart' show DateTimeRange;
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

final gastosPorRangoProvider = FutureProvider.family<List<Gasto>, DateTimeRange>((ref, range) async {
  final repo = ref.watch(gastosRepositoryProvider);
  final selectedCat = ref.watch(selectedCategoriaGastoProvider);
  
  final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);

  return repo.getGastos(
    desde: range.start,
    hasta: end,
    categoriaId: selectedCat,
  );
});

final gastosDiariosProvider = FutureProvider.autoDispose.family<List<Gasto>, DateTime>((ref, date) async {
  final repo = ref.watch(gastosRepositoryProvider);
  final selectedCat = ref.watch(selectedCategoriaGastoProvider);
  return repo.getGastos(
    desde: date,
    hasta: date,
    categoriaId: selectedCat,
  );
});

final gastosDiariosAnalisisProvider = FutureProvider.autoDispose.family<List<Gasto>, DateTime>((ref, date) async {
  final repo = ref.watch(gastosRepositoryProvider);
  return repo.getGastos(
    desde: date,
    hasta: date,
  );
});

