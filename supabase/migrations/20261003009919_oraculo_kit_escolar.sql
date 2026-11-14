-- IARA Educa — 099.19 · Oráculo: o que vem no kit escolar e no uniforme
-- "Quais materiais fazem parte do kit para entrega aos alunos" caía no almoxarifado ("materiais") e respondia os itens em falta no
-- estoque. Agora a pergunta sobre o conteúdo do kit ou do uniforme tem leitura própria: a composição oficial (iara.uk_itens e
-- iara.uk_kit_itens, a mesma do Catálogo de Uniformes e kits), por etapa quando a etapa é citada, e o andamento da entrega no recorte.
-- Vale nas regras, no Claude e no conector (leitura_executiva), porque todos passam por iara.oraculo_leitura.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

-- família de um item do kit, para resumir o que vem em vários kits ("cadernos", "lápis de cor"...)
create or replace function iara.uk_item_familia(p text) returns text
language sql immutable
as $$
  select case
    when p ~* '^lápis de cor' then 'lápis de cor'
    when p ~* '^lápis' then 'lápis grafite'
    when p ~* '^canetas esferogr' then 'canetas esferográficas'
    when p ~* '^caneta' then 'canetinhas'
    when p ~* '^caderno' then 'cadernos'
    when p ~* '^massa' then 'massa de modelar'
    when p ~* '^pincel' then 'pincéis'
    when p ~* '^bloco' then 'bloco de desenho A3'
    when p ~* '^giz' then 'giz'
    when p ~* '^cola' then 'cola'
    when p ~* '^borracha' then 'borracha'
    when p ~* '^apontador' then 'apontador'
    when p ~* '^tesoura' then 'tesoura'
    when p ~* '^régua' then 'régua'
    when p ~* '^pasta' then 'pasta'
    when p ~* '^marca-texto' then 'marca-texto'
    else lower(split_part(p, ',', 1)) end
$$;

-- p_w: a pergunta já normalizada (iara.oraculo_palavras, entre espaços)
create or replace function iara.oraculo_ler_kit(p_w text, p_units integer[], p_cidade boolean, p_nome text) returns text
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_ano integer := iara.uk_ano_padrao();
  v_hoje date := iara.hoje_local();
  v_unif boolean := p_w ~ ' (uniforme|uniformes|camiseta|camisetas|jaqueta|jaquetas|papete|papetes|calca|calcas|bermuda|bermudas|meia|meias|blusa|blusas) '
                    and p_w !~ ' (kit|kits|material escolar|materiais escolares) ';
  v_conteudo text;
  v_amp boolean := p_w ~ ' (ampliacao|jornada ampliada|contraturno|atividades complementares) ';
  v_etapa text;
  v_n text;
  k iara.uk_itens;
  ka iara.uk_itens;
  v_linhas text[];
  v_txt text;
  v_oficial boolean;
  s record;
  v_coleta integer;
  v_tam numeric;
  v_sug text[] := '{}';
  g record;
  v_qual text;
  v_total integer;
