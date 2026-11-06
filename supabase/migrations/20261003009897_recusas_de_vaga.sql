-- IARA Educa — 098.97 · Recusa de vaga: qual unidade foi oferecida, qual o motivo, quem vê o quê, e o mapa de aceitação e recusa.
-- Pedido de Rob (05/11/2026): visão para o responsável, o prefeito, a Central de Vagas, o secretário, o superintendente e o controle externo.
-- A resposta da família continua em api.offer_respond, sem mudança: um gatilho classifica o motivo que ela informou (portal, WhatsApp ou
-- atendente) numa lista fixa, para somar e mapear. O texto da família fica guardado em decline_reason.
-- Quem vê: Prefeito só números, sem pessoas. Controle externo vê cada recusa por código, sem nome e sem o texto da família.
-- Secretário, Superintendência e Central veem o nome e o texto. A família vê só as ofertas das próprias crianças.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

-- ---------------------------------------------------------------- lista de motivos
-- As cores são fixas por motivo (não pela posição no ranking). No mapa só três motivos têm cor própria, porque mais que isso não se
-- distingue com segurança para quem não enxerga bem as cores; os demais ficam em cinza e o nome aparece ao tocar no ponto.
create table if not exists iara.oferta_motivos_recusa (
  codigo text primary key,
  rotulo text not null,
  cor text not null,
  ordem smallint not null
);
alter table iara.oferta_motivos_recusa enable row level security;

insert into iara.oferta_motivos_recusa (codigo, rotulo, cor, ordem) values
  ('DISTANCIA', 'Unidade longe de casa ou do trabalho', '#2a78d6', 1),
  ('TURNO', 'Turno ou horário não atende', '#eb6834', 2),
  ('OUTRA_UNIDADE', 'Prefere aguardar outra unidade', '#1baf7a', 3),
  ('TRANSPORTE', 'Sem transporte até a unidade', '#94a3b8', 4),
  ('IRMAOS', 'Irmãos em outra unidade', '#94a3b8', 5),
  ('OUTRA_ESCOLA', 'Já conseguiu vaga em outra escola', '#94a3b8', 6),
  ('MUDANCA', 'Mudança de endereço ou de cidade', '#94a3b8', 7),
  ('SAUDE', 'Saúde ou adaptação da criança', '#94a3b8', 8),
  ('OUTRO', 'Outro motivo', '#94a3b8', 9)
on conflict (codigo) do update set rotulo = excluded.rotulo, cor = excluded.cor, ordem = excluded.ordem;

alter table iara.vacancy_offers add column if not exists decline_code text references iara.oferta_motivos_recusa(codigo);
create index if not exists vacancy_offers_decline_code_idx on iara.vacancy_offers(decline_code) where decline_code is not null;

-- Rótulo exato da lista; senão, palavras-chave no texto da família; senão, "Outro motivo".
create or replace function iara.motivo_recusa_codigo(p_texto text) returns text
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  t text := btrim(iara.norm(btrim(coalesce(p_texto, ''))));
  v text;
begin
  if t = '' then return null; end if;
  select codigo into v from iara.oferta_motivos_recusa where iara.norm(rotulo) = t;
  if found then return v; end if;
  t := btrim(regexp_replace(t, '^outro motivo\s*[:.-]?\s*', ''));
  return case
    when t ~ 'mudan|mudar|mudei|mudamos|outra cidade|outro municipio|novo endereco' then 'MUDANCA'
    when t ~ 'irma' then 'IRMAOS'
    when t ~ 'transporte|onibus|\mvan\M|conducao|carona|locomo' then 'TRANSPORTE'
    when t ~ 'turno|horario|periodo|integral|manha|tarde|noite' then 'TURNO'
    when t ~ 'distan|longe|perto|trabalho|caminho' then 'DISTANCIA'
    when t ~ 'particular|privad|outra escola|outro colegio|ja (tem|tenho|consegu)|consegui|matriculei|matriculad' then 'OUTRA_ESCOLA'
    when t ~ 'aguard|espera|prefer|outra unidade|outro cmei|outra creche' then 'OUTRA_UNIDADE'
    when t ~ 'saude|doen|laudo|acessib|adapta|medic' then 'SAUDE'
    else 'OUTRO' end;
end $$;

