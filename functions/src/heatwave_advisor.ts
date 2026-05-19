// functions/src/heatwave_advisor.ts
// M11 — Heatwave Personal Advisor
//
// Scheduled Cloud Function (every 15 min) that checks heat conditions
// in Pakistan's heat-prone cities and sends personalized, bilingual
// push notifications with nearest cooling center to outdoor users.

import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import * as geofire from 'geofire-common';

const db = getFirestore();

// ─── City coordinates for weather fetching ───
const HEAT_CITIES: Record<string, { lat: number; lon: number }> = {
  'Karachi':    { lat: 24.8607, lon: 67.0011 },
  'Hyderabad':  { lat: 25.3960, lon: 68.3578 },
  'Multan':     { lat: 30.1575, lon: 71.5249 },
  'Jacobabad':  { lat: 28.2769, lon: 68.4514 },
  'Sukkur':     { lat: 27.7052, lon: 68.8574 },
};

// Heat index thresholds (°C)
const HEAT_INDEX_ALERT_THRESHOLD = 42;     // Start sending alerts
const HEAT_INDEX_EMERGENCY_THRESHOLD = 48; // Ping emergency contacts
const DEDUP_WINDOW_MS = 4 * 3600 * 1000;  // 4 hours

// Heatwave season: April (3) through September (8), 0-indexed months
const HEATWAVE_SEASON_START = 3; // April
const HEATWAVE_SEASON_END = 8;   // September

// ─── Main scheduled function ───

export const heatwaveAdvisor = onSchedule(
  {
    schedule: 'every 15 minutes',
    region: 'asia-south1',
    timeZone: 'Asia/Karachi',
  },
  async () => {
    // Check if we're in heatwave season
    const now = new Date();
    const month = now.getMonth(); // 0-indexed
    if (month < HEATWAVE_SEASON_START || month > HEATWAVE_SEASON_END) {
      logger.info('Outside heatwave season (April–September). Skipping.');
      return;
    }

    logger.info('Heatwave Advisor running for cities:', Object.keys(HEAT_CITIES));

    for (const [city, coords] of Object.entries(HEAT_CITIES)) {
      try {
        await processCityHeatwave(city, coords.lat, coords.lon);
      } catch (error) {
        logger.error(`Error processing heatwave for ${city}:`, error);
      }
    }
  }
);

// ─── Per-city processing ───

async function processCityHeatwave(city: string, lat: number, lon: number): Promise<void> {
  // 1. Fetch current weather
  const weather = await getLatestWeather(lat, lon);
  if (!weather) {
    logger.warn(`No weather data for ${city}. Skipping.`);
    return;
  }

  // 2. Compute heat index
  const heatIndex = computeHeatIndex(weather.temp_c, weather.humidity);
  logger.info(`${city}: temp=${weather.temp_c}°C, humidity=${weather.humidity}%, heatIndex=${heatIndex.toFixed(1)}°C`);

  if (heatIndex < HEAT_INDEX_ALERT_THRESHOLD) {
    logger.info(`${city}: Heat index ${heatIndex.toFixed(1)}°C below threshold (${HEAT_INDEX_ALERT_THRESHOLD}°C). Safe.`);
    return;
  }

  // 3. Fetch users in this city
  const usersSnap = await db.collection('users').where('city', '==', city).get();
  if (usersSnap.empty) {
    logger.info(`${city}: No users found.`);
    return;
  }

  let alertsSent = 0;
  let emergencyPings = 0;

  for (const userDoc of usersSnap.docs) {
    const userData = userDoc.data();

    // 4. Check if user is likely outdoors
    if (!isLikelyOutdoors(userData)) {
      continue;
    }

    // 5. Deduplication check
    if (await sentRecently(userDoc.id, DEDUP_WINDOW_MS)) {
      continue;
    }

    // 6. Find nearest cooling spots
    const coolingSpots = await findNearestCoolingSpots(
      userData.last_known_location,
      3
    );

    // 7. Send heatwave push notification
    await sendHeatwavePush(userData, userDoc.id, heatIndex, weather, coolingSpots, city);
    alertsSent++;

    // 8. Emergency contact ping for extreme heat
    if (heatIndex >= HEAT_INDEX_EMERGENCY_THRESHOLD && userData.emergency_contacts?.length > 0) {
      await notifyEmergencyContact(userData, heatIndex, city);
      emergencyPings++;
    }

    // 9. Record warning for deduplication
    await db.collection('heatwave_warnings').add({
      user_id: userDoc.id,
      city,
      heat_index: Math.round(heatIndex * 10) / 10,
      temp_c: weather.temp_c,
      humidity: weather.humidity,
      sent_at: FieldValue.serverTimestamp(),
      cooling_spots_sent: coolingSpots.map(s => ({
        name: s.name,
        type: s.type,
        distance_m: s.distance_m,
      })),
      emergency_contact_pinged: heatIndex >= HEAT_INDEX_EMERGENCY_THRESHOLD,
    });
  }

  logger.info(`${city}: ${alertsSent} alerts sent, ${emergencyPings} emergency pings.`);
}

