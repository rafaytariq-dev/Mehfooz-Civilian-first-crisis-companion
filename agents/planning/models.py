"""
Planning Agent — Pydantic models.

M4 converts Event → Plan (system actions + per-user actions).
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any, Optional

from pydantic import BaseModel, Field


class ActionVerb(str, Enum):
    """Per-user action recommendation."""
    REROUTE = "REROUTE"
    EVACUATE = "EVACUATE"
    SHELTER_IN_PLACE = "SHELTER_IN_PLACE"
    CONTACT_HELPLINE = "CONTACT_HELPLINE"
    CHECK_ON_FAMILY = "CHECK_ON_FAMILY"
    AVOID_AREA = "AVOID_AREA"
    SEEK_COOLING = "SEEK_COOLING"
    SEEK_MEDICAL = "SEEK_MEDICAL"


class Urgency(str, Enum):
    """Action urgency level."""
    low = "low"
    med = "med"
    high = "high"
    sos = "sos"


class SystemActionType(str, Enum):
    """System-level actions."""
    notify_helpline = "notify_helpline"
    flag_route = "flag_route"
    broadcast_zone = "broadcast_zone"


class GeoLocation(BaseModel):
    """Geographic point."""
    latitude: float
    longitude: float


class Route(BaseModel):
    """Single alternative route from Google Maps."""
    origin: GeoLocation
    destination: GeoLocation
    distance_m: int
    duration_s: int
    risk_score: float  # 0–1, computed by us from passes_through_flooded + congestion
    passes_through_flooded: bool
    polyline: Optional[str] = None  # Encoded polyline or simplified path
    risk_explanation: str  # "Route passes through high-risk zone" etc.


class SafeSpot(BaseModel):
    """Pre-vetted shelter, hospital, or safe assembly point."""
    safe_spot_id: str
    name: str
    location: GeoLocation
    type: str  # "shelter", "hospital", "high_ground", "mosque", etc.
    capacity_people: Optional[int] = None
    distance_m: int  # From user's location
    contact_phone: Optional[str] = None
    is_open: bool = True


class Helpline(BaseModel):
    """Emergency helpline contact."""
    helpline_id: str
    name: str  # "Rescue 1122", "CARES 1122", etc.
    city: str
    crisis_type: str
    phone: str
    available_24h: bool


class UserAction(BaseModel):
    """Action recommended to a single user."""
    verb: ActionVerb
    message_en: str  # ≤ 100 chars, action + WHY (1 sentence)
    message_ur: str  # Urdu translation, simple register
    route_alternatives: Optional[list[Route]] = None
    safe_spots: Optional[list[SafeSpot]] = None  # Top 3 nearest
    helpline: Optional[Helpline] = None
    urgency: Urgency
    metadata: dict[str, Any] = Field(default_factory=dict)  # verb-specific data


class SystemAction(BaseModel):
    """System-level action (e.g., alert authority)."""
    type: SystemActionType
    target: str  # Helpline ID, route name, zone name, etc.
    payload: dict[str, Any]  # Type-specific data
    urgency: Urgency


class Plan(BaseModel):
    """Complete action plan for an event."""
    plan_id: str
    event_id: str
    created_at: datetime

    system_actions: list[SystemAction] = Field(default_factory=list)
    user_actions: dict[str, UserAction] = Field(default_factory=dict)  # {user_id: UserAction}


class PlanRequest(BaseModel):
    """Request to /plan/run."""
    event_id: str
    dry_run: bool = False


class PlanResult(BaseModel):
    """Result of planning operation."""
    plan_id: Optional[str] = None
    event_id: str
    system_actions_count: int = 0
    user_actions_count: int = 0
    duration_ms: int = 0
    errors: list[str] = Field(default_factory=list)


class ToolCall(BaseModel):
    """Auditable tool invocation."""
    name: str
    args: dict[str, Any] = Field(default_factory=dict)
    result: Any = None
    duration_ms: int = 0


class AgentTrace(BaseModel):
    """Execution trace for debugging."""
    trace_id: Optional[str] = None
    event_id: Optional[str] = None
    plan_id: Optional[str] = None
    agent: str = "planning"
    step: str = ""
    input_summary: str = ""
    output_summary: str = ""
    reasoning: str = ""
    tools_called: list[ToolCall] = Field(default_factory=list)
    duration_ms: int = 0
    created_at: Optional[datetime] = None
