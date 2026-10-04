import { useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router';
import clsx from 'clsx';
import { ArrowDownUp, Building2, ClipboardList, Download, FileSpreadsheet, GraduationCap, ListOrdered, MapPinned, PieChart, Sparkles, Timer, Users } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { useBootstrap } from '@/lib/data';
import { fmt1, fmtInt, fmtPct } from '@/lib/format';
import { PRESSURE, QUEUE_CATEGORY, QUEUE_CATEGORY_COLOR } from '@/lib/labels';
import { Badge, Button, Card, ErrorState, Kpi, PageHeader, Section, Segmented, SkeletonList, SourceChip } from '@/components/ui';
import { AreaChart, BarList, Donut, Funnel, GroupedBars } from '@/components/charts';
import { useToast } from '@/components/overlays';

const REPORTS: { key: string; title: string; desc: string; network?: boolean }[] = [
  { key: 'ocupacao_por_unidade', title: 'Ocupação por unidade', desc: 'Turmas, capacidade, matrículas, ocupação, vagas ofertáveis e fila' },
  { key: 'vagas_por_turma', title: 'Vagas por turma', desc: 'Capacidade, matrículas, bloqueios, reservas e ofertáveis — fórmula oficial' },
  { key: 'fila_por_unidade', title: 'Fila por unidade e faixa', desc: 'Aguardando, com oferta, espera média e vagas disponíveis' },
  { key: 'fila_por_regiao', title: 'Demanda × oferta por região', desc: 'Saldo por macrorregião e faixa etária', network: true },
  { key: 'protocolos', title: 'Protocolos abertos', desc: 'Por tipo e status, com vencidos no prazo (SLA)' },
];

export default function Indicators() {
  const { can } = useSession();
  return can('kpi.network') ? <NetworkIndicators /> : <UnitIndicators />;
}

function NetworkIndicators() {
  const { me, can } = useSession();
  const navigate = useNavigate();
  const boot = useBootstrap();
  const [stage, setStage] = useState<string>(me?.stage_filter ?? '');
  const pre = useRpc<any>('dashboard_prefeito', {}, { staleTime: 60_000 });
  const sec = useRpc<any>('dashboard_secretario', { stage: stage || null }, { staleTime: 60_000 });
  const [sort, setSort] = useState<'balance_creche' | 'queue' | 'offerable' | 'occupancy' | 'avg_km'>('balance_creche');
  const regions = useMemo(() => {
    const r = [...((pre.data?.regions ?? []) as any[])];
    r.sort((a, b) => (sort === 'balance_creche' ? a.balance_creche - b.balance_creche : (b[sort] ?? 0) - (a[sort] ?? 0)));
    return r;
  }, [pre.data, sort]);

  if (pre.isLoading || sec.isLoading) return <SkeletonList rows={6} />;
  if (pre.error || sec.error) return <ErrorState error={pre.error ?? sec.error} onRetry={() => { pre.refetch(); sec.refetch(); }} />;
  const p = pre.data;
  const s = sec.data;
  const off = p.kpis.official;
  const op = s.kpis.operational;
  const stages = (boot.data?.stages ?? []) as any[];
  const cats = Object.entries(s.by_category ?? {}).map(([key, value]) => ({ key, label: QUEUE_CATEGORY[key]?.label ?? key, value: value as number, color: QUEUE_CATEGORY_COLOR[key] ?? '#94A3B8' }));
  const f = s.offers_funnel;
  return (
    <div>
      <PageHeader
        eyebrow="Indicadores da rede"
        title="Painel de indicadores"
        subtitle="Base oficial e operação lado a lado — cada número diz de onde vem. Toque em barras, fatias e linhas para abrir o detalhe."
        actions={
          <Segmented
            value={stage}
            onChange={setStage}
            items={[{ value: '', label: 'Toda a rede' }, ...stages.filter((x) => x.code === 'EI' || x.code === 'EF').map((x) => ({ value: x.code, label: x.short_name }))]}
          />
        }
      />

      <Section title="Base oficial" subtitle={`${off.reference} · referência ${off.reference_date}`} className="mt-0" action={<SourceChip kind="oficial" detail={off.reference} />}>
        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          <Kpi icon={Building2} label="Unidades" value={fmtInt(off.units)} sub={`${off.cmeis} CMEIs · ${off.schools} escolas`} tone="blue" to="/unidades" source="oficial" />
          <Kpi icon={GraduationCap} label="Turmas" value={fmtInt(off.classes)} sub="Censo Escolar" tone="blue" source="oficial" />
          <Kpi icon={Users} label="Matrículas" value={fmtInt(off.enrollments)} sub="Censo Escolar" tone="blue" source="oficial" />
          <Kpi icon={Users} label="Docentes" value={off.teachers_census ? fmtInt(off.teachers_census) : 'PENDENTE SEDUC'} sub="Censo · funções docentes" tone="blue" source={off.teachers_census ? 'oficial' : 'pendente'} />
        </div>
      </Section>

      <Section title="Operação (demonstração)" subtitle="Calculado a partir das turmas: físicas = capacidade − matrículas; ofertáveis = físicas − bloqueadas − reservadas" action={<SourceChip kind="demo" detail={op.source} />}>
        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          <Kpi icon={PieChart} label="Ocupação" value={fmtPct(op.occupancy)} sub={`${fmtInt(op.enrolled)} de ${fmtInt(op.capacity)} lugares`} tone="purple" source="calculado" />
          <Kpi icon={Sparkles} label="Vagas ofertáveis" value={fmtInt(op.offerable)} sub={`${fmtInt(op.blocked)} bloqueadas · ${fmtInt(op.reserved)} reservadas`} tone="green" to="/vagas" source="calculado" />
          <Kpi icon={ListOrdered} label="Na fila" value={fmtInt(op.waiting)} sub={`${fmtInt(op.waiting_no_service)} sem nenhum atendimento`} tone="red" to="/fila" source="demo" />
          <Kpi icon={ClipboardList} label="Protocolos abertos" value={fmtInt(op.open_cases)} sub={`${fmtInt(op.overdue_cases)} com prazo vencido`} tone="amber" to="/atendimentos" source="demo" />
        </div>
      </Section>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1.4fr_1fr]">
        <Section title="Demanda × oferta por faixa" subtitle="Toque na faixa para abrir a fila">
          <Card className="p-4">
            <GroupedBars
              data={(s.by_grade as any[]).map((g) => ({ key: String(g.grade_level_id), label: g.grade.replace('Educação Infantil', 'EI'), queue: g.queue, offerable: g.offerable, to: `/fila?serie=${g.grade_level_id}` }))}
              series={[{ key: 'queue', label: 'Crianças na fila', color: '#D94C4C' }, { key: 'offerable', label: 'Vagas ofertáveis', color: '#16A36A' }]}
            />
          </Card>
        </Section>
        <Section title="Quem está na fila" subtitle="Categorias separam quem não tem vaga de quem pede troca">
          <Card className="p-4">
            <Donut segments={cats} onSelect={(key) => navigate(`/fila?categoria=${key}`)} center={<><b className="font-display text-2xl tabular">{fmtInt(cats.reduce((a, c) => a + c.value, 0))}</b><span className="text-[11px] text-muted">crianças</span></>} />
          </Card>
        </Section>
      </div>

      <Section
        title="Comparativo por região"
        subtitle="Alternativa em lista ao mapa — toque na região para o detalhe"
        action={<Link to="/mapa" className="inline-flex items-center gap-1 text-[13px] font-semibold text-blue-700"><MapPinned className="size-4" /> Ver no mapa</Link>}
      >
        <Card className="overflow-hidden">
          <div className="no-scrollbar overflow-x-auto">
            <table className="w-full min-w-[720px] text-[13.5px]">
              <thead className="bg-slate-50 text-left text-[11.5px] font-bold uppercase tracking-wide text-subtle">
                <tr>
                  <th className="px-4 py-2.5">Região</th>
                  <th className="px-3 py-2.5 text-right">Unidades</th>
                  {([['offerable', 'Ofertáveis'], ['queue', 'Fila'], ['balance_creche', 'Saldo creche'], ['occupancy', 'Ocupação'], ['avg_km', 'Dist. média']] as const).map(([k, l]) => (
                    <th key={k} className="px-3 py-2.5 text-right">
                      <button onClick={() => setSort(k)} className={clsx('inline-flex items-center gap-1', sort === k && 'text-purple-700')} aria-label={`Ordenar por ${l}`}>
                        {l} <ArrowDownUp className="size-3" />
                      </button>
                    </th>
                  ))}
                  <th className="px-4 py-2.5">Situação</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {regions.map((r) => (
                  <tr key={r.id} className="cursor-pointer transition hover:bg-purple-50/50" onClick={() => navigate(`/territorios/${r.id}`)}>
                    <td className="px-4 py-3 font-semibold"><span className="mr-2 inline-block size-2.5 rounded-full" style={{ background: r.color }} /><Link to={`/territorios/${r.id}`} onClick={(e) => e.stopPropagation()}>{r.name}</Link></td>
                    <td className="px-3 py-3 text-right tabular">{fmtInt(r.units)}</td>
                    <td className="px-3 py-3 text-right tabular">{fmtInt(r.offerable)}</td>
                    <td className="px-3 py-3 text-right tabular">{fmtInt(r.queue)}</td>
                    <td className={clsx('px-3 py-3 text-right font-bold tabular', r.balance_creche < 0 ? 'text-red-700' : 'text-green-700')}>{r.balance_creche > 0 ? '+' : ''}{fmtInt(r.balance_creche)}</td>
                    <td className="px-3 py-3 text-right tabular">{fmtPct(r.occupancy)}</td>
                    <td className="px-3 py-3 text-right tabular">{fmt1(r.avg_km)} km</td>
                    <td className="px-4 py-3"><Badge tone={PRESSURE[r.pressure]?.tone}>{PRESSURE[r.pressure]?.label}</Badge></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      </Section>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <Section title="Entradas na fila de creche" action={<SourceChip kind="projetado" detail={p.projection.method} />}>
          <Card className="p-4">
            <AreaChart
              points={(p.monthly as any[]).slice(-7).map((m) => ({ label: m.month.slice(5) + '/' + m.month.slice(2, 4), value: m.queue_in }))}
              projected={(p.projection.next_months ?? []).map((v: number, i: number) => ({ label: `+${i + 1}m`, value: v }))}
              height={150}
            />
            <div className="text-[12px] text-muted">Linha tracejada = projeção linear (cenário, não fato)</div>
          </Card>
        </Section>
        <Section title="Funil de ofertas" subtitle={`Últimos ${f.window_days} dias`}>
          <Card className="p-4">
            <Funnel steps={[
              { key: 'o', label: 'Ofertadas', value: f.offered, color: '#7A24C5', to: '/ofertas' },
              { key: 'a', label: 'Aceitas', value: f.accepted_or_enrolled, color: '#1594D2', to: '/ofertas' },
              { key: 'm', label: 'Matriculadas', value: f.enrolled, color: '#16A36A' },
              { key: 'r', label: 'Recusadas', value: f.declined, color: '#F2B640' },
              { key: 'e', label: 'Expiradas', value: f.expired, color: '#94A3B8' },
            ]} />
          </Card>
        </Section>
        <Section title="Atendimento" action={<SourceChip kind="demo" />}>
          <Card className="p-4">
            <div className="flex items-center gap-3">
              <span className="inline-flex size-11 items-center justify-center rounded-2xl bg-blue-100 text-blue-800"><Timer className="size-5" /></span>
              <div>
                <div className="font-display text-3xl font-black tabular">{fmt1(p.service.avg_resolution_days)} <span className="text-base text-muted">dias</span></div>
                <div className="text-[13px] text-muted">tempo médio de resolução · {fmtPct(p.service.within_sla_pct)} no prazo</div>
              </div>
            </div>
            <div className="mt-3">
              <BarList
                items={((s.cases?.by_type ?? []) as any[]).slice(0, 5).map((t) => ({ key: t.type, label: t.type, value: t.open, to: '/atendimentos', sub: t.overdue ? `${t.overdue} com prazo vencido` : undefined, color: 'linear-gradient(90deg,#1594D2,#064B86)' }))}
              />
            </div>
          </Card>
        </Section>
      </div>

      <Section title="Distância casa-escola" action={<SourceChip kind="demo" detail={p.distance.source} />}>
        <Card className="flex flex-wrap items-center gap-6 p-4">
          <div>
            <div className="font-display text-4xl font-black tabular">{fmt1(p.distance.avg_km)} <span className="text-lg text-muted">km</span></div>
            <div className="text-[13px] text-muted">média em linha reta · {fmtInt(p.distance.students)} alunos</div>
          </div>
          <div className="min-w-[220px] flex-1">
            <div className="h-3 overflow-hidden rounded-full bg-slate-100"><div className="h-full rounded-full bg-gradient-to-r from-green-500 to-green-700" style={{ width: `${p.distance.within_2km_pct}%` }} /></div>
            <div className="mt-1 text-[13px] font-semibold text-green-800">{fmtPct(p.distance.within_2km_pct)} estudam até 2 km de casa (critério de território)</div>
          </div>
        </Card>
      </Section>

      {can('reports.export') && <Exports />}
    </div>
  );
}

function UnitIndicators() {
  const res = useRpc<any>('dashboard_unidade', {});
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const o = d.ops;
  return (
    <div>
      <PageHeader eyebrow="Indicadores da unidade" title={d.unit.name} subtitle="Os mesmos cálculos da rede, no recorte da sua unidade." />
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Kpi icon={PieChart} label="Ocupação" value={fmtPct(o.occupancy)} sub={`${fmtInt(o.enrolled)} de ${fmtInt(o.capacity)}`} tone="purple" source="calculado" />
        <Kpi icon={Sparkles} label="Vagas ofertáveis" value={fmtInt(o.offerable)} sub={`${fmtInt(o.blocked)} bloqueadas · ${fmtInt(o.reserved)} reservadas`} tone="green" source="calculado" />
        <Kpi icon={ListOrdered} label="Na fila" value={fmtInt(o.queue)} sub="aguardando esta unidade" tone="red" to={`/fila?unidade=${d.unit.id}`} source="demo" />
        <Kpi icon={ClipboardList} label="Protocolos" value={fmtInt(d.cases.open)} sub={`${fmtInt(d.cases.overdue)} com prazo vencido`} tone="amber" to="/atendimentos" source="demo" />
      </div>
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title="Ocupação por turma">
          <Card className="p-4">
            <BarList
              items={(d.classes as any[]).map((c) => ({ key: c.id, label: `${c.name} · ${c.grade}`, value: c.capacity ? Math.round((c.enrolled / c.capacity) * 100) : 0, to: `/turmas/${c.id}`, sub: `${c.enrolled}/${c.capacity} · ${c.offerable} ofertável(is)` }))}
              max={100}
              valueSuffix="%"
            />
          </Card>
        </Section>
        <Section title="Fila por faixa">
          <Card className="p-4">
            {(d.queue as any[]).length ? (
              <BarList items={(d.queue as any[]).map((q) => ({ key: String(q.grade_level_id), label: q.grade, value: q.waiting, to: `/fila?unidade=${d.unit.id}&serie=${q.grade_level_id}`, color: 'linear-gradient(90deg,#F28C38,#D94C4C)' }))} />
            ) : <p className="text-sm text-muted">Sem fila para esta unidade.</p>}
          </Card>
        </Section>
      </div>
      <Exports unit />
    </div>
  );
}

function toCsv(columns: string[], rows: unknown[][]) {
  const esc = (v: unknown) => {
    const s = v == null ? '' : typeof v === 'number' ? String(v).replace('.', ',') : String(v);
    return /[;"\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return '﻿' + [columns, ...rows].map((r) => r.map(esc).join(';')).join('\r\n');
}

function Exports({ unit }: { unit?: boolean }) {
  const toast = useToast();
  const [busy, setBusy] = useState<string | null>(null);
  const download = async (key: string) => {
    setBusy(key);
    try {
      const r = await rpc<{ title: string; columns: string[]; rows: unknown[][]; generated_at: string; notice: string }>('report', { key });
      const blob = new Blob([toCsv(r.columns, r.rows)], { type: 'text/csv;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `iara-educa_${key}_${new Date().toISOString().slice(0, 10)}.csv`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 2000);
      toast({ title: `${r.title}: ${r.rows.length} linha(s)`, description: r.notice, tone: 'success' });
    } catch (e) {
      toast({ title: 'Exportação não realizada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(null);
    }
  };
  return (
    <Section title="Exportar dados" subtitle="CSV compatível com planilhas (separador “;”). Toda exportação fica registrada na auditoria.">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {REPORTS.filter((r) => !(unit && r.network)).map((r) => (
          <Card key={r.key} className="flex flex-col p-4">
            <div className="flex items-start gap-3">
              <span className="inline-flex size-10 shrink-0 items-center justify-center rounded-2xl bg-green-100 text-green-800"><FileSpreadsheet className="size-5" /></span>
              <div className="min-w-0"><div className="font-semibold">{r.title}</div><div className="text-[12.5px] text-muted">{r.desc}</div></div>
            </div>
            <Button className="mt-3" variant="secondary" size="sm" icon={Download} loading={busy === r.key} onClick={() => download(r.key)}>Baixar CSV</Button>
          </Card>
        ))}
      </div>
    </Section>
  );
}
