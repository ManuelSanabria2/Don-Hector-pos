import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licores_app/core/utils/currency_formatter.dart';

/// Simula lo que hace el campo de texto: pasa el valor nuevo por el
/// formateador y devuelve lo que quedaría escrito.
String _escribir(CopInputFormatter formatter, String texto) {
  return formatter
      .formatEditUpdate(
        const TextEditingValue(),
        TextEditingValue(
          text: texto,
          selection: TextSelection.collapsed(offset: texto.length),
        ),
      )
      .text;
}

void main() {
  group('parseCop', () {
    test('Lee montos positivos con separador de miles', () {
      expect(CurrencyFormatter.parseCop('338.416'), 338416);
      expect(CurrencyFormatter.parseCop('1.495.890'), 1495890);
      expect(CurrencyFormatter.parseCop(''), 0);
    });

    test('Conserva el signo de un descuento', () {
      expect(CurrencyFormatter.parseCop('-338.416'), -338416);
      expect(CurrencyFormatter.parseCop('-1.000'), -1000);
    });

    test('Respeta el signo con decimales', () {
      expect(CurrencyFormatter.parseCop('-1.000,50'), -1001);
      expect(CurrencyFormatter.parseCop('1.000,50'), 1001);
    });
  });

  group('CopInputFormatter sin negativos', () {
    final formatter = CopInputFormatter();

    test('Formatea los miles mientras se escribe', () {
      expect(_escribir(formatter, '338416'), '338.416');
    });

    test('Descarta el menos: en esos campos no significa nada', () {
      expect(_escribir(formatter, '-338416'), '338.416');
    });
  });

  group('CopInputFormatter con negativos', () {
    final formatter = CopInputFormatter(allowDecimals: true, allowNegative: true);

    test('Deja escribir un descuento y le formatea los miles', () {
      expect(_escribir(formatter, '-338416'), '-338.416');
    });

    test('Un monto positivo se sigue formateando igual', () {
      expect(_escribir(formatter, '338416'), '338.416');
    });

    test('El menos solo es un estado válido mientras escribe', () {
      expect(_escribir(formatter, '-'), '-');
    });

    test('Lo que escribe vuelve a salir del parseo con su signo', () {
      final texto = _escribir(formatter, '-338416');
      expect(CurrencyFormatter.parseCop(texto), -338416);
    });
  });
}
