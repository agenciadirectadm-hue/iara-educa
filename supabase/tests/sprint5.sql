-- Sprint 5: conteúdos ministrados, rematrícula, transferência entre unidades, ensalamento e eventos/certificados.
-- Roda numa transação revertida (não deixa resíduo). Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/sprint5.sql
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
create or replace function pg_temp.sessao_familia(p_hash text, p_guardian uuid) returns void language plpgsql as $f$
declare v_u uuid := gen_random_uuid();
begin
  insert into iara.app_users (id, tenant_id, display_name, role_code, guardian_id, auth_provider, is_demo) values (v_u, 1, 'Família teste', 'CIDADAO', p_guardian, 'DEMO', true);
  insert into iara.app_sessions (token_hash, user_id, expires_at, user_agent) values (p_hash, v_u, now() + interval '1 hour', 'teste');
end $f$;

do $$
declare
  v_out jsonb := '[]';
  r jsonb;
  v_t0 timestamptz := now();
  v_unit integer;
  v_outra integer;
  v_turma uuid;
  v_aluno uuid;
  v_g uuid;
  v_dia date;
  v_aula smallint;
  v_rem uuid;
  v_t record;
  v_tr uuid;
  v_classe uuid;
  v_sala uuid;
  v_sala2 uuid;
  v_ev uuid;
  v_part uuid;
  v_cod text;
  v_st uuid;
  v_fila_unit integer;
