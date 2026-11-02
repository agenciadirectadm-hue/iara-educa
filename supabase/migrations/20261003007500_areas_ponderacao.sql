-- IARA Educa — 075 · Áreas de ponderação do IBGE como recorte territorial (no lugar das macrorregiões de demonstração)
-- O IARA passa a se organizar pelas 29 áreas de ponderação de Maringá (Censo Demográfico 2022): unidades, bairros,
-- endereços, fila, painéis, filtros, controle externo e órgãos da rede de proteção. As macrorregiões calculadas por
-- distância/rumo ao centro (Centro e Zonas Norte, Sul, Leste e Oeste) deixam de existir. Iguatemi e Floriano continuam
-- como distritos, dentro da AP 001, com o limite oficial (união dos setores censitários de cada um). Os 793 setores
-- censitários entram como camada de demanda (pessoas, domicílios e crianças de 0 a 4 anos).
-- Dados: supabase/seed/11_areas_ponderacao.sql (gerado por scripts/seed/gerar_areas_ponderacao.mjs), aplicado depois desta
-- migration — é ele que chama iara.aplicar_areas_ponderacao(). Reaplicar 20261003009900_privilegios.sql em seguida.
begin;

-- ---------------------------------------------------------------------------
-- 1. Tipos de território e setores censitários
-- ---------------------------------------------------------------------------
-- MACRORREGIAO fica aceita só para a carga da base pública antiga (seed 10); iara.aplicar_areas_ponderacao() remove todas.
alter table iara.territories drop constraint if exists territories_kind_check;
alter table iara.territories add constraint territories_kind_check
  check (kind in ('MUNICIPIO', 'AREA_PONDERACAO', 'DISTRITO', 'BAIRRO', 'MACRORREGIAO'));
create index if not exists territories_kind_idx on iara.territories(kind);

create table if not exists iara.setores_censitarios (
  code text primary key,
  tenant_id smallint not null references iara.tenants(id),
  area_ponderacao_id integer not null references iara.territories(id),
  distrito text not null,
  situacao text not null check (situacao in ('URBANA', 'RURAL')),
  bairro text,
  area_km2 numeric(10, 4),
  pessoas integer not null,
  domicilios integer not null,
  criancas_0a4 integer, -- nulo: sigilo do IBGE (setor com poucos moradores)
  center extensions.geography(Point, 4326),
  geom extensions.geography(MultiPolygon, 4326) not null,
  source text not null
);
create index if not exists setores_censitarios_area_idx on iara.setores_censitarios(area_ponderacao_id);
create index if not exists setores_censitarios_geom_idx on iara.setores_censitarios using gist (geom);
-- agregado público do IBGE, mas o visitante lê só pela função (api.geo_setores): a tabela não entra na lista do teste E4
alter table iara.setores_censitarios enable row level security;
drop policy if exists setores_censitarios_read on iara.setores_censitarios;
create policy setores_censitarios_read on iara.setores_censitarios for select to authenticated using (true);
revoke all on iara.setores_censitarios from anon, authenticated;
grant select on iara.setores_censitarios to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Auxiliares: censo e unidades de um território (área de ponderação ou distrito)
-- ---------------------------------------------------------------------------
create or replace function iara.censo_territorio(p_territory integer) returns jsonb
language sql stable security definer set search_path = iara, extensions, public
as $$
  select jsonb_build_object(
    'pessoas', coalesce(sum(s.pessoas), 0), 'domicilios', coalesce(sum(s.domicilios), 0), 'criancas_0a4', coalesce(sum(s.criancas_0a4), 0),
    'setores', count(*), 'setores_sigilo', count(*) filter (where s.criancas_0a4 is null), 'setores_rurais', count(*) filter (where s.situacao = 'RURAL'),
    'fonte', 'IBGE — Censo Demográfico 2022 (agregados por setor censitário)')
  from iara.setores_censitarios s join iara.territories t on t.id = p_territory
  where s.area_ponderacao_id = t.id or (t.kind = 'DISTRITO' and iara.norm(s.distrito) = iara.norm(t.code))
$$;

-- unidades da área (pelo vínculo da unidade) ou do distrito (pelo limite do distrito, que fica dentro da AP 001)
create or replace function iara.unidades_do_territorio(p_territory integer) returns setof integer
language sql stable security definer set search_path = iara, extensions, public
as $$
  select u.id from iara.education_units u join iara.territories t on t.id = p_territory
  where u.macro_territory_id = t.id or (t.kind = 'DISTRITO' and t.geom is not null and st_covers(t.geom, u.location))
$$;

-- ---------------------------------------------------------------------------
-- 3. Reorganização: tudo o que apontava para macrorregião ou distrito passa para a área de ponderação
-- ---------------------------------------------------------------------------
create or replace function iara.aplicar_areas_ponderacao() returns jsonb
language plpgsql security definer set search_path = iara, extensions, public
as $$
declare
  v_skip text := coalesce(current_setting('iara.skip_audit', true), '');
  v_regionais integer[] := array(select id from iara.territories where kind in ('MACRORREGIAO', 'DISTRITO'));
  v_unidades integer;
  v_bairros integer;
  v_enderecos integer;
  v_fila integer;
  v_orgaos integer;
  v_macros integer;
  v_ct uuid;
  v jsonb;
begin
  if not exists (select 1 from iara.territories where kind = 'AREA_PONDERACAO' and geom is not null) then
    raise exception 'Carregue antes as áreas de ponderação (supabase/seed/11_areas_ponderacao.sql).' using errcode = '55000';
  end if;
  -- reorganização em massa: um único evento de auditoria resume tudo (o detalhe linha a linha não acrescenta nada)
  perform set_config('iara.skip_audit', 'on', true);

  -- unidades: a área que contém o ponto (ou a mais próxima, para coordenada no limite)
  with novo as (
    select u.id, (select t.id from iara.territories t where t.kind = 'AREA_PONDERACAO' and t.geom is not null
                  order by st_covers(t.geom, u.location) desc, st_distance(t.geom, u.location), t.sort limit 1) as ap
    from iara.education_units u)
  update iara.education_units u set macro_territory_id = n.ap from novo n where n.id = u.id and u.macro_territory_id is distinct from n.ap;
  get diagnostics v_unidades = row_count;

  -- bairros: a área que contém o centro do bairro
  with novo as (
    select b.id, (select t.id from iara.territories t where t.kind = 'AREA_PONDERACAO' and t.geom is not null
                  order by st_covers(t.geom, b.center) desc, st_distance(t.geom, b.center), t.sort limit 1) as ap
    from iara.territories b where b.kind = 'BAIRRO' and b.center is not null)
  update iara.territories b set parent_id = n.ap from novo n where n.id = b.id and b.parent_id is distinct from n.ap;
  get diagnostics v_bairros = row_count;

  -- endereços: a área que contém o ponto; fora de Maringá ou sem ponto, sem área
  with novo as (
    select a.id, (select t.id from iara.territories t where t.kind = 'AREA_PONDERACAO' and t.geom is not null and st_covers(t.geom, a.location)
                  order by t.sort limit 1) as ap
    from iara.addresses a where a.location is not null)
  update iara.addresses a set territory_id = n.ap from novo n where n.id = a.id and a.territory_id is distinct from n.ap;
  get diagnostics v_enderecos = row_count;
  update iara.addresses set territory_id = null where territory_id = any (v_regionais);

  -- fila: a área da unidade pretendida (como em api.queue_entry_create)
  update iara.waiting_list_entries w set territory_id = u.macro_territory_id
  from iara.education_units u where u.id = w.preferred_unit_id and w.territory_id = any (v_regionais);
  get diagnostics v_fila = row_count;
  update iara.waiting_list_entries set territory_id = null where territory_id = any (v_regionais);

  -- órgãos da rede de proteção: cada macrorregião/distrito da competência vira as áreas que ficam dentro dela
  -- (ponto interior da área) e a área que contém o centro dela — nunca lista vazia, que significaria a cidade inteira
  update iara.orgaos_destinatarios o set territorio_ids = coalesce((
      select array_agg(distinct x order by x) from (
        select ap.id as x
        from unnest(o.territorio_ids) old_id
        join iara.territories m on m.id = old_id and m.kind in ('MACRORREGIAO', 'DISTRITO') and m.geom is not null
        join iara.territories ap on ap.kind = 'AREA_PONDERACAO' and ap.geom is not null
         and (st_covers(m.geom, st_pointonsurface(ap.geom::geometry)::geography) or (m.center is not null and st_covers(ap.geom, m.center)))
        union
        select old_id from unnest(o.territorio_ids) old_id where old_id <> all (v_regionais)) z), o.territorio_ids)
  where o.territorio_ids && v_regionais;
  get diagnostics v_orgaos = row_count;

  -- demonstração: os conselhos tutelares fictícios "por macrorregião" viram um só para as 29 áreas (como em
  -- iara.demo_gerar_busca_ativa); os encaminhamentos de demonstração passam para ele
  select id into v_ct from iara.orgaos_destinatarios
  where is_demo and tipo = 'CONSELHO_TUTELAR' and nome like 'Conselho Tutelar — %' order by nome limit 1;
  if v_ct is not null then
    update iara.encaminhamentos set orgao_id = v_ct
    where orgao_id in (select id from iara.orgaos_destinatarios
                       where is_demo and tipo = 'CONSELHO_TUTELAR' and nome like 'Conselho Tutelar — %' and id <> v_ct);
    delete from iara.orgaos_destinatarios where is_demo and tipo = 'CONSELHO_TUTELAR' and nome like 'Conselho Tutelar — %' and id <> v_ct;
    update iara.orgaos_destinatarios set nome = 'Conselho Tutelar de Maringá (demonstração)', competencia = 'Proteção de crianças e adolescentes do município',
           territorio_ids = array(select t.id from iara.territories t where t.kind = 'AREA_PONDERACAO' order by t.sort)
    where id = v_ct;
  end if;

  -- macrorregiões de demonstração: saem
  update iara.territories set parent_id = null
  where parent_id in (select id from iara.territories where kind = 'MACRORREGIAO');
  delete from iara.territories where kind = 'MACRORREGIAO';
  get diagnostics v_macros = row_count;

  perform set_config('iara.skip_audit', v_skip, true);
  v := jsonb_build_object('unidades', v_unidades, 'bairros', v_bairros, 'enderecos', v_enderecos, 'fila', v_fila,
                          'orgaos', v_orgaos, 'macrorregioes_removidas', v_macros,
                          'areas', (select count(*) from iara.territories where kind = 'AREA_PONDERACAO'),
                          'setores', (select count(*) from iara.setores_censitarios));
  perform iara.audit_event('TERRITORIO_REORGANIZADO', 'territories', 'areas_ponderacao', null,
    'Recorte territorial passou a ser a área de ponderação do IBGE (Censo 2022); macrorregiões de demonstração retiradas.', v);
  return v;
end $$;

-- ---------------------------------------------------------------------------
-- 4. API pública: camadas do mapa, setores (demanda), território e busca
-- ---------------------------------------------------------------------------
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
           (select coalesce(sum(public_enrollments), 0) from iara.education_units u where u.macro_territory_id = t.id) as enrollments,
           iara.censo_territorio(t.id) as censo
    from iara.territories t where t.kind = 'AREA_PONDERACAO'
  )
  select jsonb_build_object(
    'municipality', (select jsonb_build_object('type', 'Feature', 'properties', jsonb_build_object('name', name, 'source', source),
                                               'geometry', st_asgeojson(st_simplifypreservetopology(geom::geometry, 0.0003), 6)::jsonb)
                     from iara.territories where id = 100),
    'regions', jsonb_build_object('type', 'FeatureCollection', 'features', (
      select coalesce(jsonb_agg(jsonb_build_object('type', 'Feature', 'id', t.id,
        'properties', jsonb_build_object('id', t.id, 'code', t.code, 'label', 'AP ' || right(t.code, 3), 'name', t.name, 'color', t.color,
                                         'kind', t.kind, 'source', t.source,
                                         'lat', st_y(t.center::geometry), 'lng', st_x(t.center::geometry),
                                         'units', s.units, 'enrollments', s.enrollments, 'offerable', s.offerable, 'queue', s.queue,
                                         'offerable_creche', s.offerable_creche, 'queue_creche', s.queue_creche,
                                         'balance', s.offerable - s.queue, 'balance_creche', s.offerable_creche - s.queue_creche,
                                         'pessoas', (s.censo ->> 'pessoas')::int, 'domicilios', (s.censo ->> 'domicilios')::int,
                                         'criancas_0a4', (s.censo ->> 'criancas_0a4')::int),
        'geometry', st_asgeojson(st_simplifypreservetopology(t.geom::geometry, 0.00015), 6)::jsonb) order by t.sort), '[]'::jsonb)
      from iara.territories t join stats s on s.id = t.id where t.geom is not null)),
    'districts', jsonb_build_object('type', 'FeatureCollection', 'features', (
      select coalesce(jsonb_agg(jsonb_build_object('type', 'Feature', 'id', t.id,
        'properties', jsonb_build_object('id', t.id, 'name', t.name, 'parent_id', t.parent_id, 'source', t.source),
        'geometry', st_asgeojson(st_simplifypreservetopology(t.geom::geometry, 0.00015), 6)::jsonb)), '[]'::jsonb)
      from iara.territories t where t.kind = 'DISTRITO' and t.geom is not null)),
    'areas', jsonb_build_object('type', 'FeatureCollection', 'features', (
      select coalesce(jsonb_agg(jsonb_build_object('type', 'Feature', 'id', u.id,
        'properties', jsonb_build_object('id', u.id, 'name', u.short_name, 'type', u.unit_type, 'macro_id', u.macro_territory_id),
        'geometry', st_asgeojson(st_simplifypreservetopology(u.influence_area::geometry, 0.0003), 6)::jsonb)), '[]'::jsonb)
      from iara.education_units u where u.influence_area is not null)),
    'notes', jsonb_build_array(
      'Limite municipal: malha IBGE.',
      'Áreas de ponderação, setores e distritos: IBGE, Censo Demográfico 2022 (malha simplificada).',
      'Áreas de influência (Voronoi por proximidade) são cálculo de demonstração; o zoneamento escolar oficial deve ser definido pela SEDUC.')
  )
