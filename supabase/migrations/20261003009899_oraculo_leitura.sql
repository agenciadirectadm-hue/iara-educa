-- IARA Educa — 098.99 · Oráculo que interpreta: dados tratados em informação para o Prefeito.
-- Pedido de Rob (05/11/2026): "muitos dados e poucas informações". Exemplo dele: em Brasília, o Prefeito pergunta "o que nossos alunos de ensino
-- fundamental comeram hoje?" e a resposta traz as refeições de ontem, o cardápio de ontem, o cardápio de hoje e diz que os números de hoje não fecharam.
-- Regras de toda resposta:
--   1. Responde primeiro o que foi perguntado, na mesma etapa, unidade, região e dia.
--   2. Sem o dado exato, traz o melhor dado disponível e diz o que ainda não fechou. Nunca termina num beco sem saída.
--   3. Número vem com sentido: a base (de quantos), a comparação (com a média), a causa e onde se concentra.
--   4. Termina no que dá para decidir: "Sugestão". Sugestão vem de regra sobre os números, nunca de número inventado.
--   5. Sem pessoas: só agregados; 1 ou 2 pessoas não aparecem.
-- O roteador antigo continua atrás deste (iara.oraculo_perguntar_base): nomes, dados de pessoa, comparações pedidas e os pedidos de detalhe completo.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

-- 1. Apoio ----------------------------------------------------------------------------------------------------------------------------
create or replace function iara.oraculo_n(p_chave text, p_units integer[], p_cidade boolean) returns numeric
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  i iara.oraculo_indicadores;
  v numeric;
begin
  select * into i from iara.oraculo_indicadores where chave = p_chave;
  if i.chave is null or i.consulta is null then return null; end if;
  begin
    v := iara.oraculo_valor(i.consulta, p_units, p_cidade);
  exception when others then
    return null;
  end;
  if i.pessoas and v between 1 and 2 then return null; end if;
  return v;
end $$;

create or replace function iara.oraculo_cap(p text) returns text language sql immutable as $$ select upper(left(p, 1)) || substr(p, 2) $$;
-- primeira letra minúscula, menos em siglas
create or replace function iara.oraculo_min(p text) returns text language sql immutable as $$
  select case when substr(p, 2, 1) = upper(substr(p, 2, 1)) then p else lower(left(p, 1)) || substr(p, 2) end
$$;
create or replace function iara.oraculo_pct(a numeric, b numeric, p_casas integer default 0) returns text language sql immutable set search_path = iara, public as $$
  select case when a is null or b is null or b = 0 then null else iara.num_br(round(100 * a / b, p_casas), p_casas) || '%' end
$$;
create or replace function iara.oraculo_e(p text[]) returns text language sql immutable as $$
  select case when cardinality(p) = 0 then '' when cardinality(p) = 1 then p[1]
              else array_to_string(p[1:cardinality(p) - 1], ', ') || ' e ' || p[cardinality(p)] end
$$;
create or replace function iara.oraculo_quando(d date, p_hoje date) returns text language sql immutable set search_path = iara, public as $$
  select case when d = p_hoje then 'hoje (' || iara.oraculo_dia_semana(d) || ')'
              when d = p_hoje - 1 then 'ontem (' || iara.oraculo_dia_semana(d) || ')'
              when d = p_hoje - 2 then 'anteontem (' || iara.oraculo_dia_semana(d) || ')'
              when extract(isodow from d) in (6, 7) then 'no ' || iara.oraculo_dia_semana(d)
              else 'na ' || iara.oraculo_dia_semana(d) end
$$;

-- os primeiros itens de um detalhe: "saúde (35%)", sem o que não diz nada
create or replace function iara.oraculo_top(p_chave text, p_units integer[], p_cidade boolean, p_limite integer default 2) returns text[]
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  x jsonb;
begin
  begin
    x := iara.oraculo_detalhe_lista(p_chave, p_units, p_cidade, p_limite + 2);
  exception when others then
    return '{}';
  end;
  return coalesce((select array_agg(iara.oraculo_min(regexp_replace(i ->> 'nome', ' \([^)]*\)$', '')) || coalesce(' (' || iara.num_br(round((i ->> 'pct')::numeric)) || '%)', ' (' || iara.num_br((i ->> 'valor')::numeric) || ')') order by (i ->> 'valor')::numeric desc)
                   from (select i from jsonb_array_elements(x -> 'itens') i
                         where i ->> 'nome' !~* '^(outros?|demais|não informado)' order by (i ->> 'valor')::numeric desc limit p_limite) q), '{}');
end $$;

-- as regiões onde o indicador mais pesa, sem o código do IBGE no nome
create or replace function iara.oraculo_onde(p_chave text, p_ordem text default null, p_limite integer default 3, p_por text default 'regiao') returns text[]
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  x jsonb;
begin
  begin
    x := iara.oraculo_ranking_lista(p_chave, p_por, p_ordem, p_limite);
  exception when others then
    return '{}';
  end;
  return coalesce((select array_agg(regexp_replace(i ->> 'nome', '^AP [0-9]+ · ', '') || ' (' || iara.num_br((i ->> 'valor')::numeric, coalesce((x ->> 'casas')::int, 0)) || coalesce(x ->> 'sufixo', '') || ')' order by o)
                   from jsonb_array_elements(x -> 'lista') with ordinality t(i, o)), '{}');
end $$;

-- vagas livres em filas com criança esperando (mesma unidade e mesma faixa)
create or replace function iara.oraculo_vagas_paradas(p_units integer[], out vagas numeric, out filas integer)
language sql stable security definer set search_path = iara, public
as $$
  select coalesce(sum(q.v), 0), count(*)::int from (
    select sum(c.offerable_vacancies_count) v from iara.classes c
    where c.status = 'ATIVA' and c.offerable_vacancies_count > 0 and c.unit_id = any (p_units)
      and exists (select 1 from iara.waiting_list_entries w where w.preferred_unit_id = c.unit_id and w.grade_level_id = c.grade_level_id and w.status = 'WAITING')
    group by c.unit_id, c.grade_level_id) q
$$;

-- 2. Merenda: o que comeram ------------------------------------------------------------------------------------------------------------
-- as linhas do cardápio de um dia: de uma faixa, ou de toda a rede agrupando o que é igual; só as refeições pedidas
create or replace function iara.oraculo_cardapio_linhas(x jsonb, p_faixa text, p_refeicoes text[] default null) returns text
language plpgsql immutable set search_path = iara, public
as $$
declare
  v text := '';
  g record;
  r jsonb;
  n integer := 0;
begin
  for g in select string_agg(t.f ->> 'rotulo', ', ' order by t.o) rotulos, t.f -> 'refeicoes' refeicoes, count(*) over () grupos
           from jsonb_array_elements(x -> 'faixas') with ordinality t(f, o)
           where jsonb_array_length(t.f -> 'refeicoes') > 0 and (p_faixa is null or t.f ->> 'faixa' = p_faixa)
           group by t.f -> 'refeicoes' order by min(t.o) loop
    if g.grupos > 1 then v := v || case when n > 0 then E'\n' else '' end || g.rotulos || ':'; end if;
    for r in select * from jsonb_array_elements(g.refeicoes) loop
      if p_refeicoes is null or r ->> 'refeicao' = any (p_refeicoes) then
        v := v || case when v = '' then '' else E'\n' end || '• ' || (r ->> 'refeicao') || ': ' || (select string_agg(lower(i), ', ') from jsonb_array_elements_text(r -> 'itens') i);
      end if;
    end loop;
    n := n + 1;
  end loop;
  return nullif(v, '');
end $$;

create or replace function iara.oraculo_ler_merenda(p_w text, p_units integer[], p_cidade boolean, p_nome text) returns text
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_hoje date := iara.hoje_local();
  v_faixa text := case when p_w ~ ' (ensino fundamental|fundamental|anos iniciais|[1-5]o ano|[1-5] ano) ' then 'EF'
                       when p_w ~ ' (pre escola|preescola|pre) ' then 'PRE'
                       when p_w ~ ' (creche|creches|bercario|bercarios|bebes) ' then 'CRECHE' end;
  v_units integer[];
  v_sujeito text;
  v_etapa text;
  v_alvo date := iara.oraculo_data_da_pergunta(p_w, v_hoje);
  v_fech date;
  v_total numeric;
  v_adapt numeric;
  v_nunid integer;
  v_nprev integer;
  v_media numeric;
  v_comp text;
  v_ref text[];
  v_por text;
  v_linhas text;
  v_txt text;
  v_hoje_n numeric;
  v_hoje_u integer;
  x jsonb;
  v_custo text := '';
