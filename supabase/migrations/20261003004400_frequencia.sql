-- IARA Educa — 044 · Calendário escolar e frequência (Sprint 1, módulo 2; itens 35 e 50 da seção 12)
-- Calendário: feriados nacionais reais de 2026 (Lei 662/1949, Lei 6.802/1980, Lei 14.759/2023) e datas escolares de
-- demonstração (ano letivo, bimestres, recesso, formação). Frequência: chamada por turma e dia, faltas e justificativas,
-- alertas de ausência (consecutiva e frequência abaixo do mínimo) que viram acompanhamento da escola.
-- Mínimos reais da LDB (Lei 9.394/1996): 75% no ensino fundamental (art. 24, VI) e 60% na pré-escola (art. 31, IV).
begin;

-- 1. Calendário ------------------------------------------------------------------------------------------------------------------
create table if not exists iara.calendario_eventos (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  tipo text not null check (tipo in ('FERIADO', 'RECESSO', 'INICIO_ANO', 'FIM_ANO', 'FIM_BIMESTRE', 'FORMACAO', 'REUNIAO_PAIS',
                                     'CONSELHO_CLASSE', 'EVENTO', 'PRAZO')),
  inicio date not null,
  fim date not null,
  abrangencia text not null default 'REDE' check (abrangencia in ('REDE', 'UNIDADE')),
  unit_id integer references iara.education_units(id) on delete cascade,
  publico text not null default 'TODOS' check (publico in ('TODOS', 'PROFISSIONAIS', 'FAMILIAS')),
  suspende_aulas boolean not null default false,
  descricao text,
  fonte text not null default 'DEMO',
  criado_por_label text,
  is_demo boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists calendario_inicio_idx on iara.calendario_eventos (inicio);
alter table iara.calendario_eventos enable row level security;

update iara.tenants set settings = settings || jsonb_build_object(
  'ano_letivo_inicio', '2026-02-02', 'ano_letivo_fim', '2026-12-17',
  'freq_minima_ef', 75, 'freq_minima_ei', 60, 'freq_faltas_consecutivas', 5) where id = 1;

create or replace function iara.dia_letivo(p_dia date, p_unit integer default null) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select extract(isodow from p_dia) between 1 and 5
     and p_dia between (iara.setting('ano_letivo_inicio'))::date and (iara.setting('ano_letivo_fim'))::date
     and not exists (select 1 from iara.calendario_eventos e where e.suspende_aulas and p_dia between e.inicio and e.fim
                     and (e.abrangencia = 'REDE' or e.unit_id = p_unit))
$$;

-- 2. Frequência --------------------------------------------------------------------------------------------------------------------
create table if not exists iara.frequencia_registros (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references iara.classes(id) on delete cascade,
  data date not null,
  registrado_por uuid,
  registrado_label text,
  registrado_em timestamptz not null default now(),
  is_demo boolean not null default true,
  unique (class_id, data)
);
create index if not exists frequencia_registros_data_idx on iara.frequencia_registros (data);

create table if not exists iara.frequencia_faltas (
  registro_id uuid not null references iara.frequencia_registros(id) on delete cascade,
  student_id uuid not null references iara.students(id) on delete cascade,
  tipo text not null default 'FALTA' check (tipo in ('FALTA', 'FALTA_JUSTIFICADA')),
  justificativa text,
  atestado boolean not null default false,
  is_demo boolean not null default true,
  primary key (registro_id, student_id)
);
create index if not exists frequencia_faltas_student_idx on iara.frequencia_faltas (student_id);

create table if not exists iara.frequencia_justificativas (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references iara.students(id) on delete cascade,
  data date not null,
  motivo text not null,
  atestado boolean not null default false,
  enviado_por_guardian uuid references iara.guardians(id) on delete set null,
  canal text not null default 'PORTAL',
  situacao text not null default 'ENVIADA' check (situacao in ('ENVIADA', 'ACEITA', 'RECUSADA')),
  avaliada_por_label text,
  avaliada_em timestamptz,
  observacao text,
  created_at timestamptz not null default now(),
  is_demo boolean not null default true
);

create table if not exists iara.frequencia_alertas (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references iara.students(id) on delete cascade,
  class_id uuid references iara.classes(id) on delete set null,
  unit_id integer references iara.education_units(id),
  tipo text not null check (tipo in ('AUSENCIA_CONSECUTIVA', 'FREQUENCIA_BAIXA')),
  faltas_consecutivas integer,
  percentual numeric(5, 1),
  situacao text not null default 'ABERTO' check (situacao in ('ABERTO', 'EM_ACOMPANHAMENTO', 'RESOLVIDO')),
  acao text,
  tratado_por_label text,
  tratado_em timestamptz,
  detectado_em timestamptz not null default now(),
  is_demo boolean not null default true
);
create index if not exists frequencia_alertas_unit_idx on iara.frequencia_alertas (unit_id, situacao);

alter table iara.frequencia_registros enable row level security;
alter table iara.frequencia_faltas enable row level security;
alter table iara.frequencia_justificativas enable row level security;
alter table iara.frequencia_alertas enable row level security;

-- mínimo de frequência pela etapa (LDB): fundamental 75%, educação infantil 60%
create or replace function iara.freq_minima(p_grade_code text) returns numeric
language sql stable security definer set search_path = iara, public
as $$ select case when p_grade_code in ('CRECHE', 'PRE') then coalesce((iara.setting('freq_minima_ei'))::numeric, 60)
                  else coalesce((iara.setting('freq_minima_ef'))::numeric, 75) end $$;

-- resumo de um aluno: dias com chamada na turma dele, faltas, percentual de presença e faltas consecutivas até o último dia
create or replace function iara.frequencia_resumo(p_student uuid, p_de date default null, p_ate date default null) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  with mat as (select e.class_id, coalesce(e.start_date, (iara.setting('ano_letivo_inicio'))::date) desde
               from iara.enrollments e where e.student_id = p_student and e.status = 'ACTIVE' limit 1),
  dias as (select r.data, f.tipo, f.justificativa from mat join iara.frequencia_registros r on r.class_id = mat.class_id and r.data >= mat.desde
           left join iara.frequencia_faltas f on f.registro_id = r.id and f.student_id = p_student
           where (p_de is null or r.data >= p_de) and (p_ate is null or r.data <= p_ate)),
  ult as (select data, tipo, row_number() over (order by data desc) rn from dias),
  consec as (select coalesce(min(rn) filter (where tipo is null), count(*) + 1) - 1 n from ult)
  select jsonb_build_object('dias', count(*), 'faltas', count(tipo), 'justificadas', count(*) filter (where tipo = 'FALTA_JUSTIFICADA'),
         'percentual', case when count(*) > 0 then round(100.0 * (count(*) - count(tipo)) / count(*), 1) end,
         'consecutivas', (select n from consec), 'ultimo_dia', max(data))
  from dias
$$;

-- detecção de alertas (rede ou uma unidade): abre alerta novo só se não houver outro aberto do mesmo tipo
create or replace function iara.frequencia_detectar_alertas(p_unit integer default null) returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_n integer;
  v_consec integer := coalesce((iara.setting('freq_faltas_consecutivas'))::int, 5);
begin
  with base as (
    select e.student_id, e.class_id, e.unit_id, gl.code grade, iara.frequencia_resumo(e.student_id) r
    from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
    where e.status = 'ACTIVE' and (p_unit is null or e.unit_id = p_unit)
      and exists (select 1 from iara.frequencia_faltas f join iara.frequencia_registros r on r.id = f.registro_id
                  where f.student_id = e.student_id and r.data >= current_date - 45)),
  novos as (
    select student_id, class_id, unit_id, 'AUSENCIA_CONSECUTIVA' tipo, (r ->> 'consecutivas')::int consec, (r ->> 'percentual')::numeric pct
    from base where (r ->> 'consecutivas')::int >= v_consec
    union all
    select student_id, class_id, unit_id, 'FREQUENCIA_BAIXA', (r ->> 'consecutivas')::int, (r ->> 'percentual')::numeric
    from base where (r ->> 'dias')::int >= 20 and (r ->> 'percentual')::numeric < iara.freq_minima(grade))
  insert into iara.frequencia_alertas (student_id, class_id, unit_id, tipo, faltas_consecutivas, percentual, is_demo)
  select n.student_id, n.class_id, n.unit_id, n.tipo, n.consec, n.pct,
         coalesce((select is_demo from iara.students where id = n.student_id), true)
  from novos n
  -- um alerta por aluno e tipo: o resolvido só volta a disparar 30 dias depois (o caso já foi tratado pela escola)
  where not exists (select 1 from iara.frequencia_alertas a where a.student_id = n.student_id and a.tipo = n.tipo
                    and (a.situacao <> 'RESOLVIDO' or a.tratado_em > now() - interval '30 days'));
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- 3. Gerador da demonstração -----------------------------------------------------------------------------------------------------
create or replace function iara.demo_gerar_calendario() returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_n integer;
begin
  delete from iara.calendario_eventos where is_demo or fonte = 'LEI';
  insert into iara.calendario_eventos (titulo, tipo, inicio, fim, publico, suspende_aulas, descricao, fonte, is_demo) values
    -- feriados nacionais (datas reais de 2026)
    ('Confraternização Universal', 'FERIADO', '2026-01-01', '2026-01-01', 'TODOS', true, 'Feriado nacional (Lei 662/1949).', 'LEI', true),
    ('Carnaval', 'FERIADO', '2026-02-16', '2026-02-17', 'TODOS', true, 'Ponto facultativo nacional; sem aulas na rede.', 'LEI', true),
    ('Sexta-feira Santa', 'FERIADO', '2026-04-03', '2026-04-03', 'TODOS', true, 'Feriado nacional (Lei 9.093/1995).', 'LEI', true),
    ('Tiradentes', 'FERIADO', '2026-04-21', '2026-04-21', 'TODOS', true, 'Feriado nacional (Lei 662/1949).', 'LEI', true),
    ('Dia do Trabalho', 'FERIADO', '2026-05-01', '2026-05-01', 'TODOS', true, 'Feriado nacional (Lei 662/1949).', 'LEI', true),
    ('Aniversário de Maringá', 'EVENTO', '2026-05-10', '2026-05-10', 'TODOS', false, 'Data cívica do município (domingo em 2026).', 'LEI', true),
    ('Corpus Christi', 'FERIADO', '2026-06-04', '2026-06-04', 'TODOS', true, 'Ponto facultativo nacional; sem aulas na rede.', 'LEI', true),
    ('Independência do Brasil', 'FERIADO', '2026-09-07', '2026-09-07', 'TODOS', true, 'Feriado nacional (Lei 662/1949).', 'LEI', true),
    ('Nossa Senhora Aparecida', 'FERIADO', '2026-10-12', '2026-10-12', 'TODOS', true, 'Feriado nacional (Lei 6.802/1980).', 'LEI', true),
    ('Finados', 'FERIADO', '2026-11-02', '2026-11-02', 'TODOS', true, 'Feriado nacional (Lei 662/1949).', 'LEI', true),
    ('Dia Nacional de Zumbi e da Consciência Negra', 'FERIADO', '2026-11-20', '2026-11-20', 'TODOS', true, 'Feriado nacional (Lei 14.759/2023).', 'LEI', true),
    ('Natal', 'FERIADO', '2026-12-25', '2026-12-25', 'TODOS', true, 'Feriado nacional (Lei 662/1949).', 'LEI', true),
    -- datas escolares de demonstração
    ('Início do ano letivo', 'INICIO_ANO', '2026-02-02', '2026-02-02', 'TODOS', false, 'Primeiro dia de aula na rede.', 'DEMO', true),
    ('Fim do 1º bimestre', 'FIM_BIMESTRE', '2026-04-24', '2026-04-24', 'TODOS', false, null, 'DEMO', true),
    ('Formação pedagógica da rede (sem aula)', 'FORMACAO', '2026-03-27', '2026-03-27', 'TODOS', true, 'Dia de formação continuada dos profissionais.', 'DEMO', true),
    ('Fim do 2º bimestre', 'FIM_BIMESTRE', '2026-07-10', '2026-07-10', 'TODOS', false, 'Alunos com risco de reprovação recebem plano de intervenção.', 'DEMO', true),
    ('Recesso escolar de julho', 'RECESSO', '2026-07-13', '2026-07-24', 'TODOS', true, null, 'DEMO', true),
    ('Formação pedagógica da rede (sem aula)', 'FORMACAO', '2026-09-25', '2026-09-25', 'TODOS', true, 'Dia de formação continuada dos profissionais.', 'DEMO', true),
    ('Fim do 3º bimestre', 'FIM_BIMESTRE', '2026-10-02', '2026-10-02', 'TODOS', false, null, 'DEMO', true),
    ('Prazo de lançamento das notas do 3º bimestre', 'PRAZO', '2026-10-09', '2026-10-09', 'PROFISSIONAIS', false, null, 'DEMO', true),
    ('Semana da Criança', 'EVENTO', '2026-10-13', '2026-10-16', 'TODOS', false, 'Atividades especiais em todas as unidades.', 'DEMO', true),
    ('Dia do Professor', 'EVENTO', '2026-10-15', '2026-10-15', 'TODOS', false, null, 'DEMO', true),
    ('Rematrícula 2027', 'PRAZO', '2026-11-03', '2026-11-20', 'FAMILIAS', false, 'Confirmação da vaga para 2027 pelo portal ou pela IARA.', 'DEMO', true),
    ('Fim do ano letivo', 'FIM_ANO', '2026-12-17', '2026-12-17', 'TODOS', false, null, 'DEMO', true);
  -- reuniões de pais e conselhos de classe por unidade (datas de demonstração)
  insert into iara.calendario_eventos (titulo, tipo, inicio, fim, abrangencia, unit_id, publico, descricao, fonte, is_demo)
  select 'Reunião de pais e responsáveis — ' || b.n || 'º bimestre', 'REUNIAO_PAIS', b.d + (u.id % 4), b.d + (u.id % 4), 'UNIDADE', u.id, 'FAMILIAS',
         'Entrega de pareceres e conversa com os professores.', 'DEMO', true
  from iara.education_units u cross join (values (1, date '2026-04-27'), (2, date '2026-08-03'), (3, date '2026-10-19')) b(n, d)
  where u.status = 'ATIVA';
  insert into iara.calendario_eventos (titulo, tipo, inicio, fim, abrangencia, unit_id, publico, fonte, is_demo)
  select 'Conselho de classe — ' || b.n || 'º bimestre', 'CONSELHO_CLASSE', b.d + (u.id % 3), b.d + (u.id % 3), 'UNIDADE', u.id, 'PROFISSIONAIS', 'DEMO', true
  from iara.education_units u cross join (values (1, date '2026-04-28'), (2, date '2026-07-07'), (3, date '2026-10-06')) b(n, d)
  where u.status = 'ATIVA' and u.unit_type = 'ESCOLA';
  select count(*) into v_n from iara.calendario_eventos where is_demo;
  return v_n;
end $$;

-- propensão a faltar de cada aluno (fixa por aluno): a maioria falta pouco; poucos faltam muito
create or replace function iara.demo_prob_falta(p_student uuid) returns double precision
language sql immutable as $$
  select case when h < 700 then 0.02 + (h % 30) / 1000.0
              when h < 900 then 0.06 + (h % 60) / 1000.0
              when h < 975 then 0.15 + (h % 150) / 1000.0
              else 0.33 end
  from (select abs(('x' || substr(md5(p_student::text), 1, 8))::bit(32)::int) % 1000 h) z
$$;

-- chamadas e faltas de demonstração de um período (gerado mês a mês: cada chamada cabe no tempo máximo de uma consulta)
-- p_limpar = false completa o período sem apagar (rotina diária: preserva as chamadas feitas ao vivo e as sequências de faltas)
drop function if exists iara.demo_gerar_frequencia_periodo(date, date);
create or replace function iara.demo_gerar_frequencia_periodo(p_de date, p_ate date, p_limpar boolean default true) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ini date := (iara.setting('ano_letivo_inicio'))::date;
  v_de date := greatest(p_de, v_ini);
  v_ate date := least(p_ate, (iara.setting('ano_letivo_fim'))::date, current_date - 1);
  v_reg integer;
  v_falt integer;
begin
  if v_de > v_ate then return jsonb_build_object('chamadas', 0, 'faltas', 0); end if;
  perform set_config('iara.skip_audit', 'on', true);
  if p_limpar then
    delete from iara.frequencia_registros where is_demo and data between v_de and v_ate;
  end if;
  insert into iara.frequencia_registros (class_id, data, registrado_label, registrado_em, is_demo)
  select c.id, d::date, 'Chamada da turma (demonstração)', d::date + time '08:05' + make_interval(mins => abs(hashtext(c.id::text)) % 50), true
  from iara.classes c cross join generate_series(v_de, v_ate, interval '1 day') d
  where c.status = 'ATIVA' and iara.dia_letivo(d::date, c.unit_id)
    -- no último dia letivo, algumas turmas ainda sem chamada (pendência de lançamento, como nos relatórios da rede)
    and not (d::date = current_date - 1 and abs(hashtext(c.id::text || d::text)) % 100 < 4)
  on conflict (class_id, data) do nothing;
  get diagnostics v_reg = row_count;
  -- propensão de cada aluno calculada uma vez; sorteio por aluno E por dia (hash de aluno+data), avaliado em cada dia
  -- (um random() que cita só o aluno é aplicado uma vez por aluno: ele faltaria todos os dias ou nenhum)
  create temp table if not exists tmp_prob (student_id uuid, class_id uuid, desde date, p double precision) on commit drop;
  truncate tmp_prob;
  insert into tmp_prob select e.student_id, e.class_id, coalesce(e.start_date, v_ini), iara.demo_prob_falta(e.student_id)
  from iara.enrollments e where e.status = 'ACTIVE';
  insert into iara.frequencia_faltas (registro_id, student_id, tipo, justificativa, atestado, is_demo)
  select r.id, e.student_id,
         case when x.j < 0.12 then 'FALTA_JUSTIFICADA' else 'FALTA' end,
         case when x.j < 0.07 then 'Atestado médico' when x.j < 0.10 then 'Consulta médica' when x.j < 0.12 then 'Doença na família' end,
         x.j < 0.07, true
  from iara.frequencia_registros r
  join tmp_prob e on e.class_id = r.class_id and r.data >= e.desde
  cross join lateral (select (abs(hashtext(e.student_id::text || r.data::text)) % 10000) / 10000.0 s,
                             (abs(hashtext(r.data::text || e.student_id::text || 'j')) % 10000) / 10000.0 j) x
  where r.is_demo and r.data between v_de and v_ate and x.s < e.p
  on conflict do nothing;
  get diagnostics v_falt = row_count;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('de', v_de, 'ate', v_ate, 'chamadas', v_reg, 'faltas', v_falt);
end $$;

-- 1 em cada 100 alunos com uma sequência recente de faltas (ausência prolongada para a escola acompanhar)
create or replace function iara.demo_frequencia_sequencias() returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_n integer;
begin
  insert into iara.frequencia_faltas (registro_id, student_id, tipo, is_demo)
  select r.id, e.student_id, 'FALTA', true
  from iara.enrollments e
  join lateral (select r2.id from iara.frequencia_registros r2 where r2.class_id = e.class_id and r2.is_demo
                order by r2.data desc limit 5 + abs(hashtext(e.student_id::text)) % 5) r on true
  where e.status = 'ACTIVE' and abs(('x' || substr(md5(e.student_id::text), 1, 8))::bit(32)::int) % 100 = 7
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- completa a demonstração até ontem (rotina diária): só os dias que ainda não têm chamada
create or replace function iara.demo_gerar_frequencia(p_ate date default current_date - 1, p_refazer boolean default false) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ultimo date := (select max(data) from iara.frequencia_registros where is_demo);
begin
  if p_refazer or v_ultimo is null then
    raise exception 'Para gerar o ano inteiro use iara.demo_gerar_frequencia_periodo mês a mês (scripts) — cabe no tempo máximo.' using errcode = '22023';
  end if;
  return iara.demo_gerar_frequencia_periodo(v_ultimo + 1, p_ate);
end $$;

create or replace function iara.demo_gerar_alertas_frequencia() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_n integer;
begin
  delete from iara.frequencia_alertas where is_demo;
  v_n := iara.frequencia_detectar_alertas(null);
  -- parte já tratada pela escola (com o registro do que foi feito)
  update iara.frequencia_alertas a set situacao = case when x.h % 10 < 3 then 'EM_ACOMPANHAMENTO' when x.h % 10 < 5 then 'RESOLVIDO' else 'ABERTO' end,
         acao = case when x.h % 10 < 3 then 'Contato com a família por telefone; retorno combinado para a próxima semana.'
                     when x.h % 10 < 5 then 'Família informou tratamento de saúde; atestados entregues na secretaria.' end,
         tratado_por_label = case when x.h % 10 < 5 then 'Secretaria escolar (demonstração)' end,
         tratado_em = case when x.h % 10 < 5 then now() - make_interval(days => x.h % 7) end
  from (select id, abs(hashtext(id::text)) h from iara.frequencia_alertas where is_demo) x where a.id = x.id;
  return jsonb_build_object('alertas', v_n);
end $$;

-- 4. Consultas e registros -------------------------------------------------------------------------------------------------------
-- quem pode ver/lançar a turma: gestão com escopo na unidade, ou o professor da turma
create or replace function iara.turma_acesso(p_class uuid, p_perm text) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select exists (select 1 from iara.classes c where c.id = p_class
    and ((iara.has_perm(p_perm) and iara.my_role() <> 'PROFESSOR' and iara.can_access_unit(c.unit_id))
         or (iara.has_perm(p_perm) and c.id = any (iara.minhas_turmas()))))
$$;

create or replace function api.frequencia_turma(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  c iara.classes;
  v_dia date := coalesce(nullif(p ->> 'data', '')::date, current_date);
  reg iara.frequencia_registros;
begin
  select * into c from iara.classes where id = (p ->> 'class_id')::uuid;
  if c.id is null or not iara.turma_acesso(c.id, 'frequencia.read') then
    raise exception 'Turma não encontrada ou fora do seu escopo.' using errcode = 'P0002';
  end if;
  select * into reg from iara.frequencia_registros where class_id = c.id and data = v_dia;
  return jsonb_build_object(
    'turma', jsonb_build_object('id', c.id, 'nome', c.class_name, 'turno', c.shift, 'unidade', (select name from iara.education_units where id = c.unit_id)),
    'data', v_dia, 'dia_letivo', iara.dia_letivo(v_dia, c.unit_id), 'pode_lancar', iara.turma_acesso(c.id, 'frequencia.write') and v_dia <= current_date,
    'registrado', reg.id is not null, 'registrado_por', reg.registrado_label, 'registrado_em', reg.registrado_em,
    'evento', (select jsonb_build_object('titulo', e.titulo, 'tipo', e.tipo) from iara.calendario_eventos e
               where e.suspende_aulas and v_dia between e.inicio and e.fim and (e.abrangencia = 'REDE' or e.unit_id = c.unit_id) limit 1),
    'alunos', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.full_name, 'social', s.social_name,
                 'falta', f.tipo, 'justificativa', f.justificativa, 'aee', s.aee_status,
                 'percentual', (iara.frequencia_resumo(s.id) ->> 'percentual')::numeric) order by s.full_name), '[]')
               from iara.enrollments e join iara.students s on s.id = e.student_id
               left join iara.frequencia_faltas f on f.registro_id = reg.id and f.student_id = s.id
               where e.class_id = c.id and e.status = 'ACTIVE'));
