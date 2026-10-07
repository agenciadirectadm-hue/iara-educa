-- Sprint 2 (pedagógico): notas, pareceres, alfabetização, risco e planos de intervenção, AEE e declarações — quem vê e quem lança.
-- Roda numa transação revertida (não deixa resíduo). Cada passo traz "ok": true quando o comportamento é o esperado.
-- Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/sprint2_pedagogico.sql
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

create or replace function pg_temp.as_anon(p_fn text, p_args jsonb) returns jsonb language plpgsql as $f$
declare
  v jsonb;
begin
  perform set_config('request.jwt.claims', '{"role": "anon"}', true);
  execute 'set local role anon';
  execute format('select api.%I($1)', p_fn) into v using p_args;
  execute 'reset role';
  return v;
exception when others then
  execute 'reset role';
  return jsonb_build_object('erro', sqlerrm, 'codigo', sqlstate);
end $f$;

create or replace function pg_temp.ok_erro(r jsonb, p_cod text) returns boolean language sql as $f$ select coalesce(r ->> 'codigo' = p_cod, false) $f$;
create or replace function pg_temp.n(r jsonb) returns integer language sql as $f$
  select case when jsonb_typeof(r) = 'array' then jsonb_array_length(r) else -1 end $f$;

do $$
declare
  v_out jsonb := '[]';
  r jsonb;
  v_ana uuid := (iara.setting('demo_student_ana'))::uuid;
  v_davi uuid;
  v_unit integer;
  v_ef integer;
  v_outra integer;
  v_turma_prof uuid;
  v_turma_ef1 uuid;
  v_aluno uuid;
  v_comp text;
  v_comp_outro text;
  v_risco uuid;
  v_plano uuid;
  v_aee_aluno uuid;
  v_aee_plano uuid;
  v_guard uuid;
  v_user uuid := gen_random_uuid();
  v_cod text;
  v_decl uuid;
  v_turma_pre uuid;
