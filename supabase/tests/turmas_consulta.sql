-- Turmas na consulta de unidades: todo servidor vê as turmas de qualquer unidade, sem dado de pessoa; família não; a ficha da turma continua restrita.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/turmas_consulta.sql
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
  v_unit integer := (iara.setting('demo_unit_maria'))::int;
  v_outra integer := (select id from iara.education_units where id <> v_unit and unit_type = 'ESCOLA' order by id limit 1);
  v_turma uuid := (select id from iara.classes where unit_id = v_outra and status = 'ATIVA' limit 1);
  v_n integer := (select count(*) from iara.classes where unit_id = v_outra and status = 'ATIVA');
  p text;
  r jsonb;
  v_falhas text[] := '{}';
begin
  foreach p in array array['DIRETOR_UNIDADE', 'SECRETARIA_ESCOLAR', 'PROFESSOR', 'PROFESSOR_AEE', 'ATENDIMENTO', 'MANUTENCAO', 'ALMOXARIFADO', 'PREFEITO', 'CONTROLE_EXTERNO'] loop
    perform iara.session_create(p, case when p in ('DIRETOR_UNIDADE', 'SECRETARIA_ESCOLAR', 'PROFESSOR', 'PROFESSOR_AEE') then v_unit end, 'tc-' || lower(p), 'teste');
    r := pg_temp.as_call('tc-' || lower(p), 'unit_classes_consulta', jsonb_build_object('unit_id', v_outra));
    if r ? 'erro' or jsonb_array_length(r -> 'items') <> v_n then v_falhas := v_falhas || (p || ': ' || coalesce(r ->> 'erro', jsonb_array_length(r -> 'items')::text)); end if;
  end loop;
  v_out := v_out || jsonb_build_object('passo', 'T1. Todo servidor vê as turmas de outra unidade', 'ok', cardinality(v_falhas) = 0, 'falhas', to_jsonb(v_falhas), 'esperado', v_n);

  r := pg_temp.as_call('tc-diretor_unidade', 'unit_classes_consulta', jsonb_build_object('unit_id', v_outra));
  v_out := v_out || jsonb_build_object('passo', 'T2. Traz o que a tela precisa, sem regente, sala nem aluno', 'ok',
    not exists (select 1 from jsonb_array_elements(r -> 'items') i where i ? 'teacher' or i ? 'assistant' or i ? 'room' or i ? 'students')
    and not exists (select 1 from jsonb_array_elements(r -> 'items') i where not (i ? 'name' and i ? 'capacity' and i ? 'enrolled' and i ? 'offerable' and i ? 'grade_level_id' and i ? 'shift'))
    and not exists (select 1 from iara.staff s where length(s.full_name) > 10 and r::text like '%' || s.full_name || '%'));

  r := pg_temp.as_call('tc-diretor_unidade', 'class_detail', jsonb_build_object('class_id', v_turma));
  v_out := v_out || jsonb_build_object('passo', 'T3. A ficha da turma de outra unidade continua restrita', 'ok', r ? 'erro', 'r', r);

  perform iara.session_create('CIDADAO', null, 'tc-fam', 'teste');
  r := pg_temp.as_call('tc-fam', 'unit_classes_consulta', jsonb_build_object('unit_id', v_outra));
  v_out := v_out || jsonb_build_object('passo', 'T4. Família não usa esta consulta', 'ok', r ? 'erro', 'r', r);

  r := pg_temp.as_call('tc-prefeito', 'unit_classes', jsonb_build_object('unit_id', v_outra));
  v_out := v_out || jsonb_build_object('passo', 'T5. Quem tem acesso segue com a consulta completa', 'ok', jsonb_array_length(r -> 'items') = v_n and (r -> 'items' -> 0) ? 'teacher');

  raise exception 'RESULTADO: %', v_out;
end $$;