create or replace function iara.tg_oferta_motivo_recusa() returns trigger
language plpgsql security definer set search_path = iara, public
as $$
begin
  new.decline_code := case when new.status = 'DECLINED' then coalesce(iara.motivo_recusa_codigo(new.decline_reason), 'OUTRO') end;
  return new;
end $$;

drop trigger if exists vacancy_offers_motivo on iara.vacancy_offers;
create trigger vacancy_offers_motivo before insert or update of status, decline_reason on iara.vacancy_offers
  for each row execute function iara.tg_oferta_motivo_recusa();

-- ---------------------------------------------------------------- cenário de demonstração (dados fictícios)
do $$
begin
  -- ajuste de dados fictícios: não entra na trilha, como no deslocamento de datas da demonstração
  perform set_config('iara.skip_audit', 'on', true);

  -- 9 ofertas concluídas estavam com data à frente do relógio: voltam 20 dias, para a lista não mostrar uma recusa que ainda não aconteceu
  update iara.vacancy_offers
     set offered_at = offered_at - interval '20 days', expires_at = expires_at - interval '20 days', declined_at = declined_at - interval '20 days'
   where is_demo and status in ('DECLINED', 'EXPIRED') and coalesce(declined_at, offered_at) > now();

  -- as recusas do cenário tinham só 3 textos: viram uma amostra variada (nenhum evento ou registro da trilha cita o texto antigo)
  with r as (
    select id, row_number() over (order by md5(id::text)) n
    from iara.vacancy_offers
    where is_demo and status = 'DECLINED'
      and decline_reason in ('Unidade distante do trabalho', 'Turno incompatível com o trabalho', 'Prefere aguardar a unidade preferida'))
  update iara.vacancy_offers o
     set decline_reason = case
       when r.n <= 7 then 'Unidade longe de casa ou do trabalho'
       when r.n <= 14 then 'Turno ou horário não atende'
       when r.n <= 18 then 'Prefere aguardar outra unidade'
       when r.n = 19 then 'O ônibus da rota não passa perto da nossa casa'
       when r.n <= 21 then 'Sem transporte até a unidade'
       when r.n <= 23 then 'Irmãos em outra unidade'
       when r.n <= 25 then 'Já conseguiu vaga em outra escola'
       when r.n = 26 then 'Mudança de endereço ou de cidade'
       when r.n = 27 then 'Saúde ou adaptação da criança'
       else 'Outro motivo: a família vai cuidar da criança em casa neste ano' end
    from r where o.id = r.id;

  -- exemplo para a visão da família: a Maria recusou uma vaga do Davi em outra unidade, e ele segue na fila da unidade preferida.
  -- Não foi criada por uma sessão ao vivo: a limpeza da apresentação e o reinício da família não a tiram.
  insert into iara.vacancy_offers (tenant_id, waiting_list_entry_id, student_id, class_id, unit_id, offered_at, expires_at, channel, status,
                                   declined_at, decline_reason, response_channel, idempotency_key, is_demo)
  select 1, w.id, w.student_id, c.id, c.unit_id, now() - interval '61 days', now() - interval '58 days', 'WHATSAPP', 'DECLINED',
         now() - interval '60 days', 'Turno ou horário não atende', 'PORTAL', 'demo-recusa-davi', true
  from iara.waiting_list_entries w
  join iara.education_units p on p.id = w.preferred_unit_id
  cross join lateral (
    select c2.id, c2.unit_id from iara.classes c2 join iara.education_units u2 on u2.id = c2.unit_id
    where c2.grade_level_id = w.grade_level_id and c2.unit_id <> w.preferred_unit_id and c2.shift <> 'INTEGRAL'
    order by iara.km_entre(u2.lat, u2.lng, p.lat, p.lng), c2.class_name limit 1) c
  where w.id = (iara.setting('demo_entry_davi'))::uuid
    and not exists (select 1 from iara.vacancy_offers x where x.idempotency_key = 'demo-recusa-davi');

  -- classifica o que já estava registrado
  update iara.vacancy_offers set decline_code = coalesce(iara.motivo_recusa_codigo(decline_reason), 'OUTRO')
   where status = 'DECLINED' and decline_code is null;

  perform set_config('iara.skip_audit', 'off', true);
end $$;

