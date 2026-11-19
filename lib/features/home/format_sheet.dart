import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/pop_theme.dart';
import '../../core/utils/permissions.dart';
import '../../core/widgets/pop_widgets.dart';
import '../../core/widgets/toasts.dart';
import '../../data/engine/media_info.dart';
import 'clip_preview.dart';
import 'fetch_controller.dart';
import '../../core/utils/haptics.dart';

/// Opens the Choose format sheet for the fetched link.
/// Returns true when a download was queued.
Future<bool> showFormatSheet(BuildContext context) async {
  final queued = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const FormatSheet(),
  );
  return queued ?? false;
}

class FormatSheet extends ConsumerWidget {
  const FormatSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(fetchControllerProvider);
    final c = ref.read(fetchControllerProvider.notifier);
    final info = s.info.value;
    if (info == null) return const SizedBox(height: 200);

    final modes = [
      DownloadMode.videoAndAudio,
      DownloadMode.video,
      DownloadMode.audioOnly,
      if (info.subtitles.isNotEmpty) DownloadMode.subtitlesOnly,
    ];
    const labels = {
      DownloadMode.videoAndAudio: 'Video + audio',
      DownloadMode.video: 'Video',
      DownloadMode.audioOnly: 'Audio',
      DownloadMode.subtitlesOnly: 'Subs',
    };
    final still = Pop.reduceMotion(context);
    final settings = ref.watch(settingsProvider);
    String fmt(String label) => s.mode == DownloadMode.audioOnly
        ? '$label · ${settings.audioFormat.toUpperCase()}'
        : '$label · ${settings.container.toUpperCase()}';

    Future<void> download() async {
      // Explain and ask for notification (and, on old Android, storage) access first.
      final ok = await ensureDownloadPermissions(
        context,
        ref.read(sharedPrefsProvider),
      );
      if (!ok) {
        popToast('Grab needs storage access to save files', error: true);
        return;
      }
      final id = await c.download();
      if (id == null || !context.mounted) return;
      Haptics.medium();
      popToast(
        'Added to downloads',
        icon: Icons.download_rounded,
        detail: info.title,
      );
      Navigator.of(context).pop(true);
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        children: [
          const Text(
            'Choose format',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          ClipPreview(
            info: info,
            trim: s.mode == DownloadMode.subtitlesOnly ? null : s.trim,
            onTrim: c.setTrim,
          ),
          if (s.mode != DownloadMode.subtitlesOnly &&
              info.duration != null &&
              info.duration! >= 2)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.content_cut_rounded),
              title: const Text(
                'Save only a part',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                s.trim == null
                    ? 'Pick the part on the video above'
                    : 'Keeping ${clockLabel(s.trim!.start)} to ${clockLabel(s.trim!.end)}',
              ),
              value: s.trim != null,
              onChanged: (on) {
                Haptics.selection();
                c.setTrimOn(on);
              },
            ),
          const SizedBox(height: 14),
          Text(
            info.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              info.site,
              info.uploader,
              if (info.isPlaylist) '${info.entryCount} items',
            ].whereType<String>().join(' · '),
            style: TextStyle(color: context.pop.muted),
          ),
          const SizedBox(height: 18),
          PopSegmented<DownloadMode>(
            values: modes,
            labels: [for (final m in modes) labels[m]!],
            selected: s.mode,
            onChanged: c.setMode,
          ),
          const SizedBox(height: 18),
          if (s.mode != DownloadMode.subtitlesOnly) ...[
            PopSection(s.mode == DownloadMode.audioOnly ? 'Audio' : 'Quality'),
            for (final (i, o) in s.options.indexed) ...[
              if (still)
                PopOptionTile(
                  label: fmt(o.label),
                  size: formatBytes(o.bytes),
                  selected: i == s.optionIndex.clamp(0, s.options.length - 1),
                  onTap: () => c.setOption(i),
                )
              else
                PopOptionTile(
                      label: fmt(o.label),
                      size: formatBytes(o.bytes),
                      selected:
                          i == s.optionIndex.clamp(0, s.options.length - 1),
                      onTap: () => c.setOption(i),
                    )
                    .animate()
                    .fadeIn(
                      duration: context.m3.motion.defaultEffectsDuration,
                      delay: (35 * i).ms,
                    )
                    .slideY(begin: 0.12, end: 0, curve: Curves.easeOutCubic),
            ],
          ],

          if (s.mode != DownloadMode.audioOnly) ..._subtitles(info, s, c),
          const SizedBox(height: 24),
          PopButton(
            label: switch (s.mode) {
              DownloadMode.subtitlesOnly =>
                s.subLangs.isEmpty ? 'Pick a language' : 'Download subtitles',
              _ => [
                s.trim == null ? 'Download' : 'Download clip',
                ?formatBytes(
                  s.selected?.bytes == null
                      ? null
                      : (s.selected!.bytes! * s.keptFraction).round(),
                ),
              ].join(' · '),
            },
            icon: Icons.download_rounded,
            onPressed: s.canDownload ? download : null,
          ),
        ],
      ),
    );
  }

  List<Widget> _subtitles(MediaInfo info, FetchState s, FetchController c) {
    if (info.subtitles.isEmpty) {
      return [
        const SizedBox(height: 8),
        Builder(
          builder: (context) => Text(
            'No subtitles for this link.',
            style: TextStyle(color: context.pop.muted),
          ),
        ),
      ];
    }
    return [
      const SizedBox(height: 12),
      const PopSection('Subtitles'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in info.subtitles)
            FilterChip(
              label: Text(t.auto ? '${t.name} · auto' : t.name),
              selected: s.subLangs.contains(t.lang),
              onSelected: (_) {
                Haptics.selection();
                c.toggleLang(t.lang);
              },
            ),
        ],
      ),
      if (s.mode != DownloadMode.subtitlesOnly && s.subLangs.isNotEmpty)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Put subtitles inside the video',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text('Off: saved next to it as .srt files'),
          value: s.embedSubs,
          onChanged: c.setEmbed,
        ),
    ];
  }
}
