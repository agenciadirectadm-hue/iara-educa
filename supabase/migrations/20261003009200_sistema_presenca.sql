-- IARA Educa — 092 · Sistema Presença (MEC): frequência dos alunos do Bolsa Família pronta para lançar
-- O Sistema Presença não tem API: a escola lança, a cada período de dois meses (fev-mar, abr-mai, jun-jul, ago-set, out-nov),
-- a frequência de cada estudante do Bolsa Família e, abaixo do mínimo, o motivo. Aqui o IARA calcula o percentual de cada mês
-- a partir da chamada diária, compara com o mínimo da idade (Lei 14.601/2023: 60% de 4 a 6 anos incompletos, 75% de 6 a 18
-- incompletos; valores em tenants.settings), sugere a categoria do motivo (justificativas, busca ativa, transporte), aponta a
-- escola de destino de quem foi transferido e os dias letivos sem chamada, e deixa marcar quem já foi lançado.
-- O código oficial do motivo continua sendo escolhido na tabela do Sistema Presença.
-- Beneficiários: pelo benefício declarado no cadastro do responsável. A lista oficial do período vem do próprio Sistema
-- Presença (próxima etapa: importar o arquivo que o coordenador municipal baixa).
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

insert into iara.permissions (code, description, is_sensitive) values
  ('presenca.registrar', 'Preparar e acompanhar o lançamento da frequência do Bolsa Família no Sistema Presença (MEC)', true)
on conflict (code) do update set description = excluded.description;
insert into iara.role_permissions (role_code, permission_code) values
  ('DIRETOR_UNIDADE', 'presenca.registrar'), ('SECRETARIA_ESCOLAR', 'presenca.registrar'),
  ('SECRETARIO', 'presenca.registrar'), ('SUPERINTENDENCIA', 'presenca.registrar'), ('GERENCIA_EI', 'presenca.registrar')
on conflict do nothing;

update iara.tenants set settings = settings || jsonb_build_object('presenca_minimo_4a5', 60, 'presenca_minimo_6a17', 75)
where id = 1 and not settings ? 'presenca_minimo_4a5';

create table if not exists iara.presenca_lancamentos (
  student_id uuid not null references iara.students(id) on delete cascade,
  ano smallint not null,
  periodo smallint not null check (periodo between 1 and 5),
  unit_id integer references iara.education_units(id),
  lancado_em timestamptz not null default now(),
  lancado_por_label text,
  is_demo boolean not null default true,
  primary key (student_id, ano, periodo)
);
alter table iara.presenca_lancamentos enable row level security;

-- unidade que o perfil pode ver: a própria (perfil de unidade) ou a escolhida (perfil da rede)
create or replace function iara.presenca_unidade_acesso(p_unit integer) returns integer
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else coalesce(p_unit, (iara.setting('demo_unit_maria'))::int) end;
begin
  perform iara.require_perm('presenca.registrar');
  if v is null or not iara.can_access_unit(v) then
    raise exception 'Unidade fora do seu acesso.' using errcode = '42501';
  end if;
  return v;
end $$;

-- período atual: o bimestre em curso (dezembro e janeiro ficam no de outubro e novembro)
create or replace function iara.presenca_periodo_atual() returns integer[]
language sql stable
as $$
  select array[extract(year from d)::int - case when extract(month from d) = 1 then 1 else 0 end,
               case when extract(month from d) in (12, 1) then 5 else greatest(1, least(5, extract(month from d)::int / 2)) end]
  from (select iara.hoje_local() d) x
$$;

-- categoria do motivo pela justificativa escrita
create or replace function iara.presenca_categoria(p_texto text) returns text
language sql immutable
as $$
  select case
    when p_texto is null or btrim(p_texto) = '' then null
    when iara.norm(p_texto) ~ 'transporte|onibus|van |rota' then 'TRANSPORTE'
    when iara.norm(p_texto) ~ 'falec|luto|velorio|enterro|familia|parente|viagem|mudanc' then 'FAMILIA'
    when iara.norm(p_texto) ~ 'doen|virose|febre|gripe|consulta|medic|exame|dente|dentist|hospital|atestado|saude|dor |dor$|vacina|posto|tratamento|cirurg' then 'DOENCA'
    else 'OUTRO' end
$$;

