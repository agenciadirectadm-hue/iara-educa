// Rótulos do Sprint 2 (pedagógico): avaliação, alfabetização, risco, AEE e declarações.
import type { Tone } from '@/lib/labels';

export const BIMESTRES = [1, 2, 3, 4] as const;

export const NIVEL_ALFA: Record<string, { label: string; curto: string; tone: Tone; cor: string }> = {
  PRE_SILABICO: { label: 'Pré-silábico', curto: 'Pré-sil.', tone: 'red', cor: '#ef4444' },
  SILABICO_SEM_VALOR: { label: 'Silábico sem valor sonoro', curto: 'Sil. s/ valor', tone: 'amber', cor: '#f59e0b' },
  SILABICO_COM_VALOR: { label: 'Silábico com valor sonoro', curto: 'Sil. c/ valor', tone: 'blue', cor: '#3b82f6' },
  SILABICO_ALFABETICO: { label: 'Silábico-alfabético', curto: 'Sil.-alfab.', tone: 'purple', cor: '#8b5cf6' },
  ALFABETICO: { label: 'Alfabético', curto: 'Alfabético', tone: 'green', cor: '#16a34a' },
};
export const NIVEIS = Object.keys(NIVEL_ALFA);
export const LEITURA: Record<string, string> = { NAO_LE: 'Ainda não lê', LE_PALAVRAS: 'Lê palavras', LE_FRASES: 'Lê frases', LE_TEXTOS: 'Lê textos' };
export const CICLO_ALFA: Record<string, string> = { DIAGNOSTICA: 'Diagnóstica', B1: '1º bimestre', B2: '2º bimestre', B3: '3º bimestre', B4: '4º bimestre' };

export const MOTIVO_RISCO: Record<string, { label: string; tone: Tone }> = {
  NOTAS: { label: 'Notas', tone: 'red' }, FREQUENCIA: { label: 'Frequência', tone: 'amber' },
  ALFABETIZACAO: { label: 'Alfabetização', tone: 'purple' }, OUTRO: { label: 'Outro', tone: 'gray' },
};
export const SITUACAO_PLANO: Record<string, { label: string; tone: Tone }> = {
  ATIVO: { label: 'Em andamento', tone: 'blue' }, SUPERADO: { label: 'Superado', tone: 'green' },
  ENCAMINHADO: { label: 'Encaminhado', tone: 'purple' }, ENCERRADO: { label: 'Encerrado', tone: 'gray' },
};

export const SITUACAO_AEE: Record<string, { label: string; tone: Tone }> = {
  EM_ELABORACAO: { label: 'Em elaboração', tone: 'amber' }, ATIVO: { label: 'Ativo', tone: 'green' },
  EM_REVISAO: { label: 'Em revisão', tone: 'purple' }, ENCERRADO: { label: 'Encerrado', tone: 'gray' },
};
export const MODALIDADE_AEE: Record<string, string> = {
  SRM_PROPRIA: 'Sala de recursos na própria escola', SRM_POLO: 'Sala de recursos em escola-polo',
  ITINERANTE: 'Professor(a) itinerante na unidade', DOMICILIAR: 'Atendimento domiciliar',
};
export const PRESENCA_AEE: Record<string, { label: string; tone: Tone }> = {
  PRESENTE: { label: 'Presente', tone: 'green' }, FALTA: { label: 'Faltou', tone: 'red' },
  FALTA_JUSTIFICADA: { label: 'Falta justificada', tone: 'amber' }, CANCELADO: { label: 'Cancelado', tone: 'gray' },
};
export const RECURSOS_AEE: Record<string, string> = {
  COMUNICACAO_ALTERNATIVA: 'Comunicação alternativa (pranchas, figuras)', LIBRAS: 'Libras (intérprete/instrutor)', BRAILLE: 'Braille e soroban',
  AMPLIACAO: 'Material ampliado e lupa', TECNOLOGIA_ASSISTIVA: 'Tecnologia assistiva', MOBILIARIO_ADAPTADO: 'Mobiliário adaptado e acessibilidade física',
  MEDIADOR: 'Profissional de apoio (mediador)', ENRIQUECIMENTO: 'Enriquecimento curricular', MATERIAL_CONCRETO: 'Material concreto e jogos',
  ROTINA_VISUAL: 'Rotina visual e antecipação', TEMPO_ESTENDIDO: 'Tempo estendido nas atividades',
};
export const DIAS_AEE: { value: string; label: string }[] = [
  { value: 'SEG', label: 'Seg' }, { value: 'TER', label: 'Ter' }, { value: 'QUA', label: 'Qua' }, { value: 'QUI', label: 'Qui' }, { value: 'SEX', label: 'Sex' },
];
export const DIA_AEE_LONGO: Record<string, string> = { SEG: 'segunda', TER: 'terça', QUA: 'quarta', QUI: 'quinta', SEX: 'sexta' };

export const TIPO_DECLARACAO: Record<string, { label: string; hint: string }> = {
  MATRICULA: { label: 'Declaração de matrícula', hint: 'Comprova que a criança estuda na rede (vale 90 dias).' },
  FREQUENCIA: { label: 'Declaração de frequência', hint: 'Percentual de presença no ano — usada no Bolsa Família e em benefícios (vale 30 dias).' },
  INSCRICAO_FILA: { label: 'Inscrição na fila de espera', hint: 'Comprova a inscrição na Central de Vagas (vale 30 dias).' },
  HISTORICO: { label: 'Histórico escolar', hint: 'Anos cursados, médias, frequência e resultado — para matrícula em outra escola.' },
};
export const SITUACAO_DECLARACAO: Record<string, { label: string; tone: Tone }> = {
  VALIDA: { label: 'Válida', tone: 'green' }, EXPIRADA: { label: 'Expirada', tone: 'gray' }, REVOGADA: { label: 'Revogada', tone: 'red' },
};

export const fmtNota = (n: number | string | null | undefined) => (n == null || n === '' ? '—' : Number(n).toFixed(1).replace('.', ','));
export const notaTone = (n: number | string | null | undefined, min = 6): Tone =>
  n == null || n === '' ? 'gray' : Number(n) < min ? 'red' : Number(n) < min + 1 ? 'amber' : 'green';
export const notaCor = (n: number | string | null | undefined, min = 6) =>
  n == null || n === '' ? 'text-subtle' : Number(n) < min ? 'text-red-700 font-bold' : Number(n) < min + 1 ? 'text-amber-700 font-semibold' : 'text-ink';

/** Endereço público de verificação (funciona no GitHub Pages e em produção, com hash router). */
export function urlVerificacao(codigo: string) {
  const base = `${window.location.origin}${window.location.pathname}`;
  return `${base}#/verificar/${codigo}`;
}
