import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/utils/platform.dart';

import '../../core/theme/pop_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/expressive_shapes.dart';
import '../../core/widgets/pop_widgets.dart';
import '../../data/engine/engine_channel.dart';
import '../../data/engine/media_info.dart';

/// The fetched video, playable in place, with a CapCut-style trim bar under it
/// while "Save only a part" is on. Dragging a handle shows that exact frame.
class ClipPreview extends StatefulWidget {
  const ClipPreview({
    super.key,
    required this.info,
    required this.trim,
    required this.onTrim,
  });

  final MediaInfo info;

  /// The kept part in seconds, or null when saving the whole thing.
  final ({double start, double end})? trim;
  final void Function(double start, double end) onTrim;

  @override
  State<ClipPreview> createState() => _ClipPreviewState();
}

class _ClipPreviewState extends State<ClipPreview> {
  VideoPlayerController? _c;
  var _loading = false;
  var _failed = false;

  MediaFormat? get _stream => widget.info.previewFormat;
  double get _duration => widget.info.duration ?? 0;

  @override
  void didUpdateWidget(ClipPreview old) {
    super.didUpdateWidget(old);
    final t = widget.trim;
    // Turning trim on: jump to the start of the kept part.
    if (old.trim == null && t != null) _seek(t.start);
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  /// Short videos can fall back to a small cached copy when the site won't
  /// stream to us directly.
  bool get _canCopy => _duration > 0 && _duration <= 600;

  /// TikTok refuses direct playback outside its app, so go straight to a copy.
  bool get _copyFirst =>
      _canCopy && (widget.info.site ?? '').toLowerCase().contains('tiktok');

  bool get _playable => (_stream != null || _canCopy) && !_failed;

  static VideoPlayerOptions get _options =>
      // Play even while a call or other app holds the audio; otherwise Android
      // silently holds playback back and the preview just sits there.
      VideoPlayerOptions(mixWithOthers: true);

  Future<VideoPlayerController?> _open(VideoPlayerController c) async {
    try {
      await c.initialize();
      return c;
    } catch (_) {
      await c.dispose();
      return null;
    }
  }

  Future<VideoPlayerController?> _ensure() async {
    if (_c != null) return _c;
    if (_loading || !_playable) return null;
    setState(() => _loading = true);
    VideoPlayerController? c;
    final s = _stream;
    if (s != null && !_copyFirst) {
      c = await _open(
        VideoPlayerController.networkUrl(
          Uri.parse(s.url!),
          httpHeaders: s.headers,
          // A real Android view: the texture path shows no picture on some phones.
          viewType: videoViewType,
          videoPlayerOptions: _options,
        ),
      );
    }
    if (c == null && _canCopy) {
      try {
        final path = await Engine.instance.previewFile(widget.info.url);
        if (path != null) {
          c = await _open(
            VideoPlayerController.file(
              File(path),
              viewType: videoViewType,
              videoPlayerOptions: _options,
            ),
          );
        }
      } catch (_) {}
    }
    if (!mounted) {
      await c?.dispose();
      return null;
    }
    if (c == null) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return null;
    }
    c.addListener(_onTick);
    setState(() {
      _c = c;
      _loading = false;
    });
    return c;
  }

  void _onTick() {
    final c = _c;
    if (c == null || !mounted) return;
    final t = widget.trim;
    // Play only the kept part, on a loop.
    if (t != null && c.value.isPlaying) {
      final pos = c.value.position.inMilliseconds / 1000;
      if (pos >= t.end || pos < t.start - 0.5) {
        c.seekTo(_ms(t.start));
      }
    }
    setState(() {});
  }

