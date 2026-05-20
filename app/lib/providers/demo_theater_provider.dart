/// M16 — Demo Theater State Management
///
/// Drives the 4-minute demo script: phase tracking, countdown timer,
/// and readiness checklist state. Does not touch Firestore — purely local.
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Phase definitions ─────────────────────────────────────────────────────

enum DemoPhase {
  hook,       // 0:00 – 0:30
  citizen,    // 0:30 – 1:15
  agents,     // 1:15 – 2:15
  outcomes,   // 2:15 – 3:00
  authority,  // 3:00 – 3:30
  impact,     // 3:30 – 4:00
}

extension DemoPhaseInfo on DemoPhase {
  String get label => const {
        DemoPhase.hook:      'Hook',
        DemoPhase.citizen:   'Citizen',
        DemoPhase.agents:    'Agents',
        DemoPhase.outcomes:  'Outcomes',
        DemoPhase.authority: 'Authority',
        DemoPhase.impact:    'Impact',
      }[this]!;

  String get timing => const {
        DemoPhase.hook:      '0:00 – 0:30',
        DemoPhase.citizen:   '0:30 – 1:15',
        DemoPhase.agents:    '1:15 – 2:15',
        DemoPhase.outcomes:  '2:15 – 3:00',
        DemoPhase.authority: '3:00 – 3:30',
        DemoPhase.impact:    '3:30 – 4:00',
      }[this]!;

  int get startSeconds => const {
        DemoPhase.hook:      0,
        DemoPhase.citizen:   30,
        DemoPhase.agents:    75,
        DemoPhase.outcomes:  135,
        DemoPhase.authority: 180,
        DemoPhase.impact:    210,
      }[this]!;

  int get durationSeconds => const {
        DemoPhase.hook:      30,
        DemoPhase.citizen:   45,
        DemoPhase.agents:    60,
        DemoPhase.outcomes:  45,
        DemoPhase.authority: 30,
        DemoPhase.impact:    30,
      }[this]!;

  String get headline => const {
        DemoPhase.hook:
            'Hook — The Problem',
        DemoPhase.citizen:
            'Citizen Aisha Reports',
        DemoPhase.agents:
            'Agents Activate',
        DemoPhase.outcomes:
            'Outcomes for 3 Citizens',
        DemoPhase.authority:
            'Authority View',
        DemoPhase.impact:
            'Final Impact Card',
      }[this]!;

  String get description => const {
        DemoPhase.hook:
            'Show real photo from 2025 Karachi flooding.\n\n'
            'Stat: "163mm rain in one day, thousands stranded overnight."\n\n'
            'One sentence: "Authorities had data. Citizens had nothing."',
        DemoPhase.citizen:
            'Phone screen recording: Aisha in F-10 opens app, taps Report, '
            'holds mic and says in Roman Urdu:\n\n'
            '"F-10 markaz ke paas paani bhar raha hai."\n\n'
            'She submits. Map updates with her dot.',
        DemoPhase.agents:
            'Cut to Antigravity Manager view. Five agent workspaces light up.\n\n'
            'Show Situation card emerging:\n'
            '"8 reports + 31mm rain + traffic spike = HIGH confidence urban_flood"\n\n'
            'Zoom into feedback loop — Detection at 0.55 confidence, '
            'Orchestrator triggers Ingestion retry, Detection promotes to 0.87.',
        DemoPhase.outcomes:
            'Three citizen outcomes in split-view:\n\n'
            '• Bilal → Safe Route → 3 routes, picks green\n'
            '• Sara → SOS → location auto-WhatsApp\'d, Rescue 1122 dialed\n'
            '• Ahmed (Dubai) → watches parents\' street flip to "Active alert"',
        DemoPhase.authority:
            'Cut to M15 dashboard on laptop.\n\n'
            'PDMA ticket arrives in real-time. '
            'Before/After split-screen runs:\n'
            '• Left: T-0, unverified dots, no reroutes\n'
            '• Right: T+90s, verified polygon, routes diverted, counter ticking.',
        DemoPhase.impact:
            'Final summary card on screen:\n\n'
            '"47 users alerted · 3 routes flagged · 2 tickets dispatched"\n'
            '"Est. 22 min congestion reduction"\n\n'
            'Team logo. Cut.',
      }[this]!;

  String get talkingPoint => const {
        DemoPhase.hook:
            'Lead with real human cost — not tech. '
            'Make judges feel the problem before showing the solution.',
        DemoPhase.citizen:
            'Urdu voice reporting is the "wow" moment. '
            'Make sure audio is on, mic is working, and the demo phrase is ready.',
        DemoPhase.agents:
            'Highlight the feedback loop — this is the agentic behavior. '
            'Point out confidence rising from 0.55 to 0.87 after retry.',
        DemoPhase.outcomes:
            'Three users = three personas covering the spectrum: '
            'evacuee, driver, diaspora. Human stories, not just data.',
        DemoPhase.authority:
            'Before/After is the visceral "look what the agents did" moment. '
            'Let it run — don\'t narrate over the animation.',
        DemoPhase.impact:
            'Label estimates as estimates — judges respect honesty. '
            'End on the numbers, let them land, then cut.',
      }[this]!;
}

