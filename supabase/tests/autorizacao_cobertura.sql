-- Autorização: cobertura estrutural e tentativas de acesso indevido (IDOR) — Fase 2, item 16 (SEC-AZ-02 e SEC-AZ-03).
-- Roda numa transação revertida. Cada passo traz "ok": true quando o comportamento é o esperado; "lista" mostra o que falhou.
-- Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/autorizacao_cobertura.sql
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

-- "negado" = erro de permissão/sessão/inexistente OU resposta vazia (sem dado da outra família/unidade)
create or replace function pg_temp.negado(r jsonb) returns boolean language sql as $f$
  select r is null or r = '{}'::jsonb or r = 'null'::jsonb or (r ->> 'codigo') in ('42501', '28000', 'P0002', '22023')
$f$;

do $$
declare
  v_out jsonb := '[]';
  v_lista jsonb;
  r jsonb;
  v_maria uuid := nullif(iara.setting('demo_guardian_maria'), '')::uuid;
  v_outro_aluno uuid;
  v_outro_resp uuid;
  v_outra_entrada uuid;
  v_outro_caso uuid;
  v_outra_conversa uuid;
  v_unidade_dir integer;
  v_aluno_outra_unidade uuid;
  v_turma_outra_unidade uuid;
begin
  -- ESTRUTURA ------------------------------------------------------------------------------------------------------
  select coalesce(jsonb_agg(c.relname), '[]') into v_lista from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'iara' and c.relkind = 'r' and not c.relrowsecurity;
  v_out := v_out || jsonb_build_object('passo', 'E1. Toda tabela do schema iara com RLS ligada', 'ok', v_lista = '[]', 'lista', v_lista);

  select coalesce(jsonb_agg(n.nspname || '.' || p.proname), '[]') into v_lista from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('iara', 'api', 'carga') and p.prosecdef
    and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  v_out := v_out || jsonb_build_object('passo', 'E2. Toda função SECURITY DEFINER com search_path fixo', 'ok', v_lista = '[]', 'lista', v_lista);

  select coalesce(jsonb_agg(p.proname order by p.proname), '[]') into v_lista from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'api' and has_function_privilege('anon', p.oid, 'execute')
    and p.proname not in ('bootstrap', 'units_map', 'geo_layers', 'units_list', 'unit_detail', 'territory_detail', 'network_kpis',
                          'grade_for_birthdate', 'search_vacancies', 'geo_search', 'knowledge_search', 'service_catalog', 'rules_list',
                          'data_quality', 'persona_units');
  v_out := v_out || jsonb_build_object('passo', 'E3. Visitante sem login só chama as funções públicas', 'ok', v_lista = '[]', 'lista', v_lista);

  -- leitura pelo visitante só nas tabelas de referência pública aprovadas (usadas pelas funções públicas); escrita, nenhuma.
  -- (o schema iara não é exposto pela API de dados; isto é defesa em profundidade e trava contra tabela nova aberta por engano)
  select coalesce(jsonb_agg(distinct n.nspname || '.' || c.relname), '[]') into v_lista from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('iara', 'carga') and c.relkind = 'r'
    and ((has_table_privilege('anon', c.oid, 'select') and c.relname not in ('data_quality_issues', 'demo_metrics', 'education_stages',
            'education_units', 'feature_flags', 'grade_levels', 'import_batches', 'knowledge_articles', 'organizational_roles', 'rules',
            'service_catalog', 'tenants', 'territories', 'unit_grade_stats', 'unit_offers', 'unit_shift_stats'))
         or has_table_privilege('anon', c.oid, 'insert') or has_table_privilege('anon', c.oid, 'update') or has_table_privilege('anon', c.oid, 'delete'));
  v_out := v_out || jsonb_build_object('passo', 'E4. Visitante só lê as tabelas de referência pública aprovadas', 'ok', v_lista = '[]', 'lista', v_lista);
  v_out := v_out || jsonb_build_object('passo', 'E4b. Configuração pública sem lista de telefones', 'ok',
    not exists (select 1 from iara.tenants where settings ? 'whatsapp_autorizados'));

  v_out := v_out || jsonb_build_object('passo', 'E5. Schema de carga fechado para o portal', 'ok',
    not has_schema_privilege('anon', 'carga', 'usage') and not has_schema_privilege('authenticated', 'carga', 'usage'));

  select coalesce(jsonb_agg(n.nspname || '.' || c.relname), '[]') into v_lista from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('iara', 'carga') and c.relkind = 'r'
    and (has_table_privilege('authenticated', c.oid, 'insert') or has_table_privilege('authenticated', c.oid, 'update')
         or has_table_privilege('authenticated', c.oid, 'delete'));
  v_out := v_out || jsonb_build_object('passo', 'E6. Usuário logado não escreve direto nas tabelas (só pelas funções)', 'ok', v_lista = '[]', 'lista', v_lista);

  v_lista := iara.classificacao_pendente();
  v_out := v_out || jsonb_build_object('passo', 'E7. Toda coluna com dado de pessoa está classificada (LGPD)', 'ok', v_lista = '[]', 'lista', v_lista);

  -- TENTATIVAS DE ACESSO INDEVIDO (IDOR) -----------------------------------------------------------------------------
  perform iara.session_create('CIDADAO', null, 'test-idor-cidadao', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', null, 'test-idor-diretor', 'teste');
  perform iara.session_create('CONTROLE_EXTERNO', null, 'test-idor-controle', 'teste');

  select s.id into v_outro_aluno from iara.students s
  where not exists (select 1 from iara.student_guardians sg where sg.student_id = s.id and sg.guardian_id = v_maria) limit 1;
  select g.id into v_outro_resp from iara.guardians g where g.id <> v_maria limit 1;
  select w.id into v_outra_entrada from iara.waiting_list_entries w
  where not exists (select 1 from iara.student_guardians sg where sg.student_id = w.student_id and sg.guardian_id = v_maria) limit 1;
  select c.id into v_outro_caso from iara.service_cases c where c.guardian_id is distinct from v_maria limit 1;
  select c.id into v_outra_conversa from iara.conversations c where c.guardian_id is distinct from v_maria limit 1;

  r := pg_temp.as_call('test-idor-cidadao', 'aluno_cadastro', jsonb_build_object('id', v_outro_aluno));
  v_out := v_out || jsonb_build_object('passo', 'I1. Família abre a ficha de criança de outra família (deve negar)', 'ok', pg_temp.negado(r), 'r', left(r::text, 120));
  r := pg_temp.as_call('test-idor-cidadao', 'student_detail', jsonb_build_object('student_id', v_outro_aluno));
  v_out := v_out || jsonb_build_object('passo', 'I2. Família abre o detalhe de criança de outra família (deve negar)', 'ok', pg_temp.negado(r), 'r', left(r::text, 120));
  r := pg_temp.as_call('test-idor-cidadao', 'responsavel_cadastro', jsonb_build_object('id', v_outro_resp));
  v_out := v_out || jsonb_build_object('passo', 'I3. Família abre o cadastro de outro responsável (deve negar)', 'ok', pg_temp.negado(r), 'r', left(r::text, 120));
  r := pg_temp.as_call('test-idor-cidadao', 'queue_entry_detail', jsonb_build_object('entry_id', v_outra_entrada));
  v_out := v_out || jsonb_build_object('passo', 'I4. Família abre a inscrição na fila de outra criança (deve negar)', 'ok', pg_temp.negado(r), 'r', left(r::text, 120));
  r := pg_temp.as_call('test-idor-cidadao', 'case_detail', jsonb_build_object('case_id', v_outro_caso));
  v_out := v_out || jsonb_build_object('passo', 'I5. Família abre protocolo de outra família (deve negar)', 'ok', pg_temp.negado(r), 'r', left(r::text, 120));
  r := pg_temp.as_call('test-idor-cidadao', 'conversation_detail', jsonb_build_object('id', v_outra_conversa));
  v_out := v_out || jsonb_build_object('passo', 'I6. Família abre conversa de outra família (deve negar)', 'ok', pg_temp.negado(r), 'r', left(r::text, 120));

  select unit_id into v_unidade_dir from iara.app_users where id = (select user_id from iara.app_sessions where token_hash = 'test-idor-diretor');
  select e.student_id, e.class_id into v_aluno_outra_unidade, v_turma_outra_unidade from iara.enrollments e
  where e.status = 'ACTIVE' and e.unit_id <> v_unidade_dir
    and not exists (select 1 from iara.waiting_list_entries w where w.student_id = e.student_id and w.preferred_unit_id = v_unidade_dir)
  limit 1;
  r := pg_temp.as_call('test-idor-diretor', 'aluno_cadastro', jsonb_build_object('id', v_aluno_outra_unidade));
  v_out := v_out || jsonb_build_object('passo', 'I7. Direção abre aluno de outra unidade (deve negar)', 'ok', pg_temp.negado(r), 'r', left(r::text, 120));
  r := pg_temp.as_call('test-idor-diretor', 'class_detail', jsonb_build_object('class_id', v_turma_outra_unidade));
  v_out := v_out || jsonb_build_object('passo', 'I8. Direção abre lista nominal de turma de outra unidade (sem nomes)', 'ok',
    pg_temp.negado(r) or coalesce(jsonb_array_length(r -> 'students'), 0) = 0, 'r', left(r::text, 120));

  r := pg_temp.as_call('test-idor-controle', 'aluno_cadastro', jsonb_build_object('id', v_outro_aluno));
  v_out := v_out || jsonb_build_object('passo', 'I9. Controle externo abre ficha nominal (deve negar)', 'ok', pg_temp.negado(r), 'r', left(r::text, 120));

  -- ESCRITA FORA DO ESCOPO ----------------------------------------------------------------------------------------------
  r := pg_temp.as_call('test-idor-cidadao', 'offer_create', jsonb_build_object('entry_id', v_outra_entrada));
  v_out := v_out || jsonb_build_object('passo', 'W1. Família tenta registrar oferta de vaga (deve negar)', 'ok', pg_temp.negado(r), 'r', left(r::text, 120));
  r := pg_temp.as_call('test-idor-controle', 'queue_recalculate', '{}');
  v_out := v_out || jsonb_build_object('passo', 'W2. Controle externo tenta recalcular a fila (deve negar)', 'ok', pg_temp.negado(r), 'r', left(r::text, 120));
  r := pg_temp.as_call('test-idor-diretor', 'whatsapp_autorizados_salvar', '{"somente_autorizados": false, "numeros": []}');
  v_out := v_out || jsonb_build_object('passo', 'W3. Direção tenta mexer no canal do WhatsApp (deve negar)', 'ok', pg_temp.negado(r), 'r', left(r::text, 120));
  r := pg_temp.as_call('test-idor-cidadao', 'demo_apresentacao_limpar', '{}');
  v_out := v_out || jsonb_build_object('passo', 'W4. Família tenta limpar a demonstração (deve negar)', 'ok', pg_temp.negado(r), 'r', left(r::text, 120));
  r := pg_temp.as_call('test-idor-cidadao', 'cargas_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', 'W5. Família tenta ver as cargas de dados (deve negar)', 'ok', pg_temp.negado(r), 'r', left(r::text, 120));
  r := pg_temp.as_call('test-idor-cidadao', 'auditoria_integridade', '{}');
  v_out := v_out || jsonb_build_object('passo', 'W6. Família tenta ler a auditoria (deve negar)', 'ok', pg_temp.negado(r), 'r', left(r::text, 120));

  raise exception 'RESULTADO: %', v_out;  -- reverte tudo
end $$;
