-- IARA Educa — 014 · Agente IARA: conversas, caixa de entrada, atendimento humano (cap. 74)
-- Mensagens da IARA só podem ser gravadas pelo gateway (iara.agent_reply, sem grant para clientes).
begin;

create or replace function iara.conversation_json(p_id uuid, p_limit integer default 200) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object(
    'conversation', jsonb_build_object('id', c.id, 'channel', c.channel, 'state', c.state, 'contact', c.contact_label, 'phone', c.contact_phone_masked,
      'guardian_id', c.guardian_id, 'assigned_user_id', c.assigned_user_id, 'assigned', c.assigned_label,
      'assigned_to_me', c.assigned_user_id = iara.current_user_id(), 'intent', c.intent, 'summary', c.summary,
      'identity_verified', c.identity_verified, 'active_student_id', c.active_student_id, 'active_case_id', c.active_case_id,
      'last_message_at', c.last_message_at, 'is_demo', c.is_demo, 'owner_is_me', c.owner_user_id = iara.current_user_id()),
    'messages', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'direction', m.direction, 'sender_type', m.sender_type, 'sender', m.sender_label,
                                                              'body', m.body, 'payload', m.payload, 'status', m.status, 'at', m.created_at) order by m.created_at, m.id)
                          from (select * from iara.messages m2 where m2.conversation_id = c.id order by m2.created_at desc limit p_limit) m), '[]'::jsonb)
  )
  from iara.conversations c where c.id = p_id
$$;

-- Caixa de entrada (operadores)
create or replace function api.conversations_list(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security invoker set search_path = iara, public
as $$
  with base as (
    select c.* from iara.conversations c
    where (nullif(p ->> 'state', '') is null or c.state = p ->> 'state')
      and (nullif(p ->> 'q', '') is null or iara.norm(c.contact_label || ' ' || coalesce(c.summary, '')) like '%' || iara.norm(p ->> 'q') || '%')
  )
  select jsonb_build_object(
    'counts', coalesce((select jsonb_object_agg(state, n) from (select state, count(*) n from iara.conversations group by 1) z), '{}'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'contact', c.contact_label, 'phone', c.contact_phone_masked, 'state', c.state,
        'intent', c.intent, 'summary', c.summary, 'assigned', c.assigned_label, 'assigned_to_me', c.assigned_user_id = iara.current_user_id(),
        'last_message_at', c.last_message_at, 'channel', c.channel,
        'last_message', (select left(m.body, 140) from iara.messages m where m.conversation_id = c.id order by m.created_at desc limit 1),
        'case', (select jsonb_build_object('id', sc.id, 'protocol', sc.protocol_number) from iara.service_cases sc where sc.id = c.active_case_id))
        order by case c.state when 'HUMAN_PENDING' then 0 when 'HUMAN_ACTIVE' then 1 when 'FOLLOWUP_PENDING' then 2 when 'BOT_ACTIVE' then 3 else 4 end,
                 c.last_message_at desc)
      from (select * from base order by last_message_at desc limit 80) c), '[]'::jsonb)
  )
$$;