$$;

-- setores censitários com os agregados do Censo 2022 (camada de demanda do mapa); opcionalmente só os de uma área
create or replace function api.geo_setores(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = iara, extensions, public
as $$
  select jsonb_build_object(
    'type', 'FeatureCollection',
    'fonte', 'IBGE — Censo Demográfico 2022: agregados por setor censitário. Crianças de 0 a 4 anos em branco = sigilo do IBGE.',
    'features', coalesce(jsonb_agg(jsonb_build_object('type', 'Feature',
      'properties', jsonb_build_object('code', s.code, 'area_id', s.area_ponderacao_id, 'area', 'AP ' || right(t.code, 3), 'distrito', s.distrito,
                                       'situacao', s.situacao, 'bairro', s.bairro, 'area_km2', s.area_km2, 'pessoas', s.pessoas,
                                       'domicilios', s.domicilios, 'criancas_0a4', s.criancas_0a4),
      'geometry', st_asgeojson(st_simplifypreservetopology(s.geom::geometry, 0.00008), 5)::jsonb) order by s.code), '[]'::jsonb))
  from iara.setores_censitarios s join iara.territories t on t.id = s.area_ponderacao_id
  where nullif(p ->> 'area_id', '') is null or s.area_ponderacao_id = (p ->> 'area_id')::int
$$;

create or replace function api.territory_detail(p jsonb) returns jsonb
language sql stable security definer set search_path = iara, extensions, public
as $$
  with t as (select * from iara.territories where id = (p ->> 'id')::int),
  un as (select u.* from iara.education_units u where u.id in (select iara.unidades_do_territorio((p ->> 'id')::int)))
  select jsonb_build_object(
    'territory', jsonb_build_object('id', t.id, 'code', t.code, 'name', t.name, 'kind', t.kind, 'color', t.color, 'source', t.source,
                                    'confidence', t.confidence_status, 'area_km2', round((st_area(t.geom) / 1e6)::numeric, 1),
                                    'lat', st_y(t.center::geometry), 'lng', st_x(t.center::geometry),
                                    'parent', (select jsonb_build_object('id', pt.id, 'name', pt.name, 'kind', pt.kind)
                                               from iara.territories pt where pt.id = t.parent_id and pt.kind <> 'MUNICIPIO')),
    'censo', iara.censo_territorio(t.id),
    'kpis', iara.kpis(t.id),
    'by_grade', coalesce((select jsonb_agg(x order by (x ->> 'sort')::int) from (
        select jsonb_build_object('grade_level_id', gl.id, 'grade', gl.name, 'sort', gl.sort,
          'offerable', (select coalesce(sum(c.offerable_vacancies_count), 0) from iara.classes c join un u on u.id = c.unit_id
                        where c.grade_level_id = gl.id),
          'capacity', (select coalesce(sum(c.authorized_capacity), 0) from iara.classes c join un u on u.id = c.unit_id
                        where c.grade_level_id = gl.id),
          'enrolled', (select coalesce(sum(c.active_enrollments_count), 0) from iara.classes c join un u on u.id = c.unit_id
                        where c.grade_level_id = gl.id),
          'queue', (select count(*) from iara.waiting_list_entries w join un u on u.id = w.preferred_unit_id
                    where w.grade_level_id = gl.id and w.status in ('WAITING', 'OFFERED'))) as x
        from iara.grade_levels gl) z), '[]'::jsonb),
    'units', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'short_name', u.short_name, 'type', u.unit_type,
                                                           'neighborhood', u.neighborhood, 'lat', u.lat, 'lng', u.lng, 'ops', iara.unit_ops(u.id),
                                                           'public_enrollments', u.public_enrollments) order by u.short_name)
                       from un u), '[]'::jsonb),
    'districts', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'censo', iara.censo_territorio(d.id),
                                   'units', (select count(*) from iara.unidades_do_territorio(d.id))) order by d.sort)
                           from iara.territories d where d.parent_id = t.id and d.kind = 'DISTRITO'), '[]'::jsonb),
    'neighborhoods', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name,
                                   'units', (select count(*) from iara.education_units u where u.neighborhood_territory_id = b.id)) order by b.name)
                               from iara.territories b where b.kind = 'BAIRRO'
                                 and (b.parent_id = t.id or (t.kind = 'DISTRITO' and t.geom is not null and st_covers(t.geom, b.center)))), '[]'::jsonb)
  )
  from t
$$;

create or replace function api.geo_search(p jsonb) returns jsonb
language sql stable security definer set search_path = iara, extensions, public
as $$
  with q as (select iara.norm(coalesce(p ->> 'q', '')) as q)
  select jsonb_build_object('items', coalesce(jsonb_agg(x order by x ->> 'rank', x ->> 'label'), '[]'::jsonb))
  from (
    select jsonb_build_object('kind', 'BAIRRO', 'label', t.name, 'sub', 'Bairro/região', 'lat', st_y(t.center::geometry), 'lng', st_x(t.center::geometry), 'rank', '1') as x
    from iara.territories t, q where t.kind = 'BAIRRO' and length(q.q) >= 2 and iara.norm(t.name) like '%' || q.q || '%'
    union all
    select jsonb_build_object('kind', 'AREA', 'label', t.name, 'sub', 'Área de ponderação (IBGE, Censo 2022)', 'territory_id', t.id,
                              'lat', st_y(t.center::geometry), 'lng', st_x(t.center::geometry), 'rank', '2')
    from iara.territories t, q where t.kind = 'AREA_PONDERACAO' and length(q.q) >= 2
      and (iara.norm(t.name) like '%' || q.q || '%' or replace(iara.norm(t.name), ' ', '') like '%' || replace(q.q, ' ', '') || '%')
    union all
    select jsonb_build_object('kind', 'UNIDADE', 'label', u.name, 'sub', coalesce(u.address_line, '') || ' · ' || coalesce(u.neighborhood, ''),
                              'lat', u.lat, 'lng', u.lng, 'unit_id', u.id, 'rank', '3')
    from iara.education_units u, q where length(q.q) >= 2 and iara.norm(u.name || ' ' || coalesce(u.address_line, '')) like '%' || q.q || '%'
    limit 12
  ) z
$$;

-- indicadores de um território: para distrito, as unidades dentro do limite do distrito
create or replace function iara.kpis(p_territory integer default null, p_stage text default null) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  with u as (
    select * from iara.education_units
    where (p_territory is null or id in (select iara.unidades_do_territorio(p_territory)))
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

-- ---------------------------------------------------------------------------
-- 5. Funções que filtravam por macrorregião/distrito: agora por área de ponderação
-- ---------------------------------------------------------------------------
-- api.bootstrap (de 20261003003500_rotina_apresentacao.sql)
create or replace function api.bootstrap(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'iara', 'public'
AS $function$
  select jsonb_build_object(
    'tenant', (select jsonb_build_object('id', id, 'name', name, 'state', state, 'ibge', ibge_code,
                                         'network_name', settings ->> 'network_name', 'secretariat', settings ->> 'secretariat',
                                         'school_year', (settings ->> 'school_year')::int, 'official_reference_date', settings ->> 'official_reference_date',
                                         'city_center', settings -> 'city_center', 'demo_mode', (settings ->> 'demo_mode')::boolean,
                                         'demo_unit', (settings ->> 'demo_unit_maria')::int)
               from iara.tenants where id = 1),
    'whatsapp', (select jsonb_build_object(
                   'numero', coalesce(nullif(regexp_replace(coalesce(t.settings ->> 'iara_whatsapp_numero', ''), '[^0-9]', '', 'g'), ''),
                                      (select regexp_replace(c.numero_e164, '[^0-9]', '', 'g') from iara.whatsapp_channels c
                                       where c.ativo and c.conectado and c.ultimo_sinal_em > now() - interval '5 minutes'
                                       order by c.ligado_em desc nulls last limit 1)),
                   -- ligado = interruptor ligado E ponte dando sinal: sem ponte, ninguém da Educação responde no número
                   'canal_ativo', exists (select 1 from iara.whatsapp_channels c
                                          where c.ativo and c.conectado and c.ultimo_sinal_em > now() - interval '5 minutes'),
                   'canal_ligado', exists (select 1 from iara.whatsapp_channels c where c.ativo),
                   'numero_demo', coalesce(t.settings ->> 'iara_whatsapp_numero_demo', '(44) 90000-0000'),
                   'mensagem', coalesce(nullif(t.settings ->> 'iara_whatsapp_mensagem', ''), 'Olá, IARA! Quero atendimento da Educação de Maringá.'),
                   'url_publica', t.settings ->> 'public_url')
                 from iara.tenants t where t.id = 1),
    'flags', (select jsonb_object_agg(code, enabled) from iara.feature_flags),
    'personas', (select jsonb_agg(jsonb_build_object('code', code, 'name', name, 'short_name', short_name, 'description', description,
                                                     'question', question, 'scope_type', scope_type, 'org_unit', org_unit, 'stage_filter', stage_filter)
                                  order by sort) from iara.organizational_roles where is_persona),
    'stages', (select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', name, 'short_name', short_name, 'color', color) order by sort) from iara.education_stages),
    'grades', (select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', name, 'short_name', short_name, 'stage_id', stage_id,
                                                   'min_age_months', min_age_months, 'max_age_months', max_age_months) order by sort) from iara.grade_levels),
    'territories', (select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', name, 'kind', kind, 'color', color,
                                                        'lat', extensions.st_y(center::extensions.geometry), 'lng', extensions.st_x(center::extensions.geometry)) order by sort)
                    from iara.territories where kind = 'AREA_PONDERACAO'),
    'kpis', iara.kpis(),
    'rule_version', iara.rule_version(),
    'import', (select jsonb_build_object('id', id, 'file', source_file, 'imported_at', imported_at, 'counts', row_counts) from iara.import_batches limit 1)
  )
$function$;

