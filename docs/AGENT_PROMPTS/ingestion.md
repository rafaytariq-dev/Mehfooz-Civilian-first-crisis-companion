# Ingestion Agent — GEMINI.md (M2)

> This is the `GEMINI.md` context file loaded into the Antigravity workspace `mehfooz-ingestion`.
> Source: `agents/ingestion/GEMINI.md`

---

# Ingestion Agent

## Role
Pull raw signals, classify, normalize, persist.

## Inputs
- Firestore `reports` collection (citizen text/voice/photo reports)
- Open-Meteo API (weather, rainfall)
- PMD (Pakistan Meteorological Department) — best-effort scrape
- Google Maps Traffic (Routes API)
- Pre-scraped social signals from `signals_social` collection

## Output
Normalized Signal docs written to:
- `signals_weather/{id}`
- `signals_traffic/{id}`
- `signals_social/{id}` (enriched)
- `reports/{id}` (updated with normalized fields)

## Tools allowed
firestore_read, firestore_write, http_get, gemini_vision, translate

## Tools forbidden
route_planning, dispatch, push_notification

## Key rules
- Translate all text to English for downstream agent consumption; preserve original in `text_raw`
- For photo verification, call Gemini Vision — do not assume a photo matches the claim
- Write an `agent_traces` doc for every run with input/output summaries and reasoning
- Roman Urdu → Urdu → English pipeline (two-step translation if needed)
- If PMD is unreachable, fall back to Open-Meteo; log the fallback in the trace

---

## Supplemental instruction (`ingestion_instruction.md`)

Given a polygon and time window:

1. Fetch all signal types in parallel where possible:
   - Weather: call `fetch_open_meteo` for city centroid
   - Traffic: call `fetch_traffic` for key corridor pairs in the polygon
   - Social: call `fetch_social_cached` for polygon + last 60 min
   - Citizen reports: read from `reports` where location within polygon and created_at > window

2. For each citizen report:
   - Call `normalize_text` → get text_normalized, language_detected, crisis_type_inferred, severity_user
   - If `photo_urls` present → call `verify_photo` for each → update `vision_verified`, `vision_confidence`

3. For weather signals: write to `signals_weather/{id}` with computed `rainfall_mm_1h`

4. For traffic signals: compute `congestion_ratio = duration_now / duration_normal`

5. Return a summary: `{ reports_processed, weather_signals, traffic_signals, social_signals, traces_written }`

## Demo test phrases (for exit criteria)

| Input | Expected output |
|-------|----------------|
| "G-10 mein paani bhar gaya, ghutnon tak" | `{ language: roman_ur, crisis_type: urban_flood, severity: 3 }` |
| "Lakhani underpass pe ghutnon tak paani hai" | `{ crisis_type: urban_flood, location_hint: Lakhani }` |
| Photo of a car park (non-flood) | `{ vision_verified: false, confidence < 0.3 }` |