create or replace function api.conversation_detail(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_id uuid := (p ->> 'id')::uuid;
  v jsonb;
begin
  if not iara.can_access_conversation(v_id) then
    raise exception 'Conversa não encontrada ou sem permissão.' using errcode = 'P0002';
  end if;
  v := iara.conversation_json(v_id);
  if iara.my_scope() <> 'GUARDIAN' then
    v := v || jsonb_build_object(
      'handoffs', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'reason', h.reason, 'sector', h.sector, 'status', h.status,
                                                                'summary', h.summary, 'at', h.created_at) order by h.created_at desc)
                            from iara.handoff_tasks h where h.conversation_id = v_id), '[]'::jsonb),
      'tools', coalesce((select jsonb_agg(jsonb_build_object('tool', t.tool_name, 'status', t.status, 'input', t.input, 'output', t.output,
                                                             'error', t.error, 'ms', t.duration_ms, 'at', t.created_at) order by t.created_at desc)
                         from (select * from iara.tool_executions t2 where t2.conversation_id = v_id order by t2.created_at desc limit 30) t), '[]'::jsonb),
      'context_case', (select jsonb_build_object('id', c.id, 'protocol', c.protocol_number, 'status', c.status, 'subject', c.subject)
                       from iara.service_cases c join iara.conversations cv on cv.active_case_id = c.id where cv.id = v_id),
      'context_student', (select jsonb_build_object('id', s.id, 'name', s.full_name, 'age', iara.age_text(s.birth_date))
                          from iara.students s join iara.conversations cv on cv.active_student_id = s.id where cv.id = v_id),
      'guardian', (select jsonb_build_object('id', g.id, 'name', g.full_name) from iara.guardians g join iara.conversations cv on cv.guardian_id = g.id where cv.id = v_id));
  end if;
  return v;
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
  update iara.conversations set state = 'HUMAN_ACTIVE', assigned_user_id = iara.current_user_id(), assigned_label = iara.my_label() where id = c.id;
  insert into iara.messages (conversation_id, direction, sender_type, sender_label, body)
  values (c.id, 'OUT', 'SISTEMA', 'Sistema', iara.my_label() || ' assumiu a conversa. A IARA está pausada até a devolução explícita.');
  update iara.handoff_tasks set status = 'ASSUMIDA', assigned_user_id = iara.current_user_id(), updated_at = now()
  where conversation_id = c.id and status = 'ABERTA';
  return iara.conversation_json(c.id);
end $$;

