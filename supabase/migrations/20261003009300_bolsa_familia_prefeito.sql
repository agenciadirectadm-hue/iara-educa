-- IARA Educa — 093 · Bolsa Família na escola: visão agregada do Prefeito e assunto do Oráculo
-- Só números, sem nomes, como o Prefeito pediu: quantos alunos estão em famílias que recebem o Bolsa Família, quantos deixaram
-- de receber por não alcançar a frequência mínima (definição do Prefeito: abaixo do mínimo em ao menos um período do ano; quem
-- aplica o efeito é o MDS, e a primeira vez costuma ser advertência) e quantos têm recebido assiduamente (sempre dentro do
-- mínimo). Também: acompanhados (4 a 17 anos) e abaixo em dois ou mais períodos.
-- A conta é a mesma do Sistema Presença (chamada diária, mínimo pela idade, recesso), feita de uma vez para o ano todo.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

insert into iara.permissions (code, description, is_sensitive) values
  ('bolsa_familia.resumo', 'Ver os números agregados da frequência dos alunos do Bolsa Família (sem nomes)', false)
on conflict (code) do update set description = excluded.description;
insert into iara.role_permissions (role_code, permission_code) values
  ('PREFEITO', 'bolsa_familia.resumo'), ('SECRETARIO', 'bolsa_familia.resumo'), ('SUPERINTENDENCIA', 'bolsa_familia.resumo'), ('GERENCIA_EI', 'bolsa_familia.resumo')
on conflict do nothing;

-- frequência do ano inteiro, por aluno do Bolsa Família e período: acompanhado (4 a 17 anos, com chamada) e abaixo do mínimo
create or replace function iara.presenca_ano(p_ano integer, p_units integer[] default null)
returns table (student_id uuid, unit_id integer, area integer, periodo integer, acompanhado boolean, abaixo boolean)
language plpgsql stable security definer set search_path = iara, public
as $$
#variable_conflict use_column
declare
  v_ini date := make_date(p_ano, 2, 1);
  v_hoje date := iara.hoje_local();
  v_fim date := least(make_date(p_ano, 11, 30), iara.hoje_local());
  v_min45 integer := coalesce(nullif(iara.setting('presenca_minimo_4a5'), '')::int, 60);
  v_min617 integer := coalesce(nullif(iara.setting('presenca_minimo_6a17'), '')::int, 75);
