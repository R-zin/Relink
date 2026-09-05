import { useState } from 'react';
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
    <article className="border-b border-zinc-800 bg-white/[0.03] p-4">
      <div className="mb-1.5 flex items-start justify-between">
        <span className="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-widest text-[#FF0000]">
          <span className="h-2 w-2 bg-[#FF0000] sos-flash" />
          SOS · Priority 1
        </span>
        <span className="tabular-nums text-[10px] text-zinc-500">{timeAgo(event.created_at)}</span>
      </div>

      <h3 className="mb-1 text-sm font-medium leading-snug">
        {med.name ?? 'Unknown patient'}
      </h3>
      <div className="mb-3 flex flex-wrap gap-x-4 gap-y-0.5 text-[11px] text-zinc-400">
        {med.blood_group && <Meta k="Blood" v={med.blood_group} />}
        {med.allergies && <Meta k="Allergies" v={med.allergies} />}
        {med.emergency_contact?.phone && <Meta k="Contact" v={med.emergency_contact.phone} />}
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

// Break-glass decrypt — gated by the demo passphrase, decrypted on view and
// never persisted. Plain public fields sit alongside a clear indicator.
function DecryptModal({ event, onClose }) {
  const [pass, setPass] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [result, setResult] = useState(null);
  const med = event.plaintext_medical ?? {};

  async function submit(e) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await api.decryptMedical(event.encrypted_medical, pass);
      setResult(res.decrypted_data ?? {});
    } catch (err) {
      setError(err.status === 401 ? 'Incorrect responder passphrase.' : 'Decryption failed — corrupted or wrong key.');
    } finally {
      setBusy(false);
    }
  }

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
          {/* Plaintext — always visible */}
          <div className="mb-4 border border-zinc-800 p-3">
            <div className="mb-2 text-[9px] uppercase tracking-widest text-zinc-500">Public — broadcast openly</div>
            <Row k="Name" v={med.name} />
            <Row k="Blood group" v={med.blood_group} />
            <Row k="Allergies" v={med.allergies} />
            <Row k="Emergency contact" v={med.emergency_contact ? `${med.emergency_contact.name ?? ''} ${med.emergency_contact.phone ?? ''}`.trim() : null} />
          </div>

          {!result ? (
            <form onSubmit={submit} className="space-y-3">
              <div className="text-[11px] leading-relaxed text-zinc-400">
                Sensitive fields are AES-256-GCM encrypted. Enter the responder
                passphrase to decrypt on view. Nothing is stored.
              </div>
              <input
                type="password"
                value={pass}
                onChange={(e) => setPass(e.target.value)}
                placeholder="Responder passphrase"
                autoFocus
                className="w-full border border-zinc-700 bg-black px-3 py-2 text-xs text-white placeholder-zinc-700 focus:border-zinc-500 focus:outline-none"
              />
              {error && <div className="text-[11px] text-[#FF0000]">{error}</div>}
              <button
                type="submit"
                disabled={busy || !pass}
                className="w-full bg-white px-3 py-2 text-[11px] font-bold uppercase tracking-[0.2em] text-black transition-opacity disabled:opacity-40"
              >
                {busy ? 'Decrypting…' : 'Decrypt on view'}
              </button>
            </form>
          ) : (
            <div className="border border-[#FF0000]/40 p-3">
              <div className="mb-2 flex items-center justify-between">
                <span className="text-[9px] uppercase tracking-widest text-[#FF0000]">
                  Decrypted on view — never stored
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
