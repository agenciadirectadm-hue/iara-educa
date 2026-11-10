// Central de pendências — peças compartilhadas: linha da lista, detalhe (checklist, conclusão, cobrança), atribuir tarefa,
// procedimento periódico, contador do menu e cartão do início.
import { useEffect, useState } from 'react';
import { Link } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import { AlarmClock, ArrowRight, Ban, Check, CheckCircle2, ClipboardList, Megaphone, Plus, RotateCcw, Send, Undo2 } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtDateTime, fmtInt } from '@/lib/format';
import { Badge, Button, Card, EmptyState, ErrorState, Field, MarcaSimulado, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { UnitSelect } from '@/components/escola';

export type Pendencia = {
  id: string; origem: 'AUTOMATICA' | 'ATRIBUIDA' | 'ROTINA'; tipo: string; modulo: string; titulo: string; detalhe?: string | null; quantidade?: number | null;
  prazo?: string | null; situacao: 'ABERTA' | 'CONCLUIDA' | 'CANCELADA'; rota?: string | null; checklist?: { item: string; feito: boolean; em?: string; por?: string }[] | null;
  atrasada: boolean; dias_atraso?: number | null; vence_hoje: boolean; no_prazo?: boolean | null; criada_em: string; concluida_em?: string | null;
  concluida_por?: string | null; conclusao?: string | null; atribuida_por?: string | null; procedimento?: string | null; prazo_regra?: string | null;
  posto: string; responsavel: string; papel: string; unidade?: string | null; setor?: string | null;
  ultima_cobranca?: { texto: string; autor: string; em: string } | null; simulado?: boolean;
};

export const ORIGEM: Record<Pendencia['origem'], { label: string; tone: 'gray' | 'purple' | 'blue' }> = {
  AUTOMATICA: { label: 'do sistema', tone: 'gray' },
  ATRIBUIDA: { label: 'da chefia', tone: 'purple' },
  ROTINA: { label: 'procedimento', tone: 'blue' },
};

const plural = (n: number, um: string, varios: string) => `${fmtInt(n)} ${n === 1 ? um : varios}`;

/** "atrasada há 3 dias", "vence hoje às 18h", "até 14/11". */
export function PrazoPend({ p }: { p: Pendencia }) {
  if (p.situacao === 'CONCLUIDA') {
    return p.no_prazo === false ? <Badge tone="amber">concluída fora do prazo</Badge> : <Badge tone="green" icon={Check}>concluída</Badge>;
  }
  if (p.situacao === 'CANCELADA') return <Badge tone="gray">cancelada</Badge>;
  if (!p.prazo) return <span className="text-muted">sem prazo</span>;
  if (p.atrasada) return <Badge tone="red" icon={AlarmClock}>{p.dias_atraso && p.dias_atraso > 0 ? `atrasada há ${plural(p.dias_atraso, 'dia', 'dias')}` : 'atrasada'}</Badge>;
  const d = new Date(p.prazo);
  if (p.vence_hoje) return <Badge tone="amber">vence hoje, {d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}</Badge>;
  return <span>até {fmtDate(p.prazo)}</span>;
}

function OrigemBadge({ o }: { o: Pendencia['origem'] }) {
  return <Badge tone={ORIGEM[o].tone}>{ORIGEM[o].label}</Badge>;
}

/** Lista de pendências, uma por linha; atrasada fica em vermelho. */
export function ListaPendencias({ itens, mostrarResponsavel, onAbrir, vazio }: {
  itens: Pendencia[]; mostrarResponsavel?: boolean; onAbrir: (id: string) => void; vazio?: string;
}) {
  if (!itens.length) return <EmptyState compact title={vazio ?? 'Nada pendente aqui.'} />;
  const colunas = mostrarResponsavel
    ? '170px minmax(260px,2fr) minmax(150px,1fr) 120px minmax(160px,1fr) 90px'
    : '170px minmax(280px,2fr) minmax(150px,1fr) 120px 110px';
  return (
    <Tabela colunas={colunas} largura={mostrarResponsavel ? 1060 : 900} rotulo="Pendências">
      <TCabecalho>
        <TCelula fixa>Prazo</TCelula><TCelula>Pendência</TCelula><TCelula>Área</TCelula><TCelula>Origem</TCelula>
        {mostrarResponsavel && <TCelula>Responsável</TCelula>}<TCelula>{mostrarResponsavel ? 'Cobrada' : ''}</TCelula>
      </TCabecalho>
      {itens.map((p) => (
        <TLinha key={p.id} onClick={() => onAbrir(p.id)} alerta={p.atrasada} rotulo={p.titulo}>
          <TCelula fixa livre><PrazoPend p={p} /></TCelula>
          <TCelula titulo={[p.titulo, p.detalhe].filter(Boolean).join(' — ')}>
            <span className="inline-flex items-center gap-1.5">
              {p.simulado && <MarcaSimulado />}
              <span className="font-semibold">{p.titulo}</span>
              {p.quantidade != null && p.quantidade > 1 && <span className="text-muted">· {fmtInt(p.quantidade)}</span>}
            </span>
          </TCelula>
          <TCelula>{p.modulo}</TCelula>
          <TCelula livre><OrigemBadge o={p.origem} /></TCelula>
          {mostrarResponsavel && <TCelula titulo={p.responsavel}>{p.responsavel}</TCelula>}
          <TCelula>
            {mostrarResponsavel
              ? (p.ultima_cobranca ? fmtDate(p.ultima_cobranca.em) : '—')
              : p.situacao === 'ABERTA' && p.rota && p.origem === 'AUTOMATICA'
                ? <span className="inline-flex items-center gap-1 font-semibold text-purple-700">Resolver<ArrowRight className="size-3.5" /></span>
                : p.situacao === 'ABERTA' ? <span className="font-semibold text-purple-700">Abrir</span> : null}
          </TCelula>
        </TLinha>
      ))}
    </Tabela>
  );
}

/** Detalhe de uma pendência: o que fazer, lista de conferência, conclusão e, para a chefia, cobrar, cancelar ou devolver. */
export function PendenciaSheet({ id, onClose }: { id: string | null; onClose: () => void }) {
  const toast = useToast();
  const qc = useQueryClient();
  const res = useRpc<any>('pend_item', { id }, { enabled: !!id, staleTime: 0 });
  const [nota, setNota] = useState('');
  const [msg, setMsg] = useState('');
  const [acao, setAcao] = useState<'' | 'COBRAR' | 'CANCELAR' | 'DEVOLVER'>('');
  const [busy, setBusy] = useState(false);
  useEffect(() => { setNota(''); setMsg(''); setAcao(''); }, [id]);
  const p = res.data as (Pendencia & { minha: boolean; pode_concluir: boolean; pode_cobrar: boolean; pode_cancelar: boolean; pode_devolver: boolean;
    eventos: { tipo: string; texto?: string; autor?: string; em: string }[] }) | undefined;
  const atualizar = () => {
    for (const k of ['pend_item', 'pend_minhas', 'pend_equipe', 'pend_contador', 'pend_rotinas']) qc.invalidateQueries({ queryKey: [k] });
  };
  const marcar = async (indice: number, feito: boolean) => {
    try { await rpc('pend_checklist', { id, indice, feito }); atualizar(); } catch (e) { toast({ title: 'Não marcado', description: (e as Error).message, tone: 'error' }); }
  };
  const concluir = async () => {
    setBusy(true);
    try {
      await rpc('pend_concluir', { id, nota });
      toast({ title: 'Pendência concluída', description: 'A chefia vê a conclusão com data e hora.', tone: 'success' });
      atualizar(); onClose();
    } catch (e) { toast({ title: 'Não concluída', description: (e as Error).message, tone: 'error' }); } finally { setBusy(false); }
  };
  const chefia = async () => {
    setBusy(true);
    try {
      await rpc('pend_chefia_acao', { id, acao, texto: msg });
      toast({ title: acao === 'COBRAR' ? 'Cobrança registrada' : acao === 'CANCELAR' ? 'Tarefa cancelada' : 'Devolvida para refazer',
        description: acao === 'COBRAR' ? 'Aparece para o responsável na central de pendências.' : undefined, tone: 'success' });
      setAcao(''); setMsg(''); atualizar();
      if (acao !== 'COBRAR') onClose();
    } catch (e) { toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' }); } finally { setBusy(false); }
  };
  const faltam = (p?.checklist ?? []).filter((i) => !i.feito).length;
  return (
    <Sheet open={!!id} onClose={onClose} size="lg" title={p?.titulo ?? 'Pendência'}
      subtitle={p ? `${p.modulo} · ${p.responsavel}${p.unidade ? ' · ' + p.unidade : p.setor ? ' · ' + p.setor : ''}` : undefined}
      footer={p?.pode_concluir ? (
        <Button block icon={CheckCircle2} loading={busy} disabled={faltam > 0} onClick={concluir}>
          {faltam > 0 ? `Marque os ${plural(faltam, 'item', 'itens')} da lista` : 'Concluir'}
        </Button>
      ) : p?.situacao === 'ABERTA' && p.origem === 'AUTOMATICA' && p.rota && p.minha ? (
        <Link to={p.rota} onClick={onClose} className="flex h-11 w-full items-center justify-center gap-2 rounded-2xl bg-purple-700 font-semibold text-white">
          Ir para a tela onde se resolve <ArrowRight className="size-4" />
        </Link>
      ) : undefined}>
      {res.isLoading ? <SkeletonList rows={4} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : p ? (
        <div className="space-y-4 text-[14px]">
          <div className="flex flex-wrap items-center gap-2">
            <PrazoPend p={p} /><OrigemBadge o={p.origem} />{p.simulado && <MarcaSimulado />}
            {p.prazo && <span className="text-muted">Prazo: {fmtDateTime(p.prazo)}</span>}
          </div>
          {p.detalhe && <p>{p.detalhe}</p>}
          {p.ultima_cobranca && p.situacao === 'ABERTA' && (
            <div className="rounded-2xl border border-amber-200 bg-amber-50 p-3">
              <div className="flex items-center gap-1.5 text-[12.5px] font-bold text-amber-800"><Megaphone className="size-4" />A chefia pediu atenção · {fmtDateTime(p.ultima_cobranca.em)}</div>
              <p className="mt-1">{p.ultima_cobranca.texto}</p>
              <p className="mt-0.5 text-[12.5px] text-muted">{p.ultima_cobranca.autor}</p>
            </div>
          )}
          {p.procedimento && (
            <div className="rounded-2xl bg-slate-50 p-3">
              <div className="text-[11px] font-bold uppercase tracking-wide text-subtle">O que fazer</div>
              <p className="mt-1 whitespace-pre-line">{p.procedimento}</p>
              {p.prazo_regra && <p className="mt-1 text-[12.5px] text-muted">Prazo: {p.prazo_regra}</p>}
            </div>
          )}
          {!!p.checklist?.length && (
            <div>
              <div className="mb-1 text-[11px] font-bold uppercase tracking-wide text-subtle">Lista de conferência</div>
              <ul className="space-y-1">
                {p.checklist.map((i, k) => (
                  <li key={k}>
                    <label className="flex items-start gap-2 rounded-xl px-2 py-1.5 hover:bg-slate-50">
                      <input type="checkbox" className="mt-1" checked={i.feito} disabled={!p.pode_concluir} onChange={(e) => marcar(k, e.target.checked)} />
                      <span className={i.feito ? 'text-muted line-through' : ''}>{i.item}</span>
                      {i.feito && i.em && <span className="ml-auto shrink-0 text-[12px] text-muted">{fmtDateTime(i.em)}</span>}
                    </label>
                  </li>
                ))}
              </ul>
            </div>
          )}
          {p.pode_concluir && (
            <Field label="Nota da conclusão (opcional)"><textarea className={inputCls + ' min-h-20 py-2'} value={nota} onChange={(e) => setNota(e.target.value)} maxLength={1000} /></Field>
          )}
          {p.situacao !== 'ABERTA' && (
            <div className="rounded-2xl bg-slate-50 p-3">
              <div className="font-semibold">{p.situacao === 'CANCELADA' ? 'Cancelada' : 'Concluída'} em {fmtDateTime(p.concluida_em!)}{p.concluida_por ? ` · ${p.concluida_por}` : ''}</div>
              {p.conclusao && <p className="mt-1">{p.conclusao}</p>}
            </div>
          )}
          {p.atribuida_por && <p className="text-[12.5px] text-muted">Atribuída por {p.atribuida_por} em {fmtDateTime(p.criada_em)}.</p>}
          {(p.pode_cobrar || p.pode_cancelar || p.pode_devolver) && (
            <div className="rounded-2xl border border-line p-3">
              <div className="mb-2 text-[11px] font-bold uppercase tracking-wide text-subtle">Chefia</div>
              <div className="flex flex-wrap gap-2">
                {p.pode_cobrar && <Button size="sm" variant={acao === 'COBRAR' ? 'primary' : 'secondary'} icon={Megaphone} onClick={() => setAcao('COBRAR')}>Cobrar</Button>}
                {p.pode_cancelar && <Button size="sm" variant={acao === 'CANCELAR' ? 'primary' : 'secondary'} icon={Ban} onClick={() => setAcao('CANCELAR')}>Cancelar tarefa</Button>}
                {p.pode_devolver && <Button size="sm" variant={acao === 'DEVOLVER' ? 'primary' : 'secondary'} icon={Undo2} onClick={() => setAcao('DEVOLVER')}>Devolver para refazer</Button>}
              </div>
              {acao && (
                <div className="mt-2 space-y-2">
                  <textarea className={inputCls + ' min-h-16 py-2'} value={msg} onChange={(e) => setMsg(e.target.value)} maxLength={1000}
                    placeholder={acao === 'COBRAR' ? 'Mensagem ao responsável (opcional)' : 'Motivo (obrigatório)'} />
                  <Button size="sm" icon={Send} loading={busy} disabled={acao !== 'COBRAR' && msg.trim().length < 5} onClick={chefia}>Registrar</Button>
                </div>
              )}
            </div>
          )}
          {!!p.eventos?.length && (
            <div>
              <div className="mb-1 text-[11px] font-bold uppercase tracking-wide text-subtle">Histórico</div>
              <ul className="space-y-1 text-[13px]">
                {p.eventos.map((ev, k) => (
                  <li key={k} className="flex gap-2"><span className="w-32 shrink-0 text-muted">{fmtDateTime(ev.em)}</span>
                    <span><b>{EVENTO[ev.tipo] ?? ev.tipo}</b>{ev.texto ? ` — ${ev.texto}` : ''}{ev.autor ? <span className="text-muted"> · {ev.autor}</span> : null}</span></li>
                ))}
              </ul>
            </div>
          )}
        </div>
      ) : null}
    </Sheet>
  );
}

const EVENTO: Record<string, string> = { CRIADA: 'Atribuída', COBRADA: 'Cobrada', ITEM: 'Lista', CONCLUIDA: 'Concluída', DEVOLVIDA: 'Devolvida', CANCELADA: 'Cancelada' };

/** Atribuir tarefa com prazo a alguém de uma unidade ou setor da equipe. */
export function AtribuirSheet({ open, onClose, grupo, nomeGrupo, postoInicial }: {
  open: boolean; onClose: () => void; grupo?: string; nomeGrupo?: string; postoInicial?: string;
}) {
  const toast = useToast();
  const qc = useQueryClient();
  const postos = useRpc<any>('pend_postos', { grupo }, { enabled: open });
  const [posto, setPosto] = useState(postoInicial ?? '');
  const [titulo, setTitulo] = useState('');
  const [detalhe, setDetalhe] = useState('');
  const [prazo, setPrazo] = useState('');
  const [lista, setLista] = useState('');
  const [busy, setBusy] = useState(false);
  useEffect(() => { if (open) setPosto(postoInicial ?? ''); }, [open, postoInicial]);
  const enviar = async () => {
    setBusy(true);
    try {
      await rpc('pend_atribuir', { posto, grupo, titulo, detalhe, prazo, checklist: lista.split('\n').map((s) => s.trim()).filter(Boolean) });
      toast({ title: 'Tarefa atribuída', description: 'Aparece na central de pendências do responsável.', tone: 'success' });
      for (const k of ['pend_equipe', 'pend_minhas', 'pend_contador']) qc.invalidateQueries({ queryKey: [k] });
      setTitulo(''); setDetalhe(''); setPrazo(''); setLista(''); onClose();
    } catch (e) { toast({ title: 'Não atribuída', description: (e as Error).message, tone: 'error' }); } finally { setBusy(false); }
  };
  return (
    <Sheet open={open} onClose={onClose} title="Atribuir tarefa" subtitle={nomeGrupo ? `Equipe: ${nomeGrupo}` : 'O responsável vê na central de pendências, com o prazo.'}
      footer={<Button block icon={Send} loading={busy} disabled={!posto || titulo.trim().length < 5 || !prazo} onClick={enviar}>Atribuir</Button>}>
      <div className="space-y-3">
        <Field label="Para quem">
          <select className={inputCls} value={posto} onChange={(e) => setPosto(e.target.value)}>
            <option value="">{postos.isLoading ? 'Carregando…' : 'Escolha…'}</option>
            {((postos.data?.postos ?? []) as any[]).map((x) => <option key={x.posto} value={x.posto}>{x.nome}{x.turmas ? ` · ${x.turmas}` : x.papel !== x.nome ? ` · ${x.papel}` : ''}</option>)}
          </select>
        </Field>
        <Field label="O que deve ser feito"><input className={inputCls} value={titulo} onChange={(e) => setTitulo(e.target.value)} maxLength={140} placeholder="Ex.: Conferir as fichas de matrícula do 1º ano" /></Field>
        <Field label="Orientações (opcional)"><textarea className={inputCls + ' min-h-20 py-2'} value={detalhe} onChange={(e) => setDetalhe(e.target.value)} maxLength={2000} /></Field>
        <Field label="Prazo"><input type="date" className={inputCls} value={prazo} onChange={(e) => setPrazo(e.target.value)} /></Field>
        <Field label="Lista de conferência (opcional)" hint="Um item por linha. Para concluir, o responsável marca todos.">
          <textarea className={inputCls + ' min-h-20 py-2'} value={lista} onChange={(e) => setLista(e.target.value)} />
        </Field>
      </div>
    </Sheet>
  );
}

const PERIODOS = [
  { value: 'SEMANAL', label: 'Toda semana' }, { value: 'QUINZENAL', label: 'A cada 15 dias' }, { value: 'MENSAL', label: 'Todo mês' },
  { value: 'BIMESTRAL', label: 'A cada bimestre' }, { value: 'SEMESTRAL', label: 'A cada semestre' }, { value: 'ANUAL', label: 'Todo ano' },
];
const DIAS_SEMANA = ['segunda', 'terça', 'quarta', 'quinta', 'sexta'];

/** Cadastro de procedimento periódico (SEDUC para a rede; direção para a própria unidade). */
export function RotinaSheet({ open, onClose, rotina, papeis, escopo }: {
  open: boolean; onClose: () => void; rotina?: any; papeis: { papel: string; rotulo: string; na_unidade: boolean }[]; escopo: 'UNIDADE' | 'REDE';
}) {
  const toast = useToast();
  const qc = useQueryClient();
  const [f, setF] = useState<any>({});
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    if (!open) return;
    setF(rotina ? { ...rotina, checklist: (rotina.checklist ?? []).join('\n') }
      : { titulo: '', procedimento: '', checklist: '', papel: papeis.find((p) => p.na_unidade)?.papel ?? '', alvo: escopo === 'UNIDADE' ? 'UNIDADE' : 'TODAS', periodicidade: 'MENSAL', dia: 1, prazo_dias: 5, ativo: true });
  }, [open, rotina, papeis, escopo]);
  const set = (k: string, v: any) => setF((x: any) => ({ ...x, [k]: v }));
  const papel = papeis.find((p) => p.papel === f.papel);
  const salvar = async (ativo = f.ativo) => {
    setBusy(true);
    try {
      const r = await rpc<any>('pend_rotina_salvar', { ...f, ativo, checklist: String(f.checklist ?? '').split('\n').map((s: string) => s.trim()).filter(Boolean) });
      toast({ title: ativo ? 'Procedimento salvo' : 'Procedimento desativado',
        description: r.geradas ? `${plural(r.geradas, 'pendência criada', 'pendências criadas')} para o período atual.` : 'As pendências aparecem no início de cada período.', tone: 'success' });
      for (const k of ['pend_rotinas', 'pend_minhas', 'pend_equipe', 'pend_contador']) qc.invalidateQueries({ queryKey: [k] });
      onClose();
    } catch (e) { toast({ title: 'Não salvo', description: (e as Error).message, tone: 'error' }); } finally { setBusy(false); }
  };
  const semanal = f.periodicidade === 'SEMANAL' || f.periodicidade === 'QUINZENAL';
  return (
    <Sheet open={open} onClose={onClose} size="lg" title={rotina ? 'Editar procedimento' : 'Novo procedimento periódico'}
      subtitle={escopo === 'UNIDADE' ? 'Para a equipe da sua unidade.' : 'Para as unidades ou um setor da SEDUC.'}
      footer={<div className="flex gap-2">
        {rotina?.ativo && <Button variant="secondary" icon={Ban} loading={busy} onClick={() => salvar(false)}>Desativar</Button>}
        {rotina && !rotina.ativo && <Button variant="secondary" icon={RotateCcw} loading={busy} onClick={() => salvar(true)}>Reativar</Button>}
        <Button block icon={Check} loading={busy} disabled={String(f.titulo ?? '').trim().length < 5 || String(f.procedimento ?? '').trim().length < 10 || !f.papel} onClick={() => salvar()}>Salvar</Button>
      </div>}>
      <div className="space-y-3">
        <Field label="Procedimento"><input className={inputCls} value={f.titulo ?? ''} onChange={(e) => set('titulo', e.target.value)} maxLength={140} placeholder="Ex.: Conferência mensal do estoque da cozinha" /></Field>
        <Field label="Como fazer"><textarea className={inputCls + ' min-h-24 py-2'} value={f.procedimento ?? ''} onChange={(e) => set('procedimento', e.target.value)} maxLength={2000} /></Field>
        <Field label="Lista de conferência" hint="Um item por linha. Para concluir, o responsável marca todos.">
          <textarea className={inputCls + ' min-h-24 py-2'} value={f.checklist ?? ''} onChange={(e) => set('checklist', e.target.value)} />
        </Field>
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="Quem cumpre">
            <select className={inputCls} value={f.papel ?? ''} onChange={(e) => set('papel', e.target.value)}>
              {escopo === 'REDE' && <optgroup label="Nas unidades">{papeis.filter((p) => p.na_unidade).map((p) => <option key={p.papel} value={p.papel}>{p.rotulo}</option>)}</optgroup>}
              {escopo === 'REDE' && <optgroup label="Na SEDUC">{papeis.filter((p) => !p.na_unidade).map((p) => <option key={p.papel} value={p.papel}>{p.rotulo}</option>)}</optgroup>}
              {escopo === 'UNIDADE' && papeis.map((p) => <option key={p.papel} value={p.papel}>{p.rotulo}</option>)}
            </select>
          </Field>
          {escopo === 'REDE' && papel?.na_unidade && (
            <Field label="Em quais unidades">
              <select className={inputCls} value={f.alvo ?? 'TODAS'} onChange={(e) => set('alvo', e.target.value)}>
                <option value="TODAS">Todas</option><option value="CMEI">Só os CMEIs</option><option value="ESCOLA">Só as escolas</option><option value="UNIDADE">Uma unidade</option>
              </select>
            </Field>
          )}
          {escopo === 'REDE' && papel?.na_unidade && f.alvo === 'UNIDADE' && (
            <Field label="Unidade">
              <UnitSelect className="w-full" todas={null} value={f.unit_id ? Number(f.unit_id) : null} onChange={(id) => set('unit_id', id)} />
            </Field>
          )}
          <Field label="Repetição">
            <select className={inputCls} value={f.periodicidade} onChange={(e) => set('periodicidade', e.target.value)}>{PERIODOS.map((p) => <option key={p.value} value={p.value}>{p.label}</option>)}</select>
          </Field>
          <Field label={semanal ? 'Dia da semana' : 'Dia do início (do mês)'}>
            <select className={inputCls} value={f.dia ?? 1} onChange={(e) => set('dia', Number(e.target.value))}>
              {semanal ? DIAS_SEMANA.map((d, i) => <option key={d} value={i + 1}>{d}</option>) : Array.from({ length: 28 }, (_, i) => <option key={i} value={i + 1}>dia {i + 1}</option>)}
            </select>
          </Field>
          <Field label="Prazo para cumprir (dias)"><input type="number" min={1} max={60} className={inputCls} value={f.prazo_dias ?? 5} onChange={(e) => set('prazo_dias', Number(e.target.value))} /></Field>
        </div>
      </div>
    </Sheet>
  );
}

