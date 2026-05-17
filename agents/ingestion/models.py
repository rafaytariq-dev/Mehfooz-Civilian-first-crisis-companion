"""
Ingestion Agent — Pydantic models for signals and traces.
"""
from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any, Optional

from pydantic import BaseModel, Field


# ─── Enums ───

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


class LanguageCode(str, Enum):
    ur = "ur"
    en = "en"
    roman_ur = "roman_ur"


# ─── Geo ───

class GeoLocation(BaseModel):
    latitude: float
    longitude: float


# ─── Weather signal ───

class WeatherSignal(BaseModel):
    signal_id: Optional[str] = None
    source: str = "open_meteo"
    location: GeoLocation
    city: str
    rainfall_mm_1h: float = 0.0
    rainfall_mm_24h: float = 0.0
    temp_c: float = 0.0
    humidity: float = 0.0
    wind_kph: float = 0.0
    recorded_at: Optional[datetime] = None
    fetched_at: Optional[datetime] = None


# ─── Traffic signal ───

class TrafficSignal(BaseModel):
    signal_id: Optional[str] = None
    source: str = "google_maps"
    origin: GeoLocation
    destination: GeoLocation
    route_name: str = ""
    duration_normal_s: int = 0
    duration_now_s: int = 0
    congestion_ratio: float = 1.0
    recorded_at: Optional[datetime] = None


# ─── Social signal ───

class SocialSignal(BaseModel):
    signal_id: Optional[str] = None
    source: str = "twitter"
    text: str = ""
    language: str = ""
    location_inferred: Optional[GeoLocation] = None
    posted_at: Optional[datetime] = None
    author_handle: str = ""
    url: str = ""
    media_urls: list[str] = Field(default_factory=list)


# ─── Normalized report output from Gemini ───

class NormalizedReport(BaseModel):
    text_normalized: str = ""
    language_detected: str = ""
    crisis_type_inferred: Optional[str] = None
    severity_inferred: Optional[int] = None
    location_hints: list[str] = Field(default_factory=list)


# ─── Photo verification result ───

class PhotoVerification(BaseModel):
    is_match: bool = False
    confidence: float = 0.0
    description: str = ""


# ─── Agent trace (for transparency) ───

class ToolCall(BaseModel):
    name: str
    args: dict[str, Any] = Field(default_factory=dict)
    result: Any = None
    duration_ms: int = 0


class AgentTrace(BaseModel):
    trace_id: Optional[str] = None
    event_id: Optional[str] = None
    agent: str = "ingestion"
    step: str = ""
    input_summary: str = ""
    output_summary: str = ""
    reasoning: str = ""
    tools_called: list[ToolCall] = Field(default_factory=list)
    duration_ms: int = 0
    created_at: Optional[datetime] = None


# ─── API request/response models ───

class IngestReportRequest(BaseModel):
    """Triggered by Firestore onCreate(reports/{id}) Cloud Function."""
    report_id: str
    user_id: str
    text_raw: str = ""
    voice_url: Optional[str] = None
    photo_urls: list[str] = Field(default_factory=list)
    location: GeoLocation
    geo_accuracy_m: float = 50.0
    crisis_type_user: Optional[str] = None
    severity_user: Optional[int] = None
    created_at: Optional[str] = None


class PollRequest(BaseModel):
    """Triggered by Cloud Scheduler every 2 minutes."""
    cities: list[str] = Field(default_factory=lambda: [
        "Islamabad", "Rawalpindi", "Karachi", "Lahore"
    ])


class IngestionResult(BaseModel):
    """Summary of what was ingested in one run."""
    reports_processed: int = 0
    weather_signals: int = 0
    traffic_signals: int = 0
    social_signals_enriched: int = 0
    traces_written: int = 0
    errors: list[str] = Field(default_factory=list)
