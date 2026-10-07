-- IARA Educa — 056 · Sprint 3: almoxarifado completo
-- Catálogo único de produtos por categoria (alimentos, material pedagógico, limpeza, escritório, uniformes, equipamentos), estoque
-- compartilhado (almoxarifado central e unidades). Ciclo do v1.3 “falta de produto”: a unidade pede → o almoxarifado aprova (ajusta
-- quantidades) → separa e despacha a remessa (lotes que vencem primeiro saem primeiro) → a unidade confere e recebe (divergência com
-- motivo). Alimentos com lote e validade; frutas da agricultura familiar com entrega direta do fornecedor. Cobertura do estoque de
-- alimentos em dias, pelo consumo estimado das refeições servidas (o cardápio executado). Dados fictícios (is_demo); fornecedores
-- com nomes fictícios. Catálogo e regras oficiais na Q-24.
begin;

insert into iara.organizational_roles (code, tenant_id, name, short_name, description, scope_type, stage_filter, question, org_unit, is_persona, sort) values
  ('ALMOXARIFADO', 1, 'Almoxarifado central · SEDUC', 'Almoxarifado', 'Pedidos das unidades, aprovação, remessas, recebimento conferido, lotes e validade, cobertura de alimentos.',
   'NETWORK', null, 'Alguma escola vai ficar sem produto?', 'Gerência de Suprimentos e Almoxarifado', true, 17)
on conflict (code) do update set name = excluded.name, short_name = excluded.short_name, description = excluded.description,
  scope_type = excluded.scope_type, question = excluded.question, org_unit = excluded.org_unit, is_persona = excluded.is_persona, sort = excluded.sort;
insert into iara.permissions (code, description, is_sensitive) values
  ('almoxarifado.manage', 'Aprovar pedidos das unidades, despachar remessas e gerir o almoxarifado central', false)
on conflict (code) do update set description = excluded.description;
insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('ALMOXARIFADO', 'units.read'), ('ALMOXARIFADO', 'config.read'), ('ALMOXARIFADO', 'kpi.network'), ('ALMOXARIFADO', 'materiais.read'),
  ('ALMOXARIFADO', 'materiais.write'), ('ALMOXARIFADO', 'almoxarifado.manage'),
  ('SUPERINTENDENCIA', 'almoxarifado.manage'), ('NUTRICAO', 'almoxarifado.manage')
) v(r, p)
on conflict do nothing;

-- 1. Tabelas -------------------------------------------------------------------------------------------------------------------
create table if not exists iara.produtos (
  codigo text primary key,
  nome text not null,
  categoria text not null check (categoria in ('PEDAGOGICO', 'LIMPEZA', 'ESCRITORIO', 'ALIMENTO', 'UNIFORME', 'EQUIPAMENTO', 'MOBILIARIO', 'OUTRO')),
  unidade_medida text not null default 'unidade',
  controla_validade boolean not null default false,
  duravel boolean not null default false,
  entrega_direta boolean not null default false,
  per_capita jsonb not null default '{}',
  ativo boolean not null default true,
  is_demo boolean not null default true
);
create table if not exists iara.fornecedores (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  tipo text not null check (tipo in ('AGRICULTURA_FAMILIAR', 'DISTRIBUIDOR', 'FABRICANTE')),
  categorias text[] not null default '{}',
  ativo boolean not null default true,
  is_demo boolean not null default true
);
create table if not exists iara.estoque_lotes (
  id uuid primary key default gen_random_uuid(),
  material_id uuid not null references iara.materiais(id) on delete cascade,
  lote text not null,
  validade date,
  quantidade numeric(12, 2) not null check (quantidade >= 0),
  fornecedor_id uuid references iara.fornecedores(id) on delete set null,
  entrada_em timestamptz not null default now(),
  is_demo boolean not null default false
);
create index if not exists estoque_lotes_mat_idx on iara.estoque_lotes (material_id, validade) where quantidade > 0;
create sequence if not exists iara.pedido_seq;
create table if not exists iara.pedidos (
  id uuid primary key default gen_random_uuid(),
  numero text not null unique default ('PED-2026-' || lpad(nextval('iara.pedido_seq')::text, 5, '0')),
  unit_id integer not null references iara.education_units(id),
  origem text not null default 'ALMOXARIFADO' check (origem in ('ALMOXARIFADO', 'FORNECEDOR')),
  fornecedor_id uuid references iara.fornecedores(id) on delete set null,
  situacao text not null default 'ENVIADO' check (situacao in ('ENVIADO', 'APROVADO', 'EM_TRANSPORTE', 'RECEBIDO', 'RECEBIDO_PARCIAL', 'RECUSADO', 'CANCELADO')),
  prioridade text not null default 'NORMAL' check (prioridade in ('NORMAL', 'URGENTE')),
  justificativa text,
  solicitado_por_label text,
  solicitado_em timestamptz not null default now(),
  decidido_por_label text,
  decidido_em timestamptz,
  motivo_recusa text,
  despachado_em timestamptz,
  previsao_entrega date,
  recebido_em timestamptz,
  conferido_por_label text,
  is_demo boolean not null default false
);
create index if not exists pedidos_unit_idx on iara.pedidos (unit_id, solicitado_em desc);
create index if not exists pedidos_sit_idx on iara.pedidos (situacao);
create table if not exists iara.pedido_itens (
  id uuid primary key default gen_random_uuid(),
  pedido_id uuid not null references iara.pedidos(id) on delete cascade,
  produto_codigo text not null references iara.produtos(codigo),
  quantidade_pedida numeric(12, 2) not null check (quantidade_pedida > 0),
  quantidade_aprovada numeric(12, 2),
  quantidade_enviada numeric(12, 2),
  quantidade_recebida numeric(12, 2),
  lotes jsonb not null default '[]',
  divergencia text,
  is_demo boolean not null default false
);
create index if not exists pedido_itens_pedido_idx on iara.pedido_itens (pedido_id);

alter table iara.produtos enable row level security;
alter table iara.fornecedores enable row level security;
alter table iara.estoque_lotes enable row level security;
alter table iara.pedidos enable row level security;
alter table iara.pedido_itens enable row level security;

-- 2. Apoios -------------------------------------------------------------------------------------------------------------------
-- material de um produto numa unidade (null = almoxarifado central); cria se ainda não existir
create or replace function iara.material_do_produto(p_unit integer, p_codigo text) returns iara.materiais
language plpgsql security definer set search_path = iara, public
as $$
declare
  m iara.materiais;
  pr iara.produtos;
begin
  select * into m from iara.materiais where unit_id is not distinct from p_unit and codigo = p_codigo and ativo order by created_at limit 1;
  if m.id is null then
    select * into pr from iara.produtos where codigo = p_codigo;
    insert into iara.materiais (unit_id, codigo, nome, categoria, unidade_medida, quantidade, minimo, localizacao, atualizado_por_label)
    values (p_unit, pr.codigo, pr.nome, pr.categoria, pr.unidade_medida, 0, 0, case when p_unit is null then 'Almoxarifado central' else 'Almoxarifado' end, iara.my_label())
    returning * into m;
  end if;
  return m;
