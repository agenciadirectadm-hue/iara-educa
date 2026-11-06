-- Recusa de vaga: o motivo é classificado em qualquer canal; os percentuais batem; cada perfil vê só o que pode; o mapa não traz nomes.
-- Roda numa transação revertida (não deixa resíduo). Executar: node scripts/aplicar.mjs supabase/tests/recusas_vaga.sql
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
  r jsonb; r2 jsonb;
  v_oferta uuid;
  v_cod text;
  v_nomes text[];
  v_txt text;
  v_g uuid;
  v_unit integer := (iara.setting('demo_unit_maria'))::int;
begin
  perform iara.session_create('PREFEITO', null, 'rc-pre', 'teste');
  perform iara.session_create('SECRETARIO', null, 'rc-sec', 'teste');
  perform iara.session_create('SUPERINTENDENCIA', null, 'rc-sup', 'teste');
  perform iara.session_create('ANALISTA_CENTRAL', null, 'rc-cen', 'teste');
  perform iara.session_create('CONTROLE_EXTERNO', null, 'rc-ext', 'teste');
  perform iara.session_create('DIRETOR_UNIDADE', v_unit, 'rc-dir', 'teste');
  perform iara.session_create('GERENCIA_EI', null, 'rc-ger', 'teste');
  perform iara.session_create('CIDADAO', null, 'rc-fam', 'teste');

  -- classificação
  v_out := v_out || jsonb_build_object('passo', 'R1. O motivo vira categoria: rótulo exato, palavras da família e texto solto', 'ok',
    iara.motivo_recusa_codigo('Turno ou horário não atende') = 'TURNO'
    and iara.motivo_recusa_codigo('Unidade distante') = 'DISTANCIA'
    and iara.motivo_recusa_codigo('Turno incompatível') = 'TURNO'
    and iara.motivo_recusa_codigo('Prefiro aguardar outra unidade') = 'OUTRA_UNIDADE'
    and iara.motivo_recusa_codigo('o ônibus não passa lá') = 'TRANSPORTE'
    and iara.motivo_recusa_codigo('Outro motivo: vamos nos mudar em janeiro') = 'MUDANCA'
    and iara.motivo_recusa_codigo('Outro motivo: a família vai cuidar da criança em casa') = 'OUTRO'
    and iara.motivo_recusa_codigo('Outro motivo') = 'OUTRO'
    and iara.motivo_recusa_codigo('   ') is null);

  -- recusa pelo caminho de sempre grava a categoria e mantém o texto
  select id into v_oferta from iara.vacancy_offers where status = 'OFFERED' and expires_at > now() + interval '1 hour' and is_demo limit 1;
  r := pg_temp.as_call('rc-cen', 'offer_respond', jsonb_build_object('offer_id', v_oferta, 'accept', false, 'reason', 'o ônibus não passa perto de casa', 'channel', 'PORTAL'));
  select decline_code into v_cod from iara.vacancy_offers where id = v_oferta;
  v_out := v_out || jsonb_build_object('passo', 'R2. Recusa pelo offer_respond grava a categoria e o texto da família', 'ok',
    (r ->> 'status') = 'DECLINED' and v_cod = 'TRANSPORTE'
    and (select decline_reason from iara.vacancy_offers where id = v_oferta) = 'o ônibus não passa perto de casa', 'r', r, 'cod', v_cod);

  r := pg_temp.as_call('rc-cen', 'recusas_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', 'R3. A Central vê a recusa, a unidade oferecida e o texto da família', 'ok',
    exists (select 1 from jsonb_array_elements(r -> 'registros') x where (x ->> 'id')::uuid = v_oferta
            and x ->> 'motivo_codigo' = 'TRANSPORTE' and x ->> 'texto' = 'o ônibus não passa perto de casa'
            and x ->> 'unidade' is not null and x ->> 'crianca' is not null and x ->> 'turma' is not null));

  update iara.vacancy_offers set status = 'OFFERED', declined_at = null, decline_reason = null where id = v_oferta;
  v_out := v_out || jsonb_build_object('passo', 'R4. Sem recusa não fica categoria', 'ok', (select decline_code is null from iara.vacancy_offers where id = v_oferta));
  update iara.vacancy_offers set status = 'DECLINED', declined_at = now(), decline_reason = 'Turno ou horário não atende' where id = v_oferta;

  -- percentuais
  r := pg_temp.as_call('rc-sec', 'recusas_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', 'R5. Os percentuais batem com a contagem das ofertas, sem canceladas e sem as em aberto', 'ok',
    (r -> 'totais' ->> 'decididas')::int = (select count(*) from iara.vacancy_offers where offered_at >= now() - interval '12 months' and status in ('ACCEPTED', 'ENROLLED', 'DECLINED', 'EXPIRED'))
    and (r -> 'totais' ->> 'recusadas')::int = (select count(*) from iara.vacancy_offers where offered_at >= now() - interval '12 months' and status = 'DECLINED')
    and (r -> 'totais' ->> 'pct_recusa')::int = round(100.0 * (r -> 'totais' ->> 'recusadas')::int / (r -> 'totais' ->> 'decididas')::int)::int
    and abs((r -> 'totais' ->> 'pct_aceite')::int + (r -> 'totais' ->> 'pct_recusa')::int + (r -> 'totais' ->> 'pct_sem_resposta')::int - 100) <= 1
    and (select sum((m ->> 'n')::int) from jsonb_array_elements(r -> 'motivos') m) = (r -> 'totais' ->> 'recusadas')::int
    and (select sum((u ->> 'recusadas')::int) from jsonb_array_elements(r -> 'unidades') u) = (r -> 'totais' ->> 'recusadas')::int, 'totais', r -> 'totais');
  v_out := v_out || jsonb_build_object('passo', 'R6. Secretário e Superintendência veem os nomes', 'ok',
    r ->> 'nivel' = 'NOMES' and jsonb_array_length(r -> 'registros') > 0
    and (pg_temp.as_call('rc-sup', 'recusas_painel', '{}') ->> 'nivel') = 'NOMES');

  -- Prefeito: só números
  select array_agg(distinct s.full_name) into v_nomes from iara.vacancy_offers o join iara.students s on s.id = o.student_id where o.status = 'DECLINED';
  r := pg_temp.as_call('rc-pre', 'recusas_painel', '{}');
  v_txt := r::text;
  v_out := v_out || jsonb_build_object('passo', 'R7. Prefeito vê os números e as unidades, sem nenhuma pessoa', 'ok',
    r ->> 'nivel' = 'NENHUM' and jsonb_array_length(r -> 'registros') = 0 and jsonb_array_length(r -> 'unidades') > 0
    and not exists (select 1 from unnest(v_nomes) n where position(n in v_txt) > 0));

  -- controle externo: código, sem nome e sem texto da família
  r := pg_temp.as_call('rc-ext', 'recusas_painel', '{}');
  v_txt := r::text;
  v_out := v_out || jsonb_build_object('passo', 'R8. Controle externo vê cada recusa pelo código, sem nome e sem o texto da família', 'ok',
    r ->> 'nivel' = 'CODIGOS' and jsonb_array_length(r -> 'registros') > 0
    and not exists (select 1 from jsonb_array_elements(r -> 'registros') x where x ->> 'codigo' is null or x ->> 'unidade' is null or x ->> 'motivo' is null
                      or x ? 'crianca' or x ? 'student_id' or x ? 'texto' or x ? 'turma')
    and not exists (select 1 from unnest(v_nomes) n where position(n in v_txt) > 0)
    and position('cuidar da criança em casa' in v_txt) = 0);

  -- quem não deve ver
  r := pg_temp.as_call('rc-dir', 'recusas_painel', '{}');
  r2 := pg_temp.as_call('rc-fam', 'recusas_painel', '{}');
  v_out := v_out || jsonb_build_object('passo', 'R9. Diretor, Gerência e família não entram no painel nem no mapa', 'ok',
    r ->> 'codigo' = '42501' and r2 ->> 'codigo' = '42501'
    and (pg_temp.as_call('rc-ger', 'recusas_painel', '{}') ->> 'codigo') = '42501'
    and (pg_temp.as_call('rc-fam', 'recusas_mapa', '{"camada": "oferta_recusa"}') ->> 'codigo') = '42501', 'r', r);

  -- mapa
  r := pg_temp.as_call('rc-pre', 'recusas_mapa', '{"camada": "oferta_aceite"}');
  v_txt := r::text;
  v_out := v_out || jsonb_build_object('passo', 'R10. Mapa de aceitação: faixas fixas, 100% é verde e a base aparece no ponto', 'ok',
    r ->> 'modo' = 'taxa' and jsonb_array_length(r -> 'pontos') > 0 and jsonb_array_length(r -> 'legenda') = 3
    and not exists (select 1 from jsonb_array_elements(r -> 'pontos') x where (x ->> 'valor')::int = 100 and x ->> 'cor' <> '#16A34A')
    and not exists (select 1 from jsonb_array_elements(r -> 'pontos') x where x ->> 'titulo' !~ 'aceitaram.*recusaram.*sem resposta \(\d+ oferta')
    and not exists (select 1 from unnest(v_nomes) n where position(n in v_txt) > 0));
  r := pg_temp.as_call('rc-ext', 'recusas_mapa', '{"camada": "oferta_recusa"}');
  v_out := v_out || jsonb_build_object('passo', 'R11. Mapa de recusa: 0% é verde e acima de 30% é vermelho', 'ok',
    not exists (select 1 from jsonb_array_elements(r -> 'pontos') x where (x ->> 'valor')::int = 0 and x ->> 'cor' <> '#16A34A')
    and not exists (select 1 from jsonb_array_elements(r -> 'pontos') x where (x ->> 'valor')::int > 30 and x ->> 'cor' <> '#DC2626')
    and jsonb_array_length(r -> 'niveis') > 0);
  r := pg_temp.as_call('rc-cen', 'recusas_mapa', '{"camada": "oferta_motivo"}');
  v_out := v_out || jsonb_build_object('passo', 'R12. Mapa de motivos: só unidades com recusa, cor do motivo principal e legenda com 3 cores e os demais', 'ok',
    jsonb_array_length(r -> 'pontos') > 0 and jsonb_array_length(r -> 'legenda') = 4
    and not exists (select 1 from jsonb_array_elements(r -> 'pontos') x where (x ->> 'valor')::int < 1 or x ->> 'cor' is null));
  r := pg_temp.as_call('rc-cen', 'recusas_mapa', '{"camada": "xpto"}');
  v_out := v_out || jsonb_build_object('passo', 'R13. Camada desconhecida é recusada', 'ok', r ->> 'codigo' = '22023');

  -- família: só o que é dela
  v_g := (select guardian_id from iara.app_users where id = (select user_id from iara.app_sessions where token_hash = 'rc-fam'));
  r := pg_temp.as_call('rc-fam', 'familia_ofertas', '{}');
  v_out := v_out || jsonb_build_object('passo', 'R14. A família vê só as ofertas das próprias crianças, sem as canceladas', 'ok',
    r ? 'ofertas'
    and jsonb_array_length(r -> 'ofertas') = (select count(*) from iara.vacancy_offers o where o.status <> 'CANCELLED'
        and exists (select 1 from iara.student_guardians sg where sg.student_id = o.student_id and sg.guardian_id = v_g))
    and not exists (select 1 from jsonb_array_elements(r -> 'ofertas') x where x ->> 'situacao' = 'CANCELLED')
    and exists (select 1 from jsonb_array_elements(r -> 'ofertas') x where x ->> 'situacao' = 'DECLINED' and x ->> 'crianca' = 'Davi' and x ->> 'unidade' is not null
                  and x ->> 'motivo' = 'Turno ou horário não atende' and x ->> 'respondida_em' is not null), 'n', jsonb_array_length(r -> 'ofertas'));
  r := pg_temp.as_call('rc-pre', 'familia_ofertas', '{}');
  v_out := v_out || jsonb_build_object('passo', 'R15. Quem não é responsável não usa a visão da família', 'ok', r ->> 'codigo' = '42501', 'r', r);

  -- cenário
  v_out := v_out || jsonb_build_object('passo', 'R16. Demonstração: motivos variados e nenhuma recusa com data à frente do relógio', 'ok',
    (select count(distinct decline_code) from iara.vacancy_offers where status = 'DECLINED') >= 8
    and not exists (select 1 from iara.vacancy_offers where status = 'DECLINED' and (decline_code is null or declined_at > now() + interval '1 minute'))
    and not exists (select 1 from iara.vacancy_offers where status = 'DECLINED' and decline_reason in ('Unidade distante do trabalho', 'Turno incompatível com o trabalho', 'Prefere aguardar a unidade preferida')));

  raise exception 'RESULTADO: %', v_out;
end $$;
