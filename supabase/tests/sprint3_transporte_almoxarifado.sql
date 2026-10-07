-- Sprint 3: transporte escolar e almoxarifado — quem vê e quem lança o quê, o cenário “rota não executada” e o ciclo do pedido.
-- Roda numa transação revertida (não deixa resíduo). Cada passo traz "ok": true quando o comportamento é o esperado.
-- Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/sprint3_transporte_almoxarifado.sql
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
create or replace function pg_temp.n(r jsonb) returns integer language sql as $f$
  select case when jsonb_typeof(r) = 'array' then jsonb_array_length(r) else -1 end $f$;

do $$
declare
  v_out jsonb := '[]';
  r jsonb;
  v_ana uuid := (iara.setting('demo_student_ana'))::uuid;
  v_unit integer;
  v_outra integer;
  v_rota uuid;
  v_rota_outra uuid;
  v_outro_aluno uuid;
  v_class uuid;
  v_sem jsonb;
  v_ped uuid;
  v_itens jsonb;
  v_central numeric;
  v_mat uuid;
  v_lote uuid;
begin
  select e.unit_id, e.class_id into v_unit, v_class from iara.enrollments e where e.student_id = v_ana and e.status = 'ACTIVE';
  select rota_id into v_rota from iara.transporte_alunos where student_id = v_ana and fim is null;
  select r2.id, r2.unit_id into v_rota_outra, v_outra from iara.transporte_rotas r2 where r2.unit_id <> v_unit and r2.situacao = 'ATIVA' order by r2.codigo limit 1;
  select student_id into v_outro_aluno from iara.transporte_alunos where rota_id = v_rota_outra and fim is null limit 1;
  perform iara.session_create('TRANSPORTE', null, 's3-tr', 'teste');
  perform iara.session_create('ALMOXARIFADO', null, 's3-al', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_unit, 's3-dir', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_outra, 's3-dir-outra', 'teste');
  perform iara.session_create('CIDADAO', null, 's3-fam', 'teste');
  perform iara.session_create('CIDADAO_NOVO', null, 's3-fam-nova', 'teste');
  perform iara.session_create('PREFEITO', null, 's3-pref', 'teste');
  perform iara.session_create('PROFESSOR', v_unit, 's3-prof', 'teste');

  -- Transporte: escopo ------------------------------------------------------------------------------------------------------------
  r := pg_temp.as_call('s3-tr', 'transporte_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', 'T1. Gerência vê a rede: rotas, frota e documentação', 'ok', (r ->> 'rotas')::int > 100 and r -> 'frota' ->> 'veiculos' is not null
    and pg_temp.n(r -> 'lista') > 100, 'rotas', r ->> 'rotas', 'sem_rota', r ->> 'sem_rota', 'erro', r ->> 'erro');
  r := pg_temp.as_call('s3-dir', 'transporte_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', 'T2. Direção vê só as rotas da própria escola, sem a frota', 'ok', pg_temp.n(r -> 'lista') >= 1 and r -> 'frota' = 'null'::jsonb
    and not exists (select 1 from jsonb_array_elements(r -> 'lista') x where (x ->> 'unit_id')::int <> v_unit), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s3-dir-outra', 'transporte_rota', jsonb_build_object('id', v_rota));
  v_out := v_out || jsonb_build_object('passo', 'T3. Direção de outra escola não abre a rota (deve negar)', 'ok', pg_temp.ok_erro(r, 'P0002'));
  r := pg_temp.as_call('s3-pref', 'transporte_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', 'T4. Prefeito vê os números, sem a lista de rotas', 'ok', r ->> 'erro' is null and r -> 'lista' = 'null'::jsonb, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s3-prof', 'transporte_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', 'T5. Professor não vê o transporte (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s3-dir', 'transporte_frota', '{}');
  v_out := v_out || jsonb_build_object('passo', 'T6. Direção não gerencia a frota (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));

  -- Família ---------------------------------------------------------------------------------------------------------------------
  r := pg_temp.as_call('s3-fam', 'familia_transporte', '{}');
  v_out := v_out || jsonb_build_object('passo', 'F1. Família vê a rota da Ana: o ponto dela, o horário e o veículo — sem os outros pontos e crianças', 'ok',
    exists (select 1 from jsonb_array_elements(r) x where (x ->> 'student_id')::uuid = v_ana and x -> 'rota' -> 'meu_ponto' ->> 'nome' is not null)
    and r::text not like '%"pontos"%' and r::text not like '%"alunos"%', 'erro', r ->> 'erro');
  r := pg_temp.as_call('s3-fam-nova', 'familia_transporte', '{}');
  v_out := v_out || jsonb_build_object('passo', 'F2. Outra família não vê nada da rota da Ana', 'ok', pg_temp.n(r) = 0 or r::text not like '%' || v_rota::text || '%');
  r := pg_temp.as_call('s3-fam', 'familia_transporte_avisar', jsonb_build_object('student_id', v_ana, 'sentido', 'VOLTA', 'motivo', 'Vou buscar na escola'));
  v_out := v_out || jsonb_build_object('passo', 'F3. Família avisa que a Ana não volta de transporte hoje', 'ok', (r ->> 'ok')::boolean, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s3-tr', 'transporte_embarque', jsonb_build_object('rota_id', v_rota, 'sentido', 'VOLTA'));
  v_out := v_out || jsonb_build_object('passo', 'F4. O aviso aparece na lista de embarque da volta', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'alunos') x where (x ->> 'student_id')::uuid = v_ana and x ->> 'aviso' is not null), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s3-fam', 'familia_transporte_avisar', jsonb_build_object('student_id', v_outro_aluno, 'sentido', 'IDA'));
  v_out := v_out || jsonb_build_object('passo', 'F5. Família não avisa por criança de outra família (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));

  -- Cenário “veículo não executa a rota” ----------------------------------------------------------------------------------------------
  r := pg_temp.as_call('s3-tr', 'transporte_viagem_registrar', jsonb_build_object('rota_id', v_rota, 'sentido', 'IDA', 'situacao', 'NAO_REALIZADA'));
  v_out := v_out || jsonb_build_object('passo', 'R1. Viagem não realizada sem motivo é recusada', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s3-dir', 'transporte_viagem_registrar', jsonb_build_object('rota_id', v_rota, 'sentido', 'IDA', 'situacao', 'NAO_REALIZADA', 'motivo', 'Pane mecânica'));
  v_out := v_out || jsonb_build_object('passo', 'R2. Direção não registra a viagem (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s3-tr', 'transporte_viagem_registrar', jsonb_build_object('rota_id', v_rota, 'sentido', 'IDA', 'situacao', 'NAO_REALIZADA', 'motivo', 'Pane mecânica sem reserva a tempo'));
  v_out := v_out || jsonb_build_object('passo', 'R3. Rota não executada: famílias avisadas, ocorrência aberta e falta abonada', 'ok', (r ->> 'familias_avisadas')::int >= 1
    and exists (select 1 from iara.transporte_abonos where student_id = v_ana and data = iara.hoje_local())
    and exists (select 1 from iara.transporte_ocorrencias where rota_id = v_rota and data = iara.hoje_local() and tipo = 'ROTA_NAO_EXECUTADA' and situacao = 'ABERTA')
    and exists (select 1 from iara.notifications where student_id = v_ana and event_type = 'TRANSPORTE_NAO_REALIZADO'), 'avisadas', r ->> 'familias_avisadas', 'erro', r ->> 'erro');
  if iara.dia_letivo(iara.hoje_local(), v_unit) then
    delete from iara.frequencia_faltas f using iara.frequencia_registros fr where fr.id = f.registro_id and fr.class_id = v_class and fr.data = iara.hoje_local();
    r := pg_temp.as_call('s3-dir', 'frequencia_lancar', jsonb_build_object('class_id', v_class, 'data', iara.hoje_local(), 'faltas', jsonb_build_array(v_ana)));
    v_out := v_out || jsonb_build_object('passo', 'R4. A chamada lançada depois já marca a falta da Ana como justificada pelo transporte', 'ok',
      exists (select 1 from iara.frequencia_faltas f join iara.frequencia_registros fr on fr.id = f.registro_id
              where f.student_id = v_ana and fr.data = iara.hoje_local() and f.tipo = 'FALTA_JUSTIFICADA' and f.justificativa like 'Transporte escolar%'), 'erro', r ->> 'erro');
  end if;
  r := pg_temp.as_call('s3-fam', 'familia_transporte', '{}');
  v_out := v_out || jsonb_build_object('passo', 'R5. Família vê a ida de hoje como não realizada, com o motivo', 'ok',
    exists (select 1 from jsonb_array_elements(r) x where x -> 'rota' -> 'hoje' -> 'ida' ->> 'situacao' in ('NAO_REALIZADA', 'SEM_AULA')), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s3-tr', 'transporte_embarque_registrar', jsonb_build_object('rota_id', v_rota, 'sentido', 'VOLTA',
         'registros', jsonb_build_array(jsonb_build_object('student_id', v_outro_aluno, 'embarcou', true))));
  v_out := v_out || jsonb_build_object('passo', 'R6. Embarque de aluno de outra rota é recusado', 'ok', pg_temp.ok_erro(r, '22023'));

  -- Inclusão de aluno que aguardava rota ------------------------------------------------------------------------------------------------
  r := pg_temp.as_call('s3-tr', 'transporte_sem_rota', '{}');
  v_sem := (select x from jsonb_array_elements(r) x where x -> 'sugestao' ->> 'rota_id' is not null and (x -> 'sugestao' ->> 'vagas')::int > 0 limit 1);
  r := pg_temp.as_call('s3-tr', 'transporte_aluno_incluir', jsonb_build_object('student_id', v_sem ->> 'student_id', 'rota_id', v_sem -> 'sugestao' ->> 'rota_id',
         'ponto_id', v_sem -> 'sugestao' ->> 'ponto_id', 'motivo', 'DISTANCIA'));
  v_out := v_out || jsonb_build_object('passo', 'I1. Aluno que aguardava é incluído na rota sugerida (família avisada)', 'ok', (r ->> 'ok')::boolean
    and (select school_transport_status from iara.students where id = (v_sem ->> 'student_id')::uuid) = 'ATENDIDO'
    and exists (select 1 from iara.notifications where student_id = (v_sem ->> 'student_id')::uuid and event_type = 'TRANSPORTE_INCLUIDO'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s3-tr', 'transporte_aluno_incluir', jsonb_build_object('student_id', v_ana, 'rota_id', v_rota_outra,
         'ponto_id', (select id from iara.transporte_pontos where rota_id = v_rota_outra limit 1)));
  v_out := v_out || jsonb_build_object('passo', 'I2. Rota de outra escola é recusada', 'ok', pg_temp.ok_erro(r, '22023'));

  -- Almoxarifado ------------------------------------------------------------------------------------------------------------------
  r := pg_temp.as_call('s3-dir', 'produtos_catalogo', '{}');
  v_out := v_out || jsonb_build_object('passo', 'A1. A escola vê o catálogo com o saldo central e o seu', 'ok', pg_temp.n(r) > 10, 'erro', r ->> 'erro');
  r := pg_temp.as_call('s3-dir', 'pedido_criar', jsonb_build_object('itens', jsonb_build_array(jsonb_build_object('codigo', 'ALI-010', 'quantidade', 5), jsonb_build_object('codigo', 'PED-001', 'quantidade', 5))));
  v_out := v_out || jsonb_build_object('passo', 'A2. Frutas (entrega direta) e itens do almoxarifado no mesmo pedido são recusados', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s3-dir', 'pedido_criar', jsonb_build_object('itens', jsonb_build_array(jsonb_build_object('codigo', 'PED-001', 'quantidade', 5),
         jsonb_build_object('codigo', 'LIM-002', 'quantidade', 3), jsonb_build_object('codigo', 'ALI-001', 'quantidade', 4))));
  v_ped := (r ->> 'id')::uuid; v_itens := r -> 'itens';
  v_out := v_out || jsonb_build_object('passo', 'A3. A escola faz o pedido', 'ok', r ->> 'situacao' = 'ENVIADO' and r ->> 'origem' = 'ALMOXARIFADO', 'numero', r ->> 'numero', 'erro', r ->> 'erro');
  r := pg_temp.as_call('s3-dir', 'pedido_decidir', jsonb_build_object('id', v_ped, 'aprovar', true));
  v_out := v_out || jsonb_build_object('passo', 'A4. A escola não aprova o próprio pedido (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s3-al', 'pedido_decidir', jsonb_build_object('id', v_ped, 'aprovar', true,
         'itens', jsonb_build_array(jsonb_build_object('id', (select x ->> 'id' from jsonb_array_elements(v_itens) x where x ->> 'codigo' = 'LIM-002'), 'aprovada', 2))));
  v_out := v_out || jsonb_build_object('passo', 'A5. O almoxarifado aprova ajustando a quantidade', 'ok', r ->> 'situacao' = 'APROVADO'
    and exists (select 1 from jsonb_array_elements(r -> 'itens') x where x ->> 'codigo' = 'LIM-002' and (x ->> 'aprovada')::numeric = 2), 'erro', r ->> 'erro');
  select quantidade into v_central from iara.materiais where unit_id is null and codigo = 'PED-001' and ativo;
  r := pg_temp.as_call('s3-al', 'pedido_despachar', jsonb_build_object('id', v_ped));
  v_out := v_out || jsonb_build_object('passo', 'A6. Remessa despachada: sai do estoque central; alimento sai pelo lote que vence primeiro', 'ok', r ->> 'situacao' = 'EM_TRANSPORTE'
    and (select quantidade from iara.materiais where unit_id is null and codigo = 'PED-001' and ativo) = v_central - 5
    and exists (select 1 from jsonb_array_elements(r -> 'itens') x where x ->> 'codigo' = 'ALI-001' and jsonb_array_length(x -> 'lotes') >= 1), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s3-dir-outra', 'pedido_receber', jsonb_build_object('id', v_ped));
  v_out := v_out || jsonb_build_object('passo', 'A7. Outra escola não recebe o pedido (deve negar)', 'ok', pg_temp.ok_erro(r, 'P0002'));
  r := pg_temp.as_call('s3-dir', 'pedido_receber', jsonb_build_object('id', v_ped,
         'itens', jsonb_build_array(jsonb_build_object('id', (select x ->> 'id' from jsonb_array_elements(v_itens) x where x ->> 'codigo' = 'LIM-002'), 'recebida', 1))));
  v_out := v_out || jsonb_build_object('passo', 'A8. Diferença no recebimento sem explicação é recusada', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s3-dir', 'pedido_receber', jsonb_build_object('id', v_ped,
         'itens', jsonb_build_array(jsonb_build_object('id', (select x ->> 'id' from jsonb_array_elements(v_itens) x where x ->> 'codigo' = 'LIM-002'), 'recebida', 1, 'divergencia', 'Um fardo chegou molhado'))));
  v_mat := (select id from iara.materiais where unit_id = v_unit and codigo = 'ALI-001' and ativo limit 1);
  v_out := v_out || jsonb_build_object('passo', 'A9. Recebido com divergência; o alimento entra na escola com lote e validade', 'ok', r ->> 'situacao' = 'RECEBIDO_PARCIAL'
    and exists (select 1 from iara.estoque_lotes l where l.material_id = v_mat and not l.is_demo and l.validade is not null), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s3-dir', 'material_movimentar', jsonb_build_object('id', v_mat, 'tipo', 'ENTRADA', 'quantidade', 2));
  v_out := v_out || jsonb_build_object('passo', 'A10. Entrada de alimento sem validade é recusada', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('s3-dir', 'material_movimentar', jsonb_build_object('id', v_mat, 'tipo', 'SAIDA', 'quantidade', 3, 'motivo', 'Almoço'));
  v_out := v_out || jsonb_build_object('passo', 'A11. Saída consome os lotes e o saldo bate com a soma dos lotes', 'ok', r ->> 'erro' is null
    and (select quantidade from iara.materiais where id = v_mat) = (select sum(quantidade) from iara.estoque_lotes where material_id = v_mat), 'erro', r ->> 'erro');
  v_lote := (select l.id from iara.estoque_lotes l join iara.materiais m on m.id = l.material_id where m.unit_id is null and l.quantidade > 0 limit 1);
  r := pg_temp.as_call('s3-dir', 'lote_descartar', jsonb_build_object('id', v_lote, 'motivo', 'Tentativa da escola'));
  v_out := v_out || jsonb_build_object('passo', 'A12. Escola não descarta lote do almoxarifado central (deve negar)', 'ok', pg_temp.ok_erro(r, 'P0002'));
  r := pg_temp.as_call('s3-fam', 'pedidos_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', 'A13. Família não vê pedidos (deve negar)', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('s3-al', 'almoxarifado_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', 'A14. Painel do almoxarifado: pedidos, validade e escolas com alimento para menos de 7 dias', 'ok', r -> 'pedidos' is not null
    and pg_temp.n(r -> 'cobertura_critica') >= 0 and (r ->> 'lotes_vencendo_30d')::int > 0, 'criticas', pg_temp.n(r -> 'cobertura_critica'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('s3-dir', 'cobertura_alimentos', '{}');
  v_out := v_out || jsonb_build_object('passo', 'A15. Escola vê a cobertura de cada alimento em dias (pelas refeições servidas)', 'ok', pg_temp.n(r) >= 5
    and exists (select 1 from jsonb_array_elements(r) x where (x ->> 'consumo_dia')::numeric > 0), 'erro', r ->> 'erro');

  raise exception 'RESULTADO: %', v_out;
end $$;
