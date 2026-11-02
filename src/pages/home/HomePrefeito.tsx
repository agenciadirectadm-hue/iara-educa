import { useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router';
import clsx from 'clsx';
import {
  AlertTriangle, Building2, ChevronRight, ClipboardList, Flame, GraduationCap, Hammer, Info, ListOrdered, Map as MapIcon, Route, Sparkles, Timer, Users,
} from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { useGeoLayers, useGeoSetores, useUnitsMap } from '@/lib/data';
import { fmt1, fmtInt, fmtPct } from '@/lib/format';
import { PRESSURE } from '@/lib/labels';
import { Badge, Card, ErrorState, Kpi, LinkCard, PageHeader, Section, Segmented, SkeletonList, SourceChip } from '@/components/ui';
import { AreaChart, BarList } from '@/components/charts';
import { IaraBubble } from '@/components/iara';
import MapView, { type Coropleta } from '@/components/map/MapView';
import { PURPLE } from '@/components/map/mapStyle';
import type { DadosRecorte } from '@/components/mapas/PainelQuesito';

/** O mapa do Início: as unidades da rede sobre a divisão do IBGE — por região (área de ponderação) ou microrregião (setor). */
type Ver = 'area' | 'setor';
/** Áreas de ponderação mostradas antes de "ver todas" (as de maior pressão vêm primeiro). */
const AREAS_INICIAIS = 6;

export default function HomePrefeito() {
  const dash = useRpc<any>('dashboard_prefeito');
  const units = useUnitsMap();
  const geo = useGeoLayers();
  const navigate = useNavigate();
  const [ver, setVer] = useState<Ver>('area');
  const [todasAreas, setTodasAreas] = useState(false);
  const setores = useGeoSetores(ver === 'setor');
  // quantas unidades há em cada região ou microrregião (para a dica ao passar o mouse)
  const contagem = useRpc<DadosRecorte>('mapa_recorte', { camada: 'unidades', recorte: ver }, { staleTime: 10 * 60_000 });

  // só a divisão (localização, sem medida): contorno e fundo quase transparente; tocar abre a ficha da região
  const divisao = useMemo<(Coropleta & { areaDe: Map<string, number> }) | null>(() => {
    const base = ver === 'area' ? geo.data?.regions : setores.data;
    if (!base) return null;
    const n = new Map((contagem.data?.itens ?? []).map((i) => [String(i.chave), Number(i.valor ?? 0)]));
    const areaDe = new Map<string, number>();
    const feicoes = base.features.map((f) => {
      const p = f.properties ?? {};
      const chave = ver === 'area' ? String(p.id) : String(p.code);
      areaDe.set(chave, Number(ver === 'area' ? p.id : p.area_id));
      const nome = ver === 'area' ? String(p.name) : `Microrregião ${String(p.code).slice(-6)}${p.bairro ? ` · ${p.bairro}` : ''} (${p.area})`;
      const k = n.get(chave) ?? 0;
      return { type: 'Feature' as const, geometry: f.geometry, properties: { chave, cor: PURPLE, titulo: `${nome}: ${k === 0 ? 'nenhuma unidade' : `${k} unidade(s)`}` } };
    });
    return {
      tipo: ver, neutra: true, areaDe,
      feicoes: { type: 'FeatureCollection', features: feicoes },
      faixas: { titulo: ver === 'area' ? 'Regiões do IBGE (áreas de ponderação)' : 'Microrregiões do IBGE (setores censitários)',
                itens: [{ cor: 'rgba(122,36,197,0.25)', rotulo: ver === 'area' ? '29 regiões · toque para abrir a ficha' : '793 microrregiões · toque para abrir a ficha da região' }] },
    };
  }, [ver, geo.data, setores.data, contagem.data]);

  if (dash.isLoading) return <SkeletonList rows={6} />;
  if (dash.error) return <ErrorState error={dash.error} onRetry={() => dash.refetch()} />;
  const d = dash.data;
  const k = d.kpis;
  const worst = d.regions?.[0];

  return (
    <div>
      <PageHeader eyebrow="Visão do Prefeito · cidade inteira" title="Onde precisamos investir?" subtitle="Todas as unidades da rede — CMEIs e escolas — por região do IBGE. Os demais mapas ficam em Mapas." />

      <Card className="relative overflow-hidden">
        <MapView
          className="h-[52vh] min-h-[360px] lg:h-[480px]"
          units={units.data?.units ?? []}
          geo={geo.data}
          coropleta={divisao}
          onSelectCoropleta={(chave) => { const id = divisao?.areaDe.get(chave); if (id) navigate(`/territorios/${id}`); }}
          onSelectUnit={(u) => navigate(`/unidades/${u.id}`)}
          fitKey="cidade"
          cooperative
          padding={{ top: 64, bottom: 30, left: 24, right: 64 }}
          legendNote={<>Toque numa unidade ou região para abrir <SourceChip kind="publico" /></>}
        />
        <div className="pointer-events-none absolute inset-x-0 top-0 flex flex-wrap gap-2 p-3">
          <div className="pointer-events-auto flex flex-wrap items-center gap-2">
            <Segmented className="whitespace-nowrap shadow-soft" value={ver} onChange={setVer}
              items={[{ value: 'area', label: 'Regiões' }, { value: 'setor', label: 'Microrregiões' }]} />
            <Link to="/mapa" className="inline-flex h-11 shrink-0 items-center gap-1.5 rounded-2xl bg-purple-700 px-4 text-[13.5px] font-semibold text-white shadow-soft hover:bg-purple-800">
              <MapIcon className="size-4" aria-hidden />Todos os mapas<ChevronRight className="size-4" aria-hidden />
            </Link>
          </div>
        </div>
      </Card>

      <div className="no-scrollbar -mx-4 mt-4 flex snap-x gap-3 overflow-x-auto px-4 pb-1 sm:mx-0 sm:grid sm:grid-cols-3 sm:px-0 lg:grid-cols-6">
        <Kpi className="w-40 shrink-0 snap-start sm:w-auto" compact icon={Building2} tone="blue" label="Unidades" value={fmtInt(k.official.units)} sub={`${k.official.cmeis} CMEIs · ${k.official.schools} escolas`} source="oficial" to="/unidades" />
        <Kpi className="w-40 shrink-0 snap-start sm:w-auto" compact icon={GraduationCap} tone="purple" label="Turmas" value={fmtInt(k.official.classes)} sub={`ref. ${k.official.reference_date}`} source="oficial" to="/indicadores" />
        <Kpi className="w-40 shrink-0 snap-start sm:w-auto" compact icon={Users} tone="teal" label="Matrículas" value={fmtInt(k.official.enrollments)} sub="agregado público" source="oficial" to="/indicadores" />
        <Kpi className="w-40 shrink-0 snap-start sm:w-auto" compact icon={Sparkles} tone="green" label="Vagas ofertáveis" value={fmtInt(k.operational.offerable)} sub={`${fmtPct(k.operational.occupancy)} de ocupação`} source="demo" to="/mapa?camada=vagas" />
        <Kpi className="w-40 shrink-0 snap-start sm:w-auto" compact icon={ListOrdered} tone="red" label="Fila de espera" value={fmtInt(k.operational.waiting)} sub={`${fmtInt(k.operational.waiting_no_service)} sem atendimento`} source="demo" to="/indicadores" />
        <Kpi className="w-40 shrink-0 snap-start sm:w-auto" compact icon={ClipboardList} tone="amber" label="Protocolos abertos" value={fmtInt(k.operational.open_cases)} sub={`${fmtInt(k.operational.overdue_cases)} com prazo vencido`} source="demo" to="/indicadores" />
      </div>

      {worst && worst.balance_creche < 0 && (
        <div className="mt-5">
          <IaraBubble compact>
            A área com maior pressão é a <b>{worst.name}</b>: {fmtInt(worst.queue_creche)} crianças aguardam creche para {fmtInt(worst.offerable_creche)} vagas ofertáveis
            (saldo <b className="text-red-700">{fmtInt(worst.balance_creche)}</b>; {fmtInt(worst.criancas_0a4)} crianças de 0 a 4 anos moram ali, pelo Censo 2022). <Link className="font-semibold text-purple-700 underline" to={`/territorios/${worst.id}`}>Explorar área</Link>
          </IaraBubble>
        </div>
      )}

      <Section title="Pressão por área de ponderação" subtitle="Saldo de creche = vagas ofertáveis − crianças na fila (demonstração). Áreas do IBGE, Censo 2022."
        action={d.regions.length > AREAS_INICIAIS ? (
          <button type="button" onClick={() => setTodasAreas(!todasAreas)} className="text-[13px] font-semibold text-purple-700">
            {todasAreas ? 'Mostrar só as de maior pressão' : `Ver as ${d.regions.length} áreas`}
          </button>
        ) : undefined}>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {(todasAreas ? d.regions : d.regions.slice(0, AREAS_INICIAIS)).map((r: any) => {
            const pr = PRESSURE[r.pressure];
            return (
              <LinkCard key={r.id} to={`/territorios/${r.id}`} className="p-4">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="font-display text-lg font-extrabold leading-tight">{r.name}</div>
                    <div className="text-[12.5px] text-muted">{r.units} unidades · {fmtInt(r.enrollments)} matrículas · {fmtInt(r.criancas_0a4)} crianças de 0 a 4 anos</div>
                  </div>
                  <Badge tone={pr.tone} dot>{pr.label}</Badge>
                </div>
                <div className="mt-3 grid grid-cols-3 gap-2 text-center">
                  <div className="rounded-2xl bg-red-50 p-2">
                    <div className="font-display text-xl font-extrabold tabular text-red-700">{fmtInt(r.queue_creche)}</div>
                    <div className="text-[11px] font-semibold text-muted">fila creche</div>
                  </div>
                  <div className="rounded-2xl bg-green-50 p-2">
                    <div className="font-display text-xl font-extrabold tabular text-green-800">{fmtInt(r.offerable_creche)}</div>
                    <div className="text-[11px] font-semibold text-muted">vagas creche</div>
                  </div>
                  <div className={clsx('rounded-2xl p-2', r.balance_creche < 0 ? 'bg-amber-50' : 'bg-blue-50')}>
                    <div className={clsx('font-display text-xl font-extrabold tabular', r.balance_creche < 0 ? 'text-amber-800' : 'text-blue-900')}>{r.balance_creche > 0 ? '+' : ''}{fmtInt(r.balance_creche)}</div>
                    <div className="text-[11px] font-semibold text-muted">saldo</div>
                  </div>
                </div>
                <div className="mt-3 flex items-center justify-between text-[12.5px] text-muted">
                  <span><Route className="mr-1 inline size-3.5" />{fmt1(r.avg_km)} km casa-escola</span>
                  <span className="inline-flex items-center gap-0.5 font-semibold text-purple-700">Explorar <ChevronRight className="size-4" /></span>
                </div>
              </LinkCard>
            );
          })}
        </div>
      </Section>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title="Alertas" subtitle="Toque para ver a causa">
          <Card className="divide-y divide-line">
            {d.alerts.filter(Boolean).map((a: any, i: number) => (
              <Link key={i} to={a.territory_id ? `/territorios/${a.territory_id}` : '/indicadores'} className="flex items-center gap-3 p-4 hover:bg-slate-50">
                <span className={clsx('inline-flex size-10 shrink-0 items-center justify-center rounded-2xl', a.level === 'CRITICO' ? 'bg-red-100 text-red-700' : a.level === 'ATENCAO' ? 'bg-amber-100 text-amber-800' : 'bg-blue-100 text-blue-800')}>
                  {a.level === 'INFO' ? <Info className="size-5" /> : <AlertTriangle className="size-5" />}
                </span>
                <span className="flex-1 text-[14.5px] font-semibold">{a.title}</span>
                <ChevronRight className="size-5 text-subtle" />
              </Link>
            ))}
          </Card>
        </Section>

        <Section title="Onde abrir vagas" subtitle="Cenário por regra simples — apoio à decisão" action={<SourceChip kind="projetado" detail={d.expansion?.[0]?.note} />}>
          <Card className="p-4">
            {d.expansion.length ? (
              <BarList
                items={[...d.expansion].sort((a: any, b: any) => b.deficit_creche - a.deficit_creche).slice(0, 8).map((e: any) => ({
                  key: e.territory, label: e.territory, value: e.deficit_creche, color: 'linear-gradient(90deg,#F2B640,#D94C4C)',
                  sub: `≈ ${e.suggested_classes} novas turmas de creche (capacidade de referência 20)`,
                  to: `/territorios/${d.regions.find((r: any) => r.name === e.territory)?.id ?? ''}`,
                }))}
                valueSuffix=" crianças"
              />
            ) : (
              <p className="text-sm text-muted">Nenhuma área de ponderação com déficit de creche no momento.</p>
            )}
            <div className="mt-3 flex items-start gap-2 rounded-2xl bg-purple-50 p-3 text-[12.5px] text-purple-900">
              <Hammer className="mt-0.5 size-4 shrink-0" /> Expansões e obras entram aqui quando o módulo de infraestrutura for integrado.
            </div>
          </Card>
        </Section>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <Section title="Distância casa-escola" action={<SourceChip kind="demo" detail={d.distance.source} />}>
          <Card className="p-4">
            <div className="font-display text-4xl font-black tabular text-ink">{fmt1(d.distance.avg_km)} <span className="text-lg text-muted">km</span></div>
            <div className="text-[13px] text-muted">média em linha reta · {fmtInt(d.distance.students)} alunos</div>
            <div className="mt-3 h-3 overflow-hidden rounded-full bg-slate-100">
              <div className="h-full rounded-full bg-gradient-to-r from-green-500 to-green-700" style={{ width: `${d.distance.within_2km_pct}%` }} />
            </div>
            <div className="mt-1 text-[13px] font-semibold text-green-800">{fmtPct(d.distance.within_2km_pct)} estudam até 2 km de casa</div>
          </Card>
        </Section>
        <Section title="Atendimento" action={<SourceChip kind="demo" />}>
          <Card className="p-4">
            <div className="flex items-center gap-3">
              <span className="inline-flex size-11 items-center justify-center rounded-2xl bg-blue-100 text-blue-800"><Timer className="size-5" /></span>
              <div>
                <div className="font-display text-3xl font-black tabular">{fmt1(d.service.avg_resolution_days)} <span className="text-base text-muted">dias</span></div>
                <div className="text-[13px] text-muted">tempo médio até a resolução</div>
              </div>
            </div>
            <div className="mt-3 text-[13px] font-semibold text-ink-2">{fmtPct(d.service.within_sla_pct)} resolvidos dentro do prazo · {fmtInt(d.service.closed)} protocolos (120 dias)</div>
          </Card>
        </Section>
        <Section title="Demanda futura de creche" action={<SourceChip kind="projetado" detail={d.projection.method} />}>
          <Card className="p-4">
            <AreaChart
              points={d.monthly.slice(-6).map((m: any) => ({ label: m.month.slice(5) + '/' + m.month.slice(2, 4), value: m.queue_in }))}
              projected={(d.projection.next_months ?? []).map((v: number, i: number) => ({ label: `+${i + 1}m`, value: v }))}
              height={140}
            />
            <div className="text-[12px] text-muted">Entradas mensais na fila · linha tracejada = projeção (cenário)</div>
          </Card>
        </Section>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title="Unidades saturadas" subtitle="Fila alta e nenhuma vaga ofertável">
          <Card className="divide-y divide-line">
            {d.saturated.map((u: any) => (
              <Link key={u.id} to={`/unidades/${u.id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-slate-50">
                <span className="inline-flex size-9 items-center justify-center rounded-xl bg-red-100 text-red-700"><Flame className="size-4" /></span>
                <div className="min-w-0 flex-1">
                  <div className="truncate font-semibold">{u.name}</div>
                  <div className="text-[12.5px] text-muted">{u.territory} · ocupação {fmtPct(u.occupancy)}</div>
                </div>
                <Badge tone="red">{fmtInt(u.queue)} na fila</Badge>
              </Link>
            ))}
          </Card>
        </Section>
        <Section title="Capacidade ociosa" subtitle="Vagas sobrando e pouca fila — remanejamento possível">
          <Card className="divide-y divide-line">
            {d.idle.map((u: any) => (
              <Link key={u.id} to={`/unidades/${u.id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-slate-50">
                <span className="inline-flex size-9 items-center justify-center rounded-xl bg-blue-100 text-blue-800"><MapIcon className="size-4" /></span>
                <div className="min-w-0 flex-1">
                  <div className="truncate font-semibold">{u.name}</div>
                  <div className="text-[12.5px] text-muted">{u.territory} · ocupação {fmtPct(u.occupancy)}</div>
                </div>
                <Badge tone="green">{fmtInt(u.offerable)} vagas</Badge>
              </Link>
            ))}
          </Card>
        </Section>
      </div>
    </div>
  );
}
