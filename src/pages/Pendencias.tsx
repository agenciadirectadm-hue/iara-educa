// Central de pendências: o que cada servidor tem a cumprir, o acompanhamento da equipe pela chefia,
// os procedimentos periódicos e as estatísticas da rede (Prefeito sem nomes; Secretário e Superintendência até a pessoa).
import { useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { AlarmClock, CalendarClock, CheckCircle2, ChevronRight, ClipboardList, Gauge, Map as MapIcon, Plus, Search, Timer, Users } from 'lucide-react';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtDateTime, fmtInt } from '@/lib/format';
import { Badge, Button, Card, EmptyState, ErrorState, Kpi, Meter, PageHeader, Section, Segmented, SkeletonList, Tabs, inputCls } from '@/components/ui';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { AtribuirSheet, ListaPendencias, PendenciaSheet, RotinaSheet, type Pendencia } from '@/components/pendencias';

type Aba = 'minhas' | 'equipe' | 'procedimentos' | 'estatisticas';

const pct = (n: number | null | undefined) => (n == null ? '—' : `${fmtInt(n)}%`);
const dias = (n: number | null | undefined) => (n == null ? '—' : `${fmtInt(n)} ${n === 1 ? 'dia' : 'dias'}`);
const dias1 = (n: number | null | undefined) => (n == null ? '—' : `${String(n).replace('.', ',')} ${n === 1 ? 'dia' : 'dias'}`);

export default function Pendencias() {
  const { can } = useSession();
  const [sp, setSp] = useSearchParams();
  const abas = useMemo(() => ([
    can('pend.read') && { value: 'minhas' as Aba, label: 'Minhas pendências' },
    can('pend.equipe') && { value: 'equipe' as Aba, label: 'Equipe' },
    can('pend.rotinas') && { value: 'procedimentos' as Aba, label: 'Procedimentos' },
    can('pend.estatisticas') && { value: 'estatisticas' as Aba, label: 'Estatísticas' },
  ].filter(Boolean) as { value: Aba; label: string }[]), [can]);
  const aba = (abas.find((a) => a.value === sp.get('aba'))?.value ?? abas[0]?.value ?? 'minhas') as Aba;
  const setAba = (a: Aba) => setSp(new URLSearchParams({ aba: a }), { replace: true });
  return (
    <div>
      <PageHeader eyebrow="Rotina de trabalho" title="Central de pendências"
        subtitle="Validações, conferências, aprovações, prazos e procedimentos de cada servidor. O que vem dos módulos sai daqui sozinho quando se resolve na tela própria; tarefas e procedimentos se concluem aqui." />
      {abas.length > 1 && <Tabs className="mb-4" value={aba} onChange={setAba} items={abas} />}
      {aba === 'minhas' && <Minhas />}
      {aba === 'equipe' && <Equipe />}
      {aba === 'procedimentos' && <Procedimentos />}
      {aba === 'estatisticas' && <Estatisticas />}
    </div>
  );
}

