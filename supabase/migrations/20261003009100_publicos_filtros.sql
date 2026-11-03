-- IARA Educa — 091 · Públicos do Prefeito: mais filtros, com o que o cadastro tem
-- Responsáveis: faixa etária e data de nascimento, sexo, vínculo com o aluno (mãe, pai, avó/avô, tia/tio…) e só o principal,
-- escolaridade, situação de trabalho, faixa de renda, estado civil, idioma, nacionalidade, pessoas na casa, zona, número de
-- filhos na rede, mãe solo e Bolsa Família; dos filhos, a idade e a data de nascimento.
-- Profissionais: cargo, área de atuação, tempo de rede e data de admissão (o cadastro não tem nascimento nem sexo deles).
-- Ficam de fora os dados sensíveis da LGPD (cor/raça, saúde, religião).
-- Sigilo: com mais filtros, um público pode chegar a poucas pessoas. Abaixo de 3, a contagem não aparece; o comunicado exige ao
-- menos 10 pessoas (um comunicado oficial não pode virar mensagem a uma pessoa escolhida).
begin;

create or replace function iara.publicos_lista(f jsonb, k text) returns text[]
language sql immutable
as $$ select coalesce(array(select jsonb_array_elements_text(case when jsonb_typeof(f -> k) = 'array' then f -> k else '[]' end)), '{}') $$;

create or replace function iara.publicos_data(f jsonb, k text) returns date
language sql immutable
as $$ select case when coalesce(f ->> k, '') ~ '^\d{4}-\d{2}-\d{2}$' then (f ->> k)::date end $$;

-- faixa etária do responsável, idade do filho e tempo de rede do profissional
create or replace function iara.publicos_faixa_idade(p_nasc date) returns text
language sql stable
as $$
  select case when p_nasc is null then null
    when age(iara.hoje_local(), p_nasc) < interval '25 years' then '18-24'
    when age(iara.hoje_local(), p_nasc) < interval '35 years' then '25-34'
    when age(iara.hoje_local(), p_nasc) < interval '45 years' then '35-44'
    when age(iara.hoje_local(), p_nasc) < interval '60 years' then '45-59'
    else '60+' end
$$;
create or replace function iara.publicos_faixa_filho(p_nasc date) returns text
language sql stable
as $$
  select case when p_nasc is null then null
    when age(iara.hoje_local(), p_nasc) < interval '4 years' then '0-3'
    when age(iara.hoje_local(), p_nasc) < interval '6 years' then '4-5'
    when age(iara.hoje_local(), p_nasc) < interval '11 years' then '6-10'
    else '11+' end
$$;
create or replace function iara.publicos_tempo_rede(p_admissao date) returns text
language sql stable
as $$
  select case when p_admissao is null then null
    when age(iara.hoje_local(), p_admissao) < interval '1 year' then '<1'
    when age(iara.hoje_local(), p_admissao) < interval '5 years' then '1-5'
    when age(iara.hoje_local(), p_admissao) < interval '10 years' then '5-10'
    when age(iara.hoje_local(), p_admissao) < interval '20 years' then '10-20'
    else '20+' end
$$;

