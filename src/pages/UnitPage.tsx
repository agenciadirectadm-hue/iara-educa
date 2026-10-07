import { useMemo, useState, type ReactNode } from 'react';
import { Link, useParams, useSearchParams } from 'react-router';
import clsx from 'clsx';
import {
  AlertTriangle, ArrowRight, Bus, ChevronRight, ClipboardList, Database, ExternalLink, GraduationCap, HardHat, History, LayoutGrid, ListOrdered, MapPin,
  Phone, School, Search, ShieldCheck, Sparkles, UserRound, Users,
} from 'lucide-react';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { useUnitsMap } from '@/lib/data';
import { fmtInt, fmtKm, fmtPct, timeAgo } from '@/lib/format';
import { AUDIT_ACTION, CASE_STATUS, ENTITY, FLAG, QUEUE_CATEGORY, SHIFT } from '@/lib/labels';
import {
  Avatar, Badge, Card, DataPair, EmptyState, ErrorState, Kpi, ListRow, OccupancyBar, PageHeader, Section, SeloVagasTurma, SkeletonList, SourceChip, Tabs, inputCls,
} from '@/components/ui';
import { Crumbs } from '@/components/Crumbs';
import MapView from '@/components/map/MapView';

type Tab = 'geral' | 'turmas' | 'alunos' | 'fila' | 'equipe' | 'atendimentos' | 'fontes' | 'historico';

export default function UnitPage() {
  const { id } = useParams();
  const unitId = Number(id);
  const [sp, setSp] = useSearchParams();
  const { me, can } = useSession();
  const detail = useRpc<any>('unit_detail', { id: unitId });
  const tab = (sp.get('aba') as Tab) ?? 'geral';
  const setTab = (t: Tab) => {
    const n = new URLSearchParams(sp);
    n.set('aba', t);
    n.delete('etapa');
    n.delete('serie');
    setSp(n, { replace: true });
  };

  if (detail.isLoading) return <SkeletonList rows={5} />;
  if (detail.error) return <ErrorState error={detail.error} onRetry={() => detail.refetch()} />;
  const d = detail.data;
  const u = d.unit;
  const authed = !!me;
  const inScope = me?.scope === 'NETWORK' || me?.scope === 'AGGREGATE' || (me?.scope === 'UNIT' && me.unit?.id === unitId);
  const tabs: { value: Tab; label: string; count?: number | null }[] = [
    { value: 'geral', label: 'Visão geral' },
    { value: 'turmas', label: 'Turmas', count: d.ops.classes },
    ...(authed && can('students.read') && inScope ? [{ value: 'alunos' as Tab, label: 'Alunos', count: d.ops.enrolled }] : []),
    ...(authed && can('queue.read') && inScope ? [{ value: 'fila' as Tab, label: 'Fila', count: d.ops.queue }] : []),
    ...(authed && can('classes.read') && inScope ? [{ value: 'equipe' as Tab, label: 'Equipe' }] : []),
    ...(authed && can('cases.read') && inScope ? [{ value: 'atendimentos' as Tab, label: 'Atendimentos' }] : []),
    { value: 'fontes', label: 'Dados e fontes' },
    ...(authed && can('audit.read') && inScope ? [{ value: 'historico' as Tab, label: 'Histórico' }] : []),
  ];

  return (
    <div>
      <Crumbs items={[{ label: 'Mapa', to: '/mapa' }, ...(u.territory ? [{ label: u.territory.name, to: `/territorios/${u.territory.id}` }] : []), { label: u.short_name }]} />
      <PageHeader
        eyebrow={u.type_label}
        title={u.name}
        subtitle={<span className="inline-flex flex-wrap items-center gap-x-2"><MapPin className="size-4" />{u.address} · {u.neighborhood} · CEP {u.postal_code ?? '—'}</span>}
      />
      <div className="mb-4 flex flex-wrap gap-1.5">
        <Badge tone={u.status === 'ATIVA' ? 'green' : 'gray'} dot>{u.status_label}</Badge>
        {u.inep ? <Badge tone="blue">INEP {u.inep}</Badge> : <Badge tone="amber" icon={AlertTriangle}>Sem código INEP</Badge>}
        {u.has_aee && <Badge tone="purple">AEE</Badge>}
        {u.geo.precision !== 'VALIDADO' && <Badge tone="amber">Coordenada {u.geo.precision.toLowerCase()}</Badge>}
      </div>
      <Tabs value={tab} onChange={setTab} items={tabs} />
      <div className="mt-4">
        {tab === 'geral' && <Overview d={d} />}
        {tab === 'turmas' && <ClassesTab d={d} unitId={unitId} />}
        {tab === 'alunos' && <StudentsTab unitId={unitId} />}
        {tab === 'fila' && <QueueTab unitId={unitId} />}
        {tab === 'equipe' && <StaffTab unitId={unitId} census={u.census.teachers} />}
        {tab === 'atendimentos' && <CasesTab unitId={unitId} />}
        {tab === 'fontes' && <SourcesTab d={d} />}
        {tab === 'historico' && <HistoryTab unitId={unitId} />}
      </div>
    </div>
  );
}