-- ---------------------------------------------------------------- permissões
insert into iara.permissions (code, description, is_sensitive) values
  ('recusas.read', 'Ver a aceitação e a recusa de vagas por unidade e por motivo', false),
  ('recusas.detalhe', 'Ver cada recusa de vaga com o nome da criança e o texto da família', true)
on conflict (code) do update set description = excluded.description, is_sensitive = excluded.is_sensitive;
insert into iara.role_permissions (role_code, permission_code) values
  ('PREFEITO', 'recusas.read'), ('SECRETARIO', 'recusas.read'), ('SUPERINTENDENCIA', 'recusas.read'), ('ANALISTA_CENTRAL', 'recusas.read'), ('CONTROLE_EXTERNO', 'recusas.read'),
  ('SECRETARIO', 'recusas.detalhe'), ('SUPERINTENDENCIA', 'recusas.detalhe'), ('ANALISTA_CENTRAL', 'recusas.detalhe')
on conflict do nothing;

-- ---------------------------------------------------------------- números por unidade (base do painel e do mapa)
create or replace function iara.recusas_unidades(p_desde timestamptz)
returns table (unit_id integer, nome text, lat double precision, lng double precision, decididas integer, aceitas integer, recusadas integer, sem_resposta integer, abertas integer,
               pct_aceite integer, pct_recusa integer, pct_sem_resposta integer, motivo_codigo text, motivo_rotulo text, motivo_cor text, motivos jsonb)
language sql stable security definer set search_path = iara, public
as $$
  with o as (select v.unit_id uid, v.status st, v.decline_code cod from iara.vacancy_offers v where v.offered_at >= p_desde and v.status <> 'CANCELLED'),
  c as (select o.uid,
          count(*) filter (where o.st in ('ACCEPTED', 'ENROLLED'))::int a,
          count(*) filter (where o.st = 'DECLINED')::int r,
          count(*) filter (where o.st = 'EXPIRED')::int s,
          count(*) filter (where o.st = 'OFFERED')::int ab
        from o group by o.uid),
  m as (select o.uid, o.cod, count(*)::int n, k.rotulo, k.cor, k.ordem
        from o join iara.oferta_motivos_recusa k on k.codigo = o.cod where o.st = 'DECLINED' group by o.uid, o.cod, k.rotulo, k.cor, k.ordem)
  select c.uid, u.name, u.lat, u.lng, c.a + c.r + c.s, c.a, c.r, c.s, c.ab,
         round(100.0 * c.a / nullif(c.a + c.r + c.s, 0))::int,
         round(100.0 * c.r / nullif(c.a + c.r + c.s, 0))::int,
         round(100.0 * c.s / nullif(c.a + c.r + c.s, 0))::int,
         t.cod, t.rotulo, t.cor,
         coalesce((select jsonb_agg(jsonb_build_object('codigo', x.cod, 'rotulo', x.rotulo, 'n', x.n) order by x.n desc, x.ordem) from m x where x.uid = c.uid), '[]'::jsonb)
  from c join iara.education_units u on u.id = c.uid
  left join lateral (select y.cod, y.rotulo, y.cor from m y where y.uid = c.uid order by y.n desc, y.ordem limit 1) t on true
$$;

-- totais de um período: percentuais sobre as ofertas concluídas (aceitas, recusadas e sem resposta); em aberto à parte; canceladas fora
create or replace function iara.recusas_totais(p_desde timestamptz) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  with c as (select
      count(*) filter (where status in ('ACCEPTED', 'ENROLLED'))::int a,
      count(*) filter (where status = 'ENROLLED')::int e,
      count(*) filter (where status = 'DECLINED')::int r,
      count(*) filter (where status = 'EXPIRED')::int s,
      count(*) filter (where status = 'OFFERED')::int ab
    from iara.vacancy_offers where offered_at >= p_desde and status <> 'CANCELLED')
  select jsonb_build_object('decididas', a + r + s, 'aceitas', a, 'matriculadas', e, 'recusadas', r, 'sem_resposta', s, 'abertas', ab,
    'pct_aceite', coalesce(round(100.0 * a / nullif(a + r + s, 0))::int, 0),
    'pct_recusa', coalesce(round(100.0 * r / nullif(a + r + s, 0))::int, 0),
    'pct_sem_resposta', coalesce(round(100.0 * s / nullif(a + r + s, 0))::int, 0))
  from c
$$;

