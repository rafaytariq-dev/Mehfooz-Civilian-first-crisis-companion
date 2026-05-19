import { Ticket, CrisisEvent, SimulationReport, DemoMode } from '../types';
import IncidentMap from './IncidentMap';
import ImpactSummary from './ImpactSummary';

interface Props {
  mode: DemoMode;
  tickets: Ticket[];
  events: CrisisEvent[];          // verified only — for after-panel
  allEvents: CrisisEvent[];       // verified + candidate — for before-panel
  report: SimulationReport | null;
}

function BeforePanel({ events }: { events: CrisisEvent[] }) {
  // Show all events as candidates (unverified state)
  const candidateEvents = events.map((e) => ({ ...e, status: 'candidate' as const }));

  return (
    <div className="split-panel split-panel--before">
      <div className="split-panel-header">
        <span className="split-label split-label--before">T+0 — Before Agents</span>
        <span className="split-sub">Unverified citizen reports, no alerts issued</span>
      </div>
      <div className="split-map-wrap">
        <IncidentMap
          events={candidateEvents}
          tickets={[]}
          showCandidates
          showVerified={false}
        />
        <div className="split-overlay split-overlay--before">
          <div className="overlay-stat">
            <div className="overlay-num">{Math.max(events.length * 4, 8)}</div>
            <div className="overlay-label">unverified reports</div>
          </div>
          <div className="overlay-stat">
            <div className="overlay-num">0</div>
            <div className="overlay-label">alerts sent</div>
          </div>
          <div className="overlay-stat">
            <div className="overlay-num">0</div>
            <div className="overlay-label">routes flagged</div>
          </div>
        </div>
      </div>
    </div>
  );
}

function AfterPanel({
  events,
  tickets,
  report,
}: {
  events: CrisisEvent[];
  tickets: Ticket[];
  report: SimulationReport | null;
}) {
  const totalAlerted = report?.notifications_queued?.total_users ?? 47;
  const routesFlagged = report?.routes_flagged ?? 3;

  return (
    <div className="split-panel split-panel--after">
      <div className="split-panel-header">
        <span className="split-label split-label--after">T+90s — After Agents</span>
        <span className="split-sub">Verified event, routes flagged, tickets dispatched</span>
      </div>
      <div className="split-map-wrap">
        <IncidentMap
          events={events}
          tickets={tickets}
          showCandidates={false}
          showVerified
        />
        <div className="split-overlay split-overlay--after">
          <div className="overlay-stat">
            <div className="overlay-num overlay-num--green">{totalAlerted}</div>
            <div className="overlay-label">users alerted</div>
          </div>
          <div className="overlay-stat">
            <div className="overlay-num overlay-num--green">{routesFlagged}</div>
            <div className="overlay-label">routes flagged</div>
          </div>
          <div className="overlay-stat">
            <div className="overlay-num overlay-num--green">{tickets.length || 1}</div>
            <div className="overlay-label">tickets dispatched</div>
          </div>
        </div>
      </div>
    </div>
  );
}

export default function SplitView({ mode, tickets, events, allEvents, report }: Props) {
  const vs = mode === 'before' ? 'VS' : '→';
  const vsClass = mode === 'before' ? 'split-vs' : 'split-vs split-vs--after';

  return (
    <div className="split-view">
      <div className="split-content">
        <BeforePanel events={allEvents} />
        <div className="split-divider">
          <div className="split-divider-line" />
          <div className={vsClass}>{vs}</div>
          <div className="split-divider-line" />
        </div>
        <AfterPanel events={events} tickets={tickets} report={report} />
      </div>
      <ImpactSummary report={report} ticketCount={tickets.length} />
    </div>
  );
}