// ─── Heat Index: Rothfusz regression ───
// Converts to Fahrenheit internally, returns result in Celsius.

export function computeHeatIndex(tempC: number, humidity: number): number {
  const T = tempC * 9 / 5 + 32; // °C → °F
  const R = humidity;

  // Simple formula for low heat index
  let hi = 0.5 * (T + 61.0 + ((T - 68.0) * 1.2) + (R * 0.094));

  if (hi >= 80) {
    // Full Rothfusz regression
    hi = -42.379
      + 2.04901523 * T
      + 10.14333127 * R
      - 0.22475541 * T * R
      - 0.00683783 * T * T
      - 0.05481717 * R * R
      + 0.00122874 * T * T * R
      + 0.00085282 * T * R * R
      - 0.00000199 * T * T * R * R;

    // Adjustment for low humidity
    if (R < 13 && T >= 80 && T <= 112) {
      hi -= ((13 - R) / 4) * Math.sqrt((17 - Math.abs(T - 95)) / 17);
    }

    // Adjustment for high humidity
    if (R > 85 && T >= 80 && T <= 87) {
      hi += ((R - 85) / 10) * ((87 - T) / 5);
    }
  }

  // Convert back to Celsius
  return (hi - 32) * 5 / 9;
}

// ─── Outdoor detection heuristic ───
// Per CIRO spec:
//   - User reported in last 30 min → outdoors
//   - App opened in last 15 min + movement >5km/h → outdoors
//   - Otherwise → indoors (no push)

function isLikelyOutdoors(userData: any): boolean {
  const now = Date.now();

  // Check last_report_at: if user submitted a report in last 30 min → outdoors
  if (userData.last_report_at) {
    const reportTime = userData.last_report_at instanceof Timestamp
      ? userData.last_report_at.toMillis()
      : new Date(userData.last_report_at).getTime();
    if (now - reportTime < 30 * 60 * 1000) {
      return true;
    }
  }

  // Check last_app_open_at + movement speed
  if (userData.last_app_open_at) {
    const openTime = userData.last_app_open_at instanceof Timestamp
      ? userData.last_app_open_at.toMillis()
      : new Date(userData.last_app_open_at).getTime();
    if (now - openTime < 15 * 60 * 1000) {
      // Check movement speed if available
      if (userData.movement_speed_kmh && userData.movement_speed_kmh > 5) {
        return true;
      }
      // If app was open recently but no movement data, still consider possibly outdoors
      // for rickshaw drivers / laborers who may have low-end phones
      return true;
    }
  }

  // Check last_location_at: if location updated recently, likely active
  if (userData.last_location_at) {
    const locTime = userData.last_location_at instanceof Timestamp
      ? userData.last_location_at.toMillis()
      : new Date(userData.last_location_at).getTime();
    if (now - locTime < 15 * 60 * 1000) {
      return true;
    }
  }

  // Fallback for seed data: check last_activity field
  if (userData.last_activity === 'outdoor_report' || userData.last_activity === 'app_open_moving') {
    return true;
  }

  return false;
}

// ─── Deduplication ───

