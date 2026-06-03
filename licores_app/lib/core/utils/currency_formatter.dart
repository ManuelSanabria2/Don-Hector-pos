import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

abstract final class CurrencyFormatter {
  static final NumberFormat _copNumber = NumberFormat.currency(
    locale: 'es_CO',
    symbol: '',
    decimalDigits: 0,
  );

  static String cop(num value) => '\$ ${_copNumber.format(value).trim()}';

  static String copNumberOnly(num value) => _copNumber.format(value).trim();

  static num parseCop(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    return num.tryParse(digits) ?? 0;
  }
}

String formatCOP(double monto) {
  return CurrencyFormatter.cop(monto);
}


class CopInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue();
    }

    final formatted = CurrencyFormatter.copNumberOnly(num.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
