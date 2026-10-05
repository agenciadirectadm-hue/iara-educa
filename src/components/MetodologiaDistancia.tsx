// "Como medimos a distância" — transparência do critério de proximidade da fila (página de Regras).
// Público: as três medidas, o que cada uma significa e quantas crianças atendem o critério por cada uma.
// Secretaria: simulação do impacto de trocar a medida (sem alterar nada) e situação do motor de rotas.
// Secretário(a): troca da medida, com justificativa registrada na auditoria e recálculo de todas as filas.
import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { ArrowRight, Check, CircleCheck, Globe2, Loader2, Route, Scale, ServerCog, X } from 'lucide-react';
import { rotasFila, rotasStatus, rpc, type MedidaDistancia } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtDateTime, fmtInt, fmtKm } from '@/lib/format';
import { Badge, Button, Card, Section, SourceChip } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { MEDIDA, MEDIDAS } from '@/components/distancias';

type Resumo = {
  medida: MedidaDistancia; limite_m: number; regra: string; versao: string; peso: number;
  medida_desde: string | null; medida_justificativa: string | null;
  aguardando: number; com_rota: number;
  atendem: Record<MedidaDistancia, number>;
  mediana_m: Record<MedidaDistancia, number | null>;
  desvio_pct: { A_PE: number | null; CARRO: number | null };
  rotas_calculadas_em: string | null;
};

type Simulacao = {
  medida: MedidaDistancia; medida_atual: MedidaDistancia; limite_m: number; peso: number; total: number; ganham: number; perdem: number;
  sem_rota: number; mudam_posicao: number; atende_hoje: number; atenderia: number;
  exemplos: { entry_id: string; crianca: string; unidade: string; faixa: string; reta_m: number | null; a_pe_m: number | null; carro_m: number | null;
    aplica_hoje: boolean; aplica_nova: boolean; posicao: number | null; posicao_nova: number }[];
};

