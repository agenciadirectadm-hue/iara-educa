// Rótulos e semântica visual (cor + ícone + texto — nunca só cor; spec §8.2).
export type Tone = 'blue' | 'green' | 'purple' | 'amber' | 'red' | 'gray' | 'teal';

export const CASE_STATUS: Record<string, { label: string; tone: Tone }> = {
  NOVO: { label: 'Novo', tone: 'blue' },
  EM_ANALISE: { label: 'Em análise', tone: 'purple' },
  AGUARDANDO_DOCUMENTOS: { label: 'Aguardando documentos', tone: 'amber' },
  AGUARDANDO_FAMILIA: { label: 'Aguardando família', tone: 'amber' },
  VAGA_ENCONTRADA: { label: 'Vaga encontrada', tone: 'teal' },
  VAGA_OFERTADA: { label: 'Vaga ofertada', tone: 'green' },
  EM_FILA: { label: 'Na fila', tone: 'purple' },
  MATRICULA_CONCLUIDA: { label: 'Matrícula concluída', tone: 'green' },
  NAO_ATENDIDO: { label: 'Não atendido', tone: 'red' },
  RECURSO: { label: 'Recurso', tone: 'red' },
  ENCERRADO: { label: 'Encerrado', tone: 'gray' },
};
export const CASE_STATUS_ORDER = ['NOVO', 'EM_ANALISE', 'AGUARDANDO_DOCUMENTOS', 'AGUARDANDO_FAMILIA', 'VAGA_ENCONTRADA', 'VAGA_OFERTADA', 'RECURSO'];

export const QUEUE_CATEGORY: Record<string, { label: string; short: string; tone: Tone; hint: string }> = {
  SEM_ATENDIMENTO: { label: 'Sem atendimento', short: 'Sem atendimento', tone: 'red', hint: 'Criança sem nenhuma vaga na rede' },
  AGUARDA_TRANSFERENCIA: { label: 'Aguarda transferência', short: 'Transferência', tone: 'blue', hint: 'Já atendida; quer outra unidade' },
  PARCIAL_PARA_INTEGRAL: { label: 'Parcial → integral', short: 'Integral', tone: 'teal', hint: 'Atendida em meio período; pede integral' },
  UNIDADE_PREFERENCIAL: { label: 'Unidade preferencial', short: 'Preferencial', tone: 'purple', hint: 'Atendida; aguarda unidade preferida' },
  RECUSOU_OFERTA: { label: 'Recusou oferta', short: 'Recusou', tone: 'amber', hint: 'Recusou oferta e voltou à fila' },
  DEMANDA_FUTURA: { label: 'Demanda futura', short: 'Futura', tone: 'gray', hint: 'Ainda fora da idade de atendimento' },
};

export const QUEUE_CATEGORY_COLOR: Record<string, string> = {
  SEM_ATENDIMENTO: '#D94C4C', AGUARDA_TRANSFERENCIA: '#2A7DE1', PARCIAL_PARA_INTEGRAL: '#14B8A6', UNIDADE_PREFERENCIAL: '#A846E8', RECUSOU_OFERTA: '#F2B640', DEMANDA_FUTURA: '#94A3B8',
};

export const QUEUE_STATUS: Record<string, { label: string; tone: Tone }> = {
  WAITING: { label: 'Aguardando', tone: 'purple' },
  OFFERED: { label: 'Com oferta', tone: 'green' },
  ACCEPTED: { label: 'Aceitou', tone: 'teal' },
  DECLINED: { label: 'Recusou', tone: 'amber' },
  EXPIRED: { label: 'Expirou', tone: 'gray' },
  SUSPENDED: { label: 'Suspensa', tone: 'gray' },
  CANCELLED: { label: 'Cancelada', tone: 'gray' },
  MATRICULATED: { label: 'Matriculada', tone: 'green' },
};

export const FLAG: Record<string, { label: string; short: string }> = {
  IRMAO_NA_UNIDADE: { label: 'Irmão(ã) matriculado(a) na mesma unidade', short: 'Irmão' },
  CADUNICO: { label: 'Família de baixa renda no CadÚnico', short: 'CadÚnico' },
  TERRITORIO: { label: 'Reside até 2 km da unidade', short: 'Até 2 km' },
  MAE_SOLO: { label: 'Filho(a) de mãe solo', short: 'Mãe solo' },
  PCD_TEA_AEE: { label: 'PCD/TEA/TGD/AH-SD com laudo — prioridade sob análise', short: 'Laudo · análise' },
  VULNERABILIDADE: { label: 'Rede de proteção (regra anterior)', short: 'Proteção' },
};

