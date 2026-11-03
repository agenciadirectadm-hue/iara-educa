-- Ponto por biometria do aparelho: o(a) professor(a) cadastra a credencial e bate o ponto (as etapas do gateway são simuladas
-- aqui, depois da verificação WebAuthn); desafio de uso único; espelho do mês; justificativa; painel da direção, abono, ajuste
-- auditado e fechamento; acessos. Roda numa transação revertida (não deixa resíduo).
-- Executar: node scripts/aplicar.mjs supabase/tests/ponto_biometria.sql
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
-- como o gateway: executa como sistema, com o usuário nas claims
create or replace function pg_temp.gw(p_hash text, p_fn text, p_args jsonb) returns jsonb language plpgsql as $f$
declare
  v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', (select user_id from iara.app_sessions where token_hash = p_hash), 'role', 'authenticated')::text, true);
  execute format('select iara.%I($1)', p_fn) into v using p_args;
  return v;
exception when others then
  return jsonb_build_object('erro', sqlerrm, 'codigo', sqlstate);
end $f$;

do $$
declare
  v_out jsonb := '[]';
  r jsonb; r2 jsonb; r3 jsonb;
  v_unit integer := (iara.setting('demo_unit_maria'))::int;
  v_staff uuid;
  v_outro uuid;
  v_just uuid;
  v_ontem date := iara.hoje_local() - 1;
