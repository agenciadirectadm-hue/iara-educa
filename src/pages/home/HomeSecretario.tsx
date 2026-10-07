import { useState } from 'react';
import { Link, useNavigate } from 'react-router';
import { AlertTriangle, Building2, ChevronRight, ClipboardList, Database, FileCheck, GraduationCap, ListOrdered, Plus, Sparkles, Users } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtInt, fmtPct } from '@/lib/format';
import { QUEUE_CATEGORY } from '@/lib/labels';
import { Badge, Card, ErrorState, Kpi, PageHeader, Section, Segmented, SkeletonList, SourceChip } from '@/components/ui';
import { BarList, Donut, Funnel, GroupedBars } from '@/components/charts';
import { RotinaApresentacao } from '@/components/RotinaApresentacao';

const CAT_COLOR: Record<string, string> = {
  SEM_ATENDIMENTO: '#D94C4C', AGUARDA_TRANSFERENCIA: '#2A7DE1', PARCIAL_PARA_INTEGRAL: '#14B8A6', UNIDADE_PREFERENCIAL: '#A846E8', RECUSOU_OFERTA: '#F2B640', DEMANDA_FUTURA: '#94A3B8',
};
const TEAM: Record<string, string> = { CENTRAL_VAGAS: 'Central de Vagas', SECRETARIA_ESCOLAR: 'Secretarias escolares', TRANSPORTE: 'Transporte', OUVIDORIA: 'Ouvidoria', AEE: 'AEE / inclusão', ATENDIMENTO: 'Atendimento' };

export default function HomeSecretario() {
  const { me } = useSession();
  const [stage, setStage] = useState<string>(me?.stage_filter ?? '');
  const dash = useRpc<any>('dashboard_secretario', { stage: stage || null });
  const navigate = useNavigate();

  const title = me?.role === 'SUPERINTENDENCIA' ? 'Metas e prazos estão sendo cumpridos?' : me?.role === 'GERENCIA_EI' ? 'Como está a demanda por creche e pré-escola?' : 'Onde está o gargalo?';
  return (
    <div>
      <PageHeader
        eyebrow={`${me?.role_name ?? 'Secretaria'} · rede municipal`}
        title={title}
        subtitle="Demanda × oferta por série, território e unidade — com sugestões de abertura de turmas e o andamento dos atendimentos."
        actions={
          <Segmented
            value={stage}
            onChange={setStage}
            items={[{ value: '', label: 'Toda a rede' }, { value: 'EI', label: 'Infantil' }, { value: 'EF', label: 'Fundamental' }, { value: 'EJA', label: 'EJA' }]}
          />
        }
      />
      {dash.isLoading ? <SkeletonList rows={6} /> : dash.error ? <ErrorState error={dash.error} onRetry={() => dash.refetch()} /> : <Body d={dash.data} stage={stage} navigate={navigate} />}
      <RotinaApresentacao />
    </div>
  );
}

