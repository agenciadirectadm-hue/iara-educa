-- IARA Educa — Listas de Alunos e Responsáveis mais rápidas, com o mesmo resultado.
-- As listas calculavam a matrícula de toda a rede mesmo sem filtro que dependesse dela, ordenavam pela função que remove acentos
-- (que o Postgres não consegue embutir na consulta) e guardavam os dados de exibição de todos para mostrar 40.
-- Agora a matrícula só entra quando um filtro precisa dela, a ordenação usa norm_ordem, e a exibição é buscada só para a página.
-- O plano é refeito a cada chamada, para que `v_q` e `v_mat` sejam conhecidos e o índice de nome possa ser usado.
begin;

-- Mesmo valor de iara.norm(), em versão STABLE: assim o Postgres embute na consulta e ordena cerca de três vezes mais rápido.
-- Não serve para índice, que exige IMMUTABLE: filtros que usam índice continuam com iara.norm().
create or replace function iara.norm_ordem(text) returns text
language sql stable parallel safe
as $f$ select lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce($1, ''))) $f$;
revoke execute on function iara.norm_ordem(text) from public, anon, authenticated;

-- Nome social também é pesquisado: sem índice, qualquer busca por nome voltava a ler a tabela inteira.
create index if not exists students_social_trgm_idx on iara.students using gin (iara.norm(coalesce(social_name, '')) extensions.gin_trgm_ops);
create index if not exists guardians_social_trgm_idx on iara.guardians using gin (iara.norm(coalesce(social_name, '')) extensions.gin_trgm_ops);
-- Busca por número: matrícula, CPF e INEP por igualdade; telefone pelo final, com trigramas.
create index if not exists students_inep_idx on iara.students (inep_id) where inep_id is not null;
create index if not exists guardians_fone_trgm_idx on iara.guardians using gin (iara.digitos(primary_phone) extensions.gin_trgm_ops);
create index if not exists guardians_whatsapp_trgm_idx on iara.guardians using gin (iara.digitos(whatsapp_phone) extensions.gin_trgm_ops);

