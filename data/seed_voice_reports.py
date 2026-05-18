"""
M8 — Voice Report Seed Data.

Seeds Firestore with 4 pre-normalized voice reports matching the
spec's demo test phrases, so the demo can show the full pipeline
even if STT/Gemini haven't run yet.

Run: python seed_voice_reports.py
Requires: GOOGLE_APPLICATION_CREDENTIALS set to service account key.
"""

import json
import sys
import uuid
from datetime import datetime, timezone

try:
    from google.cloud import firestore
except ImportError:
    print("Install google-cloud-firestore: pip install google-cloud-firestore")
    sys.exit(1)

PROJECT_ID = "mehfooz-prod"

# ─── Four demo phrases from M8 spec ───
DEMO_REPORTS = [
    {
        "user_id": "demo_user_g10",
        "voice_url": "gs://mehfooz-prod.appspot.com/voice/demo/phrase1.m4a",
        "voice_duration_seconds": 8,
        "text_raw": "G-10 markaz ke paas paani bhar gaya, gaariyan phans gayi hain",
        "text_normalized": "Water has filled up near G-10 Markaz, cars are stuck.",
        "language_detected": "roman_ur",
        "crisis_type_user": "flood",
        "crisis_type_inferred": "urban_flood",
        "severity_user": 3,
        "location": firestore.GeoPoint(33.6920, 73.0130),
        "geo_accuracy_m": 25.0,
        "photo_urls": [],
        "vision_verified": False,
        "vision_confidence": 0,
        "linked_event_id": None,
        "_source": "voice",
        "_voice_processed": True,
        "_location_hints": ["G-10 Markaz", "Islamabad"],
        "_is_demo_seed": True,
        "created_at": datetime.now(timezone.utc),
    },
    {
        "user_id": "demo_user_lakhani",
        "voice_url": "gs://mehfooz-prod.appspot.com/voice/demo/phrase2.m4a",
        "voice_duration_seconds": 7,
        "text_raw": "Lakhani underpass pe ghutnon tak paani hai, koi mat aaye",
        "text_normalized": "Knee-deep water at Lakhani underpass, do not come here.",
        "language_detected": "roman_ur",
        "crisis_type_user": "flood",
        "crisis_type_inferred": "flash_flood",
        "severity_user": 4,
        "location": firestore.GeoPoint(33.7050, 73.0450),
        "geo_accuracy_m": 35.0,
        "photo_urls": [],
        "vision_verified": False,
        "vision_confidence": 0,
        "linked_event_id": None,
        "_source": "voice",
        "_voice_processed": True,
        "_location_hints": ["Lakhani underpass", "Islamabad"],
        "_is_demo_seed": True,
        "created_at": datetime.now(timezone.utc),
    },
    {
        "user_id": "demo_user_faisal",
        "voice_url": "gs://mehfooz-prod.appspot.com/voice/demo/phrase3.m4a",
        "voice_duration_seconds": 9,
        "text_raw": "Sharah-e-Faisal pe Drigh Road ke pass traffic bilkul band hai",
        "text_normalized": "Traffic completely blocked on Shahra-e-Faisal near Drigh Road.",
        "language_detected": "roman_ur",
        "crisis_type_user": "road_incident",
        "crisis_type_inferred": "road_incident",
        "severity_user": 2,
        "location": firestore.GeoPoint(24.8700, 67.0500),
        "geo_accuracy_m": 50.0,
        "photo_urls": [],
        "vision_verified": False,
        "vision_confidence": 0,
        "linked_event_id": None,
        "_source": "voice",
        "_voice_processed": True,
        "_location_hints": ["Shahra-e-Faisal", "Drigh Road", "Karachi"],
        "_is_demo_seed": True,
        "created_at": datetime.now(timezone.utc),
    },
    {
        "user_id": "demo_user_mosque",
        "voice_url": "gs://mehfooz-prod.appspot.com/voice/demo/phrase4.m4a",
        "voice_duration_seconds": 6,
        "text_raw": "Heavy flooding near Faisal Mosque parking, water rising fast",
        "text_normalized": "Heavy flooding near Faisal Mosque parking, water rising fast.",
        "language_detected": "en",
        "crisis_type_user": "flood",
        "crisis_type_inferred": "flood",
        "severity_user": 4,
        "location": firestore.GeoPoint(33.7295, 73.0372),
        "geo_accuracy_m": 20.0,
        "photo_urls": [],
        "vision_verified": False,
        "vision_confidence": 0,
        "linked_event_id": None,
        "_source": "voice",
        "_voice_processed": True,
        "_location_hints": ["Faisal Mosque", "Islamabad"],
        "_is_demo_seed": True,
        "created_at": datetime.now(timezone.utc),
    },
]


def seed_voice_reports():
    db = firestore.Client(project=PROJECT_ID)
    collection = db.collection("reports")

    print(f"Seeding {len(DEMO_REPORTS)} demo voice reports...")

    # Check for existing demo seeds to avoid duplicates
    existing = list(
        collection.where("_is_demo_seed", "==", True).stream()
    )
    if existing:
        print(f"Found {len(existing)} existing demo seeds. Deleting...")
        for doc in existing:
            doc.reference.delete()

    for i, report in enumerate(DEMO_REPORTS):
        doc_id = f"demo_voice_{uuid.uuid4().hex[:8]}"
        collection.document(doc_id).set(report)
        lang = report["language_detected"]
        crisis = report["crisis_type_inferred"]
        severity = report["severity_user"]
        print(
            f"  [{i+1}/{len(DEMO_REPORTS)}] {doc_id}: "
            f"lang={lang}, crisis={crisis}, severity={severity}"
        )

    print("\nDone! Voice report seeds written.")
    print(
        "\nExpected pipeline:\n"
        "  Voice report (with _source=voice, _voice_processed=True)\n"
        "  → Ingestion agent picks up text_normalized\n"
        "  → Detection agent corroborates with weather/traffic\n"
        "  → Planning agent generates user actions\n"
        "  → Simulation agent dispatches to mock endpoints\n"
    )


if __name__ == "__main__":
    seed_voice_reports()
