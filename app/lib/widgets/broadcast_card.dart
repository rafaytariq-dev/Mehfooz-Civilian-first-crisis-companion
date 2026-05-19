/// M14 — Mosque Broadcast Card
///
/// Renders a single broadcast in the citizen feed with:
///   • mosque name (green "Verified Community Broadcaster" tier)
///   • crisis type emoji + label + severity chip
///   • bilingual body (uses user's language)
///   • mute + flag actions
///   • countdown of remaining time before auto-expiry

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';
import '../providers/broadcast_provider.dart';
import '../services/broadcast_service.dart';

class BroadcastCard extends ConsumerWidget {
  final BroadcastDoc broadcast;
  final MosqueDoc? mosque;
  final String? language; // 'en' | 'ur' | 'roman_ur'

  const BroadcastCard({
    super.key,
    required this.broadcast,
    required this.mosque,
    this.language,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = ref.watch(mutedMosquesProvider);
    final isMuted = mosque != null && muted.contains(mosque!.id);

    final isUrdu = (language ?? 'en') != 'en';
    final body = isUrdu
        ? (broadcast.textUr.isNotEmpty ? broadcast.textUr : broadcast.textEn)
        : (broadcast.textEn.isNotEmpty ? broadcast.textEn : broadcast.textUr);

    final mosqueName = mosque?.name ?? 'Verified Community Broadcaster';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: MColors.green.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: green dot, mosque name, severity chip, menu
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: MColors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🕌  $mosqueName',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'Verified Community Broadcaster',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: MColors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                _severityChip(broadcast.severity),
                IconButton(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onPressed: () => _showActions(context, ref, isMuted),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Crisis type
            Row(
              children: [
                Text(crisisTypeEmoji(broadcast.crisisType)),
                const SizedBox(width: 6),
                Text(
                  crisisTypeLabel(broadcast.crisisType),
                  style: MTypography.captionEn(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(Icons.schedule,
                    size: 12, color: MColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  _remainingText(broadcast.remaining),
                  style: MTypography.captionEn(context),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Body
            Text(
              body,
              textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.4,
              ),
            ),

            if (isMuted) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.volume_off,
                      size: 14, color: MColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Future broadcasts from this mosque are muted',
                    style: MTypography.captionEn(context),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _severityChip(int severity) {
    final color = severity >= 4
        ? MColors.red
        : severity == 3
            ? MColors.amber
            : MColors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'sev $severity',
        style: GoogleFonts.inter(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _remainingText(Duration d) {
    if (d.isNegative) return 'expired';
    if (d.inMinutes < 60) return '${d.inMinutes}m left';
    return '${d.inHours}h ${d.inMinutes % 60}m left';
  }

  void _showActions(BuildContext context, WidgetRef ref, bool isMuted) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mosque != null)
              ListTile(
                leading: Icon(isMuted ? Icons.volume_up : Icons.volume_off),
                title: Text(
                  isMuted
                      ? 'Unmute ${mosque!.name}'
                      : 'Mute ${mosque!.name}',
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await ref
                      .read(broadcastServiceProvider)
                      .setMuted(mosque!.id, !isMuted);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isMuted
                            ? 'Unmuted'
                            : 'Muted. You will not receive future broadcasts from this mosque.'),
                      ),
                    );
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: MColors.red),
              title: const Text('Report broadcast'),
              subtitle: const Text(
                  'Three flags will auto-pull this broadcast from the feed.'),
              onTap: () async {
                Navigator.pop(context);
                final ok = await ref
                    .read(broadcastServiceProvider)
                    .flagBroadcast(broadcast.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok
                          ? 'Flag recorded. Thank you.'
                          : 'Could not flag. Are you signed in?'),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
