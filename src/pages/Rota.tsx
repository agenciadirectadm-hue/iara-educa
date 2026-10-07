import { lazy, Suspense, useState } from 'react';
import { Link, useParams, useSearchParams } from 'react-router';
import { ClipboardCheck, ClipboardPlus, Flag, Play, UserMinus } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useNow, useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate } from '@/lib/format';
import { SHIFT } from '@/lib/labels';
import { Badge, Button, Card, EmptyState, ErrorState, Field, PageHeader, Section, Segmented, Simulado, Skeleton, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';
import { EstadoViagem, MOTIVO_TRANSPORTE, TIPO_OCORRENCIA_TR, TIPO_VEICULO, hm, useRecarregarTransporte } from '@/components/transporte';
import { ResolverSheet } from './Transporte';

const MapView = lazy(() => import('@/components/map/MapView'));

/** Rota: mapa com os pontos e o veículo, viagens de hoje (registrar situação), alunos, histórico e ocorrências. */
export default function Rota() {
  useNow(30_000);
  const { id } = useParams();
  const res = useRpc<any>('transporte_rota', { id }, { refetchInterval: 30_000 });
  const [viagem, setViagem] = useState<string | null>(null);
  const [ocorrencia, setOcorrencia] = useState(false);
  const [resolver, setResolver] = useState<any | null>(null);
  const [remover, setRemover] = useState<any | null>(null);
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const r = res.data;
  const emCurso = [r.hoje.ida, r.hoje.volta].find((e: any) => e?.situacao === 'EM_ANDAMENTO');
  const pontos = [
    ...(r.pontos as any[]).map((p) => ({ lat: p.lat, lng: p.lng, tipo: 'PARADA' as const, rotulo: String(p.ordem) })),
    { lat: r.escola.lat, lng: r.escola.lng, tipo: 'ESCOLA' as const, rotulo: 'E' },
    ...(emCurso?.posicao ? [{ lat: emCurso.posicao.lat, lng: emCurso.posicao.lng, tipo: 'VEICULO' as const, rotulo: '' }] : []),
  ];
  const linha: [number, number][] = [...(r.pontos as any[]).map((p) => [p.lng, p.lat] as [number, number]), [r.escola.lng, r.escola.lat]];
  return (
    <div>
      <PageHeader eyebrow={<span className="inline-flex items-center gap-1">Transporte escolar · {r.unidade}{r.is_demo && <Simulado detail="Rota fictícia." />}</span>}
        title={`Rota ${r.codigo}`} subtitle={`${SHIFT[r.turno] ?? r.turno} · ${TIPO_VEICULO[r.veiculo?.tipo] ?? ''} ${r.veiculo?.placa ?? ''} (${r.alunos}/${r.veiculo?.capacidade ?? '—'} lugares${r.veiculo?.acessivel ? ', acessível' : ''}) · motorista ${r.motorista?.nome ?? '—'}${r.monitor ? ` · monitor(a) ${r.monitor}` : ''} · ${String(r.km ?? '—').replace('.', ',')} km`}
        actions={<>
          <Link to={`/transporte/rotas/${r.id}/embarque?sentido=${emCurso?.sentido ?? 'IDA'}`} className="inline-flex h-11 items-center gap-1.5 rounded-2xl bg-white px-4 text-[15px] font-semibold ring-1 ring-line hover:bg-blue-50"><ClipboardCheck className="size-4" />Lista de embarque</Link>
          <Button variant="secondary" icon={ClipboardPlus} onClick={() => setOcorrencia(true)}>Registrar ocorrência</Button>
        </>} />
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_360px]">
        <Card className="overflow-hidden">
          <Suspense fallback={<Skeleton className="h-80" />}>
            <MapView units={[]} pontos={pontos} trajetos={[{ id: 1, modo: 'CARRO', coords: r.trajeto ?? linha }]} focus={{ lat: r.escola.lat, lng: r.escola.lng, zoom: 13.3 }}
              className="h-80 lg:h-[420px]" legend={false} cooperative />
          </Suspense>
          <p className="px-4 py-2 text-[12px] text-muted">Pontos numerados na ordem da ida; E = escola; laranja = veículo (posição simulada pelo horário, sem GPS integrado). {r.trajeto ? `Trajeto pelas ruas (${r.trajeto_fonte}); horários e quilômetros calculados por ele.` : 'Linha reta entre os pontos (o trajeto pelas ruas ainda não foi calculado).'}</p>
        </Card>
        <div className="space-y-3">
          {(['ida', 'volta'] as const).map((s) => {
            const e = r.hoje[s];
            return (
              <Card key={s} className="p-4">
                <div className="flex items-center justify-between gap-2">
                  <div className="font-display text-lg font-extrabold">{s === 'ida' ? 'Ida' : 'Volta'} de hoje</div>
                  <EstadoViagem e={e} compacto />
                </div>
                <div className="mt-1 text-[13px] text-muted">
                  {e?.situacao === 'NAO_REALIZADA' ? e.motivo : e?.situacao === 'SEM_AULA' ? 'Hoje não tem aula.' : `${hm(e?.inicio)} → ${hm(e?.fim)}${e?.atraso_min ? ` · ${e.atraso_min} min de atraso` : ''}${e?.registrada ? ' · registrada' : e?.simulada ? ' · simulada pelo horário' : ''}`}
                </div>
                {e?.proximo && <div className="mt-1 text-[13px]">Próximo: <b>{e.proximo.nome}</b> às {hm(e.proximo.previsto)}</div>}
                {r.pode_gerir && e?.situacao !== 'SEM_AULA' && (
                  <div className="mt-2 flex flex-wrap gap-2">
                    <Button size="sm" icon={Play} variant="secondary" onClick={() => setViagem(s === 'ida' ? 'IDA' : 'VOLTA')}>Registrar situação</Button>
                  </div>
                )}
              </Card>
            );
          })}
          <Card className="p-4 text-[13px]">
            <div><b>Pontualidade (30 dias):</b> {r.pontualidade_30d != null ? `${String(r.pontualidade_30d).replace('.', ',')}%` : '—'} das viagens com menos de 10 min de atraso</div>
            <div className="mt-1 text-muted">Chegada na escola às {hm(r.chegada_ida)} · saída às {hm(r.saida_volta)}</div>
          </Card>
        </div>
      </div>

      <div className="mt-4 grid grid-cols-1 gap-4 xl:grid-cols-2">
        <Section title={`Pontos (${r.pontos.length})`}>
          <Card className="overflow-hidden">
            <Tabela colunas="50px minmax(200px,2fr) 80px 80px 70px" largura={500} rotulo="Pontos da rota">
              <TCabecalho><TCelula fixa>#</TCelula><TCelula>Ponto</TCelula><TCelula>Ida</TCelula><TCelula>Volta</TCelula><TCelula>Alunos</TCelula></TCabecalho>
              {(r.pontos as any[]).map((p) => (
                <TLinha key={p.id}>
                  <TCelula fixa className="font-semibold">{p.ordem}</TCelula>
                  <TCelula titulo={p.nome}>{p.nome}</TCelula>
                  <TCelula>{hm(p.horario_ida)}</TCelula>
                  <TCelula>{hm(p.horario_volta)}</TCelula>
                  <TCelula>{p.alunos}</TCelula>
                </TLinha>
              ))}
            </Tabela>
          </Card>
        </Section>
        <Section title={`Alunos (${r.alunos})`}>
          <Card className="overflow-hidden">
            <Tabela colunas="minmax(190px,1.8fr) 100px 60px 110px minmax(120px,1fr) 50px" largura={700} rotulo="Alunos da rota">
              <TCabecalho><TCelula fixa>Aluno</TCelula><TCelula>Turma</TCelula><TCelula>Ponto</TCelula><TCelula>Motivo</TCelula><TCelula>Hoje</TCelula><TCelula /></TCabecalho>
              {(r.alunos_rota ?? []).map((a: any) => (
                <TLinha key={a.id}>
                  <TCelula fixa titulo={a.nome} className="font-semibold">{a.nome}{a.aee && <Badge tone="purple" className="ml-1">AEE</Badge>}</TCelula>
                  <TCelula>{a.turma}</TCelula>
                  <TCelula>{a.ponto_ordem}</TCelula>
                  <TCelula>{MOTIVO_TRANSPORTE[a.motivo] ?? a.motivo}</TCelula>
                  <TCelula titulo={a.aviso_hoje?.motivo}>{a.aviso_hoje ? <Badge tone="purple">Não vai ({a.aviso_hoje.sentido === 'AMBOS' ? 'ida e volta' : a.aviso_hoje.sentido.toLowerCase()})</Badge> : ''}</TCelula>
                  <TCelula livre>{r.pode_gerir && <button type="button" aria-label={`Retirar ${a.nome} da rota`} onClick={() => setRemover(a)} className="rounded-lg p-1 text-red-700 hover:bg-red-50"><UserMinus className="size-4" /></button>}</TCelula>
                </TLinha>
              ))}
            </Tabela>
          </Card>
        </Section>
      </div>

      <div className="mt-4 grid grid-cols-1 gap-4 xl:grid-cols-2">
        <Section title="Viagens recentes">
          <Card className="overflow-hidden">
            <Tabela colunas="100px 70px 150px minmax(180px,1.5fr) 90px" largura={620} rotulo="Viagens recentes">
              <TCabecalho><TCelula fixa>Data</TCelula><TCelula>Sentido</TCelula><TCelula>Situação</TCelula><TCelula>Motivo</TCelula><TCelula>Alunos</TCelula></TCabecalho>
              {(r.viagens as any[]).map((v, i) => (
                <TLinha key={i} alerta={v.situacao === 'NAO_REALIZADA'}>
                  <TCelula fixa>{fmtDate(v.data)}</TCelula>
                  <TCelula>{v.sentido === 'IDA' ? 'Ida' : 'Volta'}</TCelula>
                  <TCelula livre><EstadoViagem e={{ situacao: v.situacao, atraso_min: v.atraso_min }} compacto />{v.substituicao && <Badge tone="purple" className="ml-1">Reserva</Badge>}</TCelula>
                  <TCelula titulo={v.motivo} className="text-muted">{v.motivo ?? ''}</TCelula>
                  <TCelula>{v.situacao === 'NAO_REALIZADA' ? '—' : `${v.transportados ?? '—'}/${v.previstos ?? '—'}`}</TCelula>
                </TLinha>
              ))}
            </Tabela>
          </Card>
        </Section>
        <Section title="Ocorrências">
          <Card className="divide-y divide-line overflow-hidden">
            {(r.ocorrencias as any[]).map((o) => (
              <button key={o.id} type="button" onClick={() => setResolver({ ...o, rota: r.codigo })} className="flex w-full items-start gap-3 px-4 py-3 text-left hover:bg-slate-50">
                <Badge tone={TIPO_OCORRENCIA_TR[o.tipo]?.tone ?? 'gray'}>{TIPO_OCORRENCIA_TR[o.tipo]?.label ?? o.tipo}</Badge>
                <span className="min-w-0 flex-1 text-[13px]"><span className="text-muted">{fmtDate(o.data)} · </span>{o.aluno ? <b>{o.aluno}: </b> : null}{o.descricao}</span>
                <Badge tone={o.situacao === 'ABERTA' ? 'amber' : 'green'}>{o.situacao === 'ABERTA' ? 'Aberta' : 'Resolvida'}</Badge>
              </button>
            ))}
            {!r.ocorrencias.length && <EmptyState compact title="Sem ocorrências" />}
          </Card>
        </Section>
      </div>
      <ViagemSheet sentido={viagem} rota={r} onClose={() => setViagem(null)} />
      <OcorrenciaSheet open={ocorrencia} rota={r} onClose={() => setOcorrencia(false)} />
      <ResolverSheet alvo={resolver} onClose={() => setResolver(null)} />
      <RemoverSheet alvo={remover} onClose={() => setRemover(null)} />
    </div>
  );
}

