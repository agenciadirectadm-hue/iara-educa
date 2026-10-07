-- IARA Educa — 067 · Peso e medidas (antropometria) (Sprint 4)
-- A escola mede peso e altura (duas vezes por ano, proposta) e o sistema calcula o IMC e acompanha a evolução de cada criança.
-- Classificação do estado nutricional pelo IMC para a idade (OMS 2006 para 0–5 anos e OMS 2007 para 5–19 anos), com os pontos de corte
-- usados pelo SISVAN/Ministério da Saúde. A tabela de referência (L, M e S por sexo e idade em meses) é IMPORTADA pela nutricionista
-- responsável técnica a partir da publicação oficial da OMS — o sistema não traz valores de referência digitados à mão. Sem a tabela,
-- mostra medidas, IMC e evolução, e a classificação fica “aguardando a referência oficial”. Item 28 (nutrição) a definir com a SEDUC.
begin;

insert into iara.permissions (code, description, is_sensitive) values
  ('antropometria.write', 'Registrar peso e altura dos alunos', true),
  ('antropometria.read', 'Consultar peso, altura e estado nutricional dos alunos', true)
on conflict (code) do update set description = excluded.description, is_sensitive = excluded.is_sensitive;
insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('NUTRICAO', 'antropometria.read'), ('NUTRICAO', 'antropometria.write'),
  ('DIRETOR_UNIDADE', 'antropometria.read'), ('DIRETOR_UNIDADE', 'antropometria.write'),
  ('SECRETARIA_ESCOLAR', 'antropometria.read'), ('SECRETARIA_ESCOLAR', 'antropometria.write'),
  ('PROFESSOR', 'antropometria.read'), ('PROFESSOR', 'antropometria.write'),
  ('SECRETARIO', 'antropometria.read'), ('SUPERINTENDENCIA', 'antropometria.read'), ('GERENCIA_EI', 'antropometria.read')
) v(r, p)
on conflict do nothing;

create table if not exists iara.antropometria (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references iara.students(id) on delete cascade,
  unit_id integer,
  class_id uuid,
  data date not null,
  peso_kg numeric(5, 2) not null check (peso_kg between 2 and 150),
  altura_cm numeric(5, 1) not null check (altura_cm between 40 and 200),
  imc numeric(5, 2) not null,
  idade_meses smallint not null,
  zscore numeric(4, 2),
  classificacao text,
  conferir boolean not null default false,
  observacao text,
  medido_por_label text,
  created_at timestamptz not null default now(),
  is_demo boolean not null default false,
  unique (student_id, data)
);
create index if not exists antropometria_unit_idx on iara.antropometria (unit_id, data);
create table if not exists iara.referencia_imc (
  sexo char(1) not null check (sexo in ('M', 'F')),
  idade_meses smallint not null check (idade_meses between 0 and 228),
  l numeric not null,
  m numeric not null check (m > 0),
  s numeric not null check (s > 0),
  fonte text not null,
  importado_por_label text,
  importado_em timestamptz not null default now(),
  primary key (sexo, idade_meses)
);
alter table iara.antropometria enable row level security;
alter table iara.referencia_imc enable row level security;

-- escore z pelo método LMS (OMS) e classificação do SISVAN; nulo sem a tabela de referência importada
create or replace function iara.imc_classificar(p_sexo text, p_meses integer, p_imc numeric) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  with r as (select * from iara.referencia_imc where sexo = p_sexo and idade_meses = p_meses),
       z as (select case when r.l = 0 then ln(p_imc / r.m) / r.s else (power(p_imc / r.m, r.l) - 1) / (r.l * r.s) end z from r)
  select case when z.z is null then null else jsonb_build_object('z', round(z.z, 2), 'classe',
    case when p_meses < 60 then case when z.z < -3 then 'MAGREZA_ACENTUADA' when z.z < -2 then 'MAGREZA' when z.z <= 1 then 'EUTROFIA' when z.z <= 2 then 'RISCO_SOBREPESO'
                                     when z.z <= 3 then 'SOBREPESO' else 'OBESIDADE' end
         else case when z.z < -3 then 'MAGREZA_ACENTUADA' when z.z < -2 then 'MAGREZA' when z.z <= 1 then 'EUTROFIA' when z.z <= 2 then 'SOBREPESO'
                   when z.z <= 3 then 'OBESIDADE' else 'OBESIDADE_GRAVE' end end) end
  from z
$$;

