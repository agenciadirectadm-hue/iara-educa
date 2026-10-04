-- IARA Educa — 011 · API operacional (autenticados). Leituras: SECURITY INVOKER (RLS decide o que cada perfil vê).
-- Escritas: SECURITY DEFINER com verificação explícita de permissão, escopo, regra e auditoria. Nada de sucesso otimista.
begin;

grant execute on function iara.audit_event(text, text, text, integer, text, jsonb, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Utilitários de apresentação
-- ---------------------------------------------------------------------------
create or replace function iara.age_text(p_birth date) returns text
language sql stable as $$
  select case when p_birth is null then null
              when age(current_date, p_birth) < interval '2 years'
                then (extract(year from age(current_date, p_birth)) * 12 + extract(month from age(current_date, p_birth)))::int || ' meses'
              else extract(year from age(current_date, p_birth))::int || ' anos' end
$$;
grant execute on function iara.age_text(date) to anon, authenticated;

create or replace function iara.can_see_contacts() returns boolean
language sql stable security definer set search_path = iara, public
as $$ select iara.has_perm('guardians.read_contacts') or iara.my_scope() = 'GUARDIAN' $$;
grant execute on function iara.can_see_contacts() to authenticated;

create or replace function iara.case_open(p_status text) returns boolean
language sql immutable as $$ select p_status not in ('ENCERRADO', 'MATRICULA_CONCLUIDA', 'NAO_ATENDIDO') $$;
grant execute on function iara.case_open(text) to anon, authenticated;

create or replace function iara.guardian_json(g iara.guardians) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object(
    'id', g.id, 'full_name', g.full_name, 'social_name', g.social_name,
    'cpf', case when iara.can_see_contacts() then g.cpf else iara.mask_cpf(g.cpf) end,
    'phone', case when iara.can_see_contacts() then g.primary_phone else iara.mask_phone(g.primary_phone) end,
    'whatsapp', case when iara.can_see_contacts() then g.whatsapp_phone else iara.mask_phone(g.whatsapp_phone) end,
    'email', case when iara.can_see_contacts() then g.email else regexp_replace(coalesce(g.email, ''), '^(.).*(@.*)$', '\1•••\2') end,
    'contacts_masked', not iara.can_see_contacts(),
    'preferred_channel', g.preferred_contact_channel, 'birth_date', g.birth_date, 'occupation', g.occupation,
    'employment_status', g.employment_status, 'family_income', g.family_income, 'income_bracket', g.income_bracket,
    'cadunico', g.cadunico_status, 'nis', case when iara.can_see_contacts() then g.nis else null end, 'benefits', g.benefits,
    'education_level', g.education_level, 'household_size', g.household_size, 'consent', g.consent_flags, 'is_demo', g.is_demo)
$$;
grant execute on function iara.guardian_json(iara.guardians) to authenticated;

create or replace function iara.address_json(p_address uuid) returns jsonb
language sql stable security definer set search_path = iara, extensions, public
as $$
  select case when iara.can_access_address(a.id) then jsonb_build_object(
    'id', a.id, 'street', a.street, 'number', a.number, 'complement', a.complement, 'neighborhood', a.neighborhood,
    'postal_code', a.postal_code, 'city', a.city, 'state', a.state, 'lat', st_y(a.location::geometry), 'lng', st_x(a.location::geometry),
    'precision', a.geocode_precision, 'source', a.geocode_source,
    'territory', (select name from iara.territories t where t.id = a.territory_id),
    'line', a.street || ', ' || coalesce(a.number, 's/n') || coalesce(' — ' || a.complement, '') || ' · ' || coalesce(a.neighborhood, '') || ' · ' || a.city || '/' || a.state)
  end
  from iara.addresses a where a.id = p_address
$$;
grant execute on function iara.address_json(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Sessão
-- ---------------------------------------------------------------------------
create or replace function api.me(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare v jsonb;
begin
  select jsonb_build_object(
    'user_id', u.id, 'display_name', u.display_name, 'role', r.code, 'role_name', r.name, 'role_short', r.short_name,
    'scope', r.scope_type, 'stage_filter', r.stage_filter, 'question', r.question, 'org_unit', r.org_unit, 'is_demo', u.is_demo,
    'unit', (select jsonb_build_object('id', x.id, 'name', x.name, 'short_name', x.short_name, 'type', x.unit_type, 'lat', x.lat, 'lng', x.lng)
             from iara.education_units x where x.id = u.unit_id),
    'guardian', (select jsonb_build_object('id', g.id, 'name', g.full_name) from iara.guardians g where g.id = u.guardian_id),
    'permissions', (select coalesce(jsonb_agg(permission_code order by permission_code), '[]'::jsonb) from iara.role_permissions where role_code = u.role_code))
  into v
  from iara.app_users u join iara.organizational_roles r on r.code = u.role_code
  where u.id = iara.current_user_id();
  if v is null then
    raise exception 'Sessão expirada. Escolha um perfil novamente.' using errcode = '28000';
  end if;
  return v;
end $$;

-- ---------------------------------------------------------------------------
-- Busca global (permissões aplicadas antes de mostrar resultado — RLS)
-- ---------------------------------------------------------------------------
create or replace function api.global_search(p jsonb) returns jsonb
language sql stable security invoker set search_path = iara, public
as $$
  with q as (select iara.norm(trim(coalesce(p ->> 'q', ''))) as q, regexp_replace(coalesce(p ->> 'q', ''), '\D', '', 'g') as digits)
  select jsonb_build_object(
    'students', coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('id', s.id, 'name', s.full_name, 'sub', 'Matrícula ' || s.student_registry_number || ' · ' || iara.age_text(s.birth_date),
                                'status', s.status) as x
      from iara.students s, q where length(q.q) >= 3
        and (iara.norm(s.full_name) like '%' || q.q || '%' or (length(q.digits) >= 6 and s.student_registry_number = q.digits))
      order by s.full_name limit 8) z), '[]'::jsonb),
    'guardians', coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('id', g.id, 'name', g.full_name,
                                'sub', case when iara.can_see_contacts() then coalesce(g.primary_phone, '') else iara.mask_phone(g.primary_phone) end) as x
      from iara.guardians g, q where length(q.q) >= 3
        and (iara.norm(g.full_name) like '%' || q.q || '%' or (length(q.digits) >= 8 and regexp_replace(coalesce(g.cpf, '') || coalesce(g.primary_phone, ''), '\D', '', 'g') like '%' || q.digits || '%'))
      order by g.full_name limit 6) z), '[]'::jsonb),
    'units', coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('id', u.id, 'name', u.name, 'sub', coalesce(u.neighborhood, '') || ' · ' || u.unit_type_label) as x
      from iara.education_units u, q where length(q.q) >= 2 and iara.norm(u.name || ' ' || coalesce(u.neighborhood, '')) like '%' || q.q || '%'
      order by u.short_name limit 6) z), '[]'::jsonb),
    'classes', coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('id', c.id, 'name', c.class_name || ' · ' || u.short_name, 'sub', c.offerable_vacancies_count || ' vaga(s) ofertável(is)') as x
      from iara.classes c join iara.education_units u on u.id = c.unit_id, q
      where length(q.q) >= 3 and iara.norm(c.class_name || ' ' || u.name) like '%' || q.q || '%' order by u.short_name, c.class_code limit 6) z), '[]'::jsonb),
    'cases', coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('id', sc.id, 'name', sc.protocol_number, 'sub', sc.subject, 'status', sc.status) as x
      from iara.service_cases sc, q where length(q.q) >= 3
        and (lower(sc.protocol_number) like '%' || q.q || '%' or iara.norm(sc.subject) like '%' || q.q || '%')
      order by sc.opened_at desc limit 6) z), '[]'::jsonb)
  )
$$;

-- ---------------------------------------------------------------------------
-- Turmas
-- ---------------------------------------------------------------------------
create or replace function api.unit_classes(p jsonb) returns jsonb
language sql stable security invoker set search_path = iara, public
as $$
  select jsonb_build_object('items', coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'code', c.class_code, 'name', c.class_name, 'grade_level_id', c.grade_level_id, 'grade', gl.name, 'stage_id', c.stage_id,
      'shift', c.shift, 'room', c.room_label, 'capacity', c.authorized_capacity, 'enrolled', c.active_enrollments_count,
      'physical', c.physical_vacancies_count, 'blocked', c.blocked_seats_count, 'reserved', c.reserved_seats_count,
      'offerable', c.offerable_vacancies_count, 'status', c.status, 'confidence', c.confidence_status,
      'occupancy', case when c.authorized_capacity > 0 then round(100.0 * c.active_enrollments_count / c.authorized_capacity, 1) end,
      'teacher', (select s.full_name from iara.class_staff cs join iara.staff s on s.id = cs.staff_id where cs.class_id = c.id and cs.is_primary limit 1),
      'assistant', (select s.full_name from iara.class_staff cs join iara.staff s on s.id = cs.staff_id where cs.class_id = c.id and cs.role_type = 'AUXILIAR' limit 1),
      'queue', (select count(*) from iara.waiting_list_entries w where w.preferred_unit_id = c.unit_id and w.grade_level_id = c.grade_level_id and w.status = 'WAITING'))
      order by gl.sort, c.class_code), '[]'::jsonb),
    'source', 'DEMO — estrutura de turmas do Censo 2025; capacidade e divisão por turma fictícias')
  from iara.classes c join iara.grade_levels gl on gl.id = c.grade_level_id
  where c.unit_id = (p ->> 'unit_id')::int
    and ((p ->> 'grade_level_id') is null or c.grade_level_id = (p ->> 'grade_level_id')::smallint)
$$;

create or replace function api.class_detail(p jsonb) returns jsonb
language plpgsql stable security invoker set search_path = iara, public
as $$
declare
  c iara.classes;
  v jsonb;