  Future<void> _togglePlay() async {
    Haptics.selection();
    final c = await _ensure();
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      final t = widget.trim;
      final pos = c.value.position.inMilliseconds / 1000;
      if (t != null && (pos < t.start || pos >= t.end - 0.2)) {
        await c.seekTo(_ms(t.start));
      }
      await c.play();
    }
  }

  Future<void> _seek(double seconds) async {
    final c = await _ensure();
    if (c == null) return;
    if (c.value.isPlaying) await c.pause();
    await c.seekTo(_ms(seconds));
  }

  static Duration _ms(double s) => Duration(milliseconds: (s * 1000).round());

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final cs = context.cs;
    final m3 = context.m3;
    final playing = c?.value.isPlaying ?? false;
    final t = widget.trim;
    final pos = c == null
        ? (t?.start ?? 0)
        : c.value.position.inMilliseconds / 1000;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: m3.cardRadius,
          child: Container(
            color: Colors.black,
            height: 210,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: c != null && c.value.isInitialized
                      ? FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(
                            width: c.value.size.width,
                            height: c.value.size.height,
                            child: VideoPlayer(c),
                          ),
                        )
                      : PopThumb(
                          seed: widget.info.url,
                          url: widget.info.thumbnail,
                          size: double.infinity,
                          radius: BorderRadius.zero,
                        ),
                ),
                if (_playable)
                  Material(
                    color: playing ? Colors.black45 : cs.primaryContainer,
                    shape: ExpressivePolygonBorder(
                      polygon: playing
                          ? ExpressivePolygon.squircle
                          : ExpressivePolygon.cookie9,
                    ),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _togglePlay,
                      child: SizedBox(
                        width: 62,
                        height: 62,
                        child: _loading
                            ? Center(
                                child: ExpressiveLoadingIndicator(
                                  size: 26,
                                  color: cs.onPrimaryContainer,
                                  contained: false,
                                ),
                              )
                            : Icon(
                                playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 34,
                                color: playing
                                    ? Colors.white
                                    : cs.onPrimaryContainer,
                                semanticLabel: playing
                                    ? 'Pause preview'
                                    : 'Play preview',
                              ),
                      ),
                    ),
                  ),
                if (_duration > 0)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: _Pill(
                      c == null
                          ? clockLabel(_duration)
                          : '${clockLabel(pos)} / ${clockLabel(_duration)}',
                    ),
                  ),
                if (_failed)
                  const Positioned(
                    left: 12,
                    bottom: 12,
                    child: _Pill("Preview isn't available for this link"),
                  ),
              ],
            ),
          ),
        ),
        if (m3.motion.reduced(context))
          (t == null || _duration <= 0
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: TrimBar(
                    duration: _duration,
                    start: t.start,
                    end: t.end,
                    position: c == null ? null : pos,
                    thumbnail: widget.info.thumbnail,
                    onChanged: (s, e, moved) {
                      widget.onTrim(s, e);
                      _seek(moved);
                    },
                    onSeek: _seek,
                  ),
                ))
        else
          AnimatedSize(
            duration: m3.motion.defaultSpatialDuration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: t == null || _duration <= 0
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: TrimBar(
                      duration: _duration,
                      start: t.start,
                      end: t.end,
                      position: c == null ? null : pos,
                      thumbnail: widget.info.thumbnail,
                      onChanged: (s, e, moved) {
                        widget.onTrim(s, e);
                        _seek(moved);
                      },
                      onSeek: _seek,
                    ),
                  ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const ShapeDecoration(
      shape: StadiumBorder(),
      color: Color(0xCC141414),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    ),
  );
}

/// Filmstrip with a themed selection frame: drag either handle to set the
/// start or end, tap anywhere to look at that moment.
class TrimBar extends StatefulWidget {
  const TrimBar({
    super.key,
    required this.duration,
    required this.start,
    required this.end,
    required this.onChanged,
    required this.onSeek,
    this.position,
    this.thumbnail,
  });

  final double duration;
  final double start;
  final double end;

  /// Playhead in seconds, when the video is loaded.
  final double? position;
  final String? thumbnail;

  /// New start and end, plus the time of the handle that moved (to show it).
  final void Function(double start, double end, double moved) onChanged;
  final ValueChanged<double> onSeek;

  @override
  State<TrimBar> createState() => _TrimBarState();
}

enum _Handle { start, end }

class _TrimBarState extends State<TrimBar> {
  static const _handleW = 16.0;
  static const _height = 60.0;
  _Handle? _drag;
  Timer? _seekThrottle;

