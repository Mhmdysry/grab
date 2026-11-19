import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Persistent app-wide and cross-engine (main + share overlay) diagnostic & crash logger.
///
/// Captures:
/// - `FlutterError.onError` framework errors
/// - `PlatformDispatcher.instance.onError` uncaught async errors
/// - Explicit `AppLog.info`, `AppLog.warn`, and `AppLog.error` events
/// - Native Android logcat output for this process via `grab/app` (`getLogcat`)
abstract final class AppLog {
  static const _channel = MethodChannel('grab/app');
  static const _maxBytes = 256 * 1024; // 256 KB rolling log file
  static File? _file;
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static final List<String> _memoryBuffer = <String>[];

  /// Installs global error hooks for the current Dart entrypoint (`main` or `shareMain`).
  static Future<void> init({String entrypoint = 'main'}) async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/grab_debug.log');
      if (!_file!.existsSync()) {
        _file!.createSync(recursive: true);
      }
    } catch (_) {
      // In widget tests path_provider may not be mocked; fall back to memory buffer.
    }

    info('AppLog initialized', tag: entrypoint);

    final prevFlutterHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      error(
        'FlutterError: ${details.exceptionAsString()}',
        tag: '$entrypoint/flutter',
        stack: details.stack,
      );
      if (prevFlutterHandler != null) {
        prevFlutterHandler(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    PlatformDispatcher.instance.onError = (Object err, StackTrace stack) {
      error(
        'Uncaught async error: $err',
        tag: '$entrypoint/async',
        stack: stack,
      );
      return false;
    };
  }

  static void info(String message, {String tag = 'app'}) =>
      _write('INFO', tag, message);

  static void warn(String message, {String tag = 'app', Object? error}) =>
      _write(
        'WARN',
        tag,
        error == null ? message : '$message | $error',
      );

  static void error(
    String message, {
    String tag = 'app',
    Object? error,
    StackTrace? stack,
  }) {
    final buf = StringBuffer(message);
    if (error != null) buf.write('\nError: $error');
    if (stack != null) {
      final lines = stack.toString().split('\n').take(18).join('\n');
      buf.write('\n$lines');
    }
    _write('ERROR', tag, buf.toString());
  }

  static void _write(String level, String tag, String message) {
    final ts = DateTime.now().toIso8601String();
    final entry = '[$ts] [$level] [$tag] $message\n';
    _memoryBuffer.add(entry);
    if (_memoryBuffer.length > 400) {
      _memoryBuffer.removeAt(0);
    }
    final f = _file;
    if (f != null) {
      try {
        if (f.existsSync() && f.lengthSync() > _maxBytes) {
          final text = f.readAsStringSync();
          final keep = text.substring(text.length ~/ 2);
          f.writeAsStringSync(keep, flush: true);
        }
        f.writeAsStringSync(entry, mode: FileMode.append, flush: true);
      } catch (_) {}
    }
    revision.value++;
  }

  /// Reads all persisted Dart/Flutter logs (including logs written by `ShareActivity`).
  static Future<String> readAppLogs() async {
    final f = _file;
    if (f != null) {
      try {
        if (f.existsSync()) {
          final text = await f.readAsString();
          if (text.trim().isNotEmpty) return text;
        }
      } catch (_) {}
    }
    if (_memoryBuffer.isEmpty) return 'No app logs recorded yet.';
    return _memoryBuffer.join();
  }

  /// Fetches recent native Android logcat lines for this app process.
  static Future<String> readNativeLogcat() async {
    if (!Platform.isAndroid) {
      return 'Native logcat is only available on Android.';
    }
    try {
      final out = await _channel.invokeMethod<String>('getLogcat');
      return (out == null || out.trim().isEmpty)
          ? 'No native logcat entries available.'
          : out;
    } catch (e) {
      return 'Failed to read native logcat: $e';
    }
  }

  /// Clears both the persisted log file, in-memory buffer, and native logcat buffer.
  static Future<void> clear() async {
    _memoryBuffer.clear();
    final f = _file;
    if (f != null) {
      try {
        if (f.existsSync()) await f.writeAsString('');
      } catch (_) {}
    }
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('clearLogcat');
      } catch (_) {}
    }
    info('Debug log cleared by user');
  }
}
