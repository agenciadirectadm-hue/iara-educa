-- IARA Educa — 065 · Biblioteca escolar (Sprint 4)
-- Acervo da rede (títulos) e exemplares de cada unidade (tombo, estado, origem PNLD/doação/compra); empréstimo e devolução com prazo,
-- renovação e reserva (fila por título); na educação infantil, a “sacola literária” (empréstimo semanal). A família vê o que o filho
-- levou, quando devolve, renova e reserva — no portal e pela IARA. Regras propostas (a validar): 14 dias no fundamental, 7 na educação
-- infantil, 21 para servidores; até 2 renovações sem reserva de outro leitor; até 2 livros por aluno (1 na educação infantil); atraso
-- não gera multa, mas segura um novo empréstimo até a devolução.
begin;

insert into iara.permissions (code, description, is_sensitive) values
  ('biblioteca.read', 'Consultar o acervo e os empréstimos da biblioteca', false),
  ('biblioteca.write', 'Emprestar, devolver e renovar livros da biblioteca', false),
  ('biblioteca.acervo', 'Cadastrar títulos e exemplares e dar baixa no acervo', false)
on conflict (code) do update set description = excluded.description, is_sensitive = excluded.is_sensitive;
insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('DIRETOR_UNIDADE', 'biblioteca.read'), ('DIRETOR_UNIDADE', 'biblioteca.write'), ('DIRETOR_UNIDADE', 'biblioteca.acervo'),
  ('SECRETARIA_ESCOLAR', 'biblioteca.read'), ('SECRETARIA_ESCOLAR', 'biblioteca.write'), ('SECRETARIA_ESCOLAR', 'biblioteca.acervo'),
  ('PROFESSOR', 'biblioteca.read'), ('PROFESSOR', 'biblioteca.write'), ('PROFESSOR_AEE', 'biblioteca.read'),
  ('SECRETARIO', 'biblioteca.read'), ('SUPERINTENDENCIA', 'biblioteca.read'), ('GERENCIA_EI', 'biblioteca.read'), ('INOVACAO', 'biblioteca.read')
) v(r, p)
on conflict do nothing;

create table if not exists iara.biblioteca_titulos (
  id uuid primary key default gen_random_uuid(),
  isbn text,
  titulo text not null,
  autor text not null,
  editora text,
  ano_publicacao smallint,
  genero text not null check (genero in ('LITERATURA_INFANTIL', 'INFANTOJUVENIL', 'POESIA', 'CONTOS_FABULAS', 'HISTORIA_EM_QUADRINHOS', 'INFORMATIVO', 'DIDATICO', 'REFERENCIA', 'OUTRO')),
  faixa text not null default 'TODAS' check (faixa in ('EI', 'EF_INICIAIS', 'TODAS')),
  pnld boolean not null default false,
  criado_em timestamptz not null default now(),
  is_demo boolean not null default false
);
create table if not exists iara.biblioteca_exemplares (
  id uuid primary key default gen_random_uuid(),
  titulo_id uuid not null references iara.biblioteca_titulos(id) on delete cascade,
  unit_id integer not null references iara.education_units(id),
  tombo text not null,
  estado text not null default 'BOM' check (estado in ('BOM', 'REGULAR', 'DANIFICADO', 'EXTRAVIADO', 'BAIXADO')),
  origem text not null default 'PNLD' check (origem in ('PNLD', 'DOACAO', 'COMPRA', 'OUTRO')),
  localizacao text,
  adquirido_em date,
  baixa_motivo text,
  criado_em timestamptz not null default now(),
  alterado_em timestamptz,
  is_demo boolean not null default false,
  unique (unit_id, tombo)
);
create index if not exists biblioteca_exemplares_titulo_idx on iara.biblioteca_exemplares (titulo_id, unit_id);
create table if not exists iara.biblioteca_emprestimos (
  id uuid primary key default gen_random_uuid(),
  exemplar_id uuid not null references iara.biblioteca_exemplares(id) on delete cascade,
  unit_id integer not null,
  student_id uuid references iara.students(id) on delete cascade,
  staff_id uuid references iara.staff(id) on delete set null,
  leitor_nome text not null,
  retirada_em timestamptz not null default now(),
  prevista date not null,
  devolvido_em timestamptz,
  renovacoes smallint not null default 0,
  estado_devolucao text check (estado_devolucao in ('BOM', 'REGULAR', 'DANIFICADO', 'EXTRAVIADO')),
  alterado_em timestamptz,
  registrado_por_label text,
  devolvido_por_label text,
  is_demo boolean not null default false
);
create unique index if not exists biblioteca_emprestimo_ativo on iara.biblioteca_emprestimos (exemplar_id) where devolvido_em is null;
create index if not exists biblioteca_emprestimos_aluno_idx on iara.biblioteca_emprestimos (student_id, retirada_em desc);
create index if not exists biblioteca_emprestimos_unit_idx on iara.biblioteca_emprestimos (unit_id, devolvido_em);
create table if not exists iara.biblioteca_reservas (
  id uuid primary key default gen_random_uuid(),
  titulo_id uuid not null references iara.biblioteca_titulos(id) on delete cascade,
  unit_id integer not null,
  student_id uuid not null references iara.students(id) on delete cascade,
  situacao text not null default 'ATIVA' check (situacao in ('ATIVA', 'DISPONIVEL', 'ATENDIDA', 'CANCELADA')),
  canal text,
  criada_em timestamptz not null default now(),
  avisada_em timestamptz,
  encerrada_em timestamptz,
  is_demo boolean not null default false
);
create unique index if not exists biblioteca_reserva_unica on iara.biblioteca_reservas (titulo_id, student_id) where situacao in ('ATIVA', 'DISPONIVEL');
alter table iara.biblioteca_titulos enable row level security;
alter table iara.biblioteca_exemplares enable row level security;
alter table iara.biblioteca_emprestimos enable row level security;
alter table iara.biblioteca_reservas enable row level security;

alter table iara.biblioteca_emprestimos add column if not exists alterado_em timestamptz;

-- devolução cai em dia útil (sábado e domingo passam para segunda)
create or replace function iara.bib_dia_util(p date) returns date
language sql immutable as $$ select p + case extract(isodow from p)::int when 6 then 2 when 7 then 1 else 0 end $$;

