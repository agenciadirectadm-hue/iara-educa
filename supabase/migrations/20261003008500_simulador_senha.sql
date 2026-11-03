-- IARA Educa — 085 · Simulador de preços com senha e redutor só no acesso do titular
-- O perfil Comercial aparece na entrada da demonstração, mas o simulador só abre com senha: sem ela o banco não entrega
-- nenhum preço. Dois acessos, cada um com a sua senha (as duas começam em 123456, para trocar depois, pelo próprio simulador):
--  · Comercial: preços cheios, sem nenhuma menção a desconto (o banco nem envia o redutor);
--  · Titular: vê e define o redutor de cada prefeitura e o preço com desconto; troca as duas senhas.
-- Senhas guardadas só como hash (bcrypt), liberação por 8 horas ligada à pessoa que entrou, bloqueio de 15 minutos depois de
-- 5 senhas erradas, e auditoria de entradas, trocas de senha e redutores (sem a senha).
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

create table if not exists iara.sim_acesso (
  nivel text primary key check (nivel in ('COMERCIAL', 'TITULAR')),
  senha_hash text not null,
  alterada_em timestamptz not null default now(),
  alterada_por text
);
create table if not exists iara.sim_liberacoes (
  user_id uuid not null references iara.app_users(id) on delete cascade,
  nivel text not null check (nivel in ('COMERCIAL', 'TITULAR')),
  expira_em timestamptz not null,
  primary key (user_id, nivel)
);
create table if not exists iara.sim_tentativas (
  id bigserial primary key,
  user_id uuid not null references iara.app_users(id) on delete cascade,
  em timestamptz not null default now()
);
create index if not exists sim_tentativas_user_idx on iara.sim_tentativas (user_id, em desc);
alter table iara.sim_acesso enable row level security;
alter table iara.sim_liberacoes enable row level security;
alter table iara.sim_tentativas enable row level security;

-- senha genérica inicial (só se ainda não houver; trocar pelo simulador)
insert into iara.sim_acesso (nivel, senha_hash, alterada_por) values
  ('COMERCIAL', extensions.crypt('123456', extensions.gen_salt('bf')), 'senha inicial'),
  ('TITULAR', extensions.crypt('123456', extensions.gen_salt('bf')), 'senha inicial')
on conflict (nivel) do nothing;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('sim_acesso', 'senha_hash', 'SENSIVEL', 'credencial', 'senha do simulador de preços', 'só o hash (bcrypt); nunca sai do banco')
on conflict (tabela, coluna) do nothing;

-- nível liberado para quem está usando (o maior: titular vale também como comercial)
create or replace function iara.sim_nivel() returns text
language sql stable security definer set search_path = iara, public
as $$
  select case when bool_or(nivel = 'TITULAR') then 'TITULAR' when count(*) > 0 then 'COMERCIAL' end
  from iara.sim_liberacoes where user_id = iara.current_user_id() and expira_em > now()
$$;

