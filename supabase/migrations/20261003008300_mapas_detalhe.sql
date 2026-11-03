-- IARA Educa — 083 · Mapas: detalhamento de todo quesito (cidade → unidade → turma; região → microrregião)
-- Pedido do Prefeito e da Secretaria: achar no mapa uma unidade com 11 ocorrências e poder ver o que acontece nela. Cada
-- quesito vira um conjunto de fatos (uma linha por ocorrência, aluno, inscrição na fila, turma, professor…), com a unidade,
-- a turma, a região e a microrregião de cada fato e até seis quebras (tipo, gravidade, série, turno, mês…). Um só
-- agregador (api.mapa_detalhe) devolve, para o nível pedido: o valor, a referência (média das unidades, das turmas ou das
-- regiões; a rede, nas taxas), a posição entre os pares, as quebras e os filhos para descer mais um nível.
-- Sem dado pessoal: nenhum nome nem identificador de pessoa sai daqui. O que depende da casa da pessoa segue o sigilo do
-- mapa (região ou microrregião com menos de 3 pessoas — taxa: 5 — não aparece; quebras e unidades com menos de 3 também não).
-- Os fatos seguem as mesmas regras de api.mapa_calor (unidade e turma) e de iara.mapa_obs (região e microrregião).
begin;

-- rótulo de um código (os ordenáveis vêm com prefixo "NN|", que ordena a quebra e sai do rótulo)
create or replace function iara.rotulo_codigo(p text) returns text
language sql immutable set search_path = iara, public
as $$
  select case when p is null then null else coalesce('{
    "MANHA": "Manhã", "TARDE": "Tarde", "NOITE": "Noite", "INTEGRAL": "Integral",
    "COMPORTAMENTO": "Comportamento", "CONFLITO": "Conflito entre alunos", "ACIDENTE": "Acidente", "SAUDE": "Saúde",
    "BULLYING": "Bullying", "PERTENCES": "Pertences", "ATRASO_SAIDA": "Atraso na saída", "PEDAGOGICA": "Pedagógica", "OUTRO": "Outro",
    "LEVE": "1|Leve", "MODERADA": "2|Moderada", "GRAVE": "3|Grave",
    "ABERTA": "1|Aberta", "EM_ACOMPANHAMENTO": "2|Em acompanhamento", "ENCERRADA": "3|Encerrada",
    "FISICA": "Física", "PSICOLOGICA": "Psicológica", "SEXUAL": "Sexual", "INSTITUCIONAL": "Institucional", "PATRIMONIAL": "Patrimonial",
    "CYBERBULLYING": "Cyberbullying", "DISCRIMINACAO": "Discriminação", "AUTOLESAO": "Autolesão",
    "PRE_SILABICO": "1|Pré-silábico", "SILABICO_SEM_VALOR": "2|Silábico sem valor sonoro", "SILABICO_COM_VALOR": "3|Silábico com valor sonoro",
    "SILABICO_ALFABETICO": "4|Silábico-alfabético", "ALFABETICO": "5|Alfabético",
    "DIAGNOSTICA": "1|Diagnóstica", "B1": "2|1º bimestre", "B2": "3|2º bimestre", "B3": "4|3º bimestre", "B4": "5|4º bimestre",
    "SEM_ATENDIMENTO": "Sem vaga na rede", "AGUARDA_TRANSFERENCIA": "Aguarda transferência", "PARCIAL_PARA_INTEGRAL": "Quer passar ao integral",
    "UNIDADE_PREFERENCIAL": "Quer a unidade preferida", "RECUSOU_OFERTA": "Recusou oferta", "DEMANDA_FUTURA": "Para o próximo ano",
    "WAITING": "1|Aguardando", "OFFERED": "2|Com oferta em aberto",
    "IDA": "Ida", "VOLTA": "Volta", "EM_ANDAMENTO": "Em andamento", "CONCLUIDA": "Concluída", "NAO_REALIZADA": "Não realizada",
    "DISTANCIA": "Distância", "ZONA_RURAL": "Zona rural", "DEFICIENCIA": "Deficiência",
    "PROFESSOR": "Professor(a)", "EDUCADOR": "Educador(a)", "AEE": "Professor(a) do AEE", "AUXILIAR": "Auxiliar", "APOIO": "Apoio",
    "CMEI": "CMEI", "ESCOLA": "Escola", "ATIVA": "Ativa"
  }'::jsonb ->> p, initcap(replace(lower(p), '_', ' '))) end
$$;

