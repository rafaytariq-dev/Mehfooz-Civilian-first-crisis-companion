/// Voice Recorder Widget — M8 Urdu Voice Reporting.
///
/// The "30-second demo gold moment" widget.
/// - Hold big mic button to record (up to 30s)
/// - Live waveform visualization
/// - Upload progress ring
/// - Processing state with lottie-style animation
/// - Success/error feedback
///
/// Wires into VoiceReportingService via Riverpod.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/voice_providers.dart';
import '../services/voice_reporting_service.dart';
import '../theme.dart';
import 'demo_phrases_card.dart';
import 'voice_waveform.dart';

/// Complete voice recording interface for the Report screen's Voice tab.
class VoiceRecorderWidget extends ConsumerStatefulWidget {
  const VoiceRecorderWidget({
    super.key,
    required this.userId,
    this.crisisType,
    this.onReportSubmitted,
  });

  final String userId;
  final String? crisisType;
  final void Function(VoiceReportResult result)? onReportSubmitted;

  @override
  ConsumerState<VoiceRecorderWidget> createState() =>
      _VoiceRecorderWidgetState();
}

class _VoiceRecorderWidgetState extends ConsumerState<VoiceRecorderWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(voiceReportingServiceProvider);
    final state = service.state;

    // Manage pulse animation based on state
    if (state == VoiceRecordingState.recording && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (state != VoiceRecordingState.recording &&
        _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 8),

          // ─── Status text ───
          _buildStatusHeader(state, service),

          const SizedBox(height: 24),

          // ─── Waveform ───
          _buildWaveformArea(state, service),

          const SizedBox(height: 32),

          // ─── Mic button ───
          _buildMicButton(state, service),

          const SizedBox(height: 20),

          // ─── Timer / Progress ───
          _buildBottomInfo(state, service),

          const SizedBox(height: 16),

          // ─── Helper text ───
          _buildHelperText(state),

          // ─── Error message ───
          if (state == VoiceRecordingState.error) ...[
            const SizedBox(height: 16),
            _buildErrorCard(service.errorMessage ?? 'Unknown error'),
          ],

          // ─── Success card ───
          if (state == VoiceRecordingState.success) ...[
            const SizedBox(height: 16),
            _buildSuccessCard(service),
          ],

          // ─── Demo phrases (always visible) ───
          const SizedBox(height: 24),
          const DemoPhrasesCard(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildStatusHeader(VoiceRecordingState state, VoiceReportingService service) {
    String title;
    String subtitle;
    IconData icon;
    Color color;

    switch (state) {
      case VoiceRecordingState.idle:
        title = 'Voice Report';
        subtitle = 'Hold the button and speak';
        icon = Icons.mic_none;
        color = MColors.textPrimary;
      case VoiceRecordingState.recording:
        title = 'Recording...';
        subtitle = 'Release to stop';
        icon = Icons.mic;
        color = MColors.red;
      case VoiceRecordingState.uploading:
        title = 'Uploading...';
        subtitle = 'Sending to our servers';
        icon = Icons.cloud_upload;
        color = MColors.amber;
      case VoiceRecordingState.processing:
        title = 'Processing...';
        subtitle = 'AI is transcribing your voice';
        icon = Icons.auto_awesome;
        color = MColors.green;
      case VoiceRecordingState.success:
        title = 'Submitted!';
        subtitle = 'Report created successfully';
        icon = Icons.check_circle;
        color = MColors.green;
      case VoiceRecordingState.error:
        title = 'Error';
        subtitle = service.errorMessage ?? 'Something went wrong';
        icon = Icons.error_outline;
        color = MColors.red;
    }

    return Column(
      children: [
        Icon(icon, size: 28, color: color),
        const SizedBox(height: 8),
        Text(
          title,
          style: MTypography.titleEn(context).copyWith(color: color),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: MTypography.captionEn(context),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildWaveformArea(
      VoiceRecordingState state, VoiceReportingService service) {
    if (state == VoiceRecordingState.recording) {
      return VoiceWaveform(
        amplitudeStream: service.amplitudeStream,
        barCount: 40,
        maxHeight: 80,
      );
    }

    if (state == VoiceRecordingState.uploading) {
      return SizedBox(
        height: 80,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  value: service.uploadProgress > 0
                      ? service.uploadProgress
                      : null,
                  strokeWidth: 3,
                  color: MColors.amber,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(service.uploadProgress * 100).toInt()}%',
                style: MTypography.captionEn(context),
              ),
            ],
          ),
        ),
      );
    }

    if (state == VoiceRecordingState.processing) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: MColors.green,
                ),
              ),
              SizedBox(height: 8),
              Text('اردو → انگریزی',
                  style: TextStyle(
                    fontSize: 14,
                    color: MColors.textSecondary,
                  )),
            ],
          ),
        ),
      );
    }

    // Idle or success/error — show placeholder
    return const VoiceWaveformPlaceholder(barCount: 40, maxHeight: 80);
  }

  Widget _buildMicButton(
      VoiceRecordingState state, VoiceReportingService service) {
    final isRecording = state == VoiceRecordingState.recording;
    final canRecord =
        state == VoiceRecordingState.idle || state == VoiceRecordingState.error;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulseScale =
            isRecording ? 1.0 + _pulseController.value * 0.15 : 1.0;
        final pulseOpacity =
            isRecording ? 0.3 - _pulseController.value * 0.2 : 0.0;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulse ring (only visible when recording)
            if (isRecording)
              Transform.scale(
                scale: pulseScale * 1.4,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MColors.red.withValues(alpha: pulseOpacity),
                  ),
                ),
              ),

            // Middle glow
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isRecording ? MColors.red : MColors.red)
                        .withValues(alpha: isRecording ? 0.3 : 0.12),
                    (isRecording ? MColors.red : MColors.red)
                        .withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),

            // Main mic button
            GestureDetector(
              onLongPressStart: canRecord
                  ? (_) {
                      HapticFeedback.mediumImpact();
                      service.startRecording();
                    }
                  : null,
              onLongPressEnd: isRecording
                  ? (_) {
                      HapticFeedback.lightImpact();
                      service.stopAndSubmit(
                        userId: widget.userId,
                        crisisType: widget.crisisType,
                      ).then((result) {
                        if (result != null) {
                          widget.onReportSubmitted?.call(result);
                        }
                      });
                    }
                  : null,
              onLongPressCancel: isRecording
                  ? () => service.cancelRecording()
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: isRecording ? 110 : 100,
                height: isRecording ? 110 : 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: canRecord || isRecording
                      ? MColors.red
                      : MColors.textSecondary.withValues(alpha: 0.3),
                  boxShadow: isRecording
                      ? [
                          BoxShadow(
                            color: MColors.red.withValues(alpha: 0.4),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Icon(
                  isRecording ? Icons.stop_rounded : Icons.mic,
                  size: isRecording ? 52 : 48,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomInfo(
      VoiceRecordingState state, VoiceReportingService service) {
    if (state == VoiceRecordingState.recording) {
      final elapsed = service.elapsed;
      final remaining = VoiceReportingService.maxDuration - elapsed;
      final seconds = elapsed.inSeconds;
      final millis = (elapsed.inMilliseconds % 1000) ~/ 100;

      return Column(
        children: [
          // Timer
          Text(
            '$seconds.${millis}s',
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: MColors.red,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),

          // Progress bar
          SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              value: elapsed.inMilliseconds /
                  VoiceReportingService.maxDuration.inMilliseconds,
              backgroundColor: MColors.red.withValues(alpha: 0.15),
              color: remaining.inSeconds <= 5 ? MColors.amber : MColors.red,
              borderRadius: BorderRadius.circular(4),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 4),

          Text(
            '${remaining.inSeconds}s remaining',
            style: MTypography.captionEn(context).copyWith(
              color: remaining.inSeconds <= 5
                  ? MColors.amber
                  : MColors.textSecondary,
            ),
          ),
        ],
      );
    }

    if (state == VoiceRecordingState.success && service.lastResult != null) {
      return Text(
        'Duration: ${service.lastResult!.recordingDuration.inSeconds}s',
        style: MTypography.captionEn(context),
      );
    }

    return Text(
      'Up to 30 seconds',
      style: GoogleFonts.inter(
        fontSize: 12,
        color: MColors.textSecondary.withValues(alpha: 0.5),
      ),
    );
  }

  Widget _buildHelperText(VoiceRecordingState state) {
    if (state == VoiceRecordingState.idle ||
        state == VoiceRecordingState.error) {
      return Column(
        children: [
          Text(
            'Speak in any language — Urdu, English, or mixed',
            style: MTypography.captionEn(context),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'اردو میں بولیں — آپ کی رپورٹ خودکار طور پر ریکارڈ ہوگی',
            style: GoogleFonts.notoNaskhArabic(
              fontSize: 13,
              color: MColors.textSecondary,
            ),
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildErrorCard(String message) {
    final service = ref.read(voiceReportingServiceProvider);

    return Card(
      color: MColors.red.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: MColors.red, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: MTypography.bodyEn(context)
                    .copyWith(color: MColors.red),
              ),
            ),
            TextButton(
              onPressed: () => service.reset(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessCard(VoiceReportingService service) {
    return Card(
      color: MColors.green.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: MColors.green, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Report submitted!',
                        style: MTypography.bodyEn(context).copyWith(
                          color: MColors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Our AI is verifying and transcribing your voice report now.',
                        style: MTypography.captionEn(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => service.reset(),
                    child: const Text('Record Another'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MColors.green,
                    ),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
