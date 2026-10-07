-- IARA Educa — 052 · Sprint 2: avaliações, boletim, alfabetização, risco de aprendizagem e planos de intervenção
-- Fundamental: nota de 0 a 10 por componente e bimestre (média mínima 6, recuperação paralela substitui a nota quando
-- maior). Educação infantil: parecer descritivo por bimestre. 1º e 2º ano: sondagem de alfabetização (níveis da
-- psicogênese da escrita) e leitura. Risco: médias abaixo do mínimo, frequência perto do limite ou alfabetização
-- atrasada no 2º bimestre — a escola registra o plano de intervenção e reavalia. Família vê no portal e pela IARA.
-- Notas, pareceres e sondagens de demonstração são fictícios (is_demo). Q-20 e Q-21 definem o modelo oficial.
begin;

insert into iara.permissions (code, description, is_sensitive) values
  ('notas.read', 'Consultar notas, pareceres, alfabetização e risco de aprendizagem', true),
  ('notas.write', 'Lançar notas, pareceres e sondagens de alfabetização', true),
  ('aprendizagem.acompanhar', 'Registrar e reavaliar planos de intervenção', true)
on conflict (code) do update set description = excluded.description, is_sensitive = excluded.is_sensitive;
insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('PROFESSOR', 'notas.read'), ('PROFESSOR', 'notas.write'), ('PROFESSOR', 'aprendizagem.acompanhar'),
  ('DIRETOR_UNIDADE', 'notas.read'), ('DIRETOR_UNIDADE', 'notas.write'), ('DIRETOR_UNIDADE', 'aprendizagem.acompanhar'),
  ('SECRETARIA_ESCOLAR', 'notas.read'), ('SECRETARIA_ESCOLAR', 'notas.write'), ('SECRETARIA_ESCOLAR', 'aprendizagem.acompanhar'),
  ('SECRETARIO', 'notas.read'), ('SUPERINTENDENCIA', 'notas.read'), ('SUPERINTENDENCIA', 'aprendizagem.acompanhar'), ('GERENCIA_EI', 'notas.read')
) v(r, p)
on conflict do nothing;
update iara.tenants set settings = settings || jsonb_build_object('media_minima', 6) where id = 1 and not settings ? 'media_minima';

-- 1. Tabelas -------------------------------------------------------------------------------------------------------------------
create table if not exists iara.bimestres (
  ano smallint not null,
  numero smallint not null check (numero between 1 and 4),
  inicio date not null,
  fim date not null,
  primary key (ano, numero)
);
insert into iara.bimestres (ano, numero, inicio, fim) values
  (2026, 1, '2026-02-02', '2026-04-24'), (2026, 2, '2026-04-27', '2026-07-10'),
  (2026, 3, '2026-07-27', '2026-10-02'), (2026, 4, '2026-10-05', '2026-12-17')
on conflict (ano, numero) do update set inicio = excluded.inicio, fim = excluded.fim;

create table if not exists iara.notas (
  student_id uuid not null references iara.students(id) on delete cascade,
  class_id uuid references iara.classes(id) on delete set null,
  componente text not null,
  ano smallint not null,
  bimestre smallint not null check (bimestre between 1 and 4),
  nota numeric(4, 1) check (nota between 0 and 10),
  recuperacao numeric(4, 1) check (recuperacao between 0 and 10),
  observacao text,
  lancado_por_label text,
  lancado_em timestamptz not null default now(),
  is_demo boolean not null default true,
  primary key (student_id, componente, ano, bimestre)
);
create index if not exists notas_class_idx on iara.notas (class_id, bimestre);

create table if not exists iara.pareceres (
  student_id uuid not null references iara.students(id) on delete cascade,
  class_id uuid references iara.classes(id) on delete set null,
  ano smallint not null,
  bimestre smallint not null check (bimestre between 1 and 4),
  texto text not null,
  autor_label text,
  created_at timestamptz not null default now(),
  is_demo boolean not null default true,
  primary key (student_id, ano, bimestre)
);

create table if not exists iara.alfabetizacao_sondagens (
  student_id uuid not null references iara.students(id) on delete cascade,
  class_id uuid references iara.classes(id) on delete set null,
  ano smallint not null,
  ciclo text not null check (ciclo in ('DIAGNOSTICA', 'B1', 'B2', 'B3', 'B4')),
  nivel text not null check (nivel in ('PRE_SILABICO', 'SILABICO_SEM_VALOR', 'SILABICO_COM_VALOR', 'SILABICO_ALFABETICO', 'ALFABETICO')),
  leitura text check (leitura in ('NAO_LE', 'LE_PALAVRAS', 'LE_FRASES', 'LE_TEXTOS')),
  data date not null default current_date,
  registrado_por_label text,
  is_demo boolean not null default true,
  primary key (student_id, ano, ciclo)
);

create table if not exists iara.planos_intervencao (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references iara.students(id) on delete cascade,
  class_id uuid references iara.classes(id) on delete set null,
  unit_id integer references iara.education_units(id),
  ano smallint not null default 2026,
  motivos text[] not null,
  indicadores jsonb not null default '{}',
  objetivo text not null,
  acoes text not null,
  responsavel_label text,
  inicio date not null default current_date,
  reavaliar_em date not null,
  situacao text not null default 'ATIVO' check (situacao in ('ATIVO', 'SUPERADO', 'ENCAMINHADO', 'ENCERRADO')),
  resultado text,
  reavaliado_em timestamptz,
  criado_por_label text,
  created_at timestamptz not null default now(),
  is_demo boolean not null default true
);
create index if not exists planos_student_idx on iara.planos_intervencao (student_id, situacao);
alter table iara.alfabetizacao_sondagens add column if not exists registrado_em timestamptz not null default now();
alter table iara.planos_intervencao add column if not exists alterado_em timestamptz;

alter table iara.bimestres enable row level security;
alter table iara.notas enable row level security;
alter table iara.pareceres enable row level security;
alter table iara.alfabetizacao_sondagens enable row level security;
alter table iara.planos_intervencao enable row level security;

