-- IARA Educa — 043 · Funcionários e professores (Sprint 1, módulo 1; item 34 da seção 12 do documento de estrutura)
-- Cadastro funcional, lotações, formações, matriz curricular, horário das turmas, carga horária e mediadores.
-- Regra real usada como parâmetro: Lei 11.738/2008 (piso) — no máximo 2/3 da jornada em interação com os alunos
-- (20 h → 16 aulas de 50 min em sala; 40 h → 32). Demais números (matriz, horários, cursos) são de demonstração.
begin;

-- 1. Cadastro funcional ------------------------------------------------------------------------------------------------
alter table iara.staff add column if not exists matricula_funcional text;
alter table iara.staff add column if not exists cargo text;
alter table iara.staff add column if not exists carga_horaria_semanal smallint;
alter table iara.staff add column if not exists data_admissao date;
alter table iara.staff add column if not exists escolaridade text;
alter table iara.staff add column if not exists formacao text;
alter table iara.staff add column if not exists area_atuacao text;
alter table iara.staff add column if not exists situacao text not null default 'ATIVO';
alter table iara.staff drop constraint if exists staff_situacao_check;
alter table iara.staff add constraint staff_situacao_check check (situacao in ('ATIVO', 'LICENCA', 'AFASTADO', 'DESLIGADO'));
create unique index if not exists staff_matricula_idx on iara.staff (matricula_funcional) where matricula_funcional is not null;

create table if not exists iara.staff_lotacoes (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references iara.staff(id) on delete cascade,
  unit_id integer references iara.education_units(id),
  funcao text not null,
  inicio date not null,
  fim date,
  motivo text,
  is_demo boolean not null default true
);
create index if not exists staff_lotacoes_staff_idx on iara.staff_lotacoes (staff_id);

create table if not exists iara.staff_formacoes (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references iara.staff(id) on delete cascade,
  titulo text not null,
  tipo text not null check (tipo in ('FORMACAO_CONTINUADA', 'CURSO', 'POS_GRADUACAO', 'EVENTO')),
  instituicao text,
  carga_horaria smallint,
  concluido_em date,
  is_demo boolean not null default true
);
create index if not exists staff_formacoes_staff_idx on iara.staff_formacoes (staff_id);

-- 2. Matriz curricular (aulas por semana por componente) e horário das turmas ----------------------------------------------
create table if not exists iara.matriz_curricular (
  grade_code text not null,
  componente text not null,
  aulas_semana smallint not null,
  quem text not null check (quem in ('REGENTE', 'ESPECIALISTA')),
  ordem smallint not null,
  primary key (grade_code, componente)
);
delete from iara.matriz_curricular;
insert into iara.matriz_curricular (grade_code, componente, aulas_semana, quem, ordem)
select g, c, a, q, o from (values ('EF1'), ('EF2'), ('EF3'), ('EF4'), ('EF5'), ('EJA_AI')) gs(g)
cross join (values
  ('Língua Portuguesa', 6, 'REGENTE', 1), ('Matemática', 5, 'REGENTE', 2), ('Ciências', 2, 'REGENTE', 3), ('História', 1, 'REGENTE', 4),
  ('Geografia', 1, 'REGENTE', 5), ('Ensino Religioso', 1, 'REGENTE', 6), ('Educação Física', 3, 'ESPECIALISTA', 7), ('Arte', 2, 'ESPECIALISTA', 8),
  ('Inglês', 2, 'ESPECIALISTA', 9), ('Leitura e projetos', 2, 'ESPECIALISTA', 10)) m(c, a, q, o)
union all
select 'PRE', c, a, q, o from (values ('Campos de experiência', 16, 'REGENTE', 1), ('Educação Física', 3, 'ESPECIALISTA', 2),
  ('Arte', 2, 'ESPECIALISTA', 3), ('Música', 2, 'ESPECIALISTA', 4), ('Leitura e projetos', 2, 'ESPECIALISTA', 5)) p(c, a, q, o)
union all
select 'CRECHE', 'Rotina e experiências', 25, 'REGENTE', 1;

create table if not exists iara.horarios_turma (
  class_id uuid not null references iara.classes(id) on delete cascade,
  dia_semana smallint not null check (dia_semana between 1 and 5),
  aula smallint not null check (aula between 1 and 5),
  componente text not null,
  staff_id uuid references iara.staff(id) on delete set null,
  is_demo boolean not null default true,
  primary key (class_id, dia_semana, aula)
);
create index if not exists horarios_staff_idx on iara.horarios_turma (staff_id, dia_semana, aula);

