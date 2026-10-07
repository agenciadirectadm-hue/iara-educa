-- IARA Educa — 069 · Conteúdos ministrados (diário de classe) (Sprint 5)
-- O professor registra cada aula do horário da turma: conteúdo, objetivos, habilidades da BNCC (opcional), atividade, tarefa de casa
-- e materiais. A família vê o que o filho estudou e a tarefa (portal e IARA: “o que a Ana estudou hoje?”). A coordenação e a direção
-- acompanham as aulas sem registro por turma e por professor; a SEDUC vê o retrato da rede. Registro até 15 dias depois da aula.
begin;

insert into iara.permissions (code, description, is_sensitive) values
  ('aulas.write', 'Registrar o conteúdo das aulas da própria turma', false),
  ('aulas.read', 'Consultar os conteúdos ministrados e as aulas sem registro', false)
on conflict (code) do update set description = excluded.description;
insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('PROFESSOR', 'aulas.write'), ('PROFESSOR', 'aulas.read'), ('PROFESSOR_AEE', 'aulas.read'),
  ('DIRETOR_UNIDADE', 'aulas.read'), ('SECRETARIA_ESCOLAR', 'aulas.read'),
  ('SECRETARIO', 'aulas.read'), ('SUPERINTENDENCIA', 'aulas.read'), ('GERENCIA_EI', 'aulas.read')
) v(r, p)
on conflict do nothing;

create table if not exists iara.aulas_registros (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references iara.classes(id) on delete cascade,
  unit_id integer,
  data date not null,
  aula smallint not null check (aula between 1 and 10),
  componente text not null,
  staff_id uuid references iara.staff(id) on delete set null,
  conteudo text not null,
  objetivos text,
  habilidades text[] not null default '{}',
  atividade text,
  tarefa text,
  materiais text,
  registrado_por_label text,
  created_at timestamptz not null default now(),
  alterado_em timestamptz,
  is_demo boolean not null default false,
  unique (class_id, data, aula)
);
create index if not exists aulas_registros_data_idx on iara.aulas_registros (unit_id, data);
alter table iara.aulas_registros enable row level security;

create or replace function iara.aulas_acesso(p_class uuid) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select iara.has_perm('aulas.read') and ((iara.my_role() in ('PROFESSOR', 'PROFESSOR_AEE') and p_class = any (iara.minhas_turmas()))
    or (iara.my_role() not in ('PROFESSOR', 'PROFESSOR_AEE') and exists (select 1 from iara.classes c where c.id = p_class and iara.can_access_unit(c.unit_id))))
$$;

-- aulas previstas de um período: dias letivos × horário da turma
create or replace function iara.aulas_previstas(p_class uuid, p_de date, p_ate date) returns table (data date, aula smallint, componente text, staff_id uuid)
language sql stable security definer set search_path = iara, public
as $$
  select d::date, h.aula, h.componente, h.staff_id
  from iara.classes c cross join generate_series(p_de, p_ate, interval '1 day') d
  join iara.horarios_turma h on h.class_id = c.id and h.dia_semana = extract(isodow from d)::int
  where c.id = p_class and extract(isodow from d) between 1 and 5 and iara.dia_letivo(d::date, c.unit_id)
$$;

