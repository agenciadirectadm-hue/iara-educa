-- IARA Educa — 076 · Áreas de ponderação: ponto em fresta da malha
-- A malha das áreas é simplificada (~6 m) área por área: entre áreas vizinhas e junto ao limite do município sobram frestas
-- de poucos metros. Na primeira aplicação, 94 dos 27.973 endereços (0,3%) caíram nelas e ficaram sem área. Agora vale a
-- área que contém o ponto ou, na fresta, a mais próxima a até 150 m — em endereço novo, localização, carga e reorganização.
begin;

create or replace function iara.area_do_ponto(p_ponto extensions.geography) returns integer
language sql stable security definer set search_path = iara, extensions, public
as $$
  select t.id from iara.territories t
  where p_ponto is not null and t.kind = 'AREA_PONDERACAO' and t.geom is not null and st_dwithin(t.geom, p_ponto, 150)
  order by st_covers(t.geom, p_ponto) desc, st_distance(t.geom, p_ponto), t.sort limit 1
$$;

create or replace function iara.new_address(p_addr jsonb, p_source text) returns uuid
language plpgsql security definer set search_path = iara, extensions, public
as $$
declare
  v_id uuid := gen_random_uuid();
  v_lat float8 := nullif(p_addr ->> 'lat', '')::float8;
  v_lng float8 := nullif(p_addr ->> 'lng', '')::float8;
begin
  if v_lat is null or v_lng is null then
    raise exception 'Informe o bairro (ou marque o ponto no mapa) para localizar o endereço.' using errcode = '22023';
  end if;
  if not iara.in_maringa(v_lat, v_lng) then
    raise exception 'Este endereço fica fora de Maringá. A fila da rede municipal considera o endereço no município.' using errcode = '22023';
  end if;
  insert into iara.addresses (id, tenant_id, street, number, complement, neighborhood, postal_code, location, geocode_precision, geocode_source,
                              territory_id, is_demo)
  values (v_id, 1, coalesce(nullif(btrim(p_addr ->> 'street'), ''), 'Endereço informado'), nullif(btrim(p_addr ->> 'number'), ''),
          nullif(btrim(p_addr ->> 'complement'), ''), nullif(btrim(p_addr ->> 'neighborhood'), ''), nullif(btrim(p_addr ->> 'postal_code'), ''),
          iara.point(v_lat, v_lng), coalesce(nullif(p_addr ->> 'precision', ''), 'BAIRRO'), p_source, iara.area_do_ponto(iara.point(v_lat, v_lng)), true);
  return v_id;
end $$;

create or replace function iara.localizar(p_lat double precision, p_lng double precision) returns jsonb
language sql stable security definer set search_path = iara, extensions, public
as $$
  with pt as (select iara.point(p_lat, p_lng) as g)
  select jsonb_build_object(
    'dentro_maringa', iara.in_maringa(p_lat, p_lng),
    'territorio_id', t.id, 'territorio', t.name, 'territorio_tipo', t.kind, 'distrito', d.name,
    'bairro', b.name, 'bairro_distancia_m', b.dist)
  from pt
  left join iara.territories t on t.id = iara.area_do_ponto(pt.g)
  left join lateral (select d.name from iara.territories d
                     where d.kind = 'DISTRITO' and d.geom is not null and st_covers(d.geom, pt.g) limit 1) d on true
  left join lateral (select b.name, round(st_distance(b.center, pt.g))::int as dist from iara.territories b
                     where b.kind = 'BAIRRO' and b.center is not null order by st_distance(b.center, pt.g) limit 1) b on true
$$;

-- carga: o polígono que contém o ponto; para a área de ponderação, também a fresta (iara.area_do_ponto)
create or replace function carga.territorio(p_lat double precision, p_lng double precision, p_kinds text[]) returns integer
language sql stable as $$
  select coalesce(
    (select t.id from iara.territories t
     where p_lat is not null and t.kind = any (p_kinds) and extensions.st_covers(t.geom, iara.point(p_lat, p_lng))
     order by array_position(p_kinds, t.kind) limit 1),
    case when p_lat is not null and 'AREA_PONDERACAO' = any (p_kinds) then iara.area_do_ponto(iara.point(p_lat, p_lng)) end)
$$;

-- reorganização: endereços pela mesma regra (o resto igual à 075)
create or replace function iara.aplicar_areas_ponderacao() returns jsonb
language plpgsql security definer set search_path = iara, extensions, public
as $$
declare
  v_skip text := coalesce(current_setting('iara.skip_audit', true), '');
  v_regionais integer[] := array(select id from iara.territories where kind in ('MACRORREGIAO', 'DISTRITO'));
  v_unidades integer;
  v_bairros integer;
  v_enderecos integer;
  v_fila integer;
  v_orgaos integer;
  v_macros integer;
  v_ct uuid;
  v jsonb;
