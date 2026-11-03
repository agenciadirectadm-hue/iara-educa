-- Bolsa Família na escola: mapa (regiões e unidades com código e sigilo) e detalhe da unidade (períodos e motivos).
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/bolsa_familia_mapa.sql
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
  r jsonb; r2 jsonb;
  v_unit integer;
begin
  perform iara.session_create('PREFEITO', null, 'bfm-pref', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', null, 'bfm-dir', 'teste');
  r := pg_temp.as_call('bfm-pref', 'bolsa_familia_resumo', '{"ano": 2026, "atualizar": true}');
  select (x ->> 'id')::int into v_unit from jsonb_array_elements(r -> 'mapa_unidades') x where (x ->> 'abaixo')::int >= 3 order by (x ->> 'abaixo')::int desc limit 1;
  v_out := v_out || jsonb_build_object('passo', 'M1. Mapa: todas as regiões e unidades com código; sigilo abaixo de 3; soma das regiões = cidade', 'ok',
    jsonb_array_length(r -> 'mapa_regioes') >= 20 and jsonb_array_length(r -> 'mapa_unidades') > 50
    and not exists (select 1 from jsonb_array_elements(r -> 'mapa_unidades') x where (x ->> 'acompanhados')::int < 3 or (x ->> 'abaixo')::int between 1 and 2)
    and not exists (select 1 from jsonb_array_elements(r -> 'mapa_unidades') x where x ? 'acompanhados' and x -> 'abaixo' = 'null'::jsonb and x -> 'taxa' <> 'null'::jsonb)
    and (select sum(coalesce((x ->> 'acompanhados')::int, 0)) from jsonb_array_elements(r -> 'mapa_regioes') x) <= (r ->> 'acompanhados')::int
    and (select sum(coalesce((x ->> 'acompanhados')::int, 0)) from jsonb_array_elements(r -> 'mapa_regioes') x) > (r ->> 'acompanhados')::int * 0.95,
    'regioes', jsonb_array_length(r -> 'mapa_regioes'), 'unidades', jsonb_array_length(r -> 'mapa_unidades'), 'erro', r ->> 'erro');

  r := pg_temp.as_call('bfm-pref', 'bolsa_familia_unidade', jsonb_build_object('unit_id', v_unit));
  r2 := pg_temp.as_call('bfm-dir', 'bolsa_familia_unidade', jsonb_build_object('unit_id', v_unit));
  v_out := v_out || jsonb_build_object('passo', 'M2. Detalhe da unidade: ano, períodos e motivos do último período; só números; direção não acessa', 'ok',
    r ->> 'erro' is null and jsonb_array_length(r -> 'periodos') = 5 and (r ->> 'motivos_periodo')::int = 4
    and jsonb_typeof(r -> 'motivos') = 'array' and r::text !~ '[0-9a-f]{8}-[0-9a-f]{4}-'
    and not exists (select 1 from jsonb_array_elements(r -> 'periodos') x where (x ->> 'abaixo')::int between 1 and 2)
    and r2 ->> 'codigo' = '42501',
    'unidade', r -> 'unidade' ->> 'nome', 'motivos', r -> 'motivos', 'erro', r ->> 'erro');
  -- motivos das faltas: ano, bimestre, tipo e faixa; a soma das categorias fecha com o total
  r := pg_temp.as_call('bfm-pref', 'bolsa_familia_motivos', '{"ano": 2026}');
  r2 := pg_temp.as_call('bfm-pref', 'bolsa_familia_motivos', '{"ano": 2026, "periodo": 4, "tipo": "ESCOLA", "faixa": "6-10"}');
  v_out := v_out || jsonb_build_object('passo', 'M3. Motivos das faltas: categorias somam o total; recorte por bimestre, tipo e faixa reduz', 'ok',
    r ->> 'erro' is null and (r ->> 'total_faltas')::int > 1000
    and (select sum((x ->> 'faltas')::int) from jsonb_array_elements(r -> 'categorias') x) + (r ->> 'grupos_pequenos')::int = (r ->> 'total_faltas')::int
    and (r2 ->> 'total_faltas')::int between 1 and (r ->> 'total_faltas')::int - 1 and (r2 ->> 'alunos')::int < (r ->> 'alunos')::int
    and pg_temp.as_call('bfm-pref', 'bolsa_familia_motivos', '{"faixa": "99"}') ->> 'codigo' = '22023'
    and pg_temp.as_call('bfm-dir', 'bolsa_familia_motivos', '{}') ->> 'codigo' = '42501',
    'ano', r - 'de' - 'ate', 'recorte', r2 -> 'total_faltas', 'erro', coalesce(r ->> 'erro', r2 ->> 'erro'));
  -- camadas do mapa (095): reincidência e faltas sem justificativa, com a mesma conta da pizza
  r := pg_temp.as_call('bfm-pref', 'bolsa_familia_resumo', '{"ano": 2026, "atualizar": true}');
  r2 := pg_temp.as_call('bfm-pref', 'bolsa_familia_motivos', '{"ano": 2026}');
  v_out := v_out || jsonb_build_object('passo', 'M4. Camadas diferentes: reincidência ≤ deixaram de receber; faltas sem justificativa batem com a pizza', 'ok',
    not exists (select 1 from jsonb_array_elements(r -> 'mapa_unidades') x where x ? 'acompanhados' and not (x ? 'taxa_2' and x ? 'taxa_sem_just'))
    and not exists (select 1 from jsonb_array_elements(r -> 'mapa_unidades') x where (x ->> 'taxa_2')::numeric > (x ->> 'taxa')::numeric)
    and not exists (select 1 from jsonb_array_elements(r -> 'mapa_unidades') x where x -> 'abaixo_2' = 'null'::jsonb and x -> 'taxa_2' <> 'null'::jsonb)
    and (select sum((x ->> 'sem_justificativa')::int) from jsonb_array_elements(r -> 'mapa_unidades') x where x ? 'sem_justificativa')
        <= (select (c ->> 'faltas')::int from jsonb_array_elements(r2 -> 'categorias') c where c ->> 'categoria' = 'SEM_JUSTIFICATIVA')
    and (select sum((x ->> 'sem_justificativa')::int) from jsonb_array_elements(r -> 'mapa_unidades') x where x ? 'sem_justificativa')
        > 0.95 * (select (c ->> 'faltas')::int from jsonb_array_elements(r2 -> 'categorias') c where c ->> 'categoria' = 'SEM_JUSTIFICATIVA'),
    'exemplo', (select x from jsonb_array_elements(r -> 'mapa_regioes') x where x ? 'taxa_2' limit 1));
  raise exception 'RESULTADO: %', v_out;
end $$;
