import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licores_app/data/models/cliente_mayorista.dart';
import 'package:licores_app/features/mayoristas/mayoristas_providers.dart';
import 'package:licores_app/features/mayoristas/mayoristas_screen.dart';

/// Nombres reales de la base, los más largos que hay.
const _nombreLargo = 'CORATIENDAS SAN LUIS- DON SALOMÓN';

ClienteConCuenta _item({
  String nombre = _nombreLargo,
  num deuda = 0,
}) {
  return ClienteConCuenta(
    cliente: ClienteMayorista(id: 'c1', nombre: nombre, activo: true),
    deudaPendiente: deuda,
    totalCompras: 0,
    totalPagado: 0,
    numPedidos: 0,
  );
}

/// Monta la tarjeta en un ancho de celular angosto, que es donde el
/// nombre se recortaba.
Future<void> _montar(WidgetTester tester, ClienteConCuenta item) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [ClienteCard(item: item)],
        ),
      ),
    ),
  );
}

void main() {
  group('ClienteCard', () {
    testWidgets('Muestra el nombre largo completo, sin recortarlo',
        (tester) async {
      await _montar(tester, _item(deuda: 1250000));

      // El texto se pinta entero: si se recortara, el Text no lo contendria.
      expect(find.text(_nombreLargo), findsOneWidget);

      final titulo = tester.widget<Text>(find.text(_nombreLargo));
      // Dos lineas es lo que permite que quepa completo.
      expect(titulo.maxLines, equals(2));
      expect(titulo.overflow, equals(TextOverflow.ellipsis));
    });

    testWidgets('El nombre no comparte fila con el chip de cobro',
        (tester) async {
      await _montar(tester, _item(deuda: 1250000));

      final anchoNombre = tester.getSize(find.text(_nombreLargo)).width;
      final anchoChip = tester.getSize(find.text('Cobro pendiente')).width;

      // Antes competian por la misma fila; ahora el chip esta abajo, asi
      // que el nombre es mucho mas ancho que el.
      expect(anchoNombre, greaterThan(anchoChip));

      // Y estan en lineas distintas.
      final yNombre = tester.getTopLeft(find.text(_nombreLargo)).dy;
      final yChip = tester.getTopLeft(find.text('Cobro pendiente')).dy;
      expect(yChip, greaterThan(yNombre));
    });

    testWidgets('Sigue mostrando la deuda y el estado', (tester) async {
      await _montar(tester, _item(deuda: 1250000));

      expect(find.textContaining('Debe'), findsOneWidget);
      expect(find.text('Cobro pendiente'), findsOneWidget);
    });

    testWidgets('Un cliente sin deuda no muestra el chip', (tester) async {
      await _montar(tester, _item(deuda: 0));

      expect(find.text(_nombreLargo), findsOneWidget);
      expect(find.text('Sin deuda pendiente'), findsOneWidget);
      expect(find.text('Cobro pendiente'), findsNothing);
    });

    testWidgets('Un nombre corto se sigue viendo bien', (tester) async {
      await _montar(tester, _item(nombre: 'Ana', deuda: 5000));

      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Cobro pendiente'), findsOneWidget);
    });

    testWidgets('El nombre largo usa el ancho de la tarjeta, no una columna '
        'angosta', (tester) async {
      await _montar(tester, _item(nombre: 'Ana', deuda: 5000));
      final altoCorto = tester.getSize(find.text('Ana')).height;

      await _montar(tester, _item(deuda: 5000));
      final tamLargo = tester.getSize(find.text(_nombreLargo));

      // Ocupa dos lineas (no una sola recortada, ni muchas apretadas).
      expect(tamLargo.height, greaterThan(altoCorto));
      expect(tamLargo.height, lessThan(altoCorto * 3));

      // Y ocupa casi todo el espacio disponible del tile. El resto lo
      // consumen el avatar, la flecha y los margenes; lo que ya NO se lo
      // come es el chip, que antes le quitaba ~110px.
      final anchoTarjeta = tester.getSize(find.byType(Card)).width;
      expect(tamLargo.width, greaterThan(anchoTarjeta * 0.45));
    });
  });
}
