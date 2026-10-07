import { useState } from 'react';
import { useSearchParams } from 'react-router';
import { keepPreviousData } from '@tanstack/react-query';
import clsx from 'clsx';
import { AlertTriangle, CalendarClock, IdCard, UserPlus, Users, UserX, X } from 'lucide-react';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtInt } from '@/lib/format';
import { DIA_CURTO, FUNCAO_SERVIDOR, RELATORIO_PESSOAL } from '@/lib/escola';
import { Badge, Button, Card, EmptyState, ErrorState, Kpi, PageHeader, Simulado, SkeletonList, Tabs, inputCls } from '@/components/ui';
import { Selecao } from '@/components/cadastro';
import { Paginacao } from './Alunos';
import { ServidorForm } from '@/components/servidor-form';
import { Tabela, TCabecalho, TCelula, TLinha } from '@/components/tabela';
import { UnitSelect } from '@/components/escola';

type Aba = 'servidores' | string;

/** Pessoal: cadastro funcional, carga horária e os relatórios de acompanhamento (seção 13 do documento do portal). */
export default function Pessoal() {
  const { me, can } = useSession();
  const [novo, setNovo] = useState(false);
  const [sp, setSp] = useSearchParams();
  const aba = (sp.get('aba') ?? 'servidores') as Aba;
  const rede = me?.scope !== 'UNIT';
  const [unit, setUnit] = useState<number | null>(rede ? null : me?.unit?.id ?? null);
  const [q, setQ] = useState('');
  const dq = useDebounced(q, 300);
  const rel = useRpc<any>('pessoal_relatorio', { tipo: aba === 'servidores' ? 'carga' : aba, unit_id: unit });
  const r = rel.data?.resumo;
  const setAba = (v: string) => setSp(v === 'servidores' ? {} : { aba: v }, { replace: true });

  return (
    <div>
      <PageHeader eyebrow={rede ? 'SEDUC · rede municipal' : me?.unit?.name} title={<span className="inline-flex items-center gap-2">Pessoal<Simulado detail="Servidores, matrículas funcionais, jornadas e horários são fictícios; as turmas seguem o Censo 2025." /></span>}
        subtitle="Quem está em cada turma, a carga horária de cada servidor e o que falta cobrir na grade."
        actions={<>{rede && <UnitSelect value={unit} onChange={setUnit} />}{can('pessoal.write') && <Button icon={UserPlus} onClick={() => setNovo(true)}>Novo servidor</Button>}</>} />
      <ServidorForm open={novo} onClose={() => setNovo(false)} />

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi compact icon={Users} tone="blue" label="Professores e educadores" value={fmtInt(r?.professores)} sub={`${fmtInt(r?.servidores)} servidores`} />
        <Kpi compact icon={CalendarClock} tone="red" label="Aulas sem professor" value={fmtInt(r?.horarios_sem_professor)} onClick={() => setAba('horarios_sem_professor')} />
        <Kpi compact icon={UserX} tone="amber" label="Sem turma atribuída" value={fmtInt(r?.sem_turma)} onClick={() => setAba('sem_turma')} />
        <Kpi compact icon={AlertTriangle} tone="purple" label="Alunos do AEE sem mediação" value={fmtInt(r?.alunos_aee_sem_mediador)} onClick={() => setAba('mediadores')} />
      </div>

      <Tabs className="mt-4" value={aba} onChange={setAba}
        items={[{ value: 'servidores', label: 'Servidores' }, ...RELATORIO_PESSOAL.map((x) => ({ value: x.value, label: x.label }))]} />
      {aba !== 'servidores' && <p className="mt-2 text-[13px] text-muted">{RELATORIO_PESSOAL.find((x) => x.value === aba)?.hint}</p>}

      <div className="mt-3">
        {aba === 'servidores' ? <Servidores unit={unit} q={dq} setQ={setQ} qv={q} /> : rel.isLoading ? <SkeletonList rows={6} /> : rel.error ? (
          <ErrorState error={rel.error} onRetry={() => rel.refetch()} />
        ) : <Relatorio tipo={aba} itens={rel.data?.itens ?? []} />}
      </div>
    </div>
  );
}

const POR_PAGINA_SERVIDORES = 60;

