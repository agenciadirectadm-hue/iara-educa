// Controle externo (Ministério Público e Defensoria Pública): a fila está sendo cumprida, com critérios claros?
// Somente leitura e sem dados pessoais. Um caso individual só abre com o protocolo informado pela família (acesso registrado).
import { Link } from 'react-router';
import clsx from 'clsx';
import {
  AlertTriangle, CheckCircle2, ClipboardList, FileSearch, History, ListChecks, ListOrdered, MapPinned, Route, Scale, ScrollText, ShieldCheck, Sparkles, Timer,
} from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtDateTime, fmtInt, fmtKm } from '@/lib/format';
import { Badge, ButtonLink, Card, ErrorState, Kpi, PageHeader, Section, SkeletonList, SourceChip } from '@/components/ui';
import { BarList, Donut } from '@/components/charts';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { LinkMetodologia, MEDIDA, MEDIDAS } from '@/components/distancias';

export const ACAO_GOVERNANCA: Record<string, string> = {
  RULE_VERSION: 'Nova versão de regra',
  REGRA_MEDIDA_DISTANCIA: 'Medida da distância alterada',
  PRIORITY_DECISION: 'Oferta fora da ordem (laudo)',
  CONTROLE_CONSULTA: 'Consulta do controle externo',
  QUEUE_RECALCULATED: 'Fila recalculada',
};

const pct = (n: number, d: number) => (d > 0 ? Math.round((n / d) * 100) : 0);