-- api.report (de 20261003001100_api_operacao.sql)
create or replace function api.report(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_key text := p ->> 'key';
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else (p ->> 'unit_id')::int end;
  v_rows jsonb;
  v_cols jsonb;
  v_title text;
begin
  perform iara.require_perm('reports.export');
  if v_key = 'ocupacao_por_unidade' then
    v_title := 'Ocupação por unidade (DEMO)';
    v_cols := '["Unidade","Tipo","Área de ponderação","Turmas","Capacidade","Matrículas","Ocupação %","Vagas ofertáveis","Fila"]';
    select jsonb_agg(jsonb_build_array(u.name, u.unit_type_label, t.name, (o ->> 'classes')::int, (o ->> 'capacity')::int, (o ->> 'enrolled')::int,
                                       (o ->> 'occupancy')::numeric, (o ->> 'offerable')::int, (o ->> 'queue')::int) order by u.short_name)
    into v_rows
    from iara.education_units u left join iara.territories t on t.id = u.macro_territory_id, lateral iara.unit_ops(u.id) o
    where v_unit is null or u.id = v_unit;
  elsif v_key = 'vagas_por_turma' then
    v_title := 'Vagas por turma (DEMO)';
    v_cols := '["Unidade","Turma","Série/faixa","Turno","Capacidade","Matrículas","Bloqueadas","Reservadas","Ofertáveis"]';
    select jsonb_agg(jsonb_build_array(u.short_name, c.class_name, gl.name, c.shift, c.authorized_capacity, c.active_enrollments_count,
                                       c.blocked_seats_count, c.reserved_seats_count, c.offerable_vacancies_count) order by u.short_name, gl.sort, c.class_code)
    into v_rows
    from iara.classes c join iara.education_units u on u.id = c.unit_id join iara.grade_levels gl on gl.id = c.grade_level_id
    where v_unit is null or c.unit_id = v_unit;
  elsif v_key = 'fila_por_unidade' then
    v_title := 'Fila por unidade e faixa (DEMO)';
    v_cols := '["Unidade","Área de ponderação","Faixa","Aguardando","Com oferta","Espera média (dias)","Vagas ofertáveis"]';
    select jsonb_agg(jsonb_build_array(u.short_name, t.name, gl.name, x.waiting, x.offered, x.avg_days,
                                       (select coalesce(sum(c.offerable_vacancies_count), 0) from iara.classes c where c.unit_id = u.id and c.grade_level_id = gl.id))
                     order by u.short_name, gl.sort)
    into v_rows
    from (select preferred_unit_id, grade_level_id, count(*) filter (where status = 'WAITING') waiting, count(*) filter (where status = 'OFFERED') offered,
                 round(avg(current_date - entered_at::date)) avg_days
          from iara.waiting_list_entries where status in ('WAITING', 'OFFERED') group by 1, 2) x
    join iara.education_units u on u.id = x.preferred_unit_id join iara.grade_levels gl on gl.id = x.grade_level_id
    left join iara.territories t on t.id = u.macro_territory_id
    where v_unit is null or u.id = v_unit;
  elsif v_key = 'fila_por_regiao' then
    v_title := 'Demanda x oferta por área de ponderação (DEMO)';
    v_cols := '["Área de ponderação","Faixa","Fila","Vagas ofertáveis","Saldo"]';
    select jsonb_agg(jsonb_build_array(t.name, gl.name, q.n, v.n, coalesce(v.n, 0) - coalesce(q.n, 0)) order by t.sort, gl.sort)
    into v_rows
    from iara.territories t cross join iara.grade_levels gl
    left join lateral (select count(*) n from iara.waiting_list_entries w join iara.education_units u on u.id = w.preferred_unit_id
                       where u.macro_territory_id = t.id and w.grade_level_id = gl.id and w.status in ('WAITING', 'OFFERED')) q on true
    left join lateral (select coalesce(sum(c.offerable_vacancies_count), 0) n from iara.classes c join iara.education_units u on u.id = c.unit_id
                       where u.macro_territory_id = t.id and c.grade_level_id = gl.id) v on true
    where t.kind = 'AREA_PONDERACAO';
  elsif v_key = 'protocolos' then
    v_title := 'Protocolos abertos por tipo e status (DEMO)';
    v_cols := '["Tipo","Status","Quantidade","Vencidos (SLA)"]';
    select jsonb_agg(jsonb_build_array(sc.name, x.status, x.n, x.overdue) order by sc.sort, x.status)
    into v_rows
    from (select case_type, status, count(*) n, count(*) filter (where sla_due_at < now()) overdue
          from iara.service_cases where iara.case_open(status) and (v_unit is null or unit_id = v_unit) group by 1, 2) x
    join iara.service_catalog sc on sc.code = x.case_type;
  else
    raise exception 'Relatório desconhecido.' using errcode = '22023';
  end if;
  perform iara.audit_event('EXPORT', 'report', v_key, v_unit, format('Exportação do relatório "%s" (%s linhas).', v_title, jsonb_array_length(coalesce(v_rows, '[]'))));
  return jsonb_build_object('title', v_title, 'columns', v_cols, 'rows', coalesce(v_rows, '[]'::jsonb), 'generated_at', now(),
                            'notice', 'Dados operacionais de DEMONSTRAÇÃO. Exportação registrada na auditoria.');
end $$;

-- api.dashboard_prefeito (de 20261003001300_api_paineis.sql)
create or replace function api.dashboard_prefeito(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, extensions, public
as $$
declare
  v jsonb;
begin
  perform iara.require_perm('kpi.network');
  with reg as (
    select t.id, t.name, t.color, t.kind,
      (select count(*) from iara.education_units u where u.macro_territory_id = t.id) as units,
      (select coalesce(sum(public_enrollments), 0) from iara.education_units u where u.macro_territory_id = t.id) as enrollments,
      (select coalesce(sum(c.offerable_vacancies_count), 0) from iara.classes c join iara.education_units u on u.id = c.unit_id where u.macro_territory_id = t.id) as offerable,
      (select coalesce(sum(c.offerable_vacancies_count), 0) from iara.classes c join iara.education_units u on u.id = c.unit_id where u.macro_territory_id = t.id and c.grade_level_id = 1) as offerable_creche,
      (select count(*) from iara.waiting_list_entries w join iara.education_units u on u.id = w.preferred_unit_id where u.macro_territory_id = t.id and w.status in ('WAITING', 'OFFERED')) as queue,
      (select count(*) from iara.waiting_list_entries w join iara.education_units u on u.id = w.preferred_unit_id where u.macro_territory_id = t.id and w.status in ('WAITING', 'OFFERED') and w.grade_level_id = 1) as queue_creche,
      (select round(avg(st_distance(a.location, u.location))::numeric / 1000, 2) from iara.enrollments e join iara.students s on s.id = e.student_id
         join iara.addresses a on a.id = s.address_id join iara.education_units u on u.id = e.unit_id
        where e.status = 'ACTIVE' and u.macro_territory_id = t.id) as avg_km,
      (select round(avg(c.active_enrollments_count::numeric / nullif(c.authorized_capacity, 0)) * 100, 1) from iara.classes c join iara.education_units u on u.id = c.unit_id where u.macro_territory_id = t.id) as occupancy,
      iara.censo_territorio(t.id) as censo, t.code
    from iara.territories t where t.kind = 'AREA_PONDERACAO'
  ),
  dist as (
    select count(*) as n, avg(st_distance(a.location, u.location)) as avg_m,
           count(*) filter (where st_distance(a.location, u.location) <= 2000) as within
    from iara.enrollments e join iara.students s on s.id = e.student_id join iara.addresses a on a.id = s.address_id
    join iara.education_units u on u.id = e.unit_id where e.status = 'ACTIVE'
  ),
  monthly as (
    select to_char(date_trunc('month', x.d), 'YYYY-MM') as m, sum(x.enr) as enrollments, sum(x.q) as queue_in
    from (select enrollment_date::timestamptz as d, 1 as enr, 0 as q from iara.enrollments where entry_type in ('NOVA', 'OFERTA_FILA', 'TRANSFERENCIA') and enrollment_date >= date '2025-11-01'
          union all select entered_at, 0, 1 from iara.waiting_list_entries where entered_at >= timestamptz '2026-01-01') x
    group by 1 order by 1
  ),
  trend as (
    select regr_slope(n, k) as slope, regr_intercept(n, k) as icpt, max(k) as kmax
    from (select row_number() over (order by date_trunc('month', entered_at)) as k, count(*)::numeric as n
          from iara.waiting_list_entries where grade_level_id = 1 and entered_at >= now() - interval '7 months'
          group by date_trunc('month', entered_at)) z
  )
  select jsonb_build_object(
    'question', 'Onde precisamos investir?',
    'kpis', iara.kpis(),
    'regions', (select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'color', color, 'kind', kind, 'units', units, 'enrollments', enrollments,
                                                    'offerable', offerable, 'queue', queue, 'balance', offerable - queue,
                                                    'offerable_creche', offerable_creche, 'queue_creche', queue_creche, 'balance_creche', offerable_creche - queue_creche,
                                                    'avg_km', avg_km, 'occupancy', occupancy, 'label', 'AP ' || right(code, 3),
                                                    'pessoas', (censo ->> 'pessoas')::int, 'criancas_0a4', (censo ->> 'criancas_0a4')::int,
                                                    -- faixas por área de ponderação (~1/5 de uma antiga macrorregião)
                                                    'pressure', case when offerable_creche - queue_creche <= -40 then 'SEVERO' when offerable_creche - queue_creche <= -20 then 'ALTO'
                                                                     when offerable_creche - queue_creche < 0 then 'ATENCAO' when offerable - queue > 60 then 'OCIOSO' else 'EQUILIBRIO' end)
                                 order by (offerable_creche - queue_creche)) from reg),
    'distance', (select jsonb_build_object('students', n, 'avg_km', round((avg_m / 1000)::numeric, 2), 'within_2km_pct', round(100.0 * within / nullif(n, 0), 1),
                                           'source', 'DEMO — endereços fictícios; cálculo em linha reta (PostGIS)') from dist),
    'saturated', (select coalesce(jsonb_agg(x order by (x ->> 'queue_creche')::int desc), '[]'::jsonb) from (
        select jsonb_build_object('id', u.id, 'name', u.short_name, 'type', u.unit_type, 'territory', t.name,
                                  'queue_creche', (select count(*) from iara.waiting_list_entries w where w.preferred_unit_id = u.id and w.grade_level_id = 1 and w.status in ('WAITING', 'OFFERED')),
                                  'queue', (o ->> 'queue')::int, 'offerable', (o ->> 'offerable')::int, 'occupancy', (o ->> 'occupancy')::numeric) as x
        from iara.education_units u join iara.territories t on t.id = u.macro_territory_id, lateral iara.unit_ops(u.id) o
        where (o ->> 'queue')::int >= 12 and (o ->> 'offerable')::int <= 1 order by (o ->> 'queue')::int desc limit 8) z),
    'idle', (select coalesce(jsonb_agg(x order by (x ->> 'offerable')::int desc), '[]'::jsonb) from (
        select jsonb_build_object('id', u.id, 'name', u.short_name, 'type', u.unit_type, 'territory', t.name, 'offerable', (o ->> 'offerable')::int,
                                  'queue', (o ->> 'queue')::int, 'occupancy', (o ->> 'occupancy')::numeric) as x
        from iara.education_units u join iara.territories t on t.id = u.macro_territory_id, lateral iara.unit_ops(u.id) o
        where (o ->> 'queue')::int <= 2 and (o ->> 'offerable')::int >= 25 order by (o ->> 'offerable')::int desc limit 8) z),
    'monthly', (select coalesce(jsonb_agg(jsonb_build_object('month', m, 'enrollments', enrollments, 'queue_in', queue_in)), '[]'::jsonb) from monthly),
    'projection', (select jsonb_build_object('label', 'PROJETADO', 'method', 'Tendência linear das entradas mensais na fila de creche (7 meses). Cenário, não fato.',
                                             'next_months', jsonb_build_array(round(greatest(icpt + slope * (kmax + 1), 0)), round(greatest(icpt + slope * (kmax + 2), 0)),
                                                                              round(greatest(icpt + slope * (kmax + 3), 0)))) from trend),
    'service', (select jsonb_build_object('avg_resolution_days', round(avg(extract(epoch from (closed_at - opened_at)) / 86400)::numeric, 1),
                                          'within_sla_pct', round(100.0 * count(*) filter (where closed_at <= sla_due_at) / nullif(count(*), 0), 1), 'closed', count(*))
                from iara.service_cases where closed_at is not null and closed_at > now() - interval '120 days'),
    'expansion', (select coalesce(jsonb_agg(jsonb_build_object('territory', name, 'deficit_creche', -(offerable_creche - queue_creche),
                                                               'suggested_classes', ceil(-(offerable_creche - queue_creche) / 20.0),
                                                               'note', 'Sugestão por regra simples (déficit ÷ capacidade de referência de 20). Cenário.'))
                                    filter (where offerable_creche - queue_creche < 0), '[]'::jsonb) from reg),
    'alerts', jsonb_build_array(
      (select jsonb_build_object('level', 'CRITICO', 'title', name || ': déficit de ' || -(offerable_creche - queue_creche) || ' vagas de creche',
                                 'territory_id', id) from reg where offerable_creche - queue_creche < 0 order by offerable_creche - queue_creche limit 1),
      (select jsonb_build_object('level', 'ATENCAO', 'title', count(*) || ' protocolos com prazo (SLA) vencido') from iara.service_cases where iara.case_open(status) and sla_due_at < now()),
      (select jsonb_build_object('level', 'INFO', 'title', count(*) || ' ofertas aguardando resposta das famílias') from iara.vacancy_offers where status = 'OFFERED'))
  ) into v;
  return v;
