-- IARA Educa — 080 · Área e setor do ponto: primeiro "quem contém", a distância só na fresta
-- iara.area_do_ponto e iara.setor_do_ponto mediam a distância até todo território num raio de 150 m antes de ver qual contém
-- o ponto. Nos quesitos do transporte (centenas de paradas e veículos) isso levava de 1,5 a 3,8 s. Agora a busca pelo
-- índice acha quem contém o ponto; só o ponto que cai na fresta da malha (raro) mede distância até 150 m. Mesmo resultado.
begin;

create or replace function iara.area_do_ponto(p_ponto extensions.geography) returns integer
language sql stable security definer set search_path = iara, extensions, public
as $$
  select coalesce(
    (select t.id from iara.territories t
     where p_ponto is not null and t.kind = 'AREA_PONDERACAO' and t.geom is not null and st_covers(t.geom, p_ponto)
     order by t.sort limit 1),
    (select t.id from iara.territories t
     where p_ponto is not null and t.kind = 'AREA_PONDERACAO' and t.geom is not null and st_dwithin(t.geom, p_ponto, 150)
     order by st_distance(t.geom, p_ponto), t.sort limit 1))
$$;

create or replace function iara.setor_do_ponto(p_ponto extensions.geography) returns text
language sql stable security definer set search_path = iara, extensions, public
as $$
  select coalesce(
    (select s.code from iara.setores_censitarios s where p_ponto is not null and st_covers(s.geom, p_ponto) order by s.code limit 1),
    (select s.code from iara.setores_censitarios s
     where p_ponto is not null and st_dwithin(s.geom, p_ponto, 150) order by st_distance(s.geom, p_ponto), s.code limit 1))
$$;

commit;
