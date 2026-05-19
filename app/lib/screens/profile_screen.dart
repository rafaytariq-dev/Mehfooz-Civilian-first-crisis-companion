/// Screen 8 — Profile + Emergency Contacts
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _language = 'English';
  String _city = 'Islamabad';
  bool _womenSafe = false;

  final _contacts = [
    {'name': 'Ahmed Khan', 'phone': '+92 300 1234567', 'relation': 'Father'},
    {'name': 'Fatima Bibi', 'phone': '+92 312 9876543', 'relation': 'Mother'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // User info
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: MColors.green.withValues(alpha: 0.2),
                  child: const Icon(Icons.person, size: 40, color: MColors.green),
                ),
                const SizedBox(height: 12),
                Text('Demo User', style: MTypography.headlineEn(context)),
                Text('+92 321 *****78',
                    style: MTypography.captionEn(context)),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: MColors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '⭐ Reputation: 75',
                    style: GoogleFonts.inter(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Language
          Card(
            child: ListTile(
              leading: const Icon(Icons.language),
              title: const Text('Language'),
              trailing: DropdownButton<String>(
                value: _language,
                underline: const SizedBox(),
                items: ['English', 'اردو', 'Roman Urdu']
                    .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                    .toList(),
                onChanged: (v) => setState(() => _language = v!),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // City
          Card(
            child: ListTile(
              leading: const Icon(Icons.location_city),
              title: const Text('City'),
              trailing: DropdownButton<String>(
                value: _city,
                underline: const SizedBox(),
                items: ['Islamabad', 'Rawalpindi', 'Karachi', 'Lahore']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _city = v!),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Women's safe mode
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.shield),
              title: const Text("Women's safe route default"),
              value: _womenSafe,
                    activeTrackColor: MColors.green,
              onChanged: (v) => setState(() => _womenSafe = v),
            ),
          ),

          const SizedBox(height: 24),

          // Emergency contacts
          Row(
            children: [
              Text('Emergency Contacts', style: MTypography.titleEn(context)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add_circle, color: MColors.red),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 8),

          ..._contacts.map(
            (c) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: MColors.red.withValues(alpha: 0.1),
                  child: const Icon(Icons.person, color: MColors.red),
                ),
                title: Text(c['name']!),
                subtitle: Text('${c['phone']} · ${c['relation']}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: MColors.textSecondary),
                  onPressed: () {},
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Notification preferences
          Text('Notifications', style: MTypography.titleEn(context)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                _notifToggle('SOS Alerts', 'Loud alarm + vibration', true),
                const Divider(height: 1),
                _notifToggle('High Priority', 'Sound + banner', true),
                const Divider(height: 1),
                _notifToggle('Medium Priority', 'Banner only', true),
                const Divider(height: 1),
                _notifToggle('Heatwave Alerts', 'Heat index warnings (M11)', true),
                const Divider(height: 1),
                _notifToggle('Low Priority', 'Notification tray', false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notifToggle(String title, String subtitle, bool value) {
    return SwitchListTile(
      title: Text(title, style: MTypography.bodyEn(context)),
      subtitle: Text(subtitle, style: MTypography.captionEn(context)),
      value: value,
            activeTrackColor: MColors.green,
      onChanged: (v) {},
    );
  }
}
