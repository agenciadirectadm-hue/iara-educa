// As três medidas de distância entre a residência e a unidade: linha reta, a pé (pela rota) e de carro (pela rota).
// O critério de proximidade da fila usa UMA delas (parâmetro da regra, por município) — e as três ficam sempre visíveis
// para a equipe, para a família e para o controle externo (Ministério Público, Defensoria).
import type { ReactNode } from 'react';
import { Link } from 'react-router';
import { keepPreviousData, useQuery } from '@tanstack/react-query';
import clsx from 'clsx';
import { Car, Check, Clock, Footprints, Loader2, Ruler, X } from 'lucide-react';
import { rotasCalcular, type DistanciaUnidade, type Distancias, type MedidaDistancia, type PedidoDistancias, type TrechoRota } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtKm } from '@/lib/format';
import { useExplain } from '@/components/overlays';
import { ROTA_COLOR, ROUTE_LINE } from '@/components/map/mapStyle';

export const MEDIDAS: MedidaDistancia[] = ['LINHA_RETA', 'A_PE', 'CARRO'];
export const MEDIDA: Record<MedidaDistancia, { rotulo: string; mini: string; curto: string; icone: typeof Ruler; cor: string; explica: string }> = {
  LINHA_RETA: {
    rotulo: 'Linha reta', mini: 'Reta', curto: 'em linha reta', icone: Ruler, cor: ROUTE_LINE,
    explica: 'Menor distância entre a casa e a unidade no mapa, sem considerar ruas, rios, rodovias ou a linha do trem.',
  },
  A_PE: {
    rotulo: 'A pé', mini: 'A pé', curto: 'a pé', icone: Footprints, cor: ROTA_COLOR.A_PE,
    explica: 'Trajeto mais curto caminhando pelas ruas, calçadas, passarelas e caminhos de pedestres. Tempo estimado a 5 km/h.',
  },
  CARRO: {
    rotulo: 'De carro', mini: 'Carro', curto: 'de carro', icone: Car, cor: ROTA_COLOR.CARRO,
    explica: 'Trajeto mais rápido de carro pelas vias, respeitando a mão de direção e as conversões permitidas. Tempo sem trânsito.',
  },
};
const CHAVE = { A_PE: 'a_pe', CARRO: 'carro' } as const;

export function fmtDuracao(s: number | null | undefined) {
  if (s == null) return '';
  const m = Math.max(1, Math.round(s / 60));
  if (m < 60) return `${m} min`;
  return `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, '0')} min`;
}

export const trecho = (u: DistanciaUnidade, m: Exclude<MedidaDistancia, 'LINHA_RETA'>): TrechoRota => u[CHAVE[m]];
const semRota = (t: TrechoRota) => !!t && 'sem_rota' in t && t.sem_rota === true;
/** Metros de uma unidade numa medida (null enquanto a rota não foi calculada). */
export function metros(u: DistanciaUnidade, m: MedidaDistancia): number | null {
  if (m === 'LINHA_RETA') return u.linha_reta_m;
  const t = trecho(u, m);
  return t && !semRota(t) ? (t as { distancia_m: number }).distancia_m : null;
}
const duracao = (u: DistanciaUnidade, m: MedidaDistancia) => {
  if (m === 'LINHA_RETA') return null;
  const t = trecho(u, m);
  return t && !semRota(t) ? (t as { duracao_s: number }).duracao_s : null;
};

function faltaCalcular(d: Distancias, alvo?: number | null, modo?: 'A_PE' | 'CARRO' | null) {
  if (d.unidades.some((u) => !u.a_pe || !u.carro)) return true;
  if (modo && d.unidades.some((u) => !d.trajetos?.[String(u.id)] && !semRota(trecho(u, modo)))) return true;
  const u = alvo != null ? d.unidades.find((x) => x.id === alvo) : null;
  return !!u && (['A_PE', 'CARRO'] as const).some((m) => !d.rotas?.[m] && !semRota(trecho(u, m)));
}

/**
 * Distâncias de um ponto às unidades: mostra na hora o que já está guardado (linha reta sempre) e pede ao gateway
 * as rotas que faltam (motor OSRM sobre o OpenStreetMap), que ficam guardadas para as próximas consultas.
 */
