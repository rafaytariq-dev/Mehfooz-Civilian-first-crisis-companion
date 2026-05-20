# Mehfooz — System Architecture

> Last updated: M16 submission. For the demo scenario context, see [`demo_scenario.md`](demo_scenario.md).

---

## 1. System Overview

Mehfooz is a civilian-first crisis companion for Pakistan. It fuses citizen signals, weather data, and traffic feeds into real-time, actionable guidance — delivered per-user in Urdu, Roman Urdu, or English.

```
┌────────────────────────────────────────────────────────────────────────┐
│                         Citizens & Community                           │
│                                                                        │
│  Mobile App (Flutter)          Mosque Admin App        External Feeds  │
│  • Voice / Text / Photo        • Broadcast compose     • Open-Meteo    │
│  • SOS                         • Verified tier         • Google Maps   │
│  • Safe Route                                          • PMD           │
└────────────────┬───────────────────────┬───────────────────┬──────────┘
                 │                       │                   │
                 ▼                       ▼                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│                      Firebase / Cloud Functions                        │
│                                                                        │
│  reports/{id}    signals_weather/    signals_traffic/    signals_social/│
│  events/{id}     plans/{id}          simulation_reports/ broadcasts/   │
│  agent_traces/   push_queue/         mock_dispatches/    helplines/    │
└────────────────────────────┬───────────────────────────────────────────┘
                             │  Firestore triggers + Cloud Scheduler
                             ▼
┌────────────────────────────────────────────────────────────────────────┐
│                  Agent Pipeline (Cloud Run + ADK)                      │
│                                                                        │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐             │
│  │  Ingestion   │    │  Detection   │    │  Planning    │             │
│  │  Agent (M2)  │───▶│  Agent (M3)  │───▶│  Agent (M4)  │             │
│  └──────────────┘    └──────────────┘    └──────────────┘             │
│          │                                       │                     │
│          │  Orchestrator (M6) coordinates        ▼                     │
│          │  all agents + feedback loops  ┌──────────────┐             │
│          └──────────────────────────────▶│  Simulation  │             │
│                                          │  Agent (M5)  │             │
│                                          └──────┬───────┘             │
│                                                 │                     │
│                                          ┌──────▼───────┐             │
│                                          │  Comms Agent │             │
│                                          │   (M6 Orch)  │             │
│                                          └──────────────┘             │
└────────────────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌────────────────────────────────────────────────────────────────────────┐
│                      Users + Authorities                               │
│                                                                        │
│  FCM Push Notifications        M15 Authority Sim Dashboard             │
│  SMS fallback (M13)            mock_dispatches visible in real-time    │
│  WhatsApp deep links (SOS)     Before/After split-screen demo          │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Agent Flow Diagram

The five agents operate in a pipeline coordinated by the Orchestrator. The key innovation is the **feedback loop**: if Detection produces only a candidate event (confidence < 0.6), the Orchestrator re-invokes Ingestion with a targeted social scrape, then re-runs Detection.

```
                      ┌────────────────────────────────────┐
                      │          Orchestrator (M6)          │
                      │   Decides what runs next;           │
                      │   writes traces before each call.   │
                      └─┬──────┬──────┬──────┬──────┬──────┘
                         │      │      │      │      │
           ┌─────────────▼─┐   │      │      │   ┌──▼─────────┐
           │  Ingestion (M2)│   │      │      │   │  Comms (M6) │
           │                │   │      │      │   │             │
           │ • normalize text│   │      │      │   │ • render msg│
           │ • verify photo │   │      │      │   │ • send FCM  │
           │ • fetch weather│   │      │      │   │ • SMS fallbk│
           │ • fetch traffic│   │      │      │   └─────────────┘
           └────────┬───────┘   │      │      │
                    │           │      │      │
                    ▼           │      │      │
           ┌────────────────┐   │      │      │
           │ Detection  (M3) │  │      │      │
           │                │  │      │      │
           │ • DBSCAN cluster│  │      │      │
           │ • ≥2 modalities?│  │      │      │
           │ • calibrate conf│  │      │      │
           └───┬─────────┬──┘   │      │      │
               │         │      │      │      │
          confidence   candidate│      │      │
          ≥ 0.6?        < 0.6   │      │      │
               │         │      │      │      │
               │    ┌────▼──────▼─┐    │      │
               │    │  Feedback   │    │      │
               │    │  Loop       │    │      │
               │    │ (max 2 retry│    │      │
               │    │ social mode)│    │      │
               │    └─────┬───────┘    │      │
               │          │ re-ingest  │      │
               │          └────────────┘      │
               ▼                              │
           ┌────────────────┐                 │
           │ Planning   (M4) │                │
           │                │                │
           │ • per-user acts │                │
           │ • route compute │                │
           │ • helpline look │                │
           └────────┬───────┘                 │
                    │                         │
                    ▼                         │
           ┌────────────────┐                 │
           │ Simulation (M5) │                │
           │                │                │
           │ • mock dispatch │                │
           │ • impact estimate│               │
           │ • summary card  │                │
           └────────┬───────┘                 │
                    │                         │
                    └─────────────────────────┘
                    push_queue → Comms agent sends FCM
