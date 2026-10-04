-- IARA Educa — 006 · Regras de negócio determinísticas (vagas, faixa etária, fila, busca explicável)
-- Fórmulas (spec §15.1): vagas_fisicas = capacidade - matriculas_ativas
--                        vagas_ofertaveis = vagas_fisicas - bloqueadas - reservadas (nunca negativas)
begin;

-- ---------------------------------------------------------------------------
-- Contadores de vagas mantidos por gatilho (fonte: matrículas, bloqueios, ofertas)
-- ---------------------------------------------------------------------------
create or replace function iara.recount_class(p_class uuid) returns void
language sql security definer set search_path = iara, public
as $$
  update iara.classes c set
    active_enrollments_count = (select count(*) from iara.enrollments e where e.class_id = c.id and e.status = 'ACTIVE'),
    blocked_seats_count = coalesce((select sum(b.seats) from iara.vacancy_blocks b
                                    where b.class_id = c.id and b.released_at is null
                                      and (b.valid_until is null or b.valid_until >= current_date)), 0),
    reserved_seats_count = (select count(*) from iara.vacancy_offers o where o.class_id = c.id and o.status in ('OFFERED', 'ACCEPTED'))
  where c.id = p_class
$$;

create or replace function iara.recount_all_classes() returns void
language sql security definer set search_path = iara, public
as $$
  with e as (select class_id, count(*) n from iara.enrollments where status = 'ACTIVE' group by class_id),
       b as (select class_id, sum(seats) n from iara.vacancy_blocks
             where released_at is null and (valid_until is null or valid_until >= current_date) group by class_id),
       o as (select class_id, count(*) n from iara.vacancy_offers where status in ('OFFERED', 'ACCEPTED') group by class_id)
  update iara.classes c set
    active_enrollments_count = coalesce(e.n, 0),
    blocked_seats_count = coalesce(b.n, 0),
    reserved_seats_count = coalesce(o.n, 0)
  from iara.classes c2
  left join e on e.class_id = c2.id
  left join b on b.class_id = c2.id
  left join o on o.class_id = c2.id
  where c.id = c2.id
$$;

create or replace function iara.tg_recount_class() returns trigger
language plpgsql security definer set search_path = iara, public
as $$
begin
  if coalesce(current_setting('iara.skip_counters', true), '') = 'on' then
    return null;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform iara.recount_class(new.class_id);
  end if;
  if tg_op = 'DELETE' or (tg_op = 'UPDATE' and old.class_id is distinct from new.class_id) then
    perform iara.recount_class(old.class_id);
  end if;
  return null;
end $$;

drop trigger if exists enrollments_recount on iara.enrollments;
create trigger enrollments_recount after insert or update or delete on iara.enrollments
  for each row execute function iara.tg_recount_class();
drop trigger if exists vacancy_blocks_recount on iara.vacancy_blocks;
create trigger vacancy_blocks_recount after insert or update or delete on iara.vacancy_blocks
  for each row execute function iara.tg_recount_class();
drop trigger if exists vacancy_offers_recount on iara.vacancy_offers;
create trigger vacancy_offers_recount after insert or update or delete on iara.vacancy_offers
  for each row execute function iara.tg_recount_class();

-- ---------------------------------------------------------------------------
-- Utilitários
-- ---------------------------------------------------------------------------
create or replace function iara.point(p_lat double precision, p_lng double precision) returns extensions.geography
language sql immutable parallel safe set search_path = extensions, public
as $$ select extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography $$;

create or replace function iara.next_protocol() returns text
language sql volatile security definer set search_path = iara, public
as $$ select 'MGA-' || extract(year from now())::int || '-' || lpad(nextval('iara.protocol_seq')::text, 6, '0') $$;

create or replace function iara.setting(p_key text) returns text
language sql stable security definer set search_path = iara, public
as $$ select settings ->> p_key from iara.tenants where id = 1 $$;

create or replace function iara.school_year() returns integer
language sql stable as $$ select coalesce(iara.setting('school_year')::int, extract(year from now())::int) $$;

create or replace function iara.mask_cpf(p text) returns text
language sql immutable as $$
  select case when p is null then null else '***.' || substr(regexp_replace(p, '\D', '', 'g'), 4, 3) || '.***-**' end
