import { Link } from 'react-router';
import clsx from 'clsx';
import { Bell, ChevronRight, ClipboardList, Clock, MessageCircle, Search } from 'lucide-react';
import { useNow, useRpc } from '@/lib/hooks';
import { fmtDate, timeAgo } from '@/lib/format';
import { CASE_STATUS } from '@/lib/labels';
import { Badge, ButtonLink, Card, EmptyState, ErrorState, PageHeader, Section, SkeletonList } from '@/components/ui';
import { IaraBubble } from '@/components/iara';

/** Portal do responsável: "Minhas solicitações" — protocolos, andamento e avisos. */
export default function CitizenCases() {
  const res = useRpc<any>('citizen_home');
  const now = useNow(60_000);
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const cases = (d.cases ?? []) as any[];
  const open = cases.filter((c) => c.open);
  const closed = cases.filter((c) => !c.open);
  return (
    <div>
      <PageHeader
        eyebrow="Minhas solicitações"
        title="Protocolos"
        subtitle="Cada pedido vira um protocolo com prazo. Você acompanha cada etapa aqui ou pela IARA — sem precisar ir à Secretaria."
        actions={<ButtonLink to="/iara" variant="purple" icon={MessageCircle}>Nova solicitação com a IARA</ButtonLink>}
      />
      <Section title={`Em andamento (${open.length})`} className="mt-0">
        {open.length ? (
          <div className="space-y-3">
            {open.map((c) => <CaseCard key={c.id} c={c} now={now} />)}
          </div>
        ) : (
          <Card><EmptyState compact title="Nenhum protocolo em andamento" body="Precisa de vaga, transferência ou documento? A IARA abre o protocolo para você." action={<ButtonLink to="/vagas" variant="secondary" icon={Search}>Consultar vagas</ButtonLink>} /></Card>
        )}
      </Section>
      {(d.notifications ?? []).length > 0 && (
        <Section title="Avisos recentes">
          <Card className="divide-y divide-line">
            {(d.notifications as any[]).map((n) => (
              <div key={n.id} className="flex gap-3 px-4 py-3">
                <span className="mt-0.5 inline-flex size-9 shrink-0 items-center justify-center rounded-xl bg-purple-100 text-purple-700"><Bell className="size-4" /></span>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center justify-between gap-2"><span className="font-semibold">{n.title}</span><span className="shrink-0 text-[11.5px] text-muted">{timeAgo(n.at, now)}</span></div>
                  <p className="text-[13.5px] text-ink-2">{n.body}</p>
                </div>
              </div>
            ))}
          </Card>
        </Section>
      )}
      {closed.length > 0 && (
        <Section title={`Concluídos (${closed.length})`}>
          <Card className="divide-y divide-line">
            {closed.map((c) => (
              <Link key={c.id} to={`/atendimentos/${c.id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-slate-50">
                <ClipboardList className="size-5 shrink-0 text-subtle" />
                <div className="min-w-0 flex-1">
                  <div className="truncate font-semibold">{c.type_name}</div>
                  <div className="text-[12.5px] text-muted">{c.protocol} · aberto em {fmtDate(c.opened_at)}</div>
                </div>
                <Badge tone={CASE_STATUS[c.status]?.tone}>{CASE_STATUS[c.status]?.label ?? c.status}</Badge>
              </Link>
            ))}
          </Card>
        </Section>
      )}
      <IaraBubble compact className="mt-6">
        Dúvida sobre algum protocolo? Me chame na aba <Link to="/iara" className="font-bold text-purple-700 underline">IARA</Link> — eu consulto o andamento e, se precisar, encaminho para a equipe com o resumo.
      </IaraBubble>
    </div>
  );
}

function CaseCard({ c, now }: { c: any; now: number }) {
  const overdue = c.sla_due_at && new Date(c.sla_due_at).getTime() < now;
  const steps = ['NOVO', 'EM_ANALISE', 'VAGA_OFERTADA', 'MATRICULA_CONCLUIDA'];
  const idx = Math.max(0, steps.indexOf(c.status === 'AGUARDANDO_DOCUMENTOS' || c.status === 'AGUARDANDO_FAMILIA' || c.status === 'VAGA_ENCONTRADA' || c.status === 'EM_FILA' ? 'EM_ANALISE' : c.status));
  return (
    <Link to={`/atendimentos/${c.id}`} className="group block rounded-3xl bg-white p-4 shadow-soft ring-1 ring-line/70 transition hover:shadow-lift active:scale-[0.99]">
      <div className="flex items-start gap-3">
        <span className="inline-flex size-11 shrink-0 items-center justify-center rounded-2xl bg-blue-100 text-blue-800"><ClipboardList className="size-5" /></span>
        <div className="min-w-0 flex-1">
          <div className="font-display text-[16px] font-extrabold leading-tight">{c.type_name}</div>
          <div className="text-[12.5px] text-muted">{c.protocol} · aberto em {fmtDate(c.opened_at)}</div>
        </div>
        <ChevronRight className="mt-1 size-5 text-subtle transition group-hover:translate-x-0.5" />
      </div>
      <div className="mt-3 flex flex-wrap items-center gap-1.5">
        <Badge tone={CASE_STATUS[c.status]?.tone}>{CASE_STATUS[c.status]?.label ?? c.status}</Badge>
        {c.sla_due_at && <Badge tone={overdue ? 'red' : 'gray'} icon={Clock}>{overdue ? 'prazo vencido — em prioridade' : `prazo ${fmtDate(c.sla_due_at)}`}</Badge>}
      </div>
      {c.last_event && <p className="mt-2 rounded-2xl bg-slate-50 p-3 text-[13.5px] text-ink-2">{c.last_event}</p>}
      <ol className="mt-3 grid grid-cols-4 gap-1" aria-label="Etapas">
        {['Recebido', 'Em análise', 'Vaga ofertada', 'Matrícula'].map((s, i) => (
          <li key={s} className="text-center">
            <div className={clsx('h-1.5 rounded-full', i <= idx ? 'bg-purple-600' : 'bg-slate-200')} />
            <div className={clsx('mt-1 text-[10.5px] font-semibold leading-tight', i <= idx ? 'text-purple-800' : 'text-subtle')}>{s}</div>
          </li>
        ))}
      </ol>
    </Link>
  );
}
