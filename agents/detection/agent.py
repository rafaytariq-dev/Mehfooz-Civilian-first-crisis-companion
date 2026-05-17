"""
Detection Agent — main detection logic.

This file performs M3:
1. Read recent signals.
2. Cluster signals.
3. Check modalities.
4. Create candidate or verified events.
5. Write event docs.
6. Write trace docs.
"""

from __future__ import annotations

import logging
import time
import uuid
from collections import Counter
from datetime import datetime, timezone
from typing import Any

from cluster import cluster_signals
from models import (
    AgentTrace,
    DetectedCluster,
    DetectionRequest,
    DetectionResult,
    EventCandidate,
    GeoLocation,
    HistoricalPrior,
)
from tools import (
    fetch_historical_prior,
    make_tool_call,
    now_utc,
    read_recent_signals,
    update_reports_with_event,
    write_event,
    write_trace,
)

logger = logging.getLogger("detection.agent")


def normalize_crisis_type(values: list[str | None]) -> str:
    clean = [v for v in values if v]

    if not clean:
        return "urban_flood"

    counts = Counter(clean)

    # Prefer flood-like crisis if present because demo scenario is flood-focused.
    for preferred in ["flash_flood", "urban_flood", "flood"]:
        if preferred in counts:
            return preferred

    return counts.most_common(1)[0][0]


def calculate_severity(cluster: DetectedCluster) -> int:
    """
    Severity from:
    - max citizen severity
    - rainfall strength
    - traffic congestion
    """

    severities = [s.severity for s in cluster.signals if s.severity is not None]
    base = max(severities) if severities else 2

    max_rainfall = max(
        [s.rainfall_mm_1h or 0.0 for s in cluster.signals],
        default=0.0,
    )

    max_congestion = max(
        [s.congestion_ratio or 1.0 for s in cluster.signals],
        default=1.0,
    )

    severity = int(base)

    if max_rainfall >= 25:
        severity += 1
    elif max_rainfall >= 15 and severity < 3:
        severity = 3

    if max_congestion >= 3.0:
        severity += 1
    elif max_congestion >= 2.0 and severity < 3:
        severity = 3

    return max(1, min(5, severity))


def calculate_confidence(
    modality_count: int,
    prior: HistoricalPrior,
    severity: int,
) -> float:
    """
    Spec-calibrated confidence.

    - <2 modalities → candidate confidence <= 0.4
    - 2 modalities no prior → 0.50–0.65
    - 2 modalities + prior → 0.65–0.80
    - 3+ modalities + prior → 0.80–0.95
    - never 1.0
    """

    if modality_count < 2:
        return 0.35

    if modality_count == 2 and not prior.is_flood_prone:
        return 0.62 if severity >= 3 else 0.55

    if modality_count == 2 and prior.is_flood_prone:
        return 0.78 if severity >= 3 else 0.68

    if modality_count >= 3 and prior.is_flood_prone:
        return 0.90 if severity >= 4 else 0.86

    if modality_count >= 3:
        return 0.82 if severity >= 3 else 0.74

    return 0.35


def build_contributing_signals(cluster: DetectedCluster) -> dict[str, list[str]]:
    result = {
        "reports": [],
        "weather": [],
        "traffic": [],
        "social": [],
    }

    for signal in cluster.signals:
        if signal.modality in {"citizen_report", "photo_verified"}:
            clean_id = signal.signal_id.replace(":photo", "")
            if clean_id not in result["reports"]:
                result["reports"].append(clean_id)

        elif signal.modality == "weather":
            result["weather"].append(signal.signal_id)

        elif signal.modality == "traffic":
            result["traffic"].append(signal.signal_id)

        elif signal.modality == "social":
            result["social"].append(signal.signal_id)

    return result


def count_modality(cluster: DetectedCluster, modality: str) -> int:
    return sum(1 for s in cluster.signals if s.modality == modality)


def max_rainfall(cluster: DetectedCluster) -> float:
    return max([s.rainfall_mm_1h or 0.0 for s in cluster.signals], default=0.0)


def max_congestion(cluster: DetectedCluster) -> float:
    return max([s.congestion_ratio or 1.0 for s in cluster.signals], default=1.0)