begin
  v_units := case
    when v_faixa = 'EF' then array(select u.id from iara.education_units u where u.id = any (p_units) and u.unit_type = 'ESCOLA')
    when v_faixa in ('PRE', 'CRECHE') then array(select u.id from iara.education_units u where u.id = any (p_units) and u.unit_type = 'CMEI')
    else p_units end;
  v_nprev := cardinality(v_units);
  v_etapa := case v_faixa when 'EF' then ' do ensino fundamental' when 'PRE' then ' da pré-escola' when 'CRECHE' then ' da creche' else '' end;
  v_sujeito := case
    when not p_cidade and cardinality(p_units) = 1 then p_nome
    when v_faixa = 'EF' then 'as ' || iara.num_br(v_nprev) || ' escolas de ensino fundamental' || case when p_cidade then '' else ' de ' || p_nome end
    when v_faixa in ('PRE', 'CRECHE') then 'os ' || iara.num_br(v_nprev) || ' CMEIs (creche e pré-escola)' || case when p_cidade then '' else ' de ' || p_nome end
    else case when p_cidade then 'a rede' else p_nome end end;
  if v_nprev = 0 then
    return 'Não há ' || case when v_faixa = 'EF' then 'escola de ensino fundamental' else 'CMEI' end || ' em ' || p_nome || '. Pergunte pela rede inteira ou por outra etapa.';
  end if;
  if p_w ~ ' (custa|custam|custo|custos|custou|gasto|gastos|preco|precos|valor|valores) ' then
    v_custo := 'O custo da merenda não está no IARA Educa: fica nos sistemas de gestão da Prefeitura. O que o IARA acompanha é o que foi servido:' || E'\n\n';
  end if;

  -- dia futuro: só existe o cardápio
  if v_alvo > v_hoje then
    x := iara.oraculo_cardapio_dia(v_alvo);
    v_linhas := iara.oraculo_cardapio_linhas(x, v_faixa);
    return v_custo || coalesce(x ->> 'aviso', '') || case when x ->> 'aviso' is not null then ' ' else '' end
      || coalesce('O cardápio' || v_etapa || ' de ' || (x ->> 'dia') || ' é:' || E'\n' || v_linhas, 'Ainda não há cardápio publicado para ' || (x ->> 'dia') || '.')
      || E'\n\nAs refeições servidas só existem depois do dia: a cozinha de cada unidade lança no próprio dia.';
  end if;

  -- o último dia fechado: nunca o de hoje, que ainda está sendo lançado
  select max(s.data) into v_fech from iara.refeicoes_servidas s where s.unit_id = any (v_units) and s.data <= least(v_alvo, v_hoje - 1);
  if v_fech is not null then
    select sum(s.quantidade), sum(s.adaptadas), count(distinct s.unit_id) into v_total, v_adapt, v_nunid from iara.refeicoes_servidas s where s.unit_id = any (v_units) and s.data = v_fech;
    select array_agg(iara.oraculo_rotulo(q.refeicao) order by q.n desc),
           iara.oraculo_e(array_agg(iara.num_br(q.n) || ' no ' || lower(iara.oraculo_rotulo(q.refeicao)) order by q.n desc) filter (where q.n >= v_total * 0.005))
      into v_ref, v_por
    from (select s.refeicao, sum(s.quantidade) n from iara.refeicoes_servidas s where s.unit_id = any (v_units) and s.data = v_fech group by 1) q;
    select array_agg(iara.oraculo_rotulo(q.refeicao)) into v_ref
    from (select s.refeicao from iara.refeicoes_servidas s where s.unit_id = any (v_units) and s.data = v_fech group by 1 having sum(s.quantidade) >= v_total * 0.005) q;
    -- média dos 20 dias anteriores com registro
    select avg(q.n) into v_media from (select sum(s.quantidade) n from iara.refeicoes_servidas s where s.unit_id = any (v_units) and s.data < v_fech and s.data >= v_fech - 45
                                       group by s.data order by s.data desc limit 20) q;
    v_comp := case when v_media is null or v_media = 0 then ''
                   when abs(v_total - v_media) / v_media <= 0.05 then ', dentro da média das últimas semanas'
                   when v_total > v_media then ', ' || iara.oraculo_pct(v_total - v_media, v_media) || ' acima da média das últimas semanas'
                   else ', ' || iara.oraculo_pct(v_media - v_total, v_media) || ' abaixo da média das últimas semanas' end;
    x := iara.oraculo_cardapio_dia(v_fech);
    v_linhas := iara.oraculo_cardapio_linhas(x, v_faixa, v_ref);
    v_txt := iara.oraculo_cap(iara.oraculo_quando(v_fech, v_hoje)) || ', ' || v_sujeito
      || case when v_sujeito ~ '^(as|os) ' then ' serviram ' else ' serviu ' end || iara.num_br(v_total) || ' refeições' || v_comp
      || case when v_por <> '' then ': ' || v_por else '' end || '.'
      || case when v_adapt >= 3 then ' Dessas, ' || iara.num_br(v_adapt) || ' foram adaptadas para alunos com restrição alimentar.' else '' end
      || case when v_nunid < v_nprev then ' Lançaram ' || iara.num_br(v_nunid) || ' de ' || iara.num_br(v_nprev) || ' unidades.' else '' end
      || coalesce(E'\n\nO cardápio foi:\n' || v_linhas, '');
  else
    v_txt := 'Ainda não há refeições lançadas neste recorte.';
  end if;

  -- o dia de hoje: o cardápio é certo; o número ainda não
  if v_alvo = v_hoje then
    x := iara.oraculo_cardapio_dia(v_hoje);
    select coalesce(sum(s.quantidade), 0), count(distinct s.unit_id) into v_hoje_n, v_hoje_u from iara.refeicoes_servidas s where s.unit_id = any (v_units) and s.data = v_hoje;
    if x ->> 'aviso' is not null then
      v_txt := v_txt || E'\n\n' || (x ->> 'aviso')
        || coalesce(' O próximo cardápio' || v_etapa || ', de ' || (x ->> 'dia') || ', é:' || E'\n' || iara.oraculo_cardapio_linhas(x, v_faixa, v_ref), '');
    else
      v_linhas := iara.oraculo_cardapio_linhas(x, v_faixa, v_ref);
      v_txt := v_txt || E'\n\n' || coalesce('Hoje (' || iara.oraculo_dia_semana(v_hoje) || '), o cardápio' || v_etapa || ' é:' || E'\n' || v_linhas, 'Hoje (' || iara.oraculo_dia_semana(v_hoje) || ') não há cardápio publicado para esta etapa.')
        || E'\n\n' || case when v_hoje_n > 0
             then 'Os números de hoje ainda não fecharam: até agora, ' || iara.num_br(v_hoje_n) || ' refeições lançadas' || case when v_nprev > 1 then ' por ' || iara.num_br(v_hoje_u) || ' de ' || iara.num_br(v_nprev) || ' unidades' else '' end || '.'
             else 'Os números de hoje ainda não fecharam: as cozinhas lançam ao longo do dia.' end;
    end if;
  end if;
  -- quem pergunta só pelo cardápio recebe o cardápio do dia primeiro; o número vem depois, como apoio
  if v_alvo = v_hoje and x ->> 'aviso' is null and p_w ~ ' (cardapio|cardapios) ' and p_w !~ ' (comeram|comeu|comem|comendo|almocaram|lancharam|jantaram|servid\w*|serviram|refeicao|refeicoes) ' then
    v_linhas := iara.oraculo_cardapio_linhas(x, v_faixa);
    if v_linhas is not null then
      return v_custo || 'Hoje (' || iara.oraculo_dia_semana(v_hoje) || '), o cardápio' || v_etapa || case when v_faixa is null then ' é o mesmo em toda a rede:' else ' é:' end || E'\n' || v_linhas
        || case when v_fech is not null then E'\n\n' || iara.oraculo_cap(iara.oraculo_quando(v_fech, v_hoje)) || ', foram servidas ' || iara.num_br(v_total) || ' refeições' || v_comp || '.' else '' end
        || case when v_hoje_n > 0 then ' Os números de hoje ainda não fecharam: até agora, ' || iara.num_br(v_hoje_n) || ' lançadas.' else ' Os números de hoje ainda não fecharam.' end;
    end if;
  end if;
  return v_custo || v_txt;
end $$;

-- 3. Transporte: funcionou? ------------------------------------------------------------------------------------------------------------
create or replace function iara.oraculo_ler_transporte(p_w text, p_units integer[], p_cidade boolean, p_nome text) returns text
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_hoje date := iara.hoje_local();
  v_cod text := iara.oraculo_periodo_da_pergunta(p_w);
  pd record;
  v_de date;
  v_ate date;
  v_aviso text := '';
  v_quando text;
  t record;
  v_rotas text[];
  v_motivos text[];
  v_causa text;
  v_causa_n integer;
  v_perd30 integer;
  v_veic numeric := iara.oraculo_n('frota.vistoria', p_units, p_cidade);
  v_txt text;
  v_sug text;
