"""
Orchestrator + Comms Agent — Configuration.
Environment variables + constants shared across the module.
"""
import os

# ─── GCP / Firebase ───
PROJECT_ID = os.getenv("PROJECT_ID", "mehfooz-prod")
AGENT_NAME = "orchestrator"
REGION = os.getenv("REGION", "asia-south1")

# ─── Gemini models ───
GEMINI_FLASH = os.getenv("GEMINI_FLASH_MODEL", "gemini-2.5-flash")

# ─── Sub-agent URLs ───
# In production these point to Cloud Run services.
# Locally they point to agents running on their default ports.
INGESTION_AGENT_URL = os.getenv(
    "INGESTION_AGENT_URL", "http://localhost:8081"
)
DETECTION_AGENT_URL = os.getenv(
    "DETECTION_AGENT_URL", "http://localhost:8082"
)
PLANNING_AGENT_URL = os.getenv(
    "PLANNING_AGENT_URL", "http://localhost:8083"
)
SIMULATION_AGENT_URL = os.getenv(
    "SIMULATION_AGENT_URL", "http://localhost:8084"
)

# ─── Sub-agent endpoint paths ───
INGESTION_REPORT_PATH = "/ingest/report"
INGESTION_SOCIAL_PATH = "/ingest/social"
DETECTION_RUN_PATH = "/detect/run"
PLANNING_RUN_PATH = "/plan/run"
SIMULATION_RUN_PATH = "/simulate/run"

# ─── Orchestrator parameters ───
# Max feedback-loop retries (detection re-invokes after low confidence)
MAX_DETECTION_RETRIES = 2
# Confidence threshold below which we re-invoke ingestion
CONFIDENCE_THRESHOLD = 0.6
# Minimum modality count to avoid retry
MIN_MODALITY_COUNT = 2
# Max total ingestion-detection cycles before giving up
MAX_TOTAL_CYCLES = 3

# ─── Comms parameters ───
# Max character length for SOS/high tier push bodies
SOS_HIGH_MAX_CHARS = 140
# SMS fallback: if user has no FCM activity in this many hours, queue SMS
SMS_FALLBACK_INACTIVE_HOURS = 48

# ─── HTTP client settings ───
HTTP_TIMEOUT_SECONDS = 25  # per sub-agent call
HTTP_TOTAL_TIMEOUT_SECONDS = 120  # total chain timeout

# ─── Crisis taxonomy ───
CRISIS_TYPES = [
    "flood", "urban_flood", "flash_flood", "heatwave",
    "road_incident", "fire", "building_collapse",
    "power_outage", "air_quality", "glof",
]

# ─── Cities in scope ───
CITIES = {
    "Islamabad":  {"lat": 33.6938, "lon": 73.0651},
    "Rawalpindi": {"lat": 33.5651, "lon": 73.0169},
    "Karachi":    {"lat": 24.8607, "lon": 67.0011},
    "Lahore":     {"lat": 31.5204, "lon": 74.3587},
}
