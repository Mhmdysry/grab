import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/pop_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/permissions.dart';
import '../../core/utils/platform.dart';
import '../../core/widgets/expressive_shapes.dart';
import '../../core/widgets/pop_widgets.dart';

/// Three short pages shown on first launch.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  static const seenKey = 'seenWelcome';

  static bool seen(SharedPreferences prefs) => prefs.getBool(seenKey) ?? false;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _Page {
  const _Page(this.icon, this.title, this.body, this.steps);

  final IconData icon;
  final String title;
  final String body;
  final List<String> steps;
}

const _phonePages = [
  _Page(
    Icons.download_rounded,
    'Paste a link.\nGet the file.',
    'Video, audio or subtitles from TikTok, YouTube, Instagram, Pinterest and 1,800+ more sites. Free, no account, no ads.',
    [],
  ),
  _Page(
    Icons.ios_share_rounded,
    'Share straight\nto Grab',
    'The fastest way in, from any app:',
    ['Tap Share on a video', 'Pick Grab', 'Choose a format, done'],
  ),
  _Page(
    Icons.bolt_rounded,
    'One tap from\nanywhere',
    'Copy a link, then tap the Grab tile in Quick Settings. Add it once:',
    [
      'Swipe down twice from the top',
      'Tap the pencil (Edit)',
      'Drag "Grab link" into your tiles',
    ],
  ),
  _Page(
    Icons.notifications_active_rounded,
    'Know when\nit\'s done',
    'Grab keeps downloading when you leave the app. Allow notifications to see progress and a "Saved" alert.',
    [
      'Only about your downloads',
      'No ads, no tracking, ever',
      'Change it any time in Settings',
    ],
  ),
];

const _desktopPages = [
  _Page(
    Icons.download_rounded,
    'Paste a link.\nGet the file.',
    'Video, audio or subtitles from YouTube, TikTok, Instagram, Pinterest and 1,800+ more sites. Free, no account, no ads.',
    [],
  ),
  _Page(
    Icons.content_paste_rounded,
    'Copy, then\ngrab it',
    'The fastest way in, from any browser:',
    [
      'Copy a video link',
      'Switch to Grab',
      'Tap "Grab it" on the card that pops up',
    ],
  ),
];

List<_Page> get _pages => isPhone ? _phonePages : _desktopPages;

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _pager = PageController();
  var _page = 0;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    Haptics.light();
    if (_page == _pages.length - 1) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('askedNotifications', true);
      await requestNotifications();
      widget.onDone();
    } else {
      _pager.nextPage(duration: Pop.medium, curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    final last = _page == _pages.length - 1;
    final still = m3.motion.reduced(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: cs.primaryContainer,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: widget.onDone,
                  child: Text(
                    last && isPhone ? 'Not now' : 'Skip',
                    style: TextStyle(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pager,
                  itemCount: _pages.length,
                  onPageChanged: (i) {
                    Haptics.selection();
                    setState(() => _page = i);
                  },
                  itemBuilder: (context, i) {
                    final p = _pages[i];
                    final hero = ExpressiveShapeContainer(
                      polygon: i.isEven
                          ? ExpressivePolygon.cookie12
                          : ExpressivePolygon.clover4,
                      size: 112,
                      color: cs.primary,
                      child: Icon(p.icon, color: cs.onPrimary, size: 50),
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 48),
                          SizedBox(
                            width: 140,
                            height: 140,
                            child: Center(
                              child: still
                                  ? hero
                                  : hero
                                        .animate(
                                          onPlay: (c) =>
                                              c.repeat(reverse: true),
                                        )
                                        .scaleXY(
                                          begin: 0.96,
                                          end: 1.04,
                                          duration: 2400.ms,
                                          curve: Curves.easeInOut,
                                        ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (still)
                            Text(
                              p.title,
                              style: TextStyle(
                                color: cs.onPrimaryContainer,
                                fontSize: 40,
                                fontWeight: FontWeight.w900,
                                height: 1.02,
                                letterSpacing: -1.0,
                              ),
                            )
                          else
                            Text(
                                  p.title,
                                  style: TextStyle(
                                    color: cs.onPrimaryContainer,
                                    fontSize: 40,
                                    fontWeight: FontWeight.w900,
                                    height: 1.02,
                                    letterSpacing: -1.0,
                                  ),
                                )
                                .animate()
                                .fadeIn(duration: 350.ms)
                                .slideY(begin: 0.15, end: 0),
                          const SizedBox(height: 14),
                          Text(
                            p.body,
                            style: TextStyle(
                              color: cs.onPrimaryContainer.withValues(
                                alpha: 0.85,
                              ),
                              fontSize: 16,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 14),
                          for (final (n, step) in p.steps.indexed)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    alignment: Alignment.center,
                                    decoration: ShapeDecoration(
                                      shape: const CircleBorder(),
                                      color: cs.primary,
                                    ),
                                    child: Text(
                                      '${n + 1}',
                                      style: TextStyle(
                                        color: cs.onPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      step,
                                      style: TextStyle(
                                        color: cs.onPrimaryContainer,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const Spacer(flex: 2),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
                child: Row(
                  children: [
                    for (var i = 0; i < _pages.length; i++)
                      AnimatedContainer(
                        duration: m3.motion.resolve(
                          context,
                          m3.motion.defaultSpatialDuration,
                        ),
                        curve: m3.motion.defaultSpatialCurve,
                        margin: const EdgeInsets.only(right: 6),
                        width: i == _page ? 24 : 8,
                        height: 8,
                        decoration: ShapeDecoration(
                          shape: const StadiumBorder(),
                          color: i == _page
                              ? cs.primary
                              : cs.onPrimaryContainer.withValues(alpha: 0.25),
                        ),
                      ),
                    const Spacer(),
                    PopButton(
                      label: last
                          ? (isPhone ? 'Allow & start' : "Let's go")
                          : 'Next',
                      expand: false,
                      height: 52,
                      onPressed: _next,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
