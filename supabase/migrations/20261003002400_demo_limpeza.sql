-- =============================================================================
-- IARA Educa · Limpeza do que as sessões de demonstração criaram
--  · iara.demo_purge_session_data(): manutenção. Remove o que visitantes e testes criaram pelo app (famílias,
--    crianças, protocolos, conversas, inscrições na fila, ofertas, matrículas, bloqueios, documentos,
--    notificações e eventos) e devolve ao valor original — pela trilha de auditoria — o que as sessões
--    alteraram no cenário gerado. Uso: select iara.demo_purge_session_data();
--  · iara.demo_reset_citizen() ("Reiniciar demonstração"): passa a apagar o que as sessões criaram para a
--    família da Maria. Antes só cancelava, e o protocolo do Davi acumulava ofertas, matrículas e notas a cada
--    reinício.
-- A trilha de auditoria é imutável e não é tocada: as linhas apagadas aqui não geram registro linha a linha
-- (iara.skip_audit), só um evento de negócio com o resumo da limpeza.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
-- =============================================================================
begin;

-- Usuários das sessões de demonstração (visitantes e testes). O cenário gerado usa usuários SEED/SYSTEM.
create or replace function iara.demo_session_users() returns uuid[]
language sql stable security definer set search_path = iara, public
as $$ select coalesce(array_agg(id), '{}') from iara.app_users where auth_provider = 'DEMO' $$;

-- Deslocamento temporal da demonstração aplicado depois de um instante (iara.demo_timeshift move os registros
-- fictícios, mas não a auditoria): corrige datas recuperadas da trilha.
create or replace function iara.demo_shift_since(p_ts timestamptz) returns interval
language sql stable security definer set search_path = iara, public
as $$
  select coalesce(sum((regexp_match(a.summary, 'tempo em (.+) para manter'))[1]::interval), interval '0')
  from iara.audit_log a
  where a.action = 'DEMO_TIMESHIFT' and a.occurred_at > p_ts and a.summary ~ 'tempo em (.+) para manter'
$$;

-- Valor de cada coluna antes da 1ª alteração feita por sessão (a auditoria guarda só as colunas alteradas).
create or replace function iara.demo_original_values(p_entity_type text, p_users uuid[])
returns table (entity_id text, orig jsonb, since timestamptz)
language sql stable security definer set search_path = iara, public
as $$
  select z.entity_id, jsonb_object_agg(z.k, z.v), min(z.t)
  from (select distinct on (a.entity_id, kv.key) a.entity_id, kv.key as k, kv.value as v, a.occurred_at as t
        from iara.audit_log a cross join lateral jsonb_each(a.before_json) kv
        where a.entity_type = p_entity_type and a.action = 'UPDATE' and a.user_id = any (p_users)
        order by a.entity_id, kv.key, a.id) z
  group by z.entity_id
$$;

-- ---------------------------------------------------------------------------------------------
-- Reinício do cenário do cidadão: a família da Maria volta exatamente ao estado gerado
-- ---------------------------------------------------------------------------------------------
create or replace function iara.demo_reset_citizen() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_davi uuid := (iara.setting('demo_student_davi'))::uuid;
  v_ana uuid := (iara.setting('demo_student_ana'))::uuid;
  v_entry uuid := (iara.setting('demo_entry_davi'))::uuid;
  v_case uuid := (iara.setting('demo_case_davi'))::uuid;
  v_maria uuid := (iara.setting('demo_guardian_maria'))::uuid;
  v_jorge uuid := nullif(iara.setting('demo_guardian_jorge'), '')::uuid;
  v_addr uuid := nullif(iara.setting('demo_address_maria'), '')::uuid;
  v_unit integer := (iara.setting('demo_unit_maria'))::int;
  v_users uuid[] := iara.demo_session_users();
  v_family uuid[];
  v_extra uuid[];
  v_adults uuid[];
  v_kids uuid[];
  v_cases uuid[];
  v_entries uuid[];
  v_offers uuid[];
  v_enrolls uuid[];
  v_addrs uuid[];
  q record;
  v_pos integer;
  v_conv integer;
