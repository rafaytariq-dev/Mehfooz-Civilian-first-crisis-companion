"""
Orchestrator — Core loop.

Sequential chain: ingestion → detection → planning → simulation → comms
with a feedback loop when detection confidence is low.
"""
from __future__ import annotations

import logging
import time
import uuid
from datetime import datetime, timezone

import httpx

from config import (
    CONFIDENCE_THRESHOLD,
    DETECTION_AGENT_URL,
    DETECTION_RUN_PATH,
    HTTP_TIMEOUT_SECONDS,
    INGESTION_AGENT_URL,
    INGESTION_REPORT_PATH,
    INGESTION_SOCIAL_PATH,
    MAX_DETECTION_RETRIES,
    MAX_TOTAL_CYCLES,
    MIN_MODALITY_COUNT,
    PLANNING_AGENT_URL,
    PLANNING_RUN_PATH,
    PROJECT_ID,
    SIMULATION_AGENT_URL,
    SIMULATION_RUN_PATH,
)
from models import AgentTrace, ChainOutcome, OrchestrateRequest, OrchestrateResult, ToolCall

logger = logging.getLogger("orchestrator.loop")

# ─── Firestore (lazy) ───
_db = None

def _get_db():
    global _db
    if _db is None:
        from google.cloud import firestore
        _db = firestore.AsyncClient(project=PROJECT_ID)
    return _db


async def _write_trace(trace: AgentTrace) -> str:
    """Write an agent trace to Firestore. Returns trace_id."""
    try:
        db = _get_db()
        trace.created_at = datetime.now(timezone.utc)
        await db.collection("agent_traces").document(trace.trace_id).set(
            trace.model_dump(mode="json")
        )
    except Exception as e:
        logger.error(f"[_write_trace] Failed: {e}")
    return trace.trace_id


# ─── HTTP helpers ───

async def _post(client: httpx.AsyncClient, url: str, payload: dict) -> dict:
    """POST JSON to a sub-agent and return parsed response."""
    resp = await client.post(url, json=payload, timeout=HTTP_TIMEOUT_SECONDS)
    resp.raise_for_status()
    return resp.json()


# ─── Sub-agent callers ───

async def _call_ingestion_report(
    client: httpx.AsyncClient, trigger: OrchestrateRequest
) -> tuple[dict, ToolCall]:
    """Call ingestion agent to process a report."""
    t0 = time.monotonic()
    url = f"{INGESTION_AGENT_URL}{INGESTION_REPORT_PATH}"
    payload = {
        "report_id": trigger.report_id,
        "user_id": trigger.user_id,
        "text_raw": trigger.text_raw,
        "voice_url": trigger.voice_url,
        "photo_urls": trigger.photo_urls,
        "location": trigger.location.model_dump(),
        "geo_accuracy_m": trigger.geo_accuracy_m,
        "crisis_type_user": trigger.crisis_type_user,
        "severity_user": trigger.severity_user,
        "created_at": trigger.created_at,
    }
    result = await _post(client, url, payload)
    dur = int((time.monotonic() - t0) * 1000)
    tc = ToolCall(name="call_ingestion_report", args={"report_id": trigger.report_id}, result=result, duration_ms=dur)
    return result, tc


async def _call_ingestion_social(
    client: httpx.AsyncClient, city: str | None = None
) -> tuple[dict, ToolCall]:
    """Call ingestion agent for social enrichment (feedback loop)."""
    t0 = time.monotonic()
    url = f"{INGESTION_AGENT_URL}{INGESTION_SOCIAL_PATH}"
    params = {}
    if city:
        params["city"] = city
    resp = await client.post(url, params=params, timeout=HTTP_TIMEOUT_SECONDS)
    resp.raise_for_status()
    result = resp.json()
    dur = int((time.monotonic() - t0) * 1000)
    tc = ToolCall(name="call_ingestion_social", args={"city": city, "mode": "social_only"}, result=result, duration_ms=dur)
    return result, tc


async def _call_detection(
    client: httpx.AsyncClient, city: str | None = None, minutes: int = 60
) -> tuple[dict, ToolCall]:
    """Call detection agent."""
    t0 = time.monotonic()
    url = f"{DETECTION_AGENT_URL}{DETECTION_RUN_PATH}"
    payload = {"city": city, "minutes": minutes, "force_create": True}
    result = await _post(client, url, payload)
    dur = int((time.monotonic() - t0) * 1000)
    tc = ToolCall(name="call_detection", args={"city": city, "minutes": minutes}, result=result, duration_ms=dur)
    return result, tc