function ViagemSheet({ sentido, rota, onClose }: { sentido: string | null; rota: any; onClose: () => void }) {
  const [sit, setSit] = useState('CONCLUIDA');
  const [atraso, setAtraso] = useState('');
  const [motivo, setMotivo] = useState('');
  const [reserva, setReserva] = useState('');
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const recarregar = useRecarregarTransporte();
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('transporte_viagem_registrar', { rota_id: rota.id, sentido, situacao: sit, atraso_min: atraso || 0, motivo, veiculo_substituto_id: reserva || null });
      toast({ title: 'Viagem registrada', description: r.familias_avisadas ? `${r.familias_avisadas} família(s) avisada(s) pela IARA.` : undefined, tone: 'success' });
      recarregar();
      setAtraso(''); setMotivo(''); setReserva('');
      onClose();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!sentido} onClose={onClose} title={`${sentido === 'IDA' ? 'Ida' : 'Volta'} de hoje · rota ${rota.codigo}`}
      subtitle="Atraso de 15 minutos ou mais, troca de veículo ou viagem não realizada avisam as famílias da rota. Ida não realizada abona a falta do dia."
      footer={<Button block size="lg" variant={sit === 'NAO_REALIZADA' ? 'danger' : 'primary'} loading={busy} onClick={enviar}>Registrar</Button>}>
      <div className="space-y-3">
        <Segmented value={sit} onChange={setSit} items={[{ value: 'EM_ANDAMENTO', label: 'Saiu' }, { value: 'CONCLUIDA', label: 'Concluída' }, { value: 'NAO_REALIZADA', label: 'Não realizada' }]} />
        {sit !== 'NAO_REALIZADA' && (
          <div className="grid grid-cols-2 gap-3">
            <Field label="Atraso (min)"><input type="number" min={0} value={atraso} onChange={(e) => setAtraso(e.target.value)} className={`${inputCls} h-11`} /></Field>
            <Field label="Veículo reserva (se trocou)">
              <select value={reserva} onChange={(e) => setReserva(e.target.value)} className={`${inputCls} h-11`}>
                <option value="">Não trocou</option>
                {(rota.reservas ?? []).map((v: any) => <option key={v.id} value={v.id}>{v.placa} · {v.tipo === 'ONIBUS' ? 'ônibus' : v.tipo === 'MICRO' ? 'micro' : 'van'} ({v.capacidade})</option>)}
              </select>
            </Field>
          </div>
        )}
        <Field label="Motivo" hint={sit === 'NAO_REALIZADA' ? 'Obrigatório: vai no aviso às famílias.' : 'Obrigatório se o atraso for de 10 min ou mais.'}>
          <input value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={200} placeholder="Ex.: pane mecânica; chuva forte; obra na via" className={inputCls} />
        </Field>
      </div>
    </Sheet>
  );
}

