import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/contabilidad_repository.dart';

final resumenHoyProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(contabilidadRepositoryProvider);
  return repo.getResumenDia(DateTime.now());
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
