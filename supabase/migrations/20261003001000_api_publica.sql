-- IARA Educa — 010 · API pública (anon + autenticados): rede, mapa, unidades, territórios, KPIs, busca de vagas
-- Convenção: api.<nome>(p jsonb) returns jsonb. Somente agregados — nenhum dado pessoal sai destas funções.
begin;

-- Resumo operacional (DEMO) por unidade
create or replace function iara.unit_ops(p_unit integer) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object(
    'classes', count(*),
    'capacity', coalesce(sum(authorized_capacity), 0),
    'enrolled', coalesce(sum(active_enrollments_count), 0),
    'physical', coalesce(sum(physical_vacancies_count), 0),
    'blocked', coalesce(sum(blocked_seats_count), 0),
    'reserved', coalesce(sum(reserved_seats_count), 0),
    'offerable', coalesce(sum(offerable_vacancies_count), 0),
    'occupancy', case when sum(authorized_capacity) > 0 then round(100.0 * sum(active_enrollments_count) / sum(authorized_capacity), 1) end,
    'queue', (select count(*) from iara.waiting_list_entries w where w.preferred_unit_id = p_unit and w.status in ('WAITING', 'OFFERED')),
    'source', 'DEMO'
  )
  from iara.classes where unit_id = p_unit and status = 'ATIVA'
$$;

-- KPIs da rede (oficiais + operacionais DEMO ao vivo), filtráveis por território e etapa
create or replace function iara.kpis(p_territory integer default null, p_stage text default null) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  with u as (
    select * from iara.education_units
    where (p_territory is null or macro_territory_id = p_territory)
      and (p_stage is null or (p_stage = 'EI' and unit_type = 'CMEI') or (p_stage <> 'EI' and unit_type = 'ESCOLA'))
  ),
  g as (select id from iara.grade_levels gl where p_stage is null or gl.stage_id = (select id from iara.education_stages where code = p_stage)),
  c as (select c.* from iara.classes c join u on u.id = c.unit_id where c.grade_level_id in (select id from g) and c.status = 'ATIVA'),
  w as (select w.* from iara.waiting_list_entries w join u on u.id = w.preferred_unit_id where w.grade_level_id in (select id from g)),
  sc as (select sc.* from iara.service_cases sc where (p_territory is null or sc.unit_id in (select id from u)))
  select jsonb_build_object(
    'official', jsonb_build_object(
      'units', (select count(*) from u),
      'cmeis', (select count(*) from u where unit_type = 'CMEI'),
      'schools', (select count(*) from u where unit_type = 'ESCOLA'),
      'classes', (select coalesce(sum(public_classes), 0) from u),
      'enrollments', (select coalesce(sum(public_enrollments), 0) from u),
      'teachers_census', (select coalesce(sum(census_teachers), 0) from u),
      'special_ed_census', (select coalesce(sum(census_special_ed_enrollments), 0) from u),
      'reference', 'Agregado público mais recente por unidade (SEED-PR 2026 / Censo Escolar 2025)',
      'reference_date', iara.setting('official_reference_date')),
    'operational', jsonb_build_object(
      'classes', (select count(*) from c),
      'capacity', (select coalesce(sum(authorized_capacity), 0) from c),
      'enrolled', (select coalesce(sum(active_enrollments_count), 0) from c),
      'physical', (select coalesce(sum(physical_vacancies_count), 0) from c),
      'blocked', (select coalesce(sum(blocked_seats_count), 0) from c),
      'reserved', (select coalesce(sum(reserved_seats_count), 0) from c),
      'offerable', (select coalesce(sum(offerable_vacancies_count), 0) from c),
      'occupancy', (select case when sum(authorized_capacity) > 0 then round(100.0 * sum(active_enrollments_count) / sum(authorized_capacity), 1) end from c),
      'full_classes', (select count(*) from c where offerable_vacancies_count = 0),
      'waiting', (select count(*) from w where status in ('WAITING', 'OFFERED')),
      'waiting_no_service', (select count(*) from w where status in ('WAITING', 'OFFERED') and demand_category = 'SEM_ATENDIMENTO'),
      'offers_pending', (select count(*) from iara.vacancy_offers o where o.status = 'OFFERED' and o.unit_id in (select id from u)),
      'offers_accepted', (select count(*) from iara.vacancy_offers o where o.status = 'ACCEPTED' and o.unit_id in (select id from u)),
      'open_cases', (select count(*) from sc where status not in ('ENCERRADO', 'MATRICULA_CONCLUIDA', 'NAO_ATENDIDO')),
      'overdue_cases', (select count(*) from sc where status not in ('ENCERRADO', 'MATRICULA_CONCLUIDA', 'NAO_ATENDIDO') and sla_due_at < now()),
      'source', 'DEMONSTRAÇÃO — camada operacional fictícia calibrada; integração SEDUC pendente',
      'updated_at', now()),
    'demo_metrics', (select jsonb_object_agg(key, jsonb_build_object('label', label, 'value', value, 'source', source)) from iara.demo_metrics)
  )