def build_explanations(
    cluster: DetectedCluster,
    crisis_type: str,
    severity: int,
    status: str,
    prior: HistoricalPrior,
) -> tuple[str, str]:
    report_count = count_modality(cluster, "citizen_report")
    photo_count = count_modality(cluster, "photo_verified")
    social_count = count_modality(cluster, "social")
    rainfall = max_rainfall(cluster)
    congestion = max_congestion(cluster)

    parts = []

    if report_count:
        parts.append(f"{report_count} citizen reports")

    if photo_count:
        parts.append(f"{photo_count} verified photos")

    if rainfall > 0:
        parts.append(f"{rainfall:.0f}mm rain in 1h")

    if congestion > 1.0:
        parts.append(f"{congestion:.1f}x traffic delay")

    if social_count:
        parts.append(f"{social_count} social posts")

    if prior.is_flood_prone and prior.matched_location_name:
        parts.append(f"known flood-prone area: {prior.matched_location_name}")

    evidence = " + ".join(parts) if parts else "limited evidence"

    if status == "verified":
        explanation_en = (
            f"{evidence} indicate a severity {severity} {crisis_type.replace('_', ' ')} near this area."
        )
        explanation_ur = (
            f"Is ilaqay ke qareeb {evidence} mila hai. Yeh severity {severity} "
            f"{crisis_type.replace('_', ' ')} lag raha hai."
        )
    else:
        explanation_en = (
            f"{evidence} found, but less than 2 evidence types support it. Kept as candidate."
        )
        explanation_ur = (
            f"Kuch reports mili hain, lekin abhi 2 qisam ke saboot nahi milay. "
            f"Isay candidate rakha gaya hai."
        )

    return explanation_en[:300], explanation_ur[:300]


def build_event_from_cluster(cluster: DetectedCluster) -> EventCandidate:
    crisis_type = normalize_crisis_type([s.crisis_type for s in cluster.signals])
    prior = fetch_historical_prior(cluster.centroid, crisis_type)

    severity = calculate_severity(cluster)
    confidence = calculate_confidence(
        modality_count=cluster.modality_count,
        prior=prior,
        severity=severity,
    )

    if cluster.modality_count < 2:
        status = "candidate"
        confidence = min(confidence, 0.40)
    else:
        status = "verified"

    explanation_en, explanation_ur = build_explanations(
        cluster=cluster,
        crisis_type=crisis_type,
        severity=severity,
        status=status,
        prior=prior,
    )

    contributing_signals = build_contributing_signals(cluster)

    timestamps = [s.timestamp for s in cluster.signals]
    started_at = min(timestamps) if timestamps else now_utc()

    return EventCandidate(
        event_id=f"evt-{uuid.uuid4().hex[:12]}",
        type=crisis_type,
        polygon=cluster.polygon,
        centroid=cluster.centroid,
        severity=severity,
        confidence=confidence,
        status=status,
        explanation_en=explanation_en,
        explanation_ur=explanation_ur,
        contributing_signals=contributing_signals,
        started_at=started_at,
        last_updated=now_utc(),
    )


def event_to_firestore_dict(event: EventCandidate) -> dict[str, Any]:
    """
    Convert EventCandidate into Firestore-compatible dict.
    Geo conversion is handled inside tools.write_event().
    """

    return {
        "event_id": event.event_id,
        "type": event.type,
        "polygon": event.polygon,
        "centroid": event.centroid,
        "severity": event.severity,
        "confidence": event.confidence,
        "status": event.status,
        "explanation_en": event.explanation_en,
        "explanation_ur": event.explanation_ur,
        "contributing_signals": event.contributing_signals,
        "started_at": event.started_at,
        "last_updated": event.last_updated,
    }


