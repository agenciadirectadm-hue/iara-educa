-- =============================================================================
-- IARA Educa · Perfil "Controle externo" — Ministério Público e Defensoria Pública
-- Pedido do usuário (05/10/2026): o MP e a Defensoria acompanham a fila sem depender da Secretaria — somente leitura e
-- sem dados pessoais:
--  1. Painel de conformidade: espera por faixa, vagas ofertáveis paradas em filas com crianças, ofertas na ordem ×
--     exceções (laudo, com justificativa), prazos, saldo por região, distâncias (três medidas) e trilha de governança
--  2. Fila pública anonimizada (código público da inscrição) com conferência automática da ordem de cada fila
--  3. Consulta de um caso SÓ com o protocolo informado pela família e o motivo (atendimento/procedimento) — o acesso
--     fica na auditoria e aparece na própria trilha do controle externo
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
-- =============================================================================
begin;

-- 1. Perfil e permissão ------------------------------------------------------------------------------------------
insert into iara.permissions (code, description, is_sensitive) values
('controle.read', 'Controle externo: conformidade da fila, fila anonimizada e consulta de caso por protocolo (registrada)', false)
on conflict (code) do update set description = excluded.description;

insert into iara.organizational_roles (code, tenant_id, name, short_name, description, scope_type, stage_filter, question, org_unit, is_persona, sort)
values ('CONTROLE_EXTERNO', 1, 'Controle externo · MP e Defensoria', 'Controle externo',
        'Ministério Público e Defensoria Pública: conferem a ordem da fila, as exceções, os prazos e os critérios — somente leitura e sem dados pessoais. Um caso só é aberto com o protocolo informado pela família, e o acesso fica registrado.',
        'AGGREGATE', null, 'A fila está sendo cumprida, com critérios claros?', 'Ministério Público · Defensoria Pública', true, 12)
on conflict (code) do update set name = excluded.name, short_name = excluded.short_name, description = excluded.description,
  scope_type = excluded.scope_type, question = excluded.question, org_unit = excluded.org_unit, is_persona = true, sort = excluded.sort;

insert into iara.role_permissions (role_code, permission_code) values
  ('CONTROLE_EXTERNO', 'units.read'), ('CONTROLE_EXTERNO', 'kpi.network'), ('CONTROLE_EXTERNO', 'quality.read'),
  ('CONTROLE_EXTERNO', 'classes.read'), ('CONTROLE_EXTERNO', 'config.read'), ('CONTROLE_EXTERNO', 'controle.read'),
  -- a Secretaria vê exatamente o que o controle externo vê
  ('SECRETARIO', 'controle.read'), ('SUPERINTENDENCIA', 'controle.read')
on conflict do nothing;

-- 2. Auxiliares ----------------------------------------------------------------------------------------------------
-- código público (pseudônimo) de uma inscrição: estável e sem relação com a identidade da criança
create or replace function iara.codigo_publico(p uuid) returns text
language sql immutable as $$ select case when p is null then null else 'F-' || upper(substr(md5('iara-fila:' || p::text), 1, 6)) end $$;

-- texto livre mostrado ao controle externo: sem CID, CPF e sem os nomes indicados
create or replace function iara.anonimizar(p_texto text, p_nomes text[] default '{}') returns text
language plpgsql immutable as $$
declare
  v text := coalesce(p_texto, '');
  n text;
begin
  v := regexp_replace(v, '\m[A-TV-Z][0-9]{2}(\.[0-9]{1,2})?\M', '[CID]', 'g');
  v := regexp_replace(v, '[0-9]{3}\.?[0-9]{3}\.?[0-9]{3}-?[0-9]{2}', '[CPF]', 'g');
  foreach n in array coalesce(p_nomes, '{}') loop
    if length(n) >= 3 then
      v := regexp_replace(v, '\m' || regexp_replace(n, '([.^$*+?()\[\]{}|\\])', '\\\1', 'g') || '\M', '[nome]', 'gi');
    end if;
  end loop;
  return v;