-- quem forma o público, com o telefone normalizado (só dígitos) para conferir o bloqueio; nunca sai do banco
create or replace function iara.publicos_alvo(p_publico text, f jsonb)
returns table (pessoa uuid, unit_id integer, area integer, telefone text)
language plpgsql stable security definer set search_path = iara, extensions, public
as $$
declare
  v_unid integer[] := iara.publicos_lista(f, 'unidades')::integer[];
  v_areas integer[] := iara.publicos_lista(f, 'areas')::integer[];
  v_tipos text[] := iara.publicos_lista(f, 'tipos');
  -- profissionais
  v_funcoes text[] := iara.publicos_lista(f, 'funcoes');
  v_vinculos text[] := iara.publicos_lista(f, 'vinculos');
  v_situacoes text[] := iara.publicos_lista(f, 'situacoes');
  v_formacao text[] := iara.publicos_lista(f, 'formacao');
  v_carga text[] := iara.publicos_lista(f, 'carga');
  v_cargos text[] := iara.publicos_lista(f, 'cargos');
  v_atuacao text[] := iara.publicos_lista(f, 'areas_atuacao');
  v_tempos text[] := iara.publicos_lista(f, 'tempos_rede');
  v_adm_de date := iara.publicos_data(f, 'admissao_de');
  v_adm_ate date := iara.publicos_data(f, 'admissao_ate');
  -- filhos
  v_series text[] := iara.publicos_lista(f, 'series');
  v_turnos text[] := iara.publicos_lista(f, 'turnos');
  v_sit_aluno text[] := iara.publicos_lista(f, 'situacoes_aluno');
  v_idade_filho text[] := iara.publicos_lista(f, 'idades_filho');
  v_filho_de date := iara.publicos_data(f, 'filho_nasc_de');
  v_filho_ate date := iara.publicos_data(f, 'filho_nasc_ate');
  -- responsáveis
  v_relacoes text[] := iara.publicos_lista(f, 'relacoes');
  v_faixas text[] := iara.publicos_lista(f, 'faixas_etarias');
  v_nasc_de date := iara.publicos_data(f, 'nasc_de');
  v_nasc_ate date := iara.publicos_data(f, 'nasc_ate');
  v_sexos text[] := iara.publicos_lista(f, 'sexos');
  v_escol text[] := iara.publicos_lista(f, 'escolaridades');
  v_trab text[] := iara.publicos_lista(f, 'trabalhos');
  v_rendas text[] := iara.publicos_lista(f, 'rendas');
  v_civis text[] := iara.publicos_lista(f, 'estados_civis');
  v_idiomas text[] := iara.publicos_lista(f, 'idiomas');
  v_nacs text[] := iara.publicos_lista(f, 'nacionalidades');
  v_casa text[] := iara.publicos_lista(f, 'pessoas_casa');
  v_zonas text[] := iara.publicos_lista(f, 'zonas');
  v_nfilhos text[] := iara.publicos_lista(f, 'num_filhos');
