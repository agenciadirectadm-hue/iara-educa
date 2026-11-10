-- Central de pendências (migração 099.11): minhas, equipe, tarefas, procedimentos, estatísticas e sincronização.
-- Roda numa transação revertida (não deixa resíduo). Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/pendencias.sql
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

do $$
declare
  v_out jsonb := '[]';
  r jsonb;
  r2 jsonb;
  v_unit integer := (iara.setting('demo_unit_maria'))::int;
  v_outra integer;
  v_prof uuid;
  v_tarefa uuid;
  v_auto uuid;
  v_alheia uuid;
  v_classe uuid;
  v_chamada uuid;
  v_ativas integer;
  v_regentes integer;
  v_rot uuid;
  v_cmei integer;
  v_escola integer;
  v_pa uuid;
begin
  select u.id into v_outra from iara.education_units u where u.status = 'ATIVA' and u.id <> v_unit order by u.id limit 1;
  perform iara.session_create('SECRETARIO', null, 'pd-sec', 'teste');
  perform iara.session_create('SUPERINTENDENCIA', null, 'pd-sup', 'teste');
  perform iara.session_create('PREFEITO', null, 'pd-pref', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_unit, 'pd-dir', 'teste');
  perform iara.session_create('SECRETARIA_ESCOLAR', v_unit, 'pd-sece', 'teste');
  perform iara.session_create('PROFESSOR', v_unit, 'pd-prof', 'teste');
  perform iara.session_create('GERENCIA_APOIO', null, 'pd-ger', 'teste');
  perform iara.session_create('GERENCIA_EI', null, 'pd-gei', 'teste');
  perform iara.session_create('APOIO_INTERDISCIPLINAR', null, 'pd-api', 'teste');
  select staff_id into v_prof from iara.app_users u join iara.app_sessions s on s.user_id = u.id where s.token_hash = 'pd-prof';
  perform iara.pend_sincronizar(null);

  -- ---------------------------------------------------------------- minhas
  r := pg_temp.as_call('pd-prof', 'pend_minhas', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P1. Professor(a) vê só as próprias pendências (pessoa), com o resumo', 'ok',
    r ? 'resumo' and jsonb_array_length(r -> 'itens') >= 1
    and not exists (select 1 from jsonb_array_elements(r -> 'itens') i where i ->> 'posto' <> 'P:' || v_prof), 'erro', r ->> 'erro');

  r := pg_temp.as_call('pd-sece', 'pend_minhas', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P2. Secretaria escolar vê as da secretaria da unidade e nenhuma da direção', 'ok',
    jsonb_array_length(r -> 'itens') >= 1
    and not exists (select 1 from jsonb_array_elements(r -> 'itens') i where i ->> 'papel' <> 'Secretaria escolar' or i ->> 'unidade' is null), 'erro', r ->> 'erro');

  r := pg_temp.as_call('pd-dir', 'pend_minhas', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P3. Direção vê as da direção', 'ok',
    not exists (select 1 from jsonb_array_elements(r -> 'itens') i where i ->> 'papel' <> 'Direção'), 'erro', r ->> 'erro');

  -- ---------------------------------------------------------------- equipe da direção
  r := pg_temp.as_call('pd-dir', 'pend_equipe', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P4. Direção acompanha os postos da unidade (secretaria e professores)', 'ok',
    r ->> 'nivel' = 'grupo' and exists (select 1 from jsonb_array_elements(r -> 'postos') p where p ->> 'papel' = 'Secretaria escolar')
    and exists (select 1 from jsonb_array_elements(r -> 'postos') p where (p ->> 'pessoa')::boolean), 'erro', r ->> 'erro');

  r := pg_temp.as_call('pd-dir', 'pend_equipe', jsonb_build_object('grupo', 'U:' || v_outra));
  v_out := v_out || jsonb_build_object('passo', 'P5. Direção não abre a equipe de outra unidade', 'ok', pg_temp.ok_erro(r, '42501'), 'erro', r ->> 'erro');

  r := pg_temp.as_call('pd-dir', 'pend_equipe', jsonb_build_object('posto', 'P:' || v_prof));
  v_out := v_out || jsonb_build_object('passo', 'P6. Direção abre as pendências de um(a) professor(a) da unidade', 'ok',
    r ->> 'nivel' = 'posto' and jsonb_array_length(r -> 'itens') >= 1, 'erro', r ->> 'erro');

  -- ---------------------------------------------------------------- tarefa atribuída com lista
  r := pg_temp.as_call('pd-dir', 'pend_atribuir', jsonb_build_object('posto', 'R:SECRETARIA_ESCOLAR:' || v_unit || ':' || iara.pend_setor('UNID'),
         'titulo', 'Conferir as fichas de matrícula do 1º ano', 'prazo', iara.hoje_local() + 3, 'checklist', jsonb_build_array('Fichas assinadas', 'Certidões anexadas')));
  v_tarefa := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'P7. Direção atribui tarefa com prazo e lista à secretaria', 'ok', v_tarefa is not null and r ->> 'origem' = 'ATRIBUIDA', 'erro', r ->> 'erro');

  r := pg_temp.as_call('pd-sece', 'pend_minhas', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P8. A tarefa aparece na central da secretaria', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'itens') i where (i ->> 'id')::uuid = v_tarefa), 'erro', r ->> 'erro');

  r := pg_temp.as_call('pd-sece', 'pend_concluir', jsonb_build_object('id', v_tarefa));
  v_out := v_out || jsonb_build_object('passo', 'P9. Não conclui sem marcar a lista', 'ok', pg_temp.ok_erro(r, '22023'), 'erro', r ->> 'erro');

  r := pg_temp.as_call('pd-sece', 'pend_checklist', jsonb_build_object('id', v_tarefa, 'indice', 0, 'feito', true));
  r := pg_temp.as_call('pd-sece', 'pend_checklist', jsonb_build_object('id', v_tarefa, 'indice', 1, 'feito', true));
  r := pg_temp.as_call('pd-sece', 'pend_concluir', jsonb_build_object('id', v_tarefa, 'nota', 'Faltava uma certidão; a família trouxe.'));
  v_out := v_out || jsonb_build_object('passo', 'P10. Marca a lista e conclui no prazo', 'ok', r ->> 'situacao' = 'CONCLUIDA' and (r ->> 'no_prazo')::boolean, 'erro', r ->> 'erro');

  r := pg_temp.as_call('pd-prof', 'pend_concluir', jsonb_build_object('id', v_tarefa));
  v_out := v_out || jsonb_build_object('passo', 'P11. Professor(a) não conclui pendência de outro posto', 'ok', pg_temp.ok_erro(r, '42501'), 'erro', r ->> 'erro');

  r := pg_temp.as_call('pd-dir', 'pend_chefia_acao', jsonb_build_object('id', v_tarefa, 'acao', 'DEVOLVER', 'texto', 'Conferir também os comprovantes de endereço.'));
  r2 := pg_temp.as_call('pd-sece', 'pend_item', jsonb_build_object('id', v_tarefa));
  v_out := v_out || jsonb_build_object('passo', 'P12. Direção devolve; volta aberta, com a lista desmarcada e o motivo visível', 'ok',
    r ->> 'situacao' = 'ABERTA' and r2 -> 'ultima_cobranca' ->> 'texto' like 'Conferir também%'
    and not exists (select 1 from jsonb_array_elements(r2 -> 'checklist') i where (i ->> 'feito')::boolean), 'erro', coalesce(r ->> 'erro', r2 ->> 'erro'));

  r := pg_temp.as_call('pd-dir', 'pend_chefia_acao', jsonb_build_object('id', v_tarefa, 'acao', 'COBRAR', 'texto', 'Preciso disso até amanhã.'));
  v_out := v_out || jsonb_build_object('passo', 'P13. Direção cobra', 'ok', r -> 'ultima_cobranca' ->> 'texto' = 'Preciso disso até amanhã.', 'erro', r ->> 'erro');

  -- ---------------------------------------------------------------- automáticas
  select id into v_auto from iara.pendencias where situacao = 'ABERTA' and origem = 'AUTOMATICA' and staff_id = v_prof limit 1;
  r := pg_temp.as_call('pd-prof', 'pend_concluir', jsonb_build_object('id', v_auto));
  v_out := v_out || jsonb_build_object('passo', 'P14. Automática não se conclui à mão (resolve-se no módulo)', 'ok', pg_temp.ok_erro(r, '22023'), 'erro', r ->> 'erro');

  select id into v_alheia from iara.pendencias where situacao = 'ABERTA' and unit_id = v_outra and papel = 'DIRETOR_UNIDADE' limit 1;
  r := pg_temp.as_call('pd-prof', 'pend_item', jsonb_build_object('id', v_alheia));
  v_out := v_out || jsonb_build_object('passo', 'P15. Ninguém abre pendência de fora da sua alçada', 'ok', pg_temp.ok_erro(r, '42501'), 'erro', r ->> 'erro');

  -- chamada lançada no módulo: a pendência fecha sozinha na sincronização
  select (ref_id)::uuid, id into v_classe, v_chamada from iara.pendencias where situacao = 'ABERTA' and tipo = 'CHAMADA' and unit_id = v_unit limit 1;
  if v_classe is not null then
    insert into iara.frequencia_registros (class_id, data, registrado_label, is_demo)
    select v_classe, split_part(chave, ':', 3)::date, 'teste', true from iara.pendencias where id = v_chamada;
    perform iara.pend_sincronizar(v_unit);
  end if;
  v_out := v_out || jsonb_build_object('passo', 'P16. Chamada lançada: a pendência fecha sozinha como resolvida no módulo', 'ok',
    v_classe is null or exists (select 1 from iara.pendencias where id = v_chamada and situacao = 'CONCLUIDA' and concluida_por_label = 'Resolvida no módulo'));

  -- ---------------------------------------------------------------- procedimentos
  select count(*) into v_ativas from iara.education_units where status = 'ATIVA';
  r := pg_temp.as_call('pd-sec', 'pend_rotina_salvar', jsonb_build_object('titulo', 'Teste: conferência mensal da secretaria', 'procedimento', 'Conferir o arquivo e as pastas dos alunos.',
         'checklist', jsonb_build_array('Arquivo', 'Pastas'), 'papel', 'SECRETARIA_ESCOLAR', 'alvo', 'TODAS', 'periodicidade', 'MENSAL', 'dia', 1, 'prazo_dias', 28,
         'inicio', date_trunc('month', iara.hoje_local())::date));
  v_rot := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'P17. Secretário cadastra procedimento mensal para todas as secretarias: uma pendência por unidade ativa', 'ok',
    (r ->> 'geradas')::int = v_ativas and (select count(*) from iara.pendencias where rotina_id = v_rot) = v_ativas, 'erro', r ->> 'erro');

  select count(distinct staff_id) into v_regentes from iara.pend_regentes(v_unit);
  r := pg_temp.as_call('pd-dir', 'pend_rotina_salvar', jsonb_build_object('titulo', 'Teste: revisar o planejamento quinzenal', 'procedimento', 'Revisar o planejamento e os registros de aula.',
         'papel', 'PROFESSOR', 'periodicidade', 'MENSAL', 'dia', 1, 'prazo_dias', 28, 'inicio', date_trunc('month', iara.hoje_local())::date));
  v_out := v_out || jsonb_build_object('passo', 'P18. Direção cadastra procedimento da unidade para os professores: um por regente', 'ok',
    (r ->> 'geradas')::int = v_regentes and not exists (select 1 from iara.pendencias q where q.rotina_id = (r ->> 'id')::uuid and q.unit_id <> v_unit), 'erro', r ->> 'erro');

  r := pg_temp.as_call('pd-dir', 'pend_rotina_salvar', jsonb_build_object('titulo', 'Teste: procedimento da Central', 'procedimento', 'Não pode: a direção não manda na Central.',
         'papel', 'ANALISTA_CENTRAL', 'periodicidade', 'MENSAL'));
  v_out := v_out || jsonb_build_object('passo', 'P19. Direção não cadastra procedimento para a SEDUC', 'ok', pg_temp.ok_erro(r, '42501'), 'erro', r ->> 'erro');

  r := pg_temp.as_call('pd-dir', 'pend_rotinas', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P20. Direção edita os procedimentos da unidade e só vê os da rede que valem para ela', 'ok',
    r ->> 'escopo' = 'UNIDADE'
    and not exists (select 1 from jsonb_array_elements(r -> 'rotinas') x where (x ->> 'editavel')::boolean <> (x ->> 'alvo' = 'UNIDADE'))
    and exists (select 1 from jsonb_array_elements(r -> 'rotinas') x where x ->> 'alvo' = 'UNIDADE'), 'erro', r ->> 'erro');

  -- ---------------------------------------------------------------- alcance da SEDUC
  r := pg_temp.as_call('pd-sup', 'pend_equipe', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P21. Superintendência vê unidades e setores', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'grupos') g where g ->> 'tipo' = 'SETOR')
    and exists (select 1 from jsonb_array_elements(r -> 'grupos') g where g ->> 'tipo' in ('CMEI', 'ESCOLA')), 'erro', r ->> 'erro');

  r := pg_temp.as_call('pd-ger', 'pend_equipe', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P22. Gerência do apoio vê os núcleos e o AEE, não as pendências da secretaria escolar', 'ok',
    r ? 'grupos' and pg_temp.ok_erro(pg_temp.as_call('pd-ger', 'pend_item', jsonb_build_object('id', v_tarefa)), '42501'), 'erro', r ->> 'erro');

  select id into v_cmei from iara.education_units where status = 'ATIVA' and unit_type = 'CMEI' order by id limit 1;
  select id into v_escola from iara.education_units where status = 'ATIVA' and unit_type = 'ESCOLA' order by id limit 1;
  v_out := v_out || jsonb_build_object('passo', 'P23. Gerência de Educação Infantil alcança CMEI e não escola', 'ok',
    pg_temp.as_call('pd-gei', 'pend_equipe', jsonb_build_object('grupo', 'U:' || v_cmei)) ->> 'nivel' = 'grupo'
    and pg_temp.ok_erro(pg_temp.as_call('pd-gei', 'pend_equipe', jsonb_build_object('grupo', 'U:' || v_escola)), '42501'));

  r := pg_temp.as_call('pd-api', 'pend_minhas', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P24. Profissional do apoio vê os casos em triagem dele(a)', 'ok', r ? 'itens', 'erro', r ->> 'erro');

  -- ---------------------------------------------------------------- estatísticas
  r := pg_temp.as_call('pd-pref', 'pend_estatisticas', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P25. Prefeito vê estatísticas sem nomes', 'ok',
    (r -> 'totais' ->> 'abertas')::int > 0 and r -> 'pessoas' = 'null'::jsonb and jsonb_array_length(r -> 'evolucao') = 12, 'erro', r ->> 'erro');

  r := pg_temp.as_call('pd-sec', 'pend_estatisticas', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P26. Secretário vê estatísticas com os postos mais atrasados', 'ok',
    jsonb_typeof(r -> 'pessoas') = 'array' and (r ->> 'nomes')::boolean, 'erro', r ->> 'erro');

  r := pg_temp.as_call('pd-pref', 'pend_minhas', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P27. Prefeito não tem central própria (só estatísticas)', 'ok', pg_temp.ok_erro(r, '42501'), 'erro', r ->> 'erro');

  r := pg_temp.as_call('pd-pref', 'pend_mapa', jsonb_build_object('camada', 'pend_atrasadas'));
  v_out := v_out || jsonb_build_object('passo', 'P28. Mapa das atrasadas por unidade', 'ok', jsonb_array_length(r -> 'pontos') > 0, 'erro', r ->> 'erro');

  r := pg_temp.as_call('pd-dir', 'pend_contador', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P29. Contador da direção traz as atrasadas da equipe', 'ok', (r ->> 'abertas')::int >= 1 and r ? 'equipe_atrasadas', 'erro', r ->> 'erro');

  r := pg_temp.as_call('pd-sece', 'pend_estatisticas', '{}');
  v_out := v_out || jsonb_build_object('passo', 'P30. Secretaria escolar não vê estatísticas da rede', 'ok', pg_temp.ok_erro(r, '42501'), 'erro', r ->> 'erro');

  raise exception 'RESULTADO: %', v_out;
end $$;
