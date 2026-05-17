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

## Files
- `config.py` — environment variables, mock endpoint URLs, heuristic constants
- `models.py` — Pydantic models (SimulationReport, DispatchRecord, etc.)
- `tools.py` — Firestore read/write, mock endpoint calls, impact estimation
- `agent.py` — main simulation pipeline logic
- `main.py` — FastAPI service (port 8084)
- `simulation_instruction.md` — detailed LLM instruction
- `test_simulation.py` — comprehensive test suite