function Overview({ d }: { d: any }) {
  const u = d.unit;
  const o = d.ops;
  const units = useUnitsMap();
  return (
    <div>
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi compact icon={Users} tone="teal" label="Matrículas" value={fmtInt(u.public.enrollments)} sub={`ref. ${u.public.reference}`} source="oficial" sourceDetail={u.public.source} />
        <Kpi compact icon={GraduationCap} tone="purple" label="Turmas" value={fmtInt(u.public.classes)} sub={`Censo 2025: ${fmtInt(u.census.classes)}`} source="oficial" />
        <Kpi compact icon={Sparkles} tone="green" label="Vagas ofertáveis" value={fmtInt(o.offerable)} sub={`ocupação ${fmtPct(o.occupancy)}`} source="demo" />
        <Kpi compact icon={ListOrdered} tone="red" label="Fila" value={fmtInt(o.queue)} sub="crianças aguardando" source="demo" />
      </div>
      <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-[1.2fr_1fr]">
        <Card className="overflow-hidden">
          <MapView
            className="h-64"
            units={units.data?.units ?? []}
            selectedId={u.id}
            selectedLabel="Esta unidade"
            focus={{ lat: u.lat, lng: u.lng, zoom: 15 }}
            cooperative
            controls={false}
            onSelectUnit={(x) => (window.location.hash = `#/unidades/${x.id}`)}
          />
          <div className="flex items-center justify-between gap-2 p-3 text-[13px]">
            <span className="text-muted">{u.geo.status}</span>
            <a className="inline-flex items-center gap-1 font-semibold text-purple-700" href={`https://www.openstreetmap.org/directions?to=${u.lat}%2C${u.lng}`} target="_blank" rel="noreferrer">Como chegar <ExternalLink className="size-3.5" /></a>
          </div>
        </Card>
        <Card className="p-4">
          <dl className="grid grid-cols-2 gap-4">
            <DataPair label="Direção" value={u.director ?? 'Não confirmada'} />
            <DataPair label="Telefone" value={u.phone ?? <span className="text-muted">Pendente SEDUC</span>} />
            <DataPair label="Etapas" value={u.stages} />
            <DataPair label="Território" value={u.territory?.name} />
            <DataPair label="Docentes (Censo 2025)" value={fmtInt(u.census.teachers)} />
            <DataPair label="Educação especial" value={`${fmtInt(u.census.special_ed)} matrículas`} />
          </dl>
          {u.director_status && <p className="mt-3 text-[12px] text-muted">{u.director_status}</p>}
        </Card>
      </div>

      <Section title="Oferta por série/faixa" subtitle="Turmas e matrículas reais do Censo 2025 × camada operacional" action={<SourceChip kind="oficial" detail="Microdados do Censo Escolar 2025 (Tabela_Turma + Tabela_Matricula)." />}>
        <Card className="overflow-hidden">
          <div className="divide-y divide-line">
            {(d.grades_census as any[]).filter((g) => g.grade_level_id).map((g) => {
              const op = (d.ops_by_grade as any[]).find((x) => x.grade_level_id === g.grade_level_id);
              return (
                <Link key={g.grade} to={`?aba=turmas&serie=${g.grade_level_id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-blue-50/60">
                  <div className="min-w-0 flex-1">
                    <div className="font-semibold">{g.grade}</div>
                    <div className="text-[12.5px] text-muted">{g.classes} turmas · {g.enrollments} matrículas · média {g.avg} por turma (Censo)</div>
                  </div>
                  {op && <Badge tone={op.offerable > 0 ? 'green' : 'gray'}>{op.offerable} vaga(s)</Badge>}
                  {op && op.queue > 0 && <Badge tone="red">{op.queue} fila</Badge>}
                  <ChevronRight className="size-5 text-subtle" />
                </Link>
              );
            })}
            {(d.grades_census as any[]).filter((g) => !g.grade_level_id).map((g) => (
              <div key={g.grade} className="flex items-center gap-3 bg-slate-50/60 px-4 py-3 text-[13px]">
                <div className="flex-1"><b>{g.stage}</b> — {g.grade}: {g.enrollments} matrículas em {g.classes} turmas (agregado)</div>
              </div>
            ))}
            {!d.grades_census.length && <p className="p-4 text-sm text-muted">Unidade sem microdado no Censo 2025 — quantitativos por série pendentes SEDUC.</p>}
          </div>
        </Card>
      </Section>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title="Turnos por etapa" action={<SourceChip kind="oficial" detail="Turno agregado por etapa (não separa cada série)." />}>
          <Card className="divide-y divide-line">
            {(d.shifts_census as any[]).map((s, i) => (
              <div key={i} className="flex items-center justify-between px-4 py-2.5 text-[14px]">
                <span>{s.stage}</span>
                <span className="font-semibold">{s.shift} · {s.classes} turma(s) · {s.enrollments}</span>
              </div>
            ))}
            {!d.shifts_census.length && <p className="p-4 text-sm text-muted">Pendente SEDUC.</p>}
          </Card>
        </Section>
        <Section title="Oferta publicada" action={<SourceChip kind="publico" />}>
          <Card className="divide-y divide-line">
            {(d.offers as any[]).map((o, i) => (
              <div key={i} className="px-4 py-2.5">
                <div className="flex items-center justify-between text-[14px]"><b>{o.name}</b><span>{o.classes ?? '—'} turmas · {o.enrollments ?? '—'} matr.</span></div>
                <div className="text-[12px] text-muted">{o.source} · {o.reference}</div>
              </div>
            ))}
          </Card>
        </Section>
      </div>

      {(d.quality as any[]).length > 0 && (
        <Section title="Pendências de dados desta unidade">
          <Card className="divide-y divide-line">
            {(d.quality as any[]).map((q) => (
              <div key={q.id} className="flex items-start gap-3 px-4 py-3">
                <AlertTriangle className={clsx('mt-0.5 size-5', q.severity === 'ALTA' ? 'text-red-600' : 'text-amber-600')} />
                <div><div className="font-semibold">{q.title}</div><div className="text-[13px] text-muted">{q.description}</div><div className="mt-1 text-[12px] font-semibold text-purple-800">Ação: {q.action}</div></div>
              </div>
            ))}
          </Card>
        </Section>
      )}

      <Section title="Unidades mais próximas">
        <div className="no-scrollbar -mx-4 flex gap-3 overflow-x-auto px-4 pb-1">
          {(d.nearby as any[]).map((n) => (
            <Link key={n.id} to={`/unidades/${n.id}`} className="w-48 shrink-0 rounded-3xl bg-white p-3 shadow-soft ring-1 ring-line/70">
              <School className={clsx('size-5', n.type === 'CMEI' ? 'text-purple-600' : 'text-blue-600')} />
              <div className="mt-1 line-clamp-2 text-[14px] font-semibold">{n.name}</div>
              <div className="text-[12px] text-muted">{fmtKm(n.distance_m)}</div>
            </Link>
          ))}
        </div>
      </Section>
      <Section title="Infraestrutura e transporte">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <Card className="flex items-start gap-3 p-4"><HardHat className="size-5 text-slate-500" /><div className="text-[13.5px]"><b>Salas, obras e acessibilidade</b><p className="text-muted">Módulo de infraestrutura pendente de integração — sem dados públicos confiáveis. {u.public.capacity ? `Capacidade estrutural divulgada: ${u.public.capacity} alunos.` : ''}</p></div></Card>
          <Card className="flex items-start gap-3 p-4"><Bus className="size-5 text-slate-500" /><div className="text-[13.5px]"><b>Transporte escolar</b><p className="text-muted">Rotas e pontos entram com o módulo de transporte (fase futura). Pedidos de transporte já viram protocolos.</p></div></Card>
        </div>
      </Section>
    </div>
  );
}

function ClassesTab({ d, unitId }: { d: any; unitId: number }) {
  const [sp, setSp] = useSearchParams();
  const serie = sp.get('serie') ? Number(sp.get('serie')) : null;
  const classes = useRpc<any>('unit_classes', { unit_id: unitId }, { retry: false });
  const byGrade = d.ops_by_grade as any[];
  const stages = useMemo(() => {
    const m = new Map<number, { name: string; grades: any[] }>();
    for (const g of byGrade) {
      const name = g.stage_id === 1 ? 'Educação Infantil' : g.stage_id === 2 ? 'Ensino Fundamental — Anos Iniciais' : 'EJA';
      if (!m.has(g.stage_id)) m.set(g.stage_id, { name, grades: [] });
      m.get(g.stage_id)!.grades.push(g);
    }
    return [...m.entries()];
  }, [byGrade]);
  const go = (s: number | null) => {
    const n = new URLSearchParams(sp);
    if (s == null) n.delete('serie');
    else n.set('serie', String(s));
    setSp(n, { replace: false });
  };
  if (!byGrade.length) return <Card><EmptyState compact title="Turmas pendentes SEDUC" body="Esta unidade não tem microdado de turmas no Censo 2025 nem turmas operacionais importadas." /></Card>;
  const grade = byGrade.find((g) => g.grade_level_id === serie);
  const items = ((classes.data?.items ?? []) as any[]).filter((c) => !serie || c.grade_level_id === serie);
  return (
    <div>
      <div className="mb-3 flex items-center gap-2 text-[13px]">
        <button onClick={() => go(null)} className={clsx('rounded-full px-3 py-1 font-semibold', !serie ? 'bg-blue-900 text-white' : 'bg-white ring-1 ring-line')}>Todas as etapas</button>
        {grade && <><ChevronRight className="size-4 text-subtle" /><span className="rounded-full bg-purple-100 px-3 py-1 font-bold text-purple-800">{grade.grade}</span></>}
      </div>
      {!serie && (
        <div className="space-y-4">
          {stages.map(([sid, st]) => (
            <Card key={sid} className="p-4">
              <div className="mb-3 flex items-center justify-between">
                <h3 className="font-display text-[17px] font-extrabold">{st.name}</h3>
                <SourceChip kind="demo" />
              </div>
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                {st.grades.map((g) => (
                  <button key={g.grade_level_id} onClick={() => go(g.grade_level_id)} className="rounded-2xl bg-slate-50 p-3 text-left ring-1 ring-line transition hover:bg-purple-50 hover:ring-purple-200">
                    <div className="mb-1.5 flex items-center justify-between">
                      <span className="font-semibold">{g.grade}</span>
                      <span className="text-[12.5px] text-muted">{g.classes} turma(s) · {(g.shifts ?? []).map((s: string) => SHIFT[s]).join('/')}</span>
                    </div>
                    <OccupancyBar capacity={g.capacity} enrolled={g.enrolled} reserved={g.reserved} blocked={g.blocked} offerable={g.offerable} />
                    <div className="mt-1.5 flex justify-between text-[12px]"><span className="text-muted">{g.enrolled}/{g.capacity} ocupadas</span><span className={g.offerable > 0 ? 'font-bold text-green-700' : 'text-muted'}>{g.offerable} vaga(s) · fila {g.queue}</span></div>
                  </button>
                ))}
              </div>
            </Card>
          ))}
        </div>
      )}
      {serie && (
        classes.isLoading ? <SkeletonList rows={3} /> : classes.error ? (
          <Card className="p-4 text-sm text-muted">
            <p><b>{grade?.classes} turma(s)</b> · capacidade {grade?.capacity} · {grade?.enrolled} matrículas · {grade?.offerable} vaga(s) ofertável(is).</p>
            <p className="mt-1">O detalhe por turma é restrito a perfis da rede ou desta unidade.</p>
          </Card>
        ) : (
          <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
            {items.map((c) => (
              <Link key={c.id} to={`/turmas/${c.id}`} className="group rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 transition hover:shadow-lift">
                <div className="flex items-start justify-between gap-2">
                  <div>
                    <div className="font-display text-lg font-extrabold group-hover:text-purple-700">{c.name}</div>
                    <div className="text-[12.5px] text-muted">{SHIFT[c.shift]} · {c.room} · {c.teacher ?? 'regente a definir'}</div>
                  </div>
                  <SeloVagasTurma capacity={c.capacity} enrolled={c.enrolled} offerable={c.offerable} />
                </div>
                <div className="mt-3"><OccupancyBar capacity={c.capacity} enrolled={c.enrolled} reserved={c.reserved} blocked={c.blocked} offerable={c.offerable} showLegend /></div>
                <div className="mt-2 flex items-center justify-between text-[12.5px] text-muted">
                  <span>Capacidade {c.capacity} · fila da série {c.queue}</span>
                  <span className="inline-flex items-center gap-0.5 font-semibold text-purple-700">Abrir turma <ArrowRight className="size-3.5" /></span>
                </div>
              </Link>
            ))}
          </div>
        )
      )}
    </div>
  );
}

function StudentsTab({ unitId }: { unitId: number }) {
  const [q, setQ] = useState('');
  const dq = useDebounced(q, 250);
  const res = useRpc<any>('unit_students', { unit_id: unitId, q: dq || null });
  return (
    <div>
      <div className="relative">
        <Search className="pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-subtle" />
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar aluno pelo nome" className={clsx(inputCls, 'pl-11')} aria-label="Buscar aluno" />
      </div>
      <p className="mt-2 flex items-center gap-2 text-[12.5px] text-muted"><ShieldCheck className="size-4 text-green-700" />Lista filtrada pelo servidor conforme seu perfil e escopo. <SourceChip kind="demo" detail="Nomes fictícios." /></p>
      <div className="mt-3">
        {res.isLoading ? <SkeletonList rows={5} /> : res.error ? <ErrorState error={res.error} /> : (
          <Card className="divide-y divide-line overflow-hidden">
            {(res.data.items as any[]).map((s) => (
              <ListRow key={s.id} to={`/alunos/${s.id}`} leading={<Avatar name={s.name} seed={s.avatar_seed} />} title={s.name}
                subtitle={`${s.age} · ${s.class} · ${SHIFT[s.shift]}`}
                meta={<span className="flex gap-1">{s.aee && <Badge tone="purple">AEE</Badge>}{s.transport && <Badge tone="blue">Transporte</Badge>}</span>} />
            ))}
            {!res.data.items.length && <p className="p-4 text-sm text-muted">Nenhum aluno encontrado.</p>}
          </Card>
        )}
        {res.data && res.data.total > res.data.items.length && <p className="mt-2 text-center text-[12px] text-muted">Mostrando {res.data.items.length} de {res.data.total}. Refine pela busca.</p>}
      </div>
    </div>
  );
}

function QueueTab({ unitId }: { unitId: number }) {
  const res = useRpc<any>('queue_list', { unit_id: unitId, page_size: 80 });
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} />;
  const items = res.data.items as any[];
  return (
    <Card className="divide-y divide-line overflow-hidden">
      {items.map((w) => (
        <ListRow key={w.id} to={`/fila/${w.id}`}
          leading={<span className="inline-flex size-10 items-center justify-center rounded-2xl bg-purple-100 font-display font-black text-purple-800">{w.position}º</span>}
          title={w.student} subtitle={`${w.grade} · ${w.days_waiting} dias aguardando · ${QUEUE_CATEGORY[w.category]?.short}`}
          meta={<span className="flex flex-wrap justify-end gap-1">{(w.flags ?? []).slice(0, 2).map((f: string) => <Badge key={f} tone="purple">{FLAG[f]?.short}</Badge>)}</span>} />
      ))}
      {!items.length && <EmptyState compact title="Sem fila nesta unidade" />}
    </Card>
  );
}

function StaffTab({ unitId, census }: { unitId: number; census: number | null }) {
  const res = useRpc<any>('unit_staff', { unit_id: unitId });
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} />;
  const items = res.data.items as any[];
  return (
    <div>
      <p className="mb-3 text-[13px] text-muted">{items.length} profissionais · Censo 2025: {fmtInt(census)} docentes nesta unidade. <SourceChip kind="demo" detail={res.data.source} /></p>
      <Card className="divide-y divide-line overflow-hidden">
        {items.map((s) => (
          <div key={s.id} className="flex items-center gap-3 px-4 py-3">
            <Avatar name={s.name} seed={s.name} size={38} />
            <div className="min-w-0 flex-1">
              <div className="truncate font-semibold">{s.name}</div>
              <div className="truncate text-[12.5px] text-muted">{s.role.toLowerCase()} · {s.bond} · {(s.classes as any[]).map((c) => c.name).join(', ') || 'sem turma (apoio/AEE)'}</div>
            </div>
          </div>
        ))}
      </Card>
    </div>
  );
}

function CasesTab({ unitId }: { unitId: number }) {
  const res = useRpc<any>('cases_list', { unit_id: unitId, page_size: 30 });
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} />;
  return (
    <div>
      <Card className="divide-y divide-line overflow-hidden">
        {(res.data.items as any[]).map((c) => (
          <ListRow key={c.id} to={`/atendimentos/${c.id}`} leading={<ClipboardList className="size-5 text-blue-700" />} title={c.subject}
            subtitle={`${c.protocol} · ${c.type_name} · ${timeAgo(c.opened_at)}`}
            meta={<Badge tone={CASE_STATUS[c.status]?.tone}>{CASE_STATUS[c.status]?.label}</Badge>} />
        ))}
        {!res.data.items.length && <EmptyState compact title="Nenhum atendimento aberto" />}
      </Card>
      <Link to={`/atendimentos?unidade=${unitId}`} className="mt-3 block text-center text-sm font-semibold text-purple-700">Abrir na central de atendimentos</Link>
    </div>
  );
}

function SourcesTab({ d }: { d: any }) {
  const u = d.unit;
  const rows: [string, ReactNode, ReactNode][] = [
    ['Endereço', u.address_meta.confidence, u.address_meta.source],
    ['Coordenada', `${u.geo.precision} — ${u.geo.status}`, u.geo.note],
    ['CEP', u.postal_code, u.address_meta.cep_source],
    ['Direção', u.director_status, u.director_source],
    ['Matrículas/turmas', u.public.status, u.public.source],
    ['Censo 2025', u.census.status, 'Microdados do Censo Escolar 2025 / INEP'],
    ['Confirmação SEDUC', u.seduc_confirmation, 'Turma a turma: pendente de integração'],
  ];
  return (
    <div className="space-y-3">
      {rows.map(([k, v, src]) => (
        <Card key={k} className="p-4">
          <div className="flex items-center gap-2 text-[12px] font-bold uppercase tracking-wide text-subtle"><Database className="size-4" />{k}</div>
          <div className="mt-1 text-[14.5px] font-semibold">{v ?? '—'}</div>
          {typeof src === 'string' && src.startsWith('http') ? (
            <a href={src} target="_blank" rel="noreferrer" className="mt-1 inline-flex items-center gap-1 break-all text-[12.5px] text-purple-700 underline">{src.slice(0, 90)}… <ExternalLink className="size-3" /></a>
          ) : <div className="mt-1 text-[12.5px] text-muted">{src ?? '—'}</div>}
        </Card>
      ))}
      <p className="text-[12.5px] text-muted"><Phone className="mr-1 inline size-3.5" />Campos ausentes aparecem como “pendente SEDUC” — nada foi inventado. <UserRound className="mx-1 inline size-3.5" />Nomes de direção vêm de publicação oficial de nomeação.</p>
    </div>
  );
}

function HistoryTab({ unitId }: { unitId: number }) {
  const res = useRpc<any>('audit_list', { unit_id: unitId });
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} />;
  return (
    <Card className="divide-y divide-line overflow-hidden">
      {(res.data.items as any[]).map((a) => (
        <div key={a.id} className="flex items-start gap-3 px-4 py-3">
          <History className="mt-0.5 size-5 text-purple-700" />
          <div className="min-w-0 flex-1">
            <div className="text-[14px] font-semibold">{AUDIT_ACTION[a.action] ?? a.action} · {ENTITY[a.entity_type] ?? a.entity_type}</div>
            <div className="text-[12.5px] text-muted">{a.summary ?? ''} {a.actor} · {timeAgo(a.at)}</div>
          </div>
        </div>
      ))}
      {!res.data.items.length && <EmptyState compact title="Sem eventos auditados para esta unidade ainda" />}
      <Link to={`/auditoria?unidade=${unitId}`} className="flex items-center justify-center gap-1 p-3 text-sm font-semibold text-purple-700"><LayoutGrid className="size-4" />Trilha completa</Link>
    </Card>
  );
}
