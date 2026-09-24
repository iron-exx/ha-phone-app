import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/sip_channel.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Video card at the top of a door/video call: the native TextureView (or a
/// placeholder without video), a name chip top left ("Haustür" with the
/// amber door symbol) and [trailingChip] top right (REC).
class CallVideoCard extends StatelessWidget {
  const CallVideoCard({
    super.key,
    required this.label,
    required this.height,
    required this.showVideo,
    this.isDoor = false,
    this.trailingChip,
  });

  final String label;
  final double height;
  final bool showVideo;
  final bool isDoor;
  final Widget? trailingChip;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: const Color(0xFF15110D),
              child: showVideo && defaultTargetPlatform == TargetPlatform.android
                  ? const AndroidView(viewType: remoteVideoViewType)
                  : Semantics(
                      label: showVideo ? 'Live-Bild' : 'Kein Live-Bild',
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(showVideo ? Icons.videocam_outlined : Icons.videocam_off_outlined,
                                size: 40, color: const Color(0xFF7D6D5A)),
                            const SizedBox(height: 8),
                            ExcludeSemantics(
                              child: Text(
                                showVideo ? 'Live-Bild' : 'Kein Live-Bild',
                                style: NwType.meta.copyWith(color: const Color(0xFF7D6D5A), fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            Positioned(
              left: 12,
              top: 12,
              right: trailingChip == null ? 12 : 120,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 28),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B0F14).withOpacity(0.72),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isDoor ? Icons.door_front_door_outlined : Icons.videocam_outlined,
                          size: 14, color: isDoor ? c.door : NwColors.dark.text),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: NwType.chip.copyWith(color: NwColors.dark.text, fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (trailingChip != null) Positioned(right: 12, top: 12, child: trailingChip!),
          ],
        ),
      ),
    );
  }
}
