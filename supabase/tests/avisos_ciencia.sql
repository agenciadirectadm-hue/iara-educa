-- Avisos da família: todo aviso no quadro pede ciência e traz a hora do envio; a ciência tira do quadro e leva ao histórico, com a hora; o
-- histórico guarda o aviso mesmo depois de arquivado; a escola vê a contagem; outra família não é afetada.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/avisos_ciencia.sql
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
  r jsonb; r2 jsonb;
  v_unit integer := (iara.setting('demo_unit_maria'))::int;
  v_id uuid;
  v_enq uuid;
  v_ped integer;
  v_antes integer;
begin
  perform iara.session_create('CIDADAO', null, 'av-fam', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_unit, 'av-dir', 'teste');

  r := pg_temp.as_call('av-dir', 'mural_publicar', jsonb_build_object('titulo', 'Aviso de teste da ciência', 'texto', 'Aviso que não pediu ciência ao publicar.', 'exige_confirmacao', false));
  v_id := (r ->> 'id')::uuid;

  r := pg_temp.as_call('av-fam', 'familia_avisos', '{}');
  v_ped := (r ->> 'pendentes_confirmacao')::int;
  v_out := v_out || jsonb_build_object('passo', 'C1. Todo aviso no quadro pede ciência e traz a hora do envio', 'ok',
    jsonb_array_length(r -> 'avisos') > 0
    and not exists (select 1 from jsonb_array_elements(r -> 'avisos') a where not (a ->> 'exige_confirmacao')::boolean or a ->> 'publicado_em' is null or (a ->> 'confirmado')::boolean)
    and exists (select 1 from jsonb_array_elements(r -> 'avisos') a where (a ->> 'id')::uuid = v_id)
    and v_ped = jsonb_array_length(r -> 'avisos'), 'erro', r ->> 'erro', 'quadro', jsonb_array_length(r -> 'avisos'));

  -- só ler não tira do quadro
  r := pg_temp.as_call('av-fam', 'familia_aviso_ler', jsonb_build_object('id', v_id));
  r2 := pg_temp.as_call('av-fam', 'familia_avisos', '{}');
  v_out := v_out || jsonb_build_object('passo', 'C2. Ler não é ciência: o aviso continua no quadro', 'ok',
    not (r ->> 'confirmado')::boolean and exists (select 1 from jsonb_array_elements(r2 -> 'avisos') a where (a ->> 'id')::uuid = v_id and (a ->> 'lido')::boolean));

  -- ciência: sai do quadro e vai para o histórico, com a hora
  v_antes := (select jsonb_array_length(r2 -> 'historico'));
  r := pg_temp.as_call('av-fam', 'familia_aviso_ler', jsonb_build_object('id', v_id, 'confirmar', true));
  r2 := pg_temp.as_call('av-fam', 'familia_avisos', '{}');
  v_out := v_out || jsonb_build_object('passo', 'C3. A ciência tira do quadro e leva ao histórico, com a hora', 'ok',
    (r ->> 'confirmado')::boolean and r ->> 'ciente_em' is not null
    and not exists (select 1 from jsonb_array_elements(r2 -> 'avisos') a where (a ->> 'id')::uuid = v_id)
    and exists (select 1 from jsonb_array_elements(r2 -> 'historico') a where (a ->> 'id')::uuid = v_id and a ->> 'ciente_em' is not null and a ->> 'publicado_em' is not null)
    and jsonb_array_length(r2 -> 'historico') = v_antes + 1 and (r2 ->> 'pendentes_confirmacao')::int = v_ped - 1, 'erro', r ->> 'erro');

  -- a escola conta a ciência mesmo sem ter pedido ao publicar
  r := pg_temp.as_call('av-dir', 'mural_feed', '{}');
  v_out := v_out || jsonb_build_object('passo', 'C4. A escola vê a ciência na contagem', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'publicacoes') a where (a ->> 'id')::uuid = v_id and (a ->> 'confirmacoes')::int = 1), 'erro', r ->> 'erro');

  -- arquivado ou vencido, continua no histórico da família
  r := pg_temp.as_call('av-dir', 'mural_arquivar', jsonb_build_object('id', v_id));
  r2 := pg_temp.as_call('av-fam', 'familia_avisos', '{}');
  v_out := v_out || jsonb_build_object('passo', 'C5. Aviso arquivado continua no histórico', 'ok', r ->> 'situacao' = 'ARQUIVADO'
    and exists (select 1 from jsonb_array_elements(r2 -> 'historico') a where (a ->> 'id')::uuid = v_id));

  -- enquete: responder não é ciência; depois da resposta ela segue no quadro até a ciência, e o voto vai junto para o histórico
  r := pg_temp.as_call('av-dir', 'mural_publicar', jsonb_build_object('tipo', 'ENQUETE', 'titulo', 'Enquete de teste da ciência', 'texto', 'Qual o melhor dia para a reunião?', 'opcoes', jsonb_build_array('Segunda', 'Quarta')));
  v_enq := (r ->> 'id')::uuid;
  r := pg_temp.as_call('av-fam', 'familia_enquete_responder', jsonb_build_object('id', v_enq, 'opcao', 2));
  r2 := pg_temp.as_call('av-fam', 'familia_avisos', '{}');
  v_out := v_out || jsonb_build_object('passo', 'C6. Enquete respondida segue no quadro até a ciência', 'ok',
    exists (select 1 from jsonb_array_elements(r2 -> 'avisos') a where (a ->> 'id')::uuid = v_enq and (a ->> 'minha_resposta')::int = 2));
  r := pg_temp.as_call('av-fam', 'familia_aviso_ler', jsonb_build_object('id', v_enq, 'confirmar', true));
  r2 := pg_temp.as_call('av-fam', 'familia_avisos', '{}');
  v_out := v_out || jsonb_build_object('passo', 'C7. A enquete vai ao histórico com o voto', 'ok',
    exists (select 1 from jsonb_array_elements(r2 -> 'historico') a where (a ->> 'id')::uuid = v_enq and (a ->> 'minha_resposta')::int = 2 and a -> 'votos' is not null));

  -- outro perfil não abre
  r := pg_temp.as_call('av-dir', 'familia_avisos', '{}');
  v_out := v_out || jsonb_build_object('passo', 'C8. Só o responsável abre os avisos da família', 'ok', r ->> 'codigo' = '42501');

  raise exception 'RESULTADO: %', v_out;
end $$;