end $$;

create or replace function api.frequencia_lancar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.classes;
  v_dia date := coalesce(nullif(p ->> 'data', '')::date, current_date);
  v_reg uuid;
  v_faltas uuid[];
begin
  select * into c from iara.classes where id = (p ->> 'class_id')::uuid;
  if c.id is null or not iara.turma_acesso(c.id, 'frequencia.write') then
    raise exception 'Você não pode lançar a chamada desta turma.' using errcode = '42501';
  end if;
  if v_dia > current_date then raise exception 'Não dá para lançar chamada de dia futuro.' using errcode = '22023'; end if;
  if not iara.dia_letivo(v_dia, c.unit_id) then raise exception 'Este dia não é letivo.' using errcode = '22023'; end if;
  select coalesce(array_agg(x::uuid), '{}') into v_faltas from jsonb_array_elements_text(coalesce(p -> 'faltas', '[]'::jsonb)) x;
  if exists (select 1 from unnest(v_faltas) f where not exists (select 1 from iara.enrollments e where e.class_id = c.id and e.student_id = f and e.status = 'ACTIVE')) then
    raise exception 'Há aluno que não pertence a esta turma.' using errcode = '22023';
  end if;
  insert into iara.frequencia_registros (class_id, data, registrado_por, registrado_label, is_demo)
  values (c.id, v_dia, iara.current_user_id(), iara.my_label(), false)
  on conflict (class_id, data) do update set registrado_por = excluded.registrado_por, registrado_label = excluded.registrado_label, registrado_em = now()
  returning id into v_reg;
  -- falta justificada (atestado) não vira falta simples ao relançar
  delete from iara.frequencia_faltas where registro_id = v_reg and student_id <> all (v_faltas);
  insert into iara.frequencia_faltas (registro_id, student_id, tipo, is_demo)
  select v_reg, f, 'FALTA', false from unnest(v_faltas) f on conflict do nothing;
  perform iara.audit_event('FREQUENCIA_LANCADA', 'class', c.id::text, c.unit_id,
    format('Chamada de %s lançada (%s falta(s)).', to_char(v_dia, 'DD/MM/YYYY'), cardinality(v_faltas)));
  perform iara.frequencia_detectar_alertas(c.unit_id);
  return api.frequencia_turma(jsonb_build_object('class_id', c.id, 'data', v_dia));
