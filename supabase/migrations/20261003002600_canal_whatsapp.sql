-- =============================================================================
-- IARA Educa · Canal WhatsApp real (vinculação de um número ao agente)
--
--   celular do cidadão ──► WhatsApp ──► ponte (whatsapp-ponte/, Baileys) ──► gateway /whatsapp/entrada
--                                                                               │ mesmo agente do portal
--   celular do cidadão ◄── WhatsApp ◄── ponte ◄──────── respostas da IARA ◄─────┘
--                                         └── fila de saída (resposta de servidor, aviso de oferta) ◄── banco
--
-- · O número é o mesmo chip da IARA Saúde (+55 44 99774-8259): cada sistema tem a SUA ponte (aparelho
--   conectado próprio). Liga-se um de cada vez — com as duas ligadas, as duas responderiam.
-- · A ponte se autentica com um segredo; o banco guarda só o hash (whatsapp_channels.segredo_hash).
-- · Desligado (ativo = false): o gateway não responde nem entrega nada; a ponte pode continuar conectada.
-- · Cada telefone vira um contato com usuário próprio (auth_provider WHATSAPP, perfil de família nova);
--   ao fazer o cadastro pela conversa, o número do WhatsApp vira o contato da família (posse do aparelho).
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
-- =============================================================================
begin;

-- 1. Permissão de gestão do canal ------------------------------------------------------------
insert into iara.permissions (code, description, is_sensitive)
values ('channels.manage', 'Ligar, desligar e acompanhar o WhatsApp da IARA', false)
on conflict (code) do nothing;
insert into iara.role_permissions (role_code, permission_code)
values ('SECRETARIO', 'channels.manage'), ('INOVACAO', 'channels.manage')
on conflict do nothing;

