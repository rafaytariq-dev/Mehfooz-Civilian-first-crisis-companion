import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../providers/user_provider.dart';
import '../services/offline_cache.dart';
import '../services/connectivity_service.dart';
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
  final _captionController = TextEditingController();
  int _severity = 3;
  bool _submitting = false;
  String? _selectedCrisisType = 'flood';
  File? _selectedPhoto;

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
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Incident'),
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
          VoiceRecorderWidget(
            userId: uid.isEmpty ? 'anonymous' : uid,
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
              Navigator.pop(context);
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
          Text("What's happening?", style: MTypography.titleEn(context)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _crisisTypes.map((type) {
              final selected = _selectedCrisisType == type.$1;
              return FilterChip(
                avatar: Icon(type.$2,
                    size: 18,
                    color: selected ? Colors.white : MColors.textSecondary),
                label: Text(type.$3),
                selected: selected,
                selectedColor: MColors.red,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : MColors.textPrimary,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w400,
                ),
                onSelected: (_) =>
                    setState(() => _selectedCrisisType = type.$1),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _textController,
            maxLines: 5,
            decoration: InputDecoration(
              hintText:
                  'Describe in any language...\nاردو میں لکھیں / Roman Urdu / English',
              hintStyle: GoogleFonts.inter(
                color: MColors.textSecondary.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 20),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: MColors.severityColor(_severity)
                    .withValues(alpha: 0.15),
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submitTextReport,
              icon: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _pickPhoto(ImageSource.camera),
            child: Container(
              height: 250,
              width: double.infinity,
              decoration: BoxDecoration(
                color: MColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: MColors.divider, width: 2),
              ),
              child: _selectedPhoto != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(_selectedPhoto!, fit: BoxFit.cover),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined,
                            size: 64,
                            color: MColors.textSecondary
                                .withValues(alpha: 0.4)),
                        const SizedBox(height: 16),
                        Text('Tap to take a photo',
                            style: MTypography.bodyEn(context)),
                        const SizedBox(height: 8),
                        Text('Photo will be AI-verified',
                            style: MTypography.captionEn(context)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickPhoto(ImageSource.camera),
                  icon: const Icon(Icons.camera),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Crisis type for photo tab
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _crisisTypes.map((type) {
              final selected = _selectedCrisisType == type.$1;
              return FilterChip(
                avatar: Icon(type.$2,
                    size: 16,
                    color: selected ? Colors.white : MColors.textSecondary),
                label: Text(type.$3,
                    style: TextStyle(fontSize: 12)),
                selected: selected,
                selectedColor: MColors.red,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : MColors.textPrimary,
                ),
                onSelected: (_) {
                  setState(() => _selectedCrisisType = type.$1);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _captionController,
            decoration: InputDecoration(
              hintText: 'Optional caption (any language)...',
              hintStyle: GoogleFonts.inter(color: MColors.textSecondary),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  (_submitting || _selectedPhoto == null) ? null : _submitPhotoReport,
              icon: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: Text(_submitting ? 'Uploading...' : 'Submit Photo Report'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1920,
    );
    if (picked != null) {
      setState(() => _selectedPhoto = File(picked.path));
    }
  }

  Future<Position?> _getLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );
    } catch (_) {
      return null;
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
    final uid = ref.read(currentUidProvider);
    final isOnline = await ConnectivityService().checkOnlineStatus();

    if (!isOnline) {
      final pos = await _getLocation();
      await OfflineCache.queueReport(
        QueuedReport(
          text: _textController.text.trim(),
          lat: pos?.latitude ?? 33.6844,
          lon: pos?.longitude ?? 73.0479,
          createdAt: DateTime.now(),
        ),
      );
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offline: Report queued — will send when online.'),
            backgroundColor: MColors.amber,
          ),
        );
        Navigator.pop(context);
      }
      return;
    }

    try {
      final pos = await _getLocation();
      await FirebaseFirestore.instance.collection('reports').add({
        'user_id': uid.isEmpty ? null : uid,
        'text_raw': _textController.text.trim(),
        'text_normalized': null,
        'language_detected': null,
        'photo_urls': <String>[],
        'location': pos != null
            ? GeoPoint(pos.latitude, pos.longitude)
            : null,
        'geo_accuracy_m': pos?.accuracy ?? 0,
        'crisis_type_user': _selectedCrisisType,
        'crisis_type_inferred': null,
        'severity_user': _severity,
        'vision_verified': false,
        'vision_confidence': 0,
        'linked_event_id': null,
        'created_at': FieldValue.serverTimestamp(),
        '_source': 'text',
      });

      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted — thank you!'),
            backgroundColor: MColors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit: $e')),
        );
      }
    }
  }

  Future<void> _submitPhotoReport() async {
    if (_selectedPhoto == null) return;
    setState(() => _submitting = true);

    final uid = ref.read(currentUidProvider);

    try {
      final pos = await _getLocation();
      final fileId = const Uuid().v4();
      final ref2 = FirebaseStorage.instance.ref('photos/$uid/$fileId.jpg');
      await ref2.putFile(
        _selectedPhoto!,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final photoUrl = await ref2.getDownloadURL();

      await FirebaseFirestore.instance.collection('reports').add({
        'user_id': uid.isEmpty ? null : uid,
        'text_raw': _captionController.text.trim().isEmpty
            ? null
            : _captionController.text.trim(),
        'text_normalized': null,
        'language_detected': null,
        'photo_urls': [photoUrl],
        'location': pos != null
            ? GeoPoint(pos.latitude, pos.longitude)
            : null,
        'geo_accuracy_m': pos?.accuracy ?? 0,
        'crisis_type_user': _selectedCrisisType,
        'crisis_type_inferred': null,
        'severity_user': _severity,
        'vision_verified': false,
        'vision_confidence': 0,
        'linked_event_id': null,
        'created_at': FieldValue.serverTimestamp(),
        '_source': 'photo',
      });

      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo report submitted!'),
            backgroundColor: MColors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
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
}
