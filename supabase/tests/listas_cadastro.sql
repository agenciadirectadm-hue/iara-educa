-- Listas de Alunos e Responsáveis: contadores, filtros, busca, ordem e escopo conferidos com cálculo independente.
-- Roda numa transação revertida. Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/listas_cadastro.sql
do $$
declare
  v_out jsonb := '[]';
  v_sec uuid := (select id from iara.app_users where role_code = 'SECRETARIO' order by created_at limit 1);
  v_dir uuid := (select id from iara.app_users where role_code = 'DIRETOR_UNIDADE' and unit_id is not null order by created_at limit 1);
  v_fam uuid := (select id from iara.app_users where role_code = 'CIDADAO' order by created_at limit 1);
  v_un int := (select unit_id from iara.app_users where id = (select id from iara.app_users where role_code = 'DIRETOR_UNIDADE' and unit_id is not null order by created_at limit 1));
  v_outra int;
  r jsonb;
  v_esperado bigint;
  v_aluno iara.students;
  v_resp iara.guardians;
  v_fone text;
  v_nomes text[];
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);

  -- ALUNOS ----------------------------------------------------------------------------------------------------------
  r := api.alunos_lista('{"limite":100}');
  v_out := v_out || jsonb_build_object('passo', 'A1. Total e contagem batem com o cadastro', 'ok',
    (r ->> 'total')::bigint = (select count(*) from iara.students) and (r -> 'contagem' ->> 'todos')::bigint = (select count(*) from iara.students));

  select count(*) into v_esperado from iara.students s
  where cardinality(iara.aluno_pendencias(s, exists (select 1 from iara.student_guardians sg where sg.student_id = s.id and sg.end_date is null))) = 0;
  v_out := v_out || jsonb_build_object('passo', 'A2. Completos conferem com o cálculo por aluno', 'ok', (r -> 'contagem' ->> 'completos')::bigint = v_esperado);

  select array_agg(i ->> 'nome' order by o) into v_nomes from jsonb_array_elements(r -> 'itens') with ordinality t(i, o);
  v_out := v_out || jsonb_build_object('passo', 'A3. Página na ordem do nome sem acento', 'ok',
    v_nomes = (select array_agg(x.full_name order by x.n, x.id) from (select s.full_name, iara.norm(s.full_name) n, s.id from iara.students s order by iara.norm(s.full_name), s.id limit 100) x)
    and jsonb_array_length(r -> 'itens') = 100);

  select s.* into v_aluno from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' join iara.classes c on c.id = e.class_id order by s.id limit 1;
  r := api.alunos_lista(jsonb_build_object('q', v_aluno.student_registry_number));
  v_out := v_out || jsonb_build_object('passo', 'A4. Busca pela matrícula acha o aluno, com a unidade dele', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'itens') i where (i ->> 'id')::uuid = v_aluno.id and i -> 'unidade' ->> 'id' is not null));

  r := api.alunos_lista(jsonb_build_object('q', split_part(v_aluno.full_name, ' ', 1)));
  v_out := v_out || jsonb_build_object('passo', 'A5. Busca pelo nome só traz quem tem o nome', 'ok',
    (r ->> 'total')::int > 0 and not exists (select 1 from jsonb_array_elements(r -> 'itens') i
      where iara.norm(i ->> 'nome') not like '%' || iara.norm(split_part(v_aluno.full_name, ' ', 1)) || '%' and iara.norm(coalesce(i ->> 'nome_social', '')) not like '%' || iara.norm(split_part(v_aluno.full_name, ' ', 1)) || '%'));

  select e.unit_id into v_outra from iara.enrollments e where e.student_id = v_aluno.id and e.status = 'ACTIVE' limit 1;
  r := api.alunos_lista(jsonb_build_object('unidade_id', v_outra, 'limite', 100));
  v_out := v_out || jsonb_build_object('passo', 'A6. Filtro de unidade usa a matrícula, sem pedir nada a mais', 'ok',
    (r ->> 'total')::int > 0 and not exists (select 1 from jsonb_array_elements(r -> 'itens') i where (i -> 'unidade' ->> 'id')::int is distinct from v_outra));

  -- RESPONSÁVEIS ----------------------------------------------------------------------------------------------------
  r := api.responsaveis_lista('{"limite":100}');
  select count(*) into v_esperado from iara.guardians g where cardinality(iara.responsavel_pendencias(g)) = 0;
  v_out := v_out || jsonb_build_object('passo', 'R1. Total e completos conferem com o cadastro', 'ok',
    (r ->> 'total')::bigint = (select count(*) from iara.guardians) and (r -> 'contagem' ->> 'completos')::bigint = v_esperado);

  select g.* into v_resp from iara.guardians g where g.primary_phone is not null and g.cpf is not null order by g.id limit 1;
  v_fone := right(iara.digitos(v_resp.primary_phone), 8);
  -- quem não vê contatos não acha ninguém pelo telefone; quem vê, acha
  r := api.responsaveis_lista(jsonb_build_object('q', v_fone));
  v_out := v_out || jsonb_build_object('passo', 'R2. Sem permissão de contatos, telefone não encontra ninguém', 'ok',
    iara.can_see_contacts() or (r ->> 'total')::int = 0);
  perform set_config('request.jwt.claims', json_build_object('sub', (select u.id from iara.app_users u join iara.organizational_roles o on o.code = u.role_code
    join iara.role_permissions p on p.role_code = u.role_code and p.permission_code = 'guardians.read_contacts'
    where o.scope_type = 'NETWORK' and p.permission_code = 'guardians.read_contacts' order by u.created_at limit 1), 'role', 'authenticated')::text, true);
  r := api.responsaveis_lista(jsonb_build_object('q', v_fone, 'limite', 100));
  v_out := v_out || jsonb_build_object('passo', 'R2b. Com permissão, busca pelo final do telefone', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'itens') i where (i ->> 'id')::uuid = v_resp.id));
  perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);

  r := api.responsaveis_lista(jsonb_build_object('q', v_resp.cpf));
  v_out := v_out || jsonb_build_object('passo', 'R3. Busca pelo CPF', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'itens') i where (i ->> 'id')::uuid = v_resp.id));

  -- ESCOPO ----------------------------------------------------------------------------------------------------------
  if v_dir is not null then
    perform set_config('request.jwt.claims', json_build_object('sub', v_dir, 'role', 'authenticated')::text, true);
    r := api.alunos_lista('{"limite":100}');
    v_out := v_out || jsonb_build_object('passo', 'E1. Direção só vê alunos da própria unidade', 'ok',
      (r ->> 'escopo') = 'UNIT' and (r ->> 'total')::bigint = (select count(distinct x) from iara.unidade_alunos(v_un) x)
      and not exists (select 1 from jsonb_array_elements(r -> 'itens') i where (i ->> 'id')::uuid not in (select iara.unidade_alunos(v_un))));
    r := api.responsaveis_lista('{"limite":100}');
    v_out := v_out || jsonb_build_object('passo', 'E2. Direção só vê responsáveis da própria unidade', 'ok',
      not exists (select 1 from jsonb_array_elements(r -> 'itens') i where (i ->> 'id')::uuid not in (select iara.unidade_responsaveis(v_un))));
    -- aluno de outra unidade não aparece nem buscado pela matrícula
    select s.* into v_aluno from iara.students s where s.id not in (select iara.unidade_alunos(v_un)) order by s.id limit 1;
    r := api.alunos_lista(jsonb_build_object('q', v_aluno.student_registry_number));
    v_out := v_out || jsonb_build_object('passo', 'E3. Direção não acha aluno de outra unidade pela matrícula', 'ok', (r ->> 'total')::int = 0);
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', v_fam, 'role', 'authenticated')::text, true);
  begin
    r := api.alunos_lista('{}');
    v_out := v_out || jsonb_build_object('passo', 'E4. Família não abre a lista de alunos', 'ok', false);
  exception when others then
    v_out := v_out || jsonb_build_object('passo', 'E4. Família não abre a lista de alunos', 'ok', sqlstate = '42501');
  end;
  begin
    r := api.responsaveis_lista('{}');
    v_out := v_out || jsonb_build_object('passo', 'E5. Família não abre a lista de responsáveis', 'ok', false);
  exception when others then
    v_out := v_out || jsonb_build_object('passo', 'E5. Família não abre a lista de responsáveis', 'ok', sqlstate = '42501');
  end;

  -- ORDEM ------------------------------------------------------------------------------------------------------------
  v_out := v_out || jsonb_build_object('passo', 'N1. norm_ordem dá o mesmo valor de norm', 'ok',
    not exists (select 1 from iara.students s where iara.norm_ordem(s.full_name) is distinct from iara.norm(s.full_name))
    and iara.norm_ordem(null) = iara.norm(null) and iara.norm_ordem('Água Ñandu JOSÉ') = iara.norm('Água Ñandu JOSÉ'));
  v_out := v_out || jsonb_build_object('passo', 'N2. norm_ordem fora do alcance de quem não é o sistema', 'ok',
    not has_function_privilege('anon', 'iara.norm_ordem(text)', 'execute') and not has_function_privilege('authenticated', 'iara.norm_ordem(text)', 'execute'));

  raise exception 'RESULTADO: %', v_out;  -- reverte tudo
end $$;
