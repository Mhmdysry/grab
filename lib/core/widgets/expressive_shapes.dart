import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/pop_theme.dart';
import '../utils/haptics.dart';

/// Organic Material 3 Expressive geometric & scalloped shapes.
enum ExpressivePolygon {
  circle,
  squircle,
  clover4,
  cookie6,
  cookie9,
  cookie12,
  arch,
  pill,
}

/// An [OutlinedBorder] that renders Material 3 Expressive organic polygons and
/// supports smooth shape morphing via [lerpFrom] / [lerpTo].
class ExpressivePolygonBorder extends OutlinedBorder {
  const ExpressivePolygonBorder({
    this.polygon = ExpressivePolygon.cookie9,
    this.morphTo,
    this.morphT = 0.0,
    this.rotation = 0.0,
    super.side,
  });

  final ExpressivePolygon polygon;
  final ExpressivePolygon? morphTo;
  final double morphT;
  final double rotation;

  static const _samples = 96;

  @override
  ExpressivePolygonBorder copyWith({
    BorderSide? side,
    ExpressivePolygon? polygon,
    ExpressivePolygon? morphTo,
    double? morphT,
    double? rotation,
  }) => ExpressivePolygonBorder(
    side: side ?? this.side,
    polygon: polygon ?? this.polygon,
    morphTo: morphTo ?? this.morphTo,
    morphT: morphT ?? this.morphT,
    rotation: rotation ?? this.rotation,
  );

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  ShapeBorder scale(double t) => copyWith(side: side.scale(t));

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is ExpressivePolygonBorder) {
      return ExpressivePolygonBorder(
        polygon: a.polygon,
        morphTo: polygon,
        morphT: t,
        rotation: lerpDouble(a.rotation, rotation, t) ?? rotation,
        side: BorderSide.lerp(a.side, side, t),
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is ExpressivePolygonBorder) {
      return ExpressivePolygonBorder(
        polygon: polygon,
        morphTo: b.polygon,
        morphT: t,
        rotation: lerpDouble(rotation, b.rotation, t) ?? rotation,
        side: BorderSide.lerp(side, b.side, t),
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _buildPath(rect.deflate(side.strokeInset));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _buildPath(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0) return;
    final path = _buildPath(rect.deflate(side.strokeInset / 2));
    canvas.drawPath(path, side.toPaint());
  }

  Path _buildPath(Rect rect) {
    if (rect.width <= 0 || rect.height <= 0) return Path();
    if (polygon == ExpressivePolygon.pill &&
        (morphTo == null || morphTo == ExpressivePolygon.pill)) {
      return Path()..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2)),
      );
    }

    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final rx = rect.width / 2;
    final ry = rect.height / 2;
    final path = Path();

    for (var i = 0; i <= _samples; i++) {
      final theta = (i / _samples) * math.pi * 2;
      final r1 = _polarRadius(polygon, theta);
      final r = morphTo == null
          ? r1
          : lerpDouble(r1, _polarRadius(morphTo!, theta), morphT)!;
      final angle = theta + rotation;
      final x = cx + rx * r * math.cos(angle);
      final y = cy + ry * r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
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
        // Dome top (sin < 0 in screen coords), softly squared bottom.
        final s = math.sin(theta);
        if (s <= 0) return 1.0;
        final c = math.cos(theta).abs();
        const n = 5.0;
        final denom = math.pow(math.pow(c, n) + math.pow(s, n), 1.0 / n);
        return (1.0 / denom).clamp(0.0, 1.0);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpressivePolygonBorder &&
          polygon == other.polygon &&
          morphTo == other.morphTo &&
          morphT == other.morphT &&
          rotation == other.rotation &&
          side == other.side;

  @override
  int get hashCode => Object.hash(polygon, morphTo, morphT, rotation, side);
}

/// Tinted organic M3 Expressive shape badge/container with smooth morphing.
class ExpressiveShapeContainer extends StatelessWidget {
  const ExpressiveShapeContainer({
    super.key,
    required this.polygon,
    this.size = 56,
    this.color,
    this.rotation = 0,
    this.side = BorderSide.none,
    this.child,
  });