function Body({ d, stage, navigate }: { d: any; stage: string; navigate: (to: string) => void }) {
  const k = d.kpis;
  const cats = Object.entries(d.by_category ?? {}).map(([key, value]) => ({ key, label: QUEUE_CATEGORY[key]?.label ?? key, value: value as number, color: CAT_COLOR[key] ?? '#94A3B8' }));
  const casesByTeam = Object.entries(d.cases?.by_team ?? {}).map(([key, v]: [string, any]) => ({ key, label: TEAM[key] ?? key, value: v.open, overdue: v.overdue }));
  const f = d.offers_funnel;
  return (
    <>
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi icon={Building2} tone="blue" label="Unidades" value={fmtInt(k.official.units)} sub={`${fmtInt(k.official.enrollments)} matrículas (oficial)`} source="oficial" to="/unidades" />
        <Kpi icon={Sparkles} tone="green" label="Vagas ofertáveis" value={fmtInt(k.operational.offerable)} sub={`${fmtInt(k.operational.blocked)} bloqueadas · ${fmtInt(k.operational.reserved)} reservadas`} source="demo" to="/vagas" />
        <Kpi icon={ListOrdered} tone="red" label="Fila de espera" value={fmtInt(k.operational.waiting)} sub={`${fmtInt(k.operational.waiting_no_service)} sem nenhum atendimento`} source="demo" to="/fila" />
        <Kpi icon={ClipboardList} tone="amber" label="Protocolos abertos" value={fmtInt(k.operational.open_cases)} sub={`${fmtInt(k.operational.overdue_cases)} com prazo vencido`} source="demo" to="/atendimentos" />
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1.4fr_1fr]">
        <Section title="Demanda × oferta por série/faixa" subtitle="Toque numa série para abrir a fila filtrada" action={<SourceChip kind="demo" />}>
          <Card className="p-4">
            <GroupedBars
              data={(d.by_grade ?? []).map((g: any) => ({ key: String(g.grade_level_id), label: g.grade, queue: g.queue, offerable: g.offerable, to: `/fila?serie=${g.grade_level_id}` }))}
              series={[{ key: 'queue', label: 'Crianças na fila', color: '#D94C4C' }, { key: 'offerable', label: 'Vagas ofertáveis', color: '#16A36A' }]}
            />
          </Card>
        </Section>
        <Section title="Quem está na fila" subtitle="Não confundir: sem atendimento ≠ transferência ≠ integral" action={<SourceChip kind="demo" />}>
          <Card className="p-4">
            <Donut segments={cats} onSelect={(key) => navigate(`/fila?categoria=${key}`)} center={<><b className="font-display text-2xl tabular">{fmtInt(k.operational.waiting)}</b><span className="text-[11px] text-muted">na fila</span></>} />
          </Card>
        </Section>
      </div>

      <Section title="Abrir turmas onde a fila não anda" subtitle="Fila ≥ 12 crianças e nenhuma vaga ofertável — cenário para decisão" action={<SourceChip kind="projetado" detail="Turmas sugeridas = fila ÷ capacidade de referência da série. Profissionais = 1 regente por turma (+1 auxiliar na creche)." />}>
        {d.open_class_suggestions.length ? (
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {d.open_class_suggestions.map((s: any) => (
              <Link key={`${s.unit_id}-${s.grade_level_id}`} to={`/unidades/${s.unit_id}?aba=turmas`} className="group rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 transition hover:shadow-lift">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="truncate font-semibold">{s.unit}</div>
                    <div className="text-[12.5px] text-muted">{s.territory} · {s.grade}</div>
                  </div>
                  <Badge tone="red">{s.queue} na fila</Badge>
                </div>
                <div className="mt-3 flex items-center gap-3 rounded-2xl bg-purple-50 p-3">
                  <Plus className="size-5 text-purple-700" />
                  <div className="text-[13.5px]">
                    <b className="text-purple-900">{s.suggested_classes} turma(s)</b> de {s.grade.toLowerCase()} · <b>{s.staff_needed}</b> profissional(is)
                  </div>
                </div>
              </Link>
            ))}
          </div>
        ) : (
          <Card className="p-4 text-sm text-muted">Nenhuma unidade com fila travada neste recorte.</Card>
        )}
      </Section>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title="Unidades saturadas" subtitle="Ocupação ≥ 97%">
          <Card className="p-3">
            <BarList
              items={d.saturated.map((u: any) => ({ key: String(u.id), label: u.name, value: u.occupancy, to: `/unidades/${u.id}`, color: 'linear-gradient(90deg,#F2B640,#D94C4C)', sub: `${u.territory} · fila ${u.queue} · ${u.offerable} vaga(s)` }))}
              max={110}
              format={(n) => fmtPct(n)}
            />
          </Card>
        </Section>
        <Section title="Capacidade ociosa" subtitle="Onde há vagas para remanejar">
          <Card className="p-3">
            <BarList
              items={d.idle.map((u: any) => ({ key: String(u.id), label: u.name, value: u.offerable, to: `/unidades/${u.id}`, color: 'linear-gradient(90deg,#7FB7EA,#086DB6)', sub: `${u.territory} · ocupação ${fmtPct(u.occupancy)} · fila ${u.queue}` }))}
              valueSuffix=" vagas"
            />
          </Card>
        </Section>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title="Atendimentos por equipe" subtitle="Abertos e com prazo vencido" action={<SourceChip kind="demo" />}>
          <Card className="p-3">
            <BarList
              items={casesByTeam.sort((a, b) => b.value - a.value).map((t) => ({
                key: t.key, label: t.label, value: t.value, to: `/atendimentos`, color: 'linear-gradient(90deg,#1594D2,#064B86)',
                badge: t.overdue ? <Badge tone="red" icon={AlertTriangle}>{t.overdue} vencidos</Badge> : undefined,
              }))}
            />
          </Card>
        </Section>
        <Section title="Funil de ofertas" subtitle={`Últimos ${f.window_days} dias`} action={<SourceChip kind="demo" />}>
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
      </div>

      <div className="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-3">
        <Link to="/qualidade" className="flex items-center gap-3 rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 hover:shadow-lift">
          <span className="inline-flex size-11 items-center justify-center rounded-2xl bg-slate-100 text-slate-700"><Database className="size-5" /></span>
          <div className="flex-1"><div className="font-semibold">Qualidade dos dados</div><div className="text-[12.5px] text-muted">{d.quality.open} pendências · {d.quality.high} de prioridade alta</div></div>
          <ChevronRight className="size-5 text-subtle" />
        </Link>
        <Link to="/ofertas" className="flex items-center gap-3 rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 hover:shadow-lift">
          <span className="inline-flex size-11 items-center justify-center rounded-2xl bg-green-100 text-green-800"><FileCheck className="size-5" /></span>
          <div className="flex-1"><div className="font-semibold">Ofertas em andamento</div><div className="text-[12.5px] text-muted">{k.operational.offers_pending} aguardando · {k.operational.offers_accepted} aceitas</div></div>
          <ChevronRight className="size-5 text-subtle" />
        </Link>
        <Link to="/auditoria" className="flex items-center gap-3 rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 hover:shadow-lift">
          <span className="inline-flex size-11 items-center justify-center rounded-2xl bg-purple-100 text-purple-800"><Users className="size-5" /></span>
          <div className="flex-1"><div className="font-semibold">Auditoria executiva</div><div className="text-[12.5px] text-muted">Quem fez o quê, quando</div></div>
          <ChevronRight className="size-5 text-subtle" />
        </Link>
      </div>
      {stage && <p className="mt-4 text-center text-[12px] text-muted"><GraduationCap className="mr-1 inline size-4" />Recorte: {stage === 'EI' ? 'Educação Infantil' : stage === 'EF' ? 'Ensino Fundamental' : 'EJA'}</p>}
    </>
  );
}
