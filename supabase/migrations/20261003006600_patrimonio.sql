-- IARA Educa — 066 · Patrimônio completo (Sprint 4)
-- Sobre os bens já cadastrados em Materiais (número de patrimônio, estado e local): dados de aquisição, situação (em uso, em manutenção,
-- em transferência, aguardando baixa, baixado), transferência entre unidades com aceite do destino (ou devolução ao almoxarifado central),
-- envio e retorno de conserto com custo, baixa formal com laudo e aprovação da SEDUC, e inventário anual da unidade (localizado ou não,
-- estado e local conferidos), com histórico de tudo.
begin;

insert into iara.permissions (code, description, is_sensitive) values
  ('patrimonio.baixa', 'Aprovar a baixa de bens patrimoniais e acompanhar o patrimônio da rede', false)
on conflict (code) do update set description = excluded.description;
insert into iara.role_permissions (role_code, permission_code)
select r, 'patrimonio.baixa' from (values ('ALMOXARIFADO'), ('SUPERINTENDENCIA')) v(r)
on conflict do nothing;

alter table iara.materiais add column if not exists valor_aquisicao numeric(12, 2);
alter table iara.materiais add column if not exists adquirido_em date;
alter table iara.materiais add column if not exists nota_fiscal text;
alter table iara.materiais add column if not exists fornecedor text;
alter table iara.materiais add column if not exists situacao_patrimonio text not null default 'EM_USO';
alter table iara.materiais drop constraint if exists materiais_situacao_patrimonio_check;
alter table iara.materiais add constraint materiais_situacao_patrimonio_check
  check (situacao_patrimonio in ('EM_USO', 'EM_MANUTENCAO', 'EM_TRANSFERENCIA', 'AGUARDANDO_BAIXA', 'BAIXADO'));
alter table iara.materiais add column if not exists baixa_em date;
alter table iara.materiais add column if not exists baixa_motivo text;
alter table iara.materiais add column if not exists demo_unit_id integer;   -- unidade original do bem fictício (a limpeza devolve)
alter table iara.materiais add column if not exists patrimonio_alterado_em timestamptz;

create table if not exists iara.patrimonio_eventos (
  id uuid primary key default gen_random_uuid(),
  material_id uuid not null references iara.materiais(id) on delete cascade,
  tipo text not null check (tipo in ('CADASTRO', 'TRANSFERENCIA_SOLICITADA', 'TRANSFERENCIA_RECEBIDA', 'TRANSFERENCIA_RECUSADA', 'TRANSFERENCIA_CANCELADA',
                                     'MANUTENCAO_ENVIO', 'MANUTENCAO_RETORNO', 'BAIXA_SOLICITADA', 'BAIXA_APROVADA', 'BAIXA_NEGADA', 'INVENTARIO', 'ESTADO', 'LOCAL')),
  origem_unit integer,
  destino_unit integer,
  estado text,
  texto text,
  custo numeric(12, 2),
  documento text,
  autor_label text,
  created_at timestamptz not null default now(),
  is_demo boolean not null default false
);
create index if not exists patrimonio_eventos_idx on iara.patrimonio_eventos (material_id, created_at);
create table if not exists iara.patrimonio_transferencias (
  id uuid primary key default gen_random_uuid(),
  material_id uuid not null references iara.materiais(id) on delete cascade,
  origem_unit integer,
  destino_unit integer,   -- nulo: almoxarifado central
  motivo text not null,
  situacao text not null default 'PENDENTE' check (situacao in ('PENDENTE', 'ACEITA', 'RECUSADA', 'CANCELADA')),
  solicitada_por_label text,
  solicitada_em timestamptz not null default now(),
  respondida_por_label text,
  respondida_em timestamptz,
  resposta text,
  is_demo boolean not null default false
);
create unique index if not exists patrimonio_transferencia_pendente on iara.patrimonio_transferencias (material_id) where situacao = 'PENDENTE';
create table if not exists iara.inventarios (
  id uuid primary key default gen_random_uuid(),
  unit_id integer not null,
  ano smallint not null,
  situacao text not null default 'ABERTO' check (situacao in ('ABERTO', 'CONCLUIDO')),
  responsavel_label text,
  aberto_em timestamptz not null default now(),
  concluido_em timestamptz,
  observacao text,
  is_demo boolean not null default false,
  unique (unit_id, ano)
);
create table if not exists iara.inventario_itens (
  inventario_id uuid not null references iara.inventarios(id) on delete cascade,
  material_id uuid not null references iara.materiais(id) on delete cascade,
  localizado boolean,
  estado text,
  localizacao text,
  observacao text,
  conferido_por_label text,
  conferido_em timestamptz,
  primary key (inventario_id, material_id)
);
alter table iara.patrimonio_eventos enable row level security;
alter table iara.patrimonio_transferencias enable row level security;
alter table iara.inventarios enable row level security;
alter table iara.inventario_itens enable row level security;

