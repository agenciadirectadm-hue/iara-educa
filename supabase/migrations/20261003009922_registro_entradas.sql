-- IARA Educa — 099.22 · Registro de entradas no portal
-- Cada tentativa da senha de acesso (certa, errada, tentativas demais), cada aparelho barrado sem a senha, cada perfil aberto e o
-- uso do Oráculo pela conexão permanente ficam gravados com data, hora, IP, aparelho e a localização aproximada do IP (cidade,
-- estado, país e provedor), pela base gratuita DB-IP Lite (CC BY 4.0), carregada por scripts/geoip/carregar.mjs. A consulta é
-- feita aqui dentro: o IP de quem entra não sai do IARA.
-- A senha de acesso é a mesma para todos: o registro diz quando, de onde e de que aparelho, não quem.
-- Só o titular vê (a mesma senha do titular do simulador de preços, liberada por 8 horas na sessão).
-- Guardado por 6 meses (Marco Civil da Internet, art. 15: registros de acesso a aplicações). Fora do Oráculo.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

-- 1. Localização aproximada por IP -----------------------------------------------------------------------------------------------
create table if not exists iara.geoip_local (
  ip_ini inet primary key,
  ip_fim inet not null,
  pais text not null,   -- código ISO (BR, US...)
  estado text,          -- sigla da UF no Brasil; fora do Brasil, vazio (só o país)
  cidade text
);
create table if not exists iara.geoip_provedor (
  ip_ini inet primary key,
  ip_fim inet not null,
  asn integer,
  provedor text
);
-- o script enche estas duas e troca tudo de uma vez (iara.geoip_trocar), sem deixar a consulta vazia no meio da carga
create unlogged table if not exists iara.geoip_local_carga (like iara.geoip_local);
create unlogged table if not exists iara.geoip_provedor_carga (like iara.geoip_provedor);
create table if not exists iara.geoip_versao (
  id smallint primary key default 1 check (id = 1),
  fonte text not null,
  versao text not null,
  faixas_local integer not null,
  faixas_provedor integer not null,
  carregada_em timestamptz not null default now()
);
alter table iara.geoip_local enable row level security;
alter table iara.geoip_provedor enable row level security;
alter table iara.geoip_local_carga enable row level security;
alter table iara.geoip_provedor_carga enable row level security;
alter table iara.geoip_versao enable row level security;

-- troca a base pela carga nova; recusa carga pela metade
create or replace function iara.geoip_trocar(p_fonte text, p_versao text) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  n_l integer := (select count(*) from iara.geoip_local_carga);
  n_p integer := (select count(*) from iara.geoip_provedor_carga);
begin
  if n_l < 100000 or n_p < 100000 then
    raise exception 'Carga incompleta (% faixas de local e % de provedor): a base anterior foi mantida.', n_l, n_p using errcode = '22023';
  end if;
  truncate iara.geoip_local;
  insert into iara.geoip_local select distinct on (ip_ini) * from iara.geoip_local_carga order by ip_ini;
  truncate iara.geoip_provedor;
  insert into iara.geoip_provedor select distinct on (ip_ini) * from iara.geoip_provedor_carga order by ip_ini;
  truncate iara.geoip_local_carga, iara.geoip_provedor_carga;
  insert into iara.geoip_versao (id, fonte, versao, faixas_local, faixas_provedor, carregada_em)
  values (1, p_fonte, p_versao, (select count(*) from iara.geoip_local), (select count(*) from iara.geoip_provedor), now())
  on conflict (id) do update set fonte = excluded.fonte, versao = excluded.versao, faixas_local = excluded.faixas_local,
    faixas_provedor = excluded.faixas_provedor, carregada_em = excluded.carregada_em;
  return (select to_jsonb(v) from iara.geoip_versao v where id = 1);
end $$;
revoke all on function iara.geoip_trocar(text, text) from public;

-- IP → país, estado, cidade e provedor (a faixa com o maior começo que não passa do IP, se o IP estiver dentro dela)
create or replace function iara.geoip(p_ip text) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v inet;
  l iara.geoip_local;
  pr iara.geoip_provedor;
