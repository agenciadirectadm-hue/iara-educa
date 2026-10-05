-- =============================================================================
-- IARA Educa · Distância por ROTA (a pé e de carro), além da linha reta
-- Apresentação de 05/10/2026: o Ministério Público e a Defensoria questionaram o critério "até 2 km" medido em
-- linha reta e pedem a distância percorrida — a pé e de carro. Para a demonstração: as TRÊS medidas lado a lado,
-- visíveis para a equipe, a família e o controle externo; o critério da fila diz qual delas usa (parâmetro da regra,
-- por município), com simulação do impacto antes de trocar e troca auditada com justificativa.
-- Rotas: motor OSRM sobre o OpenStreetMap — vale para qualquer município (configuração em supabase/functions/api/rotas.ts).
--  1. Cache de rotas (origem arredondada a ~1 m × unidade × modo), com o traçado para desenhar no mapa
--  2. As três distâncias guardadas em cada inscrição da fila e a medida que o critério usou
--  3. Critério TERRITORIO_2KM: condition.medida = LINHA_RETA | A_PE | CARRO (padrão: LINHA_RETA, como hoje)
--  4. API: distancias, fila_rotas_pendentes, fila_simular_medida, fila_medida_definir, distancias_resumo;
--     queue_list passa a trazer as três distâncias de cada inscrição
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
-- =============================================================================
begin;

-- 1. Cache de rotas ---------------------------------------------------------------------------------------
create table if not exists iara.rotas_cache (
  origem_lat numeric(8, 5) not null,
  origem_lng numeric(8, 5) not null,
  unit_id integer not null references iara.education_units(id) on delete cascade,
  modo text not null check (modo in ('A_PE', 'CARRO')),
  distancia_m integer,
  duracao_s integer,
  geometria jsonb,
  sem_rota boolean not null default false,
  provedor text not null,
  calculado_em timestamptz not null default now(),
  primary key (origem_lat, origem_lng, unit_id, modo)
);
create index if not exists rotas_cache_unit_idx on iara.rotas_cache(unit_id);
alter table iara.rotas_cache enable row level security;

alter table iara.waiting_list_entries
  add column if not exists dist_reta_m integer,
  add column if not exists dist_pe_m integer,
  add column if not exists dist_carro_m integer,
  add column if not exists dist_medida text;

-- 2. Auxiliares ----------------------------------------------------------------------------------------------
create or replace function iara.c5(p double precision) returns numeric
language sql immutable as $$ select round(p::numeric, 5) $$;

create or replace function iara.medida_rotulo(p text) returns text
language sql immutable as $$
  select case p when 'A_PE' then 'a pé, pela rota' when 'CARRO' then 'de carro, pela rota' else 'em linha reta' end
$$;

-- medida que o critério de proximidade usa (parâmetro da regra TERRITORIO_2KM; padrão: linha reta)
create or replace function iara.medida_distancia_fila() returns text
language sql stable security definer set search_path = iara, public
as $$ select coalesce(nullif((iara.rule('TERRITORIO_2KM')).condition ->> 'medida', ''), 'LINHA_RETA') $$;

-- as três medidas de um ponto a uma unidade: linha reta (calculada) e rotas (do cache)
create or replace function iara.distancias_ponto(p_lat double precision, p_lng double precision, p_unit integer) returns jsonb
language sql stable security definer set search_path = iara, extensions, public
as $$
  select jsonb_build_object(
    'linha_reta_m', round(st_distance(u.location, iara.point(p_lat, p_lng)))::int,
    'a_pe', (select case when c.sem_rota then jsonb_build_object('sem_rota', true)
                         else jsonb_build_object('distancia_m', c.distancia_m, 'duracao_s', c.duracao_s, 'calculado_em', c.calculado_em, 'provedor', c.provedor) end
             from iara.rotas_cache c
             where c.origem_lat = iara.c5(p_lat) and c.origem_lng = iara.c5(p_lng) and c.unit_id = u.id and c.modo = 'A_PE'),
    'carro', (select case when c.sem_rota then jsonb_build_object('sem_rota', true)
                          else jsonb_build_object('distancia_m', c.distancia_m, 'duracao_s', c.duracao_s, 'calculado_em', c.calculado_em, 'provedor', c.provedor) end
              from iara.rotas_cache c
              where c.origem_lat = iara.c5(p_lat) and c.origem_lng = iara.c5(p_lng) and c.unit_id = u.id and c.modo = 'CARRO'))
  from iara.education_units u where u.id = p_unit