-- regras (proposta a validar)
create or replace function iara.bib_prazo_dias(p_student uuid) returns integer
language sql stable security definer set search_path = iara, public
as $$
  select case when p_student is null then 21
              when exists (select 1 from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
                           where e.student_id = p_student and e.status = 'ACTIVE' and gl.code in ('CRECHE', 'PRE')) then 7 else 14 end
$$;
create or replace function iara.bib_limite(p_student uuid) returns integer
language sql stable security definer set search_path = iara, public
as $$ select case when iara.bib_prazo_dias(p_student) = 7 then 1 else 2 end $$;

create or replace function iara.bib_unidade() returns integer
language sql stable security definer set search_path = iara, public
as $$ select case when iara.my_scope() = 'UNIT' then iara.my_unit() end $$;

create or replace function iara.bib_emprestimo_json(x iara.biblioteca_emprestimos, p_familia boolean default false) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', x.id, 'exemplar_id', x.exemplar_id, 'tombo', ex.tombo, 'titulo', t.titulo, 'autor', t.autor, 'titulo_id', t.id,
    'leitor', case when p_familia then split_part(x.leitor_nome, ' ', 1) else x.leitor_nome end, 'student_id', x.student_id,
    'retirada_em', x.retirada_em, 'prevista', x.prevista, 'devolvido_em', x.devolvido_em, 'renovacoes', x.renovacoes,
    'atrasado', x.devolvido_em is null and x.prevista < iara.hoje_local(), 'dias_atraso', case when x.devolvido_em is null and x.prevista < iara.hoje_local() then iara.hoje_local() - x.prevista end,
    'pode_renovar', x.devolvido_em is null and x.renovacoes < 2 and x.prevista >= iara.hoje_local() - 15
                    and not exists (select 1 from iara.biblioteca_reservas r where r.titulo_id = t.id and r.unit_id = x.unit_id and r.situacao = 'ATIVA' and r.student_id is distinct from x.student_id),
    'unidade', (select short_name from iara.education_units where id = x.unit_id), 'is_demo', x.is_demo)
  from iara.biblioteca_exemplares ex join iara.biblioteca_titulos t on t.id = ex.titulo_id where ex.id = x.exemplar_id
$$;

-- painel da unidade (ou da rede, só números)
create or replace function api.biblioteca_painel(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := coalesce(iara.bib_unidade(), nullif(p ->> 'unit_id', '')::int);
  v_ano_ini date := make_date(extract(year from iara.hoje_local())::int, 1, 1);
begin
  perform iara.require_perm('biblioteca.read');
  if v_unit is not null and not iara.can_access_unit(v_unit) then raise exception 'Unidade fora do seu escopo.' using errcode = '42501'; end if;
  return (with ex as (select * from iara.biblioteca_exemplares where (v_unit is null or unit_id = v_unit) and estado not in ('BAIXADO')),
               em as (select * from iara.biblioteca_emprestimos where (v_unit is null or unit_id = v_unit) and retirada_em >= v_ano_ini)
    select jsonb_build_object('unit_id', v_unit,
      'pode_emprestar', iara.has_perm('biblioteca.write') and v_unit is not null and v_unit = iara.bib_unidade(),
      'pode_acervo', iara.has_perm('biblioteca.acervo') and v_unit is not null and v_unit = iara.bib_unidade(),
      'acervo', (select jsonb_build_object('titulos', count(distinct titulo_id), 'exemplares', count(*), 'extraviados', count(*) filter (where estado = 'EXTRAVIADO'),
                  'danificados', count(*) filter (where estado = 'DANIFICADO')) from ex),
      'emprestados', (select count(*) from em where devolvido_em is null),
      'atrasados', (select count(*) from em where devolvido_em is null and prevista < iara.hoje_local()),
      'leituras_ano', (select count(*) from em where student_id is not null),
      'leitores_mes', (select count(distinct coalesce(student_id::text, leitor_nome)) from em where retirada_em >= iara.hoje_local() - 30),
      'reservas', (select count(*) from iara.biblioteca_reservas r where (v_unit is null or r.unit_id = v_unit) and r.situacao in ('ATIVA', 'DISPONIVEL')),
      'por_mes', (select coalesce(jsonb_agg(jsonb_build_object('mes', m, 'n', n) order by m), '[]') from (
                   select date_trunc('month', retirada_em at time zone 'America/Sao_Paulo')::date m, count(*) n from em group by 1) z),
      'mais_lidos', (select coalesce(jsonb_agg(jsonb_build_object('titulo_id', t.id, 'titulo', t.titulo, 'autor', t.autor, 'n', z.n) order by z.n desc), '[]') from (
                      select ex2.titulo_id, count(*) n from em join iara.biblioteca_exemplares ex2 on ex2.id = em.exemplar_id group by 1 order by 2 desc limit 10) z
                     join iara.biblioteca_titulos t on t.id = z.titulo_id),
      'turmas', case when v_unit is not null then (select coalesce(jsonb_agg(jsonb_build_object('class_id', c.id, 'turma', c.class_name, 'alunos', z.alunos, 'leituras', z.n,
                     'por_aluno', round(z.n::numeric / nullif(z.alunos, 0), 1)) order by c.class_name), '[]')
                   from (select e.class_id, count(distinct e.student_id) alunos, count(em.id) n from iara.enrollments e
                         left join em on em.student_id = e.student_id where e.unit_id = v_unit and e.status = 'ACTIVE' group by 1) z join iara.classes c on c.id = z.class_id) end,
      'unidades', case when v_unit is null then (select coalesce(jsonb_agg(jsonb_build_object('unit_id', u.id, 'unidade', u.short_name, 'exemplares', z.ex, 'leituras', z.n, 'atrasados', z.at) order by z.n desc), '[]')
                   from (select x.unit_id, count(*) ex, (select count(*) from em where em.unit_id = x.unit_id) n,
                                (select count(*) from em where em.unit_id = x.unit_id and em.devolvido_em is null and em.prevista < iara.hoje_local()) at
                         from ex x group by 1) z join iara.education_units u on u.id = z.unit_id) end,
      'ativos', case when v_unit is not null then (select coalesce(jsonb_agg(iara.bib_emprestimo_json(x) order by (x.prevista < iara.hoje_local()) desc, x.prevista), '[]')
                   from (select * from iara.biblioteca_emprestimos where unit_id = v_unit and devolvido_em is null order by prevista limit 300) x) end,
      'reservas_lista', case when v_unit is not null then (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'titulo', t.titulo, 'aluno', s.full_name, 'situacao', r.situacao, 'criada_em', r.criada_em) order by r.criada_em), '[]')
                   from iara.biblioteca_reservas r join iara.biblioteca_titulos t on t.id = r.titulo_id join iara.students s on s.id = r.student_id
                   where r.unit_id = v_unit and r.situacao in ('ATIVA', 'DISPONIVEL')) end,
      'regras', 'Proposta a validar: 14 dias no fundamental, 7 na educação infantil (sacola literária), 21 para servidores; até 2 renovações; até 2 livros por aluno (1 na educação infantil).'));