export function ComoMedimosDistancia() {
  const { me, can } = useSession();
  const res = useRpc<Resumo>('distancias_resumo', {}, { staleTime: 60_000 });
  const rede = !!me && (me.scope === 'NETWORK' || me.scope === 'AGGREGATE') && can('queue.read');
  const [sim, setSim] = useState<MedidaDistancia | null>(null);
  const r = res.data;
  return (
    <Section
      id="distancia"
      title={<span className="inline-flex items-center gap-2"><Route className="size-5 text-purple-700" />Como medimos a distância</span>}
      subtitle="Para o critério de proximidade da fila, a distância entre a casa e a unidade é medida de três formas. O sistema calcula e mostra as três para cada criança; a regra diz qual delas vale."
    >
      <Card className="p-4">
        {res.isLoading ? <div className="grid gap-3 md:grid-cols-3">{[0, 1, 2].map((i) => <div key={i} className="skeleton h-44 rounded-2xl" />)}</div>
          : res.error ? <p className="text-[13px] text-red-700">{res.error.message}</p>
          : r && (
            <>
              <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
                {MEDIDAS.map((m) => {
                  const I = MEDIDA[m].icone;
                  const atual = r.medida === m;
                  const desvio = m === 'LINHA_RETA' ? null : r.desvio_pct[m];
                  return (
                    <div key={m} className={clsx('flex flex-col rounded-2xl p-3.5', atual ? 'bg-purple-50 ring-2 ring-purple-300' : 'bg-slate-50 ring-1 ring-line/70')}>
                      <div className="flex items-center justify-between gap-2">
                        <span className="inline-flex items-center gap-2 font-display text-[16px] font-extrabold"><I className="size-5" style={{ color: MEDIDA[m].cor }} />{MEDIDA[m].rotulo}</span>
                        {atual && <Badge tone="purple" solid icon={Scale}>em uso na fila</Badge>}
                      </div>
                      <p className="mt-1.5 text-[13px] text-ink-2">{MEDIDA[m].explica}</p>
                      <div className="mt-auto pt-3">
                        <div className="font-display text-[26px] font-black leading-none tabular">{fmtInt(r.atendem[m])}</div>
                        <div className="text-[12.5px] text-muted">de {fmtInt(r.aguardando)} crianças aguardando moram a até {fmtKm(r.limite_m)}</div>
                        <div className="mt-1 text-[12px] text-muted">
                          mediana {fmtKm(r.mediana_m[m])}{desvio != null && <> · caminho em média <b className="text-ink-2">{desvio}% maior</b> que a linha reta</>}
                        </div>
                        {rede && !atual && (
                          <Button size="sm" variant={sim === m ? 'purple' : 'secondary'} className="mt-2.5" onClick={() => setSim(sim === m ? null : m)}>
                            {sim === m ? 'Fechar simulação' : `Simular a fila medindo ${MEDIDA[m].curto}`}
                          </Button>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
              <div className="mt-3 grid gap-2 text-[13px] text-ink-2 md:grid-cols-2">
                <p className="rounded-2xl bg-slate-50 p-3">
                  <b>Critério em vigor:</b> “{r.regra}” (regras {r.versao}, +{fmtInt(r.peso)} pontos), medido <b>{MEDIDA[r.medida].curto}</b>
                  {r.medida_desde ? ` desde ${fmtDate(r.medida_desde)}` : ' — como na redação da IN nº 025/2025'}.
                  {r.medida_justificativa && <> Justificativa registrada: “{r.medida_justificativa}”.</>}
                  {' '}As outras duas medidas ficam guardadas em cada inscrição, para conferência pela família e pelo controle externo.
                </p>
                <p className="rounded-2xl bg-slate-50 p-3">
                  <Globe2 className="mr-1 inline size-4 text-purple-700" />
                  As rotas são calculadas pelas ruas do <b>OpenStreetMap</b> (mapa aberto, colaborativo e atualizado) com o motor <b>OSRM</b>: vale para qualquer município.
                  Só a coordenada da casa e a da unidade vão ao motor de rotas — nunca nome, CPF ou endereço escrito.
                  {r.rotas_calculadas_em && ` Rotas da fila: ${fmtInt(r.com_rota)} de ${fmtInt(r.aguardando)} calculadas (última em ${fmtDateTime(r.rotas_calculadas_em)}).`}
                </p>
              </div>
            </>
          )}
      </Card>
      {rede && sim && r && <SimulacaoMedida medida={sim} resumo={r} onFechar={() => setSim(null)} />}
      {rede && <MotorRotas resumo={r ?? null} />}
    </Section>
  );
}

function SimulacaoMedida({ medida, resumo, onFechar }: { medida: MedidaDistancia; resumo: Resumo; onFechar: () => void }) {
  const { can } = useSession();
  const res = useRpc<Simulacao>('fila_simular_medida', { medida }, { staleTime: 60_000 });
  const [aplicar, setAplicar] = useState(false);
  const s = res.data;
  return (
    <Card className="mt-3 overflow-hidden">
      <div className="flex flex-wrap items-start gap-3 border-b border-line p-4">
        <div className="min-w-0 flex-1">
          <div className="font-display text-[16px] font-extrabold">Simulação: e se o critério medisse {MEDIDA[medida].curto}?</div>
          <div className="text-[12.5px] text-muted">Nada é alterado. Mesmas crianças, mesmos pontos — só o critério de proximidade recalculado com a outra medida. <SourceChip kind="calculado" /></div>
        </div>
        <Button size="sm" variant="ghost" icon={X} onClick={onFechar}>Fechar</Button>
      </div>
      {res.isLoading ? <div className="flex items-center gap-2 p-4 text-[13px] text-muted"><Loader2 className="size-4 animate-spin" />Simulando a fila inteira…</div>
        : res.error ? <p className="p-4 text-[13px] text-red-700">{res.error.message}</p>
        : s && (
          <>
            <div className="grid grid-cols-2 gap-px bg-line sm:grid-cols-4">
              {[
                { n: s.perdem, t: `perdem os ${fmtInt(s.peso)} pontos`, cls: 'text-red-700' },
                { n: s.ganham, t: `ganham os ${fmtInt(s.peso)} pontos`, cls: 'text-green-700' },
                { n: s.mudam_posicao, t: 'mudam de posição na fila', cls: 'text-ink' },
                { n: s.atenderia, t: `atendem o critério (hoje ${fmtInt(s.atende_hoje)})`, cls: 'text-purple-800' },
              ].map((k) => (
                <div key={k.t} className="bg-white p-3">
                  <div className={clsx('font-display text-[26px] font-black leading-none tabular', k.cls)}>{fmtInt(k.n)}</div>
                  <div className="mt-1 text-[12px] text-muted">{k.t}</div>
                </div>
              ))}
            </div>
            {s.sem_rota > 0 && <p className="border-t border-line px-4 py-2 text-[12.5px] text-amber-800">{fmtInt(s.sem_rota)} inscrição(ões) ainda sem rota calculada: na simulação, mantêm a situação de hoje.</p>}
            {s.exemplos.length > 0 && (
              <Tabela rotulo="Crianças afetadas" largura={980} colunas="minmax(130px,1fr) minmax(170px,1.3fr) 100px 80px 80px 80px 110px 110px">
                <TCabecalho>
                  <span>Criança</span><span>Unidade</span><span>Faixa</span>
                  {MEDIDAS.map((m) => <span key={m} className={clsx('text-right', m === medida && 'text-purple-800')}>{MEDIDA[m].rotulo}</span>)}
                  <span>Critério</span><span className="text-right">Posição</span>
                </TCabecalho>
                {s.exemplos.map((x) => (
                  <TLinha key={x.entry_id} to={`/fila/${x.entry_id}`} rotulo={`${x.crianca}, ${x.unidade}`}>
                    <TCelula fixa className="font-semibold">{x.crianca}</TCelula>
                    <TCelula titulo={x.unidade}>{x.unidade}</TCelula>
                    <TCelula className="text-muted">{x.faixa}</TCelula>
                    {(['reta_m', 'a_pe_m', 'carro_m'] as const).map((k, i) => (
                      <TCelula key={k} className={clsx('text-right tabular', MEDIDAS[i] === medida ? 'font-semibold' : 'text-muted')}>{fmtKm(x[k])}</TCelula>
                    ))}
                    <TCelula className="text-[12.5px]">
                      {x.aplica_hoje ? <Check className="inline size-3.5 text-green-700" /> : <X className="inline size-3.5 text-subtle" />}
                      <ArrowRight className="mx-1 inline size-3 text-subtle" />
                      {x.aplica_nova ? <Check className="inline size-3.5 text-green-700" /> : <X className="inline size-3.5 text-red-600" />}
                      <span className={clsx('ml-1', x.aplica_nova ? 'text-green-700' : 'text-red-700')}>{x.aplica_nova ? `+${fmtInt(s.peso)}` : `−${fmtInt(s.peso)}`}</span>
                    </TCelula>
                    <TCelula className="text-right tabular">{x.posicao ? `${x.posicao}º` : '—'}<ArrowRight className="mx-1 inline size-3 text-subtle" /><b>{x.posicao_nova}º</b></TCelula>
                  </TLinha>
                ))}
              </Tabela>
            )}
            <div className="flex flex-wrap items-center gap-3 border-t border-line bg-slate-50 px-4 py-3 text-[12.5px] text-muted">
              <span className="min-w-0 flex-1">Mostrando até 30 crianças com maior mudança de posição. Nomes abreviados.</span>
              {can('rules.manage') ? (
                <Button size="sm" variant="purple" icon={Scale} onClick={() => setAplicar(true)}>Passar a medir {MEDIDA[medida].curto}</Button>
              ) : <span>A troca da medida é decisão do(a) Secretário(a) de Educação, com justificativa registrada.</span>}
            </div>
          </>
        )}
      <AplicarMedida aberto={aplicar} medida={medida} resumo={resumo} simulacao={s ?? null} onFechar={() => setAplicar(false)} onFeito={onFechar} />
    </Card>
  );
}

function AplicarMedida({ aberto, medida, resumo, simulacao, onFechar, onFeito }: {
  aberto: boolean; medida: MedidaDistancia; resumo: Resumo; simulacao: Simulacao | null; onFechar: () => void; onFeito: () => void;
}) {
  const qc = useQueryClient();
  const toast = useToast();
  const [just, setJust] = useState('');
  const [busy, setBusy] = useState(false);
  const ok = just.trim().length >= 10;
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<{ recalculadas: number }>('fila_medida_definir', { medida, justificativa: just.trim() });
      toast({ title: `Critério passa a medir ${MEDIDA[medida].curto}`, description: `${fmtInt(r.recalculadas)} inscrições recalculadas · registrado na auditoria.`, tone: 'success' });
      for (const k of ['distancias_resumo', 'fila_simular_medida', 'rules_list', 'queue_list', 'queue_entry_detail', 'student_detail', 'distancias']) qc.invalidateQueries({ queryKey: [k] });
      setJust('');
      onFechar();
      onFeito();
    } catch (e) {
      toast({ title: 'Não foi possível trocar a medida', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet
      open={aberto}
      onClose={onFechar}
      title={`Medir a distância ${MEDIDA[medida].curto}`}
      subtitle={`Hoje: ${MEDIDA[resumo.medida].curto}. Vale para todas as filas da rede.`}
      footer={
        <div className="flex gap-2">
          <Button variant="secondary" className="flex-1" onClick={onFechar}>Cancelar</Button>
          <Button variant="purple" className="flex-1" icon={CircleCheck} disabled={!ok} loading={busy} onClick={enviar}>Confirmar e recalcular</Button>
        </div>
      }
    >
      <div className="space-y-3 text-[14px] text-ink-2">
        {simulacao && (
          <p className="rounded-2xl bg-amber-50 p-3 text-amber-950 ring-1 ring-amber-100">
            {fmtInt(simulacao.perdem)} criança(s) deixam de receber os {fmtInt(simulacao.peso)} pontos de proximidade
            {simulacao.ganham ? ` e ${fmtInt(simulacao.ganham)} passam a receber` : ''}; {fmtInt(simulacao.mudam_posicao)} mudam de posição. As famílias veem a nova medida no extrato da pontuação.
          </p>
        )}
        <label className="block">
          <span className="text-[13px] font-semibold">Justificativa (fica na auditoria e na página pública de regras)</span>
          <textarea
            value={just}
            onChange={(e) => setJust(e.target.value)}
            rows={4}
            placeholder="Ex.: Recomendação do Ministério Público nº …/2026; Ofício da Defensoria Pública nº …; decisão da Secretaria em …"
            className="mt-1 w-full rounded-2xl bg-white p-3 text-[14.5px] text-ink ring-1 ring-line outline-none placeholder:text-subtle focus:ring-2 focus:ring-purple-500"
          />
        </label>
        <p className="text-[12.5px] text-muted">A regra continua versionada: decisões antigas mostram a medida com que foram tomadas.</p>
      </div>
    </Sheet>
  );
}

/** Situação do motor de rotas e cálculo das rotas da fila que faltam (Secretaria). */
function MotorRotas({ resumo }: { resumo: Resumo | null }) {
  const { can } = useSession();
  const qc = useQueryClient();
  const toast = useToast();
  const st = useQuery({ queryKey: ['rotas_status'], queryFn: rotasStatus, staleTime: 10 * 60_000, retry: 0 });
  const [prog, setProg] = useState<string | null>(null);
  const pendentes = resumo ? resumo.aguardando - resumo.com_rota : 0;
  const calcular = async () => {
    setProg('Calculando…');
    try {
      for (let i = 0; i < 20; i++) {
        const r = await rotasFila(100);
        if (r.erro) throw new Error(r.erro);
        setProg(`${fmtInt(r.pares_total - r.pendentes)} de ${fmtInt(r.pares_total)} rotas`);
        if (r.pendentes === 0) break;
      }
      toast({ title: 'Rotas da fila calculadas', tone: 'success' });
      for (const k of ['distancias_resumo', 'fila_simular_medida', 'queue_list']) qc.invalidateQueries({ queryKey: [k] });
    } catch (e) {
      toast({ title: 'Motor de rotas indisponível', description: (e as Error).message, tone: 'error' });
    } finally {
      setProg(null);
    }
  };
  const Estado = ({ x, rotulo }: { x?: { ok: boolean; ms: number }; rotulo: string }) => (
    <span className="inline-flex items-center gap-1">
      {x ? x.ok ? <Check className="size-3.5 text-green-700" /> : <X className="size-3.5 text-red-600" /> : <Loader2 className="size-3.5 animate-spin" />}
      {rotulo}{x?.ok && <span className="text-subtle">({(x.ms / 1000).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} s)</span>}
    </span>
  );
  return (
    <Card className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-2 p-3 text-[12.5px] text-muted">
      <span className="inline-flex items-center gap-1.5 font-semibold text-ink-2"><ServerCog className="size-4 text-purple-700" />Motor de rotas: {st.data?.provedor ?? 'OSRM · OpenStreetMap'}</span>
      <Estado x={st.data?.a_pe} rotulo="a pé" />
      <Estado x={st.data?.carro} rotulo="de carro" />
      {st.error && <span className="text-red-700">indisponível agora</span>}
      <span>{pendentes > 0 ? `${fmtInt(pendentes)} inscrição(ões) sem rota` : 'todas as inscrições com rota'}</span>
      {(can('queue.manage') || can('rules.manage')) && pendentes > 0 && (
        <Button size="sm" variant="secondary" icon={Route} loading={!!prog} onClick={calcular}>{prog ?? 'Calcular rotas pendentes'}</Button>
      )}
      <span className="basis-full text-[12px]">
        Outro município: as mesmas regras e telas valem com o mapa do OpenStreetMap da cidade. Em produção, recomenda-se um servidor de rotas próprio (OSRM) — as coordenadas não saem da rede pública.
      </span>
    </Card>
  );
}
