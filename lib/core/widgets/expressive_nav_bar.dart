import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/settings/app_settings.dart';
import '../theme/pop_theme.dart';
import '../utils/haptics.dart';
import 'expressive_shapes.dart';
import 'morph.dart';
import 'pop_widgets.dart';

/// One tab in [PopTabBar] / [ExpressiveFloatingNavBar].
class PopTab {
  const PopTab(this.icon, this.label, {this.activeIcon, this.badge = 0});

  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final int badge;
}

/// Live companion orb state for the right-hand detached Companion Orb.
class PopDockOrb {
  const PopDockOrb({
    this.playingTitle,
    this.playingSeed,
    this.playingThumbUrl,
    this.isPlaying = false,
    this.playingPageBuilder,
    this.onOpenPlayer,
    this.onTogglePlay,
    this.activeDownloads = 0,
    this.downloadProgress,
    this.onOpenDownloads,
    this.onPasteGrab,
  });

  final String? playingTitle;
  final String? playingSeed;
  final String? playingThumbUrl;
  final bool isPlaying;
  final WidgetBuilder? playingPageBuilder;
  final VoidCallback? onOpenPlayer;
  final VoidCallback? onTogglePlay;
  final int activeDownloads;

  /// `0.0..1.0` aggregate download progress, or `null` when queued/indeterminate.
  final double? downloadProgress;
  final VoidCallback? onOpenDownloads;
  final VoidCallback? onPasteGrab;
}

/// 3-Mode Material 3 Expressive Navigation Bar (`floatingPill`, `dockedBar`, `minimalDock`).
class PopTabBar extends StatelessWidget {
  const PopTabBar({
    super.key,
    required this.tabs,
    required this.index,
    required this.onChanged,
    this.orb = const PopDockOrb(),
  });

  final List<PopTab> tabs;
  final int index;
  final ValueChanged<int> onChanged;
  final PopDockOrb orb;

  @override
  Widget build(BuildContext context) {
    return switch (context.m3.navStyle) {
      M3NavStyle.floatingPill => ExpressiveFloatingNavBar(
        tabs: tabs,
        index: index,
        onChanged: onChanged,
        orb: orb,
      ),
      M3NavStyle.dockedBar => _buildDockedBar(context),
      M3NavStyle.minimalDock => _buildMinimalDock(context),
    };
  }

  Widget _buildDockedBar(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    return NavigationBar(
      selectedIndex: index,
      animationDuration: m3.motion.resolve(
        context,
        m3.motion.defaultSpatialDuration,
      ),
      onDestinationSelected: (i) {
        if (i != index) Haptics.selection();
        onChanged(i);
      },
      destinations: [
        for (var i = 0; i < tabs.length; i++)
          NavigationDestination(
            icon: Badge(
              isLabelVisible: tabs[i].badge > 0,
              backgroundColor: cs.error,
              textColor: cs.onError,
              label: Text('${tabs[i].badge}'),
              child: Icon(tabs[i].icon),
            ),
            selectedIcon: Badge(
              isLabelVisible: tabs[i].badge > 0,
              backgroundColor: cs.error,
              textColor: cs.onError,
              label: Text('${tabs[i].badge}'),
              child: Icon(tabs[i].activeIcon ?? tabs[i].icon),
            ),
            label: tabs[i].label,
          ),
      ],
    );
  }