end $$;

-- nomes de uma pessoa (para ocultar em textos livres), a partir de uma inscrição da fila
create or replace function iara.nomes_da_inscricao(p_entry text) returns text[]
language sql stable security definer set search_path = iara, public
as $$
  select coalesce(string_to_array(s.full_name, ' '), '{}')
         || coalesce((select array_agg(x) from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id,
                      unnest(string_to_array(g.full_name, ' ')) x where sg.student_id = s.id), '{}')
  from iara.waiting_list_entries w join iara.students s on s.id = w.student_id
  where p_entry ~ '^[0-9a-f-]{36}$' and w.id = p_entry::uuid
$$;

-- tipo de uma oferta frente à ordem da fila (para a conformidade)
create or replace function iara.oferta_tipo(o iara.vacancy_offers) returns text
language sql stable security definer set search_path = iara, public
as $$
  select case
    when o.ranking_snapshot ->> 'priority_exception' = 'LAUDO' then 'LAUDO'
    when exists (select 1 from iara.waiting_list_entries w where w.id = o.waiting_list_entry_id and w.preferred_unit_id <> o.unit_id) then 'ALTERNATIVA'
    when coalesce(o.ranking_snapshot ->> 'position', o.ranking_snapshot ->> 'posicao') = '1'
      or coalesce(o.ranking_snapshot ->> 'motivo', '') like '1º da fila%' then 'NA_ORDEM'
    else 'SEM_REGISTRO' end
$$;

-- ordem de cada fila conferida pela regra (pontos, depois data de entrada): posição registrada = posição calculada
create or replace function iara.filas_conferencia() returns table (unit_id integer, grade_level_id smallint, aguardando bigint, conferida boolean)
language sql stable security definer set search_path = iara, public
as $$
  select x.preferred_unit_id, x.grade_level_id, count(*), bool_and(x.position is not distinct from x.rn)
  from (select preferred_unit_id, grade_level_id, position,
               row_number() over (partition by preferred_unit_id, grade_level_id order by priority_score desc, entered_at asc, id) as rn
        from iara.waiting_list_entries where status = 'WAITING') x
  group by 1, 2
$$;

-- exceção (laudo) cuja oferta existe. Em produção ofertas nunca são apagadas; na demonstração, a limpeza remove o que
-- sessões de teste fizeram — o registro de auditoria (imutável) fica, mas não entra nos números do painel
create or replace function iara.excecao_com_oferta(p_entry text) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select exists (select 1 from iara.vacancy_offers o
                 where o.waiting_list_entry_id::text = p_entry and o.ranking_snapshot ->> 'priority_exception' = 'LAUDO')
$$;

