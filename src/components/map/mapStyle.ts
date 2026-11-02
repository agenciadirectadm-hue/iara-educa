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
/** Contorno das áreas de ponderação sobre a camada de setores, e dos distritos (Iguatemi e Floriano, dentro da AP 001). */
export const REGION_LINE = '#4A1D7A';
export const DISTRICT_LINE = '#8C6A3F';
/** Setor com crianças de 0 a 4 anos em sigilo do IBGE. */
export const SIGILO_COLOR = '#CBD3DE';
export const SETOR_OPACITY = 0.72;

export type Stops = [number, string][];
/** Saldo (vagas ofertáveis − fila) por área de ponderação: do déficit severo à capacidade ociosa (faixas de api.dashboard_prefeito). */
export const BALANCE_STOPS: Stops = [[-40, '#D94C4C'], [-20, '#F28C38'], [-8, '#F2B640'], [0, '#9BD9B7'], [30, '#7FB7EA'], [80, '#2A7DE1']];
/** As 5 faixas de pressão (rótulos em PRESSURE, lib/labels) com a cor que a faixa tem no mapa. */
export const BALANCE_LEGEND = [
  { key: 'SEVERO', color: '#D94C4C' },
  { key: 'ALTO', color: '#F28C38' },
  { key: 'ATENCAO', color: '#F2B640' },
  { key: 'EQUILIBRIO', color: '#9BD9B7' },
  { key: 'OCIOSO', color: '#2A7DE1' },
] as const;
/** Fila e vagas por área de ponderação (demonstração, nov/2026: fila de 0 a 150, vagas de 0 a 218). */
export const QUEUE_REGION_STOPS: Stops = [[0, '#F4E9FC'], [40, '#D4A8F5'], [120, '#7A24C5']];
export const OFFERABLE_REGION_STOPS: Stops = [[0, '#E8F8F2'], [80, '#7DD3B0'], [180, '#008C72']];
/** Crianças de 0 a 4 anos (Censo 2022): por área de ponderação (291 a 1.649) e por setor censitário (mediana 25, máximo 157). */
export const CHILDREN_REGION_STOPS: Stops = [[0, '#FDF3E7'], [600, '#F7C58B'], [1100, '#E8833A'], [1600, '#B4501A']];
export const CHILDREN_SETOR_STOPS: Stops = [[0, '#FDF3E7'], [15, '#F9DDB5'], [30, '#F4B26B'], [50, '#E57B32'], [80, '#B4501A']];
export const HEAT_STOPS: Stops = [[0, 'rgba(42,125,225,0)'], [0.15, 'rgba(42,125,225,0.55)'], [0.35, '#16A36A'], [0.55, '#F2B640'], [0.75, '#F28C38'], [1, '#D94C4C']];
export const HEAT_OFFERABLE_STOPS: Stops = [[0, 'rgba(22,163,106,0)'], [0.25, 'rgba(22,163,106,0.5)'], [0.6, '#16A36A'], [1, '#086DB6']];

/** Expressão MapLibre de interpolação linear a partir de uma escala. */
export const interpolate = (input: unknown, stops: Stops) => ['interpolate', ['linear'], input, ...stops.flat()];
/** Gradiente CSS da escala (para a legenda); ignora a parada totalmente transparente do calor. */
export const cssGradient = (stops: Stops) =>
  `linear-gradient(90deg, ${stops.filter(([, c]) => !c.endsWith(',0)')).map(([, c]) => c).join(', ')})`;
