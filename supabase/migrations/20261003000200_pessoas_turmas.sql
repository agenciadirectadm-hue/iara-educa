-- IARA Educa — 002 · Pessoas (aluno/responsável 360º), turmas, matrículas e profissionais
-- Todos os dados pessoais do ambiente de demonstração são fictícios (is_demo = true).
begin;

create sequence iara.student_registry_seq start 202600001;

-- Endereços normalizados (geocodificados)
create table iara.addresses (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null references iara.tenants(id),
  street text not null,
  number text,
  complement text,
  neighborhood text,
  postal_code text,
  city text not null default 'Maringá',
  state char(2) not null default 'PR',
  location extensions.geography(Point, 4326),
  geocode_precision text not null default 'DEMO_APROXIMADO',
  geocode_source text not null default 'DEMO',
  territory_id integer references iara.territories(id),
  is_demo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index addresses_location_idx on iara.addresses using gist (location);
create trigger addresses_touch before update on iara.addresses
  for each row execute function iara.touch_updated_at();

-- Responsáveis
create table iara.guardians (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null references iara.tenants(id),
  full_name text not null,
  social_name text,
  cpf text,
  nis text,
  birth_date date,
  gender char(1),
  email text,
  primary_phone text,
  whatsapp_phone text,
  preferred_contact_channel text not null default 'WHATSAPP',
  address_id uuid references iara.addresses(id),
  occupation text,
  employment_status text,
  family_income numeric(10, 2),
  income_bracket text,
  cadunico_status boolean not null default false,
  benefits jsonb not null default '[]'::jsonb,
  education_level text,
  household_size smallint,
  accessibility_needs text,
  consent_flags jsonb not null default '{}'::jsonb,
  is_demo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid
);
create index guardians_name_trgm_idx on iara.guardians using gin (iara.norm(full_name) extensions.gin_trgm_ops);
create index guardians_address_idx on iara.guardians(address_id);
create trigger guardians_touch before update on iara.guardians
  for each row execute function iara.touch_updated_at();

-- Alunos (dados sensíveis ficam em student_sensitive, com permissão específica)
create table iara.students (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null references iara.tenants(id),
  full_name text not null,
  social_name text,
  birth_date date not null,
  gender char(1),
  student_registry_number text not null unique default (nextval('iara.student_registry_seq')::text),
  status text not null default 'SEM_VINCULO' check (status in ('MATRICULADO', 'AGUARDANDO_VAGA', 'TRANSFERENCIA', 'SEM_VINCULO', 'INATIVO')),
  current_enrollment_id uuid,
  address_id uuid references iara.addresses(id),
  transport_need boolean not null default false,
  school_transport_status text,
  aee_status boolean not null default false,
  accessibility_needs text,
  avatar_seed integer not null default (floor(random() * 1000))::int,
  is_demo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid
);
create index students_name_trgm_idx on iara.students using gin (iara.norm(full_name) extensions.gin_trgm_ops);
create index students_address_idx on iara.students(address_id);
create trigger students_touch before update on iara.students
  for each row execute function iara.touch_updated_at();

create table iara.student_sensitive (
  student_id uuid primary key references iara.students(id) on delete cascade,
  special_education_need text,
  medical_alerts text,
  food_allergies text,
  legal_notes text,
  updated_at timestamptz not null default now()
);

create table iara.student_guardians (
  student_id uuid not null references iara.students(id) on delete cascade,
  guardian_id uuid not null references iara.guardians(id) on delete cascade,
  relationship text not null,
  is_primary boolean not null default true,
  can_pick_up boolean not null default true,
  can_receive_notifications boolean not null default true,
  legal_authority_status text not null default 'CONFIRMADO',
  start_date date not null default current_date,
  end_date date,
  primary key (student_id, guardian_id)
);
create index student_guardians_guardian_idx on iara.student_guardians(guardian_id);

-- Profissionais (demonstração — nomes fictícios)
create table iara.staff (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null references iara.tenants(id),
  unit_id integer references iara.education_units(id),
  full_name text not null,
  role text not null check (role in ('PROFESSOR', 'EDUCADOR', 'AUXILIAR', 'APOIO', 'AEE', 'ESTAGIARIO', 'SUBSTITUTO')),
  bond text,
  is_demo boolean not null default true,
  created_at timestamptz not null default now()
);
create index staff_unit_idx on iara.staff(unit_id);

-- Turmas — núcleo operacional.
-- Ambiente demo: quantidade de turmas por série e matrículas vêm do Censo 2025 (oficial);
-- a divisão por turma, o turno por turma e a capacidade autorizada são DEMONSTRAÇÃO (pendentes SEDUC).
create table iara.classes (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null references iara.tenants(id),
  school_year smallint not null,
  unit_id integer not null references iara.education_units(id),
  stage_id smallint not null references iara.education_stages(id),
  grade_level_id smallint not null references iara.grade_levels(id),
  class_code text not null,
  class_name text not null,
  shift text not null check (shift in ('MANHA', 'TARDE', 'NOITE', 'INTEGRAL')),
  modality text not null default 'REGULAR',
  room_label text,
  authorized_capacity integer not null check (authorized_capacity >= 0),
  active_enrollments_count integer not null default 0,
  blocked_seats_count integer not null default 0,
  reserved_seats_count integer not null default 0,
  physical_vacancies_count integer generated always as (greatest(authorized_capacity - active_enrollments_count, 0)) stored,
  offerable_vacancies_count integer generated always as (
    greatest(greatest(authorized_capacity - active_enrollments_count, 0) - blocked_seats_count - reserved_seats_count, 0)
  ) stored,
  status text not null default 'ATIVA' check (status in ('ATIVA', 'EM_REORGANIZACAO', 'ENCERRADA')),
  source text not null,
  source_updated_at timestamptz,
  confidence_status text not null default 'DEMO',
  is_demo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (unit_id, school_year, class_code)
);
create index classes_unit_grade_idx on iara.classes(unit_id, grade_level_id);
create index classes_grade_idx on iara.classes(grade_level_id) where status = 'ATIVA';
create trigger classes_touch before update on iara.classes
  for each row execute function iara.touch_updated_at();

create table iara.class_staff (
  class_id uuid not null references iara.classes(id) on delete cascade,
  staff_id uuid not null references iara.staff(id) on delete cascade,
  role_type text not null,
  is_primary boolean not null default false,
  hours_per_week smallint,
  start_date date not null default date '2026-02-02',
  end_date date,
  primary key (class_id, staff_id)
);
create index class_staff_staff_idx on iara.class_staff(staff_id);

create table iara.enrollments (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null references iara.tenants(id),
  student_id uuid not null references iara.students(id) on delete cascade,
  class_id uuid not null references iara.classes(id),
  unit_id integer not null references iara.education_units(id),
  school_year smallint not null,
  status text not null check (status in ('PRE_ENROLLMENT', 'ACTIVE', 'TRANSFER_PENDING', 'TRANSFERRED', 'CANCELLED', 'COMPLETED', 'INACTIVE')),
  enrollment_date date not null default current_date,
  start_date date,
  end_date date,
  entry_type text not null default 'NOVA' check (entry_type in ('NOVA', 'RENOVACAO', 'TRANSFERENCIA', 'OFERTA_FILA')),
  exit_type text,
  source_protocol_id uuid,
  previous_enrollment_id uuid references iara.enrollments(id),
  is_demo boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index enrollments_student_idx on iara.enrollments(student_id);
create index enrollments_class_active_idx on iara.enrollments(class_id) where status = 'ACTIVE';
create index enrollments_unit_idx on iara.enrollments(unit_id, status);
create trigger enrollments_touch before update on iara.enrollments
  for each row execute function iara.touch_updated_at();

alter table iara.students
  add constraint students_current_enrollment_fk foreign key (current_enrollment_id) references iara.enrollments(id) on delete set null;

commit;
