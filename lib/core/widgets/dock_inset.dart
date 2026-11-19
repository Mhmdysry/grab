import 'package:flutter/widgets.dart';

import '../../data/settings/app_settings.dart';
import '../theme/pop_theme.dart';

/// Extra room the floating bars (mini player) take above the dock, so lists can
/// scroll their last item clear of them. Set by the shell.
class DockInset extends InheritedWidget {
  const DockInset({super.key, required this.extra, required super.child});

  final double extra;

  /// Bottom padding for a tab's scrolling list: the active nav bar, plus any mini player.
  static double listBottom(BuildContext context) {
    final base = switch (context.m3.navStyle) {
      M3NavStyle.floatingPill => 120.0,
      M3NavStyle.dockedBar => 104.0,
      M3NavStyle.minimalDock => 106.0,
    };
    return base +
        (context.dependOnInheritedWidgetOfExactType<DockInset>()?.extra ?? 0);
  }

  @override
  bool updateShouldNotify(DockInset old) => old.extra != extra;
}