$$;

create or replace function iara.mask_phone(p text) returns text
language sql immutable as $$
  select case when p is null then null else regexp_replace(p, '(\(\d{2}\)\s?)(\d{1,5})(\d{4})?-?(\d{4})$', '\1•••••-\4') end
$$;

-- ---------------------------------------------------------------------------
-- Faixa/série pela data de nascimento (data de corte configurável — padrão 31/03)
-- ---------------------------------------------------------------------------
create or replace function iara.grade_for_birthdate(p_birth date, p_school_year integer default null)
returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_year integer := coalesce(p_school_year, iara.school_year());
  v_cutoff date := make_date(v_year, coalesce(split_part(iara.setting('age_cutoff'), '-', 1), '3')::int,
                                    coalesce(split_part(iara.setting('age_cutoff'), '-', 2), '31')::int);
  v_months integer;
  g record;
begin
  if p_birth is null then
    return jsonb_build_object('ok', false, 'explanation', 'Informe a data de nascimento.');
  end if;
  v_months := (extract(year from age(v_cutoff, p_birth)) * 12 + extract(month from age(v_cutoff, p_birth)))::int;
  select gl.*, s.name stage_name, s.code stage_code into g
  from iara.grade_levels gl join iara.education_stages s on s.id = gl.stage_id
  where gl.tenant_id = 1 and v_months between gl.min_age_months and gl.max_age_months
  order by gl.sort limit 1;
  if found then
    return jsonb_build_object(
      'ok', true, 'grade_level_id', g.id, 'grade_code', g.code, 'grade_name', g.name,
      'stage_id', g.stage_id, 'stage_code', g.stage_code, 'stage_name', g.stage_name,
      'age_months', v_months, 'cutoff', v_cutoff, 'school_year', v_year,
      'explanation', format('Em %s a criança terá %s ano(s) e %s mês(es) → %s (regra: idade na data de corte %s, faixa de %s a %s meses).',
                            to_char(v_cutoff, 'DD/MM/YYYY'), v_months / 12, v_months % 12, g.name,
                            to_char(v_cutoff, 'DD/MM'), g.min_age_months, g.max_age_months));
  end if;
  return jsonb_build_object(
    'ok', false, 'age_months', v_months, 'cutoff', v_cutoff, 'school_year', v_year,
    'explanation', case
      when v_months < 4 then format('Em %s a criança terá %s mês(es): abaixo da idade mínima de atendimento em creche (4 meses).', to_char(v_cutoff, 'DD/MM/YYYY'), v_months)
      when v_months between 132 and 179 then 'Idade correspondente aos anos finais do Ensino Fundamental, não ofertados pela rede municipal. Verifique a rede estadual.'
      else 'Nenhuma faixa da rede municipal corresponde a esta idade.' end);
end $$;

-- ---------------------------------------------------------------------------
-- Regras vigentes
-- ---------------------------------------------------------------------------
create or replace function iara.rule(p_code text) returns iara.rules
language sql stable security definer set search_path = iara, public
as $$
  select r.* from iara.rules r
  where r.tenant_id = 1 and r.rule_code = p_code and r.is_active
    and current_date >= r.valid_from and (r.valid_to is null or current_date <= r.valid_to)
  order by r.valid_from desc limit 1
$$;

create or replace function iara.rule_version() returns text
language sql stable security definer set search_path = iara, public
as $$ select coalesce(max(version), 'sem-regras') from iara.rules where tenant_id = 1 and is_active $$;

-- ---------------------------------------------------------------------------
-- Prioridade da fila (pontuação explicável, versionada)
-- ---------------------------------------------------------------------------
create or replace function iara.compute_queue_priority(p_entry uuid) returns void
language plpgsql security definer set search_path = iara, extensions, public
as $$
declare
  w iara.waiting_list_entries;
  v_dist integer;
  v_sibling boolean;
  v_cadunico boolean;
  v_aee boolean;
  v_vuln boolean;
  v_breakdown jsonb := '[]'::jsonb;
  v_score numeric := 0;
  v_flags text[] := '{}';
  r iara.rules;
  v_max_m integer;
