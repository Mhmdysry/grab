import 'package:flutter/material.dart';

import '../theme/pop_theme.dart';

/// Reusable Material 3 Expressive collapsing large header built on
/// [SliverAppBar.large] with tonal `surfaceContainer` scroll fill and bold
/// Outfit display typography.
class ExpressiveSliverHeader extends StatelessWidget {
  const ExpressiveSliverHeader({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.expandedHeight = 116,
    this.pinned = true,
  });

  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final double expandedHeight;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return SliverAppBar.large(
      pinned: pinned,
      automaticallyImplyLeading: false,
      leading: leading,
      leadingWidth: leading != null ? 64 : null,
      titleSpacing: leading != null ? 0 : 24,
      expandedHeight: expandedHeight,
      collapsedHeight: 64,
      backgroundColor: cs.surface,
      surfaceTintColor: cs.surfaceContainerHigh,
      scrolledUnderElevation: 3,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: Pop.font,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.7,
        ),
      ),
      actions: actions,
    );
  }
}

/// Applies Material 3 stretch overscroll consistently across platforms.
class ExpressiveScrollBehavior extends MaterialScrollBehavior {
  const ExpressiveScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => StretchingOverscrollIndicator(
    axisDirection: details.axisDirection,
    child: child,
  );

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics());
}
