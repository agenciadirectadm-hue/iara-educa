import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router';
import { keepPreviousData } from '@tanstack/react-query';
import clsx from 'clsx';
import { AlertCircle, Apple, CheckCircle2, ChevronLeft, ChevronRight, MapPin, Plus, Search, ShieldAlert, ShieldCheck, SlidersHorizontal, Users, X } from 'lucide-react';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useBootstrap, useGeoLayers, useUnitsMap } from '@/lib/data';
import { fmtInt } from '@/lib/format';
import { PARENTESCO, SITUACAO_ALUNO } from '@/lib/cadastro';
import { Avatar, Badge, Button, ButtonLink, Card, EmptyState, ErrorState, MarcaSimulado, PageHeader, SkeletonList, SourceChip, inputCls } from '@/components/ui';
import { Selecao } from '@/components/cadastro';

const POR_PAGINA = 40;

/** Filtros guardados na URL (o "voltar" do navegador mantém a busca). */
export function useFiltrosUrl() {
  const [sp, setSp] = useSearchParams();
  const set = (patch: Record<string, string | number | boolean | null>) => {
    const p = new URLSearchParams(sp);
    for (const [k, v] of Object.entries(patch)) {
      if (v === null || v === '' || v === false) p.delete(k);
      else p.set(k, String(v));
    }
    if (!('pagina' in patch)) p.delete('pagina');
    setSp(p, { replace: true });
  };
  return { sp, set };
}

export function Paginacao({ pagina, total, porPagina, onPagina }: { pagina: number; total: number; porPagina: number; onPagina: (p: number) => void }) {
  const paginas = Math.max(1, Math.ceil(total / porPagina));
  if (total <= porPagina) return null;
  return (
    <div className="flex items-center justify-between gap-2 border-t border-line px-4 py-3 text-[13px] text-muted">
      <span className="tabular">{fmtInt((pagina - 1) * porPagina + 1)}–{fmtInt(Math.min(pagina * porPagina, total))} de {fmtInt(total)}</span>
      <div className="flex gap-2">
        <Button size="sm" variant="secondary" icon={ChevronLeft} disabled={pagina <= 1} onClick={() => onPagina(pagina - 1)}>Anterior</Button>
        <Button size="sm" variant="secondary" disabled={pagina >= paginas} onClick={() => onPagina(pagina + 1)}>Próxima<ChevronRight className="size-4" /></Button>
      </div>
    </div>
  );
}

export function PendenciasFrequentes({ itens, ativo, onEscolher }: { itens: { item: string; n: number }[]; ativo: string; onEscolher: (i: string) => void }) {
  if (!itens.length) return null;
  return (
    <div className="no-scrollbar -mx-4 flex items-center gap-2 overflow-x-auto px-4 pb-1 sm:mx-0 sm:flex-wrap sm:px-0">
      <span className="shrink-0 text-[12.5px] font-semibold text-muted">O que mais falta:</span>
      {itens.slice(0, 6).map((p) => (
        <button key={p.item} onClick={() => onEscolher(ativo === p.item ? '' : p.item)} aria-pressed={ativo === p.item}
          className={clsx('inline-flex h-8 shrink-0 items-center gap-1.5 rounded-full px-3 text-[12.5px] font-semibold ring-1 transition',
            ativo === p.item ? 'bg-amber-500 text-white ring-amber-500' : 'bg-amber-50 text-amber-950 ring-amber-200 hover:bg-amber-100')}>
          {p.item}<span className="tabular opacity-75">{fmtInt(p.n)}</span>
        </button>
      ))}
    </div>
  );
}