begin
  begin
    v := host(nullif(btrim(p_ip), '')::inet)::inet;
  exception when others then
    return '{}'::jsonb;
  end;
  if v is null then return '{}'::jsonb; end if;
  select * into l from iara.geoip_local where ip_ini <= v order by ip_ini desc limit 1;
  if l.ip_ini is not null and (family(l.ip_ini) <> family(v) or l.ip_fim < v) then l := null; end if;
  select * into pr from iara.geoip_provedor where ip_ini <= v order by ip_ini desc limit 1;
  if pr.ip_ini is not null and (family(pr.ip_ini) <> family(v) or pr.ip_fim < v) then pr := null; end if;
  return jsonb_strip_nulls(jsonb_build_object('pais', l.pais, 'estado', l.estado, 'cidade', l.cidade, 'provedor', pr.provedor));
end $$;
revoke all on function iara.geoip(text) from public;

-- 2. Registro de entradas --------------------------------------------------------------------------------------------------------
create table if not exists iara.acesso_entradas (
  id bigserial primary key,
  em timestamptz not null default now(),
  ultimo_em timestamptz not null default now(),   -- linhas agrupadas (Oráculo por hora; barrados e excessos por 10 min)
  evento text not null check (evento in ('SENHA_CERTA', 'SENHA_ERRADA', 'TENTATIVAS_DEMAIS', 'BARRADO', 'PERFIL_ABERTO', 'ORACULO_MCP')),
  n integer not null default 1,
  passe text,      -- parte aleatória do passe da aba (liga a senha aos perfis abertos depois); não abre nada sozinha
  perfil text,
  detalhe text,
  ip text,
  pais text,
  estado text,
  cidade text,
  provedor text,
  aparelho text
);
create index if not exists acesso_entradas_em_idx on iara.acesso_entradas (em desc);
create index if not exists acesso_entradas_passe_idx on iara.acesso_entradas (passe) where passe is not null;
alter table iara.acesso_entradas enable row level security;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('acesso_entradas', 'ip', 'PESSOAL', 'registro técnico de acesso', 'segurança do portal; registro de acesso exigido pelo Marco Civil (6 meses)', 'só o titular vê; fora do Oráculo; apagado após 6 meses'),
  ('acesso_entradas', 'aparelho', 'PESSOAL', 'registro técnico de acesso', 'segurança do portal: aparelho e navegador de quem entrou', 'só o titular vê; fora do Oráculo; apagado após 6 meses'),
  ('acesso_entradas', 'cidade', 'PESSOAL', 'localização aproximada pelo IP', 'segurança do portal: de onde o portal foi aberto', 'só o titular vê; fora do Oráculo; apagado após 6 meses'),
  ('acesso_entradas', 'estado', 'INTERNO', 'localização aproximada pelo IP', 'segurança do portal', 'só o titular vê'),
  ('acesso_entradas', 'pais', 'INTERNO', 'localização aproximada pelo IP', 'segurança do portal', 'só o titular vê'),
  ('acesso_entradas', 'provedor', 'INTERNO', 'registro técnico de acesso', 'segurança do portal: provedor de internet de quem entrou', 'só o titular vê'),
  ('acesso_entradas', 'passe', 'INTERNO', 'credencial', 'ligar a senha aos perfis abertos na mesma aba', 'só a parte aleatória, sem a assinatura: não abre o portal'),
  ('acesso_entradas', 'detalhe', 'INTERNO', 'registro técnico de acesso', 'unidade do perfil aberto ou nome da conexão do Oráculo', 'só o titular vê'),
  ('geoip_local', 'cidade', 'PUBLICO', 'base pública de localização por IP', 'localizar o IP no registro de entradas', 'DB-IP Lite, CC BY 4.0'),
  ('geoip_provedor', 'provedor', 'PUBLICO', 'base pública de provedores por IP', 'provedor do IP no registro de entradas', 'DB-IP Lite, CC BY 4.0')
on conflict (tabela, coluna) do nothing;

-- gateway: grava um evento já com a localização do IP. Agrupa o que se repete, para não encher a tabela.
create or replace function iara.acesso_registrar(p jsonb) returns void
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_evento text := p ->> 'evento';
  v_ip text := left(nullif(btrim(p ->> 'ip'), ''), 64);
  v_perfil text := left(nullif(p ->> 'perfil', ''), 60);
  v_detalhe text := left(nullif(p ->> 'detalhe', ''), 200);
  v_id bigint;
  g jsonb;
