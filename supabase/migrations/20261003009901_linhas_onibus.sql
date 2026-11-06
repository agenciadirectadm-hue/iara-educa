-- IARA Educa — Linhas de ônibus da TCCC que atendem cada unidade de ensino.
-- Fonte: dados que a TCCC publica no Na Hora Maringá (https://www.nahoramaringa.com.br/pesquisa-por-linhas/),
-- carregados por scripts/seed/linhas_onibus_tccc.mjs. As tabelas guardam linhas, viagens e paradas; quais linhas atendem
-- a unidade é calculado na hora, pela coordenada dela: corrigiu a coordenada, as linhas acompanham.
-- O raio de 500 m em linha reta é o mesmo que o aplicativo oficial usa para "paradas próximas".
begin;

create table if not exists iara.onibus_linhas (
  id text primary key,                 -- identificador da linha na fonte; compõe o link oficial de horários
  codigo text not null unique,         -- como o passageiro conhece: 220, 528A, UEM
  nome text not null,
  cor text,
  atualizado_em timestamptz not null   -- quando os dados foram consultados na fonte
);

-- Uma linha tem variantes de trajeto ("Via Jd. Espanha"); nem toda variante passa em todos os horários.
create table if not exists iara.onibus_viagens (
  id text primary key,
  linha_id text not null references iara.onibus_linhas(id) on delete cascade,
  sentido integer not null,
  descricao text not null,
  partidas_dia_util integer not null default 0
);
create index if not exists onibus_viagens_linha_idx on iara.onibus_viagens(linha_id);

create table if not exists iara.onibus_paradas (
  id text primary key,
  nome text not null,
  lat double precision not null,
  lng double precision not null,
  location extensions.geography(Point, 4326) not null
);
create index if not exists onibus_paradas_location_idx on iara.onibus_paradas using gist(location);

create table if not exists iara.onibus_viagem_paradas (
  viagem_id text not null references iara.onibus_viagens(id) on delete cascade,
  ordem integer not null,
  parada_id text not null references iara.onibus_paradas(id) on delete cascade,
  primary key (viagem_id, ordem)
);
create index if not exists onibus_viagem_paradas_parada_idx on iara.onibus_viagem_paradas(parada_id);

alter table iara.onibus_linhas enable row level security;
alter table iara.onibus_viagens enable row level security;
alter table iara.onibus_paradas enable row level security;
alter table iara.onibus_viagem_paradas enable row level security;
revoke all on iara.onibus_linhas, iara.onibus_viagens, iara.onibus_paradas, iara.onibus_viagem_paradas from public, anon, authenticated;

-- Linhas com parada no raio. atendimento:
--   REGULAR: em algum sentido, ao menos metade das partidas de dia útil passa por aqui;
--   PARCIAL: passa em dia útil, mas só em parte dos horários (variante do trajeto);
--   FIM_DE_SEMANA: nenhuma partida de dia útil passa por aqui.
-- atualizado_em nulo significa "ainda não carregado": falta de dado não é falta de ônibus.
create or replace function iara.onibus_perto(p_local extensions.geography, p_raio_m integer default 500) returns jsonb
language sql stable set search_path = iara, extensions, public
as $$
  with perto as (
    select p.id, p.nome, st_distance(p.location, p_local) as dist
    from iara.onibus_paradas p
    where st_dwithin(p.location, p_local, p_raio_m)
  ), passagens as (
    select v.id as viagem_id, v.linha_id, pt.nome, pt.dist
    from perto pt
    join iara.onibus_viagem_paradas vp on vp.parada_id = pt.id
    join iara.onibus_viagens v on v.id = vp.viagem_id
  ), por_sentido as (
    select v.linha_id, v.sentido,
           sum(v.partidas_dia_util) as total,
           coalesce(sum(v.partidas_dia_util) filter (where v.id in (select viagem_id from passagens)), 0) as passam
    from iara.onibus_viagens v
    where v.linha_id in (select linha_id from passagens)
    group by v.linha_id, v.sentido
  ), cobertura as (
    select linha_id, sum(passam) as partidas, max(passam::numeric / nullif(total, 0)) as parcela
    from por_sentido group by linha_id
  ), mais_perto as (
    select distinct on (linha_id) linha_id, nome, dist from passagens order by linha_id, dist, nome
  ), itens as (
    select l.id, l.codigo, l.nome, l.cor, m.nome as parada, round(m.dist)::int as distancia_m, c.partidas::int as partidas_dia_util,
           case when c.partidas = 0 then 'FIM_DE_SEMANA' when c.parcela < 0.5 then 'PARCIAL' else 'REGULAR' end as atendimento
    from mais_perto m
    join cobertura c using (linha_id)
    join iara.onibus_linhas l on l.id = m.linha_id
  )
  select jsonb_build_object(
    'raio_m', p_raio_m,
    'atualizado_em', (select max(atualizado_em) from iara.onibus_linhas),
    'fonte', 'https://bus2.info/reports/2you/43wpt',
    'linhas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'codigo', i.codigo, 'nome', i.nome, 'cor', i.cor, 'parada', i.parada, 'distancia_m', i.distancia_m,
               'partidas_dia_util', i.partidas_dia_util, 'atendimento', i.atendimento,
               'url', 'https://bus2.info/reports/2you/43wpt?route=' || i.id)
             order by (i.atendimento = 'FIM_DE_SEMANA'), i.distancia_m, i.codigo)
      from itens i), '[]'::jsonb))
$$;
revoke execute on function iara.onibus_perto(extensions.geography, integer) from public, anon, authenticated;

-- Detalhe público da unidade: igual ao anterior, mais a chave 'onibus'.
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
    'onibus', iara.onibus_perto(u.location),
    'staff_summary', (select jsonb_build_object('total', count(*), 'by_role', jsonb_object_agg(role, n))
                      from (select role, count(*) n from iara.staff where unit_id = u.id group by role) s),
    'demo_notice', 'Turmas, capacidade, vagas, fila e profissionais nesta unidade são dados de DEMONSTRAÇÃO (estrutura de turmas do Censo 2025).'
  ) into v;
  return v;
end $$;

commit;
