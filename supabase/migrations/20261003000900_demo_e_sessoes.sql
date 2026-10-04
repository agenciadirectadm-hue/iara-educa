-- IARA Educa — 009 · Sessões do gateway, modo demonstração (atualização temporal, reinício do cenário) e rotinas
begin;

-- ---------------------------------------------------------------------------
-- Sessões (chamadas apenas pelo gateway, conectado como postgres)
-- ---------------------------------------------------------------------------
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
  elsif r.scope_type = 'GUARDIAN' then
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

create or replace function iara.session_resolve(p_token_hash text) returns uuid
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_user uuid;
begin
  update iara.app_sessions set last_seen_at = now(), expires_at = greatest(expires_at, now() + interval '2 hours')
  where token_hash = p_token_hash and revoked_at is null and expires_at > now()
  returning user_id into v_user;
  if v_user is not null then
    update iara.app_users set last_seen_at = now() where id = v_user and (last_seen_at is null or last_seen_at < now() - interval '1 minute');
  end if;
  return v_user;
end $$;

create or replace function iara.session_revoke(p_token_hash text) returns void
language sql security definer set search_path = iara, public
as $$ update iara.app_sessions set revoked_at = now() where token_hash = p_token_hash $$;

-- ---------------------------------------------------------------------------
-- Expiração de ofertas (silêncio não é aceite nem recusa: a criança volta à fila)
-- ---------------------------------------------------------------------------
create or replace function iara.expire_due_offers() returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  o record;
  v_n integer := 0;
begin
  for o in select vo.*, w.grade_level_id from iara.vacancy_offers vo
           left join iara.waiting_list_entries w on w.id = vo.waiting_list_entry_id
           where vo.status = 'OFFERED' and vo.expires_at < now() for update of vo skip locked loop
    update iara.vacancy_offers set status = 'EXPIRED' where id = o.id;
    update iara.waiting_list_entries set status = 'WAITING' where id = o.waiting_list_entry_id and status = 'OFFERED';
    if o.case_id is not null then
      update iara.service_cases set status = 'ENCERRADO', closed_at = now(), resolution_code = 'OFERTA_EXPIRADA',
             resolution_notes = 'Oferta expirou sem resposta; a criança voltou à fila.' where id = o.case_id;
      insert into iara.case_events (case_id, event_type, message, old_value, new_value, actor_label, visibility)
      values (o.case_id, 'OFERTA', 'Oferta expirada sem resposta no prazo. A vaga foi liberada e a criança voltou à fila (silêncio não é recusa).',
              'VAGA_OFERTADA', 'ENCERRADO', 'Rotina automática IARA', 'CIDADAO');
    end if;
    insert into iara.vacancy_events (tenant_id, class_id, unit_id, event_type, quantity, reference, actor_label)
    values (1, o.class_id, o.unit_id, 'LIBERACAO', 1, 'Oferta expirada ' || substr(o.id::text, 1, 8), 'Rotina automática IARA');
    insert into iara.notifications (tenant_id, guardian_id, student_id, case_id, channel, event_type, title, body)
    select 1, sg.guardian_id, o.student_id, o.case_id, 'WHATSAPP', 'OFERTA_EXPIRADA', 'Oferta expirada',
           'O prazo da oferta terminou sem resposta. A criança continua na fila e você será avisado de novas ofertas.'
    from iara.student_guardians sg where sg.student_id = o.student_id and sg.is_primary;
    if o.grade_level_id is not null then
      perform iara.recalculate_queue(o.unit_id, o.grade_level_id);
    end if;
    perform iara.audit_event('OFFER_EXPIRED', 'vacancy_offers', o.id::text, o.unit_id, 'Oferta expirada automaticamente; vaga liberada.');
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- ---------------------------------------------------------------------------
-- Modo demonstração: desloca no tempo os registros operacionais fictícios para que a
-- demonstração pareça "ao vivo" em qualquer data (a auditoria NÃO é alterada).
-- ---------------------------------------------------------------------------
create or replace function iara.demo_timeshift(p_min_hours integer default 6) returns interval
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_base timestamptz := (iara.setting('demo_baseline_at'))::timestamptz;
  d interval;
  dd integer;
