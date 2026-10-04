-- IARA Educa — 012 · RLS otimizada: decisões de escopo calculadas UMA vez por consulta (initPlan / hashed subplan)
-- em vez de uma função por linha. Mesma semântica da migração 008.
begin;

create or replace function iara.rls_network(p_perm text) returns boolean
language sql stable security definer set search_path = iara, public
as $$ select coalesce(iara.my_scope() = 'NETWORK' and iara.has_perm(p_perm), false) $$;

-- Conjunto de alunos acessíveis por escopo UNIT/GUARDIAN (NETWORK é tratado por rls_network)
create or replace function iara.my_student_ids() returns setof uuid
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_scope text := iara.my_scope();
  v_unit integer;
begin
  if v_scope = 'GUARDIAN' then
    return query select sg.student_id from iara.student_guardians sg where sg.guardian_id = iara.my_guardian() and sg.end_date is null;
  elsif v_scope = 'UNIT' and iara.has_perm('students.read') then
    v_unit := iara.my_unit();
    return query
      select e.student_id from iara.enrollments e where e.unit_id = v_unit and e.status in ('ACTIVE', 'PRE_ENROLLMENT', 'TRANSFER_PENDING')
      union select w.student_id from iara.waiting_list_entries w where w.preferred_unit_id = v_unit and w.status in ('WAITING', 'OFFERED', 'ACCEPTED')
      union select o.student_id from iara.vacancy_offers o where o.unit_id = v_unit and o.status in ('OFFERED', 'ACCEPTED', 'ENROLLED')
      union select c.student_id from iara.service_cases c where c.unit_id = v_unit and c.student_id is not null;
  end if;
end $$;

create or replace function iara.my_guardian_ids() returns setof uuid
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_scope() = 'GUARDIAN' then
    return query select iara.my_guardian();
  elsif iara.my_scope() = 'UNIT' and iara.has_perm('guardians.read') then
    return query select distinct sg.guardian_id from iara.student_guardians sg where sg.student_id in (select iara.my_student_ids());
  end if;
end $$;

create or replace function iara.my_address_ids() returns setof uuid
language sql stable security definer set search_path = iara, public
as $$
  select s.address_id from iara.students s where s.id in (select iara.my_student_ids()) and s.address_id is not null
  union select g.address_id from iara.guardians g where g.id in (select iara.my_guardian_ids()) and g.address_id is not null
$$;

create or replace function iara.my_case_ids() returns setof uuid
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_scope text := iara.my_scope();
begin
  if v_scope = 'GUARDIAN' then
    return query select c.id from iara.service_cases c
                 where c.guardian_id = iara.my_guardian() or c.student_id in (select iara.my_student_ids());
  elsif v_scope = 'UNIT' and iara.has_perm('cases.read') then
    return query select c.id from iara.service_cases c
                 where c.unit_id = iara.my_unit() or c.student_id in (select iara.my_student_ids());
  end if;
end $$;

create or replace function iara.my_conversation_ids() returns setof uuid
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  return query select c.id from iara.conversations c where c.owner_user_id = iara.current_user_id();
  if iara.my_scope() = 'GUARDIAN' then
    return query select c.id from iara.conversations c where c.guardian_id = iara.my_guardian();
  elsif iara.my_scope() = 'UNIT' and iara.has_perm('conversations.read') then
    return query select c.id from iara.conversations c where c.active_student_id in (select iara.my_student_ids());
  end if;
end $$;

grant execute on function iara.rls_network(text), iara.my_student_ids(), iara.my_guardian_ids(), iara.my_address_ids(),
  iara.my_case_ids(), iara.my_conversation_ids() to authenticated;

-- Recria políticas de dados pessoais
drop policy if exists students_read on iara.students;
create policy students_read on iara.students for select to authenticated
  using ((select iara.rls_network('students.read')) or id in (select iara.my_student_ids()));

drop policy if exists student_sensitive_read on iara.student_sensitive;
create policy student_sensitive_read on iara.student_sensitive for select to authenticated
  using ((select iara.has_perm('students.read_sensitive'))
         and ((select iara.rls_network('students.read')) or student_id in (select iara.my_student_ids())));

drop policy if exists guardians_read on iara.guardians;
create policy guardians_read on iara.guardians for select to authenticated
  using ((select iara.rls_network('guardians.read')) or id in (select iara.my_guardian_ids()));

drop policy if exists addresses_read on iara.addresses;
create policy addresses_read on iara.addresses for select to authenticated
  using ((select iara.rls_network('students.read')) or id in (select iara.my_address_ids()));

drop policy if exists student_guardians_read on iara.student_guardians;
create policy student_guardians_read on iara.student_guardians for select to authenticated
  using ((select iara.rls_network('students.read')) or student_id in (select iara.my_student_ids()));