-- 2. Tabelas ------------------------------------------------------------------------------------
create table if not exists iara.whatsapp_channels (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null default 1,
  numero_e164 text not null unique check (numero_e164 ~ '^\+[1-9][0-9]{9,14}$'),
  nome text not null default 'IARA Educa',
  provedor text not null default 'BAILEYS' check (provedor in ('BAILEYS', 'EVOLUTION', 'META_CLOUD')),
  ativo boolean not null default false,
  estado text not null default 'SEM_PONTE' check (estado in ('SEM_PONTE', 'AGUARDANDO_PAREAMENTO', 'CONECTADO', 'DESCONECTADO')),
  conectado boolean not null default false,
  segredo_hash text,
  compartilhado_com text,
  observacoes text,
  ultimo_sinal_em timestamptz,
  pareado_em timestamptz,
  ligado_em timestamptz,
  desligado_em timestamptz,
  alterado_por text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists iara.whatsapp_contacts (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references iara.whatsapp_channels(id) on delete cascade,
  telefone_e164 text not null,
  jid text,
  nome_wa text,
  app_user_id uuid references iara.app_users(id) on delete set null,
  guardian_id uuid references iara.guardians(id) on delete set null,
  conversation_id uuid references iara.conversations(id) on delete set null,
  primeira_em timestamptz not null default now(),
  ultima_em timestamptz not null default now(),
  unique (channel_id, telefone_e164)
);
create index if not exists whatsapp_contacts_guardian_idx on iara.whatsapp_contacts (guardian_id);
create index if not exists whatsapp_contacts_conversation_idx on iara.whatsapp_contacts (conversation_id);

-- mensagens recebidas (idempotência: o WhatsApp pode reentregar a mesma mensagem)
create table if not exists iara.whatsapp_inbound (
  wa_id text primary key,
  channel_id uuid not null references iara.whatsapp_channels(id) on delete cascade,
  contact_id uuid references iara.whatsapp_contacts(id) on delete set null,
  received_at timestamptz not null default now()
);
create index if not exists whatsapp_inbound_time_idx on iara.whatsapp_inbound (channel_id, received_at desc);

-- fila de saída: o que não é resposta imediata (servidor respondendo, aviso de oferta, matrícula...)
create table if not exists iara.whatsapp_outbox (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references iara.whatsapp_channels(id) on delete cascade,
  contact_id uuid references iara.whatsapp_contacts(id) on delete cascade,
  telefone_e164 text not null,
  jid text,
  texto text not null,
  origem text not null check (origem in ('SERVIDOR', 'NOTIFICACAO')),
  ref_id uuid,
  status text not null default 'PENDENTE' check (status in ('PENDENTE', 'ENVIANDO', 'ENVIADA', 'ERRO', 'EXPIRADA')),
  tentativas smallint not null default 0,
  erro text,
  wa_id text,
  created_at timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  enviada_em timestamptz
);
create index if not exists whatsapp_outbox_fila_idx on iara.whatsapp_outbox (channel_id, status, created_at);

-- conversas pelo WhatsApp de verdade (além do simulado e do portal)
alter table iara.conversations drop constraint if exists conversations_channel_check;
alter table iara.conversations add constraint conversations_channel_check check (channel in ('WHATSAPP_SIMULADO', 'WHATSAPP', 'PORTAL'));

alter table iara.whatsapp_channels enable row level security;
alter table iara.whatsapp_contacts enable row level security;
alter table iara.whatsapp_inbound enable row level security;
alter table iara.whatsapp_outbox enable row level security;

-- 3. O número: mesmo chip da IARA Saúde, desligado até ser usado -------------------------------
insert into iara.whatsapp_channels (numero_e164, nome, provedor, ativo, estado, compartilhado_com, observacoes)
values ('+5544997748259', 'IARA Educa', 'BAILEYS', false, 'SEM_PONTE', 'IARA Saúde',
        'Mesmo chip da IARA Saúde. Ligue um de cada vez: pare a ponte da Saúde antes de ligar a da Educação (e vice-versa).')
on conflict (numero_e164) do update set compartilhado_com = excluded.compartilhado_com, observacoes = excluded.observacoes;

-- 4. Funções internas (chamadas pelo gateway) ----------------------------------------------------
create or replace function iara.fmt_tel(p text) returns text
language sql immutable
as $$
  select case
           when d ~ '^55[0-9]{11}$' then format('(%s) %s-%s', substr(d, 3, 2), substr(d, 5, 5), substr(d, 10, 4))
           when d ~ '^55[0-9]{10}$' then format('(%s) %s-%s', substr(d, 3, 2), substr(d, 5, 4), substr(d, 9, 4))
           else p end
  from (select regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') as d) z
$$;

create or replace function iara.whatsapp_canal_por_segredo(p_hash text) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select to_jsonb(c) - 'segredo_hash' from iara.whatsapp_channels c where c.segredo_hash = p_hash and p_hash is not null limit 1
$$;

create or replace function iara.whatsapp_canal_ligar(p_canal uuid, p_ativo boolean, p_origem text) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.whatsapp_channels;
begin
  update iara.whatsapp_channels set ativo = p_ativo,
         ligado_em = case when p_ativo then now() else ligado_em end,
         desligado_em = case when not p_ativo then now() else desligado_em end,
         alterado_por = left(coalesce(p_origem, 'sistema'), 120), updated_at = now()
  where id = p_canal
  returning * into c;
  if not found then
    raise exception 'Canal não encontrado.' using errcode = 'P0002';
  end if;
  -- desligado não entrega nada atrasado depois: a fila pendente expira
  if not p_ativo then
    update iara.whatsapp_outbox set status = 'EXPIRADA', atualizado_em = now() where channel_id = p_canal and status in ('PENDENTE', 'ENVIANDO', 'ERRO');
  end if;
  perform iara.audit_event('WHATSAPP_CANAL', 'whatsapp_channel', p_canal::text, null,
    format('WhatsApp da IARA (%s) %s por %s.', iara.fmt_tel(c.numero_e164), case when p_ativo then 'LIGADO' else 'DESLIGADO' end, coalesce(p_origem, 'sistema')));
  return jsonb_build_object('ativo', c.ativo, 'numero', c.numero_e164);
end $$;

create or replace function iara.whatsapp_canal_estado(p_canal uuid, p_estado text, p_conectado boolean) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.whatsapp_channels;
begin
  update iara.whatsapp_channels set
         estado = case when p_estado in ('SEM_PONTE', 'AGUARDANDO_PAREAMENTO', 'CONECTADO', 'DESCONECTADO') then p_estado else estado end,
         conectado = coalesce(p_conectado, false), ultimo_sinal_em = now(),
         pareado_em = case when p_estado = 'CONECTADO' and pareado_em is null then now() else pareado_em end,
         updated_at = now()
  where id = p_canal
  returning * into c;
  return jsonb_build_object('ativo', c.ativo, 'numero', c.numero_e164, 'estado', c.estado);
end $$;

-- true se a mensagem é nova (a mesma mensagem reentregue não é respondida duas vezes)
create or replace function iara.whatsapp_registrar_entrada(p_canal uuid, p_wa_id text) returns boolean
language plpgsql security definer set search_path = iara, public
as $$
begin
  insert into iara.whatsapp_inbound (wa_id, channel_id) values (left(p_wa_id, 200), p_canal) on conflict do nothing;
  return found;
end $$;

-- contato do WhatsApp → usuário próprio (perfil de família nova até fazer o cadastro pela conversa)
create or replace function iara.whatsapp_contato(p_canal uuid, p_telefone text, p_nome text, p_jid text) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_digits text := regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g');
  v_tel text;
  ct iara.whatsapp_contacts;
  v_user uuid;
  v_label text;
begin
  if length(v_digits) < 10 or length(v_digits) > 15 then
    raise exception 'Telefone inválido.' using errcode = '22023';
  end if;
  v_tel := '+' || v_digits;
  select * into ct from iara.whatsapp_contacts where channel_id = p_canal and telefone_e164 = v_tel for update;
  if found and ct.app_user_id is not null then
    update iara.whatsapp_contacts set ultima_em = now(), nome_wa = coalesce(nullif(trim(p_nome), ''), nome_wa), jid = coalesce(nullif(p_jid, ''), jid)
    where id = ct.id;
    update iara.app_users set last_seen_at = now() where id = ct.app_user_id;
    return jsonb_build_object('contact_id', ct.id, 'user_id', ct.app_user_id,
                              'guardian_id', (select guardian_id from iara.app_users where id = ct.app_user_id), 'conversation_id', ct.conversation_id);
  end if;

  v_label := coalesce(nullif(trim(p_nome), ''), 'Contato') || ' · WhatsApp ' || iara.mask_phone(iara.fmt_tel(v_tel));
  insert into iara.app_users (tenant_id, display_name, role_code, unit_id, guardian_id, auth_provider, is_demo, last_seen_at)
  values (1, left(v_label, 120), 'CIDADAO_NOVO', null, null, 'WHATSAPP', true, now())
  returning id into v_user;
  insert into iara.whatsapp_contacts (channel_id, telefone_e164, jid, nome_wa, app_user_id)
  values (p_canal, v_tel, nullif(p_jid, ''), nullif(trim(p_nome), ''), v_user)
  on conflict (channel_id, telefone_e164) do update set app_user_id = excluded.app_user_id, jid = coalesce(excluded.jid, iara.whatsapp_contacts.jid),
                                                        nome_wa = coalesce(excluded.nome_wa, iara.whatsapp_contacts.nome_wa), ultima_em = now()
  returning * into ct;
  return jsonb_build_object('contact_id', ct.id, 'user_id', v_user, 'guardian_id', null, 'conversation_id', null, 'novo', true);
end $$;

-- vincula a conversa ao contato; se é conversa nova, devolve a saudação já reposicionada depois da 1ª mensagem
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
         identity_verified = identity_verified or ct.guardian_id is not null
  where id = p_conversation;
  return jsonb_build_object('nova', v_nova);
end $$;

create or replace function iara.whatsapp_saudacao(p_conversation uuid) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ids uuid[];
begin
  -- a saudação foi gravada ao abrir a conversa; passa a vir depois da mensagem do cidadão
  select array_agg(id order by created_at) into v_ids from iara.messages where conversation_id = p_conversation and direction = 'OUT';
  update iara.messages set created_at = clock_timestamp() where id = any (coalesce(v_ids, '{}'));
  return coalesce((select jsonb_agg(jsonb_build_object('body', body, 'payload', payload) order by created_at)
                   from iara.messages where id = any (coalesce(v_ids, '{}'))), '[]'::jsonb);
end $$;

-- depois de cada turno: cadastro feito pela conversa → o número do WhatsApp vira o contato da família
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
    update iara.conversations set identity_verified = true, guardian_id = coalesce(guardian_id, v_g),
           contact_phone_masked = iara.mask_phone(iara.fmt_tel(ct.telefone_e164))
    where id = ct.conversation_id;
  end if;
  return jsonb_build_object('guardian_id', v_g);
end $$;

-- fila de saída: lote com reserva (o que ficar "enviando" por mais de 2 min volta para a fila)
create or replace function iara.whatsapp_saida_proximas(p_canal uuid, p_limite integer default 10) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v jsonb;
begin
  update iara.whatsapp_outbox set status = 'EXPIRADA', atualizado_em = now()
  where channel_id = p_canal and status in ('PENDENTE', 'ENVIANDO', 'ERRO') and created_at < now() - interval '24 hours';
  with lote as (
    select id from iara.whatsapp_outbox
    where channel_id = p_canal
      and (status = 'PENDENTE' or (status = 'ERRO' and tentativas < 5) or (status = 'ENVIANDO' and atualizado_em < now() - interval '2 minutes'))
    order by created_at
    limit least(greatest(coalesce(p_limite, 10), 1), 50)
    for update skip locked
  ), upd as (
    update iara.whatsapp_outbox o set status = 'ENVIANDO', tentativas = o.tentativas + 1, atualizado_em = now()
    from lote where o.id = lote.id
    returning o.id, o.telefone_e164, o.jid, o.texto, o.created_at
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'para', telefone_e164, 'jid', jid, 'texto', texto) order by created_at), '[]'::jsonb) into v from upd;
  return v;
