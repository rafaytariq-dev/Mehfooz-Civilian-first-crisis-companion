"""
Simulation Agent — Tools (Firestore + mock endpoint interactions).

Reads:
- plans (from M4)
- events (for severity/crisis_type context)

Writes:
- push_queue (notification entries for M6 Comms agent)
- simulation_reports
- agent_traces

Calls:
- Mock Cloud Function endpoints (PDMA, Rescue 1122, Traffic, SMS)
- NEVER calls real authority APIs.
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
from google.cloud import firestore

from config import (
    AUTHORITY_MAP,
    AVG_DELAY_MODERATE_MIN,
    AVG_DELAY_SEVERE_MIN,
    CONGESTION_REDUCTION_FACTOR,
    MOCK_ENDPOINTS,
    MOCK_ENDPOINTS_BASE_URL,
    PROJECT_ID,
    RESPONSE_TIME_SAVED_SOS_MIN,
    SYSTEM_ACTION_ENDPOINT_MAP,
)
from models import (
    AgentTrace,
    DispatchRecord,
    EstimatedImpact,
    NotificationCounts,
    PushQueueEntry,
    SimulationReport,
    ToolCall,
)

logger = logging.getLogger("simulation.tools")

_db: firestore.Client | None = None


def get_db() -> firestore.Client:
    """Lazy-initialize Firestore client."""
    global _db
    if _db is None:
        _db = firestore.Client(project=PROJECT_ID)
    return _db


def now_utc() -> datetime:
    """Current time in UTC."""
    return datetime.now(timezone.utc)


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
    """Wrap a tool call with timing and result capture for tracing."""
    start = time.time()
    try:
        result = func(*args, **kwargs)
        duration_ms = int((time.time() - start) * 1000)
        return ToolCall(
            name=name,
            args={str(k): str(v)[:200] for k, v in kwargs.items()},
            result=result,
            duration_ms=duration_ms,
        )
    except Exception as e:
        duration_ms = int((time.time() - start) * 1000)
        logger.exception(f"Tool call {name} failed")
        return ToolCall(
            name=name,
            args={str(k): str(v)[:200] for k, v in kwargs.items()},
            result={"error": str(e)},
            duration_ms=duration_ms,
        )


# =============================================================================
# TOOL: Read Plan from Firestore
# =============================================================================


def read_plan(plan_id: str) -> dict[str, Any]:
    """Fetch plan doc from Firestore plans collection."""
    db = get_db()
    doc = db.collection("plans").document(plan_id).get()

    if not doc.exists:
        raise ValueError(f"Plan {plan_id} not found in Firestore")

    data = safe_doc_to_dict(doc)
    logger.info(f"Read plan {plan_id}: {len(data.get('user_actions', {}))} user actions, "
                f"{len(data.get('system_actions', []))} system actions")
    return data


# =============================================================================
# TOOL: Read Event from Firestore
# =============================================================================


def read_event(event_id: str) -> dict[str, Any]:
    """Fetch event doc from Firestore events collection."""
    db = get_db()
    doc = db.collection("events").document(event_id).get()

    if not doc.exists:
        raise ValueError(f"Event {event_id} not found in Firestore")

    return safe_doc_to_dict(doc)


# =============================================================================
# TOOL: Post to mock endpoint
# =============================================================================


def post_to_mock(endpoint_key: str, payload: dict[str, Any]) -> DispatchRecord:
    """
    POST to a mock Cloud Function endpoint.

    IMPORTANT: This only calls MOCK endpoints. Never real authority APIs.

    Args:
        endpoint_key: One of 'pdma_dispatch', 'rescue_1122', 'traffic_reroute', 'sms_blast'
        payload: Dict to send as JSON body

    Returns:
        DispatchRecord with ticket_id and response status
    """
    if endpoint_key not in MOCK_ENDPOINTS:
        raise ValueError(
            f"Unknown mock endpoint: {endpoint_key}. "
            f"Valid keys: {list(MOCK_ENDPOINTS.keys())}"
        )

    url = f"{MOCK_ENDPOINTS_BASE_URL}{MOCK_ENDPOINTS[endpoint_key]}"
    authority = AUTHORITY_MAP.get(endpoint_key, endpoint_key)

    # Build a human-readable payload summary (≤ 200 chars)
    payload_summary = _build_payload_summary(authority, payload)

    logger.info(f"POST to mock endpoint: {url} (authority={authority})")

    start = time.time()
    try:
        with httpx.Client(timeout=10.0) as client:
            resp = client.post(url, json=payload)
            response_time_ms = int((time.time() - start) * 1000)

            if resp.status_code == 200:
                body = resp.json()
                ticket_id = body.get("ticket_id", f"UNKNOWN-{int(time.time())}")
                status = body.get("status", "queued")
            else:
                logger.warning(
                    f"Mock endpoint {url} returned HTTP {resp.status_code}: {resp.text[:200]}"
                )
                ticket_id = f"ERR-{int(time.time())}"
                status = f"http_{resp.status_code}"
                response_time_ms = int((time.time() - start) * 1000)

    except Exception as e:
        response_time_ms = int((time.time() - start) * 1000)
        logger.error(f"Failed to call mock endpoint {url}: {e}")
        ticket_id = f"FAIL-{int(time.time())}"
        status = "connection_error"

    record = DispatchRecord(
        authority=authority,
        ticket_id=ticket_id,
        endpoint=url,
        payload_summary=payload_summary,
        status=status,
        response_time_ms=response_time_ms,
    )

    logger.info(f"Dispatch: {authority} → ticket={ticket_id}, status={status}, "
                f"response_time={response_time_ms}ms")
    return record


def _build_payload_summary(authority: str, payload: dict) -> str:
    """Build ≤ 200 char human-readable summary of a dispatch payload."""
    event_id = payload.get("event_id", "?")
    severity = payload.get("severity", "?")
    crisis = payload.get("crisis_type", payload.get("type", "?"))
    city = payload.get("city", "?")
    users = payload.get("total_users", payload.get("recipients_count", "?"))

    summary = (
        f"{authority}: event={event_id}, severity={severity}, "
        f"crisis={crisis}, city={city}"
    )

    if users != "?":
        summary += f", users={users}"

    return summary[:200]


# =============================================================================
# TOOL: Queue push notification (for M6 Comms agent)
# =============================================================================


def queue_push(
    user_id: str,
    event_id: str,
    plan_id: str,
    verb: str,
    urgency: str,
    message_en: str,
    message_ur: str,
) -> PushQueueEntry:
    """
    Write a push notification entry to the push_queue Firestore collection.
    Does NOT send FCM directly — M6 Comms agent handles actual delivery.
    This keeps notification policy in one place.
    """
    db = get_db()
    queued_at = now_utc()

    entry = PushQueueEntry(
        user_id=user_id,
        event_id=event_id,
        plan_id=plan_id,
        verb=verb,
        urgency=urgency,
        message_en=message_en,
        message_ur=message_ur,
        queued_at=queued_at,
    )

    doc_id = f"push_{user_id}_{plan_id}_{int(queued_at.timestamp())}"
    db.collection("push_queue").document(doc_id).set(
        json.loads(entry.model_dump_json())
    )

    logger.info(f"Queued push: user={user_id}, verb={verb}, urgency={urgency}")
    return entry


# =============================================================================
# TOOL: Estimate impact (transparent heuristics from spec)
# =============================================================================


def estimate_impact(
    user_actions: dict[str, Any],
    severity: int,
) -> EstimatedImpact:
    """
    Compute estimated impact using transparent heuristics from M5 spec.

    - users_diverted = count of REROUTE actions
    - avg_delay_saved = 22 min (severity >= 4) or 12 min (severity < 4)
    - congestion_reduction_min = diverted * 0.3 * avg_delay_saved
    - response_time_saved_min = 8 if any SOS action, else 0

    IMPORTANT: These are estimates. Always label as such in UI.
    """
    diverted = 0
    has_sos = False

    for uid, action in user_actions.items():
        verb = action.get("verb", "") if isinstance(action, dict) else getattr(action, "verb", "")
        urgency = action.get("urgency", "") if isinstance(action, dict) else getattr(action, "urgency", "")

        if verb == "REROUTE":
            diverted += 1
        if urgency == "sos":
            has_sos = True

    avg_delay = AVG_DELAY_SEVERE_MIN if severity >= 4 else AVG_DELAY_MODERATE_MIN
    congestion_reduction = diverted * CONGESTION_REDUCTION_FACTOR * avg_delay
    response_time_saved = RESPONSE_TIME_SAVED_SOS_MIN if has_sos else 0.0

    impact = EstimatedImpact(
        congestion_reduction_min=round(congestion_reduction, 1),
        users_diverted=diverted,
        response_time_saved_min=response_time_saved,
    )

    logger.info(
        f"Impact estimate: diverted={diverted}, congestion_reduction={congestion_reduction:.1f}min, "
        f"response_time_saved={response_time_saved}min"
    )
    return impact


# =============================================================================
# TOOL: Count notifications by urgency tier
# =============================================================================


def count_notifications(user_actions: dict[str, Any]) -> NotificationCounts:
    """Count user actions by urgency tier."""
    counts = {"sos": 0, "high": 0, "med": 0, "low": 0}

    for uid, action in user_actions.items():
        urgency = (
            action.get("urgency", "low")
            if isinstance(action, dict)
            else getattr(action, "urgency", "low")
        )
        urgency_str = urgency if isinstance(urgency, str) else urgency.value
        if urgency_str in counts:
            counts[urgency_str] += 1
        else:
            counts["low"] += 1

    return NotificationCounts(
        sos=counts["sos"],
        high=counts["high"],
        med=counts["med"],
        low=counts["low"],
        total_users=sum(counts.values()),
    )


# =============================================================================
# TOOL: Count routes flagged
# =============================================================================


def count_routes_flagged(system_actions: list[dict[str, Any]]) -> int:
    """Count how many system actions are of type 'flag_route'."""
    count = 0
    for action in system_actions:
        action_type = (
            action.get("type", "")
            if isinstance(action, dict)
            else getattr(action, "type", "")
        )
        if action_type == "flag_route":
            count += 1
    return count


# =============================================================================
# TOOL: Generate summary text for demo card
# =============================================================================


def generate_summary(
    notifications: NotificationCounts,
    routes_flagged: int,
    dispatches: list[DispatchRecord],
    impact: EstimatedImpact,
) -> tuple[str, str]:
    """
    Generate English and Urdu summary card text.

    Target format from spec:
    "47 users alerted, 3 routes flagged, 1 ticket dispatched,
     est. 22 min congestion reduction"
    """
    total_users = notifications.total_users
    dispatch_count = len(dispatches)

    # Build authority list for the summary
    authorities = list({d.authority for d in dispatches})
    authority_str = " + ".join(authorities) if authorities else "none"

    # ─── English summary ───
    summary_en = (
        f"{total_users} users alerted, "
        f"{routes_flagged} routes flagged, "
        f"{dispatch_count} ticket{'s' if dispatch_count != 1 else ''} dispatched "
        f"({authority_str}), "
        f"est. {impact.congestion_reduction_min:.0f} min congestion reduction."
    )

    if impact.response_time_saved_min > 0:
        summary_en += f" Est. {impact.response_time_saved_min:.0f} min response time saved."

    summary_en += " [Estimates — not real data]"

    # ─── Urdu summary (simple conversational register, not literary) ───
    summary_ur = (
        f"{total_users} صارفین کو الرٹ کیا، "
        f"{routes_flagged} راستے نشان زد، "
        f"{dispatch_count} ٹکٹ بھیجے ({authority_str})، "
        f"تخمینی {impact.congestion_reduction_min:.0f} منٹ ٹریفک کم۔"
    )

    if impact.response_time_saved_min > 0:
        summary_ur += f" تخمینی {impact.response_time_saved_min:.0f} منٹ ریسپانس ٹائم بچایا۔"

    summary_ur += " [تخمینہ — حقیقی ڈیٹا نہیں]"

    return summary_en, summary_ur


# =============================================================================
# TOOL: Write simulation report to Firestore
# =============================================================================


def write_simulation_report(report: SimulationReport) -> str:
    """
    Persist SimulationReport to simulation_reports collection.
    Returns report_id.
    """
    db = get_db()

    doc = db.collection("simulation_reports").document(report.report_id)
    doc.set(json.loads(report.model_dump_json()), merge=True)

    logger.info(f"Wrote simulation report {report.report_id}")
    return report.report_id


# =============================================================================
# TOOL: Write agent trace to Firestore
# =============================================================================


def write_trace(trace: AgentTrace) -> None:
    """Write execution trace to agent_traces collection."""
    db = get_db()

    if not trace.trace_id:
        trace.trace_id = str(uuid.uuid4())
    if not trace.created_at:
        trace.created_at = now_utc()

    doc = db.collection("agent_traces").document(trace.trace_id)
    doc.set(json.loads(trace.model_dump_json()), merge=True)

    logger.info(f"Wrote trace {trace.trace_id}")


# =============================================================================
# TOOL: Determine which mock endpoints to dispatch based on plan
# =============================================================================


def determine_dispatches(
    plan_data: dict[str, Any],
    event_data: dict[str, Any],
) -> list[dict[str, Any]]:
    """
    Analyze plan's system_actions and event metadata to determine
    which mock endpoints should receive dispatches.

    Returns a list of {endpoint_key, payload} dicts.
    """
    dispatches_to_send = []
    system_actions = plan_data.get("system_actions", [])
    event_id = plan_data.get("event_id", "")
    severity = event_data.get("severity", 0)
    crisis_type = event_data.get("type", event_data.get("crisis_type", "urban_flood"))
    city = event_data.get("city", "Islamabad")

    for action in system_actions:
        action_type = (
            action.get("type", "")
            if isinstance(action, dict)
            else getattr(action, "type", "")
        )
        action_payload = (
            action.get("payload", {})
            if isinstance(action, dict)
            else getattr(action, "payload", {})
        )
        action_urgency = (
            action.get("urgency", "med")
            if isinstance(action, dict)
            else getattr(action, "urgency", "med")
        )

        endpoint_key = SYSTEM_ACTION_ENDPOINT_MAP.get(action_type)
        if not endpoint_key:
            logger.warning(f"No endpoint mapping for system action type: {action_type}")
            continue

        # Build enriched payload for the mock endpoint
        enriched_payload = {
            "event_id": event_id,
            "severity": severity,
            "crisis_type": crisis_type,
            "city": city,
            "urgency": action_urgency,
            "system_action_type": action_type,
            "source": "mehfooz-simulation-agent",
            **action_payload,
        }

        dispatches_to_send.append({
            "endpoint_key": endpoint_key,
            "payload": enriched_payload,
        })

    # Always dispatch PDMA for severity >= 3 events (even if not in system_actions)
    pdma_already = any(d["endpoint_key"] == "pdma_dispatch" for d in dispatches_to_send)
    if severity >= 3 and not pdma_already:
        dispatches_to_send.append({
            "endpoint_key": "pdma_dispatch",
            "payload": {
                "event_id": event_id,
                "severity": severity,
                "crisis_type": crisis_type,
                "city": city,
                "urgency": "high" if severity >= 4 else "med",
                "source": "mehfooz-simulation-agent",
                "reason": "auto_dispatch_severity_3_plus",
            },
        })

    # Always dispatch Rescue 1122 for severity >= 4
    rescue_already = any(d["endpoint_key"] == "rescue_1122" for d in dispatches_to_send)
    if severity >= 4 and not rescue_already:
        dispatches_to_send.append({
            "endpoint_key": "rescue_1122",
            "payload": {
                "event_id": event_id,
                "severity": severity,
                "crisis_type": crisis_type,
                "city": city,
                "urgency": "sos" if severity >= 5 else "high",
                "source": "mehfooz-simulation-agent",
                "reason": "auto_dispatch_severity_4_plus",
            },
        })

    logger.info(f"Determined {len(dispatches_to_send)} dispatches to send")
    return dispatches_to_send
