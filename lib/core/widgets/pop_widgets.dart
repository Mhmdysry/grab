import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/settings/app_settings.dart';
import '../theme/pop_theme.dart';
import '../utils/audio_art.dart';
import '../utils/haptics.dart';
import 'expressive_shapes.dart';

export 'expressive_nav_bar.dart';

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

/// Mono-safe Material 3 Expressive animated pill chip matching the contrast-shifting
/// behavior of the `Instant Grab` button across all palettes (including Monochrome).
class ExpressivePillChip extends StatelessWidget {
  const ExpressivePillChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.showCheckmark = false,
    this.onTap,
    this.semanticLabel,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final bool showCheckmark;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    final enabled = onTap != null;
    final fg = selected ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    final bg = selected ? cs.primaryContainer : cs.surfaceContainerHigh;
    final side = BorderSide(
      color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5),
      width: selected ? 1.5 : 1.0,
    );
    final shape = m3.shapeStyle == M3ShapeStyle.crisp
        ? RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: side,
          )
        : StadiumBorder(side: side);
    final effectiveIcon = selected && showCheckmark ? Icons.check_rounded : icon;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                Haptics.selection();
                onTap!();
              }
            : null,
        child: AnimatedContainer(
          duration: m3.motion.resolve(
            context,
            m3.motion.defaultSpatialDuration,
          ),
          curve: m3.motion.defaultSpatialCurve,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: ShapeDecoration(
            color: enabled ? bg : bg.withValues(alpha: 0.5),
            shape: shape,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (effectiveIcon != null) ...[
                Icon(
                  effectiveIcon,
                  size: 17,
                  color: enabled ? fg : fg.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: Pop.font,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  color: enabled ? fg : fg.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
