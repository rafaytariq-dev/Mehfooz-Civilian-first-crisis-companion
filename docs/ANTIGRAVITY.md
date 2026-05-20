# Mehfooz — Antigravity Workspace Guide

> This document explains how Antigravity is used in the Mehfooz project:
> what each workspace contains, how the Manager view is structured,
> and what to expect during a live demo run.

---

## Overview

Antigravity is the **development and visualization surface** for Mehfooz's ADK agents. It is not the runtime — agents deploy to Cloud Run independently. If Antigravity has any instability during the demo, the pipeline continues working via direct ADK invocation.

We use Antigravity for:
1. **Development:** Each agent has its own workspace with a `GEMINI.md` context file, making agent behavior transparent and editable.
2. **Demo visualization:** The Manager view shows all 5 agents activating in parallel during a G-10 scenario run — this is the "agents lighting up" moment at 1:15–2:15 of the demo script.
3. **Trace export:** Plan Artifacts from each workspace are exported to `data/sample_traces.json` for the submission package.

---

## Workspace Map

| Workspace | Agent | Module | GEMINI.md location |
|---|---|---|---|
| `mehfooz-ingestion` | Ingestion Agent | M2 | `agents/ingestion/GEMINI.md` |
| `mehfooz-detection` | Detection & Reasoning Agent | M3 | `agents/detection/GEMINI.md` |
| `mehfooz-planning` | Planning Agent | M4 | `agents/planning/GEMINI.md` |
| `mehfooz-simulation` | Simulation Agent | M5 | `agents/simulation/GEMINI.md` |
| `mehfooz-orchestrator` | Orchestrator + Comms | M6 | `agents/orchestrator/GEMINI.md` |

---

## Workspace 1: mehfooz-ingestion (M2)

### Purpose
Pulls raw signals from all sources, normalizes them into a uniform Signal shape, and writes to Firestore.

### Context file (`agents/ingestion/GEMINI.md`)
Defines the agent's role, allowed/forbidden tools, and key normalization rules:
- Roman Urdu → Urdu → English two-step translation
- Photo verification via Gemini Vision (does not assume match)
- PMD fallback to Open-Meteo with trace logging

### Tools registered
`fetch_open_meteo`, `fetch_pmd_overlay`, `fetch_traffic`, `verify_photo`, `normalize_text`, `fetch_social_cached`, `write_signal`

### What you see in Antigravity
During the G-10 replay:
1. Agent receives: `{ report_id: "rpt-g10-demo-001", polygon: G-10 bounds }`
2. Agent calls tools in parallel: weather + traffic + social scrape
3. Plan Artifact shows: `reports_processed: 8, weather_signals: 3, traffic_signals: 1`
4. Trace written to `agent_traces/` with tool call details

---

## Workspace 2: mehfooz-detection (M3)

### Purpose
Clusters signals spatially and temporally, gates on multi-modal corroboration, and emits `Event` docs with calibrated confidence.

### Context file (`agents/detection/GEMINI.md`)
Hard rules visible in GEMINI.md:
- No event promotion without ≥2 modalities
- Confidence never reaches 1.0
- Explanation must cite specific modalities and numbers

### Algorithm
DBSCAN spatial-temporal clustering (`eps=0.5km`, `min_samples=3`, haversine metric).

### What you see in Antigravity
The **feedback loop** is the key visual during demo:
1. Cycle 1 → confidence 0.42, modality_count=1 → candidate event
2. Orchestrator triggers Ingestion retry (social mode, +5 min window)
3. Cycle 2 → confidence 0.87, modality_count=3 → verified event

The Plan Artifact shows the reasoning chain:
```
Cluster 0: 8 signals in G-10 sector, lat 33.692 ±0.3km
Modalities: citizen_report (8), weather (1), traffic (1)
Prior check: flood_prone_locations match → Faizabad underpass threshold 15mm/h
Confidence: 0.87 (3 modalities + flood-prone prior)
```

---

## Workspace 3: mehfooz-planning (M4)

### Purpose
Converts verified events into two parallel action tracks: system coordination and per-user guidance.

### Context file (`agents/planning/GEMINI.md`)
Per-user decision tree is embedded in GEMINI.md with the 6 action verbs and routing rules.

### What you see in Antigravity
For the G-10 event (severity 4):
- System actions: `notify_helpline (Rescue 1122)`, `flag_route (IJP Road)`, `broadcast_zone (5km radius)`
- User u_001 (in polygon, sev 4): EVACUATE → 3 safe spots computed
- User u_002 (driving through polygon): REROUTE → 3 alternatives
- User u_004 (2km away, family in polygon): CHECK_ON_FAMILY

