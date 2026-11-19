import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/pop_theme.dart';

/// "You copied a link" M3 Expressive tonal banner that floats above the dock.
class ClipboardOffer extends StatelessWidget {
  const ClipboardOffer({
    super.key,
    required this.platform,
    required this.link,
    required this.onGrab,
    required this.onDismiss,
  });

  final String platform;
  final String link;
  final VoidCallback onGrab;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final m3 = context.m3;
    final still = m3.motion.reduced(context);

    final button = Material(
      color: cs.primaryContainer,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onGrab,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.download_rounded,
                color: cs.onPrimaryContainer,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                'Grab it',
                style: TextStyle(
                  fontFamily: Pop.font,
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      liveRegion: true,
      child: Dismissible(
        key: ValueKey('offer-$link'),
        direction: DismissDirection.down,
        onDismissed: (_) => onDismiss(),
        child: Material(
          color: cs.inverseSurface,
          elevation: 8,
          shadowColor: Colors.black38,
          shape: RoundedRectangleBorder(
            borderRadius: m3.cardRadius,
            side: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$platform link copied',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: Pop.font,
                          color: cs.onInverseSurface,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        link.replaceFirst(RegExp(r'^https?://(www\.)?'), ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: Pop.font,
                          color: cs.onInverseSurface.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  onPressed: onDismiss,
                  color: cs.onInverseSurface.withValues(alpha: 0.7),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
                still
                    ? button
                    : button
                          .animate(onPlay: (c) => c.repeat(reverse: true))
                          .scaleXY(
                            begin: 1,
                            end: 1.05,
                            duration: 750.ms,
                            curve: Curves.easeInOut,
                          ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