CREATE OR REPLACE FUNCTION api.alunos_lista(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'iara', 'extensions', 'public'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare
  v_scope text := iara.my_scope();
  v_unit integer := iara.my_unit();
  v_q text := nullif(btrim(iara.norm(coalesce(p ->> 'q', ''))), '');
  v_dig text := iara.digitos(p ->> 'q');
  v_sit text := nullif(p ->> 'situacao', '');
  v_un integer := nullif(p ->> 'unidade_id', '')::int;
  v_terr integer := nullif(p ->> 'territorio_id', '')::int;
  v_pend boolean := coalesce((p ->> 'pendentes')::boolean, false);
  v_item text := nullif(p ->> 'pendencia', '');
  v_ordem text := coalesce(nullif(p ->> 'ordem', ''), 'nome');
  v_sexo text := nullif(p ->> 'sexo', '');
  v_idmin integer := nullif(p ->> 'idade_min', '')::int;
  v_idmax integer := nullif(p ->> 'idade_max', '')::int;
  v_serie smallint := nullif(p ->> 'serie_id', '')::smallint;
  v_turno text := nullif(p ->> 'turno', '');
  v_turma uuid := nullif(p ->> 'turma_id', '')::uuid;
  v_restr text := nullif(p ->> 'restricao', '');
  v_ocor text := nullif(p ->> 'ocorrencias', '');
  v_aee boolean := coalesce((p ->> 'aee')::boolean, false);
  v_lim integer := least(greatest(coalesce(nullif(p ->> 'limite', '')::int, 40), 1), 100);
  v_off integer := greatest(coalesce(nullif(p ->> 'offset', '')::int, 0), 0);
  -- a matrícula só entra no cálculo geral quando algum filtro depende dela; a página busca a dela no fim
  v_mat boolean := v_un is not null or v_serie is not null or v_turno is not null or v_turma is not null;
  v jsonb;
begin
  perform iara.require_perm('students.read');
  if v_scope is null or v_scope not in ('NETWORK', 'UNIT') then
    raise exception 'O cadastro de alunos é da Secretaria e das unidades.' using errcode = '42501';
  end if;
  if v_dig is not null and length(v_dig) < 4 then v_dig := null; end if;
  with base as materialized (
    select s.id, s.full_name, s.birth_date, s.gender, s.status, s.aee_status, s.updated_at, a.territory_id, a.geocode_precision,
           mat.unit_id as mat_unit, mat.class_id, mat.grade_level_id, mat.shift,
           iara.aluno_pendencias(s, s.id in (select sg.student_id from iara.student_guardians sg where sg.end_date is null)) as pend
    from iara.students s
    left join iara.addresses a on a.id = s.address_id
    left join (select distinct on (e.student_id) e.student_id, e.unit_id, c.id as class_id, c.grade_level_id, c.shift
               from iara.enrollments e join iara.classes c on c.id = e.class_id
               where v_mat and e.status = 'ACTIVE' order by e.student_id, e.enrollment_date desc) mat on mat.student_id = s.id
    where (v_scope = 'NETWORK' or s.id in (select iara.unidade_alunos(v_unit)))
      and (v_q is null
           or iara.norm(s.full_name) like '%' || v_q || '%'
           or iara.norm(coalesce(s.social_name, '')) like '%' || v_q || '%'
           or (v_dig is not null and (s.student_registry_number = v_dig or (s.cpf is not null and iara.digitos(s.cpf) = v_dig) or s.inep_id = v_dig)))
  ),
  filt as (
    select b.* from base b
    where (v_sit is null or b.status = v_sit)
      and (v_un is null or b.mat_unit = v_un)
      and (v_terr is null or b.territory_id = v_terr)
      and (not v_pend or cardinality(b.pend) > 0)
      and (v_item is null or v_item = any (b.pend))
      and (v_sexo is null or b.gender = v_sexo)
      and (v_idmin is null or b.birth_date <= (current_date - make_interval(years => v_idmin))::date)
      and (v_idmax is null or b.birth_date > (current_date - make_interval(years => v_idmax + 1))::date)
      and (v_serie is null or b.grade_level_id = v_serie)
      and (v_turno is null or b.shift = v_turno)
      and (v_turma is null or b.class_id = v_turma)
      and (not v_aee or b.aee_status)
      and (v_restr is null or exists (select 1 from iara.aluno_restricoes ar where ar.student_id = b.id and ar.situacao <> 'RECUSADA'
                                        and (v_restr = 'QUALQUER' or ar.restricao_codigo = v_restr)))
      and (v_ocor is null or exists (select 1 from iara.ocorrencias o where o.student_id = b.id
                                       and (v_ocor = 'QUALQUER' or (v_ocor = 'ABERTAS' and o.situacao <> 'ENCERRADA')
                                            or (v_ocor = 'FAMILIA' and o.origem = 'FAMILIA'))))
  ),
  pagina as (
    select x.id, x.pend, row_number() over () as ord from (
      select f.id, f.pend from filt f
      order by case when v_ordem = 'pendencias' then -cardinality(f.pend) else 0 end,
               case when v_ordem = 'recentes' then -extract(epoch from f.updated_at) else 0 end,
               case when v_ordem = 'idade' then f.birth_date end desc,
               iara.norm_ordem(f.full_name), f.id
      limit v_lim offset v_off) x
  )
  select jsonb_build_object(
    'escopo', v_scope,
    'unidade', (select u.name from iara.education_units u where u.id = v_unit),
    'pode_editar', iara.has_perm('students.write'),
    'total', (select count(*) from filt),
    'contagem', (select jsonb_build_object('todos', count(*), 'completos', count(*) filter (where cardinality(pend) = 0),
        'pendentes', count(*) filter (where cardinality(pend) > 0),
        'MATRICULADO', count(*) filter (where status = 'MATRICULADO'), 'AGUARDANDO_VAGA', count(*) filter (where status = 'AGUARDANDO_VAGA'),
        'SEM_VINCULO', count(*) filter (where status = 'SEM_VINCULO'), 'TRANSFERENCIA', count(*) filter (where status = 'TRANSFERENCIA'),
        'INATIVO', count(*) filter (where status = 'INATIVO'),
        'aproximada', count(*) filter (where iara.endereco_aproximado(geocode_precision))) from base),
    'pendencias_frequentes', (select coalesce(jsonb_agg(jsonb_build_object('item', z.item, 'n', z.n) order by z.n desc, z.item), '[]'::jsonb)
                              from (select unnest(pend) as item, count(*) as n from base group by 1) z),
    'turmas', case when coalesce(v_un, case when v_scope = 'UNIT' then v_unit end) is not null then
                (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.class_name, 'turno', c.shift) order by c.class_name), '[]')
                 from iara.classes c where c.unit_id = coalesce(v_un, v_unit) and c.status = 'ATIVA') end,
    'itens', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', g.id, 'nome', st.full_name, 'nome_social', st.social_name, 'nascimento', st.birth_date, 'idade', iara.age_text(st.birth_date),
        'sexo', st.gender, 'situacao', st.status, 'registro', st.student_registry_number, 'avatar_seed', st.avatar_seed,
        'unidade', case when m.unit_id is not null then jsonb_build_object('id', m.unit_id, 'nome', m.unit_name, 'turma', m.class_name, 'turma_id', m.class_id) end,
        'bairro', ad.neighborhood, 'territorio', (select t.name from iara.territories t where t.id = ad.territory_id),
        'localizacao_aproximada', iara.endereco_aproximado(ad.geocode_precision),
        'pendencias', to_jsonb(g.pend), 'completo_pct', round(100.0 * (7 - cardinality(g.pend)) / 7),
        'aee', st.aee_status, 'ficticio', st.is_demo,
        'restricoes', (select coalesce(jsonb_agg(split_part(ra.descricao, ' (', 1) order by ra.ordem), '[]')
                       from iara.aluno_restricoes ar join iara.restricoes_alimentares ra on ra.codigo = ar.restricao_codigo
                       where ar.student_id = g.id and ar.situacao <> 'RECUSADA'),
        'ocorrencias_abertas', (select count(*) from iara.ocorrencias o where o.student_id = g.id and o.situacao <> 'ENCERRADA'),
        'responsavel', (select jsonb_build_object('id', gg.id, 'nome', gg.full_name, 'parentesco', sg.relationship)
                        from iara.student_guardians sg join iara.guardians gg on gg.id = sg.guardian_id
                        where sg.student_id = g.id and sg.end_date is null order by sg.is_primary desc, sg.relationship limit 1))
      order by g.ord), '[]'::jsonb)
      from pagina g
      join iara.students st on st.id = g.id
      left join iara.addresses ad on ad.id = st.address_id
      left join lateral (select e.unit_id, u.short_name as unit_name, c.class_name, c.id as class_id
                         from iara.enrollments e join iara.education_units u on u.id = e.unit_id join iara.classes c on c.id = e.class_id
                         where e.student_id = g.id and e.status = 'ACTIVE' order by e.enrollment_date desc limit 1) m on true)
  ) into v;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION api.responsaveis_lista(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'iara', 'extensions', 'public'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare
  v_scope text := iara.my_scope();
  v_unit integer := iara.my_unit();
  v_contatos boolean := iara.can_see_contacts();
  v_q text := nullif(btrim(iara.norm(coalesce(p ->> 'q', ''))), '');
  v_dig text := iara.digitos(p ->> 'q');
  v_terr integer := nullif(p ->> 'territorio_id', '')::int;
  v_pend boolean := coalesce((p ->> 'pendentes')::boolean, false);
  v_item text := nullif(p ->> 'pendencia', '');
  v_cad boolean := coalesce((p ->> 'cadunico')::boolean, false);
  v_ordem text := coalesce(nullif(p ->> 'ordem', ''), 'nome');
  v_lim integer := least(greatest(coalesce(nullif(p ->> 'limite', '')::int, 40), 1), 100);
  v_off integer := greatest(coalesce(nullif(p ->> 'offset', '')::int, 0), 0);
  v jsonb;
begin
  perform iara.require_perm('guardians.read');
  if v_scope is null or v_scope not in ('NETWORK', 'UNIT') then
    raise exception 'O cadastro de responsáveis é da Secretaria e das unidades.' using errcode = '42501';
  end if;
  if v_dig is not null and length(v_dig) < 4 then v_dig := null; end if;
  with base as materialized (
    select g.id, g.full_name, g.cadunico_status, g.updated_at, a.territory_id, a.geocode_precision, iara.responsavel_pendencias(g) as pend
    from iara.guardians g
    left join iara.addresses a on a.id = g.address_id
    where (v_scope = 'NETWORK' or g.id in (select iara.unidade_responsaveis(v_unit)))
      and (v_q is null
           or iara.norm(g.full_name) like '%' || v_q || '%'
           or iara.norm(coalesce(g.social_name, '')) like '%' || v_q || '%'
           or (v_dig is not null and ((g.cpf is not null and iara.digitos(g.cpf) = v_dig)
               or (v_contatos and (iara.digitos(g.primary_phone) like '%' || v_dig or iara.digitos(g.whatsapp_phone) like '%' || v_dig)))))
  ),
  filt as (
    select b.* from base b
    where (v_terr is null or b.territory_id = v_terr)
      and (not v_pend or cardinality(b.pend) > 0)
      and (v_item is null or v_item = any (b.pend))
      and (not v_cad or b.cadunico_status)
  ),
  pagina as (
    select x.id, x.pend, row_number() over () as ord from (
      select f.id, f.pend from filt f
      order by case when v_ordem = 'pendencias' then -cardinality(f.pend) else 0 end,
               case when v_ordem = 'recentes' then -extract(epoch from f.updated_at) else 0 end,
               iara.norm_ordem(f.full_name), f.id
      limit v_lim offset v_off) x
  )
  select jsonb_build_object(
    'escopo', v_scope,
    'unidade', (select u.name from iara.education_units u where u.id = v_unit),
    'pode_editar', iara.has_perm('guardians.write'),
    'contatos_mascarados', not v_contatos,
    'total', (select count(*) from filt),
    'contagem', (select jsonb_build_object('todos', count(*), 'completos', count(*) filter (where cardinality(pend) = 0),
        'pendentes', count(*) filter (where cardinality(pend) > 0), 'cadunico', count(*) filter (where cadunico_status),
        'aproximada', count(*) filter (where iara.endereco_aproximado(geocode_precision))) from base),
    'pendencias_frequentes', (select coalesce(jsonb_agg(jsonb_build_object('item', z.item, 'n', z.n) order by z.n desc, z.item), '[]'::jsonb)
                              from (select unnest(pend) as item, count(*) as n from base group by 1) z),
    'itens', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', g.id, 'nome', gu.full_name, 'nome_social', gu.social_name,
        'cpf', case when v_contatos then gu.cpf else iara.mask_cpf(gu.cpf) end,
        'telefone', case when v_contatos then coalesce(gu.whatsapp_phone, gu.primary_phone) else iara.mask_phone(coalesce(gu.whatsapp_phone, gu.primary_phone)) end,
        'cadunico', gu.cadunico_status, 'mae_solo', gu.single_mother,
        'bairro', ad.neighborhood, 'territorio', (select t.name from iara.territories t where t.id = ad.territory_id),
        'localizacao_aproximada', iara.endereco_aproximado(ad.geocode_precision),
        'pendencias', to_jsonb(g.pend), 'completo_pct', round(100.0 * (5 - cardinality(g.pend)) / 5), 'ficticio', gu.is_demo,
        'criancas', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.full_name, 'idade', iara.age_text(s.birth_date),
                                                                  'parentesco', sg.relationship, 'avatar_seed', s.avatar_seed) order by s.birth_date), '[]'::jsonb)
                     from iara.student_guardians sg join iara.students s on s.id = sg.student_id
                     where sg.guardian_id = g.id and sg.end_date is null))
      order by g.ord), '[]'::jsonb)
      from pagina g
      join iara.guardians gu on gu.id = g.id
      left join iara.addresses ad on ad.id = gu.address_id)
  ) into v;
  return v;
end $function$;

commit;
