import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grab/core/motion/expressive_motion.dart';
import 'package:grab/core/theme/pop_theme.dart';
import 'package:grab/core/widgets/expressive_shapes.dart';
import 'package:grab/core/widgets/pop_widgets.dart';
import 'package:grab/data/settings/app_settings.dart';

void main() {
  group('buildExpressiveTheme', () {
    test('builds valid light and dark themes for all palettes & schemes', () {
      for (final palette in M3Palette.values) {
        for (final scheme in M3SchemeStyle.values) {
          final settings = AppSettings(
            accentPalette: palette,
            schemeStyle: scheme,
          );
          final light = buildExpressiveTheme(
            settings,
            brightness: Brightness.light,
          );
          final dark = buildExpressiveTheme(
            settings,
            brightness: Brightness.dark,
          );
          expect(light.useMaterial3, isTrue);
          expect(dark.useMaterial3, isTrue);
          expect(light.extension<M3ExpressiveTokens>(), isNotNull);
          expect(light.extension<PopColors>(), isNotNull);
          expect(dark.extension<M3ExpressiveTokens>(), isNotNull);
          expect(dark.extension<PopColors>(), isNotNull);
        }
      }
    });

    test('AMOLED dark forces pure black surface', () {
      final theme = buildExpressiveTheme(
        const AppSettings(amoledDark: true),
        brightness: Brightness.dark,
      );
      expect(theme.colorScheme.surface, Colors.black);
      expect(theme.scaffoldBackgroundColor, Colors.black);
      expect(theme.extension<PopColors>()!.bg, Colors.black);
    });

    test('dynamicSeed overrides palette when useDynamicColor is true', () {
      const seed = Color(0xFF00FFAA);
      final withDynamic = buildExpressiveTheme(
        const AppSettings(
          accentPalette: M3Palette.amber,
          useDynamicColor: true,
        ),
        brightness: Brightness.light,
        dynamicSeed: seed,
      );
      final withoutDynamic = buildExpressiveTheme(
        const AppSettings(
          accentPalette: M3Palette.amber,
          useDynamicColor: false,
        ),
        brightness: Brightness.light,
        dynamicSeed: seed,
      );
      expect(withDynamic.colorScheme.primary, isNot(withoutDynamic.colorScheme.primary));
    });
  });

  group('ExpressiveMotion & SpringCurve', () {
    test('SpringCurve maps 0.0 -> 0.0 and 1.0 -> 1.0 cleanly', () {
      final spring = SpringCurve(stiffness: 380, dampingRatio: 0.68);
      expect(spring.transform(0.0), 0.0);
      expect(spring.transform(1.0), 1.0);
      expect(spring.transform(0.5), greaterThan(0.0));
    });

    test('M3MotionPreset.off collapses all durations to zero', () {
      final off = ExpressiveMotion.forPreset(M3MotionPreset.off);
      expect(off.isReduced, isTrue);
      expect(off.fastSpatialDuration, Duration.zero);
      expect(off.defaultSpatialDuration, Duration.zero);
      expect(off.slowSpatialDuration, Duration.zero);
      expect(off.fastEffectsDuration, Duration.zero);
      expect(off.defaultEffectsDuration, Duration.zero);
    });
  });

  group('ExpressivePolygonBorder', () {
    test('builds non-empty paths for every polygon and supports lerp', () {
      const rect = Rect.fromLTWH(0, 0, 80, 80);
      for (final p in ExpressivePolygon.values) {
        final border = ExpressivePolygonBorder(polygon: p);
        final path = border.getOuterPath(rect);
        expect(path.getBounds().width, greaterThan(0));
        expect(path.getBounds().height, greaterThan(0));
      }
      const a = ExpressivePolygonBorder(polygon: ExpressivePolygon.circle);
      const b = ExpressivePolygonBorder(polygon: ExpressivePolygon.cookie9);
      final mid = b.lerpFrom(a, 0.5) as ExpressivePolygonBorder;
      expect(mid.polygon, ExpressivePolygon.circle);
      expect(mid.morphTo, ExpressivePolygon.cookie9);
      expect(mid.morphT, 0.5);
      expect(mid.getOuterPath(rect).getBounds().width, greaterThan(0));
    });
  });

  group('Expressive Widget Kit', () {
    for (final navStyle in M3NavStyle.values) {
      testWidgets('PopTabBar renders in $navStyle mode', (tester) async {
        var selected = 0;
        final theme = buildExpressiveTheme(
          AppSettings(
            navStyle: navStyle,
            motionPreset: M3MotionPreset.off,
          ),
          brightness: Brightness.light,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: const SizedBox.expand(),
                bottomNavigationBar: PopTabBar(
                  index: selected,
                  onChanged: (i) => setState(() => selected = i),
                  tabs: const [
                    PopTab(Icons.home_rounded, 'Home'),
                    PopTab(Icons.download_rounded, 'Downloads', badge: 2),
                    PopTab(Icons.video_library_rounded, 'Library'),
                    PopTab(Icons.tune_rounded, 'Settings'),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(find.byType(PopTabBar), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
      });
    }

    testWidgets('Expressive widgets pump without errors', (tester) async {
      final theme = buildExpressiveTheme(
        const AppSettings(motionPreset: M3MotionPreset.off),
        brightness: Brightness.dark,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                PopButton(label: 'Filled', onPressed: () {}),
                const SizedBox(height: 8),
                PopButton(
                  label: 'Tonal',
                  style: PopButtonStyle.tonal,
                  onPressed: () {},
                ),
                const SizedBox(height: 8),
                PopButton(
                  label: 'Busy',
                  busy: true,
                  onPressed: () {},
                ),
                const SizedBox(height: 8),
                const ExpressiveWavyProgressBar(value: 0.65),
                const SizedBox(height: 8),
                const ExpressiveLoadingIndicator(),
                const SizedBox(height: 8),
                const ExpressiveGroup(
                  children: [
                    ExpressiveListRow(title: 'First'),
                    ExpressiveListRow(title: 'Second', subtitle: 'Detail'),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Filled'), findsOneWidget);
      expect(find.text('Tonal'), findsOneWidget);
      expect(find.byType(ExpressiveWavyProgressBar), findsOneWidget);
      expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
      expect(find.byType(ExpressiveGroup), findsOneWidget);
    });

    testWidgets(
      'narrow 360dp viewport at 1.2x text scale renders without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final theme = buildExpressiveTheme(
          const AppSettings(
            motionPreset: M3MotionPreset.off,
            navStyle: M3NavStyle.floatingPill,
            fontScale: 1.2,
          ),
          brightness: Brightness.light,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.2)),
              child: child!,
            ),
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  PopSegmented<M3MotionPreset>(
                    values: M3MotionPreset.values,
                    labels: [for (final v in M3MotionPreset.values) v.label],
                    selected: M3MotionPreset.expressive,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 12),
                  PopOptionTile(
                    label: '2160p 4K Ultra High Definition · MP4',
                    size: '1.42 GB',
                    selected: true,
                    onTap: () {},
                  ),
                  const SizedBox(height: 12),
                  const ExpressiveWavyProgressBar(
                    value: null,
                    wavy: false,
                    active: true,
                  ),
                ],
              ),
              bottomNavigationBar: PopTabBar(
                index: 1,
                onChanged: (_) {},
                tabs: const [
                  PopTab(Icons.home_rounded, 'Home'),
                  PopTab(Icons.download_rounded, 'Downloads', badge: 3),
                  PopTab(Icons.video_library_rounded, 'Library'),
                  PopTab(Icons.tune_rounded, 'Settings'),
                ],
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Downloads'), findsOneWidget);
        expect(find.text('1.42 GB'), findsOneWidget);
      },
    );
  });
}
