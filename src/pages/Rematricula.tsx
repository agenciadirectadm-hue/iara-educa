import { useState } from 'react';
import { useSearchParams } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import { ArrowRightLeft, CalendarClock, CheckCheck, GraduationCap, Hourglass, MapPinned, RefreshCw, School, UserX } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtInt } from '@/lib/format';
import { SHIFT } from '@/lib/labels';
import { Badge, Button, Card, Chip, EmptyState, ErrorState, Field, Kpi, MarcaSimulado, PageHeader, Section, Simulado, SkeletonList, Tabs, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { UnitSelect } from '@/components/escola';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { SIT_REM, TransferenciaSheet } from '@/components/sprint5';

type Aba = 'alunos' | 'unidades' | 'projecao' | 'transferencias';
const SIT_TRANSF: Record<string, { label: string; tone: 'green' | 'amber' | 'red' | 'gray' | 'purple' }> = {
  AGUARDANDO_DESTINO: { label: 'Aguardando o destino', tone: 'purple' }, EFETIVADA: { label: 'Efetivada', tone: 'green' }, RECUSADA: { label: 'Recusada', tone: 'red' },
  FILA: { label: 'Fila de transferência', tone: 'amber' }, CANCELADA: { label: 'Cancelada', tone: 'gray' },
};

function useRecarregar() {
  const qc = useQueryClient();
  return () => ['rematricula_painel', 'transferencias_lista', 'familia_rematricula'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
}

/** Rematrícula do ano seguinte (confirmação pela família no portal/IARA ou no balcão), projeção de vagas e transferências entre unidades da rede. */
export default function Rematricula() {
  const { me } = useSession();
  const rede = me?.scope !== 'UNIT';
  const [sp, setSp] = useSearchParams();
  const [unit, setUnit] = useState<number | null>(null);
  const aba = (sp.get('aba') ?? (rede && !unit ? 'unidades' : 'alunos')) as Aba;
  const [sit, setSit] = useState('');
  const [busca, setBusca] = useState('');
  const q = useDebounced(busca, 300);
  const res = useRpc<any>('rematricula_painel', { unit_id: unit, situacao: sit, busca: q });
  const tr = useRpc<any>('transferencias_lista', { unit_id: unit });
  const [gerar, setGerar] = useState(false);
  const d = res.data;
  const r = d?.resumo;
  const pct = r && r.total - r.concluintes > 0 ? Math.round((100 * r.confirmadas) / (r.total - r.concluintes)) : 0;
  const recebidas = (tr.data?.recebidas ?? []).length;
  return (
    <div>
      <PageHeader eyebrow={rede ? 'SEDUC · rede municipal' : me?.unit?.name}
        title={<span className="inline-flex items-center gap-2">Rematrícula {d?.ano ?? ''}<Simulado detail="Rematrículas e transferências de demonstração." /></span>}
        subtitle="A família confirma pelo portal ou pela IARA; quem conclui a etapa vai para a escola mais perto que oferece a série. Transferências respeitam a fila (IN nº 025/2025)."
        actions={<>{rede && <UnitSelect value={unit} onChange={setUnit} />}{d?.pode_gerar && <Button icon={RefreshCw} variant="secondary" onClick={() => setGerar(true)}>Gerar rematrícula</Button>}</>} />
      {res.isLoading ? <SkeletonList rows={4} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <>
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-6">
            <Kpi compact icon={CheckCheck} tone={pct >= 80 ? 'green' : 'amber'} label="Confirmadas" value={`${pct}%`} sub={`${fmtInt(r.confirmadas)} de ${fmtInt(r.total - r.concluintes)}`} onClick={() => setSit('CONFIRMADA')} />
            <Kpi compact icon={CalendarClock} tone="amber" label={`Pendentes (prazo ${fmtDate(d.prazo)})`} value={fmtInt(r.pendentes)} onClick={() => setSit('PENDENTE')} />
            <Kpi compact icon={Hourglass} tone="purple" label="Aguardam o resultado final" value={fmtInt(r.aguardando_resultado)} onClick={() => setSit('AGUARDANDO_RESULTADO')} />
            <Kpi compact icon={MapPinned} tone="blue" label="Mudam de escola (transição)" value={fmtInt(r.transicao)} sub={d.unit_id ? `${fmtInt(r.chegam)} chegam de outras` : undefined} />
            <Kpi compact icon={UserX} tone="red" label="Não renovam / outra escola" value={fmtInt(r.nao_renovadas + r.outra_escola)} onClick={() => setSit('NAO_RENOVADA')} />
            <Kpi compact icon={GraduationCap} tone="gray" label="Concluintes do 5º ano" value={fmtInt(r.concluintes)} sub="seguem para a rede estadual" onClick={() => setSit('CONCLUINTE')} />
          </div>
          <Tabs className="mt-4" value={aba} onChange={(v) => setSp({ aba: v }, { replace: true })} items={[
            ...(d.unit_id ? [{ value: 'alunos' as Aba, label: 'Alunos' }] : [{ value: 'unidades' as Aba, label: 'Por unidade' }]),
            { value: 'projecao', label: d.unit_id ? `Projeção de vagas ${d.ano}` : `Séries sem vaga em ${d.ano}` },
            { value: 'transferencias', label: 'Transferências', count: recebidas || null },
          ]} />
          <div className="mt-3">
            {aba === 'alunos' && d.unit_id && <Alunos d={d} sit={sit} setSit={setSit} busca={busca} setBusca={setBusca} />}
            {aba === 'unidades' && !d.unit_id && <PorUnidade d={d} onUnidade={(id) => { setUnit(id); setSp({ aba: 'alunos' }, { replace: true }); }} />}
            {aba === 'projecao' && <Projecao d={d} />}
            {aba === 'transferencias' && <Transferencias res={tr} />}
          </div>
        </>
      )}
      <GerarSheet open={gerar} onClose={() => setGerar(false)} prazo={d?.prazo} ano={d?.ano} />
    </div>
  );
}

function Alunos({ d, sit, setSit, busca, setBusca }: { d: any; sit: string; setSit: (s: string) => void; busca: string; setBusca: (s: string) => void }) {
  const [aberto, setAberto] = useState<any | null>(null);
  const [transf, setTransf] = useState<any | null>(null);
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-1.5">
        <Chip active={!sit} onClick={() => setSit('')}>Todas</Chip>
        {Object.entries(SIT_REM).map(([k, v]) => <Chip key={k} active={sit === k} onClick={() => setSit(k)}>{v.label.replace('Aguardando a sua confirmação', 'Pendente')}</Chip>)}
        <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar aluno" aria-label="Buscar aluno" className={`${inputCls} ml-auto h-9 w-56`} />
      </div>
      <Card className="overflow-hidden">
        <Tabela colunas="minmax(200px,1.6fr) minmax(170px,1.2fr) minmax(160px,1fr) 90px 190px 80px" largura={980} rotulo="Rematrícula por aluno">
          <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Série {d.ano - 1} → {d.ano}</TCelula><TCelula>Escola em {d.ano}</TCelula><TCelula>Turno</TCelula><TCelula>Situação</TCelula><TCelula>Canal</TCelula></TCabecalho>
          {(d.itens as any[]).map((x) => (
            <TLinha key={x.id} onClick={() => setAberto(x)} alerta={x.situacao === 'PENDENTE' && x.tipo === 'TRANSICAO'} rotulo={x.aluno}>
              <TCelula fixa titulo={x.aluno} className="font-semibold">{x.is_demo && <MarcaSimulado className="mr-1" />}{x.aluno}</TCelula>
              <TCelula titulo={`${x.serie_origem} → ${x.serie_destino}`}>{x.turma_origem} → {x.serie_destino}</TCelula>
              <TCelula titulo={x.unidade_destino}>{x.tipo === 'TRANSICAO' && <Badge tone="blue" className="mr-1">transição</Badge>}{x.unidade_destino ?? '—'}</TCelula>
              <TCelula>{SHIFT[x.turno_destino] ?? '—'}</TCelula>
              <TCelula><Badge tone={SIT_REM[x.situacao]?.tone}>{x.situacao === 'PENDENTE' ? 'Pendente' : SIT_REM[x.situacao]?.label}</Badge></TCelula>
              <TCelula className="text-muted">{x.canal ? x.canal.toLowerCase() : '—'}</TCelula>
            </TLinha>
          ))}
        </Tabela>
        {!(d.itens as any[]).length && <EmptyState compact title="Nenhum aluno nesta situação" />}
      </Card>
      {(d.itens as any[]).length >= 400 && <p className="text-[12.5px] text-muted">Mostrando os 400 primeiros; use a busca ou a situação para filtrar.</p>}
      <AlunoSheet x={aberto} podeConfirmar={d.pode_confirmar} onClose={() => setAberto(null)} onTransferir={(x) => { setAberto(null); setTransf(x); }} />
      <TransferenciaSheet alvo={transf} onClose={() => setTransf(null)} />
    </div>
  );
}