create or replace function iara.recusas_motivos(p_desde timestamptz) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  with m as (select v.decline_code cod, count(*)::int n from iara.vacancy_offers v where v.offered_at >= p_desde and v.status = 'DECLINED' group by 1)
  select coalesce(jsonb_agg(jsonb_build_object('codigo', k.codigo, 'rotulo', k.rotulo, 'cor', k.cor, 'n', m.n,
                                               'pct', round(100.0 * m.n / nullif((select sum(n) from m), 0))::int) order by m.n desc, k.ordem), '[]'::jsonb)
  from m join iara.oferta_motivos_recusa k on k.codigo = m.cod
$$;

-- ---------------------------------------------------------------- painel
create or replace function api.recusas_painel(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_desde timestamptz := now() - interval '12 months';
  v_nivel text;
  v_registros jsonb := '[]'::jsonb;
begin
  perform iara.require_perm('recusas.read');
  v_nivel := case when iara.has_perm('recusas.detalhe') then 'NOMES' when iara.my_role() = 'CONTROLE_EXTERNO' then 'CODIGOS' else 'NENHUM' end;

  if v_nivel = 'NOMES' then
    select coalesce(jsonb_agg(x.j order by x.quando desc), '[]'::jsonb) into v_registros from (
      select o.declined_at quando, jsonb_build_object('id', o.id, 'quando', o.declined_at, 'ofertada_em', o.offered_at, 'unit_id', o.unit_id, 'unidade', u.name,
        'turma', c.class_name, 'turno', c.shift, 'motivo_codigo', o.decline_code, 'motivo', k.rotulo,
        'texto', case when iara.norm(btrim(coalesce(o.decline_reason, ''))) <> iara.norm(k.rotulo)
                      then nullif(btrim(regexp_replace(o.decline_reason, '^Outro motivo\s*[:.-]?\s*', '')), '') end,
        'canal', o.response_channel, 'crianca', s.full_name, 'student_id', o.student_id) j
      from iara.vacancy_offers o
      join iara.education_units u on u.id = o.unit_id join iara.classes c on c.id = o.class_id
      join iara.students s on s.id = o.student_id join iara.oferta_motivos_recusa k on k.codigo = o.decline_code
      where o.status = 'DECLINED' and o.offered_at >= v_desde and iara.can_access_student(o.student_id)
      order by o.declined_at desc limit 300) x;
  elsif v_nivel = 'CODIGOS' then
    -- sem nome, sem turma e sem o texto da família: só o código da inscrição, a unidade, a data e a categoria do motivo
    select coalesce(jsonb_agg(x.j order by x.quando desc), '[]'::jsonb) into v_registros from (
      select o.declined_at quando, jsonb_build_object('quando', o.declined_at, 'unit_id', o.unit_id, 'unidade', u.name,
        'codigo', iara.codigo_publico(o.waiting_list_entry_id), 'motivo_codigo', o.decline_code, 'motivo', k.rotulo) j
      from iara.vacancy_offers o
      join iara.education_units u on u.id = o.unit_id join iara.oferta_motivos_recusa k on k.codigo = o.decline_code
      where o.status = 'DECLINED' and o.offered_at >= v_desde
      order by o.declined_at desc limit 300) x;
  end if;

  return jsonb_build_object(
    'desde', v_desde::date, 'atualizado_em', now(), 'nivel', v_nivel,
    'totais', iara.recusas_totais(v_desde),
    'motivos', iara.recusas_motivos(v_desde),
    'unidades', (select coalesce(jsonb_agg(jsonb_build_object('id', r.unit_id, 'nome', r.nome, 'decididas', r.decididas, 'aceitas', r.aceitas, 'recusadas', r.recusadas,
        'sem_resposta', r.sem_resposta, 'abertas', r.abertas, 'pct_aceite', r.pct_aceite, 'pct_recusa', r.pct_recusa, 'pct_sem_resposta', r.pct_sem_resposta,
        'motivo_codigo', r.motivo_codigo, 'motivo', r.motivo_rotulo, 'motivos', r.motivos) order by r.recusadas desc, r.pct_recusa desc nulls last, r.nome), '[]'::jsonb)
      from iara.recusas_unidades(v_desde) r where r.decididas > 0),
    'registros', v_registros);
end $$;

-- ---------------------------------------------------------------- mapa (mesmo formato de api.mapa_calor, com a legenda vinda daqui)
-- Faixas fixas, não os terços do semáforo: muitas unidades têm 100% de aceite, e os terços pintariam 100% de vermelho.
create or replace function api.recusas_mapa(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_camada text := coalesce(nullif(p ->> 'camada', ''), 'oferta_aceite');
  v_desde timestamptz := now() - interval '12 months';
  v_tot jsonb;
  v_pontos jsonb;
  v_ranking jsonb;
  v_legenda jsonb;
  v_verde constant text := '#16A34A';
  v_amarelo constant text := '#EAB308';
  v_vermelho constant text := '#DC2626';
begin
  perform iara.require_perm('recusas.read');
  if v_camada not in ('oferta_aceite', 'oferta_recusa', 'oferta_motivo') then
    raise exception 'Mapa desconhecido.' using errcode = '22023';
  end if;
  v_tot := iara.recusas_totais(v_desde);

  -- o ponto diz a unidade, os percentuais, a base e os motivos; nunca o nome de uma pessoa
  with u as (
    select r.*, format('%s: %s%% aceitaram, %s%% recusaram, %s%% sem resposta (%s oferta%s).%s', r.nome, r.pct_aceite, r.pct_recusa, r.pct_sem_resposta,
             r.decididas, case when r.decididas = 1 then '' else 's' end,
             case when r.recusadas > 0 then ' Motivos: ' || (select string_agg(format('%s (%s)', m ->> 'rotulo', m ->> 'n'), ', ') from jsonb_array_elements(r.motivos) m) || '.' else '' end) titulo
    from iara.recusas_unidades(v_desde) r where r.decididas > 0 and r.lat is not null)
  select coalesce(jsonb_agg(jsonb_build_object('lat', u.lat, 'lng', u.lng, 'titulo', u.titulo,
           'valor', case v_camada when 'oferta_aceite' then u.pct_aceite when 'oferta_recusa' then u.pct_recusa else u.recusadas end,
           'cor', case v_camada
             when 'oferta_aceite' then case when u.pct_aceite >= 85 then v_verde when u.pct_aceite >= 60 then v_amarelo else v_vermelho end
             when 'oferta_recusa' then case when u.pct_recusa <= 10 then v_verde when u.pct_recusa <= 30 then v_amarelo else v_vermelho end
             else u.motivo_cor end)), '[]'::jsonb) into v_pontos
  from u where v_camada <> 'oferta_motivo' or u.recusadas > 0;

  -- unidades com menos de 3 ofertas ficam fora do ranking (uma só recusa daria 100%), mas continuam no mapa
  if v_camada = 'oferta_aceite' then
    select coalesce(jsonb_agg(jsonb_build_object('nome', x.nome, 'detalhe', format('%s ofertas · %s recusa(s)', x.decididas, x.recusadas), 'valor', x.pct_aceite, 'sufixo', '%')
             order by x.pct_aceite, x.decididas desc, x.nome), '[]'::jsonb) into v_ranking
    from (select * from iara.recusas_unidades(v_desde) r where r.decididas >= 3 order by r.pct_aceite, r.decididas desc, r.nome limit 10) x;
    v_legenda := jsonb_build_array(
      jsonb_build_object('cor', v_vermelho, 'rotulo', 'Aceita pouco (abaixo de 60%)'),
      jsonb_build_object('cor', v_amarelo, 'rotulo', 'Intermediário (60% a 84%)'),
      jsonb_build_object('cor', v_verde, 'rotulo', 'Aceita muito (85% ou mais)'));
  elsif v_camada = 'oferta_recusa' then
    select coalesce(jsonb_agg(jsonb_build_object('nome', x.nome, 'detalhe', format('%s ofertas%s', x.decididas, coalesce(' · ' || x.motivo_rotulo, '')), 'valor', x.pct_recusa, 'sufixo', '%')
             order by x.pct_recusa desc, x.decididas desc, x.nome), '[]'::jsonb) into v_ranking
    from (select * from iara.recusas_unidades(v_desde) r where r.decididas >= 3 order by r.pct_recusa desc, r.decididas desc, r.nome limit 10) x;
    v_legenda := jsonb_build_array(
      jsonb_build_object('cor', v_vermelho, 'rotulo', 'Recusa muito (acima de 30%)'),
      jsonb_build_object('cor', v_amarelo, 'rotulo', 'Intermediário (11% a 30%)'),
      jsonb_build_object('cor', v_verde, 'rotulo', 'Recusa pouco (até 10%)'));
  else
    select coalesce(jsonb_agg(jsonb_build_object('nome', x.nome, 'detalhe', x.motivo_rotulo, 'valor', x.recusadas, 'sufixo', case when x.recusadas = 1 then ' recusa' else ' recusas' end)
             order by x.recusadas desc, x.nome), '[]'::jsonb) into v_ranking
    from (select * from iara.recusas_unidades(v_desde) r where r.recusadas > 0 order by r.recusadas desc, r.nome limit 10) x;
    select jsonb_agg(jsonb_build_object('cor', k.cor, 'rotulo', k.rotulo) order by k.ordem)
           || jsonb_build_array(jsonb_build_object('cor', '#94a3b8', 'rotulo', 'Demais motivos (o nome aparece ao tocar no ponto)')) into v_legenda
    from iara.oferta_motivos_recusa k where k.cor <> '#94a3b8';
  end if;

  return jsonb_build_object(
    'modo', 'taxa', 'sufixo', '%', 'max', null, 'pontos', v_pontos, 'legenda', v_legenda,
    'resumo', jsonb_build_array(
      jsonb_build_object('rotulo', 'Aceitaram', 'valor', (v_tot ->> 'pct_aceite')::int, 'sufixo', '%'),
      jsonb_build_object('rotulo', 'Recusaram', 'valor', (v_tot ->> 'pct_recusa')::int, 'sufixo', '%'),
      jsonb_build_object('rotulo', 'Sem resposta no prazo', 'valor', (v_tot ->> 'pct_sem_resposta')::int, 'sufixo', '%'),
      jsonb_build_object('rotulo', 'Ofertas concluídas', 'valor', (v_tot ->> 'decididas')::int)),
    'ranking', jsonb_build_object('titulo',
      case v_camada when 'oferta_aceite' then 'Onde menos se aceita' when 'oferta_recusa' then 'Onde mais se recusa' else 'Unidades com mais recusas' end, 'itens', v_ranking),
    'niveis_titulo', 'Principais motivos de recusa',
    'niveis', (select coalesce(jsonb_agg(jsonb_build_object('rotulo', m ->> 'rotulo', 'n', (m ->> 'n')::int)), '[]'::jsonb) from jsonb_array_elements(iara.recusas_motivos(v_desde)) m),
    'nota', 'Últimos 12 meses. Percentual sobre as ofertas concluídas: aceitas, recusadas e sem resposta no prazo. Cada ponto é uma unidade, com poucas ofertas em cada: confira o número ao tocar. Rankings só com 3 ofertas ou mais.',
    'atualizado_em', now());
end $$;

-- ---------------------------------------------------------------- a família: só as ofertas das próprias crianças
create or replace function api.familia_ofertas(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_g uuid := iara.my_guardian();
begin
  perform iara.require_perm('offers.respond_own');
  if v_g is null then return jsonb_build_object('ofertas', '[]'::jsonb); end if;
  return jsonb_build_object('ofertas', (
    select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'crianca', split_part(s.full_name, ' ', 1), 'unit_id', o.unit_id, 'unidade', u.name,
             'turma', c.class_name, 'turno', c.shift, 'ofertada_em', o.offered_at, 'expira_em', o.expires_at, 'situacao', o.status,
             'respondida_em', coalesce(o.declined_at, o.accepted_at), 'motivo', k.rotulo,
             'texto', case when o.status = 'DECLINED' and iara.norm(btrim(coalesce(o.decline_reason, ''))) <> iara.norm(coalesce(k.rotulo, ''))
                           then nullif(btrim(regexp_replace(o.decline_reason, '^Outro motivo\s*[:.-]?\s*', '')), '') end,
             'canal', o.response_channel) order by o.offered_at desc), '[]'::jsonb)
    from iara.vacancy_offers o
    join iara.students s on s.id = o.student_id
    join iara.education_units u on u.id = o.unit_id
    join iara.classes c on c.id = o.class_id
    left join iara.oferta_motivos_recusa k on k.codigo = o.decline_code
    where o.status <> 'CANCELLED'
      and exists (select 1 from iara.student_guardians sg where sg.student_id = o.student_id and sg.guardian_id = v_g)));
end $$;

commit;
