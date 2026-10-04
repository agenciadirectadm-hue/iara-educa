-- =============================================================================
-- IARA Educa · IARA resolutiva e vida da família
--
--  1. Prazo oficial de 72 h para efetivar a matrícula após a contemplação (IN nº 025/2025-SEDUC, Anexo II)
--  2. Alçada de cada serviço — IARA resolve na hora · secretaria da UNIDADE · SECRETARIA (SEDUC) —
--     e roteamento automático dos protocolos (equipe e unidade responsáveis)
--  3. Persona "Família recém-chegada a Maringá" (sem cadastro): cadastro pelo WhatsApp ou pelo portal
--  4. Funções únicas da família, usadas igualmente pela IARA (WhatsApp) e pelo portal:
--     cadastro, novo membro (criança/adulto), mudança de endereço, atualização de dados e declarações,
--     inscrição na fila de espera on-line (inclusive transferência de outro município) e desistência
--
-- Após aplicar: reaplicar 20261003009900_privilegios.sql e publicar o gateway.
-- =============================================================================
begin;

-- 1. Prazo oficial de 72 h ------------------------------------------------------
update iara.rules set is_active = false, valid_to = coalesce(valid_to, current_date - 1)
where tenant_id = 1 and version = '2026.01' and rule_code = 'PRAZO_RESPOSTA_OFERTA';

insert into iara.rules (tenant_id, rule_code, version, name, description, rule_type, condition, weight, source, justification,
                        valid_from, is_active, test_reference, sort, source_kind, source_url)
values (1, 'PRAZO_RESPOSTA_OFERTA', '2026.02', 'Prazo para efetivar a matrícula após a contemplação',
  'Comunicada a contemplação (oferta da vaga), o responsável legal tem 72 horas para comparecer à unidade e efetivar a matrícula com todos os documentos obrigatórios. Sem resposta no prazo, a vaga volta a ser ofertada seguindo a fila.',
  'PARAMETRO', '{"hours": 72}', 0, 'IN nº 025/2025-SEDUC (19/11/2025), Anexo II',
  'Cronograma de inscrições para 2026 (Anexo II da IN nº 025/2025): após ser comunicado da contemplação, o responsável legal tem 72 horas para comparecer presencialmente à unidade de ensino e efetivar a matrícula com todos os documentos obrigatórios. SEI nº 7410308.',
  current_date, true, 'oferta: prazo de 72 h', 40, 'OFICIAL', 'http://www3.maringa.pr.gov.br/sistema/arquivos/5e336fc8c680.pdf')
on conflict (tenant_id, rule_code, version) do update set
  name = excluded.name, description = excluded.description, condition = excluded.condition, source = excluded.source,
  justification = excluded.justification, is_active = true, valid_to = null, test_reference = excluded.test_reference,
  sort = excluded.sort, source_kind = excluded.source_kind, source_url = excluded.source_url;

-- ofertas em andamento passam a valer 72 h desde a contemplação
with x as (
  update iara.vacancy_offers o set expires_at = o.offered_at + interval '72 hours'
  where o.status in ('OFFERED', 'ACCEPTED') and o.expires_at < o.offered_at + interval '72 hours'
  returning o.id, o.case_id, o.expires_at, o.status)
update iara.service_cases c set sla_due_at = x.expires_at
from x where c.id = x.case_id and x.status = 'OFFERED' and c.status = 'VAGA_OFERTADA';

-- 2. Alçadas dos serviços ---------------------------------------------------------
alter table iara.service_catalog add column if not exists resolution_level text not null default 'SECRETARIA';
alter table iara.service_catalog drop constraint if exists service_catalog_resolution_level_check;
alter table iara.service_catalog add constraint service_catalog_resolution_level_check
  check (resolution_level in ('IARA', 'UNIDADE', 'SECRETARIA'));
alter table iara.service_catalog add column if not exists team text not null default 'CENTRAL_VAGAS';
alter table iara.service_catalog add column if not exists iara_action text;
alter table iara.service_catalog add column if not exists escalation text;

insert into iara.service_catalog (code, tenant_id, name, description, audience, requirements, required_documents, sector, sla_days, actions, source, is_demo, sort)
values
  ('TRANSFERENCIA_EXTERNA', 1, 'Vaga para quem vem de outro município',
   'Família que chegou a Maringá (ou estudante de outra rede) pede vaga: cadastro, inscrição na fila de espera on-line e documentos da transferência.',
   'CIDADAO', 'Endereço em Maringá.', '{CERTIDAO,CPF,COMPROVANTE_ENDERECO,TRANSFERENCIA,VACINACAO}', 'Central de Vagas', 10, '{}',
   'IN nº 023/2025 e nº 025/2025-SEDUC (fila de espera on-line)', true, 17),
  ('INCLUSAO_MEMBRO', 1, 'Novo membro da família',
   'Inclusão de criança (dependente) ou de outro responsável no cadastro da família.',
   'CIDADAO', null, '{CERTIDAO}', 'Central de Vagas', 5, '{}', 'Catálogo de serviços — DEMO', true, 18)
on conflict (code) do nothing;

update iara.service_catalog c set resolution_level = m.lvl, team = m.team, iara_action = m.ia, escalation = m.esc
from (values
  ('SOLICITACAO_VAGA', 'IARA', 'CENTRAL_VAGAS',
   'Inscreve a criança na fila de espera on-line da unidade escolhida e informa posição, pontos e documentos.',
   'A oferta é feita pela Central de Vagas, seguindo a ordem da fila; o aviso chega pelo WhatsApp com prazo de 72 h.'),
  ('TRANSFERENCIA_EXTERNA', 'IARA', 'CENTRAL_VAGAS',
   'Faz o cadastro da família, inclui as crianças e já inscreve na fila de espera on-line.',
   'A Central de Vagas confere a declaração de transferência e oferta a vaga pela ordem da fila.'),
  ('TRANSFERENCIA', 'IARA', 'CENTRAL_VAGAS',
   'Inscreve na fila de transferência da unidade desejada; a matrícula atual continua valendo.',
   'A Central de Vagas oferta quando houver vaga, seguindo a fila.'),
  ('MUDANCA_ENDERECO', 'IARA', 'CENTRAL_VAGAS',
   'Atualiza o endereço na hora, recalcula a fila (residência até 2 km) e mostra as unidades perto da nova casa.',
   'O comprovante de endereço é conferido na matrícula; mudança de unidade vira inscrição na fila de transferência.'),
  ('INCLUSAO_MEMBRO', 'IARA', 'CENTRAL_VAGAS',
   'Inclui a criança na família na hora (faixa pela data de nascimento) e já pode inscrevê-la na fila.',
   'Responsável que não é pai ou mãe (ex.: avó com guarda) é validado pela secretaria da unidade com o documento de guarda.'),
  ('ATUALIZACAO_CADASTRAL', 'IARA', 'SECRETARIA_ESCOLAR',
   'Atualiza telefone, e-mail e declarações (CadÚnico, mãe solo) e recalcula a fila.',
   'Comprovantes são conferidos na matrícula; divergências vão para a secretaria da unidade.'),
  ('DESISTENCIA', 'IARA', 'CENTRAL_VAGAS',
   'Retira a criança da fila de espera na hora, com protocolo.',
   'Desistência de matrícula ativa vai para a secretaria da unidade.'),
  ('DUVIDA', 'IARA', 'ATENDIMENTO',
   'Responde com a base oficial de conhecimento, citando a fonte.',
   'Sem resposta oficial vigente, encaminha ao Atendimento ao Cidadão.'),
  ('MATRICULA', 'UNIDADE', 'SECRETARIA_ESCOLAR',
   'Mostra o que falta, recebe documentos e registra o aceite da vaga.',
   'A secretaria da unidade confere os documentos e confirma a matrícula.'),
  ('TROCA_TURNO', 'UNIDADE', 'SECRETARIA_ESCOLAR',
   'Verifica na hora se há vaga no outro turno da mesma série.',
   'A secretaria da unidade decide a troca e ajusta a turma.'),
  ('DOCUMENTO', 'UNIDADE', 'SECRETARIA_ESCOLAR',
   'Informa na hora a situação da matrícula (unidade, turma e turno).',
   'Declarações oficiais são emitidas e assinadas pela secretaria da unidade.'),
  ('ALTERACAO_RESPONSAVEL', 'UNIDADE', 'SECRETARIA_ESCOLAR',
   'Registra o pedido e informa os documentos necessários.',
   'A secretaria da unidade confere o termo de guarda ou a decisão judicial.'),
  ('INTEGRAL', 'SECRETARIA', 'INTEGRAL',
   'Registra o pedido com a declaração de trabalho e informa os critérios.',
   'A Gerência de Educação Integral analisa a disponibilidade.'),
  ('TRANSPORTE', 'SECRETARIA', 'TRANSPORTE',
   'Registra o pedido com endereço e escola e informa os critérios de elegibilidade.',
   'A Gerência de Transporte Escolar avalia a elegibilidade e a rota.'),
  ('AEE', 'SECRETARIA', 'AEE',
   'Recebe o laudo, registra a necessidade e explica a prioridade sob análise na fila.',
   'A equipe de inclusão e AEE avalia o caso.'),
  ('ALIMENTACAO', 'SECRETARIA', 'ALIMENTACAO',
   'Registra a necessidade (ex.: dieta especial) com o laudo.',
   'As nutricionistas da Merenda Escolar avaliam junto com a unidade.'),
  ('RECLAMACAO', 'SECRETARIA', 'OUVIDORIA',
   'Registra a manifestação com protocolo e prazo.',
   'A Ouvidoria da SEDUC responde no prazo.'),
  ('RECURSO', 'SECRETARIA', 'GESTAO',
   'Mostra os critérios aplicados e registra o recurso.',
   'A Diretoria de Gestão Educacional analisa o recurso.')
) as m(code, lvl, team, ia, esc)
where c.code = m.code;

