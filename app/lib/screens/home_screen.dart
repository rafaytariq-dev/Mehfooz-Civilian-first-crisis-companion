/// Screen 2 — Home/Map
///
/// Real GoogleMap centered on user location. Three live Firestore streams:
///   • events (verified) → colored polygons by severity
///   • events (candidate) → amber dots
///   • active broadcasts → green mosque pins (M14)
///
/// FABs: Report (red, bottom-right) · SOS (pulsing, bottom-left).
/// Bottom sheet: live incident list ordered by distance/recency.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../theme.dart';
import '../router.dart';
import '../providers/broadcast_provider.dart';
import '../providers/heatwave_provider.dart';
import '../widgets/alert_banner.dart';
import '../widgets/incident_card.dart';
import '../widgets/heatwave_card.dart';

// Islamabad G-10 — default demo center
const _kDefaultCenter = LatLng(33.6920, 73.0130);
const _kDefaultZoom = 13.0;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  // ── Map ──────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  final CameraPosition _initialCamera = const CameraPosition(
    target: _kDefaultCenter,
    zoom: _kDefaultZoom,
  );
  Set<Polygon> _polygons = {};
  Set<Marker> _candidateMarkers = {};

  // ── Data ─────────────────────────────────────────────────────
  List<Map<String, dynamic>> _events = [];
  StreamSubscription<QuerySnapshot>? _eventsSub;

  // ── Animation ────────────────────────────────────────────────
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _subscribeToEvents();
    _centerOnUserLocation();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _eventsSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // ── Firestore stream ──────────────────────────────────────────
  void _subscribeToEvents() {
    _eventsSub = FirebaseFirestore.instance
        .collection('events')
        .where('status', whereIn: ['verified', 'candidate'])
        .orderBy('last_updated', descending: true)
        .limit(30)
        .snapshots()
        .listen((snap) {
          final events = snap.docs.map((d) {
            return {'event_id': d.id, ...d.data()};
          }).toList();

          setState(() {
            _events = events;
            _polygons = _buildPolygons(events);
            _candidateMarkers = _buildCandidateMarkers(events);
          });
        }, onError: (_) {
          // Network error — keep existing data
        });
  }

  // ── Build map overlays ────────────────────────────────────────
  Set<Polygon> _buildPolygons(List<Map<String, dynamic>> events) {
    final result = <Polygon>{};
    for (final evt in events) {
      if (evt['status'] != 'verified') continue;
      final raw = evt['polygon'];
      if (raw == null || raw is! List || raw.length < 3) continue;

      final points = raw
          .map((g) => g is GeoPoint ? LatLng(g.latitude, g.longitude) : null)
          .whereType<LatLng>()
          .toList();
      if (points.length < 3) continue;

      final severity = (evt['severity'] as int?) ?? 3;
      final color = MColors.severityColor(severity);

      result.add(Polygon(
        polygonId: PolygonId(evt['event_id'] as String),
        points: points,
        fillColor: color.withValues(alpha: 0.25),
        strokeColor: color,
        strokeWidth: 2,
        consumeTapEvents: true,
        onTap: () => Navigator.pushNamed(
          context,
          AppRouter.situationDetail,
          arguments: evt['event_id'] as String,
        ),
      ));
    }
    return result;
  }

  Set<Marker> _buildCandidateMarkers(List<Map<String, dynamic>> events) {
    final result = <Marker>{};
    for (final evt in events) {
      if (evt['status'] != 'candidate') continue;
      final raw = evt['centroid'];
      if (raw == null || raw is! GeoPoint) continue;

      result.add(Marker(
        markerId: MarkerId('cand_${evt['event_id']}'),
        position: LatLng(raw.latitude, raw.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        infoWindow: InfoWindow(
          title: _crisisLabel(evt['type'] as String? ?? 'unknown'),
          snippet: 'Candidate — awaiting corroboration',
        ),
        onTap: () => Navigator.pushNamed(
          context,
          AppRouter.situationDetail,
          arguments: evt['event_id'] as String,
        ),
      ));
    }
    return result;
  }

  // ── Center on user location ───────────────────────────────────
  Future<void> _centerOnUserLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
      );
    } catch (_) {
      // Permission denied or timeout — stay at default G-10 center
    }
  }

  // ── Helpers ───────────────────────────────────────────────────
  Map<String, dynamic> _normalizeForCard(Map<String, dynamic> evt) {
    final ts = evt['last_updated'];
    String timeAgo = '—';
    if (ts is Timestamp) {
      final diffMin =
          DateTime.now().difference(ts.toDate()).inMinutes.abs();
      timeAgo = diffMin < 60 ? '$diffMin min ago' : '${diffMin ~/ 60}h ago';
    }

    final signals = evt['contributing_signals'];
    int reportCount = 0;
    if (signals is Map) {
      final reports = signals['reports'];
      if (reports is List) reportCount = reports.length;
    }

    // Derive a display area from explanation_en or fall back to type
    final explanation = evt['explanation_en'] as String? ?? '';
    final centroid = evt['centroid'];
    String area = evt['city'] as String? ?? 'Unknown Area';
    if (explanation.contains('G-10')) area = 'G-10';
    else if (explanation.contains('G-11')) area = 'G-11';
    else if (centroid is GeoPoint) {
      area = '${centroid.latitude.toStringAsFixed(3)}°N';
    }

    return {
      'event_id': evt['event_id'],
      'severity': (evt['severity'] as int?) ?? 3,
      'crisis_type': evt['type'] as String? ?? 'unknown',
      'area': area,
      'time_ago': timeAgo,
      'reports_count': reportCount,
      'confidence': (evt['confidence'] as num?)?.toDouble() ?? 0.5,
      'explanation_en': explanation,
      'explanation_ur': evt['explanation_ur'] as String? ?? '',
    };
  }

  String _crisisLabel(String type) => type
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  List<Map<String, dynamic>> get _verifiedEvents =>
      _events.where((e) => e['status'] == 'verified').toList();

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final heatData = ref.watch(heatWeatherProvider('Karachi'));
    final heatIndexC = heatData.valueOrNull?.heatIndexC ?? 0.0;
    final tempC = heatData.valueOrNull?.tempC ?? 0.0;
    final showHeatwave = heatIndexC > 35;

    return Scaffold(
      body: Stack(
        children: [
          // ── GoogleMap ────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: _initialCamera,
            onMapCreated: (ctrl) {
              _mapController = ctrl;
              _centerOnUserLocation();
            },
            polygons: _polygons,
            markers: _candidateMarkers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            mapType: MapType.normal,
          ),

          // ── Top alert banner ─────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: AlertBanner(
              count: _verifiedEvents
                  .where((e) => (e['severity'] as int?) != null &&
                      (e['severity'] as int) >= 3)
                  .length,
              onTap: _showIncidentSheet,
            ),
          ),

          // ── Heatwave card (M11) ──────────────────────────────
          if (showHeatwave)
            Positioned(
              top: MediaQuery.of(context).padding.top + 64,
              left: 16,
              right: 16,
              child: HeatwaveCard(
                heatIndexC: heatIndexC,
                tempC: tempC,
                city: 'Karachi',
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRouter.heatwave,
                  arguments: 'Karachi',
                ),
              ),
            ),

          // ── Mosque broadcasts banner (M14) ───────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top +
                (showHeatwave ? 158 : 64),
            left: 16,
            right: 16,
            child: _buildBroadcastBanner(),
          ),

          // ── Bottom incident sheet ────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomSheet(),
          ),

          // ── Report FAB ───────────────────────────────────────
          Positioned(
            bottom: 200,
            right: 16,
            child: _buildReportFab(),
          ),

          // ── SOS FAB ─────────────────────────────────────────
          Positioned(
            bottom: 200,
            left: 16,
            child: _buildSosFab(),
          ),

          // ── Demo Theater FAB (M16) ───────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: _buildDemoFab(),
          ),
        ],
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────

  Widget _buildBottomSheet() {
    final cards = _events.map(_normalizeForCard).toList();

    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: MColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
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
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('Active Incidents', style: MTypography.titleEn(context)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _showIncidentSheet,
                  icon: const Icon(Icons.expand_less, size: 18),
                  label: Text('${cards.length} total'),
                ),
              ],
            ),
          ),
          Expanded(
            child: cards.isEmpty
                ? Center(
                    child: Text(
                      'No active incidents',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: MColors.textSecondary,
                      ),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: cards.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 260,
                          child: IncidentCard(
                            event: cards[index],
                            onTap: () => Navigator.pushNamed(
                              context,
                              AppRouter.situationDetail,
                              arguments: cards[index]['event_id'],
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

  Widget _buildDemoFab() {
    return FloatingActionButton.small(
      heroTag: 'demo_fab',
      onPressed: () => Navigator.pushNamed(context, AppRouter.demoTheater),
      backgroundColor: const Color(0xFF161B22),
      tooltip: 'Demo Theater (M16)',
      child: const Text(
        '🎬',
        style: TextStyle(fontSize: 16),
      ),
    );
  }

  Widget _buildSosFab() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (_pulseController.value * 0.05),
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
    final cards = _events.map(_normalizeForCard).toList();
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
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRouter.safeRoute),
                    child: const Text('Find safe route'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: cards.isEmpty
                  ? const Center(child: Text('No active incidents'))
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: cards.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return IncidentCard(
                          event: cards[index],
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushNamed(
                              context,
                              AppRouter.situationDetail,
                              arguments: cards[index]['event_id'],
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
