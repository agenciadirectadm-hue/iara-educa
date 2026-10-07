-- Saída da demonstração: com o interruptor tenants.settings.demo_mode DESLIGADO, nenhum mecanismo de demonstração funciona.
-- (Fase 2, item 7 do documento de estrutura.) Roda numa transação revertida: não deixa resíduo e não desliga a demonstração.
-- Executar: SQL_OUT_LIMIT=200000 node scripts/sql.mjs supabase/tests/saida_demonstracao.sql
-- Cada passo traz "ok": true quando o comportamento é o esperado.
do $$
declare
  v_out jsonb := '[]';
  v_ok boolean;
  v_err text;
  v_conv uuid;
  v_contact uuid;
  v_guardian uuid;
  r jsonb;
begin
  -- 0. desliga o interruptor só dentro desta transação
  update iara.tenants set settings = settings || '{"demo_mode": false}'::jsonb where id = 1;
  v_out := v_out || jsonb_build_object('passo', '0. Interruptor desligado', 'ok', iara.demo_mode() = false);

  -- 1. seleção de perfil sem login recusada
  begin
    perform iara.session_create('SECRETARIO', null, 'test-saida-demo', 'teste');
    v_err := null;
  exception when others then
    v_err := sqlstate;
  end;
  v_out := v_out || jsonb_build_object('passo', '1. Entrada por perfil sem login (deve negar)', 'ok', v_err = '42501', 'codigo', v_err);

  -- 2. WhatsApp: número ligado a uma família NÃO vira identidade verificada
  select id into v_guardian from iara.guardians limit 1;
  insert into iara.conversations (tenant_id, channel, contact_label, state, identity_verified, is_demo)
  values (1, 'WHATSAPP', 'Teste saída da demonstração', 'BOT_ACTIVE', false, true) returning id into v_conv;
  insert into iara.whatsapp_contacts (channel_id, telefone_e164, guardian_id)
  select id, '+5544900009999', v_guardian from iara.whatsapp_channels order by created_at limit 1
  returning id into v_contact;
  perform iara.whatsapp_vincular(v_contact, v_conv);
  select identity_verified into v_ok from iara.conversations where id = v_conv;
  v_out := v_out || jsonb_build_object('passo', '2. Número vinculado não presume identidade', 'ok', v_ok = false);

  -- 3. o mesmo cenário COM o interruptor ligado presume (comportamento atual da demonstração, preservado)
  update iara.tenants set settings = settings || '{"demo_mode": true}'::jsonb where id = 1;
  update iara.conversations set identity_verified = false where id = v_conv;
  perform iara.whatsapp_vincular(v_contact, v_conv);
  select identity_verified into v_ok from iara.conversations where id = v_conv;
  v_out := v_out || jsonb_build_object('passo', '3. Na demonstração o comportamento continua igual', 'ok', v_ok = true);
  update iara.tenants set settings = settings || '{"demo_mode": false}'::jsonb where id = 1;

  -- 4. o relatório de saída enxerga o interruptor e lista o que resta
  r := iara.saida_demonstracao_relatorio();
  v_out := v_out || jsonb_build_object('passo', '4. Relatório de saída', 'ok', (r ->> 'demo_mode')::boolean = false and r ? 'registros_is_demo',
    'pronto_para_producao', r -> 'pronto_para_producao', 'personas', jsonb_array_length(r -> 'personas_sem_login'),
    'funcoes_demo', jsonb_array_length(r -> 'funcoes_demo'));

  -- 5. o relógio da demonstração não mexe em nada com o interruptor desligado
  v_out := v_out || jsonb_build_object('passo', '5. Relógio da demonstração parado', 'ok', iara.demo_timeshift() = interval '0');

  raise exception 'RESULTADO: %', v_out;  -- reverte tudo
end $$;
