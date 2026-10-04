-- =============================================================================
-- IARA Educa · Regras 2026.02 — pontuação oficial da fila de espera
--
-- Fonte: Instrução Normativa nº 025, de 19/11/2025 (SEDUC Maringá), Anexo I — altera a IN nº 023/2025-SEDUC
--        (rematrícula on-line, fila de espera on-line, matrícula e critérios de equidade e justiça social, 2026).
--        SEI nº 7410308 · Processo nº 01.09.00153028/2025.39 · referida no Ofício nº 383/2026/SEDUC,
--        em resposta ao Requerimento nº 81/2026.
--        http://www3.maringa.pr.gov.br/sistema/arquivos/5e336fc8c680.pdf
--
--   Critérios de pontuação: irmão(ã) já matriculado(a) na mesma unidade 55 · família de baixa renda no CadÚnico 25 ·
--                           reside até 2 km da unidade 15 · filho(a) de mãe solo 5 (máximo 100)
--   Critério de prioridade: PCD, TEA, TGD e/ou altas habilidades/superdotação — laudo médico com CID —
--                           "prioridade sob análise", fora da soma de pontos.
--
-- As versões 2026.01 (parametrização de referência) ficam inativas e preservadas para auditoria.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
-- =============================================================================
begin;

-- 1. Estrutura -----------------------------------------------------------------
alter table iara.guardians add column if not exists single_mother boolean not null default false;
comment on column iara.guardians.single_mother is
  'Mãe solo (declaração do responsável) — critério de pontuação da IN nº 025/2025-SEDUC, Anexo I.';

alter table iara.rules drop constraint if exists rules_rule_type_check;
alter table iara.rules add constraint rules_rule_type_check
  check (rule_type in ('ELIMINATORIA', 'PONTUACAO_UNIDADE', 'PRIORIDADE_FILA', 'PRIORIDADE_ANALISE', 'DESEMPATE', 'PARAMETRO'));
alter table iara.rules add column if not exists source_kind text not null default 'DEMO';
alter table iara.rules drop constraint if exists rules_source_kind_check;
alter table iara.rules add constraint rules_source_kind_check check (source_kind in ('OFICIAL', 'PUBLICO', 'DEMO', 'PENDENTE'));
alter table iara.rules add column if not exists source_url text;

-- "no CMEI X" / "na Escola Municipal Y" nas mensagens às famílias
create or replace function iara.na_unidade(p_name text) returns text
language sql immutable set search_path = iara, public
as $$ select case when p_name ~* '^cmei\s' then 'no ' else 'na ' end || coalesce(p_name, 'unidade') $$;
create or replace function iara.da_unidade(p_name text) returns text
language sql immutable set search_path = iara, public
as $$ select case when p_name ~* '^cmei\s' then 'do ' else 'da ' end || coalesce(p_name, 'unidade') $$;

-- 2. Regras versão 2026.02 -------------------------------------------------------
update iara.rules set is_active = false, valid_to = coalesce(valid_to, current_date - 1)
where tenant_id = 1 and version = '2026.01'
  and rule_code in ('IRMAO_NA_UNIDADE', 'CADUNICO', 'TERRITORIO_2KM', 'PCD_TEA_AEE', 'VULNERABILIDADE');

insert into iara.rules (tenant_id, rule_code, version, name, description, rule_type, condition, weight, source, justification,
                        valid_from, is_active, test_reference, sort, source_kind, source_url)
select 1, v.code, '2026.02', v.name, v.descr, v.rtype, v.cond::jsonb, v.weight, s.src, s.just, current_date, true, v.test, v.sort, 'OFICIAL', s.url
from (values
  ('IRMAO_NA_UNIDADE', 'Irmão(ã) já matriculado(a) na mesma unidade',
   'Estudantes com irmãos já matriculados na mesma unidade de ensino pretendida.',
   'PRIORIDADE_FILA', '{}', 55, 'jornada_e2e: passo 1', 20),
  ('CADUNICO', 'Família de baixa renda inscrita no CadÚnico',
   'Famílias de baixa renda inscritas no Cadastro Único para Programas Sociais do Governo Federal.',
   'PRIORIDADE_FILA', '{}', 25, 'jornada_e2e: passo 1', 21),
  ('TERRITORIO_2KM', 'Reside até 2 km da unidade',
   'Residência próxima à unidade de ensino, em até 2 km (distância em linha reta entre o endereço cadastrado e a unidade).',
   'PRIORIDADE_FILA', '{"max_m": 2000}', 15, 'jornada_e2e: passo 1', 22),
  ('MAE_SOLO', 'Filho(a) de mãe solo',
   'Estudantes filhos(as) de mãe solo, conforme declaração do responsável no cadastro.',
   'PRIORIDADE_FILA', '{"evidence": "declaracao_responsavel"}', 5, 'fila: critério mãe solo', 23),
  ('PCD_TEA_AEE', 'Deficiência (PCD), TEA, TGD e/ou altas habilidades/superdotação',
   'Critério de prioridade mediante laudo médico com informação do(s) CID(s): prioridade sob análise, fora da soma de pontos. A Central de Vagas analisa cada caso e pode ofertar fora da ordem de pontuação, com laudo validado e justificativa registrada na auditoria.',
   'PRIORIDADE_ANALISE', '{"document": "LAUDO", "requires_cid": true, "separate_from_score": true}', 0, 'oferta: exceção por laudo validado', 24)
) as v(code, name, descr, rtype, cond, weight, test, sort)
cross join (select 'IN nº 025/2025-SEDUC (19/11/2025), Anexo I' as src,
                   'http://www3.maringa.pr.gov.br/sistema/arquivos/5e336fc8c680.pdf' as url,
                   'Instrução Normativa nº 025, de 19 de novembro de 2025, que altera a IN nº 023/2025-SEDUC (rematrícula on-line, cadastro da fila de espera on-line, matrícula e critérios de equidade e justiça social para o ano letivo de 2026). Em vigor desde a publicação. SEI nº 7410308. Referida no Ofício nº 383/2026/SEDUC, em resposta ao Requerimento nº 81/2026.' as just) s
on conflict (tenant_id, rule_code, version) do update set
  name = excluded.name, description = excluded.description, rule_type = excluded.rule_type, condition = excluded.condition,
  weight = excluded.weight, source = excluded.source, justification = excluded.justification, is_active = true, valid_to = null,
  test_reference = excluded.test_reference, sort = excluded.sort, source_kind = excluded.source_kind, source_url = excluded.source_url;

