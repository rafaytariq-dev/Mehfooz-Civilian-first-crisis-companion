/// M12 — Women's Safe Route Screen.
///
/// Full M12 implementation with:
/// - Origin/destination input
/// - Women's safe route toggle (explicit description per spec)
/// - Route results with explicit safety reasoning text
/// - Safety penalty breakdown chips per route
/// - Visually distinct routes for toggle ON vs OFF

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../services/safe_route_service.dart';

class SafeRouteScreen extends StatefulWidget {
  const SafeRouteScreen({super.key});

  @override
  State<SafeRouteScreen> createState() => _SafeRouteScreenState();
}

class _SafeRouteScreenState extends State<SafeRouteScreen>
    with SingleTickerProviderStateMixin {
  bool _womenSafeMode = false;
  bool _loading = false;
  List<RouteResult> _routes = [];
  bool _routesFound = false;

  final _originCtrl = TextEditingController(text: 'Current location');
  final _destCtrl = TextEditingController();
  final _service = SafeRouteService();

  // Demo origin/destination (Islamabad G-10 → F-7)
  static const _demoOriginLat = 33.6920;
  static const _demoOriginLon = 73.0130;
  static const _demoDestLat   = 33.7295;
  static const _demoDestLon   = 73.0372;

  @override
  void dispose() {
    _originCtrl.dispose();
    _destCtrl.dispose();
    super.dispose();
  }

  Future<void> _findRoutes() async {
    if (_destCtrl.text.isEmpty) {
      _destCtrl.text = 'Faisal Mosque, Islamabad';
    }
    setState(() {
      _loading = true;
      _routes = [];
      _routesFound = false;
    });

    final routes = await _service.computeRoutes(
      originLat: _demoOriginLat,
      originLon: _demoOriginLon,
      destLat: _demoDestLat,
      destLon: _demoDestLon,
      safetyMode: _womenSafeMode,
    );

    if (mounted) {
      setState(() {
        _loading = false;
        _routes = routes;
        _routesFound = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MColors.background,
      appBar: AppBar(
        backgroundColor: MColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Safe Route',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          if (_routesFound)
            TextButton(
              onPressed: () => setState(() {
                _routes = [];
                _routesFound = false;
                _destCtrl.clear();
              }),
              child: Text('Reset', style: GoogleFonts.inter(color: MColors.red)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInputCard(),
            const SizedBox(height: 16),
            _buildSafeModeToggle(),
            const SizedBox(height: 20),
            _buildFindButton(),
            if (_routesFound) ...[
              const SizedBox(height: 28),
              _buildResultsHeader(),
              const SizedBox(height: 12),
              ..._routes.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RouteCard(
                    route: e.value,
                    rank: e.key,
                    safetyMode: _womenSafeMode,
                    originLat: _demoOriginLat,
                    originLon: _demoOriginLon,
                    destLat: _demoDestLat,
                    destLon: _demoDestLon,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: _originCtrl,
            style: GoogleFonts.inter(fontSize: 14),
            decoration: InputDecoration(
              labelText: 'From',
              labelStyle: GoogleFonts.inter(fontSize: 12, color: MColors.textSecondary),
              prefixIcon: const Icon(Icons.my_location, color: MColors.green, size: 20),
              suffixIcon: IconButton(
                icon: const Icon(Icons.gps_fixed, size: 18),
                color: MColors.textSecondary,
                onPressed: () {},
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
          Divider(color: MColors.textSecondary.withValues(alpha: 0.15), height: 1),
          const SizedBox(height: 4),
          TextField(
            controller: _destCtrl,
            style: GoogleFonts.inter(fontSize: 14),
            decoration: InputDecoration(
              labelText: 'To',
              hintText: 'Search destination…',
              labelStyle: GoogleFonts.inter(fontSize: 12, color: MColors.textSecondary),
              hintStyle: GoogleFonts.inter(fontSize: 14, color: MColors.textSecondary.withValues(alpha: 0.5)),
              prefixIcon: const Icon(Icons.location_on, color: MColors.red, size: 20),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafeModeToggle() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _womenSafeMode
            ? const Color(0xFF7B61FF).withValues(alpha: 0.07)
            : MColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _womenSafeMode
              ? const Color(0xFF7B61FF).withValues(alpha: 0.35)
              : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _womenSafeMode
                  ? const Color(0xFF7B61FF).withValues(alpha: 0.15)
                  : MColors.textSecondary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                '🛡️',
                style: TextStyle(fontSize: _womenSafeMode ? 22 : 20),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Women's safe route mode",
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _womenSafeMode
                        ? const Color(0xFF7B61FF)
                        : MColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Longer, safer — prefers well-lit main roads',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: MColors.textSecondary,
                  ),
                ),
                if (_womenSafeMode) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Avoids back lanes, unlit roads & isolated areas',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: const Color(0xFF7B61FF).withValues(alpha: 0.8),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: _womenSafeMode,
            activeColor: const Color(0xFF7B61FF),
            onChanged: (v) {
              setState(() => _womenSafeMode = v);
              if (_routesFound) _findRoutes();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFindButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _womenSafeMode
              ? const Color(0xFF7B61FF)
              : MColors.green,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        onPressed: _loading ? null : _findRoutes,
        icon: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.route, size: 20),
        label: Text(
          _loading
              ? 'Calculating routes…'
              : _womenSafeMode
                  ? 'Find Safe Routes'
                  : 'Find Routes',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildResultsHeader() {
    return Row(
      children: [
        Text(
          '${_routes.length} routes found',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: MColors.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        if (_womenSafeMode)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF7B61FF).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Safe Mode ON',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF7B61FF),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Route Card Widget ───

class _RouteCard extends StatelessWidget {
  final RouteResult route;
  final int rank;
  final bool safetyMode;
  final double originLat;
  final double originLon;
  final double destLat;
  final double destLon;

  const _RouteCard({
    required this.route,
    required this.rank,
    required this.safetyMode,
    required this.originLat,
    required this.originLon,
    required this.destLat,
    required this.destLon,
  });

  Color get _badgeColor {
    switch (route.riskLevel) {
      case RiskLevel.safe:
        return MColors.green;
      case RiskLevel.moderate:
        return MColors.amber;
      case RiskLevel.elevated:
        return const Color(0xFFFF7043);
      case RiskLevel.danger:
        return MColors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: MColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: rank == 0
                ? Border.all(color: _badgeColor.withValues(alpha: 0.3), width: 1.5)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: rank == 0 ? 0.06 : 0.03),
                blurRadius: rank == 0 ? 16 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopRow(),
              const SizedBox(height: 10),
              _buildStats(),
              const SizedBox(height: 12),
              _buildReasoning(),
              if (safetyMode && route.safetyPenalty > 0) ...[
                const SizedBox(height: 10),
                _buildSafetyChips(),
              ],
              const SizedBox(height: 12),
              _buildStepsRow(),
              const SizedBox(height: 14),
              _buildNavigateButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopRow() {
    return Row(
      children: [
        // Rank badge
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _badgeColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '${rank + 1}',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _badgeColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _badgeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            route.riskLevelLabel,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _badgeColor,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '· ${route.riskLevelUr}',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: MColors.textSecondary,
          ),
        ),
        const Spacer(),
        if (route.passesThroughFlooded) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: MColors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.water, size: 12, color: MColors.red),
                const SizedBox(width: 3),
                Text(
                  'Flood risk',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: MColors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(width: 4),
        const Icon(Icons.open_in_new, size: 16, color: MColors.textSecondary),
      ],
    );
  }

  Widget _buildStats() {
    return Row(
      children: [
        _statChip(Icons.timer_outlined, route.durationText, MColors.textPrimary),
        const SizedBox(width: 12),
        _statChip(Icons.straighten, route.distanceText, MColors.textPrimary),
        if (safetyMode && route.safetyPenalty > 0) ...[
          const SizedBox(width: 12),
          _statChip(
            Icons.shield_outlined,
            'Penalty: ${route.safetyPenalty.round()}',
            route.safetyPenalty < 200
                ? MColors.green
                : route.safetyPenalty < 600
                    ? MColors.amber
                    : MColors.red,
          ),
        ],
      ],
    );
  }

  Widget _statChip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: MColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildReasoning() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _badgeColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _badgeColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            safetyMode ? Icons.info_outline : Icons.route,
            size: 15,
            color: _badgeColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              route.riskExplanation,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: MColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyChips() {
    final hasBack = route.steps.any(
        (s) => {'residential', 'service', 'track'}.contains(s.roadClass));
    final hasUnlit = route.steps.any((s) => s.isUnlit);
    final hasIsolated = route.steps.any((s) => s.isIsolated);

    final chips = <Widget>[];
    if (!hasBack && !hasUnlit && !hasIsolated) {
      chips.add(_safetyChip('Main roads only', const Color(0xFF7B61FF), Icons.check));
    }
    if (hasBack) chips.add(_safetyChip('Back lanes', MColors.amber, Icons.warning_amber));
    if (hasUnlit) chips.add(_safetyChip('Poorly lit', MColors.amber, Icons.nightlight));
    if (hasIsolated) chips.add(_safetyChip('Isolated area', MColors.red, Icons.dangerous_outlined));

    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }

  Widget _safetyChip(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepsRow() {
    // Show road names as breadcrumb
    final names = route.steps
        .map((s) => s.roadName)
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: names.asMap().entries.map((e) {
          final step = route.steps[e.key];
          final isRisky = {'residential', 'service', 'track'}.contains(step.roadClass)
              || step.isUnlit
              || step.isIsolated;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (e.key > 0)
                Icon(Icons.chevron_right, size: 14, color: MColors.textSecondary),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isRisky
                      ? MColors.amber.withValues(alpha: 0.1)
                      : MColors.green.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  e.value,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: isRisky ? MColors.amber : MColors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildNavigateButton() {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: _badgeColor,
          side: BorderSide(color: _badgeColor.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () {
          final uri = Uri.parse(
            'https://www.google.com/maps/dir/?api=1'
            '&origin=$originLat,$originLon'
            '&destination=$destLat,$destLon'
            '&travelmode=driving',
          );
          launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        icon: const Icon(Icons.navigation_outlined, size: 16),
        label: Text(
          'Navigate via Google Maps',
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