end $$;

-- saída de estoque: lotes que vencem primeiro saem primeiro (FEFO); devolve os lotes usados
create or replace function iara.estoque_baixar(p_material uuid, p_qtd numeric, p_motivo text) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  m iara.materiais;
  l record;
  v_resta numeric := p_qtd;
  v_tira numeric;
  v_usados jsonb := '[]';
begin
  select * into m from iara.materiais where id = p_material for update;
  if m.quantidade < p_qtd then raise exception 'Estoque insuficiente de % (% %).', m.nome, m.quantidade, m.unidade_medida using errcode = '22023'; end if;
  for l in select * from iara.estoque_lotes where material_id = m.id and quantidade > 0 order by validade nulls last, entrada_em for update loop
    exit when v_resta <= 0;
    v_tira := least(l.quantidade, v_resta);
    update iara.estoque_lotes set quantidade = quantidade - v_tira where id = l.id;
    v_usados := v_usados || jsonb_build_object('lote', l.lote, 'validade', l.validade, 'quantidade', v_tira);
    v_resta := v_resta - v_tira;
  end loop;
  update iara.materiais set quantidade = quantidade - p_qtd, atualizado_por_label = iara.my_label(), updated_at = now() where id = m.id;
  insert into iara.materiais_movimentos (material_id, tipo, quantidade, saldo, motivo, autor_label) values (m.id, 'SAIDA', p_qtd, m.quantidade - p_qtd, p_motivo, iara.my_label());
  return v_usados;
end $$;

create or replace function iara.estoque_entrar(p_material uuid, p_qtd numeric, p_motivo text, p_lote text, p_validade date, p_fornecedor uuid) returns void
language plpgsql security definer set search_path = iara, public
as $$
declare
  m iara.materiais;
begin
  select * into m from iara.materiais where id = p_material for update;
  update iara.materiais set quantidade = quantidade + p_qtd, atualizado_por_label = iara.my_label(), updated_at = now() where id = m.id;
  insert into iara.materiais_movimentos (material_id, tipo, quantidade, saldo, motivo, autor_label) values (m.id, 'ENTRADA', p_qtd, m.quantidade + p_qtd, p_motivo, iara.my_label());
  if p_lote is not null or p_validade is not null then
    insert into iara.estoque_lotes (material_id, lote, validade, quantidade, fornecedor_id) values (m.id, coalesce(p_lote, 'S/L'), p_validade, p_qtd, p_fornecedor);
  end if;
end $$;

-- consumo diário estimado de alimentos pela média das refeições servidas nos últimos 20 dias com registro
create or replace function iara.consumo_diario(p_unit integer, p_codigo text) returns numeric
language sql stable security definer set search_path = iara, public
as $$
  select round(coalesce(sum(z.media * coalesce((pr.per_capita ->> z.refeicao)::numeric, 0)), 0), 3)
  from iara.produtos pr,
       lateral (select r.refeicao, avg(r.quantidade) media from iara.refeicoes_servidas r
                where r.unit_id = p_unit and r.data >= (select min(d) from (select distinct data d from iara.refeicoes_servidas where unit_id = p_unit order by data desc limit 20) x)
                group by 1) z
  where pr.codigo = p_codigo
$$;

create or replace function iara.pedido_json(pe iara.pedidos, p_itens boolean default true) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', pe.id, 'numero', pe.numero, 'unit_id', pe.unit_id, 'unidade', u.short_name, 'origem', pe.origem,
      'fornecedor', (select nome from iara.fornecedores where id = pe.fornecedor_id), 'situacao', pe.situacao, 'prioridade', pe.prioridade,
      'justificativa', pe.justificativa, 'solicitado_por', pe.solicitado_por_label, 'solicitado_em', pe.solicitado_em, 'decidido_por', pe.decidido_por_label,
      'decidido_em', pe.decidido_em, 'motivo_recusa', pe.motivo_recusa, 'despachado_em', pe.despachado_em, 'previsao_entrega', pe.previsao_entrega,
      'recebido_em', pe.recebido_em, 'conferido_por', pe.conferido_por_label,
      'atrasado', pe.situacao = 'EM_TRANSPORTE' and pe.previsao_entrega < iara.hoje_local(),
      'categorias', (select coalesce(jsonb_agg(distinct pr.categoria), '[]') from iara.pedido_itens i join iara.produtos pr on pr.codigo = i.produto_codigo where i.pedido_id = pe.id),
      'n_itens', (select count(*) from iara.pedido_itens where pedido_id = pe.id), 'is_demo', pe.is_demo)
    || case when p_itens then jsonb_build_object('itens', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'codigo', i.produto_codigo, 'nome', pr.nome,
         'categoria', pr.categoria, 'unidade_medida', pr.unidade_medida, 'pedida', i.quantidade_pedida, 'aprovada', i.quantidade_aprovada, 'enviada', i.quantidade_enviada,
         'recebida', i.quantidade_recebida, 'lotes', i.lotes, 'divergencia', i.divergencia, 'controla_validade', pr.controla_validade,
         'saldo_central', (select quantidade from iara.materiais where unit_id is null and codigo = i.produto_codigo and ativo limit 1),
         'saldo_unidade', (select quantidade from iara.materiais where unit_id = pe.unit_id and codigo = i.produto_codigo and ativo limit 1))
         order by pr.categoria, pr.nome), '[]') from iara.pedido_itens i join iara.produtos pr on pr.codigo = i.produto_codigo where i.pedido_id = pe.id)) else '{}' end
  from iara.education_units u where u.id = pe.unit_id
$$;

