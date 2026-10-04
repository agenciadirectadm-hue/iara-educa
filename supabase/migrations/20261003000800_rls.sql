-- IARA Educa — 008 · Row Level Security por perfil (RBAC) e escopo (ABAC) + privilégios mínimos
-- Escritas diretas em tabelas não são permitidas a anon/authenticated: toda alteração passa por
-- funções api.* (SECURITY DEFINER) que validam permissão, escopo, regras e geram auditoria.
begin;

insert into iara.role_permissions (role_code, permission_code) values ('PREFEITO', 'classes.read') on conflict do nothing;

create or replace function iara.can_access_address(p_address uuid) returns boolean
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_scope() = 'NETWORK' and iara.has_perm('students.read') then
    return true;
  end if;
  return exists (select 1 from iara.students s where s.address_id = p_address and iara.can_access_student(s.id))
      or exists (select 1 from iara.guardians g where g.address_id = p_address and iara.can_access_guardian(g.id));
end $$;

create or replace function iara.can_access_conversation(p_conversation uuid) returns boolean
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  c iara.conversations;
begin
  select * into c from iara.conversations where id = p_conversation;
  if not found then return false; end if;
  if c.owner_user_id = iara.current_user_id() then return true; end if;
  if iara.my_scope() = 'GUARDIAN' then return c.guardian_id is not null and c.guardian_id = iara.my_guardian(); end if;
  if not iara.has_perm('conversations.read') then return false; end if;
  if iara.my_scope() = 'NETWORK' then return true; end if;
  return c.active_student_id is not null and iara.can_access_student(c.active_student_id);
end $$;

-- ---------------------------------------------------------------------------
-- Habilita RLS em todas as tabelas do domínio
-- ---------------------------------------------------------------------------
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'iara' loop
    execute format('alter table iara.%I enable row level security', t.tablename);
  end loop;
end $$;

-- Dados públicos e de configuração (leitura aberta)
do $$
declare t text;
begin
  foreach t in array array['tenants', 'import_batches', 'territories', 'education_stages', 'grade_levels', 'education_units',
                           'unit_offers', 'unit_grade_stats', 'unit_shift_stats', 'data_quality_issues', 'demo_metrics',
                           'feature_flags', 'rules', 'service_catalog', 'organizational_roles'] loop
    execute format('create policy %I on iara.%I for select to anon, authenticated using (true)', t || '_public_read', t);
  end loop;
end $$;

create policy knowledge_read on iara.knowledge_articles for select to anon, authenticated
  using ((status = 'PUBLICADO' and audience = 'PUBLICO' and (valid_until is null or valid_until >= current_date))
         or iara.has_perm('config.read'));

create policy permissions_read on iara.permissions for select to authenticated using (true);
create policy role_permissions_read on iara.role_permissions for select to authenticated using (true);
create policy app_users_self on iara.app_users for select to authenticated using (id = iara.current_user_id());
-- app_sessions: sem política → inacessível fora das funções do gateway.

-- Operação escolar (sem dados pessoais)
create policy classes_read on iara.classes for select to authenticated
  using ((select iara.has_perm('classes.read')) and iara.can_access_unit(unit_id));
create policy staff_read on iara.staff for select to authenticated
  using ((select iara.has_perm('classes.read')) and iara.can_access_unit(unit_id));
create policy class_staff_read on iara.class_staff for select to authenticated
  using ((select iara.has_perm('classes.read')) and exists (select 1 from iara.classes c where c.id = class_id and iara.can_access_unit(c.unit_id)));
create policy vacancy_blocks_read on iara.vacancy_blocks for select to authenticated
  using ((select iara.has_perm('classes.read')) and exists (select 1 from iara.classes c where c.id = class_id and iara.can_access_unit(c.unit_id)));
create policy vacancy_events_read on iara.vacancy_events for select to authenticated
  using ((select iara.has_perm('classes.read')) and iara.can_access_unit(unit_id));

-- Pessoas (escopo por unidade ou vínculo responsável-aluno)
create policy students_read on iara.students for select to authenticated using (iara.can_access_student(id));
create policy student_sensitive_read on iara.student_sensitive for select to authenticated
  using ((select iara.has_perm('students.read_sensitive')) and iara.can_access_student(student_id));