begin
  select * into c from iara.classes where id = (p ->> 'class_id')::uuid;
  if not found then
    raise exception 'Turma não encontrada ou fora do seu escopo.' using errcode = 'P0002';
  end if;
  select jsonb_build_object(
    'class', jsonb_build_object('id', c.id, 'code', c.class_code, 'name', c.class_name, 'shift', c.shift, 'room', c.room_label,
      'modality', c.modality, 'status', c.status, 'school_year', c.school_year, 'source', c.source, 'confidence', c.confidence_status,
      'grade_level_id', c.grade_level_id, 'grade', (select name from iara.grade_levels where id = c.grade_level_id),
      'stage', (select name from iara.education_stages where id = c.stage_id)),
    'unit', (select jsonb_build_object('id', u.id, 'name', u.name, 'short_name', u.short_name, 'type', u.unit_type, 'lat', u.lat, 'lng', u.lng)
             from iara.education_units u where u.id = c.unit_id),
    'kpis', jsonb_build_object('capacity', c.authorized_capacity, 'enrolled', c.active_enrollments_count, 'physical', c.physical_vacancies_count,
      'blocked', c.blocked_seats_count, 'reserved', c.reserved_seats_count, 'offerable', c.offerable_vacancies_count,
      'queue', (select count(*) from iara.waiting_list_entries w where w.preferred_unit_id = c.unit_id and w.grade_level_id = c.grade_level_id and w.status = 'WAITING'),
      'formula', 'Ofertáveis = capacidade − matrículas ativas − bloqueadas − reservadas'),
    'staff', coalesce((select jsonb_agg(jsonb_build_object('name', s.full_name, 'role', cs.role_type, 'staff_role', s.role, 'bond', s.bond,
                                                           'primary', cs.is_primary, 'hours', cs.hours_per_week) order by cs.is_primary desc, s.full_name)
                       from iara.class_staff cs join iara.staff s on s.id = cs.staff_id where cs.class_id = c.id), '[]'::jsonb),
    'students_visible', iara.has_perm('students.read'),
    'students', coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'name', s.full_name, 'registry', s.student_registry_number, 'age', iara.age_text(s.birth_date), 'birth_date', s.birth_date,
        'gender', s.gender, 'aee', s.aee_status, 'transport', s.transport_need, 'avatar_seed', s.avatar_seed, 'enrollment_status', e.status,
        'guardian', (select g.full_name from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
                     where sg.student_id = s.id and sg.is_primary limit 1),
        'contact', (select case when iara.can_see_contacts() then g.primary_phone else iara.mask_phone(g.primary_phone) end
                    from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id where sg.student_id = s.id and sg.is_primary limit 1))
        order by s.full_name)
      from iara.enrollments e join iara.students s on s.id = e.student_id
      where e.class_id = c.id and e.status = 'ACTIVE'), '[]'::jsonb),
    'blocks', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'seats', b.seats, 'reason', b.reason, 'justification', b.justification,
                                                            'valid_until', b.valid_until, 'created_at', b.created_at, 'released_at', b.released_at)
                                         order by b.created_at desc)
                        from iara.vacancy_blocks b where b.class_id = c.id and b.released_at is null), '[]'::jsonb),
    'offers', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'status', o.status, 'student', s.full_name, 'student_id', s.id,
                                                            'offered_at', o.offered_at, 'expires_at', o.expires_at, 'accepted_at', o.accepted_at)
                                         order by o.offered_at desc)
                        from iara.vacancy_offers o join iara.students s on s.id = o.student_id
                        where o.class_id = c.id and o.status in ('OFFERED', 'ACCEPTED')), '[]'::jsonb),
    'queue_top', coalesce((select jsonb_agg(jsonb_build_object('entry_id', w.id, 'position', w.position, 'student', s.full_name, 'student_id', s.id,
                                                               'score', w.priority_score, 'flags', w.priority_flags, 'entered_at', w.entered_at,
                                                               'category', w.demand_category) order by w.position)
                           from (select * from iara.waiting_list_entries w2
                                 where w2.preferred_unit_id = c.unit_id and w2.grade_level_id = c.grade_level_id and w2.status = 'WAITING'
                                 order by w2.position limit 10) w join iara.students s on s.id = w.student_id), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_object('type', ev.event_type, 'quantity', ev.quantity, 'reference', ev.reference,
                                                            'actor', ev.actor_label, 'at', ev.occurred_at, 'before', ev.before_json, 'after', ev.after_json)
                                         order by ev.occurred_at desc)
                        from (select * from iara.vacancy_events e2 where e2.class_id = c.id order by e2.occurred_at desc limit 15) ev), '[]'::jsonb)
  ) into v;
  return v;
end $$;

-- ---------------------------------------------------------------------------
-- Ficha 360º do aluno e do responsável
-- ---------------------------------------------------------------------------
create or replace function api.student_detail(p jsonb) returns jsonb
language plpgsql volatile security invoker set search_path = iara, extensions, public
as $$
declare
  s iara.students;
  v_sens jsonb;
  v_school record;
  v jsonb;
  v_rule jsonb;
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

  select jsonb_build_object(
    'student', jsonb_build_object('id', s.id, 'full_name', s.full_name, 'social_name', s.social_name, 'birth_date', s.birth_date,
      'age', iara.age_text(s.birth_date), 'gender', s.gender, 'registry', s.student_registry_number, 'status', s.status,
      'aee', s.aee_status, 'transport_need', s.transport_need, 'transport_status', s.school_transport_status,
      'accessibility', s.accessibility_needs, 'avatar_seed', s.avatar_seed, 'is_demo', s.is_demo, 'created_at', s.created_at),
    'grade_rule', v_rule,
    'age_grade_distortion', v_school.grade_level_id is not null and coalesce((v_rule ->> 'grade_level_id')::int, 0) > v_school.grade_level_id,
    'sensitive', v_sens,
    'sensitive_restricted', not iara.has_perm('students.read_sensitive') and s.aee_status,
    'address', iara.address_json(s.address_id),
    'school', case when v_school.enrollment_id is not null then jsonb_build_object(
      'enrollment_id', v_school.enrollment_id, 'class_id', v_school.class_id, 'class_name', v_school.class_name, 'shift', v_school.shift,
      'unit_id', v_school.unit_id, 'unit_name', v_school.unit_name, 'distance_m', v_school.dist_m, 'lat', v_school.lat, 'lng', v_school.lng) end,
    'guardians', coalesce((select jsonb_agg(iara.guardian_json(g) || jsonb_build_object('relationship', sg.relationship, 'is_primary', sg.is_primary,
                                                                                        'can_pick_up', sg.can_pick_up, 'legal_status', sg.legal_authority_status)
                                            order by sg.is_primary desc)
                           from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id where sg.student_id = s.id), '[]'::jsonb),
    'siblings', coalesce((select jsonb_agg(distinct jsonb_build_object('id', s2.id, 'name', s2.full_name, 'age', iara.age_text(s2.birth_date),
        'unit', (select u.short_name from iara.enrollments e join iara.education_units u on u.id = e.unit_id where e.student_id = s2.id and e.status = 'ACTIVE' limit 1)))
      from iara.student_guardians a1 join iara.student_guardians a2 on a2.guardian_id = a1.guardian_id and a2.student_id <> a1.student_id
      join iara.students s2 on s2.id = a2.student_id where a1.student_id = s.id), '[]'::jsonb),
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
begin
  select * into g from iara.guardians where id = (p ->> 'guardian_id')::uuid;
  if not found then
    raise exception 'Responsável não encontrado ou sem permissão.' using errcode = 'P0002';
  end if;
  select jsonb_build_object(
    'guardian', iara.guardian_json(g),
    'address', iara.address_json(g.address_id),
    'students', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.full_name, 'age', iara.age_text(s.birth_date), 'status', s.status,
        'relationship', sg.relationship, 'is_primary', sg.is_primary, 'avatar_seed', s.avatar_seed,
        'unit', (select u.short_name from iara.enrollments e join iara.education_units u on u.id = e.unit_id where e.student_id = s.id and e.status = 'ACTIVE' limit 1))
        order by s.birth_date)
      from iara.student_guardians sg join iara.students s on s.id = sg.student_id where sg.guardian_id = g.id), '[]'::jsonb),
    'household', coalesce((select jsonb_agg(iara.guardian_json(g2) || jsonb_build_object('shared_students', n) order by g2.full_name)
      from (select sg2.guardian_id, count(*) n from iara.student_guardians sg1 join iara.student_guardians sg2 on sg2.student_id = sg1.student_id
            where sg1.guardian_id = g.id and sg2.guardian_id <> g.id group by sg2.guardian_id) h join iara.guardians g2 on g2.id = h.guardian_id), '[]'::jsonb),
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

-- ---------------------------------------------------------------------------
-- Atendimentos (CRM público)
-- ---------------------------------------------------------------------------
create or replace function api.cases_list(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security invoker set search_path = iara, public
as $$
  with params as (
    select nullif(p ->> 'status', '') as status, nullif(p ->> 'case_type', '') as case_type, (p ->> 'unit_id')::int as unit_id,
           iara.norm(nullif(p ->> 'q', '')) as q, coalesce((p ->> 'mine')::boolean, false) as mine,
           coalesce((p ->> 'overdue')::boolean, false) as overdue, coalesce((p ->> 'open')::boolean, true) as only_open,
           nullif(p ->> 'channel', '') as channel, greatest(coalesce((p ->> 'page')::int, 1), 1) as page,
           least(coalesce((p ->> 'page_size')::int, 30), 100) as page_size
  ),
  base as (
    select c.* from iara.service_cases c, params x
    where (not x.only_open or iara.case_open(c.status) or x.status is not null)
      and (x.case_type is null or c.case_type = x.case_type)
      and (x.unit_id is null or c.unit_id = x.unit_id)
      and (x.channel is null or c.channel = x.channel)
      and (not x.mine or c.assigned_user_id = iara.current_user_id())
      and (not x.overdue or (c.sla_due_at < now() and iara.case_open(c.status)))
      and (x.q is null or lower(c.protocol_number) like '%' || x.q || '%' or iara.norm(c.subject) like '%' || x.q || '%')
  ),
  filtered as (select base.* from base, params x where x.status is null or base.status = x.status)
  select jsonb_build_object(
    'total', (select count(*) from filtered),
    'counts', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from base group by status) z), '{}'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'protocol', c.protocol_number, 'type', c.case_type, 'type_name', sc.name, 'status', c.status, 'priority', c.priority,
        'channel', c.channel, 'subject', c.subject, 'opened_at', c.opened_at, 'sla_due_at', c.sla_due_at,
        'overdue', c.sla_due_at < now() and iara.case_open(c.status), 'team', c.assigned_team,
        'assigned', (select display_name from iara.app_users where id = c.assigned_user_id), 'assigned_to_me', c.assigned_user_id = iara.current_user_id(),
        'student', (select jsonb_build_object('id', s.id, 'name', s.full_name, 'avatar_seed', s.avatar_seed) from iara.students s where s.id = c.student_id),
        'guardian', (select g.full_name from iara.guardians g where g.id = c.guardian_id),
        'unit', (select jsonb_build_object('id', u.id, 'name', u.short_name) from iara.education_units u where u.id = c.unit_id))
        order by case c.priority when 'URGENTE' then 0 when 'ALTA' then 1 else 2 end, c.sla_due_at nulls last, c.opened_at)
      from (select * from filtered f order by case f.priority when 'URGENTE' then 0 when 'ALTA' then 1 else 2 end, f.sla_due_at nulls last, f.opened_at
            offset ((select page from params) - 1) * (select page_size from params) limit (select page_size from params)) c
      join iara.service_catalog sc on sc.code = c.case_type), '[]'::jsonb)
  )
