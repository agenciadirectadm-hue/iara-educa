import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router';
import { AnimatePresence, motion } from 'motion/react';
import clsx from 'clsx';
import {
  ArrowRight, Building2, ChevronDown, ChevronUp, Flame, Layers, List, LocateFixed, Map as MapIcon, MapPin, Navigation, Phone, School, Search, Sparkles, X,
} from 'lucide-react';
import { useGeoLayers, useUnitsMap } from '@/lib/data';
import { useDebounced, useIsDesktop, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtInt, fmtKm, fmtPct } from '@/lib/format';
import type { UnitMapItem } from '@/lib/types';
import MapView, { type HeatMode, type RegionMetric } from '@/components/map/MapView';
import { Badge, Button, ButtonLink, Chip, OccupancyBar, SourceChip, Spinner } from '@/components/ui';
import { Sheet } from '@/components/overlays';

type Filter = 'todas' | 'cmei' | 'escola' | 'vaga' | 'creche';
type Snap = 'peek' | 'half' | 'full';

function distance(a: { lat: number; lng: number }, b: { lat: number; lng: number }) {
  const R = 6371000;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const x = Math.sin(dLat / 2) ** 2 + Math.cos((a.lat * Math.PI) / 180) * Math.cos((b.lat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(x));
}

export default function MapPage() {
  const [sp, setSp] = useSearchParams();
  const navigate = useNavigate();
  const desktop = useIsDesktop();
  const { me } = useSession();
  const units = useUnitsMap();
  const geo = useGeoLayers();
  const citizen = useRpc<any>('citizen_home', {}, { enabled: me?.scope === 'GUARDIAN' });

  const selectedId = sp.get('unidade') ? Number(sp.get('unidade')) : null;
  const view = sp.get('visao') === 'lista' ? 'lista' : 'mapa';
  const layer = sp.get('camada') ?? 'unidades';
  const [filter, setFilter] = useState<Filter>((sp.get('filtro') as Filter) ?? 'todas');
  const [snap, setSnap] = useState<Snap>('peek');
  const [layersOpen, setLayersOpen] = useState(false);
  const [q, setQ] = useState('');
  const dq = useDebounced(q.trim(), 280);
  const geoSearch = useRpc<any>('geo_search', { q: dq }, { enabled: dq.length >= 2 });
  const [point, setPoint] = useState<{ lat: number; lng: number; label: string } | null>(null);
  const [showAreas, setShowAreas] = useState(false);

  // cidadão: "unidades perto de casa"
  useEffect(() => {
    const a = citizen.data?.guardian?.address;
    if (sp.get('perto') && a?.lat && !point) setPoint({ lat: a.lat, lng: a.lng, label: 'Minha casa (cadastro)' });
  }, [citizen.data, sp, point]);

  const all = units.data?.units ?? [];
  const list = useMemo(() => {
    let l = all.filter((u) =>
      filter === 'cmei' ? u.type === 'CMEI' : filter === 'escola' ? u.type === 'ESCOLA' : filter === 'vaga' ? u.offerable > 0 : filter === 'creche' ? u.offerable_creche > 0 : true);
    if (point) l = [...l].sort((a, b) => distance(point, a) - distance(point, b));
    return l;
  }, [all, filter, point]);
  const selected = all.find((u) => u.id === selectedId) ?? null;

  const setParam = (k: string, v: string | null) => {
    const n = new URLSearchParams(sp);
    if (v == null) n.delete(k);
    else n.set(k, v);
    setSp(n, { replace: true });
  };
  const select = (u: UnitMapItem | null) => {
    setParam('unidade', u ? String(u.id) : null);
    if (u) setSnap('half');
  };

  const heat: HeatMode = layer === 'fila' ? 'queue' : layer === 'matriculas' ? 'enrollments' : layer === 'vagas' ? 'offerable' : null;
  const regionMetric: RegionMetric = layer === 'deficit' ? 'balance_creche' : null;
  const sheetH = { peek: 132, half: desktop ? 0 : 0.5, full: 0.86 }[snap];

  return (
    <div className="relative h-[calc(100dvh-64px-66px-env(safe-area-inset-bottom)-env(safe-area-inset-top))] overflow-hidden lg:h-[calc(100dvh-64px)]">
      {view === 'mapa' ? (
        <MapView
          className="absolute inset-0"
          units={list}
          geo={geo.data}
          selectedId={selectedId}
          onSelectUnit={select}
          onSelectRegion={(id) => navigate(`/territorios/${id}`)}
          heat={heat}
          regionMetric={regionMetric}
          colorMode={layer === 'vagas' || filter === 'vaga' || filter === 'creche' ? 'vacancy' : 'type'}
          showAreas={showAreas}
          home={point ? { lat: point.lat, lng: point.lng, radius_m: 2000 } : null}
          focus={selected ? { lat: selected.lat, lng: selected.lng, zoom: 15 } : point ? { lat: point.lat, lng: point.lng, zoom: 13.6 } : null}
          fitKey={`${filter}`}
          padding={{ top: 130, bottom: desktop ? 40 : 170, left: desktop ? 420 : 30, right: 70 }}
        />
      ) : (
        <ListView list={list} point={point} onPick={(u) => navigate(`/unidades/${u.id}`)} />
      )}

      {/* busca e filtros flutuantes */}
      <div className="pointer-events-none absolute inset-x-0 top-0 z-20 p-3 lg:left-[420px]">
        <div className="pointer-events-auto flex gap-2">
          <div className="relative flex-1">
            <div className="glass flex h-12 items-center gap-2 rounded-2xl px-4 shadow-soft ring-1 ring-white/70">
              <Search className="size-5 text-subtle" />
              <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Bairro ou unidade…" className="h-full min-w-0 flex-1 bg-transparent text-[15px] outline-none" aria-label="Buscar bairro ou unidade" />
              {q && <button onClick={() => setQ('')} aria-label="Limpar"><X className="size-5 text-subtle" /></button>}
            </div>
            <AnimatePresence>
              {dq.length >= 2 && (
                <motion.div initial={{ opacity: 0, y: -6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} className="absolute inset-x-0 top-14 max-h-72 overflow-y-auto rounded-2xl bg-white shadow-lift ring-1 ring-line">
                  {geoSearch.isLoading ? <div className="flex justify-center p-4"><Spinner /></div> : (geoSearch.data?.items ?? []).length === 0 ? (
                    <p className="p-4 text-sm text-muted">Nada encontrado.</p>
                  ) : (geoSearch.data.items as any[]).map((it, i) => (
                    <button
                      key={i}
                      className="flex w-full items-center gap-3 border-b border-line px-4 py-3 text-left last:border-0 hover:bg-purple-50"
                      onClick={() => {
                        setQ('');
                        if (it.kind === 'UNIDADE') {
                          const u = all.find((x) => x.id === it.unit_id);
                          if (u) select(u);
                        } else {
                          setPoint({ lat: it.lat, lng: it.lng, label: it.label });
                          setParam('unidade', null);
                          setSnap('half');
                        }
                      }}
                    >
                      {it.kind === 'UNIDADE' ? <School className="size-5 text-purple-700" /> : <MapPin className="size-5 text-blue-700" />}
                      <div className="min-w-0">
                        <div className="truncate font-semibold">{it.label}</div>
                        <div className="truncate text-[12.5px] text-muted">{it.sub}</div>
                      </div>
                    </button>
                  ))}
                </motion.div>
              )}
            </AnimatePresence>
          </div>
          <button onClick={() => setLayersOpen(true)} className="glass inline-flex size-12 items-center justify-center rounded-2xl shadow-soft ring-1 ring-white/70" aria-label="Camadas do mapa">
            <Layers className="size-5" />
          </button>
          <button onClick={() => setParam('visao', view === 'mapa' ? 'lista' : null)} className="glass inline-flex h-12 items-center gap-1.5 rounded-2xl px-3 text-sm font-semibold shadow-soft ring-1 ring-white/70" aria-label={view === 'mapa' ? 'Ver em lista' : 'Ver no mapa'}>
            {view === 'mapa' ? <List className="size-5" /> : <MapIcon className="size-5" />}
            <span className="hidden sm:inline">{view === 'mapa' ? 'Lista' : 'Mapa'}</span>
          </button>
        </div>
        <div className="pointer-events-auto no-scrollbar mt-2 flex gap-2 overflow-x-auto pb-1">
          {([['todas', 'Todas'], ['cmei', 'CMEIs'], ['escola', 'Escolas'], ['vaga', 'Com vaga'], ['creche', 'Creche com vaga']] as [Filter, string][]).map(([v, l]) => (
            <Chip key={v} active={filter === v} onClick={() => { setFilter(v); setParam('filtro', v === 'todas' ? null : v); }}>{l}</Chip>
          ))}
        </div>
      </div>

      {/* painel: inferior no celular, lateral no desktop */}
      {view === 'mapa' && (
        <motion.div
          className={clsx('absolute z-30 flex flex-col bg-white shadow-lift', desktop ? 'bottom-3 left-3 top-3 w-[400px] rounded-4xl' : 'inset-x-0 bottom-0 rounded-t-4xl')}
          animate={desktop ? {} : { height: typeof sheetH === 'number' && sheetH > 1 ? sheetH : `${(sheetH as number) * 100}%` }}
          transition={{ type: 'spring', stiffness: 360, damping: 38 }}
          drag={desktop ? false : 'y'}
          dragConstraints={{ top: 0, bottom: 0 }}
          dragElastic={0.18}
          onDragEnd={(_, info) => {
            if (info.offset.y < -60) setSnap(snap === 'peek' ? 'half' : 'full');
            else if (info.offset.y > 60) setSnap(snap === 'full' ? 'half' : 'peek');
          }}
        >
          {!desktop && (
            <div className="flex items-center justify-between px-4 pt-2">
              <span className="w-10" />
              <span className="h-1.5 w-12 rounded-full bg-slate-300" aria-hidden />
              <button onClick={() => setSnap(snap === 'full' ? 'peek' : snap === 'peek' ? 'half' : 'full')} className="inline-flex size-10 items-center justify-center rounded-xl bg-slate-100" aria-label={snap === 'full' ? 'Recolher painel' : 'Expandir painel'}>
                {snap === 'full' ? <ChevronDown className="size-5" /> : <ChevronUp className="size-5" />}
              </button>
            </div>
          )}
          <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 pb-4 pt-1">
            {selected ? (
              <UnitSummary u={selected} point={point} onClose={() => select(null)} />
            ) : (
              <Overview list={list} point={point} layer={layer} onClearPoint={() => setPoint(null)} onPick={select} total={all.length} />
            )}
          </div>
        </motion.div>
      )}

      <Sheet open={layersOpen} onClose={() => setLayersOpen(false)} title="Camadas do mapa" subtitle="Ative uma camada por vez — a legenda explica as cores">
        <div className="space-y-2">
          {[
            { v: 'unidades', icon: School, l: 'Unidades por tipo', d: 'Roxo: CMEI · Azul: escola · Cinza: situação a validar', src: 'publico' as const },
            { v: 'deficit', icon: Flame, l: 'Déficit de creche por região', d: 'Vermelho: déficit severo → azul: capacidade ociosa. Toque numa região.', src: 'demo' as const },
            { v: 'fila', icon: Building2, l: 'Mapa de calor: fila', d: 'Onde se concentra a espera', src: 'demo' as const },
            { v: 'matriculas', icon: School, l: 'Mapa de calor: matrículas', d: 'Agregado público por unidade', src: 'oficial' as const },
            { v: 'vagas', icon: Sparkles, l: 'Vagas ofertáveis', d: 'Verde: com vaga · vermelho: só fila', src: 'demo' as const },
          ].map((o) => (
            <button key={o.v} onClick={() => { setParam('camada', o.v === 'unidades' ? null : o.v); setLayersOpen(false); }} className={clsx('flex w-full items-center gap-3 rounded-2xl p-3 text-left ring-1 transition', layer === o.v ? 'bg-purple-50 ring-2 ring-purple-500' : 'bg-white ring-line hover:bg-slate-50')}>
              <span className="inline-flex size-10 items-center justify-center rounded-xl bg-slate-100"><o.icon className="size-5 text-purple-700" /></span>
              <div className="min-w-0 flex-1">
                <div className="font-semibold">{o.l}</div>
                <div className="text-[12.5px] text-muted">{o.d}</div>
              </div>
              <SourceChip kind={o.src} />
            </button>
          ))}
          <label className="flex items-center gap-3 rounded-2xl bg-white p-3 ring-1 ring-line">
            <input type="checkbox" checked={showAreas} onChange={(e) => setShowAreas(e.target.checked)} className="size-5 accent-purple-700" />
            <div className="flex-1">
              <div className="font-semibold">Áreas de influência (proximidade)</div>
              <div className="text-[12.5px] text-muted">Divisão do território pela unidade mais próxima — cálculo de demonstração, não é o zoneamento oficial.</div>
            </div>
          </label>
        </div>
      </Sheet>
    </div>
  );
}

function Overview({ list, point, layer, onClearPoint, onPick, total }: { list: UnitMapItem[]; point: any; layer: string; onClearPoint: () => void; onPick: (u: UnitMapItem) => void; total: number }) {
  const vagas = list.reduce((a, u) => a + u.offerable, 0);
  const fila = list.reduce((a, u) => a + u.queue, 0);
  return (
    <div>
      <div className="flex items-baseline justify-between gap-2">
        <h2 className="font-display text-lg font-extrabold">{point ? `Perto de ${point.label}` : 'Rede municipal de Maringá'}</h2>
        {point && <button onClick={onClearPoint} className="text-[13px] font-semibold text-purple-700">Limpar</button>}
      </div>
      <div className="mt-1 flex flex-wrap gap-x-3 text-[13px] text-muted">
        <span><b className="text-ink">{fmtInt(list.length)}</b> de {total} unidades</span>
        <span><b className="text-green-700">{fmtInt(vagas)}</b> vagas ofertáveis</span>
        <span><b className="text-red-700">{fmtInt(fila)}</b> na fila</span>
        <SourceChip kind="demo" detail="Unidades e endereços são públicos; vagas e fila pertencem à camada de demonstração." />
      </div>
      {point && <p className="mt-2 rounded-2xl bg-purple-50 p-2.5 text-[12.5px] text-purple-900">Círculo = raio de 2 km (território prioritário da regra TERRITORIO_2KM). Ordenado pela distância em linha reta.</p>}
      <div className="mt-3 divide-y divide-line">
        {list.slice(0, point ? 12 : 25).map((u) => (
          <button key={u.id} onClick={() => onPick(u)} className="flex w-full items-center gap-3 py-2.5 text-left">
            <span className={clsx('inline-flex size-9 shrink-0 items-center justify-center rounded-xl text-white', u.status !== 'ATIVA' ? 'bg-slate-400' : u.type === 'CMEI' ? 'bg-purple-500' : 'bg-blue-500')}>
              <School className="size-4" />
            </span>
            <div className="min-w-0 flex-1">
              <div className="truncate text-[14.5px] font-semibold">{u.name}</div>
              <div className="truncate text-[12px] text-muted">{u.neighborhood}{point ? ` · ${fmtKm(distance(point, u))}` : ''}</div>
            </div>
            <span className={clsx('text-[12.5px] font-bold tabular', u.offerable > 0 ? 'text-green-700' : 'text-muted')}>{u.offerable > 0 ? `${u.offerable} vagas` : layer === 'fila' ? `${u.queue} fila` : '—'}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

function UnitSummary({ u, point, onClose }: { u: UnitMapItem; point: any; onClose: () => void }) {
  return (
    <div>
      <div className="flex items-start gap-3">
        <span className={clsx('mt-0.5 inline-flex size-11 shrink-0 items-center justify-center rounded-2xl text-white', u.type === 'CMEI' ? 'bg-purple-500' : 'bg-blue-500')}>
          <School className="size-5" />
        </span>
        <div className="min-w-0 flex-1">
          <div className="font-display text-[19px] font-extrabold leading-tight">{u.name}</div>
          <div className="text-[13px] text-muted">{u.address} · {u.neighborhood}</div>
          <div className="mt-1.5 flex flex-wrap gap-1.5">
            <Badge tone={u.type === 'CMEI' ? 'purple' : 'blue'}>{u.type_label}</Badge>
            {u.status !== 'ATIVA' && <Badge tone="gray">Situação a validar</Badge>}
            {u.geo_precision !== 'VALIDADO' && <Badge tone="amber">Coordenada {u.geo_precision.toLowerCase()}</Badge>}
            {point && <Badge tone="gray" icon={Navigation}>{fmtKm(distance(point, u))}</Badge>}
          </div>
        </div>
        <button onClick={onClose} className="inline-flex size-10 shrink-0 items-center justify-center rounded-xl bg-slate-100" aria-label="Fechar unidade"><X className="size-5" /></button>
      </div>
      <div className="mt-3 grid grid-cols-2 gap-2">
        <div className="rounded-2xl bg-slate-50 p-3 ring-1 ring-line">
          <div className="flex items-center justify-between"><span className="text-[11.5px] font-bold uppercase text-subtle">Matrículas</span><SourceChip kind="oficial" /></div>
          <div className="font-display text-2xl font-black tabular">{fmtInt(u.public_enrollments)}</div>
          <div className="text-[12px] text-muted">{fmtInt(u.public_classes)} turmas · INEP {u.inep ?? 'pendente'}</div>
        </div>
        <div className="rounded-2xl bg-slate-50 p-3 ring-1 ring-line">
          <div className="flex items-center justify-between"><span className="text-[11.5px] font-bold uppercase text-subtle">Vagas</span><SourceChip kind="demo" /></div>
          <div className={clsx('font-display text-2xl font-black tabular', u.offerable > 0 ? 'text-green-700' : 'text-ink')}>{fmtInt(u.offerable)}</div>
          <div className="text-[12px] text-muted">{fmtInt(u.queue)} na fila · ocupação {fmtPct(u.occupancy)}</div>
        </div>
      </div>
      {u.capacity > 0 && <div className="mt-3"><OccupancyBar capacity={u.capacity} enrolled={u.enrolled} reserved={u.reserved} blocked={u.blocked} offerable={u.offerable} showLegend /></div>}
      <p className="mt-3 text-[13px] text-muted">Etapas: {u.stages ?? 'pendente SEDUC'}</p>
      <div className="mt-4 flex flex-col gap-2 sm:flex-row">
        <ButtonLink to={`/unidades/${u.id}`} variant="primary" size="lg" className="flex-1">Ver detalhes da unidade <ArrowRight className="size-4" /></ButtonLink>
        <a href={`https://www.openstreetmap.org/directions?to=${u.lat}%2C${u.lng}`} target="_blank" rel="noreferrer" className="inline-flex h-14 items-center justify-center gap-2 rounded-2xl bg-white px-4 font-semibold ring-1 ring-line hover:bg-slate-50">
          <LocateFixed className="size-5" /> Como chegar
        </a>
      </div>
      <p className="mt-2 flex items-center gap-1.5 text-[12px] text-muted"><Phone className="size-3.5" /> Telefone: pendente SEDUC (não localizado em fonte pública).</p>
    </div>
  );
}

function ListView({ list, point, onPick }: { list: UnitMapItem[]; point: any; onPick: (u: UnitMapItem) => void }) {
  return (
    <div className="absolute inset-0 overflow-y-auto bg-canvas px-4 pb-6 pt-[124px]">
      <div className="mx-auto max-w-3xl overflow-hidden rounded-3xl bg-white shadow-soft ring-1 ring-line">
        {list.map((u) => (
          <button key={u.id} onClick={() => onPick(u)} className="flex w-full items-center gap-3 border-b border-line px-4 py-3 text-left last:border-0 hover:bg-purple-50">
            <span className={clsx('inline-flex size-10 shrink-0 items-center justify-center rounded-xl text-white', u.type === 'CMEI' ? 'bg-purple-500' : 'bg-blue-500')}><School className="size-5" /></span>
            <div className="min-w-0 flex-1">
              <div className="truncate font-semibold">{u.name}</div>
              <div className="truncate text-[12.5px] text-muted">{u.neighborhood}{point ? ` · ${fmtKm(distance(point, u))}` : ''} · {fmtInt(u.public_enrollments)} matrículas</div>
            </div>
            <div className="text-right text-[12.5px]">
              <div className={clsx('font-bold', u.offerable > 0 ? 'text-green-700' : 'text-muted')}>{u.offerable} vagas</div>
              <div className="text-muted">{u.queue} fila</div>
            </div>
          </button>
        ))}
      </div>
      <p className="mt-3 text-center text-[12px] text-muted">Alternativa acessível ao mapa · {list.length} unidades</p>
      <div className="mt-2 flex justify-center"><Button variant="ghost" onClick={() => window.scrollTo({ top: 0 })}>Topo</Button></div>
      <Link to="/unidades" className="mt-1 block text-center text-sm font-semibold text-purple-700">Abrir lista completa com filtros</Link>
    </div>
  );
}
