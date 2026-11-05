-- Oráculo abrangente: todo indicador do catálogo roda na cidade, numa unidade e numa região; todo tema responde; perguntas caem no
-- assunto certo; situações pontuais sem dado de pessoa; comparações; estatística de nomes com sigilo; recusa de dado de pessoa; acessos.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/oraculo_abrangente.sql
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
  i iara.oraculo_indicadores;
  v_falhas text[] := '{}';
  v_unit integer := (select e.unit_id from iara.enrollments e where e.status = 'ACTIVE' group by 1 order by count(*) desc limit 1);
  v_area integer := (select macro_territory_id from iara.education_units where id = (select e.unit_id from iara.enrollments e where e.status = 'ACTIVE' group by 1 order by count(*) desc limit 1));
  v_units_area integer[];
  v_todas integer[] := array(select id from iara.education_units);
  v_t0 timestamptz;
  v_lento text; v_ms integer; v_max integer := 0;
  c record;
  v_nome text;
  v_primeiro text;
  v_certo integer;
  q record;
begin
  perform iara.session_create('PREFEITO', null, 'oa-pref', 'teste');
  perform iara.session_create('SECRETARIO', null, 'oa-sec', 'teste');
  v_units_area := array(select id from iara.education_units where macro_territory_id = v_area);

  -- A1: todo indicador roda nos três recortes, e nenhum passa de 3 s
  for i in select * from iara.oraculo_indicadores order by chave loop
    begin
      v_t0 := clock_timestamp();
      perform iara.oraculo_valor(i.consulta, v_todas, true);
      v_ms := (extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
      if v_ms > v_max then v_max := v_ms; v_lento := i.chave; end if;
      perform iara.oraculo_valor(i.consulta, array[v_unit], false);
      perform iara.oraculo_valor(i.consulta, v_units_area, false);
    exception when others then
      v_falhas := v_falhas || (i.chave || ': ' || left(sqlerrm, 120));
    end;
  end loop;
  v_out := v_out || jsonb_build_object('passo', 'A1. Todos os indicadores rodam na cidade, na unidade e na região', 'ok',
    cardinality(v_falhas) = 0 and (select count(*) from iara.oraculo_indicadores) >= 70 and v_max < 3000,
    'indicadores', (select count(*) from iara.oraculo_indicadores), 'falhas', to_jsonb(v_falhas), 'mais_lento', v_lento, 'ms', v_max);

  -- A2: todo tema responde pela ferramenta, com números na cidade
  v_falhas := '{}';
  for c in select tema from iara.oraculo_temas loop
    r := pg_temp.as_call('oa-pref', 'oraculo_dados', jsonb_build_object('topico', c.tema));
    if r ->> 'erro' is not null or jsonb_array_length(coalesce(r -> 'numeros', '[]')) = 0 then v_falhas := v_falhas || (c.tema || ': ' || coalesce(r ->> 'erro', 'sem números')); end if;
  end loop;
  r := pg_temp.as_call('oa-pref', 'oraculo_indicadores', '{}');
  v_out := v_out || jsonb_build_object('passo', 'A2. Todos os temas respondem; a lista do que o Oráculo sabe está completa', 'ok',
    cardinality(v_falhas) = 0 and jsonb_array_length(r -> 'temas') = (select count(*) from iara.oraculo_temas), 'falhas', to_jsonb(v_falhas));

  -- A3: perguntas caem no assunto certo
  v_falhas := '{}';
  for q in select * from (values
    ('Quantos chamados de manutenção estão abertos?', 'manutencao'),
    ('Quantos protocolos estão vencidos?', 'atendimento'),
    ('Como está a merenda?', 'nutricao'),
    ('Quantas crianças têm obesidade?', 'nutricao'),
    ('Quantos livros estão emprestados?', 'biblioteca'),
    ('Qual a média das notas?', 'desempenho'),
    ('Quantos alunos têm plano de AEE?', 'aee'),
    ('Quantos encaminhamentos ao Conselho Tutelar temos?', 'protecao'),
    ('Quantos veículos estão com a vistoria vencida?', 'transporte_det'),
    ('Quantas rematrículas estão pendentes?', 'rematricula'),
    ('Quantos itens estão abaixo do estoque mínimo?', 'almoxarifado'),
    ('Quantos casos de bullying tivemos?', 'ocorrencias_tipo'),
    ('Quantos professores estão de licença?', 'ponto'),
    ('Quantos moradores tem a cidade pelo censo?', 'territorio'),
    ('Quantas ofertas de vaga vencem hoje?', 'ofertas'),
    ('O que está acontecendo na rede?', 'situacoes'),
    ('Qual escola tem mais ocorrências?', 'ranking'),
    ('Quantas crianças esperam vaga na creche?', 'creche'),
    ('Como está a frequência?', 'frequencia'),
    ('Quantos alunos do Bolsa Família ficaram abaixo da frequência mínima?', 'bolsa_familia'),
    ('Quantas crianças se chamam Silvio?', 'nomes')) t(pergunta, esperado) loop
    r := pg_temp.as_call('oa-pref', 'oraculo_perguntar', jsonb_build_object('pergunta', q.pergunta));
    if coalesce(r ->> 'topico', '-') <> q.esperado or r ->> 'erro' is not null then
      v_falhas := v_falhas || (q.pergunta || ' → ' || coalesce(r ->> 'topico', '-') || coalesce(' ERRO ' || (r ->> 'erro'), ''));
    end if;
  end loop;
  v_out := v_out || jsonb_build_object('passo', 'A3. As perguntas caem no assunto certo', 'ok', cardinality(v_falhas) = 0, 'falhas', to_jsonb(v_falhas));

  -- A4: situações pontuais: sem identificador nem nome de pessoa; recorte por unidade não traz o que é só da cidade
  r := pg_temp.as_call('oa-pref', 'oraculo_situacoes', '{}');
  r2 := pg_temp.as_call('oa-pref', 'oraculo_situacoes', jsonb_build_object('unidade', v_unit));
  v_out := v_out || jsonb_build_object('passo', 'A4. Situações pontuais sem dado de pessoa; a unidade vê só o dela', 'ok',
    r ->> 'erro' is null and jsonb_array_length(r -> 'situacoes') > 0 and r::text !~ '[0-9a-f]{8}-[0-9a-f]{4}-'
    and r2 ->> 'erro' is null and not exists (select 1 from jsonb_array_elements(r2 -> 'situacoes') x where x ->> 'unidade' is not null
        and x ->> 'unidade' <> (select iara.oraculo_rotulo_unidade(unit_type, short_name) from iara.education_units where id = v_unit))
    and not exists (select 1 from jsonb_array_elements(r2 -> 'situacoes') x where x ->> 'texto' like '%sensíve%'),
    'exemplos', (select jsonb_agg(x) from (select x from jsonb_array_elements(r -> 'situacoes') x limit 6) q), 'total', jsonb_array_length(r -> 'situacoes'), 'erro', coalesce(r ->> 'erro', r2 ->> 'erro'));

  -- A5: comparação em ordem certa e com sigilo
  r := pg_temp.as_call('oa-pref', 'oraculo_ranking', '{"indicador": "base.ocorrencias", "por": "unidade", "ordem": "maior", "limite": 5}');
  r2 := pg_temp.as_call('oa-pref', 'oraculo_ranking', '{"indicador": "base.fila", "por": "regiao", "limite": 30}');
  r3 := pg_temp.as_call('oa-pref', 'oraculo_ranking', '{"indicador": "indicador.errado"}');
  v_out := v_out || jsonb_build_object('passo', 'A5. Comparações: ordem certa; indicador de pessoas só de 3 para cima; indicador inválido recusado', 'ok',
    jsonb_array_length(r -> 'lista') = 5 and (r -> 'lista' -> 0 ->> 'valor')::numeric >= (r -> 'lista' -> 4 ->> 'valor')::numeric
    and not exists (select 1 from jsonb_array_elements(r2 -> 'lista') x where (x ->> 'valor')::numeric < 3) and r3 ->> 'codigo' = '22023',
    'top', r -> 'lista' -> 0, 'erro', r ->> 'erro');

  -- A6: nomes: conta certo, sigilo, uma palavra só, e nunca mostra quem é; dado de pessoa é recusado
  select s.full_name into v_nome from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' where e.unit_id = v_unit limit 1;
  v_primeiro := split_part(v_nome, ' ', 1);
  v_certo := (select count(distinct st.id) from iara.students st join iara.enrollments e on e.student_id = st.id and e.status = 'ACTIVE'
              where iara.norm(st.full_name) ~ ('\m' || iara.norm(v_primeiro) || '\M'));
  r := pg_temp.as_call('oa-pref', 'oraculo_nomes', jsonb_build_object('nome', v_primeiro));
  r2 := pg_temp.as_call('oa-pref', 'oraculo_nomes', jsonb_build_object('nome', 'Fulano De Tal'));
  r3 := pg_temp.as_call('oa-pref', 'oraculo_perguntar', jsonb_build_object('pergunta', 'Qual o telefone da família de ' || v_nome || '?'));
  v_out := v_out || jsonb_build_object('passo', 'A6. Nomes: contagem certa, um nome por vez, sem identificar; telefone de família é recusado', 'ok',
    (r ->> 'total')::int = v_certo and r2 ->> 'codigo' = '22023' and (r3 ->> 'fora')::boolean and position(v_nome in (r3 - 'pergunta')::text) = 0,
    'nome', v_primeiro, 'total', r ->> 'total', 'recusa', left(r3 ->> 'resposta', 70));

  -- sigilo: um nome com 1 ou 2 pessoas não mostra o número
  select nm into v_primeiro from (select split_part(iara.norm(st.full_name), ' ', 1) nm, count(distinct st.id) n from iara.students st
    join iara.enrollments e on e.student_id = st.id and e.status = 'ACTIVE' group by 1 having count(distinct st.id) between 1 and 2 limit 1) z;
  if v_primeiro is not null and length(v_primeiro) >= 3 and v_primeiro ~ '^[a-z]+$' and iara.oraculo_contar_nome(v_primeiro, 'ALUNOS', v_todas, true) between 1 and 2 then
    r := pg_temp.as_call('oa-pref', 'oraculo_nomes', jsonb_build_object('nome', v_primeiro));
    v_out := v_out || jsonb_build_object('passo', 'A7. Nome raro: número em sigilo', 'ok', (r ->> 'sigilo')::boolean and r ->> 'total' is null);
  else
    v_out := v_out || jsonb_build_object('passo', 'A7. Nome raro: número em sigilo (sem nome raro na demonstração)', 'ok', true);
  end if;

  -- A8: acessos
  r := pg_temp.as_call('oa-sec', 'oraculo_situacoes', '{}');
  r2 := pg_temp.as_call('oa-sec', 'oraculo_nomes', '{"nome": "Silvio"}');
  r3 := pg_temp.as_call('oa-sec', 'oraculo_ranking', '{"indicador": "base.fila"}');
  v_out := v_out || jsonb_build_object('passo', 'A8. Só o Prefeito acessa', 'ok', r ->> 'codigo' = '42501' and r2 ->> 'codigo' = '42501' and r3 ->> 'codigo' = '42501');

  -- A9: dado ainda não lançado não vira zero
  if not exists (select 1 from iara.antropometria where zscore is not null) then
    r := pg_temp.as_call('oa-pref', 'oraculo_perguntar', '{"pergunta": "Quantas crianças têm obesidade?"}');
    r2 := pg_temp.as_call('oa-pref', 'oraculo_dados', '{"topico": "nutricao"}');
    v_out := v_out || jsonb_build_object('passo', 'A9. Dado não lançado não vira zero', 'ok',
      position('tabela oficial da OMS' in r ->> 'resposta') > 0 and position('excesso de peso' in lower((r2 -> 'numeros')::text)) = 0,
      'resposta', left(r ->> 'resposta', 120));
  else
    v_out := v_out || jsonb_build_object('passo', 'A9. Dado não lançado não vira zero (há classificação lançada)', 'ok', true);
  end if;

  raise exception 'RESULTADO: %', v_out;
end $$;
