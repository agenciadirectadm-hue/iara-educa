-- IARA Educa — 099.21 · Oráculo: a demanda do Prefeito e o tratamento pelo gênero
-- Pedido de Rob (14/11/2026):
--  • quando o Prefeito pede ao Oráculo uma informação que o IARA não tem, o Oráculo envia o pedido à área responsável, para atendimento
--    com prioridade. A demanda entra na Central de pendências da área (tipo DEMANDA_PREFEITO): prazo de 2 dias úteis, no topo da lista,
--    e só se conclui com a resposta escrita, que volta ao Oráculo. O Prefeito acompanha e cobra pelo próprio Oráculo.
--  • o Oráculo trata o Prefeito pelo gênero do cadastro do usuário (app_users.genero); sem ele, pela configuração do município
--    (prefeito_genero), que vale para as próximas sessões do gabinete e para a conexão do assistente; sem nenhum dos dois, tratamento neutro.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

-- 1. Tratamento pelo gênero -----------------------------------------------------------------------------------------------------------
alter table iara.app_users add column if not exists genero text check (genero in ('FEMININO', 'MASCULINO'));
insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('app_users', 'genero', 'PESSOAL', 'identificação', 'tratamento do usuário pelo Oráculo (o senhor, a senhora)', 'informado pelo próprio usuário; só o tratamento')
on conflict (tabela, coluna) do nothing;

create or replace function iara.oraculo_tratamento_de(p_user uuid) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select case x.g
    when 'FEMININO' then jsonb_build_object('genero', 'FEMININO', 'cargo', 'Prefeita', 'pronome', 'a senhora', 'gabinete', 'Gabinete da Prefeita', 'demanda', 'Demanda da Prefeita')
    when 'MASCULINO' then jsonb_build_object('genero', 'MASCULINO', 'cargo', 'Prefeito', 'pronome', 'o senhor', 'gabinete', 'Gabinete do Prefeito', 'demanda', 'Demanda do Prefeito')
    else jsonb_build_object('genero', null, 'cargo', null, 'pronome', null, 'gabinete', 'Gabinete', 'demanda', 'Demanda do Gabinete') end
  from (select coalesce((select u.genero from iara.app_users u where u.id = p_user), nullif(iara.setting('prefeito_genero'), '')) g) x
$$;

