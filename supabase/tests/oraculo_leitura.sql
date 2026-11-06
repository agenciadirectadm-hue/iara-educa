-- Oráculo que interpreta: responde o que foi perguntado, contorna a falta de dado, dá sentido ao número, não expõe pessoas e só atende o Prefeito.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/oraculo_leitura.sql
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
create or replace function pg_temp.perg(p text) returns text language plpgsql as $f$
begin
  return pg_temp.as_call('ol-pref', 'oraculo_perguntar', jsonb_build_object('pergunta', p)) ->> 'resposta';
end $f$;

do $$
declare
  v_out jsonb := '[]';
  t text;
  r jsonb;
  v_hoje date := iara.hoje_local();
  v_fech date;
  v_ef numeric;
  v_unit text := (select short_name from iara.education_units where id = (iara.setting('demo_unit_maria'))::int);
  q text;
  v_nomes boolean := false;
begin
  perform iara.session_create('PREFEITO', null, 'ol-pref', 'teste');
  perform iara.session_create('SECRETARIO', null, 'ol-sec', 'teste');

  -- 1. A pergunta do exemplo de Rob
  select max(s.data) into v_fech from iara.refeicoes_servidas s join iara.education_units u on u.id = s.unit_id where u.unit_type = 'ESCOLA' and s.data < v_hoje;
  select sum(s.quantidade) into v_ef from iara.refeicoes_servidas s join iara.education_units u on u.id = s.unit_id where u.unit_type = 'ESCOLA' and s.data = v_fech;
  t := pg_temp.perg('O que nossos alunos de ensino fundamental comeram hoje?');
  v_out := v_out || jsonb_build_object('passo', 'L1. Refeições do último dia fechado, só do ensino fundamental, com o número certo', 'ok', t like '%' || iara.num_br(v_ef) || ' refeições%' and t like '%ensino fundamental%', 't', t);
  v_out := v_out || jsonb_build_object('passo', 'L2. Traz o cardápio de ontem e o de hoje', 'ok', t like '%O cardápio foi:%' and t like '%o cardápio do ensino fundamental é:%');
  v_out := v_out || jsonb_build_object('passo', 'L3. Diz que os números de hoje não fecharam', 'ok', t like '%números de hoje ainda não fecharam%');
  t := pg_temp.perg('Quantas refeições foram servidas ontem?');
  v_out := v_out || jsonb_build_object('passo', 'L4. Ontem responde ontem, sem o dia de hoje', 'ok', t like 'Ontem%' and t not like '%Hoje (%', 't', t);
  t := pg_temp.perg('O que a pré-escola vai comer amanhã?');
  v_out := v_out || jsonb_build_object('passo', 'L5. Amanhã: só o cardápio, por etapa', 'ok', t like '%cardápio da pré-escola%' or t like '%não tem aula%', 't', t);
  t := pg_temp.perg('quanto custa a merenda?');
  v_out := v_out || jsonb_build_object('passo', 'L6. Custo não está no IARA: diz e contorna', 'ok', t like 'O custo da merenda não está no IARA Educa%' and t like '%refeições%', 't', t);
  t := pg_temp.perg('qual o cardápio de hoje?');
  v_out := v_out || jsonb_build_object('passo', 'L7. Quem pede o cardápio recebe o cardápio primeiro', 'ok', t like 'Hoje (%' or t like '%não tem aula%', 't', t);

  -- 2. Transporte: número com sentido
  t := pg_temp.perg('alguma rota de transporte nao funcionou hoje?');
  v_out := v_out || jsonb_build_object('passo', 'L8. Transporte: base, causa, atraso com sentido e sugestão', 'ok',
    t like '%viagens do transporte escolar%' and t like '%minutos em média%' and t like '%Sugestão:%' and t not like '%sem registro%', 't', t);

  -- 3. Decisão, em vez de lista
  t := pg_temp.perg('O que pede a minha decisão hoje?');
  v_out := v_out || jsonb_build_object('passo', 'L9. Decisão: em ordem, curta e com o que vai bem', 'ok', t like '%1. %' and t like '%O que vai bem%' and t not like '%5. %', 't', t);
  r := pg_temp.as_call('ol-pref', 'oraculo_perguntar', '{"pergunta": "Como está a rede municipal hoje?"}');
  v_out := v_out || jsonb_build_object('passo', 'L10. Não despeja os números em cartões', 'ok', jsonb_array_length(r -> 'numeros') = 0 and r ->> 'resposta' like '%decisão%');

  -- 4. Sem o assunto, diz que não tem
  t := pg_temp.perg('quantas crianças usam óculos?');
  v_out := v_out || jsonb_build_object('passo', 'L11. Assunto desconhecido: diz que não tem e quem confirma, sem despejar o resumo', 'ok',
    t like 'Não tenho esta informação neste momento%' and t like '%Secretaria%' and t not like '%Alunos matriculados%', 't', t);
  t := pg_temp.perg('quanto ganha um professor?');
  v_out := v_out || jsonb_build_object('passo', 'L12. Salário: diz que não está no IARA e traz o quadro', 'ok', t like 'Salários e folha%' and t like '%professores%', 't', t);

  -- 5. Recorte
  t := pg_temp.perg('o que os alunos do ' || v_unit || ' comeram hoje?');
  v_out := v_out || jsonb_build_object('passo', 'L13. Numa unidade, a resposta é da unidade', 'ok', t like '%' || v_unit || '%' and t not like '%a rede serviu%', 't', t);
  t := pg_temp.perg('como está o ' || v_unit || '?');
  v_out := v_out || jsonb_build_object('passo', 'L14. Panorama de uma unidade', 'ok', t like v_unit || ':%', 't', t);

  -- 6. Roteador antigo continua atendendo
  t := pg_temp.perg('telefone da mãe da Ana');
  v_out := v_out || jsonb_build_object('passo', 'L15. Dado de pessoa continua fora', 'ok', t like 'Dados de uma pessoa%', 't', t);
  t := pg_temp.perg('Quais as três escolas com mais ocorrências?');
  v_out := v_out || jsonb_build_object('passo', 'L16. Comparação pedida continua direta', 'ok', t like '%1. %' and t like '%3. %', 't', t);
  t := pg_temp.perg('detalhe completo da manutenção');
  v_out := v_out || jsonb_build_object('passo', 'L17. Detalhe completo, quando pedido', 'ok', t like '%Chamados abertos por categoria%', 't', t);
  t := pg_temp.perg('quantos alunos se chamam Silvio?');
  v_out := v_out || jsonb_build_object('passo', 'L18. Contagem por nome continua', 'ok', t like '%no nome%', 't', t);

  -- 7. Sem pessoas, em nenhuma resposta
  foreach q in array array['O que pede a minha decisão hoje?', 'alguma rota de transporte falhou hoje?', 'as crianças estão indo à escola?', 'como estão os encaminhamentos ao conselho tutelar?', 'tem muita briga nas escolas?', 'Quantos professores temos?'] loop
    t := pg_temp.perg(q);
    if exists (select 1 from iara.students s where length(s.full_name) > 10 and t like '%' || s.full_name || '%') then v_nomes := true; end if;
  end loop;
  v_out := v_out || jsonb_build_object('passo', 'L19. Nenhum nome de aluno nas respostas', 'ok', not v_nomes);

  -- 8. Acesso e registro
  r := pg_temp.as_call('ol-sec', 'oraculo_perguntar', '{"pergunta": "O que comeram hoje?"}');
  v_out := v_out || jsonb_build_object('passo', 'L20. Só o Prefeito pergunta', 'ok', r ? 'erro', 'r', r);
  r := pg_temp.as_call('ol-sec', 'oraculo_leitura', '{"pergunta": "O que comeram hoje?"}');
  v_out := v_out || jsonb_build_object('passo', 'L21. A leitura também é só do Prefeito', 'ok', r ? 'erro');
  r := pg_temp.as_call('ol-pref', 'oraculo_leitura', '{"pergunta": "O que comeram hoje?"}');
  v_out := v_out || jsonb_build_object('passo', 'L22. A leitura do conector responde', 'ok', (r ->> 'encontrada')::boolean and r ->> 'resposta' like '%refeições%');
  v_out := v_out || jsonb_build_object('passo', 'L23. Cada pergunta fica registrada', 'ok', exists (select 1 from iara.oraculo_perguntas p where p.pergunta like 'O que nossos alunos%'));

  raise exception 'RESULTADO: %', v_out;
end $$;
