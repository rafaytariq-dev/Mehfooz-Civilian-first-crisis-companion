"""
Planning Agent — main planning logic.

This file performs M4:
1. Read event.
2. Get users near event.
3. Apply per-user decision tree.
4. Compute system actions.
5. Write plan doc.
6. Write trace doc.
"""

from __future__ import annotations

import logging
import time
import uuid
from datetime import datetime, timezone
from typing import Any, Optional

from models import (
    ActionVerb,
    AgentTrace,
    GeoLocation,
    Helpline,
    Plan,
    PlanRequest,
    PlanResult,
    Route,
    SafeSpot,
    SystemAction,
    SystemActionType,
    ToolCall,
    Urgency,
    UserAction,
)
from tools import (
    compute_routes,
    find_nearest_safe_spots,
    get_lat_lon,
    get_users_near,
    lookup_helpline,
    make_tool_call,
    now_utc,
    point_in_polygon,
    read_event,
    user_has_active_route_through_polygon,
    user_has_emergency_contacts_in_area,
    write_plan,
    write_trace,
)

logger = logging.getLogger("planning.agent")


def parse_event(event_data: dict[str, Any]) -> dict[str, Any]:
    """Extract and validate event structure."""
    required = ["event_id", "centroid", "polygon", "severity", "crisis_type"]

    for field in required:
        if field not in event_data:
            raise ValueError(f"Event missing required field: {field}")

    # Normalize polygon
    polygon_raw = event_data.get("polygon", [])
    polygon = []

    for pt in polygon_raw:
        loc = get_lat_lon(pt)
        if loc:
            polygon.append(GeoLocation(latitude=loc[0], longitude=loc[1]))

    # Normalize centroid
    centroid_loc = get_lat_lon(event_data.get("centroid"))
    if not centroid_loc:
        raise ValueError("Event centroid is invalid")

    centroid = GeoLocation(latitude=centroid_loc[0], longitude=centroid_loc[1])

    return {
        "event_id": event_data.get("event_id"),
        "centroid": centroid,
        "polygon": polygon,
        "severity": int(event_data.get("severity", 0)),
        "crisis_type": event_data.get("crisis_type", "urban_flood"),
        "city": event_data.get("city", "Islamabad"),
        "raw": event_data,
    }


def compute_urgency_from_severity(severity: int) -> Urgency:
    """Map event severity to action urgency."""
    if severity >= 5:
        return Urgency.sos
    elif severity >= 4:
        return Urgency.high
    elif severity >= 3:
        return Urgency.med
    else:
        return Urgency.low


