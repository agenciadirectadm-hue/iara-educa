-- IARA Educa — 099.06 · Uniformes e kits: estatísticas, mapas e órgãos externos
-- A mesma base, sem nomes, para o Prefeito, o Secretário, a Superintendência e os órgãos externos:
--   • Tribunal de Contas (TCE-PR): quantidades compradas, remetidas, entregues, saldos e valor de referência por aluno;
--   • Conselhos (CME e CACS-Fundeb) e Câmara de Vereadores: cobertura por unidade e por região;
--   • Ministério Público e Defensoria (perfil Controle externo, que já existe): a mesma visão agregada;
--   • Conselho Tutelar: além do agregado, as crianças sem retirada muito depois do prazo, só por código público; a consulta de um código
--     exige motivo e fica na trilha de auditoria (inclusive código inexistente).
-- Mapas por unidade (pontos), na tela de Mapas, com a mesma regra de cores. Indicadores no Oráculo do Prefeito.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

-- 1. Perfis dos órgãos externos (demonstração) e permissões ---------------------------------------------------------------------------
insert into iara.organizational_roles (code, tenant_id, name, short_name, description, scope_type, stage_filter, question, org_unit, is_persona, sort) values
  ('TRIBUNAL_CONTAS', 1, 'Tribunal de Contas · TCE-PR', 'TCE-PR', 'Uniformes e kits: o que foi comprado, remetido e entregue, por unidade, com valores de referência. Sem nomes.',
   'AGGREGATE', null, 'O que foi comprado chegou às crianças?', 'Tribunal de Contas do Estado do Paraná', true, 30),
  ('CONSELHOS', 1, 'Conselhos · CME e CACS-Fundeb', 'Conselhos', 'Conselho Municipal de Educação e conselho do Fundeb: cobertura por unidade e região, Ideb das escolas. Sem nomes.',
   'AGGREGATE', null, 'A política chega a todas as escolas?', 'Conselho Municipal de Educação e CACS-Fundeb', true, 31),
  ('CONSELHO_TUTELAR', 1, 'Conselho Tutelar', 'Conselho Tutelar', 'Crianças que não retiraram uniforme e kit muito depois do prazo, por código; consulta com motivo, auditada.',
   'AGGREGATE', null, 'Que crianças precisam de atenção?', 'Conselho Tutelar de Maringá', true, 32),
  ('CAMARA', 1, 'Câmara de Vereadores', 'Câmara', 'Entrega de uniformes e kits por região e unidade, Ideb das escolas. Sem nomes.',
   'AGGREGATE', null, 'Como está a entrega em cada região?', 'Câmara Municipal de Maringá', true, 33)
on conflict (code) do update set name = excluded.name, short_name = excluded.short_name, description = excluded.description,
  scope_type = excluded.scope_type, question = excluded.question, org_unit = excluded.org_unit, is_persona = excluded.is_persona, sort = excluded.sort;

insert into iara.permissions (code, description, is_sensitive) values
  ('uk.custos', 'Ver valores de referência de uniformes e kits (custo por aluno)', false),
  ('uk.tutelar', 'Conselho Tutelar: crianças sem retirada muito depois do prazo, por código, com consulta auditada', true)
on conflict (code) do update set description = excluded.description;
insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('TRIBUNAL_CONTAS', 'units.read'), ('TRIBUNAL_CONTAS', 'uk.estatisticas'), ('TRIBUNAL_CONTAS', 'uk.custos'),
  ('CONSELHOS', 'units.read'), ('CONSELHOS', 'uk.estatisticas'), ('CONSELHOS', 'uk.custos'),
  ('CONSELHO_TUTELAR', 'units.read'), ('CONSELHO_TUTELAR', 'uk.estatisticas'), ('CONSELHO_TUTELAR', 'uk.tutelar'),
  ('CAMARA', 'units.read'), ('CAMARA', 'uk.estatisticas'),
  ('PREFEITO', 'uk.custos'), ('SECRETARIO', 'uk.custos'), ('SUPERINTENDENCIA', 'uk.custos'), ('ALMOXARIFADO', 'uk.custos'), ('CONTROLE_EXTERNO', 'uk.custos')
) v(r, p)
on conflict do nothing;

