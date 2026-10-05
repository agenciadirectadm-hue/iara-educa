import { useState, type FormEvent } from 'react';
import { Link, useParams } from 'react-router';
import clsx from 'clsx';
import { Bot, CheckCircle2, ChevronDown, CircleSlash, Headset, Lock, SendHorizontal, ShieldCheck, Undo2, UserRound, XCircle } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useNow, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { cleanLabel, fmtDateTime, timeAgo } from '@/lib/format';
import { CASE_STATUS, CHANNEL, CONV_STATE } from '@/lib/labels';
import { Avatar, Badge, Button, Card, DataPair, EmptyState, ErrorState, SkeletonList, Tabs, inputCls } from '@/components/ui';
import { Crumbs } from '@/components/Crumbs';
import { ChatThread, type ChatMessage } from '@/components/chat';
import { useConfirm, useToast } from '@/components/overlays';

const TOOL_LABEL: Record<string, string> = {
  search_official_knowledge: 'Base oficial de conhecimento', get_student_service_context: 'Contexto da família', determine_grade: 'Faixa pela data de nascimento',
  search_vacancies: 'Busca de vagas', list_units: 'Unidades próximas', create_service_case: 'Abertura de protocolo', register_student: 'Pré-cadastro da criança',
  accept_offer: 'Aceite de oferta', decline_offer: 'Recusa de oferta', submit_document: 'Envio de documento', verify_identity: 'Verificação de identidade',
  handoff_to_team: 'Encaminhamento à equipe',
};

