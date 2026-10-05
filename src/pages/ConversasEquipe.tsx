import { useEffect, useMemo, useState, type FormEvent, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { Link, useSearchParams } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import {
  AlertTriangle, ArrowLeft, Bot, Building2, CheckCheck, Clock, ExternalLink, Headset, Landmark, Lock, MessageSquare, Search, SendHorizontal, ShieldCheck,
  Shuffle, SlidersHorizontal, Undo2, X, XCircle,
} from 'lucide-react';
import { rpc } from '@/lib/api';
import { useDebounced, useIsDesktop, useNow, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { cleanLabel, fmtInt, timeAgo } from '@/lib/format';
import { Avatar, Button, Card, EmptyState, ErrorState, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useConfirm, useToast } from '@/components/overlays';
import { ChatThread, type ChatMessage } from '@/components/chat';

type Quem = 'IA' | 'AGUARDANDO' | 'HUMANO' | 'ENCERRADA';
type Responsavel = { unit_id: number | null; equipe: string; rotulo: string; curto: string };
type Item = {
  id: string; contato: string; telefone: string | null; canal: string; estado: string; quem: Quem; atendente: string | null; comigo: boolean;
  responsavel: Responsavel | null; aguardando_desde: string | null; nao_lidas: number; protocolo: string | null; resumo: string | null; em: string | null;
  ultima: { texto: string; de: string; direcao: string; em: string } | null;
};
type Lista = { escopo: 'REDE' | 'UNIDADE'; unidade: string | null; pode_controlar: boolean; contagem: Record<string, number>; itens: Item[] };
type Grupo = {
  unit_id: number | null; equipe: string; rotulo: string; curto: string; tipo: 'SEDUC' | 'UNIDADE'; aguardando: number; em_atendimento: number;
  atrasadas: number; maior_espera_min: number | null; resposta_media_min: number | null;
};
type Controle = { limite_min: number; totais: Record<string, number>; responsaveis: Grupo[]; unidades: { id: number; nome: string; curto: string }[] };
type Filtro = { unidade_id?: number; equipe?: string; rotulo: string };

const FILTROS = [
  { v: 'abertas', l: 'Abertas' }, { v: 'aguardando', l: 'Aguardando' }, { v: 'humano', l: 'Com humano' }, { v: 'ia', l: 'Com a IA' }, { v: 'encerradas', l: 'Encerradas' },
] as const;
const EQUIPES_SEDUC = [
  { v: 'ATENDIMENTO', l: 'Atendimento ao Cidadão' }, { v: 'CENTRAL_VAGAS', l: 'Central de Vagas' }, { v: 'OUVIDORIA', l: 'Ouvidoria' },
  { v: 'TRANSPORTE', l: 'Transporte Escolar' }, { v: 'AEE', l: 'Inclusão e AEE' }, { v: 'INTEGRAL', l: 'Educação Integral' },
  { v: 'ALIMENTACAO', l: 'Merenda Escolar' }, { v: 'GESTAO', l: 'Gestão Educacional' },
];
const CANAL: Record<string, string> = { WHATSAPP: 'WhatsApp', WHATSAPP_SIMULADO: 'WhatsApp simulado', PORTAL: 'Portal' };
const WA_VERDE = '#1FA855';

/** Hora no estilo do WhatsApp: hoje → 14:32 · ontem · antes → 03/10. */
function horaCurta(iso: string | null | undefined, now: number) {
  if (!iso) return '';
  const d = new Date(iso);
  if (d.toDateString() === new Date(now).toDateString()) return d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  if (d.toDateString() === new Date(now - 86_400_000).toDateString()) return 'ontem';
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
}
function duracao(min: number | null | undefined) {
  if (min == null) return '—';
  if (min < 60) return `${Math.max(0, Math.round(min))} min`;
  const h = Math.floor(min / 60);
  const m = Math.round(min % 60);
  return h < 24 ? `${h} h${m ? ` ${m} min` : ''}` : `${Math.floor(h / 24)} d ${h % 24} h`;
}
const espera = (iso: string | null | undefined, now: number) => (iso ? (now - Date.parse(iso)) / 60_000 : 0);
/** Há quanto tempo, sem o "há": "5 min", "2 h", "agora". */
const haQuanto = (iso: string | null | undefined, now: number) => timeAgo(iso, now).replace(/^há /, '');
const maiuscula = (t: string) => t.charAt(0).toUpperCase() + t.slice(1);
/** Onde está a conversa, curto: "CMEI Antonio Facci", "E.M. Geraldo Meneghetti" ou a equipe da SEDUC. */
const ondeCurto = (r: Responsavel) => (r.unit_id ? r.rotulo.replace(/^secretaria d[oa] /i, '') : r.curto);
/** "Ana · WhatsApp (44) •••••-1234" → "Ana" (o telefone aparece à parte). */
const nomeContato = (label: string | null | undefined) => cleanLabel(label).split(' · WhatsApp')[0] || 'Contato';
/** Prévia de uma linha: sem marcação de negrito/itálico e sem quebras. */
const previa = (t: string | null | undefined) => cleanLabel(t).replace(/\*\*(.+?)\*\*/g, '$1').replace(/(^|\s)[*_](\S.*?\S|\S)[*_](?=\s|$|[.,!?])/g, '$1$2').replace(/\s+/g, ' ').trim();

/**
 * Conversas da equipe no estilo do WhatsApp: lista à esquerda, conversa aberta à direita (no celular, uma de cada vez).
 * Cada linha diz quem está atendendo — a IARA ou uma pessoa — e, para a Secretaria, de qual unidade ou equipe é a conversa.
 */
export default function ConversasEquipe() {
  const [params, setParams] = useSearchParams();
  const sel = params.get('c');
  const desktop = useIsDesktop();
  const now = useNow(20_000);
  const [filtro, setFiltro] = useState<string>('abertas');
  const [q, setQ] = useState('');
  const dq = useDebounced(q, 300);
  const [soWhats, setSoWhats] = useState(false);
  const [resp, setResp] = useState<Filtro | null>(null);
  const [controleAberto, setControleAberto] = useState(false);

  const lista = useRpc<Lista>('conversas_lista', {
    filtro, q: dq || null, canal: soWhats ? 'WHATSAPP_TODOS' : null, unidade_id: resp?.unidade_id ?? null, equipe: resp?.equipe ?? null,
  }, { refetchInterval: 8_000 });
  const d = lista.data;
  const controle = useRpc<Controle>('conversas_controle', {}, { refetchInterval: 20_000, enabled: d?.escopo === 'REDE', retry: false });

  const abrir = (id: string | null) => {
    const p = new URLSearchParams(params);
    if (id) p.set('c', id);
    else p.delete('c');
    // no celular, abrir empilha no histórico: o "voltar" do aparelho fecha a conversa e volta à lista
    setParams(p, { replace: desktop || !id });
  };

  return (
    <div>
      {d?.escopo === 'REDE' && <FaixaControle c={controle.data} onAbrir={() => setControleAberto(true)} />}
      {d?.escopo === 'UNIDADE' && <FaixaUnidade d={d} />}

      <Card className="mt-3 overflow-hidden lg:grid lg:h-[74dvh] lg:min-h-[540px] lg:grid-cols-[400px_1fr]">
        <div className="flex min-h-0 flex-col lg:border-r lg:border-line">
          <div className="border-b border-line bg-white p-3">
            <div className="relative">
              <Search className="pointer-events-none absolute left-3.5 top-1/2 size-4.5 -translate-y-1/2 text-subtle" />
              <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Pesquisar contato, assunto ou telefone" aria-label="Pesquisar conversa"
                className={clsx(inputCls, 'h-10 rounded-full bg-slate-100 pl-10 ring-0')} />
              {q && <button className="absolute right-3 top-1/2 -translate-y-1/2" onClick={() => setQ('')} aria-label="Limpar"><X className="size-4 text-subtle" /></button>}
            </div>
            <div className="no-scrollbar mt-2 flex gap-1.5 overflow-x-auto pb-0.5">
              {FILTROS.map((f) => (
                <button key={f.v} onClick={() => setFiltro(f.v)}
                  className={clsx('inline-flex h-8 shrink-0 items-center gap-1.5 rounded-full px-3 text-[13px] font-semibold transition',
                    filtro === f.v ? 'bg-green-100 text-green-900' : 'bg-slate-100 text-ink-2 hover:bg-slate-200')}>
                  {f.l}{d?.contagem?.[f.v] != null && <span className="tabular text-[12px] opacity-70">{fmtInt(d.contagem[f.v])}</span>}
                </button>
              ))}
              <button onClick={() => setSoWhats(!soWhats)} aria-pressed={soWhats}
                className={clsx('inline-flex h-8 shrink-0 items-center gap-1.5 rounded-full px-3 text-[13px] font-semibold transition',
                  soWhats ? 'text-white' : 'bg-slate-100 text-ink-2 hover:bg-slate-200')} style={soWhats ? { background: WA_VERDE } : undefined}>
                <MessageSquare className="size-3.5" /> Só WhatsApp
              </button>
            </div>
            {resp && (
              <button onClick={() => setResp(null)} className="mt-2 inline-flex max-w-full items-center gap-1.5 rounded-full bg-blue-50 px-3 py-1 text-[12.5px] font-semibold text-blue-900 ring-1 ring-blue-200">
                <span className="truncate">Responsável: {resp.rotulo}</span><X className="size-3.5 shrink-0" />
              </button>
            )}
          </div>
          <div className="min-h-0 flex-1 overflow-y-auto bg-white">
            {lista.isLoading ? <div className="p-3"><SkeletonList rows={6} /></div> : lista.error ? <div className="p-3"><ErrorState error={lista.error} onRetry={() => lista.refetch()} /></div>
              : !d?.itens.length ? <EmptyState compact title="Nenhuma conversa neste filtro" body={d?.escopo === 'UNIDADE' ? 'Quando a IARA encaminhar uma conversa para a unidade, ela aparece aqui.' : undefined} />
                : d.itens.map((c) => <Linha key={c.id} c={c} ativo={c.id === sel} rede={d.escopo === 'REDE'} now={now} onClick={() => abrir(c.id)} />)}
          </div>
        </div>
        {desktop && (sel
          ? <ConversaPainel key={sel} id={sel} onVoltar={() => abrir(null)} desktop podeControlar={!!d?.pode_controlar} unidades={controle.data?.unidades ?? []} />
          : (
            <div className="flex flex-col items-center justify-center gap-2 bg-[#F0F2F5] p-8 text-center">
              <MessageSquare className="size-10 text-subtle" />
              <div className="font-display text-lg font-extrabold text-ink-2">Selecione uma conversa</div>
              <p className="max-w-sm text-[13.5px] text-muted">A lista mostra quem está atendendo cada conversa — a IARA ou uma pessoa — e quem espera um humano aparece primeiro.</p>
            </div>
          ))}
      </Card>
      {!desktop && sel && (
        <TelaCheia>
          <ConversaPainel key={sel} id={sel} onVoltar={() => abrir(null)} desktop={false} podeControlar={!!d?.pode_controlar} unidades={controle.data?.unidades ?? []} />
        </TelaCheia>
      )}

      {d?.escopo === 'REDE' && (
        <ControleSheet open={controleAberto} onClose={() => setControleAberto(false)} c={controle.data}
          onFiltrar={(g) => {
            setResp(g.unit_id ? { unidade_id: g.unit_id, rotulo: ondeCurto(g) } : { equipe: g.equipe, rotulo: g.curto });
            setFiltro('abertas');
            setControleAberto(false);
          }} />
      )}
    </div>
  );
}

/** No celular a conversa abre por cima de tudo, como no WhatsApp; a lista continua montada por baixo. */
function TelaCheia({ children }: { children: ReactNode }) {
  useEffect(() => {
    const antes = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => { document.body.style.overflow = antes; };
  }, []);
  return createPortal(<div className="fixed inset-0 z-[60] flex flex-col bg-white pt-safe pb-safe">{children}</div>, document.body);
}

/* ─────────────────────────────────────── linha da lista */

function Linha({ c, ativo, rede, now, onClick }: { c: Item; ativo: boolean; rede: boolean; now: number; onClick: () => void }) {
  const Icone = c.quem === 'IA' ? Bot : c.quem === 'HUMANO' ? Headset : c.quem === 'AGUARDANDO' ? Clock : CheckCheck;
  const cor = c.quem === 'IA' ? 'bg-purple-600' : c.quem === 'HUMANO' ? 'bg-green-600' : c.quem === 'AGUARDANDO' ? 'bg-amber-500' : 'bg-slate-400';
  const atrasada = c.quem === 'AGUARDANDO' && espera(c.aguardando_desde, now) > 30;
  const de = c.ultima?.direcao === 'OUT' ? (c.ultima.de === 'IARA' ? 'IARA: ' : c.ultima.de === 'OPERADOR' ? '✓✓ ' : '') : '';
  const onde = rede && c.responsavel ? ` · ${ondeCurto(c.responsavel)}` : '';
  return (
    <button onClick={onClick} aria-current={ativo || undefined}
      className={clsx('flex w-full items-center gap-3 border-b border-line/60 px-3 py-2.5 text-left transition', ativo ? 'bg-[#F0F2F5]' : 'hover:bg-slate-50')}>
      <span className="relative shrink-0">
        <Avatar name={nomeContato(c.contato)} seed={c.id} size={48} />
        <span className={clsx('absolute -bottom-0.5 -right-0.5 inline-flex size-5 items-center justify-center rounded-full text-white ring-2 ring-white', cor)}
          title={c.quem === 'IA' ? 'IA atendendo' : c.quem === 'HUMANO' ? 'Humano atendendo' : c.quem === 'AGUARDANDO' ? 'Aguardando humano' : 'Encerrada'}>
          <Icone className="size-3" />
        </span>
      </span>
      <span className="min-w-0 flex-1">
        <span className="flex items-baseline justify-between gap-2">
          <span className="truncate text-[15px] font-semibold text-ink">{nomeContato(c.contato)}</span>
          <span className={clsx('shrink-0 text-[11.5px]', c.nao_lidas ? 'font-bold' : 'text-subtle')} style={c.nao_lidas ? { color: WA_VERDE } : undefined}>
            {horaCurta(c.ultima?.em ?? c.em, now)}
          </span>
        </span>
        <span className="mt-0.5 flex items-center justify-between gap-2">
          <span className={clsx('truncate text-[13.5px]', c.ultima?.de === 'SISTEMA' ? 'italic text-subtle' : 'text-muted')}>{de}{previa(c.ultima?.texto ?? c.resumo) || '—'}</span>
          {c.nao_lidas > 0 && (
            <span className="inline-flex h-5 min-w-5 shrink-0 items-center justify-center rounded-full px-1.5 text-[11px] font-bold text-white" style={{ background: '#25D366' }}>
              {c.nao_lidas}
            </span>
          )}
        </span>
        <span className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[11.5px] font-semibold">
          {c.quem === 'IA' && <span className="inline-flex items-center gap-1 text-purple-700"><Bot className="size-3.5" />IA atendendo</span>}
          {c.quem === 'AGUARDANDO' && (
            <span className={clsx('inline-flex items-center gap-1', atrasada ? 'text-red-700' : 'text-amber-700')}>
              <Clock className="size-3.5" />Aguardando humano{onde} · {haQuanto(c.aguardando_desde, now)}
            </span>
          )}
          {c.quem === 'HUMANO' && (
            <span className="inline-flex items-center gap-1 text-green-700">
              <Headset className="size-3.5" />{c.comigo ? 'Você' : cleanLabel(c.atendente).split(' · ')[0] || 'Servidor'}{onde}
            </span>
          )}
          {c.quem === 'ENCERRADA' && <span className="inline-flex items-center gap-1 text-subtle"><CheckCheck className="size-3.5" />Encerrada</span>}
          <span className="font-medium" style={{ color: c.canal === 'WHATSAPP' ? WA_VERDE : undefined }}>
            <span className={c.canal === 'WHATSAPP' ? undefined : 'text-subtle'}>{CANAL[c.canal] ?? c.canal}</span>
          </span>
          {c.protocolo && <span className="font-medium text-subtle">{c.protocolo}</span>}
        </span>
      </span>
    </button>
  );
}

/* ─────────────────────────────────────── conversa aberta */

function ConversaPainel({ id, onVoltar, desktop, podeControlar, unidades }: {
  id: string; onVoltar: () => void; desktop: boolean; podeControlar: boolean; unidades: Controle['unidades'];
}) {
  const { can } = useSession();
  const qc = useQueryClient();
  const toast = useToast();
  const confirm = useConfirm();
  const now = useNow(30_000);
  const det = useRpc<any>('conversation_detail', { id }, { refetchInterval: 5_000 });
  const [texto, setTexto] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const [transferir, setTransferir] = useState(false);
  const total = det.data?.messages?.length ?? 0;

  // abrir (e cada mensagem nova com a conversa aberta) conta como lida pela equipe
  useEffect(() => {
    rpc('conversa_marcar_lida', { id }).then(() => qc.invalidateQueries({ queryKey: ['conversas_lista'] })).catch(() => {});
  }, [id, total, qc]);

  if (det.isLoading) return <div className="p-4"><SkeletonList rows={5} /></div>;
  if (det.error) {
    return (
      <div className="space-y-3 p-4">
        <ErrorState error={det.error} onRetry={() => det.refetch()} />
        <Button variant="secondary" icon={ArrowLeft} onClick={onVoltar}>Voltar à lista</Button>
      </div>
    );
  }
  const c = det.data.conversation;
  const mine = c.state === 'HUMAN_ACTIVE' && c.assigned_to_me;
  const podeAtender = can('conversations.takeover');
  const aberta = c.state !== 'CLOSED';

  /** `sair`: depois da ação a conversa deixa de ser deste perfil (a unidade devolveu à Secretaria) — fecha em vez de recarregar. */
  const act = async (fn: string, label: string, args: object = {}, sair?: () => void) => {
    setBusy(fn);
    try {
      await rpc(fn, { id, ...args });
      if (sair) sair();
      else await det.refetch();
      qc.invalidateQueries({ queryKey: ['conversas_lista'] });
      qc.invalidateQueries({ queryKey: ['conversas_controle'] });
      if (label) toast({ title: label, tone: 'success' });
      return true;
    } catch (e) {
      toast({ title: 'Ação não realizada', description: (e as Error).message, tone: 'error' });
      return false;
    } finally {
      setBusy(null);
    }
  };
  const enviar = async (e: FormEvent) => {
    e.preventDefault();
    const body = texto.trim();
    if (!body) return;
    setTexto('');
    if (!(await act('conversation_operator_message', '', { body }))) setTexto(body);
  };

  const quem = c.state === 'HUMAN_ACTIVE' ? (c.assigned_to_me ? 'Você está atendendo' : `Com ${cleanLabel(c.assigned).split(' · ')[0]}`)
    : c.state === 'HUMAN_PENDING' ? `Aguardando humano ${haQuanto(c.handoff_at, now) === 'agora' ? 'desde agora' : timeAgo(c.handoff_at, now)}` : c.state === 'CLOSED' ? 'Encerrada' : 'IA atendendo';

  return (
    <div className={clsx('flex min-h-0 flex-col', !desktop && 'h-full')}>
      <div className="flex items-center gap-3 border-b border-line bg-[#F0F2F5] px-3 py-2.5">
        {!desktop && (
          <button onClick={onVoltar} className="inline-flex size-10 items-center justify-center rounded-full hover:bg-black/5" aria-label="Voltar para a lista">
            <ArrowLeft className="size-5" />
          </button>
        )}
        <Avatar name={nomeContato(c.contact)} seed={c.id} size={42} />
        <div className="min-w-0 flex-1">
          <div className="truncate font-semibold leading-tight">{nomeContato(c.contact)}</div>
          <div className="truncate text-[12.5px]">
            <b className={clsx(c.state === 'HUMAN_PENDING' ? 'text-amber-700' : c.state === 'HUMAN_ACTIVE' ? 'text-green-700' : c.state === 'CLOSED' ? 'text-muted' : 'text-purple-700')}>{quem}</b>
            {c.responsible && <span className="text-muted"> · {c.responsible}</span>}
          </div>
          <div className="truncate text-[11.5px] text-subtle">{CANAL[c.channel] ?? c.channel}{c.phone ? ` · ${c.phone}` : ''}</div>
        </div>
        <Link to={`/conversas/${c.id}`} className="hidden size-10 shrink-0 items-center justify-center rounded-full text-ink-2 hover:bg-black/5 sm:inline-flex" aria-label="Detalhes da conversa" title="Detalhes (ferramentas, encaminhamentos)">
          <ExternalLink className="size-4.5" />
        </Link>
      </div>

      {podeAtender && aberta && (
        <div className="no-scrollbar flex gap-2 overflow-x-auto border-b border-line bg-white px-3 py-2 [&>button]:shrink-0">
          {!mine && (
            <Button size="sm" variant="purple" icon={Headset} loading={busy === 'conversation_takeover'} onClick={() => act('conversation_takeover', 'Conversa assumida — a IARA está pausada')}>
              Assumir
            </Button>
          )}
          {mine && (
            <Button size="sm" variant="secondary" icon={Undo2} loading={busy === 'conversation_release'} onClick={() => act('conversation_release', 'Conversa devolvida à IARA')}>
              Devolver à IARA
            </Button>
          )}
          <Button size="sm" variant="secondary" icon={Shuffle} onClick={() => setTransferir(true)}>
            {podeControlar ? 'Transferir' : 'Devolver à Secretaria'}
          </Button>
          <Button size="sm" variant="ghost" icon={XCircle} loading={busy === 'conversation_close'}
            onClick={async () => {
              if (await confirm({ title: 'Encerrar conversa?', body: 'Os protocolos vinculados seguem seus próprios status. Se a família escrever de novo, a conversa volta para a IARA.', confirm: 'Encerrar', tone: 'danger' }))
                act('conversation_close', 'Conversa encerrada');
            }}>
            Encerrar
          </Button>
        </div>
      )}

      <div className="min-h-0 flex-1 overflow-y-auto bg-[#EFEAE2] px-3 py-3">
        {(det.data.messages as ChatMessage[]).length ? <ChatThread messages={det.data.messages} perspective="operator" /> : <EmptyState compact title="Sem mensagens" />}
      </div>

      <div className="border-t border-line bg-[#F0F2F5] p-2.5">
        {mine ? (
          <form onSubmit={enviar} className="flex items-center gap-2">
            <input value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="Mensagem" aria-label="Resposta do servidor" maxLength={2000}
              className={clsx(inputCls, 'h-11 flex-1 rounded-full bg-white')} />
            <button type="submit" disabled={!texto.trim() || !!busy} aria-label="Enviar"
              className="inline-flex size-11 shrink-0 items-center justify-center rounded-full text-white transition active:scale-95 disabled:opacity-40" style={{ background: WA_VERDE }}>
              <SendHorizontal className="size-5" />
            </button>
          </form>
        ) : (
          <div className="flex items-center gap-2 px-1.5 py-1 text-[13px] text-muted">
            {c.state === 'CLOSED' ? <Lock className="size-4" /> : c.state === 'HUMAN_ACTIVE' ? <Headset className="size-4 text-green-700" /> : <Bot className="size-4 text-purple-700" />}
            {c.state === 'CLOSED' ? 'Conversa encerrada.'
              : c.state === 'HUMAN_ACTIVE' ? `Em atendimento por ${cleanLabel(c.assigned)}. Só quem assumiu responde.`
                : podeAtender ? 'Assuma para responder — a IARA pausa enquanto você atende.' : 'Somente leitura para o seu perfil.'}
            {c.identity_verified && <span className="ml-auto inline-flex items-center gap-1 text-green-700"><ShieldCheck className="size-3.5" />identidade verificada</span>}
          </div>
        )}
      </div>

      <TransferirSheet open={transferir} onClose={() => setTransferir(false)} podeControlar={podeControlar} unidades={unidades}
        atual={c.responsible} onTransferir={async (destino, motivo) => {
          const ok = podeControlar
            ? await act('conversation_transfer', 'Conversa transferida', { ...destino, motivo })
            : await act('conversation_transfer', 'Conversa devolvida à Secretaria', { ...destino, motivo }, () => { setTransferir(false); onVoltar(); });
          if (ok) setTransferir(false);
        }} busy={busy === 'conversation_transfer'} />
    </div>
  );
}

/* ─────────────────────────────────────── transferir */

function TransferirSheet({ open, onClose, podeControlar, unidades, atual, onTransferir, busy }: {
  open: boolean; onClose: () => void; podeControlar: boolean; unidades: Controle['unidades']; atual: string | null;
  onTransferir: (destino: { unit_id?: number; team?: string }, motivo: string) => void; busy: boolean;
}) {
  const [destino, setDestino] = useState<{ unit_id?: number; team?: string; rotulo: string } | null>(null);
  const [busca, setBusca] = useState('');
  const [motivo, setMotivo] = useState('');
  const achadas = useMemo(() => {
    const t = busca.trim().toLowerCase().normalize('NFD').replace(/\p{Diacritic}/gu, '');
    if (t.length < 2) return [];
    return unidades.filter((u) => u.nome.toLowerCase().normalize('NFD').replace(/\p{Diacritic}/gu, '').includes(t)).slice(0, 8);
  }, [busca, unidades]);
  const opcao = (key: string, ativo: boolean, onClick: () => void, children: ReactNode) => (
    <button key={key} onClick={onClick}
      className={clsx('flex w-full items-center gap-2 rounded-2xl px-3 py-2.5 text-left text-[14px] font-semibold ring-1 transition', ativo ? 'bg-green-50 text-green-900 ring-green-300' : 'bg-white ring-line hover:bg-slate-50')}>
      {children}
    </button>
  );
  return (
    <Sheet open={open} onClose={onClose} title={podeControlar ? 'Transferir conversa' : 'Devolver à Secretaria'}
      subtitle={atual ? `Hoje com: ${atual}. A família não precisa repetir nada — o histórico vai junto.` : 'O histórico vai junto; a família não precisa repetir nada.'}>
      <div className="space-y-4">
        <div>
          <div className="mb-1.5 text-[12px] font-bold uppercase tracking-wide text-subtle">Secretaria (SEDUC)</div>
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            {(podeControlar ? EQUIPES_SEDUC : EQUIPES_SEDUC.slice(0, 2)).map((e) =>
              opcao(e.v, destino?.team === e.v, () => setDestino({ team: e.v, rotulo: e.l }), <><Landmark className="size-4 shrink-0 text-blue-700" />{e.l}</>))}
          </div>
        </div>
        {podeControlar && (
          <div>
            <div className="mb-1.5 text-[12px] font-bold uppercase tracking-wide text-subtle">Unidade (secretaria da escola ou CMEI)</div>
            <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Nome da unidade" className={inputCls} aria-label="Buscar unidade" />
            <div className="mt-2 space-y-1.5">
              {achadas.map((u) => opcao(String(u.id), destino?.unit_id === u.id, () => setDestino({ unit_id: u.id, rotulo: u.nome }), <><Building2 className="size-4 shrink-0 text-orange-600" />{u.nome}</>))}
            </div>
          </div>
        )}
        <div>
          <div className="mb-1.5 text-[12px] font-bold uppercase tracking-wide text-subtle">Motivo</div>
          <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={3} maxLength={300} className={clsx(inputCls, 'h-auto py-2.5')}
            placeholder="Ex.: assunto de matrícula da unidade da criança" />
          <p className="mt-1 text-[12px] text-muted">Fica na conversa e na auditoria.</p>
        </div>
        <Button block size="lg" variant="purple" icon={Shuffle} disabled={!destino || motivo.trim().length < 5} loading={busy}
          onClick={() => destino && onTransferir(destino.unit_id ? { unit_id: destino.unit_id } : { team: destino.team }, motivo.trim())}>
          {destino ? `Transferir para ${destino.rotulo}` : 'Escolha o destino'}
        </Button>
      </div>
    </Sheet>
  );
}

/* ─────────────────────────────────────── controle da Secretaria */

function FaixaControle({ c, onAbrir }: { c?: Controle; onAbrir: () => void }) {
  if (!c) return null;
  const t = c.totais;
  const pills: { icon: typeof Bot; label: string; n: number; tone: string }[] = [
    { icon: Bot, label: 'Com a IA', n: t.ia, tone: 'bg-purple-50 text-purple-900 ring-purple-200' },
    { icon: Clock, label: 'Aguardando humano', n: t.aguardando, tone: 'bg-amber-50 text-amber-900 ring-amber-200' },
    { icon: Headset, label: 'Com humano', n: t.humano, tone: 'bg-green-50 text-green-900 ring-green-200' },
    { icon: AlertTriangle, label: `Esperando > ${c.limite_min} min`, n: t.atrasadas, tone: t.atrasadas ? 'bg-red-50 text-red-900 ring-red-200' : 'bg-white text-ink-2 ring-line' },
    { icon: Building2, label: 'Nas unidades', n: t.nas_unidades, tone: 'bg-white text-ink-2 ring-line' },
    { icon: Landmark, label: 'Na SEDUC', n: t.na_seduc, tone: 'bg-white text-ink-2 ring-line' },
  ];
  return (
    <div className="no-scrollbar -mx-4 flex items-center gap-2 overflow-x-auto px-4 py-0.5 sm:mx-0 sm:flex-wrap sm:px-0">
      <button onClick={onAbrir} className="inline-flex h-9 shrink-0 items-center gap-1.5 rounded-full bg-ink px-3.5 text-[13px] font-semibold text-white">
        <SlidersHorizontal className="size-4" /> Controle por unidade
      </button>
      {pills.map((p) => (
        <span key={p.label} className={clsx('inline-flex h-9 shrink-0 items-center gap-1.5 rounded-full px-3 text-[13px] font-semibold ring-1', p.tone)}>
          <p.icon className="size-4" /><b className="tabular">{fmtInt(p.n)}</b> {p.label}
        </span>
      ))}
    </div>
  );
}

function FaixaUnidade({ d }: { d: Lista }) {
  return (
    <div className="flex flex-wrap items-center gap-2 text-[13px] font-semibold">
      <span className="hidden text-ink-2 sm:inline">{d.unidade}:</span>
      <span className="inline-flex h-9 items-center gap-1.5 rounded-full bg-amber-50 px-3 text-amber-900 ring-1 ring-amber-200"><Clock className="size-4" /><b className="tabular">{fmtInt(d.contagem.aguardando ?? 0)}</b> aguardando a unidade</span>
      <span className="inline-flex h-9 items-center gap-1.5 rounded-full bg-green-50 px-3 text-green-900 ring-1 ring-green-200"><Headset className="size-4" /><b className="tabular">{fmtInt(d.contagem.humano ?? 0)}</b> em atendimento</span>
      <span className="text-[12px] font-medium text-muted">A Secretaria acompanha o tempo de resposta de cada unidade.</span>
    </div>
  );
}

function ControleSheet({ open, onClose, c, onFiltrar }: { open: boolean; onClose: () => void; c?: Controle; onFiltrar: (g: Grupo) => void }) {
  return (
    <Sheet open={open} onClose={onClose} size="lg" title="Controle das mensagens"
      subtitle={`Quem está com cada conversa que passou para humano. Em vermelho, quem espera há mais de ${c?.limite_min ?? 30} min. Toque numa linha para ver as conversas.`}>
      {!c ? <SkeletonList rows={4} /> : !c.responsaveis.length ? <EmptyState compact title="Nenhuma conversa com humano agora" body="Tudo com a IARA." /> : (
        <div className="divide-y divide-line overflow-hidden rounded-2xl ring-1 ring-line">
          {c.responsaveis.map((g) => (
            <button key={`${g.unit_id ?? 'seduc'}-${g.equipe}`} onClick={() => onFiltrar(g)}
              className={clsx('block w-full px-3.5 py-3 text-left transition hover:bg-slate-50', g.atrasadas > 0 && 'bg-red-50/50')}>
              <span className="flex items-center gap-2">
                {g.tipo === 'UNIDADE' ? <Building2 className="size-4.5 shrink-0 text-orange-600" /> : <Landmark className="size-4.5 shrink-0 text-blue-700" />}
                <span className="min-w-0 flex-1 truncate text-[14.5px] font-semibold">{maiuscula(g.rotulo)}</span>
                {g.atrasadas > 0 && (
                  <span className="shrink-0 rounded-full bg-red-100 px-2 py-0.5 text-[12px] font-bold text-red-800">
                    {g.atrasadas} {g.atrasadas === 1 ? 'atrasada' : 'atrasadas'}
                  </span>
                )}
              </span>
              <span className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-4">
                <Numero label="Aguardando" valor={fmtInt(g.aguardando)} />
                <Numero label="Com humano" valor={fmtInt(g.em_atendimento)} />
                <Numero label="Maior espera" valor={duracao(g.maior_espera_min)} alerta={g.atrasadas > 0} />
                <Numero label="Resposta média" valor={duracao(g.resposta_media_min)} />
              </span>
            </button>
          ))}
        </div>
      )}
    </Sheet>
  );
}

function Numero({ label, valor, alerta }: { label: string; valor: string; alerta?: boolean }) {
  return (
    <span className="rounded-xl bg-white px-2.5 py-1.5 ring-1 ring-line">
      <span className="block text-[10.5px] font-bold uppercase tracking-wide text-subtle">{label}</span>
      <span className={clsx('tabular block text-[15px] font-bold', alerta ? 'text-red-700' : 'text-ink')}>{valor}</span>
    </span>
  );
}

