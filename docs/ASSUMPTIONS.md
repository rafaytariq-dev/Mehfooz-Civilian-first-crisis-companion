# Mehfooz — Assumptions & Honest Disclosures

> This document lists every mock, simplification, replay, and heuristic in the system.
> Judges and reviewers should read this to understand what is real vs. simulated.
>
> **We believe this transparency builds more credibility than hiding it.**

---

## 1. Authority Dispatch — Simulated

**What we show:** PDMA and Rescue 1122 tickets appear in the M15 dashboard in real-time as agents run.

**What is real:** The ticket creation, the Firestore writes, the dashboard UI, and the agent reasoning that decides when to dispatch.

**What is simulated:** The actual API call. We POST to Cloud Functions (`/mockPdmaDispatch`, `/mockRescue1122`) that write to `mock_dispatches/` — no real authority system receives these.

**Production path:** Requires bilateral API agreements with PDMA, NDMA, Rescue 1122, and CDA. Each authority has its own integration format. This is a realistic integration point, not a technical barrier.

---

## 2. Weather Data — Replayed from Real 2025 PMD/Open-Meteo Data

**What we show:** Rainfall escalating from 8 mm/h to 42 mm/h during the G-10 demo scenario.

**What is real:** The underlying weather data is based on real Open-Meteo readings from Islamabad during the August–September 2025 monsoon season.

**What is simulated:** The timestamps are shifted to "now" by `data/replay_scenario.py`. We are not calling Open-Meteo live during the demo — we stream pre-seeded documents from `signals_weather/` with replayed timestamps.

**In production:** The Ingestion Agent calls Open-Meteo every 2 minutes via Cloud Scheduler. PMD is a best-effort scrape with Open-Meteo as fallback.

---

## 3. Impact Estimates — Heuristics, Not Baselines

The simulation report includes:

```
47 users alerted · 3 routes flagged · 2 tickets dispatched
Est. 22 min congestion reduction
```

**What is real:** 47 users, 3 routes, and 2 tickets are exact counts from the plan and simulation run.

**What is estimated (heuristic):** The "22 min congestion reduction" is computed as:

```python
diverted = count of REROUTE actions           # e.g., 12
avg_delay_saved = 22  # minutes (eyeballed for severity ≥ 4 urban floods)
congestion_reduction_min = diverted * 0.3 * avg_delay_saved
```

This is a simplified model. Production would require calibration against historical traffic data (e.g., Google Maps historical duration API, PTCL/NHA traffic monitoring).

**In all UI, README, and demo scripts:** We label these as "Est." or "estimates." We never present them as measured outcomes.

---

## 4. Mosque Admin Verification — Manual (Demo Pre-seeded)

**What we show:** Mosque admins can post verified broadcasts, displayed with a green trust tier.

**What is real:** The broadcast mechanism, geofence fan-out, FCM delivery, and mute controls.

**What is simplified:** In the demo, 3–5 mosque admins are pre-seeded directly in Firestore. The production verification flow (CNIC submission + letterhead + ops review) is described in the spec but not implemented.

**Production path:** Partnership with Alkhidmat Foundation or PDMA for verification infrastructure is the most practical route.

---

## 5. Social Media Signals — Pre-scraped Cache (Not Live)

**What we show:** "Signals from social media" contributing to event detection.

**What is real:** Tweets in `signals_social/` that the Detection Agent clusters against other signals. The content is based on real Pakistan flood tweets from 2025.

**What is simplified:** We cannot scrape Twitter/X live during the demo (API access constraints). The `signals_social/` collection is pre-seeded with ~100 anonymized, pseudonymized entries shifted to demo timestamps.

**In production:** The Ingestion Agent's `fetch_social_cached` tool would be replaced by a real-time scraper (or X API v2 filtered stream) writing to `signals_social/`.

---

## 6. Citizen Report User Locations — Seeded, Not Live GPS

**What we show:** 5 demo users in different parts of G-10/G-11 receiving different action recommendations.

