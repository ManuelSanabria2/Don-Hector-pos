import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/abono_fiado.dart';
import '../../data/models/fiado_publico.dart';
import '../../data/repositories/fiados_repository.dart';

/// Deuda de cada persona que quedó debiendo en ventas al público.
final estadoCuentaFiadosProvider =
    FutureProvider.autoDispose<List<CuentaFiado>>((ref) async {
  final repo = ref.watch(fiadosRepositoryProvider);
  return repo.getEstadoCuentaFiados();
});

/// Ventas fiadas de una persona, por nombre normalizado.
final fiadosDeDeudorProvider = FutureProvider.autoDispose
    .family<List<FiadoPublico>, String>((ref, deudorNombre) async {
  final repo = ref.watch(fiadosRepositoryProvider);
  return repo.getFiadosDeDeudor(deudorNombre);
});

/// Abonos registrados sobre una venta fiada puntual.
final abonosDeFiadoProvider = FutureProvider.autoDispose
    .family<List<AbonoFiado>, String>((ref, fiadoId) async {
  final repo = ref.watch(fiadosRepositoryProvider);
  return repo.getAbonosDeFiado(fiadoId);
});

/// Total fiado pendiente de cobro, para la tarjeta de Contabilidad.
final totalFiadosPendienteProvider = FutureProvider.autoDispose<num>((ref) async {
  final cuentas = await ref.watch(estadoCuentaFiadosProvider.future);
  return cuentas.fold<num>(0, (sum, cuenta) => sum + cuenta.deudaPendiente);
});
