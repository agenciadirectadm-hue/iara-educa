-- Perfil "Controle externo" (Ministério Público e Defensoria): somente leitura, sem dados pessoais; caso só por protocolo.
-- Roda numa transação revertida (não deixa resíduo).
-- Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/controle_externo.sql
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
  r jsonb;
  v_prot text;
  v_nome text;
  v_aud integer;
begin
  perform iara.session_create('CONTROLE_EXTERNO', null, 'test-controle', 'teste');

  -- 1. painel: conformidade sem dados pessoais
  r := pg_temp.as_call('test-controle', 'controle_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', '1. Painel do controle externo', 'erro', r ->> 'erro',
    'aguardando', r #> '{fila,aguardando}', 'espera_media', r #> '{fila,espera_media_dias}', 'mais_90', r #> '{fila,mais_90}',
    'ordem', jsonb_build_object('filas', r #> '{ordem,filas}', 'conferidas', r #> '{ordem,conferidas}'),
    'vagas_com_fila', jsonb_build_object('filas', r #> '{vagas_com_fila,filas}', 'vagas', r #> '{vagas_com_fila,vagas}'),
    'ofertas', r -> 'ofertas', 'excecoes', jsonb_array_length(r -> 'excecoes'), 'regioes', jsonb_array_length(r -> 'regioes'),
    'governanca', jsonb_array_length(r -> 'governanca'), 'distancias', r #> '{distancias,atendem}',
    'exemplo_excecao', r #> '{excecoes,0}',
    -- nenhum nome de criança da fila aparece no painel (nomes de escolas homenageiam pessoas e podem aparecer)
    'sem_nomes', not exists (select 1 from iara.waiting_list_entries w join iara.students s on s.id = w.student_id
                             where w.status = 'WAITING' and position(s.full_name in r::text) > 0));

  -- 2. fila pública: código público, sem nome, com conferência da ordem
  r := pg_temp.as_call('test-controle', 'controle_fila', '{"page_size": 3}');
  v_out := v_out || jsonb_build_object('passo', '2. Fila pública anonimizada', 'total', r -> 'total', 'filas', r -> 'filas',
    'conferidas', r -> 'filas_conferidas', 'exemplo', r #> '{itens,0}',
    'sem_nome', not (r #> '{itens,0}' ? 'student') and not (r #> '{itens,0}' ? 'nome'));

  -- 3. perfil não lê fichas nem a fila nominal
  r := pg_temp.as_call('test-controle', 'student_detail', jsonb_build_object('student_id', (select id from iara.students limit 1)));
  v_out := v_out || jsonb_build_object('passo', '3. Ficha de aluno (deve negar)', 'r', coalesce(r ->> 'erro', left(r::text, 120)));
  r := pg_temp.as_call('test-controle', 'queue_list', '{}');
  v_out := v_out || jsonb_build_object('passo', '4. Fila nominal (deve vir vazia ou negar)', 'erro', r ->> 'erro', 'itens', jsonb_array_length(coalesce(r -> 'items', '[]')));

  -- 5. consulta de caso exige motivo
  select c.protocol_number, s.full_name into v_prot, v_nome from iara.service_cases c join iara.students s on s.id = c.student_id
  join iara.waiting_list_entries w on w.student_id = s.id and w.status = 'WAITING' and w.position > 3
  where c.case_type = 'SOLICITACAO_VAGA' order by c.opened_at desc limit 1;
  r := pg_temp.as_call('test-controle', 'controle_caso', jsonb_build_object('protocolo', v_prot, 'motivo', 'curto'));
  v_out := v_out || jsonb_build_object('passo', '5. Consulta sem motivo (deve recusar)', 'r', r ->> 'erro');

  -- 6. consulta com protocolo e motivo: caso completo + quem está à frente sem identificação + registro na auditoria
  select count(*) into v_aud from iara.audit_log where action = 'CONTROLE_CONSULTA';
  r := pg_temp.as_call('test-controle', 'controle_caso', jsonb_build_object('protocolo', lower(v_prot), 'motivo', 'Atendimento da Defensoria Pública nº 123/2026'));
  v_out := v_out || jsonb_build_object('passo', '6. Consulta pelo protocolo', 'erro', r ->> 'erro', 'encontrado', r -> 'encontrado',
    'crianca_ok', r #>> '{crianca,nome}' = v_nome, 'posicao', r #> '{fila,posicao}', 'codigo', r #> '{fila,codigo}',
    'ordem_conferida', r #> '{fila,ordem_conferida}', 'a_frente', jsonb_array_length(r #> '{fila,a_frente}'),
    'a_frente_sem_nome', position(v_nome in (r #> '{fila,a_frente}')::text) = 0,
    'telefone', r #> '{responsavel,telefone}', 'eventos', jsonb_array_length(r -> 'eventos'),
    'auditado', (select count(*) from iara.audit_log where action = 'CONTROLE_CONSULTA') = v_aud + 1,
    'na_trilha', (select a.summary from iara.audit_log a where a.action = 'CONTROLE_CONSULTA' order by a.id desc limit 1));

  r := pg_temp.as_call('test-controle', 'controle_caso', '{"protocolo": "NAO-EXISTE-1", "motivo": "Procedimento do MP nº 45/2026"}');
  v_out := v_out || jsonb_build_object('passo', '7. Protocolo inexistente (registrado)', 'r', r,
    'auditado', (select count(*) from iara.audit_log where action = 'CONTROLE_CONSULTA') = v_aud + 2);

  -- 8. simulação da medida também para o controle externo, sem nomes
  r := pg_temp.as_call('test-controle', 'fila_simular_medida', '{"medida": "A_PE"}');
  v_out := v_out || jsonb_build_object('passo', '8. Simulação a pé (controle externo)', 'erro', r ->> 'erro', 'perdem', r -> 'perdem',
    'exemplo', r #> '{exemplos,0,crianca}', 'sem_id', r #> '{exemplos,0,entry_id}' = 'null'::jsonb);

  -- 9. nenhuma escrita: não troca a medida nem oferta vaga
  r := pg_temp.as_call('test-controle', 'fila_medida_definir', '{"medida": "A_PE", "justificativa": "Tentativa do controle externo"}');
  v_out := v_out || jsonb_build_object('passo', '9. Troca da medida (deve negar)', 'r', r ->> 'erro');

  -- 10. as outras visões não veem o painel
  r := pg_temp.as_call('test-diretor', 'controle_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', '10. Direção não vê o painel (deve negar)', 'r', r ->> 'erro');
  r := pg_temp.as_call('test-cidadao', 'controle_fila', '{}');
  v_out := v_out || jsonb_build_object('passo', '11. Família não vê a fila da rede (deve negar)', 'r', r ->> 'erro');

  raise exception 'RESULTADO: %', v_out;  -- reverte tudo
end $$;