-- horário de cada aula pelo turno (integral usa a grade da manhã; a tarde integral é rotina da unidade)
create or replace function iara.aula_horario(p_shift text, p_aula integer) returns text
language sql immutable as $$
  select case when p_shift = 'TARDE' then (array['13:00–13:50', '13:50–14:40', '14:40–15:30', '15:50–16:40', '16:40–17:30'])[p_aula]
              when p_shift = 'NOITE' then (array['19:00–19:45', '19:45–20:30', '20:30–21:15', '21:25–22:10', '22:10–22:55'])[p_aula]
              else (array['07:30–08:20', '08:20–09:10', '09:10–10:00', '10:20–11:10', '11:10–12:00'])[p_aula] end
$$;
create or replace function iara.turno_base(p_shift text) returns text
language sql immutable as $$ select case when p_shift = 'INTEGRAL' then 'MANHA' else p_shift end $$;

-- capacidade em sala (Lei 11.738/2008: até 2/3 da jornada com alunos; aula de 50 min)
create or replace function iara.aulas_capacidade(p_ch integer) returns integer
language sql immutable as $$ select (coalesce(p_ch, 0) * 4 / 5)::int $$;  -- = h × 2/3 × 60/50, em conta inteira (20 h → 16; 40 h → 32)

-- 3. Mediadores (profissional de apoio vinculado ao aluno com necessidade) --------------------------------------------------
create table if not exists iara.mediacoes (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references iara.staff(id) on delete cascade,
  student_id uuid not null references iara.students(id) on delete cascade,
  class_id uuid references iara.classes(id) on delete set null,
  inicio date not null default current_date,
  fim date,
  is_demo boolean not null default true
);
create index if not exists mediacoes_student_idx on iara.mediacoes (student_id);

alter table iara.staff_lotacoes enable row level security;
alter table iara.staff_formacoes enable row level security;
alter table iara.matriz_curricular enable row level security;
alter table iara.horarios_turma enable row level security;
alter table iara.mediacoes enable row level security;

-- 4. Gerador da demonstração (dados de exemplo; saem com iara.demo_limpar_modulo('PESSOAL')) --------------------------------
create or replace function iara.demo_gerar_pessoal() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  u record;
  sl record;
  v_staff uuid;
  v_n_slots integer := 0;
  v_sem integer := 0;
  v_area text;