drop policy if exists enrollments_read on iara.enrollments;
create policy enrollments_read on iara.enrollments for select to authenticated
  using ((select iara.rls_network('students.read')) or student_id in (select iara.my_student_ids()));

drop policy if exists documents_read on iara.documents;
create policy documents_read on iara.documents for select to authenticated
  using (((select iara.rls_network('students.read')) or student_id in (select iara.my_student_ids()) or guardian_id in (select iara.my_guardian_ids()))
         and (not is_sensitive or (select iara.has_perm('students.read_sensitive')) or (select iara.my_scope()) = 'GUARDIAN'));

drop policy if exists service_cases_read on iara.service_cases;
create policy service_cases_read on iara.service_cases for select to authenticated
  using ((select iara.rls_network('cases.read')) or id in (select iara.my_case_ids()));

drop policy if exists case_events_read on iara.case_events;
create policy case_events_read on iara.case_events for select to authenticated
  using (((select iara.rls_network('cases.read')) or case_id in (select iara.my_case_ids()))
         and (visibility = 'CIDADAO' or (select iara.my_scope()) <> 'GUARDIAN'));

drop policy if exists waiting_list_read on iara.waiting_list_entries;
create policy waiting_list_read on iara.waiting_list_entries for select to authenticated
  using (((select iara.rls_network('queue.read')))
         or (((select iara.has_perm('queue.read')) or (select iara.my_scope()) = 'GUARDIAN') and student_id in (select iara.my_student_ids())));

drop policy if exists vacancy_offers_read on iara.vacancy_offers;
create policy vacancy_offers_read on iara.vacancy_offers for select to authenticated
  using ((select iara.rls_network('students.read')) or student_id in (select iara.my_student_ids()));

drop policy if exists notifications_read on iara.notifications;
create policy notifications_read on iara.notifications for select to authenticated
  using (((select iara.my_scope()) = 'GUARDIAN' and guardian_id = (select iara.my_guardian()))
         or (select iara.rls_network('cases.read'))
         or ((select iara.has_perm('cases.read')) and guardian_id in (select iara.my_guardian_ids())));

drop policy if exists conversations_read on iara.conversations;
create policy conversations_read on iara.conversations for select to authenticated
  using ((select iara.rls_network('conversations.read')) or id in (select iara.my_conversation_ids()));

drop policy if exists messages_read on iara.messages;
create policy messages_read on iara.messages for select to authenticated
  using ((select iara.rls_network('conversations.read')) or conversation_id in (select iara.my_conversation_ids()));

drop policy if exists tool_executions_read on iara.tool_executions;
create policy tool_executions_read on iara.tool_executions for select to authenticated
  using ((select iara.has_perm('conversations.read'))
         and ((select iara.rls_network('conversations.read')) or conversation_id in (select iara.my_conversation_ids())));

drop policy if exists handoff_tasks_read on iara.handoff_tasks;
create policy handoff_tasks_read on iara.handoff_tasks for select to authenticated
  using ((select iara.has_perm('conversations.read'))
         and ((select iara.rls_network('conversations.read')) or conversation_id in (select iara.my_conversation_ids())));

drop policy if exists classes_read on iara.classes;
create policy classes_read on iara.classes for select to authenticated
  using ((select iara.has_perm('classes.read'))
         and ((select iara.my_scope()) in ('NETWORK', 'AGGREGATE') or unit_id = (select iara.my_unit())));

drop policy if exists staff_read on iara.staff;
create policy staff_read on iara.staff for select to authenticated
  using ((select iara.has_perm('classes.read'))
         and ((select iara.my_scope()) in ('NETWORK', 'AGGREGATE') or unit_id = (select iara.my_unit())));

drop policy if exists class_staff_read on iara.class_staff;
create policy class_staff_read on iara.class_staff for select to authenticated
  using ((select iara.has_perm('classes.read'))
         and ((select iara.my_scope()) in ('NETWORK', 'AGGREGATE')
              or class_id in (select c.id from iara.classes c where c.unit_id = (select iara.my_unit()))));

drop policy if exists vacancy_blocks_read on iara.vacancy_blocks;
create policy vacancy_blocks_read on iara.vacancy_blocks for select to authenticated
  using ((select iara.has_perm('classes.read'))
         and ((select iara.my_scope()) in ('NETWORK', 'AGGREGATE')
              or class_id in (select c.id from iara.classes c where c.unit_id = (select iara.my_unit()))));

drop policy if exists vacancy_events_read on iara.vacancy_events;
create policy vacancy_events_read on iara.vacancy_events for select to authenticated
  using ((select iara.has_perm('classes.read'))
         and ((select iara.my_scope()) in ('NETWORK', 'AGGREGATE') or unit_id = (select iara.my_unit())));

commit;