-- 2. Apoios -------------------------------------------------------------------------------------------------------------------
create or replace function iara.media_minima() returns numeric
language sql stable as $$ select coalesce(nullif(iara.setting('media_minima'), '')::numeric, 6) $$;
create or replace function iara.bimestre_atual() returns smallint
language sql stable as $$
  select coalesce((select numero from iara.bimestres where ano = extract(year from current_date) and current_date between inicio and fim),
                  (select max(numero) from iara.bimestres where ano = extract(year from current_date) and fim < current_date), 1)::smallint
$$;
create or replace function iara.nota_final(n numeric, r numeric) returns numeric
language sql immutable as $$ select case when n is null and r is null then null else greatest(coalesce(n, 0), coalesce(r, 0)) end $$;
create or replace function iara.nivel_ordem(p text) returns integer
language sql immutable as $$ select array_position(array['PRE_SILABICO', 'SILABICO_SEM_VALOR', 'SILABICO_COM_VALOR', 'SILABICO_ALFABETICO', 'ALFABETICO'], p) $$;

-- professor: o componente é dele naquela turma (horário); gestão da unidade lança qualquer um
create or replace function iara.pode_lancar_componente(p_class uuid, p_componente text) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select iara.has_perm('notas.write') and case
    when iara.my_role() = 'PROFESSOR' then exists (select 1 from iara.horarios_turma h where h.class_id = p_class and h.componente = p_componente
                                                    and h.staff_id = (select staff_id from iara.app_users where id = iara.current_user_id()))
    else iara.can_access_unit((select unit_id from iara.classes where id = p_class)) end
$$;

-- 3. Notas e pareceres da turma ---------------------------------------------------------------------------------------------------
create or replace function api.notas_turma(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  c iara.classes;
  v_grade text;
  v_bim smallint := coalesce(nullif(p ->> 'bimestre', '')::smallint, iara.bimestre_atual());
  v_ano smallint := 2026;
begin
  select * into c from iara.classes where id = (p ->> 'class_id')::uuid;
  if c.id is null or not iara.turma_acesso(c.id, 'notas.read') then raise exception 'Turma não encontrada ou fora do seu escopo.' using errcode = 'P0002'; end if;
  select code into v_grade from iara.grade_levels where id = c.grade_level_id;
  return jsonb_build_object(
    'turma', jsonb_build_object('id', c.id, 'nome', c.class_name, 'turno', c.shift, 'serie', v_grade, 'unidade', (select name from iara.education_units where id = c.unit_id)),
    'bimestre', v_bim, 'bimestre_atual', iara.bimestre_atual(), 'media_minima', iara.media_minima(),
    'parecer', v_grade in ('CRECHE', 'PRE'),
    'pode_parecer', v_grade in ('CRECHE', 'PRE') and iara.has_perm('notas.write') and (iara.my_role() <> 'PROFESSOR' or c.id = any (iara.minhas_turmas())),
    'componentes', (select coalesce(jsonb_agg(jsonb_build_object('nome', m.componente, 'pode_lancar', iara.pode_lancar_componente(c.id, m.componente),
        'professor', (select s.full_name from iara.horarios_turma h join iara.staff s on s.id = h.staff_id where h.class_id = c.id and h.componente = m.componente limit 1))
        order by m.ordem), '[]') from iara.matriz_curricular m where m.grade_code = v_grade and v_grade not in ('CRECHE', 'PRE')),
    'alunos', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'nome', coalesce(s.social_name, s.full_name), 'aee', s.aee_status,
        'notas', (select coalesce(jsonb_object_agg(n.componente, jsonb_build_object('nota', n.nota, 'rec', n.recuperacao, 'final', iara.nota_final(n.nota, n.recuperacao))), '{}')
                  from iara.notas n where n.student_id = s.id and n.ano = v_ano and n.bimestre = v_bim),
        'medias', (select coalesce(jsonb_object_agg(z.componente, z.m), '{}') from (select n.componente, round(avg(iara.nota_final(n.nota, n.recuperacao)), 1) m
                   from iara.notas n where n.student_id = s.id and n.ano = v_ano and n.bimestre <= v_bim group by n.componente) z),
        'parecer', (select texto from iara.pareceres pa where pa.student_id = s.id and pa.ano = v_ano and pa.bimestre = v_bim))
        order by s.full_name), '[]')
      from iara.enrollments e join iara.students s on s.id = e.student_id where e.class_id = c.id and e.status = 'ACTIVE'));
end $$;

create or replace function api.notas_lancar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.classes;
  v_comp text := p ->> 'componente';
  v_bim smallint := (p ->> 'bimestre')::smallint;
  x record;
  v_n integer := 0;
begin
  select * into c from iara.classes where id = (p ->> 'class_id')::uuid;
  if c.id is null or not iara.pode_lancar_componente(c.id, v_comp) then raise exception 'Você não lança notas deste componente nesta turma.' using errcode = '42501'; end if;
  if v_bim is null or v_bim < 1 or v_bim > iara.bimestre_atual() then raise exception 'Bimestre inválido (só até o bimestre atual).' using errcode = '22023'; end if;
  if not exists (select 1 from iara.matriz_curricular m join iara.grade_levels g on g.code = m.grade_code where g.id = c.grade_level_id and m.componente = v_comp) then
    raise exception 'Componente fora da matriz desta série.' using errcode = '22023';
  end if;
  for x in select (value ->> 'student_id')::uuid sid, nullif(value ->> 'nota', '')::numeric nota, nullif(value ->> 'rec', '')::numeric rec
           from jsonb_array_elements(coalesce(p -> 'notas', '[]')) loop
    if not exists (select 1 from iara.enrollments e where e.class_id = c.id and e.student_id = x.sid and e.status = 'ACTIVE') then
      raise exception 'Há aluno que não é desta turma.' using errcode = '22023';
    end if;
    if (x.nota is not null and (x.nota < 0 or x.nota > 10)) or (x.rec is not null and (x.rec < 0 or x.rec > 10)) then
      raise exception 'Nota deve ficar entre 0 e 10.' using errcode = '22023';
    end if;
    if x.nota is null and x.rec is null then
      delete from iara.notas where student_id = x.sid and componente = v_comp and ano = 2026 and bimestre = v_bim;
    else
      insert into iara.notas (student_id, class_id, componente, ano, bimestre, nota, recuperacao, lancado_por_label, is_demo)
      values (x.sid, c.id, v_comp, 2026, v_bim, round(x.nota, 1), round(x.rec, 1), iara.my_label(), false)
      on conflict (student_id, componente, ano, bimestre) do update set nota = excluded.nota, recuperacao = excluded.recuperacao,
        lancado_por_label = excluded.lancado_por_label, lancado_em = now(), is_demo = false, class_id = excluded.class_id;
    end if;
    v_n := v_n + 1;
  end loop;
  perform iara.audit_event('NOTAS_LANCADAS', 'class', c.id::text, c.unit_id, format('Notas de %s (%sº bimestre) lançadas: %s aluno(s).', v_comp, v_bim, v_n));
  return api.notas_turma(jsonb_build_object('class_id', c.id, 'bimestre', v_bim));
