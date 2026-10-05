-- =============================================================================
-- IARA Educa · Conversas por unidade responsável, sob controle da Secretaria
--  · Ao passar para humano, a conversa vai para quem responde pela alçada: protocolo em andamento → a alçada dele;
--    criança da família matriculada → secretaria da unidade dela; sem vínculo → equipe da SEDUC.
--  · Direção e secretaria escolar veem e atendem as conversas encaminhadas à própria unidade.
--  · A Secretaria (SEDUC) controla todas: vê, assume, transfere entre unidades/equipes e acompanha esperas e
--    tempo de resposta de cada unidade (permissão conversations.manage).
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
-- =============================================================================
begin;

-- 1. Responsável, tempos e leitura -------------------------------------------------------------
alter table iara.conversations
  add column if not exists unit_id integer references iara.education_units(id),
  add column if not exists team text,
  add column if not exists handoff_at timestamptz,
  add column if not exists first_reply_at timestamptz,
  add column if not exists staff_read_at timestamptz;
create index if not exists conversations_unit_idx on iara.conversations (unit_id) where unit_id is not null;
alter table iara.handoff_tasks add column if not exists unit_id integer references iara.education_units(id);

-- 2. Permissões ------------------------------------------------------------------------------------
insert into iara.permissions (code, description, is_sensitive)
values ('conversations.manage', 'Controlar todas as conversas: transferir entre unidades e equipes e acompanhar o tratamento', false)
on conflict (code) do nothing;
insert into iara.role_permissions (role_code, permission_code) values
  ('SECRETARIO', 'conversations.manage'), ('ANALISTA_CENTRAL', 'conversations.manage'), ('ATENDIMENTO', 'conversations.manage'),
  ('DIRETOR_UNIDADE', 'conversations.read'), ('DIRETOR_UNIDADE', 'conversations.takeover'),
  ('SECRETARIA_ESCOLAR', 'conversations.read'), ('SECRETARIA_ESCOLAR', 'conversations.takeover')
on conflict do nothing;

-- 3. Quem responde ---------------------------------------------------------------------------------
create or replace function iara.responsavel_rotulo(p_unit integer, p_team text) returns text
language sql stable security definer set search_path = iara, public
as $$
  select case when p_unit is not null then
           (select case when u.name like 'CMEI%' then 'secretaria do ' else 'secretaria da ' end || u.name from iara.education_units u where u.id = p_unit)
         else iara.team_label(coalesce(p_team, 'ATENDIMENTO')) end
$$;

create or replace function iara.conversation_responsible(p_conversation uuid) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  c iara.conversations;
  sc iara.service_cases;
  v_unit integer;
begin
  select * into c from iara.conversations where id = p_conversation;
  -- protocolo em andamento na conversa: segue a alçada dele
  if c.active_case_id is not null then
    select * into sc from iara.service_cases where id = c.active_case_id;
    if found and sc.status not in ('ENCERRADO', 'MATRICULA_CONCLUIDA', 'NAO_ATENDIDO') then
      if sc.resolution_level = 'UNIDADE' and sc.unit_id is not null then
        return jsonb_build_object('unit_id', sc.unit_id, 'team', 'SECRETARIA_ESCOLAR');
      elsif sc.resolution_level = 'SECRETARIA' then
        return jsonb_build_object('unit_id', null, 'team', coalesce(sc.assigned_team, 'ATENDIMENTO'));
      end if;
    end if;
  end if;
  -- criança da família matriculada: a secretaria da unidade dela (a da criança em atendimento primeiro)
  select e.unit_id into v_unit
  from iara.enrollments e
  where e.status = 'ACTIVE'
    and (e.student_id = c.active_student_id
         or e.student_id in (select sg.student_id from iara.student_guardians sg where sg.guardian_id = c.guardian_id))
  order by (e.student_id = c.active_student_id) desc nulls last, e.start_date desc nulls last
  limit 1;
  if v_unit is not null then
    return jsonb_build_object('unit_id', v_unit, 'team', 'SECRETARIA_ESCOLAR');
  end if;
  -- sem vínculo com unidade: vaga e fila são da Central; o resto, do Atendimento ao Cidadão
  return jsonb_build_object('unit_id', null,
    'team', case when c.intent in ('procurar_vaga', 'fila', 'posicao_fila', 'oferta', 'transferencia') then 'CENTRAL_VAGAS' else 'ATENDIMENTO' end);