-- 3. Cálculo da prioridade (explicável e versionado) --------------------------------
create or replace function iara.compute_queue_priority(p_entry uuid) returns void
language plpgsql security definer set search_path = iara, extensions, public
as $$
declare
  w iara.waiting_list_entries;
  v_dist integer;
  v_sibling boolean;
  v_cadunico boolean;
  v_single_mother boolean;
  v_aee boolean;
  v_laudo text;
  v_vuln boolean;
  v_breakdown jsonb := '[]'::jsonb;
  v_score numeric := 0;
  v_flags text[] := '{}';
  r iara.rules;
  v_max_m integer;
begin
  select * into w from iara.waiting_list_entries where id = p_entry;
  if not found then return; end if;

  select round(st_distance(a.location, u.location))::int into v_dist
  from iara.students s join iara.addresses a on a.id = s.address_id
  join iara.education_units u on u.id = w.preferred_unit_id
  where s.id = w.student_id;

  select exists (
    select 1 from iara.student_guardians sg1
    join iara.student_guardians sg2 on sg2.guardian_id = sg1.guardian_id and sg2.student_id <> sg1.student_id
    join iara.enrollments e on e.student_id = sg2.student_id and e.status = 'ACTIVE' and e.unit_id = w.preferred_unit_id
    where sg1.student_id = w.student_id) into v_sibling;

  select coalesce(bool_or(g.cadunico_status), false), coalesce(bool_or(g.single_mother), false)
    into v_cadunico, v_single_mother
  from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
  where sg.student_id = w.student_id;

  select coalesce(aee_status, false) into v_aee from iara.students where id = w.student_id;
  select d.status into v_laudo from iara.documents d
  where d.student_id = w.student_id and d.doc_type = 'LAUDO' order by d.created_at desc limit 1;
  v_vuln := 'VULNERABILIDADE' = any (w.priority_flags);

  -- Critérios de pontuação, na ordem do Anexo I
  r := iara.rule('IRMAO_NA_UNIDADE');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', v_sibling,
      'evidence', case when v_sibling then 'Irmão(ã) com matrícula ativa na unidade pretendida' else 'Sem irmão(ã) matriculado(a) na unidade' end);
    if v_sibling then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'IRMAO_NA_UNIDADE'); end if;
  end if;

  r := iara.rule('CADUNICO');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', v_cadunico,
      'evidence', case when v_cadunico then 'Responsável com inscrição ativa no CadÚnico' else 'Sem inscrição no CadÚnico informada' end);
    if v_cadunico then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'CADUNICO'); end if;
  end if;

  r := iara.rule('TERRITORIO_2KM');
  if r.id is not null then
    v_max_m := coalesce((r.condition ->> 'max_m')::int, 2000);
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', coalesce(v_dist <= v_max_m, false),
      'evidence', case when v_dist is null then 'Endereço sem geocodificação — critério não verificado'
                       else format('Residência a %s km da unidade pretendida', replace(round(v_dist / 1000.0, 1)::text, '.', ',')) end);
    if coalesce(v_dist <= v_max_m, false) then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'TERRITORIO'); end if;
  end if;

  r := iara.rule('MAE_SOLO');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', v_single_mother,
      'evidence', case when v_single_mother then 'Responsável declarou ser mãe solo' else 'Sem declaração de mãe solo' end);
    if v_single_mother then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'MAE_SOLO'); end if;
  end if;

  -- Critério de prioridade: sob análise, mediante laudo — fora da soma de pontos
  r := iara.rule('PCD_TEA_AEE');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', v_aee, 'analysis', r.rule_type = 'PRIORIDADE_ANALISE', 'laudo_status', coalesce(v_laudo, 'NAO_ENVIADO'),
      'evidence', case when not v_aee then 'Sem indicação de deficiência, TEA, TGD ou altas habilidades/superdotação'
                       when v_laudo = 'VALIDADO' then 'Laudo médico com CID validado — prioridade sob análise da Central de Vagas (não soma pontos)'
                       when v_laudo = 'RECEBIDO' then 'Laudo recebido, aguardando validação — prioridade sob análise (não soma pontos)'
                       else 'Indicação registrada; laudo médico com CID pendente — prioridade sob análise (não soma pontos)' end);
    if v_aee then
      v_flags := array_append(v_flags, 'PCD_TEA_AEE');
      if r.rule_type <> 'PRIORIDADE_ANALISE' then v_score := v_score + r.weight; end if;
    end if;
  end if;

  -- Regra anterior (2026.01), inativa na versão 2026.02: só conta se for reativada
  r := iara.rule('VULNERABILIDADE');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', v_vuln, 'evidence', case when v_vuln then 'Encaminhamento da rede de proteção registrado' else 'Sem encaminhamento da rede de proteção' end);
    if v_vuln then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'VULNERABILIDADE'); end if;
  end if;

  -- Desempate
  r := iara.rule('DATA_SOLICITACAO');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', 0, 'version', r.version,
      'applied', true, 'evidence', format('Desempate pela data de entrada: %s', to_char(w.entered_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')));
  end if;

  update iara.waiting_list_entries set
    priority_score = v_score,
    score_breakdown = v_breakdown,
    home_distance_m = v_dist,
    priority_flags = v_flags,
    rule_version = iara.rule_version(),
    last_recalculated_at = now()
  where id = p_entry;
end $$;

-- 4. APIs ajustadas (fila, oferta com prioridade sob análise, documentos, responsáveis, regras) ----
create or replace function api.queue_list(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security invoker set search_path = iara, public
as $$
  with params as (
    select (p ->> 'unit_id')::int as unit_id, (p ->> 'grade_level_id')::smallint as grade, (p ->> 'territory_id')::int as territory,
           nullif(p ->> 'category', '') as category, nullif(p ->> 'flag', '') as flag, coalesce(nullif(p ->> 'status', ''), 'WAITING') as status, iara.norm(nullif(p ->> 'q', '')) as q,
           greatest(coalesce((p ->> 'page')::int, 1), 1) as page, least(coalesce((p ->> 'page_size')::int, 40), 100) as page_size
  ),
  base as (
    select w.*, u.short_name as unit_name, u.macro_territory_id, s.full_name, s.birth_date, s.avatar_seed, gl.name as grade_name
    from iara.waiting_list_entries w join iara.students s on s.id = w.student_id
    join iara.education_units u on u.id = w.preferred_unit_id join iara.grade_levels gl on gl.id = w.grade_level_id, params x
    where (x.unit_id is null or w.preferred_unit_id = x.unit_id) and (x.grade is null or w.grade_level_id = x.grade)
      and (x.territory is null or u.macro_territory_id = x.territory) and (x.category is null or w.demand_category = x.category)
      and (x.status = 'ALL' or w.status = x.status) and (x.q is null or iara.norm(s.full_name) like '%' || x.q || '%')
      and (x.flag is null or x.flag = any (w.priority_flags))
  )
  select jsonb_build_object(
    'total', (select count(*) from base),
    'by_category', coalesce((select jsonb_object_agg(demand_category, n) from (select demand_category, count(*) n from base group by 1) z), '{}'::jsonb),
    'by_flag', coalesce((select jsonb_object_agg(f, n) from (select f, count(*) n from base b2, unnest(b2.priority_flags) f group by 1) z), '{}'::jsonb),
    'by_grade', coalesce((select jsonb_object_agg(grade_name, n) from (select grade_name, count(*) n from base group by 1) z), '{}'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', b.id, 'student_id', b.student_id, 'student', b.full_name, 'age', iara.age_text(b.birth_date), 'avatar_seed', b.avatar_seed,
        'unit_id', b.preferred_unit_id, 'unit', b.unit_name, 'grade', b.grade_name, 'grade_level_id', b.grade_level_id,
        'position', b.position, 'score', b.priority_score, 'flags', b.priority_flags, 'category', b.demand_category, 'status', b.status,
        'entered_at', b.entered_at, 'days_waiting', (current_date - b.entered_at::date), 'distance_m', b.home_distance_m,
        'shift', b.preferred_shift, 'full_time', b.full_time_requested)
        order by b.preferred_unit_id, b.grade_level_id, b.position nulls last, b.entered_at)
      from (select * from base order by unit_name, grade_level_id, position nulls last, entered_at
            offset ((select page from params) - 1) * (select page_size from params) limit (select page_size from params)) b), '[]'::jsonb)
  )
