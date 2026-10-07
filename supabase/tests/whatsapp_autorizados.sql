-- WhatsApp de teste: lista de números autorizados (Fase 1, item 1 do documento de estrutura).
-- Roda numa transação revertida (não deixa resíduo). Cada passo traz "ok": true quando o comportamento é o esperado.
-- Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/whatsapp_autorizados.sql
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
  v_canal uuid := (select id from iara.whatsapp_channels order by created_at limit 1);
begin
  perform iara.session_create('INOVACAO', null, 'test-wa-inovacao', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', null, 'test-wa-diretor', 'teste');

  -- 1. lista desligada: qualquer número conversa
  r := iara.whatsapp_triagem(v_canal, '+5544911112222');
  v_out := v_out || jsonb_build_object('passo', '1. Lista desligada: qualquer número', 'ok', (r ->> 'autorizado')::boolean);

  -- 2. quem não gerencia o canal não grava a lista
  r := pg_temp.as_call('test-wa-diretor', 'whatsapp_autorizados_salvar', '{"somente_autorizados": true, "numeros": ["5544999990000"]}');
  v_out := v_out || jsonb_build_object('passo', '2. Direção não grava a lista (deve negar)', 'ok', r ->> 'codigo' = '42501');

  -- 3. número inválido é recusado; lista ligada vazia também
  r := pg_temp.as_call('test-wa-inovacao', 'whatsapp_autorizados_salvar', '{"somente_autorizados": true, "numeros": ["4499"]}');
  v_out := v_out || jsonb_build_object('passo', '3a. Número inválido (deve negar)', 'ok', r ->> 'codigo' = '22023');
  r := pg_temp.as_call('test-wa-inovacao', 'whatsapp_autorizados_salvar', '{"somente_autorizados": true, "numeros": []}');
  v_out := v_out || jsonb_build_object('passo', '3b. Ligar sem números (deve negar)', 'ok', r ->> 'codigo' = '22023');

  -- 4. Inovação liga a lista com um número
  r := pg_temp.as_call('test-wa-inovacao', 'whatsapp_autorizados_salvar', '{"somente_autorizados": true, "numeros": ["+55 (44) 99999-0000"]}');
  v_out := v_out || jsonb_build_object('passo', '4. Inovação liga a lista', 'ok', (r ->> 'somente_autorizados')::boolean and r -> 'autorizados' = '["5544999990000"]'::jsonb);

  -- 5. número autorizado conversa; outro número é barrado e avisado uma vez
  r := iara.whatsapp_triagem(v_canal, '+5544999990000');
  v_out := v_out || jsonb_build_object('passo', '5a. Número autorizado conversa', 'ok', (r ->> 'autorizado')::boolean);
  r := iara.whatsapp_triagem(v_canal, '+5544911112222');
  v_out := v_out || jsonb_build_object('passo', '5b. Fora da lista: barrado e avisado', 'ok', not (r ->> 'autorizado')::boolean and (r ->> 'avisar')::boolean);
  r := iara.whatsapp_triagem(v_canal, '+5544911112222');
  v_out := v_out || jsonb_build_object('passo', '5c. Segunda mensagem: sem novo aviso (6 h)', 'ok', not (r ->> 'autorizado')::boolean and not (r ->> 'avisar')::boolean);

  -- 6. nada foi cadastrado para o número barrado
  v_out := v_out || jsonb_build_object('passo', '6. Número barrado sem contato cadastrado', 'ok',
    not exists (select 1 from iara.whatsapp_contacts where telefone_e164 = '+5544911112222'));

  -- 7. a auditoria registra a mudança sem expor os números
  v_out := v_out || jsonb_build_object('passo', '7. Auditoria sem números', 'ok',
    exists (select 1 from iara.audit_log where action = 'WHATSAPP_AUTORIZADOS' and summary like '%1 número(s)%' and summary not like '%99999%'));

  raise exception 'RESULTADO: %', v_out;  -- reverte tudo
end $$;
