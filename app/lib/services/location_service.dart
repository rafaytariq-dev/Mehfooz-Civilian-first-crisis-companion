import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';

class LocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<Position>? _positionStream;

  /// Start tracking user location and updating Firestore with geohash.
  /// Required for M9 Underpass Radar geo-queries.
  Future<void> startTracking(String userId) async {
    // Ensure permissions
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    // Track position changes (distance filter 100m to save battery)
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 100, 
      ),
    ).listen((Position pos) async {
      final geoFirePoint = GeoFirePoint(GeoPoint(pos.latitude, pos.longitude));
      
      try {
        await _firestore.collection('users').doc(userId).set({
          'last_known_location': geoFirePoint.geoPoint,
          'geohash': geoFirePoint.geohash,
          'last_location_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        // Handle error silently or log
      }
    });
  }

  void stopTracking() {
    _positionStream?.cancel();
  }
}
