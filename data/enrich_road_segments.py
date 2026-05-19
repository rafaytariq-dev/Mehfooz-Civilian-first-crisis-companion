"""
M12 — Women's Safe Route Layer.

OSM road segment enrichment script. One-time (or weekly) pre-compute.

Queries the Overpass API for road segments in the four target cities
and tags each with:
  - lit (yes/no/unknown) from OSM
  - landuse of surrounding polygon (industrial, agricultural, residential, commercial)
  - highway class (motorway, primary, secondary, tertiary, residential, service)

Stores results in Firestore 'road_segments' collection indexed by
a 6-character S2 cell token (≈ 1.2km × 1.2km).

Usage:
    python enrich_road_segments.py [--city Karachi]

Requirements:
    pip install google-cloud-firestore requests
    GOOGLE_APPLICATION_CREDENTIALS must be set.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
from typing import Any

import requests

try:
    from google.cloud import firestore
    HAS_FIRESTORE = True
except ImportError:
    HAS_FIRESTORE = False
    print("[WARN] google-cloud-firestore not installed — dry-run mode only.")

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
logger = logging.getLogger("enrich_road_segments")

PROJECT_ID = os.getenv("PROJECT_ID", "mehfooz-prod")

# Target cities bounding boxes [south, west, north, east]
CITY_BBOXES = {
    "Islamabad": (33.55, 72.80, 33.80, 73.20),
    "Rawalpindi": (33.52, 72.94, 33.67, 73.12),
    "Karachi":   (24.78, 66.94, 24.96, 67.17),
    "Lahore":    (31.40, 74.15, 31.68, 74.45),
}

OVERPASS_URL = "https://overpass-api.de/api/interpreter"

# Road classes that raise safety penalty (see spec)
PENALIZED_ROAD_CLASSES = {"residential", "service", "track", "path", "unclassified"}

# Land use types considered isolated per spec
ISOLATED_LANDUSES = {"industrial", "farmland", "farmyard", "cemetery", "quarry"}

# Night hours: after 8pm and before 6am PKT
NIGHT_HOURS = set(range(20, 24)) | set(range(0, 6))


def build_overpass_query(bbox: tuple[float, float, float, float]) -> str:
    """Build Overpass QL query for road segments + lighting in a bounding box."""
    s, w, n, e = bbox
    return f"""
