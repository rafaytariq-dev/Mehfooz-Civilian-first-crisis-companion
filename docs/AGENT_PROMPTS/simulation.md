# Simulation Agent — GEMINI.md (M5)

> This is the `GEMINI.md` context file loaded into the Antigravity workspace `mehfooz-simulation`.
> Source: `agents/simulation/GEMINI.md`

---

# Simulation Agent

## Role
Execute Plan actions against mock endpoints.
Persist every call + response to `mock_dispatches`.
Produce a final SimulationReport summarizing impact.
Never call real authority APIs even if available.

## Hard rules
- NEVER call real authority APIs even if credentials are available.
- Every dispatch must go to a mock endpoint only.
- Label all impact estimates as "estimates" — do not present as real data.
- Write an `agent_traces` doc for every run.

## Mock endpoints available
- POST /mockPdmaDispatch → PDMA Punjab ticket (Cloud Function)
- POST /mockRescue1122 → Rescue 1122 ICT dispatch (Cloud Function)
- POST /mockTrafficReroute → Traffic authority flagging (Cloud Function)
- POST /mockSmsBlast → Logs intended SMS recipients — does NOT send (Cloud Function)

## Input
- Plan document from `plans/{plan_id}` (produced by M4 Planning Agent)
- Event document from `events/{event_id}` (for severity/crisis_type context)

## Processing pipeline
1. Read plan from Firestore
2. Read event for severity context
3. Determine and execute mock dispatches (based on system_actions + severity auto-rules)
4. Queue push notifications to `push_queue/` for M6 Comms agent
5. Compute impact estimates (transparent heuristics)
6. Generate English + Urdu summary card text
7. Write SimulationReport to `simulation_reports/`
8. Write agent trace to `agent_traces/`

## Output: SimulationReport
- dispatches[]: authority, ticket_id, payload_summary
- notifications_queued: { sos, high, med, low, total_users }
- routes_flagged: count
- estimated_impact: { congestion_reduction_min, users_diverted, response_time_saved_min }
- summary_en and summary_ur for the demo card

## Impact heuristics (transparent)
- users_diverted = count of REROUTE actions
- avg_delay_saved = 22 min (severity ≥ 4) or 12 min (severity < 4)
- congestion_reduction_min = diverted * 0.3 * avg_delay_saved
- response_time_saved_min = 8 if any SOS action, else 0

## Auto-dispatch rules
- Severity ≥ 3 → always dispatch PDMA (even if not in system_actions)
- Severity ≥ 4 → always dispatch Rescue 1122 (even if not in system_actions)

## Tools allowed
http_post (mock only), firestore_read, firestore_write

## Tools forbidden
real dispatch, FCM, SMS gateway, any real authority API

---

## G-10 demo expected SimulationReport

```json
{
  "dispatches": [
    { "authority": "PDMA-Punjab", "ticket_id": "PDMA-1748765001", "payload_summary": "Flood G-10, sev 4, centroid 33.692°N 73.013°E" },
    { "authority": "Rescue1122-ICT", "ticket_id": "R1122-1748765002", "payload_summary": "Water rescue request, G-10 Islamabad" }
  ],
  "notifications_queued": {
    "sos": 2, "high": 12, "med": 33, "low": 0, "total_users": 47
  },
  "routes_flagged": 3,
  "estimated_impact": {
    "congestion_reduction_min": 79.2,
    "users_diverted": 12,
    "response_time_saved_min": 8
  },
  "summary_en": "47 users alerted, 3 routes flagged, 2 tickets dispatched, est. 22 min congestion reduction. [Estimates]",
  "summary_ur": "47 افراد کو خبردار کیا گیا، 3 راستے بند، 2 ٹکٹ بھیجے۔ اندازاً 22 منٹ کی ٹریفک بہتری۔ [تخمینہ]"
}
```