export function useDistancias(pedido: PedidoDistancias | null) {
  const { me } = useSession();
  const ok = !!pedido && Number.isFinite(pedido.lat) && Number.isFinite(pedido.lng);
  const base = useRpc<Distancias>('distancias', pedido ?? {}, { enabled: ok, staleTime: 5 * 60_000, placeholderData: keepPreviousData });
  const falta = !!base.data && faltaCalcular(base.data, pedido?.geometria_unidade, pedido?.geometrias_modo);
  const calc = useQuery({
    queryKey: ['rotas', pedido, me?.user_id ?? 'anon'],
    queryFn: () => rotasCalcular(pedido!),
    enabled: ok && falta,
    // se o motor falhou em alguma rota, a próxima visita tenta de novo
    staleTime: (q) => (q.state.data?.motor_indisponivel || q.state.data?.parcial ? 0 : 30 * 60_000),
    // resposta parcial (prazo do servidor): pede o restante em seguida, algumas vezes
    refetchInterval: (q) => (q.state.data?.parcial && q.state.dataUpdateCount < 6 ? 2_500 : false),
    retry: 1,
    placeholderData: keepPreviousData,
  });
  // enquanto calcula outro pedido, vale o que já está guardado para o pedido novo (nunca as rotas do pedido anterior)
  const calculado = calc.isPlaceholderData ? undefined : calc.data;
  return {
    data: calculado ?? base.data,
    isLoading: base.isLoading,
    error: base.error,
    calculando: calc.isFetching || !!calculado?.parcial,
    motorErro: calc.error ? (calc.error as Error).message : calc.data?.motor_indisponivel ?? null,
  };
}

/** Traçado de uma rota até uma unidade, para o mapa. */
export type Trajeto = { id: number; modo: 'A_PE' | 'CARRO'; coords: [number, number][] };

/** Traçados da medida escolhida no seletor (nenhum em linha reta, que o mapa desenha como reta pontilhada). */
export function trajetosDe(d: Distancias | undefined, medida: MedidaDistancia): Trajeto[] | null {
  if (!d || medida === 'LINHA_RETA' || d.trajetos_modo !== medida) return null;
  return Object.entries(d.trajetos ?? {}).filter(([, c]) => (c?.length ?? 0) > 1).map(([id, coords]) => ({ id: Number(id), modo: medida, coords }));
}

/** Pedido de traçados para a medida escolhida (linha reta não precisa de motor de rotas). */
export const modoTracado = (m: MedidaDistancia) => (m === 'LINHA_RETA' ? null : m);

/**
 * Seletor da medida mostrada no mapa e nas listas: linha reta (padrão), a pé ou de carro.
 * Vale para toda tela em que se procura ou se pede uma vaga.
 */
export function SeletorMedida({ value, onChange, carregando, className }: {
  value: MedidaDistancia; onChange: (m: MedidaDistancia) => void; carregando?: boolean; className?: string;
}) {
  return (
    <div role="radiogroup" aria-label="Como medir a distância" className={clsx('inline-flex max-w-full items-center gap-0.5 rounded-2xl bg-white p-1 shadow-soft ring-1 ring-line', className)}>
      {MEDIDAS.map((m) => {
        const I = MEDIDA[m].icone;
        const on = value === m;
        return (
          <button key={m} type="button" role="radio" aria-checked={on} onClick={() => onChange(m)} title={MEDIDA[m].explica}
            className={clsx('inline-flex h-9 shrink-0 items-center gap-1.5 rounded-xl px-2.5 text-[13px] font-semibold transition', on ? 'bg-purple-700 text-white shadow-sm' : 'text-ink-2 hover:bg-slate-100')}>
            {on && carregando && m !== 'LINHA_RETA' ? <Loader2 className="size-4 animate-spin" aria-hidden />
              : <I className="size-4" style={on ? undefined : { color: MEDIDA[m].cor }} aria-hidden />}
            {MEDIDA[m].rotulo}
          </button>
        );
      })}
    </div>
  );
}

/** Explicação da metodologia (as três medidas, o motor de rotas e qual medida o critério da fila usa). */
export function useComoMedimos() {
  const explain = useExplain();
  return (criterio?: Distancias['criterio'] | null, provedor?: string | null) =>
    explain({
      title: 'Como medimos a distância',
      body: [
        `${MEDIDA.LINHA_RETA.rotulo}: ${MEDIDA.LINHA_RETA.explica}`,
        `${MEDIDA.A_PE.rotulo}: ${MEDIDA.A_PE.explica}`,
        `${MEDIDA.CARRO.rotulo}: ${MEDIDA.CARRO.explica}`,
        `As rotas são calculadas pelas ruas do OpenStreetMap (mapa colaborativo, aberto e atualizado) com o motor OSRM${provedor ? ` (${provedor})` : ''}. Só a coordenada da casa e a da unidade vão para o motor de rotas — nunca nome, CPF ou endereço escrito.`,
        criterio
          ? `Critério da fila: "${criterio.regra}" (regras ${criterio.versao}) — até ${fmtKm(criterio.limite_m)}, medido ${MEDIDA[criterio.medida].curto}. As outras duas medidas ficam registradas na inscrição, para conferência.`
          : null,
        'A medida usada pelo critério é um parâmetro público da regra: a Secretaria pode simular o impacto e trocar, com justificativa registrada na auditoria.',
      ].filter(Boolean).join('\n\n'),
      kind: 'calculado',
    });
}