// ------------------------------------------------------------------------------------------------ minhas
function Minhas() {
  const [sp, setSp] = useSearchParams();
  const sit = sp.get('s') ?? 'ABERTAS';
  const modulo = sp.get('modulo') ?? '';
  const [aberta, setAberta] = useState<string | null>(null);
  const res = useRpc<any>('pend_minhas', { situacao: sit, modulo }, { staleTime: 30_000 });
  const set = (k: string, v: string) => { const n = new URLSearchParams(sp); if (v) n.set(k, v); else n.delete(k); setSp(n, { replace: true }); };
  const d = res.data;
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const r = d.resumo;
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
        <Kpi compact icon={ClipboardList} tone="purple" label="Em aberto" value={fmtInt(r.abertas)} sub={d.eu?.papel} onClick={() => set('s', '')} />
        <Kpi compact icon={AlarmClock} tone="red" label="Atrasadas" value={fmtInt(r.atrasadas)} onClick={() => set('s', 'ATRASADAS')} />
        <Kpi compact icon={CalendarClock} tone="amber" label="Vencem hoje" value={fmtInt(r.hoje)} sub={`${fmtInt(r.semana)} nos próximos 7 dias`} />
        <Kpi compact icon={CheckCircle2} tone="green" label="Concluídas em 7 dias" value={fmtInt(r.concluidas_7)} onClick={() => set('s', 'CONCLUIDAS')} />
        <Kpi compact icon={Gauge} tone="blue" label="No prazo (30 dias)" value={pct(r.no_prazo_30)} />
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <Segmented value={sit} onChange={(v) => set('s', v === 'ABERTAS' ? '' : v)} items={[
          { value: 'ABERTAS', label: 'Em aberto' }, { value: 'ATRASADAS', label: 'Atrasadas' }, { value: 'CONCLUIDAS', label: 'Concluídas (30 dias)' }]} />
        <select className={inputCls + ' w-auto'} value={modulo} onChange={(e) => set('modulo', e.target.value)} aria-label="Área">
          <option value="">Todas as áreas</option>
          {(d.por_modulo as any[]).map((m) => <option key={m.modulo} value={m.modulo}>{m.modulo} ({fmtInt(m.abertas)})</option>)}
        </select>
        {d.sincronizado_em && <span className="ml-auto text-[12.5px] text-muted">Conferido nos módulos às {fmtDateTime(d.sincronizado_em).split(' ').pop()}</span>}
      </div>
      <Card className="overflow-hidden">
        <ListaPendencias itens={d.itens as Pendencia[]} onAbrir={setAberta}
          vazio={sit === 'CONCLUIDAS' ? 'Nada concluído nos últimos 30 dias.' : sit === 'ATRASADAS' ? 'Nenhuma pendência atrasada.' : 'Nenhuma pendência em aberto.'} />
      </Card>
      <PendenciaSheet id={aberta} onClose={() => setAberta(null)} />
    </div>
  );
}