end $$;

-- encaminha (IARA, cidadão ou servidor): estado, responsável, tarefa, registro na conversa e auditoria
create or replace function iara.conversation_route(p_conversation uuid, p_reason text, p_unit integer, p_team text, p_by text) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.conversations;
  r jsonb;
  v_unit integer := p_unit;
  v_team text := p_team;
  v_label text;
begin
  select * into c from iara.conversations where id = p_conversation for update;
  if not found then
    raise exception 'Conversa não encontrada.' using errcode = 'P0002';
  end if;
  if v_team is null then
    r := iara.conversation_responsible(p_conversation);
    v_unit := (r ->> 'unit_id')::int;
    v_team := r ->> 'team';
  end if;
  v_label := iara.responsavel_rotulo(v_unit, v_team);
  update iara.conversations set state = 'HUMAN_PENDING', unit_id = v_unit, team = v_team, handoff_at = now(),
         first_reply_at = null, assigned_user_id = null, assigned_label = null
  where id = c.id;
  update iara.handoff_tasks set status = 'CONCLUIDA', updated_at = now() where conversation_id = c.id and status in ('ABERTA', 'ASSUMIDA');
  insert into iara.handoff_tasks (tenant_id, conversation_id, case_id, reason, sector, unit_id, summary)
  values (1, c.id, c.active_case_id, left(coalesce(nullif(trim(p_reason), ''), 'Atendimento humano'), 300), v_team, v_unit, c.summary);
  insert into iara.messages (conversation_id, direction, sender_type, sender_label, body)
  values (c.id, 'OUT', 'SISTEMA', 'Sistema',
          format('Conversa encaminhada para %s%s.', v_label, case when p_by is not null then ' por ' || p_by else '' end)
          || case when nullif(trim(p_reason), '') is not null then ' Motivo: ' || trim(p_reason) || '.' else '' end);
  perform iara.audit_event('CONVERSA_ENCAMINHADA', 'conversation', c.id::text, v_unit,
    format('Conversa de %s encaminhada para %s%s.', coalesce(c.contact_label, 'contato'), v_label, coalesce(' — ' || nullif(trim(p_reason), ''), '')));
  return jsonb_build_object('unit_id', v_unit, 'unit_name', (select name from iara.education_units where id = v_unit),
                            'team', v_team, 'team_label', iara.team_label(v_team), 'label', v_label);
end $$;

-- 4. Acesso: a unidade vê o que foi encaminhado a ela ------------------------------------------------------
create or replace function iara.can_access_conversation(p_conversation uuid) returns boolean
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  c iara.conversations;
begin
  select * into c from iara.conversations where id = p_conversation;
  if not found then return false; end if;
  if c.owner_user_id = iara.current_user_id() then return true; end if;
  if iara.my_scope() = 'GUARDIAN' then return c.guardian_id is not null and c.guardian_id = iara.my_guardian(); end if;
  if not iara.has_perm('conversations.read') then return false; end if;
  if iara.my_scope() = 'NETWORK' then return true; end if;
  if iara.my_scope() = 'UNIT' and c.unit_id is not null and c.unit_id = iara.my_unit() then return true; end if;
  return c.active_student_id is not null and iara.can_access_student(c.active_student_id);
end $$;

create or replace function iara.my_conversation_ids() returns setof uuid
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  return query select c.id from iara.conversations c where c.owner_user_id = iara.current_user_id();
  if iara.my_scope() = 'GUARDIAN' then
    return query select c.id from iara.conversations c where c.guardian_id = iara.my_guardian();
  elsif iara.my_scope() = 'UNIT' and iara.has_perm('conversations.read') then
    return query select c.id from iara.conversations c
                 where c.unit_id = iara.my_unit() or c.active_student_id in (select iara.my_student_ids());
  end if;
end $$;