$$;

create or replace function api.case_detail(p jsonb) returns jsonb
language plpgsql stable security invoker set search_path = iara, public
as $$
declare
  c iara.service_cases;
  v jsonb;
begin
  select * into c from iara.service_cases where id = (p ->> 'case_id')::uuid;
  if not found then
    raise exception 'Protocolo não encontrado ou sem permissão.' using errcode = 'P0002';
  end if;
  select jsonb_build_object(
    'case', jsonb_build_object('id', c.id, 'protocol', c.protocol_number, 'type', c.case_type, 'status', c.status, 'priority', c.priority,
      'channel', c.channel, 'subject', c.subject, 'description', c.description, 'opened_at', c.opened_at, 'sla_due_at', c.sla_due_at,
      'closed_at', c.closed_at, 'resolution_code', c.resolution_code, 'resolution_notes', c.resolution_notes, 'team', c.assigned_team,
      'overdue', c.sla_due_at < now() and iara.case_open(c.status), 'open', iara.case_open(c.status),
      'assigned_user_id', c.assigned_user_id, 'assigned', (select display_name from iara.app_users where id = c.assigned_user_id),
      'assigned_to_me', c.assigned_user_id = iara.current_user_id(), 'is_demo', c.is_demo),
    'service', (select jsonb_build_object('code', sc.code, 'name', sc.name, 'sector', sc.sector, 'sla_days', sc.sla_days,
                                          'documents', sc.required_documents, 'requirements', sc.requirements) from iara.service_catalog sc where sc.code = c.case_type),
    'student', (select jsonb_build_object('id', s.id, 'name', s.full_name, 'age', iara.age_text(s.birth_date), 'birth_date', s.birth_date,
                                          'status', s.status, 'avatar_seed', s.avatar_seed, 'aee', s.aee_status, 'address', iara.address_json(s.address_id))
                from iara.students s where s.id = c.student_id),
    'guardian', (select iara.guardian_json(g) from iara.guardians g where g.id = c.guardian_id),
    'unit', (select jsonb_build_object('id', u.id, 'name', u.name, 'lat', u.lat, 'lng', u.lng) from iara.education_units u where u.id = c.unit_id),
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'type', e.event_type, 'message', e.message, 'old', e.old_value,
        'new', e.new_value, 'actor', e.actor_label, 'visibility', e.visibility, 'at', e.occurred_at) order by e.occurred_at, e.id)
      from iara.case_events e where e.case_id = c.id), '[]'::jsonb),
    'documents', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'type', d.doc_type, 'status', d.status, 'file', d.file_name,
        'received_at', d.received_at, 'validated_at', d.validated_at) order by d.doc_type)
      from iara.documents d where d.case_id = c.id or (d.student_id = c.student_id and d.case_id is null and c.student_id is not null)), '[]'::jsonb),
    'queue', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'status', w.status, 'position', w.position, 'unit', u.short_name,
        'unit_id', w.preferred_unit_id, 'grade', gl.name, 'grade_level_id', w.grade_level_id, 'score', w.priority_score, 'breakdown', w.score_breakdown,
        'category', w.demand_category, 'entered_at', w.entered_at))
      from iara.waiting_list_entries w join iara.education_units u on u.id = w.preferred_unit_id join iara.grade_levels gl on gl.id = w.grade_level_id
      where w.student_id = c.student_id and c.student_id is not null), '[]'::jsonb),
    'offers', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'status', o.status, 'unit', u.short_name, 'class', cl.class_name,
        'shift', cl.shift, 'offered_at', o.offered_at, 'expires_at', o.expires_at, 'accepted_at', o.accepted_at) order by o.offered_at desc)
      from iara.vacancy_offers o join iara.education_units u on u.id = o.unit_id join iara.classes cl on cl.id = o.class_id
      where o.student_id = c.student_id and c.student_id is not null), '[]'::jsonb),
    'conversation', (select jsonb_build_object('id', cv.id, 'state', cv.state, 'last_message_at', cv.last_message_at)
                     from iara.conversations cv where cv.active_case_id = c.id order by cv.last_message_at desc limit 1),
    'can', jsonb_build_object('write', iara.has_perm('cases.write'), 'assign', iara.has_perm('cases.assign'),
                              'queue', iara.has_perm('queue.manage'), 'offer', iara.has_perm('offers.create'))
  ) into v;
  return v;
end $$;

