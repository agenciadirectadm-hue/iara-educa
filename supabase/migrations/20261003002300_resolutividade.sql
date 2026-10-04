-- =============================================================================
-- IARA Educa · Indicador de resolutividade da IARA
--  · Alçada (mix da demanda): de cada pedido feito pelo WhatsApp/portal, quem resolve pela matriz
--    de alçadas — IARA na hora, secretaria da unidade ou SEDUC.
--  · Conversas sem servidor: conversas que a IARA conduziu do início ao fim, sem transbordo.
--  · Execuções da IARA: pedidos que a IARA de fato executou e encerrou na hora (RESOLVIDO_IARA).
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
-- =============================================================================
begin;

create or replace function api.iara_resolution_stats(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_days integer := least(greatest(coalesce((p ->> 'days')::int, 30), 1), 365);
  v_since timestamptz := now() - make_interval(days => v_days);
begin
  if not (iara.has_perm('conversations.read') or iara.has_perm('kpi.network')) then
    raise exception 'Sem permissão para indicadores de atendimento.' using errcode = '42501';
  end if;
  return (
    with pedidos as (
      select c.case_type, c.resolution_code, coalesce(c.resolution_level, sc.resolution_level, 'SECRETARIA') lvl
      from iara.service_cases c left join iara.service_catalog sc on sc.code = c.case_type
      where c.opened_at > v_since and c.channel in ('WHATSAPP', 'WEB')
    ), conversas as (
      select cv.state in ('HUMAN_PENDING', 'HUMAN_ACTIVE') or cv.assigned_user_id is not null
             or exists (select 1 from iara.messages m where m.conversation_id = cv.id and m.sender_type = 'OPERADOR') as humano
      from iara.conversations cv
      where cv.created_at > v_since
    )
    select jsonb_build_object('days', v_days,
      'total', (select count(*) from pedidos),
      'level_iara', (select count(*) from pedidos where lvl = 'IARA'),
      'level_unit', (select count(*) from pedidos where lvl = 'UNIDADE'),
      'level_secretaria', (select count(*) from pedidos where lvl = 'SECRETARIA'),
      'resolved_by_iara', (select count(*) from pedidos where resolution_code = 'RESOLVIDO_IARA'),
      'routed_unit', (select count(*) from pedidos where lvl = 'UNIDADE' and resolution_code is distinct from 'RESOLVIDO_IARA'),
      'routed_secretaria', (select count(*) from pedidos where lvl = 'SECRETARIA' and resolution_code is distinct from 'RESOLVIDO_IARA'),
      'conversations', (select count(*) from conversas),
      'conversations_without_staff', (select count(*) from conversas where not humano),
      'by_type', (select coalesce(jsonb_agg(jsonb_build_object('type', z.name, 'level', z.lvl, 'total', z.n, 'resolved_by_iara', z.r) order by z.n desc), '[]'::jsonb)
                  from (select coalesce(sc.name, pd.case_type) as name, pd.lvl, count(*) n, count(*) filter (where pd.resolution_code = 'RESOLVIDO_IARA') r
                        from pedidos pd left join iara.service_catalog sc on sc.code = pd.case_type
                        group by 1, 2) z)));
end $$;

commit;
