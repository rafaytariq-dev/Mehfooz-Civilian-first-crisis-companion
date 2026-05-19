import { useEffect, useState } from 'react';
import {
  collection,
  query,
  orderBy,
  limit,
  where,
  onSnapshot,
} from 'firebase/firestore';
import { db } from './firebase';
import { Ticket, CrisisEvent, SimulationReport, DemoMode } from './types';
import LiveView from './components/LiveView';
import SplitView from './components/SplitView';

export default function App() {
  const [tickets, setTickets] = useState<Ticket[]>([]);
  const [events, setEvents] = useState<CrisisEvent[]>([]);
  const [allEvents, setAllEvents] = useState<CrisisEvent[]>([]);
  const [report, setReport] = useState<SimulationReport | null>(null);
  const [demoMode, setDemoMode] = useState<DemoMode>('live');
  const [isConnected, setIsConnected] = useState(true);

  useEffect(() => {
    const unsub1 = onSnapshot(
      query(collection(db, 'mock_dispatches'), orderBy('received_at', 'desc'), limit(50)),
      (snap) => {
        setIsConnected(true);
        setTickets(
          snap.docs.map((d) => ({ id: d.id, ...d.data() } as Ticket))
        );
      },
      () => setIsConnected(false)
    );

    // Verified events — used by live view and after-panel
    const unsub2 = onSnapshot(
      query(collection(db, 'events'), where('status', '==', 'verified')),
      (snap) => {
        setEvents(
          snap.docs.map((d) => ({ id: d.id, ...d.data() } as CrisisEvent))
        );
      }
    );

    // All events (verified + candidate) — used by before-panel in split view
    const unsub2b = onSnapshot(
      query(collection(db, 'events'), where('status', 'in', ['verified', 'candidate'])),
      (snap) => {
        setAllEvents(
          snap.docs.map((d) => ({ id: d.id, ...d.data() } as CrisisEvent))
        );
      }
    );

    const unsub3 = onSnapshot(
      query(
        collection(db, 'simulation_reports'),
        orderBy('executed_at', 'desc'),
        limit(1)
      ),
      (snap) => {
        if (snap.docs[0]) setReport(snap.docs[0].data() as SimulationReport);
      }
    );

    return () => {
      unsub1();
      unsub2();
      unsub2b();
      unsub3();
    };
  }, []);

  return (
    <div className="app-shell">
      <header className="app-header">
        <div className="header-left">
          <span className="header-logo">محفوظ</span>
          <span className="header-title">Mehfooz — Authority Simulation</span>
          <span className="header-authority">PDMA Punjab</span>
        </div>
        <div className="header-right">
          <span className={`live-badge ${isConnected ? 'connected' : 'disconnected'}`}>
            <span className="live-dot" />
            {isConnected ? 'Live' : 'Reconnecting…'}
          </span>
          <div className="demo-toggle">
            {(['live', 'before', 'after'] as DemoMode[]).map((mode) => (
              <button
                key={mode}
                className={`toggle-btn ${demoMode === mode ? 'active' : ''}`}
                onClick={() => setDemoMode(mode)}
              >
                {mode === 'live' ? 'Live' : mode === 'before' ? 'Demo: Before' : 'Demo: After'}
              </button>
            ))}
          </div>
        </div>
      </header>

      <main className="app-main">
        {demoMode === 'live' ? (
          <LiveView tickets={tickets} events={events} report={report} />
        ) : (
          <SplitView mode={demoMode} tickets={tickets} events={events} allEvents={allEvents} report={report} />
        )}
      </main>
    </div>
  );
}
