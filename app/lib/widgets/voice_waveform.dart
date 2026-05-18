/// Voice Waveform Visualizer — M8 Urdu Voice Reporting.
///
/// Animated waveform that responds to audio amplitude in real-time.
/// Shows a pulsing bar visualization during recording.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../theme.dart';

/// Animated waveform bars that react to microphone amplitude.
class VoiceWaveform extends StatefulWidget {
  const VoiceWaveform({
    super.key,
    required this.amplitudeStream,
    this.barCount = 40,
    this.barWidth = 3.0,
    this.barSpacing = 2.0,
    this.maxHeight = 80.0,
    this.activeColor,
    this.inactiveColor,
  });

  final Stream<Amplitude>? amplitudeStream;
  final int barCount;
  final double barWidth;
  final double barSpacing;
  final double maxHeight;
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  State<VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<VoiceWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late List<double> _bars;
  StreamSubscription<Amplitude>? _sub;
  double _currentAmplitude = 0.0;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _bars = List.filled(widget.barCount, 0.1);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addListener(_updateBars);
    _animController.repeat();
    _listenToAmplitude();
  }

  @override
  void didUpdateWidget(VoiceWaveform old) {
    super.didUpdateWidget(old);
    if (old.amplitudeStream != widget.amplitudeStream) {
      _sub?.cancel();
      _listenToAmplitude();
    }
  }

  void _listenToAmplitude() {
    _sub = widget.amplitudeStream?.listen((amp) {
      // Amplitude comes as negative dBFS; normalize to 0–1
      // Typical range: -60 (silence) to 0 (max)
      final normalized = ((amp.current + 60) / 60).clamp(0.0, 1.0);
      _currentAmplitude = normalized;
    });
  }

  void _updateBars() {
    if (!mounted) return;

    setState(() {
      // Shift bars left
      for (int i = 0; i < _bars.length - 1; i++) {
        _bars[i] = _bars[i + 1];
      }

      // New bar at the end based on current amplitude + some randomness
      final noise = _random.nextDouble() * 0.15;
      _bars[_bars.length - 1] =
          (_currentAmplitude * 0.85 + noise).clamp(0.05, 1.0);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.activeColor ?? MColors.red;
    final inactiveColor =
        widget.inactiveColor ?? MColors.red.withValues(alpha: 0.2);

    return SizedBox(
      height: widget.maxHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(widget.barCount, (i) {
          final height = max(4.0, _bars[i] * widget.maxHeight);
          final isActive = _bars[i] > 0.1;

          return Padding(
            padding:
                EdgeInsets.symmetric(horizontal: widget.barSpacing / 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: widget.barWidth,
              height: height,
              decoration: BoxDecoration(
                color: isActive ? activeColor : inactiveColor,
                borderRadius: BorderRadius.circular(widget.barWidth / 2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Static waveform placeholder shown when not recording.
class VoiceWaveformPlaceholder extends StatelessWidget {
  const VoiceWaveformPlaceholder({
    super.key,
    this.barCount = 40,
    this.barWidth = 3.0,
    this.barSpacing = 2.0,
    this.maxHeight = 80.0,
  });

  final int barCount;
  final double barWidth;
  final double barSpacing;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: maxHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(barCount, (i) {
          // Gentle sine wave for idle state
          final fraction =
              (sin(i * 0.3) * 0.15 + 0.2).clamp(0.05, 1.0);
          final height = max(4.0, fraction * maxHeight);

          return Padding(
            padding: EdgeInsets.symmetric(horizontal: barSpacing / 2),
            child: Container(
              width: barWidth,
              height: height,
              decoration: BoxDecoration(
                color: MColors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(barWidth / 2),
              ),
            ),
          );
        }),
      ),
    );
  }
}