async def _call_planning(
    client: httpx.AsyncClient, event_id: str
) -> tuple[dict, ToolCall]:
    """Call planning agent."""
    t0 = time.monotonic()
    url = f"{PLANNING_AGENT_URL}{PLANNING_RUN_PATH}"
    payload = {"event_id": event_id}
    result = await _post(client, url, payload)
    dur = int((time.monotonic() - t0) * 1000)
    tc = ToolCall(name="call_planning", args={"event_id": event_id}, result=result, duration_ms=dur)
    return result, tc


async def _call_simulation(
    client: httpx.AsyncClient, plan_id: str
) -> tuple[dict, ToolCall]:
    """Call simulation agent."""
    t0 = time.monotonic()
    url = f"{SIMULATION_AGENT_URL}{SIMULATION_RUN_PATH}"
    payload = {"plan_id": plan_id}
    result = await _post(client, url, payload)
    dur = int((time.monotonic() - t0) * 1000)
    tc = ToolCall(name="call_simulation", args={"plan_id": plan_id}, result=result, duration_ms=dur)
    return result, tc


# ─── Helpers ───

async def _fetch_event_details(event_ids: list[str]) -> list[dict]:
    """Read event docs from Firestore to check confidence/modality."""
    db = _get_db()
    events = []
    for eid in event_ids:
        doc = await db.collection("events").document(eid).get()
        if doc.exists:
            events.append({"event_id": eid, **doc.to_dict()})
    return events


async def _fetch_plan(plan_id: str) -> dict:
    """Read a plan doc from Firestore."""
    db = _get_db()
    doc = await db.collection("plans").document(plan_id).get()
    if doc.exists:
        return {"plan_id": plan_id, **doc.to_dict()}
    return {}


# ═══════════════════════════════════════════════════════════════
# MAIN ORCHESTRATION LOOP
# ═══════════════════════════════════════════════════════════════

