import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../../data/settings/app_settings.dart';
import '../theme/pop_theme.dart';
import '../utils/haptics.dart';

/// The app's one way to open a page from something on screen: the tapped card,
/// row or bar grows into the page (and shrinks back into it on close), instead
/// of a plain screen swap. Uses Material's container transform.
///
/// [builder] draws the closed state and gets an `open` callback to call on tap.
class Morph extends StatelessWidget {
  const Morph({
    super.key,
    required this.builder,
    required this.page,
    this.shape,
    this.color,
    this.pageColor,
  });

  final Widget Function(BuildContext context, VoidCallback open) builder;
  final WidgetBuilder page;
  final ShapeBorder? shape;

  /// Background of the closed widget; it fades into [pageColor] while growing.
  final Color? color;
  final Color? pageColor;

  static const duration = Duration(milliseconds: 380);

  @override
  Widget build(BuildContext context) {
    final m3 = context.m3;
    final still = m3.motion.reduced(context);
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final effectiveDuration = switch (m3.motion.preset) {
      M3MotionPreset.snappy => const Duration(milliseconds: 240),
      M3MotionPreset.off => Duration.zero,
      M3MotionPreset.expressive || M3MotionPreset.standard => duration,
    };
    return OpenContainer<void>(
      transitionType: ContainerTransitionType.fade,
      transitionDuration: still ? Duration.zero : effectiveDuration,
      closedElevation: 0,
      openElevation: 0,
      closedShape:
          shape ?? RoundedRectangleBorder(borderRadius: m3.cardRadius),
      closedColor: color ?? bg,
      openColor: pageColor ?? bg,
      middleColor: pageColor ?? bg,
      tappable: false,
      useRootNavigator: true,
      closedBuilder: (context, open) => DefaultTextStyle.merge(
        style: TextStyle(color: context.pop.text),
        child: IconTheme.merge(
          data: IconThemeData(color: context.pop.text),
          child: builder(context, () {
            Haptics.light();
            open();
          }),
        ),
      ),
      openBuilder: (context, _) => RepaintBoundary(child: page(context)),
    );
  }
}
