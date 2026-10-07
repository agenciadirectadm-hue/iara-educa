-- Sprint 1 (pessoal, frequência, cardápio e nutrição, manutenção, mural e calendário): quem vê e quem lança o quê.
-- Roda numa transação revertida (não deixa resíduo). Cada passo traz "ok": true quando o comportamento é o esperado.
-- Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/sprint1_modulos.sql
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
  v_turma uuid;
  v_turma_outra uuid;
  v_aluno uuid;
  v_staff uuid;
  v_dia date;
  v_id uuid;
  v_pub uuid;
  v_pub_outra uuid;
  v_enq uuid;
begin
  select e.unit_id into v_unit from iara.enrollments e where e.student_id = v_ana and e.status = 'ACTIVE';
  select u.id into v_outra from iara.education_units u where u.status = 'ATIVA' and u.id <> v_unit
    and exists (select 1 from iara.classes c where c.unit_id = u.id and c.status = 'ATIVA') order by u.id limit 1;
  select c.id into v_turma_outra from iara.classes c where c.unit_id = v_outra and c.status = 'ATIVA' order by c.class_name limit 1;
  perform iara.session_create('PROFESSOR', v_unit, 's1-prof', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_unit, 's1-dir', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_outra, 's1-dir-outra', 'teste');
  perform iara.session_create('SECRETARIA_ESCOLAR', v_unit, 's1-sec', 'teste');
  perform iara.session_create('SECRETARIA_ESCOLAR', v_outra, 's1-sec-outra', 'teste');
  perform iara.session_create('SECRETARIO', null, 's1-secretario', 'teste');
  perform iara.session_create('NUTRICAO', null, 's1-nut', 'teste');
  perform iara.session_create('MANUTENCAO', null, 's1-man', 'teste');
  perform iara.session_create('CIDADAO', null, 's1-fam', 'teste');
  perform iara.session_create('PREFEITO', null, 's1-pref', 'teste');

  -- Pessoal ------------------------------------------------------------------------------------------------------------------------
  r := pg_temp.as_call('s1-prof', 'me', '{}');
  v_staff := (r -> 'staff' ->> 'id')::uuid;
  v_turma := (select (t ->> 'id')::uuid from jsonb_array_elements(r -> 'turmas') t limit 1);
  v_out := v_out || jsonb_build_object('passo', 'P1. Professor entra com o servidor e as turmas dele', 'ok', v_staff is not null and pg_temp.n(r -> 'turmas') > 0);
  r := pg_temp.as_call('s1-prof', 'pessoal_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P2. Professor não lista o pessoal (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s1-prof', 'pessoal_ficha', jsonb_build_object('id', v_staff));
  v_out := v_out || jsonb_build_object('passo', 'P3a. Professor vê a própria ficha', 'ok', r ->> 'erro' is null, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s1-prof', 'pessoal_ficha', jsonb_build_object('id', (select id from iara.staff where id <> v_staff and unit_id = v_outra limit 1)));
  v_out := v_out || jsonb_build_object('passo', 'P3b. Professor não vê a ficha de outro servidor (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s1-dir', 'pessoal_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P4. Direção lista o pessoal da unidade', 'ok', r ->> 'erro' is null, 'erro', r ->> 'erro',
    'amostra', left(r::text, 300));
  r := pg_temp.as_call('s1-dir', 'pessoal_lista', jsonb_build_object('unit_id', v_outra));
  v_out := v_out || jsonb_build_object('passo', 'P5. Direção pedindo outra unidade continua vendo só a sua', 'ok',
    r::text not like '%' || (select name from iara.education_units where id = v_outra) || '%', 'erro', r ->> 'erro');

  -- Frequência ---------------------------------------------------------------------------------------------------------------------
  r := pg_temp.as_call('s1-prof', 'frequencia_turma', jsonb_build_object('class_id', v_turma));
  v_out := v_out || jsonb_build_object('passo', 'F1a. Professor abre a chamada da própria turma', 'ok', coalesce((r ->> 'pode_lancar')::boolean, false), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s1-prof', 'frequencia_turma', jsonb_build_object('class_id', v_turma_outra));
  v_out := v_out || jsonb_build_object('passo', 'F1b. Professor não abre turma de outra unidade (deve negar)', 'ok', pg_temp.ok_erro(r, 'P0002'));
  v_aluno := (select e.student_id from iara.enrollments e where e.class_id = v_turma and e.status = 'ACTIVE' order by e.student_id limit 1);
  r := pg_temp.as_call('s1-prof', 'frequencia_lancar', jsonb_build_object('class_id', v_turma, 'data', current_date, 'faltas', jsonb_build_array(v_aluno)));
  v_out := v_out || jsonb_build_object('passo', 'F2. Professor lança a chamada de hoje', 'ok', coalesce((r ->> 'registrado')::boolean, false)
    and exists (select 1 from jsonb_array_elements(r -> 'alunos') a where (a ->> 'id')::uuid = v_aluno and a ->> 'falta' = 'FALTA'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s1-prof', 'frequencia_lancar', jsonb_build_object('class_id', v_turma, 'data', current_date + 1, 'faltas', '[]'::jsonb));
  v_out := v_out || jsonb_build_object('passo', 'F3a. Chamada de dia futuro (deve negar)', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s1-prof', 'frequencia_lancar', jsonb_build_object('class_id', v_turma, 'data', current_date,
         'faltas', jsonb_build_array((select student_id from iara.enrollments where class_id = v_turma_outra and status = 'ACTIVE' limit 1))));
  v_out := v_out || jsonb_build_object('passo', 'F3b. Aluno de outra turma na chamada (deve negar)', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s1-dir-outra', 'frequencia_lancar', jsonb_build_object('class_id', v_turma, 'faltas', '[]'::jsonb));
  v_out := v_out || jsonb_build_object('passo', 'F4. Direção de outra unidade não lança (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s1-fam', 'familia_frequencia', '{}');
  v_out := v_out || jsonb_build_object('passo', 'F5. Família vê a frequência dos filhos', 'ok', pg_temp.n(r) > 0
    and exists (select 1 from jsonb_array_elements(r) x where (x ->> 'student_id')::uuid = v_ana), 'erro', r ->> 'erro');
  select r2.data into v_dia from iara.frequencia_faltas f join iara.frequencia_registros r2 on r2.id = f.registro_id
  where f.student_id = v_ana and f.tipo = 'FALTA' order by r2.data desc limit 1;
  r := pg_temp.as_call('s1-fam', 'familia_justificar_falta', jsonb_build_object('student_id', v_ana, 'data', v_dia, 'motivo', 'Consulta no posto de saúde'));
  v_out := v_out || jsonb_build_object('passo', 'F6a. Família justifica a falta da filha', 'ok', r ->> 'erro' is null, 'erro', r ->> 'erro', 'dia', v_dia);
  r := pg_temp.as_call('s1-fam', 'familia_justificar_falta', jsonb_build_object('student_id', v_aluno, 'data', current_date, 'motivo', 'Tentativa indevida'));
  v_out := v_out || jsonb_build_object('passo', 'F6b. Família não justifica falta de outra criança (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  v_id := (select id from iara.frequencia_justificativas where student_id = v_ana order by created_at desc limit 1);
  r := pg_temp.as_call('s1-sec-outra', 'frequencia_justificativa_avaliar', jsonb_build_object('id', v_id, 'aceitar', true));
  v_out := v_out || jsonb_build_object('passo', 'F7a. Secretaria de outra unidade não avalia (deve negar)', 'ok', pg_temp.ok_erro(r, 'P0002'));
  r := pg_temp.as_call('s1-sec', 'frequencia_justificativa_avaliar', jsonb_build_object('id', v_id, 'aceitar', true));
  v_out := v_out || jsonb_build_object('passo', 'F7b. Secretaria da unidade aceita e a falta vira justificada', 'ok', r ->> 'erro' is null
    and exists (select 1 from iara.frequencia_faltas f join iara.frequencia_registros r2 on r2.id = f.registro_id
                where f.student_id = v_ana and r2.data = v_dia and f.tipo = 'FALTA_JUSTIFICADA'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s1-fam', 'frequencia_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', 'F8. Família não abre o painel da rede (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));

  -- Nutrição -----------------------------------------------------------------------------------------------------------------------
  r := pg_temp.as_call('s1-fam', 'familia_informar_restricao', jsonb_build_object('student_id', v_ana, 'codigo', 'LACTOSE'));
  v_out := v_out || jsonb_build_object('passo', 'N1a. Família informa restrição (aguarda a nutrição)', 'ok', coalesce((r ->> 'ok')::boolean, false), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s1-fam', 'familia_informar_restricao', jsonb_build_object('student_id', v_ana, 'codigo', 'LACTOSE'));
  v_out := v_out || jsonb_build_object('passo', 'N1b. Mesma restrição duas vezes (deve negar)', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s1-fam', 'familia_informar_restricao', jsonb_build_object('student_id', v_aluno, 'codigo', 'SOJA'));
  v_out := v_out || jsonb_build_object('passo', 'N1c. Restrição para criança de outra família (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  v_id := (select id from iara.aluno_restricoes where student_id = v_ana and restricao_codigo = 'LACTOSE');
  r := pg_temp.as_call('s1-dir', 'restricao_validar', jsonb_build_object('id', v_id, 'validar', true));
  v_out := v_out || jsonb_build_object('passo', 'N2a. Direção não valida restrição (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s1-nut', 'restricao_validar', jsonb_build_object('id', v_id, 'validar', true));
  v_out := v_out || jsonb_build_object('passo', 'N2b. Nutrição valida', 'ok', coalesce((r ->> 'ok')::boolean, false), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s1-fam', 'familia_cardapio', '{}');
  v_out := v_out || jsonb_build_object('passo', 'N3. Cardápio da família já traz a troca da restrição validada', 'ok',
    exists (select 1 from jsonb_array_elements(r) x, jsonb_array_elements(x -> 'cardapio' -> 'dias') d, jsonb_array_elements(d -> 'refeicoes') rf,
                   jsonb_array_elements(rf -> 'itens') it where (x ->> 'student_id')::uuid = v_ana and it ->> 'troca' is not null), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s1-dir', 'cozinha_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', 'N4. Lista da cozinha com a Ana e sem laudo nem observação clínica', 'ok', pg_temp.n(r -> 'criancas') > 0
    and r::text not like '%observacao%' and r::text not like '%laudo%'
    and exists (select 1 from jsonb_array_elements(r -> 'criancas') c where c ->> 'aluno' like 'Ana L.%'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s1-pref', 'cozinha_lista', jsonb_build_object('unit_id', v_unit));
  v_out := v_out || jsonb_build_object('passo', 'N5. Prefeito não abre a lista da cozinha (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s1-pref', 'nutricao_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', 'N6. Prefeito vê o painel só com contagens (sem fila nominal)', 'ok', r ->> 'erro' is null and pg_temp.n(r -> 'aguardando_validacao') = 0);

  -- Manutenção ---------------------------------------------------------------------------------------------------------------------
  r := pg_temp.as_call('s1-dir', 'manutencao_abrir', jsonb_build_object('categoria', 'PLAYGROUND', 'local', 'Parque', 'descricao', 'Balanço com corrente solta', 'afeta_seguranca', true));
  v_id := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'M1. Direção abre chamado; risco à segurança vira urgente (24 h)', 'ok', r ->> 'prioridade' = 'URGENTE'
    and (r ->> 'unit_id')::int = v_unit and (r ->> 'prazo')::timestamptz <= now() + interval '24 hours', 'erro', r ->> 'erro');
  r := pg_temp.as_call('s1-fam', 'manutencao_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', 'M2. Família não vê chamados (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s1-dir', 'manutencao_avancar', jsonb_build_object('id', v_id, 'situacao', 'TRIAGEM'));
  v_out := v_out || jsonb_build_object('passo', 'M3. Direção não tria (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s1-man', 'manutencao_avancar', jsonb_build_object('id', v_id, 'situacao', 'CONCLUIDO'));
  v_out := v_out || jsonb_build_object('passo', 'M4. Pular do aberto para concluído (deve negar)', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s1-man', 'manutencao_avancar', jsonb_build_object('id', v_id, 'situacao', 'TRIAGEM'));
  r := pg_temp.as_call('s1-man', 'manutencao_avancar', jsonb_build_object('id', v_id, 'situacao', 'EM_EXECUCAO', 'equipe', 'EQUIPE_PROPRIA'));
  r := pg_temp.as_call('s1-man', 'manutencao_avancar', jsonb_build_object('id', v_id, 'situacao', 'CONCLUIDO', 'custo_final', 180, 'texto', 'Corrente trocada.'));
  v_out := v_out || jsonb_build_object('passo', 'M5. Infraestrutura tria, executa e conclui', 'ok', r ->> 'situacao' = 'CONCLUIDO' and pg_temp.n(r -> 'eventos') = 4, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s1-dir-outra', 'manutencao_validar', jsonb_build_object('id', v_id, 'aprovado', true));
  v_out := v_out || jsonb_build_object('passo', 'M6a. Outra unidade não valida (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s1-dir', 'manutencao_validar', jsonb_build_object('id', v_id, 'aprovado', false));
  v_out := v_out || jsonb_build_object('passo', 'M6b. Reabrir sem dizer o que falta (deve negar)', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s1-dir', 'manutencao_validar', jsonb_build_object('id', v_id, 'aprovado', true, 'nota', 5));
  v_out := v_out || jsonb_build_object('passo', 'M6c. Direção valida com nota', 'ok', r ->> 'situacao' = 'VALIDADO' and (r ->> 'nota_escola')::int = 5, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s1-dir-outra', 'manutencao_detalhe', jsonb_build_object('id', v_id));
  v_out := v_out || jsonb_build_object('passo', 'M7. Outra unidade não abre o chamado (deve negar)', 'ok', pg_temp.ok_erro(r, 'P0002'));
  r := pg_temp.as_call('s1-dir', 'manutencao_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', 'M8. Direção lista só a própria unidade', 'ok', pg_temp.n(r) > 0
    and not exists (select 1 from jsonb_array_elements(r) x where (x ->> 'unit_id')::int <> v_unit));

  -- Mural --------------------------------------------------------------------------------------------------------------------------
  r := pg_temp.as_call('s1-dir', 'mural_publicar', jsonb_build_object('tipo', 'AVISO', 'titulo', 'Teste de aviso da unidade',
         'texto', 'Aviso de teste com confirmação de leitura.', 'unit_id', v_outra, 'exige_confirmacao', true));
  v_pub := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'MU1. Direção publica sempre na própria unidade', 'ok', (r ->> 'unit_id')::int = v_unit and (r ->> 'destinatarios')::int > 0, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s1-prof', 'mural_publicar', jsonb_build_object('titulo', 'Professor publicando', 'texto', 'Não deveria publicar.'));
  v_out := v_out || jsonb_build_object('passo', 'MU2. Professor não publica (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s1-secretario', 'mural_publicar', jsonb_build_object('tipo', 'ENQUETE', 'titulo', 'Enquete de teste da rede',
         'texto', 'Qual dia da semana é melhor?', 'opcoes', jsonb_build_array('Segunda', 'Quarta', 'Sexta')));
  v_enq := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'MU3. Secretário publica enquete para a rede', 'ok', r ->> 'unit_id' is null and pg_temp.n(r -> 'opcoes') = 3, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s1-dir-outra', 'mural_publicar', jsonb_build_object('titulo', 'Aviso só da outra unidade', 'texto', 'Família da Ana não deve ver.'));
  v_pub_outra := (r ->> 'id')::uuid;
  r := pg_temp.as_call('s1-fam', 'familia_avisos', '{}');
  v_out := v_out || jsonb_build_object('passo', 'MU4. Família vê o aviso da unidade da filha e a enquete; não vê o da outra unidade', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'avisos') a where (a ->> 'id')::uuid = v_pub)
    and exists (select 1 from jsonb_array_elements(r -> 'avisos') a where (a ->> 'id')::uuid = v_enq)
    and not exists (select 1 from jsonb_array_elements(r -> 'avisos') a where (a ->> 'id')::uuid = v_pub_outra), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s1-fam', 'familia_aviso_ler', jsonb_build_object('id', v_pub, 'confirmar', true));
  r := pg_temp.as_call('s1-dir', 'mural_feed', '{}');
  v_out := v_out || jsonb_build_object('passo', 'MU5. Ciência da família aparece na contagem da escola', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'publicacoes') a where (a ->> 'id')::uuid = v_pub and (a ->> 'confirmacoes')::int = 1), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s1-fam', 'familia_aviso_ler', jsonb_build_object('id', v_pub_outra));
  v_out := v_out || jsonb_build_object('passo', 'MU6. Família não marca aviso de outra unidade (deve negar)', 'ok', pg_temp.ok_erro(r, 'P0002'));
  r := pg_temp.as_call('s1-fam', 'familia_enquete_responder', jsonb_build_object('id', v_enq, 'opcao', 9));
  v_out := v_out || jsonb_build_object('passo', 'MU7a. Opção inexistente (deve negar)', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s1-fam', 'familia_enquete_responder', jsonb_build_object('id', v_enq, 'opcao', 2));
  v_out := v_out || jsonb_build_object('passo', 'MU7b. Família responde a enquete e vê o resultado', 'ok', r ->> 'opcao' = 'Quarta' and (r -> 'votos' -> 1 ->> 'votos')::int = 1, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s1-fam', 'mural_feed', '{}');
  v_out := v_out || jsonb_build_object('passo', 'MU8. Família não abre o mural dos servidores (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s1-fam', 'calendario', '{}');
  v_out := v_out || jsonb_build_object('passo', 'C1. Calendário da família traz a reunião da unidade e não os eventos internos', 'ok',
    exists (select 1 from jsonb_array_elements(r) e where e ->> 'tipo' = 'REUNIAO_PAIS')
    and not exists (select 1 from jsonb_array_elements(r) e where e ->> 'publico' = 'PROFISSIONAIS'), 'erro', r ->> 'erro');

  raise exception 'RESULTADO: %', v_out;
end $$;
