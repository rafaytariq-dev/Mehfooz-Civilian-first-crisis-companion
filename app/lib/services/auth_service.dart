import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Phone OTP ──────────────────────────────────────────────────

  Future<void> verifyPhone({
    required String phoneNumber,
    required void Function(PhoneAuthCredential) onAutoVerified,
    required void Function(FirebaseAuthException) onFailed,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(String verificationId) onTimeout,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: onAutoVerified,
      verificationFailed: onFailed,
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: onTimeout,
      timeout: const Duration(seconds: 60),
    );
  }

  Future<UserCredential?> signInWithOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return await _auth.signInWithCredential(credential);
  }

  // ── User profile ───────────────────────────────────────────────

  Future<void> createOrUpdateUserDoc({
    required String uid,
    String? displayName,
    String? phone,
    String language = 'en',
  }) async {
    final ref = _firestore.collection('users').doc(uid);
    final snap = await ref.get();

    if (!snap.exists) {
      await ref.set({
        'uid': uid,
        'phone': phone ?? '',
        'display_name': displayName ?? '',
        'language': language,
        'city': 'Islamabad',
        'emergency_contacts': <Map<String, dynamic>>[],
        'role': 'citizen',
        'reputation': 50,
        'women_safe_route': false,
        'created_at': FieldValue.serverTimestamp(),
      });
    } else {
      // Update language preference if changed
      final updates = <String, dynamic>{};
      if (language.isNotEmpty) updates['language'] = language;
      if (displayName != null) updates['display_name'] = displayName;
      if (updates.isNotEmpty) await ref.update(updates);
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> getUserDoc(String uid) async {
    try {
      return await _firestore.collection('users').doc(uid).get();
    } catch (e) {
      debugPrint('Error fetching user doc: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
