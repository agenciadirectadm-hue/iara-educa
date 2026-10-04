-- IARA Educa — Seed 19 · Conversas de demonstração da agente IARA (WhatsApp SIMULADO — nenhuma mensagem real é enviada)
begin;

create or replace function iara.demo_seed_conversations(p_staff uuid)
returns integer
language plpgsql security definer set search_path = iara, extensions, public
as $fn$
declare
  t record;
  c record;
  v_conv uuid;
  v_ts timestamptz;
  v_msg jsonb;
  v_body text;
  v_n integer := 0;
  v_child text;
  v_unit text;
  v_pos integer;
  v_templates jsonb := $j$[
    {"key":"documentos","case_type":"MATRICULA","state":"CLOSED","intent":"documentos","n":3,
     "summary":"Responsável perguntou sobre documentos; identidade verificada; informado documento pendente (vacinação).",
     "msgs":[["CIDADAO","Oi, quais documentos preciso para a matrícula?"],
             ["IARA","Oi! Eu sou a IARA, assistente virtual da Secretaria Municipal de Educação. Na configuração atual pedimos: certidão de nascimento, CPF da criança e do responsável, comprovante de endereço, cartão SUS e carteira de vacinação. Quer que eu confira o que já recebemos no seu protocolo?"],
             ["CIDADAO","Quero sim"],
             ["IARA","Para consultar dados pessoais preciso confirmar sua identidade. Enviei um código para o telefone cadastrado (na demonstração o envio é simulado)."],
             ["CIDADAO","Código 4821"],
             ["IARA","Obrigada! No protocolo {protocol} já recebemos a certidão e o comprovante de endereço. Falta a carteira de vacinação. Você pode enviar uma foto por aqui ou levar na unidade."],
             ["CIDADAO","Levo amanhã na escola"],
             ["IARA","Combinado. Registrei no protocolo que a carteira será entregue na unidade. Quando a secretaria validar, eu aviso por aqui. 💜"]]},
    {"key":"fila","case_type":"SOLICITACAO_VAGA","state":"CLOSED","intent":"posicao_fila","n":3,
     "summary":"Consulta de posição na fila com vínculo verificado; critérios explicados; sem previsão de data.",
     "msgs":[["CIDADAO","Bom dia! Em que posição está {child} na fila?"],
             ["IARA","Bom dia! Posso ajudar. Antes, preciso confirmar que você é responsável pela criança. Enviei um código para o telefone cadastrado (simulado)."],
             ["CIDADAO","Recebi: 7312"],
             ["IARA","Vínculo confirmado. {child} está na posição {pos} da fila de {grade} da {unit}. Critérios aplicados: ✓ território (até 2 km). A posição pode mudar conforme novas entradas com critérios e ofertas realizadas. Não consigo prever data de atendimento sem fonte oficial."],
             ["CIDADAO","Entendi, obrigada"],
             ["IARA","Por nada! Se surgir uma oferta de vaga, aviso por aqui com unidade, turno e prazo para responder."]]},
    {"key":"atendente","case_type":"ALTERACAO_RESPONSAVEL","state":"HUMAN_PENDING","intent":"falar_atendente","n":3,
     "summary":"Pedido de atendimento humano: possível conflito de guarda. Encaminhado à Central sem ação automática.",
     "msgs":[["CIDADAO","Quero falar com uma pessoa, por favor"],
             ["IARA","Claro! Para eu direcionar ao setor certo: sobre o que é o atendimento?"],
             ["CIDADAO","Sou avó e cuido da {child}, mas a guarda ainda está no nome da mãe"],
             ["IARA","Entendi. Questões de guarda precisam de análise humana. Encaminhei sua conversa à equipe com o histórico completo — você não precisa repetir as informações. Suas mensagens continuam registradas enquanto aguarda."],
             ["SISTEMA","Conversa encaminhada para atendimento humano · motivo: vínculo/guarda a verificar."]]},
    {"key":"ativo","case_type":"TRANSFERENCIA","state":"HUMAN_ACTIVE","intent":"transferencia","n":2,
     "summary":"Transferência por mudança de endereço; servidora assumiu a conversa (automação pausada).",
     "msgs":[["CIDADAO","Mudei de bairro e preciso transferir {child}"],
             ["IARA","Posso ajudar com a transferência. Ela não cancela a matrícula atual até a nova vaga ser confirmada. Para seguir, preciso confirmar sua identidade (código enviado — simulado)."],
             ["CIDADAO","Código 1190"],
             ["IARA","Obrigada. Como o novo endereço muda o território, vou chamar uma servidora da Central de Vagas para analisar as opções com você."],
             ["SISTEMA","Carla Menezes (Central de Vagas) assumiu a conversa. A IARA está pausada."],
             ["OPERADOR","Olá! Aqui é a Carla, da Central de Vagas. Já vi o histórico. Pode me confirmar o novo endereço completo?"],
             ["CIDADAO","Rua das Acácias, 1.250, perto do terminal"]]},
    {"key":"vaga_nova","case_type":"SOLICITACAO_VAGA","state":"FOLLOWUP_PENDING","intent":"procurar_vaga","n":4,
     "summary":"Solicitação de vaga registrada pelo WhatsApp; protocolo gerado; documentos pendentes.",
     "msgs":[["CIDADAO","Preciso de vaga na creche"],
             ["IARA","Vamos lá! Qual é a data de nascimento da criança?"],
             ["CIDADAO","{birth}"],
             ["IARA","Pela data de corte (31/03), a faixa é {grade}. Qual é o seu bairro ou endereço?"],
             ["CIDADAO","{bairro}"],
             ["IARA","Perto de você, a {unit} atende {grade}. Isto é uma consulta de disponibilidade, não uma oferta. Posso registrar a solicitação? Ela gera um protocolo e segue os critérios públicos da fila."],
             ["CIDADAO","Pode registrar"],
             ["IARA","Pronto! Protocolo {protocol} registrado ✅. Próximo passo: enviar certidão de nascimento e comprovante de endereço. A Central de Vagas analisa em até 10 dias e eu aviso cada mudança por aqui."]]},
    {"key":"transporte","case_type":"TRANSPORTE","state":"BOT_ACTIVE","intent":"transporte","n":2,
     "summary":"Dúvida de transporte escolar encaminhada à gerência responsável.",
     "msgs":[["CIDADAO","Meu filho tem direito ao transporte escolar?"],
             ["IARA","O transporte segue critérios de elegibilidade do município, como distância e situação do aluno. Posso registrar um pedido para a Gerência de Transporte Escolar avaliar?"],
             ["CIDADAO","Sim"],
             ["IARA","Registrei no protocolo {protocol} e encaminhei à Gerência de Transporte Escolar. O prazo de análise informado no catálogo é de até 10 dias."]]},
    {"key":"reclamacao","case_type":"RECLAMACAO","state":"HUMAN_PENDING","intent":"reclamacao","n":2,
     "summary":"Reclamação registrada e encaminhada à ouvidoria; aguarda servidor.",
     "msgs":[["CIDADAO","Quero reclamar, ninguém atende o telefone da escola"],
             ["IARA","Sinto muito pela dificuldade. Vou registrar sua manifestação e encaminhar ao setor responsável, com retorno pelo canal que você preferir."],
             ["CIDADAO","Pode ser por aqui mesmo"],
             ["IARA","Registrado no protocolo {protocol}. Encaminhei para a equipe — um servidor vai continuar este atendimento."]]}
  ]$j$::jsonb;
