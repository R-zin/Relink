import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import { timeAgo } from '../lib/format';
import { EmptyPane, Panel, SectionLabel } from './ui';

// Live SOS feed — the highest-priority rail. Each card carries the plaintext
// medical card openly and a break-glass action to decrypt the sensitive fields.
export function SosFeed({ sos }) {
  const active = (sos ?? []).filter((e) => e.status === 'active' || !e.status);
  return (
    <Panel
      title="Live SOS Feed"
      right={
        <span className="tabular-nums text-[10px] text-zinc-500">{active.length}</span>
      }
      className="flex-1"
      bodyClass="flex-1 overflow-y-auto scroll-hide"
    >
      {active.length === 0 ? (
        <EmptyPane title="No active SOS signals" body="New distress beacons appear here the moment any device reaches the network." />
      ) : (
        active.map((e) => <SosCard key={e.id} event={e} />)
      )}
    </Panel>
  );
}

function SosCard({ event }) {
  const [open, setOpen] = useState(false);
  const med = event.plaintext_medical ?? {};
  const hasCipher = Boolean(event.encrypted_medical);

  return (
    <article className="border-b border-zinc-800/80 p-4 transition-colors hover:bg-zinc-900/40">
      <div className="mb-2 flex items-center justify-between">
        <div className="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wider text-[#FF0000]">
          <span className="h-2 w-2 bg-[#FF0000] sos-flash" />
          SOS · Priority 1
        </div>
        <div className="text-[10px] uppercase text-zinc-500">
          {timeAgo(event.created_at)}
        </div>
      </div>

      <div className="mb-2 text-sm font-bold tracking-tight text-white">
        {med.name ?? 'Unidentified person'}
      </div>

      <div className="mb-3 grid grid-cols-2 gap-x-2 gap-y-1 text-xs">
        <Meta k="Blood" v={med.blood_group ?? '—'} />
        <Meta k="Allergies" v={med.allergies ?? 'None'} />
        {med.emergency_contact && (
          <div className="col-span-2 text-[11px] text-zinc-400">
            Contact: {med.emergency_contact.name ?? ''} ({med.emergency_contact.phone ?? '—'})
          </div>
        )}
      </div>
      <div className="tabular-nums mb-3 text-[10px] text-zinc-600">
        {Number(event.lat).toFixed(4)}° N · {Number(event.lng).toFixed(4)}° E
      </div>

      {hasCipher ? (
        <button
          onClick={() => setOpen(true)}
          className="w-full border border-[#FF0000] px-2 py-1.5 text-[10px] font-bold uppercase tracking-[0.2em] text-[#FF0000] transition-colors hover:bg-[#FF0000] hover:text-white"
        >
          Decrypt Medical Card
        </button>
      ) : (
        <div className="text-[10px] uppercase tracking-widest text-zinc-600">
          No encrypted medical payload
        </div>
      )}

      {open && <DecryptModal event={event} onClose={() => setOpen(false)} />}
    </article>
  );
}

function Meta({ k, v }) {
  return (
    <span>
      <span className="uppercase tracking-wider text-zinc-600">{k}: </span>
      <span className="text-zinc-300">{v}</span>
    </span>
  );
}

// Break-glass decrypt — decrypted on view and never persisted.
function DecryptModal({ event, onClose }) {
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState(null);
  const [result, setResult] = useState(null);
  const med = event.plaintext_medical ?? {};

  useEffect(() => {
    let active = true;
    async function doDecrypt() {
      setBusy(true);
      setError(null);
      try {
        const res = await api.decryptMedical(event.encrypted_medical);
        if (active) {
          setResult(res.decrypted_data ?? {});
        }
      } catch (err) {
        if (active) {
          setError('Decryption failed — corrupted or wrong key.');
        }
      } finally {
        if (active) setBusy(false);
      }
    }
    doDecrypt();
    return () => {
      active = false;
    };
  }, [event.encrypted_medical]);

  return (
    <div className="fixed inset-0 z-[1000] flex items-center justify-center bg-black/80 p-4" onClick={onClose}>
      <div
        className="w-full max-w-md border border-zinc-700 bg-zinc-950"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-zinc-800 px-5 py-3">
          <SectionLabel>Break-Glass Medical Decrypt</SectionLabel>
          <button onClick={onClose} className="text-zinc-500 hover:text-white">✕</button>
        </div>

        <div className="max-h-[70vh] overflow-y-auto p-5">
          <div className="mb-4 border border-zinc-800 p-3">
            <div className="mb-2 text-[9px] uppercase tracking-widest text-zinc-500">Public — broadcast openly</div>
            <Row k="Name" v={med.name} />
            <Row k="Blood group" v={med.blood_group} />
            <Row k="Allergies" v={med.allergies} />
            <Row k="Emergency contact" v={med.emergency_contact ? `${med.emergency_contact.name ?? ''} ${med.emergency_contact.phone ?? ''}`.trim() : null} />
          </div>

          {busy && (
            <div className="flex items-center justify-center py-6 text-xs text-zinc-400">
              <span className="mr-2 inline-block h-3 w-3 animate-spin rounded-full border-2 border-zinc-400 border-t-transparent" />
              Decrypting confidential medical records…
            </div>
          )}

          {error && (
            <div className="border border-[#FF0000]/40 p-3 text-center">
              <div className="text-[11px] text-[#FF0000]">{error}</div>
              <button
                onClick={onClose}
                className="mt-3 w-full border border-zinc-700 px-3 py-1.5 text-[11px] uppercase tracking-[0.2em] text-zinc-300 hover:bg-zinc-900"
              >
                Close
              </button>
            </div>
          )}

          {!busy && !error && result && (
            <div className="border border-[#FF0000]/40 p-3">
              <div className="mb-2 flex items-center justify-between">
                <span className="text-[9px] uppercase tracking-widest text-[#FF0000]">
                  Decrypted on view — Confidential
                </span>
              </div>
              {Object.entries(result).map(([k, v]) => (
                <Row key={k} k={k.replaceAll('_', ' ')} v={typeof v === 'object' ? JSON.stringify(v) : String(v)} />
              ))}
              <button
                onClick={onClose}
                className="mt-4 w-full border border-zinc-700 px-3 py-2 text-[11px] uppercase tracking-[0.2em] text-zinc-300 hover:bg-zinc-900"
              >
                Close & discard
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function Row({ k, v }) {
  if (v === null || v === undefined || v === '') return null;
  return (
    <div className="flex justify-between gap-4 py-0.5 text-[11px]">
      <span className="shrink-0 capitalize text-zinc-500">{k}</span>
      <span className="text-right text-zinc-200">{v}</span>
    </div>
  );
}
