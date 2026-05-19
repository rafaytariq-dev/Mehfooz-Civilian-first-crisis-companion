import { SimulationReport } from '../types';

interface Props {
  report: SimulationReport | null;
  ticketCount: number;
}

export default function ImpactSummary({ report, ticketCount }: Props) {
  if (!report) {
    return (
      <footer className="impact-bar impact-bar--empty">
        <span className="impact-waiting">
          ⏳ Waiting for simulation report… Trigger the G-10 scenario to see impact metrics.
        </span>
      </footer>
    );
  }

  const { notifications_queued, routes_flagged, estimated_impact } = report;
  const totalAlerted = notifications_queued?.total_users ?? 0;
  const congest = Math.round(estimated_impact?.congestion_reduction_min ?? 0);
  const diverted = estimated_impact?.users_diverted ?? 0;
  const responseSaved = estimated_impact?.response_time_saved_min ?? 0;

  return (
    <footer className="impact-bar">
      <div className="impact-label">Impact summary (last run)</div>
      <div className="impact-stats">
        <span className="impact-stat">
          <span className="impact-num">{totalAlerted}</span> users alerted
        </span>
        <span className="impact-divider">·</span>
        <span className="impact-stat">
          <span className="impact-num">{routes_flagged}</span> routes flagged
        </span>
        <span className="impact-divider">·</span>
        <span className="impact-stat">
          <span className="impact-num">{ticketCount}</span>{' '}
          ticket{ticketCount !== 1 ? 's' : ''} dispatched
        </span>
        <span className="impact-divider">·</span>
        <span className="impact-stat">
          Est.{' '}
          <span className="impact-num">{congest} min</span> congestion reduction
        </span>
        {diverted > 0 && (
          <>
            <span className="impact-divider">·</span>
            <span className="impact-stat">
              <span className="impact-num">{diverted}</span> users diverted
            </span>
          </>
        )}
        {responseSaved > 0 && (
          <>
            <span className="impact-divider">·</span>
            <span className="impact-stat">
              <span className="impact-num">{responseSaved} min</span> faster response
            </span>
          </>
        )}
      </div>
      <div className="impact-disclaimer">
        ⚠️ Estimates are heuristics for demonstration. Production would use historical baselines.
      </div>
    </footer>
  );
}
