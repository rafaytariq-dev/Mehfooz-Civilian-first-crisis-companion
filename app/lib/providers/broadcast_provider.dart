/// M14 — Broadcast Providers
///
/// Riverpod glue around BroadcastService. Exposes active broadcasts as
/// a Stream and looks up the current user's mosques (for admins).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/broadcast_service.dart';

final broadcastServiceProvider = Provider<BroadcastService>((ref) {
  return BroadcastService();
});

/// Active (non-expired, delivered) broadcasts across the system.
/// UI filters to those near the user.
final activeBroadcastsProvider = StreamProvider<List<BroadcastDoc>>((ref) {
  final svc = ref.watch(broadcastServiceProvider);
  return svc.activeBroadcastsStream();
});

/// Current Firebase user (null if signed-out).
final currentUidProvider = Provider<String?>((ref) {
  return FirebaseAuth.instance.currentUser?.uid;
});

/// Current user's Firestore doc — used to read `role`, `muted_mosques`,
/// `language`, etc. Returns null while loading or signed-out.
final currentUserDocProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return FirebaseFirestore.instance
      .doc('users/$uid')
      .snapshots()
      .map((s) => s.data());
});

/// True iff current user has role == 'mosque_admin'. Used to gate the
/// composer screen.
final isMosqueAdminProvider = Provider<bool>((ref) {
  final doc = ref.watch(currentUserDocProvider).valueOrNull;
  return doc != null && doc['role'] == 'mosque_admin';
});

/// Mosques the current user can broadcast as. Empty for non-admins.
final myMosquesProvider = FutureProvider<List<MosqueDoc>>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return [];
  final svc = ref.watch(broadcastServiceProvider);
  return svc.mosquesForAdmin(uid);
});

/// Stream of *my* recent broadcasts for the admin dashboard.
final myBroadcastsProvider =
    StreamProvider<List<BroadcastDoc>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  final svc = ref.watch(broadcastServiceProvider);
  return svc.myBroadcastsStream(uid);
});

/// Future of a single mosque by id (with simple per-id caching via family).
final mosqueByIdProvider =
    FutureProvider.family<MosqueDoc?, String>((ref, mosqueId) async {
  final svc = ref.watch(broadcastServiceProvider);
  return svc.mosqueById(mosqueId);
});

/// Currently muted mosques for the signed-in user (from users.muted_mosques).
final mutedMosquesProvider = Provider<Set<String>>((ref) {
  final doc = ref.watch(currentUserDocProvider).valueOrNull;
  if (doc == null) return const {};
  final list = doc['muted_mosques'];
  if (list is List) return list.cast<String>().toSet();
  return const {};
});
