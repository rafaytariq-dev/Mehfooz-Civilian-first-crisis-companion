"""
Orchestrator + Comms Agent — FastAPI service.

Endpoints:
- GET  /health             — liveness check
- POST /orchestrate/run    — full chain trigger (report → push)
- POST /orchestrate/test   — smoke test with G-10 scenario data
"""
from __future__ import annotations

import logging
import os
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from loop import orchestrate
from models import OrchestrateRequest, OrchestrateResult

# ─── Logging ───
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s — %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger("orchestrator.main")


# ─── Lifespan ───

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Orchestrator Agent starting up...")
    yield
    logger.info("Orchestrator Agent shutting down...")


# ─── FastAPI app ───

app = FastAPI(
    title="Mehfooz Orchestrator + Comms Agent",
    description=(
        "M6 — Meta-agent that routes between ingestion → detection → planning → "
        "simulation → comms. Includes feedback loop for low-confidence detection "
        "and FCM push notifications with urgency tiering."
    ),
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
        "service": "orchestrator-agent",
        "version": "1.0.0",
        "module": "M6",
    }


# ─── Full chain orchestration ───

@app.post("/orchestrate/run", response_model=OrchestrateResult)
async def orchestrate_run(req: OrchestrateRequest):
    """Run the full orchestration chain.

    Triggered by Cloud Function on reports/{id} creation.
    Chains: ingestion → detection (with feedback loop) →
    planning → simulation → comms (FCM push).
    """
    try:
        result = await orchestrate(req)
        return result
    except Exception as e:
        logger.exception(f"Failed during /orchestrate/run for report {req.report_id}")
        raise HTTPException(status_code=500, detail=str(e))


# ─── Smoke test ───

@app.post("/orchestrate/test")
async def orchestrate_test():
    """Smoke test with a G-10 scenario report.

    Creates a synthetic OrchestrateRequest matching the demo
    scenario and runs it through the full chain. Requires all
    sub-agents to be running.
    """
    test_req = OrchestrateRequest(
        report_id="test-orch-g10-001",
        user_id="demo-aisha-001",
        text_raw="G-10 mein paani bhar gaya, ghutnon tak. Sadak band hai.",
        photo_urls=[],
        location={"latitude": 33.6920, "longitude": 72.0130},
        geo_accuracy_m=50.0,
        crisis_type_user="flash_flood",
        severity_user=3,
        city="Islamabad",
    )

    try:
        result = await orchestrate(test_req)
        return {
            "status": "ok",
            "test": "g10_scenario",
            "result": result.model_dump(mode="json"),
        }
    except Exception as e:
        logger.exception("Failed during /orchestrate/test")
        raise HTTPException(status_code=500, detail=str(e))


# ─── Entry point ───

if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", "8085"))
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")