end $$;

create or replace function api.frequencia_painel(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_ult date := (select max(r.data) from iara.frequencia_registros r where r.data < current_date);
begin
  perform iara.require_perm('frequencia.read');
  if iara.my_role() = 'PROFESSOR' then raise exception 'Use a chamada das suas turmas.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'unidade', (select jsonb_build_object('id', id, 'name', name) from iara.education_units where id = v_unit),
    'ultimo_dia', v_ult,
    'presenca_30d', (select round(100.0 - 100.0 * count(f.student_id)::numeric / nullif(sum(t.n), 0), 1) from (
        select r.id, (select count(*) from iara.enrollments e where e.class_id = r.class_id and e.status = 'ACTIVE') n
        from iara.frequencia_registros r join iara.classes c on c.id = r.class_id
        where r.data >= current_date - 30 and (v_unit is null or c.unit_id = v_unit)) t
        left join iara.frequencia_faltas f on f.registro_id = t.id),
    'turmas_sem_chamada', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'turma', c.class_name, 'unidade', u.short_name, 'data', v_ult)
                             order by u.short_name, c.class_name), '[]')
                           from iara.classes c join iara.education_units u on u.id = c.unit_id
                           where c.status = 'ATIVA' and (v_unit is null or c.unit_id = v_unit) and iara.dia_letivo(v_ult, c.unit_id)
                             and not exists (select 1 from iara.frequencia_registros r where r.class_id = c.id and r.data = v_ult)),
    'alertas', (select coalesce(jsonb_object_agg(situacao, n), '{}') from (select situacao, count(*) n from iara.frequencia_alertas a
                where (v_unit is null or a.unit_id = v_unit) group by 1) z),
    'justificativas_pendentes', (select count(*) from iara.frequencia_justificativas j join iara.enrollments e on e.student_id = j.student_id and e.status = 'ACTIVE'
                                 where j.situacao = 'ENVIADA' and (v_unit is null or e.unit_id = v_unit)),
    'por_unidade', case when v_unit is null then (select coalesce(jsonb_agg(z order by z.presenca), '[]') from (
        select u.id, u.short_name nome, round(100.0 - 100.0 * count(f.student_id)::numeric / nullif(sum(t.n), 0), 1) presenca,
               (select count(*) from iara.frequencia_alertas a where a.unit_id = u.id and a.situacao <> 'RESOLVIDO') alertas
        from (select r.id, c.unit_id, (select count(*) from iara.enrollments e where e.class_id = r.class_id and e.status = 'ACTIVE') n
              from iara.frequencia_registros r join iara.classes c on c.id = r.class_id where r.data >= current_date - 30) t
        join iara.education_units u on u.id = t.unit_id
        left join iara.frequencia_faltas f on f.registro_id = t.id
        group by u.id, u.short_name) z) end,
    'por_turma', case when v_unit is not null then (select coalesce(jsonb_agg(z order by z.turma), '[]') from (
        select c.id, c.class_name turma, c.shift turno, round(100.0 - 100.0 * count(f.student_id)::numeric / nullif(sum(t.n), 0), 1) presenca
        from (select r.id, r.class_id, (select count(*) from iara.enrollments e where e.class_id = r.class_id and e.status = 'ACTIVE') n
              from iara.frequencia_registros r where r.data >= current_date - 30) t
        join iara.classes c on c.id = t.class_id and c.unit_id = v_unit
        left join iara.frequencia_faltas f on f.registro_id = t.id
        group by c.id, c.class_name, c.shift) z) end);