$$;

create or replace function api.bootstrap(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object(
    'tenant', (select jsonb_build_object('id', id, 'name', name, 'state', state, 'ibge', ibge_code,
                                         'network_name', settings ->> 'network_name', 'secretariat', settings ->> 'secretariat',
                                         'school_year', (settings ->> 'school_year')::int, 'official_reference_date', settings ->> 'official_reference_date',
                                         'city_center', settings -> 'city_center', 'demo_mode', (settings ->> 'demo_mode')::boolean,
                                         'demo_unit', (settings ->> 'demo_unit_maria')::int)
               from iara.tenants where id = 1),
    'flags', (select jsonb_object_agg(code, enabled) from iara.feature_flags),
    'personas', (select jsonb_agg(jsonb_build_object('code', code, 'name', name, 'short_name', short_name, 'description', description,
                                                     'question', question, 'scope_type', scope_type, 'org_unit', org_unit, 'stage_filter', stage_filter)
                                  order by sort) from iara.organizational_roles where is_persona),
    'stages', (select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', name, 'short_name', short_name, 'color', color) order by sort) from iara.education_stages),
    'grades', (select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', name, 'short_name', short_name, 'stage_id', stage_id,
                                                   'min_age_months', min_age_months, 'max_age_months', max_age_months) order by sort) from iara.grade_levels),
    'territories', (select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', name, 'kind', kind, 'color', color,
                                                        'lat', extensions.st_y(center::extensions.geometry), 'lng', extensions.st_x(center::extensions.geometry)) order by sort)
                    from iara.territories where kind in ('MACRORREGIAO', 'DISTRITO')),
    'kpis', iara.kpis(),
    'rule_version', iara.rule_version(),
    'import', (select jsonb_build_object('id', id, 'file', source_file, 'imported_at', imported_at, 'counts', row_counts) from iara.import_batches limit 1)
  )
$$;