export default function PainelControle() {
  const res = useRpc<any>('controle_painel', {}, { staleTime: 60_000 });
  const { me } = useSession();
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const f = d.fila;
  const o = d.ofertas;
  const ordemOk = d.ordem.filas > 0 && d.ordem.conferidas === d.ordem.filas;
  const externo = me?.role === 'CONTROLE_EXTERNO';
  return (
    <div>
      <PageHeader
        eyebrow={externo ? 'Controle externo · Ministério Público e Defensoria Pública' : 'O que o controle externo vê · Ministério Público e Defensoria'}
        title="A fila está sendo cumprida, com critérios claros?"
        subtitle={`Somente leitura e sem dados pessoais. Calculado agora (${fmtDateTime(d.gerado_em)}), a partir dos mesmos registros que a Secretaria usa · regras ${d.regras.versao}.`}
        actions={<ButtonLink to="/controle/caso" icon={FileSearch} variant="purple">Consultar um caso</ButtonLink>}
      />

      <Card className="mb-4 flex items-start gap-3 bg-slate-50 p-4 ring-1 ring-line">
        <ShieldCheck className="mt-0.5 size-5 shrink-0 text-green-700" />
        <p className="text-[13.5px] text-ink-2">
          Aqui aparecem a fila inteira por <b>código público</b> (sem nomes), a conferência da ordem, as exceções com a justificativa,
          os prazos e cada mudança de regra. Um caso individual só abre com o <b>protocolo informado pela família</b> e o motivo
          (atendimento da Defensoria, procedimento do MP) — a consulta fica registrada na auditoria e nesta trilha.
        </p>
      </Card>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
        <Kpi compact icon={ListChecks} tone={ordemOk ? 'green' : 'red'} label="Ordem conferida" value={`${fmtInt(d.ordem.conferidas)}/${fmtInt(d.ordem.filas)}`}
          sub="filas em que a posição segue pontos e data" to="/controle/fila" source="calculado" />
        <Kpi compact icon={ListOrdered} tone="purple" label="Crianças aguardando" value={fmtInt(f.aguardando)} sub={`${fmtInt(f.mais_90)} há mais de 90 dias`} to="/controle/fila" source="demo" />
        <Kpi compact icon={Timer} tone="amber" label="Espera média" value={`${fmtInt(f.espera_media_dias)} dias`} sub={`mediana ${fmtInt(f.espera_mediana_dias)} · máxima ${fmtInt(f.espera_max_dias)}`} source="demo" />
        <Kpi compact icon={Sparkles} tone={d.vagas_com_fila.vagas > 0 ? 'red' : 'green'} label="Vagas paradas com fila" value={fmtInt(d.vagas_com_fila.vagas)}
          sub={`em ${fmtInt(d.vagas_com_fila.filas)} filas com crianças`} onClick={() => document.getElementById('vagas-paradas')?.scrollIntoView({ behavior: 'smooth', block: 'start' })} source="demo" />
        <Kpi compact icon={Scale} tone="blue" label="Ofertas na ordem" value={`${pct(o.na_ordem, o.na_ordem + o.laudo + o.sem_registro)}%`}
          sub={`na unidade pedida · ${fmtInt(o.laudo)} por laudo · 12 meses`} onClick={() => document.getElementById('ofertas')?.scrollIntoView({ behavior: 'smooth', block: 'start' })} source="demo" />
        <Kpi compact icon={ClipboardList} tone={d.protocolos.vencidos > 0 ? 'amber' : 'teal'} label="Protocolos vencidos" value={fmtInt(d.protocolos.vencidos)}
          sub={`${fmtInt(d.protocolos.abertos)} abertos (vaga e matrícula)`} source="demo" />
      </div>

      {!ordemOk && d.ordem.divergentes.length > 0 && (
        <Card className="mt-3 flex items-start gap-3 bg-red-50 p-4 ring-1 ring-red-200">
          <AlertTriangle className="mt-0.5 size-5 shrink-0 text-red-700" />
          <p className="text-[13.5px] text-red-950"><b>Posição fora da regra</b> em: {(d.ordem.divergentes as any[]).map((x) => `${x.unidade} (${x.faixa})`).join(', ')}.</p>
        </Card>
      )}

      <div className="grid grid-cols-1 gap-x-4 lg:grid-cols-2">
        <Section id="ofertas" title={<span className="inline-flex items-center gap-2"><Scale className="size-5 text-purple-700" />Ofertas × ordem da fila</span>}
          subtitle={`Ofertas de vaga desde ${fmtDate(o.desde)}. A vaga vai ao 1º da fila; fora da ordem, só por laudo validado e com justificativa.`}>
          <Card className="p-4">
            <Donut
              size={150}
              segments={[
                { key: 'na_ordem', label: 'Ao 1º da fila (na ordem)', value: o.na_ordem, color: '#16A36A' },
                { key: 'alternativa', label: 'Em outra unidade (oferta alternativa)', value: o.alternativa, color: '#2A7DE1' },
                { key: 'laudo', label: 'Fora da ordem por laudo (com justificativa)', value: o.laudo, color: '#7A24C5' },
                { key: 'sem_registro', label: 'Sem registro da posição', value: o.sem_registro, color: '#94A3B8' },
              ]}
              center={<div><b className="font-display text-2xl tabular">{fmtInt(o.total)}</b><div className="text-[11px] text-muted">ofertas</div></div>}
            />
            <div className="mt-4 grid grid-cols-2 gap-2 text-[13px] sm:grid-cols-3">
              {[
                ['Aceitas', o.aceitas, 'text-green-700'], ['Matrículas concluídas', o.matriculadas, 'text-green-700'], ['Recusadas', o.recusadas, 'text-ink'],
                ['Expiradas sem resposta', o.expiradas, 'text-amber-700'], ['Em aberto', o.abertas, 'text-ink'], ['Vencem em 24 h', o.vencem_24h, o.vencem_24h ? 'text-red-700' : 'text-ink'],
              ].map(([l, v, cls]) => (
                <div key={l as string} className="rounded-2xl bg-slate-50 px-3 py-2 ring-1 ring-line/70">
                  <div className={clsx('font-display text-lg font-black tabular', cls as string)}>{fmtInt(v as number)}</div>
                  <div className="text-[12px] text-muted">{l}</div>
                </div>
              ))}
            </div>
            <p className="mt-3 text-[12.5px] text-muted">
              Silêncio não é aceite: a oferta expira em 72 h (IN nº 025/2025, Anexo II) e a vaga volta para a fila.
              {o.resposta_media_h != null && <> Resposta média das famílias: <b className="text-ink-2">{fmtInt(o.resposta_media_h)} h</b>.</>}
            </p>
          </Card>
        </Section>

        <Section title={<span className="inline-flex items-center gap-2"><History className="size-5 text-purple-700" />Exceções à ordem</span>}
          subtitle="Ofertas fora da ordem de pontuação por prioridade sob análise (laudo PCD/TEA/TGD/AH-SD), como prevê a IN nº 025/2025. CIDs, CPFs e nomes são ocultados.">
          <Card className="divide-y divide-line overflow-hidden">
            {(d.excecoes as any[]).length === 0 && <p className="p-4 text-[13.5px] text-muted">Nenhuma oferta fora da ordem registrada.</p>}
            {(d.excecoes as any[]).map((x, i) => (
              <div key={i} className="p-4">
                <div className="flex flex-wrap items-center gap-2 text-[12.5px] text-muted">
                  <Badge tone="purple">laudo · fora da ordem</Badge>
                  <span>{fmtDateTime(x.quando)}</span>
                  {x.unidade && <span>· {x.unidade}</span>}
                  {x.codigo && <span className="font-mono">· {x.codigo}</span>}
                  {x.quem && <span>· {x.quem}</span>}
                </div>
                <p className="mt-1.5 text-[13.5px] text-ink-2">{x.resumo}</p>
              </div>
            ))}
          </Card>
        </Section>
      </div>

      <Section id="vagas-paradas" title={<span className="inline-flex items-center gap-2"><Sparkles className="size-5 text-purple-700" />Vagas ofertáveis em filas com crianças aguardando</span>}
        subtitle="Turmas com vaga livre na mesma unidade e faixa em que há fila. Pela regra, devem ser ofertadas ao 1º da fila.">
        <Card className="overflow-hidden">
          <Tabela rotulo="Vagas paradas com fila" largura={640} colunas="minmax(200px,1.6fr) 120px 90px 100px 130px">
            <TCabecalho><span>Unidade</span><span>Faixa</span><span className="text-right">Vagas</span><span className="text-right">Aguardando</span><span className="text-right">Espera do 1º</span></TCabecalho>
            {(d.vagas_com_fila.itens as any[]).map((x) => (
              <TLinha key={`${x.unit_id}-${x.faixa}`} to={`/unidades/${x.unit_id}`} rotulo={`${x.unidade}, ${x.faixa}`}>
                <TCelula fixa className="font-semibold" titulo={x.unidade}>{x.unidade}</TCelula>
                <TCelula className="text-muted">{x.faixa}</TCelula>
                <TCelula className="text-right font-semibold tabular text-green-700">{fmtInt(x.vagas)}</TCelula>
                <TCelula className="text-right tabular">{fmtInt(x.aguardando)}</TCelula>
                <TCelula className={clsx('text-right tabular', x.espera_dias > 90 ? 'font-semibold text-red-700' : 'text-muted')}>{fmtInt(x.espera_dias)} dias</TCelula>
              </TLinha>
            ))}
            {!(d.vagas_com_fila.itens as any[]).length && <p className="px-3 py-3 text-[13px] text-muted">Nenhuma vaga ofertável parada em fila com crianças.</p>}
          </Tabela>
          <p className="border-t border-line bg-slate-50 px-4 py-2 text-[12px] text-muted">
            {fmtInt(d.vagas_com_fila.filas)} filas · {fmtInt(d.vagas_com_fila.vagas)} vagas que atenderiam crianças já na fila · mostrando as 12 maiores.
          </p>
        </Card>
      </Section>

      <div className="grid grid-cols-1 gap-x-4 lg:grid-cols-2">
        <Section title={<span className="inline-flex items-center gap-2"><Timer className="size-5 text-purple-700" />Espera por faixa</span>} subtitle="Crianças aguardando, espera média e vagas ofertáveis na rede">
          <Card className="p-3">
            <BarList items={(f.por_faixa as any[]).map((x) => ({
              key: x.faixa, label: x.faixa, value: x.aguardando,
              sub: `espera média ${fmtInt(x.espera_media_dias)} dias · ${fmtInt(x.mais_90)} há mais de 90 dias · ${fmtInt(x.vagas)} vagas ofertáveis`,
              to: '/controle/fila',
            }))} valueSuffix=" crianças" />
          </Card>
        </Section>

        <Section title={<span className="inline-flex items-center gap-2"><MapPinned className="size-5 text-purple-700" />Saldo por região</span>} subtitle="Vagas ofertáveis − crianças aguardando (negativo = falta vaga)">
          <Card className="p-3">
            <BarList items={(d.regioes as any[]).map((x) => ({
              key: x.regiao, label: x.regiao, value: x.saldo,
              color: x.saldo < 0 ? 'linear-gradient(90deg,#F28C38,#D94C4C)' : 'linear-gradient(90deg,#7DD3B0,#16A36A)',
              sub: `${fmtInt(x.aguardando)} aguardando · ${fmtInt(x.vagas)} vagas · creche: ${fmtInt(x.aguardando_creche)} × ${fmtInt(x.vagas_creche)}`,
            }))} format={(n) => (n > 0 ? `+${fmtInt(n)}` : fmtInt(n))} />
          </Card>
        </Section>
      </div>

      <Section title={<span className="inline-flex items-center gap-2"><Route className="size-5 text-purple-700" />Distância casa–unidade</span>}
        subtitle={`Critério "até ${fmtKm(d.distancias.limite_m)}" medido ${MEDIDA[d.distancias.medida as keyof typeof MEDIDA].curto}. As três medidas ficam em cada inscrição.`}
        action={<LinkMetodologia className="text-sm">Metodologia e simulação</LinkMetodologia>}>
        <div className="grid grid-cols-3 gap-2 sm:gap-3">
          {MEDIDAS.map((m) => {
            const I = MEDIDA[m].icone;
            const desvio = m === 'LINHA_RETA' ? null : d.distancias.desvio_pct?.[m];
            return (
              <Card key={m} className={clsx('p-3 sm:p-4', d.distancias.medida === m && 'ring-2 ring-purple-300')}>
                <div className="flex items-center gap-1.5 text-[12.5px] font-bold text-ink-2"><I className="size-4" style={{ color: MEDIDA[m].cor }} />{MEDIDA[m].rotulo}</div>
                <div className="mt-1 font-display text-2xl font-black tabular">{fmtInt(d.distancias.atendem[m])}</div>
                <div className="text-[12px] text-muted">crianças a até {fmtKm(d.distancias.limite_m)}{desvio != null ? ` · caminho ${desvio}% maior que a reta` : ''}</div>
              </Card>
            );
          })}
        </div>
      </Section>

      <Section title={<span className="inline-flex items-center gap-2"><ScrollText className="size-5 text-purple-700" />Trilha de governança</span>}
        subtitle="Mudanças de regra, exceções, recálculos e consultas do controle externo — registros imutáveis."
        action={<Link to="/regras" className="text-sm font-semibold text-purple-700">Regras vigentes</Link>}>
        <Card className="divide-y divide-line overflow-hidden">
          {(d.governanca as any[]).length === 0 && <p className="p-4 text-[13.5px] text-muted">Sem eventos de governança.</p>}
          {(d.governanca as any[]).map((g, i) => (
            <div key={i} className="flex items-start gap-3 px-4 py-3">
              {g.acao === 'CONTROLE_CONSULTA' ? <FileSearch className="mt-0.5 size-4 shrink-0 text-blue-700" />
                : g.acao === 'PRIORITY_DECISION' ? <History className="mt-0.5 size-4 shrink-0 text-purple-700" />
                : <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-green-700" />}
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-x-2 text-[13.5px]">
                  <b>{ACAO_GOVERNANCA[g.acao] ?? g.acao}</b>
                  <span className="text-[12px] text-muted">{fmtDateTime(g.quando)}{g.quem ? ` · ${g.quem}` : ''}</span>
                </div>
                {g.resumo && <p className="text-[12.5px] text-muted">{g.resumo}</p>}
              </div>
            </div>
          ))}
        </Card>
      </Section>

      <p className="mt-6 flex flex-wrap items-center gap-2 text-[12px] text-muted">
        <SourceChip kind="demo" detail="Fila, ofertas e protocolos são da camada de demonstração; unidades e turmas seguem o Censo 2025." />
        Dados de demonstração. Em produção, os mesmos números vêm dos registros oficiais da SEDUC, sem intermediários.
      </p>
    </div>
  );
}
