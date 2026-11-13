-- IARAFLIX (migrações 099.14 e 099.15): quem vê cada trilha, progresso, perguntas, certificado, verificação pública, gestão e painel.
-- Roda numa transação revertida (não deixa resíduo).
-- Executar: node scripts/aplicar.mjs supabase/tests/iaraflix.sql
create or replace function pg_temp.como(p_uid uuid, p_fn text, p_args jsonb) returns jsonb language plpgsql as $f$
declare
  v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute format('select api.%I($1)', p_fn) into v using p_args;
  execute 'reset role';
  return v;
exception when others then
  execute 'reset role';
  return jsonb_build_object('erro', sqlerrm, 'codigo', sqlstate);
end $f$;

create or replace function pg_temp.sessao(p_persona text, p_hash text) returns uuid language plpgsql as $f$
begin
  perform iara.session_create(p_persona, case when p_persona in ('DIRETOR_UNIDADE', 'SECRETARIA_ESCOLAR')
                                              then (select unit_id from iara.staff where role = 'PROFESSOR' and unit_id is not null order by id limit 1) end,
                              p_hash, 'teste');
  return (select user_id from iara.app_sessions where token_hash = p_hash);
end $f$;

do $$
declare
  v_out jsonb := '[]';
  r jsonb;
  v_prof uuid := pg_temp.sessao('PROFESSOR', 'test-ifx-prof');
  v_nutri uuid := pg_temp.sessao('NUTRICAO', 'test-ifx-nutri');
  v_inov uuid := pg_temp.sessao('INOVACAO', 'test-ifx-inov');
  v_dir uuid := pg_temp.sessao('DIRETOR_UNIDADE', 'test-ifx-dir');
  v_cid uuid := pg_temp.sessao('CIDADAO', 'test-ifx-cid');
  v_aula uuid;
  v_aula_nutri uuid;
  a record;
  v_cert text;
  v_n integer;