function Servidores({ unit, q, qv, setQ }: { unit: number | null; q: string; qv: string; setQ: (v: string) => void }) {
  const [f, setF] = useState<Record<string, string>>({});
  const [pagina, setPagina] = useState(1);
  const filtro = (k: string, v: string) => { setF({ ...f, [k]: v }); setPagina(1); };
  const res = useRpc<any>('pessoal_lista', {
    unit_id: unit, q, funcao: f.funcao || null, situacao: f.situacao || null, vinculo: f.vinculo || null, area: f.area || null,
    carga: f.carga || null, regiao_id: f.regiao || null, ordem: f.ordem || null, limite: POR_PAGINA_SERVIDORES, offset: (pagina - 1) * POR_PAGINA_SERVIDORES,
  }, { placeholderData: keepPreviousData });
  const itens = (res.data?.itens ?? []) as any[];
  const op = res.data?.opcoes;
  const ativos = Object.values(f).filter(Boolean).length;
  return (
    <>
      <Card className="mb-3 space-y-2 p-3">
        <input value={qv} onChange={(e) => { setQ(e.target.value); setPagina(1); }} placeholder="Nome (ou parte do nome), matrícula ou cargo…" className={inputCls} aria-label="Buscar servidor" />
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 xl:grid-cols-4">
          <Selecao value={f.funcao ?? ''} onChange={(v) => filtro('funcao', v)} vazio="Função: todas" aria-label="Função"
            opcoes={Object.entries(FUNCAO_SERVIDOR).filter(([k]) => ['PROFESSOR', 'EDUCADOR', 'AEE', 'AUXILIAR'].includes(k)) as [string, string][]} />
          <Selecao value={f.situacao ?? ''} onChange={(v) => filtro('situacao', v)} vazio="Situação: todas" aria-label="Situação"
            opcoes={[['ATIVO', 'Em exercício'], ['LICENCA', 'Licença'], ['AFASTADO', 'Afastado']]} />
          <Selecao value={f.vinculo ?? ''} onChange={(v) => filtro('vinculo', v)} vazio="Vínculo: todos" aria-label="Vínculo" opcoes={(op?.vinculos ?? []) as string[]} />
          <Selecao value={f.area ?? ''} onChange={(v) => filtro('area', v)} vazio="Área: todas" aria-label="Área de atuação" opcoes={((op?.areas ?? []) as string[]).slice().sort()} />
          <Selecao value={f.carga ?? ''} onChange={(v) => filtro('carga', v)} vazio="Carga: todas" aria-label="Carga horária"
            opcoes={[['EXCESSO', 'Acima da capacidade'], ['LIVRE', 'Com aulas livres'], ['COMPLETA', 'Carga completa'], ['SEM_TURMA', 'Sem turma']]} />
          {unit == null && <Selecao value={f.regiao ?? ''} onChange={(v) => filtro('regiao', v)} vazio="Região: todas" aria-label="Região"
            opcoes={((op?.regioes ?? []) as any[]).map((r) => [String(r.id), r.nome] as [string, string])} />}
          <Selecao value={f.ordem ?? ''} onChange={(v) => filtro('ordem', v)} vazio="Ordem alfabética" aria-label="Ordenar"
            opcoes={[['saldo', 'Menor saldo de aulas'], ['unidade', 'Por unidade']]} />
        </div>
        <div className="flex items-center justify-between text-[13px] text-muted">
          <span>{res.data ? `${fmtInt(res.data.total)} servidor(es) encontrados` : ' '}</span>
          {ativos > 0 && <Button size="sm" variant="ghost" icon={X} onClick={() => { setF({}); setPagina(1); }}>Limpar filtros</Button>}
        </div>
      </Card>
      {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <Card className={clsx('overflow-hidden transition-opacity', res.isFetching && res.isPlaceholderData && 'opacity-60')}>
          <Tabela colunas="minmax(200px,1.4fr) 130px minmax(150px,1fr) minmax(120px,0.9fr) 90px 150px 70px" largura={980} rotulo="Servidores">
            <TCabecalho><TCelula>Servidor</TCelula><TCelula>Função</TCelula><TCelula>Unidade</TCelula><TCelula>Área</TCelula><TCelula>Jornada</TCelula><TCelula>Aulas atribuídas</TCelula><TCelula>Turmas</TCelula></TCabecalho>
            {itens.map((s) => (
              <TLinha key={s.id} to={`/pessoal/${s.id}`} alerta={s.disponivel < 0} rotulo={s.nome}>
                <TCelula fixa titulo={`${s.nome} · ${s.matricula ?? ''} · ${s.vinculo ?? ''}`}>
                  <span className="font-semibold">{s.nome}</span> <span className="text-[12px] text-muted">{s.matricula}</span>
                </TCelula>
                <TCelula>{FUNCAO_SERVIDOR[s.funcao] ?? s.funcao}</TCelula>
                <TCelula titulo={s.unidade}>{s.unidade}</TCelula>
                <TCelula titulo={s.area} className="text-muted">{s.area ?? '—'}</TCelula>
                <TCelula>{s.ch ? `${s.ch} h` : '—'}{s.situacao !== 'ATIVO' && <Badge tone="gray" className="ml-1">{s.situacao === 'LICENCA' ? 'Licença' : 'Afastado'}</Badge>}</TCelula>
                <TCelula><CargaBarra atribuidas={s.atribuidas} capacidade={s.capacidade} /></TCelula>
                <TCelula>{fmtInt(s.turmas)}</TCelula>
              </TLinha>
            ))}
          </Tabela>
          {!itens.length && <EmptyState compact title="Nenhum servidor com estes filtros" />}
          <Paginacao pagina={pagina} total={Number(res.data?.total ?? 0)} porPagina={POR_PAGINA_SERVIDORES} onPagina={setPagina} />
        </Card>
      )}
    </>
  );
}

