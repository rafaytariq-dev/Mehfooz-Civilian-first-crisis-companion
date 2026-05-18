/// Voice Reporting Providers — M8 state management.
///
/// Exposes VoiceReportingService via Riverpod for the UI layer.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/voice_reporting_service.dart';

/// Singleton instance of VoiceReportingService.
final voiceReportingServiceProvider =
    ChangeNotifierProvider<VoiceReportingService>((ref) {
  return VoiceReportingService();
});

/// Current recording state.
final voiceRecordingStateProvider = Provider<VoiceRecordingState>((ref) {
  return ref.watch(voiceReportingServiceProvider).state;
});

/// Current elapsed recording time.
final voiceElapsedProvider = Provider<Duration>((ref) {
  return ref.watch(voiceReportingServiceProvider).elapsed;
});

/// Upload progress (0.0–1.0).
final voiceUploadProgressProvider = Provider<double>((ref) {
  return ref.watch(voiceReportingServiceProvider).uploadProgress;
});

/// Error message if any.
final voiceErrorProvider = Provider<String?>((ref) {
  return ref.watch(voiceReportingServiceProvider).errorMessage;
});
