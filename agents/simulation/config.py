"""
Simulation Agent — Configuration.
Environment variables + constants shared across the agent.
"""
import os

# ─── GCP / Firebase ───
PROJECT_ID = os.getenv("PROJECT_ID", "mehfooz-prod")
AGENT_NAME = "simulation"
REGION = os.getenv("REGION", "asia-south1")

# ─── Mock endpoint base URL ───
# In production these are Cloud Functions; locally they can be the emulator
MOCK_ENDPOINTS_BASE_URL = os.getenv(
    "MOCK_ENDPOINTS_BASE_URL",
    f"https://{REGION}-{PROJECT_ID}.cloudfunctions.net",
)

# ─── Mock endpoint paths ───
MOCK_ENDPOINTS = {
    "pdma_dispatch": "/mockPdmaDispatch",
    "rescue_1122": "/mockRescue1122",
    "traffic_reroute": "/mockTrafficReroute",
    "sms_blast": "/mockSmsBlast",
}

# ─── Authority labels for dispatches ───
AUTHORITY_MAP = {
    "pdma_dispatch": "PDMA-Punjab",
    "rescue_1122": "Rescue-1122-ICT",
    "traffic_reroute": "CDA-TrafficControl",
    "sms_blast": "SMS-Gateway-Mock",
}

# ─── Impact heuristics (from spec — transparent, demo-friendly) ───
# avg_delay_saved = 22 min if severity >= 4, else 12 min
AVG_DELAY_SEVERE_MIN = 22
AVG_DELAY_MODERATE_MIN = 12
# congestion_reduction_min = diverted * 0.3 * avg_delay_saved
CONGESTION_REDUCTION_FACTOR = 0.3
# response_time_saved_min = 8 if any SOS action, else 0
RESPONSE_TIME_SAVED_SOS_MIN = 8

# ─── Notification urgency tiers ───
URGENCY_TIERS = ["sos", "high", "med", "low"]

# ─── System action → mock endpoint mapping ───
# Maps SystemAction.type to the mock endpoint key
SYSTEM_ACTION_ENDPOINT_MAP = {
    "notify_helpline": "rescue_1122",
    "flag_route": "traffic_reroute",
    "broadcast_zone": "sms_blast",
}

# ─── Crisis taxonomy ───
CRISIS_TYPES = [
    "flood", "urban_flood", "flash_flood", "heatwave",
    "road_incident", "fire", "building_collapse",
    "power_outage", "air_quality", "glof",
]
