-- IARA Educa — 060 · Monitoramento de frequência, comunicação com responsáveis e busca ativa escolar (pedido de Rob, 07/10/2026)
-- Depois que o professor conclui a chamada, cada ausência sem justificativa ou afastamento gera um único contato com o responsável
-- no mesmo dia (WhatsApp da IARA e portal), com as opções de motivo. Sem resposta, a hierarquia segue: lembrete (24 h) e tarefa da
-- secretaria; atendimento humano (48 h ou 3 dias seguidos); busca ativa formal; rede de proteção (com validação humana); Conselho
-- Tutelar (expediente validado e enviado por servidor autorizado). Relato de risco fura a fila: alerta prioritário imediato.
-- Regras e prazos ficam num cadastro versionado (rede, etapa, gatilho, base normativa, vigência, contagem, aprovador, situação):
--   · contato no mesmo dia = diretriz operacional do projeto, validação documental pendente (Decreto Municipal nº 2.119/2025 e SEDUC);
--   · 24 h, 48 h e 3 dias = parâmetros operacionais propostos (a SEDUC altera, com registro de quem, quando e o fundamento);
--   · 5 consecutivos / 7 alternados em 60 dias = só opção de configuração, desligada e “proposta” (não é regra municipal confirmada);
--   · 30% do limite legal de faltas (LDB art. 12, VIII, “a”) = confirmado em lei, calculado pela carga horária e pela etapa
--     (fundamental 75% de frequência mínima — art. 24, VI; pré-escola 60% — art. 31, IV; creche sem limite legal);
--   · faltas reiteradas ou evasão após esgotadas as providências escolares (ECA, art. 56, II) = encaminhamento decidido pela equipe.
-- Sem resposta não gera Conselho Tutelar sozinho. Falha de entrega não é recusa da família: vira tarefa de conferir o telefone.
-- Justificativa aceita não apaga a ausência. Retorno à escola não encerra caso de risco: encerramento só com registro da equipe.
begin;

insert into iara.permissions (code, description, is_sensitive) values
  ('busca_ativa.read', 'Consultar ausências, contatos, tarefas e casos de busca ativa (a unidade só os seus)', true),
  ('busca_ativa.manage', 'Registrar contatos, concluir tarefas, classificar ausências e acompanhar casos de busca ativa', true),
  ('busca_ativa.aprovar', 'Aprovar encaminhamentos à rede de proteção e expedientes ao Conselho Tutelar', true),
  ('frequencia.parametros', 'Alterar o cadastro versionado de regras da frequência, os modelos de mensagem e os órgãos destinatários', false)
on conflict (code) do update set description = excluded.description, is_sensitive = excluded.is_sensitive;
insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('DIRETOR_UNIDADE', 'busca_ativa.read'), ('DIRETOR_UNIDADE', 'busca_ativa.manage'), ('DIRETOR_UNIDADE', 'busca_ativa.aprovar'),
  ('SECRETARIA_ESCOLAR', 'busca_ativa.read'), ('SECRETARIA_ESCOLAR', 'busca_ativa.manage'),
  ('SECRETARIO', 'busca_ativa.read'), ('SECRETARIO', 'busca_ativa.aprovar'), ('SECRETARIO', 'frequencia.parametros'),
  ('SUPERINTENDENCIA', 'busca_ativa.read'), ('SUPERINTENDENCIA', 'busca_ativa.manage'), ('SUPERINTENDENCIA', 'busca_ativa.aprovar'),
  ('SUPERINTENDENCIA', 'frequencia.parametros'), ('GERENCIA_EI', 'busca_ativa.read')
) v(r, p)
on conflict do nothing;

-- 1. Cadastro versionado de regras e modelos de mensagem ----------------------------------------------------------------------------
create table if not exists iara.frequencia_parametros (
  id uuid primary key default gen_random_uuid(),
  codigo text not null,
  nome text not null,
  rede text not null default 'MUNICIPAL' check (rede in ('MUNICIPAL', 'CONVENIADA', 'TODAS')),
  etapa text not null default 'TODAS' check (etapa in ('CRECHE', 'PRE', 'EF', 'TODAS')),
  gatilho text not null,
  valor numeric,
  unidade text,
  criterio_contagem text,
  base_normativa text,
  vigencia_inicio date not null default date '2026-01-01',
  vigencia_fim date,
  aprovador text,
  situacao text not null check (situacao in ('CONFIRMADO', 'PROPOSTO', 'PENDENTE_VALIDACAO')),
  ativo boolean not null default true,
  versao integer not null default 1,
  alterado_por_label text,
  alterado_em timestamptz not null default now(),
  fundamento_alteracao text,
  unique (codigo, rede, etapa, versao)
);
create table if not exists iara.frequencia_modelos (
  codigo text primary key,
  nome text not null,
  texto text not null,
  versao integer not null default 1,
  alterado_por_label text,
  alterado_em timestamptz not null default now()
);

insert into iara.frequencia_parametros (codigo, nome, etapa, gatilho, valor, unidade, criterio_contagem, base_normativa, aprovador, situacao, ativo) values
  ('CONTATO_MESMO_DIA', 'Primeiro contato no mesmo dia', 'TODAS', 'Primeira ausência sem justificativa ou afastamento, depois da chamada concluída', 0, 'horas',
   'Dispara só com a chamada da turma concluída; uma mensagem por responsável e dia (filhos ausentes juntos)',
   'Diretriz operacional do projeto. Validação documental: Decreto Municipal nº 2.119/2025 e orientações da SEDUC', 'SEDUC', 'PENDENTE_VALIDACAO', true),
  ('LEMBRETE_SEM_RESPOSTA', 'Lembrete ao responsável', 'TODAS', 'Sem resposta ao primeiro contato', 24, 'horas', 'Um lembrete e tarefa para a secretaria da unidade',
   'Parâmetro operacional proposto', 'SEDUC', 'PROPOSTO', true),
  ('ATENDIMENTO_SEM_RESPOSTA', 'Atendimento humano por falta de resposta', 'TODAS', 'Sem resposta depois do primeiro contato', 48, 'horas',
   'Alerta à equipe pedagógica e à direção; tarefa de telefonema, contato alternativo ou reunião', 'Parâmetro operacional proposto', 'SEDUC', 'PROPOSTO', true),
  ('ATENDIMENTO_CONSECUTIVAS', 'Atendimento humano por ausências seguidas', 'TODAS', 'Dias letivos consecutivos de ausência sem justificativa', 3, 'dias letivos',
   'Conta ausências aguardando esclarecimento ou injustificadas, em dias letivos seguidos', 'Parâmetro operacional proposto', 'SEDUC', 'PROPOSTO', true),
  ('BUSCA_ATIVA_SEM_SUCESSO', 'Busca ativa por contatos sem sucesso', 'TODAS', 'Atendimento humano sem resposta da família', 5, 'dias letivos',
   'Dias letivos depois do nível 3 sem retorno da família', 'Parâmetro operacional proposto', 'SEDUC', 'PROPOSTO', true),
  ('BUSCA_ATIVA_CONSECUTIVAS', 'Busca ativa: ausências consecutivas (opção)', 'TODAS', 'Ausências consecutivas sem justificativa', 5, 'dias letivos',
   'Opção de configuração; aplicação à rede municipal depende de aprovação da SEDUC', 'Não é regra municipal confirmada', 'SEDUC', 'PROPOSTO', false),
  ('BUSCA_ATIVA_ALTERNADAS', 'Busca ativa: ausências alternadas em 60 dias (opção)', 'TODAS', 'Ausências alternadas sem justificativa em 60 dias', 7, 'dias letivos',
   'Opção de configuração; aplicação à rede municipal depende de aprovação da SEDUC', 'Não é regra municipal confirmada', 'SEDUC', 'PROPOSTO', false),
  ('LIMITE_LEGAL_30', 'Faltas acima de 30% do limite legal', 'EF', 'Horas de ausência acima de 30% do limite legal de faltas', 30, '% do limite',
   'Limite = 25% da carga horária anual (frequência mínima de 75%); horas de ausência = dias ausentes × horas diárias do turno; conta toda ausência (justificada ou não)',
   'LDB, art. 12, VIII, “a”, e art. 24, VI (Lei 9.394/1996)', 'Lei federal', 'CONFIRMADO', true),
  ('LIMITE_LEGAL_30', 'Faltas acima de 30% do limite legal', 'PRE', 'Horas de ausência acima de 30% do limite legal de faltas', 30, '% do limite',
   'Limite = 40% da carga horária anual (frequência mínima de 60% na pré-escola); horas = dias ausentes × horas diárias do turno',
   'LDB, art. 12, VIII, “a”, e art. 31, IV (Lei 9.394/1996)', 'Lei federal', 'CONFIRMADO', true),
  ('FREQUENCIA_MINIMA', 'Frequência mínima legal', 'EF', 'Base do limite legal de faltas', 75, '%', 'Sobre o total de horas letivas', 'LDB, art. 24, VI', 'Lei federal', 'CONFIRMADO', true),
  ('FREQUENCIA_MINIMA', 'Frequência mínima legal', 'PRE', 'Base do limite legal de faltas', 60, '%', 'Sobre o total de horas', 'LDB, art. 31, IV', 'Lei federal', 'CONFIRMADO', true),
  ('CARGA_HORARIA_ANUAL', 'Carga horária anual', 'EF', 'Base do cálculo do limite legal', 800, 'horas', 'Mínimo legal; a rede pode ter mais', 'LDB, art. 24, I', 'Lei federal', 'CONFIRMADO', true),
  ('CARGA_HORARIA_ANUAL', 'Carga horária anual', 'PRE', 'Base do cálculo do limite legal', 800, 'horas', 'Mínimo legal', 'LDB, art. 31, II', 'Lei federal', 'CONFIRMADO', true),
  ('HORAS_DIA', 'Horas por dia letivo (turno parcial)', 'TODAS', 'Converte dias ausentes em horas', 4, 'horas', 'Turno parcial; o integral será configurado na matriz e jornada',
   'Parâmetro operacional proposto', 'SEDUC', 'PROPOSTO', true),
  ('ACOMPANHAMENTO_CRECHE', 'Creche: acompanhamento sem limite legal', 'CRECHE', 'Ausências seguidas na creche', 5, 'dias letivos',
   'Na creche não há frequência mínima legal: acompanhamento e apoio à família, sem notificação legal', 'Parâmetro operacional proposto', 'SEDUC', 'PROPOSTO', true),
  ('ECA_56_II', 'Faltas reiteradas ou evasão', 'TODAS', 'Faltas injustificadas reiteradas ou evasão, esgotadas as providências escolares', null, null,
   'Decisão da equipe, com providências documentadas no caso', 'ECA, art. 56, II (Lei 8.069/1990)', 'Lei federal', 'CONFIRMADO', true),
  ('APOIO_SAUDE_RECORRENTE', 'Apoio por ausências de saúde recorrentes', 'TODAS', 'Ausências informadas como saúde em 30 dias', 3, 'ausências',
   'Abaixo disso, só registro (sem tarefa)', 'Parâmetro operacional proposto', 'SEDUC', 'PROPOSTO', true),
  ('HORARIO_INICIO', 'Disparos: início do horário', 'TODAS', 'Mensagens comuns só dentro do horário', 8, 'hora', 'Urgentes seguem fluxo próprio', 'Parâmetro operacional proposto', 'SEDUC', 'PROPOSTO', true),
  ('HORARIO_FIM', 'Disparos: fim do horário', 'TODAS', 'Mensagens comuns só dentro do horário', 19, 'hora', 'Fora do horário, a mensagem fica agendada', 'Parâmetro operacional proposto', 'SEDUC', 'PROPOSTO', true),
  ('LEMBRETES_POR_DIA', 'Lembretes por dia', 'TODAS', 'Limite de lembretes comuns por responsável', 1, 'por dia', null, 'Parâmetro operacional proposto', 'SEDUC', 'PROPOSTO', true)
on conflict (codigo, rede, etapa, versao) do nothing;

insert into iara.frequencia_modelos (codigo, nome, texto) values
  ('NIVEL_1', 'Primeiro contato', 'Olá, {nome_responsavel}. Sou a IARA, assistente da Educação de Maringá. Identificamos que {nome_aluno} não compareceu hoje, {data}, à {unidade}. Está tudo bem? Informe o motivo da ausência para que possamos acompanhar e ajudar.'),
  ('NIVEL_2', 'Lembrete', 'Olá, {nome_responsavel}. Ainda não recebemos informação sobre a ausência de {nome_aluno} em {data}. Precisamos saber se está tudo bem e se a família precisa de apoio. Responda por aqui ou solicite contato com a equipe da {unidade}.'),
  ('NIVEL_3', 'Contato da equipe', 'Olá, {nome_responsavel}. A equipe da {unidade} precisa conversar sobre as ausências de {nome_aluno} e entender como podemos ajudar na continuidade das aulas. Escolha um horário para contato ou informe o melhor telefone.'),
  ('NIVEL_4', 'Busca ativa', 'Olá, {nome_responsavel}. Estamos acompanhando as ausências de {nome_aluno} e precisamos combinar medidas para seu retorno e permanência na escola. A equipe da {unidade} solicita contato para identificar as dificuldades e organizar o apoio necessário.'),
  ('REDE', 'Encaminhamento à rede de apoio (após aprovação)', 'Olá, {nome_responsavel}. Conforme avaliação da equipe e contato com a família, foi solicitado apoio de {servico} para auxiliar em {necessidade}. A escola continuará acompanhando {nome_aluno}.'),
  ('CORRECAO', 'Correção de chamada', 'Olá, {nome_responsavel}. Desconsidere a mensagem anterior: a presença de {nome_aluno} em {data} foi corrigida pela escola. Obrigado!')
