-- Gestão da rede (itens 23, 24, 25 e 27): organograma, guarda e restrições, suporte técnico, catálogo de serviços, critérios e jornada.
-- Roda numa transação revertida (não deixa resíduo). Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/gestao_rede.sql
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
  v_ana uuid := (iara.setting('demo_student_ana'))::uuid;
  v_unit integer;
  v_outra integer;
  v_aluno uuid;
  v_g uuid;
  v_setor uuid;
  v_sup uuid;
  v_ch uuid;
  v_g_ret boolean;
  v_peso numeric;
  v_rid integer;
begin
  select e.unit_id into v_unit from iara.enrollments e where e.student_id = v_ana and e.status = 'ACTIVE';
  select u.id into v_outra from iara.education_units u where u.status = 'ATIVA' and u.id <> v_unit order by u.id limit 1;
  perform iara.session_create('SECRETARIO', null, 'gr-seduc', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_unit, 'gr-dir', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_outra, 'gr-dir2', 'teste');
  perform iara.session_create('PROFESSOR', v_unit, 'gr-prof', 'teste');
  perform iara.session_create('INOVACAO', null, 'gr-sup', 'teste');
  select e.student_id, sg.guardian_id, sg.can_pick_up into v_aluno, v_g, v_g_ret from iara.enrollments e
  join iara.student_guardians sg on sg.student_id = e.student_id and sg.end_date is null and not sg.is_primary
  where e.unit_id = v_unit and e.status = 'ACTIVE' and e.student_id <> v_ana
    and not exists (select 1 from iara.guarda_restricoes x where x.student_id = e.student_id) order by e.student_id limit 1;
  perform pg_temp.sessao_familia('gr-fam', v_g);

  -- organograma
  r := pg_temp.as_call('gr-dir', 'org_setor_salvar', jsonb_build_object('sigla', 'TESTE', 'nome', 'Setor teste', 'tipo', 'DIVISAO', 'superior_id', (select id from iara.org_setores where sigla = 'DIGE')));
  v_out := v_out || jsonb_build_object('passo', 'G1. Direção de unidade não edita o organograma', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('gr-seduc', 'org_importar', jsonb_build_object('texto', E'SIGLA;Nome;Tipo;Superior\nNTE;Núcleo de Tecnologia Educacional;NUCLEO;DINOV\nNTE2;Apoio;XYZ;NTE\nORF;Órfão;DIVISAO;NAOEXISTE'));
  v_out := v_out || jsonb_build_object('passo', 'G2. Importação valida tipo e superior antes de gravar', 'ok', jsonb_array_length(r -> 'erros') = 2 and jsonb_array_length(r -> 'validas') = 1
    and not (r ->> 'gravado')::boolean and not exists (select 1 from iara.org_setores where sigla = 'NTE'), 'erro', coalesce(r ->> 'erro', (r -> 'erros')::text));
  r := pg_temp.as_call('gr-seduc', 'org_importar', jsonb_build_object('confirmar', true, 'texto', E'NTE2;Apoio pedagógico digital;COORDENACAO;NTE\nNTE;Núcleo de Tecnologia Educacional;NUCLEO;DINOV'));
  v_out := v_out || jsonb_build_object('passo', 'G3. Importação grava em qualquer ordem e liga os superiores', 'ok', (r ->> 'gravado')::boolean and (r ->> 'incluidos')::int = 2
    and (select x.sigla from iara.org_setores s join iara.org_setores x on x.id = s.superior_id where s.sigla = 'NTE2') = 'NTE', 'erro', coalesce(r ->> 'erro', (r -> 'erros')::text));
  select id into v_setor from iara.org_setores where sigla = 'NTE';
  r := pg_temp.as_call('gr-seduc', 'org_setor_salvar', jsonb_build_object('id', v_setor, 'sigla', 'NTE', 'nome', 'Núcleo de Tecnologia Educacional', 'tipo', 'NUCLEO',
    'superior_id', (select id from iara.org_setores where sigla = 'NTE2')));
  v_out := v_out || jsonb_build_object('passo', 'G4. Setor não fica abaixo de um subordinado (ciclo)', 'ok', pg_temp.ok_erro(r, '22023'), 'erro', coalesce(r ->> 'erro', r::text));
  r := pg_temp.as_call('gr-seduc', 'org_vincular', jsonb_build_object('setor_id', v_setor, 'staff_id', (select id from iara.staff order by id limit 1), 'funcao', 'Coordenação', 'chefia', true));
  r := pg_temp.as_call('gr-seduc', 'org_setor_excluir', jsonb_build_object('id', v_setor));
  v_out := v_out || jsonb_build_object('passo', 'G5. Setor com subordinado ou pessoa vinculada não é excluído', 'ok', pg_temp.ok_erro(r, '22023'));

  -- guarda e restrições
  r := pg_temp.as_call('gr-prof', 'guarda_registrar', jsonb_build_object('student_id', v_aluno, 'tipo', 'PROIBICAO_RETIRADA', 'guardian_id', v_g, 'descricao', 'Não pode retirar a criança.', 'documento', 'Processo teste'));
  v_out := v_out || jsonb_build_object('passo', 'G6. Professor não registra restrição judicial', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('gr-dir', 'guarda_registrar', jsonb_build_object('student_id', v_aluno, 'tipo', 'MEDIDA_PROTETIVA', 'guardian_id', v_g, 'bloquear_portal', true,
    'descricao', 'Afastamento do responsável indicado; sem informações escolares.', 'documento', 'Processo 0001234-56.2026.8.16.0017 (teste)'));
  v_out := v_out || jsonb_build_object('passo', 'G7. Direção registra medida protetiva: o responsável deixa de poder retirar', 'ok', (r ->> 'restricao_retirada')::boolean
    and not (select can_pick_up from iara.student_guardians where student_id = v_aluno and guardian_id = v_g), 'erro', r ->> 'erro');
  r := pg_temp.as_call('gr-fam', 'familia_ocorrencias', '{}');
  v_out := v_out || jsonb_build_object('passo', 'G8. Responsável com bloqueio judicial não vê mais a criança no portal', 'ok',
    not exists (select 1 from jsonb_array_elements(r -> 'ocorrencias') x where (x ->> 'student_id')::uuid = v_aluno)
    and pg_temp.ok_erro(pg_temp.as_call('gr-fam', 'ocorrencia_registrar', jsonb_build_object('student_id', v_aluno, 'tipo', 'OUTRO', 'descricao', 'Tentativa de relato de teste.')), '42501'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('gr-prof', 'guarda_aluno', jsonb_build_object('student_id', (select student_id from iara.enrollments where class_id = (select (t ->> 'id')::uuid from jsonb_array_elements(pg_temp.as_call('gr-prof', 'me', '{}') -> 'turmas') t limit 1) and status = 'ACTIVE' limit 1)));
  v_out := v_out || jsonb_build_object('passo', 'G9. Professor vê só o alerta, nunca o detalhe (visibilidade pendente: o mais restrito)', 'ok', r ->> 'erro' is null and not (r ->> 'detalhe')::boolean and not (r ? 'itens'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('gr-dir2', 'guarda_aluno', jsonb_build_object('student_id', v_aluno));
  v_out := v_out || jsonb_build_object('passo', 'G10. Outra unidade não consulta', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('gr-dir', 'guarda_registrar', jsonb_build_object('student_id', v_aluno, 'encerrar', true, 'id', (select id from iara.guarda_restricoes where student_id = v_aluno and not is_demo limit 1), 'motivo', 'Decisão revogada (teste).'));
  v_out := v_out || jsonb_build_object('passo', 'G11. Encerrar devolve a retirada como estava e reabre o portal', 'ok', not (r ->> 'tem_restricao')::boolean
    and (select can_pick_up from iara.student_guardians where student_id = v_aluno and guardian_id = v_g) is not distinct from v_g_ret
    and v_aluno in (select x from pg_temp.as_call('gr-fam', 'familia_ocorrencias', '{}') r2, lateral (select v_aluno x) z), 'erro', r ->> 'erro');

  -- suporte técnico
  r := pg_temp.as_call('gr-dir', 'suporte_abrir', jsonb_build_object('categoria', 'ACESSO_SENHA', 'titulo', 'Sem acesso ao sistema', 'descricao', 'Não consigo entrar. Minha senha: 123456 não funciona.'));
  v_out := v_out || jsonb_build_object('passo', 'G12. Chamado com senha é recusado', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('gr-dir', 'suporte_abrir', jsonb_build_object('categoria', 'IMPRESSORA', 'prioridade', 'ALTA', 'titulo', 'Impressora parada', 'descricao', 'A impressora da secretaria não imprime desde ontem.', 'anydesk_id', '123 456 789'));
  v_ch := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'G13. Direção abre demanda com protocolo, prazo de 1 dia (alta) e AnyDesk', 'ok', r ->> 'protocolo' like 'SUP-%' and r ->> 'anydesk_id' = '123456789'
    and (r ->> 'prazo')::timestamptz between now() + interval '23 hours' and now() + interval '25 hours', 'erro', r ->> 'erro');
  r := pg_temp.as_call('gr-dir2', 'suporte_detalhe', jsonb_build_object('id', v_ch));
  v_out := v_out || jsonb_build_object('passo', 'G14. Outra unidade não vê a demanda', 'ok', pg_temp.ok_erro(r, 'P0002'));
  r := pg_temp.as_call('gr-sup', 'suporte_responder', jsonb_build_object('id', v_ch, 'texto', 'Vamos acessar pelo AnyDesk às 9h.'));
  v_out := v_out || jsonb_build_object('passo', 'G15. Suporte responde e assume (em atendimento)', 'ok', r ->> 'situacao' = 'EM_ATENDIMENTO' and r ->> 'atendente_label' is not null, 'erro', r ->> 'erro');
  r := pg_temp.as_call('gr-sup', 'suporte_responder', jsonb_build_object('id', v_ch, 'situacao', 'RESOLVIDO', 'texto', 'ok'));
  v_out := v_out || jsonb_build_object('passo', 'G16. Resolver exige descrever a solução', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('gr-sup', 'suporte_responder', jsonb_build_object('id', v_ch, 'situacao', 'RESOLVIDO', 'texto', 'Driver reinstalado por acesso remoto.'));
  r := pg_temp.as_call('gr-dir', 'suporte_responder', jsonb_build_object('id', v_ch, 'avaliacao', 5));
  v_out := v_out || jsonb_build_object('passo', 'G17. Quem abriu avalia o atendimento', 'ok', (r ->> 'avaliacao')::int = 5 and r ->> 'situacao' = 'RESOLVIDO', 'erro', r ->> 'erro');
  r := pg_temp.as_call('gr-dir', 'suporte_abrir', jsonb_build_object('canal', 'MASTER', 'categoria', 'MELHORIA', 'titulo', 'Fale com o master', 'descricao', 'Sugestão de relatório de faltas mensal por turma.'));
  v_out := v_out || jsonb_build_object('passo', 'G18. Fale com o master abre canal próprio', 'ok', r ->> 'canal' = 'MASTER', 'erro', r ->> 'erro');
  r := pg_temp.as_call('gr-dir', 'suporte_anydesk', jsonb_build_object('acao', 'SALVAR', 'equipamento', 'Computador da secretaria', 'anydesk_id', '12345'));
  v_out := v_out || jsonb_build_object('passo', 'G19. Código do AnyDesk inválido é recusado', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('gr-prof', 'suporte_anydesk', jsonb_build_object('acao', 'SALVAR', 'equipamento', 'Notebook da sala', 'anydesk_id', '987654321'));
  v_out := v_out || jsonb_build_object('passo', 'G20. Professor não cadastra AnyDesk da unidade', 'ok', pg_temp.ok_erro(r, '42501'));

  -- catálogo de serviços
  r := pg_temp.as_call('gr-dir', 'servico_salvar', jsonb_build_object('name', 'Serviço teste', 'description', 'Descrição do serviço de teste.', 'sla_days', 5));
  v_out := v_out || jsonb_build_object('passo', 'G21. Direção não edita o catálogo', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('gr-seduc', 'servico_salvar', jsonb_build_object('name', 'Segunda via de carteirinha escolar', 'description', 'Emissão de segunda via da carteirinha do aluno.',
    'sla_days', 7, 'resolution_level', 'UNIDADE', 'team', 'SECRETARIA_ESCOLAR', 'plantao', 'Seg a sex, 8h às 17h', 'iara_action', 'Abre o pedido e avisa a secretaria da unidade.'));
  v_out := v_out || jsonb_build_object('passo', 'G22. Inclusão no catálogo com prazo, alçada, equipe, plantão e ação da IARA', 'ok', r ->> 'code' = 'SEGUNDA_VIA_DE_CARTEIRINHA_ESCOLAR' and (r ->> 'ativo')::boolean
    and exists (select 1 from jsonb_array_elements(api.service_catalog('{}') -> 'items') x where x ->> 'code' = 'SEGUNDA_VIA_DE_CARTEIRINHA_ESCOLAR'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('gr-seduc', 'servico_salvar', jsonb_build_object('code', 'SEGUNDA_VIA_DE_CARTEIRINHA_ESCOLAR', 'excluir', true));
  v_out := v_out || jsonb_build_object('passo', 'G23. Exclusão tira do catálogo (histórico preservado)', 'ok', not (r ->> 'ativo')::boolean
    and not exists (select 1 from jsonb_array_elements(api.service_catalog('{}') -> 'items') x where x ->> 'code' = 'SEGUNDA_VIA_DE_CARTEIRINHA_ESCOLAR'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('gr-seduc', 'servico_salvar', jsonb_build_object('code', (select case_type from iara.service_cases where status <> 'ENCERRADO' and case_type in (select code from iara.service_catalog) limit 1), 'excluir', true));
  v_out := v_out || jsonb_build_object('passo', 'G24. Serviço com atendimentos em aberto não é excluído', 'ok', pg_temp.ok_erro(r, '22023'));

  -- critérios
  select weight into v_peso from iara.rules where id = (iara.rule('MAE_SOLO')).id;
  r := pg_temp.as_call('gr-seduc', 'criterio_salvar', jsonb_build_object('code', 'MAE_SOLO', 'weight', 60, 'justification', 'Teste de soma acima de 100.'));
  v_out := v_out || jsonb_build_object('passo', 'G25. Pontos da fila não passam de 100 (IN 025/2025)', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('gr-seduc', 'criterio_salvar', jsonb_build_object('code', 'MAE_SOLO', 'weight', v_peso, 'description', 'Filho(a) de mãe solo, conforme declaração no cadastro (texto revisado).',
    'justification', 'Revisão do texto do critério (teste).'));
  v_rid := (r ->> 'id')::int;
  v_out := v_out || jsonb_build_object('passo', 'G26. Alteração gera nova versão vigente e a anterior vale até a véspera', 'ok', (iara.rule('MAE_SOLO')).id = v_rid
    and (select count(*) from iara.rules where rule_code = 'MAE_SOLO' and valid_to = iara.hoje_local() - 1) >= 1, 'erro', r ->> 'erro');
  r := pg_temp.as_call('gr-seduc', 'criterio_salvar', jsonb_build_object('code', 'IRMAO_TRANSPORTE', 'name', 'Irmão usa o transporte escolar', 'type', 'PRIORIDADE_FILA', 'weight', 3,
    'description', 'Proposta: prioridade para quem tem irmão na mesma rota.', 'justification', 'Sugestão da Gerência de Transporte (teste).'));
  v_out := v_out || jsonb_build_object('passo', 'G27. Critério novo entra proposto, fora do cálculo', 'ok', not (r ->> 'no_calculo')::boolean, 'erro', r ->> 'erro');

  -- jornada e matriz
  r := pg_temp.as_call('gr-seduc', 'jornada_salvar', jsonb_build_object('grade_code', 'EF3', 'turno', 'MANHA', 'inicio', '07:30', 'aulas_dia', 3, 'duracao_aula_min', 45, 'fundamento', 'Teste abaixo do mínimo.'));
  v_out := v_out || jsonb_build_object('passo', 'G28. Jornada abaixo de 800 h/ano é recusada (LDB art. 24)', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('gr-seduc', 'jornada_salvar', jsonb_build_object('grade_code', 'EF3', 'turno', 'MANHA', 'inicio', '07:30', 'aulas_dia', 5, 'duracao_aula_min', 50, 'hora_atividade_pct', 20, 'fundamento', 'Teste de hora-atividade.'));
  v_out := v_out || jsonb_build_object('passo', 'G29. Hora-atividade abaixo de 1/3 é recusada (Lei 11.738/2008)', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('gr-seduc', 'jornada_salvar', jsonb_build_object('grade_code', 'EF3', 'turno', 'MANHA', 'inicio', '07:30', 'aulas_dia', 5, 'duracao_aula_min', 50, 'fundamento', 'Cinco aulas de 50 minutos (teste).'));
  v_out := v_out || jsonb_build_object('passo', 'G30. Nova jornada vira a versão 2 (histórico)', 'ok', (r ->> 'versao')::int = 2, 'erro', r ->> 'erro');
  r := pg_temp.as_call('gr-seduc', 'matriz_salvar', jsonb_build_object('grade_code', 'EF3', 'componente', 'Robótica', 'aulas_semana', 30, 'quem', 'ESPECIALISTA'));
  v_out := v_out || jsonb_build_object('passo', 'G31. Matriz não passa das aulas que a jornada comporta', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('gr-dir', 'jornada_salvar', jsonb_build_object('grade_code', 'EF3', 'turno', 'MANHA', 'inicio', '07:30', 'aulas_dia', 5, 'duracao_aula_min', 50, 'fundamento', 'Teste sem permissão.'));
  v_out := v_out || jsonb_build_object('passo', 'G32. Direção não muda a jornada padrão da rede', 'ok', pg_temp.ok_erro(r, '42501'));

  -- limpeza da demonstração desfaz o que foi mexido
  perform iara.demo_purge_gestao(now());
  v_out := v_out || jsonb_build_object('passo', 'G33. Limpeza desfaz catálogo, critérios, organograma e jornada alterados', 'ok',
    not exists (select 1 from iara.service_catalog where code = 'SEGUNDA_VIA_DE_CARTEIRINHA_ESCOLAR') and not exists (select 1 from iara.rules where id = v_rid)
    and (select valid_to from iara.rules where id = (iara.rule('MAE_SOLO')).id) is null and not exists (select 1 from iara.org_setores where sigla in ('NTE', 'NTE2'))
    and (iara.jornada_vigente('EF3', 'MANHA')).versao = 1 and not exists (select 1 from iara.suporte_chamados where id = v_ch));

  raise exception 'RESULTADO: %', v_out;
end $$;
