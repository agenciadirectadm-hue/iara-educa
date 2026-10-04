-- IARA Educa — 001 · Base: extensões, schemas e dados públicos de referência
-- Regra de ouro: dados oficiais/públicos nunca são inventados; dados operacionais fictícios
-- vivem em tabelas próprias e são marcados com is_demo = true / confidence_status = 'DEMO'.
begin;

create extension if not exists postgis with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;
create extension if not exists pgcrypto with schema extensions;

create schema if not exists iara;
create schema if not exists api;
comment on schema iara is 'IARA Educa — modelo de domínio (não exposto diretamente)';
comment on schema api is 'IARA Educa — funções expostas pelo gateway (Edge Function api)';

-- Postgres concede EXECUTE a PUBLIC por padrão; aqui tudo é explícito.
alter default privileges in schema iara revoke execute on functions from public;
alter default privileges in schema api revoke execute on functions from public;

create or replace function iara.f_unaccent(text) returns text
language sql immutable parallel safe strict
set search_path = extensions, public
as $$ select extensions.unaccent('extensions.unaccent'::regdictionary, $1) $$;

create or replace function iara.norm(text) returns text
language sql immutable parallel safe
as $$ select lower(iara.f_unaccent(coalesce($1, ''))) $$;

create or replace function iara.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Tenancy e lotes de importação
-- ---------------------------------------------------------------------------
create table iara.tenants (
  id smallint primary key,
  name text not null,
  state char(2) not null,
  ibge_code text,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table iara.import_batches (
  id text primary key,
  source_file text not null,
  description text,
  row_counts jsonb not null default '{}'::jsonb,
  imported_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Territórios (macrorregiões calculadas, bairros e distritos)
-- ---------------------------------------------------------------------------
create table iara.territories (
  id integer primary key,
  tenant_id smallint not null references iara.tenants(id),
  code text not null,
  name text not null,
  kind text not null check (kind in ('MACRORREGIAO', 'BAIRRO', 'DISTRITO')),
  parent_id integer references iara.territories(id),
  center extensions.geography(Point, 4326),
  geom extensions.geography(MultiPolygon, 4326),
  color text,
  sort smallint not null default 0,
  source text not null,
  confidence_status text not null,
  unique (tenant_id, code)
);
create index territories_parent_idx on iara.territories(parent_id);

-- ---------------------------------------------------------------------------
-- Hierarquia educacional parametrizável
-- ---------------------------------------------------------------------------
create table iara.education_stages (
  id smallint primary key,
  tenant_id smallint not null references iara.tenants(id),
  code text not null,
  name text not null,
  short_name text not null,
  color text,
  sort smallint not null,
  unique (tenant_id, code)
);

create table iara.grade_levels (
  id smallint primary key,
  tenant_id smallint not null references iara.tenants(id),
  stage_id smallint not null references iara.education_stages(id),
  code text not null,
  name text not null,
  short_name text not null,
  census_label text,
  min_age_months integer,
  max_age_months integer,
  reference_capacity integer,
  sort smallint not null,
  unique (tenant_id, code)
);

-- ---------------------------------------------------------------------------
-- Unidades educacionais (118 registros reais — seed do XLSX)
-- ---------------------------------------------------------------------------
create table iara.education_units (
  id integer primary key,
  tenant_id smallint not null references iara.tenants(id),
  name text not null,
  short_name text not null,
  inep_name text,
  unit_type text not null check (unit_type in ('CMEI', 'ESCOLA')),
  unit_type_label text not null,
  status text not null check (status in ('ATIVA', 'A_VALIDAR', 'SEM_TURMAS')),
  status_label text not null,
  address_line text,
  neighborhood text,
  postal_code text,
  city text not null default 'Maringá',
  state char(2) not null default 'PR',
  location extensions.geography(Point, 4326) not null,
  lat double precision not null,
  lng double precision not null,
  macro_territory_id integer references iara.territories(id),
  neighborhood_territory_id integer references iara.territories(id),
  inep_code text,
  director_name text,
  director_status text,
  director_source text,
  phone text,
  stages_text text,
  offers_text text,
  public_classes integer,
  public_enrollments integer,
  census_classes integer,
  census_enrollments integer,
  census_teachers integer,
  census_status text,
  census_special_ed_enrollments integer,
  public_capacity integer,
  public_detail text,
  data_reference text,
  data_status text,
  main_source text,
  address_confidence text,
  address_source text,
  geo_status text,
  geo_source text,
  geo_note text,
  geo_precision text not null default 'VALIDADO' check (geo_precision in ('VALIDADO', 'APROXIMADO', 'PROVISORIO')),
  cep_source text,
  seduc_confirmation_status text,
  confidence_status text not null default 'PUBLIC_OFFICIAL',
  source_date text,
  import_batch_id text references iara.import_batches(id),
  service_radius_m integer not null default 2000,
  has_aee boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index education_units_location_idx on iara.education_units using gist (location);
create index education_units_name_trgm_idx on iara.education_units using gin (iara.norm(name) extensions.gin_trgm_ops);
create index education_units_macro_idx on iara.education_units(macro_territory_id);
create trigger education_units_touch before update on iara.education_units
  for each row execute function iara.touch_updated_at();

-- Nível 2 — oferta por unidade (fonte pública: Consulta Escolas/SEED-PR 2026 ou Censo 2025)
create table iara.unit_offers (
  id serial primary key,
  unit_id integer not null references iara.education_units(id) on delete cascade,
  offer_name text not null,
  stage_code text,
  classes_count integer,
  enrollments_count integer,
  reference_date text,
  confidence_text text,
  source text,
  note text
);
create index unit_offers_unit_idx on iara.unit_offers(unit_id);

-- Nível 3 — série/faixa real (Microdados do Censo Escolar 2025)
create table iara.unit_grade_stats (
  id serial primary key,
  unit_id integer not null references iara.education_units(id) on delete cascade,
  stage_name text not null,
  grade_name text not null,
  grade_level_id smallint references iara.grade_levels(id),
  classes_count integer not null,
  enrollments_count integer not null,
  avg_per_class numeric(6, 2),
  reference_year smallint not null,
  source text not null,
  status text not null
);
create index unit_grade_stats_unit_idx on iara.unit_grade_stats(unit_id);

-- Turnos agregados por etapa (Censo 2025)
create table iara.unit_shift_stats (
  id serial primary key,
  unit_id integer not null references iara.education_units(id) on delete cascade,
  stage_name text not null,
  stage_id smallint references iara.education_stages(id),
  grade_level_id smallint references iara.grade_levels(id),
  shift text not null,
  classes_count integer not null,
  enrollments_count integer not null,
  reference_year smallint not null,
  source text not null,
  limitation text
);
create index unit_shift_stats_unit_idx on iara.unit_shift_stats(unit_id);

-- Pendências e qualidade do dado
create table iara.data_quality_issues (
  id serial primary key,
  tenant_id smallint not null references iara.tenants(id),
  issue_type text not null,
  severity text not null check (severity in ('ALTA', 'MEDIA', 'BAIXA')),
  unit_id integer references iara.education_units(id),
  title text not null,
  description text,
  source text,
  action text,
  status text not null default 'ABERTA' check (status in ('ABERTA', 'EM_ANALISE', 'RESOLVIDA')),
  created_at timestamptz not null default now()
);
create index data_quality_issues_unit_idx on iara.data_quality_issues(unit_id);

-- Métricas de composição visual (DEMO) — nunca tratadas como oficiais
create table iara.demo_metrics (
  key text primary key,
  tenant_id smallint not null references iara.tenants(id),
  label text not null,
  value numeric not null,
  source text not null,
  note text
);

create table iara.feature_flags (
  code text primary key,
  tenant_id smallint not null references iara.tenants(id),
  enabled boolean not null,
  description text not null
);

commit;