on conflict (codigo) do nothing;

-- 2. Ausências, contatos, tarefas, casos e encaminhamentos ---------------------------------------------------------------------------
create table if not exists iara.frequencia_afastamentos (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references iara.students(id) on delete cascade,
  inicio date not null,
  fim date not null,
  motivo text not null,
  acompanhar_em date,
  registrado_por_label text,
  created_at timestamptz not null default now(),
  is_demo boolean not null default false
);
create table if not exists iara.frequencia_ausencias (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references iara.students(id) on delete cascade,
  class_id uuid references iara.classes(id) on delete set null,
  unit_id integer references iara.education_units(id),
  etapa text not null,
  data date not null,
  situacao text not null default 'AGUARDANDO_ESCLARECIMENTO' check (situacao in ('AGUARDANDO_ESCLARECIMENTO', 'MOTIVO_INFORMADO', 'JUSTIFICATIVA_EM_ANALISE',
    'JUSTIFICATIVA_ACEITA', 'INJUSTIFICADA', 'AFASTAMENTO', 'ERRO_CORRIGIDO')),
  motivo text check (motivo in ('SAUDE', 'CONSULTA', 'TRANSPORTE', 'DIFICULDADE_FAMILIAR', 'RECUSA', 'OUTRO', 'ESTA_NA_ESCOLA')),
  motivo_texto text,
  respondido_em timestamptz,
  respondido_canal text,
  nivel smallint not null default 1,
  risco boolean not null default false,
  acompanhar_em date,
  classificado_por_label text,
  created_at timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  is_demo boolean not null default false,
  unique (student_id, data)
);
create index if not exists frequencia_ausencias_unit_idx on iara.frequencia_ausencias (unit_id, situacao, data desc);
create table if not exists iara.frequencia_contatos (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid references iara.guardians(id) on delete set null,
  student_ids uuid[] not null,
  ausencia_ids uuid[] not null default '{}',
  unit_id integer,
  data_ref date not null,
  nivel text not null check (nivel in ('1', '2', '3', '4', 'REDE', 'CORRECAO')),
  canal text not null default 'WHATSAPP' check (canal in ('WHATSAPP', 'PORTAL')),
  texto text not null,
  status text not null default 'AGENDADA' check (status in ('AGENDADA', 'ENVIADA', 'SIMULADA', 'FALHA', 'CANCELADA', 'RESPONDIDA')),
  agendada_para timestamptz not null default now(),
  enviada_em timestamptz,
  falha_motivo text,
  notification_id uuid,
  chave text unique,
  created_at timestamptz not null default now(),
  is_demo boolean not null default false
);
create index if not exists frequencia_contatos_guardian_idx on iara.frequencia_contatos (guardian_id, data_ref);
create table if not exists iara.busca_ativa_casos (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references iara.students(id) on delete cascade,
  unit_id integer references iara.education_units(id),
  etapa text,
  origem text not null check (origem in ('PERSISTENCIA', 'CONTATOS_SEM_SUCESSO', 'LIMITE_LEGAL', 'RISCO', 'MANUAL')),
  motivo_abertura text not null,
  urgente boolean not null default false,
  situacao text not null default 'ABERTO' check (situacao in ('ABERTO', 'EM_ACOMPANHAMENTO', 'RETORNOU', 'ENCERRADO')),
  responsavel_label text,
  acompanhar_em date,
  aberto_em timestamptz not null default now(),
  encerrado_em timestamptz,
  encerramento_motivo text,
  resultado text,
  is_demo boolean not null default false
);
create unique index if not exists busca_ativa_caso_aberto on iara.busca_ativa_casos (student_id) where situacao <> 'ENCERRADO';
create table if not exists iara.busca_ativa_eventos (
  id uuid primary key default gen_random_uuid(),
  caso_id uuid not null references iara.busca_ativa_casos(id) on delete cascade,
  tipo text not null check (tipo in ('ABERTURA', 'CONTATO_TELEFONE', 'MENSAGEM', 'VISITA', 'REUNIAO', 'APOIO', 'ENCAMINHAMENTO', 'RETORNO', 'OBSERVACAO', 'ENCERRAMENTO')),
  texto text not null,
  autor_label text,
  created_at timestamptz not null default now(),
  is_demo boolean not null default false
);
create table if not exists iara.frequencia_tarefas (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references iara.students(id) on delete cascade,
  ausencia_id uuid references iara.frequencia_ausencias(id) on delete cascade,
  caso_id uuid references iara.busca_ativa_casos(id) on delete cascade,
  unit_id integer,
  tipo text not null check (tipo in ('LIGAR', 'CONFERIR_TELEFONE', 'CONFERIR_PRESENCA', 'REUNIAO', 'APOIO_SETOR', 'NOTIFICAR_CT', 'AVALIAR_RISCO', 'ENVIO_ALTERNATIVO')),
  prioridade text not null default 'NORMAL' check (prioridade in ('NORMAL', 'ALTA', 'URGENTE')),
  destino text not null check (destino in ('SECRETARIA_UNIDADE', 'EQUIPE_PEDAGOGICA', 'DIRECAO', 'SEDUC', 'TRANSPORTE')),
  descricao text not null,
  prazo date,
  obrigatoria boolean not null default false,
  situacao text not null default 'ABERTA' check (situacao in ('ABERTA', 'CONCLUIDA', 'CANCELADA')),
  sucesso boolean,
  resultado text,
  concluida_por_label text,
  concluida_em timestamptz,
  chave text unique,
  created_at timestamptz not null default now(),
  is_demo boolean not null default false
);
create index if not exists frequencia_tarefas_unit_idx on iara.frequencia_tarefas (unit_id, situacao, prioridade);
create table if not exists iara.orgaos_destinatarios (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  tipo text not null check (tipo in ('CONSELHO_TUTELAR', 'CRAS', 'CREAS', 'SAUDE', 'TRANSPORTE_ESCOLAR', 'ASSISTENCIA_SOCIAL', 'OUTRO')),
  competencia text,
  territorio_ids integer[] not null default '{}',
  canal text not null check (canal in ('PROTOCOLO_ELETRONICO', 'EMAIL_INSTITUCIONAL', 'INTEGRACAO')),
  endereco_canal text,
  verificado boolean not null default false,
  verificado_por_label text,
  verificado_em timestamptz,
  ativo boolean not null default true,
  is_demo boolean not null default false
);
create table if not exists iara.encaminhamentos (
  id uuid primary key default gen_random_uuid(),
  caso_id uuid references iara.busca_ativa_casos(id) on delete cascade,
  student_id uuid not null references iara.students(id) on delete cascade,
  unit_id integer,
  tipo text not null check (tipo in ('REDE_APOIO', 'CONSELHO_TUTELAR')),
  orgao_id uuid references iara.orgaos_destinatarios(id) on delete set null,
  servico text,
  necessidade text,
  fundamento text not null,
  obrigatorio boolean not null default false,
  conteudo jsonb,
  situacao text not null default 'AGUARDANDO_APROVACAO' check (situacao in ('AGUARDANDO_APROVACAO', 'APROVADO', 'ENVIADO', 'FALHA_ENVIO', 'RECEBIDO', 'RETORNO_REGISTRADO', 'CANCELADO')),
  comunicar_familia boolean not null default false,
  criado_por_label text,
  created_at timestamptz not null default now(),
  aprovado_por_label text,
  aprovado_em timestamptz,
  enviado_em timestamptz,
  enviado_canal text,
  protocolo text,
  recebido_em timestamptz,
  retorno_texto text,
  retorno_em timestamptz,
  cancelamento_motivo text,
  is_demo boolean not null default false
);
create index if not exists encaminhamentos_unit_idx on iara.encaminhamentos (unit_id, situacao);

alter table iara.frequencia_parametros enable row level security;
alter table iara.frequencia_modelos enable row level security;
alter table iara.frequencia_afastamentos enable row level security;
alter table iara.frequencia_ausencias enable row level security;
alter table iara.frequencia_contatos enable row level security;
alter table iara.busca_ativa_casos enable row level security;
alter table iara.busca_ativa_eventos enable row level security;
alter table iara.frequencia_tarefas enable row level security;
alter table iara.orgaos_destinatarios enable row level security;
alter table iara.encaminhamentos enable row level security;

-- 3. Apoios ---------------------------------------------------------------------------------------------------------------------
create or replace function iara.etapa_freq(p_grade text) returns text
language sql immutable as $$ select case when p_grade = 'CRECHE' then 'CRECHE' when p_grade = 'PRE' then 'PRE' else 'EF' end $$;

-- valor vigente de um parâmetro (a versão ativa mais nova; a específica da etapa vence a geral)
create or replace function iara.fparam(p_codigo text, p_etapa text default 'TODAS') returns numeric
language sql stable security definer set search_path = iara, public
as $$
  select valor from iara.frequencia_parametros
  where codigo = p_codigo and ativo and etapa in (p_etapa, 'TODAS') and vigencia_inicio <= iara.hoje_local() and (vigencia_fim is null or vigencia_fim >= iara.hoje_local())
  order by (etapa = p_etapa) desc, versao desc limit 1
$$;

create or replace function iara.modelo_msg(p_codigo text, p_vars jsonb) returns text
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  t text := (select texto from iara.frequencia_modelos where codigo = p_codigo);
  k text;
begin
  for k in select jsonb_object_keys(p_vars) loop
    t := replace(t, '{' || k || '}', coalesce(p_vars ->> k, ''));
  end loop;
  return t;
end $$;

create or replace function iara.ba_acesso_unidade(p_unit integer) returns boolean
language sql stable security definer set search_path = iara, public
as $$ select iara.has_perm('busca_ativa.read') and (iara.my_scope() = 'NETWORK' or iara.can_access_unit(p_unit)) $$;

-- responsável que recebe: o principal com notificações ligadas (senão, o primeiro que recebe)
create or replace function iara.responsavel_contato(p_student uuid) returns uuid
language sql stable security definer set search_path = iara, public
as $$
  select guardian_id from iara.student_guardians where student_id = p_student and end_date is null and coalesce(can_receive_notifications, true)
  order by is_primary desc nulls last, start_date nulls last limit 1
$$;

-- envia (ou agenda) um contato: portal sempre; WhatsApp pela fila do canal quando o responsável tem contato vinculado.
-- Sem canal vinculado: na demonstração, envio simulado (uma pequena parte falha, para mostrar a tarefa de conferir o telefone);
-- na produção, falha de entrega → tarefa de contato alternativo (nunca é tratada como recusa da família).
create or replace function iara.ba_enviar(p_contato uuid) returns text
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.frequencia_contatos;
  v_ini integer := coalesce(iara.fparam('HORARIO_INICIO'), 8);
  v_fim integer := coalesce(iara.fparam('HORARIO_FIM'), 19);
  v_hora integer := extract(hour from iara.agora_local());
  v_notif uuid;
  v_out uuid;
  v_status text;
begin
  select * into c from iara.frequencia_contatos where id = p_contato for update;
  if c.id is null or c.status <> 'AGENDADA' then return c.status; end if;
  if c.nivel not in ('CORRECAO') and (v_hora < v_ini or v_hora >= v_fim) then
    update iara.frequencia_contatos set agendada_para = case when v_hora >= v_fim then (iara.hoje_local() + 1)::timestamp else iara.hoje_local()::timestamp end
                                        + make_interval(hours => v_ini) at time zone 'America/Sao_Paulo' where id = c.id;
    return 'AGENDADA';
  end if;
  insert into iara.notifications (tenant_id, guardian_id, student_id, channel, event_type, title, body, status)
  values (1, c.guardian_id, c.student_ids[1], 'PORTAL', 'FREQUENCIA_' || c.nivel,
          case c.nivel when 'CORRECAO' then 'Presença corrigida' when 'REDE' then 'Apoio à família' else 'Ausência na escola' end, c.texto, 'ENVIADA')
  returning id into v_notif;
  insert into iara.whatsapp_outbox (channel_id, contact_id, telefone_e164, jid, texto, origem, ref_id)
  select w.channel_id, w.id, w.telefone_e164, w.jid, c.texto, 'NOTIFICACAO', v_notif
  from iara.whatsapp_contacts w join iara.whatsapp_channels ch on ch.id = w.channel_id
  where w.guardian_id = c.guardian_id and ch.ativo order by w.ultima_em desc limit 1
  returning id into v_out;
  v_status := case when v_out is not null then 'ENVIADA'
                   when iara.demo_mode() and abs(hashtext(c.id::text)) % 100 >= 4 then 'SIMULADA'
                   else 'FALHA' end;
  update iara.frequencia_contatos set status = v_status, enviada_em = now(), notification_id = v_notif,
         falha_motivo = case when v_status = 'FALHA' then 'Número sem WhatsApp ou canal oficial indisponível' end
  where id = c.id;
  return v_status;
