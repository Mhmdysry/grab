import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

import '../theme/pop_theme.dart';

/// Holds the active app [ColorScheme] so [popToast] matches the user's chosen
/// Material 3 Expressive palette even when called without a [BuildContext].
ColorScheme? _activeToastScheme;

/// Synced by [GrabApp] whenever the active theme changes.
void syncToastScheme(ColorScheme scheme) => _activeToastScheme = scheme;

/// Short Material 3 Expressive toast at the top of the screen.
void popToast(
  String message, {
  IconData icon = Icons.check_rounded,
  bool error = false,
  String? detail,
  BuildContext? context,
}) {
  final cs = context != null ? Theme.of(context).colorScheme : _activeToastScheme;
  final bg = error
      ? (cs?.errorContainer ?? Pop.error)
      : (cs?.inverseSurface ?? Pop.ink);
  final fg = error
      ? (cs?.onErrorContainer ?? Colors.white)
      : (cs?.onInverseSurface ?? Colors.white);
  final iconColor = error
      ? (cs?.onErrorContainer ?? Colors.white)
      : (cs?.inversePrimary ?? Pop.yellow);

  toastification.show(
    title: Text(
      message,
      style: TextStyle(
        fontFamily: Pop.font,
        fontWeight: FontWeight.w700,
        color: fg,
      ),
    ),
    description: detail == null
        ? null
        : Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg.withValues(alpha: 0.85)),
          ),
    icon: Icon(icon, color: iconColor),
    style: ToastificationStyle.flat,
    type: error ? ToastificationType.error : ToastificationType.success,
    backgroundColor: bg,
    foregroundColor: fg,
    borderSide: BorderSide.none,
    borderRadius: BorderRadius.circular(999),
    alignment: Alignment.topCenter,
    autoCloseDuration: const Duration(milliseconds: 2400),
    showProgressBar: false,
    closeButton: const ToastCloseButton(showType: CloseButtonShowType.none),
    dragToClose: true,
  );
}
