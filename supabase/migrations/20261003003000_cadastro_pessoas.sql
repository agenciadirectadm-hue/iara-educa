-- =============================================================================
-- IARA Educa · Cadastro 360º do aluno e do responsável (arquitetura mestra, cap. 11, 11.1, 11.2, 12 e 12.1)
-- Pedido do usuário (05/10/2026): "falta o registro de responsáveis e de alunos. Cada aluno precisa ficar
-- cadastrado; cada responsável idem; dados pessoais e geográficos".
--  1. Campos que faltavam (documentos, cor/raça, nacionalidade, naturalidade, filiação, cartão SUS, código INEP;
--     RG, estado civil, 2º telefone, renda individual; zona e ponto de referência do endereço) e composição familiar
--  2. Validação de CPF/NIS, pendências de cadastro e escopo das unidades (inclui quem a própria unidade cadastrou)
--  3. Localização: território, bairro, zona e distância às unidades a partir do ponto no mapa
--  4. API: listas (alunos_lista, responsaveis_lista), fichas (aluno_cadastro, responsavel_cadastro), salvamento
--     (aluno_salvar, responsavel_salvar), vínculos, composição familiar e localizar_ponto
--  5. Fichas 360º (student_detail, guardian_detail) com os dados novos
--  6. Limpeza da demonstração desfaz também edições de cadastro feitas por sessões
--  7. Base fictícia: preenche os campos novos de todos os alunos, responsáveis e endereços
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
-- =============================================================================
begin;

-- 1. Campos -----------------------------------------------------------------------------------------------
alter table iara.students
  add column if not exists cpf text,
  add column if not exists nis text,
  add column if not exists birth_certificate text,
  add column if not exists race_color text,
  add column if not exists nationality text not null default 'BRASILEIRA',
  add column if not exists birth_country text,
  add column if not exists birth_city text,
  add column if not exists birth_state char(2),
  add column if not exists sus_card text,
  add column if not exists inep_id text,
  add column if not exists parent1_name text,
  add column if not exists parent2_name text,
  add column if not exists image_consent boolean,
  add column if not exists updated_by uuid;
alter table iara.students drop constraint if exists students_race_color_check;
alter table iara.students add constraint students_race_color_check
  check (race_color in ('BRANCA', 'PRETA', 'PARDA', 'AMARELA', 'INDIGENA', 'NAO_DECLARADA'));
alter table iara.students drop constraint if exists students_nationality_check;
alter table iara.students add constraint students_nationality_check check (nationality in ('BRASILEIRA', 'NATURALIZADA', 'ESTRANGEIRA'));

alter table iara.guardians
  add column if not exists rg text,
  add column if not exists secondary_phone text,
  add column if not exists marital_status text,
  add column if not exists preferred_language text not null default 'Português',
  add column if not exists monthly_income numeric(10, 2),
  add column if not exists nationality text not null default 'BRASILEIRA';

alter table iara.addresses
  add column if not exists zone text not null default 'URBANA',
  add column if not exists reference_point text,
  add column if not exists geocoded_at timestamptz;
alter table iara.addresses drop constraint if exists addresses_zone_check;
alter table iara.addresses add constraint addresses_zone_check check (zone in ('URBANA', 'RURAL'));

create table if not exists iara.household_members (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null default 1 references iara.tenants(id),
  guardian_id uuid not null references iara.guardians(id) on delete cascade,
  full_name text not null,
  relationship text not null,
  birth_date date,
  occupation text,
  monthly_income numeric(10, 2),
  notes text,
  is_demo boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists household_members_guardian_idx on iara.household_members(guardian_id);
alter table iara.household_members enable row level security;
drop policy if exists household_members_read on iara.household_members;
create policy household_members_read on iara.household_members for select to authenticated using (iara.can_access_guardian(guardian_id));
grant select on iara.household_members to authenticated;
drop trigger if exists audit_household_members on iara.household_members;
create trigger audit_household_members after insert or update or delete on iara.household_members
  for each row execute function iara.audit_row();

create index if not exists addresses_territory_idx on iara.addresses(territory_id);
create index if not exists enrollments_student_status_idx on iara.enrollments(student_id, status);

update iara.tenants set settings = settings || '{"salario_minimo": 1518}'::jsonb where id = 1 and not (settings ? 'salario_minimo');

-- 2. Validação, máscaras e pendências --------------------------------------------------------------------
create or replace function iara.digitos(p text) returns text
language sql immutable as $$ select nullif(regexp_replace(coalesce(p, ''), '\D', '', 'g'), '') $$;

create index if not exists students_cpf_digits_idx on iara.students ((iara.digitos(cpf))) where cpf is not null;
create index if not exists guardians_cpf_digits_idx on iara.guardians ((iara.digitos(cpf))) where cpf is not null;

create or replace function iara.cpf_valido(p text) returns boolean
language plpgsql immutable as $$
declare
  d text := iara.digitos(p);
  s integer := 0;
  r integer;
  i integer;
begin
  if d is null or length(d) <> 11 or d ~ '^(\d)\1{10}$' then return false; end if;
  for i in 1..9 loop s := s + substr(d, i, 1)::int * (11 - i); end loop;
  r := (s * 10) % 11; if r = 10 then r := 0; end if;
  if r <> substr(d, 10, 1)::int then return false; end if;
  s := 0;
  for i in 1..10 loop s := s + substr(d, i, 1)::int * (12 - i); end loop;
  r := (s * 10) % 11; if r = 10 then r := 0; end if;
  return r = substr(d, 11, 1)::int;
end $$;

create or replace function iara.nis_valido(p text) returns boolean
language plpgsql immutable as $$
declare
  d text := iara.digitos(p);
  w integer[] := array[3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
  s integer := 0;
  r integer;
  i integer;
begin
  if d is null or length(d) <> 11 then return false; end if;
  for i in 1..10 loop s := s + substr(d, i, 1)::int * w[i]; end loop;
  r := 11 - (s % 11); if r >= 10 then r := 0; end if;
  return r = substr(d, 11, 1)::int;
end $$;

create or replace function iara.fmt_cpf(p text) returns text
language sql immutable as $$
  select case when length(iara.digitos(p)) = 11
              then regexp_replace(iara.digitos(p), '(\d{3})(\d{3})(\d{3})(\d{2})', '\1.\2.\3-\4') else p end
$$;

-- documento mascarado: só os 4 últimos dígitos
create or replace function iara.mascara_doc(p text) returns text
language sql immutable as $$
  select case when iara.digitos(p) is null then null
              else repeat('•', greatest(length(iara.digitos(p)) - 4, 0)) || right(iara.digitos(p), 4) end
$$;

create or replace function iara.endereco_aproximado(p_precisao text) returns boolean
language sql immutable as $$ select coalesce(p_precisao, '') not in ('ENDERECO', 'PONTO_NO_MAPA') $$;

create or replace function iara.faixa_renda(p_renda numeric) returns text
language sql stable security definer set search_path = iara, public as $$
  select case when p_renda is null then null
              when p_renda < 1 * x.sm then 'Até 1 salário mínimo' when p_renda < 2 * x.sm then '1 a 2 salários mínimos'
              when p_renda < 3 * x.sm then '2 a 3 salários mínimos' when p_renda < 5 * x.sm then '3 a 5 salários mínimos'
              else 'Acima de 5 salários mínimos' end
  from (select coalesce((iara.setting('salario_minimo'))::numeric, 1518) as sm) x
$$;

-- O que falta para o cadastro do aluno ficar completo (7 itens verificados; Censo Escolar + matrícula)
create or replace function iara.aluno_pendencias(s iara.students, p_tem_responsavel boolean) returns text[]
language sql immutable as $$
  select array_remove(array[
    case when s.gender is null then 'Sexo' end,
    case when s.race_color is null then 'Cor/raça' end,
    case when s.nationality = 'BRASILEIRA' then case when s.birth_city is null or s.birth_state is null then 'Naturalidade' end
         else case when s.birth_country is null then 'País de nascimento' end end,
    case when s.parent1_name is null then 'Filiação' end,
    case when s.birth_certificate is null and s.cpf is null then 'Certidão de nascimento ou CPF' end,
    case when s.address_id is null then 'Endereço' end,
    case when not p_tem_responsavel then 'Responsável' end
  ], null)
$$;

-- O que falta para o cadastro do responsável ficar completo (5 itens verificados)
create or replace function iara.responsavel_pendencias(g iara.guardians) returns text[]
language sql immutable as $$
  select array_remove(array[
    case when g.cpf is null then 'CPF' end,
    case when g.birth_date is null then 'Data de nascimento' end,
    case when g.primary_phone is null and g.whatsapp_phone is null then 'Telefone' end,
    case when g.address_id is null then 'Endereço' end,
    case when g.cadunico_status and g.nis is null then 'NIS (CadÚnico)' end
  ], null)
$$;

-- Escopo da unidade: crianças com vínculo com a unidade (matrícula, fila, oferta, protocolo) ou que a própria
-- unidade cadastrou; responsáveis dessas crianças ou cadastrados pela unidade.
create or replace function iara.unidade_alunos(p_unit integer) returns setof uuid
language sql stable security definer set search_path = iara, public
as $$
  select e.student_id from iara.enrollments e
  where e.unit_id = p_unit and e.status in ('ACTIVE', 'PRE_ENROLLMENT', 'TRANSFER_PENDING')
  union
  select w.student_id from iara.waiting_list_entries w where w.preferred_unit_id = p_unit and w.status in ('WAITING', 'OFFERED', 'ACCEPTED')
  union
  select o.student_id from iara.vacancy_offers o where o.unit_id = p_unit and o.status in ('OFFERED', 'ACCEPTED', 'ENROLLED')
  union
  select c.student_id from iara.service_cases c where c.unit_id = p_unit and c.student_id is not null
  union
  select s.id from iara.students s join iara.app_users u on u.id = s.created_by where u.unit_id = p_unit
$$;

create or replace function iara.unidade_responsaveis(p_unit integer) returns setof uuid
language sql stable security definer set search_path = iara, public
as $$
  select sg.guardian_id from iara.student_guardians sg where sg.student_id in (select iara.unidade_alunos(p_unit))
  union
  select g.id from iara.guardians g join iara.app_users u on u.id = g.created_by where u.unit_id = p_unit
$$;

-- as políticas de leitura (RLS) usam estas versões em conjunto; mesmas regras de iara.can_access_student/guardian
create or replace function iara.my_student_ids() returns setof uuid
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_scope() = 'GUARDIAN' then
    return query select sg.student_id from iara.student_guardians sg where sg.guardian_id = iara.my_guardian() and sg.end_date is null;
  elsif iara.my_scope() = 'UNIT' and iara.has_perm('students.read') then
    return query select iara.unidade_alunos(iara.my_unit());
  end if;
end $$;

create or replace function iara.my_guardian_ids() returns setof uuid
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_scope() = 'GUARDIAN' then
    return query select iara.my_guardian();
  elsif iara.my_scope() = 'UNIT' and iara.has_perm('guardians.read') then
    return query select iara.unidade_responsaveis(iara.my_unit());
  end if;
end $$;

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
        or exists (select 1 from iara.service_cases c where c.student_id = p_student and c.unit_id = v_unit)
        or exists (select 1 from iara.students s join iara.app_users u on u.id = s.created_by
                   where s.id = p_student and u.unit_id = v_unit);
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
                   where sg.guardian_id = p_guardian and iara.can_access_student(sg.student_id))
        or exists (select 1 from iara.guardians g join iara.app_users u on u.id = g.created_by
                   where g.id = p_guardian and u.unit_id = iara.my_unit());
  end if;
  return false;
end $$;

-- 3. Localização --------------------------------------------------------------------------------------------
create or replace function iara.localizar(p_lat double precision, p_lng double precision) returns jsonb
language sql stable security definer set search_path = iara, extensions, public
as $$
  with pt as (select iara.point(p_lat, p_lng) as g)
  select jsonb_build_object(
    'dentro_maringa', iara.in_maringa(p_lat, p_lng),
    'territorio_id', t.id, 'territorio', t.name, 'territorio_tipo', t.kind,
    'bairro', b.name, 'bairro_distancia_m', b.dist)
  from pt
  left join lateral (select t.id, t.name, t.kind from iara.territories t
                     where t.kind in ('MACRORREGIAO', 'DISTRITO') and t.geom is not null and st_covers(t.geom, pt.g)
                     order by (t.kind = 'DISTRITO') desc limit 1) t on true
  left join lateral (select b.name, round(st_distance(b.center, pt.g))::int as dist from iara.territories b
                     where b.kind = 'BAIRRO' and b.center is not null order by st_distance(b.center, pt.g) limit 1) b on true
$$;

-- Novo endereço do cadastro (chaves em português). Nunca altera um endereço existente: cada mudança gera um
-- registro novo, e o anterior fica no histórico (auditoria).
create or replace function iara.endereco_novo(p jsonb, p_fonte text) returns uuid
language plpgsql security definer set search_path = iara, extensions, public
as $$
declare
  v_id uuid := gen_random_uuid();
  v_lat double precision := nullif(p ->> 'lat', '')::double precision;
  v_lng double precision := nullif(p ->> 'lng', '')::double precision;
  v_log text := nullif(btrim(coalesce(p ->> 'logradouro', '')), '');
  v_cep text := iara.digitos(p ->> 'cep');
  v_zona text := coalesce(nullif(p ->> 'zona', ''), 'URBANA');
  v_cidade text := coalesce(nullif(btrim(coalesce(p ->> 'cidade', '')), ''), 'Maringá');
  v_uf text := upper(coalesce(nullif(btrim(coalesce(p ->> 'uf', '')), ''), 'PR'));
  v_loc jsonb;
begin
  if v_log is null then
    raise exception 'Informe o logradouro (rua, avenida...).' using errcode = '22023';
  end if;
  if v_lat is null or v_lng is null then
    raise exception 'Marque a localização do endereço no mapa (ou localize pelo CEP ou pelo bairro).' using errcode = '22023';
  end if;
  if v_cep is not null and length(v_cep) <> 8 then
    raise exception 'CEP inválido: são 8 dígitos.' using errcode = '22023';
  end if;
  if v_zona not in ('URBANA', 'RURAL') then
    raise exception 'Zona inválida (urbana ou rural).' using errcode = '22023';
  end if;
  if length(v_uf) <> 2 then
    raise exception 'UF inválida.' using errcode = '22023';
  end if;
  v_loc := iara.localizar(v_lat, v_lng);
  insert into iara.addresses (id, tenant_id, street, number, complement, neighborhood, postal_code, city, state, location,
                              geocode_precision, geocode_source, territory_id, zone, reference_point, geocoded_at, is_demo)
  values (v_id, 1, v_log, nullif(btrim(coalesce(p ->> 'numero', '')), ''), nullif(btrim(coalesce(p ->> 'complemento', '')), ''),
          coalesce(nullif(btrim(coalesce(p ->> 'bairro', '')), ''), v_loc ->> 'bairro'),
          case when v_cep is not null then substr(v_cep, 1, 5) || '-' || substr(v_cep, 6) end,
          v_cidade, v_uf, iara.point(v_lat, v_lng), coalesce(nullif(p ->> 'precisao', ''), 'PONTO_NO_MAPA'),
          coalesce(nullif(p ->> 'fonte', ''), p_fonte),
          case when (v_loc ->> 'dentro_maringa')::boolean then (v_loc ->> 'territorio_id')::int end,
          v_zona, nullif(btrim(coalesce(p ->> 'referencia', '')), ''), now(), coalesce((iara.setting('demo_mode'))::boolean, false));
  return v_id;
end $$;

create or replace function iara.endereco_json(p_address uuid) returns jsonb
language sql stable security definer set search_path = iara, extensions, public
as $$
  select jsonb_build_object(
    'id', a.id, 'logradouro', a.street, 'numero', a.number, 'complemento', a.complement, 'bairro', a.neighborhood,
    'cep', a.postal_code, 'cidade', a.city, 'uf', a.state, 'referencia', a.reference_point, 'zona', a.zone,
    'lat', st_y(a.location::geometry), 'lng', st_x(a.location::geometry), 'precisao', a.geocode_precision, 'fonte', a.geocode_source,
    'aproximado', iara.endereco_aproximado(a.geocode_precision), 'territorio_id', a.territory_id,
    'territorio', (select t.name from iara.territories t where t.id = a.territory_id), 'atualizado_em', coalesce(a.geocoded_at, a.updated_at),
    'linha', a.street || ', ' || coalesce(a.number, 's/n') || coalesce(' — ' || a.complement, '') || ' · ' || coalesce(a.neighborhood, '')
             || ' · ' || a.city || '/' || a.state)
  from iara.addresses a where a.id = p_address
$$;

create or replace function api.localizar_ponto(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, extensions, public
as $$
declare
  v_lat double precision := nullif(p ->> 'lat', '')::double precision;
  v_lng double precision := nullif(p ->> 'lng', '')::double precision;
  v_faixa smallint := nullif(p ->> 'faixa_id', '')::smallint;
  v_pt extensions.geography;
begin
  if iara.current_user_id() is null then
    raise exception 'Sessão necessária.' using errcode = '42501';
  end if;
  if v_lat is null or v_lng is null or abs(v_lat) > 90 or abs(v_lng) > 180 then
    raise exception 'Coordenadas inválidas.' using errcode = '22023';
  end if;
  v_pt := iara.point(v_lat, v_lng);
  return iara.localizar(v_lat, v_lng) || jsonb_build_object(
    'unidades', (select coalesce(jsonb_agg(x.z order by (x.z ->> 'distancia_m')::int), '[]'::jsonb) from (
        select jsonb_build_object('id', u.id, 'nome', u.name, 'tipo', u.unit_type, 'tipo_rotulo', u.unit_type_label,
                                  'distancia_m', round(st_distance(u.location, v_pt))::int,
                                  'vagas', case when v_faixa is not null then (select coalesce(sum(c.offerable_vacancies_count), 0)::int from iara.classes c
                                                                              where c.unit_id = u.id and c.status = 'ATIVA' and c.grade_level_id = v_faixa) end) as z
        from iara.education_units u
        where u.status = 'ATIVA' and u.location is not null
          and (v_faixa is null or exists (select 1 from iara.classes c where c.unit_id = u.id and c.grade_level_id = v_faixa and c.status = 'ATIVA'))
        order by st_distance(u.location, v_pt) limit 5) x));
end $$;

-- 4. API · listas ---------------------------------------------------------------------------------------------
create or replace function api.alunos_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, extensions, public
as $$
declare
  v_scope text := iara.my_scope();
  v_unit integer := iara.my_unit();
  v_q text := nullif(btrim(iara.norm(coalesce(p ->> 'q', ''))), '');
  v_dig text := iara.digitos(p ->> 'q');
  v_sit text := nullif(p ->> 'situacao', '');
  v_un integer := nullif(p ->> 'unidade_id', '')::int;
  v_terr integer := nullif(p ->> 'territorio_id', '')::int;
  v_pend boolean := coalesce((p ->> 'pendentes')::boolean, false);
  v_item text := nullif(p ->> 'pendencia', '');
  v_ordem text := coalesce(nullif(p ->> 'ordem', ''), 'nome');
  v_lim integer := least(greatest(coalesce(nullif(p ->> 'limite', '')::int, 40), 1), 100);
  v_off integer := greatest(coalesce(nullif(p ->> 'offset', '')::int, 0), 0);
  v jsonb;
begin
  perform iara.require_perm('students.read');
  if v_scope is null or v_scope not in ('NETWORK', 'UNIT') then
    raise exception 'O cadastro de alunos é da Secretaria e das unidades.' using errcode = '42501';
  end if;
  if v_dig is not null and length(v_dig) < 4 then v_dig := null; end if;
  with base as materialized (
    select s.id, s.full_name, s.social_name, s.birth_date, s.gender, s.status, s.student_registry_number, s.avatar_seed, s.aee_status,
           s.updated_at, s.is_demo, a.neighborhood, a.territory_id, a.geocode_precision,
           mat.unit_id as mat_unit, mat.unit_name, mat.class_name,
           iara.aluno_pendencias(s, r.student_id is not null) as pend
    from iara.students s
    left join iara.addresses a on a.id = s.address_id
    left join (select distinct sg.student_id from iara.student_guardians sg where sg.end_date is null) r on r.student_id = s.id
    left join (select distinct on (e.student_id) e.student_id, e.unit_id, u.short_name as unit_name, c.class_name
               from iara.enrollments e join iara.education_units u on u.id = e.unit_id join iara.classes c on c.id = e.class_id
               where e.status = 'ACTIVE' order by e.student_id, e.enrollment_date desc) mat on mat.student_id = s.id
    where (v_scope = 'NETWORK' or s.id in (select iara.unidade_alunos(v_unit)))
      and (v_q is null
           or iara.norm(s.full_name) like '%' || v_q || '%'
           or iara.norm(coalesce(s.social_name, '')) like '%' || v_q || '%'
           or (v_dig is not null and (s.student_registry_number = v_dig or iara.digitos(s.cpf) = v_dig or s.inep_id = v_dig)))
  ),
  filt as (
    select b.* from base b
    where (v_sit is null or b.status = v_sit)
      and (v_un is null or b.mat_unit = v_un)
      and (v_terr is null or b.territory_id = v_terr)
      and (not v_pend or cardinality(b.pend) > 0)
      and (v_item is null or v_item = any (b.pend))
  ),
  pagina as (
    select f.*, row_number() over (order by
             case when v_ordem = 'pendencias' then -cardinality(f.pend) else 0 end,
             case when v_ordem = 'recentes' then -extract(epoch from f.updated_at) else 0 end,
             iara.norm(f.full_name), f.id) as ord
    from filt f
    order by ord
    limit v_lim offset v_off
  )
  select jsonb_build_object(
    'escopo', v_scope,
    'unidade', (select u.name from iara.education_units u where u.id = v_unit),
    'pode_editar', iara.has_perm('students.write'),
    'total', (select count(*) from filt),
    'contagem', (select jsonb_build_object('todos', count(*), 'completos', count(*) filter (where cardinality(pend) = 0),
        'pendentes', count(*) filter (where cardinality(pend) > 0),
        'MATRICULADO', count(*) filter (where status = 'MATRICULADO'), 'AGUARDANDO_VAGA', count(*) filter (where status = 'AGUARDANDO_VAGA'),
        'SEM_VINCULO', count(*) filter (where status = 'SEM_VINCULO'), 'TRANSFERENCIA', count(*) filter (where status = 'TRANSFERENCIA'),
        'INATIVO', count(*) filter (where status = 'INATIVO'),
        'aproximada', count(*) filter (where iara.endereco_aproximado(geocode_precision))) from base),
    'pendencias_frequentes', (select coalesce(jsonb_agg(jsonb_build_object('item', z.item, 'n', z.n) order by z.n desc, z.item), '[]'::jsonb)
                              from (select unnest(pend) as item, count(*) as n from base group by 1) z),
    'itens', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', g.id, 'nome', g.full_name, 'nome_social', g.social_name, 'nascimento', g.birth_date, 'idade', iara.age_text(g.birth_date),
        'sexo', g.gender, 'situacao', g.status, 'registro', g.student_registry_number, 'avatar_seed', g.avatar_seed,
        'unidade', case when g.mat_unit is not null then jsonb_build_object('id', g.mat_unit, 'nome', g.unit_name, 'turma', g.class_name) end,
        'bairro', g.neighborhood, 'territorio', (select t.name from iara.territories t where t.id = g.territory_id),
        'localizacao_aproximada', iara.endereco_aproximado(g.geocode_precision),
        'pendencias', to_jsonb(g.pend), 'completo_pct', round(100.0 * (7 - cardinality(g.pend)) / 7),
        'aee', g.aee_status, 'ficticio', g.is_demo,
        'responsavel', (select jsonb_build_object('id', gg.id, 'nome', gg.full_name, 'parentesco', sg.relationship)
                        from iara.student_guardians sg join iara.guardians gg on gg.id = sg.guardian_id
                        where sg.student_id = g.id and sg.end_date is null order by sg.is_primary desc, sg.relationship limit 1))
      order by g.ord), '[]'::jsonb) from pagina g)
  ) into v;
  return v;
