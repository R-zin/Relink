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
    // Fast operational endpoints: health, SOS, shelters, clusters, missing, alerts (< 100ms)
    const fastSettled = await Promise.allSettled([
      api.health(),
      api.listSos(),
      api.listShelters(),
      api.getClusters(),
      api.searchMissing(),
      api.listAlerts('all'),
    ]);
    const fastKeys = ['health', 'sos', 'shelters', 'clusters', 'missing', 'alerts'];
    const fastNext = { lastSync: new Date() };
    const fastErrors = {};
    fastSettled.forEach((r, i) => {
      const key = fastKeys[i];
      if (r.status === 'fulfilled') {
        fastNext[key] = r.value;
      } else {
        fastNext[key] = INITIAL[key];
        fastErrors[key] = r.reason?.message ?? 'error';
      }
    });
    // Immediately update so Backend: Live and SOS beacons appear instantaneously
    setData((prev) => ({
      ...prev,
      ...fastNext,
      errors: { ...prev.errors, ...fastErrors },
    }));

    // Heavy external telemetry (stats, aiReview) progressive load in background
    Promise.allSettled([
      api.getStats(region),
      api.getAiReview(region),
    ]).then((slowSettled) => {
      const slowKeys = ['stats', 'aiReview'];
      const slowNext = {};
      const slowErrors = {};
      slowSettled.forEach((r, i) => {
        const key = slowKeys[i];
        if (r.status === 'fulfilled') {
          slowNext[key] = r.value;
        } else {
          slowNext[key] = INITIAL[key];
          slowErrors[key] = r.reason?.message ?? 'error';
        }
      });
      setData((prev) => ({
        ...prev,
        ...slowNext,
        errors: { ...prev.errors, ...slowErrors },
      }));
    });
  }, [region]);

  useEffect(() => {
    pull();
    timer.current = setInterval(pull, POLL_MS);
    return () => clearInterval(timer.current);
  }, [pull]);

  return { ...data, refresh: pull };
}
