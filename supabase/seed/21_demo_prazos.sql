-- =============================================================================
-- IARA Educa · Rebalanceamento dos prazos (SLA) dos protocolos de demonstração
-- Idade de cada protocolo aberto ~ U^2,2 × min(38, 1,6 × SLA do serviço) dias
-- → cerca de 19% vencidos, distribuição realista por tipo de serviço.
-- Desloca abertura, prazo e eventos do mesmo protocolo pelo mesmo delta
-- (a linha do tempo de cada caso fica intacta). Não altera o cenário Maria/Davi.
-- =============================================================================
create or replace function iara.demo_rebalance_sla(p_seed double precision default 0.4242) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_davi_case uuid := nullif(iara.setting('demo_case_davi'), '')::uuid;
  v_n integer;
  v_overdue integer;
begin
  perform setseed(p_seed);
  create temp table tmp_shift on commit drop as
  select c.id,
         (now() - interval '1 day' * (power(random(), 2.2) * least(38, 1.6 * coalesce(sc.sla_days, 10)))
                - interval '1 hour' * floor(random() * 10)) - c.opened_at as delta
  from iara.service_cases c join iara.service_catalog sc on sc.code = c.case_type
  where iara.case_open(c.status) and c.is_demo and c.id is distinct from v_davi_case;

  alter table iara.service_cases disable trigger audit_service_cases;
  update iara.service_cases c set opened_at = c.opened_at + s.delta, sla_due_at = c.sla_due_at + s.delta
  from tmp_shift s where s.id = c.id;
  alter table iara.service_cases enable trigger audit_service_cases;

  update iara.case_events e set occurred_at = least(e.occurred_at + s.delta, now() - interval '5 minutes')
  from tmp_shift s where s.id = e.case_id;

  select count(*), count(*) filter (where sla_due_at < now()) into v_n, v_overdue
  from iara.service_cases where iara.case_open(status);
  perform iara.audit_event('DEMO_SEED', 'demo', 'sla', null,
                           format('Prazos dos protocolos de demonstração rebalanceados: %s abertos, %s vencidos.', v_n, v_overdue));
  return jsonb_build_object('open', v_n, 'overdue', v_overdue, 'shifted', (select count(*) from tmp_shift));
end $$;

revoke all on function iara.demo_rebalance_sla(double precision) from public, anon, authenticated;