end $$;

create or replace function api.responsaveis_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, extensions, public
as $$
declare
  v_scope text := iara.my_scope();
  v_unit integer := iara.my_unit();
  v_contatos boolean := iara.can_see_contacts();
  v_q text := nullif(btrim(iara.norm(coalesce(p ->> 'q', ''))), '');
  v_dig text := iara.digitos(p ->> 'q');
  v_terr integer := nullif(p ->> 'territorio_id', '')::int;
  v_pend boolean := coalesce((p ->> 'pendentes')::boolean, false);
  v_item text := nullif(p ->> 'pendencia', '');
  v_cad boolean := coalesce((p ->> 'cadunico')::boolean, false);
  v_ordem text := coalesce(nullif(p ->> 'ordem', ''), 'nome');
  v_lim integer := least(greatest(coalesce(nullif(p ->> 'limite', '')::int, 40), 1), 100);
  v_off integer := greatest(coalesce(nullif(p ->> 'offset', '')::int, 0), 0);
  v jsonb;
begin
  perform iara.require_perm('guardians.read');
  if v_scope is null or v_scope not in ('NETWORK', 'UNIT') then
    raise exception 'O cadastro de responsáveis é da Secretaria e das unidades.' using errcode = '42501';
  end if;
  if v_dig is not null and length(v_dig) < 4 then v_dig := null; end if;
  with base as materialized (
    select g.id, g.full_name, g.social_name, g.cpf, g.primary_phone, g.whatsapp_phone, g.cadunico_status, g.single_mother, g.updated_at,
           g.is_demo, a.neighborhood, a.territory_id, a.geocode_precision, iara.responsavel_pendencias(g) as pend
    from iara.guardians g
    left join iara.addresses a on a.id = g.address_id
    where (v_scope = 'NETWORK' or g.id in (select iara.unidade_responsaveis(v_unit)))
      and (v_q is null
           or iara.norm(g.full_name) like '%' || v_q || '%'
           or iara.norm(coalesce(g.social_name, '')) like '%' || v_q || '%'
           or (v_dig is not null and (iara.digitos(g.cpf) = v_dig
               or (v_contatos and (iara.digitos(g.primary_phone) like '%' || v_dig or iara.digitos(g.whatsapp_phone) like '%' || v_dig)))))
  ),
  filt as (
    select b.* from base b
    where (v_terr is null or b.territory_id = v_terr)
      and (not v_pend or cardinality(b.pend) > 0)
      and (v_item is null or v_item = any (b.pend))
      and (not v_cad or b.cadunico_status)
  ),
  pagina as (
    select f.*, row_number() over (order by
             case when v_ordem = 'pendencias' then -cardinality(f.pend) else 0 end,
             case when v_ordem = 'recentes' then -extract(epoch from f.updated_at) else 0 end,
             iara.norm(f.full_name), f.id) as ord
    from filt f
    order by ord
    limit v_lim offset v_off
  )
  select jsonb_build_object(
    'escopo', v_scope,
    'unidade', (select u.name from iara.education_units u where u.id = v_unit),
    'pode_editar', iara.has_perm('guardians.write'),
    'contatos_mascarados', not v_contatos,
    'total', (select count(*) from filt),
    'contagem', (select jsonb_build_object('todos', count(*), 'completos', count(*) filter (where cardinality(pend) = 0),
        'pendentes', count(*) filter (where cardinality(pend) > 0), 'cadunico', count(*) filter (where cadunico_status),
        'aproximada', count(*) filter (where iara.endereco_aproximado(geocode_precision))) from base),
    'pendencias_frequentes', (select coalesce(jsonb_agg(jsonb_build_object('item', z.item, 'n', z.n) order by z.n desc, z.item), '[]'::jsonb)
                              from (select unnest(pend) as item, count(*) as n from base group by 1) z),
    'itens', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', g.id, 'nome', g.full_name, 'nome_social', g.social_name,
        'cpf', case when v_contatos then g.cpf else iara.mask_cpf(g.cpf) end,
        'telefone', case when v_contatos then coalesce(g.whatsapp_phone, g.primary_phone) else iara.mask_phone(coalesce(g.whatsapp_phone, g.primary_phone)) end,
        'cadunico', g.cadunico_status, 'mae_solo', g.single_mother,
        'bairro', g.neighborhood, 'territorio', (select t.name from iara.territories t where t.id = g.territory_id),
        'localizacao_aproximada', iara.endereco_aproximado(g.geocode_precision),
        'pendencias', to_jsonb(g.pend), 'completo_pct', round(100.0 * (5 - cardinality(g.pend)) / 5), 'ficticio', g.is_demo,
        'criancas', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.full_name, 'idade', iara.age_text(s.birth_date),
                                                                  'parentesco', sg.relationship, 'avatar_seed', s.avatar_seed) order by s.birth_date), '[]'::jsonb)
                     from iara.student_guardians sg join iara.students s on s.id = sg.student_id
                     where sg.guardian_id = g.id and sg.end_date is null))
      order by g.ord), '[]'::jsonb) from pagina g)
  ) into v;
  return v;
end $$;

