"""
Ingestion Agent — Core orchestration logic.

Handles two trigger modes:
  1. PUSH — process a single new citizen report (text/voice/photo)
  2. PULL — poll weather + traffic for all cities on a schedule

Each run writes an agent trace for transparency.
"""
from __future__ import annotations

import logging
import time
import uuid
from datetime import datetime, timezone

from config import CITIES, TRAFFIC_ROUTES
from models import (
    AgentTrace,
    GeoLocation,
    IngestReportRequest,
    IngestionResult,
    PollRequest,
    ToolCall,
)
from tools import (
    fetch_open_meteo,
    fetch_pmd_overlay,
    fetch_social_cached,
    fetch_traffic,
    normalize_text,
    update_report,
    verify_photo,
    write_signal,
    write_trace,
)

logger = logging.getLogger("ingestion.agent")


# ═══════════════════════════════════════════════════════════════
# MODE 1: Process a single citizen report
# ═══════════════════════════════════════════════════════════════

async def process_report(req: IngestReportRequest) -> IngestionResult:
    """Process a new citizen report: normalize text, verify photos,
    update the report doc, and write a trace.

    Triggered by Firestore onCreate(reports/{id}) via Cloud Function.
    """
    t0 = time.monotonic()
    result = IngestionResult()
    tool_calls: list[ToolCall] = []

    logger.info(f"[process_report] Starting for report={req.report_id}")

    # ── Step 1: Normalize text ──
    normalized = {}
    if req.text_raw:
        tc_start = time.monotonic()
        normalized = await normalize_text(req.text_raw)
        tc_dur = int((time.monotonic() - tc_start) * 1000)
        tool_calls.append(ToolCall(
            name="normalize_text",
            args={"raw": req.text_raw[:100]},
            result=normalized,
            duration_ms=tc_dur,
        ))

    # ── Step 2: Verify photos ──
    photo_results = []
    claimed_type = (
        normalized.get("crisis_type_inferred")
        or req.crisis_type_user
        or "flood"
    )

    for photo_url in req.photo_urls:
        tc_start = time.monotonic()
        verification = await verify_photo(photo_url, claimed_type)
        tc_dur = int((time.monotonic() - tc_start) * 1000)
        photo_results.append(verification)
        tool_calls.append(ToolCall(
            name="verify_photo",
            args={"photo_url": photo_url[:80], "claimed_type": claimed_type},
            result=verification,
            duration_ms=tc_dur,
        ))

    # ── Step 3: Compute aggregate verification ──
    vision_verified = False
    vision_confidence = 0.0
    if photo_results:
        # Best photo determines verification status
        best = max(photo_results, key=lambda v: v.get("confidence", 0))
        vision_verified = best.get("is_match", False)
        vision_confidence = best.get("confidence", 0.0)

    # ── Step 4: Update the report document in Firestore ──
    updates = {}
    if normalized:
        updates["text_normalized"] = normalized.get("text_normalized", req.text_raw)
        updates["language_detected"] = normalized.get("language_detected", "unknown")
        if normalized.get("crisis_type_inferred"):
            updates["crisis_type_inferred"] = normalized["crisis_type_inferred"]
        if normalized.get("severity_inferred"):
            # Only override if user didn't set severity
            if not req.severity_user:
                updates["severity_user"] = normalized["severity_inferred"]

    if photo_results:
        updates["vision_verified"] = vision_verified
        updates["vision_confidence"] = vision_confidence

    if updates:
        tc_start = time.monotonic()
        await update_report(req.report_id, updates)
        tc_dur = int((time.monotonic() - tc_start) * 1000)
        tool_calls.append(ToolCall(
            name="update_report",
            args={"report_id": req.report_id, "fields": list(updates.keys())},
            result={"updated": True},
            duration_ms=tc_dur,
        ))

    result.reports_processed = 1

    # ── Step 5: Write agent trace ──
    total_dur = int((time.monotonic() - t0) * 1000)

    trace = AgentTrace(
        trace_id=f"trace-ing-rpt-{uuid.uuid4().hex[:8]}",
        agent="ingestion",
        step="process_report",
        input_summary=(
            f"Report {req.report_id} from user {req.user_id}: "
            f"'{req.text_raw[:80]}…' with {len(req.photo_urls)} photo(s)"
        ),
        output_summary=(
            f"Normalized: lang={normalized.get('language_detected', '?')}, "
            f"type={normalized.get('crisis_type_inferred', '?')}, "
            f"sev={normalized.get('severity_inferred', '?')}. "
            f"Photos: verified={vision_verified} (conf={vision_confidence:.2f})"
        ),
        reasoning=(
            f"Text was detected as {normalized.get('language_detected', 'unknown')} "
            f"and normalized to English. "
            f"Crisis type inferred as {normalized.get('crisis_type_inferred', 'unknown')} "
            f"with severity {normalized.get('severity_inferred', 'unknown')}. "
            + (
                f"Photo verification {'confirmed' if vision_verified else 'did not confirm'} "
                f"the claimed crisis type '{claimed_type}' "
                f"with confidence {vision_confidence:.2f}."
                if photo_results
                else "No photos to verify."
            )
        ),
        tools_called=tool_calls,
        duration_ms=total_dur,
    )
    await write_trace(trace)
    result.traces_written = 1

    logger.info(
        f"[process_report] Done: report={req.report_id}, "
        f"lang={normalized.get('language_detected')}, "
        f"type={normalized.get('crisis_type_inferred')}, "
        f"duration={total_dur}ms"
    )
    return result