async function sentRecently(userId: string, windowMs: number): Promise<boolean> {
  const cutoff = Timestamp.fromMillis(Date.now() - windowMs);
  const existing = await db.collection('heatwave_warnings')
    .where('user_id', '==', userId)
    .where('sent_at', '>', cutoff)
    .orderBy('sent_at', 'desc')
    .limit(1)
    .get();

  return !existing.empty;
}

// ─── Cooling spot finder ───

interface CoolingSpot {
  name: string;
  type: string;
  location: { latitude: number; longitude: number };
  address: string;
  distance_m: number;
  has_medical: boolean;
}

async function findNearestCoolingSpots(
  userLocation: { latitude: number; longitude: number },
  k: number
): Promise<CoolingSpot[]> {
  if (!userLocation) return [];

  const center: [number, number] = [userLocation.latitude, userLocation.longitude];

  // Query cooling spots within 5km radius using geohash bounds
  const radiusM = 5000;
  const bounds = geofire.geohashQueryBounds(center, radiusM);

  const spotsSnap = await db.collection('safe_spots')
    .where('has_cooling', '==', true)
    .get();

  const spotsWithDistance: CoolingSpot[] = [];

  for (const doc of spotsSnap.docs) {
    const data = doc.data();
    if (!data.location) continue;

    const spotLat = data.location.latitude || data.location._latitude;
    const spotLon = data.location.longitude || data.location._longitude;
    if (!spotLat || !spotLon) continue;

    const distKm = geofire.distanceBetween(center, [spotLat, spotLon]);
    const distM = distKm * 1000;

    if (distM <= radiusM) {
      spotsWithDistance.push({
        name: data.name,
        type: data.type,
        location: { latitude: spotLat, longitude: spotLon },
        address: data.address || '',
        distance_m: Math.round(distM),
        has_medical: data.has_medical || false,
      });
    }
  }

  // Sort by distance and take top k
  spotsWithDistance.sort((a, b) => a.distance_m - b.distance_m);
  return spotsWithDistance.slice(0, k);
}

// ─── Push notification ───

