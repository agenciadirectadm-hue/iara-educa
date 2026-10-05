import { useEffect, useState } from 'react';
import { keepPreviousData } from '@tanstack/react-query';
import clsx from 'clsx';
import { AlertCircle, CheckCircle2, HandHeart, Lock, Plus, Search, Users, X } from 'lucide-react';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useGeoLayers } from '@/lib/data';
import { fmtInt } from '@/lib/format';
import { PARENTESCO } from '@/lib/cadastro';
import { Avatar, ButtonLink, Card, EmptyState, ErrorState, MarcaSimulado, PageHeader, SkeletonList, SourceChip, inputCls } from '@/components/ui';
import { Selecao } from '@/components/cadastro';
import { Paginacao, PendenciasFrequentes, Resumo, useFiltrosUrl } from './Alunos';

const POR_PAGINA = 40;

export default function Responsaveis() {
  const { sp, set } = useFiltrosUrl();
  const q = sp.get('q') ?? '';
  const territorio = sp.get('territorio') ?? '';
  const pendencia = sp.get('pendencia') ?? '';
  const pendentes = sp.get('pendentes') === '1';
  const cadunico = sp.get('cadunico') === '1';
  const ordem = sp.get('ordem') ?? 'nome';
  const pagina = Math.max(1, Number(sp.get('pagina') ?? 1));
  const [texto, setTexto] = useState(q);
  const dq = useDebounced(texto, 350);
  useEffect(() => {
    if (dq !== q) set({ q: dq });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dq]);
  const geo = useGeoLayers();
  const res = useRpc<any>('responsaveis_lista', {
    q: q || null, territorio_id: territorio || null, pendencia: pendencia || null, pendentes, cadunico, ordem,
    limite: POR_PAGINA, offset: (pagina - 1) * POR_PAGINA,
  }, { placeholderData: keepPreviousData });
  const d = res.data;
  const c = d?.contagem ?? {};
  const pctCompleto = c.todos ? (100 * c.completos) / c.todos : 0;
  const territorios = ((geo.data?.regions?.features ?? []) as any[]).map((f) => [String(f.properties.id), f.properties.name] as [string, string]);

  return (
    <div>
      <PageHeader
        eyebrow={d?.escopo === 'UNIT' ? `Cadastro · ${d.unidade}` : 'Cadastro 360º · rede municipal'}
        title="Responsáveis"
        subtitle="Mães, pais, avós e demais responsáveis: documentos, contatos, trabalho e renda, composição familiar, endereço no mapa e as crianças vinculadas."
        actions={d?.pode_editar ? <ButtonLink to="/responsaveis/novo" variant="purple" icon={Plus}>Novo responsável</ButtonLink> : undefined}
      />

      <div className="mb-3 grid grid-cols-2 gap-2 lg:grid-cols-4">
        <Resumo icon={Users} rotulo={d?.escopo === 'UNIT' ? 'responsáveis da unidade' : 'responsáveis na rede'} valor={fmtInt(c.todos ?? 0)} />
        <Resumo icon={CheckCircle2} rotulo="com cadastro completo" valor={`${Math.round(pctCompleto)}%`} sub={`${fmtInt(c.completos ?? 0)} pessoas`} tom="green" />
        <Resumo icon={AlertCircle} rotulo="com pendência" valor={fmtInt(c.pendentes ?? 0)} tom="amber" ativo={pendentes} onClick={() => set({ pendentes: pendentes ? null : 1 })} />
        <Resumo icon={HandHeart} rotulo="famílias no CadÚnico" valor={fmtInt(c.cadunico ?? 0)} tom="purple" ativo={cadunico} onClick={() => set({ cadunico: cadunico ? null : 1 })} />
      </div>

      <Card className="mb-3 space-y-3 p-3">
        <div className="relative">
          <Search className="pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-subtle" />
          <input value={texto} onChange={(e) => setTexto(e.target.value)} placeholder={d?.contatos_mascarados ? 'Nome ou CPF' : 'Nome, CPF ou telefone'}
            className={clsx(inputCls, 'pl-11')} aria-label="Buscar responsável" />
          {texto && <button className="absolute right-3 top-1/2 -translate-y-1/2" onClick={() => setTexto('')} aria-label="Limpar"><X className="size-5 text-subtle" /></button>}
        </div>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <Selecao value={territorio} onChange={(v) => set({ territorio: v })} vazio="Todos os territórios" aria-label="Território" opcoes={territorios} />
          <Selecao value={ordem} onChange={(v) => set({ ordem: v === 'nome' ? null : v })} vazio={false} aria-label="Ordenar"
            opcoes={[['nome', 'Ordem alfabética'], ['pendencias', 'Mais pendências primeiro'], ['recentes', 'Atualizados recentemente']]} />
        </div>
        <PendenciasFrequentes itens={d?.pendencias_frequentes ?? []} ativo={pendencia} onEscolher={(i) => set({ pendencia: i })} />
        {d?.contatos_mascarados && <p className="flex items-center gap-1.5 text-[12.5px] text-muted"><Lock className="size-3.5" />CPF e telefones mascarados para o seu perfil.</p>}
      </Card>

      {res.isLoading ? <SkeletonList rows={8} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <Card className={clsx('overflow-hidden transition-opacity', res.isFetching && res.isPlaceholderData && 'opacity-60')}>
          {!d.itens.length ? <EmptyState title="Nenhum responsável com estes filtros" /> : (
            <Tabela rotulo="Responsáveis" largura={1080}
              colunas="minmax(220px,2fr) 124px 128px minmax(190px,1.7fr) minmax(150px,1.3fr) minmax(120px,1fr) 54px">
              <TCabecalho>
                <span>Responsável</span><span>CPF</span><span>Telefone</span><span>Crianças</span><span>Bairro · território</span>
                <span>Pendências</span><span className="text-right">Cadastro</span>
              </TCabecalho>
              {(d.itens as any[]).map((g) => {
                const criancas = (g.criancas as any[]).map((k) => `${k.nome.split(' ')[0]}, ${k.idade}${k.parentesco ? ` (${(PARENTESCO[k.parentesco] ?? k.parentesco).split(' ')[0].toLowerCase()})` : ''}`);
                return (
                  <TLinha key={g.id} to={`/responsaveis/${g.id}`} rotulo={`${g.nome}, cadastro ${g.completo_pct}% completo`}>
                    <TCelula fixa titulo={g.nome}>
                      <Avatar name={g.nome} seed={g.nome} size={26} className="mr-2 inline-flex align-middle" />
                      <span className="font-semibold text-ink">{g.nome}</span>
                      {g.cadunico && <span className="ml-1.5 rounded-full bg-purple-50 px-1.5 py-px text-[10.5px] font-bold text-purple-800 ring-1 ring-purple-200">CadÚnico</span>}
                      {g.mae_solo && <span className="ml-1 rounded-full bg-purple-50 px-1.5 py-px text-[10.5px] font-bold text-purple-800 ring-1 ring-purple-200">mãe solo</span>}
                      {g.ficticio && <MarcaSimulado className="ml-1" />}
                    </TCelula>
                    <TCelula className="tabular text-muted">{g.cpf ?? '—'}</TCelula>
                    <TCelula className="tabular text-muted">{g.telefone ?? '—'}</TCelula>
                    <TCelula titulo={criancas.join(' · ')} className="text-ink-2">{criancas.length ? criancas.join(' · ') : <span className="text-subtle">nenhuma</span>}</TCelula>
                    <TCelula titulo={[g.bairro, g.territorio].filter(Boolean).join(' · ')} className="text-muted">{g.bairro ?? 'sem endereço'}{g.territorio ? ` · ${g.territorio}` : ''}</TCelula>
                    <TCelula titulo={g.pendencias.length ? `Falta: ${g.pendencias.join(', ')}` : 'Cadastro completo'}>
                      {g.pendencias.length
                        ? <span className="font-semibold text-amber-700">{g.pendencias[0]}{g.pendencias.length > 1 ? ` +${g.pendencias.length - 1}` : ''}</span>
                        : <span className="inline-flex items-center gap-1 text-green-700"><CheckCircle2 className="size-3.5" />completo</span>}
                    </TCelula>
                    <TCelula className={clsx('text-right font-bold tabular', g.completo_pct >= 100 ? 'text-green-700' : g.completo_pct >= 60 ? 'text-amber-700' : 'text-red-700')}>{g.completo_pct}%</TCelula>
                  </TLinha>
                );
              })}
            </Tabela>
          )}
          <Paginacao pagina={pagina} total={Number(d.total ?? 0)} porPagina={POR_PAGINA} onPagina={(p) => set({ pagina: p })} />
        </Card>
      )}
      <p className="mt-3 flex items-center gap-2 text-[12px] text-muted"><SourceChip kind="demo" detail="Responsáveis, contatos e endereços fictícios." />Acessos e alterações auditados (LGPD).</p>
    </div>
  );
}