end $$;

-- acervo com disponibilidade na unidade
create or replace function api.biblioteca_acervo(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := coalesce(iara.bib_unidade(), nullif(p ->> 'unit_id', '')::int);
  v_q text := nullif(iara.norm(btrim(coalesce(p ->> 'q', ''))), '');
  v_fam boolean := iara.my_guardian() is not null;
begin
  if v_fam then
    -- a família consulta o acervo da escola do filho
    v_unit := (select e.unit_id from iara.enrollments e where e.student_id = (p ->> 'student_id')::uuid and e.status = 'ACTIVE' and e.student_id in (select iara.my_student_ids()) limit 1);
    if v_unit is null then raise exception 'Escolha a criança.' using errcode = '22023'; end if;
  else
    perform iara.require_perm('biblioteca.read');
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'titulo', t.titulo, 'autor', t.autor, 'editora', t.editora, 'genero', t.genero, 'faixa', t.faixa, 'pnld', t.pnld, 'isbn', t.isbn,
        'exemplares', z.ex, 'disponiveis', z.disp, 'reservas', z.res, 'is_demo', t.is_demo) order by t.titulo), '[]')
    from iara.biblioteca_titulos t
    join lateral (select count(*) ex, count(*) filter (where x.estado in ('BOM', 'REGULAR') and not exists (select 1 from iara.biblioteca_emprestimos m where m.exemplar_id = x.id and m.devolvido_em is null)) disp,
                         (select count(*) from iara.biblioteca_reservas r where r.titulo_id = t.id and (v_unit is null or r.unit_id = v_unit) and r.situacao = 'ATIVA') res
                  from iara.biblioteca_exemplares x where x.titulo_id = t.id and (v_unit is null or x.unit_id = v_unit) and x.estado <> 'BAIXADO') z on true
    where (z.ex > 0 or (v_unit is null) or coalesce((p ->> 'todos')::boolean, false))
      and (v_q is null or iara.norm(t.titulo || ' ' || t.autor || ' ' || coalesce(t.isbn, '')) like '%' || v_q || '%')
      and (nullif(p ->> 'genero', '') is null or t.genero = p ->> 'genero')
      and (not coalesce((p ->> 'disponivel')::boolean, false) or z.disp > 0)
    limit 400);
end $$;

create or replace function api.biblioteca_titulo(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := coalesce(iara.bib_unidade(), nullif(p ->> 'unit_id', '')::int);
  t iara.biblioteca_titulos;
begin
  perform iara.require_perm('biblioteca.read');
  select * into t from iara.biblioteca_titulos where id = (p ->> 'id')::uuid;
  if t.id is null then raise exception 'Título não encontrado.' using errcode = 'P0002'; end if;
  return to_jsonb(t) || jsonb_build_object(
    'exemplares', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'tombo', x.tombo, 'estado', x.estado, 'origem', x.origem, 'localizacao', x.localizacao, 'unidade', u.short_name,
                     'emprestimo', (select iara.bib_emprestimo_json(m) from iara.biblioteca_emprestimos m where m.exemplar_id = x.id and m.devolvido_em is null)) order by u.short_name, x.tombo), '[]')
                   from iara.biblioteca_exemplares x join iara.education_units u on u.id = x.unit_id where x.titulo_id = t.id and (v_unit is null or x.unit_id = v_unit)),
    'reservas', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'aluno', s.full_name, 'situacao', r.situacao, 'criada_em', r.criada_em) order by r.criada_em), '[]')
                 from iara.biblioteca_reservas r join iara.students s on s.id = r.student_id where r.titulo_id = t.id and (v_unit is null or r.unit_id = v_unit) and r.situacao in ('ATIVA', 'DISPONIVEL')),
    'leituras', (select count(*) from iara.biblioteca_emprestimos m join iara.biblioteca_exemplares x on x.id = m.exemplar_id where x.titulo_id = t.id and (v_unit is null or m.unit_id = v_unit)));
end $$;

-- título novo (ou alteração) e exemplares da unidade; tombo gerado: <unidade>-<sequência>
create or replace function api.biblioteca_titulo_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_unit integer := iara.bib_unidade();
  t iara.biblioteca_titulos;
  v_n integer := least(greatest(coalesce((p ->> 'exemplares')::int, 0), 0), 50);
  v_seq integer;
  i integer;
begin
  perform iara.require_perm('biblioteca.acervo');
  if v_unit is null then raise exception 'O acervo é cadastrado pela unidade.' using errcode = '42501'; end if;
  if length(btrim(coalesce(p ->> 'titulo', ''))) < 2 or length(btrim(coalesce(p ->> 'autor', ''))) < 2 then raise exception 'Informe título e autor.' using errcode = '22023'; end if;
  if nullif(p ->> 'isbn', '') is not null and regexp_replace(p ->> 'isbn', '[^0-9Xx]', '', 'g') !~ '^([0-9]{9}[0-9Xx]|[0-9]{13})$' then
    raise exception 'ISBN inválido (10 ou 13 dígitos).' using errcode = '22023';
  end if;
  if nullif(p ->> 'id', '') is not null then
    update iara.biblioteca_titulos set titulo = btrim(p ->> 'titulo'), autor = btrim(p ->> 'autor'), editora = nullif(btrim(coalesce(p ->> 'editora', '')), ''),
           genero = coalesce(nullif(p ->> 'genero', ''), genero), faixa = coalesce(nullif(p ->> 'faixa', ''), faixa), isbn = nullif(regexp_replace(coalesce(p ->> 'isbn', ''), '[^0-9Xx]', '', 'g'), '')
    where id = (p ->> 'id')::uuid returning * into t;
  else
    select * into t from iara.biblioteca_titulos where nullif(p ->> 'isbn', '') is not null and isbn = regexp_replace(p ->> 'isbn', '[^0-9Xx]', '', 'g') limit 1;
    if t.id is null then
      insert into iara.biblioteca_titulos (isbn, titulo, autor, editora, ano_publicacao, genero, faixa, pnld)
      values (nullif(regexp_replace(coalesce(p ->> 'isbn', ''), '[^0-9Xx]', '', 'g'), ''), btrim(p ->> 'titulo'), btrim(p ->> 'autor'), nullif(btrim(coalesce(p ->> 'editora', '')), ''),
              nullif(p ->> 'ano_publicacao', '')::smallint, coalesce(nullif(p ->> 'genero', ''), 'LITERATURA_INFANTIL'), coalesce(nullif(p ->> 'faixa', ''), 'TODAS'),
              coalesce((p ->> 'pnld')::boolean, false))
      returning * into t;
    end if;
  end if;
  if t.id is null then raise exception 'Título não encontrado.' using errcode = 'P0002'; end if;
  select coalesce(max(nullif(regexp_replace(tombo, '^.*-', ''), '')::int), 0) into v_seq from iara.biblioteca_exemplares where unit_id = v_unit and tombo ~ '-[0-9]+$';
  for i in 1..v_n loop
    insert into iara.biblioteca_exemplares (titulo_id, unit_id, tombo, origem, localizacao, adquirido_em)
    values (t.id, v_unit, v_unit || '-' || lpad((v_seq + i)::text, 5, '0'), coalesce(nullif(p ->> 'origem', ''), 'PNLD'), nullif(btrim(coalesce(p ->> 'localizacao', '')), ''), iara.hoje_local());
  end loop;
  perform iara.audit_event('BIBLIOTECA', 'biblioteca_titulo', t.id::text, v_unit, format('Acervo: %s (%s exemplar(es) novo(s)).', t.titulo, v_n));
  return api.biblioteca_titulo(jsonb_build_object('id', t.id));
