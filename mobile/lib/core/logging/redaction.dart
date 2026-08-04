/// Scrubs credentials and personal data out of anything about to be logged.
///
/// Two rules from the specification are enforced here rather than left to
/// discipline at every call site:
///
///   * `service_role` keys, JWTs, and anon keys must never appear in a log, a
///     crash report, or CI output (D37, `SECURITY.md` §11).
///   * Member PII must never appear in `audit_logs.metadata`, application logs,
///     or crash reports — log the member id, never the phone or the name
///     (D19, `SECURITY.md` §8).
///
/// Redaction is applied to keys *and* values, because the same phone number
/// arrives sometimes as `{'phone': ...}` and sometimes inside a free-text
/// message.
class LogRedactor {
  const LogRedactor();

  static const String redacted = '[REDACTED]';

  /// Field names whose values are always replaced, whatever they contain.
  ///
  /// Matched case-insensitively against the whole key and against
  /// snake/camel-case segments, so `memberPhone` and `member_phone` both hit.
  static const Set<String> _sensitiveKeys = <String>{
    // Credentials
    'anonkey', 'apikey', 'authorization', 'jwt', 'key', 'password', 'secret',
    'servicerole', 'servicerolekey', 'token', 'refreshtoken',
    'accesstoken', 'bearer', 'supabaseanonkey',
    // Member PII (D19)
    'phone', 'phonenumber', 'mobile', 'dob', 'dateofbirth', 'fullname',
    'displayname', 'membername', 'email', 'address', 'notes',
  };

  /// A JWT: three base64url segments. Covers both anon and service_role keys.
  static final RegExp _jwtPattern = RegExp(
    r'\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\b',
  );

  /// Current-format Supabase keys, publishable and secret alike.
  static final RegExp _supabaseKeyPattern = RegExp(r'\bsb_(publishable|secret)_[A-Za-z0-9_-]+');

  /// A phone number in any of the shapes staff might type or the server might
  /// return, including canonical E.164 (D36).
  static final RegExp _phonePattern = RegExp(r'(?<![\w.])\+?\d[\d\s().-]{7,17}\d(?![\w.])');

  /// Redacts a free-text string.
  String redactText(String input) {
    return input
        .replaceAll(_jwtPattern, redacted)
        .replaceAll(_supabaseKeyPattern, redacted)
        .replaceAllMapped(_phonePattern, (_) => redacted);
  }

  /// Redacts a structured field map, recursing into nested maps and lists.
  Map<String, Object?> redactFields(Map<String, Object?> fields) {
    return fields.map((key, value) {
      if (_isSensitiveKey(key)) return MapEntry(key, redacted);
      return MapEntry(key, _redactValue(value));
    });
  }

  Object? _redactValue(Object? value) {
    if (value == null) return null;
    if (value is String) return redactText(value);
    if (value is num || value is bool) return value;
    if (value is Map) {
      return redactFields(value.map((k, v) => MapEntry(k.toString(), v as Object?)));
    }
    if (value is Iterable) {
      return value.map<Object?>(_redactValue).toList(growable: false);
    }
    // Unknown types are stringified and scrubbed rather than trusted: a
    // `toString()` on a model object is a common way PII leaks into logs.
    return redactText(value.toString());
  }

  bool _isSensitiveKey(String key) {
    final normalised = key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    if (_sensitiveKeys.contains(normalised)) return true;
    // Catch composites such as `memberPhone`, `staff_pin_hash`, `authToken`.
    for (final sensitive in _sensitiveKeys) {
      if (sensitive.length >= 5 && normalised.contains(sensitive)) return true;
    }
    return normalised.contains('pin') || normalised.contains('credential');
  }
}

const LogRedactor logRedactor = LogRedactor();