-- 5. A conversa conta quem responde ---------------------------------------------------------------------
create or replace function iara.conversation_json(p_id uuid, p_limit integer default 200) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object(
    'conversation', jsonb_build_object('id', c.id, 'channel', c.channel, 'state', c.state, 'contact', c.contact_label, 'phone', c.contact_phone_masked,
      'guardian_id', c.guardian_id, 'assigned_user_id', c.assigned_user_id, 'assigned', c.assigned_label,
      'assigned_to_me', c.assigned_user_id = iara.current_user_id(), 'intent', c.intent, 'summary', c.summary,
      'identity_verified', c.identity_verified, 'active_student_id', c.active_student_id, 'active_case_id', c.active_case_id,
      'last_message_at', c.last_message_at, 'is_demo', c.is_demo, 'owner_is_me', c.owner_user_id = iara.current_user_id(),
      'unit_id', c.unit_id, 'unit_name', (select u.name from iara.education_units u where u.id = c.unit_id), 'team', c.team,
      'responsible', case when c.team is not null then iara.responsavel_rotulo(c.unit_id, c.team) end,
      'handoff_at', c.handoff_at, 'first_reply_at', c.first_reply_at),
    'messages', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'direction', m.direction, 'sender_type', m.sender_type, 'sender', m.sender_label,
                                                              'body', m.body, 'payload', m.payload, 'status', m.status, 'at', m.created_at) order by m.created_at, m.id)
                          from (select * from iara.messages m2 where m2.conversation_id = c.id order by m2.created_at desc limit p_limit) m), '[]'::jsonb)
  )
  from iara.conversations c where c.id = p_id
$$;