-- 3. Catálogo e pedidos -------------------------------------------------------------------------------------------------------------
create or replace function api.produtos_catalogo(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
begin
  perform iara.require_perm('materiais.read');
  return (select coalesce(jsonb_agg(jsonb_build_object('codigo', pr.codigo, 'nome', pr.nome, 'categoria', pr.categoria, 'unidade_medida', pr.unidade_medida,
      'controla_validade', pr.controla_validade, 'entrega_direta', pr.entrega_direta,
      'saldo_central', (select quantidade from iara.materiais where unit_id is null and codigo = pr.codigo and ativo limit 1),
      'saldo_unidade', case when v_unit is not null then (select quantidade from iara.materiais where unit_id = v_unit and codigo = pr.codigo and ativo limit 1) end,
      'minimo_unidade', case when v_unit is not null then (select minimo from iara.materiais where unit_id = v_unit and codigo = pr.codigo and ativo limit 1) end)
      order by pr.categoria, pr.nome), '[]')
    from iara.produtos pr where pr.ativo and not pr.duravel);
end $$;

create or replace function api.pedido_criar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  x record;
  pe iara.pedidos;
  v_direta boolean;
  v_n integer := 0;
begin
  perform iara.require_perm('materiais.write');
  if v_unit is null or not iara.can_access_unit(v_unit) then raise exception 'Escolha a unidade do pedido.' using errcode = '22023'; end if;
  if jsonb_array_length(coalesce(p -> 'itens', '[]')) = 0 then raise exception 'Inclua pelo menos um produto.' using errcode = '22023'; end if;
  select bool_and(pr.entrega_direta) into v_direta from jsonb_array_elements(p -> 'itens') i join iara.produtos pr on pr.codigo = i ->> 'codigo';
  if v_direta is null then raise exception 'Produto fora do catálogo.' using errcode = '22023'; end if;
  if exists (select 1 from jsonb_array_elements(p -> 'itens') i join iara.produtos pr on pr.codigo = i ->> 'codigo' where pr.entrega_direta <> v_direta) then
    raise exception 'Frutas e hortaliças da agricultura familiar vão num pedido separado (entrega direta do fornecedor).' using errcode = '22023';
  end if;
  insert into iara.pedidos (unit_id, origem, fornecedor_id, prioridade, justificativa, solicitado_por_label)
  values (v_unit, case when v_direta then 'FORNECEDOR' else 'ALMOXARIFADO' end,
          case when v_direta then (select id from iara.fornecedores where tipo = 'AGRICULTURA_FAMILIAR' and ativo order by nome limit 1) end,
          case when p ->> 'prioridade' = 'URGENTE' then 'URGENTE' else 'NORMAL' end, nullif(btrim(coalesce(p ->> 'justificativa', '')), ''), iara.my_label())
  returning * into pe;
  if pe.prioridade = 'URGENTE' and coalesce(length(pe.justificativa), 0) < 10 then raise exception 'Pedido urgente precisa de justificativa.' using errcode = '22023'; end if;
  for x in select i ->> 'codigo' codigo, (i ->> 'quantidade')::numeric q from jsonb_array_elements(p -> 'itens') i loop
    if x.q is null or x.q <= 0 then raise exception 'Quantidade inválida.' using errcode = '22023'; end if;
    if not exists (select 1 from iara.produtos where codigo = x.codigo and ativo and not duravel) then raise exception 'Produto fora do catálogo: %.', x.codigo using errcode = '22023'; end if;
    insert into iara.pedido_itens (pedido_id, produto_codigo, quantidade_pedida) values (pe.id, x.codigo, x.q);
    v_n := v_n + 1;
  end loop;
  perform iara.audit_event('PEDIDO_MATERIAL', 'pedido', pe.id::text, v_unit, format('Pedido %s enviado (%s item(ns)).', pe.numero, v_n));
  return iara.pedido_json(pe);
end $$;

create or replace function api.pedidos_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_sit text := nullif(p ->> 'situacao', '');
begin
  perform iara.require_perm('materiais.read');
  return (with base as (
      select pe from iara.pedidos pe where (v_unit is null or pe.unit_id = v_unit) and iara.can_access_unit(pe.unit_id)
        and (nullif(p ->> 'busca', '') is null or pe.numero ilike '%' || btrim(p ->> 'busca') || '%'))
    select jsonb_build_object(
      'contagem', (select coalesce(jsonb_object_agg(s, n), '{}') from (select (b.pe).situacao s, count(*) n from base b group by 1) z),
      'atrasados', (select count(*) from base b where (b.pe).situacao = 'EM_TRANSPORTE' and (b.pe).previsao_entrega < iara.hoje_local()),
      'pode_gerir', iara.has_perm('almoxarifado.manage'), 'pode_pedir', iara.has_perm('materiais.write') and (v_unit is not null),
      'itens', (select coalesce(jsonb_agg(iara.pedido_json(x.pe, false) order by x.ord), '[]') from (
          select b.pe, row_number() over (order by case (b.pe).situacao when 'ENVIADO' then 0 when 'APROVADO' then 1 when 'EM_TRANSPORTE' then 2 else 3 end,
                                                  (b.pe).prioridade = 'URGENTE' desc, (b.pe).solicitado_em desc) ord
          from base b
          where v_sit is null or (v_sit = 'ABERTOS' and (b.pe).situacao in ('ENVIADO', 'APROVADO', 'EM_TRANSPORTE')) or (v_sit = 'ATRASADOS' and (b.pe).situacao = 'EM_TRANSPORTE' and (b.pe).previsao_entrega < iara.hoje_local())
             or (b.pe).situacao = v_sit
          order by ord limit 200) x)));
end $$;

create or replace function api.pedido_detalhe(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  pe iara.pedidos;
begin
  perform iara.require_perm('materiais.read');
  select * into pe from iara.pedidos where id = (p ->> 'id')::uuid;
  if pe.id is null or not iara.can_access_unit(pe.unit_id) then raise exception 'Pedido não encontrado.' using errcode = 'P0002'; end if;
  return iara.pedido_json(pe) || jsonb_build_object('pode_gerir', iara.has_perm('almoxarifado.manage'),
    'pode_receber', iara.has_perm('materiais.write') and iara.my_scope() = 'UNIT' and pe.situacao = 'EM_TRANSPORTE',
    'pode_cancelar', iara.has_perm('materiais.write') and iara.my_scope() = 'UNIT' and pe.situacao = 'ENVIADO');
end $$;

create or replace function api.pedido_decidir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  pe iara.pedidos;
  x record;
begin
  perform iara.require_perm('almoxarifado.manage');
  select * into pe from iara.pedidos where id = (p ->> 'id')::uuid for update;
  if pe.id is null then raise exception 'Pedido não encontrado.' using errcode = 'P0002'; end if;
  if pe.situacao <> 'ENVIADO' then raise exception 'Este pedido já foi decidido.' using errcode = '22023'; end if;
  if not coalesce((p ->> 'aprovar')::boolean, false) then
    if length(btrim(coalesce(p ->> 'motivo', ''))) < 10 then raise exception 'Informe o motivo da recusa para a unidade.' using errcode = '22023'; end if;
    update iara.pedidos set situacao = 'RECUSADO', motivo_recusa = btrim(p ->> 'motivo'), decidido_por_label = iara.my_label(), decidido_em = now() where id = pe.id returning * into pe;
  else
    for x in select (i ->> 'id')::uuid id, (i ->> 'aprovada')::numeric q from jsonb_array_elements(coalesce(p -> 'itens', '[]')) i loop
      if x.q is null or x.q < 0 then raise exception 'Quantidade aprovada inválida.' using errcode = '22023'; end if;
      update iara.pedido_itens set quantidade_aprovada = x.q where id = x.id and pedido_id = pe.id;
    end loop;
    update iara.pedido_itens set quantidade_aprovada = quantidade_pedida where pedido_id = pe.id and quantidade_aprovada is null;
    if not exists (select 1 from iara.pedido_itens where pedido_id = pe.id and quantidade_aprovada > 0) then raise exception 'Aprove pelo menos um item (ou recuse o pedido).' using errcode = '22023'; end if;
    update iara.pedidos set situacao = 'APROVADO', decidido_por_label = iara.my_label(), decidido_em = now(),
           motivo_recusa = nullif(btrim(coalesce(p ->> 'motivo', '')), '') where id = pe.id returning * into pe;
  end if;
  perform iara.audit_event('PEDIDO_DECIDIDO', 'pedido', pe.id::text, pe.unit_id, format('Pedido %s %s.', pe.numero, lower(pe.situacao)));
  return api.pedido_detalhe(jsonb_build_object('id', pe.id));
end $$;

create or replace function api.pedido_despachar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  pe iara.pedidos;
  i record;
  m iara.materiais;
  v_lotes jsonb;
  v_falta text;
begin
  perform iara.require_perm('almoxarifado.manage');
  select * into pe from iara.pedidos where id = (p ->> 'id')::uuid for update;
  if pe.id is null then raise exception 'Pedido não encontrado.' using errcode = 'P0002'; end if;
  if pe.situacao <> 'APROVADO' then raise exception 'Só pedido aprovado sai para entrega.' using errcode = '22023'; end if;
  if pe.origem = 'ALMOXARIFADO' then
    select string_agg(pr.nome || ' (tem ' || coalesce(mc.quantidade, 0) || ', pedido ' || it.quantidade_aprovada || ')', '; ') into v_falta
    from iara.pedido_itens it join iara.produtos pr on pr.codigo = it.produto_codigo
    left join iara.materiais mc on mc.unit_id is null and mc.codigo = it.produto_codigo and mc.ativo
    where it.pedido_id = pe.id and it.quantidade_aprovada > coalesce(mc.quantidade, 0);
    if v_falta is not null then raise exception 'Estoque central insuficiente: %. Ajuste a aprovação.', v_falta using errcode = '22023'; end if;
    for i in select it.* from iara.pedido_itens it where it.pedido_id = pe.id and it.quantidade_aprovada > 0 loop
      m := iara.material_do_produto(null, i.produto_codigo);
      v_lotes := iara.estoque_baixar(m.id, i.quantidade_aprovada, 'Remessa ' || pe.numero || ' para ' || (select short_name from iara.education_units where id = pe.unit_id));
      update iara.pedido_itens set quantidade_enviada = i.quantidade_aprovada, lotes = v_lotes where id = i.id;
    end loop;
  else
    -- entrega direta do fornecedor: o lote vem do fornecedor
    update iara.pedido_itens set quantidade_enviada = quantidade_aprovada,
           lotes = jsonb_build_array(jsonb_build_object('lote', 'AF-' || to_char(iara.hoje_local(), 'YYMMDD'), 'validade', iara.hoje_local() + 7, 'quantidade', quantidade_aprovada))
    where pedido_id = pe.id and quantidade_aprovada > 0;
  end if;
  update iara.pedidos set situacao = 'EM_TRANSPORTE', despachado_em = now(),
         previsao_entrega = coalesce(nullif(p ->> 'previsao_entrega', '')::date, iara.hoje_local() + case when pe.prioridade = 'URGENTE' then 1 else 3 end)
  where id = pe.id returning * into pe;
  perform iara.audit_event('PEDIDO_DESPACHADO', 'pedido', pe.id::text, pe.unit_id, format('Remessa do pedido %s despachada.', pe.numero));
  return api.pedido_detalhe(jsonb_build_object('id', pe.id));
end $$;

create or replace function api.pedido_receber(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  pe iara.pedidos;
  i record;
  x record;
  m iara.materiais;
  l jsonb;
  v_div boolean := false;
  v_rec numeric;
begin
  perform iara.require_perm('materiais.write');
  select * into pe from iara.pedidos where id = (p ->> 'id')::uuid for update;
  if pe.id is null or iara.my_scope() <> 'UNIT' or pe.unit_id <> iara.my_unit() then raise exception 'Pedido não encontrado.' using errcode = 'P0002'; end if;
  if pe.situacao <> 'EM_TRANSPORTE' then raise exception 'O pedido não está em transporte.' using errcode = '22023'; end if;
  for x in select (j ->> 'id')::uuid id, (j ->> 'recebida')::numeric q, nullif(btrim(coalesce(j ->> 'divergencia', '')), '') d from jsonb_array_elements(coalesce(p -> 'itens', '[]')) j loop
    update iara.pedido_itens set quantidade_recebida = x.q, divergencia = x.d where id = x.id and pedido_id = pe.id;
  end loop;
  update iara.pedido_itens set quantidade_recebida = quantidade_enviada where pedido_id = pe.id and quantidade_recebida is null;
  for i in select it.* from iara.pedido_itens it where it.pedido_id = pe.id and coalesce(it.quantidade_enviada, 0) > 0 loop
    if i.quantidade_recebida < 0 or i.quantidade_recebida > i.quantidade_enviada * 2 then raise exception 'Quantidade recebida inválida.' using errcode = '22023'; end if;
    if i.quantidade_recebida <> i.quantidade_enviada then
      if coalesce(length(i.divergencia), 0) < 5 then raise exception 'Explique a diferença no item %.', i.produto_codigo using errcode = '22023'; end if;
      v_div := true;
    end if;
    m := iara.material_do_produto(pe.unit_id, i.produto_codigo);
    -- entrada pelos lotes enviados, proporcional ao recebido
    v_rec := i.quantidade_recebida;
    for l in select * from jsonb_array_elements(i.lotes) loop
      exit when v_rec <= 0;
      perform iara.estoque_entrar(m.id, least((l ->> 'quantidade')::numeric, v_rec), 'Recebimento ' || pe.numero, l ->> 'lote', nullif(l ->> 'validade', '')::date, pe.fornecedor_id);
      v_rec := v_rec - least((l ->> 'quantidade')::numeric, v_rec);
    end loop;
    if v_rec > 0 then perform iara.estoque_entrar(m.id, v_rec, 'Recebimento ' || pe.numero, null, null, pe.fornecedor_id); end if;
  end loop;
  update iara.pedidos set situacao = case when v_div then 'RECEBIDO_PARCIAL' else 'RECEBIDO' end, recebido_em = now(), conferido_por_label = iara.my_label()
  where id = pe.id returning * into pe;
  perform iara.audit_event('PEDIDO_RECEBIDO', 'pedido', pe.id::text, pe.unit_id, format('Pedido %s recebido%s.', pe.numero, case when v_div then ' com divergência' else '' end));
  return api.pedido_detalhe(jsonb_build_object('id', pe.id));
end $$;

create or replace function api.pedido_cancelar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  pe iara.pedidos;
begin
  perform iara.require_perm('materiais.write');
  update iara.pedidos set situacao = 'CANCELADO', motivo_recusa = nullif(btrim(coalesce(p ->> 'motivo', '')), '')
  where id = (p ->> 'id')::uuid and situacao = 'ENVIADO' and iara.can_access_unit(unit_id) returning * into pe;
  if pe.id is null then raise exception 'Só dá para cancelar pedido ainda não decidido.' using errcode = '22023'; end if;
  perform iara.audit_event('PEDIDO_CANCELADO', 'pedido', pe.id::text, pe.unit_id, format('Pedido %s cancelado pela unidade.', pe.numero));
  return jsonb_build_object('ok', true);
end $$;

-- 4. Validade, cobertura e painel -------------------------------------------------------------------------------------------------
create or replace function api.estoque_validade(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_central boolean := coalesce((p ->> 'central')::boolean, false);
  v_dias integer := coalesce(nullif(p ->> 'dias', '')::int, 30);
  v_hoje date := iara.hoje_local();
begin
  perform iara.require_perm('materiais.read');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'lote', l.lote, 'validade', l.validade, 'quantidade', l.quantidade, 'material_id', m.id,
      'nome', m.nome, 'unidade_medida', m.unidade_medida, 'unidade', coalesce(u.short_name, 'Almoxarifado central'), 'unit_id', m.unit_id,
      'dias', l.validade - v_hoje, 'vencido', l.validade < v_hoje, 'is_demo', l.is_demo) order by l.validade, u.short_name), '[]')
    from (select l2.* from iara.estoque_lotes l2 join iara.materiais m2 on m2.id = l2.material_id
          where l2.quantidade > 0 and l2.validade <= v_hoje + v_dias and m2.ativo
            and (case when iara.my_scope() = 'UNIT' then m2.unit_id = v_unit when v_central then m2.unit_id is null when v_unit is not null then m2.unit_id = v_unit else true end)
          order by l2.validade limit 300) l
    join iara.materiais m on m.id = l.material_id left join iara.education_units u on u.id = m.unit_id);
