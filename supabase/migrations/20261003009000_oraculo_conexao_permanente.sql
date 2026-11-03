-- IARA Educa — 090 · Oráculo do Prefeito: conexão permanente por MCP
-- O Prefeito cria, na página do Oráculo, uma chave de conexão para o assistente que usa (Claude no celular, no computador ou
-- no navegador). A chave não expira com a sessão: vale até ser revogada. Ela só abre as ferramentas do Oráculo (números
-- agregados, só leitura) e aparece uma única vez; o IARA guarda só o hash (SHA-256). Cada chave tem um usuário técnico com o
-- perfil do Prefeito, para que as permissões e a auditoria continuem as do banco; cada uso é contado.
-- No Claude: conector personalizado "sem login" com o endereço que leva a chave, ou o cabeçalho Authorization: Bearer.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

create table if not exists iara.oraculo_chaves (
  id uuid primary key default gen_random_uuid(),
  rotulo text not null,
  prefixo text not null,                    -- começo da chave, para reconhecer na lista
  chave_hash text not null unique,          -- SHA-256 (hex) da chave; a chave em si não fica guardada
  user_id uuid not null references iara.app_users(id) on delete cascade,  -- usuário técnico com o perfil do Prefeito
  criada_por uuid references iara.app_users(id) on delete set null,
  criada_por_label text,
  criada_em timestamptz not null default now(),
  ultimo_uso_em timestamptz,
  usos integer not null default 0,
  revogada_em timestamptz,
  is_demo boolean not null default true
);
create index if not exists oraculo_chaves_ativas_idx on iara.oraculo_chaves (criada_em desc) where revogada_em is null;
alter table iara.oraculo_chaves enable row level security;

-- p: rotulo. Devolve a chave uma única vez.
create or replace function api.oraculo_conexao_criar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, extensions, public
as $$
declare
  v_rotulo text := left(btrim(coalesce(p ->> 'rotulo', '')), 60);
  v_chave text := 'iara_mcp_' || translate(encode(extensions.gen_random_bytes(30), 'base64'), '+/', '-_');
  v_user uuid := gen_random_uuid();
  v_id uuid;
begin
  perform iara.require_perm('oraculo.prefeito');
  if length(v_rotulo) < 3 then
    raise exception 'Dê um nome à conexão (ex.: Claude no celular).' using errcode = '22023';
  end if;
  if (select count(*) from iara.oraculo_chaves where revogada_em is null) >= 5 then
    raise exception 'Já há 5 conexões ativas. Revogue uma antes de criar outra.' using errcode = '22023';
  end if;
  insert into iara.app_users (id, tenant_id, display_name, role_code, auth_provider, is_demo, last_seen_at)
  values (v_user, 1, 'Oráculo por MCP · ' || v_rotulo, 'PREFEITO', 'MCP', iara.demo_mode(), now());
  insert into iara.oraculo_chaves (rotulo, prefixo, chave_hash, user_id, criada_por, criada_por_label, is_demo)
  values (v_rotulo, left(v_chave, 13), encode(extensions.digest(v_chave, 'sha256'), 'hex'), v_user, iara.current_user_id(), iara.my_label(), iara.demo_mode())
  returning id into v_id;
  perform iara.audit_event('ORACULO_CONEXAO_CRIADA', 'oraculo_chave', v_id::text, null, 'Conexão permanente do Oráculo criada: ' || v_rotulo);
  return jsonb_build_object('id', v_id, 'rotulo', v_rotulo, 'chave', v_chave, 'prefixo', left(v_chave, 13));
end $$;

create or replace function api.oraculo_conexoes(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('oraculo.prefeito');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'rotulo', rotulo, 'prefixo', prefixo, 'criada_em', criada_em,
                    'criada_por', criada_por_label, 'ultimo_uso_em', ultimo_uso_em, 'usos', usos, 'revogada_em', revogada_em)
                    order by revogada_em nulls first, criada_em desc), '[]')
          from (select * from iara.oraculo_chaves where revogada_em is null or revogada_em > now() - interval '30 days'
                order by criada_em desc limit 20) k);
end $$;

create or replace function api.oraculo_conexao_revogar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  k iara.oraculo_chaves;
begin
  perform iara.require_perm('oraculo.prefeito');
  update iara.oraculo_chaves set revogada_em = now() where id = nullif(p ->> 'id', '')::uuid and revogada_em is null returning * into k;
  if k.id is null then raise exception 'Conexão não encontrada ou já revogada.' using errcode = 'P0002'; end if;
  perform iara.audit_event('ORACULO_CONEXAO_REVOGADA', 'oraculo_chave', k.id::text, null, 'Conexão permanente do Oráculo revogada: ' || k.rotulo);
  return jsonb_build_object('ok', true);
end $$;

-- gateway: chave (hash) → usuário técnico, contando o uso; nulo se não existe ou foi revogada
create or replace function iara.oraculo_chave_resolver(p_hash text) returns uuid
language sql security definer set search_path = iara, public
as $$
  update iara.oraculo_chaves set ultimo_uso_em = now(), usos = usos + 1
  where chave_hash = p_hash and revogada_em is null
  returning user_id
$$;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('oraculo_chaves', 'chave_hash', 'INTERNO', 'credencial', 'conexão permanente do assistente do Prefeito ao Oráculo (MCP)', 'só o hash SHA-256; revogável; só ferramentas de números agregados')
on conflict (tabela, coluna) do nothing;

revoke all on function iara.oraculo_chave_resolver(text) from public;

commit;
