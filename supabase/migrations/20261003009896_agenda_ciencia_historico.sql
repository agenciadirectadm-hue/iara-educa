-- IARA Educa — 098.96 · Agenda escolar no padrão dos avisos: data e hora do envio, ciência em todo recado da escola e histórico.
-- Decisão de Rob (05/11/2026): a mãe dava ciência num bilhete e o item ficava na lista, sem a hora da ciência e sem ir para o histórico; e só parte
-- dos recados tinha o botão. Agora todo recado da escola, inclusive os anteriores, pede ciência; depois dela sai da agenda e vai para o histórico,
-- com a hora. O bilhete que a própria família escreveu não pede ciência dela e segue na agenda pelo período de sempre.
-- Só aparece para a família o que já foi enviado: a demonstração gera recados com data futura, e "enviado em" no futuro não faria sentido.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

create or replace function iara.agenda_json(a iara.agenda_escolar, p_student uuid default null) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', a.id, 'class_id', a.class_id, 'turma', (select class_name from iara.classes where id = a.class_id),
    'student_id', a.student_id, 'aluno', (select full_name from iara.students where id = a.student_id), 'origem', a.origem, 'tipo', a.tipo,
    'titulo', a.titulo, 'texto', a.texto, 'data', a.data, 'exige_ciencia', a.origem = 'ESCOLA',
    'autor', regexp_replace(a.autor_label, '\s*\(demo #[^)]*\)', ''), 'criado_em', a.created_at, 'is_demo', a.is_demo,
    'destinatarios', case when a.student_id is not null then 1 else (select count(*) from iara.enrollments e where e.class_id = a.class_id and e.status = 'ACTIVE') end,
    'ciencias', a.ciencias_demo + (select count(*) from iara.agenda_ciencia c where c.agenda_id = a.id),
    'ciente', case when p_student is not null then exists (select 1 from iara.agenda_ciencia c where c.agenda_id = a.id and c.student_id = p_student) end,
    -- a hora da ciência: da criança pedida ou, no bilhete individual, do aluno dele (a professora vê quando a família confirmou)
    'ciente_em', (select c.ciente_em from iara.agenda_ciencia c where c.agenda_id = a.id and c.student_id = coalesce(p_student, a.student_id)))
$$;

