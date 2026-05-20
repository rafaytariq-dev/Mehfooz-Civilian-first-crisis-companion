import 'package:cloud_firestore/cloud_firestore.dart';

/// Seeds essential reference data into Firestore on first run.
/// Safe to call multiple times — checks existence before writing.
class FirestoreSeed {
  static final _db = FirebaseFirestore.instance;

  static Future<void> runIfNeeded() async {
    final marker = await _db.collection('_seed').doc('v1').get();
    if (marker.exists) return;

    await _seedHelplines();
    await _seedSafeSpots();
    await _db.collection('_seed').doc('v1').set({
      'seeded_at': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> _seedHelplines() async {
    final helplines = [
      {
        'name': 'Rescue 1122 Punjab',
        'number': '1122',
        'cities': ['Lahore', 'Rawalpindi', 'Faisalabad', 'Multan', 'Gujranwala'],
        'crisis_types': ['fire', 'road_incident', 'flood', 'medical', 'building_collapse'],
        'language_support': ['ur', 'en'],
        'notes': '24/7. Has water rescue teams in Lahore.',
      },
      {
        'name': 'CARES 1122 Islamabad',
        'number': '1122',
        'cities': ['Islamabad'],
        'crisis_types': ['fire', 'medical', 'road_incident', 'flood', 'building_collapse'],
        'language_support': ['ur', 'en'],
        'notes': 'ICT Capital Territory only. 24/7.',
      },
      {
        'name': 'Chhipa Emergency',
        'number': '1020',
        'cities': ['Karachi', 'Hyderabad', 'Sukkur'],
        'crisis_types': ['medical', 'flood', 'road_incident', 'body_recovery'],
        'language_support': ['ur', 'en'],
        'notes': 'Strong water rescue capacity in Karachi.',
      },
      {
        'name': 'Edhi Foundation',
        'number': '115',
        'cities': ['*'],
        'crisis_types': ['medical', 'ambulance', 'shelter', 'flood'],
        'language_support': ['ur'],
        'notes': 'Nationwide ambulance. Flood relief.',
      },
      {
        'name': 'NDMA',
        'number': '1135',
        'cities': ['*'],
        'crisis_types': ['disaster_coordination', 'flood', 'glof'],
        'language_support': ['ur', 'en'],
        'notes': 'For major disasters and coordination, not individual rescue.',
      },
      {
        'name': 'Alkhidmat Foundation',
        'number': '1023',
        'cities': ['*'],
        'crisis_types': ['shelter', 'flood', 'food_aid'],
        'language_support': ['ur'],
        'notes': 'Volunteer-driven. Strong in flood relief.',
      },
      {
        'name': 'Pakistan Red Crescent',
        'number': '051-9214817',
        'cities': ['Islamabad', 'Rawalpindi'],
        'crisis_types': ['medical', 'flood', 'disaster_coordination'],
        'language_support': ['ur', 'en'],
        'notes': 'Islamabad/Rawalpindi chapter.',
      },
      {
        'name': 'Punjab Emergency Service',
        'number': '1122',
        'cities': ['Punjab'],
        'crisis_types': ['fire', 'medical', 'flood', 'road_incident'],
        'language_support': ['ur', 'en', 'pa'],
        'notes': 'Province-wide Punjab.',
      },
      {
        'name': 'KPK Emergency',
        'number': '1122',
        'cities': ['Peshawar', 'Abbottabad', 'Mardan'],
        'crisis_types': ['fire', 'medical', 'flood'],
        'language_support': ['ur', 'ps'],
        'notes': 'KPK Rescue 1122.',
      },
      {
        'name': 'Sindh Emergency',
        'number': '115',
        'cities': ['Karachi', 'Hyderabad', 'Sukkur', 'Larkana'],
        'crisis_types': ['medical', 'flood', 'fire'],
        'language_support': ['ur', 'sd'],
        'notes': 'Sindh province emergency services.',
      },
      {
        'name': 'Rescue Helpline',
        'number': '1122',
        'cities': ['*'],
        'crisis_types': ['flood', 'fire', 'medical'],
        'language_support': ['ur', 'en'],
        'notes': 'General rescue helpline (fallback).',
      },
    ];

    final batch = _db.batch();
    for (final h in helplines) {
      final ref = _db.collection('helplines').doc();
      batch.set(ref, h);
    }
    await batch.commit();
  }

  static Future<void> _seedSafeSpots() async {
    final spots = [
      // Islamabad
      {
        'name': 'Polyclinic Hospital',
        'type': 'hospital',
        'location': const GeoPoint(33.7208, 73.0656),
        'address': 'G-6/2, Islamabad',
        'has_cooling': true,
        'has_medical': true,
        'open_24_7': true,
        'city': 'Islamabad',
      },
      {
        'name': 'Faisal Mosque',
        'type': 'mosque',
        'location': const GeoPoint(33.7295, 73.0372),
        'address': 'Shah Faisal Ave, Islamabad',
        'has_cooling': false,
        'has_medical': false,
        'open_24_7': false,
        'city': 'Islamabad',
      },
      {
        'name': 'PIMS Hospital',
        'type': 'hospital',
        'location': const GeoPoint(33.7184, 73.0511),
        'address': 'G-8, Islamabad',
        'has_cooling': true,
        'has_medical': true,
        'open_24_7': true,
        'city': 'Islamabad',
      },
      {
        'name': 'Centaurus Mall',
        'type': 'mall',
        'location': const GeoPoint(33.7102, 73.0479),
        'address': 'F-8, Islamabad',
        'has_cooling': true,
        'has_medical': false,
        'open_24_7': false,
        'city': 'Islamabad',
      },
      // Karachi
      {
        'name': 'Aga Khan Hospital',
        'type': 'hospital',
        'location': const GeoPoint(24.8918, 67.0809),
        'address': 'Stadium Rd, Karachi',
        'has_cooling': true,
        'has_medical': true,
        'open_24_7': true,
        'city': 'Karachi',
      },
      {
        'name': 'Dolmen Mall Clifton',
        'type': 'mall',
        'location': const GeoPoint(24.8112, 67.0261),
        'address': 'Block 4, Clifton, Karachi',
        'has_cooling': true,
        'has_medical': false,
        'open_24_7': false,
        'city': 'Karachi',
      },
      // Lahore
      {
        'name': 'Services Hospital Lahore',
        'type': 'hospital',
        'location': const GeoPoint(31.5546, 74.3185),
        'address': 'Jail Rd, Lahore',
        'has_cooling': true,
        'has_medical': true,
        'open_24_7': true,
        'city': 'Lahore',
      },
      {
        'name': 'Emporium Mall Lahore',
        'type': 'mall',
        'location': const GeoPoint(31.4810, 74.3025),
        'address': 'Johar Town, Lahore',
        'has_cooling': true,
        'has_medical': false,
        'open_24_7': false,
        'city': 'Lahore',
      },
    ];

    final batch = _db.batch();
    for (final s in spots) {
      final ref = _db.collection('safe_spots').doc();
      batch.set(ref, s);
    }
    await batch.commit();
  }
}
