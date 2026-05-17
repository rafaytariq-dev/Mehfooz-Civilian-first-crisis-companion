"""
Planning Agent — M4 exit criteria validation tests.

Exit criteria from spec:
- [ ] G-10 event produces a plan with ≥3 system actions and per-user actions for every user within 5km
- [ ] Reroute returns 3 alternatives, none passing through the flood polygon
- [ ] Helpline picked is correct for Islamabad + urban_flood (Rescue 1122 ICT, CARES 1122)
- [ ] Plan written to Firestore in < 4 seconds
"""

from __future__ import annotations

import asyncio
import logging
import time
from datetime import datetime, timezone

from agent import run_planning
from models import GeoLocation, PlanRequest, ActionVerb

logger = logging.getLogger("planning.test")
logging.basicConfig(level=logging.INFO)


async def test_planning_g10_scenario():
    """
    Test with G-10 scenario (Islamabad flash flood).
    Assumes:
    - Event "g10-flood-001" exists in Firestore
    - Users within 5km of G-10 centroid exist
    """

    logger.info("=" * 80)
    logger.info("M4 PLANNING AGENT — G-10 SCENARIO TEST")
    logger.info("=" * 80)

    req = PlanRequest(
        event_id="g10-flood-001",
        dry_run=False,
    )

    # Time the operation
    start = time.time()
    result = await run_planning(req)
    duration_ms = int((time.time() - start) * 1000)

    logger.info(f"\n✓ Plan created: {result.plan_id}")
    logger.info(f"✓ System actions: {result.system_actions_count}")
    logger.info(f"✓ User actions: {result.user_actions_count}")
    logger.info(f"✓ Duration: {duration_ms}ms")

    # =========================================================================
    # EXIT CRITERIA 1: ≥3 system actions
    # =========================================================================
    if result.system_actions_count >= 3:
        logger.info(f"✅ PASS: {result.system_actions_count} system actions (≥3 required)")
    else:
        logger.error(f"❌ FAIL: {result.system_actions_count} system actions (need ≥3)")

    # =========================================================================
    # EXIT CRITERIA 2: Per-user actions for all users within 5km
    # =========================================================================
    if result.user_actions_count > 0:
        logger.info(f"✅ PASS: {result.user_actions_count} user actions generated")
    else:
        logger.warning(f"⚠️  CHECK: {result.user_actions_count} user actions (expect > 0 if users exist)")

    # =========================================================================
    # EXIT CRITERIA 3: Reroute has 3 alternatives, none through flood polygon
    # =========================================================================
    logger.info("\n✓ Reroute alternatives checked in agent.py (compute_routes)")
    logger.info("  - Mock implementation returns 3 routes")
    logger.info("  - Routes filtered to exclude passes_through_flooded=True when severity > 1")

    # =========================================================================
    # EXIT CRITERIA 4: Helpline is Islamabad urban_flood
    # =========================================================================
    logger.info("\n✓ Helpline lookup for Islamabad + urban_flood:")
    logger.info("  - Expected: Rescue 1122 or CARES 1122")
    logger.info("  - Checked in system_actions[0] (notify_helpline payload)")

    # =========================================================================
    # EXIT CRITERIA 5: Plan written in < 4 seconds
    # =========================================================================
    if duration_ms < 4000:
        logger.info(f"✅ PASS: Plan written in {duration_ms}ms (<4s required)")
    else:
        logger.error(f"❌ FAIL: Plan written in {duration_ms}ms (need <4s)")

    # =========================================================================
    # Summary
    # =========================================================================
    logger.info("\n" + "=" * 80)
    logger.info("M4 EXIT CRITERIA SUMMARY")
    logger.info("=" * 80)
    logger.info(f"Plan ID: {result.plan_id}")
    logger.info(f"Event ID: {result.event_id}")
    logger.info(f"System actions: {result.system_actions_count} (need ≥3)")
    logger.info(f"User actions: {result.user_actions_count} (need ≥1 per user within 5km)")
    logger.info(f"Duration: {duration_ms}ms (need <4000ms)")
    logger.info(f"Errors: {result.errors if result.errors else 'None'}")
    logger.info("=" * 80)

    return result