/** Contador de pendências do usuário (menu e início). */
export function usePendContador() {
  const { can } = useSession();
  return useRpc<{ abertas: number; atrasadas: number; hoje: number; equipe_atrasadas: number | null }>('pend_contador', {},
    { enabled: can('pend.read'), staleTime: 60_000, refetchInterval: 5 * 60_000 });
}

/** Número ao lado de "Pendências" na barra: atrasadas em vermelho; senão, as em aberto. */
export function ContadorNav({ mini }: { mini?: boolean }) {
  const c = usePendContador();
  const d = c.data;
  if (!d) return null;
  const n = d.atrasadas || d.abertas;
  if (!n) return null;
  const vermelho = d.atrasadas > 0;
  const titulo = vermelho ? `${plural(d.atrasadas, 'atrasada', 'atrasadas')} de ${plural(d.abertas, 'em aberto', 'em aberto')}` : `${plural(d.abertas, 'pendência em aberto', 'pendências em aberto')}`;
  const txt = n > 99 ? '99+' : String(n);
  return mini ? (
    <span title={titulo} className={'absolute -right-2.5 -top-1.5 min-w-[18px] rounded-full px-1 text-center text-[10px] font-bold leading-[18px] text-white ' + (vermelho ? 'bg-red-600' : 'bg-slate-500')}>{txt}</span>
  ) : (
    <span title={titulo} className={'relative ml-auto rounded-full px-2 text-[11.5px] font-bold leading-5 ' + (vermelho ? 'bg-red-600 text-white' : 'bg-slate-200 text-ink-2')}>{txt}</span>
  );
}

