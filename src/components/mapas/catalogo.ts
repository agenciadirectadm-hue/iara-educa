/** Mapa unificado: a pessoa escolhe uma pergunta ("O que você quer saber?") e como ver ("Ver por": pontos, as 29 regiões
 * — áreas de ponderação do IBGE — ou as 793 microrregiões — setores censitários). Toda medida usa a mesma regra de cores
 * (semaforo.ts): vermelho = agir primeiro, amarelo = intermediário, verde = melhor, cinza = sem dado.
 * Pontos vêm das unidades (rede) ou de api.mapa_calor; regiões e microrregiões, de api.mapa_recorte. */
import { Baby, Bus, CalendarCheck, Contact, GraduationCap, NotebookPen, School, type LucideIcon } from 'lucide-react';
import type { HeatMode } from '@/components/map/MapView';
import type { Pior } from '@/components/map/semaforo';

export type Recorte = 'pontos' | 'area' | 'setor';
export const RECORTE_ROTULO: Record<Recorte, string> = { pontos: 'Pontos', area: 'Regiões', setor: 'Microrregiões' };
export const RECORTE_AJUDA: Record<Recorte, string> = {
  pontos: 'Cada escola, parada ou grupo de casas no mapa',
  area: 'As 29 regiões do IBGE (áreas de ponderação)',
  setor: 'As 793 microrregiões do IBGE (setores censitários, cerca de 300 casas cada)',
};

export type Quesito = {
  value: string;
  /** Nome curto (lista e legenda). */
  label: string;
  /** A pergunta, como aparece no seletor. */
  pergunta: string;
  /** Pergunta quando o recorte é região ou microrregião (se mudar o sentido: ex. presença pela casa do aluno). */
  perguntaRecorte?: string;
  recortes: Recorte[];
  /** De onde vêm os pontos: unidades da rede (MapView), api.mapa_calor, ou as linhas das rotas do transporte. */
  pontos?: 'rede' | 'calor' | 'rotas';
  /** Pontos da rede: mancha de calor das unidades. */
  heat?: HeatMode;
  /** Pontos da rede: cor da unidade pela vaga (verde com vaga, amarelo sem vaga e sem fila, vermelho sem vaga e com fila). */
  porVaga?: boolean;
  /** Onde fica o vermelho: "maior" (mais é pior) ou "menor" (menos é pior). Sem ele: só localização, cor neutra. */
  pior?: Pior;
  /** Como a legenda chama a ponta vermelha e a verde. */
  palavras?: { pior: string; melhor: string };
  fonte: 'oficial' | 'demo' | 'publico';
  /** Permissão extra (além da visão da rede) para ver o quesito. */
  perm?: string;
};
export type Tema = { value: string; label: string; icon: LucideIcon; publico: boolean; quesitos: Quesito[] };

const MAIS = (o: string) => ({ pior: `Mais ${o}`, melhor: `Menos ${o}` });
const MENOS = (o: string) => ({ pior: `Menos ${o}`, melhor: `Mais ${o}` });