async def orchestrate(trigger: OrchestrateRequest) -> OrchestrateResult:
    """Run the full orchestration chain.

    Sequential: ingestion → detection (with retry loop) → planning →
    simulation → comms.

    Feedback loop: if detection returns candidates with
    confidence < 0.6 AND modality_count < 2, re-invoke ingestion
    with mode='social_only' and retry detection. Max 2 retries.

    Termination: stop after simulation_report is written, OR after
    3 ingestion-detection cycles without promotion to verified.
    """
    t0 = time.monotonic()
    result = OrchestrateResult()
    all_tool_calls: list[ToolCall] = []
    city = trigger.city or "Islamabad"

    logger.info(f"[orchestrate] START report={trigger.report_id} city={city}")

    async with httpx.AsyncClient() as client:
        # ── Step 1: Ingest the report ──
        try:
            ing_result, ing_tc = await _call_ingestion_report(client, trigger)
            all_tool_calls.append(ing_tc)

            trace_id = await _write_trace(AgentTrace(
                trace_id=f"trace-orch-ingest-{uuid.uuid4().hex[:8]}",
                report_id=trigger.report_id,
                agent="orchestrator",
                step="call_ingestion",
                input_summary=f"Report {trigger.report_id}: '{trigger.text_raw[:80]}'",
                output_summary=f"Ingestion complete: {ing_result}",
                reasoning="Initial ingestion of citizen report — normalize text, verify photos.",
                tools_called=[ing_tc],
                duration_ms=ing_tc.duration_ms,
            ))
            result.trace_ids.append(trace_id)
        except Exception as e:
            logger.error(f"[orchestrate] Ingestion failed: {e}")
            result.errors.append(f"ingestion_failed: {e}")
            result.outcome = ChainOutcome.error
            result.duration_ms = int((time.monotonic() - t0) * 1000)
            return result

        # ── Step 2: Detection with feedback loop ──
        retries = 0
        total_cycles = 0
        verified_event_ids: list[str] = []
        detection_result = {}

        while total_cycles < MAX_TOTAL_CYCLES:
            total_cycles += 1
            result.total_cycles = total_cycles

            try:
                detection_result, det_tc = await _call_detection(client, city=city)
                all_tool_calls.append(det_tc)
            except Exception as e:
                logger.error(f"[orchestrate] Detection failed: {e}")
                result.errors.append(f"detection_failed: {e}")
                break

            event_ids = detection_result.get("event_ids", [])
            verified_count = detection_result.get("verified_events", 0)
            candidate_count = detection_result.get("candidate_events", 0)

            # Write detection trace
            trace_id = await _write_trace(AgentTrace(
                trace_id=f"trace-orch-detect-{uuid.uuid4().hex[:8]}",
                report_id=trigger.report_id,
                agent="orchestrator",
                step=f"call_detection (cycle {total_cycles})",
                input_summary=f"Detection for city={city}, cycle {total_cycles}",
                output_summary=(
                    f"Events: {len(event_ids)} total, "
                    f"{verified_count} verified, {candidate_count} candidates"
                ),
                reasoning=(
                    f"Ran DBSCAN clustering + multi-modal corroboration. "
                    f"Found {verified_count} verified and {candidate_count} candidate events."
                ),
                tools_called=[det_tc],
                duration_ms=det_tc.duration_ms,
            ))
            result.trace_ids.append(trace_id)

            if verified_count > 0:
                # We have verified events — proceed to planning
                verified_event_ids = event_ids
                break

            if candidate_count == 0:
                # No events at all — nothing to do
                logger.info("[orchestrate] No events found, terminating.")
                break

            # We have candidates but none verified — check if retry is warranted
            if retries >= MAX_DETECTION_RETRIES:
                logger.info(f"[orchestrate] Max retries ({MAX_DETECTION_RETRIES}) reached.")
                break

            # Check candidate confidence and modality count
            should_retry = False
            if event_ids:
                events = await _fetch_event_details(event_ids)
                for ev in events:
                    conf = ev.get("confidence", 0)
                    # Count modalities from contributing_signals
                    cs = ev.get("contributing_signals", {})
                    modality_count = sum(1 for k in ["reports", "weather", "traffic", "social"]
                                         if cs.get(k))
                    if conf < CONFIDENCE_THRESHOLD and modality_count < MIN_MODALITY_COUNT:
                        should_retry = True
                        break

            if not should_retry:
                logger.info("[orchestrate] Candidates don't meet retry criteria, stopping.")
                break

            # ── Feedback loop: re-invoke ingestion for more social data ──
            retries += 1
            result.feedback_loops = retries
            logger.info(
                f"[orchestrate] Feedback loop #{retries}: "
                f"re-invoking ingestion (social_only) for more corroboration"
            )

            try:
                social_result, social_tc = await _call_ingestion_social(client, city=city)
                all_tool_calls.append(social_tc)

                trace_id = await _write_trace(AgentTrace(
                    trace_id=f"trace-orch-social-{uuid.uuid4().hex[:8]}",
                    report_id=trigger.report_id,
                    agent="orchestrator",
                    step=f"feedback_loop_ingestion (retry {retries})",
                    input_summary=(
                        f"Re-invoking ingestion with mode=social_only for city={city}, "
                        f"+5min window, retry {retries}/{MAX_DETECTION_RETRIES}"
                    ),
                    output_summary=f"Social enrichment: {social_result}",
                    reasoning=(
                        f"Detection returned candidates with confidence < {CONFIDENCE_THRESHOLD} "
                        f"and modality_count < {MIN_MODALITY_COUNT}. "
                        f"Re-invoking ingestion to scrape social signals for corroboration."
                    ),
                    tools_called=[social_tc],
                    duration_ms=social_tc.duration_ms,
                ))
                result.trace_ids.append(trace_id)
            except Exception as e:
                logger.error(f"[orchestrate] Social re-ingestion failed: {e}")
                result.errors.append(f"social_reingestion_failed: {e}")
                break

        # ── Check if we got verified events ──
        if not verified_event_ids:
            result.outcome = (
                ChainOutcome.max_retries_exhausted
                if retries >= MAX_DETECTION_RETRIES
                else ChainOutcome.no_event
            )
            result.duration_ms = int((time.monotonic() - t0) * 1000)

            await _write_trace(AgentTrace(
                trace_id=f"trace-orch-term-{uuid.uuid4().hex[:8]}",
                report_id=trigger.report_id,
                agent="orchestrator",
                step="termination",
                input_summary=f"{total_cycles} cycles, {retries} retries",
                output_summary=f"Terminated: {result.outcome.value}",
                reasoning=(
                    f"After {total_cycles} ingestion-detection cycles and {retries} retries, "
                    f"no event was promoted to verified status."
                ),
                tools_called=[],
                duration_ms=int((time.monotonic() - t0) * 1000),
            ))

            logger.info(f"[orchestrate] END: {result.outcome.value} dur={result.duration_ms}ms")
            return result

        result.event_ids = verified_event_ids

        # ── Steps 3–5: For each verified event: plan → simulate → comms ──
        for event_id in verified_event_ids:
            try:
                await _process_verified_event(
                    client=client,
                    event_id=event_id,
                    trigger=trigger,
                    result=result,
                    all_tool_calls=all_tool_calls,
                )
            except Exception as e:
                logger.error(f"[orchestrate] Failed processing event {event_id}: {e}")
                result.errors.append(f"event_processing_failed:{event_id}:{e}")

    result.outcome = ChainOutcome.completed
    result.duration_ms = int((time.monotonic() - t0) * 1000)

    logger.info(
        f"[orchestrate] END: completed. events={len(result.event_ids)} "
        f"plans={len(result.plan_ids)} notifications={result.notifications_sent} "
        f"feedback_loops={result.feedback_loops} dur={result.duration_ms}ms"
    )
    return result