create or replace function api.conversation_release(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.conversations;
begin
  perform iara.require_perm('conversations.takeover');
  select * into c from iara.conversations where id = (p ->> 'id')::uuid for update;
  if not found or c.state <> 'HUMAN_ACTIVE' or c.assigned_user_id is distinct from iara.current_user_id() then
    raise exception 'Só quem assumiu a conversa pode devolvê-la à IARA.' using errcode = '42501';
  end if;
  update iara.conversations set state = coalesce(nullif(p ->> 'to_state', ''), 'BOT_ACTIVE'), assigned_user_id = null, assigned_label = null where id = c.id;
  insert into iara.messages (conversation_id, direction, sender_type, sender_label, body)
  values (c.id, 'OUT', 'SISTEMA', 'Sistema', 'Atendimento humano encerrado por ' || iara.my_label() || '. A IARA volta a responder nesta conversa.');
  update iara.handoff_tasks set status = 'CONCLUIDA', updated_at = now() where conversation_id = c.id and status = 'ASSUMIDA';
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
  update iara.conversations set last_message_at = now() where id = c.id;
  return iara.conversation_json(c.id);
end $$;

create or replace function api.conversation_close(p jsonb) returns jsonb
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
  update iara.conversations set state = 'CLOSED', assigned_user_id = null, assigned_label = null where id = c.id;
  insert into iara.messages (conversation_id, direction, sender_type, sender_label, body)
  values (c.id, 'OUT', 'SISTEMA', 'Sistema', 'Conversa encerrada por ' || iara.my_label() || '. Os protocolos vinculados seguem seus próprios status.');
  return iara.conversation_json(c.id);
end $$;

-- Lado do cidadão: obtém (ou cria) a conversa do usuário atual com a saudação da IARA
create or replace function api.iara_conversation(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_me uuid := iara.current_user_id();
  v_id uuid;
  v_g uuid := iara.my_guardian();
  v_name text;
begin
  if v_me is null then
    raise exception 'Sessão necessária.' using errcode = '28000';
  end if;
  select id into v_id from iara.conversations where owner_user_id = v_me and state <> 'CLOSED' order by created_at desc limit 1;
  if v_id is null or coalesce((p ->> 'new')::boolean, false) then
    select split_part(full_name, ' ', 1) into v_name from iara.guardians where id = v_g;
    insert into iara.conversations (tenant_id, channel, guardian_id, owner_user_id, contact_label, contact_phone_masked, state, identity_verified, is_demo)
    values (1, coalesce(nullif(p ->> 'channel', ''), 'WHATSAPP_SIMULADO'), v_g, v_me, coalesce(iara.my_label(), 'Visitante'),
            (select iara.mask_phone(whatsapp_phone) from iara.guardians where id = v_g), 'BOT_ACTIVE', false, true)
    returning id into v_id;
    insert into iara.messages (conversation_id, direction, sender_type, sender_label, body, payload)
    values (v_id, 'OUT', 'IARA', 'IARA',
            'Oi' || coalesce(', ' || v_name, '') || '! 💜 Eu sou a IARA, assistente virtual da Secretaria Municipal de Educação de Maringá. '
            || 'Posso ajudar você a encontrar uma unidade, acompanhar uma solicitação ou entender sua posição na fila. Como posso ajudar?',
            jsonb_build_object('quick_replies', jsonb_build_array(
                                 jsonb_build_object('label', 'Procurar vaga', 'action', 'intent:procurar_vaga'),
                                 jsonb_build_object('label', 'Posição na fila', 'action', 'intent:fila'),
                                 jsonb_build_object('label', 'Ofertas de vaga', 'action', 'intent:oferta'),
                                 jsonb_build_object('label', 'Acompanhar solicitação', 'action', 'intent:acompanhar'),
                                 jsonb_build_object('label', 'Documentos', 'action', 'intent:documentos'),
                                 jsonb_build_object('label', 'Encontrar unidade', 'action', 'intent:unidade'),
                                 jsonb_build_object('label', 'Falar com atendente', 'action', 'intent:atendente')),
                               'notice', 'Assistente virtual · demonstração (nenhuma mensagem real é enviada)'));
  end if;
  return iara.conversation_json(v_id);
end $$;

-- Mensagem do cidadão (o gateway decide a resposta da IARA em seguida)
create or replace function api.iara_send(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.conversations;
  v_body text := trim(coalesce(p ->> 'body', ''));
  v_msg uuid;
begin
  select * into c from iara.conversations where id = (p ->> 'conversation_id')::uuid for update;
  if not found or c.owner_user_id is distinct from iara.current_user_id() then
    raise exception 'Conversa não encontrada.' using errcode = 'P0002';
  end if;
  if v_body = '' then
    raise exception 'Mensagem vazia.' using errcode = '22023';
  end if;
  insert into iara.messages (conversation_id, direction, sender_type, sender_label, body, payload)
  values (c.id, 'IN', 'CIDADAO', c.contact_label, left(v_body, 2000), coalesce(p -> 'payload', '{}'::jsonb))
  returning id into v_msg;
  update iara.conversations set last_message_at = now(), state = case when state = 'CLOSED' then 'BOT_ACTIVE' else state end where id = c.id;
  return jsonb_build_object('message_id', v_msg, 'conversation_id', c.id, 'state', case when c.state = 'CLOSED' then 'BOT_ACTIVE' else c.state end,
                            'context', c.context, 'identity_verified', c.identity_verified, 'guardian_id', c.guardian_id,
                            'active_student_id', c.active_student_id, 'active_case_id', c.active_case_id);
end $$;

-- Gateway apenas: grava respostas da IARA, atualiza contexto/estado e registra ferramentas
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
  if v_state = 'HUMAN_PENDING' then
    insert into iara.handoff_tasks (tenant_id, conversation_id, case_id, reason, sector, summary)
    select 1, c.id, c.active_case_id, coalesce(p_patch ->> 'handoff_reason', 'Pedido do cidadão'), coalesce(p_patch ->> 'handoff_sector', 'CENTRAL_VAGAS'),
           coalesce(p_patch ->> 'summary', c.summary)
    from iara.conversations c where c.id = p_conversation
      and not exists (select 1 from iara.handoff_tasks h where h.conversation_id = c.id and h.status = 'ABERTA');
  end if;
  return iara.conversation_json(p_conversation);
end $$;

grant execute on function api.conversations_list(jsonb), api.conversation_detail(jsonb), api.conversation_takeover(jsonb), api.conversation_release(jsonb),
  api.conversation_operator_message(jsonb), api.conversation_close(jsonb), api.iara_conversation(jsonb), api.iara_send(jsonb)
  to authenticated;

commit;