begin
  if not exists (select 1 from iara.territories where kind = 'AREA_PONDERACAO' and geom is not null) then
    raise exception 'Carregue antes as áreas de ponderação (supabase/seed/11_areas_ponderacao.sql).' using errcode = '55000';
  end if;
  -- reorganização em massa: um único evento de auditoria resume tudo (o detalhe linha a linha não acrescenta nada)
  perform set_config('iara.skip_audit', 'on', true);

  -- unidades: a área que contém o ponto (ou a mais próxima, para coordenada no limite)
  with novo as (
    select u.id, (select t.id from iara.territories t where t.kind = 'AREA_PONDERACAO' and t.geom is not null
                  order by st_covers(t.geom, u.location) desc, st_distance(t.geom, u.location), t.sort limit 1) as ap
    from iara.education_units u)
  update iara.education_units u set macro_territory_id = n.ap from novo n where n.id = u.id and u.macro_territory_id is distinct from n.ap;
  get diagnostics v_unidades = row_count;

  -- bairros: a área que contém o centro do bairro
  with novo as (
    select b.id, (select t.id from iara.territories t where t.kind = 'AREA_PONDERACAO' and t.geom is not null
                  order by st_covers(t.geom, b.center) desc, st_distance(t.geom, b.center), t.sort limit 1) as ap
    from iara.territories b where b.kind = 'BAIRRO' and b.center is not null)
  update iara.territories b set parent_id = n.ap from novo n where n.id = b.id and b.parent_id is distinct from n.ap;
  get diagnostics v_bairros = row_count;

  -- endereços: a área que contém o ponto (ou, na fresta da malha, a mais próxima a até 150 m); fora de Maringá, sem área
  with novo as (select a.id, iara.area_do_ponto(a.location) as ap from iara.addresses a where a.location is not null)
  update iara.addresses a set territory_id = n.ap from novo n where n.id = a.id and a.territory_id is distinct from n.ap;
  get diagnostics v_enderecos = row_count;
  update iara.addresses set territory_id = null where territory_id = any (v_regionais);

  -- fila: a área da unidade pretendida (como em api.queue_entry_create)
  update iara.waiting_list_entries w set territory_id = u.macro_territory_id
  from iara.education_units u where u.id = w.preferred_unit_id and w.territory_id = any (v_regionais);
  get diagnostics v_fila = row_count;
  update iara.waiting_list_entries set territory_id = null where territory_id = any (v_regionais);

  -- órgãos da rede de proteção: cada macrorregião/distrito da competência vira as áreas que ficam dentro dela
  -- (ponto interior da área) e a área que contém o centro dela — nunca lista vazia, que significaria a cidade inteira
  update iara.orgaos_destinatarios o set territorio_ids = coalesce((
      select array_agg(distinct x order by x) from (
        select ap.id as x
        from unnest(o.territorio_ids) old_id
        join iara.territories m on m.id = old_id and m.kind in ('MACRORREGIAO', 'DISTRITO') and m.geom is not null
        join iara.territories ap on ap.kind = 'AREA_PONDERACAO' and ap.geom is not null
         and (st_covers(m.geom, st_pointonsurface(ap.geom::geometry)::geography) or (m.center is not null and st_covers(ap.geom, m.center)))
        union
        select old_id from unnest(o.territorio_ids) old_id where old_id <> all (v_regionais)) z), o.territorio_ids)
  where o.territorio_ids && v_regionais;
  get diagnostics v_orgaos = row_count;

  -- demonstração: os conselhos tutelares fictícios "por macrorregião" viram um só para as 29 áreas (como em
  -- iara.demo_gerar_busca_ativa); os encaminhamentos de demonstração passam para ele
  select id into v_ct from iara.orgaos_destinatarios
  where is_demo and tipo = 'CONSELHO_TUTELAR' and nome like 'Conselho Tutelar — %' order by nome limit 1;
  if v_ct is not null then
    update iara.encaminhamentos set orgao_id = v_ct
    where orgao_id in (select id from iara.orgaos_destinatarios
                       where is_demo and tipo = 'CONSELHO_TUTELAR' and nome like 'Conselho Tutelar — %' and id <> v_ct);
    delete from iara.orgaos_destinatarios where is_demo and tipo = 'CONSELHO_TUTELAR' and nome like 'Conselho Tutelar — %' and id <> v_ct;
    update iara.orgaos_destinatarios set nome = 'Conselho Tutelar de Maringá (demonstração)', competencia = 'Proteção de crianças e adolescentes do município',
           territorio_ids = array(select t.id from iara.territories t where t.kind = 'AREA_PONDERACAO' order by t.sort)
    where id = v_ct;
  end if;

  -- macrorregiões de demonstração: saem
  update iara.territories set parent_id = null
  where parent_id in (select id from iara.territories where kind = 'MACRORREGIAO');
  delete from iara.territories where kind = 'MACRORREGIAO';
  get diagnostics v_macros = row_count;

  perform set_config('iara.skip_audit', v_skip, true);
  v := jsonb_build_object('unidades', v_unidades, 'bairros', v_bairros, 'enderecos', v_enderecos, 'fila', v_fila,
                          'orgaos', v_orgaos, 'macrorregioes_removidas', v_macros,
                          'areas', (select count(*) from iara.territories where kind = 'AREA_PONDERACAO'),
                          'setores', (select count(*) from iara.setores_censitarios));
  perform iara.audit_event('TERRITORIO_REORGANIZADO', 'territories', 'areas_ponderacao', null,
    'Recorte territorial passou a ser a área de ponderação do IBGE (Censo 2022); macrorregiões de demonstração retiradas.', v);
  return v;
end $$;

revoke all on function iara.area_do_ponto(extensions.geography) from public;

-- endereços que ficaram na fresta na primeira aplicação (antes do seed 11 numa instalação nova, não há área: nada muda)
do $$
declare v_n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  with novo as (select a.id, iara.area_do_ponto(a.location) as ap from iara.addresses a where a.location is not null and a.territory_id is null)
  update iara.addresses a set territory_id = n.ap from novo n where n.id = a.id and n.ap is not null;
  get diagnostics v_n = row_count;
  perform set_config('iara.skip_audit', '', true);
  if v_n > 0 then
    perform iara.audit_event('TERRITORIO_REORGANIZADO', 'addresses', 'frestas_area_ponderacao', null,
      format('%s endereço(s) na fresta da malha recebeu(ram) a área de ponderação mais próxima (até 150 m).', v_n), jsonb_build_object('enderecos', v_n));
  end if;
end $$;

commit;