-- 2. Base agregada por unidade ------------------------------------------------------------------------------------------------------
create or replace function iara.uk_ano_padrao() returns integer
language sql stable security definer set search_path = iara, public
as $$
  select coalesce((select max(ano) from iara.uk_campanhas where situacao in ('SEPARACAO', 'ENTREGA')),
                  (select max(ano) from iara.uk_campanhas where situacao = 'ENCERRADA'),
                  (select max(ano) from iara.uk_campanhas where situacao <> 'PLANEJAMENTO'), iara.school_year())
$$;

-- por unidade, no ano: alunos, tamanhos, material liberado, retirado, vencido, pedidos de troca/reposição
create or replace function iara.uk_por_unidade(p_ano integer) returns table (
  unit_id integer, nome text, tipo text, regiao text, lat double precision, lng double precision,
  alunos bigint, com_tamanho bigint, sem_tamanho bigint, liberados bigint, retirados bigint, vencidos bigint, aguardando bigint,
  pct_tamanho numeric, pct_retirada numeric)
language sql stable security definer set search_path = iara, public
as $$
  with n as (
    -- tamanho informado = pela família ou pela unidade; a estimativa pela idade não conta
    select n.*, exists (select 1 from iara.uk_tamanhos t where t.student_id = n.student_id and t.ano = n.ano and t.canal <> 'ESTIMATIVA') inf
    from iara.uk_necessidades n where n.ano = p_ano and n.tipo in ('ANUAL', 'ALUNO_NOVO') and n.situacao not in ('CANCELADA', 'NEGADA'))
  select u.id, u.short_name, u.unit_type, t.name, u.lat, u.lng,
         count(distinct n.student_id),
         count(distinct n.student_id) filter (where n.conteudo = 'UNIFORME' and n.inf),
         count(distinct n.student_id) filter (where n.conteudo = 'UNIFORME' and not n.inf),
         count(*) filter (where n.situacao in ('DISPONIVEL', 'RETIRADA', 'PARCIAL')),
         count(*) filter (where n.situacao in ('RETIRADA', 'PARCIAL')),
         count(*) filter (where n.situacao = 'DISPONIVEL' and n.prazo_retirada < iara.hoje_local()),
         count(*) filter (where n.situacao in ('AGUARDANDO_MATERIAL', 'AGUARDANDO_TAMANHO')),
         round(100.0 * count(distinct n.student_id) filter (where n.conteudo = 'UNIFORME' and n.inf)
               / nullif(count(distinct n.student_id) filter (where n.conteudo = 'UNIFORME'), 0), 1),
         round(100.0 * count(*) filter (where n.situacao in ('RETIRADA', 'PARCIAL')) / nullif(count(*) filter (where n.situacao in ('DISPONIVEL', 'RETIRADA', 'PARCIAL')), 0), 1)
  from n join iara.education_units u on u.id = n.unit_id
  left join iara.territories t on t.id = u.macro_territory_id
  group by u.id, u.short_name, u.unit_type, t.name, u.lat, u.lng
$$;