end $$;

create or replace function api.lote_descartar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  l iara.estoque_lotes;
  m iara.materiais;
  v_motivo text := btrim(coalesce(p ->> 'motivo', ''));
begin
  perform iara.require_perm('materiais.write');
  select * into l from iara.estoque_lotes where id = (p ->> 'id')::uuid for update;
  select * into m from iara.materiais where id = l.material_id for update;
  if l.id is null or (iara.my_scope() = 'UNIT' and m.unit_id is distinct from iara.my_unit()) or (m.unit_id is null and not iara.has_perm('almoxarifado.manage')) then
    raise exception 'Lote não encontrado.' using errcode = 'P0002';
  end if;
  if length(v_motivo) < 5 then raise exception 'Informe o motivo do descarte.' using errcode = '22023'; end if;
  update iara.estoque_lotes set quantidade = 0 where id = l.id;
  update iara.materiais set quantidade = greatest(quantidade - l.quantidade, 0), atualizado_por_label = iara.my_label(), updated_at = now() where id = m.id;
  insert into iara.materiais_movimentos (material_id, tipo, quantidade, saldo, motivo, autor_label)
  values (m.id, 'SAIDA', l.quantidade, greatest(m.quantidade - l.quantidade, 0), 'Descarte do lote ' || l.lote || ': ' || v_motivo, iara.my_label());
  perform iara.audit_event('LOTE_DESCARTADO', 'material', m.id::text, m.unit_id, format('Lote %s descartado (%s %s): %s.', l.lote, l.quantidade, m.unidade_medida, left(v_motivo, 100)));
  return jsonb_build_object('ok', true);