  @override
  void dispose() {
    _seekThrottle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final d = widget.duration;
    final len = widget.end - widget.start;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              clockLabel(widget.start),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            PopTag('${clockLabel(len)} kept'),
            const Spacer(),
            Text(
              clockLabel(widget.end),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, box) {
            final track = box.maxWidth - _handleW * 2;
            double x(double s) => _handleW + track * (s / d);
            double timeAt(double dx) =>
                ((dx - _handleW) / track * d).clamp(0.0, d);
            final sx = x(widget.start), ex = x(widget.end);

            void move(double dx) {
              final t = timeAt(dx);
              var s = widget.start, e = widget.end;
              if (_drag == _Handle.start) {
                s = t.clamp(0.0, e - 1);
              } else {
                e = t.clamp(s + 1, d);
              }
              if (s.round() != widget.start.round() ||
                  e.round() != widget.end.round()) {
                Haptics.selection();
              }
              final moved = _drag == _Handle.start ? s : e;
              if (_seekThrottle?.isActive ?? false) {
                widget.onChanged(s, e, moved);
                return;
              }
              _seekThrottle = Timer(const Duration(milliseconds: 120), () {});
              widget.onChanged(s, e, moved);
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (u) => widget.onSeek(timeAt(u.localPosition.dx)),
              onHorizontalDragStart: (g) {
                final dx = g.localPosition.dx;
                _drag = (dx - sx).abs() <= (dx - ex).abs()
                    ? _Handle.start
                    : _Handle.end;
                Haptics.light();
              },
              onHorizontalDragUpdate: (g) => move(g.localPosition.dx),
              onHorizontalDragEnd: (_) => setState(() => _drag = null),
              child: SizedBox(
                height: _height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      left: _handleW,
                      right: _handleW,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Row(
                          children: [
                            for (var i = 0; i < 8; i++)
                              Expanded(
                                child: widget.thumbnail == null
                                    ? ColoredBox(
                                        color: i.isEven
                                            ? const Color(0xFF2A2A2A)
                                            : const Color(0xFF333333),
                                      )
                                    : Image.network(
                                        widget.thumbnail!,
                                        fit: BoxFit.cover,
                                        height: _height,
                                        errorBuilder: (_, _, _) =>
                                            const ColoredBox(
                                              color: Color(0xFF2A2A2A),
                                            ),
                                      ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: _handleW,
                      width: (sx - _handleW).clamp(0, track),
                      top: 0,
                      bottom: 0,
                      child: const ColoredBox(color: Color(0xB3000000)),
                    ),
                    Positioned(
                      left: ex,
                      right: _handleW,
                      top: 0,
                      bottom: 0,
                      child: const ColoredBox(color: Color(0xB3000000)),
                    ),
                    Positioned(
                      left: sx - _handleW,
                      width: ex - sx + _handleW * 2,
                      top: -3,
                      bottom: -3,
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _FramePainter(
                            handle: _handleW,
                            frameColor: cs.primary,
                            gripColor: cs.onPrimary,
                          ),
                        ),
                      ),
                    ),
                    if (widget.position != null &&
                        widget.position! >= widget.start &&
                        widget.position! <= widget.end)
                      Positioned(
                        left: x(widget.position!) - 1.5,
                        top: -6,
                        bottom: -6,
                        child: IgnorePointer(
                          child: Container(
                            width: 3,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: const [
                                BoxShadow(color: Colors.black54, blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Drag the handles to choose the part. Tap the strip to look at a moment.',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
      ],
    );
  }
}

/// CapCut-style frame: thick themed handles on the sides, thin top and bottom.
class _FramePainter extends CustomPainter {
  _FramePainter({
    required this.handle,
    required this.frameColor,
    required this.gripColor,
  });

  final double handle;
  final Color frameColor;
  final Color gripColor;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Paint()..color = frameColor;
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    final inner = RRect.fromRectAndRadius(
      Rect.fromLTRB(handle, 3, size.width - handle, size.height - 3),
      const Radius.circular(4),
    );
    canvas.drawDRRect(r, inner, frame);
    final grip = Paint()
      ..color = gripColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (final cx in [handle / 2, size.width - handle / 2]) {
      canvas.drawLine(
        Offset(cx, size.height / 2 - 9),
        Offset(cx, size.height / 2 + 9),
        grip,
      );
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.handle != handle ||
      old.frameColor != frameColor ||
      old.gripColor != gripColor;
}
