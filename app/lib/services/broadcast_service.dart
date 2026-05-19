/// M14 — Mosque Broadcast Service
///
/// Handles the citizen-side view of mosque broadcasts (verified community
/// broadcaster tier), and the admin-side composer flow.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BroadcastService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Active broadcasts (status == 'delivered', expires_at > now).
  /// Used by HomeScreen and SituationDetail to surface mosque-tier alerts.
  Stream<List<BroadcastDoc>> activeBroadcastsStream() {
    return _firestore
        .collection('broadcasts')
        .where('status', isEqualTo: 'delivered')
        .where('expires_at', isGreaterThan: Timestamp.now())
        .orderBy('expires_at')
        .snapshots()
        .map((s) => s.docs.map(BroadcastDoc.fromSnap).toList());
  }

  /// Broadcasts posted by a given admin (used by admin's "My broadcasts" tab).
  Stream<List<BroadcastDoc>> myBroadcastsStream(String adminUid) {
    return _firestore
        .collection('broadcasts')
        .where('admin_uid', isEqualTo: adminUid)
        .orderBy('created_at', descending: true)
        .limit(20)
        .snapshots()
        .map((s) => s.docs.map(BroadcastDoc.fromSnap).toList());
  }

  /// All mosques the given user is admin of. Used to choose which mosque
  /// to broadcast as.
  Future<List<MosqueDoc>> mosquesForAdmin(String uid) async {
    final snap = await _firestore
        .collection('mosques')
        .where('admin_uids', arrayContains: uid)
        .get();
    return snap.docs.map(MosqueDoc.fromSnap).toList();
  }

  /// Fetch one mosque by id (used to render broadcast cards with the
  /// originating mosque name + location).
  Future<MosqueDoc?> mosqueById(String mosqueId) async {
    final snap = await _firestore.doc('mosques/$mosqueId').get();
    if (!snap.exists) return null;
    return MosqueDoc.fromSnap(snap);
  }

  /// Calls the `createBroadcast` Cloud Function (callable). The function
  /// enforces admin role, crisis-type whitelist, length cap, and rate-limit.
  Future<String> createBroadcast({
    required String mosqueId,
    required String crisisType,
    required String textUr,
    required String textEn,
    int severity = 1,
  }) async {
    final callable = _functions.httpsCallable('createBroadcast');
    final result = await callable.call(<String, dynamic>{
      'mosque_id': mosqueId,
      'crisis_type': crisisType,
      'text_ur': textUr,
      'text_en': textEn,
      'severity': severity,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['broadcast_id'] as String;
  }

  /// Flag a broadcast as inappropriate. 3+ flags auto-pull it.
  /// Doc id pattern `{broadcastId}_{uid}` — Firestore rule enforces this.
  Future<bool> flagBroadcast(String broadcastId, {String reason = 'spam'}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final docId = '${broadcastId}_$uid';
    try {
      await _firestore.collection('broadcast_flags').doc(docId).set({
        'broadcast_id': broadcastId,
        'user_id': uid,
        'reason': reason,
        'created_at': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Mute / unmute a mosque on the current user's profile.
  /// Stored as an array of mosque_ids on users/{uid}.muted_mosques.
  Future<void> setMuted(String mosqueId, bool muted) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final ref = _firestore.doc('users/$uid');
    await ref.update({
      'muted_mosques': muted
          ? FieldValue.arrayUnion([mosqueId])
          : FieldValue.arrayRemove([mosqueId]),
    });
  }
}

class BroadcastDoc {
  final String id;
  final String mosqueId;
  final String adminUid;
  final String crisisType;
  final String textUr;
  final String textEn;
  final int severity;
  final int radiusM;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final String status;
  final int deliveredCount;
  final int flagCount;

  BroadcastDoc({
    required this.id,
    required this.mosqueId,
    required this.adminUid,
    required this.crisisType,
    required this.textUr,
    required this.textEn,
    required this.severity,
    required this.radiusM,
    required this.createdAt,
    required this.expiresAt,
    required this.status,
    required this.deliveredCount,
    required this.flagCount,
  });

  static BroadcastDoc fromSnap(DocumentSnapshot snap) {
    final d = snap.data() as Map<String, dynamic>;
    return BroadcastDoc(
      id: snap.id,
      mosqueId: d['mosque_id'] ?? '',
      adminUid: d['admin_uid'] ?? '',
      crisisType: d['crisis_type'] ?? 'general_safety',
      textUr: d['text_ur'] ?? '',
      textEn: d['text_en'] ?? '',
      severity: (d['severity'] as num?)?.toInt() ?? 1,
      radiusM: (d['radius_m'] as num?)?.toInt() ?? 3000,
      createdAt: (d['created_at'] as Timestamp?)?.toDate(),
      expiresAt: (d['expires_at'] as Timestamp?)?.toDate(),
      status: d['status'] ?? 'pending',
      deliveredCount: (d['delivered_count'] as num?)?.toInt() ?? 0,
      flagCount: (d['flag_count'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  Duration get remaining =>
      expiresAt == null ? Duration.zero : expiresAt!.difference(DateTime.now());
}

class MosqueDoc {
  final String id;
  final String name;
  final String? nameUr;
  final String city;
  final double latitude;
  final double longitude;
  final List<String> adminUids;

  MosqueDoc({
    required this.id,
    required this.name,
    required this.nameUr,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.adminUids,
  });

  static MosqueDoc fromSnap(DocumentSnapshot snap) {
    final d = snap.data() as Map<String, dynamic>;
    final loc = d['location'];
    double lat = 0, lon = 0;
    if (loc is GeoPoint) {
      lat = loc.latitude;
      lon = loc.longitude;
    } else if (loc is Map) {
      lat = (loc['latitude'] as num?)?.toDouble() ?? 0;
      lon = (loc['longitude'] as num?)?.toDouble() ?? 0;
    }
    return MosqueDoc(
      id: snap.id,
      name: d['name'] ?? 'Unknown Mosque',
      nameUr: d['name_ur'],
      city: d['city'] ?? '',
      latitude: lat,
      longitude: lon,
      adminUids: List<String>.from(d['admin_uids'] ?? const []),
    );
  }
}

/// Allowed crisis types — must match the server-side whitelist in
/// functions/src/mosque_broadcast.ts.
const kAllowedCrisisTypes = <String>[
  'flood',
  'urban_flood',
  'flash_flood',
  'heatwave',
  'road_incident',
  'fire',
  'building_collapse',
  'power_outage',
  'shelter',
  'general_safety',
];

String crisisTypeLabel(String type) {
  switch (type) {
    case 'flood':
    case 'urban_flood':
    case 'flash_flood':
      return 'Flood';
    case 'heatwave':
      return 'Heatwave';
    case 'road_incident':
      return 'Road incident';
    case 'fire':
      return 'Fire';
    case 'building_collapse':
      return 'Building collapse';
    case 'power_outage':
      return 'Power outage';
    case 'shelter':
      return 'Shelter open';
    case 'general_safety':
      return 'General safety';
    default:
      return type;
  }
}

String crisisTypeEmoji(String type) {
  switch (type) {
    case 'flood':
    case 'urban_flood':
    case 'flash_flood':
      return '🌊';
    case 'heatwave':
      return '🌡️';
    case 'road_incident':
      return '🚧';
    case 'fire':
      return '🔥';
    case 'building_collapse':
      return '🏚️';
    case 'power_outage':
      return '⚡';
    case 'shelter':
      return '🏠';
    case 'general_safety':
    default:
      return '📢';
  }
}
