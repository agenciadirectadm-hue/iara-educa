-- IARA Educa — 059 · Transporte: trajeto de cada rota pelas ruas (motor de rotas OSRM)
-- O trajeto é calculado fora do banco (script/gateway, só coordenadas saem para o motor) e guardado por trecho: do ponto k ao
-- ponto k+1 e do último ponto até a escola. Com ele, os quilômetros e os horários de cada ponto passam a vir do caminho real
-- (tempo do motor × 1,25 para o veículo escolar + 1 min por parada), o veículo simulado anda pelas ruas e o mapa geral ganha a
-- camada das rotas. Sem trajeto, tudo continua funcionando em linha reta.
begin;

alter table iara.transporte_rotas add column if not exists trajeto jsonb;
alter table iara.transporte_rotas add column if not exists trajeto_fonte text;
alter table iara.transporte_rotas add column if not exists trajeto_em timestamptz;

-- trechos: [{"c": [[lng, lat], ...], "m": metros, "s": segundos}], um por ponto (o último termina na escola);
-- p_ordem (opcional): os pontos na ordem otimizada pelo motor (serviço trip), que passa a ser a ordem da rota
drop function if exists iara.rota_aplicar_trajeto(uuid, jsonb, text);
create or replace function iara.rota_aplicar_trajeto(p_rota uuid, p_trechos jsonb, p_fonte text default 'OSRM · OpenStreetMap', p_ordem uuid[] default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r iara.transporte_rotas;
  v_n integer;
  k integer;
  v_acum integer := 0;
  v_seg integer;
begin
  select * into r from iara.transporte_rotas where id = p_rota for update;
  if r.id is null then raise exception 'Rota não encontrada.' using errcode = 'P0002'; end if;
  select count(*) into v_n from iara.transporte_pontos where rota_id = r.id;
  if jsonb_typeof(p_trechos) <> 'array' or jsonb_array_length(p_trechos) <> v_n then
    raise exception 'O trajeto precisa de um trecho por ponto (% pontos, % trechos).', v_n, jsonb_array_length(p_trechos) using errcode = '22023';
  end if;
  perform set_config('iara.skip_audit', 'on', true);
  if p_ordem is not null then
    if cardinality(p_ordem) <> v_n or exists (select 1 from unnest(p_ordem) x where not exists (select 1 from iara.transporte_pontos where id = x and rota_id = r.id)) then
      raise exception 'A nova ordem precisa ter todos os pontos da rota.' using errcode = '22023';
    end if;
    update iara.transporte_pontos set ordem = -ordem where rota_id = r.id;
    update iara.transporte_pontos pt set ordem = o.k, nome = regexp_replace(pt.nome, '\(ponto [0-9]+\)$', '(ponto ' || o.k || ')')
    from unnest(p_ordem) with ordinality o(id, k) where pt.id = o.id;
  end if;
  -- de trás para frente: o ponto k é atendido antes dos trechos k..n até a escola
  for k in reverse v_n..1 loop
    v_seg := round(coalesce((p_trechos -> (k - 1) ->> 's')::numeric, 0) * 1.25)::int + 60;
    v_acum := v_acum + v_seg;
    update iara.transporte_pontos set horario_ida = date_trunc('minute', r.chegada_ida - make_interval(secs => v_acum))::time,
           horario_volta = date_trunc('minute', r.saida_volta + make_interval(secs => v_acum))::time
    where rota_id = r.id and ordem = k;
  end loop;
  update iara.transporte_rotas set trajeto = p_trechos, trajeto_fonte = p_fonte, trajeto_em = now(),
         km = round((select sum((t ->> 'm')::numeric) from jsonb_array_elements(p_trechos) t) / 1000, 1)
  where id = r.id;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('rota', r.codigo, 'km', (select km from iara.transporte_rotas where id = r.id), 'minutos', round(v_acum / 60.0));
end $$;

-- ponto a uma fração f (0..1) do comprimento de uma linha [[lng, lat], ...]; ao contrário quando é a volta
create or replace function iara.ponto_na_linha(p_c jsonb, p_f double precision, p_rev boolean default false) returns jsonb
language plpgsql immutable as $$
declare
  n integer := jsonb_array_length(p_c);
  pts double precision[][] := '{}';
  tot double precision := 0;
  alvo double precision;
  acc double precision := 0;
  d double precision;
  i integer;
  a double precision[];
  b double precision[];
  x jsonb;
begin
  if n is null or n = 0 then return null; end if;
  if n = 1 then return jsonb_build_object('lng', (p_c -> 0 ->> 0)::float8, 'lat', (p_c -> 0 ->> 1)::float8); end if;
  for i in 0..n - 1 loop
    x := p_c -> (case when p_rev then n - 1 - i else i end);
    pts := pts || array[array[(x ->> 0)::float8, (x ->> 1)::float8]];
  end loop;
  for i in 1..n - 1 loop
    tot := tot + iara.km_entre(pts[i][2], pts[i][1], pts[i + 1][2], pts[i + 1][1]);
  end loop;
  alvo := greatest(least(p_f, 1), 0) * tot;
  for i in 1..n - 1 loop
    d := iara.km_entre(pts[i][2], pts[i][1], pts[i + 1][2], pts[i + 1][1]);
    if acc + d >= alvo or i = n - 1 then
      a := array[pts[i][1], pts[i][2]]; b := array[pts[i + 1][1], pts[i + 1][2]];
      return jsonb_build_object('lng', a[1] + (b[1] - a[1]) * case when d > 0 then (alvo - acc) / d else 0 end,
                                'lat', a[2] + (b[2] - a[2]) * case when d > 0 then (alvo - acc) / d else 0 end);
    end if;
    acc := acc + d;
  end loop;
  return null;
end $$;

-- estado de hoje: igual à 055, mas a posição segue o trajeto pelas ruas quando ele existe
create or replace function iara.transporte_estado(p_rota uuid, p_sentido text) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  r iara.transporte_rotas;
  v iara.transporte_viagens;
  u record;
  v_hoje date := iara.hoje_local();
  v_now time := iara.agora_local();
  v_atraso integer;
  h integer;
  pts record;
  t time[] := '{}';
  la double precision[] := '{}';
  lo double precision[] := '{}';
  nm text[] := '{}';
  n integer;
  i integer;
  f double precision;
  v_pos jsonb;
begin
  select * into r from iara.transporte_rotas where id = p_rota;
  if r.id is null then return null; end if;
  select lat, lng, short_name into u from iara.education_units where id = r.unit_id;
  if not iara.dia_letivo(v_hoje, r.unit_id) then return jsonb_build_object('sentido', p_sentido, 'situacao', 'SEM_AULA'); end if;
  select * into v from iara.transporte_viagens where rota_id = r.id and data = v_hoje and sentido = p_sentido;
  if v.id is not null and v.situacao = 'NAO_REALIZADA' then
    return jsonb_build_object('sentido', p_sentido, 'situacao', 'NAO_REALIZADA', 'motivo', v.motivo, 'registrada', true);
  end if;
  h := abs(hashtext(r.id::text || v_hoje::text || p_sentido)) % 100;
  v_atraso := coalesce(v.atraso_min, case when h < 80 then h % 5 when h < 95 then 6 + h % 9 else 15 + h % 16 end);
  if p_sentido = 'IDA' then
    for pts in select * from iara.transporte_pontos where rota_id = r.id order by ordem loop
      t := t || (pts.horario_ida + make_interval(mins => v_atraso)); la := la || pts.lat; lo := lo || pts.lng; nm := nm || pts.nome;
    end loop;
    t := t || (r.chegada_ida + make_interval(mins => v_atraso)); la := la || u.lat; lo := lo || u.lng; nm := nm || u.short_name;
  else
    t := t || (r.saida_volta + make_interval(mins => v_atraso)); la := la || u.lat; lo := lo || u.lng; nm := nm || u.short_name;
    for pts in select * from iara.transporte_pontos where rota_id = r.id order by ordem desc loop
      t := t || (pts.horario_volta + make_interval(mins => v_atraso)); la := la || pts.lat; lo := lo || pts.lng; nm := nm || pts.nome;
    end loop;
  end if;
  n := cardinality(t);
  if v.id is not null and v.situacao = 'CONCLUIDA' or v_now >= t[n] then
    return jsonb_build_object('sentido', p_sentido, 'situacao', 'CONCLUIDA', 'atraso_min', v_atraso, 'inicio', t[1], 'fim', t[n],
      'registrada', v.id is not null, 'simulada', v.id is null, 'substituicao', coalesce(v.substituicao, false));
  end if;
  if v_now < t[1] - interval '15 minutes' and v.id is null then
    return jsonb_build_object('sentido', p_sentido, 'situacao', 'PREVISTA', 'atraso_min', 0, 'inicio', t[1] - make_interval(mins => v_atraso), 'fim', t[n] - make_interval(mins => v_atraso));
  end if;
  if v_now < t[1] then
    i := 1; f := 0;
  else
    i := 1;
    while i < n and v_now >= t[i + 1] loop i := i + 1; end loop;
    f := extract(epoch from (v_now - t[i])) / greatest(extract(epoch from (t[i + 1] - t[i])), 1);
  end if;
  -- pelo trajeto: na ida o trecho i é o i-ésimo; na volta, o trecho (n - i) percorrido ao contrário
  if r.trajeto is not null and jsonb_array_length(r.trajeto) = n - 1 then
    v_pos := iara.ponto_na_linha(r.trajeto -> (case when p_sentido = 'IDA' then i - 1 else n - 1 - i end) -> 'c', f, p_sentido = 'VOLTA');
  end if;
  v_pos := coalesce(v_pos, jsonb_build_object('lat', la[i] + (la[i + 1] - la[i]) * f, 'lng', lo[i] + (lo[i + 1] - lo[i]) * f));
  return jsonb_build_object('sentido', p_sentido, 'situacao', 'EM_ANDAMENTO', 'atraso_min', v_atraso, 'inicio', t[1], 'fim', t[n],
    'registrada', v.id is not null, 'simulada', true, 'substituicao', coalesce(v.substituicao, false),
    'posicao', v_pos || jsonb_build_object('atualizado_em', now(), 'fonte', 'Simulada pelo horário planejado (sem GPS integrado)'),
    'proximo', jsonb_build_object('nome', nm[i + 1], 'previsto', t[i + 1]));
end $$;

-- linha única do trajeto (para desenhar): concatena os trechos
create or replace function iara.rota_linha(r iara.transporte_rotas) returns jsonb
language sql stable as $$
  select case when r.trajeto is null then null
              else (select jsonb_agg(c order by t.o, c.o) from jsonb_array_elements(r.trajeto) with ordinality t(x, o),
                    jsonb_array_elements(t.x -> 'c') with ordinality c(c, o)) end
$$;

-- mapa geral: todas as rotas que o perfil pode ver, com o trajeto e o veículo agora
create or replace function api.transporte_mapa(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
begin
  perform iara.require_perm('transporte.read');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'codigo', r.codigo, 'nome', r.nome, 'unidade', u.short_name, 'unit_id', r.unit_id,
      'turno', r.turno, 'alunos', (select count(*) from iara.transporte_alunos a where a.rota_id = r.id and a.fim is null), 'km', r.km,
      'escola', jsonb_build_object('lat', u.lat, 'lng', u.lng),
      'paradas', (select coalesce(jsonb_agg(jsonb_build_array(pt.lng, pt.lat) order by pt.ordem), '[]') from iara.transporte_pontos pt where pt.rota_id = r.id),
      'ida', jsonb_build_object('inicio', (select min(pt.horario_ida) from iara.transporte_pontos pt where pt.rota_id = r.id), 'chegada', r.chegada_ida),
      'linha', coalesce(iara.rota_linha(r), (select jsonb_agg(jsonb_build_array(pt.lng, pt.lat) order by pt.ordem) from iara.transporte_pontos pt where pt.rota_id = r.id)
                                          || jsonb_build_array(jsonb_build_array(u.lng, u.lat))),
      'pelas_ruas', r.trajeto is not null,
      'agora', iara.transporte_estado(r.id, case when iara.agora_local() < r.saida_volta - interval '20 minutes' then 'IDA' else 'VOLTA' end))
      order by r.codigo), '[]')
    from iara.transporte_rotas r join iara.education_units u on u.id = r.unit_id
    where r.situacao = 'ATIVA' and (v_unit is null or r.unit_id = v_unit) and iara.can_access_unit(r.unit_id)
      and (nullif(p ->> 'turno', '') is null or r.turno = p ->> 'turno'));
end $$;

-- a rota passa a devolver o trajeto
create or replace function iara.rota_trajeto_json(p_rota uuid) returns jsonb
language sql stable security definer set search_path = iara, public
as $$ select jsonb_build_object('trajeto', iara.rota_linha(r), 'trajeto_fonte', r.trajeto_fonte, 'trajeto_em', r.trajeto_em) from iara.transporte_rotas r where r.id = p_rota $$;

revoke all on function iara.rota_aplicar_trajeto(uuid, jsonb, text, uuid[]) from public;

commit;
