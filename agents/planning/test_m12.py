"""
M12 — Women's Safe Route Layer Tests.

Tests:
1. _safety_penalty: residential, unlit, isolated penalty coefficients
2. compute_routes(safety_mode=False) — sorted by flood risk only
3. compute_routes(safety_mode=True)  — sorted by safety_penalty+flood, different ordering
4. Route reasoning text contains expected M12 spec phrases
5. OSM cache lookup path (mocked cache)
"""

from __future__ import annotations
import sys
import os
import math
import logging

# Allow import from parent dir
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# ─── Minimal stubs so tools.py can import without Firestore ───
import types

# Stub google.cloud.firestore
fc = types.ModuleType("google")
fc.cloud = types.ModuleType("google.cloud")
fc.cloud.firestore = types.ModuleType("google.cloud.firestore")
fc.cloud.firestore.Client = lambda **kw: None
fc.cloud.firestore.GeoPoint = lambda lat, lon: (lat, lon)
sys.modules["google"] = fc
sys.modules["google.cloud"] = fc.cloud
sys.modules["google.cloud.firestore"] = fc.cloud.firestore

# Stub google.maps
gm = types.ModuleType("google.maps")
gm.routing_v2 = None
sys.modules["google.maps"] = gm
sys.modules["google.maps.routing_v2"] = types.ModuleType("google.maps.routing_v2")

from tools import (
    _safety_penalty,
    _build_safety_reasoning,
    _generate_mock_steps,
    compute_routes,
    distance_m,
    _PENALIZED_ROAD_CLASSES,
    _LIT_HIGHWAY_CLASSES,
)
from models import GeoLocation

logging.disable(logging.CRITICAL)

# ─── Test helpers ───

def _assert(condition: bool, msg: str) -> None:
    if condition:
        print(f"  [OK] {msg}")
    else:
        print(f"  [ERR] FAILED: {msg}")
        raise AssertionError(msg)

def _section(name: str) -> None:
    print(f"\n{'='*60}\n{name}\n{'='*60}")

# ─── Tests ───

def test_safety_penalty_residential():
    _section("T1: _safety_penalty — residential road")
    steps = [
        {"distance_m": 1000, "road_class": "residential",
         "is_unlit_assumed": False, "passes_isolated_area": False},
    ]
    penalty = _safety_penalty(steps)
    # Expected: 1000 * 0.5 = 500.0
    _assert(abs(penalty - 500.0) < 0.01, f"residential 1000m → 500.0 (got {penalty})")


def test_safety_penalty_unlit():
    _section("T2: _safety_penalty — unlit road")
    steps = [
        {"distance_m": 2000, "road_class": "tertiary",
         "is_unlit_assumed": True, "passes_isolated_area": False},
    ]
    penalty = _safety_penalty(steps)
    # Expected: 2000 * 0.3 = 600.0
    _assert(abs(penalty - 600.0) < 0.01, f"unlit 2000m → 600.0 (got {penalty})")


def test_safety_penalty_isolated():
    _section("T3: _safety_penalty — isolated area")
    steps = [
        {"distance_m": 500, "road_class": "primary",
         "is_unlit_assumed": False, "passes_isolated_area": True},
    ]
    penalty = _safety_penalty(steps)
    # Expected: 500 * 0.4 = 200.0
    _assert(abs(penalty - 200.0) < 0.01, f"isolated 500m → 200.0 (got {penalty})")


def test_safety_penalty_stacked():
    _section("T4: _safety_penalty — stacked penalties (residential + unlit + isolated)")
    steps = [
        {"distance_m": 1000, "road_class": "service",
         "is_unlit_assumed": True, "passes_isolated_area": True},
    ]
    penalty = _safety_penalty(steps)
    # Expected: 1000 * (0.5 + 0.3 + 0.4) = 1200.0
    _assert(abs(penalty - 1200.0) < 0.01, f"all penalties 1000m → 1200.0 (got {penalty})")


def test_safety_penalty_clean_route():
    _section("T5: _safety_penalty — clean primary/secondary route")
    steps = [
        {"distance_m": 5000, "road_class": "primary",
         "is_unlit_assumed": False, "passes_isolated_area": False},
        {"distance_m": 3000, "road_class": "secondary",
         "is_unlit_assumed": False, "passes_isolated_area": False},
    ]
    penalty = _safety_penalty(steps)
    # Expected: 0.0 — no penalties on main roads
    _assert(penalty == 0.0, f"clean primary+secondary → 0.0 (got {penalty})")


