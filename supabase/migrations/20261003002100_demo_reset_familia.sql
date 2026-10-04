-- =============================================================================
-- IARA Educa · Reinício completo do cenário do cidadão (família compartilhada da demonstração)
-- Todos os visitantes do perfil "Cidadão" usam a mesma família fictícia (Maria, Jorge, Ana e Davi). Como agora a
-- família pode incluir membros, mudar de endereço e atualizar declarações (pela IARA ou pelo portal), o reinício
-- devolve tudo ao estado original: membros, endereço, declarações, contatos, fila e ofertas.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
-- =============================================================================
begin;

-- referências estáveis do cenário (endereço original e pai), gravadas uma vez
update iara.tenants set settings = settings
  || jsonb_build_object('demo_address_maria', coalesce(settings ->> 'demo_address_maria',
       (select g.address_id::text from iara.guardians g where g.id = (settings ->> 'demo_guardian_maria')::uuid)))
  || jsonb_build_object('demo_guardian_jorge', coalesce(settings ->> 'demo_guardian_jorge',
       (select sg.guardian_id::text from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
        where sg.student_id = (settings ->> 'demo_student_davi')::uuid and sg.relationship = 'PAI' order by g.created_at limit 1)))
where id = 1;

create or replace function iara.demo_reset_citizen() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_davi uuid := (iara.setting('demo_student_davi'))::uuid;
  v_ana uuid := (iara.setting('demo_student_ana'))::uuid;
  v_entry uuid := (iara.setting('demo_entry_davi'))::uuid;
  v_case uuid := (iara.setting('demo_case_davi'))::uuid;
  v_maria uuid := (iara.setting('demo_guardian_maria'))::uuid;
  v_jorge uuid := nullif(iara.setting('demo_guardian_jorge'), '')::uuid;
  v_addr uuid := nullif(iara.setting('demo_address_maria'), '')::uuid;
  v_unit integer := (iara.setting('demo_unit_maria'))::int;
  v_base timestamptz := (iara.setting('demo_baseline_at'))::timestamptz;
  v_extra uuid[];
  e record;
  q record;
  v_pos integer;
begin
  if v_davi is null then
    raise exception 'Cenário de demonstração não configurado.';
  end if;

  -- 1. família: crianças e adultos incluídos por visitantes saem do cadastro da Maria
  select coalesce(array_agg(sg.student_id), '{}') into v_extra
  from iara.student_guardians sg where sg.guardian_id = v_maria and sg.student_id not in (v_ana, v_davi);
  update iara.vacancy_offers set status = 'CANCELLED', decline_reason = 'Reinício do cenário de demonstração'
  where student_id = any (v_extra) and status in ('OFFERED', 'ACCEPTED');
  for q in select distinct preferred_unit_id, grade_level_id from iara.waiting_list_entries
           where student_id = any (v_extra) and status in ('WAITING', 'OFFERED', 'ACCEPTED') loop
    update iara.waiting_list_entries set status = 'CANCELLED', position = null
    where student_id = any (v_extra) and preferred_unit_id = q.preferred_unit_id and grade_level_id = q.grade_level_id
      and status in ('WAITING', 'OFFERED', 'ACCEPTED');
    perform iara.recalculate_queue(q.preferred_unit_id, q.grade_level_id);
  end loop;
  delete from iara.student_guardians where student_id = any (v_extra);
  delete from iara.student_guardians
  where student_id in (v_ana, v_davi) and guardian_id not in (v_maria, coalesce(v_jorge, v_maria));

  -- 2. endereço, declarações e contatos originais
  update iara.guardians set cadunico_status = true, single_mother = false, primary_phone = '(44) 90000-4182',
         whatsapp_phone = '(44) 90000-4182', email = 'maria.aparecida@email.test', address_id = coalesce(v_addr, address_id)
  where id = v_maria;
  if v_addr is not null then
    update iara.guardians set address_id = v_addr where id = v_jorge;
    update iara.students set address_id = v_addr where id in (v_ana, v_davi);
  end if;
  update iara.waiting_list_entries set status = 'CANCELLED', position = null
  where student_id = v_ana and status in ('WAITING', 'OFFERED', 'ACCEPTED');

  -- 3. Davi volta a aguardar em 1º na fila de creche
  update iara.vacancy_offers set status = 'CANCELLED', decline_reason = 'Reinício do cenário de demonstração'
  where student_id = v_davi and status in ('OFFERED', 'ACCEPTED', 'ENROLLED');
  for e in select id, class_id from iara.enrollments where student_id = v_davi and status = 'ACTIVE' loop
    update iara.students set current_enrollment_id = null where id = v_davi;
    update iara.enrollments set status = 'CANCELLED', exit_type = 'REINICIO_DEMO', end_date = current_date where id = e.id;
  end loop;
  update iara.students set status = 'AGUARDANDO_VAGA', current_enrollment_id = null where id = v_davi;
  update iara.waiting_list_entries set status = 'WAITING', demand_category = 'SEM_ATENDIMENTO' where id = v_entry;
  update iara.waiting_list_entries set status = 'CANCELLED'
  where student_id = v_davi and id <> v_entry and status in ('WAITING', 'OFFERED', 'ACCEPTED');
  update iara.service_cases set status = 'ENCERRADO', closed_at = coalesce(closed_at, now()), resolution_code = 'INSERIDO_NA_FILA',
         resolution_notes = 'Sem vaga ofertável na creche da unidade preferida; criança inserida na fila.'
  where id = v_case;
  update iara.service_cases set status = 'ENCERRADO', closed_at = now(), resolution_code = 'REINICIO_DEMO',
         resolution_notes = 'Encerrado pelo reinício do cenário de demonstração.'
  where guardian_id = v_maria and id <> v_case and opened_at > coalesce(v_base, now() - interval '30 days')
    and status not in ('ENCERRADO', 'MATRICULA_CONCLUIDA');
  update iara.documents set status = 'PENDENTE', received_at = null, validated_at = null, file_name = null
  where student_id = v_davi and doc_type = 'VACINACAO';
  insert into iara.case_events (case_id, event_type, message, actor_label, visibility)
  values (v_case, 'NOTA', 'Cenário de demonstração reiniciado: família no estado original e Davi aguardando na fila.', coalesce(iara.my_label(), 'Sistema'), 'INTERNA');
  perform iara.compute_queue_priority(v_entry);
  perform iara.recalculate_queue(v_unit, 1::smallint);
  select position into v_pos from iara.waiting_list_entries where id = v_entry;
  perform iara.audit_event('DEMO_RESET', 'demo', 'cidadao', v_unit,
    format('Cenário do cidadão reiniciado: família original (%s membro(s) incluído(s) por visitantes removido(s) do cadastro), endereço e declarações restaurados.', cardinality(v_extra)));
  return jsonb_build_object('ok', true, 'posicao_davi', v_pos, 'membros_removidos', cardinality(v_extra));
end $$;

commit;
