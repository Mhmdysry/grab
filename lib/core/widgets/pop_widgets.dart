import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/settings/app_settings.dart';
import '../theme/pop_theme.dart';
import '../utils/audio_art.dart';
import '../utils/haptics.dart';
import 'expressive_shapes.dart';
import 'morph.dart';

/// Visual variant for [PopButton].
enum PopButtonStyle { filled, tonal, outlined }

/// Material 3 Expressive pill button with press-to-rounded-square shape morph
/// and spring physics feedback.
class PopButton extends StatefulWidget {
  const PopButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.height = 56,
    this.expand = true,
    this.icon,
    this.style = PopButtonStyle.filled,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final double height;
  final bool expand;
  final IconData? icon;
  final PopButtonStyle style;

  @override
  State<PopButton> createState() => _PopButtonState();
}

class _PopButtonState extends State<PopButton> {
  var _down = false;

  bool get _enabled => widget.onPressed != null && !widget.busy;

  @override
  Widget build(BuildContext context) {
    final m3 = context.m3;
    final cs = context.cs;
    final still = m3.motion.reduced(context);

    final Color bg;
    final Color fg;
    BorderSide side = BorderSide.none;

    if (!_enabled) {
      bg = cs.onSurface.withValues(alpha: 0.12);
      fg = cs.onSurface.withValues(alpha: 0.38);
    } else {
      switch (widget.style) {
        case PopButtonStyle.filled:
          bg = cs.primary;
          fg = cs.onPrimary;
        case PopButtonStyle.tonal:
          bg = cs.secondaryContainer;
          fg = cs.onSecondaryContainer;
        case PopButtonStyle.outlined:
          bg = Colors.transparent;
          fg = cs.primary;
          side = BorderSide(color: cs.outline, width: 1.5);
      }
    }

    final restingRadius = m3.shapeStyle == M3ShapeStyle.crisp
        ? 14.0
        : widget.height / 2;
    final pressedRadius = m3.shapeStyle == M3ShapeStyle.crisp ? 8.0 : 14.0;
    final radius = _down && !still ? pressedRadius : restingRadius;

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: _enabled
            ? () {
                Haptics.light();
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _down && !still ? 0.96 : 1.0,
          duration: m3.motion.resolve(context, m3.motion.fastSpatialDuration),
          curve: m3.motion.fastSpatialCurve,
          child: AnimatedContainer(
            duration: m3.motion.resolve(context, m3.motion.fastSpatialDuration),
            curve: m3.motion.fastSpatialCurve,
            height: widget.height,
            width: widget.expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: ShapeDecoration(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
                side: side,
              ),
              color: bg,
            ),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: m3.motion.resolve(
                context,
                m3.motion.fastEffectsDuration,
              ),
              child: widget.busy
                  ? ExpressiveLoadingIndicator(
                      key: const ValueKey('busy'),
                      size: 22,
                      color: fg,
                      contained: false,
                    )
                  : Row(
                      key: ValueKey(widget.label),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, color: fg, size: 20),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: fg,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tonal icon button with M3 Expressive press-to-squircle shape morph.
class PopIconButton extends StatefulWidget {
  const PopIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.background,
    this.foreground,
    this.size = 48,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? background;
  final Color? foreground;
  final double size;

  @override
  State<PopIconButton> createState() => _PopIconButtonState();
}

class _PopIconButtonState extends State<PopIconButton> {
  var _down = false;

  @override
  Widget build(BuildContext context) {
    final m3 = context.m3;
    final cs = context.cs;
    final still = m3.motion.reduced(context);
    final enabled = widget.onPressed != null;
    final bg = widget.background ?? cs.surfaceContainerHigh;
    final fg = widget.foreground ?? cs.onSurface;
    final restingRadius = m3.shapeStyle == M3ShapeStyle.crisp
        ? 12.0
        : widget.size / 2;
    final radius = _down && !still ? 12.0 : restingRadius;

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.tooltip,
        excludeSemantics: true,
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: enabled
              ? () {
                  Haptics.selection();
                  widget.onPressed!();
                }
              : null,
          child: AnimatedScale(
            scale: _down && !still ? 0.92 : 1.0,
            duration: m3.motion.resolve(context, m3.motion.fastSpatialDuration),
            curve: m3.motion.fastSpatialCurve,
            child: AnimatedContainer(
              duration: m3.motion.resolve(
                context,
                m3.motion.fastSpatialDuration,
              ),
              curve: m3.motion.fastSpatialCurve,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: enabled ? bg : bg.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(radius),
              ),
              alignment: Alignment.center,
              child: Icon(
                widget.icon,
                color: enabled ? fg : fg.withValues(alpha: 0.38),
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Material 3 Expressive Connected Button Group.
///
/// Unselected segments share tight inner corners; the selected segment morphs
/// into a full pill in `primaryContainer` with spring physics.
class PopSegmented<T> extends StatelessWidget {
  const PopSegmented({
    super.key,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final m3 = context.m3;
    final cs = context.cs;
    final index = values.indexOf(selected).clamp(0, values.length - 1);
    final n = values.length;
    final outer = m3.shapeStyle == M3ShapeStyle.crisp ? 12.0 : 26.0;
    final inner = m3.innerRadiusValue;

    return SizedBox(
      height: 50,
      child: Row(
        children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: _SegmentItem(
                label: labels[i],
                selected: i == index,
                radius: i == index
                    ? BorderRadius.circular(outer)
                    : BorderRadius.horizontal(
                        left: Radius.circular(i == 0 ? outer : inner),
                        right: Radius.circular(i == n - 1 ? outer : inner),
                      ),
                onTap: () {
                  Haptics.selection();
                  onChanged(values[i]);
                },
                selectedBg: cs.primaryContainer,
                selectedFg: cs.onPrimaryContainer,
                idleBg: cs.surfaceContainerHigh,
                idleFg: cs.onSurfaceVariant,
                compact: n >= 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SegmentItem extends StatelessWidget {
  const _SegmentItem({
    required this.label,
    required this.selected,
    required this.radius,
    required this.onTap,
    required this.selectedBg,
    required this.selectedFg,
    required this.idleBg,
    required this.idleFg,
    required this.compact,
  });

  final String label;
  final bool selected;
  final BorderRadius radius;
  final VoidCallback onTap;
  final Color selectedBg;
  final Color selectedFg;
  final Color idleBg;
  final Color idleFg;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final m3 = context.m3;
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: m3.motion.resolve(context, m3.motion.defaultSpatialDuration),
          curve: m3.motion.defaultSpatialCurve,
          decoration: BoxDecoration(
            color: selected ? selectedBg : idleBg,
            borderRadius: radius,
          ),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6),
          child: AnimatedDefaultTextStyle(
            duration: m3.motion.resolve(context, m3.motion.fastEffectsDuration),
            style: TextStyle(
              fontFamily: Pop.font,
              fontSize: compact ? 13 : 14,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? selectedFg : idleFg,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

/// Material 3 Expressive progress bar — wavy when active, flat when paused.
class PopProgressBar extends StatelessWidget {
  const PopProgressBar({
    super.key,
    required this.value,
    this.height = 10,
    this.color,
    this.track,
    this.wavy = true,
    this.active = true,
  });

  /// 0..1, or null for "waiting".
  final double? value;
  final double height;
  final Color? color;
  final Color? track;
  final bool wavy;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return ExpressiveWavyProgressBar(
      value: value,
      height: height,
      color: color,
      trackColor: track,
      wavy: wavy,
      active: active,
    );
  }
}

/// Rounded thumbnail with tonal M3 fallback and adaptive audio art.
class PopThumb extends StatelessWidget {
  const PopThumb({
    super.key,
    required this.seed,
    this.url,
    this.size = 56,
    this.audio = false,
    this.radius,
  });

  final String seed;
  final String? url;
  final double size;
  final bool audio;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = radius ?? context.m3.thumbRadius;
    if (audio && AudioArt.instance != null) {
      return _art(context, effectiveRadius);
    }
    final cs = context.cs;
    final glyph = Icon(
      audio ? Icons.music_note_rounded : Icons.play_arrow_rounded,
      color: cs.onPrimaryContainer,
      size: size.isFinite ? size * 0.42 : 56,
    );
    final fallback = ColoredBox(
      color: context.pop.tintFor(seed),
      child: Center(child: glyph),
    );
    return ClipRRect(
      borderRadius: effectiveRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: url == null || audio
            ? fallback
            : LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth.isFinite ? box.maxWidth : 400.0;
                  return Image.network(
                    url!,
                    fit: BoxFit.cover,
                    cacheWidth: (w * MediaQuery.devicePixelRatioOf(context))
                        .round()
                        .clamp(64, 1280),
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => fallback,
                    frameBuilder: (_, child, frame, sync) =>
                        sync || frame != null ? child : fallback,
                  );
                },
              ),
      ),
    );
  }

  /// Audio: line-drawn illustration tinted to harmonize with the active M3 scheme.
  Widget _art(BuildContext context, BorderRadius effectiveRadius) {
    final cs = context.cs;
    final i = AudioArt.instance!.indexFor(seed);
    return ClipRRect(
      borderRadius: effectiveRadius,
      child: Container(
        width: size,
        height: size,
        color: cs.primaryContainer,
        padding: const EdgeInsets.all(6),
        child: Image.asset(
          AudioArt.assetFor(i),
          fit: BoxFit.contain,
          color: cs.onPrimaryContainer,
          filterQuality: FilterQuality.medium,
          semanticLabel: 'Audio',
        ),
      ),
    );
  }
}

/// Small pill label, e.g. "MP4 · 1080p".
class PopTag extends StatelessWidget {
  const PopTag(this.text, {super.key, this.color, this.foreground});

  final String text;
  final Color? color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final bg = color ?? cs.secondaryContainer;
    final fg =
        foreground ?? (color == null ? cs.onSecondaryContainer : cs.onSurface);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: bg,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ),
    );
  }
}

/// Expressive section label in primary tint.
class PopSection extends StatelessWidget {
  const PopSection(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 10, left: 4),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
        color: context.cs.primary,
      ),
    ),
  );
}

/// M3 Expressive segmented card group (Android 16 Settings style: outer rounded
/// corners, tight inner corners separated by crisp surface gaps).
class ExpressiveGroup extends StatelessWidget {
  const ExpressiveGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final m3 = context.m3;
    final cs = context.cs;
    final outer = Radius.circular(m3.groupOuterRadiusValue);
    final inner = Radius.circular(m3.innerRadiusValue);
    final n = children.length;
    if (n == 0) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) const SizedBox(height: 3),
          Material(
            color: cs.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.vertical(
              top: i == 0 ? outer : inner,
              bottom: i == n - 1 ? outer : inner,
            ),
            child: children[i],
          ),
        ],
      ],
    );
  }
}

