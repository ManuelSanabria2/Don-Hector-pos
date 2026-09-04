import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/producto.dart';
import '../../data/models/utilidad_producto.dart';
import '../../data/repositories/contabilidad_repository.dart';
import '../../data/repositories/inventario_repository.dart';
import '../../data/repositories/compras_repository.dart';
import '../../data/repositories/prestamos_repository.dart';

final resumenHoyProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(contabilidadRepositoryProvider);
  final comprasRepo = ref.watch(comprasRepositoryProvider);
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

  final resumen = await repo.getResumenDia(now);
  final cogsHoy = await repo.getCogsRango(startOfDay, endOfDay);
  final gastosHoy = await repo.getTotalGastosRango(startOfDay, endOfDay);
  final comprasHoy = await comprasRepo.getTotalComprasRango(startOfDay, endOfDay);
  
  final utilidadHoy = (resumen['total_ventas'] as num? ?? 0) - cogsHoy - gastosHoy;

  return {
    ...resumen,
    'cogs_hoy': cogsHoy,
    'gastos_hoy': gastosHoy,
    'utilidad_hoy': utilidadHoy,
    'compras_hoy': comprasHoy,
  };
});

final utilidadRangoProvider = FutureProvider.autoDispose
    .family<Map<String, num>, DateTimeRange>((ref, range) async {
  final repo = ref.watch(contabilidadRepositoryProvider);
  final comprasRepo = ref.watch(comprasRepositoryProvider);
  final start = range.start;
  final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);

  final ventas = await repo.getTotalVentasRango(start, end);
  final gastos = await repo.getTotalGastosRango(start, end);
  final cogs = await repo.getCogsRango(start, end);
  final totalCompras = await comprasRepo.getTotalComprasRango(start, end);
  
  final utilidad = ventas - gastos - cogs;

  return {
    'ventas': ventas,
    'gastos': gastos,
    'cogs': cogs,
    'utilidad': utilidad,
    'compras_periodo': totalCompras,
  };
});

/// Cuántos días abarca el rango por defecto de la utilidad por producto.
const int diasSemanaUtilidad = 7;

/// Productos que el usuario eligió para ver su utilidad.
final utilidadProductosSeleccionadosProvider =
    StateProvider<List<Producto>>((ref) => const []);

/// Rango de los últimos [dias] días, hoy incluido. Es el valor por defecto.
DateTimeRange rangoUltimosDias(
  int dias, [
  DateTime? hoy,
]) {
  final ahora = hoy ?? DateTime.now();
  final fin = DateTime(ahora.year, ahora.month, ahora.day);
  return DateTimeRange(
    start: fin.subtract(Duration(days: dias - 1)),
    end: fin,
  );
}

/// Rango del mes en curso, del día 1 a hoy.
DateTimeRange rangoMesEnCurso([DateTime? hoy]) {
  final ahora = hoy ?? DateTime.now();
  return DateTimeRange(
    start: DateTime(ahora.year, ahora.month, 1),
    end: DateTime(ahora.year, ahora.month, ahora.day),
  );
}

/// Período que se está viendo en la pestaña de utilidad por producto.
final utilidadRangoFechasProvider = StateProvider<DateTimeRange>(
  (ref) => rangoUltimosDias(diasSemanaUtilidad),
);

final utilidadPorProductoRangoProvider =
    FutureProvider.autoDispose<List<UtilidadProducto>>((ref) async {
  final productos = ref.watch(utilidadProductosSeleccionadosProvider);
  if (productos.isEmpty) return const [];

  final repo = ref.watch(contabilidadRepositoryProvider);
  final rango = ref.watch(utilidadRangoFechasProvider);
  return repo.getUtilidadPorProductoRango(rango.start, rango.end, productos);
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

  final ventasPorMetodo = await repo.getVentasPorMetodoPagoRango(startOfMonth, endOfMonth);
  final ventasEfectivoPublico = ventasPorMetodo['efectivo_publico'] ?? 0;

  // El efectivo lo calcula la base: parte del conteo físico de caja en
  // capital_negocio.fecha_corte y acumula TODOS los flujos posteriores.
  // Antes se rehacía aquí a mano y quedaba descuadrado, porque ignoraba el
  // efectivo inicial, las compras y los pagos a proveedores, y se limitaba
  // al mes en curso en vez de arrancar en el conteo.
  final efectivoReal = await repo.getEfectivoReal();

  final ventasMayoristaMes = (ventasPorMetodo['efectivo'] ?? 0) + (ventasPorMetodo['transferencias'] ?? 0) - (ventasPorMetodo['efectivo_publico'] ?? 0) - (ventasPorMetodo['transferencias_publico'] ?? 0);

  return {
    'ventas_mes': ventasMes,
    'gastos_mes': gastosMes,
    'cogs_mes': cogsMes,
    'utilidad_estimada': utilidadEstimada,
    'deuda_pendiente': deudaPendiente,
    'ventas_efectivo_mes': ventasEfectivoPublico,
    'efectivo_real': efectivoReal,
    'ventas_mayorista_mes': ventasMayoristaMes,
  };
});

final metricasDiaProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, DateTime>((ref, fecha) async {
  final repo = ref.watch(contabilidadRepositoryProvider);

  final startOfDay = DateTime(fecha.year, fecha.month, fecha.day);
  final endOfDay = DateTime(fecha.year, fecha.month, fecha.day, 23, 59, 59);

  final ventasDia = await repo.getTotalVentasRango(startOfDay, endOfDay);
  final gastosDia = await repo.getTotalGastosRango(startOfDay, endOfDay);
  final cogsDia = await repo.getCogsRango(startOfDay, endOfDay);

  final deudores = await repo.getEstadoCuentaMayoristas();
  final deudaPendiente = deudores.fold<num>(0, (sum, row) => sum + ((row['deuda_pendiente'] as num?) ?? 0));

  final utilidadDia = ventasDia - gastosDia - cogsDia;

  // El efectivo lo calcula la base: parte del conteo físico de caja en
  // capital_negocio.fecha_corte y acumula TODOS los flujos posteriores.
  // Antes se rehacía aquí a mano y quedaba descuadrado, porque ignoraba el
  // efectivo inicial, las compras y los pagos a proveedores, y se limitaba
  // al mes en curso en vez de arrancar en el conteo.
  final efectivoReal = await repo.getEfectivoReal();

  final prestamosRepo = ref.watch(prestamosRepositoryProvider);
  final ventasHoyList = await repo.getVentasPorDia(fecha);
  final deudaCompras = await repo.getDeudaTotalCompras();
  final fiadosPendiente = await repo.getTotalFiadosPendiente();
  final prestamosPendiente = await prestamosRepo.getTotalPrestamosPendiente();

  return {
    'num_ventas': ventasHoyList.length,
    'ventas_dia': ventasDia,
    'gastos_dia': gastosDia,
    'cogs_dia': cogsDia,
    'utilidad_dia': utilidadDia,
    'deuda_pendiente': deudaPendiente,
    'efectivo_real': efectivoReal,
    'deuda_compras': deudaCompras,
    'fiados_pendiente': fiadosPendiente,
    'prestamos_pendiente': prestamosPendiente,
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

final ventasPorRangoProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, DateTimeRange>((ref, range) async {
  final repo = ref.watch(contabilidadRepositoryProvider);
  return repo.getVentasRango(range.start, range.end);
});

final itemsVentaProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, ventaId) async {
  final repo = ref.watch(contabilidadRepositoryProvider);
  return repo.getItemsDeVenta(ventaId);
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

final flujoEfectivoRangoProvider = FutureProvider.autoDispose
    .family<Map<String, num>, DateTimeRange>((ref, range) async {
  final contabilidadRepo = ref.watch(contabilidadRepositoryProvider);
  final comprasRepo = ref.watch(comprasRepositoryProvider);

  final start = range.start;
  final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);

  final ventasPorMetodo = await contabilidadRepo.getVentasPorMetodoPagoRango(start, end);
  final ventasEfectivoPublico = ventasPorMetodo['efectivo_publico'] ?? 0;

  final abonosPorMetodo = await contabilidadRepo.getAbonosPorMetodoPagoRango(start, end);
  final abonosEfectivo = abonosPorMetodo['efectivo'] ?? 0;

  // Los fiados entran a caja cuando la persona abona, no al venderse.
  final abonosFiados =
      await contabilidadRepo.getAbonosFiadosPorMetodoPagoRango(start, end);
  final abonosFiadosEfectivo = abonosFiados['efectivo'] ?? 0;

  // Un préstamo recibido entra a caja; el abono a capital sale. El interés
  // no va aquí: ya sale como gasto y contarlo de nuevo lo restaría dos veces.
  final movPrestamos = await ref
      .watch(prestamosRepositoryProvider)
      .getMovimientosEfectivoRango(start, end);
  final prestamosRecibidos = movPrestamos['recibido'] ?? 0;
  final prestamosAbonados = movPrestamos['abonado_capital'] ?? 0;

  // Solo los gastos pagados en efectivo salen de la caja física.
  final gastosEfectivo =
      await contabilidadRepo.getTotalGastosRango(start, end, metodoPago: 'efectivo');

  final comprasEfectivo =
      await contabilidadRepo.getTotalComprasEfectivoRango(start, end);

  // Pagos en efectivo de deudas de compras a crédito (incluye el
  // pago inicial de contado).
  final pagosComprasEfectivo = await comprasRepo.getTotalPagosComprasRango(
    start,
    end,
    metodoPago: 'efectivo',
  );

  final flujoEntradas = ventasEfectivoPublico +
      abonosEfectivo +
      abonosFiadosEfectivo +
      prestamosRecibidos;
  final flujoSalidas = gastosEfectivo +
      comprasEfectivo +
      pagosComprasEfectivo +
      prestamosAbonados;
  final flujoNeto = flujoEntradas - flujoSalidas;

  return {
    'flujo_entradas': flujoEntradas,
    'flujo_salidas': flujoSalidas,
    'flujo_neto': flujoNeto,
  };
});