export function CargaBarra({ atribuidas, capacidade }: { atribuidas: number; capacidade: number | null }) {
  if (!capacidade) return <span className="text-muted">—</span>;
  const pct = Math.min(100, Math.round((100 * atribuidas) / capacidade));
  const excesso = atribuidas > capacidade;
  return (
    <span className="flex items-center gap-2">
      <span className="h-2 w-16 overflow-hidden rounded-full bg-slate-100">
        <span className={`block h-full rounded-full ${excesso ? 'bg-red-500' : pct >= 90 ? 'bg-green-600' : 'bg-blue-500'}`} style={{ width: `${pct}%` }} />
      </span>
      <span className={`tabular ${excesso ? 'font-bold text-red-700' : ''}`}>{atribuidas}/{capacidade}</span>
    </span>
  );
}

function Relatorio({ tipo, itens }: { tipo: string; itens: any[] }) {
  if (!itens.length) return <Card><EmptyState compact title="Nada a apontar" body="Este relatório está limpo para o recorte escolhido." /></Card>;
  const linhas: Record<string, { colunas: string; largura: number; cab: string[]; linha: (x: any) => React.ReactNode; to?: (x: any) => string; alerta?: (x: any) => boolean }> = {
    carga: {
      colunas: 'minmax(200px,1.4fr) minmax(140px,1fr) 120px 80px 150px 90px', largura: 860,
      cab: ['Servidor', 'Unidade', 'Área', 'Jornada', 'Aulas', 'Saldo'],
      to: (x) => `/pessoal/${x.id}`, alerta: (x) => x.disponivel < 0,
      linha: (x) => (<>
        <TCelula fixa titulo={x.nome}><span className="font-semibold">{x.nome}</span></TCelula><TCelula>{x.unidade}</TCelula><TCelula titulo={x.area}>{x.area}</TCelula>
        <TCelula>{x.ch} h</TCelula><TCelula><CargaBarra atribuidas={x.atribuidas} capacidade={x.capacidade} /></TCelula>
        <TCelula className={x.disponivel < 0 ? 'font-bold text-red-700' : x.disponivel > 0 ? 'text-blue-800' : 'text-green-700'}>{x.disponivel > 0 ? `+${x.disponivel}` : x.disponivel}</TCelula>
      </>),
    },
    sem_turma: {
      colunas: 'minmax(200px,1.4fr) minmax(140px,1fr) 130px 120px 80px', largura: 760, cab: ['Servidor', 'Unidade', 'Função', 'Área', 'Jornada'],
      to: (x) => `/pessoal/${x.id}`,
      linha: (x) => (<><TCelula fixa titulo={x.nome}><span className="font-semibold">{x.nome}</span></TCelula><TCelula>{x.unidade}</TCelula>
        <TCelula>{FUNCAO_SERVIDOR[x.funcao] ?? x.funcao}</TCelula><TCelula titulo={x.area}>{x.area}</TCelula><TCelula>{x.ch} h</TCelula></>),
    },
    horarios_sem_professor: {
      colunas: 'minmax(140px,1fr) 120px minmax(150px,1fr) 70px 110px', largura: 640, cab: ['Unidade', 'Turma', 'Componente', 'Dia', 'Aula'],
      to: (x) => `/turmas/${x.turma_id}`, alerta: () => true,
      linha: (x) => (<><TCelula fixa>{x.unidade}</TCelula><TCelula>{x.turma}</TCelula><TCelula>{x.componente}</TCelula><TCelula>{DIA_CURTO[x.dia]}</TCelula><TCelula>{x.aula}ª · {x.hora}</TCelula></>),
    },
    choques: {
      colunas: 'minmax(200px,1.3fr) minmax(130px,1fr) 70px 110px minmax(160px,1fr)', largura: 760, cab: ['Servidor', 'Unidade', 'Dia', 'Aula', 'Turmas no mesmo horário'],
      to: (x) => `/pessoal/${x.id}`, alerta: () => true,
      linha: (x) => (<><TCelula fixa titulo={x.nome}><span className="font-semibold">{x.nome}</span></TCelula><TCelula>{x.unidade}</TCelula><TCelula>{DIA_CURTO[x.dia]}</TCelula>
        <TCelula>{x.aula}ª · {x.turno === 'MANHA' ? 'manhã' : 'tarde'}</TCelula><TCelula titulo={x.turmas}>{x.turmas}</TCelula></>),
    },
    mediadores: {
      colunas: 'minmax(140px,1fr) 120px 110px minmax(180px,1.2fr)', largura: 640, cab: ['Unidade', 'Aluno', 'Turma', 'Mediação'],
      to: (x) => (x.mediador_id ? `/pessoal/${x.mediador_id}` : ''), alerta: (x) => !x.coberto,
      linha: (x) => (<><TCelula fixa>{x.unidade}</TCelula><TCelula>{x.aluno}</TCelula><TCelula>{x.turma}</TCelula>
        <TCelula>{x.coberto ? x.mediador : <span className="font-semibold text-red-700">Sem mediador(a)</span>}</TCelula></>),
    },
    curricular: {
      colunas: 'minmax(140px,1fr) minmax(160px,1fr) 110px 110px 110px', largura: 700, cab: ['Unidade', 'Componente', 'Necessárias', 'Atribuídas', 'Cobertura'],
      alerta: (x) => x.cobertura_pct < 100,
      linha: (x) => (<><TCelula fixa>{x.unidade}</TCelula><TCelula>{x.componente}</TCelula><TCelula>{fmtInt(x.aulas_necessarias)}</TCelula>
        <TCelula>{fmtInt(x.aulas_atribuidas)}</TCelula><TCelula className={x.cobertura_pct < 100 ? 'font-bold text-red-700' : 'text-green-700'}>{x.cobertura_pct}%</TCelula></>),
    },
  };
  const L = linhas[tipo];
  if (!L) return null;
  return (
    <Card className="overflow-hidden">
      <Tabela colunas={L.colunas} largura={L.largura} rotulo={RELATORIO_PESSOAL.find((x) => x.value === tipo)?.label ?? tipo}>
        <TCabecalho>{L.cab.map((c) => <TCelula key={c}>{c}</TCelula>)}</TCabecalho>
        {itens.map((x, i) => {
          const to = L.to?.(x);
          return <TLinha key={i} to={to || undefined} alerta={L.alerta?.(x)}>{L.linha(x)}</TLinha>;
        })}
      </Tabela>
      <p className="border-t border-line p-2.5 text-center text-[12px] text-muted"><IdCard className="mr-1 inline size-3.5" />{fmtInt(itens.length)} linha(s){itens.length >= 400 ? ' (as 400 primeiras)' : ''}</p>
    </Card>
  );
}
