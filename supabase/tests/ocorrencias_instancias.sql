-- Ocorrências em 1ª e 2ª instância (pedido de Rob, 07/10/2026): quem trata, o que a família vê, modelos de resposta,
-- comunicação obrigatória ao Conselho Tutelar e indicadores. Roda numa transação revertida (não deixa resíduo).
-- Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/ocorrencias_instancias.sql
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
  v_ana uuid := (iara.setting('demo_student_ana'))::uuid;
  v_unit integer;
  v_turma uuid;
  v_aluno uuid;
  v_g uuid;
  v_id uuid;
  v_id2 uuid;
  v_id3 uuid;
  v_notif integer;
  v_cod text;
begin
  select e.unit_id into v_unit from iara.enrollments e where e.student_id = v_ana and e.status = 'ACTIVE';
  perform iara.session_create('PROFESSOR', v_unit, 'oi-prof', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_unit, 'oi-dir', 'teste');
  perform iara.session_create('SECRETARIO', null, 'oi-seduc', 'teste');
  v_turma := (select (t ->> 'id')::uuid from jsonb_array_elements(pg_temp.as_call('oi-prof', 'me', '{}') -> 'turmas') t limit 1);
  select e.student_id, sg.guardian_id into v_aluno, v_g from iara.enrollments e join iara.student_guardians sg on sg.student_id = e.student_id and sg.end_date is null and sg.is_primary
  where e.class_id = v_turma and e.status = 'ACTIVE' and e.student_id <> v_ana order by e.student_id limit 1;
  perform pg_temp.sessao_familia('oi-fam', v_g);

  -- 1ª instância: a família relata, recebe a confirmação automática e não vê a tratativa interna
  r := pg_temp.as_call('oi-fam', 'ocorrencia_registrar', jsonb_build_object('student_id', v_aluno, 'tipo', 'BULLYING', 'descricao', 'Colegas colocam apelidos e excluem meu filho no recreio.'));
  v_id := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'I1. Família relata: prazo definido e confirmação automática visível, sem campo do modelo por preencher', 'ok',
    r ->> 'origem' = 'FAMILIA' and r ->> 'prazo' is not null and r -> 'eventos' -> 0 ->> 'tipo' = 'COMUNICACAO' and (r -> 'eventos' -> 0 ->> 'texto') not like '%{%', 'erro', r ->> 'erro');
  r := pg_temp.as_call('oi-dir', 'ocorrencia_atualizar', jsonb_build_object('id', v_id, 'acao', 'NOTA_INTERNA', 'texto', 'Conversar com a professora antes de chamar a família.'));
  v_out := v_out || jsonb_build_object('passo', 'I2. Direção registra nota interna (aparece para a equipe)', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'eventos') e where (e ->> 'interno')::boolean and e ->> 'texto' like 'Conversar com a professora%'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('oi-fam', 'ocorrencia_detalhe', jsonb_build_object('id', v_id));
  v_out := v_out || jsonb_build_object('passo', 'I3. Família não vê a nota interna nem a classificação interna', 'ok', r ->> 'erro' is null
    and not exists (select 1 from jsonb_array_elements(r -> 'eventos') e where e ->> 'texto' like 'Conversar com a professora%')
    and not (r ? 'violencia') and not (r ? 'sigilosa') and not (r ? 'motivo_seduc'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('oi-prof', 'ocorrencia_atualizar', jsonb_build_object('id', v_id, 'acao', 'ENCAMINHAR_SEDUC', 'texto', 'Pedido de apoio da Secretaria.'));
  v_out := v_out || jsonb_build_object('passo', 'I4. Professor não encaminha à Secretaria (equipe gestora encaminha)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('oi-dir', 'ocorrencia_atualizar', jsonb_build_object('id', v_id, 'acao', 'ENCAMINHAR_SEDUC', 'texto', 'curto'));
  v_out := v_out || jsonb_build_object('passo', 'I5. Encaminhamento à Secretaria exige motivo', 'ok', pg_temp.ok_erro(r, '22023'));
  v_notif := (select count(*) from iara.notifications where guardian_id = v_g and event_type = 'OCORRENCIA');
  r := pg_temp.as_call('oi-dir', 'ocorrencia_atualizar', jsonb_build_object('id', v_id, 'acao', 'ENCAMINHAR_SEDUC', 'texto', 'Situação recorrente; pedimos apoio da equipe multiprofissional.'));
  v_out := v_out || jsonb_build_object('passo', 'I6. Direção encaminha: 2ª instância, prazo da Secretaria e família avisada', 'ok', r ->> 'instancia' = 'SECRETARIA'
    and (select count(*) from iara.notifications where guardian_id = v_g and event_type = 'OCORRENCIA') = v_notif + 1, 'erro', r ->> 'erro');
  r := pg_temp.as_call('oi-dir', 'ocorrencia_atualizar', jsonb_build_object('id', v_id, 'acao', 'SOLUCIONAR', 'solucao', 'Conversa com a turma realizada.'));
  v_out := v_out || jsonb_build_object('passo', 'I7. Em 2ª instância a unidade não responde no lugar da Secretaria', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('oi-seduc', 'ocorrencia_atualizar', jsonb_build_object('id', v_id, 'acao', 'SOLUCIONAR', 'solucao', 'curta'));
  v_out := v_out || jsonb_build_object('passo', 'I8. Solução exige descrição', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('oi-seduc', 'ocorrencia_atualizar', jsonb_build_object('id', v_id, 'acao', 'SOLUCIONAR',
    'solucao', 'A equipe multiprofissional fez rodas de conversa com a turma e combinou acompanhamento do recreio por 30 dias.'));
  v_out := v_out || jsonb_build_object('passo', 'I9. Secretaria responde (modelo da devolutiva) e encerra', 'ok', r ->> 'situacao' = 'ENCERRADA' and r ->> 'comunicada_em' is not null, 'erro', r ->> 'erro');
  r := pg_temp.as_call('oi-fam', 'ocorrencia_detalhe', jsonb_build_object('id', v_id));
  v_out := v_out || jsonb_build_object('passo', 'I10. Família vê a solução e a resposta da Secretaria, sem a tratativa interna', 'ok',
    r ->> 'solucao' like 'A equipe multiprofissional%' and exists (select 1 from jsonb_array_elements(r -> 'eventos') e where e ->> 'tipo' = 'SOLUCAO' and e ->> 'texto' like '%Secretaria Municipal%')
    and not exists (select 1 from jsonb_array_elements(r -> 'eventos') e where e ->> 'tipo' in ('ENCAMINHADA_SEDUC', 'NOTA_INTERNA')), 'erro', r ->> 'erro');
  r := pg_temp.as_call('oi-fam', 'ocorrencia_atualizar', jsonb_build_object('id', v_id, 'acao', 'PEDIR_REVISAO', 'texto', 'Quero que a Secretaria analise de novo.'));
  v_out := v_out || jsonb_build_object('passo', 'I11. Depois da resposta da Secretaria não há nova 2ª instância', 'ok', pg_temp.ok_erro(r, '22023'));

  -- solução pela unidade com o modelo e pedido de análise pela família
  r := pg_temp.as_call('oi-dir', 'ocorrencia_registrar', jsonb_build_object('student_id', v_aluno, 'tipo', 'CONFLITO', 'descricao', 'Discussão com um colega na fila do lanche.'));
  v_id2 := (r ->> 'id')::uuid;
  r := pg_temp.as_call('oi-dir', 'ocorrencia_atualizar', jsonb_build_object('id', v_id2, 'acao', 'SOLUCIONAR', 'solucao', 'Mediação entre as crianças e combinado de convivência na turma.'));
  v_out := v_out || jsonb_build_object('passo', 'I12. Unidade soluciona; a mensagem sai do modelo de convivência', 'ok', r ->> 'situacao' = 'ENCERRADA'
    and exists (select 1 from jsonb_array_elements(r -> 'eventos') e where e ->> 'tipo' = 'SOLUCAO' and e ->> 'texto' like '%privacidade%' and e ->> 'texto' like '%Mediação entre as crianças%'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('oi-fam', 'ocorrencia_atualizar', jsonb_build_object('id', v_id2, 'acao', 'PEDIR_REVISAO', 'texto', 'curto'));
  v_out := v_out || jsonb_build_object('passo', 'I13. Pedido de análise exige o motivo', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('oi-fam', 'ocorrencia_atualizar', jsonb_build_object('id', v_id2, 'acao', 'PEDIR_REVISAO', 'texto', 'A situação continua e ninguém nos chamou para conversar.'));
  v_out := v_out || jsonb_build_object('passo', 'I14. Família pede a análise da Secretaria: volta a andar em 2ª instância', 'ok', r ->> 'instancia' = 'SECRETARIA'
    and (r ->> 'pedido_familia')::boolean and r ->> 'situacao' = 'EM_ACOMPANHAMENTO', 'erro', r ->> 'erro');
  r := pg_temp.as_call('oi-seduc', 'ocorrencia_atualizar', jsonb_build_object('id', v_id2, 'acao', 'DEVOLVER_UNIDADE', 'texto', 'Orientamos nova mediação pela unidade.'));
  v_out := v_out || jsonb_build_object('passo', 'I15. Pedido da família não volta à unidade sem resposta da Secretaria', 'ok', pg_temp.ok_erro(r, '22023'));

  -- violência: comunicação obrigatória ao Conselho Tutelar, sigilo para a família e bloqueio do encerramento
  r := pg_temp.as_call('oi-dir', 'ocorrencia_registrar', jsonb_build_object('student_id', v_aluno, 'tipo', 'OUTRO', 'gravidade', 'GRAVE', 'violencia', jsonb_build_array('SEXUAL'),
    'descricao', 'Relato da criança à professora que exige comunicação aos órgãos de proteção.', 'encerrar', true));
  v_out := v_out || jsonb_build_object('passo', 'I16. Ocorrência com violência não é registrada já encerrada', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('oi-dir', 'ocorrencia_registrar', jsonb_build_object('student_id', v_aluno, 'tipo', 'OUTRO', 'gravidade', 'GRAVE', 'violencia', jsonb_build_array('SEXUAL'),
    'descricao', 'Relato da criança à professora que exige comunicação aos órgãos de proteção.'));
  v_id3 := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'I17. Violência sexual: registro sigiloso e comunicação ao Conselho Tutelar preparada (expediente + tarefa urgente)', 'ok',
    (r ->> 'sigilosa')::boolean and (r ->> 'comunicacao_ct')::boolean
    and exists (select 1 from iara.encaminhamentos e where e.ocorrencia_id = v_id3 and e.tipo = 'CONSELHO_TUTELAR' and e.obrigatorio and e.situacao = 'AGUARDANDO_APROVACAO' and not e.comunicar_familia)
    and exists (select 1 from iara.frequencia_tarefas t join iara.encaminhamentos e on t.chave = 'ct:' || e.id where e.ocorrencia_id = v_id3 and t.prioridade = 'URGENTE' and t.obrigatoria), 'erro', r ->> 'erro');
  r := pg_temp.as_call('oi-fam', 'familia_ocorrencias', '{}');
  v_out := v_out || jsonb_build_object('passo', 'I18. Registro sigiloso não aparece para a família', 'ok', r ->> 'erro' is null
    and not exists (select 1 from jsonb_array_elements(r -> 'ocorrencias') x where (x ->> 'id')::uuid = v_id3)
    and pg_temp.ok_erro(pg_temp.as_call('oi-fam', 'ocorrencia_detalhe', jsonb_build_object('id', v_id3)), 'P0002'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('oi-dir', 'ocorrencia_atualizar', jsonb_build_object('id', v_id3, 'acao', 'SOLUCIONAR', 'solucao', 'Atendimento feito pela equipe da escola.'));
  v_out := v_out || jsonb_build_object('passo', 'I19. Não encerra com a comunicação obrigatória pendente', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('oi-dir', 'ocorrencia_atualizar', jsonb_build_object('id', v_id2, 'acao', 'CLASSIFICAR', 'violencia', jsonb_build_array('FISICA'), 'gravidade', 'GRAVE'));
  v_out := v_out || jsonb_build_object('passo', 'I20. Reclassificar para violência física grave prepara a comunicação ao Conselho Tutelar', 'ok', r ->> 'erro' is null and (r ->> 'exige_ct')::boolean
    and exists (select 1 from iara.encaminhamentos e where e.ocorrencia_id = v_id2 and e.tipo = 'CONSELHO_TUTELAR'), 'erro', r ->> 'erro');

  -- indicadores e modelos
  r := pg_temp.as_call('oi-dir', 'ocorrencias_indicadores', '{}');
  v_out := v_out || jsonb_build_object('passo', 'I21. Indicadores da unidade: resumo, idade, série, turmas e leitura (sem ranking de unidades)', 'ok', r ->> 'erro' is null
    and (r -> 'resumo' ->> 'total')::int > 0 and jsonb_array_length(r -> 'por_idade') > 0 and jsonb_array_length(r -> 'leitura') > 0
    and jsonb_typeof(r -> 'unidades') = 'null' and not (r ->> 'rede')::boolean, 'erro', r ->> 'erro');
  r := pg_temp.as_call('oi-seduc', 'ocorrencias_indicadores', '{}');
  v_out := v_out || jsonb_build_object('passo', 'I22. Indicadores da rede: intimidação como padrão amplo; turma com brigas (foco localizado) e aluno reincidente', 'ok', r ->> 'erro' is null
    and (r ->> 'rede')::boolean and jsonb_array_length(r -> 'unidades') > 0
    and exists (select 1 from jsonb_array_elements(r -> 'leitura') x where x ->> 'chave' = 'BULLYING' and x ->> 'padrao' = 'AMPLO')
    and exists (select 1 from jsonb_array_elements(r -> 'focos') x where x ->> 'padrao' = 'LOCALIZADO' and (x ->> 'violencia')::int >= 4)
    and exists (select 1 from jsonb_array_elements(r -> 'focos') x where x ->> 'padrao' = 'REINCIDENTE'), 'erro', coalesce(r ->> 'erro', r ->> 'focos'));
  r := pg_temp.as_call('oi-fam', 'ocorrencias_indicadores', '{}');
  v_out := v_out || jsonb_build_object('passo', 'I23. Família não acessa indicadores', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('oi-dir', 'ocorrencia_modelo_salvar', jsonb_build_object('titulo', 'Teste', 'momento', 'SOLUCAO', 'texto', 'Olá! Sobre {aluno}: {solucao} Abraços da escola.'));
  v_out := v_out || jsonb_build_object('passo', 'I24. Direção não edita modelos (Secretaria edita)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('oi-seduc', 'ocorrencia_modelo_salvar', jsonb_build_object('titulo', 'Solução — pertences', 'momento', 'SOLUCAO', 'tipos', jsonb_build_array('PERTENCES'),
    'texto', 'Olá! Sobre o que {aluno} perdeu em {data}: {solucao} A {unidade} agradece o aviso.'));
  v_cod := r ->> 'codigo';
  r := pg_temp.as_call('oi-seduc', 'ocorrencia_modelo_salvar', jsonb_build_object('codigo', v_cod, 'titulo', 'Solução — pertences', 'momento', 'SOLUCAO', 'tipos', jsonb_build_array('PERTENCES'),
    'texto', 'Olá! Sobre o objeto de {aluno} (registro de {data}): {solucao} A {unidade} agradece o aviso.'));
  v_out := v_out || jsonb_build_object('passo', 'I25. Inclusão e alteração de modelo geram versões', 'ok', (r ->> 'versao')::int = 2 and (r ->> 'ativo')::boolean, 'erro', r ->> 'erro');
  r := pg_temp.as_call('oi-seduc', 'ocorrencia_modelo_salvar', jsonb_build_object('codigo', v_cod, 'titulo', 'X', 'momento', 'SOLUCAO', 'texto', 'Se repetir, a família será punida e processada. {solucao}'));
  v_out := v_out || jsonb_build_object('passo', 'I26. Modelo com linguagem de ameaça é recusado', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('oi-seduc', 'ocorrencia_modelo_salvar', jsonb_build_object('codigo', v_cod, 'titulo', 'Solução — pertences', 'momento', 'SOLUCAO', 'texto', 'Olá, {responsavel}! Sobre {aluno}: {solucao}'));
  v_out := v_out || jsonb_build_object('passo', 'I27. Campo desconhecido no modelo é recusado', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('oi-seduc', 'ocorrencia_modelo_salvar', jsonb_build_object('codigo', 'RECEBIMENTO', 'excluir', true));
  v_out := v_out || jsonb_build_object('passo', 'I28. Modelo das respostas automáticas não pode ser excluído', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('oi-seduc', 'ocorrencia_modelo_salvar', jsonb_build_object('codigo', v_cod, 'excluir', true));
  v_out := v_out || jsonb_build_object('passo', 'I29. Exclusão vira nova versão inativa (histórico preservado)', 'ok', not (r ->> 'ativo')::boolean and (r ->> 'versao')::int = 3
    and (select count(*) from iara.ocorrencia_modelos where codigo = v_cod) = 3, 'erro', r ->> 'erro');

  raise exception 'RESULTADO: %', v_out;
end $$;
