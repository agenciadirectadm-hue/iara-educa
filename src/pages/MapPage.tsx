import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router';
import { AnimatePresence, motion } from 'motion/react';
import clsx from 'clsx';
import {
  ArrowRight, ChevronDown, ChevronUp, Layers, List, LocateFixed, Map as MapIcon, MapPin, MapPinned, Navigation, Phone, School, Search, X,
} from 'lucide-react';
import { useGeoLayers, useGeoSetores, useUnitsMap } from '@/lib/data';
import { useDebounced, useIsDesktop, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtInt, fmtKm, fmtPct } from '@/lib/format';
import type { UnitMapItem } from '@/lib/types';
import MapView, { type Calor, type Coropleta } from '@/components/map/MapView';
import { Badge, Button, ButtonLink, Chip, OccupancyBar, Segmented, SourceChip, Spinner } from '@/components/ui';
import { Sheet } from '@/components/overlays';
import type { DistanciaUnidade, MedidaDistancia } from '@/lib/api';
import { LinkMetodologia, MEDIDA, SeletorMedida, TresDistancias, metros, modoTracado, trajetosDe, useDistancias } from '@/components/distancias';
import { CAMADA_ANTIGA, RECORTE_ROTULO, acharQuesito, escalaDosValores, temasVisiveis, type Recorte } from '@/components/mapas/catalogo';
import { PainelQuesito, type DadosRecorte } from '@/components/mapas/PainelQuesito';

/** Quantas unidades perto do ponto pesquisado ganham número, linha/rota no mapa e as três medidas. */
const PERTO = 8;

type Filter = 'todas' | 'cmei' | 'escola' | 'vaga' | 'creche';
type Snap = 'peek' | 'half' | 'full';
type Caixa = [[number, number], [number, number]];

