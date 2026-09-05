import {
  Bar,
  BarChart,
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { fmt } from '../lib/format';
import { LevelBar, Panel, SourcePill } from './ui';

// Shared chart chrome: recessive grid, thin monochrome marks, ink-only text.
const GRID = '#1a1a1d';
const AXIS = { stroke: '#52525b', fontSize: 9, tickLine: false, axisLine: false };
const SERIES = '#d4d4d8'; // single neutral series hue
const TOOLTIP = {
  contentStyle: { background: '#09090b', border: '1px solid #27272a', borderRadius: 0, fontSize: 11 },
  labelStyle: { color: '#a1a1aa' },
  itemStyle: { color: '#fafafa' },
  cursor: { stroke: '#3f3f46' },
};

export function RiverCard({ glofas }) {
  const forecast = (glofas?.forecast ?? []).map((f) => ({
    date: (f.date ?? '').slice(5), // MM-DD
    discharge: f.discharge_m3s,
    mean: f.mean_m3s,
  }));
  const current = glofas?.discharge_m3s;
  const trend = glofas?.trend ?? 'steady';

  return (
    <Panel
      title="River Discharge"
      right={<SourcePill>{glofas?.source_label ?? 'GloFAS'}</SourcePill>}
    >
      <div className="px-4 pb-4">
        <div className="mb-2 flex items-baseline gap-2">
          <span className="tabular-nums text-3xl font-light">{fmt(current, 1)}</span>
          <span className="text-xs text-zinc-500">m³/s</span>
          <TrendGlyph trend={trend} />
        </div>
        {forecast.length >= 2 ? (
          <ResponsiveContainer width="100%" height={110}>
            <LineChart data={forecast} margin={{ top: 4, right: 4, bottom: 0, left: -22 }}>
              <CartesianGrid stroke={GRID} vertical={false} />
              <XAxis dataKey="date" tick={AXIS.tick ? AXIS : AXIS} {...AXIS} interval="preserveStartEnd" />
              <YAxis {...AXIS} width={34} />
              <Tooltip {...TOOLTIP} />
              <Line type="monotone" dataKey="mean" stroke="#3f3f46" strokeWidth={1} dot={false} strokeDasharray="2 3" name="mean" />
              <Line type="monotone" dataKey="discharge" stroke={SERIES} strokeWidth={2} dot={{ r: 2, fill: SERIES, strokeWidth: 0 }} name="discharge" />
            </LineChart>
          </ResponsiveContainer>
        ) : (
          <div className="text-[11px] text-zinc-600">No forecast curve available.</div>
        )}
        <div className="mt-1 text-[9px] uppercase tracking-widest text-zinc-600">7-day GloFAS forecast</div>
      </div>
    </Panel>
  );
}

function TrendGlyph({ trend }) {
  const t = String(trend).toLowerCase();
  if (t === 'rising') return <span className="text-[10px] uppercase tracking-widest text-[#FF0000]">▲ rising</span>;
  if (t === 'falling') return <span className="text-[10px] uppercase tracking-widest text-zinc-400">▼ falling</span>;
  return <span className="text-[10px] uppercase tracking-widest text-zinc-500">→ steady</span>;
}

export function RainfallCard({ weather }) {
  const rain = weather?.rainfall_24h_mm;
  const gust = weather?.max_gust_kmh;
  const hourly = (weather?.hourly ?? [])
    .filter((h) => h.precipitation_mm != null)
    .slice(-24)
    .map((h) => ({ t: (h.time ?? '').slice(11, 16), mm: h.precipitation_mm }));

  return (
    <Panel title="Rainfall & Wind" right={<SourcePill>{weather?.source_label ?? 'IMD'}</SourcePill>}>
      <div className="px-4 pb-4">
        <div className="mb-2 flex gap-6">
          <Stat value={fmt(rain, 1)} unit="mm" label="rain · 24h" />
          <Stat value={fmt(gust, 0)} unit="km/h" label="max gust" />
        </div>
        {hourly.length ? (
          <ResponsiveContainer width="100%" height={80}>
            <BarChart data={hourly} margin={{ top: 4, right: 4, bottom: 0, left: -30 }}>
              <CartesianGrid stroke={GRID} vertical={false} />
              <XAxis dataKey="t" {...AXIS} interval={5} />
              <YAxis {...AXIS} width={28} />
              <Tooltip {...TOOLTIP} cursor={{ fill: '#141417' }} />
              <Bar dataKey="mm" fill={SERIES} radius={[2, 2, 0, 0]} maxBarSize={10} name="rain (mm)" />
            </BarChart>
          </ResponsiveContainer>
        ) : (
          <div className="text-[11px] text-zinc-600">No rainfall data.</div>
        )}
        <div className="mt-1 text-[9px] uppercase tracking-widest text-zinc-600">hourly · last 24h</div>
      </div>
    </Panel>
  );
}

function Stat({ value, unit, label }) {
  return (
    <div>
      <div className="flex items-baseline gap-1">
        <span className="tabular-nums text-2xl font-light">{value}</span>
        <span className="text-[11px] text-zinc-500">{unit}</span>
      </div>
      <div className="text-[9px] uppercase tracking-widest text-zinc-600">{label}</div>
    </div>
  );
}

export function DamsCard({ dams }) {
  const list = dams?.dams ?? [];
  return (
    <Panel title="Reservoir Levels" right={<SourcePill>{dams?.source_label ?? 'CWC'}</SourcePill>}>
      <div className="space-y-3 px-4 pb-4">
        {list.length === 0 && <div className="text-[11px] text-zinc-600">No reservoir data.</div>}
        {list.map((d) => {
          const pct = Number(d.storage_pct) || 0;
          const danger = Number(d.danger_level_pct) || 95;
          const over = pct >= danger;
          return (
            <div key={d.name}>
              <div className="mb-1 flex items-baseline justify-between">
                <span className="text-[11px] font-medium text-zinc-300">{d.name}</span>
                <span className={`tabular-nums text-[11px] font-semibold ${over ? 'text-[#FF0000]' : 'text-zinc-400'}`}>
                  {fmt(pct, 1)}%
                </span>
              </div>
              <LevelBar pct={pct} danger={danger} />
              {over && <div className="mt-0.5 text-[9px] font-semibold uppercase tracking-widest text-[#FF0000]">▲ above danger level</div>}
            </div>
          );
        })}
      </div>
    </Panel>
  );
}
