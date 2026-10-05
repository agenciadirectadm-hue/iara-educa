// Quadro com as três medidas e as rotas desenhadas no mapa (separado para o mapa só carregar onde aparece).
import { useState, type ReactNode } from 'react';
import clsx from 'clsx';
import { Info, Route } from 'lucide-react';
import { useUnitsMap } from '@/lib/data';
import { fmtDateTime } from '@/lib/format';
import { Card } from '@/components/ui';
import MapView from '@/components/map/MapView';
import type { MedidaDistancia } from '@/lib/api';
import { MEDIDA, TresDistancias, modoTracado, trajetosDe, useComoMedimos, useDistancias } from '@/components/distancias';

/**
 * Quadro completo: as três medidas da residência até uma unidade, com as rotas desenhadas no mapa
 * (linha reta pontilhada, a pé tracejada em verde, de carro em azul) e a explicação da metodologia.
 */
export default function QuadroDistancias({ origem, unidadeId, titulo, homeLabel = 'Residência', unidadeLabel = 'Unidade', acao, mapa = true, className }: {
  origem: { lat: number; lng: number } | null | undefined;
  unidadeId: number;
  titulo?: ReactNode;
  homeLabel?: string;
  unidadeLabel?: string;
  acao?: ReactNode;
  mapa?: boolean;
  className?: string;
}) {
  const units = useUnitsMap();
  const comoMedimos = useComoMedimos();
  // o mapa mostra uma medida por vez: linha reta (padrão), a pé ou de carro — tocando nos quadros
  const [medida, setMedida] = useState<MedidaDistancia>('LINHA_RETA');
  const pedido = origem ? { lat: Number(origem.lat), lng: Number(origem.lng), unidades: [unidadeId], geometrias_modo: modoTracado(medida) } : null;
  const d = useDistancias(pedido);
  const u = d.data?.unidades.find((x) => x.id === unidadeId);
  const calculado = u && (u.a_pe as { calculado_em?: string } | null)?.calculado_em;
  return (
    <Card className={clsx('overflow-hidden', className)}>
      <div className="flex items-start gap-2 p-4 pb-3">
        <Route className="mt-0.5 size-5 shrink-0 text-purple-700" />
        <div className="min-w-0 flex-1">
          <div className="font-display text-[16px] font-extrabold leading-tight">{titulo ?? 'Distância até a unidade'}</div>
          {u && <div className="truncate text-[12.5px] text-muted">{u.nome}</div>}
        </div>
        <button type="button" onClick={() => comoMedimos(d.data?.criterio, d.data?.provedor)} className="inline-flex shrink-0 items-center gap-1 rounded-full px-2 py-1 text-[12px] font-semibold text-purple-700 hover:bg-purple-50">
          <Info className="size-3.5" />Como medimos
        </button>
      </div>
      <div className="px-4 pb-3">
        {!origem ? <p className="text-[13px] text-muted">Endereço sem coordenada: localize o endereço no cadastro para medir as distâncias.</p>
          : d.isLoading ? <div className="grid grid-cols-3 gap-2">{[0, 1, 2].map((i) => <div key={i} className="skeleton h-[92px] rounded-2xl" />)}</div>
          : d.error ? <p className="text-[13px] text-red-700">{d.error.message}</p>
          : u ? <TresDistancias u={u} criterio={d.data?.criterio} calculando={d.calculando} destaque={mapa ? medida : undefined} onSelecionar={mapa ? setMedida : undefined} /> : null}
        {d.motorErro && !d.calculando && <p className="mt-2 text-[12px] text-amber-800">Motor de rotas indisponível agora — a linha reta segue valendo; as rotas serão calculadas na próxima consulta.</p>}
      </div>
      {mapa && origem && (
        <MapView
          className="h-60"
          units={(units.data?.units ?? []).filter((x) => x.id === unidadeId)}
          home={{ lat: Number(origem.lat), lng: Number(origem.lng) }}
          highlight={[{ id: unidadeId, label: '★' }]}
          highlightLabel={unidadeLabel}
          homeLabel={homeLabel}
          lines={medida === 'LINHA_RETA'}
          trajetos={trajetosDe(d.data, medida)}
          fitKey={`${unidadeId}-${origem.lat}-${medida}-${trajetosDe(d.data, medida)?.length ?? 0}`}
          legendNote={medida === 'LINHA_RETA' ? 'Toque em “A pé” ou “De carro” para ver o caminho' : `Caminho ${MEDIDA[medida].curto} pelas ruas`}
          cooperative
          controls={false}
        />
      )}
      {(acao || calculado) && (
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 border-t border-line px-4 py-2 text-[11.5px] text-muted">
          {calculado && <span>Rotas: {d.data?.provedor ?? 'OSRM · OpenStreetMap'} · calculadas em {fmtDateTime(calculado)}</span>}
          {acao && <span className="ml-auto">{acao}</span>}
        </div>
      )}
    </Card>
  );
}

