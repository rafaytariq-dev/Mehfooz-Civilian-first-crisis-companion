# CIRO Pakistan — Implementation Specification

> **Product:** Mehfooz (محفوظ) — civilian-first crisis companion for Pakistan.
> **Stack:** Flutter mobile + Firebase + Google ADK agents on Cloud Run + Gemini 2.5 + Antigravity (dev surface).
> **Demo scenario:** G-10/G-11 Islamabad flash flood, replayed from real 2025 data.
>
> This document is the engineering source of truth. Each module is self-contained: goal, dependencies, schema, code shape, exit criteria. Build P0 modules in dependency order; layer P1–P3 as time allows.

---

## Table of Contents

- [Module Map](#module-map)
- [M0 — Foundations & Project Setup](#m0--foundations--project-setup)
- [M1 — Data Spine](#m1--data-spine)
- [M2 — Ingestion Agent](#m2--ingestion-agent)
- [M3 — Detection & Reasoning Agent](#m3--detection--reasoning-agent)
- [M4 — Planning Agent](#m4--planning-agent)
- [M5 — Simulation Agent](#m5--simulation-agent)
- [M6 — Comms Agent + Orchestrator](#m6--comms-agent--orchestrator)
- [M7 — Mobile App Core (Flutter)](#m7--mobile-app-core-flutter)
- [M8 — Urdu Voice Reporting](#m8--urdu-voice-reporting)
- [M9 — Underpass Flood Radar](#m9--underpass-flood-radar)
- [M10 — Smart Helpline Router](#m10--smart-helpline-router)
- [M11 — Heatwave Personal Advisor](#m11--heatwave-personal-advisor)
- [M12 — Women's Safe Route Layer](#m12--womens-safe-route-layer)
- [M13 — Offline-First Crisis Kit](#m13--offline-first-crisis-kit)
- [M14 — Mosque Admin Broadcast](#m14--mosque-admin-broadcast)
- [M15 — Authority Simulation Dashboard](#m15--authority-simulation-dashboard)
- [M16 — Demo Theater & Submission](#m16--demo-theater--submission)
- [Cross-Cutting Concerns](#cross-cutting-concerns)

---

## Module Map

| # | Module | Layer | Depends on | Priority | Effort |
|---|---|---|---|---|---|
| M0 | Foundations & Project Setup | Infra | — | P0 | 0.5d |
| M1 | Data Spine | Backend | M0 | P0 | 2d |
| M2 | Ingestion Agent | Agent | M1 | P0 | 1.5d |
| M3 | Detection & Reasoning Agent | Agent | M1, M2 | P0 | 2d |
| M4 | Planning Agent | Agent | M1, M3 | P0 | 1.5d |
| M5 | Simulation Agent | Agent | M4 | P0 | 1d |
| M6 | Comms Agent + Orchestrator | Agent | M2–M5 | P0 | 1.5d |
| M7 | Mobile App Core (Flutter) | Frontend | M1, M6 | P0 | 5–7d |
| M8 | Urdu Voice Reporting | Frontend | M7 | P1 | 1d |
| M9 | Underpass Flood Radar | X-cut | M1, M3, M7 | P1 | 1d |
| M10 | Smart Helpline Router | X-cut | M1, M4, M7 | P1 | 0.5d |
| M11 | Heatwave Personal Advisor | X-cut | M3, M4, M7 | P2 | 1d |
| M12 | Women's Safe Route Layer | Frontend | M4, M7 | P2 | 0.5d |
| M13 | Offline-First Crisis Kit | Frontend | M7 | P2 | 1d |
| M14 | Mosque Admin Broadcast | Backend | M1, M7 | P3 | 1d |
| M15 | Authority Simulation Dashboard | Web | M5 | P1 | 1d |
| M16 | Demo Theater & Submission | Ops | All | P0 | 2d |

---

# M0 — Foundations & Project Setup

### Goal
Unblock the team in half a day. Every developer can clone, build, deploy, and hit a working backend.

### Dependencies
None.

### Tasks (in order)

1. **Create GCP project** `mehfooz-prod`. Apply hackathon credits.
2. **Enable APIs:** Firebase, Cloud Firestore, Cloud Run, Cloud Functions (2nd gen), Cloud Storage, Vertex AI, Maps Platform (Routes, Places, Maps SDK), Cloud Translation, Firebase Auth, FCM, BigQuery.
3. **Service accounts:**
   - `agents-runtime@…` — Cloud Run agents, Firestore RW, Vertex AI user
   - `functions-runtime@…` — Cloud Functions, Firestore RW
   - `ci@…` — deploy permissions
4. **Install Antigravity** on every laptop. Link Google account. Verify Manager view loads.
5. **Monorepo layout:**
   ```
   mehfooz/
   ├── app/                 # Flutter
   ├── agents/              # Python ADK agents (one folder per agent)
   │   ├── ingestion/
   │   ├── detection/
   │   ├── planning/
   │   ├── simulation/
   │   └── orchestrator/
   ├── functions/           # Cloud Functions (TS)
   ├── web/                 # Authority dashboard (React)
   ├── data/                # Seed datasets, helpline DB, underpass list
   ├── docs/                # This spec, ADRs, demo script
   └── GEMINI.md            # Root context for all agents
   ```
6. **Root `GEMINI.md`** — write the shared context (see below).
7. **CI/CD:** GitHub Actions workflows for (a) Flutter build, (b) agent deploy to Cloud Run, (c) Functions deploy.
8. **Pick the demo scenario:** G-10/G-11 Islamabad flash flood. Lock it.

### Root `GEMINI.md` (template)

```markdown
# Mehfooz — Agent Context

## Mission
Civilian-first crisis companion for Pakistan. Fuse citizen signals + official feeds.
Tell each user what to do right now, where they are.

## Cities in scope (priority order)
Islamabad, Rawalpindi, Karachi, Lahore. Demo focus: Islamabad G-10.

## Languages
Accept and respond in: Urdu (Nastaliq), Roman Urdu, English, code-mixed.
Default user-facing language is decided by the user's profile setting.

## Crisis taxonomy
flood | urban_flood | flash_flood | heatwave | road_incident |
fire | building_collapse | power_outage | air_quality | glof

## Helpline routing (city → crisis → number)
See /data/helplines.json. Always look up at runtime; never hardcode in prompts.

## Confidence gating
Promote Signal → Event only when ≥2 modalities corroborate
(citizen report + weather, OR citizen report + traffic anomaly, OR photo + text).

## Tone rules
- Never alarm without evidence.
- Always include the source of a claim ("Based on 12 reports in the last 20 min…").
- For SOS-tier alerts, lead with the action, not the explanation.
- For Urdu output, use simple conversational register, not formal/literary.

## Do not
- Do not invent helpline numbers — always look up.
- Do not claim authority endorsement.
- Do not output PII beyond what the user explicitly shared.
```

### Exit criteria
- [ ] Every dev can `git clone`, run `flutter doctor` clean
- [ ] `firebase emulators:start` runs locally
- [ ] An Antigravity workspace opens and reads the root `GEMINI.md`
- [ ] `gcloud run deploy` smoke test for a hello-world Python service succeeds
- [ ] Demo scenario locked in `docs/demo_scenario.md`

---

# M1 — Data Spine

### Goal
Every agent has clean data to consume; the demo has believable atmosphere with real 2025 Pakistan data.

### Dependencies
M0.

### Firestore Schema

```typescript
// users/{uid}
{
  uid: string,
  phone: string,           // E.164, e.g. +923001234567
  display_name: string,
  language: 'ur' | 'en' | 'roman_ur',
  city: string,
  emergency_contacts: [
    { name: string, phone: string, relation: string }
  ],
  role: 'citizen' | 'mosque_admin' | 'verified_reporter',
  reputation: number,      // 0–100
  last_known_location: GeoPoint,
  last_location_at: Timestamp,
  fcm_token: string,
  women_safe_route: boolean,
  created_at: Timestamp
}

// reports/{report_id}
{
  report_id: string,
  user_id: string,
  text_raw: string,
  text_normalized: string,  // English-translated for agent consumption
  language_detected: string,
  voice_url?: string,       // Cloud Storage
  photo_urls: string[],
  location: GeoPoint,
  geo_accuracy_m: number,
  crisis_type_user?: string, // user-tagged, optional
  crisis_type_inferred?: string,
  severity_user?: 1 | 2 | 3 | 4 | 5,
  created_at: Timestamp,
  vision_verified: boolean,
  vision_confidence: number,
  linked_event_id?: string
}

// signals_weather/{signal_id}
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

// signals_traffic/{signal_id}
{
  source: 'google_maps',
  origin: GeoPoint,
  destination: GeoPoint,
  duration_normal_s: number,
  duration_now_s: number,
  congestion_ratio: number, // duration_now / duration_normal
  recorded_at: Timestamp
}

// signals_social/{signal_id}
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

// events/{event_id}
{
  event_id: string,
  type: string,             // crisis taxonomy
  polygon: GeoPoint[],      // bounding polygon
  centroid: GeoPoint,
  severity: 1 | 2 | 3 | 4 | 5,
  confidence: number,       // 0–1
  status: 'candidate' | 'verified' | 'resolved',
  explanation_en: string,
  explanation_ur: string,
  contributing_signals: {
    reports: string[],      // report_ids
    weather: string[],
    traffic: string[],
    social: string[]
  },
  started_at: Timestamp,
  last_updated: Timestamp,
  resolved_at?: Timestamp
}

// helplines/{helpline_id}
{
  name: string,             // "Rescue 1122 Punjab"
  number: string,           // dial string
  cities: string[],
  crisis_types: string[],
  language_support: string[],
  notes: string             // "24/7, water rescue capable"
}

// safe_spots/{spot_id}
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

// flood_prone_locations/{location_id}
{
  name: string,             // "Lakhani Underpass"
  city: string,
  location: GeoPoint,
  type: 'underpass' | 'lowlying_road' | 'nullah_bank',
  rainfall_threshold_mm_h: number,  // floods when 1h rainfall exceeds this
  historical_notes: string,
  warn_radius_m: number     // typically 2000
}

// agent_traces/{trace_id}
{
  trace_id: string,
  event_id?: string,
  agent: 'ingestion' | 'detection' | 'planning' | 'simulation' | 'comms' | 'orchestrator',
  step: string,             // human-readable label
  input_summary: string,
  output_summary: string,
  reasoning: string,        // Gemini's chain-of-thought
  tools_called: { name: string, args: any, result: any }[],
  duration_ms: number,
  created_at: Timestamp
}

// broadcasts/{broadcast_id}  — used by M14
{
  broadcast_id: string,
  mosque_id: string,
  admin_uid: string,
  text_ur: string,
  text_en: string,
  crisis_type: string,
  radius_m: number,         // typically 3000
  expires_at: Timestamp,
  created_at: Timestamp
}

// mosques/{mosque_id}  — used by M14
{
  mosque_id: string,
  name: string,
  location: GeoPoint,
  admin_uids: string[],
  verified_at: Timestamp,
  verified_by: string
}
```

### Seed data work

1. **Tweet replay dataset** — collect ~100 real tweets from Aug–Sep 2025 floods using snscrape. Anonymize handles. Store in `signals_social` with `posted_at` shifted to demo timeline.
2. **Citizen reports** — write 20 simulated reports in mixed Urdu/Roman/English with realistic timestamps spread over 90 minutes for the G-10 scenario.
3. **Weather replay** — pull real Open-Meteo data for Islamabad on a 2025 flood day. Store hourly snapshots in `signals_weather` with replay timestamps.
4. **Helpline DB** — manually compile from PDMA/NDMA/Rescue 1122/Edhi/Chhipa/Alkhidmat/JDC sites. Target 30+ entries covering all four cities.
5. **Safe spots** — pull from Google Places for each city (hospitals + malls + major mosques). Cache top 200 per city.
6. **Flood-prone underpasses** — manually curate ~50 entries. Karachi: Lakhani, Nazimabad No. 7, Liaqatabad, Gulshan Chowrangi. Lahore: Kalma Chowk, Lawrence Road, Jail Road. Islamabad: Faizabad Interchange underpasses, IJP Road. Rawalpindi: Murree Road dips.
7. **Mock dispatch endpoint** — single Cloud Function `/mock/dispatch` that just writes incoming POST to a `mock_dispatches` collection.

### Indexes to create

- `reports` composite: `(location, created_at desc)` for geo-time queries
- `events` composite: `(status, last_updated desc)`
- `signals_social` composite: `(location_inferred, posted_at desc)`
- `broadcasts` composite: `(expires_at, created_at desc)` for active broadcasts

### Exit criteria
- [ ] All collections created with sample documents
- [ ] Helpline DB has ≥30 entries across 4 cities
- [ ] Flood-prone DB has ≥50 entries
- [ ] Replay script `python data/replay_scenario.py g10` streams the scenario into Firestore
- [ ] Indexes deployed

---

# M2 — Ingestion Agent

### Goal
Pull all raw signals from diverse sources, normalize into a uniform `Signal` shape, and write to Firestore. Acts as the data on-ramp for everything downstream.

### Dependencies
M1.

### Antigravity workspace
`agents/ingestion/` with its own `GEMINI.md`:

```markdown
# Ingestion Agent
Role: pull raw signals, classify, normalize, persist.
Inputs: Firestore reports, Open-Meteo, PMD, Google Maps Traffic, X scrape cache.
Output: Signal docs in `signals_*` collections.
Tools allowed: firestore_read, firestore_write, http_get, gemini_vision, translate.
Tools forbidden: route_planning, dispatch, push_notification.
```

### Tools the agent calls (FastAPI handlers, ADK-registered)

```python
# agents/ingestion/tools.py
from google.adk.tools import Tool

@Tool
def fetch_open_meteo(lat: float, lon: float) -> dict:
    """Pull current weather + 1h/24h rainfall for a lat/lon."""
    url = f"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current=temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m&hourly=precipitation"
    # ...returns dict with rainfall_mm_1h, temp_c, humidity, wind_kph

@Tool
def fetch_pmd_overlay(city: str) -> dict:
    """Best-effort scrape of PMD; fall back to open_meteo result."""
    # try pmd.gov.pk JSON endpoint, return None on failure

@Tool
def fetch_traffic(origin: tuple, destination: tuple) -> dict:
    """Google Maps Routes API — compare normal vs. live duration."""
    # POST to https://routes.googleapis.com/directions/v2:computeRoutes

@Tool
def verify_photo(photo_url: str, claimed_type: str) -> dict:
    """Gemini Vision: does this photo show {claimed_type}?
       Returns {is_match: bool, confidence: float, description: str}."""
    # multimodal call to gemini-2.5-pro

@Tool
def normalize_text(raw: str) -> dict:
    """Detect language, translate Roman Urdu → Urdu → English.
       Extract crisis_type, severity, location hints."""
    # Gemini Flash call

@Tool
def fetch_social_cached(polygon: list, since: str) -> list:
    """Read pre-scraped tweets from signals_social within polygon since timestamp."""

@Tool
def write_signal(collection: str, doc: dict) -> str:
    """Persist a normalized signal. Returns doc_id."""
```

### Agent loop (pseudo)

```python
# agents/ingestion/agent.py
from google.adk import LlmAgent

ingestion_agent = LlmAgent(
    name="ingestion",
    model="gemini-2.5-flash",  # high volume, cheap
    instruction=load("GEMINI.md") + load("ingestion_instruction.md"),
    tools=[
        fetch_open_meteo, fetch_pmd_overlay, fetch_traffic,
        verify_photo, normalize_text, fetch_social_cached, write_signal
    ],
)
```

`ingestion_instruction.md` tells the model: given a polygon and time window, fetch all signal types in parallel where possible, normalize each, write to the right collection, and return a summary of what was ingested.

### Cloud Run deploy

```bash
gcloud run deploy ingestion-agent \
  --source agents/ingestion \
  --region asia-south1 \
  --service-account agents-runtime@... \
  --set-env-vars PROJECT_ID=mehfooz-prod \
  --memory 512Mi
```

### Trigger paths
- **Push trigger:** Firestore `onCreate(reports/{id})` Cloud Function → POSTs to ingestion agent with the new report
- **Pull trigger:** Cloud Scheduler every 2 min → ingestion agent polls weather + traffic for all 4 cities

### Exit criteria
- [ ] 50 mixed inputs (text reports, voice transcripts, photos, tweet dump) produce 50 normalized Signal docs
- [ ] Roman Urdu input "G-10 mein paani bhar gaya, ghutnon tak" gets normalized to `{text_normalized: "Water flooding in G-10, knee-deep", language_detected: "roman_ur", crisis_type_inferred: "urban_flood", severity_user: 3}`
- [ ] Photo verification rejects a clear non-flood image with confidence < 0.3
- [ ] Trace docs written to `agent_traces` for every run

---

# M3 — Detection & Reasoning Agent

### Goal
Find real events in the noise. Cluster signals spatially + temporally, reason over the cluster, gate on multi-modal corroboration, emit `Event` docs with calibrated confidence and human-readable explanations.

### Dependencies
M1, M2.

### Antigravity workspace
`agents/detection/GEMINI.md`:

```markdown
# Detection Agent
Role: turn signals into events. Reject noise. Calibrate confidence.
Hard rule: do NOT promote Signal → Event without ≥2 modalities corroborating.
Allowed modalities: citizen_report, weather, traffic, social, photo_verified.
Output explanation must cite which modalities supported the conclusion.
```

### Core algorithm

```python
# agents/detection/cluster.py
from sklearn.cluster import DBSCAN
import numpy as np

def cluster_signals(signals: list, eps_km: float = 0.5, min_samples: int = 3, time_window_min: int = 60):
    """Spatial-temporal DBSCAN.
       eps_km converted to radians for haversine metric.
       Filters to signals within time_window_min of 'now' first."""
    now = datetime.utcnow()
    recent = [s for s in signals if (now - s.timestamp).total_seconds() < time_window_min * 60]
    if len(recent) < min_samples:
        return []
    coords = np.radians([[s.lat, s.lon] for s in recent])
    db = DBSCAN(eps=eps_km/6371.0, min_samples=min_samples, metric='haversine').fit(coords)
    clusters = {}
    for sig, label in zip(recent, db.labels_):
        if label == -1: continue   # noise
        clusters.setdefault(label, []).append(sig)
    return list(clusters.values())
```

### Tools

```python
@Tool
def read_recent_signals(polygon: list, minutes: int) -> list: ...

@Tool
def run_clustering(signals: list) -> list[list]: ...

@Tool
def fetch_historical_prior(location: GeoPoint, crisis_type: str) -> dict:
    """Look up flood_prone_locations + past events at this point.
       Returns {is_flood_prone: bool, threshold_mm: float, last_flooded: date}."""

@Tool
def cross_modal_check(cluster: list) -> dict:
    """Count distinct modalities in cluster. Return {modalities: set, count: int}."""

@Tool
def write_event(event: dict) -> str: ...

@Tool
def update_event(event_id: str, patch: dict) -> None: ...
```

### Agent reasoning prompt (key section)

```
For each cluster:
1. Identify modalities present (citizen_report, weather, traffic, social, photo_verified).
2. If modality count < 2 → emit candidate Event with status='candidate', confidence ≤ 0.4. Do not promote.
3. If modality count ≥ 2 → reason about:
   - Is this consistent with a known prior? (flood_prone + heavy rainfall = high prior)
   - Are signals temporally coherent? (clustered in last 30 min, not stale)
   - Any contradicting evidence? (e.g., one report says "all clear")
4. Assign confidence:
   - 2 modalities, no prior support → 0.5–0.65
   - 2 modalities + matching prior → 0.65–0.80
   - 3+ modalities + matching prior → 0.80–0.95
   - Never output 1.0.
5. Generate explanation_en (≤ 40 words) AND explanation_ur (simple register).
   Format: "<N> reports + <X mm> rain in <Y> min + traffic anomaly at <landmark> = <severity> <type>."
6. Write Event doc, link contributing_signals.
```

### Severity rubric

| Level | Meaning | Example |
|---|---|---|
| 1 | Minor disruption | Light water on road, passable |
| 2 | Localized issue | Ankle-deep water, slow traffic |
| 3 | Significant | Knee-deep water, vehicles stuck |
| 4 | Severe | Roads impassable, evacuation advised |
| 5 | Life-threatening | Rapid water rise, rescue needed |

### Exit criteria
- [ ] G-10 scenario replay produces exactly one Event with `confidence ≥ 0.8`, `severity ≥ 3`
- [ ] Explanation cites specific modalities and numbers
- [ ] A single-modality cluster (only tweets, no weather/photo) produces a `candidate` Event, not verified
- [ ] Urdu explanation is conversational, not literary
- [ ] Trace shows reasoning, not just final answer

---

# M4 — Planning Agent

### Goal
Convert each verified Event into two parallel action tracks: system-level coordination and per-user personalized guidance.

### Dependencies
M1, M3.

### Antigravity workspace
`agents/planning/GEMINI.md`:

```markdown
# Planning Agent
Role: events → actions. Two tracks: system, per-user.
System track: who to notify (helplines, authorities), what radius to alert.
Per-user track: for each user near the event, what is the single best action right now?

Action verbs: REROUTE, EVACUATE, SHELTER_IN_PLACE, CONTACT_HELPLINE,
              CHECK_ON_FAMILY, AVOID_AREA, SEEK_COOLING, SEEK_MEDICAL.

Never recommend driving through standing water above severity 2.
Always include the WHY in 1 sentence.
```

### Tools

```python
@Tool
def get_users_near(centroid: GeoPoint, radius_m: int) -> list:
    """Users with last_known_location within radius."""

@Tool
def compute_routes(origin: GeoPoint, destination: GeoPoint, avoid_polygons: list) -> list:
    """Google Maps Routes API. Returns 3 alternatives.
       Each route annotated with: distance_m, duration_s, risk_score,
       passes_through_flooded: bool."""

@Tool
def lookup_helpline(city: str, crisis_type: str) -> dict:
    """Returns best helpline doc from helplines collection."""

@Tool
def find_nearest_safe_spots(location: GeoPoint, k: int = 3, type_filter: str = None) -> list:
    """k-NN over safe_spots collection."""

@Tool
def write_plan(plan: dict) -> str: ...
```

### Plan output schema

```typescript
// plans/{plan_id}
{
  plan_id: string,
  event_id: string,
  created_at: Timestamp,

  system_actions: [
    {
      type: 'notify_helpline' | 'flag_route' | 'broadcast_zone',
      target: string,
      payload: object,
      urgency: 'low' | 'med' | 'high' | 'sos'
    }
  ],

  user_actions: {
    [user_id: string]: {
      verb: 'REROUTE' | 'EVACUATE' | 'SHELTER_IN_PLACE' | ...,
      message_en: string,
      message_ur: string,
      route_alternatives?: Route[],
      safe_spots?: SafeSpot[],
      helpline?: Helpline,
      urgency: 'low' | 'med' | 'high' | 'sos'
    }
  }
}
```

### Per-user action decision tree

```
For each user U near event E:
  if U.is_in_event_polygon AND E.severity ≥ 4:
    → EVACUATE (give safe_spots[3])
  elif U.is_in_event_polygon AND E.severity ≤ 3:
    → SHELTER_IN_PLACE (give helpline, neighbors)
  elif U has an active route through E.polygon:
    → REROUTE (give alternatives avoiding polygon)
  elif U is within 2km AND E.severity ≥ 3:
    → AVOID_AREA (passive notification)
  elif U has emergency_contacts in event area:
    → CHECK_ON_FAMILY (passive)
```

### Routing rules
- If `women_safe_route=true` → add penalty for routes with low road-class (residential/service)
- Always reject any route where `passes_through_flooded=true` unless `E.severity ≤ 1`
- Sort by: (not passes_through_flooded, lowest risk_score, shortest duration)

### Exit criteria
- [ ] G-10 event produces a plan with ≥3 system actions and per-user actions for every user within 5km
- [ ] Reroute returns 3 alternatives, none passing through the flood polygon
- [ ] Helpline picked is correct for Islamabad + urban_flood (Rescue 1122 ICT, CARES 1122)
- [ ] Plan written to Firestore in < 4 seconds

---

# M5 — Simulation Agent

### Goal
Execute the planned actions against mock endpoints. Produce auditable artifacts that show "what would happen" in production. Crucial for the demo and for satisfying the brief's simulation requirement.

### Dependencies
M4.

### Antigravity workspace
`agents/simulation/GEMINI.md`:

```markdown
# Simulation Agent
Role: execute Plan actions against mock endpoints.
Persist every call + response to mock_dispatches.
Produce a final SimulationReport summarizing impact.
Never call real authority APIs even if available.
```

### Mock endpoints (Cloud Functions)

```typescript
// functions/src/mock_endpoints.ts
export const mockPdmaDispatch = onRequest(async (req, res) => {
  const ticket_id = `PDMA-${Date.now()}`;
  await db.collection('mock_dispatches').add({
    ticket_id,
    received_at: FieldValue.serverTimestamp(),
    authority: 'PDMA-Punjab',
    payload: req.body,
    status: 'received'
  });
  res.json({ ticket_id, status: 'queued' });
});

export const mockRescue1122 = onRequest(async (req, res) => { /* similar */ });
export const mockTrafficReroute = onRequest(async (req, res) => { /* similar */ });
export const mockSmsBlast = onRequest(async (req, res) => {
  // Logs intended recipients; does NOT actually send
});
```

### Tools

```python
@Tool
def post_to_mock(endpoint: str, payload: dict) -> dict: ...

@Tool
def queue_push(user_id: str, payload: dict, urgency: str) -> dict:
    """Writes to push_queue collection. M6 Comms agent picks up.
       Does NOT send FCM directly — keeps notification policy in one place."""

@Tool
def write_simulation_report(report: dict) -> str: ...
```

### Simulation report schema

```typescript
// simulation_reports/{report_id}
{
  report_id: string,
  plan_id: string,
  event_id: string,
  executed_at: Timestamp,

  dispatches: [
    { authority: string, ticket_id: string, payload_summary: string }
  ],
  notifications_queued: {
    sos: number,
    high: number,
    med: number,
    low: number,
    total_users: number
  },
  routes_flagged: number,
  estimated_impact: {
    congestion_reduction_min: number,   // heuristic, not real
    users_diverted: number,
    response_time_saved_min: number
  },
  summary_en: string,        // for demo card
  summary_ur: string
}
```

### Estimated impact heuristics (transparent, demo-friendly)

```python
def estimate_impact(plan, event):
    diverted = sum(1 for a in plan.user_actions.values() if a.verb == 'REROUTE')
    avg_delay_saved = 22 if event.severity >= 4 else 12  # minutes, eyeballed
    return {
      'congestion_reduction_min': diverted * 0.3 * avg_delay_saved,
      'users_diverted': diverted,
      'response_time_saved_min': 8 if any(a.urgency == 'sos' for a in plan.user_actions.values()) else 0
    }
```

> **Demo note:** Surface these numbers but label them clearly as estimates in the UI and README. Judges respect honesty more than fake precision.

### Exit criteria
- [ ] Running the chain produces a `simulation_reports` doc with the summary card text
- [ ] `mock_dispatches` shows the PDMA + Rescue 1122 tickets visible in M15 dashboard within 2 sec
- [ ] Push queue has correctly-tiered notifications (sos > high > med)
- [ ] Summary card reads naturally: "47 users alerted, 3 routes flagged, 1 ticket dispatched, est. 22 min congestion reduction"

---

# M6 — Comms Agent + Orchestrator

### Goal
Two responsibilities in one module:
1. **Comms agent** — turns plans into user-facing messages and decides notification urgency.
2. **Orchestrator** — the actually-agentic part. Routes between agents, runs feedback loops, decides when to re-invoke.

### Dependencies
M2–M5.

### Antigravity workspace
`agents/orchestrator/GEMINI.md`:

```markdown
# Orchestrator
Role: meta-agent. Decides which sub-agent runs next based on state.
Sub-agents: ingestion, detection, planning, simulation, comms.

Feedback loop rule:
  If detection returns candidate (confidence < 0.6) AND modality_count < 2:
    instruct ingestion to scrape social for cluster polygon, +5 min window.
    re-run detection. max 2 retries.

Termination rule:
  Stop after simulation_report is written OR after 3 ingestion-detection cycles
  without promotion to verified.
```

### Orchestrator loop

```python
# agents/orchestrator/loop.py
async def orchestrate(trigger: dict):
    trace = []

    # 1. Ingest
    sig_summary = await call_ingestion(trigger)
    trace.append(('ingestion', sig_summary))

    # 2. Detect (with retry loop)
    retries = 0
    while retries < 2:
        events = await call_detection(trigger.polygon)
        trace.append(('detection', events))
        candidates = [e for e in events if e.status == 'candidate']
        if not candidates:
            break
        # feedback: ask ingestion for more
        await call_ingestion({'polygon': candidates[0].polygon, 'window': '+5min', 'mode': 'social_only'})
        retries += 1

    verified = [e for e in events if e.status == 'verified']
    if not verified:
        return {'outcome': 'no_event', 'trace': trace}

    # 3. Plan
    for event in verified:
        plan = await call_planning(event)
        trace.append(('planning', plan.plan_id))

        # 4. Simulate
        report = await call_simulation(plan)
        trace.append(('simulation', report.report_id))

        # 5. Communicate
        await call_comms(plan, report)
        trace.append(('comms', 'dispatched'))

    return {'outcome': 'completed', 'trace': trace}
```

### Comms agent responsibilities

```python
@Tool
def render_message(user: dict, action: dict) -> dict:
    """Gemini Flash. Render action.message_en/ur into final push payload.
       Use user.language. Keep ≤ 140 chars for sos/high tiers."""

@Tool
def send_fcm(user_id: str, title: str, body: str, data: dict) -> bool: ...

@Tool
def enqueue_sms_fallback(phone: str, body: str) -> bool:
    """If user has no recent FCM activity, mark for SMS gateway."""
```

### Notification urgency → channel

| Tier | Sound | Vibration | Lock screen | Channel |
|---|---|---|---|---|
| sos | Loud alarm | Strong, repeating | Full takeover | FCM high-prio + SMS fallback |
| high | Distinct tone | Standard | Banner + sound | FCM high-prio |
| med | Default | Standard | Banner | FCM normal |
| low | Silent | None | Notification tray only | FCM normal |

### Exit criteria
- [ ] Triggering orchestrator with G-10 scenario completes full chain end-to-end
- [ ] At least one feedback loop visible in trace (ingestion re-invoked after low-confidence detection)
- [ ] Comms produces Urdu messages that are conversational, not stilted translations
- [ ] SOS-tier notifications trigger correct device behavior on a test phone
- [ ] Total chain latency from trigger to first user push < 30 seconds

---

# M7 — Mobile App Core (Flutter)

### Goal
Ship the mandatory mobile deliverable. Eight screens, Pakistan-localized, real-time, low-end-device-friendly.

### Dependencies
M1, M6.

### Why Flutter
- Single codebase Android + iOS
- 12–18 MB APK achievable, important for low-end Android (still common in target users)
- Hot reload speeds hackathon iteration
- Pakistan is ~92% Android market share

### Package list (`pubspec.yaml` essentials)

```yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: ^3.x
  firebase_auth: ^5.x
  cloud_firestore: ^5.x
  firebase_messaging: ^15.x
  firebase_storage: ^12.x
  google_maps_flutter: ^2.x
  geolocator: ^13.x
  permission_handler: ^11.x
  record: ^5.x                  # voice capture
  image_picker: ^1.x
  url_launcher: ^6.x            # WhatsApp deep link + tel:
  flutter_local_notifications: ^17.x
  hive: ^2.x                    # offline cache (M13)
  flutter_riverpod: ^2.x        # state mgmt
  intl: ^0.19.x                 # Urdu locale
  google_fonts: ^6.x            # Noto Naskh / Jameel Noori
  flutter_svg: ^2.x
  cached_network_image: ^3.x
```

### Screen-by-screen build plan

#### Screen 1 — Onboarding + phone OTP
- Splash with Mehfooz logo + Urdu tagline
- Language picker first: Urdu / English / Roman Urdu
- Phone number entry with `+92` prefix locked
- Firebase Auth OTP flow
- Permission prompts (location, notifications, microphone) with Urdu/English copy
- Emergency contacts setup (skippable but encouraged) — name + phone + relation, min 1

#### Screen 2 — Home/Map
- `GoogleMap` widget centered on `last_known_location`
- Three Firestore streams overlaid:
  - `events` where `status == 'verified'` and within viewport → colored polygons by severity
  - `reports` where `created_at > now - 1h` → heatmap dots (use `google_maps_flutter_platform_interface` heatmap)
  - `mosques` with active broadcasts → green pins (M14)
- Top banner: count of active alerts in user's city, tappable
- Bottom sheet: list of incidents sorted by distance, swipe up to expand
- FAB (bottom right): big red "Report" → opens Screen 3
- FAB (bottom left): SOS → opens Screen 6

#### Screen 3 — Report flow
Three-tab segmented control: Voice / Text / Photo

**Voice tab (M8 wires in here):**
- Big mic button, hold to record (up to 30s)
- Live waveform
- On release: upload to Storage, write `reports` doc with `voice_url`, navigate to confirmation

**Text tab:**
- Multi-line text field, Urdu keyboard supported
- Optional "I am here" geo-confirm (uses current location with 100m fuzz on map preview)
- Optional severity slider 1–5

**Photo tab:**
- Camera or gallery
- Optional caption
- Auto-EXIF location strip on upload for privacy

All tabs: submit writes one `reports` doc, triggers ingestion via Firestore-onCreate Function.

#### Screen 4 — Situation detail
Tap any incident on the map → this screen.
- Top: severity chip + crisis type icon + city
- Photo carousel (verified photos from reports)
- "Why we think this is real" card → renders `explanation_en` / `explanation_ur` from Event doc
- Modality breakdown bar: "12 reports · 38mm rain · traffic +180% · 2 verified photos"
- "What you should do" card — pulled from this user's entry in the latest plan's `user_actions`
- "Open route" button if `verb == 'REROUTE'`
- "Call now" button if `helpline` present → `tel:` deep link
- Bottom: agent trace toggle (Screen 7)

#### Screen 5 — Safe Route
- Origin (default: current location) + destination autocomplete (Places API)
- Toggle: "Women's safe mode" (M12)
- "Find safe routes" → calls planning agent endpoint
- Result: 3 routes shown on map, each with risk chip (green/yellow/red) + reasoning
- Tap a route → open in Google Maps app via `url_launcher`

#### Screen 6 — SOS
- Single full-screen red button, "Hold to send SOS" (2 sec hold to prevent accidental trigger)
- On trigger, in parallel:
  - Write `sos_events` doc with location + user_id
  - Share location via WhatsApp deep link to each emergency contact:
    `whatsapp://send?phone=...&text=SOS at https://maps.google.com/?q=lat,lon`
  - Fetch nearest 3 safe spots, show on map with walking directions
  - Look up right helpline for city + situation → big "Call <name>" button
  - Pulse animation + "Help is being notified" reassurance

#### Screen 7 — Agent Trace
- Power-user view, accessed from Situation detail or from settings
- Reads `agent_traces` filtered by event_id
- Each step shown as a card: agent name + step + reasoning + tools called
- Expandable JSON for tools
- "Share this trace" → exports as JSON (useful for submission)

#### Screen 8 — Profile + emergency contacts
- Edit display name, language, city
- Emergency contacts CRUD
- Notification preferences per tier
- Toggle "Women's safe route" default
- Mosque admin signup link (M14)
- Reputation badge if `reputation ≥ 60`

### Design system

| Token | Value |
|---|---|
| Brand red | `#D62828` (emergency vest, desaturated) |
| Brand green | `#2A9D8F` (safe / verified) |
| Brand amber | `#E9C46A` (caution) |
| Background | `#F5F1E8` (warm off-white, less harsh than pure white) |
| Text primary | `#1B1B1B` |
| Urdu heading font | Jameel Noori Nastaleeq (bundled) |
| Urdu body font | Noto Naskh Urdu (bundled) |
| English heading | Inter |
| English body | Inter |
| Corner radius | 16px (cards), 28px (FABs) |

### Empty states
Illustrations of recognizable landmarks (Faisal Mosque, Minar-e-Pakistan, Empress Market, Karakoram) — commissioned or AI-generated, single line-art style.

### Exit criteria
- [ ] All 8 screens functional against live backend
- [ ] APK ≤ 22 MB
- [ ] App runs at ≥ 30fps on a 2GB-RAM Android device
- [ ] Urdu rendering correct (right-to-left, ligatures)
- [ ] Cold start to map visible < 4 seconds on mid-tier device
- [ ] All flows work end-to-end with the G-10 scenario replay

---

# M8 — Urdu Voice Reporting

### Goal
The 30-second demo gold moment. User holds a button, speaks Urdu / Roman Urdu / code-mixed naturally, and a structured `reports` doc appears in Firestore within seconds.

### Dependencies
M2, M7.

### Architecture choices

**Option A — Gemini Live API (recommended for the demo)**
Streaming audio → Gemini → structured output. Lowest latency, native multi-language handling, no separate STT step.

**Option B — Two-stage (fallback)**
Record locally → upload to Storage → Cloud Function calls Speech-to-Text (with `ur-PK` model) → Gemini Flash normalizes → write report. Higher latency but reliable.

Build Option B first, layer Option A on top once stable.

### Two-stage implementation

```dart
// app/lib/features/report/voice_recorder.dart
final recorder = AudioRecorder();
await recorder.start(
  RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000),
  path: localPath,
);
// ... user holds, releases
final path = await recorder.stop();

// Upload
final ref = FirebaseStorage.instance.ref('voice/${user.uid}/${uuid}.m4a');
await ref.putFile(File(path));
final url = await ref.getDownloadURL();

// Write report shell
final reportDoc = await FirebaseFirestore.instance.collection('reports').add({
  'user_id': user.uid,
  'voice_url': url,
  'location': GeoPoint(pos.latitude, pos.longitude),
  'geo_accuracy_m': pos.accuracy,
  'created_at': FieldValue.serverTimestamp(),
  'text_normalized': null,  // filled by Function
});
```

Cloud Function `onVoiceReportCreated`:

```typescript
export const onVoiceReportCreated = onDocumentCreated(
  'reports/{reportId}',
  async (event) => {
    const data = event.data.data();
    if (!data.voice_url || data.text_normalized) return;

    // 1. Speech-to-Text
    const audioBytes = await downloadAudio(data.voice_url);
    const sttResponse = await speechClient.recognize({
      audio: { content: audioBytes },
      config: {
        encoding: 'MP4',
        languageCode: 'ur-PK',
        alternativeLanguageCodes: ['en-US', 'en-PK'],
        model: 'latest_long',
        enableAutomaticPunctuation: true
      }
    });
    const transcript = sttResponse.results.map(r => r.alternatives[0].transcript).join(' ');

    // 2. Gemini normalize
    const gemini = await callGeminiFlash({
      system: 'Normalize this crisis report. Detect language, translate to English, ...',
      input: transcript
    });

    // 3. Update doc
    await event.data.ref.update({
      text_raw: transcript,
      text_normalized: gemini.english,
      language_detected: gemini.language,
      crisis_type_inferred: gemini.crisis_type,
      severity_user: gemini.severity
    });
    // Ingestion agent picks up via its own onCreate trigger
  }
);
```

### Gemini Live (Option A) sketch

```dart
// Streaming via WebSocket to Vertex AI Live endpoint
final live = GeminiLiveSession(
  model: 'gemini-2.5-pro-live',
  systemInstruction: voiceReportInstruction,
  responseSchema: reportSchema,  // structured JSON output
);
await live.connect();
recorder.stream.listen((chunk) => live.sendAudio(chunk));
live.responses.listen((r) {
  if (r.isFinal) writeReportDoc(r.json);
});
```

### Test phrases (use in demo)

- `"G-10 markaz ke paas paani bhar gaya, gaariyan phans gayi hain"`
- `"Lakhani underpass pe ghutnon tak paani hai, koi mat aaye"`
- `"Sharah-e-Faisal pe Drigh Road ke pass traffic bilkul band hai"`
- English fallback: `"Heavy flooding near Faisal Mosque parking, water rising fast"`

### Exit criteria
- [ ] Roman Urdu sentence → normalized Signal in Firestore in < 5 sec (Option B)
- [ ] < 2 sec with Option A
- [ ] Code-mixed input ("flood ho raha hai") correctly identified as `roman_ur`
- [ ] Severity correctly inferred for at least 4 of the 4 test phrases above

---

# M9 — Underpass Flood Radar

### Goal
The Pakistan-specific moat. Use the curated `flood_prone_locations` list to fire proactive, hyper-local warnings before water gets dangerous — naming the specific underpass in the user's actual language.

### Dependencies
M1, M3, M7.

### How it works

A scheduled Cloud Function runs every 5 minutes:
1. For each city, fetch current weather (Open-Meteo cache from M2)
2. For each `flood_prone_locations` doc where `rainfall_mm_1h > rainfall_threshold_mm_h`:
   - Query `users` where `last_known_location` within `warn_radius_m` (typically 2km)
   - For each user, check `radar_warnings` collection — if no warning sent for this location in last 6h, send
3. Push payload includes the landmark name in user's language

### Implementation

```typescript
// functions/src/underpass_radar.ts
import * as geofire from 'geofire-common';

export const underpassRadar = onSchedule('every 5 minutes', async () => {
  const floodProne = await db.collection('flood_prone_locations').get();

  for (const loc of floodProne.docs) {
    const data = loc.data();
    const weather = await getLatestWeather(data.city);
    if (!weather || weather.rainfall_mm_1h < data.rainfall_threshold_mm_h) continue;

    // Geo-query users within radius
    const center = [data.location.latitude, data.location.longitude];
    const bounds = geofire.geohashQueryBounds(center, data.warn_radius_m);
    const userPromises = bounds.map(b =>
      db.collection('users')
        .orderBy('geohash')
        .startAt(b[0])
        .endAt(b[1])
        .get()
    );
    const snaps = await Promise.all(userPromises);
    const candidates = snaps.flatMap(s => s.docs).filter(u => {
      const ul = u.data().last_known_location;
      const dist = geofire.distanceBetween([ul.latitude, ul.longitude], center) * 1000;
      return dist <= data.warn_radius_m;
    });

    for (const userDoc of candidates) {
      const dedupeKey = `${userDoc.id}_${loc.id}`;
      const existing = await db.collection('radar_warnings').doc(dedupeKey).get();
      if (existing.exists && (Date.now() - existing.data().sent_at.toMillis()) < 6 * 3600 * 1000) continue;

      await sendRadarPush(userDoc.data(), data, weather);
      await db.collection('radar_warnings').doc(dedupeKey).set({
        user_id: userDoc.id,
        location_id: loc.id,
        sent_at: FieldValue.serverTimestamp()
      });
    }
  }
});

async function sendRadarPush(user, loc, weather) {
  const title_ur = `⚠️ ${loc.name_ur || loc.name} ke qareeb seelaab ka khatra`;
  const title_en = `⚠️ Flooding likely near ${loc.name}`;
  const body_ur = `${weather.rainfall_mm_1h}mm baarish 1 ghantay mein. Agar zaroori nahi, ${loc.name_ur || loc.name} ka ilaaqa avoid karein.`;
  const body_en = `${weather.rainfall_mm_1h}mm rain in 1h. Avoid ${loc.name} if not essential.`;

  const title = user.language === 'en' ? title_en : title_ur;
  const body = user.language === 'en' ? body_en : body_ur;

  await admin.messaging().send({
    token: user.fcm_token,
    notification: { title, body },
    data: {
      type: 'underpass_radar',
      location_id: loc.id,
      tier: 'high'
    },
    android: { priority: 'high' }
  });
}
```

### Storing geohash on users
On every location update from the app, also compute and store `geohash` on the user doc so the geo-query above works:

```dart
// app/lib/services/location_service.dart
final geohash = GeoHasher().encode(pos.longitude, pos.latitude, precision: 9);
await userRef.update({
  'last_known_location': GeoPoint(pos.latitude, pos.longitude),
  'last_location_at': FieldValue.serverTimestamp(),
  'geohash': geohash,
});
```

### Calibration table (seed values)

| Location type | Threshold |
|---|---|
| Major underpass (Lakhani, Kalma Chowk) | 15 mm/h |
| Secondary underpass | 20 mm/h |
| Low-lying road | 25 mm/h |
| Nullah bank | 30 mm/h (also requires 3h cumulative > 50mm) |

### Exit criteria
- [ ] Simulating 25mm/h rainfall in Karachi sends push to all test users within 2km of Lakhani Underpass
- [ ] No duplicate push within 6h to same user-location pair
- [ ] Push lands on test device in < 60 sec from threshold breach
- [ ] Push title/body correct in user's chosen language

---

# M10 — Smart Helpline Router

### Goal
End the "which number do I call?" confusion. Given city + crisis type, return the right helpline with one tap to dial.

### Dependencies
M1, M4, M7.

### Data structure (already in M1)

```json
[
  {
    "name": "Rescue 1122 Punjab",
    "number": "1122",
    "cities": ["Lahore", "Rawalpindi", "Faisalabad", "Multan", "Gujranwala"],
    "crisis_types": ["fire", "road_incident", "flood", "medical", "building_collapse"],
    "language_support": ["ur", "en", "pa"],
    "notes": "24/7. Has water rescue teams in Lahore."
  },
  {
    "name": "Chhipa Emergency",
    "number": "1020",
    "cities": ["Karachi", "Hyderabad", "Sukkur"],
    "crisis_types": ["medical", "flood", "road_incident", "body_recovery"],
    "language_support": ["ur", "en"],
    "notes": "Strong water rescue in Karachi."
  },
  {
    "name": "Edhi Foundation",
    "number": "115",
    "cities": ["*"],
    "crisis_types": ["medical", "ambulance", "shelter"],
    "language_support": ["ur"],
    "notes": "Nationwide ambulance."
  },
  {
    "name": "CARES 1122 Islamabad",
    "number": "1122",
    "cities": ["Islamabad"],
    "crisis_types": ["fire", "medical", "road_incident", "flood"],
    "language_support": ["ur", "en"],
    "notes": "ICT only."
  },
  {
    "name": "NDMA",
    "number": "1135",
    "cities": ["*"],
    "crisis_types": ["disaster_coordination"],
    "language_support": ["ur", "en"],
    "notes": "For major disasters, not individual rescue."
  },
  {
    "name": "Alkhidmat Foundation",
    "number": "1023",
    "cities": ["*"],
    "crisis_types": ["shelter", "flood", "food_aid"],
    "language_support": ["ur"],
    "notes": "Volunteer-driven, strong in floods."
  }
  // ... 25+ more
]
```

### Resolution function

```python
# agents/planning/helpline.py
def resolve_helpline(city: str, crisis_type: str) -> dict:
    """Priority:
       1. Exact city match + exact crisis type
       2. Exact city + crisis in helpline.crisis_types
       3. city == '*' + crisis match
       4. Edhi (fallback)
    """
    all_lines = db.collection('helplines').stream()
    candidates = []
    for h in all_lines:
        d = h.to_dict()
        city_match = city in d['cities'] or '*' in d['cities']
        crisis_match = crisis_type in d['crisis_types']
        if not city_match or not crisis_match:
            continue
        # Score: prefer city-specific over '*'
        score = 0
        if city in d['cities']: score += 10
        if crisis_type in d['crisis_types']: score += 5
        # Prefer water-rescue notes for floods
        if crisis_type == 'flood' and 'water rescue' in d.get('notes', '').lower():
            score += 8
        candidates.append((score, d))
    if not candidates:
        return EDHI_FALLBACK
    candidates.sort(reverse=True)
    return candidates[0][1]
```

### UI integration

In Screen 4 (Situation detail) and Screen 6 (SOS):

```dart
// app/lib/features/sos/helpline_button.dart
final helpline = await callPlanningEndpoint('/helpline', {
  'city': user.city,
  'crisis_type': event.type,
});

return ElevatedButton.icon(
  icon: Icon(Icons.phone),
  label: Text(
    user.language == 'en'
      ? 'Call ${helpline.name} (${helpline.number})'
      : '${helpline.name} ko call karein (${helpline.number})',
  ),
  onPressed: () => launchUrl(Uri.parse('tel:${helpline.number}')),
);
```

### Exit criteria
- [ ] For (Karachi, urban_flood) → returns Chhipa 1020 first
- [ ] For (Lahore, fire) → returns Rescue 1122
- [ ] For (Islamabad, flood) → returns CARES 1122
- [ ] For any (city, crisis with no specific match) → returns Edhi 115
- [ ] One-tap dial works on Android and iOS

---

# M11 — Heatwave Personal Advisor

### Goal
Address Karachi's recurring heatwave deaths — rickshaw drivers, laborers, elderly. Personal, geo-aware, time-aware advice with nearest cooling center.

### Dependencies
M3, M4, M7.

### Trigger logic

A scheduled Function runs every 15 min in heatwave season (April–September) for Karachi, Hyderabad, Multan:

```typescript
export const heatwaveAdvisor = onSchedule('every 15 minutes', async () => {
  const heatCities = ['Karachi', 'Hyderabad', 'Multan', 'Jacobabad', 'Sukkur'];
  for (const city of heatCities) {
    const w = await getLatestWeather(city);
    if (!w) continue;
    const heatIndex = computeHeatIndex(w.temp_c, w.humidity);
    if (heatIndex < 42) continue;  // safe

    const users = await db.collection('users').where('city', '==', city).get();
    for (const u of users.docs) {
      const ud = u.data();
      if (!isLikelyOutdoors(ud)) continue;       // skip if last activity in cool location
      if (sentRecently(ud.uid, 'heatwave', 4 * 3600)) continue;

      const coolingSpots = await findNearestSafeSpots(ud.last_known_location, 3, {
        has_cooling: true
      });
      await sendHeatwavePush(ud, heatIndex, coolingSpots);
      if (heatIndex >= 48) {
        await notifyEmergencyContact(ud, heatIndex);
      }
    }
  }
});

function computeHeatIndex(tempC: number, humidity: number): number {
  // Rothfusz regression (simplified)
  const T = tempC * 9/5 + 32;
  const R = humidity;
  let hi = -42.379 + 2.04901523*T + 10.14333127*R
           - 0.22475541*T*R - 0.00683783*T*T
           - 0.05481717*R*R + 0.00122874*T*T*R
           + 0.00085282*T*R*R - 0.00000199*T*T*R*R;
  return (hi - 32) * 5/9;
}
```

### `isLikelyOutdoors` heuristic
- User has reported in last 30 min → outdoors
- User opened the app in last 15 min and movement >5km/h between location updates → outdoors
- Otherwise treat as indoors (no push)

### Cooling spots
Filter `safe_spots` where `has_cooling: true`. Seed includes:
- Major malls (Dolmen, Lucky One, Atrium)
- Hospital lobbies
- Large mosques (cool flooring, fans)
- Some public libraries

### Push content example

```
Title:   🌡️ Sakht garmi — apna khayal rakhein
Body:    Karachi mein heat index 46°C. Aap se 800m door Dolmen Mall thanda
         hai, jaane mein 10 min. Paani peeyein, dhoop avoid karein.
Action:  [Map: Dolmen Mall]  [Call family]
```

### Emergency contact ping (heat index ≥ 48)
WhatsApp deep link auto-share to first emergency contact:
> *"Salaam, [Name] Karachi mein hai aur garmi bohat zyada hai (heat index 48°C). Please check-in karein."*

### Exit criteria
- [ ] Simulated 47°C / 60% humidity in Karachi triggers push to all test users in city
- [ ] Push includes correct nearest cooling center
- [ ] Heat index ≥ 48 also pings emergency contact via WhatsApp
- [ ] No duplicate within 4 hours

---

# M12 — Women's Safe Route Layer

### Goal
A toggle that prefers routes through main roads, well-lit streets, and avoids isolated detours — even when longer. Acknowledges a real safety concern that almost no Pakistani navigation app addresses.

### Dependencies
M4, M7.

### Implementation

In Planning Agent's `compute_routes`:

```python
def compute_routes(origin, destination, avoid_polygons, safety_mode=False):
    routes = google_maps_routes(origin, destination, alternatives=5,
                                 avoid=['ferries'])
    if safety_mode:
        for r in routes:
            r.risk_score = _safety_penalty(r) + r.flood_risk_score
    else:
        for r in routes:
            r.risk_score = r.flood_risk_score
    routes.sort(key=lambda r: (r.passes_through_flooded, r.risk_score, r.duration_s))
    return routes[:3]

def _safety_penalty(route):
    penalty = 0
    for step in route.steps:
        road = step.road_class  # 'motorway', 'primary', 'secondary', 'tertiary', 'residential', 'service'
        if road in ('residential', 'service'):
            penalty += step.distance_m * 0.5
        if step.is_unlit_assumed:  # heuristic: tertiary+residential in night hours
            penalty += step.distance_m * 0.3
        if step.passes_isolated_area:  # OSM landuse query: industrial/agricultural
            penalty += step.distance_m * 0.4
    return penalty
```

### OSM enrichment (one-time precompute)

Use Overpass API to tag road segments in target cities with:
- `lit=yes/no/unknown` from OSM
- `landuse` of surrounding polygon (industrial, residential, commercial)
- `highway` class

Store in a Firestore collection `road_segments` indexed by S2 cell. Planning agent joins routes against this at runtime.

### UI

Settings toggle: "Women's safe route mode (longer, safer)" with one-line explanation. Persists to `users.women_safe_route`.

Route results show explicit reasoning:
> *"Route 1 is 4 min longer but stays on Stadium Road and Shahrah-e-Faisal — avoiding the back lanes in Korangi."*

### Exit criteria
- [ ] Same origin/destination returns visibly different routes with toggle on vs off
- [ ] Safety penalty calculation logged in plan trace
- [ ] Reasoning text shown in UI
- [ ] Available to all users (toggle), not gendered at sign-up

---

# M13 — Offline-First Crisis Kit

### Goal
Works when the network doesn't. Load-shedding, tower congestion, or being inside a flooded underpass shouldn't make the app useless.

### Dependencies
M7.

### What gets cached

Using Hive (Flutter):

```dart
// app/lib/services/offline_cache.dart
@HiveType(typeId: 0)
class CachedHelpline { ... }

@HiveType(typeId: 1)
class CachedSafeSpot { ... }

@HiveType(typeId: 2)
class CachedFirstAid {
  String topic;        // 'drowning', 'heatstroke', 'electrocution', 'bleeding'
  String content_ur;
  String content_en;
}

@HiveType(typeId: 3)
class CachedEvent { ... }  // last 24h verified events for user's city

@HiveType(typeId: 4)
class QueuedReport {
  String text;
  String voicePath;    // local file
  GeoPoint location;
  DateTime createdAt;
  bool synced;
}
```

### Sync strategy

- **On app start (online):** refresh helplines, safe spots near user, active events in city, first-aid pack (one-time)
- **On report submit (offline):** write to `QueuedReport` box; show "Will send when online" indicator
- **Connectivity restore:** background flush of `QueuedReport` to Firestore

### First-aid cards (4 essentials)

Each card: ≤ 6 bullet points, large icons, voice playback option (pre-recorded Urdu).

1. **Drowning rescue** — don't enter water, throw rope/branch, after rescue: airway → breathing → call helpline
2. **Heatstroke** — move to shade, cool with water, no ice, give fluids if conscious, call helpline if confused/unconscious
3. **Electrocution** — don't touch person, cut power if possible, after isolation: check breathing, CPR if trained
4. **Severe bleeding** — direct pressure, elevate, don't remove embedded objects, call helpline

### SMS fallback (production sketch, demo simulator)

Production would use Twilio / local aggregator like Jazz API. For demo:

```dart
// On SOS in offline mode
final smsBody = 'SOS lat:${pos.latitude} lon:${pos.longitude} ${user.name}';
final number = await getHelplineForCity(user.cachedCity, 'sos');
await launchUrl(Uri.parse('sms:$number?body=${Uri.encodeComponent(smsBody)}'));
```

This pops the native SMS app pre-filled, which works on any GSM signal even without data.

### Exit criteria
- [ ] Airplane mode: app launches, shows last-known events, full helpline list, first-aid cards
- [ ] Submit report offline: queued indicator shows, doc written on reconnect
- [ ] SOS offline: SMS draft launches with correct number + coordinates
- [ ] First-aid cards readable in Urdu with correct typography

---

# M14 — Mosque Admin Broadcast

### Goal
Plug into the trust network that actually coordinated 2025 flood rescues. Verified mosque admins broadcast hyper-local updates labeled as a distinct trust tier — not citizen, not authority.

### Dependencies
M1, M7.

### Three trust tiers visible in UI

| Tier | Source | Verification | Color |
|---|---|---|---|
| Citizen | Public app users | Reputation + corroboration | Yellow dot |
| Mosque-verified | Verified mosque admins | Manual review | Green dot |
| Authority | Official feeds | Official source | Blue dot |

### Verification flow

**Demo version (hackathon):**
Pre-seed 3–5 mosques (Faisal Mosque Islamabad, Jamia Masjid Gulshan Karachi, Data Darbar Lahore, etc.) with admin accounts.

**Production version:**
Admin requests verification → submits CNIC + letter on mosque letterhead + geo-pinned location → ops team review (possibly with Alkhidmat partnership). Verified admins get the `role: mosque_admin` flag.

### Broadcast flow

Admin opens app → sees extra "Broadcast" tab → composes:
- Crisis-type tag (required): flood / heatwave / road / fire / shelter / general_safety
- Message in Urdu and/or English (≤ 280 chars)
- Auto-attached: mosque name, location

Post → Cloud Function fans out FCM push to users within 3km whose `geohash` matches.

```typescript
// functions/src/mosque_broadcast.ts
export const onBroadcastCreated = onDocumentCreated(
  'broadcasts/{id}',
  async (event) => {
    const b = event.data.data();
    const mosque = (await db.doc(`mosques/${b.mosque_id}`).get()).data();

    const bounds = geofire.geohashQueryBounds(
      [mosque.location.latitude, mosque.location.longitude],
      b.radius_m
    );
    const snaps = await Promise.all(
      bounds.map(b => db.collection('users').orderBy('geohash').startAt(b[0]).endAt(b[1]).get())
    );
    const recipients = snaps.flatMap(s => s.docs).filter(u => {
      const ul = u.data().last_known_location;
      const dist = geofire.distanceBetween(
        [ul.latitude, ul.longitude],
        [mosque.location.latitude, mosque.location.longitude]
      ) * 1000;
      return dist <= b.radius_m;
    });

    const promises = recipients.map(r => admin.messaging().send({
      token: r.data().fcm_token,
      notification: {
        title: `🕌 ${mosque.name}`,
        body: r.data().language === 'en' ? b.text_en : b.text_ur
      },
      data: {
        type: 'mosque_broadcast',
        broadcast_id: event.params.id,
        crisis_type: b.crisis_type,
        tier: 'med'
      }
    }));
    await Promise.all(promises);

    await event.data.ref.update({ delivered_count: recipients.length });
  }
);
```

### Misuse controls

- Broadcasts must carry a crisis-type tag — admin can't post free-form anything
- Users can mute specific mosques in settings
- 3+ user reports on a single broadcast → auto-pull from feed + flag admin for review
- Admins limited to 1 broadcast per 30 min unless they tag `severity ≥ 3`
- All broadcasts auto-expire after 6h

### Inclusivity notes

- Code keeps collection name `mosques` for clarity, but UI string is **"Verified Community Broadcaster"**
- Imambargahs and women's mosques are includable
- Tier label in UI is religion-neutral

### Exit criteria
- [ ] Pre-seeded demo admin can post a broadcast
- [ ] Test users within 3km receive push within 5 sec
- [ ] Users outside 3km do not receive it
- [ ] Broadcast displays on map with green tier indicator
- [ ] Mute mosque toggle in user settings works
- [ ] Broadcasts auto-expire after 6h

---

# M15 — Authority Simulation Dashboard

### Goal
Demo prop showing "where this plugs into real systems." A tiny web page that authorities (Rescue 1122, PDMA) would use if the system were deployed — shows simulated tickets arriving in real time. Also hosts the killer "before/after" split-screen for the demo.

### Dependencies
M5.

### Stack
- React + Vite (single-page)
- Firebase Hosting
- Firestore live listeners (no backend needed)
- Maps via Google Maps JS API

### Layout

```
┌─────────────────────────────────────────────────────────────┐
│  Mehfooz — Authority Sim (PDMA Punjab)        Live: ●       │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────────────────────┐  │
│  │ Active Tickets  │  │                                 │  │
│  │                 │  │      Live Incident Map          │  │
│  │ ► PDMA-...01    │  │   (events polygons + tickets    │  │
│  │   Flood G-10    │  │    as pins)                     │  │
│  │   sev 4         │  │                                 │  │
│  │   3 min ago     │  │                                 │  │
│  │                 │  │                                 │  │
│  │ ► PDMA-...02    │  │                                 │  │
│  │   ...           │  │                                 │  │
│  └─────────────────┘  └─────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  Impact summary (last hour)                                 │
│  47 users alerted · 3 routes flagged · 1 ticket dispatched  │
│  Estimated 22 min congestion reduction                      │
└─────────────────────────────────────────────────────────────┘
```

### Before/After mode (demo special)

Toggle button: "Demo: Before/After"

Splits screen vertically:
- **Left:** city map at T-0 (before agents fire). Yellow dots = unverified citizen reports. No alerts, no reroutes.
- **Right:** same map at T+90s. Verified red polygon. Re-routed users moving on alternate roads. Tickets visible. Counter updating.

Drives the visceral "look what the agents did" moment in the demo video.

### Code shape

```tsx
// web/src/App.tsx
function AuthorityDashboard() {
  const [tickets, setTickets] = useState([]);
  const [events, setEvents] = useState([]);
  const [report, setReport] = useState(null);
  const [demoMode, setDemoMode] = useState<'live' | 'before' | 'after'>('live');

  useEffect(() => {
    const unsub1 = onSnapshot(
      query(collection(db, 'mock_dispatches'), orderBy('received_at', 'desc'), limit(50)),
      snap => setTickets(snap.docs.map(d => ({ id: d.id, ...d.data() })))
    );
    const unsub2 = onSnapshot(
      query(collection(db, 'events'), where('status', '==', 'verified')),
      snap => setEvents(snap.docs.map(d => ({ id: d.id, ...d.data() })))
    );
    const unsub3 = onSnapshot(
      query(collection(db, 'simulation_reports'), orderBy('executed_at', 'desc'), limit(1)),
      snap => snap.docs[0] && setReport(snap.docs[0].data())
    );
    return () => { unsub1(); unsub2(); unsub3(); };
  }, []);

  return demoMode === 'live' ? <LiveView ... /> : <SplitView mode={demoMode} ... />;
}
```

### Exit criteria
- [ ] Page deployed to `https://mehfooz-prod.web.app`
- [ ] Tickets stream in real-time during the agent run
- [ ] Map polygons update as Detection writes events
- [ ] Before/After toggle works for the demo
- [ ] Page loads in < 2 sec on a venue connection

---

# M16 — Demo Theater & Submission

### Goal
The 3–5 minute video that wins. Plus all submission deliverables tight, complete, and honest.

### Dependencies
All other modules.

### Antigravity-specific deliverables (mandatory)

- One Antigravity workspace per agent (5 total)
- Manager view captured during a live demo run with all 5 agents lighting up in parallel on G-10
- Plan Artifacts exported for each agent (Antigravity native export)
- Browser-integration screenshots captured during live testing
- Trace log exported as JSON from `agent_traces`

### Demo script (target 4 min, hard ceiling 5)

| Time | Beat | What's on screen |
|---|---|---|
| 0:00–0:30 | **Hook** | Real photo from 2025 Karachi flooding. One stat: "163mm rain in one day, thousands stranded overnight." One sentence: "Authorities had data. Citizens had nothing." |
| 0:30–1:15 | **Citizen Aisha** | Phone screen recording: Aisha in F-10, taps Report, holds mic, says in Roman Urdu "F-10 markaz ke paas paani bhar raha hai." Submits. Map updates with her dot. |
| 1:15–2:15 | **Agents** | Cut to Antigravity Manager view. Five agent workspaces light up in sequence. Show the Situation card emerging: "12 reports + 38mm rain + traffic spike = HIGH confidence urban_flood." Zoom into the feedback loop — Detection at 0.55, Orchestrator triggers Ingestion retry, Detection at 0.82. |
| 2:15–3:00 | **Outcomes for 3 citizens** | Bilal opens Safe Route → 3 routes, picks green. Sara hits SOS → location auto-WhatsApp'd to family, Chhipa 1020 dialed. Ahmed in Dubai watches "All clear" banner flip to "Active alert" on his parents' street. |
| 3:00–3:30 | **Authority view** | Cut to M15 dashboard. PDMA ticket arrives. Before/After split-screen runs. Routes reroute. Counter ticks. |
| 3:30–4:00 | **Outcome card** | Final summary card: "47 users alerted · 3 routes flagged · 1 ticket dispatched · est. 22 min reduction." Team logo. Cut. |

### Submission package

**GitHub repo:**
- `README.md` with architecture diagram (SVG), demo GIF, quickstart, deploy commands
- `docs/ARCHITECTURE.md` — full system view, agent diagram, data flow
- `docs/ASSUMPTIONS.md` — every mock clearly marked: mock dispatch endpoints, replay weather feed, demo scenario hardcoded, manual mosque verification skipped
- `docs/ANTIGRAVITY.md` — workspace-by-workspace explanation with screenshots
- `docs/AGENT_PROMPTS/` — every `GEMINI.md` collected
- `data/sample_traces.json` — exported `agent_traces` from one full G-10 run
- `LICENSE` — Apache 2.0

**Video:**
- Primary: 4-min YouTube unlisted
- Backup: Same video on Google Drive
- 720p minimum, captions in English

**Live demo readiness:**
- Pre-seeded backend ready to replay G-10
- Backup pre-recorded video on local laptop in case venue wifi fails
- Phone on charger with app pre-installed, demo user logged in
- Antigravity Manager view pre-loaded in browser tab

### Documentation diagrams to ship

1. **System architecture** — client / functions / agents / data sources / authority sim
2. **Agent flow** — 5 agents with arrows, including the feedback loop, annotated with sample messages
3. **Data flow for one report** — citizen report → Firestore → ingestion → detection → planning → simulation → comms → user push
4. **Trust tier diagram** — citizen / mosque / authority layered icons

### Honesty disclosures (in README, prominent)

- "Authority dispatch is simulated. Production would require API agreements with PDMA / Rescue 1122 / NDMA."
- "Mosque admin verification is manual; demo uses pre-seeded admins."
- "Weather feed for demo is replayed from real 2025 PMD data."
- "Impact estimates are heuristics for demonstration; production would require historical baselines."

Judges respect this. Pretending mocks are real is the fastest way to lose credibility.

### Exit criteria
- [ ] 4-min video published, link in submission form
- [ ] Repo public, tagged `v1.0-hackathon`
- [ ] All Antigravity Plan Artifacts exported and committed
- [ ] Sample `agent_traces.json` in repo
- [ ] Assumptions doc complete
- [ ] Backup video on local laptop
- [ ] Phone demo flow rehearsed 3+ times

---

# Cross-Cutting Concerns

### Privacy

- Public maps show user locations with 100m geo-fuzzing
- Precise location used only for: (a) personal alerts to that user, (b) explicit SOS sharing with that user's emergency contacts
- Voice recordings deleted from Cloud Storage after 30 days unless flagged as evidence
- Phone numbers never displayed publicly; user-to-user contact only via the app's relay
- All this documented in README + an in-app privacy screen

### Fake reports

- Reputation score per user, 0–100
- New users start at 50
- +5 per corroborated report (linked to a verified event with 2+ modalities)
- −10 per report flagged by 3+ other users
- Below 20 → reports excluded from clustering input
- "Verified reporter" badge at ≥ 60

### Antigravity instability mitigation

- Agents run on ADK + Cloud Run independently of Antigravity
- Antigravity is the dev surface and demo prop, not the runtime
- If Antigravity flakes during the demo, the working system still runs via direct ADK invocation

### Demo internet failure mitigation

- Pre-recorded fallback video on laptop
- Local Firestore emulator with pre-seeded scenario
- Phone has app installed with offline-mode functional

### Scope creep

- P0 modules are non-negotiable
- P1 differentiators added only if P0 is stable by Day 10
- P2/P3 are bonus
- 48-hour minimum spec: M0, M1, M7 (4 screens), M2+M3 merged, M4+M5+M6 merged, M15 minimal, M16

### Accessibility

- All Urdu text in proper RTL with Naskh/Nastaliq
- Minimum 16sp body, 20sp+ for SOS/alerts
- Color choices tested for protanopia/deuteranopia (red/green pair has icon backup)
- VoiceOver/TalkBack labels on every interactive element

### Cost guardrails (during hackathon)

- Vertex AI: use Gemini Flash for all high-volume calls (ingestion, comms rendering). Reserve Pro for Detection reasoning only.
- Maps Platform: cache routes for identical origin/destination pairs for 5 min
- Firestore: enforce TTL on `signals_social` (24h), `signals_traffic` (6h), `radar_warnings` (12h)
- Cloud Run: min instances = 0 for non-orchestrator agents; only orchestrator stays warm

---

*End of specification. Last updated: planning phase, pre-Day 1. Update timestamps as modules ship.*
