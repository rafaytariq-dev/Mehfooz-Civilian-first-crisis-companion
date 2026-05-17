"""
Ingestion Agent — Tool implementations.

Each function is a self-contained tool that the agent (or orchestrator)
can call.  They handle external API calls, Gemini reasoning, and
Firestore persistence.
"""
from __future__ import annotations

import json
import logging
import os
import time
import uuid
from datetime import datetime, timezone
from typing import Any, Optional

import httpx
from google import genai
from google.cloud import firestore

from config import (
    CITIES,
    CRISIS_TYPES,
    GEMINI_FLASH,
    GEMINI_PRO,
    MAPS_API_KEY,
    OPEN_METEO_URL,
    PMD_BASE_URL,
    PROJECT_ID,
    ROUTES_API_URL,
    TRAFFIC_ROUTES,
)
from models import (
    AgentTrace,
    GeoLocation,
    NormalizedReport,
    PhotoVerification,
    ToolCall,
    TrafficSignal,
    WeatherSignal,
)

logger = logging.getLogger("ingestion.tools")

# ─── Lazy singletons ───

_db: firestore.Client | None = None
_genai_client: genai.Client | None = None
_http: httpx.AsyncClient | None = None


def get_db() -> firestore.Client:
    global _db
    if _db is None:
        _db = firestore.Client(project=PROJECT_ID)
    return _db


def get_genai() -> genai.Client:
    global _genai_client
    if _genai_client is None:
        api_key = os.environ.get("GOOGLE_API_KEY", "")
        if api_key:
            # Local dev: use AI Studio API key (no gcloud needed)
            _genai_client = genai.Client(api_key=api_key)
            logger.info("[genai] Using API key auth (AI Studio)")
        else:
            # Cloud Run: use Vertex AI with service account
            _genai_client = genai.Client(
                vertexai=True,
                project=PROJECT_ID,
                location="us-central1",
            )
            logger.info("[genai] Using Vertex AI auth")
    return _genai_client


async def get_http() -> httpx.AsyncClient:
    global _http
    if _http is None:
        _http = httpx.AsyncClient(timeout=30.0)
    return _http


# ═══════════════════════════════════════════════════════════════
# TOOL 1: fetch_open_meteo
# ═══════════════════════════════════════════════════════════════

async def fetch_open_meteo(lat: float, lon: float) -> dict:
    """Pull current weather + 1h/24h rainfall for a lat/lon from Open-Meteo.

    Free API, no key required.  Returns a dict matching the
    signals_weather schema.
    """
    t0 = time.monotonic()
    client = await get_http()

    params = {
        "latitude": lat,
        "longitude": lon,
        "current": "temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m",
        "hourly": "precipitation",
        "timezone": "Asia/Karachi",
        "forecast_days": 1,
        "past_days": 1,
    }

    try:
        resp = await client.get(OPEN_METEO_URL, params=params)
        resp.raise_for_status()
        data = resp.json()

        current = data.get("current", {})
        hourly_precip = data.get("hourly", {}).get("precipitation", [])

        # Sum last 24 entries for 24h rainfall (hourly data)
        rainfall_24h = sum(hourly_precip[-24:]) if len(hourly_precip) >= 24 else sum(hourly_precip)
        # Last entry is approximately 1h rainfall
        rainfall_1h = hourly_precip[-1] if hourly_precip else 0.0

        result = {
            "source": "open_meteo",
            "rainfall_mm_1h": round(rainfall_1h, 1),
            "rainfall_mm_24h": round(rainfall_24h, 1),
            "temp_c": current.get("temperature_2m", 0.0),
            "humidity": current.get("relative_humidity_2m", 0),
            "wind_kph": current.get("wind_speed_10m", 0.0),
        }

        logger.info(f"[open_meteo] lat={lat}, lon={lon} → rain_1h={result['rainfall_mm_1h']}mm")
        return result

    except Exception as e:
        logger.error(f"[open_meteo] Failed for ({lat}, {lon}): {e}")
        return {
            "source": "open_meteo",
            "rainfall_mm_1h": 0.0,
            "rainfall_mm_24h": 0.0,
            "temp_c": 0.0,
            "humidity": 0,
            "wind_kph": 0.0,
            "error": str(e),
        }


