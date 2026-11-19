import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grab/core/motion/expressive_motion.dart';
import 'package:grab/core/theme/artwork_color.dart';
import 'package:grab/core/theme/pop_theme.dart';
import 'package:grab/core/widgets/expressive_app_bar.dart';
import 'package:grab/core/widgets/expressive_shapes.dart';
import 'package:grab/core/widgets/pop_widgets.dart';
import 'package:grab/data/engine/media_info.dart';
import 'package:grab/data/settings/app_settings.dart';
import 'package:grab/features/home/fetch_controller.dart';
import 'package:grab/features/home/home_screen.dart';
import 'package:grab/features/share/share_overlay_app.dart';

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
      expect(
        withDynamic.colorScheme.primary,
        isNot(withoutDynamic.colorScheme.primary),
      );
    });

    test('overrideSeed applies even when useDynamicColor is false', () {
      const artwork = Color(0xFFE91E63);
      final base = buildExpressiveTheme(
        const AppSettings(useDynamicColor: false),
        brightness: Brightness.dark,
      );
      final tinted = buildExpressiveTheme(
        const AppSettings(useDynamicColor: false),
        brightness: Brightness.dark,
        overrideSeed: artwork,
      );
      expect(tinted.colorScheme.primary, isNot(base.colorScheme.primary));
    });
  });

  group('ArtworkColor extraction & cache', () {
    test('scoreRgbaForSeed prefers saturated pixels over gray background', () {
      final rgba = <int>[
        // 4 gray pixels
        120, 120, 120, 255,
        120, 120, 120, 255,
        120, 120, 120, 255,
        120, 120, 120, 255,
        // 2 vivid teal pixels
        0, 200, 180, 255,
        0, 200, 180, 255,
      ];
      final seed = scoreRgbaForSeed(rgba);
      expect(seed, isNotNull);
      final hsl = HSLColor.fromColor(seed!);
      expect(hsl.saturation, greaterThan(0.5));
    });

    test('ArtworkColorCache stores and retrieves seed colors', () {
      ArtworkColorCache.clear();
      const c = Color(0xFF448AFF);
      ArtworkColorCache.put('k1', c);
      expect(ArtworkColorCache.get('k1'), c);
      expect(ArtworkColorCache.get('missing'), isNull);
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
                    PopTab(
                      Icons.home_outlined,
                      'Home',
                      activeIcon: Icons.home_rounded,
                    ),
                    PopTab(
                      Icons.download_outlined,
                      'Downloads',
                      activeIcon: Icons.download_rounded,
                      badge: 2,
                    ),
                    PopTab(
                      Icons.video_library_outlined,
                      'Library',
                      activeIcon: Icons.video_library_rounded,
                    ),
                    PopTab(
                      Icons.tune_outlined,
                      'Settings',
                      activeIcon: Icons.tune_rounded,
                    ),
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

    testWidgets(
      'Dual-Island Split Floating Dock orb transitions across idle, downloads, and playing states',
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

        var pasted = false;
        var openedDownloads = false;
        var toggledPlay = false;

        Widget wrap(PopDockOrb orb) => MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.2)),
            child: child!,
          ),
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: PopTabBar(
              index: 1,
              onChanged: (_) {},
              tabs: const [
                PopTab(
                  Icons.home_outlined,
                  'Home',
                  activeIcon: Icons.home_rounded,
                ),
                PopTab(
                  Icons.download_outlined,
                  'Downloads',
                  activeIcon: Icons.download_rounded,
                  badge: 3,
                ),
                PopTab(
                  Icons.video_library_outlined,
                  'Library',
                  activeIcon: Icons.video_library_rounded,
                ),
                PopTab(
                  Icons.tune_outlined,
                  'Settings',
                  activeIcon: Icons.tune_rounded,
                ),
              ],
              orb: orb,
            ),
          ),
        );

        // 1. Idle orb
        await tester.pumpWidget(
          wrap(PopDockOrb(onPasteGrab: () => pasted = true)),
        );
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.content_paste_go_rounded), findsOneWidget);
        await tester.tap(find.byIcon(Icons.content_paste_go_rounded));
        expect(pasted, isTrue);

        // 2. Active downloads orb
        await tester.pumpWidget(
          wrap(
            PopDockOrb(
              activeDownloads: 4,
              downloadProgress: 0.65,
              onOpenDownloads: () => openedDownloads = true,
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('4'), findsOneWidget);
        await tester.tap(find.text('4'));
        expect(openedDownloads, isTrue);

        // 3. Now-playing orb
        await tester.pumpWidget(
          wrap(
            PopDockOrb(
              playingTitle: 'Test Track',
              playingSeed: 'job-1',
              isPlaying: true,
              onTogglePlay: () => toggledPlay = true,
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
        await tester.longPress(find.byKey(const ValueKey('orb-playing')));
        expect(toggledPlay, isTrue);
      },
    );

    testWidgets(
      'ExpressiveWavySlider seeks on drag and handles paused/reduced motion',
      (tester) async {
        var current = 0.25;
        final theme = buildExpressiveTheme(
          const AppSettings(motionPreset: M3MotionPreset.off),
          brightness: Brightness.dark,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  child: StatefulBuilder(
                    builder: (context, setState) => ExpressiveWavySlider(
                      value: current,
                      isPlaying: false,
                      semanticLabel: 'Audio scrubber',
                      onChanged: (v) => setState(() => current = v),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.byType(ExpressiveWavySlider), findsOneWidget);
        await tester.drag(
          find.byType(ExpressiveWavySlider),
          const Offset(80, 0),
        );
        await tester.pump();
        expect(current, greaterThan(0.25));
      },
    );

    testWidgets(
      'ExpressiveSliverHeader and ExpressiveEmptyState pump without errors',
      (tester) async {
        var ctaTapped = false;
        final theme = buildExpressiveTheme(
          const AppSettings(motionPreset: M3MotionPreset.off),
          brightness: Brightness.light,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  const ExpressiveSliverHeader(title: 'Library'),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: ExpressiveEmptyState(
                        icon: Icons.video_library_rounded,
                        title: 'Empty library',
                        subtitle: 'Your saved media appears here.',
                        actionLabel: 'Browse',
                        onAction: () => ctaTapped = true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.text('Library'), findsWidgets);
        expect(find.text('Empty library'), findsOneWidget);
        await tester.tap(find.text('Browse'));
        expect(ctaTapped, isTrue);
      },
    );

    testWidgets(
      'ShareOverlayCard compact & expanded states render without overflow at 360dp / 1.2x',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final theme = buildExpressiveTheme(
          const AppSettings(
            motionPreset: M3MotionPreset.off,
            fontScale: 1.2,
          ),
          brightness: Brightness.light,
        );

        const info = MediaInfo(
          url: 'https://www.youtube.com/watch?v=abc123',
          title: 'Expressive Material 3 Showcase Video With A Long Title',
          site: 'YouTube',
          duration: 145,
          subtitles: [SubtitleTrack(lang: 'en', name: 'English')],
          formats: [
            MediaFormat(
              id: '137',
              height: 1080,
              hasVideo: true,
              hasAudio: false,
              bytes: 24 * 1024 * 1024,
            ),
            MediaFormat(
              id: '136',
              height: 720,
              hasVideo: true,
              hasAudio: false,
              bytes: 14 * 1024 * 1024,
            ),
            MediaFormat(
              id: '140',
              hasVideo: false,
              hasAudio: true,
              bytes: 3 * 1024 * 1024,
            ),
          ],
        );

        var expanded = false;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.2)),
                child: child!,
              ),
              home: Scaffold(
                backgroundColor: Colors.transparent,
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: StatefulBuilder(
                    builder: (context, setState) => ShareOverlayCard(
                      phase: ShareCardPhase.ready,
                      fetchState: const FetchState(
                        info: AsyncData(info),
                        mode: DownloadMode.video,
                      ),
                      settings: const AppSettings(),
                      url: info.url,
                      expanded: expanded,
                      onToggleExpand: () =>
                          setState(() => expanded = !expanded),
                      onDownload: () {},
                      onOpenInGrab: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('1080p · 27 MB'), findsOneWidget);

        // Expand into full Trim & Subtitles options
        await tester.tap(find.text('More options · Trim & Subtitles'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Save only a part'), findsOneWidget);
        expect(find.text('English'), findsOneWidget);
      },
    );

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
      expect(find.byType(ExpressiveLoadingIndicator), findsNWidgets(2));
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
                  PopTab(
                    Icons.home_outlined,
                    'Home',
                    activeIcon: Icons.home_rounded,
                  ),
                  PopTab(
                    Icons.download_outlined,
                    'Downloads',
                    activeIcon: Icons.download_rounded,
                    badge: 3,
                  ),
                  PopTab(
                    Icons.video_library_outlined,
                    'Library',
                    activeIcon: Icons.video_library_rounded,
                  ),
                  PopTab(
                    Icons.tune_outlined,
                    'Settings',
                    activeIcon: Icons.tune_rounded,
                  ),
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

    testWidgets(
      'ExpressiveFloatingNavBar keeps equal-width stacked labels stationary and morphs orb polygons',
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

        var selected = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.2)),
              child: child!,
            ),
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: const SizedBox.expand(),
                bottomNavigationBar: ExpressiveFloatingNavBar(
                  index: selected,
                  onChanged: (i) => setState(() => selected = i),
                  tabs: const [
                    PopTab(
                      Icons.home_outlined,
                      'Home',
                      activeIcon: Icons.home_rounded,
                    ),
                    PopTab(
                      Icons.download_outlined,
                      'Downloads',
                      activeIcon: Icons.download_rounded,
                      badge: 2,
                    ),
                    PopTab(
                      Icons.video_library_outlined,
                      'Library',
                      activeIcon: Icons.video_library_rounded,
                    ),
                    PopTab(
                      Icons.tune_outlined,
                      'Settings',
                      activeIcon: Icons.tune_rounded,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        // All 4 stacked labels remain simultaneously visible.
        expect(find.text('Home'), findsOneWidget);
        expect(find.text('Downloads'), findsOneWidget);
        expect(find.text('Library'), findsOneWidget);
        expect(find.text('Settings'), findsOneWidget);

        final homeXBefore = tester.getCenter(find.text('Home')).dx;
        final libraryXBefore = tester.getCenter(find.text('Library')).dx;
        final settingsXBefore = tester.getCenter(find.text('Settings')).dx;

        await tester.tap(find.text('Downloads'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(selected, 1);

        // Equal-width stacked tabs must never shift sibling X coordinates.
        expect(tester.getCenter(find.text('Home')).dx, closeTo(homeXBefore, 0.5));
        expect(
          tester.getCenter(find.text('Library')).dx,
          closeTo(libraryXBefore, 0.5),
        );
        expect(
          tester.getCenter(find.text('Settings')).dx,
          closeTo(settingsXBefore, 0.5),
        );
      },
    );

    testWidgets(
      'ExpressiveTabStack transitions cleanly between tabs and preserves child state',
      (tester) async {
        final theme = buildExpressiveTheme(
          const AppSettings(motionPreset: M3MotionPreset.expressive),
          brightness: Brightness.light,
        );
        var tab = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: ExpressiveTabStack(
                  index: tab,
                  children: const [
                    Center(child: _StatefulCounter()),
                    Center(child: Text('Tab One')),
                    Center(child: Text('Tab Two')),
                  ],
                ),
                floatingActionButton: FloatingActionButton(
                  onPressed: () => setState(() => tab = (tab + 1) % 3),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Tab Zero: 0'));
        await tester.pump();
        expect(find.text('Tab Zero: 1'), findsOneWidget);

        await tester.tap(find.byType(FloatingActionButton));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tab, 1);
        expect(find.text('Tab One'), findsOneWidget);
        expect(find.text('Tab Zero: 1'), findsNothing);

        // Switch through Tab Two and back to Tab Zero; state must remain intact.
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        expect(find.text('Tab Two'), findsOneWidget);

        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        expect(find.text('Tab Zero: 1'), findsOneWidget);
      },
    );

    testWidgets(
      'InstantGrabBar and ShareOverlayCard bubble prompt render without overflow at 360dp / 1.2x',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final theme = buildExpressiveTheme(
          const AppSettings(
            motionPreset: M3MotionPreset.off,
            fontScale: 1.2,
          ),
          brightness: Brightness.dark,
        );

        var instant = false;
        var modeCycled = false;
        var qualityPicked = false;
        var bubbleEnabled = false;
        var bubbleDismissed = false;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
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
                    StatefulBuilder(
                      builder: (context, setState) => InstantGrabBar(
                        settings: AppSettings(instantGrab: instant),
                        onToggleInstant: () =>
                            setState(() => instant = !instant),
                        onCycleMode: () => modeCycled = true,
                        onPickQuality: () => qualityPicked = true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ShareOverlayCard(
                      phase: ShareCardPhase.ready,
                      fetchState: const FetchState(
                        info: AsyncData(
                          MediaInfo(
                            url: 'https://example.com/v',
                            title: 'Sample Video',
                            site: 'YouTube',
                          ),
                        ),
                      ),
                      settings: const AppSettings(),
                      showBubblePrompt: true,
                      onEnableBubble: () => bubbleEnabled = true,
                      onDismissBubblePrompt: () => bubbleDismissed = true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        await tester.tap(
          find.descendant(
            of: find.byType(InstantGrabBar),
            matching: find.text('Instant Grab'),
          ),
        );
        await tester.pump();
        expect(instant, isTrue);

        await tester.tap(
          find.descendant(
            of: find.byType(InstantGrabBar),
            matching: find.text('Video'),
          ),
        );
        expect(modeCycled, isTrue);

        await tester.tap(
          find.descendant(
            of: find.byType(InstantGrabBar),
            matching: find.text('Best'),
          ),
        );
        expect(qualityPicked, isTrue);

        await tester.tap(
          find.descendant(
            of: find.byType(ShareOverlayCard),
            matching: find.text('Turn on'),
          ),
        );
        expect(bubbleEnabled, isTrue);

        await tester.tap(
          find.descendant(
            of: find.byType(ShareOverlayCard),
            matching: find.byTooltip('Dismiss'),
          ),
        );
        expect(bubbleDismissed, isTrue);
      },
    );
  });
}

class _StatefulCounter extends StatefulWidget {
  const _StatefulCounter();

  @override
  State<_StatefulCounter> createState() => _StatefulCounterState();
}

class _StatefulCounterState extends State<_StatefulCounter> {
  var _count = 0;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => _count++),
    child: Text('Tab Zero: $_count'),
  );
}
