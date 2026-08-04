import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guards over `lib/`.
///
/// Several project rules cannot be expressed as an analyzer lint but are
/// cheap to check by scanning source. Each one below has failed in a real
/// codebase at some point; the point is to catch the drift on the commit that
/// introduces it, not during a tax audit.
///
/// These are guards, not a substitute for the pgTAP suite (D35). They prove
/// the client does not *contain* something forbidden; they prove nothing about
/// what the database enforces.
void main() {
  final libFiles = _dartFilesUnder('lib');

  test('lib/ is non-empty, so the scans below mean something', () {
    expect(libFiles, isNotEmpty);
  });

  group('D24 — supabase_flutter is the only transport', () {
    test('Dio is not imported anywhere', () {
      _expectNoMatch(
        libFiles,
        RegExp(r'''package:dio'''),
        because:
            'Dio is not a dependency (D24). There is no separate REST '
            'backend; supabase_flutter is the transport.',
      );
    });

    test('no competing state-management package is imported (D25)', () {
      _expectNoMatch(
        libFiles,
        RegExp(r'''package:(flutter_bloc|bloc|get/|provider/provider)'''),
        because: 'Riverpod 3 is the only state-management package (D25).',
      );
    });

    test('raw http clients are not used directly', () {
      _expectNoMatch(
        libFiles,
        RegExp(r'package:http/http|HttpClient\('),
        because: 'All traffic goes through supabase_flutter (D24).',
      );
    });
  });

  group('D37 — no privileged credential can be in the client', () {
    // These three scan comments as well as code: a commented-out key is still
    // a leaked key.

    test('no credential-named variable is assigned a literal', () {
      // The negative lookahead exempts SCREAMING_SNAKE values: those are
      // --dart-define *names* such as 'SUPABASE_ANON_KEY', not secrets. A real
      // key is mixed-case base64.
      _expectNoMatch(
        libFiles,
        RegExp(
          r'''\b\w*(key|token|secret|credential|password)\w*\s*[:=]\s*'''
          r"""['"](?![A-Z0-9_]+['"])[^'"]{16,}['"]""",
          caseSensitive: false,
        ),
        because:
            'Credentials arrive via --dart-define at build time and are '
            'never written into source (D34, D37).',
        skipComments: false,
      );
    });

    test('no JWT literal is embedded in source', () {
      _expectNoMatch(
        libFiles,
        RegExp(r'''eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.'''),
        because: 'Keys arrive via --dart-define and are never committed (D34).',
        skipComments: false,
      );
    });

    test('no Supabase project URL is hardcoded', () {
      _expectNoMatch(
        libFiles,
        RegExp(r'''https://[a-z0-9]{16,}\.supabase\.(co|in)'''),
        because: 'The project URL is per-environment configuration (D34).',
        skipComments: false,
      );
    });
  });

  group('rule 1 / D31 / D33 — no tenant or jurisdiction data in code', () {
    test('no GST component names', () {
      _expectNoMatch(
        libFiles,
        RegExp(r'''\b(CGST|SGST|IGST|GSTIN)\b'''),
        because:
            'Tax components are rows in tax_rate_components, configured '
            'per arena (D31). No jurisdiction belongs in source.',
      );
    });

    test('no hardcoded currency, dial code, or timezone', () {
      _expectNoMatch(
        libFiles,
        RegExp(r"""(['"]INR['"])|(['"]\+91['"])|(Asia/Kolkata)"""),
        because:
            'Currency, dial code, and timezone are arena configuration '
            '(D31, D36). Test fixtures may use literals; lib/ may not.',
      );
    });

    test('no pilot-tenant identity', () {
      _expectNoMatch(
        libFiles,
        RegExp(r'''404\s*Arena''', caseSensitive: false),
        because: '404 Arena is tenant #1, not the product (CLAUDE.md).',
      );
    });

    test('no hardcoded rates, receipt prefixes, or business hours', () {
      _expectNoMatch(
        libFiles,
        RegExp(
          r'''(hourlyRate\s*=\s*\d)|(fixedPrice\s*=\s*\d)|'''
          r'''(taxPercent\s*=\s*\d)|(receiptPrefix\s*=\s*['"][^'"]+['"])|'''
          r'''(businessDayStart\s*=)''',
        ),
        because:
            'Pricing, tax, receipts, and trading hours are configuration, '
            'never code (D33).',
      );
    });

    test('no FIXTURE data ships in the client', () {
      _expectNoMatch(
        libFiles,
        RegExp(r'''\[FIXTURE\]'''),
        because:
            'Fixture pricing is seeded into dev and staging databases '
            'only, never compiled into the app (D33).',
      );
    });
  });

  group('D01 — money never touches double', () {
    test('no double-typed money declaration', () {
      _expectNoMatch(
        libFiles,
        RegExp(
          r'''double\s+\w*([Aa]mount|[Pp]rice|[Tt]otal|[Mm]oney|[Rr]ate|'''
          r'''[Ss]ubtotal|[Bb]alance|[Cc]ash|[Ff]loat\b)''',
        ),
        because:
            'Money is an int of minor units (D01). A double amount is a '
            'rounding bug waiting to be shipped.',
      );
    });

    test('money.dart contains no double in executable code', () {
      // Comments may discuss floating point; code may not use it.
      final code = File(
        'lib/core/money/money.dart',
      ).readAsLinesSync().where((line) => !line.trimLeft().startsWith('//')).join('\n');
      expect(
        RegExp(r'\bdouble\b').hasMatch(code),
        isFalse,
        reason: 'Money must never reference double outside a comment (D01).',
      );
    });
  });
}

List<File> _dartFilesUnder(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return const <File>[];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('.g.dart') && !f.path.endsWith('.freezed.dart'))
      .toList(growable: false);
}

/// Scans `files` for [pattern].
///
/// [skipComments] defaults to true: the guards are about executable code, and
/// a comment that explains why something is forbidden must not trip the guard
/// that forbids it. It is set to false for credential patterns, because a
/// commented-out key is still a leaked key.
void _expectNoMatch(
  List<File> files,
  RegExp pattern, {
  required String because,
  bool skipComments = true,
}) {
  final offenders = <String>[];
  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (skipComments && line.trimLeft().startsWith('//')) continue;
      if (pattern.hasMatch(line)) {
        offenders.add('${file.path}:${i + 1}: ${line.trim()}');
      }
    }
  }
  expect(offenders, isEmpty, reason: '$because\n${offenders.join('\n')}');
}
