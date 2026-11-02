-- Mapa unificado: todo quesito por área de ponderação e por setor censitário, sigilo pela casa (3+ pessoas; taxa 5+),
-- visitante só nos quesitos públicos, descida para os setores de uma área, setor de cada endereço e manutenção agendada.
-- Roda numa transação revertida (não deixa resíduo). Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/mapas_recortes.sql
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

create or replace function pg_temp.as_anon(p_fn text, p_args jsonb) returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', '{"role": "anon"}', true);
  execute 'set local role anon';
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
  c text;
  rc text;
  v_t0 timestamptz;
  v_tempos jsonb := '{}';
  v_falhas jsonb := '[]';
  v_vazam jsonb := '[]';
  v_ap017 integer := (select id from iara.territories where kind = 'AREA_PONDERACAO' and code = '4115200017');
  v_end uuid;
begin
  perform iara.session_create('PREFEITO', null, 'mr-pref', 'teste');

  -- R1/R2: cada quesito nos dois recortes, sem erro e sem valor pela casa abaixo do mínimo
  foreach c in array array['unidades', 'vagas', 'matriculas', 'fila', 'deficit', 'criancas_0a4', 'pessoas', 'fila_casa',
                           'transporte_necessidade', 'transporte_oferta', 'transporte_efetividade', 'transporte_veiculos',
                           'frequencia', 'faltas', 'ocorrencias', 'alfa_esperado', 'alfa_precoce', 'alfa_abaixo', 'cadastros', 'formacao'] loop
    foreach rc in array array['area', 'setor'] loop
      v_t0 := clock_timestamp();
      r := pg_temp.as_call('mr-pref', 'mapa_recorte', jsonb_build_object('camada', c, 'recorte', rc));
      v_tempos := v_tempos || jsonb_build_object(c || '/' || rc, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);
      if r ->> 'erro' is not null or jsonb_typeof(r -> 'itens') <> 'array' then
        v_falhas := v_falhas || jsonb_build_object('quesito', c || '/' || rc, 'erro', r ->> 'erro');
      elsif (r ->> 'pela_casa')::boolean and exists (
              select 1 from jsonb_array_elements(r -> 'itens') x
              where x ->> 'valor' is not null and (x ->> 'n')::int < (r ->> 'minimo')::int) then
        v_vazam := v_vazam || to_jsonb(c || '/' || rc);
      end if;
    end loop;
  end loop;
  v_out := v_out || jsonb_build_object('passo', 'R1. Os 20 quesitos respondem por área e por setor', 'ok', v_falhas = '[]', 'falhas', v_falhas, 'ms', v_tempos);
  v_out := v_out || jsonb_build_object('passo', 'R2. Pela casa: nenhum território com valor abaixo do mínimo de pessoas', 'ok', v_vazam = '[]', 'vazam', v_vazam);

  -- R3: Censo por área bate com o total do IBGE
  r := pg_temp.as_call('mr-pref', 'mapa_recorte', '{"camada": "criancas_0a4", "recorte": "area"}');
  v_out := v_out || jsonb_build_object('passo', 'R3. Crianças de 0 a 4 anos por área somam 21.656 (Censo 2022)', 'ok', (r ->> 'total')::int = 21656
    and jsonb_array_length(r -> 'itens') = 29, 'total', r ->> 'total');

  -- R4: descida para os setores de uma área
  r := pg_temp.as_call('mr-pref', 'mapa_recorte', jsonb_build_object('camada', 'faltas', 'recorte', 'setor', 'area_id', v_ap017));
  v_out := v_out || jsonb_build_object('passo', 'R4. Setores da AP 017: só os dela', 'ok', r ->> 'erro' is null
    and not exists (select 1 from jsonb_array_elements(r -> 'itens') x
                    where not exists (select 1 from iara.setores_censitarios s where s.code = x ->> 'chave' and s.area_ponderacao_id = v_ap017)),
    'setores', jsonb_array_length(r -> 'itens'));

  -- R5: visitante vê rede e Censo, não vê o que é pela casa
  r := pg_temp.as_anon('mapa_recorte', '{"camada": "deficit", "recorte": "area"}');
  v_out := v_out || jsonb_build_object('passo', 'R5a. Visitante: déficit de creche por área', 'ok', r ->> 'erro' is null and jsonb_array_length(r -> 'itens') > 0, 'erro', r ->> 'erro');
  r := pg_temp.as_anon('mapa_recorte', '{"camada": "faltas", "recorte": "setor"}');
  v_out := v_out || jsonb_build_object('passo', 'R5b. Visitante não vê faltas pela casa (deve negar)', 'ok', r ->> 'erro' is not null and r -> 'itens' is null, 'erro', r ->> 'erro');

  -- R6: setor de cada endereço e gatilho em endereço novo
  v_out := v_out || jsonb_build_object('passo', 'R6a. Todo endereço em Maringá tem setor censitário', 'ok',
    not exists (select 1 from iara.addresses a
                where a.location is not null and a.setor_censitario is null
                  and iara.in_maringa(extensions.st_y(a.location::extensions.geometry), extensions.st_x(a.location::extensions.geometry))),
    'sem_setor', (select count(*) from iara.addresses where location is not null and setor_censitario is null));
  insert into iara.addresses (tenant_id, street, number, neighborhood, location, geocode_precision, geocode_source, is_demo)
  values (1, 'Rua Teste dos Setores', '1', 'Distrito de Iguatemi', iara.point(-23.379225, -52.062136), 'PONTO_NO_MAPA', 'teste', true)
  returning id into v_end;
  v_out := v_out || jsonb_build_object('passo', 'R6b. Endereço novo ganha área e setor pelo ponto (gatilho)', 'ok',
    (select territory_id from iara.addresses where id = v_end) = (select id from iara.territories where code = '4115200001')
    and (select setor_censitario from iara.addresses where id = v_end) is not null,
    'setor', (select setor_censitario from iara.addresses where id = v_end));

  -- R7: manutenção no agendador do banco, uma rotina por job; a chamada do gateway responde na hora
  v_t0 := clock_timestamp();
  r := iara.housekeeping();
  v_out := v_out || jsonb_build_object('passo', 'R7. Manutenção agendada no pg_cron (8 jobs) e chamada do gateway sem trabalho', 'ok',
    (select count(*) from cron.job where jobname like 'iara-manutencao-%' and active) = 8 and (r ->> 'agendado')::boolean,
    'ms', (extract(epoch from clock_timestamp() - v_t0) * 1000)::int,
    'ultimas_execucoes', (select jsonb_agg(jsonb_build_object('job', j.jobname, 'status', d.status, 'ms', round(extract(epoch from d.end_time - d.start_time) * 1000)))
                          from cron.job j join lateral (select * from cron.job_run_details x where x.jobid = j.jobid order by x.start_time desc limit 1) d on true
                          where j.jobname like 'iara-manutencao-%'));

  raise exception 'RESULTADO: %', v_out;
end $$;
