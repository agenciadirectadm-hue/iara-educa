-- IARA Educa — 099.14 · IARAFLIX: a área de treinamento com vídeos
-- O treinamento é feito no IARAFLIX, no tempo de cada servidor, no celular ou no computador, e não em turmas no auditório. Cada perfil tem a sua
-- trilha: aulas curtas em vídeo (3 a 5 minutos), a prática no ambiente de treinamento, perguntas no fim e certificado com código de verificação.
-- Segurança:
--   · bucket PRIVADO; só a chave de serviço (no gateway) lê e assina. O gateway confere a sessão e o perfil no banco e devolve um link do vídeo
--     que vale 15 minutos. O vídeo não passa pelo gateway, para o navegador poder avançar e voltar (pedido por trechos);
--   · o vídeo é gravado só no ambiente de treinamento, com dados fictícios; quem publica confirma isso a cada envio, e fica registrado;
--   · no player, marca d'água com o nome de quem assiste e sem botão de baixar (desestimula repassar; não impede gravar a tela);
--   · cada perfil vê só a sua trilha (a gestão vê todas); o envio de vídeo é só da gestão do IARAFLIX.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

-- 1. Bucket privado -------------------------------------------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('iara-treinamento', 'iara-treinamento', false, 52428800, array['video/mp4', 'video/webm', 'text/vtt'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- 2. Permissões ----------------------------------------------------------------------------------------------------------------
insert into iara.permissions (code, description, is_sensitive) values
  ('iaraflix.read', 'IARAFLIX: assistir às aulas da trilha do próprio perfil e emitir o certificado', false),
  ('iaraflix.equipe', 'IARAFLIX: acompanhar quem da equipe já concluiu a trilha', false),
  ('iaraflix.manage', 'IARAFLIX: publicar aulas, vídeos e perguntas e acompanhar a adesão da rede', false)
on conflict (code) do update set description = excluded.description, is_sensitive = excluded.is_sensitive;
insert into iara.role_permissions (role_code, permission_code)
select r, 'iaraflix.read' from unnest(array['SECRETARIO', 'SUPERINTENDENCIA', 'GERENCIA_EI', 'GERENCIA_APOIO', 'INOVACAO', 'ANALISTA_CENTRAL', 'ATENDIMENTO',
  'DIRETOR_UNIDADE', 'SECRETARIA_ESCOLAR', 'PROFESSOR', 'PROFESSOR_AEE', 'APOIO_INTERDISCIPLINAR', 'NUTRICAO', 'TRANSPORTE', 'ALMOXARIFADO', 'MANUTENCAO',
  'PREFEITO', 'CONTROLE_EXTERNO', 'TRIBUNAL_CONTAS', 'CONSELHOS', 'CONSELHO_TUTELAR', 'CAMARA', 'COMERCIAL']) r
union all
select r, 'iaraflix.equipe' from unnest(array['SECRETARIO', 'SUPERINTENDENCIA', 'INOVACAO', 'GERENCIA_EI', 'GERENCIA_APOIO', 'DIRETOR_UNIDADE']) r
union all
select r, 'iaraflix.manage' from unnest(array['SECRETARIO', 'SUPERINTENDENCIA', 'INOVACAO']) r
on conflict do nothing;

-- 3. Tabelas -------------------------------------------------------------------------------------------------------------------
create table if not exists iara.iaraflix_trilhas (
  id text primary key check (id ~ '^[a-z0-9-]{3,40}$'),
  ordem integer not null,
  titulo text not null,
  publico text not null,
  objetivo text not null,
  perfis text[] not null default '{}',        -- perfis para quem a trilha é "a sua"; '*' = todos os servidores
  obrigatoria boolean not null default true,   -- falso: aparece como "também para você"
  staff_roles text[] not null default '{}',    -- funções do cadastro de servidores que contam no painel de adesão
  saber text[] not null default '{}',
  carga_horaria numeric(4, 1) not null check (carga_horaria > 0 and carga_horaria <= 40),
  situacao text not null default 'PUBLICADA' check (situacao in ('RASCUNHO', 'PUBLICADA')),
  atualizado_em timestamptz not null default now(),
  atualizado_por_label text
);
create table if not exists iara.iaraflix_aulas (
  id uuid primary key default gen_random_uuid(),
  trilha_id text not null references iara.iaraflix_trilhas(id) on delete cascade,
  ordem integer not null,
  titulo text not null,
  resumo text,
  pratica text,
  duracao_s integer check (duracao_s is null or duracao_s between 1 and 7200),
  video_caminho text,
  video_mime text check (video_mime is null or video_mime in ('video/mp4', 'video/webm')),
  video_bytes bigint,
  legenda_caminho text,
  video_conferido_por_label text,   -- quem confirmou que o vídeo só mostra dados fictícios
  video_conferido_em timestamptz,
  situacao text not null default 'PUBLICADA' check (situacao in ('RASCUNHO', 'PUBLICADA')),
  atualizado_em timestamptz not null default now(),
  atualizado_por_label text
);
create index if not exists iaraflix_aulas_trilha on iara.iaraflix_aulas (trilha_id, ordem);
create table if not exists iara.iaraflix_perguntas (
  id uuid primary key default gen_random_uuid(),
  trilha_id text not null references iara.iaraflix_trilhas(id) on delete cascade,
  ordem integer not null,
  enunciado text not null,
  opcoes text[] not null check (cardinality(opcoes) between 2 and 5),
  correta smallint not null,
  explicacao text,
  check (correta >= 0 and correta < cardinality(opcoes))
);
create index if not exists iaraflix_perguntas_trilha on iara.iaraflix_perguntas (trilha_id, ordem);
-- onde cada pessoa parou em cada aula
create table if not exists iara.iaraflix_progresso (
  user_id uuid not null references iara.app_users(id) on delete cascade,
  aula_id uuid not null references iara.iaraflix_aulas(id) on delete cascade,
  posicao_s integer not null default 0,
  assistido_s integer not null default 0,
  concluida_em timestamptz,
  atualizado_em timestamptz not null default now(),
  primary key (user_id, aula_id)
);
-- a pessoa na trilha: andamento, perguntas e certificado (o painel de adesão lê daqui)
create table if not exists iara.iaraflix_participacoes (
  id uuid primary key default gen_random_uuid(),
  trilha_id text not null references iara.iaraflix_trilhas(id) on delete cascade,
  user_id uuid references iara.app_users(id) on delete cascade,
  staff_id uuid references iara.staff(id) on delete set null,
  nome text not null,
  role_code text,
  unit_id integer references iara.education_units(id),
  aulas_concluidas integer not null default 0,
  iniciada_em timestamptz not null default now(),
  concluida_em timestamptz,
  tentativas integer not null default 0,
  acertos integer,
  perguntas integer,
  certificado_codigo text unique,
  certificado_hash text,
  is_demo boolean not null default false
);
create unique index if not exists iaraflix_part_usuario on iara.iaraflix_participacoes (trilha_id, user_id) where user_id is not null;
create unique index if not exists iaraflix_part_servidor on iara.iaraflix_participacoes (trilha_id, staff_id) where user_id is null and staff_id is not null;
create index if not exists iaraflix_part_unidade on iara.iaraflix_participacoes (unit_id, trilha_id);

alter table iara.iaraflix_trilhas enable row level security;
alter table iara.iaraflix_aulas enable row level security;
alter table iara.iaraflix_perguntas enable row level security;
alter table iara.iaraflix_progresso enable row level security;
alter table iara.iaraflix_participacoes enable row level security;

-- 4. Quem vê o quê -------------------------------------------------------------------------------------------------------------
create or replace function iara.iaraflix_minha(p_perfis text[]) returns boolean
language sql stable security definer set search_path = iara, public
as $$ select '*' = any (p_perfis) or iara.my_role() = any (p_perfis) $$;

-- a gestão vê todas (inclusive rascunho); o Comercial vê as publicadas (demonstra o produto); os demais, só as do próprio perfil
create or replace function iara.iaraflix_vejo(p_perfis text[], p_situacao text) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select iara.has_perm('iaraflix.read') and (iara.has_perm('iaraflix.manage')
    or (p_situacao = 'PUBLICADA' and (iara.my_role() = 'COMERCIAL' or iara.iaraflix_minha(p_perfis))))
$$;

create or replace function iara.iaraflix_trilha_json(t iara.iaraflix_trilhas, p_user uuid) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  with aulas as (
    select a.id, a.ordem, a.titulo, a.duracao_s, a.video_caminho is not null as tem_video, pr.concluida_em, pr.posicao_s
    from iara.iaraflix_aulas a left join iara.iaraflix_progresso pr on pr.aula_id = a.id and pr.user_id = p_user
    where a.trilha_id = t.id and a.situacao = 'PUBLICADA')
  select jsonb_build_object(
    'id', t.id, 'titulo', t.titulo, 'publico', t.publico, 'objetivo', t.objetivo, 'carga_horaria', t.carga_horaria, 'saber', to_jsonb(t.saber),
    'situacao', t.situacao, 'minha', iara.iaraflix_minha(t.perfis), 'obrigatoria', t.obrigatoria and iara.iaraflix_minha(t.perfis),
    'aulas', (select count(*) from aulas), 'com_video', (select count(*) from aulas where tem_video),
    'concluidas', (select count(*) from aulas where concluida_em is not null),
    'duracao_s', (select coalesce(sum(coalesce(duracao_s, 240)), 0) from aulas),
    'proxima', (select jsonb_build_object('id', id, 'ordem', ordem, 'titulo', titulo, 'posicao_s', coalesce(posicao_s, 0))
                from aulas where concluida_em is null order by ordem limit 1),
    'concluida_em', pa.concluida_em, 'certificado', pa.certificado_codigo)
  from (select 1) x left join iara.iaraflix_participacoes pa on pa.trilha_id = t.id and pa.user_id = p_user
$$;

-- recalcula a participação de quem está assistindo (cria na primeira aula)
create or replace function iara.iaraflix_atualizar_participacao(p_trilha text) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  u iara.app_users;
  v_total integer;
  v_feitas integer;
begin
  select * into u from iara.app_users where id = iara.current_user_id();
  if u.id is null then raise exception 'Sessão inválida.' using errcode = '42501'; end if;
  select count(*), count(pr.concluida_em) into v_total, v_feitas
  from iara.iaraflix_aulas a left join iara.iaraflix_progresso pr on pr.aula_id = a.id and pr.user_id = u.id
  where a.trilha_id = p_trilha and a.situacao = 'PUBLICADA';
  insert into iara.iaraflix_participacoes (trilha_id, user_id, staff_id, nome, role_code, unit_id, aulas_concluidas, is_demo)
  values (p_trilha, u.id, u.staff_id, coalesce(u.display_name, 'Servidor'), u.role_code, u.unit_id, v_feitas, u.auth_provider = 'DEMO')
  on conflict (trilha_id, user_id) where user_id is not null
  do update set aulas_concluidas = excluded.aulas_concluidas, role_code = excluded.role_code, unit_id = excluded.unit_id, staff_id = excluded.staff_id;
  return jsonb_build_object('aulas_concluidas', v_feitas, 'total', v_total, 'pode_avaliar', v_total > 0 and v_feitas = v_total);
end $$;

-- 5. API de quem assiste ---------------------------------------------------------------------------------------------------------
create or replace function api.iaraflix_inicio(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  u iara.app_users;
begin
  perform iara.require_perm('iaraflix.read');
  select * into u from iara.app_users where id = iara.current_user_id();
  return jsonb_build_object(
    'eu', jsonb_build_object('nome', u.display_name, 'perfil', u.role_code, 'unidade', (select short_name from iara.education_units where id = u.unit_id)),
    'gestao', iara.has_perm('iaraflix.manage'), 'equipe', iara.has_perm('iaraflix.equipe'),
    'trilhas', coalesce((
      select jsonb_agg(iara.iaraflix_trilha_json(t, u.id)
                       order by (t.obrigatoria and iara.iaraflix_minha(t.perfis)) desc, iara.iaraflix_minha(t.perfis) desc, t.ordem)
      from iara.iaraflix_trilhas t where iara.iaraflix_vejo(t.perfis, t.situacao)), '[]'::jsonb),
    'continuar', coalesce((
      select jsonb_agg(s.x order by s.em desc) from (
        select pr.atualizado_em em, jsonb_build_object('id', a.id, 'titulo', a.titulo, 'ordem', a.ordem, 'trilha_id', t.id, 'trilha', t.titulo,
                                                      'posicao_s', pr.posicao_s, 'duracao_s', a.duracao_s, 'tem_video', a.video_caminho is not null) x
        from iara.iaraflix_progresso pr
        join iara.iaraflix_aulas a on a.id = pr.aula_id
        join iara.iaraflix_trilhas t on t.id = a.trilha_id
        where pr.user_id = u.id and pr.concluida_em is null and pr.posicao_s > 0 and a.situacao = 'PUBLICADA' and iara.iaraflix_vejo(t.perfis, t.situacao)
        order by pr.atualizado_em desc limit 6) s), '[]'::jsonb));
end $$;

create or replace function api.iaraflix_trilha(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  t iara.iaraflix_trilhas;
  v_user uuid := iara.current_user_id();
  pa iara.iaraflix_participacoes;
  v_total integer;
  v_feitas integer;
begin
  perform iara.require_perm('iaraflix.read');
  select * into t from iara.iaraflix_trilhas where id = p ->> 'id';
  if t.id is null or not iara.iaraflix_vejo(t.perfis, t.situacao) then raise exception 'Trilha não encontrada.' using errcode = 'P0002'; end if;
  select * into pa from iara.iaraflix_participacoes where trilha_id = t.id and user_id = v_user;
  select count(*), count(pr.concluida_em) into v_total, v_feitas
  from iara.iaraflix_aulas a left join iara.iaraflix_progresso pr on pr.aula_id = a.id and pr.user_id = v_user
  where a.trilha_id = t.id and a.situacao = 'PUBLICADA';
  return iara.iaraflix_trilha_json(t, v_user) || jsonb_build_object(
    'lista', coalesce((
      select jsonb_agg(jsonb_build_object('id', a.id, 'ordem', a.ordem, 'titulo', a.titulo, 'resumo', a.resumo, 'pratica', a.pratica,
        'duracao_s', a.duracao_s, 'tem_video', a.video_caminho is not null, 'tem_legenda', a.legenda_caminho is not null,
        'posicao_s', coalesce(pr.posicao_s, 0), 'concluida', pr.concluida_em is not null) order by a.ordem)
      from iara.iaraflix_aulas a left join iara.iaraflix_progresso pr on pr.aula_id = a.id and pr.user_id = v_user
      where a.trilha_id = t.id and a.situacao = 'PUBLICADA'), '[]'::jsonb),
    'perguntas', coalesce((
      select jsonb_agg(jsonb_build_object('id', q.id, 'enunciado', q.enunciado, 'opcoes', to_jsonb(q.opcoes)) order by q.ordem)
      from iara.iaraflix_perguntas q where q.trilha_id = t.id), '[]'::jsonb),
    'pode_avaliar', v_total > 0 and v_feitas = v_total,
    'participacao', case when pa.id is null then null else jsonb_build_object(
      'nome', pa.nome, 'aulas_concluidas', pa.aulas_concluidas, 'concluida_em', pa.concluida_em, 'tentativas', pa.tentativas,
      'acertos', pa.acertos, 'perguntas', pa.perguntas, 'certificado', pa.certificado_codigo, 'hash', left(pa.certificado_hash, 16)) end);
end $$;

create or replace function api.iaraflix_aula(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  a iara.iaraflix_aulas;
  t iara.iaraflix_trilhas;
  pr iara.iaraflix_progresso;
  u iara.app_users;
begin
  perform iara.require_perm('iaraflix.read');
  select * into a from iara.iaraflix_aulas where id = nullif(p ->> 'id', '')::uuid;
  select * into t from iara.iaraflix_trilhas where id = a.trilha_id;
  if a.id is null or not iara.iaraflix_vejo(t.perfis, t.situacao) or (a.situacao <> 'PUBLICADA' and not iara.has_perm('iaraflix.manage')) then
    raise exception 'Aula não encontrada.' using errcode = 'P0002';
  end if;
  select * into u from iara.app_users where id = iara.current_user_id();
  select * into pr from iara.iaraflix_progresso where user_id = u.id and aula_id = a.id;
  return jsonb_build_object('id', a.id, 'ordem', a.ordem, 'titulo', a.titulo, 'resumo', a.resumo, 'pratica', a.pratica, 'duracao_s', a.duracao_s,
    'tem_video', a.video_caminho is not null, 'tem_legenda', a.legenda_caminho is not null, 'situacao', a.situacao,
    'trilha', jsonb_build_object('id', t.id, 'titulo', t.titulo,
      'total', (select count(*) from iara.iaraflix_aulas where trilha_id = t.id and situacao = 'PUBLICADA')),
    'posicao_s', coalesce(pr.posicao_s, 0), 'assistido_s', coalesce(pr.assistido_s, 0), 'concluida', pr.concluida_em is not null,
    'anterior', (select id from iara.iaraflix_aulas where trilha_id = t.id and situacao = 'PUBLICADA' and ordem < a.ordem order by ordem desc limit 1),
    'proxima', (select jsonb_build_object('id', id, 'titulo', titulo) from iara.iaraflix_aulas
                where trilha_id = t.id and situacao = 'PUBLICADA' and ordem > a.ordem order by ordem limit 1),
    'marca', jsonb_build_object('nome', u.display_name, 'unidade', (select short_name from iara.education_units where id = u.unit_id)));
end $$;

-- usado pelo gateway antes de assinar o link do vídeo (o caminho sozinho não abre nada: o bucket é privado)
create or replace function api.iaraflix_video_acesso(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  a iara.iaraflix_aulas;
  t iara.iaraflix_trilhas;
begin
  perform iara.require_perm('iaraflix.read');
  select * into a from iara.iaraflix_aulas where id = nullif(p ->> 'id', '')::uuid;
  select * into t from iara.iaraflix_trilhas where id = a.trilha_id;
  if a.id is null or not iara.iaraflix_vejo(t.perfis, t.situacao) or (a.situacao <> 'PUBLICADA' and not iara.has_perm('iaraflix.manage')) then
    raise exception 'Aula não encontrada.' using errcode = 'P0002';
  end if;
  if a.video_caminho is null then raise exception 'O vídeo desta aula ainda está em produção.' using errcode = 'P0002'; end if;
  insert into iara.iaraflix_progresso (user_id, aula_id) values (iara.current_user_id(), a.id) on conflict do nothing;
  return jsonb_build_object('bucket', 'iara-treinamento', 'video', a.video_caminho, 'legenda', a.legenda_caminho, 'mime', a.video_mime);
end $$;

-- posição e tempo assistido (o tempo assistido só cresce; a aula conclui com 90% do vídeo assistido ou, sem vídeo, quando a pessoa marca como estudada)
create or replace function api.iaraflix_progresso(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  a iara.iaraflix_aulas;
  t iara.iaraflix_trilhas;
  pr iara.iaraflix_progresso;
  v_user uuid := iara.current_user_id();
  v_dur integer;
  v_pos integer;
  v_ass integer;
  v_concluiu boolean;
begin
  perform iara.require_perm('iaraflix.read');
  select * into a from iara.iaraflix_aulas where id = nullif(p ->> 'aula_id', '')::uuid;
  select * into t from iara.iaraflix_trilhas where id = a.trilha_id;
  if a.id is null or a.situacao <> 'PUBLICADA' or not iara.iaraflix_vejo(t.perfis, t.situacao) then
    raise exception 'Aula não encontrada.' using errcode = 'P0002';
  end if;
  v_dur := coalesce(a.duracao_s, case when coalesce((p ->> 'duracao_s')::numeric, 0) >= 1 then least(7200, round((p ->> 'duracao_s')::numeric))::integer end);
  if a.duracao_s is null and v_dur is not null and a.video_caminho is not null then
    update iara.iaraflix_aulas set duracao_s = v_dur where id = a.id and duracao_s is null;
  end if;
  v_pos := greatest(0, least(round(coalesce((p ->> 'posicao_s')::numeric, 0))::integer, coalesce(v_dur, 7200)));
  v_ass := greatest(0, least(round(coalesce((p ->> 'assistido_s')::numeric, 0))::integer, coalesce(v_dur, 7200)));
  insert into iara.iaraflix_progresso as x (user_id, aula_id, posicao_s, assistido_s, atualizado_em)
  values (v_user, a.id, v_pos, v_ass, now())
  on conflict (user_id, aula_id) do update set posicao_s = excluded.posicao_s, assistido_s = greatest(x.assistido_s, excluded.assistido_s), atualizado_em = now()
  returning * into pr;
  v_concluiu := pr.concluida_em is null and (
    (a.video_caminho is not null and v_dur is not null and pr.assistido_s >= 0.9 * v_dur)
    or (a.video_caminho is null and coalesce((p ->> 'estudada')::boolean, false)));
  if v_concluiu then
    update iara.iaraflix_progresso set concluida_em = now() where user_id = v_user and aula_id = a.id;
  end if;
  return iara.iaraflix_atualizar_participacao(t.id) || jsonb_build_object('concluida', pr.concluida_em is not null or v_concluiu);
end $$;

-- perguntas do fim da trilha: acertando todas, sai o certificado (pode tentar de novo; cada erro vem com a explicação)
create or replace function api.iaraflix_avaliar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  t iara.iaraflix_trilhas;
  pa iara.iaraflix_participacoes;
  s jsonb;
  q record;
  v_resp jsonb := coalesce(p -> 'respostas', '[]'::jsonb);
  v_acertos integer := 0;
  v_n integer := 0;
  v_res jsonb := '[]'::jsonb;
  v_ok boolean;
begin
  perform iara.require_perm('iaraflix.read');
  select * into t from iara.iaraflix_trilhas where id = p ->> 'trilha_id';
  if t.id is null or t.situacao <> 'PUBLICADA' or not iara.iaraflix_vejo(t.perfis, t.situacao) then
    raise exception 'Trilha não encontrada.' using errcode = 'P0002';
  end if;
  if jsonb_typeof(v_resp) <> 'array' then raise exception 'Respostas inválidas.' using errcode = '22023'; end if;
  s := iara.iaraflix_atualizar_participacao(t.id);
  if not (s ->> 'pode_avaliar')::boolean then
    raise exception 'Conclua todas as aulas da trilha antes das perguntas.' using errcode = 'P0001';
  end if;
  select * into pa from iara.iaraflix_participacoes where trilha_id = t.id and user_id = iara.current_user_id();
  if pa.concluida_em is not null then
    return jsonb_build_object('aprovado', true, 'ja_concluida', true, 'certificado', pa.certificado_codigo);
  end if;
  for q in select * from iara.iaraflix_perguntas where trilha_id = t.id order by ordem loop
    v_ok := jsonb_typeof(v_resp -> v_n) = 'number' and (v_resp ->> v_n)::numeric = q.correta;
    v_res := v_res || jsonb_build_array(jsonb_build_object('id', q.id, 'certa', v_ok, 'explicacao', q.explicacao));
    v_acertos := v_acertos + case when v_ok then 1 else 0 end;
    v_n := v_n + 1;
  end loop;
  update iara.iaraflix_participacoes x set tentativas = x.tentativas + 1, acertos = v_acertos, perguntas = v_n,
    concluida_em = case when v_acertos = v_n then now() end,
    certificado_codigo = case when v_acertos = v_n then iara.declaracao_codigo() end,
    certificado_hash = case when v_acertos = v_n
      then encode(sha256(convert_to(x.id::text || x.nome || t.titulo || t.carga_horaria::text || now()::text, 'UTF8')), 'hex') end
  where x.id = pa.id returning * into pa;
  if pa.concluida_em is not null then
    perform iara.audit_event('IARAFLIX', 'iaraflix_participacao', pa.id::text, pa.unit_id,
      format('Trilha “%s” concluída no IARAFLIX: certificado %s.', t.titulo, pa.certificado_codigo));
  end if;
  return jsonb_build_object('aprovado', pa.concluida_em is not null, 'acertos', v_acertos, 'perguntas', v_n, 'resultado', v_res,
                            'certificado', pa.certificado_codigo);
end $$;

-- 6. API da gestão do IARAFLIX ----------------------------------------------------------------------------------------------------
create or replace function api.iaraflix_gestao(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('iaraflix.manage');
  return jsonb_build_object('limite_bytes', 52428800, 'trilhas', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', t.id, 'ordem', t.ordem, 'titulo', t.titulo, 'publico', t.publico, 'situacao', t.situacao, 'perfis', to_jsonb(t.perfis),
      'obrigatoria', t.obrigatoria, 'carga_horaria', t.carga_horaria,
      'aulas', coalesce((
        select jsonb_agg(jsonb_build_object('id', a.id, 'ordem', a.ordem, 'titulo', a.titulo, 'resumo', a.resumo, 'pratica', a.pratica,
          'duracao_s', a.duracao_s, 'tem_video', a.video_caminho is not null, 'video_mime', a.video_mime, 'video_bytes', a.video_bytes,
          'tem_legenda', a.legenda_caminho is not null, 'conferido_por', a.video_conferido_por_label, 'conferido_em', a.video_conferido_em,
          'situacao', a.situacao, 'atualizado_em', a.atualizado_em, 'atualizado_por', a.atualizado_por_label) order by a.ordem)
        from iara.iaraflix_aulas a where a.trilha_id = t.id), '[]'::jsonb),
      'perguntas', coalesce((
        select jsonb_agg(jsonb_build_object('id', q.id, 'ordem', q.ordem, 'enunciado', q.enunciado, 'opcoes', to_jsonb(q.opcoes),
          'correta', q.correta, 'explicacao', q.explicacao) order by q.ordem)
        from iara.iaraflix_perguntas q where q.trilha_id = t.id), '[]'::jsonb)) order by t.ordem)
    from iara.iaraflix_trilhas t), '[]'::jsonb));
end $$;

create or replace function api.iaraflix_aula_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  a iara.iaraflix_aulas;
  v_id uuid := nullif(p ->> 'id', '')::uuid;
begin
  perform iara.require_perm('iaraflix.manage');
  if coalesce(btrim(p ->> 'titulo'), '') = '' then raise exception 'Informe o título da aula.' using errcode = '22023'; end if;
  if v_id is null then
    if not exists (select 1 from iara.iaraflix_trilhas where id = p ->> 'trilha_id') then raise exception 'Trilha não encontrada.' using errcode = 'P0002'; end if;
    insert into iara.iaraflix_aulas (trilha_id, ordem, titulo, resumo, pratica, situacao, atualizado_por_label)
    values (p ->> 'trilha_id',
            coalesce(nullif(p ->> 'ordem', '')::integer, (select coalesce(max(ordem), 0) + 1 from iara.iaraflix_aulas where trilha_id = p ->> 'trilha_id')),
            btrim(p ->> 'titulo'), nullif(btrim(p ->> 'resumo'), ''), nullif(btrim(p ->> 'pratica'), ''),
            coalesce(nullif(p ->> 'situacao', ''), 'RASCUNHO'), iara.my_label())
    returning * into a;
  else
    update iara.iaraflix_aulas set titulo = btrim(p ->> 'titulo'), resumo = nullif(btrim(p ->> 'resumo'), ''), pratica = nullif(btrim(p ->> 'pratica'), ''),
      ordem = coalesce(nullif(p ->> 'ordem', '')::integer, ordem), situacao = coalesce(nullif(p ->> 'situacao', ''), situacao),
      atualizado_em = now(), atualizado_por_label = iara.my_label()
    where id = v_id returning * into a;
    if a.id is null then raise exception 'Aula não encontrada.' using errcode = 'P0002'; end if;
  end if;
  perform iara.audit_event('IARAFLIX', 'iaraflix_aula', a.id::text, null,
    format('Aula “%s” salva no IARAFLIX (%s).', a.titulo, case a.situacao when 'PUBLICADA' then 'publicada' else 'rascunho' end));
  return jsonb_build_object('ok', true, 'id', a.id);
end $$;

create or replace function api.iaraflix_pergunta_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id uuid := nullif(p ->> 'id', '')::uuid;
  v_opcoes text[];
  q iara.iaraflix_perguntas;
begin
  perform iara.require_perm('iaraflix.manage');
  if coalesce((p ->> 'excluir')::boolean, false) then
    delete from iara.iaraflix_perguntas where id = v_id returning * into q;
    if q.id is null then raise exception 'Pergunta não encontrada.' using errcode = 'P0002'; end if;
    perform iara.audit_event('IARAFLIX', 'iaraflix_pergunta', q.id::text, null, format('Pergunta excluída da trilha %s no IARAFLIX.', q.trilha_id));
    return jsonb_build_object('ok', true);
  end if;
  v_opcoes := array(select btrim(o) from jsonb_array_elements_text(coalesce(p -> 'opcoes', '[]'::jsonb)) o where btrim(o) <> '');
  if coalesce(btrim(p ->> 'enunciado'), '') = '' then raise exception 'Escreva a pergunta.' using errcode = '22023'; end if;
  if cardinality(v_opcoes) not between 2 and 5 then raise exception 'A pergunta precisa de 2 a 5 opções.' using errcode = '22023'; end if;
  if coalesce((p ->> 'correta')::integer, -1) not between 0 and cardinality(v_opcoes) - 1 then
    raise exception 'Marque a opção correta.' using errcode = '22023';
  end if;
  if v_id is null then
    if not exists (select 1 from iara.iaraflix_trilhas where id = p ->> 'trilha_id') then raise exception 'Trilha não encontrada.' using errcode = 'P0002'; end if;
    insert into iara.iaraflix_perguntas (trilha_id, ordem, enunciado, opcoes, correta, explicacao)
    values (p ->> 'trilha_id', (select coalesce(max(ordem), 0) + 1 from iara.iaraflix_perguntas where trilha_id = p ->> 'trilha_id'),
            btrim(p ->> 'enunciado'), v_opcoes, (p ->> 'correta')::smallint, nullif(btrim(p ->> 'explicacao'), ''))
    returning * into q;
  else
    update iara.iaraflix_perguntas set enunciado = btrim(p ->> 'enunciado'), opcoes = v_opcoes, correta = (p ->> 'correta')::smallint,
      explicacao = nullif(btrim(p ->> 'explicacao'), '')
    where id = v_id returning * into q;
    if q.id is null then raise exception 'Pergunta não encontrada.' using errcode = 'P0002'; end if;
  end if;
  perform iara.audit_event('IARAFLIX', 'iaraflix_pergunta', q.id::text, null, format('Pergunta salva na trilha %s do IARAFLIX.', q.trilha_id));
  return jsonb_build_object('ok', true, 'id', q.id);
end $$;

-- envio de vídeo e de legenda: o banco autoriza e dá o caminho; o gateway assina o envio direto ao Storage (o vídeo não passa pelo gateway)
create or replace function api.iaraflix_envio_autorizar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  a iara.iaraflix_aulas;
  v_tipo text := upper(coalesce(p ->> 'tipo', ''));
  v_mime text := lower(coalesce(p ->> 'mime', ''));
  v_bytes bigint := coalesce((p ->> 'bytes')::bigint, 0);
begin
  perform iara.require_perm('iaraflix.manage');
  select * into a from iara.iaraflix_aulas where id = nullif(p ->> 'aula_id', '')::uuid;
  if a.id is null then raise exception 'Aula não encontrada.' using errcode = 'P0002'; end if;
  if v_tipo = 'VIDEO' then
    if v_mime not in ('video/mp4', 'video/webm') then raise exception 'O vídeo deve estar em MP4 (ou WebM).' using errcode = '22023'; end if;
    if v_bytes <= 0 or v_bytes > 52428800 then
      raise exception 'O vídeo passa de 50 MB. Exporte em 720p, perto de 1 Mbps: 5 minutos ficam em cerca de 40 MB.' using errcode = '22023';
    end if;
  elsif v_tipo = 'LEGENDA' then
    if v_bytes <= 0 or v_bytes > 1048576 then raise exception 'A legenda (WebVTT) deve ter até 1 MB.' using errcode = '22023'; end if;
    v_mime := 'text/vtt';
  else
    raise exception 'Tipo de envio inválido.' using errcode = '22023';
  end if;
  return jsonb_build_object('bucket', 'iara-treinamento', 'mime', v_mime,
    'caminho', format('aulas/%s/%s.%s', a.id, gen_random_uuid(), case v_mime when 'video/mp4' then 'mp4' when 'video/webm' then 'webm' else 'vtt' end));
end $$;

create or replace function api.iaraflix_envio_confirmar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  a iara.iaraflix_aulas;
  v_tipo text := upper(coalesce(p ->> 'tipo', ''));
  v_cam text := p ->> 'caminho';
  v_antigo text;
begin
  perform iara.require_perm('iaraflix.manage');
  select * into a from iara.iaraflix_aulas where id = nullif(p ->> 'aula_id', '')::uuid for update;
  if a.id is null then raise exception 'Aula não encontrada.' using errcode = 'P0002'; end if;
  if v_cam is null or v_cam !~ ('^aulas/' || a.id::text || '/[0-9a-f-]{36}\.(mp4|webm|vtt)$') then
    raise exception 'Caminho do arquivo inválido.' using errcode = '22023';
  end if;
  if v_tipo = 'VIDEO' then
    if not coalesce((p ->> 'conferido')::boolean, false) then
      raise exception 'Confirme que o vídeo foi gravado no ambiente de treinamento, só com dados fictícios.' using errcode = '22023';
    end if;
    v_antigo := a.video_caminho;
    update iara.iaraflix_aulas set video_caminho = v_cam, video_mime = p ->> 'mime', video_bytes = (p ->> 'bytes')::bigint,
      duracao_s = case when coalesce((p ->> 'duracao_s')::numeric, 0) >= 1 then least(7200, round((p ->> 'duracao_s')::numeric))::integer end,
      video_conferido_por_label = iara.my_label(), video_conferido_em = now(), atualizado_em = now(), atualizado_por_label = iara.my_label()
    where id = a.id;
  elsif v_tipo = 'LEGENDA' then
    v_antigo := a.legenda_caminho;
    update iara.iaraflix_aulas set legenda_caminho = v_cam, atualizado_em = now(), atualizado_por_label = iara.my_label() where id = a.id;
  else
    raise exception 'Tipo de envio inválido.' using errcode = '22023';
  end if;
  if v_antigo is not null and v_antigo <> v_cam then
    insert into iara.arquivos_descartar (caminho, bucket, motivo) values (v_antigo, 'iara-treinamento', 'substituído no IARAFLIX') on conflict do nothing;
  end if;
  perform iara.audit_event('IARAFLIX', 'iaraflix_aula', a.id::text, null,
    case when v_tipo = 'VIDEO' then format('Vídeo da aula “%s” publicado no IARAFLIX; %s confirmou que só mostra dados fictícios.', a.titulo, iara.my_label())
         else format('Legenda da aula “%s” publicada no IARAFLIX.', a.titulo) end);
  return jsonb_build_object('ok', true);
end $$;

create or replace function api.iaraflix_video_remover(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  a iara.iaraflix_aulas;
  v_tipo text := upper(coalesce(p ->> 'tipo', 'VIDEO'));
  v_cam text;
begin
  perform iara.require_perm('iaraflix.manage');
  select * into a from iara.iaraflix_aulas where id = nullif(p ->> 'aula_id', '')::uuid for update;
  if a.id is null then raise exception 'Aula não encontrada.' using errcode = 'P0002'; end if;
  v_cam := case when v_tipo = 'LEGENDA' then a.legenda_caminho else a.video_caminho end;
  if v_cam is null then return jsonb_build_object('ok', true); end if;
  if v_tipo = 'LEGENDA' then
    update iara.iaraflix_aulas set legenda_caminho = null, atualizado_em = now(), atualizado_por_label = iara.my_label() where id = a.id;
  else
    update iara.iaraflix_aulas set video_caminho = null, video_mime = null, video_bytes = null, duracao_s = null, video_conferido_por_label = null,
      video_conferido_em = null, atualizado_em = now(), atualizado_por_label = iara.my_label() where id = a.id;
  end if;
  insert into iara.arquivos_descartar (caminho, bucket, motivo) values (v_cam, 'iara-treinamento', 'retirado do IARAFLIX') on conflict do nothing;
  perform iara.audit_event('IARAFLIX', 'iaraflix_aula', a.id::text, null,
    format('%s da aula “%s” retirado do IARAFLIX.', case when v_tipo = 'LEGENDA' then 'Legenda' else 'Vídeo' end, a.titulo));
  return jsonb_build_object('ok', true);
end $$;

-- adesão: a gestão e as gerências veem a rede (e podem escolher uma unidade); o diretor, a própria unidade, com os nomes da equipe
create or replace function api.iaraflix_painel(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_rede boolean;
  v_unit integer;
begin
  perform iara.require_perm('iaraflix.equipe');
  v_rede := iara.has_perm('iaraflix.manage') or iara.my_role() in ('SECRETARIO', 'SUPERINTENDENCIA', 'INOVACAO', 'GERENCIA_EI', 'GERENCIA_APOIO');
  v_unit := case when v_rede then nullif(p ->> 'unidade', '')::integer else iara.my_unit() end;
  if not v_rede and v_unit is null then raise exception 'Seu perfil não tem unidade vinculada.' using errcode = '42501'; end if;
  return (
    with part as materialized (
      select pa.* from iara.iaraflix_participacoes pa join iara.iaraflix_trilhas t on t.id = pa.trilha_id
      where t.situacao = 'PUBLICADA' and (v_unit is null or pa.unit_id = v_unit)),
    feitos as materialized (
      select distinct staff_id, trilha_id from part where concluida_em is not null and staff_id is not null),
    -- quem tem trilha do perfil (pela função no cadastro de servidores) e se já concluiu (junção, não uma subconsulta por pessoa)
    serv as materialized (
      select s.id, s.full_name, s.role, s.unit_id, t.id trilha_id, f.staff_id is not null concluiu
      from iara.staff s join iara.iaraflix_trilhas t on s.role = any (t.staff_roles) and t.id <> 'primeiros-passos' and t.situacao = 'PUBLICADA'
      left join feitos f on f.staff_id = s.id and f.trilha_id = t.id
      where coalesce(s.situacao, 'ATIVO') = 'ATIVO' and (v_unit is null or s.unit_id = v_unit)),
    contagem as (
      select trilha_id, count(*) filter (where concluida_em is not null) concluiram, count(*) filter (where concluida_em is null) andamento
      from part group by trilha_id),
    prev as (
      select t.id trilha_id, count(s.id) n from iara.iaraflix_trilhas t
      join iara.staff s on s.role = any (t.staff_roles) and coalesce(s.situacao, 'ATIVO') = 'ATIVO' and (v_unit is null or s.unit_id = v_unit)
      group by t.id)
    select jsonb_build_object(
      'escopo', case when v_unit is null then 'Rede municipal' else (select short_name from iara.education_units where id = v_unit) end,
      'unidade', v_unit, 'rede', v_rede,
      'simulado', exists (select 1 from part where is_demo),
      'resumo', jsonb_build_object(
        'concluidas', (select count(*) from part where concluida_em is not null),
        'andamento', (select count(*) from part where concluida_em is null),
        'ultimos7', (select count(*) from part where concluida_em > now() - interval '7 days'),
        'previstos', (select count(*) from serv),
        'concluiram', (select count(*) from serv where concluiu)),
      'trilhas', (
        select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'titulo', t.titulo, 'previstos', pv.n,
          'concluiram', coalesce(c.concluiram, 0), 'andamento', coalesce(c.andamento, 0)) order by t.ordem), '[]'::jsonb)
        from iara.iaraflix_trilhas t left join prev pv on pv.trilha_id = t.id left join contagem c on c.trilha_id = t.id
        where t.situacao = 'PUBLICADA'),
      'unidades', case when v_unit is null then (
        select coalesce(jsonb_agg(x order by (x ->> 'pct')::numeric, x ->> 'unidade'), '[]'::jsonb) from (
          select jsonb_build_object('id', u.id, 'unidade', u.short_name, 'previstos', count(s.id),
            'concluiram', count(s.id) filter (where s.concluiu),
            'pct', round(100.0 * count(s.id) filter (where s.concluiu) / nullif(count(s.id), 0))) x
          from serv s join iara.education_units u on u.id = s.unit_id group by u.id, u.short_name) z) end,
      'pessoas', case when v_unit is not null then (
        select coalesce(jsonb_agg(x order by case x ->> 'situacao' when 'NAO_INICIADA' then 0 when 'ANDAMENTO' then 1 else 2 end, x ->> 'nome'), '[]'::jsonb) from (
          select jsonb_build_object('nome', s.full_name, 'funcao', s.role, 'trilha', t.titulo, 'total', (select count(*) from iara.iaraflix_aulas a where a.trilha_id = t.id and a.situacao = 'PUBLICADA'),
            'aulas_concluidas', coalesce(pa.aulas_concluidas, 0), 'concluida_em', pa.concluida_em,
            'situacao', case when pa.concluida_em is not null then 'CONCLUIDA' when pa.id is not null then 'ANDAMENTO' else 'NAO_INICIADA' end) x
          from serv s join iara.iaraflix_trilhas t on t.id = s.trilha_id
          left join part pa on pa.staff_id = s.id and pa.trilha_id = s.trilha_id
          union all
          select jsonb_build_object('nome', pa.nome, 'funcao', pa.role_code, 'trilha', t.titulo, 'total', (select count(*) from iara.iaraflix_aulas a where a.trilha_id = t.id and a.situacao = 'PUBLICADA'),
            'aulas_concluidas', pa.aulas_concluidas, 'concluida_em', pa.concluida_em,
            'situacao', case when pa.concluida_em is not null then 'CONCLUIDA' else 'ANDAMENTO' end)
          from part pa join iara.iaraflix_trilhas t on t.id = pa.trilha_id
          where pa.user_id is not null and (pa.staff_id is null or not exists (select 1 from serv s where s.id = pa.staff_id and s.trilha_id = pa.trilha_id))) z) end,
      'recentes', (
        select coalesce(jsonb_agg(jsonb_build_object('nome', case when v_unit is null then iara.nome_abreviado(pa.nome) else pa.nome end, 'trilha', t.titulo,
                 'unidade', (select short_name from iara.education_units where id = pa.unit_id), 'concluida_em', pa.concluida_em) order by pa.concluida_em desc), '[]'::jsonb)
        from (select * from part where concluida_em is not null order by concluida_em desc limit 12) pa join iara.iaraflix_trilhas t on t.id = pa.trilha_id)));
end $$;

-- 7. Verificação pública do certificado (mesmo código e mesma página das declarações) ------------------------------------------------
create or replace function api.declaracao_verificar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_cod text := upper(regexp_replace(coalesce(p ->> 'codigo', ''), '[^A-Za-z0-9]', '', 'g'));
  d iara.declaracoes;
  ep iara.evento_participantes;
  e iara.eventos;
  fx iara.iaraflix_participacoes;
  ft iara.iaraflix_trilhas;
begin
  if length(v_cod) <> 12 then return jsonb_build_object('encontrada', false, 'mensagem', 'O código tem 12 letras e números (ex.: ABCD-EFGH-JK23).'); end if;
  v_cod := substr(v_cod, 1, 4) || '-' || substr(v_cod, 5, 4) || '-' || substr(v_cod, 9, 4);
  update iara.declaracoes set verificacoes = verificacoes + 1, ultima_verificacao = now() where codigo = v_cod returning * into d;
  if d.id is not null then
    return jsonb_build_object('encontrada', true) || iara.declaracao_json(d, false)
      || jsonb_build_object('tipo_rotulo', d.conteudo ->> 'titulo', 'orgao', d.conteudo ->> 'orgao');
  end if;
  select * into ep from iara.evento_participantes where certificado_codigo = v_cod;
  if ep.id is not null then
    select * into e from iara.eventos where id = ep.evento_id;
    return jsonb_build_object('encontrada', true, 'codigo', v_cod, 'tipo', 'CERTIFICADO', 'tipo_rotulo', 'Certificado de participação', 'situacao', 'VALIDA',
      'aluno', iara.nome_abreviado(ep.nome), 'emitida_em', ep.certificado_emitido_em, 'valida_ate', null, 'hash', left(ep.certificado_hash, 16),
      'unidade', coalesce((select short_name from iara.education_units where id = e.unit_id), 'Rede municipal de ensino'),
      'resumo', format('%s — %s h (%s a %s).', e.titulo, replace(e.carga_horaria::text, '.', ','), to_char(e.inicio, 'DD/MM/YYYY'), to_char(e.fim, 'DD/MM/YYYY')),
      'orgao', 'Secretaria Municipal de Educação de Maringá', 'is_demo', ep.is_demo);
  end if;
  select * into fx from iara.iaraflix_participacoes where certificado_codigo = v_cod;
  if fx.id is not null then
    select * into ft from iara.iaraflix_trilhas where id = fx.trilha_id;
    return jsonb_build_object('encontrada', true, 'codigo', v_cod, 'tipo', 'CERTIFICADO', 'tipo_rotulo', 'Certificado de formação — IARAFLIX', 'situacao', 'VALIDA',
      'aluno', iara.nome_abreviado(fx.nome), 'emitida_em', fx.concluida_em, 'valida_ate', null, 'hash', left(fx.certificado_hash, 16),
      'unidade', coalesce((select short_name from iara.education_units where id = fx.unit_id), 'Rede municipal de ensino'),
      'resumo', format('Trilha “%s” do IARAFLIX — %s h, a distância, com avaliação.', ft.titulo, replace(trim(trailing '.' from trim(trailing '0' from ft.carga_horaria::text)), '.', ',')),
      'orgao', 'Secretaria Municipal de Educação de Maringá', 'is_demo', fx.is_demo);
  end if;
  return jsonb_build_object('encontrada', false, 'mensagem', 'Nenhum documento com este código. Confira as letras e os números; se persistir, o documento não é autêntico.');
end $$;

-- 8. LGPD: as colunas com dado de pessoa do IARAFLIX entram na classificação obrigatória ---------------------------------------------
create or replace function iara.classificacao_pendente() returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select coalesce(jsonb_agg(c.table_name || '.' || c.column_name order by c.table_name, c.column_name), '[]'::jsonb)
  from information_schema.columns c
  where c.table_schema = 'iara'
    and c.table_name in ('students', 'student_sensitive', 'guardians', 'household_members', 'student_guardians', 'addresses',
                         'messages', 'conversations', 'whatsapp_contacts', 'service_cases', 'documents', 'waiting_list_entries', 'staff',
                         'staff_formacoes', 'staff_lotacoes', 'mediacoes', 'frequencia_faltas', 'frequencia_justificativas',
                         'frequencia_alertas', 'aluno_restricoes', 'manutencao_chamados', 'mural_leituras', 'mural_enquete_respostas',
                         'ocorrencias', 'ocorrencia_eventos', 'agenda_escolar', 'agenda_ciencia',
                         'notas', 'pareceres', 'alfabetizacao_sondagens', 'planos_intervencao', 'aee_planos', 'aee_atendimentos', 'declaracoes',
                         'transporte_motoristas', 'transporte_rotas', 'transporte_pontos', 'transporte_alunos', 'transporte_viagens', 'transporte_embarques',
                         'transporte_ocorrencias', 'transporte_avisos', 'transporte_abonos', 'pedidos', 'pedido_itens', 'fornecedores',
                         'uk_tamanhos', 'uk_necessidades', 'uk_avisos', 'uk_codigos', 'uk_disparos', 'apoio_casos', 'apoio_registros', 'apoio_profissionais',
                         'familia_vinculos', 'familia_qr', 'familia_codigos', 'familia_trocas_numero',
                         'iaraflix_aulas', 'iaraflix_progresso', 'iaraflix_participacoes')
    and (c.column_name ~ '(name|cpf|nis|rg|phone|email|street|number|complement|postal|location|income|birth|race|sus|notes|body|payload|summary|description|details|allerg|medical|legal|need|telefone|nome|jid|flags|breakdown|relationship|marital|occupation|benefit|consent|context|label)'
         or c.column_name ~ '(^|_)(motivo|justificativa|atestado|detalhe|observacao|acao|descricao|formacao|escolaridade|matricula_funcional|data_admissao|opcao|restricao_codigo|providencias|providencia|texto|conteudo|objetivo|objetivos|resultado|atividade|avaliacao_inicial|orientacoes_sala|divergencia|lat|lng|tecnico|orientacao_escola|orientacao_familia|analise_unidade|conclusao|documento)$')
    and c.column_name not in ('contact_label', 'assigned_label', 'sender_label', 'subject', 'file_name_ext', 'registrado_label', 'produto_codigo', 'area_codigo')
    and not exists (select 1 from iara.classificacao_dados d where d.tabela = c.table_name and d.coluna = c.column_name)
$$;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('iaraflix_participacoes', 'nome', 'PESSOAL', 'nome do servidor no certificado', 'certificado de formação e acompanhamento da adesão',
   'a própria pessoa, a direção da unidade e a gestão do IARAFLIX; na verificação pública, nome abreviado'),
  ('iaraflix_participacoes', 'perguntas', 'INTERNO', 'quantidade de perguntas da trilha (não é dado de pessoa: casa com o filtro por conter "rg")',
   'nota das perguntas de fixação', 'a própria pessoa e a gestão do IARAFLIX'),
  ('iaraflix_aulas', 'atualizado_por_label', 'PESSOAL', 'autoria', 'rastreabilidade do conteúdo', 'gestão do IARAFLIX'),
  ('iaraflix_aulas', 'video_conferido_por_label', 'PESSOAL', 'quem confirmou que o vídeo só tem dados fictícios', 'rastreabilidade do conteúdo', 'gestão do IARAFLIX')
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

revoke all on function iara.iaraflix_minha(text[]), iara.iaraflix_vejo(text[], text), iara.iaraflix_trilha_json(iara.iaraflix_trilhas, uuid),
  iara.iaraflix_atualizar_participacao(text) from public;

commit;