// ─── Checklist ─────────────────────────────────────────────────────────────

class ChecklistItem {
  final String id;
  final String label;
  final bool checked;

  const ChecklistItem({
    required this.id,
    required this.label,
    this.checked = false,
  });

  ChecklistItem copyWith({bool? checked}) =>
      ChecklistItem(id: id, label: label, checked: checked ?? this.checked);
}

const _kDefaultChecklist = [
  ChecklistItem(id: 'backend',   label: 'Backend pre-seeded (replay_scenario.py g10)'),
  ChecklistItem(id: 'phone',     label: 'Phone charged, app installed, demo user logged in'),
  ChecklistItem(id: 'm15',       label: 'M15 dashboard tab open in browser'),
  ChecklistItem(id: 'antigrav',  label: 'Antigravity Manager view pre-loaded'),
  ChecklistItem(id: 'backup',    label: 'Backup video on local laptop'),
  ChecklistItem(id: 'wifi',      label: 'Venue WiFi tested, hotspot ready as fallback'),
  ChecklistItem(id: 'rehearsed', label: 'Demo rehearsed 3+ times end-to-end'),
];

// ─── State ─────────────────────────────────────────────────────────────────

class DemoTheaterState {
  final DemoPhase currentPhase;
  final int elapsedSeconds;    // 0–240 (4 min)
  final bool isRunning;
  final List<ChecklistItem> checklist;

  const DemoTheaterState({
    this.currentPhase = DemoPhase.hook,
    this.elapsedSeconds = 0,
    this.isRunning = false,
    this.checklist = _kDefaultChecklist,
  });

  DemoTheaterState copyWith({
    DemoPhase? currentPhase,
    int? elapsedSeconds,
    bool? isRunning,
    List<ChecklistItem>? checklist,
  }) =>
      DemoTheaterState(
        currentPhase:   currentPhase   ?? this.currentPhase,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        isRunning:      isRunning      ?? this.isRunning,
        checklist:      checklist      ?? this.checklist,
      );

  bool get isComplete => elapsedSeconds >= 240;

  String get elapsedFormatted {
    final m = elapsedSeconds ~/ 60;
    final s = elapsedSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get remainingFormatted {
    final rem = (240 - elapsedSeconds).clamp(0, 240);
    final m = rem ~/ 60;
    final s = rem % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  double get progress => (elapsedSeconds / 240).clamp(0.0, 1.0);

  int get checklistDone => checklist.where((c) => c.checked).length;
  bool get checklistComplete => checklistDone == checklist.length;
}

// ─── Notifier ──────────────────────────────────────────────────────────────

class DemoTheaterNotifier extends StateNotifier<DemoTheaterState> {
  DemoTheaterNotifier() : super(const DemoTheaterState());

  Timer? _timer;

  DemoPhase _phaseForSeconds(int sec) {
    for (final phase in DemoPhase.values.reversed) {
      if (sec >= phase.startSeconds) return phase;
    }
    return DemoPhase.hook;
  }

  void startPause() {
    if (state.isRunning) {
      _timer?.cancel();
      state = state.copyWith(isRunning: false);
    } else if (!state.isComplete) {
      state = state.copyWith(isRunning: true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        final next = state.elapsedSeconds + 1;
        if (next >= 240) {
          _timer?.cancel();
          state = state.copyWith(
            elapsedSeconds: 240,
            isRunning: false,
            currentPhase: DemoPhase.impact,
          );
        } else {
          state = state.copyWith(
            elapsedSeconds: next,
            currentPhase: _phaseForSeconds(next),
          );
        }
      });
    }
  }

  void reset() {
    _timer?.cancel();
    state = const DemoTheaterState();
  }

  void jumpToPhase(DemoPhase phase) {
    _timer?.cancel();
    state = state.copyWith(
      currentPhase: phase,
      elapsedSeconds: phase.startSeconds,
      isRunning: false,
    );
  }

  void toggleChecklist(String id) {
    final updated = state.checklist.map((item) {
      if (item.id != id) return item;
      return item.copyWith(checked: !item.checked);
    }).toList();
    state = state.copyWith(checklist: updated);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ─── Provider ──────────────────────────────────────────────────────────────

final demoTheaterProvider =
    StateNotifierProvider<DemoTheaterNotifier, DemoTheaterState>(
  (ref) => DemoTheaterNotifier(),
);
