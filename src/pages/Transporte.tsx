import { useState } from 'react';
import { useSearchParams } from 'react-router';
import { AlarmClock, Ban, Bus, FileWarning, Route, Users } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useNow, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate, fmtInt, fmtPct } from '@/lib/format';
import { SHIFT } from '@/lib/labels';
import { Badge, Button, Card, Chip, EmptyState, ErrorState, Field, Kpi, PageHeader, Simulado, SkeletonList, Tabs, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { UnitSelect } from '@/components/escola';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { EstadoViagem, MOTIVO_TRANSPORTE, TIPO_OCORRENCIA_TR, TIPO_VEICULO, hm, useRecarregarTransporte } from '@/components/transporte';

type Aba = 'rotas' | 'sem_rota' | 'ocorrencias' | 'frota';

/** Transporte escolar: viagens de hoje, rotas, alunos aguardando, ocorrências e frota. Também é o início da Gerência de Transporte. */
export default function Transporte() {
  useNow(60_000);
  const { me } = useSession();
  const rede = me?.scope !== 'UNIT';
  const [sp, setSp] = useSearchParams();
  const aba = (sp.get('aba') ?? 'rotas') as Aba;
  const [unit, setUnit] = useState<number | null>(null);
  const res = useRpc<any>('transporte_painel', { unit_id: unit }, { refetchInterval: 60_000 });
  const d = res.data;
  return (
    <div>
      <PageHeader eyebrow={rede ? 'SEDUC · Gerência de Transporte Escolar' : me?.unit?.name}
        title={<span className="inline-flex items-center gap-2">Transporte escolar<Simulado detail="Rotas, veículos, motoristas, viagens e posição de demonstração." /></span>}
        subtitle="Rota planejada (pontos e horários) e execução do dia: quem está a caminho, quem atrasou, viagem não realizada com aviso às famílias e falta abonada."
        actions={rede ? <UnitSelect value={unit} onChange={setUnit} /> : undefined} />
      {res.isLoading ? <SkeletonList rows={5} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <>
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
            <Kpi compact icon={Route} tone="blue" label="Rotas ativas" value={fmtInt(d.rotas)} sub={`${fmtInt(d.alunos)} alunos transportados`} />
            <Kpi compact icon={Bus} tone="purple" label="Agora a caminho" value={fmtInt(d.hoje.em_andamento)} sub={`${fmtInt(d.hoje.concluidas)} concluídas · ${fmtInt(d.hoje.previstas)} previstas`} />
            <Kpi compact icon={AlarmClock} tone="amber" label="Atrasadas hoje (10+ min)" value={fmtInt(d.hoje.atrasadas)} sub={d.pontualidade_30d != null ? `pontualidade 30 dias: ${fmtPct(d.pontualidade_30d)}` : undefined} />
            <Kpi compact icon={Ban} tone="red" label="Não realizadas" value={fmtInt(d.hoje.nao_realizadas)} sub={`${fmtInt(d.nao_realizadas_30d)} nos últimos 30 dias`} onClick={() => setSp({ aba: 'ocorrencias' }, { replace: true })} />
            <Kpi compact icon={Users} tone="teal" label="Aguardando rota" value={fmtInt(d.sem_rota)} onClick={() => setSp({ aba: 'sem_rota' }, { replace: true })} />
          </div>
          {d.frota && (
            <Card className="mt-3 flex flex-wrap items-center gap-3 p-3 text-[13px]">
              <span><b>{fmtInt(d.frota.veiculos)}</b> veículos · <b>{fmtInt(d.frota.reserva)}</b> na reserva · <b>{fmtInt(d.frota.manutencao)}</b> em manutenção</span>
              {(d.frota.docs_vencidas > 0 || d.frota.docs_vencendo > 0) && (
                <button type="button" onClick={() => setSp({ aba: 'frota' }, { replace: true })} className="inline-flex items-center gap-1 font-semibold text-red-700">
                  <FileWarning className="size-4" />{fmtInt(d.frota.docs_vencidas)} documento(s) vencido(s) · {fmtInt(d.frota.docs_vencendo)} vencendo em 30 dias
                </button>
              )}
            </Card>
          )}
          <Tabs className="mt-4" value={aba} onChange={(v) => setSp({ aba: v }, { replace: true })} items={[
            { value: 'rotas', label: 'Rotas e viagens de hoje' }, { value: 'sem_rota', label: 'Aguardando rota', count: d.sem_rota || null },
            { value: 'ocorrencias', label: 'Ocorrências', count: d.ocorrencias_abertas || null }, ...(d.pode_gerir ? [{ value: 'frota' as Aba, label: 'Frota e motoristas' }] : []),
          ]} />
          <div className="mt-3">
            {aba === 'rotas' && <Rotas lista={d.lista ?? []} />}
            {aba === 'sem_rota' && <SemRota unitId={unit} podeGerir={d.pode_gerir} />}
            {aba === 'ocorrencias' && <Ocorrencias unitId={unit} />}
            {aba === 'frota' && d.pode_gerir && <Frota />}
          </div>
        </>
      )}
    </div>
  );
}

