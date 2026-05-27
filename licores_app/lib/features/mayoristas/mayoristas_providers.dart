import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/cliente_mayorista.dart';
import '../../data/models/cobro_mayorista.dart';
import '../../data/repositories/mayoristas_repository.dart';

final mayoristasClientesProvider =
    FutureProvider.autoDispose<List<ClienteConCuenta>>((ref) async {
      final repository = ref.watch(mayoristasRepositoryProvider);
      final clientes = await repository.getClientes();
      final cuentas = await repository.getEstadoCuentaMayoristas();
      final cuentasById = {
        for (final cuenta in cuentas) cuenta['id'] as String: cuenta,
      };

      return [
        for (final cliente in clientes)
          ClienteConCuenta(
            cliente: cliente,
            deudaPendiente: _asNum(cuentasById[cliente.id]?['deuda_pendiente']),
            totalCompras: _asNum(cuentasById[cliente.id]?['total_compras']),
            totalPagado: _asNum(cuentasById[cliente.id]?['total_pagado']),
            numPedidos: _asInt(cuentasById[cliente.id]?['num_pedidos']),
          ),
      ];
    });

final clienteCobrosProvider = FutureProvider.autoDispose
    .family<List<CobroMayorista>, String>((ref, clienteId) {
      return ref
          .watch(mayoristasRepositoryProvider)
          .getCobrosCliente(clienteId);
    });

final clienteVentasProductosProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, clienteId) {
      return ref
          .watch(mayoristasRepositoryProvider)
          .getVentasProductosCliente(clienteId);
    });

class ClienteConCuenta {
  const ClienteConCuenta({
    required this.cliente,
    required this.deudaPendiente,
    required this.totalCompras,
    required this.totalPagado,
    required this.numPedidos,
  });

  final ClienteMayorista cliente;
  final num deudaPendiente;
  final num totalCompras;
  final num totalPagado;
  final int numPedidos;

  bool get tieneCobroPendiente => deudaPendiente > 0;
}

num _asNum(Object? value) {
  if (value == null) return 0;
  if (value is num) return value;
  return num.tryParse(value.toString()) ?? 0;
}

int _asInt(Object? value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