end $$;

-- iara.new_address (de 20261003001900_iara_resolutiva.sql)
create or replace function iara.new_address(p_addr jsonb, p_source text) returns uuid
language plpgsql security definer set search_path = iara, extensions, public
as $$
declare
  v_id uuid := gen_random_uuid();
  v_lat float8 := nullif(p_addr ->> 'lat', '')::float8;
  v_lng float8 := nullif(p_addr ->> 'lng', '')::float8;
  v_terr integer;
begin
  if v_lat is null or v_lng is null then
    raise exception 'Informe o bairro (ou marque o ponto no mapa) para localizar o endereço.' using errcode = '22023';
  end if;
  if not iara.in_maringa(v_lat, v_lng) then
    raise exception 'Este endereço fica fora de Maringá. A fila da rede municipal considera o endereço no município.' using errcode = '22023';
  end if;
  select t.id into v_terr from iara.territories t
  where t.kind = 'AREA_PONDERACAO' and st_covers(t.geom, iara.point(v_lat, v_lng)) limit 1;
  insert into iara.addresses (id, tenant_id, street, number, complement, neighborhood, postal_code, location, geocode_precision, geocode_source,
                              territory_id, is_demo)
  values (v_id, 1, coalesce(nullif(btrim(p_addr ->> 'street'), ''), 'Endereço informado'), nullif(btrim(p_addr ->> 'number'), ''),
          nullif(btrim(p_addr ->> 'complement'), ''), nullif(btrim(p_addr ->> 'neighborhood'), ''), nullif(btrim(p_addr ->> 'postal_code'), ''),
          iara.point(v_lat, v_lng), coalesce(nullif(p_addr ->> 'precision', ''), 'BAIRRO'), p_source, v_terr, true);
  return v_id;
end $$;

-- iara.localizar (de 20261003003000_cadastro_pessoas.sql)
create or replace function iara.localizar(p_lat double precision, p_lng double precision) returns jsonb
language sql stable security definer set search_path = iara, extensions, public
as $$
  with pt as (select iara.point(p_lat, p_lng) as g)
  select jsonb_build_object(
    'dentro_maringa', iara.in_maringa(p_lat, p_lng),
    'territorio_id', t.id, 'territorio', t.name, 'territorio_tipo', t.kind, 'distrito', d.name,
    'bairro', b.name, 'bairro_distancia_m', b.dist)
  from pt
  left join lateral (select t.id, t.name, t.kind from iara.territories t
                     where t.kind = 'AREA_PONDERACAO' and t.geom is not null and st_covers(t.geom, pt.g) limit 1) t on true
  left join lateral (select d.name from iara.territories d
                     where d.kind = 'DISTRITO' and d.geom is not null and st_covers(d.geom, pt.g) limit 1) d on true
  left join lateral (select b.name, round(st_distance(b.center, pt.g))::int as dist from iara.territories b
                     where b.kind = 'BAIRRO' and b.center is not null order by st_distance(b.center, pt.g) limit 1) b on true
$$;

