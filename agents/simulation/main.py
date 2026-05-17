"""
Simulation Agent — FastAPI service.

Endpoints:
- GET  /health
- POST /simulate/run    — Execute a plan against mock endpoints
- POST /simulate/test   — Smoke test with inline mock data (no Firestore)
"""

from __future__ import annotations

import logging
import os
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from agent import run_simulation, run_test_simulation
from models import SimulationRequest, SimulationResult


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s — %(message)s",
    stream=sys.stdout,
)

logger = logging.getLogger("simulation.main")


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Simulation Agent starting up...")
    yield
    logger.info("Simulation Agent shutting down...")


app = FastAPI(
    title="Mehfooz Simulation Agent",
    description=(
        "M5 — Execute Plan actions against mock authority endpoints. "
        "Produce auditable SimulationReport with dispatches, notification tiers, "
        "routes flagged, and estimated impact. Never calls real authority APIs."
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


@app.get("/health")
async def health():
    """Health check endpoint for Cloud Run and CI smoke tests."""
    return {
        "status": "ok",
        "service": "simulation-agent",
        "version": "1.0.0",
        "module": "M5",
    }


@app.post("/simulate/run", response_model=SimulationResult)
async def simulate_run(req: SimulationRequest):
    """
    Execute a plan against mock endpoints.

    Reads plan from Firestore (produced by M4), dispatches to mock
    Cloud Function endpoints (PDMA, Rescue 1122, Traffic, SMS),
    queues push notifications, computes estimated impact, and
    writes a SimulationReport.

    Set dry_run=true to skip Firestore writes.
    """
    try:
        result = await run_simulation(req)
        return result
    except Exception as e:
        logger.exception("Failed during /simulate/run")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/simulate/test")
async def simulate_test():
    """
    Smoke test with inline mock data — no Firestore required.

    Returns a complete simulation pipeline result using hardcoded
    G-10 scenario data, without calling any external services.
    """
    try:
        return await run_test_simulation()
    except Exception as e:
        logger.exception("Failed during /simulate/test")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", "8084"))
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")
