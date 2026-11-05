-- IARA Educa — 098.8 · O recado da família chega à vista da professora.
-- O bilhete entrava na agenda da turma, mas a tela inicial da professora não mostrava nada: ela só via se abrisse o Diário de classe.
-- Agora a tela inicial lista os bilhetes das famílias das turmas dela, e a resposta à família diz onde o recado aparece.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

create or replace function api.familia_agenda_enviar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_txt text := btrim(coalesce(p ->> 'texto', ''));
  e record;
  a iara.agenda_escolar;
begin
  if iara.my_guardian() is null or not (v_student in (select iara.my_student_ids())) then raise exception 'Criança não vinculada a você.' using errcode = '42501'; end if;
  if length(v_txt) not between 3 and 1000 then raise exception 'Escreva o bilhete (até 1.000 caracteres).' using errcode = '22023'; end if;
  select en.unit_id, en.class_id into e from iara.enrollments en where en.student_id = v_student and en.status = 'ACTIVE' limit 1;
  if e.class_id is null then raise exception 'A criança não tem matrícula ativa.' using errcode = '22023'; end if;
  insert into iara.agenda_escolar (unit_id, class_id, student_id, origem, tipo, texto, data, autor_label, autor_guardian, is_demo)
  values (e.unit_id, e.class_id, v_student, 'FAMILIA', 'BILHETE', v_txt, current_date, iara.my_label(), iara.my_guardian(), false)
  returning * into a;
  perform iara.audit_event('AGENDA_BILHETE_FAMILIA', 'student', v_student::text, e.unit_id, 'Bilhete da família na agenda escolar.');
  return iara.agenda_json(a, v_student) || jsonb_build_object('mensagem', 'Bilhete entregue: a professora vê na tela inicial dela, e a direção, na agenda da turma.');
end $$;

-- bilhetes das famílias nas turmas de quem está na sessão (só as turmas dela; a direção segue pela agenda de cada turma)
create or replace function api.agenda_recados_familia(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_dias integer := greatest(least(coalesce(nullif(p ->> 'dias', '')::int, 3), 30), 0);
begin
  perform iara.require_perm('agenda.write');
  return (select coalesce(jsonb_agg(iara.agenda_json(q) order by q.data desc, q.created_at desc), '[]')
          from (select a.* from iara.agenda_escolar a
                where a.origem = 'FAMILIA' and a.class_id = any (iara.minhas_turmas()) and a.data >= iara.hoje_local() - v_dias
                order by a.data desc, a.created_at desc limit 30) q);
end $$;

commit;
