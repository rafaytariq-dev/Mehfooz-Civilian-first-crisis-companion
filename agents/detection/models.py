"""
Detection Agent — Pydantic models.

M3 turns normalized signals into candidate/verified crisis events.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any, Optional

from pydantic import BaseModel, Field


class CrisisType(str, Enum):
    flood = "flood"
    urban_flood = "urban_flood"
    flash_flood = "flash_flood"
    heatwave = "heatwave"
    road_incident = "road_incident"
    fire = "fire"
    building_collapse = "building_collapse"
    power_outage = "power_outage"
    air_quality = "air_quality"
    glof = "glof"


class EventStatus(str, Enum):
    candidate = "candidate"
    verified = "verified"
    resolved = "resolved"


class SignalModality(str, Enum):
    citizen_report = "citizen_report"
    weather = "weather"
    traffic = "traffic"
    social = "social"
    photo_verified = "photo_verified"


class GeoLocation(BaseModel):
    latitude: float
    longitude: float


class NormalizedSignal(BaseModel):
    signal_id: str
    source_collection: str
    modality: str

    lat: float
    lon: float
    timestamp: datetime

    city: Optional[str] = None
    crisis_type: Optional[str] = None
    severity: Optional[int] = None
    text: str = ""

    confidence: float = 0.0

    rainfall_mm_1h: Optional[float] = None
    rainfall_mm_24h: Optional[float] = None
    congestion_ratio: Optional[float] = None

    raw: dict[str, Any] = Field(default_factory=dict)


class DetectedCluster(BaseModel):
    cluster_id: str
    signals: list[NormalizedSignal] = Field(default_factory=list)
    centroid: GeoLocation
    polygon: list[GeoLocation] = Field(default_factory=list)
    modalities: list[str] = Field(default_factory=list)
    modality_count: int = 0


class HistoricalPrior(BaseModel):
    is_flood_prone: bool = False
    matched_location_id: Optional[str] = None
    matched_location_name: Optional[str] = None
    threshold_mm_h: Optional[float] = None
    distance_m: Optional[float] = None


class EventCandidate(BaseModel):
    event_id: Optional[str] = None
    type: str
    polygon: list[GeoLocation]
    centroid: GeoLocation
    severity: int
    confidence: float
    status: str
    explanation_en: str
    explanation_ur: str
    contributing_signals: dict[str, list[str]]
    started_at: datetime
    last_updated: datetime


class DetectionRequest(BaseModel):
    """
    Main request for /detect/run.
    """

    city: Optional[str] = None
    minutes: int = 60
    eps_km: float = 0.5
    min_samples: int = 3
    dry_run: bool = False
    force_create: bool = True


class DetectionResult(BaseModel):
    signals_read: int = 0
    clusters_found: int = 0
    events_created: int = 0
    verified_events: int = 0
    candidate_events: int = 0
    traces_written: int = 0
    event_ids: list[str] = Field(default_factory=list)
    errors: list[str] = Field(default_factory=list)


class ToolCall(BaseModel):
    name: str
    args: dict[str, Any] = Field(default_factory=dict)
    result: Any = None
    duration_ms: int = 0


class AgentTrace(BaseModel):
    trace_id: Optional[str] = None
    event_id: Optional[str] = None
    agent: str = "detection"
    step: str = ""
    input_summary: str = ""
    output_summary: str = ""
    reasoning: str = ""
    tools_called: list[ToolCall] = Field(default_factory=list)
    duration_ms: int = 0
    created_at: Optional[datetime] = None