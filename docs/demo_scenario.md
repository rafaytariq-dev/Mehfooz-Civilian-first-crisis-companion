# Demo Scenario — G-10/G-11 Islamabad Flash Flood

## Scenario ID
`g10_flash_flood_2025`

## Status
🔒 **LOCKED** — This is the canonical demo scenario for CIRO Pakistan / Mehfooz.

---

## Setting

| Parameter | Value |
|-----------|-------|
| City | Islamabad |
| Sectors | G-10 / G-11 |
| Crisis type | `flash_flood` / `urban_flood` |
| Date (real) | August–September 2025 (heavy monsoon) |
| Demo timeline | T+0 to T+90 minutes |
| Demo severity | 4 — Roads impassable, evacuation advised |

---

## Geographic Bounding Box

```
NW corner: 33.7200°N, 72.9900°E
SE corner: 33.6900°N, 73.0250°E
Centroid:  33.7050°N, 73.0075°E
```

Key landmarks within scope:
- **Faizabad Interchange underpasses** — historically flood-prone, known to fill within 30 min of heavy rain
- **IJP Road (Islamabad–Jhelum Pipeline Road)** — major artery, prone to waterlogging
- **G-10 Markaz** — commercial hub, high foot traffic
- **Nullah Lai tributaries** — drain through G-10/G-11; overflow when rainfall > 25 mm/h

---

## Replay Timeline (T = 00:00)

| T (min) | Event |
|---------|-------|
| 00:00 | Scenario clock starts. Weather signal: 31 mm/h rainfall, 85% humidity |
| 05:00 | First citizen report: "G-10 mein paani bhar gaya, ghutnon tak" (Roman Urdu) |
| 08:00 | Second report: "Faizabad underpass band ho gaya hai" + photo of flooded underpass |
| 12:00 | Traffic anomaly: IJP Road congestion ratio = 3.8× normal |
| 15:00 | Third report: "Main G-11 mein phans gaya, motor band ho gayi" (English + Roman Urdu mix) |
| 18:00 | Detection agent triggers — 3 modalities corroborated (weather + citizen + traffic) |
| 20:00 | Event created: confidence=0.87, severity=4, status=verified |
| 22:00 | Planning agent runs — routes, helplines, safe spots computed |
| 25:00 | Simulation agent executes — PDMA + Rescue 1122 mock dispatches sent |
| 28:00 | Push notifications sent to 47 affected users |
| 30:00 | Fourth report: "Ambulance bhi phans gayi" — severity upgraded to 5 |
| 40:00 | Rainfall begins to ease (weather signal update) |
| 70:00 | New traffic signals show IJP Road clearing |
| 80:00 | Detection agent downgrades severity to 3 |
| 90:00 | Event resolved — all-clear notifications sent |

---

## Simulated Users in Affected Zone

| User ID | Location | Scenario |
|---------|----------|----------|
| `u_001` | G-10/4, near underpass | In flood polygon — EVACUATE |
| `u_002` | G-11/1, driving on IJP Rd | Active route through flood — REROUTE |
| `u_003` | G-10 Markaz | Near zone, severity ≥ 3 — AVOID_AREA |
| `u_004` | F-10 (2 km away) | Emergency contact (u_001) in zone — CHECK_ON_FAMILY |
| `u_005` | G-10/2 | In polygon, severity 4 — EVACUATE to Shifa International |

---

## Safe Spots (Demo)

| Name | Type | Distance from centroid |
|------|------|----------------------|
| Shifa International Hospital | hospital | 1.4 km N |
| Pakistan Institute of Medical Sciences (PIMS) | hospital | 3.2 km E |
| Centaurus Mall | mall | 2.8 km NE |
| Faisal Mosque | mosque | 3.5 km N |
| Federal Government Polytechnic Institute | school | 0.9 km W |

---

## Helplines (Islamabad + Urban Flood)

| Name | Number | Notes |
|------|--------|-------|
| Rescue 1122 ICT | 1122 | Primary water rescue, Islamabad Capital Territory |
| CARES 1122 | 1122 | Backup, ICT emergency |
| NDMA Helpline | 1700 | National Disaster Management Authority |
| CDA Emergency | 051-9252717 | Capital Development Authority road closures |
| Edhi Foundation | 115 | Ambulance + rescue |

---

## Expected Agent Outputs

### Detection Agent
```json
{
  "event_id": "evt_g10_20250901_001",
  "type": "urban_flood",
  "severity": 4,
  "confidence": 0.87,
  "status": "verified",
  "explanation_en": "8 reports + 31 mm/h rain in 18 min + IJP Road traffic 3.8× normal at Faizabad = Severe urban flood.",
  "explanation_ur": "18 منٹ میں 8 رپورٹس + 31 ملی میٹر بارش + فیض آباد پر ٹریفک جام = شدید سیلاب۔"
}
```

### Simulation Report (Demo Card)
```
47 users alerted, 3 routes flagged, 2 tickets dispatched (PDMA + Rescue 1122),
est. 22 min congestion reduction. [Estimates — not real data]
```

---

## Seed Data Filenames

| Dataset | File |
|---------|------|
| Citizen reports (20 simulated) | `data/seed/reports_g10.json` |
| Weather replay (Open-Meteo) | `data/seed/weather_islamabad_2025.json` |
| Social signals (anonymized tweets) | `data/seed/tweets_g10.json` |
| Replay script | `data/replay_scenario.py` |

---

## Replay Script Usage

```bash
# Stream the G-10 scenario into Firestore (emulator or prod)
python data/replay_scenario.py g10

# Options
python data/replay_scenario.py g10 --speed 10   # 10× speed (1 min of scenario = 6 sec real)
python data/replay_scenario.py g10 --emulator    # target local Firebase emulator
python data/replay_scenario.py g10 --dry-run     # print events without writing
```

---

## Notes for Demo Presenters

1. Start with `python data/replay_scenario.py g10 --speed 10` — 90 min of scenario in 9 min.
2. Show the mobile app receiving the push notification in real-time.
3. Point to the Authority Dashboard (M15) — the PDMA and Rescue 1122 mock tickets appear within 2 sec of dispatch.
4. Highlight the Urdu explanation in the notification — simple register, not literary.
5. Walk through the agent trace in Antigravity to show reasoning transparency.
6. **Always label simulation estimates** as estimates — judges respect honesty.