-- Mapa: todas as unidades com agregados (oficial + DEMO)
create or replace function api.units_map(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  with ops as (
    select unit_id, count(*) as classes, sum(authorized_capacity) as capacity, sum(active_enrollments_count) as enrolled,
           sum(offerable_vacancies_count) as offerable, sum(blocked_seats_count) as blocked, sum(reserved_seats_count) as reserved,
           sum(offerable_vacancies_count) filter (where grade_level_id = 1) as offerable_creche,
           sum(offerable_vacancies_count) filter (where grade_level_id = 2) as offerable_pre,
           sum(offerable_vacancies_count) filter (where grade_level_id between 3 and 7) as offerable_ef,
           array_agg(distinct grade_level_id) as grades, array_agg(distinct shift) as shifts
    from iara.classes where status = 'ATIVA' group by unit_id
  ),
  q as (
    select preferred_unit_id as unit_id, count(*) as queue, count(*) filter (where grade_level_id = 1) as queue_creche
    from iara.waiting_list_entries where status in ('WAITING', 'OFFERED') group by preferred_unit_id
  )
  select jsonb_build_object(
    'generated_at', now(),
    'units', coalesce(jsonb_agg(jsonb_build_object(
      'id', u.id, 'name', u.name, 'short_name', u.short_name, 'type', u.unit_type, 'type_label', u.unit_type_label,
      'status', u.status, 'lat', u.lat, 'lng', u.lng, 'macro_id', u.macro_territory_id, 'neighborhood', u.neighborhood,
      'address', u.address_line, 'stages', u.stages_text, 'geo_precision', u.geo_precision, 'has_aee', u.has_aee,
      'inep', u.inep_code, 'public_classes', u.public_classes, 'public_enrollments', u.public_enrollments,
      'classes', coalesce(o.classes, 0), 'capacity', coalesce(o.capacity, 0), 'enrolled', coalesce(o.enrolled, 0),
      'offerable', coalesce(o.offerable, 0), 'offerable_creche', coalesce(o.offerable_creche, 0), 'offerable_pre', coalesce(o.offerable_pre, 0),
      'offerable_ef', coalesce(o.offerable_ef, 0), 'blocked', coalesce(o.blocked, 0), 'reserved', coalesce(o.reserved, 0),
      'occupancy', case when o.capacity > 0 then round(100.0 * o.enrolled / o.capacity, 1) end,
      'queue', coalesce(q.queue, 0), 'queue_creche', coalesce(q.queue_creche, 0),
      'grades', coalesce(to_jsonb(o.grades), '[]'::jsonb), 'shifts', coalesce(to_jsonb(o.shifts), '[]'::jsonb)
    ) order by u.name), '[]'::jsonb)
  )
  from iara.education_units u left join ops o on o.unit_id = u.id left join q on q.unit_id = u.id
$$;

-- Camadas geográficas (GeoJSON simplificado): município, macrorregiões com indicadores e áreas de influência
create or replace function api.geo_layers(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = iara, extensions, public
as $$
  with stats as (
    select t.id,
           (select coalesce(sum(c.offerable_vacancies_count), 0) from iara.classes c join iara.education_units u on u.id = c.unit_id where u.macro_territory_id = t.id) as offerable,
           (select coalesce(sum(c.offerable_vacancies_count), 0) from iara.classes c join iara.education_units u on u.id = c.unit_id where u.macro_territory_id = t.id and c.grade_level_id = 1) as offerable_creche,
           (select count(*) from iara.waiting_list_entries w join iara.education_units u on u.id = w.preferred_unit_id where u.macro_territory_id = t.id and w.status in ('WAITING', 'OFFERED')) as queue,
           (select count(*) from iara.waiting_list_entries w join iara.education_units u on u.id = w.preferred_unit_id where u.macro_territory_id = t.id and w.status in ('WAITING', 'OFFERED') and w.grade_level_id = 1) as queue_creche,
           (select count(*) from iara.education_units u where u.macro_territory_id = t.id) as units,
           (select coalesce(sum(public_enrollments), 0) from iara.education_units u where u.macro_territory_id = t.id) as enrollments
    from iara.territories t where t.kind in ('MACRORREGIAO', 'DISTRITO')
  )
  select jsonb_build_object(
    'municipality', (select jsonb_build_object('type', 'Feature', 'properties', jsonb_build_object('name', name, 'source', source),
                                               'geometry', st_asgeojson(st_simplifypreservetopology(geom::geometry, 0.0003), 6)::jsonb)
                     from iara.territories where id = 100),
    'regions', jsonb_build_object('type', 'FeatureCollection', 'features', (
      select coalesce(jsonb_agg(jsonb_build_object('type', 'Feature', 'id', t.id,
        'properties', jsonb_build_object('id', t.id, 'name', t.name, 'color', t.color, 'kind', t.kind, 'source', t.source,
                                         'units', s.units, 'enrollments', s.enrollments, 'offerable', s.offerable, 'queue', s.queue,
                                         'offerable_creche', s.offerable_creche, 'queue_creche', s.queue_creche,
                                         'balance', s.offerable - s.queue, 'balance_creche', s.offerable_creche - s.queue_creche),
        'geometry', st_asgeojson(st_simplifypreservetopology(t.geom::geometry, 0.0004), 6)::jsonb)), '[]'::jsonb)
      from iara.territories t join stats s on s.id = t.id where t.geom is not null)),
    'areas', jsonb_build_object('type', 'FeatureCollection', 'features', (
      select coalesce(jsonb_agg(jsonb_build_object('type', 'Feature', 'id', u.id,
        'properties', jsonb_build_object('id', u.id, 'name', u.short_name, 'type', u.unit_type, 'macro_id', u.macro_territory_id),
        'geometry', st_asgeojson(st_simplifypreservetopology(u.influence_area::geometry, 0.0003), 6)::jsonb)), '[]'::jsonb)
      from iara.education_units u where u.influence_area is not null)),
    'notes', jsonb_build_array(
      'Limite municipal: malha IBGE.',
      'Macrorregiões e áreas de influência (Voronoi por proximidade) são cálculos de demonstração; o território escolar oficial deve ser definido pela SEDUC.')
  )
$$;

-- Lista de unidades com filtros
create or replace function api.units_list(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  with params as (
    select nullif(p ->> 'q', '') as q, nullif(p ->> 'type', '') as type, (p ->> 'territory_id')::int as territory,
           nullif(p ->> 'stage', '') as stage, coalesce((p ->> 'has_vacancy')::boolean, false) as has_vacancy,
           (p ->> 'grade_level_id')::smallint as grade, coalesce(p ->> 'sort', 'name') as sort,
           (p ->> 'lat')::float8 as lat, (p ->> 'lng')::float8 as lng
  ),
  base as (
    select u.*, iara.unit_ops(u.id) as ops,
           case when (select lat from params) is not null
                then round(extensions.st_distance(u.location, iara.point((select lat from params), (select lng from params))))::int end as dist_m,
           (select coalesce(sum(c.offerable_vacancies_count), 0) from iara.classes c where c.unit_id = u.id
             and ((select grade from params) is null or c.grade_level_id = (select grade from params))) as offerable_sel
    from iara.education_units u, params
    where (params.q is null or iara.norm(u.name || ' ' || coalesce(u.neighborhood, '') || ' ' || coalesce(u.address_line, '')) like '%' || iara.norm(params.q) || '%')
      and (params.type is null or u.unit_type = params.type)
      and (params.territory is null or u.macro_territory_id = params.territory)
      and (params.stage is null or (params.stage = 'EI' and exists (select 1 from iara.classes c where c.unit_id = u.id and c.stage_id = 1))
           or (params.stage = 'EF' and exists (select 1 from iara.classes c where c.unit_id = u.id and c.stage_id = 2))
           or (params.stage = 'EJA' and exists (select 1 from iara.classes c where c.unit_id = u.id and c.stage_id = 3)))
      and (params.grade is null or exists (select 1 from iara.classes c where c.unit_id = u.id and c.grade_level_id = params.grade))
  )
  select jsonb_build_object('total', (select count(*) from base where not (select has_vacancy from params) or offerable_sel > 0),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', b.id, 'name', b.name, 'short_name', b.short_name, 'type', b.unit_type, 'type_label', b.unit_type_label, 'status', b.status,
        'neighborhood', b.neighborhood, 'address', b.address_line, 'macro_id', b.macro_territory_id,
        'territory', (select name from iara.territories t where t.id = b.macro_territory_id),
        'lat', b.lat, 'lng', b.lng, 'stages', b.stages_text, 'public_enrollments', b.public_enrollments, 'public_classes', b.public_classes,
        'director', b.director_name, 'geo_precision', b.geo_precision, 'distance_m', b.dist_m, 'offerable_selected', b.offerable_sel,
        'ops', b.ops) order by
          case when (select sort from params) = 'distance' then b.dist_m end nulls last,
          case when (select sort from params) = 'vacancy' then -(b.ops ->> 'offerable')::int end,
          case when (select sort from params) = 'queue' then -(b.ops ->> 'queue')::int end,
          case when (select sort from params) = 'occupancy' then -coalesce((b.ops ->> 'occupancy')::numeric, 0) end,
          b.short_name)
      from base b where not (select has_vacancy from params) or b.offerable_sel > 0), '[]'::jsonb))