-- quem mexe em um bem: a unidade dona (materiais.write), o almoxarifado central para bens sem unidade, a SEDUC para baixa
create or replace function iara.patrimonio_da_minha_unidade(m iara.materiais) returns boolean
language sql stable security definer set search_path = iara, public
as $$ select iara.has_perm('materiais.write') and ((iara.my_scope() = 'UNIT' and m.unit_id = iara.my_unit()) or (m.unit_id is null and iara.has_perm('almoxarifado.manage'))) $$;

create or replace function iara.patrimonio_json(m iara.materiais, p_eventos boolean default false) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', m.id, 'patrimonio', m.patrimonio, 'nome', m.nome, 'categoria', m.categoria, 'estado', m.estado, 'situacao', m.situacao_patrimonio,
    'localizacao', m.localizacao, 'unit_id', m.unit_id, 'unidade', coalesce((select short_name from iara.education_units where id = m.unit_id), 'Almoxarifado central'),
    'valor', m.valor_aquisicao, 'adquirido_em', m.adquirido_em, 'nota_fiscal', m.nota_fiscal, 'fornecedor', m.fornecedor, 'baixa_em', m.baixa_em, 'baixa_motivo', m.baixa_motivo,
    'is_demo', m.is_demo,
    'transferencia', (select jsonb_build_object('id', t.id, 'destino', coalesce((select short_name from iara.education_units where id = t.destino_unit), 'Almoxarifado central'),
                        'destino_unit', t.destino_unit, 'origem', coalesce((select short_name from iara.education_units where id = t.origem_unit), 'Almoxarifado central'),
                        'motivo', t.motivo, 'solicitada_em', t.solicitada_em, 'por', t.solicitada_por_label)
                      from iara.patrimonio_transferencias t where t.material_id = m.id and t.situacao = 'PENDENTE'),
    'eventos', case when p_eventos then (select coalesce(jsonb_agg(jsonb_build_object('tipo', e.tipo, 'texto', e.texto, 'estado', e.estado, 'custo', e.custo, 'documento', e.documento,
                     'origem', (select short_name from iara.education_units where id = e.origem_unit), 'destino', (select short_name from iara.education_units where id = e.destino_unit),
                     'autor', e.autor_label, 'em', e.created_at) order by e.created_at desc), '[]') from iara.patrimonio_eventos e where e.material_id = m.id) end)
$$;

create or replace function api.patrimonio_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_q text := nullif(iara.norm(btrim(coalesce(p ->> 'q', ''))), '');
begin
  perform iara.require_perm('materiais.read');
  if v_unit is not null and not iara.can_access_unit(v_unit) then raise exception 'Unidade fora do seu escopo.' using errcode = '42501'; end if;
  return (with base as (select m.* from iara.materiais m where m.patrimonio is not null and (v_unit is null or m.unit_id = v_unit)
                          and (coalesce((p ->> 'baixados')::boolean, false) or m.situacao_patrimonio <> 'BAIXADO'))
    select jsonb_build_object('unit_id', v_unit, 'pode_baixa', iara.has_perm('patrimonio.baixa'), 'pode_editar', iara.has_perm('materiais.write') and (iara.my_scope() = 'UNIT' or iara.has_perm('almoxarifado.manage')),
      'resumo', (select jsonb_build_object('itens', count(*), 'valor', coalesce(sum(valor_aquisicao), 0),
                   'em_manutencao', count(*) filter (where situacao_patrimonio = 'EM_MANUTENCAO'), 'em_transferencia', count(*) filter (where situacao_patrimonio = 'EM_TRANSFERENCIA'),
                   'aguardando_baixa', count(*) filter (where situacao_patrimonio = 'AGUARDANDO_BAIXA'), 'ruins', count(*) filter (where estado in ('RUIM', 'INSERVIVEL'))) from base),
      'a_receber', (select coalesce(jsonb_agg(iara.patrimonio_json(m) order by t.solicitada_em), '[]') from iara.patrimonio_transferencias t join iara.materiais m on m.id = t.material_id
                    where t.situacao = 'PENDENTE' and ((v_unit is not null and t.destino_unit = v_unit) or (v_unit is null and t.destino_unit is null and iara.has_perm('almoxarifado.manage')))),
      'baixas', case when iara.has_perm('patrimonio.baixa') then (select coalesce(jsonb_agg(iara.patrimonio_json(m) order by m.patrimonio_alterado_em), '[]')
                    from iara.materiais m where m.situacao_patrimonio = 'AGUARDANDO_BAIXA' and (v_unit is null or m.unit_id = v_unit)) end,
      'inventario', case when v_unit is not null then (select jsonb_build_object('id', i.id, 'ano', i.ano, 'situacao', i.situacao, 'aberto_em', i.aberto_em, 'concluido_em', i.concluido_em,
                        'itens', (select count(*) from iara.inventario_itens x where x.inventario_id = i.id),
                        'conferidos', (select count(*) from iara.inventario_itens x where x.inventario_id = i.id and x.localizado is not null),
                        'nao_localizados', (select count(*) from iara.inventario_itens x where x.inventario_id = i.id and x.localizado = false))
                      from iara.inventarios i where i.unit_id = v_unit order by i.ano desc limit 1) end,
      'itens', (select coalesce(jsonb_agg(iara.patrimonio_json(b) order by b.situacao_patrimonio <> 'EM_USO' desc, b.nome, b.patrimonio), '[]') from (
                  select * from base where (v_q is null or iara.norm(nome || ' ' || patrimonio || ' ' || coalesce(localizacao, '')) like '%' || v_q || '%')
                    and (nullif(p ->> 'situacao', '') is null or situacao_patrimonio = p ->> 'situacao') and (nullif(p ->> 'estado', '') is null or estado = p ->> 'estado')
                  order by nome limit 400) b)));