end $$;

create or replace function api.cobertura_alimentos(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
begin
  perform iara.require_perm('materiais.read');
  if v_unit is null then raise exception 'Escolha a unidade.' using errcode = '22023'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('codigo', pr.codigo, 'nome', pr.nome, 'unidade_medida', pr.unidade_medida, 'saldo', coalesce(m.quantidade, 0),
      'consumo_dia', c.c, 'dias', case when c.c > 0 then round(coalesce(m.quantidade, 0) / c.c, 1) end,
      'proxima_validade', (select min(l.validade) from iara.estoque_lotes l where l.material_id = m.id and l.quantidade > 0))
      order by case when c.c > 0 then coalesce(m.quantidade, 0) / c.c end nulls last), '[]')
    from iara.produtos pr cross join lateral (select iara.consumo_diario(v_unit, pr.codigo) c) c
    left join iara.materiais m on m.unit_id = v_unit and m.codigo = pr.codigo and m.ativo
    where pr.categoria = 'ALIMENTO' and pr.ativo);
end $$;

create or replace function api.almoxarifado_painel(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_hoje date := iara.hoje_local();
begin
  perform iara.require_perm('materiais.read');
  return (with pe as (select * from iara.pedidos where (v_unit is null or unit_id = v_unit) and iara.can_access_unit(unit_id)),
    lt as (select l.*, m.unit_id from iara.estoque_lotes l join iara.materiais m on m.id = l.material_id
           where l.quantidade > 0 and m.ativo and (v_unit is null or m.unit_id = v_unit))
    select jsonb_build_object(
      'unidade', (select name from iara.education_units where id = v_unit),
      'pedidos', (select coalesce(jsonb_object_agg(situacao, n), '{}') from (select situacao, count(*) n from pe group by 1) z),
      'aguardando_aprovacao', (select count(*) from pe where situacao = 'ENVIADO'),
      'urgentes', (select count(*) from pe where situacao in ('ENVIADO', 'APROVADO') and prioridade = 'URGENTE'),
      'atrasados', (select count(*) from pe where situacao = 'EM_TRANSPORTE' and previsao_entrega < v_hoje),
      'divergencias_60d', (select count(*) from pe where situacao = 'RECEBIDO_PARCIAL' and recebido_em >= now() - interval '60 days'),
      'tempo_medio_dias', (select round(avg(extract(epoch from recebido_em - solicitado_em) / 86400)::numeric, 1) from pe
                           where recebido_em >= now() - interval '60 days'),
      'lotes_vencendo_30d', (select count(*) from lt where validade between v_hoje and v_hoje + 30),
      'lotes_vencidos', (select count(*) from lt where validade < v_hoje),
      'central_abaixo_minimo', case when v_unit is null then (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'nome', m.nome, 'quantidade', m.quantidade,
          'minimo', m.minimo, 'unidade_medida', m.unidade_medida) order by m.quantidade / nullif(m.minimo, 0)), '[]')
          from iara.materiais m where m.unit_id is null and m.ativo and m.quantidade < m.minimo) end,
      -- unidades com algum alimento para menos de 7 dias (pelo consumo das refeições servidas)
      'cobertura_critica', case when v_unit is null and iara.has_perm('almoxarifado.manage') then (select coalesce(jsonb_agg(jsonb_build_object('unit_id', z.unit_id,
          'unidade', u.short_name, 'produto', z.nome, 'dias', z.dias) order by z.dias), '[]')
          from (select distinct on (m.unit_id) m.unit_id, m.nome, round(m.quantidade / iara.consumo_diario(m.unit_id, m.codigo), 1) dias
                from iara.materiais m join iara.produtos pr on pr.codigo = m.codigo and pr.categoria = 'ALIMENTO' and pr.per_capita <> '{}'
                where m.unit_id is not null and m.ativo and m.is_demo is not null and iara.consumo_diario(m.unit_id, m.codigo) > 0
                  and m.quantidade / iara.consumo_diario(m.unit_id, m.codigo) < 7
                order by m.unit_id, m.quantidade / iara.consumo_diario(m.unit_id, m.codigo)) z
          join iara.education_units u on u.id = z.unit_id) end,
      'pode_gerir', iara.has_perm('almoxarifado.manage')));
