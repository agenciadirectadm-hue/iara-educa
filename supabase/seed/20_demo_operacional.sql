-- IARA Educa — Seed 20 · Camada operacional de DEMONSTRAÇÃO
--
-- O que é REAL (Censo Escolar 2025 / INEP): quantidade de turmas e de matrículas por série em cada unidade,
-- turnos agregados por etapa, nº de docentes e de matrículas da educação especial por unidade.
-- O que é FICTÍCIO (rotulado DEMO): divisão das matrículas por turma, capacidade autorizada, alunos,
-- responsáveis, endereços, profissionais, fila, ofertas, protocolos e conversas.
-- Totais operacionais calibrados para partir dos valores do protótipo visual (demo_metrics):
-- 2.348 vagas ofertáveis · 1.276 crianças na fila (aguardando + com oferta) · 802 protocolos abertos.
begin;

create or replace function iara.fake_cpf() returns text
language plpgsql volatile
as $$
declare
  d int[] := '{}';
  s int;
  d1 int;
  d2 int;
  i int;
begin
  for i in 1..9 loop d := d || floor(random() * 10)::int; end loop;
  s := 0; for i in 1..9 loop s := s + d[i] * (11 - i); end loop;
  d1 := (s * 10) % 11; if d1 = 10 then d1 := 0; end if;
  s := 0; for i in 1..9 loop s := s + d[i] * (12 - i); end loop;
  s := s + d1 * 2; d2 := (s * 10) % 11; if d2 = 10 then d2 := 0; end if;
  d1 := (d1 + 1) % 10; -- dígito verificador propositalmente inválido: nunca coincide com um CPF real
  return format('%s%s%s.%s%s%s.%s%s%s-%s%s', d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], d[9], d1, d2);
end $$;

create or replace function iara.demo_birthdate(p_code text, p_older boolean default false) returns date
language sql volatile
as $$
  select case p_code
    when 'CRECHE' then date '2022-04-01' + floor(random() * (date '2025-11-30' - date '2022-04-01'))::int
    when 'PRE' then date '2020-04-01' + floor(random() * 730)::int
    when 'EJA_AI' then date '1962-01-01' + floor(random() * (date '2010-03-31' - date '1962-01-01'))::int
    when 'FUTURA' then date '2025-12-01' + floor(random() * 240)::int
    else make_date(2026 - 6 - (substr(p_code, 3, 1)::int - 1) - 1 - (case when p_older then 1 else 0 end), 4, 1)
         + floor(random() * 365)::int
  end
$$;

create or replace function iara.pick(p_arr text[]) returns text
language sql volatile as $$ select p_arr[1 + floor(random() * array_length(p_arr, 1))::int] $$;

create or replace function iara.demo_generate(p_seed double precision default 0.2026)
returns jsonb
language plpgsql security definer set search_path = iara, extensions, public
as $fn$
declare
  kids_f text[] := array['Alice','Helena','Laura','Maria Alice','Valentina','Heloísa','Maria Clara','Maria Cecília','Lívia','Sophia',
    'Cecília','Júlia','Manuela','Isabella','Maitê','Luiza','Eloá','Lorena','Antonella','Liz','Aurora','Maria Júlia','Lara','Mariana',
    'Elisa','Olívia','Ana Clara','Agatha','Rebeca','Esther','Melissa','Isis','Maria Luiza','Beatriz','Lavínia','Clara','Ayla','Pietra',
    'Isadora','Yasmin','Nicole','Emanuelly','Catarina','Ana Laura','Giovanna','Sarah','Stella','Mirella','Vitória','Allana',
    'Maria Eduarda','Ana Júlia','Bianca','Gabriela','Letícia','Rafaela','Larissa','Kamilly','Sofia','Ana Beatriz','Yumi','Hana','Emily'];
  kids_m text[] := array['Miguel','Arthur','Gael','Théo','Heitor','Ravi','Davi','Bernardo','Noah','Gabriel','Samuel','Pedro','Anthony',
    'Isaac','Benício','Benjamin','Matheus','Lucas','Joaquim','Nicolas','Lucca','Lorenzo','Henrique','João Miguel','Rafael','Henry',
    'Murilo','Levi','Guilherme','Vicente','Felipe','Bryan','Matteo','Bento','João Pedro','Pietro','Leonardo','Daniel','Gustavo',
    'Pedro Henrique','Enzo','Enzo Gabriel','Caio','Thiago','Eduardo','Vitor','Otávio','Davi Lucca','Augusto','Antônio','Emanuel',
    'João Lucas','Kauã','Yuri','Ryan','Calebe','Martin','Francisco','Luiz Felipe','Kenji','Hiro'];
  adults_f text[] := array['Ana Paula','Juliana','Patrícia','Aline','Fernanda','Camila','Priscila','Daniela','Tatiane','Vanessa','Simone',
    'Cristiane','Adriana','Luciana','Fabiana','Débora','Raquel','Elaine','Michele','Jéssica','Thaís','Renata','Sabrina','Kelly',
    'Andressa','Jaqueline','Eliane','Rosângela','Silvana','Marta','Sandra','Regina','Sônia','Joana','Francisca','Tereza','Aparecida',
    'Edna','Neide','Vera','Carla','Mônica','Luana','Bruna','Amanda','Natália','Gabriela','Larissa','Letícia','Bianca','Mariana',
    'Carolina','Viviane','Karina','Roberta','Márcia','Cláudia','Rosana','Solange','Gisele','Érica','Kátia','Mayara','Paula'];
  adults_m text[] := array['José','João','Antônio','Francisco','Carlos','Paulo','Pedro','Lucas','Luiz','Marcos','Luís','Gabriel','Rafael',
    'Daniel','Marcelo','Bruno','Eduardo','Felipe','Raimundo','Rodrigo','Fernando','Fábio','Leandro','Diego','Gustavo','Thiago',
    'Ricardo','Anderson','Alexandre','Sérgio','Márcio','Roberto','Vinícius','André','Júlio','Renato','Jefferson','Wellington',
    'Everton','Cristiano','Adriano','Juliano','Leonardo','Mateus','Douglas','Rogério','Edson','Valdir','Vagner','Cláudio'];
  surnames text[] := array['Silva','Santos','Oliveira','Souza','Rodrigues','Ferreira','Alves','Pereira','Lima','Gomes','Costa','Ribeiro',
    'Martins','Carvalho','Almeida','Lopes','Soares','Fernandes','Vieira','Barbosa','Rocha','Dias','Nascimento','Andrade','Moreira',
    'Nunes','Marques','Machado','Mendes','Freitas','Cardoso','Ramos','Gonçalves','Santana','Teixeira','Araújo','Moraes','Pinto',
    'Correia','Batista','Campos','Monteiro','Cavalcanti','Miranda','Castro','Reis','Rezende','Toledo','Mazzaro','Tanaka','Yamamoto',
    'Kobayashi','Nakamura','Watanabe','Zanetti','Bertoli','Rossi','Ferrari','Romano','Colombo','Ricci','Bianchi','Marchetti',
    'Pagliari','Kowalski','Nowak','Schmidt','Becker','Hoffmann','Wagner','Prado','Siqueira','Brandão','Bueno','Camargo','Fonseca',
    'Guimarães','Pires','Sato','Ito'];
  streets text[] := array['Rua das Flores','Rua dos Ipês','Rua das Palmeiras','Rua das Acácias','Rua dos Jacarandás','Avenida das Primaveras',
    'Rua das Hortênsias','Rua dos Girassóis','Rua das Orquídeas','Rua das Azaleias','Rua das Camélias','Rua das Magnólias','Rua dos Lírios',
    'Rua das Violetas','Rua das Margaridas','Rua dos Cravos','Rua das Begônias','Rua dos Manacás','Rua das Tulipas','Rua dos Flamboyants',
    'Rua das Paineiras','Rua dos Cedros','Rua das Sibipirunas','Rua das Quaresmeiras','Rua dos Coqueiros','Rua das Gardênias',
    'Rua dos Jasmins','Rua das Bromélias','Rua das Pitangueiras','Rua dos Pessegueiros'];
  occupations text[] := array['Auxiliar administrativa','Vendedor(a)','Diarista','Professor(a)','Motorista','Cozinheiro(a)','Técnico(a) de enfermagem',
    'Autônomo(a)','Do lar','Operador(a) de caixa','Costureiro(a)','Comerciante','Estudante','Atendente','Recepcionista','Analista',
    'Auxiliar de produção','Repositor(a)','Cabeleireiro(a)','Pedreiro','Eletricista','Manicure','Babá','Garçom/Garçonete','Servidor(a) público(a)'];
  v_now timestamptz := now();
  v_target_vac integer := 2348;
  v_reserved_target integer;
  v_eja_total integer;
  v_alloc integer;
  v_diff integer;
  v_muni extensions.geometry;
  v_unit_maria integer;
  v_class_ana uuid;
  v_maria_hh uuid := gen_random_uuid();
  v_maria uuid := gen_random_uuid();
  v_jorge uuid := gen_random_uuid();
  v_ana uuid := gen_random_uuid();
  v_davi uuid := gen_random_uuid();
  v_davi_case uuid := gen_random_uuid();
  v_davi_entry uuid := gen_random_uuid();
  v_staff1 uuid := '00000000-0000-4000-8000-000000000001';
  v_staff2 uuid := '00000000-0000-4000-8000-000000000002';
  v_sys uuid := '00000000-0000-4000-8000-000000000009';
  v_result jsonb;