-- 3. Estatísticas (Prefeito, SEDUC e órgãos externos) ------------------------------------------------------------------------------
create or replace function api.uk_estatisticas(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_ano integer := coalesce(nullif(p ->> 'ano', '')::int, iara.uk_ano_padrao());
  v_custos boolean := iara.has_perm('uk.custos');
begin
  perform iara.require_perm('uk.estatisticas');
  return (with n as (
      select n.* from iara.uk_necessidades n where n.ano = v_ano and n.situacao not in ('CANCELADA'))
    , anual as (select n.*, exists (select 1 from iara.uk_tamanhos t where t.student_id = n.student_id and t.ano = n.ano and t.canal <> 'ESTIMATIVA') inf from n where n.tipo in ('ANUAL', 'ALUNO_NOVO') and n.situacao <> 'NEGADA')
    , av as (select * from iara.uk_avisos where ano = v_ano)
    , pu as (select * from iara.uk_por_unidade(v_ano))
    , entregue as (
      select it ->> 'item' item, sum((it ->> 'quantidade')::numeric) q
      from anual, jsonb_array_elements(coalesce(anual.entregue, anual.itens)) it
      where anual.situacao in ('RETIRADA', 'PARCIAL') and coalesce((it ->> 'entregue')::boolean, true) group by 1)
    select jsonb_build_object(
      'ano', v_ano,
      'anos', (select coalesce(jsonb_agg(ano order by ano desc), '[]') from iara.uk_campanhas where situacao <> 'PLANEJAMENTO'),
      'campanha', (select iara.uk_campanha_json(c) from iara.uk_campanhas c where c.ano = v_ano),
      'totais', jsonb_build_object(
        'alunos', (select count(distinct student_id) from anual),
        'unidades', (select count(distinct unit_id) from anual),
        'uniformes', (select count(*) from anual where conteudo = 'UNIFORME'),
        'kits', (select count(*) from anual where conteudo = 'KIT'),
        'com_tamanho', (select count(*) from anual where conteudo = 'UNIFORME' and inf),
        'sem_tamanho', (select count(*) from anual where conteudo = 'UNIFORME' and not inf),
        'estimados', (select count(*) from anual where conteudo = 'UNIFORME' and not inf and situacao <> 'AGUARDANDO_TAMANHO'),
        'pct_tamanho', (select round(100.0 * count(*) filter (where inf) / nullif(count(*), 0), 1) from anual where conteudo = 'UNIFORME'),
        'aguardando_material', (select count(*) from anual where situacao = 'AGUARDANDO_MATERIAL'),
        'liberados', (select count(*) from anual where situacao in ('DISPONIVEL', 'RETIRADA', 'PARCIAL')),
        'retirados', (select count(*) from anual where situacao in ('RETIRADA', 'PARCIAL')),
        'parciais', (select count(*) from anual where situacao = 'PARCIAL'),
        'pct_retirada', (select round(100.0 * count(*) filter (where situacao in ('RETIRADA', 'PARCIAL')) / nullif(count(*) filter (where situacao in ('DISPONIVEL', 'RETIRADA', 'PARCIAL')), 0), 1) from anual),
        'vencidos', (select count(*) from anual where situacao = 'DISPONIVEL' and prazo_retirada < iara.hoje_local()),
        'alunos_novos', (select count(*) from anual where tipo = 'ALUNO_NOVO'),
        'com_codigo', (select count(*) from anual where situacao in ('RETIRADA', 'PARCIAL') and codigo_conferido),
        'por_documento', (select count(*) from anual where situacao in ('RETIRADA', 'PARCIAL') and not codigo_conferido)),
      'canais_tamanho', (select coalesce(jsonb_object_agg(canal, q), '{}') from (select canal, count(*) q from iara.uk_tamanhos where ano = v_ano group by canal) z),
      'avisos', jsonb_build_object(
        'total', (select count(*) from av),
        'ciencia', (select count(*) from av where ciente_em is not null),
        'pct_ciencia', (select round(100.0 * count(*) filter (where ciente_em is not null) / nullif(count(*), 0), 1) from av),
        'whatsapp_enviados', (select count(*) from av where whatsapp_status = 'ENVIADO'),
        'whatsapp_simulados', (select count(*) from av where whatsapp_status = 'SIMULADO'),
        'sem_whatsapp', (select count(*) from av where whatsapp_status = 'SEM_WHATSAPP'),
        'na_fila', (select count(*) from av where whatsapp_status = 'AGENDADO')),
      'pedidos', (select coalesce(jsonb_object_agg(tipo, jsonb_build_object('abertos', abertos, 'atendidos', atendidos, 'negados', negados, 'rotulo', iara.uk_tipo_rotulo(tipo))), '{}') from (
                    select tipo, count(*) filter (where situacao in ('AGUARDANDO_DECISAO', 'AGUARDANDO_MATERIAL', 'DISPONIVEL')) abertos,
                           count(*) filter (where situacao in ('RETIRADA', 'PARCIAL')) atendidos, count(*) filter (where situacao = 'NEGADA') negados
                    from n where tipo in ('TROCA_TAMANHO', 'REPOSICAO', 'ADAPTADO') group by tipo) z),
      'por_etapa', (select coalesce(jsonb_agg(jsonb_build_object('etapa', etapa, 'rotulo', iara.uk_etapa_rotulo(etapa), 'alunos', alunos, 'pct_tamanho', pct_tam,
                      'pct_retirada', pct_ret, 'ampliacao', amp) order by ordem), '[]') from (
                      select etapa, count(distinct student_id) alunos, count(distinct student_id) filter (where ampliacao and conteudo = 'KIT') amp,
                             round(100.0 * count(*) filter (where conteudo = 'UNIFORME' and inf) / nullif(count(*) filter (where conteudo = 'UNIFORME'), 0), 1) pct_tam,
                             round(100.0 * count(*) filter (where situacao in ('RETIRADA', 'PARCIAL')) / nullif(count(*) filter (where situacao in ('DISPONIVEL', 'RETIRADA', 'PARCIAL')), 0), 1) pct_ret,
                             case when etapa ~ '^INF' then 0 when etapa ~ '^EF' then 10 else 20 end + coalesce(nullif(regexp_replace(etapa, '\D', '', 'g'), '')::int, 0) ordem
                      from anual where etapa is not null group by etapa) z),
      'por_regiao', (select coalesce(jsonb_agg(jsonb_build_object('regiao', coalesce(regiao, 'Sem região'), 'unidades', u, 'alunos', a, 'pct_tamanho', pt, 'pct_retirada', pr, 'vencidos', v)
                       order by pr nulls first, a desc), '[]') from (
                       select regiao, count(*) u, sum(alunos) a, round(100.0 * sum(com_tamanho) / nullif(sum(com_tamanho + sem_tamanho), 0), 1) pt,
                              round(100.0 * sum(retirados) / nullif(sum(liberados), 0), 1) pr, sum(vencidos) v from pu group by regiao) z),
      'por_unidade', (select coalesce(jsonb_agg(jsonb_build_object('unit_id', unit_id, 'nome', nome, 'tipo', tipo, 'regiao', regiao, 'alunos', alunos,
                        'pct_tamanho', pct_tamanho, 'pct_retirada', pct_retirada, 'sem_tamanho', sem_tamanho, 'liberados', liberados, 'retirados', retirados,
                        'vencidos', vencidos, 'aguardando', aguardando) order by pct_retirada nulls first, vencidos desc, nome), '[]') from pu),
      'estoque', jsonb_build_object(
        'central_uniforme', (select coalesce(sum(quantidade), 0) from iara.materiais where unit_id is null and ativo and codigo like 'UNI-%'),
        'central_kits', (select coalesce(sum(quantidade), 0) from iara.materiais where unit_id is null and ativo and codigo like 'KIT-%'),
        'unidades_uniforme', (select coalesce(sum(quantidade), 0) from iara.materiais where unit_id is not null and ativo and codigo like 'UNI-%'),
        'unidades_kits', (select coalesce(sum(quantidade), 0) from iara.materiais where unit_id is not null and ativo and codigo like 'KIT-%'),
        'remessas', (select coalesce(jsonb_object_agg(situacao, q), '{}') from (
                       select pe.situacao, count(*) q from iara.pedidos pe where pe.justificativa like format('Uniformes e kits %s%%', v_ano) group by 1) z)),
      'entregue_por_item', (select coalesce(jsonb_agg(jsonb_build_object('codigo', i.codigo, 'nome', i.nome, 'tipo', i.tipo, 'quantidade', e.q,
                              'valor', case when v_custos then round(e.q * i.valor_referencia, 2) end) order by i.tipo desc, i.ordem), '[]')
                            from entregue e join iara.uk_itens i on i.codigo = e.item),
      'custos', case when v_custos then jsonb_build_object(
        'valor_entregue', (select round(sum(e.q * i.valor_referencia), 2) from entregue e join iara.uk_itens i on i.codigo = e.item),
        'alunos_atendidos', (select count(distinct student_id) from anual where situacao in ('RETIRADA', 'PARCIAL')),
        'por_aluno', (select round(sum(e.q * i.valor_referencia) / nullif((select count(distinct student_id) from anual where situacao in ('RETIRADA', 'PARCIAL')), 0), 2)
                      from entregue e join iara.uk_itens i on i.codigo = e.item),
        'sem_preco', (select coalesce(jsonb_agg(i.nome), '[]') from entregue e join iara.uk_itens i on i.codigo = e.item where i.valor_referencia is null),
        'valor_demo', exists (select 1 from iara.uk_itens where valor_demo and valor_referencia is not null)) end,
      'tutelar', case when iara.has_perm('uk.tutelar') then (select count(distinct student_id) from iara.uk_tutelar_casos()) end,
      'nota', 'Sem nomes: números por etapa, região e unidade. Retirada = retirado ÷ liberado para retirada. Tamanho informado = pela família (portal ou IARA) ou pela unidade; a estimativa pela idade não conta como informado.'));
end $$;

-- 4. Mapa por unidade (mesmo formato de api.mapa_calor) -------------------------------------------------------------------------------
create or replace function api.uk_mapa(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_camada text := coalesce(nullif(p ->> 'camada', ''), 'uk_retirada');
  v_ano integer := coalesce(nullif(p ->> 'ano', '')::int, iara.uk_ano_padrao());
  v_verde constant text := '#16A34A';
  v_amarelo constant text := '#EAB308';
  v_vermelho constant text := '#DC2626';
  v_pontos jsonb;
  v_rank jsonb;
  v_leg jsonb;
  v_res jsonb;
begin
  perform iara.require_perm('uk.estatisticas');
  if v_camada not in ('uk_retirada', 'uk_tamanhos', 'uk_vencidas') then raise exception 'Mapa desconhecido.' using errcode = '22023'; end if;
  if v_camada = 'uk_retirada' then
    select coalesce(jsonb_agg(jsonb_build_object('lat', lat, 'lng', lng, 'valor', pct_retirada,
             'titulo', format('%s: %s%% retirado (%s de %s itens liberados)%s', nome, replace(pct_retirada::text, '.', ','), retirados, liberados,
                              case when vencidos > 0 then format('; %s com prazo vencido', vencidos) else '' end),
             'cor', case when pct_retirada >= 90 then v_verde when pct_retirada >= 70 then v_amarelo else v_vermelho end)), '[]') into v_pontos
    from iara.uk_por_unidade(v_ano) where liberados > 0 and lat is not null;
    select coalesce(jsonb_agg(jsonb_build_object('nome', nome, 'valor', pct_retirada, 'sufixo', '%', 'detalhe', format('%s de %s · %s vencido(s)', retirados, liberados, vencidos))
             order by pct_retirada, liberados desc), '[]') into v_rank
    from (select * from iara.uk_por_unidade(v_ano) where liberados >= 5 order by pct_retirada, liberados desc limit 10) z;
    v_leg := jsonb_build_array(jsonb_build_object('cor', v_vermelho, 'rotulo', 'Retirou pouco (abaixo de 70%)'),
             jsonb_build_object('cor', v_amarelo, 'rotulo', 'Intermediário (70% a 89%)'), jsonb_build_object('cor', v_verde, 'rotulo', 'Retirou muito (90% ou mais)'));
    select jsonb_build_array(
      jsonb_build_object('rotulo', 'Retirado na rede', 'valor', round(100.0 * sum(retirados) / nullif(sum(liberados), 0)), 'sufixo', '%'),
      jsonb_build_object('rotulo', 'Itens liberados', 'valor', sum(liberados)), jsonb_build_object('rotulo', 'Com prazo vencido', 'valor', sum(vencidos)))
    into v_res from iara.uk_por_unidade(v_ano);
  elsif v_camada = 'uk_tamanhos' then
    select coalesce(jsonb_agg(jsonb_build_object('lat', lat, 'lng', lng, 'valor', pct_tamanho,
             'titulo', format('%s: %s%% dos tamanhos informados (%s sem tamanho)', nome, replace(coalesce(pct_tamanho, 0)::text, '.', ','), sem_tamanho),
             'cor', case when pct_tamanho >= 90 then v_verde when pct_tamanho >= 60 then v_amarelo else v_vermelho end)), '[]') into v_pontos
    from iara.uk_por_unidade(v_ano) where (com_tamanho + sem_tamanho) > 0 and lat is not null;
    select coalesce(jsonb_agg(jsonb_build_object('nome', nome, 'valor', pct_tamanho, 'sufixo', '%', 'detalhe', format('%s sem tamanho', sem_tamanho))
             order by pct_tamanho, sem_tamanho desc), '[]') into v_rank
    from (select * from iara.uk_por_unidade(v_ano) where (com_tamanho + sem_tamanho) >= 5 order by pct_tamanho, sem_tamanho desc limit 10) z;
    v_leg := jsonb_build_array(jsonb_build_object('cor', v_vermelho, 'rotulo', 'Poucos informaram (abaixo de 60%)'),
             jsonb_build_object('cor', v_amarelo, 'rotulo', 'Intermediário (60% a 89%)'), jsonb_build_object('cor', v_verde, 'rotulo', 'Quase todos (90% ou mais)'));
    select jsonb_build_array(
      jsonb_build_object('rotulo', 'Tamanhos informados', 'valor', round(100.0 * sum(com_tamanho) / nullif(sum(com_tamanho + sem_tamanho), 0)), 'sufixo', '%'),
      jsonb_build_object('rotulo', 'Alunos sem tamanho', 'valor', sum(sem_tamanho)))
    into v_res from iara.uk_por_unidade(v_ano);
  else
    select coalesce(jsonb_agg(jsonb_build_object('lat', lat, 'lng', lng, 'valor', vencidos,
             'titulo', format('%s: %s item(ns) com prazo de retirada vencido', nome, vencidos),
             'cor', case when vencidos = 0 then v_verde when vencidos <= 5 then v_amarelo else v_vermelho end)), '[]') into v_pontos
    from iara.uk_por_unidade(v_ano) where liberados > 0 and lat is not null;
    select coalesce(jsonb_agg(jsonb_build_object('nome', nome, 'valor', vencidos, 'sufixo', case when vencidos = 1 then ' item' else ' itens' end,
             'detalhe', format('%s%% retirado', replace(coalesce(pct_retirada, 0)::text, '.', ','))) order by vencidos desc), '[]') into v_rank
    from (select * from iara.uk_por_unidade(v_ano) where vencidos > 0 order by vencidos desc limit 10) z;
    v_leg := jsonb_build_array(jsonb_build_object('cor', v_vermelho, 'rotulo', 'Mais de 5 vencidos'),
             jsonb_build_object('cor', v_amarelo, 'rotulo', '1 a 5 vencidos'), jsonb_build_object('cor', v_verde, 'rotulo', 'Nenhum vencido'));
    select jsonb_build_array(jsonb_build_object('rotulo', 'Itens com prazo vencido', 'valor', sum(vencidos)),
                             jsonb_build_object('rotulo', 'Unidades com vencidos', 'valor', count(*) filter (where vencidos > 0)))
    into v_res from iara.uk_por_unidade(v_ano);
  end if;
  return jsonb_build_object('modo', 'taxa', 'sufixo', case when v_camada = 'uk_vencidas' then '' else '%' end, 'max', null, 'pontos', v_pontos,
    'legenda', v_leg, 'resumo', v_res, 'ranking', jsonb_build_object('titulo', case v_camada when 'uk_retirada' then 'Unidades que menos retiraram'
       when 'uk_tamanhos' then 'Unidades com menos tamanhos informados' else 'Unidades com mais prazos vencidos' end, 'itens', v_rank),
    'nota', format('Uniformes e kits %s, por unidade. Sem nomes.', v_ano));
end $$;

-- 5. Conselho Tutelar: por código, consulta com motivo e auditada ------------------------------------------------------------------------
create or replace function iara.uk_tutelar_casos() returns table (student_id uuid, codigo text, unit_id integer, etapa text, prazo date, dias integer, avisos bigint, ciente boolean)
language sql stable security definer set search_path = iara, public
as $$
  select n.student_id, iara.codigo_publico(n.student_id), n.unit_id, n.etapa, min(n.prazo_retirada), (iara.hoje_local() - min(n.prazo_retirada))::int,
         (select count(*) from iara.uk_avisos a where a.student_id = n.student_id and a.ano = n.ano and a.tipo in ('RETIRADA', 'LEMBRETE_RETIRADA')),
         exists (select 1 from iara.uk_avisos a where a.student_id = n.student_id and a.ano = n.ano and a.ciente_em is not null)
  from iara.uk_necessidades n
  where n.situacao = 'DISPONIVEL' and n.tipo in ('ANUAL', 'ALUNO_NOVO')
    and n.prazo_retirada < iara.hoje_local() - coalesce((iara.uk_param('tutelar_dias'))::int, 15)
  group by n.student_id, n.ano, n.unit_id, n.etapa
$$;

create or replace function api.uk_tutelar_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('uk.tutelar');
  return jsonb_build_object(
    'dias', coalesce((iara.uk_param('tutelar_dias'))::int, 15),
    'casos', (select coalesce(jsonb_agg(jsonb_build_object('codigo', c.codigo, 'unidade', u.short_name, 'regiao', t.name, 'etapa', iara.uk_etapa_rotulo(c.etapa),
                'prazo', c.prazo, 'dias', c.dias, 'avisos', c.avisos, 'ciente', c.ciente) order by c.dias desc), '[]')
              from iara.uk_tutelar_casos() c join iara.education_units u on u.id = c.unit_id left join iara.territories t on t.id = u.macro_territory_id),
    'nota', 'Crianças com uniforme ou kit liberado e não retirado muito depois do prazo, depois dos avisos e do lembrete. Só o código público: o nome aparece na consulta, que exige motivo e fica registrada.');
end $$;

create or replace function api.uk_tutelar_consulta(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_cod text := upper(btrim(coalesce(p ->> 'codigo', '')));
  v_motivo text := nullif(btrim(coalesce(p ->> 'motivo', '')), '');
  c record;
  s iara.students;
begin
  perform iara.require_perm('uk.tutelar');
  if coalesce(length(v_motivo), 0) < 15 then raise exception 'Informe o motivo da consulta (pelo menos 15 caracteres): fica registrado.' using errcode = '22023'; end if;
  select * into c from iara.uk_tutelar_casos() x where x.codigo = v_cod limit 1;
  perform iara.audit_event('TUTELAR_CONSULTA', 'student', coalesce(c.student_id::text, v_cod), c.unit_id,
                           format('Conselho Tutelar consultou o código %s%s. Motivo: %s', v_cod, case when c.student_id is null then ' (inexistente ou fora da lista)' else '' end, v_motivo));
  -- sem erro: um erro desfaria o registro da consulta na auditoria
  if c.student_id is null then return jsonb_build_object('encontrado', false, 'mensagem', 'Código não encontrado na lista de atenção. A consulta ficou registrada.'); end if;
  select * into s from iara.students where id = c.student_id;
  return jsonb_build_object('encontrado', true, 'codigo', v_cod, 'nome', s.full_name, 'idade', iara.age_text(s.birth_date),
    'unidade', (select u.short_name || coalesce(' · ' || u.phone, '') from iara.education_units u where u.id = c.unit_id),
    'turma', (select cl.class_name from iara.enrollments e join iara.classes cl on cl.id = e.class_id where e.student_id = s.id and e.status = 'ACTIVE' limit 1),
    'bairro', (select a.neighborhood from iara.addresses a where a.id = s.address_id),
    'responsavel', (select jsonb_build_object('nome', g.full_name, 'parentesco', iara.uk_parentesco(sg.relationship), 'telefone', coalesce(g.whatsapp_phone, g.primary_phone))
                    from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
                    where sg.student_id = s.id and sg.end_date is null order by sg.is_primary desc limit 1),
    'prazo', c.prazo, 'dias', c.dias,
    'avisos', (select coalesce(jsonb_agg(jsonb_build_object('titulo', a.titulo, 'enviado_em', a.enviado_em, 'whatsapp', a.whatsapp_status, 'ciente_em', a.ciente_em)
                 order by a.enviado_em), '[]') from iara.uk_avisos a where a.student_id = s.id and a.tipo in ('RETIRADA', 'LEMBRETE_RETIRADA', 'TAMANHO')),
    'aviso', 'Uso exclusivo do Conselho Tutelar para a proteção da criança. A consulta foi registrada na trilha de auditoria.');
end $$;

-- 6. Oráculo do Prefeito ------------------------------------------------------------------------------------------------------------
update iara.oraculo_temas set palavras = replace(replace(palavras, '|\muniforme', ''), '\mmateria(l|is)\M', '\mmateria(l|is)\M(?! escolar)') where tema = 'almoxarifado';
insert into iara.oraculo_temas (tema, rotulo, palavras, ordem) values
  ('uniformes', 'Uniformes e kits escolares', '\muniforme|\mkits?\M|\mkit escolar|\mmaterial escolar|\mcamiseta|\mjaqueta|\mpapete|\mtamanhos? do uniforme|\mretirad', 13)
on conflict (tema) do update set rotulo = excluded.rotulo, palavras = excluded.palavras;
insert into iara.oraculo_indicadores (chave, tema, rotulo, consulta, pessoas, sufixo, casas, palavras, palavras_ranking, pior, ordem) values
('uk.retirada', 'uniformes', 'Uniformes e kits retirados (do que foi liberado)',
 $q$select round(100.0 * count(*) filter (where situacao in ('RETIRADA', 'PARCIAL')) / nullif(count(*) filter (where situacao in ('DISPONIVEL', 'RETIRADA', 'PARCIAL')), 0), 1) from iara.uk_necessidades where ano = iara.uk_ano_padrao() and tipo in ('ANUAL', 'ALUNO_NOVO') and unit_id = any ($1)$q$,
 false, '%', 1, '\mretirad|\mentreg', '\mretirad|\mentreg', 'menor', 1),
('uk.tamanhos', 'uniformes', 'Tamanhos do uniforme informados',
 $q$select round(100.0 * count(*) filter (where situacao <> 'AGUARDANDO_TAMANHO') / nullif(count(*), 0), 1) from iara.uk_necessidades where ano = (select coalesce(max(ano), iara.school_year()) from iara.uk_campanhas where situacao in ('COLETA_TAMANHOS', 'SEPARACAO', 'ENTREGA')) and conteudo = 'UNIFORME' and tipo in ('ANUAL', 'ALUNO_NOVO') and situacao not in ('CANCELADA', 'NEGADA') and unit_id = any ($1)$q$,
 false, '%', 1, '\mtamanhos?\M', '\mtamanhos?\M', 'menor', 2),
('uk.sem_tamanho', 'uniformes', 'Alunos sem o tamanho do uniforme',
 $q$select count(distinct student_id) from iara.uk_necessidades where situacao = 'AGUARDANDO_TAMANHO' and unit_id = any ($1)$q$,
 true, null, 0, '\msem tamanho|\mnao informou', null, 'maior', 3),
('uk.vencidos', 'uniformes', 'Uniformes e kits com prazo de retirada vencido',
 $q$select count(*) from iara.uk_necessidades where situacao = 'DISPONIVEL' and prazo_retirada < $3 and unit_id = any ($1)$q$,
 false, null, 0, '\mvencid|\mnao retir', '\mvencid|\mnao retir', 'maior', 4),
('uk.pedidos', 'uniformes', 'Trocas e reposições aguardando a unidade',
 $q$select count(*) from iara.uk_necessidades where situacao = 'AGUARDANDO_DECISAO' and tipo in ('TROCA_TAMANHO', 'REPOSICAO') and unit_id = any ($1)$q$,
 false, null, 0, '\mtroca|\mreposic|\mperd', null, 'maior', 5),
('uk.adaptados', 'uniformes', 'Pedidos de material adaptado em aberto',
 $q$select count(*) from iara.uk_necessidades where conteudo = 'ADAPTADO' and situacao in ('AGUARDANDO_DECISAO', 'AGUARDANDO_MATERIAL', 'DISPONIVEL') and unit_id = any ($1)$q$,
 false, null, 0, '\madaptad|\mbraille|\mampliad', null, 'maior', 6)
on conflict (chave) do update set tema = excluded.tema, rotulo = excluded.rotulo, consulta = excluded.consulta, pessoas = excluded.pessoas, sufixo = excluded.sufixo,
  casas = excluded.casas, palavras = excluded.palavras, palavras_ranking = excluded.palavras_ranking, pior = excluded.pior, ordem = excluded.ordem;

revoke all on function iara.uk_tutelar_casos(), iara.uk_por_unidade(integer) from public;

commit;
