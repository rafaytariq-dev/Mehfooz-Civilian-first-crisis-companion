import { Ticket } from '../types';

interface Props {
  tickets: Ticket[];
}

const AUTHORITY_LABELS: Record<string, string> = {
  'PDMA-Punjab': 'PDMA Punjab',
  'Rescue-1122': 'Rescue 1122',
  'NDMA': 'NDMA',
  'Traffic-Police': 'Traffic Police',
};

function severityLabel(sev: number | undefined): string {
  if (!sev) return '—';
  const labels = ['', 'Minor', 'Localized', 'Significant', 'Severe', 'Life-threatening'];
  return labels[sev] ?? `Sev ${sev}`;
}

function severityClass(sev: number | undefined): string {
  if (!sev || sev <= 2) return 'sev-low';
  if (sev === 3) return 'sev-med';
  return 'sev-high';
}

function timeAgo(ts: { toMillis: () => number } | null): string {
  if (!ts) return '—';
  const diffMs = Date.now() - ts.toMillis();
  const diffMin = Math.floor(diffMs / 60000);
  if (diffMin < 1) return 'just now';
  if (diffMin < 60) return `${diffMin} min ago`;
  return `${Math.floor(diffMin / 60)}h ago`;
}

export default function TicketList({ tickets }: Props) {
  if (tickets.length === 0) {
    return (
      <div className="ticket-list">
        <div className="panel-header">
          <span className="panel-title">Active Tickets</span>
          <span className="ticket-count">0</span>
        </div>
        <div className="empty-state">
          <div className="empty-icon">📋</div>
          <p>No dispatches yet</p>
          <p className="empty-sub">Tickets appear when agents fire</p>
        </div>
      </div>
    );
  }

  return (
    <div className="ticket-list">
      <div className="panel-header">
        <span className="panel-title">Active Tickets</span>
        <span className="ticket-count">{tickets.length}</span>
      </div>
      <div className="ticket-scroll">
        {tickets.map((t) => (
          <div key={t.id} className="ticket-card">
            <div className="ticket-header-row">
              <span className="ticket-id">{t.ticket_id ?? t.id.slice(0, 10).toUpperCase()}</span>
              <span className={`severity-chip ${severityClass(t.payload?.severity)}`}>
                {severityLabel(t.payload?.severity)}
              </span>
            </div>
            <div className="ticket-authority">
              {AUTHORITY_LABELS[t.authority] ?? t.authority}
            </div>
            {t.payload?.event_type && (
              <div className="ticket-type">{t.payload.event_type}</div>
            )}
            {t.payload?.location && (
              <div className="ticket-location">📍 {t.payload.location}</div>
            )}
            <div className="ticket-footer-row">
              <span className={`ticket-status status-${t.status}`}>{t.status}</span>
              <span className="ticket-time">{timeAgo(t.received_at)}</span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
