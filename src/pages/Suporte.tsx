import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { Crown, Headset, Hourglass, Inbox, Lock, Monitor, Plus, Send, Star, Trash2 } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDateTime, fmtInt, timeAgo } from '@/lib/format';
import { Badge, Button, Card, Chip, EmptyState, ErrorState, Field, Kpi, MarcaSimulado, PageHeader, Segmented, Simulado, SkeletonList, Tabs, inputCls } from '@/components/ui';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { Sheet, useToast } from '@/components/overlays';

const CATEGORIA: Record<string, string> = {
  ACESSO_SENHA: 'Acesso ao sistema', SISTEMA_IARA: 'Sistema IARA Educa', WHATSAPP: 'WhatsApp da IARA', EQUIPAMENTO: 'Computador ou equipamento',
  REDE_INTERNET: 'Rede e internet', IMPRESSORA: 'Impressora', DADOS_CADASTRO: 'Dados e cadastro', MELHORIA: 'Sugestão de melhoria', OUTRO: 'Outro assunto',
};
const SITUACAO: Record<string, { label: string; tone: 'gray' | 'blue' | 'amber' | 'green' | 'red' | 'purple' }> = {
  ABERTO: { label: 'Aberto', tone: 'red' }, EM_ATENDIMENTO: { label: 'Em atendimento', tone: 'blue' }, AGUARDANDO_SOLICITANTE: { label: 'Aguardando você', tone: 'amber' },
  RESOLVIDO: { label: 'Resolvido', tone: 'green' }, CANCELADO: { label: 'Cancelado', tone: 'gray' },
};
const PRIORIDADE: Record<string, { label: string; tone: 'gray' | 'blue' | 'amber' | 'red' }> = {
  BAIXA: { label: 'Baixa', tone: 'gray' }, NORMAL: { label: 'Normal', tone: 'blue' }, ALTA: { label: 'Alta', tone: 'amber' }, URGENTE: { label: 'Urgente', tone: 'red' },
};
const anydeskFmt = (id?: string | null) => (id ? id.replace(/^(\d{1,3})(\d{3})(\d{3})(\d*)$/, '$1 $2 $3 $4').trim() : '');

