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
try:
    from google.maps import routing_v2
except ImportError:
    routing_v2 = None  # Mock mode — compute_routes uses local logic

from helpline import resolve_helpline
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
# TOOL: Compute routes (Google Maps Routes API + M12 Women's Safe Route Layer)
# =============================================================================

# Road classes that carry a safety penalty per M12 spec
_PENALIZED_ROAD_CLASSES = {"residential", "service", "track", "path", "unclassified"}

# Illuminated highway classes (assumed lit in Pakistani cities)
_LIT_HIGHWAY_CLASSES = {"motorway", "trunk", "primary"}

# Land-use types treated as isolated per M12 spec
_ISOLATED_LANDUSES = {"industrial", "farmland", "farmyard", "cemetery", "quarry"}


def _safety_penalty(
    steps: list[dict[str, Any]],
    road_segments_cache: Optional[dict[str, Any]] = None,
) -> float:
    """
    Compute total safety penalty for a route.

    Per M12 spec:
      - residential / service road: +0.5 × distance_m
      - unlit assumed (tertiary+residential at night, or OSM lit=no): +0.3 × distance_m
      - passes isolated area (industrial/agricultural OSM landuse): +0.4 × distance_m

    `steps` is a list of route step dicts with keys:
        distance_m (int), road_class (str), is_unlit_assumed (bool),
        passes_isolated_area (bool).

    If `road_segments_cache` is provided, the OSM enrichment data from
    Firestore `road_segments` is used; otherwise heuristics are applied.
    """
    penalty = 0.0

    for step in steps:
        dist = step.get("distance_m", 0)
        road = step.get("road_class", "primary")

        # Prefer OSM enrichment data over heuristic if available
        if road_segments_cache:
            cell_id = step.get("cell_id", "")
            seg = road_segments_cache.get(cell_id, {})
            osm_lit = seg.get("lit", "unknown")
            osm_highway = seg.get("highway", road)
            osm_isolated = seg.get("is_isolated", False)
            osm_penalty_pm = seg.get("penalty_per_m", 0.0)

            # Use pre-computed penalty if available from OSM enrichment
            if osm_penalty_pm > 0:
                penalty += dist * osm_penalty_pm
                continue

            # Otherwise apply heuristics using OSM highway class
            road = osm_highway
            unlit = osm_lit in ("no", "unknown") and road not in _LIT_HIGHWAY_CLASSES
            isolated = osm_isolated
        else:
            # Pure heuristic mode (demo / when road_segments not seeded)
            unlit = step.get("is_unlit_assumed", road in ("tertiary", "residential"))
            isolated = step.get("passes_isolated_area", road in ("track", "path"))

        if road in _PENALIZED_ROAD_CLASSES:
            penalty += dist * 0.5

        if unlit:
            penalty += dist * 0.3

        if isolated:
            penalty += dist * 0.4

    return penalty


def _load_road_segments_cache(
    center_lat: float,
    center_lon: float,
    radius_m: float = 20000,
) -> dict[str, Any]:
    """
    Load road segments near the route from Firestore road_segments collection.
    Returns dict keyed by cell_id for fast lookup.

    Fetches at most 500 segments (sufficient for city-scale routes).
    """
    try:
        db = get_db()
        # Approximate bounding box: 0.01° ≈ 1.1km
        delta = radius_m / 111000.0
        lat_min = center_lat - delta
        lat_max = center_lat + delta

        # Firestore can't query on computed fields, so we fetch with a basic
        # city-range filter. For production use a geohash range query.
        docs = (
            db.collection("road_segments")
            .limit(500)
            .stream()
        )

        cache = {}
        for doc in docs:
            data = safe_doc_to_dict(doc)
            cell_id = data.get("cell_id", "")
            if cell_id:
                cache[cell_id] = data

        logger.info(f"Loaded {len(cache)} road segments from Firestore")
        return cache
    except Exception as e:
        logger.warning(f"Could not load road_segments: {e}. Using heuristics.")
        return {}