/// Standard row inside an [ExpressiveGroup].
class ExpressiveListRow extends StatelessWidget {
  const ExpressiveListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final m3 = context.m3;
    final cs = context.cs;
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              Haptics.selection();
              onTap!();
            },
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 18,
          vertical: m3.rowVerticalPad,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// One tab in [PopTabBar].
class PopTab {
  const PopTab(this.icon, this.label, {this.activeIcon, this.badge = 0});

  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final int badge;
}

/// Live companion orb state for the Dual-Island Split Floating Dock.
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
class PopTabBar extends StatefulWidget {
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
  State<PopTabBar> createState() => _PopTabBarState();
}

class _PopTabBarState extends State<PopTabBar> {
  late int _from = widget.index;

  @override
  void didUpdateWidget(PopTabBar old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _from = old.index;
  }

  @override
  Widget build(BuildContext context) {
    return switch (context.m3.navStyle) {
      M3NavStyle.floatingPill => _buildFloatingPill(context),
      M3NavStyle.dockedBar => _buildDockedBar(context),
      M3NavStyle.minimalDock => _buildMinimalDock(context),
    };
  }

  Widget _buildFloatingPill(BuildContext context) {
    final m3 = context.m3;
    final cs = context.cs;
    final still = m3.motion.reduced(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final n = widget.tabs.length;
    final movingRight = widget.index > _from;
    final fast = m3.motion.fastSpatialDuration;
    final slow = m3.motion.slowSpatialDuration;
    final radius = m3.shapeStyle == M3ShapeStyle.crisp ? 20.0 : 32.0;

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
                      color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, box) {
                    const pad = 5.0;
                    const activeFlex = 22.0;
                    const idleFlex = 10.0;
                    final unit =
                        (box.maxWidth - pad * 2) /
                        (idleFlex * (n - 1) + activeFlex);
                    final w = unit * activeFlex;
                    double left(int i) => pad + unit * idleFlex * i;
                    final maxRight = box.maxWidth - pad;
                    return Stack(
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(end: left(widget.index)),
                          duration: still
                              ? Duration.zero
                              : (movingRight ? slow : fast),
                          curve: m3.motion.defaultSpatialCurve,
                          builder: (_, l, _) => TweenAnimationBuilder<double>(
                            tween: Tween(end: left(widget.index) + w),
                            duration: still
                                ? Duration.zero
                                : (movingRight ? fast : slow),
                            curve: m3.motion.defaultSpatialCurve,
                            builder: (_, r, _) {
                              final clampedL = l.clamp(pad, maxRight - 40);
                              final clampedR = r.clamp(clampedL + 40, maxRight);
                              return Positioned(
                                left: clampedL,
                                width: math.max(clampedR - clampedL, 40),
                                top: pad,
                                bottom: pad,
                                child: DecoratedBox(
                                  decoration: ShapeDecoration(
                                    shape: m3.shapeStyle == M3ShapeStyle.crisp
                                        ? RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          )
                                        : const StadiumBorder(),
                                    color: cs.primaryContainer,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(pad),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < n; i++)
                                _floatingTab(context, i),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            _SmartStatusOrb(orb: widget.orb),
          ],
        ),
      ),
    );
  }

  Widget _floatingTab(BuildContext context, int i) {
    final tab = widget.tabs[i];
    final on = i == widget.index;
    final cs = context.cs;
    final m3 = context.m3;
    final iconData = on ? (tab.activeIcon ?? tab.icon) : tab.icon;
    return Expanded(
      flex: on ? 22 : 10,
      child: Semantics(
        selected: on,
        button: true,
        label: tab.badge > 0 ? '${tab.label}, ${tab.badge} active' : tab.label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (!on) Haptics.selection();
            widget.onChanged(i);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Badge(
                  isLabelVisible: tab.badge > 0,
                  backgroundColor: cs.error,
                  textColor: cs.onError,
                  label: Text('${tab.badge}'),
                  child: AnimatedScale(
                    scale: on ? 1.08 : 1.0,
                    duration: m3.motion.resolve(
                      context,
                      m3.motion.defaultSpatialDuration,
                    ),
                    curve: m3.motion.defaultSpatialCurve,
                    child: AnimatedSwitcher(
                      duration: m3.motion.resolve(
                        context,
                        m3.motion.fastEffectsDuration,
                      ),
                      child: Icon(
                        iconData,
                        key: ValueKey(iconData),
                        size: 22,
                        color: on ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: AnimatedSize(
                    duration: m3.motion.resolve(
                      context,
                      m3.motion.defaultSpatialDuration,
                    ),
                    curve: m3.motion.effectsCurve,
                    child: on
                        ? Padding(
                            padding: const EdgeInsets.only(left: 5),
                            child: Text(
                              tab.label,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDockedBar(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    return NavigationBar(
      selectedIndex: widget.index,
      animationDuration: m3.motion.resolve(
        context,
        m3.motion.defaultSpatialDuration,
      ),
      onDestinationSelected: (i) {
        if (i != widget.index) Haptics.selection();
        widget.onChanged(i);
      },
      destinations: [
        for (var i = 0; i < widget.tabs.length; i++)
          NavigationDestination(
            icon: Badge(
              isLabelVisible: widget.tabs[i].badge > 0,
              backgroundColor: cs.error,
              textColor: cs.onError,
              label: Text('${widget.tabs[i].badge}'),
              child: Icon(widget.tabs[i].icon),
            ),
            selectedIcon: Badge(
              isLabelVisible: widget.tabs[i].badge > 0,
              backgroundColor: cs.error,
              textColor: cs.onError,
              label: Text('${widget.tabs[i].badge}'),
              child: Icon(widget.tabs[i].activeIcon ?? widget.tabs[i].icon),
            ),
            label: widget.tabs[i].label,
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
                for (var i = 0; i < widget.tabs.length; i++)
                  _minimalTab(context, i),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _minimalTab(BuildContext context, int i) {
    final tab = widget.tabs[i];
    final on = i == widget.index;
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
          widget.onChanged(i);
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

/// Right-hand companion orb in the Dual-Island Split Floating Dock.
///
/// Morphs between:
/// 1. **Now Playing** (`playingSeed != null`): circular artwork + animated ring.
/// 2. **Active Downloads** (`activeDownloads > 0`): radial progress ring + count.
/// 3. **Idle**: tactile `tertiaryContainer` squircle for Quick Paste & Grab.
class _SmartStatusOrb extends StatefulWidget {
  const _SmartStatusOrb({required this.orb});

  final PopDockOrb orb;

  @override
  State<_SmartStatusOrb> createState() => _SmartStatusOrbState();
}

class _SmartStatusOrbState extends State<_SmartStatusOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  bool _needsAnimation(BuildContext context) {
    if (context.m3.motion.reduced(context)) return false;
    final o = widget.orb;
    if (o.playingSeed != null && o.isPlaying) return true;
    if (o.playingSeed == null &&
        o.activeDownloads > 0 &&
        o.downloadProgress == null) {
      return true;
    }
    return false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_SmartStatusOrb old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_needsAnimation(context)) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m3 = context.m3;
    final o = widget.orb;

    final Widget child;
    if (o.playingSeed != null) {
      child = _buildPlayingOrb(context, o);
    } else if (o.activeDownloads > 0) {
      child = _buildDownloadsOrb(context, o);
    } else {
      child = _buildIdleOrb(context, o);
    }

    return SizedBox(
      width: 58,
      height: 58,
      child: AnimatedSwitcher(
        duration: m3.motion.resolve(context, m3.motion.defaultSpatialDuration),
        switchInCurve: m3.motion.defaultSpatialCurve,
        switchOutCurve: m3.motion.effectsCurve,
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
            scale: Tween(begin: 0.82, end: 1.0).animate(a),
            child: c,
          ),
        ),
        child: child,
      ),
    );
  }

  Widget _buildPlayingOrb(BuildContext context, PopDockOrb o) {
    final cs = context.cs;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget content(VoidCallback? onTap, {Key? key}) => Tooltip(
      key: key,
      message: o.playingTitle ?? 'Now playing',
      child: Semantics(
        button: true,
        label: o.playingTitle == null
            ? 'Now playing, tap to open player'
            : 'Now playing ${o.playingTitle}, tap to open player',
        child: GestureDetector(
          onTap: onTap,
          onLongPress: o.onTogglePlay == null
              ? null
              : () {
                  Haptics.medium();
                  o.onTogglePlay!();
                },
          child: AnimatedBuilder(
            animation: _spin,
            builder: (_, _) {
              final pulse = o.isPlaying
                  ? 0.55 + 0.45 * math.sin(_spin.value * math.pi * 2)
                  : 0.25;
              return Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surfaceContainerHigh,
                  border: Border.all(
                    color: cs.primary.withValues(alpha: pulse),
                    width: o.isPlaying ? 2.5 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.28 : 0.08,
                      ),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(4),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PopThumb(
                      seed: o.playingSeed!,
                      url: o.playingThumbUrl,
                      audio: true,
                      size: 46,
                      radius: BorderRadius.circular(23),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
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
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    if (o.playingPageBuilder != null) {
      return Morph(
        key: const ValueKey('orb-playing'),
        shape: const CircleBorder(),
        color: cs.surfaceContainerHigh,
        pageColor: cs.surface,
        page: o.playingPageBuilder!,
        builder: (_, open) => content(open),
      );
    }
    return content(o.onOpenPlayer, key: const ValueKey('orb-playing'));
  }

  Widget _buildDownloadsOrb(BuildContext context, PopDockOrb o) {
    final cs = context.cs;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      key: const ValueKey('orb-downloads'),
      message: '${o.activeDownloads} active downloads',
      child: Semantics(
        button: true,
        label: '${o.activeDownloads} active downloads, open Downloads',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () {
            Haptics.selection();
            o.onOpenDownloads?.call();
          },
          child: AnimatedBuilder(
            animation: _spin,
            builder: (_, _) => Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.surfaceContainerHigh,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: CustomPaint(
                painter: _RadialOrbPainter(
                  progress: o.downloadProgress,
                  sweepPhase: _spin.value * math.pi * 2,
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

  Widget _buildIdleOrb(BuildContext context, PopDockOrb o) {
    final cs = context.cs;
    final m3 = context.m3;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = m3.shapeStyle == M3ShapeStyle.crisp ? 16.0 : 20.0;
    return Tooltip(
      key: const ValueKey('orb-idle'),
      message: 'Paste & Grab link',
      child: Semantics(
        button: true,
        label: 'Paste and grab link from clipboard',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () {
            Haptics.medium();
            o.onPasteGrab?.call();
          },
          child: Container(
            width: 58,
            height: 58,
            decoration: ShapeDecoration(
              color: cs.tertiaryContainer,
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(radius),
                side: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              shadows: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.content_paste_go_rounded,
              color: cs.onTertiaryContainer,
              size: 24,
            ),
          ),
        ),
      ),
    );
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
    final arcRect = rect.deflate(5.5);

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

/// Reusable Material 3 Expressive empty state with a gently rotating organic
/// polygon emblem, expressive typography, and an optional tonal CTA pill.
class ExpressiveEmptyState extends StatefulWidget {
  const ExpressiveEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.polygon = ExpressivePolygon.clover4,
    this.containerColor,
    this.iconColor,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final ExpressivePolygon polygon;
  final Color? containerColor;
  final Color? iconColor;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  State<ExpressiveEmptyState> createState() => _ExpressiveEmptyStateState();
}

class _ExpressiveEmptyStateState extends State<ExpressiveEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.m3.motion.reduced(context)) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    final bg = widget.containerColor ?? cs.tertiaryContainer;
    final fg = widget.iconColor ?? cs.onTertiaryContainer;

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: m3.cardRadius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 82,
            height: 82,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _spin,
                  builder: (_, _) => Transform.rotate(
                    angle: _spin.value * math.pi * 2,
                    child: ExpressiveShapeContainer(
                      polygon: widget.polygon,
                      size: 80,
                      color: bg,
                    ),
                  ),
                ),
                Icon(widget.icon, size: 36, color: fg),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
            ),
          ],
          if (widget.actionLabel != null && widget.onAction != null) ...[
            const SizedBox(height: 18),
            PopButton(
              label: widget.actionLabel!,
              icon: widget.actionIcon,
              style: PopButtonStyle.tonal,
              expand: false,
              height: 46,
              onPressed: widget.onAction,
            ),
          ],
        ],
      ),
    );
  }
}

/// Selectable option card with M3 Expressive shape morphing and spring checkmark.
class PopOptionTile extends StatelessWidget {
  const PopOptionTile({
    super.key,
    required this.label,
    this.size,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m3 = context.m3;
    final cs = context.cs;
    final radius = BorderRadius.circular(
      selected ? m3.cardRadiusValue + 8 : m3.cardRadiusValue,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          borderRadius: radius,
          onTap: () {
            Haptics.selection();
            onTap();
          },
          child: AnimatedContainer(
            duration: m3.motion.resolve(
              context,
              m3.motion.defaultSpatialDuration,
            ),
            curve: m3.motion.defaultSpatialCurve,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
              borderRadius: radius,
              border: Border.all(
                color: selected ? cs.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: m3.motion.resolve(
                    context,
                    m3.motion.fastSpatialDuration,
                  ),
                  transitionBuilder: (child, a) => ScaleTransition(
                    scale: CurvedAnimation(
                      parent: a,
                      curve: m3.motion.fastSpatialCurve,
                    ),
                    child: child,
                  ),
                  child: selected
                      ? Container(
                          key: const ValueKey(true),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: cs.onPrimary,
                          ),
                        )
                      : Icon(
                          Icons.radio_button_off_rounded,
                          key: const ValueKey(false),
                          color: cs.onSurfaceVariant,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: selected ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                  ),
                ),
                if (size != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    size!,
                    style: TextStyle(
                      color: selected
                          ? cs.onPrimaryContainer.withValues(alpha: 0.78)
                          : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