begin
  if v_cod is null then v_cod := 'hoje'; end if;
  pd := iara.oraculo_periodo_datas(v_cod, v_hoje);
  v_de := pd.de; v_ate := pd.ate;
  if not exists (select 1 from iara.transporte_viagens v join iara.transporte_rotas r on r.id = v.rota_id where r.unit_id = any (p_units) and v.data between v_de and v_ate) then
    select max(v.data) into v_ate from iara.transporte_viagens v join iara.transporte_rotas r on r.id = v.rota_id where r.unit_id = any (p_units) and v.data <= pd.ate;
    if v_ate is null then return 'Não há viagens de transporte escolar registradas em ' || p_nome || '.'; end if;
    v_de := v_ate;
    v_aviso := iara.oraculo_cap(iara.oraculo_quando(pd.ate, v_hoje)) || ', as viagens ainda não fecharam. O último dia fechado:' || E'\n\n';
  end if;
  v_quando := case when v_de = v_ate then iara.oraculo_quando(v_de, v_hoje) else 'de ' || to_char(v_de, 'DD/MM') || ' a ' || to_char(v_ate, 'DD/MM') end;
  select count(*) total, count(*) filter (where v.situacao = 'NAO_REALIZADA') perdidas,
         count(*) filter (where coalesce(v.atraso_min, 0) > 0) atrasos, count(*) filter (where coalesce(v.atraso_min, 0) > 15) graves,
         round(avg(v.atraso_min) filter (where v.atraso_min > 0)) media_atraso,
         coalesce(sum(v.alunos_previstos), 0) previstos, coalesce(sum(v.alunos_transportados), 0) levados,
         coalesce(sum(v.alunos_previstos) filter (where v.situacao = 'NAO_REALIZADA'), 0) sem_transporte
    into t from iara.transporte_viagens v join iara.transporte_rotas r on r.id = v.rota_id where r.unit_id = any (p_units) and v.data between v_de and v_ate;
  select array_agg(q.txt) into v_rotas from (
    select r.codigo || ' (' || u.short_name || ')' txt from iara.transporte_viagens v join iara.transporte_rotas r on r.id = v.rota_id join iara.education_units u on u.id = r.unit_id
    where r.unit_id = any (p_units) and v.data between v_de and v_ate and v.situacao = 'NAO_REALIZADA' group by 1 order by count(*) desc, 1 limit 3) q;
  select array_agg(iara.oraculo_min(q.motivo) || case when t.perdidas > 1 then ' (' || q.n || ')' else '' end) into v_motivos from (
    select coalesce(v.motivo, 'motivo não informado') motivo, count(*) n from iara.transporte_viagens v join iara.transporte_rotas r on r.id = v.rota_id
    where r.unit_id = any (p_units) and v.data between v_de and v_ate and v.situacao = 'NAO_REALIZADA' group by 1 order by 2 desc, 1 limit 3) q;
  select count(*) into v_perd30 from iara.transporte_viagens v join iara.transporte_rotas r on r.id = v.rota_id
  where r.unit_id = any (p_units) and v.data >= v_hoje - 30 and v.situacao = 'NAO_REALIZADA';
  select q.motivo, q.n into v_causa, v_causa_n from (select v.motivo, count(*) n from iara.transporte_viagens v join iara.transporte_rotas r on r.id = v.rota_id
    where r.unit_id = any (p_units) and v.data >= v_hoje - 30 and v.situacao = 'NAO_REALIZADA' and v.motivo is not null group by 1 order by 2 desc limit 1) q;

  if t.perdidas = 0 then
    v_txt := iara.oraculo_cap(v_quando) || ', todas as ' || iara.num_br(t.total) || ' viagens do transporte escolar aconteceram.';
  else
    v_txt := iara.oraculo_cap(v_quando) || ', ' || iara.num_br(t.perdidas) || ' das ' || iara.num_br(t.total) || ' viagens do transporte escolar não aconteceram ('
      || iara.oraculo_pct(t.perdidas, t.total, 1) || ')'
      || case when t.sem_transporte >= 3 then ', e ' || iara.num_br(t.sem_transporte) || ' alunos ficaram sem o transporte' when t.sem_transporte > 0 then ', com menos de 3 alunos afetados' else '' end || '.';
    if coalesce(cardinality(v_rotas), 0) > 0 then v_txt := v_txt || E'\n• Rotas: ' || iara.oraculo_e(v_rotas) || case when t.perdidas > 3 then ', entre outras' else '' end || '.'; end if;
    if coalesce(cardinality(v_motivos), 0) > 0 then v_txt := v_txt || E'\n• Causa: ' || iara.oraculo_e(v_motivos) || '.'; end if;
  end if;
  if t.previstos > 0 then
    v_txt := v_txt || E'\n• Alunos levados: ' || iara.num_br(t.levados) || ' de ' || iara.num_br(t.previstos) || ' previstos (' || iara.oraculo_pct(t.levados, t.previstos) || ').';
  end if;
  if t.atrasos > 0 then
    v_txt := v_txt || E'\n• Atrasos: ' || iara.num_br(t.atrasos) || ' viagens com algum atraso, de ' || iara.num_br(t.media_atraso) || ' minutos em média; '
      || case when t.graves = 0 then 'nenhuma passou de 15 minutos.' when t.graves = 1 then 'só 1 passou de 15 minutos.' else iara.num_br(t.graves) || ' passaram de 15 minutos.' end;
  end if;
  if v_perd30 > 0 and v_causa is not null then
    v_txt := v_txt || E'\n\nNos últimos 30 dias, foram ' || iara.num_br(v_perd30) || ' viagens perdidas. A causa que mais se repete: ' || iara.oraculo_min(v_causa) || ' (' || iara.num_br(v_causa_n) || ').';
    v_sug := case
      when v_causa ~* 'motorista' then 'pedir à Gerência de Transporte uma escala de motoristas reserva, que resolve a causa mais frequente'
      when v_causa ~* 'pane|mec|veículo|veiculo' then 'pedir à Gerência de Transporte veículos reserva e a revisão da frota'
      when v_causa ~* 'chuva|estrada' then 'pedir rotas alternativas para os dias de chuva'
      else 'pedir à Gerência de Transporte um plano para essa causa' end;
    if coalesce(v_veic, 0) > 0 then v_sug := v_sug || ', e cobrar a vistoria dos ' || iara.num_br(v_veic) || ' veículos com prazo vencido'; end if;
    v_txt := v_txt || E'\n\nSugestão: ' || v_sug || '.';
  elsif coalesce(v_veic, 0) > 0 then
    v_txt := v_txt || E'\n\nSugestão: cobrar a vistoria dos ' || iara.num_br(v_veic) || ' veículos com prazo vencido.';
  end if;
  return v_aviso || v_txt;
end $$;

-- 4. Frequência: estão indo à escola? --------------------------------------------------------------------------------------------------
create or replace function iara.oraculo_ler_frequencia(p_w text, p_units integer[], p_cidade boolean, p_nome text) returns text
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_hoje date := iara.hoje_local();
  v_cod text := iara.oraculo_periodo_da_pergunta(p_w);
  pd record;
  f jsonb; pr jsonb;
  v_quando text;
  v_faltas numeric; v_pres numeric; v_media numeric;
  v_comp text := '';
  v_txt text;
  v_mot text[];
  v_onde text[];
  v_alertas numeric := iara.oraculo_n('base.alertas', p_units, p_cidade);
  v_busca numeric := iara.oraculo_n('base.busca', p_units, p_cidade);
  v_sem_resp numeric := iara.oraculo_n('aus.aguardando', p_units, p_cidade);
  v_parcial boolean := false;
  v_dia date;
begin
  v_media := iara.oraculo_n('base.presenca', p_units, p_cidade);
  v_mot := iara.oraculo_top('fal.motivo', p_units, p_cidade, 3);
  if p_cidade then v_onde := iara.oraculo_onde('base.presenca', 'menor', 3); end if;
  if v_cod is null then
    v_txt := case when v_media is null then 'Ainda não há chamada suficiente para dizer a presença em ' || p_nome || '.'
                  else 'A presença nos últimos 30 dias em ' || p_nome || ' é de ' || iara.num_br(v_media, 1) || '%' || case when v_media >= 90 then ', um bom nível' when v_media >= 85 then ', pede atenção' else ', abaixo do que se espera' end || '.' end;
  else
    pd := iara.oraculo_periodo_datas(v_cod, v_hoje);
    f := iara.oraculo_fato_valor('faltas', p_units, p_cidade, pd.de, pd.ate);
    pr := iara.oraculo_fato_valor('presenca', p_units, p_cidade, pd.de, pd.ate);
    v_faltas := (f ->> 'valor')::numeric;
    v_pres := (pr ->> 'valor')::numeric;
    v_dia := coalesce((f ->> 'ultimo_dia')::date, pd.ate);
    v_parcial := pd.de = v_hoje and f ->> 'ultimo_dia' is null;
    v_quando := case when pd.de = pd.ate or f ->> 'ultimo_dia' is not null then iara.oraculo_quando(v_dia, v_hoje) else 'de ' || to_char(pd.de, 'DD/MM') || ' a ' || to_char(pd.ate, 'DD/MM') end;
    if v_pres is not null and v_media is not null then
      v_comp := case when abs(v_pres - v_media) <= 1 then ', em linha com a média de 30 dias (' || iara.num_br(v_media, 1) || '%)'
                     when v_pres > v_media then ', acima da média de 30 dias (' || iara.num_br(v_media, 1) || '%)'
                     else ', abaixo da média de 30 dias (' || iara.num_br(v_media, 1) || '%)' end;
    end if;
    v_txt := case when f ->> 'ultimo_dia' is not null then iara.oraculo_cap(iara.oraculo_quando(pd.ate, v_hoje)) || ', a chamada ainda não fechou. O último dia fechado:' || E'\n\n' else '' end
      || iara.oraculo_cap(v_quando) || ', ' || case when (f ->> 'sigilo')::boolean then 'menos de 3 faltas' else iara.num_br(coalesce(v_faltas, 0)) || ' faltas' end || ' registradas em ' || p_nome
      || coalesce(': a presença foi de ' || iara.num_br(v_pres, 1) || '%' || v_comp, '') || '.'
      || case when v_parcial then ' É um número parcial: a chamada de hoje ainda está sendo lançada.' else '' end;
  end if;
  if coalesce(cardinality(v_mot), 0) > 0 then
    if p_w ~ ' (por que|porque|motivo|motivos|causa|causas) ' and v_cod is null then
      v_txt := 'Os principais motivos das faltas em ' || p_nome || ': ' || iara.oraculo_e(v_mot) || '.' || E'\n\n' || v_txt;
    else
      v_txt := v_txt || E'\n\nPor que faltam: ' || iara.oraculo_e(v_mot) || '.';
    end if;
  end if;
  if coalesce(cardinality(v_onde), 0) > 0 then v_txt := v_txt || E'\nOnde a presença é mais baixa: ' || iara.oraculo_e(v_onde) || '.'; end if;
  if coalesce(v_alertas, 0) > 0 or coalesce(v_busca, 0) > 0 then
    v_txt := v_txt || E'\nEm acompanhamento: ' || iara.oraculo_e(array_remove(array[
      case when coalesce(v_alertas, 0) > 0 then iara.num_br(v_alertas) || ' alunos em alerta de frequência' end,
      case when coalesce(v_busca, 0) > 0 then iara.num_br(v_busca) || ' casos de busca ativa' end], null)) || '.';
  end if;
  if coalesce(v_sem_resp, 0) > 0 then
    v_txt := v_txt || E'\n\nSugestão: ' || iara.num_br(v_sem_resp) || ' ausências ainda não têm explicação da família. Cobrar das escolas o contato com esses responsáveis é o que mais esclarece o quadro.';
  end if;
  return v_txt;
