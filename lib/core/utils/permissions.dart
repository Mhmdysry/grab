import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/pop_theme.dart';
import '../widgets/expressive_shapes.dart';
import '../widgets/pop_widgets.dart';
import 'haptics.dart';

const _appChannel = MethodChannel('grab/app');

/// Asks for what downloads need, with a short explanation first, the iOS way:
/// - Notifications (Android 13+): progress and "Saved" alerts. Optional; downloads work without it.
/// - Storage (Android 9 and older only): needed to save into Download/Grab.
///
/// Returns false only when saving is impossible (storage refused on old Android).
Future<bool> ensureDownloadPermissions(
  BuildContext context,
  SharedPreferences prefs,
) async {
  // Computers need no permission prompts to save into Downloads.
  if (!Platform.isAndroid) return true;
  final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;

  if (sdk <= 28) {
    final storage = await Permission.storage.status;
    if (!storage.isGranted) {
      if (!context.mounted) return false;
      final go = await _explain(
        context,
        icon: Icons.folder_rounded,
        title: 'Allow Grab to save files',
        body:
            'Grab saves your downloads to a folder on this phone (Download/Grab unless you pick another in Settings).',
        permanentlyDenied: storage.isPermanentlyDenied,
      );
      if (!go) return false;
      final r = storage.isPermanentlyDenied
          ? await _settings()
          : await Permission.storage.request();
      if (!r.isGranted) return false;
    }
  }

  if (sdk >= 33 && !(prefs.getBool('askedNotifications') ?? false)) {
    final n = await Permission.notification.status;
    if (!n.isGranted) {
      await prefs.setBool('askedNotifications', true);
      if (!context.mounted) return true;
      final go = await _explain(
        context,
        icon: Icons.notifications_active_rounded,
        title: 'Know when it\'s done',
        body:
            'Allow notifications to see download progress and a "Saved" alert, even when Grab is closed.',
        permanentlyDenied: n.isPermanentlyDenied,
      );
      if (go) {
        n.isPermanentlyDenied
            ? await _settings()
            : await Permission.notification.request();
      }
    }
  }
  return true;
}

/// Current notification permission, for Settings.
Future<PermissionStatus> notificationStatus() async => Platform.isAndroid
    ? Permission.notification.status
    : PermissionStatus.granted;

/// Ask again, or send the user to system settings if Android won't ask anymore.
Future<PermissionStatus> requestNotifications() async {
  if (!Platform.isAndroid) return PermissionStatus.granted;
  final s = await Permission.notification.status;
  if (s.isPermanentlyDenied) return _settings(Permission.notification);
  return Permission.notification.request();
}

/// Whether "Appear on top" (`SYSTEM_ALERT_WINDOW`) is granted on Android.
Future<bool> overlayPermissionGranted() async {
  if (!Platform.isAndroid) return true;
  try {
    return (await _appChannel.invokeMethod<bool>('canDrawOverlays')) ?? false;
  } catch (_) {
    return false;
  }
}

/// Shows an expressive explanation sheet and opens Android's "Appear on top" screen.
Future<bool> requestOverlayPermission(
  BuildContext context, {
  bool explain = true,
}) async {
  if (!Platform.isAndroid) return true;
  if (await overlayPermissionGranted()) return true;
  if (explain) {
    if (!context.mounted) return false;
    final go = await _explain(
      context,
      icon: Icons.bubble_chart_rounded,
      title: 'Floating progress bubble',
      body:
          'Allow "Appear on top" so Grab can float a draggable progress bubble while you scroll other apps. Sharing links works even without it.',
      permanentlyDenied: false,
      actionLabel: 'Allow in settings',
    );
    if (!go) return false;
  }
  try {
    await _appChannel.invokeMethod<void>('requestOverlayPermission');
  } catch (_) {}
  return overlayPermissionGranted();
}

Object? _lastBubbleSig;

/// Syncs the native floating bubble's enabled state and active Material 3 colors.
Future<void> syncBubbleConfig({
  required bool enabled,
  required ColorScheme scheme,
  bool force = false,
}) async {
  if (!Platform.isAndroid) return;
  final sig = (
    enabled,
    scheme.primary.toARGB32(),
    scheme.onPrimary.toARGB32(),
    scheme.surfaceContainerHigh.toARGB32(),
    scheme.onSurface.toARGB32(),
    scheme.primaryContainer.toARGB32(),
    scheme.onPrimaryContainer.toARGB32(),
  );
  if (!force && sig == _lastBubbleSig) return;
  _lastBubbleSig = sig;
  try {
    await _appChannel.invokeMethod<void>('setBubbleConfig', {
      'enabled': enabled,
      'primary': scheme.primary.toARGB32(),
      'onPrimary': scheme.onPrimary.toARGB32(),
      'surface': scheme.surfaceContainerHigh.toARGB32(),
      'onSurface': scheme.onSurface.toARGB32(),
      'primaryContainer': scheme.primaryContainer.toARGB32(),
      'onPrimaryContainer': scheme.onPrimaryContainer.toARGB32(),
    });
  } catch (_) {}
}

/// Triggers a 5-second interactive floating bubble preview on Android.
Future<bool> previewFloatingBubble() async {
  if (!Platform.isAndroid) return false;
  try {
    return (await _appChannel.invokeMethod<bool>('previewBubble')) ?? false;
  } catch (_) {
    return false;
  }
}

Future<PermissionStatus> _settings([Permission p = Permission.storage]) async {
  await openAppSettings();
  return p.status;
}

Future<bool> _explain(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String body,
  required bool permanentlyDenied,
  String? actionLabel,
}) async {
  Haptics.soft();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExpressiveShapeContainer(
              polygon: ExpressivePolygon.cookie9,
              size: 72,
              color: context.cs.primaryContainer,
              child: Icon(
                icon,
                size: 36,
                color: context.cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              permanentlyDenied
                  ? '$body\n\nTurn it on in Settings › Permissions.'
                  : body,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.pop.muted, height: 1.3),
            ),
            const SizedBox(height: 20),
            PopButton(
              label:
                  actionLabel ??
                  (permanentlyDenied ? 'Open settings' : 'Continue'),
              onPressed: () => Navigator.pop(context, true),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}
