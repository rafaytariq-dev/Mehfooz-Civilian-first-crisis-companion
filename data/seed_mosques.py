#!/usr/bin/env python3
"""Seed mosques and demo mosque-admin users (M14) into Firestore.

Usage:
    python seed_mosques.py                # uploads to live Firestore
    python seed_mosques.py --emulator     # uses Firestore emulator at localhost:8080
    python seed_mosques.py --local        # validate JSON only, no upload

Demo admins (uid pattern: demo-admin-*) are also created in the `users`
collection with `role: mosque_admin` so the createBroadcast callable
passes the role check. This is hackathon-only seed code; production
verification is a manual flow (CNIC + letterhead + ops review).
"""

import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path

DATA_DIR = Path(__file__).parent


def load_mosques():
    with open(DATA_DIR / 'seed_mosques.json', encoding='utf-8') as f:
        return json.load(f)


def validate(mosques):
    """Basic schema check."""
    errors = []
    for m in mosques:
        for required in ('mosque_id', 'name', 'city', 'location', 'admin_uids'):
            if required not in m:
                errors.append(f"{m.get('mosque_id', '?')}: missing {required}")
        if not isinstance(m.get('admin_uids', []), list) or not m['admin_uids']:
            errors.append(f"{m['mosque_id']}: admin_uids must be non-empty list")
        loc = m.get('location', {})
        if not (isinstance(loc.get('latitude'), (int, float))
                and isinstance(loc.get('longitude'), (int, float))):
            errors.append(f"{m['mosque_id']}: invalid location")
    return errors


def upload(mosques, emulator=False):
    if emulator:
        os.environ['FIRESTORE_EMULATOR_HOST'] = 'localhost:8080'
    try:
        from google.cloud import firestore
    except ImportError:
        print('google-cloud-firestore not installed. Run: pip install google-cloud-firestore')
        return False

    db = firestore.Client()
    now = datetime.now(timezone.utc)

    for m in mosques:
        doc = {
            'mosque_id': m['mosque_id'],
            'name': m['name'],
            'name_ur': m.get('name_ur'),
            'city': m['city'],
            'location': firestore.GeoPoint(
                m['location']['latitude'], m['location']['longitude']
            ),
            'admin_uids': m['admin_uids'],
            'verified_at': now,
            'verified_by': m.get('verified_by', 'ops-team-mehfooz'),
            'notes': m.get('notes', ''),
        }
        db.collection('mosques').document(m['mosque_id']).set(doc)
        print(f"  [ok]mosques/{m['mosque_id']}  ({m['name']})")

        # Seed demo admin user with mosque_admin role
        for admin_uid in m['admin_uids']:
            user_doc = {
                'uid': admin_uid,
                'display_name': f"Admin – {m['name']}",
                'role': 'mosque_admin',
                'city': m['city'],
                'language': 'ur',
                'reputation': 80,
                'last_known_location': doc['location'],
                'created_at': now,
            }
            db.collection('users').document(admin_uid).set(user_doc, merge=True)
            print(f"    ->users/{admin_uid}  (mosque_admin)")

    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--local', action='store_true', help='validate only, no upload')
    parser.add_argument('--emulator', action='store_true', help='target Firestore emulator')
    args = parser.parse_args()

    mosques = load_mosques()
    errors = validate(mosques)
    if errors:
        print('Validation errors:')
        for e in errors:
            print(f'  [fail]{e}')
        return 1

    print(f'Validated {len(mosques)} mosques.')

    if args.local:
        print('Local mode — skipping upload.')
        return 0

    print('Uploading...')
    ok = upload(mosques, emulator=args.emulator)
    print('Done.' if ok else 'Upload skipped (missing deps).')
    return 0 if ok else 2


if __name__ == '__main__':
    raise SystemExit(main())