end $$;

-- 4. Motor: novas ausências, primeiro contato, níveis, limite legal, falhas e agendados ------------------------------------------------
create or replace function iara.busca_ativa_processar(p_class uuid default null, p_data date default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_hoje date := iara.hoje_local();
  v_dia date := coalesce(p_data, v_hoje);
  x record;
  v_c uuid;
  v_n_novas integer := 0;
  v_n_contatos integer := 0;
  v_n_nivel integer := 0;
  v_n_legal integer := 0;
  v_caso uuid;
begin
  -- A. ausências de chamadas concluídas (lançadas ao vivo) do dia: classifica e cria a ocorrência
  insert into iara.frequencia_ausencias (student_id, class_id, unit_id, etapa, data, situacao, motivo, is_demo)
  select f.student_id, r.class_id, c.unit_id, iara.etapa_freq(gl.code), r.data,
         case when f.tipo = 'FALTA_JUSTIFICADA' then 'JUSTIFICATIVA_ACEITA'
              when exists (select 1 from iara.frequencia_justificativas j where j.student_id = f.student_id and j.data = r.data and j.situacao = 'ACEITA') then 'JUSTIFICATIVA_ACEITA'
              when exists (select 1 from iara.frequencia_justificativas j where j.student_id = f.student_id and j.data = r.data and j.situacao = 'ENVIADA') then 'JUSTIFICATIVA_EM_ANALISE'
              when exists (select 1 from iara.frequencia_afastamentos a where a.student_id = f.student_id and r.data between a.inicio and a.fim) then 'AFASTAMENTO'
              else 'AGUARDANDO_ESCLARECIMENTO' end,
         case when exists (select 1 from iara.transporte_abonos ab where ab.student_id = f.student_id and ab.data = r.data) then 'TRANSPORTE' end,
         false
  from iara.frequencia_registros r join iara.frequencia_faltas f on f.registro_id = r.id
  join iara.classes c on c.id = r.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
  where not r.is_demo and r.data = v_dia and (p_class is null or r.class_id = p_class)
  on conflict (student_id, data) do update set situacao = case when iara.frequencia_ausencias.situacao = 'ERRO_CORRIGIDO' then excluded.situacao else iara.frequencia_ausencias.situacao end,
    atualizado_em = now();
  get diagnostics v_n_novas = row_count;
  -- chamada corrigida: a falta saiu → erro corrigido, contato pendente cancelado, e correção a quem já recebeu
  for x in select a.* from iara.frequencia_ausencias a
           where not a.is_demo and a.data = v_dia and (p_class is null or a.class_id = p_class) and a.situacao <> 'ERRO_CORRIGIDO'
             and exists (select 1 from iara.frequencia_registros r where r.class_id = a.class_id and r.data = a.data)
             and not exists (select 1 from iara.frequencia_faltas f join iara.frequencia_registros r on r.id = f.registro_id
                             where f.student_id = a.student_id and r.data = a.data) loop
    update iara.frequencia_ausencias set situacao = 'ERRO_CORRIGIDO', atualizado_em = now() where id = x.id;
    update iara.frequencia_contatos set status = 'CANCELADA' where status = 'AGENDADA' and x.id = any (ausencia_ids);
    update iara.frequencia_tarefas set situacao = 'CANCELADA', resultado = 'Chamada corrigida' where ausencia_id = x.id and situacao = 'ABERTA' and not obrigatoria;
    if exists (select 1 from iara.frequencia_contatos where x.id = any (ausencia_ids) and status in ('ENVIADA', 'SIMULADA', 'RESPONDIDA')) then
      insert into iara.frequencia_contatos (guardian_id, student_ids, ausencia_ids, unit_id, data_ref, nivel, texto, chave)
      values (iara.responsavel_contato(x.student_id), array[x.student_id], array[x.id], x.unit_id, x.data, 'CORRECAO',
              iara.modelo_msg('CORRECAO', jsonb_build_object('nome_responsavel', split_part((select full_name from iara.guardians where id = iara.responsavel_contato(x.student_id)), ' ', 1),
                'nome_aluno', split_part((select full_name from iara.students where id = x.student_id), ' ', 1), 'data', to_char(x.data, 'DD/MM'))),
              'corr:' || x.id)
      on conflict (chave) do nothing returning id into v_c;
      if v_c is not null then perform iara.ba_enviar(v_c); end if;
    end if;
  end loop;

  -- B. primeiro contato: um por responsável e dia (filhos ausentes juntos), só com a chamada concluída
  for x in select iara.responsavel_contato(a.student_id) g, a.data, array_agg(a.student_id order by s.full_name) alunos, array_agg(a.id order by s.full_name) ids,
                  string_agg(split_part(s.full_name, ' ', 1), ' e ' order by s.full_name) nomes, min(a.unit_id) unit_id,
                  case when count(distinct a.unit_id) = 1 then min(u.short_name) else 'escola' end unidade
           from iara.frequencia_ausencias a join iara.students s on s.id = a.student_id join iara.education_units u on u.id = a.unit_id
           where not a.is_demo and a.data = v_dia and a.situacao = 'AGUARDANDO_ESCLARECIMENTO' and a.nivel = 1 and (p_class is null or a.class_id = p_class)
             and not exists (select 1 from iara.frequencia_contatos k where a.id = any (k.ausencia_ids) and k.nivel = '1')
             and iara.responsavel_contato(a.student_id) is not null
           group by 1, 2 loop
    insert into iara.frequencia_contatos (guardian_id, student_ids, ausencia_ids, unit_id, data_ref, nivel, texto, chave)
    values (x.g, x.alunos, x.ids, x.unit_id, x.data, '1',
            iara.modelo_msg('NIVEL_1', jsonb_build_object('nome_responsavel', split_part((select full_name from iara.guardians where id = x.g), ' ', 1),
              'nome_aluno', x.nomes, 'data', to_char(x.data, 'DD/MM'), 'unidade', x.unidade)), 'n1:' || x.g || ':' || x.data)
    on conflict (chave) do update set ausencia_ids = (select array_agg(distinct v) from unnest(iara.frequencia_contatos.ausencia_ids || excluded.ausencia_ids) v),
      student_ids = (select array_agg(distinct v) from unnest(iara.frequencia_contatos.student_ids || excluded.student_ids) v)
    returning id into v_c;
    perform iara.ba_enviar(v_c);
    v_n_contatos := v_n_contatos + 1;
  end loop;

  -- C. níveis 2 a 4 para quem não respondeu (só lançamentos ao vivo; a demonstração já vem com o histórico)
  for x in select a.*, (select min(k.enviada_em) from iara.frequencia_contatos k where a.id = any (k.ausencia_ids) and k.nivel = '1' and k.status in ('ENVIADA', 'SIMULADA', 'RESPONDIDA', 'FALHA')) envio1,
                  (select count(*) from iara.frequencia_ausencias b where b.student_id = a.student_id and b.data between a.data - 6 and a.data
                     and b.situacao in ('AGUARDANDO_ESCLARECIMENTO', 'INJUSTIFICADA')) seguidas
           from iara.frequencia_ausencias a
           where not a.is_demo and a.situacao = 'AGUARDANDO_ESCLARECIMENTO' and a.data >= v_hoje - 20 and (p_class is null or a.class_id = p_class) loop
    if x.nivel < 3 and (x.envio1 < now() - make_interval(hours => coalesce(iara.fparam('ATENDIMENTO_SEM_RESPOSTA'), 48)::int)
                        or x.seguidas >= coalesce(iara.fparam('ATENDIMENTO_CONSECUTIVAS', x.etapa), 3)) then
      update iara.frequencia_ausencias set nivel = 3, atualizado_em = now() where id = x.id;
      insert into iara.frequencia_tarefas (student_id, ausencia_id, unit_id, tipo, prioridade, destino, descricao, prazo, chave)
      values (x.student_id, x.id, x.unit_id, 'REUNIAO', 'ALTA', 'EQUIPE_PEDAGOGICA',
              'Sem resposta da família ou ausências seguidas: telefonar, usar o contato alternativo ou marcar reunião (com a direção ciente).', v_hoje + 2, 'n3:' || x.student_id || ':' || x.data)
      on conflict (chave) do nothing;
      if not exists (select 1 from iara.frequencia_contatos k where k.guardian_id = iara.responsavel_contato(x.student_id) and k.nivel in ('2', '3', '4') and k.enviada_em >= iara.hoje_local()::timestamp) then
        insert into iara.frequencia_contatos (guardian_id, student_ids, ausencia_ids, unit_id, data_ref, nivel, texto, chave)
        values (iara.responsavel_contato(x.student_id), array[x.student_id], array[x.id], x.unit_id, x.data, '3',
                iara.modelo_msg('NIVEL_3', jsonb_build_object('nome_responsavel', split_part((select full_name from iara.guardians where id = iara.responsavel_contato(x.student_id)), ' ', 1),
                  'nome_aluno', split_part((select full_name from iara.students where id = x.student_id), ' ', 1),
                  'unidade', (select short_name from iara.education_units where id = x.unit_id))), 'n3m:' || x.student_id || ':' || x.data)
        on conflict (chave) do nothing returning id into v_c;
        if v_c is not null then perform iara.ba_enviar(v_c); end if;
      end if;
      v_n_nivel := v_n_nivel + 1;
    elsif x.nivel < 2 and x.envio1 < now() - make_interval(hours => coalesce(iara.fparam('LEMBRETE_SEM_RESPOSTA'), 24)::int) then
      update iara.frequencia_ausencias set nivel = 2, atualizado_em = now() where id = x.id;
      insert into iara.frequencia_tarefas (student_id, ausencia_id, unit_id, tipo, prioridade, destino, descricao, prazo, chave)
      values (x.student_id, x.id, x.unit_id, 'LIGAR', 'NORMAL', 'SECRETARIA_UNIDADE', 'Família sem resposta ao primeiro contato: ligar para o responsável.', v_hoje + 1,
              'n2:' || x.student_id || ':' || x.data)
      on conflict (chave) do nothing;
      if not exists (select 1 from iara.frequencia_contatos k where k.guardian_id = iara.responsavel_contato(x.student_id) and k.nivel in ('2', '3', '4') and k.enviada_em >= iara.hoje_local()::timestamp) then
        insert into iara.frequencia_contatos (guardian_id, student_ids, ausencia_ids, unit_id, data_ref, nivel, texto, chave)
        values (iara.responsavel_contato(x.student_id), array[x.student_id], array[x.id], x.unit_id, x.data, '2',
                iara.modelo_msg('NIVEL_2', jsonb_build_object('nome_responsavel', split_part((select full_name from iara.guardians where id = iara.responsavel_contato(x.student_id)), ' ', 1),
                  'nome_aluno', split_part((select full_name from iara.students where id = x.student_id), ' ', 1), 'data', to_char(x.data, 'DD/MM'),
                  'unidade', (select short_name from iara.education_units where id = x.unit_id))), 'n2m:' || x.student_id || ':' || x.data)
        on conflict (chave) do nothing returning id into v_c;
        if v_c is not null then perform iara.ba_enviar(v_c); end if;
      end if;
      v_n_nivel := v_n_nivel + 1;
    end if;
    -- nível 4: nível 3 sem sucesso por N dias letivos (ou as opções 5 seguidas / 7 alternadas, se a SEDUC ligar)
    if x.nivel >= 3 and not exists (select 1 from iara.busca_ativa_casos k where k.student_id = x.student_id and k.situacao <> 'ENCERRADO')
       and (x.data <= v_hoje - coalesce(iara.fparam('BUSCA_ATIVA_SEM_SUCESSO'), 5)::int
            or x.seguidas >= coalesce(iara.fparam('BUSCA_ATIVA_CONSECUTIVAS', x.etapa), 999)
            or (select count(*) from iara.frequencia_ausencias b where b.student_id = x.student_id and b.data >= v_hoje - 60
                  and b.situacao in ('AGUARDANDO_ESCLARECIMENTO', 'INJUSTIFICADA')) >= coalesce(iara.fparam('BUSCA_ATIVA_ALTERNADAS', x.etapa), 999)) then
      insert into iara.busca_ativa_casos (student_id, unit_id, etapa, origem, motivo_abertura, acompanhar_em)
      values (x.student_id, x.unit_id, x.etapa, 'CONTATOS_SEM_SUCESSO', 'Ausências persistentes e contatos sem sucesso depois do atendimento humano.', v_hoje + 3)
      returning id into v_caso;
      insert into iara.busca_ativa_eventos (caso_id, tipo, texto, autor_label) values (v_caso, 'ABERTURA', 'Caso aberto pela regra de persistência (parâmetros vigentes).', 'IARA (regra automática)');
      insert into iara.frequencia_tarefas (student_id, caso_id, unit_id, tipo, prioridade, destino, descricao, prazo, chave)
      values (x.student_id, v_caso, x.unit_id, 'REUNIAO', 'ALTA', 'DIRECAO', 'Busca ativa aberta: organizar contato, visita ou reunião com a família e registrar no caso.', v_hoje + 3, 'n4:' || v_caso);
      update iara.frequencia_ausencias set nivel = 4, atualizado_em = now() where student_id = x.student_id and situacao = 'AGUARDANDO_ESCLARECIMENTO';
      insert into iara.frequencia_contatos (guardian_id, student_ids, ausencia_ids, unit_id, data_ref, nivel, texto, chave)
      values (iara.responsavel_contato(x.student_id), array[x.student_id], array[x.id], x.unit_id, x.data, '4',
              iara.modelo_msg('NIVEL_4', jsonb_build_object('nome_responsavel', split_part((select full_name from iara.guardians where id = iara.responsavel_contato(x.student_id)), ' ', 1),
                'nome_aluno', split_part((select full_name from iara.students where id = x.student_id), ' ', 1),
                'unidade', (select short_name from iara.education_units where id = x.unit_id))), 'n4m:' || v_caso)
      on conflict (chave) do nothing returning id into v_c;
      if v_c is not null then perform iara.ba_enviar(v_c); end if;
    end if;
  end loop;

  -- D. falha de entrega → tarefa de conferir o telefone (nunca é recusa da família)
  insert into iara.frequencia_tarefas (student_id, unit_id, tipo, prioridade, destino, descricao, prazo, chave, is_demo)
  select k.student_ids[1], k.unit_id, 'CONFERIR_TELEFONE', 'ALTA', 'SECRETARIA_UNIDADE',
         'A mensagem não foi entregue (' || coalesce(k.falha_motivo, 'falha') || '). Conferir o telefone no cadastro e usar o contato alternativo autorizado.', v_hoje + 1,
         'tel:' || k.id, k.is_demo
  from iara.frequencia_contatos k where k.status = 'FALHA' and k.created_at >= now() - interval '7 days'
  on conflict (chave) do nothing;

  -- E. agendados que chegaram no horário
  for x in select id from iara.frequencia_contatos where status = 'AGENDADA' and agendada_para <= now() limit 200 loop
    perform iara.ba_enviar(x.id);
  end loop;
  return jsonb_build_object('ausencias', v_n_novas, 'contatos', v_n_contatos, 'niveis', v_n_nivel, 'legal', v_n_legal);
end $$;

-- limite legal (LDB art. 12, VIII, “a”): horas de ausência acima de 30% do limite → tarefa obrigatória e expediente ao Conselho Tutelar
-- (em lote; o expediente completo é montado na aprovação, com os dados do dia)
create or replace function iara.busca_ativa_limite_legal(p_unit integer default null) returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_n integer := 0;
  v_ano integer := extract(year from iara.hoje_local());
begin
  with par as (
    select e etapa, coalesce(iara.fparam('HORAS_DIA', e), 4) h,
           coalesce(iara.fparam('CARGA_HORARIA_ANUAL', e), 800) * (100 - coalesce(iara.fparam('FREQUENCIA_MINIMA', e), case e when 'PRE' then 60 else 75 end)) / 100 limite,
           coalesce(iara.fparam('LIMITE_LEGAL_30', e), 30) pct
    from unnest(array['EF', 'PRE']) e),
  al as (
    select e.student_id, e.unit_id, iara.etapa_freq(gl.code) etapa from iara.enrollments e join iara.classes c on c.id = e.class_id
    join iara.grade_levels gl on gl.id = c.grade_level_id
    where e.status = 'ACTIVE' and gl.code <> 'CRECHE' and (p_unit is null or e.unit_id = p_unit)),
  fa as (select f.student_id, count(*) n from iara.frequencia_faltas f join iara.frequencia_registros r on r.id = f.registro_id
         where r.data >= make_date(v_ano, 1, 1) and f.student_id in (select student_id from al) group by 1),
  alvo as (
    select al.student_id, al.unit_id, al.etapa, fa.n * par.h horas, par.limite
    from al join fa on fa.student_id = al.student_id join par on par.etapa = al.etapa
    where fa.n * par.h > par.limite * par.pct / 100
      and not exists (select 1 from iara.encaminhamentos k where k.student_id = al.student_id and k.tipo = 'CONSELHO_TUTELAR' and k.obrigatorio
                      and k.created_at >= make_date(v_ano, 1, 1) and k.situacao <> 'CANCELADO')),
  ins as (
    insert into iara.encaminhamentos (caso_id, student_id, unit_id, tipo, orgao_id, servico, necessidade, fundamento, obrigatorio, criado_por_label)
    select (select k.id from iara.busca_ativa_casos k where k.student_id = a.student_id and k.situacao <> 'ENCERRADO'), a.student_id, a.unit_id, 'CONSELHO_TUTELAR',
           (select o.id from iara.orgaos_destinatarios o join iara.education_units u on u.id = a.unit_id
            where o.tipo = 'CONSELHO_TUTELAR' and o.ativo and o.verificado and (u.macro_territory_id = any (o.territorio_ids) or o.territorio_ids = '{}') order by o.territorio_ids = '{}' limit 1),
           'Notificação de faltas', format('Ausências: %s h, acima de 30%% do limite legal de faltas (%s h).', a.horas, round(a.limite)),
           'LDB, art. 12, VIII, “a” — faltas acima de 30% do percentual permitido em lei', true, 'IARA (regra legal)'
    from alvo a
    returning id, student_id, caso_id, unit_id)
  insert into iara.frequencia_tarefas (student_id, caso_id, unit_id, tipo, prioridade, destino, descricao, prazo, obrigatoria, chave)
  select i.student_id, i.caso_id, i.unit_id, 'NOTIFICAR_CT', 'URGENTE', 'DIRECAO',
         'Notificação obrigatória ao Conselho Tutelar (LDB, art. 12, VIII, “a”): conferir os dados do expediente, aprovar e enviar pelo canal oficial.',
         iara.hoje_local() + 5, true, 'ct:' || i.id
  from ins i;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- expediente: o necessário do aluno e do responsável, ausências, motivos, contatos, apoios e fundamento
create or replace function iara.ba_expediente(p_student uuid, p_caso uuid, p_fundamento text) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object(
    'aluno', jsonb_build_object('nome', s.full_name, 'nascimento', s.birth_date),
    'responsavel', (select jsonb_build_object('nome', g.full_name, 'telefone', g.primary_phone) from iara.guardians g where g.id = iara.responsavel_contato(s.id)),
    'unidade', u.name, 'etapa', gl.name, 'turma', c.class_name,
    'ausencias', (select jsonb_build_object('dias', count(*), 'horas', count(*) * coalesce(iara.fparam('HORAS_DIA', iara.etapa_freq(gl.code)), 4),
                   'datas', jsonb_agg(r.data order by r.data desc))
                  from iara.frequencia_faltas f join iara.frequencia_registros r on r.id = f.registro_id
                  where f.student_id = s.id and extract(year from r.data) = extract(year from iara.hoje_local())),
    'motivos', (select coalesce(jsonb_object_agg(coalesce(motivo, 'SEM_RESPOSTA'), n), '{}') from (select motivo, count(*) n from iara.frequencia_ausencias where student_id = s.id group by 1) z),
    'contatos', (select count(*) from iara.frequencia_contatos k where s.id = any (k.student_ids)),
    'providencias', (select coalesce(jsonb_agg(jsonb_build_object('data', ev.created_at, 'tipo', ev.tipo, 'texto', ev.texto) order by ev.created_at), '[]')
                     from iara.busca_ativa_eventos ev where ev.caso_id = p_caso),
    'fundamento', p_fundamento, 'gerado_em', now())
  from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' join iara.classes c on c.id = e.class_id
  join iara.grade_levels gl on gl.id = c.grade_level_id join iara.education_units u on u.id = e.unit_id
  where s.id = p_student
$$;

-- 5. Família: responder a ausência (portal e IARA) ------------------------------------------------------------------------------
create or replace function iara.texto_indica_risco(p text) returns boolean
language sql immutable as $$
  select coalesce(lower(p), '') ~ '(violen|apanh|bat(e|eu|eram|endo) n|espanc|machuc|abus|maus.?trat|ameac|amea[cç]|abandon|sozinh|fome|droga|suicid|se mat|se cort|estupr|assedi)'
$$;

create or replace function api.familia_ausencias(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'student_id', a.student_id, 'primeiro_nome', split_part(s.full_name, ' ', 1), 'data', a.data,
      'unidade', u.short_name, 'situacao', a.situacao, 'motivo', a.motivo) order by a.data desc, s.full_name), '[]')
    from iara.frequencia_ausencias a join iara.students s on s.id = a.student_id join iara.education_units u on u.id = a.unit_id
    where a.student_id in (select iara.my_student_ids()) and a.data >= iara.hoje_local() - 30
      and (a.situacao = 'AGUARDANDO_ESCLARECIMENTO' or coalesce((p ->> 'todas')::boolean, false)));
