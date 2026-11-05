-- IARA Educa — 098.9 · Histórico escolar da família: criança sem histórico não derruba a tela.
-- Para quem ainda não tem matrícula (o Davi, na fila da creche), o histórico vem vazio, e a lista ia com um item nulo: a tela da família caía em
-- "Algo saiu do lugar". Agora a lista traz só as crianças que têm histórico.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

create or replace function api.familia_historico(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(q.h || jsonb_build_object('student_id', q.id, 'primeiro_nome', split_part(q.full_name, ' ', 1)) order by q.full_name), '[]')
          from (select s.id, s.full_name, api.historico_aluno(jsonb_build_object('student_id', s.id)) h
                from iara.students s where s.id in (select iara.my_student_ids())) q
          where q.h is not null);
end $$;

commit;
