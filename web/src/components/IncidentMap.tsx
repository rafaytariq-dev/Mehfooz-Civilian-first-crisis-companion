import { useEffect, useRef } from 'react';
import { CrisisEvent, Ticket, GeoPoint } from '../types';

interface Props {
  events: CrisisEvent[];
  tickets: Ticket[];
  showCandidates?: boolean;
  showVerified?: boolean;
}

const MAPS_API_KEY = import.meta.env.VITE_GOOGLE_MAPS_API_KEY as string;

// Islamabad G-10/G-11 center
const DEFAULT_CENTER = { lat: 33.6844, lng: 73.0479 };
const DEFAULT_ZOOM = 13;

const SEV_COLORS: Record<number, string> = {
  1: '#90EE90',
  2: '#E9C46A',
  3: '#F4A261',
  4: '#E76F51',
  5: '#D62828',
};

function geoPointToLatLng(gp: GeoPoint): google.maps.LatLngLiteral {
  return { lat: gp.latitude, lng: gp.longitude };
}

function loadMapsScript(apiKey: string): Promise<void> {
  if (window.google?.maps) return Promise.resolve();
  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = `https://maps.googleapis.com/maps/api/js?key=${apiKey}&libraries=visualization`;
    script.async = true;
    script.onload = () => resolve();
    script.onerror = reject;
    document.head.appendChild(script);
  });
}

export default function IncidentMap({ events, tickets, showCandidates = true, showVerified = true }: Props) {
  const mapRef = useRef<HTMLDivElement>(null);
  const mapInstanceRef = useRef<google.maps.Map | null>(null);
  const overlaysRef = useRef<(google.maps.Polygon | google.maps.Marker)[]>([]);

  useEffect(() => {
    if (!MAPS_API_KEY) return;

    loadMapsScript(MAPS_API_KEY).then(() => {
      if (!mapRef.current || mapInstanceRef.current) return;
      mapInstanceRef.current = new google.maps.Map(mapRef.current, {
        center: DEFAULT_CENTER,
        zoom: DEFAULT_ZOOM,
        mapTypeId: 'roadmap',
        styles: [
          { featureType: 'poi', stylers: [{ visibility: 'off' }] },
          { featureType: 'transit', stylers: [{ visibility: 'off' }] },
        ],
        disableDefaultUI: false,
        zoomControl: true,
        streetViewControl: false,
        mapTypeControl: false,
      });
    });
  }, []);

  // Redraw overlays when data changes
  useEffect(() => {
    const map = mapInstanceRef.current;
    if (!map) return;

    // Clear previous overlays
    overlaysRef.current.forEach((o) => o.setMap(null));
    overlaysRef.current = [];

    // Draw event polygons
    for (const evt of events) {
      if (evt.status === 'verified' && showVerified && evt.polygon?.length >= 3) {
        const polygon = new google.maps.Polygon({
          paths: evt.polygon.map(geoPointToLatLng),
          strokeColor: SEV_COLORS[evt.severity] ?? '#D62828',
          strokeOpacity: 0.9,
          strokeWeight: 2,
          fillColor: SEV_COLORS[evt.severity] ?? '#D62828',
          fillOpacity: 0.3,
          map,
        });

        const infoWindow = new google.maps.InfoWindow({
          content: `
            <div style="font-family:Inter,sans-serif;max-width:220px">
              <b style="color:#D62828">${evt.type.replace(/_/g, ' ').toUpperCase()}</b>
              <br/>Severity ${evt.severity} · Confidence ${Math.round(evt.confidence * 100)}%
              <br/><small style="color:#555">${evt.explanation_en}</small>
            </div>
          `,
        });

        polygon.addListener('click', (e: google.maps.MapMouseEvent) => {
          infoWindow.setPosition(e.latLng);
          infoWindow.open(map);
        });

        overlaysRef.current.push(polygon);
      }

      if (evt.status === 'candidate' && showCandidates && evt.centroid) {
        const marker = new google.maps.Marker({
          position: geoPointToLatLng(evt.centroid),
          map,
          title: `Candidate: ${evt.type}`,
          icon: {
            path: google.maps.SymbolPath.CIRCLE,
            scale: 8,
            fillColor: '#E9C46A',
            fillOpacity: 0.8,
            strokeColor: '#B8860B',
            strokeWeight: 1.5,
          },
        });
        overlaysRef.current.push(marker);
      }
    }

    // Draw ticket pins
    for (const t of tickets) {
      if (!t.payload?.centroid) continue;
      const centroid = t.payload.centroid as GeoPoint;
      const marker = new google.maps.Marker({
        position: geoPointToLatLng(centroid),
        map,
        title: t.ticket_id,
        icon: {
          path: google.maps.SymbolPath.BACKWARD_CLOSED_ARROW,
          scale: 6,
          fillColor: '#2A9D8F',
          fillOpacity: 1,
          strokeColor: '#1a6b64',
          strokeWeight: 1.5,
        },
      });
      overlaysRef.current.push(marker);
    }
  }, [events, tickets, showCandidates, showVerified]);

  if (!MAPS_API_KEY) {
    return (
      <div className="map-placeholder">
        <div className="map-placeholder-inner">
          <div style={{ fontSize: 40 }}>🗺️</div>
          <p>Set <code>VITE_GOOGLE_MAPS_API_KEY</code> to enable the live map.</p>
          <p className="empty-sub">
            {events.length} verified event{events.length !== 1 ? 's' : ''} ·{' '}
            {tickets.length} ticket{tickets.length !== 1 ? 's' : ''}
          </p>
        </div>
      </div>
    );
  }

  return <div ref={mapRef} className="incident-map" />;
}