function Rotas({ lista }: { lista: any[] }) {
  const [filtro, setFiltro] = useState<'todas' | 'problema' | 'andamento'>('todas');
  const itens = lista.filter((r) => filtro === 'todas' || (filtro === 'andamento' ? r.hoje?.situacao === 'EM_ANDAMENTO'
    : r.hoje?.situacao === 'NAO_REALIZADA' || Number(r.hoje?.atraso_min ?? 0) >= 10));
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        <Chip active={filtro === 'todas'} onClick={() => setFiltro('todas')}>Todas ({lista.length})</Chip>
        <Chip active={filtro === 'andamento'} onClick={() => setFiltro('andamento')}>A caminho</Chip>
        <Chip active={filtro === 'problema'} onClick={() => setFiltro('problema')}>Atrasadas ou não realizadas</Chip>
      </div>
      <Card className="overflow-hidden">
        {itens.length ? (
          <Tabela colunas="90px minmax(170px,1.5fr) 90px 150px 80px 70px minmax(220px,1.6fr)" largura={1000} rotulo="Rotas">
            <TCabecalho><TCelula fixa>Rota</TCelula><TCelula>Escola</TCelula><TCelula>Turno</TCelula><TCelula>Veículo</TCelula><TCelula>Alunos</TCelula><TCelula>Km</TCelula><TCelula>Agora</TCelula></TCabecalho>
            {itens.map((r) => (
              <TLinha key={r.id} to={`/transporte/rotas/${r.id}`} alerta={r.hoje?.situacao === 'NAO_REALIZADA' || Number(r.hoje?.atraso_min ?? 0) >= 15} rotulo={`Rota ${r.codigo}`}>
                <TCelula fixa className="font-semibold">{r.codigo}</TCelula>
                <TCelula titulo={r.unidade}>{r.unidade}</TCelula>
                <TCelula>{SHIFT[r.turno] ?? r.turno}</TCelula>
                <TCelula titulo={r.veiculo?.placa}>{TIPO_VEICULO[r.veiculo?.tipo] ?? '—'} {r.veiculo?.placa}{r.veiculo?.acessivel ? ' ♿' : ''}</TCelula>
                <TCelula>{r.alunos}/{r.veiculo?.capacidade ?? '—'}</TCelula>
                <TCelula>{r.km != null ? String(r.km).replace('.', ',') : '—'}</TCelula>
                <TCelula livre><span className="mr-1 text-[11px] font-bold uppercase text-subtle">{r.hoje?.sentido === 'VOLTA' ? 'volta' : 'ida'}</span><EstadoViagem e={r.hoje} compacto /></TCelula>
              </TLinha>
            ))}
          </Tabela>
        ) : <EmptyState compact title="Nenhuma rota nesta lista" />}
      </Card>
    </div>
  );
}

