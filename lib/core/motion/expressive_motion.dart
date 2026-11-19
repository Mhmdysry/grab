import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../data/settings/app_settings.dart';

/// A [Curve] backed by Flutter's real [SpringSimulation] so implicit animation
/// widgets (`AnimatedContainer`, `AnimatedScale`, `AnimatedAlign`, etc.) move
/// with authentic Material 3 Expressive spring physics and overshoot.
class SpringCurve extends Curve {
  SpringCurve({
    required double stiffness,
    required double dampingRatio,
    double mass = 1.0,
  }) : _sim = SpringSimulation(
         SpringDescription.withDampingRatio(
           mass: mass,
           stiffness: stiffness,
           ratio: dampingRatio,
         ),
         0.0,
         1.0,
         0.0,
       ) {
    // Find approximate settling time so t in [0, 1] maps smoothly to [0, settle].
    var t = 0.05;
    while (t < 1.5 && !_sim.isDone(t)) {
      t += 0.016;
    }
    _settledSeconds = t.clamp(0.15, 1.5);
  }

  final SpringSimulation _sim;
  late final double _settledSeconds;

  /// Suggested duration matching this spring's physical settling time.
  Duration get duration => Duration(milliseconds: (_settledSeconds * 1000).round());

  @override
  double transformInternal(double t) {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;
    return _sim.x(t * _settledSeconds);
  }
}

/// Material 3 Expressive motion token set derived from [M3MotionPreset].
///
/// Follows Google's M3 Expressive motion scheme:
/// - **Spatial** springs animate position, scale, size, and shape morphing (can bounce).
/// - **Effects** curves animate color, opacity, and tonal elevation (never bounce).
@immutable
class ExpressiveMotion {
  const ExpressiveMotion({
    required this.preset,
    required this.isReduced,
    required this.fastSpatialDuration,
    required this.defaultSpatialDuration,
    required this.slowSpatialDuration,
    required this.fastSpatialCurve,
    required this.defaultSpatialCurve,
    required this.slowSpatialCurve,
    required this.fastEffectsDuration,
    required this.defaultEffectsDuration,
    required this.effectsCurve,
  });

  final M3MotionPreset preset;
  final bool isReduced;

  final Duration fastSpatialDuration;
  final Duration defaultSpatialDuration;
  final Duration slowSpatialDuration;

  final Curve fastSpatialCurve;
  final Curve defaultSpatialCurve;
  final Curve slowSpatialCurve;

  final Duration fastEffectsDuration;
  final Duration defaultEffectsDuration;
  final Curve effectsCurve;

  /// True when either the user chose `M3MotionPreset.off` or the OS has
  /// "Remove animations" enabled.
  bool reduced(BuildContext context) =>
      isReduced || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  Duration resolve(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;

  static final ExpressiveMotion expressive = _build(
    M3MotionPreset.expressive,
    fast: SpringCurve(stiffness: 800, dampingRatio: 0.65),
    def: SpringCurve(stiffness: 380, dampingRatio: 0.68),
    slow: SpringCurve(stiffness: 200, dampingRatio: 0.72),
    fastEffects: const Duration(milliseconds: 140),
    defEffects: const Duration(milliseconds: 240),
  );

  static final ExpressiveMotion standard = _build(
    M3MotionPreset.standard,
    fast: SpringCurve(stiffness: 900, dampingRatio: 0.88),
    def: SpringCurve(stiffness: 450, dampingRatio: 0.88),
    slow: SpringCurve(stiffness: 240, dampingRatio: 0.90),
    fastEffects: const Duration(milliseconds: 140),
    defEffects: const Duration(milliseconds: 220),
  );

  static final ExpressiveMotion snappy = _build(
    M3MotionPreset.snappy,
    fast: SpringCurve(stiffness: 1400, dampingRatio: 0.85),
    def: SpringCurve(stiffness: 900, dampingRatio: 0.85),
    slow: SpringCurve(stiffness: 500, dampingRatio: 0.88),
    fastEffects: const Duration(milliseconds: 90),
    defEffects: const Duration(milliseconds: 150),
  );

  static const ExpressiveMotion off = ExpressiveMotion(
    preset: M3MotionPreset.off,
    isReduced: true,
    fastSpatialDuration: Duration.zero,
    defaultSpatialDuration: Duration.zero,
    slowSpatialDuration: Duration.zero,
    fastSpatialCurve: Curves.linear,
    defaultSpatialCurve: Curves.linear,
    slowSpatialCurve: Curves.linear,
    fastEffectsDuration: Duration.zero,
    defaultEffectsDuration: Duration.zero,
    effectsCurve: Curves.linear,
  );

  static ExpressiveMotion forPreset(M3MotionPreset preset) => switch (preset) {
    M3MotionPreset.expressive => expressive,
    M3MotionPreset.standard => standard,
    M3MotionPreset.snappy => snappy,
    M3MotionPreset.off => off,
  };

  static ExpressiveMotion _build(
    M3MotionPreset preset, {
    required SpringCurve fast,
    required SpringCurve def,
    required SpringCurve slow,
    required Duration fastEffects,
    required Duration defEffects,
  }) => ExpressiveMotion(
    preset: preset,
    isReduced: false,
    fastSpatialDuration: fast.duration,
    defaultSpatialDuration: def.duration,
    slowSpatialDuration: slow.duration,
    fastSpatialCurve: fast,
    defaultSpatialCurve: def,
    slowSpatialCurve: slow,
    fastEffectsDuration: fastEffects,
    defaultEffectsDuration: defEffects,
    effectsCurve: Curves.easeOutCubic,
  );
}
