-- IARA Educa — 046 · Manutenção e obras (Sprint 1, módulo 4; item 46 da seção 12 do documento de estrutura)
-- A escola abre o chamado; a infraestrutura da SEDUC tria, vistoria, orça e executa; a escola valida o serviço ou reabre.
-- Prazo pela prioridade (risco à segurança = 24 horas). Os chamados de demonstração são fictícios e saem pela limpeza do módulo.
begin;

create sequence if not exists iara.manutencao_seq;

create table if not exists iara.manutencao_chamados (
  id uuid primary key default gen_random_uuid(),
  protocolo text not null unique,
  unit_id integer not null references iara.education_units(id),
  categoria text not null check (categoria in ('ELETRICA', 'HIDRAULICA', 'TELHADO', 'PINTURA', 'MARCENARIA', 'SERRALHERIA',
                                               'JARDINAGEM', 'CLIMATIZACAO', 'PLAYGROUND', 'ACESSIBILIDADE', 'INFORMATICA', 'OUTROS')),
  local text not null,
  descricao text not null,
  prioridade text not null check (prioridade in ('URGENTE', 'ALTA', 'MEDIA', 'BAIXA')),
  afeta_seguranca boolean not null default false,
  situacao text not null default 'ABERTO' check (situacao in ('ABERTO', 'TRIAGEM', 'VISTORIA', 'ORCAMENTO', 'AGUARDANDO_EXECUCAO',
                                                              'EM_EXECUCAO', 'CONCLUIDO', 'VALIDADO', 'REABERTO', 'CANCELADO')),
  equipe text check (equipe in ('EQUIPE_PROPRIA', 'EMPRESA_CONTRATADA')),
  responsavel_label text,
  custo_estimado numeric(12, 2),
  custo_final numeric(12, 2),
  aberto_por_label text,
  aberto_em timestamptz not null default now(),
  prazo timestamptz not null,
  concluido_em timestamptz,
  validado_em timestamptz,
  nota_escola smallint check (nota_escola between 1 and 5),
  reaberturas smallint not null default 0,
  is_demo boolean not null default true
);
create index if not exists manutencao_chamados_unit_idx on iara.manutencao_chamados (unit_id, situacao);

create table if not exists iara.manutencao_eventos (
  id uuid primary key default gen_random_uuid(),
  chamado_id uuid not null references iara.manutencao_chamados(id) on delete cascade,
  situacao text not null,
  texto text,
  autor_label text,
  created_at timestamptz not null default now(),
  is_demo boolean not null default true
);
create index if not exists manutencao_eventos_chamado_idx on iara.manutencao_eventos (chamado_id, created_at);

alter table iara.manutencao_chamados enable row level security;
alter table iara.manutencao_eventos enable row level security;

create or replace function iara.manutencao_prazo(p_prioridade text, p_inicio timestamptz) returns timestamptz
language sql immutable as $$
  select p_inicio + case p_prioridade when 'URGENTE' then interval '24 hours' when 'ALTA' then interval '3 days'
                                      when 'MEDIA' then interval '10 days' else interval '30 days' end
$$;

-- passos permitidos a partir de cada situação (a infraestrutura pode pular a vistoria e o orçamento nos reparos simples)
create or replace function iara.manutencao_proximos(p_situacao text) returns text[]
language sql immutable as $$
  select case p_situacao
    when 'ABERTO' then array['TRIAGEM', 'CANCELADO']
    when 'TRIAGEM' then array['VISTORIA', 'AGUARDANDO_EXECUCAO', 'EM_EXECUCAO', 'CANCELADO']
    when 'VISTORIA' then array['ORCAMENTO', 'AGUARDANDO_EXECUCAO', 'EM_EXECUCAO', 'CANCELADO']
    when 'ORCAMENTO' then array['AGUARDANDO_EXECUCAO', 'CANCELADO']
    when 'AGUARDANDO_EXECUCAO' then array['EM_EXECUCAO']
    when 'EM_EXECUCAO' then array['CONCLUIDO']
    when 'REABERTO' then array['TRIAGEM', 'EM_EXECUCAO']
    else '{}'::text[] end