create or replace function api.familia_agenda(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_lista jsonb;
  v_hist jsonb;
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  -- agenda: o que a escola enviou e ainda não teve ciência, sem limite de idade, e os bilhetes da própria família no período
  select coalesce(jsonb_agg(iara.agenda_json(a, k.student_id) || jsonb_build_object('filho', k.primeiro_nome, 'filho_id', k.student_id)
                            order by a.data desc, a.created_at desc), '[]') into v_lista
  from (select s.id student_id, split_part(s.full_name, ' ', 1) primeiro_nome, e.class_id
        from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
        where s.id in (select iara.my_student_ids())) k
  join lateral (select * from iara.agenda_escolar a where a.class_id = k.class_id and (a.student_id is null or a.student_id = k.student_id)
                  and a.created_at <= now() and a.data <= current_date + 30
                  and not exists (select 1 from iara.agenda_ciencia c where c.agenda_id = a.id and c.student_id = k.student_id)
                  and (a.origem = 'ESCOLA' or a.data >= current_date - coalesce(nullif(p ->> 'dias', '')::int, 21))
                order by a.data desc, a.created_at desc limit 40) a on true;
  -- histórico: o que teve ciência, com a hora
  select coalesce(jsonb_agg(iara.agenda_json(q.a, q.student_id) || jsonb_build_object('filho', q.primeiro_nome, 'filho_id', q.student_id) order by q.ciente_em desc), '[]') into v_hist
  from (select a, c.student_id, c.ciente_em, split_part(s.full_name, ' ', 1) primeiro_nome
        from iara.agenda_ciencia c join iara.agenda_escolar a on a.id = c.agenda_id join iara.students s on s.id = c.student_id
        where c.student_id in (select iara.my_student_ids())
        order by c.ciente_em desc limit 100) q;
  return jsonb_build_object('itens', v_lista, 'historico', v_hist,
    'aguardando_ciencia', (select count(*) from jsonb_array_elements(v_lista) x where x ->> 'origem' = 'ESCOLA'),
    'hoje', (select count(*) from jsonb_array_elements(v_lista) x where (x ->> 'data')::date = current_date));
end $$;

create or replace function api.familia_agenda_ciente(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  a iara.agenda_escolar;
  v_student uuid := (p ->> 'student_id')::uuid;
begin
  select * into a from iara.agenda_escolar where id = (p ->> 'id')::uuid;
  if a.id is null or iara.my_guardian() is null or not (v_student in (select iara.my_student_ids()))
     or not exists (select 1 from iara.enrollments e where e.student_id = v_student and e.class_id = a.class_id and e.status = 'ACTIVE')
     or (a.student_id is not null and a.student_id <> v_student) then
    raise exception 'Recado não encontrado.' using errcode = 'P0002';
  end if;
  insert into iara.agenda_ciencia (agenda_id, student_id, guardian_id) values (a.id, v_student, iara.my_guardian()) on conflict do nothing;
  return jsonb_build_object('ok', true, 'ciente_em', (select ciente_em from iara.agenda_ciencia where agenda_id = a.id and student_id = v_student));
end $$;

-- demonstração: todo recado da escola pede ciência, e a contagem acompanha
create or replace function iara.demo_gerar_agenda_periodo(p_de date, p_ate date) returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  insert into iara.agenda_escolar (unit_id, class_id, origem, tipo, titulo, texto, data, exige_ciencia, autor_label, ciencias_demo, created_at, is_demo)
  select c.unit_id, c.id, 'ESCOLA', t.tipo, t.titulo, t.texto, d::date, true,
         case when iara.faixa_cardapio(gl.code) = 'EF' then 'Professor(a) da turma (demonstração)' else 'Professora regente (demonstração)' end,
         round(x.n * least(0.92, case when d::date < current_date then 0.62 + (x.h % 25) / 100.0 else 0.18 + (x.h % 30) / 100.0 end))::int,
         d::date - interval '1 day' + interval '17 hours', true
  from iara.classes c join iara.grade_levels gl on gl.id = c.grade_level_id
  cross join generate_series(p_de, p_ate, interval '1 day') d
  cross join lateral (select abs(hashtext(c.id::text || d::date::text || 'ag')) h,
                             (select count(*) from iara.enrollments e where e.class_id = c.id and e.status = 'ACTIVE') n) x
  cross join lateral (select * from (values
      ('INF', 'MATERIAL', 'Muda de roupa', 'Mandar uma muda de roupa extra identificada na mochila.'),
      ('INF', 'RECADO', 'Contação de histórias', 'Amanhã teremos contação de histórias: se quiser, mande o livro preferido da criança.'),
      ('INF', 'MATERIAL', 'Higiene', 'Enviar escova e creme dental identificados com o nome.'),
      ('INF', 'LEMBRETE', 'Protetor solar', 'Teremos atividade no pátio: protetor solar e boné na mochila.'),
      ('INF', 'EVENTO', 'Dia do brinquedo', 'Sexta é o dia do brinquedo: a criança pode trazer um brinquedo (sem peças pequenas).'),
      ('INF', 'TAREFA', 'Desenho da família', 'Fazer em casa um desenho da família e trazer na segunda-feira.'),
      ('EF', 'TAREFA', 'Matemática', 'Livro de Matemática, página 45, exercícios 1 a 5.'),
      ('EF', 'TAREFA', 'Leitura', 'Ler o capítulo 3 do livro da biblioteca e contar a história em casa.'),
      ('EF', 'TAREFA', 'Pesquisa', 'Pesquisar uma lenda do Paraná com a família e trazer escrita no caderno.'),
      ('EF', 'RECADO', 'Avaliação', 'Avaliação de Língua Portuguesa na quinta-feira: revisar o caderno.'),
      ('EF', 'MATERIAL', 'Material', 'Trazer régua, cola e tesoura sem ponta.'),
      ('EF', 'LEMBRETE', 'Biblioteca', 'Devolver o livro da biblioteca até sexta-feira.'),
      ('EF', 'EVENTO', 'Feira de ciências', 'Feira de ciências da escola na próxima semana: as famílias estão convidadas.')) v(fx, tipo, titulo, texto)
    where v.fx = case when iara.faixa_cardapio(gl.code) = 'EF' then 'EF' else 'INF' end
    offset (x.h / 11) % case when iara.faixa_cardapio(gl.code) = 'EF' then 7 else 6 end limit 1) t
  where c.status = 'ATIVA' and iara.dia_letivo(d::date, c.unit_id) and x.h % 100 < 40
    and not exists (select 1 from iara.agenda_escolar a where a.class_id = c.id and a.data = d::date and a.is_demo and a.student_id is null);
  get diagnostics v_n = row_count;
  perform set_config('iara.skip_audit', 'off', true);
  return v_n;
end $$;

update iara.agenda_escolar a set exige_ciencia = true,
       ciencias_demo = case when a.is_demo and a.ciencias_demo = 0 and a.student_id is null
         then round((select count(*) from iara.enrollments e where e.class_id = a.class_id and e.status = 'ACTIVE') * (0.45 + abs(hashtext(a.id::text)) % 40 / 100.0))::int
         else a.ciencias_demo end
where a.origem = 'ESCOLA' and not a.exige_ciencia;

commit;
