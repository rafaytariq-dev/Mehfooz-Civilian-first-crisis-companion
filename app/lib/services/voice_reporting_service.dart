/// Voice Reporting Service — M8 Urdu Voice Reporting.
///
/// Handles:
/// - Audio recording (AAC-LC, 16 kHz, up to 30 sec)
/// - Upload to Firebase Storage (`voice/{uid}/{uuid}.m4a`)
/// - Write report shell to Firestore (ingestion picks up via onCreate)
/// - State management for the recording lifecycle
///
/// Architecture: Option B (Two-stage) per CIRO spec —
///   Record → Upload → Cloud Function STT (ur-PK) → Gemini normalize → update doc
///
/// Option A (Gemini Live streaming) can be layered on top once stable.

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Recording state machine.
enum VoiceRecordingState {
  idle,
  recording,
  uploading,
  processing, // STT + Gemini (happens server-side, we poll)
  success,
  error,
}

/// Result of a completed voice report submission.
class VoiceReportResult {
  final String reportId;
  final String voiceUrl;
  final Duration recordingDuration;

  const VoiceReportResult({
    required this.reportId,
    required this.voiceUrl,
    required this.recordingDuration,
  });
}

/// Service that manages the voice recording → upload → report lifecycle.
class VoiceReportingService extends ChangeNotifier {
  VoiceReportingService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final AudioRecorder _recorder = AudioRecorder();
  final _uuid = const Uuid();

  // ─── State ───

  VoiceRecordingState _state = VoiceRecordingState.idle;
  VoiceRecordingState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Duration _elapsed = Duration.zero;
  Duration get elapsed => _elapsed;

  double _uploadProgress = 0.0;
  double get uploadProgress => _uploadProgress;

  VoiceReportResult? _lastResult;
  VoiceReportResult? get lastResult => _lastResult;

  // Amplitude stream for waveform visualization
  Stream<Amplitude>? _amplitudeStream;
  Stream<Amplitude>? get amplitudeStream => _amplitudeStream;

  Timer? _elapsedTimer;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;

  static const maxDuration = Duration(seconds: 30);

  // ─── Public API ───