begin
  if p_publico = 'PROFISSIONAIS' then
    return query
      select st.id, st.unit_id, u.macro_territory_id, null::text
      from iara.staff st left join iara.education_units u on u.id = st.unit_id
      where (cardinality(v_unid) = 0 or st.unit_id = any (v_unid))
        and (cardinality(v_areas) = 0 or u.macro_territory_id = any (v_areas))
        and (cardinality(v_tipos) = 0 or u.unit_type = any (v_tipos))
        and (cardinality(v_funcoes) = 0 or st.role = any (v_funcoes))
        and (cardinality(v_vinculos) = 0 or st.bond = any (v_vinculos))
        and (cardinality(v_situacoes) = 0 or coalesce(st.situacao, 'ATIVO') = any (v_situacoes))
        and (cardinality(v_formacao) = 0 or coalesce(iara.formacao_nivel(st.escolaridade), 0)::text = any (v_formacao))
        and (cardinality(v_carga) = 0 or st.carga_horaria_semanal::text = any (v_carga))
        and (cardinality(v_cargos) = 0 or st.cargo = any (v_cargos))
        and (cardinality(v_atuacao) = 0 or st.area_atuacao = any (v_atuacao))
        and (cardinality(v_tempos) = 0 or iara.publicos_tempo_rede(st.data_admissao) = any (v_tempos))
        and (v_adm_de is null or st.data_admissao >= v_adm_de)
        and (v_adm_ate is null or st.data_admissao <= v_adm_ate);
  elsif p_publico = 'RESPONSAVEIS' then
    return query
      with filhos as (
        select s.id, e.unit_id, a.territory_id area_casa
        from iara.students s
        left join lateral (select e2.unit_id, e2.class_id from iara.enrollments e2
                           where e2.student_id = s.id and e2.status = 'ACTIVE' order by e2.start_date desc nulls last limit 1) e on true
        left join iara.classes c on c.id = e.class_id
        left join iara.addresses a on a.id = s.address_id
        where (cardinality(v_unid) = 0 or e.unit_id = any (v_unid)
               or exists (select 1 from iara.waiting_list_entries w where w.student_id = s.id and w.status in ('WAITING', 'OFFERED') and w.preferred_unit_id = any (v_unid)))
          and (cardinality(v_tipos) = 0 or exists (select 1 from iara.education_units u where u.id = e.unit_id and u.unit_type = any (v_tipos)))
          and (cardinality(v_areas) = 0 or a.territory_id = any (v_areas))
          and (cardinality(v_series) = 0 or c.grade_level_id::text = any (v_series)
               or exists (select 1 from iara.waiting_list_entries w where w.student_id = s.id and w.status in ('WAITING', 'OFFERED')
                            and w.grade_level_id::text = any (v_series)))
          and (cardinality(v_turnos) = 0 or c.shift = any (v_turnos))
          and (cardinality(v_sit_aluno) = 0 or s.status = any (v_sit_aluno))
          and (cardinality(v_idade_filho) = 0 or iara.publicos_faixa_filho(s.birth_date) = any (v_idade_filho))
          and (v_filho_de is null or s.birth_date >= v_filho_de)
          and (v_filho_ate is null or s.birth_date <= v_filho_ate)
          and (coalesce((f ->> 'fila')::boolean, false) = false
               or exists (select 1 from iara.waiting_list_entries w where w.student_id = s.id and w.status in ('WAITING', 'OFFERED')))
          and (coalesce((f ->> 'transporte')::boolean, false) = false
               or exists (select 1 from iara.transporte_alunos ta where ta.student_id = s.id and ta.fim is null))
          and (coalesce((f ->> 'aee')::boolean, false) = false or s.aee_status)
          and (coalesce((f ->> 'alerta_frequencia')::boolean, false) = false
               or exists (select 1 from iara.frequencia_alertas fa where fa.student_id = s.id and fa.situacao <> 'RESOLVIDO')))
      select distinct on (g.id) g.id, fi.unit_id, fi.area_casa,
             nullif(regexp_replace(coalesce(g.whatsapp_phone, g.primary_phone, ''), '\D', '', 'g'), '')
      from filhos fi
      join iara.student_guardians sg on sg.student_id = fi.id and sg.end_date is null
      join iara.guardians g on g.id = sg.guardian_id
      left join iara.addresses ga on ga.id = g.address_id
      where coalesce(sg.can_receive_notifications, true)
        and (cardinality(v_relacoes) = 0 or sg.relationship = any (v_relacoes))
        and (coalesce((f ->> 'principal')::boolean, false) = false or sg.is_primary)
        and (cardinality(v_faixas) = 0 or iara.publicos_faixa_idade(g.birth_date) = any (v_faixas))
        and (v_nasc_de is null or g.birth_date >= v_nasc_de)
        and (v_nasc_ate is null or g.birth_date <= v_nasc_ate)
        and (cardinality(v_sexos) = 0 or g.gender::text = any (v_sexos))
        and (cardinality(v_escol) = 0 or g.education_level = any (v_escol))
        and (cardinality(v_trab) = 0 or g.employment_status = any (v_trab))
        and (cardinality(v_rendas) = 0 or coalesce(g.income_bracket, 'Não informada') = any (v_rendas))
        and (cardinality(v_civis) = 0 or g.marital_status = any (v_civis))
        and (cardinality(v_idiomas) = 0 or g.preferred_language = any (v_idiomas))
        and (cardinality(v_nacs) = 0 or g.nationality = any (v_nacs))
        and (cardinality(v_casa) = 0 or (case when g.household_size >= 5 then '5+' else g.household_size::text end) = any (v_casa))
        and (cardinality(v_zonas) = 0 or ga.zone = any (v_zonas))
        and (cardinality(v_nfilhos) = 0 or (select case when count(*) >= 3 then '3+' else count(*)::text end
                                            from iara.student_guardians x where x.guardian_id = g.id and x.end_date is null) = any (v_nfilhos))
        and (coalesce((f ->> 'mae_solo')::boolean, false) = false or g.single_mother)
        and (coalesce((f ->> 'bolsa_familia')::boolean, false) = false or g.benefits ? 'Bolsa Família')
        and (coalesce((f ->> 'cadunico')::boolean, false) = false or g.cadunico_status)
      order by g.id, sg.is_primary desc;
  else
    raise exception 'Público inválido: use PROFISSIONAIS ou RESPONSAVEIS.' using errcode = '22023';
  end if;
end $$;