# ═══════════════════════════════════════════════════════════════
# TOOL 2: fetch_pmd_overlay
# ═══════════════════════════════════════════════════════════════

async def fetch_pmd_overlay(city: str) -> dict | None:
    """Best-effort scrape of PMD data.  Falls back to None on failure.

    PMD doesn't have a reliable public API, so this is a best-effort
    enrichment layer on top of Open-Meteo.
    """
    client = await get_http()

    try:
        # Attempt to hit a known PMD JSON-like endpoint
        resp = await client.get(
            f"{PMD_BASE_URL}/new/assets/forecast-data.json",
            timeout=10.0,
        )
        if resp.status_code == 200:
            data = resp.json()
            # Try to find city-specific data
            for entry in data if isinstance(data, list) else []:
                if city.lower() in str(entry).lower():
                    logger.info(f"[pmd] Got data for {city}")
                    return {"source": "pmd", "raw": entry}

        logger.info(f"[pmd] No data found for {city}, falling back to Open-Meteo only")
        return None

    except Exception as e:
        logger.warning(f"[pmd] Unreachable for {city}: {e} — falling back to Open-Meteo")
        return None


# ═══════════════════════════════════════════════════════════════
# TOOL 3: fetch_traffic
# ═══════════════════════════════════════════════════════════════

async def fetch_traffic(
    origin: dict[str, float],
    destination: dict[str, float],
    route_name: str = "",
) -> dict:
    """Google Maps Routes API — compare normal vs. live duration.

    Returns a dict matching the signals_traffic schema.
    If no API key is configured, returns a placeholder.
    """
    if not MAPS_API_KEY:
        logger.warning("[traffic] No GOOGLE_MAPS_API_KEY set — returning mock data")
        return {
            "source": "google_maps",
            "route_name": route_name,
            "duration_normal_s": 0,
            "duration_now_s": 0,
            "congestion_ratio": 1.0,
            "note": "No API key configured — mock data",
        }

    client = await get_http()

    body = {
        "origin": {
            "location": {
                "latLng": {"latitude": origin["lat"], "longitude": origin["lon"]}
            }
        },
        "destination": {
            "location": {
                "latLng": {"latitude": destination["lat"], "longitude": destination["lon"]}
            }
        },
        "travelMode": "DRIVE",
        "routingPreference": "TRAFFIC_AWARE",
        "computeAlternativeRoutes": False,
    }

    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": MAPS_API_KEY,
        "X-Goog-FieldMask": "routes.duration,routes.staticDuration",
    }

    try:
        resp = await client.post(ROUTES_API_URL, json=body, headers=headers)
        resp.raise_for_status()
        data = resp.json()

        route = data.get("routes", [{}])[0]
        # Parse durations (format: "1234s")
        static_dur = int(route.get("staticDuration", "0s").rstrip("s"))
        live_dur = int(route.get("duration", "0s").rstrip("s"))

        congestion = round(live_dur / static_dur, 2) if static_dur > 0 else 1.0

        result = {
            "source": "google_maps",
            "route_name": route_name,
            "duration_normal_s": static_dur,
            "duration_now_s": live_dur,
            "congestion_ratio": congestion,
        }

        logger.info(f"[traffic] {route_name}: {congestion}× congestion")
        return result

    except Exception as e:
        logger.error(f"[traffic] Failed for {route_name}: {e}")
        return {
            "source": "google_maps",
            "route_name": route_name,
            "duration_normal_s": 0,
            "duration_now_s": 0,
            "congestion_ratio": 1.0,
            "error": str(e),
        }


# ═══════════════════════════════════════════════════════════════
# TOOL 4: verify_photo
# ═══════════════════════════════════════════════════════════════

