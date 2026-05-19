"""
M12 — Seed Firestore road_segments collection with demo data.

Seeds representative road segments for Islamabad G-10 → Faisal Mosque
corridor so the Planning Agent can demonstrate safety mode immediately
without running the full Overpass enrichment script.

Usage: python seed_road_segments.py
Requires: GOOGLE_APPLICATION_CREDENTIALS
"""

import sys
import os

try:
    from google.cloud import firestore
except ImportError:
    print("Install: pip install google-cloud-firestore")
    sys.exit(1)

PROJECT_ID = os.getenv("PROJECT_ID", "mehfooz-prod")

# Representative segments for the Islamabad demo corridor
DEMO_SEGMENTS = [
    # ── Variant 0: Safe route (Stadium Road / Jinnah Ave / Main Blvd) ──
    {
        "way_id": "demo_001",
        "cell_id": "33.69_73.01",
        "city": "Islamabad",
        "highway": "primary",
        "name": "Stadium Road / Shahrah-e-Faisal",
        "lit": "yes",
        "is_isolated": False,
        "penalty_per_m": 0.0,
        "centroid": {"latitude": 33.692, "longitude": 73.013},
        "_enriched_by": "demo_seed",
    },
    {
        "way_id": "demo_002",
        "cell_id": "33.71_73.02",
        "city": "Islamabad",
        "highway": "secondary",
        "name": "Main Boulevard",
        "lit": "yes",
        "is_isolated": False,
        "penalty_per_m": 0.0,
        "centroid": {"latitude": 33.710, "longitude": 73.020},
        "_enriched_by": "demo_seed",
    },
    {
        "way_id": "demo_003",
        "cell_id": "33.72_73.03",
        "city": "Islamabad",
        "highway": "primary",
        "name": "Jinnah Avenue",
        "lit": "yes",
        "is_isolated": False,
        "penalty_per_m": 0.0,
        "centroid": {"latitude": 33.720, "longitude": 73.030},
        "_enriched_by": "demo_seed",
    },
    # ── Variant 1: Risky route (back lanes, industrial bypass) ──
    {
        "way_id": "demo_004",
        "cell_id": "33.70_73.04",
        "city": "Islamabad",
        "highway": "residential",
        "name": "Korangi back lanes",
        "lit": "unknown",
        "is_isolated": False,
        "penalty_per_m": 0.8,    # 0.5 residential + 0.3 unlit
        "centroid": {"latitude": 33.700, "longitude": 73.040},
        "_enriched_by": "demo_seed",
    },
    {
        "way_id": "demo_005",
        "cell_id": "33.71_73.05",
        "city": "Islamabad",
        "highway": "service",
        "name": "Industrial Area bypass",
        "lit": "no",
        "is_isolated": True,
        "penalty_per_m": 1.2,    # 0.5 service + 0.3 unlit + 0.4 isolated
        "centroid": {"latitude": 33.710, "longitude": 73.050},
        "_enriched_by": "demo_seed",
    },
    # ── Variant 2: Longer safe route (Margalla Ave / F-10 / G-9 link) ──
    {
        "way_id": "demo_006",
        "cell_id": "33.72_73.02",
        "city": "Islamabad",
        "highway": "primary",
        "name": "Margalla Avenue",
        "lit": "yes",
        "is_isolated": False,
        "penalty_per_m": 0.0,
        "centroid": {"latitude": 33.720, "longitude": 73.020},
        "_enriched_by": "demo_seed",
    },
    {
        "way_id": "demo_007",
        "cell_id": "33.73_73.03",
        "city": "Islamabad",
        "highway": "secondary",
        "name": "F-10 Markaz Road",
        "lit": "yes",
        "is_isolated": False,
        "penalty_per_m": 0.0,
        "centroid": {"latitude": 33.730, "longitude": 73.030},
        "_enriched_by": "demo_seed",
    },
    {
        "way_id": "demo_008",
        "cell_id": "33.72_73.04",
        "city": "Islamabad",
        "highway": "tertiary",
        "name": "G-9 Link",
        "lit": "unknown",
        "is_isolated": False,
        "penalty_per_m": 0.3,    # 0.3 unlit (tertiary at night)
        "centroid": {"latitude": 33.720, "longitude": 73.040},
        "_enriched_by": "demo_seed",
    },
    # ── Karachi segments for Shahrah-e-Faisal / Drigh Road corridor ──
    {
        "way_id": "demo_khi_001",
        "cell_id": "24.87_67.05",
        "city": "Karachi",
        "highway": "primary",
        "name": "Shahrah-e-Faisal",
        "lit": "yes",
        "is_isolated": False,
        "penalty_per_m": 0.0,
        "centroid": {"latitude": 24.870, "longitude": 67.050},
        "_enriched_by": "demo_seed",
    },
    {
        "way_id": "demo_khi_002",
        "cell_id": "24.88_67.07",
        "city": "Karachi",
        "highway": "service",
        "name": "Lyari back road",
        "lit": "no",
        "is_isolated": True,
        "penalty_per_m": 1.2,
        "centroid": {"latitude": 24.880, "longitude": 67.070},
        "_enriched_by": "demo_seed",
    },
]


def seed():
    db = firestore.Client(project=PROJECT_ID)
    print(f"Seeding {len(DEMO_SEGMENTS)} demo road segments...")

    # Clean existing demo seeds
    existing = list(db.collection("road_segments").where("_enriched_by", "==", "demo_seed").stream())
    if existing:
        print(f"  Removing {len(existing)} existing demo seeds...")
        for doc in existing:
            doc.reference.delete()

    batch = db.batch()
    for seg in DEMO_SEGMENTS:
        ref = db.collection("road_segments").document(seg["way_id"])
        batch.set(ref, seg)
    batch.commit()

    print(f"Done. {len(DEMO_SEGMENTS)} road segments seeded.")
    print("\nThe Planning Agent will now use these for safety_mode routing in M12.")


if __name__ == "__main__":
    seed()
