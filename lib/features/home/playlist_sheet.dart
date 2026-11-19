import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/pop_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/permissions.dart';
import '../../core/widgets/expressive_shapes.dart';
import '../../core/widgets/pop_widgets.dart';
import '../../core/widgets/toasts.dart';
import '../../data/engine/media_info.dart';
import '../../data/repositories/download_repository.dart';

/// Opens the picker for a playlist or profile. Returns true when downloads were queued.
Future<bool> showPlaylistSheet(BuildContext context, MediaInfo info) async {
  final queued = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => PlaylistSheet(info: info),
  );
  return queued ?? false;
}

/// Pick which items of a playlist or profile to save, and how.
class PlaylistSheet extends ConsumerStatefulWidget {
  const PlaylistSheet({super.key, required this.info});

  final MediaInfo info;

  @override
  ConsumerState<PlaylistSheet> createState() => _PlaylistSheetState();
}

class _PlaylistSheetState extends ConsumerState<PlaylistSheet> {
  late final Set<int> _picked = {
    for (var i = 0; i < widget.info.entries.length; i++) i,
  };
  late DownloadMode _mode = switch (ref.read(settingsProvider).defaultMode) {
    DownloadMode.subtitlesOnly => DownloadMode.video,
    final m => m,
  };
  int? _height;
  var _busy = false;

  static const _modes = [
    DownloadMode.video,
    DownloadMode.videoAndAudio,
    DownloadMode.audioOnly,
  ];
  static const _heights = <int?>[null, 1080, 720, 480];

  List<PlaylistEntry> get _entries => widget.info.entries;
  bool get _all => _picked.length == _entries.length;

  void _toggleAll() {
    Haptics.selection();
    setState(() {
      if (_all) {
        _picked.clear();
      } else {
        _picked.addAll([for (var i = 0; i < _entries.length; i++) i]);
      }
    });
  }

  Future<void> _download() async {
    final ok = await ensureDownloadPermissions(
      context,
      ref.read(sharedPrefsProvider),
    );
    if (!ok) {
      popToast('Grab needs storage access to save files', error: true);
      return;
    }
    setState(() => _busy = true);
    final settings = ref.read(settingsProvider);
    final repo = ref.read(downloadRepositoryProvider);
    final picked = _picked.toList()..sort();
    for (final i in picked) {
      final e = _entries[i];
      await repo.enqueue(
        DownloadRequest(
          info: MediaInfo(
            url: e.url,
            title: e.title,
            id: e.id,
            thumbnail: e.thumbnail,
            duration: e.duration,
            site: widget.info.site,
          ),
          mode: _mode,
          maxHeight: _mode == DownloadMode.audioOnly ? null : _height,
          container: settings.container,
          audioFormat: settings.audioFormat,
        ),
      );
    }
    if (!mounted) return;
    Haptics.medium();
    popToast(
      picked.length == 1
          ? 'Added 1 download'
          : 'Added ${picked.length} downloads',
      icon: Icons.download_rounded,
      detail: widget.info.title,
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final n = _picked.length;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: CustomScrollView(
              controller: scroll,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  sliver: SliverList.list(
                    children: [
                      Text(
                        info.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          info.site,
                          info.uploader,
                          _entries.length >= 300
                              ? 'Newest 300 items'
                              : '${_entries.length} items',
                        ].whereType<String>().join(' · '),
                        style: TextStyle(color: context.pop.muted),
                      ),
                      const SizedBox(height: 16),
                      PopSegmented<DownloadMode>(
                        values: _modes,
                        labels: const ['Video', 'Video + audio', 'Audio'],
                        selected: _mode,
                        onChanged: (m) => setState(() => _mode = m),
                      ),
                      if (_mode != DownloadMode.audioOnly) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final h in _heights)
                              ChoiceChip(
                                label: Text(h == null ? 'Best' : '${h}p'),
                                selected: _height == h,
                                onSelected: (_) {
                                  Haptics.selection();
                                  setState(() => _height = h);
                                },
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: PopSection(
                              '$n of ${_entries.length} selected',
                            ),
                          ),
                          TextButton(
                            onPressed: _toggleAll,
                            child: Text(
                              _all ? 'Select none' : 'Select all',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: _entries.length,
                    itemBuilder: (context, i) => _EntryRow(
                      entry: _entries[i],
                      index: i,
                      picked: _picked.contains(i),
                      onTap: () {
                        Haptics.selection();
                        setState(
                          () => _picked.contains(i)
                              ? _picked.remove(i)
                              : _picked.add(i),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: PopButton(
                label: n == 0
                    ? 'Pick something'
                    : n == 1
                    ? 'Download 1 item'
                    : 'Download $n items',
                icon: Icons.download_rounded,
                busy: _busy,
                onPressed: n == 0 || _busy ? null : _download,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.index,
    required this.picked,
    required this.onTap,
  });

  final PlaylistEntry entry;
  final int index;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    return Semantics(
      checked: picked,
      button: true,
      child: InkWell(
        borderRadius: m3.cardRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Stack(
                children: [
                  PopThumb(
                    seed: entry.id ?? entry.url,
                    url: entry.thumbnail,
                    size: 72,
                  ),
                  if (entry.duration != null)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: DecoratedBox(
                        decoration: const ShapeDecoration(
                          shape: StadiumBorder(),
                          color: Color(0xCC141414),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            clockLabel(entry.duration!),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: picked ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: m3.motion.resolve(
                  context,
                  m3.motion.defaultSpatialDuration,
                ),
                curve: m3.motion.defaultSpatialCurve,
                width: 28,
                height: 28,
                decoration: ShapeDecoration(
                  color: picked ? cs.primary : Colors.transparent,
                  shape: ExpressivePolygonBorder(
                    polygon: picked
                        ? ExpressivePolygon.cookie9
                        : ExpressivePolygon.circle,
                    side: BorderSide(
                      color: picked ? cs.primary : cs.onSurfaceVariant,
                      width: 2,
                    ),
                  ),
                ),
                child: picked
                    ? Icon(Icons.check_rounded, size: 17, color: cs.onPrimary)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
