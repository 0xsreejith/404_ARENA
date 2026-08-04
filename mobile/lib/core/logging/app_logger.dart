import 'dart:convert';
import 'dart:developer' as developer;

import 'package:arena_os/core/config/arena_env.dart';
import 'package:arena_os/core/logging/redaction.dart';

enum LogLevel {
  debug(500, 'DEBUG'),
  info(800, 'INFO'),
  warn(900, 'WARN'),
  error(1000, 'ERROR');

  const LogLevel(this.severity, this.label);

  final int severity;
  final String label;
}

/// One structured log record.
class LogRecord {
  const LogRecord({
    required this.level,
    required this.name,
    required this.message,
    required this.fields,
    this.error,
    this.stackTrace,
  });

  final LogLevel level;
  final String name;
  final String message;
  final Map<String, Object?> fields;
  final Object? error;
  final StackTrace? stackTrace;
}

/// Where records go. Swappable so tests can assert on output and so a crash
/// reporter can be attached later without touching call sites.
abstract class LogSink {
  void write(LogRecord record);
}

/// Writes to the Dart developer log as a single JSON object per record.
class DeveloperLogSink implements LogSink {
  const DeveloperLogSink();

  @override
  void write(LogRecord record) {
    final payload = <String, Object?>{
      'level': record.level.label,
      'logger': record.name,
      'message': record.message,
      if (record.fields.isNotEmpty) 'fields': record.fields,
      if (record.error != null) 'error': record.error.toString(),
    };
    developer.log(
      jsonEncode(payload),
      name: record.name,
      level: record.level.severity,
      error: record.error,
      stackTrace: record.stackTrace,
    );
  }
}

/// Collects records in memory. For tests.
class MemoryLogSink implements LogSink {
  final List<LogRecord> records = <LogRecord>[];

  @override
  void write(LogRecord record) => records.add(record);

  void clear() => records.clear();
}

/// Structured application logger.
///
/// Every message and every field passes through [LogRedactor] before it
/// reaches a sink, so a credential or a member's phone number cannot be logged
/// even by mistake (D19, D37). Redaction is not opt-in.
///
/// The default minimum level is raised in production so that debug detail
/// about tenant operations never ships to a device in a real venue.
class AppLogger {
  AppLogger({
    required this.name,
    required this.minimumLevel,
    this.sink = const DeveloperLogSink(),
    this.redactor = logRedactor,
  });

  /// Builds the root logger for an environment.
  factory AppLogger.forEnvironment(
    ArenaEnv env, {
    String name = 'arena',
    LogSink sink = const DeveloperLogSink(),
  }) {
    return AppLogger(
      name: name,
      minimumLevel: env.isProduction ? LogLevel.warn : LogLevel.debug,
      sink: sink,
    );
  }

  final String name;
  final LogLevel minimumLevel;
  final LogSink sink;

  /// Always applied. Injectable so the redaction rules can be tested directly,
  /// never so a call site can opt out (D19, D37).
  final LogRedactor redactor;

  /// A child logger scoped to a subsystem, e.g. `arena.sync`.
  AppLogger child(String suffix) =>
      AppLogger(name: '$name.$suffix', minimumLevel: minimumLevel, sink: sink, redactor: redactor);

  void debug(String message, {Map<String, Object?> fields = const {}}) =>
      _log(LogLevel.debug, message, fields);

  void info(String message, {Map<String, Object?> fields = const {}}) =>
      _log(LogLevel.info, message, fields);

  void warn(
    String message, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) => _log(LogLevel.warn, message, fields, error, stackTrace);

  void error(
    String message, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) => _log(LogLevel.error, message, fields, error, stackTrace);

  void _log(
    LogLevel level,
    String message,
    Map<String, Object?> fields, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (level.severity < minimumLevel.severity) return;
    sink.write(
      LogRecord(
        level: level,
        name: name,
        message: redactor.redactText(message),
        fields: redactor.redactFields(fields),
        // The error object is redacted too: exception messages routinely embed
        // the offending value.
        error: error == null ? null : redactor.redactText(error.toString()),
        stackTrace: stackTrace,
      ),
    );
  }
}
