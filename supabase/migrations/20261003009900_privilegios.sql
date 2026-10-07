-- IARA Educa — 015 · Privilégios mínimos (idempotente — reexecutar sempre que funções forem criadas).
-- O Postgres concede EXECUTE a PUBLIC em toda função nova e não permite remover isso por schema;
-- por isso revogamos tudo e concedemos explicitamente apenas o necessário.
begin;

revoke execute on all functions in schema iara from public, anon, authenticated;
revoke execute on all functions in schema api from public, anon, authenticated;

-- Utilitários usados por políticas de RLS e por funções SECURITY INVOKER
grant execute on function
  iara.f_unaccent(text), iara.norm(text), iara.current_user_id(), iara.my_role(), iara.my_scope(), iara.my_unit(), iara.my_guardian(),
  iara.my_label(), iara.has_perm(text), iara.require_perm(text), iara.can_access_unit(integer), iara.can_access_student(uuid),
  iara.can_access_guardian(uuid), iara.can_access_case(integer, uuid, uuid), iara.can_access_address(uuid), iara.can_access_conversation(uuid),
  iara.point(double precision, double precision), iara.mask_cpf(text), iara.mask_phone(text), iara.setting(text), iara.school_year(),
  iara.rule(text), iara.rule_version(), iara.grade_for_birthdate(date, integer), iara.age_text(date), iara.case_open(text),
  iara.rls_network(text), iara.my_student_ids(), iara.my_guardian_ids(), iara.my_address_ids(), iara.my_case_ids(), iara.my_conversation_ids()
  to anon, authenticated;
grant execute on function
  iara.can_see_contacts(), iara.guardian_json(iara.guardians), iara.address_json(uuid),
  iara.audit_event(text, text, text, integer, text, jsonb, jsonb)
  to authenticated;

-- Cadastro 360º: pendências e máscaras usadas pelas fichas (SECURITY INVOKER)
grant execute on function
  iara.aluno_pendencias(iara.students, boolean), iara.responsavel_pendencias(iara.guardians), iara.mascara_doc(text), iara.fmt_cpf(text),
  iara.digitos(text), iara.endereco_aproximado(text)
  to authenticated;

-- Distâncias (linha reta, a pé, de carro): medida usada pelo critério de proximidade (SECURITY INVOKER: queue_list)
grant execute on function iara.medida_distancia_fila(), iara.medida_rotulo(text) to authenticated;

-- API pública (sem dados pessoais)
grant execute on function
  api.bootstrap(jsonb), api.units_map(jsonb), api.geo_layers(jsonb), api.units_list(jsonb), api.unit_detail(jsonb), api.territory_detail(jsonb),
  api.network_kpis(jsonb), api.grade_for_birthdate(jsonb), api.search_vacancies(jsonb), api.geo_search(jsonb), api.knowledge_search(jsonb),
  api.service_catalog(jsonb), api.rules_list(jsonb), api.data_quality(jsonb), api.persona_units(jsonb), api.declaracao_verificar(jsonb)
  to anon, authenticated;

-- API autenticada (permissão e escopo verificados dentro de cada função / pela RLS)
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'api'
  loop
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;

commit;
