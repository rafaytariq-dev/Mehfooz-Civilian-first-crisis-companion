# M1 — Data Spine: Implementation Prompt

> Hand this entire prompt to an AI coding assistant (Cursor, Gemini in Antigravity, Claude Code, etc.) to complete M1 in full. M0 is already done — the repo exists, Firebase is initialized, GCP project `mehfooz-prod` is live, and the monorepo layout is in place.

---

## Your Mission

Implement **M1 — Data Spine** for the Mehfooz (محفوظ) project. Your job is to:

1. Define and deploy every Firestore collection and its schema
2. Create all required Firestore composite indexes
3. Populate all static seed data (helplines, safe spots, flood-prone locations)
4. Generate the G-10/G-11 Islamabad flash flood scenario seed data (citizen reports, weather replay, social signals)
5. Write and validate a replay script that streams the demo scenario into Firestore
6. Deploy the mock dispatch Cloud Function

When you are done, every downstream agent (M2 through M6) must have real, queryable data to consume without writing a single line of data themselves.

---

## Repository Context

```
mehfooz/
├── app/                 # Flutter (not your concern in M1)
├── agents/              # Python ADK agents (not your concern in M1)
├── functions/           # Cloud Functions (TypeScript) ← you will add here
├── web/                 # React dashboard (not your concern in M1)
├── data/                # Seed datasets ← primary output folder
│   ├── helplines.json
│   ├── safe_spots.json
│   ├── flood_prone_locations.json
│   ├── seed_reports.json
│   ├── seed_weather.json
│   ├── seed_social.json
│   └── replay_scenario.py
├── docs/
└── GEMINI.md
```

GCP project: `mehfooz-prod`
Firestore mode: Native
Region: `asia-south1`
Service account for Cloud Functions: `functions-runtime@mehfooz-prod.iam.gserviceaccount.com`

---

## Step 1 — Deploy Firestore Security Rules

