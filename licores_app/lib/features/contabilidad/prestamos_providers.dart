import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/pago_prestamo.dart';
import '../../data/models/prestamo.dart';
import '../../data/repositories/prestamos_repository.dart';

final prestamosProvider =
    FutureProvider.autoDispose<List<Prestamo>>((ref) async {
  final repo = ref.watch(prestamosRepositoryProvider);
  return repo.getPrestamos();
});

final pagosDePrestamoProvider = FutureProvider.autoDispose
    .family<List<PagoPrestamo>, String>((ref, prestamoId) async {
  final repo = ref.watch(prestamosRepositoryProvider);
  return repo.getPagosDePrestamo(prestamoId);
});

/// Deuda total por préstamos, para la tarjeta de Contabilidad.
final totalPrestamosPendienteProvider =
    FutureProvider.autoDispose<num>((ref) async {
  final prestamos = await ref.watch(prestamosProvider.future);
  return prestamos.fold<num>(0, (sum, p) => sum + p.saldo);
});
