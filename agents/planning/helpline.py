"""
Smart Helpline Router (M10).

Resolves the best helpline given city, crisis type, and optional language.
Supports Firestore mode and local sample mode for manual tests.
"""

from __future__ import annotations

import logging
import os
from typing import Any

from google.cloud import firestore

logger = logging.getLogger("planning.helpline")

PROJECT_ID = os.getenv("PROJECT_ID", "mehfooz-prod")
HELPLINE_MODE = os.getenv("HELPLINE_MODE", "auto")  # firestore | local | auto

HELPLINE_FALLBACK = {
    "helpline_id": "edhi-fallback",
    "name": "Edhi Foundation",
    "number": "115",
    "cities": ["*"],
    "crisis_types": ["medical", "ambulance", "shelter", "flood", "urban_flood"],
    "language_support": ["ur"],
    "notes": "Nationwide ambulance fallback.",
}

LOCAL_SAMPLE_HELPLINES: list[dict[str, Any]] = [
    {
        "helpline_id": "cares-1122-ict",
        "name": "CARES 1122 Islamabad",
        "number": "1122",
        "cities": ["Islamabad"],
        "crisis_types": ["fire", "medical", "road_incident", "flood", "urban_flood", "building_collapse"],
        "language_support": ["ur", "en"],
        "notes": "ICT only. 24/7 water rescue and trauma response.",
    },
    {
        "helpline_id": "rescue-1122-punjab",
        "name": "Rescue 1122 Punjab",
        "number": "1122",
        "cities": ["Lahore", "Rawalpindi"],
        "crisis_types": ["fire", "medical", "road_incident", "flood", "urban_flood", "building_collapse"],
        "language_support": ["ur", "en"],
        "notes": "24/7 provincial emergency service Punjab.",
    },
    {
        "helpline_id": "chhipa-karachi",
        "name": "Chhipa Emergency",
        "number": "1020",
        "cities": ["Karachi"],
        "crisis_types": ["medical", "ambulance", "road_incident", "fire", "flood", "urban_flood"],
        "language_support": ["ur", "roman_ur"],
        "notes": "24/7 ambulance and rescue Karachi.",
    },
    {
        "helpline_id": "ndma-national",
        "name": "NDMA",
        "number": "1700",
        "cities": ["*"],
        "crisis_types": ["flood", "urban_flood", "flash_flood", "glof"],
        "language_support": ["ur", "en"],
        "notes": "National disaster coordination; water rescue liaison.",
    },
    {
        "helpline_id": "alkhidmat-national",
        "name": "Alkhidmat Foundation",
        "number": "042-35761999",
        "cities": ["Islamabad", "Rawalpindi", "Lahore", "Karachi"],
        "crisis_types": ["flood", "urban_flood", "heatwave", "shelter", "medical"],
        "language_support": ["ur", "roman_ur"],
        "notes": "Relief and rescue, major cities.",
    },
    HELPLINE_FALLBACK,
]


def _normalize(value: str | None) -> str:
    return (value or "").strip().lower()


def _list_contains(items: list[str], value: str) -> bool:
    target = _normalize(value)
    for item in items:
        if _normalize(item) == target:
            return True
    return False


def _has_water_rescue(notes: str | None) -> bool:
    return "water rescue" in _normalize(notes)


def _valid_number(number: str | None) -> bool:
    if not number:
        return False
    digits = [c for c in number if c.isdigit()]
    return len(digits) > 0


def _score_candidate(
    candidate: dict[str, Any],
    city: str,
    crisis_type: str,
    language: str | None,
) -> tuple[int, int, bool]:
    city_exact = _list_contains(candidate.get("cities", []), city)
    crisis_exact = _list_contains(candidate.get("crisis_types", []), crisis_type)
    language_match = False
    if language:
        language_match = _list_contains(candidate.get("language_support", []), language)

    score = 0
    if city_exact:
        score += 10
    if crisis_exact:
        score += 5

    if crisis_type in {"flood", "urban_flood"} and _has_water_rescue(candidate.get("notes")):
        score += 8

    if language_match:
        score += 2

    return score, (1 if city_exact else 0), language_match


def _classify_priority(candidate: dict[str, Any], city: str, crisis_type: str) -> int:
    city_exact = _list_contains(candidate.get("cities", []), city)
    city_wildcard = _list_contains(candidate.get("cities", []), "*")
    crisis_exact = _list_contains(candidate.get("crisis_types", []), crisis_type)
    crisis_wildcard = _list_contains(candidate.get("crisis_types", []), "*")

    if city_exact and crisis_exact:
        return 1
    if city_exact and crisis_wildcard:
        return 2
    if city_wildcard and (crisis_exact or crisis_wildcard):
        return 3

    return 9