$$;

create or replace function iara.manutencao_json(c iara.manutencao_chamados) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', c.id, 'protocolo', c.protocolo, 'unit_id', c.unit_id,
    'unidade', (select short_name from iara.education_units where id = c.unit_id), 'categoria', c.categoria, 'local', c.local,
    'descricao', c.descricao, 'prioridade', c.prioridade, 'afeta_seguranca', c.afeta_seguranca, 'situacao', c.situacao,
    'equipe', c.equipe, 'responsavel', c.responsavel_label, 'custo_estimado', c.custo_estimado, 'custo_final', c.custo_final,
    'aberto_por', c.aberto_por_label, 'aberto_em', c.aberto_em, 'prazo', c.prazo, 'concluido_em', c.concluido_em,
    'validado_em', c.validado_em, 'nota_escola', c.nota_escola, 'reaberturas', c.reaberturas,
    'atrasado', c.situacao not in ('CONCLUIDO', 'VALIDADO', 'CANCELADO') and c.prazo < now()
                or c.situacao in ('CONCLUIDO', 'VALIDADO') and c.concluido_em > c.prazo,
    'dias_aberto', extract(day from coalesce(c.concluido_em, now()) - c.aberto_em)::int)
$$;

-- 1. Consultas e fluxo --------------------------------------------------------------------------------------------------------------
create or replace function api.manutencao_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_sit text := nullif(p ->> 'situacao', '');
  v_busca text := nullif(btrim(coalesce(p ->> 'busca', '')), '');
begin
  perform iara.require_perm('manutencao.read');
  return (select coalesce(jsonb_agg(iara.manutencao_json(c) order by
            c.situacao in ('CONCLUIDO', 'VALIDADO', 'CANCELADO'), array_position(array['URGENTE', 'ALTA', 'MEDIA', 'BAIXA'], c.prioridade), c.prazo), '[]')
          from (select * from iara.manutencao_chamados c
                where (v_unit is null or c.unit_id = v_unit)
                  and (v_sit is null or (v_sit = 'PENDENTES' and c.situacao not in ('CONCLUIDO', 'VALIDADO', 'CANCELADO'))
                       or (v_sit = 'ATRASADOS' and c.situacao not in ('CONCLUIDO', 'VALIDADO', 'CANCELADO') and c.prazo < now())
                       or (v_sit = 'A_VALIDAR' and c.situacao = 'CONCLUIDO') or c.situacao = v_sit)
                  and (nullif(p ->> 'categoria', '') is null or c.categoria = p ->> 'categoria')
                  and (nullif(p ->> 'prioridade', '') is null or c.prioridade = p ->> 'prioridade')
                  and (v_busca is null or c.protocolo ilike '%' || v_busca || '%' or c.descricao ilike '%' || v_busca || '%'
                       or c.local ilike '%' || v_busca || '%'
                       or exists (select 1 from iara.education_units u where u.id = c.unit_id and u.name ilike '%' || v_busca || '%'))
                order by c.situacao in ('CONCLUIDO', 'VALIDADO', 'CANCELADO'), c.prazo limit 300) c);
end $$;