end $$;

create or replace function api.familia_ausencia_responder(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  a iara.frequencia_ausencias;
  v_motivo text := upper(coalesce(p ->> 'motivo', ''));
  v_texto text := nullif(btrim(coalesce(p ->> 'texto', '')), '');
  v_risco boolean;
  v_caso uuid;
  v_msg text;
begin
  select * into a from iara.frequencia_ausencias where id = (p ->> 'id')::uuid for update;
  if a.id is null or iara.my_guardian() is null or a.student_id not in (select iara.my_student_ids()) then raise exception 'Ausência não encontrada.' using errcode = 'P0002'; end if;
  if v_motivo not in ('SAUDE', 'CONSULTA', 'TRANSPORTE', 'DIFICULDADE_FAMILIAR', 'RECUSA', 'OUTRO', 'ESTA_NA_ESCOLA') then raise exception 'Escolha o motivo.' using errcode = '22023'; end if;
  if v_motivo = 'OUTRO' and v_texto is null then raise exception 'Conte o motivo com suas palavras.' using errcode = '22023'; end if;
  v_risco := iara.texto_indica_risco(v_texto);
  update iara.frequencia_ausencias set situacao = case when a.situacao = 'AGUARDANDO_ESCLARECIMENTO' then 'MOTIVO_INFORMADO' else a.situacao end,
         motivo = v_motivo, motivo_texto = left(v_texto, 1000), respondido_em = now(), respondido_canal = coalesce(nullif(p ->> 'canal', ''), 'PORTAL'),
         risco = a.risco or v_risco, atualizado_em = now()
  where id = a.id;
  -- a resposta interrompe os lembretes e as tarefas de cobrança daquela ausência; a mensagem conjunta (irmãos) só fica
  -- respondida quando todas as ausências dela foram respondidas
  update iara.frequencia_contatos k set status = 'RESPONDIDA' where a.id = any (k.ausencia_ids) and k.status in ('ENVIADA', 'SIMULADA')
    and not exists (select 1 from iara.frequencia_ausencias b where b.id = any (k.ausencia_ids) and b.id <> a.id and b.respondido_em is null and b.situacao = 'AGUARDANDO_ESCLARECIMENTO');
  update iara.frequencia_contatos k set status = 'CANCELADA' where a.id = any (k.ausencia_ids) and k.status = 'AGENDADA' and cardinality(k.ausencia_ids) = 1;
  update iara.frequencia_tarefas set situacao = 'CANCELADA', resultado = 'A família respondeu: ' || v_motivo where ausencia_id = a.id and situacao = 'ABERTA' and tipo in ('LIGAR', 'REUNIAO') and not obrigatoria;
  if v_motivo = 'ESTA_NA_ESCOLA' then
    insert into iara.frequencia_tarefas (student_id, ausencia_id, unit_id, tipo, prioridade, destino, descricao, prazo, chave)
    values (a.student_id, a.id, a.unit_id, 'CONFERIR_PRESENCA', 'ALTA', 'SECRETARIA_UNIDADE', 'A família diz que a criança estava na escola: conferir a chamada com o professor.', iara.hoje_local(), 'pres:' || a.id)
    on conflict (chave) do nothing;
  elsif v_motivo = 'TRANSPORTE' then
    insert into iara.frequencia_tarefas (student_id, ausencia_id, unit_id, tipo, prioridade, destino, descricao, prazo, chave)
    values (a.student_id, a.id, a.unit_id, 'APOIO_SETOR', 'ALTA', 'TRANSPORTE', 'A família informou problema de transporte: verificar a rota ou o pedido de transporte escolar.', iara.hoje_local() + 2, 'apoio:' || a.id)
    on conflict (chave) do nothing;
  elsif v_motivo in ('DIFICULDADE_FAMILIAR', 'RECUSA') or (v_motivo = 'SAUDE' and (select count(*) from iara.frequencia_ausencias where student_id = a.student_id and motivo = 'SAUDE'
                                                                                    and data >= iara.hoje_local() - 30) >= coalesce(iara.fparam('APOIO_SAUDE_RECORRENTE'), 3)) then
    insert into iara.frequencia_tarefas (student_id, ausencia_id, unit_id, tipo, prioridade, destino, descricao, prazo, chave)
    values (a.student_id, a.id, a.unit_id, 'APOIO_SETOR', 'ALTA', 'EQUIPE_PEDAGOGICA',
            case v_motivo when 'RECUSA' then 'A família relata recusa ou dificuldade para frequentar a escola: acolher e planejar o apoio (sem presumir negligência).'
                          when 'SAUDE' then 'Ausências por saúde recorrentes: conversar com a família sobre apoio e, se necessário, a rede de saúde (sem pedir diagnóstico).'
                          else 'A família relata dificuldade: acolher e avaliar apoio da rede (assistência social), sem presumir negligência.' end,
            iara.hoje_local() + 2, 'apoio:' || a.id)
    on conflict (chave) do nothing;
  end if;
  -- relato com indício de risco: alerta prioritário imediato à equipe autorizada (a IARA não decide nada sozinha)
  if v_risco then
    select id into v_caso from iara.busca_ativa_casos where student_id = a.student_id and situacao <> 'ENCERRADO';
    if v_caso is null then
      insert into iara.busca_ativa_casos (student_id, unit_id, etapa, origem, motivo_abertura, urgente, acompanhar_em)
      values (a.student_id, a.unit_id, a.etapa, 'RISCO', 'Relato da família com possível indício de risco — avaliação humana imediata.', true, iara.hoje_local())
      returning id into v_caso;
    else
      update iara.busca_ativa_casos set urgente = true where id = v_caso;
    end if;
    insert into iara.busca_ativa_eventos (caso_id, tipo, texto, autor_label) values (v_caso, 'OBSERVACAO', 'Relato da família sinalizado pela IARA para avaliação: ' || left(v_texto, 500), 'IARA (sinalização)');
    insert into iara.frequencia_tarefas (student_id, ausencia_id, caso_id, unit_id, tipo, prioridade, destino, descricao, prazo, obrigatoria, chave)
    values (a.student_id, a.id, v_caso, a.unit_id, 'AVALIAR_RISCO', 'URGENTE', 'DIRECAO',
            'Relato com possível indício de risco: avaliação imediata pela equipe autorizada e, se for o caso, comunicação ao Conselho Tutelar.', iara.hoje_local(), true, 'risco:' || a.id)
    on conflict (chave) do nothing;
  end if;
  perform iara.audit_event('AUSENCIA_RESPONDIDA', 'student', a.student_id::text, a.unit_id, 'Família informou o motivo da ausência de ' || to_char(a.data, 'DD/MM') || '.');
  v_msg := case when v_risco then 'Obrigada por contar. A equipe da escola vai entrar em contato com prioridade. Se for uma emergência, ligue 190 ou procure o Conselho Tutelar.'
                when v_motivo = 'ESTA_NA_ESCOLA' then 'Obrigada! A escola vai conferir a chamada e corrigir se houve engano.'
                when v_motivo = 'SAUDE' then 'Obrigada por avisar. Desejamos melhoras! Se houver atestado, envie em Documentos (área do responsável).'
                else 'Obrigada por avisar. A escola acompanha e, se precisar de apoio, a equipe entra em contato.' end;
  return jsonb_build_object('ok', true, 'risco', v_risco, 'mensagem', v_msg);
end $$;

-- 6. Equipe: painel, listas, aluno, tarefas, casos e encaminhamentos ------------------------------------------------------------------
create or replace function api.busca_ativa_painel(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_hoje date := iara.hoje_local();
begin
  perform iara.require_perm('busca_ativa.read');
  return jsonb_build_object(
    'unidade', (select name from iara.education_units where id = v_unit),
    'sem_esclarecimento', (select count(*) from iara.frequencia_ausencias where situacao = 'AGUARDANDO_ESCLARECIMENTO' and data >= v_hoje - 30 and (v_unit is null or unit_id = v_unit)),
    'contatos_hoje', (select count(*) from iara.frequencia_contatos where enviada_em >= v_hoje::timestamp and (v_unit is null or unit_id = v_unit)),
    'contatos_pendentes', (select count(*) from iara.frequencia_contatos where status = 'AGENDADA' and (v_unit is null or unit_id = v_unit)),
    'falhas', (select count(*) from iara.frequencia_tarefas where tipo = 'CONFERIR_TELEFONE' and situacao = 'ABERTA' and (v_unit is null or unit_id = v_unit)),
    'taxa_resposta_30d', (select round(100.0 * count(*) filter (where respondido_em is not null) / nullif(count(*) filter (where situacao not in ('ERRO_CORRIGIDO', 'JUSTIFICATIVA_ACEITA', 'AFASTAMENTO')), 0), 1)
                          from iara.frequencia_ausencias where data >= v_hoje - 30 and (v_unit is null or unit_id = v_unit)),
    'busca_ativa', (select count(*) from iara.busca_ativa_casos where situacao in ('ABERTO', 'EM_ACOMPANHAMENTO') and (v_unit is null or unit_id = v_unit)),
    'encaminhamentos_aprovacao', (select count(*) from iara.encaminhamentos where situacao = 'AGUARDANDO_APROVACAO' and tipo = 'REDE_APOIO' and (v_unit is null or unit_id = v_unit)),
    'comunicacoes_legais', (select count(*) from iara.encaminhamentos where tipo = 'CONSELHO_TUTELAR' and situacao in ('AGUARDANDO_APROVACAO', 'APROVADO', 'FALHA_ENVIO') and (v_unit is null or unit_id = v_unit)),
    'urgentes', (select count(*) from iara.frequencia_tarefas where prioridade = 'URGENTE' and tipo = 'AVALIAR_RISCO' and situacao = 'ABERTA' and (v_unit is null or unit_id = v_unit)),
    'retorno', (select count(*) from iara.busca_ativa_casos where situacao = 'RETORNOU' and (v_unit is null or unit_id = v_unit)),
    'tarefas_abertas', (select coalesce(jsonb_object_agg(destino, n), '{}') from (select destino, count(*) n from iara.frequencia_tarefas where situacao = 'ABERTA' and (v_unit is null or unit_id = v_unit) group by 1) z),
    'motivos_30d', (select coalesce(jsonb_object_agg(motivo, n), '{}') from (select motivo, count(*) n from iara.frequencia_ausencias where motivo is not null and data >= v_hoje - 30 and (v_unit is null or unit_id = v_unit) group by 1) z),
    'pode_gerir', iara.has_perm('busca_ativa.manage'), 'pode_aprovar', iara.has_perm('busca_ativa.aprovar'), 'pode_parametros', iara.has_perm('frequencia.parametros'));
end $$;

create or replace function api.busca_ativa_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_painel text := coalesce(nullif(p ->> 'painel', ''), 'SEM_ESCLARECIMENTO');
  v_q text := nullif(iara.norm(btrim(coalesce(p ->> 'q', ''))), '');
  v_hoje date := iara.hoje_local();
begin
  perform iara.require_perm('busca_ativa.read');
  if v_painel = 'SEM_ESCLARECIMENTO' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'student_id', a.student_id, 'aluno', s.full_name, 'unidade', u.short_name, 'data', a.data, 'nivel', a.nivel,
        'etapa', a.etapa, 'contato', (select k.status from iara.frequencia_contatos k where a.id = any (k.ausencia_ids) order by k.created_at desc limit 1)) order by a.data, s.full_name), '[]')
      from (select * from iara.frequencia_ausencias where situacao = 'AGUARDANDO_ESCLARECIMENTO' and data >= v_hoje - 30 and (v_unit is null or unit_id = v_unit) and iara.ba_acesso_unidade(unit_id)
            order by data limit 300) a join iara.students s on s.id = a.student_id join iara.education_units u on u.id = a.unit_id
      where v_q is null or iara.norm(s.full_name) like '%' || v_q || '%');
  elsif v_painel = 'TAREFAS' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'student_id', t.student_id, 'aluno', s.full_name, 'unidade', u.short_name, 'tipo', t.tipo, 'prioridade', t.prioridade,
        'destino', t.destino, 'descricao', t.descricao, 'prazo', t.prazo, 'obrigatoria', t.obrigatoria, 'atrasada', t.prazo < v_hoje, 'caso_id', t.caso_id)
        order by case t.prioridade when 'URGENTE' then 0 when 'ALTA' then 1 else 2 end, t.prazo nulls last), '[]')
      from (select * from iara.frequencia_tarefas where situacao = 'ABERTA' and (v_unit is null or unit_id = v_unit) and iara.ba_acesso_unidade(unit_id)
              and (nullif(p ->> 'tipo', '') is null or tipo = p ->> 'tipo') order by prioridade = 'URGENTE' desc, prazo limit 300) t
      left join iara.students s on s.id = t.student_id left join iara.education_units u on u.id = t.unit_id
      where v_q is null or iara.norm(s.full_name) like '%' || v_q || '%');
  elsif v_painel in ('CASOS', 'RETORNO', 'URGENTES') then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', k.id, 'student_id', k.student_id, 'aluno', s.full_name, 'unidade', u.short_name, 'origem', k.origem, 'situacao', k.situacao,
        'urgente', k.urgente, 'motivo', k.motivo_abertura, 'aberto_em', k.aberto_em, 'acompanhar_em', k.acompanhar_em,
        'eventos', (select count(*) from iara.busca_ativa_eventos ev where ev.caso_id = k.id)) order by k.urgente desc, k.aberto_em), '[]')
      from (select * from iara.busca_ativa_casos where (v_unit is null or unit_id = v_unit) and iara.ba_acesso_unidade(unit_id)
              and case v_painel when 'CASOS' then situacao in ('ABERTO', 'EM_ACOMPANHAMENTO') when 'RETORNO' then situacao = 'RETORNOU' else urgente and situacao <> 'ENCERRADO' end
            order by urgente desc, aberto_em limit 300) k join iara.students s on s.id = k.student_id join iara.education_units u on u.id = k.unit_id
      where v_q is null or iara.norm(s.full_name) like '%' || v_q || '%');
  elsif v_painel in ('ENCAMINHAMENTOS', 'LEGAIS') then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'student_id', e.student_id, 'aluno', s.full_name, 'unidade', u.short_name, 'tipo', e.tipo, 'situacao', e.situacao,
        'orgao', o.nome, 'orgao_verificado', o.verificado, 'servico', e.servico, 'fundamento', e.fundamento, 'obrigatorio', e.obrigatorio, 'created_at', e.created_at,
        'protocolo', e.protocolo) order by e.obrigatorio desc, e.created_at), '[]')
      from (select * from iara.encaminhamentos where (v_unit is null or unit_id = v_unit) and iara.ba_acesso_unidade(unit_id)
              and case v_painel when 'LEGAIS' then tipo = 'CONSELHO_TUTELAR' and situacao in ('AGUARDANDO_APROVACAO', 'APROVADO', 'FALHA_ENVIO')
                                else tipo = 'REDE_APOIO' and situacao in ('AGUARDANDO_APROVACAO', 'APROVADO', 'FALHA_ENVIO') end
            order by created_at limit 300) e
      join iara.students s on s.id = e.student_id join iara.education_units u on u.id = e.unit_id left join iara.orgaos_destinatarios o on o.id = e.orgao_id
      where v_q is null or iara.norm(s.full_name) like '%' || v_q || '%');
  elsif v_painel = 'CONTATOS' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', k.id, 'nivel', k.nivel, 'status', k.status, 'data', k.data_ref, 'enviada_em', k.enviada_em, 'agendada_para', k.agendada_para,
        'unidade', u.short_name, 'alunos', (select string_agg(split_part(full_name, ' ', 1), ', ') from iara.students where id = any (k.student_ids)), 'falha', k.falha_motivo)
        order by k.created_at desc), '[]')
      from (select * from iara.frequencia_contatos where (v_unit is null or unit_id = v_unit) and iara.ba_acesso_unidade(unit_id)
              and status in ('AGENDADA', 'FALHA') order by created_at desc limit 300) k left join iara.education_units u on u.id = k.unit_id);
  end if;
  raise exception 'Painel desconhecido.' using errcode = '22023';
