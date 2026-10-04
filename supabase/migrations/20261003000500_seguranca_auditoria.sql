-- IARA Educa — 005 · Perfis configuráveis (RBAC + ABAC), sessões, contexto do usuário e auditoria imutável
begin;

-- ---------------------------------------------------------------------------
-- Perfis e permissões configuráveis (nada de cargos fixos no código — spec §5.1)
-- ---------------------------------------------------------------------------
create table iara.organizational_roles (
  code text primary key,
  tenant_id smallint not null references iara.tenants(id),
  name text not null,
  short_name text not null,
  description text not null,
  scope_type text not null check (scope_type in ('AGGREGATE', 'NETWORK', 'UNIT', 'GUARDIAN')),
  stage_filter text,
  question text,
  org_unit text,
  is_persona boolean not null default true,
  sort smallint not null default 0
);

create table iara.permissions (
  code text primary key,
  description text not null,
  is_sensitive boolean not null default false
);

create table iara.role_permissions (
  role_code text not null references iara.organizational_roles(code) on delete cascade,
  permission_code text not null references iara.permissions(code) on delete cascade,
  primary key (role_code, permission_code)
);

-- Usuários da aplicação. No modo demonstração cada visitante recebe um usuário próprio
-- (auth_provider = 'DEMO'); em produção: SSO municipal / gov.br / Entra ID.
create table iara.app_users (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null references iara.tenants(id),
  display_name text not null,
  role_code text not null references iara.organizational_roles(code),
  unit_id integer references iara.education_units(id),
  guardian_id uuid references iara.guardians(id) on delete set null,
  auth_provider text not null default 'DEMO',
  is_demo boolean not null default true,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz
);

create table iara.app_sessions (
  token_hash text primary key,
  user_id uuid not null references iara.app_users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  last_seen_at timestamptz not null default now(),
  user_agent text,
  revoked_at timestamptz
);
create index app_sessions_user_idx on iara.app_sessions(user_id);

