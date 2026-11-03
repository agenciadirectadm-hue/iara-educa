-- Públicos do Prefeito: só o Prefeito; só contagens (sem nome nem contato); sigilo de recortes pequenos; envio registrado
-- (simulado na demonstração) e auditado; bloqueio no período eleitoral.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/publicos_prefeito.sql
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
  r jsonb; r2 jsonb; r3 jsonb; r4 jsonb;
  v_todos integer; v_n integer; v_g record;
  v_unit integer := (select e.unit_id from iara.enrollments e where e.status = 'ACTIVE' group by 1 order by count(*) desc limit 1);
  v_nome text;
begin
  perform iara.session_create('PREFEITO', null, 'pp-pref', 'teste');
  perform iara.session_create('SECRETARIO', null, 'pp-sec', 'teste');
  perform iara.session_create('COMERCIAL', null, 'pp-com', 'teste');

  r := pg_temp.as_call('pp-pref', 'publicos_opcoes', '{}');
  r2 := pg_temp.as_call('pp-pref', 'publicos_contar', '{"publico": "RESPONSAVEIS", "filtros": {}}');
  r3 := pg_temp.as_call('pp-pref', 'publicos_contar', '{"publico": "PROFISSIONAIS", "filtros": {}}');
  v_out := v_out || jsonb_build_object('passo', 'U1. Prefeito: opções e contagens de responsáveis e profissionais', 'ok',
    r ->> 'erro' is null and jsonb_array_length(r -> 'unidades') > 0 and jsonb_array_length(r -> 'modelos') >= 4
    and (r2 ->> 'total')::int > 1000 and (r3 ->> 'total')::int > 1000,
    'responsaveis', r2 - 'por_unidade' - 'por_regiao' - 'nota', 'profissionais', r3 - 'por_unidade' - 'por_regiao' - 'nota', 'erro', coalesce(r ->> 'erro', r2 ->> 'erro'));

  -- filtros reduzem o público
  r := pg_temp.as_call('pp-pref', 'publicos_contar', jsonb_build_object('publico', 'RESPONSAVEIS', 'filtros', jsonb_build_object('unidades', jsonb_build_array(v_unit))));
  r2 := pg_temp.as_call('pp-pref', 'publicos_contar', '{"publico": "RESPONSAVEIS", "filtros": {"fila": true}}');
  r3 := pg_temp.as_call('pp-pref', 'publicos_contar', '{"publico": "PROFISSIONAIS", "filtros": {"funcoes": ["PROFESSOR"]}}');
  v_out := v_out || jsonb_build_object('passo', 'U2. Filtros por unidade, fila e função reduzem o público', 'ok',
    (r ->> 'total')::int between 1 and (r2 ->> 'total')::int + 100000 and (r2 ->> 'total')::int > 0 and (r3 ->> 'total')::int > 0
    and (r ->> 'total')::int < (pg_temp.as_call('pp-pref', 'publicos_contar', '{"publico": "RESPONSAVEIS", "filtros": {}}') ->> 'total')::int,
    'unidade', r ->> 'total', 'fila', r2 ->> 'total', 'professores', r3 ->> 'total');

  -- sem dado pessoal e sigilo dos recortes
  select g.full_name into v_nome from iara.guardians g join iara.student_guardians sg on sg.guardian_id = g.id
    join iara.enrollments e on e.student_id = sg.student_id and e.status = 'ACTIVE' where e.unit_id = v_unit limit 1;
  v_out := v_out || jsonb_build_object('passo', 'U3. Só contagens: sem nome, telefone ou identificador; recortes com 3 ou mais', 'ok',
    position(v_nome in r::text) = 0 and r::text !~ '[0-9a-f]{8}-[0-9a-f]{4}-' and r::text !~ '\(\d{2}\)'
    and not exists (select 1 from jsonb_array_elements(r -> 'por_unidade') x where (x ->> 'n')::int < 3)
    and not exists (select 1 from jsonb_array_elements(r -> 'por_regiao') x where (x ->> 'n')::int < 3));

  -- envio registrado e auditado (simulado na demonstração)
  r := pg_temp.as_call('pp-pref', 'publicos_enviar', '{"publico": "RESPONSAVEIS", "filtros": {"fila": true}, "modelo": "MATRICULA", "texto": "As inscrições para 2027 estão abertas no portal e na IARA."}');
  r2 := pg_temp.as_call('pp-pref', 'publicos_historico', '{}');
  v_out := v_out || jsonb_build_object('passo', 'U4. Envio registrado, auditado e no histórico', 'ok',
    r ->> 'erro' is null and r ->> 'situacao' in ('SIMULADO', 'ENFILEIRADO') and (r ->> 'total')::int > 0
    and exists (select 1 from iara.audit_log where action = 'PUBLICO_ENVIO' and entity_id = r ->> 'id')
    and r2 -> 0 ->> 'id' = r ->> 'id',
    'resposta', r - 'periodo_eleitoral');

  -- modelo errado para o público e texto curto
  r := pg_temp.as_call('pp-pref', 'publicos_enviar', '{"publico": "PROFISSIONAIS", "filtros": {}, "modelo": "MATRICULA", "texto": "Texto suficiente para o teste."}');
  r2 := pg_temp.as_call('pp-pref', 'publicos_enviar', '{"publico": "RESPONSAVEIS", "filtros": {}, "modelo": "COMUNICADO", "texto": "curto"}');
  v_out := v_out || jsonb_build_object('passo', 'U5. Recusa modelo de outro público e mensagem curta', 'ok',
    r ->> 'codigo' = '22023' and r2 ->> 'codigo' = '22023', 'modelo', r ->> 'erro', 'curto', r2 ->> 'erro');

  -- período eleitoral: registra e bloqueia
  update iara.tenants set settings = settings || jsonb_build_object('eleicao_municipal', (iara.hoje_local() + 30)::text) where id = 1;
  r := pg_temp.as_call('pp-pref', 'publicos_enviar', '{"publico": "PROFISSIONAIS", "filtros": {}, "modelo": "SERVIDORES", "texto": "Reunião geral na próxima semana."}');
  v_out := v_out || jsonb_build_object('passo', 'U6. Período eleitoral: o envio fica registrado e bloqueado (0 enviados)', 'ok',
    r ->> 'situacao' = 'BLOQUEADO_ELEITORAL' and (r ->> 'enviados')::int = 0, 'resposta', r - 'periodo_eleitoral');

  -- só o Prefeito
  r := pg_temp.as_call('pp-sec', 'publicos_contar', '{"publico": "RESPONSAVEIS", "filtros": {}}');
  r2 := pg_temp.as_call('pp-com', 'publicos_opcoes', '{}');
  v_out := v_out || jsonb_build_object('passo', 'U7. Secretaria e Comercial não acessam', 'ok', r ->> 'codigo' = '42501' and r2 ->> 'codigo' = '42501',
    'secretaria', r ->> 'erro', 'comercial', r2 ->> 'erro');

  -- novos filtros dos responsáveis: cada um reduz o público e combina com os outros
  v_todos := (pg_temp.as_call('pp-pref', 'publicos_contar', '{"publico": "RESPONSAVEIS", "filtros": {}}') ->> 'total')::int;
  r := pg_temp.as_call('pp-pref', 'publicos_contar', '{"publico": "RESPONSAVEIS", "filtros": {"relacoes": ["AVO"]}}');
  r2 := pg_temp.as_call('pp-pref', 'publicos_contar', '{"publico": "RESPONSAVEIS", "filtros": {"faixas_etarias": ["45-59", "60+"], "sexos": ["F"]}}');
  r3 := pg_temp.as_call('pp-pref', 'publicos_contar', '{"publico": "RESPONSAVEIS", "filtros": {"idiomas": ["Espanhol"], "mae_solo": true}}');
  r4 := pg_temp.as_call('pp-pref', 'publicos_contar', jsonb_build_object('publico', 'RESPONSAVEIS', 'filtros', jsonb_build_object(
          'nasc_de', '1980-01-01', 'nasc_ate', '1989-12-31', 'escolaridades', jsonb_build_array('Superior completo'), 'idades_filho', jsonb_build_array('0-3'),
          'num_filhos', jsonb_build_array('1'), 'principal', true)));
  v_out := v_out || jsonb_build_object('passo', 'U8. Filtros do responsável e dos filhos (vínculo, idade, sexo, idioma, mãe solo, nascimento, escolaridade…)', 'ok',
    (r ->> 'total')::int between 3 and v_todos - 1 and (r2 ->> 'total')::int between 3 and v_todos - 1
    and coalesce((r3 ->> 'total')::int, 0) < (r2 ->> 'total')::int and coalesce((r4 ->> 'total')::int, 0) < v_todos
    and r ->> 'erro' is null and r4 ->> 'erro' is null,
    'avos', r ->> 'total', 'mulheres_45_mais', r2 ->> 'total', 'espanhol_mae_solo', coalesce(r3 ->> 'total', 'sigilo'), 'combinado', coalesce(r4 ->> 'total', 'sigilo'),
    'erro', coalesce(r ->> 'erro', r4 ->> 'erro'));

  -- sigilo: um público de 1 ou 2 pessoas não mostra números; comunicado só com 10 ou mais
  select g.birth_date, sg.relationship, e.unit_id into v_g from iara.guardians g
    join iara.student_guardians sg on sg.guardian_id = g.id and sg.end_date is null
    join iara.enrollments e on e.student_id = sg.student_id and e.status = 'ACTIVE'
    where g.birth_date is not null order by g.id limit 1;
  r := jsonb_build_object('nasc_de', v_g.birth_date, 'nasc_ate', v_g.birth_date, 'relacoes', jsonb_build_array(v_g.relationship), 'unidades', jsonb_build_array(v_g.unit_id));
  v_n := (select count(*) from iara.publicos_alvo('RESPONSAVEIS', r));
  r2 := pg_temp.as_call('pp-pref', 'publicos_contar', jsonb_build_object('publico', 'RESPONSAVEIS', 'filtros', r));
  r3 := pg_temp.as_call('pp-pref', 'publicos_enviar', jsonb_build_object('publico', 'RESPONSAVEIS', 'filtros', r, 'modelo', 'COMUNICADO', 'texto', 'Mensagem de teste com mais de dez letras.'));
  v_out := v_out || jsonb_build_object('passo', 'U9. Público pequeno: menos de 3 fica em sigilo; menos de 10 não recebe comunicado', 'ok',
    v_n between 1 and 9
    and (case when v_n < 3 then (r2 ->> 'sigilo')::boolean and r2 ->> 'total' is null else (r2 ->> 'total')::int = v_n end)
    and r3 ->> 'codigo' = '22023',
    'pessoas', v_n, 'contagem', r2 ->> 'total', 'envio', r3 ->> 'erro');

  -- profissionais: cargo, área, tempo de rede, admissão
  r := pg_temp.as_call('pp-pref', 'publicos_contar', '{"publico": "PROFISSIONAIS", "filtros": {"cargos": ["Educador(a) Infantil"]}}');
  r2 := pg_temp.as_call('pp-pref', 'publicos_contar', '{"publico": "PROFISSIONAIS", "filtros": {"tempos_rede": ["20+"]}}');
  r3 := pg_temp.as_call('pp-pref', 'publicos_contar', '{"publico": "PROFISSIONAIS", "filtros": {"areas_atuacao": ["Arte"], "admissao_de": "2010-01-01", "admissao_ate": "2025-12-31"}}');
  r4 := pg_temp.as_call('pp-pref', 'publicos_opcoes', '{}');
  v_out := v_out || jsonb_build_object('passo', 'U10. Profissionais: cargo, área de atuação, tempo de rede e admissão; opções com os valores do cadastro', 'ok',
    (r ->> 'total')::int > 100 and (r2 ->> 'total')::int > 0 and coalesce((r3 ->> 'total')::int, 0) < 184
    and jsonb_array_length(r4 -> 'relacoes') >= 3 and jsonb_array_length(r4 -> 'escolaridades') >= 5 and jsonb_array_length(r4 -> 'cargos') >= 3,
    'educadores', r ->> 'total', 'vinte_anos_mais', r2 ->> 'total', 'arte_desde_2010', coalesce(r3 ->> 'total', 'sigilo'));

  raise exception 'RESULTADO: %', v_out;
end $$;
