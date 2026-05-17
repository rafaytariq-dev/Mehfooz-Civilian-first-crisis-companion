"""
Simulation Agent — main agent logic.

M5 executes Plan actions against mock endpoints:
1. Read plan from Firestore (produced by M4).
2. Read associated event for context (severity, crisis_type).
3. Dispatch to mock authority endpoints (PDMA, Rescue 1122, Traffic, SMS).
4. Queue push notifications for M6 Comms agent.
5. Compute estimated impact (transparent heuristics).
6. Generate English + Urdu summary card text.
7. Write SimulationReport to Firestore.
8. Write trace doc to agent_traces.

HARD RULES:
- NEVER call real authority APIs even if credentials are available.
- Every dispatch goes to a mock endpoint only.
- Label all impact estimates as "estimates".
- Write an agent_traces doc for every run.
"""

from __future__ import annotations

import logging
import time
import uuid
from datetime import datetime, timezone
from typing import Any

from config import AGENT_NAME
from models import (
    AgentTrace,
    DispatchRecord,
    EstimatedImpact,
    NotificationCounts,
    SimulationReport,
    SimulationRequest,
    SimulationResult,
    ToolCall,
)
from tools import (
    count_notifications,
    count_routes_flagged,
    determine_dispatches,
    estimate_impact,
    generate_summary,
    make_tool_call,
    now_utc,
    post_to_mock,
    queue_push,
    read_event,
    read_plan,
    write_simulation_report,
    write_trace,
)

logger = logging.getLogger("simulation.agent")


