-- Sistema Presença (MEC): frequência do Bolsa Família por período, conferida contra a chamada; mínimo pela idade; motivo
-- sugerido; recesso de 50% ou mais dá integral; marcação de lançado; visão da rede; acessos.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/sistema_presenca.sql
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
  v_unit integer := (iara.setting('demo_unit_maria'))::int;
  v_escola integer;
  a jsonb;
  v_aluno uuid;
  v_classe uuid;
  v_dias integer; v_faltas integer; v_pct numeric;
  v_t0 timestamptz;
  v_ms integer;
begin
  -- unidade com alunos de 6 anos ou mais (escola), para o mínimo de 75%
  select e.unit_id into v_escola from iara.enrollments e join iara.education_units u on u.id = e.unit_id
  where e.status = 'ACTIVE' and u.unit_type = 'ESCOLA' group by 1 order by count(*) desc limit 1;
  perform iara.session_create('SECRETARIA_ESCOLAR', v_escola, 'sp-sec', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_unit, 'sp-dir', 'teste');
  perform iara.session_create('SECRETARIO', null, 'sp-seduc', 'teste');
  perform iara.session_create('PREFEITO', null, 'sp-pref', 'teste');

  r := pg_temp.as_call('sp-sec', 'presenca_periodos', '{}');
  r2 := pg_temp.as_call('sp-sec', 'presenca_unidade', '{"ano": 2026, "periodo": 4}');
  a := r2 -> 'alunos' -> 0;
  v_out := v_out || jsonb_build_object('passo', 'S1. Períodos e lista da unidade: alunos do Bolsa Família com 4 a 17 anos, dois meses cada', 'ok',
    r ->> 'erro' is null and jsonb_array_length(r -> 'periodos') = 5 and r2 ->> 'erro' is null
    and (r2 -> 'resumo' ->> 'alunos')::int > 10 and jsonb_array_length(a -> 'meses') = 2
    and not exists (select 1 from jsonb_array_elements(r2 -> 'alunos') x where (x ->> 'idade')::int < 4 or (x ->> 'idade')::int > 17)
    and not exists (select 1 from jsonb_array_elements(r2 -> 'alunos') x where (x ->> 'minimo')::int <> case when (x ->> 'idade')::int < 6 then 60 else 75 end),
    'atual', r -> 'atual', 'resumo', r2 -> 'resumo', 'erro', coalesce(r ->> 'erro', r2 ->> 'erro'));

  -- o percentual de setembro de um aluno, conferido direto na chamada
  v_aluno := (a ->> 'student_id')::uuid;
  select class_id into v_classe from iara.enrollments where student_id = v_aluno and status = 'ACTIVE';
  select count(*) into v_dias from iara.frequencia_registros where class_id = v_classe and data between '2026-09-01' and '2026-09-30';
  select count(*) into v_faltas from iara.frequencia_faltas f join iara.frequencia_registros r0 on r0.id = f.registro_id
  where f.student_id = v_aluno and r0.class_id = v_classe and r0.data between '2026-09-01' and '2026-09-30';
  v_pct := round(100.0 * (v_dias - v_faltas) / nullif(v_dias, 0), 1);
  v_out := v_out || jsonb_build_object('passo', 'S2. Percentual do mês = dias com chamada menos faltas, sobre os dias com chamada', 'ok',
    (a -> 'meses' -> 1 ->> 'pct')::numeric = v_pct and (a -> 'meses' -> 1 ->> 'dias')::int = v_dias,
    'setembro', a -> 'meses' -> 1, 'conferido', jsonb_build_array(v_dias, v_faltas, v_pct));

  -- abaixo do mínimo: faltas justificadas por doença → motivo sugerido "doença"; com busca ativa aberta, ela prevalece
  insert into iara.frequencia_faltas (registro_id, student_id, tipo, justificativa, is_demo)
  select r0.id, v_aluno, 'FALTA_JUSTIFICADA', 'Criança com virose', true from iara.frequencia_registros r0
  where r0.class_id = v_classe and r0.data between '2026-09-01' and '2026-09-20'
  on conflict (registro_id, student_id) do update set tipo = 'FALTA_JUSTIFICADA', justificativa = 'Criança com virose';
  r := pg_temp.as_call('sp-sec', 'presenca_unidade', '{"ano": 2026, "periodo": 4}');
  select x into a from jsonb_array_elements(r -> 'alunos') x where x ->> 'student_id' = v_aluno::text;
  insert into iara.busca_ativa_casos (student_id, unit_id, origem, motivo_abertura, situacao) values (v_aluno, v_escola, 'MANUAL', 'Teste', 'ABERTO')
  on conflict do nothing;
  r2 := pg_temp.as_call('sp-sec', 'presenca_unidade', '{"ano": 2026, "periodo": 4}');
  select x into r3 from jsonb_array_elements(r2 -> 'alunos') x where x ->> 'student_id' = v_aluno::text;
  v_out := v_out || jsonb_build_object('passo', 'S3. Abaixo do mínimo: motivo sugerido pela justificativa (doença); busca ativa aberta prevalece', 'ok',
    (a -> 'meses' -> 1 ->> 'pct')::numeric < 75 and a -> 'motivo' ->> 'categoria' = 'DOENCA'
    and r3 -> 'motivo' ->> 'categoria' = 'BUSCA_ATIVA' and (r2 -> 'resumo' ->> 'abaixo')::int >= 1,
    'motivo', a -> 'motivo', 'com_busca_ativa', r3 -> 'motivo' ->> 'categoria');

  -- recesso de metade do mês ou mais: frequência integral
  insert into iara.calendario_eventos (titulo, tipo, inicio, fim, abrangencia, suspende_aulas, is_demo)
  values ('Recesso de teste', 'RECESSO', '2026-09-01', '2026-09-30', 'REDE', true, true);
  r := pg_temp.as_call('sp-sec', 'presenca_unidade', '{"ano": 2026, "periodo": 4}');
  v_out := v_out || jsonb_build_object('passo', 'S4. Recesso de 50% ou mais dos dias do mês: frequência integral (100%)', 'ok',
    not exists (select 1 from jsonb_array_elements(r -> 'alunos') x where (x -> 'meses' -> 1 ->> 'pct')::numeric <> 100 or not (x -> 'meses' -> 1 ->> 'integral')::boolean));
  delete from iara.calendario_eventos where titulo = 'Recesso de teste';

  -- lançado no Sistema Presença: marca, aparece no resumo, desmarca
  r := pg_temp.as_call('sp-sec', 'presenca_lancar', jsonb_build_object('student_id', v_aluno, 'ano', 2026, 'periodo', 4, 'lancado', true));
  r2 := pg_temp.as_call('sp-sec', 'presenca_unidade', '{"ano": 2026, "periodo": 4, "exportar": true}');
  r3 := pg_temp.as_call('sp-sec', 'presenca_lancar', jsonb_build_object('student_id', v_aluno, 'ano', 2026, 'periodo', 4, 'lancado', false));
  v_out := v_out || jsonb_build_object('passo', 'S5. Marcar como lançado (e desmarcar); a planilha gerada fica na auditoria', 'ok',
    r ->> 'ok' = 'true' and (r2 -> 'resumo' ->> 'lancados')::int = 1 and r3 ->> 'ok' = 'true'
    and not exists (select 1 from iara.presenca_lancamentos where student_id = v_aluno)
    and exists (select 1 from iara.audit_log where action = 'PRESENCA_PLANILHA' and entity_id = v_escola::text));

  -- rede: todas as unidades, com o tempo da consulta
  v_t0 := clock_timestamp();
  r := pg_temp.as_call('sp-seduc', 'presenca_rede', '{"ano": 2026, "periodo": 4}');
  v_ms := (extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
  r2 := pg_temp.as_call('sp-seduc', 'presenca_unidade', jsonb_build_object('unit_id', v_unit, 'ano', 2026, 'periodo', 4));
  v_out := v_out || jsonb_build_object('passo', 'S6. Secretaria vê a rede (por unidade) e abre qualquer unidade', 'ok',
    r ->> 'erro' is null and jsonb_array_length(r -> 'unidades') > 50 and (r -> 'total' ->> 'alunos')::int > 1000 and r2 ->> 'erro' is null,
    'total', r -> 'total', 'unidades', jsonb_array_length(r -> 'unidades'), 'ms', v_ms, 'erro', coalesce(r ->> 'erro', r2 ->> 'erro'));

  -- acessos
  r := pg_temp.as_call('sp-pref', 'presenca_unidade', '{}');
  r2 := pg_temp.as_call('sp-dir', 'presenca_lancar', jsonb_build_object('student_id', v_aluno, 'ano', 2026, 'periodo', 4, 'lancado', true));
  r3 := pg_temp.as_call('sp-dir', 'presenca_rede', '{}');
  v_out := v_out || jsonb_build_object('passo', 'S7. Prefeito não vê; direção não marca aluno de outra unidade nem vê a rede', 'ok',
    r ->> 'codigo' = '42501' and r2 ->> 'codigo' = '42501' and r3 ->> 'codigo' = '42501');

  raise exception 'RESULTADO: %', v_out;
end $$;
