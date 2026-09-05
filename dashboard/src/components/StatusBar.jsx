import { timeAgo } from '../lib/format';

export function StatusBar({ sosCount, shelterCount, missingCount, hazardCount, lastSync }) {
  return (
    <footer className="z-50 flex h-7 shrink-0 items-center justify-between border-t border-zinc-800 bg-black px-5">
      <div className="flex gap-5">
        <LegendDot color={sosCount > 0 ? '#FF0000' : '#3f3f46'} label={`${sosCount} SOS`} />
        <LegendDot color="#e4e4e7" label={`${shelterCount} Shelters`} />
        <LegendDot color="#a1a1aa" label={`${hazardCount} Hazard Clusters`} />
        <LegendDot color="#71717a" label={`${missingCount} Missing`} />
      </div>
      <div className="text-[9px] uppercase tracking-widest text-zinc-600">
        RELINK Command · synced {lastSync ? timeAgo(lastSync) : '—'}
      </div>
    </footer>
  );
}

function LegendDot({ color, label }) {
  return (
    <div className="flex items-center gap-1.5">
      <span className="h-1 w-1" style={{ background: color }} />
      <span className="text-[9px] uppercase tracking-widest text-zinc-500">{label}</span>
    </div>
  );
}