async def run_simulation(req: SimulationRequest) -> SimulationResult:
    """
    Main simulation agent entry point.

    Steps:
    1. Read plan from Firestore.
    2. Read event for severity/context.
    3. Execute dispatches to mock endpoints.
    4. Queue push notifications for affected users.
    5. Compute impact estimates.
    6. Generate summary card text.
    7. Write SimulationReport.
    8. Write trace.
    """

    report_id = f"simrpt_{uuid.uuid4().hex[:12]}"
    trace = AgentTrace(
        report_id=report_id,
        plan_id=req.plan_id,
        step="start",
        created_at=now_utc(),
    )
    tools_called: list[ToolCall] = []
    start_time = time.time()

    try:
        # =====================================================================
        # STEP 1: Read plan
        # =====================================================================
        trace.step = "read_plan"
        logger.info(f"Reading plan {req.plan_id}")

        read_plan_call = make_tool_call("read_plan", read_plan, plan_id=req.plan_id)
        tools_called.append(read_plan_call)

        if not isinstance(read_plan_call.result, dict):
            raise ValueError(f"Failed to read plan: {read_plan_call.result}")

        plan_data = read_plan_call.result
        event_id = plan_data.get("event_id", "")
        user_actions = plan_data.get("user_actions", {})
        system_actions = plan_data.get("system_actions", [])

        trace.event_id = event_id
        trace.input_summary = (
            f"Plan: {req.plan_id}, event={event_id}, "
            f"{len(system_actions)} system actions, "
            f"{len(user_actions)} user actions"
        )

        # =====================================================================
        # STEP 2: Read event for severity context
        # =====================================================================
        trace.step = "read_event"
        logger.info(f"Reading event {event_id}")

        read_event_call = make_tool_call("read_event", read_event, event_id=event_id)
        tools_called.append(read_event_call)

        if isinstance(read_event_call.result, dict):
            event_data = read_event_call.result
        else:
            logger.warning(f"Could not read event {event_id}; using defaults")
            event_data = {
                "event_id": event_id,
                "severity": 3,
                "type": "urban_flood",
                "city": "Islamabad",
            }

        severity = int(event_data.get("severity", 3))

        # =====================================================================
        # STEP 3: Execute dispatches to mock endpoints
        # =====================================================================
        trace.step = "execute_dispatches"
        logger.info("Determining and executing mock dispatches")

        determine_call = make_tool_call(
            "determine_dispatches",
            determine_dispatches,
            plan_data=plan_data,
            event_data=event_data,
        )
        tools_called.append(determine_call)

        dispatches_to_send = (
            determine_call.result
            if isinstance(determine_call.result, list)
            else []
        )

        dispatch_records: list[DispatchRecord] = []
        for dispatch_spec in dispatches_to_send:
            endpoint_key = dispatch_spec.get("endpoint_key", "")
            payload = dispatch_spec.get("payload", {})

            dispatch_call = make_tool_call(
                f"post_to_mock_{endpoint_key}",
                post_to_mock,
                endpoint_key=endpoint_key,
                payload=payload,
            )
            tools_called.append(dispatch_call)

            if isinstance(dispatch_call.result, DispatchRecord):
                dispatch_records.append(dispatch_call.result)

        logger.info(f"Dispatched {len(dispatch_records)} mock tickets")

        # =====================================================================
        # STEP 4: Queue push notifications for affected users
        # =====================================================================
        trace.step = "queue_notifications"
        logger.info(f"Queuing push notifications for {len(user_actions)} users")

        push_count = 0
        for uid, action in user_actions.items():
            verb = (
                action.get("verb", "AVOID_AREA")
                if isinstance(action, dict)
                else getattr(action, "verb", "AVOID_AREA")
            )
            urgency = (
                action.get("urgency", "low")
                if isinstance(action, dict)
                else getattr(action, "urgency", "low")
            )
            msg_en = (
                action.get("message_en", "")
                if isinstance(action, dict)
                else getattr(action, "message_en", "")
            )
            msg_ur = (
                action.get("message_ur", "")
                if isinstance(action, dict)
                else getattr(action, "message_ur", "")
            )

            if not req.dry_run:
                push_call = make_tool_call(
                    "queue_push",
                    queue_push,
                    user_id=uid,
                    event_id=event_id,
                    plan_id=req.plan_id,
                    verb=verb,
                    urgency=urgency,
                    message_en=msg_en,
                    message_ur=msg_ur,
                )
                tools_called.append(push_call)

            push_count += 1

        logger.info(f"Queued {push_count} push notifications")

        # =====================================================================
        # STEP 5: Compute counts and impact estimates
        # =====================================================================
        trace.step = "compute_impact"

        notifications = count_notifications(user_actions)
        routes_flagged = count_routes_flagged(system_actions)
        impact = estimate_impact(user_actions, severity)

        logger.info(
            f"Notifications: {notifications.model_dump()}, "
            f"Routes flagged: {routes_flagged}, "
            f"Impact: {impact.model_dump()}"
        )

        # =====================================================================
        # STEP 6: Generate summary card text
        # =====================================================================
        trace.step = "generate_summary"

        summary_en, summary_ur = generate_summary(
            notifications, routes_flagged, dispatch_records, impact
        )

        logger.info(f"Summary EN: {summary_en}")
        logger.info(f"Summary UR: {summary_ur}")

        # =====================================================================
        # STEP 7: Build and write SimulationReport
        # =====================================================================
        trace.step = "write_report"

        report = SimulationReport(
            report_id=report_id,
            plan_id=req.plan_id,
            event_id=event_id,
            executed_at=now_utc(),
            dispatches=dispatch_records,
            notifications_queued=notifications,
            routes_flagged=routes_flagged,
            estimated_impact=impact,
            summary_en=summary_en,
            summary_ur=summary_ur,
        )

        if not req.dry_run:
            write_report_call = make_tool_call(
                "write_simulation_report",
                write_simulation_report,
                report=report,
            )
            tools_called.append(write_report_call)
            logger.info(f"Wrote simulation report {report_id}")

        # =====================================================================
        # STEP 8: Write trace
        # =====================================================================
        trace.step = "write_trace"
        trace.output_summary = (
            f"Report: {report_id}, "
            f"dispatches={len(dispatch_records)}, "
            f"notifications={notifications.total_users}, "
            f"routes_flagged={routes_flagged}, "
            f"impact={{diverted={impact.users_diverted}, "
            f"congestion={impact.congestion_reduction_min:.1f}min}}"
        )
        trace.reasoning = (
            "Executed plan against mock endpoints per M5 spec. "
            f"Dispatched to {len(dispatch_records)} authorities. "
            f"Queued {notifications.total_users} push notifications "
            f"(sos={notifications.sos}, high={notifications.high}, "
            f"med={notifications.med}, low={notifications.low}). "
            f"Impact estimates are heuristic-based, labeled as such."
        )
        trace.tools_called = tools_called
        trace.duration_ms = int((time.time() - start_time) * 1000)

        if not req.dry_run:
            write_trace(trace)

        # =====================================================================
        # Return result
        # =====================================================================
        return SimulationResult(
            report_id=report_id,
            plan_id=req.plan_id,
            event_id=event_id,
            dispatches_sent=len(dispatch_records),
            notifications_queued=notifications.total_users,
            routes_flagged=routes_flagged,
            summary_en=summary_en,
            duration_ms=trace.duration_ms,
            errors=[],
        )

    except Exception as e:
        logger.exception(f"Simulation failed: {e}")
        trace.duration_ms = int((time.time() - start_time) * 1000)
        trace.reasoning = f"Simulation failed: {e}"
        trace.tools_called = tools_called

        if not req.dry_run:
            try:
                write_trace(trace)
            except Exception as trace_err:
                logger.error(f"Failed to write error trace: {trace_err}")

        return SimulationResult(
            plan_id=req.plan_id,
            event_id=trace.event_id or "",
            duration_ms=trace.duration_ms,
            errors=[str(e)],
        )