// ------------------------------------------------------------------------------------------------ equipe
function Equipe() {
  const { me } = useSession();
  const [sp, setSp] = useSearchParams();
  const grupo = sp.get('grupo') ?? '';
  const posto = sp.get('posto') ?? '';
  const filtro = sp.get('filtro') ?? 'TODOS';
  const [busca, setBusca] = useState('');
  const termo = useDebounced(busca, 300);
  const [aberta, setAberta] = useState<string | null>(null);
  const [atribuir, setAtribuir] = useState(false);
  const res = useRpc<any>('pend_equipe', { grupo, posto, filtro, busca: termo }, { staleTime: 30_000 });
  const ir = (k: Record<string, string>) => setSp(new URLSearchParams({ aba: 'equipe', ...k }), { replace: false });
  const naUnidade = me?.role === 'DIRETOR_UNIDADE';
  const d = res.data;
  return (
    <div className="space-y-4">
      <nav className="flex flex-wrap items-center gap-1 text-[13.5px]" aria-label="Caminho">
        {!naUnidade && <button className="font-semibold text-purple-700" onClick={() => ir({})}>Rede</button>}
        {d?.nivel !== 'rede' && grupo && !naUnidade && <ChevronRight className="size-4 text-subtle" />}
        {(d?.nivel === 'grupo' || d?.nivel === 'posto') && (naUnidade || grupo || d?.grupo) && (
          <button className="font-semibold text-purple-700" onClick={() => ir({ grupo: d?.grupo ?? grupo })}>{d?.nivel === 'grupo' ? d?.nome : d?.unidade ?? 'Equipe'}</button>
        )}
        {d?.nivel === 'posto' && <><ChevronRight className="size-4 text-subtle" /><span className="font-semibold">{d.nome}</span></>}
      </nav>
      {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : d.nivel === 'rede' ? (
        <>
          <ResumoEquipe r={d.resumo} />
          <div className="flex flex-wrap items-center gap-2">
            <Segmented value={filtro} onChange={(v) => ir({ filtro: v })} items={[
              { value: 'TODOS', label: 'Tudo' }, { value: 'ESCOLA', label: 'Escolas' }, { value: 'CMEI', label: 'CMEIs' }, { value: 'SETORES', label: 'Setores da SEDUC' }]} />
            <div className="relative"><Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-subtle" /><input className={inputCls + ' w-56 pl-9'} value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Unidade ou setor" /></div>
          </div>
          <Card className="overflow-hidden">
            {(d.grupos as any[]).length ? (
              <Tabela colunas="minmax(240px,1.6fr) 90px minmax(150px,1fr) 100px 100px 100px 110px 100px 110px" largura={1160} rotulo="Unidades e setores">
                <TCabecalho><TCelula fixa>Unidade ou setor</TCelula><TCelula>Tipo</TCelula><TCelula>Região</TCelula><TCelula>Em aberto</TCelula><TCelula>Atrasadas</TCelula>
                  <TCelula>Vencem hoje</TCelula><TCelula>Concluídas 30 d</TCelula><TCelula>No prazo</TCelula><TCelula>Mais antiga</TCelula></TCabecalho>
                {(d.grupos as any[]).map((g) => (
                  <TLinha key={g.grupo} onClick={() => ir({ grupo: g.grupo })} alerta={g.atrasadas > 0} rotulo={g.nome}>
                    <TCelula fixa titulo={g.nome}><span className="font-semibold">{g.nome}</span></TCelula>
                    <TCelula>{g.tipo === 'SETOR' ? 'SEDUC' : g.tipo === 'CMEI' ? 'CMEI' : 'Escola'}</TCelula><TCelula>{g.regiao ?? '—'}</TCelula>
                    <TCelula>{fmtInt(g.abertas)}</TCelula><TCelula>{g.atrasadas ? <b className="text-red-700">{fmtInt(g.atrasadas)}</b> : '0'}</TCelula>
                    <TCelula>{fmtInt(g.hoje)}</TCelula><TCelula>{fmtInt(g.concluidas_30)}</TCelula><TCelula>{pct(g.no_prazo)}</TCelula><TCelula>{dias(g.mais_antiga)}</TCelula>
                  </TLinha>
                ))}
              </Tabela>
            ) : <EmptyState compact title="Nenhuma pendência na sua equipe." />}
          </Card>
        </>
      ) : d.nivel === 'grupo' ? (
        <>
          <div className="flex flex-wrap items-start justify-between gap-3">
            <ResumoEquipe r={d.resumo} postos />
            {d.pode_atribuir && <Button icon={Plus} onClick={() => setAtribuir(true)}>Atribuir tarefa</Button>}
          </div>
          <Card className="overflow-hidden">
            {(d.postos as any[]).length ? (
              <Tabela colunas="minmax(240px,1.6fr) minmax(150px,1fr) 100px 100px 100px 110px 100px 110px" largura={1080} rotulo="Pessoas e postos">
                <TCabecalho><TCelula fixa>Pessoa ou posto</TCelula><TCelula>Função</TCelula><TCelula>Em aberto</TCelula><TCelula>Atrasadas</TCelula><TCelula>Vencem hoje</TCelula>
                  <TCelula>Concluídas 30 d</TCelula><TCelula>No prazo</TCelula><TCelula>Mais antiga</TCelula></TCabecalho>
                {(d.postos as any[]).map((p) => (
                  <TLinha key={p.posto} onClick={() => ir({ grupo: d.grupo, posto: p.posto })} alerta={p.atrasadas > 0} rotulo={p.nome}>
                    <TCelula fixa titulo={p.turmas ? `${p.nome} · ${p.turmas}` : p.nome}>
                      <span className="font-semibold">{p.nome}</span>{p.turmas && <span className="text-muted"> · {p.turmas}</span>}
                    </TCelula>
                    <TCelula>{p.papel}</TCelula><TCelula>{fmtInt(p.abertas)}</TCelula><TCelula>{p.atrasadas ? <b className="text-red-700">{fmtInt(p.atrasadas)}</b> : '0'}</TCelula>
                    <TCelula>{fmtInt(p.hoje)}</TCelula><TCelula>{fmtInt(p.concluidas_30)}</TCelula><TCelula>{pct(p.no_prazo)}</TCelula><TCelula>{dias(p.mais_antiga)}</TCelula>
                  </TLinha>
                ))}
              </Tabela>
            ) : <EmptyState compact title="Nenhuma pendência nesta equipe." />}
          </Card>
          <AtribuirSheet open={atribuir} onClose={() => setAtribuir(false)} grupo={d.grupo} nomeGrupo={d.nome} />
        </>
      ) : (
        <>
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div><div className="text-[18px] font-bold">{d.nome}</div><div className="text-[13px] text-muted">{d.papel}{d.unidade ? ` · ${d.unidade}` : ''}</div></div>
            <Button icon={Plus} onClick={() => setAtribuir(true)}>Atribuir tarefa</Button>
          </div>
          <Card className="overflow-hidden">
            <ListaPendencias itens={d.itens as Pendencia[]} onAbrir={setAberta} vazio="Nada pendente para esta pessoa ou posto." />
          </Card>
          <AtribuirSheet open={atribuir} onClose={() => setAtribuir(false)} grupo={d.grupo} nomeGrupo={d.unidade ?? undefined} postoInicial={d.posto} />
        </>
      )}
      <PendenciaSheet id={aberta} onClose={() => setAberta(null)} />
    </div>
  );
}