end $$;

create or replace function api.parecer_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.classes;
  v_student uuid := (p ->> 'student_id')::uuid;
  v_bim smallint := (p ->> 'bimestre')::smallint;
  v_txt text := btrim(coalesce(p ->> 'texto', ''));
begin
  select * into c from iara.classes where id = (p ->> 'class_id')::uuid;
  if c.id is null or not iara.has_perm('notas.write') or not ((iara.my_role() <> 'PROFESSOR' and iara.can_access_unit(c.unit_id)) or c.id = any (iara.minhas_turmas())) then
    raise exception 'Sem permissão para pareceres desta turma.' using errcode = '42501';
  end if;
  if not exists (select 1 from iara.enrollments e where e.class_id = c.id and e.student_id = v_student and e.status = 'ACTIVE') then raise exception 'Aluno fora da turma.' using errcode = '22023'; end if;
  if v_bim is null or v_bim < 1 or v_bim > iara.bimestre_atual() then raise exception 'Bimestre inválido.' using errcode = '22023'; end if;
  if length(v_txt) not between 20 and 4000 then raise exception 'Escreva o parecer (de 20 a 4.000 caracteres).' using errcode = '22023'; end if;
  insert into iara.pareceres (student_id, class_id, ano, bimestre, texto, autor_label, is_demo) values (v_student, c.id, 2026, v_bim, v_txt, iara.my_label(), false)
  on conflict (student_id, ano, bimestre) do update set texto = excluded.texto, autor_label = excluded.autor_label, created_at = now(), is_demo = false;
  perform iara.audit_event('PARECER_REGISTRADO', 'student', v_student::text, c.unit_id, format('Parecer do %sº bimestre registrado.', v_bim));
  return jsonb_build_object('ok', true);
end $$;

-- 4. Alfabetização (1º e 2º ano) -----------------------------------------------------------------------------------------------
create or replace function api.alfabetizacao_turma(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  c iara.classes;
  v_grade text;
  v_ciclo text := coalesce(nullif(p ->> 'ciclo', ''), (array['B1', 'B2', 'B3', 'B4'])[iara.bimestre_atual()]);
begin
  select * into c from iara.classes where id = (p ->> 'class_id')::uuid;
  if c.id is null or not iara.turma_acesso(c.id, 'notas.read') then raise exception 'Turma não encontrada ou fora do seu escopo.' using errcode = 'P0002'; end if;
  select code into v_grade from iara.grade_levels where id = c.grade_level_id;
  if v_grade not in ('EF1', 'EF2') then raise exception 'A sondagem de alfabetização é do 1º e do 2º ano.' using errcode = '22023'; end if;
  return jsonb_build_object('turma', jsonb_build_object('id', c.id, 'nome', c.class_name, 'serie', v_grade), 'ciclo', v_ciclo,
    'pode_lancar', iara.has_perm('notas.write') and ((iara.my_role() <> 'PROFESSOR' and iara.can_access_unit(c.unit_id)) or c.id = any (iara.minhas_turmas())),
    'distribuicao', (select coalesce(jsonb_object_agg(nivel, n), '{}') from (select a.nivel, count(*) n from iara.alfabetizacao_sondagens a
        join iara.enrollments e on e.student_id = a.student_id and e.class_id = c.id and e.status = 'ACTIVE' where a.ano = 2026 and a.ciclo = v_ciclo group by 1) z),
    'alunos', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'nome', coalesce(s.social_name, s.full_name),
        'atual', (select jsonb_build_object('nivel', a.nivel, 'leitura', a.leitura) from iara.alfabetizacao_sondagens a where a.student_id = s.id and a.ano = 2026 and a.ciclo = v_ciclo),
        'historico', (select coalesce(jsonb_agg(jsonb_build_object('ciclo', a.ciclo, 'nivel', a.nivel, 'leitura', a.leitura) order by a.data), '[]')
                      from iara.alfabetizacao_sondagens a where a.student_id = s.id and a.ano = 2026)) order by s.full_name), '[]')
      from iara.enrollments e join iara.students s on s.id = e.student_id where e.class_id = c.id and e.status = 'ACTIVE'));
end $$;

create or replace function api.alfabetizacao_lancar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.classes;
  v_ciclo text := p ->> 'ciclo';
  x record;
  v_n integer := 0;
