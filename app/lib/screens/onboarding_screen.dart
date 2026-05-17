/// Screen 1 — Onboarding + Language Picker
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../router.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  String _selectedLanguage = 'English';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _languagePage(),
                  _welcomePage(),
                  _permissionsPage(),
                ],
              ),
            ),
            _buildIndicators(),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (_currentPage < 2) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    } else {
                      Navigator.pushReplacementNamed(context, AppRouter.home);
                    }
                  },
                  child: Text(_currentPage < 2 ? 'Next' : 'Get Started'),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

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
          Text('Choose your language',
              style: MTypography.titleEn(context)),
          const SizedBox(height: 16),
          ...['English', 'اردو', 'Roman Urdu'].map(
            (lang) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: _selectedLanguage == lang
                    ? ElevatedButton(
                        onPressed: () => setState(() => _selectedLanguage = lang),
                        child: Text(lang),
                      )
                    : OutlinedButton(
                        onPressed: () => setState(() => _selectedLanguage = lang),
                        child: Text(lang),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _welcomePage() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_on,
              size: 64, color: MColors.red.withValues(alpha: 0.7)),
          const SizedBox(height: 24),
          Text(
            'Stay safe, stay informed',
            style: MTypography.headlineEn(context),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Mehfooz uses citizen reports, weather data, and traffic signals to tell you exactly what\'s happening — and what to do — right now, where you are.',
            style: MTypography.bodyEn(context),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Text(
              'محفوظ آپ کو بتاتا ہے کہ آپ کے ارد گرد کیا ہو رہا ہے — اور آپ کو ابھی کیا کرنا چاہیے',
              style: GoogleFonts.notoNaskhArabic(
                fontSize: 14,
                color: MColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissionsPage() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.security,
              size: 64, color: MColors.green.withValues(alpha: 0.7)),
          const SizedBox(height: 24),
          Text(
            'We need a few permissions',
            style: MTypography.headlineEn(context),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _permissionTile(
            Icons.location_on,
            'Location',
            'To show incidents near you',
            true,
          ),
          _permissionTile(
            Icons.notifications,
            'Notifications',
            'For real-time crisis alerts',
            true,
          ),
          _permissionTile(
            Icons.mic,
            'Microphone',
            'For voice reporting (optional)',
            false,
          ),
        ],
      ),
    );
  }

  Widget _permissionTile(
      IconData icon, String title, String subtitle, bool required) {
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
                    Text(title,
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                    if (required)
                      Text(' (required)',
                          style: GoogleFonts.inter(
                              fontSize: 11, color: MColors.red)),
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
}