async def _process_verified_event(
    client: httpx.AsyncClient,
    event_id: str,
    trigger: OrchestrateRequest,
    result: OrchestrateResult,
    all_tool_calls: list[ToolCall],
) -> None:
    """Run planning → simulation → comms for one verified event."""

    # ── Step 3: Planning ──
    plan_result, plan_tc = await _call_planning(client, event_id)
    all_tool_calls.append(plan_tc)
    plan_id = plan_result.get("plan_id", "")
    result.plan_ids.append(plan_id)

    trace_id = await _write_trace(AgentTrace(
        trace_id=f"trace-orch-plan-{uuid.uuid4().hex[:8]}",
        event_id=event_id,
        plan_id=plan_id,
        report_id=trigger.report_id,
        agent="orchestrator",
        step="call_planning",
        input_summary=f"Planning for event {event_id}",
        output_summary=(
            f"Plan {plan_id}: {plan_result.get('system_actions_count', 0)} system actions, "
            f"{plan_result.get('user_actions_count', 0)} user actions"
        ),
        reasoning="Converting verified event into system + per-user action plans.",
        tools_called=[plan_tc],
        duration_ms=plan_tc.duration_ms,
    ))
    result.trace_ids.append(trace_id)

    # ── Step 4: Simulation ──
    sim_result, sim_tc = await _call_simulation(client, plan_id)
    all_tool_calls.append(sim_tc)
    report_id = sim_result.get("report_id", "")
    result.simulation_report_ids.append(report_id)

    trace_id = await _write_trace(AgentTrace(
        trace_id=f"trace-orch-sim-{uuid.uuid4().hex[:8]}",
        event_id=event_id,
        plan_id=plan_id,
        report_id=trigger.report_id,
        agent="orchestrator",
        step="call_simulation",
        input_summary=f"Simulation for plan {plan_id}",
        output_summary=(
            f"Report {report_id}: {sim_result.get('dispatches_sent', 0)} dispatches, "
            f"{sim_result.get('notifications_queued', 0)} notifications queued"
        ),
        reasoning="Executing plan against mock authority endpoints and producing audit report.",
        tools_called=[sim_tc],
        duration_ms=sim_tc.duration_ms,
    ))
    result.trace_ids.append(trace_id)

    # ── Step 5: Comms ──
    from comms import process_comms

    plan_doc = await _fetch_plan(plan_id)
    comms_result = await process_comms(
        plan=plan_doc,
        event_id=event_id,
    )

    result.notifications_sent += comms_result.notifications_sent
    result.sms_enqueued += comms_result.sms_enqueued
    result.errors.extend(comms_result.errors)

    trace_id = await _write_trace(AgentTrace(
        trace_id=f"trace-orch-comms-{uuid.uuid4().hex[:8]}",
        event_id=event_id,
        plan_id=plan_id,
        report_id=trigger.report_id,
        agent="orchestrator",
        step="call_comms",
        input_summary=f"Comms for plan {plan_id} ({len(plan_doc.get('user_actions', {}))} users)",
        output_summary=(
            f"Sent {comms_result.notifications_sent} FCM, "
            f"enqueued {comms_result.sms_enqueued} SMS"
        ),
        reasoning="Rendering localized messages and dispatching FCM notifications with urgency tiering.",
        tools_called=[],
        duration_ms=0,
    ))
    result.trace_ids.append(trace_id)