end $$;

create or replace function api.frequencia_alertas(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
begin
  perform iara.require_perm('frequencia.read');
  if iara.my_role() = 'PROFESSOR' then raise exception 'Sem acesso aos alertas da unidade.' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'student_id', s.id, 'aluno', s.full_name, 'turma', c.class_name,
            'unidade', u.short_name, 'tipo', a.tipo, 'consecutivas', a.faltas_consecutivas, 'percentual', a.percentual, 'situacao', a.situacao,
            'acao', a.acao, 'tratado_por', a.tratado_por_label, 'detectado_em', a.detectado_em) order by (a.situacao = 'RESOLVIDO'), a.detectado_em desc), '[]')
          from (select * from iara.frequencia_alertas a where (v_unit is null or a.unit_id = v_unit)
                  and (nullif(p ->> 'situacao', '') is null or a.situacao = p ->> 'situacao')
                order by (a.situacao = 'RESOLVIDO'), a.detectado_em desc limit 300) a
          join iara.students s on s.id = a.student_id left join iara.classes c on c.id = a.class_id
          left join iara.education_units u on u.id = a.unit_id);
end $$;

create or replace function api.frequencia_alerta_tratar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  a iara.frequencia_alertas;
begin
  perform iara.require_perm('frequencia.acompanhar');
  select * into a from iara.frequencia_alertas where id = (p ->> 'id')::uuid;
  if a.id is null or not iara.can_access_unit(a.unit_id) then raise exception 'Alerta não encontrado.' using errcode = 'P0002'; end if;
  if coalesce(p ->> 'situacao', '') not in ('EM_ACOMPANHAMENTO', 'RESOLVIDO') then raise exception 'Situação inválida.' using errcode = '22023'; end if;
  if length(btrim(coalesce(p ->> 'acao', ''))) < 10 then raise exception 'Descreva o que foi feito (pelo menos 10 caracteres).' using errcode = '22023'; end if;
  update iara.frequencia_alertas set situacao = p ->> 'situacao', acao = btrim(p ->> 'acao'), tratado_por_label = iara.my_label(), tratado_em = now()
  where id = a.id;
  perform iara.audit_event('FREQUENCIA_ALERTA', 'student', a.student_id::text, a.unit_id, format('Alerta de frequência %s: %s.', lower(p ->> 'situacao'), left(btrim(p ->> 'acao'), 120)));
  return jsonb_build_object('ok', true);
