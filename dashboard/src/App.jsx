import { useRelinkData } from './hooks/useRelinkData';
import { Header } from './components/Header';
import { StatusBar } from './components/StatusBar';
import { SosFeed } from './components/SosFeed';
import { MissingPanel } from './components/MissingPanel';
import { MapCanvas } from './components/MapCanvas';
import { AiReviewCard } from './components/AiReviewCard';
import { RiverCard, RainfallCard, DamsCard } from './components/Telemetry';
import { AlertsPanel } from './components/AlertsPanel';

const REGION = import.meta.env.VITE_REGION ?? 'Kochi, Kerala';

export default function App() {
  const d = useRelinkData(REGION);
  const sosActive = (d.sos ?? []).filter((e) => e.status === 'active' || !e.status);
  const connected = Boolean(d.health) && !d.errors.health;
  const gfm = d.stats?.metrics?.gfm;

  return (
    <div className="flex h-screen flex-col bg-black text-white">
      <Header region={REGION} connected={connected} sosCount={sosActive.length} />

      <main className="flex min-h-0 flex-1">
        {/* LEFT — act */}
        <aside className="flex w-80 shrink-0 flex-col border-r border-zinc-800 bg-zinc-950">
          <SosFeed sos={d.sos} />
          <MissingPanel missing={d.missing} />
        </aside>

        {/* CENTER — locate */}
        <section className="relative flex min-w-0 flex-1 flex-col">
          <MapCanvas
            sos={d.sos}
            shelters={d.shelters}
            clusters={d.clusters}
            missing={d.missing}
            gfm={gfm}
          />
        </section>

        {/* RIGHT — assess */}
        <aside className="flex w-[380px] shrink-0 flex-col overflow-y-auto border-l border-zinc-800 bg-zinc-950 scroll-hide">
          <AiReviewCard review={d.aiReview} />
          <RiverCard glofas={d.stats?.metrics?.glofas} />
          <RainfallCard weather={d.stats?.metrics?.weather} />
          <DamsCard dams={d.stats?.metrics?.dams} />
          <AlertsPanel alerts={d.alerts} />
        </aside>
      </main>

      <StatusBar
        sosCount={sosActive.length}
        shelterCount={(d.shelters ?? []).length}
        hazardCount={(d.clusters?.clusters ?? []).length}
        missingCount={(d.missing ?? []).length}
        lastSync={d.lastSync}
      />
    </div>
  );
}
