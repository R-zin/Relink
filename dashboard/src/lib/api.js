// RELINK backend client. Base URL is the Phase-1..4 FastAPI service.
// All shapes mirror backend/app/schemas.py exactly — no re-derivation.

const BASE = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:8000';

async function req(path, { method = 'GET', body } = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    const err = new Error(`${method} ${path} → ${res.status}`);
    err.status = res.status;
    err.detail = text;
    throw err;
  }
  return res.status === 204 ? null : res.json();
}

export const api = {
  base: BASE,
  health: () => req('/health'),
  listSos: (status) => req(`/sos${status ? `?status=${status}` : ''}`),
  listShelters: () => req('/shelters'),
  getClusters: () => req('/reports/clusters'),
  searchMissing: (q = '') => req(`/missing-persons/search${q ? `?q=${encodeURIComponent(q)}` : ''}`),
  listAlerts: (state = 'kerala', includeExpired = false) =>
    req(`/alerts?state=${state}${includeExpired ? '&include_expired=true' : ''}`),
  getStats: (region) => req(`/stats${region ? `?region=${encodeURIComponent(region)}` : ''}`),
  getAiReview: (region) => req(`/stats/ai-review${region ? `?region=${encodeURIComponent(region)}` : ''}`),
  decryptMedical: (ciphertext, demoPass) =>
    req('/medical/decrypt', { method: 'POST', body: { ciphertext, demo_pass: demoPass } }),
};