function ResumoEquipe({ r, postos }: { r: any; postos?: boolean }) {
  return (
    <div className="grid flex-1 grid-cols-2 gap-3 lg:grid-cols-4">
      <Kpi compact icon={ClipboardList} tone="purple" label="Em aberto" value={fmtInt(r.abertas)} sub={postos ? `${fmtInt(r.postos)} pessoas ou postos` : undefined} />
      <Kpi compact icon={AlarmClock} tone="red" label="Atrasadas" value={fmtInt(r.atrasadas)} />
      <Kpi compact icon={CalendarClock} tone="amber" label="Vencem hoje" value={fmtInt(r.hoje)} />
      <Kpi compact icon={CheckCircle2} tone="green" label="Concluídas em 30 dias" value={fmtInt(r.concluidas_30)} />
    </div>
  );
}

// ------------------------------------------------------------------------------------------------ procedimentos
function Procedimentos() {
  const res = useRpc<any>('pend_rotinas', {});
  const [edit, setEdit] = useState<any | null>(null);
  const [novo, setNovo] = useState(false);
  const d = res.data;
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const onde = (x: any) => x.alvo === 'TODAS' ? 'Todas as unidades' : x.alvo === 'CMEI' ? 'Todos os CMEIs' : x.alvo === 'ESCOLA' ? 'Todas as escolas' : x.alvo === 'UNIDADE' ? x.unidade : 'Setor da SEDUC';
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="max-w-3xl text-[14px] text-muted">
          {d.escopo === 'UNIDADE'
            ? `${d.unidade}: os procedimentos que a direção cadastrou para a equipe e os da SEDUC que valem para a unidade. No início de cada período, cada responsável recebe a pendência com a lista de conferência.`
            : 'Procedimentos que se repetem nas unidades ou nos setores da SEDUC. No início de cada período, cada responsável recebe a pendência com a lista de conferência.'}
        </p>
        <Button icon={Plus} onClick={() => setNovo(true)}>Novo procedimento</Button>
      </div>
      <Card className="overflow-hidden">
        {(d.rotinas as any[]).length ? (
          <Tabela colunas="minmax(260px,1.8fr) minmax(150px,1fr) minmax(150px,1fr) 130px 110px 90px 90px 90px 90px" largura={1240} rotulo="Procedimentos">
            <TCabecalho><TCelula fixa>Procedimento</TCelula><TCelula>Quem cumpre</TCelula><TCelula>Onde</TCelula><TCelula>Repetição</TCelula><TCelula>Próximo</TCelula>
              <TCelula>Abertas</TCelula><TCelula>Atrasadas</TCelula><TCelula>No prazo</TCelula><TCelula>Situação</TCelula></TCabecalho>
            {(d.rotinas as any[]).map((x) => (
              <TLinha key={x.id} onClick={x.editavel ? () => setEdit(x) : undefined} alerta={x.atrasadas > 0} rotulo={x.titulo}>
                <TCelula fixa titulo={x.editavel ? x.titulo : `${x.titulo} — definido pela SEDUC (${x.criada_por ?? 'rede'})`}>
                  <span className="inline-flex items-center gap-1.5"><span className="font-semibold">{x.titulo}</span>{!x.editavel && <Badge tone="blue">da SEDUC</Badge>}</span>
                </TCelula>
                <TCelula>{x.papel_rotulo}</TCelula><TCelula>{onde(x)}</TCelula><TCelula>{x.periodo_rotulo}</TCelula><TCelula>{fmtDate(x.proximo)}</TCelula>
                <TCelula>{fmtInt(x.abertas)}</TCelula><TCelula>{x.atrasadas ? <b className="text-red-700">{fmtInt(x.atrasadas)}</b> : '0'}</TCelula><TCelula>{pct(x.no_prazo)}</TCelula>
                <TCelula livre>{x.ativo ? <Badge tone="green">ativo</Badge> : <Badge tone="gray">desativado</Badge>}</TCelula>
              </TLinha>
            ))}
          </Tabela>
        ) : <EmptyState compact title="Nenhum procedimento cadastrado." body="Cadastre os procedimentos que se repetem: conferências, inventários, relatórios." />}
      </Card>
      <RotinaSheet open={novo || !!edit} onClose={() => { setNovo(false); setEdit(null); }} rotina={edit ?? undefined} papeis={d.papeis} escopo={d.escopo} />
    </div>
  );
}

