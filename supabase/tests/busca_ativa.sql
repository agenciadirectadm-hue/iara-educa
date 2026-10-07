-- Busca ativa: os 10 critérios de aceite do pedido de Rob (07/10/2026), com chamadas lançadas como o professor faz.
-- Roda numa transação revertida (não deixa resíduo). Cada passo traz "ok": true quando o comportamento é o esperado.
-- Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/busca_ativa.sql
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
create or replace function pg_temp.ok_erro(r jsonb, p_cod text) returns boolean language sql as $f$ select coalesce(r ->> 'codigo' = p_cod, false) $f$;
create or replace function pg_temp.sessao_familia(p_hash text, p_guardian uuid) returns void language plpgsql as $f$
declare v_u uuid := gen_random_uuid();
begin
  insert into iara.app_users (id, tenant_id, display_name, role_code, guardian_id, auth_provider, is_demo) values (v_u, 1, 'Família teste', 'CIDADAO', p_guardian, 'DEMO', true);
  insert into iara.app_sessions (token_hash, user_id, expires_at, user_agent) values (p_hash, v_u, now() + interval '1 hour', 'teste');
end $f$;

do $$
declare
  v_out jsonb := '[]';
  r jsonb;
  v_hoje date := iara.hoje_local();
  v_g uuid;
  v_s1 uuid;
  v_s2 uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_u1 integer;
  v_a uuid;
  v_a2 uuid;
  v_n integer;
  v_ct uuid;
  v_t uuid;
  v_org_nv uuid;
  v_enc uuid;
  v_reg uuid;