# ═══════════════════════════════════════════════════════════════
# MODE 2: Scheduled poll for weather + traffic
# ═══════════════════════════════════════════════════════════════

async def poll_signals(req: PollRequest) -> IngestionResult:
    """Poll weather and traffic for all requested cities.

    Triggered by Cloud Scheduler every 2 minutes.
    """
    t0 = time.monotonic()
    result = IngestionResult()
    tool_calls: list[ToolCall] = []

    logger.info(f"[poll_signals] Starting for cities={req.cities}")

    now = datetime.now(timezone.utc)

    # ── Weather for each city ──
    for city_name in req.cities:
        city = CITIES.get(city_name)
        if not city:
            logger.warning(f"[poll_signals] Unknown city: {city_name}")
            continue

        # Fetch from Open-Meteo
        tc_start = time.monotonic()
        weather = await fetch_open_meteo(city["lat"], city["lon"])
        tc_dur = int((time.monotonic() - tc_start) * 1000)
        tool_calls.append(ToolCall(
            name="fetch_open_meteo",
            args={"city": city_name, "lat": city["lat"], "lon": city["lon"]},
            result=weather,
            duration_ms=tc_dur,
        ))

        # Try PMD overlay
        tc_start = time.monotonic()
        pmd = await fetch_pmd_overlay(city_name)
        tc_dur = int((time.monotonic() - tc_start) * 1000)
        tool_calls.append(ToolCall(
            name="fetch_pmd_overlay",
            args={"city": city_name},
            result={"available": pmd is not None},
            duration_ms=tc_dur,
        ))

        # Merge PMD data if available
        source = "open_meteo"
        if pmd:
            source = "pmd+open_meteo"
            # PMD data can override/supplement Open-Meteo values
            # For now, just note the source

        # Write weather signal
        signal_id = f"wx-{city_name.lower()}-{now.strftime('%Y%m%d%H%M')}"
        weather_doc = {
            "signal_id": signal_id,
            "source": source,
            "location": {"latitude": city["lat"], "longitude": city["lon"]},
            "city": city_name,
            "rainfall_mm_1h": weather.get("rainfall_mm_1h", 0),
            "rainfall_mm_24h": weather.get("rainfall_mm_24h", 0),
            "temp_c": weather.get("temp_c", 0),
            "humidity": weather.get("humidity", 0),
            "wind_kph": weather.get("wind_kph", 0),
            "recorded_at": now,
            "fetched_at": now,
        }

        tc_start = time.monotonic()
        await write_signal("signals_weather", weather_doc, doc_id=signal_id)
        tc_dur = int((time.monotonic() - tc_start) * 1000)
        tool_calls.append(ToolCall(
            name="write_signal",
            args={"collection": "signals_weather", "signal_id": signal_id},
            result={"written": True},
            duration_ms=tc_dur,
        ))
        result.weather_signals += 1

    # ── Traffic for key routes ──
    for city_name in req.cities:
        routes = TRAFFIC_ROUTES.get(city_name, [])
        for route_config in routes:
            tc_start = time.monotonic()
            traffic = await fetch_traffic(
                origin=route_config["origin"],
                destination=route_config["destination"],
                route_name=route_config["name"],
            )
            tc_dur = int((time.monotonic() - tc_start) * 1000)
            tool_calls.append(ToolCall(
                name="fetch_traffic",
                args={"route": route_config["name"], "city": city_name},
                result=traffic,
                duration_ms=tc_dur,
            ))

            signal_id = (
                f"trf-{city_name.lower()}-"
                f"{route_config['name'][:20].replace(' ', '_').lower()}-"
                f"{now.strftime('%Y%m%d%H%M')}"
            )
            traffic_doc = {
                "signal_id": signal_id,
                "source": traffic.get("source", "google_maps"),
                "origin": {
                    "latitude": route_config["origin"]["lat"],
                    "longitude": route_config["origin"]["lon"],
                },
                "destination": {
                    "latitude": route_config["destination"]["lat"],
                    "longitude": route_config["destination"]["lon"],
                },
                "duration_normal_s": traffic.get("duration_normal_s", 0),
                "duration_now_s": traffic.get("duration_now_s", 0),
                "congestion_ratio": traffic.get("congestion_ratio", 1.0),
                "recorded_at": now,
            }

            tc_start = time.monotonic()
            await write_signal("signals_traffic", traffic_doc, doc_id=signal_id)
            tc_dur = int((time.monotonic() - tc_start) * 1000)
            tool_calls.append(ToolCall(
                name="write_signal",
                args={"collection": "signals_traffic", "signal_id": signal_id},
                result={"written": True},
                duration_ms=tc_dur,
            ))
            result.traffic_signals += 1

    # ── Write trace ──
    total_dur = int((time.monotonic() - t0) * 1000)

    trace = AgentTrace(
        trace_id=f"trace-ing-poll-{uuid.uuid4().hex[:8]}",
        agent="ingestion",
        step="poll_signals",
        input_summary=f"Scheduled poll for cities: {', '.join(req.cities)}",
        output_summary=(
            f"Weather: {result.weather_signals} signals. "
            f"Traffic: {result.traffic_signals} signals. "
            f"Duration: {total_dur}ms."
        ),
        reasoning=(
            f"Polled Open-Meteo weather for {len(req.cities)} cities and "
            f"Google Maps traffic for {result.traffic_signals} routes. "
            f"PMD overlay was attempted for each city as supplementary data."
        ),
        tools_called=tool_calls,
        duration_ms=total_dur,
    )
    await write_trace(trace)
    result.traces_written = 1

    logger.info(
        f"[poll_signals] Done: weather={result.weather_signals}, "
        f"traffic={result.traffic_signals}, duration={total_dur}ms"
    )
    return result


