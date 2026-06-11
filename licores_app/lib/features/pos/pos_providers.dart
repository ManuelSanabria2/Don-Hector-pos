import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/carrito_item.dart';
import '../../data/models/cliente_mayorista.dart';
import '../../data/models/producto.dart';
import '../../data/models/venta_enums.dart';
import '../../data/repositories/inventario_repository.dart';
import '../../data/repositories/mayoristas_repository.dart';

import '../mayoristas/mayoristas_providers.dart';

final posBusquedaProvider = StateProvider.autoDispose<String>((ref) => '');

final posClienteBusquedaProvider = StateProvider.autoDispose<String>(
  (ref) => '',
);

final posProductosProvider = FutureProvider.autoDispose<List<Producto>>((ref) {
  final busqueda = ref.watch(posBusquedaProvider);
  return ref
      .watch(inventarioRepositoryProvider)
      .getProductos(busqueda: busqueda);
});

final posClientesProvider = FutureProvider.autoDispose<List<ClienteConCuenta>>((
  ref,
) async {
  final busqueda = ref.watch(posClienteBusquedaProvider).trim().toLowerCase();
  final clientesConCuenta = await ref.watch(mayoristasClientesProvider.future);

  if (busqueda.isEmpty) return clientesConCuenta;

  return clientesConCuenta.where((item) {
    final cliente = item.cliente;
    return cliente.nombre.toLowerCase().contains(busqueda) ||
        (cliente.telefono?.contains(busqueda) ?? false) ||
        (cliente.nit?.toLowerCase().contains(busqueda) ?? false);
  }).toList();
});

final posCartProvider =
    StateNotifierProvider.autoDispose<PosCartController, PosCartState>((ref) {
      return PosCartController();
    });

class PosCartState {
  const PosCartState({
    this.items = const [],
    this.descuento = 0,
    this.metodoPago = MetodoPago.efectivo,
    this.tipoVenta = TipoVenta.publico,
    this.clienteId,
  });

  final List<CarritoItem> items;
  final num descuento;
  final MetodoPago metodoPago;
  final TipoVenta tipoVenta;
  final String? clienteId;

  num get subtotal => items.fold<num>(0, (sum, item) => sum + item.subtotal);

  num get total {
    final value = subtotal - descuento;
    return value < 0 ? 0 : value;
  }

  int get totalItems => items.fold<int>(0, (sum, item) => sum + item.cantidad);

  bool get canSubmit {
    return items.isNotEmpty &&
        total > 0 &&
        (tipoVenta == TipoVenta.publico || clienteId != null);
  }

  PosCartState copyWith({
    List<CarritoItem>? items,
    num? descuento,
    MetodoPago? metodoPago,
    TipoVenta? tipoVenta,
    String? clienteId,
    bool clearCliente = false,
  }) {
    return PosCartState(
      items: items ?? this.items,
      descuento: descuento ?? this.descuento,
      metodoPago: metodoPago ?? this.metodoPago,
      tipoVenta: tipoVenta ?? this.tipoVenta,
      clienteId: clearCliente ? null : clienteId ?? this.clienteId,
    );
  }
}

class PosCartController extends StateNotifier<PosCartState> {
  PosCartController() : super(const PosCartState());

  void addProduct(Producto producto, {int cantidad = 1}) {
    final index = state.items.indexWhere(
      (item) => item.producto.id == producto.id,
    );

    if (index == -1) {
      if (producto.stockActual <= 0) return;
      final actualCant = cantidad <= producto.stockActual ? cantidad : producto.stockActual;
      state = state.copyWith(
        items: [
          ...state.items,
          CarritoItem(
            producto: producto,
            cantidad: actualCant,
            precioUnitario: state.tipoVenta == TipoVenta.mayorista
                ? producto.precioMayorista
                : producto.precioPublico,
          ),
        ],
      );
      return;
    }

    increment(producto.id, cantidad: cantidad);
  }

  void increment(String productoId, {int cantidad = 1}) {
    state = state.copyWith(
      items: [
        for (final item in state.items)
          if (item.producto.id == productoId)
            item.copyWith(
              cantidad: item.cantidad + cantidad <= item.producto.stockActual
                  ? item.cantidad + cantidad
                  : item.producto.stockActual,
            )
          else
            item,
      ],
    );
  }

  void decrement(String productoId) {
    state = state.copyWith(
      items: [
        for (final item in state.items)
          if (item.producto.id != productoId)
            item
          else if (item.cantidad > 0)
            item.copyWith(cantidad: item.cantidad - 1)
          else
            item,
      ],
    );
  }

  void remove(String productoId) {
    state = state.copyWith(
      items: state.items
          .where((item) => item.producto.id != productoId)
          .toList(),
    );
  }

  void setDescuento(num descuento) {
    state = state.copyWith(descuento: descuento < 0 ? 0 : descuento);
  }

  void setMetodoPago(MetodoPago metodoPago) {
    state = state.copyWith(metodoPago: metodoPago);
  }

  void setTipoVenta(TipoVenta tipoVenta) {
    state = state.copyWith(
      tipoVenta: tipoVenta,
      clearCliente: tipoVenta == TipoVenta.publico,
      items: [
        for (final item in state.items)
          item.copyWith(
            precioUnitario: tipoVenta == TipoVenta.mayorista
                ? item.producto.precioMayorista
                : item.producto.precioPublico,
          ),
      ],
    );
  }

  void setCliente(String? clienteId) {
    state = state.copyWith(clienteId: clienteId);
  }

  void clear() {
    state = const PosCartState();
  }
}