begin
  -- 1. Quem vê o quê
  r := pg_temp.como(v_prof, 'iaraflix_inicio', '{}');
  v_out := v_out || jsonb_build_object('passo', '1a. Professor: "Primeiros passos" e "Professores" como obrigatórias, Multiplicadores opcional; nada de Nutrição',
    'ok', (select bool_and(t ->> 'id' <> 'nutricao') from jsonb_array_elements(r -> 'trilhas') t)
          and exists (select 1 from jsonb_array_elements(r -> 'trilhas') t where t ->> 'id' = 'professores' and (t ->> 'obrigatoria')::boolean)
          and exists (select 1 from jsonb_array_elements(r -> 'trilhas') t where t ->> 'id' = 'primeiros-passos' and (t ->> 'obrigatoria')::boolean)
          and exists (select 1 from jsonb_array_elements(r -> 'trilhas') t where t ->> 'id' = 'multiplicadores' and not (t ->> 'obrigatoria')::boolean)
          and not (r ->> 'gestao')::boolean,
    'trilhas', (select jsonb_agg(t ->> 'id') from jsonb_array_elements(r -> 'trilhas') t));
  r := pg_temp.como(v_prof, 'iaraflix_trilha', '{"id": "nutricao"}');
  v_out := v_out || jsonb_build_object('passo', '1b. Professor abrindo a trilha da Nutrição: recusado', 'ok', r ->> 'codigo' = 'P0002');
  v_aula_nutri := (select id from iara.iaraflix_aulas where trilha_id = 'nutricao' order by ordem limit 1);
  r := pg_temp.como(v_prof, 'iaraflix_aula', jsonb_build_object('id', v_aula_nutri));
  v_out := v_out || jsonb_build_object('passo', '1c. Professor abrindo uma aula da Nutrição pelo id: recusado', 'ok', r ->> 'codigo' = 'P0002');
  r := pg_temp.como(v_cid, 'iaraflix_inicio', '{}');
  v_out := v_out || jsonb_build_object('passo', '1d. Família: sem acesso ao IARAFLIX', 'ok', r ->> 'codigo' = '42501', 'r', r);
  r := pg_temp.como(v_inov, 'iaraflix_inicio', '{}');
  v_out := v_out || jsonb_build_object('passo', '1e. Gestão (Inovação) vê as 16 trilhas', 'ok', jsonb_array_length(r -> 'trilhas') = 16 and (r ->> 'gestao')::boolean);

  -- 2. Progresso: aula sem vídeo conclui quando marcada como estudada; com vídeo, só com 90% assistido
  v_aula := (select id from iara.iaraflix_aulas where trilha_id = 'primeiros-passos' order by ordem limit 1);
  r := pg_temp.como(v_prof, 'iaraflix_avaliar', '{"trilha_id": "primeiros-passos", "respostas": [1, 1, 1, 0, 1]}');
  v_out := v_out || jsonb_build_object('passo', '2a. Perguntas antes de concluir as aulas: recusado', 'ok', r ->> 'codigo' = 'P0001');
  update iara.iaraflix_aulas set video_caminho = 'aulas/' || v_aula || '/00000000-0000-0000-0000-000000000000.mp4', video_mime = 'video/mp4', duracao_s = 200
  where id = v_aula;
  r := pg_temp.como(v_prof, 'iaraflix_progresso', jsonb_build_object('aula_id', v_aula, 'posicao_s', 150, 'assistido_s', 150, 'estudada', true));
  v_out := v_out || jsonb_build_object('passo', '2b. Vídeo com 75% assistido: não conclui (nem marcando estudada)', 'ok', not (r ->> 'concluida')::boolean);
  r := pg_temp.como(v_prof, 'iaraflix_progresso', jsonb_build_object('aula_id', v_aula, 'posicao_s', 60, 'assistido_s', 185));
  v_out := v_out || jsonb_build_object('passo', '2c. Vídeo com 92% assistido: conclui', 'ok', (r ->> 'concluida')::boolean);
  r := pg_temp.como(v_prof, 'iaraflix_progresso', jsonb_build_object('aula_id', v_aula, 'posicao_s', 10, 'assistido_s', 20));
  v_out := v_out || jsonb_build_object('passo', '2d. O tempo assistido não diminui', 'ok',
    (select assistido_s from iara.iaraflix_progresso where user_id = v_prof and aula_id = v_aula) = 185);
  for a in select id from iara.iaraflix_aulas where trilha_id = 'primeiros-passos' and id <> v_aula loop
    r := pg_temp.como(v_prof, 'iaraflix_progresso', jsonb_build_object('aula_id', a.id, 'estudada', true));
  end loop;
  v_out := v_out || jsonb_build_object('passo', '2e. Todas as aulas concluídas: pode responder', 'ok', (r ->> 'pode_avaliar')::boolean, 'r', r);

  -- 3. Perguntas e certificado
  r := pg_temp.como(v_prof, 'iaraflix_avaliar', '{"trilha_id": "primeiros-passos", "respostas": [1, 0, 1, 0, 1]}');
  v_out := v_out || jsonb_build_object('passo', '3a. Uma errada: sem certificado, com a explicação do erro', 'ok',
    not (r ->> 'aprovado')::boolean and (r ->> 'acertos')::int = 4 and r ->> 'certificado' is null
    and exists (select 1 from jsonb_array_elements(r -> 'resultado') x where not (x ->> 'certa')::boolean and x ->> 'explicacao' is not null));
  r := pg_temp.como(v_prof, 'iaraflix_avaliar', '{"trilha_id": "primeiros-passos", "respostas": [1, 1, 1, 0, 1]}');
  v_cert := r ->> 'certificado';
  v_out := v_out || jsonb_build_object('passo', '3b. Todas certas: certificado emitido na 2ª tentativa', 'ok',
    (r ->> 'aprovado')::boolean and v_cert ~ '^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$'
    and (select tentativas from iara.iaraflix_participacoes where user_id = v_prof and trilha_id = 'primeiros-passos') = 2);
  execute 'set local role anon';
  r := api.declaracao_verificar(jsonb_build_object('codigo', v_cert));
  execute 'reset role';
  v_out := v_out || jsonb_build_object('passo', '3c. Verificação pública do certificado (sem login): válido, nome abreviado', 'ok',
    (r ->> 'encontrada')::boolean and r ->> 'tipo_rotulo' like '%IARAFLIX%' and r ->> 'resumo' like '%Primeiros passos%', 'r', r);
  v_out := v_out || jsonb_build_object('passo', '3d. Conclusão registrada na auditoria', 'ok',
    exists (select 1 from iara.audit_log where action = 'IARAFLIX' and summary like '%' || v_cert || '%'));

  -- 4. Vídeo: só o gateway assina; a gestão envia; o professor não
  r := pg_temp.como(v_prof, 'iaraflix_video_acesso', jsonb_build_object('id', v_aula));
  v_out := v_out || jsonb_build_object('passo', '4a. Acesso ao vídeo da própria trilha: caminho no bucket privado', 'ok', r ->> 'bucket' = 'iara-treinamento');
  r := pg_temp.como(v_prof, 'iaraflix_envio_autorizar', jsonb_build_object('aula_id', v_aula, 'tipo', 'VIDEO', 'mime', 'video/mp4', 'bytes', 1000));
  v_out := v_out || jsonb_build_object('passo', '4b. Professor tentando enviar vídeo: recusado', 'ok', r ->> 'codigo' = '42501');
  r := pg_temp.como(v_inov, 'iaraflix_envio_autorizar', jsonb_build_object('aula_id', v_aula, 'tipo', 'VIDEO', 'mime', 'video/mp4', 'bytes', 60000000));
  v_out := v_out || jsonb_build_object('passo', '4c. Vídeo acima de 50 MB: recusado com orientação', 'ok', r ->> 'codigo' = '22023');
  r := pg_temp.como(v_inov, 'iaraflix_envio_autorizar', jsonb_build_object('aula_id', v_aula, 'tipo', 'VIDEO', 'mime', 'video/mp4', 'bytes', 30000000));
  v_out := v_out || jsonb_build_object('passo', '4d. Gestão autoriza o envio', 'ok', r ->> 'caminho' like 'aulas/' || v_aula || '/%.mp4');
  r := pg_temp.como(v_inov, 'iaraflix_envio_confirmar', jsonb_build_object('aula_id', v_aula, 'tipo', 'VIDEO', 'caminho', r ->> 'caminho', 'mime', 'video/mp4', 'bytes', 30000000));
  v_out := v_out || jsonb_build_object('passo', '4e. Publicar sem confirmar "só dados fictícios": recusado', 'ok', r ->> 'codigo' = '22023');
  r := pg_temp.como(v_inov, 'iaraflix_envio_confirmar', jsonb_build_object('aula_id', v_aula, 'tipo', 'VIDEO', 'caminho', 'aulas/outra/coisa.mp4', 'conferido', true));
  v_out := v_out || jsonb_build_object('passo', '4f. Caminho fora da pasta da aula: recusado', 'ok', r ->> 'codigo' = '22023');

  -- 5. Painel de adesão
  r := pg_temp.como(v_inov, 'iaraflix_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', '5a. Painel da rede: previstos, concluídos e unidades', 'ok',
    (r -> 'resumo' ->> 'previstos')::int > 1000 and (r -> 'resumo' ->> 'concluidas')::int > 0 and jsonb_array_length(r -> 'unidades') > 50,
    'resumo', r -> 'resumo');
  r := pg_temp.como(v_dir, 'iaraflix_painel', '{"unidade": 1}');
  v_out := v_out || jsonb_build_object('passo', '5b. Diretor: só a própria unidade (ignora outra), com a lista da equipe', 'ok',
    (r ->> 'unidade')::int = (select unit_id from iara.app_users where id = v_dir) and jsonb_array_length(r -> 'pessoas') > 0, 'escopo', r ->> 'escopo');
  r := pg_temp.como(v_prof, 'iaraflix_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', '5c. Professor: sem painel de adesão', 'ok', r ->> 'codigo' = '42501');
  r := pg_temp.como(v_prof, 'iaraflix_gestao', '{}');
  v_out := v_out || jsonb_build_object('passo', '5d. Professor: sem gestão', 'ok', r ->> 'codigo' = '42501');

  -- 6. Limpeza da demonstração apaga o que as personas fizeram e mantém a adesão gerada
  v_n := (select count(*) from iara.iaraflix_participacoes where user_id is null and is_demo);
  r := iara.demo_purge_iaraflix(null);
  v_out := v_out || jsonb_build_object('passo', '6. Limpeza: progresso das personas apagado, adesão gerada mantida', 'ok',
    not exists (select 1 from iara.iaraflix_progresso where user_id = v_prof)
    and (select count(*) from iara.iaraflix_participacoes where user_id is null and is_demo) = v_n, 'r', r);

  -- 7. LGPD
  r := iara.classificacao_pendente();
  v_out := v_out || jsonb_build_object('passo', '7. Colunas novas classificadas (LGPD)', 'ok', r = '[]'::jsonb, 'lista', r);

  raise exception 'RESULTADO: %', v_out;  -- reverte tudo
end $$;
