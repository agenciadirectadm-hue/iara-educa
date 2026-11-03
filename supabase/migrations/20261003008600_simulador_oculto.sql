-- IARA Educa — 086 · Simulador: prefeituras ocultas e ajuste do total sem aparecer
-- Para o comercial, a tela mostra só a prefeitura aberta; a lista de todas abre com a senha do titular. O titular também
-- ajusta o total de uma prefeitura (desconto percentual) sem que isso apareça: clicando no total, informa a senha e o
-- percentual; a partir daí os preços daquela prefeitura já saem reduzidos, linha por linha, sem rótulo de desconto.
-- O comercial recebe só o fator de cada prefeitura (1 − redutor), nunca o redutor. Senha conferida no banco, com o mesmo
-- limite de 5 erros em 15 minutos; nada disso libera o acesso do titular na tela.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

-- confere a senha do titular sem liberar o acesso dele; erro conta tentativa (sem levantar exceção, para a tentativa ficar)
create or replace function iara.sim_confere_titular(p_senha text) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_user uuid := iara.current_user_id();
  v_hash text;
begin
  if (select count(*) from iara.sim_tentativas where user_id = v_user and em > now() - interval '15 minutes') >= 5 then
    return jsonb_build_object('ok', false, 'erro', 'Muitas senhas erradas. Tente de novo em 15 minutos.', 'bloqueado', true);
  end if;
  select senha_hash into v_hash from iara.sim_acesso where nivel = 'TITULAR';
  if v_hash is null or extensions.crypt(coalesce(p_senha, ''), v_hash) <> v_hash then
    insert into iara.sim_tentativas (user_id) values (v_user);
    perform iara.audit_event('SIM_SENHA_ERRADA', 'simulador', 'TITULAR', null, 'Senha errada no simulador de preços (confirmação do titular).');
    return jsonb_build_object('ok', false, 'erro', 'Senha incorreta.',
      'restantes', greatest(0, 5 - (select count(*) from iara.sim_tentativas where user_id = v_user and em > now() - interval '15 minutes')));
  end if;
  delete from iara.sim_tentativas where user_id = v_user;
  return jsonb_build_object('ok', true);
end $$;

-- primeiro passo do ajuste do total: confere a senha do titular antes de abrir a caixa do percentual
create or replace function api.simulador_conferir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('precos.simular');
  if iara.sim_nivel() is null then
    raise exception 'Simulador bloqueado: entre com a senha.' using errcode = '42501';
  end if;
  return iara.sim_confere_titular(p ->> 'senha');
end $$;

-- "Ver todas": a senha do titular mostra a lista de prefeituras
create or replace function api.simulador_ver_todas(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r jsonb;
begin
  perform iara.require_perm('precos.simular');
  if iara.sim_nivel() is null then
    raise exception 'Simulador bloqueado: entre com a senha.' using errcode = '42501';
  end if;
  r := iara.sim_confere_titular(p ->> 'senha');
  if (r ->> 'ok')::boolean then
    perform iara.audit_event('SIM_VER_TODAS', 'simulador', null, null, 'Lista de prefeituras aberta no simulador.');
  end if;
  return r;
end $$;

-- ajuste do total (desconto percentual) de uma prefeitura, com a senha do titular. p: senha, municipio_id, percentual (0 a 90)
create or replace function api.simulador_ajuste(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id smallint := (p ->> 'municipio_id')::smallint;
  v_red numeric := round(coalesce((p ->> 'percentual')::numeric, 0) / 100, 4);
  v_antes numeric;
  r jsonb;
begin
  perform iara.require_perm('precos.simular');
  if iara.sim_nivel() is null then
    raise exception 'Simulador bloqueado: entre com a senha.' using errcode = '42501';
  end if;
  if v_red < 0 or v_red > 0.9 then
    raise exception 'Percentual entre 0 e 90.' using errcode = '22023';
  end if;
  r := iara.sim_confere_titular(p ->> 'senha');
  if not (r ->> 'ok')::boolean then
    return r;
  end if;
  select redutor into v_antes from iara.sim_municipios where id = v_id;
  if not found then
    raise exception 'Prefeitura não encontrada.' using errcode = 'P0002';
  end if;
  update iara.sim_municipios set redutor = v_red where id = v_id;
  perform iara.audit_event('SIM_REDUTOR', 'simulador', v_id::text, null, 'Ajuste do total de uma prefeitura no simulador.',
    jsonb_build_object('redutor', v_red), jsonb_build_object('redutor', v_antes));
  return jsonb_build_object('ok', true);
end $$;

-- os dados: o comercial recebe o fator de cada prefeitura (1 − redutor), nunca o redutor; o titular recebe os dois
create or replace function api.simulador_precos(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_nivel text;
begin
  perform iara.require_perm('precos.simular');
  v_nivel := iara.sim_nivel();
  if v_nivel is null then
    raise exception 'Simulador bloqueado: entre com a senha.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'nivel', v_nivel,
    'agentes', (select coalesce(jsonb_agg(to_jsonb(a) order by a.num), '[]') from iara.sim_agentes a),
    'municipios', (select coalesce(jsonb_agg(
                     (case when v_nivel = 'TITULAR' then to_jsonb(m) else to_jsonb(m) - 'redutor' end) || jsonb_build_object('fator', 1 - m.redutor)
                     order by m.id), '[]')
                   from iara.sim_municipios m),
    'parametros', (select coalesce(jsonb_object_agg(chave, valor), '{}') from iara.sim_parametros),
    'fonte', 'Calculadora IARA Educa (preços finais). Volumes: Censo Escolar 2025 (INEP), rede municipal. Custos adicionais: tarifas da Meta, da Anthropic e da Groq.');
end $$;

revoke all on function iara.sim_confere_titular(text) from public;

commit;
