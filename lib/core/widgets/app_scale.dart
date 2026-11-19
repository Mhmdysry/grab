import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Makes the whole app keep the same proportions on every screen.
///
/// Grab is laid out for a ~400 dp wide phone. On wider screens, or phones whose
/// "Display size" is set small (more dp across), everything would look shrunken.
/// This scales the app up uniformly, like zooming, based on the screen's shortest
/// side, so a large or high-density screen shows the same layout, just bigger.
/// Text never ends up smaller than the user's font size setting asks for, and
/// never smaller than 1x.
class AppScale extends StatelessWidget {
  const AppScale({super.key, this.fontScale = 1.0, required this.child});

  final double fontScale;
  final Widget child;

  /// Width the screens are designed for. On a ~590 dp phone (small Display
  /// size setting) 565 gives about 1.05x: a touch larger, never cramped.
  static const designWidth = 565.0;

  /// The zoom applied for a screen of [size].
  static double factorFor(Size size) {
    // A desktop window is sized by the user; keep the design at 1x there.
    if (!(Platform.isAndroid || Platform.isIOS)) return 1;
    final shortest = math.min(size.width, size.height);
    if (shortest <= 0) return 1;
    return (shortest / designWidth).clamp(0.9, 1.4);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final s = factorFor(mq.size);
    // Below 1x the user shrank text system-wide; inside Grab we already size things
    // to the screen, so keep at least 1x. Larger accessibility sizes still apply,
    // multiplied by the user's in-app Appearance fontScale preference.
    final baseText = mq.textScaler.scale(1) < 1
        ? TextScaler.noScaling
        : mq.textScaler;
    final text = (fontScale - 1.0).abs() < 0.001
        ? baseText
        : TextScaler.linear((baseText.scale(1.0) * fontScale).clamp(0.85, 2.2));
    // Always build the same tree (even at 1x) so rotating never rebuilds app state.
    final logical = mq.size / s;
    return MediaQuery(
      data: mq.copyWith(
        size: logical,
        devicePixelRatio: mq.devicePixelRatio * s,
        padding: mq.padding / s,
        viewPadding: mq.viewPadding / s,
        viewInsets: mq.viewInsets / s,
        systemGestureInsets: mq.systemGestureInsets / s,
        textScaler: text,
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: logical.width,
          maxWidth: logical.width,
          minHeight: logical.height,
          maxHeight: logical.height,
          child: Transform.scale(
            scale: s,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: logical.width,
              height: logical.height,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
