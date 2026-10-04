-- Jornada ponta a ponta (spec §74.14 / §73): oferta → aceite → documentos → matrícula → auditoria → reinício do cenário.
-- Executar: node scripts/sql.mjs supabase/tests/jornada_e2e.sql
-- Roda numa transação revertida (o resultado volta na mensagem RESULTADO): não deixa ofertas, matrículas
-- nem eventos de teste na família da demonstração.
create or replace function pg_temp.as_call(p_hash text, p_fn text, p_args jsonb) returns jsonb language plpgsql as $f$
declare
  v_uid uuid := (select user_id from iara.app_sessions where token_hash = p_hash);
  v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  perform set_config('iara.request_id', 'e2e-' || p_fn, true);
  execute 'set local role authenticated';
  execute format('select api.%I($1)', p_fn) into v using p_args;
  execute 'reset role';
  return v;
exception when others then
  execute 'reset role';
  return jsonb_build_object('erro', sqlerrm, 'codigo', sqlstate);
end $f$;

create temp table if not exists e2e (passo int, descricao text, resultado jsonb);
truncate e2e;

do $$
declare
  v_entry uuid := (iara.setting('demo_entry_davi'))::uuid;
  v_unit int := (iara.setting('demo_unit_maria'))::int;
  v_davi uuid := (iara.setting('demo_student_davi'))::uuid;
  v_class uuid;
  r jsonb;
  v_offer uuid;
  v_key text;
begin
  perform iara.demo_reset_citizen();
  v_key := 'e2e-davi-' || gen_random_uuid(); -- chave nova a cada execução (a idempotência vale por chave)
  select id into v_class from iara.classes where unit_id = v_unit and grade_level_id = 1 and offerable_vacancies_count > 0 order by offerable_vacancies_count desc limit 1;

  r := pg_temp.as_call('test-cidadao', 'citizen_home', '{}');
  insert into e2e values (1, 'Cidadã vê Davi na fila (posição e critérios)',
    jsonb_build_object('posicao', r -> 'children' -> 1 -> 'queue' -> 0 -> 'position', 'criterios',
      (select jsonb_agg(b ->> 'name') from jsonb_array_elements(r -> 'children' -> 1 -> 'queue' -> 0 -> 'breakdown') b where (b ->> 'applied')::boolean)));

  r := pg_temp.as_call('test-prefeito', 'offer_create', jsonb_build_object('entry_id', v_entry, 'class_id', v_class));
  insert into e2e values (2, 'Prefeito tenta ofertar (deve ser negado)', r);

  r := pg_temp.as_call('test-analista', 'offer_create', jsonb_build_object('entry_id', v_entry, 'class_id', v_class, 'idempotency_key', v_key));
  insert into e2e values (3, 'Analista oferta vaga ao 1º da fila', r);
  v_offer := (r ->> 'offer_id')::uuid;

  r := pg_temp.as_call('test-analista', 'offer_create', jsonb_build_object('entry_id', v_entry, 'class_id', v_class, 'idempotency_key', v_key));
  insert into e2e values (4, 'Repetição com a mesma chave (idempotente, sem duplicar)', r);

  r := pg_temp.as_call('test-diretor', 'enrollment_confirm', jsonb_build_object('offer_id', v_offer));
  insert into e2e values (5, 'Diretora tenta matricular antes do aceite (deve recusar)', r);

  r := pg_temp.as_call('test-cidadao', 'offer_respond', jsonb_build_object('offer_id', v_offer, 'accept', true, 'channel', 'PORTAL'));
  insert into e2e values (6, 'Maria aceita a oferta pelo portal', r);

  r := pg_temp.as_call('test-diretor', 'enrollment_confirm', jsonb_build_object('offer_id', v_offer));
  insert into e2e values (7, 'Diretora confirma: faltam documentos?', r);

  r := pg_temp.as_call('test-cidadao', 'document_set', jsonb_build_object('student_id', v_davi, 'doc_type', 'VACINACAO', 'status', 'VALIDADO'));
  insert into e2e values (8, 'Maria tenta VALIDAR documento (deve negar)', r);

  r := pg_temp.as_call('test-cidadao', 'document_set', jsonb_build_object('student_id', v_davi, 'doc_type', 'VACINACAO', 'status', 'RECEBIDO'));
  insert into e2e values (9, 'Maria envia a carteira de vacinação', r -> 'document');

  perform pg_temp.as_call('test-diretor', 'document_set', jsonb_build_object('student_id', v_davi, 'doc_type', 'VACINACAO', 'status', 'VALIDADO'));
  perform pg_temp.as_call('test-diretor', 'document_set', jsonb_build_object('student_id', v_davi, 'doc_type', 'CPF', 'status', 'VALIDADO'));
  r := pg_temp.as_call('test-diretor', 'enrollment_confirm', jsonb_build_object('offer_id', v_offer));
  insert into e2e values (10, 'Diretora valida documentos e confirma a matrícula', r);

  insert into e2e values (11, 'Contadores da turma após a matrícula', iara.class_snapshot(v_class));

  r := pg_temp.as_call('test-analista', 'audit_list', jsonb_build_object('business_only', true));
  insert into e2e values (12, 'Trilha de auditoria (eventos de negócio mais recentes)',
    (select jsonb_agg(jsonb_build_object('acao', i ->> 'action', 'quem', i ->> 'actor', 'resumo', i ->> 'summary')) from (
      select i from jsonb_array_elements(r -> 'items') i limit 6) z));

  r := pg_temp.as_call('test-diretor', 'audit_list', '{}');
  insert into e2e values (13, 'Diretora vê só a auditoria da própria unidade', jsonb_build_object('total', r -> 'total',
    'unidades', (select jsonb_agg(distinct i -> 'unit_id') from jsonb_array_elements(r -> 'items') i)));

  insert into e2e values (14, 'Reinício do cenário do cidadão', iara.demo_reset_citizen());
  insert into e2e values (15, 'Vagas ofertáveis da rede após o reinício', to_jsonb((select sum(offerable_vacancies_count) from iara.classes)));
end $$;

do $$ begin
  raise exception 'RESULTADO: %', (select jsonb_agg(jsonb_build_object('passo', passo, 'descricao', descricao, 'resultado', resultado) order by passo) from e2e);
end $$;  -- reverte tudo
