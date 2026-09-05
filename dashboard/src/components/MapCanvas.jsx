import { useState } from 'react';
import L from 'leaflet';
import { CircleMarker, MapContainer, Polygon, Marker, TileLayer, Tooltip, WMSTileLayer } from 'react-leaflet';
import { fmt } from '../lib/format';

const CENTER = [10.02, 76.32]; // Kochi, Kerala (config.GLOFAS_LAT/LNG)

const LAYERS = [
  { key: 'shelters', label: 'Shelters' },
  { key: 'hazards', label: 'Hazards' },
  { key: 'missing', label: 'Missing' },
  { key: 'flood', label: 'Flood Extent' },
  { key: 'sos', label: 'SOS' },
];

function icon(cls, size = 14) {
  return L.divIcon({ className: '', html: `<span class="pin ${cls}"></span>`, iconSize: [size, size], iconAnchor: [size / 2, size / 2] });
}

export function MapCanvas({ sos, shelters, clusters, missing, gfm }) {
  const [on, setOn] = useState({ shelters: true, hazards: true, missing: true, flood: true, sos: true });
  const toggle = (k) => setOn((s) => ({ ...s, [k]: !s[k] }));

  const hazardClusters = clusters?.clusters ?? [];
  // Live GFM flood extent arrives as a WMS descriptor; older cached rows may
  // still carry the GeoJSON fixture shape — tolerate both.
  const gfmIsWms = gfm?.mode === 'wms' && gfm?.wms_url && gfm?.layer;
  const floodPolys = gfmIsWms ? [] : extractPolygons(gfm);

  return (
    <div className="relative flex-1">
      {/* Layer toggles */}
      <div className="absolute left-1/2 top-4 z-[1000] flex -translate-x-1/2 gap-px border border-zinc-800 bg-black">
        {LAYERS.map((l) => (
          <button
            key={l.key}
            onClick={() => toggle(l.key)}
            className={`px-3 py-1.5 text-[9px] uppercase tracking-[0.2em] transition-colors ${
              on[l.key] ? 'bg-white text-black' : 'text-zinc-500 hover:text-white'
            } ${l.key === 'sos' && on.sos ? 'bg-[#FF0000] text-white' : ''}`}
          >
            {l.label}
          </button>
        ))}
      </div>

      <MapContainer center={CENTER} zoom={11} className="map-dark h-full w-full" zoomControl={true} attributionControl={true}>
        <TileLayer
          attribution="&copy; OpenStreetMap contributors"
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />

        {/* Live Copernicus GFM flood-extent overlay (EODC GeoServer WMS),
            rendered as transparent PNG tiles on top of the OSM basemap. */}
        {on.flood && gfmIsWms && (
          <WMSTileLayer
            url={gfm.wms_url}
            layers={gfm.layer}
            format="image/png"
            transparent={true}
            version="1.1.1"
            opacity={0.9}
            attribution="Copernicus GFM (EODC, Sentinel-1 SAR)"
          />
        )}

        {on.shelters &&
          (shelters ?? []).map((s) => (
            <Marker key={`sh-${s.id}`} position={[s.lat, s.lng]} icon={icon('pin-shelter')}>
              <Tooltip>
                <div className="text-xs">
                  <strong>{s.name}</strong>
                  <div>confirmed {s.confirm_count}×</div>
                </div>
              </Tooltip>
            </Marker>
          ))}

        {on.hazards &&
          hazardClusters.map((c) => (
            <CircleMarker
              key={`hz-${c.cluster_id}`}
              center={[c.centroid_lat, c.centroid_lng]}
              radius={8 + Math.min(18, (c.total_confirmations ?? 0) * 1.5)}
              pathOptions={{ color: '#a1a1aa', weight: 1, fillColor: '#71717a', fillOpacity: 0.35 }}
            >
              <Tooltip>
                <div className="max-w-[200px] text-xs">
                  <strong>{c.report_count} reports · {c.total_confirmations} confirmations</strong>
                  <div>{c.sample_description ?? 'Hazard cluster'}</div>
                </div>
              </Tooltip>
            </CircleMarker>
          ))}

        {on.missing &&
          (missing ?? [])
            .filter((m) => m.last_seen_lat != null && m.last_seen_lng != null)
            .map((m) => (
              <Marker key={`mp-${m.id}`} position={[m.last_seen_lat, m.last_seen_lng]} icon={icon('pin-missing')}>
                <Tooltip>
                  <div className="text-xs">
                    <strong>{m.name}</strong>
                    <div>last seen here</div>
                  </div>
                </Tooltip>
              </Marker>
            ))}

        {on.sos &&
          (sos ?? []).map((e) => (
            <Marker key={`sos-${e.id}`} position={[e.lat, e.lng]} icon={icon('pin-sos', 16)} zIndexOffset={1000}>
              <Tooltip>
                <div className="text-xs">
                  <strong>SOS · {e.plaintext_medical?.name ?? 'Unknown'}</strong>
                  <div>
                    {fmt(e.lat, 4)}° N · {fmt(e.lng, 4)}° E
                  </div>
                </div>
              </Tooltip>
            </Marker>
          ))}

        {/* Fallback for stale cached rows that still carry GeoJSON polygons. */}
        {on.flood &&
          !gfmIsWms &&
          floodPolys.map((poly, i) => (
            <Polygon
              key={`gfm-${i}`}
              positions={poly}
              pathOptions={{ color: '#d4d4d8', weight: 1, dashArray: '4 4', fillColor: '#71717a', fillOpacity: 0.22 }}
            />
          ))}
      </MapContainer>

      {/* GFM note — live WMS overlay, latest satellite observation */}
      {on.flood && gfmIsWms && (
        <div className="absolute bottom-4 left-4 z-[1000] border border-zinc-800 bg-black px-3 py-2">
          <div className="text-[9px] uppercase tracking-widest text-zinc-500">Copernicus GFM · live flood extent</div>
          <div className="tabular-nums text-[10px] text-zinc-400">
            latest Sentinel-1 observation — not a real-time stream
          </div>
        </div>
      )}
    </div>
  );
}

// GFM metric carries a GeoJSON fixture; pull polygon coordinate rings out.
function extractPolygons(gfm) {
  const fc = gfm?.geojson ?? gfm?.feature_collection ?? gfm;
  const feats = fc?.features;
  if (!Array.isArray(feats)) return [];
  const polys = [];
  for (const f of feats) {
    const geom = f?.geometry;
    if (!geom) continue;
    if (geom.type === 'Polygon') {
      polys.push(geom.coordinates[0].map(([lng, lat]) => [lat, lng]));
    } else if (geom.type === 'MultiPolygon') {
      for (const p of geom.coordinates) polys.push(p[0].map(([lng, lat]) => [lat, lng]));
    }
  }
  return polys;
}
