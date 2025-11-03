import 'package:flutter/foundation.dart';

/// A simple logging utility for the application.
///
/// In a production app, this could be expanded to integrate with a remote
/// logging service like Sentry, Firebase Crashlytics, or Datadog.
class Log {
  /// Log a message at the INFO level.
  static void i(String message) {
    if (kDebugMode) {
      print('[INFO] $message');
    }
  }

  /// Log a message at the DEBUG level.
  static void d(String message) {
    if (kDebugMode) {
      print('[DEBUG] $message');
    }
  }

  /// Log a message at the WARNING level.
  static void w(String message) {
    if (kDebugMode) {
      print('[WARN] $message');
    }
  }

  /// Log an ERROR, including the error object and an optional stack trace.
  static void e(String message, Object error, [StackTrace? stackTrace]) {
    if (kDebugMode) {
      print('[ERROR] $message\n$error');
      if (stackTrace != null) {
        print(stackTrace);
      }
    }
  }
}
