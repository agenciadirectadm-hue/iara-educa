-- IARA Educa — Pesquisa global mais rápida.
-- Com RLS, o Postgres não usa o índice de nome: `like` não é "leakproof" e só roda depois do filtro de segurança, então cada
-- busca lia as 32 mil crianças e os 35 mil responsáveis (cerca de 400 ms, mesmo sem nenhum resultado).
-- Agora as funções abaixo acham os candidatos pelo índice e só devolvem ids; quem decide o que a pessoa vê continua sendo a RLS,
-- na consulta de api.global_search, que segue SECURITY INVOKER.
begin;

create or replace function iara.busca_alunos(p_padrao text, p_digitos text) returns uuid[]
language sql stable security definer set search_path = iara, public
as $$
  select coalesce(array_agg(x.id), '{}') from (
    select s.id from iara.students s where iara.norm(s.full_name) like p_padrao
    union
    select s.id from iara.students s where length(p_digitos) >= 6 and s.student_registry_number = p_digitos
  ) x
$$;

create or replace function iara.busca_responsaveis(p_padrao text, p_digitos text) returns uuid[]
language sql stable security definer set search_path = iara, public
as $$
  select coalesce(array_agg(x.id), '{}') from (
    select g.id from iara.guardians g where iara.norm(g.full_name) like p_padrao
    union
    select g.id from iara.guardians g where length(p_digitos) >= 8
      and regexp_replace(coalesce(g.cpf, '') || coalesce(g.primary_phone, ''), '\D', '', 'g') like '%' || p_digitos || '%'
  ) x
$$;

revoke execute on function iara.busca_alunos(text, text), iara.busca_responsaveis(text, text) from public, anon;
grant execute on function iara.busca_alunos(text, text), iara.busca_responsaveis(text, text) to authenticated;

create or replace function api.global_search(p jsonb) returns jsonb
language plpgsql stable security invoker set search_path = iara, public
as $$
declare
  v_q text := iara.norm(trim(coalesce(p ->> 'q', '')));
  v_dig text := regexp_replace(coalesce(p ->> 'q', ''), '\D', '', 'g');
  v_padrao text := '%' || replace(replace(replace(iara.norm(trim(coalesce(p ->> 'q', ''))), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  v_alunos uuid[] := '{}';
  v_resp uuid[] := '{}';
  v jsonb;
begin
  if length(v_q) >= 3 then
    v_alunos := iara.busca_alunos(v_padrao, v_dig);
    v_resp := iara.busca_responsaveis(v_padrao, v_dig);
  end if;
  select jsonb_build_object(
    'students', coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('id', s.id, 'name', s.full_name, 'sub', 'Matrícula ' || s.student_registry_number || ' · ' || iara.age_text(s.birth_date),
                                'status', s.status) as x
      from iara.students s where s.id = any (v_alunos)
      order by s.full_name limit 8) z), '[]'::jsonb),
    'guardians', coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('id', g.id, 'name', g.full_name,
                                'sub', case when iara.can_see_contacts() then coalesce(g.primary_phone, '') else iara.mask_phone(g.primary_phone) end) as x
      from iara.guardians g where g.id = any (v_resp)
      order by g.full_name limit 6) z), '[]'::jsonb),
    'units', coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('id', u.id, 'name', u.name, 'sub', coalesce(u.neighborhood, '') || ' · ' || u.unit_type_label) as x
      from iara.education_units u where length(v_q) >= 2 and iara.norm(u.name || ' ' || coalesce(u.neighborhood, '')) like v_padrao
      order by u.short_name limit 6) z), '[]'::jsonb),
    'classes', coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('id', c.id, 'name', c.class_name || ' · ' || u.short_name, 'sub', c.offerable_vacancies_count || ' vaga(s) ofertável(is)') as x
      from iara.classes c join iara.education_units u on u.id = c.unit_id
      where length(v_q) >= 3 and iara.norm(c.class_name || ' ' || u.name) like v_padrao order by u.short_name, c.class_code limit 6) z), '[]'::jsonb),
    'cases', coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('id', sc.id, 'name', sc.protocol_number, 'sub', sc.subject, 'status', sc.status) as x
      from iara.service_cases sc where length(v_q) >= 3
        and (lower(sc.protocol_number) like v_padrao or iara.norm(sc.subject) like v_padrao)
      order by sc.opened_at desc limit 6) z), '[]'::jsonb)
  ) into v;
  return v;
end $$;

commit;
