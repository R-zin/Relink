import { useEffect, useState } from 'react';
import { utcClock } from '../lib/format';

export function Header({ region, connected, sosCount }) {
  const [clock, setClock] = useState(utcClock());
  useEffect(() => {
    const t = setInterval(() => setClock(utcClock()), 1000);
    return () => clearInterval(t);
  }, []);

  return (
    <header className="flex h-14 shrink-0 items-center justify-between border-b border-zinc-800 px-5">
      <div className="flex items-center gap-6">
        <div className="flex items-center gap-2">
          <div className="flex h-5 w-5 items-center justify-center bg-white">
            <div className="h-1.5 w-1.5 bg-black" />
          </div>
          <span className="text-lg font-bold tracking-tighter">RELINK</span>
          <span className="mt-px text-[9px] uppercase tracking-[0.25em] text-zinc-500">
            Command Center
          </span>
        </div>
      </div>

      <div className="hidden text-[10px] uppercase tracking-[0.3em] text-zinc-400 md:block">
        {region}
      </div>

      <div className="flex items-center gap-4">
        {sosCount > 0 && (
          <div className="flex items-center gap-1.5 border border-[#FF0000] px-2 py-1">
            <span className="h-1.5 w-1.5 bg-[#FF0000] sos-flash" />
            <span className="text-[10px] font-bold uppercase tracking-widest text-[#FF0000]">
              {sosCount} SOS
            </span>
          </div>
        )}
        <div className="flex items-center gap-2 border border-zinc-800 px-2.5 py-1">
          <span className={`h-1.5 w-1.5 ${connected ? 'bg-white' : 'bg-zinc-600'}`} />
          <span className="text-[10px] uppercase tracking-widest text-zinc-400">
            {connected ? 'Backend: Live' : 'Backend: Offline'}
          </span>
        </div>
        <div className="tabular-nums text-[10px] uppercase tracking-widest text-zinc-500">
          {clock}
        </div>
      </div>
    </header>
  );
}
