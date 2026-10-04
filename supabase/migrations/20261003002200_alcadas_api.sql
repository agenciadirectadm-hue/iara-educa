-- =============================================================================
-- IARA Educa · Alçadas visíveis nas APIs
--  · case_detail: alçada (IARA/UNIDADE/SECRETARIA), unidade responsável e detalhes estruturados do pedido
--  · service_catalog: o que a IARA resolve na hora e quem decide o restante
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
-- =============================================================================
begin;

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
      'assigned_to_me', c.assigned_user_id = iara.current_user_id(), 'is_demo', c.is_demo,
      'details', c.details, 'level', c.resolution_level, 'unit_id', c.unit_id,
      'unit_name', (select u.name from iara.education_units u where u.id = c.unit_id)),
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

create or replace function api.service_catalog(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('items', coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name, 'description', description,
         'requirements', requirements, 'documents', required_documents, 'sector', sector, 'sla_days', sla_days, 'source', source,
         'level', resolution_level, 'team', team, 'team_label', iara.team_label(team), 'iara_action', iara_action, 'escalation', escalation) order by sort), '[]'::jsonb))
  from iara.service_catalog
$$;

commit;
