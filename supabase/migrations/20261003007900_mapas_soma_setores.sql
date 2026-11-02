-- IARA Educa — 079 · Mapas: área como soma exata dos setores e índice espacial dos territórios
-- (1) No mapa unificado, a área de cada observação passa a ser a do seu setor censitário: assim a área mostra exatamente a
-- soma dos setores ao descer para eles (antes, a área vinha do contorno simplificado da área e podia divergir na borda —
-- ex.: AP 006 com 1.517 faltas e os setores dela com 1.509). (2) Índice espacial em iara.territories(geom): os quesitos do
-- transporte localizam cada parada e veículo e levavam de 1,9 a 5,6 s sem ele.
begin;

create index if not exists territories_geom_idx on iara.territories using gist (geom);

create or replace function api.mapa_recorte(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, extensions, public
as $$
declare
  v_camada text := coalesce(nullif(p ->> 'camada', ''), 'deficit');
  v_recorte text := coalesce(nullif(p ->> 'recorte', ''), 'area');
  v_area integer := nullif(p ->> 'area_id', '')::integer;
  v_min_soma constant integer := 3;  -- pela casa: menos de 3 pessoas no território não aparece
  v_min_taxa constant integer := 5;  -- pela casa, taxa: menos de 5 pessoas não aparece
  c record;
  r jsonb;
begin
  -- tipo: soma ou taxa (%) · casa: depende da casa da pessoa (sigilo) · pior: qual ponta é a ruim · publica: sem login
  select * into c from (values
    ('unidades', 'soma', false, ' unidade(s)', 'maior', true),
    ('vagas', 'soma', false, ' vaga(s)', 'menor', true),
    ('matriculas', 'soma', false, ' matrícula(s)', 'maior', true),
    ('fila', 'soma', false, ' na fila', 'maior', true),
    ('deficit', 'soma', false, '', 'menor', true),
    ('criancas_0a4', 'soma', false, ' criança(s)', 'maior', true),
    ('pessoas', 'soma', false, ' morador(es)', 'maior', true),
    ('fila_casa', 'soma', true, ' criança(s)', 'maior', false),
    ('transporte_necessidade', 'soma', true, ' criança(s)', 'maior', false),
    ('transporte_oferta', 'soma', false, ' aluno(s)', 'menor', false),
    ('transporte_efetividade', 'taxa', false, '%', 'menor', false),
    ('transporte_veiculos', 'soma', false, ' veículo(s)', 'maior', false),
    ('frequencia', 'taxa', true, '%', 'menor', false),
    ('faltas', 'soma', true, ' falta(s)', 'maior', false),
    ('ocorrencias', 'soma', true, ' ocorrência(s)', 'maior', false),
    ('alfa_esperado', 'taxa', true, '%', 'menor', false),
    ('alfa_precoce', 'soma', true, ' criança(s)', 'maior', false),
    ('alfa_abaixo', 'soma', true, ' criança(s)', 'maior', false),
    ('cadastros', 'taxa', true, '%', 'menor', false),
    ('formacao', 'taxa', false, '%', 'menor', false)
  ) q(camada, tipo, casa, sufixo, pior, publica) where q.camada = v_camada;
  if not found then
    raise exception 'Quesito desconhecido.' using errcode = '22023';
  end if;
  if v_recorte not in ('area', 'setor') then
    raise exception 'Recorte inválido: use area ou setor.' using errcode = '22023';
  end if;
  if not c.publica then
    perform iara.require_perm('kpi.network');
  end if;

  with ob as (
    -- Censo 2022: direto dos setores (crianças de 0 a 4 em sigilo ficam nulas)
    select s.area_ponderacao_id area, s.code setor, (case v_camada when 'pessoas' then s.pessoas else s.criancas_0a4 end)::numeric num,
           null::numeric den, 0 pessoas, (v_camada = 'criancas_0a4' and s.criancas_0a4 is null) sigilo
    from iara.setores_censitarios s where v_camada in ('criancas_0a4', 'pessoas')
    union all
    select o.area, o.setor, o.num, o.den, o.pessoas, false from iara.mapa_obs(v_camada) o where v_camada not in ('criancas_0a4', 'pessoas')),
  -- área = a do setor da observação (hierarquia do IBGE: a área é a soma exata dos seus setores); sem setor, a do ponto
  ob2 as (
    select coalesce(s.area_ponderacao_id, ob.area) area, ob.setor, ob.num, ob.den, ob.pessoas, ob.sigilo
    from ob left join iara.setores_censitarios s on s.code = ob.setor),
  ch as (
    select case when v_recorte = 'area' then ob.area::text else ob.setor end chave, ob.*
    from ob2 ob
    where (v_recorte = 'area' and ob.area is not null)
       or (v_recorte = 'setor' and ob.setor is not null
           and (v_area is null or exists (select 1 from iara.setores_censitarios s where s.code = ob.setor and s.area_ponderacao_id = v_area)))),
  ag as (
    select chave, sum(num) soma, sum(den) base, sum(pessoas) pessoas, bool_or(sigilo) sigilo, count(*) obs from ch group by chave),
  vl as (
    select chave, pessoas, base, obs,
           case when sigilo and soma is null then null
                when c.casa and c.tipo = 'soma' and pessoas < v_min_soma then null
                when c.casa and c.tipo = 'taxa' and pessoas < v_min_taxa then null
                when c.tipo = 'taxa' then round(100.0 * soma / nullif(base, 0), 1)
                else soma end valor,
           (sigilo and soma is null) or (c.casa and pessoas < case when c.tipo = 'taxa' then v_min_taxa else v_min_soma end) oculto
    from ag)
  select jsonb_build_object(
    'camada', v_camada, 'recorte', v_recorte, 'area_id', v_area, 'tipo', c.tipo, 'sufixo', c.sufixo, 'pior', c.pior, 'pela_casa', c.casa,
    'minimo', case when c.casa then case when c.tipo = 'taxa' then v_min_taxa else v_min_soma end end,
    'itens', coalesce((select jsonb_agg(jsonb_build_object('chave', chave, 'valor', valor, 'n', case when c.tipo = 'taxa' then base else pessoas end, 'oculto', oculto)
                                         order by chave) from vl), '[]'::jsonb),
    'total', (select case when c.tipo = 'taxa' then round(100.0 * sum(soma) / nullif(sum(base), 0), 1) else sum(soma) end from ag),
    'ocultos', (select count(*) from vl where oculto),
    'nota', case when c.casa then format('Pela casa da pessoa: território com menos de %s pessoas fica em branco (sigilo).',
                                         case when c.tipo = 'taxa' then v_min_taxa else v_min_soma end)
                 when v_camada in ('criancas_0a4', 'pessoas') then 'IBGE, Censo Demográfico 2022: agregados por setor censitário. Setor em branco = sigilo do IBGE.'
                 else 'Pelo ponto da unidade, da parada ou do veículo.' end,
    'atualizado_em', now()) into r;
  return r;
end $$;

commit;