begin
  select e.unit_id into v_unit from iara.enrollments e where e.student_id = v_ana and e.status = 'ACTIVE';
  select sg.student_id into v_davi from iara.student_guardians sg where sg.guardian_id = (iara.setting('demo_guardian_maria'))::uuid
    and sg.student_id <> v_ana and exists (select 1 from iara.waiting_list_entries w where w.student_id = sg.student_id and w.status in ('WAITING', 'OFFERED')) limit 1;
  -- escola de fundamental com turma de 1º ano e regente com horário
  select c.unit_id into v_ef from iara.classes c join iara.grade_levels g on g.id = c.grade_level_id
  where g.code = 'EF1' and c.status = 'ATIVA' and exists (select 1 from iara.horarios_turma h where h.class_id = c.id and h.staff_id is not null) order by c.unit_id limit 1;
  select u.id into v_outra from iara.education_units u where u.id not in (v_unit, v_ef) and exists (select 1 from iara.classes c where c.unit_id = u.id and c.status = 'ATIVA') order by u.id limit 1;
  perform iara.session_create('PROFESSOR', v_ef, 's2-prof', 'teste');
  perform iara.session_create('PROFESSOR', v_unit, 's2-prof-ei', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_ef, 's2-dir', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_unit, 's2-dir-ei', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_outra, 's2-dir-outra', 'teste');
  perform iara.session_create('SECRETARIA_ESCOLAR', v_unit, 's2-sec-ei', 'teste');
  perform iara.session_create('SECRETARIO', null, 's2-secretario', 'teste');
  perform iara.session_create('SUPERINTENDENCIA', null, 's2-super', 'teste');
  perform iara.session_create('PREFEITO', null, 's2-pref', 'teste');
  perform iara.session_create('CIDADAO', null, 's2-fam', 'teste');
  perform iara.session_create('CIDADAO_NOVO', null, 's2-fam-nova', 'teste');
  perform iara.session_create('PROFESSOR_AEE', v_unit, 's2-aee', 'teste');

  -- Notas ----------------------------------------------------------------------------------------------------------------------
  v_turma_prof := (select cs.class_id from iara.class_staff cs join iara.app_users u on u.staff_id = cs.staff_id
                   join iara.app_sessions se on se.user_id = u.id where se.token_hash = 's2-prof' and cs.role_type = 'REGENTE' limit 1);
  r := pg_temp.as_call('s2-prof', 'notas_turma', jsonb_build_object('class_id', v_turma_prof, 'bimestre', 3));
  v_comp := (select x ->> 'nome' from jsonb_array_elements(r -> 'componentes') x where (x ->> 'pode_lancar')::boolean limit 1);
  v_comp_outro := (select x ->> 'nome' from jsonb_array_elements(r -> 'componentes') x where not (x ->> 'pode_lancar')::boolean limit 1);
  v_aluno := (select (x ->> 'id')::uuid from jsonb_array_elements(r -> 'alunos') x limit 1);
  v_out := v_out || jsonb_build_object('passo', 'N1. Professor vê as notas da própria turma e lança só os próprios componentes', 'ok', r ->> 'erro' is null
    and v_comp is not null and v_comp_outro is not null and pg_temp.n(r -> 'alunos') > 0, 'proprio', v_comp, 'outro', v_comp_outro, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-prof', 'notas_lancar', jsonb_build_object('class_id', v_turma_prof, 'componente', v_comp, 'bimestre', 4,
         'notas', jsonb_build_array(jsonb_build_object('student_id', v_aluno, 'nota', 5.5, 'rec', 7))));
  v_out := v_out || jsonb_build_object('passo', 'N2. Professor lança nota e recuperação (vale a maior)', 'ok',
    (r -> 'alunos' -> 0 -> 'notas' -> v_comp ->> 'final')::numeric = 7 or exists (select 1 from jsonb_array_elements(r -> 'alunos') x
      where (x ->> 'id')::uuid = v_aluno and (x -> 'notas' -> v_comp ->> 'final')::numeric = 7), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-prof', 'notas_lancar', jsonb_build_object('class_id', v_turma_prof, 'componente', v_comp_outro, 'bimestre', 4,
         'notas', jsonb_build_array(jsonb_build_object('student_id', v_aluno, 'nota', 8))));
  v_out := v_out || jsonb_build_object('passo', 'N3. Professor não lança componente de outro professor (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s2-prof', 'notas_lancar', jsonb_build_object('class_id', v_turma_prof, 'componente', v_comp, 'bimestre', 4,
         'notas', jsonb_build_array(jsonb_build_object('student_id', v_aluno, 'nota', 11))));
  v_out := v_out || jsonb_build_object('passo', 'N4. Nota fora de 0 a 10 é recusada', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s2-prof', 'notas_lancar', jsonb_build_object('class_id', v_turma_prof, 'componente', v_comp, 'bimestre', 4,
         'notas', jsonb_build_array(jsonb_build_object('student_id', v_ana, 'nota', 8))));
  v_out := v_out || jsonb_build_object('passo', 'N5. Aluno de outra turma é recusado', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s2-dir-outra', 'notas_turma', jsonb_build_object('class_id', v_turma_prof));
  v_out := v_out || jsonb_build_object('passo', 'N6. Direção de outra unidade não vê as notas (deve negar)', 'ok', pg_temp.ok_erro(r, 'P0002'));
  r := pg_temp.as_call('s2-dir', 'boletim', jsonb_build_object('student_id', v_aluno));
  v_out := v_out || jsonb_build_object('passo', 'N7. Direção vê o boletim com os 3 bimestres', 'ok', pg_temp.n(r -> 'componentes') >= 6
    and (select count(*) from jsonb_object_keys(r -> 'componentes' -> 0 -> 'bimestres')) >= 3, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-fam', 'boletim', jsonb_build_object('student_id', v_aluno));
  v_out := v_out || jsonb_build_object('passo', 'N8. Família não vê boletim de criança de outra família (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s2-fam', 'familia_boletim', '{}');
  v_out := v_out || jsonb_build_object('passo', 'N9. Família vê o boletim da Ana (pareceres da educação infantil)', 'ok',
    exists (select 1 from jsonb_array_elements(r) x where (x ->> 'student_id')::uuid = v_ana and (x ->> 'parecer')::boolean and pg_temp.n(x -> 'pareceres') >= 3), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-pref', 'desempenho_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', 'N10. Prefeito não vê notas (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s2-secretario', 'desempenho_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', 'N11. SEDUC: painel por componente e unidade', 'ok', pg_temp.n(r -> 'por_componente') >= 10 and pg_temp.n(r -> 'por_unidade') > 10
    and pg_temp.n(r -> 'alfabetizacao') > 0, 'abaixo', r ->> 'alunos_abaixo', 'erro', r ->> 'erro');

  -- Pareceres (educação infantil) ----------------------------------------------------------------------------------------------
  v_turma_pre := (select cs.class_id from iara.class_staff cs join iara.app_users u on u.staff_id = cs.staff_id
                  join iara.app_sessions se on se.user_id = u.id where se.token_hash = 's2-prof-ei' and cs.role_type = 'REGENTE' limit 1);
  v_aluno := (select student_id from iara.enrollments where class_id = v_turma_pre and status = 'ACTIVE' limit 1);
  r := pg_temp.as_call('s2-prof-ei', 'parecer_salvar', jsonb_build_object('class_id', v_turma_pre, 'student_id', v_aluno, 'bimestre', 4, 'texto', 'Curto.'));
  v_out := v_out || jsonb_build_object('passo', 'P1. Parecer curto é recusado', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s2-prof-ei', 'parecer_salvar', jsonb_build_object('class_id', v_turma_pre, 'student_id', v_aluno, 'bimestre', 4,
         'texto', 'Participa das brincadeiras e já reconhece as cores e os números até 10.'));
  v_out := v_out || jsonb_build_object('passo', 'P2. Regente registra o parecer da própria turma', 'ok', (r ->> 'ok')::boolean, 'erro', r ->> 'erro');

  -- Alfabetização e risco -------------------------------------------------------------------------------------------------------
  v_turma_ef1 := (select c.id from iara.classes c join iara.grade_levels g on g.id = c.grade_level_id where c.unit_id = v_ef and g.code = 'EF1' and c.status = 'ATIVA' limit 1);
  r := pg_temp.as_call('s2-dir', 'alfabetizacao_turma', jsonb_build_object('class_id', v_turma_ef1, 'ciclo', 'B3'));
  v_aluno := (select (x ->> 'id')::uuid from jsonb_array_elements(r -> 'alunos') x limit 1);
  v_out := v_out || jsonb_build_object('passo', 'A1. Sondagem da turma de 1º ano com a distribuição por nível', 'ok', r ->> 'erro' is null
    and (select count(*) from jsonb_object_keys(r -> 'distribuicao')) >= 2, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-dir', 'alfabetizacao_lancar', jsonb_build_object('class_id', v_turma_ef1, 'ciclo', 'B4',
         'registros', jsonb_build_array(jsonb_build_object('student_id', v_aluno, 'nivel', 'ALFABETICO', 'leitura', 'LE_FRASES'))));
  v_out := v_out || jsonb_build_object('passo', 'A2. Direção registra a sondagem do 4º bimestre', 'ok', exists (select 1 from jsonb_array_elements(r -> 'alunos') x
    where (x ->> 'id')::uuid = v_aluno and x -> 'atual' ->> 'nivel' = 'ALFABETICO'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-dir-ei', 'alfabetizacao_turma', jsonb_build_object('class_id', v_turma_pre));
  v_out := v_out || jsonb_build_object('passo', 'A3. Sondagem não se aplica à educação infantil', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s2-dir', 'risco_lista', '{}');
  v_risco := (select (x ->> 'student_id')::uuid from jsonb_array_elements(r -> 'itens') x where x -> 'plano' = 'null'::jsonb or x -> 'plano' is null limit 1);
  v_out := v_out || jsonb_build_object('passo', 'R1. Direção vê os alunos em risco (notas, frequência, alfabetização)', 'ok', (r ->> 'total')::int > 0 and (r ->> 'pode_planejar')::boolean
    and v_risco is not null, 'total', r ->> 'total', 'motivos', r -> 'por_motivo', 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-dir', 'plano_salvar', jsonb_build_object('student_id', v_risco, 'motivos', jsonb_build_array('NOTAS'),
         'objetivo', 'Recuperar Matemática até o fim do bimestre.', 'acoes', 'Contraturno às terças; jogos de tabuada; devolutiva quinzenal.'));
  v_plano := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'R2. Plano de intervenção registrado e família avisada', 'ok', v_plano is not null and r ->> 'situacao' = 'ATIVO'
    and exists (select 1 from iara.notifications n where n.student_id = v_risco and n.event_type = 'PLANO_APOIO'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-dir', 'plano_reavaliar', jsonb_build_object('id', v_plano, 'situacao', 'SUPERADO'));
  v_out := v_out || jsonb_build_object('passo', 'R3. Reavaliação sem resultado é recusada', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s2-dir', 'plano_reavaliar', jsonb_build_object('id', v_plano, 'situacao', 'SUPERADO', 'resultado', 'Atingiu 7,5 na recuperação.'));
  v_out := v_out || jsonb_build_object('passo', 'R4. Reavaliação registrada', 'ok', r ->> 'situacao' = 'SUPERADO', 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-dir-outra', 'plano_reavaliar', jsonb_build_object('id', v_plano, 'situacao', 'ENCERRADO', 'resultado', 'Tentativa de outra unidade.'));
  v_out := v_out || jsonb_build_object('passo', 'R5. Outra unidade não mexe no plano (deve negar)', 'ok', pg_temp.ok_erro(r, 'P0002'));

  -- AEE -----------------------------------------------------------------------------------------------------------------------
  r := pg_temp.as_call('s2-aee', 'aee_lista', jsonb_build_object('situacao', 'MEUS'));
  v_aee_aluno := (select (x ->> 'student_id')::uuid from jsonb_array_elements(r -> 'itens') x
                  where exists (select 1 from iara.enrollments e where e.student_id = (x ->> 'student_id')::uuid and e.unit_id = v_unit and e.status = 'ACTIVE') limit 1);
  v_out := v_out || jsonb_build_object('passo', 'E1. Professor(a) do AEE vê os alunos que atende, inclusive de outra escola (itinerante)', 'ok',
    (r -> 'contagem' ->> 'meus')::int > 0 and v_aee_aluno is not null and r ? 'hoje', 'meus', r -> 'contagem' ->> 'meus', 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-aee', 'aee_plano', jsonb_build_object('student_id', v_aee_aluno));
  v_aee_plano := (r -> 'plano' ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'E2. Plano completo com a necessidade e edição', 'ok', r -> 'necessidade' ->> 'special_education_need' is not null
    and (r ->> 'pode_editar')::boolean and r -> 'plano' ->> 'objetivos' is not null and not (r -> 'necessidade' ? 'legal_notes'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-prof-ei', 'aee_plano', jsonb_build_object('student_id', v_aee_aluno));
  v_out := v_out || jsonb_build_object('passo', 'E3. Regente não abre o plano completo (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s2-dir-ei', 'aee_orientacoes_turma', jsonb_build_object('class_id', (select class_id from iara.enrollments where student_id = v_aee_aluno and status = 'ACTIVE')));
  v_out := v_out || jsonb_build_object('passo', 'E4. Orientações de sala sem diagnóstico, objetivos ou avaliação', 'ok', pg_temp.n(r) > 0
    and not exists (select 1 from jsonb_array_elements(r) x where x -> 'plano' ? 'objetivos' or x -> 'plano' ? 'avaliacao_inicial' or x ? 'necessidade'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-dir-outra', 'aee_plano', jsonb_build_object('student_id', v_aee_aluno));
  v_out := v_out || jsonb_build_object('passo', 'E5. Direção de outra unidade não abre (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s2-aee', 'aee_atendimento_registrar', jsonb_build_object('plano_id', v_aee_plano, 'data', current_date + 1, 'presenca', 'PRESENTE', 'atividade', 'Jogo'));
  v_out := v_out || jsonb_build_object('passo', 'E6. Atendimento com data futura é recusado', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s2-aee', 'aee_atendimento_registrar', jsonb_build_object('plano_id', v_aee_plano, 'presenca', 'PRESENTE', 'atividade', 'Rotina visual e jogo de encaixe'));
  v_out := v_out || jsonb_build_object('passo', 'E7. Professor(a) do AEE registra o atendimento de hoje', 'ok', r ->> 'presenca' = 'PRESENTE', 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-aee', 'aee_plano_salvar', jsonb_build_object('id', v_aee_plano, 'student_id', v_aee_aluno, 'situacao', 'ATIVO', 'objetivos', 'Ampliar a comunicação funcional na rotina.',
         'dias', jsonb_build_array('TER'), 'profissional_id', (select profissional_id from iara.aee_planos where id = v_aee_plano), 'modalidade', 'ITINERANTE', 'orientacoes_sala', ''));
  v_out := v_out || jsonb_build_object('passo', 'E8. Ativar sem orientações para a sala é recusado', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s2-sec-ei', 'aee_plano_salvar', jsonb_build_object('id', v_aee_plano, 'student_id', v_aee_aluno, 'objetivos', 'Tentativa da secretaria escolar sem permissão.'));
  v_out := v_out || jsonb_build_object('passo', 'E9. Secretaria escolar consulta mas não altera o plano (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  -- família de um aluno com AEE (sessão criada só neste teste)
  select sg.guardian_id into v_guard from iara.student_guardians sg where sg.student_id = v_aee_aluno and sg.end_date is null limit 1;
  insert into iara.app_users (id, tenant_id, display_name, role_code, guardian_id, auth_provider, is_demo) values (v_user, 1, 'Família teste AEE', 'CIDADAO', v_guard, 'DEMO', true);
  insert into iara.app_sessions (token_hash, user_id, expires_at, user_agent) values ('s2-fam-aee', v_user, now() + interval '1 hour', 'teste');
  r := pg_temp.as_call('s2-fam-aee', 'familia_aee', '{}');
  v_out := v_out || jsonb_build_object('passo', 'E10. Família vê o plano (dias, objetivos) sem a avaliação técnica', 'ok', v_guard is not null and pg_temp.n(r) > 0
    and not exists (select 1 from jsonb_array_elements(r) x where x -> 'plano' ? 'avaliacao_inicial') and exists (select 1 from jsonb_array_elements(r) x where x -> 'plano' ? 'objetivos'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-fam-aee', 'familia_aee_ciente', jsonb_build_object('plano_id', v_aee_plano));
  v_out := v_out || jsonb_build_object('passo', 'E11. Família confirma ciência do plano', 'ok', (r ->> 'ok')::boolean and (select familia_ciente_em from iara.aee_planos where id = v_aee_plano) is not null, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-fam', 'familia_aee_ciente', jsonb_build_object('plano_id', v_aee_plano));
  v_out := v_out || jsonb_build_object('passo', 'E12. Outra família não dá ciência (deve negar)', 'ok', pg_temp.ok_erro(r, 'P0002'));
  r := pg_temp.as_call('s2-secretario', 'aee_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', 'E13. Secretário vê o painel agregado do AEE (sem nomes)', 'ok', (r ->> 'alunos')::int > 1000 and not (r ->> 'detalhe')::boolean
    and pg_temp.n(r -> 'por_unidade') > 0, 'sem_plano', r ->> 'sem_plano', 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-secretario', 'aee_lista', jsonb_build_object('unit_id', v_unit));
  v_out := v_out || jsonb_build_object('passo', 'E14. Secretário não abre a lista nominal do AEE (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));

  -- Declarações ---------------------------------------------------------------------------------------------------------------
  r := pg_temp.as_call('s2-fam', 'declaracao_emitir', jsonb_build_object('student_id', v_ana, 'tipo', 'MATRICULA'));
  v_cod := r ->> 'codigo'; v_decl := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'C1. Família emite declaração de matrícula (código de 12 caracteres)', 'ok', v_cod ~ '^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$'
    and r -> 'conteudo' ->> 'texto' like '%regularmente matriculado%', 'codigo', v_cod, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-fam', 'declaracao_emitir', jsonb_build_object('student_id', v_ana, 'tipo', 'FREQUENCIA'));
  v_out := v_out || jsonb_build_object('passo', 'C2. Declaração de frequência com o percentual', 'ok', r -> 'conteudo' -> 'frequencia' ->> 'percentual' is not null, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-fam', 'declaracao_emitir', jsonb_build_object('student_id', v_davi, 'tipo', 'INSCRICAO_FILA'));
  v_out := v_out || jsonb_build_object('passo', 'C3. Declaração de inscrição na fila (Davi)', 'ok', r -> 'conteudo' ->> 'texto' like '%fila de espera%', 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-fam', 'declaracao_emitir', jsonb_build_object('student_id', v_davi, 'tipo', 'MATRICULA'));
  v_out := v_out || jsonb_build_object('passo', 'C4. Sem matrícula não emite declaração de matrícula', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_anon('declaracao_verificar', jsonb_build_object('codigo', lower(replace(v_cod, '-', ' '))));
  v_out := v_out || jsonb_build_object('passo', 'C5. Verificação pública sem login: autêntica, nome abreviado, sem o texto', 'ok', (r ->> 'encontrada')::boolean
    and r ->> 'situacao' = 'VALIDA' and r ->> 'aluno' not like '%' || (select split_part(full_name, ' ', 2) from iara.students where id = v_ana) || '%'
    and not (r ? 'conteudo'), 'aluno', r ->> 'aluno', 'erro', r ->> 'erro');
  r := pg_temp.as_anon('declaracao_verificar', jsonb_build_object('codigo', 'ABCD-EFGH-JK23'));
  v_out := v_out || jsonb_build_object('passo', 'C6. Código inexistente: não autêntica', 'ok', not (r ->> 'encontrada')::boolean, 'erro', r ->> 'erro');
  r := pg_temp.as_anon('declaracao_emitir', jsonb_build_object('student_id', v_ana, 'tipo', 'MATRICULA'));
  v_out := v_out || jsonb_build_object('passo', 'C7. Sem login não emite (deve negar)', 'ok', r ? 'erro');
  r := pg_temp.as_call('s2-fam', 'declaracao_revogar', jsonb_build_object('id', v_decl, 'motivo', 'Família tentando revogar.'));
  v_out := v_out || jsonb_build_object('passo', 'C8. Família não revoga (deve negar)', 'ok', pg_temp.ok_erro(r, 'P0002'));
  r := pg_temp.as_call('s2-sec-ei', 'declaracao_revogar', jsonb_build_object('id', v_decl, 'motivo', 'Emitida com a turma errada.'));
  r := pg_temp.as_anon('declaracao_verificar', jsonb_build_object('codigo', v_cod));
  v_out := v_out || jsonb_build_object('passo', 'C9. Secretaria revoga e a verificação mostra REVOGADA', 'ok', r ->> 'situacao' = 'REVOGADA', 'erro', r ->> 'erro');
  r := pg_temp.as_call('s2-fam-nova', 'declaracao_ver', jsonb_build_object('id', v_decl));
  v_out := v_out || jsonb_build_object('passo', 'C10. Outra família não abre a declaração (deve negar)', 'ok', pg_temp.ok_erro(r, 'P0002') or pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s2-prof-ei', 'declaracao_emitir', jsonb_build_object('student_id', v_ana, 'tipo', 'MATRICULA'));
  v_out := v_out || jsonb_build_object('passo', 'C11. Professor não emite declaração (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));

  raise exception 'RESULTADO: %', v_out;
end $$;