end $$;

-- 5. Fila e vagas: onde está o gargalo --------------------------------------------------------------------------------------------------
create or replace function iara.oraculo_ler_fila(p_w text, p_units integer[], p_cidade boolean, p_nome text) returns text
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_fila numeric := iara.oraculo_n('base.fila', p_units, p_cidade);
  v_creche numeric := iara.oraculo_n('base.fila_creche', p_units, p_cidade);
  v_vagas numeric := iara.oraculo_n('base.vagas', p_units, p_cidade);
  v_sem numeric := iara.oraculo_n('oferta.sem_atendimento', p_units, p_cidade);
  v_abertas numeric := iara.oraculo_n('oferta.abertas', p_units, p_cidade);
  vp record := iara.oraculo_vagas_paradas(p_units);
  v_180 numeric;
  v_ocup numeric := iara.oraculo_n('rede.ocupacao', p_units, p_cidade);
  v_tempo jsonb;
  v_onde text[];
  v_txt text;
begin
  begin
    v_tempo := iara.oraculo_detalhe_lista('fila.tempo', p_units, p_cidade, 8);
    select (i ->> 'valor')::numeric into v_180 from jsonb_array_elements(v_tempo -> 'itens') i where i ->> 'nome' ilike 'mais de 180%';
  exception when others then v_180 := null;
  end;
  if p_cidade then v_onde := iara.oraculo_onde(case when p_w ~ ' (creche|creches|bercario) ' then 'base.fila_creche' else 'base.fila' end, 'maior', 3); end if;
  if coalesce(v_fila, 0) = 0 then
    return 'Não há criança na fila de espera em ' || p_nome || '.' || case when coalesce(v_vagas, 0) > 0 then ' Há ' || iara.num_br(v_vagas) || ' vagas que podem ser oferecidas.' else '' end;
  end if;
  v_txt := case when p_w ~ ' (creche|creches|bercario|bercarios) ' and coalesce(v_creche, 0) > 0
      then iara.num_br(v_creche) || ' crianças esperam vaga na creche em ' || p_nome || ', de ' || iara.num_br(v_fila) || ' na fila de espera (' || iara.oraculo_pct(v_creche, v_fila) || ').'
      else iara.num_br(v_fila) || ' crianças esperam vaga em ' || p_nome || case when v_creche > 0 then ', e ' || iara.num_br(v_creche) || ' delas (' || iara.oraculo_pct(v_creche, v_fila) || ') são da creche' else '' end || '.' end
    || case when coalesce(v_180, 0) >= 3 then ' ' || iara.num_br(v_180) || ' esperam há mais de 6 meses.' else '' end;
  if vp.vagas > 0 then
    v_txt := v_txt || E'\n\nO ponto de decisão: há ' || iara.num_br(vp.vagas) || ' vagas livres em ' || iara.num_br(vp.filas) || ' filas com criança esperando, na mesma unidade e na mesma faixa. O problema ali não é falta de vaga: é a oferta chegar à família.';
  elsif coalesce(v_vagas, 0) > 0 then
    v_txt := v_txt || E'\n\nHá ' || iara.num_br(v_vagas) || ' vagas que podem ser oferecidas, mas não nas filas com criança esperando: é um problema de onde está a vaga.';
  else
    v_txt := v_txt || E'\n\nNão há vaga para oferecer neste recorte: a saída é abrir vaga ou oferecer unidade próxima.';
  end if;
  if coalesce(cardinality(v_onde), 0) > 0 then v_txt := v_txt || E'\nOnde pesa mais: ' || iara.oraculo_e(v_onde) || '.'; end if;
  if coalesce(v_sem, 0) > 0 then v_txt := v_txt || E'\nSem nenhum atendimento hoje: ' || iara.num_br(v_sem) || ' crianças.'; end if;
  if coalesce(v_abertas, 0) > 0 then v_txt := v_txt || E'\nOfertas aguardando resposta das famílias: ' || iara.num_br(v_abertas) || '.'; end if;
  if v_ocup is not null then v_txt := v_txt || E'\nOcupação das turmas: ' || iara.num_br(v_ocup, 1) || '%.'; end if;
  if vp.vagas > 0 then
    v_txt := v_txt || E'\n\nSugestão: pedir à Central de Vagas que ofereça já as vagas paradas ao primeiro de cada fila. É a forma mais rápida de reduzir a espera, sem custo de obra.';
  end if;
  return v_txt;
end $$;

-- 6. Proteção: Conselho Tutelar e rede ---------------------------------------------------------------------------------------------------
create or replace function iara.oraculo_ler_protecao(p_w text, p_units integer[], p_cidade boolean, p_nome text) returns text
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_ag numeric := iara.oraculo_n('prot.ct_aguardando', p_units, p_cidade);
  v_sr numeric := iara.oraculo_n('prot.ct_sem_retorno', p_units, p_cidade);
  v_rede numeric := iara.oraculo_n('prot.rede_apoio', p_units, p_cidade);
  v_mot text[] := iara.oraculo_top('enc.motivo', p_units, p_cidade, 3);
  v_esp text[] := iara.oraculo_top('enc.espera', p_units, p_cidade, 2);
  v_txt text;
begin
  if coalesce(v_ag, 0) = 0 and coalesce(v_sr, 0) = 0 then
    return 'Em ' || p_nome || ', não há encaminhamento ao Conselho Tutelar parado: nada aguarda aprovação nem retorno.';
  end if;
  v_txt := 'Em ' || p_nome || ', ' || case when coalesce(v_ag, 0) > 0 then iara.num_br(v_ag) || ' encaminhamentos ao Conselho Tutelar aguardam aprovação' else 'nenhum encaminhamento ao Conselho Tutelar aguarda aprovação' end
    || case when coalesce(v_sr, 0) > 0 then ', e ' || iara.num_br(v_sr) || ' já enviados ainda não tiveram retorno' else '' end || '.';
  if coalesce(cardinality(v_mot), 0) > 0 then
    if p_w ~ ' (por que|porque|motivo|motivos|causa|causas) ' then
      v_txt := 'Os principais motivos dos encaminhamentos ao Conselho Tutelar: ' || iara.oraculo_e(v_mot) || '.' || E'\n\n' || v_txt;
    else
      v_txt := v_txt || E'\n\nMotivo principal: ' || iara.oraculo_e(v_mot) || '.';
    end if;
  end if;
  if coalesce(cardinality(v_esp), 0) > 0 then v_txt := v_txt || E'\nTempo de espera da aprovação: ' || iara.oraculo_e(v_esp) || '.'; end if;
  if coalesce(v_rede, 0) > 0 then v_txt := v_txt || E'\nEncaminhamentos à rede de apoio: ' || iara.num_br(v_rede) || '.'; end if;
  v_txt := v_txt || E'\n\nSugestão: ' || case when coalesce(v_ag, 0) > 0 then 'cobrar das direções a aprovação dos encaminhamentos parados, porque comunicação de proteção não pode esperar' else 'pedir à Secretaria o contato com o Conselho Tutelar sobre os retornos pendentes' end || '.';
  return v_txt;
end $$;

-- 7. Ocorrências ------------------------------------------------------------------------------------------------------------------------
create or replace function iara.oraculo_ler_ocorrencias(p_w text, p_units integer[], p_cidade boolean, p_nome text) returns text
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_hoje date := iara.hoje_local();
  v_n numeric := iara.oraculo_n('base.ocorrencias', p_units, p_cidade);
  v_tipo text[] := iara.oraculo_top('oc.tipo', p_units, p_cidade, 3);
  v_grav text[] := iara.oraculo_top('oc.gravidade', p_units, p_cidade, 3);
  v_30 numeric := ((iara.oraculo_fato_valor('ocorrencias', p_units, p_cidade, v_hoje - 29, v_hoje)) ->> 'valor')::numeric;
  v_ant numeric := ((iara.oraculo_fato_valor('ocorrencias', p_units, p_cidade, v_hoje - 59, v_hoje - 30)) ->> 'valor')::numeric;
  v_onde text[];
  v_comp text := '';
  v_txt text;
  v_chave_tipo text;
  v_n_tipo numeric;