begin
  return query
  with meses as materialized (
    select q.m_ini, (q.m_ini + interval '1 month - 1 day')::date m_fim, extract(month from q.m_ini)::int / 2 per,
           (select count(*) from generate_series(q.m_ini, (q.m_ini + interval '1 month - 1 day')::date, interval '1 day') d
             where extract(isodow from d) between 1 and 5
               and exists (select 1 from iara.calendario_eventos e where e.tipo = 'RECESSO' and e.suspende_aulas and e.abrangencia = 'REDE' and d::date between e.inicio and e.fim)) recesso,
           (select count(*) from generate_series(q.m_ini, (q.m_ini + interval '1 month - 1 day')::date, interval '1 day') d
             where extract(isodow from d) between 1 and 5 and d::date between (iara.setting('ano_letivo_inicio'))::date and (iara.setting('ano_letivo_fim'))::date
               and not exists (select 1 from iara.calendario_eventos e where e.tipo = 'FERIADO' and d::date between e.inicio and e.fim)) uteis
    from (select (v_ini + make_interval(months => k))::date m_ini from generate_series(0, 9) k) q
    where q.m_ini <= v_fim),
  bf as (
    select distinct sg.student_id sid from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
    where sg.end_date is null and g.benefits ? 'Bolsa Família'),
  mat as (
    select distinct on (e.student_id) e.student_id sid, e.unit_id uid, e.class_id cid, coalesce(e.start_date, e.enrollment_date) inicio, e.end_date fim
    from iara.enrollments e join bf on bf.sid = e.student_id
    where (p_units is null or e.unit_id = any (p_units))
      and coalesce(e.start_date, e.enrollment_date) <= v_fim
      and (e.status = 'ACTIVE' or (e.end_date is not null and e.end_date >= v_ini))
    order by e.student_id, (e.status = 'ACTIVE') desc, e.end_date desc nulls first),
  base as materialized (
    select m.*, s.birth_date nasc, u.macro_territory_id ap
    from mat m join iara.students s on s.id = m.sid join iara.education_units u on u.id = m.uid),
  dias as (
    select b.sid, date_trunc('month', r.data)::date m_ini, count(*) n
    from base b join iara.frequencia_registros r on r.class_id = b.cid
    where r.data between greatest(v_ini, b.inicio) and least(v_fim, coalesce(b.fim, v_fim))
    group by 1, 2),
  falt as (
    select b.sid, date_trunc('month', r.data)::date m_ini, count(*) n
    from base b join iara.frequencia_faltas fa on fa.student_id = b.sid
    join iara.frequencia_registros r on r.id = fa.registro_id and r.class_id = b.cid
    where r.data between greatest(v_ini, b.inicio) and least(v_fim, coalesce(b.fim, v_fim))
    group by 1, 2),
  mes as (
    select b.sid, b.uid, b.ap, me.per,
           case when age(make_date(p_ano, 2 * me.per, 1), b.nasc) < interval '6 years' then v_min45 else v_min617 end minimo,
           age(make_date(p_ano, 2 * me.per, 1), b.nasc) between interval '4 years' and interval '18 years' - interval '1 day' idade_ok,
           coalesce(d.n, 0) dias, coalesce(f.n, 0) faltas, me.uteis > 0 and me.recesso * 2 >= me.uteis integral
    from base b cross join meses me
    left join dias d on d.sid = b.sid and d.m_ini = me.m_ini
    left join falt f on f.sid = b.sid and f.m_ini = me.m_ini)
  select mes.sid, mes.uid, mes.ap, mes.per,
         bool_and(mes.idade_ok) and (sum(mes.dias) > 0 or bool_or(mes.integral)),
         bool_and(mes.idade_ok) and bool_or(case when mes.dias > 0 and not mes.integral then 100.0 * (mes.dias - mes.faltas) / mes.dias < mes.minimo else false end)
  from mes group by mes.sid, mes.uid, mes.ap, mes.per;
end $$;

-- os números do Bolsa Família na escola (cidade, unidade ou região): só contagens. Com p_detalhe, também regiões e unidades
-- (recortes com menos de 3 alunos ficam em sigilo). O ano é calculado uma vez só.
drop function if exists iara.bolsa_familia_numeros(integer[], integer);
create or replace function iara.bolsa_familia_numeros(p_units integer[], p_ano integer, p_detalhe boolean default false) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  with pa as materialized (select * from iara.presenca_ano(p_ano, p_units)),
  al as materialized (select student_id, unit_id, area, count(*) filter (where acompanhado) periodos, count(*) filter (where acompanhado and abaixo) abaixo
                      from pa group by 1, 2, 3),
  ativos as (
    select distinct s.id, s.birth_date, sg.guardian_id from iara.students s
    join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
    join iara.student_guardians sg on sg.student_id = s.id and sg.end_date is null
    join iara.guardians g on g.id = sg.guardian_id and g.benefits ? 'Bolsa Família'
    where p_units is null or e.unit_id = any (p_units))
  select jsonb_build_object(
    'familias', (select count(distinct guardian_id) from ativos),
    'alunos', (select count(distinct id) from ativos),
    'creche', (select count(distinct id) from ativos where age(iara.hoje_local(), birth_date) < interval '4 years'),
    'acompanhados', (select count(*) from al where periodos > 0),
    'assiduos', (select count(*) from al where periodos > 0 and abaixo = 0),
    'abaixo_1', (select count(*) from al where abaixo = 1),
    'abaixo_2', (select count(*) from al where abaixo >= 2),
    'deixaram_de_receber', (select count(*) from al where abaixo >= 1),
    'periodos', (select coalesce(jsonb_agg(jsonb_build_object('periodo', periodo, 'acompanhados', a, 'abaixo', b) order by periodo), '[]')
                 from (select periodo, count(*) filter (where acompanhado) a, count(*) filter (where acompanhado and abaixo) b from pa group by periodo) q))
  || case when p_detalhe then jsonb_build_object(
    'por_regiao', (select coalesce(jsonb_agg(jsonb_build_object('nome', t.name, 'acompanhados', q.n,
                       'abaixo', case when q.b between 1 and 2 then null else q.b end, 'assiduos', q.n - q.b) order by q.b desc, t.name), '[]')
                   from (select area, count(*) filter (where periodos > 0) n, count(*) filter (where abaixo > 0) b from al group by area) q
                   join iara.territories t on t.id = q.area where q.n >= 3),
    'unidades_mais_abaixo', (select coalesce(jsonb_agg(jsonb_build_object('nome', u.short_name, 'acompanhados', q.n, 'abaixo', q.b) order by q.b desc, q.n desc), '[]')
                             from (select unit_id, count(*) filter (where periodos > 0) n, count(*) filter (where abaixo > 0) b from al group by unit_id
                                   having count(*) filter (where abaixo > 0) >= 3 order by 3 desc limit 10) q
                             join iara.education_units u on u.id = q.unit_id)) else '{}'::jsonb end
