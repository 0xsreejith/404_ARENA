import 'package:arena_os/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

/// Currency is never hardcoded in the product (D31); these are test literals.
const String inr = 'INR';
const String usd = 'USD';

void main() {
  group('Money.parse — the numeric(12,2) wire format', () {
    test('parses whole and fractional amounts to minor units', () {
      expect(Money.parse('0.00', inr).minorUnits, 0);
      expect(Money.parse('120.00', inr).minorUnits, 12000);
      expect(Money.parse('120.50', inr).minorUnits, 12050);
      expect(Money.parse('0.01', inr).minorUnits, 1);
      expect(Money.parse('99999999.99', inr).minorUnits, 9999999999);
    });

    test('accepts an absent or short fractional part', () {
      expect(Money.parse('150', inr).minorUnits, 15000);
      expect(Money.parse('150.5', inr).minorUnits, 15050);
    });

    test('accepts signs and surrounding whitespace', () {
      expect(Money.parse('-45.76', inr).minorUnits, -4576);
      expect(Money.parse('+45.76', inr).minorUnits, 4576);
      expect(Money.parse('  22.88  ', inr).minorUnits, 2288);
    });

    test('never routes through double: 0.1 + 0.2 is exactly 0.30', () {
      final sum = Money.parse('0.10', inr) + Money.parse('0.20', inr);
      expect(sum.minorUnits, 30);
      expect(sum.toDecimalString(), '0.30');
      // The double equivalent is 0.30000000000000004; this must not be.
      expect(sum.toDecimalString(), isNot(contains('000000')));
    });

    test('holds a value that double cannot represent exactly', () {
      // 8,388,608.01 is beyond float32 integer precision and lossy as a
      // decimal in float64 arithmetic chains.
      final money = Money.parse('8388608.01', inr);
      expect(money.minorUnits, 838860801);
      expect(money.toDecimalString(), '8388608.01');
    });

    test('rejects more precision than the column can hold', () {
      expect(() => Money.parse('10.005', inr), throwsA(isA<MoneyFormatException>()));
    });

    test('rejects malformed input rather than guessing', () {
      for (final bad in <String>[
        '',
        '   ',
        '-',
        '.',
        '.50',
        '10.',
        'abc',
        '1,234.00',
        '1e3',
        '10.0.0',
        '₹10.00',
        '10 00',
      ]) {
        expect(
          () => Money.parse(bad, inr),
          throwsA(isA<MoneyFormatException>()),
          reason: 'should reject "$bad"',
        );
      }
    });
  });

  group('Money.tryParseNullable', () {
    test('passes null through for nullable columns', () {
      expect(Money.tryParseNullable(null, inr), isNull);
    });

    test('parses a string', () {
      expect(Money.tryParseNullable('12.34', inr)!.minorUnits, 1234);
    });

    test('rejects a double outright', () {
      expect(() => Money.tryParseNullable(12.34, inr), throwsA(isA<MoneyFormatException>()));
    });
  });

  group('arithmetic', () {
    test('adds, subtracts, negates, and scales by a whole number', () {
      final a = Money.parse('150.00', inr);
      final b = Money.parse('45.76', inr);
      expect((a + b).toDecimalString(), '195.76');
      expect((a - b).toDecimalString(), '104.24');
      expect((-b).toDecimalString(), '-45.76');
      expect((b * 3).toDecimalString(), '137.28');
    });

    test('refuses to mix currencies', () {
      final rupees = Money.parse('10.00', inr);
      final dollars = Money.parse('10.00', usd);
      expect(() => rupees + dollars, throwsA(isA<CurrencyMismatchException>()));
      expect(() => rupees - dollars, throwsA(isA<CurrencyMismatchException>()));
      expect(() => rupees.compareTo(dollars), throwsA(isA<CurrencyMismatchException>()));
    });

    test('compares within a currency', () {
      final small = Money.parse('10.00', inr);
      final large = Money.parse('10.01', inr);
      expect(small < large, isTrue);
      expect(large > small, isTrue);
      expect(small <= Money.parse('10.00', inr), isTrue);
      expect(small >= Money.parse('10.00', inr), isTrue);
    });

    test('equality includes the currency', () {
      expect(Money.parse('1.00', inr), Money.parse('1.00', inr));
      expect(Money.parse('1.00', inr), isNot(Money.parse('1.00', usd)));
      expect(Money.parse('1.00', inr).hashCode, Money.parse('1.00', inr).hashCode);
    });
  });

  group('formatting', () {
    test('round-trips through the wire format', () {
      for (final source in <String>['0.00', '0.07', '150.00', '-45.76', '99999999.99']) {
        expect(Money.parse(source, inr).toDecimalString(), source);
      }
    });

    test('pads the fraction back to two places', () {
      expect(Money.parse('150.5', inr).toDecimalString(), '150.50');
      expect(Money.parse('150', inr).toDecimalString(), '150.00');
    });

    test('groups thousands', () {
      expect(Money.parse('1234567.89', inr).toGroupedString(), '1,234,567.89');
      expect(Money.parse('999.99', inr).toGroupedString(), '999.99');
      expect(Money.parse('-1234.50', inr).toGroupedString(), '-1,234.50');
    });

    test('zero and sign helpers', () {
      expect(Money.zero(inr).isZero, isTrue);
      expect(Money.parse('-0.01', inr).isNegative, isTrue);
      expect(Money.parse('0.01', inr).isPositive, isTrue);
    });
  });

  group('documented vectors from DATABASE.md §16.5', () {
    // These assert only that Money can carry the published figures exactly.
    // The computation itself is server-side (D05) and is proved by pgTAP.
    test('T1 — a 150.00 inclusive line splits to 127.12 + 22.88', () {
      final total = Money.parse('150.00', inr);
      final taxable = Money.parse('127.12', inr);
      final tax = Money.parse('22.88', inr);
      expect(taxable + tax, total);
    });

    test('T2 — components 7.63 + 7.62 sum exactly to 15.25', () {
      final cgst = Money.parse('7.63', inr);
      final sgst = Money.parse('7.62', inr);
      expect((cgst + sgst).toDecimalString(), '15.25');
    });

    test('T3 — two lines reconcile to the order total', () {
      final play = Money.parse('135.00', inr);
      final product = Money.parse('90.00', inr);
      expect((play + product).toDecimalString(), '225.00');
    });
  });
}
