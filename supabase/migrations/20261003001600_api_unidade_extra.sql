-- IARA Educa — 016 · Alunos e equipe por unidade (SECURITY INVOKER: a RLS limita ao escopo do perfil)
begin;

create or replace function api.unit_students(p jsonb) returns jsonb
language sql stable security invoker set search_path = iara, public
as $$
  with base as (
    select s.id, s.full_name, s.birth_date, s.avatar_seed, s.aee_status, s.transport_need, s.student_registry_number,
           c.id as class_id, c.class_name, c.shift, gl.name as grade, gl.sort
    from iara.enrollments e
    join iara.students s on s.id = e.student_id
    join iara.classes c on c.id = e.class_id
    join iara.grade_levels gl on gl.id = c.grade_level_id
    where e.unit_id = (p ->> 'unit_id')::int and e.status = 'ACTIVE'
      and (nullif(p ->> 'q', '') is null or iara.norm(s.full_name) like '%' || iara.norm(p ->> 'q') || '%')
  )
  select jsonb_build_object(
    'visible', iara.has_perm('students.read'),
    'total', (select count(*) from base),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.full_name, 'age', iara.age_text(b.birth_date), 'avatar_seed', b.avatar_seed,
                                                           'aee', b.aee_status, 'transport', b.transport_need, 'registry', b.student_registry_number,
                                                           'class_id', b.class_id, 'class', b.class_name, 'shift', b.shift, 'grade', b.grade)
                                        order by b.sort, b.class_name, b.full_name)
                       from (select * from base order by sort, class_name, full_name limit coalesce((p ->> 'limit')::int, 300)) b), '[]'::jsonb))
$$;

create or replace function api.unit_staff(p jsonb) returns jsonb
language sql stable security invoker set search_path = iara, public
as $$
  select jsonb_build_object('items', coalesce(jsonb_agg(jsonb_build_object(
      'id', s.id, 'name', s.full_name, 'role', s.role, 'bond', s.bond,
      'classes', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.class_name, 'shift', c.shift, 'role', cs.role_type) order by c.class_code), '[]'::jsonb)
                  from iara.class_staff cs join iara.classes c on c.id = cs.class_id where cs.staff_id = s.id))
      order by case s.role when 'PROFESSOR' then 1 when 'EDUCADOR' then 1 when 'AUXILIAR' then 2 when 'AEE' then 3 else 4 end, s.full_name), '[]'::jsonb),
    'source', 'DEMO — nomes fictícios; tamanho da equipe docente baseado no nº de docentes do Censo 2025')
  from iara.staff s where s.unit_id = (p ->> 'unit_id')::int
$$;

grant execute on function api.unit_students(jsonb), api.unit_staff(jsonb) to authenticated;

commit;
