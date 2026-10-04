-- =============================================================================
-- IARA Educa · Contato da IARA no WhatsApp (QR code, número e link de conversa)
-- Configuração em iara.tenants.settings:
--   iara_whatsapp_numero       número OFICIAL em formato internacional, só dígitos (ex.: 55449XXXXXXXX).
--                              Enquanto não existir, o QR code e o link abrem a conversa simulada da IARA
--                              (nunca um wa.me com número fictício, que poderia levar a um desconhecido).
--   iara_whatsapp_numero_demo  número fictício exibido na demonstração (identificado como demonstração).
--   iara_whatsapp_mensagem     mensagem que já vem escrita ao abrir a conversa.
--   public_url                 endereço público da plataforma (QR code gerado no localhost aponta para ele).
-- Para ativar o número oficial (sem novo deploy):
--   update iara.tenants set settings = settings || '{"iara_whatsapp_numero": "55449XXXXXXXX"}' where id = 1;
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
-- =============================================================================
begin;

update iara.tenants set settings = settings || jsonb_build_object(
    'iara_whatsapp_numero_demo', coalesce(settings ->> 'iara_whatsapp_numero_demo', '(44) 90000-0000'),
    'iara_whatsapp_mensagem', coalesce(settings ->> 'iara_whatsapp_mensagem', 'Olá, IARA! Quero atendimento da Educação de Maringá.'),
    'public_url', coalesce(settings ->> 'public_url', 'https://agenciadirectadm-hue.github.io/iara-educa/'))
where id = 1;

create or replace function api.bootstrap(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object(
    'tenant', (select jsonb_build_object('id', id, 'name', name, 'state', state, 'ibge', ibge_code,
                                         'network_name', settings ->> 'network_name', 'secretariat', settings ->> 'secretariat',
                                         'school_year', (settings ->> 'school_year')::int, 'official_reference_date', settings ->> 'official_reference_date',
                                         'city_center', settings -> 'city_center', 'demo_mode', (settings ->> 'demo_mode')::boolean,
                                         'demo_unit', (settings ->> 'demo_unit_maria')::int)
               from iara.tenants where id = 1),
    'whatsapp', (select jsonb_build_object(
                   'numero', nullif(regexp_replace(coalesce(settings ->> 'iara_whatsapp_numero', ''), '[^0-9]', '', 'g'), ''),
                   'numero_demo', coalesce(settings ->> 'iara_whatsapp_numero_demo', '(44) 90000-0000'),
                   'mensagem', coalesce(nullif(settings ->> 'iara_whatsapp_mensagem', ''), 'Olá, IARA! Quero atendimento da Educação de Maringá.'),
                   'url_publica', settings ->> 'public_url')
                 from iara.tenants where id = 1),
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
$$;

commit;
