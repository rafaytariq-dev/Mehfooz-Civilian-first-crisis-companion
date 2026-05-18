// functions/src/underpass_radar.ts
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import * as geofire from 'geofire-common';

const db = getFirestore();

export const underpassRadar = onSchedule('every 5 minutes', async () => {
  const floodProne = await db.collection('flood_prone_locations').get();

  for (const loc of floodProne.docs) {
    const data = loc.data();
    
    // 1. Fetch weather from Open-Meteo
    const weather = await getLatestWeather(data.location.latitude, data.location.longitude);
    if (!weather || weather.rainfall_mm_1h < data.rainfall_threshold_mm_h) continue;

    // 2. Geo-query users within radius
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
      return dist <= data.warn_radius_m;
    });

    for (const userDoc of candidates) {
      const dedupeKey = `${userDoc.id}_${loc.id}`;
      const existing = await db.collection('radar_warnings').doc(dedupeKey).get();
      
      if (existing.exists && (Date.now() - existing.data()!.sent_at.toMillis()) < 6 * 3600 * 1000) {
        continue;
      }

      await sendRadarPush(userDoc.data(), loc.id, data, weather);
      await db.collection('radar_warnings').doc(dedupeKey).set({
        user_id: userDoc.id,
        location_id: loc.id,
        sent_at: FieldValue.serverTimestamp()
      });
    }
  }
});

async function getLatestWeather(lat: number, lon: number): Promise<{rainfall_mm_1h: number} | null> {
  try {
    const response = await fetch(`https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&hourly=precipitation&timezone=Asia/Karachi&forecast_days=1&past_days=1`);
    if (!response.ok) return null;
    const data = await response.json() as any;
    const hourly_precip = data.hourly?.precipitation || [];
    const rainfall_1h = hourly_precip.length > 0 ? hourly_precip[hourly_precip.length - 1] : 0.0;
    return { rainfall_mm_1h: rainfall_1h };
  } catch (e) {
    logger.error('Failed to fetch Open-Meteo', e);
    return null;
  }
}

async function sendRadarPush(user: any, locId: string, loc: any, weather: any) {
  const title_ur = `⚠️ ${loc.name_ur || loc.name} ke qareeb seelaab ka khatra`;
  const title_en = `⚠️ Flooding likely near ${loc.name}`;
  const body_ur = `${weather.rainfall_mm_1h}mm baarish 1 ghantay mein. Agar zaroori nahi, ${loc.name_ur || loc.name} ka ilaaqa avoid karein.`;
  const body_en = `${weather.rainfall_mm_1h}mm rain in 1h. Avoid ${loc.name} if not essential.`;

  const language = user.language || 'en';
  const title = language === 'en' ? title_en : title_ur;
  const body = language === 'en' ? body_en : body_ur;

  if (!user.fcm_token) return;

  try {
    await getMessaging().send({
      token: user.fcm_token,
      notification: { title, body },
      data: {
        type: 'underpass_radar',
        location_id: locId,
        tier: 'high'
      },
      android: { priority: 'high' }
    });
    logger.info(`Push sent to ${user.fcm_token} for ${loc.name}`);
  } catch (error) {
    logger.error(`Failed to send push to ${user.fcm_token}`, error);
  }
}
