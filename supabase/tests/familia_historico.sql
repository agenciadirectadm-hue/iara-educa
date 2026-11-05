-- Histórico escolar da família: traz quem tem histórico, sem item nulo para a criança ainda sem matrícula.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/familia_historico.sql
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

do $$
declare
  v_out jsonb := '[]';
  r jsonb;
begin
  perform iara.session_create('CIDADAO', null, 'fh-fam', 'teste');
  perform iara.session_create('SECRETARIO', null, 'fh-sec', 'teste');

  r := pg_temp.as_call('fh-fam', 'familia_historico', '{}');
  v_out := v_out || jsonb_build_object('passo', 'H1. A lista não tem item nulo', 'ok',
    r ->> 'erro' is null and not exists (select 1 from jsonb_array_elements(r) x where jsonb_typeof(x) = 'null'), 'erro', r ->> 'erro');
  v_out := v_out || jsonb_build_object('passo', 'H2. A Ana aparece, com nome e identificador', 'ok',
    exists (select 1 from jsonb_array_elements(r) x where x ->> 'primeiro_nome' = 'Ana' and x ->> 'student_id' is not null),
    'criancas', (select jsonb_agg(x ->> 'primeiro_nome') from jsonb_array_elements(r) x));
  v_out := v_out || jsonb_build_object('passo', 'H3. Quem não é responsável não acessa', 'ok', pg_temp.as_call('fh-sec', 'familia_historico', '{}') ->> 'codigo' = '42501');

  raise exception 'RESULTADO: %', v_out;
end $$;