begin
  select * into c from iara.classes where id = (p ->> 'class_id')::uuid;
  if c.id is null or not iara.has_perm('notas.write') or not ((iara.my_role() <> 'PROFESSOR' and iara.can_access_unit(c.unit_id)) or c.id = any (iara.minhas_turmas())) then
    raise exception 'Sem permissão para a sondagem desta turma.' using errcode = '42501';
  end if;
  if v_ciclo not in ('DIAGNOSTICA', 'B1', 'B2', 'B3', 'B4') then raise exception 'Ciclo inválido.' using errcode = '22023'; end if;
  for x in select (value ->> 'student_id')::uuid sid, nullif(value ->> 'nivel', '') nivel, nullif(value ->> 'leitura', '') leitura
           from jsonb_array_elements(coalesce(p -> 'registros', '[]')) loop
    continue when x.nivel is null;
    if not exists (select 1 from iara.enrollments e where e.class_id = c.id and e.student_id = x.sid and e.status = 'ACTIVE') then raise exception 'Há aluno que não é desta turma.' using errcode = '22023'; end if;
    insert into iara.alfabetizacao_sondagens (student_id, class_id, ano, ciclo, nivel, leitura, data, registrado_por_label, is_demo)
    values (x.sid, c.id, 2026, v_ciclo, x.nivel, x.leitura, current_date, iara.my_label(), false)
    on conflict (student_id, ano, ciclo) do update set nivel = excluded.nivel, leitura = excluded.leitura, data = current_date,
      registrado_por_label = excluded.registrado_por_label, registrado_em = now(), is_demo = false;
    v_n := v_n + 1;
  end loop;
  perform iara.audit_event('SONDAGEM_ALFABETIZACAO', 'class', c.id::text, c.unit_id, format('Sondagem de alfabetização (%s) registrada: %s aluno(s).', v_ciclo, v_n));
  return api.alfabetizacao_turma(jsonb_build_object('class_id', c.id, 'ciclo', v_ciclo));
end $$;

-- 5. Risco de aprendizagem (conjunto) e planos de intervenção ----------------------------------------------------------------------
-- quem está em risco numa unidade ou turma: média abaixo do mínimo em 2+ componentes (ou em Português/Matemática),
-- frequência a menos de 5 pontos do mínimo, ou alfabetização atrasada a partir do 2º bimestre
create or replace function iara.risco_alunos(p_unit integer, p_class uuid default null)
returns table (student_id uuid, class_id uuid, unit_id integer, motivos text[], indicadores jsonb)
language sql stable security definer set search_path = iara, public
as $$
  with al as (
    select e.student_id, e.class_id, e.unit_id, gl.code grade from iara.enrollments e join iara.classes c on c.id = e.class_id
    join iara.grade_levels gl on gl.id = c.grade_level_id
    where e.status = 'ACTIVE' and (p_unit is null or e.unit_id = p_unit) and (p_class is null or e.class_id = p_class) and gl.code not in ('CRECHE', 'PRE')),
  med as (
    select n.student_id, n.componente, avg(iara.nota_final(n.nota, n.recuperacao)) m from iara.notas n join al on al.student_id = n.student_id
    where n.ano = 2026 group by 1, 2),
  cfg as (select iara.media_minima() mm),
  abaixo as (
    select student_id, array_agg(componente order by componente) filter (where m < cfg.mm) comps,
           count(*) filter (where m < cfg.mm) n,
           bool_or(m < cfg.mm and componente in ('Língua Portuguesa', 'Matemática')) basico
    from med cross join cfg group by 1),
  dias as (select r.class_id, count(*) d from iara.frequencia_registros r where r.class_id in (select class_id from al) group by 1),
  faltas as (select f.student_id, count(*) f from iara.frequencia_faltas f where f.student_id in (select student_id from al) group by 1),
  alfa as (select distinct on (a.student_id) a.student_id, a.nivel, a.ciclo from iara.alfabetizacao_sondagens a
           where a.ano = 2026 and a.student_id in (select student_id from al) order by a.student_id, a.data desc)
  select al.student_id, al.class_id, al.unit_id,
         array_remove(array[
           case when coalesce(ab.n, 0) >= 2 or coalesce(ab.basico, false) then 'NOTAS' end,
           case when d.d >= 20 and 100.0 * (d.d - coalesce(f.f, 0)) / d.d < iara.freq_minima(al.grade) + 5 then 'FREQUENCIA' end,
           case when al.grade in ('EF1', 'EF2') and fa.ciclo in ('B2', 'B3', 'B4')
                 and iara.nivel_ordem(fa.nivel) < case when al.grade = 'EF1' then 3 else 5 end then 'ALFABETIZACAO' end], null),
         jsonb_build_object('componentes_abaixo', coalesce(to_jsonb(ab.comps), '[]'),
                            'frequencia', case when d.d > 0 then round(100.0 * (d.d - coalesce(f.f, 0)) / d.d, 1) end,
                            'nivel', fa.nivel, 'ciclo', fa.ciclo)
  from al left join abaixo ab on ab.student_id = al.student_id left join dias d on d.class_id = al.class_id
  left join faltas f on f.student_id = al.student_id left join alfa fa on fa.student_id = al.student_id
  where coalesce(ab.n, 0) >= 2 or coalesce(ab.basico, false)
     or (d.d >= 20 and 100.0 * (d.d - coalesce(f.f, 0)) / d.d < iara.freq_minima(al.grade) + 5)
     or (al.grade in ('EF1', 'EF2') and fa.ciclo in ('B2', 'B3', 'B4') and iara.nivel_ordem(fa.nivel) < case when al.grade = 'EF1' then 3 else 5 end)
$$;

create or replace function iara.plano_json(pl iara.planos_intervencao) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', pl.id, 'student_id', pl.student_id, 'motivos', to_jsonb(pl.motivos), 'indicadores', pl.indicadores, 'objetivo', pl.objetivo,
    'acoes', pl.acoes, 'responsavel', pl.responsavel_label, 'inicio', pl.inicio, 'reavaliar_em', pl.reavaliar_em, 'situacao', pl.situacao,
    'resultado', pl.resultado, 'reavaliado_em', pl.reavaliado_em, 'atrasado', pl.situacao = 'ATIVO' and pl.reavaliar_em < current_date, 'is_demo', pl.is_demo)
$$;