begin
  perform set_config('iara.skip_audit', 'on', true);
  -- cadastro funcional dos servidores de demonstração
  with x as (select id, row_number() over (order by unit_id, full_name, id) rn, ('x' || substr(md5(id::text), 1, 8))::bit(32)::int h
             from iara.staff where is_demo)
  update iara.staff s set
    matricula_funcional = (180000 + x.rn)::text,
    cargo = case s.role when 'PROFESSOR' then 'Professor(a) de Educação Básica' when 'EDUCADOR' then 'Educador(a) Infantil'
                        when 'AUXILIAR' then 'Auxiliar de Apoio Escolar' when 'AEE' then 'Professor(a) de AEE' else initcap(lower(s.role)) end,
    carga_horaria_semanal = case when s.role in ('EDUCADOR', 'AUXILIAR') then 40 when s.role = 'AEE' then 20
                                 when abs(x.h) % 10 < 7 then 20 else 40 end,
    data_admissao = make_date(1998 + abs(x.h) % 28, 1 + abs(x.h / 7) % 12, 1 + abs(x.h / 13) % 27),
    escolaridade = case when s.role = 'AUXILIAR' then (array['Ensino médio', 'Ensino médio', 'Superior incompleto'])[1 + abs(x.h) % 3]
                        when s.role = 'EDUCADOR' then (array['Superior completo', 'Superior completo', 'Especialização', 'Magistério (nível médio)'])[1 + abs(x.h) % 4]
                        else (array['Especialização', 'Especialização', 'Superior completo', 'Especialização', 'Mestrado'])[1 + abs(x.h) % 5] end,
    formacao = case when s.role = 'AUXILIAR' then null when s.role = 'AEE' then 'Pedagogia · especialização em Educação Especial'
                    when s.role = 'EDUCADOR' then (array['Pedagogia', 'Pedagogia', 'Normal Superior'])[1 + abs(x.h) % 3]
                    else 'Pedagogia' end,
    area_atuacao = case s.role when 'EDUCADOR' then 'Educação Infantil' when 'AEE' then 'Atendimento educacional especializado'
                               when 'AUXILIAR' then 'Apoio escolar' else 'Anos iniciais' end,
    situacao = case when abs(x.h) % 50 = 0 then 'LICENCA' when abs(x.h) % 50 = 1 then 'AFASTADO' else 'ATIVO' end
  from x where s.id = x.id;
  -- regente de creche fica o dia todo com a turma: jornada de 40 h
  update iara.staff s set carga_horaria_semanal = 40
  where s.is_demo and exists (select 1 from iara.class_staff cs join iara.classes c on c.id = cs.class_id
                              join iara.grade_levels gl on gl.id = c.grade_level_id
                              where cs.staff_id = s.id and cs.role_type = 'REGENTE' and gl.code = 'CRECHE');

  -- lotação atual e, para parte deles, uma lotação anterior em outra unidade
  delete from iara.staff_lotacoes where is_demo;
  insert into iara.staff_lotacoes (staff_id, unit_id, funcao, inicio, motivo, is_demo)
  select s.id, s.unit_id, s.cargo, greatest(s.data_admissao, case when abs(('x' || substr(md5(s.id::text || 'l'), 1, 8))::bit(32)::int) % 10 < 3
                                                            then make_date(2020 + abs(('x' || substr(md5(s.id::text), 9, 8))::bit(32)::int) % 6, 2, 1) else s.data_admissao end),
         'Lotação atual', true
  from iara.staff s where s.is_demo;
  insert into iara.staff_lotacoes (staff_id, unit_id, funcao, inicio, fim, motivo, is_demo)
  select l.staff_id, (select u2.id from iara.education_units u2 where u2.id <> l.unit_id order by md5(u2.id::text || l.staff_id::text) limit 1),
         s.cargo, s.data_admissao, l.inicio - 1, 'Remoção a pedido', true
  from iara.staff_lotacoes l join iara.staff s on s.id = l.staff_id
  where l.is_demo and l.inicio > s.data_admissao;

  -- formações continuadas e cursos
  delete from iara.staff_formacoes where is_demo;
  insert into iara.staff_formacoes (staff_id, titulo, tipo, instituicao, carga_horaria, concluido_em, is_demo)
  select s.id, c.titulo, c.tipo, c.inst, c.ch, make_date(2019 + (abs(('x' || substr(md5(s.id::text || c.titulo), 1, 8))::bit(32)::int) % 8), 3 + k % 8, 10), true
  from iara.staff s
  cross join lateral (select generate_series(1, abs(('x' || substr(md5(s.id::text || 'f'), 1, 8))::bit(32)::int) % 4) k) n
  cross join lateral (select * from (values
      ('Alfabetização e letramento na idade certa', 'FORMACAO_CONTINUADA', 'SEDUC Maringá', 120),
      ('BNCC na prática da sala de aula', 'FORMACAO_CONTINUADA', 'SEDUC Maringá', 40),
      ('Educação inclusiva e TEA', 'CURSO', 'Universidade Estadual', 80),
      ('Primeiros socorros no ambiente escolar', 'CURSO', 'Corpo de Bombeiros', 16),
      ('Contação de histórias', 'CURSO', 'Biblioteca Municipal', 20),
      ('Libras básico', 'CURSO', 'Instituto Federal', 60),
      ('Cultura digital e tecnologias na escola', 'FORMACAO_CONTINUADA', 'SEDUC Maringá', 30),
      ('Gestão de sala de aula e convivência', 'FORMACAO_CONTINUADA', 'SEDUC Maringá', 24),
      ('Semana pedagógica', 'EVENTO', 'SEDUC Maringá', 16)) f(titulo, tipo, inst, ch)
    order by md5(s.id::text || f.titulo || n.k) limit 1) c
  where s.is_demo and s.role <> 'AUXILIAR';

  -- horário: aulas do regente e vagas de especialista em cada turma ativa
  delete from iara.horarios_turma where is_demo;
  delete from iara.class_staff where role_type = 'ESPECIALISTA';
  insert into iara.horarios_turma (class_id, dia_semana, aula, componente, staff_id, is_demo)
  select c.id, d, a,
         coalesce((select m.componente from iara.matriz_curricular m, lateral generate_series(1, m.aulas_semana) rep
                   where m.grade_code = gl.code order by
                     -- especialistas espalhados: cada turma da unidade começa num horário diferente
                     ((m.ordem * 7 + rep * 5 + (abs(('x' || substr(md5(c.id::text), 1, 8))::bit(32)::int) % 25)) % 25), m.ordem, rep
                   offset ((d - 1) * 5 + (a - 1)) limit 1), 'Rotina e experiências'),
         null, true
  from iara.classes c join iara.grade_levels gl on gl.id = c.grade_level_id
  cross join generate_series(1, 5) d cross join generate_series(1, 5) a
  where c.status = 'ATIVA';
  update iara.horarios_turma h set staff_id = cs.staff_id
  from iara.class_staff cs, iara.classes c, iara.grade_levels gl, iara.matriz_curricular m
  where h.is_demo and cs.class_id = h.class_id and cs.role_type = 'REGENTE' and c.id = h.class_id and gl.id = c.grade_level_id
    and m.grade_code = gl.code and m.componente = h.componente and m.quem = 'REGENTE';

  -- professores sem regência viram especialistas (Educação Física, Arte, Inglês, Leitura, Música), conforme a necessidade
  create temp table if not exists tmp_espec (staff_id uuid primary key, unit_id integer, area text, cap integer, carga integer default 0) on commit drop;
  truncate tmp_espec;
  insert into tmp_espec (staff_id, unit_id, area, cap)
  select s.id, s.unit_id, null, iara.aulas_capacidade(s.carga_horaria_semanal)
  from iara.staff s
  where s.is_demo and s.role in ('PROFESSOR', 'EDUCADOR') and s.situacao = 'ATIVO'
    and not exists (select 1 from iara.class_staff cs where cs.staff_id = s.id and cs.role_type = 'REGENTE');
  -- cada servidor livre assume a área com mais aulas ainda descobertas na sua unidade (sobra quem não é necessário)
  create temp table if not exists tmp_dem (unit_id integer, componente text, n integer, primary key (unit_id, componente)) on commit drop;
  truncate tmp_dem;
  insert into tmp_dem
  select c.unit_id, h.componente, count(*) from iara.horarios_turma h join iara.classes c on c.id = h.class_id
  join iara.grade_levels gl on gl.id = c.grade_level_id
  join iara.matriz_curricular m on m.grade_code = gl.code and m.componente = h.componente and m.quem = 'ESPECIALISTA'
  where h.is_demo group by 1, 2;
  for sl in select e.staff_id, e.unit_id, e.cap from tmp_espec e order by e.unit_id, md5(e.staff_id::text) loop
    select d.componente into v_area from tmp_dem d where d.unit_id = sl.unit_id and d.n > 0 order by d.n desc, d.componente limit 1;
    continue when v_area is null;
    update tmp_espec set area = v_area where staff_id = sl.staff_id;
    -- folga na distribuição (10 aulas por pessoa): sem folga, os horários das turmas se chocam e sobram aulas descobertas
    update tmp_dem set n = n - least(sl.cap, 10) where unit_id = sl.unit_id and componente = v_area;
  end loop;
  for sl in select h.class_id, h.dia_semana, h.aula, h.componente, c.unit_id, iara.turno_base(c.shift) turno
            from iara.horarios_turma h join iara.classes c on c.id = h.class_id
            join iara.grade_levels gl on gl.id = c.grade_level_id
            join iara.matriz_curricular m on m.grade_code = gl.code and m.componente = h.componente and m.quem = 'ESPECIALISTA'
            where h.is_demo order by c.unit_id, h.componente, c.class_name, h.dia_semana, h.aula loop
    v_n_slots := v_n_slots + 1;
    select e.staff_id into v_staff from tmp_espec e
    where e.unit_id = sl.unit_id and e.area = sl.componente and e.carga < e.cap
      and (v_n_slots % 97 = 0  -- de vez em quando, um choque de horário (para o relatório mostrar como aparece)
           or not exists (select 1 from iara.horarios_turma h2 join iara.classes c2 on c2.id = h2.class_id
                          where h2.staff_id = e.staff_id and h2.dia_semana = sl.dia_semana and h2.aula = sl.aula
                            and iara.turno_base(c2.shift) = sl.turno))
    order by e.carga limit 1;
    if v_staff is null then
      v_sem := v_sem + 1;
    else
      update iara.horarios_turma set staff_id = v_staff where class_id = sl.class_id and dia_semana = sl.dia_semana and aula = sl.aula;
      update tmp_espec set carga = carga + 1 where staff_id = v_staff;
    end if;
  end loop;
  -- 2ª rodada: o que sobrou descoberto vai para um especialista de outra unidade da mesma macrorregião (itinerante),
  -- sem choque de horário; a área de quem ainda não tinha uma passa a ser a da aula
  for sl in select h.class_id, h.dia_semana, h.aula, h.componente, c.unit_id, iara.turno_base(c.shift) turno, un.macro_territory_id terr
            from iara.horarios_turma h join iara.classes c on c.id = h.class_id join iara.education_units un on un.id = c.unit_id
            where h.is_demo and h.staff_id is null and h.componente <> 'Rotina e experiências'
            order by un.macro_territory_id, c.unit_id, h.componente loop
    select e.staff_id into v_staff from tmp_espec e join iara.education_units ue on ue.id = e.unit_id
    where ue.macro_territory_id is not distinct from sl.terr and (e.area = sl.componente or e.area is null) and e.carga < e.cap
      and not exists (select 1 from iara.horarios_turma h2 join iara.classes c2 on c2.id = h2.class_id
                      where h2.staff_id = e.staff_id and h2.dia_semana = sl.dia_semana and h2.aula = sl.aula
                        and iara.turno_base(c2.shift) = sl.turno)
    order by (e.area = sl.componente) desc nulls last, e.carga limit 1;
    if v_staff is not null then
      update iara.horarios_turma set staff_id = v_staff where class_id = sl.class_id and dia_semana = sl.dia_semana and aula = sl.aula;
      update tmp_espec set carga = carga + 1, area = coalesce(area, sl.componente) where staff_id = v_staff;
      v_sem := v_sem - 1;
    end if;
  end loop;
  update iara.staff s set area_atuacao = e.area,
         formacao = case e.area when 'Educação Física' then 'Educação Física' when 'Arte' then 'Artes Visuais'
                                when 'Inglês' then 'Letras – Inglês' when 'Música' then 'Música' else 'Pedagogia' end
  from tmp_espec e where e.staff_id = s.id and e.carga > 0;
  insert into iara.class_staff (class_id, staff_id, role_type, is_primary, hours_per_week, start_date)
  select h.class_id, h.staff_id, 'ESPECIALISTA', false, count(*)::smallint, date '2026-02-02'
  from iara.horarios_turma h join tmp_espec e on e.staff_id = h.staff_id
  group by h.class_id, h.staff_id
  on conflict (class_id, staff_id) do update set hours_per_week = excluded.hours_per_week;
  update iara.class_staff cs set hours_per_week = x.n
  from (select class_id, staff_id, count(*)::smallint n from iara.horarios_turma where staff_id is not null group by 1, 2) x
  where cs.class_id = x.class_id and cs.staff_id = x.staff_id and cs.role_type = 'REGENTE';

  -- mediadores: parte dos alunos com AEE recebe um profissional de apoio da unidade (os demais aparecem como sem cobertura)
  delete from iara.mediacoes where is_demo;
  insert into iara.mediacoes (staff_id, student_id, class_id, inicio, is_demo)
  select m.staff_id, m.student_id, m.class_id, date '2026-02-09', true from (
    select e.student_id, e.class_id,
           (select s.id from iara.staff s where s.unit_id = e.unit_id and s.role in ('AUXILIAR', 'AEE') and s.is_demo
            order by md5(s.id::text || e.student_id::text) limit 1) staff_id,
           abs(('x' || substr(md5(e.student_id::text || 'm'), 1, 8))::bit(32)::int) % 10 r
    from iara.enrollments e join iara.students st on st.id = e.student_id
    where e.status = 'ACTIVE' and st.aee_status) m
  where m.staff_id is not null and m.r < 6;
  update iara.staff s set cargo = 'Mediador(a) pedagógico(a)'
  where s.is_demo and s.role = 'AUXILIAR' and exists (select 1 from iara.mediacoes md where md.staff_id = s.id);

  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('servidores', (select count(*) from iara.staff where is_demo),
    'horarios', (select count(*) from iara.horarios_turma where is_demo), 'vagas_especialista', v_n_slots, 'sem_professor', v_sem,
    'mediacoes', (select count(*) from iara.mediacoes where is_demo), 'formacoes', (select count(*) from iara.staff_formacoes where is_demo));