export default function Conversation() {
  const { id } = useParams();
  const { can } = useSession();
  const toast = useToast();
  const confirm = useConfirm();
  const now = useNow(30_000);
  const res = useRpc<any>('conversation_detail', { id }, { refetchInterval: 5000 });
  const [text, setText] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const [tab, setTab] = useState<'contexto' | 'ferramentas' | 'encaminhamentos'>('contexto');

  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const c = d.conversation;
  const mine = c.state === 'HUMAN_ACTIVE' && c.assigned_to_me;
  const canTake = can('conversations.takeover');

  const act = async (fn: string, label: string, args: object = {}) => {
    setBusy(fn);
    try {
      await rpc(fn, { id, ...args });
      await res.refetch();
      if (label) toast({ title: label, tone: 'success' });
      return true;
    } catch (e) {
      toast({ title: 'Ação não realizada', description: (e as Error).message, tone: 'error' });
      return false;
    } finally {
      setBusy(null);
    }
  };

  const reply = async (e: FormEvent) => {
    e.preventDefault();
    const body = text.trim();
    if (!body) return;
    setText('');
    const ok = await act('conversation_operator_message', '', { body });
    if (!ok) setText(body);
  };

  return (
    <div>
      <Crumbs items={[{ label: 'Conversas', to: '/iara' }, { label: cleanLabel(c.contact) }]} />
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <Avatar name={cleanLabel(c.contact)} seed={c.id} size={52} />
        <div className="min-w-0 flex-1">
          <h1 className="font-display text-2xl font-black leading-tight">{cleanLabel(c.contact)}</h1>
          <div className="text-[13px] text-muted">{c.phone ?? 'sem telefone'} · {CHANNEL[c.channel] ?? c.channel} · última mensagem {timeAgo(c.last_message_at, now)}</div>
          <div className="mt-1 flex flex-wrap gap-1">
            <Badge tone={CONV_STATE[c.state]?.tone}>{CONV_STATE[c.state]?.label ?? c.state}</Badge>
            {c.assigned && <Badge tone={c.assigned_to_me ? 'green' : 'gray'} icon={Headset}>{c.assigned_to_me ? 'com você' : cleanLabel(c.assigned)}</Badge>}
            <Badge tone={c.identity_verified ? 'green' : 'amber'} icon={c.identity_verified ? ShieldCheck : Lock}>{c.identity_verified ? 'identidade verificada' : 'identidade não verificada'}</Badge>
            {c.is_demo && <Badge tone="amber">demonstração</Badge>}
          </div>
        </div>
        {canTake && (
          <div className="flex w-full flex-wrap gap-2 sm:w-auto">
            {!mine && c.state !== 'CLOSED' && (
              <Button variant="purple" icon={Headset} loading={busy === 'conversation_takeover'} onClick={() => act('conversation_takeover', 'Conversa assumida — a IARA está pausada')}>
                Assumir conversa
              </Button>
            )}
            {mine && (
              <Button variant="secondary" icon={Undo2} loading={busy === 'conversation_release'} onClick={() => act('conversation_release', 'Conversa devolvida à IARA')}>
                Devolver à IARA
              </Button>
            )}
            {c.state !== 'CLOSED' && (
              <Button
                variant="ghost"
                icon={XCircle}
                loading={busy === 'conversation_close'}
                onClick={async () => {
                  const ok = await confirm({ title: 'Encerrar conversa?', body: 'Os protocolos vinculados seguem seus próprios status. A família pode voltar a escrever quando quiser.', confirm: 'Encerrar', tone: 'danger' });
                  if (ok) act('conversation_close', 'Conversa encerrada');
                }}
              >
                Encerrar
              </Button>
            )}
          </div>
        )}
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1.35fr_1fr]">
        <Card className="flex flex-col overflow-hidden">
          <div className="h-[56dvh] min-h-[340px] overflow-y-auto bg-[#F4EFFA] px-3 py-3 [background-image:radial-gradient(circle_at_1px_1px,rgb(122_36_197/0.07)_1px,transparent_0)] [background-size:18px_18px] lg:h-[62dvh]">
            {(d.messages as ChatMessage[]).length ? <ChatThread messages={d.messages} perspective="operator" /> : <EmptyState compact title="Sem mensagens" />}
          </div>
          <div className="border-t border-line bg-white p-3">
            {mine ? (
              <form onSubmit={reply} className="flex items-center gap-2">
                <input value={text} onChange={(e) => setText(e.target.value)} placeholder="Responder como servidor(a) da SEDUC…" aria-label="Resposta do servidor" maxLength={2000} className={clsx(inputCls, 'flex-1 rounded-full')} />
                <button type="submit" disabled={!text.trim() || !!busy} className="inline-flex size-12 shrink-0 items-center justify-center rounded-full bg-blue-700 text-white transition active:scale-95 disabled:opacity-40" aria-label="Enviar resposta">
                  <SendHorizontal className="size-5" />
                </button>
              </form>
            ) : (
              <div className="flex items-center gap-2 text-[13px] text-muted">
                {c.state === 'CLOSED' ? <CircleSlash className="size-4" /> : c.state === 'BOT_ACTIVE' ? <Bot className="size-4 text-purple-700" /> : <Headset className="size-4 text-blue-700" />}
                {c.state === 'CLOSED'
                  ? 'Conversa encerrada.'
                  : c.state === 'HUMAN_ACTIVE'
                    ? `Em atendimento por ${cleanLabel(c.assigned)}. Só quem assumiu pode responder.`
                    : canTake ? 'Assuma a conversa para responder — evita disputa com a IARA.' : 'Somente leitura para o seu perfil.'}
              </div>
            )}
          </div>
        </Card>

        <div>
          <Tabs
            value={tab}
            onChange={setTab}
            items={[
              { value: 'contexto', label: 'Contexto' },
              { value: 'ferramentas', label: 'Ferramentas', count: (d.tools ?? []).length },
              { value: 'encaminhamentos', label: 'Encaminhamentos', count: (d.handoffs ?? []).length },
            ]}
          />
          {tab === 'contexto' && (
            <div className="mt-3 space-y-3">
              {c.summary && (
                <Card className="p-4">
                  <div className="mb-1 text-[11.5px] font-bold uppercase tracking-wide text-subtle">Resumo da IARA</div>
                  <p className="text-[14.5px] text-ink-2">{c.summary}</p>
                  {c.intent && <div className="mt-2 text-[12.5px] text-muted">Assunto: {c.intent.replace(/_/g, ' ')}</div>}
                </Card>
              )}
              <Card className="divide-y divide-line">
                {d.guardian ? (
                  <Link to={`/responsaveis/${d.guardian.id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-slate-50">
                    <UserRound className="size-5 text-blue-700" />
                    <div className="min-w-0 flex-1"><div className="text-[11.5px] font-bold uppercase tracking-wide text-subtle">Responsável</div><div className="truncate font-semibold">{d.guardian.name}</div></div>
                  </Link>
                ) : <div className="px-4 py-3 text-[13.5px] text-muted">Contato sem cadastro de responsável vinculado.</div>}
                {d.context_student && (
                  <Link to={`/alunos/${d.context_student.id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-slate-50">
                    <Avatar name={d.context_student.name} size={32} />
                    <div className="min-w-0 flex-1"><div className="text-[11.5px] font-bold uppercase tracking-wide text-subtle">Criança em atendimento</div><div className="truncate font-semibold">{d.context_student.name} · {d.context_student.age}</div></div>
                  </Link>
                )}
                {d.context_case && (
                  <Link to={`/atendimentos/${d.context_case.id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-slate-50">
                    <CheckCircle2 className="size-5 text-green-700" />
                    <div className="min-w-0 flex-1">
                      <div className="text-[11.5px] font-bold uppercase tracking-wide text-subtle">Protocolo</div>
                      <div className="truncate font-semibold">{d.context_case.protocol} · {d.context_case.subject}</div>
                    </div>
                    <Badge tone={CASE_STATUS[d.context_case.status]?.tone}>{CASE_STATUS[d.context_case.status]?.label ?? d.context_case.status}</Badge>
                  </Link>
                )}
              </Card>
              <Card className="grid grid-cols-2 gap-3 p-4">
                <DataPair label="Canal" value={CHANNEL[c.channel] ?? c.channel} />
                <DataPair label="Estado" value={CONV_STATE[c.state]?.label ?? c.state} />
                <DataPair label="Identidade" value={c.identity_verified ? 'Verificada (código simulado)' : 'Não verificada'} />
                <DataPair label="Última atividade" value={fmtDateTime(c.last_message_at)} />
              </Card>
            </div>
          )}
          {tab === 'ferramentas' && (
            <div className="mt-3">
              <p className="mb-2 text-[13px] text-muted">Cada ação da IARA chama uma função do sistema com as permissões do cidadão — registrada com entrada, saída e tempo.</p>
              <div className="space-y-2">
                {(d.tools ?? []).length ? (d.tools as any[]).map((t, i) => <ToolRow key={i} t={t} />) : <Card><EmptyState compact title="Nenhuma ferramenta executada" /></Card>}
              </div>
            </div>
          )}
          {tab === 'encaminhamentos' && (
            <div className="mt-3 space-y-2">
              {(d.handoffs ?? []).length ? (d.handoffs as any[]).map((h) => (
                <Card key={h.id} className="p-4">
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-semibold">{h.reason}</span>
                    <Badge tone={h.status === 'ABERTA' ? 'amber' : h.status === 'ASSUMIDA' ? 'blue' : 'green'}>{h.status === 'ABERTA' ? 'Aberto' : h.status === 'ASSUMIDA' ? 'Assumido' : 'Concluído'}</Badge>
                  </div>
                  <div className="mt-1 text-[12.5px] text-muted">{h.sector?.replace(/_/g, ' ')} · {fmtDateTime(h.at)}</div>
                  {h.summary && <p className="mt-2 rounded-2xl bg-slate-50 p-3 text-[13.5px] text-ink-2">{h.summary}</p>}
                </Card>
              )) : <Card><EmptyState compact title="Nenhum encaminhamento" body="A IARA resolveu sem precisar da equipe." /></Card>}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function ToolRow({ t }: { t: any }) {
  const [open, setOpen] = useState(false);
  const tone = t.status === 'OK' ? 'green' : t.status === 'NEGADO' ? 'amber' : 'red';
  return (
    <Card className="overflow-hidden">
      <button onClick={() => setOpen(!open)} className="flex w-full items-center gap-3 px-4 py-3 text-left hover:bg-slate-50" aria-expanded={open}>
        <Bot className="size-5 shrink-0 text-purple-700" />
        <div className="min-w-0 flex-1">
          <div className="truncate text-[14px] font-semibold">{TOOL_LABEL[t.tool] ?? t.tool}</div>
          <div className="text-[11.5px] text-muted"><code>{t.tool}</code> · {t.ms ?? '—'} ms · {fmtDateTime(t.at)}</div>
        </div>
        <Badge tone={tone}>{t.status}</Badge>
        <ChevronDown className={clsx('size-4 text-subtle transition', open && 'rotate-180')} />
      </button>
      {open && (
        <div className="grid gap-2 border-t border-line bg-slate-50 p-3 text-[11.5px]">
          {t.error && <div className="rounded-xl bg-red-50 p-2 text-red-800">{t.error}</div>}
          <div><div className="mb-1 font-bold text-subtle">Entrada</div><pre className="max-h-48 overflow-auto rounded-xl bg-white p-2 ring-1 ring-line">{JSON.stringify(t.input, null, 2)}</pre></div>
          <div><div className="mb-1 font-bold text-subtle">Saída</div><pre className="max-h-48 overflow-auto rounded-xl bg-white p-2 ring-1 ring-line">{JSON.stringify(t.output, null, 2)}</pre></div>
        </div>
      )}
    </Card>
  );
}
