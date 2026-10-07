-- Ocorrências, agenda escolar, vida escolar na ficha do aluno e buscas com filtros: quem vê e quem lança o quê.
-- Roda numa transação revertida (não deixa resíduo). Cada passo traz "ok": true quando o comportamento é o esperado.
-- Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/ocorrencias_agenda.sql
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

create or replace function pg_temp.ok_erro(r jsonb, p_cod text) returns boolean language sql as $f$ select coalesce(r ->> 'codigo' = p_cod, false) $f$;
create or replace function pg_temp.n(r jsonb) returns integer language sql as $f$
  select case when jsonb_typeof(r) = 'array' then jsonb_array_length(r) else -1 end $f$;

do $$
declare
  v_out jsonb := '[]';
  r jsonb;
  v_ana uuid := (iara.setting('demo_student_ana'))::uuid;
  v_unit integer;
  v_outra integer;
  v_turma_ana uuid;
  v_turma_prof uuid;
  v_aluno_prof uuid;
  v_id uuid;
  v_ag uuid;
  v_ag_outra uuid;
begin
  select e.unit_id, e.class_id into v_unit, v_turma_ana from iara.enrollments e where e.student_id = v_ana and e.status = 'ACTIVE';
  select u.id into v_outra from iara.education_units u where u.status = 'ATIVA' and u.id <> v_unit
    and exists (select 1 from iara.classes c where c.unit_id = u.id and c.status = 'ATIVA') order by u.id limit 1;
  perform iara.session_create('PROFESSOR', v_unit, 'oa-prof', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_unit, 'oa-dir', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_outra, 'oa-dir-outra', 'teste');
  perform iara.session_create('SECRETARIA_ESCOLAR', v_unit, 'oa-sec', 'teste');
  perform iara.session_create('SECRETARIO', null, 'oa-secretario', 'teste');
  perform iara.session_create('CIDADAO', null, 'oa-fam', 'teste');
  perform iara.session_create('PREFEITO', null, 'oa-pref', 'teste');
  v_turma_prof := (select (t ->> 'id')::uuid from jsonb_array_elements(pg_temp.as_call('oa-prof', 'me', '{}') -> 'turmas') t limit 1);
  v_aluno_prof := (select student_id from iara.enrollments where class_id = v_turma_prof and status = 'ACTIVE' order by student_id limit 1);

  -- Ocorrências
  r := pg_temp.as_call('oa-prof', 'ocorrencia_registrar', jsonb_build_object('student_id', v_aluno_prof, 'tipo', 'ACIDENTE', 'descricao', 'Caiu no pátio e ralou o cotovelo.', 'providencias', 'Curativo.'));
  v_id := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'O1. Professor registra ocorrência de aluno da própria turma', 'ok', r ->> 'origem' = 'ESCOLA' and (r ->> 'aguarda_ciencia')::boolean, 'erro', r ->> 'erro');
  r := pg_temp.as_call('oa-prof', 'ocorrencia_registrar', jsonb_build_object('student_id', v_ana, 'tipo', 'OUTRO', 'descricao', 'Tentativa fora da turma.'));
  v_out := v_out || jsonb_build_object('passo', 'O2. Professor não registra para aluno de outra turma (deve negar)', 'ok', pg_temp.ok_erro(r, '42501') or v_turma_prof = v_turma_ana);
  r := pg_temp.as_call('oa-prof', 'ocorrencias_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', 'O3. Professor lista só ocorrências das próprias turmas', 'ok', r ->> 'erro' is null
    and not exists (select 1 from jsonb_array_elements(r -> 'itens') x
                    where (x ->> 'class_id')::uuid not in (select (t ->> 'id')::uuid from jsonb_array_elements(pg_temp.as_call('oa-prof', 'me', '{}') -> 'turmas') t)),
    'erro', r ->> 'erro');
  r := pg_temp.as_call('oa-fam', 'familia_ocorrencias', '{}');
  v_out := v_out || jsonb_build_object('passo', 'O4. Família vê as ocorrências da Ana (uma aguardando ciência)', 'ok', (r ->> 'aguardando_ciencia')::int >= 1
    and not exists (select 1 from jsonb_array_elements(r -> 'ocorrencias') x where (x ->> 'student_id')::uuid not in
                    (select sg.student_id from iara.student_guardians sg where sg.guardian_id = (iara.setting('demo_guardian_maria'))::uuid)), 'erro', r ->> 'erro');
  v_id := (select (x ->> 'id')::uuid from jsonb_array_elements(r -> 'ocorrencias') x where (x ->> 'aguarda_ciencia')::boolean limit 1);
  r := pg_temp.as_call('oa-fam', 'familia_ocorrencia_ciente', jsonb_build_object('id', v_id));
  r := pg_temp.as_call('oa-fam', 'ocorrencia_atualizar', jsonb_build_object('id', v_id, 'texto', 'Obrigada, ela está bem.', 'situacao', 'ENCERRADA'));
  v_out := v_out || jsonb_build_object('passo', 'O5. Família dá ciência e comenta, mas não encerra', 'ok', r ->> 'situacao' <> 'ENCERRADA' and r ->> 'ciencia_familia_em' is not null
    and (r -> 'eventos' -> -1 ->> 'origem') = 'FAMILIA', 'erro', r ->> 'erro');
  r := pg_temp.as_call('oa-dir', 'ocorrencia_atualizar', jsonb_build_object('id', v_id, 'texto', 'Família ciente; encerrado.', 'situacao', 'ENCERRADA'));
  v_out := v_out || jsonb_build_object('passo', 'O6. Direção encerra', 'ok', r ->> 'situacao' = 'ENCERRADA', 'erro', r ->> 'erro');
  r := pg_temp.as_call('oa-dir-outra', 'ocorrencia_detalhe', jsonb_build_object('id', v_id));
  v_out := v_out || jsonb_build_object('passo', 'O7. Outra unidade não abre (deve negar)', 'ok', pg_temp.ok_erro(r, 'P0002'));
  r := pg_temp.as_call('oa-fam', 'ocorrencia_registrar', jsonb_build_object('student_id', v_ana, 'tipo', 'BULLYING', 'descricao', 'Ela contou que um colega puxa o cabelo dela.'));
  v_out := v_out || jsonb_build_object('passo', 'O8. Família relata ocorrência (origem família, moderada)', 'ok', r ->> 'origem' = 'FAMILIA' and r ->> 'gravidade' = 'MODERADA', 'erro', r ->> 'erro');
  r := pg_temp.as_call('oa-fam', 'ocorrencia_registrar', jsonb_build_object('student_id', v_aluno_prof, 'tipo', 'OUTRO', 'descricao', 'Criança de outra família.'));
  v_out := v_out || jsonb_build_object('passo', 'O9. Família não relata por criança de outra família (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('oa-pref', 'ocorrencias_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', 'O10. Prefeito não lista ocorrências (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('oa-secretario', 'ocorrencias_lista', jsonb_build_object('situacao', 'PENDENTES'));
  v_out := v_out || jsonb_build_object('passo', 'O11. Secretário vê a rede (só consulta)', 'ok', pg_temp.n(r -> 'itens') > 0 and not (r ->> 'pode_registrar')::boolean, 'erro', r ->> 'erro');

  -- Agenda
  r := pg_temp.as_call('oa-prof', 'agenda_publicar', jsonb_build_object('class_id', v_turma_prof, 'tipo', 'TAREFA', 'titulo', 'Leitura', 'texto', 'Ler o livro da semana.'));
  v_out := v_out || jsonb_build_object('passo', 'A1. Professor publica na agenda da própria turma', 'ok', r ->> 'tipo' = 'TAREFA', 'erro', r ->> 'erro');
  r := pg_temp.as_call('oa-prof', 'agenda_publicar', jsonb_build_object('class_id', (select id from iara.classes where unit_id = v_outra and status = 'ATIVA' limit 1), 'texto', 'Fora do escopo.'));
  v_out := v_out || jsonb_build_object('passo', 'A2. Professor não publica em turma de outra unidade (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('oa-fam', 'familia_agenda', '{}');
  v_ag := (select (x ->> 'id')::uuid from jsonb_array_elements(r -> 'itens') x where (x ->> 'exige_ciencia')::boolean and not (x ->> 'ciente')::boolean limit 1);
  v_out := v_out || jsonb_build_object('passo', 'A3. Família vê a agenda da turma da Ana (passeio pede ciência)', 'ok', v_ag is not null
    and exists (select 1 from jsonb_array_elements(r -> 'itens') x where x ->> 'tipo' = 'BILHETE'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('oa-fam', 'familia_agenda_ciente', jsonb_build_object('id', v_ag, 'student_id', v_ana));
  r := pg_temp.as_call('oa-fam', 'familia_agenda', '{}');
  v_out := v_out || jsonb_build_object('passo', 'A4. Ciência registrada', 'ok', exists (select 1 from jsonb_array_elements(r -> 'itens') x where (x ->> 'id')::uuid = v_ag and (x ->> 'ciente')::boolean));
  v_ag_outra := (select id from iara.agenda_escolar where class_id <> v_turma_ana and student_id is null limit 1);
  r := pg_temp.as_call('oa-fam', 'familia_agenda_ciente', jsonb_build_object('id', v_ag_outra, 'student_id', v_ana));
  v_out := v_out || jsonb_build_object('passo', 'A5. Família não marca recado de outra turma (deve negar)', 'ok', pg_temp.ok_erro(r, 'P0002'));
  r := pg_temp.as_call('oa-fam', 'familia_agenda_enviar', jsonb_build_object('student_id', v_ana, 'texto', 'A Ana vai sair mais cedo amanhã, às 16h, com o pai.'));
  r := pg_temp.as_call('oa-dir', 'agenda_turma', jsonb_build_object('class_id', v_turma_ana));
  v_out := v_out || jsonb_build_object('passo', 'A6. Bilhete da família aparece na agenda da turma para a escola', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'itens') x where x ->> 'origem' = 'FAMILIA' and x ->> 'texto' like 'A Ana vai sair%'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('oa-fam', 'agenda_turma', jsonb_build_object('class_id', v_turma_ana));
  v_out := v_out || jsonb_build_object('passo', 'A7. Família não abre a agenda da turma inteira pela escola (deve negar)', 'ok', pg_temp.ok_erro(r, 'P0002'));

  -- Ficha do aluno
  r := pg_temp.as_call('oa-dir', 'aluno_vida_escolar', jsonb_build_object('student_id', v_ana));
  v_out := v_out || jsonb_build_object('passo', 'F1. Direção vê alimentação, ocorrências e agenda da Ana', 'ok', pg_temp.n(r -> 'ocorrencias') >= 2 and pg_temp.n(r -> 'agenda') > 0
    and (r ->> 'pode_ocorrencia')::boolean, 'erro', r ->> 'erro');
  r := pg_temp.as_call('oa-dir-outra', 'aluno_vida_escolar', jsonb_build_object('student_id', v_ana));
  v_out := v_out || jsonb_build_object('passo', 'F2. Outra unidade não vê (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('oa-sec', 'aluno_restricao_registrar', jsonb_build_object('student_id', v_ana, 'codigo', 'SOJA', 'laudo_entregue', true));
  v_out := v_out || jsonb_build_object('passo', 'F3. Secretaria registra restrição trazida ao balcão (aguarda a nutrição)', 'ok', (r ->> 'ok')::boolean
    and exists (select 1 from iara.aluno_restricoes where student_id = v_ana and restricao_codigo = 'SOJA' and situacao = 'INFORMADA' and origem = 'UNIDADE'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('oa-prof', 'aluno_restricao_registrar', jsonb_build_object('student_id', v_aluno_prof, 'codigo', 'SOJA'));
  v_out := v_out || jsonb_build_object('passo', 'F4. Professor não registra restrição (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));

  -- Buscas
  r := pg_temp.as_call('oa-secretario', 'alunos_lista', jsonb_build_object('restricao', 'QUALQUER', 'limite', 100));
  v_out := v_out || jsonb_build_object('passo', 'B1. Busca de alunos com restrição alimentar', 'ok', (r ->> 'total')::int > 0
    and not exists (select 1 from jsonb_array_elements(r -> 'itens') x where pg_temp.n(x -> 'restricoes') = 0), 'total', r ->> 'total');
  r := pg_temp.as_call('oa-secretario', 'alunos_lista', jsonb_build_object('q', 'ana lu', 'sexo', 'F', 'idade_min', 4, 'idade_max', 6, 'limite', 100));
  v_out := v_out || jsonb_build_object('passo', 'B2. Nome parcial + sexo + idade', 'ok', exists (select 1 from jsonb_array_elements(r -> 'itens') x where (x ->> 'id')::uuid = v_ana)
    and not exists (select 1 from jsonb_array_elements(r -> 'itens') x where x ->> 'sexo' <> 'F'), 'total', r ->> 'total');
  r := pg_temp.as_call('oa-dir', 'alunos_lista', jsonb_build_object('ocorrencias', 'ABERTAS', 'turma_id', v_turma_ana));
  v_out := v_out || jsonb_build_object('passo', 'B3. Unidade: ocorrências em aberto na turma', 'ok', r ->> 'erro' is null
    and not exists (select 1 from jsonb_array_elements(r -> 'itens') x where (x ->> 'ocorrencias_abertas')::int = 0) and pg_temp.n(r -> 'turmas') > 0, 'erro', r ->> 'erro');
  r := pg_temp.as_call('oa-secretario', 'pessoal_lista', jsonb_build_object('carga', 'EXCESSO'));
  v_out := v_out || jsonb_build_object('passo', 'B4. Profissionais com aulas acima da capacidade', 'ok', (r ->> 'total')::int > 0
    and not exists (select 1 from jsonb_array_elements(r -> 'itens') x where (x ->> 'disponivel')::int >= 0), 'total', r ->> 'total');
  r := pg_temp.as_call('oa-secretario', 'pessoal_lista', jsonb_build_object('q', 'silva', 'regiao_id', (select id from iara.territories where kind = 'MACRORREGIAO' order by id limit 1), 'situacao', 'ATIVO'));
  v_out := v_out || jsonb_build_object('passo', 'B5. Profissionais: nome parcial + região + situação', 'ok', r ->> 'erro' is null and pg_temp.n(r -> 'opcoes' -> 'regioes') = 5
    and not exists (select 1 from jsonb_array_elements(r -> 'itens') x where x ->> 'nome' not ilike '%silva%' or x ->> 'situacao' <> 'ATIVO'), 'total', r ->> 'total');

  raise exception 'RESULTADO: %', v_out;
end $$;
