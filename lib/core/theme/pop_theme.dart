import 'dart:ui' show FontFeature;

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../../data/settings/app_settings.dart';
import '../motion/expressive_motion.dart';

/// Design token defaults and static helpers.
/// Dynamic theme-aware colors live in [PopColors] (`context.pop`),
/// [ColorScheme] (`context.cs`), and [M3ExpressiveTokens] (`context.m3`).
abstract final class Pop {
  /// Default Grab Amber seed & ink fallbacks (kept for legacy call sites).
  static const yellow = Color(0xFFFFD84D);
  static const ink = Color(0xFF141414);
  static const navIdle = Color(0xFFBDBDBD);
  static const error = Color(0xFFB3261E);
  static const thumbs = [
    Color(0xFFFFD84D),
    Color(0xFF9FD8FF),
    Color(0xFFFFB2C8),
  ];

  static const font = 'Outfit';
  static const cardRadius = BorderRadius.all(Radius.circular(28));
  static const thumbRadius = BorderRadius.all(Radius.circular(20));

  /// Baseline motion durations.
  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 280);

  /// Picks a stable fallback thumb tint for an item.
  static Color tintFor(String key) =>
      thumbs[key.hashCode.abs() % thumbs.length];

  /// True when either system "remove animations" or M3MotionPreset.off is active.
  static bool reduceMotion(BuildContext context) {
    final ext = Theme.of(context).extension<M3ExpressiveTokens>();
    if (ext != null && ext.motion.isReduced) return true;
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }
}

/// Material 3 Expressive design tokens (motion springs, shape scale, density, nav).
@immutable
class M3ExpressiveTokens extends ThemeExtension<M3ExpressiveTokens> {
  const M3ExpressiveTokens({
    required this.motion,
    required this.shapeStyle,
    required this.navStyle,
    required this.density,
    required this.confettiEnabled,
    required this.amoledDark,
  });

  final ExpressiveMotion motion;
  final M3ShapeStyle shapeStyle;
  final M3NavStyle navStyle;
  final M3Density density;
  final bool confettiEnabled;
  final bool amoledDark;

  static final fallback = M3ExpressiveTokens(
    motion: ExpressiveMotion.expressive,
    shapeStyle: M3ShapeStyle.expressive,
    navStyle: M3NavStyle.floatingPill,
    density: M3Density.cozy,
    confettiEnabled: true,
    amoledDark: false,
  );

  double get cardRadiusValue => switch (shapeStyle) {
    M3ShapeStyle.expressive => 28,
    M3ShapeStyle.balanced => 20,
    M3ShapeStyle.crisp => 12,
  };

  double get thumbRadiusValue => switch (shapeStyle) {
    M3ShapeStyle.expressive => 20,
    M3ShapeStyle.balanced => 14,
    M3ShapeStyle.crisp => 10,
  };

  double get groupOuterRadiusValue => switch (shapeStyle) {
    M3ShapeStyle.expressive => 24,
    M3ShapeStyle.balanced => 18,
    M3ShapeStyle.crisp => 12,
  };

  double get innerRadiusValue => switch (shapeStyle) {
    M3ShapeStyle.expressive => 8,
    M3ShapeStyle.balanced => 6,
    M3ShapeStyle.crisp => 4,
  };

  BorderRadius get cardRadius =>
      BorderRadius.all(Radius.circular(cardRadiusValue));

  BorderRadius get thumbRadius =>
      BorderRadius.all(Radius.circular(thumbRadiusValue));

  BorderRadius get innerRadius =>
      BorderRadius.all(Radius.circular(innerRadiusValue));

  double get cardPad => switch (density) {
    M3Density.compact => 12,
    M3Density.cozy => 16,
    M3Density.spacious => 20,
  };

  double get listGap => switch (density) {
    M3Density.compact => 8,
    M3Density.cozy => 12,
    M3Density.spacious => 16,
  };

  double get rowVerticalPad => switch (density) {
    M3Density.compact => 11,
    M3Density.cozy => 15,
    M3Density.spacious => 19,
  };

  double get thumbSize => switch (density) {
    M3Density.compact => 52,
    M3Density.cozy => 60,
    M3Density.spacious => 68,
  };

  @override
  M3ExpressiveTokens copyWith({
    ExpressiveMotion? motion,
    M3ShapeStyle? shapeStyle,
    M3NavStyle? navStyle,
    M3Density? density,
    bool? confettiEnabled,
    bool? amoledDark,
  }) => M3ExpressiveTokens(
    motion: motion ?? this.motion,
    shapeStyle: shapeStyle ?? this.shapeStyle,
    navStyle: navStyle ?? this.navStyle,
    density: density ?? this.density,
    confettiEnabled: confettiEnabled ?? this.confettiEnabled,
    amoledDark: amoledDark ?? this.amoledDark,
  );

