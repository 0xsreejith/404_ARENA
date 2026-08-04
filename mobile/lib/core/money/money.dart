/// Raised when a string cannot be read as a money amount.
class MoneyFormatException implements Exception {
  const MoneyFormatException(this.input, this.reason);

  final String input;
  final String reason;

  @override
  String toString() => 'MoneyFormatException("$input"): $reason';
}

/// Raised when two amounts in different currencies are combined.
class CurrencyMismatchException implements Exception {
  const CurrencyMismatchException(this.left, this.right);

  final String left;
  final String right;

  @override
  String toString() => 'CurrencyMismatchException: cannot combine $left and $right';
}

/// A monetary amount held as an integer number of **minor units** (D01).
///
/// PostgreSQL stores money as `numeric(12,2)`; the Supabase client hands that
/// back as a **string**. [parse] converts that string straight to an integer
/// without ever going through binary floating point, which cannot represent
/// most decimal amounts exactly and whose error compounds across an order's
/// lines.
///
/// P0 assumes a two-decimal minor unit for every supported currency (D01), so
/// a rupee price of `"120.50"` is 12050 paise. The currency code itself always
/// comes from `arenas.currency` and is never hardcoded (D31).
///
/// This type carries no tax behaviour. Whether a price is tax-inclusive is an
/// arena setting (D32) applied server-side; Flutter only ever displays what the
/// server computed (D05).
class Money implements Comparable<Money> {
  /// Constructs from an already-integral minor-unit amount.
  const Money.fromMinorUnits(this.minorUnits, this.currency);

  /// Zero in [currency].
  const Money.zero(this.currency) : minorUnits = 0;

  /// The amount in minor units. Negative for credits and reversals.
  final int minorUnits;

  /// ISO 4217 code, taken from `arenas.currency`. Never hardcoded (D31).
  final String currency;

  /// Digits after the decimal point. Fixed at 2 for P0 (D01).
  static const int decimalPlaces = 2;
  static const int _scale = 100;

  /// Parses a decimal string exactly as PostgreSQL `numeric(12,2)` emits it.
  ///
  /// Accepts an optional sign, an integer part, and at most
  /// [decimalPlaces] fractional digits. Rejects anything else — including
  /// exponent notation and extra precision — rather than silently rounding,
  /// because a money value that needed rounding at the boundary means the
  /// server sent something this client does not understand.
  static Money parse(String source, String currency) {
    final text = source.trim();
    if (text.isEmpty) {
      throw const MoneyFormatException('', 'empty string');
    }

    var index = 0;
    var negative = false;
    final first = text.codeUnitAt(0);
    if (first == 0x2D /* - */ || first == 0x2B /* + */ ) {
      negative = first == 0x2D;
      index = 1;
    }
    if (index >= text.length) {
      throw MoneyFormatException(source, 'sign with no digits');
    }

    final rest = text.substring(index);
    final dot = rest.indexOf('.');
    final whole = dot == -1 ? rest : rest.substring(0, dot);
    final fraction = dot == -1 ? '' : rest.substring(dot + 1);

    if (whole.isEmpty) {
      throw MoneyFormatException(source, 'missing integer part');
    }
    if (!_isAsciiDigits(whole)) {
      throw MoneyFormatException(source, 'integer part is not decimal digits');
    }
    if (dot != -1) {
      if (fraction.isEmpty) {
        throw MoneyFormatException(source, 'trailing decimal point');
      }
      if (!_isAsciiDigits(fraction)) {
        throw MoneyFormatException(source, 'fractional part is not decimal digits');
      }
      if (fraction.length > decimalPlaces) {
        throw MoneyFormatException(
          source,
          'more than $decimalPlaces decimal places; refusing to round at the '
          'transport boundary',
        );
      }
    }

    final padded = fraction.padRight(decimalPlaces, '0');
    final wholeUnits = int.tryParse(whole);
    final fractionUnits = int.tryParse(padded);
    if (wholeUnits == null || fractionUnits == null) {
      throw MoneyFormatException(source, 'value out of integer range');
    }

    final magnitude = wholeUnits * _scale + fractionUnits;
    return Money.fromMinorUnits(negative ? -magnitude : magnitude, currency);
  }

  /// Parses a value that may legitimately be absent, e.g. a nullable column.
  static Money? tryParseNullable(Object? source, String currency) {
    if (source == null) return null;
    if (source is String) return parse(source, currency);
    if (source is int) return Money.fromMinorUnits(source * _scale, currency);
    throw MoneyFormatException(
      '$source',
      'unsupported runtime type ${source.runtimeType}; money crosses the wire '
          'as a string (D01)',
    );
  }

  static bool _isAsciiDigits(String value) {
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit < 0x30 || unit > 0x39) return false;
    }
    return true;
  }

  bool get isZero => minorUnits == 0;
  bool get isNegative => minorUnits < 0;
  bool get isPositive => minorUnits > 0;

  Money operator +(Money other) =>
      Money.fromMinorUnits(minorUnits + _sameCurrency(other), currency);

  Money operator -(Money other) =>
      Money.fromMinorUnits(minorUnits - _sameCurrency(other), currency);

  Money operator -() => Money.fromMinorUnits(-minorUnits, currency);

  /// Multiplies by a whole number, e.g. a line quantity.
  ///
  /// There is deliberately no `operator *(double)` and no percentage helper:
  /// every proportional money calculation — tax, discount allocation,
  /// per-component splits — is performed server-side with defined rounding
  /// (`DATABASE.md` §10). Flutter displays those results, it does not
  /// reproduce them.
  Money operator *(int factor) => Money.fromMinorUnits(minorUnits * factor, currency);

  int _sameCurrency(Money other) {
    if (other.currency != currency) {
      throw CurrencyMismatchException(currency, other.currency);
    }
    return other.minorUnits;
  }

  /// The wire form: the same decimal string PostgreSQL `numeric(12,2)` uses.
  String toDecimalString() {
    final negative = minorUnits < 0;
    final magnitude = negative ? -minorUnits : minorUnits;
    final whole = magnitude ~/ _scale;
    final fraction = (magnitude % _scale).toString().padLeft(decimalPlaces, '0');
    return '${negative ? '-' : ''}$whole.$fraction';
  }

  /// Groups the integer part in threes: `1234567` → `12,345.67`.
  ///
  /// Deliberately locale-neutral. Locale- and currency-aware presentation is a
  /// UI concern for the milestone that builds checkout, and the symbol comes
  /// from `arenas.currency` — never a hardcoded one (D31).
  String toGroupedString() {
    final decimal = toDecimalString();
    final negative = decimal.startsWith('-');
    final body = negative ? decimal.substring(1) : decimal;
    final dot = body.indexOf('.');
    final whole = body.substring(0, dot);
    final fraction = body.substring(dot);

    final buffer = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
      buffer.write(whole[i]);
    }
    return '${negative ? '-' : ''}$buffer$fraction';
  }

  @override
  int compareTo(Money other) => minorUnits.compareTo(_sameCurrency(other));

  bool operator <(Money other) => compareTo(other) < 0;
  bool operator <=(Money other) => compareTo(other) <= 0;
  bool operator >(Money other) => compareTo(other) > 0;
  bool operator >=(Money other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Money && other.minorUnits == minorUnits && other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() => '${toDecimalString()} $currency';
}