begin
  if p_cidade then v_onde := iara.oraculo_onde('base.ocorrencias', 'maior', 3, 'unidade'); end if;
  if coalesce(v_n, 0) = 0 then return 'Em ' || p_nome || ', nenhuma ocorrência nos últimos 90 dias.'; end if;
  if coalesce(v_ant, 0) >= 5 and v_30 is not null then
    v_comp := case when v_30 < v_ant * 0.3 then ' Nos últimos 30 dias há só ' || iara.num_br(v_30) || ' registros, contra ' || iara.num_br(v_ant) || ' nos 30 anteriores: vale conferir se as escolas estão lançando.'
                   when abs(v_30 - v_ant) / v_ant <= 0.1 then ' Nos últimos 30 dias o ritmo ficou estável (' || iara.num_br(v_30) || ' contra ' || iara.num_br(v_ant) || ' nos 30 anteriores).'
                   when v_30 > v_ant then ' Nos últimos 30 dias, subiu ' || iara.oraculo_pct(v_30 - v_ant, v_ant) || ' (' || iara.num_br(v_30) || ' contra ' || iara.num_br(v_ant) || ' nos 30 anteriores).'
                   else ' Nos últimos 30 dias, caiu ' || iara.oraculo_pct(v_ant - v_30, v_ant) || ' (' || iara.num_br(v_30) || ' contra ' || iara.num_br(v_ant) || ' nos 30 anteriores).' end;
  end if;
  v_chave_tipo := case when p_w ~ ' bullying ' then 'ocor.bullying' when p_w ~ ' (acidente|acidentes) ' then 'ocor.acidente' when p_w ~ ' (briga|brigas|conflito|conflitos) ' then 'ocor.conflito' end;
  v_n_tipo := case when v_chave_tipo is not null then iara.oraculo_n(v_chave_tipo, p_units, p_cidade) end;
  v_txt := case when v_n_tipo is not null
      then 'Em ' || p_nome || ', ' || iara.num_br(v_n_tipo) || ' ' || case v_chave_tipo when 'ocor.bullying' then 'casos de bullying' when 'ocor.acidente' then 'acidentes' else 'conflitos' end
           || ' nos últimos 90 dias, de ' || iara.num_br(v_n) || ' ocorrências (' || iara.oraculo_pct(v_n_tipo, v_n) || ').'
      else 'Em ' || p_nome || ', ' || iara.num_br(v_n) || ' ocorrências nos últimos 90 dias.' end || v_comp;
  if coalesce(cardinality(v_tipo), 0) > 0 then v_txt := v_txt || E'\n\nO que mais acontece: ' || iara.oraculo_e(v_tipo) || '.'; end if;
  if coalesce(cardinality(v_grav), 0) > 0 then v_txt := v_txt || E'\nGravidade: ' || iara.oraculo_e(v_grav) || '.'; end if;
  if coalesce(cardinality(v_onde), 0) > 0 then v_txt := v_txt || E'\nOnde há mais: ' || iara.oraculo_e(v_onde) || '.'; end if;
  if coalesce(cardinality(v_tipo), 0) > 0 then
    v_txt := v_txt || E'\n\nSugestão: pedir à equipe pedagógica um plano para ' || regexp_replace(v_tipo[1], ' \([^)]*\)$', '') || case when coalesce(cardinality(v_onde), 0) > 0 then ', começando pelas unidades com mais casos' else '' end || '.';
  end if;
  return v_txt;
end $$;

-- 8. Manutenção -------------------------------------------------------------------------------------------------------------------------
create or replace function iara.oraculo_ler_manutencao(p_w text, p_units integer[], p_cidade boolean, p_nome text) returns text
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_ab numeric := iara.oraculo_n('man.abertos', p_units, p_cidade);
  v_ven numeric := iara.oraculo_n('man.vencidos', p_units, p_cidade);
  v_seg numeric := iara.oraculo_n('man.seguranca', p_units, p_cidade);
  v_urg numeric := iara.oraculo_n('man.urgentes', p_units, p_cidade);
  v_custo numeric := iara.oraculo_n('man.custo', p_units, p_cidade);
  v_cat text[] := iara.oraculo_top('man.categoria', p_units, p_cidade, 3);
  v_custo_cat text[];
  v_onde text[];
  v_txt text;
begin
  if coalesce(v_ab, 0) = 0 then return 'Em ' || p_nome || ', nenhum chamado de manutenção em aberto.'; end if;
  v_txt := 'Em ' || p_nome || ', ' || iara.num_br(v_ab) || ' chamados de manutenção em aberto'
    || case when coalesce(v_ven, 0) > 0 then ', ' || iara.num_br(v_ven) || ' com o prazo vencido (' || iara.oraculo_pct(v_ven, v_ab) || ')' else ', nenhum com o prazo vencido' end || '. '
    || case when coalesce(v_seg, 0) > 0 then 'Atenção: ' || iara.num_br(v_seg) || ' afetam a segurança das crianças.'
            when coalesce(v_urg, 0) > 0 then iara.num_br(v_urg) || ' são urgentes, mas nenhum afeta a segurança.'
            else 'Nenhum é urgente nem afeta a segurança.' end;
  if coalesce(cardinality(v_cat), 0) > 0 then
    if p_w ~ ' (comum|comuns|problema|problemas|causa|causas|motivo|motivos|quebra) ' then
      v_txt := 'O que mais quebra nas unidades: ' || iara.oraculo_e(v_cat) || '.' || E'\n\n' || v_txt;
    else
      v_txt := v_txt || E'\n\nO que mais quebra: ' || iara.oraculo_e(v_cat) || '.';
    end if;
  end if;
  if coalesce(v_custo, 0) > 0 then v_txt := v_txt || E'\nCusto de manutenção no ano: R$ ' || iara.num_br(round(v_custo)) || '.'; end if;
  v_txt := v_txt || E'\n\nSugestão: ' || case when coalesce(v_seg, 0) > 0 then 'resolver primeiro o que afeta a segurança'
      when coalesce(v_ven, 0) > 0 then 'cobrar a equipe de manutenção pelos chamados com prazo vencido'
      else 'manter o acompanhamento: os prazos estão em dia' end || '.';
  return v_txt;
end $$;

-- 9. Aprendizagem -----------------------------------------------------------------------------------------------------------------------
create or replace function iara.oraculo_ler_aprendizagem(p_w text, p_units integer[], p_cidade boolean, p_nome text) returns text
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  x jsonb;
  v_alf numeric;
  v_total numeric;
  v_evo text[];
  v_media numeric := iara.oraculo_n('des.media', p_units, p_cidade);
  v_abaixo numeric := iara.oraculo_n('des.abaixo6', p_units, p_cidade);
  v_plan numeric := iara.oraculo_n('des.intervencao', p_units, p_cidade);
  v_txt text := '';
begin
  begin
    x := iara.oraculo_detalhe_lista('alf.nivel', p_units, p_cidade, 8);
    v_total := (x ->> 'total')::numeric;
    select (i ->> 'valor')::numeric into v_alf from jsonb_array_elements(x -> 'itens') i where i ->> 'nome' = 'Alfabético';
    select array_agg(iara.num_br((i ->> 'valor')::numeric) || '% ' || case when i ->> 'nome' ilike 'sondagem%' then 'na ' else 'no ' end || iara.oraculo_min(i ->> 'nome') order by o) into v_evo
    from jsonb_array_elements((iara.oraculo_detalhe_lista('alf.evolucao', p_units, p_cidade, 8)) -> 'itens') with ordinality t(i, o);
  exception when others then v_total := null;
  end;
  if coalesce(v_total, 0) > 0 and v_alf is not null then
    v_txt := 'Na última sondagem em ' || p_nome || ', ' || iara.num_br(v_alf) || ' de ' || iara.num_br(v_total) || ' crianças avaliadas (' || iara.oraculo_pct(v_alf, v_total) || ') já estão no nível alfabético, o que mostra quem já lê e escreve com autonomia.';
    if coalesce(cardinality(v_evo), 0) > 1 then v_txt := v_txt || E'\nA evolução neste ano: ' || iara.oraculo_e(v_evo) || '.'; end if;
  end if;
  if v_media is not null then
    if p_w ~ ' (nota|notas|media|desempenho|reprov\w*|aprovad\w*) ' then
      v_txt := 'Em ' || p_nome || ', a média das notas no ano é ' || iara.num_br(v_media, 1) || coalesce(', e ' || iara.num_br(v_abaixo, 1) || '% das notas ficaram abaixo de 6', '') || '.'
        || case when v_txt <> '' then E'\n\n' || v_txt else '' end;
    else
      v_txt := v_txt || case when v_txt = '' then 'Em ' || p_nome || ', a' else E'\n\nNas notas, a' end || ' média do ano é ' || iara.num_br(v_media, 1)
        || coalesce(', e ' || iara.num_br(v_abaixo, 1) || '% das notas ficaram abaixo de 6', '') || '.';
    end if;
  end if;
  if coalesce(v_plan, 0) > 0 then v_txt := v_txt || E'\nHá ' || iara.num_br(v_plan) || ' planos de intervenção ativos para quem precisa de reforço.'; end if;
  if v_txt = '' then return 'Não tenho esta informação neste momento: as sondagens e as notas ainda não foram lançadas neste recorte. Quem pode confirmar é a equipe pedagógica da Secretaria.'; end if;
  if coalesce(v_abaixo, 0) > 20 then
    v_txt := v_txt || E'\n\nSugestão: pedir à equipe pedagógica o resultado dos planos de intervenção, para ver se as notas abaixo de 6 estão caindo.';
  end if;
  return v_txt;
end $$;

-- 10. Bolsa Família e profissionais ------------------------------------------------------------------------------------------------------
create or replace function iara.oraculo_ler_bolsa(p_unit integer, p_area integer, p_nome text) returns text
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  x jsonb := iara.oraculo_numeros('bolsa_familia', p_unit, p_area);
  v_tot numeric; v_dei numeric; v_ass numeric; v_dois numeric;
  v_txt text;
