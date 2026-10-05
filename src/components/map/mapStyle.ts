/** Cores e escalas do mapa — usadas pelas camadas (MapView) e pela legenda (MapLegend), para as duas nunca divergirem. */

export const UNIT_COLOR = { CMEI: '#A846E8', ESCOLA: '#1594D2', VALIDAR: '#8A98AB' } as const;
export const VACANCY_COLOR = { vaga: '#16A36A', fila: '#D94C4C', neutro: '#8A98AB' } as const;
export const SELECTED_STROKE = '#0E1A2B';
/** Limite do município, áreas de influência, raio da residência e marcadores de ranking. */
export const PURPLE = '#7A24C5';
export const ROUTE_LINE = '#0E1A2B';
/** Rotas calculadas pelas ruas: a pé (tracejada) e de carro (contínua). */
export const ROTA_COLOR = { A_PE: '#0A8F5B', CARRO: '#1D6FD8' } as const;
export const REGION_OPACITY = 0.42;

export type Stops = [number, string][];
/** Saldo (vagas ofertáveis − fila) por região: do déficit severo à capacidade ociosa. */
export const BALANCE_STOPS: Stops = [[-250, '#D94C4C'], [-120, '#F28C38'], [-40, '#F2B640'], [0, '#9BD9B7'], [150, '#7FB7EA'], [400, '#2A7DE1']];
/** As 5 faixas de pressão (rótulos em PRESSURE, lib/labels) com a cor que a faixa tem no mapa. */
export const BALANCE_LEGEND = [
  { key: 'SEVERO', color: '#D94C4C' },
  { key: 'ALTO', color: '#F28C38' },
  { key: 'ATENCAO', color: '#F2B640' },
  { key: 'EQUILIBRIO', color: '#9BD9B7' },
  { key: 'OCIOSO', color: '#2A7DE1' },
] as const;
export const QUEUE_REGION_STOPS: Stops = [[0, '#F4E9FC'], [150, '#D4A8F5'], [450, '#7A24C5']];
export const OFFERABLE_REGION_STOPS: Stops = [[0, '#E8F8F2'], [250, '#7DD3B0'], [600, '#008C72']];
export const HEAT_STOPS: Stops = [[0, 'rgba(42,125,225,0)'], [0.15, 'rgba(42,125,225,0.55)'], [0.35, '#16A36A'], [0.55, '#F2B640'], [0.75, '#F28C38'], [1, '#D94C4C']];
export const HEAT_OFFERABLE_STOPS: Stops = [[0, 'rgba(22,163,106,0)'], [0.25, 'rgba(22,163,106,0.5)'], [0.6, '#16A36A'], [1, '#086DB6']];

/** Expressão MapLibre de interpolação linear a partir de uma escala. */
export const interpolate = (input: unknown, stops: Stops) => ['interpolate', ['linear'], input, ...stops.flat()];
/** Gradiente CSS da escala (para a legenda); ignora a parada totalmente transparente do calor. */
export const cssGradient = (stops: Stops) =>
  `linear-gradient(90deg, ${stops.filter(([, c]) => !c.endsWith(',0)')).map(([, c]) => c).join(', ')})`;
