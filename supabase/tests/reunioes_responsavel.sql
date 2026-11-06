-- Registro de reunião com o responsável: quem vê, prontuário, resposta da família, régua de avisos D a D+3, ocorrência ao Secretário, envio aos órgãos e proteção da criança.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/reunioes_responsavel.sql
create or replace function pg_temp.as_call(p_hash text, p_fn text, p_args jsonb) returns jsonb language plpgsql as $f$
declare
  v_uid uuid := (select user_id from iara.app_sessions where token_hash = p_hash);
  v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute format('select api.%I($1)', p_fn) into v using p_args;
  execute 'reset role';
  return v;
exception when others then
  execute 'reset role';
  return jsonb_build_object('erro', sqlerrm, 'codigo', sqlstate);
end $f$;

do $$
declare
  v_out jsonb := '[]';
  r jsonb; r2 jsonb;
  v_unit integer := (iara.setting('demo_unit_maria'))::int;
  v_maria uuid := (iara.setting('demo_guardian_maria'))::uuid;
  v_ana uuid;
  v_outro uuid;
  v_outro_g uuid;
  v_id uuid;
  v_ana_rec uuid;
  v_nid uuid;
  v_texto text;
  v_turmas uuid[];
  v_fora uuid;
  v_fora_g uuid;
  v_fora_id uuid;