$$;

create or replace function api.queue_entry_detail(p jsonb) returns jsonb
language plpgsql stable security invoker set search_path = iara, public
as $$
declare
  w iara.waiting_list_entries;
  v jsonb;
begin
  select * into w from iara.waiting_list_entries where id = (p ->> 'entry_id')::uuid;
  if not found then
    raise exception 'Entrada de fila não encontrada ou sem permissão.' using errcode = 'P0002';
  end if;
  select jsonb_build_object(
    'entry', jsonb_build_object('id', w.id, 'status', w.status, 'position', w.position, 'score', w.priority_score, 'flags', w.priority_flags,
      'breakdown', w.score_breakdown, 'category', w.demand_category, 'entered_at', w.entered_at, 'rule_version', w.rule_version,
      'last_recalculated_at', w.last_recalculated_at, 'distance_m', w.home_distance_m, 'shift', w.preferred_shift,
      'full_time', w.full_time_requested, 'case_id', w.case_id, 'grade_level_id', w.grade_level_id,
      'grade', (select name from iara.grade_levels where id = w.grade_level_id),
      'queue_size', (select count(*) from iara.waiting_list_entries x where x.preferred_unit_id = w.preferred_unit_id and x.grade_level_id = w.grade_level_id and x.status = 'WAITING')),
    'student', (select jsonb_build_object('id', s.id, 'name', s.full_name, 'age', iara.age_text(s.birth_date), 'birth_date', s.birth_date,
                                          'avatar_seed', s.avatar_seed, 'address', iara.address_json(s.address_id)) from iara.students s where s.id = w.student_id),
    'unit', (select jsonb_build_object('id', u.id, 'name', u.name, 'lat', u.lat, 'lng', u.lng) from iara.education_units u where u.id = w.preferred_unit_id),
    'classes', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.class_name, 'shift', c.shift, 'capacity', c.authorized_capacity,
        'enrolled', c.active_enrollments_count, 'blocked', c.blocked_seats_count, 'reserved', c.reserved_seats_count, 'offerable', c.offerable_vacancies_count)
        order by c.offerable_vacancies_count desc, c.class_code)
      from iara.classes c where c.unit_id = w.preferred_unit_id and c.grade_level_id = w.grade_level_id and c.status = 'ATIVA'), '[]'::jsonb),
    'can_offer_now', w.status = 'WAITING' and w.position = 1 and exists (select 1 from iara.classes c where c.unit_id = w.preferred_unit_id
                       and c.grade_level_id = w.grade_level_id and c.offerable_vacancies_count > 0),
    -- IN 025/2025, Anexo I: PCD/TEA/TGD/AH-SD com laudo têm prioridade sob análise (fora da soma de pontos)
    'can_offer_priority', w.status = 'WAITING' and coalesce(w.position, 0) > 1 and 'PCD_TEA_AEE' = any (w.priority_flags)
                       and exists (select 1 from iara.classes c where c.unit_id = w.preferred_unit_id
                                     and c.grade_level_id = w.grade_level_id and c.offerable_vacancies_count > 0),
    'offers', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'status', o.status, 'class', c.class_name, 'offered_at', o.offered_at,
        'expires_at', o.expires_at, 'decline_reason', o.decline_reason) order by o.offered_at desc)
      from iara.vacancy_offers o join iara.classes c on c.id = o.class_id where o.waiting_list_entry_id = w.id), '[]'::jsonb),
    'rules', (select coalesce(jsonb_agg(jsonb_build_object('code', rule_code, 'name', name, 'weight', weight, 'version', version, 'source', source)
                                        order by sort), '[]'::jsonb) from iara.rules where rule_type in ('PRIORIDADE_FILA', 'PRIORIDADE_ANALISE', 'DESEMPATE') and is_active)
  ) into v;
  return v;
end $$;

