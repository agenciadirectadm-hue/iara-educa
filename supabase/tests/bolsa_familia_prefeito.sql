-- Bolsa Família na escola (Prefeito): só números; soma fecha (assíduos + abaixo em 1 + abaixo em 2 ou mais = acompanhados);
-- bate com o Sistema Presença no mesmo período; assunto no Oráculo; sigilo dos recortes; acessos.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/bolsa_familia_prefeito.sql
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
  r jsonb; r2 jsonb; r3 jsonb;
  v_t0 timestamptz;
  v_ms integer;
  v_nome text;
begin
  perform iara.session_create('PREFEITO', null, 'bf-pref', 'teste');
  perform iara.session_create('SECRETARIO', null, 'bf-sec', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', null, 'bf-dir', 'teste');

  v_t0 := clock_timestamp();
  r := pg_temp.as_call('bf-pref', 'bolsa_familia_resumo', '{"ano": 2026}');
  v_ms := (extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
  v_out := v_out || jsonb_build_object('passo', 'F1. Prefeito: alunos do Bolsa Família, deixaram de receber (abaixo do mínimo) e assíduos; a soma fecha', 'ok',
    r ->> 'erro' is null and (r ->> 'alunos')::int > 1000 and (r ->> 'familias')::int > 500
    and (r ->> 'acompanhados')::int <= (r ->> 'alunos')::int
    and (r ->> 'assiduos')::int + (r ->> 'abaixo_1')::int + (r ->> 'abaixo_2')::int = (r ->> 'acompanhados')::int
    and (r ->> 'deixaram_de_receber')::int = (r ->> 'abaixo_1')::int + (r ->> 'abaixo_2')::int
    and jsonb_array_length(r -> 'periodos') = 5,
    'numeros', r - 'por_regiao' - 'unidades_mais_abaixo' - 'nota' - 'rotulos', 'ms', v_ms, 'erro', r ->> 'erro');

  -- mesmo período, mesma conta do Sistema Presença
  r2 := pg_temp.as_call('bf-sec', 'presenca_rede', '{"ano": 2026, "periodo": 4}');
  v_out := v_out || jsonb_build_object('passo', 'F2. Bate com o Sistema Presença: abaixo do mínimo em agosto e setembro', 'ok',
    (r2 -> 'total' ->> 'abaixo')::int = (select (x ->> 'abaixo')::int from jsonb_array_elements(r -> 'periodos') x where (x ->> 'periodo')::int = 4),
    'presenca', r2 -> 'total' ->> 'abaixo', 'resumo', (select x from jsonb_array_elements(r -> 'periodos') x where (x ->> 'periodo')::int = 4));

  -- só números: nenhum nome de aluno nem identificador; recortes com menos de 3 em sigilo
  select s.full_name into v_nome from iara.students s join iara.student_guardians sg on sg.student_id = s.id join iara.guardians g on g.id = sg.guardian_id
  where g.benefits ? 'Bolsa Família' limit 1;
  v_out := v_out || jsonb_build_object('passo', 'F3. Sem nome nem identificador de aluno; regiões e unidades com 3 ou mais', 'ok',
    position(v_nome in r::text) = 0 and r::text !~ '[0-9a-f]{8}-[0-9a-f]{4}-'
    and not exists (select 1 from jsonb_array_elements(r -> 'por_regiao') x where (x ->> 'acompanhados')::int < 3 or (x ->> 'abaixo')::int between 1 and 2)
    and not exists (select 1 from jsonb_array_elements(r -> 'unidades_mais_abaixo') x where (x ->> 'abaixo')::int < 3)
    and jsonb_array_length(r -> 'por_regiao') > 5);

  -- Oráculo: o assunto novo, por consulta e por pergunta
  r2 := pg_temp.as_call('bf-pref', 'oraculo_dados', '{"topico": "bolsa_familia"}');
  r3 := pg_temp.as_call('bf-pref', 'oraculo_perguntar', '{"pergunta": "Quantos alunos do Bolsa Família ficaram abaixo da frequência mínima?"}');
  v_out := v_out || jsonb_build_object('passo', 'F4. Oráculo responde sobre o Bolsa Família (consulta e pergunta)', 'ok',
    r2 ->> 'erro' is null and jsonb_array_length(r2 -> 'numeros') = 5 and (r2 -> 'numeros' -> 0 ->> 'valor')::int = (r ->> 'alunos')::int
    and r3 ->> 'topico' = 'bolsa_familia',
    'resposta', r3 ->> 'resposta', 'erro', coalesce(r2 ->> 'erro', r3 ->> 'erro'));

  -- acessos
  r := pg_temp.as_call('bf-dir', 'bolsa_familia_resumo', '{}');
  r2 := pg_temp.as_call('bf-sec', 'bolsa_familia_resumo', '{}');
  v_t0 := clock_timestamp();
  r3 := pg_temp.as_call('bf-pref', 'bolsa_familia_resumo', '{"ano": 2026}');
  v_ms := (extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
  v_out := v_out || jsonb_build_object('passo', 'F6. Segunda abertura vem da conta guardada (rápida) e igual à primeira', 'ok',
    v_ms < 500 and (r3 ->> 'alunos') = (pg_temp.as_call('bf-pref', 'bolsa_familia_resumo', '{"ano": 2026, "atualizar": true}') ->> 'alunos'),
    'ms', v_ms);
  v_out := v_out || jsonb_build_object('passo', 'F5. Secretaria vê; direção de unidade não', 'ok', r ->> 'codigo' = '42501' and r2 ->> 'erro' is null);

  raise exception 'RESULTADO: %', v_out;
end $$;
