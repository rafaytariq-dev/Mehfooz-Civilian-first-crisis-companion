/// Cooling Spot Tile — M11
///
/// List tile showing a cooling center with type icon, distance,
/// walking time, and navigation/call actions.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../services/heatwave_service.dart';

class CoolingSpotTile extends StatelessWidget {
  final CoolingSpotData spot;
  final VoidCallback? onNavigate;
  final VoidCallback? onCall;
  final int index;

  const CoolingSpotTile({
    super.key,
    required this.spot,
    this.onNavigate,
    this.onCall,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 400 + (index * 100)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: MColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Type icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    spot.typeEmoji,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spot.name,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: MColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      spot.address,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: MColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _infoChip(
                          Icons.directions_walk,
                          '${spot.distanceM}m · ${spot.walkingMinutes} min',
                        ),
                        if (spot.hasMedical) ...[
                          const SizedBox(width: 8),
                          _infoChip(Icons.medical_services, 'Medical'),
                        ],
                        if (spot.open247) ...[
                          const SizedBox(width: 8),
                          _infoChip(Icons.access_time, '24/7'),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Actions
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _actionButton(
                    icon: Icons.navigation,
                    color: MColors.green,
                    onTap: onNavigate,
                    tooltip: 'Navigate',
                  ),
                  if (spot.hasMedical) ...[
                    const SizedBox(height: 8),
                    _actionButton(
                      icon: Icons.phone,
                      color: MColors.red,
                      onTap: onCall,
                      tooltip: 'Call',
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color get _typeColor {
    switch (spot.type) {
      case 'hospital':
        return MColors.red;
      case 'mosque':
        return MColors.green;
      case 'mall':
        return MColors.amber;
      case 'school':
        return const Color(0xFF42A5F5);
      default:
        return MColors.textSecondary;
    }
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: MColors.textSecondary),
        const SizedBox(width: 3),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: MColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}