end $$;

create or replace function api.busca_ativa_aluno(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  e record;
  v_caso uuid;
begin
  select en.unit_id, en.class_id, c.class_name, gl.code, iara.etapa_freq(gl.code) etapa into e from iara.enrollments en join iara.classes c on c.id = en.class_id
  join iara.grade_levels gl on gl.id = c.grade_level_id where en.student_id = v_student and en.status = 'ACTIVE' limit 1;
  if not iara.ba_acesso_unidade(e.unit_id) then raise exception 'Aluno fora do seu escopo.' using errcode = '42501'; end if;
  select id into v_caso from iara.busca_ativa_casos where student_id = v_student order by (situacao <> 'ENCERRADO') desc, aberto_em desc limit 1;
  perform iara.audit_event('BUSCA_ATIVA_CONSULTA', 'student', v_student::text, e.unit_id, 'Acompanhamento de frequência consultado.');
  return jsonb_build_object(
    'aluno', (select jsonb_build_object('id', s.id, 'nome', s.full_name, 'turma', e.class_name, 'etapa', e.etapa, 'unidade', (select short_name from iara.education_units where id = e.unit_id))
              from iara.students s where s.id = v_student),
    'responsavel', (select jsonb_build_object('nome', g.full_name, 'telefone', g.primary_phone, 'whatsapp', g.whatsapp_phone, 'alternativo', g.secondary_phone)
                    from iara.guardians g where g.id = iara.responsavel_contato(v_student)),
    'limite_legal', case when e.etapa <> 'CRECHE' then (select jsonb_build_object('dias', z.n, 'horas', z.n * coalesce(iara.fparam('HORAS_DIA', e.etapa), 4),
        'limite_horas', coalesce(iara.fparam('CARGA_HORARIA_ANUAL', e.etapa), 800) * (100 - coalesce(iara.fparam('FREQUENCIA_MINIMA', e.etapa), 75)) / 100,
        'alerta_horas', coalesce(iara.fparam('CARGA_HORARIA_ANUAL', e.etapa), 800) * (100 - coalesce(iara.fparam('FREQUENCIA_MINIMA', e.etapa), 75)) / 100 * coalesce(iara.fparam('LIMITE_LEGAL_30', e.etapa), 30) / 100)
      from (select count(*) n from iara.frequencia_faltas f join iara.frequencia_registros r on r.id = f.registro_id
            where f.student_id = v_student and extract(year from r.data) = extract(year from iara.hoje_local())) z) end,
    'ausencias', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'data', a.data, 'situacao', a.situacao, 'motivo', a.motivo, 'motivo_texto', a.motivo_texto, 'nivel', a.nivel,
        'risco', a.risco, 'respondido_em', a.respondido_em) order by a.data desc), '[]') from (select * from iara.frequencia_ausencias where student_id = v_student order by data desc limit 40) a),
    'contatos', (select coalesce(jsonb_agg(jsonb_build_object('nivel', k.nivel, 'status', k.status, 'data', k.data_ref, 'enviada_em', k.enviada_em, 'texto', k.texto, 'falha', k.falha_motivo)
        order by k.created_at desc), '[]') from (select * from iara.frequencia_contatos where v_student = any (student_ids) order by created_at desc limit 20) k),
    'tarefas', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'tipo', t.tipo, 'prioridade', t.prioridade, 'destino', t.destino, 'descricao', t.descricao, 'situacao', t.situacao,
        'prazo', t.prazo, 'resultado', t.resultado, 'obrigatoria', t.obrigatoria) order by t.situacao = 'ABERTA' desc, t.created_at desc), '[]') from iara.frequencia_tarefas t where t.student_id = v_student),
    'caso', (select jsonb_build_object('id', k.id, 'origem', k.origem, 'situacao', k.situacao, 'urgente', k.urgente, 'motivo', k.motivo_abertura, 'aberto_em', k.aberto_em,
        'acompanhar_em', k.acompanhar_em, 'encerramento_motivo', k.encerramento_motivo, 'resultado', k.resultado,
        'eventos', (select coalesce(jsonb_agg(jsonb_build_object('tipo', ev.tipo, 'texto', ev.texto, 'autor', ev.autor_label, 'em', ev.created_at) order by ev.created_at), '[]') from iara.busca_ativa_eventos ev where ev.caso_id = k.id))
      from iara.busca_ativa_casos k where k.id = v_caso),
    'encaminhamentos', (select coalesce(jsonb_agg(jsonb_build_object('id', en.id, 'tipo', en.tipo, 'situacao', en.situacao, 'orgao', o.nome, 'orgao_verificado', o.verificado, 'servico', en.servico,
        'necessidade', en.necessidade, 'fundamento', en.fundamento, 'obrigatorio', en.obrigatorio, 'protocolo', en.protocolo, 'enviado_em', en.enviado_em, 'recebido_em', en.recebido_em,
        'retorno', en.retorno_texto, 'aprovado_por', en.aprovado_por_label, 'conteudo', en.conteudo, 'comunicar_familia', en.comunicar_familia) order by en.created_at desc), '[]')
      from iara.encaminhamentos en left join iara.orgaos_destinatarios o on o.id = en.orgao_id where en.student_id = v_student),
    'orgaos', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'nome', o.nome, 'tipo', o.tipo, 'verificado', o.verificado, 'canal', o.canal) order by o.tipo, o.nome), '[]')
               from iara.orgaos_destinatarios o where o.ativo),
    'pode_gerir', iara.has_perm('busca_ativa.manage'), 'pode_aprovar', iara.has_perm('busca_ativa.aprovar'));
