-- Vida da família pela IARA/portal: cadastro de família nova, novo membro, inscrição na fila (transferência de outro
-- município), mudança de endereço, atualização de declarações, responsável não-genitor (alçada da unidade),
-- pedido para a Secretaria e desistência. Roda numa transação revertida; o resultado vem na mensagem final.
-- Executar: node scripts/sql.mjs supabase/tests/vida_familia.sql   (requer as sessões criadas por rls_smoke.sql)
create or replace function pg_temp.as_call(p_hash text, p_fn text, p_args jsonb) returns jsonb language plpgsql as $f$
declare
  v_uid uuid := (select user_id from iara.app_sessions where token_hash = p_hash);
  v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  perform set_config('iara.request_id', 'teste-familia-' || p_fn, true);
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
  v_hash text := 'teste-familia-' || substr(md5(random()::text), 1, 10);
  v_out jsonb := '[]'::jsonb;
  r jsonb;
  b1 record;
  b2 record;
  v_child uuid;
  v_grade smallint;
  v_unit integer;
  v_entry uuid;
  v_ana uuid := (iara.setting('demo_student_ana'))::uuid;
  v_case uuid;
begin
  perform iara.session_create('CIDADAO_NOVO', null, v_hash, 'teste');
  select t.name, st_y(t.center::geometry) as lat, st_x(t.center::geometry) as lng into b1
  from iara.territories t where t.kind = 'BAIRRO' and t.center is not null order by t.name limit 1;
  select t.name, st_y(t.center::geometry) as lat, st_x(t.center::geometry) as lng into b2
  from iara.territories t where t.kind = 'BAIRRO' and t.center is not null
  order by st_distance(t.center, iara.point(b1.lat, b1.lng)) desc limit 1;

  r := pg_temp.as_call(v_hash, 'family_overview', '{}');
  v_out := v_out || jsonb_build_object('passo', '1. Família nova sem cadastro', 'registrado', r -> 'registered');

  r := pg_temp.as_call(v_hash, 'family_register', jsonb_build_object('full_name', 'Joana Teste Ribeiro', 'channel', 'WHATSAPP',
         'cadunico', true, 'single_mother', true, 'origin', jsonb_build_object('city', 'Londrina', 'uf', 'PR'),
         'address', jsonb_build_object('neighborhood', b1.name, 'street', 'Rua das Acácias', 'number', '120', 'lat', b1.lat, 'lng', b1.lng)));
  v_out := v_out || jsonb_build_object('passo', '2. Cadastro pela IARA', 'ok', r -> 'ok', 'protocolo', r -> 'protocol', 'bairro', r -> 'guardian' -> 'address' ->> 'neighborhood');

  r := pg_temp.as_call(v_hash, 'family_add_child', jsonb_build_object('full_name', 'Pedro Teste Ribeiro', 'birth_date', (current_date - interval '30 months')::date,
         'gender', 'M', 'relationship', 'MAE', 'channel', 'WHATSAPP'));
  v_child := (r ->> 'student_id')::uuid;
  v_grade := (r -> 'grade_rule' ->> 'grade_level_id')::smallint;
  v_out := v_out || jsonb_build_object('passo', '3. Novo membro (criança)', 'ok', r -> 'ok', 'faixa', r -> 'grade_rule' ->> 'grade_name', 'protocolo', r -> 'protocol');

  select u.id into v_unit from iara.education_units u
  where u.status = 'ATIVA' and exists (select 1 from iara.classes c where c.unit_id = u.id and c.grade_level_id = v_grade and c.status = 'ATIVA')
  order by st_distance(u.location, iara.point(b1.lat, b1.lng)) limit 1;
  r := pg_temp.as_call(v_hash, 'queue_self_register', jsonb_build_object('student_id', v_child, 'unit_id', v_unit, 'channel', 'WHATSAPP',
         'origin', jsonb_build_object('city', 'Londrina', 'uf', 'PR', 'school', 'CMEI de origem', 'network', 'MUNICIPAL')));
  v_entry := (r ->> 'entry_id')::uuid;
  v_out := v_out || jsonb_build_object('passo', '4. Inscrição na fila (transferência de outro município)', 'tipo', r -> 'case_type',
         'posicao', r -> 'position', 'de', r -> 'queue_size', 'pontos', r -> 'score', 'msg', r -> 'message');

  r := pg_temp.as_call(v_hash, 'queue_self_register', jsonb_build_object('student_id', v_child, 'unit_id', v_unit));
  v_out := v_out || jsonb_build_object('passo', '5. Segunda inscrição na mesma faixa (deve recusar)', 'r', r);

  r := pg_temp.as_call(v_hash, 'family_move', jsonb_build_object('channel', 'WHATSAPP',
         'address', jsonb_build_object('neighborhood', b2.name, 'lat', b2.lat, 'lng', b2.lng)));
  v_out := v_out || jsonb_build_object('passo', '6. Mudança de endereço (recalcula a fila)', 'de', r -> 'previous' ->> 'neighborhood',
         'para', r -> 'address' ->> 'neighborhood', 'impactos', r -> 'impacts');

  r := pg_temp.as_call(v_hash, 'family_move', jsonb_build_object('address', jsonb_build_object('neighborhood', 'Fora', 'lat', -23.55, 'lng', -46.63)));
  v_out := v_out || jsonb_build_object('passo', '7. Endereço fora de Maringá (deve recusar)', 'r', r);

  r := pg_temp.as_call(v_hash, 'family_update', jsonb_build_object('single_mother', false, 'phone', '(44) 99876-5432'));
  v_out := v_out || jsonb_build_object('passo', '8. Atualiza declarações (mãe solo) e telefone', 'mudancas', r -> 'changes', 'impactos', r -> 'impacts');

  r := pg_temp.as_call(v_hash, 'family_add_adult', jsonb_build_object('full_name', 'Marta Teste Ribeiro', 'relationship', 'AVO', 'gender', 'F'));
  v_out := v_out || jsonb_build_object('passo', '9. Avó como responsável (vai para validação)', 'encaminhado', r -> 'escalated',
         'para', r -> 'routed_to' ->> 'team_label', 'msg', r -> 'message');

  r := pg_temp.as_call(v_hash, 'case_create', jsonb_build_object('case_type', 'TRANSPORTE', 'student_id', v_child, 'channel', 'WHATSAPP',
         'description', 'Pedido de transporte escolar (teste).'));
  v_out := v_out || jsonb_build_object('passo', '10. Transporte (alçada da Secretaria)', 'alcada', r -> 'routed_to' ->> 'level', 'para', r -> 'routed_to' ->> 'team_label');

  r := pg_temp.as_call(v_hash, 'queue_withdraw', jsonb_build_object('entry_id', v_entry, 'reason', 'Teste de desistência', 'channel', 'WHATSAPP'));
  v_out := v_out || jsonb_build_object('passo', '11. Desistência da fila', 'r', r);

  r := pg_temp.as_call('test-cidadao', 'case_create', jsonb_build_object('case_type', 'TROCA_TURNO', 'student_id', v_ana, 'channel', 'WHATSAPP',
         'description', 'Prefere o turno da manhã (teste).'));
  v_case := (r ->> 'case_id')::uuid;
  v_out := v_out || jsonb_build_object('passo', '12. Troca de turno (alçada da unidade)', 'alcada', r -> 'routed_to' ->> 'level',
         'para', r -> 'routed_to' ->> 'team_label', 'unidade', r -> 'routed_to' ->> 'unit_id');

  r := pg_temp.as_call('test-diretor', 'case_detail', jsonb_build_object('case_id', v_case));
  v_out := v_out || jsonb_build_object('passo', '13. Direção da unidade vê o pedido', 'protocolo', r -> 'case' ->> 'protocol', 'equipe', r -> 'case' ->> 'team');

  r := pg_temp.as_call('test-analista', 'iara_resolution_stats', '{}');
  v_out := v_out || jsonb_build_object('passo', '14. Resolutividade (30 dias)', 'r', r - 'by_type');

  raise exception 'RESULTADO: %', v_out;  -- reverte tudo
end $$;
