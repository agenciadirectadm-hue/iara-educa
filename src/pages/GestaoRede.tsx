import { useMemo, useState } from 'react';
import { useSearchParams } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { ChevronRight, Clock, FilePlus2, Network, Pencil, Plus, Trash2, Upload, UserPlus, X } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useDebounced, useRpc } from '@/lib/hooks';
import { fmtDate, fmtInt } from '@/lib/format';
import { SHIFT } from '@/lib/labels';
import { Badge, Button, Card, Chip, EmptyState, ErrorState, Field, Meter, PageHeader, SkeletonList, Tabs, inputCls } from '@/components/ui';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { Sheet, useToast } from '@/components/overlays';

type Aba = 'organograma' | 'servicos' | 'criterios' | 'jornada';
const TIPO_SETOR = ['SECRETARIA', 'GABINETE', 'SUPERINTENDENCIA', 'DIRETORIA', 'GERENCIA', 'DIVISAO', 'COORDENACAO', 'NUCLEO', 'ASSESSORIA', 'CONSELHO'];
const rot = (s: string) => s.charAt(0) + s.slice(1).toLowerCase().replaceAll('_', ' ');

function useSalvar(chaves: string[]) {
  const qc = useQueryClient();
  const toast = useToast();
  const [busy, setBusy] = useState(false);
  const salvar = async (fn: string, args: object, msg: string, depois?: (r: any) => void) => {
    setBusy(true);
    try {
      const r = await rpc<any>(fn, args);
      toast({ title: msg, tone: 'success' });
      chaves.forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
      depois?.(r);
      return r;
    } catch (e) {
      toast({ title: 'Não salvo', description: (e as Error).message, tone: 'error' });
      return null;
    } finally {
      setBusy(false);
    }
  };
  return { busy, salvar };
}

