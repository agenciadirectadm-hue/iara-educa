-- Sprint 4: conselho de classe, resultado final, histórico escolar, biblioteca, patrimônio e peso e medidas — quem faz o quê e as regras.
-- Roda numa transação revertida (não deixa resíduo). Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/sprint4.sql
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
  v_t0 timestamptz := now();
  v_unit integer;
  v_outra integer;
  v_turma uuid;
  v_turma_ei uuid;
  v_aluno uuid;
  v_aluno2 uuid;
  v_aluno3 uuid;
  v_g uuid;
  v_ex uuid;
  v_ex2 uuid;
  v_ex3 uuid;
  v_tombo text;
  v_emp uuid;
  v_tit uuid;
  v_bem uuid;
  v_bem2 uuid;
  v_n integer;
  v_cod text;
begin
  -- escola de fundamental com bens patrimoniais, biblioteca e turmas
  select u.id into v_unit from iara.education_units u where u.status = 'ATIVA' and u.unit_type <> 'CMEI'
    and exists (select 1 from iara.materiais m where m.unit_id = u.id and m.patrimonio is not null and m.situacao_patrimonio = 'EM_USO')
    and (select count(*) from iara.biblioteca_exemplares x where x.unit_id = u.id) > 30 order by u.id limit 1;
  select u.id into v_outra from iara.education_units u where u.status = 'ATIVA' and u.id <> v_unit and u.unit_type <> 'CMEI' order by u.id limit 1;
  perform iara.session_create('PROFESSOR', v_unit, 's4-prof', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_unit, 's4-dir', 'teste');
  perform iara.session_create('SECRETARIA_ESCOLAR', v_unit, 's4-sec', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_outra, 's4-dir2', 'teste');
  perform iara.session_create('PREFEITO', null, 's4-pref', 'teste');
  perform iara.session_create('ALMOXARIFADO', null, 's4-almox', 'teste');
  perform iara.session_create('NUTRICAO', null, 's4-nutri', 'teste');
  v_turma := (select (t ->> 'id')::uuid from jsonb_array_elements(pg_temp.as_call('s4-prof', 'me', '{}') -> 'turmas') t limit 1);
  select e.student_id into v_aluno from iara.enrollments e where e.class_id = v_turma and e.status = 'ACTIVE' order by e.student_id limit 1;
  select e.student_id into v_aluno2 from iara.enrollments e where e.class_id = v_turma and e.status = 'ACTIVE' order by e.student_id offset 1 limit 1;
  select e.student_id into v_aluno3 from iara.enrollments e where e.class_id = v_turma and e.status = 'ACTIVE' order by e.student_id offset 2 limit 1;

  -- conselho de classe
  r := pg_temp.as_call('s4-prof', 'conselho_turma', jsonb_build_object('class_id', v_turma, 'etapa', 3));
  v_out := v_out || jsonb_build_object('passo', 'C1. Professor abre o conselho do 3º bimestre da sua turma (médias, frequência, abaixo da média)', 'ok',
    r ->> 'erro' is null and jsonb_array_length(r -> 'alunos') > 0 and (r -> 'alunos' -> 0) ? 'abaixo' and not (r ->> 'pode_conduzir')::boolean, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s4-pref', 'conselho_turma', jsonb_build_object('class_id', v_turma, 'etapa', 3));
  v_out := v_out || jsonb_build_object('passo', 'C2. Prefeito não abre o conselho (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  delete from iara.conselhos_classe where class_id = v_turma and ano = 2026 and etapa = 3;
  r := pg_temp.as_call('s4-prof', 'conselho_salvar', jsonb_build_object('class_id', v_turma, 'etapa', 3,
    'deliberacoes', jsonb_build_array(jsonb_build_object('student_id', v_aluno, 'observacao', 'Avançou na leitura; precisa de apoio em frações.'))));
  v_out := v_out || jsonb_build_object('passo', 'C3. Professor registra observação do aluno', 'ok', r ->> 'erro' is null
    and exists (select 1 from jsonb_array_elements(r -> 'alunos') a where (a ->> 'student_id')::uuid = v_aluno and a -> 'deliberacao' ->> 'observacao' like 'Avançou%'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s4-prof', 'conselho_salvar', jsonb_build_object('class_id', v_turma, 'etapa', 3, 'concluir', true));
  v_out := v_out || jsonb_build_object('passo', 'C4. Professor não conclui o conselho (direção conclui)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s4-dir', 'conselho_salvar', jsonb_build_object('class_id', v_turma, 'etapa', 3, 'concluir', true));
  v_out := v_out || jsonb_build_object('passo', 'C5. Concluir exige participantes e ata', 'ok', pg_temp.ok_erro(r, '22023'));
  v_n := (select count(*) from iara.notifications where event_type = 'CONSELHO_CLASSE');
  r := pg_temp.as_call('s4-dir', 'conselho_salvar', jsonb_build_object('class_id', v_turma, 'etapa', 3, 'participantes', 'Direção, coordenação e professores da turma',
    'ata', 'A turma avançou em leitura; três alunos seguem para o reforço com acompanhamento quinzenal.', 'concluir', true,
    'deliberacoes', jsonb_build_array(jsonb_build_object('student_id', v_aluno, 'encaminhamentos', jsonb_build_array('REFORCO', 'PLANO_INTERVENCAO'), 'comunicar_familia', true))));
  v_out := v_out || jsonb_build_object('passo', 'C6. Direção conclui: plano de intervenção aberto e família avisada', 'ok', r -> 'conselho' ->> 'situacao' = 'CONCLUIDO'
    and exists (select 1 from iara.planos_intervencao pl where pl.student_id = v_aluno and pl.ano = 2026 and pl.situacao = 'ATIVO')
    and (select count(*) from iara.notifications where event_type = 'CONSELHO_CLASSE') > v_n, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s4-dir', 'conselho_salvar', jsonb_build_object('class_id', v_turma, 'etapa', 3, 'reabrir', true, 'motivo', 'curto'));
  v_out := v_out || jsonb_build_object('passo', 'C7. Reabrir exige motivo', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s4-dir', 'conselho_salvar', jsonb_build_object('class_id', v_turma, 'etapa', 5, 'participantes', 'Direção e professores',
    'ata', 'Conselho final da turma com os resultados do ano letivo.', 'concluir', true));
  v_out := v_out || jsonb_build_object('passo', 'C8. Conselho final não fecha antes do fim do 4º bimestre (só prévia)', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s4-dir', 'conselho_salvar', jsonb_build_object('class_id', v_turma, 'etapa', 5,
    'deliberacoes', jsonb_build_array(jsonb_build_object('student_id', v_aluno, 'situacao', 'APROVADO_CONSELHO', 'justificativa', 'curta'))));
  v_out := v_out || jsonb_build_object('passo', 'C9. Aprovação pelo conselho exige justificativa', 'ok', pg_temp.ok_erro(r, '22023'));
  select c.id into v_turma_ei from iara.classes c join iara.grade_levels gl on gl.id = c.grade_level_id where gl.code = 'PRE' and c.status = 'ATIVA'
    and exists (select 1 from iara.enrollments e where e.class_id = c.id and e.status = 'ACTIVE') order by c.id limit 1;
  perform iara.session_create('DIRETOR_UNIDADE', (select unit_id from iara.classes where id = v_turma_ei), 's4-dir-ei', 'teste');
  r := pg_temp.as_call('s4-dir-ei', 'conselho_salvar', jsonb_build_object('class_id', v_turma_ei, 'etapa', 5,
    'deliberacoes', jsonb_build_array(jsonb_build_object('student_id', (select student_id from iara.enrollments where class_id = v_turma_ei and status = 'ACTIVE' limit 1),
      'situacao', 'RETIDO', 'justificativa', 'Tentativa de retenção na educação infantil.'))));
  v_out := v_out || jsonb_build_object('passo', 'C10. Educação infantil não tem retenção (LDB, art. 31, I)', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s4-dir', 'resultado_previa', '{}');
  v_out := v_out || jsonb_build_object('passo', 'C11. Prévia do resultado final da unidade (quem vai ao conselho)', 'ok', r ->> 'erro' is null and r ? 'resumo' and jsonb_array_length(r -> 'turmas') > 0, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s4-prof', 'resultado_previa', '{}');
  v_out := v_out || jsonb_build_object('passo', 'C12. Professor não vê a prévia da unidade', 'ok', pg_temp.ok_erro(r, '42501'));

  -- histórico escolar
  select sg.guardian_id into v_g from iara.student_guardians sg where sg.student_id = v_aluno and sg.end_date is null order by sg.is_primary desc limit 1;
  perform pg_temp.sessao_familia('s4-fam', v_g);
  r := pg_temp.as_call('s4-fam', 'historico_aluno', jsonb_build_object('student_id', v_aluno));
  v_out := v_out || jsonb_build_object('passo', 'H1. Família vê o histórico: anos concluídos e o ano em curso sem a prévia do conselho', 'ok', r ->> 'erro' is null
    and jsonb_array_length(r -> 'anos') >= 1 and not ((r -> 'em_curso' -> 'calculada') ? 'situacao'), 'erro', coalesce(r ->> 'erro', r::text));
  r := pg_temp.as_call('s4-fam', 'declaracao_emitir', jsonb_build_object('student_id', v_aluno, 'tipo', 'HISTORICO'));
  v_cod := r ->> 'codigo';
  v_out := v_out || jsonb_build_object('passo', 'H2. Histórico escolar emitido com código (vale 5 anos)', 'ok', r ->> 'tipo' = 'HISTORICO' and jsonb_array_length(r -> 'conteudo' -> 'historico') >= 1
    and (r ->> 'valida_ate')::date > current_date + 1800, 'erro', r ->> 'erro');
  r := api.declaracao_verificar(jsonb_build_object('codigo', v_cod));
  v_out := v_out || jsonb_build_object('passo', 'H3. Verificação pública do histórico (só resumo e nome abreviado)', 'ok', (r ->> 'encontrada')::boolean and r ->> 'situacao' = 'VALIDA'
    and not (r ? 'conteudo'), 'erro', r::text);
  r := pg_temp.as_call('s4-fam', 'declaracao_emitir', jsonb_build_object('student_id', (iara.setting('demo_student_ana'))::uuid, 'tipo', 'HISTORICO'));
  v_out := v_out || jsonb_build_object('passo', 'H4. Família não emite documento de criança que não é dela', 'ok', pg_temp.ok_erro(r, '42501'));

  -- biblioteca
  select x.id, x.tombo into v_ex, v_tombo from iara.biblioteca_exemplares x where x.unit_id = v_unit and x.estado in ('BOM', 'REGULAR')
    and not exists (select 1 from iara.biblioteca_emprestimos m where m.exemplar_id = x.id and m.devolvido_em is null)
    and not exists (select 1 from iara.biblioteca_reservas b where b.titulo_id = x.titulo_id and b.unit_id = v_unit and b.situacao in ('ATIVA', 'DISPONIVEL')) order by x.tombo limit 1;
  update iara.biblioteca_emprestimos set devolvido_em = now() where student_id in (v_aluno, v_aluno2) and devolvido_em is null;
  r := pg_temp.as_call('s4-sec', 'biblioteca_emprestar', jsonb_build_object('tombo', v_tombo, 'student_id', v_aluno));
  v_emp := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'B1. Secretaria empresta pelo tombo (prazo de 14 dias no fundamental)', 'ok', r ->> 'erro' is null
    and (r ->> 'prevista')::date = iara.bib_dia_util(iara.hoje_local() + 14), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s4-sec', 'biblioteca_emprestar', jsonb_build_object('tombo', v_tombo, 'student_id', v_aluno2));
  v_out := v_out || jsonb_build_object('passo', 'B2. Exemplar emprestado não sai de novo', 'ok', pg_temp.ok_erro(r, '22023'));
  select x.id into v_ex2 from iara.biblioteca_exemplares x where x.unit_id = v_unit and x.estado in ('BOM', 'REGULAR') and x.id <> v_ex
    and not exists (select 1 from iara.biblioteca_emprestimos m where m.exemplar_id = x.id and m.devolvido_em is null)
    and not exists (select 1 from iara.biblioteca_reservas b where b.titulo_id = x.titulo_id and b.unit_id = v_unit and b.situacao in ('ATIVA', 'DISPONIVEL')) order by x.tombo offset 1 limit 1;
  select x.id into v_ex3 from iara.biblioteca_exemplares x where x.unit_id = v_unit and x.estado in ('BOM', 'REGULAR') and x.id not in (v_ex, v_ex2)
    and not exists (select 1 from iara.biblioteca_emprestimos m where m.exemplar_id = x.id and m.devolvido_em is null)
    and not exists (select 1 from iara.biblioteca_reservas b where b.titulo_id = x.titulo_id and b.unit_id = v_unit and b.situacao in ('ATIVA', 'DISPONIVEL')) order by x.tombo offset 2 limit 1;
  r := pg_temp.as_call('s4-sec', 'biblioteca_emprestar', jsonb_build_object('exemplar_id', v_ex2, 'student_id', v_aluno));
  r := pg_temp.as_call('s4-sec', 'biblioteca_emprestar', jsonb_build_object('exemplar_id', v_ex3, 'student_id', v_aluno));
  v_out := v_out || jsonb_build_object('passo', 'B3. Limite de 2 livros ao mesmo tempo', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s4-fam', 'biblioteca_renovar', jsonb_build_object('id', v_emp));
  v_out := v_out || jsonb_build_object('passo', 'B4. Família renova pelo portal (+14 dias)', 'ok', (r ->> 'renovacoes')::int = 1 and (r ->> 'prevista')::date = iara.bib_dia_util(iara.bib_dia_util(iara.hoje_local() + 14) + 14), 'erro', r ->> 'erro');
  select titulo_id into v_tit from iara.biblioteca_exemplares where id = v_ex;
  perform pg_temp.sessao_familia('s4-fam2', (select sg.guardian_id from iara.student_guardians sg where sg.student_id = v_aluno2 and sg.end_date is null order by sg.is_primary desc limit 1));
  r := pg_temp.as_call('s4-fam2', 'biblioteca_reservar', jsonb_build_object('titulo_id', v_tit, 'student_id', v_aluno2));
  v_out := v_out || jsonb_build_object('passo', 'B5. Outra família reserva o título emprestado', 'ok', r ->> 'situacao' = 'ATIVA', 'erro', r ->> 'erro');
  r := pg_temp.as_call('s4-fam', 'biblioteca_renovar', jsonb_build_object('id', v_emp));
  v_out := v_out || jsonb_build_object('passo', 'B6. Com reserva de outro leitor, não renova', 'ok', pg_temp.ok_erro(r, '22023'));
  v_n := (select count(*) from iara.notifications where event_type = 'BIBLIOTECA');
  r := pg_temp.as_call('s4-sec', 'biblioteca_devolver', jsonb_build_object('tombo', v_tombo, 'estado', 'BOM'));
  v_out := v_out || jsonb_build_object('passo', 'B7. Devolução avisa a família da reserva', 'ok', (r ->> 'reserva_avisada')::boolean and (select count(*) from iara.notifications where event_type = 'BIBLIOTECA') > v_n, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s4-sec', 'biblioteca_emprestar', jsonb_build_object('tombo', v_tombo, 'student_id', v_aluno3));
  v_out := v_out || jsonb_build_object('passo', 'B8. Exemplar reservado só sai para quem reservou', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s4-dir2', 'biblioteca_emprestar', jsonb_build_object('tombo', v_tombo, 'student_id', v_aluno2));
  v_out := v_out || jsonb_build_object('passo', 'B9. Outra unidade não empresta o acervo da escola', 'ok', pg_temp.ok_erro(r, 'P0002'));
  r := pg_temp.as_call('s4-fam', 'familia_biblioteca', '{}');
  v_out := v_out || jsonb_build_object('passo', 'B10. Família vê o livro em aberto e o que leu no ano', 'ok', r ->> 'erro' is null
    and exists (select 1 from jsonb_array_elements(r) k where (k ->> 'student_id')::uuid = v_aluno and jsonb_array_length(k -> 'ativos') >= 1), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s4-sec', 'biblioteca_exemplar', jsonb_build_object('id', v_ex2, 'estado', 'BAIXADO', 'motivo', 'Livro rasgado'));
  v_out := v_out || jsonb_build_object('passo', 'B11. Exemplar emprestado não é baixado', 'ok', pg_temp.ok_erro(r, '22023'));

  -- patrimônio
  select m.id into v_bem from iara.materiais m where m.unit_id = v_unit and m.patrimonio is not null and m.situacao_patrimonio = 'EM_USO' order by m.patrimonio limit 1;
  select m.id into v_bem2 from iara.materiais m where m.unit_id = v_unit and m.patrimonio is not null and m.situacao_patrimonio = 'EM_USO' and m.id <> v_bem order by m.patrimonio limit 1;
  r := pg_temp.as_call('s4-dir', 'patrimonio_acao', jsonb_build_object('id', v_bem, 'acao', 'TRANSFERIR', 'destino_unit', v_outra, 'texto', 'A outra escola abriu turma nova.'));
  v_out := v_out || jsonb_build_object('passo', 'P1. Direção pede a transferência do bem', 'ok', r ->> 'situacao' = 'EM_TRANSFERENCIA', 'erro', r ->> 'erro');
  r := pg_temp.as_call('s4-dir', 'patrimonio_acao', jsonb_build_object('id', v_bem, 'acao', 'RECEBER'));
  v_out := v_out || jsonb_build_object('passo', 'P2. A origem não “recebe” o próprio bem', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s4-dir2', 'patrimonio_acao', jsonb_build_object('id', v_bem, 'acao', 'RECEBER', 'localizacao', 'Sala de informática'));
  v_out := v_out || jsonb_build_object('passo', 'P3. A unidade de destino recebe: o bem muda de unidade', 'ok', (r ->> 'unit_id')::int = v_outra and r ->> 'situacao' = 'EM_USO', 'erro', r ->> 'erro');
  r := pg_temp.as_call('s4-dir', 'patrimonio_acao', jsonb_build_object('id', v_bem2, 'acao', 'MANUTENCAO_ENVIO', 'texto', 'Não liga; enviado à assistência.'));
  r := pg_temp.as_call('s4-dir', 'patrimonio_acao', jsonb_build_object('id', v_bem2, 'acao', 'MANUTENCAO_RETORNO', 'estado', 'BOM', 'custo', 180));
  v_out := v_out || jsonb_build_object('passo', 'P4. Conserto: envio e retorno com custo no histórico', 'ok', r ->> 'situacao' = 'EM_USO'
    and exists (select 1 from jsonb_array_elements(r -> 'eventos') e where e ->> 'tipo' = 'MANUTENCAO_RETORNO' and (e ->> 'custo')::numeric = 180), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s4-dir', 'patrimonio_acao', jsonb_build_object('id', v_bem2, 'acao', 'SOLICITAR_BAIXA', 'texto', 'Sem conserto conforme laudo da assistência.'));
  r := pg_temp.as_call('s4-dir', 'patrimonio_acao', jsonb_build_object('id', v_bem2, 'acao', 'DECIDIR_BAIXA', 'aprovar', true, 'texto', 'Aprovo a baixa do bem.'));
  v_out := v_out || jsonb_build_object('passo', 'P5. A escola não aprova a própria baixa', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s4-almox', 'patrimonio_acao', jsonb_build_object('id', v_bem2, 'acao', 'DECIDIR_BAIXA', 'aprovar', true, 'texto', 'Baixa aprovada com base no laudo técnico.'));
  v_out := v_out || jsonb_build_object('passo', 'P6. A SEDUC (patrimônio) aprova a baixa', 'ok', r ->> 'situacao' = 'BAIXADO' and r ->> 'estado' = 'INSERVIVEL', 'erro', r ->> 'erro');
  delete from iara.inventarios where unit_id = v_unit and ano = extract(year from iara.hoje_local())::int;
  r := pg_temp.as_call('s4-sec', 'inventario', jsonb_build_object('acao', 'ABRIR'));
  v_out := v_out || jsonb_build_object('passo', 'P7. Abre o inventário do ano com os bens da unidade', 'ok', (r ->> 'aberto')::boolean and jsonb_array_length(r -> 'itens') > 0, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s4-sec', 'inventario', jsonb_build_object('acao', 'CONCLUIR'));
  v_out := v_out || jsonb_build_object('passo', 'P8. Não conclui com bem sem conferir', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s4-sec', 'inventario', jsonb_build_object('acao', 'CONFERIR', 'itens', (select jsonb_agg(jsonb_build_object('material_id', it.material_id, 'localizado', true, 'estado', 'BOM'))
         from iara.inventario_itens it join iara.inventarios i on i.id = it.inventario_id where i.unit_id = v_unit and i.ano = extract(year from iara.hoje_local())::int)));
  r := pg_temp.as_call('s4-sec', 'inventario', jsonb_build_object('acao', 'CONCLUIR'));
  v_out := v_out || jsonb_build_object('passo', 'P9. Conclui o inventário depois de conferir tudo', 'ok', r ->> 'situacao' = 'CONCLUIDO', 'erro', r ->> 'erro');

  -- peso e medidas
  delete from iara.antropometria where student_id = v_aluno3;
  insert into iara.antropometria (student_id, unit_id, class_id, data, peso_kg, altura_cm, imc, idade_meses, is_demo)
  values (v_aluno3, v_unit, v_turma, date '2026-08-17', 28, 130, round(28 / power(1.30, 2), 2), 100, true);
  r := pg_temp.as_call('s4-prof', 'antropometria_lancar', jsonb_build_object('class_id', v_turma, 'medidas', jsonb_build_array(jsonb_build_object('student_id', v_aluno3, 'peso', '28,4', 'altura', '131'))));
  v_out := v_out || jsonb_build_object('passo', 'A1. Professor registra peso e altura (IMC calculado)', 'ok', (r ->> 'gravados')::int = 1
    and exists (select 1 from iara.antropometria where student_id = v_aluno3 and data = iara.hoje_local() and imc = round(28.4 / power(1.31, 2), 2)),
    'erro', coalesce(r ->> 'erro', (select jsonb_agg(jsonb_build_object('d', data, 'imc', imc, 's', student_id = v_aluno3))::text from iara.antropometria where created_at >= v_t0)));
  r := pg_temp.as_call('s4-prof', 'antropometria_lancar', jsonb_build_object('class_id', v_turma, 'medidas', jsonb_build_array(jsonb_build_object('student_id', v_aluno3, 'peso', '28,4', 'altura', '110'))));
  v_out := v_out || jsonb_build_object('passo', 'A2. Altura menor que a anterior pede conferência e não grava', 'ok', (r ->> 'gravados')::int = 0 and jsonb_array_length(r -> 'conferir') = 1, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s4-dir2', 'antropometria_lancar', jsonb_build_object('class_id', v_turma, 'medidas', jsonb_build_array(jsonb_build_object('student_id', v_aluno3, 'peso', '28', 'altura', '131'))));
  v_out := v_out || jsonb_build_object('passo', 'A3. Outra unidade não registra medidas da turma', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s4-nutri', 'referencia_imc_importar', jsonb_build_object('fonte', 'Tabela de teste (não é a referência oficial)',
    'texto', format(E'sexo;idade_meses;L;M;S\n%s;%s;1;16;0,1', (select gender from iara.students where id = v_aluno3),
                    (select idade_meses from iara.antropometria where student_id = v_aluno3 and data = iara.hoje_local()))));
  v_out := v_out || jsonb_build_object('passo', 'A4. Nutrição importa a referência e as medidas são classificadas (escore z)', 'ok', (r ->> 'importadas')::int = 1
    and (select classificacao is not null and zscore is not null from iara.antropometria where student_id = v_aluno3 and data = iara.hoje_local()), 'erro', r ->> 'erro');
  perform pg_temp.sessao_familia('s4-fam3', (select sg.guardian_id from iara.student_guardians sg where sg.student_id = v_aluno3 and sg.end_date is null order by sg.is_primary desc limit 1));
  r := pg_temp.as_call('s4-fam3', 'antropometria_aluno', jsonb_build_object('student_id', v_aluno3));
  v_out := v_out || jsonb_build_object('passo', 'A5. Família vê as medidas e uma leitura sem rótulo nem escore', 'ok', r ->> 'erro' is null
    and not exists (select 1 from jsonb_array_elements(r -> 'medidas') m where m ? 'zscore' or m ? 'classificacao')
    and exists (select 1 from jsonb_array_elements(r -> 'medidas') m where m ->> 'leitura' is not null), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s4-dir', 'referencia_imc_importar', jsonb_build_object('fonte', 'Tentativa sem permissão', 'texto', 'M;60;1;16;0,1'));
  v_out := v_out || jsonb_build_object('passo', 'A6. Só a nutrição importa a referência', 'ok', pg_temp.ok_erro(r, '42501'));

  -- limpeza da demonstração
  r := iara.demo_purge_sprint4(v_t0);
  v_out := v_out || jsonb_build_object('passo', 'X1. Limpeza desfaz o que foi feito ao vivo (empréstimos, conselho, medidas, patrimônio)', 'ok',
    not exists (select 1 from iara.biblioteca_emprestimos where not is_demo and retirada_em >= v_t0) and not exists (select 1 from iara.antropometria where not is_demo and created_at >= v_t0)
    and not exists (select 1 from iara.conselhos_classe where not is_demo and created_at >= v_t0) and not exists (select 1 from iara.patrimonio_eventos where not is_demo and created_at >= v_t0)
    and (select unit_id from iara.materiais where id = v_bem) = v_unit, 'erro', r::text);

  raise exception 'RESULTADO: %', v_out;
end $$;
