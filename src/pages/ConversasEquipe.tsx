import { useEffect, useMemo, useState, type FormEvent, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { Link, useSearchParams } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import {
  AlertTriangle, ArrowLeft, Bot, Building2, CheckCheck, Clock, ExternalLink, Globe, Headset, Landmark, Lock, MessageCircle, MessageSquare, Search,
  SendHorizontal, ShieldCheck, Shuffle, SlidersHorizontal, Undo2, X, XCircle,
} from 'lucide-react';
import { rpc } from '@/lib/api';
import { useDebounced, useIsDesktop, useNow, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { cleanLabel, fmtInt, timeAgo } from '@/lib/format';
import { Avatar, Button, Card, EmptyState, ErrorState, MarcaSimulado, Simulado, SkeletonList, inputCls } from '@/components/ui';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
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
// simulação não se escreve: a bandeirinha sinaliza (MarcaSimulado)
const CANAL: Record<string, string> = { WHATSAPP: 'WhatsApp', WHATSAPP_SIMULADO: 'WhatsApp', PORTAL: 'Portal' };
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

  const rede = d?.escopo === 'REDE';
  const dividido = desktop && !!sel;
  // uma conversa por linha: no celular só o essencial; no computador, com protocolo quando nenhuma conversa está aberta ao lado
  const colunas = !desktop ? '40px minmax(0,1fr) auto'
    : dividido ? '40px minmax(130px,1.1fr) minmax(130px,1fr) minmax(100px,1.5fr) 92px'
      : '40px minmax(170px,1.15fr) minmax(190px,1fr) minmax(200px,2.4fr) 128px 104px';

  return (
    <div>
      {rede && <FaixaControle c={controle.data} onAbrir={() => setControleAberto(true)} />}
      {d?.escopo === 'UNIDADE' && <FaixaUnidade d={d} />}

      <Card className={clsx('mt-3 overflow-hidden lg:h-[74dvh] lg:min-h-[540px]', dividido ? 'lg:grid lg:grid-cols-[minmax(0,1.3fr)_minmax(400px,1fr)]' : 'lg:flex lg:flex-col')}>
        <div className="flex min-h-0 flex-1 flex-col lg:border-r lg:border-line">
          <div className="flex flex-wrap items-center gap-2 border-b border-line bg-white p-3">
            <div className="relative min-w-[220px] flex-1">
              <Search className="pointer-events-none absolute left-3.5 top-1/2 size-4.5 -translate-y-1/2 text-subtle" />
              <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Pesquisar contato, assunto ou telefone" aria-label="Pesquisar conversa"
                className={clsx(inputCls, 'h-10 rounded-full bg-slate-100 pl-10 ring-0')} />
              {q && <button className="absolute right-3 top-1/2 -translate-y-1/2" onClick={() => setQ('')} aria-label="Limpar"><X className="size-4 text-subtle" /></button>}
            </div>
            <div className="no-scrollbar flex max-w-full gap-1.5 overflow-x-auto">
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
              {resp && (
                <button onClick={() => setResp(null)} className="inline-flex h-8 max-w-[260px] shrink-0 items-center gap-1.5 rounded-full bg-blue-50 px-3 text-[12.5px] font-semibold text-blue-900 ring-1 ring-blue-200">
                  <span className="truncate">Com: {resp.rotulo}</span><X className="size-3.5 shrink-0" />
                </button>
              )}
            </div>
          </div>
          {lista.isLoading ? <div className="p-3"><SkeletonList rows={6} /></div> : lista.error ? <div className="p-3"><ErrorState error={lista.error} onRetry={() => lista.refetch()} /></div>
            : !d?.itens.length ? <EmptyState compact title="Nenhuma conversa neste filtro" body={d?.escopo === 'UNIDADE' ? 'Quando a IARA encaminhar uma conversa para a unidade, ela aparece aqui.' : undefined} />
              : (
                <Tabela colunas={colunas} largura={!desktop ? 0 : dividido ? 560 : 880} rotulo="Conversas" className="min-h-0 flex-1 overflow-y-auto bg-white">
                  {desktop && (
                    <TCabecalho>
                      <span /><span>Contato</span><span>{rede ? 'Com quem está' : 'Atendimento'}</span><span>Última mensagem</span>
                      {!dividido && <span>Protocolo</span>}<span className="text-right">Espera · hora</span>
                    </TCabecalho>
                  )}
                  {d.itens.map((c) => <Linha key={c.id} c={c} ativo={c.id === sel} rede={rede} now={now} desktop={desktop} dividido={dividido} onClick={() => abrir(c.id)} />)}
                </Tabela>
              )}
          <p className="flex flex-wrap items-center gap-x-3 gap-y-1 border-t border-line bg-white px-3 py-2 text-[11.5px] text-muted">
            <span className="inline-flex items-center gap-1.5"><span className="inline-flex rounded-full bg-red-500 p-[2px]"><span className="block size-2.5 rounded-full bg-slate-300 ring-2 ring-white" /></span>atendimento humano</span>
            <span className="inline-flex items-center gap-1"><Clock className="size-3 text-amber-600" />aguardando</span>
            <span className="inline-flex items-center gap-1"><Headset className="size-3 text-green-700" />em atendimento</span>
            <span className="inline-flex items-center gap-1"><Bot className="size-3 text-purple-700" />IARA</span>
            <span className="inline-flex items-center gap-1"><MarcaSimulado />simulação</span>
          </p>
        </div>
        {dividido && <ConversaPainel key={sel} id={sel!} onVoltar={() => abrir(null)} desktop podeControlar={!!d?.pode_controlar} unidades={controle.data?.unidades ?? []} />}
      </Card>
      {!desktop && sel && (
        <TelaCheia>
          <ConversaPainel key={sel} id={sel} onVoltar={() => abrir(null)} desktop={false} podeControlar={!!d?.pode_controlar} unidades={controle.data?.unidades ?? []} />
        </TelaCheia>
      )}

      {rede && (
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

/** Canal ao lado do nome: WhatsApp (verde) ou portal; a simulação é a bandeirinha. */
function Canal({ canal }: { canal: string }) {
  return (
    <span className="ml-1.5 inline-flex items-center gap-1 align-middle">
      {canal === 'PORTAL' ? <Globe className="size-3.5 text-subtle" aria-label="Portal" /> : <MessageCircle className="size-3.5" style={{ color: WA_VERDE }} aria-label="WhatsApp" />}
      {canal === 'WHATSAPP_SIMULADO' && <MarcaSimulado titulo="Simulação — conversa de demonstração" />}
    </span>
  );
}

/**
 * Uma conversa por linha. Atendimento humano = borda vermelha no avatar (o selo pequeno diz se está aguardando ou em atendimento);
 * a IARA é o selo roxo. A coluna seguinte diz com quem está; a última, há quanto tempo a família espera (vermelho acima do limite).
 */
function Linha({ c, ativo, rede, now, desktop, dividido, onClick }: {
  c: Item; ativo: boolean; rede: boolean; now: number; desktop: boolean; dividido: boolean; onClick: () => void;
}) {
  const nome = nomeContato(c.contato);
  const humano = c.quem === 'AGUARDANDO' || c.quem === 'HUMANO';
  const Icone = c.quem === 'IA' ? Bot : c.quem === 'HUMANO' ? Headset : c.quem === 'AGUARDANDO' ? Clock : CheckCheck;
  const cor = c.quem === 'IA' ? 'bg-purple-600' : c.quem === 'HUMANO' ? 'bg-green-600' : c.quem === 'AGUARDANDO' ? 'bg-amber-500' : 'bg-slate-400';
  const atrasada = c.quem === 'AGUARDANDO' && espera(c.aguardando_desde, now) > 30;
  const de = c.ultima?.direcao === 'OUT' ? (c.ultima.de === 'IARA' ? 'IARA: ' : c.ultima.de === 'OPERADOR' ? '✓✓ ' : '') : '';
  const onde = c.responsavel ? ondeCurto(c.responsavel) : null;
  const atendente = c.comigo ? 'Você' : cleanLabel(c.atendente).split(' · ')[0] || 'Servidor';
  const comQuem = c.quem === 'IA' ? 'IARA'
    : c.quem === 'HUMANO' ? (rede && onde ? `${atendente} · ${onde}` : atendente)
      : c.quem === 'AGUARDANDO' ? (rede ? onde ?? 'Secretaria' : 'Ninguém assumiu ainda') : 'Encerrada';
  const corQuem = c.quem === 'IA' ? 'text-purple-700' : c.quem === 'HUMANO' ? 'text-green-700' : c.quem === 'AGUARDANDO' ? (atrasada ? 'text-red-700' : 'text-amber-700') : 'text-subtle';
  const IconeQuem = c.quem === 'IA' ? Bot : c.quem === 'HUMANO' ? Headset : c.quem === 'AGUARDANDO' ? (c.responsavel?.unit_id ? Building2 : Landmark) : CheckCheck;
  const texto = previa(c.ultima?.texto ?? c.resumo) || '—';
  const estado = c.quem === 'IA' ? 'IARA atendendo' : c.quem === 'HUMANO' ? 'em atendimento humano' : c.quem === 'AGUARDANDO' ? 'aguardando atendimento humano' : 'encerrada';
  return (
    <TLinha onClick={onClick} ativo={ativo} rotulo={`${nome}, ${estado}${onde ? `, ${onde}` : ''}`}>
      <TCelula livre>
        <span className={clsx('relative inline-flex rounded-full p-[2px]', humano && 'bg-red-500')} title={estado}>
          <Avatar name={nome} seed={c.id} size={30} />
          <span className={clsx('absolute -bottom-1 -right-1 inline-flex size-4 items-center justify-center rounded-full text-white ring-2 ring-white', cor)}>
            <Icone className="size-2.5" />
          </span>
        </span>
      </TCelula>
      <TCelula titulo={desktop ? nome : `${nome} · ${comQuem}`}>
        <span className="font-semibold text-ink">{nome}</span>
        <Canal canal={c.canal} />
        {!desktop && <span className={clsx('text-[12.5px]', corQuem)}> · {comQuem}</span>}
      </TCelula>
      {desktop && (
        <TCelula titulo={comQuem} className={clsx('text-[13px] font-semibold', corQuem)}>
          <IconeQuem className="mr-1 inline size-3.5 align-[-2px]" />{comQuem}
        </TCelula>
      )}
      {desktop && <TCelula titulo={`${de}${texto}`} className={c.ultima?.de === 'SISTEMA' ? 'italic text-subtle' : 'text-muted'}>{de}{texto}</TCelula>}
      {desktop && !dividido && <TCelula className="text-[12.5px] text-subtle">{c.protocolo ?? '—'}</TCelula>}
      <TCelula livre className="flex items-center justify-end gap-1.5">
        {c.quem === 'AGUARDANDO'
          ? <span className={clsx('inline-flex items-center gap-0.5 text-[12px] font-bold', atrasada ? 'text-red-700' : 'text-amber-700')} title={`Aguardando há ${haQuanto(c.aguardando_desde, now)}`}>
              <Clock className="size-3" />{haQuanto(c.aguardando_desde, now)}
            </span>
          : <span className={clsx('text-[12px]', c.nao_lidas ? 'font-bold' : 'text-subtle')} style={c.nao_lidas ? { color: WA_VERDE } : undefined}>{horaCurta(c.ultima?.em ?? c.em, now)}</span>}
        {c.nao_lidas > 0 && (
          <span className="inline-flex h-5 min-w-5 items-center justify-center rounded-full px-1.5 text-[11px] font-bold text-white" style={{ background: '#25D366' }}>{c.nao_lidas}</span>
        )}
      </TCelula>
    </TLinha>
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
        <span className={clsx('inline-flex shrink-0 rounded-full p-[2px]', (c.state === 'HUMAN_PENDING' || c.state === 'HUMAN_ACTIVE') && 'bg-red-500')}
          title={c.state === 'HUMAN_PENDING' || c.state === 'HUMAN_ACTIVE' ? 'Atendimento humano' : undefined}>
          <Avatar name={nomeContato(c.contact)} seed={c.id} size={40} />
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex min-w-0 items-center gap-1 font-semibold leading-tight">
            <span className="truncate">{nomeContato(c.contact)}</span>
            {c.channel === 'WHATSAPP_SIMULADO' && <Simulado detail="Conversa de demonstração: nenhuma mensagem real é enviada." />}
          </div>
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
    <Sheet open={open} onClose={onClose} size="xl" title="Controle das mensagens"
      subtitle={`Quem está com cada conversa que passou para humano. Em vermelho, quem tem família esperando há mais de ${c?.limite_min ?? 30} min. Toque numa linha para ver as conversas.`}>
      {!c ? <SkeletonList rows={4} /> : !c.responsaveis.length ? <EmptyState compact title="Nenhuma conversa com humano agora" body="Tudo com a IARA." /> : (
        <Tabela colunas="minmax(230px,1fr) 96px 104px 92px 112px 124px" largura={760} rotulo="Controle por unidade e equipe" className="rounded-2xl ring-1 ring-line">
          <TCabecalho>
            <span>Responsável</span><span className="text-right">Aguardando</span><span className="text-right">Com humano</span>
            <span className="text-right">Atrasadas</span><span className="text-right">Maior espera</span><span className="text-right">Resposta média</span>
          </TCabecalho>
          {c.responsaveis.map((g) => (
            <TLinha key={`${g.unit_id ?? 'seduc'}-${g.equipe}`} onClick={() => onFiltrar(g)} alerta={g.atrasadas > 0} rotulo={`${maiuscula(g.rotulo)}: ver conversas`}>
              <TCelula fixa titulo={maiuscula(g.rotulo)} className="font-semibold">
                {g.tipo === 'UNIDADE' ? <Building2 className="mr-1.5 inline size-4 align-[-3px] text-orange-600" /> : <Landmark className="mr-1.5 inline size-4 align-[-3px] text-blue-700" />}
                {maiuscula(g.rotulo)}
              </TCelula>
              <TCelula className="text-right tabular">{fmtInt(g.aguardando)}</TCelula>
              <TCelula className="text-right tabular">{fmtInt(g.em_atendimento)}</TCelula>
              <TCelula className={clsx('text-right tabular', g.atrasadas > 0 && 'font-bold text-red-700')}>{fmtInt(g.atrasadas)}</TCelula>
              <TCelula className={clsx('text-right tabular', g.atrasadas > 0 && 'font-semibold text-red-700')}>{duracao(g.maior_espera_min)}</TCelula>
              <TCelula className="text-right tabular">{duracao(g.resposta_media_min)}</TCelula>
            </TLinha>
          ))}
        </Tabela>
      )}
    </Sheet>
  );
}
