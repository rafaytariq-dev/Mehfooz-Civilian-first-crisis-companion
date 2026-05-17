/// Screen 5 — Safe Route
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

class SafeRouteScreen extends StatefulWidget {
  const SafeRouteScreen({super.key});

  @override
  State<SafeRouteScreen> createState() => _SafeRouteScreenState();
}

class _SafeRouteScreenState extends State<SafeRouteScreen> {
  bool _womenSafeMode = false;
  bool _loading = false;
  bool _routesFound = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find Safe Route')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Origin
            TextField(
              decoration: InputDecoration(
                labelText: 'From',
                hintText: 'Current location',
                prefixIcon: const Icon(Icons.my_location, color: MColors.green),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.gps_fixed),
                  onPressed: () {},
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Destination
            TextField(
              decoration: const InputDecoration(
                labelText: 'To',
                hintText: 'Search destination...',
                prefixIcon: Icon(Icons.location_on, color: MColors.red),
              ),
            ),
            const SizedBox(height: 16),

            // Women's safe mode toggle
            SwitchListTile(
              title: Text("Women's safe mode",
                  style: MTypography.bodyEn(context)),
              subtitle: Text(
                'Prefer well-lit main roads',
                style: MTypography.captionEn(context),
              ),
              value: _womenSafeMode,
              activeTrackColor: MColors.green,
              onChanged: (v) => setState(() => _womenSafeMode = v),
              contentPadding: EdgeInsets.zero,
            ),

            const SizedBox(height: 20),

            // Find button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _findRoutes,
                icon: _loading
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.route),
                label: Text(_loading ? 'Finding...' : 'Find Safe Routes'),
              ),
            ),

            if (_routesFound) ...[
              const SizedBox(height: 24),
              Text('3 routes found', style: MTypography.titleEn(context)),
              const SizedBox(height: 12),
              _routeCard('Margalla Ave → F-10', 'Safest', 0.2, '18 min',
                  '6.2 km', MColors.green, false),
              const SizedBox(height: 10),
              _routeCard('IJP Road (north)', 'Moderate', 0.5, '15 min',
                  '5.8 km', MColors.amber, true),
              const SizedBox(height: 10),
              _routeCard('Service Road → G-9', 'Longer but safe', 0.3,
                  '22 min', '7.1 km', MColors.green, false),
            ],
          ],
        ),
      ),
    );
  }

  Widget _routeCard(String name, String badge, double risk,
      String duration, String distance, Color badgeColor, bool flooded) {
    return Card(
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badge,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                      ),
                    ),
                  ),
                  if (flooded) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: MColors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.warning, size: 12,
                              color: MColors.red),
                          const SizedBox(width: 4),
                          Text(
                            'Passes near flood',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: MColors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  const Icon(Icons.open_in_new, size: 18,
                      color: MColors.textSecondary),
                ],
              ),
              const SizedBox(height: 8),
              Text(name, style: MTypography.bodyEn(context)),
              const SizedBox(height: 4),
              Text(
                '$duration · $distance',
                style: MTypography.captionEn(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _findRoutes() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() {
        _loading = false;
        _routesFound = true;
      });
    }
  }
}
