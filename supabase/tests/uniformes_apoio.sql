-- Uniformes e kits, apoio interdisciplinar, organograma da gerência e Ideb (migrações 099.05 a 099.10).
-- Roda numa transação revertida (não deixa resíduo). Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/uniformes_apoio.sql
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
  v_maria uuid := (iara.setting('demo_guardian_maria'))::uuid;
  v_ana uuid;
  v_unit integer;
  v_outra integer;
  v_aviso uuid;
  v_troca uuid;
  v_jaq numeric;
  v_nec uuid;
  v_caso uuid;
  v_caso_ana uuid;
  v_psi uuid;
  v_outro_aviso uuid;
  v_escola integer;
  v_cmei integer;
begin
  select sg.student_id, e.unit_id into v_ana, v_unit from iara.student_guardians sg join iara.enrollments e on e.student_id = sg.student_id and e.status = 'ACTIVE'
  where sg.guardian_id = v_maria order by sg.is_primary desc limit 1;
  select u.id into v_outra from iara.education_units u where u.status = 'ATIVA' and u.id <> v_unit order by u.id limit 1;
  perform iara.session_create('SECRETARIO', null, 'uk-seduc', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_unit, 'uk-dir', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_outra, 'uk-dir2', 'teste');
  perform iara.session_create('CIDADAO', null, 'uk-mae', 'teste');
  perform iara.session_create('TRIBUNAL_CONTAS', null, 'uk-tce', 'teste');
  perform iara.session_create('CONSELHO_TUTELAR', null, 'uk-ct', 'teste');
  perform iara.session_create('CAMARA', null, 'uk-cam', 'teste');
  perform iara.session_create('APOIO_INTERDISCIPLINAR', null, 'uk-api', 'teste');
  perform iara.session_create('GERENCIA_APOIO', null, 'uk-ger', 'teste');

  -- ---------------------------------------------------------------- regras de etapa e tamanho
  v_out := v_out || jsonb_build_object('passo', 'U0. Etapa: Ana no Infantil 4 em 2026 e no Infantil 5 em 2027; quem está no 5º ano sai em 2027', 'ok',
    iara.uk_etapa_aluno(v_ana, 2026) = 'INF4' and iara.uk_etapa_aluno(v_ana, 2027) = 'INF5'
    and not exists (select 1 from iara.uk_etapas(2027) e join iara.enrollments m on m.student_id = e.student_id and m.status = 'ACTIVE'
                    join iara.classes c on c.id = m.class_id join iara.grade_levels g on g.id = c.grade_level_id where g.code = 'EF5' and e.etapa is not null));

  -- ---------------------------------------------------------------- família
  r := pg_temp.as_call('uk-mae', 'familia_uniformes', '{}');
  v_out := v_out || jsonb_build_object('passo', 'U1. Família vê a Ana, o código da troca liberada e os avisos aguardando ciência', 'ok',
    jsonb_array_length(r -> 'filhos') >= 1 and (r ->> 'pendentes_ciencia')::int >= 2 and r::text like '%482 913%', 'erro', r ->> 'erro');
  r := pg_temp.as_call('uk-mae', 'familia_uniformes_tamanhos', jsonb_build_object('student_id', v_ana, 'ano', 2027, 'superior', '6', 'inferior', '6', 'calcado', 28));
  v_out := v_out || jsonb_build_object('passo', 'U2. Sem escolher o modelo (shorts-saia ou bermuda), o tamanho não é aceito', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('uk-mae', 'familia_uniformes_tamanhos', jsonb_build_object('student_id', v_ana, 'ano', 2027, 'superior', '6', 'inferior', '8', 'calcado', 29, 'modelo', 'SHORTS_SAIA', 'canal', 'WHATSAPP'));
  v_out := v_out || jsonb_build_object('passo', 'U3. Tamanho informado: a necessidade de 2027 tem shorts-saia e meias (Infantil 5), sem papete nem bermuda', 'ok',
    (r ->> 'ok')::boolean and exists (select 1 from iara.uk_necessidades n where n.student_id = v_ana and n.ano = 2027 and n.conteudo = 'UNIFORME' and n.situacao = 'AGUARDANDO_MATERIAL'
      and n.itens::text like '%UNI-SHS-T8%' and n.itens::text like '%UNI-MEI%' and n.itens::text not like '%UNI-PAP%' and n.itens::text not like '%UNI-BER%')
    and (select canal from iara.uk_tamanhos where student_id = v_ana and ano = 2027) = 'WHATSAPP', 'erro', r ->> 'erro');
  select id into v_aviso from iara.uk_avisos where student_id = v_ana and tipo = 'TAMANHO' and ciente_em is null limit 1;
  r := pg_temp.as_call('uk-mae', 'familia_uniformes_ciente', jsonb_build_object('id', v_aviso));
  v_out := v_out || jsonb_build_object('passo', 'U4. Ciência do aviso: sai do quadro e vai para o histórico', 'ok',
    (select ciente_em is not null from iara.uk_avisos where id = v_aviso) and not exists (select 1 from jsonb_array_elements(pg_temp.as_call('uk-mae', 'familia_uniformes', '{}') -> 'avisos') a where a ->> 'id' = v_aviso::text));
  select id into v_outro_aviso from iara.uk_avisos where student_id <> v_ana and ciente_em is null limit 1;
  r := pg_temp.as_call('uk-mae', 'familia_uniformes_ciente', jsonb_build_object('id', v_outro_aviso));
  v_out := v_out || jsonb_build_object('passo', 'U5. A família não dá ciência em aviso de outra criança', 'ok', pg_temp.ok_erro(r, 'P0002'));

  -- ---------------------------------------------------------------- retirada na unidade
  r := pg_temp.as_call('uk-dir2', 'uk_codigo_conferir', jsonb_build_object('codigo', '482913'));
  v_out := v_out || jsonb_build_object('passo', 'U6. Outra unidade não confere o código da Ana', 'ok', pg_temp.ok_erro(r, 'P0002'));
  r := pg_temp.as_call('uk-dir', 'uk_codigo_conferir', jsonb_build_object('codigo', '482 913'));
  select (x ->> 'id')::uuid into v_troca from jsonb_array_elements(r -> 'disponiveis') x limit 1;
  v_out := v_out || jsonb_build_object('passo', 'U7. A unidade confere o código: a troca da jaqueta está liberada e a mãe pode retirar', 'ok',
    (r ->> 'codigo_ok')::boolean and v_troca is not null and r::text like '%Maria Aparecida%', 'erro', r ->> 'erro');
  r := pg_temp.as_call('uk-dir', 'uk_retirada_registrar', jsonb_build_object('student_id', v_ana, 'ids', jsonb_build_array(v_troca), 'codigo', '482913', 'quem', jsonb_build_object('guardian_id', gen_random_uuid())));
  v_out := v_out || jsonb_build_object('passo', 'U8. Quem não é responsável nem autorizado não retira', 'ok', pg_temp.ok_erro(r, '22023'));
  select quantidade into v_jaq from iara.materiais where unit_id = v_unit and codigo = 'UNI-JAQ-T8' and ativo order by created_at limit 1;
  r := pg_temp.as_call('uk-dir', 'uk_retirada_registrar', jsonb_build_object('student_id', v_ana, 'ids', jsonb_build_array(v_troca), 'codigo', '482913', 'quem', jsonb_build_object('guardian_id', v_maria)));
  v_out := v_out || jsonb_build_object('passo', 'U9. Retirada pela mãe com código: fica na ficha, baixa o estoque da unidade e a família recebe a confirmação', 'ok',
    (r ->> 'ok')::boolean and (select situacao = 'RETIRADA' and codigo_conferido and retirada_por_parentesco = 'Mãe' from iara.uk_necessidades where id = v_troca)
    and (select quantidade from iara.materiais where unit_id = v_unit and codigo = 'UNI-JAQ-T8' and ativo order by created_at limit 1) = v_jaq - 1
    and exists (select 1 from iara.uk_avisos where student_id = v_ana and tipo = 'RETIRADA_REGISTRADA' and enviado_em > now() - interval '1 minute'), 'erro', r ->> 'erro');

  -- ---------------------------------------------------------------- troca pedida pela família e decisão
  r := pg_temp.as_call('uk-mae', 'familia_uniformes_pedir', jsonb_build_object('student_id', v_ana, 'tipo', 'TROCA_TAMANHO', 'motivo', 'ok'));
  v_out := v_out || jsonb_build_object('passo', 'U10a. Pedido sem explicar o que aconteceu é recusado', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('uk-mae', 'familia_uniformes_pedir', jsonb_build_object('student_id', v_ana, 'tipo', 'TROCA_TAMANHO', 'motivo', 'A calça 6 ficou curta; precisa da 8.'));
  v_nec := (r ->> 'id')::uuid;
  r := pg_temp.as_call('uk-dir', 'uk_necessidade_decidir', jsonb_build_object('id', v_nec, 'aprovar', false, 'motivo', 'não'));
  v_out := v_out || jsonb_build_object('passo', 'U10b. Negar exige resposta explicada à família', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('uk-dir', 'uk_necessidade_decidir', jsonb_build_object('id', v_nec, 'aprovar', true));
  v_out := v_out || jsonb_build_object('passo', 'U10c. Troca aprovada: aguarda o material e a família é avisada', 'ok',
    r ->> 'situacao' = 'AGUARDANDO_MATERIAL' and exists (select 1 from iara.uk_avisos where student_id = v_ana and tipo = 'DECISAO' and v_nec = any (necessidade_ids)), 'erro', r ->> 'erro');
  r := pg_temp.as_call('uk-dir2', 'uk_necessidade_decidir', jsonb_build_object('id', v_nec, 'aprovar', true));
  v_out := v_out || jsonb_build_object('passo', 'U10d. Outra unidade não decide o pedido', 'ok', r ? 'erro');

  -- ---------------------------------------------------------------- liberação por etapa e avisos em lote
  r := pg_temp.as_call('uk-dir', 'uk_disponibilizar', jsonb_build_object('ano', 2027, 'etapa', 'INF5', 'conteudo', 'UNIFORME'));
  v_out := v_out || jsonb_build_object('passo', 'U11. Liberar o Infantil 5: código e aviso para cada família, com data e hora', 'ok',
    (r ->> 'liberadas')::int >= 1 and (r ->> 'avisos')::int >= 1 and exists (select 1 from iara.uk_necessidades where student_id = v_ana and ano = 2027 and conteudo = 'UNIFORME' and situacao = 'DISPONIVEL')
    and exists (select 1 from iara.uk_codigos where student_id = v_ana and ano = 2027), 'erro', r ->> 'erro');
  r := pg_temp.as_call('uk-dir', 'uk_disparo_criar', jsonb_build_object('tipo', 'TAMANHO', 'ano', 2027));
  v_out := v_out || jsonb_build_object('passo', 'U12. Disparo da unidade só para quem não informou o tamanho e não recebeu aviso em 48 h', 'ok',
    (r ->> 'ok')::boolean and not exists (select 1 from iara.uk_avisos a where a.disparo_id = (r ->> 'id')::uuid and a.unit_id <> v_unit), 'erro', r ->> 'erro');
  v_out := v_out || jsonb_build_object('passo', 'U12b. Fila do WhatsApp em lotes: avisos espaçados pelo intervalo', 'ok',
    (select count(distinct agendado_para) = count(*) from iara.uk_avisos where whatsapp_status = 'AGENDADO'));

  -- ---------------------------------------------------------------- estatísticas, mapa e órgãos externos
  r := pg_temp.as_call('uk-tce', 'uk_estatisticas', jsonb_build_object('ano', 2026));
  v_out := v_out || jsonb_build_object('passo', 'U13. Tribunal de Contas: retirado, por unidade e valor de referência por aluno (sem nomes)', 'ok',
    (r -> 'totais' ->> 'retirados')::int > 0 and r -> 'custos' ->> 'por_aluno' is not null and jsonb_array_length(r -> 'por_unidade') > 50
    and r::text not like '%Maria Aparecida%', 'erro', r ->> 'erro');
  r := pg_temp.as_call('uk-cam', 'uk_estatisticas', jsonb_build_object('ano', 2026));
  v_out := v_out || jsonb_build_object('passo', 'U14. Câmara vê o agregado, sem valores', 'ok', r ? 'totais' and (r -> 'custos') = 'null'::jsonb, 'erro', r ->> 'erro');
  r := pg_temp.as_call('uk-mae', 'uk_estatisticas', '{}');
  v_out := v_out || jsonb_build_object('passo', 'U15. Família não vê as estatísticas da rede', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('uk-seduc', 'uk_mapa', jsonb_build_object('camada', 'uk_retirada', 'ano', 2026));
  v_out := v_out || jsonb_build_object('passo', 'U16. Mapa da retirada por unidade (pontos com cor e legenda)', 'ok', jsonb_array_length(r -> 'pontos') > 50 and jsonb_array_length(r -> 'legenda') = 3, 'erro', r ->> 'erro');
  r := pg_temp.as_call('uk-ct', 'uk_tutelar_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', 'U17. Conselho Tutelar: lista só por código público', 'ok',
    jsonb_array_length(r -> 'casos') > 0 and (r -> 'casos' -> 0 ->> 'codigo') like 'F-%' and r::text not like '%full_name%', 'erro', r ->> 'erro');
  r := pg_temp.as_call('uk-ct', 'uk_tutelar_consulta', jsonb_build_object('codigo', 'F-000000', 'motivo', 'curto'));
  v_out := v_out || jsonb_build_object('passo', 'U18a. Consulta sem motivo é recusada', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('uk-ct', 'uk_tutelar_consulta', jsonb_build_object('codigo', 'F-000000', 'motivo', 'Teste automatizado de código inexistente.'));
  v_out := v_out || jsonb_build_object('passo', 'U18b. Código inexistente: recusado e registrado na auditoria', 'ok',
    r ->> 'encontrado' = 'false' and exists (select 1 from iara.audit_log where action = 'TUTELAR_CONSULTA' and summary like '%F-000000%'), 'erro', r ->> 'erro');
  r := pg_temp.as_call('uk-tce', 'uk_tutelar_lista', '{}');
  v_out := v_out || jsonb_build_object('passo', 'U18c. Só o Conselho Tutelar vê a lista por código', 'ok', pg_temp.ok_erro(r, '42501'));

  -- ---------------------------------------------------------------- apoio interdisciplinar
  r := pg_temp.as_call('uk-mae', 'familia_apoio_pedir', jsonb_build_object('student_id', v_ana, 'area', 'FONOAUDIOLOGIA', 'motivo', 'Ela troca o R pelo L quando fala.'));
  v_out := v_out || jsonb_build_object('passo', 'A1a. Pedido repetido da mesma área em andamento é recusado', 'ok', pg_temp.ok_erro(r, '22023'));
  r := pg_temp.as_call('uk-mae', 'familia_apoio_pedir', jsonb_build_object('student_id', v_ana, 'area', 'PSICOLOGIA', 'motivo', 'Chora muito na chegada desde que o irmão nasceu.'));
  v_caso := (r ->> 'id')::uuid;
  v_out := v_out || jsonb_build_object('passo', 'A1b. A família pede avaliação de psicologia: vai para a escola analisar', 'ok',
    (select situacao = 'PEDIDO_FAMILIA' and origem = 'FAMILIA' from iara.apoio_casos where id = v_caso), 'erro', r ->> 'erro');
  r := pg_temp.as_call('uk-dir', 'apoio_encaminhar', jsonb_build_object('id', v_caso, 'aceitar', true, 'motivo', 'A professora confirma o choro diário na chegada.'));
  v_out := v_out || jsonb_build_object('passo', 'A2. A escola encaminha à gerência', 'ok', r ->> 'situacao' = 'ENCAMINHADO', 'erro', r ->> 'erro');
  select ap.staff_id into v_psi from iara.apoio_profissionais ap join iara.staff s on s.id = ap.staff_id where ap.area_codigo = 'PSICOLOGIA' and s.full_name = 'Juliana Prado Nunes';
  r := pg_temp.as_call('uk-api', 'apoio_atribuir', jsonb_build_object('id', v_caso, 'staff_id', v_psi));
  v_out := v_out || jsonb_build_object('passo', 'A3a. O profissional não distribui casos', 'ok', pg_temp.ok_erro(r, '42501'));
  r := pg_temp.as_call('uk-ger', 'apoio_atribuir', jsonb_build_object('id', v_caso, 'staff_id', v_psi));
  v_out := v_out || jsonb_build_object('passo', 'A3b. A gerência atribui à psicóloga: em triagem', 'ok', r ->> 'situacao' = 'EM_TRIAGEM', 'erro', r ->> 'erro');
  r := pg_temp.as_call('uk-api', 'apoio_registrar', jsonb_build_object('caso_id', v_caso, 'tipo', 'ATENDIMENTO', 'registro_tecnico', 'Teste'));
  v_out := v_out || jsonb_build_object('passo', 'A4a. A fonoaudióloga não registra no caso da psicóloga', 'ok', pg_temp.ok_erro(r, '42501'));
  select id into v_caso_ana from iara.apoio_casos where student_id = v_ana and area_codigo = 'FONOAUDIOLOGIA';
  r := pg_temp.as_call('uk-api', 'apoio_registrar', jsonb_build_object('caso_id', v_caso_ana, 'tipo', 'ATENDIMENTO', 'registro_tecnico', 'Sigiloso: teste de sigilo.',
    'orientacao_escola', 'Teste para a escola.', 'orientacao_familia', 'Teste para a família.'));
  v_out := v_out || jsonb_build_object('passo', 'A4b. A fonoaudióloga registra no caso da Ana (técnico e orientações)', 'ok', jsonb_array_length(r -> 'registros') >= 3, 'erro', r ->> 'erro');
  r := pg_temp.as_call('uk-dir', 'apoio_caso', jsonb_build_object('id', v_caso_ana));
  v_out := v_out || jsonb_build_object('passo', 'A5. A escola vê as orientações, não o registro técnico', 'ok',
    r::text like '%Teste para a escola.%' and r::text not like '%Sigiloso: teste de sigilo.%' and (r -> 'registros' -> 0 ->> 'tem_tecnico')::boolean, 'erro', r ->> 'erro');
  r := pg_temp.as_call('uk-ger', 'apoio_caso', jsonb_build_object('id', v_caso_ana));
  v_out := v_out || jsonb_build_object('passo', 'A6. A chefia vê o registro técnico', 'ok', r::text like '%Sigiloso: teste de sigilo.%', 'erro', r ->> 'erro');
  r := pg_temp.as_call('uk-dir2', 'apoio_caso', jsonb_build_object('id', v_caso_ana));
  v_out := v_out || jsonb_build_object('passo', 'A7. Outra unidade não vê o caso', 'ok', pg_temp.ok_erro(r, 'P0002'));
  r := pg_temp.as_call('uk-mae', 'familia_apoio', '{}');
  v_out := v_out || jsonb_build_object('passo', 'A8a. A família vê o andamento e as orientações, nunca o técnico', 'ok',
    (r ->> 'pendentes_ciencia')::int >= 2 and r::text like '%Teste para a família.%' and r::text not like '%Sigiloso%' and r::text not like '%Teste para a escola.%', 'erro', r ->> 'erro');
  r := pg_temp.as_call('uk-mae', 'familia_apoio_ciente', jsonb_build_object('id', (select id from iara.apoio_registros where caso_id = v_caso_ana and orientacao_familia = 'Teste para a família.')));
  v_out := v_out || jsonb_build_object('passo', 'A8b. Ciência da família na orientação', 'ok', r ->> 'ciente_em' is not null, 'erro', r ->> 'erro');
  v_out := v_out || jsonb_build_object('passo', 'A9. A trilha de auditoria não guarda o conteúdo técnico', 'ok',
    not exists (select 1 from iara.audit_log where summary like '%Sigiloso: teste de sigilo%' or after_json::text like '%Sigiloso: teste de sigilo%'));

  -- ---------------------------------------------------------------- organograma e Ideb
  v_out := v_out || jsonb_build_object('passo', 'O1. A gerência tem as 8 áreas oficiais e as funções com atribuições', 'ok',
    (select count(*) from iara.org_setores where superior_id = (select id from iara.org_setores where sigla = 'GEE')) = 8
    and (select count(*) from iara.org_funcoes where fonte = 'OFICIAL') >= 11
    and (select telefone from iara.org_setores where sigla = 'GEE') = '(44) 3221-6936');
  select u.id into v_escola from iara.education_units u join iara.ideb_escolas e on e.inep = u.inep_code where e.ano = 2025 and e.ideb is not null limit 1;
  select id into v_cmei from iara.education_units where unit_type = 'CMEI' limit 1;
  r := api.ideb_unidade(jsonb_build_object('unit_id', v_escola));
  v_out := v_out || jsonb_build_object('passo', 'I1. Ideb da escola: série 2005–2025 com a rede ao lado', 'ok', (r ->> 'tem')::boolean and jsonb_array_length(r -> 'serie') = 11, 'erro', r ->> 'erro');
  r := api.ideb_unidade(jsonb_build_object('unit_id', v_cmei));
  v_out := v_out || jsonb_build_object('passo', 'I2. CMEI não tem Ideb (e diz por quê)', 'ok', not (r ->> 'tem')::boolean and r ->> 'motivo' is not null);
  r := api.ideb_rede('{}');
  v_out := v_out || jsonb_build_object('passo', 'I3. Rede municipal: Ideb 7,4 em 2025 (INEP)', 'ok', (r -> 'rede' -> -1 ->> 'ideb')::numeric = 7.4 and (r ->> 'ultimo_ano')::int = 2025);

  raise exception 'RESULTADO: %', v_out;
end $$;