-- api.controle_painel (de 20261003003200_controle_externo.sql)
create or replace function api.controle_painel(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_desde timestamptz := now() - interval '12 months';
  v_filas jsonb;
begin
  perform iara.require_perm('controle.read');
  select jsonb_build_object('filas', count(*), 'conferidas', count(*) filter (where conferida),
                            'divergentes', coalesce(jsonb_agg(jsonb_build_object('unidade', u.short_name, 'faixa', gl.name)) filter (where not conferida), '[]'::jsonb))
  into v_filas
  from iara.filas_conferencia() f join iara.education_units u on u.id = f.unit_id join iara.grade_levels gl on gl.id = f.grade_level_id;

  return jsonb_build_object(
    'gerado_em', now(),
    'regras', jsonb_build_object('versao', iara.rule_version(), 'medida_distancia', iara.medida_distancia_fila()),
    'ordem', v_filas,
    -- espera
    'fila', (select jsonb_build_object(
        'aguardando', count(*),
        'espera_media_dias', round(avg(current_date - w.entered_at::date)),
        'espera_mediana_dias', round(percentile_cont(0.5) within group (order by current_date - w.entered_at::date)),
        'espera_max_dias', max(current_date - w.entered_at::date),
        'mais_90', count(*) filter (where current_date - w.entered_at::date > 90),
        'mais_180', count(*) filter (where current_date - w.entered_at::date > 180),
        'laudo', count(*) filter (where 'PCD_TEA_AEE' = any (w.priority_flags)),
        'por_faixa', (select coalesce(jsonb_agg(jsonb_build_object('faixa', gl.name, 'curto', gl.short_name, 'aguardando', z.n, 'espera_media_dias', z.media,
                                                                   'mais_90', z.m90, 'vagas', z.vagas) order by gl.id), '[]'::jsonb)
                      from (select w2.grade_level_id, count(*) n, round(avg(current_date - w2.entered_at::date)) media,
                                   count(*) filter (where current_date - w2.entered_at::date > 90) m90,
                                   (select coalesce(sum(c.offerable_vacancies_count), 0) from iara.classes c
                                    where c.grade_level_id = w2.grade_level_id and c.status = 'ATIVA') vagas
                            from iara.waiting_list_entries w2 where w2.status = 'WAITING' group by 1) z
                      join iara.grade_levels gl on gl.id = z.grade_level_id))
      from iara.waiting_list_entries w where w.status = 'WAITING'),
    -- vagas ofertáveis em filas com crianças aguardando (deveriam ser ofertadas, na ordem)
    'vagas_com_fila', (with vf as (
          select c.unit_id, c.grade_level_id, sum(c.offerable_vacancies_count)::int vagas
          from iara.classes c where c.status = 'ATIVA' and c.offerable_vacancies_count > 0 group by 1, 2),
        ff as (
          select preferred_unit_id as unit_id, grade_level_id, count(*)::int aguardando, min(entered_at) desde
          from iara.waiting_list_entries where status = 'WAITING' group by 1, 2),
        j as (select vf.*, ff.aguardando, ff.desde from vf join ff using (unit_id, grade_level_id))
        select jsonb_build_object(
          'filas', count(*), 'vagas', coalesce(sum(least(j.vagas, j.aguardando)), 0), 'criancas', coalesce(sum(j.aguardando), 0),
          'itens', coalesce((select jsonb_agg(jsonb_build_object('unit_id', x.unit_id, 'unidade', u.short_name, 'faixa', gl.name, 'vagas', x.vagas,
                                                                 'aguardando', x.aguardando, 'espera_dias', current_date - x.desde::date)
                                              order by least(x.vagas, x.aguardando) desc, x.aguardando desc)
                             from (select * from j order by least(j.vagas, j.aguardando) desc, j.aguardando desc limit 12) x
                             join iara.education_units u on u.id = x.unit_id join iara.grade_levels gl on gl.id = x.grade_level_id), '[]'::jsonb))
        from j),
    -- ofertas dos últimos 12 meses frente à ordem da fila
    'ofertas', (select jsonb_build_object(
        'desde', v_desde::date,
        'total', count(*),
        'na_ordem', count(*) filter (where k.tipo = 'NA_ORDEM'),
        'laudo', count(*) filter (where k.tipo = 'LAUDO'),
        'alternativa', count(*) filter (where k.tipo = 'ALTERNATIVA'),
        'sem_registro', count(*) filter (where k.tipo = 'SEM_REGISTRO'),
        'abertas', count(*) filter (where o.status = 'OFFERED'),
        'vencem_24h', count(*) filter (where o.status = 'OFFERED' and o.expires_at < now() + interval '24 hours'),
        'aceitas', count(*) filter (where o.status in ('ACCEPTED', 'ENROLLED')),
        'matriculadas', count(*) filter (where o.status = 'ENROLLED'),
        'recusadas', count(*) filter (where o.status = 'DECLINED'),
        'expiradas', count(*) filter (where o.status = 'EXPIRED'),
        'resposta_media_h', round(avg(extract(epoch from (coalesce(o.accepted_at, o.declined_at) - o.offered_at)) / 3600.0)
                                  filter (where coalesce(o.accepted_at, o.declined_at) is not null))::int)
      from iara.vacancy_offers o cross join lateral (select iara.oferta_tipo(o) as tipo) k
      where o.offered_at >= v_desde),
    -- exceções à ordem (prioridade sob análise por laudo): pela auditoria imutável, sem CID e sem nomes
    'excecoes', (select coalesce(jsonb_agg(jsonb_build_object(
          'quando', a.occurred_at, 'unidade', u.short_name, 'codigo', iara.codigo_publico(case when a.entity_id ~ '^[0-9a-f-]{36}$' then a.entity_id::uuid end),
          'quem', regexp_replace(coalesce(a.actor_label, ''), '\s*\(demo #[0-9A-F]+\)', ''),
          'resumo', iara.anonimizar(a.summary, iara.nomes_da_inscricao(a.entity_id))) order by a.occurred_at desc), '[]'::jsonb)
      from (select * from iara.audit_log a1 where a1.action = 'PRIORITY_DECISION' and iara.excecao_com_oferta(a1.entity_id)
            order by a1.occurred_at desc limit 20) a
      left join iara.education_units u on u.id = a.unit_id),
    -- prazos dos protocolos de vaga
    'protocolos', (select jsonb_build_object(
        'abertos', count(*) filter (where iara.case_open(c.status)),
        'vencidos', count(*) filter (where iara.case_open(c.status) and c.sla_due_at < now()),
        'concluidos_12m', count(*) filter (where not iara.case_open(c.status) and c.closed_at >= v_desde))
      from iara.service_cases c where c.case_type in ('SOLICITACAO_VAGA', 'MATRICULA', 'TRANSFERENCIA', 'TRANSFERENCIA_EXTERNA', 'RECURSO')),
    -- saldo por região: crianças aguardando × vagas ofertáveis
    'regioes', (select coalesce(jsonb_agg(r order by (r ->> 'saldo')::int), '[]'::jsonb) from (
        select jsonb_build_object('regiao', t.name, 'aguardando', a.n, 'aguardando_creche', a.creche, 'vagas', v.n, 'vagas_creche', v.creche,
                                  'saldo', v.n - a.n, 'saldo_creche', v.creche - a.creche) r
        from iara.territories t
        cross join lateral (select count(*) n, count(*) filter (where w.grade_level_id = 1) creche
                            from iara.waiting_list_entries w join iara.education_units u on u.id = w.preferred_unit_id
                            where w.status = 'WAITING' and u.macro_territory_id = t.id) a
        cross join lateral (select coalesce(sum(c.offerable_vacancies_count), 0)::int n,
                                   coalesce(sum(c.offerable_vacancies_count) filter (where c.grade_level_id = 1), 0)::int creche
                            from iara.classes c join iara.education_units u on u.id = c.unit_id
                            where c.status = 'ATIVA' and u.macro_territory_id = t.id) v
        where t.kind = 'AREA_PONDERACAO' and (a.n > 0 or v.n > 0)) z),
    'distancias', api.distancias_resumo('{}'::jsonb),
    -- trilha de governança: mudanças de regra, exceções, recálculos e consultas do próprio controle externo
    'governanca', (select coalesce(jsonb_agg(jsonb_build_object(
          'quando', a.occurred_at, 'acao', a.action,
          'quem', regexp_replace(coalesce(a.actor_label, ''), '\s*\(demo #[0-9A-F]+\)', ''),
          'resumo', iara.anonimizar(a.summary, case when a.action = 'PRIORITY_DECISION' then iara.nomes_da_inscricao(a.entity_id) else '{}' end))
          order by a.occurred_at desc), '[]'::jsonb)
      from (select * from iara.audit_log a1
            where a1.action in ('RULE_VERSION', 'REGRA_MEDIDA_DISTANCIA', 'PRIORITY_DECISION', 'CONTROLE_CONSULTA', 'QUEUE_RECALCULATED')
              and (a1.action <> 'PRIORITY_DECISION' or iara.excecao_com_oferta(a1.entity_id))
            order by a1.occurred_at desc limit 30) a)
  );
end $$;

-- carga.endereco_novo (de 20261003003600_estrutura_carga.sql)
create or replace function carga.endereco_novo(d jsonb, p_fonte text) returns uuid
language plpgsql as $$
declare
  v_id uuid;
  v_lat double precision := carga.coord(d ->> 'lat');
  v_lng double precision := carga.coord(d ->> 'lng');
begin
  if coalesce(carga.txt(d, 'logradouro'), carga.txt(d, 'bairro'), carga.txt(d, 'cep')) is null and v_lat is null then
    return null;
  end if;
  insert into iara.addresses (tenant_id, street, number, complement, neighborhood, postal_code, city, state, location,
                              geocode_precision, geocode_source, territory_id, is_demo, geocoded_at)
  values (1, coalesce(carga.txt(d, 'logradouro'), 'Endereço informado'), carga.txt(d, 'numero'), carga.txt(d, 'complemento'),
          carga.txt(d, 'bairro'), iara.digitos(carga.txt(d, 'cep')), 'Maringá', 'PR',
          case when v_lat is not null then iara.point(v_lat, v_lng) end,
          case when v_lat is not null then 'ENDERECO' else 'PENDENTE' end, 'Carga oficial: ' || p_fonte,
          carga.territorio(v_lat, v_lng, array['AREA_PONDERACAO']), false, case when v_lat is not null then now() end)
  returning id into v_id;
  return v_id;
end $$;

-- carga.promover_registro (de 20261003003600_estrutura_carga.sql)
create or replace function carga.promover_registro(p_lote carga.lotes, d jsonb, out acao text, out destino text, out antes jsonb)
language plpgsql as $$
declare
  v_int integer;
  v_uuid uuid;
  v_unit integer;
  v_lat double precision := carga.coord(d ->> 'lat');
  v_lng double precision := carga.coord(d ->> 'lng');
  v_g iara.grade_levels;
  v_turma iara.classes;
  v_end uuid;
  v_aluno uuid;
  v_resp uuid;
  v_status text;
  v_terr integer;
  u iara.education_units;
  s iara.students;
  g iara.guardians;
  sg iara.student_guardians;
  e iara.enrollments;
begin
  case p_lote.dominio
  when 'UNIDADES' then
    v_int := carga.ref('UNIDADES', carga.txt(d, 'codigo_unidade'))::int;
    if v_int is null and carga.txt(d, 'codigo_inep') is not null then
      select id into v_int from iara.education_units where inep_code = carga.txt(d, 'codigo_inep') order by id limit 1;
    end if;
    select * into u from iara.education_units where id = v_int;
    if u.id is not null then
      antes := to_jsonb(u) - 'location' - 'influence_area';
      update iara.education_units set
        name = carga.txt(d, 'nome'), short_name = coalesce(carga.txt(d, 'nome_curto'), short_name),
        inep_code = coalesce(carga.txt(d, 'codigo_inep'), inep_code),
        unit_type = upper(carga.txt(d, 'tipo')), unit_type_label = case upper(carga.txt(d, 'tipo')) when 'CMEI' then 'CMEI' else 'Escola Municipal' end,
        status = coalesce(upper(carga.txt(d, 'situacao')), status),
        status_label = case coalesce(upper(carga.txt(d, 'situacao')), status) when 'ATIVA' then 'Ativa' when 'A_VALIDAR' then 'A validar' else 'Sem turmas' end,
        address_line = coalesce(nullif(concat_ws(', ', carga.txt(d, 'logradouro'), carga.txt(d, 'numero')), ''), address_line),
        neighborhood = coalesce(carga.txt(d, 'bairro'), neighborhood), postal_code = coalesce(iara.digitos(carga.txt(d, 'cep')), postal_code),
        phone = coalesce(carga.txt(d, 'telefone'), phone), director_name = coalesce(carga.txt(d, 'diretor'), director_name),
        lat = v_lat, lng = v_lng, location = iara.point(v_lat, v_lng), geo_precision = 'VALIDADO', geo_source = 'Carga oficial: ' || p_lote.origem,
        macro_territory_id = coalesce(carga.territorio(v_lat, v_lng, array['AREA_PONDERACAO']), macro_territory_id),
        neighborhood_territory_id = coalesce(carga.territorio(v_lat, v_lng, array['BAIRRO']), neighborhood_territory_id),
        main_source = p_lote.origem, data_reference = p_lote.data_referencia::text, import_batch_id = p_lote.codigo, updated_at = now()
      where id = u.id;
      acao := 'ATUALIZADO'; destino := u.id::text;
    else
      select coalesce(max(id), 0) + 1 into v_int from iara.education_units;
      insert into iara.education_units (id, tenant_id, name, short_name, inep_code, unit_type, unit_type_label, status, status_label,
                                        address_line, neighborhood, postal_code, city, state, phone, director_name, location, lat, lng,
                                        geo_precision, geo_source, macro_territory_id, neighborhood_territory_id, main_source, data_reference,
                                        import_batch_id, confidence_status)
      values (v_int, 1, carga.txt(d, 'nome'), coalesce(carga.txt(d, 'nome_curto'), carga.txt(d, 'nome')), carga.txt(d, 'codigo_inep'),
              upper(carga.txt(d, 'tipo')), case upper(carga.txt(d, 'tipo')) when 'CMEI' then 'CMEI' else 'Escola Municipal' end,
              coalesce(upper(carga.txt(d, 'situacao')), 'ATIVA'),
              case coalesce(upper(carga.txt(d, 'situacao')), 'ATIVA') when 'ATIVA' then 'Ativa' when 'A_VALIDAR' then 'A validar' else 'Sem turmas' end,
              nullif(concat_ws(', ', carga.txt(d, 'logradouro'), carga.txt(d, 'numero')), ''), carga.txt(d, 'bairro'),
              iara.digitos(carga.txt(d, 'cep')), 'Maringá', 'PR', carga.txt(d, 'telefone'), carga.txt(d, 'diretor'),
              iara.point(v_lat, v_lng), v_lat, v_lng, 'VALIDADO', 'Carga oficial: ' || p_lote.origem,
              carga.territorio(v_lat, v_lng, array['AREA_PONDERACAO']), carga.territorio(v_lat, v_lng, array['BAIRRO']),
              p_lote.origem, p_lote.data_referencia::text, p_lote.codigo, 'OFICIAL');
      acao := 'CRIADO'; destino := v_int::text;
    end if;

  when 'TURMAS' then
    v_unit := carga.ref('UNIDADES', carga.txt(d, 'codigo_unidade'))::int;
    v_g := carga.serie(carga.txt(d, 'serie'));
    v_uuid := carga.ref('TURMAS', carga.txt(d, 'codigo_turma'))::uuid;
    if v_uuid is null then
      select id into v_uuid from iara.classes
      where unit_id = v_unit and school_year = carga.txt(d, 'ano_letivo')::int and class_code = carga.txt(d, 'codigo_turma');
    end if;
    select * into v_turma from iara.classes where id = v_uuid;
    if v_turma.id is not null then
      antes := to_jsonb(v_turma);
      update iara.classes set unit_id = v_unit, school_year = carga.txt(d, 'ano_letivo')::int, stage_id = v_g.stage_id, grade_level_id = v_g.id,
             class_code = carga.txt(d, 'codigo_turma'), class_name = carga.txt(d, 'nome'), shift = upper(carga.txt(d, 'turno')),
             room_label = coalesce(carga.txt(d, 'sala'), room_label), authorized_capacity = carga.txt(d, 'capacidade_autorizada')::int,
             status = coalesce(upper(carga.txt(d, 'situacao')), status), source = p_lote.origem, source_updated_at = p_lote.data_referencia,
             confidence_status = 'OFICIAL', is_demo = false
      where id = v_turma.id;
      acao := 'ATUALIZADO'; destino := v_turma.id::text;
    else
      insert into iara.classes (tenant_id, school_year, unit_id, stage_id, grade_level_id, class_code, class_name, shift, room_label,
                                authorized_capacity, status, source, source_updated_at, confidence_status, is_demo)
      values (1, carga.txt(d, 'ano_letivo')::int, v_unit, v_g.stage_id, v_g.id, carga.txt(d, 'codigo_turma'), carga.txt(d, 'nome'),
              upper(carga.txt(d, 'turno')), carga.txt(d, 'sala'), carga.txt(d, 'capacidade_autorizada')::int,
              coalesce(upper(carga.txt(d, 'situacao')), 'ATIVA'), p_lote.origem, p_lote.data_referencia, 'OFICIAL', false)
      returning id into v_uuid;
      acao := 'CRIADO'; destino := v_uuid::text;
    end if;

  when 'SERVIDORES' then
    v_uuid := carga.ref('SERVIDORES', carga.txt(d, 'matricula_funcional'))::uuid;
    v_unit := carga.ref('UNIDADES', carga.txt(d, 'codigo_unidade'))::int;
    if v_uuid is not null then
      select to_jsonb(x) into antes from iara.staff x where id = v_uuid;
      update iara.staff set full_name = carga.txt(d, 'nome'), role = upper(carga.txt(d, 'funcao')), unit_id = coalesce(v_unit, unit_id),
             bond = coalesce(carga.txt(d, 'vinculo'), bond), is_demo = false
      where id = v_uuid;
      acao := 'ATUALIZADO'; destino := v_uuid::text;
    else
      insert into iara.staff (tenant_id, unit_id, full_name, role, bond, is_demo)
      values (1, v_unit, carga.txt(d, 'nome'), upper(carga.txt(d, 'funcao')), carga.txt(d, 'vinculo'), false)
      returning id into v_uuid;
      acao := 'CRIADO'; destino := v_uuid::text;
    end if;

  when 'RESPONSAVEIS' then
    v_uuid := carga.ref('RESPONSAVEIS', carga.txt(d, 'codigo_responsavel'))::uuid;
    v_end := carga.endereco_novo(d, p_lote.origem);
    select * into g from iara.guardians where id = v_uuid;
    if g.id is not null then
      antes := to_jsonb(g) || jsonb_build_object('_endereco_novo', v_end);
      update iara.guardians set full_name = carga.txt(d, 'nome'), cpf = coalesce(iara.fmt_cpf(carga.txt(d, 'cpf')), cpf),
             nis = coalesce(iara.digitos(carga.txt(d, 'nis')), nis), rg = coalesce(carga.txt(d, 'rg'), rg),
             birth_date = coalesce(carga.data(d ->> 'data_nascimento'), birth_date), gender = coalesce(upper(carga.txt(d, 'sexo')), gender),
             email = coalesce(lower(carga.txt(d, 'email')), email), primary_phone = coalesce(iara.fmt_tel(carga.txt(d, 'telefone')), primary_phone),
             whatsapp_phone = coalesce(iara.fmt_tel(carga.txt(d, 'whatsapp')), whatsapp_phone),
             marital_status = coalesce(carga.txt(d, 'estado_civil'), marital_status), education_level = coalesce(carga.txt(d, 'escolaridade'), education_level),
             occupation = coalesce(carga.txt(d, 'ocupacao'), occupation), family_income = coalesce(carga.num(carga.txt(d, 'renda_familiar')), family_income),
             cadunico_status = coalesce(carga.sim(carga.txt(d, 'cadunico')), cadunico_status),
             single_mother = coalesce(carga.sim(carga.txt(d, 'mae_solo')), single_mother),
             household_size = coalesce(carga.txt(d, 'pessoas_domicilio')::smallint, household_size),
             address_id = coalesce(v_end, address_id), is_demo = false, updated_at = now()
      where id = g.id;
      acao := 'ATUALIZADO'; destino := g.id::text;
    else
      insert into iara.guardians (tenant_id, full_name, cpf, nis, rg, birth_date, gender, email, primary_phone, whatsapp_phone, marital_status,
                                  education_level, occupation, family_income, cadunico_status, single_mother, household_size, address_id, is_demo)
      values (1, carga.txt(d, 'nome'), iara.fmt_cpf(carga.txt(d, 'cpf')), iara.digitos(carga.txt(d, 'nis')), carga.txt(d, 'rg'),
              carga.data(d ->> 'data_nascimento'), upper(carga.txt(d, 'sexo')), lower(carga.txt(d, 'email')),
              iara.fmt_tel(carga.txt(d, 'telefone')), iara.fmt_tel(carga.txt(d, 'whatsapp')), carga.txt(d, 'estado_civil'),
              carga.txt(d, 'escolaridade'), carga.txt(d, 'ocupacao'), carga.num(carga.txt(d, 'renda_familiar')),
              coalesce(carga.sim(carga.txt(d, 'cadunico')), false), coalesce(carga.sim(carga.txt(d, 'mae_solo')), false),
              carga.txt(d, 'pessoas_domicilio')::smallint, v_end, false)
      returning id into v_uuid;
      acao := 'CRIADO'; destino := v_uuid::text; antes := jsonb_build_object('_endereco_novo', v_end);
    end if;

  when 'ALUNOS' then
    v_uuid := carga.ref('ALUNOS', carga.txt(d, 'codigo_aluno'))::uuid;
    v_end := carga.endereco_novo(d, p_lote.origem);
    select * into s from iara.students where id = v_uuid;
    if s.id is not null then
      antes := to_jsonb(s) || jsonb_build_object('_endereco_novo', v_end);
      update iara.students set full_name = carga.txt(d, 'nome'), social_name = coalesce(carga.txt(d, 'nome_social'), social_name),
             birth_date = carga.data(d ->> 'data_nascimento'), gender = coalesce(upper(carga.txt(d, 'sexo')), gender),
             race_color = coalesce(upper(carga.txt(d, 'cor_raca')), race_color), cpf = coalesce(iara.fmt_cpf(carga.txt(d, 'cpf')), cpf),
             nis = coalesce(iara.digitos(carga.txt(d, 'nis')), nis), birth_certificate = coalesce(carga.txt(d, 'certidao_nascimento'), birth_certificate),
             sus_card = coalesce(carga.txt(d, 'cartao_sus'), sus_card), inep_id = coalesce(carga.txt(d, 'codigo_inep_aluno'), inep_id),
             nationality = coalesce(upper(carga.txt(d, 'nacionalidade')), nationality),
             parent1_name = coalesce(carga.txt(d, 'nome_mae'), parent1_name), parent2_name = coalesce(carga.txt(d, 'nome_pai'), parent2_name),
             transport_need = coalesce(carga.sim(carga.txt(d, 'transporte')), transport_need),
             aee_status = coalesce(carga.sim(carga.txt(d, 'aee')), aee_status), address_id = coalesce(v_end, address_id),
             is_demo = false, updated_at = now()
      where id = s.id;
      acao := 'ATUALIZADO'; destino := s.id::text;
    else
      insert into iara.students (tenant_id, full_name, social_name, birth_date, gender, student_registry_number, status, address_id,
                                 transport_need, aee_status, cpf, nis, birth_certificate, race_color, nationality, sus_card, inep_id,
                                 parent1_name, parent2_name, is_demo)
      values (1, carga.txt(d, 'nome'), carga.txt(d, 'nome_social'), carga.data(d ->> 'data_nascimento'), upper(carga.txt(d, 'sexo')),
              carga.txt(d, 'codigo_aluno'), 'SEM_VINCULO', v_end, coalesce(carga.sim(carga.txt(d, 'transporte')), false),
              coalesce(carga.sim(carga.txt(d, 'aee')), false), iara.fmt_cpf(carga.txt(d, 'cpf')), iara.digitos(carga.txt(d, 'nis')),
              carga.txt(d, 'certidao_nascimento'), upper(carga.txt(d, 'cor_raca')), coalesce(upper(carga.txt(d, 'nacionalidade')), 'BRASILEIRA'),
              carga.txt(d, 'cartao_sus'), carga.txt(d, 'codigo_inep_aluno'), carga.txt(d, 'nome_mae'), carga.txt(d, 'nome_pai'), false)
      returning id into v_uuid;
      acao := 'CRIADO'; destino := v_uuid::text; antes := jsonb_build_object('_endereco_novo', v_end);
    end if;

  when 'VINCULOS' then
    v_aluno := carga.ref('ALUNOS', carga.txt(d, 'codigo_aluno'))::uuid;
    v_resp := carga.ref('RESPONSAVEIS', carga.txt(d, 'codigo_responsavel'))::uuid;
    select * into sg from iara.student_guardians where student_id = v_aluno and guardian_id = v_resp;
    if sg.student_id is not null then
      antes := to_jsonb(sg);
      update iara.student_guardians set relationship = upper(carga.txt(d, 'parentesco')),
             is_primary = coalesce(carga.sim(carga.txt(d, 'principal')), is_primary),
             can_pick_up = coalesce(carga.sim(carga.txt(d, 'pode_buscar')), can_pick_up),
             can_receive_notifications = coalesce(carga.sim(carga.txt(d, 'recebe_avisos')), can_receive_notifications),
             legal_authority_status = coalesce(upper(carga.txt(d, 'situacao_legal')), legal_authority_status),
             start_date = coalesce(carga.data(d ->> 'inicio'), start_date), end_date = carga.data(d ->> 'fim')
      where student_id = v_aluno and guardian_id = v_resp;
      acao := 'ATUALIZADO';
    else
      insert into iara.student_guardians (student_id, guardian_id, relationship, is_primary, can_pick_up, can_receive_notifications,
                                          legal_authority_status, start_date, end_date)
      values (v_aluno, v_resp, upper(carga.txt(d, 'parentesco')), coalesce(carga.sim(carga.txt(d, 'principal')), false),
              coalesce(carga.sim(carga.txt(d, 'pode_buscar')), true), coalesce(carga.sim(carga.txt(d, 'recebe_avisos')), true),
              coalesce(upper(carga.txt(d, 'situacao_legal')), 'DECLARADO'), coalesce(carga.data(d ->> 'inicio'), current_date),
              carga.data(d ->> 'fim'));
      acao := 'CRIADO';
    end if;
    destino := v_aluno::text || ':' || v_resp::text;

  when 'MATRICULAS' then
    v_aluno := carga.ref('ALUNOS', carga.txt(d, 'codigo_aluno'))::uuid;
    select * into v_turma from iara.classes where id = carga.ref('TURMAS', carga.txt(d, 'codigo_turma'))::uuid;
    v_status := case upper(carga.txt(d, 'situacao'))
      when 'ATIVA' then 'ACTIVE' when 'PRE_MATRICULA' then 'PRE_ENROLLMENT' when 'TRANSFERENCIA_PENDENTE' then 'TRANSFER_PENDING'
      when 'TRANSFERIDA' then 'TRANSFERRED' when 'CANCELADA' then 'CANCELLED' when 'CONCLUIDA' then 'COMPLETED' else 'INACTIVE' end;
    v_uuid := carga.ref('MATRICULAS', carga.txt(d, 'codigo_matricula'))::uuid;
    select * into e from iara.enrollments where id = v_uuid;
    if e.id is not null then
      antes := to_jsonb(e) || jsonb_build_object('_aluno', (select to_jsonb(x) from iara.students x where id = v_aluno));
      update iara.enrollments set student_id = v_aluno, class_id = v_turma.id, unit_id = v_turma.unit_id, school_year = v_turma.school_year,
             status = v_status, enrollment_date = coalesce(carga.data(d ->> 'data_matricula'), enrollment_date),
             start_date = coalesce(carga.data(d ->> 'inicio'), start_date), end_date = carga.data(d ->> 'fim'),
             entry_type = coalesce(upper(carga.txt(d, 'tipo_entrada')), entry_type), is_demo = false
      where id = e.id;
      acao := 'ATUALIZADO'; destino := e.id::text;
    else
      antes := jsonb_build_object('_aluno', (select to_jsonb(x) from iara.students x where id = v_aluno));
      insert into iara.enrollments (tenant_id, student_id, class_id, unit_id, school_year, status, enrollment_date, start_date, end_date,
                                    entry_type, is_demo)
      values (1, v_aluno, v_turma.id, v_turma.unit_id, v_turma.school_year, v_status, coalesce(carga.data(d ->> 'data_matricula'), p_lote.data_referencia),
              carga.data(d ->> 'inicio'), carga.data(d ->> 'fim'), coalesce(upper(carga.txt(d, 'tipo_entrada')), 'NOVA'), false)
      returning id into v_uuid;
      acao := 'CRIADO'; destino := v_uuid::text;
    end if;
    if v_status = 'ACTIVE' then
      update iara.students set current_enrollment_id = destino::uuid, status = 'MATRICULADO' where id = v_aluno;
    end if;

  when 'FILA' then
    v_aluno := carga.ref('ALUNOS', carga.txt(d, 'codigo_aluno'))::uuid;
    v_unit := carga.ref('UNIDADES', carga.txt(d, 'codigo_unidade'))::int;
    v_g := carga.serie(carga.txt(d, 'serie'));
    select a.territory_id into v_terr from iara.students x join iara.addresses a on a.id = x.address_id where x.id = v_aluno;
    v_status := case upper(coalesce(carga.txt(d, 'situacao'), 'AGUARDANDO')) when 'SUSPENSA' then 'SUSPENDED' else 'WAITING' end;
    v_uuid := carga.ref('FILA', carga.txt(d, 'codigo_inscricao'))::uuid;
    if v_uuid is not null and exists (select 1 from iara.waiting_list_entries where id = v_uuid) then
      select to_jsonb(x) into antes from iara.waiting_list_entries x where id = v_uuid;
      update iara.waiting_list_entries set student_id = v_aluno, stage_id = v_g.stage_id, grade_level_id = v_g.id, preferred_unit_id = v_unit,
             territory_id = v_terr, preferred_shift = upper(carga.txt(d, 'turno_preferido')),
             full_time_requested = coalesce(carga.sim(carga.txt(d, 'integral')), false),
             demand_category = coalesce(upper(carga.txt(d, 'categoria')), 'SEM_ATENDIMENTO'), status = v_status,
             entered_at = carga.data_hora(d ->> 'data_solicitacao'), is_demo = false, updated_at = now()
      where id = v_uuid;
      acao := 'ATUALIZADO'; destino := v_uuid::text;
    else
      antes := jsonb_build_object('_aluno', (select to_jsonb(x) from iara.students x where id = v_aluno));
      insert into iara.waiting_list_entries (tenant_id, student_id, stage_id, grade_level_id, preferred_unit_id, territory_id, preferred_shift,
                                             full_time_requested, demand_category, status, entered_at, is_demo)
      values (1, v_aluno, v_g.stage_id, v_g.id, v_unit, v_terr, upper(carga.txt(d, 'turno_preferido')),
              coalesce(carga.sim(carga.txt(d, 'integral')), false), coalesce(upper(carga.txt(d, 'categoria')), 'SEM_ATENDIMENTO'),
              v_status, carga.data_hora(d ->> 'data_solicitacao'), false)
      returning id into v_uuid;
      acao := 'CRIADO'; destino := v_uuid::text;
    end if;
    perform iara.compute_queue_priority(v_uuid);
    update iara.students set status = 'AGUARDANDO_VAGA' where id = v_aluno and status in ('SEM_VINCULO');
  end case;
end $$;

-- api.pessoal_lista (de 20261003005000_ocorrencias_agenda.sql)
create or replace function api.pessoal_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := iara.pessoal_escopo(nullif(p ->> 'unit_id', '')::int);
  v_q text := nullif(iara.norm(btrim(coalesce(p ->> 'q', ''))), '');
  v_funcao text := nullif(p ->> 'funcao', '');
  v_sit text := nullif(p ->> 'situacao', '');
  v_vinc text := nullif(p ->> 'vinculo', '');
  v_area text := nullif(p ->> 'area', '');
  v_carga text := nullif(p ->> 'carga', '');
  v_regiao integer := nullif(p ->> 'regiao_id', '')::int;
  v_ord text := coalesce(nullif(p ->> 'ordem', ''), 'nome');
  v_lim integer := least(greatest(coalesce(nullif(p ->> 'limite', '')::int, 100), 1), 300);
  v_off integer := greatest(coalesce(nullif(p ->> 'offset', '')::int, 0), 0);
begin
  perform iara.require_perm('pessoal.read');
  return (with base as materialized (
      select c.*, u.short_name unidade, u.macro_territory_id regiao_id
      from iara.v_carga_servidor c left join iara.education_units u on u.id = c.unit_id
      where (v_unit is null or c.unit_id = v_unit)),
    filt as (
      select b.* from base b
      where (v_funcao is null or b.role = v_funcao)
        and (v_sit is null or b.situacao = v_sit)
        and (v_vinc is null or b.bond = v_vinc)
        and (v_area is null or b.area_atuacao = v_area)
        and (v_regiao is null or b.regiao_id = v_regiao)
        and (v_carga is null or (v_carga = 'EXCESSO' and b.disponivel < 0) or (v_carga = 'LIVRE' and b.disponivel > 0 and b.atribuidas > 0)
             or (v_carga = 'SEM_TURMA' and b.atribuidas = 0) or (v_carga = 'COMPLETA' and b.disponivel = 0 and b.capacidade > 0))
        and (v_q is null or iara.norm(b.full_name) like '%' || v_q || '%' or b.matricula_funcional = btrim(p ->> 'q')
             or iara.norm(coalesce(b.cargo, '')) like '%' || v_q || '%'))
    select jsonb_build_object(
      'unidade', (select jsonb_build_object('id', id, 'name', name) from iara.education_units where id = v_unit),
      'total', (select count(*) from filt),
      'totais', (select coalesce(jsonb_object_agg(role, n), '{}') from (select role, count(*) n from base group by 1) z),
      'situacao', (select coalesce(jsonb_object_agg(situacao, n), '{}') from (select situacao, count(*) n from base group by 1) z),
      'opcoes', jsonb_build_object(
        'vinculos', (select coalesce(jsonb_agg(distinct bond), '[]') from base where bond is not null),
        'areas', (select coalesce(jsonb_agg(distinct area_atuacao), '[]') from base where area_atuacao is not null),
        'regioes', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'nome', t.name) order by t.name), '[]')
                    from iara.territories t where t.kind = 'AREA_PONDERACAO')),
      'itens', (select coalesce(jsonb_agg(jsonb_build_object('id', c.staff_id, 'nome', c.full_name, 'matricula', c.matricula_funcional, 'funcao', c.role,
                  'cargo', c.cargo, 'area', c.area_atuacao, 'vinculo', c.bond, 'ch', c.ch, 'capacidade', c.capacidade, 'atribuidas', c.atribuidas,
                  'disponivel', c.disponivel, 'turmas', c.turmas, 'situacao', c.situacao, 'unidade', c.unidade, 'unit_id', c.unit_id)
                  order by c.ord), '[]')
                from (select f.*, row_number() over (order by case when v_ord = 'saldo' then f.disponivel end, case when v_ord = 'unidade' then f.unidade end,
                                                     iara.norm(f.full_name), f.staff_id) ord
                      from filt f order by ord limit v_lim offset v_off) c)));