-- alunos do Bolsa Família das unidades, com a frequência de cada mês do período. Uma linha por aluno; nunca sai do banco
-- sem passar pela permissão (api.*).
create or replace function iara.presenca_alunos(p_units integer[], p_ano integer, p_per integer)
returns table (student_id uuid, unit_id integer, dados jsonb, abaixo boolean, lancado boolean)
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_ini date := make_date(p_ano, 2 * p_per, 1);
  v_fim date := (make_date(p_ano, 2 * p_per, 1) + interval '2 months - 1 day')::date;
  v_hoje date := iara.hoje_local();
  v_min45 integer := coalesce(nullif(iara.setting('presenca_minimo_4a5'), '')::int, 60);
  v_min617 integer := coalesce(nullif(iara.setting('presenca_minimo_6a17'), '')::int, 75);
begin
  return query
  with meses as materialized (
    select k, m_ini, (m_ini + interval '1 month - 1 day')::date m_fim,
           -- dias letivos previstos (até ontem: a chamada de hoje ainda pode estar aberta) e dias de recesso: recesso de 50% ou mais do mês dá frequência integral
           (select count(*) from generate_series(m_ini, least((m_ini + interval '1 month - 1 day')::date, v_hoje - 1), interval '1 day') d
             where extract(isodow from d) between 1 and 5 and iara.dia_letivo(d::date)) previstos,
           (select count(*) from generate_series(m_ini, (m_ini + interval '1 month - 1 day')::date, interval '1 day') d
             where extract(isodow from d) between 1 and 5
               and exists (select 1 from iara.calendario_eventos e where e.tipo = 'RECESSO' and e.suspende_aulas and e.abrangencia = 'REDE' and d::date between e.inicio and e.fim)) recesso,
           (select count(*) from generate_series(m_ini, (m_ini + interval '1 month - 1 day')::date, interval '1 day') d
             where extract(isodow from d) between 1 and 5 and d::date between (iara.setting('ano_letivo_inicio'))::date and (iara.setting('ano_letivo_fim'))::date
               and not exists (select 1 from iara.calendario_eventos e where e.tipo = 'FERIADO' and d::date between e.inicio and e.fim)) uteis
    from (select k, (v_ini + make_interval(months => k))::date m_ini from generate_series(0, 1) k) q),
  bf as (
    select distinct sg.student_id from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
    where sg.end_date is null and g.benefits ? 'Bolsa Família'),
  mat as (
    select distinct on (e.student_id) e.student_id, e.unit_id, e.class_id, e.status, coalesce(e.start_date, e.enrollment_date) inicio, e.end_date, e.id
    from iara.enrollments e join bf on bf.student_id = e.student_id
    where e.unit_id = any (p_units)
      and coalesce(e.start_date, e.enrollment_date) <= v_fim
      and (e.status = 'ACTIVE' or (e.end_date is not null and e.end_date >= v_ini))
    order by e.student_id, (e.status = 'ACTIVE') desc, e.end_date desc nulls first),
  base as (
    select m.*, s.full_name, s.birth_date, extract(year from age(v_ini, s.birth_date))::int idade, c.class_name, gl.short_name serie,
           case when age(v_ini, s.birth_date) < interval '6 years' then v_min45 else v_min617 end minimo,
           -- transferência: a matrícula seguinte, em outra unidade
           (select jsonb_build_object('unidade', u.short_name, 'inep', u.inep_code) from iara.enrollments e2 join iara.education_units u on u.id = e2.unit_id
             where e2.student_id = m.student_id and e2.id <> m.id and e2.unit_id <> m.unit_id and coalesce(e2.start_date, e2.enrollment_date) >= coalesce(m.end_date, m.inicio)
             order by coalesce(e2.start_date, e2.enrollment_date) limit 1) destino
    from mat m join iara.students s on s.id = m.student_id
    left join iara.classes c on c.id = m.class_id left join iara.grade_levels gl on gl.id = c.grade_level_id
    where age(v_ini, s.birth_date) >= interval '4 years' and age(v_ini, s.birth_date) < interval '18 years'),
  -- dias com chamada e faltas de cada aluno, por mês, de uma vez para todos (a rede inteira cabe numa consulta)
  dias as (
    select b.student_id, date_trunc('month', r.data)::date m_ini, count(*) dias
    from base b join iara.frequencia_registros r on r.class_id = b.class_id
    where r.data between greatest(v_ini, b.inicio) and least(v_fim, coalesce(b.end_date, v_fim))
    group by 1, 2),
  falt as (
    select b.student_id, date_trunc('month', r.data)::date m_ini, count(*) faltas,
           count(*) filter (where fa.tipo = 'FALTA_JUSTIFICADA' or fa.atestado or fj.id is not null) justificadas,
           string_agg(distinct coalesce(nullif(fa.justificativa, ''), fj.motivo), '; ') textos
    from base b
    join iara.frequencia_faltas fa on fa.student_id = b.student_id
    join iara.frequencia_registros r on r.id = fa.registro_id and r.class_id = b.class_id
    left join iara.frequencia_justificativas fj on fj.student_id = fa.student_id and fj.data = r.data and fj.situacao <> 'RECUSADA'
    where r.data between greatest(v_ini, b.inicio) and least(v_fim, coalesce(b.end_date, v_fim))
    group by 1, 2),
  freq as (
    select b.student_id, me.k, me.m_ini, me.previstos, me.uteis, me.recesso,
           coalesce(d.dias, 0) dias, coalesce(f.faltas, 0) faltas, coalesce(f.justificadas, 0) justificadas, f.textos
    from base b cross join meses me
    left join dias d on d.student_id = b.student_id and d.m_ini = me.m_ini
    left join falt f on f.student_id = b.student_id and f.m_ini = me.m_ini),
  -- sinais para o motivo: busca ativa aberta (ou aberta no período) e viagens do transporte que não aconteceram
  ba as materialized (
    select distinct c.student_id from iara.busca_ativa_casos c join base b on b.student_id = c.student_id
    where c.situacao in ('ABERTO', 'EM_ACOMPANHAMENTO') or c.aberto_em::date between v_ini and v_fim),
  tr as materialized (
    select ta.student_id, count(*) n from iara.transporte_alunos ta join base b on b.student_id = ta.student_id
    join iara.transporte_viagens tv on tv.rota_id = ta.rota_id
    where tv.situacao = 'NAO_REALIZADA' and tv.data between v_ini and v_fim group by 1),
  por_aluno as (
    select b.*,
      jsonb_agg(jsonb_build_object(
        'mes', to_char(fr.m_ini, 'YYYY-MM'), 'dias', fr.dias, 'faltas', fr.faltas, 'justificadas', fr.justificadas,
        'integral', fr.uteis > 0 and fr.recesso * 2 >= fr.uteis,
        'futuro', fr.m_ini > v_hoje, 'parcial', fr.m_ini <= v_hoje and (fr.m_ini + interval '1 month - 1 day')::date > v_hoje,
        'sem_chamada', greatest(fr.previstos - fr.dias, 0),
        'pct', case when fr.uteis > 0 and fr.recesso * 2 >= fr.uteis then 100
                    when fr.dias = 0 then null else round(100.0 * (fr.dias - fr.faltas) / fr.dias, 1) end) order by fr.k) meses,
      bool_or(case when fr.dias > 0 and not (fr.uteis > 0 and fr.recesso * 2 >= fr.uteis) then 100.0 * (fr.dias - fr.faltas) / fr.dias < b.minimo else false end) baixa,
      sum(fr.faltas) faltas, sum(fr.justificadas) justificadas, string_agg(fr.textos, '; ') textos
    from base b join freq fr on fr.student_id = b.student_id
    group by b.student_id, b.unit_id, b.class_id, b.status, b.inicio, b.end_date, b.id, b.full_name, b.birth_date, b.idade, b.class_name, b.serie, b.minimo, b.destino)
  select pa.student_id, pa.unit_id,
    jsonb_build_object(
      'student_id', pa.student_id, 'nome', pa.full_name, 'nascimento', pa.birth_date, 'idade', pa.idade, 'turma', pa.class_name, 'serie', pa.serie,
      'minimo', pa.minimo, 'meses', pa.meses,
      'situacao', case when pa.status = 'ACTIVE' then 'ATIVO' when pa.destino is not null then 'TRANSFERIDO' else 'SAIU' end,
      'destino', pa.destino,
      'motivo', case when pa.baixa then (
        with sinais as (
          select exists (select 1 from ba where ba.student_id = pa.student_id) busca,
                 coalesce((select n from tr where tr.student_id = pa.student_id), 0) sem_transporte,
                 (select mode() within group (order by iara.presenca_categoria(t)) from unnest(string_to_array(pa.textos, '; ')) t
                   where iara.presenca_categoria(t) is not null) cat)
        select jsonb_build_object('categoria', c, 'texto', case c
            when 'BUSCA_ATIVA' then 'Risco de abandono: caso aberto na busca ativa'
            when 'TRANSPORTE' then 'Falta ou falha do transporte escolar'
            when 'DOENCA' then 'Doença ou tratamento de saúde da criança'
            when 'FAMILIA' then 'Situação na família (luto, doença de familiar, viagem)'
            when 'OUTRO' then 'Faltas justificadas por outro motivo'
            else 'Faltas sem justificativa: falar com a família' end,
          'detalhe', format('%s falta%s no período, %s justificada%s', pa.faltas, case when pa.faltas = 1 then '' else 's' end,
                            pa.justificadas, case when pa.justificadas = 1 then '' else 's' end)
                     || coalesce(': ' || left(pa.textos, 160), ''))
        from sinais, lateral (select case
            when busca then 'BUSCA_ATIVA'
            when sem_transporte >= 2 then 'TRANSPORTE'
            when pa.justificadas * 2 >= pa.faltas and cat is not null then cat
            else 'SEM_JUSTIFICATIVA' end c) z) end,
      'lancado_em', (select lancado_em from iara.presenca_lancamentos l where l.student_id = pa.student_id and l.ano = p_ano and l.periodo = p_per)),
    coalesce(pa.baixa, false),
    exists (select 1 from iara.presenca_lancamentos l where l.student_id = pa.student_id and l.ano = p_ano and l.periodo = p_per)
  from por_aluno pa;
