// Small presentation helpers.

export function timeAgo(iso) {
  if (!iso) return '—';
  const then = new Date(iso).getTime();
  if (Number.isNaN(then)) return '—';
  const s = Math.max(0, Math.floor((Date.now() - then) / 1000));
  if (s < 60) return `${s}s ago`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.floor(h / 24);
  return `${d}d ago`;
}

export function utcClock(d = new Date()) {
  return d.toISOString().slice(11, 19) + ' UTC';
}

export function fmt(n, digits = 1) {
  if (n === null || n === undefined || Number.isNaN(Number(n))) return '—';
  return Number(n).toFixed(digits);
}

// CAP severity → is this an urgent (accent / red) alert?
export function isUrgent(severity) {
  if (!severity) return false;
  const s = String(severity).toLowerCase();
  return s === 'red' || s === 'extreme' || s === 'severe' || s === 'orange';
}