create or replace function iara.mes_rotulo(p date) returns text
language sql immutable
as $$ select to_char(p, 'YYYYMM') || '|' || (array['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'])[extract(month from p)::int] || '/' || extract(year from p) $$;

create or replace function iara.serie_rotulo(p_grade smallint) returns text
language sql stable set search_path = iara, public
as $$ select lpad(g.sort::text, 2, '0') || '|' || g.short_name from iara.grade_levels g where g.id = p_grade $$;

-- p: camada (o quesito do mapa), nivel ('cidade' | 'unidade' | 'turma' | 'area' | 'setor') e id (da unidade, da turma,
-- da região ou o código do setor)
create or replace function api.mapa_detalhe(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, extensions, public
as $$
declare
  v_camada text := coalesce(nullif(p ->> 'camada', ''), 'ocorrencias');
  v_nivel text := coalesce(nullif(p ->> 'nivel', ''), 'cidade');
  v_id text := nullif(p ->> 'id', '');
  v_hoje date := iara.hoje_local();
  v_raio double precision := coalesce(nullif(iara.setting('default_radius_m'), '')::numeric, 2000) / 1000.0;
  v_ano integer := extract(year from iara.hoje_local())::int;
  v_unit integer;
  v_class uuid;
  v_area integer;
  v_setor text;
  c record;
  v_fatos text;
  v_dims text[];
  v_mostra text[];
  v_val text;
  v_quebras text := '';
  v_chave text;
  v_filho text;
  v_ordem text;
  v_sigilo boolean;
  v_min integer;
  v_nome text;
  v_pai jsonb;
  r jsonb;
  i integer;
begin
  -- tipo: soma ou taxa (%) · casa: depende da casa da pessoa · pior: a ponta ruim · publica: sem a visão da rede
  select * into c from (values
    ('unidades', 'soma', false, ' unidade(s)', 'menor', true),
    ('vagas', 'soma', false, ' vaga(s)', 'menor', true),
    ('matriculas', 'soma', false, ' matrícula(s)', 'maior', true),
    ('fila', 'soma', false, ' na fila', 'maior', true),
    ('deficit', 'soma', false, '', 'menor', true),
    ('criancas_0a4', 'soma', false, ' criança(s)', 'maior', true),
    ('pessoas', 'soma', false, ' morador(es)', 'maior', true),
    ('fila_casa', 'soma', true, ' criança(s)', 'maior', false),
    ('transporte_necessidade', 'soma', true, ' criança(s)', 'maior', false),
    ('transporte_oferta', 'soma', false, ' aluno(s)', 'menor', false),
    ('transporte_efetividade', 'taxa', false, '%', 'menor', false),
    ('frequencia', 'taxa', true, '%', 'menor', false),
    ('faltas', 'soma', true, ' falta(s)', 'maior', false),
    ('ocorrencias', 'soma', true, ' ocorrência(s)', 'maior', false),
    ('alfa_esperado', 'taxa', true, '%', 'menor', false),
    ('alfa_precoce', 'soma', true, ' criança(s)', 'menor', false),
    ('alfa_abaixo', 'soma', true, ' criança(s)', 'maior', false),
    ('cadastros', 'taxa', true, '%', 'menor', false),
    ('formacao', 'taxa', false, '%', 'menor', false)
  ) q(camada, tipo, casa, sufixo, pior, publica) where q.camada = v_camada;
  if not found then
    raise exception 'Este quesito não tem detalhamento.' using errcode = '22023';
  end if;
  if v_nivel not in ('cidade', 'unidade', 'turma', 'area', 'setor') or (v_nivel <> 'cidade' and v_id is null) then
    raise exception 'Nível inválido: use cidade, unidade, turma, area ou setor (com o id).' using errcode = '22023';
  end if;
  if iara.current_user_id() is null then
    raise exception 'Sessão necessária.' using errcode = '28000';
  end if;
  if not c.publica then
    perform iara.require_perm('kpi.network');
  end if;

  -- o nível pedido, o nome dele e o nível de cima (para voltar)
  case v_nivel
  when 'unidade' then
    v_unit := v_id::integer;
    select u.short_name into v_nome from iara.education_units u where u.id = v_unit;
    v_pai := jsonb_build_object('nivel', 'cidade', 'nome', 'Maringá');
  when 'turma' then
    v_class := v_id::uuid;
    select c2.class_name || ' · ' || u.short_name, jsonb_build_object('nivel', 'unidade', 'id', u.id::text, 'nome', u.short_name)
      into v_nome, v_pai
    from iara.classes c2 join iara.education_units u on u.id = c2.unit_id where c2.id = v_class;
  when 'area' then
    v_area := v_id::integer;
    select t.name into v_nome from iara.territories t where t.id = v_area;
    v_pai := jsonb_build_object('nivel', 'cidade', 'nome', 'Maringá');
  when 'setor' then
    v_setor := v_id;
    select 'Setor ' || right(s.code, 6) || coalesce(' · ' || s.bairro, ''), jsonb_build_object('nivel', 'area', 'id', t.id::text, 'nome', t.name)
      into v_nome, v_pai
    from iara.setores_censitarios s join iara.territories t on t.id = s.area_ponderacao_id where s.code = v_setor;
  else
    v_nome := 'Maringá';
  end case;
  if v_nome is null then
    raise exception 'Não encontrado.' using errcode = 'P0002';
  end if;

  -- fatos do quesito: unit_id, class_id, area, setor, pessoa (só para o sigilo), num, den e as quebras d1..d6 (text[])
  -- parâmetros: $1 hoje, $2 raio (km), $3 ano letivo
  case v_camada
  when 'ocorrencias' then
    v_dims := array['Tipo', 'Gravidade', 'Situação', 'Mês', 'Série', 'Violência'];
    v_mostra := array['valor', 'valor', 'valor', 'valor', 'valor', 'valor'];
    v_fatos := $f$
      select o.unit_id, o.class_id, case when a.location is not null then a.territory_id end area, case when a.location is not null then a.setor_censitario end setor, o.student_id pessoa,
             1::numeric num, null::numeric den,
             array[iara.rotulo_codigo(o.tipo)] d1, array[iara.rotulo_codigo(o.gravidade)] d2, array[iara.rotulo_codigo(o.situacao)] d3,
             array[iara.mes_rotulo(o.ocorrida_em::date)] d4, array[coalesce(iara.serie_rotulo(c2.grade_level_id), 'Sem turma')] d5,
             case when cardinality(o.violencia) > 0 then array(select iara.rotulo_codigo(x) from unnest(o.violencia) x) else array['Sem violência'] end d6
      from iara.ocorrencias o left join iara.classes c2 on c2.id = o.class_id
      left join iara.students s on s.id = o.student_id left join iara.addresses a on a.id = s.address_id
      where o.ocorrida_em >= now() - interval '90 days' and o.tipo <> 'ELOGIO' $f$;
  when 'frequencia' then
    v_dims := array['Série', 'Turno', 'Presença dos alunos', 'Alerta de frequência', 'Busca ativa', 'Faltas'];
    v_mostra := array['valor', 'valor', 'n', 'n', 'n', 'n'];
    v_fatos := $f$
      with reg as (select r2.id, r2.class_id from iara.frequencia_registros r2 where r2.data >= $1 - 30),
           poss as (select e.student_id, e.class_id, e.unit_id, count(*) n from reg join iara.enrollments e on e.class_id = reg.class_id and e.status = 'ACTIVE' group by 1, 2, 3),
           fal as (select f.student_id, count(*) n, count(*) filter (where f.tipo = 'FALTA_JUSTIFICADA') just
                   from iara.frequencia_faltas f join reg on reg.id = f.registro_id group by 1)
      select poss.unit_id, poss.class_id, case when a.location is not null then a.territory_id end, case when a.location is not null then a.setor_censitario end, poss.student_id,
             (poss.n - coalesce(fal.n, 0))::numeric, poss.n::numeric,
             array[iara.serie_rotulo(c2.grade_level_id)], array[iara.rotulo_codigo(c2.shift)],
             array[case when 100.0 * (poss.n - coalesce(fal.n, 0)) / poss.n < 75 then '1|Abaixo de 75%' when 100.0 * (poss.n - coalesce(fal.n, 0)) / poss.n < 90 then '2|De 75% a 90%'
                        when 100.0 * (poss.n - coalesce(fal.n, 0)) / poss.n < 95 then '3|De 90% a 95%' else '4|95% ou mais' end],
             array[case when exists (select 1 from iara.frequencia_alertas fa where fa.student_id = poss.student_id and fa.situacao <> 'RESOLVIDO') then 'Em alerta' else 'Sem alerta' end],
             array[case when exists (select 1 from iara.busca_ativa_casos b where b.student_id = poss.student_id and b.situacao <> 'ENCERRADO') then 'Com caso aberto' else 'Sem caso' end],
             array[case when coalesce(fal.n, 0) = 0 then '1|Nenhuma falta' when fal.just = fal.n then '2|Só faltas justificadas' else '3|Com falta sem justificativa' end]
      from poss join iara.classes c2 on c2.id = poss.class_id join iara.students s on s.id = poss.student_id
      left join iara.addresses a on a.id = s.address_id left join fal on fal.student_id = poss.student_id $f$;
  when 'faltas' then
    v_dims := array['Série', 'Turno', 'Faltas por aluno', 'Alerta de frequência', 'Busca ativa'];
    v_mostra := array['valor', 'valor', 'n', 'n', 'n'];
    v_fatos := $f$
      with fa as (select f.student_id, count(*) n from iara.frequencia_faltas f join iara.frequencia_registros r2 on r2.id = f.registro_id
                  where r2.data >= $1 - 30 and f.tipo = 'FALTA' group by 1)
      select e.unit_id, e.class_id, case when a.location is not null then a.territory_id end, case when a.location is not null then a.setor_censitario end, s.id, coalesce(fa.n, 0)::numeric, null::numeric,
             array[iara.serie_rotulo(c2.grade_level_id)], array[iara.rotulo_codigo(c2.shift)],
             array[case when coalesce(fa.n, 0) = 0 then '1|Nenhuma' when fa.n <= 2 then '2|1 ou 2' when fa.n <= 5 then '3|3 a 5' else '4|6 ou mais' end],
             array[case when exists (select 1 from iara.frequencia_alertas x where x.student_id = s.id and x.situacao <> 'RESOLVIDO') then 'Em alerta' else 'Sem alerta' end],
             array[case when exists (select 1 from iara.busca_ativa_casos b where b.student_id = s.id and b.situacao <> 'ENCERRADO') then 'Com caso aberto' else 'Sem caso' end],
             null::text[]
      from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' join iara.classes c2 on c2.id = e.class_id
      left join iara.addresses a on a.id = s.address_id left join fa on fa.student_id = s.id $f$;
  when 'alfa_esperado', 'alfa_precoce', 'alfa_abaixo' then
    v_dims := array['Nível de escrita', 'Para a idade', 'Série', 'Última sondagem', 'Idade na sondagem', 'Turno'];
    v_mostra := array['n', 'n', 'valor', 'valor', 'valor', 'valor'];
    v_fatos := format($f$
      with so as (select distinct on (x.student_id) x.student_id, x.class_id, x.nivel, x.ciclo,
                         ((extract(year from age(x.data, s.birth_date)) * 12 + extract(month from age(x.data, s.birth_date))))::int meses
                  from iara.alfabetizacao_sondagens x join iara.students s on s.id = x.student_id
                  join iara.enrollments e on e.student_id = x.student_id and e.status = 'ACTIVE'
                  where x.ano = $3 order by x.student_id, x.data desc),
           sx as (select so.*, iara.alfa_situacao_idade(so.nivel, so.meses) sit from so)
      select c2.unit_id, sx.class_id, case when a.location is not null then a.territory_id end, case when a.location is not null then a.setor_censitario end, sx.student_id,
             (case %1$L when 'alfa_esperado' then (sx.sit <> 'ABAIXO')::int when 'alfa_precoce' then (sx.sit = 'PRECOCE')::int else (sx.sit = 'ABAIXO')::int end)::numeric,
             case when %1$L = 'alfa_esperado' then 1::numeric end,
             array[iara.rotulo_codigo(sx.nivel)],
             array[case sx.sit when 'PRECOCE' then '1|Antes do esperado' when 'ABAIXO' then '3|Abaixo do esperado' else '2|No esperado' end],
             array[iara.serie_rotulo(c2.grade_level_id)], array[iara.rotulo_codigo(sx.ciclo)],
             array[lpad((sx.meses / 12)::text, 2, '0') || '|' || (sx.meses / 12) || ' anos'], array[iara.rotulo_codigo(c2.shift)]
      from sx join iara.classes c2 on c2.id = sx.class_id join iara.students s on s.id = sx.student_id left join iara.addresses a on a.id = s.address_id $f$, v_camada);
  when 'cadastros' then
    v_dims := array['Série', 'O que falta', 'Turno'];
    v_mostra := array['valor', 'n', 'valor'];
    v_fatos := $f$
      with al as (select s.id, e.unit_id, e.class_id, s.address_id,
                         iara.aluno_pendencias(s, exists (select 1 from iara.student_guardians sg where sg.student_id = s.id and sg.end_date is null)) pa,
                         (select array_agg(distinct 'Responsável: ' || x) from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id,
                                 unnest(iara.responsavel_pendencias(g)) x
                          where sg.student_id = s.id and sg.end_date is null and sg.is_primary) pr
                  from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE')
      select al.unit_id, al.class_id, coalesce(a.territory_id, t.area), case when a.location is not null then a.setor_censitario else t.setor end, al.id,
             (cardinality(al.pa) = 0 and coalesce(cardinality(al.pr), 0) = 0)::int::numeric, 1::numeric,
             array[iara.serie_rotulo(c2.grade_level_id)],
             case when cardinality(al.pa) + coalesce(cardinality(al.pr), 0) = 0 then array['Nada: cadastro completo'] else al.pa || coalesce(al.pr, '{}') end,
             array[iara.rotulo_codigo(c2.shift)], null::text[], null::text[], null::text[]
      from al join iara.classes c2 on c2.id = al.class_id left join iara.addresses a on a.id = al.address_id join iara.unidades_territorio() t on t.id = al.unit_id $f$;
  when 'formacao' then
    v_dims := array['Formação', 'Função', 'Vínculo'];
    v_mostra := array['n', 'valor', 'valor'];
    v_fatos := $f$
      select st.unit_id, null::uuid, t.area, t.setor, st.id, (iara.formacao_nivel(st.escolaridade) >= 4)::int::numeric, (iara.formacao_nivel(st.escolaridade) is not null)::int::numeric,
             array[coalesce(iara.formacao_nivel(st.escolaridade)::text || '|' || case iara.formacao_nivel(st.escolaridade) when 1 then 'Nível médio / magistério'
                     when 2 then 'Superior incompleto' when 3 then 'Superior completo' when 4 then 'Especialização' when 5 then 'Mestrado' else 'Doutorado' end, '9|Sem informação')],
             array[iara.rotulo_codigo(st.role)], array[coalesce(st.bond, 'Sem informação')], null::text[], null::text[], null::text[]
      from iara.staff st join iara.unidades_territorio() t on t.id = st.unit_id
      where st.role in ('PROFESSOR', 'EDUCADOR', 'AEE') and coalesce(st.situacao, 'ATIVO') = 'ATIVO' $f$;
  when 'fila', 'fila_casa' then
    v_dims := array['Série', 'Por que espera', 'Tempo de espera', 'Situação', 'Critério de prioridade', 'Turno pedido'];
    v_mostra := array['valor', 'valor', 'valor', 'valor', 'valor', 'valor'];
    v_fatos := format($f$
      select w.preferred_unit_id, null::uuid,
             case when %1$L = 'fila' then t.area when a.location is not null then a.territory_id end,
             case when %1$L = 'fila' then t.setor when a.location is not null then a.setor_censitario end,
             w.student_id, 1::numeric, null::numeric,
             array[iara.serie_rotulo(w.grade_level_id)], array[iara.rotulo_codigo(w.demand_category)],
             array[case when $1 - w.entered_at::date <= 30 then '1|Até 30 dias' when $1 - w.entered_at::date <= 90 then '2|De 1 a 3 meses'
                        when $1 - w.entered_at::date <= 180 then '3|De 3 a 6 meses' else '4|Mais de 6 meses' end],
             array[iara.rotulo_codigo(w.status)],
             case when cardinality(w.priority_flags) > 0 then array(select iara.rotulo_codigo(x) from unnest(w.priority_flags) x) else array['Sem critério de prioridade'] end,
             array[case when w.full_time_requested then 'Integral' else coalesce(iara.rotulo_codigo(w.preferred_shift), 'Sem preferência') end]
      from iara.waiting_list_entries w join iara.unidades_territorio() t on t.id = w.preferred_unit_id
      left join iara.students s on s.id = w.student_id left join iara.addresses a on a.id = s.address_id
      where w.status in ('WAITING', 'OFFERED') $f$, v_camada);
  when 'vagas' then
    v_dims := array['Série', 'Turno', 'Turmas'];
    v_mostra := array['valor', 'valor', 'n'];
    v_fatos := $f$
      select c2.unit_id, c2.id, t.area, t.setor, null::uuid, c2.offerable_vacancies_count::numeric, null::numeric,
             array[iara.serie_rotulo(c2.grade_level_id)], array[iara.rotulo_codigo(c2.shift)],
             array[case when c2.offerable_vacancies_count > 0 then '1|Com vaga' else '2|Sem vaga' end], null::text[], null::text[], null::text[]
      from iara.classes c2 join iara.unidades_territorio() t on t.id = c2.unit_id $f$;
  when 'matriculas' then
    v_dims := array['Série', 'Turno'];
    v_mostra := array['valor', 'valor'];
    v_fatos := $f$
      select e.unit_id, e.class_id, t.area, t.setor, null::uuid, 1::numeric, null::numeric,
             array[iara.serie_rotulo(c2.grade_level_id)], array[iara.rotulo_codigo(c2.shift)], null::text[], null::text[], null::text[], null::text[]
      from iara.enrollments e join iara.classes c2 on c2.id = e.class_id join iara.unidades_territorio() t on t.id = e.unit_id
      where e.status = 'ACTIVE' $f$;
  when 'deficit' then
    v_dims := array['Saldo da creche', 'Turno'];
    v_mostra := array['valor', 'valor'];
    v_fatos := $f$
      select c2.unit_id, c2.id, t.area, t.setor, null::uuid, c2.offerable_vacancies_count::numeric, null::numeric,
             array['1|Vagas de creche (+)'], array[iara.rotulo_codigo(c2.shift)], null::text[], null::text[], null::text[], null::text[]
      from iara.classes c2 join iara.unidades_territorio() t on t.id = c2.unit_id where c2.grade_level_id = 1
      union all
      select w.preferred_unit_id, null::uuid, t.area, t.setor, null::uuid, -1::numeric, null::numeric,
             array['2|Crianças esperando creche (−)'], array[case when w.full_time_requested then 'Integral' else coalesce(iara.rotulo_codigo(w.preferred_shift), 'Sem preferência') end],
             null::text[], null::text[], null::text[], null::text[]
      from iara.waiting_list_entries w join iara.unidades_territorio() t on t.id = w.preferred_unit_id
      where w.grade_level_id = 1 and w.status in ('WAITING', 'OFFERED') $f$;
  when 'unidades' then
    v_dims := array['Tipo', 'Situação'];
    v_mostra := array['valor', 'valor'];
    v_fatos := $f$
      select u.id, null::uuid, t.area, t.setor, null::uuid, 1::numeric, null::numeric,
             array[iara.rotulo_codigo(u.unit_type)], array[iara.rotulo_codigo(u.status)], null::text[], null::text[], null::text[], null::text[]
      from iara.education_units u join iara.unidades_territorio() t on t.id = u.id $f$;
  when 'criancas_0a4', 'pessoas' then
    v_dims := array['Bairro', 'Situação do setor'];
    v_mostra := array['valor', 'valor'];
    v_fatos := format($f$
      select null::integer, null::uuid, s.area_ponderacao_id, s.code, null::uuid,
             (case %1$L when 'pessoas' then s.pessoas else s.criancas_0a4 end)::numeric, null::numeric,
             array[coalesce(s.bairro, 'Sem bairro')], array[initcap(lower(s.situacao))], null::text[], null::text[], null::text[], null::text[]
      from iara.setores_censitarios s $f$, v_camada);
  when 'transporte_necessidade' then
    v_dims := array['Série', 'Por que precisa', 'Distância da escola', 'Turno'];
    v_mostra := array['valor', 'valor', 'valor', 'valor'];
    v_fatos := $f$
      with al as (select s.id, e.unit_id, e.class_id, a.territory_id area, a.setor_censitario setor, s.school_transport_status st,
                         iara.km_entre(extensions.st_y(a.location::extensions.geometry), extensions.st_x(a.location::extensions.geometry), u.lat, u.lng) km
                  from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
                  join iara.addresses a on a.id = s.address_id join iara.education_units u on u.id = e.unit_id
                  where a.location is not null and not exists (select 1 from iara.transporte_alunos ta where ta.student_id = s.id and ta.fim is null))
      select al.unit_id, al.class_id, al.area, al.setor, al.id, 1::numeric, null::numeric,
             array[iara.serie_rotulo(c2.grade_level_id)],
             array[case when al.st = 'AGUARDANDO' then 'Pediu e aguarda' else 'Mora a mais de 2 km' end],
             array[case when al.km <= 2 then '1|Até 2 km' when al.km <= 3 then '2|De 2 a 3 km' when al.km <= 5 then '3|De 3 a 5 km' else '4|Mais de 5 km' end],
             array[iara.rotulo_codigo(c2.shift)], null::text[], null::text[]
      from al join iara.classes c2 on c2.id = al.class_id
      where al.st = 'AGUARDANDO' or al.km > $2 $f$;
  when 'transporte_oferta' then
    v_dims := array['Rota', 'Motivo', 'Série', 'Turno da rota'];
    v_mostra := array['valor', 'valor', 'valor', 'valor'];
    v_fatos := $f$
      with pt as (select p2.id, iara.area_do_ponto(iara.point(p2.lat, p2.lng)) area, iara.setor_do_ponto(iara.point(p2.lat, p2.lng)) setor
                  from iara.transporte_pontos p2 join iara.transporte_rotas r2 on r2.id = p2.rota_id and r2.situacao = 'ATIVA')
      select r2.unit_id, e.class_id, pt.area, pt.setor, ta.student_id, 1::numeric, null::numeric,
             array['Rota ' || r2.codigo], array[iara.rotulo_codigo(ta.motivo)], array[coalesce(iara.serie_rotulo(c2.grade_level_id), 'Sem turma')],
             array[iara.rotulo_codigo(r2.turno)], null::text[], null::text[]
      from iara.transporte_alunos ta join iara.transporte_rotas r2 on r2.id = ta.rota_id and r2.situacao = 'ATIVA'
      left join pt on pt.id = ta.ponto_id
      left join iara.enrollments e on e.student_id = ta.student_id and e.status = 'ACTIVE' left join iara.classes c2 on c2.id = e.class_id
      where ta.fim is null $f$;
  when 'transporte_efetividade' then
    -- como no mapa: cada viagem divide transportados e previstos igualmente entre as paradas da rota
    v_dims := array['Rota', 'Sentido', 'Situação da viagem', 'Dia da semana'];
    v_mostra := array['valor', 'valor', 'n', 'valor'];
    v_fatos := $f$
      with pt as (select p2.id, p2.rota_id, iara.area_do_ponto(iara.point(p2.lat, p2.lng)) area, iara.setor_do_ponto(iara.point(p2.lat, p2.lng)) setor,
                         count(*) over (partition by p2.rota_id) npt
                  from iara.transporte_pontos p2 join iara.transporte_rotas r2 on r2.id = p2.rota_id and r2.situacao = 'ATIVA'),
           vg as (select v.*, r2.unit_id, r2.codigo from iara.transporte_viagens v join iara.transporte_rotas r2 on r2.id = v.rota_id and r2.situacao = 'ATIVA'
                  where v.data >= $1 - 30 and v.data < $1
                    and (select sum(v2.alunos_previstos) from iara.transporte_viagens v2 where v2.rota_id = r2.id and v2.data >= $1 - 30 and v2.data < $1) > 0)
      select vg.unit_id, null::uuid, pt.area, pt.setor, null::uuid, coalesce(vg.alunos_transportados, 0)::numeric / pt.npt, coalesce(vg.alunos_previstos, 0)::numeric / pt.npt,
             array['Rota ' || vg.codigo], array[iara.rotulo_codigo(vg.sentido)], array[iara.rotulo_codigo(vg.situacao)],
             array[extract(isodow from vg.data)::text || '|' || (array['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'])[extract(isodow from vg.data)::int]],
             null::text[], null::text[]
      from vg join pt on pt.rota_id = vg.rota_id $f$;
  else
    raise exception 'Este quesito não tem detalhamento.' using errcode = '22023';
  end case;

  -- valor de um grupo: soma ou taxa
  v_val := case when c.tipo = 'taxa' then 'round(100.0 * sum(num) / nullif(sum(den), 0), 1)' else 'round(sum(num), 1)' end;
  v_ordem := case when c.pior = 'maior' then 'desc' else 'asc' end;
  v_sigilo := c.casa and v_nivel in ('area', 'setor');
  v_min := case when c.tipo = 'taxa' then 5 else 3 end;

  -- quebras: uma por dimensão; ordenáveis pelo prefixo, as demais pela quantidade
  for i in 1 .. coalesce(array_length(v_dims, 1), 0) loop
    v_quebras := v_quebras || format($q$,
      jsonb_build_object('titulo', %1$L, 'mostra', %2$L, 'itens', (
        select coalesce(jsonb_agg(jsonb_build_object('rotulo', regexp_replace(q.v, '^[^|]*\|', ''), 'valor', q.val, 'n', q.n)
                                  order by case when q.v ~ '\|' then q.v end, q.n desc, q.v), '[]'::jsonb)
        from (select v, %3$s val, count(*) n, count(distinct pessoa) np
              from fx cross join lateral unnest(coalesce(fx.d%4$s, array['Sem informação'])) v group by v) q
        where not $7 or q.np >= 3)) $q$, v_dims[i], v_mostra[i], v_val, i);
  end loop;

  -- quem está um nível abaixo: na cidade e nas regiões, as unidades; na unidade, as turmas
  v_chave := case v_nivel when 'unidade' then 'unit_id' when 'turma' then 'class_id' when 'area' then 'area' when 'setor' then 'setor' end;
  if v_nivel in ('cidade', 'area', 'setor') then
    v_filho := format($q$
      jsonb_build_object('nivel', 'unidade', 'titulo', %1$L, 'itens', (
        select coalesce(jsonb_agg(jsonb_build_object('id', u.id::text, 'nome', u.short_name, 'detalhe', iara.rotulo_codigo(u.unit_type), 'valor', q.val, 'n', q.n)
                                  order by q.val %2$s nulls last, q.n desc), '[]'::jsonb)
        from (select unit_id, %3$s val, count(*) n, count(distinct pessoa) np from fx where unit_id is not null group by unit_id) q
        join iara.education_units u on u.id = q.unit_id where not $7 or q.np >= 3)) $q$,
      case when v_nivel = 'cidade' then 'Unidades' when c.casa then 'Onde estudam' else 'Unidades daqui' end, v_ordem, v_val);
  elsif v_nivel = 'unidade' then
    v_filho := format($q$
      jsonb_build_object('nivel', 'turma', 'titulo', 'Turmas', 'itens', (
        select coalesce(jsonb_agg(jsonb_build_object('id', c2.id::text, 'nome', c2.class_name,
                                                     'detalhe', regexp_replace(iara.serie_rotulo(c2.grade_level_id), '^[^|]*\|', '') || ' · ' || iara.rotulo_codigo(c2.shift),
                                                     'valor', q.val, 'n', q.n)
                                  order by q.val %1$s nulls last, q.n desc), '[]'::jsonb)
        from (select class_id, %2$s val, count(*) n from fx where class_id is not null group by class_id) q
        join iara.classes c2 on c2.id = q.class_id)) $q$, v_ordem, v_val);
  else
    v_filho := 'null::jsonb';
  end if;

  execute format($q$
    with f0 (unit_id, class_id, area, setor, pessoa, num, den, d1, d2, d3, d4, d5, d6) as (%1$s),
    -- região = a do setor do fato (a região é a soma exata dos seus setores, como no mapa); sem setor, a do ponto
    f as (select f0.unit_id, f0.class_id, coalesce(sc.area_ponderacao_id, f0.area) area, f0.setor, f0.pessoa, f0.num, f0.den,
                 f0.d1, f0.d2, f0.d3, f0.d4, f0.d5, f0.d6
          from f0 left join iara.setores_censitarios sc on sc.code = f0.setor),
    fx as (select * from f where ($4::integer is null or unit_id = $4) and ($5::uuid is null or class_id = $5)
                             and ($6::integer is null or area = $6) and ($8::text is null or setor = $8)),
    pares as (select %2$s chave, %3$s val from f where %2$s is not null group by 1)
    select jsonb_build_object(
      'valor', (select %3$s from fx),
      'linhas', (select count(*) from fx),
      'pessoas', (select count(distinct pessoa) from fx),
      'rede', (select %3$s from f),
      'media', (select round(avg(val), 1) from pares),
      'posicao', (select jsonb_build_object('posicao', b.pos, 'de', b.tot) from (
                    select chave, rank() over (order by val %4$s nulls last) pos, count(*) over () tot from pares) b
                  where b.chave::text = $9),
      'quebras', jsonb_build_array(%5$s),
      'filhos', %6$s) $q$,
    v_fatos,
    coalesce(v_chave, 'null::text'),
    v_val, v_ordem, ltrim(v_quebras, ','), v_filho)
  into r
  using v_hoje, v_raio, v_ano, v_unit, v_class, v_area, v_sigilo, v_setor, v_id;

  -- sigilo: região ou microrregião com poucas pessoas não mostra nada (como no mapa)
  if v_sigilo and coalesce((r ->> 'pessoas')::int, 0) < v_min then
    r := jsonb_build_object('sigilo', true, 'minimo', v_min);
  else
    r := r - 'pessoas' || jsonb_build_object('sigilo', false);
  end if;
  return r || jsonb_build_object('camada', v_camada, 'nivel', v_nivel, 'id', v_id, 'nome', v_nome, 'pai', v_pai,
    'tipo', c.tipo, 'sufixo', c.sufixo, 'pior', c.pior, 'pela_casa', c.casa,
    'referencia', case when c.tipo = 'taxa' then 'Rede' else case v_nivel when 'unidade' then 'Média das unidades' when 'turma' then 'Média das turmas'
                    when 'area' then 'Média das regiões' when 'setor' then 'Média das microrregiões' end end,
    'atualizado_em', now());
end $$;

revoke all on function iara.rotulo_codigo(text), iara.mes_rotulo(date), iara.serie_rotulo(smallint) from public;

commit;
