/// Screen 2 — Home/Map
///
/// The main dashboard: Google Map centered on user location,
/// Firestore-streamed events as colored polygons, report heatmap,
/// and active alert count. FABs for Report and SOS.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';
import '../router.dart';
import '../providers/broadcast_provider.dart';
import '../widgets/alert_banner.dart';
import '../widgets/incident_card.dart';
import '../widgets/heatwave_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;

  // Mock data for demo — in production, Firestore streams
  final List<Map<String, dynamic>> _mockEvents = [
    {
      'event_id': 'evt-g10-001',
      'crisis_type': 'urban_flood',
      'severity': 4,
      'city': 'Islamabad',
      'area': 'G-10/2',
      'explanation_en': '12 reports + 38mm rain in 45 min + traffic +180% at IJP Road = severe urban flood.',
      'explanation_ur': '12 رپورٹس + 38mm بارش 45 منٹ میں + IJP روڈ پر ٹریفک +180% = شدید سیلاب',
      'confidence': 0.87,
      'time_ago': '15 min ago',
      'reports_count': 12,
    },
    {
      'event_id': 'evt-g11-002',
      'crisis_type': 'urban_flood',
      'severity': 2,
      'city': 'Islamabad',
      'area': 'G-11/3',
      'explanation_en': '4 reports + light rain + minor traffic delay = localized water accumulation.',
      'explanation_ur': '4 رپورٹس + ہلکی بارش + معمولی ٹریفک = مقامی پانی جمع',
      'confidence': 0.62,
      'time_ago': '28 min ago',
      'reports_count': 4,
    },
    {
      'event_id': 'evt-f10-003',
      'crisis_type': 'power_outage',
      'severity': 1,
      'city': 'Islamabad',
      'area': 'F-10 Markaz',
      'explanation_en': '3 reports of power outage near F-10 Markaz. IESCO notified.',
      'explanation_ur': 'F-10 مرکز کے قریب بجلی بند — 3 رپورٹس — IESCO کو اطلاع',
      'confidence': 0.55,
      'time_ago': '42 min ago',
      'reports_count': 3,
    },
  ];

  // Heatwave demo data (M11) — in production, fetched from Open-Meteo
  final double _demoHeatIndex = 46.3;
  final double _demoTempC = 44.1;
  final String _heatCity = 'Karachi';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map placeholder — in production, GoogleMap widget
          _buildMapPlaceholder(),

          // Top alert banner
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: AlertBanner(
              count: _mockEvents.where((e) => (e['severity'] as int) >= 3).length,
              onTap: () => _showIncidentSheet(),
            ),
          ),

          // Heatwave card (M11) — shown when heat index > 35°C
          if (_demoHeatIndex > 35)
            Positioned(
              top: MediaQuery.of(context).padding.top + 64,
              left: 16,
              right: 16,
              child: HeatwaveCard(
                heatIndexC: _demoHeatIndex,
                tempC: _demoTempC,
                city: _heatCity,
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRouter.heatwave,
                  arguments: _heatCity,
                ),
              ),
            ),

          // Mosque broadcasts banner (M14)
          Positioned(
            top: MediaQuery.of(context).padding.top +
                (_demoHeatIndex > 35 ? 158 : 64),
            left: 16,
            right: 16,
            child: _buildBroadcastBanner(),
          ),

          // Bottom sheet handle
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomSheet(),
          ),

          // Report FAB
          Positioned(
            bottom: 200,
            right: 16,
            child: _buildReportFab(),
          ),

          // SOS FAB
          Positioned(
            bottom: 200,
            left: 16,
            child: _buildSosFab(),
          ),
        ],
      ),
    );
  }

  Widget _buildMapPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFE8E4D8),
            Color(0xFFF0ECE0),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.map_outlined,
              size: 80,
              color: MColors.textSecondary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Islamabad — G-10 Area',
              style: GoogleFonts.inter(
                fontSize: 16,
                color: MColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '33.6920° N, 73.0130° E',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: MColors.textSecondary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            // Severity legend
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendDot(MColors.severity1, 'Minor'),
                _legendDot(MColors.severity3, 'Significant'),
                _legendDot(MColors.severity5, 'Critical'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: MColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSheet() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: MColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Handle
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: MColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Active Incidents',
                  style: MTypography.titleEn(context),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _showIncidentSheet,
                  icon: const Icon(Icons.expand_less, size: 18),
                  label: Text('${_mockEvents.length} total'),
                ),
              ],
            ),
          ),

          // Horizontal list
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _mockEvents.length,
              itemBuilder: (context, index) {
                final event = _mockEvents[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 260,
                    child: IncidentCard(
                      event: event,
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRouter.situationDetail,
                        arguments: event['event_id'],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBroadcastBanner() {
    final feed = ref.watch(activeBroadcastsProvider);
    final muted = ref.watch(mutedMosquesProvider);

    return feed.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        final visible =
            list.where((b) => !muted.contains(b.mosqueId)).toList();
        if (visible.isEmpty) return const SizedBox.shrink();
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () =>
                Navigator.pushNamed(context, AppRouter.broadcastFeed),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: MColors.green.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Text('🕌', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${visible.length} verified community '
                      'broadcast${visible.length == 1 ? '' : 's'} nearby',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReportFab() {
    return FloatingActionButton.extended(
      heroTag: 'report_fab',
      onPressed: () => Navigator.pushNamed(context, AppRouter.report),
      backgroundColor: MColors.red,
      icon: const Icon(Icons.add_circle_outline),
      label: Text(
        'Report',
        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildSosFab() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = 1.0 + (_pulseController.value * 0.05);
        return Transform.scale(
          scale: scale,
          child: FloatingActionButton(
            heroTag: 'sos_fab',
            onPressed: () => Navigator.pushNamed(context, AppRouter.sos),
            backgroundColor: MColors.sos,
            child: Text(
              'SOS',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

  void _showIncidentSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: MColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: MColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Text('All Incidents', style: MTypography.titleEn(context)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, AppRouter.safeRoute),
                    child: const Text('Find safe route'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _mockEvents.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  return IncidentCard(
                    event: _mockEvents[index],
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(
                        context,
                        AppRouter.situationDetail,
                        arguments: _mockEvents[index]['event_id'],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