end $$;

-- estado do exemplar e baixa (com motivo)
create or replace function api.biblioteca_exemplar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  x iara.biblioteca_exemplares;
begin
  perform iara.require_perm('biblioteca.acervo');
  select * into x from iara.biblioteca_exemplares where id = (p ->> 'id')::uuid and unit_id = iara.bib_unidade() for update;
  if x.id is null then raise exception 'Exemplar não encontrado na sua unidade.' using errcode = 'P0002'; end if;
  if coalesce(p ->> 'estado', '') not in ('BOM', 'REGULAR', 'DANIFICADO', 'EXTRAVIADO', 'BAIXADO') then raise exception 'Estado inválido.' using errcode = '22023'; end if;
  if p ->> 'estado' = 'BAIXADO' and length(btrim(coalesce(p ->> 'motivo', ''))) < 5 then raise exception 'Informe o motivo da baixa.' using errcode = '22023'; end if;
  if exists (select 1 from iara.biblioteca_emprestimos where exemplar_id = x.id and devolvido_em is null) and p ->> 'estado' in ('BAIXADO') then
    raise exception 'O exemplar está emprestado: registre a devolução (ou o extravio) antes da baixa.' using errcode = '22023';
  end if;
  update iara.biblioteca_exemplares set estado = p ->> 'estado', baixa_motivo = case when p ->> 'estado' = 'BAIXADO' then btrim(p ->> 'motivo') end, alterado_em = now() where id = x.id;
  perform iara.audit_event('BIBLIOTECA', 'biblioteca_exemplar', x.tombo, x.unit_id, format('Exemplar %s: %s.', x.tombo, lower(p ->> 'estado')));
  return jsonb_build_object('ok', true);
end $$;

-- empréstimo: aluno da unidade (professor: aluno das suas turmas), servidor da unidade ou outro leitor
create or replace function api.biblioteca_emprestar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_unit integer := iara.bib_unidade();
  x iara.biblioteca_exemplares;
  v_student uuid := nullif(p ->> 'student_id', '')::uuid;
  v_staff uuid := nullif(p ->> 'staff_id', '')::uuid;
  v_nome text;
  v_prazo integer;
  r iara.biblioteca_reservas;
  m iara.biblioteca_emprestimos;
begin
  perform iara.require_perm('biblioteca.write');
  if v_unit is null then raise exception 'O empréstimo é feito na unidade.' using errcode = '42501'; end if;
  select * into x from iara.biblioteca_exemplares where unit_id = v_unit
    and (id = nullif(p ->> 'exemplar_id', '')::uuid or tombo = upper(btrim(coalesce(p ->> 'tombo', '')))) for update;
  if x.id is null then raise exception 'Exemplar não encontrado nesta unidade (confira o tombo).' using errcode = 'P0002'; end if;
  if x.estado not in ('BOM', 'REGULAR') then raise exception 'Exemplar %: não está disponível para empréstimo.', lower(x.estado) using errcode = '22023'; end if;
  if exists (select 1 from iara.biblioteca_emprestimos where exemplar_id = x.id and devolvido_em is null) then raise exception 'Este exemplar já está emprestado.' using errcode = '22023'; end if;
  if v_student is not null then
    if not exists (select 1 from iara.enrollments e where e.student_id = v_student and e.unit_id = v_unit and e.status = 'ACTIVE'
                   and (iara.my_role() not in ('PROFESSOR') or e.class_id = any (iara.minhas_turmas()))) then
      raise exception 'Aluno fora da sua unidade ou das suas turmas.' using errcode = '42501';
    end if;
    if exists (select 1 from iara.biblioteca_emprestimos where student_id = v_student and devolvido_em is null and prevista < iara.hoje_local()) then
      raise exception 'Há livro em atraso com este aluno: registre a devolução antes de um novo empréstimo.' using errcode = '22023';
    end if;
    if (select count(*) from iara.biblioteca_emprestimos where student_id = v_student and devolvido_em is null) >= iara.bib_limite(v_student) then
      raise exception 'Limite de % livro(s) ao mesmo tempo para este aluno.', iara.bib_limite(v_student) using errcode = '22023';
    end if;
    select full_name into v_nome from iara.students where id = v_student;
  elsif v_staff is not null then
    select full_name into v_nome from iara.staff where id = v_staff and unit_id = v_unit;
    if v_nome is null then raise exception 'Servidor não encontrado na unidade.' using errcode = 'P0002'; end if;
  else
    v_nome := nullif(btrim(coalesce(p ->> 'leitor_nome', '')), '');
    if v_nome is null then raise exception 'Escolha o aluno, o servidor ou escreva o nome do leitor.' using errcode = '22023'; end if;
  end if;
  -- reserva: quem está na frente da fila do título leva primeiro
  select * into r from iara.biblioteca_reservas where titulo_id = x.titulo_id and unit_id = v_unit and situacao in ('ATIVA', 'DISPONIVEL') order by criada_em limit 1;
  if r.id is not null and r.student_id is distinct from v_student then
    raise exception 'Este título está reservado para outro aluno (primeiro da fila).' using errcode = '22023';
  end if;
  v_prazo := coalesce(nullif(p ->> 'dias', '')::int, iara.bib_prazo_dias(v_student));
  insert into iara.biblioteca_emprestimos (exemplar_id, unit_id, student_id, staff_id, leitor_nome, prevista, registrado_por_label)
  values (x.id, v_unit, v_student, v_staff, v_nome, iara.bib_dia_util(iara.hoje_local() + least(v_prazo, 30)), iara.my_label())
  returning * into m;
  if r.id is not null then update iara.biblioteca_reservas set situacao = 'ATENDIDA', encerrada_em = now() where id = r.id; end if;
  perform iara.audit_event('BIBLIOTECA', 'biblioteca_emprestimo', m.id::text, v_unit, format('Empréstimo do exemplar %s.', x.tombo));
  return iara.bib_emprestimo_json(m);
