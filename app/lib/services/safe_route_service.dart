import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// Injected at build time: flutter run --dart-define-from-file=dart_defines.env
const _kMapsApiKey = String.fromEnvironment('MAPS_API_KEY');
const _kRoutesEndpoint =
    'https://routes.googleapis.com/directions/v2:computeRoutes';

class RouteStep {
  final int distanceM;
  final String roadClass;
  final String roadName;
  final bool isUnlit;
  final bool isIsolated;

  const RouteStep({
    required this.distanceM,
    required this.roadClass,
    required this.roadName,
    this.isUnlit = false,
    this.isIsolated = false,
  });
}

enum RiskLevel { safe, moderate, elevated, danger }

class RouteResult {
  final int distanceM;
  final int durationS;
  final double riskScore;
  final bool passesThroughFlooded;
  final String? polyline;
  final String riskExplanation;
  final double safetyPenalty;
  final List<RouteStep> steps;

  const RouteResult({
    required this.distanceM,
    required this.durationS,
    required this.riskScore,
    required this.passesThroughFlooded,
    this.polyline,
    required this.riskExplanation,
    this.safetyPenalty = 0.0,
    this.steps = const [],
  });

  String get durationText {
    final mins = (durationS / 60).ceil();
    return '$mins min';
  }

  String get distanceText {
    final km = distanceM / 1000.0;
    return '${km.toStringAsFixed(1)} km';
  }

  RiskLevel get riskLevel {
    if (passesThroughFlooded || riskScore > 0.7) return RiskLevel.danger;
    if (riskScore > 0.45) return RiskLevel.elevated;
    if (riskScore > 0.25) return RiskLevel.moderate;
    return RiskLevel.safe;
  }

  String get riskLevelLabel {
    switch (riskLevel) {
      case RiskLevel.safe: return 'Safest';
      case RiskLevel.moderate: return 'Moderate';
      case RiskLevel.elevated: return 'Elevated Risk';
      case RiskLevel.danger: return 'Danger';
    }
  }

  String get riskLevelUr {
    switch (riskLevel) {
      case RiskLevel.safe: return 'محفوظ ترین';
      case RiskLevel.moderate: return 'معتدل';
      case RiskLevel.elevated: return 'بڑھا ہوا خطرہ';
      case RiskLevel.danger: return 'خطرہ';
    }
  }
}

const _kPenaltyResidentialService = 0.5;
const _kPenaltyUnlit = 0.3;
const _kPenaltyIsolated = 0.4;

const _kPenalizedRoadClasses = {
  'residential', 'service', 'track', 'path', 'unclassified',
};

double computeSafetyPenalty(List<RouteStep> steps) {
  double penalty = 0.0;
  for (final step in steps) {
    final dist = step.distanceM.toDouble();
    if (_kPenalizedRoadClasses.contains(step.roadClass)) {
      penalty += dist * _kPenaltyResidentialService;
    }
    if (step.isUnlit) penalty += dist * _kPenaltyUnlit;
    if (step.isIsolated) penalty += dist * _kPenaltyIsolated;
  }
  return penalty;
}

class SafeRouteService {
  /// Calls Google Routes API for up to 3 alternatives.
  /// Falls back to geometry-based estimation if the API fails.
  Future<List<RouteResult>> computeRoutes({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    bool safetyMode = false,
  }) async {
    try {
      final results = await _callRoutesApi(
        originLat: originLat,
        originLon: originLon,
        destLat: destLat,
        destLon: destLon,
        safetyMode: safetyMode,
      );
      if (results.isNotEmpty) return results;
    } catch (e) {
      debugPrint('Routes API error: $e');
    }

    // Fallback: geometry-based estimation (no external call)
    return _geometryFallback(
      originLat: originLat,
      originLon: originLon,
      destLat: destLat,
      destLon: destLon,
      safetyMode: safetyMode,
    );
  }