  final ExpressivePolygon polygon;
  final double size;
  final Color? color;
  final double rotation;
  final BorderSide side;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final m3 = context.m3;
    final cs = context.cs;
    return AnimatedContainer(
      duration: m3.motion.resolve(context, m3.motion.defaultSpatialDuration),
      curve: m3.motion.defaultSpatialCurve,
      width: size,
      height: size,
      decoration: ShapeDecoration(
        color: color ?? cs.primaryContainer,
        shape: ExpressivePolygonBorder(
          polygon: polygon,
          rotation: rotation,
          side: side,
        ),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// Material 3 Expressive's signature shape-morphing loading indicator.
///
/// Continuously morphs through organic polygons (`clover4 → cookie6 → squircle → cookie9`)
/// with a gentle rotation. Collapses to a static emblem when motion is reduced.
class ExpressiveLoadingIndicator extends StatefulWidget {
  const ExpressiveLoadingIndicator({
    super.key,
    this.size = 44,
    this.color,
    this.containerColor,
    this.contained = true,
  });

  final double size;
  final Color? color;
  final Color? containerColor;
  final bool contained;

  @override
  State<ExpressiveLoadingIndicator> createState() =>
      _ExpressiveLoadingIndicatorState();
}

class _ExpressiveLoadingIndicatorState extends State<ExpressiveLoadingIndicator>
    with SingleTickerProviderStateMixin {
  static const _sequence = [
    ExpressivePolygon.clover4,
    ExpressivePolygon.cookie6,
    ExpressivePolygon.squircle,
    ExpressivePolygon.cookie9,
  ];

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = context.m3.motion.reduced(context);
    if (still) {
      _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final fg = widget.color ??
        (widget.contained ? cs.onPrimaryContainer : cs.primary);
    final bg = widget.containerColor ?? cs.primaryContainer;
    final innerSize = widget.contained ? widget.size * 0.58 : widget.size;

    final morpher = AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final scaled = _ctrl.value * _sequence.length;
        final idx = scaled.floor() % _sequence.length;
        final next = (idx + 1) % _sequence.length;
        final localT = Curves.easeInOutCubic.transform(scaled - scaled.floor());
        return SizedBox(
          width: innerSize,
          height: innerSize,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: fg,
              shape: ExpressivePolygonBorder(
                polygon: _sequence[idx],
                morphTo: _sequence[next],
                morphT: localT,
                rotation: _ctrl.value * math.pi * 2,
              ),
            ),
          ),
        );
      },
    );

    if (!widget.contained) return morpher;

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: morpher,
    );
  }
}

/// Material 3 Expressive wavy linear progress indicator.
///
/// Active track animates a gentle traveling sine wave; flattens smoothly to a
/// crisp bar when [wavy] is false, [active] is false, or motion is reduced.
class ExpressiveWavyProgressBar extends StatefulWidget {
  const ExpressiveWavyProgressBar({
    super.key,
    required this.value,
    this.height = 10,
    this.color,
    this.trackColor,
    this.wavy = true,
    this.active = true,
  });

  /// 0..1 progress, or `null` for indeterminate / waiting.
  final double? value;
  final double height;
  final Color? color;
  final Color? trackColor;
  final bool wavy;
  final bool active;

  @override
  State<ExpressiveWavyProgressBar> createState() =>
      _ExpressiveWavyProgressBarState();
}