def _generate_mock_steps(
    origin_lat: float,
    origin_lon: float,
    dest_lat: float,
    dest_lon: float,
    route_variant: int,
    safety_mode: bool,
) -> list[dict[str, Any]]:
    """
    Generate representative mock route steps for demo purposes.
    In production these come from the Google Maps Routes API response.

    route_variant: 0 = main/safest, 1 = faster (some risk), 2 = longer/safer
    safety_mode:   when True, variant 0 and 2 favor main roads
    """
    dist = distance_m(origin_lat, origin_lon, dest_lat, dest_lon)

    # Step templates per route variant
    if route_variant == 0:
        return [
            {"distance_m": int(dist * 0.50), "road_class": "primary",
             "road_name": "Stadium Road / Shahrah-e-Faisal",
             "is_unlit_assumed": False, "passes_isolated_area": False},
            {"distance_m": int(dist * 0.30), "road_class": "secondary",
             "road_name": "Main Boulevard",
             "is_unlit_assumed": False, "passes_isolated_area": False},
            {"distance_m": int(dist * 0.20), "road_class": "primary",
             "road_name": "Jinnah Avenue",
             "is_unlit_assumed": False, "passes_isolated_area": False},
        ]
    elif route_variant == 1:
        return [
            {"distance_m": int(dist * 0.30), "road_class": "primary",
             "road_name": "IJP Road",
             "is_unlit_assumed": False, "passes_isolated_area": False},
            {"distance_m": int(dist * 0.40), "road_class": "residential",
             "road_name": "Korangi back lanes",
             "is_unlit_assumed": True, "passes_isolated_area": False},
            {"distance_m": int(dist * 0.30), "road_class": "service",
             "road_name": "Industrial Area bypass",
             "is_unlit_assumed": True, "passes_isolated_area": True},
        ]
    else:
        return [
            {"distance_m": int(dist * 0.40), "road_class": "primary",
             "road_name": "Margalla Avenue",
             "is_unlit_assumed": False, "passes_isolated_area": False},
            {"distance_m": int(dist * 0.40), "road_class": "secondary",
             "road_name": "F-10 Markaz Road",
             "is_unlit_assumed": False, "passes_isolated_area": False},
            {"distance_m": int(dist * 0.20), "road_class": "tertiary",
             "road_name": "G-9 Link",
             "is_unlit_assumed": True, "passes_isolated_area": False},
        ]


def _build_safety_reasoning(
    steps: list[dict[str, Any]],
    penalty: float,
    route_index: int,
    safety_mode: bool,
) -> str:
    """
    Build explicit reasoning text for route display per M12 spec.

    Example: "Route 1 is 4 min longer but stays on Stadium Road and
    Shahrah-e-Faisal — avoiding the back lanes in Korangi."
    """
    if not safety_mode:
        # Standard flood-only reasoning
        road_names = [s.get("road_name", "") for s in steps if s.get("road_name")]
        if route_index == 0:
            return f"Shortest route via {', '.join(road_names[:2]) or 'main roads'}."
        elif route_index == 1:
            return "Passes near affected zone; moderate congestion expected."
        else:
            return f"Longer but avoids main congestion points."

    # Safety mode: explicit explanation as per spec
    main_roads = [s["road_name"] for s in steps if s.get("road_class") in ("motorway", "trunk", "primary", "secondary")]
    back_roads = [s["road_name"] for s in steps if s.get("road_class") in ("residential", "service", "track")]
    unlit_roads = [s["road_name"] for s in steps if s.get("is_unlit_assumed")]
    isolated = [s["road_name"] for s in steps if s.get("passes_isolated_area")]

    if route_index == 0:
        if main_roads:
            return (
                f"Safest route: stays on {', '.join(main_roads[:2])} — "
                f"well-lit main roads throughout."
            )
        return "Safest route: prioritises well-lit main roads."

    elif route_index == 1:
        issues = []
        if back_roads:
            issues.append(f"passes through {', '.join(back_roads[:1])}")
        if unlit_roads:
            issues.append("includes poorly-lit sections")
        if isolated:
            issues.append(f"passes isolated area near {', '.join(isolated[:1])}")
        issues_text = "; ".join(issues) if issues else "uses some secondary roads"
        return f"Moderate: {issues_text}. Faster but higher safety penalty ({penalty:.0f}pts)."

    else:  # route_index == 2
        if main_roads:
            return (
                f"Safer but longer: stays on {', '.join(main_roads[:2])} — "
                f"avoids back lanes. Safety penalty: {penalty:.0f}pts."
            )
        return f"Longer but safer route. Safety penalty: {penalty:.0f}pts."


