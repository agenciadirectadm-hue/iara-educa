-- Prioridade sob análise (IN nº 025/2025-SEDUC, Anexo I): PCD/TEA/TGD/AH-SD com laudo, fora da soma de pontos.
-- Tudo roda numa transação revertida no fim (a base de demonstração não muda); o resultado vem na mensagem final.
-- Executar: node scripts/sql.mjs supabase/tests/prioridade_laudo.sql   (requer as sessões criadas por rls_smoke.sql)
create or replace function pg_temp.as_call(p_hash text, p_fn text, p_args jsonb) returns jsonb language plpgsql as $f$
declare
  v_uid uuid := (select user_id from iara.app_sessions where token_hash = p_hash);
  v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  perform set_config('iara.request_id', 'teste-laudo-' || p_fn, true);
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
  w iara.waiting_list_entries;
  v_class uuid;
  v_out jsonb := '[]'::jsonb;
  r jsonb;
  v_key text := 'teste-laudo-' || gen_random_uuid();
begin
  select x.* into w from iara.waiting_list_entries x
  where x.status = 'WAITING' and x.position > 1 and 'PCD_TEA_AEE' = any (x.priority_flags)
    and exists (select 1 from iara.documents d where d.student_id = x.student_id and d.doc_type = 'LAUDO' and d.status = 'VALIDADO')
    and exists (select 1 from iara.classes c where c.unit_id = x.preferred_unit_id and c.grade_level_id = x.grade_level_id and c.offerable_vacancies_count > 0)
  order by x.position limit 1;
  if not found then
    raise exception 'RESULTADO: nenhum caso elegível na base (fila com laudo validado, fora do 1º lugar e com vaga ofertável).';
  end if;
  select id into v_class from iara.classes c
  where c.unit_id = w.preferred_unit_id and c.grade_level_id = w.grade_level_id and c.offerable_vacancies_count > 0
  order by c.offerable_vacancies_count desc limit 1;

  r := pg_temp.as_call('test-analista', 'queue_entry_detail', jsonb_build_object('entry_id', w.id));
  v_out := v_out || jsonb_build_object('passo', '1. Detalhe: posição, pontos e flag', 'posicao', w.position, 'pontos', w.priority_score,
    'can_offer_now', r -> 'can_offer_now', 'can_offer_priority', r -> 'can_offer_priority');

  r := pg_temp.as_call('test-analista', 'offer_create', jsonb_build_object('entry_id', w.id, 'class_id', v_class, 'idempotency_key', v_key || '-a'));
  v_out := v_out || jsonb_build_object('passo', '2. Sem justificativa (deve recusar: segue a ordem)', 'r', r);

  r := pg_temp.as_call('test-analista', 'offer_create', jsonb_build_object('entry_id', w.id, 'class_id', v_class, 'idempotency_key', v_key || '-b',
                                                                          'priority_reason', 'curta'));
  v_out := v_out || jsonb_build_object('passo', '3. Justificativa curta (deve recusar)', 'r', r);

  r := pg_temp.as_call('test-prefeito', 'offer_create', jsonb_build_object('entry_id', w.id, 'class_id', v_class, 'idempotency_key', v_key || '-c',
                                                                          'priority_reason', 'Laudo com CID validado; análise da equipe técnica de inclusão.'));
  v_out := v_out || jsonb_build_object('passo', '4. Prefeito tenta (deve negar)', 'r', r);

  r := pg_temp.as_call('test-analista', 'offer_create', jsonb_build_object('entry_id', w.id, 'class_id', v_class, 'idempotency_key', v_key || '-d',
                                                                          'priority_reason', 'Laudo com CID validado; análise da equipe técnica de inclusão recomenda atendimento imediato.'));
  v_out := v_out || jsonb_build_object('passo', '5. Com laudo validado e justificativa (deve ofertar)', 'r', r - 'class_after');

  v_out := v_out || jsonb_build_object('passo', '6. Auditoria da decisão',
    'r', (select jsonb_agg(jsonb_build_object('acao', a.action, 'resumo', left(a.summary, 160))) from iara.audit_log a
          where a.action in ('PRIORITY_DECISION', 'OFFER_CREATED') and a.occurred_at > now() - interval '1 minute'));

  raise exception 'RESULTADO: %', v_out;  -- reverte tudo
end $$;
