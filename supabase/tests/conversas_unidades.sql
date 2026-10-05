-- Conversas por unidade responsável, sob controle da Secretaria. Roda numa transação revertida (não deixa resíduo).
-- Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/conversas_unidades.sql
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
  v_conv uuid;
  v_unit integer := (iara.setting('demo_unit_maria'))::int;
  v_outra integer;
begin
  select id into v_outra from iara.education_units where id <> v_unit and status = 'ATIVA' order by id limit 1;
  perform iara.session_create('DIRETOR_UNIDADE', v_outra, 'test-diretor-outra-unidade', 'teste');

  r := pg_temp.as_call('test-cidadao', 'iara_conversation', '{"new": true}');
  v_conv := (r -> 'conversation' ->> 'id')::uuid;
  r := pg_temp.as_call('test-cidadao', 'conversation_handoff', jsonb_build_object('conversation_id', v_conv, 'reason', 'Dúvida sobre o horário de saída'));
  v_out := v_out || jsonb_build_object('passo', '1. Maria pede atendente (Ana matriculada) → secretaria da unidade da Ana', 'para', r ->> 'label', 'unidade_certa', (r ->> 'unit_id')::int = v_unit);

  r := pg_temp.as_call('test-diretor', 'conversas_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', '2. Direção da unidade vê a conversa aguardando', 'escopo', r ->> 'escopo',
    've', exists (select 1 from jsonb_array_elements(r -> 'itens') i where (i ->> 'id')::uuid = v_conv and i ->> 'quem' = 'AGUARDANDO'));

  r := pg_temp.as_call('test-diretor-outra-unidade', 'conversas_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', '3. Outra unidade não vê (deve ser false)',
    've', exists (select 1 from jsonb_array_elements(r -> 'itens') i where (i ->> 'id')::uuid = v_conv));
  r := pg_temp.as_call('test-diretor-outra-unidade', 'conversation_detail', jsonb_build_object('id', v_conv));
  v_out := v_out || jsonb_build_object('passo', '4. Outra unidade abre a conversa (deve negar)', 'r', r ->> 'erro');

  r := pg_temp.as_call('test-diretor', 'conversation_transfer', jsonb_build_object('id', v_conv, 'unit_id', v_outra, 'motivo', 'Teste de transferência entre unidades'));
  v_out := v_out || jsonb_build_object('passo', '5. Unidade tenta mandar para outra unidade (deve negar)', 'r', r ->> 'erro');

  r := pg_temp.as_call('test-diretor', 'conversation_takeover', jsonb_build_object('id', v_conv));
  r := pg_temp.as_call('test-diretor', 'conversation_operator_message', jsonb_build_object('id', v_conv, 'body', 'Olá! Aqui é a direção do CMEI. A saída é às 17h.'));
  v_out := v_out || jsonb_build_object('passo', '6. Direção assume e responde', 'estado', r -> 'conversation' ->> 'state',
    'primeira_resposta', (r -> 'conversation' ->> 'first_reply_at') is not null);

  r := pg_temp.as_call('test-diretor', 'conversation_transfer', jsonb_build_object('id', v_conv, 'team', 'ATENDIMENTO', 'motivo', 'Família pediu informação de outra rede'));
  v_out := v_out || jsonb_build_object('passo', '7. Unidade devolve à Secretaria', 'responsavel', r -> 'conversation' ->> 'responsible', 'estado', r -> 'conversation' ->> 'state');

  r := pg_temp.as_call('test-analista', 'conversas_controle', '{}');
  v_out := v_out || jsonb_build_object('passo', '8. Secretaria acompanha (controle)', 'totais', r -> 'totais',
    'grupos', jsonb_array_length(r -> 'responsaveis'), 'atendimento_aguardando',
    (select (g ->> 'aguardando')::int from jsonb_array_elements(r -> 'responsaveis') g where g ->> 'equipe' = 'ATENDIMENTO' and g ->> 'unit_id' is null));

  r := pg_temp.as_call('test-analista', 'conversation_transfer', jsonb_build_object('id', v_conv, 'unit_id', v_outra, 'motivo', 'Família mudou de unidade'));
  v_out := v_out || jsonb_build_object('passo', '9. Secretaria transfere para outra unidade', 'responsavel', r -> 'conversation' ->> 'responsible');
  r := pg_temp.as_call('test-diretor-outra-unidade', 'conversas_lista', '{"filtro": "aguardando"}');
  v_out := v_out || jsonb_build_object('passo', '10. A nova unidade passa a ver', 've',
    exists (select 1 from jsonb_array_elements(r -> 'itens') i where (i ->> 'id')::uuid = v_conv));

  r := pg_temp.as_call('test-cidadao', 'conversas_controle', '{}');
  v_out := v_out || jsonb_build_object('passo', '11. Cidadã tenta ver o controle (deve negar)', 'r', r ->> 'erro');

  raise exception 'RESULTADO: %', v_out;  -- reverte tudo
end $$;
