/// Screen 3 — Report Flow
///
/// Three-tab segmented control: Text / Photo / Voice
/// Voice tab (M8) uses VoiceRecorderWidget with full recording pipeline.
/// Each submits a report to Firestore, triggering the ingestion agent.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';
import '../widgets/voice_recorder.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _textController = TextEditingController();
  int _severity = 3;
  bool _submitting = false;
  String? _selectedCrisisType;

  final _crisisTypes = [
    ('flood', Icons.water, 'Flood'),
    ('urban_flood', Icons.location_city, 'Urban Flood'),
    ('fire', Icons.local_fire_department, 'Fire'),
    ('road_incident', Icons.car_crash, 'Road Incident'),
    ('power_outage', Icons.power_off, 'Power Outage'),
    ('building_collapse', Icons.domain_disabled, 'Building Collapse'),
    ('heatwave', Icons.thermostat, 'Heatwave'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _selectedCrisisType = 'flood';
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Incident'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Attach location',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Location attached automatically')),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: MColors.red,
          unselectedLabelColor: MColors.textSecondary,
          indicatorColor: MColors.red,
          tabs: const [
            Tab(icon: Icon(Icons.text_fields), text: 'Text'),
            Tab(icon: Icon(Icons.camera_alt), text: 'Photo'),
            Tab(icon: Icon(Icons.mic), text: 'Voice'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTextTab(),
          _buildPhotoTab(),
          // ─── M8: Wired voice recorder ───
          VoiceRecorderWidget(
            // TODO: Replace with actual user ID from Firebase Auth
            userId: 'demo_user',
            crisisType: _selectedCrisisType,
            onReportSubmitted: (result) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Voice report submitted! (${result.recordingDuration.inSeconds}s)',
                  ),
                  backgroundColor: MColors.green,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What\'s happening?', style: MTypography.titleEn(context)),
          const SizedBox(height: 12),

          // Crisis type chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _crisisTypes.map((type) {
              final selected = _selectedCrisisType == type.$1;
              return FilterChip(
                avatar: Icon(type.$2, size: 18,
                    color: selected ? Colors.white : MColors.textSecondary),
                label: Text(type.$3),
                selected: selected,
                selectedColor: MColors.red,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : MColors.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                onSelected: (val) =>
                    setState(() => _selectedCrisisType = type.$1),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // Text input — supports Urdu/Roman Urdu/English
          TextField(
            controller: _textController,
            maxLines: 5,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              hintText: 'Describe in any language...\nاردو میں لکھیں / Roman Urdu / English',
              hintStyle: GoogleFonts.inter(
                color: MColors.textSecondary.withValues(alpha: 0.5),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Severity slider
          Text('Severity', style: MTypography.titleEn(context)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Minor', style: MTypography.captionEn(context)),
              Expanded(
                child: Slider(
                  value: _severity.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  activeColor: MColors.severityColor(_severity),
                  label: _severityLabel(_severity),
                  onChanged: (v) => setState(() => _severity = v.round()),
                ),
              ),
              Text('Critical', style: MTypography.captionEn(context)),
            ],
          ),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: MColors.severityColor(_severity).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _severityLabel(_severity),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: MColors.severityColor(_severity),
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submitTextReport,
              icon: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(_submitting ? 'Submitting...' : 'Submit Report'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 250,
            width: double.infinity,
            decoration: BoxDecoration(
              color: MColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: MColors.divider,
                width: 2,
                style: BorderStyle.solid,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.camera_alt_outlined, size: 64,
                    color: MColors.textSecondary.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                Text(
                  'Take a photo of the situation',
                  style: MTypography.bodyEn(context),
                ),
                const SizedBox(height: 8),
                Text(
                  'Photo will be verified by AI',
                  style: MTypography.captionEn(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.camera),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              hintText: 'Optional caption...',
              hintStyle: GoogleFonts.inter(color: MColors.textSecondary),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.send),
              label: const Text('Submit Photo Report'),
            ),
          ),
        ],
      ),
    );
  }




  String _severityLabel(int sev) {
    switch (sev) {
      case 1: return 'Minor disruption';
      case 2: return 'Localized issue';
      case 3: return 'Significant';
      case 4: return 'Severe — Evacuate';
      case 5: return 'Life-threatening';
      default: return '';
    }
  }

  Future<void> _submitTextReport() async {
    if (_textController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the situation')),
      );
      return;
    }

    setState(() => _submitting = true);

    // Simulate submit — in production, writes to Firestore
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Report submitted! Our AI is verifying it now.'),
          backgroundColor: MColors.green,
        ),
      );
      Navigator.pop(context);
    }
  }
}