alter table iara.service_cases add column if not exists details jsonb not null default '{}'::jsonb;
alter table iara.service_cases add column if not exists resolution_level text;
alter table iara.service_cases disable trigger audit_service_cases;
update iara.service_cases c set resolution_level = s.resolution_level
from iara.service_catalog s where s.code = c.case_type and c.resolution_level is null;
alter table iara.service_cases enable trigger audit_service_cases;

-- 3. Auxiliares ---------------------------------------------------------------------
create or replace function iara.team_label(p_team text) returns text
language sql immutable set search_path = iara, public
as $$
  select case p_team
    when 'CENTRAL_VAGAS' then 'Central de Vagas da SEDUC'
    when 'SECRETARIA_ESCOLAR' then 'secretaria da unidade'
    when 'TRANSPORTE' then 'Gerência de Transporte Escolar (SEDUC)'
    when 'AEE' then 'equipe de inclusão e AEE (SEDUC)'
    when 'INTEGRAL' then 'Gerência de Educação Integral (SEDUC)'
    when 'ALIMENTACAO' then 'Merenda Escolar (SEDUC)'
    when 'OUVIDORIA' then 'Ouvidoria da SEDUC'
    when 'GESTAO' then 'Diretoria de Gestão Educacional (SEDUC)'
    when 'ATENDIMENTO' then 'Atendimento ao Cidadão (SEDUC)'
    else coalesce(p_team, 'SEDUC') end
$$;

-- Para onde vai um pedido: alçada da unidade (escola/CMEI da criança) ou da Secretaria
create or replace function iara.route_case(p_type text, p_student uuid, p_unit integer) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_sc iara.service_catalog;
  v_unit integer := p_unit;
  v_level text;
  v_team text;
  v_name text;
begin
  select * into v_sc from iara.service_catalog where code = p_type;
  v_level := coalesce(v_sc.resolution_level, 'SECRETARIA');
  v_team := coalesce(v_sc.team, 'CENTRAL_VAGAS');
  if v_unit is null and p_student is not null then
    select unit_id into v_unit from iara.enrollments where student_id = p_student and status = 'ACTIVE' limit 1;
  end if;
  if v_level = 'UNIDADE' and v_unit is null then
    v_level := 'SECRETARIA';
    v_team := 'CENTRAL_VAGAS';
  elsif v_level = 'UNIDADE' then
    v_team := 'SECRETARIA_ESCOLAR';
  end if;
  select name into v_name from iara.education_units where id = v_unit;
  return jsonb_build_object(
    'level', v_level, 'team', v_team,
    'team_label', case when v_level = 'UNIDADE' and v_name is not null then 'secretaria ' || iara.da_unidade(v_name) else iara.team_label(v_team) end,
    'unit_id', v_unit, 'unit_name', v_name, 'sla_days', v_sc.sla_days, 'iara_action', v_sc.iara_action, 'escalation', v_sc.escalation);
end $$;

-- Registro (protocolo) de algo que a IARA resolveu na hora
create or replace function iara.iara_case(p_type text, p_guardian uuid, p_student uuid, p_unit integer, p_subject text, p_message text,
                                          p_details jsonb, p_channel text) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id uuid := gen_random_uuid();
  v_protocol text := iara.next_protocol();
  v_sc iara.service_catalog;
begin
  select * into v_sc from iara.service_catalog where code = p_type;
  insert into iara.service_cases (id, tenant_id, protocol_number, case_type, channel, status, priority, student_id, guardian_id, unit_id,
                                  assigned_team, subject, description, opened_at, sla_due_at, closed_at, resolution_code, resolution_notes,
                                  details, resolution_level, created_by, is_demo)
  values (v_id, 1, v_protocol, p_type, coalesce(p_channel, 'WEB'), 'ENCERRADO', 'NORMAL', p_student, p_guardian, p_unit,
          coalesce(v_sc.team, 'CENTRAL_VAGAS'), p_subject, p_message, now(), now() + make_interval(days => coalesce(v_sc.sla_days, 5)), now(),
          'RESOLVIDO_IARA', p_message, coalesce(p_details, '{}'::jsonb), 'IARA', iara.current_user_id(), true);
  insert into iara.case_events (case_id, event_type, message, new_value, user_id, actor_label, visibility)
  values (v_id, 'RESOLVIDO', p_message, 'ENCERRADO', iara.current_user_id(),
          case when coalesce(p_channel, 'WEB') = 'WHATSAPP' then 'IARA (WhatsApp)' else coalesce(iara.my_label(), 'Portal da família') end, 'CIDADAO');
  return jsonb_build_object('case_id', v_id, 'protocol', v_protocol);
end $$;

-- Responsável sobre quem a ação recai: o próprio (WhatsApp/portal) ou o informado por um servidor
create or replace function iara.family_guardian(p jsonb, p_allow_null boolean default false) returns uuid
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v uuid;
begin
  if iara.my_scope() = 'GUARDIAN' then
    perform iara.require_perm('cases.write_own');
    v := iara.my_guardian();
    if v is null and not p_allow_null then
      raise exception 'Primeiro faça o cadastro da família (responsável e endereço).' using errcode = '22023';
    end if;
    return v;
  end if;
  perform iara.require_perm('guardians.write');
  v := nullif(p ->> 'guardian_id', '')::uuid;
  if v is null or not exists (select 1 from iara.guardians where id = v) then
    raise exception 'Responsável não encontrado.' using errcode = 'P0002';
  end if;
  return v;
end $$;

create or replace function iara.in_maringa(p_lat float8, p_lng float8) returns boolean
language sql stable security definer set search_path = iara, extensions, public
as $$
  select coalesce((select st_covers(t.geom, iara.point(p_lat, p_lng)) from iara.territories t where t.code = 'MUNICIPIO' limit 1), true)
$$;

create or replace function iara.new_address(p_addr jsonb, p_source text) returns uuid
language plpgsql security definer set search_path = iara, extensions, public
as $$
declare
  v_id uuid := gen_random_uuid();
  v_lat float8 := nullif(p_addr ->> 'lat', '')::float8;
  v_lng float8 := nullif(p_addr ->> 'lng', '')::float8;
  v_terr integer;
begin
  if v_lat is null or v_lng is null then
    raise exception 'Informe o bairro (ou marque o ponto no mapa) para localizar o endereço.' using errcode = '22023';
  end if;
  if not iara.in_maringa(v_lat, v_lng) then
    raise exception 'Este endereço fica fora de Maringá. A fila da rede municipal considera o endereço no município.' using errcode = '22023';
  end if;
  select t.id into v_terr from iara.territories t
  where t.kind in ('MACRORREGIAO', 'DISTRITO') and st_covers(t.geom, iara.point(v_lat, v_lng))
  order by (t.kind = 'DISTRITO') desc limit 1;
  insert into iara.addresses (id, tenant_id, street, number, complement, neighborhood, postal_code, location, geocode_precision, geocode_source,
                              territory_id, is_demo)
  values (v_id, 1, coalesce(nullif(btrim(p_addr ->> 'street'), ''), 'Endereço informado'), nullif(btrim(p_addr ->> 'number'), ''),
          nullif(btrim(p_addr ->> 'complement'), ''), nullif(btrim(p_addr ->> 'neighborhood'), ''), nullif(btrim(p_addr ->> 'postal_code'), ''),
          iara.point(v_lat, v_lng), coalesce(nullif(p_addr ->> 'precision', ''), 'BAIRRO'), p_source, v_terr, true);
  return v_id;
end $$;

-- Fila das crianças antes/depois de uma mudança (para mostrar o impacto à família)
create or replace function iara.queue_snapshot(p_students uuid[]) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', w.id, 'student_id', w.student_id, 'child', split_part(s.full_name, ' ', 1),
      'unit_id', w.preferred_unit_id, 'unit', u.name, 'grade', gl.name, 'position', w.position, 'score', w.priority_score,
      'distance_m', w.home_distance_m, 'flags', w.priority_flags) order by s.full_name), '[]'::jsonb)
  from iara.waiting_list_entries w
  join iara.students s on s.id = w.student_id
  join iara.education_units u on u.id = w.preferred_unit_id
  join iara.grade_levels gl on gl.id = w.grade_level_id
  where w.student_id = any (p_students) and w.status = 'WAITING'
$$;