def test_compute_routes_normal_mode():
    _section("T6: compute_routes — normal mode (flood risk only)")
    # Islamabad G-10 → Faisal Mosque
    routes = compute_routes(
        origin_lat=33.692, origin_lon=73.013,
        destination_lat=33.7295, destination_lon=73.0372,
        safety_mode=False,
    )
    _assert(len(routes) == 3, f"3 routes returned (got {len(routes)})")
    _assert(not routes[0].passes_through_flooded,
            "First route (safest) doesn't pass through flood zone")
    # Routes sorted: non-flooded first
    flooded_indices = [i for i, r in enumerate(routes) if r.passes_through_flooded]
    _assert(all(i > 0 for i in flooded_indices),
            "Flooded routes ranked below non-flooded in normal mode")
    print(f"  Route risk scores: {[r.risk_score for r in routes]}")


def test_compute_routes_safety_mode():
    _section("T7: compute_routes — safety_mode=True (M12 Women's Safe Route)")
    routes_normal = compute_routes(
        origin_lat=33.692, origin_lon=73.013,
        destination_lat=33.7295, destination_lon=73.0372,
        safety_mode=False,
    )
    routes_safe = compute_routes(
        origin_lat=33.692, origin_lon=73.013,
        destination_lat=33.7295, destination_lon=73.0372,
        safety_mode=True,
    )

    _assert(len(routes_safe) == 3, f"3 routes returned in safety mode (got {len(routes_safe)})")

    # In safety mode, risk_scores should differ from normal mode due to penalty
    normal_scores = [r.risk_score for r in routes_normal]
    safe_scores = [r.risk_score for r in routes_safe]
    _assert(safe_scores != normal_scores,
            f"risk scores differ between normal {normal_scores} and safety {safe_scores} mode")

    # Flooded routes still ranked last
    flooded_indices = [i for i, r in enumerate(routes_safe) if r.passes_through_flooded]
    _assert(all(i > 0 for i in flooded_indices),
            "Flooded routes still ranked below non-flooded in safety mode")

    print(f"  Normal risk scores: {normal_scores}")
    print(f"  Safety risk scores: {safe_scores}")


def test_route_reasoning_text_normal():
    _section("T8: Route reasoning text — normal mode")
    routes = compute_routes(
        origin_lat=33.692, origin_lon=73.013,
        destination_lat=33.7295, destination_lon=73.0372,
        safety_mode=False,
    )
    for i, r in enumerate(routes):
        _assert(len(r.risk_explanation) > 10,
                f"Route {i+1} has non-empty reasoning: '{r.risk_explanation[:60]}'")


def test_route_reasoning_text_safety_mode():
    _section("T9: Route reasoning text — safety mode (M12 spec phrases)")
    routes = compute_routes(
        origin_lat=33.692, origin_lon=73.013,
        destination_lat=33.7295, destination_lon=73.0372,
        safety_mode=True,
    )
    # Best route should mention safe roads
    _assert("safe" in routes[0].risk_explanation.lower() or
            "main" in routes[0].risk_explanation.lower() or
            "well-lit" in routes[0].risk_explanation.lower(),
            f"Best route reasoning mentions safety: '{routes[0].risk_explanation}'")

    # A route with back lanes should mention the issue
    risky = [r for r in routes if r.risk_score > 0.3]
    if risky:
        reasoning = risky[0].risk_explanation.lower()
        has_issue = any(kw in reasoning for kw in
                        ["back lanes", "poorly-lit", "isolated", "penalty", "moderate"])
        _assert(has_issue,
                f"Risky route mentions issue: '{risky[0].risk_explanation}'")

    print(f"  Route 1: {routes[0].risk_explanation}")
    print(f"  Route 2: {routes[1].risk_explanation}")
    print(f"  Route 3: {routes[2].risk_explanation}")


