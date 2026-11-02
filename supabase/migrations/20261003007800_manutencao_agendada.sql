-- IARA Educa — 078 · Manutenção no agendador do banco, uma rotina por transação
-- Diagnóstico (02/11/2026, pg_stat_statements): iara.housekeeping() leva em média 0,2 s, mas chegou a 101 s, e o login
-- (iara.session_create) chegou a 82 s. Causa: a corrente de auditoria trava a linha iara.audit_chain_head até o fim da
-- transação que grava auditoria; a manutenção rodava tudo numa transação só — expirava ofertas (grava auditoria) e depois
-- rodava as rotinas diárias pesadas, segurando a trava. Enquanto isso, todo login, ficha aberta ou gravação esperava.
-- Agora cada rotina é um job do pg_cron, na sua própria transação curta, e o gateway (que ainda chama
-- iara.housekeeping() a cada 5 minutos) recebe resposta na hora, sem trabalho nem trava.
begin;

create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;

-- uma etapa da manutenção, com o mesmo tratamento de erro de antes (a rotina da demonstração nunca derruba a manutenção)
create or replace function iara.housekeeping_etapa(p_etapa text) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  return case p_etapa
    when 'relogio' then to_jsonb(iara.demo_timeshift()::text)
    when 'ofertas' then to_jsonb(iara.expire_due_offers())
    when 'rotina' then iara.demo_rotina_diaria()
    when 'sprint2' then case when iara.demo_mode() then iara.demo_rotina_sprint2() end
    when 'sprint3' then case when iara.demo_mode() then iara.demo_rotina_sprint3() end
    when 'sprint4' then case when iara.demo_mode() then iara.demo_rotina_sprint4() end
    when 'sprint5' then case when iara.demo_mode() then iara.demo_rotina_sprint5() end
    when 'busca_ativa' then iara.demo_rotina_busca_ativa()
  end;
exception when others then
  return jsonb_build_object('etapa', p_etapa, 'erro', sqlerrm);
end $$;

-- com os jobs agendados, a chamada do gateway não faz nada; sem eles (instalação nova sem pg_cron), roda tudo como antes
create or replace function iara.housekeeping() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v jsonb := '{}'::jsonb;
  e text;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and exists (select 1 from cron.job where jobname like 'iara-manutencao-%' and active) then
    return jsonb_build_object('agendado', true);
  end if;
  foreach e in array array['relogio', 'ofertas', 'rotina', 'sprint2', 'sprint3', 'sprint4', 'sprint5', 'busca_ativa'] loop
    v := v || jsonb_build_object(e, iara.housekeeping_etapa(e));
  end loop;
  return v;
end $$;

-- os jobs: cada um no seu minuto (o relógio antes das rotinas), a cada 5 minutos
do $$
declare
  j record;
begin
  for j in select jobid from cron.job where jobname like 'iara-manutencao-%' loop
    perform cron.unschedule(j.jobid);
  end loop;
  perform cron.schedule('iara-manutencao-relogio', '0-59/5 * * * *', $c$select iara.housekeeping_etapa('relogio')$c$);
  perform cron.schedule('iara-manutencao-ofertas', '1-59/5 * * * *', $c$select iara.housekeeping_etapa('ofertas')$c$);
  perform cron.schedule('iara-manutencao-rotina', '2-59/5 * * * *', $c$select iara.housekeeping_etapa('rotina')$c$);
  perform cron.schedule('iara-manutencao-sprint2', '3-59/5 * * * *', $c$select iara.housekeeping_etapa('sprint2')$c$);
  perform cron.schedule('iara-manutencao-sprint3', '3-59/5 * * * *', $c$select iara.housekeeping_etapa('sprint3')$c$);
  perform cron.schedule('iara-manutencao-sprint4', '4-59/5 * * * *', $c$select iara.housekeeping_etapa('sprint4')$c$);
  perform cron.schedule('iara-manutencao-sprint5', '4-59/5 * * * *', $c$select iara.housekeeping_etapa('sprint5')$c$);
  perform cron.schedule('iara-manutencao-busca-ativa', '1-59/5 * * * *', $c$select iara.housekeeping_etapa('busca_ativa')$c$);
end $$;

revoke all on function iara.housekeeping_etapa(text) from public;

commit;
