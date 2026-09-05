import { Panel, SourcePill, TagBadge } from './ui';

export function AiReviewCard({ review }) {
  const tag = review?.risk_tag ?? 'Unknown';
  const urgent = String(tag).toLowerCase() === 'severe';
  return (
    <Panel
      title="AI Risk Review"
      right={<SourcePill>{review?.source === 'llm' ? 'AI review' : 'Rule-based'}</SourcePill>}
    >
      <div className="px-4 pb-4">
        <div className="mb-2">
          <TagBadge label={tag} urgent={urgent} />
        </div>
        <p className="text-[12px] leading-relaxed text-zinc-300">
          {review?.summary_text ?? 'Risk summary unavailable.'}
        </p>
      </div>
    </Panel>
  );
}