/** Cartão do início: o que o servidor tem a cumprir hoje. */
export function PendenciasCartao() {
  const c = usePendContador();
  const d = c.data;
  if (!d) return null;
  const nada = d.abertas === 0 && !d.equipe_atrasadas;
  return (
    <Link to="/pendencias" className={'mb-4 flex flex-wrap items-center gap-x-4 gap-y-1 rounded-2xl px-4 py-3 ring-1 transition ' +
      (d.atrasadas > 0 ? 'bg-red-50 ring-red-200 hover:ring-red-300' : 'bg-white ring-line hover:ring-purple-200')}>
      <span className="inline-flex items-center gap-2 font-semibold"><ClipboardList className="size-5 text-purple-700" />
        {nada ? 'Nenhuma pendência sua agora' : d.abertas === 0 ? 'Nenhuma pendência sua' : `Você tem ${plural(d.abertas, 'pendência', 'pendências')}`}
      </span>
      {d.atrasadas > 0 && <Badge tone="red" icon={AlarmClock}>{plural(d.atrasadas, 'atrasada', 'atrasadas')}</Badge>}
      {d.hoje > 0 && <Badge tone="amber">{plural(d.hoje, 'vence hoje', 'vencem hoje')}</Badge>}
      {!!d.equipe_atrasadas && <span className="text-[13px] text-muted">Equipe: {plural(d.equipe_atrasadas, 'atrasada', 'atrasadas')}</span>}
      <span className="ml-auto inline-flex items-center gap-1 text-[13px] font-semibold text-purple-700">Central de pendências<ArrowRight className="size-4" /></span>
    </Link>
  );
}

export function BotaoAtribuir({ onClick }: { onClick: () => void }) {
  return <Button icon={Plus} onClick={onClick}>Atribuir tarefa</Button>;
}

export function CardLista({ children }: { children: React.ReactNode }) {
  return <Card className="overflow-hidden">{children}</Card>;
}
