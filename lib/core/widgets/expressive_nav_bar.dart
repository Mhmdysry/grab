import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../data/settings/app_settings.dart';
import '../theme/pop_theme.dart';
import '../utils/haptics.dart';
import 'expressive_shapes.dart';
import 'morph.dart';
import 'pop_widgets.dart';

/// Distinct selection animations for tabs in [ExpressiveFloatingNavBar].
enum PopTabAnimation { homeHop, libraryCascade, settingsSpin }

/// One tab in [PopTabBar] / [ExpressiveFloatingNavBar].
class PopTab {
  const PopTab(
    this.icon,
    this.label, {
    this.activeIcon,
    this.badge = 0,
    this.animation = PopTabAnimation.homeHop,
  });

  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final int badge;
  final PopTabAnimation animation;
}

/// Live companion orb state for the right-hand detached Companion Orb.
class PopDockOrb {
  const PopDockOrb({
    this.playingTitle,
    this.playingSeed,
    this.playingThumbUrl,
    this.isPlaying = false,
    this.playingProgress,
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

  /// `0.0..1.0` audio playback progress ratio (`position / duration`).
  final double? playingProgress;
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
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
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

/// Koda-Style Material 3 Expressive Floating Navigation Bar +
/// Spinning & Shape-Morphing Companion Orb.
///
/// Unselected tabs show only their icon; the selected tab expands into a
/// horizontal pill with `[Icon + Label]` side-by-side and triggers a
/// tab-specific M3 Expressive animation.
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
        height: 64,
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
                        alpha: isDark ? 0.34 : 0.10,
                      ),
                      blurRadius: 22,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < tabs.length; i++)
                        _KodaNavTab(
                          tab: tabs[i],
                          tabIndex: i,
                          selected: i == index,
                          onTap: () => onChanged(i),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            _MorphingCompanionOrb(orb: orb),
          ],
        ),
      ),
    );
  }
}