$$;

-- a conta da cidade passa por um milhão de chamadas do ano: fica guardada por 30 minutos (só números agregados)
create table if not exists iara.bolsa_familia_cache (
  ano smallint primary key,
  dados jsonb not null,
  gerado_em timestamptz not null default now()
);
alter table iara.bolsa_familia_cache enable row level security;

-- visão do Prefeito (e da Secretaria): cidade, regiões e unidades. p: ano?, atualizar? (refaz a conta agora)
create or replace function api.bolsa_familia_resumo(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ano integer := coalesce(nullif(p ->> 'ano', '')::int, (iara.presenca_periodo_atual())[1]);
  c iara.bolsa_familia_cache;
begin
  perform iara.require_perm('bolsa_familia.resumo');
  select * into c from iara.bolsa_familia_cache where ano = v_ano;
  if c.ano is null or c.gerado_em < now() - interval '30 minutes' or coalesce((p ->> 'atualizar')::boolean, false) then
    insert into iara.bolsa_familia_cache (ano, dados, gerado_em) values (v_ano, iara.bolsa_familia_numeros(null, v_ano, true), now())
    on conflict (ano) do update set dados = excluded.dados, gerado_em = excluded.gerado_em
    returning * into c;
  end if;
  return c.dados || jsonb_build_object(
    'ano', v_ano, 'gerado_em', c.gerado_em,
    'rotulos', to_jsonb(array['Fevereiro e março', 'Abril e maio', 'Junho e julho', 'Agosto e setembro', 'Outubro e novembro']),
    'periodo_atual', (iara.presenca_periodo_atual())[2],
    'nota', 'Alunos de famílias com o Bolsa Família declarado no cadastro do responsável. Frequência calculada da chamada diária, '
            || 'com o mínimo da idade (60% de 4 a 5 anos, 75% de 6 a 17). "Deixaram de receber" = abaixo do mínimo em ao menos um '
            || 'período do ano; o efeito no benefício é aplicado pelo MDS (a primeira vez costuma ser advertência). '
            || 'Recortes com menos de 3 alunos ficam em sigilo.');
end $$;

-- o Oráculo ganha o assunto bolsa_familia (mesmas funções da 088, com o novo ramo)
-- os números de um tópico, na cidade, numa unidade ou numa região (unidades da região)
create or replace function iara.oraculo_numeros(p_topico text, p_unit integer, p_area integer) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_hoje date := iara.hoje_local();
  v_units integer[];
  v_nome text;
  n jsonb := '[]';
  v_presenca numeric;
  v_bf jsonb;
begin
  if p_unit is not null then
    v_units := array[p_unit];
    select short_name into v_nome from iara.education_units where id = p_unit;
  elsif p_area is not null then
    v_units := array(select id from iara.education_units where macro_territory_id = p_area);
    select name into v_nome from iara.territories where id = p_area;
  else
    v_units := array(select id from iara.education_units);
    v_nome := 'Maringá';
  end if;

  case p_topico
  when 'matriculas' then
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Alunos matriculados', 'valor', (select count(*) from iara.enrollments where status = 'ACTIVE' and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Turmas', 'valor', (select count(*) from iara.classes where unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Matrículas no Censo Escolar 2025', 'valor', (select sum(public_enrollments) from iara.education_units where id = any (v_units))));
  when 'fila' then
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Crianças na fila de espera', 'valor', (select count(*) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED') and preferred_unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Na fila da creche', 'valor', (select count(*) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED') and grade_level_id = 1 and preferred_unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Com oferta de vaga em aberto', 'valor', (select count(*) from iara.waiting_list_entries where status = 'OFFERED' and preferred_unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Espera média (dias)', 'valor', (select round(avg(v_hoje - entered_at::date)) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED') and preferred_unit_id = any (v_units))));
  when 'vagas' then
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Vagas que podem ser oferecidas', 'valor', (select sum(offerable_vacancies_count) from iara.classes where unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Turmas com vaga', 'valor', (select count(*) from iara.classes where offerable_vacancies_count > 0 and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Vagas de creche', 'valor', (select sum(offerable_vacancies_count) from iara.classes where grade_level_id = 1 and unit_id = any (v_units))));
  when 'creche' then
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Vagas de creche', 'valor', (select coalesce(sum(offerable_vacancies_count), 0) from iara.classes where grade_level_id = 1 and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Crianças esperando creche', 'valor', (select count(*) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED') and grade_level_id = 1 and preferred_unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Matriculados na creche', 'valor', (select count(*) from iara.enrollments e join iara.classes c on c.id = e.class_id where e.status = 'ACTIVE' and c.grade_level_id = 1 and e.unit_id = any (v_units))));
  when 'frequencia' then
    with reg as (select r.id, r.class_id from iara.frequencia_registros r join iara.classes c on c.id = r.class_id where r.data >= v_hoje - 30 and c.unit_id = any (v_units)),
         poss as (select sum((select count(*) from iara.enrollments e where e.class_id = reg.class_id and e.status = 'ACTIVE')) n from reg),
         fal as (select count(*) n from iara.frequencia_faltas f join reg on reg.id = f.registro_id)
    select round(100.0 - 100.0 * fal.n / nullif(poss.n, 0), 1) into v_presenca from poss, fal;
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Presença nos últimos 30 dias', 'valor', v_presenca, 'sufixo', '%', 'casas', 1),
      jsonb_build_object('rotulo', 'Alunos em alerta de frequência', 'valor', (select count(*) from iara.frequencia_alertas where situacao <> 'RESOLVIDO' and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Casos de busca ativa abertos', 'valor', (select count(*) from iara.busca_ativa_casos where situacao in ('ABERTO', 'EM_ACOMPANHAMENTO') and unit_id = any (v_units))));
  when 'ocorrencias' then
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Ocorrências nos últimos 90 dias', 'valor', (select count(*) from iara.ocorrencias where ocorrida_em >= now() - interval '90 days' and tipo <> 'ELOGIO' and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Graves', 'valor', (select count(*) from iara.ocorrencias where ocorrida_em >= now() - interval '90 days' and gravidade = 'GRAVE' and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Com violência', 'valor', (select count(*) from iara.ocorrencias where ocorrida_em >= now() - interval '90 days' and cardinality(violencia) > 0 and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Em aberto', 'valor', (select count(*) from iara.ocorrencias where situacao <> 'ENCERRADA' and tipo <> 'ELOGIO' and unit_id = any (v_units))));
  when 'profissionais' then
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Profissionais', 'valor', (select count(*) from iara.staff where unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Professores', 'valor', (select count(*) from iara.staff where role = 'PROFESSOR' and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Educadores infantis', 'valor', (select count(*) from iara.staff where role = 'EDUCADOR' and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Auxiliares e AEE', 'valor', (select count(*) from iara.staff where role in ('AUXILIAR', 'AEE') and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Com pós-graduação', 'valor', (select round(100.0 * count(*) filter (where iara.formacao_nivel(escolaridade) >= 4) / nullif(count(*) filter (where iara.formacao_nivel(escolaridade) is not null), 0))
                                                                  from iara.staff where role in ('PROFESSOR', 'EDUCADOR', 'AEE') and unit_id = any (v_units)), 'sufixo', '%'));
  when 'transporte' then
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Rotas ativas', 'valor', (select count(*) from iara.transporte_rotas where situacao = 'ATIVA' and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Alunos transportados', 'valor', (select count(*) from iara.transporte_alunos ta join iara.transporte_rotas r on r.id = ta.rota_id where ta.fim is null and r.unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Viagens não realizadas (30 dias)', 'valor', (select count(*) from iara.transporte_viagens v join iara.transporte_rotas r on r.id = v.rota_id
                                                                                where v.situacao = 'NAO_REALIZADA' and v.data >= v_hoje - 30 and r.unit_id = any (v_units))));
  when 'alfabetizacao' then
    n := (with so as (select distinct on (x.student_id) x.student_id, x.nivel, x.class_id,
                             ((extract(year from age(x.data, s.birth_date)) * 12 + extract(month from age(x.data, s.birth_date))))::int meses
                      from iara.alfabetizacao_sondagens x join iara.students s on s.id = x.student_id
                      join iara.classes c on c.id = x.class_id
                      where x.ano = extract(year from v_hoje)::int and c.unit_id = any (v_units) order by x.student_id, x.data desc),
               sx as (select iara.alfa_situacao_idade(nivel, meses) sit from so)
          select jsonb_build_array(
            jsonb_build_object('rotulo', 'Crianças avaliadas', 'valor', count(*)),
            jsonb_build_object('rotulo', 'No nível esperado ou acima', 'valor', round(100.0 * count(*) filter (where sit <> 'ABAIXO') / nullif(count(*), 0)), 'sufixo', '%'),
            jsonb_build_object('rotulo', 'Abaixo do esperado para a idade', 'valor', count(*) filter (where sit = 'ABAIXO')))
          from sx);
  when 'busca_ativa' then
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Casos de busca ativa abertos', 'valor', (select count(*) from iara.busca_ativa_casos where situacao in ('ABERTO', 'EM_ACOMPANHAMENTO') and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Urgentes', 'valor', (select count(*) from iara.busca_ativa_casos where situacao in ('ABERTO', 'EM_ACOMPANHAMENTO') and urgente and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Crianças que voltaram à escola', 'valor', (select count(*) from iara.busca_ativa_casos where situacao = 'RETORNOU' and unit_id = any (v_units))));
  when 'unidades' then
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Unidades', 'valor', cardinality(v_units)),
      jsonb_build_object('rotulo', 'CMEIs', 'valor', (select count(*) from iara.education_units where unit_type = 'CMEI' and id = any (v_units))),
      jsonb_build_object('rotulo', 'Escolas', 'valor', (select count(*) from iara.education_units where unit_type = 'ESCOLA' and id = any (v_units))));
  when 'bolsa_familia' then
    v_bf := iara.bolsa_familia_numeros(v_units, (iara.presenca_periodo_atual())[1]);
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Alunos em famílias que recebem o Bolsa Família', 'valor', v_bf -> 'alunos'),
      jsonb_build_object('rotulo', 'Deixaram de receber por não alcançar a frequência mínima (no ano)', 'valor', v_bf -> 'deixaram_de_receber'),
      jsonb_build_object('rotulo', 'Têm recebido assiduamente (sempre dentro do mínimo)', 'valor', v_bf -> 'assiduos'),
      jsonb_build_object('rotulo', 'Com a frequência acompanhada (4 a 17 anos)', 'valor', v_bf -> 'acompanhados'),
      jsonb_build_object('rotulo', 'Abaixo do mínimo em dois ou mais períodos', 'valor', v_bf -> 'abaixo_2'));
  when 'cadastros' then
    n := (with al as (select cardinality(iara.aluno_pendencias(s, exists (select 1 from iara.student_guardians sg where sg.student_id = s.id and sg.end_date is null))) = 0 ok
                      from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' where e.unit_id = any (v_units))
          select jsonb_build_array(
            jsonb_build_object('rotulo', 'Cadastros de alunos completos', 'valor', round(100.0 * count(*) filter (where ok) / nullif(count(*), 0), 1), 'sufixo', '%', 'casas', 1),
            jsonb_build_object('rotulo', 'Cadastros a completar', 'valor', count(*) filter (where not ok)))
          from al);
  else  -- visão geral
    n := jsonb_build_array(
      jsonb_build_object('rotulo', 'Unidades', 'valor', cardinality(v_units)),
      jsonb_build_object('rotulo', 'Alunos matriculados', 'valor', (select count(*) from iara.enrollments where status = 'ACTIVE' and unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Crianças na fila de espera', 'valor', (select count(*) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED') and preferred_unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Vagas que podem ser oferecidas', 'valor', (select sum(offerable_vacancies_count) from iara.classes where unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Profissionais', 'valor', (select count(*) from iara.staff where unit_id = any (v_units))),
      jsonb_build_object('rotulo', 'Ocorrências nos últimos 90 dias', 'valor', (select count(*) from iara.ocorrencias where ocorrida_em >= now() - interval '90 days' and tipo <> 'ELOGIO' and unit_id = any (v_units))));
    p_topico := 'visao_geral';
  end case;
  return jsonb_build_object('topico', p_topico, 'recorte', v_nome, 'unidade', p_unit, 'area', p_area, 'numeros', n,
    'nota', 'Dados da demonstração do IARA Educa (Censo Escolar 2025 para as matrículas oficiais). Só números agregados.');
end $$;

-- sem a chave da Anthropic: palavras da pergunta → tópico e recorte → números → resposta em português
create or replace function api.oraculo_perguntar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_perg text := btrim(coalesce(p ->> 'pergunta', ''));
  v_n text := iara.norm(coalesce(p ->> 'pergunta', ''));
  v_topico text;
  v_rec jsonb := iara.oraculo_recorte(p ->> 'pergunta');
  r jsonb;
  v_texto text;
  x jsonb;
  v_partes text[] := '{}';
begin
  perform iara.require_perm('oraculo.prefeito');
  if length(v_perg) < 3 then
    raise exception 'Faça uma pergunta.' using errcode = '22023';
  end if;
  v_topico := case
    when v_n ~ 'bolsa|beneficio|condicionalidade|sistema presenca|cadunico' then 'bolsa_familia'
    when v_n ~ 'creche|bercario' then 'creche'
    when v_n ~ 'fila|espera|aguard' then 'fila'
    when v_n ~ 'vaga' then 'vagas'
    when v_n ~ 'frequenc|presenc|falta|ausen' then 'frequencia'
    when v_n ~ 'ocorrenc|violenc|bullying|briga|acidente|indisciplina' then 'ocorrencias'
    when v_n ~ 'professor|profissiona|servidor|educador|auxiliar|docente|funcionari' then 'profissionais'
    when v_n ~ 'transporte|onibus|rota|van|veicul|motorista' then 'transporte'
    when v_n ~ 'alfabetiz|leitura|escrita|sondagem|ler e escrever' then 'alfabetizacao'
    when v_n ~ 'busca ativa|evasao|abandono' then 'busca_ativa'
    when v_n ~ 'cadastr|documento' then 'cadastros'
    when v_n ~ 'matricul|aluno|estudante' then 'matriculas'
    when v_n ~ 'unidade|escola|cmei' then 'unidades'
    else 'visao_geral' end;
  r := iara.oraculo_numeros(v_topico, (v_rec ->> 'unidade')::int, (v_rec ->> 'area')::int);
  for x in select * from jsonb_array_elements(r -> 'numeros') loop
    v_partes := v_partes || ((x ->> 'rotulo') || ': '
                 || iara.num_br((x ->> 'valor')::numeric, coalesce((x ->> 'casas')::int, 0)) || coalesce(x ->> 'sufixo', ''));
  end loop;
  v_texto := 'Em ' || (r ->> 'recorte') || ' — ' || array_to_string(v_partes, '; ') || '.';
  insert into iara.oraculo_perguntas (user_id, pergunta, canal, modo, resposta, ferramentas, is_demo)
  values (iara.current_user_id(), v_perg, coalesce(nullif(p ->> 'canal', ''), 'TEXTO'), 'REGRAS', v_texto,
          jsonb_build_array(jsonb_build_object('topico', v_topico, 'unidade', v_rec -> 'unidade', 'area', v_rec -> 'area')), iara.demo_mode());
  return r || jsonb_build_object('pergunta', v_perg, 'resposta', v_texto, 'modo', 'REGRAS');
end $$;

revoke all on function iara.presenca_ano(integer, integer[]), iara.bolsa_familia_numeros(integer[], integer, boolean) from public;

-- a conta guardada é refeita com os campos desta versão
delete from iara.bolsa_familia_cache;

commit;
