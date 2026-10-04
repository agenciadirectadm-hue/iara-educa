-- IARA Educa — 013 · Painéis por perfil. Cada painel responde a uma pergunta real (spec §70).
begin;

-- Prefeito: "Onde precisamos investir?" — somente agregados, sem dados pessoais
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
      (select round(avg(c.active_enrollments_count::numeric / nullif(c.authorized_capacity, 0)) * 100, 1) from iara.classes c join iara.education_units u on u.id = c.unit_id where u.macro_territory_id = t.id) as occupancy
    from iara.territories t where t.kind in ('MACRORREGIAO', 'DISTRITO')
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
                                                    'avg_km', avg_km, 'occupancy', occupancy,
                                                    'pressure', case when offerable_creche - queue_creche <= -120 then 'SEVERO' when offerable_creche - queue_creche <= -60 then 'ALTO'
                                                                     when offerable_creche - queue_creche < 0 then 'ATENCAO' when offerable - queue > 250 then 'OCIOSO' else 'EQUILIBRIO' end)
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

-- Secretário(a): "Onde está o gargalo?"
create or replace function api.dashboard_secretario(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, extensions, public
as $$
declare
  v_stage text := nullif(p ->> 'stage', '');
  v jsonb;
begin
  perform iara.require_perm('kpi.network');
  select jsonb_build_object(
    'question', 'Onde está o gargalo?',
    'stage', v_stage,
    'kpis', iara.kpis(null, v_stage),
    'by_grade', (select jsonb_agg(jsonb_build_object('grade_level_id', gl.id, 'grade', gl.name, 'stage_id', gl.stage_id,
        'capacity', (select coalesce(sum(authorized_capacity), 0) from iara.classes where grade_level_id = gl.id),
        'enrolled', (select coalesce(sum(active_enrollments_count), 0) from iara.classes where grade_level_id = gl.id),
        'offerable', (select coalesce(sum(offerable_vacancies_count), 0) from iara.classes where grade_level_id = gl.id),
        'queue', (select count(*) from iara.waiting_list_entries where grade_level_id = gl.id and status in ('WAITING', 'OFFERED')),
        'queue_no_service', (select count(*) from iara.waiting_list_entries where grade_level_id = gl.id and status in ('WAITING', 'OFFERED') and demand_category = 'SEM_ATENDIMENTO'))
        order by gl.sort)
      from iara.grade_levels gl where v_stage is null or gl.stage_id = (select id from iara.education_stages where code = v_stage)),
    'by_category', (select jsonb_object_agg(demand_category, n) from (select demand_category, count(*) n from iara.waiting_list_entries w
        join iara.grade_levels gl on gl.id = w.grade_level_id
        where w.status in ('WAITING', 'OFFERED') and (v_stage is null or gl.stage_id = (select id from iara.education_stages where code = v_stage)) group by 1) z),
    'open_class_suggestions', (select coalesce(jsonb_agg(x order by (x ->> 'queue')::int desc), '[]'::jsonb) from (
        select jsonb_build_object('unit_id', u.id, 'unit', u.short_name, 'territory', t.name, 'grade_level_id', gl.id, 'grade', gl.name,
                                  'queue', q.n, 'offerable', coalesce(v.n, 0), 'suggested_classes', ceil(q.n / gl.reference_capacity::numeric),
                                  'staff_needed', ceil(q.n / gl.reference_capacity::numeric) * case when gl.id = 1 then 2 else 1 end,
                                  'rule', 'Fila ≥ 12 sem vaga ofertável → turmas = fila ÷ capacidade de referência (' || gl.reference_capacity || '). Cenário para decisão.') as x
        from (select preferred_unit_id, grade_level_id, count(*) n from iara.waiting_list_entries where status = 'WAITING' group by 1, 2) q
        join iara.education_units u on u.id = q.preferred_unit_id join iara.grade_levels gl on gl.id = q.grade_level_id
        join iara.territories t on t.id = u.macro_territory_id
        left join lateral (select sum(offerable_vacancies_count) n from iara.classes c where c.unit_id = u.id and c.grade_level_id = gl.id) v on true
        where q.n >= 12 and coalesce(v.n, 0) = 0 and (v_stage is null or gl.stage_id = (select id from iara.education_stages where code = v_stage))
        order by q.n desc limit 12) z),
    'saturated', (select coalesce(jsonb_agg(x order by (x ->> 'occupancy')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object('id', u.id, 'name', u.short_name, 'territory', t.name, 'occupancy', (o ->> 'occupancy')::numeric,
                                  'queue', (o ->> 'queue')::int, 'offerable', (o ->> 'offerable')::int) as x
        from iara.education_units u join iara.territories t on t.id = u.macro_territory_id, lateral iara.unit_ops(u.id) o
        where (o ->> 'occupancy')::numeric >= 97 and (v_stage is null or (v_stage = 'EI' and u.unit_type = 'CMEI') or (v_stage <> 'EI' and u.unit_type = 'ESCOLA'))
        order by (o ->> 'occupancy')::numeric desc, (o ->> 'queue')::int desc limit 10) z),
    'idle', (select coalesce(jsonb_agg(x order by (x ->> 'offerable')::int desc), '[]'::jsonb) from (
        select jsonb_build_object('id', u.id, 'name', u.short_name, 'territory', t.name, 'offerable', (o ->> 'offerable')::int,
                                  'queue', (o ->> 'queue')::int, 'occupancy', (o ->> 'occupancy')::numeric) as x
        from iara.education_units u join iara.territories t on t.id = u.macro_territory_id, lateral iara.unit_ops(u.id) o
        where (o ->> 'offerable')::int >= 20 and (v_stage is null or (v_stage = 'EI' and u.unit_type = 'CMEI') or (v_stage <> 'EI' and u.unit_type = 'ESCOLA'))
        order by (o ->> 'offerable')::int desc limit 10) z),
    'cases', (select jsonb_build_object(
        'by_status', (select jsonb_object_agg(status, n) from (select status, count(*) n from iara.service_cases where iara.case_open(status) group by 1) z),
        'by_team', (select jsonb_object_agg(assigned_team, jsonb_build_object('open', n, 'overdue', od)) from (
                      select assigned_team, count(*) n, count(*) filter (where sla_due_at < now()) od from iara.service_cases where iara.case_open(status) group by 1) z),
        'by_type', (select jsonb_agg(jsonb_build_object('type', sc.name, 'open', z.n, 'overdue', z.od) order by z.n desc) from (
                      select case_type, count(*) n, count(*) filter (where sla_due_at < now()) od from iara.service_cases where iara.case_open(status) group by 1) z
                    join iara.service_catalog sc on sc.code = z.case_type))),
    'offers_funnel', (select jsonb_build_object('window_days', 120,
        'offered', count(*), 'accepted_or_enrolled', count(*) filter (where status in ('ACCEPTED', 'ENROLLED')),
        'enrolled', count(*) filter (where status = 'ENROLLED'), 'declined', count(*) filter (where status = 'DECLINED'),
        'expired', count(*) filter (where status = 'EXPIRED'), 'pending', count(*) filter (where status = 'OFFERED'))
      from iara.vacancy_offers where offered_at > now() - interval '120 days'),
    'quality', (select jsonb_build_object('open', count(*), 'high', count(*) filter (where severity = 'ALTA')) from iara.data_quality_issues where status <> 'RESOLVIDA')
  ) into v;
  return v;
end $$;

-- Analista da Central de Vagas: "Qual vaga posso oferecer agora?"
create or replace function api.dashboard_analista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v jsonb;
begin
  perform iara.require_perm('cases.read');
  select jsonb_build_object(
    'question', 'Qual vaga posso oferecer agora?',
    'cases', jsonb_build_object(
      'by_status', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from iara.service_cases where iara.case_open(status) group by 1) z),
      'mine', (select count(*) from iara.service_cases where assigned_user_id = iara.current_user_id() and iara.case_open(status)),
      'overdue', (select count(*) from iara.service_cases where iara.case_open(status) and sla_due_at < now()),
      'new_today', (select count(*) from iara.service_cases where opened_at >= date_trunc('day', now())),
      'unassigned', (select count(*) from iara.service_cases where iara.case_open(status) and assigned_user_id is null)),
    'ready_to_offer', (select coalesce(jsonb_agg(x order by (x ->> 'score')::numeric desc, x ->> 'entered_at'), '[]'::jsonb) from (
        select jsonb_build_object('entry_id', w.id, 'student_id', s.id, 'student', s.full_name, 'avatar_seed', s.avatar_seed, 'age', iara.age_text(s.birth_date),
                                  'unit_id', u.id, 'unit', u.short_name, 'grade', gl.name, 'grade_level_id', gl.id, 'score', w.priority_score,
                                  'flags', w.priority_flags, 'entered_at', w.entered_at, 'offerable', v.n, 'class_id', v.class_id, 'class', v.class_name) as x
        from iara.waiting_list_entries w join iara.students s on s.id = w.student_id join iara.education_units u on u.id = w.preferred_unit_id
        join iara.grade_levels gl on gl.id = w.grade_level_id
        join lateral (select sum(c.offerable_vacancies_count) over () as n, c.id as class_id, c.class_name
                      from iara.classes c where c.unit_id = w.preferred_unit_id and c.grade_level_id = w.grade_level_id and c.offerable_vacancies_count > 0
                      order by c.offerable_vacancies_count desc limit 1) v on true
        where w.status = 'WAITING' and w.position = 1
        order by w.priority_score desc, w.entered_at limit 15) z),
    'expiring', (select coalesce(jsonb_agg(jsonb_build_object('offer_id', o.id, 'student', s.full_name, 'student_id', s.id, 'unit', u.short_name,
                                                              'expires_at', o.expires_at, 'hours_left', round(extract(epoch from (o.expires_at - now())) / 3600.0, 1))
                                           order by o.expires_at), '[]'::jsonb)
                 from iara.vacancy_offers o join iara.students s on s.id = o.student_id join iara.education_units u on u.id = o.unit_id
                 where o.status = 'OFFERED' and o.expires_at < now() + interval '24 hours'),
    'accepted', (select count(*) from iara.vacancy_offers where status = 'ACCEPTED'),
    'conversations_pending', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'contact', c.contact_label, 'summary', c.summary,
                                                                           'last_message_at', c.last_message_at) order by c.last_message_at), '[]'::jsonb)
                              from iara.conversations c where c.state = 'HUMAN_PENDING'),
    'new_cases', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'protocol', c.protocol_number, 'subject', c.subject, 'channel', c.channel,
                                                               'opened_at', c.opened_at, 'priority', c.priority) order by c.opened_at desc), '[]'::jsonb)
                  from (select * from iara.service_cases where status = 'NOVO' order by opened_at desc limit 8) c)
  ) into v;
  return v;