create or replace function iara.requeue_students(p_students uuid[]) returns void
language plpgsql security definer set search_path = iara, public
as $$
declare
  r record;
begin
  perform iara.compute_queue_priority(w.id) from iara.waiting_list_entries w
  where w.student_id = any (p_students) and w.status in ('WAITING', 'OFFERED', 'ACCEPTED');
  for r in select distinct preferred_unit_id, grade_level_id from iara.waiting_list_entries
           where student_id = any (p_students) and status = 'WAITING' loop
    perform iara.recalculate_queue(r.preferred_unit_id, r.grade_level_id);
  end loop;
end $$;

create or replace function iara.queue_impacts(p_before jsonb, p_after jsonb) returns jsonb
language sql immutable set search_path = iara, public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'entry_id', a ->> 'entry_id', 'child', a ->> 'child', 'unit', a ->> 'unit', 'grade', a ->> 'grade',
      'position_before', (b ->> 'position')::int, 'position_after', (a ->> 'position')::int,
      'score_before', (b ->> 'score')::numeric, 'score_after', (a ->> 'score')::numeric,
      'distance_before', (b ->> 'distance_m')::int, 'distance_after', (a ->> 'distance_m')::int,
      'changed', (b ->> 'position') is distinct from (a ->> 'position') or (b ->> 'score') is distinct from (a ->> 'score'))), '[]'::jsonb)
  from jsonb_array_elements(p_after) a
  left join jsonb_array_elements(p_before) b on b ->> 'entry_id' = a ->> 'entry_id'
$$;

create or replace function iara.family_json(p_guardian uuid) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object(
    'guardian', (select jsonb_build_object('id', g.id, 'name', g.full_name, 'first_name', split_part(g.full_name, ' ', 1),
        'phone', iara.mask_phone(g.primary_phone), 'whatsapp', iara.mask_phone(g.whatsapp_phone), 'email', g.email,
        'cadunico', g.cadunico_status, 'single_mother', g.single_mother, 'gender', g.gender, 'address', iara.address_json(g.address_id))
      from iara.guardians g where g.id = p_guardian),
    'children', coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'name', s.full_name, 'first_name', split_part(s.full_name, ' ', 1), 'birth_date', s.birth_date,
        'age', iara.age_text(s.birth_date), 'status', s.status, 'relationship', sg.relationship, 'avatar_seed', s.avatar_seed,
        'aee', s.aee_status, 'grade_rule', iara.grade_for_birthdate(s.birth_date),
        'same_address', s.address_id is not distinct from (select address_id from iara.guardians where id = p_guardian),
        'school', (select jsonb_build_object('unit_id', u.id, 'unit', u.name, 'class', c.class_name, 'shift', c.shift, 'grade_level_id', c.grade_level_id)
                   from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.education_units u on u.id = e.unit_id
                   where e.student_id = s.id and e.status = 'ACTIVE' limit 1),
        'queue', (select jsonb_agg(jsonb_build_object('id', w.id, 'status', w.status, 'position', w.position, 'score', w.priority_score,
                    'unit_id', w.preferred_unit_id, 'unit', u.name, 'grade', gl.name, 'grade_level_id', w.grade_level_id,
                    'category', w.demand_category, 'entered_at', w.entered_at) order by w.entered_at desc)
                  from iara.waiting_list_entries w join iara.education_units u on u.id = w.preferred_unit_id
                  join iara.grade_levels gl on gl.id = w.grade_level_id
                  where w.student_id = s.id and w.status in ('WAITING', 'OFFERED', 'ACCEPTED')))
        order by s.birth_date)
      from iara.student_guardians sg join iara.students s on s.id = sg.student_id where sg.guardian_id = p_guardian), '[]'::jsonb),
    'adults', coalesce((select jsonb_agg(x order by x ->> 'name') from (
        select jsonb_build_object('id', g.id, 'name', g.full_name, 'is_me', g.id = p_guardian,
                                  'relationships', jsonb_agg(distinct sg.relationship), 'legal_authority', min(sg.legal_authority_status),
                                  'primary', bool_or(sg.is_primary)) as x
        from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
        where sg.student_id in (select student_id from iara.student_guardians where guardian_id = p_guardian) or g.id = p_guardian
        group by g.id, g.full_name) z), '[]'::jsonb),
    'services', (select jsonb_agg(jsonb_build_object('code', code, 'name', name, 'description', description, 'level', resolution_level,
        'team', team, 'team_label', iara.team_label(team), 'iara_action', iara_action, 'escalation', escalation,
        'documents', required_documents, 'sla_days', sla_days) order by sort)
      from iara.service_catalog where audience = 'CIDADAO'),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'protocol', c.protocol_number, 'type', c.case_type, 'type_name', sc.name,
        'status', c.status, 'level', c.resolution_level, 'resolution', c.resolution_code, 'team_label', iara.team_label(c.assigned_team),
        'subject', c.subject, 'opened_at', c.opened_at) order by c.opened_at desc)
      from (select * from iara.service_cases x where x.guardian_id = p_guardian order by x.opened_at desc limit 8) c
      join iara.service_catalog sc on sc.code = c.case_type), '[]'::jsonb))
$$;

-- 4. Persona: família recém-chegada (sem cadastro) -------------------------------------------
insert into iara.organizational_roles (code, tenant_id, name, short_name, description, scope_type, stage_filter, question, org_unit, is_persona, sort)
values ('CIDADAO_NOVO', 1, 'Família recém-chegada a Maringá', 'Família nova',
        'Chegou de outra cidade: faz o cadastro pela IARA (WhatsApp) ou pelo portal e pede vaga por transferência.',
        'GUARDIAN', null, 'Acabamos de chegar a Maringá. Como garanto a vaga das crianças?', 'WhatsApp da IARA / Portal do Cidadão', true, 11)
on conflict (code) do update set name = excluded.name, short_name = excluded.short_name, description = excluded.description,
  question = excluded.question, org_unit = excluded.org_unit, is_persona = true, sort = excluded.sort;
insert into iara.role_permissions (role_code, permission_code)
select 'CIDADAO_NOVO', permission_code from iara.role_permissions where role_code = 'CIDADAO'
on conflict do nothing;

create or replace function iara.session_create(p_persona text, p_unit integer, p_token_hash text, p_user_agent text)
returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r iara.organizational_roles;
  v_user uuid := gen_random_uuid();
  v_unit integer;
  v_guardian uuid;
  v_label text;
  v_unit_name text;
  v_suffix text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4));
begin
  if not coalesce((iara.setting('demo_mode'))::boolean, false) then
    raise exception 'Seleção de perfil disponível apenas no modo demonstração.' using errcode = '42501';
  end if;
  select * into r from iara.organizational_roles where code = p_persona and is_persona;
  if not found then
    raise exception 'Perfil desconhecido: %', p_persona using errcode = '22023';
  end if;
  if r.scope_type = 'UNIT' then
    v_unit := coalesce(p_unit, (iara.setting('demo_unit_maria'))::int);
    select name into v_unit_name from iara.education_units where id = v_unit;
    if v_unit_name is null then
      raise exception 'Unidade inválida.' using errcode = '22023';
    end if;
  elsif r.scope_type = 'GUARDIAN' and r.code = 'CIDADAO' then  -- CIDADAO_NOVO começa sem cadastro (faz pela IARA ou portal)
    v_guardian := (iara.setting('demo_guardian_maria'))::uuid;
  end if;
  v_label := case r.code
    when 'PREFEITO' then 'Gabinete do Prefeito'
    when 'SECRETARIO' then 'Secretaria Municipal de Educação'
    when 'SUPERINTENDENCIA' then 'Superintendência da SEDUC'
    when 'ANALISTA_CENTRAL' then 'Analista · Central de Vagas'
    when 'GERENCIA_EI' then 'Gerência de Educação Infantil'
    when 'DIRETOR_UNIDADE' then 'Direção · ' || v_unit_name
    when 'SECRETARIA_ESCOLAR' then 'Secretaria escolar · ' || v_unit_name
    when 'ATENDIMENTO' then 'Atendimento ao Cidadão'
    when 'INOVACAO' then 'Diretoria de Inovação Educacional'
    when 'CIDADAO' then (select full_name from iara.guardians where id = v_guardian)
    else r.name end || ' (demo #' || v_suffix || ')';

  insert into iara.app_users (id, tenant_id, display_name, role_code, unit_id, guardian_id, auth_provider, is_demo, last_seen_at)
  values (v_user, 1, v_label, r.code, v_unit, v_guardian, 'DEMO', true, now());
  insert into iara.app_sessions (token_hash, user_id, expires_at, user_agent)
  values (p_token_hash, v_user, now() + interval '12 hours', left(p_user_agent, 300));

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  perform iara.audit_event('LOGIN_DEMO', 'app_user', v_user::text, v_unit, 'Sessão de demonstração iniciada: ' || r.name);
  return jsonb_build_object('user_id', v_user, 'role', r.code);
end $$;