begin
  if v_ip = 'desconhecido' then v_ip := null; end if;
  if v_evento = 'PERFIL_ABERTO' then
    v_perfil := coalesce((select short_name from iara.organizational_roles where code = v_perfil), v_perfil);
  elsif v_evento = 'ORACULO_MCP' then
    v_detalhe := coalesce((select rotulo from iara.oraculo_chaves where user_id = nullif(p ->> 'user_id', '')::uuid), 'Conexão do Oráculo');
    -- uma linha por conexão e por hora, com a contagem de consultas
    update iara.acesso_entradas set n = n + 1, ultimo_em = now()
    where id = (select id from iara.acesso_entradas where evento = 'ORACULO_MCP' and detalhe = v_detalhe and em >= date_trunc('hour', now())
                order by id desc limit 1)
    returning id into v_id;
  elsif v_evento in ('TENTATIVAS_DEMAIS', 'BARRADO') then
    -- o mesmo endereço insistindo em 10 minutos soma na mesma linha
    update iara.acesso_entradas set n = n + 1, ultimo_em = now()
    where id = (select id from iara.acesso_entradas where evento = v_evento and ip is not distinct from v_ip and ultimo_em > now() - interval '10 minutes'
                order by id desc limit 1)
    returning id into v_id;
  end if;
  if v_id is not null then return; end if;
  g := iara.geoip(v_ip);
  insert into iara.acesso_entradas (evento, passe, perfil, detalhe, ip, pais, estado, cidade, provedor, aparelho)
  values (v_evento, left(nullif(p ->> 'passe', ''), 40), v_perfil, v_detalhe, v_ip, g ->> 'pais', g ->> 'estado', g ->> 'cidade', g ->> 'provedor',
          left(nullif(p ->> 'aparelho', ''), 300));
  if random() < 0.02 then
    delete from iara.acesso_entradas where em < now() - interval '6 months';
  end if;
end $$;
revoke all on function iara.acesso_registrar(jsonb) from public;

-- 3. Consulta do titular ---------------------------------------------------------------------------------------------------------
-- p: senha (a do titular do simulador). Libera o registro nesta sessão por 8 horas; 5 erros em 15 minutos bloqueiam.
create or replace function api.acesso_entradas_entrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_user uuid := iara.current_user_id();
  v_hash text;
begin
  if v_user is null then
    raise exception 'Escolha um perfil antes de abrir o registro de entradas.' using errcode = '42501';
  end if;
  -- senha errada não levanta erro: a tentativa precisa ficar gravada para o bloqueio (um erro desfaria a gravação)
  if (select count(*) from iara.sim_tentativas where user_id = v_user and em > now() - interval '15 minutes') >= 5 then
    return jsonb_build_object('ok', false, 'erro', 'Muitas senhas erradas. Tente de novo em 15 minutos.', 'bloqueado', true);
  end if;
  select senha_hash into v_hash from iara.sim_acesso where nivel = 'TITULAR';
  if v_hash is null or extensions.crypt(coalesce(p ->> 'senha', ''), v_hash) <> v_hash then
    insert into iara.sim_tentativas (user_id) values (v_user);
    perform iara.audit_event('ENTRADAS_SENHA_ERRADA', 'acesso_entradas', null, null, 'Senha do titular errada no registro de entradas no portal.');
    return jsonb_build_object('ok', false, 'erro', 'Senha incorreta.',
      'restantes', greatest(0, 5 - (select count(*) from iara.sim_tentativas where user_id = v_user and em > now() - interval '15 minutes')));
  end if;
  delete from iara.sim_tentativas where user_id = v_user;
  insert into iara.sim_liberacoes (user_id, nivel, expira_em) values (v_user, 'TITULAR', now() + interval '8 hours')
  on conflict (user_id, nivel) do update set expira_em = excluded.expira_em;
  perform iara.audit_event('ENTRADAS_CONSULTA', 'acesso_entradas', null, null, 'O titular abriu o registro de entradas no portal.');
  return jsonb_build_object('ok', true);
end $$;

