-- =============================================================================
-- IARA Educa · Dados de demonstração para os critérios da IN nº 025/2025-SEDUC (Anexo I)
-- (fictícios, determinísticos por id; executados por iara.demo_generate e uma vez na atualização das regras)
--  · mãe solo: ~30% das mães que são a única responsável cadastrada da criança (declaração fictícia)
--  · laudo médico com CID (documento sensível) para crianças com indicação de AEE na fila: ~60% validados, ~40% recebidos
-- =============================================================================
create or replace function iara.demo_family_criteria() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_mothers integer;
  v_laudos integer;
begin
  update iara.guardians g set single_mother = (abs(hashtext(g.id::text || ':mae-solo')) % 100) < 30
  where g.is_demo and g.gender = 'F'
    and exists (select 1 from iara.student_guardians sg where sg.guardian_id = g.id and sg.relationship = 'MAE')
    and not exists (select 1 from iara.student_guardians sg
                    join iara.student_guardians o on o.student_id = sg.student_id and o.guardian_id <> sg.guardian_id
                    where sg.guardian_id = g.id);

  insert into iara.documents (tenant_id, student_id, doc_type, status, file_name, received_at, validated_at, notes, is_sensitive, is_demo)
  select 1, s.id, 'LAUDO', x.st, 'laudo_medico_cid.pdf', now() - interval '21 days',
         case when x.st = 'VALIDADO' then now() - interval '14 days' end,
         'Laudo médico com CID — demonstração (conteúdo restrito)', true, true
  from iara.students s
  cross join lateral (select case when abs(hashtext(s.id::text || ':laudo')) % 100 < 60 then 'VALIDADO' else 'RECEBIDO' end as st) x
  where s.is_demo and s.aee_status
    and exists (select 1 from iara.waiting_list_entries w where w.student_id = s.id and w.status in ('WAITING', 'OFFERED', 'ACCEPTED'))
    and not exists (select 1 from iara.documents d where d.student_id = s.id and d.doc_type = 'LAUDO');

  select count(*) into v_mothers from iara.guardians where single_mother;
  select count(*) into v_laudos from iara.documents where doc_type = 'LAUDO';
  return jsonb_build_object('maes_solo', v_mothers, 'laudos', v_laudos);
end $$;

-- Cenário do cidadão: Davi (irmã matriculada + CadÚnico + até 2 km = 95 pontos) segue em 1º na fila de creche.
-- Se alguma declaração fictícia de mãe solo colocar outra criança à frente, essa declaração é desfeita (apenas na demo).
create or replace function iara.demo_ensure_davi_first() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  w iara.waiting_list_entries;
  v_entry uuid := nullif(iara.setting('demo_entry_davi'), '')::uuid;
begin
  select * into w from iara.waiting_list_entries where id = v_entry;
  if not found or w.status <> 'WAITING' then
    return jsonb_build_object('ok', true, 'posicao_davi', w.position, 'status', w.status);
  end if;
  if w.position > 1 then
    update iara.guardians g set single_mother = false
    where g.single_mother and g.is_demo and g.id in (
      select sg.guardian_id from iara.waiting_list_entries x join iara.student_guardians sg on sg.student_id = x.student_id
      where x.preferred_unit_id = w.preferred_unit_id and x.grade_level_id = w.grade_level_id and x.status = 'WAITING'
        and x.position < w.position);
    perform iara.compute_queue_priority(x.id) from iara.waiting_list_entries x
    where x.preferred_unit_id = w.preferred_unit_id and x.grade_level_id = w.grade_level_id and x.status in ('WAITING', 'OFFERED', 'ACCEPTED');
    perform iara.recalculate_queue(w.preferred_unit_id, w.grade_level_id);
    select * into w from iara.waiting_list_entries where id = v_entry;
  end if;
  return jsonb_build_object('ok', w.position = 1, 'posicao_davi', w.position, 'pontuacao', w.priority_score);
end $$;

-- Aplicação única na base já gerada (atualização para as regras 2026.02)
create or replace function iara.demo_apply_in025() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_criteria jsonb;
  v_davi jsonb;
begin
  v_criteria := iara.demo_family_criteria();
  perform iara.compute_queue_priority(id) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED', 'ACCEPTED');
  perform iara.recalculate_all_queues();
  v_davi := iara.demo_ensure_davi_first();
  return v_criteria || v_davi;
end $$;

revoke all on function iara.demo_family_criteria(), iara.demo_ensure_davi_first(), iara.demo_apply_in025() from public, anon, authenticated;