create or replace function api.publicos_opcoes(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_escol text[] := array['Sem escolaridade', 'Fundamental incompleto', 'Fundamental completo', 'Médio incompleto', 'Médio completo',
                          'Superior incompleto', 'Superior completo', 'Pós-graduação'];
  v_rendas text[] := array['Até 1 salário mínimo', '1 a 2 salários mínimos', '2 a 3 salários mínimos', '3 a 5 salários mínimos',
                           'Acima de 5 salários mínimos', 'Não informada'];
begin
  perform iara.require_perm('publicos.prefeito');
  return jsonb_build_object(
    'unidades', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nome', short_name, 'tipo', unit_type, 'area', macro_territory_id) order by short_name), '[]')
                 from iara.education_units),
    'areas', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nome', name) order by name), '[]') from iara.territories where kind = 'AREA_PONDERACAO'),
    'funcoes', (select coalesce(jsonb_agg(distinct role), '[]') from iara.staff),
    'vinculos', (select coalesce(jsonb_agg(distinct bond), '[]') from iara.staff where bond is not null),
    'situacoes', (select coalesce(jsonb_agg(distinct coalesce(situacao, 'ATIVO')), '[]') from iara.staff),
    'cargas', (select coalesce(jsonb_agg(distinct carga_horaria_semanal order by carga_horaria_semanal), '[]') from iara.staff where carga_horaria_semanal is not null),
    'cargos', (select coalesce(jsonb_agg(distinct cargo), '[]') from iara.staff where cargo is not null),
    'areas_atuacao', (select coalesce(jsonb_agg(distinct area_atuacao), '[]') from iara.staff where area_atuacao is not null),
    'series', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nome', short_name) order by sort), '[]') from iara.grade_levels),
    'situacoes_aluno', (select coalesce(jsonb_agg(distinct status), '[]') from iara.students),
    'relacoes', (select coalesce(jsonb_agg(relationship order by n desc), '[]')
                 from (select relationship, count(*) n from iara.student_guardians where end_date is null group by 1) x),
    'escolaridades', (select coalesce(jsonb_agg(x order by coalesce(array_position(v_escol, x), 99), x), '[]')
                      from (select distinct education_level x from iara.guardians where education_level is not null) q),
    'trabalhos', (select coalesce(jsonb_agg(distinct employment_status), '[]') from iara.guardians where employment_status is not null),
    'rendas', (select coalesce(jsonb_agg(x order by coalesce(array_position(v_rendas, x), 99), x), '[]')
               from (select distinct coalesce(income_bracket, 'Não informada') x from iara.guardians) q),
    'estados_civis', (select coalesce(jsonb_agg(distinct marital_status), '[]') from iara.guardians where marital_status is not null),
    'idiomas', (select coalesce(jsonb_agg(distinct preferred_language), '[]') from iara.guardians),
    'nacionalidades', (select coalesce(jsonb_agg(distinct nationality), '[]') from iara.guardians),
    'zonas', (select coalesce(jsonb_agg(distinct a.zone), '[]') from iara.guardians g join iara.addresses a on a.id = g.address_id),
    'modelos', (select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'nome', nome, 'publico', publico, 'categoria', categoria, 'corpo', corpo) order by nome), '[]')
                from iara.publicos_modelos where ativo),
    'periodo_eleitoral', iara.publicos_periodo_eleitoral());
end $$;