end $$;

-- 5. Consultas ----------------------------------------------------------------------------------------------------------------
-- carga de cada servidor: contratada, capacidade em sala e aulas atribuídas
create or replace view iara.v_carga_servidor as
select s.id staff_id, s.unit_id, s.full_name, s.role, s.cargo, s.matricula_funcional, s.situacao, s.area_atuacao, s.bond,
       s.carga_horaria_semanal ch, iara.aulas_capacidade(s.carga_horaria_semanal) capacidade,
       (select count(*) from iara.horarios_turma h where h.staff_id = s.id)::int atribuidas,
       iara.aulas_capacidade(s.carga_horaria_semanal) - (select count(*) from iara.horarios_turma h where h.staff_id = s.id)::int disponivel,
       (select count(distinct h.class_id) from iara.horarios_turma h where h.staff_id = s.id)::int turmas
from iara.staff s;

create or replace function iara.pessoal_escopo(p_unit integer) returns integer
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_scope() = 'UNIT' then return iara.my_unit(); end if;
  return p_unit;  -- rede: a unidade pedida (ou null = todas)
end $$;

create or replace function api.pessoal_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := iara.pessoal_escopo(nullif(p ->> 'unit_id', '')::int);
  v_q text := nullif(btrim(coalesce(p ->> 'q', '')), '');
  v_funcao text := nullif(p ->> 'funcao', '');
