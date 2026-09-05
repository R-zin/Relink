// Monochrome primitives that carry the design language from the Superdesign
// reference: hairline zinc borders, uppercase micro-labels, tabular numerals,
// and a single reserved red used only for SOS / Red-severity elements.

export function SectionLabel({ children, className = '' }) {
  return (
    <h2 className={`text-[10px] uppercase tracking-[0.3em] text-zinc-500 ${className}`}>
      {children}
    </h2>
  );
}

export function Panel({ title, right, children, className = '', bodyClass = '' }) {
  return (
    <section className={`flex flex-col border-b border-zinc-800 ${className}`}>
      {(title || right) && (
        <header className="flex items-center justify-between px-4 pt-3 pb-2">
          <SectionLabel>{title}</SectionLabel>
          {right}
        </header>
      )}
      <div className={`min-h-0 ${bodyClass}`}>{children}</div>
    </section>
  );
}

export function SourcePill({ children }) {
  return (
    <span className="border border-zinc-800 px-1.5 py-0.5 text-[9px] uppercase tracking-widest text-zinc-500">
      {children}
    </span>
  );
}

// TagBadge — filled red ONLY when severe/urgent; otherwise a neutral outline.
export function TagBadge({ label, urgent = false }) {
  if (urgent) {
    return (
      <span className="bg-[#FF0000] px-2 py-0.5 text-[10px] font-bold uppercase tracking-widest text-white">
        {label}
      </span>
    );
  }
  return (
    <span className="border border-zinc-700 px-2 py-0.5 text-[10px] uppercase tracking-widest text-zinc-400">
      {label}
    </span>
  );
}

export function BigStat({ value, unit, label }) {
  return (
    <div>
      <div className="flex items-baseline gap-1">
        <span className="tabular-nums text-3xl font-light">{value}</span>
        {unit && <span className="text-xs text-zinc-500">{unit}</span>}
      </div>
      <div className="mt-0.5 text-[10px] uppercase tracking-widest text-zinc-500">{label}</div>
    </div>
  );
}

export function EmptyPane({ title, body }) {
  return (
    <div className="flex flex-col items-center justify-center gap-1 px-6 py-8 text-center">
      <div className="text-xs font-medium text-zinc-400">{title}</div>
      {body && <div className="text-[11px] leading-relaxed text-zinc-600">{body}</div>}
    </div>
  );
}

// Hairline progress bar for reservoir levels.
export function LevelBar({ pct, danger }) {
  const p = Math.max(0, Math.min(100, Number(pct) || 0));
  const over = danger != null && p >= danger;
  return (
    <div className="h-1 w-full bg-zinc-800">
      <div className={`h-full ${over ? 'bg-[#FF0000]' : 'bg-zinc-300'}`} style={{ width: `${p}%` }} />
    </div>
  );
}