end $$;

create or replace function iara.whatsapp_saida_confirmar(p_canal uuid, p_id uuid, p_wa_id text, p_erro text) returns void
language plpgsql security definer set search_path = iara, public
as $$
declare
  o iara.whatsapp_outbox;
begin
  update iara.whatsapp_outbox set status = case when p_erro is null then 'ENVIADA' else 'ERRO' end,
         wa_id = left(p_wa_id, 200), erro = left(p_erro, 400), atualizado_em = now(),
         enviada_em = case when p_erro is null then now() else enviada_em end
  where id = p_id and channel_id = p_canal
  returning * into o;
  if found and p_erro is null and o.origem = 'NOTIFICACAO' and o.ref_id is not null then
    update iara.notifications set status = 'ENVIADA' where id = o.ref_id;
  end if;
end $$;

-- 5. Gatilhos que alimentam a fila de saída (só com o canal ligado) ---------------------------
create or replace function iara.tg_whatsapp_saida_mensagem() returns trigger
language plpgsql security definer set search_path = iara, public
as $$
begin
  if new.direction <> 'OUT' or new.sender_type <> 'OPERADOR' then
    return null;
  end if;
  insert into iara.whatsapp_outbox (channel_id, contact_id, telefone_e164, jid, texto, origem, ref_id)
  select w.channel_id, w.id, w.telefone_e164, w.jid, new.body, 'SERVIDOR', new.id
  from iara.whatsapp_contacts w join iara.whatsapp_channels ch on ch.id = w.channel_id
  where w.conversation_id = new.conversation_id and ch.ativo
  limit 1;
  return null;