$$;

-- 3. Critério de proximidade com a medida da regra -----------------------------------------------------------
update iara.rules set condition = condition || '{"medida": "LINHA_RETA"}'::jsonb
where tenant_id = 1 and rule_code = 'TERRITORIO_2KM' and is_active and not (condition ? 'medida');

create or replace function iara.compute_queue_priority(p_entry uuid) returns void
language plpgsql security definer set search_path = iara, extensions, public
as $$
declare
  w iara.waiting_list_entries;
  v_dist integer;
  v_reta integer;
  v_pe integer;
  v_carro integer;
  v_lat double precision;
  v_lng double precision;
  v_medida text;
  v_provisoria boolean := false;
  v_sibling boolean;
  v_cadunico boolean;
  v_single_mother boolean;
  v_aee boolean;
  v_laudo text;
  v_vuln boolean;
  v_breakdown jsonb := '[]'::jsonb;
  v_score numeric := 0;
  v_flags text[] := '{}';
  r iara.rules;
  v_max_m integer;
begin
  select * into w from iara.waiting_list_entries where id = p_entry;
  if not found then return; end if;

  select st_y(a.location::geometry), st_x(a.location::geometry), round(st_distance(a.location, u.location))::int
  into v_lat, v_lng, v_reta
  from iara.students s join iara.addresses a on a.id = s.address_id
  join iara.education_units u on u.id = w.preferred_unit_id
  where s.id = w.student_id;
  if v_lat is not null then
    select max(c.distancia_m) filter (where c.modo = 'A_PE' and not c.sem_rota), max(c.distancia_m) filter (where c.modo = 'CARRO' and not c.sem_rota)
    into v_pe, v_carro
    from iara.rotas_cache c
    where c.origem_lat = iara.c5(v_lat) and c.origem_lng = iara.c5(v_lng) and c.unit_id = w.preferred_unit_id;
  end if;

  select exists (
    select 1 from iara.student_guardians sg1
    join iara.student_guardians sg2 on sg2.guardian_id = sg1.guardian_id and sg2.student_id <> sg1.student_id
    join iara.enrollments e on e.student_id = sg2.student_id and e.status = 'ACTIVE' and e.unit_id = w.preferred_unit_id
    where sg1.student_id = w.student_id) into v_sibling;

  select coalesce(bool_or(g.cadunico_status), false), coalesce(bool_or(g.single_mother), false)
    into v_cadunico, v_single_mother
  from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
  where sg.student_id = w.student_id;

  select coalesce(aee_status, false) into v_aee from iara.students where id = w.student_id;
  select d.status into v_laudo from iara.documents d
  where d.student_id = w.student_id and d.doc_type = 'LAUDO' order by d.created_at desc limit 1;
  v_vuln := 'VULNERABILIDADE' = any (w.priority_flags);

  -- Critérios de pontuação, na ordem do Anexo I
  r := iara.rule('IRMAO_NA_UNIDADE');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', v_sibling,
      'evidence', case when v_sibling then 'Irmão(ã) com matrícula ativa na unidade pretendida' else 'Sem irmão(ã) matriculado(a) na unidade' end);
    if v_sibling then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'IRMAO_NA_UNIDADE'); end if;
  end if;

  r := iara.rule('CADUNICO');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', v_cadunico,
      'evidence', case when v_cadunico then 'Responsável com inscrição ativa no CadÚnico' else 'Sem inscrição no CadÚnico informada' end);
    if v_cadunico then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'CADUNICO'); end if;
  end if;

  -- proximidade: a medida (linha reta, a pé ou de carro) é parâmetro da regra; as três ficam registradas
  r := iara.rule('TERRITORIO_2KM');
  if r.id is not null then
    v_max_m := coalesce((r.condition ->> 'max_m')::int, 2000);
    v_medida := coalesce(nullif(r.condition ->> 'medida', ''), 'LINHA_RETA');
    v_dist := case v_medida when 'A_PE' then v_pe when 'CARRO' then v_carro else v_reta end;
    if v_dist is null and v_reta is not null and v_medida <> 'LINHA_RETA' then
      v_dist := v_reta;
      v_provisoria := true;
    end if;
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', coalesce(v_dist <= v_max_m, false), 'medida', v_medida, 'provisoria', v_provisoria, 'max_m', v_max_m,
      'distancias', jsonb_build_object('linha_reta_m', v_reta, 'a_pe_m', v_pe, 'carro_m', v_carro),
      'evidence', case when v_dist is null then 'Endereço sem geocodificação — critério não verificado'
                       else format('Residência a %s km da unidade pretendida (%s)%s', replace(round(v_dist / 1000.0, 1)::text, '.', ','),
                                   case when v_provisoria then 'em linha reta' else iara.medida_rotulo(v_medida) end,
                                   case when v_provisoria then format(' — rota %s ainda não calculada: vale a linha reta, provisoriamente',
                                                                      case v_medida when 'A_PE' then 'a pé' else 'de carro' end)
                                        else '' end) end);
    if coalesce(v_dist <= v_max_m, false) then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'TERRITORIO'); end if;
  end if;

  r := iara.rule('MAE_SOLO');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', v_single_mother,
      'evidence', case when v_single_mother then 'Responsável declarou ser mãe solo' else 'Sem declaração de mãe solo' end);
    if v_single_mother then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'MAE_SOLO'); end if;
  end if;

  -- Critério de prioridade: sob análise, mediante laudo — fora da soma de pontos
  r := iara.rule('PCD_TEA_AEE');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', v_aee, 'analysis', r.rule_type = 'PRIORIDADE_ANALISE', 'laudo_status', coalesce(v_laudo, 'NAO_ENVIADO'),
      'evidence', case when not v_aee then 'Sem indicação de deficiência, TEA, TGD ou altas habilidades/superdotação'
                       when v_laudo = 'VALIDADO' then 'Laudo médico com CID validado — prioridade sob análise da Central de Vagas (não soma pontos)'
                       when v_laudo = 'RECEBIDO' then 'Laudo recebido, aguardando validação — prioridade sob análise (não soma pontos)'
                       else 'Indicação registrada; laudo médico com CID pendente — prioridade sob análise (não soma pontos)' end);
    if v_aee then
      v_flags := array_append(v_flags, 'PCD_TEA_AEE');
      if r.rule_type <> 'PRIORIDADE_ANALISE' then v_score := v_score + r.weight; end if;
    end if;
  end if;

  -- Regra anterior (2026.01), inativa na versão 2026.02: só conta se for reativada
  r := iara.rule('VULNERABILIDADE');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', v_vuln, 'evidence', case when v_vuln then 'Encaminhamento da rede de proteção registrado' else 'Sem encaminhamento da rede de proteção' end);
    if v_vuln then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'VULNERABILIDADE'); end if;
  end if;

  -- Desempate
  r := iara.rule('DATA_SOLICITACAO');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', 0, 'version', r.version,
      'applied', true, 'evidence', format('Desempate pela data de entrada: %s', to_char(w.entered_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')));
  end if;

  update iara.waiting_list_entries set
    priority_score = v_score,
    score_breakdown = v_breakdown,
    home_distance_m = v_dist,
    dist_reta_m = v_reta,
    dist_pe_m = v_pe,
    dist_carro_m = v_carro,
    dist_medida = v_medida,
    priority_flags = v_flags,
    rule_version = iara.rule_version(),
    last_recalculated_at = now()
  where id = p_entry;
end $$;

-- recalcula a pontuação de todas as inscrições ativas e as posições de todas as filas (troca de medida)
create or replace function iara.recalcular_filas() returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  n integer := 0;
  q record;
begin
  perform iara.compute_queue_priority(w.id) from iara.waiting_list_entries w where w.status in ('WAITING', 'OFFERED', 'ACCEPTED');
  get diagnostics n = row_count;
  for q in select distinct preferred_unit_id as u, grade_level_id as g from iara.waiting_list_entries where status = 'WAITING' loop
    perform iara.recalculate_queue(q.u, q.g);
  end loop;
  return n;
end $$;

-- 4. Gravação das rotas (só o gateway, como sistema) ----------------------------------------------------------
create or replace function iara.rotas_gravar(p jsonb) returns integer
language plpgsql security definer set search_path = iara, extensions, public
as $$
declare
  n integer;
  q record;
  v_medida text := iara.medida_distancia_fila();
  v_ids uuid[];
begin
  insert into iara.rotas_cache (origem_lat, origem_lng, unit_id, modo, distancia_m, duracao_s, geometria, sem_rota, provedor, calculado_em)
  select iara.c5((x ->> 'lat')::double precision), iara.c5((x ->> 'lng')::double precision), (x ->> 'unit_id')::int, x ->> 'modo',
         nullif(x ->> 'distancia_m', '')::int, nullif(x ->> 'duracao_s', '')::int,
         case when jsonb_typeof(x -> 'geometria') = 'array' then x -> 'geometria' end,
         nullif(x ->> 'distancia_m', '') is null, coalesce(nullif(x ->> 'provedor', ''), 'OSRM'), now()
  from jsonb_array_elements(coalesce(p -> 'itens', '[]'::jsonb)) x
  where x ->> 'modo' in ('A_PE', 'CARRO')
  on conflict (origem_lat, origem_lng, unit_id, modo) do update set
    distancia_m = excluded.distancia_m, duracao_s = excluded.duracao_s,
    geometria = coalesce(excluded.geometria, iara.rotas_cache.geometria),
    sem_rota = excluded.sem_rota, provedor = excluded.provedor, calculado_em = now();
  get diagnostics n = row_count;

  -- inscrições da fila com esta origem e esta unidade passam a ter as distâncias por rota
  select coalesce(array_agg(w.id), '{}') into v_ids
  from iara.waiting_list_entries w
  join iara.students s on s.id = w.student_id
  join iara.addresses a on a.id = s.address_id
  where w.status in ('WAITING', 'OFFERED', 'ACCEPTED')
    and (iara.c5(st_y(a.location::geometry)), iara.c5(st_x(a.location::geometry)), w.preferred_unit_id) in (
      select iara.c5((x ->> 'lat')::double precision), iara.c5((x ->> 'lng')::double precision), (x ->> 'unit_id')::int
      from jsonb_array_elements(coalesce(p -> 'itens', '[]'::jsonb)) x);
  if cardinality(v_ids) > 0 then
    if v_medida = 'LINHA_RETA' then
      -- a pontuação não muda (o critério usa a linha reta): só as distâncias registradas na inscrição e no extrato
      perform set_config('iara.skip_audit', 'on', true);
      perform iara.compute_queue_priority(x) from unnest(v_ids) x;
      perform set_config('iara.skip_audit', 'off', true);
    else
      -- o critério já usa rota: a pontuação e a posição mudam com a rota calculada
      perform iara.compute_queue_priority(x) from unnest(v_ids) x;
      for q in select distinct preferred_unit_id as u, grade_level_id as g from iara.waiting_list_entries where id = any (v_ids) and status = 'WAITING' loop
        perform iara.recalculate_queue(q.u, q.g);
      end loop;
    end if;
  end if;
  return n;
end $$;
revoke all on function iara.rotas_gravar(jsonb) from public;

-- 5. API ----------------------------------------------------------------------------------------------------
-- as três medidas de um ponto às unidades indicadas (ou às mais próximas); traçados: das duas rotas até uma unidade
-- (`geometria_unidade`) e/ou de uma rota (`geometrias_modo` = A_PE | CARRO) até todas as unidades da lista
create or replace function api.distancias(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, extensions, public
as $$
declare
  v_lat double precision := nullif(p ->> 'lat', '')::double precision;
  v_lng double precision := nullif(p ->> 'lng', '')::double precision;
  v_ids integer[];
  v_n integer := least(greatest(coalesce(nullif(p ->> 'proximas', '')::int, 3), 1), 10);
  v_faixa smallint := nullif(p ->> 'faixa_id', '')::smallint;
  v_geo integer := nullif(p ->> 'geometria_unidade', '')::int;
  v_modo text := case when p ->> 'geometrias_modo' in ('A_PE', 'CARRO') then p ->> 'geometrias_modo' end;
  v_pt extensions.geography;
  r iara.rules := iara.rule('TERRITORIO_2KM');
begin
  if iara.current_user_id() is null then
    raise exception 'Sessão necessária.' using errcode = '42501';
  end if;
  if v_lat is null or v_lng is null or abs(v_lat) > 90 or abs(v_lng) > 180 then
    raise exception 'Informe a origem (latitude e longitude).' using errcode = '22023';
  end if;
  v_pt := iara.point(v_lat, v_lng);
  if jsonb_typeof(p -> 'unidades') = 'array' and jsonb_array_length(p -> 'unidades') > 0 then
    select array_agg(distinct x::int) into v_ids from jsonb_array_elements_text(p -> 'unidades') x;
    v_ids := v_ids[1:12];
  else
    select array_agg(x.id order by x.d) into v_ids from (
      select u.id, st_distance(u.location, v_pt) as d from iara.education_units u
      where u.status = 'ATIVA' and u.location is not null
        and (v_faixa is null or exists (select 1 from iara.classes c where c.unit_id = u.id and c.grade_level_id = v_faixa and c.status = 'ATIVA'))
      order by st_distance(u.location, v_pt) limit v_n) x;
  end if;
  if v_geo is not null and not (v_geo = any (coalesce(v_ids, '{}'))) then
    v_ids := coalesce(v_ids, '{}') || v_geo;
  end if;
  return jsonb_build_object(
    'origem', jsonb_build_object('lat', v_lat, 'lng', v_lng),
    'criterio', jsonb_build_object('medida', iara.medida_distancia_fila(), 'limite_m', coalesce((r.condition ->> 'max_m')::int, 2000),
                                   'regra', r.name, 'versao', r.version),
    'unidades', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'nome', u.name, 'curto', u.short_name, 'tipo', u.unit_type_label,
          'lat', u.lat, 'lng', u.lng,
          'vagas', case when v_faixa is not null then (select coalesce(sum(c.offerable_vacancies_count), 0)::int from iara.classes c
                                                       where c.unit_id = u.id and c.grade_level_id = v_faixa and c.status = 'ATIVA') end)
        || iara.distancias_ponto(v_lat, v_lng, u.id) order by array_position(v_ids, u.id))
      from iara.education_units u where u.id = any (v_ids)), '[]'::jsonb),
    'rotas', case when v_geo is not null then (select jsonb_object_agg(c.modo, c.geometria) from iara.rotas_cache c
                                               where c.origem_lat = iara.c5(v_lat) and c.origem_lng = iara.c5(v_lng)
                                                 and c.unit_id = v_geo and c.geometria is not null) end,
    'trajetos_modo', v_modo,
    'trajetos', case when v_modo is not null then coalesce((select jsonb_object_agg(c.unit_id::text, c.geometria) from iara.rotas_cache c
                                                           where c.origem_lat = iara.c5(v_lat) and c.origem_lng = iara.c5(v_lng)
                                                             and c.unit_id = any (v_ids) and c.modo = v_modo and c.geometria is not null), '{}'::jsonb) end
  );
