-- IARA Educa — 077 · Mapas por área de ponderação e por setor censitário
-- O mapa unificado (Mapa + Mapas de calor) detalha todo quesito em três recortes: pontos (como antes), as 29 áreas de
-- ponderação e os 793 setores censitários do IBGE. Cada quesito vira um conjunto de observações (iara.mapa_obs) somadas
-- por território (api.mapa_recorte). O que depende da casa da pessoa só aparece com 3 ou mais pessoas no território
-- (taxa: 5 ou mais); o que é da escola, da rota ou do Censo aparece sempre.
-- Cada endereço guarda o setor do ponto (como já guarda a área), preenchido sozinho quando o ponto muda.
begin;

-- ---------------------------------------------------------------------------
-- 1. Setor do ponto e território de cada endereço
-- ---------------------------------------------------------------------------
-- o setor que contém o ponto ou, na fresta da malha simplificada, o mais próximo a até 150 m (como iara.area_do_ponto)
create or replace function iara.setor_do_ponto(p_ponto extensions.geography) returns text
language sql stable security definer set search_path = iara, extensions, public
as $$
  select s.code from iara.setores_censitarios s
  where p_ponto is not null and st_dwithin(s.geom, p_ponto, 150)
  order by st_covers(s.geom, p_ponto) desc, st_distance(s.geom, p_ponto), s.code limit 1
$$;

alter table iara.addresses add column if not exists setor_censitario text;
create index if not exists addresses_setor_idx on iara.addresses(setor_censitario);
insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('addresses', 'setor_censitario', 'PESSOAL', 'localização', 'recorte territorial (setor censitário do IBGE) dos mapas agregados',
   'só sai somado, com 3 ou mais pessoas no setor')
on conflict (tabela, coluna) do nothing;

-- área e setor seguem o ponto em qualquer caminho de gravação (cadastro, IARA, carga, demonstração)
create or replace function iara.endereco_territorio() returns trigger
language plpgsql security definer set search_path = iara, extensions, public
as $$
begin
  if new.location is null then
    new.setor_censitario := null;
  elsif tg_op = 'INSERT' or new.location is distinct from old.location or new.setor_censitario is null then
    new.territory_id := iara.area_do_ponto(new.location);
    new.setor_censitario := iara.setor_do_ponto(new.location);
  end if;
  return new;
end $$;
drop trigger if exists addresses_territorio on iara.addresses;
create trigger addresses_territorio before insert or update of location on iara.addresses
  for each row execute function iara.endereco_territorio();

-- endereços já gravados
do $$
begin
  perform set_config('iara.skip_audit', 'on', true);
  with novo as (select a.id, iara.setor_do_ponto(a.location) setor from iara.addresses a where a.location is not null)
  update iara.addresses a set setor_censitario = n.setor from novo n where n.id = a.id and a.setor_censitario is distinct from n.setor;
  perform set_config('iara.skip_audit', '', true);
end $$;

-- área (vínculo da unidade) e setor (pelo ponto) de cada unidade da rede
create or replace function iara.unidades_territorio() returns table (id integer, area integer, setor text)
language sql stable security definer set search_path = iara, extensions, public
as $$
  select u.id, u.macro_territory_id, iara.setor_do_ponto(u.location) from iara.education_units u
$$;

-- ---------------------------------------------------------------------------
-- 2. Observações de cada quesito: área e setor de cada uma, valor (num), base da taxa (den) e pessoas por trás
-- ---------------------------------------------------------------------------
create or replace function iara.mapa_obs(p_camada text)
returns table (area integer, setor text, num numeric, den numeric, pessoas integer)
language plpgsql stable security definer set search_path = iara, extensions, public
as $$
declare
  v_hoje date := iara.hoje_local();
  v_raio double precision := coalesce(nullif(iara.setting('default_radius_m'), '')::numeric, 2000) / 1000.0;
  v_ano integer := extract(year from iara.hoje_local())::int;