function OcorrenciaSheet({ open, rota, onClose }: { open: boolean; rota: any; onClose: () => void }) {
  const [tipo, setTipo] = useState('ATRASO');
  const [aluno, setAluno] = useState('');
  const [desc, setDesc] = useState('');
  const [prov, setProv] = useState('');
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const recarregar = useRecarregarTransporte();
  const enviar = async () => {
    setBusy(true);
    try {
      await rpc('transporte_ocorrencia_registrar', { rota_id: rota.id, tipo, student_id: aluno || null, descricao: desc, providencia: prov });
      toast({ title: 'Ocorrência registrada', description: aluno ? 'A família do aluno é avisada.' : undefined, tone: 'success' });
      recarregar();
      setDesc(''); setProv(''); setAluno('');
      onClose();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} title={`Ocorrência · rota ${rota.codigo}`}
      footer={<Button block size="lg" loading={busy} disabled={desc.trim().length < 10} onClick={enviar}>Registrar</Button>}>
      <div className="space-y-3">
        <Field label="Tipo">
          <select value={tipo} onChange={(e) => setTipo(e.target.value)} className={`${inputCls} h-11`}>
            {Object.entries(TIPO_OCORRENCIA_TR).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
          </select>
        </Field>
        <Field label="Aluno (se for sobre um aluno)">
          <select value={aluno} onChange={(e) => setAluno(e.target.value)} className={`${inputCls} h-11`}>
            <option value="">Nenhum</option>
            {(rota.alunos_rota ?? []).map((a: any) => <option key={a.student_id} value={a.student_id}>{a.nome}</option>)}
          </select>
        </Field>
        <Field label="O que aconteceu"><textarea value={desc} onChange={(e) => setDesc(e.target.value)} rows={3} maxLength={600} className={`${inputCls} h-auto py-3`} /></Field>
        <Field label="Providência (se já houver)"><input value={prov} onChange={(e) => setProv(e.target.value)} maxLength={300} className={inputCls} /></Field>
      </div>
    </Sheet>
  );
}

function RemoverSheet({ alvo, onClose }: { alvo: any | null; onClose: () => void }) {
  const [motivo, setMotivo] = useState('');
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const recarregar = useRecarregarTransporte();
  const enviar = async () => {
    setBusy(true);
    try {
      await rpc('transporte_aluno_remover', { id: alvo.id, motivo });
      toast({ title: 'Aluno retirado da rota', tone: 'success' });
      recarregar();
      setMotivo('');
      onClose();
    } catch (e) {
      toast({ title: 'Não foi possível', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!alvo} onClose={onClose} title={`Retirar ${alvo?.nome ?? ''} da rota`} footer={<Button block size="lg" variant="danger" loading={busy} disabled={motivo.trim().length < 5} onClick={enviar}>Retirar</Button>}>
      <Field label="Motivo"><input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Ex.: mudou de endereço; transferido" className={inputCls} /></Field>
    </Sheet>
  );
}

/** Lista de embarque do dia (monitor): quem faltou na chamada ou avisou que não vai aparece marcado. */
export function Embarque() {
  const { id } = useParams();
  const [sp, setSp] = useSearchParams();
  const sentido = sp.get('sentido') === 'VOLTA' ? 'VOLTA' : 'IDA';
  const res = useRpc<any>('transporte_embarque', { rota_id: id, sentido });
  const { can } = useSession();
  const [marcas, setMarcas] = useState<Record<string, boolean>>({});
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const recarregar = useRecarregarTransporte();
  if (res.isLoading) return <SkeletonList rows={6} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  const d = res.data;
  const valor = (a: any) => marcas[a.student_id] ?? a.embarcou ?? (!a.aviso && !a.faltou);
  const salvar = async () => {
    setBusy(true);
    try {
      await rpc('transporte_embarque_registrar', { rota_id: id, sentido, registros: (d.alunos as any[]).map((a) => ({ student_id: a.student_id, embarcou: valor(a) })) });
      toast({ title: 'Embarque registrado', tone: 'success' });
      setMarcas({});
      recarregar();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  const embarcados = (d.alunos as any[]).filter(valor).length;
  return (
    <div className="mx-auto max-w-2xl">
      <PageHeader eyebrow={`Rota ${d.codigo} · ${d.unidade}`} title="Lista de embarque" subtitle={`${new Date(d.data + 'T12:00:00').toLocaleDateString('pt-BR')} · ${embarcados} de ${d.alunos.length} embarcando`}
        actions={<Segmented value={sentido} onChange={(v) => setSp({ sentido: v }, { replace: true })} items={[{ value: 'IDA', label: 'Ida' }, { value: 'VOLTA', label: 'Volta' }]} />} />
      <div className="mb-3"><EstadoViagem e={d.estado} /></div>
      <Card className="divide-y divide-line overflow-hidden">
        {(d.alunos as any[]).map((a) => {
          const v = valor(a);
          return (
            <label key={a.student_id} className={`flex cursor-pointer items-center gap-3 px-4 py-3 ${v ? '' : 'bg-slate-50'}`}>
              <input type="checkbox" className="size-5 accent-green-700" checked={v} disabled={!can('transporte.manage')} onChange={(e) => setMarcas({ ...marcas, [a.student_id]: e.target.checked })} />
              <span className="w-12 text-[12.5px] text-muted">{hm(a.horario)}</span>
              <span className="min-w-0 flex-1">
                <span className="block font-semibold">{a.nome}</span>
                <span className="block truncate text-[12.5px] text-muted">{a.ponto} · {a.turma}</span>
              </span>
              {a.aviso && <Badge tone="purple">Família avisou</Badge>}
              {a.faltou && <Badge tone="amber">Faltou na chamada</Badge>}
              {a.aee && <Badge tone="blue">AEE</Badge>}
            </label>
          );
        })}
        {!d.alunos.length && <EmptyState compact title="Nenhum aluno nesta rota" />}
      </Card>
      {d.pode_registrar && (
        <div className="sticky bottom-3 mt-3 flex justify-end">
          <Button icon={Flag} loading={busy} onClick={salvar}>Salvar embarque</Button>
        </div>
      )}
      <Link to={`/transporte/rotas/${id}`} className="mt-3 inline-block text-[13px] font-semibold text-blue-700">Voltar à rota</Link>
    </div>
  );
}