-- p: publico, filtros. Só contagens; abaixo de 3 pessoas o público inteiro fica em sigilo, e os recortes também.
create or replace function api.publicos_contar(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_pub text := coalesce(p ->> 'publico', 'RESPONSAVEIS');
  v_f jsonb := coalesce(p -> 'filtros', '{}'::jsonb);
  r jsonb;
begin
  perform iara.require_perm('publicos.prefeito');
  with a as (select * from iara.publicos_alvo(v_pub, v_f)),
  b as (select a.*, iara.publicos_nao_quer(a.telefone) nao_quer from a)
  select jsonb_build_object(
    'publico', v_pub,
    'total', (select count(*) from b),
    'com_contato', (select count(*) from b where telefone is not null and not nao_quer),
    'sem_contato', (select count(*) from b where telefone is null),
    'nao_querem', (select count(*) from b where nao_quer),
    'por_unidade', (select coalesce(jsonb_agg(jsonb_build_object('nome', u.short_name, 'n', q.n) order by q.n desc), '[]') from (
                      select unit_id, count(*) n from b where unit_id is not null group by unit_id having count(*) >= 3 order by count(*) desc limit 10) q
                    join iara.education_units u on u.id = q.unit_id),
    'por_regiao', (select coalesce(jsonb_agg(jsonb_build_object('nome', t.name, 'n', q.n) order by q.n desc), '[]') from (
                     select area, count(*) n from b where area is not null group by area having count(*) >= 3 order by count(*) desc limit 10) q
                   join iara.territories t on t.id = q.area)) into r;
  if (r ->> 'total')::int between 1 and 2 then
    r := jsonb_build_object('publico', v_pub, 'total', null, 'com_contato', null, 'sem_contato', null, 'nao_querem', null,
                            'por_unidade', '[]'::jsonb, 'por_regiao', '[]'::jsonb, 'sigilo', true);
  end if;
  return r || jsonb_build_object('minimo_envio', 10,
    'nota', 'Só contagens: nenhum nome, telefone ou identificador. Públicos e recortes com menos de 3 pessoas ficam em sigilo.');
end $$;

-- p: publico, filtros, modelo, texto. Registra o envio (simulado na demonstração) e audita; bloqueia no período eleitoral
-- e para públicos com menos de 10 pessoas.
create or replace function api.publicos_enviar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_pub text := coalesce(p ->> 'publico', 'RESPONSAVEIS');
  v_f jsonb := coalesce(p -> 'filtros', '{}'::jsonb);
  v_modelo iara.publicos_modelos;
  v_texto text := btrim(coalesce(p ->> 'texto', ''));
  v_total integer; v_com integer; v_sem integer; v_nao integer;
  v_situacao text;
  v_id uuid;
  v_ele jsonb := iara.publicos_periodo_eleitoral();
begin
  perform iara.require_perm('publicos.prefeito');
  select * into v_modelo from iara.publicos_modelos where codigo = p ->> 'modelo' and ativo;
  if v_modelo.codigo is null then
    raise exception 'Escolha um modelo de mensagem aprovado.' using errcode = '22023';
  end if;
  if v_modelo.publico <> 'TODOS' and v_modelo.publico <> v_pub then
    raise exception 'Este modelo não serve para este público.' using errcode = '22023';
  end if;
  if length(v_texto) < 10 or length(v_texto) > 700 then
    raise exception 'Escreva a mensagem (de 10 a 700 caracteres).' using errcode = '22023';
  end if;
  select count(*), count(*) filter (where telefone is not null and not iara.publicos_nao_quer(telefone)),
         count(*) filter (where telefone is null), count(*) filter (where iara.publicos_nao_quer(telefone))
    into v_total, v_com, v_sem, v_nao
  from iara.publicos_alvo(v_pub, v_f);
  if v_total = 0 then
    raise exception 'Ninguém neste público.' using errcode = '22023';
  end if;
  if v_total < 10 then
    raise exception 'Público pequeno demais para um comunicado (menos de 10 pessoas). Use filtros mais amplos.' using errcode = '22023';
  end if;
  v_situacao := case when (v_ele ->> 'restrito')::boolean then 'BLOQUEADO_ELEITORAL' when iara.demo_mode() then 'SIMULADO' else 'ENFILEIRADO' end;
  insert into iara.publicos_envios (autor_label, publico, filtros, modelo, texto, total, com_contato, sem_contato, nao_querem, enviados, situacao, is_demo)
  values (iara.my_label(), v_pub, v_f, v_modelo.codigo, v_texto, v_total, v_com, v_sem, v_nao,
          case when v_situacao = 'BLOQUEADO_ELEITORAL' then 0 else v_com end, v_situacao, iara.demo_mode())
  returning id into v_id;
  perform iara.audit_event('PUBLICO_ENVIO', 'publicos_envios', v_id::text, null,
    format('Envio aos %s (%s pessoas, %s com contato): %s', lower(v_pub), v_total, v_com, v_situacao),
    jsonb_build_object('publico', v_pub, 'filtros', v_f, 'modelo', v_modelo.codigo, 'total', v_total, 'situacao', v_situacao));
  -- produção: aqui entram as mensagens na fila do WhatsApp oficial (modelo aprovado pela Meta), um por pessoa com contato
  return jsonb_build_object('id', v_id, 'situacao', v_situacao, 'total', v_total, 'enviados', case when v_situacao = 'BLOQUEADO_ELEITORAL' then 0 else v_com end,
    'sem_contato', v_sem, 'nao_querem', v_nao, 'periodo_eleitoral', v_ele,
    'mensagem', replace(v_modelo.corpo, '{texto}', v_texto));
end $$;

revoke all on function iara.publicos_alvo(text, jsonb), iara.publicos_lista(jsonb, text), iara.publicos_data(jsonb, text),
  iara.publicos_faixa_idade(date), iara.publicos_faixa_filho(date), iara.publicos_tempo_rede(date) from public;

commit;
