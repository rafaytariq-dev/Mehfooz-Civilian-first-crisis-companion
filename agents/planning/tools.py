"""
Planning Agent — Firestore tools and Google Maps integration.

Reads:
- events (verified status)
- users (location + emergency_contacts)
- helplines
- safe_spots
- routes (cached if needed)

Writes:
- plans
- agent_traces
"""

from __future__ import annotations

import json
import logging
import math
import os
import time
import uuid
from datetime import datetime, timezone
from typing import Any, Optional

from google.cloud import firestore
from google.maps import routing_v2

from models import (
    ActionVerb,
    AgentTrace,
    GeoLocation,
    Helpline,
    Plan,
    Route,
    SafeSpot,
    ToolCall,
    Urgency,
)

logger = logging.getLogger("planning.tools")

PROJECT_ID = os.getenv("PROJECT_ID", "mehfooz-prod")
GOOGLE_MAPS_API_KEY = os.getenv("GOOGLE_MAPS_API_KEY", "")
AGENT_NAME = "planning"

_db: firestore.Client | None = None
_maps_client: routing_v2.RoutesAsyncClient | None = None


def get_db() -> firestore.Client:
    global _db
    if _db is None:
        _db = firestore.Client(project=PROJECT_ID)
    return _db


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def to_aware_utc(value: Any) -> datetime:
    """Convert Firestore timestamp, ISO string, or None to aware UTC datetime."""
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
    """Extract (lat, lon) from Firestore GeoPoint, dict, or custom object."""
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
    """Convert GeoLocation to Firestore GeoPoint."""
    return firestore.GeoPoint(location.latitude, location.longitude)


def geo_point_from_lat_lon(lat: float, lon: float) -> firestore.GeoPoint:
    """Create Firestore GeoPoint from lat/lon."""
    return firestore.GeoPoint(lat, lon)


def distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Haversine distance in meters."""
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


def safe_doc_to_dict(snapshot) -> dict[str, Any]:
    """Convert Firestore document snapshot to dict, preserving ID."""
    data = snapshot.to_dict() or {}
    data["_id"] = snapshot.id
    return data


def make_tool_call(
    name: str,
    func,
    *args,
    **kwargs,
) -> ToolCall:
    """Wrap a tool call with timing and result capture."""
    start = time.time()
    try:
        result = func(*args, **kwargs)
        duration_ms = int((time.time() - start) * 1000)
        return ToolCall(
            name=name,
            args={str(k): str(v)[:100] for k, v in kwargs.items()},
            result=result,
            duration_ms=duration_ms,
        )
    except Exception as e:
        duration_ms = int((time.time() - start) * 1000)
        logger.exception(f"Tool call {name} failed")
        return ToolCall(
            name=name,
            args={str(k): str(v)[:100] for k, v in kwargs.items()},
            result={"error": str(e)},
            duration_ms=duration_ms,
        )


# =============================================================================
# TOOL: Read Event
# =============================================================================


def read_event(event_id: str) -> dict[str, Any]:
    """Fetch event from Firestore by ID."""
    db = get_db()
    doc = db.collection("events").document(event_id).get()

    if not doc.exists:
        raise ValueError(f"Event {event_id} not found")

    data = safe_doc_to_dict(doc)
    return data


# =============================================================================
# TOOL: Get users near event
# =============================================================================


def get_users_near(
    centroid_lat: float,
    centroid_lon: float,
    radius_m: int,
) -> list[dict[str, Any]]:
    """
    Fetch users with last_known_location within radius of centroid.
    
    Note: Firestore doesn't support distance-based queries directly.
    We do a client-side radius check. For production, consider a geohashing library.
    """
    db = get_db()

    # Get all users with known location (brute force; optimize later)
    users = []
    for doc in db.collection("users").stream():
        data = safe_doc_to_dict(doc)

        loc = get_lat_lon(data.get("last_known_location"))
        if not loc:
            continue

        lat, lon = loc
        dist = distance_m(centroid_lat, centroid_lon, lat, lon)

        if dist <= radius_m:
            data["distance_m"] = int(dist)
            users.append(data)

    # Sort by distance
    users.sort(key=lambda u: u.get("distance_m", float("inf")))

    logger.info(f"Found {len(users)} users within {radius_m}m of ({centroid_lat}, {centroid_lon})")
    return users


# =============================================================================
# TOOL: Compute routes (Google Maps Routes API)
# =============================================================================


def compute_routes(
    origin_lat: float,
    origin_lon: float,
    destination_lat: float,
    destination_lon: float,
    avoid_polygons: Optional[list[list[GeoLocation]]] = None,
    prefer_safe_roads: bool = False,
) -> list[Route]:
    """
    Compute 3 alternative routes from origin to destination,
    annotated with risk_score and passes_through_flooded.

    For demo purposes, this is a mock that returns 3 dummy routes.
    Real implementation would call Google Maps Routes API.
    """
    
    # Mock implementation
    origin = GeoLocation(latitude=origin_lat, longitude=origin_lon)
    destination = GeoLocation(latitude=destination_lat, longitude=destination_lon)

    dist = distance_m(origin_lat, origin_lon, destination_lat, destination_lon)
    duration = int(dist / 15)  # Assume 15 m/s average

    routes = [
        Route(
            origin=origin,
            destination=destination,
            distance_m=int(dist * 0.95),
            duration_s=int(duration * 0.95),
            risk_score=0.2,
            passes_through_flooded=False,
            polyline=None,
            risk_explanation="Safest route: avoids flood zone, main roads.",
        ),
        Route(
            origin=origin,
            destination=destination,
            distance_m=int(dist * 1.05),
            duration_s=int(duration * 1.05),
            risk_score=0.5,
            passes_through_flooded=True,
            polyline=None,
            risk_explanation="Passes near affected zone; moderate congestion.",
        ),
        Route(
            origin=origin,
            destination=destination,
            distance_m=int(dist * 1.15),
            duration_s=int(duration * 1.15),
            risk_score=0.3,
            passes_through_flooded=False,
            polyline=None,
            risk_explanation="Longer but low-risk; uses high-ground roads.",
        ),
    ]

    # Filter routes: reject if passes_through_flooded=True (unless severity <= 1)
    # This is checked by caller (agent.py)

    return routes


# =============================================================================
# TOOL: Lookup helpline
# =============================================================================


def lookup_helpline(city: str, crisis_type: str) -> Optional[Helpline]:
    """
    Query helplines collection for best match (city + crisis_type).
    Fall back to city-wide if crisis_type not found.
    """
    db = get_db()

    # Try exact match first
    try:
        docs = list(
            db.collection("helplines")
            .where("city", "==", city)
            .where("crisis_type", "==", crisis_type)
            .limit(1)
            .stream()
        )
        if docs:
            data = safe_doc_to_dict(docs[0])
            return Helpline(
                helpline_id=data.get("_id"),
                name=data.get("name", ""),
                city=data.get("city", ""),
                crisis_type=data.get("crisis_type", ""),
                phone=data.get("phone", ""),
                available_24h=data.get("available_24h", True),
            )
    except Exception as e:
        logger.warning(f"Exact helpline query failed: {e}")

    # Fall back to city only
    try:
        docs = list(
            db.collection("helplines")
            .where("city", "==", city)
            .limit(1)
            .stream()
        )
        if docs:
            data = safe_doc_to_dict(docs[0])
            return Helpline(
                helpline_id=data.get("_id"),
                name=data.get("name", ""),
                city=data.get("city", ""),
                crisis_type=data.get("crisis_type", ""),
                phone=data.get("phone", ""),
                available_24h=data.get("available_24h", True),
            )
    except Exception as e:
        logger.warning(f"City helpline query failed: {e}")

    # Return a generic helpline if all else fails
    logger.warning(f"No helpline found for {city}/{crisis_type}; returning generic")
    return Helpline(
        helpline_id="generic",
        name="Emergency Services",
        city=city,
        crisis_type=crisis_type,
        phone="1122",
        available_24h=True,
    )


# =============================================================================
# TOOL: Find nearest safe spots
# =============================================================================


def find_nearest_safe_spots(
    location_lat: float,
    location_lon: float,
    k: int = 3,
    type_filter: Optional[str] = None,
) -> list[SafeSpot]:
    """
    Find k nearest safe_spots to a location (Euclidean nearest; not realistic geo).
    Optionally filter by type (shelter, hospital, high_ground, etc.).
    """
    db = get_db()

    spots = []
    for doc in db.collection("safe_spots").stream():
        data = safe_doc_to_dict(doc)

        if type_filter and data.get("type") != type_filter:
            continue

        loc = get_lat_lon(data.get("location"))
        if not loc:
            continue

        lat, lon = loc
        dist = distance_m(location_lat, location_lon, lat, lon)

        spot = SafeSpot(
            safe_spot_id=data.get("_id"),
            name=data.get("name", ""),
            location=GeoLocation(latitude=lat, longitude=lon),
            type=data.get("type", "shelter"),
            capacity_people=data.get("capacity_people"),
            distance_m=int(dist),
            contact_phone=data.get("contact_phone"),
            is_open=data.get("is_open", True),
        )
        spots.append(spot)

    # Sort by distance, take top k
    spots.sort(key=lambda s: s.distance_m)
    return spots[:k]


# =============================================================================
# TOOL: Point in polygon (simple)
# =============================================================================


def point_in_polygon(
    lat: float,
    lon: float,
    polygon: list[GeoLocation],
) -> bool:
    """
    Ray casting algorithm: check if (lat, lon) is inside polygon.
    Polygon is list of GeoLocation in order (CCW or CW).
    """
    n = len(polygon)
    inside = False

    p1_lat, p1_lon = polygon[0].latitude, polygon[0].longitude
    for i in range(1, n + 1):
        p2_lat, p2_lon = polygon[i % n].latitude, polygon[i % n].longitude

        if lat > min(p1_lat, p2_lat):
            if lat <= max(p1_lat, p2_lat):
                if lon <= max(p1_lon, p2_lon):
                    if p1_lat != p2_lat:
                        xinters = (lat - p1_lat) * (p2_lon - p1_lon) / (p2_lat - p1_lat) + p1_lon
                    if p1_lon == p2_lon or lon <= xinters:
                        inside = not inside

        p1_lat, p1_lon = p2_lat, p2_lon

    return inside


# =============================================================================
# TOOL: Write plan to Firestore
# =============================================================================


def write_plan(plan: Plan) -> str:
    """Write plan document to Firestore and return plan ID."""
    db = get_db()

    doc = db.collection("plans").document(plan.plan_id)
    doc.set(json.loads(plan.model_dump_json()), merge=True)

    logger.info(f"Wrote plan {plan.plan_id}")
    return plan.plan_id


# =============================================================================
# TOOL: Write trace
# =============================================================================


def write_trace(trace: AgentTrace) -> None:
    """Write execution trace to Firestore."""
    db = get_db()

    if not trace.trace_id:
        trace.trace_id = str(uuid.uuid4())
    if not trace.created_at:
        trace.created_at = now_utc()

    doc = db.collection("agent_traces").document(trace.trace_id)
    doc.set(json.loads(trace.model_dump_json()), merge=True)

    logger.info(f"Wrote trace {trace.trace_id}")


# =============================================================================
# TOOL: User has active route through polygon
# =============================================================================


def user_has_active_route_through_polygon(
    user_id: str,
    polygon: list[GeoLocation],
) -> tuple[bool, Optional[dict]]:
    """
    Check if user has an active navigation route that passes through polygon.
    Returns (has_route, route_data).
    
    For demo, this is a stub. In production, check user's nav state.
    """
    db = get_db()

    try:
        user_doc = db.collection("users").document(user_id).get()
        if not user_doc.exists:
            return False, None

        user_data = safe_doc_to_dict(user_doc)
        active_route = user_data.get("active_route")

        if not active_route:
            return False, None

        # Check if any waypoint in route passes through polygon
        for waypoint in active_route.get("waypoints", []):
            loc = get_lat_lon(waypoint)
            if loc and point_in_polygon(loc[0], loc[1], polygon):
                return True, active_route

        return False, None

    except Exception as e:
        logger.warning(f"Failed to check active route: {e}")
        return False, None


# =============================================================================
# TOOL: User has emergency contacts in area
# =============================================================================


def user_has_emergency_contacts_in_area(
    user_id: str,
    polygon: list[GeoLocation],
) -> list[str]:
    """
    Check if user has emergency_contacts (family) whose last known location
    is inside the event polygon.
    Returns list of contact names/IDs.
    """
    db = get_db()

    try:
        user_doc = db.collection("users").document(user_id).get()
        if not user_doc.exists:
            return []

        user_data = safe_doc_to_dict(user_doc)
        emergency_contacts = user_data.get("emergency_contacts", [])

        contacts_in_area = []

        for contact_id in emergency_contacts:
            try:
                contact_doc = db.collection("users").document(contact_id).get()
                if contact_doc.exists:
                    contact_data = safe_doc_to_dict(contact_doc)
                    loc = get_lat_lon(contact_data.get("last_known_location"))

                    if loc and point_in_polygon(loc[0], loc[1], polygon):
                        contacts_in_area.append(contact_id)
            except Exception as e:
                logger.warning(f"Failed to check contact {contact_id}: {e}")

        return contacts_in_area

    except Exception as e:
        logger.warning(f"Failed to check emergency contacts: {e}")
        return []