begin
  case p_camada
  -- Censo: vem direto dos setores (api.mapa_recorte), sem observação aqui
  when 'criancas_0a4', 'pessoas' then
    return;
  -- Rede e vagas (ponto da unidade)
  when 'unidades' then
    return query select t.area, t.setor, 1::numeric, null::numeric, 0 from iara.unidades_territorio() t;
  when 'vagas' then
    return query select t.area, t.setor, coalesce(sum(c.offerable_vacancies_count), 0)::numeric, null::numeric, 0
      from iara.unidades_territorio() t left join iara.classes c on c.unit_id = t.id group by t.id, t.area, t.setor;
  when 'matriculas' then
    return query select t.area, t.setor, coalesce(u.public_enrollments, 0)::numeric, null::numeric, 0
      from iara.unidades_territorio() t join iara.education_units u on u.id = t.id;
  when 'fila' then
    return query select t.area, t.setor, count(*)::numeric, null::numeric, 0
      from iara.waiting_list_entries w join iara.unidades_territorio() t on t.id = w.preferred_unit_id
      where w.status in ('WAITING', 'OFFERED') group by t.id, t.area, t.setor;
  when 'deficit' then
    -- saldo de creche da unidade (vagas ofertáveis de creche − crianças aguardando creche nela), como em api.geo_layers
    return query select t.area, t.setor,
        (coalesce((select sum(c.offerable_vacancies_count) from iara.classes c where c.unit_id = t.id and c.grade_level_id = 1), 0)
         - (select count(*) from iara.waiting_list_entries w where w.preferred_unit_id = t.id and w.grade_level_id = 1 and w.status in ('WAITING', 'OFFERED')))::numeric,
        null::numeric, 0
      from iara.unidades_territorio() t;
  -- Demanda pela casa da criança
  when 'fila_casa' then
    return query select a.territory_id, a.setor_censitario, 1::numeric, null::numeric, 1
      from iara.waiting_list_entries w join iara.students s on s.id = w.student_id join iara.addresses a on a.id = s.address_id
      where w.status in ('WAITING', 'OFFERED') and a.location is not null;
  -- Transporte
  when 'transporte_necessidade' then
    return query select a.territory_id, a.setor_censitario, 1::numeric, null::numeric, 1
      from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
      join iara.addresses a on a.id = s.address_id join iara.education_units u on u.id = e.unit_id
      where a.location is not null
        and not exists (select 1 from iara.transporte_alunos ta where ta.student_id = s.id and ta.fim is null)
        and (s.school_transport_status = 'AGUARDANDO'
             or iara.km_entre(extensions.st_y(a.location::extensions.geometry), extensions.st_x(a.location::extensions.geometry), u.lat, u.lng) > v_raio);
  when 'transporte_oferta' then
    return query select iara.area_do_ponto(iara.point(p2.lat, p2.lng)), iara.setor_do_ponto(iara.point(p2.lat, p2.lng)), count(ta.id)::numeric, null::numeric, 0
      from iara.transporte_pontos p2 join iara.transporte_rotas r2 on r2.id = p2.rota_id and r2.situacao = 'ATIVA'
      left join iara.transporte_alunos ta on ta.ponto_id = p2.id and ta.fim is null
      group by p2.id, p2.lat, p2.lng;
  when 'transporte_efetividade' then
    -- cada rota divide transportados e previstos (30 dias) igualmente entre os seus pontos de parada
    return query
      with ef as (select r2.id, sum(v.alunos_previstos)::numeric prev, sum(coalesce(v.alunos_transportados, 0))::numeric transp,
                         (select count(*) from iara.transporte_pontos p3 where p3.rota_id = r2.id) npt
                  from iara.transporte_rotas r2 join iara.transporte_viagens v on v.rota_id = r2.id and v.data >= v_hoje - 30 and v.data < v_hoje
                  where r2.situacao = 'ATIVA' group by r2.id)
      select iara.area_do_ponto(iara.point(p2.lat, p2.lng)), iara.setor_do_ponto(iara.point(p2.lat, p2.lng)), ef.transp / ef.npt, ef.prev / ef.npt, 0
      from ef join iara.transporte_pontos p2 on p2.rota_id = ef.id where ef.npt > 0 and ef.prev > 0;
  when 'transporte_veiculos' then
    -- veículos das rotas ativas na posição simulada de agora (mesma regra de api.mapa_calor)
    return query
      with ro as (select r2.id, u.lat ulat, u.lng ulng, iara.transporte_estado(r2.id, 'IDA') ida, iara.transporte_estado(r2.id, 'VOLTA') volta,
                         (select jsonb_build_object('lat', p2.lat, 'lng', p2.lng) from iara.transporte_pontos p2 where p2.rota_id = r2.id order by p2.ordem limit 1) inicio
                  from iara.transporte_rotas r2 join iara.education_units u on u.id = r2.unit_id where r2.situacao = 'ATIVA'),
           pp as (select coalesce((coalesce(volta -> 'posicao', ida -> 'posicao') ->> 'lat')::double precision,
                                  case when ida ->> 'situacao' = 'CONCLUIDA' and volta ->> 'situacao' = 'PREVISTA' then ulat else (inicio ->> 'lat')::double precision end, ulat) lat,
                         coalesce((coalesce(volta -> 'posicao', ida -> 'posicao') ->> 'lng')::double precision,
                                  case when ida ->> 'situacao' = 'CONCLUIDA' and volta ->> 'situacao' = 'PREVISTA' then ulng else (inicio ->> 'lng')::double precision end, ulng) lng
                  from ro)
      select iara.area_do_ponto(iara.point(pp.lat, pp.lng)), iara.setor_do_ponto(iara.point(pp.lat, pp.lng)), 1::numeric, null::numeric, 0 from pp;
  -- Frequência e ocorrências (pela casa do aluno)
  when 'frequencia' then
    return query
      with reg as (select r2.id, r2.class_id from iara.frequencia_registros r2 where r2.data >= v_hoje - 30),
           poss as (select e.student_id, count(*) n from reg join iara.enrollments e on e.class_id = reg.class_id and e.status = 'ACTIVE' group by 1),
           fal as (select f.student_id, count(*) n from iara.frequencia_faltas f join reg on reg.id = f.registro_id group by 1)
      select a.territory_id, a.setor_censitario, (poss.n - coalesce(fal.n, 0))::numeric, poss.n::numeric, 1
      from poss join iara.students s on s.id = poss.student_id join iara.addresses a on a.id = s.address_id
      left join fal on fal.student_id = poss.student_id where a.location is not null;
  when 'faltas' then
    return query
      with fa as (select f.student_id, count(*) n from iara.frequencia_faltas f join iara.frequencia_registros r2 on r2.id = f.registro_id
                  where r2.data >= v_hoje - 30 and f.tipo = 'FALTA' group by 1)
      select a.territory_id, a.setor_censitario, coalesce(fa.n, 0)::numeric, null::numeric, 1
      from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' join iara.addresses a on a.id = s.address_id
      left join fa on fa.student_id = s.id where a.location is not null;
  when 'ocorrencias' then
    return query
      with oc as (select o.student_id, count(*) n from iara.ocorrencias o
                  where o.ocorrida_em >= now() - interval '90 days' and o.tipo <> 'ELOGIO' group by 1)
      select a.territory_id, a.setor_censitario, oc.n::numeric, null::numeric, 1
      from oc join iara.students s on s.id = oc.student_id join iara.addresses a on a.id = s.address_id where a.location is not null;
  -- Alfabetização na idade esperada (pela casa da criança avaliada)
  when 'alfa_esperado', 'alfa_precoce', 'alfa_abaixo' then
    return query
      with so as (select distinct on (x.student_id) x.student_id, x.nivel,
                         ((extract(year from age(x.data, s.birth_date)) * 12 + extract(month from age(x.data, s.birth_date))))::int meses
                  from iara.alfabetizacao_sondagens x join iara.students s on s.id = x.student_id
                  join iara.enrollments e on e.student_id = x.student_id and e.status = 'ACTIVE'
                  where x.ano = v_ano order by x.student_id, x.data desc),
           sx as (select so.student_id, iara.alfa_situacao_idade(so.nivel, so.meses) sit from so)
      select a.territory_id, a.setor_censitario,
             (case p_camada when 'alfa_esperado' then (sx.sit <> 'ABAIXO')::int when 'alfa_precoce' then (sx.sit = 'PRECOCE')::int else (sx.sit = 'ABAIXO')::int end)::numeric,
             case when p_camada = 'alfa_esperado' then 1::numeric end, 1
      from sx join iara.students s on s.id = sx.student_id join iara.addresses a on a.id = s.address_id where a.location is not null;
  -- Cadastros completos (pela casa; sem endereço no mapa, no ponto da escola)
  when 'cadastros' then
    return query
      with al as (select s.id, e.unit_id, s.address_id,
                         cardinality(iara.aluno_pendencias(s, exists (select 1 from iara.student_guardians sg where sg.student_id = s.id and sg.end_date is null))) = 0
                         and not exists (select 1 from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
                                         where sg.student_id = s.id and sg.end_date is null and sg.is_primary and cardinality(iara.responsavel_pendencias(g)) > 0) ok
                  from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE')
      select coalesce(a.territory_id, t.area), case when a.location is not null then a.setor_censitario else t.setor end, al.ok::int::numeric, 1::numeric, 1
      from al left join iara.addresses a on a.id = al.address_id join iara.unidades_territorio() t on t.id = al.unit_id;
  -- Formação dos professores (ponto da escola)
  when 'formacao' then
    return query
      with pf as (select st.unit_id, iara.formacao_nivel(st.escolaridade) nv from iara.staff st
                  where st.role in ('PROFESSOR', 'EDUCADOR', 'AEE') and coalesce(st.situacao, 'ATIVO') = 'ATIVO' and st.unit_id is not null)
      select t.area, t.setor, (pf.nv >= 4)::int::numeric, (pf.nv is not null)::int::numeric, 0
      from pf join iara.unidades_territorio() t on t.id = pf.unit_id;
  else
    raise exception 'Quesito desconhecido.' using errcode = '22023';
  end case;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Quesito por área de ponderação ou por setor censitário
-- ---------------------------------------------------------------------------
-- p: camada, recorte ('area' | 'setor'), area_id (opcional: só os setores dessa área — o detalhamento ao tocar numa área)
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
  ch as (
    select case when v_recorte = 'area' then ob.area::text else ob.setor end chave, ob.*
    from ob
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

revoke all on function iara.setor_do_ponto(extensions.geography), iara.endereco_territorio(), iara.mapa_obs(text), iara.unidades_territorio() from public;

commit;