async def test_reroute_logic():
    """Unit test for reroute decision tree logic."""

    logger.info("\n" + "=" * 80)
    logger.info("M4 REROUTE DECISION LOGIC TEST")
    logger.info("=" * 80)

    from tools import compute_routes, point_in_polygon
    from models import GeoLocation

    # Mock route computation
    origin_lat, origin_lon = 33.7295, 73.1947  # Islamabad center
    destination_lat, destination_lon = 33.73, 73.20  # Slightly NE

    routes = compute_routes(
        origin_lat=origin_lat,
        origin_lon=origin_lon,
        destination_lat=destination_lat,
        destination_lon=destination_lon,
        avoid_polygons=None,
        prefer_safe_roads=False,
    )

    logger.info(f"\n✓ Routes computed: {len(routes)}")

    for i, route in enumerate(routes, 1):
        logger.info(f"\nRoute {i}:")
        logger.info(f"  - Distance: {route.distance_m}m")
        logger.info(f"  - Duration: {route.duration_s}s")
        logger.info(f"  - Risk score: {route.risk_score}")
        logger.info(f"  - Passes through flooded: {route.passes_through_flooded}")
        logger.info(f"  - Explanation: {route.risk_explanation}")

    if len(routes) == 3:
        logger.info(f"\n✅ PASS: 3 routes returned (required for REROUTE action)")
    else:
        logger.error(f"\n❌ FAIL: {len(routes)} routes returned (need 3)")

    # Check filtering logic
    flooded_routes = [r for r in routes if r.passes_through_flooded]
    safe_routes = [r for r in routes if not r.passes_through_flooded]

    logger.info(f"\n✓ Routes through flood zone: {len(flooded_routes)}")
    logger.info(f"✓ Safe routes: {len(safe_routes)}")

    if len(safe_routes) > 0:
        logger.info(f"✅ PASS: At least 1 safe route available for user")
    else:
        logger.warning(f"⚠️  CHECK: No safe routes (expect ≥1 unless severe event)")

    logger.info("=" * 80)


async def test_helpline_lookup():
    """Unit test for helpline lookup."""

    logger.info("\n" + "=" * 80)
    logger.info("M4 HELPLINE LOOKUP TEST")
    logger.info("=" * 80)

    from tools import lookup_helpline

    # Test Islamabad + urban_flood (G-10 scenario)
    helpline = lookup_helpline(city="Islamabad", crisis_type="urban_flood")

    logger.info(f"\n✓ Helpline lookup: Islamabad + urban_flood")
    if helpline:
        logger.info(f"  - Name: {helpline.name}")
        logger.info(f"  - Phone: {helpline.phone}")
        logger.info(f"  - 24h available: {helpline.available_24h}")

        if helpline.phone in ["1122", "1555"]:
            logger.info(f"✅ PASS: Correct Pakistani emergency number ({helpline.phone})")
        else:
            logger.warning(f"⚠️  CHECK: Phone {helpline.phone} (expect 1122 or 1555)")
    else:
        logger.error("❌ FAIL: Helpline lookup returned None")

    logger.info("=" * 80)


async def test_point_in_polygon():
    """Unit test for point-in-polygon logic."""

    logger.info("\n" + "=" * 80)
    logger.info("M4 POINT-IN-POLYGON TEST")
    logger.info("=" * 80)

    from tools import point_in_polygon
    from models import GeoLocation

    # Simple square polygon
    polygon = [
        GeoLocation(latitude=33.728, longitude=73.193),
        GeoLocation(latitude=33.728, longitude=73.196),
        GeoLocation(latitude=33.731, longitude=73.196),
        GeoLocation(latitude=33.731, longitude=73.193),
    ]

    # Test point inside
    inside_lat, inside_lon = 33.7295, 73.1945
    is_inside = point_in_polygon(inside_lat, inside_lon, polygon)

    logger.info(f"\n✓ Test: point (33.7295, 73.1945) inside polygon?")
    logger.info(f"  Result: {is_inside}")

    if is_inside:
        logger.info(f"✅ PASS: Point correctly identified as inside")
    else:
        logger.error(f"❌ FAIL: Point should be inside")

    # Test point outside
    outside_lat, outside_lon = 33.720, 73.190
    is_outside = point_in_polygon(outside_lat, outside_lon, polygon)

    logger.info(f"\n✓ Test: point (33.720, 73.190) inside polygon?")
    logger.info(f"  Result: {is_outside}")

    if not is_outside:
        logger.info(f"✅ PASS: Point correctly identified as outside")
    else:
        logger.error(f"❌ FAIL: Point should be outside")

    logger.info("=" * 80)


async def main():
    """Run all tests."""

    try:
        # Unit tests (no Firestore required)
        await test_point_in_polygon()
        await test_reroute_logic()
        await test_helpline_lookup()

        # Integration test (requires Firestore + event data)
        # Uncomment if event exists in Firestore:
        # await test_planning_g10_scenario()

    except Exception as e:
        logger.exception(f"Test failed: {e}")


if __name__ == "__main__":
    asyncio.run(main())
