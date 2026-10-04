import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Link } from 'react-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useReducedMotion } from 'motion/react';
import clsx from 'clsx';
import { Bot, Headset, MessageCirclePlus, Search, SendHorizontal, ShieldCheck, Sparkles, Wrench, X, Zap } from 'lucide-react';
import { iaraMessage, rpc, type ApiError } from '@/lib/api';
import { useDebounced, useNow, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { cleanLabel, fmtInt, timeAgo } from '@/lib/format';
import { CHANNEL, CONV_STATE } from '@/lib/labels';
import { Avatar, Badge, Card, EmptyState, ErrorState, PageHeader, SkeletonList, SourceChip, Tabs, inputCls } from '@/components/ui';
import { IaraAvatar, IaraBubble } from '@/components/iara';
import { ChatThread, QuickReplies, asQuickReply, type ChatMessage, type QuickReply } from '@/components/chat';
import { useConfirm, useToast } from '@/components/overlays';
import { WhatsAppButton } from '@/components/whatsapp';

export default function IaraHub() {
  const { me } = useSession();
  return me?.scope === 'GUARDIAN' ? <CitizenChat /> : <StaffInbox />;
}

// ============================================================================ Cidadão: WhatsApp simulado
const DEFAULT_MENU: QuickReply[] = [
  { label: 'Procurar vaga', action: 'intent:procurar_vaga' },
  { label: 'Posição na fila', action: 'intent:fila' },
  { label: 'Ofertas de vaga', action: 'intent:oferta' },
  { label: 'Acompanhar solicitação', action: 'intent:acompanhar' },
  { label: 'Documentos', action: 'intent:documentos' },
  { label: 'Minha família', action: 'intent:familia' },
  { label: 'Outros serviços', action: 'intent:servicos' },
  { label: 'Falar com atendente', action: 'intent:atendente' },
];
type ConvData = { conversation: any; messages: ChatMessage[]; bot_paused?: boolean };

function CitizenChat() {
  const { me } = useSession();
  const qc = useQueryClient();
  const toast = useToast();
  const confirm = useConfirm();
  const reduce = useReducedMotion();
  const key = useMemo(() => ['iara_conversation', me?.user_id], [me?.user_id]);
  const conv = useQuery<ConvData, ApiError>({
    queryKey: key,
    queryFn: () => rpc<ConvData>('iara_conversation', {}),
    staleTime: 10_000,
    refetchInterval: (q) => (['HUMAN_PENDING', 'HUMAN_ACTIVE'].includes(q.state.data?.conversation?.state) ? 4000 : false),
  });
  const [text, setText] = useState('');
  const [pending, setPending] = useState<ChatMessage | null>(null);
  const [sending, setSending] = useState(false);
  const [revealed, setRevealed] = useState<number | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const all = conv.data?.messages ?? [];
  const total = all.length;
  // Revela as respostas da IARA uma a uma (efeito "digitando"), salvo movimento reduzido
  useEffect(() => {
    if (revealed == null && total) setRevealed(total);
  }, [total, revealed]);
  useEffect(() => {
    if (revealed == null || revealed >= total) return;
    const next = all[revealed];
    const delay = reduce || next?.sender_type !== 'IARA' ? 0 : Math.min(1100, 380 + (next?.body?.length ?? 0) * 4);
    const t = setTimeout(() => setRevealed((r) => (r == null ? r : r + 1)), delay);
    return () => clearTimeout(t);
  }, [revealed, total, all, reduce]);

  const shown = revealed == null ? all : all.slice(0, revealed);
  const list = pending ? [...shown, pending] : shown;
  const typing = sending || (revealed != null && revealed < total);
  const state: string = conv.data?.conversation?.state ?? 'BOT_ACTIVE';
  const human = state === 'HUMAN_PENDING' || state === 'HUMAN_ACTIVE';
  const last = shown[shown.length - 1];
  const lastQuick = last && last.sender_type === 'IARA' ? (last.payload?.quick_replies ?? []).map(asQuickReply) : [];
  // sem botões na última resposta → menu padrão, para a conversa sempre ter um próximo passo clicável
  const quick: QuickReply[] = typing || human || !last ? [] : lastQuick.length ? lastQuick : DEFAULT_MENU;

  const send = async (body: string, action?: string | null) => {
    const conversationId = conv.data?.conversation?.id;
    if (!conversationId || sending || (!body.trim() && !action)) return;
    setPending({ id: 'pending', direction: 'IN', sender_type: 'CIDADAO', body: body.trim(), at: new Date().toISOString(), pending: true });
    setSending(true);
    setText('');
    const before = conv.data?.messages.length ?? 0;
    try {
      const res = (await iaraMessage(conversationId, body.trim(), action)) as ConvData;
      // tudo até a mensagem do cidadão aparece de imediato; as respostas da IARA entram em sequência
      const msgs = res.messages ?? [];
      let lastIn = -1;
      msgs.forEach((m, i) => { if (m.sender_type === 'CIDADAO' && i >= before - 1) lastIn = i; });
      setRevealed(lastIn >= 0 ? lastIn + 1 : before);
      qc.setQueryData(key, res);
    } catch (e) {
      toast({ title: 'Mensagem não enviada', description: (e as Error).message, tone: 'error' });
      setText(body);
    } finally {
      setPending(null);
      setSending(false);
      inputRef.current?.focus();
    }
  };

  const onSubmit = (e: FormEvent) => {
    e.preventDefault();
    send(text);
  };

  const restart = async () => {
    const ok = await confirm({ title: 'Começar nova conversa?', body: 'A conversa atual fica registrada no histórico. Os protocolos abertos continuam valendo.', confirm: 'Nova conversa', tone: 'purple' });
    if (!ok) return;
    try {
      const res = await rpc<ConvData>('iara_conversation', { new: true });
      setRevealed(null);
      qc.setQueryData(key, res);
    } catch (e) {
      toast({ title: 'Não foi possível reiniciar', description: (e as Error).message, tone: 'error' });
    }
  };

  return (
    <div className="mx-auto flex h-[calc(100dvh-4rem-66px-env(safe-area-inset-top)-env(safe-area-inset-bottom))] max-w-3xl flex-col lg:h-[calc(100dvh-4rem)] lg:px-6 lg:py-4">
      {/* Cabeçalho estilo app de mensagens */}
      <div className="flex items-center gap-3 border-b border-line/70 bg-white/85 px-4 py-2.5 backdrop-blur lg:rounded-t-3xl lg:border lg:shadow-soft">
        <IaraAvatar size={42} online={!human} />
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5 font-display text-[16px] font-extrabold leading-tight">IARA <Badge tone="purple" className="!py-0">assistente virtual</Badge></div>
          <div className="truncate text-[12px] text-muted">
            {human ? (state === 'HUMAN_ACTIVE' ? `Em atendimento com ${cleanLabel(conv.data?.conversation?.assigned) || 'servidor da SEDUC'}` : 'Aguardando um servidor da SEDUC') : typing ? 'digitando…' : `online · ${CHANNEL[conv.data?.conversation?.channel] ?? 'WhatsApp (simulado)'}`}
          </div>
        </div>
        <WhatsAppButton />
        <button onClick={restart} className="inline-flex size-11 items-center justify-center rounded-2xl text-purple-700 hover:bg-purple-50" aria-label="Nova conversa" title="Nova conversa">
          <MessageCirclePlus className="size-5" />
        </button>
      </div>

      {/* Mensagens */}
      <div className="relative min-h-0 flex-1 overflow-y-auto bg-[#F4EFFA] px-3 py-3 [background-image:radial-gradient(circle_at_1px_1px,rgb(122_36_197/0.07)_1px,transparent_0)] [background-size:18px_18px] lg:border-x lg:border-line/70">
        <div className="mx-auto mb-3 max-w-md rounded-2xl bg-amber-50/95 px-3 py-2 text-center text-[11.5px] text-amber-900 ring-1 ring-amber-100">
          <ShieldCheck className="mr-1 inline size-3.5" />
          Demonstração: nenhuma mensagem real é enviada. A IARA só informa dados oficiais e confirma ações depois do sistema.
        </div>
        {conv.isLoading ? (
          <div className="px-2"><SkeletonList rows={3} /></div>
        ) : conv.error ? (
          <ErrorState error={conv.error} onRetry={() => conv.refetch()} />
        ) : (
          <ChatThread messages={list} perspective="citizen" typing={typing} />
        )}
      </div>

      {/* Respostas rápidas + composição */}
      <div className="border-t border-line/70 bg-white/90 px-3 pb-3 pt-2 backdrop-blur lg:rounded-b-3xl lg:border lg:shadow-soft">
        {human && (
          <div className="mb-2 flex items-center gap-2 rounded-2xl bg-blue-50 px-3 py-2 text-[12.5px] text-blue-900 ring-1 ring-blue-100">
            <Headset className="size-4 shrink-0" />
            {state === 'HUMAN_ACTIVE' ? 'Um servidor está respondendo por aqui. A IARA está pausada.' : 'Sua conversa foi encaminhada com resumo. Um servidor vai responder aqui mesmo.'}
          </div>
        )}
        <QuickReplies items={quick} disabled={sending} onPick={(q) => send(q.label, q.action ?? null)} />
        <form onSubmit={onSubmit} className="mt-1 flex items-center gap-2">
          <input
            ref={inputRef}
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder={human ? 'Escreva para o atendimento…' : 'Escreva sua mensagem…'}
            aria-label="Mensagem para a IARA"
            maxLength={2000}
            className={clsx(inputCls, 'h-12 flex-1 rounded-full')}
            disabled={!conv.data}
          />
          <button
            type="submit"
            disabled={!text.trim() || sending || !conv.data}
            className="inline-flex size-12 shrink-0 items-center justify-center rounded-full bg-purple-700 text-white shadow-glow transition active:scale-95 disabled:opacity-40"
            aria-label="Enviar"
          >
            <SendHorizontal className="size-5" />
          </button>
        </form>
      </div>
    </div>
  );
}

// ============================================================================ Servidores: caixa de entrada
const STATES = ['HUMAN_PENDING', 'HUMAN_ACTIVE', 'FOLLOWUP_PENDING', 'BOT_ACTIVE', 'CLOSED'] as const;

function StaffInbox() {
  const [state, setState] = useState<string>('ALL');
  const [q, setQ] = useState('');
  const dq = useDebounced(q, 300);
  const now = useNow(30_000);
  const res = useRpc<any>('conversations_list', { state: state === 'ALL' ? null : state, q: dq || null }, { refetchInterval: 15_000 });
  const counts = (res.data?.counts ?? {}) as Record<string, number>;
  const totalAll = Object.values(counts).reduce((a, b) => a + b, 0);
  return (
    <div className="mx-auto w-full max-w-6xl px-4 pb-32 pt-3 sm:px-6 lg:pb-12">
      <PageHeader
        eyebrow="Agente IARA · WhatsApp e portal"
        title="Caixa da IARA"
        subtitle="Conversas atendidas pela IARA e as que ela encaminhou para a equipe com resumo. Assuma, responda e devolva — tudo auditado."
      />
      <IaraBubble compact className="mb-4">
        Quando não consigo resolver com segurança — exceção, reclamação, dado divergente ou pedido de atendente — eu <b>pauso</b> e passo para vocês com o resumo e o protocolo. Nunca prometo vaga, prazo ou posição sem confirmação do sistema.
      </IaraBubble>
      <ResolutionStats />
      <div className="mb-3 grid grid-cols-2 gap-2 sm:grid-cols-4">
        {(['HUMAN_PENDING', 'HUMAN_ACTIVE', 'FOLLOWUP_PENDING', 'BOT_ACTIVE'] as const).map((s) => (
          <button key={s} onClick={() => setState(state === s ? 'ALL' : s)} className={clsx('rounded-3xl p-3 text-left ring-1 transition active:scale-[0.98]', state === s ? 'bg-purple-700 text-white ring-purple-700' : 'bg-white ring-line hover:ring-purple-200')}>
            <div className={clsx('font-display text-2xl font-black tabular', state === s ? 'text-white' : 'text-ink')}>{fmtInt(counts[s] ?? 0)}</div>
            <div className={clsx('text-[12.5px] font-semibold', state === s ? 'text-purple-100' : 'text-muted')}>{CONV_STATE[s].label}</div>
          </button>
        ))}
      </div>
      <Tabs
        value={state}
        onChange={setState}
        items={[{ value: 'ALL', label: 'Todas', count: totalAll }, ...STATES.map((s) => ({ value: s, label: CONV_STATE[s].label, count: counts[s] ?? 0 }))]}
      />
      <div className="relative mt-3">
        <Search className="pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-subtle" />
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Contato ou assunto" className={clsx(inputCls, 'pl-11')} aria-label="Buscar conversa" />
        {q && <button className="absolute right-3 top-1/2 -translate-y-1/2" onClick={() => setQ('')} aria-label="Limpar"><X className="size-5 text-subtle" /></button>}
      </div>
      <div className="mt-2 flex items-center gap-2 text-[12.5px] text-muted"><SourceChip kind="demo" detail="Conversas fictícias geradas para a demonstração" /> atualiza a cada 15 s</div>
      <div className="mt-3">
        {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : !res.data.items.length ? (
          <Card><EmptyState title="Nenhuma conversa neste filtro" /></Card>
        ) : (
          <Card className="divide-y divide-line overflow-hidden">
            {(res.data.items as any[]).map((c) => (
              <Link key={c.id} to={`/conversas/${c.id}`} className="flex items-start gap-3 px-4 py-3 transition hover:bg-purple-50/50">
                <div className="relative">
                  <Avatar name={cleanLabel(c.contact)} seed={c.id} size={44} />
                  <span className={clsx('absolute -bottom-0.5 -right-0.5 inline-flex size-5 items-center justify-center rounded-full ring-2 ring-white', c.state === 'BOT_ACTIVE' ? 'bg-purple-600' : c.state.startsWith('HUMAN') ? 'bg-blue-600' : 'bg-slate-400')}>
                    {c.state === 'BOT_ACTIVE' ? <Bot className="size-3 text-white" /> : <Headset className="size-3 text-white" />}
                  </span>
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center justify-between gap-2">
                    <span className="truncate font-semibold">{cleanLabel(c.contact)}</span>
                    <span className="shrink-0 text-[11.5px] text-muted">{timeAgo(c.last_message_at, now)}</span>
                  </div>
                  <div className="truncate text-[13px] text-muted">{c.summary ?? c.last_message ?? '—'}</div>
                  <div className="mt-1 flex flex-wrap items-center gap-1">
                    <Badge tone={CONV_STATE[c.state]?.tone}>{CONV_STATE[c.state]?.label ?? c.state}</Badge>
                    {c.assigned_to_me && <Badge tone="green">com você</Badge>}
                    {c.assigned && !c.assigned_to_me && <Badge tone="gray" icon={Headset}>{cleanLabel(c.assigned).split(' · ')[0]}</Badge>}
                    {c.case && <Badge tone="blue">{c.case.protocol}</Badge>}
                    {c.intent && <span className="text-[11.5px] text-subtle">· {c.intent.replace(/_/g, ' ')}</span>}
                  </div>
                </div>
              </Link>
            ))}
          </Card>
        )}
      </div>
      <Card className="mt-6 p-4">
        <div className="mb-2 flex items-center gap-2 font-display font-extrabold"><Wrench className="size-5 text-purple-700" /> Como a IARA trabalha</div>
        <ul className="grid grid-cols-1 gap-2 text-[13.5px] text-ink-2 sm:grid-cols-2">
          <li className="flex gap-2"><Sparkles className="mt-0.5 size-4 shrink-0 text-purple-600" />Usa ferramentas do próprio sistema (buscar vagas, consultar fila, registrar protocolo, aceitar oferta) com as permissões do cidadão.</li>
          <li className="flex gap-2"><ShieldCheck className="mt-0.5 size-4 shrink-0 text-purple-600" />Dados pessoais só depois de verificar a identidade e o vínculo com a criança.</li>
          <li className="flex gap-2"><Headset className="mt-0.5 size-4 shrink-0 text-purple-600" />Encaminha com resumo quando há exceção, divergência ou pedido de atendente — e pausa até a devolução.</li>
          <li className="flex gap-2"><Bot className="mt-0.5 size-4 shrink-0 text-purple-600" />Cada ferramenta executada fica registrada (entrada, saída, tempo) e aparece no detalhe da conversa.</li>
        </ul>
      </Card>
    </div>
  );
}

/** Princípio da IARA resolutiva: quanto sai resolvido na hora × encaminhado para a unidade ou para a SEDUC. */
function ResolutionStats() {
  const res = useRpc<any>('iara_resolution_stats', { days: 30 }, { staleTime: 60_000 });
  const d = res.data;
  if (!d) return null;
  const levels = [
    { key: 'IARA', n: d.level_iara ?? 0, label: 'a IARA resolve na hora', bar: 'bg-green-500', box: 'bg-green-50 ring-green-100', text: 'text-green-800' },
    { key: 'UNIDADE', n: d.level_unit ?? 0, label: 'vão para a unidade', bar: 'bg-blue-500', box: 'bg-blue-50 ring-blue-100', text: 'text-blue-800' },
    { key: 'SECRETARIA', n: d.level_secretaria ?? 0, label: 'vão para a SEDUC', bar: 'bg-purple-500', box: 'bg-purple-50 ring-purple-100', text: 'text-purple-800' },
  ];
  const total = levels.reduce((s, l) => s + l.n, 0);
  const pct = (n: number) => (total ? Math.round((100 * n) / total) : 0);
  const conv = d.conversations ?? 0;
  const convPct = conv ? Math.round((100 * (d.conversations_without_staff ?? 0)) / conv) : 0;
  return (
    <Card className="mb-4 p-4">
      <div className="mb-1 flex items-center justify-between gap-2">
        <div className="font-display font-extrabold">Quem resolve os pedidos · 30 dias</div>
        <SourceChip kind="demo" detail="Pedidos feitos pelo WhatsApp e pelo portal, classificados pela matriz de alçadas: a IARA executa na hora o que é dela (cadastro, fila, endereço, dados, desistência); o que exige decisão humana vai para a secretaria da unidade ou para a SEDUC, com protocolo e prazo." />
      </div>
      <p className="mb-3 text-[12.5px] text-slate-500">De {fmtInt(total)} pedidos pelo WhatsApp e pelo portal, pela matriz de alçadas.</p>
      <div className="flex h-2.5 overflow-hidden rounded-full bg-slate-100" aria-hidden>
        {levels.map((l) => l.n > 0 && <div key={l.key} className={l.bar} style={{ width: `${(100 * l.n) / total}%` }} />)}
      </div>
      <div className="mt-3 grid grid-cols-3 gap-2 text-center">
        {levels.map((l) => (
          <div key={l.key} className={clsx('rounded-2xl p-2.5 ring-1', l.box)}>
            <div className={clsx('font-display text-2xl font-black tabular', l.text)}>{pct(l.n)}%</div>
            <div className="text-[11.5px] font-semibold leading-tight text-slate-800">{l.label}</div>
            <div className="mt-0.5 text-[11px] tabular text-slate-500">{fmtInt(l.n)} pedidos</div>
          </div>
        ))}
      </div>
      <div className="mt-3 space-y-1.5 text-[12.5px] text-slate-600">
        {conv > 0 && (
          <div className="flex items-start gap-2"><Bot className="mt-0.5 size-4 shrink-0 text-purple-600" /><span><b className="text-slate-800">{convPct}% das conversas</b> terminaram sem precisar de servidor ({fmtInt(d.conversations_without_staff)} de {fmtInt(conv)}).</span></div>
        )}
        {(d.resolved_by_iara ?? 0) > 0 && (
          <div className="flex items-start gap-2"><Zap className="mt-0.5 size-4 shrink-0 text-green-600" /><span><b className="text-slate-800">{fmtInt(d.resolved_by_iara)} pedidos</b> executados e encerrados pela própria IARA na hora.</span></div>
        )}
      </div>
    </Card>
  );
}
