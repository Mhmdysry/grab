import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/pop_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/expressive_shapes.dart';
import '../../core/widgets/pop_widgets.dart';
import '../../core/widgets/toasts.dart';
import '../../data/engine/media_info.dart';
import '../library/library_items.dart';

const _channel = MethodChannel('grab/ringtone');

/// Longest ringtone; phones cut longer ones off anyway.
const maxRingtoneSeconds = 40.0;

/// Pick up to 40 seconds of a saved file, save it as a ringtone, optionally set it.
Future<void> showRingtoneSheet(BuildContext context, LibraryItem item) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RingtoneSheet(item: item),
    );

class _RingtoneSheet extends StatefulWidget {
  const _RingtoneSheet({required this.item});

  final LibraryItem item;

  @override
  State<_RingtoneSheet> createState() => _RingtoneSheetState();
}

class _RingtoneSheetState extends State<_RingtoneSheet> {
  double? _duration;
  RangeValues _range = const RangeValues(0, 30);
  var _busy = false;
  String? _saved;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _channel.invokeMethod<double>('duration', {'input': widget.item.path}).then(
      (d) {
        if (!mounted) return;
        final total = d ?? 30;
        setState(() {
          _duration = total;
          _range = RangeValues(0, total.clamp(1, 30).toDouble());
        });
      },
      onError: (Object e) => setState(() => _error = e),
    );
  }

  Future<void> _make() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final uri = await _channel.invokeMethod<String>('make', {
        'input': widget.item.path,
        'start': _range.start,
        'end': _range.end,
        'title': widget.item.title,
      });
      Haptics.success();
      setState(() => _saved = uri);
    } on PlatformException catch (e) {
      Haptics.error();
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _set() async {
    final r = await _channel.invokeMethod<String>('set', {'uri': _saved});
    if (!mounted) return;
    if (r == 'set') {
      Haptics.success();
      popToast('Ringtone set', icon: Icons.ring_volume_rounded);
      Navigator.pop(context);
    } else {
      popToast(
        'Allow Grab to change your ringtone',
        icon: Icons.settings_rounded,
        detail:
            'Turn on "Modify system settings" for Grab, come back, then tap Set again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final d = _duration;
    final len = _range.end - _range.start;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Make a ringtone',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              widget.item.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            if (d == null && _error == null)
              const Center(child: ExpressiveLoadingIndicator())
            else if (d != null) ...[
              Row(
                children: [
                  Text(
                    clockLabel(_range.start),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  PopTag(
                    '${len.round()} s',
                    color: cs.primaryContainer,
                    foreground: cs.onPrimaryContainer,
                  ),
                  const Spacer(),
                  Text(
                    clockLabel(_range.end),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              RangeSlider(
                min: 0,
                max: d,
                divisions: d.round().clamp(1, 7200),
                values: _range,
                onChanged: _saved != null
                    ? null
                    : (v) {
                        var s = v.start, e = v.end;
                        if (e - s > maxRingtoneSeconds) {
                          if (s != _range.start) {
                            e = s + maxRingtoneSeconds;
                          } else {
                            s = e - maxRingtoneSeconds;
                          }
                        }
                        if (e - s < 1) return;
                        if (s.round() != _range.start.round() ||
                            e.round() != _range.end.round()) {
                          Haptics.selection();
                        }
                        setState(() => _range = RangeValues(s, e));
                      },
              ),
              Text(
                'Up to ${maxRingtoneSeconds.round()} seconds. It fades in and out so it never starts with a jolt.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text('$_error', style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 20),
            if (_saved == null)
              PopButton(
                label: 'Save as ringtone',
                icon: Icons.content_cut_rounded,
                busy: _busy,
                onPressed: d == null || _busy ? null : _make,
              )
            else ...[
              Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Saved to Ringtones/Grab. It now shows up in your phone\'s ringtone list.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              PopButton(
                label: 'Set as my ringtone',
                icon: Icons.ring_volume_rounded,
                onPressed: _set,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