create or replace function api.risco_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_class uuid := nullif(p ->> 'class_id', '')::uuid;
begin
  perform iara.require_perm('notas.read');
  if v_class is not null and not iara.turma_acesso(v_class, 'notas.read') then raise exception 'Turma fora do seu escopo.' using errcode = '42501'; end if;
  if iara.my_role() = 'PROFESSOR' and v_class is null then raise exception 'Escolha uma das suas turmas.' using errcode = '22023'; end if;
  if v_unit is null and v_class is null then raise exception 'Escolha a unidade.' using errcode = '22023'; end if;
  return (with r as (select * from iara.risco_alunos(v_unit, v_class))
    select jsonb_build_object(
      'total', (select count(*) from r),
      'com_plano', (select count(*) from r where exists (select 1 from iara.planos_intervencao pl where pl.student_id = r.student_id and pl.situacao = 'ATIVO')),
      'por_motivo', (select coalesce(jsonb_object_agg(m, n), '{}') from (select unnest(motivos) m, count(*) n from r group by 1) z),
      'pode_planejar', iara.has_perm('aprendizagem.acompanhar'),
      'itens', (select coalesce(jsonb_agg(jsonb_build_object('student_id', r.student_id, 'aluno', s.full_name, 'turma', c.class_name, 'class_id', r.class_id,
          'motivos', to_jsonb(r.motivos), 'indicadores', r.indicadores,
          'plano', (select iara.plano_json(pl) from iara.planos_intervencao pl where pl.student_id = r.student_id and pl.ano = 2026 order by (pl.situacao = 'ATIVO') desc, pl.created_at desc limit 1))
          order by c.class_name, s.full_name), '[]')
        from r join iara.students s on s.id = r.student_id join iara.classes c on c.id = r.class_id)));
end $$;

create or replace function api.plano_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id uuid := nullif(p ->> 'id', '')::uuid;
  v_student uuid := (p ->> 'student_id')::uuid;
  v_motivos text[] := array(select jsonb_array_elements_text(coalesce(p -> 'motivos', '[]')));
  e record;
  pl iara.planos_intervencao;
begin
  if not iara.aluno_acesso(v_student, 'aprendizagem.acompanhar') then raise exception 'Sem permissão para o plano deste aluno.' using errcode = '42501'; end if;
  if not v_motivos <@ array['NOTAS', 'FREQUENCIA', 'ALFABETIZACAO', 'OUTRO'] or cardinality(v_motivos) = 0 then raise exception 'Informe o(s) motivo(s).' using errcode = '22023'; end if;
  if length(btrim(coalesce(p ->> 'objetivo', ''))) < 10 or length(btrim(coalesce(p ->> 'acoes', ''))) < 10 then
    raise exception 'Descreva o objetivo e as ações (pelo menos 10 caracteres cada).' using errcode = '22023';
  end if;
  select en.unit_id, en.class_id into e from iara.enrollments en where en.student_id = v_student and en.status = 'ACTIVE' limit 1;
  if v_id is null then
    insert into iara.planos_intervencao (student_id, class_id, unit_id, motivos, indicadores, objetivo, acoes, responsavel_label, reavaliar_em, criado_por_label, is_demo)
    values (v_student, e.class_id, e.unit_id, v_motivos, coalesce((select r.indicadores from iara.risco_alunos(e.unit_id, e.class_id) r where r.student_id = v_student), '{}'),
            btrim(p ->> 'objetivo'), btrim(p ->> 'acoes'), coalesce(nullif(btrim(p ->> 'responsavel'), ''), iara.my_label()),
            coalesce(nullif(p ->> 'reavaliar_em', '')::date, current_date + 45), iara.my_label(), false)
    returning * into pl;
    perform iara.avisar_familia(v_student, 'PLANO_APOIO', 'Plano de apoio na escola',
      'A escola montou um plano de apoio para a criança: ' || left(btrim(p ->> 'objetivo'), 200) || '. Veja os detalhes no boletim.');
  else
    update iara.planos_intervencao set motivos = v_motivos, objetivo = btrim(p ->> 'objetivo'), acoes = btrim(p ->> 'acoes'),
           responsavel_label = coalesce(nullif(btrim(p ->> 'responsavel'), ''), responsavel_label),
           reavaliar_em = coalesce(nullif(p ->> 'reavaliar_em', '')::date, reavaliar_em), alterado_em = now()
    where id = v_id and student_id = v_student returning * into pl;
    if pl.id is null then raise exception 'Plano não encontrado.' using errcode = 'P0002'; end if;
  end if;
  perform iara.audit_event('PLANO_INTERVENCAO', 'student', v_student::text, e.unit_id, 'Plano de intervenção registrado.');
  return iara.plano_json(pl);
end $$;

create or replace function api.plano_reavaliar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  pl iara.planos_intervencao;
  v_sit text := p ->> 'situacao';
begin
  select * into pl from iara.planos_intervencao where id = (p ->> 'id')::uuid for update;
  if pl.id is null or not iara.aluno_acesso(pl.student_id, 'aprendizagem.acompanhar') then raise exception 'Plano não encontrado.' using errcode = 'P0002'; end if;
  if v_sit not in ('ATIVO', 'SUPERADO', 'ENCAMINHADO', 'ENCERRADO') then raise exception 'Situação inválida.' using errcode = '22023'; end if;
  if length(btrim(coalesce(p ->> 'resultado', ''))) < 10 then raise exception 'Registre o resultado da reavaliação.' using errcode = '22023'; end if;
  update iara.planos_intervencao set situacao = v_sit, resultado = btrim(p ->> 'resultado'), reavaliado_em = now(), alterado_em = now(),
         reavaliar_em = case when v_sit = 'ATIVO' then coalesce(nullif(p ->> 'reavaliar_em', '')::date, current_date + 45) else reavaliar_em end
  where id = pl.id returning * into pl;
  perform iara.audit_event('PLANO_REAVALIADO', 'student', pl.student_id::text, pl.unit_id, 'Plano de intervenção reavaliado: ' || lower(v_sit) || '.');
  return iara.plano_json(pl);
end $$;

