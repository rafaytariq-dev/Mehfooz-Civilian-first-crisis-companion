import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/user_provider.dart';
import '../services/connectivity_service.dart';
import '../theme.dart';

class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key});

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen>
    with SingleTickerProviderStateMixin {
  bool _holding = false;
  bool _triggered = false;
  double _holdProgress = 0.0;
  late AnimationController _pulseController;

  Position? _position;
  Map<String, dynamic>? _helpline;
  List<Map<String, dynamic>> _safeSpots = [];
  List<Map<String, dynamic>> _emergencyContacts = [];
  bool _loadingData = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _triggered ? MColors.red : MColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: _triggered ? Colors.white : MColors.textPrimary,
        title: Text(_triggered ? 'SOS Sent' : 'Emergency SOS'),
      ),
      body: _triggered ? _buildTriggeredView() : _buildHoldView(),
    );
  }

  Widget _buildHoldView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final scale = 1.0 + (_pulseController.value * 0.08);
              return Transform.scale(
                scale: _holding ? 1.1 : scale,
                child: child,
              );
            },
            child: GestureDetector(
              onLongPressStart: (_) => _startHold(),
              onLongPressEnd: (_) => _endHold(),
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MColors.red,
                  boxShadow: [
                    BoxShadow(
                      color: MColors.red.withValues(alpha: 0.4),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_holding)
                      SizedBox(
                        width: 160,
                        height: 160,
                        child: CircularProgressIndicator(
                          value: _holdProgress,
                          strokeWidth: 6,
                          color: Colors.white,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.emergency, size: 48, color: Colors.white),
                        const SizedBox(height: 4),
                        Text(
                          'SOS',
                          style: GoogleFonts.inter(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
          Text(
            'Hold for 2 seconds to send SOS',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: MColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your location will be shared with\nemergency contacts via WhatsApp',
            style: GoogleFonts.inter(fontSize: 13, color: MColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Text(
              'آپ کی لوکیشن ایمرجنسی رابطوں کو بھیجی جائے گی',
              style: GoogleFonts.notoNaskhArabic(
                fontSize: 14,
                color: MColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTriggeredView() {
    if (_loadingData) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.check_circle, size: 80, color: Colors.white),
          const SizedBox(height: 16),
          Text(
            'Help is being notified',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          if (_position != null)
            Text(
              'Location: ${_position!.latitude.toStringAsFixed(4)}°N, '
              '${_position!.longitude.toStringAsFixed(4)}°E',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 32),

          // ── Emergency contacts ───────────────────────────────
          if (_emergencyContacts.isNotEmpty) ...[
            _sectionCard(
              title: 'Contacts Notified via WhatsApp',
              children: _emergencyContacts
                  .map((c) => _contactTile(c))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],

          // ── Helpline ─────────────────────────────────────────
          _sectionCard(
            title: _helpline?['name'] ?? 'Emergency Services',
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _call(_helpline?['number'] ?? '1122'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: MColors.red,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.phone, size: 24),
                  label: Text(
                    'Call ${_helpline?['number'] ?? '1122'}',
                    style: GoogleFonts.inter(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Safe spots ───────────────────────────────────────
          if (_safeSpots.isNotEmpty)
            _sectionCard(
              title: 'Nearest Safe Spots',
              children: _safeSpots
                  .map((s) => _safeSpotTile(s))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _contactTile(Map<String, dynamic> contact) {
    final name = contact['name'] as String? ?? 'Contact';
    final phone = contact['phone'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.person, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14)),
          ),
          TextButton(
            onPressed: () => _whatsApp(phone, ''),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            child: const Text('WhatsApp'),
          ),
        ],
      ),
    );
  }

  Widget _safeSpotTile(Map<String, dynamic> spot) {
    final name = spot['name'] as String? ?? 'Safe spot';
    final type = spot['type'] as String? ?? 'location';
    final distM = spot['_dist_m'] as double?;
    final distText = distM != null
        ? distM < 1000
            ? '${distM.round()}m'
            : '${(distM / 1000).toStringAsFixed(1)}km'
        : '';

    IconData icon;
    switch (type) {
      case 'hospital': icon = Icons.local_hospital; break;
      case 'mosque': icon = Icons.mosque; break;
      case 'mall': icon = Icons.local_mall; break;
      case 'school': icon = Icons.school; break;
      default: icon = Icons.location_on;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14)),
          ),
          if (distText.isNotEmpty)
            Text(distText,
                style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Hold logic ─────────────────────────────────────────────────

  void _startHold() {
    setState(() => _holding = true);
    _animateHold();
  }

  void _endHold() {
    setState(() {
      _holding = false;
      if (_holdProgress < 1.0) _holdProgress = 0;
    });
  }

  Future<void> _animateHold() async {
    const steps = 40;
    for (int i = 0; i <= steps; i++) {
      if (!_holding || !mounted) return;
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
      setState(() => _holdProgress = i / steps);
    }
    if (_holding && mounted) {
      setState(() {
        _triggered = true;
        _loadingData = true;
      });
      await _handleSosTrigger();
    }
  }

  // ── SOS trigger ────────────────────────────────────────────────

  Future<void> _handleSosTrigger() async {
    // 1. Get location
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.denied &&
          perm != LocationPermission.deniedForever) {
        _position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 6),
          ),
        );
      }
    } catch (_) {}

    final uid = ref.read(currentUidProvider);
    final isOnline = await ConnectivityService().checkOnlineStatus();

    if (!isOnline) {
      // Offline SOS: SMS fallback
      final lat = _position?.latitude ?? 33.6844;
      final lon = _position?.longitude ?? 73.0479;
      final smsBody = 'SOS lat:$lat lon:$lon Mehfooz';
      await launchUrl(
          Uri.parse('sms:1122?body=${Uri.encodeComponent(smsBody)}'));
      if (mounted) setState(() => _loadingData = false);
      return;
    }

    // 2. Write SOS event to Firestore
    if (_position != null && uid.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('sos_events').add({
          'user_id': uid,
          'location': GeoPoint(_position!.latitude, _position!.longitude),
          'created_at': FieldValue.serverTimestamp(),
          'status': 'active',
        });
      } catch (_) {}
    }

    // 3. Fetch user profile (emergency contacts + city)
    String city = 'Islamabad';
    if (uid.isNotEmpty) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        if (userDoc.exists) {
          city = userDoc.data()?['city'] as String? ?? 'Islamabad';
          final contacts = userDoc.data()?['emergency_contacts'];
          if (contacts is List) {
            _emergencyContacts = contacts
                .whereType<Map<String, dynamic>>()
                .toList();
          }
        }
      } catch (_) {}
    }

    // 4. WhatsApp all emergency contacts
    if (_position != null) {
      for (final contact in _emergencyContacts) {
        final phone = (contact['phone'] as String? ?? '').replaceAll('+', '');
        if (phone.isNotEmpty) {
          await _whatsApp(
            phone,
            'SOS — I need help! My location: '
            'https://maps.google.com/?q=${_position!.latitude},${_position!.longitude}',
          );
        }
      }
    }

    // 5. Fetch nearest helpline for city + flood
    await _fetchHelpline(city);

    // 6. Fetch nearest safe spots
    if (_position != null) {
      await _fetchSafeSpots(_position!);
    }

    if (mounted) setState(() => _loadingData = false);
  }

  Future<void> _fetchHelpline(String city) async {
    try {
      // Try city-specific match for flood/emergency first
      QuerySnapshot snap = await FirebaseFirestore.instance
          .collection('helplines')
          .where('cities', arrayContains: city)
          .where('crisis_types', arrayContains: 'flood')
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        // Fallback: wildcard cities
        snap = await FirebaseFirestore.instance
            .collection('helplines')
            .where('cities', arrayContains: '*')
            .limit(1)
            .get();
      }

      if (snap.docs.isNotEmpty && mounted) {
        setState(() => _helpline = snap.docs.first.data() as Map<String, dynamic>);
      }
    } catch (_) {
      // Keep null — UI shows default 1122
    }
  }

  Future<void> _fetchSafeSpots(Position pos) async {
    try {
      // Simple query: get safe spots, compute distance client-side
      final snap = await FirebaseFirestore.instance
          .collection('safe_spots')
          .limit(20)
          .get();

      final spots = snap.docs.map((d) {
        final data = d.data();
        final loc = data['location'];
        double distM = double.infinity;
        if (loc is GeoPoint) {
          distM = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            loc.latitude,
            loc.longitude,
          );
        }
        return {...data, '_dist_m': distM, 'id': d.id};
      }).toList()
        ..sort((a, b) =>
            (a['_dist_m'] as double).compareTo(b['_dist_m'] as double));

      if (mounted) {
        setState(() => _safeSpots = spots.take(3).toList());
      }
    } catch (_) {}
  }

  // ── Helpers ────────────────────────────────────────────────────

  Future<void> _call(String number) async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _whatsApp(String phone, String message) async {
    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse('whatsapp://send?phone=$phone&text=$encoded');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}