$$;

-- Detalhe público da unidade (sem dados pessoais)
create or replace function api.unit_detail(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, extensions, public
as $$
declare
  v_id integer := (p ->> 'id')::int;
  u iara.education_units;
  v jsonb;
begin
  select * into u from iara.education_units where id = v_id;
  if not found then
    raise exception 'Unidade não encontrada.' using errcode = 'P0002';
  end if;
  select jsonb_build_object(
    'unit', jsonb_build_object(
      'id', u.id, 'name', u.name, 'short_name', u.short_name, 'type', u.unit_type, 'type_label', u.unit_type_label,
      'status', u.status, 'status_label', u.status_label, 'address', u.address_line, 'neighborhood', u.neighborhood,
      'postal_code', u.postal_code, 'city', u.city, 'lat', u.lat, 'lng', u.lng, 'inep', u.inep_code, 'phone', u.phone,
      'director', u.director_name, 'director_status', u.director_status, 'director_source', u.director_source,
      'stages', u.stages_text, 'offers_text', u.offers_text, 'has_aee', u.has_aee, 'service_radius_m', u.service_radius_m,
      'territory', (select jsonb_build_object('id', t.id, 'name', t.name, 'color', t.color, 'source', t.source) from iara.territories t where t.id = u.macro_territory_id),
      'public', jsonb_build_object('classes', u.public_classes, 'enrollments', u.public_enrollments, 'reference', u.data_reference,
                                   'status', u.data_status, 'source', u.main_source, 'detail', u.public_detail, 'capacity', u.public_capacity),
      'census', jsonb_build_object('classes', u.census_classes, 'enrollments', u.census_enrollments, 'teachers', u.census_teachers,
                                   'special_ed', u.census_special_ed_enrollments, 'status', u.census_status),
      'geo', jsonb_build_object('precision', u.geo_precision, 'status', u.geo_status, 'source', u.geo_source, 'note', u.geo_note),
      'address_meta', jsonb_build_object('confidence', u.address_confidence, 'source', u.address_source, 'cep_source', u.cep_source),
      'seduc_confirmation', u.seduc_confirmation_status, 'confidence_status', u.confidence_status),
    'offers', coalesce((select jsonb_agg(jsonb_build_object('name', o.offer_name, 'stage', o.stage_code, 'classes', o.classes_count,
                                                            'enrollments', o.enrollments_count, 'reference', o.reference_date,
                                                            'confidence', o.confidence_text, 'source', o.source) order by o.id)
                        from iara.unit_offers o where o.unit_id = u.id), '[]'::jsonb),
    'grades_census', coalesce((select jsonb_agg(jsonb_build_object('stage', s.stage_name, 'grade', s.grade_name, 'grade_level_id', s.grade_level_id,
                                                                   'classes', s.classes_count, 'enrollments', s.enrollments_count, 'avg', s.avg_per_class,
                                                                   'year', s.reference_year, 'source', s.source, 'status', s.status)
                                        order by coalesce(gl.sort, 99), s.grade_name)
                               from iara.unit_grade_stats s left join iara.grade_levels gl on gl.id = s.grade_level_id where s.unit_id = u.id), '[]'::jsonb),
    'shifts_census', coalesce((select jsonb_agg(jsonb_build_object('stage', s.stage_name, 'shift', s.shift, 'classes', s.classes_count,
                                                                   'enrollments', s.enrollments_count, 'limitation', s.limitation) order by s.stage_name, s.shift)
                               from iara.unit_shift_stats s where s.unit_id = u.id), '[]'::jsonb),
    'ops', iara.unit_ops(u.id),
    'ops_by_grade', coalesce((select jsonb_agg(x order by (x ->> 'sort')::int) from (
        select jsonb_build_object('grade_level_id', gl.id, 'grade', gl.name, 'stage_id', gl.stage_id, 'sort', gl.sort,
                                  'classes', count(c.*), 'capacity', sum(c.authorized_capacity), 'enrolled', sum(c.active_enrollments_count),
                                  'offerable', sum(c.offerable_vacancies_count), 'blocked', sum(c.blocked_seats_count), 'reserved', sum(c.reserved_seats_count),
                                  'shifts', array_agg(distinct c.shift),
                                  'queue', (select count(*) from iara.waiting_list_entries w where w.preferred_unit_id = u.id and w.grade_level_id = gl.id
                                              and w.status in ('WAITING', 'OFFERED'))) as x
        from iara.classes c join iara.grade_levels gl on gl.id = c.grade_level_id
        where c.unit_id = u.id and c.status = 'ATIVA' group by gl.id) z), '[]'::jsonb),
    'quality', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'type', q.issue_type, 'severity', q.severity, 'title', q.title,
                                                             'description', q.description, 'action', q.action, 'status', q.status))
                         from iara.data_quality_issues q where q.unit_id = u.id), '[]'::jsonb),
    'nearby', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'name', n.short_name, 'type', n.unit_type,
                                                            'distance_m', round(st_distance(n.location, u.location))::int) order by st_distance(n.location, u.location))
                        from (select * from iara.education_units n where n.id <> u.id order by n.location <-> u.location limit 5) n), '[]'::jsonb),
    'staff_summary', (select jsonb_build_object('total', count(*), 'by_role', jsonb_object_agg(role, n))
                      from (select role, count(*) n from iara.staff where unit_id = u.id group by role) s),
    'demo_notice', 'Turmas, capacidade, vagas, fila e profissionais nesta unidade são dados de DEMONSTRAÇÃO (estrutura de turmas do Censo 2025).'
  ) into v;
  return v;
