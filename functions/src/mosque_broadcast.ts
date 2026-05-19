// functions/src/mosque_broadcast.ts
// M14 — Mosque Admin Broadcast
//
// Verified mosque admins post hyper-local crisis broadcasts. Cloud Functions
// fan them out via FCM to users within radius_m (default 3km) and enforce
// misuse controls: rate-limit (1 per 30 min unless severity >=3), 6h auto-expire,
// flagging when 3+ users mark a broadcast.

import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import * as geofire from 'geofire-common';

const db = getFirestore();

const DEFAULT_RADIUS_M = 3000;
const BROADCAST_TTL_HOURS = 6;
const RATE_LIMIT_WINDOW_MS = 30 * 60 * 1000; // 30 min
const FLAG_AUTO_PULL_THRESHOLD = 3;

const ALLOWED_CRISIS_TYPES = new Set([
  'flood',
  'urban_flood',
  'flash_flood',
  'heatwave',
  'road_incident',
  'fire',
  'building_collapse',
  'power_outage',
  'shelter',
  'general_safety',
]);

// ─── 1. Fan-out trigger ───
// When a broadcasts/{id} doc is created, deliver to users within radius.

export const onBroadcastCreated = onDocumentCreated(
  {
    document: 'broadcasts/{broadcastId}',
    region: 'asia-south1',
  },
  async (event) => {
    const broadcastId = event.params.broadcastId;
    const snap = event.data;
    if (!snap) return;
    const b = snap.data();

    // Validate required fields
    if (!b.mosque_id || !b.admin_uid || !b.crisis_type) {
      logger.warn(`Broadcast ${broadcastId} missing required fields, deleting`);
      await snap.ref.delete();
      return;
    }

    if (!ALLOWED_CRISIS_TYPES.has(b.crisis_type)) {
      logger.warn(`Broadcast ${broadcastId} has disallowed crisis_type: ${b.crisis_type}`);
      await snap.ref.update({ status: 'rejected', reason: 'invalid_crisis_type' });
      return;
    }

    // Resolve mosque
    const mosqueSnap = await db.doc(`mosques/${b.mosque_id}`).get();
    if (!mosqueSnap.exists) {
      logger.error(`Broadcast ${broadcastId} references unknown mosque ${b.mosque_id}`);
      await snap.ref.update({ status: 'rejected', reason: 'unknown_mosque' });
      return;
    }
    const mosque = mosqueSnap.data()!;

    // Verify admin is in mosque admins list
    const adminUids: string[] = mosque.admin_uids || [];
    if (!adminUids.includes(b.admin_uid)) {
      logger.warn(`Broadcast ${broadcastId} admin ${b.admin_uid} not authorized for mosque ${b.mosque_id}`);
      await snap.ref.update({ status: 'rejected', reason: 'unauthorized_admin' });
      return;
    }

    // Rate-limit: 1 broadcast / 30 min unless severity >= 3
    const severity = (b.severity || 1) as number;
    if (severity < 3) {
      const cutoff = Timestamp.fromMillis(Date.now() - RATE_LIMIT_WINDOW_MS);
      const recent = await db.collection('broadcasts')
        .where('admin_uid', '==', b.admin_uid)
        .where('created_at', '>=', cutoff)
        .get();
      // Exclude self
      const others = recent.docs.filter(d => d.id !== broadcastId);
      if (others.length > 0) {
        logger.info(`Rate-limited broadcast ${broadcastId} (admin posted ${others.length} in last 30 min)`);
        await snap.ref.update({ status: 'rejected', reason: 'rate_limited' });
        return;
      }
    }

    const center: [number, number] = [
      mosque.location.latitude,
      mosque.location.longitude,
    ];
    const radius = b.radius_m || DEFAULT_RADIUS_M;

    // Compute and set expires_at if missing
    const expiresAt = b.expires_at
      || Timestamp.fromMillis(Date.now() + BROADCAST_TTL_HOURS * 3600 * 1000);

    // Geo-query users within radius (via geohash bounds)
    const bounds = geofire.geohashQueryBounds(center, radius);
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
      const dist = geofire.distanceBetween(
        [ul.latitude, ul.longitude],
        center
      ) * 1000;
      if (dist > radius) return false;
      // Skip users who muted this mosque
      const muted: string[] = u.data().muted_mosques || [];
      if (muted.includes(b.mosque_id)) return false;
      return true;
    });

    logger.info(`Broadcast ${broadcastId}: ${candidates.length} recipients within ${radius}m of ${mosque.name}`);

    // Send FCM to each (skip users with no fcm_token)
    const sendPromises = candidates
      .filter(u => !!u.data().fcm_token)
      .map(async (u) => {
        const ud = u.data();
        const language = ud.language || 'en';
        const body = language === 'en'
          ? (b.text_en || b.text_ur || '')
          : (b.text_ur || b.text_en || '');

        try {
          await getMessaging().send({
            token: ud.fcm_token,
            notification: {
              title: `🕌 ${mosque.name}`,
              body,
            },
            data: {
              type: 'mosque_broadcast',
              broadcast_id: broadcastId,
              mosque_id: b.mosque_id,
              crisis_type: b.crisis_type,
              tier: severity >= 3 ? 'high' : 'med',
            },
            android: {
              priority: severity >= 3 ? 'high' : 'normal',
            },
          });
        } catch (err) {
          logger.warn(`FCM send failed for ${u.id}`, err);
        }
      });

    await Promise.all(sendPromises);

    await snap.ref.update({
      status: 'delivered',
      delivered_count: candidates.length,
      expires_at: expiresAt,
      delivered_at: FieldValue.serverTimestamp(),
    });

    logger.info(`Broadcast ${broadcastId} delivered to ${candidates.length} users`);
  }
);