  @override
  M3ExpressiveTokens lerp(M3ExpressiveTokens? other, double t) {
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }
}

/// Theme-dependent surface & accent slots, dynamically derived from [ColorScheme].
@immutable
class PopColors extends ThemeExtension<PopColors> {
  const PopColors({
    required this.bg,
    required this.text,
    required this.muted,
    required this.card,
    required this.field,
    required this.track,
    required this.soft,
    required this.trackOnSoft,
    required this.strong,
    required this.onStrong,
    required this.bar,
    required this.disabled,
    required this.errorSoft,
    this.thumbTints = Pop.thumbs,
  });

  factory PopColors.fromScheme(ColorScheme s) => PopColors(
    bg: s.surface,
    text: s.onSurface,
    muted: s.onSurfaceVariant,
    card: s.surfaceContainerLow,
    field: s.surfaceContainerHigh,
    track: s.surfaceContainerHighest,
    soft: s.primaryContainer,
    trackOnSoft: s.surfaceContainerLowest,
    strong: s.primary,
    onStrong: s.onPrimary,
    bar: s.surfaceContainerHigh,
    disabled: s.onSurface.withValues(alpha: 0.14),
    errorSoft: s.errorContainer,
    thumbTints: [
      s.primaryContainer,
      s.secondaryContainer,
      s.tertiaryContainer,
    ],
  );

  final Color bg;
  final Color text;
  final Color muted;
  final Color card;
  final Color field;
  final Color track;
  final Color soft;
  final Color trackOnSoft;
  final Color strong;
  final Color onStrong;
  final Color bar;
  final Color disabled;
  final Color errorSoft;
  final List<Color> thumbTints;

  Color tintFor(String key) =>
      thumbTints[key.hashCode.abs() % thumbTints.length];

  static const light = PopColors(
    bg: Colors.white,
    text: Pop.ink,
    muted: Color(0xFF555555),
    card: Color(0xFFF7F7F7),
    field: Color(0xFFF4F4F4),
    track: Color(0xFFEFEFEF),
    soft: Color(0xFFFFF1B8),
    trackOnSoft: Colors.white,
    strong: Pop.ink,
    onStrong: Pop.yellow,
    bar: Pop.ink,
    disabled: Color(0xFF3A3A3A),
    errorSoft: Color(0xFFFFE1E1),
  );

  static const dark = PopColors(
    bg: Color(0xFF121212),
    text: Color(0xFFF4F4F4),
    muted: Color(0xFFA8A8A8),
    card: Color(0xFF1E1E1E),
    field: Color(0xFF262626),
    track: Color(0xFF333333),
    soft: Color(0xFF3A3215),
    trackOnSoft: Color(0xFF1E1A0B),
    strong: Pop.yellow,
    onStrong: Pop.ink,
    bar: Color(0xFF242424),
    disabled: Color(0xFF3A3A3A),
    errorSoft: Color(0xFF4A2020),
  );

  @override
  PopColors copyWith({
    Color? bg,
    Color? text,
    Color? muted,
    Color? card,
    Color? field,
    Color? track,
    Color? soft,
    Color? trackOnSoft,
    Color? strong,
    Color? onStrong,
    Color? bar,
    Color? disabled,
    Color? errorSoft,
    List<Color>? thumbTints,
  }) => PopColors(
    bg: bg ?? this.bg,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    card: card ?? this.card,
    field: field ?? this.field,
    track: track ?? this.track,
    soft: soft ?? this.soft,
    trackOnSoft: trackOnSoft ?? this.trackOnSoft,
    strong: strong ?? this.strong,
    onStrong: onStrong ?? this.onStrong,
    bar: bar ?? this.bar,
    disabled: disabled ?? this.disabled,
    errorSoft: errorSoft ?? this.errorSoft,
    thumbTints: thumbTints ?? this.thumbTints,
  );