function Situacao({ m, limite }: { m: number | null; limite: number }) {
  if (m == null) return null;
  return m <= limite
    ? <span className="inline-flex items-center gap-0.5 text-green-700"><Check className="size-3.5" />até {fmtKm(limite)}</span>
    : <span className="inline-flex items-center gap-0.5 text-muted"><X className="size-3.5" />acima de {fmtKm(limite)}</span>;
}

/** Valor de uma medida: "4,0 km · 48 min", "calculando…", "sem rota" ou "—". */
export function ValorMedida({ u, m, calculando, comTempo = true }: { u: DistanciaUnidade; m: MedidaDistancia; calculando?: boolean; comTempo?: boolean }) {
  const v = metros(u, m);
  if (v == null) {
    if (m !== 'LINHA_RETA' && semRota(trecho(u, m))) return <span className="text-muted">sem rota</span>;
    return calculando ? <span className="inline-flex items-center gap-1 text-muted"><Loader2 className="size-3.5 animate-spin" />calculando</span> : <span className="text-muted">—</span>;
  }
  const t = duracao(u, m);
  return <span className="tabular">{fmtKm(v)}{comTempo && t != null && <span className="font-normal text-muted"> · {fmtDuracao(t)}</span>}</span>;
}

/**
 * As três medidas lado a lado. `blocos`: três quadros (fichas e telas de detalhe); `linha`: uma linha compacta (listas).
 * A medida do critério da fila aparece destacada, com o resultado frente ao limite.
 */
export function TresDistancias({ u, criterio, calculando, variante = 'blocos', destaque, onSelecionar, className }: {
  u: DistanciaUnidade; criterio?: Distancias['criterio'] | null; calculando?: boolean; variante?: 'blocos' | 'linha';
  /** medida escolhida no seletor: aparece em destaque (linha) ou marcada como a do mapa (blocos) */
  destaque?: MedidaDistancia;
  /** blocos clicáveis: escolher a medida mostrada no mapa */
  onSelecionar?: (m: MedidaDistancia) => void;
  className?: string;
}) {
  if (variante === 'linha') {
    return (
      <span className={clsx('inline-flex flex-wrap items-center gap-x-2.5 gap-y-0.5 text-[12.5px]', className)}>
        {MEDIDAS.map((m) => {
          const I = MEDIDA[m].icone;
          const crit = criterio?.medida === m;
          const enf = destaque ? destaque === m : crit;
          return (
            <span key={m} className={clsx('inline-flex items-center gap-1', enf ? 'font-semibold text-ink' : 'text-ink-2', destaque === m && 'rounded-full bg-purple-50 px-1.5 py-px ring-1 ring-purple-200')}
              title={`${MEDIDA[m].rotulo}${crit ? ' — medida usada pelo critério da fila' : ''}`}>
              <I className="size-3.5 shrink-0" style={{ color: MEDIDA[m].cor }} aria-label={MEDIDA[m].rotulo} />
              <ValorMedida u={u} m={m} calculando={calculando} comTempo={destaque === m} />
            </span>
          );
        })}
      </span>
    );
  }
  return (
    <div className={clsx('grid grid-cols-3 gap-2', className)}>
      {MEDIDAS.map((m) => {
        const I = MEDIDA[m].icone;
        const crit = criterio?.medida === m;
        const v = metros(u, m);
        const t = duracao(u, m);
        const sel = destaque === m;
        const cls = clsx('min-w-0 rounded-2xl p-2.5 text-left transition sm:p-3', crit ? 'bg-purple-50' : 'bg-slate-50',
          onSelecionar ? (sel ? 'ring-2 ring-purple-600 shadow-soft' : 'ring-1 ring-line/70 hover:ring-purple-300') : crit ? 'ring-2 ring-purple-300' : 'ring-1 ring-line/70');
        const conteudo = (
          <>
            <div className="flex items-center gap-1 text-[12px] font-bold text-ink-2 sm:gap-1.5 sm:text-[12.5px]">
              <I className="size-4 shrink-0" style={{ color: MEDIDA[m].cor }} aria-hidden />
              <span className="truncate sm:hidden">{MEDIDA[m].mini}</span>
              <span className="hidden truncate sm:inline">{MEDIDA[m].rotulo}</span>
            </div>
            <div className="mt-1 font-display text-[22px] font-black leading-none tabular sm:text-[26px]">
              {v != null ? fmtKm(v) : m !== 'LINHA_RETA' && semRota(trecho(u, m)) ? <span className="text-[15px] text-muted">sem rota</span>
                : calculando ? <Loader2 className="size-5 animate-spin text-subtle" aria-label="calculando" /> : <span className="text-muted">—</span>}
            </div>
            <div className="mt-1 min-h-[16px] text-[11.5px] leading-tight text-muted sm:text-[12px]">
              {m === 'LINHA_RETA' ? 'ignora as ruas' : t != null ? <span className="inline-flex items-center gap-1"><Clock className="size-3 shrink-0" aria-hidden />{fmtDuracao(t)}</span> : ''}
            </div>
            {crit && (
              <div className="mt-1.5 flex flex-wrap items-center gap-x-1.5 text-[11.5px] font-semibold">
                <span className="rounded-full bg-purple-700 px-1.5 py-px text-[10px] uppercase tracking-wide text-white">critério</span>
                <Situacao m={v} limite={criterio!.limite_m} />
              </div>
            )}
            {onSelecionar && (
              <div className={clsx('mt-1.5 text-[11px] font-semibold', sel ? 'text-purple-700' : 'text-subtle')}>{sel ? '● no mapa' : 'ver no mapa'}</div>
            )}
          </>
        );
        return onSelecionar ? (
          <button key={m} type="button" onClick={() => onSelecionar(m)} aria-pressed={sel} title={`Ver ${MEDIDA[m].curto} no mapa`} className={cls}>{conteudo}</button>
        ) : (
          <div key={m} className={cls}>{conteudo}</div>
        );
      })}
    </div>
  );
}