end $$;

create or replace function api.presenca_periodos(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_at integer[] := iara.presenca_periodo_atual();
  v_ano integer := coalesce(nullif(p ->> 'ano', '')::int, v_at[1]);
  v_nomes text[] := array['Fevereiro e março', 'Abril e maio', 'Junho e julho', 'Agosto e setembro', 'Outubro e novembro'];
begin
  perform iara.require_perm('presenca.registrar');
  return jsonb_build_object('ano', v_ano, 'atual', jsonb_build_object('ano', v_at[1], 'periodo', v_at[2]),
    'minimos', jsonb_build_object('de_4_a_5', coalesce(nullif(iara.setting('presenca_minimo_4a5'), '')::int, 60),
                                  'de_6_a_17', coalesce(nullif(iara.setting('presenca_minimo_6a17'), '')::int, 75)),
    'rede', iara.my_scope() <> 'UNIT',
    'unidade', case when iara.my_scope() = 'UNIT' then (select jsonb_build_object('id', id, 'nome', short_name) from iara.education_units where id = iara.my_unit()) end,
    'periodos', (select jsonb_agg(jsonb_build_object('periodo', k, 'rotulo', v_nomes[k],
                   'situacao', case when make_date(v_ano, 2 * k, 1) > iara.hoje_local() then 'FUTURO'
                                    when (make_date(v_ano, 2 * k, 1) + interval '2 months - 1 day')::date < iara.hoje_local() then 'ENCERRADO'
                                    else 'EM_ANDAMENTO' end) order by k) from generate_series(1, 5) k));
end $$;

-- p: unit_id? (rede), ano, periodo, exportar? (registra na auditoria a geração da planilha)
create or replace function api.presenca_unidade(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_unit integer := iara.presenca_unidade_acesso(nullif(p ->> 'unit_id', '')::int);
  v_at integer[] := iara.presenca_periodo_atual();
  v_ano integer := coalesce(nullif(p ->> 'ano', '')::int, v_at[1]);
  v_per integer := coalesce(nullif(p ->> 'periodo', '')::int, v_at[2]);
  v_ini date;
  v_alunos jsonb;
  r jsonb;
begin
  if v_per not between 1 and 5 then raise exception 'Período de 1 a 5.' using errcode = '22023'; end if;
  v_ini := make_date(v_ano, 2 * v_per, 1);
  select coalesce(jsonb_agg(a.dados order by a.dados ->> 'nome'), '[]') into v_alunos from iara.presenca_alunos(array[v_unit], v_ano, v_per) a;
  r := jsonb_build_object(
    'unidade', (select jsonb_build_object('id', id, 'nome', short_name, 'nome_completo', name, 'inep', inep_code) from iara.education_units where id = v_unit),
    'ano', v_ano, 'periodo', v_per, 'meses', jsonb_build_array(to_char(v_ini, 'YYYY-MM'), to_char(v_ini + interval '1 month', 'YYYY-MM')),
    'alunos', v_alunos,
    'resumo', jsonb_build_object('alunos', jsonb_array_length(v_alunos),
      'abaixo', (select count(*) from jsonb_array_elements(v_alunos) x where jsonb_typeof(x -> 'motivo') = 'object'),
      'lancados', (select count(*) from jsonb_array_elements(v_alunos) x where x ->> 'lancado_em' is not null),
      'transferidos', (select count(*) from jsonb_array_elements(v_alunos) x where x ->> 'situacao' <> 'ATIVO')),
    'turmas_sem_chamada', (select coalesce(jsonb_agg(distinct x ->> 'turma'), '[]') from jsonb_array_elements(v_alunos) x, jsonb_array_elements(x -> 'meses') m
                           where (m ->> 'sem_chamada')::int > 0),
    'dias_sem_aula', (select coalesce(jsonb_agg(jsonb_build_object('titulo', titulo, 'tipo', tipo, 'inicio', inicio, 'fim', fim) order by inicio), '[]')
                      from iara.calendario_eventos where suspende_aulas and inicio <= (v_ini + interval '2 months - 1 day')::date and fim >= v_ini
                        and (abrangencia = 'REDE' or unit_id = v_unit)),
    'nota', 'Beneficiários pelo Bolsa Família declarado no cadastro do responsável; a lista oficial do período é a do Sistema Presença. '
            || 'O código do motivo de baixa frequência é escolhido na tabela do Sistema Presença.');
  if coalesce((p ->> 'exportar')::boolean, false) then
    perform iara.audit_event('PRESENCA_PLANILHA', 'education_unit', v_unit::text, v_unit,
      format('Planilha do Sistema Presença gerada (%s/%s, %s alunos)', v_per, v_ano, jsonb_array_length(v_alunos)));
  end if;
  return r;
end $$;

-- marca (ou desmarca) que a frequência do aluno já foi lançada no Sistema Presença. p: student_id, ano, periodo, lancado
create or replace function api.presenca_lancar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_aluno uuid := nullif(p ->> 'student_id', '')::uuid;
  v_ano integer := nullif(p ->> 'ano', '')::int;
  v_per integer := nullif(p ->> 'periodo', '')::int;
  v_unit integer;
begin
  perform iara.require_perm('presenca.registrar');
  if v_aluno is null or v_ano is null or v_per not between 1 and 5 then raise exception 'Informe aluno, ano e período.' using errcode = '22023'; end if;
  select e.unit_id into v_unit from iara.enrollments e where e.student_id = v_aluno
  order by (e.status = 'ACTIVE') desc, e.end_date desc nulls first limit 1;
  if v_unit is null or not iara.can_access_unit(v_unit) or (iara.my_scope() = 'UNIT' and v_unit <> iara.my_unit()) then
    raise exception 'Aluno fora do seu acesso.' using errcode = '42501';
  end if;
  if coalesce((p ->> 'lancado')::boolean, true) then
    insert into iara.presenca_lancamentos (student_id, ano, periodo, unit_id, lancado_por_label, is_demo)
    values (v_aluno, v_ano, v_per, v_unit, iara.my_label(), iara.demo_mode())
    on conflict (student_id, ano, periodo) do update set lancado_em = now(), lancado_por_label = excluded.lancado_por_label;
  else
    delete from iara.presenca_lancamentos where student_id = v_aluno and ano = v_ano and periodo = v_per;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- acompanhamento da rede (só perfis da rede): por unidade, quantos alunos, quantos abaixo do mínimo e quantos já lançados
create or replace function api.presenca_rede(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_at integer[] := iara.presenca_periodo_atual();
  v_ano integer := coalesce(nullif(p ->> 'ano', '')::int, v_at[1]);
  v_per integer := coalesce(nullif(p ->> 'periodo', '')::int, v_at[2]);
  v_lin jsonb;
begin
  perform iara.require_perm('presenca.registrar');
  if iara.my_scope() = 'UNIT' then raise exception 'Visão da rede só para a Secretaria.' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'nome', u.short_name, 'tipo', u.unit_type, 'alunos', q.alunos, 'abaixo', q.abaixo, 'lancados', q.lancados)
                  order by q.alunos - q.lancados desc, u.short_name), '[]') into v_lin
  from (select unit_id, count(*) alunos, count(*) filter (where abaixo) abaixo, count(*) filter (where lancado) lancados
        from iara.presenca_alunos(array(select id from iara.education_units), v_ano, v_per) group by unit_id) q
  join iara.education_units u on u.id = q.unit_id;
  return jsonb_build_object('ano', v_ano, 'periodo', v_per, 'unidades', v_lin,
    'total', jsonb_build_object('alunos', (select coalesce(sum((x ->> 'alunos')::int), 0) from jsonb_array_elements(v_lin) x),
                                'abaixo', (select coalesce(sum((x ->> 'abaixo')::int), 0) from jsonb_array_elements(v_lin) x),
                                'lancados', (select coalesce(sum((x ->> 'lancados')::int), 0) from jsonb_array_elements(v_lin) x)));
end $$;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('presenca_lancamentos', 'student_id', 'PESSOAL', 'educação', 'controle do lançamento da frequência do Bolsa Família no Sistema Presença (MEC)', 'só a unidade e a Secretaria; planilha gerada fica na auditoria')
on conflict (tabela, coluna) do nothing;

revoke all on function iara.presenca_unidade_acesso(integer), iara.presenca_periodo_atual(), iara.presenca_categoria(text),
  iara.presenca_alunos(integer[], integer, integer) from public;

commit;
