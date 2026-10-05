-- Distâncias por rota (linha reta, a pé, de carro), simulação e troca auditada da medida do critério "até 2 km".
-- Roda numa transação revertida (não deixa resíduo). Pressupõe as rotas da fila já calculadas (POST /rotas/fila).
-- Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/distancias_rota.sql
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
  sim jsonb;
  w iara.waiting_list_entries;
  v_lat double precision;
  v_lng double precision;
  v_pontos_antes numeric;
  v_soma_antes numeric;
  v_n integer;
  v_ex jsonb;
begin
  perform iara.session_create('SECRETARIO', null, 'test-secretario-dist', 'teste');

  -- 1. as três medidas de uma casa da fila, iguais às registradas na inscrição
  select * into w from iara.waiting_list_entries
  where status = 'WAITING' and dist_pe_m is not null and dist_carro_m is not null and dist_reta_m <= 2000 and dist_pe_m > 2000
  order by entered_at limit 1;
  select st_y(a.location::geometry), st_x(a.location::geometry) into v_lat, v_lng
  from iara.students s join iara.addresses a on a.id = s.address_id where s.id = w.student_id;
  r := pg_temp.as_call('test-analista', 'distancias', jsonb_build_object('lat', v_lat, 'lng', v_lng, 'unidades', jsonb_build_array(w.preferred_unit_id)));
  v_out := v_out || jsonb_build_object('passo', '1. Três medidas = as da inscrição',
    'ok', (r #>> '{unidades,0,linha_reta_m}')::int = w.dist_reta_m and (r #>> '{unidades,0,a_pe,distancia_m}')::int = w.dist_pe_m
          and (r #>> '{unidades,0,carro,distancia_m}')::int = w.dist_carro_m,
    'reta', r #> '{unidades,0,linha_reta_m}', 'a_pe', r #> '{unidades,0,a_pe,distancia_m}', 'carro', r #> '{unidades,0,carro,distancia_m}',
    'criterio', r -> 'criterio');

  -- 2. resumo público (família): contagens por medida, sem dados pessoais
  r := pg_temp.as_call('test-cidadao', 'distancias_resumo', '{}');
  v_out := v_out || jsonb_build_object('passo', '2. Resumo público (família)', 'medida', r ->> 'medida', 'aguardando', r -> 'aguardando',
    'com_rota', r -> 'com_rota', 'atendem', r -> 'atendem', 'desvio_pct', r -> 'desvio_pct',
    'ok', (r #>> '{atendem,LINHA_RETA}')::int >= (r #>> '{atendem,A_PE}')::int and r ? 'erro' = false);

  -- 3. simulação (Secretaria): a pé ninguém ganha (caminho ≥ linha reta); quem perde é quem passa de 2 km pela rota
  sim := pg_temp.as_call('test-analista', 'fila_simular_medida', '{"medida": "A_PE"}');
  v_out := v_out || jsonb_build_object('passo', '3. Simulação a pé', 'perdem', sim -> 'perdem', 'ganham', sim -> 'ganham', 'mudam', sim -> 'mudam_posicao',
    'hoje', sim -> 'atende_hoje', 'atenderia', sim -> 'atenderia', 'sem_rota', sim -> 'sem_rota',
    'ok', (sim ->> 'ganham')::int = 0 and (sim ->> 'atende_hoje')::int - (sim ->> 'perdem')::int = (sim ->> 'atenderia')::int
          and (sim ->> 'atende_hoje')::int = (r #>> '{atendem,LINHA_RETA}')::int);

  r := pg_temp.as_call('test-diretor', 'fila_simular_medida', '{"medida": "A_PE"}');
  v_out := v_out || jsonb_build_object('passo', '4. Unidade não simula a rede (deve negar)', 'r', r ->> 'erro');

  r := pg_temp.as_call('test-analista', 'fila_medida_definir', '{"medida": "A_PE", "justificativa": "Teste automatizado da troca"}');
  v_out := v_out || jsonb_build_object('passo', '5. Analista não troca a medida (deve negar)', 'r', r ->> 'erro');

  r := pg_temp.as_call('test-secretario-dist', 'fila_medida_definir', '{"medida": "A_PE", "justificativa": "curta"}');
  v_out := v_out || jsonb_build_object('passo', '6. Troca sem justificativa (deve recusar)', 'r', r ->> 'erro');

  -- 7. Secretário troca para "a pé": todas as filas recalculadas, igual à simulação, com auditoria
  select priority_score into v_pontos_antes from iara.waiting_list_entries where id = w.id;
  select sum(priority_score) into v_soma_antes from iara.waiting_list_entries where status in ('WAITING', 'OFFERED', 'ACCEPTED');
  r := pg_temp.as_call('test-secretario-dist', 'fila_medida_definir',
        '{"medida": "A_PE", "justificativa": "Teste automatizado: recomendação do Ministério Público"}');
  select count(*) into v_n from iara.waiting_list_entries x
  where x.status = 'WAITING' and exists (select 1 from jsonb_array_elements(x.score_breakdown) b where b ->> 'code' = 'TERRITORIO_2KM' and (b ->> 'applied')::boolean);
  select * into w from iara.waiting_list_entries where id = w.id;
  v_ex := sim -> 'exemplos' -> 0;
  v_out := v_out || jsonb_build_object('passo', '7. Secretário passa a medir a pé', 'r', r, 'medida_regra', iara.medida_distancia_fila(),
    'atendem_agora', v_n, 'simulado', sim -> 'atenderia',
    'crianca', jsonb_build_object('pontos_antes', v_pontos_antes, 'pontos_depois', w.priority_score, 'medida', w.dist_medida,
                                  'evidencia', (select b ->> 'evidence' from jsonb_array_elements(w.score_breakdown) b where b ->> 'code' = 'TERRITORIO_2KM')),
    'exemplo_simulado', jsonb_build_object('posicao_nova', v_ex -> 'posicao_nova',
                                           'posicao_real', (select position from iara.waiting_list_entries where id = (v_ex ->> 'entry_id')::uuid)),
    'auditoria', (select count(*) from iara.audit_log where action = 'REGRA_MEDIDA_DISTANCIA' and occurred_at > now() - interval '1 minute'),
    'ok', v_n = (sim ->> 'atenderia')::int and w.priority_score = v_pontos_antes - 15 and w.dist_medida = 'A_PE'
          and (v_ex ->> 'posicao_nova')::int = (select position from iara.waiting_list_entries where id = (v_ex ->> 'entry_id')::uuid));

  -- 8. rota ainda não calculada (casa nova): vale a linha reta, provisoriamente, e a rota entra na fila de cálculo
  delete from iara.rotas_cache where origem_lat = iara.c5(v_lat) and origem_lng = iara.c5(v_lng) and unit_id = w.preferred_unit_id and modo = 'A_PE';
  perform iara.compute_queue_priority(w.id);
  select * into w from iara.waiting_list_entries where id = w.id;
  v_out := v_out || jsonb_build_object('passo', '8. Sem rota: linha reta provisória', 'pontos', w.priority_score,
    'provisoria', (select b -> 'provisoria' from jsonb_array_elements(w.score_breakdown) b where b ->> 'code' = 'TERRITORIO_2KM'),
    'evidencia', (select b ->> 'evidence' from jsonb_array_elements(w.score_breakdown) b where b ->> 'code' = 'TERRITORIO_2KM'),
    'pendentes', iara.rotas_pendentes('{"unidades": 1}') -> 'pendentes');

  -- 9. a rota chega (gateway): pontuação e posição refeitas na hora
  perform iara.rotas_gravar(jsonb_build_object('itens', jsonb_build_array(jsonb_build_object(
    'lat', v_lat, 'lng', v_lng, 'unit_id', w.preferred_unit_id, 'modo', 'A_PE', 'distancia_m', 2600, 'duracao_s', 1900, 'provedor', 'teste'))));
  select * into w from iara.waiting_list_entries where id = w.id;
  v_out := v_out || jsonb_build_object('passo', '9. Rota calculada: critério pela rota', 'pontos', w.priority_score, 'dist_pe_m', w.dist_pe_m,
    'provisoria', (select b -> 'provisoria' from jsonb_array_elements(w.score_breakdown) b where b ->> 'code' = 'TERRITORIO_2KM'),
    'pendentes', iara.rotas_pendentes('{"unidades": 1}') -> 'pendentes',
    'ok', w.dist_pe_m = 2600 and w.priority_score = v_pontos_antes - 15);

  -- 10. volta para a linha reta: as pontuações voltam a ser as de antes
  r := pg_temp.as_call('test-secretario-dist', 'fila_medida_definir', '{"medida": "LINHA_RETA", "justificativa": "Teste automatizado: retorno à redação da IN"}');
  v_out := v_out || jsonb_build_object('passo', '10. Volta à linha reta', 'r', r,
    'soma_antes', v_soma_antes, 'soma_depois', (select sum(priority_score) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED', 'ACCEPTED')),
    'ok', v_soma_antes = (select sum(priority_score) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED', 'ACCEPTED')));

  raise exception 'RESULTADO: %', v_out;  -- reverte tudo
end $$;
