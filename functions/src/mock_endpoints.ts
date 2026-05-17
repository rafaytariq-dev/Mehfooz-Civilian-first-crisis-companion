import { onRequest } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const db = getFirestore();

export const mockPdmaDispatch = onRequest(
  { region: 'asia-south1' },
  async (req, res) => {
    const ticket_id = `PDMA-${Date.now()}`;
    await db.collection('mock_dispatches').add({
      ticket_id,
      received_at: FieldValue.serverTimestamp(),
      authority: 'PDMA-Punjab',
      payload: req.body,
      status: 'received'
    });
    res.json({ ticket_id, status: 'queued' });
  }
);

export const mockRescue1122 = onRequest(
  { region: 'asia-south1' },
  async (req, res) => {
    const ticket_id = `RES1122-${Date.now()}`;
    await db.collection('mock_dispatches').add({
      ticket_id,
      received_at: FieldValue.serverTimestamp(),
      authority: 'Rescue-1122-ICT',
      payload: req.body,
      status: 'received'
    });
    res.json({ ticket_id, status: 'queued' });
  }
);

export const mockTrafficReroute = onRequest(
  { region: 'asia-south1' },
  async (req, res) => {
    const ticket_id = `TRAF-${Date.now()}`;
    await db.collection('mock_dispatches').add({
      ticket_id,
      received_at: FieldValue.serverTimestamp(),
      authority: 'CDA-TrafficControl',
      payload: req.body,
      status: 'received'
    });
    res.json({ ticket_id, status: 'queued' });
  }
);

export const mockSmsBlast = onRequest(
  { region: 'asia-south1' },
  async (req, res) => {
    const ticket_id = `SMS-${Date.now()}`;
    await db.collection('mock_dispatches').add({
      ticket_id,
      received_at: FieldValue.serverTimestamp(),
      authority: 'SMS-Gateway-Mock',
      payload: req.body,
      status: 'received'
    });
    // IMPORTANT: does NOT send real SMS
    res.json({ ticket_id, status: 'logged_only', note: 'Mock endpoint — no real SMS sent' });
  }
);