  @override
  PopColors lerp(PopColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return PopColors(
      bg: l(bg, other.bg),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      card: l(card, other.card),
      field: l(field, other.field),
      track: l(track, other.track),
      soft: l(soft, other.soft),
      trackOnSoft: l(trackOnSoft, other.trackOnSoft),
      strong: l(strong, other.strong),
      onStrong: l(onStrong, other.onStrong),
      bar: l(bar, other.bar),
      disabled: l(disabled, other.disabled),
      errorSoft: l(errorSoft, other.errorSoft),
      thumbTints: [
        for (var i = 0; i < thumbTints.length && i < other.thumbTints.length; i++)
          l(thumbTints[i], other.thumbTints[i]),
      ],
    );
  }
}

extension PopContext on BuildContext {
  PopColors get pop => Theme.of(this).extension<PopColors>() ?? PopColors.light;
  M3ExpressiveTokens get m3 =>
      Theme.of(this).extension<M3ExpressiveTokens>() ??
      M3ExpressiveTokens.fallback;
  ColorScheme get cs => Theme.of(this).colorScheme;
}

/// Builds Grab's Material 3 Expressive [ThemeData] from [AppSettings].
ThemeData buildExpressiveTheme(
  AppSettings settings, {
  required Brightness brightness,
  Color? dynamicSeed,
  Color? overrideSeed,
}) {
  final seed = overrideSeed ??
      (settings.useDynamicColor && dynamicSeed != null
          ? dynamicSeed
          : settings.accentPalette.seed);

  var scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: settings.schemeStyle.variant,
    contrastLevel: settings.contrast.level,
  );

  if (brightness == Brightness.dark && settings.amoledDark) {
    scheme = scheme.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0C0C0C),
      surfaceContainer: const Color(0xFF141414),
      surfaceContainerHigh: const Color(0xFF1B1B1B),
      surfaceContainerHighest: const Color(0xFF242424),
    );
  }

  final c = PopColors.fromScheme(scheme);
  final tokens = M3ExpressiveTokens(
    motion: ExpressiveMotion.forPreset(settings.motionPreset),
    shapeStyle: settings.shapeStyle,
    navStyle: settings.navStyle,
    density: settings.density,
    confettiEnabled: settings.confettiEnabled,
    amoledDark: settings.amoledDark,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: Pop.font,
    brightness: brightness,
  );

  final textTheme = base.textTheme
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
      .copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -1.4,
          height: 1.04,
        ),
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -1.1,
          height: 1.08,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.7,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );

  return base.copyWith(
    extensions: [c, tokens],
    scaffoldBackgroundColor: scheme.surface,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final p in TargetPlatform.values)
          p: _ExpressivePageTransitions(
            scheme.surface,
            reduced: tokens.motion.isReduced,
          ),
      },
    ),
    textTheme: textTheme,
    iconTheme: IconThemeData(color: scheme.onSurface),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: Pop.font,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: scheme.onSurface,
        letterSpacing: -0.3,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(
            settings.shapeStyle == M3ShapeStyle.crisp ? 16 : 999,
          ),
        ),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(
            settings.shapeStyle == M3ShapeStyle.crisp ? 16 : 999,
          ),
        ),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: scheme.secondaryContainer,
      selectedColor: scheme.primary,
      checkmarkColor: scheme.onPrimary,
      labelStyle: WidgetStateTextStyle.resolveWith(
        (states) => TextStyle(
          fontFamily: Pop.font,
          fontWeight: FontWeight.w700,
          color: states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSecondaryContainer,
        ),
      ),
      secondaryLabelStyle: TextStyle(
        fontFamily: Pop.font,
        fontWeight: FontWeight.w700,
        color: scheme.onPrimary,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.surfaceContainerHighest,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Colors.transparent
            : scheme.outlineVariant,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.14),
      trackHeight: 6,
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.all(scheme.primary),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.45),
      dragHandleSize: const Size(40, 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(tokens.cardRadiusValue + 4),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: tokens.cardRadius),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: const StadiumBorder(),
      height: 72,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: Pop.font,
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
          color: s.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
  );
}

/// Default Material 3 Expressive theme (Grab Amber).
ThemeData popTheme({Brightness brightness = Brightness.light}) =>
    buildExpressiveTheme(const AppSettings(), brightness: brightness);

/// Shared-axis zoom-and-fade between pages; instant when motion is reduced.
class _ExpressivePageTransitions extends PageTransitionsBuilder {
  const _ExpressivePageTransitions(this.fill, {required this.reduced});

  final Color fill;
  final bool reduced;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduced || MediaQuery.disableAnimationsOf(context)) return child;
    return SharedAxisPageTransitionsBuilder(
      transitionType: SharedAxisTransitionType.scaled,
      fillColor: fill,
    ).buildTransitions(route, context, animation, secondaryAnimation, child);
  }
}