end $$;

-- Direção / secretaria escolar: "Como está minha unidade?" · "O que falta para concluir esta matrícula?"
create or replace function api.dashboard_unidade(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else (p ->> 'unit_id')::int end;
  v jsonb;
begin
  perform iara.require_perm('classes.read');
  if v_unit is null or not iara.can_access_unit(v_unit) then
    raise exception 'Unidade fora do seu escopo.' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'question', case when iara.my_role() = 'SECRETARIA_ESCOLAR' then 'O que falta para concluir esta matrícula?' else 'Como está minha unidade?' end,
    'unit', (select jsonb_build_object('id', u.id, 'name', u.name, 'short_name', u.short_name, 'type', u.unit_type, 'director', u.director_name,
                                       'address', u.address_line, 'neighborhood', u.neighborhood, 'inep', u.inep_code, 'lat', u.lat, 'lng', u.lng,
                                       'census_teachers', u.census_teachers, 'public_enrollments', u.public_enrollments)
             from iara.education_units u where u.id = v_unit),
    'ops', iara.unit_ops(v_unit),
    'classes', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.class_name, 'grade', gl.name, 'grade_level_id', gl.id, 'shift', c.shift,
                                                             'capacity', c.authorized_capacity, 'enrolled', c.active_enrollments_count, 'blocked', c.blocked_seats_count,
                                                             'reserved', c.reserved_seats_count, 'offerable', c.offerable_vacancies_count,
                                                             'occupancy', round(100.0 * c.active_enrollments_count / nullif(c.authorized_capacity, 0), 1))
                                          order by gl.sort, c.class_code)
                         from iara.classes c join iara.grade_levels gl on gl.id = c.grade_level_id where c.unit_id = v_unit), '[]'::jsonb),
    'queue', coalesce((select jsonb_agg(jsonb_build_object('grade', gl.name, 'grade_level_id', gl.id, 'waiting', z.n,
                                                           'top', (select jsonb_agg(jsonb_build_object('entry_id', w.id, 'position', w.position, 'student', s.full_name,
                                                                                                       'student_id', s.id, 'score', w.priority_score, 'flags', w.priority_flags) order by w.position)
                                                                   from (select * from iara.waiting_list_entries w2 where w2.preferred_unit_id = v_unit and w2.grade_level_id = gl.id
                                                                           and w2.status = 'WAITING' order by w2.position limit 5) w join iara.students s on s.id = w.student_id))
                                        order by gl.sort)
                       from (select grade_level_id, count(*) n from iara.waiting_list_entries where preferred_unit_id = v_unit and status = 'WAITING' group by 1) z
                       join iara.grade_levels gl on gl.id = z.grade_level_id), '[]'::jsonb),
    'pending_enrollments', coalesce((select jsonb_agg(jsonb_build_object('offer_id', o.id, 'status', o.status, 'student', s.full_name, 'student_id', s.id,
        'avatar_seed', s.avatar_seed, 'class', c.class_name, 'shift', c.shift, 'offered_at', o.offered_at, 'accepted_at', o.accepted_at, 'expires_at', o.expires_at,
        'documents', (select jsonb_agg(jsonb_build_object('type', d, 'status', coalesce((select x.status from iara.documents x where x.student_id = o.student_id and x.doc_type = d
                                                                                         order by x.created_at desc limit 1), 'NAO_ENVIADO')))
                      from unnest((select required_documents from iara.service_catalog where code = 'MATRICULA')) d))
        order by case o.status when 'ACCEPTED' then 0 else 1 end, o.offered_at)
      from iara.vacancy_offers o join iara.students s on s.id = o.student_id join iara.classes c on c.id = o.class_id
      where o.unit_id = v_unit and o.status in ('OFFERED', 'ACCEPTED')), '[]'::jsonb),
    'cases', (select jsonb_build_object('open', count(*), 'overdue', count(*) filter (where sla_due_at < now()),
                                        'by_type', (select jsonb_object_agg(case_type, n) from (select case_type, count(*) n from iara.service_cases
                                                     where unit_id = v_unit and iara.case_open(status) group by 1) z))
              from iara.service_cases where unit_id = v_unit and iara.case_open(status)),
    'staff', (select jsonb_build_object('total', count(*), 'by_role', jsonb_object_agg(role, n)) from (select role, count(*) n from iara.staff where unit_id = v_unit group by 1) z),
    'events', coalesce((select jsonb_agg(jsonb_build_object('type', e.event_type, 'class', c.class_name, 'quantity', e.quantity, 'reference', e.reference,
                                                            'actor', e.actor_label, 'at', e.occurred_at) order by e.occurred_at desc)
                        from (select * from iara.vacancy_events e2 where e2.unit_id = v_unit order by e2.occurred_at desc limit 10) e
                        left join iara.classes c on c.id = e.class_id), '[]'::jsonb),
    'blocks', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'class', c.class_name, 'seats', b.seats, 'reason', b.reason, 'justification', b.justification))
                        from iara.vacancy_blocks b join iara.classes c on c.id = b.class_id where c.unit_id = v_unit and b.released_at is null), '[]'::jsonb)
  ) into v;
  return v;
