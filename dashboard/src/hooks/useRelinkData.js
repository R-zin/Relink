import { useCallback, useEffect, useRef, useState } from 'react';
import { api } from '../lib/api';

// Polls every RELINK endpoint the dashboard needs. Each resource is tracked
// independently so one failing endpoint never blanks the whole console.
const POLL_MS = 12000;

const INITIAL = {
  health: null,
  sos: [],
  shelters: [],
  clusters: { clusters: [], noise: [] },
  missing: [],
  alerts: [],
  stats: null,
  aiReview: null,
  errors: {},
  lastSync: null,
};

export function useRelinkData(region) {
  const [data, setData] = useState(INITIAL);
  const timer = useRef(null);

  const pull = useCallback(async () => {
    const settled = await Promise.allSettled([
      api.health(),
      api.listSos(),
      api.listShelters(),
      api.getClusters(),
      api.searchMissing(),
      api.listAlerts('kerala'),
      api.getStats(region),
      api.getAiReview(region),
    ]);
    const keys = ['health', 'sos', 'shelters', 'clusters', 'missing', 'alerts', 'stats', 'aiReview'];
    const next = { errors: {}, lastSync: new Date() };
    settled.forEach((r, i) => {
      const key = keys[i];
      if (r.status === 'fulfilled') {
        next[key] = r.value;
      } else {
        next[key] = INITIAL[key];
        next.errors[key] = r.reason?.message ?? 'error';
      }
    });
    setData((prev) => ({ ...prev, ...next }));
  }, [region]);

  useEffect(() => {
    pull();
    timer.current = setInterval(pull, POLL_MS);
    return () => clearInterval(timer.current);
  }, [pull]);

  return { ...data, refresh: pull };
}
