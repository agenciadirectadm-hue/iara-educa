-- IARA Educa — 061 · Busca ativa: demonstração, rotina automática e limpeza
-- Demonstração: os últimos 10 dias letivos da frequência fictícia viram ausências com contatos, respostas, níveis, tarefas, casos e
-- encaminhamentos; órgãos destinatários fictícios (marcados “demonstração”) já verificados; comunicações legais pelo limite de 30%.
-- Rotina: o housekeeping do gateway processa os níveis e os agendados a cada 10 minutos e o limite legal uma vez por dia.
begin;

create or replace function iara.demo_gerar_busca_ativa() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_t0 timestamptz := now();  -- início da transação: o que for criado aqui tem created_at >= v_t0
  v_ate date := iara.hoje_local() - 1;
  v_de date;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.encaminhamentos where is_demo;
  delete from iara.busca_ativa_casos where is_demo;
  delete from iara.frequencia_tarefas where is_demo;
  delete from iara.frequencia_contatos where is_demo;
  delete from iara.frequencia_ausencias where is_demo;
  delete from iara.frequencia_afastamentos where is_demo;
  delete from iara.orgaos_destinatarios where is_demo;
  select min(d) into v_de from (select distinct r.data d from iara.frequencia_registros r where r.is_demo and r.data <= v_ate order by r.data desc limit 10) z;

  -- órgãos fictícios por região (protocolo eletrônico de demonstração), já verificados
  insert into iara.orgaos_destinatarios (nome, tipo, competencia, territorio_ids, canal, endereco_canal, verificado, verificado_por_label, verificado_em, is_demo)
  select 'Conselho Tutelar — ' || t.name || ' (demonstração)', 'CONSELHO_TUTELAR', 'Proteção de crianças e adolescentes da região', array[t.id], 'PROTOCOLO_ELETRONICO',
         'Protocolo eletrônico (demonstração)', true, 'SEDUC (demonstração)', now() - interval '30 days', true
  from iara.territories t where t.kind = 'MACRORREGIAO';
  insert into iara.orgaos_destinatarios (nome, tipo, competencia, canal, endereco_canal, verificado, verificado_por_label, verificado_em, is_demo) values
    ('CRAS de referência (demonstração)', 'CRAS', 'Assistência social básica: acompanhamento familiar, benefícios', 'PROTOCOLO_ELETRONICO', 'Protocolo eletrônico (demonstração)', true, 'SEDUC (demonstração)', now() - interval '30 days', true),
    ('CREAS (demonstração)', 'CREAS', 'Proteção social especial: violação de direitos', 'PROTOCOLO_ELETRONICO', 'Protocolo eletrônico (demonstração)', true, 'SEDUC (demonstração)', now() - interval '30 days', true),
    ('Unidade Básica de Saúde de referência (demonstração)', 'SAUDE', 'Atenção básica à saúde da criança', 'PROTOCOLO_ELETRONICO', 'Protocolo eletrônico (demonstração)', true, 'SEDUC (demonstração)', now() - interval '30 days', true),
    ('Gerência de Transporte Escolar (demonstração)', 'TRANSPORTE_ESCOLAR', 'Pedido e ajuste de rota', 'INTEGRACAO', 'Módulo de transporte do IARA', true, 'SEDUC (demonstração)', now() - interval '30 days', true),
    ('Serviço de convivência (cadastro pendente de verificação)', 'ASSISTENCIA_SOCIAL', 'Contraturno e convivência', 'EMAIL_INSTITUCIONAL', null, false, null, null, true);

  -- ausências dos últimos 10 dias letivos (situação e motivo pela “família” fictícia)
  insert into iara.frequencia_ausencias (student_id, class_id, unit_id, etapa, data, situacao, motivo, motivo_texto, respondido_em, respondido_canal, nivel, created_at, atualizado_em, is_demo)
  select f.student_id, r.class_id, c.unit_id, iara.etapa_freq(gl.code), r.data,
         case when f.tipo = 'FALTA_JUSTIFICADA' then 'JUSTIFICATIVA_ACEITA' when h.h < 58 then 'MOTIVO_INFORMADO' when h.h < 64 then 'JUSTIFICATIVA_EM_ANALISE'
              when h.h < 72 then 'INJUSTIFICADA' when h.h < 74 then 'AFASTAMENTO' else 'AGUARDANDO_ESCLARECIMENTO' end,
         case when f.tipo = 'FALTA_JUSTIFICADA' then coalesce(case when f.justificativa ilike 'Transporte%' then 'TRANSPORTE' end, 'SAUDE')
              when h.h < 58 then (array['SAUDE', 'SAUDE', 'SAUDE', 'SAUDE', 'SAUDE', 'SAUDE', 'SAUDE', 'SAUDE', 'SAUDE', 'CONSULTA', 'CONSULTA', 'CONSULTA',
                                        'TRANSPORTE', 'DIFICULDADE_FAMILIAR', 'DIFICULDADE_FAMILIAR', 'RECUSA', 'OUTRO', 'OUTRO', 'OUTRO', 'ESTA_NA_ESCOLA'])[1 + h.h % 20] end,
         case when h.h < 58 and h.h % 20 >= 16 and h.h % 20 <= 18 then (array['Viagem de família', 'Choveu muito e não conseguimos ir', 'Problema com a documentação'])[1 + h.h % 3] end,
         case when h.h < 64 then r.data + interval '14 hours' + make_interval(mins => h.h * 7 % 300) end,
         case when h.h < 64 then (array['WHATSAPP', 'WHATSAPP', 'PORTAL'])[1 + h.h % 3] end,
         case when h.h >= 74 and r.data <= v_ate - 2 then 3 when h.h >= 74 and r.data <= v_ate - 1 then 2 else 1 end,
         r.data + interval '10 hours', r.data + interval '15 hours', true
  from iara.frequencia_registros r join iara.frequencia_faltas f on f.registro_id = r.id
  join iara.classes c on c.id = r.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
  cross join lateral (select abs(hashtext(f.student_id::text || r.data::text || 'ba')) % 100 h) h
  where r.is_demo and r.data between v_de and v_ate
  on conflict (student_id, data) do nothing;
  -- afastamentos acompanhados (os poucos marcados acima)
  insert into iara.frequencia_afastamentos (student_id, inicio, fim, motivo, acompanhar_em, registrado_por_label, is_demo)
  select a.student_id, a.data, a.data + 4, 'Afastamento acompanhado pela escola (motivo registrado sem diagnóstico)', a.data + 5, 'Secretaria da unidade (demonstração)', true
  from iara.frequencia_ausencias a where a.is_demo and a.situacao = 'AFASTAMENTO';

  -- primeiro contato: um por responsável e dia
  insert into iara.frequencia_contatos (guardian_id, student_ids, ausencia_ids, unit_id, data_ref, nivel, canal, texto, status, agendada_para, enviada_em, falha_motivo, chave, created_at, is_demo)
  select z.g, z.alunos, z.ids, z.unit_id, z.data, '1', 'WHATSAPP',
         iara.modelo_msg('NIVEL_1', jsonb_build_object('nome_responsavel', split_part(gu.full_name, ' ', 1), 'nome_aluno', z.nomes, 'data', to_char(z.data, 'DD/MM'), 'unidade', z.unidade)),
         case when z.falha then 'FALHA' when z.respondeu then 'RESPONDIDA' else 'SIMULADA' end,
         z.data + interval '10 hours 20 minutes', z.data + interval '10 hours 21 minutes', case when z.falha then 'Número sem WhatsApp (demonstração)' end,
         'n1:' || z.g || ':' || z.data, z.data + interval '10 hours 20 minutes', true
  from (select iara.responsavel_contato(a.student_id) g, a.data, array_agg(a.student_id) alunos, array_agg(a.id) ids, min(a.unit_id) unit_id,
               string_agg(split_part(s.full_name, ' ', 1), ' e ') nomes, min(u.short_name) unidade, bool_or(a.respondido_em is not null) respondeu,
               abs(hashtext(min(a.id::text))) % 100 < 4 and not bool_or(a.respondido_em is not null) falha
        from iara.frequencia_ausencias a join iara.students s on s.id = a.student_id join iara.education_units u on u.id = a.unit_id
        where a.is_demo and a.situacao not in ('JUSTIFICATIVA_ACEITA', 'AFASTAMENTO')
        group by 1, 2) z join iara.guardians gu on gu.id = z.g
  where z.g is not null
  on conflict (chave) do nothing;
  -- lembretes (nível 2) e atendimento (nível 3) para quem não respondeu
  insert into iara.frequencia_contatos (guardian_id, student_ids, ausencia_ids, unit_id, data_ref, nivel, canal, texto, status, agendada_para, enviada_em, chave, created_at, is_demo)
  select iara.responsavel_contato(a.student_id), array[a.student_id], array[a.id], a.unit_id, a.data, n.nivel, 'WHATSAPP',
         iara.modelo_msg('NIVEL_' || n.nivel, jsonb_build_object('nome_responsavel', split_part(gu.full_name, ' ', 1), 'nome_aluno', split_part(s.full_name, ' ', 1),
           'data', to_char(a.data, 'DD/MM'), 'unidade', u.short_name)), 'SIMULADA',
         a.data + make_interval(days => n.dias, hours => 9), a.data + make_interval(days => n.dias, hours => 9), 'n' || n.nivel || 'm:' || a.student_id || ':' || a.data,
         a.data + make_interval(days => n.dias, hours => 9), true
  from iara.frequencia_ausencias a join iara.students s on s.id = a.student_id join iara.education_units u on u.id = a.unit_id
  join iara.guardians gu on gu.id = iara.responsavel_contato(a.student_id)
  cross join (values ('2', 1), ('3', 2)) n(nivel, dias)
  where a.is_demo and a.situacao = 'AGUARDANDO_ESCLARECIMENTO' and a.nivel >= n.nivel::int
  on conflict (chave) do nothing;

  -- tarefas: ligar (nível 2), reunião (nível 3), conferir telefone (falha), apoio (motivos), conferir presença
  insert into iara.frequencia_tarefas (student_id, ausencia_id, unit_id, tipo, prioridade, destino, descricao, prazo, situacao, sucesso, resultado, concluida_por_label, concluida_em, chave, created_at, is_demo)
  select a.student_id, a.id, a.unit_id, case when a.nivel >= 3 then 'REUNIAO' else 'LIGAR' end, case when a.nivel >= 3 then 'ALTA' else 'NORMAL' end,
         case when a.nivel >= 3 then 'EQUIPE_PEDAGOGICA' else 'SECRETARIA_UNIDADE' end,
         case when a.nivel >= 3 then 'Sem resposta da família ou ausências seguidas: telefonar, usar o contato alternativo ou marcar reunião (com a direção ciente).'
              else 'Família sem resposta ao primeiro contato: ligar para o responsável.' end,
         a.data + 2, case when abs(hashtext(a.id::text || 't')) % 3 = 0 then 'CONCLUIDA' else 'ABERTA' end,
         case when abs(hashtext(a.id::text || 't')) % 3 = 0 then abs(hashtext(a.id::text)) % 2 = 0 end,
         case when abs(hashtext(a.id::text || 't')) % 3 = 0 then (array['Ligação atendida: a criança estava doente e volta amanhã.', 'Telefone não atende; deixado recado com a avó.'])[1 + abs(hashtext(a.id::text)) % 2] end,
         case when abs(hashtext(a.id::text || 't')) % 3 = 0 then 'Secretaria da unidade (demonstração)' end,
         case when abs(hashtext(a.id::text || 't')) % 3 = 0 then least(a.data + interval '1 day 15 hours', now() - interval '1 hour') end,
         'n' || case when a.nivel >= 3 then 3 else 2 end || ':' || a.student_id || ':' || a.data, a.data + interval '1 day', true
  from iara.frequencia_ausencias a where a.is_demo and a.situacao = 'AGUARDANDO_ESCLARECIMENTO' and a.nivel >= 2
  on conflict (chave) do nothing;
  insert into iara.frequencia_tarefas (student_id, unit_id, tipo, prioridade, destino, descricao, prazo, chave, created_at, is_demo)
  select k.student_ids[1], k.unit_id, 'CONFERIR_TELEFONE', 'ALTA', 'SECRETARIA_UNIDADE', 'A mensagem não foi entregue (número sem WhatsApp). Conferir o telefone no cadastro e usar o contato alternativo autorizado.',
         k.data_ref + 1, 'tel:' || k.id, k.created_at, true
  from iara.frequencia_contatos k where k.is_demo and k.status = 'FALHA'
  on conflict (chave) do nothing;
  insert into iara.frequencia_tarefas (student_id, ausencia_id, unit_id, tipo, prioridade, destino, descricao, prazo, situacao, resultado, concluida_por_label, concluida_em, chave, created_at, is_demo)
  select a.student_id, a.id, a.unit_id, case when a.motivo = 'ESTA_NA_ESCOLA' then 'CONFERIR_PRESENCA' else 'APOIO_SETOR' end, 'ALTA',
         case a.motivo when 'TRANSPORTE' then 'TRANSPORTE' when 'ESTA_NA_ESCOLA' then 'SECRETARIA_UNIDADE' else 'EQUIPE_PEDAGOGICA' end,
         case a.motivo when 'TRANSPORTE' then 'A família informou problema de transporte: verificar a rota ou o pedido de transporte escolar.'
                       when 'ESTA_NA_ESCOLA' then 'A família diz que a criança estava na escola: conferir a chamada com o professor.'
                       when 'RECUSA' then 'A família relata recusa ou dificuldade para frequentar a escola: acolher e planejar o apoio (sem presumir negligência).'
                       else 'A família relata dificuldade: acolher e avaliar apoio da rede (assistência social), sem presumir negligência.' end,
         a.data + 2, case when a.data <= v_ate - 4 then 'CONCLUIDA' else 'ABERTA' end,
         case when a.data <= v_ate - 4 then 'Família acolhida; combinado acompanhamento quinzenal.' end,
         case when a.data <= v_ate - 4 then 'Equipe pedagógica (demonstração)' end, case when a.data <= v_ate - 4 then a.data + interval '3 days' end,
         'apoio:' || a.id, a.data + interval '15 hours', true
  from iara.frequencia_ausencias a where a.is_demo and a.motivo in ('TRANSPORTE', 'DIFICULDADE_FAMILIAR', 'RECUSA', 'ESTA_NA_ESCOLA') and a.situacao = 'MOTIVO_INFORMADO'
  on conflict (chave) do nothing;

  -- casos de busca ativa: 3+ ausências sem esclarecimento ou injustificadas na janela; o caso abre na 3ª ausência e só tem
  -- andamento (contato, reunião, retorno) que já caberia no tempo decorrido
  insert into iara.busca_ativa_casos (student_id, unit_id, etapa, origem, motivo_abertura, situacao, responsavel_label, acompanhar_em, aberto_em, is_demo)
  select z.student_id, z.unit_id, z.etapa, case when z.n >= 4 then 'CONTATOS_SEM_SUCESSO' else 'PERSISTENCIA' end,
         format('%s ausências sem esclarecimento nos últimos dias letivos; contatos sem sucesso.', z.n),
         case when z.ab > now() - interval '1 day' then 'ABERTO'
              when z.ab > now() - interval '5 days' then (array['ABERTO', 'EM_ACOMPANHAMENTO', 'EM_ACOMPANHAMENTO', 'EM_ACOMPANHAMENTO'])[1 + abs(hashtext(z.student_id::text)) % 4]
              else (array['ABERTO', 'EM_ACOMPANHAMENTO', 'EM_ACOMPANHAMENTO', 'RETORNOU'])[1 + abs(hashtext(z.student_id::text)) % 4] end,
         'Coordenação pedagógica (demonstração)', v_ate + 3, z.ab, true
  from (select student_id, min(unit_id) unit_id, min(etapa) etapa, count(*) n, (array_agg(data order by data))[3] + interval '16 hours' ab
        from iara.frequencia_ausencias
        where is_demo and situacao in ('AGUARDANDO_ESCLARECIMENTO', 'INJUSTIFICADA') group by 1 having count(*) >= 3) z
  on conflict do nothing;
  insert into iara.busca_ativa_eventos (caso_id, tipo, texto, autor_label, created_at, is_demo)
  select k.id, e.tipo, e.texto, e.autor, k.aberto_em + e.dt, true
  from iara.busca_ativa_casos k
  cross join lateral (values ('ABERTURA', 'Caso aberto pela regra de persistência (parâmetros vigentes).', 'IARA (regra automática)', interval '0'),
                             ('CONTATO_TELEFONE', 'Ligação para o responsável: sem resposta; tentado o contato alternativo.', 'Secretaria da unidade (demonstração)', interval '1 day'),
                             ('REUNIAO', 'Reunião com a família: dificuldade de rotina pela manhã; combinado acompanhamento semanal.', 'Coordenação pedagógica (demonstração)', interval '3 days')) e(tipo, texto, autor, dt)
  where k.is_demo and (e.tipo = 'ABERTURA' or k.situacao <> 'ABERTO') and k.aberto_em + e.dt <= now();
  insert into iara.busca_ativa_eventos (caso_id, tipo, texto, autor_label, created_at, is_demo)
  select k.id, 'RETORNO', 'O aluno voltou a frequentar; o caso segue em acompanhamento até a equipe encerrar.', 'Coordenação pedagógica (demonstração)', k.aberto_em + interval '5 days', true
  from iara.busca_ativa_casos k where k.is_demo and k.situacao = 'RETORNOU';
  -- alguns encaminhamentos à rede de apoio
  insert into iara.encaminhamentos (caso_id, student_id, unit_id, tipo, orgao_id, servico, necessidade, fundamento, obrigatorio, conteudo, situacao, comunicar_familia, criado_por_label,
                                    created_at, aprovado_por_label, aprovado_em, enviado_em, enviado_canal, protocolo, is_demo)
  select k.id, k.student_id, k.unit_id, 'REDE_APOIO', (select id from iara.orgaos_destinatarios where is_demo and tipo = 'CRAS' limit 1), 'CRAS de referência',
         'acompanhamento familiar e acesso a benefícios', 'Necessidade de apoio social identificada no contato com a família', false,
         iara.ba_expediente(k.student_id, k.id, 'Necessidade de apoio social identificada no contato com a família'),
         case when abs(hashtext(k.id::text)) % 3 = 0 then 'AGUARDANDO_APROVACAO' else 'ENVIADO' end, true, 'Coordenação pedagógica (demonstração)',
         k.aberto_em + interval '4 days', case when abs(hashtext(k.id::text)) % 3 <> 0 then 'Direção (demonstração)' end,
         case when abs(hashtext(k.id::text)) % 3 <> 0 then k.aberto_em + interval '4 days 3 hours' end,
         case when abs(hashtext(k.id::text)) % 3 <> 0 then k.aberto_em + interval '4 days 4 hours' end,
         case when abs(hashtext(k.id::text)) % 3 <> 0 then 'PROTOCOLO_ELETRONICO' end,
         case when abs(hashtext(k.id::text)) % 3 <> 0 then 'DEMO-' || (abs(hashtext(k.id::text)) % 90000 + 10000) end, true
  from iara.busca_ativa_casos k where k.is_demo and abs(hashtext(k.id::text || 'rede')) % 100 < 30 and k.aberto_em + interval '4 days 4 hours' <= now();

  -- casos urgentes (relato com possível risco) para mostrar o fluxo prioritário — nunca com a família da demonstração
  insert into iara.busca_ativa_casos (student_id, unit_id, etapa, origem, motivo_abertura, urgente, situacao, acompanhar_em, aberto_em, is_demo)
  select a.student_id, a.unit_id, a.etapa, 'RISCO', 'Relato da família com possível indício de risco — avaliação humana imediata.', true, 'ABERTO', iara.hoje_local(), a.data + interval '15 hours', true
  from (select distinct on (a.unit_id) a.* from iara.frequencia_ausencias a
        where a.is_demo and a.situacao = 'MOTIVO_INFORMADO' and a.motivo = 'DIFICULDADE_FAMILIAR'
          and a.student_id is distinct from nullif(iara.setting('demo_student_ana'), '')::uuid
          and not exists (select 1 from iara.busca_ativa_casos k where k.student_id = a.student_id and k.situacao <> 'ENCERRADO')
        order by a.unit_id, a.data desc) a
  where abs(hashtext(a.unit_id::text || 'risco')) % 100 < 4;
  insert into iara.frequencia_tarefas (student_id, caso_id, unit_id, tipo, prioridade, destino, descricao, prazo, obrigatoria, chave, created_at, is_demo)
  select k.student_id, k.id, k.unit_id, 'AVALIAR_RISCO', 'URGENTE', 'DIRECAO',
         'Relato com possível indício de risco: avaliação imediata pela equipe autorizada e, se for o caso, comunicação ao Conselho Tutelar.', iara.hoje_local(), true, 'risco:' || k.id, k.aberto_em, true
  from iara.busca_ativa_casos k where k.is_demo and k.origem = 'RISCO';

  -- comunicações legais (30% do limite de faltas): a maioria já enviada; parte aguardando aprovação ou envio
  perform iara.busca_ativa_limite_legal(null);
  update iara.encaminhamentos set is_demo = true where created_at >= v_t0 and not is_demo;
  update iara.frequencia_tarefas set is_demo = true where created_at >= v_t0 and not is_demo;
  update iara.encaminhamentos e set situacao = x.sit, aprovado_por_label = case when x.sit <> 'AGUARDANDO_APROVACAO' then 'Direção (demonstração)' end,
         aprovado_em = case when x.sit <> 'AGUARDANDO_APROVACAO' then now() - interval '6 days' end,
         enviado_em = case when x.sit in ('ENVIADO', 'RECEBIDO') then now() - interval '5 days' end,
         enviado_canal = case when x.sit in ('ENVIADO', 'RECEBIDO') then 'PROTOCOLO_ELETRONICO' end,
         protocolo = case when x.sit in ('ENVIADO', 'RECEBIDO') then 'CT-DEMO-' || (abs(hashtext(e.id::text)) % 90000 + 10000) end,
         recebido_em = case when x.sit = 'RECEBIDO' then now() - interval '4 days' end, created_at = now() - interval '8 days'
  from (select id, case when abs(hashtext(id::text)) % 100 < 45 then 'RECEBIDO' when abs(hashtext(id::text)) % 100 < 75 then 'ENVIADO'
                        when abs(hashtext(id::text)) % 100 < 90 then 'APROVADO' else 'AGUARDANDO_APROVACAO' end sit
        from iara.encaminhamentos where is_demo and tipo = 'CONSELHO_TUTELAR') x
  where e.id = x.id;
  update iara.frequencia_tarefas t set situacao = 'CONCLUIDA', sucesso = true, resultado = 'Expediente enviado — protocolo ' || e.protocolo, concluida_por_label = 'Direção (demonstração)',
         concluida_em = e.enviado_em
  from iara.encaminhamentos e where t.is_demo and t.tipo = 'NOTIFICAR_CT' and t.chave = 'ct:' || e.id and e.situacao in ('ENVIADO', 'RECEBIDO');
  update iara.frequencia_tarefas t set created_at = e.created_at from iara.encaminhamentos e where t.is_demo and t.chave = 'ct:' || e.id;
  perform set_config('iara.skip_audit', 'off', true);
  update iara.tenants set settings = settings || jsonb_build_object('ba_legal_dia', iara.hoje_local()::text) where id = 1;
  return jsonb_build_object('ausencias', (select count(*) from iara.frequencia_ausencias where is_demo), 'contatos', (select count(*) from iara.frequencia_contatos where is_demo),
    'tarefas', (select count(*) from iara.frequencia_tarefas where is_demo), 'casos', (select count(*) from iara.busca_ativa_casos where is_demo),
    'encaminhamentos', (select count(*) from iara.encaminhamentos where is_demo), 'ct', (select count(*) from iara.encaminhamentos where is_demo and tipo = 'CONSELHO_TUTELAR'));