def _reason_for_priority(priority: int, city: str, crisis_type: str) -> str:
    if priority == 1:
        return "Exact city and crisis match."
    if priority == 2:
        return "Exact city with generalized crisis coverage."
    if priority == 3:
        return "Wildcard city with crisis match."
    return "Fallback to nationwide Edhi Foundation."


def _confidence_for(priority: int, score: int) -> float:
    base = {1: 0.95, 2: 0.9, 3: 0.8}.get(priority, 0.6)
    bump = min(score, 30) / 300
    return round(min(0.99, base + bump), 2)


def _load_firestore_helplines() -> list[dict[str, Any]]:
    db = firestore.Client(project=PROJECT_ID)
    results = []
    for doc in db.collection("helplines").stream():
        data = doc.to_dict() or {}
        data["helpline_id"] = data.get("helpline_id", doc.id)
        results.append(data)
    return results


def _get_candidates(mode: str) -> list[dict[str, Any]]:
    mode_norm = _normalize(mode)
    if mode_norm == "local":
        return list(LOCAL_SAMPLE_HELPLINES)

    if mode_norm in {"firestore", "auto"}:
        try:
            firestore_candidates = _load_firestore_helplines()
            if firestore_candidates:
                return firestore_candidates
        except Exception as exc:
            logger.warning("Firestore helpline lookup failed: %s", exc)

        if mode_norm == "auto":
            return list(LOCAL_SAMPLE_HELPLINES)

    return []


def resolve_helpline(
    city: str,
    crisis_type: str,
    language: str | None = None,
    mode: str | None = None,
) -> dict[str, Any]:
    """
    Resolve the best helpline record.

    Returns a dict containing helpline fields plus confidence + reason.
    """

    if not city or not crisis_type:
        fallback = dict(HELPLINE_FALLBACK)
        fallback["confidence"] = 0.6
        fallback["reason"] = "Fallback to nationwide Edhi Foundation."
        return fallback

    candidates = _get_candidates(mode or HELPLINE_MODE)
    crisis_type_norm = _normalize(crisis_type)

    viable = []
    for candidate in candidates:
        if not _valid_number(candidate.get("number")):
            continue

        city_exact = _list_contains(candidate.get("cities", []), city)
        city_wildcard = _list_contains(candidate.get("cities", []), "*")
        crisis_exact = _list_contains(candidate.get("crisis_types", []), crisis_type_norm)
        crisis_wildcard = _list_contains(candidate.get("crisis_types", []), "*")

        if not (city_exact or city_wildcard):
            continue
        if not (crisis_exact or crisis_wildcard):
            continue

        priority = _classify_priority(candidate, city, crisis_type_norm)
        score, _, language_match = _score_candidate(candidate, city, crisis_type_norm, language)
        viable.append((priority, score, language_match, candidate))

    if not viable:
        fallback = dict(HELPLINE_FALLBACK)
        fallback["confidence"] = 0.6
        fallback["reason"] = "Fallback to nationwide Edhi Foundation."
        return fallback

    viable.sort(key=lambda item: (item[0], -item[1], -int(item[2])))
    priority, score, _, selected = viable[0]

    result = dict(selected)
    result["confidence"] = _confidence_for(priority, score)
    result["reason"] = _reason_for_priority(priority, city, crisis_type_norm)
    return result


def run_helpline_tests(local_only: bool = True) -> tuple[bool, list[str]]:
    """Run M10 test cases. Returns (passed, errors)."""

    errors = []
    mode = "local" if local_only else "auto"

    def check(case_name: str, city: str, crisis: str, expected_name: str):
        result = resolve_helpline(
            city=city,
            crisis_type=crisis,
            use_firestore=(not local_only),
            mode=mode,
        )
        if result.get("name") != expected_name:
            errors.append(
                f"{case_name}: expected {expected_name}, got {result.get('name')}"
            )

    check("case_1", "Islamabad", "flood", "CARES 1122 Islamabad")
    check("case_2", "Lahore", "fire", "Rescue 1122 Punjab")
    check("case_3", "Karachi", "urban_flood", "Chhipa Emergency")
    check("case_4", "Unknown", "unknown", "Edhi Foundation")
    check("case_5", "Karachi", "medical", "Chhipa Emergency")

    return len(errors) == 0, errors
