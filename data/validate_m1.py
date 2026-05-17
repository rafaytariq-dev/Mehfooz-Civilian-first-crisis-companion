#!/usr/bin/env python3
"""Validates M1 exit criteria. Run after seeding.
Can run in --local mode to validate JSON files without Firestore.
"""

import argparse
import json
from pathlib import Path

DATA_DIR = Path(__file__).parent


def validate_local():
    """Validate JSON files locally without Firestore connection."""
    checks = []

    # Check helplines >= 30
    with open(DATA_DIR / 'helplines.json', encoding='utf-8') as f:
        count = len(json.load(f))
    checks.append(('helplines >= 30', count >= 30, count))

    # Check flood_prone_locations >= 50
    with open(DATA_DIR / 'flood_prone_locations.json', encoding='utf-8') as f:
        count = len(json.load(f))
    checks.append(('flood_prone_locations >= 50', count >= 50, count))

    # Check safe_spots >= 200
    with open(DATA_DIR / 'safe_spots.json', encoding='utf-8') as f:
        count = len(json.load(f))
    checks.append(('safe_spots >= 200', count >= 200, count))

    # Check reports >= 20
    with open(DATA_DIR / 'seed_reports.json', encoding='utf-8') as f:
        count = len(json.load(f))
    checks.append(('seed_reports >= 20', count >= 20, count))

    # Check weather signals >= 6
    with open(DATA_DIR / 'seed_weather.json', encoding='utf-8') as f:
        count = len(json.load(f))
    checks.append(('seed_weather >= 6', count >= 6, count))

    # Check social signals >= 15
    with open(DATA_DIR / 'seed_social.json', encoding='utf-8') as f:
        count = len(json.load(f))
    checks.append(('seed_social >= 15', count >= 15, count))

    # Check traffic signals >= 5
    with open(DATA_DIR / 'seed_traffic.json', encoding='utf-8') as f:
        count = len(json.load(f))
    checks.append(('seed_traffic >= 5', count >= 5, count))

    # Check users >= 8
    with open(DATA_DIR / 'seed_users.json', encoding='utf-8') as f:
        count = len(json.load(f))
    checks.append(('seed_users >= 8', count >= 8, count))

    return checks


def validate_firestore():
    """Validate Firestore collections after seeding."""
    import firebase_admin
    from firebase_admin import credentials, firestore

    if not firebase_admin._apps:
        cred = credentials.ApplicationDefault()
        firebase_admin.initialize_app(cred, {'projectId': 'mehfooz-prod'})
    db = firestore.client()

    checks = []

    count = len(db.collection('helplines').get())
    checks.append(('helplines >= 30', count >= 30, count))

    count = len(db.collection('flood_prone_locations').get())
    checks.append(('flood_prone_locations >= 50', count >= 50, count))

    count = len(db.collection('safe_spots').get())
    checks.append(('safe_spots >= 200', count >= 200, count))

    count = len(db.collection('reports').get())
    checks.append(('reports seeded', count >= 20, count))

    count = len(db.collection('signals_weather').get())
    checks.append(('signals_weather seeded', count >= 6, count))

    count = len(db.collection('signals_social').get())
    checks.append(('signals_social seeded', count >= 15, count))

    count = len(db.collection('users').get())
    checks.append(('demo users seeded', count >= 8, count))

    # Check mock_dispatches collection exists
    db.collection('mock_dispatches').document('_validate_test').set({'test': True})
    doc = db.collection('mock_dispatches').document('_validate_test').get()
    checks.append(('mock_dispatches writable', doc.exists, 'exists' if doc.exists else 'missing'))
    db.collection('mock_dispatches').document('_validate_test').delete()

    return checks


def main():
    parser = argparse.ArgumentParser(description='Validate M1 exit criteria')
    parser.add_argument('--local', action='store_true',
                        help='Validate JSON files locally without Firestore')
    args = parser.parse_args()

    if args.local:
        print("\n=== M1 Local Validation (JSON files) ===")
        checks = validate_local()
    else:
        print("\n=== M1 Firestore Validation ===")
        checks = validate_firestore()

    all_pass = True
    for name, passed, value in checks:
        status = "PASS" if passed else "FAIL"
        symbol = "+" if passed else "X"
        print(f"[{symbol}] {status} | {name} | value={value}")
        if not passed:
            all_pass = False

    print("\n" + (
        "[+] ALL CHECKS PASSED - M1 complete." if all_pass
        else "[X] SOME CHECKS FAILED - fix before handing off."
    ))


if __name__ == '__main__':
    main()