async def run_test_simulation() -> dict[str, Any]:
    """
    Local smoke test without Firestore or mock endpoints.
    Demonstrates the simulation pipeline with mock data inline.
    """
    logger.info("Running test simulation (inline mock data)")

    # ─── Mock plan data (as if produced by M4) ───
    mock_plan = {
        "plan_id": "test-plan-001",
        "event_id": "test-event-001",
        "system_actions": [
            {
                "type": "notify_helpline",
                "target": "rescue_1122_ict",
                "payload": {
                    "helpline_name": "Rescue 1122 ICT",
                    "phone": "1122",
                    "crisis_type": "urban_flood",
                    "city": "Islamabad",
                    "severity": 4,
                },
                "urgency": "high",
            },
            {
                "type": "flag_route",
                "target": "major_roads_in_polygon",
                "payload": {
                    "severity": 4,
                    "reason": "Flooding detected; routes unsafe.",
                },
                "urgency": "high",
            },
            {
                "type": "broadcast_zone",
                "target": "radius_5km_Islamabad",
                "payload": {
                    "radius_m": 5000,
                    "message": "ALERT: Level 4 urban_flood event. Seek shelter.",
                    "severity": 4,
                },
                "urgency": "sos",
            },
        ],
        "user_actions": {
            "u_001": {
                "verb": "EVACUATE",
                "urgency": "sos",
                "message_en": "EVACUATE: Level 4 flood. Seek shelter at Shifa Hospital.",
                "message_ur": "فوری نکلیں: سیلاب۔ شفا ہسپتال جائیں۔",
            },
            "u_002": {
                "verb": "REROUTE",
                "urgency": "high",
                "message_en": "REROUTE: Flooding on IJP Road. Use alternate.",
                "message_ur": "راستہ بدلیں: IJP روڈ بند ہے۔",
            },
            "u_003": {
                "verb": "AVOID_AREA",
                "urgency": "med",
                "message_en": "AVOID: Crisis 1km away. Avoid area.",
                "message_ur": "علاقہ سے بچیں: سنگین صورتحال۔",
            },
            "u_004": {
                "verb": "CHECK_ON_FAMILY",
                "urgency": "med",
                "message_en": "CHECK ON FAMILY: Contact in affected area.",
                "message_ur": "خاندان سے رابطہ کریں۔",
            },
            "u_005": {
                "verb": "EVACUATE",
                "urgency": "sos",
                "message_en": "EVACUATE: Level 4 flood. Seek shelter at PIMS.",
                "message_ur": "فوری نکلیں: PIMS جائیں۔",
            },
        },
    }

    severity = 4

    # ─── Compute everything locally ───
    notifications = count_notifications(mock_plan["user_actions"])
    routes_flagged = count_routes_flagged(mock_plan["system_actions"])
    impact = estimate_impact(mock_plan["user_actions"], severity)

    # ─── Build mock dispatch records (without hitting real endpoints) ───
    mock_dispatches = [
        DispatchRecord(
            authority="PDMA-Punjab",
            ticket_id=f"PDMA-{int(time.time())}",
            endpoint="(test mode — no endpoint called)",
            payload_summary="PDMA-Punjab: event=test-event-001, severity=4, crisis=urban_flood",
            status="queued",
            response_time_ms=0,
        ),
        DispatchRecord(
            authority="Rescue-1122-ICT",
            ticket_id=f"RES1122-{int(time.time())}",
            endpoint="(test mode — no endpoint called)",
            payload_summary="Rescue-1122-ICT: event=test-event-001, severity=4",
            status="queued",
            response_time_ms=0,
        ),
    ]

    summary_en, summary_ur = generate_summary(
        notifications, routes_flagged, mock_dispatches, impact
    )

    return {
        "status": "ok",
        "test": "simulation",
        "report_id": f"test_simrpt_{uuid.uuid4().hex[:8]}",
        "plan_id": mock_plan["plan_id"],
        "event_id": mock_plan["event_id"],
        "dispatches": [d.model_dump() for d in mock_dispatches],
        "notifications": notifications.model_dump(),
        "routes_flagged": routes_flagged,
        "estimated_impact": impact.model_dump(),
        "summary_en": summary_en,
        "summary_ur": summary_ur,
        "note": "Test mode — no Firestore or mock endpoints were called.",
    }
