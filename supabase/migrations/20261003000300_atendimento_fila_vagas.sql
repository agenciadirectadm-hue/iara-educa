-- IARA Educa — 003 · CRM público, catálogo de serviços, motor de regras, fila, ofertas, vagas e documentos
begin;

create sequence iara.protocol_seq start 1;

-- Catálogo oficial de serviços (conteúdo de demonstração a validar pela SEDUC)
create table iara.service_catalog (
  code text primary key,
  tenant_id smallint not null references iara.tenants(id),
  name text not null,
  description text not null,
  audience text not null default 'CIDADAO',
  requirements text,
  required_documents text[] not null default '{}',
  sector text not null,
  sla_days smallint not null,
  actions text[] not null default '{}',
  source text not null,
  is_demo boolean not null default true,
  sort smallint not null default 0
);

-- Protocolos / atendimentos
create table iara.service_cases (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null references iara.tenants(id),
  protocol_number text not null unique,
  case_type text not null references iara.service_catalog(code),
  channel text not null check (channel in ('WEB', 'WHATSAPP', 'PRESENCIAL', 'TELEFONE', 'EMAIL', 'ESCOLA', 'CMEI', 'CENTRAL_VAGAS', 'API')),
  status text not null check (status in (
    'NOVO', 'EM_ANALISE', 'AGUARDANDO_DOCUMENTOS', 'AGUARDANDO_FAMILIA', 'VAGA_ENCONTRADA',
    'VAGA_OFERTADA', 'EM_FILA', 'MATRICULA_CONCLUIDA', 'NAO_ATENDIDO', 'RECURSO', 'ENCERRADO')),
  priority text not null default 'NORMAL' check (priority in ('NORMAL', 'ALTA', 'URGENTE')),
  student_id uuid references iara.students(id),
  guardian_id uuid references iara.guardians(id),
  unit_id integer references iara.education_units(id),
  assigned_team text not null default 'CENTRAL_VAGAS',
  assigned_user_id uuid,
  subject text not null,
  description text,
  opened_at timestamptz not null default now(),
  sla_due_at timestamptz,
  closed_at timestamptz,
  resolution_code text,
  resolution_notes text,
  idempotency_key text unique,
  is_demo boolean not null default true,
  created_by uuid,
  updated_at timestamptz not null default now()
);
create index service_cases_status_idx on iara.service_cases(status);
create index service_cases_student_idx on iara.service_cases(student_id);
create index service_cases_guardian_idx on iara.service_cases(guardian_id);
create index service_cases_unit_idx on iara.service_cases(unit_id);
create index service_cases_opened_idx on iara.service_cases(opened_at desc);
create trigger service_cases_touch before update on iara.service_cases
  for each row execute function iara.touch_updated_at();

create table iara.case_events (
  id bigserial primary key,
  case_id uuid not null references iara.service_cases(id) on delete cascade,
  event_type text not null,
  message text not null,
  old_value text,
  new_value text,
  user_id uuid,
  actor_label text,
  visibility text not null default 'INTERNA' check (visibility in ('INTERNA', 'CIDADAO')),
  occurred_at timestamptz not null default now()
);
create index case_events_case_idx on iara.case_events(case_id, occurred_at);

-- Motor de regras determinístico (versionado, com vigência e fonte)
create table iara.rules (
  id serial primary key,
  tenant_id smallint not null references iara.tenants(id),
  rule_code text not null,
  version text not null,
  name text not null,
  description text not null,
  rule_type text not null check (rule_type in ('ELIMINATORIA', 'PONTUACAO_UNIDADE', 'PRIORIDADE_FILA', 'DESEMPATE', 'PARAMETRO')),
  condition jsonb not null default '{}'::jsonb,
  weight numeric not null default 0,
  source text not null,
  justification text,
  valid_from date not null,
  valid_to date,
  is_active boolean not null default true,
  test_reference text,
  sort smallint not null default 0,
  unique (tenant_id, rule_code, version)
);

-- Fila de espera
create table iara.waiting_list_entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null references iara.tenants(id),
  student_id uuid not null references iara.students(id) on delete cascade,
  case_id uuid references iara.service_cases(id),
  stage_id smallint not null references iara.education_stages(id),
  grade_level_id smallint not null references iara.grade_levels(id),
  preferred_unit_id integer not null references iara.education_units(id),
  alternative_unit_ids integer[] not null default '{}',
  territory_id integer references iara.territories(id),
  preferred_shift text,
  full_time_requested boolean not null default false,
  demand_category text not null check (demand_category in (
    'SEM_ATENDIMENTO', 'AGUARDA_TRANSFERENCIA', 'PARCIAL_PARA_INTEGRAL', 'UNIDADE_PREFERENCIAL', 'RECUSOU_OFERTA', 'DEMANDA_FUTURA')),
  priority_flags text[] not null default '{}',
  priority_score numeric not null default 0,
  score_breakdown jsonb not null default '[]'::jsonb,
  home_distance_m integer,
  position integer,
  status text not null default 'WAITING' check (status in (
    'WAITING', 'OFFERED', 'ACCEPTED', 'DECLINED', 'EXPIRED', 'SUSPENDED', 'CANCELLED', 'MATRICULATED')),
  entered_at timestamptz not null default now(),
  last_recalculated_at timestamptz,
  rule_version text,
  is_demo boolean not null default true,
  created_by uuid,
  updated_at timestamptz not null default now()
);
create index waiting_list_queue_idx on iara.waiting_list_entries(preferred_unit_id, grade_level_id, status);
create index waiting_list_student_idx on iara.waiting_list_entries(student_id);
create index waiting_list_status_idx on iara.waiting_list_entries(status);
create trigger waiting_list_touch before update on iara.waiting_list_entries
  for each row execute function iara.touch_updated_at();

