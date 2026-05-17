#!/usr/bin/env python3
"""
Replay the G-10/G-11 Islamabad flash flood scenario into Firestore.
Usage: python data/replay_scenario.py g10 [--speed 1.0] [--dry-run]

--speed: multiplier for replay. 1.0 = real-time. 60 = 1 minute of demo = 1 sec.
--dry-run: print what would be written without writing.
"""

import argparse
import json
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

DATA_DIR = Path(__file__).parent

def load_json(filename):
    with open(DATA_DIR / filename, encoding='utf-8') as f:
        return json.load(f)

def init_firestore():
    import firebase_admin
    from firebase_admin import credentials, firestore
    if not firebase_admin._apps:
        cred = credentials.ApplicationDefault()
        firebase_admin.initialize_app(cred, {'projectId': 'mehfooz-prod'})
    return firestore.client()

def replay_g10(speed: float, dry_run: bool):
    db = None if dry_run else init_firestore()
    now = datetime.now(timezone.utc)

    reports = load_json("seed_reports.json")
    weather = load_json("seed_weather.json")
    social  = load_json("seed_social.json")
    traffic = load_json("seed_traffic.json")
    users   = load_json("seed_users.json")

    # Seed reference data first (idempotent — skip if already exists)
    seed_static(db, dry_run)

    # Seed users (idempotent)
    seed_users(db, users, now, dry_run)

    # Sort all events by their offset, then emit in order with real-time delay
    events = []
    for r in reports:
        events.append(('report', r, r['t_offset_min'] * 60))
    for w in weather:
        events.append(('weather', w, w['t_offset_hour'] * 3600))
    for s in social:
        events.append(('social', s, s['t_offset_min'] * 60))
    for t in traffic:
        events.append(('traffic', t, t['t_offset_min'] * 60))

    events.sort(key=lambda x: x[2])

    prev_offset = events[0][2]
    for kind, doc, offset_s in events:
        delay = (offset_s - prev_offset) / speed
        if delay > 0:
            print(f"[replay] sleeping {delay:.1f}s (speed={speed}x)...")
            time.sleep(delay)
        prev_offset = offset_s

        ts = now + timedelta(seconds=offset_s)
        write_event(db, kind, doc, ts, dry_run)

    print("[replay] G-10 scenario complete.")

def seed_static(db, dry_run):
    """Write helplines, flood_prone_locations, safe_spots — skip if collection already has docs."""
    for collection, filename in [
        ('helplines', 'helplines.json'),
        ('flood_prone_locations', 'flood_prone_locations.json'),
        ('safe_spots', 'safe_spots.json'),
    ]:
        docs = load_json(filename)
        for doc in docs:
            doc_id = doc.get('helpline_id') or doc.get('location_id') or doc.get('spot_id')
            print(f"[seed] {collection}/{doc_id}")
            if not dry_run:
                db.collection(collection).document(doc_id).set(doc, merge=True)

def seed_users(db, users, now, dry_run):
    for u in users:
        uid = u['uid']
        payload = {**u,
            'last_location_at': now,
            'created_at': now - timedelta(days=30),
            'fcm_token': f'demo-fcm-token-{uid}',
        }
        if not dry_run:
            from firebase_admin import firestore as fs
            payload['last_known_location'] = fs.GeoPoint(
                u['last_known_location']['latitude'],
                u['last_known_location']['longitude']
            )
        else:
            payload['last_known_location'] = u['last_known_location']
        print(f"[seed] users/{uid}")
        if not dry_run:
            db.collection('users').document(uid).set(payload, merge=True)


def write_event(db, kind, doc, ts, dry_run):
    def geo(lat, lon):
        if dry_run:
            return {"latitude": lat, "longitude": lon}
        from firebase_admin import firestore as fs
        return fs.GeoPoint(lat, lon)

    if kind == 'report':
        col = 'reports'
        doc_id = doc['report_id']
        payload = {**doc,
            'created_at': ts,
            'location': geo(doc['location']['latitude'], doc['location']['longitude'])
        }
        payload.pop('t_offset_min', None)

    elif kind == 'weather':
        col = 'signals_weather'
        doc_id = doc['signal_id']
        payload = {**doc,
            'recorded_at': ts,
            'fetched_at': ts,
            'location': geo(doc['location']['latitude'], doc['location']['longitude'])
        }
        payload.pop('t_offset_hour', None)

    elif kind == 'social':
        col = 'signals_social'
        doc_id = doc['signal_id']
        loc = doc.get('location_inferred')
        payload = {**doc,
            'posted_at': ts,
            'location_inferred': geo(loc['latitude'], loc['longitude']) if loc else None
        }
        payload.pop('t_offset_min', None)

    elif kind == 'traffic':
        col = 'signals_traffic'
        doc_id = doc['signal_id']
        payload = {**doc,
            'recorded_at': ts,
            'origin': geo(doc['origin']['latitude'], doc['origin']['longitude']),
            'destination': geo(doc['destination']['latitude'], doc['destination']['longitude']),
        }
        payload.pop('t_offset_min', None)

    else:
        return

    print(f"[{ts.strftime('%H:%M:%S')}] writing {col}/{doc_id}")
    if not dry_run:
        db.collection(col).document(doc_id).set(payload)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('scenario', choices=['g10'])
    parser.add_argument('--speed', type=float, default=60.0,
                        help='Replay speed multiplier (default 60 = 1min of scenario per 1sec)')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()

    if args.scenario == 'g10':
        replay_g10(args.speed, args.dry_run)

if __name__ == '__main__':
    main()
