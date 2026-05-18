"""
M9 Verification Script — Underpass Flood Radar

This script:
1. Seeds a flood_prone_locations doc for Lakhani Underpass (Karachi) with a 20mm/h threshold.
2. Seeds test users with locations near (1.5km) and far (5km) from the underpass, using geohashes.
3. Clears any existing radar_warnings to ensure fresh test execution.

After running this, the Cloud Function `underpassRadar` should be invoked to verify:
- It fetches weather.
- It queries geohashes.
- It writes radar_warnings for the nearby user.
"""
import os
import time
from google.cloud import firestore
import pygeohash as pgh

# Use the same project ID as the main app
os.environ["FIRESTORE_EMULATOR_HOST"] = "localhost:8080" # If running locally, adjust as needed

def get_db():
    try:
        # Check if emulator is running
        return firestore.Client(project="demo-mehfooz")
    except:
        return firestore.Client()

def verify_m9():
    db = get_db()
    
    # 1. Seed flood_prone_locations
    lakhani_ref = db.collection('flood_prone_locations').document('lakhani_underpass')
    lakhani_ref.set({
        'name': 'Lakhani Underpass',
        'name_ur': 'لاکھانی انڈرپاس',
        'city': 'Karachi',
        'location': firestore.GeoPoint(24.9150, 67.0900), # Roughly Karachi coordinates
        'rainfall_threshold_mm_h': 15.0, # low threshold for testing
        'warn_radius_m': 2000, # 2km radius
    })
    
    print("✅ Seeded flood_prone_locations: Lakhani Underpass (warn_radius: 2000m)")

    # 2. Seed test users
    # User 1: 1km away (within 2km radius)
    near_lat, near_lon = 24.9190, 67.0900 # ~440m away
    near_geohash = pgh.encode(near_lat, near_lon, precision=9)
    
    # User 2: 5km away (outside 2km radius)
    far_lat, far_lon = 24.9600, 67.0900 # ~5km away
    far_geohash = pgh.encode(far_lat, far_lon, precision=9)

    db.collection('users').document('user_m9_near').set({
        'name': 'Near User',
        'language': 'en',
        'fcm_token': 'mock_token_near',
        'last_known_location': firestore.GeoPoint(near_lat, near_lon),
        'geohash': near_geohash,
    }, merge=True)
    
    db.collection('users').document('user_m9_far').set({
        'name': 'Far User',
        'language': 'ur',
        'fcm_token': 'mock_token_far',
        'last_known_location': firestore.GeoPoint(far_lat, far_lon),
        'geohash': far_geohash,
    }, merge=True)

    print("✅ Seeded users: user_m9_near (440m) and user_m9_far (5km)")

    # 3. Clear existing warnings
    warnings = db.collection('radar_warnings').stream()
    for w in warnings:
        w.reference.delete()
    
    print("✅ Cleared existing radar_warnings")
    print("\nNext steps to verify M9:")
    print("1. Ensure functions are deployed or running via `npm run serve`")
    print("2. Since we cannot easily inject weather into Open-Meteo API, you can manually trigger the Cloud Function logic.")
    print("   If the current rainfall in Karachi is < 15mm, the function will correctly skip sending.")
    print("   To force a push, modify functions/src/underpass_radar.ts to mock `rainfall_mm_1h = 25.0;` temporarily and run it.")
    print("3. Check Firestore `radar_warnings` collection. It should contain `user_m9_near_lakhani_underpass`.")

if __name__ == '__main__':
    verify_m9()