function useRecarregar() {
  const qc = useQueryClient();
  return () => ['suporte_painel', 'suporte_detalhe', 'suporte_anydesk'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
}

/** Suporte técnico: demandas com protocolo e prazo, “fale com o master” e AnyDesk das unidades (só o código, nunca a senha). */
export default function Suporte() {
  const { me } = useSession();
  const [aba, setAba] = useState<'demandas' | 'anydesk'>('demandas');
  const [canal, setCanal] = useState('');
  const [todos, setTodos] = useState(false);
  const [aberto, setAberto] = useState<string | null>(null);
  const [nova, setNova] = useState<'DEMANDA' | 'MASTER' | null>(null);
  const res = useRpc<any>('suporte_painel', { canal: canal || null, todos }, { refetchInterval: 60_000 });
  const c = res.data?.contagem;
  return (
    <div>
      <PageHeader eyebrow={me?.unit?.name ?? 'SEDUC · Diretoria de Inovação Educacional'}
        title={<span className="inline-flex items-center gap-2">Suporte técnico<Simulado detail="Demandas e códigos de AnyDesk de demonstração." /></span>}
        subtitle="Abra uma demanda, acompanhe o atendimento e fale com o administrador do sistema. O suporte nunca pede senha: no AnyDesk, você aceita a conexão na tela."
        actions={<>
          <Button icon={Plus} onClick={() => setNova('DEMANDA')}>Nova demanda</Button>
          <Button variant="secondary" icon={Crown} onClick={() => setNova('MASTER')}>Fale com o master</Button>
        </>} />
      {res.isLoading ? <SkeletonList rows={3} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
          <Kpi compact icon={Inbox} tone="blue" label={res.data.atende ? 'Demandas em aberto' : 'Minhas demandas em aberto'} value={fmtInt(c?.abertos)} sub={`${fmtInt(c?.novos)} sem atendimento`} />
          <Kpi compact icon={Hourglass} tone="red" label="Prazo vencido" value={fmtInt(c?.vencidos)} />
          <Kpi compact icon={Crown} tone="purple" label="Fale com o master" value={fmtInt(c?.master)} onClick={() => setCanal(canal === 'MASTER' ? '' : 'MASTER')} />
          <Kpi compact icon={Headset} tone="green" label="Resolvidas em 30 dias" value={fmtInt(c?.resolvidos_30d)} />
          <Kpi compact icon={Star} tone="amber" label="Avaliação média" value={c?.avaliacao != null ? String(c.avaliacao).replace('.', ',') : '—'} />
        </div>
      )}
      <Tabs className="mt-4" value={aba} onChange={setAba} items={[{ value: 'demandas', label: 'Demandas' }, { value: 'anydesk', label: 'AnyDesk das unidades' }]} />
      {aba === 'anydesk' ? <AnyDesk /> : (
        <div className="mt-3 space-y-3">
          <div className="flex flex-wrap gap-2">
            <Chip active={canal === ''} onClick={() => setCanal('')}>Todas</Chip>
            <Chip active={canal === 'DEMANDA'} onClick={() => setCanal('DEMANDA')}>Demandas</Chip>
            <Chip active={canal === 'MASTER'} onClick={() => setCanal('MASTER')}>Fale com o master</Chip>
            <Chip active={todos} onClick={() => setTodos(!todos)}>Incluir antigas</Chip>
          </div>
          <Card className="overflow-hidden">
            {!res.data?.itens?.length ? <EmptyState compact title="Nenhuma demanda" body="Use “Nova demanda” para pedir ajuda." /> : (
              <Tabela colunas="130px minmax(220px,2fr) minmax(130px,1fr) 170px 100px 150px 120px" largura={1080} rotulo="Demandas de suporte">
                <TCabecalho><TCelula fixa>Protocolo</TCelula><TCelula>Assunto</TCelula><TCelula>Unidade/setor</TCelula><TCelula>Categoria</TCelula><TCelula>Prioridade</TCelula><TCelula>Situação</TCelula><TCelula>Aberta</TCelula></TCabecalho>
                {(res.data.itens as any[]).map((x) => (
                  <TLinha key={x.id} onClick={() => setAberto(x.id)} alerta={x.vencido || x.prioridade === 'URGENTE' && x.situacao === 'ABERTO'} rotulo={x.titulo}>
                    <TCelula fixa className="font-semibold">{x.protocolo}{x.is_demo && <MarcaSimulado className="ml-1" />}</TCelula>
                    <TCelula titulo={x.titulo}>{x.canal === 'MASTER' && <Crown className="mr-1 inline size-3.5 text-purple-700" aria-label="fale com o master" />}{x.titulo}</TCelula>
                    <TCelula titulo={x.unidade ?? x.setor}>{x.unidade ?? x.setor ?? '—'}</TCelula>
                    <TCelula>{CATEGORIA[x.categoria]}</TCelula>
                    <TCelula livre><Badge tone={PRIORIDADE[x.prioridade]?.tone}>{PRIORIDADE[x.prioridade]?.label}</Badge></TCelula>
                    <TCelula livre><Badge tone={SITUACAO[x.situacao]?.tone}>{SITUACAO[x.situacao]?.label}</Badge>{x.vencido && <span className="ml-1 text-[11.5px] font-semibold text-red-700">vencido</span>}</TCelula>
                    <TCelula>{timeAgo(x.created_at)}</TCelula>
                  </TLinha>
                ))}
              </Tabela>
            )}
          </Card>
        </div>
      )}
      <NovaDemanda canal={nova} anydesk={res.data?.anydesk_unidade ?? []} onClose={() => setNova(null)} onCriada={(id) => { setNova(null); setAberto(id); }} />
      <DemandaSheet id={aberto} onClose={() => setAberto(null)} />
    </div>
  );
}

