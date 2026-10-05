-- Cadastro 360º de alunos e responsáveis. Roda numa transação revertida (não deixa resíduo).
-- Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/cadastro_pessoas.sql
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
  r jsonb;
  v_unit integer := (iara.setting('demo_unit_maria'))::int;
  v_aluno uuid;
  v_resp uuid;
  v_resp2 uuid;
  v_outro uuid;
  v_addr_antes uuid;
  v_seed uuid;
  v_seed_raca text;
  v_seed_addr uuid;
  -- ponto dentro de Maringá (Zona 7, perto da UEM)
  v_end jsonb := '{"logradouro": "Rua Teste do Cadastro", "numero": "100", "bairro": "Zona 07", "cep": "87020-025", "lat": -23.4065, "lng": -51.9405, "precisao": "PONTO_NO_MAPA", "zona": "URBANA"}';
begin
  perform iara.session_create('SECRETARIO', null, 'test-secretario', 'teste');

  r := pg_temp.as_call('test-analista', 'alunos_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', '1. Secretaria: lista da rede', 'escopo', r ->> 'escopo', 'total', r ->> 'total',
    'completos', r #>> '{contagem,completos}', 'pendencias', r -> 'pendencias_frequentes', 'itens', jsonb_array_length(r -> 'itens'));

  r := pg_temp.as_call('test-diretor', 'alunos_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', '2. Unidade: só os seus alunos', 'escopo', r ->> 'escopo', 'unidade', r ->> 'unidade', 'total', r ->> 'total');
  select s.id into v_outro from iara.students s
  where not exists (select 1 from iara.enrollments e where e.student_id = s.id and e.unit_id = v_unit)
    and not exists (select 1 from iara.waiting_list_entries w where w.student_id = s.id and w.preferred_unit_id = v_unit) limit 1;
  r := pg_temp.as_call('test-diretor', 'aluno_cadastro', jsonb_build_object('id', v_outro));
  v_out := v_out || jsonb_build_object('passo', '3. Unidade abre aluno de outra unidade (deve negar)', 'r', r ->> 'erro');

  r := pg_temp.as_call('test-diretor', 'aluno_salvar', jsonb_build_object('nome', 'Teste Cadastro Silva', 'nascimento', '2023-03-10', 'sexo', 'F',
        'cor_raca', 'PARDA', 'nacionalidade', 'BRASILEIRA', 'naturalidade_municipio', 'Maringá', 'naturalidade_uf', 'PR', 'cpf', '111.111.111-11',
        'endereco', v_end || '{"modo": "PROPRIO"}'));
  v_out := v_out || jsonb_build_object('passo', '4. CPF inválido (deve recusar)', 'r', r ->> 'erro');

  r := pg_temp.as_call('test-diretor', 'aluno_salvar', jsonb_build_object('nome', 'Teste Cadastro Silva', 'nascimento', '2023-03-10', 'sexo', 'F',
        'cor_raca', 'PARDA', 'nacionalidade', 'BRASILEIRA', 'naturalidade_municipio', 'Maringá', 'naturalidade_uf', 'PR', 'cpf', '529.982.247-25',
        'filiacao_1', 'Mãe Teste Silva', 'endereco', v_end || '{"modo": "PROPRIO"}'));
  v_aluno := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', '5. Unidade cadastra criança (endereço próprio)', 'ok', r ->> 'ok', 'erro', r ->> 'erro',
    'territorio', r #>> '{cadastro,endereco,territorio}', 'pendencias', r #> '{cadastro,pendencias}', 'pct', r #>> '{cadastro,completo_pct}');

  r := pg_temp.as_call('test-diretor', 'alunos_lista', '{"q": "teste cadastro"}');
  v_out := v_out || jsonb_build_object('passo', '6. A unidade encontra quem cadastrou', 'achou', r ->> 'total');

  r := pg_temp.as_call('test-analista', 'responsavel_salvar', jsonb_build_object('nome', 'Responsável Teste Silva', 'nascimento', '1990-05-01', 'sexo', 'F',
        'cpf', '390.533.447-05', 'telefone', '(44) 90000-1111', 'estado_civil', 'SOLTEIRO', 'renda_familiar', 2500, 'cadunico', true,
        'endereco', v_end, 'crianca', jsonb_build_object('id', v_aluno, 'parentesco', 'MAE')));
  v_resp := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', '7. Secretaria cadastra responsável e vincula à criança', 'ok', r ->> 'ok', 'erro', r ->> 'erro',
    'faixa', r #>> '{cadastro,responsavel,faixa_renda}', 'criancas', jsonb_array_length(r #> '{cadastro,criancas}'), 'pendencias', r #> '{cadastro,pendencias}');

  r := pg_temp.as_call('test-analista', 'responsavel_salvar', jsonb_build_object('nome', 'Outra Pessoa', 'cpf', '390.533.447-05'));
  v_out := v_out || jsonb_build_object('passo', '8. CPF já cadastrado (deve recusar)', 'r', coalesce(r ->> 'erro', r ->> 'mensagem'));

  r := pg_temp.as_call('test-diretor', 'aluno_salvar', jsonb_build_object('id', v_aluno, 'endereco', '{"modo": "RESPONSAVEL"}'::jsonb));
  v_out := v_out || jsonb_build_object('passo', '9. Criança passa a usar o endereço do responsável', 'ok', r ->> 'ok', 'mesmo', r #>> '{cadastro,endereco_do_responsavel}');

  select address_id into v_addr_antes from iara.guardians where id = v_resp;
  r := pg_temp.as_call('test-analista', 'responsavel_salvar', jsonb_build_object('id', v_resp,
        'endereco', v_end || '{"logradouro": "Avenida Nova", "numero": "200", "lat": -23.4210, "lng": -51.9330}'));
  v_out := v_out || jsonb_build_object('passo', '10. Responsável muda de endereço: a criança muda junto', 'criancas_mudaram', r ->> 'criancas_mudaram',
    'aluno_no_novo', (select s.address_id = g.address_id from iara.students s, iara.guardians g where s.id = v_aluno and g.id = v_resp));

  r := pg_temp.as_call('test-diretor', 'vinculo_encerrar', jsonb_build_object('aluno_id', v_aluno, 'responsavel_id', v_resp, 'motivo', 'Teste de encerramento'));
  v_out := v_out || jsonb_build_object('passo', '11. Encerrar o único vínculo (deve recusar)', 'r', r ->> 'erro');

  r := pg_temp.as_call('test-analista', 'responsavel_salvar', jsonb_build_object('nome', 'Avó Teste Silva', 'nascimento', '1960-01-01', 'sexo', 'F',
        'telefone', '(44) 90000-2222', 'crianca', jsonb_build_object('id', v_aluno, 'parentesco', 'AVO')));
  v_resp2 := (r ->> 'id')::uuid;
  r := pg_temp.as_call('test-diretor', 'vinculo_salvar', jsonb_build_object('aluno_id', v_aluno, 'responsavel_id', v_resp2, 'parentesco', 'AVO',
        'principal', true, 'pode_buscar', true, 'recebe_avisos', true, 'situacao_legal', 'A_VERIFICAR'));
  r := pg_temp.as_call('test-diretor', 'vinculo_encerrar', jsonb_build_object('aluno_id', v_aluno, 'responsavel_id', v_resp2, 'motivo', 'Mudou de cidade'));
  v_out := v_out || jsonb_build_object('passo', '12. Segundo responsável: vira principal e depois é encerrado (histórico)', 'ok', r ->> 'ok',
    'principal_agora', (select g.full_name from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
                        where sg.student_id = v_aluno and sg.is_primary and sg.end_date is null),
    'encerrados', (select count(*) from iara.student_guardians where student_id = v_aluno and end_date is not null));

  r := pg_temp.as_call('test-analista', 'domicilio_salvar', jsonb_build_object('responsavel_id', v_resp, 'nome', 'Irmão Teste Silva', 'parentesco', 'IRMAO',
        'nascimento', '2010-02-02', 'ocupacao', 'Estudante'));
  r := pg_temp.as_call('test-analista', 'responsavel_cadastro', jsonb_build_object('id', v_resp));
  v_out := v_out || jsonb_build_object('passo', '13. Composição familiar', 'domicilio', jsonb_array_length(r -> 'domicilio'),
    'pessoas', r ->> 'pessoas_domicilio', 'renda_per_capita', r ->> 'renda_per_capita');

  r := pg_temp.as_call('test-diretor', 'aluno_salvar', jsonb_build_object('id', v_aluno, 'aee', true,
        'sensiveis', jsonb_build_object('necessidade_especial', 'TEA nível 1 (teste)', 'alergias_alimentares', 'Lactose')));
  v_out := v_out || jsonb_build_object('passo', '14. Unidade registra dado sensível (tem permissão)', 'ok', r ->> 'ok', 'sens', r #>> '{cadastro,sensiveis,necessidade_especial}');
  r := pg_temp.as_call('test-analista', 'aluno_salvar', jsonb_build_object('id', v_aluno, 'sensiveis', jsonb_build_object('alertas_saude', 'x')));
  v_out := v_out || jsonb_build_object('passo', '15. Central sem permissão de dado sensível (deve recusar)', 'r', r ->> 'erro');

  r := pg_temp.as_call('test-secretario', 'aluno_cadastro', jsonb_build_object('id', v_aluno));
  v_out := v_out || jsonb_build_object('passo', '16. Secretário vê documentos mascarados', 'cpf', r #>> '{aluno,cpf}', 'mascarado', r ->> 'documentos_mascarados',
    'sensiveis', r -> 'sensiveis');

  r := pg_temp.as_call('test-diretor', 'student_detail', jsonb_build_object('student_id', v_aluno));
  v_out := v_out || jsonb_build_object('passo', '16b. Ficha 360º do aluno (permissões do perfil)', 'erro', r ->> 'erro',
    'completo', r #>> '{registry,complete_pct}', 'pendencias', r #> '{registry,pending}', 'raca', r #>> '{student,race_color}');
  r := pg_temp.as_call('test-analista', 'guardian_detail', jsonb_build_object('guardian_id', v_resp));
  v_out := v_out || jsonb_build_object('passo', '16c. Ficha 360º do responsável', 'erro', r ->> 'erro', 'completo', r #>> '{registry,complete_pct}',
    'domicilio', jsonb_array_length(r -> 'household_members'), 'zona', r #>> '{address,zone}');

  r := pg_temp.as_call('test-cidadao', 'alunos_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', '17. Cidadã tenta a lista de alunos (deve negar)', 'r', r ->> 'erro');

  r := pg_temp.as_call('test-analista', 'localizar_ponto', '{"lat": -23.4065, "lng": -51.9405, "faixa_id": 1}');
  v_out := v_out || jsonb_build_object('passo', '18. Localizar ponto', 'territorio', r ->> 'territorio', 'bairro', r ->> 'bairro',
    'unidade_mais_proxima', r #>> '{unidades,0,nome}', 'distancia_m', r #>> '{unidades,0,distancia_m}');

  -- limpeza: edição de um aluno do cenário por sessão volta ao original
  select s.id, s.race_color, s.address_id into v_seed, v_seed_raca, v_seed_addr from iara.students s
  join iara.enrollments e on e.student_id = s.id and e.unit_id = v_unit and e.status = 'ACTIVE' where s.created_by is null limit 1;
  r := pg_temp.as_call('test-diretor', 'aluno_salvar', jsonb_build_object('id', v_seed, 'cor_raca', 'AMARELA', 'endereco', v_end || '{"modo": "PROPRIO"}'));
  r := (select iara.demo_purge_session_data('DEMO'));
  v_out := v_out || jsonb_build_object('passo', '19. Limpeza da demonstração desfaz a edição',
    'raca_volta', (select race_color = v_seed_raca from iara.students where id = v_seed),
    'endereco_volta', (select address_id = v_seed_addr from iara.students where id = v_seed),
    'aluno_teste_removido', not exists (select 1 from iara.students where id = v_aluno),
    'responsaveis_removidos', not exists (select 1 from iara.guardians where id in (v_resp, v_resp2)),
    'domicilio_removido', not exists (select 1 from iara.household_members where guardian_id = v_resp));

  raise exception 'RESULTADO: %', v_out;  -- reverte tudo
end $$;
