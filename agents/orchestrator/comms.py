"""
Comms Agent — Flow coordinator.

Processes a plan's user_actions: for each user, render the notification
in their language, send via FCM with the correct urgency channel,
and enqueue SMS fallback for SOS-tier or FCM-inactive users.
"""
from __future__ import annotations

import logging
import time
import uuid
from datetime import datetime, timezone

from config import PROJECT_ID
from comms_tools import enqueue_sms_fallback, render_message, send_fcm
from models import (
    AgentTrace,
    CommsResult,
    ToolCall,
    UserActionPayload,
    UserProfile,
)
from notification_channels import get_channel_config

logger = logging.getLogger("orchestrator.comms")


# ─── Firestore (lazy) ───

_db = None


def _get_db():
    global _db
    if _db is None:
        from google.cloud import firestore
        _db = firestore.AsyncClient(project=PROJECT_ID)
    return _db


# ─── Trace writer ───

async def _write_trace(trace: AgentTrace) -> None:
    """Write an agent trace to Firestore."""
    try:
        db = _get_db()
        trace.created_at = datetime.now(timezone.utc)
        await db.collection("agent_traces").document(trace.trace_id).set(
            trace.model_dump(mode="json")
        )
    except Exception as e:
        logger.error(f"[_write_trace] Failed to write trace {trace.trace_id}: {e}")


# ─── Main comms flow ───


async def process_comms(
    plan: dict,
    simulation_report: dict | None = None,
    event_id: str = "",
) -> CommsResult:
    """Process communications for a plan.

    For each user in the plan's user_actions:
      1. Fetch user profile (for language, FCM token, phone)
      2. Render the message in the user's language
      3. Send FCM push notification with correct urgency channel
      4. If SOS tier or FCM inactive → enqueue SMS fallback
      5. Write comms trace

    Args:
        plan: The plan dict (from Firestore or planning agent response).
              Must have 'plan_id', 'event_id', 'user_actions'.
        simulation_report: Optional simulation report for context.
        event_id: The event ID this plan is for.

    Returns:
        CommsResult with counts and errors.
    """
    t0 = time.monotonic()
    result = CommsResult()
    tool_calls: list[ToolCall] = []

    plan_id = plan.get("plan_id", "unknown")
    event_id = event_id or plan.get("event_id", "")
    user_actions: dict = plan.get("user_actions", {})

    logger.info(
        f"[process_comms] Starting for plan={plan_id} "
        f"event={event_id} users={len(user_actions)}"
    )

    if not user_actions:
        logger.info("[process_comms] No user actions in plan, skipping comms.")
        return result

    db = _get_db()

    for user_id, action_data in user_actions.items():
        try:
            await _process_single_user(
                db=db,
                user_id=user_id,
                action_data=action_data,
                plan_id=plan_id,
                event_id=event_id,
                result=result,
                tool_calls=tool_calls,
            )
        except Exception as e:
            error_msg = f"Comms failed for user {user_id}: {e}"
            logger.error(f"[process_comms] {error_msg}")
            result.errors.append(error_msg)

    # Write comms trace
    total_dur = int((time.monotonic() - t0) * 1000)

    trace = AgentTrace(
        trace_id=f"trace-comms-{uuid.uuid4().hex[:8]}",
        event_id=event_id,
        plan_id=plan_id,
        agent="comms",
        step="process_comms",
        input_summary=(
            f"Plan {plan_id} with {len(user_actions)} user actions "
            f"for event {event_id}"
        ),
        output_summary=(
            f"Sent {result.notifications_sent} FCM notifications, "
            f"enqueued {result.sms_enqueued} SMS fallbacks. "
            f"Errors: {len(result.errors)}"
        ),
        reasoning=(
            f"Processed {len(user_actions)} users from plan. "
            f"Each user's notification was rendered in their preferred language "
            f"using Gemini Flash and sent via FCM with the urgency tier's channel config. "
            f"SOS-tier users and FCM-inactive users also received SMS fallback."
        ),
        tools_called=tool_calls,
        duration_ms=total_dur,
    )
    await _write_trace(trace)

    logger.info(
        f"[process_comms] Done: plan={plan_id} sent={result.notifications_sent} "
        f"sms={result.sms_enqueued} errors={len(result.errors)} dur={total_dur}ms"
    )

    return result