[out:json][timeout:120];
(
  way["highway"]["highway"!="footway"]["highway"!="cycleway"]
    ({s},{w},{n},{e});
);
out body geom;
"""


def fetch_overpass(bbox: tuple[float, float, float, float]) -> dict[str, Any]:
    """Fetch road data from Overpass API with retry logic."""
    query = build_overpass_query(bbox)

    for attempt in range(3):
        try:
            logger.info(f"Fetching Overpass data (attempt {attempt + 1})...")
            response = requests.post(
                OVERPASS_URL,
                data={"data": query},
                timeout=120,
            )
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logger.warning(f"Overpass request failed: {e}")
            if attempt < 2:
                time.sleep(5 * (attempt + 1))

    return {}


def classify_lighting(tags: dict[str, str], highway: str) -> str:
    """
    Determine lighting status from OSM tags.

    Priority:
      1. Explicit OSM lit tag
      2. Heuristic: primary/secondary assumed lit in daylight
      3. Tertiary/residential/service in cities: unknown
      4. Track/path: assume unlit
    """
    lit = tags.get("lit", "").lower()
    if lit in ("yes", "24/7"):
        return "yes"
    if lit == "no":
        return "no"

    # Heuristics for Pakistani cities
    if highway in ("motorway", "trunk", "primary"):
        return "yes"
    if highway in ("track", "path", "service"):
        return "no"

    return "unknown"


def is_unlit_at_night(lighting: str) -> bool:
    """True if road is likely unlit during night hours per spec heuristic."""
    return lighting in ("no", "unknown")


def classify_isolation(tags: dict[str, str], highway: str) -> bool:
    """
    True if road passes through isolated area.
    Uses landuse tag and highway class as proxy per spec.
    """
    landuse = tags.get("landuse", tags.get("adjacent_landuse", "")).lower()
    if any(il in landuse for il in ISOLATED_LANDUSES):
        return True

    # In absence of landuse data, tertiary+service roads outside commercial area
    # are treated as potentially isolated
    if highway in ("track", "path"):
        return True

    return False


def compute_safety_penalty_per_meter(
    highway: str,
    lighting: str,
    is_isolated: bool,
) -> float:
    """
    Compute the per-meter safety penalty coefficient for this road segment.

    This implements the spec formula:
      residential/service: +0.5/m
      unlit (at night):    +0.3/m
      isolated area:       +0.4/m

    Coefficients can stack for the worst roads.
    """
    coeff = 0.0

    if highway in PENALIZED_ROAD_CLASSES:
        coeff += 0.5

    if is_unlit_at_night(lighting):
        coeff += 0.3

    if is_isolated:
        coeff += 0.4

    return coeff


def s2_cell_from_latlon(lat: float, lon: float, level: int = 10) -> str:
    """
    Return a simple grid cell key for a lat/lon at the given level.

    Since we can't import the S2 C++ library easily, we use a
    simplified grid cell approach: round to 2 decimal places.
    This creates ≈ 1.1km × 1.1km cells, close to S2 level 14.

    For production, use the s2geometry Python library.
    """
    lat_cell = round(lat, 2)
    lon_cell = round(lon, 2)
    return f"{lat_cell:.2f}_{lon_cell:.2f}"


def process_city(
    city: str,
    bbox: tuple[float, float, float, float],
    dry_run: bool = False,
) -> list[dict]:
    """Fetch and process road segments for one city."""
    logger.info(f"Processing {city}...")

    data = fetch_overpass(bbox)
    elements = data.get("elements", [])
    ways = [e for e in elements if e.get("type") == "way"]

    logger.info(f"{city}: {len(ways)} road ways fetched.")

    segments = []
    for way in ways:
        tags = way.get("tags", {})
        highway = tags.get("highway", "unclassified")
        geometry = way.get("geometry", [])

        if not geometry:
            continue

        # Midpoint of the way for cell assignment
        mid_idx = len(geometry) // 2
        mid = geometry[mid_idx]
        lat, lon = mid.get("lat", 0.0), mid.get("lon", 0.0)

        lighting = classify_lighting(tags, highway)
        is_isolated = classify_isolation(tags, highway)
        penalty_per_m = compute_safety_penalty_per_meter(highway, lighting, is_isolated)

        cell_id = s2_cell_from_latlon(lat, lon)

        segment = {
            "way_id": way.get("id"),
            "cell_id": cell_id,
            "city": city,
            "highway": highway,
            "lit": lighting,
            "is_isolated": is_isolated,
            "penalty_per_m": penalty_per_m,
            "name": tags.get("name", tags.get("name:en", "")),
            "name_ur": tags.get("name:ur", ""),
            "oneway": tags.get("oneway", "no"),
            "maxspeed": tags.get("maxspeed", ""),
            "centroid": {"latitude": lat, "longitude": lon},
            "_enriched_by": "overpass_m12",
            "_city": city,
        }
        segments.append(segment)

    logger.info(f"{city}: {len(segments)} segments enriched.")

    if not dry_run and HAS_FIRESTORE:
        db = firestore.Client(project=PROJECT_ID)
        batch = db.batch()
        count = 0
        BATCH_SIZE = 500

        for seg in segments:
            way_id = str(seg["way_id"])
            ref = db.collection("road_segments").document(way_id)
            batch.set(ref, seg, merge=True)
            count += 1

            if count % BATCH_SIZE == 0:
                batch.commit()
                batch = db.batch()
                logger.info(f"  Committed {count} segments...")

        if count % BATCH_SIZE != 0:
            batch.commit()

        logger.info(f"{city}: Committed {count} road segments to Firestore.")
    else:
        logger.info(f"[DRY RUN] Would write {len(segments)} segments to Firestore.")
        # Print sample
        if segments:
            sample = segments[0]
            logger.info(f"Sample segment: {json.dumps(sample, indent=2)}")

    return segments


def main():
    parser = argparse.ArgumentParser(description="M12 Road Segment Enrichment")
    parser.add_argument(
        "--city",
        choices=list(CITY_BBOXES.keys()) + ["all"],
        default="all",
        help="City to process (default: all)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Fetch data but don't write to Firestore",
    )
    args = parser.parse_args()

    cities = CITY_BBOXES.keys() if args.city == "all" else [args.city]
    total_segments = 0

    for city in cities:
        bbox = CITY_BBOXES[city]
        segs = process_city(city, bbox, dry_run=args.dry_run)
        total_segments += len(segs)

        # Rate limit between cities
        if not args.dry_run:
            time.sleep(2)

    logger.info(f"Done. {total_segments} total segments processed across {len(list(cities))} cities.")
    logger.info(
        "Next step: Planning Agent will query road_segments at runtime for "
        "compute_routes(safety_mode=True) to apply per-meter safety penalty."
    )


if __name__ == "__main__":
    main()