# ═══════════════════════════════════════════════════════════════
# MODE 3: Enrich social signals (on-demand)
# ═══════════════════════════════════════════════════════════════

async def enrich_social(city: str | None = None) -> IngestionResult:
    """Read cached social signals and enrich them with NLP.

    For the demo, social signals are pre-seeded.  This function
    normalizes any that haven't been processed yet.
    """
    t0 = time.monotonic()
    result = IngestionResult()
    tool_calls: list[ToolCall] = []

    signals = await fetch_social_cached(city=city)

    for signal in signals:
        text = signal.get("text", "")
        # Skip if already has language detected (already enriched)
        if signal.get("_enriched"):
            continue

        tc_start = time.monotonic()
        normalized = await normalize_text(text)
        tc_dur = int((time.monotonic() - tc_start) * 1000)
        tool_calls.append(ToolCall(
            name="normalize_text",
            args={"text": text[:60]},
            result=normalized,
            duration_ms=tc_dur,
        ))

        # Update the social signal with enrichment
        enrichment = {
            "language": normalized.get("language_detected", signal.get("language", "")),
            "crisis_type_inferred": normalized.get("crisis_type_inferred"),
            "severity_inferred": normalized.get("severity_inferred"),
            "text_normalized": normalized.get("text_normalized", ""),
            "_enriched": True,
        }

        signal_id = signal.get("signal_id", signal.get("id", ""))
        if signal_id:
            tc_start = time.monotonic()
            await write_signal("signals_social", enrichment, doc_id=signal_id)
            tc_dur = int((time.monotonic() - tc_start) * 1000)
            tool_calls.append(ToolCall(
                name="write_signal",
                args={"collection": "signals_social", "signal_id": signal_id},
                result={"enriched": True},
                duration_ms=tc_dur,
            ))
            result.social_signals_enriched += 1

    total_dur = int((time.monotonic() - t0) * 1000)

    trace = AgentTrace(
        trace_id=f"trace-ing-social-{uuid.uuid4().hex[:8]}",
        agent="ingestion",
        step="enrich_social",
        input_summary=f"Enrich {len(signals)} social signals for city={city or 'all'}",
        output_summary=f"Enriched {result.social_signals_enriched} signals in {total_dur}ms",
        reasoning=(
            f"Processed {len(signals)} cached social signals. "
            f"Each was normalized for language, crisis type, and severity."
        ),
        tools_called=tool_calls,
        duration_ms=total_dur,
    )
    await write_trace(trace)
    result.traces_written = 1

    return result