begin
  perform iara.session_create('CIDADAO', null, 're-fam', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_unit, 're-dir', 'teste');
  perform iara.session_create('SECRETARIA_ESCOLAR', v_unit, 're-sec', 'teste');
  perform iara.session_create('SECRETARIO', null, 're-seduc', 'teste');
  perform iara.session_create('SUPERINTENDENCIA', null, 're-sup', 'teste');
  perform iara.session_create('PREFEITO', null, 're-pref', 'teste');
  perform iara.session_create('GERENCIA_EI', null, 're-ger', 'teste');
  perform iara.session_create('CONTROLE_EXTERNO', null, 're-ext', 'teste');
  perform iara.session_create('NUTRICAO', null, 're-nut', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', (select id from iara.education_units where id <> v_unit order by id limit 1), 're-dir2', 'teste');

  select student_id into v_ana from iara.reunioes_responsavel where guardian_id = v_maria and is_demo limit 1;
  select id into v_ana_rec from iara.reunioes_responsavel where guardian_id = v_maria and is_demo limit 1;
  select e.student_id, sg.guardian_id into v_outro, v_outro_g from iara.enrollments e join iara.student_guardians sg on sg.student_id = e.student_id and sg.is_primary and sg.end_date is null
  where e.unit_id = v_unit and e.status = 'ACTIVE' and sg.guardian_id <> v_maria order by e.student_id limit 1;

  -- 1. Registro e visão de cada perfil
  r := pg_temp.as_call('re-dir', 'reuniao_registrar', jsonb_build_object('student_id', v_ana, 'guardian_id', v_maria, 'tema', 'INFREQUENCIA', 'envia_responsavel', true,
    'resumo', 'Reunião de teste sobre as faltas da criança no mês.', 'solucoes', 'Plano de retorno combinado.', 'posicao_escola', 'A escola reforça a presença.', 'posicao_responsavel', 'A família concorda.'));
  v_id := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'R1. Direção registra; aviso de D sai na hora; situação aguardando', 'ok',
    v_id is not null and r ->> 'situacao' = 'AGUARDANDO' and (r ->> 'ultimo_aviso')::int = 0
    and exists (select 1 from iara.reuniao_eventos e where e.reuniao_id = v_id and e.tipo = 'AVISO' and e.dia = 0)
    and exists (select 1 from iara.notifications n where n.guardian_id = v_maria and n.event_type = 'REUNIAO_AVISO' and n.created_at >= now() - interval '1 minute'), 'r', r);

  v_out := v_out || jsonb_build_object('passo', 'R2. Encaminhado aos 5 destinos', 'ok', (select count(*) from iara.reuniao_destinos where reuniao_id = v_id) = 5);

  r := pg_temp.as_call('re-sec', 'reuniao_detalhe', jsonb_build_object('id', v_id));
  r2 := pg_temp.as_call('re-seduc', 'reuniao_detalhe', jsonb_build_object('id', v_id));
  v_out := v_out || jsonb_build_object('passo', 'R3. Secretaria escolar e secretário leem, e a leitura fica anotada', 'ok',
    r ->> 'resumo' is not null and r2 ->> 'resumo' is not null
    and (select count(*) from iara.reuniao_destinos where reuniao_id = v_id and lido_em is not null) >= 3);
  r := pg_temp.as_call('re-sup', 'reuniao_detalhe', jsonb_build_object('id', v_id));
  v_out := v_out || jsonb_build_object('passo', 'R4. Superintendência lê', 'ok', r ->> 'resumo' is not null);

  r := pg_temp.as_call('re-pref', 'reuniao_detalhe', jsonb_build_object('id', v_id));
  r2 := pg_temp.as_call('re-nut', 'reunioes_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', 'R5. Prefeito lê; nutrição não acessa', 'ok', r ->> 'resumo' is not null and r2 ? 'erro', 'r', r, 'r2', r2);
  r := pg_temp.as_call('re-ger', 'reuniao_detalhe', jsonb_build_object('id', v_id));
  v_out := v_out || jsonb_build_object('passo', 'R5b. Gerência lê', 'ok', r ->> 'resumo' is not null, 'r', r);
  r := pg_temp.as_call('re-dir', 'reunioes_lista', jsonb_build_object('guardian_id', v_maria));
  r2 := pg_temp.as_call('re-nut', 'reunioes_lista', jsonb_build_object('guardian_id', v_maria));
  v_out := v_out || jsonb_build_object('passo', 'R5c. Prontuário do responsável: a lista filtra por ele', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'itens') x where (x ->> 'id')::uuid = v_id)
    and not exists (select 1 from jsonb_array_elements(r -> 'itens') x where x ->> 'responsavel' <> (select full_name from iara.guardians where id = v_maria)) and r2 ? 'erro', 'r', r);
  v_out := v_out || jsonb_build_object('passo', 'R5d. Assunto sem proteção, com envio e sem órgão: não abre ocorrência ao Secretário', 'ok',
    (select ocorrencia_seduc_id from iara.reunioes_responsavel where id = v_id) is null);
  r := pg_temp.as_call('re-dir2', 'reuniao_detalhe', jsonb_build_object('id', v_id));
  r2 := pg_temp.as_call('re-dir2', 'reunioes_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', 'R6. Direção de outra unidade não vê', 'ok',
    r ? 'erro' and not exists (select 1 from jsonb_array_elements(r2 -> 'itens') x where (x ->> 'id')::uuid = v_id));

  -- professor: só da própria turma (a direção registra para um aluno de outra turma da unidade)
  perform iara.session_create('PROFESSOR', v_unit, 're-prof', 'teste');
  select coalesce(array_agg(cs.class_id), '{}') into v_turmas from iara.class_staff cs join iara.app_users u on u.staff_id = cs.staff_id
    join iara.app_sessions x on x.user_id = u.id where x.token_hash = 're-prof' and (cs.end_date is null or cs.end_date >= current_date);
  select e.student_id, sg.guardian_id into v_fora, v_fora_g from iara.enrollments e join iara.student_guardians sg on sg.student_id = e.student_id and sg.end_date is null
  where e.unit_id = v_unit and e.status = 'ACTIVE' and not (e.class_id = any (v_turmas)) order by e.student_id desc limit 1;
  r := pg_temp.as_call('re-dir', 'reuniao_registrar', jsonb_build_object('student_id', v_fora, 'guardian_id', v_fora_g, 'tema', 'OUTRO', 'envia_responsavel', true,
    'resumo', 'Assunto de teste em outra turma da unidade.', 'solucoes', 'Solução de teste.', 'posicao_escola', 'Posição da escola.', 'posicao_responsavel', 'Posição.'));
  v_fora_id := (r ->> 'id')::uuid;
  r2 := pg_temp.as_call('re-prof', 'reunioes_lista', '{}');
  r := pg_temp.as_call('re-prof', 'reuniao_detalhe', jsonb_build_object('id', v_fora_id));
  v_out := v_out || jsonb_build_object('passo', 'R6b. Professor vê a própria turma, e não as outras', 'ok', v_fora_id is not null and r ? 'erro'
    and exists (select 1 from jsonb_array_elements(r2 -> 'itens') x where (x ->> 'id')::uuid = v_id)
    and not exists (select 1 from jsonb_array_elements(r2 -> 'itens') x where (x ->> 'id')::uuid = v_fora_id), 'r', r, 'turmas', to_jsonb(v_turmas));

  -- 2. Controle externo
  r := pg_temp.as_call('re-ext', 'controle_reunioes', '{}');
  v_out := v_out || jsonb_build_object('passo', 'R7. Lista do controle externo não identifica a criança', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'itens') x where (x ->> 'id')::uuid = v_id)
    and not (r::text like '%' || (select full_name from iara.students where id = v_ana) || '%')
    and not exists (select 1 from jsonb_array_elements(r -> 'itens') x where x ? 'aluno' or x ? 'responsavel' or x ? 'resumo'));
  r := pg_temp.as_call('re-ext', 'controle_reuniao', jsonb_build_object('id', v_id));
  r2 := pg_temp.as_call('re-ext', 'controle_reuniao', jsonb_build_object('id', v_id, 'motivo', 'Procedimento do MP nº 123/2026'));
  v_out := v_out || jsonb_build_object('passo', 'R8. Abrir exige motivo, mostra o conteúdo e registra a consulta', 'ok',
    r ? 'erro' and r2 ->> 'resumo' is not null
    and exists (select 1 from iara.reuniao_eventos e where e.reuniao_id = v_id and e.tipo = 'CONSULTA_EXTERNA')
    and exists (select 1 from iara.audit_log a where a.action = 'CONTROLE_CONSULTA' and a.summary like '%' || iara.reuniao_codigo(v_id) || '%'));

  -- 3. Régua de avisos
  r := jsonb_build_object('a', iara.reuniao_processar(v_id, true));
  v_out := v_out || jsonb_build_object('passo', 'R9. No mesmo dia não há novo aviso', 'ok', r ->> 'a' = 'sem_acao', 'r', r);
  update iara.reunioes_responsavel set enviada_em = enviada_em - interval '1 day' where id = v_id;
  r := jsonb_build_object('a', iara.reuniao_processar(v_id, true), 'b', iara.reuniao_processar(v_id, true));
  select texto into v_texto from iara.reuniao_eventos where reuniao_id = v_id and tipo = 'AVISO' and dia = 1;
  v_out := v_out || jsonb_build_object('passo', 'R10. D+1: disponibilidade e importância, sem repetir', 'ok',
    r ->> 'a' = 'aviso_1' and r ->> 'b' = 'sem_acao' and v_texto like '%disponível%' and v_texto like '%importante%', 'r', r);
  update iara.reunioes_responsavel set enviada_em = enviada_em - interval '1 day' where id = v_id;
  r := jsonb_build_object('a', iara.reuniao_processar(v_id, true));
  select texto into v_texto from iara.reuniao_eventos where reuniao_id = v_id and tipo = 'AVISO' and dia = 2;
  v_out := v_out || jsonb_build_object('passo', 'R11. D+2: alerta de envio ao Conselho Tutelar', 'ok', r ->> 'a' = 'aviso_2' and v_texto like '%Conselho Tutelar%');
  update iara.reunioes_responsavel set enviada_em = enviada_em - interval '1 day' where id = v_id;
  update iara.reuniao_eventos set em = em - interval '1 day' where reuniao_id = v_id;
  r := jsonb_build_object('a', iara.reuniao_processar(v_id, true));
  select texto into v_texto from iara.reuniao_eventos where reuniao_id = v_id and tipo = 'AVISO' and dia = 3;
  v_out := v_out || jsonb_build_object('passo', 'R12. D+3: último aviso, implicações legais e os três órgãos', 'ok',
    r ->> 'a' = 'aviso_3' and v_texto like '%ÚLTIMO AVISO%' and v_texto like '%ECA%' and v_texto like '%Defensoria%' and v_texto like '%Ministério Público%' and v_texto like '%não significa concordar%');
  r := jsonb_build_object('a', iara.reuniao_processar(v_id, true));
  v_out := v_out || jsonb_build_object('passo', 'R13. No próprio D+3 ainda não prepara o envio', 'ok', r ->> 'a' = 'sem_acao');
  update iara.reunioes_responsavel set enviada_em = enviada_em - interval '1 day' where id = v_id;
  update iara.reuniao_eventos set em = em - interval '1 day' where reuniao_id = v_id;
  r := jsonb_build_object('a', iara.reuniao_processar(v_id, true));
  v_out := v_out || jsonb_build_object('passo', 'R14. D+4 sem resposta: prepara o envio aos três órgãos, sem enviar sozinho', 'ok',
    r ->> 'a' = 'prazo_vencido' and (select situacao from iara.reunioes_responsavel where id = v_id) = 'PRAZO_VENCIDO'
    and (select count(*) from iara.reuniao_envios_orgaos where reuniao_id = v_id and situacao = 'AGUARDANDO_ENVIO') = 3
    and (select count(*) from iara.reuniao_envios_orgaos where reuniao_id = v_id and situacao = 'ENVIADO') = 0, 'r', r);
  v_out := v_out || jsonb_build_object('passo', 'R14b. Prazo vencido abre a ocorrência ao Secretário', 'ok',
    exists (select 1 from iara.ocorrencias o join iara.reunioes_responsavel x on x.ocorrencia_seduc_id = o.id where x.id = v_id and o.instancia = 'SECRETARIA' and o.sigilosa and o.gravidade = 'GRAVE'));

  -- 4. Resposta da família
  r := pg_temp.as_call('re-fam', 'familia_reunioes', '{}');
  v_out := v_out || jsonb_build_object('passo', 'R15. A família vê o registro, com os avisos recebidos', 'ok',
    (r ->> 'aguardando')::int >= 1 and exists (select 1 from jsonb_array_elements(r -> 'reunioes') x where (x ->> 'id')::uuid = v_id and jsonb_array_length(x -> 'avisos') = 4));
  r := pg_temp.as_call('re-fam', 'familia_reuniao_responder', jsonb_build_object('id', v_id, 'acao', 'MANIFESTAR', 'texto', 'curto'));
  v_out := v_out || jsonb_build_object('passo', 'R16. Manifestação exige texto', 'ok', r ? 'erro');
  r := pg_temp.as_call('re-fam', 'familia_reuniao_responder', jsonb_build_object('id', v_id, 'acao', 'MANIFESTAR', 'texto', 'Não concordo com a descrição das faltas.', 'canal', 'PORTAL'));
  v_out := v_out || jsonb_build_object('passo', 'R17. A resposta antes do envio cancela o que era por falta de validação', 'ok',
    (r ->> 'ok')::boolean and (select situacao from iara.reunioes_responsavel where id = v_id) = 'MANIFESTADA'
    and (select count(*) from iara.reuniao_envios_orgaos where reuniao_id = v_id and situacao = 'CANCELADO') = 3, 'r', r);
  r := pg_temp.as_call('re-fam', 'familia_reuniao_responder', jsonb_build_object('id', v_id, 'acao', 'ACEITAR'));
  v_out := v_out || jsonb_build_object('passo', 'R18. Não responde duas vezes', 'ok', r ? 'erro');

  -- 5. Proteção da criança
  r := pg_temp.as_call('re-dir', 'reuniao_registrar', jsonb_build_object('student_id', v_outro, 'guardian_id', v_outro_g, 'tema', 'VIOLENCIA_DOMESTICA',
    'resumo', 'Relato de violência doméstica feito à escola.', 'solucoes', 'Acompanhamento pela rede de proteção.', 'posicao_escola', 'A escola tem o dever de comunicar.', 'posicao_responsavel', 'Concordou.'));
  v_out := v_out || jsonb_build_object('passo', 'R19. Violência doméstica: é obrigatório dizer se pode enviar ao responsável', 'ok', r ? 'erro', 'r', r);
  r := pg_temp.as_call('re-dir', 'reuniao_registrar', jsonb_build_object('student_id', v_outro, 'guardian_id', v_outro_g, 'tema', 'VIOLENCIA_DOMESTICA', 'envia_responsavel', false,
    'resumo', 'Relato de violência doméstica feito à escola.', 'solucoes', 'Acompanhamento pela rede de proteção.', 'posicao_escola', 'A escola tem o dever de comunicar.', 'posicao_responsavel', 'Concordou.'));
  v_out := v_out || jsonb_build_object('passo', 'R20. Sem envio exige justificativa', 'ok', r ? 'erro');
  r := pg_temp.as_call('re-dir', 'reuniao_registrar', jsonb_build_object('student_id', v_outro, 'guardian_id', v_outro_g, 'tema', 'VIOLENCIA_DOMESTICA', 'envia_responsavel', false,
    'motivo_sem_envio', 'Enviar o registro pode aumentar o risco para a criança.',
    'resumo', 'Relato de violência doméstica feito à escola.', 'solucoes', 'Acompanhamento pela rede de proteção.', 'posicao_escola', 'A escola tem o dever de comunicar.', 'posicao_responsavel', 'Concordou.'));
  v_nid := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'R21. Sem envio: nenhum aviso, nenhuma notificação, e Conselho Tutelar preparado na hora', 'ok',
    r ->> 'situacao' = 'SEM_ENVIO' and not exists (select 1 from iara.reuniao_eventos e where e.reuniao_id = v_nid and e.tipo = 'AVISO')
    and not exists (select 1 from iara.notifications n where n.student_id = v_outro and n.event_type = 'REUNIAO_AVISO')
    and exists (select 1 from iara.reuniao_envios_orgaos e where e.reuniao_id = v_nid and e.orgao = 'CONSELHO_TUTELAR' and e.motivo = 'PROTECAO' and e.situacao = 'AGUARDANDO_ENVIO')
    and iara.reuniao_processar(v_nid, true) = 'sem_acao', 'r', r);
  r2 := pg_temp.as_call('re-seduc', 'ocorrencias_lista', jsonb_build_object('instancia', 'SECRETARIA'));
  v_out := v_out || jsonb_build_object('passo', 'R21b. A ocorrência urgente aparece na lista do Secretário, em 2ª instância e sigilosa', 'ok',
    exists (select 1 from jsonb_array_elements(r2 -> 'itens') x where (x ->> 'id')::uuid = (r ->> 'ocorrencia_seduc_id')::uuid and x ->> 'instancia' = 'SECRETARIA'
            and (x ->> 'sigilosa')::boolean and x ->> 'gravidade' = 'GRAVE' and x ->> 'descricao' like 'Registro de reunião R-%'), 'r2', r2 -> 'contagem');
  perform iara.session_create('CIDADAO', null, 're-fam2', 'teste');
  update iara.app_users set guardian_id = v_outro_g where id = (select user_id from iara.app_sessions where token_hash = 're-fam2');
  r2 := pg_temp.as_call('re-fam2', 'familia_ocorrencias', '{}');
  v_out := v_out || jsonb_build_object('passo', 'R21c. A família desse aluno não vê a ocorrência nem o registro', 'ok',
    not (r2::text like '%' || (r ->> 'ocorrencia_seduc_id') || '%') and not (pg_temp.as_call('re-fam2', 'familia_reunioes', '{}')::text like '%' || v_nid::text || '%'), 'r2', r2 -> 'aguardando_ciencia');
  update iara.reunioes_responsavel set guardian_id = v_maria where id = v_nid;
  r := pg_temp.as_call('re-fam', 'familia_reunioes', '{}');
  v_out := v_out || jsonb_build_object('passo', 'R22. Registro sem envio nunca aparece para a família', 'ok',
    not exists (select 1 from jsonb_array_elements(r -> 'reunioes') x where (x ->> 'id')::uuid = v_nid));
  update iara.reunioes_responsavel set guardian_id = v_outro_g where id = v_nid;

  r := pg_temp.as_call('re-dir', 'reuniao_registrar', jsonb_build_object('student_id', v_outro, 'guardian_id', v_outro_g, 'tema', 'VIOLENCIA_SEXUAL', 'envia_responsavel', true,
    'resumo', 'Relato de suspeita feito à escola, em sigilo.', 'solucoes', 'Comunicação imediata à rede de proteção.', 'posicao_escola', 'A escola comunica.', 'posicao_responsavel', 'Ciente.'));
  v_out := v_out || jsonb_build_object('passo', 'R23. Suspeita de violência sexual nunca vai à família, mesmo pedindo envio', 'ok', r ->> 'situacao' = 'SEM_ENVIO', 'r', r);

  insert into iara.guarda_restricoes (student_id, unit_id, tipo, guardian_id, descricao, documento, vigencia_inicio) values (v_outro, v_unit, 'MEDIDA_PROTETIVA', v_outro_g, 'Medida protetiva de teste.', 'Processo de teste', iara.hoje_local());
  r := pg_temp.as_call('re-dir', 'reuniao_registrar', jsonb_build_object('student_id', v_outro, 'guardian_id', v_outro_g, 'tema', 'OUTRO', 'envia_responsavel', true,
    'resumo', 'Assunto de teste com responsável sob restrição.', 'solucoes', 'Sem solução de teste.', 'posicao_escola', 'Posição da escola.', 'posicao_responsavel', 'Posição.'));
  v_out := v_out || jsonb_build_object('passo', 'R24. Medida protetiva sobre o responsável bloqueia o envio', 'ok', r ? 'erro', 'r', r);

  -- 6. Envio aos órgãos
  select id into v_nid from iara.reuniao_envios_orgaos where reuniao_id = (select id from iara.reunioes_responsavel where student_id = v_outro and tema = 'VIOLENCIA_DOMESTICA' and not is_demo limit 1) limit 1;
  r := pg_temp.as_call('re-seduc', 'reuniao_envio_orgao', jsonb_build_object('id', v_nid));
  r2 := pg_temp.as_call('re-seduc', 'reuniao_envio_orgao', jsonb_build_object('id', v_nid, 'protocolo', 'CT-123'));
  v_out := v_out || jsonb_build_object('passo', 'R25. Confirmar o envio exige protocolo', 'ok', r ? 'erro' and (r2 ->> 'ok')::boolean
    and (select situacao from iara.reuniao_envios_orgaos where id = v_nid) = 'ENVIADO', 'r2', r2);
  r := pg_temp.as_call('re-sec', 'reuniao_envio_orgao', jsonb_build_object('id', v_nid, 'protocolo', 'CT-456'));
  r2 := pg_temp.as_call('re-dir', 'reuniao_envio_orgao', jsonb_build_object('id', v_nid, 'protocolo', 'CT-456'));
  v_out := v_out || jsonb_build_object('passo', 'R26. Secretaria escolar e direção não confirmam envio', 'ok', r ? 'erro' and r2 ? 'erro');
  v_out := v_out || jsonb_build_object('passo', 'R26b. A confirmação vai para a linha da ocorrência do Secretário', 'ok',
    exists (select 1 from iara.ocorrencia_eventos e join iara.reunioes_responsavel x on x.ocorrencia_seduc_id = e.ocorrencia_id join iara.reuniao_envios_orgaos en on en.reuniao_id = x.id
            where en.id = v_nid and e.interno and e.texto like '%Protocolo CT-123%'));

  -- 7. Fora da apresentação, a rotina não toca nos registros de demonstração
  update iara.reunioes_responsavel set enviada_em = enviada_em - interval '10 days' where id = v_ana_rec;
  perform iara.reunioes_rotina();
  v_out := v_out || jsonb_build_object('passo', 'R27. A rotina automática não mexe nos registros de demonstração', 'ok',
    (select situacao from iara.reunioes_responsavel where id = v_ana_rec) = 'AGUARDANDO');

  r := pg_temp.as_call('re-dir', 'reuniao_demo_avancar', jsonb_build_object('id', v_ana_rec));
  v_out := v_out || jsonb_build_object('passo', 'R28. O avanço de dia da apresentação funciona', 'ok', (r ->> 'ok')::boolean, 'r', r);

  -- 8. Relato de violência à IARA
  r := pg_temp.as_call('re-fam', 'familia_relato_protecao', jsonb_build_object('texto', 'Relato de teste: violência em casa.'));
  v_nid := (r ->> 'id')::uuid;
  r2 := pg_temp.as_call('re-seduc', 'ocorrencias_lista', jsonb_build_object('instancia', 'SECRETARIA'));
  v_out := v_out || jsonb_build_object('passo', 'R29. Relato à IARA abre ocorrência urgente e sigilosa com o Secretário, com prazo no dia seguinte', 'ok',
    exists (select 1 from jsonb_array_elements(r2 -> 'itens') x where (x ->> 'id')::uuid = v_nid and (x ->> 'sigilosa')::boolean and x ->> 'gravidade' = 'GRAVE' and (x ->> 'prazo')::date = iara.hoje_local() + 1), 'r', r);
  v_out := v_out || jsonb_build_object('passo', 'R30. O relato prepara a comunicação obrigatória ao Conselho Tutelar', 'ok',
    exists (select 1 from iara.encaminhamentos k where k.ocorrencia_id = v_nid and k.tipo = 'CONSELHO_TUTELAR' and k.obrigatorio and k.situacao = 'AGUARDANDO_APROVACAO'));
  r2 := pg_temp.as_call('re-fam', 'familia_ocorrencias', '{}');
  v_out := v_out || jsonb_build_object('passo', 'R31. O relato não aparece para nenhum responsável, nem para quem relatou', 'ok', not (r2::text like '%' || v_nid::text || '%'));
  r := pg_temp.as_call('re-fam', 'familia_relato_protecao', jsonb_build_object('texto', 'Segundo relato de teste.'));
  v_out := v_out || jsonb_build_object('passo', 'R32. Novo relato no mesmo dia soma ao registro aberto', 'ok', (r ->> 'id')::uuid = v_nid
    and exists (select 1 from iara.ocorrencia_eventos e where e.ocorrencia_id = v_nid and e.texto like '%Segundo relato%' and e.interno));
  r := pg_temp.as_call('re-dir', 'familia_relato_protecao', jsonb_build_object('texto', 'Servidor não usa.'));
  v_out := v_out || jsonb_build_object('passo', 'R33. Só responsável usa o relato', 'ok', r ? 'erro');

  raise exception 'RESULTADO: %', v_out;
end $$;
