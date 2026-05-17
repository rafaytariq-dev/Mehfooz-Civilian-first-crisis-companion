# Planning Agent (M4) — Implementation Guide

## Overview

The **Planning Agent** is the M4 module in the Mehfooz crisis companion system. It converts verified crisis Events into actionable Plans with two parallel tracks:

1. **System Actions** — Notify helplines, flag routes, broadcast alerts
2. **Per-User Actions** — Personalized guidance for each user near the event

---

## Architecture

```
┌──────────────────┐
│   Verified Event │
│   (from M3)      │
└────────┬─────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────┐
│         Planning Agent (FastAPI)                        │
│  ┌──────────────────────────────────────────────────┐  │
│  │ 1. Read event from Firestore                     │  │
│  │ 2. Get users within 5km radius                   │  │
│  │ 3. Apply per-user decision tree                  │  │
│  │ 4. Compute system-level actions                  │  │
│  │ 5. Write plan + trace to Firestore               │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────┐
│   Plan Document              │
│  - system_actions[]          │
│  - user_actions{user: ...}   │
└──────────────────────────────┘
         │
         ▼
┌──────────────────────┐
│   Comms Agent (M6)   │
│   executes actions   │
└──────────────────────┘
```

---

## File Structure

```
agents/planning/
├── models.py              # Pydantic schemas (Plan, UserAction, etc.)
├── tools.py               # Firestore ops, geo utilities, route computation
├── agent.py               # Core decision tree logic
├── main.py                # FastAPI service (GET /health, POST /plan/run)
├── requirements.txt       # Python dependencies
├── Dockerfile             # Container image for Cloud Run
├── test_planning.py       # Unit & integration tests
├── GEMINI.md              # Agent context + hardcoded rules
└── README.md              # This file
```

---

## API Endpoints

### `GET /health`

Health check endpoint.

**Response:**
```json
{
  "status": "ok",
  "service": "planning-agent",
  "version": "1.0.0"
}
```

---

### `POST /plan/run`

Run the planning agent against a Firestore event.

**Request Body:**
```json
{
  "event_id": "events/event-001",
  "dry_run": false
}
```

**Response:**
```json
{
  "plan_id": "uuid",
  "event_id": "events/event-001",
  "system_actions_count": 3,
  "user_actions_count": 12,
  "duration_ms": 1200,
  "errors": []
}
```

---

### `POST /plan/test`

Smoke test without Firestore (mock data).

**Response:**
```json
{
  "status": "ok",
  "test": "planning",
  "mock_event_id": "test-event-001",
  "mock_severity": 4
}
```

---

## Per-User Decision Tree

For each user U within 5km of event E:

### 1. User in polygon + Severity ≥ 4 → **EVACUATE**
- Action verb: `EVACUATE`
- Include: 3 nearest safe spots (shelters), helpline contact
- Urgency: `sos`
- Message EN: `"EVACUATE: Level 4 flooding nearby. Seek shelter. Call 1122."`
- Message UR: `"فوری نکلیں: سنگین سیلاب ہے۔ محفوظ جگہ تلاش کریں۔"`

### 2. User in polygon + Severity ≤ 3 → **SHELTER_IN_PLACE**
- Action verb: `SHELTER_IN_PLACE`
- Include: Helpline contact, neighbor list (optional)
- Urgency: `med` or `high` based on severity
- Message EN: `"SHELTER IN PLACE: Stay home, monitor updates. Help: 1122."`
- Message UR: `"گھر میں رہیں: پانی کا خطرہ۔ اپ ڈیٹ سنیں۔"`

### 3. Active nav route through polygon → **REROUTE**
- Action verb: `REROUTE`
- Include: 3 alternative routes (sorted by safety, duration)
- Urgency: `med`
- Message EN: `"REROUTE: Flooding on your route. Use alternate paths below."`
- Message UR: `"راستہ بدلیں: اپ کے راستے میں پانی ہے۔"`

### 4. Within 2km + Severity ≥ 3 → **AVOID_AREA**
- Action verb: `AVOID_AREA`
- Include: Event details
- Urgency: `med`
- Message EN: `"AVOID: Crisis 2km away. Don't travel toward area."`
- Message UR: `"علاقہ سے بچیں: شدید صورتحال۔ وہاں مت جائیں۔"`

### 5. Emergency contact in polygon → **CHECK_ON_FAMILY**
- Action verb: `CHECK_ON_FAMILY`
- Include: Contact names/IDs
- Urgency: `med`
- Message EN: `"CHECK ON FAMILY: 2 family members in affected area. Call them."`
- Message UR: `"خاندان سے رابطہ کریں: آپ کے رشتے دار وہاں ہیں۔"`

---

## System Actions

### 1. Notify Helpline
- Type: `notify_helpline`
- Target: Helpline ID from `helplines` collection
- Urgency: Based on severity
- Example payload:
  ```json
  {
    "helpline_name": "Rescue 1122",
    "phone": "1122",
    "crisis_type": "urban_flood",
    "city": "Islamabad",
    "severity": 4,
    "event_id": "...",
    "centroid": {"lat": 33.7295, "lon": 73.1947}
  }
  ```

### 2. Flag Route
- Type: `flag_route`
- Target: Major roads in polygon
- Urgency: Based on severity
- Example payload:
  ```json
  {
    "polygon": [...],
    "severity": 4,
    "reason": "Flooding detected; routes unsafe."
  }
  ```