export const OFFER_STATUS: Record<string, { label: string; tone: Tone }> = {
  OFFERED: { label: 'Aguardando resposta', tone: 'amber' },
  ACCEPTED: { label: 'Aceita — aguardando matrícula', tone: 'teal' },
  DECLINED: { label: 'Recusada', tone: 'gray' },
  EXPIRED: { label: 'Expirada', tone: 'gray' },
  CANCELLED: { label: 'Cancelada', tone: 'gray' },
  ENROLLED: { label: 'Matrícula concluída', tone: 'green' },
};

export const DOC: Record<string, string> = {
  CERTIDAO: 'Certidão de nascimento', CPF: 'CPF', RG: 'RG', COMPROVANTE_ENDERECO: 'Comprovante de endereço', CARTAO_SUS: 'Cartão SUS',
  VACINACAO: 'Carteira de vacinação', CADUNICO: 'Comprovante CadÚnico', DECLARACAO_TRABALHO: 'Declaração de trabalho', LAUDO: 'Laudo',
  GUARDA: 'Termo de guarda', DECISAO_JUDICIAL: 'Decisão judicial', TRANSFERENCIA: 'Declaração de transferência',
};
export const DOC_STATUS: Record<string, { label: string; tone: Tone }> = {
  PENDENTE: { label: 'Pendente', tone: 'amber' },
  NAO_ENVIADO: { label: 'Não enviado', tone: 'red' },
  RECEBIDO: { label: 'Recebido', tone: 'blue' },
  VALIDADO: { label: 'Validado', tone: 'green' },
  REJEITADO: { label: 'Rejeitado', tone: 'red' },
  VENCIDO: { label: 'Vencido', tone: 'gray' },
};

export const SHIFT: Record<string, string> = { MANHA: 'Manhã', TARDE: 'Tarde', NOITE: 'Noite', INTEGRAL: 'Integral' };
export const CHANNEL: Record<string, string> = {
  WEB: 'Portal', WHATSAPP: 'WhatsApp', PRESENCIAL: 'Presencial', TELEFONE: 'Telefone', EMAIL: 'E-mail', ESCOLA: 'Escola', CMEI: 'CMEI',
  CENTRAL_VAGAS: 'Central de Vagas', API: 'Integração', WHATSAPP_SIMULADO: 'WhatsApp (simulado)', PORTAL: 'Portal',
};
export const CONV_STATE: Record<string, { label: string; tone: Tone }> = {
  BOT_ACTIVE: { label: 'IARA atendendo', tone: 'purple' },
  HUMAN_PENDING: { label: 'Aguardando servidor', tone: 'amber' },
  HUMAN_ACTIVE: { label: 'Servidor atendendo', tone: 'green' },
  FOLLOWUP_PENDING: { label: 'Acompanhamento', tone: 'blue' },
  CLOSED: { label: 'Encerrada', tone: 'gray' },
};
export const BLOCK_REASON: Record<string, string> = {
  INCLUSAO: 'Inclusão', DECISAO_JUDICIAL: 'Decisão judicial', ADAPTACAO_SALA: 'Adaptação de sala', RESERVA_ADMINISTRATIVA: 'Reserva administrativa',
  REORGANIZACAO: 'Turma em reorganização', OBRA: 'Obra', AUSENCIA_PROFISSIONAL: 'Ausência de profissional', OUTRO: 'Outro',
};
export const VACANCY_EVENT: Record<string, string> = {
  MATRICULA: 'Matrícula', CANCELAMENTO: 'Cancelamento', TRANSF_SAIDA: 'Transferência de saída', TRANSF_ENTRADA: 'Transferência de entrada',
  BLOQUEIO: 'Bloqueio', DESBLOQUEIO: 'Desbloqueio', RESERVA: 'Reserva (oferta)', LIBERACAO: 'Liberação', ALTERACAO_CAPACIDADE: 'Alteração de capacidade',
  CORRECAO: 'Correção administrativa',
};
export const PRESSURE: Record<string, { label: string; tone: Tone; color: string }> = {
  SEVERO: { label: 'Déficit severo', tone: 'red', color: '#D94C4C' },
  ALTO: { label: 'Pressão alta', tone: 'amber', color: '#F28C38' },
  ATENCAO: { label: 'Atenção', tone: 'amber', color: '#F2B640' },
  EQUILIBRIO: { label: 'Equilíbrio', tone: 'green', color: '#16A36A' },
  OCIOSO: { label: 'Capacidade ociosa', tone: 'blue', color: '#2A7DE1' },
};
export const AUDIT_ACTION: Record<string, string> = {
  INSERT: 'Inclusão', UPDATE: 'Alteração', DELETE: 'Exclusão', OFFER_CREATED: 'Oferta registrada', OFFER_ACCEPTED: 'Aceite registrado',
  OFFER_DECLINED: 'Recusa registrada', OFFER_EXPIRED: 'Oferta expirada', ENROLLMENT_CONFIRMED: 'Matrícula confirmada', CASE_CREATED: 'Protocolo aberto',
  QUEUE_RECALCULATED: 'Fila recalculada', PRIORITY_FLAG: 'Critério de prioridade', VIEW_SENSITIVE: 'Consulta a dado sensível', EXPORT: 'Exportação',
  LOGIN_DEMO: 'Entrada no sistema', RULE_VERSION: 'Nova versão de regras', PRIORITY_DECISION: 'Prioridade sob análise (laudo)',
  FAMILY_REGISTERED: 'Cadastro de família', FAMILY_MEMBER_ADDED: 'Novo membro da família', FAMILY_UPDATED: 'Atualização de dados da família',
  ADDRESS_CHANGED: 'Mudança de endereço', QUEUE_SELF_REGISTER: 'Inscrição na fila on-line', QUEUE_WITHDRAWN: 'Desistência da fila', DEMO_SEED: 'Base de demonstração', DEMO_RESET: 'Reinício do cenário', DEMO_TIMESHIFT: 'Atualização temporal (demo)', WHATSAPP_CANAL: 'WhatsApp da IARA ligado/desligado', DEMO_PURGE: 'Limpeza da demonstração',
};
export const ENTITY: Record<string, string> = {
  students: 'Aluno', guardians: 'Responsável', addresses: 'Endereço', student_guardians: 'Vínculo', enrollments: 'Matrícula', classes: 'Turma',
  vacancy_blocks: 'Bloqueio de vaga', vacancy_offers: 'Oferta', waiting_list_entries: 'Fila', service_cases: 'Protocolo', documents: 'Documento',
  rules: 'Regra', conversations: 'Conversa', student_sensitive: 'Dado sensível', app_user: 'Usuário', report: 'Relatório', queue: 'Fila', demo: 'Demonstração',
};

