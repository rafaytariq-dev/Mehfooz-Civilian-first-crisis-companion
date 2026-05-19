/// Heat Index Gauge — M11
///
/// Custom-painted circular gauge showing heat index value with
/// color-coded segments and animated needle.

import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';

class HeatIndexGauge extends StatefulWidget {
  final double heatIndexC;
  final double size;

  const HeatIndexGauge({
    super.key,
    required this.heatIndexC,
    this.size = 200,
  });

  @override
  State<HeatIndexGauge> createState() => _HeatIndexGaugeState();
}

class _HeatIndexGaugeState extends State<HeatIndexGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = Tween<double>(begin: 0, end: widget.heatIndexC).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(HeatIndexGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heatIndexC != widget.heatIndexC) {
      _animation = Tween<double>(
        begin: _animation.value,
        end: widget.heatIndexC,
      ).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _GaugePainter(
              value: _animation.value,
              maxValue: 60,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_animation.value.toStringAsFixed(1)}°',
                    style: TextStyle(
                      fontSize: widget.size * 0.2,
                      fontWeight: FontWeight.w800,
                      color: _colorForValue(_animation.value),
                    ),
                  ),
                  Text(
                    'Heat Index',
                    style: TextStyle(
                      fontSize: widget.size * 0.07,
                      color: MColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color:
                          _colorForValue(_animation.value).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _labelForValue(_animation.value),
                      style: TextStyle(
                        fontSize: widget.size * 0.06,
                        fontWeight: FontWeight.w700,
                        color: _colorForValue(_animation.value),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Color _colorForValue(double v) {
    if (v < 27) return const Color(0xFF4CAF50); // Safe — green
    if (v < 32) return const Color(0xFFFFEB3B); // Caution — yellow
    if (v < 41) return const Color(0xFFFF9800); // Extreme caution — orange
    if (v < 54) return const Color(0xFFF44336); // Danger — red
    return const Color(0xFF9C27B0); // Extreme danger — purple
  }

  static String _labelForValue(double v) {
    if (v < 27) return 'Safe';
    if (v < 32) return 'Caution';
    if (v < 41) return 'Extreme Caution';
    if (v < 54) return 'Danger';
    return 'Extreme Danger';
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final double maxValue;

  _GaugePainter({required this.value, required this.maxValue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 16;
    const startAngle = 135 * pi / 180; // Start at bottom-left
    const sweepTotal = 270 * pi / 180; // 270° arc

    // Background track
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..color = Colors.grey.withValues(alpha: 0.15)
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal,
      false,
      bgPaint,
    );

    // Color segments
    final segments = [
      (0.0, 27.0, const Color(0xFF4CAF50)),  // Safe
      (27.0, 32.0, const Color(0xFFFFEB3B)),  // Caution
      (32.0, 41.0, const Color(0xFFFF9800)),  // Extreme Caution
      (41.0, 54.0, const Color(0xFFF44336)),  // Danger
      (54.0, 60.0, const Color(0xFF9C27B0)),  // Extreme Danger
    ];

    for (final (segStart, segEnd, color) in segments) {
      if (value <= segStart) break;

      final effectiveEnd = value.clamp(segStart, segEnd);
      final startFraction = segStart / maxValue;
      final endFraction = effectiveEnd / maxValue;

      final segPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..color = color
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + startFraction * sweepTotal,
        (endFraction - startFraction) * sweepTotal,
        false,
        segPaint,
      );
    }

    // Needle dot
    final needleAngle =
        startAngle + (value.clamp(0, maxValue) / maxValue) * sweepTotal;
    final needlePos = Offset(
      center.dx + radius * cos(needleAngle),
      center.dy + radius * sin(needleAngle),
    );

    // Outer glow
    canvas.drawCircle(
      needlePos,
      10,
      Paint()
        ..color = Colors.white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Inner dot
    canvas.drawCircle(
      needlePos,
      6,
      Paint()..color = _colorForValue(value),
    );
    canvas.drawCircle(
      needlePos,
      3,
      Paint()..color = Colors.white,
    );
  }

  Color _colorForValue(double v) {
    if (v < 27) return const Color(0xFF4CAF50);
    if (v < 32) return const Color(0xFFFFEB3B);
    if (v < 41) return const Color(0xFFFF9800);
    if (v < 54) return const Color(0xFFF44336);
    return const Color(0xFF9C27B0);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value;
}