create or replace function api.case_create(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_scope text := iara.my_scope();
  v_key text := nullif(p ->> 'idempotency_key', '');
  v_existing iara.service_cases;
  v_type text := coalesce(p ->> 'case_type', 'SOLICITACAO_VAGA');
  v_sc iara.service_catalog;
  v_student uuid := nullif(p ->> 'student_id', '')::uuid;
  v_guardian uuid := nullif(p ->> 'guardian_id', '')::uuid;
  v_id uuid := gen_random_uuid();
  v_protocol text;
  v_unit integer := (p ->> 'unit_id')::int;
  v_channel text := coalesce(nullif(p ->> 'channel', ''), case when v_scope = 'GUARDIAN' then 'WEB' else 'PRESENCIAL' end);
begin
  if v_key is not null then
    select * into v_existing from iara.service_cases where idempotency_key = v_key;
    if found then
      return jsonb_build_object('ok', true, 'idempotent', true, 'case_id', v_existing.id, 'protocol', v_existing.protocol_number, 'status', v_existing.status);
    end if;
  end if;
  select * into v_sc from iara.service_catalog where code = v_type;
  if not found then
    raise exception 'Tipo de atendimento inválido.' using errcode = '22023';
  end if;
  if v_scope = 'GUARDIAN' then
    perform iara.require_perm('cases.write_own');
    v_guardian := iara.my_guardian();
    if v_student is not null and not exists (select 1 from iara.student_guardians where student_id = v_student and guardian_id = v_guardian) then
      raise exception 'Você só pode abrir protocolos para crianças sob sua responsabilidade.' using errcode = '42501';
    end if;
  else
    perform iara.require_perm('cases.write');
    if v_student is not null and not iara.can_access_student(v_student) then
      raise exception 'Aluno fora do seu escopo.' using errcode = '42501';
    end if;
    if v_guardian is null and v_student is not null then
      select guardian_id into v_guardian from iara.student_guardians where student_id = v_student and is_primary limit 1;
    end if;
  end if;
  if v_unit is null and v_student is not null then
    select unit_id into v_unit from iara.enrollments where student_id = v_student and status = 'ACTIVE' limit 1;
  end if;
  v_protocol := iara.next_protocol();
  insert into iara.service_cases (id, tenant_id, protocol_number, case_type, channel, status, priority, student_id, guardian_id, unit_id,
                                  assigned_team, subject, description, opened_at, sla_due_at, idempotency_key, created_by, is_demo)
  values (v_id, 1, v_protocol, v_type, v_channel, 'NOVO', coalesce(nullif(p ->> 'priority', ''), 'NORMAL'), v_student, v_guardian, v_unit,
          case v_sc.sector when 'Central de Vagas' then 'CENTRAL_VAGAS' when 'Secretaria Escolar' then 'SECRETARIA_ESCOLAR'
                           when 'Ouvidoria' then 'OUVIDORIA' else 'ATENDIMENTO' end,
          coalesce(nullif(p ->> 'subject', ''), v_sc.name), nullif(p ->> 'description', ''), now(),
          now() + make_interval(days => v_sc.sla_days), v_key, iara.current_user_id(), true);
  insert into iara.case_events (case_id, event_type, message, new_value, user_id, actor_label, visibility)
  values (v_id, 'CRIADO', 'Protocolo ' || v_protocol || ' aberto (' || lower(v_channel) || ').', 'NOVO', iara.current_user_id(), iara.my_label(), 'CIDADAO');
  if v_guardian is not null then
    insert into iara.notifications (tenant_id, guardian_id, student_id, case_id, channel, event_type, title, body)
    values (1, v_guardian, v_student, v_id, 'PORTAL', 'PROTOCOLO_CRIADO', 'Protocolo registrado',
            'Recebemos sua solicitação (' || v_sc.name || '). Protocolo ' || v_protocol || '. Prazo de análise: até ' || v_sc.sla_days || ' dia(s).');
  end if;
  perform iara.audit_event('CASE_CREATED', 'service_cases', v_id::text, v_unit, 'Protocolo ' || v_protocol || ' · ' || v_sc.name);
  return jsonb_build_object('ok', true, 'case_id', v_id, 'protocol', v_protocol, 'status', 'NOVO',
                            'sla_due_at', now() + make_interval(days => v_sc.sla_days), 'sector', v_sc.sector,
                            'next_steps', jsonb_build_array(
                              case when cardinality(v_sc.required_documents) > 0 then 'Enviar documentos: ' || array_to_string(v_sc.required_documents, ', ') end,
                              'Análise por: ' || v_sc.sector || ' (prazo de ' || v_sc.sla_days || ' dia(s))'));
end $$;

create or replace function api.case_update(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.service_cases;
  v_status text := nullif(p ->> 'status', '');
  v_note text := nullif(trim(coalesce(p ->> 'note', '')), '');
  v_assign text := p ->> 'assign';
begin
  select * into c from iara.service_cases where id = (p ->> 'case_id')::uuid for update;
  if not found or not iara.can_access_case(c.unit_id, c.student_id, c.guardian_id) then
    raise exception 'Protocolo não encontrado ou fora do seu escopo.' using errcode = 'P0002';
  end if;
  if v_assign is not null then
    perform iara.require_perm('cases.assign');
    update iara.service_cases set assigned_user_id = case when v_assign = 'me' then iara.current_user_id() else null end where id = c.id;
    insert into iara.case_events (case_id, event_type, message, user_id, actor_label)
    values (c.id, 'ATRIBUICAO', case when v_assign = 'me' then iara.my_label() || ' assumiu o atendimento.' else 'Atendimento devolvido para a fila da equipe.' end,
            iara.current_user_id(), iara.my_label());
  end if;
  if v_status is not null and v_status <> c.status then
    perform iara.require_perm('cases.write');
    if v_status not in ('NOVO', 'EM_ANALISE', 'AGUARDANDO_DOCUMENTOS', 'AGUARDANDO_FAMILIA', 'VAGA_ENCONTRADA', 'RECURSO', 'NAO_ATENDIDO', 'ENCERRADO') then
      raise exception 'Status não pode ser definido manualmente (ofertas e matrículas mudam o status pelo próprio fluxo).' using errcode = '22023';
    end if;
    if v_status in ('ENCERRADO', 'NAO_ATENDIDO') and v_note is null then
      raise exception 'Informe a resolução para encerrar o atendimento.' using errcode = '22023';
    end if;
    update iara.service_cases set status = v_status,
           closed_at = case when v_status in ('ENCERRADO', 'NAO_ATENDIDO') then now() end,
           resolution_code = case when v_status in ('ENCERRADO', 'NAO_ATENDIDO') then coalesce(nullif(p ->> 'resolution_code', ''), 'RESOLVIDO') end,
           resolution_notes = case when v_status in ('ENCERRADO', 'NAO_ATENDIDO') then v_note end
    where id = c.id;
    insert into iara.case_events (case_id, event_type, message, old_value, new_value, user_id, actor_label, visibility)
    values (c.id, 'STATUS', coalesce(v_note, 'Status atualizado.'), c.status, v_status, iara.current_user_id(), iara.my_label(), 'CIDADAO');
    if c.guardian_id is not null then
      insert into iara.notifications (tenant_id, guardian_id, student_id, case_id, channel, event_type, title, body)
      values (1, c.guardian_id, c.student_id, c.id, 'PORTAL', 'STATUS', 'Atualização do protocolo ' || c.protocol_number,
              'Novo status: ' || replace(initcap(replace(v_status, '_', ' ')), ' ', ' ') || coalesce('. ' || v_note, '.'));
    end if;
  elsif v_note is not null then
    perform iara.require_perm('cases.write');
    insert into iara.case_events (case_id, event_type, message, user_id, actor_label, visibility)
    values (c.id, 'NOTA', v_note, iara.current_user_id(), iara.my_label(), coalesce(nullif(p ->> 'visibility', ''), 'INTERNA'));
  end if;
  return api.case_detail(jsonb_build_object('case_id', c.id));
end $$;

-- ---------------------------------------------------------------------------
-- Fila de espera
-- ---------------------------------------------------------------------------
create or replace function api.queue_list(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security invoker set search_path = iara, public
as $$
  with params as (
    select (p ->> 'unit_id')::int as unit_id, (p ->> 'grade_level_id')::smallint as grade, (p ->> 'territory_id')::int as territory,
           nullif(p ->> 'category', '') as category, coalesce(nullif(p ->> 'status', ''), 'WAITING') as status, iara.norm(nullif(p ->> 'q', '')) as q,
           greatest(coalesce((p ->> 'page')::int, 1), 1) as page, least(coalesce((p ->> 'page_size')::int, 40), 100) as page_size
  ),
  base as (
    select w.*, u.short_name as unit_name, u.macro_territory_id, s.full_name, s.birth_date, s.avatar_seed, gl.name as grade_name
    from iara.waiting_list_entries w join iara.students s on s.id = w.student_id
    join iara.education_units u on u.id = w.preferred_unit_id join iara.grade_levels gl on gl.id = w.grade_level_id, params x
    where (x.unit_id is null or w.preferred_unit_id = x.unit_id) and (x.grade is null or w.grade_level_id = x.grade)
      and (x.territory is null or u.macro_territory_id = x.territory) and (x.category is null or w.demand_category = x.category)
      and (x.status = 'ALL' or w.status = x.status) and (x.q is null or iara.norm(s.full_name) like '%' || x.q || '%')
  )
  select jsonb_build_object(
    'total', (select count(*) from base),
    'by_category', coalesce((select jsonb_object_agg(demand_category, n) from (select demand_category, count(*) n from base group by 1) z), '{}'::jsonb),
    'by_grade', coalesce((select jsonb_object_agg(grade_name, n) from (select grade_name, count(*) n from base group by 1) z), '{}'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', b.id, 'student_id', b.student_id, 'student', b.full_name, 'age', iara.age_text(b.birth_date), 'avatar_seed', b.avatar_seed,
        'unit_id', b.preferred_unit_id, 'unit', b.unit_name, 'grade', b.grade_name, 'grade_level_id', b.grade_level_id,
        'position', b.position, 'score', b.priority_score, 'flags', b.priority_flags, 'category', b.demand_category, 'status', b.status,
        'entered_at', b.entered_at, 'days_waiting', (current_date - b.entered_at::date), 'distance_m', b.home_distance_m,
        'shift', b.preferred_shift, 'full_time', b.full_time_requested)
        order by b.preferred_unit_id, b.grade_level_id, b.position nulls last, b.entered_at)
      from (select * from base order by unit_name, grade_level_id, position nulls last, entered_at
            offset ((select page from params) - 1) * (select page_size from params) limit (select page_size from params)) b), '[]'::jsonb)
  )
$$;

create or replace function api.queue_entry_detail(p jsonb) returns jsonb
language plpgsql stable security invoker set search_path = iara, public
as $$
declare
  w iara.waiting_list_entries;
  v jsonb;
begin
  select * into w from iara.waiting_list_entries where id = (p ->> 'entry_id')::uuid;
  if not found then
    raise exception 'Entrada de fila não encontrada ou sem permissão.' using errcode = 'P0002';
  end if;
  select jsonb_build_object(
    'entry', jsonb_build_object('id', w.id, 'status', w.status, 'position', w.position, 'score', w.priority_score, 'flags', w.priority_flags,
      'breakdown', w.score_breakdown, 'category', w.demand_category, 'entered_at', w.entered_at, 'rule_version', w.rule_version,
      'last_recalculated_at', w.last_recalculated_at, 'distance_m', w.home_distance_m, 'shift', w.preferred_shift,
      'full_time', w.full_time_requested, 'case_id', w.case_id, 'grade_level_id', w.grade_level_id,
      'grade', (select name from iara.grade_levels where id = w.grade_level_id),
      'queue_size', (select count(*) from iara.waiting_list_entries x where x.preferred_unit_id = w.preferred_unit_id and x.grade_level_id = w.grade_level_id and x.status = 'WAITING')),
    'student', (select jsonb_build_object('id', s.id, 'name', s.full_name, 'age', iara.age_text(s.birth_date), 'birth_date', s.birth_date,
                                          'avatar_seed', s.avatar_seed, 'address', iara.address_json(s.address_id)) from iara.students s where s.id = w.student_id),
    'unit', (select jsonb_build_object('id', u.id, 'name', u.name, 'lat', u.lat, 'lng', u.lng) from iara.education_units u where u.id = w.preferred_unit_id),
    'classes', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.class_name, 'shift', c.shift, 'capacity', c.authorized_capacity,
        'enrolled', c.active_enrollments_count, 'blocked', c.blocked_seats_count, 'reserved', c.reserved_seats_count, 'offerable', c.offerable_vacancies_count)
        order by c.offerable_vacancies_count desc, c.class_code)
      from iara.classes c where c.unit_id = w.preferred_unit_id and c.grade_level_id = w.grade_level_id and c.status = 'ATIVA'), '[]'::jsonb),
    'can_offer_now', w.status = 'WAITING' and w.position = 1 and exists (select 1 from iara.classes c where c.unit_id = w.preferred_unit_id
                       and c.grade_level_id = w.grade_level_id and c.offerable_vacancies_count > 0),
    'offers', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'status', o.status, 'class', c.class_name, 'offered_at', o.offered_at,
        'expires_at', o.expires_at, 'decline_reason', o.decline_reason) order by o.offered_at desc)
      from iara.vacancy_offers o join iara.classes c on c.id = o.class_id where o.waiting_list_entry_id = w.id), '[]'::jsonb),
    'rules', (select coalesce(jsonb_agg(jsonb_build_object('code', rule_code, 'name', name, 'weight', weight, 'version', version, 'source', source)
                                        order by sort), '[]'::jsonb) from iara.rules where rule_type in ('PRIORIDADE_FILA', 'DESEMPATE') and is_active)
  ) into v;
  return v;
end $$;