end $$;

create or replace function api.frequencia_aluno(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
begin
  if not ((iara.has_perm('frequencia.read') and iara.my_role() <> 'PROFESSOR' and iara.can_access_student(v_student))
          or v_student in (select iara.my_student_ids())
          or exists (select 1 from iara.enrollments e where e.student_id = v_student and e.status = 'ACTIVE' and e.class_id = any (iara.minhas_turmas()))) then
    raise exception 'Aluno fora do seu escopo.' using errcode = '42501';
  end if;
  return iara.frequencia_resumo(v_student) || jsonb_build_object(
    'minimo', (select iara.freq_minima(gl.code) from iara.enrollments e join iara.classes c on c.id = e.class_id
               join iara.grade_levels gl on gl.id = c.grade_level_id where e.student_id = v_student and e.status = 'ACTIVE' limit 1),
    'por_mes', (select coalesce(jsonb_agg(z order by z.mes), '[]') from (
        select to_char(r.data, 'YYYY-MM') mes, count(*) dias, count(f.student_id) faltas
        from iara.enrollments e join iara.frequencia_registros r on r.class_id = e.class_id
        left join iara.frequencia_faltas f on f.registro_id = r.id and f.student_id = v_student
        where e.student_id = v_student and e.status = 'ACTIVE' group by 1) z),
    'faltas_recentes', (select coalesce(jsonb_agg(jsonb_build_object('data', r.data, 'tipo', f.tipo, 'justificativa', f.justificativa) order by r.data desc), '[]')
        from (select f.* from iara.frequencia_faltas f join iara.frequencia_registros r on r.id = f.registro_id
              where f.student_id = v_student order by r.data desc limit 15) f join iara.frequencia_registros r on r.id = f.registro_id),
    'alertas', (select coalesce(jsonb_agg(jsonb_build_object('tipo', a.tipo, 'situacao', a.situacao, 'acao', a.acao)), '[]')
                from iara.frequencia_alertas a where a.student_id = v_student and a.situacao <> 'RESOLVIDO'),
    'justificativas', (select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'data', j.data, 'motivo', j.motivo, 'situacao', j.situacao) order by j.data desc), '[]')
                       from iara.frequencia_justificativas j where j.student_id = v_student));
