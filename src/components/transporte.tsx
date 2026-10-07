// Sprint 3: transporte escolar — rótulos, estado da viagem e a visão da família (só o ponto da criança e o veículo).
import { lazy, Suspense, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Bus, Clock, MapPin, ShieldAlert, UserRound } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useNow, useRpc } from '@/lib/hooks';
import type { Tone } from '@/lib/labels';
import { Badge, Button, Card, EmptyState, ErrorState, Field, Segmented, Skeleton, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';

const MapView = lazy(() => import('@/components/map/MapView'));

export const TIPO_VEICULO: Record<string, string> = { VAN: 'Van', MICRO: 'Micro-ônibus', ONIBUS: 'Ônibus' };
export const TIPO_OCORRENCIA_TR: Record<string, { label: string; tone: Tone }> = {
  ATRASO: { label: 'Atraso', tone: 'amber' }, QUEBRA: { label: 'Pane no veículo', tone: 'red' }, SUBSTITUICAO: { label: 'Veículo substituto', tone: 'purple' },
  ROTA_NAO_EXECUTADA: { label: 'Rota não executada', tone: 'red' }, ACIDENTE: { label: 'Acidente', tone: 'red' }, ALUNO_NAO_EMBARCOU: { label: 'Aluno não embarcou', tone: 'amber' },
  COMPORTAMENTO: { label: 'Comportamento', tone: 'blue' }, OUTRO: { label: 'Outro', tone: 'gray' },
};
export const MOTIVO_TRANSPORTE: Record<string, string> = { DISTANCIA: 'Distância', ZONA_RURAL: 'Zona rural', DEFICIENCIA: 'Deficiência', OUTRO: 'Outro' };
export const hm = (t?: string | null) => (t ? String(t).slice(0, 5) : '—');
export function somaMin(t: string | null | undefined, min: number) {
  if (!t) return '—';
  const [h, m] = String(t).split(':').map(Number);
  const x = h * 60 + m + (min || 0);
  return `${String(Math.floor(x / 60) % 24).padStart(2, '0')}:${String(x % 60).padStart(2, '0')}`;
}

/** "no seu ponto às" ou "passou no seu ponto às", pelo relógio de Brasília. */
export function noPonto(t: string | null | undefined, atraso: number) {
  const prev = somaMin(t, atraso);
  const agora = new Date().toLocaleTimeString('pt-BR', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit' });
  return agora > prev ? `passou no ponto ~${prev}` : `no ponto ~${prev}`;
}

export function useRecarregarTransporte() {
  const qc = useQueryClient();
  return () => ['transporte_painel', 'transporte_rota', 'transporte_embarque', 'transporte_sem_rota', 'transporte_ocorrencias', 'transporte_frota', 'familia_transporte']
    .forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
}

/** Situação da viagem (registrada ou simulada pelo horário). */
export function EstadoViagem({ e, compacto }: { e: any; compacto?: boolean }) {
  if (!e) return <span className="text-subtle">—</span>;
  const atraso = Number(e.atraso_min ?? 0);
  const m: Record<string, { label: string; tone: Tone }> = {
    PREVISTA: { label: `Prevista ${hm(e.inicio)}`, tone: 'gray' },
    EM_ANDAMENTO: { label: atraso >= 10 ? `A caminho · +${atraso} min` : 'A caminho', tone: atraso >= 10 ? 'amber' : 'blue' },
    CONCLUIDA: { label: atraso >= 10 ? `Concluída · +${atraso} min` : 'Concluída', tone: atraso >= 10 ? 'amber' : 'green' },
    NAO_REALIZADA: { label: 'Não realizada', tone: 'red' },
    SEM_AULA: { label: 'Sem aula', tone: 'gray' },
  };
  const x = m[e.situacao] ?? { label: e.situacao, tone: 'gray' as Tone };
  return (
    <span className="inline-flex items-center gap-1">
      <Badge tone={x.tone}>{x.label}</Badge>
      {!compacto && e.substituicao && <Badge tone="purple">Veículo reserva</Badge>}
      {!compacto && e.situacao === 'EM_ANDAMENTO' && e.proximo && <span className="text-[12px] text-muted">próx.: {e.proximo.nome} às {hm(e.proximo.previsto)}</span>}
    </span>
  );
}

/** Família: a rota de cada filho, o ponto, os horários de hoje, o veículo no mapa e o aviso de que não vai usar. */
export function TransporteFamilia() {
  useNow(30_000);
  const res = useRpc<any[]>('familia_transporte', {}, { refetchInterval: 30_000 });
  const [aviso, setAviso] = useState<any | null>(null);
  if (res.isLoading) return <SkeletonList rows={3} />;
  if (res.error) return <ErrorState error={res.error} onRetry={() => res.refetch()} />;
  if (!res.data?.length) {
    return <Card><EmptyState compact title="Suas crianças não usam o transporte escolar" body="Para pedir, use Protocolos → Transporte escolar ou diga à IARA “pedir transporte escolar”." /></Card>;
  }
  return (
    <div className="space-y-4">
      {res.data.map((k) => {
        const r = k.rota;
        if (!r) return <Card key={k.student_id} className="p-4"><b>{k.primeiro_nome}</b>: pedido de transporte em análise pela Gerência de Transporte Escolar.</Card>;
        const p = r.meu_ponto ?? {};
        const ida = r.hoje?.ida;
        const volta = r.hoje?.volta;
        const emCurso = [ida, volta].find((e) => e?.situacao === 'EM_ANDAMENTO');
        const pontos = [
          ...(p.lat ? [{ lat: p.lat, lng: p.lng, tipo: 'MEU_PONTO' as const, rotulo: '' }] : []),
          { lat: r.escola_lat, lng: r.escola_lng, tipo: 'ESCOLA' as const, rotulo: '' },
          ...(emCurso?.posicao ? [{ lat: emCurso.posicao.lat, lng: emCurso.posicao.lng, tipo: 'VEICULO' as const, rotulo: '' }] : []),
        ];
        return (
          <Card key={k.student_id} className="overflow-hidden">
            <div className="flex flex-wrap items-center gap-2 p-4">
              <Bus className="size-5 text-blue-700" />
              <span className="font-display text-[17px] font-extrabold">{k.primeiro_nome}</span>
              <Badge tone="blue">Rota {r.codigo}</Badge>
              <span className="text-[13px] text-muted">{TIPO_VEICULO[r.veiculo?.tipo] ?? ''} {r.veiculo?.placa}{r.veiculo?.acessivel ? ' · acessível' : ''} · motorista {r.motorista ?? '—'}{r.monitor ? ` · monitor(a) ${r.monitor}` : ''}</span>
            </div>
            <div className="grid grid-cols-1 gap-0 border-t border-line lg:grid-cols-[1fr_340px]">
              <Suspense fallback={<Skeleton className="h-64" />}>
                <MapView units={[]} pontos={pontos} focus={{ lat: emCurso?.posicao?.lat ?? p.lat ?? r.escola_lat, lng: emCurso?.posicao?.lng ?? p.lng ?? r.escola_lng, zoom: 14.2 }}
                  className="h-64 lg:h-72" legend={false} controls={false} cooperative />
              </Suspense>
              <div className="space-y-3 p-4 text-[14px]">
                <div className="flex items-start gap-2"><MapPin className="mt-0.5 size-4 text-purple-700" /><div><b>{p.nome ?? 'Ponto'}</b><div className="text-[12.5px] text-muted">ida às {hm(p.horario_ida)} · volta às {hm(p.horario_volta)} · chega à escola às {hm(r.chegada_escola)}</div></div></div>
                <div className="flex items-center gap-2"><Clock className="size-4 text-blue-700" /><span className="w-12 text-muted">Ida</span><EstadoViagem e={ida} compacto />
                  {ida?.situacao === 'EM_ANDAMENTO' && <span className="text-[12.5px]">{noPonto(p.horario_ida, ida.atraso_min)}</span>}</div>
                <div className="flex items-center gap-2"><Clock className="size-4 text-blue-700" /><span className="w-12 text-muted">Volta</span><EstadoViagem e={volta} compacto />
                  {volta?.situacao === 'EM_ANDAMENTO' && <span className="text-[12.5px]">{noPonto(p.horario_volta, volta.atraso_min)}</span>}</div>
                {[ida, volta].some((e) => e?.situacao === 'NAO_REALIZADA') && (
                  <p className="rounded-2xl bg-red-50 p-2 text-[12.5px] text-red-800">{[ida, volta].find((e) => e?.situacao === 'NAO_REALIZADA')?.motivo}. {ida?.situacao === 'NAO_REALIZADA' ? 'A falta de hoje fica abonada.' : ''}</p>
                )}
                {emCurso?.posicao && <p className="text-[11.5px] text-muted">{emCurso.posicao.fonte}. Atualizado agora.</p>}
                {(r.avisos as any[]).map((a) => <Badge key={a.data} tone="purple" icon={UserRound}>Não usa em {new Date(a.data + 'T12:00:00').toLocaleDateString('pt-BR')} ({a.sentido === 'AMBOS' ? 'ida e volta' : a.sentido.toLowerCase()})</Badge>)}
                <Button size="sm" variant="secondary" onClick={() => setAviso(k)}>Avisar que não vai usar</Button>
              </div>
            </div>
            {(r.recentes as any[]).length > 0 && (
              <div className="border-t border-line px-4 py-3 text-[12.5px] text-muted">
                <ShieldAlert className="mr-1 inline size-4 text-amber-600" />Últimos registros da rota: {(r.recentes as any[]).map((o) => `${new Date(o.data + 'T12:00:00').toLocaleDateString('pt-BR')} — ${o.descricao}`).join(' · ')}
              </div>
            )}
          </Card>
        );
      })}
      <p className="text-[12.5px] text-muted">Sem GPS integrado, a posição do veículo é estimada pelo horário planejado e pelo atraso registrado. Você vê só o ponto da sua criança. Pela IARA: “o ônibus já passou?”.</p>
      <AvisoSheet alvo={aviso} onClose={() => setAviso(null)} />
    </div>
  );
}

function AvisoSheet({ alvo, onClose }: { alvo: any | null; onClose: () => void }) {
  const hoje = new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Sao_Paulo' });
  const [data, setData] = useState(hoje);
  const [sentido, setSentido] = useState('AMBOS');
  const [motivo, setMotivo] = useState('');
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const recarregar = useRecarregarTransporte();
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('familia_transporte_avisar', { student_id: alvo.student_id, data, sentido, motivo });
      toast({ title: 'Aviso registrado', description: r.mensagem, tone: 'success' });
      recarregar();
      onClose();
    } catch (e) {
      toast({ title: 'Não registrado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!alvo} onClose={onClose} title={`${alvo?.primeiro_nome ?? ''} não vai usar o transporte`} subtitle="O monitor vê o aviso na lista de embarque e o veículo não espera no ponto."
      footer={<Button block size="lg" loading={busy} onClick={enviar}>Avisar</Button>}>
      <div className="space-y-3">
        <Field label="Quando"><input type="date" min={hoje} value={data} onChange={(e) => setData(e.target.value)} className={`${inputCls} h-11`} /></Field>
        <Segmented value={sentido} onChange={setSentido} items={[{ value: 'IDA', label: 'Ida' }, { value: 'VOLTA', label: 'Volta' }, { value: 'AMBOS', label: 'Ida e volta' }]} />
        <Field label="Motivo (opcional)"><input value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={200} placeholder="Ex.: vou buscar na escola" className={inputCls} /></Field>
      </div>
    </Sheet>
  );
}