end $$;

-- devolução (por empréstimo ou tombo); se houver reserva, avisa a família do primeiro da fila
create or replace function api.biblioteca_devolver(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_unit integer := iara.bib_unidade();
  m iara.biblioteca_emprestimos;
  x iara.biblioteca_exemplares;
  r record;
  v_estado text := coalesce(nullif(p ->> 'estado', ''), 'BOM');
begin
  perform iara.require_perm('biblioteca.write');
  select em.* into m from iara.biblioteca_emprestimos em join iara.biblioteca_exemplares ex on ex.id = em.exemplar_id
  where em.unit_id = v_unit and em.devolvido_em is null
    and (em.id = nullif(p ->> 'emprestimo_id', '')::uuid or ex.tombo = upper(btrim(coalesce(p ->> 'tombo', '')))) for update of em;
  if m.id is null then raise exception 'Empréstimo em aberto não encontrado (confira o tombo).' using errcode = 'P0002'; end if;
  if v_estado not in ('BOM', 'REGULAR', 'DANIFICADO', 'EXTRAVIADO') then raise exception 'Estado inválido.' using errcode = '22023'; end if;
  update iara.biblioteca_emprestimos set devolvido_em = now(), estado_devolucao = v_estado, devolvido_por_label = iara.my_label() where id = m.id;
  update iara.biblioteca_exemplares set estado = case when v_estado in ('DANIFICADO', 'EXTRAVIADO') then v_estado else estado end, alterado_em = now()
  where id = m.exemplar_id returning * into x;
  if v_estado in ('BOM', 'REGULAR') then
    select br.*, t.titulo, s.full_name into r from iara.biblioteca_reservas br join iara.biblioteca_titulos t on t.id = br.titulo_id join iara.students s on s.id = br.student_id
    where br.titulo_id = x.titulo_id and br.unit_id = v_unit and br.situacao = 'ATIVA' order by br.criada_em limit 1;
    if r.id is not null then
      update iara.biblioteca_reservas set situacao = 'DISPONIVEL', avisada_em = now() where id = r.id;
      insert into iara.notifications (tenant_id, guardian_id, student_id, channel, event_type, title, body, status)
      select 1, sg.guardian_id, r.student_id, 'PORTAL', 'BIBLIOTECA', 'Livro reservado disponível',
             format('O livro “%s”, reservado para %s, chegou na biblioteca da escola. Ele fica separado por 5 dias letivos.', r.titulo, split_part(r.full_name, ' ', 1)), 'ENVIADA'
      from iara.student_guardians sg where sg.student_id = r.student_id and sg.end_date is null and coalesce(sg.can_receive_notifications, true);
    end if;
  end if;
  perform iara.audit_event('BIBLIOTECA', 'biblioteca_emprestimo', m.id::text, v_unit, format('Devolução do exemplar %s (%s).', x.tombo, lower(v_estado)));
  return jsonb_build_object('ok', true, 'reserva_avisada', r.id is not null, 'emprestimo', iara.bib_emprestimo_json((select e2 from iara.biblioteca_emprestimos e2 where e2.id = m.id)));
end $$;

-- renovação: escola ou família (do próprio filho); até 2 vezes, sem reserva de outro leitor e sem atraso longo
create or replace function api.biblioteca_renovar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  m iara.biblioteca_emprestimos;
  v_fam boolean := iara.my_guardian() is not null;
  j jsonb;
begin
  select * into m from iara.biblioteca_emprestimos where id = (p ->> 'id')::uuid and devolvido_em is null for update;
  if m.id is null then raise exception 'Empréstimo em aberto não encontrado.' using errcode = 'P0002'; end if;
  if not ((v_fam and m.student_id in (select iara.my_student_ids())) or (not v_fam and iara.has_perm('biblioteca.write') and m.unit_id = iara.bib_unidade())) then
    raise exception 'Empréstimo fora do seu acesso.' using errcode = '42501';
  end if;
  j := iara.bib_emprestimo_json(m);
  if not (j ->> 'pode_renovar')::boolean then
    raise exception '%', case when m.renovacoes >= 2 then 'Este livro já foi renovado 2 vezes: devolva na escola.'
                              when m.prevista < iara.hoje_local() - 15 then 'O livro está muito atrasado: devolva na escola.'
                              else 'Outro leitor reservou este livro: devolva na escola até ' || to_char(m.prevista, 'DD/MM') || '.' end using errcode = '22023';
  end if;
  update iara.biblioteca_emprestimos set prevista = iara.bib_dia_util(greatest(prevista, iara.hoje_local()) + iara.bib_prazo_dias(student_id)), renovacoes = renovacoes + 1, alterado_em = now()
  where id = m.id returning * into m;
  perform iara.audit_event('BIBLIOTECA', 'biblioteca_emprestimo', m.id::text, m.unit_id, format('Renovação (%s) pela %s.', m.renovacoes, case when v_fam then 'família' else 'escola' end));
  return iara.bib_emprestimo_json(m);
end $$;

create or replace function api.biblioteca_reservar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_fam boolean := iara.my_guardian() is not null;
  v_unit integer;
  r iara.biblioteca_reservas;
begin
  if coalesce((p ->> 'cancelar')::boolean, false) then
    select * into r from iara.biblioteca_reservas where id = (p ->> 'id')::uuid and situacao in ('ATIVA', 'DISPONIVEL');
    if r.id is null or not ((v_fam and r.student_id in (select iara.my_student_ids())) or (not v_fam and iara.has_perm('biblioteca.write') and r.unit_id = iara.bib_unidade())) then
      raise exception 'Reserva não encontrada.' using errcode = 'P0002';
    end if;
    update iara.biblioteca_reservas set situacao = 'CANCELADA', encerrada_em = now() where id = r.id;
    return jsonb_build_object('ok', true);
  end if;
  if not ((v_fam and v_student in (select iara.my_student_ids())) or (not v_fam and iara.has_perm('biblioteca.write'))) then
    raise exception 'Aluno fora do seu acesso.' using errcode = '42501';
  end if;
  select unit_id into v_unit from iara.enrollments where student_id = v_student and status = 'ACTIVE' limit 1;
  if v_unit is null or (not v_fam and v_unit is distinct from iara.bib_unidade()) then raise exception 'Aluno sem matrícula nesta unidade.' using errcode = '22023'; end if;
  if not exists (select 1 from iara.biblioteca_exemplares where titulo_id = (p ->> 'titulo_id')::uuid and unit_id = v_unit and estado in ('BOM', 'REGULAR')) then
    raise exception 'A biblioteca da escola não tem este título.' using errcode = '22023';
  end if;
  if exists (select 1 from iara.biblioteca_emprestimos m join iara.biblioteca_exemplares x on x.id = m.exemplar_id where m.student_id = v_student and m.devolvido_em is null and x.titulo_id = (p ->> 'titulo_id')::uuid) then
    raise exception 'Este livro já está com a criança.' using errcode = '22023';
  end if;
  if (select count(*) from iara.biblioteca_reservas where student_id = v_student and situacao in ('ATIVA', 'DISPONIVEL')) >= 2 then
    raise exception 'Até 2 reservas por criança.' using errcode = '22023';
  end if;
  insert into iara.biblioteca_reservas (titulo_id, unit_id, student_id, canal) values ((p ->> 'titulo_id')::uuid, v_unit, v_student, coalesce(nullif(p ->> 'canal', ''), case when v_fam then 'PORTAL' else 'UNIDADE' end))
  returning * into r;
  return to_jsonb(r) || jsonb_build_object('posicao', (select count(*) from iara.biblioteca_reservas x where x.titulo_id = r.titulo_id and x.unit_id = v_unit and x.situacao in ('ATIVA', 'DISPONIVEL') and x.criada_em <= r.criada_em));
exception when unique_violation then
  raise exception 'Já há uma reserva deste livro para a criança.' using errcode = '22023';
end $$;

-- família: o que cada filho levou, até quando devolve, o que leu no ano e as reservas
create or replace function api.familia_biblioteca(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('student_id', s.id, 'primeiro_nome', split_part(s.full_name, ' ', 1),
      'unidade', (select u.short_name from iara.enrollments e join iara.education_units u on u.id = e.unit_id where e.student_id = s.id and e.status = 'ACTIVE' limit 1),
      'prazo_dias', iara.bib_prazo_dias(s.id),
      'ativos', (select coalesce(jsonb_agg(iara.bib_emprestimo_json(m, true) order by m.prevista), '[]') from iara.biblioteca_emprestimos m where m.student_id = s.id and m.devolvido_em is null),
      'lidos', (select coalesce(jsonb_agg(jsonb_build_object('titulo', t.titulo, 'autor', t.autor, 'retirada_em', m.retirada_em) order by m.retirada_em desc), '[]')
                from iara.biblioteca_emprestimos m join iara.biblioteca_exemplares x on x.id = m.exemplar_id join iara.biblioteca_titulos t on t.id = x.titulo_id
                where m.student_id = s.id and m.devolvido_em is not null and m.retirada_em >= make_date(extract(year from iara.hoje_local())::int, 1, 1)),
      'reservas', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'titulo', t.titulo, 'situacao', r.situacao, 'criada_em', r.criada_em) order by r.criada_em), '[]')
                   from iara.biblioteca_reservas r join iara.biblioteca_titulos t on t.id = r.titulo_id where r.student_id = s.id and r.situacao in ('ATIVA', 'DISPONIVEL')))
      order by s.full_name), '[]')
    from iara.students s where s.id in (select iara.my_student_ids())
      and exists (select 1 from iara.enrollments e where e.student_id = s.id and e.status = 'ACTIVE'));