end $$;

-- detalhe do material com os lotes; movimento manual respeita os lotes (saída FEFO, entrada com lote e validade)
create or replace function api.material_detalhe(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  m iara.materiais;
begin
  perform iara.require_perm('materiais.read');
  select * into m from iara.materiais where id = (p ->> 'id')::uuid;
  if m.id is null or (iara.my_scope() = 'UNIT' and m.unit_id is distinct from iara.my_unit()) then raise exception 'Material não encontrado.' using errcode = 'P0002'; end if;
  return iara.material_json(m) || jsonb_build_object(
    'controla_validade', coalesce((select controla_validade from iara.produtos where codigo = m.codigo), false),
    'consumo_dia', case when m.unit_id is not null and m.categoria = 'ALIMENTO' then iara.consumo_diario(m.unit_id, m.codigo) end,
    'lotes', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'lote', l.lote, 'validade', l.validade, 'quantidade', l.quantidade,
        'vencido', l.validade < iara.hoje_local(), 'dias', l.validade - iara.hoje_local(), 'fornecedor', (select nome from iara.fornecedores where id = l.fornecedor_id))
        order by l.validade nulls last), '[]') from iara.estoque_lotes l where l.material_id = m.id and l.quantidade > 0),
    'movimentos', (select coalesce(jsonb_agg(jsonb_build_object('tipo', v.tipo, 'quantidade', v.quantidade,
           'saldo', v.saldo, 'motivo', v.motivo, 'autor', v.autor_label, 'em', v.created_at) order by v.created_at desc), '[]')
         from (select * from iara.materiais_movimentos where material_id = m.id order by created_at desc limit 50) v));
end $$;

create or replace function api.material_movimentar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  m iara.materiais;
  v_tipo text := p ->> 'tipo';
  v_q numeric := nullif(p ->> 'quantidade', '')::numeric;
  v_saldo numeric;
  v_lotes boolean;
begin
  perform iara.require_perm('materiais.write');
  select * into m from iara.materiais where id = (p ->> 'id')::uuid for update;
  if m.id is null or (iara.my_scope() = 'UNIT' and m.unit_id is distinct from iara.my_unit()) then raise exception 'Material fora do seu escopo.' using errcode = '42501'; end if;
  if v_tipo not in ('ENTRADA', 'SAIDA', 'AJUSTE') or v_q is null or v_q < 0 or (v_tipo <> 'AJUSTE' and v_q = 0) then
    raise exception 'Movimento inválido.' using errcode = '22023';
  end if;
  v_saldo := case v_tipo when 'ENTRADA' then m.quantidade + v_q when 'SAIDA' then m.quantidade - v_q else v_q end;
  if v_saldo < 0 then raise exception 'Saída maior que o estoque (% %).', m.quantidade, m.unidade_medida using errcode = '22023'; end if;
  if v_tipo = 'AJUSTE' and length(btrim(coalesce(p ->> 'motivo', ''))) < 5 then raise exception 'Ajuste de inventário pede o motivo.' using errcode = '22023'; end if;
  v_lotes := coalesce((select controla_validade from iara.produtos where codigo = m.codigo), false);
  if v_lotes and v_tipo = 'ENTRADA' and nullif(p ->> 'validade', '') is null then raise exception 'Alimento: informe o lote e a validade.' using errcode = '22023'; end if;
  if v_tipo = 'SAIDA' or (v_tipo = 'AJUSTE' and v_saldo < m.quantidade) then
    perform iara.estoque_baixar(m.id, m.quantidade - v_saldo, coalesce(nullif(btrim(coalesce(p ->> 'motivo', '')), ''), case when v_tipo = 'AJUSTE' then 'Ajuste de inventário' end));
    if v_tipo = 'AJUSTE' then update iara.materiais_movimentos set tipo = 'AJUSTE', quantidade = v_saldo - m.quantidade
                              where id = (select id from iara.materiais_movimentos where material_id = m.id order by created_at desc limit 1); end if;
  else
    perform iara.estoque_entrar(m.id, v_saldo - m.quantidade, coalesce(nullif(btrim(coalesce(p ->> 'motivo', '')), ''), case when v_tipo = 'AJUSTE' then 'Ajuste de inventário' end),
                                nullif(btrim(coalesce(p ->> 'lote', '')), ''), nullif(p ->> 'validade', '')::date, null);
    if v_tipo = 'AJUSTE' then update iara.materiais_movimentos set tipo = 'AJUSTE'
                              where id = (select id from iara.materiais_movimentos where material_id = m.id order by created_at desc limit 1); end if;
  end if;
  return api.material_detalhe(jsonb_build_object('id', m.id));
end $$;

