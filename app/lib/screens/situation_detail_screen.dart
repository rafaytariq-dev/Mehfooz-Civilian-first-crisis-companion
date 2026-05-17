/// Screen 4 — Situation Detail
///
/// Shows event details: severity, crisis type, explanation,
/// modality breakdown, recommended action, and agent trace link.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';
import '../router.dart';

class SituationDetailScreen extends StatelessWidget {
  final String eventId;

  const SituationDetailScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context) {
    // Mock data — in production, Firestore stream by eventId
    final event = _mockEvent;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: MColors.severityColor(event['severity'] as int),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'SEV ${event['severity']}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(event['area'] as String),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Crisis type header
            _buildCrisisHeader(event),
            const SizedBox(height: 20),

            // "Why we think this is real" card
            _buildExplanationCard(context, event),
            const SizedBox(height: 16),

            // Modality breakdown
            _buildModalityBreakdown(context, event),
            const SizedBox(height: 16),

            // "What you should do" card
            _buildActionCard(context, event),
            const SizedBox(height: 16),

            // Action buttons
            _buildActionButtons(context, event),
            const SizedBox(height: 24),

            // Agent trace toggle
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pushNamed(
                  context,
                  AppRouter.agentTrace,
                  arguments: eventId,
                ),
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('View Agent Reasoning Trace'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCrisisHeader(Map<String, dynamic> event) {
    final icon = _crisisIcon(event['crisis_type'] as String);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: MColors.severityColor(event['severity'] as int)
                .withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, size: 32,
              color: MColors.severityColor(event['severity'] as int)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _crisisLabel(event['crisis_type'] as String),
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${event['city']} · ${event['time_ago']}',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: MColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: MColors.green.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${((event['confidence'] as double) * 100).round()}%',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: MColors.green,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExplanationCard(BuildContext context, Map<String, dynamic> event) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified, color: MColors.green, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Why we think this is real',
                  style: MTypography.titleEn(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              event['explanation_en'] as String,
              style: MTypography.bodyEn(context),
            ),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                event['explanation_ur'] as String,
                style: GoogleFonts.notoNaskhArabic(
                  fontSize: 14,
                  color: MColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModalityBreakdown(
      BuildContext context, Map<String, dynamic> event) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Evidence Sources',
              style: MTypography.titleEn(context),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _modalityChip(Icons.people, '${event['reports_count']} reports',
                    MColors.red),
                const SizedBox(width: 8),
                _modalityChip(Icons.water_drop, '38mm rain', MColors.green),
                const SizedBox(width: 8),
                _modalityChip(
                    Icons.traffic, '+180% traffic', MColors.amber),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _modalityChip(
                    Icons.verified_user, '2 photos verified', MColors.green),
                const SizedBox(width: 8),
                _modalityChip(Icons.tag, '5 social posts', Colors.blue),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _modalityChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, Map<String, dynamic> event) {
    final severity = event['severity'] as int;
    final verb = severity >= 4 ? 'EVACUATE' : 'SHELTER IN PLACE';
    final color = severity >= 4 ? MColors.red : MColors.amber;

    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  severity >= 4
                      ? Icons.directions_run
                      : Icons.home_outlined,
                  color: color,
                ),
                const SizedBox(width: 8),
                Text(
                  'What you should do',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                verb,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              severity >= 4
                  ? 'Move to higher ground immediately. Nearest safe spots have been identified for you.'
                  : 'Stay indoors and monitor updates. Avoid low-lying areas.',
              style: MTypography.bodyEn(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, Map<String, dynamic> event) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () =>
                Navigator.pushNamed(context, AppRouter.safeRoute),
            icon: const Icon(Icons.route),
            label: const Text('Safe Route'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: MColors.green,
            ),
            icon: const Icon(Icons.phone),
            label: const Text('Call 1122'),
          ),
        ),
      ],
    );
  }

  IconData _crisisIcon(String type) {
    switch (type) {
      case 'flood':
      case 'urban_flood':
      case 'flash_flood':
        return Icons.water;
      case 'fire':
        return Icons.local_fire_department;
      case 'heatwave':
        return Icons.thermostat;
      case 'power_outage':
        return Icons.power_off;
      case 'building_collapse':
        return Icons.domain_disabled;
      case 'road_incident':
        return Icons.car_crash;
      default:
        return Icons.warning;
    }
  }

  String _crisisLabel(String type) {
    return type.replaceAll('_', ' ').split(' ').map(
        (w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  Map<String, dynamic> get _mockEvent => {
    'event_id': eventId,
    'crisis_type': 'urban_flood',
    'severity': 4,
    'city': 'Islamabad',
    'area': 'G-10/2',
    'explanation_en':
        '12 reports + 38mm rain in 45 min + traffic +180% at IJP Road = severe urban flood.',
    'explanation_ur':
        '12 رپورٹس + 38mm بارش 45 منٹ میں + IJP روڈ پر ٹریفک +180% = شدید سیلاب',
    'confidence': 0.87,
    'time_ago': '15 min ago',
    'reports_count': 12,
  };
}