begin
  for t in select * from jsonb_array_elements(v_templates) e(tpl) loop
    for c in
      select sc.id as case_id, sc.protocol_number, sc.guardian_id, sc.student_id, sc.unit_id, sc.opened_at,
             g.full_name as guardian_name, g.whatsapp_phone, s.full_name as student_name, s.birth_date, u.name as unit_name,
             u.neighborhood, gl.name as grade_name, w.position
      from iara.service_cases sc
      join iara.guardians g on g.id = sc.guardian_id
      left join iara.students s on s.id = sc.student_id
      left join iara.education_units u on u.id = sc.unit_id
      left join iara.waiting_list_entries w on w.student_id = sc.student_id and w.status = 'WAITING'
      left join iara.grade_levels gl on gl.id = coalesce(w.grade_level_id, (select c2.grade_level_id from iara.enrollments e join iara.classes c2 on c2.id = e.class_id
                                                                              where e.student_id = sc.student_id and e.status = 'ACTIVE' limit 1), 1)
      where sc.case_type = t.tpl ->> 'case_type'
        and ((t.tpl ->> 'key') <> 'fila' or w.position is not null)
        and not exists (select 1 from iara.conversations cv where cv.guardian_id = sc.guardian_id)
      order by sc.opened_at desc
      limit (t.tpl ->> 'n')::int
    loop
      v_conv := gen_random_uuid();
      v_ts := greatest(c.opened_at, now() - interval '9 days') - interval '20 minutes';
      v_child := split_part(coalesce(c.student_name, 'a criança'), ' ', 1);
      insert into iara.conversations (id, tenant_id, channel, guardian_id, contact_label, contact_phone_masked, state, assigned_user_id, assigned_label,
                                      active_student_id, active_case_id, intent, summary, identity_verified, last_message_at, created_at, is_demo)
      values (v_conv, 1, 'WHATSAPP_SIMULADO', c.guardian_id, c.guardian_name, iara.mask_phone(c.whatsapp_phone), t.tpl ->> 'state',
              case when t.tpl ->> 'state' = 'HUMAN_ACTIVE' then p_staff end,
              case when t.tpl ->> 'state' = 'HUMAN_ACTIVE' then 'Carla Menezes · Central de Vagas (demo)' end,
              c.student_id, c.case_id, t.tpl ->> 'intent', t.tpl ->> 'summary', (t.tpl ->> 'key') <> 'atendente', v_ts, v_ts, true);
      for v_msg in select * from jsonb_array_elements(t.tpl -> 'msgs') loop
        v_ts := v_ts + ((1 + floor(random() * 3)) || ' minutes')::interval;
        v_body := replace(replace(replace(replace(replace(replace(replace(v_msg ->> 1,
                    '{protocol}', c.protocol_number), '{child}', v_child), '{unit}', coalesce(c.unit_name, 'unidade')),
                    '{grade}', coalesce(c.grade_name, 'Creche')), '{pos}', coalesce(c.position::text, '—')),
                    '{bairro}', coalesce(c.neighborhood, 'Jardim Alvorada')), '{birth}', coalesce(to_char(c.birth_date, 'DD/MM/YYYY'), '12/01/2025'));
        insert into iara.messages (conversation_id, direction, sender_type, sender_label, body, status, created_at)
        values (v_conv, case when v_msg ->> 0 = 'CIDADAO' then 'IN' else 'OUT' end, v_msg ->> 0,
                case v_msg ->> 0 when 'CIDADAO' then c.guardian_name when 'IARA' then 'IARA' when 'OPERADOR' then 'Carla Menezes · Central de Vagas (demo)' else 'Sistema' end,
                v_body, 'LIDA', v_ts);
      end loop;
      update iara.conversations set last_message_at = v_ts where id = v_conv;
      if t.tpl ->> 'state' in ('HUMAN_PENDING', 'HUMAN_ACTIVE') then
        insert into iara.handoff_tasks (tenant_id, conversation_id, case_id, reason, sector, status, assigned_user_id, summary, created_at)
        values (1, v_conv, c.case_id, coalesce(t.tpl ->> 'intent', 'atendimento'), 'CENTRAL_VAGAS',
                case when t.tpl ->> 'state' = 'HUMAN_ACTIVE' then 'ASSUMIDA' else 'ABERTA' end,
                case when t.tpl ->> 'state' = 'HUMAN_ACTIVE' then p_staff end, t.tpl ->> 'summary', v_ts - interval '3 minutes');
      end if;
      insert into iara.tool_executions (conversation_id, tool_name, input, output, status, correlation_id, duration_ms, created_at)
      values (v_conv, case t.tpl ->> 'key' when 'fila' then 'get_queue_status' when 'vaga_nova' then 'create_service_case'
                                          when 'documentos' then 'get_document_requirements' else 'handoff_to_team' end,
              jsonb_build_object('protocolo', c.protocol_number), jsonb_build_object('ok', true), 'OK', 'demo-' || substr(v_conv::text, 1, 8),
              80 + floor(random() * 300)::int, v_ts - interval '1 minute');
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_n;
end $fn$;

commit;
