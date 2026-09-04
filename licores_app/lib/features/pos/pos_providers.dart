import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/carrito_item.dart';
import '../../data/models/producto.dart';
import '../../data/models/venta_enums.dart';
import '../../data/repositories/inventario_repository.dart';

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
  PosCartState({
    List<CarritoItem> items = const [],
    this.descuento = 0,
    this.metodoPago = MetodoPago.efectivo,
    this.tipoVenta = TipoVenta.publico,
    this.clienteId,
    this.deudorNombre,
  }) : items = List<CarritoItem>.from(items)
         ..sort((a, b) => a.producto.nombre.toLowerCase().compareTo(b.producto.nombre.toLowerCase()));

  final List<CarritoItem> items;
  final num descuento;
  final MetodoPago metodoPago;
  final TipoVenta tipoVenta;
  final String? clienteId;

  /// A quién se le fía, en ventas al público a crédito. No hay ficha de
  /// cliente: es solo el nombre escrito en el momento.
  final String? deudorNombre;

  /// La venta es un fiado informal: público + crédito.
  bool get esFiadoPublico =>
      tipoVenta == TipoVenta.publico && metodoPago == MetodoPago.credito;

  num get subtotal => items.fold<num>(0, (sum, item) => sum + item.subtotal);

  num get total {
    final value = subtotal - descuento;
    return value < 0 ? 0 : value;
  }

  int get totalItems => items.fold<int>(0, (sum, item) => sum + item.cantidad);

  bool get canSubmit {
    return items.isNotEmpty &&
        total > 0 &&
        (tipoVenta == TipoVenta.publico || clienteId != null) &&
        // Un fiado sin nombre no se puede cobrar después; la base
        // también lo rechaza.
        (!esFiadoPublico || (deudorNombre?.trim().isNotEmpty ?? false));
  }

  PosCartState copyWith({
    List<CarritoItem>? items,
    num? descuento,
    MetodoPago? metodoPago,
    TipoVenta? tipoVenta,
    String? clienteId,
    String? deudorNombre,
    bool clearCliente = false,
    bool clearDeudor = false,
  }) {
    return PosCartState(
      items: items ?? this.items,
      descuento: descuento ?? this.descuento,
      metodoPago: metodoPago ?? this.metodoPago,
      tipoVenta: tipoVenta ?? this.tipoVenta,
      clienteId: clearCliente ? null : clienteId ?? this.clienteId,
      deudorNombre: clearDeudor ? null : deudorNombre ?? this.deudorNombre,
    );
  }
}

class PosCartController extends StateNotifier<PosCartState> {
  PosCartController() : super(PosCartState());

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
    state = state.copyWith(
      metodoPago: metodoPago,
      // El nombre del deudor solo tiene sentido mientras la venta sea fiada.
      clearDeudor: metodoPago != MetodoPago.credito,
    );
  }

  void setDeudorNombre(String? deudorNombre) {
    state = state.copyWith(deudorNombre: deudorNombre);
  }

  void setTipoVenta(TipoVenta tipoVenta) {
    state = state.copyWith(
      tipoVenta: tipoVenta,
      clearCliente: tipoVenta == TipoVenta.publico,
      // Al pasar a mayorista el fiado deja de identificarse por nombre
      // suelto: la deuda queda a cargo del cliente seleccionado.
      clearDeudor: tipoVenta == TipoVenta.mayorista,
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
    state = PosCartState();
  }
}

final posTurboProductosProvider = FutureProvider.autoDispose<List<Producto>>((ref) {
  return ref.watch(inventarioRepositoryProvider).getProductosTurbo();
});

/// Top 10 productos mas vendidos a mayoristas en el dia de hoy, que
/// encabezan la lista de la pestana de venta.
final posMasVendidosProvider = FutureProvider.autoDispose<List<Producto>>((ref) {
  return ref
      .watch(inventarioRepositoryProvider)
      .getProductosMasVendidosMayoristaDia(limit: 10);
});