// ------------------------------------------------------------------------------------------------ estatísticas
function Estatisticas() {
  const { can } = useSession();
  const [sp, setSp] = useSearchParams();
  const diasP = Number(sp.get('dias') ?? 30);
  const regiao = sp.get('regiao') ?? '';
  const tipo = sp.get('tipo') ?? '';
  const res = useRpc<any>('pend_estatisticas', { dias: diasP, regiao, tipo }, { staleTime: 60_000 });
  const set = (k: string, v: string) => { const n = new URLSearchParams(sp); if (v) n.set(k, v); else n.delete(k); setSp(n, { replace: true }); };
  const d = res.data;
  const detalhar = can('pend.equipe');
  const linkGrupo = (g: string) => `/pendencias?aba=equipe&grupo=${encodeURIComponent(g)}`;
  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center gap-2">
        <Segmented value={String(diasP)} onChange={(v) => set('dias', v === '30' ? '' : v)} items={[{ value: '30', label: '30 dias' }, { value: '60', label: '60 dias' }, { value: '90', label: '90 dias' }]} />
        <Segmented value={tipo || 'TODOS'} onChange={(v) => set('tipo', v === 'TODOS' ? '' : v)} items={[
          { value: 'TODOS', label: 'Toda a rede' }, { value: 'ESCOLA', label: 'Escolas' }, { value: 'CMEI', label: 'CMEIs' }, { value: 'SEDUC', label: 'Setores da SEDUC' }]} />
        <select className={inputCls + ' w-auto'} value={regiao} onChange={(e) => set('regiao', e.target.value)} aria-label="Região">
          <option value="">Todas as regiões</option>{((d?.regioes ?? []) as string[]).map((r) => <option key={r} value={r}>{r}</option>)}
        </select>
        <Link to="/mapa?q=pend_atrasadas" className="ml-auto inline-flex h-9 items-center gap-1.5 rounded-2xl bg-white px-3 text-[13px] font-semibold ring-1 ring-line hover:ring-purple-200"><MapIcon className="size-4" />Ver no mapa</Link>
      </div>
      {res.isLoading ? <SkeletonList rows={6} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <>
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-6">
            <Kpi compact icon={ClipboardList} tone="purple" label="Em aberto" value={fmtInt(d.totais.abertas)} sub={`${fmtInt(d.totais.criadas)} surgiram no período`} />
            <Kpi compact icon={AlarmClock} tone="red" label="Atrasadas" value={fmtInt(d.totais.atrasadas)} sub={`${fmtInt(d.totais.postos_com_atraso)} postos com atraso`} />
            <Kpi compact icon={AlarmClock} tone="red" label="Atrasadas há mais de 7 dias" value={fmtInt(d.totais.atrasadas_7)} />
            <Kpi compact icon={CheckCircle2} tone="green" label="Concluídas no período" value={fmtInt(d.totais.concluidas)} />
            <Kpi compact icon={Gauge} tone="blue" label="Concluídas no prazo" value={pct(d.totais.no_prazo)} />
            <Kpi compact icon={Timer} tone="amber" label="Tempo médio para resolver" value={dias1(d.totais.tempo_medio)} />
          </div>

          <Section title="Semana a semana" subtitle="Pendências concluídas em cada semana e quantas estavam atrasadas no fim dela (últimas 12 semanas).">
            <Card className="p-4"><GraficoSemanas semanas={d.evolucao} /></Card>
          </Section>

          <Section title="Por área" subtitle="Onde as pendências se acumulam e quanto se cumpre no prazo.">
            <Card className="overflow-hidden">
              <Tabela colunas="minmax(220px,1.4fr) 100px 100px 110px minmax(160px,1fr) 120px" largura={860} rotulo="Por área">
                <TCabecalho><TCelula fixa>Área</TCelula><TCelula>Em aberto</TCelula><TCelula>Atrasadas</TCelula><TCelula>Concluídas</TCelula><TCelula>No prazo</TCelula><TCelula>Tempo médio</TCelula></TCabecalho>
                {(d.por_modulo as any[]).map((m) => (
                  <TLinha key={m.modulo} alerta={m.atrasadas > 0 && m.atrasadas >= m.abertas / 2}>
                    <TCelula fixa>{m.modulo}</TCelula><TCelula>{fmtInt(m.abertas)}</TCelula><TCelula>{fmtInt(m.atrasadas)}</TCelula><TCelula>{fmtInt(m.concluidas)}</TCelula>
                    <TCelula livre><span className="flex items-center gap-2"><Meter value={m.no_prazo ?? 0} tone={(m.no_prazo ?? 0) >= 90 ? 'green' : (m.no_prazo ?? 0) >= 70 ? 'amber' : 'red'} className="w-20" />{pct(m.no_prazo)}</span></TCelula>
                    <TCelula>{dias1(m.tempo_medio)}</TCelula>
                  </TLinha>
                ))}
              </Tabela>
            </Card>
          </Section>

          <div className="grid gap-5 xl:grid-cols-2">
            <Section title="Por função" subtitle="Quem tem mais pendências atrasadas, sem nomes.">
              <Card className="overflow-hidden">
                <Tabela colunas="minmax(200px,1.4fr) 100px 100px 100px 100px" largura={620} rotulo="Por função">
                  <TCabecalho><TCelula fixa>Função</TCelula><TCelula>Em aberto</TCelula><TCelula>Atrasadas</TCelula><TCelula>Postos</TCelula><TCelula>No prazo</TCelula></TCabecalho>
                  {(d.por_papel as any[]).map((m) => (
                    <TLinha key={m.papel}><TCelula fixa>{m.papel}</TCelula><TCelula>{fmtInt(m.abertas)}</TCelula><TCelula>{fmtInt(m.atrasadas)}</TCelula><TCelula>{fmtInt(m.postos)}</TCelula><TCelula>{pct(m.no_prazo)}</TCelula></TLinha>
                  ))}
                </Tabela>
              </Card>
            </Section>
            <Section title="Por região" subtitle="Pendências das unidades em cada região.">
              <Card className="overflow-hidden">
                <Tabela colunas="minmax(200px,1.4fr) 90px 100px 100px 100px" largura={600} rotulo="Por região">
                  <TCabecalho><TCelula fixa>Região</TCelula><TCelula>Unidades</TCelula><TCelula>Em aberto</TCelula><TCelula>Atrasadas</TCelula><TCelula>No prazo</TCelula></TCabecalho>
                  {(d.por_regiao as any[]).map((m) => (
                    <TLinha key={m.regiao} onClick={() => set('regiao', m.regiao === 'Sem região' ? '' : m.regiao)} ativo={regiao === m.regiao}>
                      <TCelula fixa>{m.regiao}</TCelula><TCelula>{fmtInt(m.unidades)}</TCelula><TCelula>{fmtInt(m.abertas)}</TCelula><TCelula>{fmtInt(m.atrasadas)}</TCelula><TCelula>{pct(m.no_prazo)}</TCelula>
                    </TLinha>
                  ))}
                </Tabela>
              </Card>
            </Section>
          </div>

          <div className="grid gap-5 xl:grid-cols-2">
            <Section title="Unidades com mais atrasadas" subtitle={detalhar ? 'Toque para ver as pessoas e os postos da unidade.' : 'As 20 unidades com mais pendências atrasadas.'}>
              <Card className="overflow-hidden">
                <Tabela colunas="minmax(200px,1.5fr) 80px 100px 100px 100px" largura={620} rotulo="Unidades com mais atrasadas">
                  <TCabecalho><TCelula fixa>Unidade</TCelula><TCelula>Tipo</TCelula><TCelula>Em aberto</TCelula><TCelula>Atrasadas</TCelula><TCelula>No prazo</TCelula></TCabecalho>
                  {(d.por_unidade as any[]).map((u) => (
                    <TLinha key={u.grupo} to={detalhar ? linkGrupo(u.grupo) : undefined} alerta={u.atrasadas > 0} rotulo={u.nome}>
                      <TCelula fixa titulo={u.nome}>{u.nome}</TCelula><TCelula>{u.tipo === 'CMEI' ? 'CMEI' : 'Escola'}</TCelula><TCelula>{fmtInt(u.abertas)}</TCelula>
                      <TCelula>{fmtInt(u.atrasadas)}</TCelula><TCelula>{pct(u.no_prazo)}</TCelula>
                    </TLinha>
                  ))}
                </Tabela>
              </Card>
            </Section>
            <Section title="Setores da SEDUC" subtitle="Pendências dos setores do organograma.">
              <Card className="overflow-hidden">
                {(d.setores as any[]).length ? (
                  <Tabela colunas="minmax(220px,1.6fr) 100px 100px 100px" largura={560} rotulo="Setores da SEDUC">
                    <TCabecalho><TCelula fixa>Setor</TCelula><TCelula>Em aberto</TCelula><TCelula>Atrasadas</TCelula><TCelula>No prazo</TCelula></TCabecalho>
                    {(d.setores as any[]).map((s) => (
                      <TLinha key={s.grupo} to={detalhar ? linkGrupo(s.grupo) : undefined} alerta={s.atrasadas > 0} rotulo={s.nome}>
                        <TCelula fixa titulo={s.nome}>{s.nome}</TCelula><TCelula>{fmtInt(s.abertas)}</TCelula><TCelula>{fmtInt(s.atrasadas)}</TCelula><TCelula>{pct(s.no_prazo)}</TCelula>
                      </TLinha>
                    ))}
                  </Tabela>
                ) : <EmptyState compact title="Nenhuma pendência nos setores." />}
              </Card>
            </Section>
          </div>

          <Section title="Tipos que mais atrasam" subtitle="O que mais fica para trás na rede.">
            <Card className="overflow-hidden">
              <Tabela colunas="minmax(260px,1.8fr) minmax(160px,1fr) minmax(150px,1fr) 100px 100px 100px" largura={980} rotulo="Tipos de pendência">
                <TCabecalho><TCelula fixa>Pendência</TCelula><TCelula>Área</TCelula><TCelula>Função</TCelula><TCelula>Em aberto</TCelula><TCelula>Atrasadas</TCelula><TCelula>No prazo</TCelula></TCabecalho>
                {(d.por_tipo as any[]).map((t) => (
                  <TLinha key={t.tipo}><TCelula fixa titulo={t.titulo}>{t.titulo}</TCelula><TCelula>{t.modulo}</TCelula><TCelula>{t.papel}</TCelula>
                    <TCelula>{fmtInt(t.abertas)}</TCelula><TCelula>{fmtInt(t.atrasadas)}</TCelula><TCelula>{pct(t.no_prazo)}</TCelula></TLinha>
                ))}
              </Tabela>
            </Card>
          </Section>

          {Array.isArray(d.pessoas) && (
            <Section title="Pessoas e postos com mais atrasadas" subtitle="Visível ao Secretário e à Superintendência. Toque para abrir as pendências.">
              <Card className="overflow-hidden">
                {(d.pessoas as any[]).length ? (
                  <Tabela colunas="minmax(220px,1.5fr) minmax(150px,1fr) minmax(160px,1fr) 100px 100px" largura={800} rotulo="Pessoas e postos com mais atrasadas">
                    <TCabecalho><TCelula fixa>Pessoa ou posto</TCelula><TCelula>Função</TCelula><TCelula>Unidade</TCelula><TCelula>Em aberto</TCelula><TCelula>Atrasadas</TCelula></TCabecalho>
                    {(d.pessoas as any[]).map((p) => (
                      <TLinha key={p.posto} to={`/pendencias?aba=equipe&grupo=${encodeURIComponent(p.grupo)}&posto=${encodeURIComponent(p.posto)}`} alerta rotulo={p.nome}>
                        <TCelula fixa titulo={p.nome}><span className="inline-flex items-center gap-1.5"><Users className="size-4 text-subtle" />{p.nome}</span></TCelula>
                        <TCelula>{p.papel}</TCelula><TCelula>{p.unidade ?? 'SEDUC'}</TCelula><TCelula>{fmtInt(p.abertas)}</TCelula><TCelula>{fmtInt(p.atrasadas)}</TCelula>
                      </TLinha>
                    ))}
                  </Tabela>
                ) : <EmptyState compact title="Ninguém com pendência atrasada." />}
              </Card>
            </Section>
          )}
        </>
      )}
    </div>
  );
}

