import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../theme.dart';
import '../services/offline_cache.dart';

class FirstAidScreen extends StatefulWidget {
  const FirstAidScreen({super.key});

  @override
  State<FirstAidScreen> createState() => _FirstAidScreenState();
}

class _FirstAidScreenState extends State<FirstAidScreen> {
  late Box<CachedFirstAid> _firstAidBox;

  @override
  void initState() {
    super.initState();
    _firstAidBox = Hive.box<CachedFirstAid>(OfflineCache.boxFirstAid);
  }

  @override
  Widget build(BuildContext context) {
    final items = _firstAidBox.values.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('First Aid (Offline Kit)'),
      ),
      body: items.isEmpty
          ? const Center(child: Text('No First Aid data available.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _buildFirstAidCard(item);
              },
            ),
    );
  }

  Widget _buildFirstAidCard(CachedFirstAid item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _getIconForTopic(item.topic),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.topic,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: MColors.red,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.volume_up, color: MColors.red),
                  onPressed: () {
                    // M13 Voice Playback stub
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Playing pre-recorded Urdu instructions...')),
                    );
                  },
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              item.contentEn,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              item.contentUr,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.5,
                color: MColors.textSecondary,
              ),
              textDirection: TextDirection.rtl,
            ),
          ],
        ),
      ),
    );
  }

  Widget _getIconForTopic(String topic) {
    IconData iconData = Icons.health_and_safety;
    if (topic.toLowerCase().contains('drowning')) iconData = Icons.water;
    if (topic.toLowerCase().contains('heat')) iconData = Icons.thermostat;
    if (topic.toLowerCase().contains('electric')) iconData = Icons.electric_bolt;
    if (topic.toLowerCase().contains('bleed')) iconData = Icons.bloodtype;

    return CircleAvatar(
      backgroundColor: MColors.red.withValues(alpha: 0.1),
      child: Icon(iconData, color: MColors.red),
    );
  }
}
