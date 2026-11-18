-- Registro de entradas no portal (migração 099.22): gravação com localização, agrupamento, acesso só do titular e fora do Oráculo.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/registro_entradas.sql
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

do $$
declare
  v_out jsonb := '[]';
  r jsonb;
  g jsonb;
  v_user uuid;
  v_antes bigint := (select coalesce(max(id), 0) from iara.acesso_entradas);
  v_chave_user uuid := (select user_id from iara.oraculo_chaves where revogada_em is null order by criada_em limit 1);
  v_n integer;
  v_max integer;
  v_ok boolean;
begin
  perform iara.session_create('COMERCIAL', null, 'test-entradas', 'teste');
  v_user := (select user_id from iara.app_sessions where token_hash = 'test-entradas');

  -- 1. localização: um IP público dos EUA e um de Maringá
  g := iara.geoip('8.8.8.8');
  v_out := v_out || jsonb_build_object('passo', '1a. IP dos EUA: só o país', 'ok', g ->> 'pais' = 'US' and g ->> 'cidade' is null, 'g', g);
  g := iara.geoip('200.160.0.8');
  v_out := v_out || jsonb_build_object('passo', '1b. IP brasileiro: UF e cidade', 'ok', g ->> 'pais' = 'BR' and length(g ->> 'estado') = 2 and g ->> 'cidade' is not null, 'g', g);
  g := iara.geoip('2804:14c::1');
  v_out := v_out || jsonb_build_object('passo', '1c. IPv6 brasileiro', 'ok', g ->> 'pais' = 'BR', 'g', g);
  v_out := v_out || jsonb_build_object('passo', '1d. IP inválido não quebra', 'ok', iara.geoip('desconhecido') = '{}'::jsonb and iara.geoip(null) = '{}'::jsonb);

  -- 2. gravação e agrupamento
  perform iara.acesso_registrar('{"evento": "SENHA_ERRADA", "ip": "200.160.0.8", "aparelho": "teste"}');
  v_out := v_out || jsonb_build_object('passo', '2a. Senha errada gravada com a localização', 'ok',
    exists (select 1 from iara.acesso_entradas where id > v_antes and evento = 'SENHA_ERRADA' and pais = 'BR' and aparelho = 'teste'));
  perform iara.acesso_registrar('{"evento": "BARRADO", "ip": "203.0.113.9"}');
  perform iara.acesso_registrar('{"evento": "BARRADO", "ip": "203.0.113.9"}');
  select count(*), max(n) into v_n, v_max from iara.acesso_entradas where id > v_antes and evento = 'BARRADO' and ip = '203.0.113.9';
  v_out := v_out || jsonb_build_object('passo', '2b. Barrado repetido soma na mesma linha', 'ok', v_n = 1 and v_max = 2);
  if v_chave_user is not null then
    perform iara.acesso_registrar(jsonb_build_object('evento', 'ORACULO_MCP', 'ip', '160.79.104.10', 'user_id', v_chave_user));
    perform iara.acesso_registrar(jsonb_build_object('evento', 'ORACULO_MCP', 'ip', '160.79.104.10', 'user_id', v_chave_user));
    select count(*), max(n) into v_n, v_max from iara.acesso_entradas where id > v_antes and evento = 'ORACULO_MCP';
    v_out := v_out || jsonb_build_object('passo', '2c. Oráculo: uma linha por conexão e por hora, com o nome da conexão', 'ok',
      v_n = 1 and v_max = 2 and exists (select 1 from iara.acesso_entradas where id > v_antes and evento = 'ORACULO_MCP'
                                              and detalhe = (select rotulo from iara.oraculo_chaves where user_id = v_chave_user)));
  end if;
  perform iara.acesso_registrar('{"evento": "SENHA_CERTA", "ip": "200.160.0.8", "passe": "abcTESTEdef"}');
  perform iara.acesso_registrar('{"evento": "PERFIL_ABERTO", "ip": "200.160.0.8", "passe": "abcTESTEdef", "perfil": "PREFEITO"}');
  begin
    perform iara.acesso_registrar('{"evento": "INVENTADO"}');
    v_ok := false;
  exception when check_violation then v_ok := true;
  end;
  v_out := v_out || jsonb_build_object('passo', '2d. Evento desconhecido recusado', 'ok', v_ok);

  -- 3. só o titular vê
  r := pg_temp.como(v_user, 'acesso_entradas', '{}');
  v_out := v_out || jsonb_build_object('passo', '3a. Sem a senha do titular: recusado', 'ok', r ->> 'codigo' = '42501');
  r := pg_temp.como(v_user, 'acesso_entradas_entrar', '{"senha": "senha-errada-do-teste"}');
  v_out := v_out || jsonb_build_object('passo', '3b. Senha do titular errada: não libera e conta a tentativa', 'ok',
    not (r ->> 'ok')::boolean and (r ->> 'restantes')::int = 4, 'r', r);
  insert into iara.sim_liberacoes (user_id, nivel, expira_em) values (v_user, 'TITULAR', now() + interval '1 hour');
  r := pg_temp.como(v_user, 'acesso_entradas', '{"dias": 1}');
  v_out := v_out || jsonb_build_object('passo', '3c. Titular vê a senha certa com o perfil aberto junto', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'itens') i where i ->> 'evento' = 'SENHA_CERTA'
            and i -> 'perfis' ? (select short_name from iara.organizational_roles where code = 'PREFEITO'))
    and not exists (select 1 from jsonb_array_elements(r -> 'itens') i where i ->> 'evento' = 'PERFIL_ABERTO' and i ->> 'ip' = '200.160.0.8'),
    'perfil', (select short_name from iara.organizational_roles where code = 'PREFEITO'));
  v_out := v_out || jsonb_build_object('passo', '3d. Resumo por tipo', 'ok', (r -> 'resumo' ->> 'BARRADO')::int >= 2);

  -- 4. ninguém lê a tabela direto, e o Oráculo não a vê
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    execute 'select count(*) from iara.acesso_entradas' into v_n;
    execute 'reset role';
    v_ok := v_n = 0;
  exception when insufficient_privilege then
    execute 'reset role';
    v_ok := true;
  end;
  v_out := v_out || jsonb_build_object('passo', '4a. Perfil comum não lê a tabela', 'ok', v_ok);
  v_out := v_out || jsonb_build_object('passo', '4b. Fora do Oráculo', 'ok',
    'acesso_entradas' = any (iara.oraculo_base_fora()) and 'geoip_local' = any (iara.oraculo_base_fora())
    and not has_table_privilege('oraculo_leitor', 'iara.acesso_entradas', 'select')
    and not has_column_privilege('oraculo_leitor', 'iara.acesso_entradas', 'ip', 'select'));
  v_out := v_out || jsonb_build_object('passo', '4c. Funções internas fechadas ao público', 'ok',
    not has_function_privilege('authenticated', 'iara.acesso_registrar(jsonb)', 'execute')
    and not has_function_privilege('anon', 'iara.geoip(text)', 'execute')
    and not has_function_privilege('authenticated', 'iara.geoip_trocar(text, text)', 'execute'));

  raise exception 'RESULTADO: %', v_out;  -- reverte tudo
end $$;