async def verify_photo(photo_url: str, claimed_type: str) -> dict:
    """Gemini Vision: does this photo show {claimed_type}?

    Returns {is_match: bool, confidence: float, description: str}.
    Uses Gemini 2.5 Pro for higher accuracy on visual verification.
    """
    t0 = time.monotonic()

    try:
        client = get_genai()

        prompt = f"""You are a crisis photo verification system for Pakistan.
Analyze this image and determine if it shows evidence of: {claimed_type}

Respond ONLY in this JSON format:
{{
  "is_match": true/false,
  "confidence": 0.0-1.0,
  "description": "brief description of what the image actually shows (max 30 words)"
}}

Be strict: only set is_match=true if the image clearly shows the claimed crisis type.
A photo of a sunny day should NOT match "flood" (confidence < 0.2).
A photo of standing water on a road SHOULD match "flood" (confidence > 0.7)."""

        # For demo/seeded data, handle gs:// URLs gracefully
        if photo_url.startswith("gs://"):
            # In production, fetch from Cloud Storage
            # For demo, return a plausible verification
            logger.info(f"[verify_photo] gs:// URL detected, using demo verification for {claimed_type}")
            return {
                "is_match": True,
                "confidence": 0.85,
                "description": f"Demo image verification for {claimed_type}",
            }

        # Build multimodal content
        response = client.models.generate_content(
            model=GEMINI_PRO,
            contents=[
                {"text": prompt},
                {"file_uri": photo_url, "mime_type": "image/jpeg"},
            ],
        )

        # Parse JSON from response
        text = response.text.strip()
        # Strip markdown code fences if present
        if text.startswith("```"):
            text = text.split("\n", 1)[1].rsplit("```", 1)[0].strip()

        result = json.loads(text)
        dur = int((time.monotonic() - t0) * 1000)
        logger.info(
            f"[verify_photo] {photo_url[:60]}… → match={result['is_match']}, "
            f"conf={result['confidence']:.2f} ({dur}ms)"
        )
        return result

    except Exception as e:
        logger.error(f"[verify_photo] Failed for {photo_url}: {e}")
        return {
            "is_match": False,
            "confidence": 0.0,
            "description": f"Verification failed: {e}",
        }


# ═══════════════════════════════════════════════════════════════
# TOOL 5: normalize_text
# ═══════════════════════════════════════════════════════════════

async def normalize_text(raw: str) -> dict:
    """Detect language, translate Roman Urdu / Urdu / code-mixed to English.
    Extract crisis_type, severity, and location hints.

    Uses Gemini Flash for speed on high-volume normalization.
    """
    if not raw or not raw.strip():
        return {
            "text_normalized": "",
            "language_detected": "unknown",
            "crisis_type_inferred": None,
            "severity_inferred": None,
            "location_hints": [],
        }

    t0 = time.monotonic()

    try:
        client = get_genai()

        prompt = f"""You are a Pakistani crisis report normalizer. Analyze this citizen report text.

INPUT TEXT: "{raw}"

Tasks:
1. Detect the language: "ur" (Urdu script), "roman_ur" (Romanized Urdu), "en" (English), or "mixed" (code-mixed)
2. Translate to clear, natural English (preserve meaning, don't add info)
3. Infer the crisis type from: {', '.join(CRISIS_TYPES)}
4. Infer severity (1-5): 1=minor disruption, 2=localized issue, 3=significant (knee-deep water/vehicles stuck), 4=severe (roads impassable), 5=life-threatening (rescue needed)
5. Extract location hints (sector names, road names, landmarks)

Respond ONLY in this JSON format:
{{
  "text_normalized": "English translation",
  "language_detected": "ur|roman_ur|en|mixed",
  "crisis_type_inferred": "one_of_the_types_or_null",
  "severity_inferred": 1-5_or_null,
  "location_hints": ["G-10", "IJP Road", etc]
}}"""

        response = client.models.generate_content(
            model=GEMINI_FLASH,
            contents=prompt,
        )

        text = response.text.strip()
        if text.startswith("```"):
            text = text.split("\n", 1)[1].rsplit("```", 1)[0].strip()

        result = json.loads(text)
        dur = int((time.monotonic() - t0) * 1000)

        logger.info(
            f"[normalize] lang={result.get('language_detected')}, "
            f"type={result.get('crisis_type_inferred')}, "
            f"sev={result.get('severity_inferred')} ({dur}ms)"
        )
        return result

    except Exception as e:
        logger.error(f"[normalize] Failed for '{raw[:50]}…': {e}")
        # Graceful fallback — don't lose the report
        return {
            "text_normalized": raw,
            "language_detected": "unknown",
            "crisis_type_inferred": None,
            "severity_inferred": None,
            "location_hints": [],
            "error": str(e),
        }