-- Bloqueios de vaga (motivo obrigatório)
create table iara.vacancy_blocks (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null references iara.tenants(id),
  class_id uuid not null references iara.classes(id) on delete cascade,
  seats integer not null check (seats > 0),
  reason text not null check (reason in (
    'INCLUSAO', 'DECISAO_JUDICIAL', 'ADAPTACAO_SALA', 'RESERVA_ADMINISTRATIVA', 'REORGANIZACAO', 'OBRA', 'AUSENCIA_PROFISSIONAL', 'OUTRO')),
  justification text not null check (length(justification) >= 10),
  valid_until date,
  is_demo boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  released_at timestamptz,
  released_by uuid
);
create index vacancy_blocks_class_idx on iara.vacancy_blocks(class_id) where released_at is null;

-- Ofertas de vaga
create table iara.vacancy_offers (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null references iara.tenants(id),
  waiting_list_entry_id uuid references iara.waiting_list_entries(id),
  student_id uuid not null references iara.students(id) on delete cascade,
  class_id uuid not null references iara.classes(id),
  unit_id integer not null references iara.education_units(id),
  case_id uuid references iara.service_cases(id),
  offered_at timestamptz not null default now(),
  expires_at timestamptz not null,
  channel text not null default 'WHATSAPP',
  status text not null check (status in ('OFFERED', 'ACCEPTED', 'DECLINED', 'EXPIRED', 'CANCELLED', 'ENROLLED')),
  accepted_at timestamptz,
  declined_at timestamptz,
  decline_reason text,
  response_channel text,
  ranking_snapshot jsonb not null default '{}'::jsonb,
  idempotency_key text unique,
  is_demo boolean not null default true,
  created_by uuid,
  updated_at timestamptz not null default now()
);
create index vacancy_offers_class_idx on iara.vacancy_offers(class_id, status);
create index vacancy_offers_student_idx on iara.vacancy_offers(student_id);
create index vacancy_offers_status_idx on iara.vacancy_offers(status);
create trigger vacancy_offers_touch before update on iara.vacancy_offers
  for each row execute function iara.touch_updated_at();

-- Movimentação de vagas (antes/depois)
create table iara.vacancy_events (
  id bigserial primary key,
  tenant_id smallint not null references iara.tenants(id),
  class_id uuid references iara.classes(id) on delete cascade,
  unit_id integer references iara.education_units(id),
  event_type text not null check (event_type in (
    'MATRICULA', 'CANCELAMENTO', 'TRANSF_SAIDA', 'TRANSF_ENTRADA', 'BLOQUEIO', 'DESBLOQUEIO', 'RESERVA', 'LIBERACAO',
    'ALTERACAO_CAPACIDADE', 'CORRECAO')),
  quantity integer not null default 1,
  before_json jsonb,
  after_json jsonb,
  reference text,
  user_id uuid,
  actor_label text,
  occurred_at timestamptz not null default now()
);
create index vacancy_events_class_idx on iara.vacancy_events(class_id, occurred_at desc);

-- Documentos (somente metadados no ambiente demo)
create table iara.documents (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null references iara.tenants(id),
  student_id uuid references iara.students(id) on delete cascade,
  guardian_id uuid references iara.guardians(id) on delete cascade,
  case_id uuid references iara.service_cases(id) on delete set null,
  doc_type text not null check (doc_type in (
    'CERTIDAO', 'CPF', 'RG', 'COMPROVANTE_ENDERECO', 'CARTAO_SUS', 'VACINACAO', 'CADUNICO', 'DECLARACAO_TRABALHO',
    'LAUDO', 'GUARDA', 'DECISAO_JUDICIAL', 'TRANSFERENCIA')),
  status text not null check (status in ('PENDENTE', 'RECEBIDO', 'VALIDADO', 'REJEITADO', 'VENCIDO')),
  file_name text,
  received_at timestamptz,
  validated_at timestamptz,
  validated_by uuid,
  notes text,
  is_sensitive boolean not null default false,
  is_demo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index documents_student_idx on iara.documents(student_id);
create index documents_case_idx on iara.documents(case_id);
create trigger documents_touch before update on iara.documents
  for each row execute function iara.touch_updated_at();

-- Notificações (no demo: simuladas, nenhuma mensagem real é enviada)
create table iara.notifications (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null references iara.tenants(id),
  guardian_id uuid references iara.guardians(id) on delete cascade,
  student_id uuid references iara.students(id) on delete cascade,
  case_id uuid references iara.service_cases(id) on delete set null,
  channel text not null check (channel in ('WHATSAPP', 'SMS', 'EMAIL', 'PUSH', 'PORTAL')),
  event_type text not null,
  title text not null,
  body text not null,
  status text not null default 'SIMULADA' check (status in ('SIMULADA', 'ENVIADA', 'ENTREGUE', 'LIDA', 'FALHOU')),
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index notifications_guardian_idx on iara.notifications(guardian_id, created_at desc);

commit;