begin
  select u.id into v_unit from iara.education_units u where u.status = 'ATIVA' and u.unit_type <> 'CMEI'
    and exists (select 1 from iara.classes c join iara.grade_levels g on g.id = c.grade_level_id where c.unit_id = u.id and g.code = 'EF3') order by u.id limit 1;
  select u.id into v_outra from iara.education_units u where u.status = 'ATIVA' and u.id <> v_unit and u.unit_type <> 'CMEI' order by u.id limit 1;
  perform iara.session_create('PROFESSOR', v_unit, 's5-prof', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_unit, 's5-dir', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_outra, 's5-dir2', 'teste');
  perform iara.session_create('SECRETARIO', null, 's5-seduc', 'teste');
  v_turma := (select (t ->> 'id')::uuid from jsonb_array_elements(pg_temp.as_call('s5-prof', 'me', '{}') -> 'turmas') t limit 1);
  select e.student_id into v_aluno from iara.enrollments e where e.class_id = v_turma and e.status = 'ACTIVE' order by e.student_id limit 1;
  select sg.guardian_id into v_g from iara.student_guardians sg where sg.student_id = v_aluno and sg.end_date is null order by sg.is_primary desc limit 1;
  perform pg_temp.sessao_familia('s5-fam', v_g);

  -- conteúdos ministrados
  select max(ap.data) into v_dia from iara.aulas_previstas(v_turma, iara.hoje_local() - 10, iara.hoje_local()) ap;
  select ap.aula into v_aula from iara.aulas_previstas(v_turma, v_dia, v_dia) ap order by ap.aula limit 1;
  delete from iara.aulas_registros where class_id = v_turma and data = v_dia and aula = v_aula;
  r := pg_temp.as_call('s5-prof', 'aulas_dia', jsonb_build_object('class_id', v_turma, 'data', v_dia));
  v_out := v_out || jsonb_build_object('passo', 'L1. Professor vê o horário do dia com as aulas a registrar', 'ok', (r ->> 'pode_registrar')::boolean and jsonb_array_length(r -> 'aulas') > 0, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s5-prof', 'aula_registrar', jsonb_build_object('class_id', v_turma, 'data', v_dia, 'aula', v_aula, 'conteudo', 'Problemas de divisão com resto',
    'habilidades', jsonb_build_array('EF03MA08'), 'atividade', 'Jogo em duplas', 'tarefa', 'Resolver os 3 problemas da folha'));
  v_out := v_out || jsonb_build_object('passo', 'L2. Professor registra o conteúdo, a habilidade da BNCC e a tarefa', 'ok', r ->> 'erro' is null
    and exists (select 1 from iara.aulas_registros where class_id = v_turma and data = v_dia and aula = v_aula and conteudo like 'Problemas de divisão%'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s5-prof', 'aula_registrar', jsonb_build_object('class_id', v_turma, 'data', iara.hoje_local() + 1, 'aula', 1, 'conteudo', 'Aula futura'));
  v_out := v_out || jsonb_build_object('passo', 'L3. Não registra aula futura', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s5-prof', 'aula_registrar', jsonb_build_object('class_id', v_turma, 'data', v_dia, 'aula', v_aula, 'conteudo', 'Conteúdo válido', 'habilidades', jsonb_build_array('MATEMATICA1')));
  v_out := v_out || jsonb_build_object('passo', 'L4. Código da BNCC inválido é recusado', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s5-dir', 'aula_registrar', jsonb_build_object('class_id', v_turma, 'data', v_dia, 'aula', v_aula, 'conteudo', 'Registro da direção'));
  v_out := v_out || jsonb_build_object('passo', 'L5. Só o professor da turma registra o conteúdo', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s5-dir', 'aulas_pendencias', '{}');
  v_out := v_out || jsonb_build_object('passo', 'L6. Direção vê aulas sem registro por turma e professor', 'ok', r ->> 'erro' is null and jsonb_array_length(r -> 'turmas') > 0
    and (r ->> 'previstas')::int >= (r ->> 'registradas')::int, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s5-fam', 'familia_aulas', '{}');
  v_out := v_out || jsonb_build_object('passo', 'L7. Família vê o que o filho estudou e a tarefa', 'ok', exists (select 1 from jsonb_array_elements(r) k, jsonb_array_elements(k -> 'dias') d,
    jsonb_array_elements(d -> 'aulas') a where (k ->> 'student_id')::uuid = v_aluno and a ->> 'tarefa' = 'Resolver os 3 problemas da folha'), 'erro', r ->> 'erro');

  -- rematrícula
  update iara.rematriculas set situacao = 'PENDENTE', confirmada_em = null where student_id = v_aluno and ano = 2027;
  r := pg_temp.as_call('s5-fam', 'familia_rematricula', '{}');
  select (x ->> 'id')::uuid into v_rem from jsonb_array_elements(r) x where (x ->> 'student_id')::uuid = v_aluno;
  v_out := v_out || jsonb_build_object('passo', 'R1. Família vê a rematrícula de 2027 (série, unidade e turno)', 'ok', v_rem is not null, 'erro', coalesce(r ->> 'erro', r::text));
  r := pg_temp.as_call('s5-fam', 'rematricula_responder', jsonb_build_object('id', v_rem, 'acao', 'CONFIRMAR', 'turno', 'NOITE'));
  v_out := v_out || jsonb_build_object('passo', 'R2. Turno que a unidade não oferece é recusado', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s5-fam', 'rematricula_responder', jsonb_build_object('id', v_rem, 'acao', 'CONFIRMAR', 'canal', 'PORTAL'));
  v_out := v_out || jsonb_build_object('passo', 'R3. Família confirma a rematrícula', 'ok', r ->> 'situacao' in ('CONFIRMADA', 'AGUARDANDO_RESULTADO') and r ->> 'mensagem' is not null, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s5-dir2', 'rematricula_responder', jsonb_build_object('id', v_rem, 'acao', 'CONFIRMAR'));
  v_out := v_out || jsonb_build_object('passo', 'R4. Outra unidade não responde pela família', 'ok', pg_temp.ok_erro(r, 'P0002'));
  r := pg_temp.as_call('s5-dir', 'rematricula_responder', jsonb_build_object('id', v_rem, 'acao', 'NAO_RENOVAR'));
  v_out := v_out || jsonb_build_object('passo', 'R5. Não renovar exige o motivo', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s5-dir', 'rematricula_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', 'R6. Direção vê resumo e projeção de vagas de 2027', 'ok', r ->> 'erro' is null and (r -> 'resumo' ->> 'total')::int > 0 and jsonb_array_length(r -> 'projecao') > 0, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s5-seduc', 'rematricula_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', 'R7. SEDUC vê a rede (confirmação por unidade e onde falta vaga)', 'ok', r ->> 'erro' is null and jsonb_array_length(r -> 'unidades') > 0, 'erro', r ->> 'erro');
  v_out := v_out || jsonb_build_object('passo', 'R8. Data de corte: criança da pré com 5 anos em 31/03 continua na pré; com 6 anos vai ao 1º ano', 'ok',
    iara.proxima_serie('PRE', date '2021-06-10', 2027) = 'PRE' and iara.proxima_serie('PRE', date '2021-02-10', 2027) = 'EF1' and iara.proxima_serie('EF5', date '2016-01-01', 2027) = 'EF6_ESTADUAL');

  -- transferência entre unidades
  select e.student_id sid, e.unit_id orig, c.grade_level_id gid, c.shift, d.id dest into v_t
  from iara.enrollments e join iara.classes c on c.id = e.class_id
  join lateral (select u.id from iara.education_units u where u.id <> e.unit_id and u.status = 'ATIVA'
                  and exists (select 1 from iara.classes c2 where c2.unit_id = u.id and c2.grade_level_id = c.grade_level_id and c2.shift = c.shift and c2.status = 'ATIVA' and c2.offerable_vacancies_count > 0)
                  and not exists (select 1 from iara.waiting_list_entries w where w.preferred_unit_id = u.id and w.grade_level_id = c.grade_level_id and w.status = 'WAITING') limit 1) d on true
  where e.status = 'ACTIVE' and e.unit_id = v_unit and not exists (select 1 from iara.transferencias t where t.student_id = e.student_id and t.situacao = 'AGUARDANDO_DESTINO') limit 1;
  perform iara.session_create('DIRETOR_UNIDADE', v_t.dest, 's5-dir-dest', 'teste');
  r := pg_temp.as_call('s5-dir', 'transferencia_solicitar', jsonb_build_object('student_id', v_t.sid, 'unit_destino', v_t.dest, 'motivo_tipo', 'MUDANCA_ENDERECO', 'motivo', 'Mudou de bairro'));
  v_tr := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'T1. Pedido com vaga e sem fila vai para o aceite do destino', 'ok', r ->> 'situacao' = 'AGUARDANDO_DESTINO', 'erro', coalesce(r ->> 'erro', r ->> 'situacao'));
  r := pg_temp.as_call('s5-dir', 'transferencia_solicitar', jsonb_build_object('student_id', v_t.sid, 'unit_destino', v_t.dest, 'motivo_tipo', 'OUTRO'));
  v_out := v_out || jsonb_build_object('passo', 'T2. Não abre dois pedidos para a mesma criança', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s5-dir', 'transferencia_responder', jsonb_build_object('id', v_tr, 'aceitar', true, 'class_id', (select id from iara.classes where unit_id = v_t.dest limit 1)));
  v_out := v_out || jsonb_build_object('passo', 'T3. A origem não aceita no lugar do destino', 'ok', pg_temp.ok_erro(r, '42501'));
  select c.id into v_classe from iara.classes c where c.unit_id = v_t.dest and c.grade_level_id = v_t.gid and c.shift = v_t.shift and c.status = 'ATIVA' and c.offerable_vacancies_count > 0 limit 1;
  r := pg_temp.as_call('s5-dir-dest', 'transferencia_responder', jsonb_build_object('id', v_tr, 'aceitar', true, 'class_id', v_classe));
  v_out := v_out || jsonb_build_object('passo', 'T4. O destino aceita: a matrícula muda na hora e as vagas são recontadas', 'ok', r ->> 'situacao' = 'EFETIVADA'
    and (select unit_id from iara.enrollments where student_id = v_t.sid and status = 'ACTIVE') = v_t.dest
    and exists (select 1 from iara.enrollments where student_id = v_t.sid and status = 'TRANSFERRED' and exit_type = 'TRANSFERENCIA_INTERNA'), 'erro', r ->> 'erro');
  select e.student_id, w.preferred_unit_id into v_st, v_fila_unit
  from iara.enrollments e join iara.classes c on c.id = e.class_id
  join iara.waiting_list_entries w on w.grade_level_id = c.grade_level_id and w.status = 'WAITING' and w.preferred_unit_id <> e.unit_id
  where e.unit_id = v_unit and e.status = 'ACTIVE' and e.student_id <> v_t.sid
    and exists (select 1 from iara.classes c3 where c3.unit_id = w.preferred_unit_id and c3.grade_level_id = c.grade_level_id and c3.shift = c.shift and c3.status = 'ATIVA')
  limit 1;
  if v_st is not null then
    r := pg_temp.as_call('s5-dir', 'transferencia_solicitar', jsonb_build_object('student_id', v_st, 'unit_destino', v_fila_unit, 'motivo_tipo', 'IRMAOS'));
    v_out := v_out || jsonb_build_object('passo', 'T5. Com fila na série do destino, o pedido vai para a fila (IN 025)', 'ok', r ->> 'situacao' = 'FILA', 'erro', coalesce(r ->> 'erro', r ->> 'situacao'));
  else
    v_out := v_out || jsonb_build_object('passo', 'T5. Com fila na série do destino, o pedido vai para a fila (IN 025) — sem cenário nesta base', 'ok', true);
  end if;

  -- ensalamento
  r := pg_temp.as_call('s5-dir', 'ensalamento', '{}');
  v_out := v_out || jsonb_build_object('passo', 'E1. Direção vê salas, ocupação por turno e salas livres', 'ok', r ->> 'erro' is null and jsonb_array_length(r -> 'salas') > 0, 'erro', r ->> 'erro');
  select c.sala_id into v_sala from iara.classes c where c.unit_id = v_unit and c.status = 'ATIVA' and c.sala_id is not null and c.id <> v_turma
    and c.shift = (select shift from iara.classes where id = v_turma) limit 1;
  r := pg_temp.as_call('s5-dir', 'turma_sala', jsonb_build_object('class_id', v_turma, 'sala_id', v_sala));
  v_out := v_out || jsonb_build_object('passo', 'E2. Sala ocupada no mesmo turno é recusada', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s5-dir', 'sala_salvar', jsonb_build_object('nome', 'Sala teste pequena', 'capacidade', 5));
  r := pg_temp.as_call('s5-dir', 'turma_sala', jsonb_build_object('class_id', v_turma, 'sala_id', r ->> 'id'));
  v_out := v_out || jsonb_build_object('passo', 'E3. Turma maior que a sala é recusada', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s5-dir', 'sala_salvar', jsonb_build_object('nome', 'Sala teste nova', 'capacidade', 45, 'area_m2', 60, 'acessivel', true));
  v_sala2 := (r ->> 'id')::uuid;
  r := pg_temp.as_call('s5-dir', 'turma_sala', jsonb_build_object('class_id', v_turma, 'sala_id', v_sala2));
  v_out := v_out || jsonb_build_object('passo', 'E4. Turma vai para a sala livre e acessível', 'ok', (select sala_id from iara.classes where id = v_turma) = v_sala2, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s5-dir', 'sala_salvar', jsonb_build_object('id', v_sala2, 'excluir', true));
  v_out := v_out || jsonb_build_object('passo', 'E5. Sala com turma não é excluída', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s5-seduc', 'ensalamento', '{}');
  v_out := v_out || jsonb_build_object('passo', 'E6. SEDUC vê salas livres por turno cruzadas com a fila', 'ok', r ->> 'erro' is null and jsonb_array_length(r -> 'unidades') > 0, 'erro', r ->> 'erro');

  -- eventos e certificados
  r := pg_temp.as_call('s5-seduc', 'evento_salvar', jsonb_build_object('titulo', 'Formação de teste: avaliação formativa', 'tipo', 'FORMACAO', 'publico', 'SERVIDORES',
    'inicio', iara.hoje_local() - 2, 'fim', iara.hoje_local() - 1, 'carga_horaria', 8));
  v_ev := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'V1. SEDUC cria formação da rede', 'ok', v_ev is not null, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s5-dir', 'evento_participantes', jsonb_build_object('evento_id', v_ev, 'acao', 'INSCREVER', 'staff_id', (select id from iara.staff limit 1)));
  v_out := v_out || jsonb_build_object('passo', 'V2. Direção de unidade não gere evento da rede', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s5-seduc', 'evento_participantes', jsonb_build_object('evento_id', v_ev, 'acao', 'INSCREVER', 'staff_id', (select id from iara.staff order by id limit 1)));
  r := pg_temp.as_call('s5-seduc', 'evento_participantes', jsonb_build_object('evento_id', v_ev, 'acao', 'INSCREVER', 'staff_id', (select id from iara.staff order by id offset 1 limit 1)));
  r := pg_temp.as_call('s5-seduc', 'evento_participantes', jsonb_build_object('evento_id', v_ev, 'acao', 'INSCREVER', 'student_id', v_aluno));
  v_out := v_out || jsonb_build_object('passo', 'V3. Aluno não entra em formação de servidores', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s5-seduc', 'evento_participantes', jsonb_build_object('evento_id', v_ev, 'acao', 'CONCLUIR'));
  v_out := v_out || jsonb_build_object('passo', 'V4. Não conclui sem a presença de todos', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s5-seduc', 'evento_participantes', jsonb_build_object('evento_id', v_ev, 'acao', 'PRESENCA',
    'itens', (select jsonb_agg(jsonb_build_object('id', z.id, 'presenca', case when z.rn = 1 then 90 else 50 end))
              from (select id, row_number() over (order by nome) rn from iara.evento_participantes where evento_id = v_ev) z)));
  r := pg_temp.as_call('s5-seduc', 'evento_participantes', jsonb_build_object('evento_id', v_ev, 'acao', 'CONCLUIR'));
  v_out := v_out || jsonb_build_object('passo', 'V5. Conclui: certificado só para quem atingiu 75% de presença', 'ok', r ->> 'situacao' = 'CONCLUIDO' and (r ->> 'afetados')::int = 1, 'erro', r ->> 'erro');
  select certificado_codigo into v_cod from iara.evento_participantes where evento_id = v_ev and certificado_codigo is not null;
  r := api.declaracao_verificar(jsonb_build_object('codigo', v_cod));
  v_out := v_out || jsonb_build_object('passo', 'V6. Certificado confere na verificação pública (nome abreviado)', 'ok', (r ->> 'encontrada')::boolean and r ->> 'tipo' = 'CERTIFICADO', 'erro', r::text);
  r := pg_temp.as_call('s5-seduc', 'evento_salvar', jsonb_build_object('id', v_ev, 'titulo', 'Mudança depois de concluir', 'inicio', iara.hoje_local() - 2, 'fim', iara.hoje_local() - 1, 'carga_horaria', 10));
  v_out := v_out || jsonb_build_object('passo', 'V7. Evento concluído não muda (certificados emitidos)', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s5-fam', 'familia_eventos', '{}');
  v_out := v_out || jsonb_build_object('passo', 'V8. Família vê eventos e certificados do filho', 'ok', r ->> 'erro' is null and jsonb_typeof(r) = 'array', 'erro', r ->> 'erro');

  -- limpeza da demonstração
  r := iara.demo_purge_sprint5(v_t0);
  v_out := v_out || jsonb_build_object('passo', 'X1. Limpeza desfaz a transferência (matrícula volta à origem), aulas, salas e eventos criados ao vivo', 'ok',
    (select unit_id from iara.enrollments where student_id = v_t.sid and status = 'ACTIVE') = v_t.orig
    and not exists (select 1 from iara.aulas_registros where not is_demo and created_at >= v_t0) and not exists (select 1 from iara.eventos where not is_demo and criado_em >= v_t0)
    and not exists (select 1 from iara.salas where not is_demo and criado_em >= v_t0), 'erro', r::text);

  raise exception 'RESULTADO: %', v_out;
end $$;
