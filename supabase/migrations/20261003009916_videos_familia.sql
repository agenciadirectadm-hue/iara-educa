-- IARA Educa — 099.16 · Vídeos da SEDUC para as famílias
-- A SEDUC publica vídeos para as famílias (como usar o portal e a IARA, vagas e matrícula, vida escolar, avisos e campanhas).
-- O vídeo vem do YouTube (link de um vídeo público ou não listado do canal oficial; o player usa youtube-nocookie e só carrega
-- quando a pessoa toca para assistir) ou de um arquivo enviado pela SEDUC (bucket privado, link assinado de 15 minutos pelo gateway).
-- É conteúdo público: a lista e o player abrem sem login, no portal e pela IARA ("tem vídeo de como fazer a matrícula?").
-- Quem publica: Secretário, Superintendência e Inovação (a gestão do IARAFLIX).
-- Após aplicar: reaplicar 20261003009900_privilegios.sql (que dá acesso anônimo às funções públicas daqui).
begin;

insert into iara.permissions (code, description, is_sensitive) values
  ('videos_familia.manage', 'Vídeos para as famílias: publicar, editar e retirar vídeos do portal e da IARA', false)
on conflict (code) do update set description = excluded.description, is_sensitive = excluded.is_sensitive;
insert into iara.role_permissions (role_code, permission_code)
select r, 'videos_familia.manage' from unnest(array['SECRETARIO', 'SUPERINTENDENCIA', 'INOVACAO']) r
on conflict do nothing;

create table if not exists iara.videos_familia (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  descricao text,
  categoria text not null default 'TUTORIAL' check (categoria in ('TUTORIAL', 'MATRICULA', 'VIDA_ESCOLAR', 'AVISOS', 'OUTROS')),
  fonte text not null check (fonte in ('YOUTUBE', 'ARQUIVO')),
  youtube_id text check (youtube_id is null or youtube_id ~ '^[A-Za-z0-9_-]{11}$'),
  arquivo_caminho text,
  arquivo_mime text check (arquivo_mime is null or arquivo_mime in ('video/mp4', 'video/webm')),
  arquivo_bytes bigint,
  duracao_s integer check (duracao_s is null or duracao_s between 1 and 7200),
  situacao text not null default 'RASCUNHO' check (situacao in ('RASCUNHO', 'PUBLICADO')),
  destaque boolean not null default false,
  ordem integer not null default 0,
  visualizacoes integer not null default 0,
  publicado_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  atualizado_por_label text,
  is_demo boolean not null default false,
  check (fonte <> 'YOUTUBE' or youtube_id is not null)
);
create index if not exists videos_familia_pub on iara.videos_familia (situacao, categoria, ordem);
alter table iara.videos_familia enable row level security;

-- link do YouTube em qualquer formato (watch?v=, youtu.be/, shorts/, embed/, live/) ou o próprio código de 11 caracteres
create or replace function iara.youtube_id(p text) returns text
language sql immutable as $$
  select coalesce(
    substring(btrim(coalesce(p, '')) from '(?:youtube(?:-nocookie)?\.com/(?:watch\?(?:.*&)?v=|embed/|shorts/|live/|v/)|youtu\.be/)([A-Za-z0-9_-]{11})'),
    case when btrim(coalesce(p, '')) ~ '^[A-Za-z0-9_-]{11}$' then btrim(p) end)
$$;

create or replace function iara.video_familia_json(v iara.videos_familia, p_gestao boolean default false) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', v.id, 'titulo', v.titulo, 'descricao', v.descricao, 'categoria', v.categoria, 'fonte', v.fonte,
    'youtube_id', v.youtube_id, 'tem_arquivo', v.arquivo_caminho is not null, 'duracao_s', v.duracao_s, 'destaque', v.destaque,
    'publicado_em', v.publicado_em, 'is_demo', v.is_demo)
  || case when p_gestao then jsonb_build_object('situacao', v.situacao, 'ordem', v.ordem, 'visualizacoes', v.visualizacoes,
       'arquivo_bytes', v.arquivo_bytes, 'atualizado_em', v.atualizado_em, 'atualizado_por', v.atualizado_por_label) else '{}'::jsonb end
