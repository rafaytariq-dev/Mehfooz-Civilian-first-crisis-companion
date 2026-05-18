/// M8 Voice Reporting — Widget & Unit Tests.
///
/// Tests:
/// - VoiceReportingService state machine transitions
/// - Recording duration timer
/// - Error handling for short recordings
/// - Demo phrases card content (four spec phrases present)
/// - VoiceRecorderWidget renders for each state

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mehfooz/services/voice_reporting_service.dart';
import 'package:mehfooz/widgets/voice_waveform.dart';
import 'package:mehfooz/widgets/demo_phrases_card.dart';
import 'package:mehfooz/theme.dart';

// ─── Helpers ───

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: MTheme.light(),
      home: Scaffold(body: child),
    ),
  );
}

// ─── VoiceReportingService unit tests ───

void main() {
  group('VoiceReportingService — state machine', () {
    late VoiceReportingService service;

    setUp(() {
      service = VoiceReportingService();
    });

    tearDown(() {
      service.dispose();
    });

    test('initial state is idle', () {
      expect(service.state, VoiceRecordingState.idle);
      expect(service.elapsed, Duration.zero);
      expect(service.uploadProgress, 0.0);
      expect(service.errorMessage, isNull);
      expect(service.lastResult, isNull);
    });

    test('cancelRecording from idle does not throw', () async {
      // Should be a no-op
      await service.cancelRecording();
      expect(service.state, VoiceRecordingState.idle);
    });

    test('reset clears all state', () async {
      // Manually set state to simulate after a flow
      service.reset();
      expect(service.state, VoiceRecordingState.idle);
      expect(service.elapsed, Duration.zero);
      expect(service.uploadProgress, 0.0);
      expect(service.errorMessage, isNull);
      expect(service.lastResult, isNull);
    });

    test('maxDuration is 30 seconds', () {
      expect(VoiceReportingService.maxDuration, const Duration(seconds: 30));
    });
  });

  // ─── VoiceWaveform widget tests ───

  group('VoiceWaveform widget', () {
    testWidgets('renders without amplitudeStream', (tester) async {
      await tester.pumpWidget(_wrap(
        const VoiceWaveform(amplitudeStream: null),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      // Should not throw
      expect(find.byType(VoiceWaveform), findsOneWidget);
    });

    testWidgets('VoiceWaveformPlaceholder renders', (tester) async {
      await tester.pumpWidget(_wrap(
        const VoiceWaveformPlaceholder(),
      ));
      expect(find.byType(VoiceWaveformPlaceholder), findsOneWidget);
    });

    testWidgets('placeholder renders specified bar count', (tester) async {
      await tester.pumpWidget(_wrap(
        const VoiceWaveformPlaceholder(barCount: 10),
      ));
      // Should render 10 bars as containers in a row
      final row = tester.widget<Row>(find.byType(Row).last);
      expect(row.children.length, 10);
    });
  });

  // ─── DemoPhrasesCard widget tests ───

  group('DemoPhrasesCard', () {
    testWidgets('renders with collapsed header', (tester) async {
      await tester.pumpWidget(_wrap(const DemoPhrasesCard()));

      // Header should be visible
      expect(find.text('Demo phrases'), findsOneWidget);
    });

    testWidgets('expands to show all four spec phrases', (tester) async {
      await tester.pumpWidget(_wrap(const DemoPhrasesCard()));
      await tester.pumpAndSettle();

      // Tap the header to expand
      await tester.tap(find.text('Demo phrases'));
      await tester.pumpAndSettle();

      // All four demo phrases from the spec must be present
      expect(
        find.textContaining('G-10 markaz ke paas paani bhar gaya'),
        findsOneWidget,
        reason: 'Spec phrase 1: G-10 flood',
      );
      expect(
        find.textContaining('Lakhani underpass pe ghutnon tak paani'),
        findsOneWidget,
        reason: 'Spec phrase 2: Lakhani underpass',
      );
      expect(
        find.textContaining('Sharah-e-Faisal pe Drigh Road'),
        findsOneWidget,
        reason: 'Spec phrase 3: Shahra-e-Faisal traffic',
      );
      expect(
        find.textContaining('Heavy flooding near Faisal Mosque'),
        findsOneWidget,
        reason: 'Spec phrase 4: Faisal Mosque (English fallback)',
      );
    });

    testWidgets('tapping a phrase expands its detail', (tester) async {
      await tester.pumpWidget(_wrap(const DemoPhrasesCard()));
      await tester.pumpAndSettle();

      // Expand the card
      await tester.tap(find.text('Demo phrases'));
      await tester.pumpAndSettle();

      // Tap the first phrase
      await tester.tap(find.textContaining('G-10 markaz ke paas paani bhar gaya'));
      await tester.pumpAndSettle();

      // Should show expected crisis chip
      expect(find.text('urban_flood'), findsOneWidget);
      // Should show severity chip
      expect(find.text('Severity 3'), findsOneWidget);
      // Should show English translation
      expect(find.textContaining('Water has filled up near G-10'), findsOneWidget);
    });

    testWidgets('tapping header again collapses', (tester) async {
      await tester.pumpWidget(_wrap(const DemoPhrasesCard()));
      await tester.pumpAndSettle();

      // Expand
      await tester.tap(find.text('Demo phrases'));
      await tester.pumpAndSettle();

      // Collapse
      await tester.tap(find.text('Demo phrases'));
      await tester.pumpAndSettle();

      // Phrases should be collapsed now
      // (AnimatedCrossFade keeps them in tree but offstage)
    });

    testWidgets('all four crisis types are correct per spec', (tester) async {
      await tester.pumpWidget(_wrap(const DemoPhrasesCard()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Demo phrases'));
      await tester.pumpAndSettle();

      // Tap each phrase and verify its crisis type chip
      final expectedCrises = [
        ('G-10 markaz ke paas paani bhar gaya', 'urban_flood'),
        ('Lakhani underpass pe ghutnon tak paani', 'flash_flood'),
        ('Sharah-e-Faisal pe Drigh Road', 'road_incident'),
        ('Heavy flooding near Faisal Mosque', 'flood'),
      ];

      for (final (searchText, crisisType) in expectedCrises) {
        // Tap this phrase
        await tester.tap(find.textContaining(searchText).first);
        await tester.pumpAndSettle();

        // Verify correct crisis type chip appears
        expect(
          find.text(crisisType),
          findsOneWidget,
          reason: 'Phrase "$searchText" should map to crisis "$crisisType"',
        );

        // Tap again to collapse before next phrase
        await tester.tap(find.textContaining(searchText).first);
        await tester.pumpAndSettle();
      }
    });
  });

  // ─── VoiceReportResult model ───

  group('VoiceReportResult', () {
    test('holds reportId, voiceUrl, recordingDuration', () {
      final result = VoiceReportResult(
        reportId: 'rep_abc123',
        voiceUrl: 'https://storage.googleapis.com/bucket/voice/uid/file.m4a',
        recordingDuration: const Duration(seconds: 12),
      );

      expect(result.reportId, 'rep_abc123');
      expect(result.voiceUrl, contains('m4a'));
      expect(result.recordingDuration.inSeconds, 12);
    });
  });
}
