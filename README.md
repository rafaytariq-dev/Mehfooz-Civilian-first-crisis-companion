# Mehfooz (محفوظ)

> **Civilian-first crisis companion for Pakistan.**
> Fuse citizen signals + official feeds. Tell each user what to do, right now, where they are.

[![Flutter Build](https://github.com/mehfooz-team/mehfooz/actions/workflows/flutter_build.yml/badge.svg)](https://github.com/mehfooz-team/mehfooz/actions/workflows/flutter_build.yml)
[![Agents Deploy](https://github.com/mehfooz-team/mehfooz/actions/workflows/agents_deploy.yml/badge.svg)](https://github.com/mehfooz-team/mehfooz/actions/workflows/agents_deploy.yml)
[![Functions Deploy](https://github.com/mehfooz-team/mehfooz/actions/workflows/functions_deploy.yml/badge.svg)](https://github.com/mehfooz-team/mehfooz/actions/workflows/functions_deploy.yml)

---

## Demo Scenario

🔒 **Locked:** G-10/G-11 Islamabad Flash Flood — see [`docs/demo_scenario.md`](docs/demo_scenario.md)

```bash
# Run the full demo scenario at 10× speed
python data/replay_scenario.py g10 --speed 10
```

---

## Monorepo Structure

```
mehfooz/
├── app/                 # Flutter mobile app (M7+)
├── agents/              # Python ADK agents on Cloud Run
│   ├── ingestion/       # M2 — pulls & normalizes all signals
│   ├── detection/       # M3 — clusters signals → events
│   ├── planning/        # M4 — events → per-user action plans
│   ├── simulation/      # M5 — executes plans against mock APIs
│   └── orchestrator/    # M6 — meta-agent + comms
├── functions/           # Cloud Functions (TypeScript) — triggers, mock endpoints
├── web/                 # Authority Simulation Dashboard (React) — M15
├── data/                # Seed datasets, helpline DB, underpass list, replay script
├── docs/                # This spec, ADRs, demo script, GCP setup guide
└── GEMINI.md            # Root shared context for all agents
```

---

## Getting Started

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Flutter | 3.24+ | [flutter.dev](https://flutter.dev) |
| Python | 3.12+ | [python.org](https://python.org) |
| Node.js | 20+ | [nodejs.org](https://nodejs.org) |
| gcloud CLI | latest | [cloud.google.com/sdk](https://cloud.google.com/sdk) |
| Firebase CLI | latest | `npm install -g firebase-tools` |
| Docker | latest | [docker.com](https://docker.com) |

### 1. Clone & verify Flutter

```bash
git clone https://github.com/mehfooz-team/mehfooz.git
cd mehfooz/app
flutter pub get
flutter doctor  # should be all green
```

### 2. Run Firebase emulators locally

```bash
firebase emulators:start
# Firestore: http://localhost:4000
# Auth: http://localhost:9099
# Functions: http://localhost:5001
```

### 3. Run an agent locally

```bash
cd agents/ingestion
pip install -r requirements.txt
uvicorn main:app --reload --port 8081
curl http://localhost:8081/health
```

### 4. Run demo scenario (against emulators)

```bash
python data/replay_scenario.py g10 --emulator --speed 10
```

### 5. Run the Authority Dashboard (M15)

```bash
cd web
cp .env.example .env          # fill in your Firebase + Maps API keys
npm install
npm run dev                   # http://localhost:5173
```

To build for Firebase Hosting:

```bash
npm run build
firebase deploy --only hosting
```

---

## GCP Infrastructure

See [`docs/gcp_setup.md`](docs/gcp_setup.md) for the full setup runbook.

- **Project:** `mehfooz-prod`
- **Region:** `asia-south1` (Mumbai)
- **Stack:** Firebase + Cloud Run + Vertex AI (Gemini 2.5) + Cloud Functions (2nd gen)

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  Flutter App (Android / iOS)    Mosque Admin    External Feeds      │
│  Voice · Text · Photo · SOS     Broadcasts      Open-Meteo · Maps   │
└────────────────────┬────────────────┬─────────────────┬────────────┘
                     │                │                 │
                     ▼                ▼                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│           Firebase (Firestore · Auth · FCM · Storage)               │
│  reports/  signals_*/  events/  plans/  simulation_reports/         │
│  broadcasts/  helplines/  safe_spots/  flood_prone_locations/       │
└────────────────────────────┬────────────────────────────────────────┘
                             │  Firestore triggers + Cloud Scheduler
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│          Agent Pipeline — Cloud Run (Python ADK + Gemini 2.5)       │
│                                                                     │
│  Ingestion → Detection ──► Planning → Simulation → Comms            │
│     (M2)      (M3)    │     (M4)       (M5)         (M6)            │
│                  ↑    │                                             │
│           Feedback loop│ ← Orchestrator (M6) coordinates all        │
│           retry social ┘   and writes agent_traces/ per step        │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  FCM Push to users            M15 Authority Dashboard               │
│  (SOS · high · med · low)     mock_dispatches/ real-time stream     │
│  SMS fallback (offline)       Before/After split-screen demo        │
└─────────────────────────────────────────────────────────────────────┘
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for full diagrams including agent flow, data flow for one report, screen map, and trust tier model.

## Agent Architecture

```
citizen report → Ingestion Agent → signals_*
                                        ↓
                              Detection Agent → events/
                              (≥2 modalities gate)
                                        ↓ [feedback loop if candidate]
                               Planning Agent → plans/
                                        ↓
                             Simulation Agent → mock_dispatches/ + simulation_reports/
                                        ↓
                    Orchestrator + Comms Agent → FCM push to users
```

All agents are coordinated by the Orchestrator. Each run writes to `agent_traces/` for full transparency.

---

## Crisis Coverage

`flood` | `urban_flood` | `flash_flood` | `heatwave` | `road_incident` | `fire` | `building_collapse` | `power_outage` | `air_quality` | `glof`

Cities: **Islamabad** · **Rawalpindi** · **Karachi** · **Lahore**

---

## Languages

Urdu (Nastaliq) · Roman Urdu · English · Code-mixed

---

## Module Status

| Module | Description | Status |
|--------|-------------|--------|
| M0 | Foundations & Project Setup | ✅ Done |
| M1 | Data Spine | ✅ Done |
| M2 | Ingestion Agent | ✅ Done |
| M3 | Detection & Reasoning Agent | ✅ Done |
| M4 | Planning Agent | ✅ Done |
| M5 | Simulation Agent | ✅ Done |
| M6 | Comms Agent + Orchestrator | ✅ Done |
| M7 | Mobile App Core (Flutter) | ✅ Done |
| M8 | Voice Reporting (STT + Gemini) | ✅ Done |
| M9 | Underpass Flood Radar | ✅ Done |
| M10 | Smart Helpline Router | ✅ Done |
| M11 | Heatwave Personal Advisor | ✅ Done |
| M12 | Women's Safe Route Layer | ✅ Done |
| M13 | Offline-First Crisis Kit | ✅ Done |
| M14 | Mosque Admin Broadcast | ✅ Done |
| M15 | Authority Simulation Dashboard | ✅ Done |
| M16 | Demo Theater & Submission | ✅ Done |

---

## CI/CD

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| `flutter_build.yml` | Push to `app/**` | Build + test Flutter app, upload APK artifact |
| `agents_deploy.yml` | Push to `agents/**` | Deploy changed agents to Cloud Run, health-check |
| `functions_deploy.yml` | Push to `functions/**` | Build TS, deploy Cloud Functions, smoke-test mock endpoint |

**Required GitHub Secrets:**
- `GCP_SA_KEY_CI` — JSON key for `ci@mehfooz-prod.iam.gserviceaccount.com`

---

## Demo Theater (M16)

The app includes a built-in demo guide accessible via the 🎬 button on the home map screen.

It provides:
- **6-beat script** with timing (0:00–4:00) and talking points
- **Live countdown timer** to keep the demo on pace
- **Quick navigation** to each relevant app screen per beat
- **Demo readiness checklist** (backend, phone, M15 dashboard, rehearsals)
- **Replay controls** — command to run `python data/replay_scenario.py g10 --speed 10`
- **Impact card** with the final numbers (labeled as estimates)

### Submission deliverables

| Deliverable | Location |
|---|---|
| Architecture diagram | `docs/ARCHITECTURE.md` |
| Assumptions & mocks | `docs/ASSUMPTIONS.md` |
| Antigravity guide | `docs/ANTIGRAVITY.md` |
| Agent prompts | `docs/AGENT_PROMPTS/` |
| Sample traces | `data/sample_traces.json` |
| Demo scenario | `docs/demo_scenario.md` |

---

## Honesty Disclosures

The following components are **simulated** in this demo. We document them clearly because we believe transparency builds more credibility than hiding limitations.

> **Authority dispatch is simulated.** Production would require API agreements with PDMA / NDMA / Rescue 1122. Mock endpoints write to Firestore — no real authority system receives requests.

> **Weather data is replayed.** The demo streams pre-seeded weather documents from `signals_weather/` with timestamps shifted to "now", based on real 2025 Open-Meteo data for Islamabad.

> **Impact estimates are heuristics.** "22 min congestion reduction" is computed as `diverted_users × 0.3 × avg_delay_saved`. Not measured data — a transparent formula for demonstration.

> **Mosque admin verification is manual.** The demo uses 3–5 pre-seeded admins. Production requires CNIC + letterhead submission + ops review.

> **Social signals are pre-scraped.** `signals_social/` contains anonymized 2025 flood tweets with replayed timestamps. Live X API scraping is not active during the demo.

See [`docs/ASSUMPTIONS.md`](docs/ASSUMPTIONS.md) for the full breakdown of every mock and simplification.

---

## Contributing

1. Branch from `develop`: `git checkout -b feat/m1-data-spine`
2. Keep agent code in its own folder under `agents/`
3. Every agent must have: `GEMINI.md`, `main.py` (FastAPI), `tools.py`, `requirements.txt`, `Dockerfile`
4. Write traces to `agent_traces/` on every run
5. PR → `develop` → squash merge to `main` triggers deploy

---

## License

Apache 2.0 — see `LICENSE`