begin
  select max((i ->> 'valor')::numeric) filter (where i ->> 'rotulo' ilike 'alunos em famílias%'),
         max((i ->> 'valor')::numeric) filter (where i ->> 'rotulo' ilike 'deixaram de receber%'),
         max((i ->> 'valor')::numeric) filter (where i ->> 'rotulo' ilike 'têm recebido%'),
         max((i ->> 'valor')::numeric) filter (where i ->> 'rotulo' ilike 'abaixo do mínimo em dois%')
    into v_tot, v_dei, v_ass, v_dois from jsonb_array_elements(x -> 'numeros') i;
  if coalesce(v_tot, 0) = 0 then return 'Não tenho esta informação neste momento: não há alunos do Bolsa Família identificados em ' || p_nome || '.'; end if;
  v_txt := 'Em ' || p_nome || ', ' || iara.num_br(v_tot) || ' alunos são de famílias do Bolsa Família.'
    || coalesce(' Neste ano, ' || iara.num_br(v_dei) || ' (' || iara.oraculo_pct(v_dei, v_tot) || ') não alcançaram a frequência mínima em algum período, o que põe o benefício da família em risco.', '')
    || coalesce(' Outros ' || iara.num_br(v_ass) || ' seguem sempre dentro do mínimo.', '');
  if coalesce(v_dois, 0) > 0 then
    v_txt := v_txt || E'\n\nOs casos mais sérios: ' || iara.num_br(v_dois) || ' alunos abaixo do mínimo em dois ou mais períodos.'
      || E'\n\nSugestão: acionar a busca ativa e o CRAS para esses ' || iara.num_br(v_dois) || ' alunos, antes do próximo fechamento do Sistema Presença.';
  end if;
  return v_txt;
end $$;

drop function if exists iara.oraculo_ler_profissionais(integer, integer, integer[], boolean, text);
create or replace function iara.oraculo_ler_profissionais(p_w text, p_unit integer, p_area integer, p_units integer[], p_cidade boolean, p_nome text) returns text
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  x jsonb := iara.oraculo_numeros('profissionais', p_unit, p_area);
  v_tot numeric; v_prof numeric; v_edu numeric; v_pos numeric;
  v_marc numeric := iara.oraculo_n('ponto.marcaram', p_units, p_cidade);
  v_lic numeric := iara.oraculo_n('ponto.licenca', p_units, p_cidade);
  v_jus numeric := iara.oraculo_n('ponto.justificativas', p_units, p_cidade);
  v_txt text;
begin
  select max((i ->> 'valor')::numeric) filter (where i ->> 'rotulo' = 'Profissionais'),
         max((i ->> 'valor')::numeric) filter (where i ->> 'rotulo' = 'Professores'),
         max((i ->> 'valor')::numeric) filter (where i ->> 'rotulo' = 'Educadores infantis'),
         max((i ->> 'valor')::numeric) filter (where i ->> 'rotulo' ilike 'com pós%')
    into v_tot, v_prof, v_edu, v_pos from jsonb_array_elements(x -> 'numeros') i;
  if coalesce(v_tot, 0) = 0 then return 'Não tenho esta informação neste momento: não há profissionais cadastrados em ' || p_nome || '.'; end if;
  v_txt := case when p_w ~ ' (professor|professores|professora|professoras|docente|docentes) ' and v_prof is not null
      then 'Em ' || p_nome || ', são ' || iara.num_br(v_prof) || ' professores, num quadro de ' || iara.num_br(v_tot) || ' profissionais' || coalesce(', com ' || iara.num_br(v_edu) || ' educadores infantis', '') || '.'
      else 'Em ' || p_nome || ', são ' || iara.num_br(v_tot) || ' profissionais' || coalesce(': ' || iara.num_br(v_prof) || ' professores', '') || coalesce(' e ' || iara.num_br(v_edu) || ' educadores infantis', '') || '.' end
    || coalesce(' ' || iara.num_br(v_pos) || '% têm pós-graduação.', '');
  if v_marc is not null then
    v_txt := v_txt || E'\n\nHoje, ' || iara.num_br(v_marc) || ' marcaram o ponto até agora (' || iara.oraculo_pct(v_marc, v_tot) || ' do quadro)' || coalesce('; ' || iara.num_br(v_lic) || ' estão em licença ou afastados', '') || '.';
  end if;
  if coalesce(v_jus, 0) > 0 then
    v_txt := v_txt || E'\n\nSugestão: ' || iara.num_br(v_jus) || ' justificativas de ponto aguardam a direção. Cobrar a análise evita falta sem registro na folha.';
  end if;
  return v_txt;
end $$;

-- 11. O que precisa de decisão: a rede em poucas linhas ----------------------------------------------------------------------------------
create or replace function iara.oraculo_ler_briefing(p_units integer[], p_cidade boolean, p_nome text) returns text
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_hoje date := iara.hoje_local();
  v_alunos numeric := iara.oraculo_n('base.matriculas', p_units, p_cidade);
  v_pres numeric := iara.oraculo_n('base.presenca', p_units, p_cidade);
  v_fila numeric := iara.oraculo_n('base.fila', p_units, p_cidade);
  v_ct numeric := iara.oraculo_n('prot.ct_aguardando', p_units, p_cidade);
  v_prot numeric := iara.oraculo_n('atend.vencidos', p_units, p_cidade);
  v_urg numeric := iara.oraculo_n('atend.urgentes', p_units, p_cidade);
  v_venc numeric := iara.oraculo_n('alm.vencidos', p_units, p_cidade);
  v_seg numeric := iara.oraculo_n('man.seguranca', p_units, p_cidade);
  v_man numeric := iara.oraculo_n('man.vencidos', p_units, p_cidade);
  v_busca numeric := iara.oraculo_n('base.busca', p_units, p_cidade);
  v_vist numeric := iara.oraculo_n('frota.vistoria', p_units, p_cidade);
  vp record := iara.oraculo_vagas_paradas(p_units);
  v_ref numeric;
  v_ref_d date;
  v_perd numeric;
  v_perd_d date;
  v_itens text[] := '{}';
  v_bem text[] := '{}';
  v_txt text;
  i integer;
begin
  select s.data, sum(s.quantidade) into v_ref_d, v_ref from iara.refeicoes_servidas s where s.unit_id = any (p_units) and s.data < v_hoje group by 1 order by 1 desc limit 1;
  select max(v.data) into v_perd_d from iara.transporte_viagens v join iara.transporte_rotas r on r.id = v.rota_id where r.unit_id = any (p_units) and v.data <= v_hoje;
  select count(*) filter (where v.situacao = 'NAO_REALIZADA') into v_perd from iara.transporte_viagens v join iara.transporte_rotas r on r.id = v.rota_id where r.unit_id = any (p_units) and v.data = v_perd_d;

  -- em ordem de gravidade: proteção da criança, segurança, atendimento à família, acesso à escola, compromissos, estoque
  if coalesce(v_seg, 0) > 0 then v_itens := v_itens || (iara.num_br(v_seg) || ' chamados de manutenção afetam a segurança das crianças. Precisam de solução imediata.'); end if;
  if coalesce(v_ct, 0) > 0 then v_itens := v_itens || (iara.num_br(v_ct) || ' encaminhamentos ao Conselho Tutelar aguardam aprovação. É comunicação de proteção: cobrar as direções.'); end if;
  if vp.vagas > 0 and coalesce(v_fila, 0) > 0 then v_itens := v_itens || (iara.num_br(v_fila) || ' crianças na fila, e ' || iara.num_br(vp.vagas) || ' vagas livres em filas com criança esperando. Pedir à Central de Vagas que ofereça já.'); end if;
  if coalesce(v_prot, 0) > 0 then v_itens := v_itens || (iara.num_br(v_prot) || ' protocolos de famílias com o prazo vencido' || case when coalesce(v_urg, 0) > 0 then ', ' || iara.num_br(v_urg) || ' urgentes ou de alta prioridade' else '' end || case when v_prot >= 20 then '. Pedir um mutirão de resposta.' else '. Cobrar a resposta.' end); end if;
  if coalesce(v_busca, 0) > 0 then v_itens := v_itens || (iara.num_br(v_busca) || ' casos de busca ativa abertos: crianças em risco de abandonar a escola. Acompanhar os retornos.'); end if;
  if coalesce(v_venc, 0) > 0 then v_itens := v_itens || (iara.num_br(v_venc) || ' lotes do almoxarifado vencidos com saldo. Dar baixa e apurar a perda.'); end if;
  if coalesce(v_man, 0) > 0 then v_itens := v_itens || (iara.num_br(v_man) || ' chamados de manutenção com prazo vencido. Cobrar a equipe.'); end if;
  if coalesce(v_vist, 0) > 0 then v_itens := v_itens || (iara.num_br(v_vist) || ' veículos do transporte com a vistoria vencida. Regularizar.'); end if;

  if v_pres >= 90 then v_bem := v_bem || ('presença de ' || iara.num_br(v_pres, 1) || '%'); end if;
  if coalesce(v_ref, 0) > 0 then v_bem := v_bem || (iara.num_br(v_ref) || ' refeições servidas ' || iara.oraculo_quando(v_ref_d, v_hoje)); end if;
  if v_perd_d is not null and coalesce(v_perd, 0) <= 5 then v_bem := v_bem || (case when coalesce(v_perd, 0) = 0 then 'nenhuma viagem de transporte perdida' else 'só ' || iara.num_br(v_perd) || ' viagens de transporte perdidas' end); end if;
  if coalesce(v_seg, 0) = 0 then v_bem := v_bem || 'nenhum chamado de manutenção afetando a segurança'::text; end if;

  v_txt := case when p_cidade then 'A rede de ' || p_nome else p_nome end || ': ' || coalesce(iara.num_br(v_alunos) || ' alunos', 'sem matrículas neste recorte') || '.';
  if cardinality(v_itens) = 0 then
    v_txt := v_txt || E'\n\nNada pede a sua decisão neste momento.';
  else
    v_txt := v_txt || E'\n\n' || case when cardinality(v_itens) = 1 then 'Um ponto pede a sua decisão:' else 'O que pede a sua decisão, do mais grave ao menos grave:' end;
    for i in 1 .. least(cardinality(v_itens), 4) loop
      v_txt := v_txt || E'\n' || i || '. ' || v_itens[i];
    end loop;
    if cardinality(v_itens) > 4 then
      v_txt := v_txt || E'\n\nTambém em acompanhamento: ' || iara.oraculo_e(array(select lower(left(x, 1)) || split_part(substr(x, 2), '. ', 1) from unnest(v_itens[5:cardinality(v_itens)]) x)) || '.';
    end if;
  end if;
  if cardinality(v_bem) > 0 then v_txt := v_txt || E'\n\nO que vai bem: ' || iara.oraculo_e(v_bem) || '.'; end if;
  return v_txt;
