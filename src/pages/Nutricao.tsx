import { useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import { ChefHat, ChevronLeft, ChevronRight, Salad, ShieldCheck, Soup, Utensils } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtInt, timeAgo } from '@/lib/format';
import { DIA_CURTO, FAIXA_CARDAPIO, MOTIVO_RESTRICAO, REFEICAO, diaCurto, hojeISO } from '@/lib/escola';
import { Badge, Button, Card, EmptyState, ErrorState, Kpi, PageHeader, Section, Segmented, Simulado, SkeletonList, Tabs } from '@/components/ui';
import { Tabela, TCabecalho, TCelula, TLinha } from '@/components/tabela';
import { AreaChart } from '@/components/charts';
import { useToast } from '@/components/overlays';
import { UnitSelect } from '@/components/escola';

type Aba = 'cardapio' | 'restricoes' | 'refeicoes';
const REFEICOES = ['DESJEJUM', 'ALMOCO', 'LANCHE', 'JANTAR'];

function somaDias(iso: string, n: number) {
  const [y, m, d] = iso.split('-').map(Number);
  const dt = new Date(y, m - 1, d + n);
  return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`;
}

/** Cardápio e nutrição: cardápio semanal por faixa, restrições alimentares (17 categorias, motivo separado) e refeições servidas. */
export default function Nutricao() {
  const { me } = useSession();
  const [sp, setSp] = useSearchParams();
  const aba = (sp.get('aba') ?? 'cardapio') as Aba;
  const rede = me?.scope !== 'UNIT';
  const [unit, setUnit] = useState<number | null>(null);
  const painel = useRpc<any>('nutricao_painel', { unit_id: unit });
  const p = painel.data;
  const aguardando = (p?.por_restricao ?? []).reduce((s: number, r: any) => s + r.aguardando, 0);
  const validadas = (p?.por_restricao ?? []).reduce((s: number, r: any) => s + r.validadas, 0);
  const ultimo = p?.refeicoes_ultimo_dia ?? {};
  const totalUltimo = Object.values(ultimo).reduce((s: number, v: any) => s + Number(v), 0);

  return (
    <div>
      <PageHeader eyebrow={rede ? 'SEDUC · alimentação escolar' : me?.unit?.name}
        title={<span className="inline-flex items-center gap-2">Cardápio e nutrição<Simulado detail="Cardápios, restrições e refeições são de demonstração; as 17 categorias de restrição são as do sistema atual da SEDUC." /></span>}
        subtitle="Cada criança comendo o que pode: a família informa, a nutrição valida e a cozinha recebe só a instrução de preparo — nunca o laudo."
        actions={<>{rede && <UnitSelect value={unit} onChange={setUnit} />}<Link to="/cozinha" className="inline-flex h-10 items-center gap-1.5 rounded-2xl bg-white px-3 text-[14px] font-semibold ring-1 ring-line hover:bg-blue-50"><ChefHat className="size-4" />Lista da cozinha</Link></>} />

      {painel.error ? <ErrorState error={painel.error} onRetry={() => painel.refetch()} /> : (
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <Kpi compact icon={Utensils} tone="green" label="Refeições no último dia letivo" value={fmtInt(totalUltimo)} sub={p?.ultimo_dia ? diaCurto(p.ultimo_dia) : undefined} />
          <Kpi compact icon={Soup} tone="blue" label="Refeições no mês" value={fmtInt(p?.refeicoes_mes)} sub={`${fmtInt(p?.refeicoes_ano)} no ano`} />
          <Kpi compact icon={Salad} tone="purple" label="Restrições validadas" value={fmtInt(validadas)} sub={`${fmtInt(p?.adaptadas_ultimo_dia)} refeições adaptadas no último dia`} onClick={() => setSp({ aba: 'restricoes' })} />
          <Kpi compact icon={ShieldCheck} tone="amber" label="Aguardando a nutrição" value={fmtInt(aguardando)} onClick={() => setSp({ aba: 'restricoes' })} />
        </div>
      )}

      <Tabs className="mt-4" value={aba} onChange={(v) => setSp({ aba: v }, { replace: true })}
        items={[{ value: 'cardapio', label: 'Cardápio da semana' }, { value: 'restricoes', label: 'Restrições', count: aguardando || null }, { value: 'refeicoes', label: 'Refeições servidas' }]} />
      <div className="mt-3">
        {aba === 'cardapio' && <CardapioSemana />}
        {aba === 'restricoes' && (painel.isLoading ? <SkeletonList rows={6} /> : <Restricoes p={p} />)}
        {aba === 'refeicoes' && (painel.isLoading ? <SkeletonList rows={4} /> : <Refeicoes p={p} />)}
      </div>
    </div>
  );
}

export function CardapioSemana({ faixaInicial = 'EF' }: { faixaInicial?: string }) {
  const [data, setData] = useState(hojeISO());
  const [faixa, setFaixa] = useState(faixaInicial);
  const res = useRpc<any>('cardapio', { data });
  if (res.isLoading) return <SkeletonList rows={4} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const f = (res.data?.faixas ?? []).find((x: any) => x.faixa === faixa);
  return (
    <>
      <div className="mb-3 flex flex-wrap items-center gap-2">
        <Segmented value={faixa} onChange={setFaixa} items={Object.entries(FAIXA_CARDAPIO).map(([value, label]) => ({ value, label }))} />
        <div className="ml-auto flex items-center gap-1">
          <Button size="sm" variant="secondary" icon={ChevronLeft} onClick={() => setData(somaDias(res.data.semana_inicio, -7))} aria-label="Semana anterior" />
          <span className="px-2 text-[13.5px] font-semibold">Semana de {diaCurto(res.data?.semana_inicio)}</span>
          <Button size="sm" variant="secondary" icon={ChevronRight} onClick={() => setData(somaDias(res.data.semana_inicio, 7))} aria-label="Próxima semana" />
        </div>
      </div>
      {!f ? <Card><EmptyState compact title="Cardápio não publicado" body="A nutrição publica o cardápio na semana anterior." /></Card> : <GradeCardapio f={f} />}
      {f?.responsavel && <p className="mt-2 text-[12.5px] text-muted">Responsável técnica: {f.responsavel}</p>}
    </>
  );
}

/** Dias × refeições; quando há troca por restrição, o item trocado aparece riscado e o substituto em destaque. */
export function GradeCardapio({ f }: { f: any }) {
  const refeicoes = REFEICOES.filter((r) => (f.dias as any[]).some((d) => (d.refeicoes as any[]).some((x) => x.refeicao === r)));
  const hoje = hojeISO();
  return (
    <div role="region" aria-label="Cardápio da semana" tabIndex={0} className="overflow-x-auto">
      <div className="grid min-w-[720px] gap-1.5" style={{ gridTemplateColumns: `110px repeat(${f.dias.length}, minmax(0, 1fr))` }}>
        <div />
        {(f.dias as any[]).map((d) => (
          <div key={d.dia} className={`rounded-xl px-2 py-1 text-center text-[12px] font-bold ${d.data === hoje ? 'bg-purple-700 text-white' : 'text-subtle'}`}>
            {DIA_CURTO[d.dia]} {d.data.slice(8, 10)}/{d.data.slice(5, 7)}
          </div>
        ))}
        {refeicoes.map((r) => (
          <div key={r} className="contents">
            <div className="flex items-center rounded-xl bg-slate-50 px-2 text-[12px] font-bold ring-1 ring-line">{REFEICAO[r]}</div>
            {(f.dias as any[]).map((d) => {
              const ref = (d.refeicoes as any[]).find((x) => x.refeicao === r);
              return (
                <div key={d.dia} className="min-w-0 rounded-xl bg-white p-2 text-[12.5px] ring-1 ring-line">
                  {(ref?.itens ?? []).map((it: any, i: number) => (
                    <div key={i} className="leading-snug">
                      {it.troca ? (<><span className="text-muted line-through">{it.nome}</span><br /><span className="font-semibold text-green-800">→ {it.troca}</span></>) : it.nome}
                    </div>
                  ))}
                </div>
              );
            })}
          </div>
        ))}
      </div>
    </div>
  );
}

function Restricoes({ p }: { p: any }) {
  const { can } = useSession();
  const qc = useQueryClient();
  const toast = useToast();
  const validar = async (id: string, ok: boolean) => {
    try {
      await rpc('restricao_validar', { id, validar: ok });
      toast({ title: ok ? 'Restrição validada' : 'Restrição não validada', description: ok ? 'A cozinha da unidade já recebe a instrução de preparo.' : 'A família é avisada no portal.', tone: 'success' });
      qc.invalidateQueries({ queryKey: ['nutricao_painel'] });
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    }
  };
  const fila = (p?.aguardando_validacao ?? []) as any[];
  return (
    <>
      {can('nutricao.manage') && (
        <Section title={`Aguardando validação (${fmtInt(fila.length)})`} className="mt-0" subtitle="Restrições clínicas pedem laudo, entregue na secretaria da unidade. Religião e opção da família não pedem laudo.">
          <Card className="overflow-hidden">
            <Tabela colunas="minmax(180px,1.2fr) minmax(140px,1fr) minmax(200px,1.4fr) 100px 210px" largura={940} rotulo="Restrições aguardando validação">
              <TCabecalho><TCelula>Aluno</TCelula><TCelula>Unidade</TCelula><TCelula>Restrição</TCelula><TCelula>Informada</TCelula><TCelula className="text-right">Decisão</TCelula></TCabecalho>
              {fila.map((r) => (
                <TLinha key={r.id}>
                  <TCelula fixa titulo={r.aluno}><span className="font-semibold">{r.aluno}</span></TCelula>
                  <TCelula titulo={`${r.unidade} · ${r.turma}`}>{r.unidade}</TCelula>
                  <TCelula titulo={r.restricao}>{r.exige_laudo && <Badge tone="purple" className="mr-1">Laudo</Badge>}{r.restricao}{r.detalhe ? ` (${r.detalhe})` : ''}</TCelula>
                  <TCelula>{timeAgo(r.informada_em)}</TCelula>
                  <TCelula livre className="flex justify-end gap-1.5">
                    <Button size="sm" variant="secondary" onClick={() => validar(r.id, false)}>Não validar</Button>
                    <Button size="sm" variant="success" onClick={() => validar(r.id, true)}>Validar</Button>
                  </TCelula>
                </TLinha>
              ))}
            </Tabela>
            {!fila.length && <EmptyState compact title="Nada aguardando" />}
          </Card>
        </Section>
      )}
      <Section title="Restrições por categoria" subtitle="As 17 categorias do sistema atual, com o motivo separado (alergia, intolerância, saúde, religião ou opção).">
        <Card className="overflow-hidden">
          <Tabela colunas="minmax(260px,2fr) 150px 100px 110px" largura={640} rotulo="Restrições por categoria">
            <TCabecalho><TCelula>Restrição</TCelula><TCelula>Motivo</TCelula><TCelula>Validadas</TCelula><TCelula>Aguardando</TCelula></TCabecalho>
            {((p?.por_restricao ?? []) as any[]).map((r) => (
              <TLinha key={r.codigo}>
                <TCelula fixa titulo={r.descricao}>{r.descricao}</TCelula>
                <TCelula><Badge tone={MOTIVO_RESTRICAO[r.motivo]?.tone}>{MOTIVO_RESTRICAO[r.motivo]?.label}</Badge></TCelula>
                <TCelula className="tabular font-semibold">{fmtInt(r.validadas)}</TCelula>
                <TCelula className={r.aguardando ? 'tabular font-semibold text-amber-700' : 'tabular text-muted'}>{fmtInt(r.aguardando)}</TCelula>
              </TLinha>
            ))}
          </Tabela>
        </Card>
      </Section>
    </>
  );
}

function Refeicoes({ p }: { p: any }) {
  const ultimo = p?.refeicoes_ultimo_dia ?? {};
  const pontos = ((p?.por_dia ?? []) as any[]).map((d) => ({ label: d.data.slice(8, 10) + '/' + d.data.slice(5, 7), value: Number(d.quantidade) }));
  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_1.4fr]">
      <Card className="p-4">
        <div className="text-[12px] font-bold uppercase tracking-wide text-subtle">Último dia letivo · {diaCurto(p?.ultimo_dia)}</div>
        <div className="mt-2 space-y-1.5">
          {REFEICOES.filter((r) => ultimo[r] != null).map((r) => (
            <div key={r} className="flex items-center justify-between rounded-2xl bg-slate-50 px-3 py-2 ring-1 ring-line">
              <span className="font-semibold">{REFEICAO[r]}</span><span className="font-display text-lg font-black tabular">{fmtInt(ultimo[r])}</span>
            </div>
          ))}
        </div>
        {p?.unidades_sem_registro?.length > 0 && (
          <p className="mt-3 rounded-2xl bg-amber-50 p-2.5 text-[12.5px] text-amber-900">Sem registro no dia: {(p.unidades_sem_registro as string[]).slice(0, 8).join(', ')}{p.unidades_sem_registro.length > 8 ? '…' : ''}</p>
        )}
        <p className="mt-3 text-[12.5px] text-muted">A quantidade vem da presença registrada na chamada: quem faltou não entra na conta da cozinha.</p>
      </Card>
      <Card className="p-4">
        <div className="mb-2 text-[12px] font-bold uppercase tracking-wide text-subtle">Refeições por dia · últimos 30 dias</div>
        {pontos.length > 1 ? <AreaChart points={pontos} height={170} color="#008C72" /> : <EmptyState compact title="Sem registros no período" />}
      </Card>
    </div>
  );
}