$$;

-- lista pública (com "q", ordena pelo que mais combina: a IARA usa assim); a gestão pede {"gestao": true} e vê rascunhos e números
create or replace function api.videos_familia_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_gestao boolean := coalesce((p ->> 'gestao')::boolean, false);
  v_termos text[] := array(select w from regexp_split_to_table(iara.norm(coalesce(p ->> 'q', '')), '[^a-z0-9]+') w
                           where length(w) > 3 and w not in ('video', 'videos', 'tutorial', 'tutoriais', 'como', 'fazer', 'assistir', 'quero', 'algum', 'sobre', 'para'));
begin
  if v_gestao then perform iara.require_perm('videos_familia.manage'); end if;
  return jsonb_build_object(
    'gestao', v_gestao,
    'categorias', jsonb_build_array(
      jsonb_build_object('codigo', 'TUTORIAL', 'nome', 'Aprenda a usar o portal e a IARA'),
      jsonb_build_object('codigo', 'MATRICULA', 'nome', 'Vagas e matrícula'),
      jsonb_build_object('codigo', 'VIDA_ESCOLAR', 'nome', 'Vida escolar'),
      jsonb_build_object('codigo', 'AVISOS', 'nome', 'Avisos e campanhas da SEDUC'),
      jsonb_build_object('codigo', 'OUTROS', 'nome', 'Outros')),
    'videos', coalesce((
      select jsonb_agg(iara.video_familia_json(x.v, v_gestao) order by x.score desc, (x.v).destaque desc, (x.v).ordem, (x.v).publicado_em desc nulls last)
      from (
        select v, (select count(*) from unnest(v_termos) t where iara.norm(v.titulo || ' ' || coalesce(v.descricao, '')) like '%' || t || '%') score
        from iara.videos_familia v
        where (v_gestao or v.situacao = 'PUBLICADO')) x), '[]'::jsonb));
end $$;

