"""
Detection Agent — spatial-temporal clustering.

Uses DBSCAN with haversine distance.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Iterable

import numpy as np
from sklearn.cluster import DBSCAN

from models import DetectedCluster, GeoLocation, NormalizedSignal


EARTH_RADIUS_KM = 6371.0


def _to_aware_utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def filter_recent_signals(
    signals: Iterable[NormalizedSignal],
    time_window_min: int,
) -> list[NormalizedSignal]:
    now = datetime.now(timezone.utc)
    recent: list[NormalizedSignal] = []

    for signal in signals:
        ts = _to_aware_utc(signal.timestamp)
        age_seconds = (now - ts).total_seconds()

        if age_seconds <= time_window_min * 60:
            recent.append(signal)

    return recent


def build_centroid(signals: list[NormalizedSignal]) -> GeoLocation:
    lat = sum(s.lat for s in signals) / len(signals)
    lon = sum(s.lon for s in signals) / len(signals)

    return GeoLocation(latitude=lat, longitude=lon)


def build_polygon(
    signals: list[NormalizedSignal],
    padding_deg: float = 0.002,
) -> list[GeoLocation]:
    min_lat = min(s.lat for s in signals) - padding_deg
    max_lat = max(s.lat for s in signals) + padding_deg
    min_lon = min(s.lon for s in signals) - padding_deg
    max_lon = max(s.lon for s in signals) + padding_deg

    return [
        GeoLocation(latitude=max_lat, longitude=min_lon),
        GeoLocation(latitude=max_lat, longitude=max_lon),
        GeoLocation(latitude=min_lat, longitude=max_lon),
        GeoLocation(latitude=min_lat, longitude=min_lon),
    ]


def cluster_signals(
    signals: list[NormalizedSignal],
    eps_km: float = 0.5,
    min_samples: int = 3,
    time_window_min: int = 60,
) -> list[DetectedCluster]:
    """
    Spatial-temporal DBSCAN clustering.

    eps_km=0.5 means signals within 500 meters can form a cluster.
    """

    recent = filter_recent_signals(
        signals=signals,
        time_window_min=time_window_min,
    )

    if len(recent) < min_samples:
        return []

    coords = np.radians([[s.lat, s.lon] for s in recent])

    db = DBSCAN(
        eps=eps_km / EARTH_RADIUS_KM,
        min_samples=min_samples,
        metric="haversine",
    ).fit(coords)

    grouped: dict[int, list[NormalizedSignal]] = {}

    for signal, label in zip(recent, db.labels_):
        if label == -1:
            continue

        grouped.setdefault(int(label), []).append(signal)

    clusters: list[DetectedCluster] = []

    for label, cluster_items in grouped.items():
        modalities = sorted({s.modality for s in cluster_items})

        clusters.append(
            DetectedCluster(
                cluster_id=f"cluster-{label}",
                signals=cluster_items,
                centroid=build_centroid(cluster_items),
                polygon=build_polygon(cluster_items),
                modalities=modalities,
                modality_count=len(modalities),
            )
        )

    return clusters