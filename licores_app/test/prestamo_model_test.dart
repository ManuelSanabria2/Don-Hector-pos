import 'package:flutter_test/flutter_test.dart';
import 'package:licores_app/data/models/pago_prestamo.dart';
import 'package:licores_app/data/models/prestamo.dart';
import 'package:licores_app/data/models/venta_enums.dart';

void main() {
  group('Prestamo', () {
    // PostgREST devuelve los numeric como String, no como número.
    Map<String, dynamic> fila({
      String monto = '1000000.000',
      String capitalPagado = '120000.000',
      String saldo = '880000.000',
      String interesPagado = '30000.000',
      Object? tasa = '2.500',
      String tipo = 'banco',
      String estado = 'parcial',
    }) {
      return {
        'id': 'prestamo-1',
        'acreedor': 'Banco Prueba',
        'tipo': tipo,
        'monto': monto,
        'capital_pagado': capitalPagado,
        'saldo': saldo,
        'interes_pagado': interesPagado,
        'tasa_interes': tasa,
        'metodo_pago': 'efectivo',
        'estado': estado,
        'fecha': '2026-08-08T10:00:00Z',
        'notas': null,
        'created_at': '2026-08-08T10:00:00Z',
      };
    }

    test('Parsea los numeric que llegan como texto', () {
      final p = Prestamo.fromJson(fila());

      expect(p.monto, equals(1000000));
      expect(p.capitalPagado, equals(120000));
      expect(p.saldo, equals(880000));
      expect(p.interesPagado, equals(30000));
      expect(p.tasaInteres, equals(2.5));
      expect(p.tipo, equals(TipoPrestamo.banco));
      expect(p.estado, equals(EstadoCobro.parcial));
      expect(p.metodoPago, equals(MetodoPago.efectivo));
    });

    test('La tasa de interes es opcional', () {
      final p = Prestamo.fromJson(fila(tasa: null));
      expect(p.tasaInteres, isNull);
    });

    test('estaPagado depende del saldo, no del interes', () {
      final pagado = Prestamo.fromJson(
        fila(capitalPagado: '1000000.000', saldo: '0.000', estado: 'pagado'),
      );
      expect(pagado.estaPagado, isTrue);
      // Haber pagado intereses no deja el prestamo pendiente.
      expect(pagado.interesPagado, greaterThan(0));

      expect(Prestamo.fromJson(fila()).estaPagado, isFalse);
    });

    test('Un tipo desconocido no revienta el parseo', () {
      final p = Prestamo.fromJson(fila(tipo: 'cooperativa'));
      expect(p.tipo, equals(TipoPrestamo.prestamista));
    });
  });

  group('PagoPrestamo', () {
    test('Separa abono a capital de interes, y el total es la suma', () {
      final pago = PagoPrestamo.fromJson({
        'id': 'pago-1',
        'prestamo_id': 'prestamo-1',
        'abono_capital': '120000.000',
        'interes': '30000.000',
        'monto': '150000.000',
        'metodo_pago': 'efectivo',
        'fecha': '2026-08-08T12:00:00Z',
        'notas': null,
      });

      expect(pago.abonoCapital, equals(120000));
      expect(pago.interes, equals(30000));
      // Lo que salio de la caja es la cuota completa.
      expect(pago.monto, equals(150000));
      expect(pago.abonoCapital + pago.interes, equals(pago.monto));
    });

    test('Una cuota de solo interes no abona a capital', () {
      final pago = PagoPrestamo.fromJson({
        'id': 'pago-2',
        'prestamo_id': 'prestamo-1',
        'abono_capital': '0.000',
        'interes': '5000.000',
        'monto': '5000.000',
        'metodo_pago': 'efectivo',
        'fecha': '2026-08-08T12:00:00Z',
        'notas': null,
      });

      expect(pago.abonoCapital, equals(0));
      expect(pago.monto, equals(5000));
    });
  });
}
