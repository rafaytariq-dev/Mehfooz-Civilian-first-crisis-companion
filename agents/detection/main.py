"""
Detection Agent — FastAPI service.

Endpoints:
- GET  /health
- POST /detect/run
- POST /detect/test
"""

from __future__ import annotations

import logging
import os
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from agent import run_detection, run_test_detection
from models import DetectionRequest, DetectionResult


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s — %(message)s",
    stream=sys.stdout,
)

logger = logging.getLogger("detection.main")


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Detection Agent starting up...")
    yield
    logger.info("Detection Agent shutting down...")


app = FastAPI(
    title="Mehfooz Detection Agent",
    description="Clusters crisis signals, performs multi-modal corroboration, and writes Event docs.",
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
        "service": "detection-agent",
        "version": "1.0.0",
    }


@app.post("/detect/run", response_model=DetectionResult)
async def detect_run(req: DetectionRequest):
    """
    Run M3 detection against Firestore data.
    """

    try:
        result = await run_detection(req)
        return result
    except Exception as e:
        logger.exception("Failed during /detect/run")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/detect/test")
async def detect_test():
    """
    Local smoke test without Firestore.
    """

    try:
        return await run_test_detection()
    except Exception as e:
        logger.exception("Failed during /detect/test")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", "8082"))
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")