begin
  v_conteudo := case when v_unif then 'UNIFORME' else 'KIT' end;
  -- etapa citada: "infantil 3", "1º ano", "primeiro ano", "3º e 4º anos", "EJA"
  if p_w ~ ' (eja|jovens e adultos) ' then
    v_etapa := 'EJA';
  elsif p_w ~ ' infantil [0-5] ' then
    v_etapa := 'INF' || substring(p_w from ' infantil ([0-5]) ');
  elsif p_w ~ ' [1-5] (ano|anos|serie) ' then
    v_etapa := 'EF' || substring(p_w from ' ([1-5]) (?:ano|anos|serie) ');
  elsif p_w ~ ' (primeiro|segundo|terceiro|quarto|quinto) (ano|anos|serie) ' then
    v_n := substring(p_w from ' (primeiro|segundo|terceiro|quarto|quinto) (?:ano|anos|serie) ');
    v_etapa := 'EF' || array_position(array['primeiro', 'segundo', 'terceiro', 'quarto', 'quinto'], v_n)::text;
  end if;
  if v_etapa = 'EJA' and v_unif then v_etapa := null; end if;
  if v_amp and coalesce(v_etapa, 'EF') !~ '^EF' then v_amp := false; end if;

  -- 1. o que vem ------------------------------------------------------------------------------------------------------------------
  if v_conteudo = 'KIT' and (v_etapa is not null or v_amp) then
    select * into k from iara.uk_itens i
    where i.ativo and i.tipo = 'KIT' and i.so_ampliacao = v_amp and (v_etapa is null or v_etapa = any (i.etapas))
    order by i.ordem limit 1;
    if k.codigo is null then
      return 'Não há kit escolar cadastrado para ' || coalesce(iara.uk_etapa_rotulo(v_etapa), 'essa etapa') || '. Quem pode confirmar é a Secretaria Municipal de Educação.';
    end if;
    v_linhas := array(select '• ' || ki.item || ': ' || iara.num_br(ki.quantidade) || case when ki.unidade <> 'un' then ' ' || ki.unidade else '' end
                      from iara.uk_kit_itens ki where ki.kit_codigo = k.codigo order by ki.ordem);
    if cardinality(v_linhas) = 0 then
      return k.nome || ': a composição ainda não foi cadastrada no Catálogo de Uniformes e kits. Quem pode confirmar é a Secretaria Municipal de Educação.';
    end if;
    v_txt := k.nome || ' (' || v_ano || ')' || case when k.fonte = 'OFICIAL' then ', pela composição oficial publicada pela Prefeitura' else '' end
      || ': ' || cardinality(v_linhas) || ' itens por aluno.' || E'\n' || array_to_string(v_linhas, E'\n');
    if not v_amp and v_etapa ~ '^EF' then
      select * into ka from iara.uk_itens i where i.ativo and i.tipo = 'KIT' and i.so_ampliacao and v_etapa = any (i.etapas) order by i.ordem limit 1;
      if ka.codigo is not null then
        v_txt := v_txt || E'\n\nQuem está na Ampliação de Jornada recebe também o ' || lower(left(ka.nome, 1)) || substr(ka.nome, 2) || ' ('
          || (select count(*) from iara.uk_kit_itens ki where ki.kit_codigo = ka.codigo) || ' itens), que soma a este.';
      end if;
    end if;

  elsif v_conteudo = 'KIT' then
    select bool_and(i.fonte = 'OFICIAL') into v_oficial from iara.uk_itens i where i.ativo and i.tipo = 'KIT';
    v_linhas := '{}';
    for g in
      with kits as (
        select i.codigo, case when i.so_ampliacao then 4 when i.etapas[1] ~ '^INF' then 1 when i.etapas[1] ~ '^EF' then 2 else 3 end grupo
        from iara.uk_itens i where i.ativo and i.tipo = 'KIT'),
      comp as (select k2.grupo, k2.codigo, iara.uk_item_familia(ki.item) fam, ki.quantidade from kits k2 join iara.uk_kit_itens ki on ki.kit_codigo = k2.codigo),
      fam as (select c.grupo, c.fam, count(distinct c.codigo) nk, sum(c.quantidade) q from comp c group by 1, 2),
      tam as (select k3.grupo, count(*) nkits, min(n) mn, max(n) mx
              from (select k2.grupo, (select count(*) from iara.uk_kit_itens ki where ki.kit_codigo = k2.codigo) n from kits k2) k3 group by 1)
      select t.grupo, t.nkits, t.mn, t.mx,
             array(select f.fam from fam f where f.grupo = t.grupo order by f.nk desc, f.q desc, f.fam limit 10) fams,
             (select count(*) from fam f where f.grupo = t.grupo) nfams
      from tam t where t.mx > 0 order by t.grupo
    loop
      v_linhas := v_linhas || ('• ' || case g.grupo when 1 then 'Educação Infantil' when 2 then '1º ao 5º ano' when 3 then 'EJA' else 'Ampliação de Jornada, que soma ao kit do ano' end
        || ' (' || case when g.nkits > 1 then g.nkits || ' kits, ' else '' end
        || case when g.mn = g.mx then g.mx || ' itens' else 'de ' || g.mn || ' a ' || g.mx || ' itens' end || '): '
        || iara.oraculo_e(g.fams) || case when g.nfams > 10 then ', entre outros' else '' end || '.');
    end loop;
    if cardinality(v_linhas) = 0 then
      return 'A composição dos kits escolares ainda não foi cadastrada no Catálogo de Uniformes e kits. Quem pode confirmar é a Secretaria Municipal de Educação.';
    end if;
    v_txt := 'Kit escolar ' || v_ano || case when v_oficial then ', pela composição oficial publicada pela Prefeitura' else '' end
      || ': o conteúdo muda com a etapa. O que vem nos kits:' || E'\n' || array_to_string(v_linhas, E'\n');

  else
    -- uniforme: peças por aluno; shorts-saia ou bermuda é escolha da família
    select count(distinct e) into v_total from iara.uk_itens u, unnest(u.etapas) e where u.ativo and u.tipo = 'UNIFORME';
    v_linhas := array(
      select '• ' || upper(left(x.nomes, 1)) || substr(x.nomes, 2) || ': ' || iara.num_br(x.qtd)
             || case when x.n > 1 then ' (a família escolhe o modelo)' else '' end
             || case when v_etapa is null and cardinality(x.et) < v_total
                     then ' (do ' || iara.uk_etapa_rotulo(x.et[1]) || ' ao ' || iara.uk_etapa_rotulo(x.et[cardinality(x.et)]) || ')' else '' end
      from (select min(i.ordem) ord, string_agg(lower(i.nome), ' ou ' order by i.ordem) nomes, max(i.quantidade) qtd, count(*) n,
                   string_to_array(min(array_to_string(i.etapas, ',')), ',') et
            from iara.uk_itens i
            where i.ativo and i.tipo = 'UNIFORME' and (v_etapa is null or v_etapa = any (i.etapas))
            group by coalesce(case when i.modelo is not null then 'MODELO_' || i.medida end, i.codigo)) x
      order by x.ord);
    if cardinality(v_linhas) = 0 then
      return 'As peças do uniforme ' || coalesce('do ' || iara.uk_etapa_rotulo(v_etapa), '') || ' ainda não foram cadastradas no Catálogo de Uniformes e kits. Quem pode confirmar é a Secretaria Municipal de Educação.';
    end if;
    select bool_and(i.fonte = 'OFICIAL') into v_oficial from iara.uk_itens i where i.ativo and i.tipo = 'UNIFORME';
    v_txt := 'Uniforme escolar ' || v_ano || coalesce(' do ' || iara.uk_etapa_rotulo(v_etapa), '')
      || case when v_oficial then ', pela composição oficial publicada pela Prefeitura' else '' end || ', peças por aluno:' || E'\n' || array_to_string(v_linhas, E'\n');
  end if;

  -- 2. como está a entrega no recorte -------------------------------------------------------------------------------------------
  select count(*) total,
         count(*) filter (where n.situacao in ('RETIRADA', 'PARCIAL')) retirados,
         count(*) filter (where n.situacao = 'PARCIAL') parciais,
         count(*) filter (where n.situacao = 'DISPONIVEL') disponiveis,
         count(*) filter (where n.situacao = 'DISPONIVEL' and n.prazo_retirada < v_hoje) vencidos,
         count(*) filter (where n.situacao = 'AGUARDANDO_MATERIAL') sem_material,
         count(*) filter (where n.situacao = 'AGUARDANDO_TAMANHO') sem_tamanho
    into s
  from iara.uk_necessidades n
  where n.ano = v_ano and n.conteudo = v_conteudo and n.tipo in ('ANUAL', 'ALUNO_NOVO') and n.situacao not in ('CANCELADA', 'NEGADA')
    and n.unit_id = any (p_units) and (v_etapa is null or n.etapa = v_etapa) and (not v_amp or n.ampliacao);
  v_qual := case when v_conteudo = 'KIT' then 'kit' else 'uniforme' end;
  if s.total = 0 then
    v_txt := v_txt || E'\n\nEntrega de ' || v_ano || ': ainda não há ' || v_qual || 's registrados para ' || p_nome || '.';
  else
    v_txt := v_txt || E'\n\nEntrega de ' || v_ano || ' em ' || p_nome || ': ' || iara.num_br(s.retirados) || ' de ' || iara.num_br(s.total) || ' ' || v_qual || 's'
      || ' já retirados (' || iara.oraculo_pct(s.retirados, s.total, 1) || ')'
      || case when s.parciais = 1 then ', 1 deles em parte' when s.parciais > 1 then ', ' || iara.num_br(s.parciais) || ' deles em parte' else '' end || '.';
    if s.disponiveis > 0 then
      v_txt := v_txt || ' ' || iara.num_br(s.disponiveis) || case when s.disponiveis = 1 then ' espera' else ' esperam' end || ' a família na unidade'
        || case when s.vencidos = 0 then ''
                when s.vencidos = s.disponiveis then case when s.disponiveis = 1 then ', com o prazo de retirada vencido' else ', todos com o prazo de retirada vencido' end
                else ', ' || iara.num_br(s.vencidos) || ' com o prazo de retirada vencido' end || '.';
    end if;
    if s.sem_material > 0 then v_txt := v_txt || ' ' || iara.num_br(s.sem_material) || case when s.sem_material = 1 then ' aguarda' else ' aguardam' end || ' material.'; end if;
    if s.sem_tamanho > 0 then v_txt := v_txt || ' ' || iara.num_br(s.sem_tamanho) || case when s.sem_tamanho = 1 then ' aguarda' else ' aguardam' end || ' o tamanho.'; end if;
    if s.vencidos = 1 then v_sug := v_sug || ('pedir à unidade um novo aviso à família do ' || v_qual || ' com o prazo vencido');
    elsif s.vencidos > 1 then v_sug := v_sug || ('pedir às unidades um novo aviso às famílias dos ' || iara.num_br(s.vencidos) || ' ' || v_qual || 's com o prazo vencido'); end if;
    if s.sem_material = 1 then v_sug := v_sug || ('cobrar do almoxarifado o material do ' || v_qual || ' que ainda não chegou à unidade');
    elsif s.sem_material > 1 then v_sug := v_sug || ('cobrar do almoxarifado o material dos ' || iara.num_br(s.sem_material) || ' ' || v_qual || 's que ainda não chegaram às unidades'); end if;
  end if;

  -- uniforme: a coleta de tamanhos da próxima entrega
  if v_conteudo = 'UNIFORME' then
    select max(c.ano) into v_coleta from iara.uk_campanhas c where c.situacao = 'COLETA_TAMANHOS';
    if v_coleta > v_ano then
      v_tam := iara.oraculo_n('uk.tamanhos', p_units, p_cidade);
      if v_tam is not null then
        v_txt := v_txt || E'\nPara ' || v_coleta || ', ' || iara.num_br(v_tam, 1) || '% dos tamanhos já foram informados.';
        if v_tam < 90 then v_sug := v_sug || ('cobrar das unidades os tamanhos que faltam para ' || v_coleta); end if;
      end if;
    end if;
  end if;

  if cardinality(v_sug) > 0 then v_txt := v_txt || E'\n\nSugestão: ' || iara.oraculo_e(v_sug) || '.'; end if;
  if v_conteudo = 'KIT' and v_etapa is null and not v_amp then
    v_txt := v_txt || E'\n\nPara a lista completa de uma etapa, pergunte: “o que vem no kit do 1º ano?”.';
  end if;
  return v_txt;
