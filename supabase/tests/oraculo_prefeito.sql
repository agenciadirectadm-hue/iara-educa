-- Oráculo do Prefeito: só o Prefeito; números agregados por tópico na cidade, numa unidade e numa região; resposta por
-- regras (sem a chave da Anthropic) que entende o assunto e o recorte da pergunta; registro no histórico; sem dado pessoal.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/oraculo_prefeito.sql
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
  r jsonb; r2 jsonb; r3 jsonb;
  v_unit integer := (select e.unit_id from iara.enrollments e where e.status = 'ACTIVE' group by 1 order by count(*) desc limit 1);
  v_unome text := (select short_name from iara.education_units where id = v_unit);
  v_ap text := (select 'AP ' || right(t.code, 3) from iara.territories t join iara.education_units u on u.macro_territory_id = t.id where u.id = v_unit);
  v_topico text;
  v_falhas text[] := '{}';
  v_nome text;
  v_uid uuid;
begin
  perform iara.session_create('PREFEITO', null, 'or-pref', 'teste');
  perform iara.session_create('SECRETARIO', null, 'or-sec', 'teste');

  -- todos os tópicos respondem, na cidade, sem erro e com números
  foreach v_topico in array array['visao_geral', 'matriculas', 'fila', 'vagas', 'creche', 'frequencia', 'ocorrencias', 'profissionais',
                                  'transporte', 'alfabetizacao', 'busca_ativa', 'unidades', 'cadastros'] loop
    r := pg_temp.as_call('or-pref', 'oraculo_dados', jsonb_build_object('topico', v_topico));
    if r ->> 'erro' is not null or jsonb_array_length(coalesce(r -> 'numeros', '[]')) = 0 or r ->> 'topico' <> v_topico then
      v_falhas := v_falhas || (v_topico || ': ' || coalesce(r ->> 'erro', 'sem números'));
    end if;
  end loop;
  r := pg_temp.as_call('or-pref', 'oraculo_dados', '{"topico": "matriculas"}');
  v_out := v_out || jsonb_build_object('passo', 'O1. Os 13 tópicos respondem na cidade', 'ok', cardinality(v_falhas) = 0, 'falhas', to_jsonb(v_falhas),
    'matriculas', r -> 'numeros');

  -- recorte por unidade (nome) e por região (AP)
  r := pg_temp.as_call('or-pref', 'oraculo_dados', jsonb_build_object('topico', 'matriculas', 'unidade', v_unome));
  r2 := pg_temp.as_call('or-pref', 'oraculo_dados', jsonb_build_object('topico', 'matriculas', 'regiao', v_ap));
  r3 := pg_temp.as_call('or-pref', 'oraculo_dados', '{"topico": "matriculas"}');
  v_out := v_out || jsonb_build_object('passo', 'O2. Unidade e região recortam (unidade ≤ região ≤ cidade)', 'ok',
    (r ->> 'unidade')::int = v_unit and r2 ->> 'area' is not null
    and (r -> 'numeros' -> 0 ->> 'valor')::int <= (r2 -> 'numeros' -> 0 ->> 'valor')::int
    and (r2 -> 'numeros' -> 0 ->> 'valor')::int < (r3 -> 'numeros' -> 0 ->> 'valor')::int,
    'unidade', r ->> 'recorte', 'regiao', r2 ->> 'recorte', 'n', jsonb_build_array(r -> 'numeros' -> 0 ->> 'valor', r2 -> 'numeros' -> 0 ->> 'valor', r3 -> 'numeros' -> 0 ->> 'valor'));

  -- regras: assunto e recorte vêm da pergunta
  r := pg_temp.as_call('or-pref', 'oraculo_perguntar', jsonb_build_object('pergunta', 'Quantas crianças estão esperando vaga na creche no ' || v_unome || '?'));
  r2 := pg_temp.as_call('or-pref', 'oraculo_perguntar', jsonb_build_object('pergunta', 'Como está a frequência na ' || v_ap || '?'));
  r3 := pg_temp.as_call('or-pref', 'oraculo_perguntar', '{"pergunta": "Quantos professores temos?"}');
  v_out := v_out || jsonb_build_object('passo', 'O3. Por regras: tópico e recorte da pergunta, resposta em português', 'ok',
    r ->> 'topico' = 'creche' and (r ->> 'unidade')::int = v_unit and r2 ->> 'topico' = 'frequencia' and r2 ->> 'area' is not null
    and r3 ->> 'topico' = 'profissionais' and r3 ->> 'recorte' = 'Maringá' and r ->> 'modo' = 'REGRAS' and length(r ->> 'resposta') > 20,
    'respostas', jsonb_build_array(r ->> 'resposta', r2 ->> 'resposta', r3 ->> 'resposta'));

  -- histórico e registro do Claude
  r := pg_temp.as_call('or-pref', 'oraculo_registrar', '{"pergunta": "Teste do Claude", "canal": "AUDIO", "resposta": "Resposta do teste.", "ferramentas": [{"topico": "fila"}]}');
  r2 := pg_temp.as_call('or-pref', 'oraculo_historico', '{}');
  v_out := v_out || jsonb_build_object('passo', 'O4. Perguntas ficam no histórico do próprio Prefeito', 'ok',
    r ->> 'ok' = 'true' and jsonb_array_length(r2) = 4 and r2 -> 0 ->> 'modo' = 'CLAUDE' and r2 -> 0 ->> 'canal' = 'AUDIO');

  -- sem dado pessoal
  select full_name into v_nome from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' where e.unit_id = v_unit limit 1;
  r := pg_temp.as_call('or-pref', 'oraculo_perguntar', jsonb_build_object('pergunta', 'Qual o telefone da família de ' || v_nome || '?'));
  r2 := pg_temp.as_call('or-pref', 'oraculo_unidades', jsonb_build_object('busca', left(v_unome, 6)));
  r3 := pg_temp.as_call('or-pref', 'oraculo_unidades', '{}');
  v_out := v_out || jsonb_build_object('passo', 'O5. Só números agregados (nem nome nem identificador de pessoa); lista de unidades', 'ok',
    position(v_nome in (r - 'pergunta')::text) = 0 and (r - 'pergunta')::text !~ '[0-9a-f]{8}-[0-9a-f]{4}-'
    and jsonb_array_length(r2 -> 'unidades') >= 1 and jsonb_array_length(r3 -> 'regioes') >= 20 and (r3 ->> 'total_unidades')::int > 100,
    'resposta', r ->> 'resposta', 'nome_ok', position(v_nome in (r - 'pergunta')::text) = 0, 'uuid_ok', (r - 'pergunta')::text !~ '[0-9a-f]{8}-[0-9a-f]{4}-', 'n_unid', jsonb_array_length(r2 -> 'unidades'), 'n_reg', jsonb_array_length(r3 -> 'regioes'), 'tot', r3 ->> 'total_unidades');

  -- só o Prefeito
  r := pg_temp.as_call('or-sec', 'oraculo_dados', '{"topico": "fila"}');
  r2 := pg_temp.as_call('or-sec', 'oraculo_perguntar', '{"pergunta": "Quantos alunos?"}');
  v_out := v_out || jsonb_build_object('passo', 'O6. Secretaria não acessa', 'ok', r ->> 'codigo' = '42501' and r2 ->> 'codigo' = '42501');

  -- conexão permanente: a chave aparece uma vez, o banco guarda só o hash, o resolver conta o uso e a revogação corta na hora
  r := pg_temp.as_call('or-pref', 'oraculo_conexao_criar', '{"rotulo": "Claude do teste"}');
  v_uid := iara.oraculo_chave_resolver(encode(extensions.digest(r ->> 'chave', 'sha256'), 'hex'));
  r2 := pg_temp.as_call('or-pref', 'oraculo_conexoes', '{}');
  r3 := pg_temp.as_call('or-sec', 'oraculo_conexao_criar', '{"rotulo": "Tentativa"}');
  v_out := v_out || jsonb_build_object('passo', 'O7. Conexão permanente: chave única (só o hash no banco), uso contado, revogável; só o Prefeito cria', 'ok',
    r ->> 'chave' like 'iara_mcp_%' and length(r ->> 'chave') >= 40
    and not exists (select 1 from iara.oraculo_chaves k where k.chave_hash = r ->> 'chave' or k.prefixo = r ->> 'chave')
    and v_uid is not null and (select role_code from iara.app_users where id = v_uid) = 'PREFEITO'
    and (select usos from iara.oraculo_chaves where id = (r ->> 'id')::uuid) = 1
    and r2 -> 0 ->> 'rotulo' = 'Claude do teste' and not (r2 -> 0 ? 'chave')
    and (pg_temp.as_call('or-pref', 'oraculo_conexao_revogar', jsonb_build_object('id', r ->> 'id')) ->> 'ok')::boolean
    and iara.oraculo_chave_resolver(encode(extensions.digest(r ->> 'chave', 'sha256'), 'hex')) is null
    and r3 ->> 'codigo' = '42501',
    'erro', coalesce(r ->> 'erro', r2 ->> 'erro'));

  -- perguntas fora do Oráculo (096): nome de pessoa recebe a explicação, sem número; sem assunto recebe o aviso
  r := pg_temp.as_call('or-pref', 'oraculo_perguntar', '{"pergunta": "quantos alunos no municipio se chamam silvio?"}');
  r2 := pg_temp.as_call('or-pref', 'oraculo_perguntar', '{"pergunta": "qual o time de futebol da cidade?"}');
  r3 := pg_temp.as_call('or-pref', 'oraculo_perguntar', '{"pergunta": "Quantos alunos estão matriculados?"}');
  v_out := v_out || jsonb_build_object('passo', 'O8. Pergunta por nome: explicação sem número; sem assunto: aviso e resumo; assunto conhecido: como antes', 'ok',
    (r ->> 'fora')::boolean and jsonb_array_length(r -> 'numeros') = 0 and r ->> 'resposta' like 'O Oráculo não conta%'
    and (r2 ->> 'fora')::boolean and r2 ->> 'resposta' like 'Não achei%' and r3 ->> 'topico' = 'matriculas' and not (r3 ->> 'fora')::boolean,
    'nome', r ->> 'resposta', 'sem_assunto', left(r2 ->> 'resposta', 90));
  raise exception 'RESULTADO: %', v_out;
end $$;