begin
  perform iara.require_perm('pessoal.read');
  return jsonb_build_object(
    'unidade', (select jsonb_build_object('id', id, 'name', name) from iara.education_units where id = v_unit),
    'totais', (select coalesce(jsonb_object_agg(role, n), '{}') from (select role, count(*) n from iara.staff s
               where (v_unit is null or s.unit_id = v_unit) group by 1) z),
    'situacao', (select coalesce(jsonb_object_agg(situacao, n), '{}') from (select situacao, count(*) n from iara.staff s
               where (v_unit is null or s.unit_id = v_unit) group by 1) z),
    'itens', (select coalesce(jsonb_agg(jsonb_build_object('id', c.staff_id, 'nome', c.full_name, 'matricula', c.matricula_funcional, 'funcao', c.role,
                'cargo', c.cargo, 'area', c.area_atuacao, 'vinculo', c.bond, 'ch', c.ch, 'capacidade', c.capacidade, 'atribuidas', c.atribuidas,
                'disponivel', c.disponivel, 'turmas', c.turmas, 'situacao', c.situacao, 'unidade', u.short_name, 'unit_id', c.unit_id)
                order by u.short_name, c.full_name), '[]')
              from (select * from iara.v_carga_servidor c
                    where (v_unit is null or c.unit_id = v_unit) and (v_funcao is null or c.role = v_funcao)
                      and (v_q is null or iara.norm(c.full_name) like '%' || iara.norm(v_q) || '%' or c.matricula_funcional = v_q)
                    order by c.full_name limit 300) c
              left join iara.education_units u on u.id = c.unit_id));
