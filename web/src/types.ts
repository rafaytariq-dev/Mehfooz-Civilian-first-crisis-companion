export interface GeoPoint {
  latitude: number;
  longitude: number;
}

export interface Ticket {
  id: string;
  ticket_id: string;
  received_at: { toMillis: () => number } | null;
  authority: string;
  payload: {
    event_type?: string;
    severity?: number;
    location?: string;
    [key: string]: unknown;
  };
  status: string;
}

export interface CrisisEvent {
  id: string;
  type: string;
  polygon: GeoPoint[];
  centroid: GeoPoint;
  severity: 1 | 2 | 3 | 4 | 5;
  confidence: number;
  status: 'candidate' | 'verified' | 'resolved';
  explanation_en: string;
  explanation_ur: string;
  last_updated: { toMillis: () => number } | null;
}

export interface SimulationReport {
  plan_id: string;
  event_id: string;
  executed_at: { toMillis: () => number } | null;
  dispatches: { authority: string; ticket_id: string; payload_summary: string }[];
  notifications_queued: {
    sos: number;
    high: number;
    med: number;
    low: number;
    total_users: number;
  };
  routes_flagged: number;
  estimated_impact: {
    congestion_reduction_min: number;
    users_diverted: number;
    response_time_saved_min: number;
  };
  summary_en: string;
  summary_ur: string;
}

export type DemoMode = 'live' | 'before' | 'after';