begin
  perform set_config('iara.skip_audit', 'on', true);
  perform set_config('iara.skip_counters', 'on', true);
  perform setseed(p_seed);

  truncate iara.audit_log, iara.tool_executions, iara.handoff_tasks, iara.messages, iara.conversations, iara.notifications,
           iara.documents, iara.vacancy_events, iara.vacancy_offers, iara.vacancy_blocks, iara.waiting_list_entries,
           iara.case_events, iara.service_cases, iara.enrollments, iara.class_staff, iara.staff, iara.classes,
           iara.student_guardians, iara.student_sensitive, iara.students, iara.guardians, iara.addresses,
           iara.app_sessions, iara.app_users restart identity cascade;
  perform setval('iara.protocol_seq', 1, false);
  perform setval('iara.student_registry_seq', 202600001, false);

  select extensions.st_buffer(geom::extensions.geometry, 0) into v_muni from iara.territories where id = 100;

  -- Usuários de serviço fixos (equipe fictícia que realizou as ações históricas)
  insert into iara.app_users (id, tenant_id, display_name, role_code, auth_provider, is_demo) values
    (v_staff1, 1, 'Carla Menezes · Central de Vagas (demo)', 'ANALISTA_CENTRAL', 'SEED', true),
    (v_staff2, 1, 'Rodrigo Tanaka · Central de Vagas (demo)', 'ANALISTA_CENTRAL', 'SEED', true),
    (v_sys, 1, 'Rotina automática IARA', 'ANALISTA_CENTRAL', 'SYSTEM', true);

  -- =========================================================================
  -- 1. TURMAS — nº por série e matrículas do Censo 2025; divisão/turno/capacidade fictícios
  -- =========================================================================
  create temp table tmp_cls on commit drop as
  with g as (
    select s.unit_id, s.grade_level_id, gl.code as gcode, gl.name as gname, gl.stage_id, gl.sort as gsort,
           s.classes_count as n, s.enrollments_count as m, u.macro_territory_id as macro
    from iara.unit_grade_stats s
    join iara.grade_levels gl on gl.id = s.grade_level_id
    join iara.education_units u on u.id = s.unit_id
    where s.grade_level_id is not null and s.classes_count > 0 and s.enrollments_count > 0 and u.status = 'ATIVA'
  ),
  x as (select g.*, i, 0.8 + random() * 0.4 as w from g, generate_series(1, g.n) i),
  y as (select x.*, x.m * x.w / sum(x.w) over (partition by x.unit_id, x.grade_level_id) as share from x),
  f as (select y.*, floor(y.share)::int as base, y.share - floor(y.share) as frac from y),
  r as (select f.*, f.m - sum(f.base) over (partition by f.unit_id, f.grade_level_id) as rem,
               row_number() over (partition by f.unit_id, f.grade_level_id order by f.frac desc, f.i) as rk from f)
  select gen_random_uuid() as id, unit_id, grade_level_id, gcode, gname, stage_id, gsort, macro, i as idx,
         base + case when rk <= rem then 1 else 0 end as enrolled, null::text as shift
  from r;

  with grp as (
    select c.*, case c.gcode when 'CRECHE' then 'Educação Infantil - Creche' when 'PRE' then 'Educação Infantil - Pré-escola'
                             when 'EJA_AI' then 'EJA - Fundamental' else 'Ensino Fundamental - anos iniciais' end as sgroup
    from tmp_cls c
  ),
  ordered as (select grp.*, row_number() over (partition by unit_id, sgroup order by gsort, idx) as rn from grp),
  arr as (
    select unit_id, stage_name, array_agg(sh order by ord, k) as shifts
    from (select unit_id, stage_name, case shift when 'Manhã' then 'MANHA' when 'Tarde' then 'TARDE' else 'NOITE' end as sh,
                 case shift when 'Manhã' then 1 when 'Tarde' then 2 else 3 end as ord, k
          from iara.unit_shift_stats, generate_series(1, classes_count) k) e
    group by unit_id, stage_name
  )
  update tmp_cls t set shift = coalesce(a.shifts[1 + ((o.rn - 1) % array_length(a.shifts, 1))],
                                        case when o.gcode = 'EJA_AI' then 'NOITE' when o.rn % 2 = 0 then 'TARDE' else 'MANHA' end)
  from ordered o left join arr a on a.unit_id = o.unit_id and a.stage_name = o.sgroup
  where t.id = o.id;

  insert into iara.classes (id, tenant_id, school_year, unit_id, stage_id, grade_level_id, class_code, class_name, shift, room_label,
                            authorized_capacity, source, source_updated_at, confidence_status, is_demo)
  select id, 1, 2026, unit_id, stage_id, grade_level_id, gcode || '-' || chr(64 + idx), gname || ' ' || chr(64 + idx), shift,
         'Sala ' || lpad((row_number() over (partition by unit_id, shift order by gsort, idx))::text, 2, '0'),
         enrolled,
         'DEMO — nº de turmas e de matrículas por série: Censo Escolar 2025/INEP (oficial). Divisão por turma, turno da turma e capacidade autorizada: fictícios, pendentes SEDUC.',
         v_now, 'DEMO', true
  from tmp_cls;

  -- =========================================================================
  -- 2. ALUNOS MATRICULADOS + FAMÍLIAS (agrupadas por macrorregião → irmãos em unidades próximas)
  -- =========================================================================
  create temp table tmp_seat on commit drop as
  select gen_random_uuid() as student_id, c.id as class_id, c.unit_id, c.grade_level_id, c.gcode, c.macro,
         u.lat as ulat, u.lng as ulng, u.neighborhood, u.postal_code, random() as r_shuffle,
         case when random() < 0.5 then 'F' else 'M' end as gender, (random() < 0.03 and c.gcode like 'EF%') as older,
         null::bigint as hh
  from tmp_cls c join iara.education_units u on u.id = c.unit_id, generate_series(1, c.enrolled) k;

  create index on tmp_seat (unit_id);
  with o as (select student_id, macro, row_number() over (partition by macro order by r_shuffle) as rn, random() < 0.86 as newhh from tmp_seat),
       h as (select student_id, macro, sum(case when newhh or rn = 1 then 1 else 0 end) over (partition by macro order by rn) as hseq from o)
  update tmp_seat s set hh = h.macro * 1000000 + h.hseq from h where h.student_id = s.student_id;

  create temp table tmp_hh on commit drop as
  select distinct on (hh) hh, unit_id as anchor_unit, ulat, ulng, neighborhood, postal_code, macro,
         gen_random_uuid() as address_id, gen_random_uuid() as guardian_id, gen_random_uuid() as guardian2_id,
         0.0::float8 as lat, 0.0::float8 as lng, null::text as rel, iara.pick(surnames) as surname,
         random() as x_income, random() < 0.30 as has_second
  from tmp_seat order by hh, r_shuffle;

  update tmp_hh set rel = case when random() < 0.78 then 'MAE' when random() < 0.68 then 'PAI' when random() < 0.6 then 'AVO' else 'TIA' end;

  update tmp_hh h set lat = h.ulat + d.km * cos(d.ang) / 111.32,
                      lng = h.ulng + d.km * sin(d.ang) / (111.32 * cos(radians(h.ulat)))
  from (select hh, (case when random() < 0.65 then 0.15 + random() * 1.45 when random() < 0.8 then 1.6 + random() * 1.6 else 3.2 + random() * 2.8 end)
                   * (case when macro in (6, 7) then 0.45 else 1 end) as km,
               random() * 2 * pi() as ang
        from tmp_hh) d
  where d.hh = h.hh;
  update tmp_hh h set lat = h.ulat + (random() - 0.5) * 0.006, lng = h.ulng + (random() - 0.5) * 0.006
  where v_muni is not null and not extensions.st_contains(v_muni, extensions.st_setsrid(extensions.st_makepoint(h.lng, h.lat), 4326));

  insert into iara.addresses (id, tenant_id, street, number, complement, neighborhood, postal_code, location, geocode_precision, geocode_source, territory_id, is_demo)
  select address_id, 1, iara.pick(streets), (10 + floor(random() * 2400))::int::text,
         case when random() < 0.10 then 'Casa ' || (1 + floor(random() * 3))::int when random() < 0.08 then 'Apto ' || (11 + floor(random() * 80))::int end,
         neighborhood, regexp_replace(coalesce(postal_code, '87000-000'), '-\d{3}$', '-000'), iara.point(lat, lng),
         'DEMO_APROXIMADO', 'DEMO — endereço fictício', macro, true
  from tmp_hh;

  insert into iara.guardians (id, tenant_id, full_name, cpf, nis, birth_date, gender, email, primary_phone, whatsapp_phone,
                              preferred_contact_channel, address_id, occupation, employment_status, family_income, income_bracket,
                              cadunico_status, benefits, education_level, household_size, consent_flags, is_demo)
  select h.guardian_id, 1, x.first || ' ' || iara.pick(surnames) || ' ' || h.surname, iara.fake_cpf(),
         case when x.cad then '2' || lpad(floor(random() * 1e10)::bigint::text, 10, '0') end,
         case when h.rel = 'AVO' then date '1956-01-01' + floor(random() * 5800)::int else date '1976-01-01' + floor(random() * 10200)::int end,
         case when h.rel in ('MAE', 'AVO', 'TIA') then 'F' else 'M' end,
         lower(iara.f_unaccent(split_part(x.first, ' ', 1) || '.' || h.surname)) || (10 + floor(random() * 89))::int || '@email.test',
         '(44) 90000-' || lpad(floor(random() * 10000)::int::text, 4, '0'),
         '(44) 90000-' || lpad(floor(random() * 10000)::int::text, 4, '0'),
         case when random() < 0.72 then 'WHATSAPP' when random() < 0.6 then 'SMS' else 'EMAIL' end,
         h.address_id, iara.pick(occupations),
         case when random() < 0.48 then 'CLT' when random() < 0.45 then 'Autônomo' when random() < 0.5 then 'Informal' when random() < 0.5 then 'Desempregado' else 'Servidor público' end,
         round((x.inc * 1518)::numeric, 2),
         case when x.inc < 1 then 'Até 1 salário mínimo' when x.inc < 2 then '1 a 2 salários mínimos' when x.inc < 3 then '2 a 3 salários mínimos'
              when x.inc < 5 then '3 a 5 salários mínimos' else 'Acima de 5 salários mínimos' end,
         x.cad,
         case when x.cad and random() < 0.7 then '["Bolsa Família"]'::jsonb else '[]'::jsonb end,
         iara.pick(array['Fundamental incompleto','Fundamental completo','Médio incompleto','Médio completo','Médio completo','Superior incompleto','Superior completo']),
         (2 + floor(random() * 4))::int,
         '{"lgpd_ciencia": true, "whatsapp": true}'::jsonb, true
  from tmp_hh h
  cross join lateral (
    select case when h.rel in ('MAE', 'AVO', 'TIA') then iara.pick(adults_f) else iara.pick(adults_m) end as first,
           power(h.x_income, 1.6) * 7 + 0.4 as inc,
           (power(h.x_income, 1.6) * 7 + 0.4) < 2.2 and random() < 0.62 as cad
    where h.hh is not null
  ) x;

  insert into iara.guardians (id, tenant_id, full_name, cpf, birth_date, gender, email, primary_phone, whatsapp_phone, address_id,
                              occupation, employment_status, cadunico_status, consent_flags, is_demo)
  select h.guardian2_id, 1,
         case when h.rel = 'PAI' then iara.pick(adults_f) else iara.pick(adults_m) end || ' ' || iara.pick(surnames) || ' ' || h.surname,
         iara.fake_cpf(), date '1974-01-01' + floor(random() * 10500)::int, case when h.rel = 'PAI' then 'F' else 'M' end,
         null, '(44) 90000-' || lpad(floor(random() * 10000)::int::text, 4, '0'), null, h.address_id, iara.pick(occupations),
         case when random() < 0.6 then 'CLT' else 'Autônomo' end, false, '{"lgpd_ciencia": true}'::jsonb, true
  from tmp_hh h where h.has_second and h.rel in ('MAE', 'PAI');

  insert into iara.students (id, tenant_id, full_name, birth_date, gender, status, address_id, transport_need, avatar_seed, is_demo)
  select s.student_id, 1,
         case when s.gender = 'F' then iara.pick(kids_f) else iara.pick(kids_m) end || ' ' || iara.pick(surnames) || ' ' || h.surname,
         iara.demo_birthdate(s.gcode, s.older), s.gender, 'MATRICULADO', h.address_id,
         random() < (case when s.macro in (6, 7) then 0.22 else 0.04 end), floor(random() * 1000)::int, true
  from tmp_seat s join tmp_hh h on h.hh = s.hh;

  insert into iara.student_guardians (student_id, guardian_id, relationship, is_primary, start_date)
  select s.student_id, h.guardian_id, h.rel, true, date '2025-11-10'
  from tmp_seat s join tmp_hh h on h.hh = s.hh;
  insert into iara.student_guardians (student_id, guardian_id, relationship, is_primary, start_date)
  select s.student_id, h.guardian2_id, case when h.rel = 'PAI' then 'MAE' else 'PAI' end, false, date '2025-11-10'
  from tmp_seat s join tmp_hh h on h.hh = s.hh where h.has_second and h.rel in ('MAE', 'PAI');

  insert into iara.enrollments (tenant_id, student_id, class_id, unit_id, school_year, status, enrollment_date, start_date, entry_type, is_demo)
  select 1, student_id, class_id, unit_id, 2026, 'ACTIVE', date '2025-11-10' + floor(random() * 115)::int, date '2026-02-02',
         case when random() < 0.8 then 'RENOVACAO' else 'NOVA' end, true
  from tmp_seat;
  update iara.students s set current_enrollment_id = e.id from iara.enrollments e where e.student_id = s.id;

  -- AEE: exatamente o nº oficial de matrículas da educação especial de cada unidade (Censo 2025); alunos sorteados são fictícios
  with ranked as (
    select s.student_id, s.unit_id, row_number() over (partition by s.unit_id order by random()) as rn
    from tmp_seat s where s.gcode <> 'EJA_AI'
  )
  update iara.students st set aee_status = true
  from ranked r join iara.education_units u on u.id = r.unit_id
  where st.id = r.student_id and r.rn <= coalesce(u.census_special_ed_enrollments, 0);

  insert into iara.student_sensitive (student_id, special_education_need, medical_alerts)
  select id, iara.pick(array['TEA — nível 1 de suporte','TEA — nível 2 de suporte','Deficiência intelectual','Deficiência física',
                             'Deficiência visual — baixa visão','Deficiência auditiva','Altas habilidades/superdotação']),
         case when random() < 0.2 then iara.pick(array['Epilepsia controlada — protocolo na secretaria','Asma — bombinha na mochila','Uso de medicação contínua (detalhe com a família)']) end
  from iara.students where aee_status;
  update iara.students set accessibility_needs = iara.pick(array['Cadeirante — necessita rampa e banheiro adaptado','Baixa visão — material ampliado','Usuário de aparelho auditivo'])
  where aee_status and random() < 0.12;
  insert into iara.student_sensitive (student_id, food_allergies)
  select id, iara.pick(array['Intolerância à lactose','Doença celíaca (sem glúten)','Alergia a amendoim','Alergia a ovo','Alergia a corantes'])
  from iara.students where random() < 0.04
  on conflict (student_id) do update set food_allergies = excluded.food_allergies;

  -- Documentos das matrículas vigentes (validados)
  insert into iara.documents (tenant_id, student_id, doc_type, status, file_name, received_at, validated_at, is_demo)
  select 1, s.student_id, d.doc, 'VALIDADO', lower(d.doc) || '_' || substr(s.student_id::text, 1, 8) || '.pdf',
         timestamptz '2025-11-12 10:00-03' + (floor(random() * 100) || ' days')::interval,
         timestamptz '2025-11-20 10:00-03' + (floor(random() * 100) || ' days')::interval, true
  from tmp_seat s cross join (values ('CERTIDAO'), ('COMPROVANTE_ENDERECO'), ('CARTAO_SUS'), ('VACINACAO')) d(doc);

  -- =========================================================================
  -- 3. PROFISSIONAIS (pool dimensionado pelo nº real de docentes do Censo 2025; nomes fictícios)
  -- =========================================================================
  insert into iara.staff (tenant_id, unit_id, full_name, role, bond, is_demo)
  select 1, u.id, case when random() < 0.86 then iara.pick(adults_f) else iara.pick(adults_m) end || ' ' || iara.pick(surnames) || ' ' || iara.pick(surnames),
         case when u.unit_type = 'CMEI' then 'EDUCADOR' else 'PROFESSOR' end,
         case when random() < 0.82 then 'Efetivo' else 'PSS / temporário' end, true
  from iara.education_units u
  join (select unit_id, count(*) as nc from tmp_cls group by unit_id) c on c.unit_id = u.id
  cross join lateral generate_series(1, greatest(coalesce(u.census_teachers, 0), ceil(c.nc / 1.6)::int)) k;

  with cl as (select c.id as class_id, c.unit_id, row_number() over (partition by c.unit_id order by c.shift, c.grade_level_id, c.class_code) as rn from iara.classes c),
       st as (select s.id as staff_id, s.unit_id, row_number() over (partition by s.unit_id order by s.full_name) as rn,
                     count(*) over (partition by s.unit_id) as n from iara.staff s)
  insert into iara.class_staff (class_id, staff_id, role_type, is_primary, hours_per_week)
  select cl.class_id, st.staff_id, 'REGENTE', true, 20
  from cl join st on st.unit_id = cl.unit_id and st.rn = ((cl.rn - 1) % st.n) + 1;

  with aux as (
    insert into iara.staff (tenant_id, unit_id, full_name, role, bond, is_demo)
    select 1, c.unit_id, iara.pick(adults_f) || ' ' || iara.pick(surnames) || ' ' || iara.pick(surnames), 'AUXILIAR', 'Efetivo', true
    from iara.classes c where c.grade_level_id = 1
    returning id, unit_id
  ), aux_n as (select id, unit_id, row_number() over (partition by unit_id order by id) as rn from aux),
     cls_n as (select id, unit_id, row_number() over (partition by unit_id order by id) as rn from iara.classes where grade_level_id = 1)
  insert into iara.class_staff (class_id, staff_id, role_type, is_primary, hours_per_week)
  select c.id, a.id, 'AUXILIAR', false, 40 from cls_n c join aux_n a on a.unit_id = c.unit_id and a.rn = c.rn;

  insert into iara.staff (tenant_id, unit_id, full_name, role, bond, is_demo)
  select 1, u.id, iara.pick(adults_f) || ' ' || iara.pick(surnames) || ' ' || iara.pick(surnames), 'AEE', 'Efetivo', true
  from iara.education_units u where coalesce(u.census_special_ed_enrollments, 0) >= 8 and exists (select 1 from iara.classes c where c.unit_id = u.id);

  -- =========================================================================
  -- 4. BLOQUEIOS DE VAGA (motivo e justificativa obrigatórios)
  -- =========================================================================
  insert into iara.vacancy_blocks (tenant_id, class_id, seats, reason, justification, valid_until, created_by, created_at, is_demo)
  select 1, c.id, 1 + (random() < 0.35)::int, r.reason, r.just, current_date + 30 + floor(random() * 90)::int, v_staff1,
         v_now - (floor(random() * 40) || ' days')::interval, true
  from (select id from iara.classes where grade_level_id <> 8 order by random() limit 46) c
  cross join lateral (
    select reason, just from (values
      ('INCLUSAO', 'Redução de turma para inclusão de aluno com deficiência (laudo arquivado em fluxo restrito).'),
      ('INCLUSAO', 'Turma com estudante TEA nível 2: vaga mantida bloqueada por recomendação da equipe multiprofissional.'),
      ('ADAPTACAO_SALA', 'Sala com metragem inferior à capacidade nominal; aguardando adequação de mobiliário.'),
      ('OBRA', 'Reforma de banheiros infantis em andamento; capacidade reduzida até a entrega da obra.'),
      ('AUSENCIA_PROFISSIONAL', 'Aguardando contratação de auxiliar para cumprir a proporção adulto/criança.'),
      ('RESERVA_ADMINISTRATIVA', 'Reserva para remanejamento interno aprovado pela Diretoria de Gestão Educacional.'),
      ('DECISAO_JUDICIAL', 'Vaga reservada para cumprimento de decisão judicial (processo em segredo de justiça).'),
      ('REORGANIZACAO', 'Turma em reorganização de turnos para o segundo semestre.')
    ) v(reason, just) where c.id is not null order by random() limit 1
  ) r;

  -- =========================================================================
  -- 5. CAPACIDADE AUTORIZADA (fictícia) — calibrada para 2.348 vagas ofertáveis
  -- =========================================================================
  v_reserved_target := 58; -- 40 ofertas aguardando resposta + 18 aceites aguardando matrícula
  create temp table tmp_cap on commit drop as
  select c.id, c.unit_id, c.grade_level_id, c.macro, c.enrolled,
         coalesce((select sum(b.seats) from iara.vacancy_blocks b where b.class_id = c.id), 0)::int as blocked,
         0 as v,
         case
           when c.gcode = 'EJA_AI' then 0
           when random() < (case c.gcode when 'CRECHE' then 0.42 else 0.22 end + case c.macro when 2 then 0.16 when 4 then 0.08 else 0 end) then 0
           else power(random(), 1.3)
                * (case c.macro when 1 then 1.7 when 3 then 1.3 when 5 then 1.15 when 4 then 0.8 when 2 then 0.55 when 6 then 1.2 else 1.4 end)
                * (case c.gcode when 'CRECHE' then 0.55 when 'PRE' then 0.95 else 1.2 end)
         end as w
  from tmp_cls c;
  update tmp_cap set v = 2 + floor(random() * 5)::int where grade_level_id = 8;
  select coalesce(sum(v), 0) into v_eja_total from tmp_cap where grade_level_id = 8;
  v_alloc := v_target_vac + v_reserved_target - v_eja_total;
  with s as (select id, v_alloc * w / sum(w) over () as share from tmp_cap where grade_level_id <> 8 and w > 0),
       f as (select id, floor(share)::int as base, share - floor(share) as frac from s),
       r as (select id, base, row_number() over (order by frac desc) as rk, v_alloc - sum(base) over () as rem from f)
  update tmp_cap t set v = r.base + case when r.rk <= r.rem then 1 else 0 end from r where r.id = t.id;
  update iara.classes c set authorized_capacity = t.enrolled + t.v + t.blocked from tmp_cap t where t.id = c.id;

  perform iara.recount_all_classes();

  -- =========================================================================
  -- 6. FILA DE ESPERA — 1.275 entradas sorteadas (+ Davi, cenário do cidadão)
  -- =========================================================================
  create temp table tmp_ug on commit drop as
  select c.unit_id, c.grade_level_id, u.macro_territory_id as macro, count(*) as n_classes,
         sum(c.offerable_vacancies_count) as offerable, u.lat, u.lng, u.neighborhood, u.postal_code
  from iara.classes c join iara.education_units u on u.id = c.unit_id
  group by c.unit_id, c.grade_level_id, u.macro_territory_id, u.lat, u.lng, u.neighborhood, u.postal_code;

  create temp table tmp_q (
    entry_id uuid default gen_random_uuid(), student_id uuid default gen_random_uuid(), case_id uuid default gen_random_uuid(),
    category text, grade_level_id smallint, gcode text, macro integer, unit_id integer, sibling_of uuid,
    existing_student boolean default false, full_time boolean default false, entered_at timestamptz, gender char(1),
    hh_address uuid, hh_guardian uuid, vuln boolean default false, aee boolean default false, status text default 'WAITING',
    channel text
  ) on commit drop;

  -- 6a. Crianças sem atendimento / recusaram / demanda futura (novas famílias ou irmãos de matriculados)
  insert into tmp_q (category, gcode, macro)
  select cat, case when cat = 'DEMANDA_FUTURA' then 'CRECHE'
                   when x < 0.80 then 'CRECHE' when x < 0.93 then 'PRE' when x < 0.97 then 'EF1'
                   else 'EF' || (2 + floor(x * 1000)::int % 4) end,
         case when y < 0.34 then 2 when y < 0.60 then 4 when y < 0.74 then 3 when y < 0.88 then 5 when y < 0.94 then 1 when y < 0.97 then 6 else 7 end
  from (select cat, random() as x, random() as y
        from unnest(array_fill('SEM_ATENDIMENTO'::text, array[1035]) || array_fill('RECUSOU_OFERTA'::text, array[28])
                    || array_fill('DEMANDA_FUTURA'::text, array[17])) as cat) z;
  update tmp_q q set grade_level_id = gl.id from iara.grade_levels gl where gl.code = q.gcode;
  update tmp_q q set unit_id = (
    select ug.unit_id from tmp_ug ug where ug.grade_level_id = q.grade_level_id and ug.macro = q.macro and q.entry_id is not null
    order by power(random(), 1.0 / ug.n_classes) desc limit 1)
  where q.category in ('SEM_ATENDIMENTO', 'RECUSOU_OFERTA', 'DEMANDA_FUTURA');
  update tmp_q q set unit_id = (
    select ug.unit_id from tmp_ug ug where ug.grade_level_id = q.grade_level_id and q.entry_id is not null
    order by power(random(), 1.0 / ug.n_classes) desc limit 1)
  where q.unit_id is null;
  update tmp_q q set sibling_of = (select s.student_id from tmp_seat s where s.unit_id = q.unit_id and q.entry_id is not null order by random() limit 1)
  where random() < 0.12 and q.category <> 'DEMANDA_FUTURA';

  -- 6b. Já atendidas: transferência, unidade preferencial (alunos matriculados) e parcial → integral
  insert into tmp_q (category, student_id, existing_student, grade_level_id, gcode, macro, unit_id, full_time)
  select z.cat, z.student_id, true, z.grade_level_id, z.gcode, z.macro,
         case when z.cat = 'PARCIAL_PARA_INTEGRAL' then z.unit_id
              else (select ug.unit_id from tmp_ug ug
                    where ug.grade_level_id = z.grade_level_id and ug.unit_id <> z.unit_id
                      and extensions.st_dwithin(iara.point(ug.lat, ug.lng), iara.point(z.ulat, z.ulng), 3500)
                    order by random() limit 1) end,
         z.cat = 'PARCIAL_PARA_INTEGRAL'
  from (
    select s.*, c.cat, row_number() over (partition by c.cat order by random()) as rn
    from tmp_seat s cross join (values ('AGUARDA_TRANSFERENCIA'), ('UNIDADE_PREFERENCIAL'), ('PARCIAL_PARA_INTEGRAL')) c(cat)
    where s.gcode <> 'EJA_AI' and (c.cat <> 'PARCIAL_PARA_INTEGRAL' or s.gcode in ('CRECHE', 'PRE'))
  ) z
  where (z.cat = 'AGUARDA_TRANSFERENCIA' and z.rn <= 140) or (z.cat = 'UNIDADE_PREFERENCIAL' and z.rn <= 70)
     or (z.cat = 'PARCIAL_PARA_INTEGRAL' and z.rn <= 60);
  delete from tmp_q where unit_id is null;
  delete from tmp_q a using tmp_q b
  where a.existing_student and b.existing_student and a.student_id = b.student_id and a.entry_id > b.entry_id;
  delete from tmp_q where entry_id in (
    select entry_id from (select entry_id, category, row_number() over (partition by category order by random()) rn from tmp_q
                          where category in ('AGUARDA_TRANSFERENCIA', 'UNIDADE_PREFERENCIAL')) t
    where (category = 'AGUARDA_TRANSFERENCIA' and rn > 115) or (category = 'UNIDADE_PREFERENCIAL' and rn > 50));

  update tmp_q set entered_at = timestamptz '2026-10-02 17:00-03' - ((power(random(), 1.25) * 240) || ' days')::interval
                                - ((floor(random() * 9)) || ' hours')::interval,
                   gender = case when random() < 0.5 then 'F' else 'M' end,
                   vuln = random() < 0.06, aee = random() < 0.04,
                   channel = case when random() < 0.36 then 'WEB' when random() < 0.5 then 'WHATSAPP' when random() < 0.6 then 'PRESENCIAL'
                                  when random() < 0.6 then 'TELEFONE' else 'CMEI' end;

  -- famílias das novas crianças
  update tmp_q q set hh_address = s.address_id, hh_guardian = sg.guardian_id
  from iara.students s join iara.student_guardians sg on sg.student_id = s.id and sg.is_primary
  where q.sibling_of = s.id;

  create temp table tmp_newhh on commit drop as
  select q.entry_id, gen_random_uuid() as address_id, gen_random_uuid() as guardian_id, iara.pick(surnames) as surname,
         ug.lat + km * cos(ang) / 111.32 as lat, ug.lng + km * sin(ang) / (111.32 * cos(radians(ug.lat))) as lng,
         ug.neighborhood, ug.postal_code, q.macro, random() as x_income,
         case when random() < 0.82 then 'MAE' when random() < 0.7 then 'PAI' else 'AVO' end as rel
  from tmp_q q
  join tmp_ug ug on ug.unit_id = q.unit_id and ug.grade_level_id = q.grade_level_id
  cross join lateral (select (case when random() < 0.75 then 0.2 + random() * 1.75 else 2.0 + random() * 2.6 end)
                             * (case when q.macro in (6, 7) then 0.5 else 1 end) as km, random() * 2 * pi() as ang
                      where q.entry_id is not null) d
  where not q.existing_student and q.sibling_of is null;
  update tmp_newhh h set lat = h.lat + (random() - 0.5) * 0.004, lng = h.lng + (random() - 0.5) * 0.004
  where v_muni is not null and not extensions.st_contains(v_muni, extensions.st_setsrid(extensions.st_makepoint(h.lng, h.lat), 4326));

  insert into iara.addresses (id, tenant_id, street, number, neighborhood, postal_code, location, geocode_precision, geocode_source, territory_id, is_demo)
  select address_id, 1, iara.pick(streets), (10 + floor(random() * 2400))::int::text, neighborhood,
         regexp_replace(coalesce(postal_code, '87000-000'), '-\d{3}$', '-000'), iara.point(lat, lng), 'DEMO_APROXIMADO', 'DEMO — endereço fictício', macro, true
  from tmp_newhh;
  insert into iara.guardians (id, tenant_id, full_name, cpf, birth_date, gender, email, primary_phone, whatsapp_phone, address_id, occupation,
                              employment_status, family_income, income_bracket, cadunico_status, benefits, household_size, consent_flags, is_demo)
  select h.guardian_id, 1, x.first || ' ' || iara.pick(surnames) || ' ' || h.surname, iara.fake_cpf(),
         date '1980-01-01' + floor(random() * 9000)::int, case when h.rel = 'PAI' then 'M' else 'F' end,
         lower(iara.f_unaccent(split_part(x.first, ' ', 1) || '.' || h.surname)) || (10 + floor(random() * 89))::int || '@email.test',
         '(44) 90000-' || lpad(floor(random() * 10000)::int::text, 4, '0'), '(44) 90000-' || lpad(floor(random() * 10000)::int::text, 4, '0'),
         h.address_id, iara.pick(occupations), case when random() < 0.5 then 'CLT' when random() < 0.5 then 'Informal' else 'Autônomo' end,
         round((x.inc * 1518)::numeric, 2),
         case when x.inc < 1 then 'Até 1 salário mínimo' when x.inc < 2 then '1 a 2 salários mínimos' when x.inc < 3 then '2 a 3 salários mínimos'
              when x.inc < 5 then '3 a 5 salários mínimos' else 'Acima de 5 salários mínimos' end,
         x.cad, case when x.cad then '["Bolsa Família"]'::jsonb else '[]'::jsonb end, (2 + floor(random() * 4))::int,
         '{"lgpd_ciencia": true, "whatsapp": true}'::jsonb, true
  from tmp_newhh h
  cross join lateral (select case when h.rel = 'PAI' then iara.pick(adults_m) else iara.pick(adults_f) end as first,
                             power(h.x_income, 1.5) * 6 + 0.35 as inc,
                             (power(h.x_income, 1.5) * 6 + 0.35) < 2.2 and random() < 0.62 as cad where h.entry_id is not null) x;
  update tmp_q q set hh_address = h.address_id, hh_guardian = h.guardian_id from tmp_newhh h where h.entry_id = q.entry_id;

  insert into iara.students (id, tenant_id, full_name, birth_date, gender, status, address_id, aee_status, avatar_seed, is_demo)
  select q.student_id, 1,
         case when q.gender = 'F' then iara.pick(kids_f) else iara.pick(kids_m) end || ' ' || iara.pick(surnames) || ' ' ||
           coalesce((select split_part(g.full_name, ' ', array_length(string_to_array(g.full_name, ' '), 1)) from iara.guardians g where g.id = q.hh_guardian), iara.pick(surnames)),
         iara.demo_birthdate(case when q.category = 'DEMANDA_FUTURA' then 'FUTURA' else q.gcode end),
         q.gender, 'AGUARDANDO_VAGA', q.hh_address, q.aee, floor(random() * 1000)::int, true
  from tmp_q q where not q.existing_student;
  insert into iara.student_sensitive (student_id, special_education_need)
  select student_id, iara.pick(array['TEA — nível 1 de suporte','Deficiência física','Deficiência intelectual','Atraso global do desenvolvimento (em investigação)'])
  from tmp_q where aee and not existing_student;
  insert into iara.student_guardians (student_id, guardian_id, relationship, is_primary, start_date)
  select q.student_id, q.hh_guardian, coalesce(h.rel, 'MAE'), true, (q.entered_at)::date
  from tmp_q q left join tmp_newhh h on h.entry_id = q.entry_id where not q.existing_student;

  -- protocolo de origem (encerrado: criança inserida na fila) + entrada na fila
  insert into iara.service_cases (id, tenant_id, protocol_number, case_type, channel, status, priority, student_id, guardian_id, unit_id,
                                  assigned_team, subject, description, opened_at, sla_due_at, closed_at, resolution_code, resolution_notes, created_by, is_demo)
  select q.case_id, 1, iara.next_protocol(),
         case when q.category in ('AGUARDA_TRANSFERENCIA', 'UNIDADE_PREFERENCIAL') then 'TRANSFERENCIA'
              when q.category = 'PARCIAL_PARA_INTEGRAL' then 'INTEGRAL' else 'SOLICITACAO_VAGA' end,
         coalesce(q.channel, 'WEB'), 'ENCERRADO', 'NORMAL', q.student_id,
         coalesce(q.hh_guardian, (select sg.guardian_id from iara.student_guardians sg where sg.student_id = q.student_id and sg.is_primary limit 1)),
         q.unit_id, 'CENTRAL_VAGAS',
         case q.category when 'AGUARDA_TRANSFERENCIA' then 'Transferência para unidade mais próxima de casa'
                         when 'UNIDADE_PREFERENCIAL' then 'Aguarda vaga na unidade preferida'
                         when 'PARCIAL_PARA_INTEGRAL' then 'Pedido de período integral'
                         when 'DEMANDA_FUTURA' then 'Cadastro antecipado de demanda (bebê)'
                         else 'Solicitação de vaga — ' || (select name from iara.grade_levels where id = q.grade_level_id) end,
         'Pedido registrado e analisado; sem vaga ofertável compatível no momento da análise.',
         q.entered_at - interval '2 days', q.entered_at + interval '8 days', q.entered_at, 'INSERIDO_NA_FILA',
         'Criança inserida na fila conforme regras vigentes.', v_staff1, true
  from tmp_q q;

  insert into iara.waiting_list_entries (id, tenant_id, student_id, case_id, stage_id, grade_level_id, preferred_unit_id, territory_id,
                                         preferred_shift, full_time_requested, demand_category, priority_flags, entered_at, status, created_by, is_demo)
  select q.entry_id, 1, q.student_id, q.case_id, gl.stage_id, q.grade_level_id, q.unit_id, q.macro,
         case when random() < 0.35 then null when random() < 0.55 then 'MANHA' else 'TARDE' end,
         q.full_time, q.category, case when q.vuln then array['VULNERABILIDADE'] else '{}' end, q.entered_at, 'WAITING', v_staff1, true
  from tmp_q q join iara.grade_levels gl on gl.id = q.grade_level_id;

  -- =========================================================================
  -- 7. CENÁRIO DO CIDADÃO (Maria + Ana Luísa matriculada + Davi 1º da fila de creche)
  -- =========================================================================
  perform iara.demo_family_criteria(); -- mães solo e laudos fictícios (critérios da IN nº 025/2025)
  perform iara.compute_queue_priority(id) from iara.waiting_list_entries;

  select u.id into v_unit_maria
  from iara.education_units u
  where u.unit_type = 'CMEI' and u.status = 'ATIVA' and u.macro_territory_id in (2, 4)
    and exists (select 1 from iara.classes c where c.unit_id = u.id and c.grade_level_id = 1 and c.offerable_vacancies_count >= 2)
    and exists (select 1 from iara.classes c where c.unit_id = u.id and c.grade_level_id = 2)
    and not exists (select 1 from iara.waiting_list_entries w where w.preferred_unit_id = u.id and w.grade_level_id = 1 and w.priority_score >= 95)
  order by (u.neighborhood ilike '%alvorada%') desc, (select count(*) from iara.waiting_list_entries w where w.preferred_unit_id = u.id and w.grade_level_id = 1) desc
  limit 1;
  if v_unit_maria is null then
    select u.id into v_unit_maria from iara.education_units u
    where u.unit_type = 'CMEI' and u.status = 'ATIVA'
      and exists (select 1 from iara.classes c where c.unit_id = u.id and c.grade_level_id = 1 and c.offerable_vacancies_count >= 1)
      and exists (select 1 from iara.classes c where c.unit_id = u.id and c.grade_level_id = 2)
    order by (select coalesce(max(w.priority_score), 0) from iara.waiting_list_entries w where w.preferred_unit_id = u.id and w.grade_level_id = 1)
    limit 1;
    -- garante Davi como 1º: quem tiver pontuação igual ou maior é remanejado para outra unidade com creche
    update iara.waiting_list_entries w set preferred_unit_id = (
      select ug.unit_id from tmp_ug ug where ug.grade_level_id = 1 and ug.unit_id <> v_unit_maria and w.id is not null order by random() limit 1)
    where w.preferred_unit_id = v_unit_maria and w.grade_level_id = 1 and w.priority_score >= 95;
  end if;

  select id into v_class_ana from iara.classes where unit_id = v_unit_maria and grade_level_id = 2 order by class_code limit 1;

  insert into iara.addresses (id, tenant_id, street, number, neighborhood, postal_code, location, geocode_precision, geocode_source, territory_id, is_demo)
  select v_maria_hh, 1, 'Rua das Pitangueiras', '418', u.neighborhood, regexp_replace(coalesce(u.postal_code, '87000-000'), '-\d{3}$', '-000'),
         iara.point(u.lat + 0.0045, u.lng - 0.0021), 'DEMO_APROXIMADO', 'DEMO — endereço fictício', u.macro_territory_id, true
  from iara.education_units u where u.id = v_unit_maria;

  insert into iara.guardians (id, tenant_id, full_name, cpf, nis, birth_date, gender, email, primary_phone, whatsapp_phone, preferred_contact_channel,
                              address_id, occupation, employment_status, family_income, income_bracket, cadunico_status, benefits, education_level,
                              household_size, consent_flags, is_demo)
  values (v_maria, 1, 'Maria Aparecida dos Santos', iara.fake_cpf(), '20481516234', date '1992-08-17', 'F', 'maria.aparecida@email.test',
          '(44) 90000-4182', '(44) 90000-4182', 'WHATSAPP', v_maria_hh, 'Auxiliar de cozinha', 'CLT', 2120.00, '1 a 2 salários mínimos',
          true, '["Bolsa Família"]', 'Médio completo', 4, '{"lgpd_ciencia": true, "whatsapp": true}', true),
         (v_jorge, 1, 'Jorge Luiz de Oliveira', iara.fake_cpf(), null, date '1989-03-02', 'M', null, '(44) 90000-7731', null, 'SMS',
          v_maria_hh, 'Motorista de entregas', 'Autônomo', null, null, false, '[]', 'Médio completo', 4, '{"lgpd_ciencia": true}', true);

  insert into iara.students (id, tenant_id, full_name, birth_date, gender, status, address_id, avatar_seed, is_demo) values
    (v_ana, 1, 'Ana Luísa Santos Oliveira', date '2021-05-14', 'F', 'MATRICULADO', v_maria_hh, 512, true),
    (v_davi, 1, 'Davi Santos Oliveira', date '2024-07-20', 'M', 'AGUARDANDO_VAGA', v_maria_hh, 377, true);
  insert into iara.student_guardians (student_id, guardian_id, relationship, is_primary, start_date) values
    (v_ana, v_maria, 'MAE', true, date '2024-11-20'), (v_ana, v_jorge, 'PAI', false, date '2024-11-20'),
    (v_davi, v_maria, 'MAE', true, date '2026-06-03'), (v_davi, v_jorge, 'PAI', false, date '2026-06-03');
  insert into iara.enrollments (tenant_id, student_id, class_id, unit_id, school_year, status, enrollment_date, start_date, entry_type, is_demo)
  values (1, v_ana, v_class_ana, v_unit_maria, 2026, 'ACTIVE', date '2025-11-24', date '2026-02-02', 'RENOVACAO', true);
  update iara.students s set current_enrollment_id = e.id from iara.enrollments e where e.student_id = s.id and s.id = v_ana;
  insert into iara.documents (tenant_id, student_id, doc_type, status, file_name, received_at, validated_at, is_demo)
  select 1, v_ana, d, 'VALIDADO', lower(d) || '_ana_luisa.pdf', timestamptz '2025-11-24 09:30-03', timestamptz '2025-11-26 14:00-03', true
  from unnest(array['CERTIDAO','COMPROVANTE_ENDERECO','CARTAO_SUS','VACINACAO']) d;
  insert into iara.documents (tenant_id, student_id, guardian_id, doc_type, status, file_name, received_at, validated_at, is_demo)
  select 1, v_davi, null, d, case when d = 'VACINACAO' then 'PENDENTE' else 'VALIDADO' end,
         case when d = 'VACINACAO' then null else lower(d) || '_davi.pdf' end,
         case when d = 'VACINACAO' then null else timestamptz '2026-06-03 10:15-03' end,
         case when d = 'VACINACAO' then null else timestamptz '2026-06-05 16:40-03' end, true
  from unnest(array['CERTIDAO','COMPROVANTE_ENDERECO','CARTAO_SUS','VACINACAO']) d;

  insert into iara.service_cases (id, tenant_id, protocol_number, case_type, channel, status, priority, student_id, guardian_id, unit_id,
                                  assigned_team, subject, description, opened_at, sla_due_at, closed_at, resolution_code, resolution_notes, created_by, is_demo)
  values (v_davi_case, 1, iara.next_protocol(), 'SOLICITACAO_VAGA', 'WHATSAPP', 'ENCERRADO', 'NORMAL', v_davi, v_maria, v_unit_maria,
          'CENTRAL_VAGAS', 'Solicitação de vaga — Creche (Davi)', 'Pedido feito pelo WhatsApp da IARA. Irmã matriculada na unidade.',
          timestamptz '2026-06-01 19:42-03', timestamptz '2026-06-11 19:42-03', timestamptz '2026-06-03 11:05-03', 'INSERIDO_NA_FILA',
          'Sem vaga ofertável na creche da unidade preferida; criança inserida na fila.', v_staff1, true);
  insert into iara.waiting_list_entries (id, tenant_id, student_id, case_id, stage_id, grade_level_id, preferred_unit_id, territory_id,
                                         preferred_shift, demand_category, priority_flags, entered_at, status, created_by, is_demo)
  select v_davi_entry, 1, v_davi, v_davi_case, 1, 1, v_unit_maria, u.macro_territory_id, 'MANHA', 'SEM_ATENDIMENTO', '{}',
         timestamptz '2026-06-03 11:05-03', 'WAITING', v_staff1, true
  from iara.education_units u where u.id = v_unit_maria;
  perform iara.compute_queue_priority(v_davi_entry);

  perform iara.recalculate_all_queues();

  -- =========================================================================
  -- 8. OFERTAS — 40 aguardando resposta + 18 aceitas (sempre ao 1º da fila) + histórico
  -- =========================================================================
  create temp table tmp_offer on commit drop as
  with cand as (
    select w.id as entry_id, w.student_id, w.case_id, w.preferred_unit_id as unit_id, w.grade_level_id,
           (select c.id from iara.classes c join tmp_cap t on t.id = c.id
             where c.unit_id = w.preferred_unit_id and c.grade_level_id = w.grade_level_id and t.v >= 2
             order by random() limit 1) as class_id
    from iara.waiting_list_entries w
    where w.status = 'WAITING' and w.position = 1 and w.id <> v_davi_entry
      and not (w.preferred_unit_id = v_unit_maria and w.grade_level_id = 1)
  )
  , dedup as (select cand.*, row_number() over (partition by class_id order by random()) as k from cand where class_id is not null)
  select entry_id, student_id, case_id, unit_id, grade_level_id, class_id, row_number() over (order by random()) as rn
  from dedup where k = 1;
  delete from tmp_offer where rn > 58;

  insert into iara.vacancy_offers (tenant_id, waiting_list_entry_id, student_id, class_id, unit_id, case_id, offered_at, expires_at, channel,
                                   status, accepted_at, response_channel, ranking_snapshot, idempotency_key, created_by, is_demo)
  select 1, o.entry_id, o.student_id, o.class_id, o.unit_id, o.case_id, t.offered_at, t.offered_at + interval '72 hours',
         'WHATSAPP', case when o.rn <= 40 then 'OFFERED' else 'ACCEPTED' end,
         case when o.rn > 40 then t.offered_at + ((2 + floor(random() * 20)) || ' hours')::interval end,
         case when o.rn > 40 then 'WHATSAPP' end,
         jsonb_build_object('motivo', '1º da fila da unidade/faixa com vaga ofertável', 'regras', iara.rule_version(), 'posicao', 1),
         'seed-offer-' || o.entry_id, case when random() < 0.5 then v_staff1 else v_staff2 end, true
  from tmp_offer o
  cross join lateral (select v_now - ((case when o.rn <= 40 then 1 + floor(random() * 38) else 26 + floor(random() * 90) end) || ' hours')::interval as offered_at
                      where o.entry_id is not null) t;
  update iara.waiting_list_entries w set status = case when o.rn <= 40 then 'OFFERED' else 'ACCEPTED' end
  from tmp_offer o where o.entry_id = w.id;
  update iara.service_cases c set status = 'VAGA_OFERTADA', closed_at = null, resolution_code = null,
         resolution_notes = null, sla_due_at = v_now + interval '3 days'
  from tmp_offer o where o.case_id = c.id;

  -- histórico: ofertas que viraram matrícula (alunos novos de 2026)
  with picked as (
    select e.id as enrollment_id, e.student_id, e.class_id, e.unit_id, e.enrollment_date, c.grade_level_id, gl.stage_id,
           row_number() over (order by random()) as rn
    from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
    where e.entry_type = 'NOVA' and c.grade_level_id <> 8
  ), sel as (select *, gen_random_uuid() as entry_id, gen_random_uuid() as case_id from picked where rn <= 180),
  cases as (
    insert into iara.service_cases (id, tenant_id, protocol_number, case_type, channel, status, priority, student_id, guardian_id, unit_id,
                                    assigned_team, subject, description, opened_at, sla_due_at, closed_at, resolution_code, resolution_notes, created_by, is_demo)
    select s.case_id, 1, iara.next_protocol(), 'SOLICITACAO_VAGA', 'WEB', 'MATRICULA_CONCLUIDA', 'NORMAL', s.student_id,
           (select sg.guardian_id from iara.student_guardians sg where sg.student_id = s.student_id and sg.is_primary limit 1), s.unit_id,
           'CENTRAL_VAGAS', 'Solicitação de vaga — ' || (select name from iara.grade_levels where id = s.grade_level_id),
           'Atendida por oferta da fila.', (s.enrollment_date - 40)::timestamptz, (s.enrollment_date - 30)::timestamptz,
           (s.enrollment_date)::timestamptz + interval '15 hours', 'MATRICULADO', 'Matrícula confirmada pela unidade.', v_staff1, true
    from sel s returning id
  ), entries as (
    insert into iara.waiting_list_entries (id, tenant_id, student_id, case_id, stage_id, grade_level_id, preferred_unit_id, demand_category,
                                           entered_at, status, created_by, is_demo, score_breakdown, rule_version)
    select s.entry_id, 1, s.student_id, s.case_id, s.stage_id, s.grade_level_id, s.unit_id, 'SEM_ATENDIMENTO',
           (s.enrollment_date - 38)::timestamptz, 'MATRICULATED', v_staff1, true, '[]', '2026.01'
    from sel s returning id
  )
  insert into iara.vacancy_offers (tenant_id, waiting_list_entry_id, student_id, class_id, unit_id, case_id, offered_at, expires_at, channel, status,
                                   accepted_at, response_channel, ranking_snapshot, idempotency_key, created_by, is_demo)
  select 1, s.entry_id, s.student_id, s.class_id, s.unit_id, s.case_id, (s.enrollment_date - 3)::timestamptz + interval '10 hours',
         (s.enrollment_date - 1)::timestamptz + interval '10 hours', 'WHATSAPP', 'ENROLLED',
         (s.enrollment_date - 2)::timestamptz + interval '9 hours', 'WHATSAPP',
         jsonb_build_object('motivo', '1º da fila da unidade/faixa com vaga ofertável', 'regras', '2026.01'), 'seed-hist-' || s.entry_id, v_staff2, true
  from sel s;
  update iara.enrollments e set entry_type = 'OFERTA_FILA'
  from iara.vacancy_offers o where o.status = 'ENROLLED' and o.student_id = e.student_id;

  -- histórico: recusas (voltaram à fila) e expirações (silêncio não é recusa)
  insert into iara.vacancy_offers (tenant_id, waiting_list_entry_id, student_id, class_id, unit_id, case_id, offered_at, expires_at, channel, status,
                                   declined_at, decline_reason, response_channel, ranking_snapshot, idempotency_key, created_by, is_demo)
  select 1, w.id, w.student_id, c.id, c.unit_id, w.case_id, w.entered_at + interval '20 days', w.entered_at + interval '22 days', 'WHATSAPP',
         z.st, case when z.st = 'DECLINED' then w.entered_at + interval '21 days' end,
         case when z.st = 'DECLINED' then iara.pick(array['Unidade distante do trabalho','Prefere aguardar a unidade preferida','Turno incompatível com o trabalho']) end,
         case when z.st = 'DECLINED' then 'WHATSAPP' end,
         jsonb_build_object('motivo', 'Vaga em unidade alternativa', 'regras', '2026.01'), 'seed-past-' || w.id, v_staff1, true
  from (select w.*, case when w.demand_category = 'RECUSOU_OFERTA' then 'DECLINED' else 'EXPIRED' end as st,
               row_number() over (partition by (w.demand_category = 'RECUSOU_OFERTA') order by random()) as rn
        from iara.waiting_list_entries w where w.status = 'WAITING' and w.id <> v_davi_entry
          and (w.demand_category = 'RECUSOU_OFERTA' or w.demand_category = 'SEM_ATENDIMENTO')) z
  join iara.waiting_list_entries w on w.id = z.id
  cross join lateral (select c.id, c.unit_id from iara.classes c where c.grade_level_id = w.grade_level_id and c.unit_id <> w.preferred_unit_id
                      order by random() limit 1) c
  where (z.st = 'DECLINED') or (z.st = 'EXPIRED' and z.rn <= 15);

  perform iara.recalculate_all_queues();

  -- =========================================================================
  -- 9. PROTOCOLOS ABERTOS — 744 + 58 reabertos por oferta = 802
  -- =========================================================================
  create temp table tmp_case (
    id uuid default gen_random_uuid(), case_type text, status text, student_id uuid, guardian_id uuid, unit_id integer,
    grade_level_id smallint, new_child boolean default false, opened_at timestamptz, channel text, priority text default 'NORMAL'
  ) on commit drop;

  -- 9a. solicitações de vaga novas (303): crianças ainda não inseridas na fila
  insert into tmp_case (case_type, status, new_child, grade_level_id, unit_id)
  select 'SOLICITACAO_VAGA', z.st, true, ug.grade_level_id, ug.unit_id
  from (select st, case when x < 0.74 then 1 when x < 0.9 then 2 else 3 + (floor(x * 1000)::int % 5) end as gid
        from (select st, random() as x
              from unnest(array_fill('NOVO'::text, array[70]) || array_fill('EM_ANALISE'::text, array[95]) || array_fill('AGUARDANDO_DOCUMENTOS'::text, array[80])
                          || array_fill('AGUARDANDO_FAMILIA'::text, array[36]) || array_fill('VAGA_ENCONTRADA'::text, array[22])) as st) z0) z
  cross join lateral (select ug.unit_id, ug.grade_level_id from tmp_ug ug
                      where ug.grade_level_id = z.gid and z.st is not null
                      order by power(random(), 1.0 / ug.n_classes) desc limit 1) ug;

  -- 9b. demais serviços (441) para alunos matriculados
  create temp table tmp_pool on commit drop as
  select student_id, unit_id, grade_level_id, row_number() over (order by random()) as rn from tmp_seat;
  create index on tmp_pool (rn);

  insert into tmp_case (case_type, status, student_id, unit_id, grade_level_id)
  select t.case_type,
         case when t.case_type = 'RECURSO' then 'RECURSO'
              when t.r < 0.30 then 'NOVO' when t.r < 0.75 then 'EM_ANALISE' when t.r < 0.90 then 'AGUARDANDO_DOCUMENTOS' else 'AGUARDANDO_FAMILIA' end,
         p.student_id, p.unit_id, p.grade_level_id
  from (select case_type, random() as r, row_number() over () as k
        from unnest(array_fill('TRANSFERENCIA'::text, array[88]) || array_fill('TROCA_TURNO'::text, array[26]) || array_fill('INTEGRAL'::text, array[18])
                    || array_fill('ATUALIZACAO_CADASTRAL'::text, array[58]) || array_fill('DOCUMENTO'::text, array[64]) || array_fill('TRANSPORTE'::text, array[42])
                    || array_fill('AEE'::text, array[30]) || array_fill('ALIMENTACAO'::text, array[14]) || array_fill('RECLAMACAO'::text, array[28])
                    || array_fill('DUVIDA'::text, array[20]) || array_fill('RECURSO'::text, array[12]) || array_fill('MUDANCA_ENDERECO'::text, array[10])
                    || array_fill('DESISTENCIA'::text, array[4]) || array_fill('ALTERACAO_RESPONSAVEL'::text, array[6]) || array_fill('MATRICULA'::text, array[21])) as case_type) t
  join tmp_pool p on p.rn = t.k;

  -- idade ~ U^2,2 × min(38, 1,6 × SLA): ~19% dos protocolos abertos com prazo vencido (realista)
  update tmp_case set opened_at = v_now - interval '1 day' * (power(random(), 2.2) * least(38, 1.6 * coalesce((select sla_days from iara.service_catalog s where s.code = tmp_case.case_type), 10)))
                                        - interval '1 hour' * floor(random() * 10),
                      channel = case when random() < 0.34 then 'WEB' when random() < 0.48 then 'WHATSAPP' when random() < 0.5 then 'PRESENCIAL'
                                     when random() < 0.5 then 'TELEFONE' when random() < 0.5 then 'ESCOLA' else 'EMAIL' end,
                      priority = case when random() < 0.08 then 'ALTA' when random() < 0.02 then 'URGENTE' else 'NORMAL' end;

  -- famílias novas para as solicitações de vaga
  create temp table tmp_casehh on commit drop as
  select c.id as case_id, gen_random_uuid() as address_id, gen_random_uuid() as guardian_id, gen_random_uuid() as student_id,
         iara.pick(surnames) as surname, ug.lat + km * cos(ang) / 111.32 as lat, ug.lng + km * sin(ang) / (111.32 * cos(radians(ug.lat))) as lng,
         ug.neighborhood, ug.postal_code, ug.macro, case when random() < 0.5 then 'F' else 'M' end as gender,
         (select code from iara.grade_levels where id = c.grade_level_id) as gcode
  from tmp_case c join tmp_ug ug on ug.unit_id = c.unit_id and ug.grade_level_id = c.grade_level_id
  cross join lateral (select 0.2 + random() * 2.8 as km, random() * 2 * pi() as ang where c.id is not null) d
  where c.new_child;
  insert into iara.addresses (id, tenant_id, street, number, neighborhood, postal_code, location, geocode_precision, geocode_source, territory_id, is_demo)
  select address_id, 1, iara.pick(streets), (10 + floor(random() * 2400))::int::text, neighborhood,
         regexp_replace(coalesce(postal_code, '87000-000'), '-\d{3}$', '-000'), iara.point(lat, lng), 'DEMO_APROXIMADO', 'DEMO — endereço fictício', macro, true
  from tmp_casehh;
  insert into iara.guardians (id, tenant_id, full_name, cpf, birth_date, gender, email, primary_phone, whatsapp_phone, address_id, occupation,
                              employment_status, cadunico_status, consent_flags, is_demo)
  select guardian_id, 1, iara.pick(adults_f) || ' ' || iara.pick(surnames) || ' ' || surname, iara.fake_cpf(),
         date '1982-01-01' + floor(random() * 8000)::int, 'F', null, '(44) 90000-' || lpad(floor(random() * 10000)::int::text, 4, '0'),
         '(44) 90000-' || lpad(floor(random() * 10000)::int::text, 4, '0'), address_id, iara.pick(occupations),
         case when random() < 0.5 then 'CLT' else 'Informal' end, random() < 0.3, '{"lgpd_ciencia": true}'::jsonb, true
  from tmp_casehh;
  insert into iara.students (id, tenant_id, full_name, birth_date, gender, status, address_id, avatar_seed, is_demo)
  select student_id, 1, case when gender = 'F' then iara.pick(kids_f) else iara.pick(kids_m) end || ' ' || iara.pick(surnames) || ' ' || surname,
         iara.demo_birthdate(gcode), gender, 'SEM_VINCULO', address_id, floor(random() * 1000)::int, true
  from tmp_casehh;
  insert into iara.student_guardians (student_id, guardian_id, relationship, is_primary)
  select student_id, guardian_id, 'MAE', true from tmp_casehh;
  update tmp_case c set student_id = h.student_id, guardian_id = h.guardian_id from tmp_casehh h where h.case_id = c.id;
  update tmp_case c set guardian_id = (select sg.guardian_id from iara.student_guardians sg where sg.student_id = c.student_id and sg.is_primary limit 1)
  where c.guardian_id is null;

  insert into iara.service_cases (id, tenant_id, protocol_number, case_type, channel, status, priority, student_id, guardian_id, unit_id,
                                  assigned_team, assigned_user_id, subject, description, opened_at, sla_due_at, created_by, is_demo)
  select c.id, 1, iara.next_protocol(), c.case_type, c.channel, c.status, c.priority, c.student_id, c.guardian_id, c.unit_id,
         case sc.sector when 'Central de Vagas' then 'CENTRAL_VAGAS' when 'Secretaria Escolar' then 'SECRETARIA_ESCOLAR'
                        when 'Gerência de Transporte Escolar' then 'TRANSPORTE' when 'Ouvidoria' then 'OUVIDORIA'
                        when 'Gerência de Apoio Pedagógico Interdisciplinar' then 'AEE' else 'ATENDIMENTO' end,
         case when c.status in ('EM_ANALISE', 'AGUARDANDO_DOCUMENTOS', 'AGUARDANDO_FAMILIA', 'VAGA_ENCONTRADA') and random() < 0.55
              then case when random() < 0.5 then v_staff1 else v_staff2 end end,
         case c.case_type
           when 'SOLICITACAO_VAGA' then 'Solicitação de vaga — ' || (select name from iara.grade_levels where id = c.grade_level_id)
           when 'TRANSFERENCIA' then iara.pick(array['Transferência por mudança de endereço','Transferência para ficar perto do trabalho','Transferência para a unidade do irmão'])
           when 'TROCA_TURNO' then iara.pick(array['Troca para o turno da manhã','Troca para o turno da tarde'])
           when 'INTEGRAL' then 'Pedido de período integral'
           when 'ATUALIZACAO_CADASTRAL' then iara.pick(array['Atualização de telefone','Atualização de endereço','Inclusão de responsável para retirada'])
           when 'DOCUMENTO' then iara.pick(array['Declaração de matrícula para o trabalho','Declaração de frequência — benefício social','Segunda via de histórico'])
           when 'TRANSPORTE' then iara.pick(array['Solicitação de transporte escolar','Mudança de ponto do transporte','Atraso recorrente do transporte'])
           when 'AEE' then iara.pick(array['Pedido de profissional de apoio','Avaliação para AEE','Adaptação de material'])
           when 'ALIMENTACAO' then iara.pick(array['Cardápio para restrição alimentar','Informação sobre alergia alimentar'])
           when 'RECLAMACAO' then iara.pick(array['Reclamação sobre atendimento na secretaria','Sugestão de melhoria na entrada da escola','Reclamação sobre fila de espera'])
           when 'DUVIDA' then iara.pick(array['Dúvida sobre documentos da matrícula','Dúvida sobre calendário','Dúvida sobre critérios da fila'])
           when 'RECURSO' then 'Recurso sobre posição na fila'
           when 'MUDANCA_ENDERECO' then 'Comunicação de mudança de endereço'
           when 'DESISTENCIA' then 'Desistência de vaga'
           when 'ALTERACAO_RESPONSAVEL' then 'Alteração de responsável legal'
           else 'Matrícula — conferência de documentos' end,
         'Registro de demonstração com dados fictícios.', c.opened_at, c.opened_at + (sc.sla_days || ' days')::interval,
         case when c.channel in ('WEB', 'WHATSAPP') then null else v_staff1 end, true
  from tmp_case c join iara.service_catalog sc on sc.code = c.case_type;

  insert into iara.documents (tenant_id, student_id, guardian_id, case_id, doc_type, status, file_name, received_at, is_demo)
  select 1, c.student_id, null, c.id, d.doc,
         case when c.status = 'AGUARDANDO_DOCUMENTOS' and d.doc <> 'CERTIDAO' then 'PENDENTE' when random() < 0.5 then 'RECEBIDO' else 'VALIDADO' end,
         null, c.opened_at + interval '1 hour', true
  from tmp_case c cross join (values ('CERTIDAO'), ('COMPROVANTE_ENDERECO'), ('CPF')) d(doc)
  where c.case_type = 'SOLICITACAO_VAGA';
  update iara.documents set file_name = lower(doc_type) || '_' || substr(id::text, 1, 6) || '.pdf' where status <> 'PENDENTE' and file_name is null;
  update iara.documents set received_at = null where status = 'PENDENTE';

  -- documentos de matrícula das ofertas aceitas (o que falta para concluir a matrícula)
  insert into iara.documents (tenant_id, student_id, case_id, doc_type, status, file_name, received_at, validated_at, is_demo)
  select 1, o.student_id, o.case_id, d.doc,
         case when random() < 0.45 then 'VALIDADO' when random() < 0.5 then 'RECEBIDO' else 'PENDENTE' end, null, v_now - interval '1 day', null, true
  from iara.vacancy_offers o cross join (values ('CERTIDAO'), ('CPF'), ('COMPROVANTE_ENDERECO'), ('CARTAO_SUS'), ('VACINACAO')) d(doc)
  where o.status in ('ACCEPTED', 'OFFERED');
  update iara.documents set validated_at = received_at + interval '6 hours' where status = 'VALIDADO' and validated_at is null;
  update iara.documents set received_at = null where status = 'PENDENTE';
  update iara.documents set file_name = lower(doc_type) || '_' || substr(id::text, 1, 6) || '.pdf' where status <> 'PENDENTE' and file_name is null;

  -- protocolos encerrados (histórico de SLA)
  insert into iara.service_cases (tenant_id, protocol_number, case_type, channel, status, priority, student_id, guardian_id, unit_id, assigned_team,
                                  subject, description, opened_at, sla_due_at, closed_at, resolution_code, resolution_notes, created_by, is_demo)
  select 1, iara.next_protocol(), t.case_type, case when random() < 0.4 then 'WHATSAPP' when random() < 0.5 then 'WEB' else 'PRESENCIAL' end,
         'ENCERRADO', 'NORMAL', s.student_id, (select sg.guardian_id from iara.student_guardians sg where sg.student_id = s.student_id and sg.is_primary limit 1),
         s.unit_id, 'ATENDIMENTO',
         case t.case_type when 'DUVIDA' then 'Dúvida respondida' when 'DOCUMENTO' then 'Declaração emitida' when 'ATUALIZACAO_CADASTRAL' then 'Cadastro atualizado'
                          when 'TRANSPORTE' then 'Transporte avaliado' else 'Atendimento concluído' end,
         'Registro histórico de demonstração.', t.opened, t.opened + interval '7 days', t.opened + ((0.2 + power(random(), 2) * 16) || ' days')::interval,
         case when t.case_type = 'DUVIDA' then 'ORIENTADO' when random() < 0.8 then 'RESOLVIDO' else 'ENCAMINHADO' end,
         'Atendimento concluído com orientação registrada.', v_staff2, true
  from (select iara.pick(array['DUVIDA','DUVIDA','DOCUMENTO','ATUALIZACAO_CADASTRAL','TRANSPORTE','TROCA_TURNO','ALIMENTACAO']) as case_type,
               v_now - ((40 + random() * 200) || ' days')::interval as opened, g
        from generate_series(1, 520) g) t
  join tmp_pool s on s.rn = t.g + 1000;

  -- =========================================================================
  -- 9b. Calibração: fila = 1.276 (aguardando + com oferta) · protocolos abertos = 802
  -- =========================================================================
  select count(*) into v_diff from iara.waiting_list_entries where status in ('WAITING', 'OFFERED');
  if v_diff > 1276 then
    update iara.waiting_list_entries w set status = 'CANCELLED'
    where w.id in (select x.id from iara.waiting_list_entries x
                   where x.status = 'WAITING' and x.demand_category = 'SEM_ATENDIMENTO' and x.id <> v_davi_entry
                     and not exists (select 1 from iara.vacancy_offers o where o.waiting_list_entry_id = x.id)
                   order by random() limit v_diff - 1276);
    perform iara.recalculate_all_queues();
  end if;

  select count(*) into v_diff from iara.service_cases where status not in ('ENCERRADO', 'MATRICULA_CONCLUIDA', 'NAO_ATENDIDO');
  if v_diff > 802 then
    update iara.service_cases set status = 'ENCERRADO', closed_at = least(opened_at + interval '6 hours', v_now),
           resolution_code = 'RESOLVIDO', resolution_notes = 'Atendimento concluído com orientação registrada.'
    where id in (select id from iara.service_cases where status in ('NOVO', 'EM_ANALISE')
                   and case_type in ('DUVIDA', 'ATUALIZACAO_CADASTRAL', 'DOCUMENTO', 'TROCA_TURNO') order by random() limit v_diff - 802);
  elsif v_diff < 802 then
    insert into iara.service_cases (tenant_id, protocol_number, case_type, channel, status, priority, student_id, guardian_id, unit_id, assigned_team,
                                    subject, description, opened_at, sla_due_at, is_demo)
    select 1, iara.next_protocol(), 'DUVIDA', 'WHATSAPP', 'NOVO', 'NORMAL', p.student_id,
           (select sg.guardian_id from iara.student_guardians sg where sg.student_id = p.student_id and sg.is_primary limit 1), p.unit_id, 'ATENDIMENTO',
           'Dúvida sobre documentos da matrícula', 'Registro de demonstração com dados fictícios.', v_now - ((random() * 3) || ' days')::interval,
           v_now + interval '1 day', true
    from tmp_pool p where p.rn between 6000 and 6000 + (802 - v_diff) - 1;
  end if;

  -- =========================================================================
  -- 10. HISTÓRICO DOS PROTOCOLOS (eventos)
  -- =========================================================================
  insert into iara.case_events (case_id, event_type, message, new_value, user_id, actor_label, visibility, occurred_at)
  select c.id, 'CRIADO',
         'Protocolo ' || c.protocol_number || ' aberto pelo canal ' || lower(replace(c.channel, '_', ' ')) || '.',
         'NOVO', c.created_by, coalesce((select display_name from iara.app_users where id = c.created_by), 'Cidadão (portal/WhatsApp)'), 'CIDADAO', c.opened_at
  from iara.service_cases c;
  insert into iara.case_events (case_id, event_type, message, old_value, new_value, user_id, actor_label, visibility, occurred_at)
  select c.id, 'STATUS', 'Atendimento em análise pela equipe responsável.', 'NOVO', 'EM_ANALISE', v_staff1, 'Carla Menezes · Central de Vagas (demo)', 'CIDADAO',
         c.opened_at + interval '5 hours'
  from iara.service_cases c where c.status <> 'NOVO';
  insert into iara.case_events (case_id, event_type, message, old_value, new_value, user_id, actor_label, visibility, occurred_at)
  select c.id, 'STATUS',
         case c.status when 'AGUARDANDO_DOCUMENTOS' then 'Documentos solicitados à família.'
                       when 'AGUARDANDO_FAMILIA' then 'Aguardando retorno da família por WhatsApp.'
                       when 'VAGA_ENCONTRADA' then 'Vaga compatível encontrada; aguardando validação da oferta.'
                       when 'RECURSO' then 'Recurso recebido e encaminhado para análise humana.'
                       when 'ENCERRADO' then coalesce(c.resolution_notes, 'Atendimento encerrado.')
                       when 'MATRICULA_CONCLUIDA' then 'Matrícula confirmada pela unidade.'
                       when 'VAGA_OFERTADA' then 'Vaga ofertada à família pelo 1º lugar na fila da unidade.'
                       else 'Atualização de status.' end,
         'EM_ANALISE', c.status, v_staff1, 'Carla Menezes · Central de Vagas (demo)', 'CIDADAO',
         coalesce(c.closed_at, least(c.opened_at + interval '1 day', v_now - interval '10 minutes'))
  from iara.service_cases c where c.status not in ('NOVO', 'EM_ANALISE');
  insert into iara.case_events (case_id, event_type, message, user_id, actor_label, visibility, occurred_at)
  select c.id, 'NOTA', iara.pick(array['Contato telefônico realizado com a responsável.','Família orientada sobre os critérios da fila.',
                                       'Conferido endereço no mapa: dentro do território da unidade.','Mensagem enviada pelo WhatsApp com a lista de documentos.']),
         v_staff2, 'Rodrigo Tanaka · Central de Vagas (demo)', 'INTERNA', c.opened_at + interval '3 hours'
  from iara.service_cases c where random() < 0.35;

  -- =========================================================================
  -- 11. NOTIFICAÇÕES (simuladas) e eventos de vaga
  -- =========================================================================
  insert into iara.notifications (tenant_id, guardian_id, student_id, case_id, channel, event_type, title, body, status, created_at)
  select 1, c.guardian_id, o.student_id, o.case_id, 'WHATSAPP', 'VAGA_OFERTADA', 'Vaga ofertada',
         'Há uma vaga para ' || split_part(s.full_name, ' ', 1) || ' na ' || u.name || ' (' || cl.class_name || ', ' || lower(cl.shift) ||
         '). Responda até ' || to_char(o.expires_at at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') || '.', 'SIMULADA', o.offered_at
  from iara.vacancy_offers o join iara.service_cases c on c.id = o.case_id join iara.students s on s.id = o.student_id
  join iara.education_units u on u.id = o.unit_id join iara.classes cl on cl.id = o.class_id
  where o.status in ('OFFERED', 'ACCEPTED');

  insert into iara.vacancy_events (tenant_id, class_id, unit_id, event_type, quantity, before_json, after_json, reference, user_id, actor_label, occurred_at)
  select 1, o.class_id, o.unit_id, 'RESERVA', 1, null, jsonb_build_object('status', o.status), 'Oferta ' || substr(o.id::text, 1, 8), o.created_by,
         'Central de Vagas (demo)', o.offered_at
  from iara.vacancy_offers o where o.status in ('OFFERED', 'ACCEPTED');
  insert into iara.vacancy_events (tenant_id, class_id, unit_id, event_type, quantity, after_json, reference, user_id, actor_label, occurred_at)
  select 1, b.class_id, c.unit_id, 'BLOQUEIO', b.seats, jsonb_build_object('motivo', b.reason), 'Bloqueio ' || substr(b.id::text, 1, 8), b.created_by,
         'Direção da unidade (demo)', b.created_at
  from iara.vacancy_blocks b join iara.classes c on c.id = b.class_id;
  insert into iara.vacancy_events (tenant_id, class_id, unit_id, event_type, quantity, before_json, after_json, reference, actor_label, occurred_at)
  select 1, c.id, c.unit_id, 'TRANSF_SAIDA', 1, jsonb_build_object('matriculas', c.active_enrollments_count + 1),
         jsonb_build_object('matriculas', c.active_enrollments_count), 'Transferência para outra rede', 'Secretaria escolar (demo)', v_now - interval '5 hours'
  from iara.classes c where c.unit_id = v_unit_maria and c.grade_level_id = 1 and c.offerable_vacancies_count >= 1
  order by c.offerable_vacancies_count desc limit 1;

  -- =========================================================================
  -- 12. CALIBRAÇÃO FINAL — exatamente 2.348 vagas ofertáveis
  -- =========================================================================
  perform set_config('iara.skip_counters', 'off', true);
  perform iara.recount_all_classes();
  for i in 1..60 loop
    select v_target_vac - sum(offerable_vacancies_count) into v_diff from iara.classes;
    exit when v_diff = 0;
    if v_diff > 0 then
      update iara.classes set authorized_capacity = authorized_capacity + 1
      where id in (select id from iara.classes where grade_level_id <> 8 and unit_id <> v_unit_maria and offerable_vacancies_count between 1 and 6
                   order by random() limit v_diff);
    else
      update iara.classes set authorized_capacity = authorized_capacity - 1
      where id in (select id from iara.classes where offerable_vacancies_count >= 2 and unit_id <> v_unit_maria order by random() limit -v_diff);
    end if;
  end loop;

  -- =========================================================================
  -- 13. CONVERSAS DA IARA (WhatsApp simulado) — histórico para a caixa de entrada
  -- =========================================================================
  perform iara.demo_seed_conversations(v_staff1);

  update iara.tenants set settings = settings || jsonb_build_object('demo_baseline_at', v_now, 'demo_unit_maria', v_unit_maria,
         'demo_guardian_maria', v_maria, 'demo_student_ana', v_ana, 'demo_student_davi', v_davi, 'demo_entry_davi', v_davi_entry,
         'demo_case_davi', v_davi_case, 'demo_guardian_jorge', v_jorge, 'demo_address_maria', v_maria_hh)
  where id = 1;

  select jsonb_build_object(
    'turmas_demo', (select count(*) from iara.classes),
    'matriculas_ativas', (select count(*) from iara.enrollments where status = 'ACTIVE'),
    'alunos', (select count(*) from iara.students),
    'responsaveis', (select count(*) from iara.guardians),
    'vagas_ofertaveis', (select sum(offerable_vacancies_count) from iara.classes),
    'fila_aguardando_mais_ofertadas', (select count(*) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED')),
    'protocolos_abertos', (select count(*) from iara.service_cases where status not in ('ENCERRADO', 'MATRICULA_CONCLUIDA', 'NAO_ATENDIDO')),
    'ofertas_pendentes', (select count(*) from iara.vacancy_offers where status in ('OFFERED', 'ACCEPTED')),
    'unidade_cenario_cidadao', v_unit_maria,
    'posicao_davi', (select position from iara.waiting_list_entries where id = v_davi_entry)
  ) into v_result;

  perform set_config('iara.skip_audit', 'off', true);
  insert into iara.audit_log (user_id, actor_label, actor_role, action, entity_type, entity_id, summary, after_json)
  values (v_sys, 'Rotina automática IARA', 'SISTEMA', 'DEMO_SEED', 'demo', 'baseline',
          'Camada operacional de demonstração gerada (dados pessoais fictícios; estrutura de turmas do Censo 2025).', v_result);
  return v_result;
end $fn$;

commit;