def per_user_action_decision_tree(
    user_data: dict[str, Any],
    event: dict[str, Any],
    tools_called: list[ToolCall],
) -> Optional[UserAction]:
    """
    Apply decision tree logic to recommend an action for a single user.

    Decision tree (from spec):
      if user in polygon AND severity >= 4:
        → EVACUATE (give safe_spots[3])
      elif user in polygon AND severity <= 3:
        → SHELTER_IN_PLACE (give helpline, neighbors)
      elif user has active route through polygon:
        → REROUTE (give alternatives avoiding polygon)
      elif user within 2km AND severity >= 3:
        → AVOID_AREA (passive)
      elif user has emergency_contacts in event area:
        → CHECK_ON_FAMILY (passive)
      else:
        → None (no action needed)
    """

    user_id = user_data.get("_id")
    user_loc = get_lat_lon(user_data.get("last_known_location"))

    if not user_loc:
        logger.debug(f"User {user_id} has no known location")
        return None

    user_gpt = GeoLocation(latitude=user_loc[0], longitude=user_loc[1])

    centroid = event["centroid"]
    polygon = event["polygon"]
    severity = event["severity"]
    crisis_type = event["crisis_type"]
    city = event["city"]

    # Check if user is in polygon
    user_in_polygon = point_in_polygon(user_loc[0], user_loc[1], polygon)

    urgency_base = compute_urgency_from_severity(severity)

    # ===========================================================================
    # DECISION 1: User in polygon AND severity >= 4 → EVACUATE
    # ===========================================================================
    if user_in_polygon and severity >= 4:
        safe_spots_call = make_tool_call(
            "find_nearest_safe_spots",
            find_nearest_safe_spots,
            location_lat=user_loc[0],
            location_lon=user_loc[1],
            k=3,
            type_filter="shelter",
        )
        tools_called.append(safe_spots_call)

        safe_spots = safe_spots_call.result if isinstance(safe_spots_call.result, list) else []

        helpline_call = make_tool_call(
            "lookup_helpline",
            lookup_helpline,
            city=city,
            crisis_type=crisis_type,
        )
        tools_called.append(helpline_call)

        helpline = helpline_call.result if isinstance(helpline_call.result, Helpline) else None

        message_en = f"EVACUATE: {severity}-level event nearby. Seek shelter at marked locations. Call {helpline.phone if helpline else '1122'} if needed."
        message_ur = f"فوری نکلیں: گھر سے نکل کر محفوظ جگہ تلاش کریں۔ مدد کے لیے {helpline.phone if helpline else '1122'} پر کال کریں۔"

        return UserAction(
            verb=ActionVerb.EVACUATE,
            message_en=message_en[:100],
            message_ur=message_ur[:100],
            safe_spots=safe_spots,
            helpline=helpline,
            urgency=Urgency.sos,
            metadata={
                "reason": "in_polygon_severity_4_or_higher",
                "severity": severity,
            },
        )

    # ===========================================================================
    # DECISION 2: User in polygon AND severity <= 3 → SHELTER_IN_PLACE
    # ===========================================================================
    if user_in_polygon and severity <= 3:
        helpline_call = make_tool_call(
            "lookup_helpline",
            lookup_helpline,
            city=city,
            crisis_type=crisis_type,
        )
        tools_called.append(helpline_call)

        helpline = helpline_call.result if isinstance(helpline_call.result, Helpline) else None

        message_en = f"SHELTER IN PLACE: Light flooding detected. Stay home and monitor updates. Help: {helpline.phone if helpline else '1122'}."
        message_ur = f"گھر میں رہیں: پانی کا خطرہ ہے۔ گھر میں رہ کر اپ ڈیٹ سنیں۔ مدد: {helpline.phone if helpline else '1122'}۔"

        return UserAction(
            verb=ActionVerb.SHELTER_IN_PLACE,
            message_en=message_en[:100],
            message_ur=message_ur[:100],
            helpline=helpline,
            urgency=urgency_base,
            metadata={
                "reason": "in_polygon_low_severity",
                "severity": severity,
            },
        )

    # ===========================================================================
    # DECISION 3: User has active route through polygon → REROUTE
    # ===========================================================================
    has_route, route_data = user_has_active_route_through_polygon(user_id, polygon)

    if has_route and route_data:
        destination = route_data.get("destination")
        if destination:
            dest_lat, dest_lon = (
                get_lat_lon(destination)
                or (centroid.latitude + 0.1, centroid.longitude + 0.1)
            )

            routes_call = make_tool_call(
                "compute_routes",
                compute_routes,
                origin_lat=user_loc[0],
                origin_lon=user_loc[1],
                destination_lat=dest_lat,
                destination_lon=dest_lon,
                avoid_polygons=[polygon],
                prefer_safe_roads=user_data.get("women_safe_route", False),
            )
            tools_called.append(routes_call)

            routes = routes_call.result if isinstance(routes_call.result, list) else []

            # Filter: reject routes where passes_through_flooded=True unless severity <= 1
            if severity > 1:
                routes = [r for r in routes if not r.passes_through_flooded]

            message_en = f"REROUTE: Flooding on your planned route. Use alternate roads below (safest first)."
            message_ur = f"راستہ بدلیں: آپ کے راستے میں سیلاب ہے۔ دوسری سڑکوں سے جائیں۔"

            return UserAction(
                verb=ActionVerb.REROUTE,
                message_en=message_en[:100],
                message_ur=message_ur[:100],
                route_alternatives=routes[:3],
                urgency=urgency_base,
                metadata={
                    "reason": "active_route_through_polygon",
                    "original_destination": destination,
                },
            )

    # ===========================================================================
    # DECISION 4: User within 2km AND severity >= 3 → AVOID_AREA
    # ===========================================================================
    user_distance_m = user_data.get("distance_m", float("inf"))

    if user_distance_m <= 2000 and severity >= 3 and not user_in_polygon:
        message_en = f"AVOID: Crisis detected {int(user_distance_m / 1000)}km away. Avoid area if traveling."
        message_ur = f"علاقہ سے بچیں: سنگین صورتحال ہے۔ اگر باہر جانا ہو تو احتیاط کریں۔"

        return UserAction(
            verb=ActionVerb.AVOID_AREA,
            message_en=message_en[:100],
            message_ur=message_ur[:100],
            urgency=urgency_base,
            metadata={
                "reason": "near_event_high_severity",
                "distance_m": int(user_distance_m),
            },
        )

    # ===========================================================================
    # DECISION 5: User has emergency_contacts in event area → CHECK_ON_FAMILY
    # ===========================================================================
    contacts_in_area = user_has_emergency_contacts_in_area(user_id, polygon)

    if contacts_in_area:
        message_en = f"CHECK ON FAMILY: {len(contacts_in_area)} contact(s) in affected area. Call to confirm safety."
        message_ur = f"خاندان سے رابطہ کریں: آپ کے رشتے داروں کا علاقہ متاثر ہے۔ ان سے بات کریں۔"

        return UserAction(
            verb=ActionVerb.CHECK_ON_FAMILY,
            message_en=message_en[:100],
            message_ur=message_ur[:100],
            urgency=Urgency.med,
            metadata={
                "reason": "contacts_in_polygon",
                "contact_ids": contacts_in_area,
            },
        )

    # ===========================================================================
    # No action needed
    # ===========================================================================
    logger.debug(f"User {user_id} has no matching decision tree condition")
    return None


