/// M14 — Mosque Admin Broadcast Composer
///
/// Verified mosque admins (users.role == 'mosque_admin') reach this screen
/// from the Profile tab. They pick the mosque, crisis type, severity, and
/// compose a bilingual message (≤280 chars). Tapping "Post broadcast" calls
/// the `createBroadcast` Cloud Function which fans out FCM to users in 3km.
///
/// All misuse controls (rate-limit, role check, length cap, allowed-types
/// whitelist) are enforced server-side. The UI gives feedback when they
/// trip.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../theme.dart';
import '../providers/broadcast_provider.dart';
import '../services/broadcast_service.dart';

class BroadcastComposeScreen extends ConsumerStatefulWidget {
  const BroadcastComposeScreen({super.key});

  @override
  ConsumerState<BroadcastComposeScreen> createState() =>
      _BroadcastComposeScreenState();
}

class _BroadcastComposeScreenState
    extends ConsumerState<BroadcastComposeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _textUrCtrl = TextEditingController();
  final _textEnCtrl = TextEditingController();

  MosqueDoc? _selectedMosque;
  String _crisisType = 'general_safety';
  int _severity = 1;
  bool _posting = false;

  @override
  void dispose() {
    _textUrCtrl.dispose();
    _textEnCtrl.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMosque == null) {
      _snack('Select a mosque first');
      return;
    }
    if (_textUrCtrl.text.trim().isEmpty && _textEnCtrl.text.trim().isEmpty) {
      _snack('Enter a message (Urdu or English)');
      return;
    }

    setState(() => _posting = true);
    try {
      final svc = ref.read(broadcastServiceProvider);
      final id = await svc.createBroadcast(
        mosqueId: _selectedMosque!.id,
        crisisType: _crisisType,
        textUr: _textUrCtrl.text.trim(),
        textEn: _textEnCtrl.text.trim(),
        severity: _severity,
      );
      if (!mounted) return;
      _snack('Broadcast posted: $id', isError: false);
      _textUrCtrl.clear();
      _textEnCtrl.clear();
      setState(() => _severity = 1);
    } on FirebaseFunctionsException catch (e) {
      _snack(_friendlyError(e));
    } catch (e) {
      _snack('Failed to post: $e');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  String _friendlyError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'You are not authorized to broadcast as this mosque.';
      case 'unauthenticated':
        return 'Please sign in to broadcast.';
      case 'invalid-argument':
        return 'Invalid input: ${e.message ?? 'check the form.'}';
      case 'not-found':
        return 'Mosque not found.';
      default:
        return e.message ?? 'Broadcast failed (${e.code}).';
    }
  }

  void _snack(String msg, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? MColors.red : MColors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mosquesAsync = ref.watch(myMosquesProvider);
    final myBroadcasts = ref.watch(myBroadcastsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mosque Broadcast'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(Icons.shield, size: 14, color: MColors.green),
                const SizedBox(width: 6),
                Text(
                  'Verified Community Broadcaster',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: MColors.green,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: mosquesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load mosques: $e')),
        data: (mosques) {
          if (mosques.isEmpty) {
            return _noMosquesView();
          }
          // Default selection
          _selectedMosque ??= mosques.first;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _composerCard(mosques),
              const SizedBox(height: 16),
              Text('My recent broadcasts',
                  style: MTypography.titleEn(context)),
              const SizedBox(height: 8),
              myBroadcasts.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('$e'),
                data: (list) {
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No broadcasts yet.',
                        style: MTypography.captionEn(context),
                      ),
                    );
                  }
                  return Column(
                    children: list.map(_historyTile).toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _noMosquesView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mosque_outlined,
                size: 64, color: MColors.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'No mosques linked to your account.',
              style: MTypography.bodyEn(context),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Mosque verification is a manual ops process. '
              'Contact the Mehfooz team to register a new verified mosque.',
              style: MTypography.captionEn(context),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _composerCard(List<MosqueDoc> mosques) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mosque picker
              DropdownButtonFormField<MosqueDoc>(
                value: _selectedMosque,
                decoration: const InputDecoration(
                  labelText: 'Broadcast as',
                  prefixIcon: Icon(Icons.mosque),
                  border: OutlineInputBorder(),
                ),
                items: mosques
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text('${m.name} · ${m.city}'),
                        ))
                    .toList(),
                onChanged: (m) => setState(() => _selectedMosque = m),
              ),
              const SizedBox(height: 12),

              // Crisis type
              DropdownButtonFormField<String>(
                value: _crisisType,
                decoration: const InputDecoration(
                  labelText: 'Crisis type',
                  prefixIcon: Icon(Icons.warning_amber),
                  border: OutlineInputBorder(),
                ),
                items: kAllowedCrisisTypes
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(
                              '${crisisTypeEmoji(t)}  ${crisisTypeLabel(t)}'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _crisisType = v ?? 'general_safety'),
              ),
              const SizedBox(height: 12),

              // Severity
              Text('Severity', style: MTypography.captionEn(context)),
              Slider(
                value: _severity.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                label: 'Severity $_severity',
                onChanged: (v) => setState(() => _severity = v.round()),
              ),
              Text(
                _severity >= 3
                    ? 'High-priority push. Rate limit is waived.'
                    : 'Standard delivery. 1 broadcast per 30 min limit.',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: _severity >= 3 ? MColors.red : MColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),

              // Urdu message
              TextFormField(
                controller: _textUrCtrl,
                maxLength: 280,
                maxLines: 3,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'پیغام (اردو)',
                  hintText: 'مثلاً: علاقے میں شدید بارش متوقع ہے۔',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // English message
              TextFormField(
                controller: _textEnCtrl,
                maxLength: 280,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Message (English)',
                  hintText: 'Heavy rain expected in the area, take precautions.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Radius hint
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: MColors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.adjust, size: 16, color: MColors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Reaches verified users within 3 km. '
                        'Auto-expires after 6 hours.',
                        style: MTypography.captionEn(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _posting ? null : _post,
                  icon: _posting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.campaign),
                  label: Text(_posting ? 'Posting...' : 'Post broadcast'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MColors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyTile(BroadcastDoc b) {
    final status = b.status;
    Color color;
    switch (status) {
      case 'delivered':
        color = MColors.green;
        break;
      case 'flagged':
        color = MColors.red;
        break;
      case 'rejected':
        color = MColors.red;
        break;
      case 'expired':
        color = MColors.textSecondary;
        break;
      default:
        color = MColors.amber;
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(crisisTypeEmoji(b.crisisType)),
        ),
        title: Text(
          b.textEn.isNotEmpty ? b.textEn : b.textUr,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${crisisTypeLabel(b.crisisType)} · sev ${b.severity} · ${b.deliveredCount} delivered',
          style: MTypography.captionEn(context),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            status,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