function AlunoSheet({ x, podeConfirmar, onClose, onTransferir }: { x: any | null; podeConfirmar: boolean; onClose: () => void; onTransferir: (x: any) => void }) {
  const recarregar = useRecarregar();
  const toast = useToast();
  const [acao, setAcao] = useState<string | null>(null);
  const [motivo, setMotivo] = useState('');
  const [turno, setTurno] = useState('');
  const [busy, setBusy] = useState(false);
  const fechar = () => { setAcao(null); setMotivo(''); setTurno(''); onClose(); };
  const enviar = async (a: string) => {
    setBusy(true);
    try {
      const r = await rpc<any>('rematricula_responder', { id: x.id, acao: a, motivo, turno: turno || undefined });
      toast({ title: 'Registrado', description: r.mensagem, tone: 'success' });
      recarregar();
      fechar();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const aberta = x && !['CONCLUINTE'].includes(x.situacao);
  return (
    <Sheet open={!!x} onClose={fechar} title={x?.aluno ?? ''} subtitle={x ? `${x.serie_origem} · ${x.turma_origem} · ${x.unidade_origem}` : ''}>
      {x && (
        <div className="space-y-3 pt-1 text-[14px]">
          <div className="flex flex-wrap items-center gap-2"><Badge tone={SIT_REM[x.situacao]?.tone}>{x.situacao === 'PENDENTE' ? 'Pendente' : SIT_REM[x.situacao]?.label}</Badge>{x.tipo === 'TRANSICAO' && <Badge tone="blue">transição de etapa</Badge>}</div>
          <p>{x.situacao === 'CONCLUINTE' ? 'Concluinte do 5º ano: a matrícula do 6º ano é na rede estadual; a escola orienta a família.'
            : <>Em {x.ano}: <b>{x.serie_destino}</b> na <b>{x.unidade_destino}</b>, turno {SHIFT[x.turno_destino]?.toLowerCase()}{x.distancia_m ? ` (a ${(x.distancia_m / 1000).toFixed(1).replace('.', ',')} km de casa)` : ''}.</>}</p>
          {x.situacao === 'AGUARDANDO_RESULTADO' && <p className="text-muted">A série de {x.ano} depende do resultado final (conselho de classe). Se houver retenção, a rematrícula é refeita para a mesma série.</p>}
          {x.motivo && <p className="text-muted">Motivo: {x.motivo}</p>}
          {x.confirmada_em && <p className="text-[12.5px] text-muted">Respondida em {fmtDate(x.confirmada_em)} por {x.confirmada_por}{x.canal ? ` (${x.canal.toLowerCase()})` : ''}.</p>}
          {podeConfirmar && aberta && (
            <div className="space-y-3 border-t border-line pt-3">
              {!acao && (
                <div className="flex flex-wrap gap-2">
                  {x.situacao !== 'CONFIRMADA' && <Button size="sm" loading={busy} onClick={() => enviar('CONFIRMAR')}>Confirmar no balcão</Button>}
                  {(x.turnos_destino ?? []).length > 1 && <Button size="sm" variant="secondary" onClick={() => setAcao('TURNO')}>Trocar o turno</Button>}
                  <Button size="sm" variant="secondary" onClick={() => setAcao('NAO_RENOVAR')}>Não renova</Button>
                  <Button size="sm" variant="secondary" icon={ArrowRightLeft} onClick={() => onTransferir(x)}>Pedir transferência</Button>
                </div>
              )}
              {acao === 'TURNO' && (
                <>
                  <div className="flex flex-wrap gap-2">{(x.turnos_destino as string[]).map((t) => <Chip key={t} active={turno === t} onClick={() => setTurno(t)}>{SHIFT[t] ?? t}</Chip>)}</div>
                  <Button block loading={busy} disabled={!turno} onClick={() => enviar('CONFIRMAR')}>Confirmar com este turno</Button>
                </>
              )}
              {acao === 'NAO_RENOVAR' && (
                <>
                  <Field label="Motivo" hint="Ex.: mudança de cidade, escola particular."><input value={motivo} onChange={(e) => setMotivo(e.target.value)} className={inputCls} /></Field>
                  <Button block loading={busy} disabled={motivo.trim().length < 5} onClick={() => enviar('NAO_RENOVAR')}>Registrar que não renova</Button>
                </>
              )}
            </div>
          )}
        </div>
      )}
    </Sheet>
  );
}

function PorUnidade({ d, onUnidade }: { d: any; onUnidade: (id: number) => void }) {
  return (
    <Card className="overflow-hidden">
      <Tabela colunas="minmax(220px,2fr) 100px 120px 110px" largura={560} rotulo="Rematrícula por unidade">
        <TCabecalho><TCelula fixa>Unidade</TCelula><TCelula>Alunos</TCelula><TCelula>Confirmadas</TCelula><TCelula>%</TCelula></TCabecalho>
        {((d.unidades ?? []) as any[]).map((u) => (
          <TLinha key={u.unit_id} onClick={() => onUnidade(u.unit_id)} alerta={(u.pct ?? 0) < 40} rotulo={u.unidade}>
            <TCelula fixa className="font-semibold">{u.unidade}</TCelula><TCelula>{fmtInt(u.total)}</TCelula><TCelula>{fmtInt(u.confirmadas)}</TCelula><TCelula>{u.pct ?? '—'}%</TCelula>
          </TLinha>
        ))}
      </Tabela>
    </Card>
  );
}

function Projecao({ d }: { d: any }) {
  const itens = d.projecao as any[];
  return (
    <div className="space-y-2">
      <p className="text-[12.5px] text-muted">Capacidade das turmas atuais × alunos que seguem para cada série e turno (pendentes, aguardando resultado e confirmados). Saldo negativo: falta vaga em {d.ano} — abrir turma, remanejar turno ou orientar transição.</p>
      <Card className="overflow-hidden">
        <Tabela colunas="minmax(170px,1.4fr) minmax(130px,1fr) 90px 100px 100px 90px 80px" largura={820} rotulo="Projeção de vagas">
          <TCabecalho><TCelula fixa>Unidade</TCelula><TCelula>Série</TCelula><TCelula>Turno</TCelula><TCelula>Capacidade</TCelula><TCelula>Previstos</TCelula><TCelula>Saldo</TCelula><TCelula>Fila</TCelula></TCabecalho>
          {itens.map((p) => (
            <TLinha key={`${p.unit_id}-${p.grade}-${p.turno}`} alerta={p.saldo < 0} rotulo={`${p.unidade} ${p.serie}`}>
              <TCelula fixa titulo={p.unidade}>{p.unidade}</TCelula><TCelula>{p.serie}</TCelula><TCelula>{SHIFT[p.turno] ?? p.turno}</TCelula>
              <TCelula>{fmtInt(p.capacidade)}</TCelula><TCelula>{fmtInt(p.previstos)}</TCelula>
              <TCelula className={p.saldo < 0 ? 'font-bold text-red-700' : 'text-emerald-700'}>{p.saldo > 0 ? '+' : ''}{fmtInt(p.saldo)}</TCelula><TCelula>{fmtInt(p.fila)}</TCelula>
            </TLinha>
          ))}
        </Tabela>
        {!itens.length && <EmptyState compact title="Nenhuma série sem vaga prevista" />}
      </Card>
    </div>
  );
}

function Transferencias({ res }: { res: any }) {
  const [aberta, setAberta] = useState<any | null>(null);
  if (res.isLoading) return <SkeletonList rows={3} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const linha = (t: any, recebida: boolean) => (
    <TLinha key={t.id} onClick={() => setAberta({ ...t, recebida })} alerta={recebida} rotulo={t.aluno}>
      <TCelula fixa titulo={t.aluno} className="font-semibold">{t.is_demo && <MarcaSimulado className="mr-1" />}{t.aluno}</TCelula>
      <TCelula>{t.serie} · {SHIFT[t.turno] ?? t.turno}</TCelula>
      <TCelula titulo={`${t.unidade_origem} → ${t.unidade_destino}`}>{t.unidade_origem} → {t.unidade_destino}</TCelula>
      <TCelula>{fmtDate(t.criada_em)}</TCelula>
      <TCelula><Badge tone={SIT_TRANSF[t.situacao]?.tone}>{SIT_TRANSF[t.situacao]?.label}</Badge></TCelula>
    </TLinha>
  );
  const cols = 'minmax(190px,1.4fr) minmax(150px,1fr) minmax(220px,1.6fr) 100px 180px';
  return (
    <div className="space-y-4">
      <Section title="Recebidas — aguardando a sua unidade" className="mt-0">
        <Card className="overflow-hidden">
          <Tabela colunas={cols} largura={900} rotulo="Transferências recebidas">
            <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Série e turno</TCelula><TCelula>De → para</TCelula><TCelula>Pedido</TCelula><TCelula>Situação</TCelula></TCabecalho>
            {(d.recebidas as any[]).map((t) => linha(t, true))}
          </Tabela>
          {!(d.recebidas as any[]).length && <EmptyState compact title="Nenhum pedido aguardando" />}
        </Card>
      </Section>
      <Section title="Pedidos da unidade e histórico">
        <Card className="overflow-hidden">
          <Tabela colunas={cols} largura={900} rotulo="Transferências enviadas">
            <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Série e turno</TCelula><TCelula>De → para</TCelula><TCelula>Pedido</TCelula><TCelula>Situação</TCelula></TCabecalho>
            {(d.enviadas as any[]).map((t) => linha(t, false))}
          </Tabela>
          {!(d.enviadas as any[]).length && <EmptyState compact title="Nenhum pedido" />}
        </Card>
      </Section>
      <TransferenciaDetalhe t={aberta} podeResponder={d.pode_responder} onClose={() => setAberta(null)} />
    </div>
  );
}

function TransferenciaDetalhe({ t, podeResponder, onClose }: { t: any | null; podeResponder: boolean; onClose: () => void }) {
  const recarregar = useRecarregar();
  const toast = useToast();
  const [turma, setTurma] = useState('');
  const [motivo, setMotivo] = useState('');
  const [recusar, setRecusar] = useState(false);
  const [busy, setBusy] = useState(false);
  const fechar = () => { setTurma(''); setMotivo(''); setRecusar(false); onClose(); };
  const responder = async (args: object, ok: string) => {
    setBusy(true);
    try {
      await rpc('transferencia_responder', { id: t.id, ...args });
      toast({ title: ok, tone: 'success' });
      recarregar();
      fechar();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const responde = t?.recebida && podeResponder && t.situacao === 'AGUARDANDO_DESTINO';
  return (
    <Sheet open={!!t} onClose={fechar} title={t?.aluno ?? ''} subtitle={t ? `${t.serie} · ${SHIFT[t.turno] ?? t.turno} · ${t.unidade_origem} → ${t.unidade_destino}` : ''}>
      {t && (
        <div className="space-y-3 pt-1 text-[14px]">
          <Badge tone={SIT_TRANSF[t.situacao]?.tone}>{SIT_TRANSF[t.situacao]?.label}</Badge>
          <p>Pedido por {t.solicitante === 'FAMILIA' ? 'família' : t.solicitante === 'ESCOLA' ? 'escola' : 'SEDUC'} ({t.solicitada_por_label}) em {fmtDate(t.criada_em)} · motivo: {String(t.motivo_tipo).replace(/_/g, ' ').toLowerCase()}{t.motivo ? ` — ${t.motivo}` : ''}.</p>
          <p className="text-muted">No pedido: {fmtInt(t.vagas_no_pedido)} vaga(s) ofertável(is) e {fmtInt(t.fila_no_pedido)} criança(s) na fila da série.</p>
          {(t.pendencias as string[]).length > 0 && <ul className="list-disc pl-5 text-amber-800">{(t.pendencias as string[]).map((p) => <li key={p}>{p}</li>)}</ul>}
          {t.resposta && <p className="text-muted">Resposta: {t.resposta}</p>}
          {t.turma_destino && <p>Turma de destino: <b>{t.turma_destino}</b>.</p>}
          {responde && !recusar && (
            <div className="space-y-2 border-t border-line pt-3">
              <Field label="Turma de destino">
                <div className="flex flex-wrap gap-2">{(t.turmas_com_vaga as any[]).map((c) => <Chip key={c.class_id} active={turma === c.class_id} onClick={() => setTurma(c.class_id)}>{c.turma} · {c.vagas} vaga(s)</Chip>)}</div>
              </Field>
              {!(t.turmas_com_vaga as any[]).length && <p className="text-amber-800">Nenhuma turma com vaga ofertável agora.</p>}
              <div className="flex gap-2">
                <Button icon={School} loading={busy} disabled={!turma} onClick={() => responder({ aceitar: true, class_id: turma }, 'Transferência efetivada')}>Aceitar e matricular</Button>
                <Button variant="secondary" onClick={() => setRecusar(true)}>Recusar</Button>
              </div>
            </div>
          )}
          {responde && recusar && (
            <div className="space-y-2 border-t border-line pt-3">
              <Field label="Motivo da recusa" hint="A família e a escola de origem veem a resposta."><input value={motivo} onChange={(e) => setMotivo(e.target.value)} className={inputCls} /></Field>
              <Button block variant="danger" loading={busy} disabled={motivo.trim().length < 10} onClick={() => responder({ aceitar: false, motivo }, 'Pedido recusado')}>Recusar o pedido</Button>
            </div>
          )}
          {!t.recebida && t.situacao === 'AGUARDANDO_DESTINO' && (
            <Button variant="secondary" loading={busy} onClick={() => responder({ cancelar: true }, 'Pedido cancelado')}>Cancelar o pedido</Button>
          )}
        </div>
      )}
    </Sheet>
  );
}

function GerarSheet({ open, onClose, prazo, ano }: { open: boolean; onClose: () => void; prazo?: string; ano?: number }) {
  const recarregar = useRecarregar();
  const toast = useToast();
  const [p, setP] = useState('');
  const [busy, setBusy] = useState(false);
  const gerar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('rematricula_gerar', { ano, prazo: p || undefined });
      toast({ title: 'Rematrícula gerada', description: `${fmtInt(r.gerados)} aluno(s) sem resposta atualizados com a série e a escola de ${ano}.`, tone: 'success' });
      recarregar();
      onClose();
    } catch (e) {
      toast({ title: 'Não gerada', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} title={`Gerar a rematrícula ${ano ?? ''}`}
      subtitle="Calcula a série de cada aluno (data de corte 31/03) e a escola: a mesma, se ela oferece a série; senão, a mais perto de casa. Quem já respondeu não muda."
      footer={<Button block icon={RefreshCw} loading={busy} onClick={gerar}>Gerar</Button>}>
      <Field label="Prazo para a família confirmar" hint={`Atual: ${prazo ? fmtDate(prazo) : '—'}`}><input type="date" value={p} onChange={(e) => setP(e.target.value)} className={inputCls} /></Field>
    </Sheet>
  );
}
