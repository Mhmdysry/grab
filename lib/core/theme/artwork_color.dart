import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'pop_theme.dart';

/// In-memory LRU cache for extracted artwork seed colors.
abstract final class ArtworkColorCache {
  static const _maxEntries = 64;
  static final _entries = LinkedHashMap<String, Color>();

  static Color? get(String key) {
    final c = _entries.remove(key);
    if (c != null) _entries[key] = c;
    return c;
  }

  static void put(String key, Color color) {
    _entries.remove(key);
    if (_entries.length >= _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = color;
  }

  static void clear() => _entries.clear();
}

/// Extracts the most expressive dominant seed color from [provider] using
/// pure `dart:ui` (`ResizeImage` -> `rawRgba`), scoring pixels by saturation
/// and balanced luminance. Returns `null` if decoding fails or times out.
Future<Color?> extractArtworkSeed(
  ImageProvider provider, {
  String? cacheKey,
}) async {
  if (cacheKey != null) {
    final cached = ArtworkColorCache.get(cacheKey);
    if (cached != null) return cached;
  }

  final resized = ResizeImage(provider, width: 48, height: 48);
  final stream = resized.resolve(ImageConfiguration.empty);
  final completer = Completer<ui.Image?>();

  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (ImageInfo info, bool _) {
      stream.removeListener(listener);
      if (!completer.isCompleted) {
        completer.complete(info.image.clone());
      }
      info.dispose();
    },
    onError: (_, _) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete(null);
    },
  );

  stream.addListener(listener);
  ui.Image? image;
  try {
    image = await completer.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () {
        stream.removeListener(listener);
        return null;
      },
    );
    if (image == null) return null;
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) return null;

    final seed = scoreRgbaForSeed(bytes.buffer.asUint8List());
    if (seed != null && cacheKey != null) {
      ArtworkColorCache.put(cacheKey, seed);
    }
    return seed;
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
  }
}

/// Scores raw RGBA pixel bytes by saturation and balanced luminance across 24
/// hue buckets and returns the most expressive dominant color.
Color? scoreRgbaForSeed(List<int> rgba) {
  const buckets = 24;
  final scores = List<double>.filled(buckets, 0);
  final sumR = List<double>.filled(buckets, 0);
  final sumG = List<double>.filled(buckets, 0);
  final sumB = List<double>.filled(buckets, 0);
  final sumW = List<double>.filled(buckets, 0);

  var fallbackR = 0.0;
  var fallbackG = 0.0;
  var fallbackB = 0.0;
  var fallbackCount = 0;

  for (var i = 0; i + 3 < rgba.length; i += 4) {
    final a = rgba[i + 3];
    if (a < 128) continue;
    final r = rgba[i];
    final g = rgba[i + 1];
    final b = rgba[i + 2];

    fallbackR += r;
    fallbackG += g;
    fallbackB += b;
    fallbackCount++;

    final hsl = HSLColor.fromColor(Color.fromARGB(255, r, g, b));
    if (hsl.saturation < 0.14) continue;
    if (hsl.lightness < 0.12 || hsl.lightness > 0.90) continue;

    final bucket = (hsl.hue / 15.0).floor() % buckets;
    final lumBalance = (1.0 - (hsl.lightness - 0.5).abs() * 1.4).clamp(
      0.2,
      1.0,
    );
    final weight = (0.35 + hsl.saturation * 0.65) * lumBalance;

    scores[bucket] += weight;
    sumR[bucket] += r * weight;
    sumG[bucket] += g * weight;
    sumB[bucket] += b * weight;
    sumW[bucket] += weight;
  }

  var bestBucket = -1;
  var bestScore = 0.0;
  for (var b = 0; b < buckets; b++) {
    if (scores[b] > bestScore) {
      bestScore = scores[b];
      bestBucket = b;
    }
  }

  if (bestBucket >= 0 && sumW[bestBucket] > 0) {
    final w = sumW[bestBucket];
    return Color.fromARGB(
      255,
      (sumR[bestBucket] / w).round().clamp(0, 255),
      (sumG[bestBucket] / w).round().clamp(0, 255),
      (sumB[bestBucket] / w).round().clamp(0, 255),
    );
  }

  if (fallbackCount > 0) {
    return Color.fromARGB(
      255,
      (fallbackR / fallbackCount).round().clamp(0, 255),
      (fallbackG / fallbackCount).round().clamp(0, 255),
      (fallbackB / fallbackCount).round().clamp(0, 255),
    );
  }
  return null;
}

/// Wraps [child] in an [AnimatedTheme] dynamically seeded from [imageUrl]
/// when `settings.artworkTinting` is enabled.
class ArtworkThemeScope extends ConsumerStatefulWidget {
  const ArtworkThemeScope({
    super.key,
    required this.child,
    this.imageUrl,
    this.cacheKey,
    this.imageProvider,
  });

  final Widget child;
  final String? imageUrl;
  final String? cacheKey;
  final ImageProvider? imageProvider;

  @override
  ConsumerState<ArtworkThemeScope> createState() => _ArtworkThemeScopeState();
}

class _ArtworkThemeScopeState extends ConsumerState<ArtworkThemeScope> {
  Color? _seed;
  String? _activeKey;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ArtworkThemeScope old) {
    super.didUpdateWidget(old);
    if (old.imageUrl != widget.imageUrl ||
        old.cacheKey != widget.cacheKey ||
        old.imageProvider != widget.imageProvider) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final provider =
        widget.imageProvider ??
        (widget.imageUrl != null && widget.imageUrl!.isNotEmpty
            ? NetworkImage(widget.imageUrl!)
            : null);
    final key = widget.cacheKey ?? widget.imageUrl;
    _activeKey = key;
    if (provider == null) {
      if (_seed != null && mounted) setState(() => _seed = null);
      return;
    }

    if (key != null) {
      final cached = ArtworkColorCache.get(key);
      if (cached != null) {
        if (mounted) setState(() => _seed = cached);
        return;
      }
    }

    final extracted = await extractArtworkSeed(provider, cacheKey: key);
    if (!mounted || _activeKey != key) return;
    if (extracted != null) setState(() => _seed = extracted);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    if (!settings.artworkTinting || _seed == null) return widget.child;

    final m3 = context.m3;
    final brightness = Theme.of(context).brightness;
    final tinted = buildExpressiveTheme(
      settings,
      brightness: brightness,
      overrideSeed: _seed,
    );
    return AnimatedTheme(
      data: tinted,
      duration: m3.motion.resolve(context, m3.motion.defaultEffectsDuration),
      curve: m3.motion.effectsCurve,
      child: widget.child,
    );
  }
}
