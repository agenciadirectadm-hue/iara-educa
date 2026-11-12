-- Acesso das famílias pela conversa com a IARA (migração 099.13): níveis, código de uso único, QR da escola e troca de número.
-- Roda numa transação revertida (não deixa resíduo), com a demonstração DESLIGADA dentro da transação, como em produção.
-- Executar: node scripts/aplicar.mjs supabase/tests/acesso_familias.sql
create or replace function pg_temp.como(p_uid uuid, p_fn text, p_args jsonb) returns jsonb language plpgsql as $f$
declare
  v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute format('select api.%I($1)', p_fn) into v using p_args;
  execute 'reset role';
  return v;
exception when others then
  execute 'reset role';
  return jsonb_build_object('erro', sqlerrm, 'codigo', sqlstate);
end $f$;

-- o código que saiu na fila do WhatsApp (só existe em claro até ser usado)
create or replace function pg_temp.codigo_enviado(p_codigo uuid) returns text language sql as $f$
  select substring(o.texto from '\*([0-9]{6})\*') from iara.whatsapp_outbox o join iara.familia_codigos c on c.outbox_id = o.id where c.id = p_codigo
$f$;

do $$
declare
  v_out jsonb := '[]';
  r jsonb;
  v_canal uuid := (select id from iara.whatsapp_channels order by created_at limit 1);
  v_analista uuid;
  v_g1 uuid := gen_random_uuid();
  v_g2 uuid := gen_random_uuid();
  v_aluno uuid := gen_random_uuid();
  c_g1 jsonb; c_estranho jsonb; c_novo jsonb; c_outro jsonb;
  v_conv uuid;
  v_token text;
  v_cod uuid;
  v_troca iara.familia_trocas_numero;
  v_n integer;