end $$;

create or replace function api.patrimonio_detalhe(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  m iara.materiais;
begin
  perform iara.require_perm('materiais.read');
  select * into m from iara.materiais where id = (p ->> 'id')::uuid and patrimonio is not null;
  if m.id is null or (m.unit_id is not null and not iara.can_access_unit(m.unit_id)) then raise exception 'Bem não encontrado.' using errcode = 'P0002'; end if;
  return iara.patrimonio_json(m, true) || jsonb_build_object(
    'pode_mover', iara.patrimonio_da_minha_unidade(m) and m.situacao_patrimonio in ('EM_USO', 'EM_MANUTENCAO'),
    'pode_receber', exists (select 1 from iara.patrimonio_transferencias t where t.material_id = m.id and t.situacao = 'PENDENTE'
                            and ((t.destino_unit is not null and iara.my_scope() = 'UNIT' and t.destino_unit = iara.my_unit() and iara.has_perm('materiais.write'))
                                 or (t.destino_unit is null and iara.has_perm('almoxarifado.manage')))),
    'pode_decidir_baixa', iara.has_perm('patrimonio.baixa') and m.situacao_patrimonio = 'AGUARDANDO_BAIXA',
    'unidades', (select jsonb_agg(jsonb_build_object('id', u.id, 'nome', u.short_name) order by u.short_name) from iara.education_units u where u.status = 'ATIVA' and u.id is distinct from m.unit_id));
end $$;

-- ações sobre o bem: transferir, receber/recusar, cancelar, conserto (envio/retorno), estado/local, pedir e decidir a baixa
create or replace function api.patrimonio_acao(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  m iara.materiais;
  t iara.patrimonio_transferencias;
  v_acao text := upper(coalesce(p ->> 'acao', ''));
  v_txt text := btrim(coalesce(p ->> 'texto', ''));
  v_dest integer := nullif(p ->> 'destino_unit', '')::int;
begin
  select * into m from iara.materiais where id = (p ->> 'id')::uuid and patrimonio is not null for update;
  if m.id is null then raise exception 'Bem não encontrado.' using errcode = 'P0002'; end if;
  if v_acao in ('RECEBER', 'RECUSAR') then
    select * into t from iara.patrimonio_transferencias where material_id = m.id and situacao = 'PENDENTE' for update;
    if t.id is null then raise exception 'Não há transferência pendente para este bem.' using errcode = '22023'; end if;
    if not ((t.destino_unit is not null and iara.my_scope() = 'UNIT' and t.destino_unit = iara.my_unit() and iara.has_perm('materiais.write'))
            or (t.destino_unit is null and iara.has_perm('almoxarifado.manage'))) then
      raise exception 'Só a unidade de destino recebe o bem.' using errcode = '42501';
    end if;
    if v_acao = 'RECUSAR' and length(v_txt) < 5 then raise exception 'Informe o motivo da recusa.' using errcode = '22023'; end if;
    update iara.patrimonio_transferencias set situacao = case when v_acao = 'RECEBER' then 'ACEITA' else 'RECUSADA' end, respondida_por_label = iara.my_label(),
           respondida_em = now(), resposta = nullif(v_txt, '') where id = t.id;
    update iara.materiais set unit_id = case when v_acao = 'RECEBER' then t.destino_unit else unit_id end, situacao_patrimonio = 'EM_USO',
           localizacao = case when v_acao = 'RECEBER' then coalesce(nullif(btrim(coalesce(p ->> 'localizacao', '')), ''), 'A definir') else localizacao end, patrimonio_alterado_em = now()
    where id = m.id;
    insert into iara.patrimonio_eventos (material_id, tipo, origem_unit, destino_unit, texto, autor_label)
    values (m.id, case when v_acao = 'RECEBER' then 'TRANSFERENCIA_RECEBIDA' else 'TRANSFERENCIA_RECUSADA' end, t.origem_unit, t.destino_unit, nullif(v_txt, ''), iara.my_label());
  elsif v_acao = 'DECIDIR_BAIXA' then
    perform iara.require_perm('patrimonio.baixa');
    if m.situacao_patrimonio <> 'AGUARDANDO_BAIXA' then raise exception 'O bem não está aguardando baixa.' using errcode = '22023'; end if;
    if length(v_txt) < 10 then raise exception 'Registre o parecer (mínimo de 10 caracteres).' using errcode = '22023'; end if;
    if coalesce((p ->> 'aprovar')::boolean, false) then
      update iara.materiais set situacao_patrimonio = 'BAIXADO', estado = 'INSERVIVEL', baixa_em = iara.hoje_local(), quantidade = 0, patrimonio_alterado_em = now() where id = m.id;
      insert into iara.patrimonio_eventos (material_id, tipo, origem_unit, texto, documento, autor_label) values (m.id, 'BAIXA_APROVADA', m.unit_id, v_txt, nullif(btrim(coalesce(p ->> 'documento', '')), ''), iara.my_label());
    else
      update iara.materiais set situacao_patrimonio = 'EM_USO', baixa_motivo = null, patrimonio_alterado_em = now() where id = m.id;
      insert into iara.patrimonio_eventos (material_id, tipo, origem_unit, texto, autor_label) values (m.id, 'BAIXA_NEGADA', m.unit_id, v_txt, iara.my_label());
    end if;
  else
    if not iara.patrimonio_da_minha_unidade(m) then raise exception 'Só a unidade responsável pelo bem registra esta ação.' using errcode = '42501'; end if;
    if v_acao = 'TRANSFERIR' then
      if m.situacao_patrimonio <> 'EM_USO' then raise exception 'Só um bem em uso pode ser transferido.' using errcode = '22023'; end if;
      if v_dest is not distinct from m.unit_id then raise exception 'Escolha outra unidade de destino.' using errcode = '22023'; end if;
      if v_dest is not null and not exists (select 1 from iara.education_units where id = v_dest and status = 'ATIVA') then raise exception 'Unidade de destino inválida.' using errcode = '22023'; end if;
      if length(v_txt) < 10 then raise exception 'Explique o motivo da transferência (mínimo de 10 caracteres).' using errcode = '22023'; end if;
      insert into iara.patrimonio_transferencias (material_id, origem_unit, destino_unit, motivo, solicitada_por_label) values (m.id, m.unit_id, v_dest, v_txt, iara.my_label());
      update iara.materiais set situacao_patrimonio = 'EM_TRANSFERENCIA', patrimonio_alterado_em = now() where id = m.id;
      insert into iara.patrimonio_eventos (material_id, tipo, origem_unit, destino_unit, texto, autor_label) values (m.id, 'TRANSFERENCIA_SOLICITADA', m.unit_id, v_dest, v_txt, iara.my_label());
    elsif v_acao = 'CANCELAR_TRANSFERENCIA' then
      update iara.patrimonio_transferencias set situacao = 'CANCELADA', respondida_por_label = iara.my_label(), respondida_em = now(), resposta = nullif(v_txt, '')
      where material_id = m.id and situacao = 'PENDENTE';
      if not found then raise exception 'Não há transferência pendente.' using errcode = '22023'; end if;
      update iara.materiais set situacao_patrimonio = 'EM_USO', patrimonio_alterado_em = now() where id = m.id;
      insert into iara.patrimonio_eventos (material_id, tipo, origem_unit, texto, autor_label) values (m.id, 'TRANSFERENCIA_CANCELADA', m.unit_id, nullif(v_txt, ''), iara.my_label());
    elsif v_acao = 'MANUTENCAO_ENVIO' then
      if m.situacao_patrimonio <> 'EM_USO' then raise exception 'O bem não está em uso.' using errcode = '22023'; end if;
      if length(v_txt) < 5 then raise exception 'Descreva o defeito e para onde foi.' using errcode = '22023'; end if;
      update iara.materiais set situacao_patrimonio = 'EM_MANUTENCAO', patrimonio_alterado_em = now() where id = m.id;
      insert into iara.patrimonio_eventos (material_id, tipo, origem_unit, texto, documento, autor_label) values (m.id, 'MANUTENCAO_ENVIO', m.unit_id, v_txt, nullif(btrim(coalesce(p ->> 'documento', '')), ''), iara.my_label());
    elsif v_acao = 'MANUTENCAO_RETORNO' then
      if m.situacao_patrimonio <> 'EM_MANUTENCAO' then raise exception 'O bem não está em manutenção.' using errcode = '22023'; end if;
      if coalesce(p ->> 'estado', '') not in ('NOVO', 'BOM', 'REGULAR', 'RUIM', 'INSERVIVEL') then raise exception 'Informe o estado no retorno.' using errcode = '22023'; end if;
      update iara.materiais set situacao_patrimonio = 'EM_USO', estado = p ->> 'estado', patrimonio_alterado_em = now() where id = m.id;
      insert into iara.patrimonio_eventos (material_id, tipo, origem_unit, estado, custo, texto, documento, autor_label)
      values (m.id, 'MANUTENCAO_RETORNO', m.unit_id, p ->> 'estado', nullif(p ->> 'custo', '')::numeric, nullif(v_txt, ''), nullif(btrim(coalesce(p ->> 'documento', '')), ''), iara.my_label());
    elsif v_acao = 'ATUALIZAR' then
      if coalesce(p ->> 'estado', m.estado) not in ('NOVO', 'BOM', 'REGULAR', 'RUIM', 'INSERVIVEL') then raise exception 'Estado inválido.' using errcode = '22023'; end if;
      update iara.materiais set estado = coalesce(nullif(p ->> 'estado', ''), estado), localizacao = coalesce(nullif(btrim(coalesce(p ->> 'localizacao', '')), ''), localizacao),
             valor_aquisicao = coalesce(nullif(p ->> 'valor', '')::numeric, valor_aquisicao), adquirido_em = coalesce(nullif(p ->> 'adquirido_em', '')::date, adquirido_em),
             nota_fiscal = coalesce(nullif(btrim(coalesce(p ->> 'nota_fiscal', '')), ''), nota_fiscal), fornecedor = coalesce(nullif(btrim(coalesce(p ->> 'fornecedor', '')), ''), fornecedor),
             patrimonio_alterado_em = now()
      where id = m.id;
      insert into iara.patrimonio_eventos (material_id, tipo, origem_unit, estado, texto, autor_label)
      values (m.id, case when nullif(p ->> 'localizacao', '') is not null and p ->> 'localizacao' is distinct from m.localizacao then 'LOCAL' else 'ESTADO' end, m.unit_id,
              coalesce(nullif(p ->> 'estado', ''), m.estado), format('Estado %s; local %s.', lower(coalesce(nullif(p ->> 'estado', ''), m.estado)), coalesce(nullif(p ->> 'localizacao', ''), m.localizacao, '—')), iara.my_label());
    elsif v_acao = 'SOLICITAR_BAIXA' then
      if m.situacao_patrimonio not in ('EM_USO', 'EM_MANUTENCAO') then raise exception 'O bem não pode ir para baixa agora.' using errcode = '22023'; end if;
      if length(v_txt) < 10 then raise exception 'Explique por que o bem é inservível (mínimo de 10 caracteres).' using errcode = '22023'; end if;
      update iara.materiais set situacao_patrimonio = 'AGUARDANDO_BAIXA', baixa_motivo = v_txt, patrimonio_alterado_em = now() where id = m.id;
      insert into iara.patrimonio_eventos (material_id, tipo, origem_unit, texto, documento, autor_label) values (m.id, 'BAIXA_SOLICITADA', m.unit_id, v_txt, nullif(btrim(coalesce(p ->> 'documento', '')), ''), iara.my_label());
    else
      raise exception 'Ação desconhecida.' using errcode = '22023';
    end if;
  end if;
  perform iara.audit_event('PATRIMONIO', 'material', m.patrimonio, m.unit_id, format('Patrimônio %s: %s.', m.patrimonio, lower(replace(v_acao, '_', ' '))));
  return api.patrimonio_detalhe(jsonb_build_object('id', m.id));
end $$;

-- inventário anual da unidade: abrir (lista os bens), conferir item a item e concluir (não localizados ficam registrados)
create or replace function api.inventario(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_unit integer := iara.my_unit();
  i iara.inventarios;
  v_acao text := upper(coalesce(p ->> 'acao', 'VER'));
  x jsonb;
begin
  perform iara.require_perm('materiais.read');
  if iara.my_scope() <> 'UNIT' then
    v_unit := nullif(p ->> 'unit_id', '')::int;
    if v_acao <> 'VER' then raise exception 'O inventário é feito pela unidade.' using errcode = '42501'; end if;
  end if;
  select * into i from iara.inventarios where unit_id = v_unit and ano = extract(year from iara.hoje_local())::int;
  if v_acao <> 'VER' then perform iara.require_perm('materiais.write'); end if;
  if v_acao = 'ABRIR' then
    if i.id is not null then raise exception 'O inventário deste ano já foi aberto.' using errcode = '22023'; end if;
    insert into iara.inventarios (unit_id, ano, responsavel_label) values (v_unit, extract(year from iara.hoje_local())::int, iara.my_label()) returning * into i;
    insert into iara.inventario_itens (inventario_id, material_id) select i.id, m.id from iara.materiais m where m.unit_id = v_unit and m.patrimonio is not null and m.situacao_patrimonio <> 'BAIXADO';
  elsif v_acao = 'CONFERIR' then
    if i.id is null or i.situacao <> 'ABERTO' then raise exception 'Não há inventário aberto.' using errcode = '22023'; end if;
    for x in select * from jsonb_array_elements(coalesce(p -> 'itens', '[]')) loop
      update iara.inventario_itens set localizado = (x ->> 'localizado')::boolean, estado = nullif(x ->> 'estado', ''), localizacao = nullif(btrim(coalesce(x ->> 'localizacao', '')), ''),
             observacao = nullif(btrim(coalesce(x ->> 'observacao', '')), ''), conferido_por_label = iara.my_label(), conferido_em = now()
      where inventario_id = i.id and material_id = (x ->> 'material_id')::uuid;
    end loop;
  elsif v_acao = 'CONCLUIR' then
    if i.id is null or i.situacao <> 'ABERTO' then raise exception 'Não há inventário aberto.' using errcode = '22023'; end if;
    if exists (select 1 from iara.inventario_itens where inventario_id = i.id and localizado is null) then raise exception 'Confira todos os bens antes de concluir.' using errcode = '22023'; end if;
    update iara.materiais m set estado = coalesce(it.estado, m.estado), localizacao = coalesce(it.localizacao, m.localizacao), patrimonio_alterado_em = now()
    from iara.inventario_itens it where it.inventario_id = i.id and it.material_id = m.id and it.localizado;
    insert into iara.patrimonio_eventos (material_id, tipo, origem_unit, estado, texto, autor_label)
    select it.material_id, 'INVENTARIO', v_unit, it.estado, case when it.localizado then 'Localizado no inventário ' || i.ano || '.' else 'NÃO localizado no inventário ' || i.ano || coalesce(': ' || it.observacao, '.') end, iara.my_label()
    from iara.inventario_itens it where it.inventario_id = i.id;
    update iara.inventarios set situacao = 'CONCLUIDO', concluido_em = now(), observacao = nullif(btrim(coalesce(p ->> 'observacao', '')), '') where id = i.id returning * into i;
    perform iara.audit_event('PATRIMONIO', 'inventario', i.id::text, v_unit, format('Inventário %s concluído.', i.ano));
  end if;
  if i.id is null then return jsonb_build_object('aberto', false, 'pode_abrir', iara.has_perm('materiais.write') and iara.my_scope() = 'UNIT'); end if;
  return to_jsonb(i) || jsonb_build_object('aberto', true,
    'itens', (select coalesce(jsonb_agg(jsonb_build_object('material_id', m.id, 'patrimonio', m.patrimonio, 'nome', m.nome, 'estado_cadastro', m.estado, 'local_cadastro', m.localizacao,
                 'localizado', it.localizado, 'estado', it.estado, 'localizacao', it.localizacao, 'observacao', it.observacao, 'conferido_em', it.conferido_em) order by m.localizacao, m.nome), '[]')
              from iara.inventario_itens it join iara.materiais m on m.id = it.material_id where it.inventario_id = i.id));
end $$;

-- demonstração: dados de aquisição, consertos, transferências (algumas aguardando aceite), baixas aguardando e inventários em andamento
create or replace function iara.demo_gerar_patrimonio() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.inventarios where is_demo;
  delete from iara.patrimonio_transferencias where is_demo;
  delete from iara.patrimonio_eventos where is_demo;
  update iara.materiais set demo_unit_id = unit_id where is_demo and patrimonio is not null and demo_unit_id is null;
  update iara.materiais m set unit_id = m.demo_unit_id,
         valor_aquisicao = round((case when m.nome ilike '%projetor%' then 2900 when m.nome ilike '%computador%' or m.nome ilike '%notebook%' then 3400
                                       when m.nome ilike '%geladeira%' or m.nome ilike '%freezer%' then 3800 when m.nome ilike '%fogão%' then 2100
                                       when m.categoria = 'MOBILIARIO' then 420 else 1300 end * (0.8 + (abs(hashtext(m.id::text)) % 40) / 100.0))::numeric, 2),
         adquirido_em = date '2018-02-01' + abs(hashtext(m.id::text || 'aq')) % 2900,
         nota_fiscal = 'NF ' || (10000 + abs(hashtext(m.id::text || 'nf')) % 89999) || ' (demonstração)',
         fornecedor = (array['Comercial Exemplo Ltda. (demonstração)', 'Distribuidora Modelo S.A. (demonstração)', 'Fornecedor Teste ME (demonstração)'])[1 + abs(hashtext(m.id::text)) % 3],
         situacao_patrimonio = case when abs(hashtext(m.id::text || 'sit')) % 100 < 4 then 'EM_MANUTENCAO' when abs(hashtext(m.id::text || 'sit')) % 100 < 6 then 'AGUARDANDO_BAIXA'
                                    when abs(hashtext(m.id::text || 'sit')) % 100 < 8 then 'EM_TRANSFERENCIA' else 'EM_USO' end,
         baixa_motivo = case when abs(hashtext(m.id::text || 'sit')) % 100 between 4 and 5 then 'Equipamento sem conserto segundo o laudo técnico; peças fora de linha.' end,
         baixa_em = null, patrimonio_alterado_em = null
  where m.is_demo and m.patrimonio is not null;
  insert into iara.patrimonio_eventos (material_id, tipo, origem_unit, texto, autor_label, created_at, is_demo)
  select m.id, 'CADASTRO', m.unit_id, 'Incorporado ao patrimônio — ' || m.nota_fiscal, 'Patrimônio · SEDUC (demonstração)', m.adquirido_em::timestamptz + interval '10 hours', true
  from iara.materiais m where m.is_demo and m.patrimonio is not null;
  insert into iara.patrimonio_eventos (material_id, tipo, origem_unit, estado, custo, texto, autor_label, created_at, is_demo)
  select m.id, t.tipo, m.unit_id, case when t.tipo = 'MANUTENCAO_RETORNO' then 'BOM' end, case when t.tipo = 'MANUTENCAO_RETORNO' then 80 + abs(hashtext(m.id::text)) % 400 end,
         case when t.tipo = 'MANUTENCAO_ENVIO' then 'Não liga; enviado à assistência técnica credenciada.' else 'Retornou consertado (troca de fonte).' end,
         'Secretaria escolar (demonstração)', now() - make_interval(days => t.d + abs(hashtext(m.id::text)) % 60), true
  from iara.materiais m cross join (values ('MANUTENCAO_ENVIO', 90), ('MANUTENCAO_RETORNO', 70)) t(tipo, d)
  where m.is_demo and m.patrimonio is not null and abs(hashtext(m.id::text || 'cons')) % 100 < 15;
  insert into iara.patrimonio_eventos (material_id, tipo, origem_unit, texto, autor_label, created_at, is_demo)
  select m.id, case m.situacao_patrimonio when 'EM_MANUTENCAO' then 'MANUTENCAO_ENVIO' else 'BAIXA_SOLICITADA' end, m.unit_id,
         case m.situacao_patrimonio when 'EM_MANUTENCAO' then 'Defeito na tela; enviado à assistência técnica.' else m.baixa_motivo end,
         'Direção da unidade (demonstração)', now() - make_interval(days => 3 + abs(hashtext(m.id::text)) % 40), true
  from iara.materiais m where m.is_demo and m.situacao_patrimonio in ('EM_MANUTENCAO', 'AGUARDANDO_BAIXA');
  update iara.materiais m set patrimonio_alterado_em = now() - make_interval(days => 3 + abs(hashtext(m.id::text)) % 40)
  where m.is_demo and m.situacao_patrimonio in ('EM_MANUTENCAO', 'AGUARDANDO_BAIXA', 'EM_TRANSFERENCIA');
  insert into iara.patrimonio_transferencias (material_id, origem_unit, destino_unit, motivo, solicitada_por_label, solicitada_em, is_demo)
  select m.id, m.unit_id, (select u.id from iara.education_units u where u.status = 'ATIVA' and u.id <> m.unit_id order by abs(hashtext(u.id::text || m.id::text)) limit 1),
         'Remanejamento: a unidade de destino abriu nova turma e precisa do equipamento.', 'Direção da unidade (demonstração)', now() - make_interval(days => 1 + abs(hashtext(m.id::text)) % 10), true
  from iara.materiais m where m.is_demo and m.situacao_patrimonio = 'EM_TRANSFERENCIA';
  insert into iara.patrimonio_eventos (material_id, tipo, origem_unit, destino_unit, texto, autor_label, created_at, is_demo)
  select t.material_id, 'TRANSFERENCIA_SOLICITADA', t.origem_unit, t.destino_unit, t.motivo, t.solicitada_por_label, t.solicitada_em, true
  from iara.patrimonio_transferencias t where t.is_demo;
  -- inventário do ano: concluído em parte das unidades, em andamento em outras
  insert into iara.inventarios (unit_id, ano, situacao, responsavel_label, aberto_em, concluido_em, observacao, is_demo)
  select u.id, extract(year from iara.hoje_local())::int, case when abs(hashtext(u.id::text || 'inv')) % 100 < 35 then 'CONCLUIDO' else 'ABERTO' end,
         'Secretaria escolar (demonstração)', now() - interval '40 days', case when abs(hashtext(u.id::text || 'inv')) % 100 < 35 then now() - interval '12 days' end,
         case when abs(hashtext(u.id::text || 'inv')) % 100 < 35 then 'Inventário conferido com a equipe da unidade.' end, true
  from iara.education_units u where u.status = 'ATIVA' and exists (select 1 from iara.materiais m where m.unit_id = u.id and m.patrimonio is not null and m.is_demo)
    and abs(hashtext(u.id::text || 'inv')) % 100 < 70;
  insert into iara.inventario_itens (inventario_id, material_id, localizado, estado, localizacao, conferido_por_label, conferido_em)
  select i.id, m.id,
         case when i.situacao = 'CONCLUIDO' or abs(hashtext(m.id::text || 'conf')) % 100 < 60 then abs(hashtext(m.id::text || 'loc')) % 100 >= 3 end,
         case when i.situacao = 'CONCLUIDO' or abs(hashtext(m.id::text || 'conf')) % 100 < 60 then m.estado end,
         case when i.situacao = 'CONCLUIDO' or abs(hashtext(m.id::text || 'conf')) % 100 < 60 then m.localizacao end,
         case when i.situacao = 'CONCLUIDO' or abs(hashtext(m.id::text || 'conf')) % 100 < 60 then 'Secretaria escolar (demonstração)' end,
         case when i.situacao = 'CONCLUIDO' or abs(hashtext(m.id::text || 'conf')) % 100 < 60 then now() - interval '20 days' end
  from iara.inventarios i join iara.materiais m on m.unit_id = i.unit_id and m.patrimonio is not null and m.situacao_patrimonio <> 'BAIXADO' where i.is_demo;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('bens', (select count(*) from iara.materiais where is_demo and patrimonio is not null),
    'transferencias', (select count(*) from iara.patrimonio_transferencias where is_demo), 'baixas', (select count(*) from iara.materiais where is_demo and situacao_patrimonio = 'AGUARDANDO_BAIXA'),
    'inventarios', (select count(*) from iara.inventarios where is_demo));
end $$;

create or replace function iara.demo_purge_patrimonio(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  d timestamptz := coalesce(p_desde, '-infinity'::timestamptz);
  v jsonb := '{}'::jsonb;
  n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.patrimonio_eventos where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('eventos', n);
  delete from iara.patrimonio_transferencias where not is_demo and solicitada_em >= d;
  delete from iara.inventarios where not is_demo and aberto_em >= d;
  if exists (select 1 from iara.materiais where is_demo and patrimonio_alterado_em >= d) or exists (select 1 from iara.inventario_itens it join iara.inventarios i on i.id = it.inventario_id
            where i.is_demo and it.conferido_em >= d and it.conferido_por_label not like '%(demonstração)%') then
    v := v || jsonb_build_object('refeito', iara.demo_gerar_patrimonio());
  end if;
  perform set_config('iara.skip_audit', 'off', true);
  return v;
end $$;

revoke all on function iara.demo_gerar_patrimonio(), iara.demo_purge_patrimonio(timestamptz) from public;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('patrimonio_eventos', 'autor_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('patrimonio_transferencias', 'solicitada_por_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('patrimonio_transferencias', 'respondida_por_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('inventario_itens', 'conferido_por_label', 'PESSOAL', 'identificação', 'auditoria', null)
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

select iara.demo_gerar_patrimonio() where iara.demo_mode();

commit;
