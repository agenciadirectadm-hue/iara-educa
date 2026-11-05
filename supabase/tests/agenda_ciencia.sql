-- Agenda no padrão dos avisos: todo recado da escola com a hora do envio e ciência, inclusive os anteriores; a ciência leva ao histórico, com a hora, e a
-- professora vê quando foi; o bilhete da própria família não pede ciência; recado ainda não enviado não aparece; outra família não dá ciência.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/agenda_ciencia.sql
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
  v_turma uuid := (select e.class_id from iara.enrollments e where e.student_id = nullif(iara.setting('demo_student_ana'), '')::uuid and e.status = 'ACTIVE' limit 1);
  v_bil uuid;
  v_velho uuid;
  v_futuro uuid;
  v_pend integer;
begin
  perform iara.session_create('CIDADAO', null, 'ag-fam', 'teste');
  perform iara.session_create('PROFESSOR', v_unit, 'ag-prof', 'teste');

  r := pg_temp.as_call('ag-prof', 'agenda_publicar', jsonb_build_object('class_id', v_turma, 'student_id', v_ana, 'tipo', 'BILHETE', 'texto', 'Sem problemas, mãe, pode buscar quando quiser.'));
  v_bil := (r ->> 'id')::uuid;
  -- um recado antigo, sem ciência, de quando só alguns pediam; e um que ainda não foi enviado
  insert into iara.agenda_escolar (unit_id, class_id, origem, tipo, titulo, texto, data, exige_ciencia, autor_label, created_at, is_demo)
  values (v_unit, v_turma, 'ESCOLA', 'MATERIAL', 'Recado antigo', 'Recado de dois meses atrás.', current_date - 60, false, 'Professora', now() - interval '60 days', false)
  returning id into v_velho;
  insert into iara.agenda_escolar (unit_id, class_id, origem, tipo, titulo, texto, data, exige_ciencia, autor_label, created_at, is_demo)
  values (v_unit, v_turma, 'ESCOLA', 'EVENTO', 'Recado do futuro', 'Ainda não enviado.', current_date + 3, false, 'Professora', now() + interval '2 days', false)
  returning id into v_futuro;

  r := pg_temp.as_call('ag-fam', 'familia_agenda', '{}');
  v_pend := (r ->> 'aguardando_ciencia')::int;
  v_out := v_out || jsonb_build_object('passo', 'G1. Todo recado da escola pede ciência e traz a hora do envio; autor sem a marca da demonstração', 'ok',
    r ->> 'erro' is null
    and not exists (select 1 from jsonb_array_elements(r -> 'itens') a where a ->> 'origem' = 'ESCOLA' and (not (a ->> 'exige_ciencia')::boolean or a ->> 'criado_em' is null or (a ->> 'ciente')::boolean))
    and exists (select 1 from jsonb_array_elements(r -> 'itens') a where (a ->> 'id')::uuid = v_bil and a ->> 'autor' not like '%demo #%'),
    'erro', r ->> 'erro', 'autor', (select a ->> 'autor' from jsonb_array_elements(r -> 'itens') a where (a ->> 'id')::uuid = v_bil limit 1));
  v_out := v_out || jsonb_build_object('passo', 'G2. Recados anteriores continuam com a ciência pendente; o não enviado ainda não aparece', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'itens') a where (a ->> 'id')::uuid = v_velho and (a ->> 'exige_ciencia')::boolean)
    and not exists (select 1 from jsonb_array_elements(r -> 'itens') a where (a ->> 'id')::uuid = v_futuro));

  -- ciência
  r := pg_temp.as_call('ag-fam', 'familia_agenda_ciente', jsonb_build_object('id', v_bil, 'student_id', v_ana));
  r2 := pg_temp.as_call('ag-fam', 'familia_agenda', '{}');
  v_out := v_out || jsonb_build_object('passo', 'G3. A ciência tira da agenda e leva ao histórico, com a hora', 'ok',
    r ->> 'ciente_em' is not null
    and not exists (select 1 from jsonb_array_elements(r2 -> 'itens') a where (a ->> 'id')::uuid = v_bil)
    and exists (select 1 from jsonb_array_elements(r2 -> 'historico') a where (a ->> 'id')::uuid = v_bil and a ->> 'ciente_em' is not null and a ->> 'criado_em' is not null and a ->> 'filho' = 'Ana')
    and (r2 ->> 'aguardando_ciencia')::int = v_pend - 1, 'erro', r ->> 'erro');

  -- recado antigo também
  r := pg_temp.as_call('ag-fam', 'familia_agenda_ciente', jsonb_build_object('id', v_velho, 'student_id', v_ana));
  r2 := pg_temp.as_call('ag-fam', 'familia_agenda', '{}');
  v_out := v_out || jsonb_build_object('passo', 'G4. Recado anterior também vai ao histórico', 'ok', exists (select 1 from jsonb_array_elements(r2 -> 'historico') a where (a ->> 'id')::uuid = v_velho));

  -- a professora vê quando foi
  r := pg_temp.as_call('ag-prof', 'agenda_turma', jsonb_build_object('class_id', v_turma));
  v_out := v_out || jsonb_build_object('passo', 'G5. A professora vê a hora da ciência no bilhete individual', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'itens') a where (a ->> 'id')::uuid = v_bil and a ->> 'ciente_em' is not null), 'erro', r ->> 'erro');

  -- bilhete da própria família
  r := pg_temp.as_call('ag-fam', 'familia_agenda_enviar', jsonb_build_object('student_id', v_ana, 'texto', 'Bilhete da família para o teste.'));
  r2 := pg_temp.as_call('ag-fam', 'familia_agenda', '{}');
  v_out := v_out || jsonb_build_object('passo', 'G6. O bilhete da própria família fica na agenda e não pede ciência dela', 'ok',
    exists (select 1 from jsonb_array_elements(r2 -> 'itens') a where (a ->> 'id')::uuid = (r ->> 'id')::uuid and not (a ->> 'exige_ciencia')::boolean));

  -- recado de outra turma não aceita ciência
  r := pg_temp.as_call('ag-fam', 'familia_agenda_ciente', jsonb_build_object('id', (select id from iara.agenda_escolar where class_id <> v_turma and student_id is null limit 1), 'student_id', v_ana));
  v_out := v_out || jsonb_build_object('passo', 'G7. Recado de outra turma não aceita ciência', 'ok', r ->> 'codigo' = 'P0002');

  raise exception 'RESULTADO: %', v_out;
end $$;
