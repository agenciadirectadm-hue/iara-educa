-- Relógio da demonstração.
-- Em 04/10 às 09:06 três sessões abriram ao mesmo tempo e cada uma rodou iara.demo_timeshift: os registros fictícios
-- foram deslocados 3 × 9h01 enquanto a linha de base andou só 9h01. Resultado: conversas, protocolos e eventos do
-- cenário gerado ficaram até 18 h "no futuro" (na lista de conversas apareciam mensagens às 15:28 de hoje à 00:30).
-- 1. O deslocamento passa a ser um de cada vez (trava na linha do tenant) e relê a linha de base depois da trava.
-- 2. O que foi criado ao vivo (sessões de visitantes, testes, WhatsApp) acontece em tempo real e não é deslocado.
-- 3. Os campos novos das conversas (encaminhamento, 1ª resposta, leitura) acompanham o deslocamento.
-- 4. Correção única: desfaz as 18h02 duplicadas no cenário gerado e registra na trilha como deslocamento negativo
--    (iara.demo_shift_since soma os deslocamentos da auditoria; com o registro negativo a soma volta a bater).
begin;

create or replace function iara.demo_shift_apply(d interval) returns void
language plpgsql security definer set search_path = iara, public
as $$
declare
  dd integer := extract(day from d)::int;
begin
  perform set_config('iara.skip_audit', 'on', true);
  create temp table if not exists tmp_ao_vivo_usuarios (id uuid primary key) on commit drop;
  truncate tmp_ao_vivo_usuarios;
  insert into tmp_ao_vivo_usuarios select id from iara.app_users where auth_provider in ('DEMO', 'WHATSAPP');
  create temp table if not exists tmp_casos_gerados (id uuid primary key) on commit drop;
  truncate tmp_casos_gerados;
  insert into tmp_casos_gerados
  select c.id from iara.service_cases c where c.is_demo and not exists (select 1 from tmp_ao_vivo_usuarios u where u.id = c.created_by);
  create temp table if not exists tmp_conversas_geradas (id uuid primary key) on commit drop;
  truncate tmp_conversas_geradas;
  insert into tmp_conversas_geradas
  select c.id from iara.conversations c
  where c.is_demo and c.channel <> 'WHATSAPP' and not exists (select 1 from tmp_ao_vivo_usuarios u where u.id = c.owner_user_id);

  update iara.service_cases set opened_at = opened_at + d, sla_due_at = sla_due_at + d, closed_at = closed_at + d
  where id in (select id from tmp_casos_gerados);
  update iara.case_events set occurred_at = occurred_at + d where case_id in (select id from tmp_casos_gerados);
  update iara.waiting_list_entries w set entered_at = entered_at + d
  where is_demo and not exists (select 1 from tmp_ao_vivo_usuarios u where u.id = w.created_by);
  update iara.vacancy_offers o set offered_at = offered_at + d, expires_at = expires_at + d, accepted_at = accepted_at + d, declined_at = declined_at + d
  where is_demo and not exists (select 1 from tmp_ao_vivo_usuarios u where u.id = o.created_by);
  update iara.vacancy_blocks b set created_at = created_at + d, released_at = released_at + d, valid_until = valid_until + dd
  where is_demo and not exists (select 1 from tmp_ao_vivo_usuarios u where u.id = b.created_by);
  update iara.vacancy_events e set occurred_at = occurred_at + d
  where not exists (select 1 from tmp_ao_vivo_usuarios u where u.id = e.user_id);
  update iara.documents set received_at = received_at + d, validated_at = validated_at + d
  where is_demo and received_at > now() - interval '120 days' and (case_id is null or case_id in (select id from tmp_casos_gerados));
  update iara.notifications n set created_at = created_at + d, read_at = read_at + d
  where not exists (select 1 from iara.whatsapp_contacts w where w.guardian_id = n.guardian_id)
    and (n.case_id is null or n.case_id in (select id from tmp_casos_gerados));
  update iara.conversations set last_message_at = last_message_at + d, created_at = created_at + d,
         handoff_at = handoff_at + d, first_reply_at = first_reply_at + d, staff_read_at = staff_read_at + d
  where id in (select id from tmp_conversas_geradas);
  update iara.messages set created_at = created_at + d where conversation_id in (select id from tmp_conversas_geradas);
  update iara.handoff_tasks set created_at = created_at + d where conversation_id in (select id from tmp_conversas_geradas);
  update iara.tool_executions set created_at = created_at + d where conversation_id in (select id from tmp_conversas_geradas);
  perform set_config('iara.skip_audit', 'off', true);
end $$;

create or replace function iara.demo_timeshift(p_min_hours integer default 6) returns interval
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_base timestamptz;
  d interval;
begin
  if not coalesce((iara.setting('demo_mode'))::boolean, false) then
    return interval '0';
  end if;
  v_base := (iara.setting('demo_baseline_at'))::timestamptz;
  if v_base is null or now() - v_base < make_interval(hours => p_min_hours) then
    return interval '0';
  end if;
  -- um de cada vez: quem chegar junto espera e, ao reler a linha de base, vê que já foi deslocado
  perform 1 from iara.tenants where id = 1 for update;
  v_base := (select (settings ->> 'demo_baseline_at')::timestamptz from iara.tenants where id = 1);
  d := date_trunc('minute', now() - v_base);
  if d < make_interval(hours => p_min_hours) then
    return interval '0';
  end if;
  perform iara.demo_shift_apply(d);
  perform set_config('iara.skip_audit', 'on', true);
  update iara.tenants set settings = jsonb_set(settings, '{demo_baseline_at}', to_jsonb(v_base + d)) where id = 1;
  perform set_config('iara.skip_audit', 'off', true);
  perform iara.audit_event('DEMO_TIMESHIFT', 'demo', 'baseline', null,
                           'Registros fictícios deslocados no tempo em ' || d::text || ' para manter a demonstração atual.');
  return d;
end $$;

revoke all on function iara.demo_shift_apply(interval) from public;

-- Correção única do deslocamento repetido de 04/10 09:06 (2 × 9h01 a mais)
do $$
declare
  d constant interval := -(interval '18 hours 2 minutes');
  v_excesso interval;
begin
  if coalesce((iara.setting('demo_reparo_relogio_0410'))::boolean, false) then
    raise notice 'Correção do relógio já aplicada.';
    return;
  end if;
  select max(m.created_at) - now() into v_excesso
  from iara.messages m join iara.conversations c on c.id = m.conversation_id
  where c.is_demo and c.channel <> 'WHATSAPP' and c.owner_user_id is null;
  if v_excesso is null or v_excesso < interval '6 hours' then
    raise notice 'Nada a corrigir (cenário à frente do relógio em %).', v_excesso;
  else
    perform iara.demo_shift_apply(d);
    perform iara.audit_event('DEMO_TIMESHIFT', 'demo', 'baseline', null,
      'Registros fictícios deslocados no tempo em ' || d::text || ' para manter a demonstração atual '
      || '(correção: o deslocamento de 04/10 09:06 rodou três vezes em sessões simultâneas).');
  end if;
  perform set_config('iara.skip_audit', 'on', true);
  update iara.tenants set settings = settings || '{"demo_reparo_relogio_0410": true}'::jsonb where id = 1;
  perform set_config('iara.skip_audit', 'off', true);
end $$;

commit;