end $$;

create or replace function iara.demo_purge_busca_ativa(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v jsonb := '{}'::jsonb;
  n integer;
  d timestamptz := coalesce(p_desde, '-infinity'::timestamptz);
  x record;
begin
  if not iara.demo_mode() then raise exception 'Limpeza disponível apenas no modo demonstração.' using errcode = '42501'; end if;
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.encaminhamentos where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('encaminhamentos', n);
  delete from iara.busca_ativa_eventos where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('eventos', n);
  delete from iara.busca_ativa_casos where not is_demo and aberto_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('casos', n);
  delete from iara.frequencia_tarefas where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('tarefas', n);
  delete from iara.frequencia_contatos where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('contatos', n);
  delete from iara.frequencia_ausencias where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('ausencias', n);
  delete from iara.frequencia_afastamentos where not is_demo and created_at >= d;
  delete from iara.notifications where created_at >= d and event_type like 'FREQUENCIA\_%';
  -- regras alteradas ao vivo voltam à versão anterior
  for x in select * from iara.frequencia_parametros where alterado_em >= d and versao > 1 loop
    delete from iara.frequencia_parametros where id = x.id;
    update iara.frequencia_parametros set ativo = true, vigencia_fim = null
    where codigo = x.codigo and rede = x.rede and etapa = x.etapa and versao = (select max(versao) from iara.frequencia_parametros where codigo = x.codigo and rede = x.rede and etapa = x.etapa);
  end loop;
  -- o que a equipe mexeu ao vivo em dados de demonstração é recriado
  if exists (select 1 from iara.frequencia_tarefas where is_demo and concluida_em >= d and concluida_em > created_at + interval '1 minute' and concluida_por_label not like '%demonstração%')
     or exists (select 1 from iara.frequencia_ausencias where is_demo and (respondido_em >= d or atualizado_em >= d) and atualizado_em > created_at + interval '1 day')
     or exists (select 1 from iara.encaminhamentos where is_demo and (aprovado_em >= d or enviado_em >= d) and coalesce(aprovado_por_label, '') not like '%demonstração%') then
    v := v || jsonb_build_object('recriado', iara.demo_gerar_busca_ativa());
  end if;
  perform set_config('iara.skip_audit', 'off', true);
  return v;
end $$;

create or replace function iara.demo_rotina_busca_ativa() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ult timestamptz := nullif(iara.setting('ba_processado_em'), '')::timestamptz;
  v jsonb := null;
begin
  if v_ult is null or v_ult < now() - interval '10 minutes' then
    if not pg_try_advisory_xact_lock(hashtext('iara.busca_ativa_processar')) then return null; end if;
    v := jsonb_build_object('processo', iara.busca_ativa_processar(null, null));
    if coalesce(iara.setting('ba_legal_dia'), '') <> iara.hoje_local()::text then
      v := v || jsonb_build_object('limite_legal', iara.busca_ativa_limite_legal(null));
      update iara.tenants set settings = settings || jsonb_build_object('ba_legal_dia', iara.hoje_local()::text) where id = 1;
    end if;
    update iara.tenants set settings = settings || jsonb_build_object('ba_processado_em', now()::text) where id = 1;
  end if;
  return v;
end $$;

create or replace function iara.housekeeping() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_shift interval;
  v_expired integer;
  v_rotina jsonb;
  v_rotina2 jsonb;
  v_rotina3 jsonb;
  v_ba jsonb;
begin
  v_shift := iara.demo_timeshift();
  v_expired := iara.expire_due_offers();
  begin
    v_rotina := iara.demo_rotina_diaria();
  exception when others then
    -- a rotina da demonstração nunca derruba o housekeeping
    v_rotina := jsonb_build_object('erro', sqlerrm);
  end;
  if iara.demo_mode() then
    begin
      v_rotina2 := iara.demo_rotina_sprint2();
    exception when others then
      v_rotina2 := jsonb_build_object('erro', sqlerrm);
    end;
    begin
      v_rotina3 := iara.demo_rotina_sprint3();
    exception when others then
      v_rotina3 := jsonb_build_object('erro', sqlerrm);
    end;
  end if;
  -- busca ativa: níveis, agendados e limite legal (vale também na produção)
  begin
    v_ba := iara.demo_rotina_busca_ativa();
  exception when others then
    v_ba := jsonb_build_object('erro', sqlerrm);
  end;
  return jsonb_build_object('timeshift', v_shift::text, 'expired_offers', v_expired, 'rotina', v_rotina, 'rotina_sprint2', v_rotina2, 'rotina_sprint3', v_rotina3, 'busca_ativa', v_ba);
end $$;

create or replace function api.demo_apresentacao_limpar(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r jsonb;
begin
  perform iara.require_perm('demo.manage');
  perform iara.exigir_demo();
  r := iara.demo_purge_session_data(null, null);
  r := r || jsonb_build_object('vida_escolar', iara.demo_purge_sprint1(null), 'pedagogico', iara.demo_purge_sprint2(null),
                               'transporte_almoxarifado', iara.demo_purge_sprint3(null), 'busca_ativa', iara.demo_purge_busca_ativa(null),
                               'arquivos', iara.demo_limpar_arquivos_vivos(null));
  return jsonb_build_object('ok', true, 'resultado', r, 'situacao', api.demo_apresentacao_situacao('{}'::jsonb));
end $$;

revoke all on function iara.demo_gerar_busca_ativa(), iara.demo_purge_busca_ativa(timestamptz), iara.demo_rotina_busca_ativa() from public;

commit;