end $$;

-- Território (macrorregião/distrito)
create or replace function api.territory_detail(p jsonb) returns jsonb
language sql stable security definer set search_path = iara, extensions, public
as $$
  select jsonb_build_object(
    'territory', jsonb_build_object('id', t.id, 'name', t.name, 'kind', t.kind, 'color', t.color, 'source', t.source,
                                    'confidence', t.confidence_status, 'area_km2', round((st_area(t.geom) / 1e6)::numeric, 1),
                                    'lat', st_y(t.center::geometry), 'lng', st_x(t.center::geometry)),
    'kpis', iara.kpis(t.id),
    'by_grade', coalesce((select jsonb_agg(x order by (x ->> 'sort')::int) from (
        select jsonb_build_object('grade_level_id', gl.id, 'grade', gl.name, 'sort', gl.sort,
          'offerable', (select coalesce(sum(c.offerable_vacancies_count), 0) from iara.classes c join iara.education_units u on u.id = c.unit_id
                        where u.macro_territory_id = t.id and c.grade_level_id = gl.id),
          'capacity', (select coalesce(sum(c.authorized_capacity), 0) from iara.classes c join iara.education_units u on u.id = c.unit_id
                        where u.macro_territory_id = t.id and c.grade_level_id = gl.id),
          'enrolled', (select coalesce(sum(c.active_enrollments_count), 0) from iara.classes c join iara.education_units u on u.id = c.unit_id
                        where u.macro_territory_id = t.id and c.grade_level_id = gl.id),
          'queue', (select count(*) from iara.waiting_list_entries w join iara.education_units u on u.id = w.preferred_unit_id
                    where u.macro_territory_id = t.id and w.grade_level_id = gl.id and w.status in ('WAITING', 'OFFERED'))) as x
        from iara.grade_levels gl) z), '[]'::jsonb),
    'units', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'short_name', u.short_name, 'type', u.unit_type,
                                                           'neighborhood', u.neighborhood, 'lat', u.lat, 'lng', u.lng, 'ops', iara.unit_ops(u.id),
                                                           'public_enrollments', u.public_enrollments) order by u.short_name)
                       from iara.education_units u where u.macro_territory_id = t.id), '[]'::jsonb),
    'neighborhoods', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name,
                                   'units', (select count(*) from iara.education_units u where u.neighborhood_territory_id = b.id)) order by b.name)
                               from iara.territories b where b.parent_id = t.id and b.kind = 'BAIRRO'), '[]'::jsonb)
  )
  from iara.territories t where t.id = (p ->> 'id')::int
