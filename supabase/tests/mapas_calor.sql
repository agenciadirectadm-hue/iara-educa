-- Mapas de calor da visão do prefeito: cada camada responde para o prefeito, nada sai por pessoa e quem não tem a permissão não vê.
-- Roda numa transação revertida (não deixa resíduo). Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/mapas_calor.sql
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
  c text;
  v_t0 timestamptz;
  v_ms integer;
  v_pontos integer;
  v_chaves text[];
begin
  perform iara.session_create('PREFEITO', null, 'mc-pref', 'teste');
  perform iara.session_create('PROFESSOR', (select id from iara.education_units where status = 'ATIVA' order by id limit 1), 'mc-prof', 'teste');
  foreach c in array array['transporte_necessidade', 'transporte_oferta', 'transporte_efetividade', 'transporte_veiculos', 'frequencia', 'faltas', 'ocorrencias',
                           'alfa_esperado', 'alfa_precoce', 'alfa_abaixo', 'cadastros', 'formacao'] loop
    v_t0 := clock_timestamp();
    r := pg_temp.as_call('mc-pref', 'mapa_calor', jsonb_build_object('camada', c));
    v_ms := (extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
    v_pontos := jsonb_array_length(coalesce(r -> 'pontos', '[]'));
    -- nenhum ponto traz identificador de pessoa: só lat, lng, valor, título e cor
    select array_agg(distinct k) into v_chaves from jsonb_array_elements(coalesce(r -> 'pontos', '[]')) x, jsonb_object_keys(x) k;
    v_out := v_out || jsonb_build_object('passo', 'Camada ' || c, 'ok', r ->> 'erro' is null and v_pontos > 0 and r ->> 'modo' in ('densidade', 'taxa')
             and (r ->> 'modo' = 'densidade' or jsonb_array_length(r -> 'escala') = 5) and jsonb_array_length(r -> 'resumo') >= 3
             and v_chaves <@ array['lat', 'lng', 'valor', 'titulo', 'cor'],
             'pontos', v_pontos, 'ms', v_ms, 'resumo', r -> 'resumo', 'ranking1', r -> 'ranking' -> 'itens' -> 0, 'erro', r ->> 'erro');
  end loop;

  -- células da casa da criança: nenhuma com menos de 3 crianças
  r := pg_temp.as_call('mc-pref', 'mapa_calor', '{"camada": "transporte_necessidade"}');
  v_out := v_out || jsonb_build_object('passo', 'Necessidade de transporte: só células com 3+ crianças', 'ok',
           not exists (select 1 from jsonb_array_elements(r -> 'pontos') x where (x ->> 'valor')::int < 3));

  -- cadastros: escala de 95 (vermelho) a 100 (azul)
  r := pg_temp.as_call('mc-pref', 'mapa_calor', '{"camada": "cadastros"}');
  v_out := v_out || jsonb_build_object('passo', 'Cadastros: escala 95 vermelho → 100 azul', 'ok',
           (r -> 'escala' -> 0 ->> 0)::numeric = 95 and r -> 'escala' -> 0 ->> 1 = '#dc2626' and (r -> 'escala' -> 4 ->> 0)::numeric = 100 and r -> 'escala' -> 4 ->> 1 = '#1d4ed8',
           'pendencias', r -> 'pendencias');

  -- formação: níveis padronizados
  v_out := v_out || jsonb_build_object('passo', 'Formação: texto livre vira nível', 'ok',
           iara.formacao_nivel('Pós-graduação') = 4 and iara.formacao_nivel('Especialização') = 4 and iara.formacao_nivel('Mestrado') = 5
           and iara.formacao_nivel('Magistério (nível médio)') = 1 and iara.formacao_nivel('Superior incompleto') = 2 and iara.formacao_nivel('Superior completo') = 3
           and iara.formacao_nivel('Doutorado') = 6 and iara.formacao_nivel(null) is null);

  -- alfabetização × idade
  v_out := v_out || jsonb_build_object('passo', 'Alfabetização: precoce, esperado e abaixo pela idade', 'ok',
           iara.alfa_situacao_idade('ALFABETICO', 80) = 'PRECOCE' and iara.alfa_situacao_idade('SILABICO_ALFABETICO', 75) = 'PRECOCE'
           and iara.alfa_situacao_idade('ALFABETICO', 88) = 'ESPERADO' and iara.alfa_situacao_idade('SILABICO_COM_VALOR', 90) = 'ABAIXO'
           and iara.alfa_situacao_idade('PRE_SILABICO', 74) = 'ESPERADO' and iara.alfa_situacao_idade('SILABICO_ALFABETICO', 100) = 'ABAIXO');

  -- quem não tem a visão da rede não vê
  r := pg_temp.as_call('mc-prof', 'mapa_calor', '{"camada": "cadastros"}');
  v_out := v_out || jsonb_build_object('passo', 'Professor não acessa os mapas de calor', 'ok', r ->> 'codigo' = '42501', 'erro', r ->> 'erro');
  r := pg_temp.as_call('mc-pref', 'mapa_calor', '{"camada": "inexistente"}');
  v_out := v_out || jsonb_build_object('passo', 'Camada desconhecida é recusada', 'ok', r ->> 'codigo' = '22023');

  raise exception 'RESULTADO: %', v_out;
end $$;
