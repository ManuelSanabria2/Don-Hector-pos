import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/contabilidad_repository.dart';
import '../../data/repositories/inventario_repository.dart';

final resumenHoyProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(contabilidadRepositoryProvider);
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

  final resumen = await repo.getResumenDia(now);
  final cogsHoy = await repo.getCogsRango(startOfDay, endOfDay);
  final gastosHoy = await repo.getTotalGastosRango(startOfDay, endOfDay);
  final utilidadHoy = (resumen['total_ventas'] as num? ?? 0) - cogsHoy - gastosHoy;

  return {
    ...resumen,
    'cogs_hoy': cogsHoy,
    'gastos_hoy': gastosHoy,
    'utilidad_hoy': utilidadHoy,
  };
});

final utilidadRangoProvider = FutureProvider.autoDispose
    .family<Map<String, num>, DateTimeRange>((ref, range) async {
  final repo = ref.watch(contabilidadRepositoryProvider);
  final start = range.start;
  final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);

  final ventas = await repo.getTotalVentasRango(start, end);
  final gastos = await repo.getTotalGastosRango(start, end);
  final cogs = await repo.getCogsRango(start, end);
  final utilidad = ventas - gastos - cogs;

  return {
    'ventas': ventas,
    'gastos': gastos,
    'cogs': cogs,
    'utilidad': utilidad,
  };
});

final metricasMesProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(contabilidadRepositoryProvider);
  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1);
  final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

  final ventasMes = await repo.getTotalVentasRango(startOfMonth, endOfMonth);
  final gastosMes = await repo.getTotalGastosRango(startOfMonth, endOfMonth);
  final cogsMes = await repo.getCogsRango(startOfMonth, endOfMonth);
  final utilidadEstimada = ventasMes - gastosMes - cogsMes;

  final estadoCuenta = await repo.getEstadoCuentaMayoristas();
  final deudaPendiente = estadoCuenta.fold<num>(0, (sum, row) => sum + ((row['deuda_pendiente'] as num?) ?? 0));

  return {
    'ventas_mes': ventasMes,
    'gastos_mes': gastosMes,
    'utilidad_estimada': utilidadEstimada,
    'deuda_pendiente': deudaPendiente,
  };
});

final ventasUltimos7DiasProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(contabilidadRepositoryProvider);
  return repo.getResumenVentasUltimos7Dias();
});

final topProductosMesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(contabilidadRepositoryProvider);
  return repo.getProductosMasVendidos(limit: 5);
});

final ventasPorDiaProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, DateTime>((ref, fecha) async {
  final repo = ref.watch(contabilidadRepositoryProvider);
  return repo.getVentasPorDia(fecha);
});

final valorInventarioProvider = FutureProvider.autoDispose<Map<String, num>>((ref) async {
  final repo = ref.watch(inventarioRepositoryProvider);
  final productos = await repo.getProductos();
  num totalCosto = 0;
  num totalVenta = 0;
  for (final p in productos) {
    totalCosto += p.stockActual * p.costo;
    totalVenta += p.stockActual * p.precioPublico;
  }
  return {
    'total_costo': totalCosto,
    'total_venta': totalVenta,
    'utilidad_potencial': totalVenta - totalCosto,
  };
});