create or replace function api.aulas_dia(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_class uuid := (p ->> 'class_id')::uuid;
  v_data date := coalesce(nullif(p ->> 'data', '')::date, iara.hoje_local());
  v_unit integer;
begin
  if not iara.aulas_acesso(v_class) then raise exception 'Turma fora do seu escopo.' using errcode = '42501'; end if;
  select unit_id into v_unit from iara.classes where id = v_class;
  return jsonb_build_object('class_id', v_class, 'data', v_data, 'letivo', iara.dia_letivo(v_data, v_unit) and extract(isodow from v_data) between 1 and 5,
    'pode_registrar', iara.has_perm('aulas.write') and v_class = any (iara.minhas_turmas()) and v_data <= iara.hoje_local() and v_data >= iara.hoje_local() - 15,
    'turma', (select c.class_name || ' · ' || u.short_name from iara.classes c join iara.education_units u on u.id = c.unit_id where c.id = v_class),
    'aulas', (select coalesce(jsonb_agg(jsonb_build_object('aula', h.aula, 'componente', h.componente, 'professor', st.full_name,
                 'registro', (select to_jsonb(r) - 'class_id' - 'unit_id' from iara.aulas_registros r where r.class_id = v_class and r.data = v_data and r.aula = h.aula)) order by h.aula), '[]')
              from iara.horarios_turma h left join iara.staff st on st.id = h.staff_id
              where h.class_id = v_class and h.dia_semana = extract(isodow from v_data)::int),
    'semana', (select coalesce(jsonb_agg(jsonb_build_object('data', z.data, 'previstas', z.prev, 'registradas', z.reg) order by z.data), '[]') from (
                 select ap.data, count(*) prev, count(r.id) reg from iara.aulas_previstas(v_class, v_data - 6, least(v_data, iara.hoje_local())) ap
                 left join iara.aulas_registros r on r.class_id = v_class and r.data = ap.data and r.aula = ap.aula group by 1) z));
end $$;

create or replace function api.aula_registrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_class uuid := (p ->> 'class_id')::uuid;
  v_data date := (p ->> 'data')::date;
  v_aula smallint := (p ->> 'aula')::smallint;
  v_unit integer;
  h iara.horarios_turma;
  v_hab text[] := coalesce((select array_agg(distinct upper(btrim(x))) from jsonb_array_elements_text(coalesce(p -> 'habilidades', '[]')) x where btrim(x) <> ''), '{}');
  r iara.aulas_registros;
begin
  if not (iara.has_perm('aulas.write') and v_class = any (iara.minhas_turmas())) then
    raise exception 'O conteúdo é registrado pelo professor da turma.' using errcode = '42501';
  end if;
  select unit_id into v_unit from iara.classes where id = v_class;
  if v_data > iara.hoje_local() then raise exception 'Não dá para registrar aula futura.' using errcode = '22023'; end if;
  if v_data < iara.hoje_local() - 15 then raise exception 'O registro vai até 15 dias depois da aula; peça à coordenação para registrar com justificativa.' using errcode = '22023'; end if;
  if extract(isodow from v_data) > 5 or not iara.dia_letivo(v_data, v_unit) then raise exception 'Não é dia letivo.' using errcode = '22023'; end if;
  select * into h from iara.horarios_turma where class_id = v_class and dia_semana = extract(isodow from v_data)::int and aula = v_aula;
  if h.class_id is null then raise exception 'Esta aula não está no horário da turma.' using errcode = '22023'; end if;
  if length(btrim(coalesce(p ->> 'conteudo', ''))) < 5 then raise exception 'Escreva o conteúdo da aula.' using errcode = '22023'; end if;
  if exists (select 1 from unnest(v_hab) x where x !~ '^E[IF][0-9]{2}[A-Z]{2}[0-9]{2}$') then
    raise exception 'Código de habilidade da BNCC inválido (ex.: EF03MA05 ou EI03EO01).' using errcode = '22023';
  end if;
  insert into iara.aulas_registros (class_id, unit_id, data, aula, componente, staff_id, conteudo, objetivos, habilidades, atividade, tarefa, materiais, registrado_por_label)
  values (v_class, v_unit, v_data, v_aula, h.componente, h.staff_id, btrim(p ->> 'conteudo'), nullif(btrim(coalesce(p ->> 'objetivos', '')), ''), v_hab,
          nullif(btrim(coalesce(p ->> 'atividade', '')), ''), nullif(btrim(coalesce(p ->> 'tarefa', '')), ''), nullif(btrim(coalesce(p ->> 'materiais', '')), ''), iara.my_label())
  on conflict (class_id, data, aula) do update set conteudo = excluded.conteudo, objetivos = excluded.objetivos, habilidades = excluded.habilidades,
     atividade = excluded.atividade, tarefa = excluded.tarefa, materiais = excluded.materiais, registrado_por_label = excluded.registrado_por_label, alterado_em = now()
  returning * into r;
  perform iara.audit_event('AULA_REGISTRADA', 'class', v_class::text, v_unit, format('Conteúdo da %sª aula (%s) de %s registrado.', v_aula, h.componente, to_char(v_data, 'DD/MM')));
  return api.aulas_dia(jsonb_build_object('class_id', v_class, 'data', v_data));
end $$;

-- aulas sem registro: na unidade por turma e professor (desde o início do bimestre); na rede por unidade (últimos 10 dias)
create or replace function api.aulas_pendencias(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_ate date := iara.hoje_local() - 1;
  v_de date;
begin
  perform iara.require_perm('aulas.read');
  if iara.my_role() in ('PROFESSOR', 'PROFESSOR_AEE') then raise exception 'Use a turma para ver as suas aulas.' using errcode = '42501'; end if;
  if v_unit is not null then
    if not iara.can_access_unit(v_unit) then raise exception 'Unidade fora do seu escopo.' using errcode = '42501'; end if;
    v_de := coalesce((select inicio from iara.bimestres where ano = 2026 and numero = iara.bimestre_atual()), v_ate - 30);
    return (with prev as (select c.id class_id, c.class_name, ap.* from iara.classes c cross join lateral iara.aulas_previstas(c.id, v_de, v_ate) ap
                          where c.unit_id = v_unit and c.status = 'ATIVA'),
                 x as (select prev.*, r.id reg from prev left join iara.aulas_registros r on r.class_id = prev.class_id and r.data = prev.data and r.aula = prev.aula)
      select jsonb_build_object('unit_id', v_unit, 'de', v_de, 'ate', v_ate,
        'previstas', (select count(*) from x), 'registradas', (select count(reg) from x),
        'turmas', (select coalesce(jsonb_agg(jsonb_build_object('class_id', class_id, 'turma', class_name, 'previstas', n, 'registradas', reg, 'pct', round(100.0 * reg / nullif(n, 0)),
                       'ultima_sem_registro', ult) order by round(100.0 * reg / nullif(n, 0)), class_name), '[]')
                   from (select class_id, class_name, count(*) n, count(reg) reg, max(data) filter (where reg is null) ult from x group by 1, 2) z),
        'professores', (select coalesce(jsonb_agg(jsonb_build_object('staff_id', staff_id, 'nome', st.full_name, 'previstas', n, 'registradas', reg, 'pct', round(100.0 * reg / nullif(n, 0)))
                         order by round(100.0 * reg / nullif(n, 0)), st.full_name), '[]')
                        from (select staff_id, count(*) n, count(reg) reg from x where staff_id is not null group by 1) z join iara.staff st on st.id = z.staff_id)));
  end if;
  v_de := v_ate - 13;
  return (with x as (select c.unit_id, ap.data, r.id reg from iara.classes c cross join lateral iara.aulas_previstas(c.id, v_de, v_ate) ap
                     left join iara.aulas_registros r on r.class_id = c.id and r.data = ap.data and r.aula = ap.aula where c.status = 'ATIVA')
    select jsonb_build_object('unit_id', null, 'de', v_de, 'ate', v_ate, 'previstas', (select count(*) from x), 'registradas', (select count(reg) from x),
      'unidades', (select coalesce(jsonb_agg(jsonb_build_object('unit_id', z.unit_id, 'unidade', u.short_name, 'previstas', z.n, 'registradas', z.reg, 'pct', round(100.0 * z.reg / nullif(z.n, 0)))
                    order by round(100.0 * z.reg / nullif(z.n, 0)), u.short_name), '[]')
                   from (select unit_id, count(*) n, count(reg) reg from x group by 1) z join iara.education_units u on u.id = z.unit_id)));
end $$;

-- família: o que cada filho estudou nos últimos dias letivos e a tarefa de casa
create or replace function api.familia_aulas(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('student_id', s.id, 'primeiro_nome', split_part(s.full_name, ' ', 1), 'turma', c.class_name,
      'dias', (select coalesce(jsonb_agg(jsonb_build_object('data', d.data, 'aulas', d.aulas) order by d.data desc), '[]') from (
                 select r.data, jsonb_agg(jsonb_build_object('aula', r.aula, 'componente', r.componente, 'conteudo', r.conteudo, 'atividade', r.atividade, 'tarefa', r.tarefa,
                          'materiais', r.materiais) order by r.aula) aulas
                 from iara.aulas_registros r where r.class_id = e.class_id and r.data >= iara.hoje_local() - coalesce(nullif(p ->> 'dias', '')::int, 10)
                 group by r.data) d))
      order by s.full_name), '[]')
    from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' join iara.classes c on c.id = e.class_id
    where s.id in (select iara.my_student_ids()));