function distance(a: { lat: number; lng: number }, b: { lat: number; lng: number }) {
  const R = 6371000;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const x = Math.sin(dLat / 2) ** 2 + Math.cos((a.lat * Math.PI) / 180) * Math.cos((b.lat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(x));
}

/** Caixa ([oeste, sul], [leste, norte]) de um polígono ou multipolígono. */
function caixaDe(g?: GeoJSON.Geometry | null): Caixa | null {
  if (!g || (g.type !== 'Polygon' && g.type !== 'MultiPolygon')) return null;
  const aneis = g.type === 'Polygon' ? g.coordinates : g.coordinates.flat();
  let [o, s, l, n] = [Infinity, Infinity, -Infinity, -Infinity];
  for (const anel of aneis) for (const [x, y] of anel) { o = Math.min(o, x); s = Math.min(s, y); l = Math.max(l, x); n = Math.max(n, y); }
  return Number.isFinite(o) ? [[o, s], [l, n]] : null;
}

/** Mapa unificado (Mapa + Mapas de calor): tema e quesito no topo, recorte em pontos, áreas de ponderação ou setores
 * censitários; tocar numa área desce para os setores dela. Endereço: ?q=quesito&recorte=area|setor|pontos&area=id. */
export default function MapPage() {
  const [sp, setSp] = useSearchParams();
  const navigate = useNavigate();
  const desktop = useIsDesktop();
  const { me, can } = useSession();
  const units = useUnitsMap();
  const geo = useGeoLayers();
  const citizen = useRpc<any>('citizen_home', {}, { enabled: me?.scope === 'GUARDIAN' });

  // tema, quesito e recorte (aceita os endereços antigos ?camada= do Mapa e dos Mapas de calor)
  const temas = useMemo(() => temasVisiveis(can), [can]);
  const qParam = sp.get('q') ?? CAMADA_ANTIGA[sp.get('camada') ?? ''] ?? sp.get('camada');
  const achado = acharQuesito(temas, qParam)
    ?? acharQuesito(temas, 'unidades')
    ?? { tema: temas[0], quesito: temas[0].quesitos[0] };
  const { tema, quesito } = achado;
  const recParam = sp.get('recorte') as Recorte | null;
  const recorte: Recorte = recParam && quesito.recortes.includes(recParam) ? recParam : quesito.recortes[0];
  const areaDrill = recorte === 'setor' && sp.get('area') ? Number(sp.get('area')) : null;
  const pontosRede = recorte === 'pontos' && quesito.pontos === 'rede';

  const selectedId = sp.get('unidade') ? Number(sp.get('unidade')) : null;
  const view = sp.get('visao') === 'lista' && pontosRede ? 'lista' : 'mapa';
  const [filter, setFilter] = useState<Filter>((sp.get('filtro') as Filter) ?? 'todas');
  const [snap, setSnap] = useState<Snap>('peek');
  const [layersOpen, setLayersOpen] = useState(false);
  const [q, setQ] = useState('');
  const dq = useDebounced(q.trim(), 280);
  const geoSearch = useRpc<any>('geo_search', { q: dq }, { enabled: dq.length >= 2 });
  const [point, setPoint] = useState<{ lat: number; lng: number; label: string } | null>(null);
  const [showAreas, setShowAreas] = useState(false);
  const [foco, setFoco] = useState<{ chave: string; caixa: Caixa } | null>(null);

  const setParams = (mudar: Record<string, string | null>) => {
    const n = new URLSearchParams(sp);
    for (const [k, v] of Object.entries(mudar)) {
      if (v == null) n.delete(k);
      else n.set(k, v);
    }
    n.delete('camada');
    setSp(n, { replace: true });
  };
  const setParam = (k: string, v: string | null) => setParams({ [k]: v });
  const irQuesito = (valor: string, rec?: Recorte) => { setFoco(null); setParams({ q: valor, recorte: rec ?? null, area: null, unidade: null }); };

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

  // ponto pesquisado (ou a casa da família): as unidades mais próximas, medidas em linha reta (padrão), a pé ou de carro
  const [medida, setMedida] = useState<MedidaDistancia>('LINHA_RETA');
  const perto = useMemo(() => (point && pontosRede ? list.slice(0, PERTO) : []), [list, point, pontosRede]);
  const dist = useDistancias(point && perto.length
    ? { lat: point.lat, lng: point.lng, unidades: perto.map((u) => u.id), geometrias_modo: modoTracado(medida) } : null);
  const porUnidade = useMemo(() => new Map((dist.data?.unidades ?? []).map((u) => [u.id, u])), [dist.data]);
  const ordenadas = useMemo(() => {
    const val = (u: UnitMapItem) => {
      const x = porUnidade.get(u.id);
      return (x ? metros(x, medida) : null) ?? (point ? distance(point, u) : 0);
    };
    return [...perto].sort((a, b) => val(a) - val(b));
  }, [perto, porUnidade, medida, point]);
  const trajetos = trajetosDe(dist.data, medida);

  const select = (u: UnitMapItem | null) => {
    setParam('unidade', u ? String(u.id) : null);
    if (u) setSnap('half');
  };

  // rotas do transporte escolar (perfis com acesso ao transporte): trajetos pelas ruas e veículos a caminho
  const verRotas = recorte === 'pontos' && quesito.pontos === 'rotas';
  const tr = useRpc<any[]>('transporte_mapa', {}, { enabled: verRotas, refetchInterval: 60_000 });
  const linhasTr = useMemo(() => (verRotas ? (tr.data ?? []).map((r, i) => ({
    id: String(r.id), coords: r.linha as [number, number][], rotulo: r.codigo,
    cor: ['#1D6FD8', '#7A24C5', '#0A8F5B', '#D94C4C', '#F28C38', '#0E7490', '#A21CAF', '#4D7C0F'][i % 8],
  })) : null), [tr.data, verRotas]);
  const veiculos = useMemo(() => (verRotas ? (tr.data ?? []).filter((r) => r.agora?.posicao)
    .map((r) => ({ lat: r.agora.posicao.lat, lng: r.agora.posicao.lng, tipo: 'VEICULO' as const, rotulo: '' })) : null), [tr.data, verRotas]);

  // pontos do mapa de calor
  const verCalor = recorte === 'pontos' && quesito.pontos === 'calor';
  const calorRes = useRpc<any>('mapa_calor', { camada: quesito.value }, {
    enabled: verCalor, staleTime: 60_000, refetchInterval: quesito.value === 'transporte_veiculos' ? 60_000 : false,
  });
  const calor = useMemo<Calor | null>(() => (verCalor && calorRes.data
    ? { modo: calorRes.data.modo, pontos: calorRes.data.pontos ?? [], escala: calorRes.data.escala ?? null, max: calorRes.data.max ?? null } : null), [verCalor, calorRes.data]);

  // áreas de ponderação e setores censitários
  const recRes = useRpc<DadosRecorte>('mapa_recorte', { camada: quesito.value, recorte: recorte === 'pontos' ? 'area' : recorte, area_id: areaDrill },
    { enabled: recorte !== 'pontos', staleTime: 60_000 });
  const setoresGeo = useGeoSetores(recorte === 'setor', areaDrill ?? undefined);
  const nomes = useMemo(() => {
    const m = new Map<string, string>();
    for (const f of geo.data?.regions?.features ?? []) m.set(String(f.properties?.id), String(f.properties?.name));
    for (const f of setoresGeo.data?.features ?? []) {
      const p = f.properties ?? {};
      m.set(String(p.code), `Setor ${String(p.code).slice(-6)}${p.bairro ? ` · ${p.bairro}` : ''} (${p.area})`);
    }
    return m;
  }, [geo.data, setoresGeo.data]);
  const areaFeicao = areaDrill != null ? geo.data?.regions?.features.find((f) => f.properties?.id === areaDrill) : undefined;
  const areaNome = areaFeicao ? String(areaFeicao.properties?.name) : null;

  const coropleta = useMemo<Coropleta | null>(() => {
    const d = recRes.data;
    if (recorte === 'pontos' || !d) return null;
    const base = recorte === 'area' ? geo.data?.regions : setoresGeo.data;
    if (!base) return null;
    const porChave = new Map(d.itens.map((i) => [String(i.chave), i]));
    const censo = quesito.value === 'criancas_0a4' || quesito.value === 'pessoas';
    const feicoes = base.features
      .filter((f) => recorte === 'area' || areaDrill == null || f.properties?.area_id === areaDrill)
      .map((f) => {
        const chave = recorte === 'area' ? String(f.properties?.id) : String(f.properties?.code);
        const it = porChave.get(chave);
        // sem observação: soma = 0 (nada ali); taxa e Censo = sem dado
        const valor = it ? (it.oculto ? null : it.valor) : d.tipo === 'soma' && !censo ? 0 : null;
        const nome = nomes.get(chave) ?? chave;
        const txt = valor != null ? `${valor.toLocaleString('pt-BR', { maximumFractionDigits: 1 })}${d.sufixo}`
          : it?.oculto ? (d.pela_casa ? `sigilo (menos de ${d.minimo} pessoas)` : 'sigilo do IBGE') : 'sem dado';
        return { type: 'Feature' as const, geometry: f.geometry, properties: { chave, valor, titulo: `${nome}: ${txt}` } };
      });
    const valores = feicoes.map((f) => f.properties.valor).filter((v): v is number => v != null);
    return {
      tipo: recorte,
      feicoes: { type: 'FeatureCollection', features: feicoes },
      escala: quesito.escala?.[recorte] ?? escalaDosValores(valores, d.pior),
      titulo: `${recorte === 'area' ? 'Áreas de ponderação' : 'Setores censitários'} · ${quesito.label}`,
      semValor: d.pela_casa ? `Sigilo: menos de ${d.minimo} pessoas` : censo ? 'Sigilo do IBGE' : d.tipo === 'taxa' ? 'Sem dado' : null,
    };
  }, [recRes.data, recorte, geo.data, setoresGeo.data, areaDrill, quesito, nomes]);

  // a área detalhada, o setor tocado no ranking ou, ao voltar para a cidade, o conjunto das unidades
  const caixaCidade = useMemo<Caixa | null>(() => {
    if (!all.length) return null;
    const lats = all.map((u) => u.lat);
    const lngs = all.map((u) => u.lng);
    return [[Math.min(...lngs), Math.min(...lats)], [Math.max(...lngs), Math.max(...lats)]];
  }, [all]);
  const enquadrar = useMemo(() => {
    if (foco) return foco;
    const caixa = caixaDe(areaFeicao?.geometry);
    if (areaDrill != null && caixa) return { chave: `area-${areaDrill}`, caixa };
    return caixaCidade ? { chave: 'cidade', caixa: caixaCidade } : null;
  }, [foco, areaDrill, areaFeicao, caixaCidade]);

  const descerArea = (chave: string) => { setFoco(null); setParams({ recorte: 'setor', area: chave, unidade: null }); setSnap('half'); };
  const focarSetor = (chave: string) => {
    const f = setoresGeo.data?.features.find((x) => String(x.properties?.code) === chave);
    const caixa = caixaDe(f?.geometry);
    if (caixa) setFoco({ chave: `setor-${chave}-${Date.now()}`, caixa });
  };
  const voltarCidade = () => { setFoco(null); setParams({ recorte: quesito.recortes.includes('area') ? 'area' : null, area: null }); };

  const sheetH = { peek: 132, half: desktop ? 0 : 0.5, full: 0.86 }[snap];
  const mostrarUnidades = tema.value === 'rede' && !verCalor && !verRotas;

  return (
    <div className="flex h-[calc(100dvh-64px-66px-env(safe-area-inset-bottom)-env(safe-area-inset-top))] flex-col overflow-hidden lg:h-[calc(100dvh-64px)]">
      {/* temas, quesitos e recorte */}
      <div className="shrink-0 space-y-2 border-b border-line bg-white px-3 pb-2.5 pt-2.5 lg:px-4">
        <div className="no-scrollbar -mx-3 flex gap-1.5 overflow-x-auto px-3 lg:mx-0 lg:px-0" role="tablist" aria-label="Temas do mapa">
          {temas.map((t) => (
            <Chip key={t.value} icon={t.icon} active={t.value === tema.value} onClick={() => irQuesito(t.quesitos[0].value)}>{t.label}</Chip>
          ))}
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {tema.quesitos.length > 1 && (
            <div className="no-scrollbar min-w-0 max-w-full flex-1 overflow-x-auto">
              <Segmented className="whitespace-nowrap" value={quesito.value} onChange={(v) => irQuesito(v, recorte)} items={tema.quesitos.map((x) => ({ value: x.value, label: x.label }))} />
            </div>
          )}
          {quesito.recortes.length > 1 && (
            <div className="flex items-center gap-2">
              <span className="text-[12px] font-semibold text-subtle">Recorte</span>
              <Segmented className="whitespace-nowrap" value={recorte} onChange={(v) => { setFoco(null); setParams({ recorte: v, area: null }); }}
                items={quesito.recortes.map((r) => ({ value: r, label: RECORTE_ROTULO[r] }))} />
            </div>
          )}
        </div>
      </div>

      <div className="relative min-h-0 flex-1">
        {view === 'mapa' ? (
          <MapView
            className="absolute inset-0"
            units={mostrarUnidades ? list : []}
            showUnits={mostrarUnidades}
            geo={areaDrill != null && geo.data ? { ...geo.data, regions: { type: 'FeatureCollection', features: areaFeicao ? [areaFeicao] : [] } } : geo.data}
            selectedId={selectedId}
            onSelectUnit={select}
            heat={pontosRede ? quesito.rede?.heat ?? null : null}
            colorMode={pontosRede && (quesito.rede?.colorMode === 'vacancy' || filter === 'vaga' || filter === 'creche') ? 'vacancy' : 'type'}
            calor={calor}
            coropleta={coropleta}
            onSelectCoropleta={recorte === 'area' ? descerArea : undefined}
            enquadrar={enquadrar}
            showAreas={showAreas}
            home={point && pontosRede ? { lat: point.lat, lng: point.lng, radius_m: medida === 'LINHA_RETA' ? 2000 : undefined } : null}
            highlight={point && pontosRede ? ordenadas.map((u, i) => ({ id: u.id, label: String(i + 1) })) : undefined}
            highlightLabel={`Mais perto ${MEDIDA[medida].curto} (número = ordem)`}
            lines={!!point && pontosRede && medida === 'LINHA_RETA'}
            trajetos={point && pontosRede ? trajetos : null}
            linhas={linhasTr}
            pontos={veiculos}
            onSelectLinha={(id) => navigate(`/transporte/rotas/${id}`)}
            homeLabel="Ponto pesquisado"
            legend="overlay"
            legendClassName={desktop ? 'bottom-3 left-[424px]' : 'left-3 top-[66px]'}
            focus={selected ? { lat: selected.lat, lng: selected.lng, zoom: 15 } : point && pontosRede ? { lat: point.lat, lng: point.lng, zoom: 13.6 } : null}
            fitKey={`${filter}-${verRotas ? (tr.data?.length ?? 0) : ''}`}
            fitLinhas={verRotas && !point && !selected}
            padding={{ top: point ? 120 : 70, bottom: desktop ? 40 : 170, left: desktop ? 420 : 30, right: 70 }}
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
                <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Bairro, área (ex.: AP 017) ou unidade…" className="h-full min-w-0 flex-1 bg-transparent text-[15px] outline-none" aria-label="Buscar bairro, área ou unidade" />
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
                            if (u) {
                              if (!pontosRede) irQuesito('unidades', 'pontos');
                              select(u);
                            }
                          } else if (it.kind === 'AREA') {
                            // área: os setores dela no quesito aberto (ou a ficha, se o quesito não tem setores)
                            if (quesito.recortes.includes('setor')) descerArea(String(it.territory_id));
                            else navigate(`/territorios/${it.territory_id}`);
                          } else {
                            if (!pontosRede) irQuesito('unidades', 'pontos');
                            setPoint({ lat: it.lat, lng: it.lng, label: it.label });
                            setParam('unidade', null);
                            setSnap('half');
                          }
                        }}
                      >
                        {it.kind === 'UNIDADE' ? <School className="size-5 text-purple-700" /> : it.kind === 'AREA' ? <MapPinned className="size-5 text-purple-700" /> : <MapPin className="size-5 text-blue-700" />}
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
            <button onClick={() => setLayersOpen(true)} className="glass inline-flex size-12 items-center justify-center rounded-2xl shadow-soft ring-1 ring-white/70" aria-label="Mais opções do mapa">
              <Layers className="size-5" />
            </button>
            {pontosRede && (
              <button onClick={() => setParam('visao', view === 'mapa' ? 'lista' : null)} className="glass inline-flex h-12 items-center gap-1.5 rounded-2xl px-3 text-sm font-semibold shadow-soft ring-1 ring-white/70" aria-label={view === 'mapa' ? 'Ver em lista' : 'Ver no mapa'}>
                {view === 'mapa' ? <List className="size-5" /> : <MapIcon className="size-5" />}
                <span className="hidden sm:inline">{view === 'mapa' ? 'Lista' : 'Mapa'}</span>
              </button>
            )}
          </div>
          {pontosRede && (
            <div className="pointer-events-auto no-scrollbar mt-2 flex gap-2 overflow-x-auto pb-1">
              {([['todas', 'Todas'], ['cmei', 'CMEIs'], ['escola', 'Escolas'], ['vaga', 'Com vaga'], ['creche', 'Creche com vaga']] as [Filter, string][]).map(([v, l]) => (
                <Chip key={v} active={filter === v} onClick={() => { setFilter(v); setParam('filtro', v === 'todas' ? null : v); }}>{l}</Chip>
              ))}
            </div>
          )}
          {point && pontosRede && view === 'mapa' && (
            <div className="pointer-events-auto mt-1">
              <SeletorMedida value={medida} onChange={setMedida} carregando={dist.calculando} />
            </div>
          )}
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
                <UnitSummary u={selected} point={point} dist={porUnidade.get(selected.id) ?? null} medida={medida} onClose={() => select(null)} />
              ) : pontosRede ? (
                <Overview list={list} point={point} quesito={quesito.value} onClearPoint={() => setPoint(null)} onPick={select} total={all.length}
                  perto={ordenadas} porUnidade={porUnidade} medida={medida} calculando={dist.calculando} />
              ) : (
                <PainelQuesito tema={tema} quesito={quesito} recorte={recorte} areaNome={areaNome} areaId={areaDrill}
                  calor={calorRes} rec={recRes} nomes={nomes} onArea={descerArea} onSetor={focarSetor} onVoltar={voltarCidade} />
              )}
            </div>
          </motion.div>
        )}
      </div>

      <Sheet open={layersOpen} onClose={() => setLayersOpen(false)} title="Mais opções do mapa" subtitle="Temas e recortes ficam na barra acima do mapa">
        <label className="flex items-center gap-3 rounded-2xl bg-white p-3 ring-1 ring-line">
          <input type="checkbox" checked={showAreas} onChange={(e) => setShowAreas(e.target.checked)} className="size-5 accent-purple-700" />
          <div className="flex-1">
            <div className="font-semibold">Áreas de influência (proximidade)</div>
            <div className="text-[12.5px] text-muted">Divisão do território pela unidade mais próxima — cálculo de demonstração, não é o zoneamento oficial.</div>
          </div>
        </label>
        {temas.length > 0 && (
          <p className="mt-3 text-[12.5px] text-muted">
            Áreas de ponderação e setores censitários: IBGE, Censo Demográfico 2022. O que depende da casa da pessoa só aparece somado, com 3 ou mais pessoas no território.
          </p>
        )}
      </Sheet>
    </div>
  );
}

