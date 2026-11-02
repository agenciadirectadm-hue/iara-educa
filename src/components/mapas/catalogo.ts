/** Mapa unificado (Mapa + Mapas de calor): temas no topo, um quesito por pergunta e três recortes — pontos, as 29 áreas de
 * ponderação e os 793 setores censitários do IBGE. Pontos vêm das unidades (rede) ou de api.mapa_calor; áreas e setores,
 * de api.mapa_recorte. */
import { Baby, Bus, CalendarCheck, Contact, GraduationCap, NotebookPen, School, type LucideIcon } from 'lucide-react';
import type { ColorMode, HeatMode, RegionMetric } from '@/components/map/MapView';
import { BALANCE_STOPS, CHILDREN_REGION_STOPS, CHILDREN_SETOR_STOPS, type Stops } from '@/components/map/mapStyle';

export type Recorte = 'pontos' | 'area' | 'setor';
export const RECORTE_ROTULO: Record<Recorte, string> = { pontos: 'Pontos', area: 'Áreas', setor: 'Setores' };

export type Quesito = {
  value: string;
  label: string;
  pergunta: string;
  /** Pergunta quando o recorte é área ou setor (se mudar o sentido: ex. presença pela casa do aluno). */
  perguntaRecorte?: string;
  recortes: Recorte[];
  /** De onde vêm os pontos: unidades da rede (MapView), api.mapa_calor, ou as linhas das rotas do transporte. */
  pontos?: 'rede' | 'calor' | 'rotas';
  rede?: { heat?: HeatMode; regionMetric?: RegionMetric; colorMode?: ColorMode };
  fonte: 'oficial' | 'demo' | 'publico';
  /** Escala fixa (taxas e Censo); sem ela, a escala sai dos próprios valores (quartis). */
  escala?: Partial<Record<'area' | 'setor', Stops>>;
  /** Permissão extra (além da visão da rede) para ver o quesito. */
  perm?: string;
};
export type Tema = { value: string; label: string; icon: LucideIcon; publico: boolean; quesitos: Quesito[] };

const TAXA = (a: number, b: number, c: number, d: number, e: number): Stops => [[a, '#dc2626'], [b, '#f97316'], [c, '#facc15'], [d, '#22c55e'], [e, '#1d4ed8']];

export const TEMAS: Tema[] = [
  {
    value: 'rede', label: 'Rede e vagas', icon: School, publico: true, quesitos: [
      { value: 'deficit', label: 'Déficit de creche', pergunta: 'Onde falta vaga de creche?', recortes: ['area', 'setor'], fonte: 'demo',
        escala: { area: BALANCE_STOPS, setor: BALANCE_STOPS } },
      { value: 'unidades', label: 'Unidades', pergunta: 'Onde estão as unidades da rede?', recortes: ['pontos', 'area', 'setor'], pontos: 'rede', fonte: 'publico', rede: { colorMode: 'type' } },
      { value: 'vagas', label: 'Vagas', pergunta: 'Onde há vagas ofertáveis?', recortes: ['pontos', 'area', 'setor'], pontos: 'rede', fonte: 'demo', rede: { heat: 'offerable', colorMode: 'vacancy' } },
      { value: 'fila', label: 'Fila', pergunta: 'Onde se concentra a espera?', recortes: ['pontos', 'area', 'setor'], pontos: 'rede', fonte: 'demo', rede: { heat: 'queue' } },
      { value: 'matriculas', label: 'Matrículas', pergunta: 'Onde estão as matrículas?', recortes: ['pontos', 'area', 'setor'], pontos: 'rede', fonte: 'oficial', rede: { heat: 'enrollments' } },
    ],
  },
  {
    value: 'demanda', label: 'Demanda · Censo', icon: Baby, publico: true, quesitos: [
      { value: 'criancas_0a4', label: 'Crianças de 0 a 4 anos', pergunta: 'Onde moram as crianças de 0 a 4 anos (Censo 2022)?', recortes: ['setor', 'area'], fonte: 'oficial',
        escala: { area: CHILDREN_REGION_STOPS, setor: CHILDREN_SETOR_STOPS } },
      { value: 'pessoas', label: 'Moradores', pergunta: 'Onde moram as pessoas (Censo 2022)?', recortes: ['setor', 'area'], fonte: 'oficial' },
      { value: 'fila_casa', label: 'Fila pela casa', pergunta: 'Onde moram as crianças que esperam vaga?', recortes: ['area', 'setor'], fonte: 'demo', perm: 'kpi.network' },
    ],
  },
  {
    value: 'transporte', label: 'Transporte', icon: Bus, publico: false, quesitos: [
      { value: 'transporte_necessidade', label: 'Onde mais precisa', pergunta: 'Onde moram as crianças longe da escola e sem transporte?', recortes: ['pontos', 'area', 'setor'], pontos: 'calor', fonte: 'demo' },
      { value: 'transporte_oferta', label: 'Onde mais tem', pergunta: 'Onde o transporte escolar já atende mais alunos?', recortes: ['pontos', 'area', 'setor'], pontos: 'calor', fonte: 'demo' },
      { value: 'transporte_efetividade', label: 'Onde é mais efetivo', pergunta: 'Onde as rotas levam quem está previsto, no horário?', recortes: ['pontos', 'area', 'setor'], pontos: 'calor', fonte: 'demo',
        escala: { area: TAXA(70, 80, 88, 94, 100), setor: TAXA(70, 80, 88, 94, 100) } },
      { value: 'transporte_veiculos', label: 'Veículos agora', pergunta: 'Onde estão os veículos neste momento?', recortes: ['pontos', 'area', 'setor'], pontos: 'calor', fonte: 'demo' },
      { value: 'rotas', label: 'Rotas', pergunta: 'Por onde passam as rotas do transporte escolar?', recortes: ['pontos'], pontos: 'rotas', fonte: 'demo', perm: 'transporte.read' },
    ],
  },
  {
    value: 'frequencia', label: 'Frequência', icon: CalendarCheck, publico: false, quesitos: [
      { value: 'frequencia', label: 'Presença', pergunta: 'Quais escolas têm menor presença nos últimos 30 dias?', perguntaRecorte: 'Onde moram os alunos com menor presença (30 dias)?',
        recortes: ['pontos', 'area', 'setor'], pontos: 'calor', fonte: 'demo', escala: { area: TAXA(88, 91, 93, 95, 97), setor: TAXA(88, 91, 93, 95, 97) } },
      { value: 'faltas', label: 'Faltas pela casa', pergunta: 'Em que partes da cidade as faltas se concentram?', recortes: ['pontos', 'area', 'setor'], pontos: 'calor', fonte: 'demo' },
      { value: 'ocorrencias', label: 'Ocorrências', pergunta: 'Onde há mais ocorrências com alunos nos últimos 90 dias?', perguntaRecorte: 'Onde moram os alunos com mais ocorrências (90 dias)?',
        recortes: ['pontos', 'area', 'setor'], pontos: 'calor', fonte: 'demo' },
    ],
  },
  {
    value: 'alfabetizacao', label: 'Alfabetização', icon: NotebookPen, publico: false, quesitos: [
      { value: 'alfa_esperado', label: 'Na idade esperada', pergunta: 'Quantas crianças estão no nível de escrita esperado para a idade?', recortes: ['pontos', 'area', 'setor'], pontos: 'calor', fonte: 'demo',
        escala: { area: TAXA(65, 72, 78, 84, 90), setor: TAXA(65, 72, 78, 84, 90) } },
      { value: 'alfa_precoce', label: 'Precoces', pergunta: 'Onde estão as crianças que se alfabetizaram antes do esperado?', recortes: ['pontos', 'area', 'setor'], pontos: 'calor', fonte: 'demo' },
      { value: 'alfa_abaixo', label: 'Com defasagem', pergunta: 'Onde estão as crianças abaixo do esperado para a idade?', recortes: ['pontos', 'area', 'setor'], pontos: 'calor', fonte: 'demo' },
    ],
  },
  {
    value: 'cadastros', label: 'Cadastros', icon: Contact, publico: false, quesitos: [
      { value: 'cadastros', label: 'Cadastros completos', pergunta: 'Quanto falta para 100% dos cadastros completos?', recortes: ['pontos', 'area', 'setor'], pontos: 'calor', fonte: 'demo',
        escala: { area: TAXA(95, 96.5, 98, 99, 100), setor: TAXA(95, 96.5, 98, 99, 100) } },
    ],
  },
  {
    value: 'formacao', label: 'Formação', icon: GraduationCap, publico: false, quesitos: [
      { value: 'formacao', label: 'Pós-graduação', pergunta: 'Onde os professores têm mais e menos pós-graduação?', recortes: ['pontos', 'area', 'setor'], pontos: 'calor', fonte: 'demo',
        escala: { area: TAXA(25, 38, 50, 62, 75), setor: TAXA(25, 38, 50, 62, 75) } },
    ],
  },
];

