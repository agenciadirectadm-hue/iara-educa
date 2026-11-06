import { useMemo, useRef, useState } from 'react';
import { CircleHelp, Hourglass, ThumbsDown, ThumbsUp } from 'lucide-react';
import { useRpc } from '@/lib/hooks';
import { useGeoLayers, useUnitsMap } from '@/lib/data';
import { fmtDateTime, fmtInt } from '@/lib/format';
import { CHANNEL, SHIFT } from '@/lib/labels';
import { Button, Card, ErrorState, Kpi, PageHeader, Section, Segmented, SkeletonList, SourceChip, inputCls } from '@/components/ui';
import { BarList } from '@/components/charts';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import MapView, { type Calor } from '@/components/map/MapView';

type Camada = 'oferta_aceite' | 'oferta_recusa' | 'oferta_motivo';
type Motivo = { codigo: string; rotulo: string; cor: string; n: number; pct: number };
type Unidade = {
  id: number; nome: string; decididas: number; aceitas: number; recusadas: number; sem_resposta: number; abertas: number;
  pct_aceite: number; pct_recusa: number; pct_sem_resposta: number; motivo_codigo: string | null; motivo: string | null;
};
type Registro = {
  id?: string; quando: string; unit_id: number; unidade: string; motivo_codigo: string; motivo: string; codigo?: string;
  turma?: string; turno?: string; texto?: string | null; canal?: string | null; crianca?: string; student_id?: string;
};
type Painel = {
  desde: string; atualizado_em: string; nivel: 'NOMES' | 'CODIGOS' | 'NENHUM';
  totais: { decididas: number; aceitas: number; matriculadas: number; recusadas: number; sem_resposta: number; abertas: number; pct_aceite: number; pct_recusa: number; pct_sem_resposta: number };
  motivos: Motivo[]; unidades: Unidade[]; registros: Registro[];
};

const CAMADAS: Record<Camada, { rotulo: string; legenda: string; explica: string }> = {
  oferta_aceite: { rotulo: 'Aceitação', legenda: 'Unidades · aceitação', explica: 'Cada ponto é uma unidade: de cada 100 ofertas concluídas, quantas as famílias aceitaram.' },
  oferta_recusa: { rotulo: 'Recusa', legenda: 'Unidades · recusa', explica: 'Cada ponto é uma unidade: de cada 100 ofertas concluídas, quantas as famílias recusaram.' },
  oferta_motivo: { rotulo: 'Motivo principal', legenda: 'Motivo mais citado na unidade', explica: 'Cada ponto é uma unidade com recusa, na cor do motivo mais citado ali.' },
};