create or replace function api.simulador_acesso(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('precos.simular');
  return jsonb_build_object('nivel', iara.sim_nivel(),
    'expira_em', (select max(expira_em) from iara.sim_liberacoes where user_id = iara.current_user_id() and expira_em > now()));
end $$;

-- p: nivel ('COMERCIAL' | 'TITULAR'), senha
create or replace function api.simulador_entrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_user uuid := iara.current_user_id();
  v_nivel text := coalesce(nullif(p ->> 'nivel', ''), 'COMERCIAL');
  v_hash text;
begin
  perform iara.require_perm('precos.simular');
  if v_nivel not in ('COMERCIAL', 'TITULAR') then
    raise exception 'Acesso inválido.' using errcode = '22023';
  end if;
  -- senha errada não levanta erro: a tentativa precisa ficar gravada para o bloqueio (um erro desfaria a gravação)
  if (select count(*) from iara.sim_tentativas where user_id = v_user and em > now() - interval '15 minutes') >= 5 then
    return jsonb_build_object('ok', false, 'erro', 'Muitas senhas erradas. Tente de novo em 15 minutos.', 'bloqueado', true);
  end if;
  select senha_hash into v_hash from iara.sim_acesso where nivel = v_nivel;
  if v_hash is null or extensions.crypt(coalesce(p ->> 'senha', ''), v_hash) <> v_hash then
    insert into iara.sim_tentativas (user_id) values (v_user);
    perform iara.audit_event('SIM_SENHA_ERRADA', 'simulador', v_nivel, null, 'Senha errada no simulador de preços.');
    return jsonb_build_object('ok', false, 'erro', 'Senha incorreta.',
      'restantes', greatest(0, 5 - (select count(*) from iara.sim_tentativas where user_id = v_user and em > now() - interval '15 minutes')));
  end if;
  delete from iara.sim_tentativas where user_id = v_user;
  insert into iara.sim_liberacoes (user_id, nivel, expira_em) values (v_user, v_nivel, now() + interval '8 hours')
  on conflict (user_id, nivel) do update set expira_em = excluded.expira_em;
  perform iara.audit_event('SIM_ENTRADA', 'simulador', v_nivel, null, 'Entrada no simulador de preços (' || lower(v_nivel) || ').');
  return jsonb_build_object('ok', true, 'nivel', iara.sim_nivel());
end $$;

create or replace function api.simulador_sair(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  delete from iara.sim_liberacoes where user_id = iara.current_user_id();
  return jsonb_build_object('nivel', null);
end $$;

-- p: nivel (a senha a trocar), atual (a senha atual daquele acesso), nova (6 ou mais caracteres)
create or replace function api.simulador_trocar_senha(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_nivel text := coalesce(nullif(p ->> 'nivel', ''), 'COMERCIAL');
  v_nova text := coalesce(p ->> 'nova', '');
  v_hash text;
begin
  perform iara.require_perm('precos.simular');
  if iara.sim_nivel() is null then
    raise exception 'Simulador bloqueado: entre com a senha.' using errcode = '42501';
  end if;
  if v_nivel = 'TITULAR' and iara.sim_nivel() <> 'TITULAR' then
    raise exception 'Só o titular troca a senha do titular.' using errcode = '42501';
  end if;
  if length(v_nova) < 6 then
    raise exception 'A senha nova precisa de 6 ou mais caracteres.' using errcode = '22023';
  end if;
  select senha_hash into v_hash from iara.sim_acesso where nivel = v_nivel;
  if v_hash is null or extensions.crypt(coalesce(p ->> 'atual', ''), v_hash) <> v_hash then
    raise exception 'A senha atual não confere.' using errcode = '28P01';
  end if;
  update iara.sim_acesso set senha_hash = extensions.crypt(v_nova, extensions.gen_salt('bf')), alterada_em = now(), alterada_por = iara.my_label()
  where nivel = v_nivel;
  perform iara.audit_event('SIM_SENHA_TROCADA', 'simulador', v_nivel, null, 'Senha do simulador de preços trocada (' || lower(v_nivel) || ').');
  return jsonb_build_object('ok', true);
end $$;

-- p: municipio_id, redutor (0 a 0,9) — só o titular
create or replace function api.simulador_redutor(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id smallint := (p ->> 'municipio_id')::smallint;
  v_red numeric := round(coalesce((p ->> 'redutor')::numeric, 0), 4);
  v_antes numeric;
begin
  perform iara.require_perm('precos.simular');
  if coalesce(iara.sim_nivel(), '') <> 'TITULAR' then
    raise exception 'Só o titular define o redutor.' using errcode = '42501';
  end if;
  if v_red < 0 or v_red > 0.9 then
    raise exception 'Redutor entre 0%% e 90%%.' using errcode = '22023';
  end if;
  select redutor into v_antes from iara.sim_municipios where id = v_id;
  if not found then
    raise exception 'Prefeitura não encontrada.' using errcode = 'P0002';
  end if;
  update iara.sim_municipios set redutor = v_red where id = v_id;
  perform iara.audit_event('SIM_REDUTOR', 'simulador', v_id::text, null, 'Redutor do simulador alterado.',
    jsonb_build_object('redutor', v_red), jsonb_build_object('redutor', v_antes));
  return jsonb_build_object('ok', true, 'redutor', v_red);
end $$;

-- os dados do simulador: só com o simulador liberado; o redutor só para o titular
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
    'municipios', (select coalesce(jsonb_agg(case when v_nivel = 'TITULAR' then to_jsonb(m) else to_jsonb(m) - 'redutor' end order by m.id), '[]')
                   from iara.sim_municipios m),
    'parametros', (select coalesce(jsonb_object_agg(chave, valor), '{}') from iara.sim_parametros),
    'fonte', 'Calculadora IARA Educa (preços finais). Volumes: Censo Escolar 2025 (INEP), rede municipal. Custos adicionais: tarifas da Meta, da Anthropic e da Groq.');
end $$;

revoke all on function iara.sim_nivel() from public;

commit;
