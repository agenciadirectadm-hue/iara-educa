-- Pesquisa global: o resultado tem de ser idêntico ao da consulta antiga em cada perfil, e a RLS continua decidindo o escopo.
-- Roda numa transação revertida. Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/busca_global.sql
create or replace function pg_temp.busca_antiga(p jsonb) returns jsonb
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
grant execute on function pg_temp.busca_antiga(jsonb) to public;

do $$
declare
  v_out jsonb := '[]';
  v_reg text := (select student_registry_number from iara.students where student_registry_number is not null order by id limit 1);
  v_fone text := (select regexp_replace(primary_phone, '\D', '', 'g') from iara.guardians where primary_phone is not null order by id limit 1);
  v_prot text := (select protocol_number from iara.service_cases order by opened_at desc limit 1);
  v_termos text[];
  c record;
  t text;
  u uuid;
  novo jsonb;
  antigo jsonb;
  diferentes jsonb;
  t0 timestamptz;
  v_ms numeric;
  v_pior numeric;
begin
  v_termos := array['maria', 'ana', 'silva', 'Alvorada', 'zzzzz', 'jo', 'ÁGUA', v_reg, v_fone, v_prot];
  for c in select * from (values ('SECRETARIO'), ('DIRETOR_UNIDADE'), ('SECRETARIA_ESCOLAR'), ('PROFESSOR'), ('CIDADAO'), ('PREFEITO'), ('ATENDIMENTO')) x(papel) loop
    select id into u from iara.app_users where role_code = c.papel order by created_at limit 1;
    continue when u is null;
    diferentes := '[]';
    v_pior := 0;
    perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    foreach t in array v_termos loop
      continue when t is null;
      t0 := clock_timestamp();
      novo := api.global_search(jsonb_build_object('q', t));
      v_ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
      v_pior := greatest(v_pior, v_ms);
      antigo := pg_temp.busca_antiga(jsonb_build_object('q', t));
      if novo is distinct from antigo then diferentes := diferentes || to_jsonb(t); end if;
    end loop;
    execute 'reset role';
    v_out := v_out || jsonb_build_object('passo', 'Mesmo resultado da consulta antiga: ' || c.papel, 'ok', diferentes = '[]', 'diferentes', diferentes, 'pior_ms', v_pior);
  end loop;

  -- quem é da família só encontra as próprias crianças, mesmo com os candidatos vindos do índice
  select id into u from iara.app_users where role_code = 'CIDADAO' order by created_at limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  novo := api.global_search('{"q":"maria"}');
  execute 'reset role';
  v_out := v_out || jsonb_build_object('passo', 'Família não vê crianças de outras famílias', 'ok',
    not exists (select 1 from jsonb_array_elements(novo -> 'students') e
                where (e ->> 'id')::uuid not in (select sg.student_id from iara.student_guardians sg
                                                 join iara.app_users au on au.guardian_id = sg.guardian_id where au.id = u)));

  v_out := v_out || jsonb_build_object('passo', 'Visitante sem login não usa as funções de candidatos', 'ok',
    not has_function_privilege('anon', 'iara.busca_alunos(text, text)', 'execute')
    and not has_function_privilege('anon', 'iara.busca_responsaveis(text, text)', 'execute')
    and not has_function_privilege('anon', 'api.global_search(jsonb)', 'execute'));

  v_out := v_out || jsonb_build_object('passo', 'Percentual digitado não vira curinga', 'ok', true,
    'alunos_com_percentual', cardinality(iara.busca_alunos('%' || replace('%%%', '%', '\%') || '%', '')));

  raise exception 'RESULTADO: %', v_out;  -- reverte tudo
end $$;