# ═══════════════════════════════════════════════════════════════
# TOOL 6: fetch_social_cached
# ═══════════════════════════════════════════════════════════════

async def fetch_social_cached(
    city: str | None = None,
    minutes_back: int = 60,
) -> list[dict]:
    """Read pre-scraped social signals from Firestore.

    For the demo, social signals are pre-seeded.  In production,
    this would query a live scraping pipeline.
    """
    db = get_db()

    try:
        query = db.collection("signals_social")

        # Firestore doesn't support geospatial natively, so filter by time
        cutoff = datetime.now(timezone.utc)
        # For demo, just return all signals — the seeded data is scoped to G-10
        docs = query.order_by(
            "posted_at", direction=firestore.Query.DESCENDING
        ).limit(50).stream()

        results = []
        for doc in docs:
            d = doc.to_dict()
            d["signal_id"] = doc.id
            results.append(d)

        logger.info(f"[social_cached] Fetched {len(results)} social signals")
        return results

    except Exception as e:
        logger.error(f"[social_cached] Failed: {e}")
        return []


# ═══════════════════════════════════════════════════════════════
# TOOL 7: write_signal
# ═══════════════════════════════════════════════════════════════

async def write_signal(collection: str, doc: dict, doc_id: str | None = None) -> str:
    """Persist a normalized signal to Firestore.  Returns doc_id."""
    db = get_db()

    now = datetime.now(timezone.utc)
    doc["_ingested_at"] = now

    # Convert GeoLocation dicts to Firestore GeoPoints
    doc = _convert_geopoints(doc)

    try:
        if doc_id:
            db.collection(collection).document(doc_id).set(doc, merge=True)
            logger.info(f"[write_signal] {collection}/{doc_id} (merge)")
            return doc_id
        else:
            ref = db.collection(collection).add(doc)
            new_id = ref[1].id
            logger.info(f"[write_signal] {collection}/{new_id} (new)")
            return new_id
    except Exception as e:
        logger.error(f"[write_signal] Failed writing to {collection}: {e}")
        raise


def _convert_geopoints(doc: dict) -> dict:
    """Recursively convert {'latitude': x, 'longitude': y} dicts to GeoPoints."""
    geo_fields = ["location", "origin", "destination", "location_inferred"]
    for field in geo_fields:
        if field in doc and isinstance(doc[field], dict):
            val = doc[field]
            if "latitude" in val and "longitude" in val:
                doc[field] = firestore.GeoPoint(val["latitude"], val["longitude"])
    return doc


# ═══════════════════════════════════════════════════════════════
# TOOL 8: write_trace
# ═══════════════════════════════════════════════════════════════

async def write_trace(trace: AgentTrace) -> str:
    """Write an agent trace document for transparency."""
    db = get_db()

    trace_id = trace.trace_id or f"trace-ing-{uuid.uuid4().hex[:12]}"
    trace.trace_id = trace_id
    trace.created_at = datetime.now(timezone.utc)

    doc = trace.model_dump(exclude_none=True)
    # Convert datetime to Firestore-friendly
    doc["created_at"] = trace.created_at

    db.collection("agent_traces").document(trace_id).set(doc)
    logger.info(f"[write_trace] agent_traces/{trace_id} step={trace.step}")
    return trace_id


# ═══════════════════════════════════════════════════════════════
# TOOL 9: update_report
# ═══════════════════════════════════════════════════════════════

async def update_report(report_id: str, updates: dict) -> None:
    """Update an existing report doc with normalized/verified fields."""
    db = get_db()
    db.collection("reports").document(report_id).update(updates)
    logger.info(f"[update_report] reports/{report_id} updated {list(updates.keys())}")
