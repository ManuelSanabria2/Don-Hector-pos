import 'package:intl/intl.dart';

abstract final class DateFormatter {
  static final DateFormat _date = DateFormat('dd/MM/yyyy', 'es_CO');
  static final DateFormat _dateTime = DateFormat('dd/MM/yyyy HH:mm', 'es_CO');

  static String date(DateTime value) => _date.format(value);

  static String dateTime(DateTime value) => _dateTime.format(value);
}