**What is real:** The Planning Agent correctly applies the per-user decision tree (EVACUATE / REROUTE / AVOID_AREA / CHECK_ON_FAMILY) based on each user's seeded location vs. the event polygon.

**What is seeded:** `data/seed_users.json` pre-positions users in specific grid sectors. These are not real people — they are synthetic personas for the demo.

---

## 7. Gemini Live API (Option A Voice) — Not Yet in Production Build

**What we show:** Voice reports via M8 (voice tab → Speech-to-Text → Gemini normalize).

**What is implemented:** The two-stage pipeline (Option B): local recording → Cloud Storage upload → Cloud Function → Google Speech-to-Text (ur-PK) → Gemini Flash normalize.

**What is not yet wired:** Gemini Live API streaming (Option A). The `GeminiLiveSession` code path is scaffolded in comments but not deployed — Option B is the working path for the demo.

---

## 8. SMS Fallback — System Tray / Draft Only

**What we show:** SOS in offline mode opens a pre-filled SMS draft.

**What is implemented:** `launchUrl(Uri.parse('sms:1122?body=...'))` — this opens the native SMS app pre-filled. The user must press Send.

**What is not implemented:** Automatic SMS gateway dispatch (Twilio / Jazz API). In production, this would require a carrier agreement.

---

## 9. Women's Safe Route OSM Data — One-Time Precompute

**What we show:** Routes scored with a safety penalty for residential/unlit roads when Women's Safe Mode is toggled.

**What is implemented:** The `_safety_penalty()` function in the Planning Agent applies penalty multipliers based on road class.

**What is simplified:** The OSM road segment data (lit=yes/no, landuse, highway class) is pre-computed and stored in `road_segments/` collection for demo cities. Live OSM queries via Overpass API are not called in real-time.

---

## 10. Route Computation — Google Maps Mock Responses for Demo

**What we show:** 3 route alternatives with risk scores in the Safe Route screen.

**What is implemented:** The Planning Agent calls Google Maps Routes API. In the live system, this is real.

**Demo note:** If Maps API quota is exceeded or the key is not configured, the Planning Agent falls back to hardcoded G-10 demo routes. Look for `MAPS_FALLBACK` in `agents/planning/tools.py`.

---

## 11. Antigravity — Dev Surface, Not Runtime

**What we show:** Antigravity Manager view with 5 agent workspaces lighting up during the demo.

**What is real:** The agents run on ADK + Cloud Run independently of Antigravity. Antigravity is used as the development and visualization surface.

**Implication:** If Antigravity has any instability during the demo, the system continues to work via direct ADK invocation. The mobile app, dashboard, and push notifications are unaffected.

---

## 12. Reputation System — Seeded Starting Values

**What we show:** Users have reputation scores (0–100) affecting how their reports are weighted.

**What is implemented:** The algorithm (+5 per corroborated report, −10 per flagged report, exclusion below 20) is implemented in Detection Agent clustering.

**What is seeded:** Demo users start at pre-set reputation values (50–80) to ensure the G-10 scenario runs correctly. A new production user starts at 50.

---

## Summary Table

| Component | Real | Simulated / Seeded | Production Path |
|---|---|---|---|
| Authority dispatch | Logic + UI | Mock endpoints | API agreements with PDMA/NDMA |
| Weather data | Real 2025 data | Replayed timestamps | Live Open-Meteo every 2 min |
| Impact estimates | Counts exact | Heuristic formula | Historical traffic baseline |
| Mosque verification | Mechanism | Pre-seeded admins | CNIC + ops review flow |
| Social signals | Real tweet content | Pre-scraped, not live | X API filtered stream |
| User locations | Decision logic | Synthetic personas | Live GPS from app |
| Gemini Live (voice) | Option B works | Option A scaffolded | Enable when stable |
| SMS fallback | Draft opens | No auto-send | Carrier gateway integration |
| OSM road data | Penalty function | Precomputed batch | Real-time Overpass API |
| Route computation | Google Maps API | Fallback if quota | Production Maps key |
