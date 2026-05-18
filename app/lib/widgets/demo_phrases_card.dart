/// Demo Phrases Widget — M8 Urdu Voice Reporting.
///
/// Shows the four canonical M8 test phrases from the spec
/// so the demo presenter can tap-to-highlight each one
/// and know what to say during the 30-second demo moment.
///
/// Displayed below the voice recorder in demo mode.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';

/// A phrase in one of the demo languages.
class _DemoPhrase {
  const _DemoPhrase({
    required this.roman,
    required this.urdu,
    required this.english,
    required this.expectedCrisis,
    required this.expectedSeverity,
  });

  final String roman;       // Roman Urdu (as spoken)
  final String urdu;        // Urdu script
  final String english;     // English translation
  final String expectedCrisis;
  final int expectedSeverity;
}

const _demoPhrases = [
  _DemoPhrase(
    roman: '"G-10 markaz ke paas paani bhar gaya, gaariyan phans gayi hain"',
    urdu: '«جی ١٠ مرکز کے پاس پانی بھر گیا، گاڑیاں پھنس گئی ہیں»',
    english: 'Water has filled up near G-10 Markaz, cars are stuck.',
    expectedCrisis: 'urban_flood',
    expectedSeverity: 3,
  ),
  _DemoPhrase(
    roman: '"Lakhani underpass pe ghutnon tak paani hai, koi mat aaye"',
    urdu: '«لاکھانی انڈرپاس پر گھٹنوں تک پانی ہے، کوئی مت آئے»',
    english: 'Knee-deep water at Lakhani underpass, don\'t come here.',
    expectedCrisis: 'flash_flood',
    expectedSeverity: 4,
  ),
  _DemoPhrase(
    roman: '"Sharah-e-Faisal pe Drigh Road ke pass traffic bilkul band hai"',
    urdu: '«شاہراہِ فیصل پر ڈرگ روڈ کے پاس ٹریفک بالکل بند ہے»',
    english: 'Traffic completely blocked on Shahra-e-Faisal near Drigh Road.',
    expectedCrisis: 'road_incident',
    expectedSeverity: 2,
  ),
  _DemoPhrase(
    roman: '"Heavy flooding near Faisal Mosque parking, water rising fast"',
    urdu: '«فیصل مسجد پارکنگ کے قریب شدید سیلاب، پانی تیزی سے بڑھ رہا ہے»',
    english: 'Heavy flooding near Faisal Mosque parking, water rising fast.',
    expectedCrisis: 'flood',
    expectedSeverity: 4,
  ),
];

/// Collapsible card showing the four M8 demo test phrases.
class DemoPhrasesCard extends StatefulWidget {
  const DemoPhrasesCard({super.key});

  @override
  State<DemoPhrasesCard> createState() => _DemoPhrasesCardState();
}

class _DemoPhrasesCardState extends State<DemoPhrasesCard> {
  bool _expanded = false;
  int? _activePhrase;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          // Header — tap to expand/collapse
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.tips_and_updates_outlined,
                      size: 18, color: MColors.amber),
                  const SizedBox(width: 8),
                  Text(
                    'Demo phrases',
                    style: MTypography.titleEn(context).copyWith(
                      fontSize: 14,
                      color: MColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down,
                        color: MColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),

          // Phrase list
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                const Divider(height: 1),
                ...List.generate(_demoPhrases.length, (i) {
                  return _PhraseCard(
                    index: i + 1,
                    phrase: _demoPhrases[i],
                    isActive: _activePhrase == i,
                    onTap: () => setState(() {
                      _activePhrase = _activePhrase == i ? null : i;
                    }),
                  );
                }),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhraseCard extends StatelessWidget {
  const _PhraseCard({
    required this.index,
    required this.phrase,
    required this.isActive,
    required this.onTap,
  });

  final int index;
  final _DemoPhrase phrase;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: isActive
            ? MColors.red.withValues(alpha: 0.06)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Roman Urdu — the "say this" line
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? MColors.red
                        : MColors.red.withValues(alpha: 0.12),
                  ),
                  child: Center(
                    child: Text(
                      '$index',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isActive ? Colors.white : MColors.red,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    phrase.roman,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: MColors.textPrimary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                // Copy button
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: phrase.roman
                        .replaceAll('"', '')
                        .replaceAll('"', '')
                        .replaceAll('"', '')));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Phrase copied'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.copy, size: 16,
                        color: MColors.textSecondary),
                  ),
                ),
              ],
            ),

            // Expanded details
            if (isActive) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Urdu script
                    Text(
                      phrase.urdu,
                      style: GoogleFonts.notoNaskhArabic(
                        fontSize: 13,
                        color: MColors.textSecondary,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 6),
                    // English translation
                    Text(
                      phrase.english,
                      style: MTypography.captionEn(context),
                    ),
                    const SizedBox(height: 8),
                    // Expected output chips
                    Row(
                      children: [
                        _Chip(
                          label: phrase.expectedCrisis,
                          color: MColors.red,
                          icon: Icons.warning_amber_rounded,
                        ),
                        const SizedBox(width: 6),
                        _Chip(
                          label: 'Severity ${phrase.expectedSeverity}',
                          color: MColors.severityColor(phrase.expectedSeverity),
                          icon: Icons.bar_chart,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
