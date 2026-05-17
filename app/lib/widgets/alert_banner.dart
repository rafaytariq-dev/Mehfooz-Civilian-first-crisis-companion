/// Alert Banner — shown at top of map screen
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

class AlertBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const AlertBanner({super.key, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: count >= 2 ? MColors.red : MColors.amber,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: (count >= 2 ? MColors.red : MColors.amber)
                  .withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              '$count active alert${count > 1 ? 's' : ''} in your city',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }
}