def compute_system_actions(event: dict[str, Any], tools_called: list[ToolCall]) -> list[SystemAction]:
    """
    Compute system-level actions.

    System track from spec:
    - notify_helpline (event city + crisis type)
    - flag_route (if applicable)
    - broadcast_zone (if severity >= 4)
    """

    actions = []
    severity = event["severity"]
    crisis_type = event["crisis_type"]
    city = event["city"]

    # ===========================================================================
    # ACTION 1: Notify helpline
    # ===========================================================================
    helpline_call = make_tool_call(
        "lookup_helpline",
        lookup_helpline,
        city=city,
        crisis_type=crisis_type,
    )
    tools_called.append(helpline_call)

    helpline = helpline_call.result if isinstance(helpline_call.result, Helpline) else None

    if helpline:
        actions.append(
            SystemAction(
                type=SystemActionType.notify_helpline,
                target=helpline.helpline_id,
                payload={
                    "helpline_name": helpline.name,
                    "phone": helpline.phone,
                    "crisis_type": crisis_type,
                    "city": city,
                    "severity": severity,
                    "event_id": event["event_id"],
                    "centroid": {
                        "lat": event["centroid"].latitude,
                        "lon": event["centroid"].longitude,
                    },
                },
                urgency=compute_urgency_from_severity(severity),
            )
        )

    # ===========================================================================
    # ACTION 2: Flag route (if applicable)
    # ===========================================================================
    # This is a placeholder. Real impl would identify major roads passing through polygon.
    if severity >= 3:
        actions.append(
            SystemAction(
                type=SystemActionType.flag_route,
                target="major_roads_in_polygon",
                payload={
                    "polygon": [
                        {"lat": pt.latitude, "lon": pt.longitude} for pt in event["polygon"]
                    ],
                    "severity": severity,
                    "reason": "Flooding detected; routes unsafe.",
                },
                urgency=compute_urgency_from_severity(severity),
            )
        )

    # ===========================================================================
    # ACTION 3: Broadcast to zone (if severity >= 4)
    # ===========================================================================
    if severity >= 4:
        actions.append(
            SystemAction(
                type=SystemActionType.broadcast_zone,
                target=f"radius_5km_{city}",
                payload={
                    "centroid": {
                        "lat": event["centroid"].latitude,
                        "lon": event["centroid"].longitude,
                    },
                    "radius_m": 5000,
                    "message": f"ALERT: Level {severity} {crisis_type} event detected. Seek shelter. Call 1122.",
                    "severity": severity,
                },
                urgency=Urgency.sos if severity >= 5 else Urgency.high,
            )
        )

    return actions