end $$;

-- Cidadão: "Onde meu filho será atendido e o que preciso fazer?"
create or replace function api.citizen_home(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, extensions, public
as $$
declare
  v_g uuid := iara.my_guardian();
  v jsonb;
begin
  if iara.my_scope() <> 'GUARDIAN' or v_g is null then
    raise exception 'Área exclusiva do responsável.' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'question', 'Onde meu filho será atendido e o que preciso fazer?',
    'guardian', (select jsonb_build_object('id', g.id, 'name', g.full_name, 'first_name', split_part(g.full_name, ' ', 1), 'phone', g.whatsapp_phone,
                                           'email', g.email, 'address', iara.address_json(g.address_id), 'cadunico', g.cadunico_status)
                 from iara.guardians g where g.id = v_g),
    'children', coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'name', s.full_name, 'first_name', split_part(s.full_name, ' ', 1), 'age', iara.age_text(s.birth_date), 'birth_date', s.birth_date,
        'status', s.status, 'avatar_seed', s.avatar_seed, 'grade_rule', iara.grade_for_birthdate(s.birth_date),
        'school', (select jsonb_build_object('unit_id', u.id, 'unit', u.name, 'class', c.class_name, 'shift', c.shift, 'lat', u.lat, 'lng', u.lng,
                                             'address', u.address_line, 'phone', u.phone)
                   from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.education_units u on u.id = e.unit_id
                   where e.student_id = s.id and e.status = 'ACTIVE' limit 1),
        'queue', (select jsonb_agg(jsonb_build_object('id', w.id, 'status', w.status, 'position', w.position, 'unit_id', u.id, 'unit', u.name,
                                                      'grade', gl.name, 'entered_at', w.entered_at, 'category', w.demand_category, 'breakdown', w.score_breakdown,
                                                      'score', w.priority_score, 'rule_version', w.rule_version,
                                                      'queue_size', (select count(*) from iara.waiting_list_entries x where x.preferred_unit_id = w.preferred_unit_id
                                                                       and x.grade_level_id = w.grade_level_id and x.status = 'WAITING'))
                                   order by w.entered_at desc)
                  from iara.waiting_list_entries w join iara.education_units u on u.id = w.preferred_unit_id join iara.grade_levels gl on gl.id = w.grade_level_id
                  where w.student_id = s.id and w.status in ('WAITING', 'OFFERED', 'ACCEPTED')),
        'offers', (select jsonb_agg(jsonb_build_object('id', o.id, 'status', o.status, 'unit', u.name, 'unit_id', u.id, 'class', c.class_name, 'shift', c.shift,
                                                       'offered_at', o.offered_at, 'expires_at', o.expires_at, 'accepted_at', o.accepted_at,
                                                       'hours_left', round(extract(epoch from (o.expires_at - now())) / 3600.0, 1), 'lat', u.lat, 'lng', u.lng,
                                                       'address', u.address_line) order by o.offered_at desc)
                   from iara.vacancy_offers o join iara.education_units u on u.id = o.unit_id join iara.classes c on c.id = o.class_id
                   where o.student_id = s.id and o.status in ('OFFERED', 'ACCEPTED')),
        'documents', (select jsonb_agg(jsonb_build_object('type', d, 'status', coalesce((select x.status from iara.documents x where x.student_id = s.id and x.doc_type = d
                                                                                       order by x.created_at desc limit 1), 'NAO_ENVIADO')))
                      from unnest((select required_documents from iara.service_catalog where code = 'MATRICULA')) d))
        order by s.birth_date)
      from iara.student_guardians sg join iara.students s on s.id = sg.student_id where sg.guardian_id = v_g), '[]'::jsonb),
    'cases', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'protocol', c.protocol_number, 'type_name', sc.name, 'status', c.status,
                                                           'subject', c.subject, 'opened_at', c.opened_at, 'sla_due_at', c.sla_due_at, 'open', iara.case_open(c.status),
                                                           'last_event', (select e.message from iara.case_events e where e.case_id = c.id and e.visibility = 'CIDADAO'
                                                                          order by e.occurred_at desc limit 1))
                                        order by iara.case_open(c.status) desc, c.opened_at desc)
                       from iara.service_cases c join iara.service_catalog sc on sc.code = c.case_type
                       where c.guardian_id = v_g or c.student_id in (select student_id from iara.student_guardians where guardian_id = v_g)), '[]'::jsonb),
    'notifications', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'title', n.title, 'body', n.body, 'channel', n.channel, 'at', n.created_at,
                                                                   'event', n.event_type) order by n.created_at desc)
                               from (select * from iara.notifications n2 where n2.guardian_id = v_g order by n2.created_at desc limit 12) n), '[]'::jsonb),
    'nearby', coalesce((select jsonb_agg(x order by (x ->> 'distance_m')::int) from (
        select jsonb_build_object('id', u.id, 'name', u.name, 'type', u.unit_type, 'lat', u.lat, 'lng', u.lng,
                                  'distance_m', round(st_distance(u.location, a.location))::int, 'neighborhood', u.neighborhood,
                                  'offerable_creche', (select coalesce(sum(c.offerable_vacancies_count), 0) from iara.classes c where c.unit_id = u.id and c.grade_level_id = 1),
                                  'offerable_pre', (select coalesce(sum(c.offerable_vacancies_count), 0) from iara.classes c where c.unit_id = u.id and c.grade_level_id = 2),
                                  'offerable_ef', (select coalesce(sum(c.offerable_vacancies_count), 0) from iara.classes c where c.unit_id = u.id and c.grade_level_id between 3 and 7)) as x
        from iara.guardians g join iara.addresses a on a.id = g.address_id, iara.education_units u
        where g.id = v_g order by u.location <-> a.location limit 6) z), '[]'::jsonb),
    'demo', jsonb_build_object('can_reset', true, 'hint', 'Cenário fictício: Davi aguarda vaga de creche. A oferta é feita pela Central de Vagas (perfil Analista).')
  ) into v;
  return v;
end $$;

grant execute on function api.dashboard_prefeito(jsonb), api.dashboard_secretario(jsonb), api.dashboard_analista(jsonb),
  api.dashboard_unidade(jsonb), api.citizen_home(jsonb) to authenticated;

commit;
