/// Screen — Heatwave Advisory (M11)
///
/// Full-featured heatwave advice screen with:
/// - Heat index gauge
/// - Current conditions card
/// - Nearest cooling centers
/// - Safety tips (bilingual)
/// - Emergency contact quick-share
///
/// Uses Riverpod for state management and follows Mehfooz design system.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';
import '../services/heatwave_service.dart';
import '../providers/heatwave_provider.dart';
import '../widgets/heat_index_gauge.dart';
import '../widgets/cooling_spot_tile.dart';

class HeatwaveScreen extends ConsumerStatefulWidget {
  final String city;

  const HeatwaveScreen({super.key, this.city = 'Karachi'});

  @override
  ConsumerState<HeatwaveScreen> createState() => _HeatwaveScreenState();
}

class _HeatwaveScreenState extends ConsumerState<HeatwaveScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final HeatwaveService _service = HeatwaveService();

  // Demo data for fallback display
  double _demoHeatIndex = 46.3;
  double _demoTempC = 44.1;
  double _demoHumidity = 56;
  double _demoWindKph = 4;

  List<CoolingSpotData> _coolingSpots = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Try fetching live weather
    final weather = await _service.fetchCurrentWeather(widget.city);
    if (weather != null) {
      _demoHeatIndex = weather.heatIndexC;
      _demoTempC = weather.tempC;
      _demoHumidity = weather.humidity;
      _demoWindKph = weather.windKph;
    }

    // Fetch cooling spots
    // Use Karachi coordinates as default
    _coolingSpots = await _service.getNearestCoolingSpots(
      lat: 24.8918,
      lng: 67.0745,
      limit: 5,
    );

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tips = ref.watch(heatSafetyTipsProvider);

    return Scaffold(
      backgroundColor: MColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 300,
              pinned: true,
              backgroundColor: MColors.surface,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadData,
                  tooltip: 'Refresh',
                ),
                IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: _shareWithFamily,
                  tooltip: 'Share with family',
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: _buildGaugeHeader(),
              ),
              bottom: TabBar(
                controller: _tabController,
                labelColor: MColors.red,
                unselectedLabelColor: MColors.textSecondary,
                indicatorColor: MColors.red,
                indicatorWeight: 3,
                labelStyle: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(text: 'Conditions'),
                  Tab(text: 'Cooling Centers'),
                  Tab(text: 'Safety Tips'),
                ],
              ),
            ),
          ];
        },
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildConditionsTab(),
                  _buildCoolingCentersTab(),
                  _buildSafetyTipsTab(tips),
                ],
              ),
      ),
    );
  }

  // ─── Header with gauge ───
  Widget _buildGaugeHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _headerGradientColor.withValues(alpha: 0.08),
            MColors.surface,
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            HeatIndexGauge(
              heatIndexC: _demoHeatIndex,
              size: 180,
            ),
            const SizedBox(height: 8),
            Text(
              widget.city,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: MColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color get _headerGradientColor {
    if (_demoHeatIndex < 27) return const Color(0xFF4CAF50);
    if (_demoHeatIndex < 32) return const Color(0xFFFFEB3B);
    if (_demoHeatIndex < 41) return const Color(0xFFFF9800);
    if (_demoHeatIndex < 54) return MColors.red;
    return const Color(0xFF9C27B0);
  }

  // ─── Tab 1: Current Conditions ───
  Widget _buildConditionsTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Weather conditions grid
        _sectionTitle('Current Conditions', 'موجودہ حالات'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _conditionCard(
                '🌡️',
                'Temperature',
                '${_demoTempC.toStringAsFixed(1)}°C',
                'درجہ حرارت',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _conditionCard(
                '💧',
                'Humidity',
                '${_demoHumidity.toStringAsFixed(0)}%',
                'نمی',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _conditionCard(
                '💨',
                'Wind',
                '${_demoWindKph.toStringAsFixed(0)} km/h',
                'ہوا',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _conditionCard(
                '🔥',
                'Heat Index',
                '${_demoHeatIndex.toStringAsFixed(1)}°C',
                'ہیٹ انڈیکس',
                highlight: true,
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // What does this mean?
        _sectionTitle('What does this mean?', 'اس کا کیا مطلب ہے؟'),
        const SizedBox(height: 12),
        _dangerExplanationCard(),

        const SizedBox(height: 24),

        // Emergency contact section
        _sectionTitle('Emergency Actions', 'ایمرجنسی اقدامات'),
        const SizedBox(height: 12),
        _buildEmergencyActions(),
      ],
    );
  }

  Widget _conditionCard(
    String emoji,
    String label,
    String value,
    String labelUr, {
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight
            ? _headerGradientColor.withValues(alpha: 0.08)
            : MColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: highlight
            ? Border.all(color: _headerGradientColor.withValues(alpha: 0.3))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: highlight ? _headerGradientColor : MColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: MColors.textSecondary,
            ),
          ),
          Text(
            labelUr,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: MColors.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dangerExplanationCard() {
    final level = HeatwaveService.dangerLevel(_demoHeatIndex);
    final levelUr = HeatwaveService.dangerLevelUr(_demoHeatIndex);
    final explanation = _explanationForLevel(_demoHeatIndex);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _headerGradientColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _headerGradientColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _headerGradientColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$level · $levelUr',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _headerGradientColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            explanation['en']!,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: MColors.textPrimary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            explanation['ur']!,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: MColors.textSecondary,
              height: 1.5,
            ),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  Map<String, String> _explanationForLevel(double hi) {
    if (hi >= 54) {
      return {
        'en':
            'EXTREME DANGER: Heatstroke is imminent. Move to air-conditioned shelter immediately. Do not go outside.',
        'ur':
            'انتہائی خطرہ: ہیٹ سٹروک کا فوری خدشہ ہے۔ فوراً ایئر کنڈیشنڈ پناہ گاہ میں جائیں۔ باہر مت جائیں۔',
      };
    }
    if (hi >= 41) {
      return {
        'en':
            'DANGER: Heatstroke, cramps, and exhaustion likely with prolonged exposure. Seek cooling shelter, drink water every 15 min.',
        'ur':
            'خطرہ: زیادہ دیر باہر رہنے سے ہیٹ سٹروک، اکڑن اور تھکاوٹ ہو سکتی ہے۔ ٹھنڈی جگہ تلاش کریں، ہر 15 منٹ میں پانی پئیں۔',
      };
    }
    if (hi >= 32) {
      return {
        'en':
            'EXTREME CAUTION: Heat exhaustion possible. Limit outdoor activity, stay hydrated, take frequent breaks.',
        'ur':
            'شدید احتیاط: گرمی سے تھکاوٹ ہو سکتی ہے۔ باہر کی سرگرمی محدود کریں، پانی پیتے رہیں۔',
      };
    }
    return {
      'en': 'CAUTION: Fatigue possible with prolonged exposure. Stay hydrated.',
      'ur': 'احتیاط: زیادہ دیر باہر رہنے سے تھکاوٹ ہو سکتی ہے۔ پانی پیتے رہیں۔',
    };
  }

  Widget _buildEmergencyActions() {
    return Column(
      children: [
        // Share with family
        _actionButton(
          icon: Icons.family_restroom,
          emoji: '👨‍👩‍👧',
          title: 'Share with family',
          titleUr: 'خاندان کو بتائیں',
          subtitle: 'WhatsApp se heat alert share karein',
          color: MColors.green,
          onTap: _shareWithFamily,
        ),
        const SizedBox(height: 10),
        // Call helpline
        _actionButton(
          icon: Icons.phone_in_talk,
          emoji: '📞',
          title: 'Call Helpline (1166)',
          titleUr: 'ہیلپ لائن کال کریں',
          subtitle: 'Edhi Emergency — 24/7',
          color: MColors.red,
          onTap: () {
            // Would launch phone dialer
          },
        ),
        const SizedBox(height: 10),
        // Navigate to cooling center
        if (_coolingSpots.isNotEmpty)
          _actionButton(
            icon: Icons.ac_unit,
            emoji: '❄️',
            title: 'Navigate to nearest cooling center',
            titleUr: 'قریب ترین ٹھنڈی جگہ',
            subtitle: '${_coolingSpots.first.name} · ${_coolingSpots.first.distanceM}m',
            color: const Color(0xFF42A5F5),
            onTap: () => _service.navigateToCoolingSpot(_coolingSpots.first),
          ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String emoji,
    required String title,
    required String titleUr,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: MColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: MColors.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: MColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Tab 2: Cooling Centers ───
  Widget _buildCoolingCentersTab() {
    if (_coolingSpots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('❄️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              'No cooling centers found nearby',
              style: GoogleFonts.inter(
                fontSize: 16,
                color: MColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _coolingSpots.length + 1, // +1 for header
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(
                  'Nearest Cooling Centers',
                  'قریب ترین ٹھنڈی جگہیں',
                ),
                const SizedBox(height: 4),
                Text(
                  '${_coolingSpots.length} spots with cooling within 5km',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: MColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        final spot = _coolingSpots[index - 1];
        return CoolingSpotTile(
          spot: spot,
          index: index - 1,
          onNavigate: () => _service.navigateToCoolingSpot(spot),
        );
      },
    );
  }

  // ─── Tab 3: Safety Tips ───
  Widget _buildSafetyTipsTab(List<HeatSafetyTip> tips) {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: tips.length + 2, // +1 header, +1 footer
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _sectionTitle(
              'Heat Safety Tips',
              'گرمی سے بچاؤ کی تجاویز',
            ),
          );
        }

        if (index == tips.length + 1) {
          return _buildFirstAidCard();
        }

        final tip = tips[index - 1];
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 400 + (index * 80)),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 16 * (1 - value)),
                child: child,
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MColors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tip.icon, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tip.titleEn,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: MColors.textPrimary,
                        ),
                      ),
                      Text(
                        tip.titleUr,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: MColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tip.bodyEn,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: MColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tip.bodyUr,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: MColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFirstAidCard() {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            MColors.red.withValues(alpha: 0.06),
            MColors.amber.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MColors.red.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🆘', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Text(
                'Heatstroke First Aid',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: MColors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _firstAidStep('1', 'Move person to shade or cool area',
              'شخص کو سایہ یا ٹھنڈی جگہ لے جائیں'),
          _firstAidStep('2', 'Cool with water — do NOT use ice',
              'پانی سے ٹھنڈا کریں — برف استعمال نہ کریں'),
          _firstAidStep('3', 'Give fluids if conscious',
              'اگر ہوش میں ہو تو پانی پلائیں'),
          _firstAidStep('4', 'Call helpline if confused or unconscious',
              'اگر بےہوش ہو تو فوراً ہیلپ لائن کال کریں'),
        ],
      ),
    );
  }

  Widget _firstAidStep(String num, String textEn, String textUr) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: MColors.red.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                num,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: MColors.red,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  textEn,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: MColors.textPrimary,
                  ),
                ),
                Text(
                  textUr,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: MColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ───

  Widget _sectionTitle(String titleEn, String titleUr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titleEn,
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: MColors.textPrimary,
          ),
        ),
        Text(
          titleUr,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: MColors.textSecondary,
          ),
          textDirection: TextDirection.rtl,
        ),
      ],
    );
  }

  void _shareWithFamily() {
    _service.shareHeatWarningWhatsApp(
      contactPhone: '+923001234567',
      contactName: 'Family',
      heatIndex: _demoHeatIndex,
      city: widget.city,
      userName: 'Demo User',
    );
  }
}
