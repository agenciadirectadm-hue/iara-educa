-- Vídeos da SEDUC para as famílias (099.16): lista pública, rascunho escondido, links do YouTube, arquivo e gestão.
-- Roda numa transação revertida. Executar: node scripts/aplicar.mjs supabase/tests/videos_familia.sql
create or replace function pg_temp.como(p_uid uuid, p_fn text, p_args jsonb) returns jsonb language plpgsql as $f$
declare
  v jsonb;
begin
  if p_uid is null then
    perform set_config('request.jwt.claims', '{"role": "anon"}', true);
    execute 'set local role anon';
  else
    perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
  end if;
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
  v_inov uuid;
  v_cid uuid;
  v_yt uuid;
  v_rasc uuid;
  v_arq uuid;
  v_n integer;
begin
  perform iara.session_create('INOVACAO', null, 'test-vid-inov', 'teste');
  v_inov := (select user_id from iara.app_sessions where token_hash = 'test-vid-inov');
  perform iara.session_create('CIDADAO', null, 'test-vid-cid', 'teste');
  v_cid := (select user_id from iara.app_sessions where token_hash = 'test-vid-cid');

  -- 1. links do YouTube em vários formatos
  v_out := v_out || jsonb_build_object('passo', '1. Links do YouTube reconhecidos (watch, youtu.be, shorts, embed, código) e link estranho recusado', 'ok',
    iara.youtube_id('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10s') = 'dQw4w9WgXcQ'
    and iara.youtube_id('https://youtu.be/dQw4w9WgXcQ?si=abc') = 'dQw4w9WgXcQ'
    and iara.youtube_id('https://youtube.com/shorts/dQw4w9WgXcQ') = 'dQw4w9WgXcQ'
    and iara.youtube_id('https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ') = 'dQw4w9WgXcQ'
    and iara.youtube_id(' dQw4w9WgXcQ ') = 'dQw4w9WgXcQ'
    and iara.youtube_id('https://vimeo.com/12345') is null);

  -- 2. gestão publica um do YouTube, deixa um em rascunho e cria um de arquivo
  r := pg_temp.como(v_inov, 'videos_familia_salvar', '{"titulo": "Como falar com a IARA", "categoria": "TUTORIAL", "fonte": "YOUTUBE", "youtube": "https://youtu.be/dQw4w9WgXcQ", "situacao": "PUBLICADO"}');
  v_yt := (r ->> 'id')::uuid;
  r := pg_temp.como(v_inov, 'videos_familia_salvar', '{"titulo": "Rascunho da matrícula", "categoria": "MATRICULA", "fonte": "YOUTUBE", "youtube": "dQw4w9WgXcQ"}');
  v_rasc := (r ->> 'id')::uuid;
  r := pg_temp.como(v_inov, 'videos_familia_salvar', '{"titulo": "Sem link", "fonte": "YOUTUBE", "youtube": "https://vimeo.com/1"}');
  v_out := v_out || jsonb_build_object('passo', '2a. Link que não é do YouTube: recusado', 'ok', r ->> 'codigo' = '22023');
  r := pg_temp.como(v_inov, 'videos_familia_salvar', '{"titulo": "Arquivo", "fonte": "ARQUIVO", "situacao": "PUBLICADO"}');
  v_out := v_out || jsonb_build_object('passo', '2b. Publicar vídeo de arquivo sem o arquivo: recusado', 'ok', r ->> 'codigo' = '22023');
  r := pg_temp.como(v_inov, 'videos_familia_salvar', '{"titulo": "Arquivo", "fonte": "ARQUIVO"}');
  v_arq := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', '2c. Vídeos salvos (YouTube publicado, rascunho, arquivo em rascunho)', 'ok', v_yt is not null and v_rasc is not null and v_arq is not null);

  -- 3. sem login: só o publicado
  r := pg_temp.como(null, 'videos_familia_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', '3a. Sem login: a lista mostra o publicado e esconde os rascunhos', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'videos') x where (x ->> 'id')::uuid = v_yt)
    and not exists (select 1 from jsonb_array_elements(r -> 'videos') x where (x ->> 'id')::uuid in (v_rasc, v_arq))
    and not exists (select 1 from jsonb_array_elements(r -> 'videos') x where x ? 'visualizacoes'));
  r := pg_temp.como(null, 'videos_familia_ver', jsonb_build_object('id', v_rasc));
  v_out := v_out || jsonb_build_object('passo', '3b. Sem login: abrir rascunho pelo id é recusado', 'ok', r ->> 'codigo' = 'P0002');
  r := pg_temp.como(null, 'videos_familia_lista', '{"gestao": true}');
  v_out := v_out || jsonb_build_object('passo', '3c. Sem login: visão da gestão recusada (sessão necessária)', 'ok', r ->> 'codigo' = '28000');
  r := pg_temp.como(v_cid, 'videos_familia_salvar', '{"titulo": "x", "youtube": "dQw4w9WgXcQ"}');
  v_out := v_out || jsonb_build_object('passo', '3d. Família não publica vídeo', 'ok', r ->> 'codigo' = '42501');

  -- 4. visualizações e arquivo
  perform pg_temp.como(null, 'videos_familia_assistiu', jsonb_build_object('id', v_yt));
  perform pg_temp.como(v_cid, 'videos_familia_assistiu', jsonb_build_object('id', v_yt));
  perform pg_temp.como(null, 'videos_familia_assistiu', jsonb_build_object('id', v_rasc));
  v_out := v_out || jsonb_build_object('passo', '4a. Visualizações contam só no publicado', 'ok',
    (select visualizacoes from iara.videos_familia where id = v_yt) = 2 and (select visualizacoes from iara.videos_familia where id = v_rasc) = 0);
  r := pg_temp.como(null, 'videos_familia_acesso', jsonb_build_object('id', v_yt));
  v_out := v_out || jsonb_build_object('passo', '4b. Vídeo do YouTube não tem arquivo para assinar', 'ok', r ->> 'codigo' = 'P0002');
  r := pg_temp.como(v_inov, 'videos_familia_envio_autorizar', jsonb_build_object('id', v_arq, 'mime', 'video/mp4', 'bytes', 1000));
  v_out := v_out || jsonb_build_object('passo', '4c. Envio autorizado na pasta familias/ do bucket privado', 'ok', r ->> 'caminho' like 'familias/' || v_arq || '/%.mp4');
  r := pg_temp.como(v_inov, 'videos_familia_envio_confirmar', jsonb_build_object('id', v_arq, 'caminho', r ->> 'caminho', 'mime', 'video/mp4', 'bytes', 1000, 'duracao_s', 10));
  r := pg_temp.como(v_inov, 'videos_familia_salvar', jsonb_build_object('id', v_arq, 'titulo', 'Arquivo', 'fonte', 'ARQUIVO', 'situacao', 'PUBLICADO'));
  r := pg_temp.como(null, 'videos_familia_acesso', jsonb_build_object('id', v_arq));
  v_out := v_out || jsonb_build_object('passo', '4d. Depois do arquivo e de publicar: sem login recebe o caminho para o gateway assinar', 'ok', r ->> 'bucket' = 'iara-treinamento' and r ->> 'video' like 'familias/%');

  -- 5. busca da IARA e exclusão
  r := pg_temp.como(v_cid, 'videos_familia_lista', '{"q": "tem video de como falar com a iara?"}');
  v_out := v_out || jsonb_build_object('passo', '5a. Busca da IARA: o vídeo que combina vem primeiro', 'ok', (r -> 'videos' -> 0 ->> 'id')::uuid = v_yt);
  r := pg_temp.como(v_inov, 'videos_familia_salvar', jsonb_build_object('id', v_arq, 'excluir', true));
  v_out := v_out || jsonb_build_object('passo', '5b. Excluir: some e o arquivo vai para a fila de descarte', 'ok',
    not exists (select 1 from iara.videos_familia where id = v_arq) and exists (select 1 from iara.arquivos_descartar where caminho like 'familias/' || v_arq || '/%'));
  v_out := v_out || jsonb_build_object('passo', '5c. Publicação registrada na auditoria', 'ok',
    exists (select 1 from iara.audit_log where action = 'VIDEO_FAMILIA' and entity_id = v_yt::text));

  raise exception 'RESULTADO: %', v_out;  -- reverte tudo
end $$;
