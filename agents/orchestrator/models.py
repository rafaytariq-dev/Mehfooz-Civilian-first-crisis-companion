"""
Orchestrator + Comms Agent — Pydantic models.

Covers orchestration requests/results, comms payloads,
notification structures, and agent traces.
"""
from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any, Optional

from pydantic import BaseModel, Field


# ─────────────────────────────────────────────────────────────────────────────
# Enums
# ─────────────────────────────────────────────────────────────────────────────


class Urgency(str, Enum):
    """Notification urgency tiers from M6 spec."""
    low = "low"
    med = "med"
    high = "high"
    sos = "sos"


class ActionVerb(str, Enum):
    """Per-user action verbs from M4."""
    REROUTE = "REROUTE"
    EVACUATE = "EVACUATE"
    SHELTER_IN_PLACE = "SHELTER_IN_PLACE"
    CONTACT_HELPLINE = "CONTACT_HELPLINE"
    CHECK_ON_FAMILY = "CHECK_ON_FAMILY"
    AVOID_AREA = "AVOID_AREA"
    SEEK_COOLING = "SEEK_COOLING"
    SEEK_MEDICAL = "SEEK_MEDICAL"


class ChainOutcome(str, Enum):
    """Possible end states of an orchestration run."""
    completed = "completed"
    no_event = "no_event"
    max_retries_exhausted = "max_retries_exhausted"
    error = "error"


# ─────────────────────────────────────────────────────────────────────────────
# Geo
# ─────────────────────────────────────────────────────────────────────────────


class GeoLocation(BaseModel):
    latitude: float
    longitude: float


# ─────────────────────────────────────────────────────────────────────────────
# Orchestrate API — request / response
# ─────────────────────────────────────────────────────────────────────────────


class OrchestrateRequest(BaseModel):
    """Trigger payload for the orchestrator.

    Sent by the Cloud Function when a new report is created.
    """
    report_id: str
    user_id: str = ""
    text_raw: str = ""
    voice_url: Optional[str] = None
    photo_urls: list[str] = Field(default_factory=list)
    location: GeoLocation
    geo_accuracy_m: float = 50.0
    crisis_type_user: Optional[str] = None
    severity_user: Optional[int] = None
    created_at: Optional[str] = None
    # Optional: restrict detection to a specific city
    city: Optional[str] = None
    # Optional: override polygon for detection (used in retries)
    polygon: Optional[list[GeoLocation]] = None


class OrchestrateResult(BaseModel):
    """Summary of a full orchestration run."""
    outcome: ChainOutcome = ChainOutcome.no_event
    event_ids: list[str] = Field(default_factory=list)
    plan_ids: list[str] = Field(default_factory=list)
    simulation_report_ids: list[str] = Field(default_factory=list)
    notifications_sent: int = 0
    sms_enqueued: int = 0
    feedback_loops: int = 0
    total_cycles: int = 0
    duration_ms: int = 0
    errors: list[str] = Field(default_factory=list)
    trace_ids: list[str] = Field(default_factory=list)


# ─────────────────────────────────────────────────────────────────────────────
# Comms models
# ─────────────────────────────────────────────────────────────────────────────


class UserProfile(BaseModel):
    """Subset of user doc needed for comms."""
    uid: str
    display_name: str = ""
    phone: str = ""
    language: str = "en"  # 'ur' | 'en' | 'roman_ur'
    fcm_token: Optional[str] = None
    fcm_last_active: Optional[datetime] = None


class UserActionPayload(BaseModel):
    """Per-user action from the plan, used by comms."""
    verb: str
    message_en: str = ""
    message_ur: str = ""
    urgency: str = "med"
    event_id: str = ""
    plan_id: str = ""
    safe_spots: Optional[list[dict]] = None
    helpline: Optional[dict] = None


class RenderedMessage(BaseModel):
    """Output from render_message: final push-ready text."""
    title: str
    body: str
    language: str


class FCMResult(BaseModel):
    """Result of a send_fcm call."""
    success: bool = False
    message_id: Optional[str] = None
    error: Optional[str] = None


class SMSResult(BaseModel):
    """Result of enqueue_sms_fallback."""
    enqueued: bool = False
    reason: str = ""


class CommsResult(BaseModel):
    """Summary of comms processing for one plan."""
    notifications_sent: int = 0
    sms_enqueued: int = 0
    errors: list[str] = Field(default_factory=list)


# ─────────────────────────────────────────────────────────────────────────────
# Agent trace (consistent with M2–M5)
# ─────────────────────────────────────────────────────────────────────────────


class ToolCall(BaseModel):
    """Auditable tool invocation."""
    name: str
    args: dict[str, Any] = Field(default_factory=dict)
    result: Any = None
    duration_ms: int = 0


class AgentTrace(BaseModel):
    """Execution trace written to agent_traces collection."""
    trace_id: Optional[str] = None
    event_id: Optional[str] = None
    plan_id: Optional[str] = None
    report_id: Optional[str] = None
    agent: str = "orchestrator"
    step: str = ""
    input_summary: str = ""
    output_summary: str = ""
    reasoning: str = ""
    tools_called: list[ToolCall] = Field(default_factory=list)
    duration_ms: int = 0
    created_at: Optional[datetime] = None
