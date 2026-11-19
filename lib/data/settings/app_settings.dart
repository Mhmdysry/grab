import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/media_info.dart';

/// Curated Material 3 Expressive seed palettes.
enum M3Palette {
  amber(Color(0xFFFFC107), 'Grab Amber'),
  coral(Color(0xFFFF5E5B), 'Coral'),
  violet(Color(0xFF7C4DFF), 'Violet'),
  emerald(Color(0xFF00BFA5), 'Emerald'),
  cobalt(Color(0xFF2979FF), 'Cobalt'),
  rose(Color(0xFFEC407A), 'Rose'),
  tangerine(Color(0xFFFF7043), 'Tangerine'),
  teal(Color(0xFF00ACC1), 'Teal'),
  slate(Color(0xFF607D8B), 'Slate');

  const M3Palette(this.seed, this.label);

  final Color seed;
  final String label;
}

/// Material 3 DynamicSchemeVariant presets.
enum M3SchemeStyle {
  expressive('Expressive', DynamicSchemeVariant.expressive),
  vibrant('Vibrant', DynamicSchemeVariant.vibrant),
  tonal('Tonal', DynamicSchemeVariant.tonalSpot),
  monochrome('Mono', DynamicSchemeVariant.monochrome);

  const M3SchemeStyle(this.label, this.variant);

  final String label;
  final DynamicSchemeVariant variant;
}

/// Material 3 contrast level.
enum M3Contrast {
  standard('Standard', 0.0),
  medium('Medium', 0.5),
  high('High', 1.0);

  const M3Contrast(this.label, this.level);

  final String label;
  final double level;
}

/// Material 3 Expressive spring physics preset.
enum M3MotionPreset {
  expressive('Expressive', 'Bouncy M3 springs & wavy motion'),
  standard('Standard', 'Smooth, balanced transitions'),
  snappy('Snappy', 'Fast, tight responses'),
  off('Off', 'Instant transitions, no bounce');

  const M3MotionPreset(this.label, this.subtitle);

  final String label;
  final String subtitle;
}

/// Corner roundness & organic shape personality.
enum M3ShapeStyle {
  expressive('Expressive'),
  balanced('Balanced'),
  crisp('Crisp');

  const M3ShapeStyle(this.label);

  final String label;
}

/// Bottom navigation bar style.
enum M3NavStyle {
  floatingPill('Floating'),
  dockedBar('Docked'),
  minimalDock('Minimal');

  const M3NavStyle(this.label);

  final String label;
}

/// Card & list spacing density.
enum M3Density {
  compact('Compact'),
  cozy('Cozy'),
  spacious('Spacious');

  const M3Density(this.label);

  final String label;
}

