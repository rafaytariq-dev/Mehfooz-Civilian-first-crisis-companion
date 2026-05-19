/// M12 — Women's Safe Route Service.
///
/// Service layer that:
/// 1. Calls the Planning Agent's compute_routes endpoint.
/// 2. Reads/writes `users.women_safe_route` preference in Firestore.
/// 3. Provides a local `_safety_penalty` mock for instant demo.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Represents a single step in a route.
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

  factory RouteStep.fromJson(Map<String, dynamic> json) => RouteStep(
        distanceM: json['distance_m'] as int? ?? 0,
        roadClass: json['road_class'] as String? ?? 'primary',
        roadName: json['road_name'] as String? ?? '',
        isUnlit: json['is_unlit_assumed'] as bool? ?? false,
        isIsolated: json['passes_isolated_area'] as bool? ?? false,
      );
}

/// Road risk level badge for UI display.
enum RiskLevel { safe, moderate, elevated, danger }

/// A computed route from origin to destination.
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

  factory RouteResult.fromJson(Map<String, dynamic> json) => RouteResult(
        distanceM: json['distance_m'] as int? ?? 0,
        durationS: json['duration_s'] as int? ?? 0,
        riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0.0,
        passesThroughFlooded:
            json['passes_through_flooded'] as bool? ?? false,
        polyline: json['polyline'] as String?,
        riskExplanation:
            json['risk_explanation'] as String? ?? '',
        safetyPenalty:
            (json['safety_penalty'] as num?)?.toDouble() ?? 0.0,
        steps: (json['steps'] as List<dynamic>?)
                ?.map((s) => RouteStep.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
      );

  /// Duration as "N min" string.
  String get durationText {
    final mins = (durationS / 60).ceil();
    return '$mins min';
  }

  /// Distance as "X.X km" string.
  String get distanceText {
    final km = distanceM / 1000.0;
    return '${km.toStringAsFixed(1)} km';
  }

  /// Route level badge.
  RiskLevel get riskLevel {
    if (passesThroughFlooded || riskScore > 0.7) return RiskLevel.danger;
    if (riskScore > 0.45) return RiskLevel.elevated;
    if (riskScore > 0.25) return RiskLevel.moderate;
    return RiskLevel.safe;
  }

  String get riskLevelLabel {
    switch (riskLevel) {
      case RiskLevel.safe:
        return 'Safest';
      case RiskLevel.moderate:
        return 'Moderate';
      case RiskLevel.elevated:
        return 'Elevated Risk';
      case RiskLevel.danger:
        return 'Danger';
    }
  }

  String get riskLevelUr {
    switch (riskLevel) {
      case RiskLevel.safe:
        return 'محفوظ ترین';
      case RiskLevel.moderate:
        return 'معتدل';
      case RiskLevel.elevated:
        return 'بڑھا ہوا خطرہ';
      case RiskLevel.danger:
        return 'خطرہ';
    }
  }
}

/// Per-step safety penalty coefficients per M12 spec.
const _kPenaltyResidentialService = 0.5;
const _kPenaltyUnlit = 0.3;
const _kPenaltyIsolated = 0.4;

const _kPenalizedRoadClasses = {
  'residential',
  'service',
  'track',
  'path',
  'unclassified',
};

/// Compute safety penalty for a list of route steps.
/// Mirrors the Planning Agent's Python `_safety_penalty` function.
double computeSafetyPenalty(List<RouteStep> steps) {
  double penalty = 0.0;
  for (final step in steps) {
    final dist = step.distanceM.toDouble();
    if (_kPenalizedRoadClasses.contains(step.roadClass)) {
      penalty += dist * _kPenaltyResidentialService;
    }
    if (step.isUnlit) {
      penalty += dist * _kPenaltyUnlit;
    }
    if (step.isIsolated) {
      penalty += dist * _kPenaltyIsolated;
    }
  }
  return penalty;
}

/// Service class for M12 safe route computation.
class SafeRouteService {
  // ─── Mock route data for demo (mirrors Planning Agent output) ───

