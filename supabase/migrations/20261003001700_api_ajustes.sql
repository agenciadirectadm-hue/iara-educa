-- =============================================================================
-- IARA Educa · Ajustes de API para as telas de Ofertas
-- offers_list passa a devolver o checklist completo de documentos da matrícula
-- (mesma forma usada em dashboard_unidade.pending_enrollments).
-- =============================================================================

create or replace function api.offers_list(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security invoker set search_path = iara, public
as $$
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', o.id, 'offer_id', o.id, 'status', o.status, 'student_id', s.id, 'student', s.full_name, 'avatar_seed', s.avatar_seed,
      'unit_id', u.id, 'unit', u.short_name, 'class_id', c.id, 'class', c.class_name, 'shift', c.shift,
      'offered_at', o.offered_at, 'expires_at', o.expires_at, 'accepted_at', o.accepted_at, 'case_id', o.case_id,
      'hours_left', round(extract(epoch from (o.expires_at - now())) / 3600.0, 1),
      'documents', (select coalesce(jsonb_agg(jsonb_build_object('type', d, 'status', coalesce((select x.status from iara.documents x
                                                                   where x.student_id = o.student_id and x.doc_type = d
                                                                   order by x.created_at desc limit 1), 'NAO_ENVIADO'))), '[]'::jsonb)
                    from unnest((select required_documents from iara.service_catalog where code = 'MATRICULA')) d),
      'missing_documents', (select coalesce(jsonb_agg(d), '[]'::jsonb)
                            from unnest((select required_documents from iara.service_catalog where code = 'MATRICULA')) d
                            where not exists (select 1 from iara.documents x where x.student_id = o.student_id and x.doc_type = d and x.status = 'VALIDADO')))
      order by case o.status when 'ACCEPTED' then 0 else 1 end, o.expires_at), '[]'::jsonb),
    'generated_at', now())
  from iara.vacancy_offers o
  join iara.students s on s.id = o.student_id
  join iara.education_units u on u.id = o.unit_id
  join iara.classes c on c.id = o.class_id
  where o.status = any (coalesce((select array_agg(x) from jsonb_array_elements_text(p -> 'status') x), array['OFFERED', 'ACCEPTED']))
    and ((p ->> 'unit_id') is null or o.unit_id = (p ->> 'unit_id')::int)
$$;

-- Saudação da IARA com botões acionáveis (inclui Ofertas de vaga)
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