-- 4. API · fichas de cadastro ---------------------------------------------------------------------------------
create or replace function api.aluno_cadastro(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = iara, extensions, public
as $$
declare
  s iara.students;
  v_docs boolean := iara.can_see_contacts();
  v_pode_sens boolean := iara.has_perm('students.read_sensitive');
  v_sens jsonb;
  v_prim record;
  v_mat record;
  v_pend text[];
begin
  perform iara.require_perm('students.read');
  select * into s from iara.students where id = nullif(p ->> 'id', '')::uuid;
  if not found or not iara.can_access_student(s.id) then
    raise exception 'Aluno não encontrado ou fora do seu escopo.' using errcode = 'P0002';
  end if;
  if v_pode_sens then
    select jsonb_build_object('necessidade_especial', x.special_education_need, 'alertas_saude', x.medical_alerts,
                              'alergias_alimentares', x.food_allergies, 'observacoes_legais', x.legal_notes, 'atualizado_em', x.updated_at)
    into v_sens from iara.student_sensitive x where x.student_id = s.id;
    if v_sens is not null then
      perform iara.audit_event('VIEW_SENSITIVE', 'students', s.id::text, null, 'Consulta a dados sensíveis no cadastro (AEE/saúde/restrições).');
    end if;
  end if;
  select sg.guardian_id, g.full_name, g.address_id into v_prim
  from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
  where sg.student_id = s.id and sg.end_date is null order by sg.is_primary desc, sg.relationship limit 1;
  select e.unit_id, u.name as unit_name, c.class_name, c.shift, round(st_distance(u.location, a.location))::int as dist
  into v_mat
  from iara.enrollments e join iara.education_units u on u.id = e.unit_id join iara.classes c on c.id = e.class_id
  left join iara.addresses a on a.id = s.address_id
  where e.student_id = s.id and e.status = 'ACTIVE' order by e.enrollment_date desc limit 1;
  v_pend := iara.aluno_pendencias(s, v_prim.guardian_id is not null);
  return jsonb_build_object(
    'aluno', jsonb_build_object(
      'id', s.id, 'nome', s.full_name, 'nome_social', s.social_name, 'nascimento', s.birth_date, 'idade', iara.age_text(s.birth_date),
      'sexo', s.gender, 'cor_raca', s.race_color, 'nacionalidade', s.nationality, 'pais_nascimento', s.birth_country,
      'naturalidade_municipio', s.birth_city, 'naturalidade_uf', s.birth_state,
      'cpf', case when v_docs then iara.fmt_cpf(s.cpf) else iara.mask_cpf(s.cpf) end,
      'nis', case when v_docs then s.nis else iara.mascara_doc(s.nis) end,
      'certidao', case when v_docs then s.birth_certificate else iara.mascara_doc(s.birth_certificate) end,
      'cartao_sus', case when v_docs then s.sus_card else iara.mascara_doc(s.sus_card) end,
      'codigo_inep', s.inep_id, 'registro', s.student_registry_number,
      'filiacao_1', s.parent1_name, 'filiacao_2', s.parent2_name, 'uso_imagem', s.image_consent, 'situacao', s.status,
      'transporte', s.transport_need, 'transporte_situacao', s.school_transport_status, 'acessibilidade', s.accessibility_needs,
      'aee', s.aee_status, 'avatar_seed', s.avatar_seed, 'ficticio', s.is_demo, 'criado_em', s.created_at, 'atualizado_em', s.updated_at),
    'documentos_mascarados', not v_docs,
    'sensiveis', v_sens,
    'sensiveis_restrito', not v_pode_sens,
    'endereco', iara.endereco_json(s.address_id),
    'endereco_do_responsavel', s.address_id is not null and s.address_id = v_prim.address_id,
    'responsavel_principal', case when v_prim.guardian_id is not null then
        jsonb_build_object('id', v_prim.guardian_id, 'nome', v_prim.full_name, 'tem_endereco', v_prim.address_id is not null,
                           'endereco', iara.endereco_json(v_prim.address_id)) end,
    'responsaveis', coalesce((select jsonb_agg(jsonb_build_object(
        'id', g.id, 'nome', g.full_name, 'cpf', case when v_docs then g.cpf else iara.mask_cpf(g.cpf) end,
        'telefone', case when v_docs then coalesce(g.whatsapp_phone, g.primary_phone) else iara.mask_phone(coalesce(g.whatsapp_phone, g.primary_phone)) end,
        'parentesco', sg.relationship, 'principal', sg.is_primary, 'pode_buscar', sg.can_pick_up, 'recebe_avisos', sg.can_receive_notifications,
        'situacao_legal', sg.legal_authority_status, 'desde', sg.start_date, 'ate', sg.end_date, 'mesmo_endereco', g.address_id = s.address_id)
        order by sg.end_date nulls first, sg.is_primary desc, sg.relationship)
      from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id where sg.student_id = s.id), '[]'::jsonb),
    'matricula', case when v_mat.unit_id is not null then jsonb_build_object('unidade_id', v_mat.unit_id, 'unidade', v_mat.unit_name,
        'turma', v_mat.class_name, 'turno', v_mat.shift, 'distancia_m', v_mat.dist) end,
    'faixa', iara.grade_for_birthdate(s.birth_date),
    'pendencias', to_jsonb(v_pend), 'completo_pct', round(100.0 * (7 - cardinality(v_pend)) / 7), 'itens_verificados', 7,
    'permissoes', jsonb_build_object('editar', iara.has_perm('students.write'), 'sensiveis', v_pode_sens, 'documentos', v_docs,
                                     'vinculos', iara.has_perm('students.write'))
  );
end $$;

create or replace function api.responsavel_cadastro(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, extensions, public
as $$
declare
  g iara.guardians;
  v_docs boolean := iara.can_see_contacts();
  v_pend text[];
  v_pessoas integer;
begin
  perform iara.require_perm('guardians.read');
  select * into g from iara.guardians where id = nullif(p ->> 'id', '')::uuid;
  if not found or not iara.can_access_guardian(g.id) then
    raise exception 'Responsável não encontrado ou fora do seu escopo.' using errcode = 'P0002';
  end if;
  v_pend := iara.responsavel_pendencias(g);
  v_pessoas := coalesce(g.household_size, 1 + (select count(*) from iara.household_members h where h.guardian_id = g.id)::int
                        + (select count(*) from iara.student_guardians sg where sg.guardian_id = g.id and sg.end_date is null)::int);
  return jsonb_build_object(
    'responsavel', jsonb_build_object(
      'id', g.id, 'nome', g.full_name, 'nome_social', g.social_name,
      'cpf', case when v_docs then iara.fmt_cpf(g.cpf) else iara.mask_cpf(g.cpf) end,
      'rg', case when v_docs then g.rg else iara.mascara_doc(g.rg) end,
      'nis', case when v_docs then g.nis else iara.mascara_doc(g.nis) end,
      'nascimento', g.birth_date, 'idade', iara.age_text(g.birth_date), 'sexo', g.gender, 'nacionalidade', g.nationality,
      'estado_civil', g.marital_status, 'escolaridade', g.education_level, 'idioma', g.preferred_language,
      'email', case when v_docs then g.email else regexp_replace(coalesce(g.email, ''), '^(.).*(@.*)$', '\1•••\2') end,
      'telefone', case when v_docs then g.primary_phone else iara.mask_phone(g.primary_phone) end,
      'telefone_2', case when v_docs then g.secondary_phone else iara.mask_phone(g.secondary_phone) end,
      'whatsapp', case when v_docs then g.whatsapp_phone else iara.mask_phone(g.whatsapp_phone) end,
      'canal_preferido', g.preferred_contact_channel, 'ocupacao', g.occupation, 'situacao_trabalho', g.employment_status,
      'renda_individual', g.monthly_income, 'renda_familiar', g.family_income, 'faixa_renda', g.income_bracket,
      'cadunico', g.cadunico_status, 'beneficios', g.benefits, 'pessoas_domicilio', g.household_size, 'mae_solo', g.single_mother,
      'acessibilidade', g.accessibility_needs, 'consentimento', g.consent_flags, 'ficticio', g.is_demo,
      'criado_em', g.created_at, 'atualizado_em', g.updated_at),
    'contatos_mascarados', not v_docs,
    'endereco', iara.endereco_json(g.address_id),
    'criancas', coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'nome', s.full_name, 'idade', iara.age_text(s.birth_date), 'situacao', s.status, 'avatar_seed', s.avatar_seed,
        'unidade', (select u.short_name from iara.enrollments e join iara.education_units u on u.id = e.unit_id
                    where e.student_id = s.id and e.status = 'ACTIVE' limit 1),
        'parentesco', sg.relationship, 'principal', sg.is_primary, 'pode_buscar', sg.can_pick_up, 'recebe_avisos', sg.can_receive_notifications,
        'situacao_legal', sg.legal_authority_status, 'desde', sg.start_date, 'ate', sg.end_date, 'mesmo_endereco', s.address_id = g.address_id,
        'acesso', iara.can_access_student(s.id)) order by sg.end_date nulls first, s.birth_date)
      from iara.student_guardians sg join iara.students s on s.id = sg.student_id where sg.guardian_id = g.id), '[]'::jsonb),
    'domicilio', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'nome', h.full_name, 'parentesco', h.relationship,
        'nascimento', h.birth_date, 'idade', iara.age_text(h.birth_date), 'ocupacao', h.occupation, 'renda', h.monthly_income,
        'observacoes', h.notes) order by h.birth_date nulls last, h.full_name)
      from iara.household_members h where h.guardian_id = g.id), '[]'::jsonb),
    'outros_responsaveis', coalesce((select jsonb_agg(jsonb_build_object('id', g2.id, 'nome', g2.full_name, 'criancas_em_comum', x.n,
        'mesmo_endereco', g2.address_id = g.address_id) order by g2.full_name)
      from (select sg2.guardian_id, count(*) as n from iara.student_guardians sg1
            join iara.student_guardians sg2 on sg2.student_id = sg1.student_id and sg2.guardian_id <> sg1.guardian_id and sg2.end_date is null
            where sg1.guardian_id = g.id and sg1.end_date is null group by 1) x join iara.guardians g2 on g2.id = x.guardian_id), '[]'::jsonb),
    'pessoas_domicilio', v_pessoas,
    'renda_per_capita', case when g.family_income is not null and v_pessoas > 0 then round(g.family_income / v_pessoas, 2) end,
    'pendencias', to_jsonb(v_pend), 'completo_pct', round(100.0 * (5 - cardinality(v_pend)) / 5), 'itens_verificados', 5,
    'permissoes', jsonb_build_object('editar', iara.has_perm('guardians.write'), 'contatos', v_docs,
                                     'vincular', iara.has_perm('students.write'))
  );
end $$;

