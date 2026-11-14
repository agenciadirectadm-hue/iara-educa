-- Oráculo: demanda do Prefeito à área responsável e tratamento pelo gênero (migração 099.21). Não grava nada: devolve o resultado no erro.
-- SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/oraculo_demandas.sql
create or replace function pg_temp.api(p_fn text, p_args jsonb) returns jsonb language plpgsql as $f$
declare r jsonb;
begin
  begin
    execute format('select api.%I($1)', p_fn) into r using p_args;
  exception when others then r := jsonb_build_object('excecao', sqlerrm);
  end;
  return r;
end $f$;

create or replace function pg_temp.como(p_role text) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', (select id from iara.app_users where role_code = p_role order by last_seen_at desc nulls last limit 1), 'role', 'authenticated')::text, true);
end $f$;

do $$
declare
  v_out jsonb := '[]'::jsonb;
  r jsonb;
  m jsonb;
  dir jsonb;
  sec jsonb;
begin
  perform pg_temp.como('PREFEITO');
  r := pg_temp.api('oraculo_tratamento', '{"genero": "FEMININO"}');
  v_out := v_out || jsonb_build_object('passo', 'T1. Tratamento pelo cadastro: a senhora, Prefeita', 'ok', r ->> 'pronome' = 'a senhora' and r ->> 'cargo' = 'Prefeita',
    'detalhe', r);
  v_out := v_out || jsonb_build_object('passo', 'T2. Gravado no cadastro do usuário e no município',
    'ok', (select genero from iara.app_users where id = iara.current_user_id()) = 'FEMININO' and iara.setting('prefeito_genero') = 'FEMININO');

  m := pg_temp.api('oraculo_demandar', '{"area": "MERENDA", "pedido": "Saber o que os alunos da EJA comeram ontem, separado por etapa", "o_que_falta": "As refeições são lançadas por unidade, não por etapa", "pergunta": "o que os alunos do eja comeram ontem"}');
  v_out := v_out || jsonb_build_object('passo', 'D1. Demanda enviada à Merenda, com número e prazo de 2 dias úteis',
    'ok', length(m ->> 'numero') = 8 and m ->> 'area' = 'Gerência da Merenda Escolar' and (m ->> 'prazo')::timestamptz > now() + interval '1 day'
          and not (m ->> 'ja_existia')::boolean, 'detalhe', m);
  v_out := v_out || jsonb_build_object('passo', 'D2. Na Central, como demanda da Prefeita, com a pergunta e o que falta',
    'ok', exists (select 1 from iara.pendencias where id = (m ->> 'id')::uuid and tipo = 'DEMANDA_PREFEITO' and titulo like 'Demanda da Prefeita:%'
                  and papel = 'NUTRICAO' and detalhe like '%Pergunta feita ao Oráculo%' and detalhe like '%O que o IARA não tem%'));
  r := pg_temp.api('oraculo_demandar', '{"area": "MERENDA", "pedido": "Saber o que os alunos da EJA comeram ontem separado por etapa"}');
  v_out := v_out || jsonb_build_object('passo', 'D3. O mesmo pedido não duplica', 'ok', (r ->> 'ja_existia')::boolean and r ->> 'id' = m ->> 'id');
  r := pg_temp.api('oraculo_demandar', '{"area": "RH", "pedido": "Celular da diretora da escola"}');
  v_out := v_out || jsonb_build_object('passo', 'D4. Área desconhecida é recusada, com a lista', 'ok', r ->> 'excecao' like 'Área desconhecida%');
  r := pg_temp.api('oraculo_demandar', '{"area": "DIRECAO_DA_UNIDADE", "pedido": "Plano para melhorar o Ideb da escola"}');
  v_out := v_out || jsonb_build_object('passo', 'D5. Direção sem unidade é recusada', 'ok', r ? 'excecao');
  dir := pg_temp.api('oraculo_demandar', '{"area": "DIRECAO_DA_UNIDADE", "unidade": "Octavio Periotto", "pedido": "Plano para melhorar o Ideb da escola"}');
  v_out := v_out || jsonb_build_object('passo', 'D6. Direção da unidade recebe na unidade', 'ok', dir ->> 'unidade' = 'Octavio Periotto'
    and exists (select 1 from iara.pendencias where id = (dir ->> 'id')::uuid and papel = 'DIRETOR_UNIDADE' and unit_id is not null), 'detalhe', dir);
  sec := pg_temp.api('oraculo_demandar', '{"area": "SECRETARIO", "unidade": "Octavio Periotto", "pedido": "Celular da diretora da escola Octavio Periotto"}');
  v_out := v_out || jsonb_build_object('passo', 'D7. Área da SEDUC recebe no setor, citando a unidade', 'ok',
    exists (select 1 from iara.pendencias where id = (sec ->> 'id')::uuid and papel = 'SECRETARIO' and unit_id is null and detalhe like '%Sobre a unidade: Octavio Periotto%'));

  perform pg_temp.como('NUTRICAO');
  r := pg_temp.api('pend_minhas', '{}');
  v_out := v_out || jsonb_build_object('passo', 'C1. A Merenda vê a demanda no topo da lista', 'ok', r -> 'itens' -> 0 ->> 'tipo' = 'DEMANDA_PREFEITO'
    and (r -> 'resumo' ->> 'do_prefeito')::int >= 1, 'detalhe', r -> 'itens' -> 0 ->> 'titulo');
  r := pg_temp.api('pend_concluir', jsonb_build_object('id', m ->> 'id'));
  v_out := v_out || jsonb_build_object('passo', 'C2. Não conclui sem a resposta', 'ok', r ->> 'excecao' like 'Escreva a resposta%');
  r := pg_temp.api('pend_concluir', jsonb_build_object('id', m ->> 'id', 'nota', 'Ontem a EJA jantou arroz, feijão e polenta com molho de carne. Vamos lançar a EJA separada a partir de segunda.'));
  v_out := v_out || jsonb_build_object('passo', 'C3. Conclui com a resposta', 'ok', r ->> 'situacao' = 'CONCLUIDA');

  perform pg_temp.como('PREFEITO');
  r := pg_temp.api('oraculo_demandas', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P1. A resposta volta para o Oráculo',
    'ok', exists (select 1 from jsonb_array_elements(r -> 'demandas') d where d ->> 'id' = m ->> 'id' and d ->> 'resposta' like 'Ontem a EJA%' and d ->> 'respondida_por' is not null),
    'detalhe', r -> 'resumo');
  r := pg_temp.api('oraculo_demanda_cobrar', jsonb_build_object('numero', dir ->> 'numero', 'texto', 'Preciso disso até amanhã.'));
  v_out := v_out || jsonb_build_object('passo', 'P2. Cobrar pelo número', 'ok', (r ->> 'cobrancas')::int = 1
    and exists (select 1 from iara.pend_eventos where pendencia_id = (dir ->> 'id')::uuid and tipo = 'COBRADA' and autor_label like 'Gabinete da Prefeita%'));
  r := pg_temp.api('oraculo_tratamento', '{"genero": "MASCULINO"}');
  v_out := v_out || jsonb_build_object('passo', 'T3. Troca para o senhor, Prefeito', 'ok', r ->> 'pronome' = 'o senhor');

  perform pg_temp.como('DIRETOR_UNIDADE');
  r := pg_temp.api('oraculo_demandar', '{"area": "MERENDA", "pedido": "Quero saber a merenda de ontem da EJA"}');
  v_out := v_out || jsonb_build_object('passo', 'S1. Só o Prefeito demanda pelo Oráculo', 'ok', r ? 'excecao');
  r := pg_temp.api('oraculo_tratamento', '{"genero": "FEMININO"}');
  v_out := v_out || jsonb_build_object('passo', 'S2. Só o Prefeito muda o tratamento', 'ok', r ? 'excecao');

  raise exception 'RESULTADO: %', jsonb_build_object('falhas', (select count(*) from jsonb_array_elements(v_out) e where not coalesce((e ->> 'ok')::boolean, false)), 'passos', v_out);
end $$;