Create `firestore.rules` at the repo root:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Users: only the owner can read/write their own doc
    match /users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }

    // Reports: authenticated users can create; owner can update
    match /reports/{reportId} {
      allow create: if request.auth != null;
      allow read: if request.auth != null;
      allow update: if request.auth != null && request.auth.uid == resource.data.user_id;
    }

    // All signal collections: agents read/write via service account (server-side only)
    // Mobile clients read signals_weather and signals_traffic for display
    match /signals_weather/{id} { allow read: if request.auth != null; }
    match /signals_traffic/{id} { allow read: if request.auth != null; }
    match /signals_social/{id}  { allow read: if request.auth != null; }

    // Events: all authenticated users can read
    match /events/{id} { allow read: if request.auth != null; }

    // Reference data: public read
    match /helplines/{id}              { allow read: if true; }
    match /safe_spots/{id}             { allow read: if true; }
    match /flood_prone_locations/{id}  { allow read: if true; }

    // Plans, simulation reports, traces: server-side only
    match /plans/{id}               { allow read: if request.auth != null; }
    match /simulation_reports/{id}  { allow read: if request.auth != null; }
    match /agent_traces/{id}        { allow read: if request.auth != null; }
    match /mock_dispatches/{id}     { allow read: if request.auth != null; }
    match /push_queue/{id}          { allow read: if request.auth != null; }

    // Broadcasts and mosques
    match /broadcasts/{id} { allow read: if request.auth != null; }
    match /mosques/{id}    { allow read: if request.auth != null; }
  }
}
```

Deploy with: `firebase deploy --only firestore:rules`

---

## Step 2 — Deploy Firestore Indexes

Create `firestore.indexes.json` at the repo root. These exact composite indexes are required by the agents:

```json
{
  "indexes": [
    {
      "collectionGroup": "reports",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "location", "order": "ASCENDING" },
        { "fieldPath": "created_at", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "reports",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "linked_event_id", "order": "ASCENDING" },
        { "fieldPath": "created_at", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "events",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "last_updated", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "signals_social",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "location_inferred", "order": "ASCENDING" },
        { "fieldPath": "posted_at", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "broadcasts",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "expires_at", "order": "ASCENDING" },
        { "fieldPath": "created_at", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "agent_traces",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "event_id", "order": "ASCENDING" },
        { "fieldPath": "created_at", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "mock_dispatches",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "received_at", "order": "DESCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
```

Deploy with: `firebase deploy --only firestore:indexes`

---

## Step 3 — Firestore Schema Reference

Every collection agent M2–M6 will read from or write to. Do NOT change field names — they are hardcoded in agent tools.

### `users/{uid}`
```typescript
{
  uid: string,
  phone: string,                    // E.164, e.g. "+923001234567"
  display_name: string,
  language: 'ur' | 'en' | 'roman_ur',
  city: string,
  emergency_contacts: Array<{ name: string, phone: string, relation: string }>,
  role: 'citizen' | 'mosque_admin' | 'verified_reporter',
  reputation: number,               // 0–100, new users start at 50
  last_known_location: GeoPoint,
  last_location_at: Timestamp,
  fcm_token: string,
  women_safe_route: boolean,
  created_at: Timestamp
}
```

### `reports/{report_id}`
```typescript
{
  report_id: string,
  user_id: string,
  text_raw: string,
  text_normalized: string,          // English translation for agents
  language_detected: string,        // 'ur' | 'roman_ur' | 'en'
  voice_url?: string,               // Cloud Storage gs:// URL
  photo_urls: string[],
  location: GeoPoint,
  geo_accuracy_m: number,
  crisis_type_user?: string,
  crisis_type_inferred?: string,
  severity_user?: 1 | 2 | 3 | 4 | 5,
  created_at: Timestamp,
  vision_verified: boolean,
  vision_confidence: number,        // 0–1
  linked_event_id?: string
}
```

### `signals_weather/{signal_id}`
```typescript
{
  source: 'open_meteo' | 'pmd' | 'replay',
  location: GeoPoint,
  city: string,
  rainfall_mm_1h: number,
  rainfall_mm_24h: number,
  temp_c: number,
  humidity: number,
  wind_kph: number,
  recorded_at: Timestamp,
  fetched_at: Timestamp
}
```

### `signals_traffic/{signal_id}`
```typescript
{
  source: 'google_maps',
  origin: GeoPoint,
  destination: GeoPoint,
  duration_normal_s: number,
  duration_now_s: number,
  congestion_ratio: number,         // duration_now / duration_normal
  recorded_at: Timestamp
}
```

### `signals_social/{signal_id}`
```typescript
{
  source: 'twitter' | 'facebook',
  text: string,
  language: string,
  location_inferred?: GeoPoint,
  posted_at: Timestamp,
  author_handle: string,
  url: string,
  media_urls: string[]
}
```

### `events/{event_id}`
```typescript
{
  event_id: string,
  type: string,                     // from crisis taxonomy
  polygon: GeoPoint[],              // bounding polygon of the event area
  centroid: GeoPoint,
  severity: 1 | 2 | 3 | 4 | 5,
  confidence: number,               // 0–1
  status: 'candidate' | 'verified' | 'resolved',
  explanation_en: string,
  explanation_ur: string,
  contributing_signals: {
    reports: string[],
    weather: string[],
    traffic: string[],
    social: string[]
  },
  started_at: Timestamp,
  last_updated: Timestamp,
  resolved_at?: Timestamp
}
```

### `helplines/{helpline_id}`
```typescript
{
  name: string,
  number: string,
  cities: string[],
  crisis_types: string[],
  language_support: string[],
  notes: string
}
```

### `safe_spots/{spot_id}`
```typescript
{
  name: string,
  type: 'hospital' | 'mosque' | 'mall' | 'school' | 'gov_building',
  location: GeoPoint,
  address: string,
  capacity?: number,
  has_cooling: boolean,
  has_medical: boolean,
  open_24_7: boolean,
  source: 'google_places' | 'manual'
}
```

### `flood_prone_locations/{location_id}`
```typescript
{
  name: string,
  city: string,
  location: GeoPoint,
  type: 'underpass' | 'lowlying_road' | 'nullah_bank',
  rainfall_threshold_mm_h: number,  // 1h rainfall (mm) that causes flooding
  historical_notes: string,
  warn_radius_m: number             // typically 2000
}
```

### `agent_traces/{trace_id}` — written by agents, schema for reference
```typescript
{
  trace_id: string,
  event_id?: string,
  agent: 'ingestion' | 'detection' | 'planning' | 'simulation' | 'comms' | 'orchestrator',
  step: string,
  input_summary: string,
  output_summary: string,
  reasoning: string,
  tools_called: Array<{ name: string, args: any, result: any }>,
  duration_ms: number,
  created_at: Timestamp
}
```

### `broadcasts/{broadcast_id}`
```typescript
{
  broadcast_id: string,
  mosque_id: string,
  admin_uid: string,
  text_ur: string,
  text_en: string,
  crisis_type: string,
  radius_m: number,
  expires_at: Timestamp,
  created_at: Timestamp
}
```

### `mosques/{mosque_id}`
```typescript
{
  mosque_id: string,
  name: string,
  location: GeoPoint,
  admin_uids: string[],
  verified_at: Timestamp,
  verified_by: string
}
```

### `plans/{plan_id}` — written by M4 Planning agent, schema for reference
```typescript
{
  plan_id: string,
  event_id: string,
  created_at: Timestamp,
  system_actions: Array<{
    type: 'notify_helpline' | 'flag_route' | 'broadcast_zone',
    target: string,
    payload: object,
    urgency: 'low' | 'med' | 'high' | 'sos'
  }>,
  user_actions: {
    [user_id: string]: {
      verb: string,
      message_en: string,
      message_ur: string,
      route_alternatives?: any[],
      safe_spots?: any[],
      helpline?: any,
      urgency: 'low' | 'med' | 'high' | 'sos'
    }
  }
}
```

### `push_queue/{id}` — written by M5, read by M6
```typescript
{
  user_id: string,
  payload: object,
  urgency: 'low' | 'med' | 'high' | 'sos',
  created_at: Timestamp,
  sent: boolean
}
```

### `mock_dispatches/{id}` — written by mock Cloud Function
```typescript
{
  ticket_id: string,
  received_at: Timestamp,
  authority: string,
  payload: object,
  status: 'received' | 'queued'
}
```

### `simulation_reports/{report_id}` — written by M5
```typescript
{
  report_id: string,
  plan_id: string,
  event_id: string,
  executed_at: Timestamp,
  dispatches: Array<{ authority: string, ticket_id: string, payload_summary: string }>,
  notifications_queued: { sos: number, high: number, med: number, low: number, total_users: number },
  routes_flagged: number,
  estimated_congestion_reduction_min: number,
  summary_en: string,
  summary_ur: string
}
```

---

## Step 4 — Build `data/helplines.json`

Create this file with **at minimum 30 entries** covering Islamabad, Rawalpindi, Karachi, and Lahore.

Required entries (do not omit these — agents look them up by city + crisis_type at runtime):

```json
[
  {
    "helpline_id": "rescue-1122-ict",
    "name": "Rescue 1122 ICT / CARES",
    "number": "1122",
    "cities": ["Islamabad"],
    "crisis_types": ["flood", "urban_flood", "flash_flood", "fire", "road_incident", "building_collapse"],
    "language_support": ["ur", "en"],
    "notes": "24/7, water rescue, trauma response, Islamabad Capital Territory"
  },
  {
    "helpline_id": "rescue-1122-punjab",
    "name": "Rescue 1122 Punjab",
    "number": "1122",
    "cities": ["Lahore", "Rawalpindi"],
    "crisis_types": ["flood", "urban_flood", "flash_flood", "fire", "road_incident", "building_collapse"],
    "language_support": ["ur", "en"],
    "notes": "24/7, provincial emergency service Punjab"
  },
  {
    "helpline_id": "edhi-karachi",
    "name": "Edhi Foundation Karachi",
    "number": "115",
    "cities": ["Karachi"],
    "crisis_types": ["flood", "urban_flood", "road_incident", "building_collapse"],
    "language_support": ["ur", "en", "roman_ur"],
    "notes": "24/7 ambulance and rescue, nationwide but HQ Karachi"
  },
  {
    "helpline_id": "chhipa-karachi",
    "name": "Chhipa Welfare Association",
    "number": "1020",
    "cities": ["Karachi"],
    "crisis_types": ["flood", "urban_flood", "road_incident", "fire"],
    "language_support": ["ur", "roman_ur"],
    "notes": "24/7 ambulance and rescue Karachi"
  },
  {
    "helpline_id": "pdma-punjab",
    "name": "PDMA Punjab Helpline",
    "number": "0800-02345",
    "cities": ["Lahore", "Rawalpindi"],
    "crisis_types": ["flood", "flash_flood", "glof"],
    "language_support": ["ur", "en"],
    "notes": "Provincial Disaster Management Authority Punjab"
  },
  {
    "helpline_id": "ndma-national",
    "name": "NDMA National Helpline",
    "number": "1700",
    "cities": ["Islamabad", "Rawalpindi", "Karachi", "Lahore"],
    "crisis_types": ["flood", "flash_flood", "glof", "building_collapse"],
    "language_support": ["ur", "en"],
    "notes": "National Disaster Management Authority — national coverage"
  },
  {
    "helpline_id": "alkhidmat-national",
    "name": "Al-Khidmat Foundation",
    "number": "042-35761999",
    "cities": ["Islamabad", "Rawalpindi", "Lahore", "Karachi"],
    "crisis_types": ["flood", "urban_flood", "heatwave"],
    "language_support": ["ur", "roman_ur"],
    "notes": "Relief and rescue, all major cities"
  },
  {
    "helpline_id": "jdc-karachi",
    "name": "JDC Foundation Karachi",
    "number": "021-111-532-532",
    "cities": ["Karachi"],
    "crisis_types": ["flood", "urban_flood", "fire", "road_incident"],
    "language_support": ["ur", "roman_ur"],
    "notes": "24/7 Karachi emergency welfare"
  },
  {
    "helpline_id": "pwd-islamabad",
    "name": "CDA Emergency (Roads/Drainage)",
    "number": "051-9252626",
    "cities": ["Islamabad"],
    "crisis_types": ["urban_flood", "road_incident", "power_outage"],
    "language_support": ["ur", "en"],
    "notes": "Capital Development Authority roads and drainage emergency"
  },
  {
    "helpline_id": "wasa-lahore",
    "name": "WASA Lahore Emergency",
    "number": "042-99200301",
    "cities": ["Lahore"],
    "crisis_types": ["urban_flood", "power_outage"],
    "language_support": ["ur"],
    "notes": "Water and Sanitation Authority Lahore — drainage complaints"
  }
]
```

Fill the remaining **20+ entries** covering: Karachi Water Board, KWSB, Lahore PDMA district, Rawalpindi RDA, fire brigades (all 4 cities), heatwave health helplines (DEWS), air quality, police emergency (15), and Pakistan Red Crescent.

---

## Step 5 — Build `data/flood_prone_locations.json`

Create with **at minimum 50 entries**. Use real coordinates. Required entries:

**Karachi (min 15):**
- Lakhani Underpass (~24.8900, 67.0650), threshold: 25mm/h
- Nazimabad No. 7 Underpass (~24.9200, 67.0500), threshold: 20mm/h
- Liaqatabad Underpass (~24.9050, 67.0480), threshold: 20mm/h
- Gulshan Chowrangi area (~24.9230, 67.0890), threshold: 30mm/h
- Surjani Town low-lying road, threshold: 18mm/h
- Malir Nullah bank (~24.9150, 67.1800), threshold: 15mm/h
- Orangi Town drain bank (~24.9400, 67.0100), threshold: 15mm/h
- Korangi Creek area, threshold: 12mm/h
- Hawks Bay Road dip, threshold: 25mm/h
- North Karachi sector 11-C low road, threshold: 20mm/h
- Shahra-e-Faisal depression near Drigh Road, threshold: 22mm/h
- Paposh Nagar nullah bank, threshold: 15mm/h
- Baldia Town floodplain, threshold: 18mm/h
- Site Area Nullah crossing, threshold: 20mm/h
- Landhi industrial low road, threshold: 25mm/h

**Lahore (min 10):**
- Kalma Chowk Underpass (~31.5100, 74.3300), threshold: 35mm/h
- Lawrence Road dip (~31.5550, 74.3250), threshold: 30mm/h
- Jail Road underpass (~31.5250, 74.3400), threshold: 30mm/h
- Johar Town nullah bank (~31.4700, 74.2800), threshold: 25mm/h
- Model Town link road low point, threshold: 28mm/h
- Gulberg III interior roads, threshold: 35mm/h
- DHA Phase 6 nullah crossing, threshold: 20mm/h
- Raiwind Road seasonal flood zone, threshold: 22mm/h
- Shahdara nullah bank, threshold: 15mm/h
- Sagian Bridge approaches, threshold: 12mm/h

**Islamabad/Rawalpindi (min 15):**
- Faizabad Interchange underpass (~33.7100, 72.0350), threshold: 28mm/h — **this is the G-10 demo area**
- IJP Road dip near G-10 Markaz (~33.6920, 72.0130), threshold: 25mm/h — **primary demo location**
- G-11 Markaz low road (~33.7020, 72.0050), threshold: 25mm/h
- Murree Road Rawalpindi dip (~33.6000, 73.0500), threshold: 30mm/h
- Saddar Rawalpindi storm drain overflow (~33.5980, 73.0430), threshold: 25mm/h
- Chaklala Scheme 3 low road (~33.6200, 73.0700), threshold: 28mm/h
- Nullah Leh bank Rawalpindi (~33.5750, 73.0200), threshold: 15mm/h
- Soan River bank Islamabad (~33.6400, 72.9800), threshold: 12mm/h
- F-10 Markaz road depression (~33.7050, 72.9780), threshold: 30mm/h
- Blue Area underpass (~33.7280, 73.0930), threshold: 35mm/h
- I-8 sector nullah bank (~33.6850, 73.0650), threshold: 20mm/h
- H-8 Islamabad drain overflow (~33.6700, 73.0450), threshold: 22mm/h
- Rawat area road dip (~33.5600, 73.2000), threshold: 20mm/h
- Golra Mor underpass (~33.7200, 72.9600), threshold: 28mm/h
- Tarnol low road (~33.6900, 72.8700), threshold: 22mm/h

Format each entry exactly as:
```json
{
  "location_id": "faizabad-underpass-isb",
  "name": "Faizabad Interchange Underpass",
  "city": "Islamabad",
  "location": { "latitude": 33.7100, "longitude": 72.0350 },
  "type": "underpass",
  "rainfall_threshold_mm_h": 28,
  "historical_notes": "Floods within 30 min of sustained 28mm/h rainfall. Recorded flooding events in 2022 and 2025 monsoon.",
  "warn_radius_m": 2000
}
```

---

## Step 6 — Build `data/safe_spots.json`

Create with **at minimum 200 entries across all 4 cities** (50 per city). Pull from real places. Each city needs:
- 10+ hospitals
- 10+ major mosques
- 5+ large malls/shopping centres
- 5+ government buildings
- 5+ schools/universities that double as safe spots

**Critical Islamabad entries (must exist for demo):**
- PIMS Hospital (Pakistan Institute of Medical Sciences)
- Shifa International Hospital
- Polyclinic Hospital Islamabad
- Faisal Mosque (massive open courtyard, cooling)
- Islamabad Club
- Centaurus Mall
- F-6 Markaz Super Market area (high ground)
- G-10 Markaz (high ground portion)
- Capital Hospital

Format:
```json
{
  "spot_id": "pims-islamabad",
  "name": "Pakistan Institute of Medical Sciences (PIMS)",
  "type": "hospital",
  "location": { "latitude": 33.7200, "longitude": 73.0600 },
  "address": "G-8/3, Islamabad",
  "capacity": 1500,
  "has_cooling": true,
  "has_medical": true,
  "open_24_7": true,
  "source": "manual"
}
```

---

## Step 7 — Build G-10 Flood Scenario Seed Data

This is the demo scenario. All timestamps are **relative** — the replay script will shift them to `now` when run.

### `data/seed_users.json` — 8 demo users

Create 8 users representing the demo personas:

```json
[
  {
    "uid": "demo-aisha-001",
    "phone": "+923001110001",
    "display_name": "Aisha Rehman",
    "language": "roman_ur",
    "city": "Islamabad",
    "emergency_contacts": [
      { "name": "Ali Rehman", "phone": "+923001110099", "relation": "husband" }
    ],
    "role": "citizen",
    "reputation": 65,
    "last_known_location": { "latitude": 33.6920, "longitude": 72.0130 },
    "women_safe_route": true
  },
  {
    "uid": "demo-bilal-002",
    "phone": "+923001110002",
    "display_name": "Bilal Khan",
    "language": "ur",
    "city": "Islamabad",
    "emergency_contacts": [],
    "role": "citizen",
    "reputation": 50,
    "last_known_location": { "latitude": 33.6980, "longitude": 72.0200 },
    "women_safe_route": false
  },
  {
    "uid": "demo-sara-003",
    "phone": "+923001110003",
    "display_name": "Sara Malik",
    "language": "en",
    "city": "Islamabad",
    "emergency_contacts": [
      { "name": "Usman Malik", "phone": "+923001110088", "relation": "father" }
    ],
    "role": "citizen",
    "reputation": 50,
    "last_known_location": { "latitude": 33.6950, "longitude": 72.0090 },
    "women_safe_route": true
  },
  {
    "uid": "demo-ahmed-004",
    "phone": "+971501234567",
    "display_name": "Ahmed Siddiqui (Dubai)",
    "language": "en",
    "city": "Islamabad",
    "emergency_contacts": [
      { "name": "Ammi Siddiqui", "phone": "+923001110077", "relation": "mother" }
    ],
    "role": "citizen",
    "reputation": 50,
    "last_known_location": { "latitude": 33.6910, "longitude": 72.0070 },
    "women_safe_route": false
  },
  {
    "uid": "demo-mosque-admin-005",
    "phone": "+923001110005",
    "display_name": "Hafiz Tariq (G-10 Mosque)",
    "language": "ur",
    "city": "Islamabad",
    "emergency_contacts": [],
    "role": "mosque_admin",
    "reputation": 80,
    "last_known_location": { "latitude": 33.6930, "longitude": 72.0110 },
    "women_safe_route": false
  },
  {
    "uid": "demo-reporter-006",
    "phone": "+923001110006",
    "display_name": "Zara Hussain (Verified Reporter)",
    "language": "ur",
    "city": "Islamabad",
    "emergency_contacts": [],
    "role": "verified_reporter",
    "reputation": 75,
    "last_known_location": { "latitude": 33.6900, "longitude": 72.0150 },
    "women_safe_route": true
  },
  {
    "uid": "demo-citizen-007",
    "phone": "+923001110007",
    "display_name": "Imran Butt",
    "language": "roman_ur",
    "city": "Islamabad",
    "emergency_contacts": [],
    "role": "citizen",
    "reputation": 50,
    "last_known_location": { "latitude": 33.7010, "longitude": 72.0180 },
    "women_safe_route": false
  },
  {
    "uid": "demo-citizen-008",
    "phone": "+923001110008",
    "display_name": "Fatima Noor",
    "language": "ur",
    "city": "Islamabad",
    "emergency_contacts": [
      { "name": "Noor Baji", "phone": "+923001110066", "relation": "sister" }
    ],
    "role": "citizen",
    "reputation": 55,
    "last_known_location": { "latitude": 33.6940, "longitude": 72.0060 },
    "women_safe_route": true
  }
]
```

### `data/seed_reports.json` — 20 citizen reports over 90 minutes

Reports must be in mixed languages (Urdu, Roman Urdu, English) and spread over T-90min to T-0 relative to demo start. G-10/G-11 Islamabad area (lat ~33.69–33.71, lon ~72.00–72.03).

Create 20 reports. Examples to include and expand upon:

```json
[
  {
    "report_id": "rpt-001",
    "user_id": "demo-aisha-001",
    "text_raw": "F-10 markaz ke paas paani bhar raha hai, ghutnon tak aa gaya hai",
    "text_normalized": "Water is flooding near F-10 Markaz, it has reached knee level",
    "language_detected": "roman_ur",
    "photo_urls": [],
    "location": { "latitude": 33.6920, "longitude": 72.0130 },
    "geo_accuracy_m": 15,
    "crisis_type_user": "flood",
    "severity_user": 3,
    "t_offset_min": -85,
    "vision_verified": false,
    "vision_confidence": 0.0
  },
  {
    "report_id": "rpt-002",
    "user_id": "demo-citizen-007",
    "text_raw": "G-10/1 mein sadak par paani hi paani, gaari band ho gayi",
    "text_normalized": "There is water all over the road in G-10/1, the car has stalled",
    "language_detected": "roman_ur",
    "photo_urls": ["gs://mehfooz-prod-seed/flood_g10_001.jpg"],
    "location": { "latitude": 33.6950, "longitude": 72.0100 },
    "geo_accuracy_m": 20,
    "crisis_type_user": "urban_flood",
    "severity_user": 3,
    "t_offset_min": -80,
    "vision_verified": true,
    "vision_confidence": 0.88
  },
  {
    "report_id": "rpt-003",
    "user_id": "demo-reporter-006",
    "text_raw": "G-11 markaz ke neeche wali road completely block hai, pedestrians phans gaye hain",
    "text_normalized": "The road below G-11 Markaz is completely blocked, pedestrians are trapped",
    "language_detected": "roman_ur",
    "photo_urls": ["gs://mehfooz-prod-seed/flood_g11_001.jpg"],
    "location": { "latitude": 33.7020, "longitude": 72.0050 },
    "geo_accuracy_m": 10,
    "crisis_type_user": "urban_flood",
    "severity_user": 4,
    "t_offset_min": -75,
    "vision_verified": true,
    "vision_confidence": 0.92
  },
  {
    "report_id": "rpt-004",
    "user_id": "demo-bilal-002",
    "text_raw": "پانی بہت تیزی سے بڑھ رہا ہے جی ٹین میں، گھٹنوں سے اوپر ہو گیا",
    "text_normalized": "Water is rising very fast in G-10, it has risen above the knees",
    "language_detected": "ur",
    "photo_urls": [],
    "location": { "latitude": 33.6980, "longitude": 72.0200 },
    "geo_accuracy_m": 25,
    "crisis_type_user": "flood",
    "severity_user": 4,
    "t_offset_min": -70,
    "vision_verified": false,
    "vision_confidence": 0.0
  },
  {
    "report_id": "rpt-005",
    "user_id": "demo-sara-003",
    "text_raw": "Heavy flooding on IJP Road, can't pass. Vehicles stuck everywhere.",
    "text_normalized": "Heavy flooding on IJP Road, can't pass. Vehicles stuck everywhere.",
    "language_detected": "en",
    "photo_urls": [],
    "location": { "latitude": 33.6910, "longitude": 72.0070 },
    "geo_accuracy_m": 18,
    "crisis_type_user": "urban_flood",
    "severity_user": 3,
    "t_offset_min": -65,
    "vision_verified": false,
    "vision_confidence": 0.0
  }
]
```

**Write 15 more reports** following the same pattern with:
- Varying t_offset_min from -60 to -5
- Locations spreading across G-10 and G-11 (lat 33.69–33.71, lon 72.00–72.03)
- Mix of Urdu, Roman Urdu, and English
- 3–4 reports with photo_urls and vision_verified=true
- Severity escalating over time (mostly 3–4, one severity 5 at T-10min)
- One report near T-5min saying "paani aur zyada ho gaya, rescue chahiye" (severity 5)

### `data/seed_weather.json` — Weather replay data

Create 10 hourly snapshots for Islamabad, based on real 2025 monsoon data. Timestamps use t_offset_hour relative to demo start.

```json
[
  {
    "signal_id": "wx-001",
    "source": "replay",
    "location": { "latitude": 33.6938, "longitude": 73.0651 },
    "city": "Islamabad",
    "rainfall_mm_1h": 8.2,
    "rainfall_mm_24h": 22.4,
    "temp_c": 29.5,
    "humidity": 82,
    "wind_kph": 12,
    "t_offset_hour": -5
  },
  {
    "signal_id": "wx-002",
    "source": "replay",
    "location": { "latitude": 33.6938, "longitude": 73.0651 },
    "city": "Islamabad",
    "rainfall_mm_1h": 18.5,
    "rainfall_mm_24h": 40.9,
    "temp_c": 27.8,
    "humidity": 91,
    "wind_kph": 22,
    "t_offset_hour": -4
  },
  {
    "signal_id": "wx-003",
    "source": "replay",
    "location": { "latitude": 33.6938, "longitude": 73.0651 },
    "city": "Islamabad",
    "rainfall_mm_1h": 31.2,
    "rainfall_mm_24h": 72.1,
    "temp_c": 26.1,
    "humidity": 96,
    "wind_kph": 35,
    "t_offset_hour": -3
  },
  {
    "signal_id": "wx-004",
    "source": "replay",
    "location": { "latitude": 33.6938, "longitude": 73.0651 },
    "city": "Islamabad",
    "rainfall_mm_1h": 38.6,
    "rainfall_mm_24h": 110.7,
    "temp_c": 25.5,
    "humidity": 98,
    "wind_kph": 41,
    "t_offset_hour": -2
  },
  {
    "signal_id": "wx-005",
    "source": "replay",
    "location": { "latitude": 33.6938, "longitude": 73.0651 },
    "city": "Islamabad",
    "rainfall_mm_1h": 42.1,
    "rainfall_mm_24h": 152.8,
    "temp_c": 25.0,
    "humidity": 99,
    "wind_kph": 38,
    "t_offset_hour": -1
  },
  {
    "signal_id": "wx-006",
    "source": "replay",
    "location": { "latitude": 33.6938, "longitude": 73.0651 },
    "city": "Islamabad",
    "rainfall_mm_1h": 29.4,
    "rainfall_mm_24h": 182.2,
    "temp_c": 25.2,
    "humidity": 99,
    "wind_kph": 30,
    "t_offset_hour": 0
  }
]
```

Add 4 more entries for t_offset_hour 1–4 showing rainfall tapering off (for resolved event demo).

### `data/seed_social.json` — Pre-scraped social signals

Create 15 anonymized tweet-like entries relevant to G-10/G-11 flooding:

```json
[
  {
    "signal_id": "soc-001",
    "source": "twitter",
    "text": "G-10 Islamabad completely submerged. This is insane. Cars floating. #IslamabadFloods",
    "language": "en",
    "location_inferred": { "latitude": 33.6940, "longitude": 72.0120 },
    "author_handle": "@anon_isb_user1",
    "url": "https://x.com/anon_isb_user1/status/demo001",
    "media_urls": [],
    "t_offset_min": -72
  },
  {
    "signal_id": "soc-002",
    "source": "twitter",
    "text": "جی گیارہ مرکز کے پاس سڑک ڈوب گئی ہے۔ PDMA کو فوری ایکشن لینا چاہیے #اسلام_آباد_سیلاب",
    "language": "ur",
    "location_inferred": { "latitude": 33.7020, "longitude": 72.0060 },
    "author_handle": "@anon_isb_user2",
    "url": "https://x.com/anon_isb_user2/status/demo002",
    "media_urls": [],
    "t_offset_min": -68
  }
]
```

Write 13 more entries covering the 90-minute window. Include a mix of Urdu and English. Some should have `location_inferred: null` (not all tweets are geotagged).

### `data/seed_traffic.json` — Traffic anomaly signals

Create 5 traffic signal entries showing congestion ratio spiking in G-10/G-11:

```json
[
  {
    "signal_id": "trf-001",
    "source": "google_maps",
    "origin": { "latitude": 33.6800, "longitude": 71.9900 },
    "destination": { "latitude": 33.7100, "longitude": 72.0300 },
    "duration_normal_s": 480,
    "duration_now_s": 1920,
    "congestion_ratio": 4.0,
    "t_offset_min": -60
  },
  {
    "signal_id": "trf-002",
    "source": "google_maps",
    "origin": { "latitude": 33.6850, "longitude": 72.0000 },
    "destination": { "latitude": 33.7050, "longitude": 72.0400 },
    "duration_normal_s": 360,
    "duration_now_s": 2160,
    "congestion_ratio": 6.0,
    "t_offset_min": -45
  }
]
```

Add 3 more entries showing congestion_ratio between 3.5 and 8.0.

---

## Step 8 — Write the Replay Script

Create `data/replay_scenario.py`:

```python
#!/usr/bin/env python3
"""
Replay the G-10/G-11 Islamabad flash flood scenario into Firestore.
Usage: python data/replay_scenario.py g10 [--speed 1.0] [--dry-run]

--speed: multiplier for replay. 1.0 = real-time. 60 = 1 minute of demo = 1 sec.
--dry-run: print what would be written without writing.
"""

import argparse
import json
import time
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore

DATA_DIR = Path(__file__).parent

def load_json(filename):
    with open(DATA_DIR / filename) as f:
        return json.load(f)

def init_firestore():
    if not firebase_admin._apps:
        cred = credentials.ApplicationDefault()
        firebase_admin.initialize_app(cred, {'projectId': 'mehfooz-prod'})
    return firestore.client()

def replay_g10(speed: float, dry_run: bool):
    db = None if dry_run else init_firestore()
    now = datetime.now(timezone.utc)

    reports = load_json("seed_reports.json")
    weather = load_json("seed_weather.json")
    social  = load_json("seed_social.json")
    traffic = load_json("seed_traffic.json")
    users   = load_json("seed_users.json")

    # Seed reference data first (idempotent — skip if already exists)
    seed_static(db, dry_run)

    # Seed users (idempotent)
    seed_users(db, users, now, dry_run)

    # Sort all events by their offset, then emit in order with real-time delay
    events = []
    for r in reports:
        events.append(('report', r, r['t_offset_min'] * 60))
    for w in weather:
        events.append(('weather', w, w['t_offset_hour'] * 3600))
    for s in social:
        events.append(('social', s, s['t_offset_min'] * 60))
    for t in traffic:
        events.append(('traffic', t, t['t_offset_min'] * 60))

    events.sort(key=lambda x: x[2])

    prev_offset = events[0][2]
    for kind, doc, offset_s in events:
        delay = (offset_s - prev_offset) / speed
        if delay > 0:
            print(f"[replay] sleeping {delay:.1f}s (speed={speed}x)...")
            time.sleep(delay)
        prev_offset = offset_s

        ts = now + timedelta(seconds=offset_s)
        write_event(db, kind, doc, ts, dry_run)

    print("[replay] G-10 scenario complete.")

def seed_static(db, dry_run):
    """Write helplines, flood_prone_locations, safe_spots — skip if collection already has docs."""
    for collection, filename in [
        ('helplines', 'helplines.json'),
        ('flood_prone_locations', 'flood_prone_locations.json'),
        ('safe_spots', 'safe_spots.json'),
    ]:
        docs = load_json(filename)
        for doc in docs:
            doc_id = doc.get('helpline_id') or doc.get('location_id') or doc.get('spot_id')
            print(f"[seed] {collection}/{doc_id}")
            if not dry_run:
                db.collection(collection).document(doc_id).set(doc, merge=True)

def seed_users(db, users, now, dry_run):
    for u in users:
        uid = u['uid']
        payload = {**u,
            'last_location_at': now,
            'created_at': now - timedelta(days=30),
            'fcm_token': f'demo-fcm-token-{uid}',
            'last_known_location': firestore.GeoPoint(
                u['last_known_location']['latitude'],
                u['last_known_location']['longitude']
            ) if not dry_run else u['last_known_location']
        }
        print(f"[seed] users/{uid}")
        if not dry_run:
            db.collection('users').document(uid).set(payload, merge=True)

def write_event(db, kind, doc, ts, dry_run):
    if kind == 'report':
        col = 'reports'
        doc_id = doc['report_id']
        payload = {**doc,
            'created_at': ts,
            'location': firestore.GeoPoint(
                doc['location']['latitude'], doc['location']['longitude']
            ) if not dry_run else doc['location']
        }
        payload.pop('t_offset_min', None)

    elif kind == 'weather':
        col = 'signals_weather'
        doc_id = doc['signal_id']
        payload = {**doc,
            'recorded_at': ts,
            'fetched_at': ts,
            'location': firestore.GeoPoint(
                doc['location']['latitude'], doc['location']['longitude']
            ) if not dry_run else doc['location']
        }
        payload.pop('t_offset_hour', None)

    elif kind == 'social':
        col = 'signals_social'
        doc_id = doc['signal_id']
        loc = doc.get('location_inferred')
        payload = {**doc,
            'posted_at': ts,
            'location_inferred': firestore.GeoPoint(loc['latitude'], loc['longitude'])
                if (loc and not dry_run) else loc
        }
        payload.pop('t_offset_min', None)

    elif kind == 'traffic':
        col = 'signals_traffic'
        doc_id = doc['signal_id']
        payload = {**doc,
            'recorded_at': ts,
            'origin': firestore.GeoPoint(
                doc['origin']['latitude'], doc['origin']['longitude']
            ) if not dry_run else doc['origin'],
            'destination': firestore.GeoPoint(
                doc['destination']['latitude'], doc['destination']['longitude']
            ) if not dry_run else doc['destination'],
        }
        payload.pop('t_offset_min', None)

    else:
        return

    print(f"[{ts.strftime('%H:%M:%S')}] writing {col}/{doc_id}")
    if not dry_run:
        db.collection(col).document(doc_id).set(payload)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('scenario', choices=['g10'])
    parser.add_argument('--speed', type=float, default=60.0,
                        help='Replay speed multiplier (default 60 = 1min of scenario per 1sec)')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()

    if args.scenario == 'g10':
        replay_g10(args.speed, args.dry_run)

if __name__ == '__main__':
    main()
```

Add `data/requirements.txt`:
```
firebase-admin>=6.0.0
```

---

## Step 9 — Mock Dispatch Cloud Function

Add to `functions/src/mock_endpoints.ts`:

```typescript
import { onRequest } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const db = getFirestore();

export const mockPdmaDispatch = onRequest(
  { region: 'asia-south1', serviceAccount: 'functions-runtime@mehfooz-prod.iam.gserviceaccount.com' },
  async (req, res) => {
    const ticket_id = `PDMA-${Date.now()}`;
    await db.collection('mock_dispatches').add({
      ticket_id,
      received_at: FieldValue.serverTimestamp(),
      authority: 'PDMA-Punjab',
      payload: req.body,
      status: 'received'
    });
    res.json({ ticket_id, status: 'queued' });
  }
);

export const mockRescue1122 = onRequest(
  { region: 'asia-south1', serviceAccount: 'functions-runtime@mehfooz-prod.iam.gserviceaccount.com' },
  async (req, res) => {
    const ticket_id = `RES1122-${Date.now()}`;
    await db.collection('mock_dispatches').add({
      ticket_id,
      received_at: FieldValue.serverTimestamp(),
      authority: 'Rescue-1122-ICT',
      payload: req.body,
      status: 'received'
    });
    res.json({ ticket_id, status: 'queued' });
  }
);

export const mockTrafficReroute = onRequest(
  { region: 'asia-south1', serviceAccount: 'functions-runtime@mehfooz-prod.iam.gserviceaccount.com' },
  async (req, res) => {
    const ticket_id = `TRAF-${Date.now()}`;
    await db.collection('mock_dispatches').add({
      ticket_id,
      received_at: FieldValue.serverTimestamp(),
      authority: 'CDA-TrafficControl',
      payload: req.body,
      status: 'received'
    });
    res.json({ ticket_id, status: 'queued' });
  }
);

export const mockSmsBlast = onRequest(
  { region: 'asia-south1', serviceAccount: 'functions-runtime@mehfooz-prod.iam.gserviceaccount.com' },
  async (req, res) => {
    const ticket_id = `SMS-${Date.now()}`;
    await db.collection('mock_dispatches').add({
      ticket_id,
      received_at: FieldValue.serverTimestamp(),
      authority: 'SMS-Gateway-Mock',
      payload: req.body,
      status: 'received'
    });
    // IMPORTANT: does NOT send real SMS
    res.json({ ticket_id, status: 'logged_only', note: 'Mock endpoint — no real SMS sent' });
  }
);
```

Export all four from `functions/src/index.ts`. Deploy:
```bash
firebase deploy --only functions:mockPdmaDispatch,mockRescue1122,mockTrafficReroute,mockSmsBlast
```

After deploy, save the four endpoint URLs — M5 (Simulation Agent) needs them.

---

## Step 10 — Firestore TTL Policies

Set TTL policies via GCP Console or CLI to prevent runaway data:

```bash
# signals_social — 24h TTL on posted_at
gcloud firestore fields ttls update posted_at \
  --collection-group=signals_social \
  --enable-ttl \
  --project=mehfooz-prod

# signals_traffic — 6h TTL on recorded_at
gcloud firestore fields ttls update recorded_at \
  --collection-group=signals_traffic \
  --enable-ttl \
  --project=mehfooz-prod
```

Note: TTL in Firestore deletes within 72h of the TTL field, not exactly at expiry. This is acceptable for the demo.

---

## Step 11 — Validation Script

Create `data/validate_m1.py` to confirm M1 exit criteria:

```python
#!/usr/bin/env python3
"""Validates M1 exit criteria. Run after seeding."""

import firebase_admin
from firebase_admin import credentials, firestore

def main():
    if not firebase_admin._apps:
        cred = credentials.ApplicationDefault()
        firebase_admin.initialize_app(cred, {'projectId': 'mehfooz-prod'})
    db = firestore.client()

    checks = []

    # Check helplines ≥ 30
    count = len(db.collection('helplines').get())
    checks.append(('helplines ≥ 30', count >= 30, count))

    # Check flood_prone_locations ≥ 50
    count = len(db.collection('flood_prone_locations').get())
    checks.append(('flood_prone_locations ≥ 50', count >= 50, count))

    # Check safe_spots ≥ 200
    count = len(db.collection('safe_spots').get())
    checks.append(('safe_spots ≥ 200', count >= 200, count))

    # Check reports exist
    count = len(db.collection('reports').get())
    checks.append(('reports seeded', count >= 20, count))

    # Check weather signals
    count = len(db.collection('signals_weather').get())
    checks.append(('signals_weather seeded', count >= 6, count))

    # Check social signals
    count = len(db.collection('signals_social').get())
    checks.append(('signals_social seeded', count >= 15, count))

    # Check users
    count = len(db.collection('users').get())
    checks.append(('demo users seeded', count >= 8, count))

    # Check mock_dispatches collection exists (write one test doc)
    db.collection('mock_dispatches').document('_validate_test').set({'test': True})
    doc = db.collection('mock_dispatches').document('_validate_test').get()
    checks.append(('mock_dispatches writable', doc.exists, 'exists' if doc.exists else 'missing'))
    db.collection('mock_dispatches').document('_validate_test').delete()

    print("\n=== M1 Validation Results ===")
    all_pass = True
    for name, passed, value in checks:
        status = "✅ PASS" if passed else "❌ FAIL"
        print(f"{status} | {name} | value={value}")
        if not passed:
            all_pass = False

    print("\n" + ("✅ ALL CHECKS PASSED — M1 complete." if all_pass else "❌ SOME CHECKS FAILED — fix before handing off."))

if __name__ == '__main__':
    main()
```

---

## Exit Criteria Checklist

Before handing off to the M2 developer, verify every box:

- [ ] `firestore.rules` deployed — confirmed in Firebase Console
- [ ] `firestore.indexes.json` deployed — all indexes in "Enabled" state (may take a few minutes)
- [ ] `data/helplines.json` has ≥ 30 entries including all mandatory ones listed above
- [ ] `data/flood_prone_locations.json` has ≥ 50 entries including G-10/G-11 Islamabad locations
- [ ] `data/safe_spots.json` has ≥ 200 entries including all critical Islamabad entries
- [ ] `python data/replay_scenario.py g10 --dry-run` runs without errors
- [ ] `python data/replay_scenario.py g10 --speed 120` completes and all collections show documents in Firebase Console
- [ ] `python data/validate_m1.py` prints ALL CHECKS PASSED
- [ ] All 4 mock dispatch Cloud Functions deployed and URLs confirmed
- [ ] Mock endpoint POST test: `curl -X POST <mockPdmaDispatch_url> -H "Content-Type: application/json" -d '{"test": true}'` returns `{"ticket_id": "PDMA-...", "status": "queued"}` and the doc appears in `mock_dispatches` in Firestore
- [ ] TTL policies set on `signals_social` and `signals_traffic`
- [ ] Commit everything to `main` with message: `feat(M1): data spine — schema, seed data, replay script, mock endpoints`

---

## What to Hand Off to M2

After M1 is done, document the following in a short comment or PR description for the M2 (Ingestion Agent) developer:

1. **Firestore project:** `mehfooz-prod`
2. **Replay command:** `python data/replay_scenario.py g10 --speed 60`
3. **Mock dispatch URLs:** (paste the 4 deployed function URLs)
4. **Collection names and field names are final** — do not rename without updating this spec
5. **Service account for agents:** `agents-runtime@mehfooz-prod.iam.gserviceaccount.com` has Firestore RW

---

*M1 is a pure data and infrastructure task. No Flutter, no agent logic. Done right, it is invisible — every module that builds on top just works.*