create or replace function api.videos_familia_ver(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v iara.videos_familia;
  v_gestao boolean := iara.has_perm('videos_familia.manage');
begin
  select * into v from iara.videos_familia where id = nullif(p ->> 'id', '')::uuid;
  if v.id is null or (v.situacao <> 'PUBLICADO' and not v_gestao) then raise exception 'Vídeo não encontrado.' using errcode = 'P0002'; end if;
  return iara.video_familia_json(v, v_gestao) || jsonb_build_object(
    'mais', coalesce((select jsonb_agg(s.j order by s.n)
                      from (select iara.video_familia_json(o) j, row_number() over (order by o.categoria = v.categoria desc, o.destaque desc, o.ordem, o.publicado_em desc) n
                            from iara.videos_familia o where o.situacao = 'PUBLICADO' and o.id <> v.id) s
                      where s.n <= 6), '[]'::jsonb));
end $$;

-- conta uma visualização quando a pessoa dá o play (estatística para a SEDUC; sem identificar quem assistiu)
create or replace function api.videos_familia_assistiu(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  update iara.videos_familia set visualizacoes = visualizacoes + 1 where id = nullif(p ->> 'id', '')::uuid and situacao = 'PUBLICADO';
  return jsonb_build_object('ok', true);
end $$;

-- usado pelo gateway antes de assinar o link do arquivo (só vídeo publicado; a gestão vê também o rascunho)
create or replace function api.videos_familia_acesso(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v iara.videos_familia;
begin
  select * into v from iara.videos_familia where id = nullif(p ->> 'id', '')::uuid;
  if v.id is null or (v.situacao <> 'PUBLICADO' and not iara.has_perm('videos_familia.manage')) then
    raise exception 'Vídeo não encontrado.' using errcode = 'P0002';
  end if;
  if v.arquivo_caminho is null then raise exception 'Este vídeo não tem arquivo.' using errcode = 'P0002'; end if;
  return jsonb_build_object('bucket', 'iara-treinamento', 'video', v.arquivo_caminho, 'mime', v.arquivo_mime);
end $$;

create or replace function api.videos_familia_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v iara.videos_familia;
  v_id uuid := nullif(p ->> 'id', '')::uuid;
  v_fonte text := upper(coalesce(nullif(p ->> 'fonte', ''), 'YOUTUBE'));
  v_yt text := iara.youtube_id(p ->> 'youtube');
  v_sit text := upper(coalesce(nullif(p ->> 'situacao', ''), 'RASCUNHO'));
begin
  perform iara.require_perm('videos_familia.manage');
  if v_id is not null then select * into v from iara.videos_familia where id = v_id for update; end if;
  if coalesce((p ->> 'excluir')::boolean, false) then
    if v.id is null then raise exception 'Vídeo não encontrado.' using errcode = 'P0002'; end if;
    delete from iara.videos_familia where id = v.id;
    if v.arquivo_caminho is not null then
      insert into iara.arquivos_descartar (caminho, bucket, motivo) values (v.arquivo_caminho, 'iara-treinamento', 'vídeo das famílias excluído') on conflict do nothing;
    end if;
    perform iara.audit_event('VIDEO_FAMILIA', 'video_familia', v.id::text, null, format('Vídeo “%s” excluído da área das famílias.', v.titulo));
    return jsonb_build_object('ok', true);
  end if;
  if coalesce(btrim(p ->> 'titulo'), '') = '' then raise exception 'Informe o título do vídeo.' using errcode = '22023'; end if;
  if v_fonte = 'YOUTUBE' and v_yt is null then
    raise exception 'Cole o link do vídeo no YouTube (por exemplo, https://youtu.be/...).' using errcode = '22023';
  end if;
  if v_fonte = 'ARQUIVO' and v_sit = 'PUBLICADO' and coalesce(v.arquivo_caminho, '') = '' then
    raise exception 'Envie o arquivo do vídeo antes de publicar.' using errcode = '22023';
  end if;
  if v.id is null then
    insert into iara.videos_familia (titulo, descricao, categoria, fonte, youtube_id, situacao, destaque, ordem, publicado_em, atualizado_por_label, is_demo)
    values (btrim(p ->> 'titulo'), nullif(btrim(p ->> 'descricao'), ''), coalesce(nullif(p ->> 'categoria', ''), 'TUTORIAL'), v_fonte,
            case when v_fonte = 'YOUTUBE' then v_yt end, v_sit, coalesce((p ->> 'destaque')::boolean, false), coalesce(nullif(p ->> 'ordem', '')::integer, 0),
            case when v_sit = 'PUBLICADO' then now() end, iara.my_label(), iara.demo_mode())
    returning * into v;
  else
    -- passou a ser do YouTube: o arquivo enviado antes sai do armazenamento
    if v_fonte = 'YOUTUBE' and v.arquivo_caminho is not null then
      insert into iara.arquivos_descartar (caminho, bucket, motivo) values (v.arquivo_caminho, 'iara-treinamento', 'vídeo das famílias passou para o YouTube') on conflict do nothing;
    end if;
    update iara.videos_familia set titulo = btrim(p ->> 'titulo'), descricao = nullif(btrim(p ->> 'descricao'), ''),
      categoria = coalesce(nullif(p ->> 'categoria', ''), categoria), fonte = v_fonte,
      youtube_id = case when v_fonte = 'YOUTUBE' then v_yt end,
      arquivo_caminho = case when v_fonte = 'YOUTUBE' then null else arquivo_caminho end,
      arquivo_mime = case when v_fonte = 'YOUTUBE' then null else arquivo_mime end,
      arquivo_bytes = case when v_fonte = 'YOUTUBE' then null else arquivo_bytes end,
      situacao = v_sit, destaque = coalesce((p ->> 'destaque')::boolean, destaque), ordem = coalesce(nullif(p ->> 'ordem', '')::integer, ordem),
      publicado_em = case when v_sit = 'PUBLICADO' then coalesce(publicado_em, now()) end,
      atualizado_em = now(), atualizado_por_label = iara.my_label()
    where id = v.id returning * into v;
  end if;
  perform iara.audit_event('VIDEO_FAMILIA', 'video_familia', v.id::text, null,
    format('Vídeo “%s” salvo na área das famílias (%s, %s).', v.titulo, case v.fonte when 'YOUTUBE' then 'YouTube' else 'arquivo' end,
           case v.situacao when 'PUBLICADO' then 'publicado' else 'rascunho' end));
  return jsonb_build_object('ok', true, 'id', v.id, 'youtube_id', v.youtube_id);
end $$;

-- envio de arquivo (quando o vídeo não está no YouTube): mesmo caminho do IARAFLIX, na pasta familias/ do bucket privado
create or replace function api.videos_familia_envio_autorizar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v iara.videos_familia;
  v_mime text := lower(coalesce(p ->> 'mime', ''));
  v_bytes bigint := coalesce((p ->> 'bytes')::bigint, 0);
begin
  perform iara.require_perm('videos_familia.manage');
  select * into v from iara.videos_familia where id = nullif(p ->> 'id', '')::uuid;
  if v.id is null then raise exception 'Salve o vídeo antes de enviar o arquivo.' using errcode = 'P0002'; end if;
  if v_mime not in ('video/mp4', 'video/webm') then raise exception 'O vídeo deve estar em MP4 (ou WebM).' using errcode = '22023'; end if;
  if v_bytes <= 0 or v_bytes > 52428800 then raise exception 'O vídeo passa de 50 MB. Exporte em 720p, perto de 1 Mbps.' using errcode = '22023'; end if;
  return jsonb_build_object('bucket', 'iara-treinamento', 'mime', v_mime,
    'caminho', format('familias/%s/%s.%s', v.id, gen_random_uuid(), case v_mime when 'video/mp4' then 'mp4' else 'webm' end));
end $$;

create or replace function api.videos_familia_envio_confirmar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v iara.videos_familia;
  v_cam text := p ->> 'caminho';
begin
  perform iara.require_perm('videos_familia.manage');
  select * into v from iara.videos_familia where id = nullif(p ->> 'id', '')::uuid for update;
  if v.id is null then raise exception 'Vídeo não encontrado.' using errcode = 'P0002'; end if;
  if v_cam is null or v_cam !~ ('^familias/' || v.id::text || '/[0-9a-f-]{36}\.(mp4|webm)$') then raise exception 'Caminho do arquivo inválido.' using errcode = '22023'; end if;
  if v.arquivo_caminho is not null and v.arquivo_caminho <> v_cam then
    insert into iara.arquivos_descartar (caminho, bucket, motivo) values (v.arquivo_caminho, 'iara-treinamento', 'vídeo das famílias substituído') on conflict do nothing;
  end if;
  update iara.videos_familia set fonte = 'ARQUIVO', youtube_id = null, arquivo_caminho = v_cam, arquivo_mime = p ->> 'mime',
    arquivo_bytes = (p ->> 'bytes')::bigint,
    duracao_s = case when coalesce((p ->> 'duracao_s')::numeric, 0) >= 1 then least(7200, round((p ->> 'duracao_s')::numeric))::integer end,
    atualizado_em = now(), atualizado_por_label = iara.my_label()
  where id = v.id;
  perform iara.audit_event('VIDEO_FAMILIA', 'video_familia', v.id::text, null, format('Arquivo do vídeo “%s” enviado para a área das famílias.', v.titulo));
  return jsonb_build_object('ok', true);
end $$;

revoke all on function iara.youtube_id(text), iara.video_familia_json(iara.videos_familia, boolean) from public;

commit;
