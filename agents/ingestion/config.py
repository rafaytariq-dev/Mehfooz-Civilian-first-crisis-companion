"""
Ingestion Agent — Configuration.
Environment variables + constants shared across the agent.
"""
import os

# ─── GCP / Firebase ───
PROJECT_ID = os.getenv("PROJECT_ID", "mehfooz-prod")
AGENT_NAME = "ingestion"
REGION = os.getenv("REGION", "asia-south1")

# ─── Gemini models ───
GEMINI_FLASH = os.getenv("GEMINI_FLASH_MODEL", "gemini-2.5-flash")
GEMINI_PRO = os.getenv("GEMINI_PRO_MODEL", "gemini-2.5-pro")

# ─── Google Maps API key (for traffic) ───
MAPS_API_KEY = os.getenv("GOOGLE_MAPS_API_KEY", "")

# ─── Cities in scope (priority order) ───
CITIES: dict[str, dict[str, float]] = {
    "Islamabad":  {"lat": 33.6938, "lon": 73.0651},
    "Rawalpindi": {"lat": 33.5651, "lon": 73.0169},
    "Karachi":    {"lat": 24.8607, "lon": 67.0011},
    "Lahore":     {"lat": 31.5204, "lon": 74.3587},
}

# ─── Key traffic routes to monitor per city ───
TRAFFIC_ROUTES: dict[str, list[dict]] = {
    "Islamabad": [
        {
            "name": "G-10 to Faizabad via IJP Road",
            "origin": {"lat": 33.6920, "lon": 72.0130},
            "destination": {"lat": 33.7100, "lon": 72.0350},
        },
        {
            "name": "G-11 Markaz to Blue Area",
            "origin": {"lat": 33.7020, "lon": 72.0050},
            "destination": {"lat": 33.7280, "lon": 73.0930},
        },
        {
            "name": "F-10 Markaz to Faisal Mosque",
            "origin": {"lat": 33.7050, "lon": 72.9780},
            "destination": {"lat": 33.7295, "lon": 73.0372},
        },
    ],
    "Rawalpindi": [
        {
            "name": "Saddar to Faizabad",
            "origin": {"lat": 33.5980, "lon": 73.0430},
            "destination": {"lat": 33.7100, "lon": 72.0350},
        },
    ],
    "Karachi": [
        {
            "name": "Saddar to Gulshan via Shahra-e-Faisal",
            "origin": {"lat": 24.8560, "lon": 67.0210},
            "destination": {"lat": 24.9230, "lon": 67.0890},
        },
        {
            "name": "SITE Area to Nazimabad",
            "origin": {"lat": 24.9100, "lon": 67.0200},
            "destination": {"lat": 24.9200, "lon": 67.0500},
        },
    ],
    "Lahore": [
        {
            "name": "Kalma Chowk to Mall Road",
            "origin": {"lat": 31.5100, "lon": 74.3300},
            "destination": {"lat": 31.5550, "lon": 74.3250},
        },
    ],
}

# ─── Crisis taxonomy ───
CRISIS_TYPES = [
    "flood", "urban_flood", "flash_flood", "heatwave",
    "road_incident", "fire", "building_collapse",
    "power_outage", "air_quality", "glof",
]

# ─── Open-Meteo base URL (free, no key needed) ───
OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"

# ─── PMD best-effort endpoint ───
PMD_BASE_URL = "https://nwfc.pmd.gov.pk"

# ─── Google Maps Routes API ───
ROUTES_API_URL = "https://routes.googleapis.com/directions/v2:computeRoutes"
