-- Demonstração coerente: na unidade da Maria, o perfil Professor(a) abre o(a) regente da turma da filha dela, com a turma e a aluna à vista;
-- nas outras unidades, continua abrindo um(a) regente da própria unidade.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/demo_professora_coerente.sql
do $$
declare
  v_out jsonb := '[]';
  v_maria uuid := (iara.setting('demo_guardian_maria'))::uuid;
  v_unit integer := (iara.setting('demo_unit_maria'))::int;
  v_filha uuid;
  v_turma uuid;
  v_user uuid;
  v_staff uuid;
  v_outra integer;
begin
  select e.student_id, e.class_id into v_filha, v_turma
  from iara.student_guardians sg join iara.enrollments e on e.student_id = sg.student_id and e.status = 'ACTIVE'
  where sg.guardian_id = v_maria and sg.end_date is null and e.unit_id = v_unit limit 1;

  -- sem escolher unidade (entra na da família) e escolhendo a unidade da família: o mesmo resultado
  perform iara.session_create('PROFESSOR', null, 'dp-a', 'teste');
  select u.id, u.staff_id into v_user, v_staff from iara.app_users u join iara.app_sessions s on s.user_id = u.id where s.token_hash = 'dp-a';
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  v_out := v_out || jsonb_build_object('passo', 'P1. Na unidade da Maria abre o(a) regente da turma da filha dela', 'ok',
    v_turma = any (iara.minhas_turmas())
    and exists (select 1 from iara.class_staff cs where cs.class_id = v_turma and cs.staff_id = v_staff and cs.role_type = 'REGENTE'),
    'quem', (select display_name from iara.app_users where id = v_user), 'turma', (select class_name from iara.classes where id = v_turma));

  perform iara.session_create('PROFESSOR', v_unit, 'dp-b', 'teste');
  v_out := v_out || jsonb_build_object('passo', 'P2. Escolhendo a unidade da Maria, a mesma pessoa', 'ok',
    (select u.staff_id from iara.app_users u join iara.app_sessions s on s.user_id = u.id where s.token_hash = 'dp-b') = v_staff);

  -- outra unidade: regente dela, sem relação com a família
  select c.unit_id into v_outra from iara.classes c join iara.class_staff cs on cs.class_id = c.id and cs.role_type = 'REGENTE'
  where c.status = 'ATIVA' and c.unit_id <> v_unit order by c.unit_id limit 1;
  perform iara.session_create('PROFESSOR', v_outra, 'dp-c', 'teste');
  select u.staff_id into v_staff from iara.app_users u join iara.app_sessions s on s.user_id = u.id where s.token_hash = 'dp-c';
  v_out := v_out || jsonb_build_object('passo', 'P3. Em outra unidade abre um(a) regente daquela unidade', 'ok',
    exists (select 1 from iara.class_staff cs join iara.classes c on c.id = cs.class_id where cs.staff_id = v_staff and cs.role_type = 'REGENTE' and c.unit_id = v_outra));

  raise exception 'RESULTADO: %', v_out;
end $$;
