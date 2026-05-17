"""
Detection Agent — Firestore tools and helper functions.

Reads:
- reports
- signals_weather
- signals_traffic
- signals_social
- flood_prone_locations

Writes:
- events
- agent_traces
"""

from __future__ import annotations

import logging
import math
import os
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from google.cloud import firestore

from models import (
    AgentTrace,
    GeoLocation,
    HistoricalPrior,
    NormalizedSignal,
    ToolCall,
)

logger = logging.getLogger("detection.tools")


PROJECT_ID = os.getenv("PROJECT_ID", "mehfooz-prod")
AGENT_NAME = "detection"

_db: firestore.Client | None = None


def get_db() -> firestore.Client:
    global _db
    if _db is None:
        _db = firestore.Client(project=PROJECT_ID)
    return _db


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def to_aware_utc(value: Any) -> datetime:
    """
    Converts Firestore timestamps, ISO strings, or missing values into aware UTC datetime.
    """

    if value is None:
        return now_utc()

    if isinstance(value, datetime):
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)

    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=timezone.utc)
            return parsed.astimezone(timezone.utc)
        except Exception:
            return now_utc()

    return now_utc()


def get_lat_lon(value: Any) -> Optional[tuple[float, float]]:
    """
    Accepts Firestore GeoPoint, dict, or custom object.
    """

    if value is None:
        return None

    if hasattr(value, "latitude") and hasattr(value, "longitude"):
        return float(value.latitude), float(value.longitude)

    if isinstance(value, dict):
        lat = value.get("latitude", value.get("lat"))
        lon = value.get("longitude", value.get("lon", value.get("lng")))
        if lat is not None and lon is not None:
            return float(lat), float(lon)

    return None


def geo_point(location: GeoLocation) -> firestore.GeoPoint:
    return firestore.GeoPoint(location.latitude, location.longitude)


def geo_point_from_lat_lon(lat: float, lon: float) -> firestore.GeoPoint:
    return firestore.GeoPoint(lat, lon)


def distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Haversine distance in meters.
    """

    radius_m = 6371000.0

    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lon2 - lon1)

    a = (
        math.sin(d_phi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    )

    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    return radius_m * c


def crisis_from_text(text: str) -> str:
    """
    Lightweight fallback crisis inference.
    M2 should already infer crisis_type, but this protects M3.
    """

    t = (text or "").lower()

    flood_words = [
        "flood",
        "rain",
        "rainfall",
        "water",
        "pani",
        "paani",
        "baarish",
        "barish",
        "seelaab",
        "selab",
        "سیلاب",
        "پانی",
        "بارش",
    ]
    traffic_words = ["traffic", "jam", "blocked", "band", "road", "گاڑی", "گاڑیاں"]

    if any(w in t for w in flood_words):
        return "urban_flood"

    if any(w in t for w in traffic_words):
        return "road_incident"

    return "urban_flood"


def useful_weather_signal(data: dict[str, Any]) -> bool:
    rainfall = float(data.get("rainfall_mm_1h") or 0.0)
    return rainfall >= 8.0


def useful_traffic_signal(data: dict[str, Any]) -> bool:
    ratio = float(data.get("congestion_ratio") or 1.0)
    return ratio >= 1.7


def city_matches(doc_city: Any, target_city: Optional[str]) -> bool:
    if not target_city:
        return True
    if not doc_city:
        return True
    return str(doc_city).lower() == target_city.lower()


def safe_doc_to_dict(snapshot) -> dict[str, Any]:
    data = snapshot.to_dict() or {}
    data["_id"] = snapshot.id
    return data


def _recent_query(collection_name: str, timestamp_field: str, minutes: int, limit: int = 500):
    """
    Best effort recent query.
    If Firestore query fails because field/index does not exist,
    fallback to reading limited docs and filtering in Python.
    """

    db = get_db()
    cutoff = now_utc() - timedelta(minutes=minutes)

    try:
        return list(
            db.collection(collection_name)
            .where(timestamp_field, ">=", cutoff)
            .order_by(timestamp_field, direction=firestore.Query.DESCENDING)
            .limit(limit)
            .stream()
        )
    except Exception as e:
        logger.warning(
            "Recent query failed for %s.%s, falling back to limited scan: %s",
            collection_name,
            timestamp_field,
            e,
        )
        return list(db.collection(collection_name).limit(limit).stream())


def read_recent_reports(minutes: int = 60, city: Optional[str] = None) -> list[NormalizedSignal]:
    docs = _recent_query("reports", "created_at", minutes)
    signals: list[NormalizedSignal] = []

    for snap in docs:
        data = safe_doc_to_dict(snap)

        if not city_matches(data.get("city"), city):
            continue

        loc = get_lat_lon(data.get("location"))
        if not loc:
            continue

        lat, lon = loc
        created_at = to_aware_utc(data.get("created_at"))

        # Python fallback filter
        if (now_utc() - created_at).total_seconds() > minutes * 60:
            continue

        text = (
            data.get("text_normalized")
            or data.get("text_raw")
            or data.get("caption")
            or ""
        )

        crisis_type = (
            data.get("crisis_type_inferred")
            or data.get("crisis_type_user")
            or crisis_from_text(text)
        )

        severity = data.get("severity_user") or data.get("severity_inferred")

        try:
            severity = int(severity) if severity is not None else None
        except Exception:
            severity = None

        report_signal = NormalizedSignal(
            signal_id=snap.id,
            source_collection="reports",
            modality="citizen_report",
            lat=lat,
            lon=lon,
            timestamp=created_at,
            city=data.get("city") or city,
            crisis_type=crisis_type,
            severity=severity,
            text=text,
            confidence=0.65,
            raw=data,
        )
        signals.append(report_signal)

        # If vision verified, add a second modality for the same report.
        vision_verified = bool(data.get("vision_verified") or False)
        vision_confidence = float(data.get("vision_confidence") or 0.0)

        if vision_verified and vision_confidence >= 0.5:
            photo_signal = NormalizedSignal(
                signal_id=f"{snap.id}:photo",
                source_collection="reports",
                modality="photo_verified",
                lat=lat,
                lon=lon,
                timestamp=created_at,
                city=data.get("city") or city,
                crisis_type=crisis_type,
                severity=severity,
                text=f"Verified photo evidence for report {snap.id}",
                confidence=vision_confidence,
                raw=data,
            )
            signals.append(photo_signal)

    return signals


def read_recent_weather(minutes: int = 60, city: Optional[str] = None) -> list[NormalizedSignal]:
    docs = _recent_query("signals_weather", "recorded_at", minutes)
    signals: list[NormalizedSignal] = []

    for snap in docs:
        data = safe_doc_to_dict(snap)

        if not city_matches(data.get("city"), city):
            continue

        if not useful_weather_signal(data):
            continue

        loc = get_lat_lon(data.get("location"))
        if not loc:
            continue

        lat, lon = loc
        timestamp = to_aware_utc(data.get("recorded_at") or data.get("fetched_at"))

        if (now_utc() - timestamp).total_seconds() > minutes * 60:
            continue

        rainfall_1h = float(data.get("rainfall_mm_1h") or 0.0)
        rainfall_24h = float(data.get("rainfall_mm_24h") or 0.0)

        signals.append(
            NormalizedSignal(
                signal_id=snap.id,
                source_collection="signals_weather",
                modality="weather",
                lat=lat,
                lon=lon,
                timestamp=timestamp,
                city=data.get("city") or city,
                crisis_type="urban_flood",
                severity=None,
                text=f"{rainfall_1h}mm rainfall in last hour",
                confidence=min(0.9, 0.45 + rainfall_1h / 100),
                rainfall_mm_1h=rainfall_1h,
                rainfall_mm_24h=rainfall_24h,
                raw=data,
            )
        )

    return signals


def read_recent_traffic(minutes: int = 60, city: Optional[str] = None) -> list[NormalizedSignal]:
    docs = _recent_query("signals_traffic", "recorded_at", minutes)
    signals: list[NormalizedSignal] = []

    for snap in docs:
        data = safe_doc_to_dict(snap)

        if not city_matches(data.get("city"), city):
            continue

        if not useful_traffic_signal(data):
            continue

        origin = get_lat_lon(data.get("origin"))
        destination = get_lat_lon(data.get("destination"))

        if not origin and not destination:
            continue

        if origin and destination:
            lat = (origin[0] + destination[0]) / 2
            lon = (origin[1] + destination[1]) / 2
        elif origin:
            lat, lon = origin
        else:
            lat, lon = destination  # type: ignore

        timestamp = to_aware_utc(data.get("recorded_at"))

        if (now_utc() - timestamp).total_seconds() > minutes * 60:
            continue

        ratio = float(data.get("congestion_ratio") or 1.0)

        signals.append(
            NormalizedSignal(
                signal_id=snap.id,
                source_collection="signals_traffic",
                modality="traffic",
                lat=lat,
                lon=lon,
                timestamp=timestamp,
                city=data.get("city") or city,
                crisis_type="urban_flood" if ratio >= 2.0 else "road_incident",
                severity=None,
                text=f"Traffic congestion ratio {ratio:.1f}",
                confidence=min(0.9, 0.35 + ratio / 10),
                congestion_ratio=ratio,
                raw=data,
            )
        )

    return signals


def read_recent_social(minutes: int = 60, city: Optional[str] = None) -> list[NormalizedSignal]:
    docs = _recent_query("signals_social", "posted_at", minutes)
    signals: list[NormalizedSignal] = []

    for snap in docs:
        data = safe_doc_to_dict(snap)

        if not city_matches(data.get("city"), city):
            continue

        loc = get_lat_lon(data.get("location_inferred"))
        if not loc:
            continue

        lat, lon = loc
        timestamp = to_aware_utc(data.get("posted_at"))

        if (now_utc() - timestamp).total_seconds() > minutes * 60:
            continue

        text = data.get("text") or ""
        crisis_type = data.get("crisis_type_inferred") or crisis_from_text(text)

        signals.append(
            NormalizedSignal(
                signal_id=snap.id,
                source_collection="signals_social",
                modality="social",
                lat=lat,
                lon=lon,
                timestamp=timestamp,
                city=data.get("city") or city,
                crisis_type=crisis_type,
                severity=None,
                text=text,
                confidence=0.55,
                raw=data,
            )
        )

    return signals


def read_recent_signals(minutes: int = 60, city: Optional[str] = None) -> list[NormalizedSignal]:
    signals: list[NormalizedSignal] = []
    signals.extend(read_recent_reports(minutes=minutes, city=city))
    signals.extend(read_recent_weather(minutes=minutes, city=city))
    signals.extend(read_recent_traffic(minutes=minutes, city=city))
    signals.extend(read_recent_social(minutes=minutes, city=city))
    return signals


def fetch_historical_prior(
    location: GeoLocation,
    crisis_type: str,
    max_distance_m: float = 2000.0,
) -> HistoricalPrior:
    """
    Checks flood_prone_locations near the cluster centroid.
    """

    if crisis_type not in {"flood", "urban_flood", "flash_flood"}:
        return HistoricalPrior(is_flood_prone=False)

    db = get_db()

    best: tuple[float, str, dict[str, Any]] | None = None

    try:
        docs = list(db.collection("flood_prone_locations").limit(500).stream())
    except Exception as e:
        logger.warning("Could not read flood_prone_locations: %s", e)
        return HistoricalPrior(is_flood_prone=False)

    for snap in docs:
        data = safe_doc_to_dict(snap)
        loc = get_lat_lon(data.get("location"))
        if not loc:
            continue

        d = distance_m(
            location.latitude,
            location.longitude,
            loc[0],
            loc[1],
        )

        if d <= max_distance_m:
            if best is None or d < best[0]:
                best = (d, snap.id, data)

    if not best:
        return HistoricalPrior(is_flood_prone=False)

    d, location_id, data = best

    return HistoricalPrior(
        is_flood_prone=True,
        matched_location_id=location_id,
        matched_location_name=data.get("name"),
        threshold_mm_h=data.get("rainfall_threshold_mm_h"),
        distance_m=d,
    )


def write_event(event: dict[str, Any]) -> str:
    db = get_db()

    event_id = event.get("event_id") or f"evt-{uuid.uuid4().hex[:12]}"
    event["event_id"] = event_id

    # Convert Pydantic GeoLocation objects or dicts to Firestore GeoPoint.
    centroid = event.get("centroid")
    if isinstance(centroid, GeoLocation):
        event["centroid"] = geo_point(centroid)
    elif isinstance(centroid, dict):
        event["centroid"] = geo_point_from_lat_lon(
            float(centroid["latitude"]),
            float(centroid["longitude"]),
        )

    polygon = []
    for point in event.get("polygon", []):
        if isinstance(point, GeoLocation):
            polygon.append(geo_point(point))
        elif isinstance(point, dict):
            polygon.append(
                geo_point_from_lat_lon(
                    float(point["latitude"]),
                    float(point["longitude"]),
                )
            )
        else:
            polygon.append(point)

    event["polygon"] = polygon

    db.collection("events").document(event_id).set(event, merge=True)

    return event_id


def update_reports_with_event(report_ids: list[str], event_id: str) -> int:
    db = get_db()
    updated = 0

    for report_id in report_ids:
        clean_id = report_id.replace(":photo", "")
        try:
            db.collection("reports").document(clean_id).set(
                {"linked_event_id": event_id},
                merge=True,
            )
            updated += 1
        except Exception as e:
            logger.warning("Could not link report %s to event %s: %s", report_id, event_id, e)

    return updated


def write_trace(trace: AgentTrace) -> str:
    db = get_db()

    trace_id = trace.trace_id or f"trace-{uuid.uuid4().hex[:12]}"

    payload = trace.model_dump(mode="json")
    payload["trace_id"] = trace_id
    payload["created_at"] = trace.created_at or now_utc()

    db.collection("agent_traces").document(trace_id).set(payload)

    return trace_id


def make_tool_call(name: str, args: dict[str, Any], result: Any, started_at: float) -> ToolCall:
    return ToolCall(
        name=name,
        args=args,
        result=result,
        duration_ms=int((time.monotonic() - started_at) * 1000),
    )