Plan Artifact includes:
- Route computation results (3 alternatives, none crossing flood polygon)
- Helpline resolution: Rescue 1122 ICT (exact city match, flood type match, water rescue note)

---

## Workspace 4: mehfooz-simulation (M5)

### Purpose
Executes plan actions against mock endpoints. Produces an auditable `SimulationReport` with the demo impact card.

### Context file (`agents/simulation/GEMINI.md`)
Hard rule prominently displayed: **"NEVER call real authority APIs even if credentials are available."**

### Mock endpoints
All four Cloud Functions (`/mockPdmaDispatch`, `/mockRescue1122`, `/mockTrafficReroute`, `/mockSmsBlast`) write to `mock_dispatches/` — nothing is sent to real authorities.

### What you see in Antigravity
Plan Artifact:
```json
{
  "dispatches": [
    { "authority": "PDMA-Punjab", "ticket_id": "PDMA-1748765001" },
    { "authority": "Rescue1122-ICT", "ticket_id": "R1122-1748765002" }
  ],
  "notifications_queued": { "sos": 2, "high": 12, "med": 33, "low": 0, "total": 47 },
  "routes_flagged": 3,
  "estimated_impact": { "congestion_reduction_min": 79.2, "users_diverted": 12 },
  "summary_en": "47 users alerted, 3 routes flagged, 2 tickets dispatched, est. 22 min congestion reduction."
}
```

---

## Workspace 5: mehfooz-orchestrator (M6)

### Purpose
Meta-agent that routes between sub-agents, manages the feedback loop, and acts as the Comms agent.

### Context file (`agents/orchestrator/GEMINI.md`)
Defines:
- Feedback loop rule (retry ingestion if candidate confidence < 0.6)
- Termination rule (stop after simulation_report written OR 3 cycles)
- Comms batching rules by urgency tier

### What you see in Antigravity
The Orchestrator workspace shows the **full pipeline trace** including the retry:
```
[T+0s]   call_ingestion(report_id="rpt-g10-001") → OK
[T+2s]   call_detection(city=Islamabad)          → candidate 0.42
[T+2s]   feedback: call_ingestion(mode=social)   → +4 social signals
[T+5s]   call_detection(city=Islamabad)          → verified 0.87
[T+7s]   call_planning(event_id=evt-g10-001)     → plan_id=plt-001
[T+11s]  call_simulation(plan_id=plt-001)        → report_id=rpt-sim-001
[T+13s]  call_comms(plan_id, report_id)          → 47 FCM queued
[T+14s]  outcome: completed
```

Total chain latency from trigger to first push: **~14 seconds**.

---

## Manager View During Demo

During the Agents beat (1:15–2:15 of the demo script), the Antigravity Manager view should show:

```
┌─────────────────────────────────────────────────────────────┐
│  Mehfooz — Antigravity Manager                      ●LIVE   │
├─────────────────┬───────────────────────────────────────────┤
│  Workspaces     │                                           │
│                 │  [mehfooz-orchestrator]  ████████░░  80%  │
│ ● ingestion  ✓  │    orchestrate(trigger=g10)               │
│ ● detection  ✓  │    cycle 1: candidate 0.42                │
│ ● planning   ✓  │    ↳ retry ingestion (social mode)        │
│ ● simulation ✓  │    cycle 2: verified 0.87                 │
│ ● orchestratr↗  │    → planning → simulation → comms        │
│                 │                                           │
│                 │  Agents completed: 4 of 5                 │
│                 │  Traces written: 8                        │
└─────────────────┴───────────────────────────────────────────┘
```

**Demo tip:** Point explicitly to the confidence rising from 0.42 to 0.87 — this is the agentic behavior (not a simple rule, but a reasoned retry based on low evidence).

---

## Exporting Plan Artifacts

After running the G-10 scenario:

1. In each workspace, open the Plan Artifacts panel
2. Export as JSON
3. Combine into `data/sample_traces.json` for the submission package

The pre-exported traces are already in `data/sample_traces.json` from the most recent G-10 run.

---

## Browser Integration Screenshots (for submission)

Capture these during a live demo run:
1. **Manager overview** — all 5 workspaces with activity indicators
2. **Ingestion workspace** — showing tool calls (normalize_text, verify_photo)
3. **Detection workspace** — showing the confidence step from 0.42 to 0.87
4. **Orchestrator workspace** — showing the feedback loop trace
5. **Plan Artifact panel** — from the Simulation workspace, showing the impact numbers

These should be committed to `docs/screenshots/` for the submission repo.
