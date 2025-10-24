import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Centralized logging utility for the application
/// 
/// Usage:
/// ```dart
/// AppLogger.debug('Debug message');
/// AppLogger.info('Info message');
/// AppLogger.warning('Warning message');
/// AppLogger.error('Error message', error: exception, stackTrace: st);
/// ```
/// 
/// Log levels:
/// - **DEBUG**: Verbose information for development (disabled in production)
/// - **INFO**: General informational messages
/// - **WARNING**: Warning messages that don't break functionality
/// - **ERROR**: Error messages for exceptions and failures
class AppLogger {
  static final Logger _logger = Logger(
    filter: _LogFilter(),
    printer: PrettyPrinter(
      methodCount: 0, // No stack trace for non-errors
      errorMethodCount: 5, // Show stack trace for errors
      lineLength: 80,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    output: _LogOutput(),
  );

  /// Debug level logging - Only enabled in debug mode
  /// Use for verbose information during development
  static void debug(String message, {String? tag}) {
    if (kDebugMode) {
      _logger.d(_formatMessage(message, tag));
    }
  }

  /// Info level logging - Important informational messages
  /// Use for significant app events (connections, data loads, etc.)
  static void info(String message, {String? tag}) {
    _logger.i(_formatMessage(message, tag));
  }

  /// Warning level logging - Non-critical issues
  /// Use for recoverable errors or unexpected conditions
  static void warning(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.w(
      _formatMessage(message, tag),
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Error level logging - Critical errors and exceptions
  /// Use for errors that impact functionality
  static void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.e(
      _formatMessage(message, tag),
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Format message with optional tag prefix
  static String _formatMessage(String message, String? tag) {
    return tag != null ? '[$tag] $message' : message;
  }
}

/// Custom log filter - Only shows logs in debug mode for DEBUG level
class _LogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    // In production (release mode), only show INFO, WARNING, and ERROR
    if (kReleaseMode && event.level == Level.debug) {
      return false;
    }
    return true;
  }
}

/// Custom log output - Uses debugPrint which respects Flutter's logging
class _LogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      // Use debugPrint which handles log throttling in Flutter
      debugPrint(line);
    }
  }
}

/// Extension for easy component-specific logging
extension LoggerExtension on String {
  /// Get a logger with this string as the tag
  ComponentLogger get logger => ComponentLogger(this);
}

/// Component-specific logger with automatic tagging
class ComponentLogger {
  final String tag;

  const ComponentLogger(this.tag);

  void debug(String message) => AppLogger.debug(message, tag: tag);
  
  void info(String message) => AppLogger.info(message, tag: tag);
  
  void warning(String message, {Object? error, StackTrace? stackTrace}) {
    AppLogger.warning(message, tag: tag, error: error, stackTrace: stackTrace);
  }
  
  void error(String message, {Object? error, StackTrace? stackTrace}) {
    AppLogger.error(message, tag: tag, error: error, stackTrace: stackTrace);
  }
}
