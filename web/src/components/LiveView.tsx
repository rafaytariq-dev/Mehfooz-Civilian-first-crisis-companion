import { Ticket, CrisisEvent, SimulationReport } from '../types';
import TicketList from './TicketList';
import IncidentMap from './IncidentMap';
import ImpactSummary from './ImpactSummary';

interface Props {
  tickets: Ticket[];
  events: CrisisEvent[];
  report: SimulationReport | null;
}

export default function LiveView({ tickets, events, report }: Props) {
  return (
    <div className="live-view">
      <div className="content-row">
        <TicketList tickets={tickets} />
        <div className="map-panel">
          <div className="panel-header">
            <span className="panel-title">Live Incident Map</span>
            <div className="map-legend">
              <span className="legend-item">
                <span className="legend-dot" style={{ background: '#D62828' }} /> Verified
              </span>
              <span className="legend-item">
                <span className="legend-dot" style={{ background: '#E9C46A' }} /> Candidate
              </span>
              <span className="legend-item">
                <span className="legend-dot" style={{ background: '#2A9D8F' }} /> Ticket
              </span>
            </div>
          </div>
          <IncidentMap events={events} tickets={tickets} showCandidates showVerified />
        </div>
      </div>
      <ImpactSummary report={report} ticketCount={tickets.length} />
    </div>
  );
}