end $$;

-- 12. Número num período, com sentido ---------------------------------------------------------------------------------------------------
create or replace function iara.oraculo_ler_fatos(p_chaves text[], p_cod text, p_units integer[], p_cidade boolean, p_nome text) returns text
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_hoje date := iara.hoje_local();
  pd record := iara.oraculo_periodo_datas(p_cod, v_hoje);
  c text;
  x jsonb;
  v numeric;
  v_base numeric;
  v_dias integer := pd.ate - pd.de + 1;
  v_media numeric;
  v_comp text;
  v_ult date;
  v_linhas text[] := '{}';
  v_rot text;
begin
  foreach c in array p_chaves loop
    x := iara.oraculo_fato_valor(c, p_units, p_cidade, pd.de, pd.ate);
    v_rot := iara.oraculo_min(x ->> 'rotulo');
    if (x ->> 'sigilo')::boolean then
      v_linhas := v_linhas || (v_rot || ': menos de 3');
      continue;
    end if;
    v := (x ->> 'valor')::numeric;
    v_ult := (x ->> 'ultimo_dia')::date;
    if v is null then
      v_linhas := v_linhas || (v_rot || ': ainda sem registro');
      continue;
    end if;
    -- a média dos 30 dias antes do período, na mesma duração
    v_base := ((iara.oraculo_fato_valor(c, p_units, p_cidade, pd.de - 30, pd.de - 1)) ->> 'valor')::numeric;
    v_media := case when v_base is not null and v_base > 0 then v_base / 30.0 * v_dias end;
    v_comp := case when coalesce(x ->> 'casas', '0') <> '0' or v_media is null or v_ult is not null then ''
                   when abs(v - v_media) <= greatest(v_media * 0.15, 1) then ', dentro do normal (em média, ' || iara.num_br(round(v_media, case when v_media < 10 then 1 else 0 end), case when v_media < 10 then 1 else 0 end) || ')'
                   when v > v_media then ', acima do normal (em média, ' || iara.num_br(round(v_media, case when v_media < 10 then 1 else 0 end), case when v_media < 10 then 1 else 0 end) || ')'
                   else ', abaixo do normal (em média, ' || iara.num_br(round(v_media, case when v_media < 10 then 1 else 0 end), case when v_media < 10 then 1 else 0 end) || ')' end;
    v_linhas := v_linhas || (v_rot || ': ' || iara.num_br(v, coalesce((x ->> 'casas')::int, 0)) || coalesce(x ->> 'sufixo', '') || v_comp
      || case when v_ult is not null then ' (último dia fechado: ' || iara.oraculo_quando(v_ult, v_hoje) || ')' else '' end);
  end loop;
  return pd.rotulo || ', em ' || p_nome || case when cardinality(v_linhas) = 1 then ': ' || v_linhas[1] || '.'
                                                 else E':\n• ' || array_to_string(v_linhas, E'\n• ') end;
end $$;

-- 13. Qualquer outro assunto: em vez de todas as listas, o principal de cada uma --------------------------------------------------------------
create or replace function iara.oraculo_ler_assunto(p_assunto text, p_unit integer, p_area integer) returns text
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  x jsonb := iara.oraculo_aprofundar(p_assunto, p_unit, p_area, 3);
  v_nums text[];
  v_txt text;
  d jsonb;
  v_top text[];
  n integer := 0;
begin
  v_nums := array(select iara.oraculo_numero_texto(i) from jsonb_array_elements(coalesce(x -> 'numeros', '[]')) with ordinality t(i, o) order by o limit 3);
  v_txt := (x ->> 'rotulo') || ', em ' || (x ->> 'recorte')
    || case when cardinality(v_nums) > 0 then ': ' || array_to_string(v_nums, '; ') || '.' else ':' end;
  for d in select * from jsonb_array_elements(coalesce(x -> 'detalhes', '[]')) limit 2 loop
    v_top := array(select iara.oraculo_min(i ->> 'nome') || coalesce(' (' || iara.num_br(round((i ->> 'pct')::numeric)) || '%)', ' (' || iara.num_br((i ->> 'valor')::numeric, coalesce((d ->> 'casas')::int, 0)) || coalesce(d ->> 'sufixo', '') || ')')
                   from jsonb_array_elements(d -> 'itens') with ordinality t(i, o) where i ->> 'nome' !~* '^(outros?|demais)' order by o limit 2);
    if cardinality(v_top) > 0 then
      v_txt := v_txt || case when n = 0 then E'\n\n' else E'\n' end || (d ->> 'rotulo') || ': ' || iara.oraculo_e(v_top) || '.';
      n := n + 1;
    end if;
  end loop;
  if jsonb_array_length(coalesce(x -> 'onde' -> 'lista', '[]')) > 0 then
    v_txt := v_txt || E'\nOnde pesa mais: ' || iara.oraculo_e(array(select regexp_replace(i ->> 'nome', '^AP [0-9]+ · ', '') || ' (' || iara.num_br((i ->> 'valor')::numeric, coalesce((x -> 'onde' ->> 'casas')::int, 0)) || coalesce(x -> 'onde' ->> 'sufixo', '') || ')'
                                                                    from jsonb_array_elements(x -> 'onde' -> 'lista') i)) || '.';
  end if;
  if cardinality(v_nums) = 0 and n = 0 then return null; end if;
  return v_txt || E'\n\nPara ver tudo, peça: “detalhe completo de ' || lower(x ->> 'rotulo') || '”.';
end $$;

-- 14. O roteador da leitura: devolve texto e tópico, ou nada, e aí vale o roteador antigo ----------------------------------------------------
create or replace function iara.oraculo_leitura(p_pergunta text) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_w text := ' ' || iara.oraculo_palavras(p_pergunta) || ' ';
  v_rec jsonb := iara.oraculo_recorte(p_pergunta);
  v_unit integer := (v_rec ->> 'unidade')::int;
  v_area integer := (v_rec ->> 'area')::int;
  rc record := iara.oraculo_recorte_de(v_unit, v_area);
  v_cod text := iara.oraculo_periodo_da_pergunta(v_w);
  v_chaves text[];
  v_texto text;
  v_topico text;
  a iara.oraculo_assuntos;
  v_bolsa constant text := 'bolsa|beneficio|condicionalidade|sistema presenca|cadunico';
