/// M14 — Mosque Broadcast Feed (citizen view)
///
/// All active broadcasts from verified mosques, filtered to non-muted
/// senders. Tapping a broadcast opens its details. Long-press shows
/// mute/flag actions (also available via the trailing menu).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme.dart';
import '../providers/broadcast_provider.dart';
import '../services/broadcast_service.dart';
import '../widgets/broadcast_card.dart';

class BroadcastFeedScreen extends ConsumerWidget {
  const BroadcastFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(activeBroadcastsProvider);
    final muted = ref.watch(mutedMosquesProvider);
    final userDoc = ref.watch(currentUserDocProvider).valueOrNull;
    final language = (userDoc?['language'] ?? 'en') as String;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mosque Broadcasts'),
      ),
      body: feed.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) {
          final visible = list.where((b) => !muted.contains(b.mosqueId)).toList();
          if (visible.isEmpty) {
            return _emptyView(context);
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final b = visible[i];
              return _broadcastTile(ref, b, language);
            },
          );
        },
      ),
    );
  }

  Widget _broadcastTile(WidgetRef ref, BroadcastDoc b, String language) {
    final mosqueAsync = ref.watch(mosqueByIdProvider(b.mosqueId));
    final mosque = mosqueAsync.valueOrNull;
    return BroadcastCard(broadcast: b, mosque: mosque, language: language);
  }

  Widget _emptyView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mosque_outlined,
              size: 64, color: MColors.textSecondary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            'No active community broadcasts.',
            style: MTypography.bodyEn(context),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'When a verified mosque in your area posts a safety update, '
              'it will appear here and as a push notification.',
              textAlign: TextAlign.center,
              style: MTypography.captionEn(context),
            ),
          ),
        ],
      ),
    );
  }
}
