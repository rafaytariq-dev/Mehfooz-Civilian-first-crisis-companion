/// Heatwave Service — M11
///
/// Fetches weather data, computes heat index, queries cooling spots,
/// and manages WhatsApp deep links for emergency contact alerts.

import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

class HeatwaveService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ─── Heat Index computation (Rothfusz regression) ───
  // Mirrors the Cloud Function implementation for local display.
  static double computeHeatIndex(double tempC, double humidity) {
    final t = tempC * 9 / 5 + 32; // °C → °F
    final r = humidity;

    // Simple formula
    double hi = 0.5 * (t + 61.0 + ((t - 68.0) * 1.2) + (r * 0.094));

    if (hi >= 80) {
      // Full Rothfusz regression
      hi = -42.379 +
          2.04901523 * t +
          10.14333127 * r -
          0.22475541 * t * r -
          0.00683783 * t * t -
          0.05481717 * r * r +
          0.00122874 * t * t * r +
          0.00085282 * t * r * r -
          0.00000199 * t * t * r * r;

      // Low humidity adjustment
      if (r < 13 && t >= 80 && t <= 112) {
        hi -= ((13 - r) / 4) * sqrt((17 - (t - 95).abs()) / 17);
      }

      // High humidity adjustment
      if (r > 85 && t >= 80 && t <= 87) {
        hi += ((r - 85) / 10) * ((87 - t) / 5);
      }
    }

    return (hi - 32) * 5 / 9; // back to Celsius
  }

  // ─── Danger level for UI display ───
  static String dangerLevel(double heatIndexC) {
    if (heatIndexC < 27) return 'Safe';
    if (heatIndexC < 32) return 'Caution';
    if (heatIndexC < 41) return 'Extreme Caution';
    if (heatIndexC < 54) return 'Danger';
    return 'Extreme Danger';
  }

  static String dangerLevelUr(double heatIndexC) {
    if (heatIndexC < 27) return 'محفوظ';
    if (heatIndexC < 32) return 'احتیاط';
    if (heatIndexC < 41) return 'شدید احتیاط';
    if (heatIndexC < 54) return 'خطرہ';
    return 'انتہائی خطرہ';
  }

  // ─── Fetch current weather from Open-Meteo ───
  Future<HeatWeatherData?> fetchCurrentWeather(String city) async {
    final coords = _cityCoordinates[city];
    if (coords == null) return null;

    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${coords['lat']}'
        '&longitude=${coords['lon']}'
        '&current=temperature_2m,relative_humidity_2m,wind_speed_10m'
        '&timezone=Asia/Karachi',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final current = data['current'];
      if (current == null) return null;

      final tempC = (current['temperature_2m'] as num?)?.toDouble() ?? 0;
      final humidity =
          (current['relative_humidity_2m'] as num?)?.toDouble() ?? 0;
      final windKph =
          (current['wind_speed_10m'] as num?)?.toDouble() ?? 0;
      final heatIndex = computeHeatIndex(tempC, humidity);

      return HeatWeatherData(
        tempC: tempC,
        humidity: humidity,
        windKph: windKph,
        heatIndexC: heatIndex,
        city: city,
        fetchedAt: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  // ─── Find nearest cooling spots from Firestore ───
  Future<List<CoolingSpotData>> getNearestCoolingSpots({
    required double lat,
    required double lng,
    int limit = 3,
  }) async {
    try {
      final snap = await _firestore
          .collection('safe_spots')
          .where('has_cooling', isEqualTo: true)
          .get();

      final spots = <CoolingSpotData>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final loc = data['location'];
        if (loc == null) continue;

        double spotLat, spotLng;
        if (loc is GeoPoint) {
          spotLat = loc.latitude;
          spotLng = loc.longitude;
        } else if (loc is Map) {
          spotLat = (loc['latitude'] as num?)?.toDouble() ?? 0;
          spotLng = (loc['longitude'] as num?)?.toDouble() ?? 0;
        } else {
          continue;
        }

        final distM = _haversineDistance(lat, lng, spotLat, spotLng);

        spots.add(CoolingSpotData(
          spotId: doc.id,
          name: data['name'] ?? 'Unknown',
          type: data['type'] ?? 'other',
          address: data['address'] ?? '',
          latitude: spotLat,
          longitude: spotLng,
          distanceM: distM.round(),
          hasMedical: data['has_medical'] ?? false,
          capacity: data['capacity'] ?? 0,
          open247: data['open_24_7'] ?? false,
        ));
      }

      spots.sort((a, b) => a.distanceM.compareTo(b.distanceM));
      return spots.take(limit).toList();
    } catch (e) {
      return [];
    }
  }

  // ─── Get heatwave warning history ───
  Future<List<Map<String, dynamic>>> getWarningHistory(String userId) async {
    try {
      final snap = await _firestore
          .collection('heatwave_warnings')
          .where('user_id', isEqualTo: userId)
          .orderBy('sent_at', descending: true)
          .limit(10)
          .get();

      return snap.docs.map((d) => d.data()).toList();
    } catch (e) {
      return [];
    }
  }

  // ─── WhatsApp share for emergency contacts ───
  Future<bool> shareHeatWarningWhatsApp({
    required String contactPhone,
    required String contactName,
    required double heatIndex,
    required String city,
    required String userName,
    bool isUrdu = true,
  }) async {
    final hiRounded = heatIndex.round();
    final cleanPhone = contactPhone.replaceAll(RegExp(r'[\s+\-]'), '');

    final message = isUrdu
        ? 'Salaam, $userName $city mein hai aur garmi bohat zyada hai '
            '(heat index ${hiRounded}°C). Please check-in karein.'
        : 'Hello, $userName is in $city and the heat is extreme '
            '(heat index ${hiRounded}°C). Please check on them.';

    final url = Uri.parse(
      'https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}',
    );

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ─── Open Google Maps navigation to cooling spot ───
  Future<bool> navigateToCoolingSpot(CoolingSpotData spot) async {
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${spot.latitude},${spot.longitude}'
      '&travelmode=walking',
    );

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ─── Haversine distance (meters) ───
  static double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0; // Earth's radius in meters
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  static double _toRad(double deg) => deg * pi / 180;

  // ─── City coordinate lookup ───
  static final Map<String, Map<String, double>> _cityCoordinates = {
    'Karachi': {'lat': 24.8607, 'lon': 67.0011},
    'Hyderabad': {'lat': 25.3960, 'lon': 68.3578},
    'Multan': {'lat': 30.1575, 'lon': 71.5249},
    'Jacobabad': {'lat': 28.2769, 'lon': 68.4514},
    'Sukkur': {'lat': 27.7052, 'lon': 68.8574},
    'Islamabad': {'lat': 33.6938, 'lon': 73.0651},
    'Rawalpindi': {'lat': 33.5651, 'lon': 73.0169},
    'Lahore': {'lat': 31.5204, 'lon': 74.3587},
  };
}

// ─── Data classes ───

class HeatWeatherData {
  final double tempC;
  final double humidity;
  final double windKph;
  final double heatIndexC;
  final String city;
  final DateTime fetchedAt;

  HeatWeatherData({
    required this.tempC,
    required this.humidity,
    required this.windKph,
    required this.heatIndexC,
    required this.city,
    required this.fetchedAt,
  });

  /// Walking time estimate to reach a distance in meters (~80m/min)
  int walkingMinutes(int distanceM) => (distanceM / 80).ceil();
}

class CoolingSpotData {
  final String spotId;
  final String name;
  final String type;
  final String address;
  final double latitude;
  final double longitude;
  final int distanceM;
  final bool hasMedical;
  final int capacity;
  final bool open247;

  CoolingSpotData({
    required this.spotId,
    required this.name,
    required this.type,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.distanceM,
    required this.hasMedical,
    required this.capacity,
    required this.open247,
  });

  /// Walking time estimate (~80m/min)
  int get walkingMinutes => (distanceM / 80).ceil();

  /// Type icon for display
  String get typeEmoji {
    switch (type) {
      case 'hospital':
        return '🏥';
      case 'mosque':
        return '🕌';
      case 'mall':
        return '🏬';
      case 'school':
        return '🏫';
      case 'gov_building':
        return '🏛️';
      default:
        return '🏢';
    }
  }
}
