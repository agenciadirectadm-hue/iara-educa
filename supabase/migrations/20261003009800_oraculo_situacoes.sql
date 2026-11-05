-- IARA Educa — 098 · Oráculo abrangente: situações pontuais e leitura das perguntas
-- Situações pontuais: o que pede atenção agora na rede (chamados que afetam a segurança, ocorrências graves, protocolos vencidos,
-- ofertas vencendo, transporte que não passou…), com a unidade e sem nome de pessoa nem o texto dos registros. Casos sensíveis
-- (violência sexual, autolesão) aparecem só somados na cidade, nunca por unidade.
-- Perguntas (sem a chave da Anthropic), nesta ordem: dado de pessoa (recusa), nome (contagem com sigilo), comparação ("qual escola
-- tem mais…"), indicador do catálogo, tema do catálogo, situações, assuntos de sempre; sem assunto, avisa e dá o resumo da rede.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

-- p_units: unidades do recorte; p_cidade: inclui o que só existe na cidade inteira. Nível: 1 alta, 2 média, 3 informação.
-- Muitas unidades têm nome de pessoa: na lista de situações, o tipo vem junto para não parecer que o caso é de alguém.
create or replace function iara.oraculo_rotulo_unidade(p_tipo text, p_nome text) returns text
language sql immutable set search_path = pg_catalog as $$
  select case when p_nome ~* '^(cmei|escola|e\.? ?m\.?) ' then p_nome
              when p_tipo = 'CMEI' then 'CMEI ' || p_nome
              else 'Escola ' || p_nome end
$$;

create or replace function iara.oraculo_situacoes_lista(p_units integer[], p_cidade boolean, p_dias integer default 7) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_hoje date := iara.hoje_local();
  v_ini date := iara.hoje_local() - greatest(coalesce(p_dias, 7), 1);
  -- último dia letivo antes de hoje
  v_ult date := (select max(d::date) from generate_series(iara.hoje_local() - 10, iara.hoje_local() - 1, interval '1 day') d where iara.dia_letivo(d::date));
begin
  return (
    with itens (nivel, area, unidade, quando, texto) as (
      -- manutenção: o que afeta a segurança ou é urgente (categoria e local, sem a descrição)
      select case when c.afeta_seguranca then 1 else 2 end, 'Manutenção', iara.oraculo_rotulo_unidade(u.unit_type, u.short_name), c.aberto_em::date,
             'Chamado ' || lower(c.categoria) || coalesce(' em ' || nullif(c.local, ''), '')
             || case when c.afeta_seguranca then ', afeta a segurança' else ', urgente' end
             || ', aberto há ' || (v_hoje - c.aberto_em::date) || ' dia(s)'
             || case when c.prazo < now() then ', prazo vencido' else '' end
      from iara.manutencao_chamados c join iara.education_units u on u.id = c.unit_id
      where c.situacao not in ('VALIDADO', 'CONCLUIDO', 'CANCELADO') and (c.afeta_seguranca or c.prioridade = 'URGENTE') and c.unit_id = any (p_units)
      union all
      -- ocorrências graves no período, por unidade; casos sensíveis ficam fora daqui
      select 1, 'Ocorrências', iara.oraculo_rotulo_unidade(u.unit_type, u.short_name), max(o.ocorrida_em)::date,
             count(*) || ' ocorrência(s) grave(s) nos últimos ' || greatest(coalesce(p_dias, 7), 1) || ' dias (' || string_agg(distinct lower(o.tipo), ', ') || ')'
      from iara.ocorrencias o join iara.education_units u on u.id = o.unit_id
      where o.gravidade = 'GRAVE' and o.ocorrida_em >= v_ini and o.unit_id = any (p_units) and not (o.violencia && array['SEXUAL', 'AUTOLESAO']::text[])
      group by u.unit_type, u.short_name
      union all
      select 1, 'Proteção', null, null, n || ' caso(s) sensível(is) nos últimos ' || greatest(coalesce(p_dias, 7), 1) || ' dias, acompanhados pela rede de proteção'
      from (select count(*) n from iara.ocorrencias o where o.ocorrida_em >= v_ini and o.violencia && array['SEXUAL', 'AUTOLESAO']::text[]) q where p_cidade and n > 0
      union all
      select 1, 'Proteção', iara.oraculo_rotulo_unidade(u.unit_type, u.short_name), null, n || ' encaminhamento(s) ao Conselho Tutelar aguardando aprovação há mais de 3 dias'
      from (select e.unit_id, count(*) n from iara.encaminhamentos e where e.tipo = 'CONSELHO_TUTELAR' and e.situacao = 'AGUARDANDO_APROVACAO'
              and e.created_at < now() - interval '3 days' and e.unit_id = any (p_units) group by 1 having count(*) >= 3 order by 2 desc limit 5) q
      join iara.education_units u on u.id = q.unit_id
      union all
      -- atendimento
      select case when n_urg > 0 then 1 else 2 end, 'Atendimento', null, null,
             n || ' protocolo(s) com prazo vencido' || case when n_urg > 0 then ', ' || n_urg || ' urgente(s) ou de alta prioridade' else '' end
      from (select count(*) n, count(*) filter (where priority in ('ALTA', 'URGENTE')) n_urg from iara.service_cases
            where status not in ('ENCERRADO', 'MATRICULA_CONCLUIDA') and sla_due_at < now() and (unit_id = any (p_units) or p_cidade)) q where n > 0
      union all
      select 2, 'Atendimento', null, null, n || ' família(s) aguardando atendimento humano nas conversas'
      from (select count(*) n from iara.conversations where state = 'HUMAN_PENDING' and (unit_id = any (p_units) or p_cidade)) q where n > 0
      union all
      -- vagas
      select 2, 'Vagas', iara.oraculo_rotulo_unidade(u.unit_type, u.short_name), null, n || ' oferta(s) de vaga vencendo em 24 horas'
      from (select o.unit_id, count(*) n from iara.vacancy_offers o where o.status = 'OFFERED' and o.expires_at < now() + interval '1 day' and o.unit_id = any (p_units)
            group by 1 order by 2 desc limit 5) q join iara.education_units u on u.id = q.unit_id
      union all
      -- transporte
      select 2, 'Transporte', iara.oraculo_rotulo_unidade(u.unit_type, u.short_name), max(v.data), count(*) || ' viagem(ns) não realizada(s) nos últimos 2 dias'
      from iara.transporte_viagens v join iara.transporte_rotas r on r.id = v.rota_id join iara.education_units u on u.id = r.unit_id
      where v.situacao = 'NAO_REALIZADA' and v.data >= v_hoje - 2 and r.unit_id = any (p_units) group by u.unit_type, u.short_name
      union all
      select 2, 'Transporte', null, null, n || ' veículo(s) com a vistoria vencida'
      from (select count(*) n from iara.transporte_veiculos where situacao <> 'MANUTENCAO' and vistoria_validade < v_hoje) q where p_cidade and n > 0
      union all
      -- frequência: turmas sem chamada só quando alguma turma registrou no dia (senão a rede inteira ainda não lançou)
      select 2, 'Frequência', null, v_ult, n || ' turma(s) sem chamada no último dia letivo'
      from (select count(*) n from iara.classes c where c.status = 'ATIVA' and c.unit_id = any (p_units)
              and not exists (select 1 from iara.frequencia_registros r where r.class_id = c.id and r.data = v_ult)) q
      where n > 0 and exists (select 1 from iara.frequencia_registros r where r.data = v_ult)
      union all
      select 1, 'Busca ativa', null, null, n || ' caso(s) urgente(s) de busca ativa em aberto'
      from (select count(*) n from iara.busca_ativa_casos where situacao in ('ABERTO', 'EM_ACOMPANHAMENTO') and urgente and unit_id = any (p_units)) q where n >= 3
      union all
      select 2, 'Frequência', null, null, n || ' aluno(s) entraram em alerta de frequência nos últimos ' || greatest(coalesce(p_dias, 7), 1) || ' dias'
      from (select count(*) n from iara.frequencia_alertas where situacao <> 'RESOLVIDO' and detectado_em >= v_ini and unit_id = any (p_units)) q where n >= 3
      union all
      -- merenda e almoxarifado
      select 2, 'Merenda', null, v_ult, n || ' unidade(s) sem refeição registrada no último dia letivo'
      from (select count(*) n from iara.education_units u where u.id = any (p_units)
              and exists (select 1 from iara.classes c where c.unit_id = u.id and c.status = 'ATIVA')
              and not exists (select 1 from iara.refeicoes_servidas f where f.unit_id = u.id and f.data = v_ult)) q
      where n > 0 and exists (select 1 from iara.refeicoes_servidas f where f.data = v_ult)
      union all
      select 2, 'Almoxarifado', null, null, n || ' lote(s) com validade vencendo em 15 dias'
      from (select count(*) n from iara.estoque_lotes l join iara.materiais m on m.id = l.material_id
            where l.quantidade > 0 and l.validade between v_hoje and v_hoje + 15 and m.unit_id = any (p_units)) q where n > 0
      union all
      select 3, 'Almoxarifado', iara.oraculo_rotulo_unidade(u.unit_type, u.short_name), null, n || ' item(ns) abaixo do estoque mínimo'
      from (select m.unit_id, count(*) n from iara.materiais m where m.ativo and m.quantidade < m.minimo and m.unit_id = any (p_units)
            group by 1 order by 2 desc limit 5) q join iara.education_units u on u.id = q.unit_id
      union all
      -- gestão de pessoas e suporte
      select 3, 'Ponto', null, null, n || ' justificativa(s) de ponto aguardando a direção'
      from (select count(*) n from iara.ponto_justificativas where situacao = 'PENDENTE' and unit_id = any (p_units)) q where n >= 3
      union all
      select 3, 'Suporte', null, null, n || ' chamado(s) de suporte técnico em aberto'
      from (select count(*) n from iara.suporte_chamados where situacao in ('ABERTO', 'EM_ATENDIMENTO', 'AGUARDANDO_SOLICITANTE') and (unit_id = any (p_units) or p_cidade)) q where n > 0
      union all
      -- agenda da rede
      select 3, 'Calendário', null, e.inicio, e.titulo
      from iara.calendario_eventos e where p_cidade and e.abrangencia = 'REDE' and e.inicio between v_hoje and v_hoje + 7
        and e.tipo in ('FERIADO', 'RECESSO', 'FIM_BIMESTRE', 'REUNIAO_PAIS', 'FORMACAO', 'FIM_ANO', 'INICIO_ANO')
    )
    select coalesce(jsonb_agg(jsonb_build_object('nivel', case nivel when 1 then 'ALTA' when 2 then 'MEDIA' else 'INFO' end, 'area', area, 'unidade', unidade, 'quando', quando, 'texto', texto)
                    order by nivel, area, unidade nulls first), '[]')
    from (select * from itens order by nivel, area, unidade nulls first limit 40) q);
end $$;

-- p: unidade?, regiao?, dias?
create or replace function api.oraculo_situacoes(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  a record := iara.oraculo_args(p);
  rc record := iara.oraculo_recorte_de(a.p_unit, a.p_area);
begin
  perform iara.require_perm('oraculo.prefeito');
  return jsonb_build_object('recorte', rc.nome, 'dias', coalesce(nullif(p ->> 'dias', '')::int, 7),
    'situacoes', iara.oraculo_situacoes_lista(rc.unidades, rc.cidade, coalesce(nullif(p ->> 'dias', '')::int, 7)),
    'nota', 'O que pede atenção agora, sem nome de pessoa. Casos sensíveis só aparecem somados na cidade.');
end $$;

-- sem a chave da Anthropic: lê a pergunta e responde pelo catálogo
create or replace function api.oraculo_perguntar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_perg text := btrim(coalesce(p ->> 'pergunta', ''));
  v_w text := ' ' || iara.oraculo_palavras(p ->> 'pergunta') || ' ';
  v_rec jsonb := iara.oraculo_recorte(p ->> 'pergunta');
  v_unit integer := (v_rec ->> 'unidade')::int;
  v_area integer := (v_rec ->> 'area')::int;
  rc record := iara.oraculo_recorte_de(v_unit, v_area);
  v_exemplos constant text := 'Pergunte, por exemplo: “Quantas crianças esperam vaga na creche?”, “Qual escola tem mais ocorrências?”, “Quantos chamados de manutenção estão abertos?” ou “O que está acontecendo na rede?”.';
  v_topico text;
  v_nome text;
  v_quem text;
  v_chaves text[];
  v_tema text;
  v_ord text;
  v_tipo text;
  v_por text;
  n integer;
  r jsonb := '{}';
  x jsonb;
  v_partes text[] := '{}';
  v_texto text;
  v_fora boolean := false;
  v_ferr jsonb := '[]';
begin
  perform iara.require_perm('oraculo.prefeito');
  if length(v_perg) < 3 then
    raise exception 'Faça uma pergunta.' using errcode = '22023';
  end if;
  v_nome := (regexp_match(v_w, ' (?:se chamam?|com o nome de|com o nome|de nome|(?:alunos?|criancas?|estudantes?|professor(?:es|as?)?|pessoas?|profissionais|responsaveis) chamad[oa]s?) +([a-z]{3,}) '))[1];

  if v_w ~ ' (telefone|telefones|celular|whatsapp d[aeo]|endereco|enderecos|cpf|rg|nis|email|e mail) ' and v_w ~ ' (d[aeo]s?|alun[oa]s?|famili[as]+|responsave[il]s?|mae|pai) '
     and v_w !~ ' (quantos|quantas) ' or v_w ~ ' (quem (e|sao|foi|foram)|lista de nomes|nomes d[aeo]s?|quais os nomes|me diga o nome) ' then
    -- dado de pessoa: fora do Oráculo
    v_texto := 'Dados de uma pessoa (nome, telefone, endereço, documentos) não ficam no Oráculo: ele traz números, nunca quem são as pessoas. '
               || 'O detalhe de um caso fica com a Secretaria e com a unidade, com registro de acesso. ' || v_exemplos;
    v_fora := true;
  elsif v_nome is not null then
    -- estatística de nomes: só a contagem, com sigilo
    v_quem := case when v_w ~ ' (professor\w*|profissiona\w*|servidor\w*|educador\w*|funcionari\w*) ' then 'PROFISSIONAIS'
                   when v_w ~ ' (responsave\w*|maes?|pais?|familias?) ' then 'RESPONSAVEIS' else 'ALUNOS' end;
    n := iara.oraculo_contar_nome(v_nome, v_quem, rc.unidades, rc.cidade);
    v_texto := 'Em ' || rc.nome || ': '
               || case when n = 0 then case v_quem when 'PROFISSIONAIS' then 'nenhum profissional' when 'RESPONSAVEIS' then 'nenhum responsável' else 'nenhum aluno' end
                       else case when n between 1 and 2 then 'menos de 3' else iara.num_br(n) end
                            || case v_quem when 'PROFISSIONAIS' then ' profissionais' when 'RESPONSAVEIS' then ' responsáveis' else ' alunos' end end
               || ' com “' || initcap(v_nome) || '” no nome (primeiro nome ou sobrenome). Só a contagem: o Oráculo não mostra quem são.';
    v_topico := 'nomes';
    v_ferr := jsonb_build_array(jsonb_build_object('nomes', v_quem));
    r := jsonb_build_object('topico', v_topico, 'recorte', rc.nome, 'unidade', v_unit, 'area', v_area, 'numeros', '[]'::jsonb);
  elsif v_w ~ ' (qual|quais|onde|ranking) ' and v_w ~ ' (mais|menos|maior|menor|pior|piores|melhor|melhores) '
        and (v_w ~ ' (unidades?|escolas?|cmeis?|regioes|regiao|bairros?) ' or v_w ~ ' onde ') then
    -- comparação: o indicador cujas palavras aparecem na pergunta
    select chave into v_tema from iara.oraculo_indicadores where palavras_ranking is not null and v_w ~ palavras_ranking
    order by (tema = 'base'), ordem limit 1;
    if v_tema is not null then
      v_ord := case when v_w ~ ' (menos|menor) ' then 'menor' when v_w ~ ' (mais|maior) ' then 'maior' end;
      v_tipo := case when v_w ~ ' cmeis? ' then 'CMEI' when v_w ~ ' escolas? ' then 'ESCOLA' end;
      v_por := case when v_w ~ ' (regioes|regiao|bairros?) ' then 'regiao' else 'unidade' end;
      x := iara.oraculo_ranking_lista(v_tema, v_por, v_ord, 5, v_tipo);
      if jsonb_array_length(x -> 'lista') > 0 then
        select array_agg((i ->> 'nome') || ': ' || iara.num_br((i ->> 'valor')::numeric, coalesce((x ->> 'casas')::int, 0)) || coalesce(x ->> 'sufixo', ''))
          into v_partes from jsonb_array_elements(x -> 'lista') i;
        v_texto := (x ->> 'rotulo') || ', ' || case when x ->> 'ordem' = 'maior' then 'os maiores' else 'os menores' end || ' por '
                   || case v_por when 'regiao' then 'região' else coalesce(lower(nullif(v_tipo, '')), 'unidade') end || ': ' || array_to_string(v_partes, '; ') || '.';
      else
        v_texto := (x ->> 'rotulo') || ': nenhuma comparação a mostrar (valores pequenos ficam em sigilo).';
      end if;
      v_topico := 'ranking';
      v_ferr := jsonb_build_array(jsonb_build_object('ranking', v_tema));
      r := jsonb_build_object('topico', v_topico, 'recorte', rc.nome, 'unidade', v_unit, 'area', v_area, 'numeros', '[]'::jsonb);
    end if;
  end if;

  if v_texto is null then
    -- indicadores específicos; se não houver, o tema inteiro
    v_chaves := array(select chave from iara.oraculo_indicadores where palavras is not null and v_w ~ palavras order by ordem limit 6);
    if cardinality(v_chaves) > 0 then
      r := iara.oraculo_tema_numeros(null, v_chaves, v_unit, v_area);
    else
      select tema into v_tema from iara.oraculo_temas where palavras is not null and v_w ~ palavras order by ordem limit 1;
      if v_tema is not null then r := iara.oraculo_tema_numeros(v_tema, null, v_unit, v_area); end if;
    end if;
    if r ? 'numeros' then
      v_topico := r ->> 'topico';
      v_ferr := jsonb_build_array(jsonb_build_object('topico', v_topico, 'unidade', v_unit, 'area', v_area));
    end if;
  end if;

  if v_texto is null and v_topico is null and v_w ~ ' (acontec\w*|problemas?|urgenc\w*|urgentes?|criticos?|criticas?|prioridades?|novidades?) ' then
    x := iara.oraculo_situacoes_lista(rc.unidades, rc.cidade, 7);
    v_topico := 'situacoes';
  end if;

  if v_texto is null and v_topico is null then
    v_topico := case
      when v_w ~ 'bolsa|beneficio|condicionalidade|sistema presenca|cadunico' then 'bolsa_familia'
      when v_w ~ 'creche|bercario' then 'creche'
      when v_w ~ 'fila|espera|aguard' then 'fila'
      when v_w ~ 'vaga' then 'vagas'
      when v_w ~ 'frequenc|presenc|falta|ausen' then 'frequencia'
      when v_w ~ 'ocorrenc|violenc' then 'ocorrencias'
      when v_w ~ 'professor|profissiona|servidor|educador|auxiliar|docente|funcionari' then 'profissionais'
      when v_w ~ 'transporte|onibus|rota|van|motorista' then 'transporte'
      when v_w ~ 'alfabetiz|leitura|escrita|sondagem|ler e escrever' then 'alfabetizacao'
      when v_w ~ 'busca ativa|evasao|abandono' then 'busca_ativa'
      when v_w ~ 'cadastr|documento' then 'cadastros'
      when v_w ~ 'matricul|aluno|estudante|crianca' then 'matriculas'
      when v_w ~ 'unidade|escola|cmei' then 'unidades'
      when v_w ~ ' (hoje|agora|alertas?|pendencias?|situacao|situacoes) ' then 'situacoes'
      when v_w ~ 'geral|resumo|panorama|como esta|rede' then 'visao_geral'
    end;
    if v_topico = 'situacoes' then
      x := iara.oraculo_situacoes_lista(rc.unidades, rc.cidade, 7);
    elsif v_topico is not null then
      r := iara.oraculo_numeros(v_topico, v_unit, v_area);
      v_ferr := jsonb_build_array(jsonb_build_object('topico', v_topico, 'unidade', v_unit, 'area', v_area));
    end if;
  end if;

  if v_texto is null and v_topico = 'situacoes' then
    r := jsonb_build_object('topico', 'situacoes', 'recorte', rc.nome, 'unidade', v_unit, 'area', v_area, 'numeros', '[]'::jsonb, 'situacoes', x);
    v_ferr := jsonb_build_array(jsonb_build_object('topico', 'situacoes', 'unidade', v_unit, 'area', v_area));
    if jsonb_array_length(x) = 0 then
      v_texto := 'Em ' || rc.nome || ': nada pedindo atenção neste momento.';
    else
      select string_agg('• ' || coalesce((i ->> 'unidade') || ': ', '') || (i ->> 'texto') || ' (' || lower(i ->> 'area') || ')', E'\n') into v_texto
      from (select i from jsonb_array_elements(x) i limit 12) q;
      v_texto := 'Em ' || rc.nome || ', o que pede atenção agora:' || E'\n' || v_texto
                 || case when jsonb_array_length(x) > 12 then E'\n…e mais ' || (jsonb_array_length(x) - 12) || ' item(ns).' else '' end;
    end if;
  end if;

  if v_texto is null and v_topico is null then
    -- sem assunto conhecido: avisa e dá o resumo
    v_fora := true;
    r := iara.oraculo_numeros('visao_geral', v_unit, v_area);
    v_ferr := jsonb_build_array(jsonb_build_object('topico', 'visao_geral', 'unidade', v_unit, 'area', v_area));
  end if;

  if v_texto is null then
    for x in select * from jsonb_array_elements(r -> 'numeros') loop
      v_partes := v_partes || ((x ->> 'rotulo') || ': '
                   || case when (x ->> 'sigilo')::boolean then 'menos de 3'
                           else iara.num_br((x ->> 'valor')::numeric, coalesce((x ->> 'casas')::int, 0)) || coalesce(x ->> 'sufixo', '') end);
    end loop;
    v_texto := case when v_fora then 'Não achei na pergunta um assunto que o Oráculo conheça. Segue o resumo da rede. ' else '' end
               || 'Em ' || (r ->> 'recorte') || ' — '
               || case when cardinality(v_partes) = 0 then 'esse número não está disponível neste recorte (alguns só existem para a cidade inteira; outros dependem de dados ainda não lançados)' else array_to_string(v_partes, '; ') end || '.'
               || case when v_fora then ' ' || v_exemplos else '' end;
  end if;

  insert into iara.oraculo_perguntas (user_id, pergunta, canal, modo, resposta, ferramentas, is_demo)
  values (iara.current_user_id(), v_perg, coalesce(nullif(p ->> 'canal', ''), 'TEXTO'), 'REGRAS', v_texto, v_ferr, iara.demo_mode());
  return (case when r ? 'numeros' then r else jsonb_build_object('topico', null, 'recorte', rc.nome, 'numeros', '[]'::jsonb) end)
         || jsonb_build_object('pergunta', v_perg, 'resposta', v_texto, 'modo', 'REGRAS', 'fora', v_fora);
end $$;

revoke all on function iara.oraculo_situacoes_lista(integer[], boolean, integer) from public;

commit;
