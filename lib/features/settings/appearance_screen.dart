import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/pop_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/expressive_shapes.dart';
import '../../core/widgets/pop_widgets.dart';
import '../../core/widgets/toasts.dart';
import '../../data/settings/app_settings.dart';

/// Live Material 3 Expressive Customization Studio.
class AppearanceScreen extends ConsumerStatefulWidget {
  const AppearanceScreen({super.key});

  @override
  ConsumerState<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends ConsumerState<AppearanceScreen> {
  var _bounceToggle = false;

  void _set(AppSettings Function(AppSettings) fn) {
    ref.read(settingsProvider.notifier).update(fn);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final dynamicSeed = ref.watch(dynamicColorProvider).value;
    final cs = context.cs;
    final m3 = context.m3;

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance Studio')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          MediaQuery.paddingOf(context).bottom + 32,
        ),
        children: [
          const _LivePreviewStage(),
          const SizedBox(height: 18),

          const PopSection('Theme & Surface'),
          PopSegmented<ThemeMode>(
            values: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
            labels: const ['System', 'Light', 'Dark'],
            selected: s.themeMode,
            onChanged: (m) => _set((x) => x.copyWith(themeMode: m)),
          ),
          const SizedBox(height: 12),
          ExpressiveGroup(
            children: [
              ExpressiveListRow(
                title: 'AMOLED Pure Black',
                subtitle: 'True #000000 canvas in dark mode',
                leading: Icon(
                  Icons.contrast_rounded,
                  color: cs.primary,
                ),
                trailing: Switch(
                  value: s.amoledDark,
                  onChanged: (v) {
                    Haptics.selection();
                    _set((x) => x.copyWith(amoledDark: v));
                  },
                ),
                onTap: () => _set((x) => x.copyWith(amoledDark: !s.amoledDark)),
              ),
              if (dynamicSeed != null)
                ExpressiveListRow(
                  title: 'Wallpaper Dynamic Color',
                  subtitle: 'Match your Android wallpaper palette',
                  leading: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: dynamicSeed,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: cs.outlineVariant,
                        width: 1.5,
                      ),
                    ),
                  ),
                  trailing: Switch(
                    value: s.useDynamicColor,
                    onChanged: (v) {
                      Haptics.selection();
                      _set((x) => x.copyWith(useDynamicColor: v));
                    },
                  ),
                  onTap: () => _set(
                    (x) => x.copyWith(useDynamicColor: !s.useDynamicColor),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 18),
          const PopSection('Expressive Palette'),
          AnimatedOpacity(
            duration: m3.motion.resolve(context, m3.motion.fastEffectsDuration),
            opacity: s.useDynamicColor && dynamicSeed != null ? 0.5 : 1.0,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: m3.cardRadius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final p in M3Palette.values)
                        _PaletteSwatch(
                          palette: p,
                          selected:
                              !(s.useDynamicColor && dynamicSeed != null) &&
                              s.accentPalette == p,
                          onTap: () {
                            Haptics.selection();
                            _set(
                              (x) => x.copyWith(
                                accentPalette: p,
                                useDynamicColor: false,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s.useDynamicColor && dynamicSeed != null
                        ? 'Using Android wallpaper color'
                        : s.accentPalette.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          const PopSection('Palette Style'),
          PopSegmented<M3SchemeStyle>(
            values: M3SchemeStyle.values,
            labels: [for (final v in M3SchemeStyle.values) v.label],
            selected: s.schemeStyle,
            onChanged: (v) => _set((x) => x.copyWith(schemeStyle: v)),
          ),

          const SizedBox(height: 16),
          const PopSection('Contrast'),
          PopSegmented<M3Contrast>(
            values: M3Contrast.values,
            labels: [for (final v in M3Contrast.values) v.label],
            selected: s.contrast,
            onChanged: (v) => _set((x) => x.copyWith(contrast: v)),
          ),

          const SizedBox(height: 18),
          const PopSection('Motion & Physics'),
          PopSegmented<M3MotionPreset>(
            values: M3MotionPreset.values,
            labels: [for (final v in M3MotionPreset.values) v.label],
            selected: s.motionPreset,
            onChanged: (v) => _set((x) => x.copyWith(motionPreset: v)),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.motionPreset.subtitle,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Haptics.light();
                    setState(() => _bounceToggle = !_bounceToggle);
                  },
                  child: AnimatedContainer(
                    duration: m3.motion.resolve(
                      context,
                      m3.motion.defaultSpatialDuration,
                    ),
                    curve: m3.motion.defaultSpatialCurve,
                    padding: EdgeInsets.symmetric(
                      horizontal: _bounceToggle ? 18 : 14,
                      vertical: 8,
                    ),
                    decoration: ShapeDecoration(
                      color: _bounceToggle
                          ? cs.primary
                          : cs.secondaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          _bounceToggle ? 12 : 999,
                        ),
                      ),
                    ),
                    child: Text(
                      'Test spring',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _bounceToggle
                            ? cs.onPrimary
                            : cs.onSecondaryContainer,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),
          const PopSection('Shape & Navigation'),
          PopSegmented<M3ShapeStyle>(
            values: M3ShapeStyle.values,
            labels: [for (final v in M3ShapeStyle.values) v.label],
            selected: s.shapeStyle,
            onChanged: (v) => _set((x) => x.copyWith(shapeStyle: v)),
          ),
          const SizedBox(height: 10),
          PopSegmented<M3NavStyle>(
            values: M3NavStyle.values,
            labels: [for (final v in M3NavStyle.values) v.label],
            selected: s.navStyle,
            onChanged: (v) => _set((x) => x.copyWith(navStyle: v)),
          ),

          const SizedBox(height: 18),
          const PopSection('Layout & Typography'),
          PopSegmented<M3Density>(
            values: M3Density.values,
            labels: [for (final v in M3Density.values) v.label],
            selected: s.density,
            onChanged: (v) => _set((x) => x.copyWith(density: v)),
          ),
          const SizedBox(height: 10),
          PopSegmented<int>(
            values: AppSettings.libraryColumnOptions,
            labels: const ['Library: 2 columns', 'Library: 3 columns'],
            selected: s.libraryColumns,
            onChanged: (v) => _set((x) => x.copyWith(libraryColumns: v)),
          ),
          const SizedBox(height: 10),
          PopSegmented<double>(
            values: AppSettings.fontScales,
            labels: const ['90%', '100%', '110%', '120%'],
            selected: s.fontScale,
            onChanged: (v) => _set((x) => x.copyWith(fontScale: v)),
          ),

          const SizedBox(height: 18),
          const PopSection('Feel & Extras'),
          ExpressiveGroup(
            children: [
              ExpressiveListRow(
                title: 'Dynamic artwork colors',
                subtitle: 'Tint Detail & Audio Player from media thumbnails',
                leading: Icon(Icons.colorize_rounded, color: cs.primary),
                trailing: Switch(
                  value: s.artworkTinting,
                  onChanged: (v) {
                    Haptics.selection();
                    _set((x) => x.copyWith(artworkTinting: v));
                  },
                ),
                onTap: () => _set(
                  (x) => x.copyWith(artworkTinting: !s.artworkTinting),
                ),
              ),
              ExpressiveListRow(
                title: 'Keep share popup open',
                subtitle: 'Watch progress inside the floating share window',
                leading: Icon(Icons.picture_in_picture_alt_rounded, color: cs.primary),
                trailing: Switch(
                  value: s.shareKeepOpen,
                  onChanged: (v) {
                    Haptics.selection();
                    _set((x) => x.copyWith(shareKeepOpen: v));
                  },
                ),
                onTap: () => _set(
                  (x) => x.copyWith(shareKeepOpen: !s.shareKeepOpen),
                ),
              ),
              ExpressiveListRow(
                title: 'Haptic feedback',
                subtitle: 'Crisp tactile taps on buttons and tabs',
                leading: Icon(Icons.vibration_rounded, color: cs.primary),
                trailing: Switch(
                  value: s.hapticsEnabled,
                  onChanged: (v) {
                    _set((x) => x.copyWith(hapticsEnabled: v));
                    if (v) {
                      Haptics.enabled = true;
                      Haptics.selection();
                    }
                  },
                ),
                onTap: () =>
                    _set((x) => x.copyWith(hapticsEnabled: !s.hapticsEnabled)),
              ),
              ExpressiveListRow(
                title: 'Completion confetti',
                subtitle: 'Celebrate when a download finishes',
                leading: Icon(Icons.celebration_rounded, color: cs.primary),
                trailing: Switch(
                  value: s.confettiEnabled,
                  onChanged: (v) {
                    Haptics.selection();
                    _set((x) => x.copyWith(confettiEnabled: v));
                  },
                ),
                onTap: () => _set(
                  (x) => x.copyWith(confettiEnabled: !s.confettiEnabled),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          PopButton(
            label: 'Reset appearance',
            icon: Icons.restart_alt_rounded,
            style: PopButtonStyle.tonal,
            onPressed: () {
              _set((x) => x.resetAppearance());
              popToast('Appearance reset to Grab Amber', context: context);
            },
          ),
        ],
      ),
    );
  }
}

/// Interactive mini-mockup at the top of the Customization Studio so every
/// palette, shape, motion, and density tweak previews live.
class _LivePreviewStage extends StatefulWidget {
  const _LivePreviewStage();

  @override
  State<_LivePreviewStage> createState() => _LivePreviewStageState();
}

class _LivePreviewStageState extends State<_LivePreviewStage> {
  var _playing = true;
  var _scrub = 0.68;
  var _dockTab = 0;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    return AnimatedContainer(
      duration: m3.motion.resolve(context, m3.motion.defaultSpatialDuration),
      curve: m3.motion.defaultSpatialCurve,
      padding: EdgeInsets.all(m3.cardPad),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.45),
        borderRadius: m3.cardRadius,
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExpressiveShapeContainer(
                polygon: _playing
                    ? ExpressivePolygon.cookie9
                    : ExpressivePolygon.squircle,
                size: 46,
                color: cs.primary,
                child: Icon(
                  Icons.music_note_rounded,
                  color: cs.onPrimary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Material 3 Expressive',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Live preview · ${(_scrub * 100).round()}% · Dual-Island & Wave',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const PopTag('1080p'),
            ],
          ),
          const SizedBox(height: 10),
          ExpressiveWavySlider(
            value: _scrub,
            isPlaying: _playing,
            activeColor: cs.primary,
            inactiveColor: cs.surfaceContainerLowest,
            thumbColor: cs.primary,
            onChanged: (v) => setState(() => _scrub = v),
          ),
          const SizedBox(height: 10),
          // Mini Dual-Island Split Floating Dock preview
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(
                      m3.shapeStyle == M3ShapeStyle.crisp ? 14 : 999,
                    ),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    children: [
                      for (final (i, icon, label) in const [
                        (0, Icons.home_rounded, 'Home'),
                        (1, Icons.download_rounded, 'Queue'),
                        (2, Icons.video_library_rounded, 'Files'),
                      ])
                        Expanded(
                          flex: _dockTab == i ? 2 : 1,
                          child: GestureDetector(
                            onTap: () {
                              Haptics.selection();
                              setState(() => _dockTab = i);
                            },
                            child: AnimatedContainer(
                              duration: m3.motion.resolve(
                                context,
                                m3.motion.defaultSpatialDuration,
                              ),
                              curve: m3.motion.defaultSpatialCurve,
                              decoration: BoxDecoration(
                                color: _dockTab == i
                                    ? cs.primaryContainer
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  m3.shapeStyle == M3ShapeStyle.crisp ? 10 : 999,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    icon,
                                    size: 16,
                                    color: _dockTab == i
                                        ? cs.onPrimaryContainer
                                        : cs.onSurfaceVariant,
                                  ),
                                  if (_dockTab == i) ...[
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        label,
                                        maxLines: 1,
                                        overflow: TextOverflow.fade,
                                        softWrap: false,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: cs.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer,
                  borderRadius: BorderRadius.circular(
                    m3.shapeStyle == M3ShapeStyle.crisp ? 12 : 16,
                  ),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  _playing
                      ? Icons.graphic_eq_rounded
                      : Icons.content_paste_go_rounded,
                  size: 19,
                  color: cs.onTertiaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PopButton(
                  label: _playing ? 'Pause wave' : 'Resume wave',
                  icon: _playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  height: 44,
                  onPressed: () => setState(() => _playing = !_playing),
                ),
              ),
              const SizedBox(width: 10),
              PopIconButton(
                icon: Icons.auto_awesome_rounded,
                tooltip: 'Sample toast',
                size: 44,
                background: cs.secondaryContainer,
                foreground: cs.onSecondaryContainer,
                onPressed: () => popToast(
                  'Looking expressive!',
                  icon: Icons.auto_awesome_rounded,
                  context: context,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final M3Palette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m3 = context.m3;
    final cs = context.cs;
    final preview = ColorScheme.fromSeed(
      seedColor: palette.seed,
      brightness: Theme.of(context).brightness,
    );
    return Tooltip(
      message: palette.label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 1.08 : 1.0,
          duration: m3.motion.resolve(context, m3.motion.fastSpatialDuration),
          curve: m3.motion.fastSpatialCurve,
          child: AnimatedContainer(
            duration: m3.motion.resolve(
              context,
              m3.motion.defaultSpatialDuration,
            ),
            curve: m3.motion.defaultSpatialCurve,
            width: 50,
            height: 50,
            decoration: ShapeDecoration(
              color: preview.primaryContainer,
              shape: ExpressivePolygonBorder(
                polygon: selected
                    ? ExpressivePolygon.cookie9
                    : ExpressivePolygon.circle,
                side: selected
                    ? BorderSide(color: cs.primary, width: 2.5)
                    : BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.4),
                      ),
              ),
            ),
            alignment: Alignment.center,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: preview.primary,
                shape: BoxShape.circle,
              ),
              child: selected
                  ? Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: preview.onPrimary,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