-- 6. Ações ------------------------------------------------------------------------------------------------
-- IARA (pelo cidadão): passa para humano no responsável certo e diz para onde foi
create or replace function api.conversation_handoff(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.conversations;
begin
  select * into c from iara.conversations where id = (p ->> 'conversation_id')::uuid;
  if not found or not (c.owner_user_id = iara.current_user_id() or (iara.my_scope() = 'GUARDIAN' and c.guardian_id = iara.my_guardian())) then
    raise exception 'Conversa não encontrada.' using errcode = 'P0002';
  end if;
  if c.state in ('HUMAN_PENDING', 'HUMAN_ACTIVE') and c.team is not null then
    return jsonb_build_object('ja_encaminhada', true, 'unit_id', c.unit_id, 'team', c.team, 'label', iara.responsavel_rotulo(c.unit_id, c.team));
  end if;
  return iara.conversation_route(c.id, p ->> 'reason', null, null, null);
end $$;

-- servidor: transfere. A SEDUC manda para qualquer unidade ou equipe; a unidade devolve à Secretaria.
create or replace function api.conversation_transfer(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.conversations;
  v_unit integer := nullif(p ->> 'unit_id', '')::int;
  v_team text := nullif(p ->> 'team', '');
  v_motivo text := nullif(trim(coalesce(p ->> 'motivo', '')), '');
begin
  perform iara.require_perm('conversations.takeover');
  select * into c from iara.conversations where id = (p ->> 'id')::uuid for update;
  if not found or not iara.can_access_conversation(c.id) then
    raise exception 'Conversa não encontrada.' using errcode = 'P0002';
  end if;
  if c.state = 'CLOSED' then
    raise exception 'Conversa encerrada. Se a família escrever de novo, ela volta para a fila.' using errcode = '22023';
  end if;
  if v_unit is not null then
    v_team := 'SECRETARIA_ESCOLAR';
    if not exists (select 1 from iara.education_units where id = v_unit) then
      raise exception 'Unidade inválida.' using errcode = '22023';
    end if;
    if not iara.has_perm('conversations.manage') then
      raise exception 'A unidade devolve a conversa à Secretaria; a transferência entre unidades é feita pela SEDUC.' using errcode = '42501';
    end if;
  else
    v_team := coalesce(v_team, 'ATENDIMENTO');
    if v_team not in ('ATENDIMENTO', 'CENTRAL_VAGAS', 'TRANSPORTE', 'AEE', 'INTEGRAL', 'ALIMENTACAO', 'OUVIDORIA', 'GESTAO') then
      raise exception 'Equipe inválida.' using errcode = '22023';
    end if;
  end if;
  if v_motivo is null then
    raise exception 'Informe o motivo (fica registrado na conversa e na auditoria).' using errcode = '22023';
  end if;
  perform iara.conversation_route(c.id, v_motivo, v_unit, v_team, iara.my_label());
  return iara.conversation_json(c.id);
end $$;

create or replace function api.conversation_takeover(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.conversations;
begin
  perform iara.require_perm('conversations.takeover');
  select * into c from iara.conversations where id = (p ->> 'id')::uuid for update;
  if not found or not iara.can_access_conversation(c.id) then
    raise exception 'Conversa não encontrada.' using errcode = 'P0002';
  end if;
  if c.state = 'HUMAN_ACTIVE' and c.assigned_user_id is distinct from iara.current_user_id() then
    raise exception 'Conversa já assumida por %.', c.assigned_label using errcode = '55006';
  end if;
  -- assumir direto da IARA também conta como encaminhamento (a quem assumiu)
  update iara.conversations set state = 'HUMAN_ACTIVE', assigned_user_id = iara.current_user_id(), assigned_label = iara.my_label(),
         staff_read_at = now(), handoff_at = coalesce(handoff_at, now()),
         unit_id = case when team is null and iara.my_scope() = 'UNIT' then iara.my_unit() else unit_id end,
         team = coalesce(team, case when iara.my_scope() = 'UNIT' then 'SECRETARIA_ESCOLAR' else 'ATENDIMENTO' end)
  where id = c.id;
  insert into iara.messages (conversation_id, direction, sender_type, sender_label, body)
  values (c.id, 'OUT', 'SISTEMA', 'Sistema', iara.my_label() || ' assumiu a conversa. A IARA está pausada até a devolução explícita.');
  update iara.handoff_tasks set status = 'ASSUMIDA', assigned_user_id = iara.current_user_id(), updated_at = now()
  where conversation_id = c.id and status = 'ABERTA';
  return iara.conversation_json(c.id);
end $$;

create or replace function api.conversation_operator_message(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.conversations;
  v_body text := trim(coalesce(p ->> 'body', ''));
begin
  perform iara.require_perm('conversations.takeover');
  select * into c from iara.conversations where id = (p ->> 'id')::uuid for update;
  if not found or c.state <> 'HUMAN_ACTIVE' or c.assigned_user_id is distinct from iara.current_user_id() then
    raise exception 'Assuma a conversa antes de responder (evita disputa com a IARA).' using errcode = '42501';
  end if;
  if v_body = '' then
    raise exception 'Mensagem vazia.' using errcode = '22023';
  end if;
  insert into iara.messages (conversation_id, direction, sender_type, sender_label, body)
  values (c.id, 'OUT', 'OPERADOR', iara.my_label(), left(v_body, 2000));
  update iara.conversations set last_message_at = now(), staff_read_at = now(), first_reply_at = coalesce(first_reply_at, now()) where id = c.id;
  return iara.conversation_json(c.id);
end $$;

create or replace function api.conversa_marcar_lida(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id uuid := (p ->> 'id')::uuid;
begin
  if iara.my_scope() = 'GUARDIAN' or not iara.can_access_conversation(v_id) then
    return jsonb_build_object('ok', false);
  end if;
  update iara.conversations set staff_read_at = now() where id = v_id;
  return jsonb_build_object('ok', true);
end $$;

-- 7. IARA: passagem para humano sempre com responsável (inclusive caminhos antigos) ----------------------------
create or replace function iara.agent_reply(p_conversation uuid, p_messages jsonb, p_patch jsonb, p_tools jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  m jsonb;
  t jsonb;
  v_state text := p_patch ->> 'state';
begin
  for m in select * from jsonb_array_elements(coalesce(p_messages, '[]'::jsonb)) loop
    insert into iara.messages (conversation_id, direction, sender_type, sender_label, body, payload, created_at)
    values (p_conversation, 'OUT', coalesce(m ->> 'sender_type', 'IARA'), coalesce(m ->> 'sender', 'IARA'), m ->> 'body',
            coalesce(m -> 'payload', '{}'::jsonb), clock_timestamp());
  end loop;
  for t in select * from jsonb_array_elements(coalesce(p_tools, '[]'::jsonb)) loop
    insert into iara.tool_executions (conversation_id, tool_name, input, output, status, error, correlation_id, idempotency_key, duration_ms, user_id)
    values (p_conversation, t ->> 'tool', coalesce(t -> 'input', '{}'::jsonb), coalesce(t -> 'output', '{}'::jsonb), coalesce(t ->> 'status', 'OK'),
            t ->> 'error', t ->> 'correlation_id', t ->> 'idempotency_key', (t ->> 'ms')::int, iara.current_user_id());
  end loop;
  update iara.conversations set
    context = case when p_patch ? 'context' then coalesce(p_patch -> 'context', '{}'::jsonb) else context end,
    intent = coalesce(p_patch ->> 'intent', intent),
    state = coalesce(v_state, state),
    identity_verified = coalesce((p_patch ->> 'identity_verified')::boolean, identity_verified),
    active_student_id = case when p_patch ? 'active_student_id' then nullif(p_patch ->> 'active_student_id', '')::uuid else active_student_id end,
    active_case_id = case when p_patch ? 'active_case_id' then nullif(p_patch ->> 'active_case_id', '')::uuid else active_case_id end,
    summary = coalesce(p_patch ->> 'summary', summary),
    last_message_at = clock_timestamp()
  where id = p_conversation;
  if v_state = 'HUMAN_PENDING' and not exists (select 1 from iara.handoff_tasks h where h.conversation_id = p_conversation and h.status = 'ABERTA') then
    perform iara.conversation_route(p_conversation, coalesce(p_patch ->> 'handoff_reason', 'Pedido do cidadão'), null, null, null);
  end if;
  return iara.conversation_json(p_conversation);
end $$;

-- 8. Listas ------------------------------------------------------------------------------------------------
-- lista no estilo WhatsApp: a SEDUC vê todas; a unidade, as encaminhadas a ela
create or replace function api.conversas_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_all boolean := iara.my_scope() = 'NETWORK';
  v_unit integer := iara.my_unit();
  v_filtro text := coalesce(nullif(p ->> 'filtro', ''), 'abertas');
  v_canal text := nullif(p ->> 'canal', '');
  v_q text := nullif(iara.norm(coalesce(p ->> 'q', '')), '');
  v_unidade integer := nullif(p ->> 'unidade_id', '')::int;
  v_equipe text := nullif(p ->> 'equipe', '');
begin
  if not iara.has_perm('conversations.read') then
    raise exception 'Sem permissão para ver conversas.' using errcode = '42501';
  end if;
  if not v_all and v_unit is null then
    raise exception 'Perfil sem unidade vinculada.' using errcode = '42501';
  end if;
  return (
    with base as (
      select c.* from iara.conversations c
      where (v_all or c.unit_id = v_unit)
        and (v_canal is null or c.channel = v_canal or (v_canal = 'WHATSAPP_TODOS' and c.channel in ('WHATSAPP', 'WHATSAPP_SIMULADO')))
        and (v_unidade is null or c.unit_id = v_unidade)
        and (v_equipe is null or (v_equipe = 'SEDUC' and c.unit_id is null and c.team is not null) or c.team = v_equipe)
        and (v_q is null or iara.norm(coalesce(c.contact_label, '') || ' ' || coalesce(c.summary, '') || ' ' || coalesce(c.contact_phone_masked, '')) like '%' || v_q || '%')
    ), quem as (
      select b.*, case when b.state in ('BOT_ACTIVE', 'FOLLOWUP_PENDING') then 'IA' when b.state = 'HUMAN_PENDING' then 'AGUARDANDO'
                       when b.state = 'HUMAN_ACTIVE' then 'HUMANO' else 'ENCERRADA' end as quem
      from base b
    ), filtrada as (
      -- quem espera humano primeiro (a espera mais antiga no topo), depois humano atendendo, depois a IARA
      select q.*, row_number() over (order by case q.quem when 'AGUARDANDO' then 0 when 'HUMANO' then 1 when 'IA' then 2 else 3 end,
                                             case when q.quem = 'AGUARDANDO' then extract(epoch from q.handoff_at) end asc nulls last,
                                             q.last_message_at desc nulls last) as ordem
      from quem q where case v_filtro
        when 'abertas' then q.quem <> 'ENCERRADA' when 'ia' then q.quem = 'IA' when 'aguardando' then q.quem = 'AGUARDANDO'
        when 'humano' then q.quem = 'HUMANO' when 'encerradas' then q.quem = 'ENCERRADA' else true end
    )
    select jsonb_build_object(
      'escopo', case when v_all then 'REDE' else 'UNIDADE' end,
      'unidade', (select u.name from iara.education_units u where u.id = v_unit),
      'pode_controlar', iara.has_perm('conversations.manage'),
      'contagem', (select jsonb_build_object('abertas', count(*) filter (where quem <> 'ENCERRADA'), 'ia', count(*) filter (where quem = 'IA'),
                                             'aguardando', count(*) filter (where quem = 'AGUARDANDO'), 'humano', count(*) filter (where quem = 'HUMANO'),
                                             'encerradas', count(*) filter (where quem = 'ENCERRADA')) from quem),
      'itens', coalesce((select jsonb_agg(jsonb_build_object(
          'id', f.id, 'contato', f.contact_label, 'telefone', f.contact_phone_masked, 'canal', f.channel, 'estado', f.state, 'quem', f.quem,
          'atendente', f.assigned_label, 'comigo', f.assigned_user_id = iara.current_user_id(),
          'responsavel', case when f.team is not null then jsonb_build_object('unit_id', f.unit_id, 'equipe', f.team,
                              'rotulo', iara.responsavel_rotulo(f.unit_id, f.team),
                              'curto', coalesce((select u.short_name from iara.education_units u where u.id = f.unit_id), iara.team_label(f.team))) end,
          'aguardando_desde', case when f.quem = 'AGUARDANDO' then f.handoff_at end,
          'ultima', (select jsonb_build_object('texto', left(m.body, 120), 'de', m.sender_type, 'direcao', m.direction, 'em', m.created_at)
                     from iara.messages m where m.conversation_id = f.id order by m.created_at desc limit 1),
          'nao_lidas', case when f.quem in ('AGUARDANDO', 'HUMANO')
                            then (select count(*) from iara.messages m where m.conversation_id = f.id and m.direction = 'IN'
                                    and m.created_at > coalesce(f.staff_read_at, f.handoff_at, '-infinity'::timestamptz)) else 0 end,
          'protocolo', (select sc.protocol_number from iara.service_cases sc where sc.id = f.active_case_id),
          'resumo', f.summary, 'em', f.last_message_at) order by f.ordem) from filtrada f where f.ordem <= 120), '[]'::jsonb)
    ));
end $$;

-- controle da Secretaria: como cada unidade e equipe está tratando as conversas
create or replace function api.conversas_controle(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_limite integer := least(greatest(coalesce((p ->> 'limite_min')::int, 30), 5), 1440);
begin
  if not (iara.has_perm('conversations.manage') or (iara.my_scope() = 'NETWORK' and iara.has_perm('conversations.read'))) then
    raise exception 'Somente a Secretaria acompanha o tratamento das conversas de todas as unidades.' using errcode = '42501';
  end if;
  return (
    with abertas as (
      select c.*, extract(epoch from now() - c.handoff_at) / 60 as espera_min from iara.conversations c where c.state <> 'CLOSED'
    ), grupos as (
      select a.unit_id, coalesce(a.team, 'ATENDIMENTO') as team,
             count(*) filter (where a.state = 'HUMAN_PENDING') as aguardando,
             count(*) filter (where a.state = 'HUMAN_ACTIVE') as em_atendimento,
             count(*) filter (where a.state = 'HUMAN_PENDING' and a.espera_min > v_limite) as atrasadas,
             round(max(a.espera_min) filter (where a.state = 'HUMAN_PENDING')) as maior_espera_min
      from abertas a
      where a.state in ('HUMAN_PENDING', 'HUMAN_ACTIVE')
      group by 1, 2
    ), resposta as (
      select c.unit_id, coalesce(c.team, 'ATENDIMENTO') as team,
             round(avg(extract(epoch from c.first_reply_at - c.handoff_at) / 60)) as resposta_media_min, count(*) as respondidas_30d
      from iara.conversations c
      where c.first_reply_at is not null and c.handoff_at > now() - interval '30 days'
      group by 1, 2
    )
    select jsonb_build_object(
      'limite_min', v_limite,
      'totais', (select jsonb_build_object(
          'ia', count(*) filter (where state in ('BOT_ACTIVE', 'FOLLOWUP_PENDING')),
          'aguardando', count(*) filter (where state = 'HUMAN_PENDING'),
          'humano', count(*) filter (where state = 'HUMAN_ACTIVE'),
          'atrasadas', count(*) filter (where state = 'HUMAN_PENDING' and espera_min > v_limite),
          'nas_unidades', count(*) filter (where state in ('HUMAN_PENDING', 'HUMAN_ACTIVE') and unit_id is not null),
          'na_seduc', count(*) filter (where state in ('HUMAN_PENDING', 'HUMAN_ACTIVE') and unit_id is null),
          'whatsapp_real', count(*) filter (where channel = 'WHATSAPP')) from abertas),
      'responsaveis', coalesce((select jsonb_agg(jsonb_build_object(
          'unit_id', g.unit_id, 'equipe', g.team, 'rotulo', iara.responsavel_rotulo(g.unit_id, g.team),
          'curto', coalesce((select u.short_name from iara.education_units u where u.id = g.unit_id), iara.team_label(g.team)),
          'tipo', case when g.unit_id is null then 'SEDUC' else 'UNIDADE' end,
          'aguardando', g.aguardando, 'em_atendimento', g.em_atendimento, 'atrasadas', g.atrasadas, 'maior_espera_min', g.maior_espera_min,
          'resposta_media_min', r.resposta_media_min)
          order by g.atrasadas desc, g.aguardando desc, g.maior_espera_min desc nulls last)
        from grupos g left join resposta r on r.unit_id is not distinct from g.unit_id and r.team = g.team), '[]'::jsonb),
      'unidades', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'nome', u.name, 'curto', u.short_name) order by u.name)
                            from iara.education_units u where u.status = 'ATIVA'), '[]'::jsonb)
    ));
end $$;

-- 9. Demonstração: as conversas que já aguardavam humano ganham responsável pela mesma regra -----------------
do $$
declare
  r record;
  j jsonb;
begin
  perform set_config('iara.skip_audit', 'on', true);
  for r in select c.id, c.state, c.last_message_at from iara.conversations c
           where c.state in ('HUMAN_PENDING', 'HUMAN_ACTIVE') and c.team is null loop
    if r.state = 'HUMAN_ACTIVE' then
      j := jsonb_build_object('unit_id', null, 'team', 'CENTRAL_VAGAS'); -- já está com servidor da Central
    else
      j := iara.conversation_responsible(r.id);
    end if;
    update iara.conversations c set unit_id = (j ->> 'unit_id')::int, team = j ->> 'team',
           handoff_at = coalesce((select min(h.created_at) from iara.handoff_tasks h where h.conversation_id = c.id and h.status in ('ABERTA', 'ASSUMIDA')),
                                 r.last_message_at - interval '20 minutes'),
           first_reply_at = case when r.state = 'HUMAN_ACTIVE'
                                 then coalesce((select min(m.created_at) from iara.messages m where m.conversation_id = c.id and m.sender_type = 'OPERADOR'),
                                               r.last_message_at - interval '12 minutes') end
    where c.id = r.id;
    update iara.handoff_tasks set unit_id = (j ->> 'unit_id')::int, sector = j ->> 'team'
    where conversation_id = r.id and status in ('ABERTA', 'ASSUMIDA');
  end loop;
  perform set_config('iara.skip_audit', 'off', true);
end $$;

revoke all on function iara.conversation_route(uuid, text, integer, text, text), iara.conversation_responsible(uuid),
  iara.responsavel_rotulo(integer, text) from public;

commit;