end $$;

-- 2. Demonstração ------------------------------------------------------------------------------------------------------------------
create or replace function iara.demo_gerar_biblioteca() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ana uuid := nullif(iara.setting('demo_student_ana'), '')::uuid;
  v_ex uuid;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.biblioteca_reservas where is_demo;
  delete from iara.biblioteca_emprestimos where is_demo;
  delete from iara.biblioteca_exemplares where is_demo;
  delete from iara.biblioteca_titulos where is_demo;
  -- títulos (obras e autores reais da literatura infantil; editora e ISBN omitidos na demonstração)
  insert into iara.biblioteca_titulos (titulo, autor, genero, faixa, pnld, is_demo)
  select t, a, g, f, abs(hashtext(t)) % 3 = 0, true from (values
    ('O Menino Maluquinho', 'Ziraldo', 'LITERATURA_INFANTIL', 'EF_INICIAIS'), ('Flicts', 'Ziraldo', 'LITERATURA_INFANTIL', 'TODAS'),
    ('Marcelo, Marmelo, Martelo', 'Ruth Rocha', 'CONTOS_FABULAS', 'EF_INICIAIS'), ('O Reizinho Mandão', 'Ruth Rocha', 'LITERATURA_INFANTIL', 'EF_INICIAIS'),
    ('Chapeuzinho Amarelo', 'Chico Buarque', 'POESIA', 'TODAS'), ('A Bolsa Amarela', 'Lygia Bojunga', 'INFANTOJUVENIL', 'EF_INICIAIS'),
    ('Reinações de Narizinho', 'Monteiro Lobato', 'INFANTOJUVENIL', 'EF_INICIAIS'), ('A Arca de Noé', 'Vinicius de Moraes', 'POESIA', 'TODAS'),
    ('Ou Isto ou Aquilo', 'Cecília Meireles', 'POESIA', 'EF_INICIAIS'), ('Bisa Bia, Bisa Bel', 'Ana Maria Machado', 'INFANTOJUVENIL', 'EF_INICIAIS'),
    ('Menina Bonita do Laço de Fita', 'Ana Maria Machado', 'LITERATURA_INFANTIL', 'TODAS'), ('O Pequeno Príncipe', 'Antoine de Saint-Exupéry', 'INFANTOJUVENIL', 'EF_INICIAIS'),
    ('A Casa Sonolenta', 'Audrey Wood', 'LITERATURA_INFANTIL', 'EI'), ('Bruxa, Bruxa, Venha à Minha Festa', 'Arden Druce', 'LITERATURA_INFANTIL', 'EI'),
    ('O Grande Rabanete', 'Tatiana Belinky', 'CONTOS_FABULAS', 'EI'), ('A Galinha Ruiva', 'Conto popular', 'CONTOS_FABULAS', 'EI'),
    ('Os Três Porquinhos', 'Conto popular', 'CONTOS_FABULAS', 'EI'), ('João e o Pé de Feijão', 'Conto popular', 'CONTOS_FABULAS', 'EI'),
    ('Fábulas de Esopo', 'Esopo', 'CONTOS_FABULAS', 'EF_INICIAIS'), ('Turma da Mônica — Almanaque', 'Mauricio de Sousa', 'HISTORIA_EM_QUADRINHOS', 'TODAS'),
    ('Chico Bento — Histórias da Roça', 'Mauricio de Sousa', 'HISTORIA_EM_QUADRINHOS', 'EF_INICIAIS'), ('Até as Princesas Soltam Pum', 'Ilan Brenman', 'LITERATURA_INFANTIL', 'TODAS'),
    ('O Livro dos Porquês', 'Ilan Brenman', 'INFORMATIVO', 'EF_INICIAIS'), ('Lúcia Já-Vou-Indo', 'Maria Heloísa Penteado', 'LITERATURA_INFANTIL', 'EI'),
    ('Pedro e Tina', 'Stephen Michael King', 'LITERATURA_INFANTIL', 'EI'), ('Tanto, Tanto!', 'Trish Cooke', 'LITERATURA_INFANTIL', 'EI'),
    ('O Sanduíche da Maricota', 'Avelino Guedes', 'LITERATURA_INFANTIL', 'EI'), ('Bom Dia, Todas as Cores!', 'Ruth Rocha', 'LITERATURA_INFANTIL', 'EI'),
    ('A Fada Que Tinha Ideias', 'Fernanda Lopes de Almeida', 'INFANTOJUVENIL', 'EF_INICIAIS'), ('O Caso da Borboleta Atíria', 'Lúcia Machado de Almeida', 'INFANTOJUVENIL', 'EF_INICIAIS'),
    ('Raul da Ferrugem Azul', 'Ana Maria Machado', 'INFANTOJUVENIL', 'EF_INICIAIS'), ('Viagem ao Centro da Terra (adaptação)', 'Júlio Verne', 'INFANTOJUVENIL', 'EF_INICIAIS'),
    ('Atlas Geográfico Escolar', 'IBGE', 'REFERENCIA', 'EF_INICIAIS'), ('Dicionário Ilustrado de Português', 'Equipe editorial', 'REFERENCIA', 'EF_INICIAIS'),
    ('Os Bichos da Mata Atlântica', 'Equipe editorial', 'INFORMATIVO', 'TODAS'), ('Corpo Humano para Crianças', 'Equipe editorial', 'INFORMATIVO', 'EF_INICIAIS'),
    ('Contos de Andersen', 'Hans Christian Andersen', 'CONTOS_FABULAS', 'EF_INICIAIS'), ('Contos de Grimm', 'Irmãos Grimm', 'CONTOS_FABULAS', 'EF_INICIAIS'),
    ('O Saci', 'Monteiro Lobato', 'INFANTOJUVENIL', 'EF_INICIAIS'), ('Lendas Brasileiras', 'Câmara Cascudo', 'CONTOS_FABULAS', 'EF_INICIAIS')
  ) v(t, a, g, f);
  -- exemplares: cada unidade recebe parte do acervo conforme a etapa (educação infantil nos CMEIs)
  insert into iara.biblioteca_exemplares (titulo_id, unit_id, tombo, estado, origem, localizacao, adquirido_em, is_demo)
  select t.id, u.id, u.id || '-' || lpad((row_number() over (partition by u.id order by t.titulo, k))::text, 5, '0'),
         case when abs(hashtext(t.id::text || u.id || k)) % 100 < 85 then 'BOM' when abs(hashtext(t.id::text || u.id || k)) % 100 < 96 then 'REGULAR' else 'DANIFICADO' end,
         (array['PNLD', 'PNLD', 'DOACAO', 'COMPRA'])[1 + abs(hashtext(t.id::text || u.id)) % 4], 'Estante ' || chr(65 + abs(hashtext(t.id::text)) % 6),
         date '2022-03-01' + abs(hashtext(t.id::text || u.id || k)) % 1300, true
  from iara.education_units u cross join iara.biblioteca_titulos t cross join generate_series(1, 3) k
  where u.status = 'ATIVA' and t.is_demo
    and ((u.unit_type = 'CMEI' and t.faixa in ('EI', 'TODAS')) or (u.unit_type <> 'CMEI' and t.faixa in ('EF_INICIAIS', 'TODAS', 'EI')))
    and abs(hashtext(t.id::text || u.id)) % 100 < 70 and k <= 1 + abs(hashtext(t.id::text || u.id || 'n')) % 3;
  -- empréstimos do ano: metade dos alunos lê; sacola literária semanal na educação infantil
  insert into iara.biblioteca_emprestimos (exemplar_id, unit_id, student_id, leitor_nome, retirada_em, prevista, devolvido_em, renovacoes, estado_devolucao,
                                           registrado_por_label, devolvido_por_label, is_demo)
  select ex.id, z.unit_id, z.student_id, z.full_name, z.ret, iara.bib_dia_util((z.ret at time zone 'America/Sao_Paulo')::date + z.prazo),
         -- todos entram devolvidos; os candidatos a “em aberto” ficam sem estado de devolução e são reabertos abaixo (1 por exemplar e por aluno)
         least(z.ret + make_interval(days => 3 + abs(hashtext(z.student_id::text || z.i)) % z.prazo), now() - interval '1 hour'),
         case when abs(hashtext(z.student_id::text || z.i || 'r')) % 100 < 10 then 1 else 0 end,
         case when z.ret < now() - make_interval(days => z.prazo + 3) or abs(hashtext(z.student_id::text || z.i)) % 100 < 40 then 'BOM' end,
         'Biblioteca da escola (demonstração)', 'Biblioteca da escola (demonstração)', true
  from (select e.student_id, e.unit_id, s.full_name, i, case when gl.code in ('CRECHE', 'PRE') then 7 else 14 end prazo,
               (date '2026-02-23' + (i - 1) * 21 + abs(hashtext(e.student_id::text || i)) % 14 + time '10:00') at time zone 'America/Sao_Paulo' ret
        from iara.enrollments e join iara.students s on s.id = e.student_id join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
        cross join generate_series(1, 11) i
        where e.status = 'ACTIVE' and abs(hashtext(e.student_id::text || 'leitor')) % 100 < 50 and abs(hashtext(e.student_id::text || i || 'mes')) % 100 < 55
          and e.student_id is distinct from v_ana) z
  join lateral (select x.id from iara.biblioteca_exemplares x where x.unit_id = z.unit_id and x.is_demo order by abs(hashtext(x.id::text || z.student_id::text || z.i)) limit 1) ex on true
  where z.ret < now() - interval '2 hours';
  -- em aberto: o candidato mais recente de cada exemplar e de cada aluno; os demais ficam devolvidos
  update iara.biblioteca_emprestimos m set devolvido_em = null, devolvido_por_label = null
  from (select id, row_number() over (partition by exemplar_id order by retirada_em desc) rx, row_number() over (partition by student_id order by retirada_em desc) rs
        from iara.biblioteca_emprestimos where is_demo and estado_devolucao is null) q
  where m.id = q.id and q.rx = 1 and q.rs = 1;
  update iara.biblioteca_emprestimos set estado_devolucao = 'BOM' where is_demo and estado_devolucao is null and devolvido_em is not null;
  -- a Ana (apresentação): sacola literária desta semana
  select x.id into v_ex from iara.biblioteca_exemplares x join iara.biblioteca_titulos t on t.id = x.titulo_id
  where x.unit_id = (select unit_id from iara.enrollments where student_id = v_ana and status = 'ACTIVE' limit 1) and t.titulo = 'Chapeuzinho Amarelo'
    and not exists (select 1 from iara.biblioteca_emprestimos m where m.exemplar_id = x.id and m.devolvido_em is null) limit 1;
  if v_ex is null then
    select x.id into v_ex from iara.biblioteca_exemplares x where x.unit_id = (select unit_id from iara.enrollments where student_id = v_ana and status = 'ACTIVE' limit 1)
      and not exists (select 1 from iara.biblioteca_emprestimos m where m.exemplar_id = x.id and m.devolvido_em is null) limit 1;
  end if;
  if v_ex is not null then
    insert into iara.biblioteca_emprestimos (exemplar_id, unit_id, student_id, leitor_nome, retirada_em, prevista, registrado_por_label, is_demo)
    select v_ex, e.unit_id, v_ana, s.full_name, now() - interval '3 days', iara.bib_dia_util(iara.hoje_local() + 4), 'Professora da turma (demonstração)', true
    from iara.enrollments e join iara.students s on s.id = e.student_id where e.student_id = v_ana and e.status = 'ACTIVE';
  end if;
  -- reservas abertas
  insert into iara.biblioteca_reservas (titulo_id, unit_id, student_id, canal, criada_em, is_demo)
  select x.titulo_id, m.unit_id, z.student_id, 'UNIDADE', now() - interval '2 days', true
  from iara.biblioteca_emprestimos m join iara.biblioteca_exemplares x on x.id = m.exemplar_id
  join lateral (select e.student_id from iara.enrollments e where e.unit_id = m.unit_id and e.status = 'ACTIVE' and e.student_id <> coalesce(m.student_id, e.student_id)
                order by abs(hashtext(e.student_id::text || m.id::text)) limit 1) z on true
  where m.is_demo and m.devolvido_em is null and abs(hashtext(m.id::text || 'res')) % 100 < 6
  on conflict do nothing;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('titulos', (select count(*) from iara.biblioteca_titulos where is_demo), 'exemplares', (select count(*) from iara.biblioteca_exemplares where is_demo),
    'emprestimos', (select count(*) from iara.biblioteca_emprestimos where is_demo), 'ativos', (select count(*) from iara.biblioteca_emprestimos where is_demo and devolvido_em is null),
    'atrasados', (select count(*) from iara.biblioteca_emprestimos where is_demo and devolvido_em is null and prevista < iara.hoje_local()),
    'reservas', (select count(*) from iara.biblioteca_reservas where is_demo));