export default function Alunos() {
  const { sp, set } = useFiltrosUrl();
  const q = sp.get('q') ?? '';
  const situacao = sp.get('situacao') ?? '';
  const unidade = sp.get('unidade') ?? '';
  const territorio = sp.get('territorio') ?? '';
  const pendencia = sp.get('pendencia') ?? '';
  const pendentes = sp.get('pendentes') === '1';
  const ordem = sp.get('ordem') ?? 'nome';
  // filtros da busca avançada (todos na URL)
  const sexo = sp.get('sexo') ?? '';
  const idadeMin = sp.get('idade_min') ?? '';
  const idadeMax = sp.get('idade_max') ?? '';
  const serie = sp.get('serie') ?? '';
  const turno = sp.get('turno') ?? '';
  const turma = sp.get('turma') ?? '';
  const restricao = sp.get('restricao') ?? '';
  const ocorrencias = sp.get('ocorrencias') ?? '';
  const aee = sp.get('aee') === '1';
  const avancados = [sexo, idadeMin, idadeMax, serie, turno, turma, restricao, ocorrencias, aee ? '1' : ''].filter(Boolean).length;
  const [maisFiltros, setMaisFiltros] = useState(avancados > 0);
  const boot = useBootstrap();
  const catalogo = useRpc<any>('cardapio', {}, { staleTime: 30 * 60_000, enabled: maisFiltros });
  const pagina = Math.max(1, Number(sp.get('pagina') ?? 1));
  const [texto, setTexto] = useState(q);
  const dq = useDebounced(texto, 350);
  useEffect(() => {
    if (dq !== q) set({ q: dq });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dq]);
  const units = useUnitsMap();
  const geo = useGeoLayers();
  const res = useRpc<any>('alunos_lista', {
    q: q || null, situacao: situacao || null, unidade_id: unidade || null, territorio_id: territorio || null, pendencia: pendencia || null,
    pendentes, ordem, limite: POR_PAGINA, offset: (pagina - 1) * POR_PAGINA,
    sexo: sexo || null, idade_min: idadeMin || null, idade_max: idadeMax || null, serie_id: serie || null, turno: turno || null,
    turma_id: turma || null, restricao: restricao || null, ocorrencias: ocorrencias || null, aee,
  }, { placeholderData: keepPreviousData });
  const d = res.data;
  const c = d?.contagem ?? {};
  const rede = d?.escopo === 'NETWORK';
  const pctCompleto = c.todos ? (100 * c.completos) / c.todos : 0;
  const territorios = ((geo.data?.regions?.features ?? []) as any[]).map((f) => [String(f.properties.id), f.properties.name] as [string, string]);

  return (
    <div>
      <PageHeader
        eyebrow={d?.escopo === 'UNIT' ? `Cadastro · ${d.unidade}` : 'Cadastro 360º · rede municipal'}
        title="Alunos"
        subtitle="Cada criança com dados pessoais, documentos, filiação, responsáveis e o endereço marcado no mapa. O que falta para o cadastro ficar completo aparece em cada ficha."
        actions={d?.pode_editar ? <ButtonLink to="/alunos/novo" variant="purple" icon={Plus}>Novo aluno</ButtonLink> : undefined}
      />

      <div className="mb-3 grid grid-cols-2 gap-2 lg:grid-cols-4">
        <Resumo icon={Users} rotulo={d?.escopo === 'UNIT' ? 'alunos da unidade' : 'alunos na rede'} valor={fmtInt(c.todos ?? 0)} />
        <Resumo icon={CheckCircle2} rotulo="com cadastro completo" valor={`${Math.round(pctCompleto)}%`} sub={`${fmtInt(c.completos ?? 0)} alunos`} tom="green" />
        <Resumo icon={AlertCircle} rotulo="com pendência" valor={fmtInt(c.pendentes ?? 0)} tom="amber" ativo={pendentes}
          onClick={() => set({ pendentes: pendentes ? null : 1 })} />
        <Resumo icon={MapPin} rotulo="localização aproximada" valor={fmtInt(c.aproximada ?? 0)} sub="ponto a conferir no mapa" />
      </div>

      <Card className="mb-3 space-y-3 p-3">
        <div className="relative">
          <Search className="pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-subtle" />
          <input value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="Nome, nome social, código da rede, CPF ou código INEP"
            className={clsx(inputCls, 'pl-11')} aria-label="Buscar aluno" />
          {texto && <button className="absolute right-3 top-1/2 -translate-y-1/2" onClick={() => setTexto('')} aria-label="Limpar"><X className="size-5 text-subtle" /></button>}
        </div>
        <div className="no-scrollbar -mx-3 flex gap-1.5 overflow-x-auto px-3">
          {[['', 'Todos', c.todos], ...Object.entries(SITUACAO_ALUNO).map(([k, v]) => [k, v.label, c[k]])].map(([k, l, n]) => (
            <button key={k as string} onClick={() => set({ situacao: k as string })} aria-pressed={situacao === k}
              className={clsx('inline-flex h-9 shrink-0 items-center gap-1.5 rounded-full px-3.5 text-[13px] font-semibold transition',
                situacao === k ? 'bg-purple-700 text-white' : 'bg-slate-100 text-ink-2 hover:bg-slate-200')}>
              {l as string}{n != null && <span className="tabular text-[12px] opacity-70">{fmtInt(n as number)}</span>}
            </button>
          ))}
        </div>
        <div className={clsx('grid grid-cols-1 gap-2', rede ? 'sm:grid-cols-3' : 'sm:grid-cols-2')}>
          {rede && (
            <Selecao value={unidade} onChange={(v) => set({ unidade: v })} vazio="Todas as unidades" aria-label="Unidade"
              opcoes={((units.data?.units ?? []) as any[]).slice().sort((a, b) => a.name.localeCompare(b.name)).map((u) => [String(u.id), u.name] as [string, string])} />
          )}
          <Selecao value={territorio} onChange={(v) => set({ territorio: v })} vazio="Todos os territórios" aria-label="Território" opcoes={territorios} />
          <Selecao value={ordem} onChange={(v) => set({ ordem: v === 'nome' ? null : v })} vazio={false} aria-label="Ordenar"
            opcoes={[['nome', 'Ordem alfabética'], ['idade', 'Mais novos primeiro'], ['pendencias', 'Mais pendências primeiro'], ['recentes', 'Atualizados recentemente']]} />
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Button size="sm" variant={maisFiltros ? 'soft' : 'secondary'} icon={SlidersHorizontal} onClick={() => setMaisFiltros(!maisFiltros)}>
            Mais filtros{avancados ? ` (${avancados})` : ''}
          </Button>
          {avancados > 0 && (
            <Button size="sm" variant="ghost" icon={X} onClick={() => set({ sexo: null, idade_min: null, idade_max: null, serie: null, turno: null, turma: null, restricao: null, ocorrencias: null, aee: null })}>
              Limpar filtros
            </Button>
          )}
        </div>
        {maisFiltros && (
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 xl:grid-cols-4">
            <Selecao value={sexo} onChange={(v) => set({ sexo: v })} vazio="Sexo: todos" aria-label="Sexo" opcoes={[['F', 'Feminino'], ['M', 'Masculino']]} />
            <div className="flex items-center gap-1.5">
              <span className="shrink-0 pl-1 text-[13px] font-semibold text-muted">Idade</span>
              <Selecao className="min-w-0 flex-1" value={idadeMin} onChange={(v) => set({ idade_min: v })} vazio="de" aria-label="Idade mínima"
                opcoes={Array.from({ length: 16 }, (_, i) => [String(i), `${i} ano${i === 1 ? '' : 's'}`] as [string, string])} />
              <Selecao className="min-w-0 flex-1" value={idadeMax} onChange={(v) => set({ idade_max: v })} vazio="até" aria-label="Idade máxima"
                opcoes={Array.from({ length: 16 }, (_, i) => [String(i), `${i} ano${i === 1 ? '' : 's'}`] as [string, string])} />
            </div>
            <Selecao value={serie} onChange={(v) => set({ serie: v, turma: null })} vazio="Série: todas" aria-label="Série"
              opcoes={((boot.data?.grades ?? []) as any[]).map((g) => [String(g.id), g.name] as [string, string])} />
            <Selecao value={turno} onChange={(v) => set({ turno: v })} vazio="Turno: todos" aria-label="Turno"
              opcoes={[['MANHA', 'Manhã'], ['TARDE', 'Tarde'], ['INTEGRAL', 'Integral'], ['NOITE', 'Noite']]} />
            <Selecao value={turma} onChange={(v) => set({ turma: v })} disabled={!d?.turmas}
              vazio={d?.turmas ? 'Turma: todas' : 'Turma: escolha a unidade'} aria-label="Turma"
              opcoes={((d?.turmas ?? []) as any[]).filter((t) => !turno || t.turno === turno).map((t) => [t.id, t.nome] as [string, string])} />
            <Selecao value={restricao} onChange={(v) => set({ restricao: v })} vazio="Restrição alimentar: tanto faz" aria-label="Restrição alimentar"
              opcoes={[['QUALQUER', 'Com alguma restrição'], ...((catalogo.data?.restricoes ?? []) as any[]).map((r) => [r.codigo, r.descricao.split(' (')[0]] as [string, string])]} />
            <Selecao value={ocorrencias} onChange={(v) => set({ ocorrencias: v })} vazio="Ocorrências: tanto faz" aria-label="Ocorrências"
              opcoes={[['ABERTAS', 'Com ocorrência em aberto'], ['FAMILIA', 'Relatada pela família'], ['QUALQUER', 'Com alguma ocorrência']]} />
            <button onClick={() => set({ aee: aee ? null : 1 })} aria-pressed={aee}
              className={clsx('inline-flex h-12 items-center justify-center gap-1.5 rounded-2xl px-3 text-[14px] font-semibold ring-1 transition',
                aee ? 'bg-purple-700 text-white ring-purple-700' : 'bg-white text-ink-2 ring-line hover:bg-purple-50')}>
              <ShieldCheck className="size-4" />Só AEE / inclusão
            </button>
          </div>
        )}
        <PendenciasFrequentes itens={d?.pendencias_frequentes ?? []} ativo={pendencia} onEscolher={(i) => set({ pendencia: i })} />
      </Card>

      {res.isLoading ? <SkeletonList rows={8} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <Card className={clsx('overflow-hidden transition-opacity', res.isFetching && res.isPlaceholderData && 'opacity-60')}>
          {!d.itens.length ? <EmptyState title="Nenhum aluno com estes filtros" body={q ? 'Confira a grafia ou busque pelo código da rede.' : undefined} /> : (
            <Tabela rotulo="Alunos" largura={1100}
              colunas="minmax(210px,2fr) 66px 122px minmax(150px,1.5fr) minmax(140px,1.2fr) minmax(150px,1.3fr) minmax(120px,1fr) 54px">
              <TCabecalho>
                <span>Aluno</span><span>Idade</span><span>Situação</span><span>Unidade · turma</span><span>Bairro · território</span>
                <span>Responsável</span><span>Pendências</span><span className="text-right">Cadastro</span>
              </TCabecalho>
              {(d.itens as any[]).map((i) => (
                <TLinha key={i.id} to={`/alunos/${i.id}`} rotulo={`${i.nome}, ${i.idade}, cadastro ${i.completo_pct}% completo`}>
                  <TCelula fixa titulo={i.nome_social ? `${i.nome} (nome social: ${i.nome_social})` : i.nome}>
                    <Avatar name={i.nome} seed={i.avatar_seed} size={26} className="mr-2 inline-flex align-middle" />
                    <span className="font-semibold text-ink">{i.nome}</span>
                    {i.nome_social && <span className="text-[12px] text-muted"> · {i.nome_social}</span>}
                    {i.aee && <ShieldCheck className="ml-1 inline size-3.5 align-[-2px] text-purple-700" aria-label="AEE" />}
                    {(i.restricoes ?? []).length > 0 && <span title={`Restrição alimentar: ${i.restricoes.join(', ')}`}><Apple className="ml-1 inline size-3.5 align-[-2px] text-red-600" aria-label="Restrição alimentar" /></span>}
                    {i.ocorrencias_abertas > 0 && <span title={`${i.ocorrencias_abertas} ocorrência(s) em aberto`}><ShieldAlert className="ml-1 inline size-3.5 align-[-2px] text-amber-600" aria-label="Ocorrência em aberto" /></span>}
                    {i.ficticio && <MarcaSimulado className="ml-1" />}
                  </TCelula>
                  <TCelula className="text-muted">{i.idade}</TCelula>
                  <TCelula livre><Badge tone={SITUACAO_ALUNO[i.situacao]?.tone ?? 'gray'}>{SITUACAO_ALUNO[i.situacao]?.label ?? i.situacao}</Badge></TCelula>
                  <TCelula titulo={i.unidade ? `${i.unidade.nome} · ${i.unidade.turma}` : undefined} className="text-ink-2">
                    {i.unidade ? <>{i.unidade.nome} <span className="text-muted">· {i.unidade.turma}</span></> : <span className="text-subtle">sem matrícula</span>}
                  </TCelula>
                  <TCelula titulo={[i.bairro, i.territorio].filter(Boolean).join(' · ')} className="text-muted">
                    {i.bairro ?? 'sem endereço'}{i.territorio ? ` · ${i.territorio}` : ''}
                  </TCelula>
                  <TCelula titulo={i.responsavel?.nome} className="text-muted">
                    {i.responsavel ? <>{(PARENTESCO[i.responsavel.parentesco] ?? 'Resp.').split(' ')[0]}: <span className="text-ink-2">{i.responsavel.nome}</span></> : <span className="font-semibold text-amber-700">sem responsável</span>}
                  </TCelula>
                  <TCelula titulo={i.pendencias.length ? `Falta: ${i.pendencias.join(', ')}` : 'Cadastro completo'}>
                    {i.pendencias.length
                      ? <span className="font-semibold text-amber-700">{i.pendencias[0]}{i.pendencias.length > 1 ? ` +${i.pendencias.length - 1}` : ''}</span>
                      : <span className="inline-flex items-center gap-1 text-green-700"><CheckCircle2 className="size-3.5" />completo</span>}
                  </TCelula>
                  <TCelula className={clsx('text-right font-bold tabular', i.completo_pct >= 100 ? 'text-green-700' : i.completo_pct >= 70 ? 'text-amber-700' : 'text-red-700')}>
                    {i.completo_pct}%
                  </TCelula>
                </TLinha>
              ))}
            </Tabela>
          )}
          <Paginacao pagina={pagina} total={Number(d.total ?? 0)} porPagina={POR_PAGINA} onPagina={(p) => set({ pagina: p })} />
        </Card>
      )}
      <p className="mt-3 flex items-center gap-2 text-[12px] text-muted"><SourceChip kind="demo" detail="Alunos, responsáveis e endereços fictícios; documentos com dígitos verificadores propositalmente inválidos." />Dados pessoais protegidos (LGPD): CPF e contatos mascarados conforme o perfil; acessos e alterações auditados.</p>
    </div>
  );
}

