/// Heatwave Providers — M11
///
/// Riverpod providers for heat index state, cooling spots, and service access.
/// Auto-refreshes when screen is active.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/heatwave_service.dart';

// ─── Service singleton ───
final heatwaveServiceProvider = Provider<HeatwaveService>((ref) {
  return HeatwaveService();
});

// ─── Current weather + heat index ───
final heatWeatherProvider =
    FutureProvider.family<HeatWeatherData?, String>((ref, city) async {
  final service = ref.watch(heatwaveServiceProvider);
  return service.fetchCurrentWeather(city);
});

// ─── Nearest cooling spots ───
final coolingSpotParams = Provider<({double lat, double lng, int limit})>(
  (ref) => (lat: 24.8607, lng: 67.0011, limit: 5),
);

final coolingSpotsFutureProvider =
    FutureProvider.family<List<CoolingSpotData>, ({double lat, double lng, int limit})>(
  (ref, params) async {
    final service = ref.watch(heatwaveServiceProvider);
    return service.getNearestCoolingSpots(
      lat: params.lat,
      lng: params.lng,
      limit: params.limit,
    );
  },
);

// ─── Heat safety tips (static content, bilingual) ───
class HeatSafetyTip {
  final String titleEn;
  final String titleUr;
  final String bodyEn;
  final String bodyUr;
  final String icon;

  const HeatSafetyTip({
    required this.titleEn,
    required this.titleUr,
    required this.bodyEn,
    required this.bodyUr,
    required this.icon,
  });
}

final heatSafetyTipsProvider = Provider<List<HeatSafetyTip>>((ref) {
  return const [
    HeatSafetyTip(
      icon: '💧',
      titleEn: 'Stay Hydrated',
      titleUr: 'Paani peete rahein',
      bodyEn: 'Drink water every 15–20 minutes even if not thirsty.',
      bodyUr: 'Har 15–20 minute mein paani peeyein, chahe pyaas na lagay.',
    ),
    HeatSafetyTip(
      icon: '☀️',
      titleEn: 'Avoid Direct Sun',
      titleUr: 'Dhoop se bachein',
      bodyEn: 'Stay in shade, especially between 11 AM and 4 PM.',
      bodyUr: 'Saaye mein rahein, khaas tor par subah 11 se sham 4 tak.',
    ),
    HeatSafetyTip(
      icon: '👕',
      titleEn: 'Wear Light Clothing',
      titleUr: 'Halke kapray pehnein',
      bodyEn: 'Choose loose, light-colored, breathable clothes.',
      bodyUr: 'Dheelay, halkay rang ke, hawa dar kapray pehnein.',
    ),
    HeatSafetyTip(
      icon: '🧊',
      titleEn: 'Cool Down',
      titleUr: 'Thanda karein',
      bodyEn: 'Wet a cloth and put on your neck. Seek AC/fans.',
      bodyUr: 'Geela kapra gardan par rakhein. AC ya pankha talash karein.',
    ),
    HeatSafetyTip(
      icon: '🚨',
      titleEn: 'Know Heatstroke Signs',
      titleUr: 'Heatstroke ki nishaniyan janein',
      bodyEn: 'Confusion, no sweat, hot skin → call helpline immediately.',
      bodyUr: 'Confusion, pasina band, garam jild → foran helpline call karein.',
    ),
    HeatSafetyTip(
      icon: '📞',
      titleEn: 'Check on Vulnerable People',
      titleUr: 'Burhon aur bachon ka khayal rakhein',
      bodyEn: 'Call elderly relatives and neighbors regularly.',
      bodyUr: 'Buzurg rishtedaron aur parhosion ko call karein.',
    ),
  ];
});