function Overview({ list, point, quesito, onClearPoint, onPick, total, perto, porUnidade, medida, calculando }: {
  list: UnitMapItem[]; point: any; quesito: string; onClearPoint: () => void; onPick: (u: UnitMapItem) => void; total: number;
  perto: UnitMapItem[]; porUnidade: Map<number, DistanciaUnidade>; medida: MedidaDistancia; calculando: boolean;
}) {
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
      {point && (
        <p className="mt-2 rounded-2xl bg-purple-50 p-2.5 text-[12.5px] text-purple-900">
          {medida === 'LINHA_RETA'
            ? 'Círculo = 2 km em linha reta (critério de proximidade da fila). '
            : `Caminho ${MEDIDA[medida].curto} pelas ruas até cada unidade. `}
          As {perto.length} mais próximas estão numeradas, na ordem da distância {MEDIDA[medida].curto}. <LinkMetodologia className="text-[12.5px]" />
        </p>
      )}
      {point && perto.length > 0 && (
        <div className="mt-3 divide-y divide-line">
          {perto.map((u, i) => {
            const x = porUnidade.get(u.id);
            return (
              <button key={u.id} onClick={() => onPick(u)} className="flex w-full items-center gap-3 py-2.5 text-left">
                <span className="inline-flex size-9 shrink-0 items-center justify-center rounded-full bg-purple-700 font-display text-[14px] font-black text-white">{i + 1}</span>
                <div className="min-w-0 flex-1">
                  <div className="truncate text-[14.5px] font-semibold">{u.name}</div>
                  {x ? <TresDistancias variante="linha" u={x} destaque={medida} calculando={calculando} />
                    : <div className="truncate text-[12px] text-muted">{u.neighborhood} · {fmtKm(distance(point, u))} em linha reta</div>}
                </div>
                <span className={clsx('text-[12.5px] font-bold tabular', u.offerable > 0 ? 'text-green-700' : 'text-muted')}>{u.offerable > 0 ? `${u.offerable} vagas` : '—'}</span>
              </button>
            );
          })}
        </div>
      )}
      <div className="mt-3 divide-y divide-line">
        {list.slice(point ? perto.length : 0, point ? 12 : 25).map((u) => (
          <button key={u.id} onClick={() => onPick(u)} className="flex w-full items-center gap-3 py-2.5 text-left">
            <span className={clsx('inline-flex size-9 shrink-0 items-center justify-center rounded-xl text-white', u.status !== 'ATIVA' ? 'bg-slate-400' : u.type === 'CMEI' ? 'bg-purple-500' : 'bg-blue-500')}>
              <School className="size-4" />
            </span>
            <div className="min-w-0 flex-1">
              <div className="truncate text-[14.5px] font-semibold">{u.name}</div>
              <div className="truncate text-[12px] text-muted">{u.neighborhood}{point ? ` · ${fmtKm(distance(point, u))}` : ''}</div>
            </div>
            <span className={clsx('text-[12.5px] font-bold tabular', u.offerable > 0 ? 'text-green-700' : 'text-muted')}>{u.offerable > 0 ? `${u.offerable} vagas` : quesito === 'fila' ? `${u.queue} fila` : '—'}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

function UnitSummary({ u, point, dist, medida, onClose }: { u: UnitMapItem; point: any; dist: DistanciaUnidade | null; medida: MedidaDistancia; onClose: () => void }) {
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
            {point && !dist && <Badge tone="gray" icon={Navigation}>{fmtKm(distance(point, u))} em linha reta</Badge>}
          </div>
          {point && dist && (
            <div className="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-[12.5px]">
              <span className="font-semibold text-ink-2">Do ponto pesquisado:</span>
              <TresDistancias variante="linha" u={dist} destaque={medida} />
            </div>
          )}
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
