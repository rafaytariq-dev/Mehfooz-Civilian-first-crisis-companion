import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'offline_cache.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  bool isOnline = true;

  void init() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (hasConnection && !isOnline) {
        isOnline = true;
        _flushQueue();
      } else if (!hasConnection) {
        isOnline = false;
      }
    });

    // Check initial status
    Connectivity().checkConnectivity().then((List<ConnectivityResult> results) {
      isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline) {
        _flushQueue();
      }
    });
  }

  Future<void> _flushQueue() async {
    final pending = OfflineCache.getPendingReports();
    if (pending.isEmpty) return;

    for (var report in pending) {
      try {
        await FirebaseFirestore.instance.collection('reports').add({
          'text_raw': report.text,
          'location': GeoPoint(report.lat, report.lon),
          'created_at': report.createdAt,
          '_voice_processed': false,
        });
        await OfflineCache.markReportSynced(report);
      } catch (e) {
        // Ignore errors, will retry on next flush
      }
    }
  }

  Future<bool> checkOnlineStatus() async {
    final results = await Connectivity().checkConnectivity();
    isOnline = results.any((r) => r != ConnectivityResult.none);
    return isOnline;
  }
}