begin
  if v_base is null or not coalesce((iara.setting('demo_mode'))::boolean, false) then
    return interval '0';
  end if;
  d := date_trunc('minute', now() - v_base);
  if d < make_interval(hours => p_min_hours) then
    return interval '0';
  end if;
  dd := extract(day from d)::int;
  perform set_config('iara.skip_audit', 'on', true);
  update iara.service_cases set opened_at = opened_at + d, sla_due_at = sla_due_at + d, closed_at = closed_at + d where is_demo;
  update iara.case_events set occurred_at = occurred_at + d where case_id in (select id from iara.service_cases where is_demo);
  update iara.waiting_list_entries set entered_at = entered_at + d where is_demo;
  update iara.vacancy_offers set offered_at = offered_at + d, expires_at = expires_at + d, accepted_at = accepted_at + d, declined_at = declined_at + d where is_demo;
  update iara.vacancy_blocks set created_at = created_at + d, released_at = released_at + d, valid_until = valid_until + dd where is_demo;
  update iara.vacancy_events set occurred_at = occurred_at + d;
  update iara.documents set received_at = received_at + d, validated_at = validated_at + d where is_demo and received_at > now() - interval '120 days';
  update iara.notifications set created_at = created_at + d, read_at = read_at + d;
  update iara.conversations set last_message_at = last_message_at + d, created_at = created_at + d where is_demo;
  update iara.messages set created_at = created_at + d;
  update iara.handoff_tasks set created_at = created_at + d;
  update iara.tool_executions set created_at = created_at + d;
  update iara.tenants set settings = jsonb_set(settings, '{demo_baseline_at}', to_jsonb(v_base + d)) where id = 1;
  perform set_config('iara.skip_audit', 'off', true);
  perform iara.audit_event('DEMO_TIMESHIFT', 'demo', 'baseline', null,
                           'Registros fictícios deslocados no tempo em ' || d::text || ' para manter a demonstração atual.');
  return d;
end $$;

create or replace function iara.housekeeping() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_shift interval;
  v_expired integer;
begin
  v_shift := iara.demo_timeshift();
  v_expired := iara.expire_due_offers();
  return jsonb_build_object('timeshift', v_shift::text, 'expired_offers', v_expired);
end $$;

-- ---------------------------------------------------------------------------
-- Reinício do cenário do cidadão (Maria · Ana Luísa · Davi)
-- ---------------------------------------------------------------------------
create or replace function iara.demo_reset_citizen() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_davi uuid := (iara.setting('demo_student_davi'))::uuid;
  v_entry uuid := (iara.setting('demo_entry_davi'))::uuid;
  v_case uuid := (iara.setting('demo_case_davi'))::uuid;
  v_maria uuid := (iara.setting('demo_guardian_maria'))::uuid;
  v_unit integer := (iara.setting('demo_unit_maria'))::int;
  v_base timestamptz := (iara.setting('demo_baseline_at'))::timestamptz;
  e record;
  v_pos integer;
begin
  if v_davi is null then
    raise exception 'Cenário de demonstração não configurado.';
  end if;
  update iara.vacancy_offers set status = 'CANCELLED', decline_reason = 'Reinício do cenário de demonstração'
  where student_id = v_davi and status in ('OFFERED', 'ACCEPTED', 'ENROLLED');
  for e in select id, class_id from iara.enrollments where student_id = v_davi and status = 'ACTIVE' loop
    update iara.students set current_enrollment_id = null where id = v_davi;
    update iara.enrollments set status = 'CANCELLED', exit_type = 'REINICIO_DEMO', end_date = current_date where id = e.id;
  end loop;
  update iara.students set status = 'AGUARDANDO_VAGA', current_enrollment_id = null where id = v_davi;
  update iara.waiting_list_entries set status = 'WAITING', demand_category = 'SEM_ATENDIMENTO' where id = v_entry;
  update iara.waiting_list_entries set status = 'CANCELLED'
  where student_id = v_davi and id <> v_entry and status in ('WAITING', 'OFFERED', 'ACCEPTED');
  update iara.service_cases set status = 'ENCERRADO', closed_at = coalesce(closed_at, now()), resolution_code = 'INSERIDO_NA_FILA',
         resolution_notes = 'Sem vaga ofertável na creche da unidade preferida; criança inserida na fila.'
  where id = v_case;
  update iara.service_cases set status = 'ENCERRADO', closed_at = now(), resolution_code = 'REINICIO_DEMO',
         resolution_notes = 'Encerrado pelo reinício do cenário de demonstração.'
  where guardian_id = v_maria and id <> v_case and opened_at > coalesce(v_base, now() - interval '30 days')
    and status not in ('ENCERRADO', 'MATRICULA_CONCLUIDA');
  update iara.documents set status = 'PENDENTE', received_at = null, validated_at = null, file_name = null
  where student_id = v_davi and doc_type = 'VACINACAO';
  insert into iara.case_events (case_id, event_type, message, actor_label, visibility)
  values (v_case, 'NOTA', 'Cenário de demonstração reiniciado: Davi volta a aguardar na fila.', coalesce(iara.my_label(), 'Sistema'), 'INTERNA');
  perform iara.compute_queue_priority(v_entry);
  perform iara.recalculate_queue(v_unit, 1::smallint);
  select position into v_pos from iara.waiting_list_entries where id = v_entry;
  perform iara.audit_event('DEMO_RESET', 'demo', 'cidadao', v_unit, 'Cenário do cidadão (Maria/Davi) reiniciado.');
  return jsonb_build_object('ok', true, 'posicao_davi', v_pos);
end $$;

commit;