end $$;
drop trigger if exists whatsapp_saida_mensagem on iara.messages;
create trigger whatsapp_saida_mensagem after insert on iara.messages
  for each row execute function iara.tg_whatsapp_saida_mensagem();

create or replace function iara.tg_whatsapp_saida_notificacao() returns trigger
language plpgsql security definer set search_path = iara, public
as $$
begin
  if new.guardian_id is null or new.channel <> 'WHATSAPP' then
    return null;
  end if;
  insert into iara.whatsapp_outbox (channel_id, contact_id, telefone_e164, jid, texto, origem, ref_id)
  select w.channel_id, w.id, w.telefone_e164, w.jid, '*' || new.title || '*' || E'\n' || new.body, 'NOTIFICACAO', new.id
  from iara.whatsapp_contacts w join iara.whatsapp_channels ch on ch.id = w.channel_id
  where w.guardian_id = new.guardian_id and ch.ativo
  order by w.ultima_em desc
  limit 1;
  return null;
end $$;
drop trigger if exists whatsapp_saida_notificacao on iara.notifications;
create trigger whatsapp_saida_notificacao after insert on iara.notifications
  for each row execute function iara.tg_whatsapp_saida_notificacao();

-- 6. APIs do painel ---------------------------------------------------------------------------------
create or replace function api.whatsapp_canal(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if not (iara.has_perm('conversations.read') or iara.has_perm('channels.manage')) then
    raise exception 'Sem permissão para ver o canal do WhatsApp.' using errcode = '42501';
  end if;
  return (
    select jsonb_build_object('id', c.id, 'numero', c.numero_e164, 'numero_formatado', iara.fmt_tel(c.numero_e164), 'nome', c.nome,
      'provedor', c.provedor, 'ativo', c.ativo, 'estado', c.estado,
      'online', c.conectado and c.ultimo_sinal_em > now() - interval '3 minutes',
      'ultimo_sinal_em', c.ultimo_sinal_em, 'pareado_em', c.pareado_em, 'ligado_em', c.ligado_em, 'desligado_em', c.desligado_em,
      'alterado_por', c.alterado_por, 'compartilhado_com', c.compartilhado_com, 'observacoes', c.observacoes,
      'ponte_configurada', c.segredo_hash is not null, 'pode_gerenciar', iara.has_perm('channels.manage'),
      'contatos', (select count(*) from iara.whatsapp_contacts w where w.channel_id = c.id),
      'familias_vinculadas', (select count(*) from iara.whatsapp_contacts w where w.channel_id = c.id and w.guardian_id is not null),
      'mensagens_24h', (select count(*) from iara.whatsapp_inbound i where i.channel_id = c.id and i.received_at > now() - interval '24 hours'),
      'saida_pendente', (select count(*) from iara.whatsapp_outbox o where o.channel_id = c.id and o.status in ('PENDENTE', 'ENVIANDO', 'ERRO')),
      'enviadas_24h', (select count(*) from iara.whatsapp_outbox o where o.channel_id = c.id and o.status = 'ENVIADA' and o.enviada_em > now() - interval '24 hours'))
    from iara.whatsapp_channels c order by c.created_at limit 1);
end $$;

create or replace function api.whatsapp_canal_ligar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id uuid;
begin
  perform iara.require_perm('channels.manage');
  if not (p ? 'ativo') then
    raise exception 'Informe se o canal fica ligado ou desligado.' using errcode = '22023';
  end if;
  select id into v_id from iara.whatsapp_channels order by created_at limit 1;
  perform iara.whatsapp_canal_ligar(v_id, (p ->> 'ativo')::boolean, coalesce(iara.my_label(), 'painel'));
  return api.whatsapp_canal('{}'::jsonb);
end $$;

-- 7. Contato público: com o canal ligado, o QR code e o link abrem o WhatsApp de verdade -----------
create or replace function api.bootstrap(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object(
    'tenant', (select jsonb_build_object('id', id, 'name', name, 'state', state, 'ibge', ibge_code,
                                         'network_name', settings ->> 'network_name', 'secretariat', settings ->> 'secretariat',
                                         'school_year', (settings ->> 'school_year')::int, 'official_reference_date', settings ->> 'official_reference_date',
                                         'city_center', settings -> 'city_center', 'demo_mode', (settings ->> 'demo_mode')::boolean,
                                         'demo_unit', (settings ->> 'demo_unit_maria')::int)
               from iara.tenants where id = 1),
    'whatsapp', (select jsonb_build_object(
                   'numero', coalesce(nullif(regexp_replace(coalesce(t.settings ->> 'iara_whatsapp_numero', ''), '[^0-9]', '', 'g'), ''),
                                      (select regexp_replace(c.numero_e164, '[^0-9]', '', 'g') from iara.whatsapp_channels c
                                       where c.ativo order by c.ligado_em desc nulls last limit 1)),
                   'canal_ativo', exists (select 1 from iara.whatsapp_channels c where c.ativo),
                   'numero_demo', coalesce(t.settings ->> 'iara_whatsapp_numero_demo', '(44) 90000-0000'),
                   'mensagem', coalesce(nullif(t.settings ->> 'iara_whatsapp_mensagem', ''), 'Olá, IARA! Quero atendimento da Educação de Maringá.'),
                   'url_publica', t.settings ->> 'public_url')
                 from iara.tenants t where t.id = 1),
    'flags', (select jsonb_object_agg(code, enabled) from iara.feature_flags),
    'personas', (select jsonb_agg(jsonb_build_object('code', code, 'name', name, 'short_name', short_name, 'description', description,
                                                     'question', question, 'scope_type', scope_type, 'org_unit', org_unit, 'stage_filter', stage_filter)
                                  order by sort) from iara.organizational_roles where is_persona),
    'stages', (select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', name, 'short_name', short_name, 'color', color) order by sort) from iara.education_stages),
    'grades', (select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', name, 'short_name', short_name, 'stage_id', stage_id,
                                                   'min_age_months', min_age_months, 'max_age_months', max_age_months) order by sort) from iara.grade_levels),
    'territories', (select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', name, 'kind', kind, 'color', color,
                                                        'lat', extensions.st_y(center::extensions.geometry), 'lng', extensions.st_x(center::extensions.geometry)) order by sort)
                    from iara.territories where kind in ('MACRORREGIAO', 'DISTRITO')),
    'kpis', iara.kpis(),
    'rule_version', iara.rule_version(),
    'import', (select jsonb_build_object('id', id, 'file', source_file, 'imported_at', imported_at, 'counts', row_counts) from iara.import_batches limit 1)
  )
