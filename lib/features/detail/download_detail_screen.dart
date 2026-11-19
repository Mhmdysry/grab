import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/utils/platform.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_playback.dart';
import '../../core/theme/pop_theme.dart';
import '../../core/widgets/expressive_shapes.dart';
import '../../core/widgets/pop_widgets.dart';
import '../../core/widgets/toasts.dart';
import '../../data/db/app_database.dart';
import '../../data/engine/media_info.dart';
import '../../data/settings/app_settings.dart';
import '../library/library_items.dart';
import '../library/player_screen.dart';
import 'extraction_controller.dart';
import 'ringtone_sheet.dart';
import '../../core/utils/haptics.dart';

void openDownload(BuildContext context, String jobId) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => DownloadDetailScreen(jobId: jobId)));
}

/// One download: a preview, its files (play, share, delete), extract audio from a saved video,
/// and download again from the original link.
class DownloadDetailScreen extends ConsumerWidget {
  const DownloadDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = (ref.watch(jobsProvider).value ?? const <DownloadJob>[])
        .where((j) => j.id == jobId)
        .firstOrNull;
    if (job == null) {
      return const Scaffold(
        body: Center(child: Text('This download was removed.')),
      );
    }
    final files = job.paths.split('\n').where((p) => p.isNotEmpty).toList();
    final onPhone = files.where((p) => File(p).existsSync()).toList();
    final media = onPhone
        .where((p) => kindOf(p) != LibraryKind.subtitles)
        .toList();
    final preview =
        media.where((p) => kindOf(p) == LibraryKind.video).firstOrNull ??
        media.firstOrNull;
    final videos = onPhone
        .where((p) => kindOf(p) == LibraryKind.video)
        .toList();
    final extraction = ref.watch(extractionProvider)[job.id];
    final mode = DownloadMode.values
        .where((m) => m.name == job.mode)
        .firstOrNull;
    final m3 = context.m3;
    final cs = context.cs;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            tooltip: 'Remove from history',
            onPressed: () async {
              await ref.read(downloadRepositoryProvider).remove(job.id);
              if (context.mounted) Navigator.pop(context);
              popToast(
                'Removed from history',
                icon: Icons.history_rounded,
                detail: 'Files on the phone were kept.',
              );
            },
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
        children: [
          if (preview != null)
            _Preview(key: ValueKey(preview), path: preview, job: job)
          else
            SizedBox(
              height: 200,
              child: PopThumb(
                seed: job.id,
                url: job.thumbnail,
                size: double.infinity,
                radius: m3.cardRadius,
              ),
            ),
          const SizedBox(height: 16),
          Text(
            job.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              job.site,
              if (mode != null) _modeLabel(mode),
              if (job.finishedAt != null) _date(job.finishedAt!),
            ].whereType<String>().join(' · '),
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: PopButton(
                  label: 'Download again',
                  icon: Icons.refresh_rounded,
                  height: 52,
                  onPressed: () {
                    ref.read(pendingLinkProvider.notifier).set(job.url);
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                ),
              ),
              const SizedBox(width: 10),
              PopIconButton(
                icon: Icons.ios_share_rounded,
                tooltip: 'Share all files',
                onPressed: onPhone.isEmpty
                    ? null
                    : () => SharePlus.instance.share(
                        ShareParams(
                          files: [for (final f in onPhone) XFile(f)],
                          subject: job.title,
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              PopIconButton(
                icon: Icons.link_rounded,
                tooltip: 'Copy link',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: job.url));
                  popToast('Link copied', icon: Icons.link_rounded);
                },
              ),
            ],
          ),
          if (videos.isNotEmpty) ...[
            const SizedBox(height: 24),
            const PopSection('Extract audio'),
            _ExtractCard(job: job, videos: videos, extraction: extraction),
          ],
          const SizedBox(height: 24),
          PopSection('Files · ${files.length}'),
          if (files.isEmpty)
            Text(
              'No files recorded for this download.',
              style: TextStyle(color: cs.onSurfaceVariant),
            )
          else
            ExpressiveGroup(
              children: [
                for (final f in files) _FileRow(path: f, job: job),
              ],
            ),
        ],
      ),
    );
  }

  static String _modeLabel(DownloadMode m) => switch (m) {
    DownloadMode.video => 'Video',
    DownloadMode.videoAndAudio => 'Video + audio file',
    DownloadMode.audioOnly => 'Audio',
    DownloadMode.subtitlesOnly => 'Subtitles',
  };

  static String _date(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

/// Inline preview of the main file. Tap to play or pause; the corner button opens full screen.
class _Preview extends StatefulWidget {
  const _Preview({super.key, required this.path, required this.job});

  final String path;
  final DownloadJob job;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  late final VideoPlayerController _c = VideoPlayerController.file(
    File(widget.path),
    // A real Android view: the texture path shows no picture on some phones.
    viewType: videoViewType,
    // Play even while a call or other app holds the audio; otherwise Android
    // silently holds playback back and the preview just sits there.
    videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
  );
  var _failed = false;

  bool get _audio => kindOf(widget.path) == LibraryKind.audio;

  @override
  void initState() {
    super.initState();
    _c.addListener(() => mounted ? setState(() {}) : null);
    // Opening a video file is heavy; wait until the page has finished growing
    // open, so the morph runs at full frame rate.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final a = ModalRoute.of(context)?.animation;
      if (a == null || a.isCompleted) return _start();
      void done(AnimationStatus s) {
        if (s != AnimationStatus.completed) return;
        a.removeStatusListener(done);
        _start();
      }

      a.addStatusListener(done);
    });
  }

  void _start() {
    if (!mounted) return;
    _c.initialize().catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  LibraryItem get _item => LibraryItem(
    jobId: widget.job.id,
    path: widget.path,
    title: widget.job.title,
    kind: kindOf(widget.path),
    thumbnail: widget.job.thumbnail,
    site: widget.job.site,
  );

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    final cs = context.cs;
    final m3 = context.m3;
    final ready = v.isInitialized && !_failed;
    final ratio = ready && !_audio && v.aspectRatio > 0
        ? v.aspectRatio.clamp(0.5, 2.0)
        : 16 / 9;
    return ClipRRect(
      borderRadius: m3.cardRadius,
      child: AspectRatio(
        aspectRatio: ratio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.black,
              child: ready && !_audio && v.position > Duration.zero
                  ? FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: v.size.width,
                        height: v.size.height,
                        child: VideoPlayer(_c),
                      ),
                    )
                  : PopThumb(
                      seed: widget.job.id,
                      url: widget.job.thumbnail,
                      audio: _audio,
                      size: double.infinity,
                      radius: BorderRadius.zero,
                    ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: ready
                    ? () {
                        Haptics.selection();
                        v.isPlaying ? _c.pause() : _c.play();
                      }
                    : null,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: v.isPlaying ? 0 : 1,
                    duration: m3.motion.resolve(
                      context,
                      m3.motion.fastEffectsDuration,
                    ),
                    child: ExpressiveShapeContainer(
                      polygon: ExpressivePolygon.cookie9,
                      size: 72,
                      color: cs.primaryContainer,
                      child: Icon(
                        _failed
                            ? Icons.error_outline_rounded
                            : Icons.play_arrow_rounded,
                        size: 38,
                        color: cs.onPrimaryContainer,
                        semanticLabel: v.isPlaying ? 'Pause' : 'Play',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (ready)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  minHeight: 4,
                  value: v.duration.inMilliseconds == 0
                      ? 0
                      : v.position.inMilliseconds / v.duration.inMilliseconds,
                  color: cs.primary,
                  backgroundColor: Colors.white24,
                ),
              ),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton(
                tooltip: 'Full screen',
                onPressed: () {
                  _c.pause();
                  openPlayer(context, _item);
                },
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.fullscreen_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pick a format and extract the audio from a saved video. Shows progress while it runs.
class _ExtractCard extends ConsumerStatefulWidget {
  const _ExtractCard({
    required this.job,
    required this.videos,
    required this.extraction,
  });

  final DownloadJob job;
  final List<String> videos;
  final Extraction? extraction;

  @override
  ConsumerState<_ExtractCard> createState() => _ExtractCardState();
}

class _ExtractCardState extends ConsumerState<_ExtractCard> {
  late String _format = ref.read(settingsProvider).audioFormat;

  @override
  Widget build(BuildContext context) {
    final x = widget.extraction;
    final c = ref.read(extractionProvider.notifier);
    final cs = context.cs;
    final m3 = context.m3;
    return Container(
      padding: EdgeInsets.all(m3.cardPad),
      decoration: BoxDecoration(
        color: x == null ? cs.surfaceContainerLow : cs.primaryContainer,
        borderRadius: m3.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Save the sound of this video as its own file. No need to fetch the link again.',
            style: TextStyle(
              color: x == null
                  ? cs.onSurfaceVariant
                  : cs.onPrimaryContainer.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 12),
          if (x == null) ...[
            PopSegmented<String>(
              values: AppSettings.audioFormats,
              labels: [
                for (final f in AppSettings.audioFormats) f.toUpperCase(),
              ],
              selected: _format,
              onChanged: (f) => setState(() => _format = f),
            ),
            const SizedBox(height: 12),
            PopButton(
              label: 'Extract audio · ${_format.toUpperCase()}',
              icon: Icons.music_note_rounded,
              height: 52,
              onPressed: () => c.extractAudio(
                jobId: widget.job.id,
                input: widget.videos.first,
                title: widget.job.title,
                format: _format,
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: PopProgressBar(
                    value: x.progress / 100,
                    wavy: true,
                    active: true,
                    color: cs.primary,
                    track: cs.surfaceContainerLowest,
                  ),
                ),
                const SizedBox(width: 8),
                PopIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Cancel extraction',
                  background: cs.surfaceContainerLowest,
                  foreground: cs.onSurface,
                  onPressed: () => c.cancel(widget.job.id),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Extracting audio… ${x.progress.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 12,
                color: cs.onPrimaryContainer.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FileRow extends ConsumerWidget {
  const _FileRow({required this.path, required this.job});

  final String path;
  final DownloadJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.cs;
    final m3 = context.m3;
    final exists = File(path).existsSync();
    final kind = kindOf(path);
    final item = LibraryItem(
      jobId: job.id,
      path: path,
      title: job.title,
      kind: kind,
      thumbnail: job.thumbnail,
      site: job.site,
    );
    final icon = switch (kind) {
      LibraryKind.video => Icons.movie_rounded,
      LibraryKind.audio => Icons.music_note_rounded,
      LibraryKind.subtitles => Icons.subtitles_rounded,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: exists ? cs.primaryContainer : cs.surfaceContainerHigh,
              borderRadius: m3.thumbRadius,
            ),
            child: Icon(
              icon,
              color: exists ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  exists
                      ? '${item.ext} · ${fileSizeLabel(path) ?? ''}'
                      : 'Deleted from the phone',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (exists && kind != LibraryKind.subtitles)
            IconButton(
              tooltip: 'Play',
              onPressed: () => openPlayer(context, item),
              icon: const Icon(Icons.play_arrow_rounded),
            ),
          if (exists && kind != LibraryKind.subtitles && isPhone)
            IconButton(
              tooltip: 'Make ringtone',
              onPressed: () => showRingtoneSheet(context, item),
              icon: const Icon(Icons.ring_volume_rounded),
            ),
          if (exists)
            IconButton(
              tooltip: 'Share',
              onPressed: () => SharePlus.instance.share(
                ShareParams(files: [XFile(path)], subject: job.title),
              ),
              icon: const Icon(Icons.share_rounded),
            ),
          if (exists)
            IconButton(
              tooltip: 'Delete file',
              onPressed: () => _delete(context, ref, item),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    LibraryItem item,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this file?'),
        content: Text(
          "${item.fileName}\n\nIt will be removed from your phone. This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(
                color: context.cs.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AudioPlayback.forget(item.path);
      await File(item.path).delete();
      ref.invalidate(jobsProvider);
      popToast('Deleted', icon: Icons.delete_rounded, detail: item.fileName);
    } catch (e) {
      popToast("Couldn't delete", error: true, detail: '$e');
    }
  }
}
