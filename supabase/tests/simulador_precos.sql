-- Simulador de preços (perfil Comercial): fechado por senha; o comercial vê o preço cheio (sem redutor); o titular vê e define
-- o redutor; troca de senha; bloqueio depois de 5 senhas erradas; os perfis da prefeitura e o visitante não veem preços.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/simulador_precos.sql
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

create or replace function pg_temp.as_anon(p_fn text, p_args jsonb) returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', '{"role": "anon"}', true);
  execute 'set local role anon';
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
  r2 jsonb;
  r3 jsonb;
  r4 jsonb;
  v_mun integer;
  i integer;
begin
  -- senhas conhecidas só dentro desta transação (revertida no fim): as senhas reais do simulador não mudam
  update iara.sim_acesso set senha_hash = extensions.crypt('123456', extensions.gen_salt('bf'));
  perform iara.session_create('COMERCIAL', null, 'sp-com', 'teste');
  perform iara.session_create('COMERCIAL', null, 'sp-tit', 'teste');
  perform iara.session_create('COMERCIAL', null, 'sp-bloq', 'teste');
  perform iara.session_create('PREFEITO', null, 'sp-pref', 'teste');
  perform iara.session_create('SECRETARIO', null, 'sp-sec', 'teste');

  -- P1: fechado sem senha; senha errada conta tentativa; a certa abre
  r := pg_temp.as_call('sp-com', 'simulador_precos', '{}');
  r2 := pg_temp.as_call('sp-com', 'simulador_entrar', '{"nivel": "COMERCIAL", "senha": "errada"}');
  r3 := pg_temp.as_call('sp-com', 'simulador_entrar', '{"nivel": "COMERCIAL", "senha": "123456"}');
  v_out := v_out || jsonb_build_object('passo', 'P1. Sem senha não abre; senha errada é recusada; 123456 abre como comercial', 'ok',
    r ->> 'codigo' = '42501' and not (r2 ->> 'ok')::boolean and (r2 ->> 'restantes')::int = 4
    and (r3 ->> 'ok')::boolean and r3 ->> 'nivel' = 'COMERCIAL',
    'sem_senha', r ->> 'erro', 'errada', r2, 'certa', r3);

  -- P2: o comercial vê preços, mas nenhum redutor, e não consegue definir redutor
  r := pg_temp.as_call('sp-com', 'simulador_precos', '{}');
  v_mun := (r -> 'municipios' -> 0 ->> 'id')::int;
  r2 := pg_temp.as_call('sp-com', 'simulador_redutor', jsonb_build_object('municipio_id', v_mun, 'redutor', 0.1));
  v_out := v_out || jsonb_build_object('passo', 'P2. Comercial: 33 agentes e 30 municípios, sem redutor; não define redutor', 'ok',
    r ->> 'nivel' = 'COMERCIAL' and jsonb_array_length(r -> 'agentes') = 33 and jsonb_array_length(r -> 'municipios') = 30
    and not exists (select 1 from jsonb_array_elements(r -> 'municipios') x where x ? 'redutor') and r2 ->> 'codigo' = '42501',
    'redutor_como_comercial', r2 ->> 'erro');

  -- P3: o titular vê e define o redutor
  r := pg_temp.as_call('sp-tit', 'simulador_entrar', '{"nivel": "TITULAR", "senha": "123456"}');
  r2 := pg_temp.as_call('sp-tit', 'simulador_redutor', jsonb_build_object('municipio_id', v_mun, 'redutor', 0.15));
  r3 := pg_temp.as_call('sp-tit', 'simulador_precos', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P3. Titular: entra com a senha dele, vê o redutor e define 15%', 'ok',
    r ->> 'nivel' = 'TITULAR' and (r2 ->> 'ok')::boolean and r3 ->> 'nivel' = 'TITULAR'
    and (select (x ->> 'redutor')::numeric from jsonb_array_elements(r3 -> 'municipios') x where (x ->> 'id')::int = v_mun) = 0.15,
    'entrada', r, 'redutor', r2);

  -- P4: troca de senha: a atual errada é recusada; depois da troca, a nova abre e a antiga não
  r := pg_temp.as_call('sp-com', 'simulador_trocar_senha', '{"nivel": "COMERCIAL", "atual": "000000", "nova": "abcdef"}');
  r2 := pg_temp.as_call('sp-com', 'simulador_trocar_senha', '{"nivel": "COMERCIAL", "atual": "123456", "nova": "abcdef"}');
  r3 := pg_temp.as_call('sp-com', 'simulador_trocar_senha', '{"nivel": "TITULAR", "atual": "123456", "nova": "zzzzzz"}');
  perform pg_temp.as_call('sp-com', 'simulador_sair', '{}');
  r4 := pg_temp.as_call('sp-com', 'simulador_entrar', '{"nivel": "COMERCIAL", "senha": "123456"}');
  v_out := v_out || jsonb_build_object('passo', 'P4. Troca de senha: confere a atual; a nova abre e a antiga não; comercial não troca a do titular', 'ok',
    r ->> 'codigo' = '28P01' and (r2 ->> 'ok')::boolean and r3 ->> 'codigo' = '42501' and not (r4 ->> 'ok')::boolean
    and (pg_temp.as_call('sp-com', 'simulador_entrar', '{"nivel": "COMERCIAL", "senha": "abcdef"}') ->> 'ok')::boolean,
    'atual_errada', r ->> 'erro', 'titular_pelo_comercial', r3 ->> 'erro');

  -- P5: 5 senhas erradas bloqueiam por 15 minutos (mesmo com a certa)
  for i in 1 .. 5 loop
    perform pg_temp.as_call('sp-bloq', 'simulador_entrar', '{"nivel": "COMERCIAL", "senha": "errada"}');
  end loop;
  r := pg_temp.as_call('sp-bloq', 'simulador_entrar', '{"nivel": "COMERCIAL", "senha": "abcdef"}');
  v_out := v_out || jsonb_build_object('passo', 'P5. Cinco senhas erradas bloqueiam por 15 minutos', 'ok',
    not (r ->> 'ok')::boolean and (r ->> 'bloqueado')::boolean, 'resposta', r);

  -- P6: perfis da prefeitura e visitante
  r2 := pg_temp.as_call('sp-pref', 'simulador_precos', '{}');
  r3 := pg_temp.as_call('sp-sec', 'simulador_entrar', '{"nivel": "COMERCIAL", "senha": "abcdef"}');
  r4 := pg_temp.as_anon('simulador_precos', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P6. Prefeito, Secretaria e visitante não entram, nem com a senha', 'ok',
    r2 ->> 'codigo' = '42501' and r3 ->> 'codigo' = '42501' and r4 ->> 'erro' is not null,
    'prefeito', r2 ->> 'erro', 'secretaria', r3 ->> 'erro', 'visitante', r4 ->> 'erro');

  -- P7: senhas só como hash; sem divisor nem valor de referência no banco; perfil sem dados de pessoas
  v_out := v_out || jsonb_build_object('passo', 'P7. Senhas só como hash bcrypt; sem divisor no banco; Comercial sem dados de pessoas', 'ok',
    not exists (select 1 from iara.sim_acesso where senha_hash not like '$2%' or senha_hash like '%123456%')
    and not exists (select 1 from information_schema.columns where table_schema = 'iara' and table_name like 'sim_%' and column_name ~ 'refer|divisor')
    and exists (select 1 from iara.organizational_roles where code = 'COMERCIAL' and is_persona and scope_type = 'AGGREGATE')
    and not exists (select 1 from iara.role_permissions where role_code = 'COMERCIAL' and permission_code in ('students.read', 'guardians.read', 'kpi.network')));

  -- P8 (086): o comercial recebe só o fator; "Ver todas" e o ajuste do total pedem a senha do titular, sem liberar o titular
  perform iara.session_create('COMERCIAL', null, 'sp-aj', 'teste');
  -- a senha do comercial foi trocada para abcdef no P4 (a do titular continua 123456)
  perform pg_temp.as_call('sp-aj', 'simulador_entrar', '{"nivel": "COMERCIAL", "senha": "abcdef"}');
  r := pg_temp.as_call('sp-aj', 'simulador_ver_todas', '{"senha": "errada"}');
  r2 := pg_temp.as_call('sp-aj', 'simulador_ver_todas', '{"senha": "123456"}');
  r3 := pg_temp.as_call('sp-aj', 'simulador_ajuste', jsonb_build_object('senha', 'errada', 'municipio_id', v_mun, 'percentual', 10));
  r4 := pg_temp.as_call('sp-aj', 'simulador_ajuste', jsonb_build_object('senha', '123456', 'municipio_id', v_mun, 'percentual', 10));
  v_out := v_out || jsonb_build_object('passo', 'P8. Ver todas e ajuste do total: só com a senha do titular, sem liberar o titular', 'ok',
    not (r ->> 'ok')::boolean and (r2 ->> 'ok')::boolean and not (r3 ->> 'ok')::boolean and (r4 ->> 'ok')::boolean
    and (pg_temp.as_call('sp-aj', 'simulador_acesso', '{}') ->> 'nivel') = 'COMERCIAL',
    'ver_errada', r, 'ajuste_errado', r3);
  r := pg_temp.as_call('sp-aj', 'simulador_precos', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P9. Depois do ajuste de 10%, o comercial recebe fator 0,9 e nenhum redutor', 'ok',
    (select (x ->> 'fator')::numeric from jsonb_array_elements(r -> 'municipios') x where (x ->> 'id')::int = v_mun) = 0.9
    and not exists (select 1 from jsonb_array_elements(r -> 'municipios') x where x ? 'redutor'),
    'fator', (select x ->> 'fator' from jsonb_array_elements(r -> 'municipios') x where (x ->> 'id')::int = v_mun));

  raise exception 'RESULTADO: %', v_out;
end $$;
