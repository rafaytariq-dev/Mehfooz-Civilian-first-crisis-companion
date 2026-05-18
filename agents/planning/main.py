"""
Planning Agent — FastAPI service.

Endpoints:
- GET  /health
- POST /plan/run
- POST /plan/test
"""

from __future__ import annotations

import logging
import os
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from agent import run_planning, run_test_planning
from helpline import resolve_helpline, run_helpline_tests
from models import (
    HelplineResolveRequest,
    HelplineResolveResponse,
    HelplineTestResponse,
    PlanRequest,
    PlanResult,
)


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s — %(message)s",
    stream=sys.stdout,
)

logger = logging.getLogger("planning.main")


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Planning Agent starting up...")
    yield
    logger.info("Planning Agent shutting down...")


app = FastAPI(
    title="Mehfooz Planning Agent",
    description="Converts crisis Events into action Plans (system + per-user).",
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
    return {
        "status": "ok",
        "service": "planning-agent",
        "version": "1.0.0",
    }


@app.post("/plan/run", response_model=PlanResult)
async def plan_run(req: PlanRequest):
    """
    Run M4 planning against a Firestore event.
    Converts event → plan (system + per-user actions).
    """

    try:
        result = await run_planning(req)
        return result
    except Exception as e:
        logger.exception("Failed during /plan/run")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/plan/test")
async def plan_test():
    """
    Local smoke test without Firestore.
    """

    try:
        return await run_test_planning()
    except Exception as e:
        logger.exception("Failed during /plan/test")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/helpline/resolve", response_model=HelplineResolveResponse)
async def helpline_resolve(req: HelplineResolveRequest):
    """Resolve the best helpline for a city + crisis type."""

    try:
        result = resolve_helpline(
            city=req.city,
            crisis_type=req.crisis_type,
            language=req.language,
            use_firestore=req.use_firestore,
        )
        return HelplineResolveResponse(
            name=result.get("name", ""),
            number=result.get("number", ""),
            cities=result.get("cities", []),
            crisis_types=result.get("crisis_types", []),
            language_support=result.get("language_support", []),
            notes=result.get("notes", ""),
            confidence=float(result.get("confidence", 0.6)),
            reason=result.get("reason", ""),
        )
    except Exception as e:
        logger.exception("Failed during /helpline/resolve")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/helpline/test", response_model=HelplineTestResponse)
async def helpline_test():
    """Local helpline resolver tests (no Firestore required)."""

    try:
        passed, errors = run_helpline_tests(local_only=True)
        return HelplineTestResponse(status="ok", tests_passed=passed, errors=errors)
    except Exception as e:
        logger.exception("Failed during /helpline/test")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", "8083"))
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")