begin
  if not iara.dia_letivo(v_hoje, null) then
    raise exception 'RESULTADO: %', jsonb_build_array(jsonb_build_object('passo', 'Hoje não é dia letivo: teste da chamada não se aplica', 'ok', true));
  end if;
  -- irmãos matriculados (mesmo responsável principal), em turmas do fundamental
  select z.g, z.s1, z.s2 into v_g, v_s1, v_s2 from (
    select iara.responsavel_contato(sg.student_id) g, min(sg.student_id::text)::uuid s1, max(sg.student_id::text)::uuid s2
    from iara.student_guardians sg join iara.enrollments e on e.student_id = sg.student_id and e.status = 'ACTIVE'
    join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
    where sg.end_date is null and gl.code like 'EF%' and sg.is_primary
    group by 1 having count(distinct sg.student_id) = 2 and count(distinct e.unit_id) = 1) z where z.g is not null limit 1;
  select class_id, unit_id into v_c1, v_u1 from iara.enrollments where student_id = v_s1 and status = 'ACTIVE';
  select class_id into v_c2 from iara.enrollments where student_id = v_s2 and status = 'ACTIVE';
  -- a chamada de hoje das duas turmas começa limpa (o teste é revertido no fim)
  delete from iara.frequencia_faltas f using iara.frequencia_registros fr where fr.id = f.registro_id and fr.class_id in (v_c1, v_c2) and fr.data = v_hoje;
  delete from iara.frequencia_registros where class_id in (v_c1, v_c2) and data = v_hoje;
  delete from iara.frequencia_ausencias where student_id in (v_s1, v_s2) and data = v_hoje;
  perform iara.session_create('DIRETOR_UNIDADE', v_u1, 'ba-dir', 'teste');
  perform iara.session_create('SECRETARIA_ESCOLAR', v_u1, 'ba-sec', 'teste');
  perform iara.session_create('PROFESSOR', v_u1, 'ba-prof', 'teste');
  perform iara.session_create('PREFEITO', null, 'ba-pref', 'teste');
  perform iara.session_create('SECRETARIO', null, 'ba-secretario', 'teste');
  perform pg_temp.sessao_familia('ba-fam', v_g);

  -- 1. ausência confirmada sem justificativa → um único contato no mesmo dia (irmãos: uma mensagem consolidada)
  r := pg_temp.as_call('ba-dir', 'frequencia_lancar', jsonb_build_object('class_id', v_c1, 'data', v_hoje, 'faltas', jsonb_build_array(v_s1)));
  if v_c2 <> v_c1 then r := pg_temp.as_call('ba-dir', 'frequencia_lancar', jsonb_build_object('class_id', v_c2, 'data', v_hoje, 'faltas', jsonb_build_array(v_s2)));
  else r := pg_temp.as_call('ba-dir', 'frequencia_lancar', jsonb_build_object('class_id', v_c1, 'data', v_hoje, 'faltas', jsonb_build_array(v_s1, v_s2))); end if;
  r := pg_temp.as_call('ba-dir', 'frequencia_lancar', jsonb_build_object('class_id', v_c1, 'data', v_hoje, 'faltas', jsonb_build_array(v_s1) || case when v_c1 = v_c2 then jsonb_build_array(v_s2) else '[]' end));
  select count(*) into v_n from iara.frequencia_contatos where guardian_id = v_g and data_ref = v_hoje and nivel = '1';
  v_out := v_out || jsonb_build_object('passo', 'A1. Ausência sem justificativa gera um único contato no mesmo dia (irmãos juntos, sem duplicar ao relançar)', 'ok',
    v_n = 1 and (select cardinality(student_ids) from iara.frequencia_contatos where guardian_id = v_g and data_ref = v_hoje and nivel = '1') = 2
    and (select count(*) from iara.frequencia_ausencias where student_id in (v_s1, v_s2) and data = v_hoje and situacao = 'AGUARDANDO_ESCLARECIMENTO') = 2,
    'contatos', v_n, 'status', (select status from iara.frequencia_contatos where guardian_id = v_g and data_ref = v_hoje and nivel = '1'));
  -- o envio simulado falha em ~4% dos casos (sorteio pelo id): aqui fica fixo como entregue
  update iara.frequencia_contatos set status = 'SIMULADA', falha_motivo = null where guardian_id = v_g and data_ref = v_hoje and nivel = '1';
  select id into v_a from iara.frequencia_ausencias where student_id = v_s1 and data = v_hoje;
  select id into v_a2 from iara.frequencia_ausencias where student_id = v_s2 and data = v_hoje;

  -- 9. o responsável vê os dois filhos, cada um com a sua ausência
  r := pg_temp.as_call('ba-fam', 'familia_ausencias', '{}');
  v_out := v_out || jsonb_build_object('passo', 'A9. O responsável acompanha os dois filhos sem misturar os casos', 'ok',
    exists (select 1 from jsonb_array_elements(r) x where (x ->> 'id')::uuid = v_a) and exists (select 1 from jsonb_array_elements(r) x where (x ->> 'id')::uuid = v_a2), 'erro', r ->> 'erro');

  -- 2. resposta da família atualiza a ocorrência e interrompe lembretes
  r := pg_temp.as_call('ba-fam', 'familia_ausencia_responder', jsonb_build_object('id', v_a, 'motivo', 'SAUDE', 'canal', 'WHATSAPP'));
  update iara.frequencia_contatos set enviada_em = now() - interval '30 hours' where guardian_id = v_g and data_ref = v_hoje and nivel = '1';
  perform iara.busca_ativa_processar(null, null);
  v_out := v_out || jsonb_build_object('passo', 'A2. A resposta atualiza a ausência e só quem não respondeu recebe lembrete', 'ok',
    (select situacao from iara.frequencia_ausencias where id = v_a) = 'MOTIVO_INFORMADO'
    and not exists (select 1 from iara.frequencia_contatos where v_a = any (ausencia_ids) and nivel = '2')
    and exists (select 1 from iara.frequencia_contatos where v_a2 = any (ausencia_ids) and nivel = '2')
    and exists (select 1 from iara.frequencia_tarefas where ausencia_id = v_a2 and tipo = 'LIGAR'), 'erro', r ->> 'erro');

  -- correção da chamada: a falta saiu → erro corrigido e mensagem de correção a quem já recebeu
  r := pg_temp.as_call('ba-dir', 'frequencia_lancar', jsonb_build_object('class_id', v_c2, 'data', v_hoje,
         'faltas', case when v_c1 = v_c2 then jsonb_build_array(v_s1) else '[]'::jsonb end));
  v_out := v_out || jsonb_build_object('passo', 'A2b. Presença corrigida: ausência vira erro corrigido e a família recebe a correção', 'ok',
    (select situacao from iara.frequencia_ausencias where id = v_a2) = 'ERRO_CORRIGIDO' and exists (select 1 from iara.frequencia_contatos where v_a2 = any (ausencia_ids) and nivel = 'CORRECAO'),
    'erro', r ->> 'erro');

  -- 3. falha de entrega → tarefa de contato alternativo
  update iara.frequencia_contatos set status = 'FALHA', falha_motivo = 'teste' where guardian_id = v_g and data_ref = v_hoje and nivel = '1';
  perform iara.busca_ativa_processar(null, null);
  v_out := v_out || jsonb_build_object('passo', 'A3. Falha de entrega gera tarefa de conferir o telefone (não é recusa)', 'ok',
    exists (select 1 from iara.frequencia_tarefas where tipo = 'CONFERIR_TELEFONE' and chave = 'tel:' || (select id from iara.frequencia_contatos where guardian_id = v_g and data_ref = v_hoje and nivel = '1')));

  -- 4. parâmetros por etapa e carga horária
  v_out := v_out || jsonb_build_object('passo', 'A4. Parâmetros por etapa: fundamental 75%, pré-escola 60%, creche sem limite legal', 'ok',
    iara.fparam('FREQUENCIA_MINIMA', 'EF') = 75 and iara.fparam('FREQUENCIA_MINIMA', 'PRE') = 60 and iara.fparam('LIMITE_LEGAL_30', 'CRECHE') is null
    and (pg_temp.as_call('ba-dir', 'busca_ativa_aluno', jsonb_build_object('student_id', v_s1)) -> 'limite_legal' ->> 'alerta_horas')::numeric = 60);

  -- 5. limite legal → tarefa prioritária e obrigatória (não se fecha sem o envio, o expediente não se cancela)
  select k.id, (select t.id from iara.frequencia_tarefas t where t.chave = 'ct:' || k.id) into v_ct, v_t from iara.encaminhamentos k
  join iara.enrollments e on e.student_id = k.student_id and e.status = 'ACTIVE' where k.tipo = 'CONSELHO_TUTELAR' and k.situacao = 'AGUARDANDO_APROVACAO' and e.unit_id = v_u1 limit 1;
  if v_ct is null then
    select k.id, (select t.id from iara.frequencia_tarefas t where t.chave = 'ct:' || k.id) into v_ct, v_t from iara.encaminhamentos k where k.tipo = 'CONSELHO_TUTELAR' and k.situacao = 'AGUARDANDO_APROVACAO' limit 1;
    perform iara.session_create('DIRETOR_UNIDADE', (select unit_id from iara.encaminhamentos where id = v_ct), 'ba-dir', 'teste-2');
  end if;
  v_out := v_out || jsonb_build_object('passo', 'A5. Faltas acima de 30% do limite legal geram tarefa urgente e obrigatória de notificação', 'ok',
    v_t is not null and (select prioridade = 'URGENTE' and obrigatoria from iara.frequencia_tarefas where id = v_t));
  r := pg_temp.as_call('ba-dir', 'ba_tarefa_concluir', jsonb_build_object('id', v_t, 'resultado', 'Tentando fechar sem enviar o expediente.'));
  v_out := v_out || jsonb_build_object('passo', 'A5b. A tarefa legal não fecha sem o envio', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('ba-dir', 'ba_encaminhamento', jsonb_build_object('acao', 'CANCELAR', 'id', v_ct, 'texto', 'Tentativa de ignorar a comunicação legal.'));
  v_out := v_out || jsonb_build_object('passo', 'A5c. A comunicação legal não pode ser cancelada', 'ok', pg_temp.ok_erro(r, '22023'));

  -- 6. destinatário verificado e aprovação autorizada
  insert into iara.orgaos_destinatarios (nome, tipo, canal, verificado) values ('Órgão sem verificação (teste)', 'CONSELHO_TUTELAR', 'PROTOCOLO_ELETRONICO', false) returning id into v_org_nv;
  r := pg_temp.as_call('ba-dir', 'ba_encaminhamento', jsonb_build_object('acao', 'APROVAR', 'id', v_ct, 'orgao_id', v_org_nv));
  v_out := v_out || jsonb_build_object('passo', 'A6. Encaminhamento a destinatário não verificado é recusado', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('ba-sec', 'ba_encaminhamento', jsonb_build_object('acao', 'APROVAR', 'id', v_ct));
  v_out := v_out || jsonb_build_object('passo', 'A6b. Secretaria escolar não aprova (deve negar)', 'ok', pg_temp.ok_erro(r, '42501') or pg_temp.ok_erro(r, 'P0002'));
  r := pg_temp.as_call('ba-dir', 'ba_encaminhamento', jsonb_build_object('acao', 'APROVAR', 'id', v_ct));
  r := pg_temp.as_call('ba-dir', 'ba_encaminhamento', jsonb_build_object('acao', 'ENVIO', 'id', v_ct, 'protocolo', 'PROT-TESTE-1'));
  v_out := v_out || jsonb_build_object('passo', 'A6c. Direção aprova (destinatário verificado), envia com protocolo e a tarefa legal fecha', 'ok',
    (select situacao from iara.encaminhamentos where id = v_ct) = 'ENVIADO' and (select conteudo ? 'fundamento' from iara.encaminhamentos where id = v_ct)
    and (select situacao from iara.frequencia_tarefas where id = v_t) = 'CONCLUIDA', 'erro', r ->> 'erro');

  -- 7. relato de risco fura a sequência
  r := pg_temp.as_call('ba-fam', 'familia_ausencia_responder', jsonb_build_object('id', v_a, 'motivo', 'OUTRO', 'texto', 'Ele apanha em casa e está com medo.'));
  v_out := v_out || jsonb_build_object('passo', 'A7. Relato com indício de risco: caso urgente e avaliação imediata, sem esperar os níveis', 'ok',
    (r ->> 'risco')::boolean and exists (select 1 from iara.busca_ativa_casos where student_id = v_s1 and urgente and situacao <> 'ENCERRADO')
    and exists (select 1 from iara.frequencia_tarefas where student_id = v_s1 and tipo = 'AVALIAR_RISCO' and prioridade = 'URGENTE' and obrigatoria), 'erro', r ->> 'erro');

  -- 8. registro de disparos e decisões
  v_out := v_out || jsonb_build_object('passo', 'A8. Cada disparo e decisão fica registrado', 'ok',
    exists (select 1 from iara.audit_log where action = 'AUSENCIA_RESPONDIDA' and entity_id = v_s1::text)
    and exists (select 1 from iara.audit_log where action = 'ENCAMINHAMENTO' and entity_id = (select student_id::text from iara.encaminhamentos where id = v_ct))
    and exists (select 1 from iara.frequencia_contatos where guardian_id = v_g and enviada_em is not null));

  -- 10. regras propostas não aparecem como confirmadas; alteração exige fundamento e gera versão
  v_out := v_out || jsonb_build_object('passo', 'A10. 5 seguidas / 7 alternadas existem só como opção proposta e desligada', 'ok',
    (select bool_and(situacao = 'PROPOSTO' and not ativo) from iara.frequencia_parametros where codigo in ('BUSCA_ATIVA_CONSECUTIVAS', 'BUSCA_ATIVA_ALTERNADAS'))
    and iara.fparam('BUSCA_ATIVA_CONSECUTIVAS') is null
    and (select situacao from iara.frequencia_parametros where codigo = 'CONTATO_MESMO_DIA' and ativo) = 'PENDENTE_VALIDACAO');
  r := pg_temp.as_call('ba-secretario', 'frequencia_regra_salvar', jsonb_build_object('id', (select id from iara.frequencia_parametros where codigo = 'LEMBRETE_SEM_RESPOSTA' and ativo), 'valor', 36));
  v_out := v_out || jsonb_build_object('passo', 'A10b. Alterar regra sem fundamento é recusado', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('ba-secretario', 'frequencia_regra_salvar', jsonb_build_object('id', (select id from iara.frequencia_parametros where codigo = 'LEMBRETE_SEM_RESPOSTA' and ativo),
         'valor', 36, 'fundamento', 'Ofício SEDUC nº 00/2026 (teste)'));
  v_out := v_out || jsonb_build_object('passo', 'A10c. Com fundamento, vira nova versão e a anterior fica no histórico', 'ok',
    iara.fparam('LEMBRETE_SEM_RESPOSTA') = 36 and (select count(*) from iara.frequencia_parametros where codigo = 'LEMBRETE_SEM_RESPOSTA') = 2, 'erro', r ->> 'erro');
  r := pg_temp.as_call('ba-dir', 'frequencia_regra_salvar', jsonb_build_object('id', (select id from iara.frequencia_parametros where codigo = 'LEMBRETE_SEM_RESPOSTA' and ativo), 'valor', 12, 'fundamento', 'Direção tentando mudar a regra'));
  v_out := v_out || jsonb_build_object('passo', 'A10d. Direção não altera a regra da rede (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));

  -- acesso
  r := pg_temp.as_call('ba-prof', 'busca_ativa_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', 'S1. Professor não vê o painel da busca ativa (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('ba-pref', 'busca_ativa_indicadores', '{}');
  v_out := v_out || jsonb_build_object('passo', 'S2. Prefeito vê só indicadores agregados', 'ok', r ->> 'erro' is null and r::text not like '%student%', 'erro', r ->> 'erro');
  r := pg_temp.as_call('ba-pref', 'busca_ativa_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', 'S3. Prefeito não abre a lista nominal (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));

  raise exception 'RESULTADO: %', v_out;
end $$;