```

### Feedback loop example (G-10 demo)

| Cycle | Agent | Confidence | Modalities | Action |
|-------|-------|-----------|------------|--------|
| 1     | Detection | 0.42 | citizen_report only | Candidate — trigger retry |
| Retry | Ingestion | — | social scrape for G-10 polygon | Added 4 social signals |
| 2     | Detection | 0.87 | citizen + weather + traffic | **Verified event** |

---

## 3. Data Flow: One Citizen Report → User Push

```
Citizen speaks Roman Urdu voice report
          │
          ▼
  Flutter app (M7/M8)
  • records audio locally
  • uploads to Cloud Storage
  • writes reports/{id} doc:
    { voice_url, location, user_id }
          │
          ▼
  Cloud Function: onVoiceReportCreated
  • Google Speech-to-Text (ur-PK model)
  • Gemini Flash normalize:
    → text_normalized (English)
    → language_detected: roman_ur
    → crisis_type_inferred: urban_flood
    → severity_user: 3
          │
          ▼
  Firestore: reports/{id} updated
          │
          ▼ (Firestore onCreate trigger)
  Orchestrator (M6) triggered
  → calls Ingestion Agent (M2)
          │
          ▼
  Ingestion Agent
  • fetches Open-Meteo weather (31mm/h rainfall)
  • fetches Google Maps traffic (IJP Road 3.8× congestion)
  • writes signals_weather/{id}, signals_traffic/{id}
          │
          ▼
  Detection Agent (M3)
  • DBSCAN clusters 8 signals in G-10 polygon
  • cross-modal check: citizen_report + weather + traffic = 3 modalities
  • confidence = 0.87 (3 modalities + known flood-prone prior)
  • writes events/{id}: { severity: 4, confidence: 0.87, status: verified }
          │
          ▼
  Planning Agent (M4)
  • finds 47 users near G-10 centroid
  • computes routes (3 alternatives avoiding polygon)
  • looks up helpline: Rescue 1122 ICT
  • writes plans/{id}: { user_actions, system_actions }
          │
          ▼
  Simulation Agent (M5)
  • POST /mockPdmaDispatch → ticket PDMA-001
  • POST /mockRescue1122 → ticket R1122-001
  • writes push_queue entries (sos, high, med tiers)
  • writes simulation_reports/{id}: { summary_en, estimated_impact }
          │
          ▼
  Comms Agent (M6)
  • reads push_queue
  • renders per-user message in user.language (Urdu/English/Roman Urdu)
  • sends FCM high-priority push
  • SMS fallback for users without recent FCM activity
          │
          ▼
  User receives push notification:
  "EVACUATE — Mehfooz: Sev 4 flooding in G-10.
   3 routes available. Call Rescue 1122."
