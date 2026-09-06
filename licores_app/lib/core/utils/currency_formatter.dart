import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

abstract final class CurrencyFormatter {
  static final NumberFormat _copNumber = NumberFormat.currency(
    locale: 'es_CO',
    symbol: '',
    decimalDigits: 0,
  );

  static final NumberFormat _copNumberDec = NumberFormat.currency(
    locale: 'es_CO',
    symbol: '',
    decimalDigits: 3,
  );

  static String cop(num value) {
    final rounded = value.round();
    return '\$ ${_copNumber.format(rounded).trim()}';
  }

  static String copNumberOnly(num value, {bool allowDecimals = false}) {
    if (allowDecimals) {
      final valStr = value.toString();
      if (valStr.contains('.')) {
        final parts = valStr.split('.');
        final intPart = num.parse(parts[0]);
        final formattedInt = _copNumber.format(intPart).trim();
        final decPart = parts[1];
        return '$formattedInt,$decPart';
      }
      return _copNumber.format(value).trim();
    }
    final rounded = value.round();
    return _copNumber.format(rounded).trim();
  }

  /// Un menos al principio se conserva: los campos que aceptan
  /// descuentos (ajustar factura) escriben montos negativos. En los
  /// campos que no los aceptan nunca llega el signo, porque
  /// [CopInputFormatter] solo lo deja pasar si se lo piden.
  static num parseCop(String value) {
    String clean = value.trim();
    final esNegativo = clean.startsWith('-');
    final signo = esNegativo ? -1 : 1;

    if (clean.contains(',')) {
      final parts = clean.split(',');
      final intPart = parts[0].replaceAll(RegExp(r'[^0-9]'), '');
      final decPart = parts.length > 1 ? parts[1].replaceAll(RegExp(r'[^0-9]'), '') : '';
      final parsedDouble = double.tryParse('${intPart.isEmpty ? '0' : intPart}.${decPart.isEmpty ? '0' : decPart}') ?? 0;
      return signo * parsedDouble.round();
    } else {
      final digits = clean.replaceAll(RegExp(r'[^0-9]'), '');
      final parsedNum = num.tryParse(digits) ?? 0;
      return signo * parsedNum.round();
    }
  }
}

String formatCOP(double monto) {
  return CurrencyFormatter.cop(monto);
}

class CopInputFormatter extends TextInputFormatter {
  final bool allowDecimals;

  /// Deja escribir un menos al principio. Solo lo activan los campos
  /// donde un negativo significa algo, como el descuento de una
  /// factura; en el resto el signo se sigue descartando.
  final bool allowNegative;

  CopInputFormatter({this.allowDecimals = false, this.allowNegative = false});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return const TextEditingValue();
    }

    if (allowNegative) {
      // El menos se aparta antes de formatear y se vuelve a pegar al
      // final: así el formateo de miles no tiene que saber del signo.
      final negativo = newValue.text.contains('-');
      final sinSigno = newValue.text.replaceAll('-', '');

      if (sinSigno.isEmpty) {
        // Solo el menos: es un estado válido mientras sigue escribiendo.
        return negativo
            ? const TextEditingValue(
                text: '-',
                selection: TextSelection.collapsed(offset: 1),
              )
            : const TextEditingValue();
      }

      final cuerpo = CopInputFormatter(allowDecimals: allowDecimals)
          .formatEditUpdate(oldValue, newValue.copyWith(text: sinSigno));

      if (!negativo) return cuerpo;

      final texto = '-${cuerpo.text}';
      return TextEditingValue(
        text: texto,
        selection: TextSelection.collapsed(offset: texto.length),
      );
    }

    if (!allowDecimals) {
      final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) {
        return const TextEditingValue();
      }
      final formatted = CurrencyFormatter.copNumberOnly(num.parse(digits));
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    } else {
      String txt = newValue.text;
      
      // Auto-convert dot to comma at the end for decimal typing
      if (txt.endsWith('.') && !txt.substring(0, txt.length - 1).contains(',')) {
        txt = txt.substring(0, txt.length - 1) + ',';
      }
      
      txt = txt.replaceAll('.', '');
      txt = txt.replaceAll(RegExp(r'[^0-9,]'), '');
      
      final parts = txt.split(',');
      if (parts.length > 2) {
        txt = '${parts[0]},${parts.sublist(1).join('')}';
      }
      
      if (txt.isEmpty) {
        return const TextEditingValue();
      }
      
      final commaIndex = txt.indexOf(',');
      if (commaIndex == -1) {
        final formattedInt = CurrencyFormatter.copNumberOnly(num.parse(txt));
        return TextEditingValue(
          text: formattedInt,
          selection: TextSelection.collapsed(offset: formattedInt.length),
        );
      } else {
        final intPart = txt.substring(0, commaIndex);
        final decPart = txt.substring(commaIndex + 1);
        
        final formattedInt = intPart.isEmpty ? '0' : CurrencyFormatter.copNumberOnly(num.parse(intPart));
        final truncatedDec = decPart.length > 2 ? decPart.substring(0, 2) : decPart;
        
        final formatted = '$formattedInt,$truncatedDec';
        return TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    }
  }
}
