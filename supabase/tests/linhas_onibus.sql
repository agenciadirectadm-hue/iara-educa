-- Linhas de ônibus da unidade: raio, parada mais próxima, atendimento parcial e de fim de semana, e dado não carregado.
-- Roda numa transação revertida, com linhas de teste; não depende da carga real.
-- Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/linhas_onibus.sql
do $$
declare
  v_out jsonb := '[]';
  v_unit iara.education_units;
  r jsonb;
  v_linhas jsonb;
  -- ponto a p_m metros ao norte da unidade (1 grau de latitude ~ 110,7 km aqui)
  v_lat_100 double precision;
  v_lat_400 double precision;
  v_lat_700 double precision;
begin
  select * into v_unit from iara.education_units order by id limit 1;
  v_lat_100 := v_unit.lat + 100 / 110700.0;
  v_lat_400 := v_unit.lat + 400 / 110700.0;
  v_lat_700 := v_unit.lat + 700 / 110700.0;

  delete from iara.onibus_viagem_paradas; delete from iara.onibus_viagens; delete from iara.onibus_paradas; delete from iara.onibus_linhas;

  -- 1. Sem carga: não pode parecer que não há ônibus
  r := api.unit_detail(jsonb_build_object('id', v_unit.id)) -> 'onibus';
  v_out := v_out || jsonb_build_object('passo', '1. Sem carga: atualizado_em nulo e lista vazia', 'ok', (r ->> 'atualizado_em') is null and r -> 'linhas' = '[]'::jsonb);

  insert into iara.onibus_linhas (id, codigo, nome, atualizado_em) values
    ('reg', '100', 'Regular', now()), ('par', '200', 'Parcial', now()), ('fds', '300', 'Fim de semana', now()), ('lon', '400', 'Longe', now());
  insert into iara.onibus_paradas (id, nome, lat, lng, location) values
    ('p100', 'Parada a 100 m', v_lat_100, v_unit.lng, iara.point(v_lat_100, v_unit.lng)),
    ('p400', 'Parada a 400 m', v_lat_400, v_unit.lng, iara.point(v_lat_400, v_unit.lng)),
    ('p700', 'Parada a 700 m', v_lat_700, v_unit.lng, iara.point(v_lat_700, v_unit.lng));
  insert into iara.onibus_viagens (id, linha_id, sentido, descricao, partidas_dia_util) values
    ('reg-ida', 'reg', 0, 'Ida', 20), ('reg-volta', 'reg', 1, 'Volta', 20),   -- só a ida passa: um sentido inteiro basta para ser regular
    ('par-normal', 'par', 0, 'Normal', 18), ('par-via', 'par', 0, 'Via escola', 2),  -- só a variante passa: parcial
    ('fds-ida', 'fds', 0, 'Ida', 0),
    ('lon-ida', 'lon', 0, 'Ida', 30);
  insert into iara.onibus_viagem_paradas (viagem_id, ordem, parada_id) values
    ('reg-ida', 1, 'p400'), ('reg-ida', 2, 'p100'), ('reg-volta', 1, 'p700'),
    ('par-normal', 1, 'p700'), ('par-via', 1, 'p400'),
    ('fds-ida', 1, 'p100'),
    ('lon-ida', 1, 'p700');

  r := api.unit_detail(jsonb_build_object('id', v_unit.id)) -> 'onibus';
  v_linhas := r -> 'linhas';

  v_out := v_out || jsonb_build_object('passo', '2. Parada fora do raio de 500 m não conta', 'ok',
    not exists (select 1 from jsonb_array_elements(v_linhas) e where e ->> 'codigo' = '400'), 'linhas', v_linhas);
  v_out := v_out || jsonb_build_object('passo', '3. Mostra a parada mais próxima da linha, com a distância', 'ok',
    exists (select 1 from jsonb_array_elements(v_linhas) e where e ->> 'codigo' = '100' and e ->> 'parada' = 'Parada a 100 m' and (e ->> 'distancia_m')::int between 95 and 105));
  v_out := v_out || jsonb_build_object('passo', '4. Um sentido inteiro passando é atendimento regular', 'ok',
    exists (select 1 from jsonb_array_elements(v_linhas) e where e ->> 'codigo' = '100' and e ->> 'atendimento' = 'REGULAR' and (e ->> 'partidas_dia_util')::int = 20));
  v_out := v_out || jsonb_build_object('passo', '5. Só uma variante com poucas partidas é atendimento parcial', 'ok',
    exists (select 1 from jsonb_array_elements(v_linhas) e where e ->> 'codigo' = '200' and e ->> 'atendimento' = 'PARCIAL' and (e ->> 'partidas_dia_util')::int = 2));
  v_out := v_out || jsonb_build_object('passo', '6. Sem partida em dia útil é só fim de semana, e vai para o fim da lista', 'ok',
    v_linhas -> -1 ->> 'codigo' = '300' and v_linhas -> -1 ->> 'atendimento' = 'FIM_DE_SEMANA');
  v_out := v_out || jsonb_build_object('passo', '7. Link oficial da linha', 'ok',
    v_linhas -> 0 ->> 'url' like 'https://bus2.info/reports/2you/43wpt?route=%');

  -- 8. A coordenada manda: mudou a unidade de lugar, as linhas acompanham
  v_linhas := iara.onibus_perto(iara.point(v_lat_700 + 100 / 110700.0, v_unit.lng)) -> 'linhas';
  v_out := v_out || jsonb_build_object('passo', '8. As linhas acompanham a coordenada', 'ok',
    exists (select 1 from jsonb_array_elements(v_linhas) e where e ->> 'codigo' = '400')
    and not exists (select 1 from jsonb_array_elements(v_linhas) e where e ->> 'codigo' = '300'));

  -- 9. Visitante sem login vê pela ficha pública, mas não abre as tabelas nem a função direto
  v_out := v_out || jsonb_build_object('passo', '9. Visitante só pela ficha pública', 'ok',
    has_function_privilege('anon', 'api.unit_detail(jsonb)', 'execute')
    and not has_function_privilege('anon', 'iara.onibus_perto(extensions.geography, integer)', 'execute')
    and not has_table_privilege('anon', 'iara.onibus_paradas', 'select')
    and not has_table_privilege('anon', 'iara.onibus_linhas', 'select')
    and not has_table_privilege('authenticated', 'iara.onibus_viagens', 'insert'));

  execute 'set local role anon';
  r := api.unit_detail(jsonb_build_object('id', v_unit.id)) -> 'onibus';
  execute 'reset role';
  v_out := v_out || jsonb_build_object('passo', '10. Visitante sem login recebe as linhas na ficha', 'ok', jsonb_array_length(r -> 'linhas') = 3);

  raise exception 'RESULTADO: %', v_out;  -- reverte tudo
end $$;
