import 'package:flutter/services.dart';

/// iPhone-style haptics. Uses Android haptic primitives (crisp taps) through
/// the native "grab/haptics" channel, and falls back to Flutter's HapticFeedback.
abstract final class Haptics {
  static const _channel = MethodChannel('grab/haptics');

  /// Global toggle synced with AppSettings.hapticsEnabled.
  static bool enabled = true;

  /// Moving between options: tabs, segments, chips. The lightest tick.
  static Future<void> selection() =>
      _play('selection', HapticFeedback.selectionClick);

  /// Buttons.
  static Future<void> light() => _play('light', HapticFeedback.lightImpact);
  static Future<void> medium() => _play('medium', HapticFeedback.mediumImpact);
  static Future<void> heavy() => _play('heavy', HapticFeedback.heavyImpact);

  /// A soft bump, e.g. a sheet settling.
  static Future<void> soft() => _play('soft', HapticFeedback.selectionClick);

  /// Notifications, like iOS: a download finished, failed, or needs attention.
  static Future<void> success() =>
      _play('success', HapticFeedback.mediumImpact);
  static Future<void> warning() =>
      _play('warning', HapticFeedback.mediumImpact);
  static Future<void> error() => _play('error', HapticFeedback.heavyImpact);

  static Future<void> _play(
    String type,
    Future<void> Function() fallback,
  ) async {
    if (!enabled) return;
    try {
      await _channel.invokeMethod('play', {'type': type});
    } on MissingPluginException {
      await fallback();
    } on PlatformException {
      await fallback();
    }
  }
}