-- p: genero (FEMININO, MASCULINO ou vazio para neutro) para definir; sem genero, só devolve o tratamento atual
create or replace function api.oraculo_tratamento(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v text := nullif(upper(btrim(coalesce(p ->> 'genero', ''))), '');
begin
  perform iara.require_perm('oraculo.prefeito');
  if p ? 'genero' then
    if v is not null and v not in ('FEMININO', 'MASCULINO') then raise exception 'Use FEMININO ou MASCULINO.' using errcode = '22023'; end if;
    update iara.app_users set genero = v where id = iara.current_user_id();
    -- o gabinete é um só: vale também para as próximas sessões e para a conexão do assistente
    update iara.tenants set settings = case when v is null then settings - 'prefeito_genero' else jsonb_set(settings, '{prefeito_genero}', to_jsonb(v)) end
    where id = 1;
    perform iara.audit_event('ORACULO_TRATAMENTO', 'app_user', iara.current_user_id()::text, null, 'Tratamento no Oráculo: ' || coalesce(lower(v), 'neutro'));
  end if;
  return iara.oraculo_tratamento_de(iara.current_user_id());
end $$;

-- 2. As áreas que recebem demandas ----------------------------------------------------------------------------------------------------
create or replace function iara.oraculo_areas() returns table (codigo text, papel text, setor_sigla text, rotulo text, cuida text)
language sql immutable
as $$
  select * from (values
    ('SECRETARIO', 'SECRETARIO', 'SEDUC', 'Secretário(a) de Educação', 'assuntos gerais da Secretaria, pessoal, contatos de servidores e o que não tem área própria'),
    ('SUPERINTENDENCIA', 'SUPERINTENDENCIA', 'SUP', 'Superintendência', 'coordenação das diretorias, quadro de servidores, lotação e indicadores da rede'),
    ('EDUCACAO_INFANTIL', 'GERENCIA_EI', 'GEI', 'Gerência de Educação Infantil', 'CMEIs, creche e pré-escola'),
    ('EDUCACAO_ESPECIAL', 'GERENCIA_APOIO', 'GEE', 'Gerência de Educação Especial e Apoio', 'AEE, inclusão e apoio interdisciplinar'),
    ('CENTRAL_DE_VAGAS', 'ANALISTA_CENTRAL', 'CV', 'Central de Vagas', 'fila, vagas, matrículas e transferências'),
    ('ATENDIMENTO', 'ATENDIMENTO', 'CA', 'Central de Atendimento', 'protocolos e atendimento às famílias'),
    ('INOVACAO', 'INOVACAO', 'DINOV', 'Diretoria de Inovação Educacional', 'sistemas, dados e o próprio IARA'),
    ('MERENDA', 'NUTRICAO', 'GME', 'Gerência da Merenda Escolar', 'merenda, cardápio e refeições servidas'),
    ('TRANSPORTE', 'TRANSPORTE', 'GTE', 'Gerência de Transporte Escolar', 'transporte escolar, rotas, frota e motoristas'),
    ('ALMOXARIFADO', 'ALMOXARIFADO', 'GSA', 'Gerência de Suprimentos e Almoxarifado', 'materiais, uniformes e kits, estoque e compras'),
    ('MANUTENCAO', 'MANUTENCAO', 'DMAN', 'Divisão de Manutenção', 'prédios, reformas e chamados de manutenção'),
    ('DIRECAO_DA_UNIDADE', 'DIRETOR_UNIDADE', 'UNID', 'Direção da unidade', 'o que é de uma escola ou CMEI específico (informe a unidade)')
  ) v(codigo, papel, setor_sigla, rotulo, cuida)
$$;

-- prazo em dias úteis (sem fim de semana nem feriado da rede), às 18h
create or replace function iara.oraculo_prazo_uteis(p_dias integer) returns timestamptz
language plpgsql stable set search_path = iara, public
as $$
declare
  d date := iara.hoje_local();
  n integer := 0;
begin
  while n < p_dias loop
    d := d + 1;
    if extract(isodow from d) < 6 and not exists (select 1 from iara.calendario_eventos c
        where c.tipo = 'FERIADO' and c.unit_id is null and d between c.inicio::date and coalesce(c.fim, c.inicio)::date) then
      n := n + 1;
    end if;
  end loop;
  return (d::timestamp + time '18:00') at time zone 'America/Sao_Paulo';
end $$;

-- 3. A demanda na Central de pendências -----------------------------------------------------------------------------------------------
insert into iara.pend_tipos (codigo, modulo, titulo, papel, procedimento, prazo_regra, rota, origem, ordem) values
  ('DEMANDA_PREFEITO', 'Demandas do Prefeito', 'Demanda do Prefeito', null,
   'O Prefeito pediu esta informação ou providência pelo Oráculo, e o IARA não tinha a resposta. Atenda com prioridade: escreva a resposta '
   || 'ao Prefeito na nota da conclusão. Ela volta para o Oráculo com o seu nome, a data e a hora. Se a informação não existir ou depender '
   || 'de outra área, diga isso na resposta e quem pode resolver.',
   '2 dias úteis, com prioridade sobre as demais pendências.', null, 'ATRIBUIDA', 0)
on conflict (codigo) do update set modulo = excluded.modulo, titulo = excluded.titulo, procedimento = excluded.procedimento,
  prazo_regra = excluded.prazo_regra, origem = excluded.origem, ordem = excluded.ordem;

create or replace function iara.oraculo_demanda_json(x iara.pendencias) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object(
    'id', x.id, 'numero', upper(left(x.id::text, 8)),
    'pedido', regexp_replace(x.titulo, '^Demanda d[oa] (Prefeit[oa]|Gabinete): ', ''),
    'area', coalesce((select s.nome from iara.org_setores s where s.id = x.setor_id and s.sigla <> 'UNID'), iara.pend_posto_rotulo(x.papel, x.unit_id, x.setor_id, x.staff_id)),
    'unidade', (select u.short_name from iara.education_units u where u.id = x.unit_id),
    'criada_em', x.criada_em, 'prazo', x.prazo, 'situacao', x.situacao,
    'atrasada', x.situacao = 'ABERTA' and x.prazo < now(),
    'respondida_em', case when x.situacao = 'CONCLUIDA' then x.concluida_em end,
    'resposta', x.conclusao, 'respondida_por', x.concluida_por_label,
    'motivo_cancelamento', case when x.situacao = 'CANCELADA' then (select e.texto from iara.pend_eventos e where e.pendencia_id = x.id and e.tipo = 'CANCELADA' order by e.em desc limit 1) end,
    'cobrancas', (select count(*) from iara.pend_eventos e where e.pendencia_id = x.id and e.tipo = 'COBRADA'))
$$;

-- p: area (codigo de iara.oraculo_areas), pedido, o_que_falta, pergunta (as palavras do Prefeito), unidade (nome ou id)
create or replace function api.oraculo_demandar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  a record;
  v_area text := upper(btrim(coalesce(p ->> 'area', '')));
  v_pedido text := regexp_replace(btrim(coalesce(p ->> 'pedido', '')), '\s+', ' ', 'g');
  v_falta text := nullif(btrim(coalesce(p ->> 'o_que_falta', '')), '');
  v_perg text := nullif(btrim(coalesce(p ->> 'pergunta', '')), '');
  v_un text := nullif(btrim(coalesce(p ->> 'unidade', '')), '');
  v_unit integer;
  v_n integer;
  v_posto_unit integer;
  v_setor uuid;
  v_trat jsonb := iara.oraculo_tratamento_de(iara.current_user_id());
  v_det text;
  x iara.pendencias;
begin
  perform iara.require_perm('oraculo.prefeito');
  select * into a from iara.oraculo_areas() o where o.codigo = v_area;
  if a.codigo is null then
    raise exception 'Área desconhecida: %. Use uma destas: %.', v_area, (select string_agg(codigo, ', ') from iara.oraculo_areas()) using errcode = '22023';
  end if;
  if length(v_pedido) < 10 or length(v_pedido) > 600 then
    raise exception 'Escreva o pedido (de 10 a 600 caracteres).' using errcode = '22023';
  end if;
  if v_un is not null then
    if v_un ~ '^[0-9]+$' then
      select id into v_unit from iara.education_units where id = v_un::int;
    else
      select id into v_unit from iara.education_units where iara.norm(short_name) = iara.norm(v_un) or iara.norm(name) = iara.norm(v_un) limit 1;
      if v_unit is null then
        select count(*), min(id) into v_n, v_unit from iara.education_units where iara.norm(short_name || ' ' || name) like '%' || iara.norm(v_un) || '%';
        if v_n > 1 then
          raise exception 'Há % unidades com "%": diga qual (%).', v_n, v_un,
            (select string_agg(short_name, '; ') from (select short_name from iara.education_units where iara.norm(short_name || ' ' || name) like '%' || iara.norm(v_un) || '%' order by short_name limit 6) z)
            using errcode = '22023';
        end if;
      end if;
    end if;
    if v_unit is null then raise exception 'Unidade não encontrada: %.', v_un using errcode = '22023'; end if;
  end if;
  if a.papel = 'DIRETOR_UNIDADE' and v_unit is null then
    raise exception 'Para a direção de uma unidade, informe qual unidade.' using errcode = '22023';
  end if;
  -- a área da SEDUC recebe no setor; a direção, na unidade
  v_posto_unit := case when a.papel = 'DIRETOR_UNIDADE' then v_unit end;
  v_setor := (select id from iara.org_setores where sigla = a.setor_sigla);

  -- o mesmo pedido, ainda aberto na mesma área: não duplica
  select * into x from iara.pendencias d
  where d.tipo = 'DEMANDA_PREFEITO' and d.situacao = 'ABERTA' and d.papel = a.papel and d.unit_id is not distinct from v_posto_unit
    and extensions.similarity(iara.norm(regexp_replace(d.titulo, '^Demanda d[oa] (Prefeit[oa]|Gabinete): ', '')), iara.norm(v_pedido)) > 0.55
  order by d.criada_em desc limit 1;
  if x.id is not null then
    return iara.oraculo_demanda_json(x) || jsonb_build_object('ja_existia', true);
  end if;

  v_det := (v_trat ->> 'cargo') || ' pediu: ' || v_pedido;
  if v_det is null then v_det := 'O Gabinete pediu: ' || v_pedido; else v_det := case when v_trat ->> 'genero' = 'FEMININO' then 'A ' else 'O ' end || v_det; end if;
  if v_unit is not null and v_posto_unit is null then
    v_det := v_det || E'\nSobre a unidade: ' || (select short_name from iara.education_units where id = v_unit) || '.';
  end if;
  if v_perg is not null then v_det := v_det || E'\nPergunta feita ao Oráculo: «' || left(v_perg, 500) || '».'; end if;
  if v_falta is not null then v_det := v_det || E'\nO que o IARA não tem: ' || left(v_falta, 500); end if;
  v_det := v_det || E'\nResponda na nota da conclusão: a resposta volta para o Oráculo.';

  insert into iara.pendencias (origem, tipo, chave, titulo, detalhe, papel, unit_id, setor_id, prazo, atribuida_por, atribuida_por_label, is_demo)
  values ('ATRIBUIDA', 'DEMANDA_PREFEITO', 'PREF:' || gen_random_uuid(), left((v_trat ->> 'demanda') || ': ' || v_pedido, 140), left(v_det, 2000),
          a.papel, v_posto_unit, v_setor, iara.oraculo_prazo_uteis(2), iara.current_user_id(), (v_trat ->> 'gabinete') || ' · Oráculo', iara.demo_mode())
  returning * into x;
  insert into iara.pend_eventos (pendencia_id, tipo, texto, autor, autor_label, is_demo)
  values (x.id, 'CRIADA', v_pedido, iara.current_user_id(), (v_trat ->> 'gabinete') || ' · Oráculo', iara.demo_mode());
  perform iara.audit_event('ORACULO_DEMANDA', 'pendencia', x.id::text, x.unit_id, format('Demanda enviada a %s: %s', a.rotulo, left(v_pedido, 200)));
  return iara.oraculo_demanda_json(x) || jsonb_build_object('ja_existia', false);
end $$;

-- p: situacao (ABERTAS, RESPONDIDAS, TODAS)
create or replace function api.oraculo_demandas(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_sit text := upper(coalesce(nullif(p ->> 'situacao', ''), 'TODAS'));
begin
  perform iara.require_perm('oraculo.prefeito');
  return (
    with d as (select * from iara.pendencias where tipo = 'DEMANDA_PREFEITO' and (situacao = 'ABERTA' or coalesce(concluida_em, criada_em) > now() - interval '120 days'))
    select jsonb_build_object(
      'resumo', jsonb_build_object(
        'abertas', (select count(*) from d where situacao = 'ABERTA'),
        'atrasadas', (select count(*) from d where situacao = 'ABERTA' and prazo < now()),
        'respondidas_7_dias', (select count(*) from d where situacao = 'CONCLUIDA' and concluida_em > now() - interval '7 days')),
      'demandas', (select coalesce(jsonb_agg(iara.oraculo_demanda_json(x) order by case when x.situacao = 'ABERTA' then 0 else 1 end, x.prazo, x.concluida_em desc), '[]')
                   from (select * from d
                         where case v_sit when 'ABERTAS' then situacao = 'ABERTA' when 'RESPONDIDAS' then situacao = 'CONCLUIDA' else true end
                         order by case when situacao = 'ABERTA' then 0 else 1 end, coalesce(concluida_em, criada_em) desc limit 40) x)));
end $$;

-- p: numero (os 8 primeiros caracteres) ou id, texto (o recado do Prefeito)
create or replace function api.oraculo_demanda_cobrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ref text := upper(btrim(coalesce(p ->> 'numero', p ->> 'id', '')));
  v_txt text := nullif(btrim(coalesce(p ->> 'texto', '')), '');
  v_trat jsonb := iara.oraculo_tratamento_de(iara.current_user_id());
  x iara.pendencias;
begin
  perform iara.require_perm('oraculo.prefeito');
  if length(v_ref) < 6 then raise exception 'Informe o número da demanda.' using errcode = '22023'; end if;
  select * into x from iara.pendencias where tipo = 'DEMANDA_PREFEITO' and upper(id::text) like v_ref || '%' order by criada_em desc limit 1;
  if x.id is null then raise exception 'Demanda % não encontrada.', v_ref using errcode = 'P0002'; end if;
  if x.situacao <> 'ABERTA' then return iara.oraculo_demanda_json(x) || jsonb_build_object('aviso', 'Esta demanda já foi encerrada.'); end if;
  insert into iara.pend_eventos (pendencia_id, tipo, texto, autor, autor_label, is_demo)
  values (x.id, 'COBRADA', coalesce(left(v_txt, 1000), 'Cobrou a resposta.'), iara.current_user_id(), (v_trat ->> 'gabinete') || ' · Oráculo', iara.demo_mode());
  perform iara.audit_event('ORACULO_DEMANDA_COBRADA', 'pendencia', x.id::text, x.unit_id, 'Cobrou a demanda: ' || left(x.titulo, 200));
  return iara.oraculo_demanda_json(x);
end $$;

-- 4. Na Central: demanda do Prefeito no topo e resposta obrigatória ----------------------------------------------------------------
create or replace function api.pend_minhas(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $function$
declare
  e record;
  v_sit text := coalesce(nullif(p ->> 'situacao', ''), 'ABERTAS');
  v_mod text := nullif(p ->> 'modulo', '');
  v jsonb;
begin
  perform iara.require_perm('pend.read');
  select * into e from iara.pend_eu();
  perform iara.pend_sincronizar_se_preciso(case when e.na_unidade then e.unit_id end);
  with minhas as materialized (
    select p.* from iara.pendencias p
    where iara.pend_minha(p.staff_id, p.papel, p.unit_id, e.papel, e.unit_id, e.staff_id, e.na_unidade)
      and (p.situacao = 'ABERTA' or p.concluida_em > now() - interval '30 days')),
  abertas as (select * from minhas where situacao = 'ABERTA')
  select jsonb_build_object(
    'eu', jsonb_build_object('nome', e.nome, 'papel', iara.pend_papel_rotulo(e.papel), 'chefia', e.chefia,
                             'unidade', (select short_name from iara.education_units where id = e.unit_id)),
    'resumo', jsonb_build_object(
      'abertas', (select count(*) from abertas),
      'atrasadas', (select count(*) from abertas where prazo < now()),
      'hoje', (select count(*) from abertas where prazo >= now() and (prazo at time zone 'America/Sao_Paulo')::date = iara.hoje_local()),
      'semana', (select count(*) from abertas where prazo >= now() and prazo < now() + interval '7 days'),
      'concluidas_7', (select count(*) from minhas where situacao = 'CONCLUIDA' and concluida_em > now() - interval '7 days'),
      'no_prazo_30', (select round(100.0 * count(*) filter (where concluida_em <= prazo) / nullif(count(*), 0)) from minhas
                      where situacao = 'CONCLUIDA' and prazo is not null),
      'do_prefeito', (select count(*) from abertas where tipo = 'DEMANDA_PREFEITO')),
    'por_modulo', (select coalesce(jsonb_agg(jsonb_build_object('modulo', modulo, 'abertas', n, 'atrasadas', a) order by a desc, n desc), '[]')
                   from (select t.modulo, count(*) n, count(*) filter (where m.prazo < now()) a from abertas m join iara.pend_tipos t on t.codigo = m.tipo group by t.modulo) z),
    -- a demanda do Prefeito vem antes de tudo; depois, atrasadas e por prazo
    'itens', (select coalesce(jsonb_agg(iara.pend_json(m) order by
                 case when m.situacao = 'ABERTA' and m.tipo = 'DEMANDA_PREFEITO' then 0 else 1 end,
                 case when m.situacao <> 'ABERTA' then 2 when m.prazo < now() then 0 else 1 end, m.prazo nulls last, m.concluida_em desc nulls last, m.criada_em), '[]')
              from (select m.* from minhas m join iara.pend_tipos t on t.codigo = m.tipo
                    where (v_mod is null or t.modulo = v_mod)
                      and case v_sit when 'ATRASADAS' then m.situacao = 'ABERTA' and m.prazo < now()
                                     when 'CONCLUIDAS' then m.situacao <> 'ABERTA'
                                     else m.situacao = 'ABERTA' end
                    order by case when m.tipo = 'DEMANDA_PREFEITO' then 0 else 1 end, m.prazo nulls last limit 300) m),
    'sincronizado_em', (select max(em) from iara.pend_sinc where escopo in ('*', coalesce(e.unit_id::text, '*'))))
  into v;
  return v;
end $function$;

create or replace function api.pend_concluir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $function$
declare
  e record;
  x iara.pendencias;
  v_nota text := nullif(btrim(coalesce(p ->> 'nota', '')), '');
begin
  perform iara.require_perm('pend.read');
  select * into e from iara.pend_eu();
  select * into x from iara.pendencias where id = nullif(p ->> 'id', '')::uuid for update;
  if not found or not iara.pend_minha(x.staff_id, x.papel, x.unit_id, e.papel, e.unit_id, e.staff_id, e.na_unidade) then
    raise exception 'Esta pendência não é sua.' using errcode = '42501'; end if;
  if x.situacao <> 'ABERTA' then raise exception 'A pendência já foi encerrada.' using errcode = '22023'; end if;
  if x.origem = 'AUTOMATICA' then
    raise exception 'Esta pendência se resolve na própria tela (%). Ela sai daqui sozinha quando estiver resolvida.', coalesce(x.rota, 'do módulo') using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(coalesce(x.checklist, '[]')) i where not coalesce((i ->> 'feito')::boolean, false)) then
    raise exception 'Marque todos os itens da lista de conferência antes de concluir.' using errcode = '22023';
  end if;
  -- a demanda do Prefeito só se conclui com a resposta, que volta para o Oráculo
  if x.tipo = 'DEMANDA_PREFEITO' and coalesce(length(v_nota), 0) < 10 then
    raise exception 'Escreva a resposta ao Prefeito na nota (ao menos 10 caracteres): ela volta para o Oráculo.' using errcode = '22023';
  end if;
  if length(v_nota) > 1000 then raise exception 'A nota pode ter até 1.000 caracteres.' using errcode = '22023'; end if;
  update iara.pendencias set situacao = 'CONCLUIDA', concluida_em = now(), concluida_por = iara.current_user_id(), concluida_por_label = iara.my_label(),
                             conclusao = v_nota
  where id = x.id returning * into x;
  insert into iara.pend_eventos (pendencia_id, tipo, texto, autor, autor_label, is_demo)
  values (x.id, 'CONCLUIDA', v_nota, iara.current_user_id(), iara.my_label(), iara.demo_mode());
  perform iara.audit_event('PENDENCIA_CONCLUIDA', 'pendencia', x.id::text, x.unit_id, format('Concluiu "%s"%s', x.titulo, case when x.prazo < now() then ' (fora do prazo)' else '' end));
  return iara.pend_json(x);
end $function$;

revoke all on function iara.oraculo_tratamento_de(uuid), iara.oraculo_areas(), iara.oraculo_prazo_uteis(integer), iara.oraculo_demanda_json(iara.pendencias) from public;

commit;