end $$;

-- iara.demo_gerar_busca_ativa (de 20261003006100_busca_ativa_demo.sql)
create or replace function iara.demo_gerar_busca_ativa() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_t0 timestamptz := now();  -- início da transação: o que for criado aqui tem created_at >= v_t0
  v_ate date := iara.hoje_local() - 1;
  v_de date;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.encaminhamentos where is_demo;
  delete from iara.busca_ativa_casos where is_demo;
  delete from iara.frequencia_tarefas where is_demo;
  delete from iara.frequencia_contatos where is_demo;
  delete from iara.frequencia_ausencias where is_demo;
  delete from iara.frequencia_afastamentos where is_demo;
  delete from iara.orgaos_destinatarios where is_demo;
  select min(d) into v_de from (select distinct r.data d from iara.frequencia_registros r where r.is_demo and r.data <= v_ate order by r.data desc limit 10) z;

  -- órgãos fictícios (protocolo eletrônico de demonstração), já verificados. Um conselho tutelar para as 29 áreas de
  -- ponderação: a competência real de cada conselho é cadastrada pela SEDUC como lista de áreas.
  insert into iara.orgaos_destinatarios (nome, tipo, competencia, territorio_ids, canal, endereco_canal, verificado, verificado_por_label, verificado_em, is_demo)
  select 'Conselho Tutelar de Maringá (demonstração)', 'CONSELHO_TUTELAR', 'Proteção de crianças e adolescentes do município',
         array(select t.id from iara.territories t where t.kind = 'AREA_PONDERACAO' order by t.sort), 'PROTOCOLO_ELETRONICO',
         'Protocolo eletrônico (demonstração)', true, 'SEDUC (demonstração)', now() - interval '30 days', true;
  insert into iara.orgaos_destinatarios (nome, tipo, competencia, canal, endereco_canal, verificado, verificado_por_label, verificado_em, is_demo) values
    ('CRAS de referência (demonstração)', 'CRAS', 'Assistência social básica: acompanhamento familiar, benefícios', 'PROTOCOLO_ELETRONICO', 'Protocolo eletrônico (demonstração)', true, 'SEDUC (demonstração)', now() - interval '30 days', true),
    ('CREAS (demonstração)', 'CREAS', 'Proteção social especial: violação de direitos', 'PROTOCOLO_ELETRONICO', 'Protocolo eletrônico (demonstração)', true, 'SEDUC (demonstração)', now() - interval '30 days', true),
    ('Unidade Básica de Saúde de referência (demonstração)', 'SAUDE', 'Atenção básica à saúde da criança', 'PROTOCOLO_ELETRONICO', 'Protocolo eletrônico (demonstração)', true, 'SEDUC (demonstração)', now() - interval '30 days', true),
    ('Gerência de Transporte Escolar (demonstração)', 'TRANSPORTE_ESCOLAR', 'Pedido e ajuste de rota', 'INTEGRACAO', 'Módulo de transporte do IARA', true, 'SEDUC (demonstração)', now() - interval '30 days', true),
    ('Serviço de convivência (cadastro pendente de verificação)', 'ASSISTENCIA_SOCIAL', 'Contraturno e convivência', 'EMAIL_INSTITUCIONAL', null, false, null, null, true);

  -- ausências dos últimos 10 dias letivos (situação e motivo pela “família” fictícia)
  insert into iara.frequencia_ausencias (student_id, class_id, unit_id, etapa, data, situacao, motivo, motivo_texto, respondido_em, respondido_canal, nivel, created_at, atualizado_em, is_demo)
  select f.student_id, r.class_id, c.unit_id, iara.etapa_freq(gl.code), r.data,
         case when f.tipo = 'FALTA_JUSTIFICADA' then 'JUSTIFICATIVA_ACEITA' when h.h < 58 then 'MOTIVO_INFORMADO' when h.h < 64 then 'JUSTIFICATIVA_EM_ANALISE'
              when h.h < 72 then 'INJUSTIFICADA' when h.h < 74 then 'AFASTAMENTO' else 'AGUARDANDO_ESCLARECIMENTO' end,
         case when f.tipo = 'FALTA_JUSTIFICADA' then coalesce(case when f.justificativa ilike 'Transporte%' then 'TRANSPORTE' end, 'SAUDE')
              when h.h < 58 then (array['SAUDE', 'SAUDE', 'SAUDE', 'SAUDE', 'SAUDE', 'SAUDE', 'SAUDE', 'SAUDE', 'SAUDE', 'CONSULTA', 'CONSULTA', 'CONSULTA',
                                        'TRANSPORTE', 'DIFICULDADE_FAMILIAR', 'DIFICULDADE_FAMILIAR', 'RECUSA', 'OUTRO', 'OUTRO', 'OUTRO', 'ESTA_NA_ESCOLA'])[1 + h.h % 20] end,
         case when h.h < 58 and h.h % 20 >= 16 and h.h % 20 <= 18 then (array['Viagem de família', 'Choveu muito e não conseguimos ir', 'Problema com a documentação'])[1 + h.h % 3] end,
         case when h.h < 64 then r.data + interval '14 hours' + make_interval(mins => h.h * 7 % 300) end,
         case when h.h < 64 then (array['WHATSAPP', 'WHATSAPP', 'PORTAL'])[1 + h.h % 3] end,
         case when h.h >= 74 and r.data <= v_ate - 2 then 3 when h.h >= 74 and r.data <= v_ate - 1 then 2 else 1 end,
         r.data + interval '10 hours', r.data + interval '15 hours', true
  from iara.frequencia_registros r join iara.frequencia_faltas f on f.registro_id = r.id
  join iara.classes c on c.id = r.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
  cross join lateral (select abs(hashtext(f.student_id::text || r.data::text || 'ba')) % 100 h) h
  where r.is_demo and r.data between v_de and v_ate
  on conflict (student_id, data) do nothing;
  -- afastamentos acompanhados (os poucos marcados acima)
  insert into iara.frequencia_afastamentos (student_id, inicio, fim, motivo, acompanhar_em, registrado_por_label, is_demo)
  select a.student_id, a.data, a.data + 4, 'Afastamento acompanhado pela escola (motivo registrado sem diagnóstico)', a.data + 5, 'Secretaria da unidade (demonstração)', true
  from iara.frequencia_ausencias a where a.is_demo and a.situacao = 'AFASTAMENTO';

  -- primeiro contato: um por responsável e dia
  insert into iara.frequencia_contatos (guardian_id, student_ids, ausencia_ids, unit_id, data_ref, nivel, canal, texto, status, agendada_para, enviada_em, falha_motivo, chave, created_at, is_demo)
  select z.g, z.alunos, z.ids, z.unit_id, z.data, '1', 'WHATSAPP',
         iara.modelo_msg('NIVEL_1', jsonb_build_object('nome_responsavel', split_part(gu.full_name, ' ', 1), 'nome_aluno', z.nomes, 'data', to_char(z.data, 'DD/MM'), 'unidade', z.unidade)),
         case when z.falha then 'FALHA' when z.respondeu then 'RESPONDIDA' else 'SIMULADA' end,
         z.data + interval '10 hours 20 minutes', z.data + interval '10 hours 21 minutes', case when z.falha then 'Número sem WhatsApp (demonstração)' end,
         'n1:' || z.g || ':' || z.data, z.data + interval '10 hours 20 minutes', true
  from (select iara.responsavel_contato(a.student_id) g, a.data, array_agg(a.student_id) alunos, array_agg(a.id) ids, min(a.unit_id) unit_id,
               string_agg(split_part(s.full_name, ' ', 1), ' e ') nomes, min(u.short_name) unidade, bool_or(a.respondido_em is not null) respondeu,
               abs(hashtext(min(a.id::text))) % 100 < 4 and not bool_or(a.respondido_em is not null) falha
        from iara.frequencia_ausencias a join iara.students s on s.id = a.student_id join iara.education_units u on u.id = a.unit_id
        where a.is_demo and a.situacao not in ('JUSTIFICATIVA_ACEITA', 'AFASTAMENTO')
        group by 1, 2) z join iara.guardians gu on gu.id = z.g
  where z.g is not null
  on conflict (chave) do nothing;
  -- lembretes (nível 2) e atendimento (nível 3) para quem não respondeu
  insert into iara.frequencia_contatos (guardian_id, student_ids, ausencia_ids, unit_id, data_ref, nivel, canal, texto, status, agendada_para, enviada_em, chave, created_at, is_demo)
  select iara.responsavel_contato(a.student_id), array[a.student_id], array[a.id], a.unit_id, a.data, n.nivel, 'WHATSAPP',
         iara.modelo_msg('NIVEL_' || n.nivel, jsonb_build_object('nome_responsavel', split_part(gu.full_name, ' ', 1), 'nome_aluno', split_part(s.full_name, ' ', 1),
           'data', to_char(a.data, 'DD/MM'), 'unidade', u.short_name)), 'SIMULADA',
         a.data + make_interval(days => n.dias, hours => 9), a.data + make_interval(days => n.dias, hours => 9), 'n' || n.nivel || 'm:' || a.student_id || ':' || a.data,
         a.data + make_interval(days => n.dias, hours => 9), true
  from iara.frequencia_ausencias a join iara.students s on s.id = a.student_id join iara.education_units u on u.id = a.unit_id
  join iara.guardians gu on gu.id = iara.responsavel_contato(a.student_id)
  cross join (values ('2', 1), ('3', 2)) n(nivel, dias)
  where a.is_demo and a.situacao = 'AGUARDANDO_ESCLARECIMENTO' and a.nivel >= n.nivel::int
  on conflict (chave) do nothing;

  -- tarefas: ligar (nível 2), reunião (nível 3), conferir telefone (falha), apoio (motivos), conferir presença
  insert into iara.frequencia_tarefas (student_id, ausencia_id, unit_id, tipo, prioridade, destino, descricao, prazo, situacao, sucesso, resultado, concluida_por_label, concluida_em, chave, created_at, is_demo)
  select a.student_id, a.id, a.unit_id, case when a.nivel >= 3 then 'REUNIAO' else 'LIGAR' end, case when a.nivel >= 3 then 'ALTA' else 'NORMAL' end,
         case when a.nivel >= 3 then 'EQUIPE_PEDAGOGICA' else 'SECRETARIA_UNIDADE' end,
         case when a.nivel >= 3 then 'Sem resposta da família ou ausências seguidas: telefonar, usar o contato alternativo ou marcar reunião (com a direção ciente).'
              else 'Família sem resposta ao primeiro contato: ligar para o responsável.' end,
         a.data + 2, case when abs(hashtext(a.id::text || 't')) % 3 = 0 then 'CONCLUIDA' else 'ABERTA' end,
         case when abs(hashtext(a.id::text || 't')) % 3 = 0 then abs(hashtext(a.id::text)) % 2 = 0 end,
         case when abs(hashtext(a.id::text || 't')) % 3 = 0 then (array['Ligação atendida: a criança estava doente e volta amanhã.', 'Telefone não atende; deixado recado com a avó.'])[1 + abs(hashtext(a.id::text)) % 2] end,
         case when abs(hashtext(a.id::text || 't')) % 3 = 0 then 'Secretaria da unidade (demonstração)' end,
         case when abs(hashtext(a.id::text || 't')) % 3 = 0 then least(a.data + interval '1 day 15 hours', now() - interval '1 hour') end,
         'n' || case when a.nivel >= 3 then 3 else 2 end || ':' || a.student_id || ':' || a.data, a.data + interval '1 day', true
  from iara.frequencia_ausencias a where a.is_demo and a.situacao = 'AGUARDANDO_ESCLARECIMENTO' and a.nivel >= 2
  on conflict (chave) do nothing;
  insert into iara.frequencia_tarefas (student_id, unit_id, tipo, prioridade, destino, descricao, prazo, chave, created_at, is_demo)
  select k.student_ids[1], k.unit_id, 'CONFERIR_TELEFONE', 'ALTA', 'SECRETARIA_UNIDADE', 'A mensagem não foi entregue (número sem WhatsApp). Conferir o telefone no cadastro e usar o contato alternativo autorizado.',
         k.data_ref + 1, 'tel:' || k.id, k.created_at, true
  from iara.frequencia_contatos k where k.is_demo and k.status = 'FALHA'
  on conflict (chave) do nothing;
  insert into iara.frequencia_tarefas (student_id, ausencia_id, unit_id, tipo, prioridade, destino, descricao, prazo, situacao, resultado, concluida_por_label, concluida_em, chave, created_at, is_demo)
  select a.student_id, a.id, a.unit_id, case when a.motivo = 'ESTA_NA_ESCOLA' then 'CONFERIR_PRESENCA' else 'APOIO_SETOR' end, 'ALTA',
         case a.motivo when 'TRANSPORTE' then 'TRANSPORTE' when 'ESTA_NA_ESCOLA' then 'SECRETARIA_UNIDADE' else 'EQUIPE_PEDAGOGICA' end,
         case a.motivo when 'TRANSPORTE' then 'A família informou problema de transporte: verificar a rota ou o pedido de transporte escolar.'
                       when 'ESTA_NA_ESCOLA' then 'A família diz que a criança estava na escola: conferir a chamada com o professor.'
                       when 'RECUSA' then 'A família relata recusa ou dificuldade para frequentar a escola: acolher e planejar o apoio (sem presumir negligência).'
                       else 'A família relata dificuldade: acolher e avaliar apoio da rede (assistência social), sem presumir negligência.' end,
         a.data + 2, case when a.data <= v_ate - 4 then 'CONCLUIDA' else 'ABERTA' end,
         case when a.data <= v_ate - 4 then 'Família acolhida; combinado acompanhamento quinzenal.' end,
         case when a.data <= v_ate - 4 then 'Equipe pedagógica (demonstração)' end, case when a.data <= v_ate - 4 then a.data + interval '3 days' end,
         'apoio:' || a.id, a.data + interval '15 hours', true
  from iara.frequencia_ausencias a where a.is_demo and a.motivo in ('TRANSPORTE', 'DIFICULDADE_FAMILIAR', 'RECUSA', 'ESTA_NA_ESCOLA') and a.situacao = 'MOTIVO_INFORMADO'
  on conflict (chave) do nothing;

  -- casos de busca ativa: 3+ ausências sem esclarecimento ou injustificadas na janela; o caso abre na 3ª ausência e só tem
  -- andamento (contato, reunião, retorno) que já caberia no tempo decorrido
  insert into iara.busca_ativa_casos (student_id, unit_id, etapa, origem, motivo_abertura, situacao, responsavel_label, acompanhar_em, aberto_em, is_demo)
  select z.student_id, z.unit_id, z.etapa, case when z.n >= 4 then 'CONTATOS_SEM_SUCESSO' else 'PERSISTENCIA' end,
         format('%s ausências sem esclarecimento nos últimos dias letivos; contatos sem sucesso.', z.n),
         case when z.ab > now() - interval '1 day' then 'ABERTO'
              when z.ab > now() - interval '5 days' then (array['ABERTO', 'EM_ACOMPANHAMENTO', 'EM_ACOMPANHAMENTO', 'EM_ACOMPANHAMENTO'])[1 + abs(hashtext(z.student_id::text)) % 4]
              else (array['ABERTO', 'EM_ACOMPANHAMENTO', 'EM_ACOMPANHAMENTO', 'RETORNOU'])[1 + abs(hashtext(z.student_id::text)) % 4] end,
         'Coordenação pedagógica (demonstração)', v_ate + 3, z.ab, true
  from (select student_id, min(unit_id) unit_id, min(etapa) etapa, count(*) n, (array_agg(data order by data))[3] + interval '16 hours' ab
        from iara.frequencia_ausencias
        where is_demo and situacao in ('AGUARDANDO_ESCLARECIMENTO', 'INJUSTIFICADA') group by 1 having count(*) >= 3) z
  on conflict do nothing;
  insert into iara.busca_ativa_eventos (caso_id, tipo, texto, autor_label, created_at, is_demo)
  select k.id, e.tipo, e.texto, e.autor, k.aberto_em + e.dt, true
  from iara.busca_ativa_casos k
  cross join lateral (values ('ABERTURA', 'Caso aberto pela regra de persistência (parâmetros vigentes).', 'IARA (regra automática)', interval '0'),
                             ('CONTATO_TELEFONE', 'Ligação para o responsável: sem resposta; tentado o contato alternativo.', 'Secretaria da unidade (demonstração)', interval '1 day'),
                             ('REUNIAO', 'Reunião com a família: dificuldade de rotina pela manhã; combinado acompanhamento semanal.', 'Coordenação pedagógica (demonstração)', interval '3 days')) e(tipo, texto, autor, dt)
  where k.is_demo and (e.tipo = 'ABERTURA' or k.situacao <> 'ABERTO') and k.aberto_em + e.dt <= now();
  insert into iara.busca_ativa_eventos (caso_id, tipo, texto, autor_label, created_at, is_demo)
  select k.id, 'RETORNO', 'O aluno voltou a frequentar; o caso segue em acompanhamento até a equipe encerrar.', 'Coordenação pedagógica (demonstração)', k.aberto_em + interval '5 days', true
  from iara.busca_ativa_casos k where k.is_demo and k.situacao = 'RETORNOU';
  -- alguns encaminhamentos à rede de apoio
  insert into iara.encaminhamentos (caso_id, student_id, unit_id, tipo, orgao_id, servico, necessidade, fundamento, obrigatorio, conteudo, situacao, comunicar_familia, criado_por_label,
                                    created_at, aprovado_por_label, aprovado_em, enviado_em, enviado_canal, protocolo, is_demo)
  select k.id, k.student_id, k.unit_id, 'REDE_APOIO', (select id from iara.orgaos_destinatarios where is_demo and tipo = 'CRAS' limit 1), 'CRAS de referência',
         'acompanhamento familiar e acesso a benefícios', 'Necessidade de apoio social identificada no contato com a família', false,
         iara.ba_expediente(k.student_id, k.id, 'Necessidade de apoio social identificada no contato com a família'),
         case when abs(hashtext(k.id::text)) % 3 = 0 then 'AGUARDANDO_APROVACAO' else 'ENVIADO' end, true, 'Coordenação pedagógica (demonstração)',
         k.aberto_em + interval '4 days', case when abs(hashtext(k.id::text)) % 3 <> 0 then 'Direção (demonstração)' end,
         case when abs(hashtext(k.id::text)) % 3 <> 0 then k.aberto_em + interval '4 days 3 hours' end,
         case when abs(hashtext(k.id::text)) % 3 <> 0 then k.aberto_em + interval '4 days 4 hours' end,
         case when abs(hashtext(k.id::text)) % 3 <> 0 then 'PROTOCOLO_ELETRONICO' end,
         case when abs(hashtext(k.id::text)) % 3 <> 0 then 'DEMO-' || (abs(hashtext(k.id::text)) % 90000 + 10000) end, true
  from iara.busca_ativa_casos k where k.is_demo and abs(hashtext(k.id::text || 'rede')) % 100 < 30 and k.aberto_em + interval '4 days 4 hours' <= now();

  -- casos urgentes (relato com possível risco) para mostrar o fluxo prioritário — nunca com a família da demonstração
  insert into iara.busca_ativa_casos (student_id, unit_id, etapa, origem, motivo_abertura, urgente, situacao, acompanhar_em, aberto_em, is_demo)
  select a.student_id, a.unit_id, a.etapa, 'RISCO', 'Relato da família com possível indício de risco — avaliação humana imediata.', true, 'ABERTO', iara.hoje_local(), a.data + interval '15 hours', true
  from (select distinct on (a.unit_id) a.* from iara.frequencia_ausencias a
        where a.is_demo and a.situacao = 'MOTIVO_INFORMADO' and a.motivo = 'DIFICULDADE_FAMILIAR'
          and a.student_id is distinct from nullif(iara.setting('demo_student_ana'), '')::uuid
          and not exists (select 1 from iara.busca_ativa_casos k where k.student_id = a.student_id and k.situacao <> 'ENCERRADO')
        order by a.unit_id, a.data desc) a
  where abs(hashtext(a.unit_id::text || 'risco')) % 100 < 4;
  insert into iara.frequencia_tarefas (student_id, caso_id, unit_id, tipo, prioridade, destino, descricao, prazo, obrigatoria, chave, created_at, is_demo)
  select k.student_id, k.id, k.unit_id, 'AVALIAR_RISCO', 'URGENTE', 'DIRECAO',
         'Relato com possível indício de risco: avaliação imediata pela equipe autorizada e, se for o caso, comunicação ao Conselho Tutelar.', iara.hoje_local(), true, 'risco:' || k.id, k.aberto_em, true
  from iara.busca_ativa_casos k where k.is_demo and k.origem = 'RISCO';

  -- comunicações legais (30% do limite de faltas): a maioria já enviada; parte aguardando aprovação ou envio
  perform iara.busca_ativa_limite_legal(null);
  update iara.encaminhamentos set is_demo = true where created_at >= v_t0 and not is_demo;
  update iara.frequencia_tarefas set is_demo = true where created_at >= v_t0 and not is_demo;
  update iara.encaminhamentos e set situacao = x.sit, aprovado_por_label = case when x.sit <> 'AGUARDANDO_APROVACAO' then 'Direção (demonstração)' end,
         aprovado_em = case when x.sit <> 'AGUARDANDO_APROVACAO' then now() - interval '6 days' end,
         enviado_em = case when x.sit in ('ENVIADO', 'RECEBIDO') then now() - interval '5 days' end,
         enviado_canal = case when x.sit in ('ENVIADO', 'RECEBIDO') then 'PROTOCOLO_ELETRONICO' end,
         protocolo = case when x.sit in ('ENVIADO', 'RECEBIDO') then 'CT-DEMO-' || (abs(hashtext(e.id::text)) % 90000 + 10000) end,
         recebido_em = case when x.sit = 'RECEBIDO' then now() - interval '4 days' end, created_at = now() - interval '8 days'
  from (select id, case when abs(hashtext(id::text)) % 100 < 45 then 'RECEBIDO' when abs(hashtext(id::text)) % 100 < 75 then 'ENVIADO'
                        when abs(hashtext(id::text)) % 100 < 90 then 'APROVADO' else 'AGUARDANDO_APROVACAO' end sit
        from iara.encaminhamentos where is_demo and tipo = 'CONSELHO_TUTELAR') x
  where e.id = x.id;
  update iara.frequencia_tarefas t set situacao = 'CONCLUIDA', sucesso = true, resultado = 'Expediente enviado — protocolo ' || e.protocolo, concluida_por_label = 'Direção (demonstração)',
         concluida_em = e.enviado_em
  from iara.encaminhamentos e where t.is_demo and t.tipo = 'NOTIFICAR_CT' and t.chave = 'ct:' || e.id and e.situacao in ('ENVIADO', 'RECEBIDO');
  update iara.frequencia_tarefas t set created_at = e.created_at from iara.encaminhamentos e where t.is_demo and t.chave = 'ct:' || e.id;
  perform set_config('iara.skip_audit', 'off', true);
  update iara.tenants set settings = settings || jsonb_build_object('ba_legal_dia', iara.hoje_local()::text) where id = 1;
  return jsonb_build_object('ausencias', (select count(*) from iara.frequencia_ausencias where is_demo), 'contatos', (select count(*) from iara.frequencia_contatos where is_demo),
    'tarefas', (select count(*) from iara.frequencia_tarefas where is_demo), 'casos', (select count(*) from iara.busca_ativa_casos where is_demo),
    'encaminhamentos', (select count(*) from iara.encaminhamentos where is_demo), 'ct', (select count(*) from iara.encaminhamentos where is_demo and tipo = 'CONSELHO_TUTELAR'));
end $$;

revoke all on function iara.aplicar_areas_ponderacao(), iara.censo_territorio(integer), iara.unidades_do_territorio(integer) from public;

commit;