/** Temas e quesitos que a pessoa pode ver: o público vê rede e Censo; a visão da rede (kpi.network) vê tudo. */
export function temasVisiveis(can: (perm: string) => boolean): Tema[] {
  const rede = can('kpi.network');
  return TEMAS.filter((t) => t.publico || rede)
    .map((t) => ({ ...t, quesitos: t.quesitos.filter((q) => !q.perm || can(q.perm)) }))
    .filter((t) => t.quesitos.length > 0);
}

/** Endereços antigos (?camada= do Mapa e dos Mapas de calor) → tema e quesito novos. */
export const CAMADA_ANTIGA: Record<string, string> = { unidades: 'unidades', deficit: 'deficit', fila: 'fila', matriculas: 'matriculas', vagas: 'vagas', criancas: 'criancas_0a4', transporte: 'rotas' };

export function acharQuesito(temas: Tema[], q: string | null): { tema: Tema; quesito: Quesito } | null {
  for (const tema of temas) {
    const quesito = tema.quesitos.find((x) => x.value === q);
    if (quesito) return { tema, quesito };
  }
  return null;
}

/** Escala pelos próprios valores: quartis (com o máximo no percentil 95), do claro ao escuro.
 * "maior é pior" vai para o vermelho; "menor é pior" (vagas, oferta), para o verde. */
export function escalaDosValores(valores: number[], pior: 'maior' | 'menor'): Stops {
  const v = valores.filter((x) => Number.isFinite(x)).sort((a, b) => a - b);
  const cores = pior === 'maior' ? ['#FEF3E2', '#FBC98A', '#F28C38', '#D94C4C', '#8E1B1B'] : ['#ECF8F2', '#A7E0C4', '#4CBF8B', '#16A36A', '#0A5F3E'];
  if (!v.length) return [[0, cores[0]], [1, cores[4]]];
  const q = (p: number) => v[Math.min(v.length - 1, Math.floor(p * (v.length - 1)))];
  const marcas = [v[0], q(0.25), q(0.5), q(0.75), q(0.95)];
  // paradas estritamente crescentes (a interpolação do MapLibre exige)
  const out: Stops = [];
  marcas.forEach((m, i) => {
    const anterior = out.length ? out[out.length - 1][0] : -Infinity;
    out.push([m > anterior ? m : anterior + 1e-6 * (i + 1), cores[i]]);
  });
  return out;
}
