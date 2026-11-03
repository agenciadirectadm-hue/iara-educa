-- IARA Educa — 094 · Bolsa Família na escola: mapa com detalhamento
-- O mapa pinta as regiões (áreas de ponderação) e as unidades pela parte dos alunos acompanhados que deixaram de receber
-- (abaixo da frequência mínima em ao menos um período do ano) ou pela assiduidade. Tocar numa região mostra os números
-- dela e das unidades que ficam ali; tocar numa unidade mostra os números de cada período e os motivos sugeridos do último
-- período encerrado. Só contagens: recortes com menos de 3 alunos ficam em sigilo, e contagens de 1 ou 2 aparecem como
-- "menos de 3".
-- Leitura dos motivos das faltas (api.bolsa_familia_motivos): por bimestre, tipo de unidade e faixa etária.
begin;

-- os números do Bolsa Família na escola: com p_detalhe, também regiões e unidades (lista e mapa, com o código de cada uma)
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
    where p_units is null or e.unit_id = any (p_units)),
  -- por região e por unidade: acompanhados, deixaram de receber (abaixo em ao menos um período), em dois ou mais, assíduos
  reg as (select area id, count(*) filter (where periodos > 0) n, count(*) filter (where abaixo > 0) b, count(*) filter (where abaixo >= 2) b2
          from al where area is not null group by area),
  uni as (select unit_id id, count(*) filter (where periodos > 0) n, count(*) filter (where abaixo > 0) b, count(*) filter (where abaixo >= 2) b2
          from al group by unit_id)
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
                   from reg q join iara.territories t on t.id = q.id where q.n >= 3),
    'unidades_mais_abaixo', (select coalesce(jsonb_agg(jsonb_build_object('nome', u.short_name, 'acompanhados', q.n, 'abaixo', q.b) order by q.b desc, q.n desc), '[]')
                             from (select * from uni where b >= 3 order by b desc limit 10) q
                             join iara.education_units u on u.id = q.id),
    -- para o mapa: abaixo de 3 acompanhados, só o sigilo; 1 ou 2 abaixo aparecem como nulo ("menos de 3"), e a taxa também
    -- (com o total de acompanhados, ela daria o número exato)
    'mapa_regioes', (select coalesce(jsonb_agg(case when q.n < 3 then jsonb_build_object('id', q.id, 'sigilo', true)
                       else jsonb_build_object('id', q.id, 'acompanhados', q.n, 'abaixo', case when q.b between 1 and 2 then null else q.b end,
                              'abaixo_2', case when q.b2 between 1 and 2 then null else q.b2 end, 'assiduos', q.n - q.b,
                              'taxa', case when q.b between 1 and 2 then null else round(100.0 * q.b / q.n, 1) end) end), '[]') from reg q),
    'mapa_unidades', (select coalesce(jsonb_agg(case when q.n < 3 then jsonb_build_object('id', q.id, 'sigilo', true)
                        else jsonb_build_object('id', q.id, 'acompanhados', q.n, 'abaixo', case when q.b between 1 and 2 then null else q.b end,
                               'abaixo_2', case when q.b2 between 1 and 2 then null else q.b2 end, 'assiduos', q.n - q.b,
                               'taxa', case when q.b between 1 and 2 then null else round(100.0 * q.b / q.n, 1) end) end), '[]') from uni q)) else '{}'::jsonb end
$$;