export const TONE_CLASSES: Record<Tone, { bg: string; text: string; ring: string; dot: string; solid: string }> = {
  blue: { bg: 'bg-blue-100', text: 'text-blue-900', ring: 'ring-blue-200', dot: 'bg-blue-500', solid: 'bg-blue-700 text-white' },
  green: { bg: 'bg-green-100', text: 'text-green-800', ring: 'ring-green-200', dot: 'bg-green-500', solid: 'bg-green-700 text-white' },
  purple: { bg: 'bg-purple-100', text: 'text-purple-800', ring: 'ring-purple-200', dot: 'bg-purple-500', solid: 'bg-purple-700 text-white' },
  amber: { bg: 'bg-amber-100', text: 'text-amber-900', ring: 'ring-amber-200', dot: 'bg-amber-500', solid: 'bg-amber-500 text-ink' },
  red: { bg: 'bg-red-100', text: 'text-red-800', ring: 'ring-red-200', dot: 'bg-red-500', solid: 'bg-red-600 text-white' },
  gray: { bg: 'bg-slate-100', text: 'text-slate-700', ring: 'ring-slate-200', dot: 'bg-slate-400', solid: 'bg-slate-600 text-white' },
  teal: { bg: 'bg-teal-50', text: 'text-teal-800', ring: 'ring-teal-200', dot: 'bg-teal-500', solid: 'bg-teal-600 text-white' },
};

/** Equipe responsável por um protocolo (roteamento por alçada). */
export const TEAM: Record<string, string> = {
  CENTRAL_VAGAS: 'Central de Vagas (SEDUC)', SECRETARIA_ESCOLAR: 'Secretaria da unidade', TRANSPORTE: 'Gerência de Transporte Escolar',
  AEE: 'Inclusão e AEE', INTEGRAL: 'Gerência de Educação Integral', ALIMENTACAO: 'Merenda Escolar', OUVIDORIA: 'Ouvidoria',
  GESTAO: 'Diretoria de Gestão Educacional', ATENDIMENTO: 'Atendimento ao Cidadão',
};
/** Alçada de resolução: o que a IARA resolve na hora, o que a unidade decide e o que a SEDUC decide. */
export const LEVEL_LABEL: Record<string, { label: string; tone: Tone }> = {
  IARA: { label: 'Alçada da IARA (na hora)', tone: 'green' },
  UNIDADE: { label: 'Alçada da unidade', tone: 'blue' },
  SECRETARIA: { label: 'Alçada da SEDUC', tone: 'purple' },
};
