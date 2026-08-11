import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licores_app/data/models/producto.dart';
import 'package:licores_app/data/models/utilidad_producto.dart';
import 'package:licores_app/features/contabilidad/contabilidad_providers.dart';
import 'package:licores_app/features/contabilidad/utilidad_producto_tab.dart';

Producto _producto(String id, String nombre) => Producto(
      id: id,
      nombre: nombre,
      precioPublico: 5000,
      precioMayorista: 4000,
      costo: 2000,
      stockActual: 10,
      stockMinimo: 5,
    );

/// Monta la pestaña con la selección y el resultado ya resueltos, para probar
/// lo que se pinta sin tocar la red.
Future<void> _montar(
  WidgetTester tester, {
  required List<Producto> seleccion,
  required List<UtilidadProducto> filas,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        utilidadProductosSeleccionadosProvider.overrideWith((ref) => seleccion),
        utilidadPorProductoSemanaProvider.overrideWith((ref) async => filas),
      ],
      child: const MaterialApp(
        home: Scaffold(body: UtilidadProductoTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('UtilidadProductoTab', () {
    testWidgets('Sin selección invita a elegir productos', (tester) async {
      await _montar(tester, seleccion: const [], filas: const []);

      expect(find.textContaining('Elige uno o varios productos'), findsOneWidget);
      expect(find.text('Elegir productos'), findsOneWidget);
      expect(find.textContaining('Últimos $diasSemanaUtilidad días'),
          findsOneWidget);
    });

    testWidgets('Muestra métricas y total de la selección', (tester) async {
      await _montar(
        tester,
        seleccion: [_producto('p1', 'AGUILA 269'), _producto('p2', 'CORONITA')],
        filas: const [
          UtilidadProducto(
            productoId: 'p1',
            nombre: 'AGUILA 269',
            unidades: 276,
            ingresos: 874092,
            costo: 538712,
          ),
          UtilidadProducto(
            productoId: 'p2',
            nombre: 'CORONITA',
            unidades: 210,
            ingresos: 787500,
            costo: 576700,
          ),
        ],
      );

      expect(find.text('AGUILA 269'), findsWidgets);
      expect(find.text('CORONITA'), findsWidgets);

      // Utilidad por producto: 874092-538712 y 787500-576700.
      expect(find.text('\$ 335.380'), findsOneWidget);
      expect(find.text('\$ 210.800'), findsOneWidget);
      // Y el total de la selección: la suma de ambas.
      expect(find.text('Utilidad total de la selección'), findsOneWidget);
      expect(find.text('\$ 546.180'), findsOneWidget);

      // Las unidades se listan por producto.
      expect(find.text('276'), findsOneWidget);
      expect(find.text('210'), findsOneWidget);
      // El botón refleja cuántos hay elegidos.
      expect(find.text('Elegir (2)'), findsOneWidget);
    });

    testWidgets('Un producto sin ventas se muestra en ceros, no desaparece',
        (tester) async {
      await _montar(
        tester,
        seleccion: [_producto('p1', 'RON SIN VENTAS')],
        filas: const [
          UtilidadProducto(
            productoId: 'p1',
            nombre: 'RON SIN VENTAS',
            unidades: 0,
            ingresos: 0,
            costo: 0,
          ),
        ],
      );

      expect(find.text('RON SIN VENTAS'), findsWidgets);
      expect(find.text('Sin ventas en el período'), findsOneWidget);
    });

    testWidgets('Una utilidad negativa se pinta en rojo', (tester) async {
      await _montar(
        tester,
        seleccion: [_producto('p1', 'VENDIDO A PÉRDIDA')],
        filas: const [
          UtilidadProducto(
            productoId: 'p1',
            nombre: 'VENDIDO A PÉRDIDA',
            unidades: 2,
            ingresos: 1000,
            costo: 3000,
          ),
        ],
      );

      final texto = tester.widget<Text>(find.text('\$ -2.000').first);
      expect(texto.style?.color, equals(const Color(0xFFE57373)));
    });
  });
}