-- ---------------------------------------------------------------------------
-- Contexto da requisição: o gateway define request.jwt.claims (sub) por transação,
-- no mesmo formato do PostgREST/Supabase Auth.
-- ---------------------------------------------------------------------------
create or replace function iara.current_user_id() returns uuid
language sql stable parallel safe
as $$ select (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid $$;

create or replace function iara.my_role() returns text
language sql stable security definer set search_path = iara, public
as $$ select role_code from iara.app_users where id = iara.current_user_id() $$;

create or replace function iara.my_scope() returns text
language sql stable security definer set search_path = iara, public
as $$
  select r.scope_type from iara.app_users u join iara.organizational_roles r on r.code = u.role_code
  where u.id = iara.current_user_id()
$$;

create or replace function iara.my_unit() returns integer
language sql stable security definer set search_path = iara, public
as $$ select unit_id from iara.app_users where id = iara.current_user_id() $$;

create or replace function iara.my_guardian() returns uuid
language sql stable security definer set search_path = iara, public
as $$ select guardian_id from iara.app_users where id = iara.current_user_id() $$;

create or replace function iara.my_label() returns text
language sql stable security definer set search_path = iara, public
as $$ select display_name from iara.app_users where id = iara.current_user_id() $$;

create or replace function iara.has_perm(p_code text) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select exists (
    select 1 from iara.app_users u
    join iara.role_permissions rp on rp.role_code = u.role_code
    where u.id = iara.current_user_id() and rp.permission_code = p_code
  )
$$;

create or replace function iara.require_perm(p_code text) returns void
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.current_user_id() is null then
    raise exception 'Sessão necessária para esta ação.' using errcode = '28000';
  end if;
  if not iara.has_perm(p_code) then
    raise exception 'Seu perfil não tem permissão para esta ação (%).', p_code using errcode = '42501';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- ABAC: escopo por unidade / vínculo responsável-aluno
-- ---------------------------------------------------------------------------
create or replace function iara.can_access_unit(p_unit integer) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select case iara.my_scope()
    when 'NETWORK' then true
    when 'AGGREGATE' then true
    when 'UNIT' then p_unit = iara.my_unit()
    else false
  end
$$;

create or replace function iara.can_access_student(p_student uuid) returns boolean
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_scope text := iara.my_scope();
  v_unit integer;
begin
  if v_scope is null then
    return false;
  elsif v_scope = 'GUARDIAN' then
    return exists (select 1 from iara.student_guardians sg
                   where sg.student_id = p_student and sg.guardian_id = iara.my_guardian() and sg.end_date is null);
  elsif not iara.has_perm('students.read') then
    return false;
  elsif v_scope = 'NETWORK' then
    return true;
  elsif v_scope = 'UNIT' then
    v_unit := iara.my_unit();
    return exists (select 1 from iara.enrollments e where e.student_id = p_student and e.unit_id = v_unit
                     and e.status in ('ACTIVE', 'PRE_ENROLLMENT', 'TRANSFER_PENDING'))
        or exists (select 1 from iara.waiting_list_entries w where w.student_id = p_student and w.preferred_unit_id = v_unit
                     and w.status in ('WAITING', 'OFFERED', 'ACCEPTED'))
        or exists (select 1 from iara.vacancy_offers o where o.student_id = p_student and o.unit_id = v_unit
                     and o.status in ('OFFERED', 'ACCEPTED', 'ENROLLED'))
        or exists (select 1 from iara.service_cases c where c.student_id = p_student and c.unit_id = v_unit);
  end if;
  return false;
end $$;

create or replace function iara.can_access_guardian(p_guardian uuid) returns boolean
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_scope text := iara.my_scope();
begin
  if v_scope is null then
    return false;
  elsif v_scope = 'GUARDIAN' then
    return p_guardian = iara.my_guardian();
  elsif not iara.has_perm('guardians.read') then
    return false;
  elsif v_scope = 'NETWORK' then
    return true;
  elsif v_scope = 'UNIT' then
    return exists (select 1 from iara.student_guardians sg
                   where sg.guardian_id = p_guardian and iara.can_access_student(sg.student_id));
  end if;
  return false;
end $$;

create or replace function iara.can_access_case(p_unit integer, p_student uuid, p_guardian uuid) returns boolean
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_scope text := iara.my_scope();
begin
  if v_scope is null then
    return false;
  elsif v_scope = 'GUARDIAN' then
    return p_guardian = iara.my_guardian()
        or (p_student is not null and exists (select 1 from iara.student_guardians sg
              where sg.student_id = p_student and sg.guardian_id = iara.my_guardian()));
  elsif not iara.has_perm('cases.read') then
    return false;
  elsif v_scope = 'NETWORK' then
    return true;
  elsif v_scope = 'UNIT' then
    return p_unit = iara.my_unit() or (p_student is not null and iara.can_access_student(p_student));
  end if;
  return false;
end $$;

-- ---------------------------------------------------------------------------
-- Auditoria imutável
-- ---------------------------------------------------------------------------
create table iara.audit_log (
  id bigserial primary key,
  tenant_id smallint not null default 1,
  user_id uuid,
  actor_label text,
  actor_role text,
  action text not null,
  entity_type text not null,
  entity_id text,
  unit_id integer,
  summary text,
  before_json jsonb,
  after_json jsonb,
  ip_address text,
  user_agent text,
  request_id text,
  occurred_at timestamptz not null default now()
);
create index audit_log_entity_idx on iara.audit_log(entity_type, entity_id);
create index audit_log_time_idx on iara.audit_log(occurred_at desc);
create index audit_log_user_idx on iara.audit_log(user_id);
create index audit_log_unit_idx on iara.audit_log(unit_id);

create or replace function iara.audit_immutable() returns trigger
language plpgsql as $$
begin
  raise exception 'A trilha de auditoria é imutável: % não é permitido.', tg_op using errcode = '42501';
end $$;
create trigger audit_log_no_update before update or delete on iara.audit_log
  for each row execute function iara.audit_immutable();

-- Registro de evento de negócio (oferta, exportação, visualização de dado sensível...)
create or replace function iara.audit_event(
  p_action text, p_entity_type text, p_entity_id text, p_unit integer, p_summary text,
  p_after jsonb default null, p_before jsonb default null
) returns void
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_user uuid := iara.current_user_id();
  v_label text;
  v_role text;
begin
  select display_name, role_code into v_label, v_role from iara.app_users where id = v_user;
  insert into iara.audit_log (user_id, actor_label, actor_role, action, entity_type, entity_id, unit_id, summary,
                              before_json, after_json, ip_address, user_agent, request_id)
  values (v_user, coalesce(v_label, 'Sistema'), v_role, p_action, p_entity_type, p_entity_id, p_unit, p_summary,
          p_before, p_after,
          nullif(current_setting('iara.ip', true), ''), nullif(current_setting('iara.ua', true), ''),
          nullif(current_setting('iara.request_id', true), ''));
end $$;

-- Trigger genérico de auditoria por linha. TG_ARGV[0]: colunas ignoradas (csv), p.ex. contadores.
create or replace function iara.audit_row() returns trigger
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_before jsonb;
  v_after jsonb;
  v_ignore text[] := array['updated_at'];
  v_changed text[];
  v_user uuid := iara.current_user_id();
  v_label text;
  v_role text;
  v_entity_id text;
  v_unit integer;
begin
  if coalesce(current_setting('iara.skip_audit', true), '') = 'on' then
    return coalesce(new, old);
  end if;
  if tg_nargs > 0 then
    v_ignore := v_ignore || string_to_array(tg_argv[0], ',');
  end if;
  if tg_op in ('UPDATE', 'DELETE') then v_before := to_jsonb(old); end if;
  if tg_op in ('INSERT', 'UPDATE') then v_after := to_jsonb(new); end if;

  if tg_op = 'UPDATE' then
    select coalesce(array_agg(k), '{}') into v_changed
    from jsonb_object_keys(v_after) k
    where not (k = any (v_ignore)) and (v_before -> k) is distinct from (v_after -> k);
    if cardinality(v_changed) = 0 then
      return new;
    end if;
    select jsonb_object_agg(k, v_before -> k) into v_before from unnest(v_changed) k;
    select jsonb_object_agg(k, v_after -> k) into v_after from unnest(v_changed) k;
  end if;

  v_entity_id := coalesce(to_jsonb(coalesce(new, old)) ->> 'id', to_jsonb(coalesce(new, old)) ->> 'student_id',
                          to_jsonb(coalesce(new, old)) ->> 'class_id');
  v_unit := coalesce((to_jsonb(coalesce(new, old)) ->> 'unit_id')::integer,
                     (to_jsonb(coalesce(new, old)) ->> 'preferred_unit_id')::integer);
  select display_name, role_code into v_label, v_role from iara.app_users where id = v_user;

  insert into iara.audit_log (user_id, actor_label, actor_role, action, entity_type, entity_id, unit_id,
                              before_json, after_json, ip_address, user_agent, request_id)
  values (v_user, coalesce(v_label, 'Sistema'), v_role, tg_op, tg_table_name, v_entity_id, v_unit,
          v_before, v_after,
          nullif(current_setting('iara.ip', true), ''), nullif(current_setting('iara.ua', true), ''),
          nullif(current_setting('iara.request_id', true), ''));
  return coalesce(new, old);
end $$;

create trigger audit_students after insert or update or delete on iara.students
  for each row execute function iara.audit_row('avatar_seed');
create trigger audit_student_sensitive after insert or update or delete on iara.student_sensitive
  for each row execute function iara.audit_row();
create trigger audit_guardians after insert or update or delete on iara.guardians
  for each row execute function iara.audit_row();
create trigger audit_addresses after insert or update or delete on iara.addresses
  for each row execute function iara.audit_row();
create trigger audit_student_guardians after insert or update or delete on iara.student_guardians
  for each row execute function iara.audit_row();
create trigger audit_enrollments after insert or update or delete on iara.enrollments
  for each row execute function iara.audit_row();
create trigger audit_classes after insert or update or delete on iara.classes
  for each row execute function iara.audit_row(
    'active_enrollments_count,blocked_seats_count,reserved_seats_count,physical_vacancies_count,offerable_vacancies_count');
create trigger audit_vacancy_blocks after insert or update or delete on iara.vacancy_blocks
  for each row execute function iara.audit_row();
create trigger audit_vacancy_offers after insert or update or delete on iara.vacancy_offers
  for each row execute function iara.audit_row();
create trigger audit_waiting_list after insert or update or delete on iara.waiting_list_entries
  for each row execute function iara.audit_row('last_recalculated_at,position');
create trigger audit_service_cases after insert or update or delete on iara.service_cases
  for each row execute function iara.audit_row();
create trigger audit_documents after insert or update or delete on iara.documents
  for each row execute function iara.audit_row();
create trigger audit_rules after insert or update or delete on iara.rules
  for each row execute function iara.audit_row();
create trigger audit_conversations after update of state, assigned_user_id on iara.conversations
  for each row execute function iara.audit_row('context,last_message_at,summary,intent');

commit;
