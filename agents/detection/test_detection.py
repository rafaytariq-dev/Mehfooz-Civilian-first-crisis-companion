"""
Basic tests for Detection Agent.

Run without pytest:
python test_detection.py

Run with pytest:
python -m pytest test_detection.py
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from cluster import cluster_signals
from models import NormalizedSignal
from agent import calculate_severity


def test_cluster_signals_finds_one_cluster():
    now = datetime.now(timezone.utc)

    signals = [
        NormalizedSignal(
            signal_id="r1",
            source_collection="reports",
            modality="citizen_report",
            lat=33.6920,
            lon=72.0130,
            timestamp=now,
            crisis_type="urban_flood",
            severity=3,
        ),
        NormalizedSignal(
            signal_id="r2",
            source_collection="reports",
            modality="citizen_report",
            lat=33.6921,
            lon=72.0131,
            timestamp=now,
            crisis_type="urban_flood",
            severity=3,
        ),
        NormalizedSignal(
            signal_id="w1",
            source_collection="signals_weather",
            modality="weather",
            lat=33.6922,
            lon=72.0132,
            timestamp=now,
            crisis_type="urban_flood",
            rainfall_mm_1h=30,
        ),
    ]

    clusters = cluster_signals(
        signals=signals,
        eps_km=0.5,
        min_samples=3,
        time_window_min=60,
    )

    assert len(clusters) == 1
    assert clusters[0].modality_count == 2
    assert "citizen_report" in clusters[0].modalities
    assert "weather" in clusters[0].modalities


def test_old_signals_are_ignored():
    now = datetime.now(timezone.utc)

    signals = [
        NormalizedSignal(
            signal_id="old1",
            source_collection="reports",
            modality="citizen_report",
            lat=33.6920,
            lon=72.0130,
            timestamp=now - timedelta(hours=5),
        ),
        NormalizedSignal(
            signal_id="old2",
            source_collection="reports",
            modality="citizen_report",
            lat=33.6921,
            lon=72.0131,
            timestamp=now - timedelta(hours=5),
        ),
        NormalizedSignal(
            signal_id="old3",
            source_collection="signals_weather",
            modality="weather",
            lat=33.6922,
            lon=72.0132,
            timestamp=now - timedelta(hours=5),
        ),
    ]

    clusters = cluster_signals(
        signals=signals,
        eps_km=0.5,
        min_samples=3,
        time_window_min=60,
    )

    assert len(clusters) == 0


def test_severity_increases_with_rain_and_traffic():
    now = datetime.now(timezone.utc)

    signals = [
        NormalizedSignal(
            signal_id="r1",
            source_collection="reports",
            modality="citizen_report",
            lat=33.6920,
            lon=72.0130,
            timestamp=now,
            severity=3,
            crisis_type="urban_flood",
        ),
        NormalizedSignal(
            signal_id="w1",
            source_collection="signals_weather",
            modality="weather",
            lat=33.6921,
            lon=72.0131,
            timestamp=now,
            rainfall_mm_1h=30,
            crisis_type="urban_flood",
        ),
        NormalizedSignal(
            signal_id="t1",
            source_collection="signals_traffic",
            modality="traffic",
            lat=33.6922,
            lon=72.0132,
            timestamp=now,
            congestion_ratio=3.2,
            crisis_type="urban_flood",
        ),
    ]

    clusters = cluster_signals(
        signals=signals,
        eps_km=0.5,
        min_samples=3,
        time_window_min=60,
    )

    severity = calculate_severity(clusters[0])

    assert severity >= 4
    assert severity <= 5


if __name__ == "__main__":
    test_cluster_signals_finds_one_cluster()
    test_old_signals_are_ignored()
    test_severity_increases_with_rain_and_traffic()

    print("All detection tests passed ✅")