end $$;

create or replace function api.ba_tarefa_concluir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  t iara.frequencia_tarefas;
  v_caso uuid;
begin
  perform iara.require_perm('busca_ativa.manage');
  select * into t from iara.frequencia_tarefas where id = (p ->> 'id')::uuid for update;
  if t.id is null or not iara.ba_acesso_unidade(t.unit_id) then raise exception 'Tarefa não encontrada.' using errcode = 'P0002'; end if;
  if t.situacao <> 'ABERTA' then raise exception 'Tarefa já encerrada.' using errcode = '22023'; end if;
  if length(btrim(coalesce(p ->> 'resultado', ''))) < 10 then raise exception 'Registre o que foi feito (pelo menos 10 caracteres).' using errcode = '22023'; end if;
  -- comunicação legal não pode ser simplesmente ignorada: a tarefa só fecha com o expediente aprovado
  if t.tipo = 'NOTIFICAR_CT' and not exists (select 1 from iara.encaminhamentos where student_id = t.student_id and tipo = 'CONSELHO_TUTELAR' and situacao in ('ENVIADO', 'RECEBIDO', 'RETORNO_REGISTRADO')) then
    raise exception 'A notificação ao Conselho Tutelar é obrigatória: aprove e registre o envio do expediente antes de concluir.' using errcode = '22023';
  end if;
  update iara.frequencia_tarefas set situacao = 'CONCLUIDA', sucesso = coalesce((p ->> 'sucesso')::boolean, true), resultado = btrim(p ->> 'resultado'),
         concluida_por_label = iara.my_label(), concluida_em = now() where id = t.id;
  v_caso := coalesce(t.caso_id, (select id from iara.busca_ativa_casos where student_id = t.student_id and situacao <> 'ENCERRADO'));
  if v_caso is not null then
    insert into iara.busca_ativa_eventos (caso_id, tipo, texto, autor_label)
    values (v_caso, case t.tipo when 'LIGAR' then 'CONTATO_TELEFONE' when 'REUNIAO' then 'REUNIAO' when 'APOIO_SETOR' then 'APOIO' else 'OBSERVACAO' end, btrim(p ->> 'resultado'), iara.my_label());
  end if;
  perform iara.audit_event('BUSCA_ATIVA_TAREFA', 'student', t.student_id::text, t.unit_id, 'Tarefa concluída: ' || lower(t.tipo) || '.');
  return jsonb_build_object('ok', true);
end $$;

create or replace function api.ba_ausencia_classificar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  a iara.frequencia_ausencias;
  v_sit text := p ->> 'situacao';
begin
  perform iara.require_perm('busca_ativa.manage');
  select * into a from iara.frequencia_ausencias where id = (p ->> 'id')::uuid for update;
  if a.id is null or not iara.ba_acesso_unidade(a.unit_id) then raise exception 'Ausência não encontrada.' using errcode = 'P0002'; end if;
  if v_sit not in ('JUSTIFICATIVA_ACEITA', 'INJUSTIFICADA', 'AFASTAMENTO', 'JUSTIFICATIVA_EM_ANALISE') then raise exception 'Situação inválida.' using errcode = '22023'; end if;
  -- justificativa aceita ou afastamento: suspende lembretes do período e marca data de acompanhamento (a ausência continua contada)
  update iara.frequencia_ausencias set situacao = v_sit, classificado_por_label = iara.my_label(), atualizado_em = now(),
         acompanhar_em = case when v_sit in ('JUSTIFICATIVA_ACEITA', 'AFASTAMENTO') then coalesce(nullif(p ->> 'acompanhar_em', '')::date, iara.hoje_local() + 15) else acompanhar_em end
  where id = a.id;
  if v_sit in ('JUSTIFICATIVA_ACEITA', 'AFASTAMENTO') then
    update iara.frequencia_contatos set status = 'CANCELADA' where a.id = any (ausencia_ids) and status = 'AGENDADA';
    update iara.frequencia_tarefas set situacao = 'CANCELADA', resultado = 'Justificativa aceita ou afastamento' where ausencia_id = a.id and situacao = 'ABERTA' and not obrigatoria and tipo in ('LIGAR', 'REUNIAO');
  end if;
  perform iara.audit_event('AUSENCIA_CLASSIFICADA', 'student', a.student_id::text, a.unit_id, format('Ausência de %s: %s.', to_char(a.data, 'DD/MM'), lower(replace(v_sit, '_', ' '))));
  return jsonb_build_object('ok', true);
end $$;