class _ExpressiveWavyProgressBarState extends State<ExpressiveWavyProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  bool _shouldAnimate(BuildContext context) =>
      (widget.wavy || widget.value == null) &&
      widget.active &&
      !context.m3.motion.reduced(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(ExpressiveWavyProgressBar old) {
    super.didUpdateWidget(old);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (_shouldAnimate(context)) {
      if (!_phase.isAnimating) _phase.repeat();
    } else {
      _phase.stop();
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final motion = context.m3.motion;
    final reduced = motion.reduced(context);
    final activeColor = widget.color ?? cs.primary;
    final inactiveColor = widget.trackColor ?? cs.surfaceContainerHighest;
    final target = (widget.value ?? 0.0).clamp(0.0, 1.0);
    final targetAmp =
        widget.wavy && widget.active && !reduced && widget.value != null
            ? (widget.height * 0.28).clamp(1.8, 3.2)
            : 0.0;

    return Semantics(
      value: widget.value == null ? 'waiting' : '${(target * 100).round()}%',
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: target),
        duration: reduced
            ? Duration.zero
            : const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (_, progress, _) => TweenAnimationBuilder<double>(
          tween: Tween(end: targetAmp),
          duration: motion.resolve(context, motion.defaultEffectsDuration),
          curve: motion.effectsCurve,
          builder: (_, amp, _) => AnimatedBuilder(
            animation: _phase,
            builder: (_, _) => SizedBox(
              height: widget.height + 6,
              width: double.infinity,
              child: CustomPaint(
                painter: _WavyTrackPainter(
                  progress: widget.value == null ? null : progress,
                  phase: _phase.value * math.pi * 2,
                  amplitude: amp,
                  strokeWidth: (widget.height * 0.58).clamp(4.0, 8.0),
                  activeColor: activeColor,
                  trackColor: inactiveColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WavyTrackPainter extends CustomPainter {
  const _WavyTrackPainter({
    required this.progress,
    required this.phase,
    required this.amplitude,
    required this.strokeWidth,
    required this.activeColor,
    required this.trackColor,
  });

  final double? progress;
  final double phase;
  final double amplitude;
  final double strokeWidth;
  final Color activeColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final cy = size.height / 2;
    final capPad = strokeWidth / 2;
    final usableW = math.max(0.0, size.width - strokeWidth);

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Indeterminate / waiting state: sliding soft highlight on the track.
    if (progress == null) {
      canvas.drawLine(
        Offset(capPad, cy),
        Offset(size.width - capPad, cy),
        trackPaint,
      );
      final segW = usableW * 0.28;
      final t = (phase / (math.pi * 2)) % 1.0;
      final start = capPad + (usableW - segW) * t;
      canvas.drawLine(
        Offset(start, cy),
        Offset(start + segW, cy),
        activePaint,
      );
      return;
    }

    final p = progress!.clamp(0.0, 1.0);
    final activeEnd = capPad + usableW * p;
    final gap = p > 0.01 && p < 0.99 ? strokeWidth + 4.0 : 0.0;

    // Inactive track on the right of the gap.
    final inactiveStart = activeEnd + gap;
    if (inactiveStart < size.width - capPad) {
      canvas.drawLine(
        Offset(inactiveStart, cy),
        Offset(size.width - capPad, cy),
        trackPaint,
      );
      // M3 Expressive end stop indicator dot.
      canvas.drawCircle(
        Offset(size.width - capPad, cy),
        strokeWidth * 0.36,
        Paint()..color = activeColor.withValues(alpha: 0.7),
      );
    }

    // Active wavy (or flat) track on the left.
    if (p > 0.005) {
      if (amplitude <= 0.1 || activeEnd - capPad < 6) {
        canvas.drawLine(
          Offset(capPad, cy),
          Offset(activeEnd, cy),
          activePaint,
        );
      } else {
        const wavelength = 24.0;
        const k = (math.pi * 2) / wavelength;
        final path = Path();
        final span = activeEnd - capPad;
        final steps = math.max(12, (span / 2.5).ceil());
        for (var i = 0; i <= steps; i++) {
          final x = capPad + (span * i / steps);
          // Taper slightly at the ends so caps join smoothly.
          final edgeTaper = math.min(1.0, math.min(i / 4.0, (steps - i) / 4.0));
          final y = cy + math.sin(x * k - phase) * amplitude * edgeTaper;
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(path, activePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_WavyTrackPainter old) =>
      old.progress != progress ||
      old.phase != phase ||
      old.amplitude != amplitude ||
      old.strokeWidth != strokeWidth ||
      old.activeColor != activeColor ||
      old.trackColor != trackColor;
}

/// Android 16 Material 3 Expressive wavy / squiggly interactive audio scrubber.
///
/// Draws a traveling sine wave on the active segment while [isPlaying] is true,
/// smoothly flattening when paused or when reduced motion is active. Features a
/// vertical rounded pill thumb that expands slightly during dragging.
class ExpressiveWavySlider extends StatefulWidget {
  const ExpressiveWavySlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.isPlaying = true,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
    this.semanticLabel,
    this.semanticValue,
    this.height = 36,
  });

  /// Normalized progress in `0.0..1.0`.
  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final bool isPlaying;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? thumbColor;
  final String? semanticLabel;
  final String? semanticValue;
  final double height;

  @override
  State<ExpressiveWavySlider> createState() => _ExpressiveWavySliderState();
}

class _ExpressiveWavySliderState extends State<ExpressiveWavySlider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  var _dragging = false;
  double? _dragValue;
  int _lastBucket = -1;

  bool _shouldAnimate(BuildContext context) =>
      widget.isPlaying && !context.m3.motion.reduced(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(ExpressiveWavySlider old) {
    super.didUpdateWidget(old);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (_shouldAnimate(context)) {
      if (!_phase.isAnimating) _phase.repeat();
    } else {
      _phase.stop();
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  double _fractionFor(double dx, double width) {
    const pad = 10.0;
    final usable = math.max(1.0, width - pad * 2);
    return ((dx - pad) / usable).clamp(0.0, 1.0);
  }

  void _emit(double next) {
    final bucket = (next * 20).round();
    if (bucket != _lastBucket) {
      _lastBucket = bucket;
      Haptics.selection();
    }
    setState(() => _dragValue = next);
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    final reduced = m3.motion.reduced(context);
    final active = widget.activeColor ?? cs.primary;
    final inactive = widget.inactiveColor ?? cs.surfaceContainerHighest;
    final thumb = widget.thumbColor ?? active;

    final p = (_dragging ? (_dragValue ?? widget.value) : widget.value).clamp(
      0.0,
      1.0,
    );
    final targetAmp = widget.isPlaying && !reduced ? 3.5 : 0.0;
    final enabled = widget.onChanged != null;

    final incPct = '${((p + 0.05).clamp(0.0, 1.0) * 100).round()}%';
    final decPct = '${((p - 0.05).clamp(0.0, 1.0) * 100).round()}%';

    return Semantics(
      slider: true,
      enabled: enabled,
      label: widget.semanticLabel,
      value: widget.semanticValue ?? '${(p * 100).round()}%',
      increasedValue: enabled ? incPct : null,
      decreasedValue: enabled ? decPct : null,
      onIncrease: enabled
          ? () => widget.onChanged!((p + 0.05).clamp(0.0, 1.0))
          : null,
      onDecrease: enabled
          ? () => widget.onChanged!((p - 0.05).clamp(0.0, 1.0))
          : null,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: !enabled
                ? null
                : (d) {
                    final next = _fractionFor(d.localPosition.dx, w);
                    _lastBucket = (next * 20).round();
                    Haptics.selection();
                    widget.onChangeStart?.call(next);
                    widget.onChanged!(next);
                    widget.onChangeEnd?.call(next);
                  },
            onHorizontalDragStart: !enabled
                ? null
                : (d) {
                    final next = _fractionFor(d.localPosition.dx, w);
                    _lastBucket = (next * 20).round();
                    Haptics.selection();
                    setState(() {
                      _dragging = true;
                      _dragValue = next;
                    });
                    widget.onChangeStart?.call(next);
                    widget.onChanged!(next);
                  },
            onHorizontalDragUpdate: !enabled
                ? null
                : (d) => _emit(_fractionFor(d.localPosition.dx, w)),
            onHorizontalDragEnd: !enabled
                ? null
                : (_) {
                    final endVal = _dragValue ?? p;
                    setState(() {
                      _dragging = false;
                      _dragValue = null;
                    });
                    widget.onChangeEnd?.call(endVal);
                  },
            onHorizontalDragCancel: !enabled
                ? null
                : () {
                    setState(() {
                      _dragging = false;
                      _dragValue = null;
                    });
                  },
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: targetAmp),
              duration: m3.motion.resolve(
                context,
                m3.motion.defaultEffectsDuration,
              ),
              curve: m3.motion.effectsCurve,
              builder: (_, amp, _) => TweenAnimationBuilder<double>(
                tween: Tween(end: _dragging ? 1.0 : 0.0),
                duration: m3.motion.resolve(
                  context,
                  m3.motion.fastSpatialDuration,
                ),
                curve: m3.motion.fastSpatialCurve,
                builder: (_, dragT, _) => AnimatedBuilder(
                  animation: _phase,
                  builder: (_, _) => SizedBox(
                    height: widget.height,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _WavySliderPainter(
                        value: p,
                        phase: _phase.value * math.pi * 2,
                        amplitude: amp,
                        thumbWidth: lerpDouble(4.5, 6.2, dragT)!,
                        thumbHeight: lerpDouble(22.0, 27.0, dragT)!,
                        activeColor: active,
                        inactiveColor: inactive,
                        thumbColor: thumb,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WavySliderPainter extends CustomPainter {
  const _WavySliderPainter({
    required this.value,
    required this.phase,
    required this.amplitude,
    required this.thumbWidth,
    required this.thumbHeight,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
  });

  final double value;
  final double phase;
  final double amplitude;
  final double thumbWidth;
  final double thumbHeight;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    const pad = 10.0;
    const stroke = 4.5;
    const gap = 7.0;
    final cy = size.height / 2;
    final left = pad;
    final right = math.max(left, size.width - pad);
    final usable = right - left;
    final thumbX = left + usable * value.clamp(0.0, 1.0);

    final activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final inactivePaint = Paint()
      ..color = inactiveColor
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Inactive segment to the right of the pill thumb.
    final inactiveStart = thumbX + gap;
    if (inactiveStart < right - 2) {
      canvas.drawLine(
        Offset(inactiveStart, cy),
        Offset(right, cy),
        inactivePaint,
      );
      canvas.drawCircle(
        Offset(right, cy),
        stroke * 0.35,
        Paint()..color = activeColor.withValues(alpha: 0.65),
      );
    }

    // Active wavy (or flat) segment to the left of the pill thumb.
    final activeEnd = thumbX - gap;
    if (activeEnd > left + 2) {
      final span = activeEnd - left;
      if (amplitude <= 0.1 || span < 6) {
        canvas.drawLine(Offset(left, cy), Offset(activeEnd, cy), activePaint);
      } else {
        const wavelength = 22.0;
        const k = (math.pi * 2) / wavelength;
        final path = Path();
        final steps = math.max(12, (span / 2.2).ceil());
        for (var i = 0; i <= steps; i++) {
          final x = left + (span * i / steps);
          final taper = math.min(1.0, math.min(i / 4.0, (steps - i) / 4.0));
          final y = cy + math.sin((x - left) * k - phase) * amplitude * taper;
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(path, activePaint);
      }
    }

    // Vertical rounded pill thumb.
    final thumbRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(thumbX, cy),
        width: thumbWidth,
        height: thumbHeight,
      ),
      Radius.circular(thumbWidth / 2),
    );
    canvas.drawRRect(thumbRect, Paint()..color = thumbColor);
  }

  @override
  bool shouldRepaint(_WavySliderPainter old) =>
      old.value != value ||
      old.phase != phase ||
      old.amplitude != amplitude ||
      old.thumbWidth != thumbWidth ||
      old.thumbHeight != thumbHeight ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor ||
      old.thumbColor != thumbColor;
}

