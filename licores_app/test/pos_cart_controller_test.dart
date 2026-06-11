import 'package:flutter_test/flutter_test.dart';
import 'package:licores_app/data/models/producto.dart';
import 'package:licores_app/data/models/venta_enums.dart';
import 'package:licores_app/features/pos/pos_providers.dart';

void main() {
  group('PosCartController Tests', () {
    late Producto testProduct;

    setUp(() {
      testProduct = Producto(
        id: 'prod-123',
        nombre: 'Cerveza Club Colombia',
        precioPublico: 5000,
        precioMayorista: 4500,
        costo: 3000,
        stockActual: 10,
        stockMinimo: 2,
        activo: true,
      );
    });

    test('Initial state is empty', () {
      final controller = PosCartController();
      expect(controller.state.items, isEmpty);
      expect(controller.state.descuento, equals(0));
      expect(controller.state.subtotal, equals(0));
      expect(controller.state.total, equals(0));
      expect(controller.state.totalItems, equals(0));
      expect(controller.state.canSubmit, isFalse);
    });

    test('Add product to cart', () {
      final controller = PosCartController();
      controller.addProduct(testProduct, cantidad: 2);

      final state = controller.state;
      expect(state.items.length, equals(1));
      expect(state.items.first.producto.id, equals('prod-123'));
      expect(state.items.first.cantidad, equals(2));
      expect(state.subtotal, equals(10000));
      expect(state.total, equals(10000));
      expect(state.totalItems, equals(2));
      expect(state.canSubmit, isTrue);
    });

    test('Increment and decrement quantity', () {
      final controller = PosCartController();
      controller.addProduct(testProduct, cantidad: 1);

      // Increment
      controller.increment(testProduct.id, cantidad: 2);
      expect(controller.state.items.first.cantidad, equals(3));
      expect(controller.state.total, equals(15000));

      // Decrement
      controller.decrement(testProduct.id);
      expect(controller.state.items.first.cantidad, equals(2));
      expect(controller.state.total, equals(10000));
    });

    test('Cannot exceed stockActual when adding or incrementing', () {
      final controller = PosCartController();
      
      // Try adding 15 units of a product that has stockActual = 10
      controller.addProduct(testProduct, cantidad: 15);
      expect(controller.state.items.first.cantidad, equals(10));

      // Try incrementing beyond stock
      controller.increment(testProduct.id, cantidad: 5);
      expect(controller.state.items.first.cantidad, equals(10));
    });

    test('Apply discount and calculate total', () {
      final controller = PosCartController();
      controller.addProduct(testProduct, cantidad: 3); // Subtotal: 15000
      
      controller.setDescuento(2000);
      expect(controller.state.descuento, equals(2000));
      expect(controller.state.subtotal, equals(15000));
      expect(controller.state.total, equals(13000));

      // Discount larger than subtotal should result in total = 0
      controller.setDescuento(20000);
      expect(controller.state.total, equals(0));
    });

    test('Clear cart resets all states', () {
      final controller = PosCartController();
      controller.addProduct(testProduct, cantidad: 3);
      controller.setDescuento(2000);
      controller.setCliente('cliente-abc');
      controller.setTipoVenta(TipoVenta.mayorista);
      
      controller.clear();
      final state = controller.state;
      expect(state.items, isEmpty);
      expect(state.descuento, equals(0));
      expect(state.clienteId, isNull);
      expect(state.tipoVenta, equals(TipoVenta.publico));
    });
  });
}
