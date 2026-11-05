-- IARA Educa — 098.7 · Demonstração: o cenário da Maria acompanha o calendário.
-- O passeio com "Estou ciente" e o bilhete da professora foram criados uma vez, em outubro, e saíram da agenda da família depois de 21 dias;
-- a última reunião de pais do calendário era a do 3º bimestre. Quem abria a agenda e o calendário da Maria em novembro não via nenhum dos dois.
-- Agora o passeio passa para a próxima sexta-feira letiva quando a data passa (a ciência da edição anterior sai junto), o bilhete da
-- professora fica sempre recente, e o calendário ganha a reunião de pais do 4º bimestre.
-- Só mexe em dados de demonstração e só roda em modo demonstração.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

insert into iara.calendario_eventos (titulo, tipo, inicio, fim, abrangencia, unit_id, publico, descricao, fonte, is_demo)
select 'Reunião de pais e responsáveis — 4º bimestre', 'REUNIAO_PAIS', date '2026-12-14' + (u.id % 4), date '2026-12-14' + (u.id % 4), 'UNIDADE', u.id, 'FAMILIAS',
       'Entrega de pareceres e conversa com os professores.', 'DEMO', true
from iara.education_units u
where u.status = 'ATIVA' and iara.demo_mode()
  and not exists (select 1 from iara.calendario_eventos e where e.unit_id = u.id and e.titulo = 'Reunião de pais e responsáveis — 4º bimestre');

create or replace function iara.demo_rotina_cenario_maria() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_hoje date := iara.hoje_local();
  v_ana uuid := nullif(iara.setting('demo_student_ana'), '')::uuid;
  v_unit integer;
  v_turma uuid;
  v_dia date;
  v_ultimo date;
  v_passeio iara.agenda_escolar;
  v_out jsonb := '{}'::jsonb;
  n integer;
begin
  if not iara.demo_mode() or v_ana is null then return null; end if;
  select e.unit_id, e.class_id into v_unit, v_turma from iara.enrollments e where e.student_id = v_ana and e.status = 'ACTIVE' limit 1;
  if v_turma is null then return null; end if;
  perform set_config('iara.skip_audit', 'on', true);

  -- passeio: a próxima sexta-feira letiva (ou o próximo dia letivo), com pelo menos 2 dias para a família dar a ciência
  select * into v_passeio from iara.agenda_escolar a
  where a.is_demo and a.class_id = v_turma and a.student_id is null and a.titulo = 'Passeio ao Parque do Ingá' order by a.data desc limit 1;
  if v_passeio.id is null or v_passeio.data < v_hoje then
    select d::date into v_dia from generate_series(v_hoje + 2, v_hoje + 30, interval '1 day') d
    where iara.dia_letivo(d::date, v_unit) order by extract(isodow from d) <> 5, d limit 1;
    if v_dia is not null then
      if v_passeio.id is null then
        insert into iara.agenda_escolar (unit_id, class_id, origem, tipo, titulo, texto, data, exige_ciencia, autor_label, ciencias_demo, created_at, is_demo)
        values (v_unit, v_turma, 'ESCOLA', 'EVENTO', 'Passeio ao Parque do Ingá', '', v_dia, true, 'Professora regente (demonstração)', 11, now() - interval '20 hours', true)
        returning * into v_passeio;
      else
        delete from iara.agenda_ciencia where agenda_id = v_passeio.id;
      end if;
      update iara.agenda_escolar set data = v_dia, ciencias_demo = 11, created_at = now() - interval '20 hours',
             texto = 'Na ' || iara.oraculo_dia_semana(v_dia) || ', a turma visita o Parque do Ingá, das 13h30 às 16h. Mande boné, garrafinha e roupa confortável. Confirme a ciência para autorizar.'
      where id = v_passeio.id;
      v_out := v_out || jsonb_build_object('passeio', v_dia);
    end if;
  end if;

  -- bilhete da professora para a família: sempre do último dia letivo, quando o anterior já está para sair da agenda
  select max(d::date) into v_ultimo from generate_series(v_hoje - 7, v_hoje - 1, interval '1 day') d where iara.dia_letivo(d::date, v_unit);
  if v_ultimo is not null then
    update iara.agenda_escolar a set data = v_ultimo, created_at = v_ultimo + interval '17 hours'
    where a.is_demo and a.class_id = v_turma and a.student_id = v_ana and a.tipo = 'BILHETE' and a.origem = 'ESCOLA' and a.data < v_hoje - 14;
    get diagnostics n = row_count;
    if n > 0 then v_out := v_out || jsonb_build_object('bilhete', v_ultimo); end if;
  end if;

  perform set_config('iara.skip_audit', 'off', true);
  return v_out;
end $$;

-- a etapa nova entra na mesma manutenção agendada das outras
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
    when 'cenario_maria' then iara.demo_rotina_cenario_maria()
  end;
exception when others then
  return jsonb_build_object('etapa', p_etapa, 'erro', sqlerrm);
end $$;

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
  foreach e in array array['relogio', 'ofertas', 'rotina', 'sprint2', 'sprint3', 'sprint4', 'sprint5', 'busca_ativa', 'cenario_maria'] loop
    v := v || jsonb_build_object(e, iara.housekeeping_etapa(e));
  end loop;
  return v;
end $$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('iara-manutencao-cenario-maria', '7 * * * *', $c$select iara.housekeeping_etapa('cenario_maria')$c$);
  end if;
end $$;

select iara.demo_rotina_cenario_maria();

commit;
