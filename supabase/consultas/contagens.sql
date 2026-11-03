-- Números da solução para apresentação (só leitura): alunos, responsáveis, servidores, usuários do sistema, a IARA e as
-- rotinas automáticas. Executar: node scripts/aplicar.mjs supabase/consultas/contagens.sql
select jsonb_build_object(
  'alunos', jsonb_build_object(
    'cadastrados', (select count(*) from iara.students),
    'ficticios_da_demonstracao', (select count(*) from iara.students where is_demo),
    'com_matricula_ativa', (select count(distinct student_id) from iara.enrollments where status = 'ACTIVE'),
    'na_fila_de_espera', (select count(distinct student_id) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED')),
    'por_situacao', (select jsonb_object_agg(coalesce(status, '?'), n) from (select status, count(*) n from iara.students group by 1) z),
    'matriculas_oficiais_censo_escolar', (select coalesce(sum(public_enrollments), 0) from iara.education_units)),
  'responsaveis', (select count(*) from iara.guardians),
  'servidores', jsonb_build_object(
    'total', (select count(*) from iara.staff),
    'por_funcao', (select jsonb_object_agg(coalesce(role, '?'), n) from (select role, count(*) n from iara.staff group by 1) z)),
  'usuarios_do_sistema', jsonb_build_object(
    'perfis_de_acesso', (select count(*) from iara.organizational_roles where is_persona),
    'contas', (select count(*) from iara.app_users),
    'contas_por_origem', (select jsonb_object_agg(auth_provider, n) from (select auth_provider, count(*) n from iara.app_users group by 1) z),
    'contas_por_perfil', (select jsonb_object_agg(role_code, n) from (select role_code, count(*) n from iara.app_users group by 1) z),
    'ativas_nos_ultimos_30_dias', (select count(*) from iara.app_users where last_seen_at > now() - interval '30 days'),
    'sessoes_abertas_agora', (select count(*) from iara.app_sessions where expires_at > now())),
  'iara', jsonb_build_object(
    'conversas', (select count(*) from iara.conversations),
    'conversas_por_canal', (select jsonb_object_agg(coalesce(channel, '?'), n) from (select channel, count(*) n from iara.conversations group by 1) z),
    'mensagens', (select count(*) from iara.messages),
    'numeros_de_whatsapp', (select count(*) from iara.whatsapp_channels)),
  'rotinas_agendadas_no_banco', (select count(*) from cron.job where active),
  'unidades', (select count(*) from iara.education_units)
) as numeros;