end $$;

-- família: frequência de todos os filhos (cada item identifica a criança) — portal e IARA
create or replace function api.familia_frequencia(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('student_id', s.id, 'nome', s.full_name, 'primeiro_nome', split_part(s.full_name, ' ', 1),
            'turma', c.class_name, 'unidade', u.short_name) || iara.frequencia_resumo(s.id)
            || jsonb_build_object('minimo', iara.freq_minima(gl.code),
                 'faltas_recentes', (select coalesce(jsonb_agg(jsonb_build_object('data', r.data, 'tipo', f.tipo, 'justificativa', f.justificativa) order by r.data desc), '[]')
                    from (select f.* from iara.frequencia_faltas f join iara.frequencia_registros r on r.id = f.registro_id
                          where f.student_id = s.id order by r.data desc limit 5) f join iara.frequencia_registros r on r.id = f.registro_id),
                 'justificativas', (select coalesce(jsonb_agg(jsonb_build_object('data', j.data, 'situacao', j.situacao) order by j.data desc), '[]')
                    from iara.frequencia_justificativas j where j.student_id = s.id))
            order by s.full_name), '[]')
          from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
          join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
          join iara.education_units u on u.id = e.unit_id
          where s.id in (select iara.my_student_ids()));
end $$;

create or replace function api.familia_justificar_falta(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_dia date := (p ->> 'data')::date;
  v_id uuid;
begin
  if iara.my_guardian() is null or not (v_student in (select iara.my_student_ids())) then
    raise exception 'Criança não vinculada a você.' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p ->> 'motivo', ''))) < 5 then raise exception 'Conte o motivo da falta.' using errcode = '22023'; end if;
  if not exists (select 1 from iara.frequencia_faltas f join iara.frequencia_registros r on r.id = f.registro_id
                 where f.student_id = v_student and r.data = v_dia) then
    raise exception 'Não há falta registrada nesse dia.' using errcode = '22023';
  end if;
  if exists (select 1 from iara.frequencia_justificativas where student_id = v_student and data = v_dia and situacao <> 'RECUSADA') then
    raise exception 'Essa falta já tem justificativa enviada.' using errcode = '22023';
  end if;
  insert into iara.frequencia_justificativas (student_id, data, motivo, atestado, enviado_por_guardian, canal, is_demo)
  values (v_student, v_dia, left(btrim(p ->> 'motivo'), 300), coalesce((p ->> 'atestado')::boolean, false), iara.my_guardian(),
          coalesce(nullif(p ->> 'canal', ''), 'PORTAL'), false)
  returning id into v_id;
  perform iara.audit_event('FALTA_JUSTIFICADA_ENVIADA', 'student', v_student::text, null, format('Justificativa de falta de %s enviada pela família.', to_char(v_dia, 'DD/MM/YYYY')));
  return jsonb_build_object('ok', true, 'id', v_id, 'mensagem', 'Justificativa enviada. A secretaria da escola confere e responde aqui.');