-- detalhe de uma unidade no mapa: números do ano, cada período e os motivos sugeridos do último período encerrado
create or replace function api.bolsa_familia_unidade(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := nullif(p ->> 'unit_id', '')::int;
  v_at integer[] := iara.presenca_periodo_atual();
  v_ano integer := coalesce(nullif(p ->> 'ano', '')::int, v_at[1]);
  v_ult integer := case when coalesce(nullif(p ->> 'ano', '')::int, v_at[1]) < v_at[1] then 5 else v_at[2] - 1 end;
  n jsonb;
  m jsonb := '[]';
  -- 1 ou 2 viram nulo ("menos de 3")
  sig constant text := 'menos de 3';
begin
  perform iara.require_perm('bolsa_familia.resumo');
  if not exists (select 1 from iara.education_units where id = v_unit) then raise exception 'Unidade não encontrada.' using errcode = 'P0002'; end if;
  n := iara.bolsa_familia_numeros(array[v_unit], v_ano, false);
  if (n ->> 'acompanhados')::int between 1 and 2 then
    return jsonb_build_object('unidade', (select jsonb_build_object('id', id, 'nome', short_name, 'tipo', unit_type) from iara.education_units where id = v_unit),
                              'sigilo', true, 'nota', 'Menos de 3 alunos do Bolsa Família acompanhados: os números ficam em sigilo.');
  end if;
  if v_ult >= 1 then
    select coalesce(jsonb_agg(jsonb_build_object('categoria', cat, 'texto', txt, 'alunos', case when q between 1 and 2 then null else q end) order by q desc), '[]') into m
    from (select a.dados -> 'motivo' ->> 'categoria' cat, a.dados -> 'motivo' ->> 'texto' txt, count(*) q
          from iara.presenca_alunos(array[v_unit], v_ano, v_ult) a where a.abaixo group by 1, 2) x;
  end if;
  return jsonb_build_object(
    'unidade', (select jsonb_build_object('id', u.id, 'nome', u.short_name, 'tipo', u.unit_type, 'regiao', t.name)
                from iara.education_units u left join iara.territories t on t.id = u.macro_territory_id where u.id = v_unit),
    'ano', v_ano,
    'alunos', n -> 'alunos', 'acompanhados', n -> 'acompanhados', 'assiduos', n -> 'assiduos',
    'deixaram_de_receber', case when (n ->> 'deixaram_de_receber')::int between 1 and 2 then null else n -> 'deixaram_de_receber' end,
    'abaixo_2', case when (n ->> 'abaixo_2')::int between 1 and 2 then null else n -> 'abaixo_2' end,
    'periodos', (select coalesce(jsonb_agg(jsonb_build_object('periodo', x -> 'periodo', 'acompanhados', x -> 'acompanhados',
                   'abaixo', case when (x ->> 'abaixo')::int between 1 and 2 then null else x -> 'abaixo' end)), '[]') from jsonb_array_elements(n -> 'periodos') x),
    'motivos_periodo', case when v_ult >= 1 then v_ult end,
    'motivos', m,
    'nota', 'Contagens de 1 ou 2 alunos aparecem como "' || sig || '". Motivos sugeridos pelo IARA (justificativas, busca ativa, transporte).');
end $$;

-- motivos das faltas dos alunos do Bolsa Família (cada falta numa categoria), com recorte por período, tipo de unidade e
-- faixa etária. p: ano?, periodo? (1 a 5; nulo ou 0 = ano todo), tipo? (CMEI | ESCOLA), faixa? (4-5 | 6-10 | 11-14 | 15-17).
-- Categoria: a da justificativa escrita (doença, família, transporte, outro); atestado sem texto = doença; falta sem
-- justificativa num dia em que o transporte do aluno não passou = transporte; aluno em busca ativa = risco de abandono;
-- o resto = sem justificativa. Categorias de menos de 3 alunos entram juntas como "grupos pequenos".
create or replace function api.bolsa_familia_motivos(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_at integer[] := iara.presenca_periodo_atual();
  v_ano integer := coalesce(nullif(p ->> 'ano', '')::int, v_at[1]);
  v_per integer := nullif(nullif(p ->> 'periodo', ''), '0')::int;
  v_tipo text := nullif(p ->> 'tipo', '');
  v_faixa text := nullif(p ->> 'faixa', '');
  v_ini date;
  v_fim date;
  r jsonb;
begin
  perform iara.require_perm('bolsa_familia.resumo');
  if v_per is not null and v_per not between 1 and 5 then raise exception 'Bimestre de 1 a 5.' using errcode = '22023'; end if;
  if v_tipo is not null and v_tipo not in ('CMEI', 'ESCOLA') then raise exception 'Tipo de unidade: CMEI ou ESCOLA.' using errcode = '22023'; end if;
  if v_faixa is not null and v_faixa not in ('4-5', '6-10', '11-14', '15-17') then raise exception 'Faixa etária inválida.' using errcode = '22023'; end if;
  v_ini := make_date(v_ano, 2 * coalesce(v_per, 1), 1);
  v_fim := least(case when v_per is null then make_date(v_ano, 11, 30) else (v_ini + interval '2 months - 1 day')::date end, iara.hoje_local());
  with bf as (
    select distinct sg.student_id sid from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
    where sg.end_date is null and g.benefits ? 'Bolsa Família'),
  alunos as materialized (
    select distinct on (e.student_id) e.student_id sid, e.class_id cid, coalesce(e.start_date, e.enrollment_date) inicio, e.end_date fim
    from iara.enrollments e join bf on bf.sid = e.student_id
    join iara.education_units u on u.id = e.unit_id join iara.students s on s.id = e.student_id
    where coalesce(e.start_date, e.enrollment_date) <= v_fim and (e.status = 'ACTIVE' or (e.end_date is not null and e.end_date >= v_ini))
      and (v_tipo is null or u.unit_type = v_tipo)
      and age(v_ini, s.birth_date) >= interval '4 years' and age(v_ini, s.birth_date) < interval '18 years'
      and (v_faixa is null or v_faixa = case when age(v_ini, s.birth_date) < interval '6 years' then '4-5'
                                             when age(v_ini, s.birth_date) < interval '11 years' then '6-10'
                                             when age(v_ini, s.birth_date) < interval '15 years' then '11-14' else '15-17' end)
    order by e.student_id, (e.status = 'ACTIVE') desc, e.end_date desc nulls first),
  faltas as materialized (
    select a.sid, r0.data, coalesce(nullif(fa.justificativa, ''), fj.motivo) texto, fa.tipo, fa.atestado
    from alunos a join iara.frequencia_faltas fa on fa.student_id = a.sid
    join iara.frequencia_registros r0 on r0.id = fa.registro_id and r0.class_id = a.cid
    left join iara.frequencia_justificativas fj on fj.student_id = fa.student_id and fj.data = r0.data and fj.situacao <> 'RECUSADA'
    where r0.data between greatest(v_ini, a.inicio) and least(v_fim, coalesce(a.fim, v_fim))),
  sem_onibus as materialized (
    select distinct ta.student_id sid, tv.data from iara.transporte_alunos ta join alunos a on a.sid = ta.student_id
    join iara.transporte_viagens tv on tv.rota_id = ta.rota_id
    where tv.situacao = 'NAO_REALIZADA' and tv.data between v_ini and v_fim),
  busca as materialized (
    select distinct c.student_id sid from iara.busca_ativa_casos c join alunos a on a.sid = c.student_id
    where c.situacao in ('ABERTO', 'EM_ACOMPANHAMENTO') or c.aberto_em::date between v_ini and v_fim),
  cat as (
    select f.sid, case
      when iara.presenca_categoria(f.texto) is not null then iara.presenca_categoria(f.texto)
      when f.atestado then 'DOENCA'
      when f.tipo = 'FALTA_JUSTIFICADA' then 'OUTRO'
      when exists (select 1 from sem_onibus so where so.sid = f.sid and so.data = f.data) then 'TRANSPORTE'
      when exists (select 1 from busca b where b.sid = f.sid) then 'BUSCA_ATIVA'
      else 'SEM_JUSTIFICATIVA' end c
    from faltas f),
  agg as (select c, count(*) faltas, count(distinct sid) alunos from cat group by c)
  select jsonb_build_object(
    'ano', v_ano, 'periodo', v_per, 'tipo', v_tipo, 'faixa', v_faixa, 'de', v_ini, 'ate', v_fim,
    'alunos', (select count(*) from alunos),
    'alunos_com_falta', (select count(distinct sid) from cat),
    'total_faltas', (select count(*) from cat),
    'categorias', (select coalesce(jsonb_agg(jsonb_build_object('categoria', c, 'faltas', faltas, 'alunos', alunos) order by faltas desc), '[]')
                   from agg where alunos >= 3),
    'grupos_pequenos', (select coalesce(sum(faltas), 0) from agg where alunos < 3)) into r;
  if (r ->> 'alunos')::int between 1 and 2 then
    return jsonb_build_object('ano', v_ano, 'periodo', v_per, 'tipo', v_tipo, 'faixa', v_faixa, 'sigilo', true, 'categorias', '[]'::jsonb,
                              'nota', 'Menos de 3 alunos neste recorte: os números ficam em sigilo.');
  end if;
  return r;
end $$;

-- a conta guardada é refeita com os campos do mapa
delete from iara.bolsa_familia_cache;

commit;