/** Aceitação e recusa de vagas: percentuais, motivos, mapa e cada recusa, conforme o perfil (o servidor decide o que vem). */
export default function RecusasVaga() {
  const res = useRpc<Painel>('recusas_painel');
  const [camada, setCamada] = useState<Camada>('oferta_aceite');
  const mapa = useRpc<any>('recusas_mapa', { camada }, { staleTime: 60_000 });
  const geo = useGeoLayers();
  const units = useUnitsMap();
  const [todas, setTodas] = useState(false);
  const [filtroUnidade, setFiltroUnidade] = useState('');
  const [filtroMotivo, setFiltroMotivo] = useState('');
  const refRegistros = useRef<HTMLDivElement>(null);

  const calor = useMemo<Calor | null>(() => (mapa.data
    ? { modo: 'taxa', pontos: mapa.data.pontos, max: null, pior: camada === 'oferta_aceite' ? 'menor' : 'maior', rotulo: CAMADAS[camada].rotulo }
    : null), [mapa.data, camada]);
  const faixas = useMemo(() => (mapa.data ? [{ titulo: CAMADAS[camada].legenda, itens: mapa.data.legenda }] : []), [mapa.data, camada]);
  const enquadrar = useMemo(() => {
    const l = units.data?.units ?? [];
    if (!l.length) return null;
    return { chave: 'cidade', caixa: [[Math.min(...l.map((u) => u.lng)), Math.min(...l.map((u) => u.lat))], [Math.max(...l.map((u) => u.lng)), Math.max(...l.map((u) => u.lat))]] as [[number, number], [number, number]] };
  }, [units.data]);

  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data!;
  const t = d.totais;
  const comRegistros = d.nivel !== 'NENHUM';
  const registros = d.registros.filter((r) => (!filtroUnidade || String(r.unit_id) === filtroUnidade) && (!filtroMotivo || r.motivo_codigo === filtroMotivo));
  const unidadesLista = todas ? d.unidades : d.unidades.slice(0, 12);
  const unidadesComRegistro = [...new Map(d.registros.map((r) => [r.unit_id, r.unidade])).entries()].sort((a, b) => a[1].localeCompare(b[1], 'pt-BR'));

  return (
    <div>
      <PageHeader
        eyebrow="Ofertas de vaga"
        title="Aceitação e recusa de vagas"
        subtitle="Quando a família recusa, fica registrado qual unidade foi oferecida e o motivo. Percentuais sobre as ofertas concluídas nos últimos 12 meses: aceitas, recusadas e sem resposta no prazo."
        actions={<SourceChip kind="demo" />}
      />

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi compact icon={ThumbsUp} tone="green" label="Aceitaram" value={`${t.pct_aceite}%`} sub={`${fmtInt(t.aceitas)} de ${fmtInt(t.decididas)} ofertas · ${fmtInt(t.matriculadas)} matrículas`} />
        <Kpi compact icon={ThumbsDown} tone="red" label="Recusaram" value={`${t.pct_recusa}%`} sub={`${fmtInt(t.recusadas)} de ${fmtInt(t.decididas)} ofertas`} />
        <Kpi compact icon={CircleHelp} tone="gray" label="Sem resposta no prazo" value={`${t.pct_sem_resposta}%`} sub={`${fmtInt(t.sem_resposta)} ofertas: silêncio não é recusa`} />
        <Kpi compact icon={Hourglass} tone="amber" label="Em aberto" value={fmtInt(t.abertas)} sub="fora dos percentuais" />
      </div>

      <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-[minmax(0,1fr)_360px]">
        <div className="relative overflow-hidden rounded-3xl bg-white ring-1 ring-line">
          <MapView
            className="h-[52vh] min-h-[360px] lg:h-[500px]"
            units={[]}
            showUnits={false}
            geo={geo.data}
            calor={calor}
            faixas={faixas}
            enquadrar={enquadrar}
            fitKey="recusas"
            chave={false}
            cooperative
            padding={{ top: 88, bottom: 30, left: 24, right: 48 }}
            legendNote="Toque num ponto para ver os percentuais, o número de ofertas e os motivos"
          />
          <div className="pointer-events-none absolute inset-x-0 top-0 flex flex-col items-start gap-1.5 p-3">
            <Segmented className="pointer-events-auto whitespace-nowrap shadow-soft" value={camada} onChange={(v) => setCamada(v as Camada)}
              items={(Object.keys(CAMADAS) as Camada[]).map((k) => ({ value: k, label: CAMADAS[k].rotulo }))} />
            <p className="max-w-[460px] rounded-xl bg-white/90 px-2.5 py-1 text-[12px] text-ink-2 shadow-soft ring-1 ring-line backdrop-blur">{CAMADAS[camada].explica}</p>
          </div>
        </div>

        <Card className="p-3">
          <h2 className="px-2 pt-1 font-display text-[17px] font-extrabold">Principais motivos de recusa</h2>
          <p className="mb-2 px-2 text-[12.5px] text-muted">{fmtInt(t.recusadas)} recusas no período. As cores são as do mapa.</p>
          <BarList items={d.motivos.map((m) => ({
            key: m.codigo, label: m.rotulo, value: m.n, color: m.cor, sub: `${m.pct}% das recusas`,
            ...(comRegistros ? { onClick: () => { setFiltroMotivo(m.codigo); refRegistros.current?.scrollIntoView({ behavior: 'smooth', block: 'start' }); } } : {}),
          }))} />
        </Card>
      </div>

      <Section title="Por unidade" subtitle="Da unidade com mais recusas para a com menos. Cada unidade recebeu poucas ofertas: confira a coluna Ofertas antes de comparar percentuais.">
        <Card className="overflow-hidden">
          <Tabela rotulo="Aceitação e recusa por unidade" largura={820} colunas="minmax(220px,1.6fr) 70px 86px 86px 100px minmax(200px,1.4fr)">
            <TCabecalho><span>Unidade</span><span className="text-right">Ofertas</span><span className="text-right">Aceitaram</span><span className="text-right">Recusaram</span><span className="text-right">Sem resposta</span><span>Motivo principal</span></TCabecalho>
            {unidadesLista.map((u) => (
              <TLinha key={u.id} to={`/unidades/${u.id}`} rotulo={`${u.nome}: ${u.pct_aceite}% aceitaram, ${u.pct_recusa}% recusaram`}>
                <TCelula fixa className="font-semibold" titulo={u.nome}>{u.nome}</TCelula>
                <TCelula className="text-right tabular">{fmtInt(u.decididas)}</TCelula>
                <TCelula className="text-right tabular">{u.pct_aceite}%</TCelula>
                <TCelula className="text-right font-semibold tabular">{u.pct_recusa}%</TCelula>
                <TCelula className="text-right tabular text-muted">{u.pct_sem_resposta}%</TCelula>
                <TCelula className="text-muted" titulo={u.motivo ?? undefined}>{u.motivo ?? '—'}</TCelula>
              </TLinha>
            ))}
          </Tabela>
        </Card>
        {d.unidades.length > 12 && (
          <div className="mt-2 text-center">
            <Button variant="secondary" size="sm" onClick={() => setTodas((v) => !v)}>{todas ? 'Ver menos' : `Ver as ${fmtInt(d.unidades.length)} unidades`}</Button>
          </div>
        )}
      </Section>

      {!comRegistros && (
        <p className="mt-4 rounded-2xl bg-slate-50 px-4 py-3 text-[13px] text-ink-2 ring-1 ring-line">Nesta visão aparecem os números por unidade e por motivo, sem identificar crianças ou famílias.</p>
      )}

      {comRegistros && (
        <div ref={refRegistros} className="scroll-mt-20">
          <Section
            title="Cada recusa"
            subtitle={d.nivel === 'NOMES'
              ? 'Qual unidade foi oferecida, quando e o motivo informado pela família. Dados pessoais: use só para atender a família.'
              : 'Cada recusa aparece pelo código da inscrição, o mesmo da fila pública, sem nome e sem o texto da família.'}
          >
            <div className="mb-2 flex flex-wrap items-center gap-2">
              <select aria-label="Filtrar por unidade" value={filtroUnidade} onChange={(e) => setFiltroUnidade(e.target.value)} className={`${inputCls} h-10 max-w-xs`}>
                <option value="">Todas as unidades</option>
                {unidadesComRegistro.map(([id, nome]) => <option key={id} value={id}>{nome}</option>)}
              </select>
              <select aria-label="Filtrar por motivo" value={filtroMotivo} onChange={(e) => setFiltroMotivo(e.target.value)} className={`${inputCls} h-10 max-w-xs`}>
                <option value="">Todos os motivos</option>
                {d.motivos.map((m) => <option key={m.codigo} value={m.codigo}>{m.rotulo}</option>)}
              </select>
              <span className="text-[13px] text-muted">{fmtInt(registros.length)} de {fmtInt(d.registros.length)}</span>
              {(filtroUnidade || filtroMotivo) && <Button variant="secondary" size="sm" onClick={() => { setFiltroUnidade(''); setFiltroMotivo(''); }}>Limpar</Button>}
            </div>
            <Card className="overflow-hidden">
              {d.nivel === 'NOMES' ? (
                <Tabela rotulo="Recusas de vaga" largura={1040} colunas="130px minmax(190px,1.2fr) minmax(200px,1.3fr) 150px minmax(240px,1.8fr) 90px">
                  <TCabecalho><span>Recusada em</span><span>Criança</span><span>Unidade oferecida</span><span>Turma</span><span>Motivo</span><span>Canal</span></TCabecalho>
                  {registros.map((r) => {
                    const motivo = r.texto ? `${r.motivo}: ${r.texto}` : r.motivo;
                    return (
                      <TLinha key={r.id} to={`/alunos/${r.student_id}`} rotulo={`${r.crianca}, ${r.unidade}, ${motivo}`}>
                        <TCelula className="tabular text-muted">{fmtDateTime(r.quando)}</TCelula>
                        <TCelula fixa className="font-semibold" titulo={r.crianca}>{r.crianca}</TCelula>
                        <TCelula titulo={r.unidade}>{r.unidade}</TCelula>
                        <TCelula className="text-muted" titulo={`${r.turma} · ${SHIFT[r.turno ?? ''] ?? r.turno}`}>{r.turma} · {SHIFT[r.turno ?? ''] ?? r.turno}</TCelula>
                        <TCelula titulo={motivo}>{motivo}</TCelula>
                        <TCelula className="text-muted">{r.canal ? CHANNEL[r.canal] ?? r.canal : '—'}</TCelula>
                      </TLinha>
                    );
                  })}
                  {!registros.length && <p className="px-3 py-3 text-[13px] text-muted">Nenhuma recusa com esse filtro.</p>}
                </Tabela>
              ) : (
                <Tabela rotulo="Recusas de vaga" largura={760} colunas="130px 110px minmax(220px,1.3fr) minmax(240px,1.5fr)">
                  <TCabecalho><span>Recusada em</span><span>Código</span><span>Unidade oferecida</span><span>Motivo</span></TCabecalho>
                  {registros.map((r, i) => (
                    <TLinha key={`${r.codigo}-${i}`}>
                      <TCelula className="tabular text-muted">{fmtDateTime(r.quando)}</TCelula>
                      <TCelula className="font-mono text-[12.5px]">{r.codigo}</TCelula>
                      <TCelula titulo={r.unidade}>{r.unidade}</TCelula>
                      <TCelula titulo={r.motivo}>{r.motivo}</TCelula>
                    </TLinha>
                  ))}
                  {!registros.length && <p className="px-3 py-3 text-[13px] text-muted">Nenhuma recusa com esse filtro.</p>}
                </Tabela>
              )}
            </Card>
          </Section>
        </div>
      )}
      <p className="mt-4 text-center text-[12px] text-muted">Atualizado em {fmtDateTime(d.atualizado_em)}. Pela regra vigente, quem recusa volta à fila sem perder a pontuação.</p>
    </div>
  );
}