-- 5. Protocolos com alçada e roteamento -------------------------------------------------------
create or replace function api.case_create(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_scope text := iara.my_scope();
  v_key text := nullif(p ->> 'idempotency_key', '');
  v_existing iara.service_cases;
  v_type text := coalesce(p ->> 'case_type', 'SOLICITACAO_VAGA');
  v_sc iara.service_catalog;
  v_student uuid := nullif(p ->> 'student_id', '')::uuid;
  v_guardian uuid := nullif(p ->> 'guardian_id', '')::uuid;
  v_id uuid := gen_random_uuid();
  v_protocol text;
  v_unit integer := (p ->> 'unit_id')::int;
  v_channel text := coalesce(nullif(p ->> 'channel', ''), case when v_scope = 'GUARDIAN' then 'WEB' else 'PRESENCIAL' end);
  v_route jsonb;
begin
  if v_key is not null then
    select * into v_existing from iara.service_cases where idempotency_key = v_key;
    if found then
      return jsonb_build_object('ok', true, 'idempotent', true, 'case_id', v_existing.id, 'protocol', v_existing.protocol_number, 'status', v_existing.status);
    end if;
  end if;
  select * into v_sc from iara.service_catalog where code = v_type;
  if not found then
    raise exception 'Tipo de atendimento inválido.' using errcode = '22023';
  end if;
  if v_scope = 'GUARDIAN' then
    perform iara.require_perm('cases.write_own');
    v_guardian := iara.my_guardian();
    if v_student is not null and not exists (select 1 from iara.student_guardians where student_id = v_student and guardian_id = v_guardian) then
      raise exception 'Você só pode abrir protocolos para crianças sob sua responsabilidade.' using errcode = '42501';
    end if;
  else
    perform iara.require_perm('cases.write');
    if v_student is not null and not iara.can_access_student(v_student) then
      raise exception 'Aluno fora do seu escopo.' using errcode = '42501';
    end if;
    if v_guardian is null and v_student is not null then
      select guardian_id into v_guardian from iara.student_guardians where student_id = v_student and is_primary limit 1;
    end if;
  end if;
  if v_unit is null and v_student is not null then
    select unit_id into v_unit from iara.enrollments where student_id = v_student and status = 'ACTIVE' limit 1;
  end if;
  -- alçada: secretaria da unidade da criança ou equipe da Secretaria (SEDUC), conforme o catálogo
  v_route := iara.route_case(v_type, v_student, v_unit);
  v_unit := (v_route ->> 'unit_id')::int;
  v_protocol := iara.next_protocol();
  insert into iara.service_cases (id, tenant_id, protocol_number, case_type, channel, status, priority, student_id, guardian_id, unit_id,
                                  assigned_team, subject, description, opened_at, sla_due_at, idempotency_key, created_by, is_demo,
                                  details, resolution_level)
  values (v_id, 1, v_protocol, v_type, v_channel, 'NOVO', coalesce(nullif(p ->> 'priority', ''), 'NORMAL'), v_student, v_guardian, v_unit,
          v_route ->> 'team',
          coalesce(nullif(p ->> 'subject', ''), v_sc.name), nullif(p ->> 'description', ''), now(),
          now() + make_interval(days => v_sc.sla_days), v_key, iara.current_user_id(), true,
          coalesce(p -> 'details', '{}'::jsonb), v_route ->> 'level');
  insert into iara.case_events (case_id, event_type, message, new_value, user_id, actor_label, visibility)
  values (v_id, 'CRIADO', 'Protocolo ' || v_protocol || ' aberto (' || lower(v_channel) || '). Encaminhado para ' || (v_route ->> 'team_label') || '.', 'NOVO', iara.current_user_id(), iara.my_label(), 'CIDADAO');
  if v_guardian is not null then
    insert into iara.notifications (tenant_id, guardian_id, student_id, case_id, channel, event_type, title, body)
    values (1, v_guardian, v_student, v_id, 'PORTAL', 'PROTOCOLO_CRIADO', 'Protocolo registrado',
            'Recebemos sua solicitação (' || v_sc.name || '). Protocolo ' || v_protocol || '. Quem analisa: ' || (v_route ->> 'team_label') || '. Prazo: até ' || v_sc.sla_days || ' dia(s).');
  end if;
  perform iara.audit_event('CASE_CREATED', 'service_cases', v_id::text, v_unit, 'Protocolo ' || v_protocol || ' · ' || v_sc.name);
  return jsonb_build_object('ok', true, 'case_id', v_id, 'protocol', v_protocol, 'status', 'NOVO',
                            'sla_due_at', now() + make_interval(days => v_sc.sla_days), 'sector', v_sc.sector,
                            'routed_to', v_route, 'iara_action', v_sc.iara_action, 'escalation', v_sc.escalation,
                            'next_steps', jsonb_build_array(
                              case when cardinality(v_sc.required_documents) > 0 then 'Enviar documentos: ' || array_to_string(v_sc.required_documents, ', ') end,
                              'Análise por: ' || (v_route ->> 'team_label') || ' (prazo de ' || v_sc.sla_days || ' dia(s))'));
end $$;

-- 6. Funções da família (IARA e portal) ----------------------------------------------------------
create or replace function api.family_overview(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v uuid := iara.family_guardian(p, true);
begin
  if v is null then
    return jsonb_build_object('registered', false,
      'services', (select jsonb_agg(jsonb_build_object('code', code, 'name', name, 'description', description, 'level', resolution_level,
          'team_label', iara.team_label(team), 'iara_action', iara_action, 'escalation', escalation) order by sort)
        from iara.service_catalog where audience = 'CIDADAO'));
  end if;
  return iara.family_json(v) || jsonb_build_object('registered', true);
end $$;

create or replace function api.family_register(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_me uuid := iara.current_user_id();
  v_g uuid := gen_random_uuid();
  v_addr uuid;
  v_name text := btrim(coalesce(p ->> 'full_name', ''));
  v_phone text := nullif(btrim(coalesce(p ->> 'phone', '')), '');
  v_channel text := coalesce(nullif(p ->> 'channel', ''), 'WEB');
  v_case jsonb;
begin
  if iara.my_scope() <> 'GUARDIAN' then
    raise exception 'O cadastro da família é feito pelo próprio responsável (WhatsApp da IARA ou portal).' using errcode = '42501';
  end if;
  perform iara.require_perm('cases.write_own');
  if iara.my_guardian() is not null then
    raise exception 'Sua família já tem cadastro. Para mudar dados, use "Atualizar dados" ou "Mudança de endereço".' using errcode = '22023';
  end if;
  if length(v_name) < 5 or array_length(regexp_split_to_array(v_name, '\s+'), 1) < 2 then
    raise exception 'Informe o nome completo do responsável (nome e sobrenome).' using errcode = '22023';
  end if;
  v_addr := iara.new_address(p -> 'address', case when v_channel = 'WHATSAPP' then 'Informado à IARA (WhatsApp)' else 'Informado no portal' end);
  if v_phone is null then
    -- demonstração: o número real viria do próprio WhatsApp; aqui é fictício
    v_phone := '(44) 90000-' || lpad((floor(random() * 10000))::int::text, 4, '0');
  end if;
  insert into iara.guardians (id, tenant_id, full_name, cpf, gender, email, primary_phone, whatsapp_phone, preferred_contact_channel, address_id,
                              cadunico_status, single_mother, consent_flags, created_by, is_demo)
  values (v_g, 1, v_name, nullif(p ->> 'cpf', ''), nullif(p ->> 'gender', ''), nullif(p ->> 'email', ''), v_phone, v_phone, 'WHATSAPP', v_addr,
          coalesce((p ->> 'cadunico')::boolean, false), coalesce((p ->> 'single_mother')::boolean, false),
          jsonb_build_object('lgpd_ciencia', true, 'registrado_em', now(), 'canal', v_channel), v_me, true);
  update iara.app_users set guardian_id = v_g,
         display_name = v_name || coalesce(substring(display_name from ' \(demo #[0-9A-F]+\)$'), '')
  where id = v_me;
  update iara.conversations set guardian_id = v_g, contact_label = v_name, contact_phone_masked = iara.mask_phone(v_phone)
  where owner_user_id = v_me and guardian_id is null;
  v_case := iara.iara_case('ATUALIZACAO_CADASTRAL', v_g, null, null, 'Cadastro da família',
    format('Cadastro da família feito %s: responsável %s, endereço em %s.',
           case when v_channel = 'WHATSAPP' then 'pela IARA no WhatsApp' else 'no portal' end, split_part(v_name, ' ', 1),
           coalesce(nullif(p -> 'address' ->> 'neighborhood', ''), 'Maringá')),
    jsonb_build_object('evento', 'CADASTRO_FAMILIA', 'bairro', p -> 'address' ->> 'neighborhood',
                       'cadunico', coalesce((p ->> 'cadunico')::boolean, false), 'mae_solo', coalesce((p ->> 'single_mother')::boolean, false),
                       'origem', p -> 'origin'), v_channel);
  perform iara.audit_event('FAMILY_REGISTERED', 'guardians', v_g::text, null,
                           'Cadastro de família pelo próprio responsável (' || lower(v_channel) || ')');
  return iara.family_json(v_g) || jsonb_build_object('ok', true, 'registered', true, 'guardian_id', v_g, 'protocol', v_case ->> 'protocol');
end $$;

create or replace function api.family_add_child(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_g uuid := iara.family_guardian(p);
  v_id uuid := gen_random_uuid();
  v_name text := btrim(coalesce(p ->> 'full_name', ''));
  v_birth date := nullif(p ->> 'birth_date', '')::date;
  v_rel text := upper(coalesce(nullif(p ->> 'relationship', ''), 'RESPONSAVEL_LEGAL'));
  v_aee boolean := coalesce((p ->> 'aee')::boolean, false);
  v_channel text := coalesce(nullif(p ->> 'channel', ''), case when iara.my_scope() = 'GUARDIAN' then 'WEB' else 'PRESENCIAL' end);
  v_existing uuid;
  v_addr uuid;
  v_case jsonb;
begin
  if length(v_name) < 5 or array_length(regexp_split_to_array(v_name, '\s+'), 1) < 2 then
    raise exception 'Informe o nome completo da criança (nome e sobrenome).' using errcode = '22023';
  end if;
  if v_birth is null or v_birth > current_date or v_birth < current_date - interval '18 years' then
    raise exception 'Data de nascimento inválida.' using errcode = '22023';
  end if;
  select s.id into v_existing from iara.students s join iara.student_guardians sg on sg.student_id = s.id
  where sg.guardian_id = v_g and iara.norm(s.full_name) = iara.norm(v_name) and s.birth_date = v_birth limit 1;
  if v_existing is not null then
    return jsonb_build_object('ok', true, 'existing', true, 'student_id', v_existing, 'name', v_name, 'first_name', split_part(v_name, ' ', 1),
                              'grade_rule', iara.grade_for_birthdate(v_birth));
  end if;
  if exists (select 1 from iara.students s where iara.norm(s.full_name) = iara.norm(v_name) and s.birth_date = v_birth) then
    -- já existe em outro cadastro: não duplica nem expõe dados de outra família; a Central confere
    v_case := api.case_create(jsonb_build_object('case_type', 'INCLUSAO_MEMBRO', 'channel', v_channel, 'guardian_id', v_g,
      'subject', 'Conferir cadastro de criança (possível duplicidade)',
      'description', format('Inclusão de %s (nascimento em %s) encontrou cadastro com mesmo nome e data. Conferir vínculo antes de incluir.',
                            split_part(v_name, ' ', 1), to_char(v_birth, 'DD/MM/YYYY')),
      'details', jsonb_build_object('evento', 'NOVO_DEPENDENTE', 'possivel_duplicidade', true)));
    return jsonb_build_object('ok', false, 'duplicate', true, 'protocol', v_case ->> 'protocol', 'routed_to', v_case -> 'routed_to',
      'message', format('Já existe uma criança com esse nome e data de nascimento em outro cadastro. Para proteger os dados das famílias, a %s vai conferir e falar com você (protocolo %s).',
                        (v_case -> 'routed_to' ->> 'team_label'), v_case ->> 'protocol'));
  end if;
  select address_id into v_addr from iara.guardians where id = v_g;
  insert into iara.students (id, tenant_id, full_name, birth_date, gender, status, address_id, aee_status, created_by, is_demo)
  values (v_id, 1, v_name, v_birth, nullif(upper(p ->> 'gender'), ''), 'SEM_VINCULO', v_addr, v_aee, iara.current_user_id(), true);
  insert into iara.student_guardians (student_id, guardian_id, relationship, is_primary, legal_authority_status)
  values (v_id, v_g, v_rel, true, 'DECLARADO');
  insert into iara.documents (tenant_id, student_id, doc_type, status, is_sensitive, is_demo)
  values (1, v_id, 'CERTIDAO', 'PENDENTE', false, true);
  if v_aee then
    insert into iara.documents (tenant_id, student_id, doc_type, status, notes, is_sensitive, is_demo)
    values (1, v_id, 'LAUDO', 'PENDENTE', 'Laudo médico com CID — necessário para a prioridade sob análise (IN nº 025/2025)', true, true);
  end if;
  v_case := iara.iara_case('INCLUSAO_MEMBRO', v_g, v_id, null, 'Novo membro da família: ' || split_part(v_name, ' ', 1),
    format('%s incluído(a) na família (%s). Faixa pela data de nascimento: %s.', split_part(v_name, ' ', 1), lower(v_rel),
           coalesce(iara.grade_for_birthdate(v_birth) ->> 'grade_name', 'a definir')),
    jsonb_build_object('evento', 'NOVO_DEPENDENTE', 'nome', v_name, 'nascimento', v_birth, 'parentesco', v_rel, 'aee', v_aee, 'origem', p -> 'origin'),
    v_channel);
  perform iara.audit_event('FAMILY_MEMBER_ADDED', 'students', v_id::text, null, 'Novo membro da família (criança) incluído pelo responsável');
  return jsonb_build_object('ok', true, 'student_id', v_id, 'name', v_name, 'first_name', split_part(v_name, ' ', 1),
                            'grade_rule', iara.grade_for_birthdate(v_birth), 'protocol', v_case ->> 'protocol');
end $$;

create or replace function api.family_add_adult(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_g uuid := iara.family_guardian(p);
  v_new uuid := gen_random_uuid();
  v_name text := btrim(coalesce(p ->> 'full_name', ''));
  v_rel text := upper(coalesce(nullif(p ->> 'relationship', ''), 'OUTRO'));
  v_together boolean := coalesce((p ->> 'lives_together')::boolean, true);
  v_channel text := coalesce(nullif(p ->> 'channel', ''), case when iara.my_scope() = 'GUARDIAN' then 'WEB' else 'PRESENCIAL' end);
  v_students uuid[];
  v_parent boolean;
  v_main iara.guardians;
  v_case jsonb;
  v_escalated boolean := false;
  v_phone text := nullif(btrim(coalesce(p ->> 'phone', '')), '');
begin
  if length(v_name) < 5 or array_length(regexp_split_to_array(v_name, '\s+'), 1) < 2 then
    raise exception 'Informe o nome completo (nome e sobrenome).' using errcode = '22023';
  end if;
  select * into v_main from iara.guardians where id = v_g;
  select coalesce(array_agg(sg.student_id), '{}') into v_students from iara.student_guardians sg
  where sg.guardian_id = v_g
    and (p -> 'student_ids' is null or jsonb_typeof(p -> 'student_ids') <> 'array' or jsonb_array_length(p -> 'student_ids') = 0
         or sg.student_id::text in (select jsonb_array_elements_text(p -> 'student_ids')));
  v_parent := v_rel in ('MAE', 'PAI');
  insert into iara.guardians (id, tenant_id, full_name, cpf, gender, primary_phone, whatsapp_phone, address_id, consent_flags, created_by, is_demo)
  values (v_new, 1, v_name, nullif(p ->> 'cpf', ''), case when v_rel in ('MAE', 'MADRASTA') then 'F' when v_rel in ('PAI', 'PADRASTO') then 'M' else nullif(upper(p ->> 'gender'), '') end,
          v_phone, v_phone, case when v_together then v_main.address_id end,
          jsonb_build_object('lgpd_ciencia', true, 'registrado_em', now(), 'incluido_por', v_g), iara.current_user_id(), true);
  insert into iara.student_guardians (student_id, guardian_id, relationship, is_primary, legal_authority_status)
  select unnest(v_students), v_new, v_rel, false, case when v_parent then 'DECLARADO' else 'PENDENTE' end;
  if v_parent or cardinality(v_students) = 0 then
    v_case := iara.iara_case('INCLUSAO_MEMBRO', v_g, null, null, 'Novo membro da família: ' || split_part(v_name, ' ', 1),
      format('%s incluído(a) como %s.', split_part(v_name, ' ', 1), lower(v_rel)),
      jsonb_build_object('evento', 'NOVO_RESPONSAVEL', 'nome', v_name, 'parentesco', v_rel, 'mora_junto', v_together), v_channel);
  else
    -- quem não é pai/mãe só passa a responder pela criança depois de a unidade conferir a guarda
    v_escalated := true;
    v_case := api.case_create(jsonb_build_object('case_type', 'ALTERACAO_RESPONSAVEL', 'channel', v_channel, 'guardian_id', v_g,
      'student_id', v_students[1],
      'subject', format('Validar responsável: %s (%s)', split_part(v_name, ' ', 1), lower(v_rel)),
      'description', format('%s foi incluído(a) como %s. Conferir termo de guarda ou documento de representação antes de liberar decisões sobre a criança.',
                            v_name, lower(v_rel)),
      'details', jsonb_build_object('evento', 'NOVO_RESPONSAVEL', 'parentesco', v_rel, 'criancas', cardinality(v_students), 'mora_junto', v_together)));
  end if;
  perform iara.audit_event('FAMILY_MEMBER_ADDED', 'guardians', v_new::text, null,
                           format('Novo responsável (%s) incluído%s', lower(v_rel), case when v_escalated then ' — validação de guarda pela unidade' else '' end));
  return jsonb_build_object('ok', true, 'guardian_id', v_new, 'escalated', v_escalated, 'protocol', v_case ->> 'protocol',
    'routed_to', v_case -> 'routed_to',
    'review_single_mother', coalesce(v_main.single_mother, false) and v_together and v_rel in ('PAI', 'PADRASTO', 'COMPANHEIRO'),
    'message', case when v_escalated
      then format('Incluí %s. Como não é pai nem mãe, a %s confere o documento de guarda (protocolo %s).',
                  split_part(v_name, ' ', 1), v_case -> 'routed_to' ->> 'team_label', v_case ->> 'protocol')
      else format('Incluí %s na família (protocolo %s).', split_part(v_name, ' ', 1), v_case ->> 'protocol') end);
end $$;

create or replace function api.family_update(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_g uuid := iara.family_guardian(p);
  v_old iara.guardians;
  v_students uuid[];
  v_before jsonb;
  v_after jsonb;
  v_changes jsonb := '{}'::jsonb;
  v_requeue boolean := false;
  v_case jsonb;
  v_channel text := coalesce(nullif(p ->> 'channel', ''), case when iara.my_scope() = 'GUARDIAN' then 'WEB' else 'PRESENCIAL' end);
begin
  select * into v_old from iara.guardians where id = v_g;
  v_students := (select coalesce(array_agg(student_id), '{}') from iara.student_guardians where guardian_id = v_g);
  v_before := iara.queue_snapshot(v_students);
  if nullif(btrim(coalesce(p ->> 'phone', '')), '') is not null then
    update iara.guardians set primary_phone = btrim(p ->> 'phone'), whatsapp_phone = coalesce(nullif(btrim(p ->> 'whatsapp'), ''), btrim(p ->> 'phone')) where id = v_g;
    v_changes := v_changes || jsonb_build_object('telefone', iara.mask_phone(btrim(p ->> 'phone')));
  end if;
  if nullif(btrim(coalesce(p ->> 'email', '')), '') is not null then
    update iara.guardians set email = btrim(p ->> 'email') where id = v_g;
    v_changes := v_changes || jsonb_build_object('email', btrim(p ->> 'email'));
  end if;
  if p ? 'cadunico' and (p ->> 'cadunico')::boolean is distinct from v_old.cadunico_status then
    update iara.guardians set cadunico_status = (p ->> 'cadunico')::boolean where id = v_g;
    v_changes := v_changes || jsonb_build_object('cadunico', (p ->> 'cadunico')::boolean);
    v_requeue := true;
  end if;
  if p ? 'single_mother' and (p ->> 'single_mother')::boolean is distinct from v_old.single_mother then
    update iara.guardians set single_mother = (p ->> 'single_mother')::boolean where id = v_g;
    v_changes := v_changes || jsonb_build_object('mae_solo', (p ->> 'single_mother')::boolean);
    v_requeue := true;
  end if;
  if v_changes = '{}'::jsonb then
    return jsonb_build_object('ok', true, 'changes', v_changes, 'impacts', '[]'::jsonb, 'message', 'Nada mudou: os dados informados já estavam no cadastro.');
  end if;
  if v_requeue then
    perform iara.requeue_students(v_students);
  end if;
  v_after := iara.queue_snapshot(v_students);
  v_case := iara.iara_case('ATUALIZACAO_CADASTRAL', v_g, null, null, 'Atualização de dados da família',
    'Dados atualizados: ' || (select string_agg(k, ', ') from jsonb_object_keys(v_changes) k) ||
    case when v_requeue then '. Fila recalculada com os novos critérios; comprovantes são conferidos na matrícula.' else '.' end,
    jsonb_build_object('evento', 'ATUALIZACAO_DADOS', 'alteracoes', v_changes, 'impactos', iara.queue_impacts(v_before, v_after)), v_channel);
  perform iara.audit_event('FAMILY_UPDATED', 'guardians', v_g::text, null, 'Atualização de dados pelo responsável: ' ||
                           (select string_agg(k, ', ') from jsonb_object_keys(v_changes) k));
  return jsonb_build_object('ok', true, 'changes', v_changes, 'requeued', v_requeue, 'impacts', iara.queue_impacts(v_before, v_after),
                            'protocol', v_case ->> 'protocol',
                            'documents_note', case when v_requeue then 'CadÚnico e mãe solo são conferidos na matrícula (comprovante e declaração).' end);
end $$;

create or replace function api.family_move(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, extensions, public
as $$
declare
  v_g uuid := iara.family_guardian(p);
  v_old_addr uuid;
  v_old_json jsonb;
  v_new uuid;
  v_point extensions.geography;
  v_students uuid[];
  v_before jsonb;
  v_after jsonb;
  v_enrolled jsonb;
  v_waiting_near jsonb;
  v_case jsonb;
  v_channel text := coalesce(nullif(p ->> 'channel', ''), case when iara.my_scope() = 'GUARDIAN' then 'WEB' else 'PRESENCIAL' end);
begin
  select address_id into v_old_addr from iara.guardians where id = v_g;
  v_old_json := iara.address_json(v_old_addr);
  v_new := iara.new_address(p -> 'address', case when v_channel = 'WHATSAPP' then 'Informado à IARA (WhatsApp)' else 'Informado no portal' end);
  select location into v_point from iara.addresses where id = v_new;
  -- quem muda junto: crianças da família no mesmo endereço (ou as indicadas)
  select coalesce(array_agg(s.id), '{}') into v_students
  from iara.students s join iara.student_guardians sg on sg.student_id = s.id and sg.guardian_id = v_g
  where case when jsonb_typeof(p -> 'student_ids') = 'array' and jsonb_array_length(p -> 'student_ids') > 0
             then s.id::text in (select jsonb_array_elements_text(p -> 'student_ids'))
             else s.address_id is not distinct from v_old_addr or s.address_id is null end;
  v_before := iara.queue_snapshot(v_students);
  update iara.guardians set address_id = v_new
  where id = v_g or (address_id = v_old_addr and id in (select sg.guardian_id from iara.student_guardians sg where sg.student_id = any (v_students)));
  update iara.students set address_id = v_new where id = any (v_students);
  perform iara.requeue_students(v_students);
  v_after := iara.queue_snapshot(v_students);
  -- crianças matriculadas: distância da escola atual e unidades com vaga perto da nova casa
  select coalesce(jsonb_agg(jsonb_build_object('student_id', s.id, 'child', split_part(s.full_name, ' ', 1), 'unit_id', u.id, 'unit', u.name,
      'grade', gl.name, 'grade_level_id', gl.id, 'distance_m', round(st_distance(u.location, v_point))::int,
      'nearby', (select coalesce(jsonb_agg(zz.z order by (zz.z ->> 'distance_m')::int), '[]'::jsonb) from (
          select jsonb_build_object('unit_id', u2.id, 'unit', u2.name, 'distance_m', round(st_distance(u2.location, v_point))::int,
                                    'offerable', x.n) as z
          from (select c2.unit_id, sum(c2.offerable_vacancies_count)::int as n from iara.classes c2
                where c2.grade_level_id = gl.id and c2.status = 'ATIVA'
                group by c2.unit_id having sum(c2.offerable_vacancies_count) > 0) x
          join iara.education_units u2 on u2.id = x.unit_id
          where u2.id <> u.id and u2.status = 'ATIVA'
          order by st_distance(u2.location, v_point) limit 3) zz))), '[]'::jsonb)
  into v_enrolled
  from iara.students s
  join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
  join iara.education_units u on u.id = e.unit_id
  join iara.classes c on c.id = e.class_id
  join iara.grade_levels gl on gl.id = c.grade_level_id
  where s.id = any (v_students);
  v_case := iara.iara_case('MUDANCA_ENDERECO', v_g, null, null, 'Mudança de endereço',
    format('Endereço atualizado: %s → %s. Fila recalculada (residência até 2 km); o comprovante é conferido na matrícula.',
           coalesce(v_old_json ->> 'neighborhood', 'endereço anterior'), coalesce(nullif(p -> 'address' ->> 'neighborhood', ''), 'novo endereço')),
    jsonb_build_object('evento', 'MUDANCA_ENDERECO', 'de', v_old_json ->> 'neighborhood', 'para', p -> 'address' ->> 'neighborhood',
                       'criancas', cardinality(v_students), 'impactos', iara.queue_impacts(v_before, v_after)), v_channel);
  insert into iara.notifications (tenant_id, guardian_id, case_id, channel, event_type, title, body)
  values (1, v_g, (v_case ->> 'case_id')::uuid, 'PORTAL', 'ENDERECO', 'Endereço atualizado',
          'Seu endereço foi atualizado e a fila das crianças foi recalculada. Leve o comprovante de endereço na matrícula.');
  perform iara.audit_event('ADDRESS_CHANGED', 'guardians', v_g::text, null,
                           format('Mudança de endereço (%s → %s) com recálculo da fila de %s criança(s)',
                                  coalesce(v_old_json ->> 'neighborhood', '?'), coalesce(p -> 'address' ->> 'neighborhood', '?'), cardinality(v_students)));
  return jsonb_build_object('ok', true, 'address', iara.address_json(v_new), 'previous', v_old_json, 'students_moved', cardinality(v_students),
                            'impacts', iara.queue_impacts(v_before, v_after), 'enrolled', v_enrolled, 'protocol', v_case ->> 'protocol');
end $$;

-- Inscrição na fila de espera on-line (a própria família, como no Conecta Seduc) — também transferências
create or replace function api.queue_self_register(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_unit integer := (p ->> 'unit_id')::int;
  v_channel text := coalesce(nullif(p ->> 'channel', ''), case when iara.my_scope() = 'GUARDIAN' then 'WEB' else 'PRESENCIAL' end);
  v_origin jsonb := case when jsonb_typeof(p -> 'origin') = 'object' and (p -> 'origin') <> '{}'::jsonb then p -> 'origin' end;
  s iara.students;
  v_rule jsonb;
  v_grade smallint;
  v_enroll iara.enrollments;
  v_alts integer[] := '{}';
  v_entry uuid := gen_random_uuid();
  v_type text;
  v_guardian uuid;
  v_case jsonb;
  w iara.waiting_list_entries;
  v_size integer;
  v_offerable integer;
  v_unit_name text;
  v_grade_name text;
  v_existing record;
begin
  if iara.my_scope() = 'GUARDIAN' then
    perform iara.require_perm('cases.write_own');
    if not exists (select 1 from iara.student_guardians where student_id = v_student and guardian_id = iara.my_guardian()) then
      raise exception 'Você só pode inscrever crianças sob sua responsabilidade.' using errcode = '42501';
    end if;
  else
    perform iara.require_perm('queue.manage');
    if not iara.can_access_student(v_student) then
      raise exception 'Aluno fora do seu escopo.' using errcode = '42501';
    end if;
  end if;
  select * into s from iara.students where id = v_student;
  if not found then
    raise exception 'Criança não encontrada.' using errcode = 'P0002';
  end if;
  select * into v_enroll from iara.enrollments where student_id = v_student and status = 'ACTIVE' limit 1;
  v_rule := iara.grade_for_birthdate(s.birth_date);
  if v_enroll.id is not null then
    select c.grade_level_id into v_grade from iara.classes c where c.id = v_enroll.class_id;  -- transferência: mesma série da turma atual
  elsif nullif(p ->> 'grade_level_id', '') is not null and v_origin is not null then
    v_grade := (p ->> 'grade_level_id')::smallint;  -- transferência: série pelo histórico escolar
  elsif coalesce((v_rule ->> 'ok')::boolean, false) then
    v_grade := (v_rule ->> 'grade_level_id')::smallint;
  else
    raise exception '%', coalesce(v_rule ->> 'explanation', 'Não foi possível definir a faixa pela data de nascimento.') using errcode = '22023';
  end if;
  select name into v_unit_name from iara.education_units where id = v_unit and status = 'ATIVA';
  if v_unit_name is null or not exists (select 1 from iara.classes c where c.unit_id = v_unit and c.grade_level_id = v_grade and c.status = 'ATIVA') then
    raise exception 'Esta unidade não atende esta faixa/série. Escolha outra unidade próxima.' using errcode = '22023';
  end if;
  select name into v_grade_name from iara.grade_levels where id = v_grade;
  select w2.id, w2.position, u.name as unit into v_existing from iara.waiting_list_entries w2 join iara.education_units u on u.id = w2.preferred_unit_id
  where w2.student_id = v_student and w2.grade_level_id = v_grade and w2.status in ('WAITING', 'OFFERED', 'ACCEPTED') limit 1;
  if found then
    raise exception '% já está na fila de % %, na posição %. Para trocar de unidade, desista da inscrição atual primeiro.',
      split_part(s.full_name, ' ', 1), v_grade_name, iara.da_unidade(v_existing.unit), coalesce(v_existing.position::text, '—') using errcode = '23505';
  end if;
  if v_enroll.id is not null and v_enroll.unit_id = v_unit then
    raise exception '% já estuda nesta unidade.', split_part(s.full_name, ' ', 1) using errcode = '22023';
  end if;
  if jsonb_typeof(p -> 'alternative_unit_ids') = 'array' then
    select coalesce(array_agg(distinct x::int), '{}') into v_alts
    from (select jsonb_array_elements_text(p -> 'alternative_unit_ids') x limit 2) a
    where x::int <> v_unit and exists (select 1 from iara.classes c where c.unit_id = x::int and c.grade_level_id = v_grade and c.status = 'ATIVA');
  end if;
  v_type := case when v_enroll.id is not null then 'TRANSFERENCIA' when v_origin is not null then 'TRANSFERENCIA_EXTERNA' else 'SOLICITACAO_VAGA' end;
  select guardian_id into v_guardian from iara.student_guardians where student_id = v_student order by is_primary desc limit 1;

  insert into iara.waiting_list_entries (id, tenant_id, student_id, stage_id, grade_level_id, preferred_unit_id, alternative_unit_ids, territory_id,
                                         preferred_shift, full_time_requested, demand_category, priority_flags, entered_at, status, created_by, is_demo)
  select v_entry, 1, v_student, gl.stage_id, v_grade, v_unit, v_alts, u.macro_territory_id,
         nullif(p ->> 'shift', ''), coalesce((p ->> 'full_time')::boolean, false),
         case when v_enroll.id is not null then 'AGUARDA_TRANSFERENCIA' else 'SEM_ATENDIMENTO' end, '{}', now(), 'WAITING', iara.current_user_id(), true
  from iara.grade_levels gl, iara.education_units u where gl.id = v_grade and u.id = v_unit;
  perform iara.compute_queue_priority(v_entry);
  perform iara.recalculate_queue(v_unit, v_grade);
  select * into w from iara.waiting_list_entries where id = v_entry;
  select count(*) into v_size from iara.waiting_list_entries where preferred_unit_id = v_unit and grade_level_id = v_grade and status = 'WAITING';
  select coalesce(sum(offerable_vacancies_count), 0) into v_offerable from iara.classes where unit_id = v_unit and grade_level_id = v_grade and status = 'ATIVA';
  if s.status = 'SEM_VINCULO' then
    update iara.students set status = 'AGUARDANDO_VAGA' where id = v_student;
  end if;

  v_case := iara.iara_case(v_type, v_guardian, v_student, v_unit,
    format('%s — %s (%s)', case v_type when 'TRANSFERENCIA' then 'Transferência' when 'TRANSFERENCIA_EXTERNA' then 'Vaga por transferência de outro município' else 'Inscrição na fila' end,
           v_grade_name, split_part(s.full_name, ' ', 1)),
    format('%s inscrito(a) na fila de espera on-line de %s %s: posição %s de %s, %s de 100 pontos (regras %s).',
           split_part(s.full_name, ' ', 1), v_grade_name, iara.da_unidade(v_unit_name), w.position, v_size, w.priority_score, w.rule_version),
    jsonb_build_object('evento', 'INSCRICAO_FILA', 'unidade', v_unit_name, 'faixa', v_grade_name, 'posicao', w.position, 'pontos', w.priority_score,
                       'alternativas', to_jsonb(v_alts), 'turno', p ->> 'shift', 'origem', v_origin), v_channel);
  update iara.waiting_list_entries set case_id = (v_case ->> 'case_id')::uuid where id = v_entry;
  insert into iara.notifications (tenant_id, guardian_id, student_id, case_id, channel, event_type, title, body)
  select 1, sg.guardian_id, v_student, (v_case ->> 'case_id')::uuid, 'PORTAL', 'FILA', 'Inscrição na fila',
         format('%s está na fila de %s %s: posição %s de %s (%s pontos). Quando a vaga for ofertada, você terá 72 h para efetivar a matrícula.',
                split_part(s.full_name, ' ', 1), v_grade_name, iara.da_unidade(v_unit_name), w.position, v_size, w.priority_score)
  from iara.student_guardians sg where sg.student_id = v_student and sg.is_primary;
  perform iara.audit_event('QUEUE_SELF_REGISTER', 'waiting_list_entries', v_entry::text, v_unit,
                           format('Inscrição na fila on-line (%s) pelo %s: posição %s, %s pontos', lower(v_type),
                                  case when iara.my_scope() = 'GUARDIAN' then 'responsável' else 'servidor' end, w.position, w.priority_score));
  return jsonb_build_object('ok', true, 'entry_id', v_entry, 'protocol', v_case ->> 'protocol', 'case_type', v_type,
    'student_id', v_student, 'child', split_part(s.full_name, ' ', 1), 'unit_id', v_unit, 'unit', v_unit_name, 'grade', v_grade_name,
    'position', w.position, 'queue_size', v_size, 'score', w.priority_score, 'breakdown', w.score_breakdown, 'rule_version', w.rule_version,
    'offerable_now', v_offerable, 'first_in_line', w.position = 1,
    'documents', (select required_documents from iara.service_catalog where code = v_type),
    'message', case when w.position = 1 and v_offerable > 0
      then 'Há vaga ofertável e a criança é a 1ª da fila: a Central de Vagas faz a oferta e o aviso chega pelo WhatsApp, com 72 h para efetivar a matrícula.'
      else format('Inscrição feita: posição %s de %s. A posição muda com novas inscrições e ofertas; você é avisado(a) a cada mudança.', w.position, v_size) end);
end $$;

create or replace function api.queue_withdraw(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  w iara.waiting_list_entries;
  v_reason text := coalesce(nullif(btrim(p ->> 'reason'), ''), 'Desistência informada pela família');
  v_channel text := coalesce(nullif(p ->> 'channel', ''), case when iara.my_scope() = 'GUARDIAN' then 'WEB' else 'PRESENCIAL' end);
  v_child text;
  v_unit_name text;
  v_guardian uuid;
  v_case jsonb;
begin
  select * into w from iara.waiting_list_entries where id = (p ->> 'entry_id')::uuid for update;
  if not found then
    raise exception 'Inscrição não encontrada.' using errcode = 'P0002';
  end if;
  if iara.my_scope() = 'GUARDIAN' then
    perform iara.require_perm('cases.write_own');
    if not exists (select 1 from iara.student_guardians where student_id = w.student_id and guardian_id = iara.my_guardian()) then
      raise exception 'Inscrição de criança fora da sua responsabilidade.' using errcode = '42501';
    end if;
  else
    perform iara.require_perm('queue.manage');
  end if;
  if w.status = 'OFFERED' then
    raise exception 'Há uma oferta de vaga aguardando resposta para esta inscrição: recuse a oferta para liberar a vaga.' using errcode = '22023';
  elsif w.status <> 'WAITING' then
    raise exception 'Esta inscrição não está aguardando (situação atual: %).', w.status using errcode = '22023';
  end if;
  update iara.waiting_list_entries set status = 'CANCELLED', position = null where id = w.id;
  perform iara.recalculate_queue(w.preferred_unit_id, w.grade_level_id);
  update iara.students set status = 'SEM_VINCULO'
  where id = w.student_id and status = 'AGUARDANDO_VAGA'
    and not exists (select 1 from iara.waiting_list_entries x where x.student_id = w.student_id and x.status in ('WAITING', 'OFFERED', 'ACCEPTED'));
  select split_part(full_name, ' ', 1) into v_child from iara.students where id = w.student_id;
  select name into v_unit_name from iara.education_units where id = w.preferred_unit_id;
  select guardian_id into v_guardian from iara.student_guardians where student_id = w.student_id order by is_primary desc limit 1;
  v_case := iara.iara_case('DESISTENCIA', v_guardian, w.student_id, w.preferred_unit_id, 'Desistência da fila: ' || v_child,
    format('%s saiu da fila %s a pedido da família. Motivo: %s.', v_child, iara.da_unidade(v_unit_name), v_reason),
    jsonb_build_object('evento', 'DESISTENCIA_FILA', 'unidade', v_unit_name, 'posicao_anterior', w.position, 'motivo', v_reason), v_channel);
  perform iara.audit_event('QUEUE_WITHDRAWN', 'waiting_list_entries', w.id::text, w.preferred_unit_id,
                           format('Desistência da fila (posição %s): %s', w.position, v_reason));
  return jsonb_build_object('ok', true, 'protocol', v_case ->> 'protocol',
                            'message', format('%s saiu da fila %s. Se mudar de ideia, é só fazer uma nova inscrição.', v_child, iara.da_unidade(v_unit_name)));
end $$;

-- Resolutividade da IARA: quanto foi resolvido na hora × encaminhado à unidade × à Secretaria
create or replace function api.iara_resolution_stats(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_days integer := least(greatest(coalesce((p ->> 'days')::int, 30), 1), 365);
begin
  if not (iara.has_perm('conversations.read') or iara.has_perm('kpi.network')) then
    raise exception 'Sem permissão para indicadores de atendimento.' using errcode = '42501';
  end if;
  return (
    select jsonb_build_object('days', v_days,
      'total', count(*),
      'resolved_by_iara', count(*) filter (where c.resolution_code = 'RESOLVIDO_IARA'),
      'routed_unit', count(*) filter (where c.resolution_level = 'UNIDADE' and c.resolution_code is distinct from 'RESOLVIDO_IARA'),
      'routed_secretaria', count(*) filter (where c.resolution_level = 'SECRETARIA' and c.resolution_code is distinct from 'RESOLVIDO_IARA'),
      'by_type', (select coalesce(jsonb_agg(jsonb_build_object('type', z.name, 'level', z.lvl, 'total', z.n, 'resolved_by_iara', z.r) order by z.n desc), '[]'::jsonb)
                  from (select sc.name, sc.resolution_level lvl, count(*) n, count(*) filter (where c2.resolution_code = 'RESOLVIDO_IARA') r
                        from iara.service_cases c2 join iara.service_catalog sc on sc.code = c2.case_type
                        where c2.opened_at > now() - make_interval(days => v_days) and c2.channel in ('WHATSAPP', 'WEB')
                        group by sc.name, sc.resolution_level) z))
    from iara.service_cases c
    where c.opened_at > now() - make_interval(days => v_days) and c.channel in ('WHATSAPP', 'WEB'));
end $$;

-- 7. Base de conhecimento da IARA ------------------------------------------------------------
update iara.knowledge_articles set
  body = 'A oferta informa unidade, turma e turno. Pela IN nº 025/2025-SEDUC (Anexo II), depois de comunicada a contemplação você tem 72 horas para comparecer à unidade e efetivar a matrícula com todos os documentos obrigatórios. Aceitar a oferta pela IARA garante a reserva enquanto a unidade confere os documentos. Sem resposta no prazo, a vaga volta a ser ofertada seguindo a fila.',
  source = 'IN nº 025/2025-SEDUC, Anexo II (texto da equipe IARA — revisão SEDUC pendente)', version = '2.0'
where title = 'Recebi uma oferta de vaga. E agora?';

insert into iara.knowledge_articles (tenant_id, service_code, title, body, keywords, audience, source, owner_sector, version, approved_at, valid_from, review_due, status)
select 1, v.code, v.title, v.body, v.kw::text[], 'PUBLICO', 'Fluxos IARA Educa — demonstração (validar com a SEDUC)', v.sector, '1.0',
       current_date, date '2026-01-01', date '2026-12-31', 'PUBLICADO'
from (values
  ('MUDANCA_ENDERECO', 'Mudei de endereço. O que acontece?',
   'Pela IARA ou pelo portal você atualiza o endereço na hora. A fila é recalculada automaticamente (critério de residência até 2 km da unidade) e mostramos as unidades com vaga perto da nova casa. O comprovante de endereço é conferido na matrícula. Se a criança já estuda na rede e quer mudar de unidade, a IARA faz a inscrição na fila de transferência; a matrícula atual continua valendo até a nova vaga.',
   '{mudanca,mudei,endereco,mudar,casa,bairro,comprovante}', 'Central de Vagas'),
  ('TRANSFERENCIA_EXTERNA', 'Chegamos de outra cidade. Como pedir vaga?',
   'Bem-vindos a Maringá! A IARA faz o cadastro da família pelo WhatsApp (ou pelo portal), inclui as crianças e já inscreve na fila de espera on-line da unidade escolhida. Quando a vaga for ofertada, leve à unidade: declaração de transferência ou histórico da escola anterior, certidão de nascimento, CPF, comprovante de endereço em Maringá e carteira de vacinação. A Central de Vagas faz a oferta seguindo a fila.',
   '{outra,cidade,municipio,chegamos,mudamos,transferencia,fora,cadastro,nova,familia}', 'Central de Vagas'),
  ('INCLUSAO_MEMBRO', 'Nasceu ou chegou uma criança na família',
   'Inclua pelo WhatsApp da IARA ou pelo portal com nome completo e data de nascimento: a faixa (creche, pré-escola ou ano) é calculada pela data de corte e a criança já pode entrar na fila. Outro responsável (pai, mãe, avós com guarda) também pode ser incluído; quando não é pai nem mãe, a secretaria da unidade confere o documento de guarda.',
   '{nasceu,novo,membro,filho,filha,crianca,incluir,familia,dependente,guarda,avo}', 'Central de Vagas'),
  ('DUVIDA', 'Quem resolve o meu pedido?',
   'A IARA resolve na hora: cadastro, novo membro da família, mudança de endereço, inscrição e desistência da fila, atualização de dados, posição na fila, ofertas e envio de documentos. Vão para a secretaria da unidade: troca de turno, declarações, alteração de responsável e matrícula. Vão para a Secretaria (SEDUC): transporte, educação integral, AEE, alimentação especial, recursos e reclamações. Em todos os casos você recebe protocolo e prazo.',
   '{quem,resolve,pedido,protocolo,secretaria,unidade,encaminhado,alcada,prazo}', 'Atendimento ao Cidadão')
) as v(code, title, body, kw, sector)
where not exists (select 1 from iara.knowledge_articles k where k.title = v.title);

do $$
begin
  perform iara.audit_event('RULE_VERSION', 'rules', 'PRAZO_RESPOSTA_OFERTA:2026.02', null,
    'Prazo para efetivar a matrícula após a contemplação ajustado para 72 h (IN nº 025/2025-SEDUC, Anexo II); ofertas em andamento estendidas.');
end $$;

commit;