create or replace function api.ba_caso(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  k iara.busca_ativa_casos;
  v_acao text := p ->> 'acao';
  v_student uuid := nullif(p ->> 'student_id', '')::uuid;
  e record;
begin
  perform iara.require_perm('busca_ativa.manage');
  if v_acao = 'ABRIR' then
    select en.unit_id, iara.etapa_freq(gl.code) etapa into e from iara.enrollments en join iara.classes c on c.id = en.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
    where en.student_id = v_student and en.status = 'ACTIVE' limit 1;
    if not iara.ba_acesso_unidade(e.unit_id) then raise exception 'Aluno fora do seu escopo.' using errcode = '42501'; end if;
    if length(btrim(coalesce(p ->> 'texto', ''))) < 10 then raise exception 'Descreva o motivo da abertura.' using errcode = '22023'; end if;
    insert into iara.busca_ativa_casos (student_id, unit_id, etapa, origem, motivo_abertura, urgente, responsavel_label, acompanhar_em)
    values (v_student, e.unit_id, e.etapa, 'MANUAL', btrim(p ->> 'texto'), coalesce((p ->> 'urgente')::boolean, false), iara.my_label(), iara.hoje_local() + 3) returning * into k;
    insert into iara.busca_ativa_eventos (caso_id, tipo, texto, autor_label) values (k.id, 'ABERTURA', btrim(p ->> 'texto'), iara.my_label());
  else
    select * into k from iara.busca_ativa_casos where id = (p ->> 'caso_id')::uuid for update;
    if k.id is null or not iara.ba_acesso_unidade(k.unit_id) then raise exception 'Caso não encontrado.' using errcode = 'P0002'; end if;
    if length(btrim(coalesce(p ->> 'texto', ''))) < 10 then raise exception 'Registre o que aconteceu (pelo menos 10 caracteres).' using errcode = '22023'; end if;
    if v_acao = 'EVENTO' then
      if coalesce(p ->> 'tipo', '') not in ('CONTATO_TELEFONE', 'MENSAGEM', 'VISITA', 'REUNIAO', 'APOIO', 'RETORNO', 'OBSERVACAO') then raise exception 'Tipo inválido.' using errcode = '22023'; end if;
      insert into iara.busca_ativa_eventos (caso_id, tipo, texto, autor_label) values (k.id, p ->> 'tipo', btrim(p ->> 'texto'), iara.my_label());
      -- o retorno à escola atualiza o caso, mas não o encerra (encerramento exige registro da equipe)
      update iara.busca_ativa_casos set situacao = case when p ->> 'tipo' = 'RETORNO' then 'RETORNOU' when situacao = 'ABERTO' then 'EM_ACOMPANHAMENTO' else situacao end,
             acompanhar_em = coalesce(nullif(p ->> 'acompanhar_em', '')::date, acompanhar_em) where id = k.id;
    elsif v_acao = 'ENCERRAR' then
      if length(btrim(coalesce(p ->> 'resultado', ''))) < 10 then raise exception 'Registre o resultado.' using errcode = '22023'; end if;
      if exists (select 1 from iara.frequencia_tarefas where caso_id = k.id and obrigatoria and situacao = 'ABERTA') then
        raise exception 'Há comunicação obrigatória ou avaliação de risco pendente neste caso: conclua antes de encerrar.' using errcode = '22023';
      end if;
      update iara.busca_ativa_casos set situacao = 'ENCERRADO', encerrado_em = now(), encerramento_motivo = btrim(p ->> 'texto'), resultado = btrim(p ->> 'resultado') where id = k.id;
      insert into iara.busca_ativa_eventos (caso_id, tipo, texto, autor_label) values (k.id, 'ENCERRAMENTO', btrim(p ->> 'texto') || ' — ' || btrim(p ->> 'resultado'), iara.my_label());
    else
      raise exception 'Ação inválida.' using errcode = '22023';
    end if;
  end if;
  perform iara.audit_event('BUSCA_ATIVA_CASO', 'student', k.student_id::text, k.unit_id, 'Busca ativa: ' || lower(v_acao) || '.');
  return jsonb_build_object('ok', true, 'caso_id', k.id);
end $$;

create or replace function api.ba_encaminhamento(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  en iara.encaminhamentos;
  o iara.orgaos_destinatarios;
  v_acao text := p ->> 'acao';
  v_student uuid := nullif(p ->> 'student_id', '')::uuid;
  v_caso uuid;
  v_unit integer;
  v_c uuid;
begin
  if v_acao = 'CRIAR' then
    perform iara.require_perm('busca_ativa.manage');
    select unit_id into v_unit from iara.enrollments where student_id = v_student and status = 'ACTIVE' limit 1;
    if not iara.ba_acesso_unidade(v_unit) then raise exception 'Aluno fora do seu escopo.' using errcode = '42501'; end if;
    if coalesce(p ->> 'tipo', '') not in ('REDE_APOIO', 'CONSELHO_TUTELAR') then raise exception 'Tipo inválido.' using errcode = '22023'; end if;
    if length(btrim(coalesce(p ->> 'fundamento', ''))) < 5 then raise exception 'Informe o fundamento.' using errcode = '22023'; end if;
    select id into v_caso from iara.busca_ativa_casos where student_id = v_student and situacao <> 'ENCERRADO';
    insert into iara.encaminhamentos (caso_id, student_id, unit_id, tipo, orgao_id, servico, necessidade, fundamento, conteudo, comunicar_familia, criado_por_label)
    values (v_caso, v_student, v_unit, p ->> 'tipo', nullif(p ->> 'orgao_id', '')::uuid, nullif(btrim(coalesce(p ->> 'servico', '')), ''), nullif(btrim(coalesce(p ->> 'necessidade', '')), ''),
            btrim(p ->> 'fundamento'), iara.ba_expediente(v_student, v_caso, btrim(p ->> 'fundamento')), coalesce((p ->> 'comunicar_familia')::boolean, false), iara.my_label())
    returning * into en;
    if v_caso is not null then insert into iara.busca_ativa_eventos (caso_id, tipo, texto, autor_label) values (v_caso, 'ENCAMINHAMENTO', 'Encaminhamento preparado (' || lower(en.tipo) || '), aguardando aprovação.', iara.my_label()); end if;
    return jsonb_build_object('ok', true, 'id', en.id);
  end if;
  select * into en from iara.encaminhamentos where id = (p ->> 'id')::uuid for update;
  if en.id is null or not iara.ba_acesso_unidade(en.unit_id) then raise exception 'Encaminhamento não encontrado.' using errcode = 'P0002'; end if;
  select * into o from iara.orgaos_destinatarios where id = coalesce(nullif(p ->> 'orgao_id', '')::uuid, en.orgao_id);
  if v_acao = 'APROVAR' then
    perform iara.require_perm('busca_ativa.aprovar');
    if en.situacao <> 'AGUARDANDO_APROVACAO' then raise exception 'Este encaminhamento não está aguardando aprovação.' using errcode = '22023'; end if;
    if en.caso_id is null then en.caso_id := (select id from iara.busca_ativa_casos where student_id = en.student_id and situacao <> 'ENCERRADO'); end if;
    if o.id is null or not o.verificado or not o.ativo then raise exception 'Escolha um destinatário institucional verificado (cadastro de órgãos).' using errcode = '22023'; end if;
    update iara.encaminhamentos set situacao = 'APROVADO', orgao_id = o.id, aprovado_por_label = iara.my_label(), aprovado_em = now(),
           comunicar_familia = coalesce((p ->> 'comunicar_familia')::boolean, comunicar_familia),
           caso_id = en.caso_id, conteudo = iara.ba_expediente(en.student_id, en.caso_id, en.fundamento) where id = en.id returning * into en;
    -- a família só é avisada quando a equipe aprova (no Conselho Tutelar, só se a equipe decidir que não aumenta o risco)
    if en.comunicar_familia then
      insert into iara.frequencia_contatos (guardian_id, student_ids, unit_id, data_ref, nivel, texto, chave)
      values (iara.responsavel_contato(en.student_id), array[en.student_id], en.unit_id, iara.hoje_local(), 'REDE',
              iara.modelo_msg('REDE', jsonb_build_object('nome_responsavel', split_part((select full_name from iara.guardians where id = iara.responsavel_contato(en.student_id)), ' ', 1),
                'nome_aluno', split_part((select full_name from iara.students where id = en.student_id), ' ', 1), 'servico', coalesce(en.servico, o.nome),
                'necessidade', coalesce(en.necessidade, 'acompanhamento'))), 'rede:' || en.id)
      on conflict (chave) do nothing returning id into v_c;
      if v_c is not null then perform iara.ba_enviar(v_c); end if;
    end if;
  elsif v_acao = 'ENVIO' then
    perform iara.require_perm('busca_ativa.manage');
    if en.situacao not in ('APROVADO', 'FALHA_ENVIO') then raise exception 'Só encaminhamento aprovado é enviado.' using errcode = '22023'; end if;
    if coalesce((p ->> 'falhou')::boolean, false) then
      update iara.encaminhamentos set situacao = 'FALHA_ENVIO' where id = en.id;
      insert into iara.frequencia_tarefas (student_id, caso_id, unit_id, tipo, prioridade, destino, descricao, prazo, obrigatoria, chave)
      values (en.student_id, en.caso_id, en.unit_id, 'ENVIO_ALTERNATIVO', 'URGENTE', 'DIRECAO', 'O envio pelo canal oficial falhou: enviar pelo canal alternativo autorizado e registrar o protocolo.',
              iara.hoje_local() + 1, en.obrigatorio, 'alt:' || en.id || ':' || extract(epoch from now())::bigint);
    else
      if length(btrim(coalesce(p ->> 'protocolo', ''))) < 3 then raise exception 'Informe o protocolo ou o número do envio.' using errcode = '22023'; end if;
      update iara.encaminhamentos set situacao = 'ENVIADO', enviado_em = now(), enviado_canal = coalesce(nullif(p ->> 'canal', ''), o.canal), protocolo = btrim(p ->> 'protocolo') where id = en.id;
      update iara.frequencia_tarefas set situacao = 'CONCLUIDA', sucesso = true, resultado = 'Expediente enviado — protocolo ' || btrim(p ->> 'protocolo'), concluida_por_label = iara.my_label(), concluida_em = now()
      where student_id = en.student_id and tipo in ('NOTIFICAR_CT', 'ENVIO_ALTERNATIVO') and situacao = 'ABERTA' and en.tipo = 'CONSELHO_TUTELAR';
    end if;
  elsif v_acao = 'RECEBIDO' then
    perform iara.require_perm('busca_ativa.manage');
    if en.situacao <> 'ENVIADO' then raise exception 'Registre primeiro o envio.' using errcode = '22023'; end if;
    update iara.encaminhamentos set situacao = 'RECEBIDO', recebido_em = coalesce(nullif(p ->> 'em', '')::timestamptz, now()) where id = en.id;
  elsif v_acao = 'RETORNO' then
    perform iara.require_perm('busca_ativa.manage');
    if en.situacao not in ('ENVIADO', 'RECEBIDO') then raise exception 'Registre o envio antes do retorno.' using errcode = '22023'; end if;
    if length(btrim(coalesce(p ->> 'texto', ''))) < 10 then raise exception 'Registre o retorno do órgão.' using errcode = '22023'; end if;
    update iara.encaminhamentos set situacao = 'RETORNO_REGISTRADO', retorno_texto = btrim(p ->> 'texto'), retorno_em = now() where id = en.id;
  elsif v_acao = 'CANCELAR' then
    perform iara.require_perm('busca_ativa.aprovar');
    if en.obrigatorio then raise exception 'Comunicação legal obrigatória não pode ser cancelada: confira os dados e formalize o envio.' using errcode = '22023'; end if;
    if length(btrim(coalesce(p ->> 'texto', ''))) < 10 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
    update iara.encaminhamentos set situacao = 'CANCELADO', cancelamento_motivo = btrim(p ->> 'texto') where id = en.id;
  else
    raise exception 'Ação inválida.' using errcode = '22023';
  end if;
  if en.caso_id is not null then
    insert into iara.busca_ativa_eventos (caso_id, tipo, texto, autor_label)
    values (en.caso_id, 'ENCAMINHAMENTO', format('Encaminhamento (%s): %s%s.', lower(replace(en.tipo, '_', ' ')), lower(v_acao), coalesce(' — protocolo ' || nullif(p ->> 'protocolo', ''), '')), iara.my_label());
  end if;
  perform iara.audit_event('ENCAMINHAMENTO', 'student', en.student_id::text, en.unit_id, format('Encaminhamento %s: %s.', lower(en.tipo), lower(v_acao)));
  return jsonb_build_object('ok', true);
end $$;

create or replace function api.ba_afastamento(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_unit integer;
begin
  perform iara.require_perm('busca_ativa.manage');
  select unit_id into v_unit from iara.enrollments where student_id = v_student and status = 'ACTIVE' limit 1;
  if not iara.ba_acesso_unidade(v_unit) then raise exception 'Aluno fora do seu escopo.' using errcode = '42501'; end if;
  if nullif(p ->> 'inicio', '') is null or nullif(p ->> 'fim', '') is null or (p ->> 'fim')::date < (p ->> 'inicio')::date then raise exception 'Informe o período.' using errcode = '22023'; end if;
  if length(btrim(coalesce(p ->> 'motivo', ''))) < 5 then raise exception 'Informe o motivo (sem diagnóstico).' using errcode = '22023'; end if;
  insert into iara.frequencia_afastamentos (student_id, inicio, fim, motivo, acompanhar_em, registrado_por_label)
  values (v_student, (p ->> 'inicio')::date, (p ->> 'fim')::date, btrim(p ->> 'motivo'), coalesce(nullif(p ->> 'acompanhar_em', '')::date, (p ->> 'fim')::date + 1), iara.my_label());
  update iara.frequencia_ausencias set situacao = 'AFASTAMENTO', atualizado_em = now()
  where student_id = v_student and data between (p ->> 'inicio')::date and (p ->> 'fim')::date and situacao in ('AGUARDANDO_ESCLARECIMENTO', 'MOTIVO_INFORMADO', 'INJUSTIFICADA');
  perform iara.audit_event('AFASTAMENTO', 'student', v_student::text, v_unit, 'Afastamento acompanhado registrado.');
  return jsonb_build_object('ok', true);
end $$;

-- 7. Regras, modelos e órgãos -----------------------------------------------------------------------------------------------------
create or replace function api.frequencia_regras(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if not (iara.has_perm('busca_ativa.read') or iara.has_perm('frequencia.parametros')) then raise exception 'Sem permissão.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'regras', (select coalesce(jsonb_agg(to_jsonb(r) order by r.codigo, r.etapa, r.versao desc), '[]') from iara.frequencia_parametros r),
    'modelos', (select coalesce(jsonb_agg(to_jsonb(m) order by m.codigo), '[]') from iara.frequencia_modelos m),
    'orgaos', (select coalesce(jsonb_agg(to_jsonb(o) order by o.tipo, o.nome), '[]') from iara.orgaos_destinatarios o),
    'pode_editar', iara.has_perm('frequencia.parametros'));
end $$;

-- alteração gera nova versão (a anterior fica no histórico, com o fim da vigência); exige o fundamento
create or replace function api.frequencia_regra_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r iara.frequencia_parametros;
  n iara.frequencia_parametros;
begin
  perform iara.require_perm('frequencia.parametros');
  select * into r from iara.frequencia_parametros where id = (p ->> 'id')::uuid for update;
  if r.id is null then raise exception 'Regra não encontrada.' using errcode = 'P0002'; end if;
  if length(btrim(coalesce(p ->> 'fundamento', ''))) < 10 then raise exception 'Informe o fundamento da alteração (ato, ofício ou decisão).' using errcode = '22023'; end if;
  if coalesce(p ->> 'situacao', r.situacao) not in ('CONFIRMADO', 'PROPOSTO', 'PENDENTE_VALIDACAO') then raise exception 'Situação inválida.' using errcode = '22023'; end if;
  if coalesce(p ->> 'situacao', r.situacao) = 'CONFIRMADO' and length(btrim(coalesce(p ->> 'base_normativa', r.base_normativa, ''))) < 10 then
    raise exception 'Regra confirmada precisa da base normativa.' using errcode = '22023';
  end if;
  update iara.frequencia_parametros set ativo = false, vigencia_fim = iara.hoje_local() - 1 where id = r.id;
  insert into iara.frequencia_parametros (codigo, nome, rede, etapa, gatilho, valor, unidade, criterio_contagem, base_normativa, vigencia_inicio, aprovador, situacao, ativo, versao,
                                          alterado_por_label, fundamento_alteracao)
  values (r.codigo, r.nome, r.rede, r.etapa, coalesce(nullif(p ->> 'gatilho', ''), r.gatilho), coalesce(nullif(p ->> 'valor', '')::numeric, r.valor), r.unidade,
          coalesce(nullif(p ->> 'criterio_contagem', ''), r.criterio_contagem), coalesce(nullif(p ->> 'base_normativa', ''), r.base_normativa), iara.hoje_local(),
          coalesce(nullif(p ->> 'aprovador', ''), r.aprovador), coalesce(nullif(p ->> 'situacao', ''), r.situacao), coalesce((p ->> 'ativo')::boolean, true),
          (select max(versao) + 1 from iara.frequencia_parametros where codigo = r.codigo and rede = r.rede and etapa = r.etapa), iara.my_label(), btrim(p ->> 'fundamento'))
  returning * into n;
  perform iara.audit_event('REGRA_FREQUENCIA', 'frequencia_parametro', n.id::text, null,
    format('Regra %s (%s) versão %s: %s → %s; situação %s. Fundamento: %s', r.codigo, r.etapa, n.versao, coalesce(r.valor::text, '—'), coalesce(n.valor::text, '—'), n.situacao, left(n.fundamento_alteracao, 150)));
  return to_jsonb(n);
end $$;

create or replace function api.frequencia_modelo_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('frequencia.parametros');
  if length(btrim(coalesce(p ->> 'texto', ''))) < 30 then raise exception 'Mensagem curta demais.' using errcode = '22023'; end if;
  if p ->> 'texto' ~* '(multa|pris|crime|puni|polícia|policia|culpa)' then raise exception 'A mensagem deve ser acolhedora, sem ameaça ou presunção de culpa.' using errcode = '22023'; end if;
  update iara.frequencia_modelos set texto = btrim(p ->> 'texto'), versao = versao + 1, alterado_por_label = iara.my_label(), alterado_em = now() where codigo = p ->> 'codigo';
  if not found then raise exception 'Modelo não encontrado.' using errcode = 'P0002'; end if;
  perform iara.audit_event('MODELO_MENSAGEM', 'frequencia_modelo', p ->> 'codigo', null, 'Modelo de mensagem alterado: ' || (p ->> 'codigo') || '.');
  return jsonb_build_object('ok', true);
end $$;

create or replace function api.orgao_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  o iara.orgaos_destinatarios;
begin
  perform iara.require_perm('frequencia.parametros');
  if length(btrim(coalesce(p ->> 'nome', ''))) < 5 then raise exception 'Informe o nome do órgão.' using errcode = '22023'; end if;
  if coalesce(p ->> 'canal', '') not in ('PROTOCOLO_ELETRONICO', 'EMAIL_INSTITUCIONAL', 'INTEGRACAO') then raise exception 'Canal oficial inválido.' using errcode = '22023'; end if;
  if p ->> 'canal' = 'EMAIL_INSTITUCIONAL' and coalesce(p ->> 'endereco_canal', '') !~* '@[a-z0-9.-]+\.(gov|jus|mp|leg)\.br$|@[a-z0-9.-]*maringa\.pr\.gov\.br$' then
    raise exception 'E-mail institucional precisa ser de domínio público oficial (.gov.br, .jus.br, .mp.br).' using errcode = '22023';
  end if;
  if nullif(p ->> 'id', '') is null then
    insert into iara.orgaos_destinatarios (nome, tipo, competencia, territorio_ids, canal, endereco_canal)
    values (btrim(p ->> 'nome'), p ->> 'tipo', nullif(btrim(coalesce(p ->> 'competencia', '')), ''), coalesce(array(select jsonb_array_elements_text(p -> 'territorio_ids'))::int[], '{}'),
            p ->> 'canal', nullif(btrim(coalesce(p ->> 'endereco_canal', '')), '')) returning * into o;
  else
    -- mudar o canal desfaz a verificação
    update iara.orgaos_destinatarios set nome = btrim(p ->> 'nome'), tipo = p ->> 'tipo', competencia = nullif(btrim(coalesce(p ->> 'competencia', '')), ''),
           verificado = verificado and canal = p ->> 'canal' and endereco_canal is not distinct from nullif(btrim(coalesce(p ->> 'endereco_canal', '')), ''),
           canal = p ->> 'canal', endereco_canal = nullif(btrim(coalesce(p ->> 'endereco_canal', '')), ''), ativo = coalesce((p ->> 'ativo')::boolean, ativo)
    where id = (p ->> 'id')::uuid returning * into o;
  end if;
  if coalesce((p ->> 'verificar')::boolean, false) then
    update iara.orgaos_destinatarios set verificado = true, verificado_por_label = iara.my_label(), verificado_em = now() where id = o.id returning * into o;
  end if;
  perform iara.audit_event('ORGAO_DESTINATARIO', 'orgao', o.id::text, null, 'Órgão destinatário salvo' || case when o.verificado then ' e verificado' else '' end || ': ' || o.nome || '.');
  return to_jsonb(o);
end $$;

-- indicadores agregados (sociedade e controle externo): sem identificar crianças
create or replace function api.busca_ativa_indicadores(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if not (iara.has_perm('kpi.network') or iara.has_perm('busca_ativa.read')) then raise exception 'Sem permissão.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'ausencias_30d', (select count(*) from iara.frequencia_ausencias where data >= iara.hoje_local() - 30 and situacao <> 'ERRO_CORRIGIDO'),
    'respondidas_pct', (select round(100.0 * count(*) filter (where respondido_em is not null) / nullif(count(*), 0), 1) from iara.frequencia_ausencias where data >= iara.hoje_local() - 30),
    'motivos', (select coalesce(jsonb_object_agg(motivo, n), '{}') from (select motivo, count(*) n from iara.frequencia_ausencias where motivo is not null and data >= iara.hoje_local() - 30 group by 1) z),
    'casos_abertos', (select count(*) from iara.busca_ativa_casos where situacao in ('ABERTO', 'EM_ACOMPANHAMENTO')),
    'casos_retorno', (select count(*) from iara.busca_ativa_casos where situacao in ('RETORNOU') or (situacao = 'ENCERRADO' and resultado ilike '%retorn%')),
    'notificacoes_legais_enviadas', (select count(*) from iara.encaminhamentos where tipo = 'CONSELHO_TUTELAR' and situacao in ('ENVIADO', 'RECEBIDO', 'RETORNO_REGISTRADO')),
    'notificacoes_legais_pendentes', (select count(*) from iara.encaminhamentos where tipo = 'CONSELHO_TUTELAR' and situacao in ('AGUARDANDO_APROVACAO', 'APROVADO', 'FALHA_ENVIO')));
end $$;

-- 8. A chamada concluída dispara o processamento da turma (mesmo dia) ------------------------------------------------------------------
create or replace function api.frequencia_lancar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.classes;
  v_dia date := coalesce(nullif(p ->> 'data', '')::date, current_date);
  v_reg uuid;
  v_faltas uuid[];
  v_ba jsonb;
begin
  select * into c from iara.classes where id = (p ->> 'class_id')::uuid;
  if c.id is null or not iara.turma_acesso(c.id, 'frequencia.write') then
    raise exception 'Você não pode lançar a chamada desta turma.' using errcode = '42501';
  end if;
  if v_dia > current_date then raise exception 'Não dá para lançar chamada de dia futuro.' using errcode = '22023'; end if;
  if not iara.dia_letivo(v_dia, c.unit_id) then raise exception 'Este dia não é letivo.' using errcode = '22023'; end if;
  select coalesce(array_agg(x::uuid), '{}') into v_faltas from jsonb_array_elements_text(coalesce(p -> 'faltas', '[]'::jsonb)) x;
  if exists (select 1 from unnest(v_faltas) f where not exists (select 1 from iara.enrollments e where e.class_id = c.id and e.student_id = f and e.status = 'ACTIVE')) then
    raise exception 'Há aluno que não pertence a esta turma.' using errcode = '22023';
  end if;
  insert into iara.frequencia_registros (class_id, data, registrado_por, registrado_label, is_demo)
  values (c.id, v_dia, iara.current_user_id(), iara.my_label(), false)
  on conflict (class_id, data) do update set registrado_por = excluded.registrado_por, registrado_label = excluded.registrado_label, registrado_em = now(), is_demo = false
  returning id into v_reg;
  -- falta justificada (atestado) não vira falta simples ao relançar
  delete from iara.frequencia_faltas where registro_id = v_reg and student_id <> all (v_faltas);
  insert into iara.frequencia_faltas (registro_id, student_id, tipo, is_demo)
  select v_reg, f, 'FALTA', false from unnest(v_faltas) f on conflict do nothing;
  perform iara.audit_event('FREQUENCIA_LANCADA', 'class', c.id::text, c.unit_id,
    format('Chamada de %s lançada (%s falta(s)).', to_char(v_dia, 'DD/MM/YYYY'), cardinality(v_faltas)));
  perform iara.frequencia_detectar_alertas(c.unit_id);
  -- chamada concluída: contato com os responsáveis no mesmo dia (e correção se a presença foi corrigida)
  v_ba := iara.busca_ativa_processar(c.id, v_dia);
  return api.frequencia_turma(jsonb_build_object('class_id', c.id, 'data', v_dia)) || jsonb_build_object('busca_ativa', v_ba);
end $$;

-- 9. Classificação ---------------------------------------------------------------------------------------------------------------
insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('frequencia_ausencias', 'motivo', 'SENSIVEL', 'saúde/vida familiar da criança', 'acompanhamento da frequência', 'unidade e equipe da busca ativa'),
  ('frequencia_ausencias', 'motivo_texto', 'SENSIVEL', 'relato da família', 'acompanhamento e proteção', 'unidade e equipe autorizada'),
  ('frequencia_ausencias', 'classificado_por_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('frequencia_contatos', 'texto', 'PESSOAL', 'comunicação com a família', 'contato sobre ausência', 'unidade'),
  ('frequencia_contatos', 'falha_motivo', 'INTERNO', 'operação', 'entrega', null),
  ('frequencia_tarefas', 'descricao', 'PESSOAL', 'acompanhamento', 'busca ativa', 'unidade'),
  ('frequencia_tarefas', 'resultado', 'SENSIVEL', 'acompanhamento e proteção', 'busca ativa', 'unidade e equipe autorizada'),
  ('frequencia_tarefas', 'concluida_por_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('busca_ativa_casos', 'motivo_abertura', 'SENSIVEL', 'proteção da criança', 'busca ativa', 'unidade e equipe autorizada'),
  ('busca_ativa_casos', 'encerramento_motivo', 'SENSIVEL', 'proteção da criança', 'busca ativa', 'unidade e equipe autorizada'),
  ('busca_ativa_casos', 'resultado', 'SENSIVEL', 'proteção da criança', 'busca ativa', 'unidade e equipe autorizada'),
  ('busca_ativa_casos', 'responsavel_label', 'PESSOAL', 'identificação', 'responsável pelo caso', null),
  ('busca_ativa_eventos', 'texto', 'SENSIVEL', 'proteção da criança', 'busca ativa', 'unidade e equipe autorizada'),
  ('busca_ativa_eventos', 'autor_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('encaminhamentos', 'conteudo', 'SENSIVEL', 'expediente de proteção', 'encaminhamento à rede e ao Conselho Tutelar', 'só destinatário verificado e canal oficial'),
  ('encaminhamentos', 'necessidade', 'SENSIVEL', 'proteção da criança', 'encaminhamento', 'equipe autorizada'),
  ('encaminhamentos', 'retorno_texto', 'SENSIVEL', 'proteção da criança', 'encaminhamento', 'equipe autorizada'),
  ('encaminhamentos', 'cancelamento_motivo', 'INTERNO', 'operação', 'encaminhamento', null),
  ('encaminhamentos', 'criado_por_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('encaminhamentos', 'aprovado_por_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('frequencia_afastamentos', 'motivo', 'SENSIVEL', 'saúde/vida familiar', 'afastamento acompanhado', 'unidade (sem diagnóstico)'),
  ('frequencia_afastamentos', 'registrado_por_label', 'PESSOAL', 'identificação', 'auditoria', null)
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

revoke all on function iara.busca_ativa_processar(uuid, date), iara.busca_ativa_limite_legal(integer), iara.ba_enviar(uuid), iara.ba_expediente(uuid, uuid, text) from public;

commit;