/** Gestão da rede: organograma, catálogo de serviços, critérios e jornada/matriz — tudo com histórico. */
export default function GestaoRede() {
  const [sp, setSp] = useSearchParams();
  const aba = (sp.get('aba') ?? 'organograma') as Aba;
  return (
    <div>
      <PageHeader eyebrow="SEDUC · gestão da rede" title="Gestão da rede"
        subtitle="Organograma e vínculos, catálogo de serviços (prazos, plantão e ações da IARA), critérios da fila e jornada escolar. Toda alteração fica no histórico." />
      <Tabs value={aba} onChange={(v) => setSp({ aba: v }, { replace: true })} items={[
        { value: 'organograma', label: 'Organograma' }, { value: 'servicos', label: 'Catálogo de serviços' },
        { value: 'criterios', label: 'Critérios' }, { value: 'jornada', label: 'Jornada e matriz' },
      ]} />
      <div className="mt-3">
        {aba === 'organograma' && <Organograma />}
        {aba === 'servicos' && <Servicos />}
        {aba === 'criterios' && <Criterios />}
        {aba === 'jornada' && <Jornada />}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------- Organograma
function Organograma() {
  const res = useRpc<any>('org_arvore', {});
  const [aberto, setAberto] = useState<any | null>(null);
  const [importar, setImportar] = useState(false);
  const setores = (res.data?.setores ?? []) as any[];
  const filhos = useMemo(() => {
    const m = new Map<string | null, any[]>();
    for (const s of setores) m.set(s.superior_id ?? null, [...(m.get(s.superior_id ?? null) ?? []), s]);
    return m;
  }, [setores]);
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const Ramo = ({ pai, nivel }: { pai: string | null; nivel: number }) => (
    <>
      {(filhos.get(pai) ?? []).map((s) => {
        const chefe = (s.pessoas as any[]).find((p) => p.chefia);
        return (
          <div key={s.id}>
            <button type="button" onClick={() => setAberto(s)} className="flex w-full items-center gap-2 border-b border-line/60 px-3 py-2 text-left text-[13.5px] hover:bg-blue-50"
              style={{ paddingLeft: 12 + nivel * 22 }}>
              {nivel > 0 && <ChevronRight className="size-3.5 shrink-0 text-subtle" aria-hidden />}
              <span className="w-16 shrink-0 font-bold">{s.sigla}</span>
              <span className="min-w-0 flex-1 truncate">{s.nome}</span>
              <Badge tone="gray" className="hidden sm:inline-flex">{rot(s.tipo)}</Badge>
              <span className="hidden w-48 shrink-0 truncate text-muted md:block">{chefe ? `Chefia: ${chefe.nome}` : 'chefia a definir'}</span>
              <span className="w-16 shrink-0 text-right text-muted">{(s.pessoas as any[]).length} pess.</span>
              {s.fonte !== 'OFICIAL' && <Badge tone="amber">{s.fonte === 'A_VALIDAR' ? 'a validar' : 'demonstração'}</Badge>}
            </button>
            <Ramo pai={s.id} nivel={nivel + 1} />
          </div>
        );
      })}
    </>
  );
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        {res.data.pode_editar && <Button icon={Plus} onClick={() => setAberto({})}>Novo setor</Button>}
        {res.data.pode_editar && <Button variant="secondary" icon={Upload} onClick={() => setImportar(true)}>Importar</Button>}
        <p className="text-[12.5px] text-muted">Estrutura inicial montada a partir dos perfis do sistema: <b>a validar pela SEDUC</b>. As {fmtInt(res.data.unidades)} unidades escolares ficam sob “UNID”.</p>
      </div>
      <Card className="overflow-hidden"><Ramo pai={null} nivel={0} /></Card>
      <SetorSheet setor={aberto} setores={setores} podeEditar={res.data.pode_editar} onClose={() => setAberto(null)} />
      <ImportarSheet open={importar} onClose={() => setImportar(false)} />
    </div>
  );
}

function SetorSheet({ setor, setores, podeEditar, onClose }: { setor: any | null; setores: any[]; podeEditar: boolean; onClose: () => void }) {
  const { busy, salvar } = useSalvar(['org_arvore']);
  const novo = !!setor && !setor.id;
  const [f, setF] = useState<any>({});
  const [chave, setChave] = useState<string | null>(null);
  const [q, setQ] = useState('');
  const dq = useDebounced(q, 300);
  const [pessoa, setPessoa] = useState<{ id?: string; nome: string } | null>(null);
  const [funcao, setFuncao] = useState('');
  const [chefia, setChefia] = useState(false);
  const busca = useRpc<any[]>('org_pessoas_busca', { q: dq }, { enabled: podeEditar && dq.trim().length >= 3 && !pessoa });
  if (setor && chave !== (setor.id ?? 'novo')) {
    setChave(setor.id ?? 'novo');
    setF({ sigla: setor.sigla ?? '', nome: setor.nome ?? '', tipo: setor.tipo ?? 'DIVISAO', superior_id: setor.superior_id ?? '', competencias: setor.competencias ?? '', email: setor.email ?? '', telefone: setor.telefone ?? '' });
  }
  const fechar = () => { setChave(null); setPessoa(null); setQ(''); setFuncao(''); setChefia(false); onClose(); };
  return (
    <Sheet open={!!setor} onClose={fechar} size="lg" title={novo ? 'Novo setor' : `${setor?.sigla} · ${setor?.nome}`} subtitle={novo ? '' : `${rot(setor?.tipo ?? '')} · superior: ${setor?.superior ?? '—'}`}
      footer={podeEditar ? (
        <div className="flex gap-2">
          {!novo && <Button variant="secondary" icon={Trash2} loading={busy} onClick={() => salvar('org_setor_excluir', { id: setor.id }, 'Setor excluído', fechar)}>Excluir</Button>}
          <Button block loading={busy} disabled={!f.sigla || (f.nome ?? '').length < 3} onClick={() => salvar('org_setor_salvar', { ...f, id: setor.id ?? null }, 'Setor salvo', fechar)}>Salvar</Button>
        </div>
      ) : undefined}>
      {setor && (
        <div className="space-y-4 pt-1">
          <div className="grid gap-3 sm:grid-cols-[120px_1fr]">
            <Field label="Sigla"><input value={f.sigla} disabled={!podeEditar} onChange={(e) => setF({ ...f, sigla: e.target.value.toUpperCase() })} className={inputCls} /></Field>
            <Field label="Nome"><input value={f.nome} disabled={!podeEditar} onChange={(e) => setF({ ...f, nome: e.target.value })} className={inputCls} /></Field>
          </div>
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="Tipo"><select value={f.tipo} disabled={!podeEditar} onChange={(e) => setF({ ...f, tipo: e.target.value })} className={inputCls}>{TIPO_SETOR.map((t) => <option key={t} value={t}>{rot(t)}</option>)}</select></Field>
            <Field label="Setor superior">
              <select value={f.superior_id} disabled={!podeEditar} onChange={(e) => setF({ ...f, superior_id: e.target.value })} className={inputCls}>
                <option value="">— topo —</option>{setores.filter((s) => s.id !== setor.id).map((s) => <option key={s.id} value={s.id}>{s.sigla} · {s.nome}</option>)}
              </select>
            </Field>
          </div>
          <Field label="Competências"><textarea value={f.competencias} disabled={!podeEditar} onChange={(e) => setF({ ...f, competencias: e.target.value })} rows={2} className={`${inputCls} h-auto py-3`} /></Field>
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="E-mail do setor"><input value={f.email} disabled={!podeEditar} onChange={(e) => setF({ ...f, email: e.target.value })} className={inputCls} /></Field>
            <Field label="Telefone"><input value={f.telefone} disabled={!podeEditar} onChange={(e) => setF({ ...f, telefone: e.target.value })} className={inputCls} /></Field>
          </div>
          {!novo && (
            <div className="space-y-2">
              <h3 className="font-semibold">Pessoas vinculadas</h3>
              {!(setor.pessoas as any[]).length && <p className="text-[13px] text-muted">Ninguém vinculado ainda.</p>}
              {(setor.pessoas as any[]).map((p) => (
                <div key={p.id} className="flex items-center gap-2 rounded-2xl bg-white p-2 text-[13.5px] ring-1 ring-line">
                  <span className="min-w-0 flex-1"><b>{p.nome}</b> · {p.funcao}{p.chefia && <Badge tone="purple" className="ml-1">chefia</Badge>}</span>
                  <span className="text-[12px] text-muted">desde {fmtDate(p.inicio)}</span>
                  {podeEditar && <button type="button" aria-label="Desvincular" onClick={() => salvar('org_vincular', { id: p.id, desvincular: true }, 'Vínculo encerrado', fechar)} className="rounded-full p-1 hover:bg-red-50"><X className="size-4 text-red-700" /></button>}
                </div>
              ))}
              {podeEditar && (
                <div className="space-y-2 rounded-3xl bg-slate-50 p-3 ring-1 ring-line">
                  {pessoa ? (
                    <div className="flex items-center gap-2 text-[13.5px]"><b>{pessoa.nome}</b><button type="button" onClick={() => setPessoa(null)} className="text-blue-800 underline">trocar</button></div>
                  ) : (
                    <>
                      <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar servidor pelo nome (ou digite um nome novo)" className={inputCls} />
                      {((busca.data ?? []) as any[]).map((s) => (
                        <button key={s.id} type="button" onClick={() => setPessoa({ id: s.id, nome: s.nome })} className="block w-full rounded-xl px-2 py-1 text-left text-[13px] hover:bg-blue-50">
                          {s.nome} <span className="text-muted">· {s.cargo ?? ''}{s.unidade ? ` · ${s.unidade}` : ''}</span>
                        </button>
                      ))}
                      {q.trim().length >= 3 && <button type="button" onClick={() => setPessoa({ nome: q.trim() })} className="text-[13px] font-semibold text-blue-800 underline">Usar “{q.trim()}” (sem cadastro de servidor)</button>}
                    </>
                  )}
                  <input value={funcao} onChange={(e) => setFuncao(e.target.value)} placeholder="Função no setor (ex.: gerente, assessora)" className={inputCls} />
                  <label className="flex items-center gap-2 text-[13.5px]"><input type="checkbox" checked={chefia} onChange={(e) => setChefia(e.target.checked)} className="size-5 accent-purple-700" />É a chefia do setor</label>
                  <Button icon={UserPlus} loading={busy} disabled={!pessoa || funcao.trim().length < 3}
                    onClick={() => salvar('org_vincular', { setor_id: setor.id, staff_id: pessoa?.id ?? null, nome: pessoa?.nome, funcao, chefia }, 'Pessoa vinculada', fechar)}>Vincular</Button>
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </Sheet>
  );
}

function ImportarSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { busy, salvar } = useSalvar(['org_arvore']);
  const [texto, setTexto] = useState('');
  const [r, setR] = useState<any | null>(null);
  return (
    <Sheet open={open} onClose={() => { setR(null); onClose(); }} size="lg" title="Importar organograma"
      subtitle="Uma linha por setor: SIGLA;Nome;Tipo;SIGLA do superior[;e-mail;telefone]. Pode colar de uma planilha (separado por tabulação). Setores existentes são atualizados pela sigla."
      footer={<div className="flex gap-2">
        <Button variant="secondary" loading={busy} disabled={texto.trim().length < 5} onClick={() => salvar('org_importar', { texto }, 'Arquivo conferido', setR)}>Conferir</Button>
        <Button block loading={busy} disabled={!r || r.erros.length > 0 || !r.validas.length} onClick={() => salvar('org_importar', { texto, confirmar: true }, 'Organograma importado', (x) => { setR(x); setTexto(''); })}>Importar</Button>
      </div>}>
      <div className="space-y-3 pt-1">
        <textarea value={texto} onChange={(e) => { setTexto(e.target.value); setR(null); }} rows={10} placeholder={'SIGLA;Nome;Tipo;Superior\nNTE;Núcleo de Tecnologia Educacional;NUCLEO;DINOV'} className={`${inputCls} h-auto py-3 font-mono text-[12.5px]`} />
        <p className="text-[12px] text-muted">Tipos: {TIPO_SETOR.join(', ')}.</p>
        {r && (
          <div className="space-y-2 text-[13px]">
            {r.gravado && <p className="rounded-2xl bg-green-50 p-2 text-green-900">Importado: {r.incluidos} incluído(s), {r.alterados} alterado(s).</p>}
            {!r.gravado && <p>{r.validas.length} linha(s) válida(s) · {r.erros.length} com erro.</p>}
            {(r.erros as any[]).map((e, i) => <p key={i} className="rounded-xl bg-red-50 px-2 py-1 text-red-900">Linha {e.linha}: {e.erro}</p>)}
            {!r.gravado && (r.validas as any[]).slice(0, 30).map((v, i) => <p key={i} className="text-muted">Linha {v.linha}: {v.acao} {v.sigla} — {v.nome}</p>)}
          </div>
        )}
      </div>
    </Sheet>
  );
}

// ---------------------------------------------------------------- Catálogo de serviços
const NIVEL: Record<string, string> = { IARA: 'IARA resolve', UNIDADE: 'Unidade', SECRETARIA: 'Secretaria' };
function Servicos() {
  const [inativos, setInativos] = useState(false);
  const res = useRpc<any>('servicos_gestao', { inativos });
  const [aberto, setAberto] = useState<any | null>(null);
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        {res.data.pode_editar && <Button icon={FilePlus2} onClick={() => setAberto({})}>Novo serviço</Button>}
        <Chip active={inativos} onClick={() => setInativos(!inativos)}>Mostrar excluídos</Chip>
      </div>
      <Card className="overflow-hidden">
        <Tabela colunas="minmax(220px,1.6fr) 120px minmax(180px,1.2fr) 80px minmax(150px,1fr) minmax(200px,1.5fr) 80px" largura={1180} rotulo="Catálogo de serviços">
          <TCabecalho><TCelula fixa>Serviço</TCelula><TCelula>Alçada</TCelula><TCelula>Equipe</TCelula><TCelula>Prazo</TCelula><TCelula>Plantão</TCelula><TCelula>Ação da IARA</TCelula><TCelula>Abertos</TCelula></TCabecalho>
          {(res.data.itens as any[]).map((s) => (
            <TLinha key={s.code} onClick={() => setAberto(s)} rotulo={s.name}>
              <TCelula fixa titulo={s.description}><span className={clsx('font-semibold', !s.ativo && 'line-through')}>{s.name}</span></TCelula>
              <TCelula>{NIVEL[s.resolution_level] ?? s.resolution_level}</TCelula>
              <TCelula titulo={s.team_label}>{s.team_label}</TCelula>
              <TCelula>{s.sla_days} dia(s)</TCelula>
              <TCelula titulo={s.plantao}>{s.plantao ?? '—'}</TCelula>
              <TCelula titulo={s.iara_action}>{s.iara_action ?? '—'}</TCelula>
              <TCelula>{fmtInt(s.casos_abertos)}</TCelula>
            </TLinha>
          ))}
        </Tabela>
      </Card>
      <ServicoSheet servico={aberto} equipes={res.data.equipes} podeEditar={res.data.pode_editar} onClose={() => setAberto(null)} />
    </div>
  );
}

function ServicoSheet({ servico, equipes, podeEditar, onClose }: { servico: any | null; equipes: any[]; podeEditar: boolean; onClose: () => void }) {
  const { busy, salvar } = useSalvar(['servicos_gestao', 'service_catalog']);
  const [f, setF] = useState<any>({});
  const [chave, setChave] = useState<string | null>(null);
  const novo = !!servico && !servico.code;
  if (servico && chave !== (servico.code ?? 'novo')) {
    setChave(servico.code ?? 'novo');
    setF({ name: servico.name ?? '', description: servico.description ?? '', requirements: servico.requirements ?? '', documents: (servico.required_documents ?? []).join(', '),
      sla_days: servico.sla_days ?? 10, resolution_level: servico.resolution_level ?? 'SECRETARIA', team: servico.team ?? 'CENTRAL_VAGAS', plantao: servico.plantao ?? '',
      iara_action: servico.iara_action ?? '', escalation: servico.escalation ?? '', canais: servico.canais ?? ['PORTAL', 'IARA', 'PRESENCIAL'], source: servico.source ?? '' });
  }
  const fechar = () => { setChave(null); onClose(); };
  const args = () => ({ ...f, code: servico.code ?? null, documents: String(f.documents).split(',').map((x: string) => x.trim().toUpperCase()).filter(Boolean), sla_days: Number(f.sla_days) });
  return (
    <Sheet open={!!servico} onClose={fechar} size="lg" title={novo ? 'Novo serviço' : servico?.name} subtitle={novo ? 'Aparece no portal, na IARA e no atendimento.' : servico?.code}
      footer={podeEditar ? (
        <div className="flex gap-2">
          {servico && !novo && servico.ativo && <Button variant="secondary" icon={Trash2} loading={busy} onClick={() => salvar('servico_salvar', { code: servico.code, excluir: true }, 'Serviço excluído do catálogo', fechar)}>Excluir</Button>}
          <Button block loading={busy} disabled={(f.name ?? '').length < 5 || (f.description ?? '').length < 15} onClick={() => salvar('servico_salvar', args(), novo ? 'Serviço incluído' : 'Serviço alterado', fechar)}>
            {servico && !novo && !servico.ativo ? 'Reativar e salvar' : 'Salvar'}
          </Button>
        </div>
      ) : undefined}>
      {servico && (
        <div className="space-y-3 pt-1">
          <Field label="Nome"><input value={f.name} disabled={!podeEditar} onChange={(e) => setF({ ...f, name: e.target.value })} className={inputCls} /></Field>
          <Field label="Descrição"><textarea value={f.description} disabled={!podeEditar} onChange={(e) => setF({ ...f, description: e.target.value })} rows={3} className={`${inputCls} h-auto py-3`} /></Field>
          <div className="grid gap-3 sm:grid-cols-3">
            <Field label="Prazo (dias)"><input type="number" min={1} max={120} value={f.sla_days} disabled={!podeEditar} onChange={(e) => setF({ ...f, sla_days: e.target.value })} className={inputCls} /></Field>
            <Field label="Alçada"><select value={f.resolution_level} disabled={!podeEditar} onChange={(e) => setF({ ...f, resolution_level: e.target.value })} className={inputCls}>{Object.entries(NIVEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
            <Field label="Equipe"><select value={f.team} disabled={!podeEditar} onChange={(e) => setF({ ...f, team: e.target.value })} className={inputCls}>{equipes.map((e) => <option key={e.code} value={e.code}>{e.label}</option>)}</select></Field>
          </div>
          <Field label="Plantão / horário de atendimento"><input value={f.plantao} disabled={!podeEditar} onChange={(e) => setF({ ...f, plantao: e.target.value })} placeholder="Ex.: seg a sex, 8h às 17h; plantão de matrícula aos sábados em janeiro" className={inputCls} /></Field>
          <Field label="O que a IARA faz" hint="Ação automática da IARA neste serviço (abre o pedido, consulta, agenda, encaminha…)."><textarea value={f.iara_action} disabled={!podeEditar} onChange={(e) => setF({ ...f, iara_action: e.target.value })} rows={2} className={`${inputCls} h-auto py-3`} /></Field>
          <Field label="Quando passa para uma pessoa"><textarea value={f.escalation} disabled={!podeEditar} onChange={(e) => setF({ ...f, escalation: e.target.value })} rows={2} className={`${inputCls} h-auto py-3`} /></Field>
          <Field label="Requisitos"><input value={f.requirements} disabled={!podeEditar} onChange={(e) => setF({ ...f, requirements: e.target.value })} className={inputCls} /></Field>
          <Field label="Documentos (códigos separados por vírgula)"><input value={f.documents} disabled={!podeEditar} onChange={(e) => setF({ ...f, documents: e.target.value })} placeholder="CERTIDAO, CPF, COMPROVANTE_ENDERECO" className={inputCls} /></Field>
          <Field label="Canais">
            <div className="flex flex-wrap gap-1.5">
              {['PORTAL', 'IARA', 'WHATSAPP', 'PRESENCIAL', 'TELEFONE'].map((c) => (
                <Chip key={c} active={(f.canais ?? []).includes(c)} onClick={() => podeEditar && setF({ ...f, canais: (f.canais ?? []).includes(c) ? f.canais.filter((x: string) => x !== c) : [...(f.canais ?? []), c] })}>{rot(c)}</Chip>
              ))}
            </div>
          </Field>
          <Field label="Fonte normativa"><input value={f.source} disabled={!podeEditar} onChange={(e) => setF({ ...f, source: e.target.value })} className={inputCls} /></Field>
          {!novo && servico.atualizado_em && <p className="text-[12px] text-muted">Última alteração: {fmtDate(servico.atualizado_em)} · {servico.atualizado_por_label}</p>}
        </div>
      )}
    </Sheet>
  );
}

// ---------------------------------------------------------------- Critérios
const TIPO_REGRA: Record<string, string> = {
  PRIORIDADE_FILA: 'Pontuação da fila', PRIORIDADE_ANALISE: 'Prioridade sob análise', DESEMPATE: 'Desempate', ELIMINATORIA: 'Eliminatória da busca',
  PONTUACAO_UNIDADE: 'Ordenação das unidades', PARAMETRO: 'Prazo ou parâmetro',
};
function Criterios() {
  const res = useRpc<any>('criterios_gestao', {});
  const [hist, setHist] = useState(false);
  const [aberto, setAberto] = useState<any | null>(null);
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const itens = (res.data.itens as any[]).filter((r) => hist || r.vigente || (!r.no_calculo && !r.valid_to));
  const soma = (res.data.itens as any[]).filter((r) => r.vigente && r.type === 'PRIORIDADE_FILA' && r.no_calculo).reduce((a, r) => a + Number(r.weight ?? 0), 0);
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        {res.data.pode_editar && <Button icon={Plus} onClick={() => setAberto({})}>Novo critério</Button>}
        <Chip active={hist} onClick={() => setHist(!hist)}>Mostrar versões anteriores</Chip>
        <span className="text-[13px] text-muted">Pontuação da fila vigente: <b>{fmtInt(soma)}</b> de 100 pontos (IN 025/2025, Anexo I). A página pública “Regras e critérios” mostra a versão vigente.</span>
      </div>
      <Card className="overflow-hidden">
        <Tabela colunas="minmax(220px,1.6fr) 170px 70px 120px 190px 150px" largura={980} rotulo="Critérios">
          <TCabecalho><TCelula fixa>Critério</TCelula><TCelula>Tipo</TCelula><TCelula>Peso</TCelula><TCelula>Versão</TCelula><TCelula>Vigência</TCelula><TCelula>Situação</TCelula></TCabecalho>
          {itens.map((r) => (
            <TLinha key={r.id} onClick={() => setAberto(r)} rotulo={r.name}>
              <TCelula fixa titulo={r.description}><span className="font-semibold">{r.name}</span> <span className="text-[12px] text-muted">{r.code}</span></TCelula>
              <TCelula>{TIPO_REGRA[r.type] ?? r.type}</TCelula>
              <TCelula>{r.weight != null ? String(r.weight).replace('.', ',') : '—'}</TCelula>
              <TCelula>{r.version}</TCelula>
              <TCelula>{fmtDate(r.valid_from)}{r.valid_to ? ` → ${fmtDate(r.valid_to)}` : ''}</TCelula>
              <TCelula livre>{r.vigente ? <Badge tone="green">vigente</Badge> : !r.no_calculo ? <Badge tone="amber">proposto</Badge> : r.valid_to ? <Badge tone="gray">encerrado</Badge> : <Badge tone="blue">futuro/inativo</Badge>}</TCelula>
            </TLinha>
          ))}
        </Tabela>
      </Card>
      <CriterioSheet regra={aberto} podeEditar={res.data.pode_editar} onClose={() => setAberto(null)} />
    </div>
  );
}

function CriterioSheet({ regra, podeEditar, onClose }: { regra: any | null; podeEditar: boolean; onClose: () => void }) {
  const { busy, salvar } = useSalvar(['criterios_gestao', 'rules_list']);
  const [f, setF] = useState<any>({});
  const [chave, setChave] = useState<string | null>(null);
  const novo = !!regra && !regra.code;
  if (regra && chave !== (regra.id ? String(regra.id) : 'novo')) {
    setChave(regra.id ? String(regra.id) : 'novo');
    setF({ code: regra.code ?? '', name: regra.name ?? '', description: regra.description ?? '', type: regra.type ?? 'PRIORIDADE_FILA', weight: regra.weight ?? 0,
      source: regra.source ?? '', valid_from: new Date().toISOString().slice(0, 10), justification: '' });
  }
  const fechar = () => { setChave(null); onClose(); };
  return (
    <Sheet open={!!regra} onClose={fechar} size="lg" title={novo ? 'Novo critério' : regra?.name} subtitle={novo ? 'Entra como proposto: só passa a contar na fila depois da implementação técnica.' : `${regra?.code} · versão ${regra?.version}`}
      footer={podeEditar ? (
        <div className="flex gap-2">
          {regra && !novo && regra.vigente && regra.type !== 'ELIMINATORIA' && <Button variant="secondary" icon={Trash2} loading={busy} disabled={(f.justification ?? '').length < 10}
            onClick={() => salvar('criterio_salvar', { code: regra.code, desativar: true, valid_from: f.valid_from, justification: f.justification }, 'Critério desativado', fechar)}>Desativar</Button>}
          <Button block icon={Pencil} loading={busy} disabled={(f.justification ?? '').length < 10 || (f.code ?? '').length < 3}
            onClick={() => salvar('criterio_salvar', { ...f, weight: Number(f.weight) }, novo ? 'Critério proposto' : 'Nova versão registrada', fechar)}>{novo ? 'Propor' : 'Salvar nova versão'}</Button>
        </div>
      ) : undefined}>
      {regra && (
        <div className="space-y-3 pt-1">
          {novo && <Field label="Código"><input value={f.code} onChange={(e) => setF({ ...f, code: e.target.value.toUpperCase() })} placeholder="EX.: IRMAO_TRANSPORTE" className={inputCls} /></Field>}
          <Field label="Nome"><input value={f.name} disabled={!podeEditar} onChange={(e) => setF({ ...f, name: e.target.value })} className={inputCls} /></Field>
          <Field label="Descrição (como a família lê)"><textarea value={f.description} disabled={!podeEditar} onChange={(e) => setF({ ...f, description: e.target.value })} rows={3} className={`${inputCls} h-auto py-3`} /></Field>
          <div className="grid gap-3 sm:grid-cols-3">
            <Field label="Tipo"><select value={f.type} disabled={!podeEditar || !novo} onChange={(e) => setF({ ...f, type: e.target.value })} className={inputCls}>{Object.entries(TIPO_REGRA).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
            <Field label="Peso (pontos)"><input type="number" min={0} max={100} value={f.weight} disabled={!podeEditar} onChange={(e) => setF({ ...f, weight: e.target.value })} className={inputCls} /></Field>
            <Field label="Vale a partir de"><input type="date" value={f.valid_from} disabled={!podeEditar} onChange={(e) => setF({ ...f, valid_from: e.target.value })} className={inputCls} /></Field>
          </div>
          <Field label="Fonte normativa"><input value={f.source} disabled={!podeEditar} onChange={(e) => setF({ ...f, source: e.target.value })} className={inputCls} /></Field>
          {podeEditar && <Field label="Justificativa (obrigatória)" hint="Decisão, norma, ofício do MP ou da Defensoria. Fica no histórico e na auditoria.">
            <textarea value={f.justification} onChange={(e) => setF({ ...f, justification: e.target.value })} rows={2} className={`${inputCls} h-auto py-3`} />
          </Field>}
          {!novo && regra.justification && <p className="text-[12.5px] text-muted">Justificativa desta versão: {regra.justification}</p>}
          {!novo && regra.criado_por && <p className="text-[12px] text-muted">Registrada por {regra.criado_por}.</p>}
          <p className="text-[12px] text-muted">Mudar o peso da pontuação recalcula a fila no mesmo dia; quem perde posição recebe a explicação na consulta da fila.</p>
        </div>
      )}
    </Sheet>
  );
}

// ---------------------------------------------------------------- Jornada e matriz
function Jornada() {
  const res = useRpc<any>('jornada_gestao', {});
  const [jornada, setJornada] = useState<any | null>(null);
  const [disc, setDisc] = useState<any | null>(null);
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  return (
    <div className="space-y-4">
      <p className="text-[13px] text-muted">Padrões por série e turno: as turmas seguem o padrão, salvo jornada própria. Mínimo legal: {d.minimo_ldb_horas} h em {d.dias_letivos} dias letivos (LDB, art. 24); hora-atividade de pelo menos 1/3 da jornada do professor (Lei 11.738/2008, art. 2º, §4º).</p>
      {(d.series as any[]).filter((s) => (s.jornadas as any[]).length).map((s) => {
        const capacidade = Math.max(0, ...(s.jornadas as any[]).map((j) => j.aulas_dia * j.dias_semana));
        const precisa = Math.ceil(capacidade / 3);
        return (
          <Card key={s.code} className="p-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <h3 className="font-display text-lg font-extrabold">{s.nome}</h3>
              {d.pode_editar && <Button size="sm" variant="secondary" icon={Plus} onClick={() => setDisc({ grade_code: s.code, serie: s.nome })}>Disciplina</Button>}
            </div>
            <div className="mt-2 space-y-1.5">
              {(s.jornadas as any[]).map((j) => (
                <button key={j.id} type="button" onClick={() => setJornada({ ...j, serie: s.nome })} className="flex w-full flex-wrap items-center gap-2 rounded-2xl bg-slate-50 px-3 py-2 text-left text-[13.5px] ring-1 ring-line hover:bg-blue-50">
                  <Clock className="size-4 text-subtle" aria-hidden /><b className="w-16">{SHIFT[j.turno] ?? j.turno}</b>
                  <span>{j.inicio.slice(0, 5)}–{String(j.termino).slice(0, 5)} · {j.aulas_dia} aulas de {j.duracao_aula_min} min · intervalo {j.intervalo_min} min</span>
                  <span className={clsx('font-semibold', j.horas_ano < d.minimo_ldb_horas ? 'text-red-700' : 'text-green-800')}>{fmtInt(j.horas_ano)} h/ano</span>
                  <span className="text-muted">hora-atividade {String(j.hora_atividade_pct).replace('.', ',')}% · {fmtInt(j.turmas)} turma(s){j.turmas_proprias ? `, ${j.turmas_proprias} com jornada própria` : ''}</span>
                  <Badge tone={j.situacao === 'CONFIRMADO' ? 'green' : 'amber'}>{j.situacao === 'CONFIRMADO' ? 'confirmado' : 'proposto'} · v{j.versao}</Badge>
                </button>
              ))}
            </div>
            {(s.matriz as any[]).length > 0 && (
              <>
                <div className="mt-3 overflow-x-auto">
                  <table className="w-full min-w-[520px] text-[13px]">
                    <thead><tr className="text-left text-[11.5px] uppercase text-muted"><th className="py-1">Disciplina</th><th>Aulas/semana</th><th>Quem leciona</th><th>Cobre hora-atividade</th></tr></thead>
                    <tbody>
                      {(s.matriz as any[]).map((m) => (
                        <tr key={m.componente} className="border-t border-line/60 hover:bg-blue-50" onClick={() => d.pode_editar && setDisc({ ...m, serie: s.nome })} style={{ cursor: d.pode_editar ? 'pointer' : 'default' }}>
                          <td className="py-1.5 font-semibold">{m.componente}</td><td>{m.aulas_semana}</td><td>{m.quem === 'REGENTE' ? 'Regente' : 'Especialista'}</td><td>{m.cobre_hora_atividade ? 'sim' : '—'}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <div className="mt-2 grid gap-2 text-[12.5px] sm:grid-cols-2">
                  <div>Aulas na matriz: <b>{s.aulas_semana}</b> de {capacidade} que a jornada comporta<Meter value={s.aulas_semana} max={capacidade || 1} tone={s.aulas_semana > capacidade ? 'red' : 'blue'} className="mt-1" /></div>
                  <div>Hora-atividade do regente coberta por especialistas: <b>{s.aulas_especialista}</b> de {precisa} aulas<Meter value={s.aulas_especialista} max={precisa || 1} tone={s.aulas_especialista >= precisa ? 'green' : 'amber'} className="mt-1" /></div>
                </div>
              </>
            )}
          </Card>
        );
      })}
      {!(d.series as any[]).some((s) => (s.jornadas as any[]).length) && <EmptyState title="Nenhuma jornada cadastrada" />}
      <JornadaSheet jornada={jornada} podeEditar={d.pode_editar} onClose={() => setJornada(null)} />
      <DisciplinaSheet disc={disc} onClose={() => setDisc(null)} />
    </div>
  );
}

function JornadaSheet({ jornada, podeEditar, onClose }: { jornada: any | null; podeEditar: boolean; onClose: () => void }) {
  const { busy, salvar } = useSalvar(['jornada_gestao']);
  const [f, setF] = useState<any>({});
  const [chave, setChave] = useState<string | null>(null);
  if (jornada && chave !== jornada.id) {
    setChave(jornada.id);
    setF({ inicio: jornada.inicio.slice(0, 5), aulas_dia: jornada.aulas_dia, duracao_aula_min: jornada.duracao_aula_min, intervalo_min: jornada.intervalo_min,
      intervalo_apos: jornada.intervalo_apos, dias_semana: jornada.dias_semana, hora_atividade_pct: jornada.hora_atividade_pct, situacao: jornada.situacao, fundamento: '' });
  }
  const horasAno = Math.round((Number(f.aulas_dia) * Number(f.duracao_aula_min) / 60) * 200);
  const fechar = () => { setChave(null); onClose(); };
  return (
    <Sheet open={!!jornada} onClose={fechar} title={jornada ? `Jornada · ${jornada.serie} · ${SHIFT[jornada.turno] ?? jornada.turno}` : ''} subtitle={jornada ? `Versão ${jornada.versao} · ${jornada.fundamento ?? ''}` : ''}
      footer={podeEditar ? <Button block loading={busy} disabled={(f.fundamento ?? '').length < 10}
        onClick={() => salvar('jornada_salvar', { ...f, grade_code: jornada.grade_code, turno: jornada.turno }, 'Nova versão da jornada salva', fechar)}>Salvar nova versão</Button> : undefined}>
      {jornada && (
        <div className="space-y-3 pt-1">
          <div className="grid grid-cols-2 gap-3">
            <Field label="Início"><input type="time" value={f.inicio} disabled={!podeEditar} onChange={(e) => setF({ ...f, inicio: e.target.value })} className={inputCls} /></Field>
            <Field label="Aulas por dia"><input type="number" min={1} max={10} value={f.aulas_dia} disabled={!podeEditar} onChange={(e) => setF({ ...f, aulas_dia: e.target.value })} className={inputCls} /></Field>
            <Field label="Duração da aula (min)"><input type="number" min={30} max={120} value={f.duracao_aula_min} disabled={!podeEditar} onChange={(e) => setF({ ...f, duracao_aula_min: e.target.value })} className={inputCls} /></Field>
            <Field label="Intervalo (min)"><input type="number" min={0} max={60} value={f.intervalo_min} disabled={!podeEditar} onChange={(e) => setF({ ...f, intervalo_min: e.target.value })} className={inputCls} /></Field>
            <Field label="Intervalo após a aula nº"><input type="number" min={1} max={9} value={f.intervalo_apos} disabled={!podeEditar} onChange={(e) => setF({ ...f, intervalo_apos: e.target.value })} className={inputCls} /></Field>
            <Field label="Hora-atividade (%)" hint="Mínimo 33,33% (1/3)"><input type="number" min={33.33} max={50} step={0.01} value={f.hora_atividade_pct} disabled={!podeEditar} onChange={(e) => setF({ ...f, hora_atividade_pct: e.target.value })} className={inputCls} /></Field>
          </div>
          <p className={clsx('rounded-2xl p-2 text-[13px]', horasAno < 800 ? 'bg-red-50 text-red-900' : 'bg-green-50 text-green-900')}>
            {horasAno} h por ano em 200 dias letivos {horasAno < 800 ? '— abaixo do mínimo de 800 h (LDB, art. 24)' : '— atende ao mínimo de 800 h'}.
          </p>
          {podeEditar && (
            <>
              <label className="flex items-center gap-2 text-[13.5px]"><input type="checkbox" checked={f.situacao === 'CONFIRMADO'} onChange={(e) => setF({ ...f, situacao: e.target.checked ? 'CONFIRMADO' : 'PROPOSTO' })} className="size-5 accent-purple-700" />Confirmado pela SEDUC (sai de “proposto”)</label>
              <Field label="Fundamento da alteração"><textarea value={f.fundamento} onChange={(e) => setF({ ...f, fundamento: e.target.value })} rows={2} className={`${inputCls} h-auto py-3`} /></Field>
            </>
          )}
        </div>
      )}
    </Sheet>
  );
}

function DisciplinaSheet({ disc, onClose }: { disc: any | null; onClose: () => void }) {
  const { busy, salvar } = useSalvar(['jornada_gestao']);
  const [f, setF] = useState<any>({});
  const [chave, setChave] = useState<string | null>(null);
  const nova = !!disc && !disc.componente;
  if (disc && chave !== `${disc.grade_code}:${disc.componente ?? ''}`) {
    setChave(`${disc.grade_code}:${disc.componente ?? ''}`);
    setF({ componente: disc.componente ?? '', aulas_semana: disc.aulas_semana ?? 2, quem: disc.quem ?? 'ESPECIALISTA', cobre_hora_atividade: disc.cobre_hora_atividade ?? true });
  }
  const fechar = () => { setChave(null); onClose(); };
  return (
    <Sheet open={!!disc} onClose={fechar} title={nova ? `Nova disciplina · ${disc?.serie}` : `${disc?.componente} · ${disc?.serie}`}
      footer={<div className="flex gap-2">
        {!nova && <Button variant="secondary" icon={Trash2} loading={busy} onClick={() => salvar('matriz_salvar', { grade_code: disc.grade_code, componente: disc.componente, excluir: true }, 'Disciplina excluída', fechar)}>Excluir</Button>}
        <Button block loading={busy} disabled={(f.componente ?? '').length < 3} onClick={() => salvar('matriz_salvar', { ...f, grade_code: disc.grade_code, aulas_semana: Number(f.aulas_semana) }, 'Matriz salva', fechar)}>Salvar</Button>
      </div>}>
      {disc && (
        <div className="space-y-3 pt-1">
          <Field label="Disciplina"><input value={f.componente} disabled={!nova} onChange={(e) => setF({ ...f, componente: e.target.value })} className={inputCls} /></Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Aulas por semana"><input type="number" min={1} max={30} value={f.aulas_semana} onChange={(e) => setF({ ...f, aulas_semana: e.target.value })} className={inputCls} /></Field>
            <Field label="Quem leciona"><select value={f.quem} onChange={(e) => setF({ ...f, quem: e.target.value })} className={inputCls}><option value="REGENTE">Regente</option><option value="ESPECIALISTA">Especialista</option></select></Field>
          </div>
          <label className="flex items-center gap-2 text-[13.5px]"><input type="checkbox" checked={!!f.cobre_hora_atividade} onChange={(e) => setF({ ...f, cobre_hora_atividade: e.target.checked })} className="size-5 accent-purple-700" />
            Estas aulas cobrem a hora-atividade do regente</label>
          <p className="flex items-center gap-1 text-[12px] text-muted"><Network className="size-3.5" aria-hidden />Vale para todas as turmas da série; os horários das turmas usam esta matriz.</p>
        </div>
      )}
    </Sheet>
  );
}
