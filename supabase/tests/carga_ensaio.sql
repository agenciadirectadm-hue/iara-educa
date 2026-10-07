-- Estrutura de carga dos dados reais — ensaio de ponta a ponta com dados FICTÍCIOS (seção 9 do documento de estrutura).
-- Recebe → valida → promove os 8 domínios na ordem, confere repetição sem duplicar, conciliação da fila e reversão.
-- Roda numa transação revertida: não deixa nada na base. Cada passo traz "ok": true quando o comportamento é o esperado.
-- Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/carga_ensaio.sql
do $$
declare
  v_out jsonb := '[]';
  r jsonb;
  v_ano int := iara.school_year();
  v_inep text;
  u iara.education_units;
  n_alunos_antes int := (select count(*) from iara.students);
  n_fila_antes int := (select count(*) from iara.waiting_list_entries);
  n_mat_antes int := (select count(*) from iara.enrollments);
  n int;
  v_err text;
  -- crianças: nascimento que cai em creche e pré neste ano letivo
  v_nasc_creche text := to_char(make_date(v_ano - 2, 6, 15), 'DD/MM/YYYY');
  v_nasc_pre text := to_char(make_date(v_ano - 5, 1, 10), 'YYYY-MM-DD');
begin
  perform set_config('carga.ensaio', 'on', true);
  select * into u from iara.education_units where inep_code is not null order by id limit 1;
  v_inep := u.inep_code;

  -- UNIDADES: uma nova e uma já existente (adotada pelo código INEP); uma fora de Maringá (erro)
  perform carga.receber(jsonb_build_object('lote', 'T-UNI', 'dominio', 'UNIDADES', 'arquivo', 'unidades.csv', 'hash', repeat('a', 64),
    'origem', 'Ensaio', 'data_referencia', current_date::text, 'responsavel', 'teste', 'ensaio', true, 'linhas', jsonb_build_array(
      jsonb_build_object('Código Unidade', 'U-ENS-1', 'Nome', 'CMEI Ensaio Jardim', 'Tipo', 'cmei', 'Lat', '-23,4200', 'Lng', '-51,9330', 'Bairro', 'Zona 7'),
      jsonb_build_object('codigo_unidade', 'U-ENS-2', 'codigo_inep', v_inep, 'nome', u.name, 'tipo', u.unit_type, 'lat', u.lat::text, 'lng', u.lng::text),
      jsonb_build_object('codigo_unidade', 'U-ENS-3', 'nome', 'Fora', 'tipo', 'ESCOLA', 'lat', '-25.43', 'lng', '-49.27'))));
  r := carga.validar('{"lote": "T-UNI"}');
  v_out := v_out || jsonb_build_object('passo', '1. Unidades validadas (1 erro: fora de Maringá)', 'ok', (r ->> 'erro')::int = 1 and (r ->> 'situacao') = 'COM_ERROS');
  begin
    perform carga.promover('{"lote": "T-UNI"}');
    v_err := null;
  exception when others then v_err := sqlstate;
  end;
  v_out := v_out || jsonb_build_object('passo', '2. Lote com erro não promove sem "parcial"', 'ok', v_err = '55006');
  r := carga.promover('{"lote": "T-UNI", "parcial": true}');
  v_out := v_out || jsonb_build_object('passo', '3. Unidades promovidas: 1 criada, 1 adotada', 'ok',
    (r #>> '{resultado,criados}')::int = 1 and (r #>> '{resultado,atualizados}')::int = 1 and carga.ref('UNIDADES', 'U-ENS-2') = u.id::text);

  -- TURMAS (uma com série inválida)
  perform carga.receber(jsonb_build_object('lote', 'T-TUR', 'dominio', 'TURMAS', 'arquivo', 'turmas.csv', 'origem', 'Ensaio', 'responsavel', 'teste', 'ensaio', true,
    'linhas', jsonb_build_array(
      jsonb_build_object('codigo_turma', 'T-ENS-CRE', 'codigo_unidade', 'U-ENS-1', 'ano_letivo', v_ano::text, 'serie', 'CRECHE', 'nome', 'Creche A', 'turno', 'INTEGRAL', 'capacidade_autorizada', '2'),
      jsonb_build_object('codigo_turma', 'T-ENS-PRE', 'codigo_unidade', 'U-ENS-1', 'ano_letivo', v_ano::text, 'serie', 'PRE', 'nome', 'Pré A', 'turno', 'MANHA', 'capacidade_autorizada', '24'),
      jsonb_build_object('codigo_turma', 'T-ENS-X', 'codigo_unidade', 'U-ENS-1', 'ano_letivo', v_ano::text, 'serie', 'MATERNAL', 'nome', 'X', 'turno', 'MANHA', 'capacidade_autorizada', '10'))));
  r := carga.validar('{"lote": "T-TUR"}');
  r := carga.promover('{"lote": "T-TUR", "parcial": true}');
  v_out := v_out || jsonb_build_object('passo', '4. Turmas: 2 criadas, série inválida fora', 'ok', (r #>> '{resultado,criados}')::int = 2 and (r ->> 'erro')::int = 1,
    'mensagens', r -> 'mensagens');

  -- SERVIDORES
  perform carga.receber(jsonb_build_object('lote', 'T-SER', 'dominio', 'SERVIDORES', 'arquivo', 'servidores.csv', 'origem', 'Ensaio', 'responsavel', 'teste', 'ensaio', true,
    'linhas', jsonb_build_array(jsonb_build_object('matricula_funcional', 'S-ENS-1', 'nome', 'Professora Ensaio', 'codigo_unidade', 'U-ENS-1', 'funcao', 'PROFESSOR',
      'cargo', 'Professor(a) de Educação Básica', 'carga_horaria_semanal', '40', 'data_admissao', '02/03/2015', 'formacao', 'Pedagogia', 'situacao', 'ATIVO'))));
  perform carga.validar('{"lote": "T-SER"}');
  r := carga.promover('{"lote": "T-SER"}');
  v_out := v_out || jsonb_build_object('passo', '5. Servidor promovido com a ficha funcional', 'ok', (r #>> '{resultado,criados}')::int = 1
    and exists (select 1 from iara.staff where matricula_funcional = 'S-ENS-1' and carga_horaria_semanal = 40 and data_admissao = date '2015-03-02'
                and formacao = 'Pedagogia' and situacao = 'ATIVO' and not is_demo));

  -- RESPONSÁVEIS (um CPF inválido: descartado com aviso)
  perform carga.receber(jsonb_build_object('lote', 'T-RES', 'dominio', 'RESPONSAVEIS', 'arquivo', 'responsaveis.csv', 'origem', 'Ensaio', 'responsavel', 'teste', 'ensaio', true,
    'linhas', jsonb_build_array(
      jsonb_build_object('codigo_responsavel', 'R-ENS-1', 'nome', 'Mãe Ensaio Um', 'cpf', '529.982.247-25', 'cadunico', 'S', 'mae_solo', 'S',
                         'logradouro', 'Rua Ensaio', 'numero', '10', 'bairro', 'Zona 7', 'cep', '87020-000', 'lat', '-23.4210', 'lng', '-51.9320'),
      jsonb_build_object('codigo_responsavel', 'R-ENS-2', 'nome', 'Mãe Ensaio Dois', 'cpf', '111.111.111-11', 'cadunico', 'N',
                         'lat', '-23.4500', 'lng', '-51.9000'))));
  r := carga.validar('{"lote": "T-RES"}');
  v_out := v_out || jsonb_build_object('passo', '6. CPF inválido vira aviso (linha segue)', 'ok', (r ->> 'aviso')::int = 1 and (r ->> 'erro')::int = 0);
  r := carga.promover('{"lote": "T-RES"}');
  v_out := v_out || jsonb_build_object('passo', '7. Responsáveis promovidos sem o CPF inválido', 'ok',
    (r #>> '{resultado,criados}')::int = 2 and (select cpf from iara.guardians where id = carga.ref('RESPONSAVEIS', 'R-ENS-2')::uuid) is null
    and (select is_demo from iara.guardians where id = carga.ref('RESPONSAVEIS', 'R-ENS-1')::uuid) = false);

  -- ALUNOS (um sem nascimento: erro; uma chave repetida: erro)
  perform carga.receber(jsonb_build_object('lote', 'T-ALU', 'dominio', 'ALUNOS', 'arquivo', 'alunos.csv', 'origem', 'Ensaio', 'responsavel', 'teste', 'ensaio', true,
    'linhas', jsonb_build_array(
      jsonb_build_object('codigo_aluno', 'A-ENS-1', 'nome', 'Criança Ensaio Um', 'data_nascimento', v_nasc_creche, 'sexo', 'F', 'nome_mae', 'Mãe Ensaio Um', 'lat', '-23.4210', 'lng', '-51.9320', 'bairro', 'Zona 7'),
      jsonb_build_object('codigo_aluno', 'A-ENS-2', 'nome', 'Criança Ensaio Dois', 'data_nascimento', v_nasc_creche, 'sexo', 'M', 'lat', '-23.4500', 'lng', '-51.9000'),
      jsonb_build_object('codigo_aluno', 'A-ENS-3', 'nome', 'Criança Ensaio Três', 'data_nascimento', v_nasc_pre, 'sexo', 'F'),
      jsonb_build_object('codigo_aluno', 'A-ENS-4', 'nome', 'Sem nascimento'),
      jsonb_build_object('codigo_aluno', 'A-ENS-3', 'nome', 'Repetida', 'data_nascimento', v_nasc_pre))));
  r := carga.validar('{"lote": "T-ALU"}');
  v_out := v_out || jsonb_build_object('passo', '8. Alunos: sem nascimento e chave repetida são erros', 'ok', (r ->> 'erro')::int = 2);
  r := carga.promover('{"lote": "T-ALU", "parcial": true}');
  v_out := v_out || jsonb_build_object('passo', '9. Alunos válidos promovidos com registro permanente', 'ok',
    (r #>> '{resultado,criados}')::int = 3 and (select student_registry_number from iara.students where id = carga.ref('ALUNOS', 'A-ENS-1')::uuid) = 'A-ENS-1');

  -- repetir a mesma carga não duplica (atualiza)
  perform carga.receber(jsonb_build_object('lote', 'T-ALU-2', 'dominio', 'ALUNOS', 'arquivo', 'alunos.csv', 'origem', 'Ensaio', 'responsavel', 'teste', 'ensaio', true,
    'linhas', jsonb_build_array(jsonb_build_object('codigo_aluno', 'A-ENS-1', 'nome', 'Criança Ensaio Um (corrigido)', 'data_nascimento', v_nasc_creche))));
  perform carga.validar('{"lote": "T-ALU-2"}');
  r := carga.promover('{"lote": "T-ALU-2"}');
  v_out := v_out || jsonb_build_object('passo', '10. Recarga atualiza o mesmo aluno (sem duplicar)', 'ok',
    (r #>> '{resultado,atualizados}')::int = 1 and (select count(*) from iara.students where student_registry_number = 'A-ENS-1') = 1
    and (select full_name from iara.students where id = carga.ref('ALUNOS', 'A-ENS-1')::uuid) = 'Criança Ensaio Um (corrigido)');

  -- VÍNCULOS
  perform carga.receber(jsonb_build_object('lote', 'T-VIN', 'dominio', 'VINCULOS', 'arquivo', 'vinculos.csv', 'origem', 'Ensaio', 'responsavel', 'teste', 'ensaio', true,
    'linhas', jsonb_build_array(
      jsonb_build_object('codigo_aluno', 'A-ENS-1', 'codigo_responsavel', 'R-ENS-1', 'parentesco', 'MAE', 'principal', 'S', 'situacao_legal', 'CONFIRMADO'),
      jsonb_build_object('codigo_aluno', 'A-ENS-2', 'codigo_responsavel', 'R-ENS-2', 'parentesco', 'MAE', 'principal', 'S'),
      jsonb_build_object('codigo_aluno', 'A-ENS-9', 'codigo_responsavel', 'R-ENS-2', 'parentesco', 'MAE'))));
  r := carga.validar('{"lote": "T-VIN"}');
  r := carga.promover('{"lote": "T-VIN", "parcial": true}');
  v_out := v_out || jsonb_build_object('passo', '11. Vínculos: aluno inexistente fica de fora', 'ok', (r #>> '{resultado,criados}')::int = 2 and (r ->> 'erro')::int = 1);

  -- MATRÍCULAS (duas ATIVAS do mesmo aluno: erro)
  perform carga.receber(jsonb_build_object('lote', 'T-MAT', 'dominio', 'MATRICULAS', 'arquivo', 'matriculas.csv', 'origem', 'Ensaio', 'responsavel', 'teste', 'ensaio', true,
    'linhas', jsonb_build_array(
      jsonb_build_object('codigo_matricula', 'M-ENS-1', 'codigo_aluno', 'A-ENS-3', 'codigo_turma', 'T-ENS-PRE', 'ano_letivo', v_ano::text, 'situacao', 'ATIVA'),
      jsonb_build_object('codigo_matricula', 'M-ENS-2', 'codigo_aluno', 'A-ENS-2', 'codigo_turma', 'T-ENS-CRE', 'ano_letivo', v_ano::text, 'situacao', 'ATIVA'),
      jsonb_build_object('codigo_matricula', 'M-ENS-3', 'codigo_aluno', 'A-ENS-2', 'codigo_turma', 'T-ENS-PRE', 'ano_letivo', v_ano::text, 'situacao', 'ATIVA'))));
  r := carga.validar('{"lote": "T-MAT"}');
  v_out := v_out || jsonb_build_object('passo', '12. Duas matrículas ativas do mesmo aluno: erro', 'ok', (r ->> 'erro')::int = 2);
  r := carga.promover('{"lote": "T-MAT", "parcial": true}');
  v_out := v_out || jsonb_build_object('passo', '13. Matrícula promovida atualiza turma e aluno', 'ok',
    (select active_enrollments_count from iara.classes where id = carga.ref('TURMAS', 'T-ENS-PRE')::uuid) = 1
    and (select status from iara.students where id = carga.ref('ALUNOS', 'A-ENS-3')::uuid) = 'MATRICULADO');

  -- FILA: a ordem calculada pela IN 025 confere com a lista oficial?
  perform carga.receber(jsonb_build_object('lote', 'T-FIL', 'dominio', 'FILA', 'arquivo', 'fila.csv', 'origem', 'Ensaio', 'responsavel', 'teste', 'ensaio', true,
    'linhas', jsonb_build_array(
      jsonb_build_object('codigo_inscricao', 'F-ENS-1', 'codigo_aluno', 'A-ENS-1', 'codigo_unidade', 'U-ENS-1', 'serie', 'CRECHE', 'data_solicitacao', '02/03/' || v_ano || ' 09:15', 'posicao_oficial', '1'),
      jsonb_build_object('codigo_inscricao', 'F-ENS-2', 'codigo_aluno', 'A-ENS-2', 'codigo_unidade', 'U-ENS-1', 'serie', 'CRECHE', 'data_solicitacao', v_ano || '-02-01 08:00', 'posicao_oficial', '2'))));
  r := carga.validar('{"lote": "T-FIL"}');
  r := carga.promover('{"lote": "T-FIL"}');
  v_out := v_out || jsonb_build_object('passo', '14. Fila promovida e conciliada com a IN 025', 'ok', (r #>> '{resultado,criados}')::int = 2,
    'mesma_posicao', r #> '{conciliacao,mesma_posicao}', 'divergencias', r #> '{conciliacao,divergencias}');

  -- nada da carga é de demonstração
  v_out := v_out || jsonb_build_object('passo', '15. Registros carregados não são de demonstração', 'ok',
    not exists (select 1 from iara.students where id::text in (select id_interno from carga.correspondencia where dominio = 'ALUNOS' and chave like 'A-ENS-%') and is_demo));

  -- ensaio fora do modo de ensaio: recusado
  perform set_config('carga.ensaio', 'off', true);
  perform carga.receber(jsonb_build_object('lote', 'T-SER-2', 'dominio', 'SERVIDORES', 'arquivo', 'x.csv', 'origem', 'Ensaio', 'responsavel', 'teste', 'ensaio', true,
    'linhas', jsonb_build_array(jsonb_build_object('matricula_funcional', 'S-ENS-2', 'nome', 'Outro', 'funcao', 'APOIO'))));
  perform carga.validar('{"lote": "T-SER-2"}');
  begin
    perform carga.promover('{"lote": "T-SER-2"}');
    v_err := null;
  exception when others then v_err := sqlstate;
  end;
  v_out := v_out || jsonb_build_object('passo', '16. Lote de ensaio não promove fora do ensaio', 'ok', v_err = '42501');
  perform set_config('carga.ensaio', 'on', true);

  -- reverter na ordem inversa; reverter ALUNOS antes de MATRÍCULAS é recusado
  begin
    perform carga.reverter('{"lote": "T-ALU"}');
    v_err := null;
  exception when others then v_err := sqlstate;
  end;
  v_out := v_out || jsonb_build_object('passo', '17. Reverter alunos antes das matrículas: recusado', 'ok', v_err = '23503');
  perform carga.reverter('{"lote": "T-FIL"}');
  perform carga.reverter('{"lote": "T-MAT"}');
  perform carga.reverter('{"lote": "T-VIN"}');
  perform carga.reverter('{"lote": "T-ALU-2"}');
  perform carga.reverter('{"lote": "T-ALU"}');
  v_out := v_out || jsonb_build_object('passo', '18. Reversão devolve a base ao estado anterior', 'ok',
    (select count(*) from iara.students) = n_alunos_antes and (select count(*) from iara.waiting_list_entries) = n_fila_antes
    and (select count(*) from iara.enrollments) = n_mat_antes and carga.ref('ALUNOS', 'A-ENS-1') is null);
  perform carga.reverter('{"lote": "T-RES"}');
  perform carga.reverter('{"lote": "T-SER"}');
  perform carga.reverter('{"lote": "T-TUR"}');
  perform carga.reverter('{"lote": "T-UNI"}');
  v_out := v_out || jsonb_build_object('passo', '19. Unidade adotada volta ao original', 'ok',
    (select name from iara.education_units where id = u.id) = u.name and carga.ref('UNIDADES', 'U-ENS-1') is null
    and not exists (select 1 from iara.education_units where name = 'CMEI Ensaio Jardim'));

  raise exception 'RESULTADO: %', v_out;  -- reverte tudo
end $$;