export function Resumo({ icon: I, rotulo, valor, sub, tom = 'purple', ativo, onClick }: {
  icon: typeof Users; rotulo: string; valor: string; sub?: string; tom?: 'purple' | 'green' | 'amber'; ativo?: boolean; onClick?: () => void;
}) {
  const cor = { purple: 'text-purple-700 bg-purple-50', green: 'text-green-700 bg-green-50', amber: 'text-amber-700 bg-amber-50' }[tom];
  const corpo = (
    <>
      <span className={clsx('inline-flex size-9 shrink-0 items-center justify-center rounded-xl', cor)}><I className="size-5" /></span>
      <span className="min-w-0">
        <span className="block font-display text-xl font-black leading-tight tabular">{valor}</span>
        <span className="block text-[12px] font-semibold leading-tight text-muted">{rotulo}</span>
        {sub && <span className="block text-[11px] text-subtle">{sub}</span>}
      </span>
    </>
  );
  const cls = clsx('flex items-center gap-3 rounded-3xl bg-white p-3 text-left shadow-soft ring-1 transition', ativo ? 'ring-2 ring-amber-500' : 'ring-line/70');
  return onClick ? <button onClick={onClick} aria-pressed={ativo} className={clsx(cls, 'hover:ring-amber-300')}>{corpo}</button> : <div className={cls}>{corpo}</div>;
}
