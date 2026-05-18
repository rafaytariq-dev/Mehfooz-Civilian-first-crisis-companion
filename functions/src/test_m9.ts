import * as admin from 'firebase-admin';
import * as geofire from 'geofire-common';

admin.initializeApp({ projectId: "demo-mehfooz" });
const db = admin.firestore();

async function testM9() {
  console.log("Starting M9 Logic Test...");

  // 1. Seed flood_prone_locations
  console.log("Seeding Lakhani Underpass...");
  const lakhaniRef = db.collection('flood_prone_locations').doc('lakhani_underpass');
  await lakhaniRef.set({
      name: 'Lakhani Underpass',
      name_ur: 'لاکھانی انڈرپاس',
      city: 'Karachi',
      location: new admin.firestore.GeoPoint(24.9150, 67.0900),
      rainfall_threshold_mm_h: 15.0,
      warn_radius_m: 2000,
  });

  // 2. Seed test users
  const nearCenter = [24.9190, 67.0900] as [number, number]; // 440m away
  const farCenter = [24.9600, 67.0900] as [number, number]; // 5km away

  await db.collection('users').doc('user_m9_near').set({
      name: 'Near User',
      language: 'en',
      fcm_token: 'mock_token_near',
      last_known_location: new admin.firestore.GeoPoint(nearCenter[0], nearCenter[1]),
      geohash: geofire.geohashForLocation(nearCenter, 9),
  }, { merge: true });

  await db.collection('users').doc('user_m9_far').set({
      name: 'Far User',
      language: 'ur',
      fcm_token: 'mock_token_far',
      last_known_location: new admin.firestore.GeoPoint(farCenter[0], farCenter[1]),
      geohash: geofire.geohashForLocation(farCenter, 9),
  }, { merge: true });

  // 3. Clear existing radar warnings
  console.log("Clearing existing warnings...");
  const existingWarnings = await db.collection('radar_warnings').get();
  for (const doc of existingWarnings.docs) {
    await doc.ref.delete();
  }

  // 4. Run the Radar logic with mock weather
  console.log("Running Radar logic...");
  const floodProne = await db.collection('flood_prone_locations').get();

  for (const loc of floodProne.docs) {
    const data = loc.data();
    console.log(`Checking location: ${data.name}`);
    
    // MOCK WEATHER > THRESHOLD
    const weather = { rainfall_mm_1h: 25.0 }; // Force trigger
    console.log(`Mocking weather to 25mm/h (Threshold: ${data.rainfall_threshold_mm_h})`);

    // Geo-query users
    const center = [data.location.latitude, data.location.longitude] as [number, number];
    const bounds = geofire.geohashQueryBounds(center, data.warn_radius_m);
    
    const userPromises = bounds.map(b =>
      db.collection('users')
        .orderBy('geohash')
        .startAt(b[0])
        .endAt(b[1])
        .get()
    );
    const snaps = await Promise.all(userPromises);
    
    const candidates = snaps.flatMap(s => s.docs).filter(u => {
      const ul = u.data().last_known_location;
      if (!ul) return false;
      const dist = geofire.distanceBetween([ul.latitude, ul.longitude], center) * 1000;
      console.log(`User ${u.id} distance: ${dist.toFixed(1)}m`);
      return dist <= data.warn_radius_m;
    });

    console.log(`Found ${candidates.length} candidates within radius`);

    for (const userDoc of candidates) {
      const dedupeKey = `${userDoc.id}_${loc.id}`;
      console.log(`Sending push to ${userDoc.id} (${userDoc.data().name})`);
      await db.collection('radar_warnings').doc(dedupeKey).set({
        user_id: userDoc.id,
        location_id: loc.id,
        sent_at: admin.firestore.FieldValue.serverTimestamp()
      });
    }
  }
}

testM9().then(() => console.log("Done.")).catch(console.error);