-- 6. Boletim (escola e família) e painel ----------------------------------------------------------------------------------------------
create or replace function iara.boletim_json(p_student uuid, p_familia boolean) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('student_id', s.id, 'aluno', s.full_name, 'primeiro_nome', split_part(s.full_name, ' ', 1),
    'turma', c.class_name, 'serie', gl.short_name, 'grade', gl.code, 'unidade', u.short_name, 'ano', 2026, 'media_minima', iara.media_minima(),
    'bimestre_atual', iara.bimestre_atual(), 'parecer', gl.code in ('CRECHE', 'PRE'),
    'componentes', (select coalesce(jsonb_agg(jsonb_build_object('nome', m.componente,
        'bimestres', (select coalesce(jsonb_object_agg(n.bimestre::text, iara.nota_final(n.nota, n.recuperacao)), '{}') from iara.notas n
                      where n.student_id = s.id and n.ano = 2026 and n.componente = m.componente),
        'recuperou', exists (select 1 from iara.notas n where n.student_id = s.id and n.ano = 2026 and n.componente = m.componente and n.recuperacao > coalesce(n.nota, 0)),
        'media', (select round(avg(iara.nota_final(n.nota, n.recuperacao)), 1) from iara.notas n where n.student_id = s.id and n.ano = 2026 and n.componente = m.componente))
        order by m.ordem), '[]') from iara.matriz_curricular m where m.grade_code = gl.code and gl.code not in ('CRECHE', 'PRE')),
    'pareceres', (select coalesce(jsonb_agg(jsonb_build_object('bimestre', pa.bimestre, 'texto', pa.texto, 'autor', pa.autor_label) order by pa.bimestre), '[]')
                  from iara.pareceres pa where pa.student_id = s.id and pa.ano = 2026),
    'alfabetizacao', (select coalesce(jsonb_agg(jsonb_build_object('ciclo', a.ciclo, 'nivel', a.nivel, 'leitura', a.leitura, 'data', a.data) order by a.data), '[]')
                      from iara.alfabetizacao_sondagens a where a.student_id = s.id and a.ano = 2026),
    'frequencia', iara.frequencia_resumo(s.id) || jsonb_build_object('minimo', iara.freq_minima(gl.code)),
    'planos', (select coalesce(jsonb_agg(iara.plano_json(pl) - case when p_familia then 'indicadores' else '' end order by pl.created_at desc), '[]')
               from iara.planos_intervencao pl where pl.student_id = s.id and pl.ano = 2026 and (not p_familia or pl.situacao in ('ATIVO', 'SUPERADO'))))
  from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
  join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id join iara.education_units u on u.id = e.unit_id
  where s.id = p_student
$$;

create or replace function api.boletim(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_fam boolean := iara.my_guardian() is not null;
begin
  if not ((v_fam and v_student in (select iara.my_student_ids())) or iara.aluno_acesso(v_student, 'notas.read')) then
    raise exception 'Aluno fora do seu escopo.' using errcode = '42501';
  end if;
  return coalesce(iara.boletim_json(v_student, v_fam), jsonb_build_object('sem_matricula', true));
end $$;

create or replace function api.familia_boletim(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(iara.boletim_json(e.student_id, true) order by s.full_name), '[]')
          from iara.enrollments e join iara.students s on s.id = e.student_id where e.status = 'ACTIVE' and e.student_id in (select iara.my_student_ids()));
end $$;

