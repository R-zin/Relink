import { isUrgent, timeAgo } from '../lib/format';
import { EmptyPane, Panel, TagBadge } from './ui';

export function AlertsPanel({ alerts }) {
  const list = alerts ?? [];
  return (
    <Panel
      title="NDMA Alerts"
      right={<span className="tabular-nums text-[10px] text-zinc-500">{list.length}</span>}
      className="flex-1"
      bodyClass="flex-1 overflow-y-auto scroll-hide"
    >
      {list.length === 0 ? (
        <EmptyPane title="No active alerts" body="Official NDMA Sachet alerts for the region appear here verbatim." />
      ) : (
        list.map((a) => {
          const urgent = isUrgent(a.severity);
          return (
            <article
              key={a.id}
              className={`border-b border-zinc-800 p-4 ${urgent ? 'border-l-2 border-l-[#FF0000] bg-white/[0.02]' : ''}`}
            >
              <div className="mb-1.5 flex items-start justify-between gap-2">
                <TagBadge label={a.severity ?? 'Advisory'} urgent={urgent} />
                <span className="tabular-nums shrink-0 text-[10px] text-zinc-500">{timeAgo(a.issued_at)}</span>
              </div>
              <h3 className="mb-1 text-xs font-semibold leading-snug text-zinc-100">
                {a.headline ?? a.event ?? 'Alert'}
              </h3>
              {a.area_desc && <div className="mb-1 text-[10px] uppercase tracking-widest text-zinc-500">{a.area_desc}</div>}
              {a.description && <p className="mb-1 text-[11px] leading-relaxed text-zinc-400">{a.description}</p>}
              {a.instruction && (
                <p className="text-[11px] leading-relaxed text-zinc-300">
                  <span className="font-semibold text-zinc-200">Do this: </span>
                  {a.instruction}
                </p>
              )}
              <div className="mt-2 text-[9px] uppercase tracking-widest text-zinc-600">
                Source: NDMA Sachet{a.is_test ? ' · test' : ''} · quoted verbatim
              </div>
            </article>
          );
        })
      )}
    </Panel>
  );
}