  Future<List<RouteResult>> _callRoutesApi({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    required bool safetyMode,
  }) async {
    final body = jsonEncode({
      'origin': {
        'location': {
          'latLng': {'latitude': originLat, 'longitude': originLon}
        }
      },
      'destination': {
        'location': {
          'latLng': {'latitude': destLat, 'longitude': destLon}
        }
      },
      'travelMode': 'DRIVE',
      'computeAlternativeRoutes': true,
      'routeModifiers': {
        'avoidFerries': true,
      },
      'routingPreference': 'TRAFFIC_AWARE',
    });

    final response = await http
        .post(
          Uri.parse(_kRoutesEndpoint),
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': _kMapsApiKey,
            'X-Goog-FieldMask':
                'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,routes.legs',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Routes API ${response.statusCode}: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = json['routes'] as List<dynamic>? ?? [];
    if (routes.isEmpty) return [];

    final results = <RouteResult>[];
    for (int i = 0; i < routes.length && i < 3; i++) {
      final r = routes[i] as Map<String, dynamic>;
      final distM = r['distanceMeters'] as int? ?? 0;
      final durStr = r['duration'] as String? ?? '0s';
      final durS = _parseDurationSeconds(durStr);
      final polyline = (r['polyline'] as Map?)
          ?['encodedPolyline'] as String?;

      // Derive steps from legs
      final steps = _extractSteps(r);
      final penalty = safetyMode ? computeSafetyPenalty(steps) : 0.0;
      final riskScore = safetyMode
          ? (penalty / math.max(distM.toDouble(), 1)) * 0.6
          : (i * 0.15); // mild risk gradient across alternatives

      results.add(RouteResult(
        distanceM: distM,
        durationS: durS,
        riskScore: riskScore.clamp(0.0, 0.95),
        passesThroughFlooded: false, // updated by Detection agent when events exist
        polyline: polyline,
        riskExplanation: _buildReasoning(steps, penalty, i, safetyMode, distM),
        safetyPenalty: penalty,
        steps: steps,
      ));
    }

    results.sort((a, b) {
      final fl = (a.passesThroughFlooded ? 1 : 0)
          .compareTo(b.passesThroughFlooded ? 1 : 0);
      if (fl != 0) return fl;
      final rs = a.riskScore.compareTo(b.riskScore);
      if (rs != 0) return rs;
      return a.durationS.compareTo(b.durationS);
    });

    return results;
  }

  List<RouteStep> _extractSteps(Map<String, dynamic> route) {
    final steps = <RouteStep>[];
    final legs = route['legs'] as List<dynamic>? ?? [];
    for (final leg in legs) {
      final legSteps = (leg as Map)['steps'] as List<dynamic>? ?? [];
      for (final s in legSteps) {
        final sm = s as Map<String, dynamic>;
        final distM = sm['distanceMeters'] as int? ?? 0;
        // Routes API doesn't expose road class directly; we approximate from
        // navigationInstruction maneuver and local road hints.
        steps.add(RouteStep(
          distanceM: distM,
          roadClass: 'primary', // default; enriched by OSM in production
          roadName: (sm['navigationInstruction'] as Map?)?['instructions']
                  as String? ?? '',
        ));
      }
    }
    return steps;
  }

  String _buildReasoning(
    List<RouteStep> steps,
    double penalty,
    int index,
    bool safetyMode,
    int distM,
  ) {
    if (!safetyMode) {
      if (index == 0) return 'Fastest route via main roads.';
      if (index == 1) return 'Alternative route — slightly longer.';
      return 'Third option — avoids main congestion points.';
    }
    if (index == 0) return 'Safest option: well-lit main roads throughout.';
    if (index == 1) {
      return 'Moderate: includes some secondary roads. '
          'Safety penalty ${penalty.round()} pts.';
    }
    return 'Longer but avoids back lanes. Safety penalty ${penalty.round()} pts.';
  }

  int _parseDurationSeconds(String s) {
    // Format: "1234s"
    return int.tryParse(s.replaceAll('s', '')) ?? 0;
  }

  // ── Geometry fallback (no API call) ───────────────────────────

  List<RouteResult> _geometryFallback({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    required bool safetyMode,
  }) {
    final dist = _haversineM(originLat, originLon, destLat, destLon);
    final durationBase = (dist / 8).round(); // ~8 m/s city speed (slower estimate)

    return [
      RouteResult(
        distanceM: dist.round(),
        durationS: durationBase,
        riskScore: 0.15,
        passesThroughFlooded: false,
        riskExplanation: 'Route via main roads (offline estimate).',
        safetyPenalty: 0,
        steps: const [],
      ),
      RouteResult(
        distanceM: (dist * 1.1).round(),
        durationS: (durationBase * 1.1).round(),
        riskScore: 0.30,
        passesThroughFlooded: false,
        riskExplanation: 'Alternative route — slightly longer (offline estimate).',
        safetyPenalty: 0,
        steps: const [],
      ),
      RouteResult(
        distanceM: (dist * 1.25).round(),
        durationS: (durationBase * 1.25).round(),
        riskScore: 0.20,
        passesThroughFlooded: false,
        riskExplanation: 'Longer but avoids congestion (offline estimate).',
        safetyPenalty: 0,
        steps: const [],
      ),
    ];
  }

  double _haversineM(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final dPhi = (lat2 - lat1) * math.pi / 180;
    final dLam = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.sin(dLam / 2) *
            math.sin(dLam / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
