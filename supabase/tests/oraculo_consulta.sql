-- Oráculo com a base inteira (migração 099.20): catálogo, consulta livre só de leitura, o que entra e o que fica fora, e só o Prefeito.
-- Não grava nada: devolve o resultado no erro (RESULTADO: ...). SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/oraculo_consulta.sql
-- Cada chamada roda numa subtransação desfeita (a consulta deixa a transação só de leitura, como no gateway, em que cada chamada é uma transação).
create or replace function pg_temp.chamar(p_fn text, p_args jsonb) returns jsonb language plpgsql as $f$
declare r jsonb;
begin
  begin
    execute format('select api.%I($1)', p_fn) into r using p_args;
    raise exception using errcode = 'P0099', message = 'volta';
  exception
    when sqlstate 'P0099' then null;
    when others then r := jsonb_build_object('excecao', sqlerrm);
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
  v_c jsonb := iara.oraculo_base_conceder();
  n integer;
begin
  v_out := v_out || jsonb_build_object('passo', 'C1. Regras concedem a base (tabelas e colunas)', 'ok', (v_c ->> 'tabelas')::int > 100 and (v_c ->> 'colunas')::int > 1000, 'detalhe', v_c);
  v_out := v_out || jsonb_build_object('passo', 'C2. Nada de saúde, documento ou contato da família',
    'ok', not has_column_privilege('oraculo_leitor', 'iara.students', 'cpf', 'SELECT') and not has_column_privilege('oraculo_leitor', 'iara.students', 'race_color', 'SELECT')
          and not has_column_privilege('oraculo_leitor', 'iara.guardians', 'primary_phone', 'SELECT') and not has_table_privilege('oraculo_leitor', 'iara.student_sensitive', 'SELECT')
          and not exists (select 1 from information_schema.column_privileges where grantee = 'oraculo_leitor' and table_name in ('aee_planos', 'encaminhamentos', 'messages', 'app_sessions', 'audit_log'))
          and not has_column_privilege('oraculo_leitor', 'iara.ocorrencias', 'student_id', 'SELECT'));
  v_out := v_out || jsonb_build_object('passo', 'C3. Entram nomes, a escola com endereço, telefone e diretor(a), e o ponto',
    'ok', has_column_privilege('oraculo_leitor', 'iara.students', 'full_name', 'SELECT') and has_column_privilege('oraculo_leitor', 'iara.staff', 'full_name', 'SELECT')
          and has_column_privilege('oraculo_leitor', 'iara.education_units', 'phone', 'SELECT') and has_column_privilege('oraculo_leitor', 'iara.education_units', 'director_name', 'SELECT')
          and has_column_privilege('oraculo_leitor', 'iara.education_units', 'address_line', 'SELECT') and has_column_privilege('oraculo_leitor', 'iara.ponto_marcacoes', 'staff_id', 'SELECT'));
  v_out := v_out || jsonb_build_object('passo', 'C4. O gateway (authenticated) pode chamar as duas funções',
    'ok', has_function_privilege('authenticated', 'api.oraculo_consulta(jsonb)', 'execute') and has_function_privilege('authenticated', 'api.oraculo_catalogo(jsonb)', 'execute'));

  perform pg_temp.como('PREFEITO');
  r := pg_temp.chamar('oraculo_catalogo', '{}');
  v_out := v_out || jsonb_build_object('passo', 'K1. Catálogo lista a base', 'ok', jsonb_array_length(r -> 'tabelas') > 100, 'detalhe', jsonb_array_length(r -> 'tabelas'));
  r := pg_temp.chamar('oraculo_catalogo', '{"busca": "diretor endereço escola"}');
  v_out := v_out || jsonb_build_object('passo', 'K2. "diretor" acha as unidades', 'ok', r -> 'tabelas' -> 0 ->> 'tabela' = 'education_units', 'detalhe', r -> 'tabelas' -> 0 ->> 'tabela');
  r := pg_temp.chamar('oraculo_catalogo', '{"tabela": "students"}');
  v_out := v_out || jsonb_build_object('passo', 'K3. Ficha da tabela: colunas liberadas e ligações',
    'ok', (r -> 'colunas') @> '[{"coluna": "full_name"}]' and not ((r -> 'colunas') @> '[{"coluna": "cpf"}]') and jsonb_array_length(r -> 'apontada_por') > 0);

  r := pg_temp.chamar('oraculo_consulta', jsonb_build_object('finalidade', 'escola de menor Ideb', 'sql',
    'select u.short_name, u.director_name, u.address_line, u.neighborhood, u.phone, e.ideb, e.ano from ideb_escolas e join education_units u on u.inep_code = e.inep '
    || 'where e.ano = (select max(ano) from ideb_escolas where ideb is not null) and e.ideb is not null order by e.ideb limit 1'));
  v_out := v_out || jsonb_build_object('passo', 'Q1. Escola de menor Ideb com diretor(a), endereço e telefone', 'ok', (r ->> 'quantidade')::int = 1, 'detalhe', r -> 'linhas' -> 0);
  r := pg_temp.chamar('oraculo_consulta', jsonb_build_object('sql',
    'with u as (select id from education_units order by id limit 1) select count(distinct m.staff_id) servidores, count(*) filter (where m.tipo = ''ENTRADA'') entradas '
    || 'from ponto_marcacoes m where m.unit_id = (select id from u) and m.data >= current_date - 30'));
  v_out := v_out || jsonb_build_object('passo', 'Q2. Cruza ponto dos servidores de uma escola', 'ok', (r ->> 'quantidade')::int = 1 and r ? 'linhas', 'detalhe', r -> 'linhas' -> 0);
  r := pg_temp.chamar('oraculo_consulta', '{"sql": "select full_name from students order by full_name limit 2"}');
  v_out := v_out || jsonb_build_object('passo', 'Q3. Nome de aluno quando pedido', 'ok', (r ->> 'quantidade')::int = 2);
  r := pg_temp.chamar('oraculo_consulta', '{"sql": "select id from students limit 500"}');
  v_out := v_out || jsonb_build_object('passo', 'Q4. Até 200 linhas, com aviso de corte', 'ok', (r ->> 'quantidade')::int = 200 and (r ->> 'truncado')::boolean);

  r := pg_temp.chamar('oraculo_consulta', '{"sql": "select cpf from students limit 1"}');
  v_out := v_out || jsonb_build_object('passo', 'S1. CPF é negado', 'ok', r ? 'erro' and not (r ? 'linhas'), 'detalhe', r ->> 'erro');
  r := pg_temp.chamar('oraculo_consulta', '{"sql": "select medical_alerts from student_sensitive limit 1"}');
  v_out := v_out || jsonb_build_object('passo', 'S2. Saúde é negada', 'ok', r ? 'erro' and not (r ? 'linhas'));
  r := pg_temp.chamar('oraculo_consulta', '{"sql": "select body from messages limit 1"}');
  v_out := v_out || jsonb_build_object('passo', 'S3. Conversa com a família é negada', 'ok', r ? 'erro' and not (r ? 'linhas'));
  r := pg_temp.chamar('oraculo_consulta', '{"sql": "delete from limites_taxa"}');
  v_out := v_out || jsonb_build_object('passo', 'S4. Escrita é recusada', 'ok', r ? 'erro');
  r := pg_temp.chamar('oraculo_consulta', '{"sql": "select 1; select 2"}');
  v_out := v_out || jsonb_build_object('passo', 'S5. Dois comandos são recusados', 'ok', r ? 'erro');
  r := pg_temp.chamar('oraculo_consulta', '{"sql": "select pg_sleep(30)"}');
  v_out := v_out || jsonb_build_object('passo', 'S6. pg_sleep é recusado', 'ok', r ? 'erro');
  -- defesa em profundidade: mesmo sem a validação, o oraculo_leitor não escreve
  begin
    perform oraculo_exec.executar('with d as (delete from iara.limites_taxa returning 1) select * from d', 5);
    v_out := v_out || jsonb_build_object('passo', 'S7. O leitor não apaga nem com a validação contornada', 'ok', false);
  exception when others then
    -- a consulta vai dentro de um SELECT: o Postgres nem aceita DELETE ali (0A000); sem isso, o leitor não teria o privilégio (42501)
    v_out := v_out || jsonb_build_object('passo', 'S7. O leitor não apaga nem com a validação contornada', 'ok', sqlstate in ('42501', '0A000'), 'detalhe', sqlerrm);
  end;
  begin
    perform oraculo_exec.executar('select iara.audit_event(''X'', ''x'', null, null, ''x'')', 5);
    v_out := v_out || jsonb_build_object('passo', 'S9. O leitor não chama função que grava', 'ok', false);
  exception when others then
    v_out := v_out || jsonb_build_object('passo', 'S9. O leitor não chama função que grava', 'ok', sqlstate = '42501', 'detalhe', sqlerrm);
  end;
  begin
    perform oraculo_exec.executar('select token_hash from iara.app_sessions', 5);
    v_out := v_out || jsonb_build_object('passo', 'S8. O leitor não lê sessões', 'ok', false);
  exception when others then
    v_out := v_out || jsonb_build_object('passo', 'S8. O leitor não lê sessões', 'ok', sqlstate = '42501');
  end;

  perform pg_temp.como('DIRETOR_UNIDADE');
  r := pg_temp.chamar('oraculo_consulta', '{"sql": "select 1"}');
  v_out := v_out || jsonb_build_object('passo', 'P1. Só o Prefeito consulta', 'ok', r ? 'excecao', 'detalhe', r ->> 'excecao');
  r := pg_temp.chamar('oraculo_catalogo', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P2. Só o Prefeito vê o catálogo', 'ok', r ? 'excecao');

  -- registro na auditoria (sem desfazer: a transação inteira é revertida no fim)
  perform pg_temp.como('PREFEITO');
  r := api.oraculo_consulta('{"sql": "select count(*) from education_units", "finalidade": "teste de auditoria"}');
  select count(*) into n from iara.audit_log where action = 'ORACULO_CONSULTA' and summary like 'teste de auditoria%';
  v_out := v_out || jsonb_build_object('passo', 'A1. Cada consulta fica registrada', 'ok', n = 1);

  raise exception 'RESULTADO: %', jsonb_build_object('falhas', (select count(*) from jsonb_array_elements(v_out) e where not coalesce((e ->> 'ok')::boolean, false)), 'passos', v_out);
end $$;
