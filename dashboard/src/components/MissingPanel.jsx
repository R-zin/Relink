import { timeAgo } from '../lib/format';
import { EmptyPane, Panel } from './ui';

export function MissingPanel({ missing }) {
  const list = missing ?? [];
  return (
    <Panel
      title="Missing Persons"
      right={<span className="tabular-nums text-[10px] text-zinc-500">{list.length}</span>}
      className="max-h-64"
      bodyClass="overflow-y-auto scroll-hide"
    >
      {list.length === 0 ? (
        <EmptyPane title="No missing-person reports" body="Crowdsourced last-seen reports sync here from the mesh and cloud." />
      ) : (
        list.map((m) => (
          <div key={m.id} className="flex items-start gap-3 border-b border-zinc-900 px-4 py-3">
            <div className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center bg-zinc-800 text-[11px] font-semibold text-zinc-300">
              {(m.name ?? '?').slice(0, 1).toUpperCase()}
            </div>
            <div className="min-w-0">
              <div className="truncate text-xs font-medium text-zinc-200">{m.name}</div>
              <div className="truncate text-[11px] text-zinc-500">{m.description ?? 'No description'}</div>
              <div className="tabular-nums mt-0.5 text-[9px] uppercase tracking-widest text-zinc-600">
                last seen {timeAgo(m.created_at)}
              </div>
            </div>
          </div>
        ))
      )}
    </Panel>
  );
}