// ─── 2. Flag accumulator ───
// When a user flags a broadcast (broadcast_flags/{broadcast_id}_{user_id}),
// increment the flag count on the broadcast. If >= 3, mark as flagged and
// pull from feed.

export const onBroadcastFlagCreated = onDocumentCreated(
  {
    document: 'broadcast_flags/{flagId}',
    region: 'asia-south1',
  },
  async (event) => {
    const f = event.data?.data();
    if (!f || !f.broadcast_id) return;

    const bRef = db.doc(`broadcasts/${f.broadcast_id}`);
    await db.runTransaction(async (txn) => {
      const bSnap = await txn.get(bRef);
      if (!bSnap.exists) return;
      const flagCount = (bSnap.data()!.flag_count || 0) + 1;
      const update: any = { flag_count: flagCount };
      if (flagCount >= FLAG_AUTO_PULL_THRESHOLD) {
        update.status = 'flagged';
        update.pulled_at = FieldValue.serverTimestamp();
      }
      txn.update(bRef, update);
    });

    logger.info(`Flag recorded for broadcast ${f.broadcast_id}`);
  }
);

// ─── 3. Expiry sweeper ───
// Run hourly; mark broadcasts whose expires_at < now as 'expired'.

export const expireOldBroadcasts = onSchedule(
  {
    schedule: 'every 60 minutes',
    region: 'asia-south1',
    timeZone: 'Asia/Karachi',
  },
  async () => {
    const now = Timestamp.now();
    const stale = await db.collection('broadcasts')
      .where('status', 'in', ['delivered', 'pending'])
      .where('expires_at', '<=', now)
      .limit(200)
      .get();

    const batch = db.batch();
    stale.docs.forEach((d) => {
      batch.update(d.ref, { status: 'expired' });
    });
    await batch.commit();

    if (stale.size > 0) {
      logger.info(`Expired ${stale.size} broadcasts`);
    }
  }
);

// ─── 4. Callable: createBroadcast ───
// Verified mosque admins call this from the app. Performs server-side
// validation and writes the broadcast doc. The onBroadcastCreated trigger
// then handles fan-out.

export const createBroadcast = onCall(
  { region: 'asia-south1' },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Must be signed in to broadcast');
    }

    const { mosque_id, crisis_type, text_ur, text_en, severity } = request.data || {};
    if (!mosque_id || !crisis_type || (!text_ur && !text_en)) {
      throw new HttpsError('invalid-argument', 'Missing mosque_id, crisis_type, or text');
    }
    if (!ALLOWED_CRISIS_TYPES.has(crisis_type)) {
      throw new HttpsError('invalid-argument', `Crisis type "${crisis_type}" not allowed`);
    }

    // Cap message length (280 chars per spec)
    const cap = (s: string | undefined) => (s || '').slice(0, 280);

    // Verify user is admin of mosque
    const mosqueSnap = await db.doc(`mosques/${mosque_id}`).get();
    if (!mosqueSnap.exists) {
      throw new HttpsError('not-found', 'Mosque not found');
    }
    const adminUids: string[] = mosqueSnap.data()!.admin_uids || [];
    if (!adminUids.includes(uid)) {
      throw new HttpsError('permission-denied', 'Not an admin of this mosque');
    }

    // Verify role on user doc (defense in depth)
    const userSnap = await db.doc(`users/${uid}`).get();
    if (userSnap.exists) {
      const role = userSnap.data()!.role;
      if (role !== 'mosque_admin') {
        throw new HttpsError('permission-denied', 'User does not have mosque_admin role');
      }
    }

    const expiresAt = Timestamp.fromMillis(Date.now() + BROADCAST_TTL_HOURS * 3600 * 1000);

    const doc = await db.collection('broadcasts').add({
      mosque_id,
      admin_uid: uid,
      crisis_type,
      text_ur: cap(text_ur),
      text_en: cap(text_en),
      severity: severity || 1,
      radius_m: DEFAULT_RADIUS_M,
      created_at: FieldValue.serverTimestamp(),
      expires_at: expiresAt,
      status: 'pending',
      flag_count: 0,
    });

    return { broadcast_id: doc.id, status: 'pending', expires_at: expiresAt.toMillis() };
  }
);