end $$;

create or replace function api.pessoal_ficha(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  s iara.staff;
  c record;
begin
  select * into s from iara.staff where id = (p ->> 'id')::uuid;
  if s.id is null then raise exception 'Servidor não encontrado.' using errcode = 'P0002'; end if;
  -- o próprio servidor vê a sua ficha; a gestão, conforme a permissão e o escopo
  if not (s.id = (select staff_id from iara.app_users where id = iara.current_user_id())
          or (iara.has_perm('pessoal.read') and iara.can_access_unit(s.unit_id))) then
    raise exception 'Servidor fora do seu escopo.' using errcode = '42501';
  end if;
  select * into c from iara.v_carga_servidor where staff_id = s.id;
  return jsonb_build_object(
    'id', s.id, 'nome', s.full_name, 'matricula', s.matricula_funcional, 'funcao', s.role, 'cargo', s.cargo, 'vinculo', s.bond,
    'ch', s.carga_horaria_semanal, 'admissao', s.data_admissao, 'escolaridade', s.escolaridade, 'formacao', s.formacao,
    'area', s.area_atuacao, 'situacao', s.situacao, 'is_demo', s.is_demo,
    'unidade', (select jsonb_build_object('id', id, 'name', name) from iara.education_units where id = s.unit_id),
    'carga', jsonb_build_object('capacidade', c.capacidade, 'atribuidas', c.atribuidas, 'disponivel', c.disponivel, 'turmas', c.turmas),
    'lotacoes', (select coalesce(jsonb_agg(jsonb_build_object('unidade', u.name, 'funcao', l.funcao, 'inicio', l.inicio, 'fim', l.fim, 'motivo', l.motivo)
                  order by l.inicio desc), '[]') from iara.staff_lotacoes l left join iara.education_units u on u.id = l.unit_id where l.staff_id = s.id),
    'formacoes', (select coalesce(jsonb_agg(jsonb_build_object('titulo', f.titulo, 'tipo', f.tipo, 'instituicao', f.instituicao,
                  'carga_horaria', f.carga_horaria, 'concluido_em', f.concluido_em) order by f.concluido_em desc), '[]')
                  from iara.staff_formacoes f where f.staff_id = s.id),
    'turmas', (select coalesce(jsonb_agg(jsonb_build_object('id', cl.id, 'nome', cl.class_name, 'turno', cl.shift, 'papel', cs.role_type,
                 'aulas', cs.hours_per_week, 'serie', gl.short_name) order by cl.class_name), '[]')
               from iara.class_staff cs join iara.classes cl on cl.id = cs.class_id join iara.grade_levels gl on gl.id = cl.grade_level_id
               where cs.staff_id = s.id),
    'horario', (select coalesce(jsonb_agg(jsonb_build_object('dia', h.dia_semana, 'aula', h.aula, 'hora', iara.aula_horario(cl.shift, h.aula),
                  'turno', iara.turno_base(cl.shift), 'turma', cl.class_name, 'componente', h.componente) order by iara.turno_base(cl.shift), h.dia_semana, h.aula), '[]')
                from iara.horarios_turma h join iara.classes cl on cl.id = h.class_id where h.staff_id = s.id),
    'mediacoes', (select coalesce(jsonb_agg(jsonb_build_object('aluno', split_part(st.full_name, ' ', 1), 'turma', cl.class_name)), '[]')
                  from iara.mediacoes m join iara.students st on st.id = m.student_id left join iara.classes cl on cl.id = m.class_id
                  where m.staff_id = s.id and (m.fim is null or m.fim >= current_date)));
end $$;

create or replace function api.turma_horario(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  c iara.classes;
begin
  select * into c from iara.classes where id = (p ->> 'class_id')::uuid;
  if c.id is null then raise exception 'Turma não encontrada.' using errcode = 'P0002'; end if;
  if not ((iara.has_perm('classes.read') and iara.can_access_unit(c.unit_id) and iara.my_role() <> 'PROFESSOR') or c.id = any (iara.minhas_turmas())) then
    raise exception 'Turma fora do seu escopo.' using errcode = '42501';
  end if;
  return jsonb_build_object('turno', c.shift, 'aulas', (select coalesce(jsonb_agg(jsonb_build_object('dia', h.dia_semana, 'aula', h.aula,
      'hora', iara.aula_horario(c.shift, h.aula), 'componente', h.componente, 'professor', s.full_name, 'staff_id', s.id,
      'sem_professor', h.staff_id is null) order by h.aula, h.dia_semana), '[]')
    from iara.horarios_turma h left join iara.staff s on s.id = h.staff_id where h.class_id = c.id));
end $$;

-- relatórios dos prints de acompanhamento (seção 13 do documento do portal)
create or replace function api.pessoal_relatorio(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := iara.pessoal_escopo(nullif(p ->> 'unit_id', '')::int);
  v_tipo text := coalesce(p ->> 'tipo', 'carga');
begin
  perform iara.require_perm('pessoal.read');
  return jsonb_build_object('tipo', v_tipo, 'itens', case v_tipo
    when 'carga' then (select coalesce(jsonb_agg(to_jsonb(z) order by z.disponivel, z.nome), '[]') from (
      select c.staff_id id, c.full_name nome, c.matricula_funcional matricula, u.short_name unidade, c.role funcao, c.area_atuacao area,
             c.ch, c.capacidade, c.atribuidas, c.disponivel, c.turmas
      from iara.v_carga_servidor c left join iara.education_units u on u.id = c.unit_id
      where (v_unit is null or c.unit_id = v_unit) and c.role in ('PROFESSOR', 'EDUCADOR', 'AEE') and c.situacao = 'ATIVO'
      order by c.disponivel, c.full_name limit 400) z)
    when 'sem_turma' then (select coalesce(jsonb_agg(to_jsonb(z) order by z.unidade, z.nome), '[]') from (
      select c.staff_id id, c.full_name nome, c.matricula_funcional matricula, u.short_name unidade, c.role funcao, c.area_atuacao area, c.ch, c.situacao
      from iara.v_carga_servidor c left join iara.education_units u on u.id = c.unit_id
      where (v_unit is null or c.unit_id = v_unit) and c.role in ('PROFESSOR', 'EDUCADOR') and c.atribuidas = 0 limit 400) z)
    when 'horarios_sem_professor' then (select coalesce(jsonb_agg(to_jsonb(z) order by z.unidade, z.turma, z.dia, z.aula), '[]') from (
      select u.short_name unidade, cl.id turma_id, cl.class_name turma, h.componente, h.dia_semana dia, h.aula, iara.aula_horario(cl.shift, h.aula) hora
      from iara.horarios_turma h join iara.classes cl on cl.id = h.class_id join iara.education_units u on u.id = cl.unit_id
      where h.staff_id is null and (v_unit is null or cl.unit_id = v_unit) limit 400) z)
    when 'choques' then (select coalesce(jsonb_agg(to_jsonb(z) order by z.nome, z.dia, z.aula), '[]') from (
      select s.id, s.full_name nome, u.short_name unidade, h.dia_semana dia, h.aula, iara.turno_base(cl.shift) turno,
             string_agg(cl.class_name, ' e ' order by cl.class_name) turmas
      from iara.horarios_turma h join iara.classes cl on cl.id = h.class_id join iara.staff s on s.id = h.staff_id
      left join iara.education_units u on u.id = s.unit_id
      where (v_unit is null or cl.unit_id = v_unit)
      group by s.id, s.full_name, u.short_name, h.dia_semana, h.aula, iara.turno_base(cl.shift) having count(*) > 1 limit 200) z)
    when 'mediadores' then (select coalesce(jsonb_agg(to_jsonb(z) order by z.unidade, z.coberto, z.aluno), '[]') from (
      select u.short_name unidade, split_part(st.full_name, ' ', 1) || ' ' || left(split_part(st.full_name, ' ', 2), 1) || '.' aluno,
             cl.class_name turma, s.full_name mediador, s.id mediador_id, s.id is not null coberto
      from iara.enrollments e join iara.students st on st.id = e.student_id join iara.classes cl on cl.id = e.class_id
      join iara.education_units u on u.id = e.unit_id
      left join iara.mediacoes m on m.student_id = e.student_id and (m.fim is null or m.fim >= current_date)
      left join iara.staff s on s.id = m.staff_id
      where e.status = 'ACTIVE' and st.aee_status and (v_unit is null or e.unit_id = v_unit) limit 400) z)
    when 'curricular' then (select coalesce(jsonb_agg(to_jsonb(z) order by z.unidade, z.componente), '[]') from (
      select u.short_name unidade, h.componente, count(*) aulas_necessarias, count(h.staff_id) aulas_atribuidas,
             round(100.0 * count(h.staff_id) / count(*)) cobertura_pct
      from iara.horarios_turma h join iara.classes cl on cl.id = h.class_id join iara.education_units u on u.id = cl.unit_id
      where (v_unit is null or cl.unit_id = v_unit)
      group by u.short_name, h.componente having count(*) > count(h.staff_id) or v_unit is not null limit 400) z)
    else '[]'::jsonb end,
    'resumo', (select jsonb_build_object(
      'servidores', count(*), 'professores', count(*) filter (where c.role in ('PROFESSOR', 'EDUCADOR')),
      'com_excesso', count(*) filter (where c.disponivel < 0 and c.role in ('PROFESSOR', 'EDUCADOR', 'AEE')),
      'sem_turma', count(*) filter (where c.atribuidas = 0 and c.role in ('PROFESSOR', 'EDUCADOR')),
      'horarios_sem_professor', (select count(*) from iara.horarios_turma h join iara.classes cl on cl.id = h.class_id
                                 where h.staff_id is null and (v_unit is null or cl.unit_id = v_unit)),
      'alunos_aee_sem_mediador', (select count(*) from iara.enrollments e join iara.students st on st.id = e.student_id
                                  where e.status = 'ACTIVE' and st.aee_status and (v_unit is null or e.unit_id = v_unit)
                                    and not exists (select 1 from iara.mediacoes m where m.student_id = e.student_id)))
      from iara.v_carga_servidor c where (v_unit is null or c.unit_id = v_unit)));
end $$;

revoke all on function iara.demo_gerar_pessoal(), iara.pessoal_escopo(integer) from public;

commit;