create or replace function api.desempenho_painel(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_min numeric := iara.media_minima();
  -- padrão: o último bimestre encerrado (o atual ainda está sendo lançado)
  v_bim smallint := coalesce(nullif(p ->> 'bimestre', '')::smallint, (select max(numero) from iara.bimestres where ano = 2026 and fim < current_date), 1);
begin
  perform iara.require_perm('notas.read');
  if iara.my_role() = 'PROFESSOR' then raise exception 'Use as notas das suas turmas.' using errcode = '42501'; end if;
  return (with n as (
      select n.*, c.unit_id, iara.nota_final(n.nota, n.recuperacao) f from iara.notas n join iara.classes c on c.id = n.class_id
      where n.ano = 2026 and n.bimestre = v_bim and (v_unit is null or c.unit_id = v_unit))
    select jsonb_build_object('bimestre', v_bim, 'media_minima', v_min,
      'unidade', (select name from iara.education_units where id = v_unit),
      'por_componente', (select coalesce(jsonb_agg(jsonb_build_object('componente', componente, 'media', m, 'abaixo_pct', a, 'lancadas', q) order by m), '[]') from (
          select componente, round(avg(f), 1) m, round(100.0 * count(*) filter (where f < v_min) / count(*), 1) a, count(*) q from n group by 1) z),
      'alunos_abaixo', (select count(distinct student_id) from n where f < v_min),
      'alunos_avaliados', (select count(distinct student_id) from n),
      'por_unidade', case when v_unit is null then (select coalesce(jsonb_agg(jsonb_build_object('unit_id', unit_id, 'unidade', u.short_name, 'media', m, 'abaixo_pct', a) order by a desc), '[]')
          from (select unit_id, round(avg(f), 1) m, round(100.0 * count(*) filter (where f < v_min) / count(*), 1) a from n group by 1) z
          join iara.education_units u on u.id = z.unit_id) end,
      'por_turma', case when v_unit is not null then (select coalesce(jsonb_agg(jsonb_build_object('class_id', c.id, 'turma', c.class_name, 'media', m, 'abaixo_pct', a) order by c.class_name), '[]')
          from (select class_id, round(avg(f), 1) m, round(100.0 * count(*) filter (where f < v_min) / count(*), 1) a from n group by 1) z
          join iara.classes c on c.id = z.class_id) end,
      'alfabetizacao', (select coalesce(jsonb_agg(jsonb_build_object('serie', grade, 'nivel', nivel, 'n', q)), '[]') from (
          select gl.code grade, a.nivel, count(*) q from iara.alfabetizacao_sondagens a
          join iara.enrollments e on e.student_id = a.student_id and e.status = 'ACTIVE' join iara.classes c on c.id = e.class_id
          join iara.grade_levels gl on gl.id = c.grade_level_id
          where a.ano = 2026 and a.ciclo = 'B' || (select coalesce(max(numero), 1) from iara.bimestres where ano = 2026 and fim < current_date)
            and (v_unit is null or e.unit_id = v_unit) group by 1, 2) z),
      'planos', (select coalesce(jsonb_object_agg(situacao, q), '{}') from (select situacao, count(*) q from iara.planos_intervencao
                 where ano = 2026 and (v_unit is null or unit_id = v_unit) group by 1) z),
      'planos_atrasados', (select count(*) from iara.planos_intervencao where ano = 2026 and situacao = 'ATIVO' and reavaliar_em < current_date and (v_unit is null or unit_id = v_unit))));
end $$;

-- 7. Demonstração -------------------------------------------------------------------------------------------------------------------
-- habilidade de cada aluno (hash) + dificuldade do componente + ruído; quem falta mais tende a ir pior
drop function if exists iara.demo_gerar_notas_bimestre(smallint);
create or replace function iara.demo_gerar_notas_bimestre(p_bim smallint, p_class uuid default null) returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  if p_class is null then delete from iara.notas where is_demo and ano = 2026 and bimestre = p_bim; end if;
  insert into iara.notas (student_id, class_id, componente, ano, bimestre, nota, recuperacao, lancado_por_label, lancado_em, is_demo)
  select x.student_id, x.class_id, x.componente, 2026, p_bim, x.nota,
         case when x.nota < 6 and x.h % 3 <> 0 then least(10, round((x.nota + 1.2 + (x.h % 20) / 10.0)::numeric, 1)) end,
         'Professor(a) da turma (demonstração)', (select fim from iara.bimestres where ano = 2026 and numero = p_bim) + interval '3 days 10 hours', true
  from (select e.student_id, e.class_id, m.componente, abs(hashtext(e.student_id::text || m.componente || p_bim)) h,
               greatest(0, least(10, round((7.3 + ((abs(hashtext(e.student_id::text || 'hab')) % 100) - 50) / 22.0
                 + case m.componente when 'Matemática' then -0.6 when 'Língua Portuguesa' then -0.3 when 'Educação Física' then 0.7 when 'Arte' then 0.5 else 0 end
                 + ((abs(hashtext(e.student_id::text || m.componente || p_bim)) % 100) - 50) / 45.0
                 - case when iara.demo_prob_falta(e.student_id) > 0.08 then 1.4 else 0 end
                 + (p_bim - 2) * 0.15)::numeric, 1))) nota
        from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
        join iara.matriz_curricular m on m.grade_code = gl.code
        where e.status = 'ACTIVE' and gl.code not in ('CRECHE', 'PRE') and (p_class is null or e.class_id = p_class)) x
  on conflict (student_id, componente, ano, bimestre) do nothing;
  get diagnostics v_n = row_count;
  perform set_config('iara.skip_audit', 'off', true);
  return v_n;
end $$;

drop function if exists iara.demo_gerar_pareceres();
create or replace function iara.demo_gerar_pareceres(p_class uuid default null) returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_n integer;
  v_ana uuid := nullif(iara.setting('demo_student_ana'), '')::uuid;
begin
  perform set_config('iara.skip_audit', 'on', true);
  if p_class is null then delete from iara.pareceres where is_demo; end if;
  insert into iara.pareceres (student_id, class_id, ano, bimestre, texto, autor_label, created_at, is_demo)
  select e.student_id, e.class_id, 2026, b.numero,
         split_part(s.full_name, ' ', 1) || ' ' ||
         (array['participa com entusiasmo das rodas de conversa e das brincadeiras coletivas',
                'demonstra curiosidade nas atividades de exploração da natureza e dos materiais',
                'tem avançado na autonomia nas rotinas de alimentação e higiene',
                'interage bem com os colegas e começa a resolver pequenos conflitos com o diálogo',
                'gosta de ouvir histórias e reconta trechos com as próprias palavras'])[1 + abs(hashtext(s.id::text || b.numero)) % 5] || '. ' ||
         (array['Neste bimestre, ampliou o repertório de movimentos e a coordenação nas atividades de pátio.',
                'Reconhece o próprio nome e começa a identificar algumas letras e números do cotidiano.',
                'Expressa sentimentos e preferências e pede ajuda quando precisa.',
                'Explorou tintas, massinha e materiais recicláveis com criatividade.',
                'Seguimos incentivando a fala em grupo e a escuta dos colegas.'])[1 + abs(hashtext(s.id::text || b.numero || 'b')) % 5],
         'Professora regente (demonstração)', b.fim + interval '4 days', true
  from iara.enrollments e join iara.students s on s.id = e.student_id join iara.classes c on c.id = e.class_id
  join iara.grade_levels gl on gl.id = c.grade_level_id cross join iara.bimestres b
  where e.status = 'ACTIVE' and gl.code in ('CRECHE', 'PRE') and b.ano = 2026 and b.fim < current_date and (p_class is null or e.class_id = p_class)
  on conflict (student_id, ano, bimestre) do nothing;
  get diagnostics v_n = row_count;
  if v_ana is not null then
    update iara.pareceres set texto = 'Ana participa com alegria da contação de histórias e já reconta as histórias preferidas para a turma. '
      || case bimestre when 1 then 'Adaptou-se bem à rotina e faz amizade com facilidade.'
                       when 2 then 'Reconhece o próprio nome e o dos colegas e gosta de desenhar a família.'
                       else 'Está escrevendo o nome sozinha, conta até 20 e ajuda os colegas nas atividades em grupo.' end
    where student_id = v_ana and is_demo and texto not like 'Ana participa com alegria%';
  end if;
  perform set_config('iara.skip_audit', 'off', true);
  return v_n;
end $$;

-- sondagens do 1º e 2º ano: diagnóstica em fevereiro e ao fim de cada bimestre, com avanço gradual
drop function if exists iara.demo_gerar_alfabetizacao();
create or replace function iara.demo_gerar_alfabetizacao(p_class uuid default null) returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  if p_class is null then delete from iara.alfabetizacao_sondagens where is_demo; end if;
  insert into iara.alfabetizacao_sondagens (student_id, class_id, ano, ciclo, nivel, leitura, data, registrado_por_label, is_demo)
  select x.student_id, x.class_id, 2026, x.ciclo,
         (array['PRE_SILABICO', 'SILABICO_SEM_VALOR', 'SILABICO_COM_VALOR', 'SILABICO_ALFABETICO', 'ALFABETICO'])[x.idx],
         (array['NAO_LE', 'NAO_LE', 'LE_PALAVRAS', 'LE_FRASES', 'LE_TEXTOS'])[x.idx],
         x.data, 'Professora regente (demonstração)', true
  from (select e.student_id, e.class_id, ci.ciclo, ci.data,
               least(5, greatest(1, case gl.code when 'EF1' then 1 else 3 end + (abs(hashtext(e.student_id::text || 'alf')) % 100) / 45
                 + floor(ci.k * (0.35 + (abs(hashtext(e.student_id::text || 'rit')) % 100) / 160.0))::int
                 - case when iara.demo_prob_falta(e.student_id) > 0.08 then 1 else 0 end)) idx
        from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
        cross join (values ('DIAGNOSTICA', date '2026-02-20', 0), ('B1', date '2026-04-22', 1), ('B2', date '2026-07-08', 2), ('B3', date '2026-09-30', 3)) ci(ciclo, data, k)
        where e.status = 'ACTIVE' and gl.code in ('EF1', 'EF2') and ci.data < current_date and (p_class is null or e.class_id = p_class)) x
  on conflict (student_id, ano, ciclo) do nothing;
  get diagnostics v_n = row_count;
  perform set_config('iara.skip_audit', 'off', true);
  return v_n;
end $$;

-- planos para parte dos alunos em risco (a escola ainda não planejou para todos: é o que o painel mostra)
create or replace function iara.demo_gerar_planos() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.planos_intervencao where is_demo;
  insert into iara.planos_intervencao (student_id, class_id, unit_id, motivos, indicadores, objetivo, acoes, responsavel_label, inicio, reavaliar_em,
                                       situacao, resultado, reavaliado_em, criado_por_label, created_at, is_demo)
  select r.student_id, r.class_id, r.unit_id, r.motivos, r.indicadores,
         case when 'ALFABETIZACAO' = any (r.motivos) then 'Avançar na hipótese de escrita e na leitura de palavras e frases simples.'
              when 'FREQUENCIA' = any (r.motivos) then 'Recuperar a frequência e as aprendizagens perdidas nas ausências.'
              else 'Recuperar as aprendizagens de ' || coalesce((r.indicadores -> 'componentes_abaixo' ->> 0), 'Português e Matemática') || '.' end,
         case when 'ALFABETIZACAO' = any (r.motivos) then 'Reagrupamento 2x por semana; jogos de consciência fonológica; leitura diária com a família (livro na mochila).'
              when 'FREQUENCIA' = any (r.motivos) then 'Contato semanal com a família; atividades de reposição; acompanhamento pela coordenação.'
              else 'Recuperação paralela no contraturno; atividades diferenciadas em sala; devolutiva quinzenal à família.' end,
         'Coordenação pedagógica (demonstração)', current_date - (abs(hashtext(r.student_id::text)) % 40 + 10),
         current_date + (abs(hashtext(r.student_id::text)) % 50) - 12,
         case when abs(hashtext(r.student_id::text || 'pl')) % 10 < 7 then 'ATIVO' when abs(hashtext(r.student_id::text || 'pl')) % 10 < 9 then 'SUPERADO' else 'ENCAMINHADO' end,
         case when abs(hashtext(r.student_id::text || 'pl')) % 10 between 7 and 8 then 'Atingiu a média nas avaliações de recuperação e avançou na leitura.'
              when abs(hashtext(r.student_id::text || 'pl')) % 10 = 9 then 'Encaminhado para avaliação multiprofissional (com autorização da família).' end,
         case when abs(hashtext(r.student_id::text || 'pl')) % 10 >= 7 then now() - interval '5 days' end,
         'Coordenação pedagógica (demonstração)', now() - make_interval(days => abs(hashtext(r.student_id::text)) % 40 + 10), true
  from iara.risco_alunos(null, null) r
  where abs(hashtext(r.student_id::text || 'tem')) % 100 < 55;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('planos', (select count(*) from iara.planos_intervencao where is_demo));
end $$;

revoke all on function iara.demo_gerar_notas_bimestre(smallint, uuid), iara.demo_gerar_pareceres(uuid), iara.demo_gerar_alfabetizacao(uuid),
  iara.demo_gerar_planos(), iara.risco_alunos(integer, uuid) from public;

-- 8. Classificação --------------------------------------------------------------------------------------------------------------
insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('pareceres', 'texto', 'PESSOAL', 'desenvolvimento da criança', 'acompanhamento pedagógico e família', 'escopo família/unidade/professor da turma'),
  ('pareceres', 'autor_label', 'PESSOAL', 'identificação', 'auditoria (quem escreveu)', null),
  ('planos_intervencao', 'objetivo', 'PESSOAL', 'aprendizagem', 'plano de intervenção', 'escopo família/unidade'),
  ('planos_intervencao', 'acoes', 'PESSOAL', 'aprendizagem', 'plano de intervenção', 'escopo família/unidade'),
  ('planos_intervencao', 'resultado', 'PESSOAL', 'aprendizagem', 'reavaliação', 'escopo família/unidade'),
  ('planos_intervencao', 'responsavel_label', 'PESSOAL', 'identificação', 'responsável pelo plano', null),
  ('planos_intervencao', 'criado_por_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('notas', 'observacao', 'PESSOAL', 'aprendizagem', 'registro do professor', 'escopo família/unidade'),
  ('notas', 'lancado_por_label', 'PESSOAL', 'identificação', 'auditoria (quem lançou)', null),
  ('alfabetizacao_sondagens', 'registrado_por_label', 'PESSOAL', 'identificação', 'auditoria (quem registrou)', null)
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

commit;