begin
  if v_davi is null then
    raise exception 'Cenário de demonstração não configurado.';
  end if;
  v_family := array_remove(array[v_maria, v_jorge], null);

  -- 1. o que as sessões criaram para a família (crianças e adultos incluídos, protocolos, fila, ofertas, matrículas)
  select coalesce(array_agg(s.id), '{}') into v_extra from iara.students s
  where s.id not in (v_ana, v_davi) and s.created_by = any (v_users)
    and (exists (select 1 from iara.student_guardians sg where sg.student_id = s.id and sg.guardian_id = any (v_family))
         or (not exists (select 1 from iara.student_guardians sg where sg.student_id = s.id)
             and exists (select 1 from iara.app_users u where u.id = s.created_by and u.role_code = 'CIDADAO')));
  v_kids := array[v_ana, v_davi] || v_extra;
  select coalesce(array_agg(g.id), '{}') into v_adults from iara.guardians g
  where not (g.id = any (v_family)) and g.created_by = any (v_users)
    and exists (select 1 from iara.student_guardians sg where sg.guardian_id = g.id and sg.student_id = any (v_kids));
  select coalesce(array_agg(c.id), '{}') into v_cases from iara.service_cases c
  where c.id <> v_case and c.created_by = any (v_users)
    and (c.guardian_id = any (v_family || v_adults) or c.student_id = any (v_kids));
  select coalesce(array_agg(w.id), '{}') into v_entries from iara.waiting_list_entries w
  where w.id <> v_entry
    and (w.student_id = any (v_extra) or w.case_id = any (v_cases) or (w.student_id = any (v_kids) and w.created_by = any (v_users)));
  select coalesce(array_agg(o.id), '{}') into v_offers from iara.vacancy_offers o
  where (o.student_id = any (v_kids) and (o.created_by = any (v_users) or o.case_id = any (v_cases)))
     or o.waiting_list_entry_id = any (v_entries);
  select coalesce(array_agg(e.id), '{}') into v_enrolls from iara.enrollments e
  where e.student_id = any (v_kids) and e.created_by = any (v_users);
  select coalesce(array_agg(a.id), '{}') into v_addrs from iara.addresses a
  where a.id is distinct from v_addr
    and exists (select 1 from iara.audit_log l where l.entity_type = 'addresses' and l.entity_id = a.id::text
                and l.action = 'INSERT' and l.user_id = any (v_users))
    and (exists (select 1 from iara.guardians g where g.address_id = a.id and g.id = any (v_family || v_adults))
         or exists (select 1 from iara.students s where s.address_id = a.id and s.id = any (v_kids)));

  perform set_config('iara.skip_audit', 'on', true);
  -- o cenário gerado não tem notificações para a família: todas vêm das sessões
  delete from iara.notifications where guardian_id = any (v_family || v_adults) or student_id = any (v_kids) or case_id = any (v_cases);
  delete from iara.vacancy_events v using iara.vacancy_offers o
  where o.id = any (v_offers) and v.class_id = o.class_id and v.reference = 'Oferta ' || substr(o.id::text, 1, 8);
  delete from iara.vacancy_offers where id = any (v_offers);
  update iara.students set current_enrollment_id = null where current_enrollment_id = any (v_enrolls);
  update iara.enrollments set previous_enrollment_id = null where previous_enrollment_id = any (v_enrolls);
  delete from iara.enrollments where id = any (v_enrolls);
  for q in select distinct preferred_unit_id, grade_level_id from iara.waiting_list_entries
           where id = any (v_entries) and status in ('WAITING', 'OFFERED', 'ACCEPTED') loop
    delete from iara.waiting_list_entries
    where id = any (v_entries) and preferred_unit_id = q.preferred_unit_id and grade_level_id = q.grade_level_id;
    perform iara.recalculate_queue(q.preferred_unit_id, q.grade_level_id);
  end loop;
  delete from iara.waiting_list_entries where id = any (v_entries);
  delete from iara.conversations c
  where c.owner_user_id = any (v_users)
    and (c.guardian_id = any (v_family || v_adults)
         or (c.guardian_id is null and exists (select 1 from iara.app_users u where u.id = c.owner_user_id and u.role_code = 'CIDADAO')));
  get diagnostics v_conv = row_count;
  delete from iara.case_events ev using iara.service_cases c
  where ev.case_id = c.id and not (c.id = any (v_cases))
    and (c.guardian_id = any (v_family) or c.student_id = any (v_kids))
    and (ev.user_id = any (v_users) or ev.message like 'Cenário de demonstração reiniciado%');
  delete from iara.documents d
  where d.case_id = any (v_cases) or d.guardian_id = any (v_adults) or d.student_id = any (v_extra)
     or (d.student_id = any (v_kids) and exists (select 1 from iara.audit_log l where l.entity_type = 'documents'
                                                  and l.entity_id = d.id::text and l.action = 'INSERT' and l.user_id = any (v_users)));
  delete from iara.service_cases where id = any (v_cases);
  delete from iara.students where id = any (v_extra);
  delete from iara.guardians where id = any (v_adults);
  delete from iara.student_guardians where student_id in (v_ana, v_davi) and not (guardian_id = any (v_family));

  -- 2. endereço, declarações e contatos originais
  update iara.guardians set cadunico_status = true, single_mother = false, primary_phone = '(44) 90000-4182',
         whatsapp_phone = '(44) 90000-4182', email = 'maria.aparecida@email.test', address_id = coalesce(v_addr, address_id)
  where id = v_maria;
  if v_addr is not null then
    update iara.guardians set address_id = v_addr where id = v_jorge;
    update iara.students set address_id = v_addr where id in (v_ana, v_davi);
  end if;
  delete from iara.addresses a
  where a.id = any (v_addrs)
    and not exists (select 1 from iara.guardians g where g.address_id = a.id)
    and not exists (select 1 from iara.students s where s.address_id = a.id);

  -- 3. Davi volta a aguardar em 1º na fila de creche; protocolo como gerado (encerrado ao entrar na fila)
  update iara.students set status = 'AGUARDANDO_VAGA', current_enrollment_id = null where id = v_davi;
  update iara.waiting_list_entries set status = 'WAITING', demand_category = 'SEM_ATENDIMENTO' where id = v_entry;
  update iara.service_cases set status = 'ENCERRADO', resolution_code = 'INSERIDO_NA_FILA',
         resolution_notes = 'Sem vaga ofertável na creche da unidade preferida; criança inserida na fila.',
         closed_at = opened_at + interval '1 day 15 hours 23 minutes', sla_due_at = opened_at + interval '10 days',
         assigned_user_id = null
  where id = v_case;
  update iara.documents set status = 'PENDENTE', received_at = null, validated_at = null, validated_by = null, file_name = null
  where student_id = v_davi and doc_type = 'VACINACAO';
  perform set_config('iara.skip_audit', 'off', true);

  perform iara.compute_queue_priority(v_entry);
  perform iara.recalculate_queue(v_unit, 1::smallint);
  select position into v_pos from iara.waiting_list_entries where id = v_entry;
  perform iara.audit_event('DEMO_RESET', 'demo', 'cidadao', v_unit,
    format('Cenário do cidadão reiniciado: família original restaurada (%s membro(s), %s protocolo(s), %s oferta(s), %s matrícula(s) e %s conversa(s) de visitantes removidos).',
           cardinality(v_extra) + cardinality(v_adults), cardinality(v_cases), cardinality(v_offers), cardinality(v_enrolls), v_conv));
  return jsonb_build_object('ok', true, 'posicao_davi', v_pos, 'membros_removidos', cardinality(v_extra) + cardinality(v_adults),
                            'protocolos_removidos', cardinality(v_cases), 'ofertas_removidas', cardinality(v_offers),
                            'matriculas_removidas', cardinality(v_enrolls), 'conversas_removidas', v_conv);