end $$;

create or replace function api.frequencia_justificativas(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
begin
  perform iara.require_perm('frequencia.acompanhar');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'aluno', s.full_name, 'turma', c.class_name, 'unidade', u.short_name,
            'data', j.data, 'motivo', j.motivo, 'atestado', j.atestado, 'canal', j.canal, 'situacao', j.situacao, 'enviada_em', j.created_at)
            order by j.created_at desc), '[]')
          from iara.frequencia_justificativas j join iara.students s on s.id = j.student_id
          join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' join iara.classes c on c.id = e.class_id
          join iara.education_units u on u.id = e.unit_id
          where (v_unit is null or e.unit_id = v_unit) and (coalesce(p ->> 'todas', 'false')::boolean or j.situacao = 'ENVIADA'));
end $$;

create or replace function api.frequencia_justificativa_avaliar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  j iara.frequencia_justificativas;
  v_unit integer;
begin
  perform iara.require_perm('frequencia.acompanhar');
  select * into j from iara.frequencia_justificativas where id = (p ->> 'id')::uuid;
  select unit_id into v_unit from iara.enrollments where student_id = j.student_id and status = 'ACTIVE' limit 1;
  if j.id is null or not iara.can_access_unit(v_unit) then raise exception 'Justificativa não encontrada.' using errcode = 'P0002'; end if;
  update iara.frequencia_justificativas set situacao = case when (p ->> 'aceitar')::boolean then 'ACEITA' else 'RECUSADA' end,
         avaliada_por_label = iara.my_label(), avaliada_em = now(), observacao = nullif(btrim(coalesce(p ->> 'observacao', '')), '')
  where id = j.id;
  if (p ->> 'aceitar')::boolean then
    update iara.frequencia_faltas f set tipo = 'FALTA_JUSTIFICADA', justificativa = j.motivo, atestado = j.atestado
    from iara.frequencia_registros r where r.id = f.registro_id and f.student_id = j.student_id and r.data = j.data;
  end if;
  perform iara.audit_event('FALTA_JUSTIFICATIVA_AVALIADA', 'student', j.student_id::text, v_unit,
    format('Justificativa de %s %s.', to_char(j.data, 'DD/MM/YYYY'), case when (p ->> 'aceitar')::boolean then 'aceita' else 'recusada' end));
  return jsonb_build_object('ok', true);