  Widget _buildMinimalDock(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = m3.shapeStyle == M3ShapeStyle.crisp ? 16.0 : 30.0;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Center(
        heightFactor: 1.0,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: cs.surfaceContainerHigh,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(radius),
              side: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            shadows: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < tabs.length; i++) _minimalTab(context, i),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _minimalTab(BuildContext context, int i) {
    final tab = tabs[i];
    final on = i == index;
    final cs = context.cs;
    final m3 = context.m3;
    return Semantics(
      selected: on,
      button: true,
      label: tab.badge > 0 ? '${tab.label}, ${tab.badge} active' : tab.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!on) Haptics.selection();
          onChanged(i);
        },
        child: AnimatedContainer(
          duration: m3.motion.resolve(context, m3.motion.defaultSpatialDuration),
          curve: m3.motion.defaultSpatialCurve,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: EdgeInsets.symmetric(horizontal: on ? 18 : 14, vertical: 10),
          decoration: BoxDecoration(
            color: on ? cs.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(
              m3.shapeStyle == M3ShapeStyle.crisp ? 12 : 999,
            ),
          ),
          child: Badge(
            isLabelVisible: tab.badge > 0,
            backgroundColor: cs.error,
            textColor: cs.onError,
            label: Text('${tab.badge}'),
            child: AnimatedScale(
              scale: on ? 1.1 : 1.0,
              duration: m3.motion.resolve(
                context,
                m3.motion.fastSpatialDuration,
              ),
              curve: m3.motion.fastSpatialCurve,
              child: Icon(
                on ? (tab.activeIcon ?? tab.icon) : tab.icon,
                size: 22,
                color: on ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// From-scratch Material 3 Expressive Stacked Floating Navigation Bar +
/// Shape-Morphing Companion Orb.
///
/// Equal-width slots guarantee siblings never shift horizontally, while the
/// active indicator pill springs open beneath the icon and the label sits crisply
/// underneath.
class ExpressiveFloatingNavBar extends StatelessWidget {
  const ExpressiveFloatingNavBar({
    super.key,
    required this.tabs,
    required this.index,
    required this.onChanged,
    this.orb = const PopDockOrb(),
  });

  final List<PopTab> tabs;
  final int index;
  final ValueChanged<int> onChanged;
  final PopDockOrb orb;

  @override
  Widget build(BuildContext context) {
    final m3 = context.m3;
    final cs = context.cs;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = m3.shapeStyle == M3ShapeStyle.crisp ? 20.0 : 34.0;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: cs.surfaceContainerHigh,
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(radius),
                    side: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.55),
                    ),
                  ),
                  shadows: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.30 : 0.09,
                      ),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < tabs.length; i++)
                        Expanded(
                          flex: 1,
                          child: _StackedNavTab(
                            tab: tabs[i],
                            tabIndex: i,
                            selected: i == index,
                            onTap: () => onChanged(i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _MorphingCompanionOrb(orb: orb),
          ],
        ),
      ),
    );
  }
}

class _StackedNavTab extends StatefulWidget {
  const _StackedNavTab({
    required this.tab,
    required this.tabIndex,
    required this.selected,
    required this.onTap,
  });

  final PopTab tab;
  final int tabIndex;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_StackedNavTab> createState() => _StackedNavTabState();
}

