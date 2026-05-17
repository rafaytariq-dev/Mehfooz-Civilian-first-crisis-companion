"""
Ingestion Agent — FastAPI service.

Deployed to Cloud Run.  Exposes endpoints for:
  - /health            — liveness check
  - /ingest/report     — process a single new report (push trigger)
  - /ingest/poll       — poll weather + traffic for all cities (pull trigger)
  - /ingest/social     — enrich social signals on demand
  - /ingest/test       — smoke test with a sample Roman Urdu input
"""
from __future__ import annotations

import logging
import os
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from agent import enrich_social, poll_signals, process_report
from models import IngestReportRequest, IngestionResult, PollRequest

# ─── Logging ───
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s — %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger("ingestion.main")


# ─── Lifespan ───

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Ingestion Agent starting up...")
    yield
    logger.info("Ingestion Agent shutting down...")
    # Clean up HTTP client
    from tools import _http
    if _http:
        await _http.aclose()


# ─── FastAPI app ───

app = FastAPI(
    title="Mehfooz Ingestion Agent",
    description="Pulls and normalizes signals from citizens, weather, traffic, and social media.",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── Health check ───

@app.get("/health")
async def health():
    """Liveness check for Cloud Run and CI smoke tests."""
    return {
        "status": "ok",
        "service": "ingestion-agent",
        "version": "1.0.0",
    }


# ─── Report ingestion (push trigger) ───

@app.post("/ingest/report", response_model=IngestionResult)
async def ingest_report(req: IngestReportRequest):
    """Process a single new citizen report.

    Called by the Cloud Function triggered by Firestore
    onCreate(reports/{id}).
    """
    try:
        result = await process_report(req)
        return result
    except Exception as e:
        logger.exception(f"Failed to process report {req.report_id}")
        raise HTTPException(status_code=500, detail=str(e))


# ─── Scheduled poll (pull trigger) ───

@app.post("/ingest/poll", response_model=IngestionResult)
async def ingest_poll(req: PollRequest | None = None):
    """Poll weather + traffic for all cities.

    Called by Cloud Scheduler every 2 minutes.
    """
    if req is None:
        req = PollRequest()

    try:
        result = await poll_signals(req)
        return result
    except Exception as e:
        logger.exception("Failed during scheduled poll")
        raise HTTPException(status_code=500, detail=str(e))


# ─── Social enrichment (on demand) ───

@app.post("/ingest/social", response_model=IngestionResult)
async def ingest_social(city: str | None = None):
    """Enrich cached social signals with NLP.

    Can be called on demand or by the orchestrator when it
    needs more social signals for a detection cycle.
    """
    try:
        result = await enrich_social(city=city)
        return result
    except Exception as e:
        logger.exception("Failed during social enrichment")
        raise HTTPException(status_code=500, detail=str(e))


# ─── Smoke test ───

@app.post("/ingest/test")
async def ingest_test():
    """Smoke test: process a sample Roman Urdu report.

    Exercises normalize_text without requiring Firestore writes.
    """
    from tools import normalize_text, verify_photo

    results = {}

    # Test 1: Roman Urdu normalization
    test_input = "G-10 mein paani bhar gaya, ghutnon tak"
    normalized = await normalize_text(test_input)
    results["normalize_text"] = {
        "input": test_input,
        "output": normalized,
    }

    # Test 2: Urdu script normalization
    test_input_ur = "پانی بہت تیزی سے بڑھ رہا ہے جی ٹین میں"
    normalized_ur = await normalize_text(test_input_ur)
    results["normalize_urdu"] = {
        "input": test_input_ur,
        "output": normalized_ur,
    }

    # Test 3: English normalization
    test_input_en = "Heavy flooding near Faisal Mosque parking, water rising fast"
    normalized_en = await normalize_text(test_input_en)
    results["normalize_english"] = {
        "input": test_input_en,
        "output": normalized_en,
    }

    return {
        "status": "ok",
        "tests": results,
    }


# ─── Entry point ───

if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", "8081"))
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")