-- 3. Painel do controle externo --------------------------------------------------------------------------------------
create or replace function api.controle_painel(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_desde timestamptz := now() - interval '12 months';
  v_filas jsonb;
begin
  perform iara.require_perm('controle.read');
  select jsonb_build_object('filas', count(*), 'conferidas', count(*) filter (where conferida),
                            'divergentes', coalesce(jsonb_agg(jsonb_build_object('unidade', u.short_name, 'faixa', gl.name)) filter (where not conferida), '[]'::jsonb))
  into v_filas
  from iara.filas_conferencia() f join iara.education_units u on u.id = f.unit_id join iara.grade_levels gl on gl.id = f.grade_level_id;

  return jsonb_build_object(
    'gerado_em', now(),
    'regras', jsonb_build_object('versao', iara.rule_version(), 'medida_distancia', iara.medida_distancia_fila()),
    'ordem', v_filas,
    -- espera
    'fila', (select jsonb_build_object(
        'aguardando', count(*),
        'espera_media_dias', round(avg(current_date - w.entered_at::date)),
        'espera_mediana_dias', round(percentile_cont(0.5) within group (order by current_date - w.entered_at::date)),
        'espera_max_dias', max(current_date - w.entered_at::date),
        'mais_90', count(*) filter (where current_date - w.entered_at::date > 90),
        'mais_180', count(*) filter (where current_date - w.entered_at::date > 180),
        'laudo', count(*) filter (where 'PCD_TEA_AEE' = any (w.priority_flags)),
        'por_faixa', (select coalesce(jsonb_agg(jsonb_build_object('faixa', gl.name, 'curto', gl.short_name, 'aguardando', z.n, 'espera_media_dias', z.media,
                                                                   'mais_90', z.m90, 'vagas', z.vagas) order by gl.id), '[]'::jsonb)
                      from (select w2.grade_level_id, count(*) n, round(avg(current_date - w2.entered_at::date)) media,
                                   count(*) filter (where current_date - w2.entered_at::date > 90) m90,
                                   (select coalesce(sum(c.offerable_vacancies_count), 0) from iara.classes c
                                    where c.grade_level_id = w2.grade_level_id and c.status = 'ATIVA') vagas
                            from iara.waiting_list_entries w2 where w2.status = 'WAITING' group by 1) z
                      join iara.grade_levels gl on gl.id = z.grade_level_id))
      from iara.waiting_list_entries w where w.status = 'WAITING'),
    -- vagas ofertáveis em filas com crianças aguardando (deveriam ser ofertadas, na ordem)
    'vagas_com_fila', (with vf as (
          select c.unit_id, c.grade_level_id, sum(c.offerable_vacancies_count)::int vagas
          from iara.classes c where c.status = 'ATIVA' and c.offerable_vacancies_count > 0 group by 1, 2),
        ff as (
          select preferred_unit_id as unit_id, grade_level_id, count(*)::int aguardando, min(entered_at) desde
          from iara.waiting_list_entries where status = 'WAITING' group by 1, 2),
        j as (select vf.*, ff.aguardando, ff.desde from vf join ff using (unit_id, grade_level_id))
        select jsonb_build_object(
          'filas', count(*), 'vagas', coalesce(sum(least(j.vagas, j.aguardando)), 0), 'criancas', coalesce(sum(j.aguardando), 0),
          'itens', coalesce((select jsonb_agg(jsonb_build_object('unit_id', x.unit_id, 'unidade', u.short_name, 'faixa', gl.name, 'vagas', x.vagas,
                                                                 'aguardando', x.aguardando, 'espera_dias', current_date - x.desde::date)
                                              order by least(x.vagas, x.aguardando) desc, x.aguardando desc)
                             from (select * from j order by least(j.vagas, j.aguardando) desc, j.aguardando desc limit 12) x
                             join iara.education_units u on u.id = x.unit_id join iara.grade_levels gl on gl.id = x.grade_level_id), '[]'::jsonb))
        from j),
    -- ofertas dos últimos 12 meses frente à ordem da fila
    'ofertas', (select jsonb_build_object(
        'desde', v_desde::date,
        'total', count(*),
        'na_ordem', count(*) filter (where k.tipo = 'NA_ORDEM'),
        'laudo', count(*) filter (where k.tipo = 'LAUDO'),
        'alternativa', count(*) filter (where k.tipo = 'ALTERNATIVA'),
        'sem_registro', count(*) filter (where k.tipo = 'SEM_REGISTRO'),
        'abertas', count(*) filter (where o.status = 'OFFERED'),
        'vencem_24h', count(*) filter (where o.status = 'OFFERED' and o.expires_at < now() + interval '24 hours'),
        'aceitas', count(*) filter (where o.status in ('ACCEPTED', 'ENROLLED')),
        'matriculadas', count(*) filter (where o.status = 'ENROLLED'),
        'recusadas', count(*) filter (where o.status = 'DECLINED'),
        'expiradas', count(*) filter (where o.status = 'EXPIRED'),
        'resposta_media_h', round(avg(extract(epoch from (coalesce(o.accepted_at, o.declined_at) - o.offered_at)) / 3600.0)
                                  filter (where coalesce(o.accepted_at, o.declined_at) is not null))::int)
      from iara.vacancy_offers o cross join lateral (select iara.oferta_tipo(o) as tipo) k
      where o.offered_at >= v_desde),
    -- exceções à ordem (prioridade sob análise por laudo): pela auditoria imutável, sem CID e sem nomes
    'excecoes', (select coalesce(jsonb_agg(jsonb_build_object(
          'quando', a.occurred_at, 'unidade', u.short_name, 'codigo', iara.codigo_publico(case when a.entity_id ~ '^[0-9a-f-]{36}$' then a.entity_id::uuid end),
          'quem', regexp_replace(coalesce(a.actor_label, ''), '\s*\(demo #[0-9A-F]+\)', ''),
          'resumo', iara.anonimizar(a.summary, iara.nomes_da_inscricao(a.entity_id))) order by a.occurred_at desc), '[]'::jsonb)
      from (select * from iara.audit_log a1 where a1.action = 'PRIORITY_DECISION' and iara.excecao_com_oferta(a1.entity_id)
            order by a1.occurred_at desc limit 20) a
      left join iara.education_units u on u.id = a.unit_id),
    -- prazos dos protocolos de vaga
    'protocolos', (select jsonb_build_object(
        'abertos', count(*) filter (where iara.case_open(c.status)),
        'vencidos', count(*) filter (where iara.case_open(c.status) and c.sla_due_at < now()),
        'concluidos_12m', count(*) filter (where not iara.case_open(c.status) and c.closed_at >= v_desde))
      from iara.service_cases c where c.case_type in ('SOLICITACAO_VAGA', 'MATRICULA', 'TRANSFERENCIA', 'TRANSFERENCIA_EXTERNA', 'RECURSO')),
    -- saldo por região: crianças aguardando × vagas ofertáveis
    'regioes', (select coalesce(jsonb_agg(r order by (r ->> 'saldo')::int), '[]'::jsonb) from (
        select jsonb_build_object('regiao', t.name, 'aguardando', a.n, 'aguardando_creche', a.creche, 'vagas', v.n, 'vagas_creche', v.creche,
                                  'saldo', v.n - a.n, 'saldo_creche', v.creche - a.creche) r
        from iara.territories t
        cross join lateral (select count(*) n, count(*) filter (where w.grade_level_id = 1) creche
                            from iara.waiting_list_entries w join iara.education_units u on u.id = w.preferred_unit_id
                            where w.status = 'WAITING' and u.macro_territory_id = t.id) a
        cross join lateral (select coalesce(sum(c.offerable_vacancies_count), 0)::int n,
                                   coalesce(sum(c.offerable_vacancies_count) filter (where c.grade_level_id = 1), 0)::int creche
                            from iara.classes c join iara.education_units u on u.id = c.unit_id
                            where c.status = 'ATIVA' and u.macro_territory_id = t.id) v
        where t.kind = 'MACRORREGIAO' and (a.n > 0 or v.n > 0)) z),
    'distancias', api.distancias_resumo('{}'::jsonb),
    -- trilha de governança: mudanças de regra, exceções, recálculos e consultas do próprio controle externo
    'governanca', (select coalesce(jsonb_agg(jsonb_build_object(
          'quando', a.occurred_at, 'acao', a.action,
          'quem', regexp_replace(coalesce(a.actor_label, ''), '\s*\(demo #[0-9A-F]+\)', ''),
          'resumo', iara.anonimizar(a.summary, case when a.action = 'PRIORITY_DECISION' then iara.nomes_da_inscricao(a.entity_id) else '{}' end))
          order by a.occurred_at desc), '[]'::jsonb)
      from (select * from iara.audit_log a1
            where a1.action in ('RULE_VERSION', 'REGRA_MEDIDA_DISTANCIA', 'PRIORITY_DECISION', 'CONTROLE_CONSULTA', 'QUEUE_RECALCULATED')
              and (a1.action <> 'PRIORITY_DECISION' or iara.excecao_com_oferta(a1.entity_id))
            order by a1.occurred_at desc limit 30) a)
  );
end $$;

-- 4. Fila pública anonimizada ----------------------------------------------------------------------------------------
create or replace function api.controle_fila(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := nullif(p ->> 'unit_id', '')::int;
  v_grade smallint := nullif(p ->> 'grade_level_id', '')::smallint;
  v_flag text := nullif(p ->> 'flag', '');
  v_q text := upper(nullif(btrim(coalesce(p ->> 'q', '')), ''));
  v_status text := coalesce(nullif(p ->> 'status', ''), 'WAITING');
  v_page integer := greatest(coalesce(nullif(p ->> 'page', '')::int, 1), 1);
  v_size integer := least(greatest(coalesce(nullif(p ->> 'page_size', '')::int, 50), 1), 5000);
begin
  perform iara.require_perm('controle.read');
  if v_status not in ('WAITING', 'OFFERED', 'ACCEPTED', 'ALL') then v_status := 'WAITING'; end if;
  return (
    with base as (
      select w.id, w.preferred_unit_id, w.grade_level_id, w.position, w.priority_score, w.priority_flags, w.demand_category, w.status,
             w.entered_at, w.dist_reta_m, w.dist_pe_m, w.dist_carro_m, w.rule_version,
             u.short_name as unidade, gl.name as faixa, iara.codigo_publico(w.id) as codigo
      from iara.waiting_list_entries w
      join iara.education_units u on u.id = w.preferred_unit_id
      join iara.grade_levels gl on gl.id = w.grade_level_id
      where (case when v_status = 'ALL' then w.status in ('WAITING', 'OFFERED', 'ACCEPTED') else w.status = v_status end)
        and (v_unit is null or w.preferred_unit_id = v_unit)
        and (v_grade is null or w.grade_level_id = v_grade)
        and (v_flag is null or v_flag = any (w.priority_flags))
    ),
    filtrada as (select * from base where v_q is null or codigo like '%' || v_q || '%'),
    conf as (select * from iara.filas_conferencia())
    select jsonb_build_object(
      'total', (select count(*) from filtrada),
      'filas', (select count(*) from conf), 'filas_conferidas', (select count(*) from conf where conferida),
      'criterio_distancia', jsonb_build_object('medida', iara.medida_distancia_fila(),
                                               'limite_m', coalesce(((iara.rule('TERRITORIO_2KM')).condition ->> 'max_m')::int, 2000)),
      'regras', iara.rule_version(),
      'itens', coalesce((select jsonb_agg(jsonb_build_object(
          'codigo', b.codigo, 'unit_id', b.preferred_unit_id, 'unidade', b.unidade, 'faixa', b.faixa, 'grade_level_id', b.grade_level_id,
          'posicao', b.position, 'pontos', b.priority_score, 'criterios', b.priority_flags, 'categoria', b.demand_category, 'status', b.status,
          'entrada', b.entered_at::date, 'dias', current_date - b.entered_at::date, 'regras', b.rule_version,
          'dist', jsonb_build_object('linha_reta_m', b.dist_reta_m, 'a_pe_m', b.dist_pe_m, 'carro_m', b.dist_carro_m),
          'ordem_conferida', (select c.conferida from conf c where c.unit_id = b.preferred_unit_id and c.grade_level_id = b.grade_level_id))
          order by b.unidade, b.grade_level_id, b.position nulls last, b.entered_at)
        from (select * from filtrada order by unidade, grade_level_id, position nulls last, entered_at
              offset (v_page - 1) * v_size limit v_size) b), '[]'::jsonb)
    )
  );
end $$;

-- 5. Consulta de um caso pelo protocolo (informado pela família), com motivo e registro na auditoria ----------------
create or replace function api.controle_caso(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_prot text := upper(btrim(coalesce(p ->> 'protocolo', '')));
  v_motivo text := nullif(btrim(coalesce(p ->> 'motivo', '')), '');
  c iara.service_cases;
  s iara.students;
  w iara.waiting_list_entries;
  v_conf boolean;
begin
  perform iara.require_perm('controle.read');
  if v_prot = '' then
    raise exception 'Informe o número do protocolo.' using errcode = '22023';
  end if;
  if v_motivo is null or length(v_motivo) < 10 then
    raise exception 'Registre o motivo da consulta (ex.: atendimento da Defensoria nº …, procedimento do MP nº …).' using errcode = '22023';
  end if;
  select * into c from iara.service_cases where upper(protocol_number) = v_prot;
  if not found then
    -- a tentativa também fica registrada (controle de acesso)
    perform iara.audit_event('CONTROLE_CONSULTA', 'service_cases', null, null,
      format('Controle externo consultou o protocolo %s (não encontrado). Motivo: %s', v_prot, v_motivo));
    return jsonb_build_object('encontrado', false, 'acesso_registrado', true,
                              'mensagem', 'Protocolo não encontrado. Confira o número informado pela família.');
  end if;
  select * into s from iara.students where id = c.student_id;
  select * into w from iara.waiting_list_entries x
  where x.student_id = c.student_id
  order by (x.case_id = c.id) desc nulls last, (x.status in ('WAITING', 'OFFERED', 'ACCEPTED')) desc, x.entered_at desc limit 1;
  if w.id is not null then
    select f.conferida into v_conf from iara.filas_conferencia() f where f.unit_id = w.preferred_unit_id and f.grade_level_id = w.grade_level_id;
  end if;
  perform iara.audit_event('CONTROLE_CONSULTA', 'service_cases', c.id::text, c.unit_id,
    format('Controle externo consultou o protocolo %s. Motivo: %s', c.protocol_number, v_motivo));
  return jsonb_build_object(
    'encontrado', true, 'acesso_registrado', true, 'consultado_em', now(), 'motivo', v_motivo,
    'protocolo', (select jsonb_build_object('numero', c.protocol_number, 'tipo', sc.name, 'status', c.status, 'aberto_em', c.opened_at,
                                            'prazo', c.sla_due_at, 'encerrado_em', c.closed_at, 'canal', c.channel, 'assunto', c.subject,
                                            'em_aberto', iara.case_open(c.status), 'vencido', iara.case_open(c.status) and c.sla_due_at < now())
                  from iara.service_catalog sc where sc.code = c.case_type),
    'crianca', case when s.id is not null then jsonb_build_object('nome', s.full_name, 'idade', iara.age_text(s.birth_date),
                                                                  'faixa_pela_idade', (iara.grade_for_birthdate(s.birth_date)) ->> 'grade_name') end,
    'responsavel', (select jsonb_build_object('nome', g.full_name, 'telefone', iara.mask_phone(coalesce(g.whatsapp_phone, g.primary_phone)))
                    from iara.guardians g where g.id = c.guardian_id),
    'fila', case when w.id is not null then jsonb_build_object(
        'codigo', iara.codigo_publico(w.id), 'status', w.status, 'posicao', w.position, 'pontos', w.priority_score, 'regras', w.rule_version,
        'unidade', (select name from iara.education_units where id = w.preferred_unit_id),
        'faixa', (select name from iara.grade_levels where id = w.grade_level_id),
        'entrada', w.entered_at, 'dias', current_date - w.entered_at::date, 'criterios', w.score_breakdown,
        'aguardando', (select count(*) from iara.waiting_list_entries x where x.preferred_unit_id = w.preferred_unit_id
                         and x.grade_level_id = w.grade_level_id and x.status = 'WAITING'),
        'ordem_conferida', v_conf,
        'vagas_ofertaveis', (select coalesce(sum(cl.offerable_vacancies_count), 0) from iara.classes cl
                             where cl.unit_id = w.preferred_unit_id and cl.grade_level_id = w.grade_level_id and cl.status = 'ATIVA'),
        -- quem está à frente, sem identificação: código público, pontos, critérios e data de entrada
        'a_frente', (select coalesce(jsonb_agg(jsonb_build_object('codigo', iara.codigo_publico(x.id), 'posicao', x.position, 'pontos', x.priority_score,
                                                                  'criterios', x.priority_flags, 'entrada', x.entered_at::date) order by x.position), '[]'::jsonb)
                     from (select * from iara.waiting_list_entries x where x.preferred_unit_id = w.preferred_unit_id and x.grade_level_id = w.grade_level_id
                             and x.status = 'WAITING' and x.position < coalesce(w.position, 0) order by x.position limit 30) x)) end,
    'ofertas', (select coalesce(jsonb_agg(jsonb_build_object('quando', o.offered_at, 'unidade', u.name, 'status', o.status, 'prazo', o.expires_at,
                                                             'tipo', iara.oferta_tipo(o), 'motivo_recusa', o.decline_reason) order by o.offered_at desc), '[]'::jsonb)
                from iara.vacancy_offers o join iara.education_units u on u.id = o.unit_id where o.student_id = c.student_id),
    'eventos', (select coalesce(jsonb_agg(jsonb_build_object('quando', e.occurred_at, 'tipo', e.event_type, 'mensagem', e.message) order by e.occurred_at), '[]'::jsonb)
                from iara.case_events e where e.case_id = c.id and e.visibility = 'CIDADAO'),
    'documentos', (select coalesce(jsonb_agg(jsonb_build_object('tipo', d.doc_type, 'status', d.status) order by d.doc_type), '[]'::jsonb)
                   from (select distinct on (doc_type) doc_type, status from iara.documents where student_id = c.student_id order by doc_type, created_at desc) d)
  );
end $$;

-- 6b. Demonstração: protocolos fictícios para testar a consulta (só no modo demonstração; sem nomes)
create or replace function api.controle_protocolos_demo(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('controle.read');
  if not coalesce((iara.setting('demo_mode'))::boolean, false) then
    return '[]'::jsonb;
  end if;
  return (
    with cand as (
      select c.protocol_number, w.position, w.priority_flags, gl.name as faixa, u.short_name as unidade, w.student_id,
             exists (select 1 from iara.student_guardians sg where sg.student_id = w.student_id
                       and sg.guardian_id = nullif(iara.setting('demo_guardian_maria'), '')::uuid) as maria,
             exists (select 1 from iara.vacancy_offers o where o.student_id = w.student_id and o.status = 'OFFERED') as ofertada
      from iara.service_cases c
      join iara.waiting_list_entries w on w.student_id = c.student_id and w.status in ('WAITING', 'OFFERED')
      join iara.education_units u on u.id = w.preferred_unit_id
      join iara.grade_levels gl on gl.id = w.grade_level_id
      where c.case_type in ('SOLICITACAO_VAGA', 'MATRICULA', 'TRANSFERENCIA', 'TRANSFERENCIA_EXTERNA')
    ),
    escolhidos as (
      (select 1 as ord, 'Família da Maria (portal e WhatsApp)' as rotulo, * from cand where maria order by position nulls last limit 1)
      union all
      (select 2, 'Longe do topo da fila', * from cand where not maria and position > 15 order by position desc limit 1)
      union all
      (select 3, 'Com laudo (prioridade sob análise)', * from cand where not maria and 'PCD_TEA_AEE' = any (priority_flags) order by position limit 1)
      union all
      (select 4, 'Com vaga ofertada', * from cand where not maria and ofertada limit 1)
    )
    select coalesce(jsonb_agg(jsonb_build_object('protocolo', e.protocol_number, 'rotulo', e.rotulo,
             'descricao', format('%s · %s · %s', e.faixa, e.unidade, case when e.position is not null then e.position || 'º na fila' else 'vaga ofertada' end))
           order by e.ord), '[]'::jsonb)
    from (select distinct on (protocol_number) * from escolhidos order by protocol_number, ord) e
  );
end $$;

-- 6. Simulação da medida: também para o controle externo (sem nomes para quem não lê ficha de aluno) ----------------
create or replace function api.fila_simular_medida(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_medida text := coalesce(nullif(p ->> 'medida', ''), 'A_PE');
  r iara.rules := iara.rule('TERRITORIO_2KM');
  v_max integer := coalesce((r.condition ->> 'max_m')::int, 2000);
  v_peso numeric := coalesce(r.weight, 0);
  v_nomes boolean := iara.has_perm('students.read');
begin
  if not (iara.has_perm('queue.read') or iara.has_perm('controle.read')) then
    raise exception 'Seu perfil não tem permissão para esta ação (queue.read).' using errcode = '42501';
  end if;
  if iara.my_scope() not in ('NETWORK', 'AGGREGATE') then
    raise exception 'A simulação olha a rede inteira: disponível para a Secretaria e o controle externo.' using errcode = '42501';
  end if;
  if v_medida not in ('LINHA_RETA', 'A_PE', 'CARRO') then
    raise exception 'Medida inválida.' using errcode = '22023';
  end if;
  return (
    with base as (
      select w.id, w.preferred_unit_id as u, w.grade_level_id as g, w.priority_score as pontos, w.position as posicao, w.entered_at,
             w.dist_reta_m, w.dist_pe_m, w.dist_carro_m, w.student_id,
             coalesce((select (x ->> 'applied')::boolean from jsonb_array_elements(w.score_breakdown) x where x ->> 'code' = 'TERRITORIO_2KM'), false) as aplica_hoje
      from iara.waiting_list_entries w where w.status = 'WAITING'
    ),
    sim as (
      select b.*, case v_medida when 'A_PE' then b.dist_pe_m when 'CARRO' then b.dist_carro_m else b.dist_reta_m end as d_nova
      from base b
    ),
    novo as (
      select s.*, case when s.d_nova is null then s.aplica_hoje else s.d_nova <= v_max end as aplica_nova
      from sim s
    ),
    pont as (
      select n.*, n.pontos - case when n.aplica_hoje then v_peso else 0 end + case when n.aplica_nova then v_peso else 0 end as pontos_novos
      from novo n
    ),
    pos as (
      select t.*, row_number() over (partition by t.u, t.g order by t.pontos_novos desc, t.entered_at, t.id) as posicao_nova
      from pont t
    )
    select jsonb_build_object(
      'medida', v_medida, 'medida_atual', iara.medida_distancia_fila(), 'limite_m', v_max, 'peso', v_peso,
      'total', count(*), 'ganham', count(*) filter (where not aplica_hoje and aplica_nova),
      'perdem', count(*) filter (where aplica_hoje and not aplica_nova),
      'sem_rota', count(*) filter (where d_nova is null),
      'mudam_posicao', count(*) filter (where posicao is not null and posicao <> posicao_nova),
      'atende_hoje', count(*) filter (where aplica_hoje), 'atenderia', count(*) filter (where aplica_nova),
      'exemplos', (select coalesce(jsonb_agg(z.j order by z.mov desc), '[]'::jsonb) from (
          select jsonb_build_object('entry_id', case when v_nomes then x.id end, 'codigo', iara.codigo_publico(x.id),
                   'crianca', case when v_nomes then split_part(st.full_name, ' ', 1) || ' ' || left(split_part(st.full_name, ' ', 2), 1) || '.'
                                   else iara.codigo_publico(x.id) end,
                   'unidade', un.short_name, 'faixa', gl.name, 'reta_m', x.dist_reta_m, 'a_pe_m', x.dist_pe_m, 'carro_m', x.dist_carro_m,
                   'aplica_hoje', x.aplica_hoje, 'aplica_nova', x.aplica_nova, 'posicao', x.posicao, 'posicao_nova', x.posicao_nova) as j,
                 abs(coalesce(x.posicao, 0) - x.posicao_nova) as mov
          from pos x join iara.students st on st.id = x.student_id join iara.education_units un on un.id = x.u join iara.grade_levels gl on gl.id = x.g
          where x.aplica_hoje <> x.aplica_nova
          order by abs(coalesce(x.posicao, 0) - x.posicao_nova) desc limit 30) z))
    from pos
  );
end $$;

commit;