begin
  select * into w from iara.waiting_list_entries where id = p_entry;
  if not found then return; end if;

  select round(st_distance(a.location, u.location))::int into v_dist
  from iara.students s join iara.addresses a on a.id = s.address_id
  join iara.education_units u on u.id = w.preferred_unit_id
  where s.id = w.student_id;

  select exists (
    select 1 from iara.student_guardians sg1
    join iara.student_guardians sg2 on sg2.guardian_id = sg1.guardian_id and sg2.student_id <> sg1.student_id
    join iara.enrollments e on e.student_id = sg2.student_id and e.status = 'ACTIVE' and e.unit_id = w.preferred_unit_id
    where sg1.student_id = w.student_id) into v_sibling;

  select coalesce(bool_or(g.cadunico_status), false) into v_cadunico
  from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
  where sg.student_id = w.student_id;

  select aee_status into v_aee from iara.students where id = w.student_id;
  v_vuln := 'VULNERABILIDADE' = any (w.priority_flags);

  -- TERRITORIO_2KM
  r := iara.rule('TERRITORIO_2KM');
  if r.id is not null then
    v_max_m := coalesce((r.condition ->> 'max_m')::int, 2000);
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', coalesce(v_dist <= v_max_m, false),
      'evidence', case when v_dist is null then 'Endereço sem geocodificação' else format('Residência a %s km da unidade preferida', round(v_dist / 1000.0, 1)) end);
    if coalesce(v_dist <= v_max_m, false) then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'TERRITORIO'); end if;
  end if;
  -- IRMAO_NA_UNIDADE
  r := iara.rule('IRMAO_NA_UNIDADE');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', v_sibling, 'evidence', case when v_sibling then 'Irmão(ã) com matrícula ativa na unidade preferida' else 'Sem irmão matriculado na unidade' end);
    if v_sibling then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'IRMAO_NA_UNIDADE'); end if;
  end if;
  -- CADUNICO
  r := iara.rule('CADUNICO');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', v_cadunico, 'evidence', case when v_cadunico then 'Responsável com inscrição ativa no CadÚnico' else 'Sem CadÚnico informado' end);
    if v_cadunico then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'CADUNICO'); end if;
  end if;
  -- PCD_TEA_AEE
  r := iara.rule('PCD_TEA_AEE');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', coalesce(v_aee, false), 'evidence', case when v_aee then 'Necessidade de AEE/inclusão registrada (detalhe restrito)' else 'Sem indicação de AEE' end);
    if v_aee then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'PCD_TEA_AEE'); end if;
  end if;
  -- VULNERABILIDADE
  r := iara.rule('VULNERABILIDADE');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', v_vuln, 'evidence', case when v_vuln then 'Encaminhamento da rede de proteção registrado' else 'Sem encaminhamento da rede de proteção' end);
    if v_vuln then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'VULNERABILIDADE'); end if;
  end if;
  -- DATA_SOLICITACAO (desempate)
  r := iara.rule('DATA_SOLICITACAO');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', 0, 'version', r.version,
      'applied', true, 'evidence', format('Desempate pela data de entrada: %s', to_char(w.entered_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')));
  end if;

  update iara.waiting_list_entries set
    priority_score = v_score,
    score_breakdown = v_breakdown,
    home_distance_m = v_dist,
    priority_flags = coalesce((select array_agg(distinct f) from unnest(v_flags || array_remove(w.priority_flags, null)) f
                               where f in ('TERRITORIO', 'IRMAO_NA_UNIDADE', 'CADUNICO', 'PCD_TEA_AEE', 'VULNERABILIDADE')), '{}'),
    rule_version = iara.rule_version(),
    last_recalculated_at = now()
  where id = p_entry;
end $$;

-- Posição: por unidade preferida + faixa, ordenada por pontuação e data de entrada (determinístico)
create or replace function iara.recalculate_queue(p_unit integer, p_grade smallint) returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_n integer;
begin
  update iara.waiting_list_entries w set position = null
  where w.preferred_unit_id = p_unit and w.grade_level_id = p_grade and w.status <> 'WAITING' and w.position is not null;

  with ranked as (
    select id, row_number() over (order by priority_score desc, entered_at asc, id) as pos
    from iara.waiting_list_entries
    where preferred_unit_id = p_unit and grade_level_id = p_grade and status = 'WAITING'
  )
  update iara.waiting_list_entries w set position = ranked.pos, last_recalculated_at = now()
  from ranked where w.id = ranked.id and w.position is distinct from ranked.pos;

  select count(*) into v_n from iara.waiting_list_entries
  where preferred_unit_id = p_unit and grade_level_id = p_grade and status = 'WAITING';
  return v_n;
end $$;

create or replace function iara.recalculate_all_queues() returns void
language sql security definer set search_path = iara, public
as $$
  update iara.waiting_list_entries set position = null where status <> 'WAITING' and position is not null;
  with ranked as (
    select id, row_number() over (partition by preferred_unit_id, grade_level_id
                                  order by priority_score desc, entered_at asc, id) as pos
    from iara.waiting_list_entries where status = 'WAITING'
  )
  update iara.waiting_list_entries w set position = ranked.pos, last_recalculated_at = now()
  from ranked where w.id = ranked.id;
$$;

-- ---------------------------------------------------------------------------
-- Busca Inteligente de Vaga — ranking determinístico e explicável (spec §19)
-- Nunca devolve "recomendado por IA": cada ponto da pontuação tem regra, versão e evidência.
-- ---------------------------------------------------------------------------
create or replace function iara.search_vacancies_core(
  p_grade smallint,
  p_lat double precision,
  p_lng double precision,
  p_shift text default null,
  p_shift_required boolean default false,
  p_student uuid default null,
  p_aee boolean default false,
  p_limit integer default 8,
  p_max_km numeric default 12
) returns jsonb
language plpgsql stable security definer set search_path = iara, extensions, public
as $$
declare
  v_home extensions.geography := iara.point(p_lat, p_lng);
  r_vaga iara.rules := iara.rule('VAGA_OFERTAVEL');
  r_terr iara.rules := iara.rule('TERRITORIO_2KM');
  r_dist iara.rules := iara.rule('DISTANCIA');
  r_irmao iara.rules := iara.rule('IRMAO_NA_UNIDADE');
  r_aee iara.rules := iara.rule('AEE_UNIDADE');
  r_turno iara.rules := iara.rule('TURNO_PREFERIDO');
  r_fila iara.rules := iara.rule('FILA_PRESSAO');
  v_max_m integer;
  v_results jsonb;
  v_excluded jsonb;
  v_grade jsonb;
begin
  v_max_m := coalesce((r_terr.condition ->> 'max_m')::int, 2000);

  select jsonb_build_object('id', gl.id, 'code', gl.code, 'name', gl.name, 'stage_id', s.id, 'stage_name', s.name)
  into v_grade
  from iara.grade_levels gl join iara.education_stages s on s.id = gl.stage_id where gl.id = p_grade;

  with cand as (
    select u.id, u.name, u.unit_type, u.unit_type_label, u.status, u.lat, u.lng, u.has_aee, u.address_line, u.neighborhood,
           t.name as territory_name, round(st_distance(u.location, v_home))::int as dist_m
    from iara.education_units u
    left join iara.territories t on t.id = u.macro_territory_id
    where st_dwithin(u.location, v_home, p_max_km * 1000)
  ),
  cls as (
    select c.unit_id,
           count(*) as n_classes,
           sum(c.authorized_capacity) as capacity,
           sum(c.active_enrollments_count) as enrolled,
           sum(c.physical_vacancies_count) as physical,
           sum(c.blocked_seats_count) as blocked,
           sum(c.reserved_seats_count) as reserved,
           sum(c.offerable_vacancies_count) as offerable,
           coalesce(sum(c.offerable_vacancies_count) filter (where p_shift is not null and c.shift = p_shift), 0) as offerable_shift,
           array_agg(distinct c.shift) as shifts,
           bool_or(p_shift is not null and c.shift = p_shift) as has_shift
    from iara.classes c
    where c.grade_level_id = p_grade and c.status = 'ATIVA'
    group by c.unit_id
  ),
  q as (
    select preferred_unit_id as unit_id, count(*) as queue
    from iara.waiting_list_entries where grade_level_id = p_grade and status = 'WAITING'
    group by preferred_unit_id
  ),
  mine as (
    select preferred_unit_id as unit_id, position
    from iara.waiting_list_entries
    where p_student is not null and student_id = p_student and grade_level_id = p_grade and status = 'WAITING'
  ),
  sib as (
    select distinct e.unit_id
    from iara.student_guardians sg1
    join iara.student_guardians sg2 on sg2.guardian_id = sg1.guardian_id and sg2.student_id <> sg1.student_id
    join iara.enrollments e on e.student_id = sg2.student_id and e.status = 'ACTIVE'
    where p_student is not null and sg1.student_id = p_student
  ),
  joined as (
    select cand.*, cls.n_classes, cls.capacity, cls.enrolled, cls.physical, cls.blocked, cls.reserved, cls.offerable,
           cls.offerable_shift, cls.shifts, coalesce(cls.has_shift, false) as has_shift,
           coalesce(q.queue, 0) as queue, mine.position as my_position,
           (sib.unit_id is not null) as sibling,
           case
             when cand.status <> 'ATIVA' then 'ELIM_UNIDADE_ATIVA'
             when cls.unit_id is null then 'ELIM_ETAPA_SERIE'
             when p_shift_required and p_shift is not null and not coalesce(cls.has_shift, false) then 'ELIM_TURNO'
           end as excluded_by
    from cand
    left join cls on cls.unit_id = cand.id
    left join q on q.unit_id = cand.id
    left join mine on mine.unit_id = cand.id
    left join sib on sib.unit_id = cand.id
  ),
  scored as (
    select j.*,
           case when p_shift is not null and j.has_shift then j.offerable_shift else j.offerable end as offerable_eff,
           greatest(coalesce(j.my_position - 1, j.queue), 0) as queue_ahead
    from joined j where j.excluded_by is null
  ),
  pts as (
    select s.*,
      (case when s.offerable_eff > 0 then coalesce(r_vaga.weight, 0) else 0 end)
      + (case when s.dist_m <= v_max_m then coalesce(r_terr.weight, 0) else 0 end)
      + coalesce(r_dist.weight, 0) * (s.dist_m / 1000.0)
      + (case when s.sibling then coalesce(r_irmao.weight, 0) else 0 end)
      + (case when p_aee and s.has_aee then coalesce(r_aee.weight, 0) else 0 end)
      + (case when p_shift is not null and s.has_shift then coalesce(r_turno.weight, 0) else 0 end)
      + coalesce(r_fila.weight, 0) * least(s.queue_ahead, coalesce((r_fila.condition ->> 'cap')::int, 20))
      as score
    from scored s
  ),
  ranked as (
    select p.*, row_number() over (order by p.score desc, p.dist_m asc, p.id) as rank
    from pts p
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'rank', r.rank,
      'unit_id', r.id, 'name', r.name, 'unit_type', r.unit_type, 'unit_type_label', r.unit_type_label,
      'lat', r.lat, 'lng', r.lng, 'address', r.address_line, 'neighborhood', r.neighborhood, 'territory', r.territory_name,
      'distance_m', r.dist_m, 'within_territory', r.dist_m <= v_max_m,
      'classes', r.n_classes, 'capacity', r.capacity, 'enrolled', r.enrolled, 'physical', r.physical,
      'blocked', r.blocked, 'reserved', r.reserved, 'offerable', r.offerable, 'offerable_effective', r.offerable_eff,
      'shifts', r.shifts, 'queue', r.queue, 'queue_ahead', r.queue_ahead, 'my_position', r.my_position,
      'sibling', r.sibling, 'has_aee', r.has_aee,
      'score', round(r.score::numeric, 1),
      'can_offer_now', r.offerable_eff > 0 and r.queue_ahead = 0,
      'reasons', array_remove(array[
        case when r.offerable_eff > 0 then format('%s vaga(s) ofertável(is)%s', r.offerable_eff, case when p_shift is not null and r.has_shift then ' no turno preferido' else '' end)
             else 'Sem vaga ofertável no momento' end,
        format('%s km da residência%s', replace(round(r.dist_m / 1000.0, 1)::text, '.', ','),
               case when r.dist_m <= v_max_m then ' — dentro do território prioritário' else ' — fora do raio prioritário' end),
        case when r.sibling then 'Irmão(ã) matriculado(a) na unidade' end,
        case when p_aee and r.has_aee then 'Unidade com atendimento educacional especializado (AEE)' end,
        case when r.queue_ahead > 0 then format('%s criança(s) à frente na fila desta faixa', r.queue_ahead) end,
        case when r.my_position is not null then format('A criança é a %sª da fila nesta unidade', r.my_position) end,
        case when r.offerable_eff > 0 and r.queue_ahead > 0 then 'A vaga deve ser ofertada respeitando a ordem da fila' end
      ], null),
      'score_detail', jsonb_build_array(
        jsonb_build_object('code', 'VAGA_OFERTAVEL', 'points', case when r.offerable_eff > 0 then coalesce(r_vaga.weight, 0) else 0 end),
        jsonb_build_object('code', 'TERRITORIO_2KM', 'points', case when r.dist_m <= v_max_m then coalesce(r_terr.weight, 0) else 0 end),
        jsonb_build_object('code', 'DISTANCIA', 'points', round((coalesce(r_dist.weight, 0) * r.dist_m / 1000.0)::numeric, 1)),
        jsonb_build_object('code', 'IRMAO_NA_UNIDADE', 'points', case when r.sibling then coalesce(r_irmao.weight, 0) else 0 end),
        jsonb_build_object('code', 'AEE_UNIDADE', 'points', case when p_aee and r.has_aee then coalesce(r_aee.weight, 0) else 0 end),
        jsonb_build_object('code', 'TURNO_PREFERIDO', 'points', case when p_shift is not null and r.has_shift then coalesce(r_turno.weight, 0) else 0 end),
        jsonb_build_object('code', 'FILA_PRESSAO', 'points', coalesce(r_fila.weight, 0) * least(r.queue_ahead, coalesce((r_fila.condition ->> 'cap')::int, 20)))
      ),
      'top_classes', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'class_id', c.id, 'class_name', c.class_name, 'shift', c.shift, 'capacity', c.authorized_capacity,
                 'enrolled', c.active_enrollments_count, 'offerable', c.offerable_vacancies_count) order by c.offerable_vacancies_count desc, c.class_code), '[]'::jsonb)
        from (select * from iara.classes c2
              where c2.unit_id = r.id and c2.grade_level_id = p_grade and c2.status = 'ATIVA'
                and (not p_shift_required or p_shift is null or c2.shift = p_shift)
              order by c2.offerable_vacancies_count desc, c2.class_code limit 4) c)
    ) order by r.rank), '[]'::jsonb)
  into v_results
  from ranked r where r.rank <= p_limit;

  select jsonb_build_object(
    'ELIM_UNIDADE_ATIVA', count(*) filter (where u.status <> 'ATIVA'),
    'ELIM_ETAPA_SERIE', count(*) filter (where u.status = 'ATIVA' and not exists (
        select 1 from iara.classes c where c.unit_id = u.id and c.grade_level_id = p_grade and c.status = 'ATIVA')),
    'ELIM_TURNO', case when p_shift_required and p_shift is not null then count(*) filter (where u.status = 'ATIVA'
        and exists (select 1 from iara.classes c where c.unit_id = u.id and c.grade_level_id = p_grade and c.status = 'ATIVA')
        and not exists (select 1 from iara.classes c where c.unit_id = u.id and c.grade_level_id = p_grade and c.status = 'ATIVA' and c.shift = p_shift)) else 0 end,
    'FORA_DO_RAIO_DE_BUSCA', count(*) filter (where not st_dwithin(u.location, v_home, p_max_km * 1000)))
  into v_excluded
  from iara.education_units u where u.tenant_id = 1;

  return jsonb_build_object(
    'grade', v_grade,
    'home', jsonb_build_object('lat', p_lat, 'lng', p_lng),
    'filters', jsonb_build_object('shift', p_shift, 'shift_required', p_shift_required, 'aee', p_aee, 'max_km', p_max_km),
    'rule_version', iara.rule_version(),
    'territory_radius_m', v_max_m,
    'generated_at', now(),
    'results', v_results,
    'excluded', v_excluded,
    'disclaimer', 'Consulta de disponibilidade: não é oferta de vaga. Ofertas seguem a ordem da fila e a validação da Central de Vagas.'
  );
end $$;

commit;
