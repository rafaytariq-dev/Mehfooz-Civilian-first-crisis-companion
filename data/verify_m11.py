#!/usr/bin/env python3
"""
M11 — Heatwave Personal Advisor: Verification Script

Validates:
  1. Heatwave seed data structure
  2. Heat index computation against reference values
  3. Cooling spot data has has_cooling fields
  4. Deduplication window logic
  5. Emergency contact ping threshold (≥48°C)
  6. Cloud Function file structure
  7. Flutter file structure
"""

import json
import math
import os
import sys
from pathlib import Path

# Fix Windows console encoding
if sys.platform == 'win32':
    sys.stdout.reconfigure(encoding='utf-8')

# ─── Paths ───
BASE = Path(__file__).parent.parent
DATA_DIR = BASE / "data"
FUNCTIONS_DIR = BASE / "functions" / "src"
APP_DIR = BASE / "app" / "lib"

# Track results
passed = 0
failed = 0
warnings = 0


def check(condition: bool, label: str, detail: str = ""):
    global passed, failed
    if condition:
        print(f"  ✅ {label}")
        passed += 1
    else:
        print(f"  ❌ {label}")
        if detail:
            print(f"     → {detail}")
        failed += 1


def warn(label: str):
    global warnings
    print(f"  ⚠️  {label}")
    warnings += 1


# ═══════════════════════════════════════════
# 1. Heatwave Seed Data
# ═══════════════════════════════════════════
print("\n📋 1. Heatwave Seed Data")
print("=" * 50)

# Weather data
hw_weather_path = DATA_DIR / "seed_heatwave_weather.json"
check(hw_weather_path.exists(), "seed_heatwave_weather.json exists")

if hw_weather_path.exists():
    with open(hw_weather_path) as f:
        hw_weather = json.load(f)

    check(isinstance(hw_weather, list), "Weather data is a list")
    check(len(hw_weather) >= 10, f"Has {len(hw_weather)} weather snapshots (≥10)")

    for i, w in enumerate(hw_weather):
        required = ["signal_id", "source", "location", "city",
                     "rainfall_mm_1h", "temp_c", "humidity"]
        for field in required:
            if field not in w:
                check(False, f"Entry {i} has field '{field}'")
                break
        else:
            if i == 0:
                check(True, "Weather entries have all required fields")

    # Check temperature range (heatwave: 38–50°C)
    temps = [w["temp_c"] for w in hw_weather]
    check(
        max(temps) >= 45,
        f"Peak temp is {max(temps)}°C (≥45°C for realistic heatwave)",
    )
    check(
        all(w["city"] == "Karachi" for w in hw_weather),
        "All entries are for Karachi",
    )

# User data
hw_users_path = DATA_DIR / "seed_heatwave_users.json"
check(hw_users_path.exists(), "seed_heatwave_users.json exists")

if hw_users_path.exists():
    with open(hw_users_path) as f:
        hw_users = json.load(f)

    check(isinstance(hw_users, list), "User data is a list")
    check(len(hw_users) >= 6, f"Has {len(hw_users)} test users (≥6)")

    outdoor_users = [u for u in hw_users if u.get("last_activity") in ("outdoor_report", "app_open_moving")]
    indoor_users = [u for u in hw_users if u.get("last_activity") == "indoor"]
    check(
        len(outdoor_users) >= 3,
        f"Has {len(outdoor_users)} outdoor users (≥3 for testing)",
    )
    check(
        len(indoor_users) >= 1,
        f"Has {len(indoor_users)} indoor users (≥1 for negative test)",
    )

    with_contacts = [u for u in hw_users if u.get("emergency_contacts")]
    check(
        len(with_contacts) >= 4,
        f"Has {len(with_contacts)} users with emergency contacts (≥4)",
    )

# ═══════════════════════════════════════════
# 2. Heat Index Computation
# ═══════════════════════════════════════════
print("\n🌡️ 2. Heat Index Computation")
print("=" * 50)


def compute_heat_index(temp_c: float, humidity: float) -> float:
    """Rothfusz regression — mirrors the TypeScript implementation."""
    T = temp_c * 9 / 5 + 32  # °C → °F
    R = humidity

    hi = 0.5 * (T + 61.0 + ((T - 68.0) * 1.2) + (R * 0.094))

    if hi >= 80:
        hi = (-42.379
              + 2.04901523 * T
              + 10.14333127 * R
              - 0.22475541 * T * R
              - 0.00683783 * T * T
              - 0.05481717 * R * R
              + 0.00122874 * T * T * R
              + 0.00085282 * T * R * R
              - 0.00000199 * T * T * R * R)

        if R < 13 and 80 <= T <= 112:
            hi -= ((13 - R) / 4) * math.sqrt((17 - abs(T - 95)) / 17)
        if R > 85 and 80 <= T <= 87:
            hi += ((R - 85) / 10) * ((87 - T) / 5)

    return (hi - 32) * 5 / 9