create policy guardians_read on iara.guardians for select to authenticated using (iara.can_access_guardian(id));
create policy addresses_read on iara.addresses for select to authenticated using (iara.can_access_address(id));
create policy student_guardians_read on iara.student_guardians for select to authenticated using (iara.can_access_student(student_id));
create policy enrollments_read on iara.enrollments for select to authenticated using (iara.can_access_student(student_id));
create policy documents_read on iara.documents for select to authenticated
  using ((student_id is not null and iara.can_access_student(student_id) or guardian_id is not null and iara.can_access_guardian(guardian_id))
         and (not is_sensitive or (select iara.has_perm('students.read_sensitive')) or (select iara.my_scope()) = 'GUARDIAN'));

-- Atendimento, fila e ofertas
create policy service_cases_read on iara.service_cases for select to authenticated
  using (iara.can_access_case(unit_id, student_id, guardian_id));
create policy case_events_read on iara.case_events for select to authenticated
  using (exists (select 1 from iara.service_cases c where c.id = case_id and iara.can_access_case(c.unit_id, c.student_id, c.guardian_id))
         and (visibility = 'CIDADAO' or (select iara.my_scope()) <> 'GUARDIAN'));
create policy waiting_list_read on iara.waiting_list_entries for select to authenticated
  using (((select iara.has_perm('queue.read')) or (select iara.my_scope()) = 'GUARDIAN') and iara.can_access_student(student_id));
create policy vacancy_offers_read on iara.vacancy_offers for select to authenticated using (iara.can_access_student(student_id));
create policy notifications_read on iara.notifications for select to authenticated
  using (((select iara.my_scope()) = 'GUARDIAN' and guardian_id = (select iara.my_guardian()))
         or ((select iara.has_perm('cases.read')) and guardian_id is not null and iara.can_access_guardian(guardian_id)));

-- Agente IARA
create policy conversations_read on iara.conversations for select to authenticated using (iara.can_access_conversation(id));
create policy messages_read on iara.messages for select to authenticated using (iara.can_access_conversation(conversation_id));
create policy tool_executions_read on iara.tool_executions for select to authenticated
  using ((select iara.has_perm('conversations.read')) and iara.can_access_conversation(conversation_id));
create policy handoff_tasks_read on iara.handoff_tasks for select to authenticated
  using ((select iara.has_perm('conversations.read')) and iara.can_access_conversation(conversation_id));

-- Auditoria
create policy audit_log_read on iara.audit_log for select to authenticated
  using ((select iara.has_perm('audit.read'))
         and ((select iara.my_scope()) = 'NETWORK' or ((select iara.my_scope()) = 'UNIT' and unit_id = (select iara.my_unit()))));

-- ---------------------------------------------------------------------------
-- Privilégios
-- ---------------------------------------------------------------------------
grant usage on schema iara, api, extensions to anon, authenticated;
revoke all on all tables in schema iara from anon, authenticated;
grant select on all tables in schema iara to authenticated;
revoke select on iara.app_sessions from authenticated;
grant select on iara.tenants, iara.import_batches, iara.territories, iara.education_stages, iara.grade_levels,
  iara.education_units, iara.unit_offers, iara.unit_grade_stats, iara.unit_shift_stats, iara.data_quality_issues,
  iara.demo_metrics, iara.feature_flags, iara.rules, iara.service_catalog, iara.organizational_roles, iara.knowledge_articles
  to anon;

revoke execute on all functions in schema iara from public, anon, authenticated;
grant execute on function
  iara.f_unaccent(text), iara.norm(text), iara.current_user_id(), iara.my_role(), iara.my_scope(), iara.my_unit(),
  iara.my_guardian(), iara.my_label(), iara.has_perm(text), iara.require_perm(text), iara.can_access_unit(integer),
  iara.can_access_student(uuid), iara.can_access_guardian(uuid), iara.can_access_case(integer, uuid, uuid),
  iara.can_access_address(uuid), iara.can_access_conversation(uuid), iara.point(double precision, double precision),
  iara.mask_cpf(text), iara.mask_phone(text), iara.setting(text), iara.school_year(), iara.rule(text), iara.rule_version(),
  iara.grade_for_birthdate(date, integer)
  to anon, authenticated;

commit;