end $$;

-- ---------------------------------------------------------------------------------------------
-- Limpeza geral (manutenção): tudo o que sessões de demonstração criaram ou alteraram
-- ---------------------------------------------------------------------------------------------
create or replace function iara.demo_purge_session_data() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_keep_students uuid[] := array_remove(array[nullif(iara.setting('demo_student_ana'), '')::uuid,
                                               nullif(iara.setting('demo_student_davi'), '')::uuid], null);
  v_keep_guardians uuid[] := array_remove(array[nullif(iara.setting('demo_guardian_maria'), '')::uuid,
                                                nullif(iara.setting('demo_guardian_jorge'), '')::uuid], null);
  v_addr_maria uuid := nullif(iara.setting('demo_address_maria'), '')::uuid;
  v_users uuid[] := iara.demo_session_users();
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
begin
  if not coalesce((iara.setting('demo_mode'))::boolean, false) then
    raise exception 'Limpeza disponível apenas no modo demonstração.' using errcode = '42501';
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

  -- 3. família da Maria: reinício completo
  v_reset := iara.demo_reset_citizen();

  v_out := jsonb_build_object('familias_removidas', cardinality(v_guardians), 'responsaveis', coalesce(v_names, '-'),
    'criancas_removidas', cardinality(v_students), 'protocolos_removidos', cardinality(v_cases),
    'inscricoes_removidas', cardinality(v_entries), 'ofertas_removidas', cardinality(v_offers),
    'matriculas_removidas', cardinality(v_enrolls), 'bloqueios_removidos', cardinality(v_blocks),
    'conversas_removidas', n_conv, 'eventos_removidos', n_events, 'documentos_removidos', n_docs,
    'notificacoes_removidas', n_notif, 'movimentos_de_vaga_removidos', n_vev, 'enderecos_removidos', n_addr,
    'linhas_restauradas', v_restored, 'reinicio_cidadao', v_reset);
  perform iara.audit_event('DEMO_PURGE', 'demo', 'sessoes', null,
    format('Limpeza da demonstração: %s família(s) e %s criança(s) criadas por sessões, %s protocolo(s), %s oferta(s), %s matrícula(s) e %s conversa(s) removidos; %s registro(s) do cenário restaurados.',
           cardinality(v_guardians), cardinality(v_students), cardinality(v_cases), cardinality(v_offers), cardinality(v_enrolls), n_conv, v_restored),
    v_out);
  return v_out;
end $$;

revoke all on function iara.demo_session_users(), iara.demo_shift_since(timestamptz), iara.demo_original_values(text, uuid[]),
  iara.demo_purge_session_data() from public;

commit;