end $$;

create or replace function iara.demo_purge_biblioteca(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  d timestamptz := coalesce(p_desde, '-infinity'::timestamptz);
  n integer;
  v jsonb := '{}'::jsonb;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.biblioteca_reservas where not is_demo and criada_em >= d;
  delete from iara.biblioteca_emprestimos where not is_demo and retirada_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('emprestimos', n);
  delete from iara.biblioteca_exemplares x where not x.is_demo and x.criado_em >= d and not exists (select 1 from iara.biblioteca_emprestimos m where m.exemplar_id = x.id);
  delete from iara.biblioteca_titulos t where not t.is_demo and t.criado_em >= d and not exists (select 1 from iara.biblioteca_exemplares x where x.titulo_id = t.id);
  delete from iara.notifications where created_at >= d and event_type = 'BIBLIOTECA';
  -- demonstração mexida ao vivo (devolução, renovação, reserva atendida, estado do exemplar) volta ao original
  if exists (select 1 from iara.biblioteca_emprestimos where is_demo and ((devolvido_em >= d and devolvido_por_label not like '%(demonstração)%') or alterado_em >= d))
     or exists (select 1 from iara.biblioteca_exemplares where is_demo and alterado_em >= d)
     or exists (select 1 from iara.biblioteca_reservas where is_demo and encerrada_em >= d) then
    v := v || jsonb_build_object('refeita', iara.demo_gerar_biblioteca());
  end if;
  perform set_config('iara.skip_audit', 'off', true);
  return v;
end $$;

revoke all on function iara.demo_gerar_biblioteca(), iara.demo_purge_biblioteca(timestamptz) from public;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('biblioteca_emprestimos', 'leitor_nome', 'PESSOAL', 'identificação', 'empréstimo', 'unidade; família só do próprio filho'),
  ('biblioteca_emprestimos', 'registrado_por_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('biblioteca_emprestimos', 'devolvido_por_label', 'PESSOAL', 'identificação', 'auditoria', null)
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

select iara.demo_gerar_biblioteca() where iara.demo_mode();

commit;
