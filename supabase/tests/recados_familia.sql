-- Recado da família: a professora da turma vê na tela inicial; a de outra turma e a família não recebem essa lista; a família lê onde o recado aparece.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/recados_familia.sql
create or replace function pg_temp.as_call(p_hash text, p_fn text, p_args jsonb) returns jsonb language plpgsql as $f$
declare
  v_uid uuid := (select user_id from iara.app_sessions where token_hash = p_hash);
  v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute format('select api.%I($1)', p_fn) into v using p_args;
  execute 'reset role';
  return v;
exception when others then
  execute 'reset role';
  return jsonb_build_object('erro', sqlerrm, 'codigo', sqlstate);
end $f$;

do $$
declare
  v_out jsonb := '[]';
  r jsonb; r2 jsonb;
  v_ana uuid := nullif(iara.setting('demo_student_ana'), '')::uuid;
  v_unit integer := (iara.setting('demo_unit_maria'))::int;
  v_outra_unit integer;
  v_marca constant text := 'recado de teste: febre 38';
begin
  perform iara.session_create('CIDADAO', null, 'rf-fam', 'teste');
  perform iara.session_create('PROFESSOR', v_unit, 'rf-prof', 'teste');
  select c.unit_id into v_outra_unit from iara.classes c join iara.class_staff cs on cs.class_id = c.id and cs.role_type = 'REGENTE' where c.status = 'ATIVA' and c.unit_id <> v_unit order by c.unit_id limit 1;
  perform iara.session_create('PROFESSOR', v_outra_unit, 'rf-outra', 'teste');

  r := pg_temp.as_call('rf-fam', 'familia_agenda_enviar', jsonb_build_object('student_id', v_ana, 'texto', v_marca));
  v_out := v_out || jsonb_build_object('passo', 'R1. A família envia e lê onde o recado aparece', 'ok', r ->> 'erro' is null and r ->> 'mensagem' like '%tela inicial%', 'mensagem', r ->> 'mensagem', 'erro', r ->> 'erro');

  r := pg_temp.as_call('rf-prof', 'agenda_recados_familia', '{}');
  v_out := v_out || jsonb_build_object('passo', 'R2. A professora da turma vê o recado inteiro, com a criança e a turma', 'ok',
    exists (select 1 from jsonb_array_elements(r) x where x ->> 'texto' = v_marca and x ->> 'aluno' like 'Ana%' and x ->> 'class_id' is not null and x ->> 'turma' is not null), 'erro', r ->> 'erro');

  r := pg_temp.as_call('rf-outra', 'agenda_recados_familia', '{}');
  r2 := pg_temp.as_call('rf-fam', 'agenda_recados_familia', '{}');
  v_out := v_out || jsonb_build_object('passo', 'R3. Professora de outra unidade não vê; a família não abre a lista', 'ok',
    not exists (select 1 from jsonb_array_elements(r) x where x ->> 'texto' = v_marca) and r2 ->> 'codigo' = '42501', 'erro', r ->> 'erro');

  r := pg_temp.as_call('rf-prof', 'agenda_recados_familia', '{"dias": 0}');
  v_out := v_out || jsonb_build_object('passo', 'R4. O recado de hoje aparece mesmo olhando só o dia', 'ok', exists (select 1 from jsonb_array_elements(r) x where x ->> 'texto' = v_marca));

  raise exception 'RESULTADO: %', v_out;
end $$;