$$;

-- 8. Opções pendentes por contato: "1", "2"... valem a última lista que a IARA mandou para aquele telefone ---------
alter table iara.whatsapp_contacts add column if not exists opcoes jsonb;

create or replace function iara.whatsapp_opcoes(p_contact uuid, p_opcoes jsonb) returns void
language sql security definer set search_path = iara, public
as $$ update iara.whatsapp_contacts set opcoes = nullif(p_opcoes, '[]'::jsonb) where id = p_contact $$;

create or replace function iara.whatsapp_contato_opcoes(p_contact uuid) returns jsonb
language sql stable security definer set search_path = iara, public
as $$ select coalesce(opcoes, '[]'::jsonb) from iara.whatsapp_contacts where id = p_contact $$;

-- servidor respondendo: a lista anterior da IARA deixa de valer
create or replace function iara.tg_whatsapp_saida_mensagem() returns trigger
language plpgsql security definer set search_path = iara, public
as $$
begin
  if new.direction <> 'OUT' or new.sender_type <> 'OPERADOR' then
    return null;
  end if;
  update iara.whatsapp_contacts set opcoes = null where conversation_id = new.conversation_id and opcoes is not null;
  insert into iara.whatsapp_outbox (channel_id, contact_id, telefone_e164, jid, texto, origem, ref_id)
  select w.channel_id, w.id, w.telefone_e164, w.jid, new.body, 'SERVIDOR', new.id
  from iara.whatsapp_contacts w join iara.whatsapp_channels ch on ch.id = w.channel_id
  where w.conversation_id = new.conversation_id and ch.ativo
  limit 1;
  return null;