end $$;

-- pares (casa × unidade pretendida) da fila ativa ainda sem rota — para o cálculo em lote e para a rotina automática
-- do gateway (inscrições novas e mudanças de endereço, por qualquer canal)
create or replace function iara.rotas_pendentes(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = iara, extensions, public
as $$
  with pares as (
    select distinct w.preferred_unit_id as unit_id, iara.c5(st_y(a.location::geometry)) as lat, iara.c5(st_x(a.location::geometry)) as lng
    from iara.waiting_list_entries w
    join iara.students s on s.id = w.student_id
    join iara.addresses a on a.id = s.address_id
    where w.status in ('WAITING', 'OFFERED', 'ACCEPTED') and a.location is not null
  ),
  faltando as (
    select pr.*, m.modo from pares pr cross join (values ('A_PE'), ('CARRO')) m(modo)
    where not exists (select 1 from iara.rotas_cache c where c.origem_lat = pr.lat and c.origem_lng = pr.lng and c.unit_id = pr.unit_id and c.modo = m.modo)
  ),
  grupos as (
    select f.unit_id, f.modo, jsonb_agg(jsonb_build_object('lat', f.lat, 'lng', f.lng)) as origens
    from faltando f group by f.unit_id, f.modo order by f.unit_id, f.modo
    limit least(greatest(coalesce(nullif(p ->> 'unidades', '')::int, 8), 1), 500)
  )
  select jsonb_build_object(
    'pares_total', (select count(*) * 2 from pares), 'pendentes', (select count(*) from faltando),
    'grupos', coalesce((select jsonb_agg(jsonb_build_object('unit_id', g.unit_id, 'modo', g.modo, 'lat', u.lat, 'lng', u.lng, 'origens', g.origens))
                        from grupos g join iara.education_units u on u.id = g.unit_id), '[]'::jsonb))
$$;
revoke all on function iara.rotas_pendentes(jsonb) from public;

create or replace function api.fila_rotas_pendentes(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if not (iara.has_perm('queue.manage') or iara.has_perm('rules.manage')) then
    raise exception 'Seu perfil não pode calcular as rotas da fila.' using errcode = '42501';
  end if;
  return iara.rotas_pendentes(p);
end $$;

-- o que mudaria na fila se o critério de proximidade usasse outra medida (sem alterar nada)
create or replace function api.fila_simular_medida(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_medida text := coalesce(nullif(p ->> 'medida', ''), 'A_PE');
  r iara.rules := iara.rule('TERRITORIO_2KM');
  v_max integer := coalesce((r.condition ->> 'max_m')::int, 2000);
  v_peso numeric := coalesce(r.weight, 0);
begin
  perform iara.require_perm('queue.read');
  if iara.my_scope() not in ('NETWORK', 'AGGREGATE') then
    raise exception 'A simulação olha a rede inteira: disponível para a Secretaria.' using errcode = '42501';
  end if;
  if v_medida not in ('LINHA_RETA', 'A_PE', 'CARRO') then
    raise exception 'Medida inválida.' using errcode = '22023';
  end if;
  return (
    with base as (
      select w.id, w.preferred_unit_id as u, w.grade_level_id as g, w.priority_score as pontos, w.position as posicao, w.entered_at,
             w.dist_reta_m, w.dist_pe_m, w.dist_carro_m, w.student_id,
             coalesce((select (x ->> 'applied')::boolean from jsonb_array_elements(w.score_breakdown) x where x ->> 'code' = 'TERRITORIO_2KM'), false) as aplica_hoje
      from iara.waiting_list_entries w where w.status = 'WAITING'
    ),
    sim as (
      select b.*, case v_medida when 'A_PE' then b.dist_pe_m when 'CARRO' then b.dist_carro_m else b.dist_reta_m end as d_nova
      from base b
    ),
    novo as (
      select s.*, case when s.d_nova is null then s.aplica_hoje else s.d_nova <= v_max end as aplica_nova
      from sim s
    ),
    pont as (
      select n.*, n.pontos - case when n.aplica_hoje then v_peso else 0 end + case when n.aplica_nova then v_peso else 0 end as pontos_novos
      from novo n
    ),
    pos as (
      select t.*, row_number() over (partition by t.u, t.g order by t.pontos_novos desc, t.entered_at) as posicao_nova
      from pont t
    )
    select jsonb_build_object(
      'medida', v_medida, 'medida_atual', iara.medida_distancia_fila(), 'limite_m', v_max, 'peso', v_peso,
      'total', count(*), 'ganham', count(*) filter (where not aplica_hoje and aplica_nova),
      'perdem', count(*) filter (where aplica_hoje and not aplica_nova),
      'sem_rota', count(*) filter (where d_nova is null),
      'mudam_posicao', count(*) filter (where posicao is not null and posicao <> posicao_nova),
      'atende_hoje', count(*) filter (where aplica_hoje), 'atenderia', count(*) filter (where aplica_nova),
      'exemplos', (select coalesce(jsonb_agg(z.j order by z.mov desc), '[]'::jsonb) from (
          select jsonb_build_object('entry_id', x.id, 'crianca', split_part(st.full_name, ' ', 1) || ' ' || left(split_part(st.full_name, ' ', 2), 1) || '.',
                   'unidade', un.short_name, 'faixa', gl.name, 'reta_m', x.dist_reta_m, 'a_pe_m', x.dist_pe_m, 'carro_m', x.dist_carro_m,
                   'aplica_hoje', x.aplica_hoje, 'aplica_nova', x.aplica_nova, 'posicao', x.posicao, 'posicao_nova', x.posicao_nova) as j,
                 abs(coalesce(x.posicao, 0) - x.posicao_nova) as mov
          from pos x join iara.students st on st.id = x.student_id join iara.education_units un on un.id = x.u join iara.grade_levels gl on gl.id = x.g
          where x.aplica_hoje <> x.aplica_nova
          order by abs(coalesce(x.posicao, 0) - x.posicao_nova) desc limit 30) z))
    from pos
  );
end $$;

-- troca da medida do critério (Secretário), com justificativa e auditoria; recalcula todas as filas
create or replace function api.fila_medida_definir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_medida text := nullif(p ->> 'medida', '');
  v_just text := nullif(btrim(coalesce(p ->> 'justificativa', '')), '');
  r iara.rules := iara.rule('TERRITORIO_2KM');
  v_antes text := iara.medida_distancia_fila();
  n integer;
begin
  perform iara.require_perm('rules.manage');
  if v_medida not in ('LINHA_RETA', 'A_PE', 'CARRO') then
    raise exception 'Medida inválida (linha reta, a pé ou de carro).' using errcode = '22023';
  end if;
  if v_just is null or length(v_just) < 10 then
    raise exception 'Registre a justificativa (ex.: decisão, ofício do Ministério Público ou da Defensoria).' using errcode = '22023';
  end if;
  if r.id is null then
    raise exception 'Regra de proximidade não encontrada.' using errcode = 'P0002';
  end if;
  update iara.rules set
    condition = condition || jsonb_build_object('medida', v_medida, 'medida_desde', current_date, 'medida_justificativa', v_just),
    description = format('Residência próxima à unidade de ensino, em até %s km (distância %s entre o endereço cadastrado e a unidade).',
                         replace(round(coalesce((condition ->> 'max_m')::int, 2000) / 1000.0, 1)::text, '.', ','),
                         case v_medida when 'A_PE' then 'a pé, pelo trajeto mais curto pelas ruas e caminhos de pedestres do OpenStreetMap'
                                       when 'CARRO' then 'de carro, pelo trajeto mais rápido nas vias do OpenStreetMap, respeitando a mão de direção'
                                       else 'em linha reta' end)
  where id = r.id;
  n := iara.recalcular_filas();
  perform iara.audit_event('REGRA_MEDIDA_DISTANCIA', 'rules', r.id::text, null,
    format('Critério de proximidade passa a medir %s (antes: %s). Justificativa: %s. %s inscrições recalculadas.',
           iara.medida_rotulo(v_medida), iara.medida_rotulo(v_antes), v_just, n),
    jsonb_build_object('medida', v_medida), jsonb_build_object('medida', v_antes));
  return jsonb_build_object('ok', true, 'medida', v_medida, 'antes', v_antes, 'recalculadas', n);
end $$;

-- lista da fila com as três distâncias de cada inscrição (e a medida que o critério usa)
create or replace function api.queue_list(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security invoker set search_path = iara, public
as $$
  with params as (
    select (p ->> 'unit_id')::int as unit_id, (p ->> 'grade_level_id')::smallint as grade, (p ->> 'territory_id')::int as territory,
           nullif(p ->> 'category', '') as category, nullif(p ->> 'flag', '') as flag, coalesce(nullif(p ->> 'status', ''), 'WAITING') as status, iara.norm(nullif(p ->> 'q', '')) as q,
           greatest(coalesce((p ->> 'page')::int, 1), 1) as page, least(coalesce((p ->> 'page_size')::int, 40), 100) as page_size
  ),
  base as (
    select w.*, u.short_name as unit_name, u.macro_territory_id, s.full_name, s.birth_date, s.avatar_seed, gl.name as grade_name
    from iara.waiting_list_entries w join iara.students s on s.id = w.student_id
    join iara.education_units u on u.id = w.preferred_unit_id join iara.grade_levels gl on gl.id = w.grade_level_id, params x
    where (x.unit_id is null or w.preferred_unit_id = x.unit_id) and (x.grade is null or w.grade_level_id = x.grade)
      and (x.territory is null or u.macro_territory_id = x.territory) and (x.category is null or w.demand_category = x.category)
      and (x.status = 'ALL' or w.status = x.status) and (x.q is null or iara.norm(s.full_name) like '%' || x.q || '%')
      and (x.flag is null or x.flag = any (w.priority_flags))
  )
  select jsonb_build_object(
    'total', (select count(*) from base),
    'criterio_distancia', jsonb_build_object('medida', iara.medida_distancia_fila(),
                                             'limite_m', coalesce(((iara.rule('TERRITORIO_2KM')).condition ->> 'max_m')::int, 2000)),
    'by_category', coalesce((select jsonb_object_agg(demand_category, n) from (select demand_category, count(*) n from base group by 1) z), '{}'::jsonb),
    'by_flag', coalesce((select jsonb_object_agg(f, n) from (select f, count(*) n from base b2, unnest(b2.priority_flags) f group by 1) z), '{}'::jsonb),
    'by_grade', coalesce((select jsonb_object_agg(grade_name, n) from (select grade_name, count(*) n from base group by 1) z), '{}'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', b.id, 'student_id', b.student_id, 'student', b.full_name, 'age', iara.age_text(b.birth_date), 'avatar_seed', b.avatar_seed,
        'unit_id', b.preferred_unit_id, 'unit', b.unit_name, 'grade', b.grade_name, 'grade_level_id', b.grade_level_id,
        'position', b.position, 'score', b.priority_score, 'flags', b.priority_flags, 'category', b.demand_category, 'status', b.status,
        'entered_at', b.entered_at, 'days_waiting', (current_date - b.entered_at::date), 'distance_m', b.home_distance_m,
        'dist', jsonb_build_object('linha_reta_m', b.dist_reta_m, 'a_pe_m', b.dist_pe_m, 'carro_m', b.dist_carro_m, 'medida', b.dist_medida),
        'shift', b.preferred_shift, 'full_time', b.full_time_requested)
        order by b.preferred_unit_id, b.grade_level_id, b.position nulls last, b.entered_at)
      from (select * from base order by unit_name, grade_level_id, position nulls last, entered_at
            offset ((select page from params) - 1) * (select page_size from params) limit (select page_size from params)) b), '[]'::jsonb)
  )
$$;

-- resumo público e anônimo das três medidas na fila (transparência para famílias e controle externo)
create or replace function api.distancias_resumo(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  r iara.rules := iara.rule('TERRITORIO_2KM');
  v_max integer := coalesce((r.condition ->> 'max_m')::int, 2000);
begin
  if iara.current_user_id() is null then
    raise exception 'Sessão necessária.' using errcode = '42501';
  end if;
  return (
    select jsonb_build_object(
      'medida', iara.medida_distancia_fila(), 'limite_m', v_max, 'regra', r.name, 'versao', r.version, 'peso', r.weight,
      'medida_desde', r.condition ->> 'medida_desde', 'medida_justificativa', r.condition ->> 'medida_justificativa',
      'aguardando', count(*),
      'com_rota', count(*) filter (where w.dist_pe_m is not null and w.dist_carro_m is not null),
      'atendem', jsonb_build_object(
        'LINHA_RETA', count(*) filter (where w.dist_reta_m <= v_max),
        'A_PE', count(*) filter (where w.dist_pe_m <= v_max),
        'CARRO', count(*) filter (where w.dist_carro_m <= v_max)),
      'mediana_m', jsonb_build_object(
        'LINHA_RETA', round(percentile_cont(0.5) within group (order by w.dist_reta_m)),
        'A_PE', round(percentile_cont(0.5) within group (order by w.dist_pe_m)),
        'CARRO', round(percentile_cont(0.5) within group (order by w.dist_carro_m))),
      -- quanto o caminho real é maior que a linha reta (média, casas a mais de 300 m da unidade)
      'desvio_pct', jsonb_build_object(
        'A_PE', round(100 * (avg(w.dist_pe_m::numeric / w.dist_reta_m) filter (where w.dist_reta_m > 300 and w.dist_pe_m is not null) - 1)),
        'CARRO', round(100 * (avg(w.dist_carro_m::numeric / w.dist_reta_m) filter (where w.dist_reta_m > 300 and w.dist_carro_m is not null) - 1))),
      'rotas_calculadas_em', (select max(c.calculado_em) from iara.rotas_cache c))
    from iara.waiting_list_entries w where w.status = 'WAITING'
  );
end $$;

-- distâncias registradas nas inscrições já existentes (linha reta agora; rotas quando calculadas)
do $$
begin
  perform set_config('iara.skip_audit', 'on', true);
  update iara.waiting_list_entries w set dist_reta_m = w.home_distance_m, dist_medida = 'LINHA_RETA'
  where w.dist_reta_m is null;
  -- extrato da pontuação com as três distâncias (com o critério em linha reta, a pontuação não muda)
  if iara.medida_distancia_fila() = 'LINHA_RETA' then
    perform iara.compute_queue_priority(w.id) from iara.waiting_list_entries w
    where w.status in ('WAITING', 'OFFERED', 'ACCEPTED')
      and not exists (select 1 from jsonb_array_elements(w.score_breakdown) x where x ->> 'code' = 'TERRITORIO_2KM' and x ? 'distancias');
  end if;
  perform set_config('iara.skip_audit', 'off', true);
end $$;

commit;