### 3. Broadcast Zone
- Type: `broadcast_zone` (severity ≥ 4 only)
- Target: 5km radius around centroid
- Urgency: `high` or `sos`
- Example payload:
  ```json
  {
    "centroid": {"lat": 33.7295, "lon": 73.1947},
    "radius_m": 5000,
    "message": "ALERT: Level 4 urban flood. Seek shelter. Call 1122.",
    "severity": 4
  }
  ```

---

## Routing Rules

**Google Maps Routes API Integration:**

1. **Request:** origin → destination + avoid_polygons list
2. **Response:** 3 alternatives, each with:
   - `distance_m`: meters
   - `duration_s`: seconds
   - `risk_score`: 0.0–1.0 (computed by us)
   - `passes_through_flooded`: boolean
   - `risk_explanation`: brief text

**Filtering & Sorting:**

- Reject routes with `passes_through_flooded=true` unless `severity ≤ 1`
- Sort by: `(is_safe, risk_score, duration)`
- If `user.women_safe_route=true`, penalize residential/service roads
- Return top 3 to user

---

## Helpline Lookup

Query logic:
1. Try exact match: `city + crisis_type`
2. Fall back to city only
3. Fall back to generic "Emergency Services" 1122

**Firestore Query:**
```python
helplines.where("city", "==", "Islamabad")
         .where("crisis_type", "==", "urban_flood")
         .limit(1)
```

For G-10 scenario, expected result:
- **Name:** Rescue 1122 or CARES 1122
- **Phone:** 1122
- **Available 24h:** true

---

## Safe Spots Lookup

Find k=3 nearest shelters, hospitals, high-ground to user location.

**Firestore Collection:** `safe_spots`

**Fields (per document):**
- `name`: string
- `type`: "shelter" | "hospital" | "high_ground" | "mosque"
- `location`: GeoPoint
- `capacity_people`: int (optional)
- `contact_phone`: string (optional)
- `is_open`: boolean

**Algorithm:**
- Client-side Haversine distance from user to all spots
- Sort by distance, return top 3
- (TODO: Geohashing for production scale)

---

## Installation & Deployment

### Local Development

```bash
cd agents/planning

# Create virtual environment
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export PROJECT_ID="mehfooz-prod"
export GOOGLE_MAPS_API_KEY="..."
# Google Cloud credentials auto-detected if using gcloud auth

# Run tests
python -m pytest test_planning.py

# Run service
python -m main
# Server starts on http://localhost:8083
```

### Docker Build & Run

```bash
docker build -t mehfooz/planning-agent:latest .
docker run -p 8083:8083 \
  -e PROJECT_ID="mehfooz-prod" \
  -e GOOGLE_MAPS_API_KEY="..." \
  -v ~/.config/gcloud:/root/.config/gcloud \
  mehfooz/planning-agent:latest
```

### Cloud Run Deployment

```bash
gcloud run deploy planning-agent \
  --source . \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars PROJECT_ID=mehfooz-prod \
  --set-env-vars GOOGLE_MAPS_API_KEY=... \
  --memory 512Mi \
  --timeout 60s
```

---

## Testing

### Unit Tests (no Firestore)

```bash
python -m pytest test_planning.py::test_point_in_polygon -v
python -m pytest test_planning.py::test_reroute_logic -v
python -m pytest test_planning.py::test_helpline_lookup -v
```

### Integration Test (requires Firestore + event)

```bash
python -m pytest test_planning.py::test_planning_g10_scenario -v
```

### Manual Test

```bash
curl -X POST http://localhost:8083/plan/run \
  -H "Content-Type: application/json" \
  -d '{"event_id":"g10-flood-001","dry_run":false}'
```

---

## Exit Criteria (M4 Spec)

- [ ] G-10 scenario produces plan with ≥3 system actions
- [ ] Per-user actions for every user within 5km
- [ ] REROUTE returns 3 alternatives; none through flood polygon
- [ ] Helpline correct for Islamabad + urban_flood
- [ ] Plan written to Firestore in < 4 seconds

---

## Limitations & Future Work

1. **Routes API:** Currently mocked (returns dummy routes). Real impl uses Google Maps Routes API.
2. **Geohashing:** Brute-force distance check for users. Prod should use geohashing library.
3. **Women's safe routes:** Stub logic. Real impl needs road classification data.
4. **Offline routes:** No fallback if Maps API down. Should cache key routes.
5. **Multi-language:** Urdu translations are basic. Needs professional localization.

---

## Dependencies

- `fastapi` — Web framework
- `pydantic` — Data validation
- `google-cloud-firestore` — Firestore client
- `google-maps-routing` — Routes API (optional for production)
- `uvicorn` — ASGI server

See `requirements.txt`.

---

## Logs & Debugging

Logs go to stdout (JSON format for Cloud Logging).

**Key fields:**
- `agent`: "planning"
- `step`: "read_event", "get_users_near", "per_user_decision_tree", etc.
- `duration_ms`: execution time
- `tools_called`: auditable tool invocations

**Enable verbose logging:**
```bash
export LOG_LEVEL=DEBUG
python -m main
```

---

## Contact & Support

- **Spec:** See `CIRO_Implementation_Spec.md` (M4 section)
- **Agent context:** See `GEMINI.md` (this agent's hardcoded rules)
- **Related agents:** M3 (Detection), M6 (Comms), M5 (Simulation)

---

*Last updated: 2025-05-17*
*Status: ✅ M4 Core Implementation Complete*
