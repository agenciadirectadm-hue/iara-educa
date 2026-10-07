-- IARA Educa — 034 · Preparação da saída da demonstração (Fase 2, item 7 do documento de estrutura)
-- Um só interruptor decide o que é de demonstração: tenants.settings.demo_mode. Desligado (produção):
--   · nenhuma seleção de perfil sem login (já era assim: iara.session_create);
--   · a IARA não usa código simulado nem presume identidade (gateway: Agent com { demo: false });
--   · o WhatsApp não presume identidade pelo número (abaixo);
--   · a bandeirinha de simulação não aparece (front: componente Simulado).
-- E um relatório do que ainda resta de demonstração no banco, base do teste "saída da demonstração".
begin;

-- o interruptor, em um lugar só ------------------------------------------------------------------------------------
create or replace function iara.demo_mode() returns boolean
language sql stable security definer set search_path = iara, public
as $$ select coalesce((settings ->> 'demo_mode')::boolean, false) from iara.tenants where id = 1 $$;

-- a flag DEMO_MODE fica só como espelho informativo do interruptor (quem vale é tenants.settings.demo_mode)
update iara.feature_flags
set enabled = iara.demo_mode(),
    description = 'Espelho do interruptor tenants.settings.demo_mode (o que vale). Ligado: dados pessoais fictícios, perfis selecionáveis, verificação simulada. Em produção: desligado.'
where code = 'DEMO_MODE';

-- WhatsApp: vincular conversa ao contato — identidade pelo número só na demonstração ------------------------------
create or replace function iara.whatsapp_vincular(p_contact uuid, p_conversation uuid) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  ct iara.whatsapp_contacts;
  v_nova boolean;
begin
  select * into ct from iara.whatsapp_contacts where id = p_contact;
  v_nova := ct.conversation_id is distinct from p_conversation;
  update iara.whatsapp_contacts set conversation_id = p_conversation where id = p_contact;
  update iara.conversations set channel = 'WHATSAPP',
         contact_phone_masked = coalesce(contact_phone_masked, iara.mask_phone(iara.fmt_tel(ct.telefone_e164))),
         -- produção: posse do número não comprova identidade (SEC-ID-09); só a demonstração presume
         identity_verified = identity_verified or (iara.demo_mode() and ct.guardian_id is not null)
  where id = p_conversation;
  return jsonb_build_object('nova', v_nova);
end $$;

-- depois de cada turno: cadastro feito pela conversa → o número vira o contato da família (identidade só na demonstração)
create or replace function iara.whatsapp_pos_turno(p_contact uuid) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  ct iara.whatsapp_contacts;
  v_g uuid;
begin
  select * into ct from iara.whatsapp_contacts where id = p_contact;
  select guardian_id into v_g from iara.app_users where id = ct.app_user_id;
  if v_g is not null and ct.guardian_id is distinct from v_g then
    update iara.whatsapp_contacts set guardian_id = v_g where id = p_contact;
    -- a família cadastrada por este contato fica com o número do WhatsApp (o cadastro sem telefone gera um fictício);
    -- identificador de privacidade (LID) não é telefone e não é gravado como tal
    if ct.telefone_e164 ~ '^\+55[0-9]{10,11}$' then
      update iara.guardians set whatsapp_phone = iara.fmt_tel(ct.telefone_e164), primary_phone = iara.fmt_tel(ct.telefone_e164),
             preferred_contact_channel = 'WHATSAPP'
      where id = v_g and created_by = ct.app_user_id;
    end if;
    update iara.conversations set identity_verified = identity_verified or iara.demo_mode(), guardian_id = coalesce(guardian_id, v_g),
           contact_phone_masked = iara.mask_phone(iara.fmt_tel(ct.telefone_e164))
    where id = ct.conversation_id;
  end if;
  return jsonb_build_object('guardian_id', v_g);
end $$;
revoke all on function iara.whatsapp_vincular(uuid, uuid), iara.whatsapp_pos_turno(uuid) from public;

-- relatório: tudo o que ainda é de demonstração neste banco (vazio = pronto para produção) ----------------------------
create or replace function iara.saida_demonstracao_relatorio() returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_is_demo jsonb := '{}'::jsonb;
  t record;
  n bigint;
begin
  for t in select c.table_name from information_schema.columns c
           where c.table_schema = 'iara' and c.column_name = 'is_demo' order by c.table_name loop
    execute format('select count(*) from iara.%I where is_demo', t.table_name) into n;
    if n > 0 then v_is_demo := v_is_demo || jsonb_build_object(t.table_name, n); end if;
  end loop;
  return jsonb_build_object(
    'demo_mode', iara.demo_mode(),
    'registros_is_demo', v_is_demo,
    'personas_sem_login', (select coalesce(jsonb_agg(code order by sort), '[]'::jsonb) from iara.organizational_roles where is_persona),
    'usuarios_demonstracao', (select count(*) from iara.app_users where auth_provider in ('DEMO', 'WHATSAPP')),
    'sessoes_ativas_demonstracao', (select count(*) from iara.app_sessions s join iara.app_users u on u.id = s.user_id
                                    where u.auth_provider in ('DEMO', 'WHATSAPP') and s.revoked_at is null and s.expires_at > now()),
    'funcoes_demo', (select coalesce(jsonb_agg(p.proname order by p.proname), '[]'::jsonb) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                     where ns.nspname = 'iara' and p.proname like 'demo\_%'),
    'metricas_demo', (select count(*) from iara.demo_metrics),
    'canal_whatsapp_nao_oficial', (select coalesce(jsonb_agg(jsonb_build_object('numero', iara.fmt_tel(numero_e164), 'provedor', provedor)), '[]'::jsonb)
                                   from iara.whatsapp_channels where provedor <> 'META_CLOUD'),
    'regras_de_referencia', (select count(*) from iara.rules where is_active and source_kind <> 'OFICIAL'),
    'pronto_para_producao', not iara.demo_mode()
      and not exists (select 1 from iara.organizational_roles where is_persona)
      and not exists (select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'iara' and p.proname like 'demo\_%')
      and v_is_demo = '{}'::jsonb
  );
end $$;
revoke all on function iara.saida_demonstracao_relatorio() from public;

-- leitura pelo painel técnico (Inovação, Secretário): o que falta para a saída
create or replace function api.saida_demonstracao(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('quality.read');
  return iara.saida_demonstracao_relatorio();
end $$;

commit;
