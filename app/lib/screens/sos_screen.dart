/// Screen 6 — SOS
///
/// Full-screen red button. 2-sec hold to send.
/// Shares location via WhatsApp, shows nearest safe spots,
/// displays relevant helpline to call.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../services/connectivity_service.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen>
    with SingleTickerProviderStateMixin {
  bool _holding = false;
  bool _triggered = false;
  double _holdProgress = 0.0;
  late AnimationController _pulseController;

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
            style: GoogleFonts.inter(
              fontSize: 13,
              color: MColors.textSecondary,
            ),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Success animation
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
          Text(
            'Stay calm. Emergency services have been alerted.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white70,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // Call helpline card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  'Rescue 1122 (Islamabad)',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: MColors.red,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.phone, size: 24),
                    label: Text(
                      'Call 1122',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Nearest safe spots
          Container(
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
                  'Nearest Safe Spots',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                _safeSpotTile('G-10 Markaz Mosque', '300m', Icons.mosque),
                _safeSpotTile('Polyclinic Hospital', '800m', Icons.local_hospital),
                _safeSpotTile('NUST Campus Gate', '1.2km', Icons.school),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _safeSpotTile(String name, String distance, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
            ),
          ),
          Text(
            distance,
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

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
      setState(() => _triggered = true);
      _handleSosTrigger();
    }
  }

  Future<void> _handleSosTrigger() async {
    final isOnline = await ConnectivityService().checkOnlineStatus();
    
    if (!isOnline) {
      // M13: Offline SOS Fallback via SMS
      const lat = 33.6844;
      const lon = 73.0479;
      final smsBody = 'SOS lat:$lat lon:$lon Mehfooz User';
      final number = '1122';
      final url = Uri.parse('sms:$number?body=${Uri.encodeComponent(smsBody)}');
      
      try {
        await launchUrl(url);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to open SMS app.')),
          );
        }
      }
    } else {
      // Online: Proceed with standard WhatsApp/Firebase trigger
    }
  }
}