-- 5. Demonstração -------------------------------------------------------------------------------------------------------------------
create or replace function iara.demo_gerar_almoxarifado() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_hoje date := iara.hoje_local();
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.pedidos where is_demo;
  -- numeração recomeça depois do último pedido que ficou (os lançados ao vivo não são tocados)
  perform setval('iara.pedido_seq', coalesce((select max(substring(numero from 10)::int) from iara.pedidos), 0) + 1, false);
  delete from iara.estoque_lotes where is_demo;
  delete from iara.materiais where is_demo and categoria = 'ALIMENTO';
  delete from iara.fornecedores where is_demo;
  insert into iara.produtos (codigo, nome, categoria, unidade_medida, controla_validade, duravel, entrega_direta, per_capita, is_demo) values
    ('ALI-001', 'Arroz tipo 1 (5 kg)', 'ALIMENTO', 'pacote', true, false, false, '{"ALMOCO": 0.01, "JANTAR": 0.01}', true),
    ('ALI-002', 'Feijão carioca (1 kg)', 'ALIMENTO', 'pacote', true, false, false, '{"ALMOCO": 0.025, "JANTAR": 0.025}', true),
    ('ALI-003', 'Macarrão parafuso (500 g)', 'ALIMENTO', 'pacote', true, false, false, '{"ALMOCO": 0.016}', true),
    ('ALI-004', 'Óleo de soja (900 ml)', 'ALIMENTO', 'frasco', true, false, false, '{"ALMOCO": 0.004, "JANTAR": 0.004}', true),
    ('ALI-005', 'Leite em pó integral (400 g)', 'ALIMENTO', 'pacote', true, false, false, '{"DESJEJUM": 0.05, "LANCHE": 0.03}', true),
    ('ALI-006', 'Aveia em flocos (500 g)', 'ALIMENTO', 'pacote', true, false, false, '{"DESJEJUM": 0.02, "LANCHE": 0.01}', true),
    ('ALI-007', 'Fubá (1 kg)', 'ALIMENTO', 'pacote', true, false, false, '{"LANCHE": 0.008}', true),
    ('ALI-008', 'Extrato de tomate (340 g)', 'ALIMENTO', 'lata', true, false, false, '{"ALMOCO": 0.012}', true),
    ('ALI-009', 'Sal refinado (1 kg)', 'ALIMENTO', 'pacote', true, false, false, '{"ALMOCO": 0.0015}', true),
    ('ALI-010', 'Frutas da agricultura familiar (kg)', 'ALIMENTO', 'kg', true, false, true, '{"LANCHE": 0.09, "DESJEJUM": 0.05}', true)
  on conflict (codigo) do update set nome = excluded.nome, per_capita = excluded.per_capita, controla_validade = excluded.controla_validade, entrega_direta = excluded.entrega_direta;
  insert into iara.produtos (codigo, nome, categoria, unidade_medida, duravel, is_demo)
  select distinct on (m.codigo) m.codigo, m.nome, m.categoria, m.unidade_medida, m.categoria in ('EQUIPAMENTO', 'MOBILIARIO'), true
  from iara.materiais m where m.is_demo and m.codigo is not null and m.categoria <> 'ALIMENTO'
  on conflict (codigo) do nothing;
  insert into iara.fornecedores (nome, tipo, categorias, is_demo) values
    ('Cooperativa da Agricultura Familiar Exemplo (demonstração)', 'AGRICULTURA_FAMILIAR', '{ALIMENTO}', true),
    ('Distribuidora de Alimentos Exemplo Ltda. (demonstração)', 'DISTRIBUIDOR', '{ALIMENTO}', true),
    ('Papelaria Atacadista Exemplo (demonstração)', 'DISTRIBUIDOR', '{PEDAGOGICO,ESCRITORIO}', true),
    ('Confecções Exemplo (demonstração)', 'FABRICANTE', '{UNIFORME}', true),
    ('Produtos de Limpeza Exemplo (demonstração)', 'DISTRIBUIDOR', '{LIMPEZA}', true);

  -- almoxarifado central: todo o catálogo de consumo (alguns itens abaixo do mínimo)
  delete from iara.materiais where is_demo and unit_id is null;
  insert into iara.materiais (unit_id, codigo, nome, categoria, unidade_medida, quantidade, minimo, localizacao, atualizado_por_label, is_demo)
  select null, pr.codigo, pr.nome, pr.categoria, pr.unidade_medida,
         case when pr.codigo in ('LIM-002', 'ALI-002', 'PED-003') then 120 + abs(hashtext(pr.codigo)) % 80 else 900 + abs(hashtext(pr.codigo)) % 2600 end,
         case when pr.codigo in ('LIM-002', 'ALI-002', 'PED-003') then 500 else 300 end,
         case when pr.categoria = 'ALIMENTO' then 'Almoxarifado da alimentação' else 'Almoxarifado central' end, 'Almoxarifado SEDUC (demonstração)', true
  from iara.produtos pr where not pr.duravel and not pr.entrega_direta;
  -- alimentos nas unidades: de 4 a 45 dias de consumo; o mínimo cobre uma semana
  insert into iara.materiais (unit_id, codigo, nome, categoria, unidade_medida, quantidade, minimo, localizacao, atualizado_por_label, is_demo)
  select u.id, pr.codigo, pr.nome, pr.categoria, pr.unidade_medida,
         ceil(c.c * (case when abs(hashtext(u.id::text || pr.codigo)) % 100 < 6 then 3 + abs(hashtext(u.id::text || pr.codigo)) % 4
                          else 9 + abs(hashtext(u.id::text || pr.codigo)) % 36 end)), ceil(c.c * 7), 'Despensa da cozinha', 'Cozinha da unidade (demonstração)', true
  from iara.education_units u cross join iara.produtos pr cross join lateral (select iara.consumo_diario(u.id, pr.codigo) c) c
  where pr.categoria = 'ALIMENTO' and c.c > 0 and u.status = 'ATIVA';
  -- lotes: central e unidades (a maioria longe do vencimento; alguns vencendo e poucos vencidos)
  insert into iara.estoque_lotes (material_id, lote, validade, quantidade, fornecedor_id, entrada_em, is_demo)
  select m.id, 'L' || to_char(v_hoje - (z.k * 25), 'YYMM') || '-' || (abs(hashtext(m.id::text || z.k)) % 900 + 100),
         case when pr.entrega_direta then v_hoje + (abs(hashtext(m.id::text || z.k)) % 6) - 1
              when abs(hashtext(m.id::text || z.k)) % 100 < 2 then v_hoje - 1 - abs(hashtext(m.id::text)) % 10
              when abs(hashtext(m.id::text || z.k)) % 100 < 7 then v_hoje + 3 + abs(hashtext(m.id::text)) % 25
              else v_hoje + 60 + abs(hashtext(m.id::text || z.k)) % 240 end,
         case when z.k = 1 then ceil(m.quantidade * 0.6) else m.quantidade - ceil(m.quantidade * 0.6) end,
         (select id from iara.fornecedores where is_demo and tipo = case when pr.entrega_direta then 'AGRICULTURA_FAMILIAR' else 'DISTRIBUIDOR' end and 'ALIMENTO' = any (categorias) limit 1),
         now() - make_interval(days => z.k * 25), true
  from iara.materiais m join iara.produtos pr on pr.codigo = m.codigo cross join (values (1), (2)) z(k)
  where m.is_demo and pr.controla_validade and m.quantidade > 0 and (z.k = 1 or m.quantidade - ceil(m.quantidade * 0.6) > 0);

  -- pedidos de agosto até hoje: a maioria recebida; alguns em aprovação, separação ou a caminho (uns atrasados)
  create temp table tmp_ped on commit drop as
  select u.id unit_id, g, abs(hashtext(u.id::text || 'ped' || g)) % 100 h,
         ((v_hoje - (70 - g * 16 + abs(hashtext(u.id::text || g)) % 9))::timestamp + interval '7 hours 30 minutes'
           + make_interval(mins => abs(hashtext(u.id::text || g || 'h')) % 600)) at time zone 'America/Sao_Paulo' em
  from iara.education_units u cross join generate_series(1, 4) g
  where u.status = 'ATIVA' and exists (select 1 from iara.classes c where c.unit_id = u.id and c.status = 'ATIVA');
  insert into iara.pedidos (unit_id, origem, fornecedor_id, situacao, prioridade, justificativa, solicitado_por_label, solicitado_em, decidido_por_label, decidido_em,
                            motivo_recusa, despachado_em, previsao_entrega, recebido_em, conferido_por_label, is_demo)
  select t.unit_id, case when t.h % 5 = 0 then 'FORNECEDOR' else 'ALMOXARIFADO' end,
         case when t.h % 5 = 0 then (select id from iara.fornecedores where is_demo and tipo = 'AGRICULTURA_FAMILIAR' limit 1) end,
         x.sit, case when t.h % 11 = 0 then 'URGENTE' else 'NORMAL' end,
         case when t.h % 11 = 0 then 'Estoque acabando antes da próxima remessa programada.' end,
         'Secretaria da unidade (demonstração)', t.em,
         case when x.sit not in ('ENVIADO', 'CANCELADO') then 'Almoxarifado SEDUC (demonstração)' end,
         case when x.sit not in ('ENVIADO', 'CANCELADO') then t.em + interval '1 day' end,
         case when x.sit = 'RECUSADO' then 'Quantidade acima da cota bimestral da unidade; refaça com a cota.' end,
         case when x.sit in ('EM_TRANSPORTE', 'RECEBIDO', 'RECEBIDO_PARCIAL') then t.em + interval '2 days' end,
         case when x.sit = 'EM_TRANSPORTE' then v_hoje + 1 + t.h % 3 when x.sit in ('RECEBIDO', 'RECEBIDO_PARCIAL') then (t.em + interval '5 days')::date end,
         case when x.sit in ('RECEBIDO', 'RECEBIDO_PARCIAL') then t.em + make_interval(days => 3 + t.h % 4) end,
         case when x.sit in ('RECEBIDO', 'RECEBIDO_PARCIAL') then 'Secretaria da unidade (demonstração)' end, true
  from tmp_ped t cross join lateral (select case
      when t.g < 4 and t.h < 3 then 'RECUSADO' when t.g < 4 and t.h < 11 then 'RECEBIDO_PARCIAL' when t.g < 4 then 'RECEBIDO'
      when t.h < 25 then 'ENVIADO' when t.h < 45 then 'APROVADO' when t.h < 70 then 'EM_TRANSPORTE' when t.h < 72 then 'CANCELADO' else 'RECEBIDO' end sit) x;
  update iara.pedidos set previsao_entrega = v_hoje - 2 - abs(hashtext(id::text)) % 4
  where is_demo and situacao = 'EM_TRANSPORTE' and abs(hashtext(id::text || 'atr')) % 100 < 30;
  insert into iara.pedido_itens (pedido_id, produto_codigo, quantidade_pedida, quantidade_aprovada, quantidade_enviada, quantidade_recebida, lotes, divergencia, is_demo)
  select pe.id, pr.codigo, q.q,
         case when pe.situacao in ('APROVADO', 'EM_TRANSPORTE', 'RECEBIDO', 'RECEBIDO_PARCIAL') then case when abs(hashtext(pe.id::text || pr.codigo)) % 10 = 0 then ceil(q.q * 0.7) else q.q end end,
         case when pe.situacao in ('EM_TRANSPORTE', 'RECEBIDO', 'RECEBIDO_PARCIAL') then case when abs(hashtext(pe.id::text || pr.codigo)) % 10 = 0 then ceil(q.q * 0.7) else q.q end end,
         case when pe.situacao = 'RECEBIDO' then case when abs(hashtext(pe.id::text || pr.codigo)) % 10 = 0 then ceil(q.q * 0.7) else q.q end
              when pe.situacao = 'RECEBIDO_PARCIAL' then case when abs(hashtext(pe.id::text || pr.codigo)) % 10 = 0 then ceil(q.q * 0.7) else q.q end - case when pr.rn = 1 then greatest(1, floor(q.q * 0.2)) else 0 end end,
         case when pr.controla_validade and pe.situacao in ('EM_TRANSPORTE', 'RECEBIDO', 'RECEBIDO_PARCIAL')
              then jsonb_build_array(jsonb_build_object('lote', 'L' || to_char(pe.solicitado_em, 'YYMM') || '-' || (abs(hashtext(pe.id::text || pr.codigo)) % 900 + 100),
                     'validade', (pe.solicitado_em + case when pr.entrega_direta then interval '7 days' else interval '210 days' end)::date, 'quantidade', q.q)) else '[]' end,
         case when pe.situacao = 'RECEBIDO_PARCIAL' and pr.rn = 1 then (array['Duas caixas chegaram avariadas', 'Faltou um volume na entrega', 'Embalagens abertas, devolvidas ao motorista'])[1 + abs(hashtext(pe.id::text)) % 3] end,
         true
  from iara.pedidos pe
  cross join lateral (select p2.*, row_number() over (order by abs(hashtext(pe.id::text || p2.codigo))) rn from iara.produtos p2
                      where p2.ativo and not p2.duravel and (case when pe.origem = 'FORNECEDOR' then p2.entrega_direta else not p2.entrega_direta end)
                      order by abs(hashtext(pe.id::text || p2.codigo)) limit case when pe.origem = 'FORNECEDOR' then 1 else 2 + abs(hashtext(pe.id::text)) % 4 end) pr
  cross join lateral (select case when pr.categoria = 'ALIMENTO' then 10 + abs(hashtext(pe.id::text || pr.codigo)) % 40 else 2 + abs(hashtext(pe.id::text || pr.codigo)) % 15 end::numeric q) q
  where pe.is_demo;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('produtos', (select count(*) from iara.produtos), 'pedidos', (select count(*) from iara.pedidos where is_demo),
    'itens', (select count(*) from iara.pedido_itens where is_demo), 'lotes', (select count(*) from iara.estoque_lotes where is_demo),
    'alimentos_unidades', (select count(*) from iara.materiais where is_demo and categoria = 'ALIMENTO' and unit_id is not null));
end $$;

revoke all on function iara.demo_gerar_almoxarifado(), iara.material_do_produto(integer, text), iara.estoque_baixar(uuid, numeric, text),
  iara.estoque_entrar(uuid, numeric, text, text, date, uuid) from public;

-- 6. Classificação --------------------------------------------------------------------------------------------------------------
insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('pedidos', 'justificativa', 'INTERNO', 'texto livre', 'pedido de material', null),
  ('pedidos', 'motivo_recusa', 'INTERNO', 'texto livre', 'pedido de material', null),
  ('pedidos', 'solicitado_por_label', 'PESSOAL', 'identificação', 'auditoria (quem pediu)', null),
  ('pedidos', 'decidido_por_label', 'PESSOAL', 'identificação', 'auditoria (quem decidiu)', null),
  ('pedidos', 'conferido_por_label', 'PESSOAL', 'identificação', 'auditoria (quem conferiu)', null),
  ('pedido_itens', 'divergencia', 'INTERNO', 'texto livre', 'conferência do recebimento', null),
  ('fornecedores', 'nome', 'INTERNO', 'pessoa jurídica', 'abastecimento', null)
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

commit;
