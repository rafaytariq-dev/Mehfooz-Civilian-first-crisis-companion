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
