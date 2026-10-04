import { useState } from 'react';
import { Link } from 'react-router';
import { AlarmClock, ChevronRight, ClipboardPlus, Inbox, MessageCircle, Search, Sparkles, UserCheck } from 'lucide-react';
import { useNow, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtInt, timeAgo, timeLeft, cleanLabel } from '@/lib/format';
import { CASE_STATUS, CASE_STATUS_ORDER, CHANNEL, FLAG, TONE_CLASSES } from '@/lib/labels';
import { Avatar, Badge, Button, ButtonLink, Card, EmptyState, ErrorState, PageHeader, Section, SkeletonList, SourceChip } from '@/components/ui';
import { OfferSheet } from '@/components/OfferSheet';
import { IaraBubble } from '@/components/iara';

export default function HomeAnalista() {
  const { me } = useSession();
  const dash = useRpc<any>('dashboard_analista', {}, { refetchInterval: 30_000 });
  const now = useNow(30_000);
  const [offerEntry, setOfferEntry] = useState<string | null>(null);

  if (dash.isLoading) return <SkeletonList rows={6} />;
  if (dash.error) return <ErrorState error={dash.error} onRetry={() => dash.refetch()} />;
  const d = dash.data;
  const by = d.cases.by_status ?? {};
  return (
    <div>
      <PageHeader
        eyebrow={me?.role_name}
        title="Qual vaga posso oferecer agora?"
        subtitle="Fila de atendimentos, vagas prontas para ofertar ao 1º da fila e conversas que pedem um servidor."
        actions={
          <>
            <ButtonLink to="/atendimentos/novo" icon={ClipboardPlus} variant="primary">Novo atendimento</ButtonLink>
            <ButtonLink to="/vagas" icon={Search} variant="secondary">Busca inteligente</ButtonLink>
          </>
        }
      />

      <div className="no-scrollbar -mx-4 flex gap-2.5 overflow-x-auto px-4 pb-1">
        {CASE_STATUS_ORDER.map((s) => {
          const st = CASE_STATUS[s];
          const t = TONE_CLASSES[st.tone];
          return (
            <Link key={s} to={`/atendimentos?status=${s}`} className="flex min-w-[124px] shrink-0 flex-col rounded-3xl bg-white p-3.5 shadow-soft ring-1 ring-line/70 transition hover:shadow-lift">
              <span className={`mb-2 inline-flex w-fit items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-bold ${t.bg} ${t.text}`}>
                <span className={`size-1.5 rounded-full ${t.dot}`} />{st.label}
              </span>
              <span className="font-display text-[28px] font-black leading-none tabular">{fmtInt(by[s] ?? 0)}</span>
            </Link>
          );
        })}
      </div>

      <div className="mt-3 grid grid-cols-3 gap-2.5">
        <Link to="/atendimentos?mine=1" className="rounded-3xl bg-white p-3 text-center shadow-soft ring-1 ring-line/70">
          <UserCheck className="mx-auto size-5 text-blue-700" />
          <div className="mt-1 font-display text-xl font-black tabular">{fmtInt(d.cases.mine)}</div>
          <div className="text-[11.5px] font-semibold text-muted">comigo</div>
        </Link>
        <Link to="/atendimentos?overdue=1" className="rounded-3xl bg-white p-3 text-center shadow-soft ring-1 ring-line/70">
          <AlarmClock className="mx-auto size-5 text-red-600" />
          <div className="mt-1 font-display text-xl font-black tabular text-red-700">{fmtInt(d.cases.overdue)}</div>
          <div className="text-[11.5px] font-semibold text-muted">prazo vencido</div>
        </Link>
        <Link to="/iara" className="rounded-3xl bg-white p-3 text-center shadow-soft ring-1 ring-line/70">
          <Inbox className="mx-auto size-5 text-purple-700" />
          <div className="mt-1 font-display text-xl font-black tabular text-purple-800">{fmtInt(d.conversations_pending.length)}</div>
          <div className="text-[11.5px] font-semibold text-muted">aguardam servidor</div>
        </Link>
      </div>

      <Section
        title="Vagas prontas para ofertar"
        subtitle="1º lugar da fila da unidade/faixa e turma com vaga ofertável agora"
        action={<SourceChip kind="calculado" detail="Lista gerada pelo motor de regras: posição 1 na fila (pontuação + data) e vaga ofertável = capacidade − matrículas − bloqueadas − reservadas." />}
      >
        {d.ready_to_offer.length ? (
          <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
            {d.ready_to_offer.map((r: any) => (
              <Card key={r.entry_id} className="p-4">
                <div className="flex items-start gap-3">
                  <Avatar name={r.student} seed={r.avatar_seed} size={44} />
                  <div className="min-w-0 flex-1">
                    <Link to={`/fila/${r.entry_id}`} className="block truncate font-semibold hover:text-purple-700">{r.student}</Link>
                    <div className="text-[12.5px] text-muted">{r.age} · {r.grade} · {r.unit}</div>
                    <div className="mt-1.5 flex flex-wrap gap-1">
                      <Badge tone="green">1º da fila</Badge>
                      {(r.flags ?? []).map((f: string) => <Badge key={f} tone="purple">{FLAG[f]?.short ?? f}</Badge>)}
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="font-display text-2xl font-black tabular text-green-700">{r.offerable}</div>
                    <div className="text-[11px] font-semibold text-muted">vaga(s)</div>
                  </div>
                </div>
                <div className="mt-3 flex gap-2">
                  <Button className="flex-1" variant="purple" icon={Sparkles} onClick={() => setOfferEntry(r.entry_id)}>Ofertar vaga</Button>
                  <ButtonLink to={`/alunos/${r.student_id}`} variant="secondary">Ficha</ButtonLink>
                </div>
              </Card>
            ))}
          </div>
        ) : (
          <Card><EmptyState compact title="Nenhuma vaga pronta agora" body="Quando uma vaga for liberada para o 1º da fila, ela aparece aqui." /></Card>
        )}
      </Section>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title="Ofertas vencendo em 24 h" subtitle="Lembre a família antes do prazo">
          <Card className="divide-y divide-line">
            {d.expiring.length ? d.expiring.map((o: any) => (
              <Link key={o.offer_id} to={`/alunos/${o.student_id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-slate-50">
                <AlarmClock className="size-5 text-amber-600" />
                <div className="min-w-0 flex-1">
                  <div className="truncate font-semibold">{o.student}</div>
                  <div className="text-[12.5px] text-muted">{o.unit}</div>
                </div>
                <Badge tone="amber">{timeLeft(o.expires_at, now)}</Badge>
              </Link>
            )) : <p className="p-4 text-sm text-muted">Nenhuma oferta perto do vencimento.</p>}
          </Card>
        </Section>
        <Section title="Conversas aguardando servidor" subtitle="A IARA encaminhou com o histórico completo">
          <Card className="divide-y divide-line">
            {d.conversations_pending.length ? d.conversations_pending.map((c: any) => (
              <Link key={c.id} to={`/conversas/${c.id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-slate-50">
                <MessageCircle className="size-5 text-purple-700" />
                <div className="min-w-0 flex-1">
                  <div className="truncate font-semibold">{cleanLabel(c.contact)}</div>
                  <div className="truncate text-[12.5px] text-muted">{c.summary}</div>
                </div>
                <span className="text-[12px] text-muted">{timeAgo(c.last_message_at, now)}</span>
              </Link>
            )) : <p className="p-4 text-sm text-muted">Nenhuma conversa aguardando.</p>}
          </Card>
        </Section>
      </div>

      <Section title="Protocolos novos" action={<Link to="/atendimentos?status=NOVO" className="text-sm font-semibold text-purple-700">Ver todos</Link>}>
        <Card className="divide-y divide-line">
          {d.new_cases.map((c: any) => (
            <Link key={c.id} to={`/atendimentos/${c.id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-slate-50">
              <div className="min-w-0 flex-1">
                <div className="truncate font-semibold">{c.subject}</div>
                <div className="text-[12.5px] text-muted">{c.protocol} · {CHANNEL[c.channel] ?? c.channel} · {timeAgo(c.opened_at, now)}</div>
              </div>
              {c.priority !== 'NORMAL' && <Badge tone="red">{c.priority === 'URGENTE' ? 'Urgente' : 'Alta'}</Badge>}
              <ChevronRight className="size-5 text-subtle" />
            </Link>
          ))}
        </Card>
      </Section>

      <div className="mt-6">
        <IaraBubble compact>
          Dica: a busca inteligente mostra o ranking de unidades com a explicação de cada ponto — nunca “recomendado por IA”. <Link to="/vagas" className="font-semibold text-purple-700 underline">Abrir busca</Link>
        </IaraBubble>
      </div>

      <OfferSheet open={!!offerEntry} entryId={offerEntry} onClose={() => setOfferEntry(null)} />
    </div>
  );
}