end $$;

-- roteador: a pergunta sobre o conteúdo do kit ou do uniforme vem antes de tudo (antes, "materiais" levava ao almoxarifado)
create or replace function iara.oraculo_leitura(p_pergunta text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'iara', 'public'
as $function$
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

  -- o que vem no kit escolar ou no uniforme
  if v_w ~ ' (kit|kits|uniforme|uniformes|material escolar|materiais escolares) '
     and (v_w ~ ' (composicao|compoe|compoem|composto|contem|fazem parte|faz parte|conteudo|itens|pecas|lista de materiais) '
          or (v_w ~ ' (o que|quais|qual|que) ' and v_w ~ ' (materiais|material|vem|vai|tem|inclui|incluem|recebe|recebem|ganha|ganham) '))
     and v_w !~ ' (quantos|quantas|retirad\w*|retiraram|entregues|vencid\w*|percentual|porcentagem) ' then
    v_topico := 'uniformes';
    v_texto := iara.oraculo_ler_kit(v_w, rc.unidades, rc.cidade, rc.nome);
  -- merenda
  elsif v_w ~ ' (comeram|comeu|comem|comer|comendo|comida|almocaram|almocou|almoco|almocos|lancharam|lanche|lanches|jantar|jantaram|desjejum|merenda|merendas|refeicao|refeicoes|cardapio|cardapios|alimentacao|alimentados|servido|servida|servidos|servidas|serviram|servem) '
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
end $function$;

-- empate de tema: "kit" ou "uniforme" na pergunta pesa mais que "materiais" (almoxarifado)
update iara.oraculo_temas set ordem = 12 where tema = 'uniformes';
-- "materiais em falta no almoxarifado" levava às faltas dos alunos: "em falta" é de estoque, não de aluno
update iara.oraculo_assuntos set palavras = replace(palavras, '\mfaltas?\M', '\m(?<!em )faltas?\M')
where assunto = 'faltas' and position('\mfaltas?\M' in palavras) > 0 and position('(?<!em )' in palavras) = 0;

revoke all on function iara.uk_item_familia(text) from public;
revoke all on function iara.oraculo_ler_kit(text, integer[], boolean, text) from public;

commit;