$$;

create or replace function api.network_kpis(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = iara, public
as $$ select iara.kpis((p ->> 'territory_id')::int, nullif(p ->> 'stage', '')) $$;

create or replace function api.grade_for_birthdate(p jsonb) returns jsonb
language sql stable security definer set search_path = iara, public
as $$ select iara.grade_for_birthdate((p ->> 'birth_date')::date) $$;

create or replace function api.search_vacancies(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_grade smallint := (p ->> 'grade_level_id')::smallint;
  v_student uuid := nullif(p ->> 'student_id', '')::uuid;
  v_g jsonb;
  v_res jsonb;
begin
  if v_grade is null and p ? 'birth_date' then
    v_g := iara.grade_for_birthdate((p ->> 'birth_date')::date);
    if not coalesce((v_g ->> 'ok')::boolean, false) then
      return jsonb_build_object('ok', false, 'grade_rule', v_g, 'results', '[]'::jsonb);
    end if;
    v_grade := (v_g ->> 'grade_level_id')::smallint;
  end if;
  if v_grade is null or p ->> 'lat' is null or p ->> 'lng' is null then
    raise exception 'Informe a faixa (ou data de nascimento) e a localização da residência.' using errcode = '22023';
  end if;
  if v_student is not null and not iara.can_access_student(v_student) then
    v_student := null; -- sem vínculo/permissão: a busca segue sem dados da criança
  end if;
  v_res := iara.search_vacancies_core(v_grade, (p ->> 'lat')::float8, (p ->> 'lng')::float8, nullif(p ->> 'shift', ''),
                                      coalesce((p ->> 'shift_required')::boolean, false), v_student,
                                      coalesce((p ->> 'aee')::boolean, false), coalesce((p ->> 'limit')::int, 8),
                                      coalesce((p ->> 'max_km')::numeric, 12));
  return v_res || jsonb_build_object('ok', true, 'grade_rule', v_g, 'student_considered', v_student is not null);
end $$;

-- Localização por bairro/unidade (sem geocodificador externo)
create or replace function api.geo_search(p jsonb) returns jsonb
language sql stable security definer set search_path = iara, extensions, public
as $$
  with q as (select iara.norm(coalesce(p ->> 'q', '')) as q)
  select jsonb_build_object('items', coalesce(jsonb_agg(x order by x ->> 'rank', x ->> 'label'), '[]'::jsonb))
  from (
    select jsonb_build_object('kind', 'BAIRRO', 'label', t.name, 'sub', 'Bairro/região', 'lat', st_y(t.center::geometry), 'lng', st_x(t.center::geometry), 'rank', '1') as x
    from iara.territories t, q where t.kind = 'BAIRRO' and length(q.q) >= 2 and iara.norm(t.name) like '%' || q.q || '%'
    union all
    select jsonb_build_object('kind', 'UNIDADE', 'label', u.name, 'sub', coalesce(u.address_line, '') || ' · ' || coalesce(u.neighborhood, ''),
                              'lat', u.lat, 'lng', u.lng, 'unit_id', u.id, 'rank', '2')
    from iara.education_units u, q where length(q.q) >= 2 and iara.norm(u.name || ' ' || coalesce(u.address_line, '')) like '%' || q.q || '%'
    limit 12
  ) z
$$;

create or replace function api.knowledge_search(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  with q as (select regexp_split_to_array(iara.norm(coalesce(p ->> 'q', '')), '\s+') as words)
  select jsonb_build_object('items', coalesce(jsonb_agg(jsonb_build_object(
      'id', a.id, 'title', a.title, 'body', a.body, 'service', a.service_code, 'source', a.source, 'sector', a.owner_sector,
      'version', a.version, 'approved_at', a.approved_at, 'valid_until', a.valid_until, 'status', a.status, 'score', a.score)
      order by a.score desc, a.id), '[]'::jsonb))
  from (
    select k.*, (select count(*) from unnest((select words from q)) w
                 where length(w) > 2 and (iara.norm(k.title || ' ' || k.body) like '%' || w || '%' or w = any (k.keywords))) as score
    from iara.knowledge_articles k
    where k.status = 'PUBLICADO' and k.audience = 'PUBLICO' and (k.valid_until is null or k.valid_until >= current_date)
  ) a
  where coalesce(p ->> 'q', '') = '' or a.score > 0
$$;

create or replace function api.service_catalog(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('items', coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name, 'description', description,
         'requirements', requirements, 'documents', required_documents, 'sector', sector, 'sla_days', sla_days, 'source', source) order by sort), '[]'::jsonb))
  from iara.service_catalog
$$;

create or replace function api.rules_list(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('version', iara.rule_version(), 'items', coalesce(jsonb_agg(jsonb_build_object(
      'code', rule_code, 'version', version, 'name', name, 'description', description, 'type', rule_type, 'condition', condition,
      'weight', weight, 'source', source, 'justification', justification, 'valid_from', valid_from, 'valid_to', valid_to,
      'active', is_active, 'test', test_reference) order by sort), '[]'::jsonb))
  from iara.rules where tenant_id = 1
$$;

create or replace function api.data_quality(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'total', (select count(*) from iara.data_quality_issues),
      'by_severity', (select jsonb_object_agg(severity, n) from (select severity, count(*) n from iara.data_quality_issues group by 1) x),
      'by_type', (select jsonb_object_agg(issue_type, n) from (select issue_type, count(*) n from iara.data_quality_issues group by 1) x),
      'geo', (select jsonb_object_agg(geo_precision, n) from (select geo_precision, count(*) n from iara.education_units group by 1) x),
      'without_inep', (select count(*) from iara.education_units where inep_code is null),
      'without_phone', (select count(*) from iara.education_units where phone is null),
      'units_census', (select count(*) from iara.education_units where census_enrollments is not null)),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'type', q.issue_type, 'severity', q.severity, 'title', q.title,
                                                           'description', q.description, 'source', q.source, 'action', q.action, 'status', q.status,
                                                           'unit_id', q.unit_id, 'unit_name', u.short_name)
                                        order by case q.severity when 'ALTA' then 1 when 'MEDIA' then 2 else 3 end, q.id)
                       from iara.data_quality_issues q left join iara.education_units u on u.id = q.unit_id), '[]'::jsonb))
$$;

create or replace function api.persona_units(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('items', coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'type', u.unit_type, 'neighborhood', u.neighborhood)
                                                        order by (u.id = (iara.setting('demo_unit_maria'))::int) desc, u.short_name), '[]'::jsonb))
  from iara.education_units u
  where u.status = 'ATIVA' and exists (select 1 from iara.classes c where c.unit_id = u.id)
    and (coalesce(p ->> 'q', '') = '' or iara.norm(u.name) like '%' || iara.norm(p ->> 'q') || '%')
$$;

revoke execute on all functions in schema api from public;
grant execute on function api.bootstrap(jsonb), api.units_map(jsonb), api.geo_layers(jsonb), api.units_list(jsonb), api.unit_detail(jsonb),
  api.territory_detail(jsonb), api.network_kpis(jsonb), api.grade_for_birthdate(jsonb), api.search_vacancies(jsonb), api.geo_search(jsonb),
  api.knowledge_search(jsonb), api.service_catalog(jsonb), api.rules_list(jsonb), api.data_quality(jsonb), api.persona_units(jsonb)
  to anon, authenticated;

commit;