end $$;

-- 9. O que chega pelo WhatsApp acontece em tempo real: o deslocamento temporal da demonstração não mexe nele -------
-- (antes, conversas ao vivo iam para o futuro e a ordem das mensagens se embaralhava a cada deslocamento)
create or replace function iara.demo_timeshift(p_min_hours integer default 6) returns interval
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_base timestamptz := (iara.setting('demo_baseline_at'))::timestamptz;
  d interval;
  dd integer;
begin
  if v_base is null or not coalesce((iara.setting('demo_mode'))::boolean, false) then
    return interval '0';
  end if;
  d := date_trunc('minute', now() - v_base);
  if d < make_interval(hours => p_min_hours) then
    return interval '0';
  end if;
  dd := extract(day from d)::int;
  perform set_config('iara.skip_audit', 'on', true);
  create temp table if not exists tmp_ao_vivo_usuarios (id uuid primary key) on commit drop;
  truncate tmp_ao_vivo_usuarios;
  insert into tmp_ao_vivo_usuarios select id from iara.app_users where auth_provider = 'WHATSAPP';

  update iara.service_cases c set opened_at = opened_at + d, sla_due_at = sla_due_at + d, closed_at = closed_at + d
  where is_demo and not exists (select 1 from tmp_ao_vivo_usuarios u where u.id = c.created_by);
  update iara.case_events set occurred_at = occurred_at + d
  where case_id in (select c.id from iara.service_cases c where c.is_demo and not exists (select 1 from tmp_ao_vivo_usuarios u where u.id = c.created_by));
  update iara.waiting_list_entries w set entered_at = entered_at + d
  where is_demo and not exists (select 1 from tmp_ao_vivo_usuarios u where u.id = w.created_by);
  update iara.vacancy_offers o set offered_at = offered_at + d, expires_at = expires_at + d, accepted_at = accepted_at + d, declined_at = declined_at + d
  where is_demo and not exists (select 1 from tmp_ao_vivo_usuarios u where u.id = o.created_by);
  update iara.vacancy_blocks set created_at = created_at + d, released_at = released_at + d, valid_until = valid_until + dd where is_demo;
  update iara.vacancy_events set occurred_at = occurred_at + d;
  update iara.documents set received_at = received_at + d, validated_at = validated_at + d where is_demo and received_at > now() - interval '120 days';
  update iara.notifications n set created_at = created_at + d, read_at = read_at + d
  where not exists (select 1 from iara.whatsapp_contacts w where w.guardian_id = n.guardian_id);
  update iara.conversations set last_message_at = last_message_at + d, created_at = created_at + d where is_demo and channel <> 'WHATSAPP';
  update iara.messages m set created_at = created_at + d
  where not exists (select 1 from iara.conversations c where c.id = m.conversation_id and c.channel = 'WHATSAPP');
  update iara.handoff_tasks h set created_at = created_at + d
  where not exists (select 1 from iara.conversations c where c.id = h.conversation_id and c.channel = 'WHATSAPP');
  update iara.tool_executions t set created_at = created_at + d
  where not exists (select 1 from iara.conversations c where c.id = t.conversation_id and c.channel = 'WHATSAPP');
  update iara.tenants set settings = jsonb_set(settings, '{demo_baseline_at}', to_jsonb(v_base + d)) where id = 1;
  perform set_config('iara.skip_audit', 'off', true);
  perform iara.audit_event('DEMO_TIMESHIFT', 'demo', 'baseline', null,
                           'Registros fictícios deslocados no tempo em ' || d::text || ' para manter a demonstração atual.');
  return d;
end $$;

-- 10. Limpeza da demonstração também cobre quem chegou pelo WhatsApp -----------------------------------
create or replace function iara.demo_session_users() returns uuid[]
language sql stable security definer set search_path = iara, public
as $$ select coalesce(array_agg(id), '{}') from iara.app_users where auth_provider in ('DEMO', 'WHATSAPP') $$;

revoke all on function iara.whatsapp_canal_por_segredo(text), iara.whatsapp_canal_ligar(uuid, boolean, text), iara.whatsapp_canal_estado(uuid, text, boolean),
  iara.whatsapp_registrar_entrada(uuid, text), iara.whatsapp_contato(uuid, text, text, text), iara.whatsapp_vincular(uuid, uuid),
  iara.whatsapp_saudacao(uuid), iara.whatsapp_pos_turno(uuid), iara.whatsapp_saida_proximas(uuid, integer),
  iara.whatsapp_saida_confirmar(uuid, uuid, text, text), iara.whatsapp_opcoes(uuid, jsonb), iara.whatsapp_contato_opcoes(uuid) from public;

commit;