def test_osm_cache_lookup():
    _section("T10: _safety_penalty with OSM cache (mocked road_segments data)")
    mock_cache = {
        "33.69_73.01": {
            "highway": "service",
            "lit": "no",
            "is_isolated": True,
            "penalty_per_m": 1.2,  # pre-computed: 0.5+0.3+0.4
        }
    }
    steps = [
        {"distance_m": 1000, "road_class": "service",
         "cell_id": "33.69_73.01",
         "is_unlit_assumed": True, "passes_isolated_area": True},
    ]
    penalty = _safety_penalty(steps, road_segments_cache=mock_cache)
    # With pre-computed penalty_per_m=1.2: 1000 * 1.2 = 1200.0
    _assert(abs(penalty - 1200.0) < 0.01,
            f"OSM cache pre-computed penalty 1000m → 1200.0 (got {penalty})")


def test_prefer_safe_roads_alias():
    _section("T11: prefer_safe_roads=True is equivalent to safety_mode=True")
    routes_safe = compute_routes(
        origin_lat=33.692, origin_lon=73.013,
        destination_lat=33.7295, destination_lon=73.0372,
        safety_mode=True,
    )
    routes_prefer = compute_routes(
        origin_lat=33.692, origin_lon=73.013,
        destination_lat=33.7295, destination_lon=73.0372,
        prefer_safe_roads=True,
    )
    scores_safe = [r.risk_score for r in routes_safe]
    scores_prefer = [r.risk_score for r in routes_prefer]
    _assert(scores_safe == scores_prefer,
            f"safety_mode=True == prefer_safe_roads=True: {scores_safe}")


def test_exit_criteria_different_routes():
    _section("T12: Exit criteria — same origin/destination returns DIFFERENT routes with toggle")
    # This is the key M12 spec exit criterion
    routes_off = compute_routes(33.692, 73.013, 33.7295, 73.0372, safety_mode=False)
    routes_on  = compute_routes(33.692, 73.013, 33.7295, 73.0372, safety_mode=True)

    explanations_off = [r.risk_explanation for r in routes_off]
    explanations_on  = [r.risk_explanation for r in routes_on]

    _assert(explanations_off != explanations_on,
            "Route explanations differ between toggle OFF and toggle ON")

    scores_off = [round(r.risk_score, 3) for r in routes_off]
    scores_on  = [round(r.risk_score, 3) for r in routes_on]
    _assert(scores_off != scores_on,
            f"Risk scores differ: OFF={scores_off}, ON={scores_on}")
    print(f"  Toggle OFF risk scores: {scores_off}")
    print(f"  Toggle ON  risk scores: {scores_on}")


def test_penalty_constants():
    _section("T13: Spec-defined penalty constants")
    steps_r = [{"distance_m": 100, "road_class": "residential",
                 "is_unlit_assumed": False, "passes_isolated_area": False}]
    steps_u = [{"distance_m": 100, "road_class": "primary",
                 "is_unlit_assumed": True, "passes_isolated_area": False}]
    steps_i = [{"distance_m": 100, "road_class": "primary",
                 "is_unlit_assumed": False, "passes_isolated_area": True}]

    _assert(abs(_safety_penalty(steps_r) - 50.0) < 0.01,
            "residential: 100m * 0.5 = 50.0")
    _assert(abs(_safety_penalty(steps_u) - 30.0) < 0.01,
            "unlit: 100m * 0.3 = 30.0")
    _assert(abs(_safety_penalty(steps_i) - 40.0) < 0.01,
            "isolated: 100m * 0.4 = 40.0")


# ─── Main ───

if __name__ == "__main__":
    tests = [
        test_safety_penalty_residential,
        test_safety_penalty_unlit,
        test_safety_penalty_isolated,
        test_safety_penalty_stacked,
        test_safety_penalty_clean_route,
        test_compute_routes_normal_mode,
        test_compute_routes_safety_mode,
        test_route_reasoning_text_normal,
        test_route_reasoning_text_safety_mode,
        test_osm_cache_lookup,
        test_prefer_safe_roads_alias,
        test_exit_criteria_different_routes,
        test_penalty_constants,
    ]

    passed = 0
    failed = 0
    for t in tests:
        try:
            t()
            passed += 1
        except AssertionError as e:
            print(f"  [FAIL] {e}")
            failed += 1
        except Exception as e:
            print(f"  [ERR] Unexpected error: {e}")
            failed += 1

    print(f"\n{'='*60}")
    print(f"M12 Test Results: {passed} passed, {failed} failed")
    print(f"{'='*60}\n")
    sys.exit(0 if failed == 0 else 1)