create or replace function api.queue_entry_create(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_unit integer := (p ->> 'preferred_unit_id')::int;
  v_grade smallint := (p ->> 'grade_level_id')::smallint;
  v_case uuid := nullif(p ->> 'case_id', '')::uuid;
  v_entry uuid := gen_random_uuid();
  v_rule jsonb;
  v_flags text[] := '{}';
  v_pos integer;
  s iara.students;
begin
  perform iara.require_perm('queue.manage');
  select * into s from iara.students where id = v_student;
  if not found or not iara.can_access_student(v_student) then
    raise exception 'Aluno não encontrado ou fora do seu escopo.' using errcode = 'P0002';
  end if;
  if v_grade is null then
    v_rule := iara.grade_for_birthdate(s.birth_date);
    if not coalesce((v_rule ->> 'ok')::boolean, false) then
      raise exception '%', v_rule ->> 'explanation' using errcode = '22023';
    end if;
    v_grade := (v_rule ->> 'grade_level_id')::smallint;
  end if;
  if not exists (select 1 from iara.classes c where c.unit_id = v_unit and c.grade_level_id = v_grade and c.status = 'ATIVA') then
    raise exception 'A unidade escolhida não atende esta faixa/série.' using errcode = '22023';
  end if;
  if exists (select 1 from iara.waiting_list_entries w where w.student_id = v_student and w.grade_level_id = v_grade
               and w.preferred_unit_id = v_unit and w.status in ('WAITING', 'OFFERED', 'ACCEPTED')) then
    raise exception 'A criança já está na fila desta unidade/faixa.' using errcode = '23505';
  end if;
  if coalesce((p ->> 'vulnerability')::boolean, false) and (iara.rule('VULNERABILIDADE')).id is not null then
    if length(coalesce(p ->> 'vulnerability_note', '')) < 15 then
      raise exception 'O critério de rede de proteção exige justificativa (encaminhamento formal) com pelo menos 15 caracteres.' using errcode = '22023';
    end if;
    v_flags := array['VULNERABILIDADE'];
  end if;
  insert into iara.waiting_list_entries (id, tenant_id, student_id, case_id, stage_id, grade_level_id, preferred_unit_id, territory_id,
                                         preferred_shift, full_time_requested, demand_category, priority_flags, entered_at, status, created_by, is_demo)
  select v_entry, 1, v_student, v_case, gl.stage_id, v_grade, v_unit, u.macro_territory_id, nullif(p ->> 'preferred_shift', ''),
         coalesce((p ->> 'full_time')::boolean, false), coalesce(nullif(p ->> 'category', ''),
           case when exists (select 1 from iara.enrollments e where e.student_id = v_student and e.status = 'ACTIVE') then 'AGUARDA_TRANSFERENCIA' else 'SEM_ATENDIMENTO' end),
         v_flags, now(), 'WAITING', iara.current_user_id(), true
  from iara.grade_levels gl, iara.education_units u where gl.id = v_grade and u.id = v_unit;
  perform iara.compute_queue_priority(v_entry);
  perform iara.recalculate_queue(v_unit, v_grade);
  update iara.students set status = 'AGUARDANDO_VAGA' where id = v_student and status = 'SEM_VINCULO';
  select position into v_pos from iara.waiting_list_entries where id = v_entry;
  if v_case is not null then
    update iara.service_cases set status = 'ENCERRADO', closed_at = now(), resolution_code = 'INSERIDO_NA_FILA',
           resolution_notes = 'Sem vaga ofertável compatível; criança inserida na fila.' where id = v_case and iara.case_open(status);
    insert into iara.case_events (case_id, event_type, message, new_value, user_id, actor_label, visibility)
    values (v_case, 'FILA', format('Criança inserida na fila (%s) — posição %s pelas regras %s.', (select name from iara.grade_levels where id = v_grade), v_pos, iara.rule_version()),
            'EM_FILA', iara.current_user_id(), iara.my_label(), 'CIDADAO');
  end if;
  insert into iara.notifications (tenant_id, guardian_id, student_id, case_id, channel, event_type, title, body)
  select 1, sg.guardian_id, v_student, v_case, 'PORTAL', 'FILA', 'Inserção na fila',
         format('%s entrou na fila de %s %s. Posição atual: %s. Os critérios aplicados podem ser consultados no portal.',
                split_part(s.full_name, ' ', 1), (select name from iara.grade_levels where id = v_grade), iara.da_unidade((select name from iara.education_units where id = v_unit)), v_pos)
  from iara.student_guardians sg where sg.student_id = v_student and sg.is_primary;
  if cardinality(v_flags) > 0 then
    perform iara.audit_event('PRIORITY_FLAG', 'waiting_list_entries', v_entry::text, v_unit, 'Critério rede de proteção: ' || (p ->> 'vulnerability_note'));
  end if;
  return api.queue_entry_detail(jsonb_build_object('entry_id', v_entry));
end $$;

create or replace function api.offer_create(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_key text := coalesce(nullif(p ->> 'idempotency_key', ''), 'auto-' || (p ->> 'entry_id') || '-' || (p ->> 'class_id'));
  o iara.vacancy_offers;
  w iara.waiting_list_entries;
  c iara.classes;
  v_before jsonb;
  v_hours integer := coalesce((iara.rule('PRAZO_RESPOSTA_OFERTA')).condition ->> 'hours', '48')::int;
  v_offer uuid := gen_random_uuid();
  v_unit_name text;
  v_child text;
  v_reason text := nullif(btrim(coalesce(p ->> 'priority_reason', '')), '');
  v_exception boolean := false;
begin
  perform iara.require_perm('offers.create');
  select * into o from iara.vacancy_offers where idempotency_key = v_key;
  if found then
    return jsonb_build_object('ok', true, 'idempotent', true, 'offer_id', o.id, 'status', o.status, 'expires_at', o.expires_at);
  end if;
  select * into w from iara.waiting_list_entries where id = (p ->> 'entry_id')::uuid for update;
  if not found or not iara.can_access_student(w.student_id) then
    raise exception 'Entrada de fila não encontrada ou fora do seu escopo.' using errcode = 'P0002';
  end if;
  if w.status <> 'WAITING' then
    raise exception 'Esta criança não está aguardando (situação atual: %).', w.status using errcode = '22023';
  end if;
  select * into c from iara.classes where id = (p ->> 'class_id')::uuid for update;
  if not found then
    raise exception 'Turma não encontrada.' using errcode = 'P0002';
  end if;
  if c.grade_level_id <> w.grade_level_id then
    raise exception 'A turma não corresponde à faixa/série da criança.' using errcode = '22023';
  end if;
  if c.unit_id <> w.preferred_unit_id and not (c.unit_id = any (w.alternative_unit_ids)) then
    raise exception 'A turma é de outra unidade. Registre a unidade como alternativa aceita pela família antes de ofertar.' using errcode = '22023';
  end if;
  if c.status <> 'ATIVA' then
    raise exception 'Turma não está ativa.' using errcode = '22023';
  end if;
  if c.offerable_vacancies_count < 1 then
    raise exception 'Sem vaga ofertável nesta turma: capacidade %, matrículas %, bloqueadas %, reservadas %.',
      c.authorized_capacity, c.active_enrollments_count, c.blocked_seats_count, c.reserved_seats_count using errcode = '22023';
  end if;
  if c.unit_id = w.preferred_unit_id and coalesce(w.position, 999) <> 1 then
    -- IN 025/2025, Anexo I: PCD/TEA/TGD/AH-SD com laudo médico (CID) têm prioridade sob análise, fora da soma de pontos.
    if v_reason is not null and 'PCD_TEA_AEE' = any (w.priority_flags) then
      if not exists (select 1 from iara.documents d where d.student_id = w.student_id and d.doc_type = 'LAUDO' and d.status = 'VALIDADO') then
        raise exception 'A prioridade sob análise exige laudo médico com CID validado pela equipe.' using errcode = '22023';
      end if;
      if length(v_reason) < 20 then
        raise exception 'Registre a análise da prioridade (laudo) com pelo menos 20 caracteres.' using errcode = '22023';
      end if;
      v_exception := true;
    else
      raise exception 'Há % criança(s) à frente na fila desta unidade/faixa. A oferta segue a ordem de classificação; fora dela, só por prioridade sob análise com laudo validado e justificativa.',
        coalesce(w.position, 1) - 1 using errcode = '22023';
    end if;
  end if;
  v_before := iara.class_snapshot(c.id);
  insert into iara.vacancy_offers (id, tenant_id, waiting_list_entry_id, student_id, class_id, unit_id, case_id, offered_at, expires_at, channel,
                                   status, ranking_snapshot, idempotency_key, created_by, is_demo)
  values (v_offer, 1, w.id, w.student_id, c.id, c.unit_id, w.case_id, now(), now() + make_interval(hours => v_hours),
          coalesce(nullif(p ->> 'channel', ''), 'WHATSAPP'), 'OFFERED',
          jsonb_build_object('position', w.position, 'score', w.priority_score, 'breakdown', w.score_breakdown, 'rule_version', iara.rule_version(),
                             'class_before', v_before, 'note', nullif(p ->> 'note', ''),
                             'priority_exception', case when v_exception then 'LAUDO' end, 'priority_reason', case when v_exception then v_reason end),
          v_key, iara.current_user_id(), true);
  update iara.waiting_list_entries set status = 'OFFERED' where id = w.id;
  perform iara.recalculate_queue(w.preferred_unit_id, w.grade_level_id);
  select name into v_unit_name from iara.education_units where id = c.unit_id;
  select split_part(full_name, ' ', 1) into v_child from iara.students where id = w.student_id;
  if w.case_id is not null then
    update iara.service_cases set status = 'VAGA_OFERTADA', closed_at = null, resolution_code = null, resolution_notes = null,
           sla_due_at = now() + make_interval(hours => v_hours) where id = w.case_id;
    insert into iara.case_events (case_id, event_type, message, new_value, user_id, actor_label, visibility)
    values (w.case_id, 'OFERTA', format('Vaga ofertada: %s · %s (%s). Prazo de resposta: %s horas.', v_unit_name, c.class_name, lower(c.shift), v_hours),
            'VAGA_OFERTADA', iara.current_user_id(), iara.my_label(), 'CIDADAO');
  end if;
  insert into iara.notifications (tenant_id, guardian_id, student_id, case_id, channel, event_type, title, body)
  select 1, sg.guardian_id, w.student_id, w.case_id, ch, 'VAGA_OFERTADA', 'Vaga ofertada para ' || v_child,
         format('Há uma vaga para %s %s (%s, turno %s). Responda até %s. Aceitar não é a matrícula: depois a unidade confere os documentos.',
                v_child, iara.na_unidade(v_unit_name), c.class_name, lower(c.shift), to_char((now() + make_interval(hours => v_hours)) at time zone 'America/Sao_Paulo', 'DD/MM às HH24:MI'))
  from iara.student_guardians sg cross join (values ('WHATSAPP'), ('PORTAL')) x(ch)
  where sg.student_id = w.student_id and sg.is_primary;
  insert into iara.vacancy_events (tenant_id, class_id, unit_id, event_type, quantity, before_json, after_json, reference, user_id, actor_label)
  values (1, c.id, c.unit_id, 'RESERVA', 1, v_before, iara.class_snapshot(c.id), 'Oferta ' || substr(v_offer::text, 1, 8), iara.current_user_id(), iara.my_label());
  perform iara.audit_event('OFFER_CREATED', 'vacancy_offers', v_offer::text, c.unit_id,
                           format('Oferta de vaga a %s (%s, pontuação %s) — %s · %s', v_child,
                                  case when v_exception then format('prioridade sob análise por laudo; %sº da fila', w.position) else '1º da fila' end,
                                  w.priority_score, v_unit_name, c.class_name),
                           jsonb_build_object('entry', w.id, 'class', c.id, 'rule_version', iara.rule_version()));
  if v_exception then
    perform iara.audit_event('PRIORITY_DECISION', 'waiting_list_entries', w.id::text, c.unit_id,
      format('Oferta fora da ordem de pontuação por prioridade sob análise (laudo PCD/TEA/TGD/AH-SD, IN nº 025/2025). Posição %s, pontuação %s. Justificativa: %s',
             w.position, w.priority_score, v_reason));
  end if;
  return jsonb_build_object('ok', true, 'offer_id', v_offer, 'status', 'OFFERED', 'expires_at', now() + make_interval(hours => v_hours),
                            'class_after', iara.class_snapshot(c.id),
                            'message', format('Oferta registrada e família notificada (simulado). Prazo: %s horas.%s', v_hours,
                                              case when v_exception then ' Prioridade sob análise (laudo) registrada na auditoria.' else '' end));
end $$;

create or replace function api.offer_respond(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  o iara.vacancy_offers;
  v_accept boolean := (p ->> 'accept')::boolean;
  v_reason text := nullif(trim(coalesce(p ->> 'reason', '')), '');
  v_child text;
  v_unit_name text;
  v_class text;
  v_missing text[];
  v_grade smallint;
begin
  if v_accept is null then
    raise exception 'Informe se a família aceita ou recusa a oferta.' using errcode = '22023';
  end if;
  select * into o from iara.vacancy_offers where id = (p ->> 'offer_id')::uuid for update;
  if not found then
    raise exception 'Oferta não encontrada.' using errcode = 'P0002';
  end if;
  if iara.my_scope() = 'GUARDIAN' then
    perform iara.require_perm('offers.respond_own');
    if not exists (select 1 from iara.student_guardians where student_id = o.student_id and guardian_id = iara.my_guardian()) then
      raise exception 'Esta oferta não é de uma criança sob sua responsabilidade.' using errcode = '42501';
    end if;
  else
    perform iara.require_perm('offers.respond');
    if not iara.can_access_student(o.student_id) then
      raise exception 'Fora do seu escopo.' using errcode = '42501';
    end if;
  end if;
  if o.status <> 'OFFERED' then
    raise exception 'Esta oferta não está aguardando resposta (situação: %).', o.status using errcode = '22023';
  end if;
  if o.expires_at < now() then
    perform iara.expire_due_offers();
    raise exception 'O prazo desta oferta terminou. A vaga foi liberada e a criança continua na fila.' using errcode = '22023';
  end if;
  select split_part(s.full_name, ' ', 1), u.name, c.class_name, c.grade_level_id into v_child, v_unit_name, v_class, v_grade
  from iara.students s, iara.education_units u, iara.classes c where s.id = o.student_id and u.id = o.unit_id and c.id = o.class_id;

  if v_accept then
    update iara.vacancy_offers set status = 'ACCEPTED', accepted_at = now(), response_channel = coalesce(nullif(p ->> 'channel', ''), 'PORTAL') where id = o.id;
    update iara.waiting_list_entries set status = 'ACCEPTED' where id = o.waiting_list_entry_id;
    select coalesce(array_agg(d), '{}') into v_missing
    from unnest((select required_documents from iara.service_catalog where code = 'MATRICULA')) d
    where not exists (select 1 from iara.documents x where x.student_id = o.student_id and x.doc_type = d and x.status = 'VALIDADO');
    if o.case_id is not null then
      insert into iara.case_events (case_id, event_type, message, new_value, user_id, actor_label, visibility)
      values (o.case_id, 'OFERTA', 'Aceite registrado. Aceite não é matrícula: a unidade vai conferir os documentos e confirmar a matrícula.',
              'ACEITE', iara.current_user_id(), iara.my_label(), 'CIDADAO');
    end if;
    insert into iara.notifications (tenant_id, guardian_id, student_id, case_id, channel, event_type, title, body)
    select 1, sg.guardian_id, o.student_id, o.case_id, 'PORTAL', 'ACEITE', 'Aceite registrado',
           format('Recebemos o aceite da vaga de %s %s. Próximo passo: a unidade confere os documentos e confirma a matrícula.%s',
                  v_child, iara.na_unidade(v_unit_name), case when cardinality(v_missing) > 0 then ' Pendentes: ' || array_to_string(v_missing, ', ') || '.' else '' end)
    from iara.student_guardians sg where sg.student_id = o.student_id and sg.is_primary;
    perform iara.audit_event('OFFER_ACCEPTED', 'vacancy_offers', o.id::text, o.unit_id, 'Aceite registrado para ' || v_child || ' (' || v_class || ')');
    return jsonb_build_object('ok', true, 'status', 'ACCEPTED', 'missing_documents', to_jsonb(v_missing),
      'message', 'Aceite registrado. Aceitar não é a matrícula: a unidade vai conferir os documentos e confirmar.');
  else
    if v_reason is null then
      raise exception 'Informe o motivo da recusa.' using errcode = '22023';
    end if;
    update iara.vacancy_offers set status = 'DECLINED', declined_at = now(), decline_reason = v_reason,
           response_channel = coalesce(nullif(p ->> 'channel', ''), 'PORTAL') where id = o.id;
    update iara.waiting_list_entries set status = 'WAITING', demand_category = 'RECUSOU_OFERTA' where id = o.waiting_list_entry_id;
    perform iara.recalculate_queue(o.unit_id, v_grade);
    if o.case_id is not null then
      update iara.service_cases set status = 'ENCERRADO', closed_at = now(), resolution_code = 'OFERTA_RECUSADA',
             resolution_notes = 'Oferta recusada pela família; criança mantida na fila conforme regra vigente.' where id = o.case_id;
      insert into iara.case_events (case_id, event_type, message, old_value, new_value, user_id, actor_label, visibility)
      values (o.case_id, 'OFERTA', 'Recusa registrada: ' || v_reason || '. Pela regra vigente, a criança volta à fila sem perder a pontuação.',
              'VAGA_OFERTADA', 'ENCERRADO', iara.current_user_id(), iara.my_label(), 'CIDADAO');
    end if;
    insert into iara.vacancy_events (tenant_id, class_id, unit_id, event_type, quantity, reference, user_id, actor_label)
    values (1, o.class_id, o.unit_id, 'LIBERACAO', 1, 'Recusa da oferta ' || substr(o.id::text, 1, 8), iara.current_user_id(), iara.my_label());
    perform iara.audit_event('OFFER_DECLINED', 'vacancy_offers', o.id::text, o.unit_id, 'Recusa registrada (' || v_reason || ')');
    return jsonb_build_object('ok', true, 'status', 'DECLINED',
      'message', 'Recusa registrada. Pela regra vigente, a criança continua na fila sem perder a pontuação.');
  end if;
end $$;

create or replace function api.enrollment_confirm(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  o iara.vacancy_offers;
  v_missing text[];
  v_before jsonb;
  v_enr uuid := gen_random_uuid();
  v_prev record;
  v_child text;
begin
  perform iara.require_perm('enrollment.confirm');
  select * into o from iara.vacancy_offers where id = (p ->> 'offer_id')::uuid for update;
  if not found or not iara.can_access_unit(o.unit_id) then
    raise exception 'Oferta não encontrada ou de outra unidade.' using errcode = 'P0002';
  end if;
  if o.status <> 'ACCEPTED' then
    raise exception 'A matrícula só pode ser confirmada após o aceite da família (situação atual: %).', o.status using errcode = '22023';
  end if;
  select coalesce(array_agg(d), '{}') into v_missing
  from unnest((select required_documents from iara.service_catalog where code = 'MATRICULA')) d
  where not exists (select 1 from iara.documents x where x.student_id = o.student_id and x.doc_type = d and x.status = 'VALIDADO');
  if cardinality(v_missing) > 0 then
    return jsonb_build_object('ok', false, 'missing_documents', to_jsonb(v_missing),
                              'message', 'Faltam documentos validados para concluir a matrícula: ' || array_to_string(v_missing, ', ') || '.');
  end if;
  v_before := iara.class_snapshot(o.class_id);
  select e.id, e.class_id, e.unit_id into v_prev from iara.enrollments e where e.student_id = o.student_id and e.status = 'ACTIVE' limit 1;
  if v_prev.id is not null then
    update iara.enrollments set status = 'TRANSFERRED', exit_type = 'TRANSFERENCIA_INTERNA', end_date = current_date where id = v_prev.id;
    insert into iara.vacancy_events (tenant_id, class_id, unit_id, event_type, quantity, reference, user_id, actor_label)
    values (1, v_prev.class_id, v_prev.unit_id, 'TRANSF_SAIDA', 1, 'Transferência interna ' || substr(o.id::text, 1, 8), iara.current_user_id(), iara.my_label());
  end if;
  insert into iara.enrollments (id, tenant_id, student_id, class_id, unit_id, school_year, status, enrollment_date, start_date, entry_type,
                                source_protocol_id, previous_enrollment_id, created_by, is_demo)
  values (v_enr, 1, o.student_id, o.class_id, o.unit_id, iara.school_year(), 'ACTIVE', current_date, current_date,
          case when v_prev.id is not null then 'TRANSFERENCIA' else 'OFERTA_FILA' end, o.case_id, v_prev.id, iara.current_user_id(), true);
  update iara.vacancy_offers set status = 'ENROLLED' where id = o.id;
  update iara.waiting_list_entries set status = 'MATRICULATED' where id = o.waiting_list_entry_id;
  update iara.students set status = 'MATRICULADO', current_enrollment_id = v_enr where id = o.student_id;
  select split_part(full_name, ' ', 1) into v_child from iara.students where id = o.student_id;
  if o.case_id is not null then
    update iara.service_cases set status = 'MATRICULA_CONCLUIDA', closed_at = now(), resolution_code = 'MATRICULADO',
           resolution_notes = 'Matrícula confirmada pela unidade.' where id = o.case_id;
    insert into iara.case_events (case_id, event_type, message, old_value, new_value, user_id, actor_label, visibility)
    values (o.case_id, 'MATRICULA', 'Matrícula confirmada pela unidade. Atendimento concluído.', 'VAGA_OFERTADA', 'MATRICULA_CONCLUIDA',
            iara.current_user_id(), iara.my_label(), 'CIDADAO');
  end if;
  insert into iara.notifications (tenant_id, guardian_id, student_id, case_id, channel, event_type, title, body)
  select 1, sg.guardian_id, o.student_id, o.case_id, ch, 'MATRICULA', 'Matrícula confirmada! 🎉',
         format('A matrícula de %s %s está confirmada (%s). Bem-vindo(a) à rede municipal de Maringá!', v_child,
                iara.na_unidade((select name from iara.education_units where id = o.unit_id)), (select class_name from iara.classes where id = o.class_id))
  from iara.student_guardians sg cross join (values ('WHATSAPP'), ('PORTAL')) x(ch) where sg.student_id = o.student_id and sg.is_primary;
  insert into iara.vacancy_events (tenant_id, class_id, unit_id, event_type, quantity, before_json, after_json, reference, user_id, actor_label)
  values (1, o.class_id, o.unit_id, 'MATRICULA', 1, v_before, iara.class_snapshot(o.class_id), 'Oferta ' || substr(o.id::text, 1, 8), iara.current_user_id(), iara.my_label());
  perform iara.audit_event('ENROLLMENT_CONFIRMED', 'enrollments', v_enr::text, o.unit_id, 'Matrícula confirmada a partir da oferta ' || substr(o.id::text, 1, 8));
  return jsonb_build_object('ok', true, 'enrollment_id', v_enr, 'class_after', iara.class_snapshot(o.class_id),
                            'message', 'Matrícula confirmada. A família foi notificada (simulado).');
end $$;

create or replace function api.document_set(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_type text := p ->> 'doc_type';
  v_status text := p ->> 'status';
  d iara.documents;
begin
  if iara.my_scope() = 'GUARDIAN' then
    perform iara.require_perm('documents.submit_own');
    if not exists (select 1 from iara.student_guardians where student_id = v_student and guardian_id = iara.my_guardian()) then
      raise exception 'Documento de criança fora da sua responsabilidade.' using errcode = '42501';
    end if;
    if v_status <> 'RECEBIDO' then
      raise exception 'O responsável pode apenas enviar documentos; a validação é feita pela unidade.' using errcode = '42501';
    end if;
  else
    perform iara.require_perm('documents.manage');
    if not iara.can_access_student(v_student) then
      raise exception 'Aluno fora do seu escopo.' using errcode = '42501';
    end if;
  end if;
  if v_status not in ('PENDENTE', 'RECEBIDO', 'VALIDADO', 'REJEITADO') then
    raise exception 'Status de documento inválido.' using errcode = '22023';
  end if;
  select * into d from iara.documents where student_id = v_student and doc_type = v_type order by created_at desc limit 1 for update;
  if found then
    update iara.documents set status = v_status,
           received_at = case when v_status in ('RECEBIDO', 'VALIDADO') then coalesce(received_at, now()) else received_at end,
           validated_at = case when v_status = 'VALIDADO' then now() end,
           validated_by = case when v_status = 'VALIDADO' then iara.current_user_id() end,
           file_name = coalesce(file_name, case when v_status in ('RECEBIDO', 'VALIDADO') then lower(v_type) || '_recebido.pdf' end),
           notes = coalesce(nullif(p ->> 'notes', ''), notes)
    where id = d.id returning * into d;
  else
    insert into iara.documents (tenant_id, student_id, case_id, doc_type, status, file_name, received_at, validated_at, validated_by, notes, is_sensitive, is_demo)
    values (1, v_student, nullif(p ->> 'case_id', '')::uuid, v_type, v_status,
            case when v_status in ('RECEBIDO', 'VALIDADO') then lower(v_type) || '_recebido.pdf' end,
            case when v_status in ('RECEBIDO', 'VALIDADO') then now() end, case when v_status = 'VALIDADO' then now() end,
            case when v_status = 'VALIDADO' then iara.current_user_id() end, nullif(p ->> 'notes', ''),
            v_type in ('LAUDO', 'DECISAO_JUDICIAL'), true)
    returning * into d;
  end if;
  -- laudo muda a evidência do critério de prioridade sob análise: atualiza a explicação na fila
  if v_type = 'LAUDO' then
    perform iara.compute_queue_priority(w.id) from iara.waiting_list_entries w
    where w.student_id = v_student and w.status in ('WAITING', 'OFFERED', 'ACCEPTED');
  end if;
  return jsonb_build_object('ok', true, 'document', jsonb_build_object('id', d.id, 'type', d.doc_type, 'status', d.status,
                            'received_at', d.received_at, 'validated_at', d.validated_at));
end $$;

create or replace function api.guardian_create(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id uuid := gen_random_uuid();
  v_addr uuid;
  v_cpf text := nullif(regexp_replace(coalesce(p ->> 'cpf', ''), '\D', '', 'g'), '');
  v_dups jsonb;
begin
  perform iara.require_perm('guardians.write');
  if length(coalesce(p ->> 'full_name', '')) < 5 then
    raise exception 'Informe o nome completo do responsável.' using errcode = '22023';
  end if;
  if not coalesce((p ->> 'force')::boolean, false) then
    select jsonb_agg(jsonb_build_object('id', g.id, 'name', g.full_name, 'phone', iara.mask_phone(g.primary_phone))) into v_dups
    from iara.guardians g
    where (v_cpf is not null and regexp_replace(coalesce(g.cpf, ''), '\D', '', 'g') = v_cpf)
       or (iara.norm(g.full_name) = iara.norm(p ->> 'full_name') and regexp_replace(coalesce(g.primary_phone, ''), '\D', '', 'g') = regexp_replace(coalesce(p ->> 'phone', ''), '\D', '', 'g'));
    if v_dups is not null then
      return jsonb_build_object('ok', false, 'duplicates', v_dups, 'message', 'Possível cadastro duplicado. Confira antes de continuar.');
    end if;
  end if;
  if p ? 'address' and (p -> 'address' ->> 'lat') is not null then
    insert into iara.addresses (tenant_id, street, number, complement, neighborhood, postal_code, location, geocode_precision, geocode_source, is_demo)
    values (1, coalesce(p -> 'address' ->> 'street', 'Endereço informado'), p -> 'address' ->> 'number', p -> 'address' ->> 'complement',
            p -> 'address' ->> 'neighborhood', p -> 'address' ->> 'postal_code',
            iara.point((p -> 'address' ->> 'lat')::float8, (p -> 'address' ->> 'lng')::float8),
            coalesce(p -> 'address' ->> 'precision', 'PONTO_NO_MAPA'), 'Informado no atendimento', true)
    returning id into v_addr;
  end if;
  insert into iara.guardians (id, tenant_id, full_name, cpf, birth_date, email, primary_phone, whatsapp_phone, address_id, cadunico_status, single_mother,
                              family_income, income_bracket, occupation, consent_flags, created_by, is_demo)
  values (v_id, 1, p ->> 'full_name', p ->> 'cpf', nullif(p ->> 'birth_date', '')::date, nullif(p ->> 'email', ''), nullif(p ->> 'phone', ''),
          coalesce(nullif(p ->> 'whatsapp', ''), nullif(p ->> 'phone', '')), v_addr, coalesce((p ->> 'cadunico')::boolean, false), coalesce((p ->> 'single_mother')::boolean, false),
          nullif(p ->> 'family_income', '')::numeric, nullif(p ->> 'income_bracket', ''), nullif(p ->> 'occupation', ''),
          jsonb_build_object('lgpd_ciencia', true, 'registrado_em', now()), iara.current_user_id(), true);
  return jsonb_build_object('ok', true, 'guardian_id', v_id, 'address_id', v_addr);
end $$;

create or replace function iara.guardian_json(g iara.guardians) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object(
    'id', g.id, 'full_name', g.full_name, 'social_name', g.social_name,
    'cpf', case when iara.can_see_contacts() then g.cpf else iara.mask_cpf(g.cpf) end,
    'phone', case when iara.can_see_contacts() then g.primary_phone else iara.mask_phone(g.primary_phone) end,
    'whatsapp', case when iara.can_see_contacts() then g.whatsapp_phone else iara.mask_phone(g.whatsapp_phone) end,
    'email', case when iara.can_see_contacts() then g.email else regexp_replace(coalesce(g.email, ''), '^(.).*(@.*)$', '\1•••\2') end,
    'contacts_masked', not iara.can_see_contacts(),
    'preferred_channel', g.preferred_contact_channel, 'birth_date', g.birth_date, 'occupation', g.occupation,
    'employment_status', g.employment_status, 'family_income', g.family_income, 'income_bracket', g.income_bracket,
    'cadunico', g.cadunico_status, 'single_mother', g.single_mother, 'nis', case when iara.can_see_contacts() then g.nis else null end, 'benefits', g.benefits,
    'education_level', g.education_level, 'household_size', g.household_size, 'consent', g.consent_flags, 'is_demo', g.is_demo)
$$;

create or replace function api.rules_list(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('version', iara.rule_version(), 'items', coalesce(jsonb_agg(jsonb_build_object(
      'code', rule_code, 'version', version, 'name', name, 'description', description, 'type', rule_type, 'condition', condition,
      'weight', weight, 'source', source, 'justification', justification, 'valid_from', valid_from, 'valid_to', valid_to,
      'active', is_active, 'test', test_reference, 'source_kind', source_kind, 'source_url', source_url)
      order by is_active desc, sort, version desc), '[]'::jsonb))
  from iara.rules where tenant_id = 1
$$;

-- 5. Base de conhecimento da IARA ----------------------------------------------
update iara.knowledge_articles set
  body = 'A ordem da fila segue a Instrução Normativa nº 025/2025 da SEDUC (Anexo I). Critérios de pontuação: irmão(ã) já matriculado(a) na mesma unidade (55 pontos), família de baixa renda inscrita no CadÚnico (25), residência a até 2 km da unidade (15) e filho(a) de mãe solo (5) — no máximo 100 pontos. Estudantes com deficiência (PCD), TEA, TGD e/ou altas habilidades/superdotação têm prioridade sob análise, mediante laudo médico com CID, separada da soma de pontos. Em caso de empate, vale a data da solicitação. Você vê os critérios aplicados à sua criança, nunca dados de outras crianças.',
  keywords = '{fila,posicao,criterio,criterios,espera,prioridade,pontuacao,pontos,irmao,cadunico,mae,solo,laudo}',
  source = 'IN nº 025/2025-SEDUC, Anexo I (texto da equipe IARA — revisão SEDUC pendente)', version = '2.0'
where title = 'Como funciona a fila de espera';

update iara.knowledge_articles set
  body = 'Estudantes com deficiência (PCD), TEA, TGD e/ou altas habilidades/superdotação têm prioridade sob análise na fila, mediante laudo médico com informação do(s) CID(s) (IN nº 025/2025-SEDUC, Anexo I). Essa prioridade não entra na soma de pontos: a Central de Vagas analisa cada caso. Laudos e documentos sensíveis são enviados por fluxo seguro e têm acesso restrito.',
  keywords = '{aee,inclusao,deficiencia,tea,tgd,autismo,laudo,cid,superdotacao,altas,habilidades}',
  source = 'IN nº 025/2025-SEDUC, Anexo I (texto da equipe IARA — revisão SEDUC pendente)', version = '2.0'
where title = 'Inclusão e AEE';

-- 6. Recalcula toda a fila com as regras 2026.02 -----------------------------------
do $$
declare
  v_n integer;
begin
  perform iara.compute_queue_priority(id) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED', 'ACCEPTED');
  select count(*) into v_n from iara.waiting_list_entries where status in ('WAITING', 'OFFERED', 'ACCEPTED');
  perform iara.recalculate_all_queues();
  perform iara.audit_event('RULE_VERSION', 'rules', '2026.02', null,
    format('Pontuação da fila atualizada conforme a IN nº 025/2025-SEDUC, Anexo I (irmão na mesma unidade 55, CadÚnico 25, até 2 km 15, mãe solo 5; PCD/TEA/TGD/AH-SD com laudo: prioridade sob análise, fora da soma). %s entrada(s) recalculada(s).', v_n));
end $$;

commit;
