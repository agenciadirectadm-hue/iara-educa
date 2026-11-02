-- Áreas de ponderação como recorte territorial: 29 áreas do IBGE (Censo 2022), nenhuma macrorregião restante, unidades,
-- endereços, bairros, fila e órgãos reorganizados, distritos dentro da AP 001 e camadas públicas do mapa.
-- Roda numa transação revertida (não deixa resíduo). Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/areas_ponderacao.sql
create or replace function pg_temp.as_call(p_hash text, p_fn text, p_args jsonb) returns jsonb language plpgsql as $f$
declare
  v_uid uuid := (select user_id from iara.app_sessions where token_hash = p_hash);
  v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute format('select api.%I($1)', p_fn) into v using p_args;
  execute 'reset role';
  return v;
exception when others then
  execute 'reset role';
  return jsonb_build_object('erro', sqlerrm, 'codigo', sqlstate);
end $f$;

do $$
declare
  v_out jsonb := '[]';
  r jsonb;
  v_ap001 integer := (select id from iara.territories where kind = 'AREA_PONDERACAO' and code = '4115200001');
  v_ap017 integer := (select id from iara.territories where kind = 'AREA_PONDERACAO' and code = '4115200017');
  v_lista jsonb;
begin
  perform iara.session_create('PREFEITO', null, 'ap-pref', 'teste');

  v_out := v_out || jsonb_build_object('passo', 'A1. 29 áreas, 793 setores, 409.657 moradores e nenhuma macrorregião', 'ok',
    (select count(*) from iara.territories where kind = 'AREA_PONDERACAO') = 29
    and (select count(*) from iara.setores_censitarios) = 793
    and (select sum(pessoas) from iara.setores_censitarios) = 409657
    and not exists (select 1 from iara.territories where kind = 'MACRORREGIAO'));

  select coalesce(jsonb_agg(u.short_name), '[]') into v_lista from iara.education_units u
  left join iara.territories t on t.id = u.macro_territory_id
  where t.kind is distinct from 'AREA_PONDERACAO';
  v_out := v_out || jsonb_build_object('passo', 'A2. Toda unidade está numa área de ponderação', 'ok', v_lista = '[]', 'lista', v_lista,
    'fora_do_poligono', (select count(*) from iara.education_units u join iara.territories t on t.id = u.macro_territory_id
                         where not extensions.st_covers(t.geom, u.location)));

  -- a área que contém o ponto ou, na fresta da malha simplificada, a mais próxima a até 150 m (iara.area_do_ponto)
  v_out := v_out || jsonb_build_object('passo', 'A3. Endereço com ponto em Maringá tem a área do ponto', 'ok',
    not exists (select 1 from iara.addresses a
                where a.location is not null and iara.in_maringa(extensions.st_y(a.location::extensions.geometry), extensions.st_x(a.location::extensions.geometry))
                  and a.territory_id is distinct from iara.area_do_ponto(a.location)),
    'sem_area', (select count(*) from iara.addresses a where a.location is not null and a.territory_id is null),
    'na_fresta', (select count(*) from iara.addresses a join iara.territories t on t.id = a.territory_id
                  where not extensions.st_covers(t.geom, a.location)),
    'longe_de_toda_area', (select count(*) from iara.addresses a
                           where a.location is not null and a.territory_id is null
                             and iara.in_maringa(extensions.st_y(a.location::extensions.geometry), extensions.st_x(a.location::extensions.geometry))));

  v_out := v_out || jsonb_build_object('passo', 'A4. Fila, bairros e órgãos só apontam para áreas', 'ok',
    not exists (select 1 from iara.waiting_list_entries w join iara.territories t on t.id = w.territory_id where t.kind <> 'AREA_PONDERACAO')
    and not exists (select 1 from iara.territories b join iara.territories p on p.id = b.parent_id where b.kind = 'BAIRRO' and p.kind <> 'AREA_PONDERACAO')
    and not exists (select 1 from iara.orgaos_destinatarios o, unnest(o.territorio_ids) x
                    where not exists (select 1 from iara.territories t where t.id = x and t.kind = 'AREA_PONDERACAO')));

  v_out := v_out || jsonb_build_object('passo', 'A5. Iguatemi e Floriano: distritos dentro da AP 001, com limite, moradores e unidades', 'ok',
    (select count(*) from iara.territories where kind = 'DISTRITO' and parent_id = v_ap001 and geom is not null) = 2
    and (select bool_and((iara.censo_territorio(id) ->> 'pessoas')::int > 0) from iara.territories where kind = 'DISTRITO')
    and (select count(*) from iara.unidades_do_territorio((select id from iara.territories where code = 'IGUATEMI'))) > 0,
    'distritos', (select jsonb_agg(jsonb_build_object('nome', name, 'censo', iara.censo_territorio(id),
                                   'unidades', (select count(*) from iara.unidades_do_territorio(t.id))))
                  from iara.territories t where kind = 'DISTRITO'));

  r := pg_temp.as_call(null, 'geo_layers', '{}');
  v_out := v_out || jsonb_build_object('passo', 'A6. Camadas públicas: 29 áreas com o Censo e os 2 distritos', 'ok', r ->> 'erro' is null
    and jsonb_array_length(r -> 'regions' -> 'features') = 29
    and (select sum((f -> 'properties' ->> 'criancas_0a4')::int) from jsonb_array_elements(r -> 'regions' -> 'features') f) = 21656
    and jsonb_array_length(r -> 'districts' -> 'features') = 2, 'erro', r ->> 'erro');

  r := pg_temp.as_call(null, 'geo_setores', '{}');
  v_out := v_out || jsonb_build_object('passo', 'A7. Setores: 793 no município, só os da área quando filtrado', 'ok', r ->> 'erro' is null
    and jsonb_array_length(r -> 'features') = 793
    and (select bool_and((f -> 'properties' ->> 'area_id')::int = v_ap017)
         from jsonb_array_elements(pg_temp.as_call(null, 'geo_setores', jsonb_build_object('area_id', v_ap017)) -> 'features') f),
    'erro', r ->> 'erro');

  r := pg_temp.as_call(null, 'territory_detail', jsonb_build_object('id', v_ap001));
  v_out := v_out || jsonb_build_object('passo', 'A8. Ficha da AP 001: Censo, distritos e unidades', 'ok', r ->> 'erro' is null
    and (r -> 'censo' ->> 'pessoas')::int = 16422 and jsonb_array_length(r -> 'districts') = 2 and jsonb_array_length(r -> 'units') > 0,
    'censo', r -> 'censo', 'erro', r ->> 'erro');

  -- ponto da Escola Municipal Dona Angelina L. Meneguetti, no distrito de Iguatemi
  r := iara.localizar(-23.379225, -52.062136);
  v_out := v_out || jsonb_build_object('passo', 'A9. Endereço em Iguatemi: AP 001 e distrito', 'ok',
    (r ->> 'territorio_id')::int = v_ap001 and r ->> 'territorio_tipo' = 'AREA_PONDERACAO' and r ->> 'distrito' = 'Distrito de Iguatemi', 'ponto', r);

  r := pg_temp.as_call('ap-pref', 'dashboard_prefeito', '{}');
  v_out := v_out || jsonb_build_object('passo', 'A10. Painel do prefeito por área: 29 áreas com pressão e crianças de 0 a 4 anos', 'ok', r ->> 'erro' is null
    and jsonb_array_length(r -> 'regions') = 29
    and not exists (select 1 from jsonb_array_elements(r -> 'regions') x where x ->> 'pressure' is null or x ->> 'criancas_0a4' is null),
    'pressao', (select jsonb_object_agg(p, n) from (select x ->> 'pressure' p, count(*) n from jsonb_array_elements(r -> 'regions') x group by 1) z),
    'saldo_creche_min_max', jsonb_build_array((select min((x ->> 'balance_creche')::int) from jsonb_array_elements(r -> 'regions') x),
                                              (select max((x ->> 'balance_creche')::int) from jsonb_array_elements(r -> 'regions') x)),
    'erro', r ->> 'erro');

  r := pg_temp.as_call(null, 'geo_search', '{"q": "ap 017"}');
  v_out := v_out || jsonb_build_object('passo', 'A11. Busca acha a área pelo número', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'items') x where x ->> 'kind' = 'AREA' and (x ->> 'territory_id')::int = v_ap017));

  raise exception 'RESULTADO: %', v_out;
end $$;