```

---

## 4. Mobile App Screens

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Flutter App Screens                          │
│                                                                     │
│  S1 Onboarding    S2 Home/Map      S3 Report         S4 Situation  │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐      ┌──────────┐  │
│  │ Language │     │ Map +    │     │ Voice /  │      │ Severity │  │
│  │ picker   │     │ polygons │     │ Text /   │      │ chip +   │  │
│  │ OTP auth │     │ FABs:    │     │ Photo    │      │ Modality │  │
│  │ Contacts │     │ Report   │     │ tabs     │      │ breakdown│  │
│  └──────────┘     │ SOS      │     └──────────┘      │ What to  │  │
│                   │ 🎬Demo   │                        │ do card  │  │
│  S5 Safe Route    └──────────┘     S6 SOS            └──────────┘  │
│  ┌──────────┐                      ┌──────────┐                     │
│  │ Origin/  │     S7 Agent         │ Hold 2s  │      S8 Profile    │
│  │ Dest     │     Trace            │ button   │      ┌──────────┐  │
│  │ Women's  │     ┌──────────┐     │ WhatsApp │      │ Contacts │  │
│  │ safe     │     │ Steps +  │     │ deeplink │      │ Language │  │
│  │ mode     │     │ reasoning│     │ Helpline │      │ Notif    │  │
│  │ 3 routes │     │ tools    │     │ button   │      │ prefs    │  │
│  └──────────┘     └──────────┘     └──────────┘      └──────────┘  │
│                                                                     │
│  + M16 Demo Theater (accessed via 🎬 button on home)               │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 5. Trust Tier Model

```
┌─────────────────────────────────────────────────────────────┐
│                       Trust Tiers                           │
│                                                             │
│  ●  CITIZEN                                                 │
│     Color: Yellow                                           │
│     Source: Any registered app user                         │
│     Verification: Reputation system (0–100) + corroboration│
│     Threshold: Reputation < 20 → excluded from clustering   │
│                                                             │
│  ●  COMMUNITY BROADCASTER (Mosque Admin)                    │
│     Color: Green                                            │
│     Source: Verified mosque/community admins                │
│     Verification: Manual review (CNIC + letter)             │
│     Demo: Pre-seeded admins (Faisal Mosque, etc.)           │
│     Limits: 1 broadcast/30min, auto-expire 6h              │
│                                                             │
│  ●  AUTHORITY                                               │
│     Color: Blue                                             │
│     Source: Official government feeds (PMD, PDMA)           │
│     Note: In demo, authority data is SIMULATED              │
│           via mock endpoints + replay weather feed          │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. Firestore Collections

| Collection | Module | Description |
|---|---|---|
| `users/` | M1 | User profiles, location, FCM token, reputation |
| `reports/` | M1, M8 | Citizen reports (text, voice, photo) |
| `signals_weather/` | M2 | Normalized Open-Meteo / PMD weather signals |
| `signals_traffic/` | M2 | Google Maps Routes API traffic anomalies |
| `signals_social/` | M2 | Pre-scraped tweet cache |
| `events/` | M3 | Detected crisis events (candidate / verified / resolved) |
| `plans/` | M4 | System + per-user action plans |
| `simulation_reports/` | M5 | Mock dispatch outcomes + impact estimates |
| `mock_dispatches/` | M5 | PDMA / Rescue 1122 mock tickets |
| `push_queue/` | M5, M6 | Notification queue (sos / high / med / low) |
| `agent_traces/` | All | Full reasoning chain for every agent run |
| `broadcasts/` | M14 | Mosque admin broadcasts |
| `mosques/` | M14 | Verified community broadcaster profiles |
| `helplines/` | M10 | Emergency numbers by city + crisis type |
| `safe_spots/` | M4, M11 | Hospitals, malls, mosques as safe spots |
| `flood_prone_locations/` | M9 | Underpass / nullah radar thresholds |
| `radar_warnings/` | M9 | Dedup keys: user_id + location_id, 6h TTL |

---

## 7. Infrastructure

| Component | Service | Region |
|---|---|---|
| Mobile app | Android / iOS (Flutter) | — |
| Database | Firestore (Native mode) | asia-south1 |
| Agents | Cloud Run (Python FastAPI + ADK) | asia-south1 |
| Functions | Cloud Functions 2nd gen (TypeScript) | asia-south1 |
| Storage | Cloud Storage (voice, photos) | asia-south1 |
| AI | Vertex AI — Gemini 2.5 Flash + Pro | us-central1 |
| Auth | Firebase Authentication (Phone OTP) | — |
| Push | Firebase Cloud Messaging | — |
| Dashboard | Firebase Hosting (React + Vite) | global CDN |

---

## 8. Confidence Gating Rule

```
Signal → Event promotion requires:
  • ≥ 2 distinct modalities corroborating
  • Modalities: citizen_report | weather | traffic | social | photo_verified

Confidence scale:
  2 modalities, no flood-prone prior:     0.50 – 0.65  → candidate
  2 modalities + flood-prone location:    0.65 – 0.80  → verified
  3+ modalities + flood-prone location:   0.80 – 0.95  → verified (high)
  Max confidence allowed:                 0.95 (never 1.0)
```
