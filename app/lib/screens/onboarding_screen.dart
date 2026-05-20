import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/user_provider.dart';
import '../router.dart';
import '../theme.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  String _selectedLanguage = 'en';

  // Phone auth state
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  String? _verificationId;
  bool _codeSent = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _pageController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  // ── Pages ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _languagePage(),
                  _phonePage(),
                  _permissionsPage(),
                ],
              ),
            ),
            _buildIndicators(),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildBottomButton(),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButton() {
    if (_currentPage == 1) return const SizedBox.shrink(); // phone page has its own button
    if (_currentPage == 2) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _finishOnboarding,
          child: const Text('Get Started'),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ),
        child: const Text('Next'),
      ),
    );
  }

  // ── Page 1: Language ───────────────────────────────────────────

  Widget _languagePage() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: MColors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.shield, size: 48, color: MColors.red),
          ),
          const SizedBox(height: 24),
          Text(
            'محفوظ',
            style: GoogleFonts.notoNaskhArabic(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: MColors.red,
            ),
          ),
          Text(
            'Mehfooz',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w300,
              color: MColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          Text('Choose your language', style: MTypography.titleEn(context)),
          const SizedBox(height: 16),
          ...[('en', 'English'), ('ur', 'اردو'), ('roman_ur', 'Roman Urdu')]
              .map((lang) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: _selectedLanguage == lang.$1
                          ? ElevatedButton(
                              onPressed: () =>
                                  setState(() => _selectedLanguage = lang.$1),
                              child: Text(lang.$2),
                            )
                          : OutlinedButton(
                              onPressed: () =>
                                  setState(() => _selectedLanguage = lang.$1),
                              child: Text(lang.$2),
                            ),
                    ),
                  )),
        ],
      ),
    );
  }

  // ── Page 2: Phone OTP ──────────────────────────────────────────

  Widget _phonePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text('Your phone number', style: MTypography.headlineEn(context)),
          const SizedBox(height: 8),
          Text(
            'We\'ll send a one-time code to verify your number.',
            style: MTypography.bodyEn(context),
          ),
          const SizedBox(height: 32),

          if (!_codeSent) ...[
            // Phone number input
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: MColors.divider),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('+92', style: MTypography.bodyEn(context)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 10,
                    decoration: const InputDecoration(
                      hintText: '3001234567',
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: GoogleFonts.inter(color: MColors.red, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _sendOtp,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Send Code'),
              ),
            ),
          ] else ...[
            // OTP input
            Text(
              'Enter the 6-digit code sent to +92${_phoneController.text}',
              style: MTypography.bodyEn(context),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              style: GoogleFonts.inter(fontSize: 24, letterSpacing: 8),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: '------',
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: GoogleFonts.inter(color: MColors.red, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _verifyOtp,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Verify'),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _loading
                    ? null
                    : () => setState(() {
                          _codeSent = false;
                          _otpController.clear();
                          _error = null;
                        }),
                child: const Text('Change number'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Page 3: Permissions ────────────────────────────────────────

  Widget _permissionsPage() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.security, size: 64, color: MColors.green.withValues(alpha: 0.7)),
          const SizedBox(height: 24),
          Text('We need a few permissions', style: MTypography.headlineEn(context),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          _permTile(Icons.location_on, 'Location', 'To show incidents near you', true),
          _permTile(Icons.notifications, 'Notifications', 'For real-time crisis alerts', true),
          _permTile(Icons.mic, 'Microphone', 'For voice reporting (optional)', false),
        ],
      ),
    );
  }

  Widget _permTile(IconData icon, String title, String subtitle, bool required) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: MColors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: MColors.green),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                    if (required)
                      Text(' (required)',
                          style: GoogleFonts.inter(fontSize: 11, color: MColors.red)),
                  ],
                ),
                Text(subtitle, style: MTypography.captionEn(context)),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: MColors.green),
        ],
      ),
    );
  }

  Widget _buildIndicators() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        3,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: _currentPage == i ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: _currentPage == i ? MColors.red : MColors.divider,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  // ── Auth logic ─────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    final number = _phoneController.text.trim();
    if (number.length < 9) {
      setState(() => _error = 'Enter a valid 10-digit number');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    await ref.read(authServiceProvider).verifyPhone(
      phoneNumber: '+92$number',
      onAutoVerified: (credential) async {
        await _signInWithCredential(credential);
      },
      onFailed: (e) {
        setState(() {
          _loading = false;
          _error = e.message ?? 'Verification failed. Try again.';
        });
      },
      onCodeSent: (verificationId, _) {
        setState(() {
          _verificationId = verificationId;
          _codeSent = true;
          _loading = false;
        });
      },
      onTimeout: (_) {
        setState(() => _loading = false);
      },
    );
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    if (_verificationId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final cred = await ref.read(authServiceProvider).signInWithOtp(
        verificationId: _verificationId!,
        smsCode: code,
      );

      if (cred?.user != null) {
        await _onSignedIn(cred!.user!);
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message ?? 'Invalid code. Try again.';
      });
    }
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      final cred = await FirebaseAuth.instance.signInWithCredential(credential);
      if (cred.user != null) await _onSignedIn(cred.user!);
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _onSignedIn(User user) async {
    await ref.read(authServiceProvider).createOrUpdateUserDoc(
      uid: user.uid,
      phone: user.phoneNumber,
      language: _selectedLanguage,
    );

    if (mounted) {
      setState(() => _loading = false);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _finishOnboarding() async {
    await [
      Permission.location,
      Permission.notification,
    ].request();

    if (mounted) {
      Navigator.pushReplacementNamed(context, AppRouter.home);
    }
  }
}