function SemRota({ unitId, podeGerir }: { unitId: number | null; podeGerir: boolean }) {
  const res = useRpc<any[]>('transporte_sem_rota', { unit_id: unitId });
  const toast = useToast();
  const recarregar = useRecarregarTransporte();
  const [busy, setBusy] = useState<string | null>(null);
  const incluir = async (x: any) => {
    setBusy(x.student_id);
    try {
      await rpc('transporte_aluno_incluir', { student_id: x.student_id, rota_id: x.sugestao.rota_id, ponto_id: x.sugestao.ponto_id, motivo: x.aee ? 'DEFICIENCIA' : 'DISTANCIA' });
      toast({ title: `${x.nome} incluído(a) na rota ${x.sugestao.codigo}`, description: 'A família recebe o aviso com o ponto e o horário.', tone: 'success' });
      recarregar();
    } catch (e) {
      toast({ title: 'Não incluído', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(null);
    }
  };
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  return (
    <Card className="overflow-hidden">
      {res.data?.length ? (
        <Tabela colunas="minmax(190px,1.6fr) minmax(150px,1.2fr) 100px 90px minmax(220px,1.8fr) 120px" largura={1000} rotulo="Alunos aguardando rota">
          <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Escola e turma</TCelula><TCelula>Turno</TCelula><TCelula>Até a escola</TCelula><TCelula>Sugestão</TCelula><TCelula /></TCabecalho>
          {res.data.map((x) => (
            <TLinha key={x.student_id}>
              <TCelula fixa titulo={x.nome} className="font-semibold">{x.nome}{x.aee && <Badge tone="purple" className="ml-1">AEE</Badge>}</TCelula>
              <TCelula titulo={`${x.unidade} · ${x.turma}`}>{x.unidade} · {x.turma}</TCelula>
              <TCelula>{SHIFT[x.turno] ?? x.turno}</TCelula>
              <TCelula>{x.km_escola != null ? `${String(x.km_escola).replace('.', ',')} km` : '—'}</TCelula>
              <TCelula titulo={x.sugestao ? `${x.sugestao.codigo} · ${x.sugestao.ponto}` : ''} className="text-[12.5px]">
                {x.sugestao ? <>Rota <b>{x.sugestao.codigo}</b> · {x.sugestao.ponto} ({String(x.sugestao.km_ponto).replace('.', ',')} km) · {x.sugestao.vagas} vaga(s)</> : <span className="text-red-700">Sem rota nesta escola e turno</span>}
              </TCelula>
              <TCelula livre className="text-right">{podeGerir && x.sugestao && x.sugestao.vagas > 0 && <Button size="sm" loading={busy === x.student_id} onClick={() => incluir(x)}>Incluir</Button>}</TCelula>
            </TLinha>
          ))}
        </Tabela>
      ) : <EmptyState compact title="Ninguém aguardando rota" />}
    </Card>
  );
}

function Ocorrencias({ unitId }: { unitId: number | null }) {
  const [sit, setSit] = useState('ABERTA');
  const res = useRpc<any[]>('transporte_ocorrencias', { unit_id: unitId, situacao: sit || null });
  const [alvo, setAlvo] = useState<any | null>(null);
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        <Chip active={sit === 'ABERTA'} onClick={() => setSit('ABERTA')}>Abertas</Chip>
        <Chip active={sit === 'RESOLVIDA'} onClick={() => setSit('RESOLVIDA')}>Resolvidas</Chip>
        <Chip active={!sit} onClick={() => setSit('')}>Todas</Chip>
      </div>
      {res.isLoading ? <SkeletonList rows={5} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <Card className="overflow-hidden">
          {res.data?.length ? (
            <Tabela colunas="100px 80px minmax(150px,1fr) 170px minmax(240px,2fr) 110px" largura={1000} rotulo="Ocorrências do transporte">
              <TCabecalho><TCelula fixa>Data</TCelula><TCelula>Rota</TCelula><TCelula>Escola</TCelula><TCelula>Tipo</TCelula><TCelula>O que houve</TCelula><TCelula>Situação</TCelula></TCabecalho>
              {res.data.map((o) => (
                <TLinha key={o.id} onClick={() => setAlvo(o)} alerta={o.situacao === 'ABERTA' && ['ROTA_NAO_EXECUTADA', 'ACIDENTE'].includes(o.tipo)} rotulo={`Ocorrência ${o.rota}`}>
                  <TCelula fixa>{fmtDate(o.data)}</TCelula>
                  <TCelula className="font-semibold">{o.rota}</TCelula>
                  <TCelula titulo={o.unidade}>{o.unidade}</TCelula>
                  <TCelula livre><Badge tone={TIPO_OCORRENCIA_TR[o.tipo]?.tone ?? 'gray'}>{TIPO_OCORRENCIA_TR[o.tipo]?.label ?? o.tipo}</Badge></TCelula>
                  <TCelula titulo={o.descricao}>{o.aluno ? `${o.aluno}: ` : ''}{o.descricao}</TCelula>
                  <TCelula livre><Badge tone={o.situacao === 'ABERTA' ? 'amber' : 'green'}>{o.situacao === 'ABERTA' ? 'Aberta' : 'Resolvida'}</Badge></TCelula>
                </TLinha>
              ))}
            </Tabela>
          ) : <EmptyState compact title="Nenhuma ocorrência nesta lista" />}
        </Card>
      )}
      <ResolverSheet alvo={alvo} onClose={() => setAlvo(null)} />
    </div>
  );
}

