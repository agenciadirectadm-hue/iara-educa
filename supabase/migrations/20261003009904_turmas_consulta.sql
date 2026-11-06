-- IARA Educa — 099.04 · Turmas de uma etapa na consulta de unidades, para todo servidor.
-- Unidades entrou no menu de todos os perfis. Quem não tem acesso às turmas daquela unidade (direção de outra escola, AEE, manutenção...) via as etapas
-- e, ao abrir uma, a tela ficava em branco: api.unit_classes respeita a RLS e devolve lista vazia, sem erro.
-- Esta consulta traz só o que não identifica pessoas: nome da turma, turno, capacidade, matrículas, vagas e fila. Sem regente, sem sala e sem alunos.
-- A ficha da turma (/turmas/:id) continua restrita a quem é da rede ou da unidade. Família e visitante continuam vendo o resumo da etapa.
begin;

create or replace function api.unit_classes_consulta(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if not (iara.e_servidor() or iara.my_role() = 'CONTROLE_EXTERNO') then
    raise exception 'Consulta disponível para os servidores da rede.' using errcode = '42501';
  end if;
  return jsonb_build_object('items', coalesce((
    select jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.class_name, 'grade_level_id', c.grade_level_id, 'grade', gl.name, 'stage_id', c.stage_id, 'shift', c.shift,
        'capacity', c.authorized_capacity, 'enrolled', c.active_enrollments_count, 'blocked', c.blocked_seats_count,
        'reserved', c.reserved_seats_count, 'offerable', c.offerable_vacancies_count,
        'queue', (select count(*) from iara.waiting_list_entries w where w.preferred_unit_id = c.unit_id and w.grade_level_id = c.grade_level_id and w.status = 'WAITING'))
      order by gl.sort, c.class_code)
    from iara.classes c join iara.grade_levels gl on gl.id = c.grade_level_id
    where c.unit_id = (p ->> 'unit_id')::int and c.status = 'ATIVA'), '[]'::jsonb));
end $$;

revoke all on function api.unit_classes_consulta(jsonb) from public, anon;
grant execute on function api.unit_classes_consulta(jsonb) to authenticated;

commit;