export const TEMAS: Tema[] = [
  {
    value: 'rede', label: 'Rede e vagas', icon: School, publico: true, quesitos: [
      { value: 'deficit', label: 'Falta de vaga na creche', pergunta: 'Onde falta vaga de creche?', recortes: ['area', 'setor'], fonte: 'demo',
        pior: 'menor', palavras: { pior: 'Falta mais vaga', melhor: 'Falta menos vaga' } },
      { value: 'vagas', label: 'Vagas', pergunta: 'Onde há vagas sobrando?', recortes: ['pontos', 'area', 'setor'], pontos: 'rede', fonte: 'demo',
        heat: 'offerable', porVaga: true, pior: 'menor', palavras: MENOS('vagas') },
      { value: 'fila', label: 'Fila de espera', pergunta: 'Onde mais crianças esperam vaga?', recortes: ['pontos', 'area', 'setor'], pontos: 'rede', fonte: 'demo',
        heat: 'queue', pior: 'maior', palavras: MAIS('fila') },
      { value: 'matriculas', label: 'Alunos matriculados', pergunta: 'Onde estão os alunos matriculados?', recortes: ['pontos', 'area', 'setor'], pontos: 'rede', fonte: 'oficial',
        heat: 'enrollments', pior: 'maior', palavras: MAIS('alunos') },
      { value: 'unidades', label: 'Escolas e CMEIs', pergunta: 'Onde ficam as escolas e os CMEIs?', recortes: ['pontos', 'area', 'setor'], pontos: 'rede', fonte: 'publico',
        pior: 'menor', palavras: MENOS('unidades') },
    ],
  },
  {
    value: 'demanda', label: 'Crianças (Censo)', icon: Baby, publico: true, quesitos: [
      { value: 'criancas_0a4', label: 'Crianças de 0 a 4 anos', pergunta: 'Onde moram as crianças pequenas (0 a 4 anos)?', recortes: ['setor', 'area'], fonte: 'oficial',
        pior: 'maior', palavras: MAIS('crianças') },
      { value: 'pessoas', label: 'Moradores', pergunta: 'Onde mora mais gente?', recortes: ['setor', 'area'], fonte: 'oficial', pior: 'maior', palavras: MAIS('moradores') },
      { value: 'fila_casa', label: 'Fila pela casa', pergunta: 'Onde moram as crianças que esperam vaga?', recortes: ['area', 'setor'], fonte: 'demo', perm: 'kpi.network',
        pior: 'maior', palavras: MAIS('crianças esperando') },
    ],
  },
  {
    value: 'transporte', label: 'Transporte', icon: Bus, publico: false, quesitos: [
      { value: 'transporte_necessidade', label: 'Precisa de transporte', pergunta: 'Onde moram crianças longe da escola e sem transporte?', recortes: ['pontos', 'area', 'setor'],
        pontos: 'calor', fonte: 'demo', pior: 'maior', palavras: MAIS('crianças sem transporte') },
      { value: 'transporte_oferta', label: 'Transporte que já atende', pergunta: 'Onde o transporte escolar já atende mais alunos?', recortes: ['pontos', 'area', 'setor'],
        pontos: 'calor', fonte: 'demo', pior: 'menor', palavras: MENOS('alunos atendidos') },
      { value: 'transporte_efetividade', label: 'Rotas que cumprem', pergunta: 'Onde as rotas levam quem está previsto?', recortes: ['pontos', 'area', 'setor'],
        pontos: 'calor', fonte: 'demo', pior: 'menor', palavras: { pior: 'Cumpre menos', melhor: 'Cumpre mais' } },
      { value: 'transporte_veiculos', label: 'Veículos agora', pergunta: 'Onde estão os veículos agora?', recortes: ['pontos', 'area', 'setor'],
        pontos: 'calor', fonte: 'demo', pior: 'menor', palavras: MENOS('veículos') },
      { value: 'rotas', label: 'Rotas', pergunta: 'Por onde passam as rotas do transporte?', recortes: ['pontos'], pontos: 'rotas', fonte: 'demo', perm: 'transporte.read' },
    ],
  },
  {
    value: 'frequencia', label: 'Frequência', icon: CalendarCheck, publico: false, quesitos: [
      { value: 'faltas', label: 'Faltas', pergunta: 'Onde as crianças mais faltam?', recortes: ['pontos', 'area', 'setor'], pontos: 'calor', fonte: 'demo',
        pior: 'maior', palavras: MAIS('faltas') },
      { value: 'frequencia', label: 'Presença', pergunta: 'Quais escolas têm a presença mais baixa?', perguntaRecorte: 'Onde moram os alunos com a presença mais baixa?',
        recortes: ['pontos', 'area', 'setor'], pontos: 'calor', fonte: 'demo', pior: 'menor', palavras: MENOS('presença') },
      { value: 'ocorrencias', label: 'Ocorrências', pergunta: 'Onde há mais ocorrências com alunos?', perguntaRecorte: 'Onde moram os alunos com mais ocorrências?',
        recortes: ['pontos', 'area', 'setor'], pontos: 'calor', fonte: 'demo', pior: 'maior', palavras: MAIS('ocorrências') },
    ],
  },
  {
    value: 'alfabetizacao', label: 'Alfabetização', icon: NotebookPen, publico: false, quesitos: [
      { value: 'alfa_abaixo', label: 'Abaixo do esperado', pergunta: 'Onde há crianças abaixo do esperado na escrita?', recortes: ['pontos', 'area', 'setor'],
        pontos: 'calor', fonte: 'demo', pior: 'maior', palavras: MAIS('crianças abaixo') },
      { value: 'alfa_esperado', label: 'No nível esperado', pergunta: 'Onde as crianças estão no nível esperado para a idade?', recortes: ['pontos', 'area', 'setor'],
        pontos: 'calor', fonte: 'demo', pior: 'menor', palavras: MENOS('crianças no esperado') },
      { value: 'alfa_precoce', label: 'Adiantadas', pergunta: 'Onde há crianças que aprenderam antes do esperado?', recortes: ['pontos', 'area', 'setor'],
        pontos: 'calor', fonte: 'demo', pior: 'menor', palavras: MENOS('crianças adiantadas') },
    ],
  },
  {
    value: 'cadastros', label: 'Cadastros', icon: Contact, publico: false, quesitos: [
      { value: 'cadastros', label: 'Cadastros completos', pergunta: 'Onde faltam mais cadastros completos?', recortes: ['pontos', 'area', 'setor'],
        pontos: 'calor', fonte: 'demo', pior: 'menor', palavras: MENOS('cadastros completos') },
    ],
  },
  {
    value: 'formacao', label: 'Professores', icon: GraduationCap, publico: false, quesitos: [
      { value: 'formacao', label: 'Pós-graduação', pergunta: 'Onde há menos professores com pós-graduação?', recortes: ['pontos', 'area', 'setor'],
        pontos: 'calor', fonte: 'demo', pior: 'menor', palavras: MENOS('pós-graduados') },
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

/** Endereços antigos (?camada= do Mapa e dos Mapas de calor) → quesito novo. */
export const CAMADA_ANTIGA: Record<string, string> = { unidades: 'unidades', deficit: 'deficit', fila: 'fila', matriculas: 'matriculas', vagas: 'vagas', criancas: 'criancas_0a4', transporte: 'rotas' };

export function acharQuesito(temas: Tema[], q: string | null): { tema: Tema; quesito: Quesito } | null {
  for (const tema of temas) {
    const quesito = tema.quesitos.find((x) => x.value === q);
    if (quesito) return { tema, quesito };
  }
  return null;
}
