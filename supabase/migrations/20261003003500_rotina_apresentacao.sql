-- IARA Educa — 035 · Rotina de apresentação (Fase 1, item 6 do documento de estrutura)
-- Antes da apresentação: conferir o cenário (Maria e Davi, WhatsApp, o que sobrou de visitas anteriores).
-- Depois: limpar em um clique o que visitantes, testes e o WhatsApp criaram (sem token, pela própria tela).
-- Tudo só existe com o interruptor demo_mode ligado; em produção estas funções recusam.
begin;

insert into iara.permissions (code, description, is_sensitive)
values ('demo.manage', 'Conferir, limpar e reiniciar a demonstração depois de apresentações (só com o modo demonstração ligado)', false)
on conflict (code) do update set description = excluded.description;

insert into iara.role_permissions (role_code, permission_code) values
  ('SECRETARIO', 'demo.manage'), ('SUPERINTENDENCIA', 'demo.manage'), ('INOVACAO', 'demo.manage')
on conflict do nothing;

create or replace function iara.exigir_demo() returns void
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if not iara.demo_mode() then
    raise exception 'Disponível apenas no modo demonstração.' using errcode = '42501';
  end if;
end $$;

-- o botão "Reiniciar cenário do cidadão" passa a exigir o modo demonstração (antes bastava qualquer sessão)
create or replace function api.demo_reset_citizen(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  if iara.current_user_id() is null then
    raise exception 'Sessão necessária.' using errcode = '28000';
  end if;
  perform iara.exigir_demo();
  return iara.demo_reset_citizen();
end $$;

-- situação da demonstração: o que conferir antes de apresentar
create or replace function api.demo_apresentacao_situacao(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_users uuid[];
  v_davi uuid := nullif(iara.setting('demo_student_davi'), '')::uuid;
  w iara.waiting_list_entries;
  v_ultima timestamptz;
begin
  perform iara.require_perm('demo.manage');
  perform iara.exigir_demo();
  v_users := iara.demo_session_users(null);
  select * into w from iara.waiting_list_entries where student_id = v_davi and status in ('WAITING', 'OFFERED') order by entered_at limit 1;
  select max(occurred_at) into v_ultima from iara.audit_log where action = 'DEMO_PURGE';
  return jsonb_build_object(
    'demo_mode', true,
    'davi', jsonb_build_object('posicao', w.position, 'pontos', w.priority_score, 'situacao', w.status),
    'davi_ok', w.position = 1 and w.priority_score = 95,
    -- o que sessões, testes e o WhatsApp criaram desde a última limpeza
    'criado_por_visitas', jsonb_build_object(
      'familias', (select count(*) from iara.guardians g where g.created_by = any (v_users)),
      'criancas', (select count(*) from iara.students s where s.created_by = any (v_users)),
      'protocolos', (select count(*) from iara.service_cases c where c.created_by = any (v_users)),
      'conversas_whatsapp', (select count(*) from iara.whatsapp_contacts)),
    'ultima_limpeza', v_ultima,
    'whatsapp', (select jsonb_build_object('ligado', c.ativo, 'online', c.conectado and c.ultimo_sinal_em > now() - interval '3 minutes',
                                           'somente_autorizados', coalesce((iara.setting('whatsapp_somente_autorizados'))::boolean, false))
                 from iara.whatsapp_channels c order by c.created_at limit 1)
  );
end $$;

-- depois da apresentação: limpa tudo o que visitas, testes e WhatsApp criaram e reinicia a família da Maria
create or replace function api.demo_apresentacao_limpar(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r jsonb;
begin
  perform iara.require_perm('demo.manage');
  perform iara.exigir_demo();
  r := iara.demo_purge_session_data(null, null);
  return jsonb_build_object('ok', true, 'resultado', r, 'situacao', api.demo_apresentacao_situacao('{}'::jsonb));
end $$;

-- WhatsApp no portal: o QR code e os avisos só tratam o canal como ligado quando a ponte está dando sinal
-- (o canal ficou ligado sem ponte desde 05/10: o QR mandava a família para o chip compartilhado sem a Educação ouvindo)
create or replace function api.bootstrap(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'iara', 'public'
AS $function$
  select jsonb_build_object(
    'tenant', (select jsonb_build_object('id', id, 'name', name, 'state', state, 'ibge', ibge_code,
                                         'network_name', settings ->> 'network_name', 'secretariat', settings ->> 'secretariat',
                                         'school_year', (settings ->> 'school_year')::int, 'official_reference_date', settings ->> 'official_reference_date',
                                         'city_center', settings -> 'city_center', 'demo_mode', (settings ->> 'demo_mode')::boolean,
                                         'demo_unit', (settings ->> 'demo_unit_maria')::int)
               from iara.tenants where id = 1),
    'whatsapp', (select jsonb_build_object(
                   'numero', coalesce(nullif(regexp_replace(coalesce(t.settings ->> 'iara_whatsapp_numero', ''), '[^0-9]', '', 'g'), ''),
                                      (select regexp_replace(c.numero_e164, '[^0-9]', '', 'g') from iara.whatsapp_channels c
                                       where c.ativo and c.conectado and c.ultimo_sinal_em > now() - interval '5 minutes'
                                       order by c.ligado_em desc nulls last limit 1)),
                   -- ligado = interruptor ligado E ponte dando sinal: sem ponte, ninguém da Educação responde no número
                   'canal_ativo', exists (select 1 from iara.whatsapp_channels c
                                          where c.ativo and c.conectado and c.ultimo_sinal_em > now() - interval '5 minutes'),
                   'canal_ligado', exists (select 1 from iara.whatsapp_channels c where c.ativo),
                   'numero_demo', coalesce(t.settings ->> 'iara_whatsapp_numero_demo', '(44) 90000-0000'),
                   'mensagem', coalesce(nullif(t.settings ->> 'iara_whatsapp_mensagem', ''), 'Olá, IARA! Quero atendimento da Educação de Maringá.'),
                   'url_publica', t.settings ->> 'public_url')
                 from iara.tenants t where t.id = 1),
    'flags', (select jsonb_object_agg(code, enabled) from iara.feature_flags),
    'personas', (select jsonb_agg(jsonb_build_object('code', code, 'name', name, 'short_name', short_name, 'description', description,
                                                     'question', question, 'scope_type', scope_type, 'org_unit', org_unit, 'stage_filter', stage_filter)
                                  order by sort) from iara.organizational_roles where is_persona),
    'stages', (select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', name, 'short_name', short_name, 'color', color) order by sort) from iara.education_stages),
    'grades', (select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', name, 'short_name', short_name, 'stage_id', stage_id,
                                                   'min_age_months', min_age_months, 'max_age_months', max_age_months) order by sort) from iara.grade_levels),
    'territories', (select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', name, 'kind', kind, 'color', color,
                                                        'lat', extensions.st_y(center::extensions.geometry), 'lng', extensions.st_x(center::extensions.geometry)) order by sort)
                    from iara.territories where kind in ('MACRORREGIAO', 'DISTRITO')),
    'kpis', iara.kpis(),
    'rule_version', iara.rule_version(),
    'import', (select jsonb_build_object('id', id, 'file', source_file, 'imported_at', imported_at, 'counts', row_counts) from iara.import_batches limit 1)
  )
$function$;

revoke all on function iara.exigir_demo() from public;

commit;