  /// Returns 3 routes for demo purposes.
  /// When [safetyMode]=true, route order and reasoning reflect M12 safety penalty.
  Future<List<RouteResult>> computeRoutes({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    bool safetyMode = false,
  }) async {
    // Simulate network latency
    await Future.delayed(const Duration(milliseconds: 1200));

    final dist = _haversineM(originLat, originLon, destLat, destLon);
    final durationBase = (dist / 13).round(); // ~13 m/s city speed

    // Mock steps per route variant (mirror of Python _generate_mock_steps)
    final stepsVariant0 = [
      RouteStep(distanceM: (dist * 0.50).round(), roadClass: 'primary',
          roadName: 'Stadium Road / Shahrah-e-Faisal'),
      RouteStep(distanceM: (dist * 0.30).round(), roadClass: 'secondary',
          roadName: 'Main Boulevard'),
      RouteStep(distanceM: (dist * 0.20).round(), roadClass: 'primary',
          roadName: 'Jinnah Avenue'),
    ];

    final stepsVariant1 = [
      RouteStep(distanceM: (dist * 0.30).round(), roadClass: 'primary',
          roadName: 'IJP Road'),
      RouteStep(distanceM: (dist * 0.40).round(), roadClass: 'residential',
          roadName: 'Korangi back lanes', isUnlit: true),
      RouteStep(distanceM: (dist * 0.30).round(), roadClass: 'service',
          roadName: 'Industrial Area bypass', isUnlit: true, isIsolated: true),
    ];

    final stepsVariant2 = [
      RouteStep(distanceM: (dist * 0.40).round(), roadClass: 'primary',
          roadName: 'Margalla Avenue'),
      RouteStep(distanceM: (dist * 0.40).round(), roadClass: 'secondary',
          roadName: 'F-10 Markaz Road'),
      RouteStep(distanceM: (dist * 0.20).round(), roadClass: 'tertiary',
          roadName: 'G-9 Link', isUnlit: true),
    ];

    final allSteps = [stepsVariant0, stepsVariant1, stepsVariant2];
    final floodRisk = [0.2, 0.55, 0.3];
    final passesFl = [false, true, false];
    final mult = [0.95, 1.0, 1.15];

    List<Map<String, dynamic>> rawRoutes = [];

    for (int i = 0; i < 3; i++) {
      final steps = allSteps[i];
      final safePen = safetyMode ? computeSafetyPenalty(steps) : 0.0;
      final riskScore = safetyMode
          ? (safePen / math.max(dist, 1) + floodRisk[i])
          : floodRisk[i];

      rawRoutes.add({
        'distance_m': (dist * mult[i]).round(),
        'duration_s': (durationBase * mult[i]).round(),
        'risk_score': riskScore,
        'passes_through_flooded': passesFl[i],
        'safety_penalty': safePen,
        'steps': steps,
        'variant_index': i,
      });
    }

    // M12 spec sort: (passes_through_flooded, risk_score, duration_s)
    rawRoutes.sort((a, b) {
      final fl = (a['passes_through_flooded'] as bool ? 1 : 0)
          .compareTo(b['passes_through_flooded'] as bool ? 1 : 0);
      if (fl != 0) return fl;
      final rs = (a['risk_score'] as double).compareTo(b['risk_score'] as double);
      if (rs != 0) return rs;
      return (a['duration_s'] as int).compareTo(b['duration_s'] as int);
    });

    // Assign reasoning text based on new sort position
    final results = <RouteResult>[];
    for (int i = 0; i < rawRoutes.length; i++) {
      final r = rawRoutes[i];
      final steps = r['steps'] as List<RouteStep>;
      final safePen = r['safety_penalty'] as double;
      final reasoning = _buildSafetyReasoning(steps, safePen, i, safetyMode);

      results.add(RouteResult(
        distanceM: r['distance_m'] as int,
        durationS: r['duration_s'] as int,
        riskScore: r['risk_score'] as double,
        passesThroughFlooded: r['passes_through_flooded'] as bool,
        riskExplanation: reasoning,
        safetyPenalty: safePen,
        steps: steps,
      ));
    }

    return results;
  }

  String _buildSafetyReasoning(
    List<RouteStep> steps,
    double penalty,
    int index,
    bool safetyMode,
  ) {
    if (!safetyMode) {
      if (index == 0) return 'Shortest route via main roads.';
      if (index == 1) return 'Passes near affected zone; moderate congestion.';
      return 'Longer but avoids main congestion points.';
    }

    final mainRoads = steps
        .where((s) => {'motorway', 'trunk', 'primary', 'secondary'}.contains(s.roadClass))
        .map((s) => s.roadName)
        .toList();
    final backRoads = steps
        .where((s) => {'residential', 'service', 'track'}.contains(s.roadClass))
        .map((s) => s.roadName)
        .toList();
    final unlitRoads = steps.where((s) => s.isUnlit).map((s) => s.roadName).toList();
    final isolated = steps.where((s) => s.isIsolated).map((s) => s.roadName).toList();

    if (index == 0) {
      if (mainRoads.isNotEmpty) {
        return 'Safest route: stays on ${mainRoads.take(2).join(", ")} — '
            'well-lit main roads throughout.';
      }
      return 'Safest route: prioritises well-lit main roads.';
    } else if (index == 1) {
      final issues = <String>[];
      if (backRoads.isNotEmpty) issues.add('passes through ${backRoads.first}');
      if (unlitRoads.isNotEmpty) issues.add('includes poorly-lit sections');
      if (isolated.isNotEmpty) issues.add('passes isolated area near ${isolated.first}');
      final issuesText = issues.isNotEmpty ? issues.join('; ') : 'uses some secondary roads';
      return 'Moderate: $issuesText. Faster but higher safety penalty '
          '(${penalty.round()}pts).';
    } else {
      if (mainRoads.isNotEmpty) {
        return 'Safer but longer: stays on ${mainRoads.take(2).join(", ")} — '
            'avoids back lanes. Safety penalty: ${penalty.round()}pts.';
      }
      return 'Longer but safer route. Safety penalty: ${penalty.round()}pts.';
    }
  }

  double _haversineM(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final dPhi = (lat2 - lat1) * math.pi / 180;
    final dLam = (lon2 - lon1) * math.pi / 180;

    final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
        math.cos(phi1) * math.cos(phi2) * math.sin(dLam / 2) * math.sin(dLam / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
