-- =============================================================================
-- IARA Educa · Serviços resolvidos na hora pela IARA
--  · shift_availability: vaga no outro turno da mesma série/unidade (troca de turno é decidida pela unidade,
--    mas a IARA já informa a disponibilidade antes de encaminhar)
--  · saudação da IARA para quem ainda não tem cadastro (família recém-chegada)
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
-- =============================================================================
begin;

create or replace function api.shift_availability(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  e record;
begin
  if iara.my_scope() = 'GUARDIAN' then
    if not exists (select 1 from iara.student_guardians where student_id = v_student and guardian_id = iara.my_guardian()) then
      raise exception 'Criança fora da sua responsabilidade.' using errcode = '42501';
    end if;
  else
    perform iara.require_perm('classes.read');
  end if;
  select en.unit_id, u.name as unit, c.grade_level_id, gl.name as grade, c.shift, c.class_name into e
  from iara.enrollments en join iara.classes c on c.id = en.class_id join iara.education_units u on u.id = en.unit_id
  join iara.grade_levels gl on gl.id = c.grade_level_id
  where en.student_id = v_student and en.status = 'ACTIVE' limit 1;
  if not found then
    return jsonb_build_object('enrolled', false);
  end if;
  return jsonb_build_object('enrolled', true, 'unit_id', e.unit_id, 'unit', e.unit, 'grade', e.grade, 'current_shift', e.shift, 'class', e.class_name,
    'options', coalesce((select jsonb_agg(jsonb_build_object('shift', x.shift, 'offerable', x.n) order by x.shift)
                         from (select c.shift, sum(c.offerable_vacancies_count)::int as n from iara.classes c
                               where c.unit_id = e.unit_id and c.grade_level_id = e.grade_level_id and c.status = 'ATIVA' and c.shift <> e.shift
                               group by c.shift) x), '[]'::jsonb));
end $$;

-- Saudação: com cadastro, menu completo; sem cadastro, a IARA oferece o cadastro pelo próprio WhatsApp
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
    if v_g is not null then
      insert into iara.messages (conversation_id, direction, sender_type, sender_label, body, payload)
      values (v_id, 'OUT', 'IARA', 'IARA',
              'Oi' || coalesce(', ' || v_name, '') || '! 💜 Eu sou a IARA, assistente virtual da Secretaria Municipal de Educação de Maringá. '
              || 'Resolvo por aqui vaga, fila, ofertas, documentos e mudanças na família — e, quando precisar, encaminho para a unidade ou para a SEDUC. Como posso ajudar?',
              jsonb_build_object('quick_replies', jsonb_build_array(
                                   jsonb_build_object('label', 'Procurar vaga', 'action', 'intent:procurar_vaga'),
                                   jsonb_build_object('label', 'Posição na fila', 'action', 'intent:fila'),
                                   jsonb_build_object('label', 'Ofertas de vaga', 'action', 'intent:oferta'),
                                   jsonb_build_object('label', 'Minha família', 'action', 'intent:familia'),
                                   jsonb_build_object('label', 'Acompanhar solicitação', 'action', 'intent:acompanhar'),
                                   jsonb_build_object('label', 'Documentos', 'action', 'intent:documentos'),
                                   jsonb_build_object('label', 'Outros serviços', 'action', 'intent:servicos'),
                                   jsonb_build_object('label', 'Falar com atendente', 'action', 'intent:atendente')),
                                 'notice', 'Assistente virtual · demonstração (nenhuma mensagem real é enviada)'));
    else
      insert into iara.messages (conversation_id, direction, sender_type, sender_label, body, payload)
      values (v_id, 'OUT', 'IARA', 'IARA',
              'Oi! 💜 Eu sou a IARA, assistente virtual da Secretaria Municipal de Educação de Maringá. '
              || 'Ainda não encontrei cadastro para este número. Se vocês acabaram de chegar a Maringá, eu faço o cadastro da família e a inscrição na fila por aqui mesmo, sem precisar ir à Secretaria.',
              jsonb_build_object('quick_replies', jsonb_build_array(
                                   jsonb_build_object('label', 'Acabamos de chegar a Maringá', 'action', 'intent:outra_cidade'),
                                   jsonb_build_object('label', 'Fazer meu cadastro', 'action', 'intent:cadastro'),
                                   jsonb_build_object('label', 'Consultar vagas', 'action', 'intent:procurar_vaga'),
                                   jsonb_build_object('label', 'Encontrar unidade', 'action', 'intent:unidade'),
                                   jsonb_build_object('label', 'Tirar uma dúvida', 'action', 'intent:servicos')),
                                 'notice', 'Assistente virtual · demonstração (nenhuma mensagem real é enviada)'));
    end if;
  end if;
  return iara.conversation_json(v_id);
end $$;

commit;
