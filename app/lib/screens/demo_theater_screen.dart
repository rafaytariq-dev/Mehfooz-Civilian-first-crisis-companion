/// M16 — Demo Theater Screen
///
/// 4-minute demo script guide with:
///   • Phase timeline + auto-advancing countdown timer
///   • Per-phase talking points and screen navigation shortcuts
///   • Demo readiness checklist
///   • Impact summary card
///   • Replay scenario + trace export triggers
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/demo_theater_provider.dart';
import '../router.dart';
import '../theme.dart';

class DemoTheaterScreen extends ConsumerWidget {
  const DemoTheaterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state    = ref.watch(demoTheaterProvider);
    final notifier = ref.read(demoTheaterProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: _buildAppBar(context, state, notifier),
      body: SafeArea(
        child: Column(
          children: [
            // Timer bar
            _TimerBar(state: state),

            // Phase selector
            _PhaseStrip(state: state, notifier: notifier),

            // Main content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _PhaseCard(state: state),
                    const SizedBox(height: 12),
                    _NavigationRow(phase: state.currentPhase),
                    const SizedBox(height: 16),
                    _ImpactCard(),
                    const SizedBox(height: 16),
                    _ReplayControls(),
                    const SizedBox(height: 16),
                    _ChecklistCard(state: state, notifier: notifier),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar(
    BuildContext context,
    DemoTheaterState state,
    DemoTheaterNotifier notifier,
  ) {
    return AppBar(
      backgroundColor: const Color(0xFF161B22),
      foregroundColor: Colors.white,
      title: Row(
        children: [
          const Text('🎬', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(
            'Demo Theater',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          // Live / Complete chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: state.isComplete
                  ? MColors.green.withValues(alpha: 0.2)
                  : state.isRunning
                      ? Colors.red.withValues(alpha: 0.2)
                      : Colors.white12,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: state.isComplete
                    ? MColors.green
                    : state.isRunning
                        ? Colors.red
                        : Colors.white30,
                width: 1,
              ),
            ),
            child: Text(
              state.isComplete
                  ? 'Complete'
                  : state.isRunning
                      ? '● LIVE'
                      : 'Standby',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: state.isComplete
                    ? MColors.green
                    : state.isRunning
                        ? Colors.red
                        : Colors.white60,
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_outlined, color: Colors.white70),
          tooltip: 'Reset timer',
          onPressed: notifier.reset,
        ),
      ],
    );
  }
}

// ─── Timer bar ─────────────────────────────────────────────────────────────

class _TimerBar extends ConsumerWidget {
  final DemoTheaterState state;
  const _TimerBar({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(demoTheaterProvider.notifier);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: const Color(0xFF161B22),
      child: Column(
        children: [
          Row(
            children: [
              // Elapsed
              Text(
                state.elapsedFormatted,
                style: GoogleFonts.robotoMono(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: state.isComplete ? MColors.green : Colors.white,
                ),
              ),
              const Spacer(),
              // Start/Pause
              GestureDetector(
                onTap: notifier.startPause,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: state.isRunning ? Colors.red : MColors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        state.isRunning ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        state.isRunning
                            ? 'Pause'
                            : state.isComplete
                                ? 'Done'
                                : 'Start',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '–${state.remainingFormatted}',
                style: GoogleFonts.robotoMono(
                  fontSize: 14,
                  color: Colors.white38,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.progress,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(
                state.isComplete ? MColors.green : MColors.amber,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Phase strip ───────────────────────────────────────────────────────────

class _PhaseStrip extends StatelessWidget {
  final DemoTheaterState state;
  final DemoTheaterNotifier notifier;

  const _PhaseStrip({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: const Color(0xFF161B22),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: DemoPhase.values.map((phase) {
          final isActive = phase == state.currentPhase;
          final isDone =
              state.elapsedSeconds >= phase.startSeconds + phase.durationSeconds;

          return GestureDetector(
            onTap: () => notifier.jumpToPhase(phase),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? MColors.amber
                    : isDone
                        ? MColors.green.withValues(alpha: 0.25)
                        : Colors.white10,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive
                      ? MColors.amber
                      : isDone
                          ? MColors.green
                          : Colors.white24,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isDone && !isActive) ...[
                    const Icon(Icons.check, size: 12, color: MColors.green),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    phase.label,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive
                          ? const Color(0xFF0D1117)
                          : isDone
                              ? MColors.green
                              : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Phase card ────────────────────────────────────────────────────────────

class _PhaseCard extends StatelessWidget {
  final DemoTheaterState state;
  const _PhaseCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final phase = state.currentPhase;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MColors.amber.withValues(alpha: 0.4), width: 1),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Phase header
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: MColors.amber,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  phase.timing,
                  style: GoogleFonts.robotoMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0D1117),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  phase.headline,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Colors.white12),
          const SizedBox(height: 12),

          // Script description
          Text(
            'Script',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white38,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            phase.description,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.87),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),

          // Talking point
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💡', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    phase.talkingPoint,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: MColors.amber,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Navigation row ─────────────────────────────────────────────────────────

class _NavigationRow extends StatelessWidget {
  final DemoPhase phase;
  const _NavigationRow({required this.phase});

  @override
  Widget build(BuildContext context) {
    final buttons = _buttonsFor(context, phase);
    if (buttons.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Navigation',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white38,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: buttons,
        ),
      ],
    );
  }

  List<Widget> _buttonsFor(BuildContext context, DemoPhase phase) {
    switch (phase) {
      case DemoPhase.hook:
        return [];
      case DemoPhase.citizen:
        return [
          _NavButton(
            label: 'Open Report Screen',
            icon: Icons.mic,
            color: MColors.red,
            onTap: () => Navigator.pushNamed(context, AppRouter.report),
          ),
          _NavButton(
            label: 'Open Home Map',
            icon: Icons.map,
            color: Colors.blueAccent,
            onTap: () => Navigator.popUntil(context, (r) => r.isFirst),
          ),
        ];
      case DemoPhase.agents:
        return [
          _NavButton(
            label: 'Agent Trace',
            icon: Icons.account_tree,
            color: MColors.green,
            onTap: () =>
                Navigator.pushNamed(context, AppRouter.agentTrace, arguments: ''),
          ),
        ];
      case DemoPhase.outcomes:
        return [
          _NavButton(
            label: 'Safe Route',
            icon: Icons.directions,
            color: MColors.green,
            onTap: () => Navigator.pushNamed(context, AppRouter.safeRoute),
          ),
          _NavButton(
            label: 'SOS Screen',
            icon: Icons.warning,
            color: MColors.red,
            onTap: () => Navigator.pushNamed(context, AppRouter.sos),
          ),
          _NavButton(
            label: 'Situation Detail',
            icon: Icons.info_outline,
            color: MColors.amber,
            onTap: () => Navigator.pushNamed(
              context,
              AppRouter.situationDetail,
              arguments: 'evt_g10_20250901_001',
            ),
          ),
        ];
      case DemoPhase.authority:
        return [
          _NavButton(
            label: 'Open M15 Dashboard',
            icon: Icons.open_in_browser,
            color: Colors.blueAccent,
            onTap: () => _launchM15(),
          ),
        ];
      case DemoPhase.impact:
        return [
          _NavButton(
            label: 'Copy Impact Numbers',
            icon: Icons.copy,
            color: MColors.green,
            onTap: () {
              Clipboard.setData(const ClipboardData(
                text: '47 users alerted · 3 routes flagged · '
                    '2 tickets dispatched · est. 22 min congestion reduction',
              ));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Impact numbers copied!')),
              );
            },
          ),
        ];
    }
  }

  void _launchM15() {
    launchUrl(
      Uri.parse('https://mehfooz-prod.web.app'),
      mode: LaunchMode.externalApplication,
    );
  }
}

class _NavButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _NavButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Impact card ────────────────────────────────────────────────────────────

class _ImpactCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            MColors.green.withValues(alpha: 0.15),
            MColors.green.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MColors.green.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📊', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                'Impact Summary (Demo Numbers)',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: MColors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ImpactRow(icon: '👥', value: '47', label: 'users alerted'),
          const SizedBox(height: 8),
          _ImpactRow(icon: '🛣️', value: '3',  label: 'routes flagged'),
          const SizedBox(height: 8),
          _ImpactRow(icon: '🎫', value: '2',  label: 'tickets dispatched (PDMA + Rescue 1122)'),
          const SizedBox(height: 8),
          _ImpactRow(icon: '⏱️', value: '22m', label: 'estimated congestion reduction'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              '⚠️ Estimates — heuristic values for demonstration. '
              'Not real-world measurements.',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: Colors.white54,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImpactRow extends StatelessWidget {
  final String icon;
  final String value;
  final String label;

  const _ImpactRow({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        Text(
          value,
          style: GoogleFonts.robotoMono(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.white60,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Replay controls ─────────────────────────────────────────────────────────

class _ReplayControls extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Demo Controls',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white38,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ControlButton(
                  icon: Icons.play_circle_outline,
                  label: 'Run Scenario',
                  subtitle: 'replay_scenario.py g10 --speed 10',
                  color: MColors.amber,
                  onTap: () => _showReplayDialog(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ControlButton(
                  icon: Icons.download_outlined,
                  label: 'Export Traces',
                  subtitle: 'data/sample_traces.json',
                  color: Colors.blueAccent,
                  onTap: () => _showExportDialog(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ControlButton(
                  icon: Icons.open_in_new,
                  label: 'M15 Dashboard',
                  subtitle: 'mehfooz-prod.web.app',
                  color: MColors.green,
                  onTap: () => launchUrl(
                    Uri.parse('https://mehfooz-prod.web.app'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ControlButton(
                  icon: Icons.medical_services,
                  label: 'First Aid',
                  subtitle: 'Offline kit demo',
                  color: Colors.redAccent,
                  onTap: () =>
                      Navigator.pushNamed(context, AppRouter.firstAid),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showReplayDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Text(
          'Run G-10 Scenario',
          style: GoogleFonts.inter(color: Colors.white, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Run this command in your terminal:',
              style: GoogleFonts.inter(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                'python data/replay_scenario.py g10 --speed 10',
                style: GoogleFonts.robotoMono(
                  fontSize: 12,
                  color: MColors.green,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '10× speed = 9 minutes for the full 90-min scenario',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white38,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(const ClipboardData(
                text: 'python data/replay_scenario.py g10 --speed 10',
              ));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Command copied to clipboard')),
              );
            },
            child: Text(
              'Copy Command',
              style: GoogleFonts.inter(color: MColors.amber),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: GoogleFonts.inter(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Text(
          'Agent Traces',
          style: GoogleFonts.inter(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          'Sample agent traces are pre-exported to:\n\n'
          'data/sample_traces.json\n\n'
          'For a live export, run the G-10 scenario and view the '
          'agent_traces collection in Firestore Console.',
          style: GoogleFonts.inter(color: Colors.white60, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: GoogleFonts.inter(color: MColors.amber),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.robotoMono(
                fontSize: 10,
                color: Colors.white38,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Readiness checklist ────────────────────────────────────────────────────

class _ChecklistCard extends StatelessWidget {
  final DemoTheaterState state;
  final DemoTheaterNotifier notifier;

  const _ChecklistCard({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final done = state.checklistDone;
    final total = state.checklist.length;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: state.checklistComplete
              ? MColors.green.withValues(alpha: 0.5)
              : Colors.white12,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                state.checklistComplete ? '✅' : '📋',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(width: 8),
              Text(
                'Demo Readiness Checklist',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color:
                      state.checklistComplete ? MColors.green : Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: state.checklistComplete
                      ? MColors.green.withValues(alpha: 0.2)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$done / $total',
                  style: GoogleFonts.robotoMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: state.checklistComplete
                        ? MColors.green
                        : Colors.white60,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: done / total,
              backgroundColor: Colors.white10,
              valueColor:
                  AlwaysStoppedAnimation<Color>(MColors.green),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 12),
          ...state.checklist.map(
            (item) => _CheckItem(
              item: item,
              onToggle: () => notifier.toggleChecklist(item.id),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckItem extends StatelessWidget {
  final ChecklistItem item;
  final VoidCallback onToggle;

  const _CheckItem({required this.item, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: item.checked ? MColors.green : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: item.checked ? MColors.green : Colors.white30,
                  width: 1.5,
                ),
              ),
              child: item.checked
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: item.checked ? Colors.white54 : Colors.white.withValues(alpha: 0.87),
                  decoration: item.checked
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
