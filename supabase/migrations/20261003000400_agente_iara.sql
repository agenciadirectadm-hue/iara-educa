-- IARA Educa — 004 · Agente resolutiva IARA (capítulo 74): conversas, mensagens, conhecimento e rastreabilidade
begin;

create table iara.conversations (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null references iara.tenants(id),
  channel text not null check (channel in ('WHATSAPP_SIMULADO', 'PORTAL')),
  guardian_id uuid references iara.guardians(id) on delete set null,
  owner_user_id uuid,
  contact_label text not null,
  contact_phone_masked text,
  state text not null default 'BOT_ACTIVE' check (state in ('BOT_ACTIVE', 'HUMAN_PENDING', 'HUMAN_ACTIVE', 'FOLLOWUP_PENDING', 'CLOSED')),
  assigned_user_id uuid,
  assigned_label text,
  active_student_id uuid references iara.students(id) on delete set null,
  active_case_id uuid references iara.service_cases(id) on delete set null,
  intent text,
  context jsonb not null default '{}'::jsonb,
  summary text,
  identity_verified boolean not null default false,
  last_message_at timestamptz not null default now(),
  is_demo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index conversations_state_idx on iara.conversations(state, last_message_at desc);
create index conversations_guardian_idx on iara.conversations(guardian_id);
create index conversations_owner_idx on iara.conversations(owner_user_id);
create trigger conversations_touch before update on iara.conversations
  for each row execute function iara.touch_updated_at();

create table iara.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references iara.conversations(id) on delete cascade,
  direction text not null check (direction in ('IN', 'OUT')),
  sender_type text not null check (sender_type in ('CIDADAO', 'IARA', 'OPERADOR', 'SISTEMA')),
  sender_label text,
  body text not null,
  payload jsonb not null default '{}'::jsonb,
  channel_message_id text,
  status text not null default 'ENTREGUE' check (status in ('ENVIADA', 'ENTREGUE', 'LIDA', 'FALHOU')),
  created_at timestamptz not null default now()
);
create index messages_conversation_idx on iara.messages(conversation_id, created_at);

-- Base de conhecimento oficial (fluxo editorial; apenas PUBLICADO e vigente orienta procedimentos)
create table iara.knowledge_articles (
  id serial primary key,
  tenant_id smallint not null references iara.tenants(id),
  service_code text references iara.service_catalog(code),
  title text not null,
  body text not null,
  keywords text[] not null default '{}',
  audience text not null default 'PUBLICO' check (audience in ('PUBLICO', 'INTERNO')),
  source text not null,
  owner_sector text not null,
  version text not null,
  approved_at date,
  valid_from date not null,
  valid_until date,
  review_due date,
  status text not null check (status in ('RASCUNHO', 'REVISAO', 'APROVADO', 'PUBLICADO', 'EXPIRADO')),
  is_demo boolean not null default true
);

-- Execuções de ferramentas da agente (entradas/saídas minimizadas; sem raciocínio interno)
create table iara.tool_executions (
  id bigserial primary key,
  conversation_id uuid references iara.conversations(id) on delete cascade,
  tool_name text not null,
  input jsonb not null default '{}'::jsonb,
  output jsonb not null default '{}'::jsonb,
  status text not null check (status in ('OK', 'ERRO', 'NEGADO')),
  error text,
  correlation_id text,
  idempotency_key text,
  duration_ms integer,
  user_id uuid,
  created_at timestamptz not null default now()
);
create index tool_executions_conversation_idx on iara.tool_executions(conversation_id, created_at);

create table iara.handoff_tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null references iara.tenants(id),
  conversation_id uuid not null references iara.conversations(id) on delete cascade,
  case_id uuid references iara.service_cases(id) on delete set null,
  reason text not null,
  sector text not null default 'CENTRAL_VAGAS',
  status text not null default 'ABERTA' check (status in ('ABERTA', 'ASSUMIDA', 'CONCLUIDA')),
  assigned_user_id uuid,
  summary text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index handoff_tasks_status_idx on iara.handoff_tasks(status);

commit;
