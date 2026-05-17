# Planning Agent (M4)

## Overview
Converts verified crisis Events into actionable Plans.
Two parallel tracks: **system-level coordination** and **per-user personalized guidance**.

---

## System Track

**Objective:** Notify authorities, flag affected routes, broadcast alerts.

**System Actions:**
1. `notify_helpline` — Alert emergency services for the crisis type + city
   - Payload: helpline ID, phone, event centroid, severity
2. `flag_route` — Mark major roads through polygon as unsafe
   - Payload: polygon, severity, reason
3. `broadcast_zone` — Send alert to all users within 5km (if severity ≥ 4)
   - Payload: centroid, radius, alert message

---

## Per-User Track

**Objective:** For each user near the event, recommend the single best action.

### Action Verbs
- `EVACUATE` — Leave area immediately (severity ≥ 4, user in polygon)
- `SHELTER_IN_PLACE` — Stay home and monitor (severity ≤ 3, user in polygon)
- `REROUTE` — Avoid polygon via alternate route (active nav through polygon)
- `AVOID_AREA` — Don't travel toward event (within 2km, severity ≥ 3)
- `CHECK_ON_FAMILY` — Call emergency contact in affected area
- `CONTACT_HELPLINE` — Dial helpline for guidance (optional verb)
- `SEEK_COOLING` / `SEEK_MEDICAL` — For heatwave/health scenarios (future)

### Per-User Decision Tree

```
For each user U near event E:

if U.is_in_event_polygon AND E.severity ≥ 4:
    → EVACUATE (give 3 safe_spots + helpline, urgency=sos)

elif U.is_in_event_polygon AND E.severity ≤ 3:
    → SHELTER_IN_PLACE (give helpline, urgency=med)

elif U.has_active_route_through_polygon:
    → REROUTE (give 3 alternatives avoiding polygon, urgency=med)

elif U.distance_m ≤ 2km AND E.severity ≥ 3:
    → AVOID_AREA (passive notify, urgency=med)

elif U.has_emergency_contacts_in_polygon:
    → CHECK_ON_FAMILY (passive notify, urgency=med)

else:
    → (no action)
```

---

## Routing Rules

- **Women's safe routes:** If `user.women_safe_route=true`, penalize low-class roads
- **Flood rejection:** Any route with `passes_through_flooded=true` is rejected
  - Exception: allowed only if `event.severity ≤ 1`
- **Route sorting:** Priority = (is_safe, lowest_risk_score, shortest_duration)

---

## Message Format

**English:** ≤100 chars, action verb + reason (1 sentence)
Example: `"EVACUATE: Level 4 flooding nearby. Seek shelter immediately. Call 1122."`

**Urdu:** Simple conversational register, not literary
Example: `"فوری نکلیں: سنگین سیلاب ہے۔ محفوظ جگہ تلاش کریں۔"`

---

## Hard Rules

1. **Never recommend driving through standing water above severity 2**
2. **Always include WHY** in the user message (brief explanation)
3. **Helpline lookup mandatory** — never hardcode phone numbers
   - Source: `helplines` Firestore collection (city + crisis_type match)
4. **Safe spots lookup** — find k=3 nearest shelters, hospitals, high ground
   - Source: `safe_spots` collection
5. **Point-in-polygon check** — ray casting algorithm for user location vs event polygon

---

## Tools Allowed

- `firestore_read`: events, users, helplines, safe_spots, safe_contacts
- `firestore_write`: plans, agent_traces
- `google_maps_routes`: 3 alternative routes (mocked for demo)
- `google_maps_places`: k-NN nearest shelters

---

## Tools Forbidden

- `dispatch`, `push_notification` → **Comms Agent (M6) handles those**
- Never write to users collection (read-only)
- Never mutate event docs

---

## Urgency Levels

| Severity | Low Users | Med Users | High Users |
|----------|-----------|-----------|------------|
| 1–2      | `low`     | `low`     | `low`      |
| 3        | —         | `med`     | `med`      |
| 4        | —         | `high`    | `high`     |
| 5        | —         | `sos`     | `sos`      |

---

## Exit Criteria (M4)

- [ ] G-10 scenario produces plan with ≥3 system actions
- [ ] Per-user actions generated for every user within 5km radius
- [ ] REROUTE returns 3 alternatives; none pass through flood polygon
- [ ] Helpline lookup correct for Islamabad + urban_flood (Rescue 1122)
- [ ] Plan written to Firestore in < 4 seconds

---

## File Structure

```
agents/planning/
├── models.py           # Pydantic schemas
├── tools.py            # Firestore + geo utilities
├── agent.py            # Decision tree + planning logic
├── main.py             # FastAPI service
├── requirements.txt    # Dependencies
├── Dockerfile          # Container image
├── test_planning.py    # M4 exit criteria tests
└── GEMINI.md           # This file (agent context)
```