create or replace function api.manutencao_detalhe(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  c iara.manutencao_chamados;
begin
  perform iara.require_perm('manutencao.read');
  select * into c from iara.manutencao_chamados where id = (p ->> 'id')::uuid;
  if c.id is null or not iara.can_access_unit(c.unit_id) then raise exception 'Chamado não encontrado.' using errcode = 'P0002'; end if;
  return iara.manutencao_json(c) || jsonb_build_object(
    'proximos', case when iara.has_perm('manutencao.manage') then to_jsonb(iara.manutencao_proximos(c.situacao)) else '[]'::jsonb end,
    'pode_validar', c.situacao = 'CONCLUIDO' and iara.has_perm('manutencao.open') and iara.my_scope() = 'UNIT' and iara.my_unit() = c.unit_id,
    'eventos', (select coalesce(jsonb_agg(jsonb_build_object('situacao', e.situacao, 'texto', e.texto, 'autor', e.autor_label, 'em', e.created_at)
                order by e.created_at), '[]') from iara.manutencao_eventos e where e.chamado_id = c.id));
end $$;

create or replace function api.manutencao_abrir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_seg boolean := coalesce((p ->> 'afeta_seguranca')::boolean, false);
  v_prio text := case when v_seg then 'URGENTE' else coalesce(nullif(p ->> 'prioridade', ''), 'MEDIA') end;
  v_desc text := btrim(coalesce(p ->> 'descricao', ''));
  c iara.manutencao_chamados;
begin
  if not (iara.has_perm('manutencao.open') or iara.has_perm('manutencao.manage')) then
    raise exception 'Sem permissão para abrir chamado.' using errcode = '42501';
  end if;
  if v_unit is null or not iara.can_access_unit(v_unit) then raise exception 'Unidade fora do seu escopo.' using errcode = '42501'; end if;
  if length(v_desc) < 10 or length(v_desc) > 2000 then raise exception 'Descreva o problema (de 10 a 2.000 caracteres).' using errcode = '22023'; end if;
  if v_prio not in ('URGENTE', 'ALTA', 'MEDIA', 'BAIXA') then raise exception 'Prioridade inválida.' using errcode = '22023'; end if;
  insert into iara.manutencao_chamados (protocolo, unit_id, categoria, local, descricao, prioridade, afeta_seguranca, aberto_por_label, prazo, is_demo)
  values ('MAN-' || extract(year from now())::int || '-' || lpad(nextval('iara.manutencao_seq')::text, 5, '0'), v_unit,
          coalesce(nullif(p ->> 'categoria', ''), 'OUTROS'), coalesce(nullif(btrim(p ->> 'local'), ''), 'Não informado'), v_desc, v_prio, v_seg,
          iara.my_label(), iara.manutencao_prazo(v_prio, now()), false)
  returning * into c;
  insert into iara.manutencao_eventos (chamado_id, situacao, texto, autor_label, is_demo)
  values (c.id, 'ABERTO', case when v_seg then 'Risco à segurança informado: prazo de 24 horas.' end, iara.my_label(), false);
  perform iara.audit_event('MANUTENCAO_ABERTA', 'manutencao', c.id::text, v_unit, 'Chamado de manutenção ' || c.protocolo || ' aberto.');
  return iara.manutencao_json(c);
end $$;

create or replace function api.manutencao_avancar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.manutencao_chamados;
  v_para text := p ->> 'situacao';
begin
  perform iara.require_perm('manutencao.manage');
  select * into c from iara.manutencao_chamados where id = (p ->> 'id')::uuid for update;
  if c.id is null then raise exception 'Chamado não encontrado.' using errcode = 'P0002'; end if;
  if not (v_para = any (iara.manutencao_proximos(c.situacao))) then
    raise exception 'Passo não permitido: de % para %.', c.situacao, coalesce(v_para, '?') using errcode = '22023';
  end if;
  if v_para = 'CANCELADO' and length(btrim(coalesce(p ->> 'texto', ''))) < 5 then
    raise exception 'Informe o motivo do cancelamento.' using errcode = '22023';
  end if;
  update iara.manutencao_chamados set situacao = v_para,
    prioridade = coalesce(nullif(p ->> 'prioridade', ''), prioridade),
    prazo = case when nullif(p ->> 'prioridade', '') is not null and p ->> 'prioridade' <> prioridade
                 then iara.manutencao_prazo(p ->> 'prioridade', aberto_em) else prazo end,
    equipe = coalesce(nullif(p ->> 'equipe', ''), equipe),
    responsavel_label = coalesce(nullif(p ->> 'responsavel', ''), responsavel_label, iara.my_label()),
    custo_estimado = coalesce(nullif(p ->> 'custo_estimado', '')::numeric, custo_estimado),
    custo_final = coalesce(nullif(p ->> 'custo_final', '')::numeric, custo_final),
    concluido_em = case when v_para = 'CONCLUIDO' then now() else concluido_em end
  where id = c.id returning * into c;
  insert into iara.manutencao_eventos (chamado_id, situacao, texto, autor_label, is_demo)
  values (c.id, v_para, nullif(btrim(coalesce(p ->> 'texto', '')), ''), iara.my_label(), c.is_demo);
  perform iara.audit_event('MANUTENCAO_SITUACAO', 'manutencao', c.id::text, c.unit_id, 'Chamado ' || c.protocolo || ': ' || v_para || '.');
  return api.manutencao_detalhe(jsonb_build_object('id', c.id));
end $$;

-- a escola confere o serviço: valida (com nota) ou reabre
create or replace function api.manutencao_validar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.manutencao_chamados;
  v_ok boolean := coalesce((p ->> 'aprovado')::boolean, true);
begin
  perform iara.require_perm('manutencao.open');
  select * into c from iara.manutencao_chamados where id = (p ->> 'id')::uuid for update;
  if c.id is null or iara.my_scope() <> 'UNIT' or iara.my_unit() <> c.unit_id then
    raise exception 'Só a unidade do chamado valida o serviço.' using errcode = '42501';
  end if;
  if c.situacao <> 'CONCLUIDO' then raise exception 'O chamado ainda não foi concluído.' using errcode = '22023'; end if;
  if not v_ok and length(btrim(coalesce(p ->> 'texto', ''))) < 5 then
    raise exception 'Diga o que ficou pendente para reabrir.' using errcode = '22023';
  end if;
  update iara.manutencao_chamados set situacao = case when v_ok then 'VALIDADO' else 'REABERTO' end,
    validado_em = case when v_ok then now() end, nota_escola = case when v_ok then nullif(p ->> 'nota', '')::smallint end,
    reaberturas = reaberturas + case when v_ok then 0 else 1 end, concluido_em = case when v_ok then concluido_em end
  where id = c.id returning * into c;
  insert into iara.manutencao_eventos (chamado_id, situacao, texto, autor_label, is_demo)
  values (c.id, c.situacao, nullif(btrim(coalesce(p ->> 'texto', '')), ''), iara.my_label(), c.is_demo);
  perform iara.audit_event('MANUTENCAO_VALIDACAO', 'manutencao', c.id::text, c.unit_id,
    'Chamado ' || c.protocolo || case when v_ok then ' validado pela unidade.' else ' reaberto pela unidade.' end);
  return api.manutencao_detalhe(jsonb_build_object('id', c.id));
end $$;

create or replace function api.manutencao_painel(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
begin
  perform iara.require_perm('manutencao.read');
  return (with c as (select * from iara.manutencao_chamados where v_unit is null or unit_id = v_unit),
               ab as (select * from c where situacao not in ('CONCLUIDO', 'VALIDADO', 'CANCELADO'))
    select jsonb_build_object(
      'pendentes', (select count(*) from ab),
      'atrasados', (select count(*) from ab where prazo < now()),
      'urgentes', (select count(*) from ab where prioridade = 'URGENTE'),
      'a_validar', (select count(*) from c where situacao = 'CONCLUIDO'),
      'concluidos_30d', (select count(*) from c where concluido_em >= now() - interval '30 days'),
      'no_prazo_pct', (select round(100.0 * count(*) filter (where concluido_em <= prazo) / nullif(count(*), 0), 1) from c where concluido_em >= now() - interval '90 days'),
      'dias_medios', (select round(avg(extract(epoch from concluido_em - aberto_em) / 86400)::numeric, 1) from c where concluido_em >= now() - interval '90 days'),
      'nota_media', (select round(avg(nota_escola), 1) from c where nota_escola is not null),
      'custo_ano', (select coalesce(sum(custo_final), 0) from c where concluido_em >= date_trunc('year', now())),
      'por_situacao', (select coalesce(jsonb_object_agg(situacao, n), '{}') from (select situacao, count(*) n from ab group by 1) z),
      'por_categoria', (select coalesce(jsonb_agg(jsonb_build_object('categoria', categoria, 'pendentes', n, 'atrasados', a) order by n desc), '[]')
                        from (select categoria, count(*) n, count(*) filter (where prazo < now()) a from ab group by 1) z),
      'por_mes', (select coalesce(jsonb_agg(jsonb_build_object('mes', m, 'abertos', a, 'concluidos', k) order by m), '[]') from (
          select to_char(d, 'YYYY-MM') m, (select count(*) from c where date_trunc('month', aberto_em) = d) a,
                 (select count(*) from c where date_trunc('month', concluido_em) = d) k
          from generate_series(date_trunc('month', now()) - interval '7 months', date_trunc('month', now()), interval '1 month') d) z),
      'unidades', case when v_unit is null then (select coalesce(jsonb_agg(jsonb_build_object('unit_id', u.id, 'unidade', u.short_name,
                     'pendentes', z.n, 'atrasados', z.a) order by z.a desc, z.n desc), '[]')
                   from (select unit_id, count(*) n, count(*) filter (where prazo < now()) a from ab group by 1 order by 3 desc, 2 desc limit 15) z
                   join iara.education_units u on u.id = z.unit_id) end));
end $$;

-- 2. Gerador da demonstração (chamados fictícios ao longo do ano) ------------------------------------------------------------------
create or replace function iara.demo_gerar_manutencao() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_inicio date := date '2026-01-26';
  x record;
  v_id uuid;
  v_t timestamptz;
  v_fim text;
  v_passos text[];
  v_passo text;
  v_n integer := 0;
  v_h integer;
  v_prazo timestamptz;
  v_prio text;
  v_equipe text;
  v_custo numeric;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.manutencao_chamados where is_demo;
  perform setval('iara.manutencao_seq', coalesce((select max(substring(protocolo from '[0-9]+$')::int) from iara.manutencao_chamados), 0) + 1, false);
  for x in
    select u.id unit_id, u.unit_type, k.k, abs(hashtext(u.id::text || '-man-' || k.k)) h
    from iara.education_units u cross join generate_series(1, 6) k(k)
    where u.status = 'ATIVA'
      and abs(hashtext(u.id::text || '-man-' || k.k)) % 100 < case when u.unit_type = 'ESCOLA' then 70 else 55 end
    order by u.id, k.k
  loop
    v_h := x.h;
    -- abertura espalhada pelo ano letivo, com mais chamados recentes
    v_t := (v_inicio + ((current_date - v_inicio) * (1 - power(((v_h / 7) % 1000) / 1000.0, 1.6)))::int)
           + make_interval(hours => 7 + v_h % 10, mins => v_h % 60);
    if v_t > now() - interval '2 hours' then v_t := now() - make_interval(hours => 2 + v_h % 40); end if;
    v_prio := case when v_h % 100 < 7 then 'URGENTE' when v_h % 100 < 30 then 'ALTA' when v_h % 100 < 80 then 'MEDIA' else 'BAIXA' end;
    v_prazo := iara.manutencao_prazo(v_prio, v_t);
    v_equipe := case when v_h % 3 = 0 then 'EMPRESA_CONTRATADA' else 'EQUIPE_PROPRIA' end;
    insert into iara.manutencao_chamados (protocolo, unit_id, categoria, local, descricao, prioridade, afeta_seguranca, situacao,
                                          equipe, aberto_por_label, aberto_em, prazo, is_demo)
    select 'MAN-2026-' || lpad(nextval('iara.manutencao_seq')::text, 5, '0'), x.unit_id, t.cat, t.loc, t.descr, v_prio,
           v_prio = 'URGENTE' and t.seg, 'ABERTO', null,
           case when x.unit_type = 'CMEI' then 'Direção do CMEI (demonstração)' else 'Direção da escola (demonstração)' end, v_t, v_prazo, true
    from (select * from (values
      ('ELETRICA', 'Sala de aula', 'Lâmpadas queimadas e reator fazendo barulho.', false),
      ('ELETRICA', 'Cozinha', 'Tomada da geladeira esquentando; disjuntor desarma.', true),
      ('ELETRICA', 'Pátio coberto', 'Fiação exposta perto do quadro de luz.', true),
      ('HIDRAULICA', 'Banheiro infantil', 'Vaso sanitário entupido e descarga vazando.', false),
      ('HIDRAULICA', 'Cozinha', 'Torneira da pia pingando e sifão com vazamento.', false),
      ('HIDRAULICA', 'Bebedouro', 'Bebedouro sem pressão e com infiltração na parede.', false),
      ('TELHADO', 'Corredor', 'Goteira forte quando chove; balde no corredor.', false),
      ('TELHADO', 'Refeitório', 'Calha entupida transbordando para dentro.', false),
      ('PINTURA', 'Salas do bloco B', 'Paredes descascando e com mofo.', false),
      ('MARCENARIA', 'Sala de aula', 'Porta empenada não fecha; fechadura quebrada.', false),
      ('MARCENARIA', 'Biblioteca', 'Prateleira solta da parede.', true),
      ('SERRALHERIA', 'Portão de entrada', 'Portão de pedestres não tranca.', true),
      ('SERRALHERIA', 'Janelas do bloco A', 'Grade de janela com solda solta.', false),
      ('JARDINAGEM', 'Área externa', 'Grama alta e galhos sobre o muro.', false),
      ('CLIMATIZACAO', 'Sala multifuncional', 'Ar-condicionado não liga.', false),
      ('CLIMATIZACAO', 'Berçário', 'Ventilador de teto com hélice frouxa.', true),
      ('PLAYGROUND', 'Parque infantil', 'Balanço com corrente desgastada.', true),
      ('PLAYGROUND', 'Parque infantil', 'Escorregador com farpas e parafuso exposto.', true),
      ('ACESSIBILIDADE', 'Entrada principal', 'Rampa com piso quebrado; corrimão solto.', false),
      ('INFORMATICA', 'Laboratório', 'Ponto de rede sem sinal em seis computadores.', false),
      ('OUTROS', 'Muro lateral', 'Trinca no muro após a chuva.', false)) v(cat, loc, descr, seg)
      offset (v_h / 13) % 21 limit 1) t
    returning id into v_id;
    v_n := v_n + 1;
    insert into iara.manutencao_eventos (chamado_id, situacao, texto, autor_label, created_at, is_demo)
    values (v_id, 'ABERTO', null, 'Direção da unidade (demonstração)', v_t, true);

    -- o caminho do chamado; quanto mais antigo, mais longe ele chegou
    v_passos := case when v_h % 4 = 0 then array['TRIAGEM', 'EM_EXECUCAO', 'CONCLUIDO', 'VALIDADO']
                     when v_h % 4 = 1 then array['TRIAGEM', 'VISTORIA', 'AGUARDANDO_EXECUCAO', 'EM_EXECUCAO', 'CONCLUIDO', 'VALIDADO']
                     else array['TRIAGEM', 'VISTORIA', 'ORCAMENTO', 'AGUARDANDO_EXECUCAO', 'EM_EXECUCAO', 'CONCLUIDO', 'VALIDADO'] end;
    if v_h % 17 = 0 then  -- parte volta: a escola não aprova e a equipe retorna
      v_passos := v_passos[1:array_length(v_passos, 1) - 1] || array['REABERTO', 'EM_EXECUCAO', 'CONCLUIDO', 'VALIDADO'];
    end if;
    v_custo := case when v_passos[3] = 'ORCAMENTO' then 800 + (v_h % 90) * 150 else 60 + (v_h % 40) * 12 end;
    foreach v_passo in array v_passos loop
      -- intervalo entre passos: proporcional à prioridade, com atraso em parte dos chamados
      v_t := v_t + make_interval(hours => case v_prio when 'URGENTE' then 3 + v_h % 6 when 'ALTA' then 8 + v_h % 20
                                                       when 'MEDIA' then 30 + v_h % 60 else 80 + v_h % 120 end
                                                  * case when v_h % 9 = 0 then 3 else 1 end
                                                  * case when v_passo = 'ORCAMENTO' then 3 when v_passo = 'AGUARDANDO_EXECUCAO' then 2 else 1 end);
      exit when v_t > now();
      if v_passo = 'REABERTO' then
        insert into iara.manutencao_eventos (chamado_id, situacao, texto, autor_label, created_at, is_demo)
        values (v_id, 'REABERTO', 'O problema voltou depois do serviço.', 'Direção da unidade (demonstração)', v_t, true);
        update iara.manutencao_chamados set situacao = 'REABERTO', reaberturas = 1, concluido_em = null, custo_final = null where id = v_id;
        continue;
      end if;
      insert into iara.manutencao_eventos (chamado_id, situacao, texto, autor_label, created_at, is_demo)
      values (v_id, v_passo, case v_passo when 'VISTORIA' then 'Vistoria agendada com a direção.'
                                         when 'ORCAMENTO' then 'Orçamento solicitado à empresa contratada.'
                                         when 'EM_EXECUCAO' then 'Equipe no local.'
                                         when 'CONCLUIDO' then 'Serviço concluído; aguardando a conferência da escola.' end,
              case when v_passo = 'VALIDADO' then 'Direção da unidade (demonstração)' else 'Infraestrutura SEDUC (demonstração)' end, v_t, true);
      update iara.manutencao_chamados set situacao = v_passo,
        equipe = case when v_passo in ('EM_EXECUCAO', 'AGUARDANDO_EXECUCAO') then v_equipe else equipe end,
        responsavel_label = case when v_passo = 'TRIAGEM' then 'Infraestrutura SEDUC (demonstração)' else responsavel_label end,
        custo_estimado = case when v_passo in ('ORCAMENTO', 'AGUARDANDO_EXECUCAO') then v_custo else custo_estimado end,
        custo_final = case when v_passo = 'CONCLUIDO' then round(v_custo * (0.9 + (v_h % 25) / 100.0), 2) else custo_final end,
        concluido_em = case when v_passo = 'CONCLUIDO' then v_t else concluido_em end,
        validado_em = case when v_passo = 'VALIDADO' then v_t else validado_em end,
        nota_escola = case when v_passo = 'VALIDADO' then (array[5, 5, 4, 4, 4, 3, 5, 2])[1 + v_h % 8] else nota_escola end
      where id = v_id;
    end loop;
  end loop;
  -- base do relógio dos chamados: a rotina diária desloca as datas para a demonstração continuar atual
  update iara.tenants set settings = settings || jsonb_build_object('demo_manutencao_base', current_date) where id = 1;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('chamados', v_n,
    'por_situacao', (select jsonb_object_agg(situacao, n) from (select situacao, count(*) n from iara.manutencao_chamados where is_demo group by 1) z),
    'atrasados', (select count(*) from iara.manutencao_chamados where is_demo and situacao not in ('CONCLUIDO', 'VALIDADO', 'CANCELADO') and prazo < now()));
end $$;

revoke all on function iara.demo_gerar_manutencao() from public;

commit;
