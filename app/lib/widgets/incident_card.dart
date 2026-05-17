/// Incident Card — used in bottom sheet and incident list
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

class IncidentCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final VoidCallback onTap;

  const IncidentCard({super.key, required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final severity = event['severity'] as int;
    final crisisType = event['crisis_type'] as String;
    final area = event['area'] as String;
    final timeAgo = event['time_ago'] as String;
    final reportsCount = event['reports_count'] as int;
    final confidence = event['confidence'] as double;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: MColors.severityColor(severity),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'SEV $severity',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _crisisIcon(crisisType),
                    size: 16,
                    color: MColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _crisisLabel(crisisType),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Area
              Text(
                area,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),

              // Meta row
              Row(
                children: [
                  Icon(Icons.access_time, size: 12,
                      color: MColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    timeAgo,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: MColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.people, size: 12, color: MColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    '$reportsCount reports',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: MColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: MColors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${(confidence * 100).round()}%',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: MColors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
      default:
        return Icons.warning;
    }
  }

  String _crisisLabel(String type) {
    return type
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
