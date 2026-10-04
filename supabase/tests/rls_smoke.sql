-- Teste de fumaça de RLS/ABAC por perfil. Executar: node scripts/sql.mjs supabase/tests/rls_smoke.sql
-- Cria sessões de teste (se não existirem), simula cada perfil como o gateway faz e confere o escopo visível.
do $$ begin
  if not exists (select 1 from iara.app_sessions where token_hash = 'test-analista') then perform iara.session_create('ANALISTA_CENTRAL', null, 'test-analista', 'cli'); end if;
  if not exists (select 1 from iara.app_sessions where token_hash = 'test-diretor') then perform iara.session_create('DIRETOR_UNIDADE', null, 'test-diretor', 'cli'); end if;
  if not exists (select 1 from iara.app_sessions where token_hash = 'test-cidadao') then perform iara.session_create('CIDADAO', null, 'test-cidadao', 'cli'); end if;
  if not exists (select 1 from iara.app_sessions where token_hash = 'test-prefeito') then perform iara.session_create('PREFEITO', null, 'test-prefeito', 'cli'); end if;
end $$;

create temp table if not exists rls_result (perfil text, verificacao text, valor text);
truncate rls_result;
grant all on rls_result to authenticated;

create or replace function pg_temp.check_as(p_hash text, p_label text) returns void language plpgsql as $f$
declare
  v_uid uuid := (select user_id from iara.app_sessions where token_hash = p_hash);
  v_unit int;
  r record;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_unit := iara.my_unit();
  insert into rls_result values
    (p_label, 'alunos visíveis', (select count(*)::text from iara.students)),
    (p_label, 'responsáveis visíveis', (select count(*)::text from iara.guardians)),
    (p_label, 'dados sensíveis visíveis', (select count(*)::text from iara.student_sensitive)),
    (p_label, 'protocolos visíveis', (select count(*)::text from iara.service_cases)),
    (p_label, 'fila visível', (select count(*)::text from iara.waiting_list_entries)),
    (p_label, 'turmas visíveis', (select count(*)::text from iara.classes)),
    (p_label, 'unidades distintas nas turmas', (select count(distinct unit_id)::text from iara.classes)),
    (p_label, 'auditoria visível', (select count(*)::text from iara.audit_log)),
    (p_label, 'conversas visíveis', (select count(*)::text from iara.conversations)),
    (p_label, 'sessões visíveis (deve falhar/0)', coalesce((select 'ERRO: visível' from iara.app_users where id <> v_uid limit 1), 'ok — só a própria'));
  begin
    perform 1 from iara.app_sessions limit 1;
    insert into rls_result values (p_label, 'app_sessions', 'ERRO: leitura permitida');
  exception when insufficient_privilege then
    insert into rls_result values (p_label, 'app_sessions', 'ok — sem privilégio');
  end;
  begin
    update iara.classes set authorized_capacity = authorized_capacity + 10 where true;
    insert into rls_result values (p_label, 'escrita direta em turmas', 'ERRO: permitida');
  exception when insufficient_privilege then
    insert into rls_result values (p_label, 'escrita direta em turmas', 'ok — negada');
  end;
  execute 'reset role';
end $f$;

begin;
select pg_temp.check_as('test-analista', '1 Analista');
select pg_temp.check_as('test-diretor', '2 Diretor (unidade demo)');
select pg_temp.check_as('test-cidadao', '3 Cidadã (Maria)');
select pg_temp.check_as('test-prefeito', '4 Prefeito');
commit;

select perfil, verificacao, valor from rls_result order by perfil, verificacao;
