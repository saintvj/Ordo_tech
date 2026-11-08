import 'package:flutter_test/flutter_test.dart';
import 'package:ordo/domain/money.dart';

void main() {
  group('formatRupees', () {
    test('formats paise with two decimals', () {
      expect(formatRupees(0), '₹0.00');
      expect(formatRupees(5), '₹0.05');
      expect(formatRupees(12050), '₹120.50');
      expect(formatRupees(-250), '-₹2.50');
    });
  });

  group('parseRupees', () {
    test('accepts whole and decimal amounts', () {
      expect(parseRupees('120'), 12000);
      expect(parseRupees(' 120.5 '), 12050);
      expect(parseRupees('120.05'), 12005);
      expect(parseRupees('0'), 0);
    });

    test('rejects invalid input', () {
      for (final input in ['', 'abc', '-5', '1.234', '1,000', '.5', '12.']) {
        expect(parseRupees(input), isNull, reason: input);
      }
    });

    test('round-trips through rupeesInputText', () {
      for (final paise in [100, 12050, 12005, 99999]) {
        expect(parseRupees(rupeesInputText(paise)), paise);
      }
    });
  });

  group('percentOf', () {
    test('rounds half up to the nearest paisa', () {
      expect(percentOf(10000, 250), 250);
      expect(percentOf(5020, 250), 126); // 125.5 rounds up
      expect(percentOf(5000, 250), 125);
      expect(percentOf(0, 250), 0);
    });
  });
}