begin
  perform iara.session_create('PROFESSOR', v_unit, 'pt-prof', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_unit, 'pt-dir', 'teste');
  perform iara.session_create('PREFEITO', null, 'pt-pref', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', (select id from iara.education_units where id <> v_unit order by id limit 1), 'pt-dir2', 'teste');
  v_staff := (select u.staff_id from iara.app_users u join iara.app_sessions s on s.user_id = u.id where s.token_hash = 'pt-prof');
  -- pela ordem, o dia de ontem é o último completo; força um dia útil recente
  while not iara.ponto_dia_util(v_ontem) loop v_ontem := v_ontem - 1; end loop;

  -- a demonstração tem marcações da rede
  r := pg_temp.as_call('pt-prof', 'ponto_eu', '{}');
  v_out := v_out || jsonb_build_object('passo', 'B1. Professor(a): ponto do dia, jornada e unidade', 'ok',
    r ->> 'erro' is null and r -> 'jornada' -> 'periodos' is not null and r -> 'unidade' ->> 'nome' is not null
    and (select count(*) from iara.ponto_marcacoes where is_demo and data >= iara.hoje_local() - 30) > 10000,
    'jornada', r -> 'jornada', 'hoje', r -> 'hoje' ->> 'situacao', 'erro', r ->> 'erro');

  -- sem biometria cadastrada não há como pedir a marcação; o cadastro guarda só a chave pública
  r := pg_temp.gw('pt-prof', 'ponto_gateway_desafio', '{"tipo": "MARCACAO", "desafio": "desafio-de-teste-0001", "rp_id": "localhost"}');
  r2 := pg_temp.gw('pt-prof', 'ponto_gateway_desafio', '{"tipo": "CADASTRO", "desafio": "desafio-de-teste-0002", "rp_id": "localhost"}');
  r3 := pg_temp.gw('pt-prof', 'ponto_gateway_conferir', '{"tipo": "CADASTRO", "rp_id": "localhost"}');
  v_out := v_out || jsonb_build_object('passo', 'B2. Marcação exige biometria cadastrada; o desafio do cadastro é devolvido uma vez', 'ok',
    r ->> 'codigo' = '22023' and r2 ->> 'erro' is null and r3 ->> 'desafio' = 'desafio-de-teste-0002'
    and pg_temp.gw('pt-prof', 'ponto_gateway_conferir', '{"tipo": "CADASTRO", "rp_id": "localhost"}') ->> 'codigo' = '22023',
    'sem_biometria', r ->> 'erro');

  r := pg_temp.gw('pt-prof', 'ponto_gateway_cadastrar', '{"credencial": "cred-teste-1", "chave_publica": "pQECAyYgASFYIA", "contador": 0, "transportes": ["internal"], "rp_id": "localhost", "aparelho": "Teste"}');
  v_out := v_out || jsonb_build_object('passo', 'B3. Cadastro da biometria: chave pública guardada, auditado, demonstração de hoje retirada', 'ok',
    r ->> 'ok' = 'true' and exists (select 1 from iara.audit_log where action = 'PONTO_BIOMETRIA_CADASTRO' and entity_id = r ->> 'id')
    and not exists (select 1 from iara.ponto_marcacoes where staff_id = v_staff and data = iara.hoje_local()));

  -- marcação: desafio → conferência (chave pública) → marca; a segunda em menos de 2 min não duplica
  perform pg_temp.gw('pt-prof', 'ponto_gateway_desafio', '{"tipo": "MARCACAO", "desafio": "desafio-de-teste-0003", "rp_id": "localhost"}');
  r := pg_temp.gw('pt-prof', 'ponto_gateway_conferir', '{"tipo": "MARCACAO", "rp_id": "localhost", "credencial": "cred-teste-1"}');
  r2 := pg_temp.gw('pt-prof', 'ponto_gateway_marcar', jsonb_build_object('credencial', 'cred-teste-1', 'contador', 1,
          'lat', (select lat from iara.education_units where id = v_unit), 'lng', (select lng from iara.education_units where id = v_unit), 'precisao', 15));
  r3 := pg_temp.gw('pt-prof', 'ponto_gateway_marcar', '{"credencial": "cred-teste-1", "contador": 2}');
  v_out := v_out || jsonb_build_object('passo', 'B4. Bater o ponto: entrada na unidade, sem duplicar', 'ok',
    r -> 'credencial' ->> 'chave_publica' = 'pQECAyYgASFYIA' and r2 ->> 'tipo' = 'ENTRADA' and (r2 ->> 'fora')::boolean = false
    and (r2 ->> 'distancia_m')::int < 50 and (r3 ->> 'repetida')::boolean
    and (select count(*) from iara.ponto_marcacoes where staff_id = v_staff and data = iara.hoje_local()) = 1,
    'marcacao', r2 - 'dia');

  -- saída longe da unidade (simula 2 min depois): sinalizada, não bloqueada
  update iara.ponto_marcacoes set marcada_em = marcada_em - interval '3 hours' where staff_id = v_staff and data = iara.hoje_local();
  r := pg_temp.gw('pt-prof', 'ponto_gateway_marcar', jsonb_build_object('credencial', 'cred-teste-1', 'contador', 3,
          'lat', (select lat from iara.education_units where id = v_unit) + 0.02, 'lng', (select lng from iara.education_units where id = v_unit)));
  v_out := v_out || jsonb_build_object('passo', 'B5. Saída longe da unidade fica sinalizada; o dia soma as horas', 'ok',
    r ->> 'tipo' = 'SAIDA' and (r ->> 'fora')::boolean and (r -> 'dia' ->> 'minutos')::int between 170 and 190,
    'distancia', r ->> 'distancia_m', 'minutos', r -> 'dia' ->> 'minutos');

  -- marcar exige o caminho do gateway: api.* não marca ponto
  v_out := v_out || jsonb_build_object('passo', 'B6. Não há como marcar ponto pela API sem a biometria', 'ok',
    not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'api' and p.proname ~ 'ponto_(marcar|gateway)')
    and not has_function_privilege('authenticated', 'iara.ponto_gateway_marcar(jsonb)', 'execute'));

  -- espelho e justificativa
  r := pg_temp.as_call('pt-prof', 'ponto_espelho', '{}');
  r2 := pg_temp.as_call('pt-prof', 'ponto_justificar', jsonb_build_object('data', v_ontem, 'tipo', 'ESQUECIMENTO', 'descricao', 'Esqueci de bater a saída.'));
  v_just := (r2 ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'B7. Espelho do mês e justificativa de um dia', 'ok',
    r ->> 'erro' is null and jsonb_array_length(r -> 'dias') = extract(day from iara.hoje_local())::int and r -> 'totais' ? 'saldo'
    and r2 ->> 'ok' = 'true',
    'totais', r -> 'totais', 'erro', coalesce(r ->> 'erro', r2 ->> 'erro'));

  -- direção: painel do dia, abono, ajuste, fechamento
  r := pg_temp.as_call('pt-dir', 'ponto_painel', '{}');
  r2 := pg_temp.as_call('pt-dir', 'ponto_tratar', jsonb_build_object('id', v_just, 'decisao', 'ABONAR'));
  v_outro := (select s.id from iara.staff s where s.unit_id = v_unit and s.id <> v_staff and coalesce(s.situacao, 'ATIVO') = 'ATIVO' order by s.id limit 1);
  r3 := pg_temp.as_call('pt-dir', 'ponto_ajustar', jsonb_build_object('staff_id', v_outro, 'data', v_ontem, 'hora', '06:58', 'tipo', 'ENTRADA',
          'motivo', 'Biometria do aparelho falhou; entrada conferida pela direção.'));
  v_out := v_out || jsonb_build_object('passo', 'B8. Direção: presença do dia, abono e ajuste auditado', 'ok',
    r ->> 'erro' is null and (r -> 'contagens' ->> 'equipe')::int > 3 and exists (select 1 from jsonb_array_elements(r -> 'equipe') e where (e ->> 'biometria')::boolean)
    and r2 ->> 'ok' = 'true' and r3 ->> 'ok' = 'true'
    and exists (select 1 from iara.audit_log where action = 'PONTO_AJUSTE' and entity_id = r3 ->> 'id')
    and (select situacao from iara.ponto_justificativas where id = v_just) = 'ABONADA',
    'contagens', r -> 'contagens', 'erro', coalesce(r ->> 'erro', r2 ->> 'erro', r3 ->> 'erro'));

  r := pg_temp.as_call('pt-dir', 'ponto_fechar_mes', jsonb_build_object('mes', to_char(iara.hoje_local(), 'YYYY-MM')));
  update iara.ponto_justificativas set situacao = 'ABONADA' where unit_id = v_unit and situacao = 'PENDENTE'
    and date_trunc('month', data) = date_trunc('month', iara.hoje_local() - interval '1 month');
  r2 := pg_temp.as_call('pt-dir', 'ponto_fechar_mes', jsonb_build_object('mes', to_char(iara.hoje_local() - interval '1 month', 'YYYY-MM')));
  r3 := pg_temp.as_call('pt-dir', 'ponto_ajustar', jsonb_build_object('staff_id', v_outro,
          'data', (date_trunc('month', iara.hoje_local()) - interval '3 days')::date, 'hora', '07:00', 'tipo', 'ENTRADA', 'motivo', 'Teste depois do fechamento do mês.'));
  v_out := v_out || jsonb_build_object('passo', 'B9. Fechamento: só mês terminado; depois dele, sem ajustes', 'ok',
    r ->> 'codigo' = '22023' and r2 ->> 'ok' = 'true' and r3 ->> 'codigo' = '55006',
    'resumo', r2 -> 'resumo', 'erro', r2 ->> 'erro');

  -- acessos
  r := pg_temp.as_call('pt-pref', 'ponto_painel', '{}');
  r2 := pg_temp.as_call('pt-dir2', 'ponto_espelho', jsonb_build_object('staff_id', v_staff));
  r3 := pg_temp.as_call('pt-dir', 'ponto_eu', '{}');
  v_out := v_out || jsonb_build_object('passo', 'B10. Prefeito e direção de outra unidade não veem; direção não bate ponto como professor(a)', 'ok',
    r ->> 'codigo' = '42501' and r2 ->> 'codigo' = '42501' and r3 ->> 'codigo' = '42501');

  raise exception 'RESULTADO: %', v_out;
end $$;