class _KodaNavTab extends StatefulWidget {
  const _KodaNavTab({
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
  State<_KodaNavTab> createState() => _KodaNavTabState();
}

class _KodaNavTabState extends State<_KodaNavTab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _impulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(_KodaNavTab old) {
    super.didUpdateWidget(old);
    if (!old.selected &&
        widget.selected &&
        !context.m3.motion.reduced(context)) {
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

  Widget _buildAnimatedIcon(
    BuildContext context, {
    required IconData iconData,
    required Color color,
    required bool still,
  }) {
    final baseIcon = Icon(
      iconData,
      key: ValueKey(iconData),
      size: 22,
      color: color,
    );

    return AnimatedBuilder(
      animation: _impulse,
      builder: (context, child) {
        final t = still ? 0.0 : _impulse.value;
        if (t <= 0.0001) return child!;

        switch (widget.tab.animation) {
          case PopTabAnimation.homeHop:
            final wave = math.sin(t * math.pi);
            final tiltSign = widget.tabIndex.isEven ? -1.0 : 1.0;
            return Transform.translate(
              offset: Offset(0, -3.2 * wave),
              child: Transform.rotate(
                angle: tiltSign * 0.035 * math.pi * 2 * wave,
                child: child,
              ),
            );

          case PopTabAnimation.libraryCascade:
            final wave = math.sin(t * math.pi);
            final rock = math.sin(t * math.pi * 2);
            final scale = 1.0 + 0.20 * wave;
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (wave > 0.04)
                  Transform.translate(
                    offset: Offset(-4.5 * wave, 2.8 * wave),
                    child: Transform.rotate(
                      angle: -0.16 * wave,
                      child: Opacity(
                        opacity: (0.40 * wave).clamp(0.0, 1.0),
                        child: Icon(
                          iconData,
                          size: 20,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                Transform.translate(
                  offset: Offset(1.5 * wave, -3.0 * wave),
                  child: Transform.rotate(
                    angle: 0.11 * rock,
                    child: Transform.scale(
                      scale: scale,
                      child: child,
                    ),
                  ),
                ),
              ],
            );

          case PopTabAnimation.settingsSpin:
            // Damped 270° circular gear spin with spring overshoot.
            final spinT = Curves.easeOutBack.transform(t.clamp(0.0, 1.0));
            final pulse = 1.0 + 0.14 * math.sin(t * math.pi);
            return Transform.scale(
              scale: pulse,
              child: Transform.rotate(
                angle: spinT * math.pi * 1.5,
                child: child,
              ),
            );
        }
      },
      child: Badge(
        isLabelVisible: widget.tab.badge > 0,
        backgroundColor: context.cs.error,
        textColor: context.cs.onError,
        label: Text('${widget.tab.badge}'),
        child: AnimatedSwitcher(
          duration: context.m3.motion.resolve(
            context,
            context.m3.motion.fastEffectsDuration,
          ),
          child: baseIcon,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    final still = m3.motion.reduced(context);
    final on = widget.selected;
    final iconData = on
        ? (widget.tab.activeIcon ?? widget.tab.icon)
        : widget.tab.icon;
    final pillRadius = m3.shapeStyle == M3ShapeStyle.crisp ? 14.0 : 999.0;
    final fg = on ? cs.onPrimaryContainer : cs.onSurfaceVariant;

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
        child: AnimatedContainer(
          duration: m3.motion.resolve(
            context,
            m3.motion.defaultSpatialDuration,
          ),
          curve: m3.motion.defaultSpatialCurve,
          padding: EdgeInsets.symmetric(
            horizontal: on ? 18 : 16,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: on ? cs.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(pillRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildAnimatedIcon(
                context,
                iconData: iconData,
                color: fg,
                still: still,
              ),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: on ? 1.0 : 0.0),
                duration: still
                    ? Duration.zero
                    : m3.motion.defaultSpatialDuration,
                curve: m3.motion.defaultSpatialCurve,
                builder: (context, t, child) {
                  final clamped = t.clamp(0.0, 1.0);
                  if (clamped <= 0.01) return const SizedBox.shrink();
                  return ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: clamped,
                      child: Opacity(
                        opacity: clamped,
                        child: child,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    widget.tab.label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontFamily: Pop.font,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: cs.onPrimaryContainer,
                      letterSpacing: -0.1,
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

/// Detached Koda-Style Shape-Morphing & Spinning Companion Orb (`64×64dp`).
///
/// - **Idle** → `ExpressivePolygon.squircle` (`tertiaryContainer`, Paste & Grab)
/// - **Active Downloads** → cycles & spins through Material 3 polygons while
///   painting a fixed-orientation progress border starting from 12 o'clock.
/// - **Playing Audio** → cycles & spins through Material 3 polygons while
///   spinning the full-bleed album art inside the shape; the progress border
///   stays anchored at 12 o'clock. When paused, stops at the exact last
///   Material shape and rotation angle.
///   - Single tap: play / pause
///   - Long press: open full player
class _MorphingCompanionOrb extends StatefulWidget {
  const _MorphingCompanionOrb({required this.orb});

  final PopDockOrb orb;

  @override
  State<_MorphingCompanionOrb> createState() => _MorphingCompanionOrbState();
}

class _MorphingCompanionOrbState extends State<_MorphingCompanionOrb>
    with TickerProviderStateMixin {
  static const List<ExpressivePolygon> _cycleShapes = [
    ExpressivePolygon.clover4,
    ExpressivePolygon.cookie6,
    ExpressivePolygon.squircle,
    ExpressivePolygon.cookie9,
    ExpressivePolygon.cookie12,
    ExpressivePolygon.arch,
  ];

  late final AnimationController _morphSpin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  late final AnimationController _indeterminateSweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  _OrbState get _state {
    final o = widget.orb;
    if (o.playingSeed != null) return _OrbState.playing;
    if (o.activeDownloads > 0) return _OrbState.downloads;
    return _OrbState.idle;
  }

  /// Current `(fromPolygon, toPolygon, morphT, spinAngle)` for the orb.
  (ExpressivePolygon, ExpressivePolygon, double, double) get _shapeMetrics {
    final st = _state;
    if (st == _OrbState.idle) {
      return (
        ExpressivePolygon.squircle,
        ExpressivePolygon.squircle,
        0.0,
        0.0,
      );
    }
    final v = _morphSpin.value.clamp(0.0, 1.0);
    final scaled = v * _cycleShapes.length;
    final idx = scaled.floor() % _cycleShapes.length;
    final nextIdx = (idx + 1) % _cycleShapes.length;
    final rawT = scaled - scaled.floor();
    final morphT = Curves.easeInOutCubic.transform(rawT.clamp(0.0, 1.0));
    // Two full rotations per 18s cycle so wrap-around at v=1.0->0.0 is seamless.
    final spinAngle = v * math.pi * 4;
    return (_cycleShapes[idx], _cycleShapes[nextIdx], morphT, spinAngle);
  }

  void _sync() {
    if (context.m3.motion.reduced(context)) {
      _morphSpin.stop(canceled: false);
      _indeterminateSweep.stop(canceled: false);
      return;
    }
    final o = widget.orb;
    final st = _state;
    final shouldSpinAndMorph =
        (st == _OrbState.playing && o.isPlaying) || st == _OrbState.downloads;
    if (shouldSpinAndMorph) {
      if (!_morphSpin.isAnimating) {
        _morphSpin.repeat();
      }
    } else {
      // Freeze at the exact current Material shape and rotation angle!
      _morphSpin.stop(canceled: false);
    }

    final needsIndeterminate =
        st == _OrbState.downloads && o.downloadProgress == null;
    if (needsIndeterminate) {
      if (!_indeterminateSweep.isAnimating) _indeterminateSweep.repeat();
    } else {
      _indeterminateSweep.stop(canceled: false);
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
    _morphSpin.dispose();
    _indeterminateSweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final o = widget.orb;
    final st = _state;

    return SizedBox(
      width: 64,
      height: 64,
      child: AnimatedBuilder(
        animation: Listenable.merge([_morphSpin, _indeterminateSweep]),
        builder: (context, _) {
          final (fromPoly, toPoly, morphT, spinAngle) = _shapeMetrics;
          final shapeBorder = ExpressivePolygonBorder(
            polygon: fromPoly,
            morphTo: toPoly,
            morphT: morphT,
            rotation: spinAngle,
          );

          final bgColor = switch (st) {
            _OrbState.idle => cs.tertiaryContainer,
            _OrbState.downloads => cs.surfaceContainerHigh,
            _OrbState.playing => cs.primaryContainer,
          };

          final double? progress = switch (st) {
            _OrbState.idle => null,
            _OrbState.downloads => o.downloadProgress,
            _OrbState.playing => (o.playingProgress ?? 0.0).clamp(0.0, 1.0),
          };

          return DecoratedBox(
            decoration: ShapeDecoration(
              color: bgColor,
              shape: shapeBorder,
              shadows: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: isDark ? 0.34 : 0.10,
                  ),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedSwitcher(
                  duration: m3.motion.resolve(
                    context,
                    m3.motion.defaultSpatialDuration,
                  ),
                  switchInCurve: m3.motion.defaultSpatialCurve,
                  switchOutCurve: m3.motion.effectsCurve,
                  child: switch (st) {
                    _OrbState.idle => _buildIdleContent(context, o),
                    _OrbState.downloads => _buildDownloadsContent(
                      context,
                      o,
                      fromPoly: fromPoly,
                      toPoly: toPoly,
                      morphT: morphT,
                      spinAngle: spinAngle,
                      progress: progress,
                    ),
                    _OrbState.playing => _buildPlayingContent(
                      context,
                      o,
                      fromPoly: fromPoly,
                      toPoly: toPoly,
                      morphT: morphT,
                      spinAngle: spinAngle,
                      progress: progress ?? 0.0,
                    ),
                  },
                ),
              ],
            ),
          );
        },
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
            width: 64,
            height: 64,
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

  Widget _buildDownloadsContent(
    BuildContext context,
    PopDockOrb o, {
    required ExpressivePolygon fromPoly,
    required ExpressivePolygon toPoly,
    required double morphT,
    required double spinAngle,
    required double? progress,
  }) {
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
          child: SizedBox(
            width: 64,
            height: 64,
            child: CustomPaint(
              painter: _FixedStartMorphProgressPainter(
                fromPolygon: fromPoly,
                toPolygon: toPoly,
                morphT: morphT,
                spinAngle: spinAngle,
                progress: progress,
                sweepPhase: _indeterminateSweep.value * math.pi * 2,
                trackColor: cs.outlineVariant.withValues(alpha: 0.45),
                activeColor: cs.primary,
                strokeWidth: 3.5,
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
    );
  }

  Widget _buildPlayingContent(
    BuildContext context,
    PopDockOrb o, {
    required ExpressivePolygon fromPoly,
    required ExpressivePolygon toPoly,
    required double morphT,
    required double spinAngle,
    required double progress,
  }) {
    final cs = context.cs;
    final innerBorder = ExpressivePolygonBorder(
      polygon: fromPoly,
      morphTo: toPoly,
      morphT: morphT,
      rotation: spinAngle,
    );

    Widget buildOrbBody(VoidCallback? openPlayer, {Key? key}) {
      return Tooltip(
        key: key,
        message: o.playingTitle ?? 'Now playing',
        child: Semantics(
          button: true,
          label: o.playingTitle == null
              ? 'Now playing, tap to play or pause, long press to open player'
              : 'Now playing ${o.playingTitle}, tap to play or pause, long press to open player',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Haptics.light();
              if (o.onTogglePlay != null) {
                o.onTogglePlay!();
              } else {
                openPlayer?.call();
              }
            },
            onLongPress: openPlayer == null
                ? null
                : () {
                    Haptics.medium();
                    openPlayer();
                  },
            child: SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Full-bleed album art clipped to the rotating & morphing M3 shape.
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: ClipPath(
                      clipper: ShapeBorderClipper(shape: innerBorder),
                      child: Transform.rotate(
                        angle: spinAngle,
                        child: Transform.scale(
                          scale: 1.24,
                          child: PopThumb(
                            seed: o.playingSeed!,
                            url: o.playingThumbUrl,
                            audio: true,
                            size: 56,
                            radius: BorderRadius.zero,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Subtle pause veil when paused so the user can tell at a glance,
                  // while keeping the exact last Material shape and album art visible.
                  if (!o.isPlaying)
                    Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: ClipPath(
                        clipper: ShapeBorderClipper(shape: innerBorder),
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.28),
                          child: const SizedBox.expand(
                            child: Center(
                              child: Icon(
                                Icons.play_arrow_rounded,
                                size: 22,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Fixed-orientation progress border tracing the spinning polygon perimeter
                  // from 12 o'clock clockwise without rotating its start anchor.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _FixedStartMorphProgressPainter(
                          fromPolygon: fromPoly,
                          toPolygon: toPoly,
                          morphT: morphT,
                          spinAngle: spinAngle,
                          progress: progress,
                          sweepPhase: 0.0,
                          trackColor: cs.primary.withValues(alpha: 0.28),
                          activeColor: cs.primary,
                          strokeWidth: 3.5,
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
    }

    if (o.playingPageBuilder != null) {
      return Morph(
        key: const ValueKey('orb-playing'),
        shape: innerBorder,
        color: Colors.transparent,
        pageColor: cs.surface,
        page: o.playingPageBuilder!,
        builder: (_, open) => buildOrbBody(open),
      );
    }
    return buildOrbBody(o.onOpenPlayer, key: const ValueKey('orb-playing'));
  }
}

/// Paints a track border and active progress stroke around the morphing &
/// spinning Material 3 polygon perimeter while keeping the progress start
/// anchored at 12 o'clock (`-math.pi / 2`) in screen coordinates.
class _FixedStartMorphProgressPainter extends CustomPainter {
  const _FixedStartMorphProgressPainter({
    required this.fromPolygon,
    required this.toPolygon,
    required this.morphT,
    required this.spinAngle,
    required this.progress,
    required this.sweepPhase,
    required this.trackColor,
    required this.activeColor,
    this.strokeWidth = 3.5,
  });

  final ExpressivePolygon fromPolygon;
  final ExpressivePolygon toPolygon;
  final double morphT;
  final double spinAngle;
  final double? progress;
  final double sweepPhase;
  final Color trackColor;
  final Color activeColor;
  final double strokeWidth;

  static const int _samples = 120;

  double _radiusAtScreenAngle(double screenAngle) {
    final localTheta = screenAngle - spinAngle;
    final r1 = _polarRadius(fromPolygon, localTheta);
    final r2 = _polarRadius(toPolygon, localTheta);
    return lerpDouble(r1, r2, morphT) ?? r1;
  }

  static double _polarRadius(ExpressivePolygon p, double theta) {
    switch (p) {
      case ExpressivePolygon.circle:
      case ExpressivePolygon.pill:
        return 1.0;
      case ExpressivePolygon.squircle:
        final c = math.cos(theta).abs();
        final s = math.sin(theta).abs();
        const n = 4.2;
        final denom = math.pow(math.pow(c, n) + math.pow(s, n), 1.0 / n);
        return (1.0 / denom).clamp(0.0, 1.0);
      case ExpressivePolygon.clover4:
        return 0.85 + 0.15 * math.cos(4 * (theta - math.pi / 4));
      case ExpressivePolygon.cookie6:
        return 0.89 + 0.11 * math.cos(6 * theta);
      case ExpressivePolygon.cookie9:
        return 0.915 + 0.085 * math.cos(9 * theta);
      case ExpressivePolygon.cookie12:
        return 0.935 + 0.065 * math.cos(12 * theta);
      case ExpressivePolygon.arch:
        final s = math.sin(theta);
        if (s <= 0) return 1.0;
        final c = math.cos(theta).abs();
        const n = 5.0;
        final denom = math.pow(math.pow(c, n) + math.pow(s, n), 1.0 / n);
        return (1.0 / denom).clamp(0.0, 1.0);
    }
  }

  Path _buildSubPath(Rect rect, double startAngle, double sweepAngle) {
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final rx = rect.width / 2;
    final ry = rect.height / 2;
    final steps = math.max(
      4,
      (_samples * (sweepAngle.abs() / (math.pi * 2))).ceil(),
    );
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final alpha = startAngle + (i / steps) * sweepAngle;
      final r = _radiusAtScreenAngle(alpha);
      final x = cx + rx * r * math.cos(alpha);
      final y = cy + ry * r * math.sin(alpha);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2 + 0.5);
    if (rect.width <= 0 || rect.height <= 0) return;

    final trackPath = _buildSubPath(rect, -math.pi / 2, math.pi * 2)..close();
    canvas.drawPath(
      trackPath,
      Paint()
        ..color = trackColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    final activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (progress == null) {
      // Indeterminate sweeping segment along the morphing contour.
      final seg = _buildSubPath(
        rect,
        -math.pi / 2 + sweepPhase,
        math.pi * 0.7,
      );
      canvas.drawPath(seg, activePaint);
    } else {
      final clamped = progress!.clamp(0.0, 1.0);
      if (clamped <= 0.005) return;
      final sweep = (clamped * math.pi * 2).clamp(0.08, math.pi * 2);
      final activePath = _buildSubPath(rect, -math.pi / 2, sweep);
      canvas.drawPath(activePath, activePaint);
    }
  }

  @override
  bool shouldRepaint(_FixedStartMorphProgressPainter old) =>
      old.fromPolygon != fromPolygon ||
      old.toPolygon != toPolygon ||
      old.morphT != morphT ||
      old.spinAngle != spinAngle ||
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
        final fadeT =
            still ? 1.0 : m3.motion.effectsCurve.transform(_ctrl.value);
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
