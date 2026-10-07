// Rótulos dos módulos da vida escolar (Sprint 1): pessoal, frequência, cardápio, manutenção, mural e calendário.
import type { Tone } from './labels';

export const DIA_SEMANA = ['', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta'];
export const DIA_CURTO = ['', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex'];

export const FUNCAO_SERVIDOR: Record<string, string> = {
  PROFESSOR: 'Professor(a)', EDUCADOR: 'Educador(a) infantil', AEE: 'Professor(a) AEE', MEDIADOR: 'Mediador(a)',
  DIRETOR: 'Direção', COORDENADOR: 'Coordenação', SECRETARIO: 'Secretaria', APOIO: 'Apoio', AUXILIAR: 'Auxiliar',
};

export const RELATORIO_PESSOAL: { value: string; label: string; hint: string }[] = [
  { value: 'carga', label: 'Carga horária', hint: 'Aulas atribuídas × capacidade (2/3 da jornada em sala, Lei 11.738/2008)' },
  { value: 'sem_turma', label: 'Sem turma', hint: 'Professores e educadores sem nenhuma aula atribuída' },
  { value: 'horarios_sem_professor', label: 'Aulas sem professor', hint: 'Horários da grade ainda sem ninguém' },
  { value: 'choques', label: 'Choques de horário', hint: 'Mesmo servidor em duas turmas na mesma aula' },
  { value: 'mediadores', label: 'Mediação (AEE)', hint: 'Alunos do AEE e quem faz a mediação' },
  { value: 'curricular', label: 'Matriz curricular', hint: 'Aulas necessárias × atribuídas por componente' },
];

export const ALERTA_FREQ: Record<string, { label: string; tone: Tone }> = {
  AUSENCIA_CONSECUTIVA: { label: 'Faltas seguidas', tone: 'red' },
  FREQUENCIA_BAIXA: { label: 'Frequência abaixo do mínimo', tone: 'amber' },
};
export const SITUACAO_ALERTA: Record<string, { label: string; tone: Tone }> = {
  ABERTO: { label: 'Aberto', tone: 'red' },
  EM_ACOMPANHAMENTO: { label: 'Em acompanhamento', tone: 'amber' },
  RESOLVIDO: { label: 'Resolvido', tone: 'green' },
};
export const SITUACAO_JUSTIFICATIVA: Record<string, { label: string; tone: Tone }> = {
  ENVIADA: { label: 'Aguardando a escola', tone: 'amber' },
  ACEITA: { label: 'Aceita', tone: 'green' },
  RECUSADA: { label: 'Recusada', tone: 'red' },
};

export const REFEICAO: Record<string, string> = { DESJEJUM: 'Café da manhã', ALMOCO: 'Almoço', LANCHE: 'Lanche', JANTAR: 'Jantar' };
export const FAIXA_CARDAPIO: Record<string, string> = { CRECHE: 'Creche', PRE: 'Pré-escola', EF: 'Ensino fundamental' };
export const MOTIVO_RESTRICAO: Record<string, { label: string; tone: Tone }> = {
  ALERGIA: { label: 'Alergia', tone: 'red' },
  INTOLERANCIA: { label: 'Intolerância', tone: 'amber' },
  DOENCA: { label: 'Condição de saúde', tone: 'purple' },
  RELIGIOSO: { label: 'Religião', tone: 'blue' },
  OPCAO: { label: 'Opção da família', tone: 'teal' },
};
export const SITUACAO_RESTRICAO: Record<string, { label: string; tone: Tone }> = {
  INFORMADA: { label: 'Aguardando a nutrição', tone: 'amber' },
  VALIDADA: { label: 'Validada', tone: 'green' },
  RECUSADA: { label: 'Não validada', tone: 'gray' },
};

export const CATEGORIA_MANUTENCAO: Record<string, string> = {
  ELETRICA: 'Elétrica', HIDRAULICA: 'Hidráulica', TELHADO: 'Telhado e calhas', PINTURA: 'Pintura', MARCENARIA: 'Marcenaria',
  SERRALHERIA: 'Serralheria', JARDINAGEM: 'Jardinagem e roçada', CLIMATIZACAO: 'Climatização e ventilação', PLAYGROUND: 'Parque infantil',
  ACESSIBILIDADE: 'Acessibilidade', INFORMATICA: 'Rede e informática', OUTROS: 'Outros',
};
export const PRIORIDADE: Record<string, { label: string; tone: Tone; prazo: string }> = {
  URGENTE: { label: 'Urgente', tone: 'red', prazo: '24 horas' },
  ALTA: { label: 'Alta', tone: 'amber', prazo: '3 dias' },
  MEDIA: { label: 'Média', tone: 'blue', prazo: '10 dias' },
  BAIXA: { label: 'Baixa', tone: 'gray', prazo: '30 dias' },
};
export const SITUACAO_CHAMADO: Record<string, { label: string; tone: Tone; acao: string }> = {
  ABERTO: { label: 'Aberto', tone: 'blue', acao: 'Abrir' },
  TRIAGEM: { label: 'Em triagem', tone: 'purple', acao: 'Triar' },
  VISTORIA: { label: 'Vistoria', tone: 'purple', acao: 'Agendar vistoria' },
  ORCAMENTO: { label: 'Orçamento', tone: 'amber', acao: 'Pedir orçamento' },
  AGUARDANDO_EXECUCAO: { label: 'Aguardando execução', tone: 'amber', acao: 'Aprovar e programar' },
  EM_EXECUCAO: { label: 'Em execução', tone: 'teal', acao: 'Iniciar execução' },
  CONCLUIDO: { label: 'Concluído · a escola confere', tone: 'green', acao: 'Concluir' },
  VALIDADO: { label: 'Validado pela escola', tone: 'green', acao: 'Validar' },
  REABERTO: { label: 'Reaberto', tone: 'red', acao: 'Reabrir' },
  CANCELADO: { label: 'Cancelado', tone: 'gray', acao: 'Cancelar' },
};
export const EQUIPE: Record<string, string> = { EQUIPE_PROPRIA: 'Equipe da SEDUC', EMPRESA_CONTRATADA: 'Empresa contratada' };

export const TIPO_MURAL: Record<string, { label: string; tone: Tone }> = {
  AVISO: { label: 'Aviso', tone: 'blue' },
  COMUNICADO: { label: 'Comunicado', tone: 'purple' },
  EVENTO: { label: 'Evento', tone: 'teal' },
  ENQUETE: { label: 'Enquete', tone: 'amber' },
  CAMPANHA: { label: 'Campanha', tone: 'green' },
};
export const PUBLICO_MURAL: Record<string, string> = { FAMILIAS: 'Famílias', PROFISSIONAIS: 'Profissionais', TODOS: 'Todos' };

export const TIPO_CALENDARIO: Record<string, { label: string; tone: Tone }> = {
  FERIADO: { label: 'Feriado', tone: 'red' },
  RECESSO: { label: 'Recesso', tone: 'red' },
  INICIO_ANO: { label: 'Início do ano', tone: 'green' },
  FIM_ANO: { label: 'Fim do ano', tone: 'green' },
  FIM_BIMESTRE: { label: 'Fim de bimestre', tone: 'purple' },
  FORMACAO: { label: 'Formação', tone: 'blue' },
  REUNIAO_PAIS: { label: 'Reunião de pais', tone: 'amber' },
  CONSELHO_CLASSE: { label: 'Conselho de classe', tone: 'purple' },
  EVENTO: { label: 'Evento', tone: 'teal' },
  PRAZO: { label: 'Prazo', tone: 'gray' },
};

export const fmtReais = (n: number | null | undefined) =>
  n == null ? '—' : n.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });

/** Data ISO (aaaa-mm-dd) local, sem fuso: o dia letivo é o dia de Maringá. */
export function hojeISO() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
/** "seg., 05/10" a partir de aaaa-mm-dd (sem conversão de fuso). */
export function diaCurto(iso: string | null | undefined) {
  if (!iso) return '—';
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number);
  const dt = new Date(y, m - 1, d);
  return `${dt.toLocaleDateString('pt-BR', { weekday: 'short' })} ${String(d).padStart(2, '0')}/${String(m).padStart(2, '0')}`;
}
export function diaLongo(iso: string | null | undefined) {
  if (!iso) return '—';
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString('pt-BR', { weekday: 'long', day: '2-digit', month: 'long' });
}
export function pctTone(p: number | null | undefined, minimo = 75): Tone {
  if (p == null) return 'gray';
  if (p < minimo) return 'red';
  if (p < minimo + 10) return 'amber';
  return 'green';
}