begin
  -- sessão da Central (antes de desligar a demonstração: a seleção de perfil só existe nela)
  perform iara.session_create('ANALISTA_CENTRAL', null, 'test-acesso-central', 'teste');
  v_analista := (select user_id from iara.app_sessions where token_hash = 'test-acesso-central');
  update iara.tenants set settings = settings || '{"demo_mode": false}'::jsonb where id = 1;

  -- cadastro oficial: Joana (WhatsApp 44 98888-1111) e Pedro (44 98888-3333), responsáveis da mesma criança
  insert into iara.guardians (id, tenant_id, full_name, cpf, whatsapp_phone, primary_phone, is_demo)
  values (v_g1, 1, 'Joana Teste Acesso', '529.982.247-25', '(44) 98888-1111', '(44) 98888-1111', false),
         (v_g2, 1, 'Pedro Teste Acesso', null, '(44) 98888-3333', null, false);
  insert into iara.students (id, tenant_id, full_name, birth_date, is_demo) values (v_aluno, 1, 'Criança Teste Acesso', '2019-05-10', false);
  insert into iara.student_guardians (student_id, guardian_id, relationship) values (v_aluno, v_g1, 'MAE'), (v_aluno, v_g2, 'PAI');

  -- 1. número fora do cadastro: nível 0
  c_estranho := iara.whatsapp_contato(v_canal, '+5544911110000', 'Estranho', '');
  r := pg_temp.como((c_estranho ->> 'user_id')::uuid, 'iara_conversation', '{"channel": "WHATSAPP"}');
  v_conv := coalesce((r -> 'conversation' ->> 'id'), r ->> 'id')::uuid;
  perform iara.whatsapp_vincular((c_estranho ->> 'contact_id')::uuid, v_conv);
  v_out := v_out || jsonb_build_object('passo', '1. Número fora do cadastro: nível 0, sem responsável', 'ok',
    exists (select 1 from iara.conversations where id = v_conv and identity_level = 0 and not identity_verified and guardian_id is null));

  -- 2. número do cadastro: nível 1 e o responsável certo (inclusive o WhatsApp sem o 9)
  c_g1 := iara.whatsapp_contato(v_canal, '+554488881111', 'Joana', '');
  r := pg_temp.como((c_g1 ->> 'user_id')::uuid, 'iara_conversation', '{"channel": "WHATSAPP"}');
  v_conv := coalesce((r -> 'conversation' ->> 'id'), r ->> 'id')::uuid;
  perform iara.whatsapp_vincular((c_g1 ->> 'contact_id')::uuid, v_conv);
  v_out := v_out || jsonb_build_object('passo', '2. Número do cadastro (sem o 9): nível 1, Joana', 'ok',
    exists (select 1 from iara.conversations where id = v_conv and identity_level = 1 and identity_verified and guardian_id = v_g1)
    and (select guardian_id from iara.app_users where id = (c_g1 ->> 'user_id')::uuid) = v_g1);
  r := pg_temp.como((c_g1 ->> 'user_id')::uuid, 'iara_send', jsonb_build_object('conversation_id', v_conv, 'body', 'oi'));
  v_out := v_out || jsonb_build_object('passo', '2b. O retrato da conversa traz o nível', 'ok', (r ->> 'identity_level')::int = 1);

  -- 3. QR da secretaria: sem documento conferido, não gera
  r := pg_temp.como(v_analista, 'familia_vinculo_qr', jsonb_build_object('guardian_id', v_g1, 'documento_tipo', 'RG'));
  v_out := v_out || jsonb_build_object('passo', '3a. QR sem documento conferido: recusado', 'ok', r ->> 'codigo' = '22023');
  r := pg_temp.como(v_analista, 'familia_vinculo_qr', jsonb_build_object('guardian_id', v_g1, 'documento_tipo', 'RG', 'documento_conferido', true));
  v_token := r ->> 'token';
  v_out := v_out || jsonb_build_object('passo', '3b. QR gerado: 8 caracteres, link do WhatsApp, só o hash guardado', 'ok',
    v_token ~ '^[A-HJ-NP-Z2-9]{8}$' and r ->> 'link' like 'https://wa.me/%VINCULAR%20' || v_token
    and not exists (select 1 from iara.familia_qr where token_hash = v_token));

  -- 4. o responsável aponta o WhatsApp: nível 2; o mesmo QR não vale de novo
  r := iara.familia_vinculo_qr_usar((c_g1 ->> 'contact_id')::uuid, lower(v_token));
  v_out := v_out || jsonb_build_object('passo', '4a. QR usado pelo número da Joana: nível 2', 'ok',
    (r ->> 'ok')::boolean and exists (select 1 from iara.conversations where id = v_conv and identity_level = 2)
    and (iara.familia_identificar('+5544988881111') ->> 'nivel')::int = 2);
  r := iara.familia_vinculo_qr_usar((c_g1 ->> 'contact_id')::uuid, v_token);
  v_out := v_out || jsonb_build_object('passo', '4b. O mesmo QR não vale de novo', 'ok', not (r ->> 'ok')::boolean);

  -- 5. QR vencido e QR de outro responsável
  r := pg_temp.como(v_analista, 'familia_vinculo_qr', jsonb_build_object('guardian_id', v_g1, 'documento_tipo', 'CNH', 'documento_conferido', true));
  update iara.familia_qr set expira_em = now() - interval '1 minute' where token_hash = iara.familia_hash('qr:' || (r ->> 'token'));
  r := iara.familia_vinculo_qr_usar((c_g1 ->> 'contact_id')::uuid, r ->> 'token');
  v_out := v_out || jsonb_build_object('passo', '5a. QR vencido: recusado', 'ok', not (r ->> 'ok')::boolean and r ->> 'mensagem' like '%venceu%');
  r := pg_temp.como(v_analista, 'familia_vinculo_qr', jsonb_build_object('guardian_id', v_g2, 'documento_tipo', 'RG', 'documento_conferido', true));
  r := iara.familia_vinculo_qr_usar((c_g1 ->> 'contact_id')::uuid, r ->> 'token');
  v_out := v_out || jsonb_build_object('passo', '5b. Número da Joana no QR do Pedro: recusado', 'ok',
    not (r ->> 'ok')::boolean and r ->> 'mensagem' like '%outro responsável%'
    and not exists (select 1 from iara.familia_vinculos where guardian_id = v_g2));

  -- 6. celular dividido não chega ao nível 2
  update iara.guardians set primary_phone = '(44) 98888-1111' where id = v_g2;
  v_out := v_out || jsonb_build_object('passo', '6. Número dividido com outro responsável: nível 1', 'ok',
    (iara.familia_identificar('+5544988881111') ->> 'nivel')::int = 1);
  update iara.guardians set primary_phone = null where id = v_g2;

  -- 7. código de uso único: errado conta, certo vale uma vez, e o texto enviado perde o código
  v_cod := iara.familia_codigo_emitir(v_g1, '+5544988881111', 'ACAO', 'teste', null, 10, 'Seu código: *{codigo}*');
  r := iara.familia_codigo_conferir(v_cod, '000000');
  if pg_temp.codigo_enviado(v_cod) = '000000' then r := iara.familia_codigo_conferir(v_cod, '111111'); end if;
  v_out := v_out || jsonb_build_object('passo', '7a. Código errado: restam 4', 'ok', r ->> 'motivo' = 'ERRADO' and (r ->> 'restantes')::int = 4
    and not exists (select 1 from iara.familia_codigos where id = v_cod and codigo_hash = pg_temp.codigo_enviado(v_cod)));
  r := iara.familia_codigo_conferir(v_cod, pg_temp.codigo_enviado(v_cod));
  v_out := v_out || jsonb_build_object('passo', '7b. Código certo: aceito e apagado do texto enviado', 'ok',
    (r ->> 'ok')::boolean and pg_temp.codigo_enviado(v_cod) is null);
  r := iara.familia_codigo_conferir(v_cod, '123456');
  v_out := v_out || jsonb_build_object('passo', '7c. Código já usado: não vale', 'ok', r ->> 'motivo' = 'INVALIDO');
  v_cod := iara.familia_codigo_emitir(v_g1, '+5544988881111', 'ACAO', 'teste', null, 10, 'Seu código: *{codigo}*');
  for v_n in 1 .. 5 loop
    r := iara.familia_codigo_conferir(v_cod, case when pg_temp.codigo_enviado(v_cod) = '999999' then '888888' else '999999' end);
  end loop;
  v_out := v_out || jsonb_build_object('passo', '7d. Cinco erros: código bloqueado', 'ok', r ->> 'motivo' = 'BLOQUEADO'
    and exists (select 1 from iara.familia_codigos where id = v_cod and bloqueado_em is not null));

  -- 8. troca pelo número novo: pede o CPF, o código vai ao número antigo; resposta igual com CPF desconhecido
  c_novo := iara.whatsapp_contato(v_canal, '+5544977772222', 'Joana nova', '');
  r := pg_temp.como((c_novo ->> 'user_id')::uuid, 'iara_conversation', '{"channel": "WHATSAPP"}');
  perform iara.whatsapp_vincular((c_novo ->> 'contact_id')::uuid, coalesce((r -> 'conversation' ->> 'id'), r ->> 'id')::uuid);
  r := pg_temp.como((c_novo ->> 'user_id')::uuid, 'familia_troca_pedir', '{"cpf": "11122233344"}');
  v_out := v_out || jsonb_build_object('passo', '8a. CPF fora do cadastro: mesma resposta, nenhum código', 'ok',
    (r ->> 'ok')::boolean and not exists (select 1 from iara.familia_trocas_numero where guardian_id = v_g1));
  r := pg_temp.como((c_novo ->> 'user_id')::uuid, 'familia_troca_pedir', '{"cpf": "529.982.247-25"}');
  select * into v_troca from iara.familia_trocas_numero where guardian_id = v_g1 order by pedido_em desc limit 1;
  v_out := v_out || jsonb_build_object('passo', '8b. CPF da Joana: código enviado ao número antigo', 'ok',
    (r ->> 'ok')::boolean and v_troca.telefone_antigo = '+5544988881111' and v_troca.telefone_novo = '+5544977772222'
    and exists (select 1 from iara.whatsapp_outbox o join iara.familia_codigos c on c.outbox_id = o.id
                where c.id = v_troca.codigo_id and o.telefone_e164 = '+5544988881111' and o.texto like '%NÃO FUI EU%'));
  r := pg_temp.como((c_novo ->> 'user_id')::uuid, 'familia_troca_confirmar', jsonb_build_object('codigo', pg_temp.codigo_enviado(v_troca.codigo_id)));
  select * into v_troca from iara.familia_trocas_numero where id = v_troca.id;
  v_out := v_out || jsonb_build_object('passo', '8c. Código certo no número novo: vale em 48 h, avisa o antigo e o Pedro', 'ok',
    (r ->> 'ok')::boolean and v_troca.libera_em between now() + interval '47 hours' and now() + interval '49 hours'
    and exists (select 1 from iara.whatsapp_outbox where telefone_e164 = '+5544988883333' and texto like '%Joana%48 horas%'));

  -- 9. antes das 48 h nada muda; depois, o cadastro troca e o vínculo da escola do número antigo cai
  perform iara.whatsapp_vincular((c_novo ->> 'contact_id')::uuid, (select conversation_id from iara.whatsapp_contacts where id = (c_novo ->> 'contact_id')::uuid));
  v_out := v_out || jsonb_build_object('passo', '9a. Antes das 48 h: número novo ainda no nível 0', 'ok',
    (iara.familia_identificar('+5544977772222') ->> 'nivel')::int = 0
    and (select whatsapp_phone from iara.guardians where id = v_g1) = '(44) 98888-1111');
  update iara.familia_trocas_numero set libera_em = now() - interval '1 minute' where id = v_troca.id;
  perform iara.whatsapp_vincular((c_novo ->> 'contact_id')::uuid, (select conversation_id from iara.whatsapp_contacts where id = (c_novo ->> 'contact_id')::uuid));
  v_out := v_out || jsonb_build_object('passo', '9b. Depois das 48 h: cadastro com o número novo (nível 1), vínculo antigo revogado', 'ok',
    (select whatsapp_phone from iara.guardians where id = v_g1) = '(44) 97777-2222'
    and (iara.familia_identificar('+5544977772222') ->> 'nivel')::int = 1
    and (iara.familia_identificar('+5544988881111') ->> 'nivel')::int = 0
    and not exists (select 1 from iara.familia_vinculos where guardian_id = v_g1 and revogado_em is null));

  -- 10. "não fui eu": o número do cadastro cancela o pedido feito por outro número, e o cadastro fica 24 h sem novo código
  c_outro := iara.whatsapp_contato(v_canal, '+5544966663333', 'Golpista', '');
  r := pg_temp.como((c_outro ->> 'user_id')::uuid, 'iara_conversation', '{"channel": "WHATSAPP"}');
  perform iara.whatsapp_vincular((c_outro ->> 'contact_id')::uuid, coalesce((r -> 'conversation' ->> 'id'), r ->> 'id')::uuid);
  r := pg_temp.como((c_outro ->> 'user_id')::uuid, 'familia_troca_pedir', '{"cpf": "52998224725"}');
  r := pg_temp.como((c_novo ->> 'user_id')::uuid, 'familia_troca_contestar', '{}');
  v_out := v_out || jsonb_build_object('passo', '10a. Não fui eu: pedido cancelado', 'ok', (r ->> 'canceladas')::int = 1);
  r := pg_temp.como((c_outro ->> 'user_id')::uuid, 'familia_troca_confirmar', '{"codigo": "123456"}');
  v_out := v_out || jsonb_build_object('passo', '10b. O outro número não confirma mais', 'ok', r ->> 'motivo' = 'SEM_PEDIDO');
  select count(*) into v_n from iara.familia_trocas_numero where guardian_id = v_g1;
  r := pg_temp.como((c_outro ->> 'user_id')::uuid, 'familia_troca_pedir', '{"cpf": "52998224725"}');
  v_out := v_out || jsonb_build_object('passo', '10c. Depois de contestado: 24 h sem novo código', 'ok',
    (r ->> 'ok')::boolean and (select count(*) from iara.familia_trocas_numero where guardian_id = v_g1) = v_n);

  -- 11. situação na ficha e revogação pela secretaria
  r := pg_temp.como(v_analista, 'familia_vinculo_situacao', jsonb_build_object('guardian_id', v_g1));
  v_out := v_out || jsonb_build_object('passo', '11a. Ficha mostra o número mascarado e o histórico', 'ok',
    r ->> 'numero_cadastro' like '%••%' and jsonb_array_length(r -> 'historico') >= 1 and (r ->> 'pode_vincular')::boolean);
  r := pg_temp.como(v_analista, 'familia_vinculo_revogar', jsonb_build_object('guardian_id', v_g1));
  v_out := v_out || jsonb_build_object('passo', '11b. Revogar sem motivo: recusado', 'ok', r ->> 'codigo' = '22023');

  -- 12. LGPD: nenhuma coluna nova sem classificação
  r := iara.classificacao_pendente();
  v_out := v_out || jsonb_build_object('passo', '12. Colunas novas classificadas (LGPD)', 'ok', r = '[]'::jsonb, 'lista', r);

  raise exception 'RESULTADO: %', v_out;  -- reverte tudo
end $$;
