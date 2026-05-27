import 'producto.dart';

class CarritoItem {
  const CarritoItem({
    required this.producto,
    required this.cantidad,
    required this.precioUnitario,
  });

  final Producto producto;
  final int cantidad;
  final num precioUnitario;

  num get subtotal => cantidad * precioUnitario;

  CarritoItem copyWith({
    Producto? producto,
    int? cantidad,
    num? precioUnitario,
  }) {
    return CarritoItem(
      producto: producto ?? this.producto,
      cantidad: cantidad ?? this.cantidad,
      precioUnitario: precioUnitario ?? this.precioUnitario,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'producto_id': producto.id,
      'cantidad': cantidad,
      'precio_unitario': precioUnitario,
    };
  }
}
