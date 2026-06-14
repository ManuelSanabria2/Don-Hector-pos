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
    decimalDigits: 2,
  );

  static String cop(num value) {
    if (value % 1 != 0) {
      return '\$ ${_copNumberDec.format(value).trim()}';
    }
    return '\$ ${_copNumber.format(value).trim()}';
  }

  static String copNumberOnly(num value, {bool allowDecimals = false}) {
    if (allowDecimals || value % 1 != 0) {
      return _copNumberDec.format(value).trim();
    }
    return _copNumber.format(value).trim();
  }

  static num parseCop(String value) {
    String clean = value.trim();
    if (clean.contains(',')) {
      final parts = clean.split(',');
      final intPart = parts[0].replaceAll('.', '');
      final decPart = parts.length > 1 ? parts[1] : '';
      return double.tryParse('$intPart.$decPart') ?? 0;
    } else {
      final digits = clean.replaceAll(RegExp(r'[^0-9]'), '');
      return num.tryParse(digits) ?? 0;
    }
  }
}

String formatCOP(double monto) {
  return CurrencyFormatter.cop(monto);
}

class CopInputFormatter extends TextInputFormatter {
  final bool allowDecimals;
  CopInputFormatter({this.allowDecimals = false});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return const TextEditingValue();
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