async def _process_single_user(
    db,
    user_id: str,
    action_data: dict,
    plan_id: str,
    event_id: str,
    result: CommsResult,
    tool_calls: list[ToolCall],
) -> None:
    """Process comms for a single user."""

    # 1. Fetch user profile
    tc_start = time.monotonic()
    user_doc = await db.collection("users").document(user_id).get()
    tc_dur = int((time.monotonic() - tc_start) * 1000)

    if not user_doc.exists:
        logger.warning(f"[comms] User {user_id} not found in Firestore")
        result.errors.append(f"user_not_found:{user_id}")
        return

    user_data = user_doc.to_dict()
    user = UserProfile(
        uid=user_id,
        display_name=user_data.get("display_name", ""),
        phone=user_data.get("phone", ""),
        language=user_data.get("language", "en"),
        fcm_token=user_data.get("fcm_token"),
        fcm_last_active=user_data.get("fcm_last_active"),
    )

    tool_calls.append(ToolCall(
        name="fetch_user_profile",
        args={"user_id": user_id},
        result={"language": user.language, "has_fcm": bool(user.fcm_token)},
        duration_ms=tc_dur,
    ))

    # Parse action
    action = UserActionPayload(
        verb=action_data.get("verb", "ALERT"),
        message_en=action_data.get("message_en", ""),
        message_ur=action_data.get("message_ur", ""),
        urgency=action_data.get("urgency", "med"),
        event_id=event_id,
        plan_id=plan_id,
    )

    # 2. Render the message
    tc_start = time.monotonic()
    rendered = await render_message(user, action)
    tc_dur = int((time.monotonic() - tc_start) * 1000)

    tool_calls.append(ToolCall(
        name="render_message",
        args={"user_id": user_id, "language": user.language, "verb": action.verb},
        result={"title": rendered.title, "body_len": len(rendered.body)},
        duration_ms=tc_dur,
    ))

    # 3. Send FCM
    channel = get_channel_config(action.urgency)
    data_payload = {
        "event_id": event_id,
        "plan_id": plan_id,
        "verb": action.verb,
        "urgency": action.urgency,
    }

    tc_start = time.monotonic()
    fcm_result = await send_fcm(
        user_id=user_id,
        title=rendered.title,
        body=rendered.body,
        data=data_payload,
        urgency=action.urgency,
        fcm_token=user.fcm_token,
    )
    tc_dur = int((time.monotonic() - tc_start) * 1000)

    tool_calls.append(ToolCall(
        name="send_fcm",
        args={
            "user_id": user_id,
            "urgency": action.urgency,
            "channel": channel.android_channel_id,
        },
        result={"success": fcm_result.success, "message_id": fcm_result.message_id},
        duration_ms=tc_dur,
    ))

    if fcm_result.success:
        result.notifications_sent += 1

    # 4. SMS fallback for SOS tier or if FCM failed/inactive
    if channel.sms_fallback or not fcm_result.success:
        tc_start = time.monotonic()
        sms_result = await enqueue_sms_fallback(
            phone=user.phone,
            body=rendered.body,
            user_id=user_id,
            event_id=event_id,
        )
        tc_dur = int((time.monotonic() - tc_start) * 1000)

        tool_calls.append(ToolCall(
            name="enqueue_sms_fallback",
            args={"user_id": user_id, "has_phone": bool(user.phone)},
            result={"enqueued": sms_result.enqueued, "reason": sms_result.reason},
            duration_ms=tc_dur,
        ))

        if sms_result.enqueued:
            result.sms_enqueued += 1