/** Barras: concluídas na semana; linha: atrasadas no fim da semana. Um eixo só (quantidade). */
function GraficoSemanas({ semanas }: { semanas: { semana: string; criadas: number; concluidas: number; no_prazo: number | null; atrasadas: number }[] }) {
  const [foco, setFoco] = useState<number | null>(null);
  if (!semanas?.length) return <EmptyState compact title="Sem dados no período." />;
  const W = 720, H = 220, P = { l: 44, r: 12, t: 12, b: 28 };
  const max = Math.max(1, ...semanas.map((s) => Math.max(s.concluidas, s.atrasadas)));
  const passo = (W - P.l - P.r) / semanas.length;
  const y = (v: number) => P.t + (H - P.t - P.b) * (1 - v / max);
  const ticks = [0, Math.round(max / 2), max];
  const linha = semanas.map((s, i) => `${i ? 'L' : 'M'}${P.l + passo * i + passo / 2},${y(s.atrasadas)}`).join(' ');
  const f = foco != null ? semanas[foco] : null;
  return (
    <div>
      <div className="mb-2 flex flex-wrap items-center gap-4 text-[12.5px]">
        <span className="inline-flex items-center gap-1.5"><span className="inline-block size-3 rounded-sm bg-purple-500" />Concluídas na semana</span>
        <span className="inline-flex items-center gap-1.5"><span className="inline-block h-0.5 w-4 bg-red-600" />Atrasadas no fim da semana</span>
        {f && <span className="ml-auto text-muted">Semana de {fmtDate(f.semana)}: {fmtInt(f.concluidas)} concluídas ({pct(f.no_prazo)} no prazo), {fmtInt(f.atrasadas)} atrasadas, {fmtInt(f.criadas)} novas</span>}
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full" role="img" aria-label="Pendências concluídas e atrasadas por semana" onMouseLeave={() => setFoco(null)}>
        {ticks.map((t) => (
          <g key={t}><line x1={P.l} x2={W - P.r} y1={y(t)} y2={y(t)} stroke="currentColor" className="text-slate-200" strokeWidth={1} />
            <text x={P.l - 6} y={y(t) + 4} textAnchor="end" className="fill-slate-500 text-[11px]">{fmtInt(t)}</text></g>
        ))}
        {semanas.map((s, i) => {
          const x = P.l + passo * i;
          return (
            <g key={s.semana} onMouseEnter={() => setFoco(i)}>
              <rect x={x} y={P.t} width={passo} height={H - P.t - P.b} fill="transparent" />
              <rect x={x + passo * 0.2} y={y(s.concluidas)} width={passo * 0.6} height={Math.max(0, H - P.b - y(s.concluidas))} rx={4}
                className={foco === i ? 'fill-purple-600' : 'fill-purple-400'} />
              <text x={x + passo / 2} y={H - 10} textAnchor="middle" className="fill-slate-500 text-[10.5px]">{fmtDate(s.semana).slice(0, 5)}</text>
              <title>{`Semana de ${fmtDate(s.semana)}: ${s.concluidas} concluídas, ${s.atrasadas} atrasadas no fim`}</title>
            </g>
          );
        })}
        <path d={linha} fill="none" stroke="#dc2626" strokeWidth={2} />
        {semanas.map((s, i) => <circle key={i} cx={P.l + passo * i + passo / 2} cy={y(s.atrasadas)} r={foco === i ? 5 : 3.5} fill="#dc2626" stroke="white" strokeWidth={2} />)}
      </svg>
    </div>
  );
}
