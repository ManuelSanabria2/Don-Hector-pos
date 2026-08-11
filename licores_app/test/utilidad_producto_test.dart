import 'package:flutter_test/flutter_test.dart';
import 'package:licores_app/data/models/producto.dart';
import 'package:licores_app/data/models/utilidad_producto.dart';

void main() {
  Producto producto({
    required String id,
    required String nombre,
    num costo = 2000,
  }) {
    return Producto(
      id: id,
      nombre: nombre,
      precioPublico: 5000,
      precioMayorista: 4000,
      costo: costo,
      stockActual: 10,
      stockMinimo: 5,
    );
  }

  // PostgREST devuelve los numeric como String, no como número.
  Map<String, dynamic> linea({
    String productoId = 'p1',
    Object? cantidad = 2,
    String precio = '5000.000',
    Object? costoHistorico = '2000.000',
  }) {
    return {
      'producto_id': productoId,
      'cantidad': cantidad,
      'precio_unitario': precio,
      'costo_unitario_historico': costoHistorico,
    };
  }

  group('UtilidadProducto', () {
    test('La utilidad es ingresos menos costo', () {
      const u = UtilidadProducto(
        productoId: 'p1',
        nombre: 'Aguardiente',
        unidades: 3,
        ingresos: 15000,
        costo: 6000,
      );

      expect(u.utilidad, equals(9000));
      expect(u.margen, closeTo(60, 0.001));
      expect(u.sinVentas, isFalse);
    });

    test('Sin ingresos no hay margen', () {
      const u = UtilidadProducto(
        productoId: 'p1',
        nombre: 'Aguardiente',
        unidades: 0,
        ingresos: 0,
        costo: 0,
      );

      expect(u.margen, isNull);
      expect(u.sinVentas, isTrue);
    });
  });

  group('agruparUtilidadPorProducto', () {
    test('Suma varias líneas del mismo producto en una sola fila', () {
      final filas = agruparUtilidadPorProducto(
        [producto(id: 'p1', nombre: 'Aguardiente')],
        [
          linea(cantidad: 2),
          linea(cantidad: 3),
        ],
      );

      expect(filas, hasLength(1));
      expect(filas.single.unidades, equals(5));
      expect(filas.single.ingresos, equals(25000));
      expect(filas.single.costo, equals(10000));
      expect(filas.single.utilidad, equals(15000));
    });

    test('Usa el costo actual cuando no hay costo histórico', () {
      final filas = agruparUtilidadPorProducto(
        [producto(id: 'p1', nombre: 'Aguardiente', costo: 1500)],
        [linea(cantidad: 2, costoHistorico: null)],
      );

      expect(filas.single.costo, equals(3000));
      expect(filas.single.utilidad, equals(7000));
    });

    test('Prefiere el costo histórico sobre el costo actual', () {
      final filas = agruparUtilidadPorProducto(
        [producto(id: 'p1', nombre: 'Aguardiente', costo: 9999)],
        [linea(cantidad: 1, costoHistorico: '2000.000')],
      );

      expect(filas.single.costo, equals(2000));
    });

    test('Los productos sin ventas aparecen en ceros', () {
      final filas = agruparUtilidadPorProducto(
        [
          producto(id: 'p1', nombre: 'Aguardiente'),
          producto(id: 'p2', nombre: 'Ron'),
        ],
        [linea(productoId: 'p1', cantidad: 1)],
      );

      final ron = filas.firstWhere((f) => f.productoId == 'p2');
      expect(ron.unidades, equals(0));
      expect(ron.ingresos, equals(0));
      expect(ron.costo, equals(0));
      expect(ron.sinVentas, isTrue);
    });

    test('Ignora líneas de productos que no se pidieron', () {
      final filas = agruparUtilidadPorProducto(
        [producto(id: 'p1', nombre: 'Aguardiente')],
        [
          linea(productoId: 'p1', cantidad: 1),
          linea(productoId: 'otro', cantidad: 99),
        ],
      );

      expect(filas, hasLength(1));
      expect(filas.single.unidades, equals(1));
    });

    test('Ordena de mayor a menor utilidad', () {
      final filas = agruparUtilidadPorProducto(
        [
          producto(id: 'p1', nombre: 'Poca'),
          producto(id: 'p2', nombre: 'Mucha'),
        ],
        [
          linea(productoId: 'p1', cantidad: 1),
          linea(productoId: 'p2', cantidad: 10),
        ],
      );

      expect(filas.map((f) => f.productoId), equals(['p2', 'p1']));
    });
  });
}
