/// Heatwave Card — M11
///
/// Compact card for the home screen showing current heat index + status.
/// Animated temperature icon. Tappable → navigates to full heatwave screen.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

class HeatwaveCard extends StatefulWidget {
  final double heatIndexC;
  final double tempC;
  final String city;
  final VoidCallback? onTap;

  const HeatwaveCard({
    super.key,
    required this.heatIndexC,
    required this.tempC,
    required this.city,
    this.onTap,
  });

  @override
  State<HeatwaveCard> createState() => _HeatwaveCardState();
}

class _HeatwaveCardState extends State<HeatwaveCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    // Only pulse for danger levels
    if (widget.heatIndexC >= 41) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _dangerColor;
    final level = _dangerLabel;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final glowIntensity =
              widget.heatIndexC >= 41 ? (_pulseController.value * 0.3) : 0.0;

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: 0.08 + glowIntensity),
                  color.withValues(alpha: 0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withValues(alpha: 0.3 + glowIntensity),
                width: 1.5,
              ),
              boxShadow: [
                if (widget.heatIndexC >= 41)
                  BoxShadow(
                    color: color.withValues(alpha: 0.15 + glowIntensity * 0.3),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
              ],
            ),
            child: Row(
              children: [
                // Temperature icon with pulse
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      '🌡️',
                      style: TextStyle(
                        fontSize: 28 + (glowIntensity * 4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Heat Index: ${widget.heatIndexC.toStringAsFixed(0)}°C',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: MColors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              level,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.city} · ${widget.tempC.toStringAsFixed(0)}°C actual · Tap for advice',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: MColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  color: color.withValues(alpha: 0.6),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color get _dangerColor {
    if (widget.heatIndexC < 27) return const Color(0xFF4CAF50);
    if (widget.heatIndexC < 32) return const Color(0xFFFFEB3B);
    if (widget.heatIndexC < 41) return const Color(0xFFFF9800);
    if (widget.heatIndexC < 54) return MColors.red;
    return const Color(0xFF9C27B0);
  }

  String get _dangerLabel {
    if (widget.heatIndexC < 27) return 'Safe';
    if (widget.heatIndexC < 32) return 'Caution';
    if (widget.heatIndexC < 41) return 'Extreme Caution';
    if (widget.heatIndexC < 54) return 'Danger';
    return 'Extreme Danger';
  }
}