class _StackedNavTabState extends State<_StackedNavTab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _impulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  @override
  void didUpdateWidget(_StackedNavTab old) {
    super.didUpdateWidget(old);
    if (!old.selected && widget.selected && !context.m3.motion.reduced(context)) {
      _impulse.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _impulse.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.selected) {
      Haptics.selection();
    } else if (!context.m3.motion.reduced(context)) {
      _impulse.forward(from: 0.0);
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    final still = m3.motion.reduced(context);
    final on = widget.selected;
    final iconData = on ? (widget.tab.activeIcon ?? widget.tab.icon) : widget.tab.icon;
    final pillShape = m3.shapeStyle == M3ShapeStyle.crisp
        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
        : const StadiumBorder();
    final tiltSign = widget.tabIndex.isEven ? -1.0 : 1.0;

    return Semantics(
      selected: on,
      button: true,
      label: widget.tab.badge > 0
          ? '${widget.tab.label}, ${widget.tab.badge} active'
          : widget.tab.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 30,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedOpacity(
                      opacity: on ? 1.0 : 0.0,
                      duration: m3.motion.resolve(
                        context,
                        m3.motion.fastEffectsDuration,
                      ),
                      curve: m3.motion.effectsCurve,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: on ? 1.0 : 0.35),
                        duration: still
                            ? Duration.zero
                            : m3.motion.defaultSpatialDuration,
                        curve: m3.motion.defaultSpatialCurve,
                        builder: (_, scaleX, child) => Transform.scale(
                          scaleX: scaleX.clamp(0.05, 1.25),
                          scaleY: 1.0,
                          child: child,
                        ),
                        child: Container(
                          width: 54,
                          height: 30,
                          decoration: ShapeDecoration(
                            color: cs.primaryContainer,
                            shape: pillShape,
                          ),
                        ),
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _impulse,
                      builder: (_, child) {
                        final wave = still
                            ? 0.0
                            : math.sin(_impulse.value * math.pi);
                        return Transform.translate(
                          offset: Offset(0, -2.5 * wave),
                          child: Transform.rotate(
                            angle: tiltSign * 0.03 * math.pi * 2 * wave,
                            child: child,
                          ),
                        );
                      },
                      child: Badge(
                        isLabelVisible: widget.tab.badge > 0,
                        backgroundColor: cs.error,
                        textColor: cs.onError,
                        label: Text('${widget.tab.badge}'),
                        child: AnimatedScale(
                          scale: on ? 1.08 : 1.0,
                          duration: m3.motion.resolve(
                            context,
                            m3.motion.fastSpatialDuration,
                          ),
                          curve: m3.motion.fastSpatialCurve,
                          child: AnimatedSwitcher(
                            duration: m3.motion.resolve(
                              context,
                              m3.motion.fastEffectsDuration,
                            ),
                            child: Icon(
                              iconData,
                              key: ValueKey(iconData),
                              size: 21,
                              color: on
                                  ? cs.onPrimaryContainer
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AnimatedDefaultTextStyle(
                      duration: m3.motion.resolve(
                        context,
                        m3.motion.fastEffectsDuration,
                      ),
                      curve: m3.motion.effectsCurve,
                      style: TextStyle(
                        fontFamily: Pop.font,
                        fontSize: 11,
                        height: 1.1,
                        fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                        color: on ? cs.onSurface : cs.onSurfaceVariant,
                      ),
                      child: Text(
                        widget.tab.label,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _OrbState { idle, downloads, playing }

/// Detached Shape-Morphing Companion Orb (`60×60dp`).
///
/// Morphs its actual [ExpressivePolygonBorder] geometry between:
/// - **Idle** → `ExpressivePolygon.squircle` (`tertiaryContainer`, Paste & Grab)
/// - **Active Downloads** → `ExpressivePolygon.circle` (`surfaceContainerHigh` + radial arc)
/// - **Playing Audio** → `ExpressivePolygon.cookie9` (rotating scalloped badge + track art)
class _MorphingCompanionOrb extends StatefulWidget {
  const _MorphingCompanionOrb({required this.orb});

  final PopDockOrb orb;

  @override
  State<_MorphingCompanionOrb> createState() => _MorphingCompanionOrbState();
}

class _MorphingCompanionOrbState extends State<_MorphingCompanionOrb>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late final AnimationController _cookieSpin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  _OrbState get _state {
    final o = widget.orb;
    if (o.playingSeed != null) return _OrbState.playing;
    if (o.activeDownloads > 0) return _OrbState.downloads;
    return _OrbState.idle;
  }

  void _sync() {
    if (context.m3.motion.reduced(context)) {
      _pulse.stop();
      _cookieSpin.stop();
      return;
    }
    final o = widget.orb;
    final st = _state;
    final needsPulse =
        (st == _OrbState.playing && o.isPlaying) ||
        (st == _OrbState.downloads && o.downloadProgress == null);
    if (needsPulse) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
    }
    if (st == _OrbState.playing && o.isPlaying) {
      if (!_cookieSpin.isAnimating) _cookieSpin.repeat();
    } else {
      _cookieSpin.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_MorphingCompanionOrb old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _cookieSpin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final o = widget.orb;
    final st = _state;

    final ExpressivePolygon polygon = switch (st) {
      _OrbState.idle => ExpressivePolygon.squircle,
      _OrbState.downloads => ExpressivePolygon.circle,
      _OrbState.playing => ExpressivePolygon.cookie9,
    };

    final Color bgColor = switch (st) {
      _OrbState.idle => cs.tertiaryContainer,
      _OrbState.downloads => cs.surfaceContainerHigh,
      _OrbState.playing => cs.surfaceContainerHigh,
    };

    final BorderSide side = switch (st) {
      _OrbState.idle => BorderSide(
        color: cs.outlineVariant.withValues(alpha: 0.45),
      ),
      _OrbState.downloads => BorderSide.none,
      _OrbState.playing => BorderSide(
        color: o.isPlaying
            ? cs.primary.withValues(alpha: 0.72)
            : cs.outlineVariant.withValues(alpha: 0.55),
        width: o.isPlaying ? 2.0 : 1.2,
      ),
    };

    final Widget content = switch (st) {
      _OrbState.idle => _buildIdleContent(context, o),
      _OrbState.downloads => _buildDownloadsContent(context, o),
      _OrbState.playing => _buildPlayingContent(context, o),
    };

    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _cookieSpin,
              builder: (_, child) => Transform.rotate(
                angle: st == _OrbState.playing
                    ? _cookieSpin.value * math.pi * 2
                    : 0.0,
                child: child,
              ),
              child: AnimatedContainer(
                duration: m3.motion.resolve(
                  context,
                  m3.motion.defaultSpatialDuration,
                ),
                curve: m3.motion.defaultSpatialCurve,
                decoration: ShapeDecoration(
                  color: bgColor,
                  shape: ExpressivePolygonBorder(
                    polygon: polygon,
                    side: side,
                  ),
                  shadows: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.30 : 0.09,
                      ),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: m3.motion.resolve(
              context,
              m3.motion.defaultSpatialDuration,
            ),
            switchInCurve: m3.motion.defaultSpatialCurve,
            switchOutCurve: m3.motion.effectsCurve,
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(
                scale: Tween(begin: 0.82, end: 1.0).animate(a),
                child: c,
              ),
            ),
            child: content,
          ),
        ],
      ),
    );
  }

  Widget _buildIdleContent(BuildContext context, PopDockOrb o) {
    final cs = context.cs;
    return Tooltip(
      key: const ValueKey('orb-idle'),
      message: 'Paste & Grab link',
      child: Semantics(
        button: true,
        label: 'Paste and grab link from clipboard',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.medium();
            o.onPasteGrab?.call();
          },
          child: SizedBox(
            width: 60,
            height: 60,
            child: Center(
              child: Icon(
                Icons.content_paste_go_rounded,
                color: cs.onTertiaryContainer,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadsContent(BuildContext context, PopDockOrb o) {
    final cs = context.cs;
    return Tooltip(
      key: const ValueKey('orb-downloads'),
      message: '${o.activeDownloads} active downloads',
      child: Semantics(
        button: true,
        label: '${o.activeDownloads} active downloads, open Downloads',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.selection();
            o.onOpenDownloads?.call();
          },
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (_, _) => SizedBox(
              width: 60,
              height: 60,
              child: CustomPaint(
                painter: _RadialOrbPainter(
                  progress: o.downloadProgress,
                  sweepPhase: _pulse.value * math.pi * 2,
                  trackColor: cs.surfaceContainerHighest,
                  activeColor: cs.primary,
                ),
                child: Center(
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${o.activeDownloads}',
                      style: TextStyle(
                        fontFamily: Pop.font,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayingContent(BuildContext context, PopDockOrb o) {
    final cs = context.cs;
    Widget inner(VoidCallback? onTap, {Key? key}) => Tooltip(
      key: key,
      message: o.playingTitle ?? 'Now playing',
      child: Semantics(
        button: true,
        label: o.playingTitle == null
            ? 'Now playing, tap to open player'
            : 'Now playing ${o.playingTitle}, tap to open player',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: o.onTogglePlay == null
              ? null
              : () {
                  Haptics.medium();
                  o.onTogglePlay!();
                },
          child: SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PopThumb(
                  seed: o.playingSeed!,
                  url: o.playingThumbUrl,
                  audio: true,
                  size: 40,
                  radius: BorderRadius.circular(20),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, child) {
                      final scale = o.isPlaying
                          ? 1.0 + 0.12 * math.sin(_pulse.value * math.pi * 2)
                          : 1.0;
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: cs.surfaceContainerHigh,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        o.isPlaying
                            ? Icons.graphic_eq_rounded
                            : Icons.pause_rounded,
                        size: 12,
                        color: cs.onPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (o.playingPageBuilder != null) {
      return Morph(
        key: const ValueKey('orb-playing'),
        shape: const ExpressivePolygonBorder(
          polygon: ExpressivePolygon.cookie9,
        ),
        color: Colors.transparent,
        pageColor: cs.surface,
        page: o.playingPageBuilder!,
        builder: (_, open) => inner(open),
      );
    }
    return inner(o.onOpenPlayer, key: const ValueKey('orb-playing'));
  }
}

class _RadialOrbPainter extends CustomPainter {
  const _RadialOrbPainter({
    required this.progress,
    required this.sweepPhase,
    required this.trackColor,
    required this.activeColor,
  });

  final double? progress;
  final double sweepPhase;
  final Color trackColor;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(6.0);

    canvas.drawArc(
      arcRect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = trackColor
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke,
    );

    final activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    if (progress == null) {
      canvas.drawArc(
        arcRect,
        -math.pi / 2 + sweepPhase,
        math.pi * 0.75,
        false,
        activePaint,
      );
    } else {
      final sweep = (progress!.clamp(0.0, 1.0) * math.pi * 2).clamp(
        0.15,
        math.pi * 2,
      );
      canvas.drawArc(arcRect, -math.pi / 2, sweep, false, activePaint);
    }
  }

  @override
  bool shouldRepaint(_RadialOrbPainter old) =>
      old.progress != progress ||
      old.sweepPhase != sweepPhase ||
      old.trackColor != trackColor ||
      old.activeColor != activeColor;
}

/// Preserves all tab states alive (like [IndexedStack]) while applying a
/// smooth Material 3 Expressive directional fade + subtle horizontal slide
/// between tab switches. Instant when reduced motion is active.
class ExpressiveTabStack extends StatefulWidget {
  const ExpressiveTabStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<ExpressiveTabStack> createState() => _ExpressiveTabStackState();
}

class _ExpressiveTabStackState extends State<ExpressiveTabStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1.0,
  );

  late int _current = widget.index;
  int? _previous;
  double _direction = 1.0;

  @override
  void initState() {
    super.initState();
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted && _previous != null) {
        setState(() => _previous = null);
      }
    });
  }

  @override
  void didUpdateWidget(ExpressiveTabStack old) {
    super.didUpdateWidget(old);
    if (widget.index != _current) {
      _previous = _current;
      _direction = widget.index > _current ? 1.0 : -1.0;
      _current = widget.index;
      final m3 = context.m3;
      if (m3.motion.reduced(context)) {
        _previous = null;
        _ctrl.value = 1.0;
      } else {
        _ctrl.duration = m3.motion.defaultSpatialDuration;
        _ctrl.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m3 = context.m3;
    final still = m3.motion.reduced(context);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final spatialT = still
            ? 1.0
            : m3.motion.defaultSpatialCurve.transform(_ctrl.value);
        final fadeT = still ? 1.0 : m3.motion.effectsCurve.transform(_ctrl.value);
        final animating = !still && _previous != null && _ctrl.isAnimating;

        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              _buildTabChild(
                i: i,
                child: widget.children[i],
                animating: animating,
                spatialT: spatialT,
                fadeT: fadeT,
              ),
          ],
        );
      },
    );
  }

  Widget _buildTabChild({
    required int i,
    required Widget child,
    required bool animating,
    required double spatialT,
    required double fadeT,
  }) {
    final isIncoming = i == _current;
    final isOutgoing = animating && i == _previous;
    final visible = isIncoming || isOutgoing;

    final double opacity;
    final Offset translation;
    if (animating && isIncoming) {
      opacity = fadeT.clamp(0.0, 1.0);
      translation = Offset(_direction * 0.05 * (1.0 - spatialT), 0.0);
    } else if (animating && isOutgoing) {
      opacity = (1.0 - fadeT).clamp(0.0, 1.0);
      translation = Offset(-_direction * 0.05 * fadeT, 0.0);
    } else {
      opacity = 1.0;
      translation = Offset.zero;
    }

    return Opacity(
      opacity: opacity,
      child: FractionalTranslation(
        translation: translation,
        child: TickerMode(
          enabled: isIncoming,
          child: Offstage(
            offstage: !visible,
            child: IgnorePointer(
              ignoring: !isIncoming,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