end $$;

-- demonstração: os últimos 12 dias com registro em cerca de 88% das aulas (o resto vira pendência)
create or replace function iara.demo_gerar_aulas() returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.aulas_registros where is_demo;
  insert into iara.aulas_registros (class_id, unit_id, data, aula, componente, staff_id, conteudo, atividade, tarefa, registrado_por_label, created_at, is_demo)
  select c.id, c.unit_id, ap.data, ap.aula, ap.componente, ap.staff_id,
         t.conteudos[1 + abs(hashtext(c.id::text || ap.data || ap.aula)) % array_length(t.conteudos, 1)],
         (array['Explicação no quadro e atividade no caderno', 'Trabalho em duplas', 'Jogo pedagógico em grupos', 'Leitura coletiva e conversa', 'Atividade prática com material concreto'])[1 + abs(hashtext(c.id::text || ap.data || 'at')) % 5],
         case when ap.componente in ('Língua Portuguesa', 'Matemática') and abs(hashtext(c.id::text || ap.data || ap.aula || 'tc')) % 100 < 35
              then (array['Ler o livro da sacola e contar a história para a família', 'Exercícios 1 a 5 do caderno', 'Pesquisar com a família uma receita e trazer escrita',
                          'Resolver as 3 situações-problema da folha', 'Treinar a leitura do texto da semana'])[1 + abs(hashtext(c.id::text || ap.data)) % 5] end,
         coalesce((select split_part(full_name, ' ', 1) from iara.staff where id = ap.staff_id), 'Professora') || ' (demonstração)',
         ap.data::timestamptz + interval '15 hours', true
  from iara.classes c cross join lateral iara.aulas_previstas(c.id, iara.hoje_local() - 12, iara.hoje_local() - 1) ap
  join (values
    ('Língua Portuguesa', array['Leitura compartilhada e interpretação de texto narrativo', 'Produção de texto: bilhete e recado', 'Ortografia: palavras com R e RR', 'Pontuação no diálogo',
                               'Leitura de poemas e rimas', 'Substantivos próprios e comuns', 'Reescrita de conto conhecido', 'Sinônimos e antônimos']),
    ('Matemática', array['Adição e subtração com reagrupamento', 'Situações-problema de multiplicação', 'Sistema monetário: compras e troco', 'Medidas de comprimento com régua',
                        'Frações: metade e terça parte', 'Tabelas e gráficos de colunas', 'Figuras geométricas planas', 'Cálculo mental e estimativa']),
    ('Ciências', array['Ciclo da água', 'Partes das plantas e suas funções', 'Cuidados com o corpo e higiene', 'Animais vertebrados e invertebrados', 'Materiais e suas propriedades', 'Sistema solar']),
    ('História', array['Linha do tempo da família', 'Maringá: fundação e crescimento da cidade', 'Brincadeiras de antigamente e de hoje', 'Povos indígenas do Paraná', 'Documentos pessoais e memória']),
    ('Geografia', array['Mapa do bairro e pontos de referência', 'Paisagens naturais e modificadas', 'Zona urbana e zona rural de Maringá', 'Orientação: pontos cardeais', 'Trânsito seguro']),
    ('Arte', array['Releitura de obra de Tarsila do Amaral', 'Cores primárias e secundárias', 'Modelagem com argila', 'Desenho de observação', 'Colagem com materiais recicláveis']),
    ('Educação Física', array['Jogos cooperativos', 'Circuito motor', 'Brincadeiras populares', 'Iniciação ao handebol', 'Ginástica e alongamento']),
    ('Inglês', array['Greetings and colors', 'Numbers 1 to 20', 'Family members', 'Animals vocabulary']),
    ('Ensino Religioso', array['Respeito às diferenças', 'Festas e tradições', 'Valores: amizade e cooperação']),
    ('Leitura e projetos', array['Roda de leitura', 'Projeto horta escolar', 'Projeto meio ambiente: reciclagem']),
    ('Música', array['Canções e parlendas', 'Instrumentos de percussão', 'Ritmo e pulsação']),
    ('Campos de experiência', array['Roda de conversa sobre o fim de semana', 'Contação de história com fantoches', 'Exploração de texturas no parque sensorial', 'Música e movimento', 'Pintura com guache']),
    ('Rotina e experiências', array['Brincadeira com massinha: cores e formas', 'Brincadeiras no pátio: corre-cotia', 'Hora do conto', 'Cantigas de roda', 'Montagem com blocos'])
  ) t(componente, conteudos) on t.componente = ap.componente
  where c.status = 'ATIVA' and abs(hashtext(c.id::text || ap.data || ap.aula || 'reg')) % 100 < 88;
  get diagnostics n = row_count;
  perform set_config('iara.skip_audit', 'off', true);
  return n;
end $$;

create or replace function iara.demo_purge_aulas(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  d timestamptz := coalesce(p_desde, '-infinity'::timestamptz);
  n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.aulas_registros where not is_demo and created_at >= d; get diagnostics n = row_count;
  if exists (select 1 from iara.aulas_registros where is_demo and alterado_em >= d) then perform iara.demo_gerar_aulas(); end if;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('aulas', n);
end $$;

revoke all on function iara.demo_gerar_aulas(), iara.demo_purge_aulas(timestamptz) from public;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('aulas_registros', 'registrado_por_label', 'PESSOAL', 'identificação', 'auditoria', null)
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

select iara.demo_gerar_aulas() where iara.demo_mode();

commit;
