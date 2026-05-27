DateTime? parseDateTime(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

DateTime parseRequiredDate(Object? value) {
  if (value == null) {
    throw FormatException('Expected a date value, got null');
  }

  return DateTime.parse(value.toString());
}

num parseNum(Object? value, [num fallback = 0]) {
  if (value == null) return fallback;
  if (value is num) return value;
  return num.tryParse(value.toString()) ?? fallback;
}

int parseInt(Object? value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

String? dateOnly(DateTime? value) {
  if (value == null) return null;
  return value.toIso8601String().split('T').first;
}
