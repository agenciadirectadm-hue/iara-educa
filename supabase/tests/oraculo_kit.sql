-- Oráculo: o que vem no kit escolar e no uniforme (migração 099.19). Não grava nada: devolve as respostas no erro (RESULTADO: ...).
-- SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/oraculo_kit.sql
do $$
declare
  v_out text := '';
  v_p text;
  x jsonb;
  v_erros text[] := '{}';
begin
  foreach v_p in array array[
    'quais materiais fazem parte do kit para entrega aos alunos',
    'O que vem no kit do 1º ano?',
    'o que tem no kit da EJA',
    'quais itens do kit do infantil 3',
    'o que vem no kit da ampliação de jornada do 3º ano',
    'quais peças do uniforme do infantil 3',
    'o que vem no uniforme escolar',
    'o que vem no kit do primeiro ano na região do Jardim Alvorada',
    'quantos kits foram entregues',
    'quais materiais estão em falta no almoxarifado'
  ] loop
    x := iara.oraculo_leitura(v_p);
    v_out := v_out || E'\n\n=== ' || v_p || ' → ' || coalesce(x ->> 'topico', 'roteador antigo') || E'\n' || coalesce(x ->> 'resposta', '');
  end loop;

  -- conferências
  x := iara.oraculo_leitura('quais materiais fazem parte do kit para entrega aos alunos');
  if x ->> 'topico' is distinct from 'uniformes' or x ->> 'resposta' !~ 'Kit escolar' or x ->> 'resposta' ~ 'Leite em pó' then v_erros := v_erros || 'pergunta do kit não lê a composição'; end if;
  x := iara.oraculo_leitura('O que vem no kit do 1º ano?');
  if x ->> 'resposta' !~ 'Kit escolar 1º ano' or x ->> 'resposta' !~ 'Ampliação de Jornada' then v_erros := v_erros || 'kit do 1º ano'; end if;
  x := iara.oraculo_leitura('quais peças do uniforme do infantil 3');
  if x ->> 'resposta' !~ 'Uniforme escolar' or x ->> 'resposta' !~* 'papete' then v_erros := v_erros || 'uniforme do Infantil 3 sem a papete'; end if;
  x := iara.oraculo_leitura('o que vem no uniforme escolar');
  if x ->> 'resposta' !~* 'meias \(par\): 2 \(do Infantil 4 ao 5º ano\)' then v_erros := v_erros || 'uniforme sem a faixa de etapas das meias'; end if;
  x := iara.oraculo_leitura('quantos kits foram entregues');
  if x ->> 'topico' = 'uniformes' and x ->> 'resposta' ~ 'itens por aluno|O que vem nos kits' then v_erros := v_erros || '"quantos" virou composição'; end if;
  x := iara.oraculo_leitura('quais materiais estão em falta no almoxarifado');
  if x ->> 'topico' in ('uniformes', 'frequencia') then v_erros := v_erros || 'almoxarifado virou ' || (x ->> 'topico'); end if;
  x := iara.oraculo_leitura('quantas crianças faltaram ontem');
  if x is null or x ->> 'resposta' !~* 'falt|presen' then v_erros := v_erros || 'faltas dos alunos deixaram de ser lidas'; end if;

  -- "quantos" vai ao roteador por indicadores, como antes (com o perfil do Prefeito)
  perform set_config('request.jwt.claims', jsonb_build_object('sub', (select id from iara.app_users where role_code = 'PREFEITO' order by last_seen_at desc nulls last limit 1))::text, true);
  x := iara.oraculo_perguntar_base(jsonb_build_object('pergunta', 'quantos kits foram entregues'));
  v_out := v_out || E'\n\n=== quantos kits foram entregues (roteador por indicadores) → ' || coalesce(x ->> 'topico', '?') || E'\n' || coalesce(x ->> 'resposta', '');

  raise exception 'RESULTADO: % %', case when cardinality(v_erros) = 0 then 'OK' else 'FALHOU: ' || array_to_string(v_erros, '; ') end, v_out;
end $$;