-- 4. API · salvamento ----------------------------------------------------------------------------------------
create or replace function api.aluno_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, extensions, public
as $$
declare
  v_id uuid := nullif(p ->> 'id', '')::uuid;
  v_novo boolean := nullif(p ->> 'id', '') is null;
  s iara.students;
  v_nome text := regexp_replace(btrim(coalesce(p ->> 'nome', '')), '\s+', ' ', 'g');
  v_nasc date;
  v_sexo text := nullif(p ->> 'sexo', '');
  v_raca text := nullif(p ->> 'cor_raca', '');
  v_nac text := coalesce(nullif(p ->> 'nacionalidade', ''), 'BRASILEIRA');
  v_uf text := upper(nullif(btrim(coalesce(p ->> 'naturalidade_uf', '')), ''));
  v_cpf text;
  v_nis text;
  v_sus text;
  v_cert text;
  v_inep text := iara.digitos(p ->> 'codigo_inep');
  v_resp uuid := nullif(p #>> '{responsavel,id}', '')::uuid;
  v_dups jsonb;
  v_addr uuid;
  v_addr_mudou boolean := false;
  v_fila_antes jsonb;
  v_impactos jsonb := '[]'::jsonb;
  v_ufs text[] := array['AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO'];
begin
  perform iara.require_perm('students.write');
  if iara.my_scope() not in ('NETWORK', 'UNIT') then
    raise exception 'O cadastro de alunos é feito pela Secretaria e pelas unidades.' using errcode = '42501';
  end if;
  if not v_novo then
    select * into s from iara.students where id = v_id for update;
    if not found or not iara.can_access_student(v_id) then
      raise exception 'Aluno não encontrado ou fora do seu escopo.' using errcode = 'P0002';
    end if;
    -- quem vê documentos mascarados não os regrava (o formulário recebe o valor mascarado)
    if not iara.can_see_contacts() then
      p := p - 'cpf' - 'nis' - 'certidao' - 'cartao_sus';
    end if;
  end if;
  v_cpf := iara.digitos(p ->> 'cpf');
  v_nis := iara.digitos(p ->> 'nis');
  v_sus := iara.digitos(p ->> 'cartao_sus');
  v_cert := iara.digitos(p ->> 'certidao');
  -- validações (campos ausentes no pedido mantêm o valor atual)
  if v_novo or p ? 'nome' then
    if length(v_nome) < 5 or position(' ' in v_nome) = 0 then
      raise exception 'Informe o nome completo da criança (nome e sobrenome).' using errcode = '22023';
    end if;
  else
    v_nome := s.full_name;
  end if;
  if v_novo or p ? 'nascimento' then
    begin
      v_nasc := nullif(p ->> 'nascimento', '')::date;
    exception when others then
      raise exception 'Data de nascimento inválida.' using errcode = '22023';
    end;
    if v_nasc is null then raise exception 'Informe a data de nascimento.' using errcode = '22023'; end if;
    if v_nasc > current_date then raise exception 'A data de nascimento está no futuro.' using errcode = '22023'; end if;
    if v_nasc < current_date - interval '100 years' then raise exception 'Confira a data de nascimento.' using errcode = '22023'; end if;
  else
    v_nasc := s.birth_date;
  end if;
  if v_sexo is not null and v_sexo not in ('F', 'M') then
    raise exception 'Sexo inválido.' using errcode = '22023';
  end if;
  if v_raca is not null and v_raca not in ('BRANCA', 'PRETA', 'PARDA', 'AMARELA', 'INDIGENA', 'NAO_DECLARADA') then
    raise exception 'Cor/raça inválida.' using errcode = '22023';
  end if;
  if v_nac not in ('BRASILEIRA', 'NATURALIZADA', 'ESTRANGEIRA') then
    raise exception 'Nacionalidade inválida.' using errcode = '22023';
  end if;
  if v_uf is not null and not (v_uf = any (v_ufs)) then
    raise exception 'UF de nascimento inválida.' using errcode = '22023';
  end if;
  if v_cpf is not null and v_cpf is distinct from iara.digitos(s.cpf) then
    if not iara.cpf_valido(v_cpf) then
      raise exception 'CPF inválido: os dígitos verificadores não conferem.' using errcode = '22023';
    end if;
    if exists (select 1 from iara.students x where iara.digitos(x.cpf) = v_cpf and x.id is distinct from v_id) then
      raise exception 'Este CPF já está no cadastro de outra criança.' using errcode = '23505';
    end if;
  end if;
  if v_nis is not null and v_nis is distinct from iara.digitos(s.nis) and not iara.nis_valido(v_nis) then
    raise exception 'NIS inválido: confira os 11 dígitos.' using errcode = '22023';
  end if;
  if v_sus is not null and length(v_sus) <> 15 then
    raise exception 'O Cartão SUS (CNS) tem 15 dígitos.' using errcode = '22023';
  end if;
  if v_cert is not null and length(v_cert) <> 32 then
    raise exception 'A matrícula da certidão de nascimento tem 32 dígitos.' using errcode = '22023';
  end if;
  if v_inep is not null and length(v_inep) <> 12 then
    raise exception 'O código INEP do aluno tem 12 dígitos.' using errcode = '22023';
  end if;
  if v_novo and v_resp is not null and not iara.can_access_guardian(v_resp) then
    raise exception 'Responsável fora do seu escopo.' using errcode = '42501';
  end if;
  -- possível duplicidade (cadastro novo)
  if v_novo and not coalesce((p ->> 'forcar')::boolean, false) then
    select jsonb_agg(jsonb_build_object('id', x.id, 'nome', x.full_name, 'nascimento', x.birth_date, 'registro', x.student_registry_number))
    into v_dups from iara.students x
    where (iara.norm(x.full_name) = iara.norm(v_nome) and x.birth_date = v_nasc) or (v_cpf is not null and iara.digitos(x.cpf) = v_cpf);
    if v_dups is not null then
      return jsonb_build_object('ok', false, 'duplicados', v_dups,
        'mensagem', 'Já existe criança com o mesmo nome e data de nascimento (ou o mesmo CPF). Confira antes de cadastrar de novo.');
    end if;
  end if;
  -- endereço: o mesmo do responsável principal ou um endereço próprio (registro novo, geolocalizado)
  v_addr := s.address_id;
  if jsonb_typeof(p -> 'endereco') = 'object' then
    if p #>> '{endereco,modo}' = 'RESPONSAVEL' then
      v_addr := null;
      if not v_novo then
        select g.address_id into v_addr from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
        where sg.student_id = v_id and sg.end_date is null and g.address_id is not null order by sg.is_primary desc limit 1;
      end if;
      if v_addr is null and v_resp is not null then
        select address_id into v_addr from iara.guardians where id = v_resp;
      end if;
      if v_addr is null then
        raise exception 'O responsável ainda não tem endereço cadastrado. Informe o endereço da criança.' using errcode = '22023';
      end if;
    else
      v_addr := iara.endereco_novo(p -> 'endereco', 'Cadastro do aluno');
    end if;
  elsif v_novo and v_resp is not null then
    select address_id into v_addr from iara.guardians where id = v_resp;
  end if;
  v_addr_mudou := not v_novo and v_addr is distinct from s.address_id;
  if v_addr_mudou then
    v_fila_antes := iara.queue_snapshot(array[v_id]);
  end if;

  if v_novo then
    v_id := gen_random_uuid();
    insert into iara.students (id, tenant_id, full_name, social_name, birth_date, gender, status, address_id, race_color, nationality,
                               birth_country, birth_city, birth_state, cpf, nis, birth_certificate, sus_card, inep_id, parent1_name, parent2_name,
                               image_consent, transport_need, school_transport_status, accessibility_needs, aee_status, created_by, updated_by, is_demo)
    values (v_id, 1, v_nome, nullif(btrim(coalesce(p ->> 'nome_social', '')), ''), v_nasc, v_sexo, 'SEM_VINCULO', v_addr, v_raca, v_nac,
            case when v_nac <> 'BRASILEIRA' then nullif(btrim(coalesce(p ->> 'pais_nascimento', '')), '') end,
            case when v_nac = 'BRASILEIRA' then nullif(btrim(coalesce(p ->> 'naturalidade_municipio', '')), '') end,
            case when v_nac = 'BRASILEIRA' then v_uf end,
            iara.fmt_cpf(v_cpf), v_nis, v_cert, v_sus, v_inep,
            nullif(btrim(coalesce(p ->> 'filiacao_1', '')), ''), nullif(btrim(coalesce(p ->> 'filiacao_2', '')), ''),
            (p ->> 'uso_imagem')::boolean, coalesce((p ->> 'transporte')::boolean, false), nullif(p ->> 'transporte_situacao', ''),
            nullif(btrim(coalesce(p ->> 'acessibilidade', '')), ''), coalesce((p ->> 'aee')::boolean, false),
            iara.current_user_id(), iara.current_user_id(), coalesce((iara.setting('demo_mode'))::boolean, false));
  else
    update iara.students set
      full_name = v_nome,
      social_name = case when p ? 'nome_social' then nullif(btrim(coalesce(p ->> 'nome_social', '')), '') else social_name end,
      birth_date = v_nasc,
      gender = case when p ? 'sexo' then v_sexo else gender end,
      race_color = case when p ? 'cor_raca' then v_raca else race_color end,
      nationality = case when p ? 'nacionalidade' then v_nac else nationality end,
      birth_country = case when p ? 'nacionalidade' or p ? 'pais_nascimento'
                           then case when v_nac <> 'BRASILEIRA' then nullif(btrim(coalesce(p ->> 'pais_nascimento', '')), '') end else birth_country end,
      birth_city = case when p ? 'nacionalidade' or p ? 'naturalidade_municipio'
                        then case when v_nac = 'BRASILEIRA' then nullif(btrim(coalesce(p ->> 'naturalidade_municipio', '')), '') end else birth_city end,
      birth_state = case when p ? 'nacionalidade' or p ? 'naturalidade_uf' then case when v_nac = 'BRASILEIRA' then v_uf end else birth_state end,
      cpf = case when p ? 'cpf' then iara.fmt_cpf(v_cpf) else cpf end,
      nis = case when p ? 'nis' then v_nis else nis end,
      birth_certificate = case when p ? 'certidao' then v_cert else birth_certificate end,
      sus_card = case when p ? 'cartao_sus' then v_sus else sus_card end,
      inep_id = case when p ? 'codigo_inep' then v_inep else inep_id end,
      parent1_name = case when p ? 'filiacao_1' then nullif(btrim(coalesce(p ->> 'filiacao_1', '')), '') else parent1_name end,
      parent2_name = case when p ? 'filiacao_2' then nullif(btrim(coalesce(p ->> 'filiacao_2', '')), '') else parent2_name end,
      image_consent = case when p ? 'uso_imagem' then (p ->> 'uso_imagem')::boolean else image_consent end,
      transport_need = case when p ? 'transporte' then coalesce((p ->> 'transporte')::boolean, false) else transport_need end,
      school_transport_status = case when p ? 'transporte_situacao' then nullif(p ->> 'transporte_situacao', '') else school_transport_status end,
      accessibility_needs = case when p ? 'acessibilidade' then nullif(btrim(coalesce(p ->> 'acessibilidade', '')), '') else accessibility_needs end,
      aee_status = case when p ? 'aee' then coalesce((p ->> 'aee')::boolean, false) else aee_status end,
      address_id = v_addr,
      updated_by = iara.current_user_id()
    where id = v_id;
  end if;

  -- dados sensíveis (saúde, inclusão, observações legais): só com permissão específica
  if jsonb_typeof(p -> 'sensiveis') = 'object' then
    if not iara.has_perm('students.read_sensitive') then
      raise exception 'Saúde, inclusão e observações legais exigem permissão específica.' using errcode = '42501';
    end if;
    insert into iara.student_sensitive (student_id, special_education_need, medical_alerts, food_allergies, legal_notes, updated_at)
    values (v_id, nullif(btrim(coalesce(p #>> '{sensiveis,necessidade_especial}', '')), ''), nullif(btrim(coalesce(p #>> '{sensiveis,alertas_saude}', '')), ''),
            nullif(btrim(coalesce(p #>> '{sensiveis,alergias_alimentares}', '')), ''), nullif(btrim(coalesce(p #>> '{sensiveis,observacoes_legais}', '')), ''), now())
    on conflict (student_id) do update set special_education_need = excluded.special_education_need, medical_alerts = excluded.medical_alerts,
      food_allergies = excluded.food_allergies, legal_notes = excluded.legal_notes, updated_at = now();
  end if;

  -- cadastro novo a partir de um responsável: vínculo principal
  if v_novo and v_resp is not null then
    insert into iara.student_guardians (student_id, guardian_id, relationship, is_primary, legal_authority_status)
    values (v_id, v_resp, coalesce(nullif(p #>> '{responsavel,parentesco}', ''), 'RESPONSAVEL_LEGAL'), true, 'DECLARADO')
    on conflict (student_id, guardian_id) do nothing;
  end if;

  if v_addr_mudou then
    perform iara.requeue_students(array[v_id]);
    v_impactos := iara.queue_impacts(v_fila_antes, iara.queue_snapshot(array[v_id]));
  end if;
  perform iara.audit_event(case when v_novo then 'CADASTRO_ALUNO_CRIADO' else 'CADASTRO_ALUNO_ATUALIZADO' end, 'students', v_id::text, iara.my_unit(),
    case when v_novo then format('Cadastro do aluno criado: %s', v_nome)
         else format('Cadastro do aluno atualizado: %s%s', v_nome, case when v_addr_mudou then ' (endereço alterado; fila recalculada)' else '' end) end);
  return jsonb_build_object('ok', true, 'id', v_id, 'novo', v_novo, 'endereco_alterado', v_addr_mudou, 'impactos_fila', v_impactos,
                            'cadastro', api.aluno_cadastro(jsonb_build_object('id', v_id)));
end $$;

create or replace function api.responsavel_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, extensions, public
as $$
declare
  v_id uuid := nullif(p ->> 'id', '')::uuid;
  v_novo boolean := nullif(p ->> 'id', '') is null;
  g iara.guardians;
  v_nome text := regexp_replace(btrim(coalesce(p ->> 'nome', '')), '\s+', ' ', 'g');
  v_nasc date;
  v_cpf text := iara.digitos(p ->> 'cpf');
  v_nis text := iara.digitos(p ->> 'nis');
  v_tel text := nullif(btrim(coalesce(p ->> 'telefone', '')), '');
  v_tel2 text := nullif(btrim(coalesce(p ->> 'telefone_2', '')), '');
  v_wpp text := nullif(btrim(coalesce(p ->> 'whatsapp', '')), '');
  v_email text := lower(nullif(btrim(coalesce(p ->> 'email', '')), ''));
  v_sexo text := nullif(p ->> 'sexo', '');
  v_renda numeric := nullif(p ->> 'renda_familiar', '')::numeric;
  v_crianca uuid := nullif(p #>> '{crianca,id}', '')::uuid;
  v_dups jsonb;
  v_addr uuid;
  v_old_addr uuid;
  v_alunos uuid[] := '{}';
  v_fila_antes jsonb;
  v_impactos jsonb := '[]'::jsonb;
  v_contatos boolean := iara.can_see_contacts();
begin
  perform iara.require_perm('guardians.write');
  if iara.my_scope() not in ('NETWORK', 'UNIT') then
    raise exception 'O cadastro de responsáveis é feito pela Secretaria e pelas unidades.' using errcode = '42501';
  end if;
  if not v_novo then
    select * into g from iara.guardians where id = v_id for update;
    if not found or not iara.can_access_guardian(v_id) then
      raise exception 'Responsável não encontrado ou fora do seu escopo.' using errcode = 'P0002';
    end if;
  end if;
  if v_novo or p ? 'nome' then
    if length(v_nome) < 5 or position(' ' in v_nome) = 0 then
      raise exception 'Informe o nome completo do responsável (nome e sobrenome).' using errcode = '22023';
    end if;
  else
    v_nome := g.full_name;
  end if;
  if p ? 'nascimento' then
    begin
      v_nasc := nullif(p ->> 'nascimento', '')::date;
    exception when others then
      raise exception 'Data de nascimento inválida.' using errcode = '22023';
    end;
    if v_nasc is not null and (v_nasc > current_date - interval '12 years' or v_nasc < current_date - interval '110 years') then
      raise exception 'Confira a data de nascimento do responsável.' using errcode = '22023';
    end if;
  else
    v_nasc := g.birth_date;
  end if;
  if v_sexo is not null and v_sexo not in ('F', 'M') then
    raise exception 'Sexo inválido.' using errcode = '22023';
  end if;
  if v_cpf is not null and v_cpf is distinct from iara.digitos(g.cpf) then
    if not iara.cpf_valido(v_cpf) then
      raise exception 'CPF inválido: os dígitos verificadores não conferem.' using errcode = '22023';
    end if;
    if exists (select 1 from iara.guardians x where iara.digitos(x.cpf) = v_cpf and x.id is distinct from v_id) then
      raise exception 'Este CPF já está no cadastro de outro responsável. Use a busca para abrir o cadastro existente.' using errcode = '23505';
    end if;
  end if;
  if v_nis is not null and v_nis is distinct from iara.digitos(g.nis) and not iara.nis_valido(v_nis) then
    raise exception 'NIS inválido: confira os 11 dígitos.' using errcode = '22023';
  end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'E-mail inválido.' using errcode = '22023';
  end if;
  -- editar contatos exige ver contatos (perfis com contatos mascarados não sobrescrevem às cegas)
  if not v_novo and not v_contatos and (p ? 'cpf' or p ? 'telefone' or p ? 'whatsapp' or p ? 'email' or p ? 'nis' or p ? 'rg' or p ? 'telefone_2') then
    raise exception 'Seu perfil vê CPF e contatos mascarados e não pode alterá-los.' using errcode = '42501';
  end if;
  if v_novo and v_crianca is not null and not iara.can_access_student(v_crianca) then
    raise exception 'Criança fora do seu escopo.' using errcode = '42501';
  end if;
  if v_novo and not coalesce((p ->> 'forcar')::boolean, false) then
    select jsonb_agg(jsonb_build_object('id', x.id, 'nome', x.full_name, 'telefone', iara.mask_phone(coalesce(x.whatsapp_phone, x.primary_phone))))
    into v_dups from iara.guardians x
    where (v_cpf is not null and iara.digitos(x.cpf) = v_cpf)
       or (iara.norm(x.full_name) = iara.norm(v_nome) and v_nasc is not null and x.birth_date = v_nasc);
    if v_dups is not null then
      return jsonb_build_object('ok', false, 'duplicados', v_dups,
        'mensagem', 'Possível cadastro duplicado (mesmo CPF, ou mesmo nome e nascimento). Confira antes de continuar.');
    end if;
  end if;

  v_old_addr := g.address_id;
  v_addr := g.address_id;
  if jsonb_typeof(p -> 'endereco') = 'object' then
    v_addr := iara.endereco_novo(p -> 'endereco', 'Cadastro do responsável');
  elsif nullif(p ->> 'endereco_id', '') is not null then
    -- mesmo endereço de alguém já cadastrado (ex.: a criança com quem mora): reaproveita o registro
    v_addr := (p ->> 'endereco_id')::uuid;
    if not exists (select 1 from iara.addresses where id = v_addr) or not iara.can_access_address(v_addr) then
      raise exception 'Endereço não encontrado.' using errcode = 'P0002';
    end if;
  end if;

  if v_novo then
    v_id := gen_random_uuid();
    insert into iara.guardians (id, tenant_id, full_name, social_name, cpf, rg, nis, birth_date, gender, nationality, marital_status, education_level,
                                preferred_language, email, primary_phone, secondary_phone, whatsapp_phone, preferred_contact_channel, address_id,
                                occupation, employment_status, monthly_income, family_income, income_bracket, cadunico_status, benefits, household_size,
                                single_mother, accessibility_needs, consent_flags, created_by, updated_by, is_demo)
    values (v_id, 1, v_nome, nullif(btrim(coalesce(p ->> 'nome_social', '')), ''), iara.fmt_cpf(v_cpf), nullif(btrim(coalesce(p ->> 'rg', '')), ''), v_nis,
            v_nasc, v_sexo, coalesce(nullif(p ->> 'nacionalidade', ''), 'BRASILEIRA'), nullif(p ->> 'estado_civil', ''), nullif(p ->> 'escolaridade', ''),
            coalesce(nullif(p ->> 'idioma', ''), 'Português'), v_email, v_tel, v_tel2, coalesce(v_wpp, v_tel),
            coalesce(nullif(p ->> 'canal_preferido', ''), 'WHATSAPP'), v_addr, nullif(btrim(coalesce(p ->> 'ocupacao', '')), ''),
            nullif(p ->> 'situacao_trabalho', ''), nullif(p ->> 'renda_individual', '')::numeric, v_renda, iara.faixa_renda(v_renda),
            coalesce((p ->> 'cadunico')::boolean, false), coalesce(p -> 'beneficios', '[]'::jsonb), nullif(p ->> 'pessoas_domicilio', '')::smallint,
            coalesce((p ->> 'mae_solo')::boolean, false), nullif(btrim(coalesce(p ->> 'acessibilidade', '')), ''),
            jsonb_build_object('lgpd_ciencia', coalesce((p #>> '{consentimento,lgpd_ciencia}')::boolean, true),
                               'whatsapp', coalesce((p #>> '{consentimento,whatsapp}')::boolean, true), 'registrado_em', now()),
            iara.current_user_id(), iara.current_user_id(), coalesce((iara.setting('demo_mode'))::boolean, false));
  else
    update iara.guardians set
      full_name = v_nome,
      social_name = case when p ? 'nome_social' then nullif(btrim(coalesce(p ->> 'nome_social', '')), '') else social_name end,
      cpf = case when p ? 'cpf' then iara.fmt_cpf(v_cpf) else cpf end,
      rg = case when p ? 'rg' then nullif(btrim(coalesce(p ->> 'rg', '')), '') else rg end,
      nis = case when p ? 'nis' then v_nis else nis end,
      birth_date = v_nasc,
      gender = case when p ? 'sexo' then v_sexo else gender end,
      nationality = case when p ? 'nacionalidade' then coalesce(nullif(p ->> 'nacionalidade', ''), 'BRASILEIRA') else nationality end,
      marital_status = case when p ? 'estado_civil' then nullif(p ->> 'estado_civil', '') else marital_status end,
      education_level = case when p ? 'escolaridade' then nullif(p ->> 'escolaridade', '') else education_level end,
      preferred_language = case when p ? 'idioma' then coalesce(nullif(p ->> 'idioma', ''), 'Português') else preferred_language end,
      email = case when p ? 'email' then v_email else email end,
      primary_phone = case when p ? 'telefone' then v_tel else primary_phone end,
      secondary_phone = case when p ? 'telefone_2' then v_tel2 else secondary_phone end,
      whatsapp_phone = case when p ? 'whatsapp' then v_wpp else whatsapp_phone end,
      preferred_contact_channel = case when p ? 'canal_preferido' then coalesce(nullif(p ->> 'canal_preferido', ''), 'WHATSAPP') else preferred_contact_channel end,
      occupation = case when p ? 'ocupacao' then nullif(btrim(coalesce(p ->> 'ocupacao', '')), '') else occupation end,
      employment_status = case when p ? 'situacao_trabalho' then nullif(p ->> 'situacao_trabalho', '') else employment_status end,
      monthly_income = case when p ? 'renda_individual' then nullif(p ->> 'renda_individual', '')::numeric else monthly_income end,
      family_income = case when p ? 'renda_familiar' then v_renda else family_income end,
      income_bracket = case when p ? 'renda_familiar' then iara.faixa_renda(v_renda) else income_bracket end,
      cadunico_status = case when p ? 'cadunico' then coalesce((p ->> 'cadunico')::boolean, false) else cadunico_status end,
      benefits = case when p ? 'beneficios' then coalesce(p -> 'beneficios', '[]'::jsonb) else benefits end,
      household_size = case when p ? 'pessoas_domicilio' then nullif(p ->> 'pessoas_domicilio', '')::smallint else household_size end,
      single_mother = case when p ? 'mae_solo' then coalesce((p ->> 'mae_solo')::boolean, false) else single_mother end,
      accessibility_needs = case when p ? 'acessibilidade' then nullif(btrim(coalesce(p ->> 'acessibilidade', '')), '') else accessibility_needs end,
      consent_flags = case when jsonb_typeof(p -> 'consentimento') = 'object'
                           then consent_flags || jsonb_build_object('lgpd_ciencia', coalesce((p #>> '{consentimento,lgpd_ciencia}')::boolean, true),
                                                                    'whatsapp', coalesce((p #>> '{consentimento,whatsapp}')::boolean, true),
                                                                    'atualizado_em', now())
                           else consent_flags end,
      address_id = v_addr,
      updated_by = iara.current_user_id()
    where id = v_id;
    -- mudança de endereço: as crianças (e os demais responsáveis delas) que moravam no endereço anterior mudam junto
    if v_addr is distinct from v_old_addr and v_old_addr is not null and coalesce((p #>> '{endereco,aplicar_criancas}')::boolean, true) then
      select coalesce(array_agg(distinct s.id), '{}') into v_alunos
      from iara.students s join iara.student_guardians sg on sg.student_id = s.id
      where sg.guardian_id = v_id and sg.end_date is null and s.address_id = v_old_addr;
      v_fila_antes := iara.queue_snapshot(v_alunos);
      update iara.students set address_id = v_addr, updated_by = iara.current_user_id() where id = any (v_alunos);
      update iara.guardians set address_id = v_addr, updated_by = iara.current_user_id()
      where address_id = v_old_addr and id <> v_id
        and id in (select sg.guardian_id from iara.student_guardians sg where sg.student_id = any (v_alunos) and sg.end_date is null);
      perform iara.requeue_students(v_alunos);
      v_impactos := iara.queue_impacts(v_fila_antes, iara.queue_snapshot(v_alunos));
    end if;
  end if;

  if v_novo and v_crianca is not null then
    insert into iara.student_guardians (student_id, guardian_id, relationship, is_primary, legal_authority_status)
    values (v_crianca, v_id, coalesce(nullif(p #>> '{crianca,parentesco}', ''), 'RESPONSAVEL_LEGAL'),
            not exists (select 1 from iara.student_guardians x where x.student_id = v_crianca and x.end_date is null), 'DECLARADO')
    on conflict (student_id, guardian_id) do nothing;
    perform iara.audit_event('VINCULO_CRIADO', 'student_guardians', v_crianca::text, iara.my_unit(),
      format('Responsável %s vinculado à criança', v_nome),
      (select to_jsonb(x) from iara.student_guardians x where x.student_id = v_crianca and x.guardian_id = v_id), null);
  end if;

  perform iara.audit_event(case when v_novo then 'CADASTRO_RESPONSAVEL_CRIADO' else 'CADASTRO_RESPONSAVEL_ATUALIZADO' end, 'guardians', v_id::text, iara.my_unit(),
    case when v_novo then format('Cadastro do responsável criado: %s', v_nome)
         else format('Cadastro do responsável atualizado: %s%s', v_nome,
                     case when v_addr is distinct from v_old_addr then format(' (endereço alterado; %s criança(s) mudaram junto)', cardinality(v_alunos)) else '' end) end);
  return jsonb_build_object('ok', true, 'id', v_id, 'novo', v_novo, 'endereco_alterado', v_addr is distinct from v_old_addr and not v_novo,
                            'criancas_mudaram', cardinality(v_alunos), 'impactos_fila', v_impactos,
                            'cadastro', api.responsavel_cadastro(jsonb_build_object('id', v_id)));
end $$;

-- vínculo aluno-responsável (cap. 12.1): cria ou altera; o encerramento guarda a data (histórico)
create or replace function api.vinculo_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_aluno uuid := nullif(p ->> 'aluno_id', '')::uuid;
  v_resp uuid := nullif(p ->> 'responsavel_id', '')::uuid;
  v_antes jsonb;
  v_depois jsonb;
  v_principal boolean := coalesce((p ->> 'principal')::boolean, false);
  v_situacao text := coalesce(nullif(p ->> 'situacao_legal', ''), 'DECLARADO');
begin
  perform iara.require_perm('students.write');
  if v_aluno is null or v_resp is null then
    raise exception 'Informe a criança e o responsável.' using errcode = '22023';
  end if;
  if not iara.can_access_student(v_aluno) then
    raise exception 'Criança fora do seu escopo.' using errcode = '42501';
  end if;
  if not exists (select 1 from iara.guardians where id = v_resp) or not (iara.can_access_guardian(v_resp) or iara.my_scope() = 'NETWORK') then
    raise exception 'Responsável não encontrado ou fora do seu escopo.' using errcode = 'P0002';
  end if;
  if v_situacao not in ('CONFIRMADO', 'DECLARADO', 'A_VERIFICAR') then
    raise exception 'Situação legal inválida.' using errcode = '22023';
  end if;
  select to_jsonb(x) into v_antes from iara.student_guardians x where x.student_id = v_aluno and x.guardian_id = v_resp;
  if v_principal then
    update iara.student_guardians set is_primary = false where student_id = v_aluno and guardian_id <> v_resp and is_primary;
  end if;
  insert into iara.student_guardians (student_id, guardian_id, relationship, is_primary, can_pick_up, can_receive_notifications, legal_authority_status)
  values (v_aluno, v_resp, coalesce(nullif(p ->> 'parentesco', ''), 'RESPONSAVEL_LEGAL'),
          v_principal or not exists (select 1 from iara.student_guardians x where x.student_id = v_aluno and x.end_date is null),
          coalesce((p ->> 'pode_buscar')::boolean, true), coalesce((p ->> 'recebe_avisos')::boolean, true), v_situacao)
  on conflict (student_id, guardian_id) do update set
    relationship = excluded.relationship, is_primary = excluded.is_primary or (iara.student_guardians.is_primary and not (p ? 'principal')),
    can_pick_up = excluded.can_pick_up, can_receive_notifications = excluded.can_receive_notifications,
    legal_authority_status = excluded.legal_authority_status, end_date = null;
  select to_jsonb(x) into v_depois from iara.student_guardians x where x.student_id = v_aluno and x.guardian_id = v_resp;
  perform iara.audit_event(case when v_antes is null then 'VINCULO_CRIADO' else 'VINCULO_ALTERADO' end, 'student_guardians', v_aluno::text, iara.my_unit(),
    format('Vínculo com %s: %s', (select full_name from iara.guardians where id = v_resp), lower(v_depois ->> 'relationship')), v_depois, v_antes);
  return jsonb_build_object('ok', true, 'vinculo', v_depois);
end $$;

create or replace function api.vinculo_encerrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_aluno uuid := nullif(p ->> 'aluno_id', '')::uuid;
  v_resp uuid := nullif(p ->> 'responsavel_id', '')::uuid;
  v_motivo text := nullif(btrim(coalesce(p ->> 'motivo', '')), '');
  v_antes jsonb;
  v_depois jsonb;
begin
  perform iara.require_perm('students.write');
  if not iara.can_access_student(v_aluno) then
    raise exception 'Criança fora do seu escopo.' using errcode = '42501';
  end if;
  if v_motivo is null or length(v_motivo) < 5 then
    raise exception 'Informe o motivo do encerramento do vínculo.' using errcode = '22023';
  end if;
  select to_jsonb(x) into v_antes from iara.student_guardians x where x.student_id = v_aluno and x.guardian_id = v_resp and x.end_date is null;
  if v_antes is null then
    raise exception 'Vínculo ativo não encontrado.' using errcode = 'P0002';
  end if;
  if (select count(*) from iara.student_guardians x where x.student_id = v_aluno and x.end_date is null) <= 1 then
    raise exception 'A criança precisa de ao menos um responsável. Vincule outro responsável antes de encerrar este.' using errcode = '22023';
  end if;
  update iara.student_guardians set end_date = current_date, is_primary = false, can_pick_up = false, can_receive_notifications = false
  where student_id = v_aluno and guardian_id = v_resp;
  if (v_antes ->> 'is_primary')::boolean then
    update iara.student_guardians set is_primary = true
    where student_id = v_aluno and end_date is null
      and guardian_id = (select x.guardian_id from iara.student_guardians x where x.student_id = v_aluno and x.end_date is null
                         order by (x.relationship in ('MAE', 'PAI')) desc, x.start_date limit 1);
  end if;
  select to_jsonb(x) into v_depois from iara.student_guardians x where x.student_id = v_aluno and x.guardian_id = v_resp;
  perform iara.audit_event('VINCULO_ENCERRADO', 'student_guardians', v_aluno::text, iara.my_unit(),
    format('Vínculo com %s encerrado. Motivo: %s', (select full_name from iara.guardians where id = v_resp), v_motivo), v_depois, v_antes);
  return jsonb_build_object('ok', true, 'vinculo', v_depois);
end $$;

-- composição familiar (cap. 11.1): pessoas que moram no domicílio e não têm cadastro próprio
create or replace function api.domicilio_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_resp uuid := nullif(p ->> 'responsavel_id', '')::uuid;
  v_id uuid := nullif(p ->> 'id', '')::uuid;
  v_nome text := regexp_replace(btrim(coalesce(p ->> 'nome', '')), '\s+', ' ', 'g');
  v_nasc date;
begin
  perform iara.require_perm('guardians.write');
  if v_resp is null or not iara.can_access_guardian(v_resp) then
    raise exception 'Responsável não encontrado ou fora do seu escopo.' using errcode = 'P0002';
  end if;
  if length(v_nome) < 3 then
    raise exception 'Informe o nome da pessoa.' using errcode = '22023';
  end if;
  if nullif(p ->> 'parentesco', '') is null then
    raise exception 'Informe o parentesco com o responsável.' using errcode = '22023';
  end if;
  begin
    v_nasc := nullif(p ->> 'nascimento', '')::date;
  exception when others then
    raise exception 'Data de nascimento inválida.' using errcode = '22023';
  end;
  if v_nasc > current_date then
    raise exception 'A data de nascimento está no futuro.' using errcode = '22023';
  end if;
  if v_id is null then
    insert into iara.household_members (guardian_id, full_name, relationship, birth_date, occupation, monthly_income, notes, created_by, is_demo)
    values (v_resp, v_nome, p ->> 'parentesco', v_nasc, nullif(btrim(coalesce(p ->> 'ocupacao', '')), ''), nullif(p ->> 'renda', '')::numeric,
            nullif(btrim(coalesce(p ->> 'observacoes', '')), ''), iara.current_user_id(), coalesce((iara.setting('demo_mode'))::boolean, false))
    returning id into v_id;
  else
    update iara.household_members set full_name = v_nome, relationship = p ->> 'parentesco', birth_date = v_nasc,
      occupation = nullif(btrim(coalesce(p ->> 'ocupacao', '')), ''), monthly_income = nullif(p ->> 'renda', '')::numeric,
      notes = nullif(btrim(coalesce(p ->> 'observacoes', '')), '')
    where id = v_id and guardian_id = v_resp;
    if not found then
      raise exception 'Pessoa do domicílio não encontrada.' using errcode = 'P0002';
    end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function api.domicilio_remover(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  h iara.household_members;
begin
  perform iara.require_perm('guardians.write');
  select * into h from iara.household_members where id = nullif(p ->> 'id', '')::uuid;
  if not found or not iara.can_access_guardian(h.guardian_id) then
    raise exception 'Pessoa do domicílio não encontrada.' using errcode = 'P0002';
  end if;
  delete from iara.household_members where id = h.id;
  return jsonb_build_object('ok', true);
end $$;

-- 5. Fichas 360º com os dados novos ------------------------------------------------------------------------
create or replace function iara.address_json(p_address uuid) returns jsonb
language sql stable security definer set search_path = iara, extensions, public
as $$
  select case when iara.can_access_address(a.id) then jsonb_build_object(
    'id', a.id, 'street', a.street, 'number', a.number, 'complement', a.complement, 'neighborhood', a.neighborhood,
    'postal_code', a.postal_code, 'city', a.city, 'state', a.state, 'lat', st_y(a.location::geometry), 'lng', st_x(a.location::geometry),
    'precision', a.geocode_precision, 'source', a.geocode_source, 'zone', a.zone, 'reference', a.reference_point,
    'approximate', iara.endereco_aproximado(a.geocode_precision), 'territory_id', a.territory_id,
    'territory', (select name from iara.territories t where t.id = a.territory_id),
    'line', a.street || ', ' || coalesce(a.number, 's/n') || coalesce(' — ' || a.complement, '') || ' · ' || coalesce(a.neighborhood, '') || ' · ' || a.city || '/' || a.state)
  end
  from iara.addresses a where a.id = p_address
$$;

create or replace function iara.guardian_json(g iara.guardians) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object(
    'id', g.id, 'full_name', g.full_name, 'social_name', g.social_name,
    'cpf', case when iara.can_see_contacts() then g.cpf else iara.mask_cpf(g.cpf) end,
    'rg', case when iara.can_see_contacts() then g.rg else iara.mascara_doc(g.rg) end,
    'phone', case when iara.can_see_contacts() then g.primary_phone else iara.mask_phone(g.primary_phone) end,
    'phone2', case when iara.can_see_contacts() then g.secondary_phone else iara.mask_phone(g.secondary_phone) end,
    'whatsapp', case when iara.can_see_contacts() then g.whatsapp_phone else iara.mask_phone(g.whatsapp_phone) end,
    'email', case when iara.can_see_contacts() then g.email else regexp_replace(coalesce(g.email, ''), '^(.).*(@.*)$', '\1•••\2') end,
    'contacts_masked', not iara.can_see_contacts(),
    'preferred_channel', g.preferred_contact_channel, 'birth_date', g.birth_date, 'gender', g.gender, 'occupation', g.occupation,
    'employment_status', g.employment_status, 'monthly_income', g.monthly_income, 'family_income', g.family_income, 'income_bracket', g.income_bracket,
    'cadunico', g.cadunico_status, 'single_mother', g.single_mother, 'nis', case when iara.can_see_contacts() then g.nis else null end, 'benefits', g.benefits,
    'education_level', g.education_level, 'household_size', g.household_size, 'marital_status', g.marital_status,
    'nationality', g.nationality, 'language', g.preferred_language, 'consent', g.consent_flags, 'is_demo', g.is_demo)
$$;

create or replace function api.student_detail(p jsonb) returns jsonb
language plpgsql volatile security invoker set search_path = iara, extensions, public
as $$
declare
  s iara.students;
  v_sens jsonb;
  v_school record;
  v jsonb;
  v_rule jsonb;
  v_docs boolean := iara.can_see_contacts();
  v_pend text[];
begin
  select * into s from iara.students where id = (p ->> 'student_id')::uuid;
  if not found then
    raise exception 'Aluno não encontrado ou sem vínculo/permissão para consulta.' using errcode = 'P0002';
  end if;
  if iara.has_perm('students.read_sensitive') then
    select to_jsonb(x) - 'student_id' into v_sens from iara.student_sensitive x where x.student_id = s.id;
    if v_sens is not null then
      perform iara.audit_event('VIEW_SENSITIVE', 'students', s.id::text, null, 'Consulta a dados sensíveis (AEE/saúde/restrições).');
    end if;
  end if;
  select e.id as enrollment_id, e.status, c.id as class_id, c.class_name, c.shift, c.grade_level_id, u.id as unit_id, u.name as unit_name,
         u.lat, u.lng, round(st_distance(u.location, a.location))::int as dist_m
  into v_school
  from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.education_units u on u.id = e.unit_id
  left join iara.addresses a on a.id = s.address_id
  where e.student_id = s.id and e.status = 'ACTIVE' limit 1;
  v_rule := iara.grade_for_birthdate(s.birth_date);
  v_pend := iara.aluno_pendencias(s, exists (select 1 from iara.student_guardians sg where sg.student_id = s.id and sg.end_date is null));

  select jsonb_build_object(
    'student', jsonb_build_object('id', s.id, 'full_name', s.full_name, 'social_name', s.social_name, 'birth_date', s.birth_date,
      'age', iara.age_text(s.birth_date), 'gender', s.gender, 'registry', s.student_registry_number, 'status', s.status,
      'aee', s.aee_status, 'transport_need', s.transport_need, 'transport_status', s.school_transport_status,
      'accessibility', s.accessibility_needs, 'avatar_seed', s.avatar_seed, 'is_demo', s.is_demo, 'created_at', s.created_at,
      'updated_at', s.updated_at, 'race_color', s.race_color, 'nationality', s.nationality, 'birth_country', s.birth_country,
      'birth_city', s.birth_city, 'birth_state', s.birth_state, 'parent1', s.parent1_name, 'parent2', s.parent2_name,
      'image_consent', s.image_consent, 'inep_id', s.inep_id,
      'cpf', case when v_docs then iara.fmt_cpf(s.cpf) else iara.mask_cpf(s.cpf) end,
      'nis', case when v_docs then s.nis else iara.mascara_doc(s.nis) end,
      'birth_certificate', case when v_docs then s.birth_certificate else iara.mascara_doc(s.birth_certificate) end,
      'sus_card', case when v_docs then s.sus_card else iara.mascara_doc(s.sus_card) end,
      'docs_masked', not v_docs),
    'registry', jsonb_build_object('pending', to_jsonb(v_pend), 'complete_pct', round(100.0 * (7 - cardinality(v_pend)) / 7),
                                   'can_edit', iara.has_perm('students.write')),
    'grade_rule', v_rule,
    'age_grade_distortion', v_school.grade_level_id is not null and coalesce((v_rule ->> 'grade_level_id')::int, 0) > v_school.grade_level_id,
    'sensitive', v_sens,
    'sensitive_restricted', not iara.has_perm('students.read_sensitive') and s.aee_status,
    'address', iara.address_json(s.address_id),
    'school', case when v_school.enrollment_id is not null then jsonb_build_object(
      'enrollment_id', v_school.enrollment_id, 'class_id', v_school.class_id, 'class_name', v_school.class_name, 'shift', v_school.shift,
      'unit_id', v_school.unit_id, 'unit_name', v_school.unit_name, 'distance_m', v_school.dist_m, 'lat', v_school.lat, 'lng', v_school.lng) end,
    'guardians', coalesce((select jsonb_agg(iara.guardian_json(g) || jsonb_build_object('relationship', sg.relationship, 'is_primary', sg.is_primary,
                                                                                        'can_pick_up', sg.can_pick_up, 'legal_status', sg.legal_authority_status,
                                                                                        'can_notify', sg.can_receive_notifications)
                                            order by sg.is_primary desc)
                           from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
                           where sg.student_id = s.id and sg.end_date is null), '[]'::jsonb),
    'former_guardians', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'full_name', g.full_name, 'relationship', sg.relationship,
                                                                      'start_date', sg.start_date, 'end_date', sg.end_date) order by sg.end_date desc)
                           from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
                           where sg.student_id = s.id and sg.end_date is not null), '[]'::jsonb),
    'siblings', coalesce((select jsonb_agg(distinct jsonb_build_object('id', s2.id, 'name', s2.full_name, 'age', iara.age_text(s2.birth_date),
        'unit', (select u.short_name from iara.enrollments e join iara.education_units u on u.id = e.unit_id where e.student_id = s2.id and e.status = 'ACTIVE' limit 1)))
      from iara.student_guardians a1 join iara.student_guardians a2 on a2.guardian_id = a1.guardian_id and a2.student_id <> a1.student_id
      join iara.students s2 on s2.id = a2.student_id where a1.student_id = s.id and a1.end_date is null and a2.end_date is null), '[]'::jsonb),
    'enrollments', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'status', e.status, 'school_year', e.school_year,
        'unit_id', e.unit_id, 'unit', u.short_name, 'class_id', c.id, 'class', c.class_name, 'shift', c.shift, 'entry_type', e.entry_type,
        'exit_type', e.exit_type, 'enrollment_date', e.enrollment_date, 'end_date', e.end_date) order by e.created_at desc)
      from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.education_units u on u.id = e.unit_id where e.student_id = s.id), '[]'::jsonb),
    'documents', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'type', d.doc_type, 'status', d.status, 'file', d.file_name,
        'received_at', d.received_at, 'validated_at', d.validated_at, 'sensitive', d.is_sensitive, 'case_id', d.case_id) order by d.doc_type, d.created_at desc)
      from iara.documents d where d.student_id = s.id), '[]'::jsonb),
    'cases', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'protocol', c.protocol_number, 'type', c.case_type,
        'type_name', sc.name, 'status', c.status, 'subject', c.subject, 'opened_at', c.opened_at, 'closed_at', c.closed_at,
        'sla_due_at', c.sla_due_at, 'channel', c.channel) order by c.opened_at desc)
      from iara.service_cases c join iara.service_catalog sc on sc.code = c.case_type where c.student_id = s.id), '[]'::jsonb),
    'queue', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'status', w.status, 'position', w.position, 'score', w.priority_score,
        'flags', w.priority_flags, 'breakdown', w.score_breakdown, 'category', w.demand_category, 'unit_id', w.preferred_unit_id,
        'unit', u.short_name, 'grade', gl.name, 'grade_level_id', w.grade_level_id, 'entered_at', w.entered_at, 'rule_version', w.rule_version,
        'distance_m', w.home_distance_m, 'shift', w.preferred_shift, 'full_time', w.full_time_requested) order by w.entered_at desc)
      from iara.waiting_list_entries w join iara.education_units u on u.id = w.preferred_unit_id
      join iara.grade_levels gl on gl.id = w.grade_level_id where w.student_id = s.id), '[]'::jsonb),
    'offers', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'status', o.status, 'unit_id', o.unit_id, 'unit', u.short_name,
        'class_id', o.class_id, 'class', c.class_name, 'shift', c.shift, 'offered_at', o.offered_at, 'expires_at', o.expires_at,
        'accepted_at', o.accepted_at, 'declined_at', o.declined_at, 'decline_reason', o.decline_reason) order by o.offered_at desc)
      from iara.vacancy_offers o join iara.classes c on c.id = o.class_id join iara.education_units u on u.id = o.unit_id where o.student_id = s.id), '[]'::jsonb),
    'audit', case when iara.has_perm('audit.read') then coalesce((select jsonb_agg(jsonb_build_object('action', a.action, 'entity', a.entity_type,
        'actor', a.actor_label, 'at', a.occurred_at, 'summary', a.summary, 'after', a.after_json) order by a.occurred_at desc)
      from (select * from iara.audit_log al where al.entity_id = s.id::text order by al.occurred_at desc limit 20) a), '[]'::jsonb) end
  ) into v;
  return v;
end $$;

create or replace function api.guardian_detail(p jsonb) returns jsonb
language plpgsql stable security invoker set search_path = iara, public
as $$
declare
  g iara.guardians;
  v jsonb;
  v_pend text[];
begin
  select * into g from iara.guardians where id = (p ->> 'guardian_id')::uuid;
  if not found then
    raise exception 'Responsável não encontrado ou sem permissão.' using errcode = 'P0002';
  end if;
  v_pend := iara.responsavel_pendencias(g);
  select jsonb_build_object(
    'guardian', iara.guardian_json(g),
    'registry', jsonb_build_object('pending', to_jsonb(v_pend), 'complete_pct', round(100.0 * (5 - cardinality(v_pend)) / 5),
                                   'can_edit', iara.has_perm('guardians.write')),
    'address', iara.address_json(g.address_id),
    'students', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.full_name, 'age', iara.age_text(s.birth_date), 'status', s.status,
        'relationship', sg.relationship, 'is_primary', sg.is_primary, 'avatar_seed', s.avatar_seed, 'same_address', s.address_id = g.address_id,
        'unit', (select u.short_name from iara.enrollments e join iara.education_units u on u.id = e.unit_id where e.student_id = s.id and e.status = 'ACTIVE' limit 1))
        order by s.birth_date)
      from iara.student_guardians sg join iara.students s on s.id = sg.student_id where sg.guardian_id = g.id and sg.end_date is null), '[]'::jsonb),
    'household', coalesce((select jsonb_agg(iara.guardian_json(g2) || jsonb_build_object('shared_students', n) order by g2.full_name)
      from (select sg2.guardian_id, count(*) n from iara.student_guardians sg1 join iara.student_guardians sg2 on sg2.student_id = sg1.student_id
            where sg1.guardian_id = g.id and sg2.guardian_id <> g.id and sg1.end_date is null and sg2.end_date is null group by sg2.guardian_id) h
      join iara.guardians g2 on g2.id = h.guardian_id), '[]'::jsonb),
    'household_members', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'name', h.full_name, 'relationship', h.relationship,
        'birth_date', h.birth_date, 'age', iara.age_text(h.birth_date), 'occupation', h.occupation, 'income', h.monthly_income)
        order by h.birth_date nulls last) from iara.household_members h where h.guardian_id = g.id and iara.can_access_guardian(g.id)), '[]'::jsonb),
    'cases', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'protocol', c.protocol_number, 'type_name', sc.name, 'status', c.status,
        'subject', c.subject, 'opened_at', c.opened_at, 'channel', c.channel) order by c.opened_at desc)
      from iara.service_cases c join iara.service_catalog sc on sc.code = c.case_type where c.guardian_id = g.id), '[]'::jsonb),
    'conversations', coalesce((select jsonb_agg(jsonb_build_object('id', cv.id, 'state', cv.state, 'channel', cv.channel, 'last_message_at', cv.last_message_at,
        'summary', cv.summary) order by cv.last_message_at desc) from iara.conversations cv where cv.guardian_id = g.id), '[]'::jsonb),
    'notifications', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'title', n.title, 'body', n.body, 'channel', n.channel,
        'status', n.status, 'at', n.created_at) order by n.created_at desc)
      from (select * from iara.notifications n2 where n2.guardian_id = g.id order by n2.created_at desc limit 15) n), '[]'::jsonb)
  ) into v;
  return v;