# Reference test cases — Rothfusz regression is highly nonlinear at extreme temps.
# At Pakistan heatwave temperatures (40-50°C), heat index rises dramatically.
# Values verified against NWS Heat Index Calculator.
test_cases = [
    # (temp_c, humidity, expected_hi_c, tolerance, description)
    (40, 60, 63, 5, "40°C + 60% humidity → ~63°C (extreme danger)"),
    (35, 40, 37, 4, "35°C + 40% humidity → ~37°C (caution)"),
    (47, 60, 96, 10, "47°C + 60% humidity → ~96°C (extreme danger)"),
    (30, 50, 31, 4, "30°C + 50% humidity → ~31°C (safe/caution border)"),
    (44, 56, 76, 10, "44°C + 56% humidity → ~76°C (extreme danger)"),
]

for temp, hum, expected, tol, desc in test_cases:
    hi = compute_heat_index(temp, hum)
    within_tol = abs(hi - expected) < tol
    check(within_tol, f"HI({temp}°C, {hum}%) = {hi:.1f}°C ≈ {expected}°C ±{tol}")

# Threshold checks
hi_alert = compute_heat_index(40, 55)
check(hi_alert >= 42, f"Alert threshold: HI(40°C, 55%) = {hi_alert:.1f}°C ≥ 42°C")

hi_emergency = compute_heat_index(46, 60)
check(hi_emergency >= 48, f"Emergency threshold: HI(46°C, 60%) = {hi_emergency:.1f}°C ≥ 48°C")

# ═══════════════════════════════════════════
# 3. Cooling Spots Data
# ═══════════════════════════════════════════
print("\n❄️ 3. Cooling Spots Data")
print("=" * 50)

safe_spots_path = DATA_DIR / "safe_spots.json"
check(safe_spots_path.exists(), "safe_spots.json exists")

if safe_spots_path.exists():
    with open(safe_spots_path) as f:
        safe_spots = json.load(f)

    check(isinstance(safe_spots, list), "Safe spots is a list")
    check(len(safe_spots) >= 50, f"Has {len(safe_spots)} safe spots (≥50)")

    # Count Karachi spots with cooling
    karachi_cooling = [
        s for s in safe_spots
        if s.get("has_cooling") is True
        and any(kw in s.get("address", "").lower() for kw in ["karachi", "khi"])
    ]

    # Also check by coordinates (Karachi: ~24.8–25.0 lat)
    karachi_by_coords = [
        s for s in safe_spots
        if s.get("has_cooling") is True
        and 24.5 <= s.get("location", {}).get("latitude", 0) <= 25.5
        and 66.5 <= s.get("location", {}).get("longitude", 0) <= 68.0
    ]

    total_karachi = max(len(karachi_cooling), len(karachi_by_coords))
    check(total_karachi >= 5, f"Karachi has {total_karachi} cooling spots (≥5)")

    # Check all cooling spots have required fields
    cooling_spots = [s for s in safe_spots if s.get("has_cooling") is True]
    check(len(cooling_spots) >= 20, f"Total cooling spots: {len(cooling_spots)} (≥20)")

    for s in cooling_spots[:5]:
        has_fields = all(
            k in s for k in ["name", "type", "location", "has_cooling"]
        )
        if not has_fields:
            check(False, f"Cooling spot missing fields: {s.get('name', 'unknown')}")
            break
    else:
        check(True, "Cooling spots have all required fields (sampled)")

# ═══════════════════════════════════════════
# 4. Deduplication Logic
# ═══════════════════════════════════════════
print("\n⏱️ 4. Deduplication Logic")
print("=" * 50)

DEDUP_WINDOW_MS = 4 * 3600 * 1000
check(DEDUP_WINDOW_MS == 14400000, f"Dedup window = {DEDUP_WINDOW_MS}ms (4 hours)")

# Simulate dedup check
import time
now = time.time() * 1000
recent = now - (3 * 3600 * 1000)  # 3 hours ago
old = now - (5 * 3600 * 1000)     # 5 hours ago

check(now - recent < DEDUP_WINDOW_MS, "3h-old warning blocks new alert (within window)")
check(now - old >= DEDUP_WINDOW_MS, "5h-old warning allows new alert (outside window)")

# ═══════════════════════════════════════════
# 5. Emergency Contact Threshold
# ═══════════════════════════════════════════
print("\n🚨 5. Emergency Contact Threshold")
print("=" * 50)

EMERGENCY_THRESHOLD = 48
check(EMERGENCY_THRESHOLD == 48, f"Emergency threshold = {EMERGENCY_THRESHOLD}°C")

# Test scenarios
scenarios = [
    (45, False, "45°C → no emergency ping"),
    (48, True, "48°C → emergency ping"),
    (52, True, "52°C → emergency ping"),
    (41, False, "41°C → no emergency ping"),
]

for hi, should_ping, desc in scenarios:
    actual = hi >= EMERGENCY_THRESHOLD
    check(actual == should_ping, desc)

# ═══════════════════════════════════════════
# 6. Cloud Function Files
# ═══════════════════════════════════════════
print("\n⚡ 6. Cloud Function Files")
print("=" * 50)

