/// Screen 7 — Agent Trace
///
/// Power-user view showing agent reasoning steps, tool calls, and timing.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

class AgentTraceScreen extends StatelessWidget {
  final String eventId;
  const AgentTraceScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent Reasoning Trace'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Export as JSON',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Trace exported as JSON')),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MColors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_tree, color: MColors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Full Chain Trace',
                          style: MTypography.titleEn(context)),
                      Text(
                        'Event: $eventId',
                        style: MTypography.captionEn(context),
                      ),
                    ],
                  ),
                ),
                Text(
                  '4.2s total',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: MColors.green,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Agent steps
          _traceStep(
            context,
            agent: 'Ingestion',
            step: 'normalize_text',
            reasoning:
                'Input is Roman Urdu: "G-10 mein paani bhar gaya, ghutnon tak". Detected language=roman_ur. Translated to English. Inferred crisis_type=urban_flood, severity=3.',
            tools: [
              ('normalize_text', '1,245ms',
                  '{"lang":"roman_ur","type":"urban_flood","sev":3}'),
              ('verify_photo', '890ms',
                  '{"is_match":true,"confidence":0.91}'),
              ('write_signal', '120ms',
                  '{"collection":"signals_citizen","id":"sig-abc123"}'),
            ],
            color: Colors.blue,
            durationMs: 2255,
          ),
          _traceStep(
            context,
            agent: 'Detection',
            step: 'cluster_and_reason',
            reasoning:
                'DBSCAN found 1 cluster with 12 signals in G-10 area. Modalities present: citizen_report(12), weather(1), traffic(1), photo_verified(2). Count=4 ≥ 2 → promoting to verified. Confidence: 3+ modalities + flood_prone prior → 0.87.',
            tools: [
              ('read_recent_signals', '340ms', '{"count":15}'),
              ('run_clustering', '45ms', '{"clusters":1,"noise":3}'),
              ('cross_modal_check', '2ms', '{"modalities":4}'),
              ('write_event', '180ms', '{"event_id":"evt-g10-001"}'),
            ],
            color: Colors.purple,
            durationMs: 567,
          ),
          _traceStep(
            context,
            agent: 'Planning',
            step: 'per_user_decision_tree',
            reasoning:
                'Event severity=4, 8 users within 5km. 2 users in polygon → EVACUATE. 3 users within 2km → AVOID_AREA. 1 user with active route through polygon → REROUTE. 2 users with family in area → CHECK_ON_FAMILY.',
            tools: [
              ('get_users_near', '280ms', '{"users":8}'),
              ('lookup_helpline', '90ms',
                  '{"name":"Rescue 1122","phone":"1122"}'),
              ('find_nearest_safe_spots', '150ms', '{"spots":3}'),
              ('write_plan', '110ms', '{"plan_id":"plan-xyz"}'),
            ],
            color: Colors.orange,
            durationMs: 630,
          ),
          _traceStep(
            context,
            agent: 'Simulation',
            step: 'execute_plan',
            reasoning:
                'Dispatched to PDMA + Rescue 1122. Queued 8 push notifications (2 SOS, 3 high, 3 med). Flagged 3 routes. Estimated impact: 3 users diverted, ~22 min congestion reduction.',
            tools: [
              ('post_to_mock (PDMA)', '200ms',
                  '{"ticket_id":"PDMA-1234"}'),
              ('post_to_mock (Rescue 1122)', '180ms',
                  '{"ticket_id":"R1122-5678"}'),
              ('queue_push (×8)', '350ms', '{"queued":8}'),
            ],
            color: Colors.teal,
            durationMs: 730,
          ),
        ],
      ),
    );
  }

  Widget _traceStep(
    BuildContext context, {
    required String agent,
    required String step,
    required String reasoning,
    required List<(String, String, String)> tools,
    required Color color,
    required int durationMs,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              agent[0],
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ),
        title: Text(
          '$agent → $step',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '${durationMs}ms',
          style: GoogleFonts.inter(fontSize: 12, color: color),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Reasoning
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: MColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    reasoning,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: MColors.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Tool calls
                Text(
                  'Tool Calls',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: MColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                ...tools.map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.functions, size: 14, color: color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    t.$1,
                                    style: GoogleFonts.firaCode(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    t.$2,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: MColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                t.$3,
                                style: GoogleFonts.firaCode(
                                  fontSize: 10,
                                  color: MColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
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