end $$;

-- 6. Limpeza da demonstração: desfaz também edições de cadastro feitas por sessões ----------------------------
-- Restaura colunas pelo valor anterior registrado na auditoria (jsonb_populate_record sobre a linha atual).
create or replace function iara.demo_restaurar_colunas(p_tabela text, p_chave text, p_id uuid, p_orig jsonb, p_excluir text[] default '{}')
returns void
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_cols text;
begin
  select string_agg(format('%I', k), ', ') into v_cols
  from jsonb_object_keys(p_orig) k
  where k <> all (array['id', 'student_id', 'guardian_id', 'created_at', 'updated_at', 'created_by'] || p_excluir)
    and exists (select 1 from information_schema.columns c where c.table_schema = 'iara' and c.table_name = p_tabela and c.column_name = k);
  if v_cols is null then
    return;
  end if;
  execute format('update iara.%1$I t set (%2$s) = (select %2$s from jsonb_populate_record(t, $1)) where t.%3$I = $2', p_tabela, v_cols, p_chave)
  using p_orig, p_id;
end $$;

-- p_usuarios: limpa só o que essas sessões fizeram (ex.: um teste), sem tocar no resto nem reiniciar a família da Maria
drop function if exists iara.demo_purge_session_data(text);
create or replace function iara.demo_purge_session_data(p_origem text default null, p_usuarios uuid[] default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_keep_students uuid[] := array_remove(array[nullif(iara.setting('demo_student_ana'), '')::uuid,
                                               nullif(iara.setting('demo_student_davi'), '')::uuid], null);
  v_keep_guardians uuid[] := array_remove(array[nullif(iara.setting('demo_guardian_maria'), '')::uuid,
                                                nullif(iara.setting('demo_guardian_jorge'), '')::uuid], null);
  v_addr_maria uuid := nullif(iara.setting('demo_address_maria'), '')::uuid;
  v_users uuid[] := coalesce(p_usuarios, iara.demo_session_users(p_origem));
  v_guardians uuid[];
  v_students uuid[];
  v_cases uuid[];
  v_entries uuid[];
  v_offers uuid[];
  v_enrolls uuid[];
  v_blocks uuid[];
  v_classes uuid[];
  v_addrs uuid[];
  v_requeue uuid[] := '{}';
  v_names text;
  r record;
  q record;
  d interval;
  v_queues jsonb := '[]';
  v_restored integer := 0;
  n_notif integer; n_vev integer; n_conv integer; n_events integer; n_docs integer; n_addr integer; n_dom integer := 0; n_vinc integer := 0;
  v_reset jsonb;
  v_out jsonb;
  n_wa integer := 0;
begin
  if not coalesce((iara.setting('demo_mode'))::boolean, false) then
    raise exception 'Limpeza disponível apenas no modo demonstração.' using errcode = '42501';
  end if;
  if p_origem is not null and p_origem not in ('DEMO', 'WHATSAPP') then
    raise exception 'Origem desconhecida: % (use DEMO, WHATSAPP ou deixe em branco para tudo).', p_origem using errcode = '22023';
  end if;

  -- 1. o que as sessões criaram
  select coalesce(array_agg(id), '{}'), string_agg(full_name, ', ' order by full_name) into v_guardians, v_names
  from iara.guardians where created_by = any (v_users) and not (id = any (v_keep_guardians));
  select coalesce(array_agg(id), '{}') into v_students from iara.students
  where created_by = any (v_users) and not (id = any (v_keep_students));
  select coalesce(array_agg(id), '{}') into v_cases from iara.service_cases
  where created_by = any (v_users) or guardian_id = any (v_guardians) or student_id = any (v_students);
  select coalesce(array_agg(id), '{}') into v_entries from iara.waiting_list_entries
  where created_by = any (v_users) or student_id = any (v_students) or case_id = any (v_cases);
  select coalesce(array_agg(id), '{}') into v_offers from iara.vacancy_offers
  where created_by = any (v_users) or student_id = any (v_students) or case_id = any (v_cases) or waiting_list_entry_id = any (v_entries);
  select coalesce(array_agg(id), '{}') into v_enrolls from iara.enrollments
  where created_by = any (v_users) or student_id = any (v_students);
  select coalesce(array_agg(id), '{}'), coalesce(array_agg(distinct class_id), '{}') into v_blocks, v_classes
  from iara.vacancy_blocks where created_by = any (v_users);
  select coalesce(array_agg(a.id), '{}') into v_addrs from iara.addresses a
  where a.id is distinct from v_addr_maria
    and (exists (select 1 from iara.audit_log l where l.entity_type = 'addresses' and l.entity_id = a.id::text
                 and l.action = 'INSERT' and l.user_id = any (v_users))
         or exists (select 1 from iara.guardians g where g.address_id = a.id and g.id = any (v_guardians))
         or exists (select 1 from iara.students s where s.address_id = a.id and s.id = any (v_students)));
  select coalesce(jsonb_agg(distinct jsonb_build_object('u', preferred_unit_id, 'g', grade_level_id)), '[]') into v_queues
  from iara.waiting_list_entries where id = any (v_entries) and status in ('WAITING', 'OFFERED', 'ACCEPTED');

  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.notifications n
  where n.guardian_id = any (v_guardians) or n.student_id = any (v_students) or n.case_id = any (v_cases)
     or exists (select 1 from iara.vacancy_offers o where o.id = any (v_offers) and o.student_id = n.student_id
                and n.created_at >= o.offered_at - interval '1 minute');
  get diagnostics n_notif = row_count;
  delete from iara.vacancy_events v
  where v.user_id = any (v_users)
     or exists (select 1 from iara.vacancy_offers o where o.id = any (v_offers) and v.class_id = o.class_id
                and v.reference = 'Oferta ' || substr(o.id::text, 1, 8))
     or exists (select 1 from iara.vacancy_blocks b where b.id = any (v_blocks) and v.class_id = b.class_id
                and v.reference = 'Bloqueio ' || substr(b.id::text, 1, 8));
  get diagnostics n_vev = row_count;
  delete from iara.vacancy_offers where id = any (v_offers);
  delete from iara.vacancy_blocks where id = any (v_blocks);
  update iara.students set current_enrollment_id = null where current_enrollment_id = any (v_enrolls);
  update iara.enrollments set previous_enrollment_id = null where previous_enrollment_id = any (v_enrolls);
  delete from iara.enrollments where id = any (v_enrolls);
  delete from iara.waiting_list_entries where id = any (v_entries);
  delete from iara.conversations where owner_user_id = any (v_users) or guardian_id = any (v_guardians);
  get diagnostics n_conv = row_count;
  delete from iara.case_events where user_id = any (v_users) or message like 'Cenário de demonstração reiniciado%';
  get diagnostics n_events = row_count;
  delete from iara.documents dc
  where dc.guardian_id = any (v_guardians) or dc.student_id = any (v_students) or dc.case_id = any (v_cases)
     or exists (select 1 from iara.audit_log l where l.entity_type = 'documents' and l.entity_id = dc.id::text
                and l.action = 'INSERT' and l.user_id = any (v_users));
  get diagnostics n_docs = row_count;
  delete from iara.service_cases where id = any (v_cases);
  delete from iara.household_members where created_by = any (v_users);
  get diagnostics n_dom = row_count;
  delete from iara.students where id = any (v_students);
  delete from iara.guardians where id = any (v_guardians);

  -- 2. linhas do cenário gerado alteradas por sessões voltam ao valor original (a família da Maria fica com o reinício)
  for r in select o.entity_id, o.orig, o.since from iara.demo_original_values('waiting_list_entries', v_users) o
           join iara.waiting_list_entries w on w.id::text = o.entity_id
           where not (w.student_id = any (v_keep_students)) loop
    update iara.waiting_list_entries w set
      status = case when r.orig ? 'status' then r.orig ->> 'status' else w.status end,
      demand_category = case when r.orig ? 'demand_category' then r.orig ->> 'demand_category' else w.demand_category end
    where w.id = r.entity_id::uuid;
    perform iara.compute_queue_priority(r.entity_id::uuid);
    select v_queues || jsonb_build_array(jsonb_build_object('u', w.preferred_unit_id, 'g', w.grade_level_id)) into v_queues
    from iara.waiting_list_entries w where w.id = r.entity_id::uuid;
    v_restored := v_restored + 1;
  end loop;

  for r in select o.entity_id, o.orig, o.since from iara.demo_original_values('service_cases', v_users) o
           join iara.service_cases c on c.id::text = o.entity_id
           where not coalesce(c.guardian_id = any (v_keep_guardians) or c.student_id = any (v_keep_students), false) loop
    d := iara.demo_shift_since(r.since);
    update iara.service_cases c set
      status = case when r.orig ? 'status' then r.orig ->> 'status' else c.status end,
      resolution_code = case when r.orig ? 'resolution_code' then r.orig ->> 'resolution_code' else c.resolution_code end,
      resolution_notes = case when r.orig ? 'resolution_notes' then r.orig ->> 'resolution_notes' else c.resolution_notes end,
      closed_at = case when r.orig ? 'closed_at' then (r.orig ->> 'closed_at')::timestamptz + d else c.closed_at end,
      sla_due_at = case when r.orig ? 'sla_due_at' then (r.orig ->> 'sla_due_at')::timestamptz + d else c.sla_due_at end,
      assigned_user_id = case when r.orig ? 'assigned_user_id' then (r.orig ->> 'assigned_user_id')::uuid else c.assigned_user_id end,
      assigned_team = case when r.orig ? 'assigned_team' then r.orig ->> 'assigned_team' else c.assigned_team end
    where c.id = r.entity_id::uuid;
    v_restored := v_restored + 1;
  end loop;

  for r in select o.entity_id, o.orig, o.since from iara.demo_original_values('documents', v_users) o
           join iara.documents dc on dc.id::text = o.entity_id
           where not coalesce(dc.student_id = any (v_keep_students) or dc.guardian_id = any (v_keep_guardians), false) loop
    d := iara.demo_shift_since(r.since);
    update iara.documents dc set
      status = case when r.orig ? 'status' then r.orig ->> 'status' else dc.status end,
      received_at = case when r.orig ? 'received_at' then (r.orig ->> 'received_at')::timestamptz + d else dc.received_at end,
      validated_at = case when r.orig ? 'validated_at' then (r.orig ->> 'validated_at')::timestamptz + d else dc.validated_at end,
      validated_by = case when r.orig ? 'validated_by' then (r.orig ->> 'validated_by')::uuid else dc.validated_by end,
      file_name = case when r.orig ? 'file_name' then r.orig ->> 'file_name' else dc.file_name end,
      notes = case when r.orig ? 'notes' then r.orig ->> 'notes' else dc.notes end
    where dc.id = r.entity_id::uuid;
    v_restored := v_restored + 1;
  end loop;

  -- alunos: situação/matrícula como antes; demais colunas (dados pessoais, endereço) pelo valor original
  for r in select o.entity_id, o.orig from iara.demo_original_values('students', v_users) o
           join iara.students s on s.id::text = o.entity_id
           where not (s.id = any (v_keep_students)) loop
    update iara.students s set
      status = case when r.orig ? 'status' then r.orig ->> 'status' else s.status end,
      current_enrollment_id = case when r.orig ? 'current_enrollment_id'
                                   then (select e.id from iara.enrollments e where e.id = (r.orig ->> 'current_enrollment_id')::uuid)
                                   else s.current_enrollment_id end
    where s.id = r.entity_id::uuid;
    perform iara.demo_restaurar_colunas('students', 'id', r.entity_id::uuid, r.orig, array['status', 'current_enrollment_id', 'updated_by']);
    if r.orig ? 'address_id' then v_requeue := v_requeue || r.entity_id::uuid; end if;
    v_restored := v_restored + 1;
  end loop;

  -- responsáveis: dados pessoais, contatos e endereço pelo valor original
  for r in select o.entity_id, o.orig from iara.demo_original_values('guardians', v_users) o
           join iara.guardians g on g.id::text = o.entity_id
           where not (g.id = any (v_keep_guardians)) loop
    perform iara.demo_restaurar_colunas('guardians', 'id', r.entity_id::uuid, r.orig, array['updated_by']);
    v_restored := v_restored + 1;
  end loop;

  -- saúde/inclusão: o que sessões criaram sai; o que alteraram volta
  delete from iara.student_sensitive x
  where not (x.student_id = any (v_keep_students))
    and exists (select 1 from iara.audit_log l where l.entity_type = 'student_sensitive' and l.entity_id = x.student_id::text
                and l.action = 'INSERT' and l.user_id = any (v_users))
    and not exists (select 1 from iara.audit_log l where l.entity_type = 'student_sensitive' and l.entity_id = x.student_id::text
                    and l.action = 'INSERT' and not (l.user_id = any (v_users)));
  for r in select o.entity_id, o.orig from iara.demo_original_values('student_sensitive', v_users) o
           where not (o.entity_id::uuid = any (v_keep_students)) loop
    perform iara.demo_restaurar_colunas('student_sensitive', 'student_id', r.entity_id::uuid, r.orig);
    v_restored := v_restored + 1;
  end loop;

  -- vínculos: os criados por sessões saem; os alterados/encerrados voltam ao estado anterior (eventos VINCULO_*)
  for r in select distinct on (l.entity_id, l.after_json ->> 'guardian_id') l.action, l.entity_id, l.before_json, l.after_json
           from iara.audit_log l
           where l.action in ('VINCULO_CRIADO', 'VINCULO_ALTERADO', 'VINCULO_ENCERRADO') and l.user_id = any (v_users)
             and not (l.entity_id::uuid = any (v_keep_students))
           order by l.entity_id, l.after_json ->> 'guardian_id', l.id loop
    if r.before_json is null then
      delete from iara.student_guardians where student_id = r.entity_id::uuid and guardian_id = (r.after_json ->> 'guardian_id')::uuid;
    else
      update iara.student_guardians x set relationship = r.before_json ->> 'relationship', is_primary = (r.before_json ->> 'is_primary')::boolean,
        can_pick_up = (r.before_json ->> 'can_pick_up')::boolean, can_receive_notifications = (r.before_json ->> 'can_receive_notifications')::boolean,
        legal_authority_status = r.before_json ->> 'legal_authority_status', start_date = (r.before_json ->> 'start_date')::date,
        end_date = (r.before_json ->> 'end_date')::date
      where x.student_id = r.entity_id::uuid and x.guardian_id = (r.before_json ->> 'guardian_id')::uuid;
    end if;
    n_vinc := n_vinc + 1;
  end loop;
  delete from iara.student_guardians x
  where not (x.student_id = any (v_keep_students))
    and exists (select 1 from iara.audit_log l where l.entity_type = 'student_guardians' and l.action = 'INSERT' and l.user_id = any (v_users)
                and l.entity_id = x.student_id::text and l.after_json ->> 'guardian_id' = x.guardian_id::text);

  for r in select o.entity_id, o.orig from iara.demo_original_values('conversations', v_users) o
           join iara.conversations c on c.id::text = o.entity_id loop
    update iara.conversations c set
      state = case when r.orig ? 'state' then r.orig ->> 'state' else c.state end,
      assigned_user_id = case when r.orig ? 'assigned_user_id' then (r.orig ->> 'assigned_user_id')::uuid else c.assigned_user_id end,
      assigned_label = case when r.orig ? 'assigned_label' then r.orig ->> 'assigned_label' else c.assigned_label end
    where c.id = r.entity_id::uuid;
    v_restored := v_restored + 1;
  end loop;

  -- endereços criados por sessões que ficaram sem ninguém (depois de restaurar quem apontava para eles)
  delete from iara.addresses a
  where a.id is distinct from v_addr_maria
    and (a.id = any (v_addrs)
         or exists (select 1 from iara.audit_log l where l.entity_type = 'addresses' and l.entity_id = a.id::text
                    and l.action = 'INSERT' and l.user_id = any (v_users)))
    and not exists (select 1 from iara.guardians g where g.address_id = a.id)
    and not exists (select 1 from iara.students s where s.address_id = a.id);
  get diagnostics n_addr = row_count;
  perform set_config('iara.skip_audit', 'off', true);

  if cardinality(v_requeue) > 0 then
    perform iara.requeue_students(v_requeue);
  end if;
  for q in select distinct (x ->> 'u')::integer as u, (x ->> 'g')::smallint as g from jsonb_array_elements(v_queues) x loop
    perform iara.recalculate_queue(q.u, q.g);
  end loop;
  for q in select unnest(v_classes) as c loop
    perform iara.recount_class(q.c);
  end loop;

  -- 3. contatos do WhatsApp das famílias removidas: o mesmo telefone volta a começar do zero
  delete from iara.whatsapp_outbox where contact_id in (select id from iara.whatsapp_contacts where app_user_id = any (v_users));
  delete from iara.whatsapp_inbound where contact_id in (select id from iara.whatsapp_contacts where app_user_id = any (v_users));
  delete from iara.whatsapp_contacts where app_user_id = any (v_users);
  get diagnostics n_wa = row_count;
  delete from iara.app_users where id = any (v_users) and auth_provider = 'WHATSAPP';

  -- 4. família da Maria: reinício completo (não se aplica à limpeza só do WhatsApp nem à de sessões específicas)
  if p_origem is distinct from 'WHATSAPP' and p_usuarios is null then
    v_reset := iara.demo_reset_citizen();
  end if;

  v_out := jsonb_build_object('familias_removidas', cardinality(v_guardians), 'responsaveis', coalesce(v_names, '-'),
    'criancas_removidas', cardinality(v_students), 'protocolos_removidos', cardinality(v_cases),
    'inscricoes_removidas', cardinality(v_entries), 'ofertas_removidas', cardinality(v_offers),
    'matriculas_removidas', cardinality(v_enrolls), 'bloqueios_removidos', cardinality(v_blocks),
    'conversas_removidas', n_conv, 'eventos_removidos', n_events, 'documentos_removidos', n_docs,
    'notificacoes_removidas', n_notif, 'movimentos_de_vaga_removidos', n_vev, 'enderecos_removidos', n_addr,
    'pessoas_do_domicilio_removidas', n_dom, 'vinculos_restaurados', n_vinc, 'filas_recalculadas_por_endereco', cardinality(v_requeue),
    'contatos_whatsapp_removidos', n_wa, 'linhas_restauradas', v_restored, 'reinicio_cidadao', v_reset,
    'origem', case when p_usuarios is not null then format('%s sessão(ões) indicada(s)', cardinality(p_usuarios)) else coalesce(p_origem, 'todas') end);
  perform iara.audit_event('DEMO_PURGE', 'demo', 'sessoes', null,
    format('Limpeza da demonstração: %s família(s) e %s criança(s) criadas por sessões, %s protocolo(s), %s oferta(s), %s matrícula(s) e %s conversa(s) removidos; %s registro(s) do cenário restaurados.',
           cardinality(v_guardians), cardinality(v_students), cardinality(v_cases), cardinality(v_offers), cardinality(v_enrolls), n_conv, v_restored),
    v_out);
  return v_out;
end $$;

revoke all on function iara.demo_purge_session_data(text, uuid[]), iara.demo_restaurar_colunas(text, text, uuid, jsonb, text[]) from public;

-- 7. Base fictícia: todos os alunos, responsáveis e endereços com os dados novos -------------------------------
do $$
declare
  fem text[] := array['Ana','Maria','Juliana','Fernanda','Patrícia','Aline','Camila','Daniela','Renata','Vanessa','Tatiane','Simone','Cristiane',
                      'Luciana','Jéssica','Priscila','Bruna','Gabriela','Larissa','Sandra','Elaine','Rosângela','Adriana','Kelly','Michele','Thaís'];
  masc text[] := array['José','João','Carlos','Paulo','Marcos','Luiz','Rafael','Rodrigo','Fernando','Ricardo','Anderson','Fábio','Diego',
                       'Thiago','Leandro','Márcio','Alexandre','Bruno','Gustavo','Eduardo','Sérgio','Roberto','Wellington','Everton'];
  cidades_pr text[] := array['Sarandi','Sarandi','Sarandi','Paiçandu','Paiçandu','Marialva','Marialva','Mandaguari','Londrina','Londrina',
                             'Cianorte','Campo Mourão','Umuarama','Apucarana','Curitiba','Curitiba','Astorga','Mandaguaçu','Nova Esperança',
                             'Paranavaí','Cascavel'];
  outras text[] := array['São Paulo/SP','Presidente Prudente/SP','Campo Grande/MS','Dourados/MS','Cuiabá/MT','Florianópolis/SC','Porto Alegre/RS',
                         'Belo Horizonte/MG','Goiânia/GO','Salvador/BA','Recife/PE','São Luís/MA','Belém/PA','Brasília/DF','Porto Velho/RO',
                         'Fortaleza/CE','Teresina/PI','Manaus/AM'];
  paises text[] := array['Haiti','Haiti','Haiti','Haiti','Venezuela','Venezuela','Venezuela','Paraguai','Argentina','Colômbia','Japão','Bolívia'];
  referencias text[] := array['Próximo à praça','Em frente ao mercado','Ao lado da UBS','Perto do ponto de ônibus','Casa dos fundos',
                              'Esquina com a avenida','Portão verde','Próximo à igreja','Ao lado da escola','Condomínio — bloco B'];
  v_alunos integer;
  v_resp integer;
  v_end integer;
  v_dom integer;
begin
  if not coalesce((iara.setting('demo_mode'))::boolean, false) then
    raise notice 'Fora do modo demonstração: base não alterada.';
    return;
  end if;
  perform set_config('iara.skip_audit', 'on', true);
  perform setseed(0.261005);

  -- endereços: território pelo ponto, zona e ponto de referência
  update iara.addresses a set territory_id = t.id
  from iara.territories t
  where a.territory_id is null and a.location is not null and t.kind in ('MACRORREGIAO', 'DISTRITO') and t.geom is not null
    and st_covers(t.geom, a.location)
    and not exists (select 1 from iara.territories t2 where t2.kind = 'DISTRITO' and t.kind = 'MACRORREGIAO' and t2.geom is not null
                    and st_covers(t2.geom, a.location));
  update iara.addresses set reference_point = referencias[1 + floor(random() * array_length(referencias, 1))::int]
  where reference_point is null and is_demo and random() < 0.28;
  get diagnostics v_end = row_count;

  -- alunos: filiação a partir dos vínculos (mãe/pai); sem vínculo de mãe/pai, nome fictício com o sobrenome da criança
  update iara.students s set
    parent1_name = coalesce(f.mae, fem[1 + floor(random() * array_length(fem, 1))::int] || ' ' || split_part(s.full_name, ' ', array_length(string_to_array(s.full_name, ' '), 1))),
    parent2_name = coalesce(f.pai, case when random() < 0.55 then masc[1 + floor(random() * array_length(masc, 1))::int] || ' '
                                         || split_part(s.full_name, ' ', array_length(string_to_array(s.full_name, ' '), 1)) end)
  from (select x.id, max(g.full_name) filter (where sg.relationship = 'MAE') as mae, max(g.full_name) filter (where sg.relationship = 'PAI') as pai
        from iara.students x left join iara.student_guardians sg on sg.student_id = x.id left join iara.guardians g on g.id = sg.guardian_id
        where x.is_demo group by x.id) f
  where f.id = s.id and s.parent1_name is null;

  -- cor/raça (declarada pela família; proporções próximas às de Maringá), nacionalidade e naturalidade
  update iara.students s set
    race_color = case when z.r < 0.585 then 'BRANCA' when z.r < 0.885 then 'PARDA' when z.r < 0.93 then 'PRETA' when z.r < 0.952 then 'AMARELA'
                      when z.r < 0.955 then 'INDIGENA' when z.r < 0.985 then 'NAO_DECLARADA' end,
    nationality = case when z.n < 0.986 then 'BRASILEIRA' when z.n < 0.989 then 'NATURALIZADA' else 'ESTRANGEIRA' end,
    birth_country = case when z.n >= 0.986 then paises[1 + floor(random() * array_length(paises, 1))::int] end,
    birth_city = case when z.n < 0.986 and z.c < 0.985 then
                   case when z.m < 0.80 then 'Maringá' when z.m < 0.92 then cidades_pr[1 + floor(random() * array_length(cidades_pr, 1))::int]
                        else split_part(outras[1 + floor(z.o * array_length(outras, 1))::int], '/', 1) end end,
    birth_state = case when z.n < 0.986 and z.c < 0.985 then
                    case when z.m < 0.92 then 'PR' else split_part(outras[1 + floor(z.o * array_length(outras, 1))::int], '/', 2) end end
  from (select id, random() as r, random() as n, random() as c, random() as m, random() as o from iara.students where is_demo) z
  where z.id = s.id and s.race_color is null;

  -- documentos fictícios (nunca coincidem com documentos reais: CPF com dígito verificador inválido, cartório 9000xx)
  update iara.students s set
    birth_certificate = case when random() < 0.93 then '9000' || lpad(floor(random() * 100)::int::text, 2, '0') || '01' || '55'
                               || extract(year from s.birth_date)::int::text || '1' || lpad(floor(random() * 100000)::int::text, 5, '0')
                               || lpad(floor(random() * 1000)::int::text, 3, '0') || lpad(floor(random() * 10000000)::int::text, 7, '0')
                               || lpad(floor(random() * 100)::int::text, 2, '0') end,
    cpf = case when random() < 0.68 then iara.fake_cpf() end,
    sus_card = case when random() < 0.88 then '7' || lpad(floor(random() * 100000000000000)::bigint::text, 14, '0') end,
    inep_id = case when s.status = 'MATRICULADO' and s.birth_date < date '2025-04-01' and random() < 0.95
                   then '1' || lpad(floor(random() * 100000000000)::bigint::text, 11, '0') end,
    image_consent = case when random() < 0.86 then true when random() < 0.7 then false end
  where s.is_demo and s.birth_certificate is null and s.cpf is null and s.sus_card is null;
  -- NIS das crianças de famílias no CadÚnico
  update iara.students s set nis = '2' || lpad(floor(random() * 10000000000)::bigint::text, 10, '0')
  where s.is_demo and s.nis is null and random() < 0.85
    and exists (select 1 from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
                where sg.student_id = s.id and g.cadunico_status);
  get diagnostics v_alunos = row_count;

  -- responsáveis: RG, estado civil, 2º telefone, renda individual, escolaridade e pessoas no domicílio
  update iara.guardians g set
    rg = case when random() < 0.87 then substr(z.d, 1, 2) || '.' || substr(z.d, 3, 3) || '.' || substr(z.d, 6, 3) || '-' || floor(random() * 10)::int end,
    marital_status = case when g.single_mother then case when z.e < 0.70 then 'SOLTEIRO' when z.e < 0.95 then 'DIVORCIADO' else 'SEPARADO' end
                          when g.birth_date < date '1965-01-01' and z.e < 0.25 then 'VIUVO'
                          when z.e < 0.36 then 'CASADO' when z.e < 0.58 then 'UNIAO_ESTAVEL' when z.e < 0.88 then 'SOLTEIRO' when z.e < 0.97 then 'DIVORCIADO'
                          else 'SEPARADO' end,
    secondary_phone = case when random() < 0.22 then '(44) 90000-' || lpad(floor(random() * 10000)::int::text, 4, '0') end,
    monthly_income = case when g.family_income is null then null when g.employment_status = 'Desempregado' then 0
                          else round((g.family_income * (0.40 + random() * 0.55))::numeric, 2) end,
    education_level = coalesce(g.education_level, case when random() < 0.85 then
                        (array['Fundamental incompleto','Fundamental completo','Médio incompleto','Médio completo','Médio completo','Superior incompleto','Superior completo'])[1 + floor(random() * 7)::int] end)
  from (select id, lpad(floor(random() * 100000000)::bigint::text, 8, '0') as d, random() as e from iara.guardians where is_demo) z
  where z.id = g.id and g.rg is null and g.marital_status is null;
  get diagnostics v_resp = row_count;
  update iara.guardians g set household_size = 1 + x.n + (case when g.marital_status in ('CASADO', 'UNIAO_ESTAVEL') then 1 else 0 end)
  from (select sg.guardian_id, count(*)::int as n from iara.student_guardians sg where sg.end_date is null group by 1) x
  where x.guardian_id = g.id and g.household_size is null and g.is_demo;

  -- famílias de crianças nascidas fora do Brasil: responsável estrangeiro e idioma
  update iara.guardians g set nationality = 'ESTRANGEIRA',
    preferred_language = case when s.birth_country = 'Haiti' then 'Crioulo haitiano / francês' when s.birth_country = 'Japão' then 'Japonês'
                              else 'Espanhol' end
  from iara.student_guardians sg join iara.students s on s.id = sg.student_id
  where sg.guardian_id = g.id and s.nationality = 'ESTRANGEIRA' and g.is_demo and g.nationality = 'BRASILEIRA';

  -- composição familiar: outras pessoas que moram junto (parte das famílias)
  insert into iara.household_members (guardian_id, full_name, relationship, birth_date, occupation, monthly_income, is_demo)
  select g.id,
         case when z.k < 0.35 then fem[1 + floor(random() * array_length(fem, 1))::int] else masc[1 + floor(random() * array_length(masc, 1))::int] end
           || ' ' || split_part(g.full_name, ' ', array_length(string_to_array(g.full_name, ' '), 1)),
         case when z.k < 0.35 then 'AVO' when z.k < 0.70 then 'IRMAO' when z.k < 0.88 then 'TIO' else 'OUTRO' end,
         case when z.k < 0.35 then date '1952-01-01' + floor(random() * 6000)::int
              when z.k < 0.70 then date '2007-01-01' + floor(random() * 2500)::int
              else date '1975-01-01' + floor(random() * 9000)::int end,
         case when z.k < 0.35 then 'Aposentada(o)' when z.k < 0.70 then 'Estudante' else 'Autônomo(a)' end,
         case when z.k < 0.35 then 1518 when z.k < 0.70 then 0 else round((1200 + random() * 2400)::numeric, 2) end,
         true
  from (select g0.*, random() as k from iara.guardians g0 where g0.is_demo and random() < 0.10) g
  cross join lateral (select g.k) z
  where true
    and exists (select 1 from iara.student_guardians sg where sg.guardian_id = g.id and sg.is_primary and sg.end_date is null)
    and not exists (select 1 from iara.household_members h where h.guardian_id = g.id);
  get diagnostics v_dom = row_count;

  perform set_config('iara.skip_audit', 'off', true);
  perform iara.audit_event('DEMO_CADASTRO', 'demo', 'cadastro', null,
    format('Cadastro 360º completado na base fictícia: %s alunos, %s responsáveis, %s endereços com ponto de referência, %s pessoas em composições familiares.',
           (select count(*) from iara.students where is_demo), v_resp, v_end, v_dom));
end $$;

commit;