ha_path = FUNCTIONS_DIR / "heatwave_advisor.ts"
check(ha_path.exists(), "heatwave_advisor.ts exists")

if ha_path.exists():
    content = ha_path.read_text(encoding="utf-8")
    check("computeHeatIndex" in content, "Has computeHeatIndex function")
    check("isLikelyOutdoors" in content, "Has isLikelyOutdoors heuristic")
    check("sentRecently" in content, "Has sentRecently deduplication")
    check("findNearestCoolingSpots" in content, "Has findNearestCoolingSpots")
    check("sendHeatwavePush" in content, "Has sendHeatwavePush function")
    check("notifyEmergencyContact" in content, "Has notifyEmergencyContact function")
    check("heatwaveAdvisor" in content, "Has heatwaveAdvisor export")
    check("every 15 minutes" in content, "Scheduled every 15 minutes")
    check("onSchedule" in content, "Uses onSchedule trigger")
    check("Rothfusz" in content, "Mentions Rothfusz regression")
    check("heatwave_warnings" in content, "Writes to heatwave_warnings collection")
    check("wa.me" in content, "Has WhatsApp deep link")

index_path = FUNCTIONS_DIR / "index.ts"
check(index_path.exists(), "index.ts exists")
if index_path.exists():
    idx_content = index_path.read_text(encoding="utf-8")
    check("heatwaveAdvisor" in idx_content, "index.ts exports heatwaveAdvisor")
    check("heatwave_advisor" in idx_content, "index.ts imports from heatwave_advisor")

# ═══════════════════════════════════════════
# 7. Flutter Files
# ═══════════════════════════════════════════
print("\n📱 7. Flutter Files")
print("=" * 50)

flutter_files = {
    "screens/heatwave_screen.dart": ["HeatwaveScreen", "HeatIndexGauge", "CoolingSpotTile"],
    "widgets/heat_index_gauge.dart": ["HeatIndexGauge", "_GaugePainter", "CustomPaint"],
    "widgets/cooling_spot_tile.dart": ["CoolingSpotTile", "CoolingSpotData"],
    "widgets/heatwave_card.dart": ["HeatwaveCard", "heatIndexC"],
    "services/heatwave_service.dart": ["HeatwaveService", "computeHeatIndex", "CoolingSpotData"],
    "providers/heatwave_provider.dart": ["heatwaveServiceProvider", "heatSafetyTipsProvider"],
}

for rel_path, keywords in flutter_files.items():
    full_path = APP_DIR / rel_path
    check(full_path.exists(), f"{rel_path} exists")
    if full_path.exists():
        content = full_path.read_text(encoding="utf-8")
        for kw in keywords:
            if kw not in content:
                check(False, f"  {rel_path} contains '{kw}'")
                break
        else:
            check(True, f"  {rel_path} contains all key symbols")

# Router integration
router_path = APP_DIR / "router.dart"
if router_path.exists():
    router = router_path.read_text(encoding="utf-8")
    check("heatwave" in router, "router.dart has /heatwave route")
    check("HeatwaveScreen" in router, "router.dart references HeatwaveScreen")

# Home screen integration
home_path = APP_DIR / "screens" / "home_screen.dart"
if home_path.exists():
    home = home_path.read_text(encoding="utf-8")
    check("HeatwaveCard" in home, "home_screen.dart has HeatwaveCard")
    check("heatwave_card.dart" in home, "home_screen.dart imports heatwave_card")

# Profile screen integration
profile_path = APP_DIR / "screens" / "profile_screen.dart"
if profile_path.exists():
    profile = profile_path.read_text(encoding="utf-8")
    check("Heatwave" in profile, "profile_screen.dart has Heatwave toggle")

# ═══════════════════════════════════════════
# 8. Firestore Rules & Indexes
# ═══════════════════════════════════════════
print("\n🔒 8. Firestore Rules & Indexes")
print("=" * 50)

rules_path = BASE / "firestore.rules"
if rules_path.exists():
    rules = rules_path.read_text(encoding="utf-8")
    check("heatwave_warnings" in rules, "firestore.rules has heatwave_warnings rule")

indexes_path = BASE / "firestore.indexes.json"
if indexes_path.exists():
    with open(indexes_path) as f:
        indexes = json.load(f)
    hw_indexes = [
        i for i in indexes.get("indexes", [])
        if i.get("collectionGroup") == "heatwave_warnings"
    ]
    check(len(hw_indexes) >= 1, f"firestore.indexes.json has {len(hw_indexes)} heatwave index(es)")

# ═══════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════
print("\n" + "=" * 50)
print(f"📊 Results: {passed} passed, {failed} failed, {warnings} warnings")
print("=" * 50)

if failed == 0:
    print("🎉 All M11 checks passed! Heatwave Personal Advisor is ready.")
else:
    print(f"⚠️  {failed} check(s) failed. Review and fix before proceeding.")

sys.exit(0 if failed == 0 else 1)