/// User preferences. Stored in SharedPreferences; small and read at startup.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.defaultMode = DownloadMode.video,
    this.maxHeight,
    this.container = 'mp4',
    this.audioFormat = 'mp3',
    this.maxParallel = 2,
    this.saveBase = 'download',
    this.saveFolder = 'Grab',
    this.fileTemplate = defaultFileTemplate,
    this.accentPalette = M3Palette.amber,
    this.useDynamicColor = false,
    this.schemeStyle = M3SchemeStyle.expressive,
    this.amoledDark = false,
    this.contrast = M3Contrast.standard,
    this.motionPreset = M3MotionPreset.expressive,
    this.shapeStyle = M3ShapeStyle.expressive,
    this.navStyle = M3NavStyle.floatingPill,
    this.density = M3Density.cozy,
    this.libraryColumns = 2,
    this.fontScale = 1.0,
    this.hapticsEnabled = true,
    this.confettiEnabled = true,
    this.artworkTinting = true,
    this.shareKeepOpen = false,
  });

  final ThemeMode themeMode;
  final DownloadMode defaultMode;

  /// Preferred video height; null = best available.
  final int? maxHeight;
  final String container;
  final String audioFormat;
  final int maxParallel;

  /// Public folder files go in: download | movies | music.
  final String saveBase;

  /// Folder name inside [saveBase].
  final String saveFolder;

  /// File names, e.g. "{title} - {site}".
  final String fileTemplate;

  /// Material 3 Expressive customization fields.
  final M3Palette accentPalette;
  final bool useDynamicColor;
  final M3SchemeStyle schemeStyle;
  final bool amoledDark;
  final M3Contrast contrast;
  final M3MotionPreset motionPreset;
  final M3ShapeStyle shapeStyle;
  final M3NavStyle navStyle;
  final M3Density density;
  final int libraryColumns;
  final double fontScale;
  final bool hapticsEnabled;
  final bool confettiEnabled;
  final bool artworkTinting;
  final bool shareKeepOpen;

  static const saveBases = ['download', 'movies', 'music'];

  static String baseLabel(String b) => switch (b) {
    'movies' => 'Movies',
    'music' => 'Music',
    _ => 'Download',
  };

  /// "Download/Grab"
  String get savePath => '${baseLabel(saveBase)}/$saveFolder';

  static const containers = ['mp4', 'mkv', 'webm'];
  static const audioFormats = ['mp3', 'm4a', 'opus', 'flac'];
  static const heights = [null, 2160, 1440, 1080, 720, 480, 360];
  static const libraryColumnOptions = [2, 3];
  static const fontScales = [0.9, 1.0, 1.1, 1.2];

  AppSettings copyWith({
    ThemeMode? themeMode,
    DownloadMode? defaultMode,
    int? Function()? maxHeight,
    String? container,
    String? audioFormat,
    int? maxParallel,
    String? saveBase,
    String? saveFolder,
    String? fileTemplate,
    M3Palette? accentPalette,
    bool? useDynamicColor,
    M3SchemeStyle? schemeStyle,
    bool? amoledDark,
    M3Contrast? contrast,
    M3MotionPreset? motionPreset,
    M3ShapeStyle? shapeStyle,
    M3NavStyle? navStyle,
    M3Density? density,
    int? libraryColumns,
    double? fontScale,
    bool? hapticsEnabled,
    bool? confettiEnabled,
    bool? artworkTinting,
    bool? shareKeepOpen,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    defaultMode: defaultMode ?? this.defaultMode,
    maxHeight: maxHeight != null ? maxHeight() : this.maxHeight,
    container: container ?? this.container,
    audioFormat: audioFormat ?? this.audioFormat,
    maxParallel: maxParallel ?? this.maxParallel,
    saveBase: saveBase ?? this.saveBase,
    saveFolder: saveFolder ?? this.saveFolder,
    fileTemplate: fileTemplate ?? this.fileTemplate,
    accentPalette: accentPalette ?? this.accentPalette,
    useDynamicColor: useDynamicColor ?? this.useDynamicColor,
    schemeStyle: schemeStyle ?? this.schemeStyle,
    amoledDark: amoledDark ?? this.amoledDark,
    contrast: contrast ?? this.contrast,
    motionPreset: motionPreset ?? this.motionPreset,
    shapeStyle: shapeStyle ?? this.shapeStyle,
    navStyle: navStyle ?? this.navStyle,
    density: density ?? this.density,
    libraryColumns: libraryColumns ?? this.libraryColumns,
    fontScale: fontScale ?? this.fontScale,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    confettiEnabled: confettiEnabled ?? this.confettiEnabled,
    artworkTinting: artworkTinting ?? this.artworkTinting,
    shareKeepOpen: shareKeepOpen ?? this.shareKeepOpen,
  );

  /// Resets only appearance & studio preferences while preserving download settings.
  AppSettings resetAppearance() => copyWith(
    themeMode: ThemeMode.system,
    accentPalette: M3Palette.amber,
    useDynamicColor: false,
    schemeStyle: M3SchemeStyle.expressive,
    amoledDark: false,
    contrast: M3Contrast.standard,
    motionPreset: M3MotionPreset.expressive,
    shapeStyle: M3ShapeStyle.expressive,
    navStyle: M3NavStyle.floatingPill,
    density: M3Density.cozy,
    libraryColumns: 2,
    fontScale: 1.0,
    hapticsEnabled: true,
    confettiEnabled: true,
    artworkTinting: true,
  );

  static AppSettings load(SharedPreferences p) {
    T pick<T>(List<T> options, T? value, T fallback) =>
        value != null && options.contains(value) ? value : fallback;
    T pickEnum<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;

    final mode = p.getString(
      'mode',
    ); // 'defaultMode' held the old mode names; ignored
    final h = p.getInt('maxHeight');
    final savedScale = p.getDouble('fontScale');
    final fontScale = savedScale != null
        ? fontScales
                  .where((f) => (f - savedScale).abs() < 0.01)
                  .firstOrNull ??
              1.0
        : 1.0;

    return AppSettings(
      themeMode: pickEnum(
        ThemeMode.values,
        p.getString('themeMode'),
        ThemeMode.system,
      ),
      // Subtitles-only is per-link; it is never a default.
      defaultMode:
          DownloadMode.values
              .where((m) => m.name == mode && m != DownloadMode.subtitlesOnly)
              .firstOrNull ??
          DownloadMode.video,
      maxHeight: h != null && heights.contains(h) ? h : null,
      container: pick(containers, p.getString('container'), 'mp4'),
      audioFormat: pick(audioFormats, p.getString('audioFormat'), 'mp3'),
      maxParallel: (p.getInt('maxParallel') ?? 2).clamp(1, 3),
      saveBase: pick(saveBases, p.getString('saveBase'), 'download'),
      saveFolder: p.getString('saveFolder') ?? 'Grab',
      fileTemplate: p.getString('fileTemplate') ?? defaultFileTemplate,
      accentPalette: pickEnum(
        M3Palette.values,
        p.getString('accentPalette'),
        M3Palette.amber,
      ),
      useDynamicColor: p.getBool('useDynamicColor') ?? false,
      schemeStyle: pickEnum(
        M3SchemeStyle.values,
        p.getString('schemeStyle'),
        M3SchemeStyle.expressive,
      ),
      amoledDark: p.getBool('amoledDark') ?? false,
      contrast: pickEnum(
        M3Contrast.values,
        p.getString('contrast'),
        M3Contrast.standard,
      ),
      motionPreset: pickEnum(
        M3MotionPreset.values,
        p.getString('motionPreset'),
        M3MotionPreset.expressive,
      ),
      shapeStyle: pickEnum(
        M3ShapeStyle.values,
        p.getString('shapeStyle'),
        M3ShapeStyle.expressive,
      ),
      navStyle: pickEnum(
        M3NavStyle.values,
        p.getString('navStyle'),
        M3NavStyle.floatingPill,
      ),
      density: pickEnum(
        M3Density.values,
        p.getString('density'),
        M3Density.cozy,
      ),
      libraryColumns: pick(
        libraryColumnOptions,
        p.getInt('libraryColumns'),
        2,
      ),
      fontScale: fontScale,
      hapticsEnabled: p.getBool('hapticsEnabled') ?? true,
      confettiEnabled: p.getBool('confettiEnabled') ?? true,
      artworkTinting: p.getBool('artworkTinting') ?? true,
      shareKeepOpen: p.getBool('shareKeepOpen') ?? false,
    );
  }

  Future<void> save(SharedPreferences p) async {
    await p.setString('themeMode', themeMode.name);
    await p.setString('mode', defaultMode.name);
    if (maxHeight == null) {
      await p.remove('maxHeight');
    } else {
      await p.setInt('maxHeight', maxHeight!);
    }
    await p.setString('container', container);
    await p.setString('audioFormat', audioFormat);
    await p.setInt('maxParallel', maxParallel);
    await p.setString('saveBase', saveBase);
    await p.setString('saveFolder', saveFolder);
    await p.setString('fileTemplate', fileTemplate);
    await p.setString('accentPalette', accentPalette.name);
    await p.setBool('useDynamicColor', useDynamicColor);
    await p.setString('schemeStyle', schemeStyle.name);
    await p.setBool('amoledDark', amoledDark);
    await p.setString('contrast', contrast.name);
    await p.setString('motionPreset', motionPreset.name);
    await p.setString('shapeStyle', shapeStyle.name);
    await p.setString('navStyle', navStyle.name);
    await p.setString('density', density.name);
    await p.setInt('libraryColumns', libraryColumns);
    await p.setDouble('fontScale', fontScale);
    await p.setBool('hapticsEnabled', hapticsEnabled);
    await p.setBool('confettiEnabled', confettiEnabled);
    await p.setBool('artworkTinting', artworkTinting);
    await p.setBool('shareKeepOpen', shareKeepOpen);
  }

  /// Index of the quality option closest to [maxHeight] without going over.
  /// Options are best first, so with no preference that is index 0.
  int preferredOptionIndex(List<QualityOption> options) {
    if (maxHeight == null) return 0;
    final i = options.indexWhere(
      (o) => o.height != null && o.height! <= maxHeight!,
    );
    return i < 0 ? options.length - 1 : i;
  }
}
