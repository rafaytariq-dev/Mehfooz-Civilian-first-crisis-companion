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

---

## GCP Infrastructure

See [`docs/gcp_setup.md`](docs/gcp_setup.md) for the full setup runbook.

- **Project:** `mehfooz-prod`
- **Region:** `asia-south1` (Mumbai)
- **Stack:** Firebase + Cloud Run + Vertex AI (Gemini 2.5) + Cloud Functions (2nd gen)

---

## Agent Architecture

```
citizen report → Ingestion Agent → signals_*
                                        ↓
                              Detection Agent → events/
                                        ↓
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
| M1 | Data Spine | 🔜 Next |
| M2 | Ingestion Agent | ⬜ Pending |
| M3 | Detection & Reasoning Agent | ⬜ Pending |
| M4 | Planning Agent | ⬜ Pending |
| M5 | Simulation Agent | ⬜ Pending |
| M6 | Comms Agent + Orchestrator | ⬜ Pending |
| M7 | Mobile App Core (Flutter) | ⬜ Pending |
| M8–M16 | Extended Modules | ⬜ Pending |

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

## Contributing

1. Branch from `develop`: `git checkout -b feat/m1-data-spine`
2. Keep agent code in its own folder under `agents/`
3. Every agent must have: `GEMINI.md`, `main.py` (FastAPI), `tools.py`, `requirements.txt`, `Dockerfile`
4. Write traces to `agent_traces/` on every run
5. PR → `develop` → squash merge to `main` triggers deploy

---

## License

MIT — see `LICENSE`
