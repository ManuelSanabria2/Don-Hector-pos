import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/proveedor.dart';
import '../../data/models/compra_inventario.dart';
import '../../data/models/capital_negocio.dart';
import '../../data/repositories/compras_repository.dart';
import '../../data/repositories/capital_repository.dart';

final proveedoresProvider = FutureProvider<List<Proveedor>>((ref) {
  final repo = ref.watch(comprasRepositoryProvider);
  return repo.getProveedores();
});

final comprasDelMesProvider = FutureProvider<List<CompraInventario>>((ref) async {
  final repo = ref.watch(comprasRepositoryProvider);
  
  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1);
  final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

  return repo.getCompras(
    desde: startOfMonth,
    hasta: endOfMonth,
    incluirAnuladas: false,
  );
});

final comprasPorRangoProvider = FutureProvider.family<List<CompraInventario>, DateTimeRange>((ref, range) async {
  final repo = ref.watch(comprasRepositoryProvider);
  
  final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);

  return repo.getCompras(
    desde: range.start,
    hasta: end,
    incluirAnuladas: false,
  );
});

final totalComprasRangoProvider = FutureProvider.family<num, DateTimeRange>((ref, range) async {
  final repo = ref.watch(comprasRepositoryProvider);
  
  final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);

  return repo.getTotalComprasRango(range.start, end);
});

final capitalNegocioProvider = FutureProvider<CapitalNegocio?>((ref) {
  final repo = ref.watch(capitalRepositoryProvider);
  return repo.getCapital();
});

final resumenPatrimonioProvider = FutureProvider<Map<String, num>>((ref) {
  final repo = ref.watch(capitalRepositoryProvider);
  return repo.getResumenFinancieroGeneral();
});

final compraDetalleProvider = FutureProvider.family<CompraInventario, String>((ref, compraId) {
  final repo = ref.watch(comprasRepositoryProvider);
  return repo.getCompraConDetalle(compraId);
});