def compute_routes(
    origin_lat: float,
    origin_lon: float,
    destination_lat: float,
    destination_lon: float,
    avoid_polygons: Optional[list[list[GeoLocation]]] = None,
    prefer_safe_roads: bool = False,
    safety_mode: bool = False,
) -> list[Route]:
    """
    Compute 3 alternative routes from origin to destination.

    When safety_mode=True (M12 Women's Safe Route):
      - Fetches road_segments from Firestore for OSM enrichment
      - Applies _safety_penalty per step (residential, unlit, isolated)
      - Sorts routes by (passes_through_flooded, risk_score, duration_s)
      - Adds explicit reasoning text for each route
      - prefer_safe_roads=True is equivalent to safety_mode=True

    When safety_mode=False:
      - risk_score = flood_risk_score only
      - Sorted by (passes_through_flooded, duration_s)

    Returns top 3 routes.
    """
    effective_safety = safety_mode or prefer_safe_roads

    origin = GeoLocation(latitude=origin_lat, longitude=origin_lon)
    destination = GeoLocation(latitude=destination_lat, longitude=destination_lon)

    dist = distance_m(origin_lat, origin_lon, destination_lat, destination_lon)
    duration_base = int(dist / 13)  # ~13 m/s city speed

    # Load OSM road segment data from Firestore if safety mode is active
    road_segments_cache: dict[str, Any] = {}
    if effective_safety:
        mid_lat = (origin_lat + destination_lat) / 2
        mid_lon = (origin_lon + destination_lon) / 2
        road_segments_cache = _load_road_segments_cache(mid_lat, mid_lon)

    # Generate 3 route variants with mock steps
    raw_routes = []
    for variant in range(3):
        steps = _generate_mock_steps(
            origin_lat, origin_lon, destination_lat, destination_lon,
            variant, effective_safety
        )

        # Base flood risk scores per variant
        flood_risk = [0.2, 0.55, 0.3][variant]
        passes_flooded = variant == 1  # Middle route passes near flood zone

        # Compute safety penalty using spec formula
        safety_pen = 0.0
        if effective_safety:
            safety_pen = _safety_penalty(steps, road_segments_cache)

        # M12 spec: risk_score = safety_penalty + flood_risk_score (safety mode)
        #           risk_score = flood_risk_score only (normal mode)
        risk_score = (safety_pen / max(dist, 1) + flood_risk) if effective_safety else flood_risk

        # Route distance/duration varies by variant
        mult = [0.95, 1.0, 1.15][variant]

        reasoning = _build_safety_reasoning(steps, safety_pen, variant, effective_safety)

        raw_routes.append({
            "origin": origin,
            "destination": destination,
            "distance_m": int(dist * mult),
            "duration_s": int(duration_base * mult),
            "risk_score": round(risk_score, 3),
            "passes_through_flooded": passes_flooded,
            "polyline": None,
            "risk_explanation": reasoning,
            "safety_penalty": round(safety_pen, 1),
            "steps": steps,
        })

    # M12 spec sort: (passes_through_flooded, risk_score, duration_s)
    raw_routes.sort(
        key=lambda r: (
            int(r["passes_through_flooded"]),
            r["risk_score"],
            r["duration_s"],
        )
    )

    result = []
    for r in raw_routes[:3]:
        result.append(Route(
            origin=r["origin"],
            destination=r["destination"],
            distance_m=r["distance_m"],
            duration_s=r["duration_s"],
            risk_score=r["risk_score"],
            passes_through_flooded=r["passes_through_flooded"],
            polyline=r["polyline"],
            risk_explanation=r["risk_explanation"],
        ))

    logger.info(
        f"compute_routes: safety_mode={effective_safety}, "
        f"routes={[(r.risk_score, r.passes_through_flooded) for r in result]}"
    )
    return result


# =============================================================================
# TOOL: Lookup helpline
# =============================================================================


def lookup_helpline(city: str, crisis_type: str) -> Optional[Helpline]:
    """
    Query helplines collection for best match (city + crisis_type).
    Fall back to city-wide if crisis_type not found.
    """
    result = resolve_helpline(city=city, crisis_type=crisis_type, mode="auto")
    if not result:
        return None

    notes = result.get("notes", "") or ""
    available_24h = "24/7" in notes or "24x7" in notes

    return Helpline(
        helpline_id=result.get("helpline_id", ""),
        name=result.get("name", ""),
        city=city,
        crisis_type=crisis_type,
        phone=result.get("number", ""),
        available_24h=available_24h,
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
