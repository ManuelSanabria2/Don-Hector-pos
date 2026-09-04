import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licores_app/data/models/rebate_proveedor.dart';
import 'package:licores_app/features/compras/compras_providers.dart';
import 'package:licores_app/features/compras/rebates_screen.dart';

RebateProveedor _movimiento(String tipo, num monto) => RebateProveedor(
      id: 'r-$tipo',
      proveedorId: 'p1',
      nombreProveedor: 'Bavaria',
      fecha: DateTime(2026, 9, 1),
      tipo: tipo,
      monto: monto,
    );

SaldoRebateProveedor _saldo({
  required num acumulado,
  required num canjeado,
}) =>
    SaldoRebateProveedor(
      proveedorId: 'p1',
      proveedor: 'Bavaria',
      acumulado: acumulado,
      ajustado: 0,
      canjeado: canjeado,
      vencido: 0,
      saldo: acumulado - canjeado,
    );

Future<void> _montarPantalla(
  WidgetTester tester, {
  required List<SaldoRebateProveedor> saldos,
  required List<RebateProveedor> movimientos,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        saldosRebatesProvider.overrideWith((ref) async => saldos),
        movimientosRebateProvider.overrideWith((ref, _) async => movimientos),
      ],
      child: const MaterialApp(home: RebatesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('RebateProveedor', () {
    test('El tipo pone el signo, no el monto', () {
      expect(_movimiento(RebateProveedor.tipoAcumulacion, 50000).montoConSigno,
          50000);
      expect(_movimiento(RebateProveedor.tipoAjuste, 5000).montoConSigno, 5000);
      expect(_movimiento(RebateProveedor.tipoCanje, 30000).montoConSigno,
          -30000);
      expect(_movimiento(RebateProveedor.tipoVencimiento, 1000).montoConSigno,
          -1000);
    });

    test('Lee el nombre del proveedor del join de Supabase', () {
      final mov = RebateProveedor.fromJson({
        'id': 'r1',
        'proveedor_id': 'p1',
        'fecha': '2026-09-01',
        'tipo': 'acumulacion',
        'monto': '50000.000',
        'proveedores': {'nombre': 'Bavaria'},
      });

      expect(mov.nombreProveedor, 'Bavaria');
      expect(mov.monto, 50000);
      expect(mov.compraId, isNull);
    });
  });

  group('SaldoRebateProveedor', () {
    test('Un saldo consumido por completo deja de estar disponible', () {
      final saldo = _saldo(acumulado: 80000, canjeado: 80000);
      expect(saldo.saldo, 0);
      expect(saldo.tieneSaldo, isFalse);
    });
  });

  group('RebatesScreen', () {
    testWidgets('Sin saldos explica el mecanismo igual', (tester) async {
      await _montarPantalla(tester, saldos: const [], movimientos: const []);

      expect(find.textContaining('Ningún proveedor tiene saldo'), findsOneWidget);
      expect(find.textContaining('solo se canjea en mercancía'), findsOneWidget);
      expect(find.textContaining('Todavía no hay movimientos'), findsOneWidget);
    });

    testWidgets('Muestra el saldo vivo y sus movimientos', (tester) async {
      await _montarPantalla(
        tester,
        saldos: [_saldo(acumulado: 80000, canjeado: 30000)],
        movimientos: [
          _movimiento(RebateProveedor.tipoAcumulacion, 80000),
          _movimiento(RebateProveedor.tipoCanje, 30000),
        ],
      );

      expect(find.text('Bavaria'), findsOneWidget);
      expect(find.textContaining('disponible'), findsOneWidget);
      expect(find.textContaining('Acumulación'), findsWidgets);
      expect(find.textContaining('Canje'), findsWidgets);
    });

    testWidgets('Un proveedor sin saldo no ocupa la lista', (tester) async {
      await _montarPantalla(
        tester,
        saldos: [_saldo(acumulado: 40000, canjeado: 40000)],
        movimientos: const [],
      );

      expect(find.text('Bavaria'), findsNothing);
      expect(find.textContaining('Ningún proveedor tiene saldo'), findsOneWidget);
    });
  });
}