create or replace function api.acesso_entradas_sair(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  delete from iara.sim_liberacoes where user_id = iara.current_user_id();
  return jsonb_build_object('ok', true);
end $$;

-- p: dias (1 a 183; padrão 7). Uma linha por registro; o perfil aberto depois da senha vai junto da linha da senha.
create or replace function api.acesso_entradas(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_dias integer := least(greatest(coalesce(nullif(p ->> 'dias', '')::int, 7), 1), 183);
  v_desde timestamptz := now() - make_interval(days => v_dias);
begin
  if coalesce(iara.sim_nivel(), '') <> 'TITULAR' then
    raise exception 'Só o titular vê as entradas no portal: entre com a senha do titular.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'dias', v_dias,
    'resumo', (select coalesce(jsonb_object_agg(evento, n), '{}'::jsonb) from (
       select evento, sum(n) n from iara.acesso_entradas where em >= v_desde group by 1) z),
    'itens', (select coalesce(jsonb_agg(to_jsonb(z) order by z.em desc), '[]'::jsonb) from (
       select e.id, e.em, e.ultimo_em, e.evento, e.n, e.perfil, e.detalhe, e.ip, e.pais, e.estado, e.cidade, e.provedor, e.aparelho,
              case when e.evento = 'SENHA_CERTA' and e.passe is not null then
                (select jsonb_agg(distinct x.perfil) from iara.acesso_entradas x where x.passe = e.passe and x.evento = 'PERFIL_ABERTO') end as perfis
       from iara.acesso_entradas e
       where e.em >= v_desde
         and not (e.evento = 'PERFIL_ABERTO' and e.passe is not null
                  and exists (select 1 from iara.acesso_entradas s where s.passe = e.passe and s.evento = 'SENHA_CERTA'))
       order by e.em desc
       limit 500) z),
    'guardado_desde', (select min(em) from iara.acesso_entradas),
    'base_local', (select jsonb_build_object('fonte', fonte, 'versao', versao, 'carregada_em', carregada_em) from iara.geoip_versao where id = 1)
  );
end $$;

-- 4. Fora do Oráculo: o registro tem IP e aparelho; a base de localização não é assunto da educação ---------------------------
create or replace function iara.oraculo_base_fora() returns text[]
language sql immutable
as $$ select array[
  -- saúde, deficiência, laudos, proteção da criança, sigilo profissional
  'student_sensitive', 'aluno_restricoes', 'antropometria', 'aee_atendimentos', 'aee_planos', 'mediacoes', 'apoio_casos', 'apoio_registros',
  'encaminhamentos', 'guarda_restricoes', 'frequencia_afastamentos', 'reunioes_responsavel', 'reuniao_eventos', 'reuniao_destinos',
  'reuniao_envios_orgaos', 'household_members',
  -- conversas e mensagens com as famílias
  'messages', 'conversations', 'notifications', 'handoff_tasks', 'tool_executions', 'case_events',
  'whatsapp_avisos_bloqueio', 'whatsapp_channels', 'whatsapp_contacts', 'whatsapp_inbound', 'whatsapp_outbox',
  -- credenciais, códigos e acessos
  'app_sessions', 'familia_codigos', 'familia_qr', 'familia_trocas_numero', 'familia_vinculos', 'uk_codigos', 'declaracoes',
  'ponto_credenciais', 'ponto_desafios', 'oraculo_chaves', 'sim_acesso', 'sim_liberacoes', 'sim_tentativas', 'suporte_anydesk',
  'acesso_entradas',
  -- rastros técnicos e configuração interna
  'audit_log', 'audit_chain_head', 'gestao_hist', 'eventos_seguranca', 'limites_taxa', 'arquivos', 'arquivos_descartar', 'import_batches',
  'rotas_cache', 'pend_estat_cache', 'pend_sinc', 'bolsa_familia_cache', 'feature_flags', 'ponto_demo_estado', 'demo_metrics', 'demo_quadro_extra',
  'oraculo_perguntas', 'oraculo_indicadores', 'oraculo_detalhes', 'oraculo_fatos', 'oraculo_assuntos', 'oraculo_temas', 'oraculo_base_descricoes',
  'sim_agentes', 'sim_municipios', 'sim_parametros', 'classificacao_dados', 'iaraflix_progresso', 'tenants',
  'geoip_local', 'geoip_provedor', 'geoip_local_carga', 'geoip_provedor_carga', 'geoip_versao'
]::text[] $$;

commit;
