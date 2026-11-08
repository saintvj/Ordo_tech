/// Money is stored as integer paise to avoid floating-point drift.
library;

final _rupeesPattern = RegExp(r'^(\d{1,7})(?:\.(\d{1,2}))?$');

/// Formats paise as a rupee amount with two decimals, e.g. `₹120.50`.
String formatRupees(int paise) {
  final sign = paise < 0 ? '-' : '';
  final abs = paise.abs();
  return '$sign₹${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}

/// Formats paise for an editable price field, e.g. `120` or `120.5`.
String rupeesInputText(int paise) {
  final rupees = paise ~/ 100;
  final fraction = paise % 100;
  if (fraction == 0) return '$rupees';
  return '$rupees.${fraction.toString().padLeft(2, '0')}';
}

/// Parses user input such as `120`, `120.5` or `120.50` into paise.
///
/// Returns null for anything that is not a non-negative amount with at most
/// two decimal places.
int? parseRupees(String input) {
  final match = _rupeesPattern.firstMatch(input.trim());
  if (match == null) return null;
  final rupees = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return rupees * 100 + int.parse(fraction);
}

/// Returns [basisPoints] (1% = 100 bp) of a non-negative [paise] amount,
/// rounded half-up to the nearest paisa.
int percentOf(int paise, int basisPoints) =>
    (paise * basisPoints + 5000) ~/ 10000;