function NovaDemanda({ canal, anydesk, onClose, onCriada }: { canal: 'DEMANDA' | 'MASTER' | null; anydesk: any[]; onClose: () => void; onCriada: (id: string) => void }) {
  const toast = useToast();
  const recarregar = useRecarregar();
  const [categoria, setCategoria] = useState('SISTEMA_IARA');
  const [prioridade, setPrioridade] = useState('NORMAL');
  const [titulo, setTitulo] = useState('');
  const [descricao, setDescricao] = useState('');
  const [any, setAny] = useState('');
  const [contato, setContato] = useState('');
  const [busy, setBusy] = useState(false);
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('suporte_abrir', { canal, categoria: canal === 'MASTER' && categoria === 'SISTEMA_IARA' ? 'MELHORIA' : categoria, prioridade, titulo, descricao, anydesk_id: any || null, contato });
      toast({ title: `Demanda ${r.protocolo} aberta`, description: 'Acompanhe por aqui; você é avisado(a) a cada resposta.', tone: 'success' });
      setTitulo(''); setDescricao(''); setAny('');
      recarregar();
      onCriada(r.id);
    } catch (e) {
      toast({ title: 'Não aberta', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!canal} onClose={onClose} title={canal === 'MASTER' ? 'Fale com o master' : 'Nova demanda de suporte'}
      subtitle={canal === 'MASTER' ? 'Mensagem direta ao administrador do sistema: sugestões, decisões e problemas que a unidade não resolveu.' : 'Descreva o problema; o suporte responde dentro do prazo da prioridade.'}
      footer={<Button block size="lg" icon={Send} loading={busy} disabled={titulo.trim().length < 5 || descricao.trim().length < 15} onClick={enviar}>Enviar</Button>}>
      <div className="space-y-4 pt-1">
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="Categoria"><select value={categoria} onChange={(e) => setCategoria(e.target.value)} className={inputCls}>{Object.entries(CATEGORIA).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
          <Field label="Prioridade" hint="Urgente: 4 h · alta: 1 dia · normal: 3 dias · baixa: 5 dias">
            <select value={prioridade} onChange={(e) => setPrioridade(e.target.value)} className={inputCls}>{Object.entries(PRIORIDADE).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}</select>
          </Field>
        </div>
        <Field label="Assunto"><input value={titulo} onChange={(e) => setTitulo(e.target.value)} maxLength={120} className={inputCls} /></Field>
        <Field label="O que está acontecendo" hint="Nunca escreva senhas. Diga desde quando e o que já tentou.">
          <textarea value={descricao} onChange={(e) => setDescricao(e.target.value)} rows={5} maxLength={3000} className={`${inputCls} h-auto py-3`} />
        </Field>
        {canal !== 'MASTER' && (
          <Field label="Código do AnyDesk (opcional)" hint="Se o suporte precisar acessar o computador. Só o código; a conexão você aceita na tela.">
            {anydesk.length ? (
              <select value={any} onChange={(e) => setAny(e.target.value)} className={inputCls}>
                <option value="">Sem acesso remoto</option>
                {anydesk.map((a) => <option key={a.id} value={a.anydesk_id}>{a.equipamento} · {anydeskFmt(a.anydesk_id)}</option>)}
              </select>
            ) : <input value={any} onChange={(e) => setAny(e.target.value)} inputMode="numeric" placeholder="9 ou 10 números" className={inputCls} />}
          </Field>
        )}
        <Field label="Contato para retorno (opcional)"><input value={contato} onChange={(e) => setContato(e.target.value)} placeholder="Ramal ou e-mail funcional" className={inputCls} /></Field>
      </div>
    </Sheet>
  );
}

function DemandaSheet({ id, onClose }: { id: string | null; onClose: () => void }) {
  const res = useRpc<any>('suporte_detalhe', { id }, { enabled: !!id });
  const toast = useToast();
  const recarregar = useRecarregar();
  const [texto, setTexto] = useState('');
  const [sit, setSit] = useState('');
  const [interno, setInterno] = useState(false);
  const [busy, setBusy] = useState(false);
  const d = res.data;
  const enviar = async (args: object, msg: string) => {
    setBusy(true);
    try {
      await rpc('suporte_responder', { id, ...args });
      toast({ title: msg, tone: 'success' });
      setTexto(''); setSit(''); setInterno(false);
      recarregar();
    } catch (e) {
      toast({ title: 'Não enviado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const encerrada = d && ['RESOLVIDO', 'CANCELADO'].includes(d.situacao);
  return (
    <Sheet open={!!id} onClose={onClose} size="lg" title={d ? `${d.protocolo} · ${d.titulo}` : 'Demanda'}
      subtitle={d ? `${CATEGORIA[d.categoria]} · ${d.unidade ?? d.setor ?? ''} · aberta ${fmtDateTime(d.created_at)} por ${d.solicitante_label ?? '—'}` : ''}>
      {!d ? <SkeletonList rows={3} /> : (
        <div className="space-y-4 pt-1">
          <div className="flex flex-wrap gap-1.5">
            <Badge tone={SITUACAO[d.situacao]?.tone}>{SITUACAO[d.situacao]?.label}</Badge>
            <Badge tone={PRIORIDADE[d.prioridade]?.tone}>Prioridade {PRIORIDADE[d.prioridade]?.label.toLowerCase()}</Badge>
            {d.canal === 'MASTER' && <Badge tone="purple" icon={Crown}>Fale com o master</Badge>}
            {!encerrada && d.prazo && <Badge tone={d.vencido ? 'red' : 'gray'}>{d.vencido ? 'prazo vencido' : 'prazo'} {fmtDateTime(d.prazo)}</Badge>}
            {d.atendente_label && <Badge tone="blue" icon={Headset}>{d.atendente_label}</Badge>}
          </div>
          <Card className="p-3 text-[14px]"><p className="whitespace-pre-line">{d.descricao}</p>{d.contato && <p className="mt-1 text-[12.5px] text-muted">Contato: {d.contato}</p>}</Card>
          {d.anydesk_id && (
            <div className="flex flex-wrap items-center gap-2 rounded-2xl bg-blue-50 p-3 text-[13.5px] ring-1 ring-blue-100">
              <Monitor className="size-4 text-blue-800" aria-hidden />AnyDesk <b className="tabular-nums">{anydeskFmt(d.anydesk_id)}</b>
              {d.pode_atender && <a href={`anydesk:${d.anydesk_id}`} className="font-semibold text-blue-800 underline">Conectar</a>}
              <span className="text-[12px] text-muted">A pessoa na unidade aceita a conexão na tela; nunca se pede senha.</span>
            </div>
          )}
          {d.solucao && <p className="rounded-2xl bg-green-50 p-3 text-[13.5px] text-green-900 ring-1 ring-green-100"><b>Solução:</b> {d.solucao}</p>}
          <ol className="space-y-2">
            {((d.mensagens ?? []) as any[]).map((m, i) => (
              <li key={i} className={clsx('rounded-2xl p-2.5 text-[13.5px] ring-1', m.interno ? 'mr-6 bg-slate-50 ring-slate-200' : m.do_suporte ? 'mr-6 bg-white ring-line' : 'ml-6 bg-purple-50 ring-purple-100')}>
                <div className="flex items-center gap-1 text-[11.5px] font-semibold text-muted">{m.interno && <Lock className="size-3" aria-label="nota interna" />}{m.autor} · {fmtDateTime(m.em)}</div>
                <p className="whitespace-pre-line">{m.texto}</p>
              </li>
            ))}
          </ol>
          {d.pode_avaliar && (
            <div className="flex flex-wrap items-center gap-2 rounded-2xl bg-amber-50 p-3 text-[13.5px] ring-1 ring-amber-100">
              Como foi o atendimento?
              {[1, 2, 3, 4, 5].map((n) => (
                <button key={n} type="button" onClick={() => enviar({ avaliacao: n }, 'Obrigado pela avaliação')} aria-label={`${n} estrela(s)`} className="rounded-full p-1 hover:bg-amber-100">
                  <Star className="size-5 text-amber-500" />
                </button>
              ))}
            </div>
          )}
          {d.avaliacao && <p className="text-[13px] text-muted">Avaliação: {'★'.repeat(d.avaliacao)}{'☆'.repeat(5 - d.avaliacao)}</p>}
          <div className="space-y-2">
            <Field label={d.pode_atender ? 'Resposta' : 'Mensagem ao suporte'} hint="Não escreva senhas.">
              <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} maxLength={3000} className={`${inputCls} h-auto py-3`} />
            </Field>
            {d.pode_atender ? (
              <>
                <Segmented value={sit} onChange={setSit} items={[{ value: '', label: 'Manter' }, { value: 'EM_ATENDIMENTO', label: 'Em atendimento' },
                  { value: 'AGUARDANDO_SOLICITANTE', label: 'Aguardar solicitante' }, { value: 'RESOLVIDO', label: 'Resolver' }, { value: 'CANCELADO', label: 'Cancelar' }]} />
                <label className="flex items-center gap-2 text-[13.5px]"><input type="checkbox" checked={interno} onChange={(e) => setInterno(e.target.checked)} className="size-5 accent-purple-700" />Nota interna (quem abriu não vê)</label>
              </>
            ) : encerrada ? (
              <label className="flex items-center gap-2 text-[13.5px]"><input type="checkbox" checked={sit === 'ABERTO'} onChange={(e) => setSit(e.target.checked ? 'ABERTO' : '')} className="size-5 accent-purple-700" />Reabrir: o problema voltou</label>
            ) : null}
            <Button block icon={Send} loading={busy} disabled={texto.trim().length < 2 && !sit}
              onClick={() => enviar({ texto, situacao: sit || null, interno }, sit === 'RESOLVIDO' ? 'Demanda resolvida' : 'Mensagem enviada')}>Enviar</Button>
            {!d.pode_atender && d.meu && !encerrada && (
              <Button block variant="ghost" icon={Trash2} loading={busy} onClick={() => enviar({ situacao: 'CANCELADO', texto: 'Cancelado por quem abriu.' }, 'Demanda cancelada')}>Cancelar a demanda</Button>
            )}
          </div>
        </div>
      )}
    </Sheet>
  );
}

/** Cadastro do AnyDesk dos computadores das unidades (código apenas; nunca a senha). */
function AnyDesk() {
  const res = useRpc<any>('suporte_anydesk', { acao: 'LISTAR' });
  const toast = useToast();
  const recarregar = useRecarregar();
  const [form, setForm] = useState<{ id?: string; equipamento: string; anydesk_id: string; local: string; responsavel: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const salvar = async (args: object, msg: string) => {
    setBusy(true);
    try {
      await rpc('suporte_anydesk', args);
      toast({ title: msg, tone: 'success' });
      setForm(null);
      recarregar();
    } catch (e) {
      toast({ title: 'Não salvo', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  return (
    <div className="mt-3 space-y-3">
      {res.data.pode_editar && <Button icon={Plus} onClick={() => setForm({ equipamento: '', anydesk_id: '', local: '', responsavel: '' })}>Cadastrar equipamento</Button>}
      <Card className="overflow-hidden">
        {!res.data.itens.length ? <EmptyState compact title="Nenhum equipamento cadastrado" /> : (
          <Tabela colunas="minmax(170px,1.2fr) minmax(200px,1.4fr) 150px minmax(130px,1fr) minmax(150px,1fr) 120px" largura={960} rotulo="AnyDesk das unidades">
            <TCabecalho><TCelula fixa>Unidade</TCelula><TCelula>Equipamento</TCelula><TCelula>AnyDesk</TCelula><TCelula>Local</TCelula><TCelula>Responsável</TCelula><TCelula>Atualizado</TCelula></TCabecalho>
            {(res.data.itens as any[]).map((a) => (
              <TLinha key={a.id} onClick={res.data.pode_editar ? () => setForm({ id: a.id, equipamento: a.equipamento, anydesk_id: a.anydesk_id, local: a.local ?? '', responsavel: a.responsavel ?? '' }) : undefined} rotulo={a.equipamento}>
                <TCelula fixa>{a.unidade ?? a.setor ?? '—'}{a.is_demo && <MarcaSimulado className="ml-1" />}</TCelula>
                <TCelula>{a.equipamento}</TCelula>
                <TCelula className="tabular-nums font-semibold">{anydeskFmt(a.anydesk_id)}</TCelula>
                <TCelula>{a.local ?? '—'}</TCelula>
                <TCelula>{a.responsavel ?? '—'}</TCelula>
                <TCelula>{timeAgo(a.atualizado_em)}</TCelula>
              </TLinha>
            ))}
          </Tabela>
        )}
      </Card>
      <Sheet open={!!form} onClose={() => setForm(null)} title={form?.id ? 'Equipamento' : 'Cadastrar equipamento'} subtitle="Só o código do AnyDesk. A senha nunca é cadastrada nem pedida."
        footer={form && (
          <div className="flex gap-2">
            {form.id && <Button variant="secondary" icon={Trash2} loading={busy} onClick={() => salvar({ acao: 'EXCLUIR', id: form.id }, 'Equipamento removido')}>Remover</Button>}
            <Button block loading={busy} disabled={form.equipamento.trim().length < 3 || form.anydesk_id.replace(/\D/g, '').length < 9}
              onClick={() => salvar({ acao: 'SALVAR', ...form }, 'Equipamento salvo')}>Salvar</Button>
          </div>
        )}>
        {form && (
          <div className="space-y-3 pt-1">
            <Field label="Equipamento"><input value={form.equipamento} onChange={(e) => setForm({ ...form, equipamento: e.target.value })} placeholder="Computador da secretaria" className={inputCls} /></Field>
            <Field label="Código do AnyDesk"><input value={form.anydesk_id} onChange={(e) => setForm({ ...form, anydesk_id: e.target.value })} inputMode="numeric" placeholder="123 456 789" className={inputCls} /></Field>
            <Field label="Local"><input value={form.local} onChange={(e) => setForm({ ...form, local: e.target.value })} className={inputCls} /></Field>
            <Field label="Responsável"><input value={form.responsavel} onChange={(e) => setForm({ ...form, responsavel: e.target.value })} className={inputCls} /></Field>
          </div>
        )}
      </Sheet>
    </div>
  );
}