/** Distâncias já registradas na inscrição da fila (extrato do critério de proximidade). */
export type DistInscricao = { linha_reta_m: number | null; a_pe_m: number | null; carro_m: number | null };
export function distInscricao(breakdown: any[] | null | undefined): { d: DistInscricao; medida: MedidaDistancia; limite: number; provisoria: boolean } | null {
  const b = (breakdown ?? []).find((x) => x?.code === 'TERRITORIO_2KM');
  if (!b?.distancias) return null;
  return { d: b.distancias, medida: (b.medida ?? 'LINHA_RETA') as MedidaDistancia, limite: Number(b.max_m) || 2000, provisoria: !!b.provisoria };
}

/** Linha compacta com as três medidas registradas numa inscrição (sem chamar o motor de rotas). */
export function TresDistanciasInscricao({ breakdown, className, mostrarCriterio = true }: { breakdown: any[] | null | undefined; className?: string; mostrarCriterio?: boolean }) {
  const x = distInscricao(breakdown);
  if (!x) return null;
  const val: Record<MedidaDistancia, number | null> = { LINHA_RETA: x.d.linha_reta_m, A_PE: x.d.a_pe_m, CARRO: x.d.carro_m };
  return (
    <span className={clsx('inline-flex flex-wrap items-center gap-x-3 gap-y-0.5 text-[12.5px]', className)}>
      {MEDIDAS.map((m) => {
        const I = MEDIDA[m].icone;
        const crit = x.medida === m;
        const v = val[m];
        return (
          <span key={m} className={clsx('inline-flex items-center gap-1', crit && mostrarCriterio ? 'font-semibold text-ink' : 'text-ink-2')}
            title={`${MEDIDA[m].rotulo}${crit ? ' — medida usada pelo critério da fila' : ''}`}>
            <I className="size-3.5 shrink-0" style={{ color: MEDIDA[m].cor }} aria-label={MEDIDA[m].rotulo} />
            <span className="tabular">{v != null ? fmtKm(v) : '—'}</span>
            {crit && mostrarCriterio && v != null && (v <= x.limite ? <Check className="size-3.5 text-green-700" aria-label="dentro do limite" /> : <X className="size-3.5 text-subtle" aria-label="acima do limite" />)}
          </span>
        );
      })}
    </span>
  );
}

/** Link para a explicação pública da metodologia, na página de regras. */
export function LinkMetodologia({ className, children }: { className?: string; children?: ReactNode }) {
  return <Link to="/regras#distancia" className={clsx('font-semibold text-purple-700 underline-offset-2 hover:underline', className)}>{children ?? 'Como medimos a distância'}</Link>;
}