create or replace function api.queue_entry_create(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_unit integer := (p ->> 'preferred_unit_id')::int;
  v_grade smallint := (p ->> 'grade_level_id')::smallint;
  v_case uuid := nullif(p ->> 'case_id', '')::uuid;
  v_entry uuid := gen_random_uuid();
  v_rule jsonb;
  v_flags text[] := '{}';
  v_pos integer;
  s iara.students;
begin
  perform iara.require_perm('queue.manage');
  select * into s from iara.students where id = v_student;
  if not found or not iara.can_access_student(v_student) then
    raise exception 'Aluno não encontrado ou fora do seu escopo.' using errcode = 'P0002';
  end if;
  if v_grade is null then
    v_rule := iara.grade_for_birthdate(s.birth_date);
    if not coalesce((v_rule ->> 'ok')::boolean, false) then
      raise exception '%', v_rule ->> 'explanation' using errcode = '22023';
    end if;
    v_grade := (v_rule ->> 'grade_level_id')::smallint;
  end if;
  if not exists (select 1 from iara.classes c where c.unit_id = v_unit and c.grade_level_id = v_grade and c.status = 'ATIVA') then
    raise exception 'A unidade escolhida não atende esta faixa/série.' using errcode = '22023';
  end if;
  if exists (select 1 from iara.waiting_list_entries w where w.student_id = v_student and w.grade_level_id = v_grade
               and w.preferred_unit_id = v_unit and w.status in ('WAITING', 'OFFERED', 'ACCEPTED')) then
    raise exception 'A criança já está na fila desta unidade/faixa.' using errcode = '23505';
  end if;
  if coalesce((p ->> 'vulnerability')::boolean, false) then
    if length(coalesce(p ->> 'vulnerability_note', '')) < 15 then
      raise exception 'O critério de rede de proteção exige justificativa (encaminhamento formal) com pelo menos 15 caracteres.' using errcode = '22023';
    end if;
    v_flags := array['VULNERABILIDADE'];
  end if;
  insert into iara.waiting_list_entries (id, tenant_id, student_id, case_id, stage_id, grade_level_id, preferred_unit_id, territory_id,
                                         preferred_shift, full_time_requested, demand_category, priority_flags, entered_at, status, created_by, is_demo)
  select v_entry, 1, v_student, v_case, gl.stage_id, v_grade, v_unit, u.macro_territory_id, nullif(p ->> 'preferred_shift', ''),
         coalesce((p ->> 'full_time')::boolean, false), coalesce(nullif(p ->> 'category', ''),
           case when exists (select 1 from iara.enrollments e where e.student_id = v_student and e.status = 'ACTIVE') then 'AGUARDA_TRANSFERENCIA' else 'SEM_ATENDIMENTO' end),
         v_flags, now(), 'WAITING', iara.current_user_id(), true
  from iara.grade_levels gl, iara.education_units u where gl.id = v_grade and u.id = v_unit;
  perform iara.compute_queue_priority(v_entry);
  perform iara.recalculate_queue(v_unit, v_grade);
  update iara.students set status = 'AGUARDANDO_VAGA' where id = v_student and status = 'SEM_VINCULO';
  select position into v_pos from iara.waiting_list_entries where id = v_entry;
  if v_case is not null then
    update iara.service_cases set status = 'ENCERRADO', closed_at = now(), resolution_code = 'INSERIDO_NA_FILA',
           resolution_notes = 'Sem vaga ofertável compatível; criança inserida na fila.' where id = v_case and iara.case_open(status);
    insert into iara.case_events (case_id, event_type, message, new_value, user_id, actor_label, visibility)
    values (v_case, 'FILA', format('Criança inserida na fila (%s) — posição %s pelas regras %s.', (select name from iara.grade_levels where id = v_grade), v_pos, iara.rule_version()),
            'EM_FILA', iara.current_user_id(), iara.my_label(), 'CIDADAO');
  end if;
  insert into iara.notifications (tenant_id, guardian_id, student_id, case_id, channel, event_type, title, body)
  select 1, sg.guardian_id, v_student, v_case, 'PORTAL', 'FILA', 'Inserção na fila',
         format('%s entrou na fila de %s da %s. Posição atual: %s. Os critérios aplicados podem ser consultados no portal.',
                split_part(s.full_name, ' ', 1), (select name from iara.grade_levels where id = v_grade), (select name from iara.education_units where id = v_unit), v_pos)
  from iara.student_guardians sg where sg.student_id = v_student and sg.is_primary;
  if cardinality(v_flags) > 0 then
    perform iara.audit_event('PRIORITY_FLAG', 'waiting_list_entries', v_entry::text, v_unit, 'Critério rede de proteção: ' || (p ->> 'vulnerability_note'));
  end if;
  return api.queue_entry_detail(jsonb_build_object('entry_id', v_entry));
end $$;

create or replace function api.queue_recalculate(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_unit integer := (p ->> 'unit_id')::int;
  v_grade smallint := (p ->> 'grade_level_id')::smallint;
  v_before jsonb;
  v_after jsonb;
  v_n integer;
  v_changed integer;
begin
  perform iara.require_perm('queue.recalculate');
  select coalesce(jsonb_object_agg(id, position), '{}'::jsonb) into v_before from iara.waiting_list_entries
  where preferred_unit_id = v_unit and grade_level_id = v_grade and status = 'WAITING';
  perform iara.compute_queue_priority(id) from iara.waiting_list_entries
  where preferred_unit_id = v_unit and grade_level_id = v_grade and status = 'WAITING';
  v_n := iara.recalculate_queue(v_unit, v_grade);
  select coalesce(jsonb_object_agg(id, position), '{}'::jsonb) into v_after from iara.waiting_list_entries
  where preferred_unit_id = v_unit and grade_level_id = v_grade and status = 'WAITING';
  select count(*) into v_changed from jsonb_each(v_after) a where v_before -> a.key is distinct from a.value;
  perform iara.audit_event('QUEUE_RECALCULATED', 'queue', v_unit || ':' || v_grade, v_unit,
                           format('Fila recalculada pelas regras %s: %s criança(s), %s posição(ões) alterada(s).', iara.rule_version(), v_n, v_changed));
  return jsonb_build_object('ok', true, 'entries', v_n, 'changed', v_changed, 'rule_version', iara.rule_version());
end $$;

-- ---------------------------------------------------------------------------
-- Ofertas e matrícula (transacionais, idempotentes, com revalidação de vaga)
-- ---------------------------------------------------------------------------
create or replace function iara.class_snapshot(p_class uuid) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('capacity', authorized_capacity, 'enrolled', active_enrollments_count, 'blocked', blocked_seats_count,
                            'reserved', reserved_seats_count, 'offerable', offerable_vacancies_count)
  from iara.classes where id = p_class
$$;

create or replace function api.offer_create(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_key text := coalesce(nullif(p ->> 'idempotency_key', ''), 'auto-' || (p ->> 'entry_id') || '-' || (p ->> 'class_id'));
  o iara.vacancy_offers;
  w iara.waiting_list_entries;
  c iara.classes;
  v_before jsonb;
  v_hours integer := coalesce((iara.rule('PRAZO_RESPOSTA_OFERTA')).condition ->> 'hours', '48')::int;
  v_offer uuid := gen_random_uuid();
  v_unit_name text;
  v_child text;
begin
  perform iara.require_perm('offers.create');
  select * into o from iara.vacancy_offers where idempotency_key = v_key;
  if found then
    return jsonb_build_object('ok', true, 'idempotent', true, 'offer_id', o.id, 'status', o.status, 'expires_at', o.expires_at);
  end if;
  select * into w from iara.waiting_list_entries where id = (p ->> 'entry_id')::uuid for update;
  if not found or not iara.can_access_student(w.student_id) then
    raise exception 'Entrada de fila não encontrada ou fora do seu escopo.' using errcode = 'P0002';
  end if;
  if w.status <> 'WAITING' then
    raise exception 'Esta criança não está aguardando (situação atual: %).', w.status using errcode = '22023';
  end if;
  select * into c from iara.classes where id = (p ->> 'class_id')::uuid for update;
  if not found then
    raise exception 'Turma não encontrada.' using errcode = 'P0002';
  end if;
  if c.grade_level_id <> w.grade_level_id then
    raise exception 'A turma não corresponde à faixa/série da criança.' using errcode = '22023';
  end if;
  if c.unit_id <> w.preferred_unit_id and not (c.unit_id = any (w.alternative_unit_ids)) then
    raise exception 'A turma é de outra unidade. Registre a unidade como alternativa aceita pela família antes de ofertar.' using errcode = '22023';
  end if;
  if c.status <> 'ATIVA' then
    raise exception 'Turma não está ativa.' using errcode = '22023';
  end if;
  if c.offerable_vacancies_count < 1 then
    raise exception 'Sem vaga ofertável nesta turma: capacidade %, matrículas %, bloqueadas %, reservadas %.',
      c.authorized_capacity, c.active_enrollments_count, c.blocked_seats_count, c.reserved_seats_count using errcode = '22023';
  end if;
  if c.unit_id = w.preferred_unit_id and coalesce(w.position, 999) <> 1 then
    raise exception 'Há % criança(s) à frente na fila desta unidade/faixa. A oferta deve seguir a ordem de classificação.',
      coalesce(w.position, 1) - 1 using errcode = '22023';
  end if;
  v_before := iara.class_snapshot(c.id);
  insert into iara.vacancy_offers (id, tenant_id, waiting_list_entry_id, student_id, class_id, unit_id, case_id, offered_at, expires_at, channel,
                                   status, ranking_snapshot, idempotency_key, created_by, is_demo)
  values (v_offer, 1, w.id, w.student_id, c.id, c.unit_id, w.case_id, now(), now() + make_interval(hours => v_hours),
          coalesce(nullif(p ->> 'channel', ''), 'WHATSAPP'), 'OFFERED',
          jsonb_build_object('position', w.position, 'score', w.priority_score, 'breakdown', w.score_breakdown, 'rule_version', iara.rule_version(),
                             'class_before', v_before, 'note', nullif(p ->> 'note', '')),
          v_key, iara.current_user_id(), true);
  update iara.waiting_list_entries set status = 'OFFERED' where id = w.id;
  perform iara.recalculate_queue(w.preferred_unit_id, w.grade_level_id);
  select name into v_unit_name from iara.education_units where id = c.unit_id;
  select split_part(full_name, ' ', 1) into v_child from iara.students where id = w.student_id;
  if w.case_id is not null then
    update iara.service_cases set status = 'VAGA_OFERTADA', closed_at = null, resolution_code = null, resolution_notes = null,
           sla_due_at = now() + make_interval(hours => v_hours) where id = w.case_id;
    insert into iara.case_events (case_id, event_type, message, new_value, user_id, actor_label, visibility)
    values (w.case_id, 'OFERTA', format('Vaga ofertada: %s · %s (%s). Prazo de resposta: %s horas.', v_unit_name, c.class_name, lower(c.shift), v_hours),
            'VAGA_OFERTADA', iara.current_user_id(), iara.my_label(), 'CIDADAO');
  end if;
  insert into iara.notifications (tenant_id, guardian_id, student_id, case_id, channel, event_type, title, body)
  select 1, sg.guardian_id, w.student_id, w.case_id, ch, 'VAGA_OFERTADA', 'Vaga ofertada para ' || v_child,
         format('Há uma vaga para %s na %s (%s, turno %s). Responda até %s. Aceitar não é a matrícula: depois a unidade confere os documentos.',
                v_child, v_unit_name, c.class_name, lower(c.shift), to_char((now() + make_interval(hours => v_hours)) at time zone 'America/Sao_Paulo', 'DD/MM às HH24:MI'))
  from iara.student_guardians sg cross join (values ('WHATSAPP'), ('PORTAL')) x(ch)
  where sg.student_id = w.student_id and sg.is_primary;
  insert into iara.vacancy_events (tenant_id, class_id, unit_id, event_type, quantity, before_json, after_json, reference, user_id, actor_label)
  values (1, c.id, c.unit_id, 'RESERVA', 1, v_before, iara.class_snapshot(c.id), 'Oferta ' || substr(v_offer::text, 1, 8), iara.current_user_id(), iara.my_label());
  perform iara.audit_event('OFFER_CREATED', 'vacancy_offers', v_offer::text, c.unit_id,
                           format('Oferta de vaga a %s (1º da fila, pontuação %s) — %s · %s', v_child, w.priority_score, v_unit_name, c.class_name),
                           jsonb_build_object('entry', w.id, 'class', c.id, 'rule_version', iara.rule_version()));
  return jsonb_build_object('ok', true, 'offer_id', v_offer, 'status', 'OFFERED', 'expires_at', now() + make_interval(hours => v_hours),
                            'class_after', iara.class_snapshot(c.id),
                            'message', format('Oferta registrada e família notificada (simulado). Prazo: %s horas.', v_hours));
end $$;

create or replace function api.offer_respond(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  o iara.vacancy_offers;
  v_accept boolean := (p ->> 'accept')::boolean;
  v_reason text := nullif(trim(coalesce(p ->> 'reason', '')), '');
  v_child text;
  v_unit_name text;
  v_class text;
  v_missing text[];
  v_grade smallint;
begin
  if v_accept is null then
    raise exception 'Informe se a família aceita ou recusa a oferta.' using errcode = '22023';
  end if;
  select * into o from iara.vacancy_offers where id = (p ->> 'offer_id')::uuid for update;
  if not found then
    raise exception 'Oferta não encontrada.' using errcode = 'P0002';
  end if;
  if iara.my_scope() = 'GUARDIAN' then
    perform iara.require_perm('offers.respond_own');
    if not exists (select 1 from iara.student_guardians where student_id = o.student_id and guardian_id = iara.my_guardian()) then
      raise exception 'Esta oferta não é de uma criança sob sua responsabilidade.' using errcode = '42501';
    end if;
  else
    perform iara.require_perm('offers.respond');
    if not iara.can_access_student(o.student_id) then
      raise exception 'Fora do seu escopo.' using errcode = '42501';
    end if;
  end if;
  if o.status <> 'OFFERED' then
    raise exception 'Esta oferta não está aguardando resposta (situação: %).', o.status using errcode = '22023';
  end if;
  if o.expires_at < now() then
    perform iara.expire_due_offers();
    raise exception 'O prazo desta oferta terminou. A vaga foi liberada e a criança continua na fila.' using errcode = '22023';
  end if;
  select split_part(s.full_name, ' ', 1), u.name, c.class_name, c.grade_level_id into v_child, v_unit_name, v_class, v_grade
  from iara.students s, iara.education_units u, iara.classes c where s.id = o.student_id and u.id = o.unit_id and c.id = o.class_id;

  if v_accept then
    update iara.vacancy_offers set status = 'ACCEPTED', accepted_at = now(), response_channel = coalesce(nullif(p ->> 'channel', ''), 'PORTAL') where id = o.id;
    update iara.waiting_list_entries set status = 'ACCEPTED' where id = o.waiting_list_entry_id;
    select coalesce(array_agg(d), '{}') into v_missing
    from unnest((select required_documents from iara.service_catalog where code = 'MATRICULA')) d
    where not exists (select 1 from iara.documents x where x.student_id = o.student_id and x.doc_type = d and x.status = 'VALIDADO');
    if o.case_id is not null then
      insert into iara.case_events (case_id, event_type, message, new_value, user_id, actor_label, visibility)
      values (o.case_id, 'OFERTA', 'Aceite registrado. Aceite não é matrícula: a unidade vai conferir os documentos e confirmar a matrícula.',
              'ACEITE', iara.current_user_id(), iara.my_label(), 'CIDADAO');
    end if;
    insert into iara.notifications (tenant_id, guardian_id, student_id, case_id, channel, event_type, title, body)
    select 1, sg.guardian_id, o.student_id, o.case_id, 'PORTAL', 'ACEITE', 'Aceite registrado',
           format('Recebemos o aceite da vaga de %s na %s. Próximo passo: a unidade confere os documentos e confirma a matrícula.%s',
                  v_child, v_unit_name, case when cardinality(v_missing) > 0 then ' Pendentes: ' || array_to_string(v_missing, ', ') || '.' else '' end)
    from iara.student_guardians sg where sg.student_id = o.student_id and sg.is_primary;
    perform iara.audit_event('OFFER_ACCEPTED', 'vacancy_offers', o.id::text, o.unit_id, 'Aceite registrado para ' || v_child || ' (' || v_class || ')');
    return jsonb_build_object('ok', true, 'status', 'ACCEPTED', 'missing_documents', to_jsonb(v_missing),
      'message', 'Aceite registrado. Aceitar não é a matrícula: a unidade vai conferir os documentos e confirmar.');
  else
    if v_reason is null then
      raise exception 'Informe o motivo da recusa.' using errcode = '22023';
    end if;
    update iara.vacancy_offers set status = 'DECLINED', declined_at = now(), decline_reason = v_reason,
           response_channel = coalesce(nullif(p ->> 'channel', ''), 'PORTAL') where id = o.id;
    update iara.waiting_list_entries set status = 'WAITING', demand_category = 'RECUSOU_OFERTA' where id = o.waiting_list_entry_id;
    perform iara.recalculate_queue(o.unit_id, v_grade);
    if o.case_id is not null then
      update iara.service_cases set status = 'ENCERRADO', closed_at = now(), resolution_code = 'OFERTA_RECUSADA',
             resolution_notes = 'Oferta recusada pela família; criança mantida na fila conforme regra vigente.' where id = o.case_id;
      insert into iara.case_events (case_id, event_type, message, old_value, new_value, user_id, actor_label, visibility)
      values (o.case_id, 'OFERTA', 'Recusa registrada: ' || v_reason || '. Pela regra vigente, a criança volta à fila sem perder a pontuação.',
              'VAGA_OFERTADA', 'ENCERRADO', iara.current_user_id(), iara.my_label(), 'CIDADAO');
    end if;
    insert into iara.vacancy_events (tenant_id, class_id, unit_id, event_type, quantity, reference, user_id, actor_label)
    values (1, o.class_id, o.unit_id, 'LIBERACAO', 1, 'Recusa da oferta ' || substr(o.id::text, 1, 8), iara.current_user_id(), iara.my_label());
    perform iara.audit_event('OFFER_DECLINED', 'vacancy_offers', o.id::text, o.unit_id, 'Recusa registrada (' || v_reason || ')');
    return jsonb_build_object('ok', true, 'status', 'DECLINED',
      'message', 'Recusa registrada. Pela regra vigente, a criança continua na fila sem perder a pontuação.');
  end if;
end $$;

create or replace function api.enrollment_confirm(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  o iara.vacancy_offers;
  v_missing text[];
  v_before jsonb;
  v_enr uuid := gen_random_uuid();
  v_prev record;
  v_child text;
begin
  perform iara.require_perm('enrollment.confirm');
  select * into o from iara.vacancy_offers where id = (p ->> 'offer_id')::uuid for update;
  if not found or not iara.can_access_unit(o.unit_id) then
    raise exception 'Oferta não encontrada ou de outra unidade.' using errcode = 'P0002';
  end if;
  if o.status <> 'ACCEPTED' then
    raise exception 'A matrícula só pode ser confirmada após o aceite da família (situação atual: %).', o.status using errcode = '22023';
  end if;
  select coalesce(array_agg(d), '{}') into v_missing
  from unnest((select required_documents from iara.service_catalog where code = 'MATRICULA')) d
  where not exists (select 1 from iara.documents x where x.student_id = o.student_id and x.doc_type = d and x.status = 'VALIDADO');
  if cardinality(v_missing) > 0 then
    return jsonb_build_object('ok', false, 'missing_documents', to_jsonb(v_missing),
                              'message', 'Faltam documentos validados para concluir a matrícula: ' || array_to_string(v_missing, ', ') || '.');
  end if;
  v_before := iara.class_snapshot(o.class_id);
  select e.id, e.class_id, e.unit_id into v_prev from iara.enrollments e where e.student_id = o.student_id and e.status = 'ACTIVE' limit 1;
  if v_prev.id is not null then
    update iara.enrollments set status = 'TRANSFERRED', exit_type = 'TRANSFERENCIA_INTERNA', end_date = current_date where id = v_prev.id;
    insert into iara.vacancy_events (tenant_id, class_id, unit_id, event_type, quantity, reference, user_id, actor_label)
    values (1, v_prev.class_id, v_prev.unit_id, 'TRANSF_SAIDA', 1, 'Transferência interna ' || substr(o.id::text, 1, 8), iara.current_user_id(), iara.my_label());
  end if;
  insert into iara.enrollments (id, tenant_id, student_id, class_id, unit_id, school_year, status, enrollment_date, start_date, entry_type,
                                source_protocol_id, previous_enrollment_id, created_by, is_demo)
  values (v_enr, 1, o.student_id, o.class_id, o.unit_id, iara.school_year(), 'ACTIVE', current_date, current_date,
          case when v_prev.id is not null then 'TRANSFERENCIA' else 'OFERTA_FILA' end, o.case_id, v_prev.id, iara.current_user_id(), true);
  update iara.vacancy_offers set status = 'ENROLLED' where id = o.id;
  update iara.waiting_list_entries set status = 'MATRICULATED' where id = o.waiting_list_entry_id;
  update iara.students set status = 'MATRICULADO', current_enrollment_id = v_enr where id = o.student_id;
  select split_part(full_name, ' ', 1) into v_child from iara.students where id = o.student_id;
  if o.case_id is not null then
    update iara.service_cases set status = 'MATRICULA_CONCLUIDA', closed_at = now(), resolution_code = 'MATRICULADO',
           resolution_notes = 'Matrícula confirmada pela unidade.' where id = o.case_id;
    insert into iara.case_events (case_id, event_type, message, old_value, new_value, user_id, actor_label, visibility)
    values (o.case_id, 'MATRICULA', 'Matrícula confirmada pela unidade. Atendimento concluído.', 'VAGA_OFERTADA', 'MATRICULA_CONCLUIDA',
            iara.current_user_id(), iara.my_label(), 'CIDADAO');
  end if;
  insert into iara.notifications (tenant_id, guardian_id, student_id, case_id, channel, event_type, title, body)
  select 1, sg.guardian_id, o.student_id, o.case_id, ch, 'MATRICULA', 'Matrícula confirmada! 🎉',
         format('A matrícula de %s na %s está confirmada (%s). Bem-vindo(a) à rede municipal de Maringá!', v_child,
                (select name from iara.education_units where id = o.unit_id), (select class_name from iara.classes where id = o.class_id))
  from iara.student_guardians sg cross join (values ('WHATSAPP'), ('PORTAL')) x(ch) where sg.student_id = o.student_id and sg.is_primary;
  insert into iara.vacancy_events (tenant_id, class_id, unit_id, event_type, quantity, before_json, after_json, reference, user_id, actor_label)
  values (1, o.class_id, o.unit_id, 'MATRICULA', 1, v_before, iara.class_snapshot(o.class_id), 'Oferta ' || substr(o.id::text, 1, 8), iara.current_user_id(), iara.my_label());
  perform iara.audit_event('ENROLLMENT_CONFIRMED', 'enrollments', v_enr::text, o.unit_id, 'Matrícula confirmada a partir da oferta ' || substr(o.id::text, 1, 8));
  return jsonb_build_object('ok', true, 'enrollment_id', v_enr, 'class_after', iara.class_snapshot(o.class_id),
                            'message', 'Matrícula confirmada. A família foi notificada (simulado).');
end $$;

create or replace function api.offers_list(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security invoker set search_path = iara, public
as $$
  select jsonb_build_object('items', coalesce(jsonb_agg(jsonb_build_object(
      'id', o.id, 'status', o.status, 'student_id', s.id, 'student', s.full_name, 'avatar_seed', s.avatar_seed, 'unit_id', u.id, 'unit', u.short_name,
      'class_id', c.id, 'class', c.class_name, 'shift', c.shift, 'offered_at', o.offered_at, 'expires_at', o.expires_at,
      'accepted_at', o.accepted_at, 'case_id', o.case_id,
      'hours_left', round(extract(epoch from (o.expires_at - now())) / 3600.0, 1),
      'missing_documents', (select coalesce(jsonb_agg(d), '[]'::jsonb) from unnest((select required_documents from iara.service_catalog where code = 'MATRICULA')) d
                            where not exists (select 1 from iara.documents x where x.student_id = o.student_id and x.doc_type = d and x.status = 'VALIDADO')))
      order by case o.status when 'ACCEPTED' then 0 else 1 end, o.expires_at), '[]'::jsonb))
  from iara.vacancy_offers o join iara.students s on s.id = o.student_id join iara.education_units u on u.id = o.unit_id join iara.classes c on c.id = o.class_id
  where o.status = any (coalesce((select array_agg(x) from jsonb_array_elements_text(p -> 'status') x), array['OFFERED', 'ACCEPTED']))
    and ((p ->> 'unit_id') is null or o.unit_id = (p ->> 'unit_id')::int)
$$;

-- ---------------------------------------------------------------------------
-- Documentos
-- ---------------------------------------------------------------------------
create or replace function api.document_set(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_type text := p ->> 'doc_type';
  v_status text := p ->> 'status';
  d iara.documents;
begin
  if iara.my_scope() = 'GUARDIAN' then
    perform iara.require_perm('documents.submit_own');
    if not exists (select 1 from iara.student_guardians where student_id = v_student and guardian_id = iara.my_guardian()) then
      raise exception 'Documento de criança fora da sua responsabilidade.' using errcode = '42501';
    end if;
    if v_status <> 'RECEBIDO' then
      raise exception 'O responsável pode apenas enviar documentos; a validação é feita pela unidade.' using errcode = '42501';
    end if;
  else
    perform iara.require_perm('documents.manage');
    if not iara.can_access_student(v_student) then
      raise exception 'Aluno fora do seu escopo.' using errcode = '42501';
    end if;
  end if;
  if v_status not in ('PENDENTE', 'RECEBIDO', 'VALIDADO', 'REJEITADO') then
    raise exception 'Status de documento inválido.' using errcode = '22023';
  end if;
  select * into d from iara.documents where student_id = v_student and doc_type = v_type order by created_at desc limit 1 for update;
  if found then
    update iara.documents set status = v_status,
           received_at = case when v_status in ('RECEBIDO', 'VALIDADO') then coalesce(received_at, now()) else received_at end,
           validated_at = case when v_status = 'VALIDADO' then now() end,
           validated_by = case when v_status = 'VALIDADO' then iara.current_user_id() end,
           file_name = coalesce(file_name, case when v_status in ('RECEBIDO', 'VALIDADO') then lower(v_type) || '_recebido.pdf' end),
           notes = coalesce(nullif(p ->> 'notes', ''), notes)
    where id = d.id returning * into d;
  else
    insert into iara.documents (tenant_id, student_id, case_id, doc_type, status, file_name, received_at, validated_at, validated_by, notes, is_demo)
    values (1, v_student, nullif(p ->> 'case_id', '')::uuid, v_type, v_status,
            case when v_status in ('RECEBIDO', 'VALIDADO') then lower(v_type) || '_recebido.pdf' end,
            case when v_status in ('RECEBIDO', 'VALIDADO') then now() end, case when v_status = 'VALIDADO' then now() end,
            case when v_status = 'VALIDADO' then iara.current_user_id() end, nullif(p ->> 'notes', ''), true)
    returning * into d;
  end if;
  return jsonb_build_object('ok', true, 'document', jsonb_build_object('id', d.id, 'type', d.doc_type, 'status', d.status,
                            'received_at', d.received_at, 'validated_at', d.validated_at));
end $$;

-- ---------------------------------------------------------------------------
-- Bloqueio de vagas (motivo e justificativa obrigatórios)
-- ---------------------------------------------------------------------------
create or replace function api.vacancy_block(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.classes;
  v_seats integer := coalesce((p ->> 'seats')::int, 1);
  v_before jsonb;
  v_id uuid;
begin
  perform iara.require_perm('vacancy.block');
  select * into c from iara.classes where id = (p ->> 'class_id')::uuid for update;
  if not found or not iara.can_access_unit(c.unit_id) then
    raise exception 'Turma não encontrada ou de outra unidade.' using errcode = 'P0002';
  end if;
  if v_seats < 1 or v_seats > c.offerable_vacancies_count then
    raise exception 'Só é possível bloquear vagas ofertáveis (disponíveis agora: %).', c.offerable_vacancies_count using errcode = '22023';
  end if;
  if length(coalesce(p ->> 'justification', '')) < 10 then
    raise exception 'Justificativa obrigatória (mínimo de 10 caracteres).' using errcode = '22023';
  end if;
  v_before := iara.class_snapshot(c.id);
  insert into iara.vacancy_blocks (tenant_id, class_id, seats, reason, justification, valid_until, created_by, is_demo)
  values (1, c.id, v_seats, p ->> 'reason', p ->> 'justification', nullif(p ->> 'valid_until', '')::date, iara.current_user_id(), true)
  returning id into v_id;
  insert into iara.vacancy_events (tenant_id, class_id, unit_id, event_type, quantity, before_json, after_json, reference, user_id, actor_label)
  values (1, c.id, c.unit_id, 'BLOQUEIO', v_seats, v_before, iara.class_snapshot(c.id), p ->> 'reason', iara.current_user_id(), iara.my_label());
  return jsonb_build_object('ok', true, 'block_id', v_id, 'class_after', iara.class_snapshot(c.id));
end $$;

create or replace function api.vacancy_unblock(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  b iara.vacancy_blocks;
  c iara.classes;
  v_before jsonb;
begin
  perform iara.require_perm('vacancy.block');
  select * into b from iara.vacancy_blocks where id = (p ->> 'block_id')::uuid for update;
  if not found or b.released_at is not null then
    raise exception 'Bloqueio não encontrado ou já liberado.' using errcode = 'P0002';
  end if;
  select * into c from iara.classes where id = b.class_id;
  if not iara.can_access_unit(c.unit_id) then
    raise exception 'Bloqueio de outra unidade.' using errcode = '42501';
  end if;
  v_before := iara.class_snapshot(c.id);
  update iara.vacancy_blocks set released_at = now(), released_by = iara.current_user_id() where id = b.id;
  insert into iara.vacancy_events (tenant_id, class_id, unit_id, event_type, quantity, before_json, after_json, reference, user_id, actor_label)
  values (1, c.id, c.unit_id, 'DESBLOQUEIO', b.seats, v_before, iara.class_snapshot(c.id), b.reason, iara.current_user_id(), iara.my_label());
  return jsonb_build_object('ok', true, 'class_after', iara.class_snapshot(c.id));
end $$;

-- ---------------------------------------------------------------------------
-- Cadastro de aluno / responsável / vínculo (com deduplicação)
-- ---------------------------------------------------------------------------
create or replace function api.guardian_create(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id uuid := gen_random_uuid();
  v_addr uuid;
  v_cpf text := nullif(regexp_replace(coalesce(p ->> 'cpf', ''), '\D', '', 'g'), '');
  v_dups jsonb;
begin
  perform iara.require_perm('guardians.write');
  if length(coalesce(p ->> 'full_name', '')) < 5 then
    raise exception 'Informe o nome completo do responsável.' using errcode = '22023';
  end if;
  if not coalesce((p ->> 'force')::boolean, false) then
    select jsonb_agg(jsonb_build_object('id', g.id, 'name', g.full_name, 'phone', iara.mask_phone(g.primary_phone))) into v_dups
    from iara.guardians g
    where (v_cpf is not null and regexp_replace(coalesce(g.cpf, ''), '\D', '', 'g') = v_cpf)
       or (iara.norm(g.full_name) = iara.norm(p ->> 'full_name') and regexp_replace(coalesce(g.primary_phone, ''), '\D', '', 'g') = regexp_replace(coalesce(p ->> 'phone', ''), '\D', '', 'g'));
    if v_dups is not null then
      return jsonb_build_object('ok', false, 'duplicates', v_dups, 'message', 'Possível cadastro duplicado. Confira antes de continuar.');
    end if;
  end if;
  if p ? 'address' and (p -> 'address' ->> 'lat') is not null then
    insert into iara.addresses (tenant_id, street, number, complement, neighborhood, postal_code, location, geocode_precision, geocode_source, is_demo)
    values (1, coalesce(p -> 'address' ->> 'street', 'Endereço informado'), p -> 'address' ->> 'number', p -> 'address' ->> 'complement',
            p -> 'address' ->> 'neighborhood', p -> 'address' ->> 'postal_code',
            iara.point((p -> 'address' ->> 'lat')::float8, (p -> 'address' ->> 'lng')::float8),
            coalesce(p -> 'address' ->> 'precision', 'PONTO_NO_MAPA'), 'Informado no atendimento', true)
    returning id into v_addr;
  end if;
  insert into iara.guardians (id, tenant_id, full_name, cpf, birth_date, email, primary_phone, whatsapp_phone, address_id, cadunico_status,
                              family_income, income_bracket, occupation, consent_flags, created_by, is_demo)
  values (v_id, 1, p ->> 'full_name', p ->> 'cpf', nullif(p ->> 'birth_date', '')::date, nullif(p ->> 'email', ''), nullif(p ->> 'phone', ''),
          coalesce(nullif(p ->> 'whatsapp', ''), nullif(p ->> 'phone', '')), v_addr, coalesce((p ->> 'cadunico')::boolean, false),
          nullif(p ->> 'family_income', '')::numeric, nullif(p ->> 'income_bracket', ''), nullif(p ->> 'occupation', ''),
          jsonb_build_object('lgpd_ciencia', true, 'registrado_em', now()), iara.current_user_id(), true);
  return jsonb_build_object('ok', true, 'guardian_id', v_id, 'address_id', v_addr);
end $$;

create or replace function api.student_create(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id uuid := gen_random_uuid();
  v_guardian uuid := nullif(p ->> 'guardian_id', '')::uuid;
  v_addr uuid;
  v_dups jsonb;
  v_birth date := (p ->> 'birth_date')::date;
begin
  if iara.my_scope() = 'GUARDIAN' then
    perform iara.require_perm('cases.write_own');
    v_guardian := iara.my_guardian();
  else
    perform iara.require_perm('students.write');
  end if;
  if length(coalesce(p ->> 'full_name', '')) < 5 or v_birth is null then
    raise exception 'Informe nome completo e data de nascimento.' using errcode = '22023';
  end if;
  if v_birth > current_date then
    raise exception 'Data de nascimento no futuro.' using errcode = '22023';
  end if;
  if not coalesce((p ->> 'force')::boolean, false) then
    select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.full_name, 'birth_date', s.birth_date, 'registry', s.student_registry_number)) into v_dups
    from iara.students s where iara.norm(s.full_name) = iara.norm(p ->> 'full_name') and s.birth_date = v_birth;
    if v_dups is not null then
      return jsonb_build_object('ok', false, 'duplicates', v_dups, 'message', 'Já existe criança com o mesmo nome e data de nascimento. Evite cadastro duplicado.');
    end if;
  end if;
  if v_guardian is not null then
    select address_id into v_addr from iara.guardians where id = v_guardian;
  end if;
  insert into iara.students (id, tenant_id, full_name, social_name, birth_date, gender, status, address_id, aee_status, transport_need, created_by, is_demo)
  values (v_id, 1, p ->> 'full_name', nullif(p ->> 'social_name', ''), v_birth, nullif(p ->> 'gender', ''), 'SEM_VINCULO', v_addr,
          coalesce((p ->> 'aee')::boolean, false), coalesce((p ->> 'transport_need')::boolean, false), iara.current_user_id(), true);
  if v_guardian is not null then
    insert into iara.student_guardians (student_id, guardian_id, relationship, is_primary)
    values (v_id, v_guardian, coalesce(nullif(p ->> 'relationship', ''), 'RESPONSAVEL_LEGAL'), true);
  end if;
  return jsonb_build_object('ok', true, 'student_id', v_id, 'grade_rule', iara.grade_for_birthdate(v_birth));
end $$;

create or replace function api.student_link_guardian(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('students.write');
  perform iara.require_perm('guardians.write');
  if not iara.can_access_student((p ->> 'student_id')::uuid) then
    raise exception 'Aluno fora do seu escopo.' using errcode = '42501';
  end if;
  insert into iara.student_guardians (student_id, guardian_id, relationship, is_primary, legal_authority_status)
  values ((p ->> 'student_id')::uuid, (p ->> 'guardian_id')::uuid, coalesce(nullif(p ->> 'relationship', ''), 'RESPONSAVEL_LEGAL'),
          coalesce((p ->> 'is_primary')::boolean, false), 'A_VERIFICAR')
  on conflict (student_id, guardian_id) do update set relationship = excluded.relationship;
  return jsonb_build_object('ok', true, 'message', 'Vínculo registrado. Situação legal: a verificar (análise humana).');
end $$;

-- ---------------------------------------------------------------------------
-- Auditoria e relatórios (exportação auditada)
-- ---------------------------------------------------------------------------
create or replace function api.audit_list(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security invoker set search_path = iara, public
as $$
  with base as (
    select a.* from iara.audit_log a
    where (nullif(p ->> 'entity_type', '') is null or a.entity_type = p ->> 'entity_type')
      and (nullif(p ->> 'entity_id', '') is null or a.entity_id = p ->> 'entity_id')
      and (nullif(p ->> 'action', '') is null or a.action = p ->> 'action')
      and ((p ->> 'unit_id') is null or a.unit_id = (p ->> 'unit_id')::int)
      and (coalesce((p ->> 'business_only')::boolean, false) = false or a.action not in ('INSERT', 'UPDATE', 'DELETE'))
  )
  select jsonb_build_object(
    'total', (select count(*) from base),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'action', a.action, 'entity_type', a.entity_type, 'entity_id', a.entity_id,
        'unit_id', a.unit_id, 'actor', a.actor_label, 'role', a.actor_role, 'summary', a.summary, 'before', a.before_json, 'after', a.after_json,
        'request_id', a.request_id, 'at', a.occurred_at) order by a.occurred_at desc, a.id desc)
      from (select * from base order by occurred_at desc, id desc
            offset (greatest(coalesce((p ->> 'page')::int, 1), 1) - 1) * 50 limit 50) a), '[]'::jsonb),
    'immutable', true)
$$;

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
    v_cols := '["Unidade","Tipo","Região","Turmas","Capacidade","Matrículas","Ocupação %","Vagas ofertáveis","Fila"]';
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
    v_cols := '["Unidade","Região","Faixa","Aguardando","Com oferta","Espera média (dias)","Vagas ofertáveis"]';
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
    v_title := 'Demanda x oferta por região (DEMO)';
    v_cols := '["Região","Faixa","Fila","Vagas ofertáveis","Saldo"]';
    select jsonb_agg(jsonb_build_array(t.name, gl.name, q.n, v.n, coalesce(v.n, 0) - coalesce(q.n, 0)) order by t.sort, gl.sort)
    into v_rows
    from iara.territories t cross join iara.grade_levels gl
    left join lateral (select count(*) n from iara.waiting_list_entries w join iara.education_units u on u.id = w.preferred_unit_id
                       where u.macro_territory_id = t.id and w.grade_level_id = gl.id and w.status in ('WAITING', 'OFFERED')) q on true
    left join lateral (select coalesce(sum(c.offerable_vacancies_count), 0) n from iara.classes c join iara.education_units u on u.id = c.unit_id
                       where u.macro_territory_id = t.id and c.grade_level_id = gl.id) v on true
    where t.kind in ('MACRORREGIAO', 'DISTRITO');
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

create or replace function api.demo_reset_citizen(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  if iara.current_user_id() is null then
    raise exception 'Sessão necessária.' using errcode = '28000';
  end if;
  return iara.demo_reset_citizen();
end $$;

grant execute on function api.me(jsonb), api.global_search(jsonb), api.unit_classes(jsonb), api.class_detail(jsonb), api.student_detail(jsonb),
  api.guardian_detail(jsonb), api.cases_list(jsonb), api.case_detail(jsonb), api.case_create(jsonb), api.case_update(jsonb),
  api.queue_list(jsonb), api.queue_entry_detail(jsonb), api.queue_entry_create(jsonb), api.queue_recalculate(jsonb),
  api.offer_create(jsonb), api.offer_respond(jsonb), api.enrollment_confirm(jsonb), api.offers_list(jsonb), api.document_set(jsonb),
  api.vacancy_block(jsonb), api.vacancy_unblock(jsonb), api.guardian_create(jsonb), api.student_create(jsonb), api.student_link_guardian(jsonb),
  api.audit_list(jsonb), api.report(jsonb), api.demo_reset_citizen(jsonb)
  to authenticated;

commit;