export function ResolverSheet({ alvo, onClose }: { alvo: any | null; onClose: () => void }) {
  const { can } = useSession();
  const [prov, setProv] = useState('');
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const recarregar = useRecarregarTransporte();
  const resolver = async () => {
    setBusy(true);
    try {
      await rpc('transporte_ocorrencia_resolver', { id: alvo.id, providencia: prov });
      toast({ title: 'Ocorrência resolvida', tone: 'success' });
      recarregar();
      setProv('');
      onClose();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const pode = can('transporte.manage') && alvo?.situacao === 'ABERTA';
  return (
    <Sheet open={!!alvo} onClose={onClose} title={alvo ? `${TIPO_OCORRENCIA_TR[alvo.tipo]?.label ?? alvo.tipo} · rota ${alvo.rota ?? ''}` : ''} subtitle={alvo ? `${fmtDate(alvo.data)}${alvo.sentido ? ` · ${alvo.sentido.toLowerCase()}` : ''}` : ''}
      footer={pode ? <Button block size="lg" variant="success" loading={busy} disabled={prov.trim().length < 10} onClick={resolver}>Marcar como resolvida</Button> : undefined}>
      {alvo && (
        <div className="space-y-3 text-[14px]">
          <p>{alvo.aluno ? <b>{alvo.aluno}: </b> : null}{alvo.descricao}</p>
          {alvo.providencia && <p className="text-muted"><b>Providência:</b> {alvo.providencia}</p>}
          {alvo.familias_avisadas && <Badge tone="green">Famílias avisadas</Badge>}
          {pode && <Field label="Providência" hint="O que foi feito para resolver."><textarea value={prov} onChange={(e) => setProv(e.target.value)} rows={3} className={`${inputCls} h-auto py-3`} /></Field>}
        </div>
      )}
    </Sheet>
  );
}

function Frota() {
  const res = useRpc<any>('transporte_frota', {});
  const [aba, setAba] = useState<'v' | 'm'>('v');
  if (res.isLoading) return <SkeletonList rows={5} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const doc = (x: string) => <Badge tone={x === 'VENCIDA' ? 'red' : x === 'VENCENDO' ? 'amber' : 'green'}>{x === 'VENCIDA' ? 'Vencida' : x === 'VENCENDO' ? 'Vence em 30 dias' : 'Em dia'}</Badge>;
  return (
    <div className="space-y-3">
      <div className="flex gap-2">
        <Chip active={aba === 'v'} onClick={() => setAba('v')}>Veículos ({res.data.veiculos.length})</Chip>
        <Chip active={aba === 'm'} onClick={() => setAba('m')}>Motoristas ({res.data.motoristas.length})</Chip>
      </div>
      <Card className="overflow-hidden">
        {aba === 'v' ? (
          <Tabela colunas="110px 120px 90px 90px minmax(200px,1.6fr) 110px 120px 150px" largura={1050} rotulo="Veículos">
            <TCabecalho><TCelula fixa>Placa</TCelula><TCelula>Tipo</TCelula><TCelula>Lugares</TCelula><TCelula>Rota</TCelula><TCelula>Operador</TCelula><TCelula>Situação</TCelula><TCelula>Vistoria</TCelula><TCelula>Documentação</TCelula></TCabecalho>
            {(res.data.veiculos as any[]).map((v) => (
              <TLinha key={v.id} alerta={v.doc === 'VENCIDA'}>
                <TCelula fixa className="font-mono font-semibold">{v.placa}</TCelula>
                <TCelula>{TIPO_VEICULO[v.tipo]}{v.acessivel ? ' ♿' : ''}</TCelula>
                <TCelula>{v.capacidade}</TCelula>
                <TCelula>{v.rota ?? '—'}</TCelula>
                <TCelula titulo={v.operador}>{v.operador}</TCelula>
                <TCelula>{v.situacao === 'RESERVA' ? 'Reserva' : v.situacao === 'MANUTENCAO' ? 'Manutenção' : 'Ativo'}</TCelula>
                <TCelula>{fmtDate(v.vistoria_validade)}</TCelula>
                <TCelula livre>{doc(v.doc)}</TCelula>
              </TLinha>
            ))}
          </Tabela>
        ) : (
          <Tabela colunas="minmax(200px,1.6fr) 70px 90px 120px 140px minmax(160px,1.2fr) 150px" largura={1000} rotulo="Motoristas">
            <TCabecalho><TCelula fixa>Motorista</TCelula><TCelula>CNH</TCelula><TCelula>Rota</TCelula><TCelula>CNH vence</TCelula><TCelula>Curso (art. 138)</TCelula><TCelula>Operador</TCelula><TCelula>Documentação</TCelula></TCabecalho>
            {(res.data.motoristas as any[]).map((m) => (
              <TLinha key={m.id} alerta={m.doc === 'VENCIDA'}>
                <TCelula fixa titulo={m.nome} className="font-semibold">{m.nome}</TCelula>
                <TCelula>{m.cnh_categoria}</TCelula>
                <TCelula>{m.rota ?? (m.situacao === 'RESERVA' ? 'reserva' : '—')}</TCelula>
                <TCelula>{fmtDate(m.cnh_validade)}</TCelula>
                <TCelula>{fmtDate(m.curso_validade)}</TCelula>
                <TCelula titulo={m.operador}>{m.operador}</TCelula>
                <TCelula livre>{doc(m.doc)}</TCelula>
              </TLinha>
            ))}
          </Tabela>
        )}
      </Card>
      <p className="text-[12.5px] text-muted">Código de Trânsito: veículo com vistoria semestral; motorista com CNH categoria D e curso especializado de transporte escolar (art. 136 a 138).</p>
    </div>
  );
}

export const MOTIVOS = MOTIVO_TRANSPORTE;
export { hm };
