import { Link } from 'react-router';
import clsx from 'clsx';
import {
  ArrowRightLeft, Ban, ChevronRight, ClipboardList, FilePen, FileText, GraduationCap, ListOrdered, MapPin, Phone, School, Search, Sparkles, UserPlus, Users,
} from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtInt, fmtPct, timeAgo } from '@/lib/format';
import { BLOCK_REASON, FLAG, SHIFT, VACANCY_EVENT } from '@/lib/labels';
import { Badge, Card, EmptyState, ErrorState, Kpi, LinkCard, OccupancyBar, PageHeader, Section, SkeletonList, SourceChip } from '@/components/ui';
import { EnrollmentCard } from '@/components/EnrollmentCard';

export default function HomeUnidade() {
  const { me } = useSession();
  const dash = useRpc<any>('dashboard_unidade', { unit_id: me?.unit?.id });
  const secretaria = me?.role === 'SECRETARIA_ESCOLAR';
  if (dash.isLoading) return <SkeletonList rows={6} />;
  if (dash.error) return <ErrorState error={dash.error} onRetry={() => dash.refetch()} />;
  const d = dash.data;
  const u = d.unit;
  const o = d.ops;
  const pending = d.pending_enrollments as any[];
  const grades = groupByGrade(d.classes);

  const shortcuts = [
    { icon: UserPlus, label: 'Nova matrícula', to: '/atendimentos/novo?tipo=MATRICULA' },
    { icon: ArrowRightLeft, label: 'Transferência', to: '/atendimentos/novo?tipo=TRANSFERENCIA' },
    { icon: FilePen, label: 'Atualização cadastral', to: '/atendimentos/novo?tipo=ATUALIZACAO_CADASTRAL' },
    { icon: FileText, label: 'Declaração', to: '/atendimentos/novo?tipo=DOCUMENTO' },
    { icon: Search, label: 'Consultar aluno', to: `/unidades/${u.id}?aba=alunos` },
    { icon: ClipboardList, label: 'Atendimentos', to: `/atendimentos?unidade=${u.id}` },
  ];

  return (
    <div>
      <PageHeader eyebrow={`${me?.role_name} · ${u.type === 'CMEI' ? 'CMEI' : 'Escola Municipal'}`} title={d.question} subtitle={u.name} />

      <LinkCard to={`/unidades/${u.id}`} className="overflow-hidden">
        <div className="relative bg-gradient-to-br from-purple-700 via-purple-800 to-blue-900 p-5 text-white">
          <div className="absolute -right-10 -top-10 size-44 rounded-full bg-white/10" aria-hidden />
          <div className="flex items-start gap-3">
            <span className="inline-flex size-12 items-center justify-center rounded-2xl bg-white/15"><School className="size-6" /></span>
            <div className="min-w-0">
              <div className="font-display text-xl font-extrabold leading-tight">{u.name}</div>
              <div className="mt-1 text-[13px] text-white/80"><MapPin className="mr-1 inline size-3.5" />{u.address} · {u.neighborhood}</div>
              {u.director && <div className="text-[13px] text-white/80">Direção: {u.director}</div>}
            </div>
          </div>
          <div className="mt-4 grid grid-cols-3 gap-2 text-center">
            <div className="rounded-2xl bg-white/12 p-2"><div className="font-display text-2xl font-black tabular">{fmtInt(o.enrolled)}</div><div className="text-[11px] text-white/80">matrículas</div></div>
            <div className="rounded-2xl bg-white/12 p-2"><div className="font-display text-2xl font-black tabular">{fmtInt(o.classes)}</div><div className="text-[11px] text-white/80">turmas</div></div>
            <div className="rounded-2xl bg-white/12 p-2"><div className="font-display text-2xl font-black tabular">{fmtPct(o.occupancy)}</div><div className="text-[11px] text-white/80">ocupação</div></div>
          </div>
        </div>
        <div className="flex items-center justify-between px-5 py-3 text-[13px] font-semibold text-purple-700">
          Ver unidade completa (turmas, alunos, equipe, histórico) <ChevronRight className="size-4" />
        </div>
      </LinkCard>

      {secretaria && (
        <Section title="Atalhos da secretaria">
          <div className="grid grid-cols-3 gap-2.5 sm:grid-cols-6">
            {shortcuts.map((s) => (
              <Link key={s.label} to={s.to} className="flex flex-col items-center gap-2 rounded-3xl bg-white p-3 text-center shadow-soft ring-1 ring-line/70 transition active:scale-95 hover:shadow-lift">
                <span className="inline-flex size-11 items-center justify-center rounded-2xl bg-blue-100 text-blue-800"><s.icon className="size-5" /></span>
                <span className="text-[12px] font-semibold leading-tight">{s.label}</span>
              </Link>
            ))}
          </div>
        </Section>
      )}

      <Section title="Matrículas para concluir" subtitle="Ofertas aceitas pelas famílias e documentos a validar" action={<SourceChip kind="demo" />}>
        {pending.length ? (
          <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">{pending.map((p) => <EnrollmentCard key={p.offer_id} item={p} />)}</div>
        ) : (
          <Card><EmptyState compact title="Nada pendente por aqui" body="Quando uma família aceitar uma vaga nesta unidade, a matrícula aparece aqui com a lista do que falta." /></Card>
        )}
      </Section>

      <div className="mt-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi compact icon={GraduationCap} tone="blue" label="Capacidade" value={fmtInt(o.capacity)} sub="autorizada (demo)" source="demo" to={`/unidades/${u.id}?aba=turmas`} />
        <Kpi compact icon={Sparkles} tone="green" label="Vagas ofertáveis" value={fmtInt(o.offerable)} sub={`${o.blocked} bloqueada(s) · ${o.reserved} reservada(s)`} source="calculado" to={`/unidades/${u.id}?aba=turmas`} />
        <Kpi compact icon={ListOrdered} tone="red" label="Fila local" value={fmtInt(o.queue)} sub="crianças aguardando" source="demo" to={`/fila?unidade=${u.id}`} />
        <Kpi compact icon={Users} tone="purple" label="Equipe" value={fmtInt(d.staff?.total)} sub={`Censo 2025: ${fmtInt(u.census_teachers)} docentes`} source="demo" to={`/unidades/${u.id}?aba=equipe`} />
      </div>

      <Section title="Turmas por série" subtitle="Toque numa turma para ver alunos, vagas e equipe">
        <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
          {grades.map(([grade, classes]) => (
            <Card key={grade} className="p-4">
              <div className="mb-2 flex items-center justify-between">
                <div className="font-display text-[17px] font-extrabold">{grade}</div>
                <Badge tone="gray">{classes.length} turma(s)</Badge>
              </div>
              <div className="space-y-2">
                {classes.map((c: any) => (
                  <Link key={c.id} to={`/turmas/${c.id}`} className="block rounded-2xl p-2 transition hover:bg-blue-50/70">
                    <div className="mb-1.5 flex items-center justify-between text-[13.5px]">
                      <span className="font-semibold">{c.name} <span className="font-normal text-muted">· {SHIFT[c.shift]}</span></span>
                      <span className={clsx('font-bold tabular', c.offerable > 0 ? 'text-green-700' : 'text-muted')}>{c.enrolled}/{c.capacity}{c.offerable > 0 ? ` · ${c.offerable} vaga(s)` : ''}</span>
                    </div>
                    <OccupancyBar capacity={c.capacity} enrolled={c.enrolled} reserved={c.reserved} blocked={c.blocked} offerable={c.offerable} />
                  </Link>
                ))}
              </div>
            </Card>
          ))}
        </div>
      </Section>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title="Fila local" subtitle="Primeiros de cada faixa (critérios aplicados)">
          <Card className="divide-y divide-line">
            {(d.queue as any[]).length ? (d.queue as any[]).map((q) => (
              <div key={q.grade} className="p-4">
                <div className="mb-2 flex items-center justify-between">
                  <span className="font-semibold">{q.grade}</span>
                  <Link to={`/fila?unidade=${u.id}&serie=${q.grade_level_id}`} className="text-[13px] font-semibold text-purple-700">{q.waiting} aguardando →</Link>
                </div>
                <ol className="space-y-1">
                  {(q.top ?? []).map((t: any) => (
                    <li key={t.entry_id}>
                      <Link to={`/fila/${t.entry_id}`} className="flex items-center gap-2 rounded-xl px-2 py-1.5 text-[13.5px] hover:bg-slate-50">
                        <span className="inline-flex size-6 items-center justify-center rounded-full bg-purple-100 text-[12px] font-bold text-purple-800">{t.position}</span>
                        <span className="min-w-0 flex-1 truncate">{t.student}</span>
                        <span className="flex gap-1">{(t.flags ?? []).slice(0, 2).map((f: string) => <Badge key={f} tone="purple">{FLAG[f]?.short ?? f}</Badge>)}</span>
                      </Link>
                    </li>
                  ))}
                </ol>
              </div>
            )) : <p className="p-4 text-sm text-muted">Sem crianças aguardando nesta unidade.</p>}
          </Card>
        </Section>
        <Section title="Movimentação de vagas" subtitle="Antes e depois de cada evento">
          <Card className="divide-y divide-line">
            {(d.events as any[]).map((e, i) => (
              <div key={i} className="flex items-center gap-3 px-4 py-3">
                <span className="inline-flex size-9 items-center justify-center rounded-xl bg-slate-100 text-[11px] font-bold text-slate-700">{e.quantity > 0 ? `±${e.quantity}` : '•'}</span>
                <div className="min-w-0 flex-1">
                  <div className="truncate text-[14px] font-semibold">{VACANCY_EVENT[e.type] ?? e.type} {e.class ? `· ${e.class}` : ''}</div>
                  <div className="truncate text-[12px] text-muted">{e.reference} · {e.actor}</div>
                </div>
                <span className="text-[12px] text-muted">{timeAgo(e.at)}</span>
              </div>
            ))}
            {(d.blocks as any[]).map((b) => (
              <div key={b.id} className="flex items-center gap-3 bg-amber-50/50 px-4 py-3">
                <Ban className="size-5 text-amber-700" />
                <div className="min-w-0 flex-1">
                  <div className="truncate text-[14px] font-semibold">{b.seats} vaga(s) bloqueada(s) · {b.class}</div>
                  <div className="truncate text-[12px] text-muted">{BLOCK_REASON[b.reason]} — {b.justification}</div>
                </div>
              </div>
            ))}
          </Card>
        </Section>
      </div>

      <Section title="Atendimentos da unidade">
        <LinkCard to={`/atendimentos?unidade=${u.id}`} className="flex items-center gap-3 p-4">
          <span className="inline-flex size-11 items-center justify-center rounded-2xl bg-amber-100 text-amber-800"><ClipboardList className="size-5" /></span>
          <div className="flex-1">
            <div className="font-semibold">{fmtInt(d.cases.open)} protocolos abertos</div>
            <div className="text-[12.5px] text-muted">{fmtInt(d.cases.overdue)} com prazo vencido</div>
          </div>
          <ChevronRight className="size-5 text-subtle" />
        </LinkCard>
        {u.phone ? null : <p className="mt-2 text-[12px] text-muted"><Phone className="mr-1 inline size-3.5" />Telefone da unidade: pendente SEDUC (não localizado em fonte pública).</p>}
      </Section>
    </div>
  );
}

function groupByGrade(classes: any[]): [string, any[]][] {
  const m = new Map<string, any[]>();
  for (const c of classes) {
    if (!m.has(c.grade)) m.set(c.grade, []);
    m.get(c.grade)!.push(c);
  }
  return [...m.entries()];
}