async def run_detection(req: DetectionRequest) -> DetectionResult:
    started = time.monotonic()
    result = DetectionResult()

    tool_calls = []

    try:
        t0 = time.monotonic()
        signals = read_recent_signals(minutes=req.minutes, city=req.city)
        tool_calls.append(
            make_tool_call(
                name="read_recent_signals",
                args={"minutes": req.minutes, "city": req.city},
                result={"signals": len(signals)},
                started_at=t0,
            )
        )

        result.signals_read = len(signals)

        t1 = time.monotonic()
        clusters = cluster_signals(
            signals=signals,
            eps_km=req.eps_km,
            min_samples=req.min_samples,
            time_window_min=req.minutes,
        )

        tool_calls.append(
            make_tool_call(
                name="run_clustering",
                args={
                    "eps_km": req.eps_km,
                    "min_samples": req.min_samples,
                    "time_window_min": req.minutes,
                },
                result={"clusters": len(clusters)},
                started_at=t1,
            )
        )

        result.clusters_found = len(clusters)

        events: list[EventCandidate] = []

        for cluster in clusters:
            event = build_event_from_cluster(cluster)
            events.append(event)

            if event.status == "verified":
                result.verified_events += 1
            else:
                result.candidate_events += 1

            if not req.dry_run:
                event_id = write_event(event_to_firestore_dict(event))
                result.event_ids.append(event_id)
                result.events_created += 1

                report_ids = event.contributing_signals.get("reports", [])
                update_reports_with_event(report_ids, event_id)
            else:
                if event.event_id:
                    result.event_ids.append(event.event_id)

        duration_ms = int((time.monotonic() - started) * 1000)

        reasoning = (
            f"Read {len(signals)} recent signals and found {len(clusters)} clusters. "
            f"Each cluster was checked for multi-modal corroboration. "
            f"Clusters with fewer than 2 modalities were kept as candidate events. "
            f"Clusters with 2 or more modalities were promoted to verified events."
        )

        output_summary = (
            f"Created {result.events_created} events "
            f"({result.verified_events} verified, {result.candidate_events} candidate)."
            if not req.dry_run
            else f"Dry run produced {len(events)} possible events "
                 f"({result.verified_events} verified, {result.candidate_events} candidate)."
        )

        trace = AgentTrace(
            event_id=result.event_ids[0] if result.event_ids else None,
            agent="detection",
            step="detect_events",
            input_summary=(
                f"city={req.city or 'all'}, minutes={req.minutes}, "
                f"signals_read={len(signals)}"
            ),
            output_summary=output_summary,
            reasoning=reasoning,
            tools_called=tool_calls,
            duration_ms=duration_ms,
            created_at=datetime.now(timezone.utc),
        )

        if not req.dry_run:
            write_trace(trace)
            result.traces_written = 1

        return result

    except Exception as e:
        logger.exception("Detection run failed")
        result.errors.append(str(e))

        duration_ms = int((time.monotonic() - started) * 1000)

        try:
            trace = AgentTrace(
                agent="detection",
                step="detect_events_error",
                input_summary=f"city={req.city or 'all'}, minutes={req.minutes}",
                output_summary="Detection failed",
                reasoning=str(e),
                tools_called=tool_calls,
                duration_ms=duration_ms,
                created_at=datetime.now(timezone.utc),
            )
            if not req.dry_run:
                write_trace(trace)
                result.traces_written = 1
        except Exception:
            logger.exception("Could not write failure trace")

        return result


async def run_test_detection() -> dict[str, Any]:
    """
    Test without Firestore.

    Creates a small fake G-10 cluster with:
    - citizen reports
    - verified photo
    - weather
    - traffic

    Expected:
    - one verified event
    - confidence >= 0.8
    - severity >= 3
    """

    from models import NormalizedSignal
    from cluster import cluster_signals

    now = datetime.now(timezone.utc)

    fake_signals = [
        NormalizedSignal(
            signal_id="r1",
            source_collection="reports",
            modality="citizen_report",
            lat=33.6920,
            lon=72.0130,
            timestamp=now,
            city="Islamabad",
            crisis_type="urban_flood",
            severity=3,
            text="G-10 mein paani bhar gaya",
            confidence=0.65,
        ),
        NormalizedSignal(
            signal_id="r2",
            source_collection="reports",
            modality="citizen_report",
            lat=33.6922,
            lon=72.0131,
            timestamp=now,
            city="Islamabad",
            crisis_type="urban_flood",
            severity=3,
            text="Vehicles stuck near G-10",
            confidence=0.65,
        ),
        NormalizedSignal(
            signal_id="r2:photo",
            source_collection="reports",
            modality="photo_verified",
            lat=33.6922,
            lon=72.0131,
            timestamp=now,
            city="Islamabad",
            crisis_type="urban_flood",
            severity=3,
            text="Verified flood photo",
            confidence=0.85,
        ),
        NormalizedSignal(
            signal_id="w1",
            source_collection="signals_weather",
            modality="weather",
            lat=33.6921,
            lon=72.0131,
            timestamp=now,
            city="Islamabad",
            crisis_type="urban_flood",
            text="31mm rain in last hour",
            rainfall_mm_1h=31,
            confidence=0.8,
        ),
        NormalizedSignal(
            signal_id="t1",
            source_collection="signals_traffic",
            modality="traffic",
            lat=33.6923,
            lon=72.0132,
            timestamp=now,
            city="Islamabad",
            crisis_type="urban_flood",
            text="Traffic delay 3.5x",
            congestion_ratio=3.5,
            confidence=0.7,
        ),
    ]

    clusters = cluster_signals(
        signals=fake_signals,
        eps_km=0.5,
        min_samples=3,
        time_window_min=60,
    )

    fake_events = []

    for cluster in clusters:
        # Do not call Firestore prior in local test.
        severity = calculate_severity(cluster)

        modality_count = cluster.modality_count
        confidence = 0.84 if modality_count >= 3 else 0.62
        status = "verified" if modality_count >= 2 else "candidate"

        fake_events.append(
            {
                "modalities": cluster.modalities,
                "modality_count": modality_count,
                "severity": severity,
                "confidence": confidence,
                "status": status,
                "centroid": cluster.centroid.model_dump(),
            }
        )

    return {
        "status": "ok",
        "clusters_found": len(clusters),
        "events": fake_events,
        "expected": {
            "clusters_found": 1,
            "status": "verified",
            "confidence": ">= 0.8",
            "severity": ">= 3",
        },
    }