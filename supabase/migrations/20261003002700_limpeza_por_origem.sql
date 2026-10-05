-- =============================================================================
-- IARA Educa · Limpeza da demonstração por origem
--   select iara.demo_purge_session_data();             -- tudo o que sessões criaram (portal e WhatsApp)
--   select iara.demo_purge_session_data('WHATSAPP');   -- só quem chegou pelo WhatsApp (contatos, famílias, conversas)
--   select iara.demo_purge_session_data('DEMO');       -- só as sessões de demonstração do portal
-- Contatos do WhatsApp removidos recomeçam do zero na próxima mensagem.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
-- =============================================================================
begin;

drop function if exists iara.demo_purge_session_data();
drop function if exists iara.demo_session_users();

create or replace function iara.demo_session_users(p_origem text default null) returns uuid[]
language sql stable security definer set search_path = iara, public
as $$
  select coalesce(array_agg(id), '{}') from iara.app_users
  where auth_provider in ('DEMO', 'WHATSAPP') and (p_origem is null or auth_provider = p_origem)
$$;

create or replace function iara.demo_purge_session_data(p_origem text default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_keep_students uuid[] := array_remove(array[nullif(iara.setting('demo_student_ana'), '')::uuid,
                                               nullif(iara.setting('demo_student_davi'), '')::uuid], null);
  v_keep_guardians uuid[] := array_remove(array[nullif(iara.setting('demo_guardian_maria'), '')::uuid,
                                                nullif(iara.setting('demo_guardian_jorge'), '')::uuid], null);
  v_addr_maria uuid := nullif(iara.setting('demo_address_maria'), '')::uuid;
  v_users uuid[] := iara.demo_session_users(p_origem);
  v_guardians uuid[];
  v_students uuid[];
  v_cases uuid[];
  v_entries uuid[];
  v_offers uuid[];
  v_enrolls uuid[];
  v_blocks uuid[];
  v_classes uuid[];
  v_addrs uuid[];
  v_names text;
  r record;
  q record;
  d interval;
  v_queues jsonb := '[]';
  v_restored integer := 0;
  n_notif integer; n_vev integer; n_conv integer; n_events integer; n_docs integer; n_addr integer;
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
  delete from iara.students where id = any (v_students);
  delete from iara.guardians where id = any (v_guardians);
  delete from iara.addresses a
  where a.id = any (v_addrs)
    and not exists (select 1 from iara.guardians g where g.address_id = a.id)
    and not exists (select 1 from iara.students s where s.address_id = a.id);
  get diagnostics n_addr = row_count;

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

  for r in select o.entity_id, o.orig from iara.demo_original_values('students', v_users) o
           join iara.students s on s.id::text = o.entity_id
           where not (s.id = any (v_keep_students)) loop
    update iara.students s set
      status = case when r.orig ? 'status' then r.orig ->> 'status' else s.status end,
      current_enrollment_id = case when r.orig ? 'current_enrollment_id'
                                   then (select e.id from iara.enrollments e where e.id = (r.orig ->> 'current_enrollment_id')::uuid)
                                   else s.current_enrollment_id end
    where s.id = r.entity_id::uuid;
    v_restored := v_restored + 1;
  end loop;

  for r in select o.entity_id, o.orig from iara.demo_original_values('conversations', v_users) o
           join iara.conversations c on c.id::text = o.entity_id loop
    update iara.conversations c set
      state = case when r.orig ? 'state' then r.orig ->> 'state' else c.state end,
      assigned_user_id = case when r.orig ? 'assigned_user_id' then (r.orig ->> 'assigned_user_id')::uuid else c.assigned_user_id end,
      assigned_label = case when r.orig ? 'assigned_label' then r.orig ->> 'assigned_label' else c.assigned_label end
    where c.id = r.entity_id::uuid;
    v_restored := v_restored + 1;
  end loop;
  perform set_config('iara.skip_audit', 'off', true);

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

  -- 4. família da Maria: reinício completo (não se aplica à limpeza só do WhatsApp)
  if p_origem is distinct from 'WHATSAPP' then
    v_reset := iara.demo_reset_citizen();
  end if;

  v_out := jsonb_build_object('familias_removidas', cardinality(v_guardians), 'responsaveis', coalesce(v_names, '-'),
    'criancas_removidas', cardinality(v_students), 'protocolos_removidos', cardinality(v_cases),
    'inscricoes_removidas', cardinality(v_entries), 'ofertas_removidas', cardinality(v_offers),
    'matriculas_removidas', cardinality(v_enrolls), 'bloqueios_removidos', cardinality(v_blocks),
    'conversas_removidas', n_conv, 'eventos_removidos', n_events, 'documentos_removidos', n_docs,
    'notificacoes_removidas', n_notif, 'movimentos_de_vaga_removidos', n_vev, 'enderecos_removidos', n_addr,
    'contatos_whatsapp_removidos', n_wa, 'linhas_restauradas', v_restored, 'reinicio_cidadao', v_reset, 'origem', coalesce(p_origem, 'todas'));
  perform iara.audit_event('DEMO_PURGE', 'demo', 'sessoes', null,
    format('Limpeza da demonstração: %s família(s) e %s criança(s) criadas por sessões, %s protocolo(s), %s oferta(s), %s matrícula(s) e %s conversa(s) removidos; %s registro(s) do cenário restaurados.',
           cardinality(v_guardians), cardinality(v_students), cardinality(v_cases), cardinality(v_offers), cardinality(v_enrolls), n_conv, v_restored),
    v_out);
  return v_out;
end $$;

revoke all on function iara.demo_session_users(text), iara.demo_purge_session_data(text) from public;

commit;