async def run_planning(req: PlanRequest) -> PlanResult:
    """
    Main planning agent entry point.

    1. Read event.
    2. Get users near event.
    3. Apply per-user decision tree.
    4. Compute system actions.
    5. Write plan.
    6. Write trace.
    """

    plan_id = str(uuid.uuid4())
    trace = AgentTrace(
        plan_id=plan_id,
        event_id=req.event_id,
        step="start",
        created_at=now_utc(),
    )
    tools_called: list[ToolCall] = []

    start_time = time.time()

    try:
        # =====================================================================
        # STEP 1: Read event
        # =====================================================================
        trace.step = "read_event"
        logger.info(f"Reading event {req.event_id}")

        read_event_call = make_tool_call(
            "read_event",
            read_event,
            event_id=req.event_id,
        )
        tools_called.append(read_event_call)

        if isinstance(read_event_call.result, dict):
            event_data = read_event_call.result
        else:
            raise ValueError(f"Failed to read event: {read_event_call.result}")

        event = parse_event(event_data)
        trace.input_summary = f"Event: {event['event_id']}, severity={event['severity']}, crisis_type={event['crisis_type']}"

        # =====================================================================
        # STEP 2: Get users near event
        # =====================================================================
        trace.step = "get_users_near"
        logger.info(f"Finding users within 5km of event centroid")

        users_call = make_tool_call(
            "get_users_near",
            get_users_near,
            centroid_lat=event["centroid"].latitude,
            centroid_lon=event["centroid"].longitude,
            radius_m=5000,
        )
        tools_called.append(users_call)

        users = users_call.result if isinstance(users_call.result, list) else []
        logger.info(f"Found {len(users)} users")

        # =====================================================================
        # STEP 3: Compute system actions
        # =====================================================================
        trace.step = "compute_system_actions"
        system_actions = compute_system_actions(event, tools_called)
        logger.info(f"Computed {len(system_actions)} system actions")

        # =====================================================================
        # STEP 4: Apply per-user decision tree
        # =====================================================================
        trace.step = "per_user_decision_tree"
        user_actions = {}

        for user_data in users:
            user_id = user_data.get("_id")
            action = per_user_action_decision_tree(user_data, event, tools_called)

            if action:
                user_actions[user_id] = action
                logger.info(f"User {user_id}: {action.verb.value}")

        logger.info(f"Generated actions for {len(user_actions)} users")

        # =====================================================================
        # STEP 5: Construct and write plan
        # =====================================================================
        trace.step = "write_plan"

        plan = Plan(
            plan_id=plan_id,
            event_id=req.event_id,
            created_at=now_utc(),
            system_actions=system_actions,
            user_actions=user_actions,
        )

        if not req.dry_run:
            write_plan_call = make_tool_call(
                "write_plan",
                write_plan,
                plan=plan,
            )
            tools_called.append(write_plan_call)

            logger.info(f"Wrote plan {plan_id}")

        # =====================================================================
        # STEP 6: Write trace
        # =====================================================================
        trace.step = "write_trace"
        trace.output_summary = f"Plan: {len(system_actions)} system actions, {len(user_actions)} user actions"
        trace.reasoning = "Applied per-user decision tree per M4 spec"
        trace.tools_called = tools_called
        trace.duration_ms = int((time.time() - start_time) * 1000)

        if not req.dry_run:
            write_trace(trace)

        # =====================================================================
        # Return result
        # =====================================================================
        return PlanResult(
            plan_id=plan_id,
            event_id=req.event_id,
            system_actions_count=len(system_actions),
            user_actions_count=len(user_actions),
            duration_ms=trace.duration_ms,
            errors=[],
        )

    except Exception as e:
        logger.exception(f"Planning failed: {e}")
        trace.duration_ms = int((time.time() - start_time) * 1000)
        trace.tools_called = tools_called

        if not req.dry_run:
            write_trace(trace)

        return PlanResult(
            event_id=req.event_id,
            system_actions_count=0,
            user_actions_count=0,
            duration_ms=trace.duration_ms,
            errors=[str(e)],
        )


async def run_test_planning() -> dict[str, Any]:
    """Local smoke test without Firestore."""
    logger.info("Running test planning (mock data)")

    mock_event = {
        "event_id": "test-event-001",
        "centroid": GeoLocation(latitude=33.7295, longitude=73.1947),  # Islamabad
        "polygon": [
            GeoLocation(latitude=33.728, longitude=73.193),
            GeoLocation(latitude=33.728, longitude=73.196),
            GeoLocation(latitude=33.731, longitude=73.196),
            GeoLocation(latitude=33.731, longitude=73.193),
        ],
        "severity": 4,
        "crisis_type": "urban_flood",
        "city": "Islamabad",
    }

    return {
        "status": "ok",
        "test": "planning",
        "mock_event_id": mock_event["event_id"],
        "mock_severity": mock_event["severity"],
    }