async function sendHeatwavePush(
  userData: any,
  userId: string,
  heatIndex: number,
  weather: { temp_c: number; humidity: number },
  coolingSpots: CoolingSpot[],
  city: string
): Promise<void> {
  const hiRounded = Math.round(heatIndex);
  const nearest = coolingSpots[0];
  const walkMinutes = nearest ? Math.round(nearest.distance_m / 80) : 0; // ~80m/min walking

  // Bilingual content
  const title_ur = `🌡️ Sakht garmi — apna khayal rakhein`;
  const title_en = `🌡️ Extreme Heat Alert — Stay Safe`;

  let body_ur = `${city} mein heat index ${hiRounded}°C.`;
  let body_en = `Heat index ${hiRounded}°C in ${city}.`;

  if (nearest) {
    body_ur += ` Aap se ${nearest.distance_m}m door ${nearest.name} thanda hai, jaane mein ${walkMinutes} min. Paani peeyein, dhoop avoid karein.`;
    body_en += ` ${nearest.name} is ${nearest.distance_m}m away (~${walkMinutes} min walk) with cooling. Stay hydrated, avoid direct sun.`;
  } else {
    body_ur += ` Paani peeyein, dhoop avoid karein, kisi thandi jagah mein jaayein.`;
    body_en += ` Stay hydrated, avoid direct sun, seek shade or indoor shelter.`;
  }

  const language = userData.language || 'en';
  const isUrdu = language === 'ur' || language === 'roman_ur';
  const title = isUrdu ? title_ur : title_en;
  const body = isUrdu ? body_ur : body_en;

  if (!userData.fcm_token) {
    logger.info(`User ${userId} has no FCM token. Logging alert only.`);
    return;
  }

  try {
    // Build data payload with map action
    const dataPayload: Record<string, string> = {
      type: 'heatwave_advisory',
      heat_index: hiRounded.toString(),
      city,
      tier: hiRounded >= HEAT_INDEX_EMERGENCY_THRESHOLD ? 'sos' : 'high',
    };

    if (nearest) {
      dataPayload['cooling_spot_name'] = nearest.name;
      dataPayload['cooling_spot_lat'] = nearest.location.latitude.toString();
      dataPayload['cooling_spot_lon'] = nearest.location.longitude.toString();
      // Google Maps navigation intent
      dataPayload['map_url'] = `https://www.google.com/maps/dir/?api=1&destination=${nearest.location.latitude},${nearest.location.longitude}&travelmode=walking`;
    }

    await getMessaging().send({
      token: userData.fcm_token,
      notification: { title, body },
      data: dataPayload,
      android: {
        priority: 'high',
        notification: {
          channelId: 'heatwave_alerts',
          priority: 'high',
          defaultVibrateTimings: true,
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    });
    logger.info(`Heatwave push sent to ${userId} (${city}, HI=${hiRounded}°C)`);
  } catch (error) {
    logger.error(`Failed to send heatwave push to ${userId}:`, error);
  }
}

// ─── Emergency contact notification (heat index ≥ 48°C) ───
// Generates a WhatsApp deep link message for the user's emergency contact.

async function notifyEmergencyContact(
  userData: any,
  heatIndex: number,
  city: string
): Promise<void> {
  if (!userData.emergency_contacts || userData.emergency_contacts.length === 0) return;

  const contact = userData.emergency_contacts[0];
  const userName = userData.display_name || 'Aapka pyaara';
  const hiRounded = Math.round(heatIndex);

  // Clean phone number for WhatsApp (remove + and spaces)
  const cleanPhone = contact.phone.replace(/[\s+\-]/g, '');

  const message_ur = `Salaam, ${userName} ${city} mein hai aur garmi bohat zyada hai (heat index ${hiRounded}°C). Please check-in karein.`;
  const message_en = `Hello, ${userName} is in ${city} and the heat is extreme (heat index ${hiRounded}°C). Please check on them.`;

  const language = userData.language || 'en';
  const isUrdu = language === 'ur' || language === 'roman_ur';
  const message = isUrdu ? message_ur : message_en;

  // Store the WhatsApp deep link in push_queue for the app to handle
  await db.collection('push_queue').add({
    user_id: userData.uid || '',
    type: 'heatwave_emergency_contact',
    payload: {
      contact_name: contact.name,
      contact_phone: contact.phone,
      whatsapp_url: `https://wa.me/${cleanPhone}?text=${encodeURIComponent(message)}`,
      message,
      heat_index: hiRounded,
      city,
    },
    urgency: 'sos',
    created_at: FieldValue.serverTimestamp(),
    processed: false,
  });

  // Also send push to user to prompt them to share
  if (userData.fcm_token) {
    try {
      const title = isUrdu
        ? `🚨 Apne ghar walon ko batayein!`
        : `🚨 Alert your family!`;
      const body = isUrdu
        ? `Heat index ${hiRounded}°C! ${contact.name} ko WhatsApp bhejein.`
        : `Heat index ${hiRounded}°C! Share alert with ${contact.name} via WhatsApp.`;

      await getMessaging().send({
        token: userData.fcm_token,
        notification: { title, body },
        data: {
          type: 'heatwave_family_alert',
          whatsapp_url: `https://wa.me/${cleanPhone}?text=${encodeURIComponent(message)}`,
          contact_name: contact.name,
          tier: 'sos',
        },
        android: {
          priority: 'high',
          notification: {
            channelId: 'heatwave_alerts',
            priority: 'max',
          },
        },
      });
      logger.info(`Emergency contact ping sent for user ${userData.display_name}`);
    } catch (error) {
      logger.error(`Failed to send emergency contact ping:`, error);
    }
  }
}

// ─── Weather fetcher (Open-Meteo) ───

async function getLatestWeather(
  lat: number,
  lon: number
): Promise<{ temp_c: number; humidity: number; wind_kph: number } | null> {
  try {
    const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,relative_humidity_2m,wind_speed_10m&timezone=Asia/Karachi`;
    const response = await fetch(url);
    if (!response.ok) return null;

    const data = await response.json() as any;
    const current = data.current;
    if (!current) return null;

    return {
      temp_c: current.temperature_2m ?? 0,
      humidity: current.relative_humidity_2m ?? 0,
      wind_kph: current.wind_speed_10m ?? 0,
    };
  } catch (error) {
    logger.error('Failed to fetch weather from Open-Meteo:', error);
    return null;
  }
}