create or replace function iara.antropo_json(a iara.antropometria) returns jsonb
language sql stable as $$
  select jsonb_build_object('id', a.id, 'data', a.data, 'peso', a.peso_kg, 'altura', a.altura_cm, 'imc', a.imc, 'idade_meses', a.idade_meses,
    'zscore', a.zscore, 'classificacao', a.classificacao, 'conferir', a.conferir, 'observacao', a.observacao, 'por', a.medido_por_label, 'is_demo', a.is_demo)
$$;

create or replace function iara.antropo_acesso(p_class uuid, p_escrever boolean) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select iara.has_perm(case when p_escrever then 'antropometria.write' else 'antropometria.read' end)
     and ((iara.my_role() = 'PROFESSOR' and p_class = any (iara.minhas_turmas()))
          or (iara.my_role() <> 'PROFESSOR' and exists (select 1 from iara.classes c where c.id = p_class and iara.can_access_unit(c.unit_id))
              and (not p_escrever or iara.my_role() = 'NUTRICAO' or exists (select 1 from iara.classes c where c.id = p_class and c.unit_id = iara.my_unit()))))
$$;

create or replace function api.antropometria_turma(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_class uuid := (p ->> 'class_id')::uuid;
begin
  if not iara.antropo_acesso(v_class, false) then raise exception 'Turma fora do seu escopo.' using errcode = '42501'; end if;
  return jsonb_build_object('class_id', v_class, 'pode_lancar', iara.antropo_acesso(v_class, true),
    'turma', (select c.class_name || ' · ' || u.short_name from iara.classes c join iara.education_units u on u.id = c.unit_id where c.id = v_class),
    'referencia', exists (select 1 from iara.referencia_imc),
    'alunos', (select coalesce(jsonb_agg(jsonb_build_object('student_id', s.id, 'nome', s.full_name, 'sexo', s.gender, 'nascimento', s.birth_date,
                 'ultima', (select iara.antropo_json(a) from iara.antropometria a where a.student_id = s.id order by a.data desc limit 1),
                 'anterior', (select iara.antropo_json(a) from iara.antropometria a where a.student_id = s.id order by a.data desc offset 1 limit 1)) order by s.full_name), '[]')
               from iara.enrollments e join iara.students s on s.id = e.student_id where e.class_id = v_class and e.status = 'ACTIVE'));
end $$;

-- lançamento da turma: confere valores fora do esperado (altura que diminui ou peso que muda mais de 20%) antes de gravar
create or replace function api.antropometria_lancar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_class uuid := (p ->> 'class_id')::uuid;
  v_data date := coalesce(nullif(p ->> 'data', '')::date, iara.hoje_local());
  x jsonb;
  s iara.students;
  ant iara.antropometria;
  v_peso numeric;
  v_alt numeric;
  v_imc numeric;
  v_meses integer;
  v_cls jsonb;
  v_alertas jsonb := '[]';
  v_conf boolean := coalesce((p ->> 'confirmar')::boolean, false);
  v_n integer := 0;
  v_unit integer;
  v_flag boolean;
begin
  if not iara.antropo_acesso(v_class, true) then raise exception 'Sem permissão para medir esta turma.' using errcode = '42501'; end if;
  if v_data > iara.hoje_local() or v_data < iara.hoje_local() - 60 then raise exception 'Data da medição inválida (até 60 dias atrás).' using errcode = '22023'; end if;
  select unit_id into v_unit from iara.classes where id = v_class;
  for x in select * from jsonb_array_elements(coalesce(p -> 'medidas', '[]')) loop
    v_peso := nullif(replace(x ->> 'peso', ',', '.'), '')::numeric;
    v_alt := nullif(replace(x ->> 'altura', ',', '.'), '')::numeric;
    continue when v_peso is null and v_alt is null;
    if v_peso is null or v_alt is null then raise exception 'Informe peso e altura juntos.' using errcode = '22023'; end if;
    select st.* into s from iara.students st join iara.enrollments e on e.student_id = st.id and e.class_id = v_class and e.status = 'ACTIVE' where st.id = (x ->> 'student_id')::uuid;
    if s.id is null then raise exception 'Aluno fora da turma.' using errcode = '22023'; end if;
    if v_peso not between 2 and 150 or v_alt not between 40 and 200 then raise exception 'Valores fora da faixa possível para %.', split_part(s.full_name, ' ', 1) using errcode = '22023'; end if;
    select * into ant from iara.antropometria where student_id = s.id and data < v_data order by data desc limit 1;
    v_flag := ant.id is not null and (v_alt < ant.altura_cm - 1.5 or abs(v_peso - ant.peso_kg) > ant.peso_kg * 0.2);
    if v_flag and not v_conf then
      v_alertas := v_alertas || jsonb_build_object('student_id', s.id, 'nome', s.full_name, 'anterior', iara.antropo_json(ant),
        'motivo', case when v_alt < ant.altura_cm - 1.5 then 'altura menor que a medida anterior' else 'peso mudou mais de 20% desde a medida anterior' end);
      continue;
    end if;
    v_imc := round(v_peso / power(v_alt / 100.0, 2), 2);
    v_meses := (extract(year from age(v_data, s.birth_date)) * 12 + extract(month from age(v_data, s.birth_date)))::int;
    v_cls := iara.imc_classificar(s.gender, v_meses, v_imc);
    insert into iara.antropometria (student_id, unit_id, class_id, data, peso_kg, altura_cm, imc, idade_meses, zscore, classificacao, conferir, observacao, medido_por_label)
    values (s.id, v_unit, v_class, v_data, v_peso, v_alt, v_imc, v_meses, (v_cls ->> 'z')::numeric, v_cls ->> 'classe', v_flag, nullif(btrim(coalesce(x ->> 'observacao', '')), ''), iara.my_label())
    on conflict (student_id, data) do update set peso_kg = excluded.peso_kg, altura_cm = excluded.altura_cm, imc = excluded.imc, zscore = excluded.zscore,
       classificacao = excluded.classificacao, conferir = excluded.conferir, observacao = excluded.observacao, medido_por_label = excluded.medido_por_label;
    v_n := v_n + 1;
  end loop;
  if v_n > 0 then perform iara.audit_event('ANTROPOMETRIA', 'class', v_class::text, v_unit, format('Peso e altura de %s aluno(s) registrados.', v_n)); end if;
  return jsonb_build_object('gravados', v_n, 'conferir', v_alertas, 'turma', api.antropometria_turma(jsonb_build_object('class_id', v_class)));
end $$;

-- ficha do aluno e família: a evolução; a família vê as medidas e uma leitura sem rótulo (acompanhamento pela nutrição quando preciso)
create or replace function api.antropometria_aluno(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_fam boolean := iara.my_guardian() is not null;
  v_class uuid := (select class_id from iara.enrollments where student_id = v_student and status = 'ACTIVE' limit 1);
begin
  if not ((v_fam and v_student in (select iara.my_student_ids())) or (not v_fam and iara.antropo_acesso(v_class, false))) then
    raise exception 'Aluno fora do seu escopo.' using errcode = '42501';
  end if;
  return jsonb_build_object('student_id', v_student, 'primeiro_nome', (select split_part(full_name, ' ', 1) from iara.students where id = v_student),
    'medidas', (select coalesce(jsonb_agg(case when v_fam then iara.antropo_json(a) - 'zscore' - 'classificacao' - 'por' - 'conferir'
                                                   || jsonb_build_object('leitura', case when a.classificacao is null then null when a.classificacao = 'EUTROFIA' then 'Dentro do esperado para a idade'
                                                                                         else 'A equipe de nutrição da rede acompanha; converse com a escola ou com a UBS' end)
                                               else iara.antropo_json(a) end order by a.data), '[]')
                from iara.antropometria a where a.student_id = v_student),
    'referencia', exists (select 1 from iara.referencia_imc));
end $$;

create or replace function api.familia_antropometria(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(api.antropometria_aluno(jsonb_build_object('student_id', s.id)) order by s.full_name), '[]')
          from iara.students s where s.id in (select iara.my_student_ids()) and exists (select 1 from iara.enrollments e where e.student_id = s.id and e.status = 'ACTIVE'));
end $$;

-- painel da nutrição e da unidade: cobertura do semestre, distribuição (com a referência), alertas e medidas a conferir
create or replace function api.antropometria_painel(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_sem date := case when extract(month from iara.hoje_local()) >= 7 then make_date(extract(year from iara.hoje_local())::int, 7, 1)
                     else make_date(extract(year from iara.hoje_local())::int, 1, 1) end;
begin
  perform iara.require_perm('antropometria.read');
  if iara.my_role() = 'PROFESSOR' then raise exception 'Use a turma para ver as medidas.' using errcode = '42501'; end if;
  if v_unit is not null and not iara.can_access_unit(v_unit) then raise exception 'Unidade fora do seu escopo.' using errcode = '42501'; end if;
  return (with al as (select e.student_id, e.unit_id, e.class_id from iara.enrollments e where e.status = 'ACTIVE' and (v_unit is null or e.unit_id = v_unit)),
               ult as (select distinct on (a.student_id) a.* from iara.antropometria a join al on al.student_id = a.student_id order by a.student_id, a.data desc)
    select jsonb_build_object('unit_id', v_unit, 'referencia', exists (select 1 from iara.referencia_imc),
      'referencia_fonte', (select min(fonte) from iara.referencia_imc), 'pode_importar', iara.has_perm('nutricao.manage'),
      'alunos', (select count(*) from al), 'medidos_semestre', (select count(*) from ult where data >= v_sem), 'semestre_desde', v_sem,
      'conferir', (select count(*) from ult where conferir),
      'distribuicao', (select coalesce(jsonb_object_agg(classificacao, n), '{}') from (select classificacao, count(*) n from ult where classificacao is not null group by 1) z),
      'unidades', case when v_unit is null then (select coalesce(jsonb_agg(jsonb_build_object('unit_id', u.id, 'unidade', u.short_name, 'alunos', z.al, 'medidos', z.med,
                       'cobertura', round(100.0 * z.med / nullif(z.al, 0)), 'alerta', z.alerta) order by round(100.0 * z.med / nullif(z.al, 0)) nulls first), '[]')
                     from (select al.unit_id, count(*) al, count(ult.id) filter (where ult.data >= v_sem) med,
                                  count(ult.id) filter (where ult.classificacao in ('MAGREZA_ACENTUADA', 'MAGREZA', 'OBESIDADE', 'OBESIDADE_GRAVE')) alerta
                           from al left join ult on ult.student_id = al.student_id group by 1) z join iara.education_units u on u.id = z.unit_id) end,
      'turmas', case when v_unit is not null then (select coalesce(jsonb_agg(jsonb_build_object('class_id', c.id, 'turma', c.class_name, 'alunos', z.al, 'medidos', z.med) order by c.class_name), '[]')
                     from (select al.class_id, count(*) al, count(ult.id) filter (where ult.data >= v_sem) med from al left join ult on ult.student_id = al.student_id group by 1) z
                     join iara.classes c on c.id = z.class_id) end,
      'acompanhar', (select coalesce(jsonb_agg(jsonb_build_object('student_id', s.id, 'nome', s.full_name, 'unidade', u.short_name, 'imc', ult.imc, 'classificacao', ult.classificacao,
                        'conferir', ult.conferir, 'data', ult.data) order by ult.conferir desc, ult.zscore), '[]')
                     from ult join iara.students s on s.id = ult.student_id join iara.education_units u on u.id = ult.unit_id
                     where ult.conferir or ult.classificacao in ('MAGREZA_ACENTUADA', 'MAGREZA', 'OBESIDADE_GRAVE') limit 200)));
end $$;

-- importação da tabela oficial (sexo;idade_meses;L;M;S), reclassificando as medidas
create or replace function api.referencia_imc_importar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  l text;
  c text[];
  n integer := 0;
  v_err jsonb := '[]';
  i integer := 0;
begin
  perform iara.require_perm('nutricao.manage');
  if length(btrim(coalesce(p ->> 'fonte', ''))) < 10 then raise exception 'Informe a fonte oficial (ex.: OMS 2007, tabela IMC para idade, publicação e data).' using errcode = '22023'; end if;
  foreach l in array regexp_split_to_array(replace(coalesce(p ->> 'texto', ''), E'\r', ''), E'\n') loop
    i := i + 1;
    continue when btrim(l) = '' or l ~* '^\s*(sexo|sex)';
    c := regexp_split_to_array(btrim(l), '\s*[;\t]\s*');
    if array_length(c, 1) < 5 or upper(c[1]) not in ('M', 'F', '1', '2') or c[2] !~ '^[0-9]+$' then
      v_err := v_err || jsonb_build_object('linha', i, 'erro', 'Use: sexo (M/F);idade em meses;L;M;S'); continue;
    end if;
    insert into iara.referencia_imc (sexo, idade_meses, l, m, s, fonte, importado_por_label)
    values (case when upper(c[1]) in ('M', '1') then 'M' else 'F' end, c[2]::smallint, replace(c[3], ',', '.')::numeric, replace(c[4], ',', '.')::numeric,
            replace(c[5], ',', '.')::numeric, btrim(p ->> 'fonte'), iara.my_label())
    on conflict (sexo, idade_meses) do update set l = excluded.l, m = excluded.m, s = excluded.s, fonte = excluded.fonte, importado_por_label = excluded.importado_por_label, importado_em = now();
    n := n + 1;
  end loop;
  if jsonb_array_length(v_err) > 0 and n = 0 then raise exception 'Nenhuma linha válida: %', v_err::text using errcode = '22023'; end if;
  update iara.antropometria a set zscore = (r ->> 'z')::numeric, classificacao = r ->> 'classe'
  from (select a2.id, iara.imc_classificar(s.gender, a2.idade_meses, a2.imc) r from iara.antropometria a2 join iara.students s on s.id = a2.student_id) z
  where z.id = a.id;
  perform iara.audit_event('ANTROPOMETRIA', 'referencia_imc', 'importacao', null, format('Referência de IMC para a idade importada: %s linha(s) (%s).', n, btrim(p ->> 'fonte')));
  return jsonb_build_object('importadas', n, 'erros', v_err);
end $$;

-- demonstração: duas medições no ano (março e agosto) para a maioria dos alunos; valores fictícios plausíveis para a idade
create or replace function iara.demo_gerar_antropometria() returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.antropometria where is_demo;
  insert into iara.antropometria (student_id, unit_id, class_id, data, peso_kg, altura_cm, imc, idade_meses, conferir, medido_por_label, created_at, is_demo)
  select z.student_id, z.unit_id, z.class_id, z.data, z.peso, z.alt, round(z.peso / power(z.alt / 100.0, 2), 2), z.meses, false, 'Professora da turma (demonstração)', z.data::timestamptz + interval '10 hours', true
  from (select e.student_id, e.unit_id, e.class_id, d.data,
               (extract(year from age(d.data, s.birth_date)) * 12 + extract(month from age(d.data, s.birth_date)))::int meses,
               round((50 + 1.7 * least((extract(year from age(d.data, s.birth_date)) * 12 + extract(month from age(d.data, s.birth_date))), 24)
                      + 0.55 * greatest((extract(year from age(d.data, s.birth_date)) * 12 + extract(month from age(d.data, s.birth_date))) - 24, 0)
                      + (abs(hashtext(e.student_id::text || 'alt')) % 120 - 60) / 10.0)::numeric, 1) alt,
               d.k, abs(hashtext(e.student_id::text || 'imc')) % 100 h
        from iara.enrollments e join iara.students s on s.id = e.student_id
        cross join (values (1, date '2026-03-16'), (2, date '2026-08-17')) d(k, data)
        where e.status = 'ACTIVE' and s.birth_date < d.data - 180 and abs(hashtext(e.student_id::text || 'med' || d.k)) % 100 < case d.k when 1 then 88 else 76 end) z0
  cross join lateral (select z0.*, round((power(z0.alt / 100.0, 2) * (14.6 + (z0.h % 40) / 10.0 + case when z0.h >= 93 then 4.5 when z0.h < 3 then -2.2 else 0 end
                               + (abs(hashtext(z0.student_id::text || z0.k)) % 6 - 3) / 10.0))::numeric, 2) peso) z
  where z.alt between 45 and 190 and z.peso between 3 and 120
  on conflict (student_id, data) do nothing;
  get diagnostics n = row_count;
  perform set_config('iara.skip_audit', 'off', true);
  return n;
end $$;

create or replace function iara.demo_purge_antropometria(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  d timestamptz := coalesce(p_desde, '-infinity'::timestamptz);
  n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.antropometria where not is_demo and created_at >= d; get diagnostics n = row_count;
  -- a referência importada ao vivo é dado oficial: só sai na limpeza total, nunca aqui
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('medidas', n);
end $$;

revoke all on function iara.demo_gerar_antropometria(), iara.demo_purge_antropometria(timestamptz) from public;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('antropometria', 'peso_kg', 'SENSIVEL', 'saúde da criança', 'acompanhamento nutricional', 'escola, nutrição da rede e família'),
  ('antropometria', 'altura_cm', 'SENSIVEL', 'saúde da criança', 'acompanhamento nutricional', 'escola, nutrição da rede e família'),
  ('antropometria', 'imc', 'SENSIVEL', 'saúde da criança', 'acompanhamento nutricional', 'escola, nutrição da rede e família'),
  ('antropometria', 'classificacao', 'SENSIVEL', 'saúde da criança', 'acompanhamento nutricional', 'nutrição e escola; a família vê leitura sem rótulo'),
  ('antropometria', 'observacao', 'SENSIVEL', 'saúde da criança', 'acompanhamento nutricional', 'escola e nutrição'),
  ('antropometria', 'medido_por_label', 'PESSOAL', 'identificação', 'auditoria', null)
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

select iara.demo_gerar_antropometria() where iara.demo_mode();

commit;