  /// Start recording audio (AAC-LC, 16 kHz mono).
  /// Call this on mic button press-down.
  Future<void> startRecording() async {
    if (_state == VoiceRecordingState.recording) return;

    try {
      // Check microphone permission
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        _setError('Microphone permission denied');
        return;
      }

      // Generate local file path
      final dir = await getTemporaryDirectory();
      final fileId = _uuid.v4();
      _currentRecordingPath = '${dir.path}/mehfooz_voice_$fileId.m4a';

      // Start recording — AAC-LC at 16 kHz (optimal for STT)
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 64000,
        ),
        path: _currentRecordingPath!,
      );

      _state = VoiceRecordingState.recording;
      _elapsed = Duration.zero;
      _errorMessage = null;
      _recordingStartTime = DateTime.now();
      notifyListeners();

      // Start elapsed timer (updates every 100ms for smooth UI)
      _elapsedTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) {
          if (_recordingStartTime != null) {
            _elapsed = DateTime.now().difference(_recordingStartTime!);
            notifyListeners();

            // Auto-stop at 30 seconds
            if (_elapsed >= maxDuration) {
              stopRecording();
            }
          }
        },
      );

      // Set up amplitude stream for waveform
      _amplitudeStream = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100));
    } catch (e) {
      _setError('Failed to start recording: $e');
    }
  }

  /// Stop recording and return the local file path.
  /// Call this on mic button release.
  Future<String?> stopRecording() async {
    if (_state != VoiceRecordingState.recording) return null;

    _elapsedTimer?.cancel();
    _elapsedTimer = null;

    try {
      final path = await _recorder.stop();
      _amplitudeStream = null;
      return path ?? _currentRecordingPath;
    } catch (e) {
      _setError('Failed to stop recording: $e');
      return null;
    }
  }

  /// Cancel an in-progress recording without submitting.
  Future<void> cancelRecording() async {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;

    if (_state == VoiceRecordingState.recording) {
      try {
        await _recorder.stop();
      } catch (_) {}
    }

    // Clean up temp file
    if (_currentRecordingPath != null) {
      try {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }

    _state = VoiceRecordingState.idle;
    _elapsed = Duration.zero;
    _amplitudeStream = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Stop recording, upload to Storage, write report doc.
  /// This is the main "submit" flow.
  Future<VoiceReportResult?> stopAndSubmit({
    required String userId,
    String? crisisType,
  }) async {
    // 1. Stop recording
    final localPath = await stopRecording();
    if (localPath == null) {
      _setError('No recording to submit');
      return null;
    }

    final file = File(localPath);
    if (!await file.exists()) {
      _setError('Recording file not found');
      return null;
    }

    final recordingDuration = _elapsed;

    // Skip very short recordings (< 1 second)
    if (recordingDuration.inMilliseconds < 1000) {
      _setError('Recording too short — hold for at least 1 second');
      await _cleanupFile(localPath);
      return null;
    }

    try {
      // 2. Upload to Firebase Storage
      _state = VoiceRecordingState.uploading;
      _uploadProgress = 0.0;
      notifyListeners();

      final voiceUrl = await _uploadToStorage(file, userId);

      // 3. Get current location
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 5),
          ),
        );
      } catch (e) {
        debugPrint('Location unavailable for voice report: $e');
        // Continue without location — not a blocker
      }

      // 4. Write report shell to Firestore
      _state = VoiceRecordingState.processing;
      notifyListeners();

      final reportId = await _writeReportDoc(
        userId: userId,
        voiceUrl: voiceUrl,
        position: position,
        crisisType: crisisType,
        durationSeconds: recordingDuration.inSeconds,
      );

      // 5. Clean up local file
      await _cleanupFile(localPath);

      // 6. Return result
      _lastResult = VoiceReportResult(
        reportId: reportId,
        voiceUrl: voiceUrl,
        recordingDuration: recordingDuration,
      );
      _state = VoiceRecordingState.success;
      notifyListeners();

      return _lastResult;
    } catch (e) {
      _setError('Failed to submit: $e');
      await _cleanupFile(localPath);
      return null;
    }
  }

  /// Reset state back to idle (call after showing success/error UI).
  void reset() {
    _state = VoiceRecordingState.idle;
    _elapsed = Duration.zero;
    _uploadProgress = 0.0;
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();
  }

  // ─── Private helpers ───

  /// Upload audio file to Firebase Storage.
  /// Path: `voice/{uid}/{uuid}.m4a`
  Future<String> _uploadToStorage(File file, String userId) async {
    final fileId = _uuid.v4();
    final ref = _storage.ref('voice/$userId/$fileId.m4a');

    final uploadTask = ref.putFile(
      file,
      SettableMetadata(
        contentType: 'audio/mp4',
        customMetadata: {
          'source': 'mehfooz_voice_report',
          'user_id': userId,
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
        },
      ),
    );

    // Track upload progress
    uploadTask.snapshotEvents.listen((snapshot) {
      _uploadProgress =
          snapshot.bytesTransferred / snapshot.totalBytes;
      notifyListeners();
    });

    await uploadTask;
    return await ref.getDownloadURL();
  }

  /// Write the initial report document to Firestore.
  /// The Cloud Function `onVoiceReportCreated` will detect voice_url,
  /// run STT + Gemini normalization, and update the doc.
  Future<String> _writeReportDoc({
    required String userId,
    required String voiceUrl,
    Position? position,
    String? crisisType,
    int? durationSeconds,
  }) async {
    final doc = await _firestore.collection('reports').add({
      'user_id': userId,
      'voice_url': voiceUrl,
      'voice_duration_seconds': durationSeconds,
      'text_raw': null, // filled by STT Cloud Function
      'text_normalized': null, // filled by Gemini normalization
      'language_detected': null, // filled by STT
      'photo_urls': <String>[],
      'location': position != null
          ? GeoPoint(position.latitude, position.longitude)
          : null,
      'geo_accuracy_m': position?.accuracy ?? 0,
      'crisis_type_user': crisisType,
      'crisis_type_inferred': null, // filled by ingestion agent
      'severity_user': null, // filled by Gemini normalization
      'vision_verified': false,
      'vision_confidence': 0,
      'linked_event_id': null,
      'created_at': FieldValue.serverTimestamp(),
      '_source': 'voice', // marks this as a voice report for the trigger
    });

    return doc.id;
  }

  Future<void> _cleanupFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  void _setError(String message) {
    _state = VoiceRecordingState.error;
    _errorMessage = message;
    _elapsedTimer?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}