end $$;

-- calendário: o que vale para quem consulta (rede + unidades do perfil ou dos filhos)
create or replace function api.calendario(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_de date := coalesce(nullif(p ->> 'de', '')::date, date_trunc('month', current_date)::date);
  v_ate date := coalesce(nullif(p ->> 'ate', '')::date, (date_trunc('month', current_date) + interval '3 months')::date);
  v_units integer[];
  v_familia boolean := iara.my_guardian() is not null;
begin
  v_units := case when v_familia then (select coalesce(array_agg(distinct e.unit_id), '{}') from iara.enrollments e
                                        where e.student_id in (select iara.my_student_ids()) and e.status = 'ACTIVE')
                  when iara.my_scope() = 'UNIT' then array[iara.my_unit()]
                  when nullif(p ->> 'unit_id', '') is not null then array[(p ->> 'unit_id')::int]
                  else '{}' end;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'titulo', e.titulo, 'tipo', e.tipo, 'inicio', e.inicio, 'fim', e.fim,
            'unidade', u.short_name, 'publico', e.publico, 'sem_aula', e.suspende_aulas, 'descricao', e.descricao, 'fonte', e.fonte)
            order by e.inicio, e.titulo), '[]')
          from iara.calendario_eventos e left join iara.education_units u on u.id = e.unit_id
          where e.fim >= v_de and e.inicio <= v_ate
            and (e.abrangencia = 'REDE' or e.unit_id = any (v_units))
            and (e.publico = 'TODOS' or (v_familia and e.publico = 'FAMILIAS')
                 or (not v_familia and iara.current_user_id() is not null and e.publico = 'PROFISSIONAIS')
                 or (not v_familia and iara.current_user_id() is not null and e.publico = 'FAMILIAS')));
end $$;

drop function if exists iara.demo_gerar_frequencia(date);
revoke all on function iara.demo_gerar_calendario(), iara.demo_gerar_frequencia(date, boolean), iara.demo_gerar_alertas_frequencia(),
  iara.demo_gerar_frequencia_periodo(date, date, boolean), iara.demo_frequencia_sequencias(),
  iara.frequencia_detectar_alertas(integer) from public;
grant execute on function api.calendario(jsonb) to anon;

commit;
