-- Demonstração: o cenário da Maria não envelhece. O passeio sempre pede ciência em data futura e letiva, o bilhete da professora fica recente,
-- e o calendário da família tem a próxima reunião de pais; a rotina não muda nada quando já está em dia.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/demo_cenario_maria.sql
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
  v_hoje date := iara.hoje_local();
  v_ana uuid := nullif(iara.setting('demo_student_ana'), '')::uuid;
  v_unit integer := (select e.unit_id from iara.enrollments e where e.student_id = nullif(iara.setting('demo_student_ana'), '')::uuid and e.status = 'ACTIVE' limit 1);
  v_turma uuid := (select e.class_id from iara.enrollments e where e.student_id = nullif(iara.setting('demo_student_ana'), '')::uuid and e.status = 'ACTIVE' limit 1);
  v_id uuid;
  v_data date;
  v_data2 date;
begin
  perform iara.session_create('CIDADAO', null, 'dm-fam', 'teste');
  perform iara.session_create('PROFESSOR', v_unit, 'dm-prof', 'teste');

  -- envelhece o cenário e roda a rotina
  update iara.agenda_escolar set data = v_hoje - 40 where is_demo and class_id = v_turma and titulo = 'Passeio ao Parque do Ingá' returning id into v_id;
  update iara.agenda_escolar set data = v_hoje - 40 where is_demo and class_id = v_turma and student_id = v_ana and tipo = 'BILHETE' and origem = 'ESCOLA';
  insert into iara.agenda_ciencia (agenda_id, student_id) values (v_id, v_ana) on conflict do nothing;
  r := iara.demo_rotina_cenario_maria();
  select data into v_data from iara.agenda_escolar where id = v_id;
  v_out := v_out || jsonb_build_object('passo', 'M1. Passeio vencido vai para um dia letivo futuro, com pelo menos 2 dias, e a ciência antiga sai', 'ok',
    v_data >= v_hoje + 2 and iara.dia_letivo(v_data, v_unit) and not exists (select 1 from iara.agenda_ciencia where agenda_id = v_id)
    and (select texto from iara.agenda_escolar where id = v_id) like '%' || to_char(v_data, 'DD/MM') || '%', 'rotina', r, 'dia', v_data);

  r := iara.demo_rotina_cenario_maria();
  select data into v_data2 from iara.agenda_escolar where id = v_id;
  v_out := v_out || jsonb_build_object('passo', 'M2. A rotina não muda nada quando já está em dia', 'ok', r = '{}'::jsonb and v_data2 = v_data, 'rotina', r);

  -- o que a Maria vê
  r := pg_temp.as_call('dm-fam', 'familia_agenda', '{}');
  v_out := v_out || jsonb_build_object('passo', 'M3. Maria vê o passeio pedindo ciência e o bilhete da professora', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'itens') x where x ->> 'titulo' = 'Passeio ao Parque do Ingá' and (x ->> 'exige_ciencia')::boolean and not (x ->> 'ciente')::boolean)
    and exists (select 1 from jsonb_array_elements(r -> 'itens') x where x ->> 'tipo' = 'BILHETE' and x ->> 'origem' = 'ESCOLA'), 'erro', r ->> 'erro');

  r := pg_temp.as_call('dm-fam', 'calendario', '{}');
  v_out := v_out || jsonb_build_object('passo', 'M4. Calendário da Maria tem reunião de pais', 'ok',
    exists (select 1 from jsonb_array_elements(r) e where e ->> 'tipo' = 'REUNIAO_PAIS' and (e ->> 'inicio')::date >= v_hoje),
    'reuniao', (select jsonb_agg(e ->> 'inicio') from jsonb_array_elements(r) e where e ->> 'tipo' = 'REUNIAO_PAIS'));

  -- a professora da Ana enxerga o mesmo passeio e dá para a Maria dar ciência
  r := pg_temp.as_call('dm-prof', 'agenda_turma', jsonb_build_object('class_id', v_turma));
  r2 := pg_temp.as_call('dm-fam', 'familia_agenda_ciente', jsonb_build_object('id', v_id, 'student_id', v_ana));
  v_out := v_out || jsonb_build_object('passo', 'M5. A professora da turma vê o passeio; a Maria dá a ciência', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'itens') x where x ->> 'titulo' = 'Passeio ao Parque do Ingá') and r2 ->> 'erro' is null, 'erro', coalesce(r ->> 'erro', r2 ->> 'erro'));

  -- etapa agendada
  r := iara.housekeeping_etapa('cenario_maria');
  v_out := v_out || jsonb_build_object('passo', 'M6. A etapa está na manutenção agendada', 'ok', r ->> 'erro' is null
    and exists (select 1 from cron.job where jobname = 'iara-manutencao-cenario-maria' and active), 'etapa', r);

  raise exception 'RESULTADO: %', v_out;
end $$;