begin
  -- continua no roteador antigo: dado de pessoa, nomes, salários, comparações pedidas e o detalhe completo
  if v_w ~ ' (telefone|telefones|celular|endereco|enderecos|cpf|rg|nis|email|e mail) ' or v_w ~ ' (quem (e|sao|foi|foram)|lista de nomes|nomes d[aeo]s?|quais os nomes|me diga o nome) '
     or v_w ~ ' (se chamam?|com o nome|de nome|(alunos?|criancas?|estudantes?|professor(es|as?)?|pessoas?|profissionais|responsaveis) chamad[oa]s?) ' or v_w ~ ' (salarios?|salarial|salariais|remuneracao|folha de pagamento|orcamentos?|licitac\w+|receitas?|despesas?|fundeb|verbas?) '
     or v_w ~ ' (completo|completa|detalhado|detalhada|detalhes|tudo sobre|todos os numeros) ' then
    return null;
  end if;
  if v_w ~ ' (qual|quais|ranking) ' and v_w ~ ' (mais|menos|maior|maiores|menor|menores|pior|piores|melhor|melhores) ' and v_w ~ ' (unidades?|escolas?|cmeis?|regioes|regiao|bairros?) '
     and v_w !~ ' (comeram|comem|comer|merenda|cardapio) ' then
    return null;
  end if;

  -- merenda
  if v_w ~ ' (comeram|comeu|comem|comer|comendo|comida|almocaram|almocou|almoco|almocos|lancharam|lanche|lanches|jantar|jantaram|desjejum|merenda|merendas|refeicao|refeicoes|cardapio|cardapios|alimentacao|alimentados|servido|servida|servidos|servidas|serviram|servem) '
     and v_w !~ ' (restric\w*|alerg\w*|imc|peso|obesidade|nutricional|nutricionista|adaptad\w*) ' then
    v_topico := 'merenda';
    v_texto := iara.oraculo_ler_merenda(v_w, rc.unidades, rc.cidade, rc.nome);
  elsif v_w ~ v_bolsa then
    v_topico := 'bolsa_familia';
    v_texto := iara.oraculo_ler_bolsa(v_unit, v_area, rc.nome);
  elsif v_w ~ ' (transporte|transportes|rota|rotas|onibus|van|vans|viagem|viagens|motorista|motoristas) ' then
    v_topico := 'transporte';
    v_texto := iara.oraculo_ler_transporte(v_w, rc.unidades, rc.cidade, rc.nome);
  elsif v_w ~ ' (faltaram|faltou|faltas|faltando|frequencia|presenca|presentes|ausencia|ausencias|ausentes|compareceram|indo a escola|indo para a escola|indo as aulas|vao a escola|evasao|abandono) ' then
    v_topico := 'frequencia';
    v_texto := iara.oraculo_ler_frequencia(v_w, rc.unidades, rc.cidade, rc.nome);
  elsif v_w ~ ' (fila|filas|espera|esperam|esperando|creche|creches|vaga|vagas) ' and v_w !~ ' (oferta|ofertas|vencem|vencendo|recusad\w*|recusaram|recusa|bloquead\w*) ' then
    v_topico := 'fila';
    v_texto := iara.oraculo_ler_fila(v_w, rc.unidades, rc.cidade, rc.nome);
  elsif v_w ~ ' (conselho tutelar|conselhos tutelares|encaminhamento|encaminhamentos|protecao|violencia domestica|defensoria|ministerio publico|maus tratos) ' and v_cod is null then
    v_topico := 'protecao';
    v_texto := iara.oraculo_ler_protecao(v_w, rc.unidades, rc.cidade, rc.nome);
  elsif v_w ~ ' (ocorrencia|ocorrencias|bullying|briga|brigas|conflito|conflitos|violencia|acidente|acidentes) ' and v_cod is null then
    v_topico := 'ocorrencias';
    v_texto := iara.oraculo_ler_ocorrencias(v_w, rc.unidades, rc.cidade, rc.nome);
  elsif v_w ~ ' (manutencao|chamado|chamados|reforma|reformas|obra|obras|telhado|goteira|goteiras|predio|predios) ' and v_cod is null then
    v_topico := 'manutencao';
    v_texto := iara.oraculo_ler_manutencao(v_w, rc.unidades, rc.cidade, rc.nome);
  elsif v_w ~ ' (aprendendo|aprender|aprendizagem|alfabetiz\w*|ler|lendo|leitura|escrever|escrita|sondagem|sondagens|nota|notas|desempenho|reprov\w*|aprovad\w*) ' and v_cod is null then
    v_topico := 'aprendizagem';
    v_texto := iara.oraculo_ler_aprendizagem(v_w, rc.unidades, rc.cidade, rc.nome);
  elsif v_w ~ ' (professor|professores|professora|professoras|profissional|profissionais|servidor|servidores|educador|educadores|educadoras|docente|docentes|funcionario|funcionarios) ' and v_cod is null
        and v_w !~ ' (licenca|licencas|afastad\w*|ponto|marcaram|bateram|justificativas?|cargos?|vinculos?|escolaridade|formacao) ' then
    v_topico := 'profissionais';
    v_texto := iara.oraculo_ler_profissionais(v_w, v_unit, v_area, rc.unidades, rc.cidade, rc.nome);
  end if;

  -- salário não está aqui: diz isso e traz o que há sobre o quadro
  if v_topico = 'profissionais' and v_w ~ ' (ganha|ganham|recebe|recebem) ' then
    v_texto := 'Salários e folha de pagamento não estão no IARA Educa: ficam nos sistemas de gestão da Prefeitura. O que o IARA mostra do quadro:' || E'\n\n' || v_texto;
  end if;

  -- um número num período
  if v_texto is null and v_cod is not null and v_w !~ ' (venc\w*) ' then
    v_chaves := array(select f.chave from iara.oraculo_fatos f where v_w ~ f.palavras order by f.ordem limit 3);
    if cardinality(v_chaves) > 0 then
      v_topico := 'periodo';
      v_texto := iara.oraculo_ler_fatos(v_chaves, v_cod, rc.unidades, rc.cidade, rc.nome);
    end if;
  end if;

  -- assunto do catálogo, sem pedido de um recorte específico; "quantos" de um indicador conhecido vai direto ao número
  if v_texto is null and not (v_w ~ ' (quantos|quantas) ' and exists (select 1 from iara.oraculo_indicadores i where i.palavras is not null and v_w ~ i.palavras)) then
    select * into a from iara.oraculo_assuntos s where v_w ~ s.palavras order by s.ordem limit 1;
    -- "crianças" sozinha leva às matrículas: "quantas crianças usam óculos" não pode virar o perfil dos alunos
    if a.assunto is not null and not (a.assunto = 'matriculas' and v_w !~ ' (matricul\w*|perfil|alunos por|meninos|meninas|idade|raca|cor|sexo|etapa|etapas|turno|turnos) ')
       and not exists (select 1 from iara.oraculo_detalhes d where d.assunto = a.assunto and d.pede is not null and v_w ~ d.pede) and v_w !~ ' por (regiao|regioes|bairro|bairros|escola|escolas|unidade|unidades) ' then
      v_topico := a.tema;
      v_texto := iara.oraculo_ler_assunto(a.assunto, v_unit, v_area);
    end if;
  end if;

  -- a rede: o que pede decisão
  if v_texto is null and (v_w ~ ' (como esta|como estao|como vai|como vao|como anda|como andam|panorama|resumo|balanco|visao geral|acontecendo|aconteceu|problema|problemas|prioridade|prioridades|urgente|urgentes|urgencia|critico|criticos|critica|criticas|decisao|decisoes|decidir|preocupar|preocupa|atencao|destaque|destaques|novidade|novidades) '
                          or (v_unit is not null or v_area is not null)) then
    v_topico := 'panorama';
    v_texto := iara.oraculo_ler_briefing(rc.unidades, rc.cidade, rc.nome);
  end if;

  if v_texto is null then return null; end if;
  return jsonb_build_object('topico', v_topico, 'recorte', rc.nome, 'unidade', v_unit, 'area', v_area, 'resposta', v_texto);
end $$;

-- 15. A porta de entrada: a leitura primeiro; o roteador antigo para o resto ----------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'iara' and p.proname = 'oraculo_perguntar_base') then
    alter function api.oraculo_perguntar(jsonb) rename to oraculo_perguntar_base;
    alter function api.oraculo_perguntar_base(jsonb) set schema iara;
  end if;
end $$;

create or replace function api.oraculo_perguntar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_perg text := btrim(coalesce(p ->> 'pergunta', ''));
  x jsonb;
  r jsonb;
  v_txt text;
  v_id uuid;
begin
  perform iara.require_perm('oraculo.prefeito');
  if length(v_perg) < 3 then raise exception 'Faça uma pergunta.' using errcode = '22023'; end if;
  x := iara.oraculo_leitura(v_perg);
  if x is not null then
    insert into iara.oraculo_perguntas (user_id, pergunta, canal, modo, resposta, ferramentas, is_demo)
    values (iara.current_user_id(), v_perg, coalesce(nullif(p ->> 'canal', ''), 'TEXTO'), 'REGRAS', x ->> 'resposta',
            jsonb_build_array(jsonb_build_object('leitura', x ->> 'topico', 'unidade', x -> 'unidade', 'area', x -> 'area')), iara.demo_mode());
    return x || jsonb_build_object('pergunta', v_perg, 'modo', 'REGRAS', 'fora', false, 'numeros', '[]'::jsonb);
  end if;
  r := iara.oraculo_perguntar_base(p);
  -- pergunta sem assunto conhecido: nada de despejar o resumo; diz que não tem, quem pode confirmar e o que há de mais próximo
  if coalesce((r ->> 'fora')::boolean, false) and r ->> 'topico' = 'visao_geral' then
    v_txt := 'Não tenho esta informação neste momento. Quem pode confirmar é a Secretaria Municipal de Educação.'
      || E'\n\nO que posso trazer agora é o que acontece na rede: merenda, transporte, frequência, fila e vagas, ocorrências, proteção, manutenção, aprendizagem, professores e Bolsa Família. Por exemplo: “O que pede a minha decisão hoje?”.';
    select id into v_id from iara.oraculo_perguntas where user_id is not distinct from iara.current_user_id() and pergunta = v_perg order by criado_em desc limit 1;
    update iara.oraculo_perguntas set resposta = v_txt where id = v_id;
    return r || jsonb_build_object('resposta', v_txt, 'numeros', '[]'::jsonb);
  end if;
  return r;
end $$;

-- para o Claude e o conector: a mesma leitura, como ponto de partida; o Claude pode combiná-la com as outras consultas
create or replace function api.oraculo_leitura(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_perg text := btrim(coalesce(p ->> 'pergunta', ''));
  x jsonb;
begin
  perform iara.require_perm('oraculo.prefeito');
  if length(v_perg) < 3 then raise exception 'Faça uma pergunta.' using errcode = '22023'; end if;
  x := iara.oraculo_leitura(v_perg);
  if x is null then
    return jsonb_build_object('encontrada', false, 'motivo', 'Essa pergunta precisa das outras consultas: comparar_unidades, detalhar ou numeros_do_municipio.');
  end if;
  return x || jsonb_build_object('encontrada', true);
end $$;

commit;
