-- Oráculo que explica: todo detalhe e todo fato rodam nos três recortes; as perguntas reais do Prefeito têm a resposta certa; sigilo; sem
-- texto livre nem nome de pessoa; cardápio com refeições; pergunta sem assunto é avisada; só o Prefeito acessa.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/oraculo_detalhes.sql
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
  d iara.oraculo_detalhes;
  f iara.oraculo_fatos;
  a iara.oraculo_assuntos;
  v_falhas text[] := '{}';
  v_unit integer := (select e.unit_id from iara.enrollments e where e.status = 'ACTIVE' group by 1 order by count(*) desc limit 1);
  v_area integer := (select macro_territory_id from iara.education_units where id = (select e.unit_id from iara.enrollments e where e.status = 'ACTIVE' group by 1 order by count(*) desc limit 1));
  v_units_area integer[];
  v_todas integer[] := array(select id from iara.education_units);
  v_t0 timestamptz;
  v_lento text; v_ms integer; v_max integer := 0; v_ms_ap integer; v_max_ap integer := 0; v_lento_ap text;
  v_hoje date := iara.hoje_local();
  v_txt text;
  v_nome text;
  q record;
begin
  perform iara.session_create('PREFEITO', null, 'od-pref', 'teste');
  perform iara.session_create('SECRETARIO', null, 'od-sec', 'teste');
  v_units_area := array(select id from iara.education_units where macro_territory_id = v_area);

  -- D1: todo detalhe roda nos três recortes em menos de 3 s
  for d in select * from iara.oraculo_detalhes order by chave loop
    begin
      v_t0 := clock_timestamp();
      perform iara.oraculo_detalhe_lista(d.chave, v_todas, true, 8);
      v_ms := (extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
      if v_ms > v_max then v_max := v_ms; v_lento := d.chave; end if;
      perform iara.oraculo_detalhe_lista(d.chave, array[v_unit], false, 8);
      perform iara.oraculo_detalhe_lista(d.chave, v_units_area, false, 8);
    exception when others then
      v_falhas := v_falhas || (d.chave || ': ' || left(sqlerrm, 140));
    end;
  end loop;
  v_out := v_out || jsonb_build_object('passo', 'D1. Todos os detalhes rodam na cidade, na unidade e na região, em menos de 3 s', 'ok',
    cardinality(v_falhas) = 0 and v_max < 3000 and (select count(*) from iara.oraculo_detalhes) >= 60,
    'detalhes', (select count(*) from iara.oraculo_detalhes), 'falhas', to_jsonb(v_falhas), 'mais_lento', v_lento, 'ms', v_max);

  -- D2: todo fato roda nos três recortes, em todos os períodos
  v_falhas := '{}'; v_max := 0;
  for f in select * from iara.oraculo_fatos order by chave loop
    begin
      v_t0 := clock_timestamp();
      perform iara.oraculo_fato_valor(f.chave, v_todas, true, v_hoje - 30, v_hoje);
      v_ms := (extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
      if v_ms > v_max then v_max := v_ms; v_lento := f.chave; end if;
      perform iara.oraculo_fato_valor(f.chave, array[v_unit], false, v_hoje, v_hoje);
      perform iara.oraculo_fato_valor(f.chave, v_units_area, false, v_hoje - 1, v_hoje - 1);
    exception when others then
      v_falhas := v_falhas || (f.chave || ': ' || left(sqlerrm, 140));
    end;
  end loop;
  for q in select * from (values ('hoje'), ('ontem'), ('anteontem'), ('semana'), ('semana_passada'), ('mes'), ('mes_passado'), ('ano'), ('ultimos_7')) t(c) loop
    r := pg_temp.as_call('od-pref', 'oraculo_periodo', jsonb_build_object('fato', 'ocorrencias', 'periodo', q.c));
    if r ->> 'erro' is not null then v_falhas := v_falhas || (q.c || ': ' || (r ->> 'erro')); end if;
  end loop;
  v_out := v_out || jsonb_build_object('passo', 'D2. Todos os fatos rodam nos três recortes e em todos os períodos, em menos de 3 s', 'ok',
    cardinality(v_falhas) = 0 and v_max < 3000 and (select count(*) from iara.oraculo_fatos) >= 12,
    'falhas', to_jsonb(v_falhas), 'mais_lento', v_lento, 'ms', v_max);

  -- D3: todo assunto aprofunda sem erro, e o ranking e os indicadores que ele cita existem
  v_falhas := '{}';
  for a in select * from iara.oraculo_assuntos order by ordem loop
    begin
      v_t0 := clock_timestamp();
      r := iara.oraculo_aprofundar(a.assunto, null, null, 4);
      v_ms_ap := (extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
      if v_ms_ap > v_max_ap then v_max_ap := v_ms_ap; v_lento_ap := a.assunto; end if;
      perform iara.oraculo_aprofundar_texto(r);
      if jsonb_array_length(r -> 'detalhes') = 0 then v_falhas := v_falhas || (a.assunto || ': sem detalhes'); end if;
      if a.ranking is not null and not exists (select 1 from iara.oraculo_indicadores where chave = a.ranking) then v_falhas := v_falhas || (a.assunto || ': ranking inexistente'); end if;
      if exists (select 1 from unnest(a.indicadores) c where not exists (select 1 from iara.oraculo_indicadores i where i.chave = c)) then v_falhas := v_falhas || (a.assunto || ': indicador inexistente'); end if;
    exception when others then
      v_falhas := v_falhas || (a.assunto || ': ' || left(sqlerrm, 140));
    end;
  end loop;
  v_out := v_out || jsonb_build_object('passo', 'D3. Todo assunto aprofunda, em menos de 8 s', 'ok', cardinality(v_falhas) = 0 and v_max_ap < 8000,
    'falhas', to_jsonb(v_falhas), 'mais_lento', v_lento_ap, 'ms', v_max_ap);

  -- D4: as perguntas reais do Prefeito
  r := pg_temp.as_call('od-pref', 'oraculo_perguntar', '{"pergunta": "ola, como esta a rede hoje/"}');
  v_out := v_out || jsonb_build_object('passo', 'D4a. "como está a rede hoje": números e o que pede atenção', 'ok',
    r ->> 'topico' = 'panorama' and r ->> 'resposta' like '%Alunos matriculados%' and r ->> 'resposta' like '%Presença%' and r ->> 'resposta' like '%O que pede atenção agora%', 'resposta', left(r ->> 'resposta', 400));

  r := pg_temp.as_call('od-pref', 'oraculo_perguntar', '{"pergunta": "me fale mais sobre os encaminhamentos ao conselho tutelar"}');
  v_out := v_out || jsonb_build_object('passo', 'D4b. "me fale mais sobre os encaminhamentos": números, motivo, situação, espera e onde pesa', 'ok',
    r ->> 'topico' = 'protecao' and r ->> 'resposta' like '%Por motivo%' and r ->> 'resposta' like '%Em que situação estão%' and r ->> 'resposta' like '%Há quanto tempo aguardam%' and r ->> 'resposta' like '%Regiões com os%'
    and r ->> 'resposta' not like '%Restrições de guarda%', 'resposta', left(r ->> 'resposta', 900));

  r := pg_temp.as_call('od-pref', 'oraculo_perguntar', '{"pergunta": "quais os maiores motivos de encaminhamento"}');
  v_out := v_out || jsonb_build_object('passo', 'D4c. "maiores motivos de encaminhamento": por motivo, com percentual', 'ok',
    r ->> 'topico' = 'protecao' and r ->> 'resposta' like '%Excesso de faltas%' and r ->> 'resposta' ~ '\([0-9]+%\)' and r ->> 'resposta' !~ 'Ausências: [0-9]+ h', 'resposta', left(r ->> 'resposta', 600));

  r := pg_temp.as_call('od-pref', 'oraculo_perguntar', '{"pergunta": "quais as tres escolas com mais ocorrencias?"}');
  v_out := v_out || jsonb_build_object('passo', 'D4d. "as três escolas com mais ocorrências": exatamente 3, numeradas', 'ok',
    r ->> 'topico' = 'ranking' and r ->> 'resposta' like '%as 3 escolas%' and r ->> 'resposta' like E'%\n1. %' and r ->> 'resposta' like E'%\n3. %' and r ->> 'resposta' not like E'%\n4. %', 'resposta', r ->> 'resposta');

  r := pg_temp.as_call('od-pref', 'oraculo_perguntar', '{"pergunta": "qual o cardapio de hoje"}');
  v_out := v_out || jsonb_build_object('passo', 'D4e. "cardápio de hoje": as refeições de verdade, por faixa', 'ok',
    r ->> 'topico' = 'cardapio' and r ->> 'resposta' ~ 'Creche' and r ->> 'resposta' ~ 'Almoço|Lanche' and r ->> 'resposta' not like '%Refeições servidas%', 'resposta', left(r ->> 'resposta', 500));

  r := pg_temp.as_call('od-pref', 'oraculo_perguntar', '{"pergunta": "quantas crianças estao abaixo do peso normal?"}');
  v_out := v_out || jsonb_build_object('passo', 'D4f. "abaixo do peso": diz o motivo real e mostra as medidas, sem cair em matrículas', 'ok',
    r ->> 'topico' = 'nutricao' and r ->> 'resposta' like '%tabela oficial da OMS%' and r ->> 'resposta' like '%medidos%' and r ->> 'resposta' not like '%Alunos matriculados%', 'resposta', r ->> 'resposta');

  r := pg_temp.as_call('od-pref', 'oraculo_perguntar', '{"pergunta": "quantas crianças faltaram às aulas ontem/"}');
  v_out := v_out || jsonb_build_object('passo', 'D4g. "faltaram ontem": o dia pedido, não os últimos 30 dias', 'ok',
    r ->> 'topico' = 'periodo' and r ->> 'resposta' like 'Ontem (' || to_char(v_hoje - 1, 'DD/MM') || ')%' and r ->> 'resposta' like '%Faltas registradas%', 'resposta', r ->> 'resposta');

  r := pg_temp.as_call('od-pref', 'oraculo_perguntar', '{"pergunta": "Quantos profissionais marcaram o ponto hoje?"}');
  r2 := pg_temp.as_call('od-pref', 'oraculo_perguntar', '{"pergunta": "quantas crianças usam óculos"}');
  r3 := pg_temp.as_call('od-pref', 'oraculo_perguntar', '{"pergunta": "quais as maiores causas de chamados de manutenção?"}');
  v_out := v_out || jsonb_build_object('passo', 'D5. Período sem registro avisa; sem assunto é avisado; "maiores causas" abre o detalhe', 'ok',
    (r ->> 'topico' = 'periodo' and (r ->> 'resposta' like '%sem registro%' or exists (select 1 from iara.ponto_marcacoes where data = v_hoje)))
    and (r2 ->> 'fora')::boolean and r2 ->> 'resposta' like 'Não achei%'
    and r3 ->> 'topico' = 'manutencao' and r3 ->> 'resposta' like '%por categoria%',
    'periodo', r ->> 'resposta', 'fora', left(r2 ->> 'resposta', 80), 'causas', left(r3 ->> 'resposta', 200));

  -- D6: sigilo: em detalhe de pessoas nenhum item mostra 1 ou 2; o total some quando o resto é pequeno
  v_falhas := '{}';
  for d in select * from iara.oraculo_detalhes where pessoas order by chave loop
    r := iara.oraculo_detalhe_lista(d.chave, array[v_unit], false, 30);
    if exists (select 1 from jsonb_array_elements(r -> 'itens') i where (i ->> 'valor')::numeric between 1 and 2) then v_falhas := v_falhas || (d.chave || ': item de 1 ou 2'); end if;
    if r -> 'outros' ->> 'valor' is not null and (r -> 'outros' ->> 'valor')::numeric between 1 and 2 then v_falhas := v_falhas || (d.chave || ': resto de 1 ou 2'); end if;
  end loop;
  r := iara.oraculo_detalhe_lista('enc.motivo', v_todas, true, 8);
  v_out := v_out || jsonb_build_object('passo', 'D6. Sigilo: item de 1 ou 2 vai para "Outros", sem nome da categoria e sem número', 'ok', cardinality(v_falhas) = 0
    and r::text not like '%Suspeita de violência%', 'falhas', to_jsonb(v_falhas), 'motivo', r);

  -- D7: nada de nome de pessoa nem identificador nas respostas; texto digitado de encaminhamento não aparece
  select split_part(full_name, ' ', 1) || ' ' || split_part(full_name, ' ', 2) into v_nome from iara.students s join iara.encaminhamentos e on e.student_id = s.id limit 1;
  r := pg_temp.as_call('od-pref', 'oraculo_detalhar', '{"assunto": "encaminhamentos"}');
  r2 := pg_temp.as_call('od-pref', 'oraculo_detalhar', '{"assunto": "ocorrencias"}');
  v_txt := r::text || r2::text;
  v_out := v_out || jsonb_build_object('passo', 'D7. Detalhes sem nome de pessoa, sem identificador e sem texto digitado', 'ok',
    r ->> 'erro' is null and position(v_nome in v_txt) = 0 and v_txt !~ '[0-9a-f]{8}-[0-9a-f]{4}-' and v_txt !~ 'Ausências: [0-9]+ h' and v_txt !~ 'Notificação de faltas', 'erro', r ->> 'erro');

  -- D8: ferramentas
  r := pg_temp.as_call('od-pref', 'oraculo_cardapio', jsonb_build_object('data', (v_hoje + ((8 - extract(isodow from v_hoje))::int % 7) + 7)::text));
  r2 := pg_temp.as_call('od-pref', 'oraculo_calendario', '{"dias": 400}');
  r3 := pg_temp.as_call('od-pref', 'oraculo_indicadores', '{}');
  v_out := v_out || jsonb_build_object('passo', 'D8. Ferramentas: cardápio, calendário e a lista do que o Oráculo sabe', 'ok',
    jsonb_array_length(r -> 'faixas') >= 1 and jsonb_array_length(r -> 'faixas' -> 0 -> 'refeicoes') >= 1 and jsonb_array_length(r2 -> 'eventos') >= 1
    and jsonb_array_length(r3 -> 'assuntos') >= 20 and jsonb_array_length(r3 -> 'fatos_por_periodo') >= 12 and jsonb_array_length(r3 -> 'temas') >= 15,
    'cardapio', left(r::text, 260), 'erro', coalesce(r ->> 'erro', r2 ->> 'erro', r3 ->> 'erro'));

  -- D9: só o Prefeito
  r := pg_temp.as_call('od-sec', 'oraculo_detalhar', '{"assunto": "fila"}');
  r2 := pg_temp.as_call('od-sec', 'oraculo_periodo', '{"fato": "faltas"}');
  r3 := pg_temp.as_call('od-sec', 'oraculo_cardapio', '{}');
  v_out := v_out || jsonb_build_object('passo', 'D9. Só o Prefeito acessa', 'ok', r ->> 'codigo' = '42501' and r2 ->> 'codigo' = '42501' and r3 ->> 'codigo' = '42501'
    and pg_temp.as_call('od-sec', 'oraculo_calendario', '{}') ->> 'codigo' = '42501');

  raise exception 'RESULTADO: %', v_out;
end $$;
