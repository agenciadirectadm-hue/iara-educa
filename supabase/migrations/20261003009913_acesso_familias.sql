-- IARA Educa — 099.13 · Acesso das famílias pela conversa com a IARA (decisão de Rob, 11/11/2026)
-- A porta de entrada da versão 1 é a conversa com a IARA; o gov.br fica para uma versão seguinte, como caminho a mais.
-- Níveis de identidade da conversa (conversations.identity_level):
--   0 · ninguém identificado: só informação pública;
--   1 · o número está no cadastro oficial de um responsável (no WhatsApp, o próprio remetente; em outro canal, um código
--       de uso único enviado a esse número) ou a família se cadastrou por este número: rotina (frequência, avisos, boletim, fila);
--   2 · o número foi vinculado na escola pelo QR, com documento conferido pela secretaria: dados sensíveis (AEE,
--       ocorrências, transporte, documentos, dados cadastrais).
-- Código de uso único: aleatório, só o hash fica guardado, vale minutos, preso a um pedido, 5 erros bloqueiam.
-- Troca de número pela conversa: confirmada por código enviado ao número antigo, vale depois de 48 h, com aviso ao número
-- antigo e aos outros responsáveis; "NÃO FUI EU" no número antigo cancela. Na escola, o QR troca na hora.
-- Na demonstração (demo_mode ligado) nada muda no que já existia: a identidade continua simulada; o QR funciona para mostrar.
begin;

-- 1. Chave do telefone: DDD + 8 últimos dígitos (o WhatsApp às vezes omite o 9 dos celulares brasileiros) -----------------
create or replace function iara.tel_chave(p text) returns text
language sql immutable
as $$
  select case
           when length(d) in (12, 13) and d like '55%' then substr(d, 3, 2) || right(d, 8)
           when length(d) in (10, 11) then substr(d, 1, 2) || right(d, 8)
         end
  from (select regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') as d) z
$$;

-- telefone guardado no cadastro → formato E.164 (+55…), ou nulo se não for um número brasileiro completo
create or replace function iara.tel_e164(p text) returns text
language sql immutable
as $$
  select case
           when length(d) in (12, 13) and d like '55%' then '+' || d
           when length(d) in (10, 11) then '+55' || d
         end
  from (select regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') as d) z
$$;

create index if not exists guardians_tel_chave_wa_idx on iara.guardians (iara.tel_chave(whatsapp_phone));
create index if not exists guardians_tel_chave_pri_idx on iara.guardians (iara.tel_chave(primary_phone));

alter table iara.conversations add column if not exists identity_level smallint not null default 0;
alter table iara.conversations drop constraint if exists conversations_identity_level_check;
alter table iara.conversations add constraint conversations_identity_level_check check (identity_level between 0 and 2);

-- 2. Tabelas ---------------------------------------------------------------------------------------------------------------
-- vínculo do número feito na escola (nível 2): a secretaria conferiu o documento e o responsável apontou o WhatsApp para o QR
create table if not exists iara.familia_vinculos (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null default 1,
  guardian_id uuid not null references iara.guardians(id) on delete cascade,
  telefone_e164 text not null check (telefone_e164 ~ '^\+[1-9][0-9]{9,14}$'),
  nivel smallint not null default 2 check (nivel = 2),
  origem text not null default 'QR_ESCOLA' check (origem in ('QR_ESCOLA')),
  documento_tipo text not null,
  unit_id integer,
  registrado_por uuid,
  registrado_label text,
  criado_em timestamptz not null default now(),
  valido_ate date not null,
  revogado_em timestamptz,
  motivo text,
  is_demo boolean not null default false
);
create index if not exists familia_vinculos_guardian_idx on iara.familia_vinculos (guardian_id) where revogado_em is null;
create index if not exists familia_vinculos_tel_idx on iara.familia_vinculos (iara.tel_chave(telefone_e164)) where revogado_em is null;

-- QR de uso único gerado pela secretaria (vale 10 minutos; só o hash do código fica guardado)
create table if not exists iara.familia_qr (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid not null references iara.guardians(id) on delete cascade,
  token_hash text not null unique,
  documento_tipo text not null,
  unit_id integer,
  criado_por uuid,
  registrado_label text,
  criado_em timestamptz not null default now(),
  expira_em timestamptz not null,
  usado_em timestamptz,
  usado_telefone text,
  resultado text,
  is_demo boolean not null default false
);

-- códigos de uso único (só o hash; o texto enviado tem o código apagado depois de usado, vencido ou bloqueado)
create table if not exists iara.familia_codigos (
  id uuid primary key default gen_random_uuid(),
  tenant_id smallint not null default 1,
  conversation_id uuid references iara.conversations(id) on delete set null,
  guardian_id uuid references iara.guardians(id) on delete cascade,
  telefone_e164 text not null,
  finalidade text not null check (finalidade in ('ENTRAR', 'ACAO', 'TROCAR_NUMERO')),
  acao text,
  codigo_hash text not null,
  criado_em timestamptz not null default now(),
  expira_em timestamptz not null,
  tentativas smallint not null default 0,
  usado_em timestamptz,
  bloqueado_em timestamptz,
  outbox_id uuid,
  is_demo boolean not null default false
);
create index if not exists familia_codigos_tel_idx on iara.familia_codigos (telefone_e164, criado_em desc);

-- troca de número pela conversa: confirmada pelo número antigo, vale depois de 48 h
create table if not exists iara.familia_trocas_numero (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid not null references iara.guardians(id) on delete cascade,
  telefone_antigo text not null,
  telefone_novo text not null,
  codigo_id uuid references iara.familia_codigos(id) on delete set null,
  pedido_em timestamptz not null default now(),
  confirmado_em timestamptz,
  libera_em timestamptz,
  aplicado_em timestamptz,
  cancelado_em timestamptz,
  motivo text,
  is_demo boolean not null default false
);
create index if not exists familia_trocas_novo_idx on iara.familia_trocas_numero (iara.tel_chave(telefone_novo)) where aplicado_em is null and cancelado_em is null;
create index if not exists familia_trocas_antigo_idx on iara.familia_trocas_numero (iara.tel_chave(telefone_antigo)) where aplicado_em is null and cancelado_em is null;

alter table iara.familia_vinculos enable row level security;
alter table iara.familia_qr enable row level security;
alter table iara.familia_codigos enable row level security;
alter table iara.familia_trocas_numero enable row level security;

-- 3. Classificação LGPD das colunas novas --------------------------------------------------------------------------------
insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('familia_vinculos', 'telefone_e164', 'PESSOAL', 'contato do responsável', 'identificar o responsável na conversa com a IARA', 'só funções do gateway; mascarado nas telas'),
  ('familia_vinculos', 'registrado_label', 'INTERNO', 'servidor que conferiu o documento', 'trilha do vínculo feito na escola', 'secretaria da unidade e SEDUC'),
  ('familia_vinculos', 'motivo', 'INTERNO', 'motivo da revogação', 'trilha do vínculo', 'secretaria da unidade e SEDUC'),
  ('familia_qr', 'usado_telefone', 'PESSOAL', 'contato do responsável', 'trilha do QR de vínculo', 'só funções do gateway'),
  ('familia_qr', 'registrado_label', 'INTERNO', 'servidor que gerou o QR', 'trilha do QR de vínculo', 'secretaria da unidade e SEDUC'),
  ('familia_codigos', 'telefone_e164', 'PESSOAL', 'contato do responsável', 'destino do código de uso único', 'só funções do gateway; o código fica só em hash'),
  ('familia_codigos', 'acao', 'INTERNO', 'pedido a que o código está preso', 'impedir uso do código em outro pedido', 'só funções do gateway'),
  ('familia_trocas_numero', 'telefone_antigo', 'PESSOAL', 'contato do responsável', 'confirmar a troca pelo número antigo', 'só funções do gateway; mascarado nas telas'),
  ('familia_trocas_numero', 'telefone_novo', 'PESSOAL', 'contato do responsável', 'troca de número pedida pela conversa', 'só funções do gateway; mascarado nas telas'),
  ('familia_trocas_numero', 'motivo', 'INTERNO', 'motivo do cancelamento', 'trilha da troca de número', 'secretaria da unidade e SEDUC')
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

-- a checagem de colunas sem classificação passa a olhar também as tabelas novas
create or replace function iara.classificacao_pendente() returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select coalesce(jsonb_agg(c.table_name || '.' || c.column_name order by c.table_name, c.column_name), '[]'::jsonb)
  from information_schema.columns c
  where c.table_schema = 'iara'
    and c.table_name in ('students', 'student_sensitive', 'guardians', 'household_members', 'student_guardians', 'addresses',
                         'messages', 'conversations', 'whatsapp_contacts', 'service_cases', 'documents', 'waiting_list_entries', 'staff',
                         'staff_formacoes', 'staff_lotacoes', 'mediacoes', 'frequencia_faltas', 'frequencia_justificativas',
                         'frequencia_alertas', 'aluno_restricoes', 'manutencao_chamados', 'mural_leituras', 'mural_enquete_respostas',
                         'ocorrencias', 'ocorrencia_eventos', 'agenda_escolar', 'agenda_ciencia',
                         'notas', 'pareceres', 'alfabetizacao_sondagens', 'planos_intervencao', 'aee_planos', 'aee_atendimentos', 'declaracoes',
                         'transporte_motoristas', 'transporte_rotas', 'transporte_pontos', 'transporte_alunos', 'transporte_viagens', 'transporte_embarques',
                         'transporte_ocorrencias', 'transporte_avisos', 'transporte_abonos', 'pedidos', 'pedido_itens', 'fornecedores',
                         'uk_tamanhos', 'uk_necessidades', 'uk_avisos', 'uk_codigos', 'uk_disparos', 'apoio_casos', 'apoio_registros', 'apoio_profissionais',
                         'familia_vinculos', 'familia_qr', 'familia_codigos', 'familia_trocas_numero')
    and (c.column_name ~ '(name|cpf|nis|rg|phone|email|street|number|complement|postal|location|income|birth|race|sus|notes|body|payload|summary|description|details|allerg|medical|legal|need|telefone|nome|jid|flags|breakdown|relationship|marital|occupation|benefit|consent|context|label)'
         or c.column_name ~ '(^|_)(motivo|justificativa|atestado|detalhe|observacao|acao|descricao|formacao|escolaridade|matricula_funcional|data_admissao|opcao|restricao_codigo|providencias|providencia|texto|conteudo|objetivo|objetivos|resultado|atividade|avaliacao_inicial|orientacoes_sala|divergencia|lat|lng|tecnico|orientacao_escola|orientacao_familia|analise_unidade|conclusao|documento)$')
    and c.column_name not in ('contact_label', 'assigned_label', 'sender_label', 'subject', 'file_name_ext', 'registrado_label', 'produto_codigo', 'area_codigo')
    and not exists (select 1 from iara.classificacao_dados d where d.tabela = c.table_name and d.coluna = c.column_name)
$$;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('familia_qr', 'resultado', 'INTERNO', 'resultado do uso do QR', 'trilha do QR de vínculo', 'secretaria da unidade e SEDUC')
on conflict (tabela, coluna) do nothing;

-- 4. Utilitários ----------------------------------------------------------------------------------------------------------
create or replace function iara.familia_hash(p text) returns text
language sql immutable
as $$ select encode(extensions.digest(p, 'sha256'), 'hex') $$;

-- 6 algarismos aleatórios (gerador criptográfico)
create or replace function iara.familia_codigo_novo() returns text
language sql volatile
as $$
  select lpad((((get_byte(b, 0)::bigint << 24) + (get_byte(b, 1)::bigint << 16) + (get_byte(b, 2)::bigint << 8) + get_byte(b, 3)::bigint) % 1000000)::text, 6, '0')
  from (select extensions.gen_random_bytes(4) as b) z
$$;

-- 8 caracteres sem letras ou algarismos que se confundem (32^8 ≈ 1 trilhão de combinações)
create or replace function iara.familia_token_novo() returns text
language sql volatile
as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (get_byte(z.b, i) % 32) + 1, 1), '' order by i)
  from (select extensions.gen_random_bytes(8) as b) z, generate_series(0, 7) i
$$;

-- texto para a fila de saída do WhatsApp (sem contato prévio, vai pelo número)
create or replace function iara.familia_enviar(p_tel text, p_texto text, p_ref uuid default null) returns uuid
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_canal uuid;
  v_out uuid;
begin
  if p_tel is null or p_tel !~ '^\+[1-9][0-9]{9,14}$' then return null; end if;
  select id into v_canal from iara.whatsapp_channels order by ativo desc, created_at limit 1;
  if v_canal is null then return null; end if;
  insert into iara.whatsapp_outbox (channel_id, contact_id, telefone_e164, jid, texto, origem, ref_id)
  select v_canal, ct.id, p_tel, ct.jid, p_texto, 'NOTIFICACAO', p_ref
  from (select 1) x left join iara.whatsapp_contacts ct on ct.channel_id = v_canal and ct.telefone_e164 = p_tel
  returning id into v_out;
  return v_out;
end $$;

-- apaga o código do texto já enviado (o código só existe em claro enquanto pode ser usado)
create or replace function iara.familia_apagar_codigo(p_codigo uuid) returns void
language sql security definer set search_path = iara, public
as $$
  update iara.whatsapp_outbox o set texto = regexp_replace(o.texto, '[0-9]{6}', '••••••', 'g')
  where o.id = (select outbox_id from iara.familia_codigos where id = p_codigo)
$$;

-- 5. Código de uso único ----------------------------------------------------------------------------------------------------
-- p_texto traz {codigo} onde o código entra
create or replace function iara.familia_codigo_emitir(p_guardian uuid, p_tel text, p_finalidade text, p_acao text,
                                                      p_conversation uuid, p_minutos integer, p_texto text) returns uuid
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id uuid := gen_random_uuid();
  v_codigo text := iara.familia_codigo_novo();
  v_out uuid;
  r record;
begin
  -- um pedido por vez: o código anterior do mesmo destino e finalidade deixa de valer
  for r in update iara.familia_codigos set bloqueado_em = now()
           where telefone_e164 = p_tel and finalidade = p_finalidade and usado_em is null and bloqueado_em is null
           returning id loop
    perform iara.familia_apagar_codigo(r.id);
  end loop;
  -- códigos vencidos há mais de 1 hora: some o texto em claro
  for r in select id from iara.familia_codigos
           where expira_em < now() - interval '1 hour' and expira_em > now() - interval '2 days' and usado_em is null and bloqueado_em is null loop
    update iara.familia_codigos set bloqueado_em = now() where id = r.id;
    perform iara.familia_apagar_codigo(r.id);
  end loop;
  v_out := iara.familia_enviar(p_tel, replace(p_texto, '{codigo}', v_codigo), v_id);
  insert into iara.familia_codigos (id, conversation_id, guardian_id, telefone_e164, finalidade, acao, codigo_hash, expira_em, outbox_id, is_demo)
  values (v_id, p_conversation, p_guardian, p_tel, p_finalidade, p_acao, iara.familia_hash(v_id::text || ':' || v_codigo),
          now() + make_interval(mins => greatest(coalesce(p_minutos, 10), 1)), v_out, iara.demo_mode());
  return v_id;
end $$;

create or replace function iara.familia_codigo_conferir(p_id uuid, p_codigo text) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.familia_codigos;
  v_n smallint;
begin
  select * into c from iara.familia_codigos where id = p_id for update;
  if c.id is null or c.usado_em is not null or c.bloqueado_em is not null then
    return jsonb_build_object('ok', false, 'motivo', 'INVALIDO');
  end if;
  if c.expira_em < now() then
    update iara.familia_codigos set bloqueado_em = now() where id = c.id;
    perform iara.familia_apagar_codigo(c.id);
    return jsonb_build_object('ok', false, 'motivo', 'EXPIRADO');
  end if;
  if c.codigo_hash = iara.familia_hash(c.id::text || ':' || regexp_replace(coalesce(p_codigo, ''), '[^0-9]', '', 'g')) then
    update iara.familia_codigos set usado_em = now() where id = c.id;
    perform iara.familia_apagar_codigo(c.id);
    return jsonb_build_object('ok', true);
  end if;
  update iara.familia_codigos set tentativas = tentativas + 1 where id = c.id returning tentativas into v_n;
  if v_n >= 5 then
    update iara.familia_codigos set bloqueado_em = now() where id = c.id;
    perform iara.familia_apagar_codigo(c.id);
    perform iara.audit_event('FAMILIA_CODIGO_BLOQUEADO', 'familia_codigo', c.id::text, null,
      format('Código de uso único (%s) bloqueado depois de 5 tentativas erradas.', lower(c.finalidade)));
    return jsonb_build_object('ok', false, 'motivo', 'BLOQUEADO');
  end if;
  return jsonb_build_object('ok', false, 'motivo', 'ERRADO', 'restantes', 5 - v_n);
end $$;

-- 6. Quem é o responsável deste número, e em que nível ---------------------------------------------------------------------
create or replace function iara.familia_identificar(p_tel text) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_k text := iara.tel_chave(p_tel);
  v_vinc iara.familia_vinculos;
  v_n integer;
  v_g uuid;
begin
  if v_k is null then
    return jsonb_build_object('nivel', 0);
  end if;
  select count(*), (array_agg(g.id order by coalesce(iara.tel_chave(g.whatsapp_phone) = v_k, false) desc, g.created_at))[1]
    into v_n, v_g
  from iara.guardians g
  where iara.tel_chave(g.whatsapp_phone) = v_k or iara.tel_chave(g.primary_phone) = v_k;
  select * into v_vinc from iara.familia_vinculos v
  where iara.tel_chave(v.telefone_e164) = v_k and v.revogado_em is null and v.valido_ate >= iara.hoje_local()
  order by v.criado_em desc limit 1;
  if v_vinc.id is not null then
    -- celular dividido com outro responsável não chega ao nível 2
    if exists (select 1 from iara.guardians g where g.id <> v_vinc.guardian_id
               and (iara.tel_chave(g.whatsapp_phone) = v_k or iara.tel_chave(g.primary_phone) = v_k)) then
      return jsonb_build_object('nivel', 1, 'guardian_id', v_vinc.guardian_id, 'compartilhado', true);
    end if;
    return jsonb_build_object('nivel', 2, 'guardian_id', v_vinc.guardian_id, 'valido_ate', v_vinc.valido_ate);
  end if;
  if v_n > 0 then
    return jsonb_build_object('nivel', 1, 'guardian_id', v_g, 'compartilhado', v_n > 1);
  end if;
  return jsonb_build_object('nivel', 0);
end $$;

-- 7. Troca de número pela conversa: aplica as que já passaram das 48 h ----------------------------------------------------
create or replace function iara.familia_trocas_aplicar(p_tel text default null) returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  t record;
  g iara.guardians;
  v_n integer := 0;
begin
  for t in select * from iara.familia_trocas_numero
           where confirmado_em is not null and aplicado_em is null and cancelado_em is null and libera_em <= now()
             and (p_tel is null or iara.tel_chave(telefone_novo) = iara.tel_chave(p_tel))
           for update skip locked loop
    select * into g from iara.guardians where id = t.guardian_id;
    update iara.guardians set whatsapp_phone = iara.fmt_tel(t.telefone_novo), preferred_contact_channel = 'WHATSAPP',
           primary_phone = case when iara.tel_chave(primary_phone) = iara.tel_chave(t.telefone_antigo) then iara.fmt_tel(t.telefone_novo) else primary_phone end
    where id = t.guardian_id;
    update iara.familia_vinculos set revogado_em = now(), motivo = 'Número trocado pela conversa (confirmado pelo número antigo)'
    where guardian_id = t.guardian_id and revogado_em is null;
    update iara.familia_trocas_numero set aplicado_em = now() where id = t.id;
    perform iara.audit_event('FAMILIA_TROCA_APLICADA', 'guardian', t.guardian_id::text, null,
      format('WhatsApp de %s trocado no cadastro, 48 h depois da confirmação pelo número antigo.', g.full_name));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- 8. Identidade da conversa do WhatsApp (produção): recalculada a cada mensagem ----------------------------------------------
create or replace function iara.familia_aplicar_identidade(p_contact uuid) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  ct iara.whatsapp_contacts;
  u iara.app_users;
  r jsonb;
  v_nivel integer;
  v_g uuid;
  v_proprio boolean;
begin
  select * into ct from iara.whatsapp_contacts where id = p_contact;
  if ct.id is null or iara.demo_mode() then
    return jsonb_build_object('demo', iara.demo_mode());
  end if;
  perform iara.familia_trocas_aplicar(ct.telefone_e164);
  select * into u from iara.app_users where id = ct.app_user_id;
  -- família que se cadastrou por este número: o cadastro é dela (nível 1, ou 2 se depois vinculou na escola)
  v_proprio := u.guardian_id is not null and exists (select 1 from iara.guardians g where g.id = u.guardian_id and g.created_by = u.id);
  r := iara.familia_identificar(ct.telefone_e164);
  v_nivel := coalesce((r ->> 'nivel')::int, 0);
  v_g := (r ->> 'guardian_id')::uuid;
  if v_proprio and (v_g is null or v_g <> u.guardian_id) then
    v_g := u.guardian_id;
    v_nivel := 1;
  end if;
  update iara.app_users set guardian_id = v_g where id = u.id and guardian_id is distinct from v_g;
  update iara.whatsapp_contacts set guardian_id = v_g where id = ct.id and guardian_id is distinct from v_g;
  if ct.conversation_id is not null then
    update iara.conversations set identity_level = v_nivel, identity_verified = v_nivel > 0, guardian_id = v_g
    where id = ct.conversation_id
      and (identity_level is distinct from v_nivel or identity_verified is distinct from (v_nivel > 0) or guardian_id is distinct from v_g);
  end if;
  return jsonb_build_object('nivel', v_nivel, 'guardian_id', v_g);
end $$;

-- o WhatsApp passa a calcular a identidade em produção (o resto igual à migração 034)
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
         -- produção: o número do cadastro oficial identifica (nível 1); só a demonstração presume pelo contato
         identity_verified = identity_verified or (iara.demo_mode() and ct.guardian_id is not null)
  where id = p_conversation;
  if not iara.demo_mode() then
    perform iara.familia_aplicar_identidade(p_contact);
  end if;
  return jsonb_build_object('nova', v_nova);
end $$;

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
    if ct.telefone_e164 ~ '^\+55[0-9]{10,11}$' then
      update iara.guardians set whatsapp_phone = iara.fmt_tel(ct.telefone_e164), primary_phone = iara.fmt_tel(ct.telefone_e164),
             preferred_contact_channel = 'WHATSAPP'
      where id = v_g and created_by = ct.app_user_id;
    end if;
    update iara.conversations set identity_verified = identity_verified or iara.demo_mode(), guardian_id = coalesce(guardian_id, v_g),
           contact_phone_masked = iara.mask_phone(iara.fmt_tel(ct.telefone_e164))
    where id = ct.conversation_id;
  end if;
  if not iara.demo_mode() then
    perform iara.familia_aplicar_identidade(p_contact);
  end if;
  return jsonb_build_object('guardian_id', v_g);
end $$;

-- o retrato da conversa que o gateway recebe passa a trazer o nível
create or replace function api.iara_send(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.conversations;
  v_body text := trim(coalesce(p ->> 'body', ''));
  v_msg uuid;
begin
  select * into c from iara.conversations where id = (p ->> 'conversation_id')::uuid for update;
  if not found or c.owner_user_id is distinct from iara.current_user_id() then
    raise exception 'Conversa não encontrada.' using errcode = 'P0002';
  end if;
  if v_body = '' then
    raise exception 'Mensagem vazia.' using errcode = '22023';
  end if;
  insert into iara.messages (conversation_id, direction, sender_type, sender_label, body, payload)
  values (c.id, 'IN', 'CIDADAO', c.contact_label, left(v_body, 2000), coalesce(p -> 'payload', '{}'::jsonb))
  returning id into v_msg;
  update iara.conversations set last_message_at = now(), state = case when state = 'CLOSED' then 'BOT_ACTIVE' else state end where id = c.id;
  return jsonb_build_object('message_id', v_msg, 'conversation_id', c.id, 'state', case when c.state = 'CLOSED' then 'BOT_ACTIVE' else c.state end,
                            'context', c.context, 'identity_verified', c.identity_verified, 'identity_level', c.identity_level,
                            'guardian_id', c.guardian_id, 'active_student_id', c.active_student_id, 'active_case_id', c.active_case_id);
end $$;

-- 9. QR da secretaria ---------------------------------------------------------------------------------------------------------
create or replace function iara.familia_vinculo_json(v iara.familia_vinculos) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', v.id, 'numero', iara.mask_phone(iara.fmt_tel(v.telefone_e164)), 'nivel', v.nivel, 'documento', v.documento_tipo,
    'unidade', (select u.short_name from iara.education_units u where u.id = v.unit_id), 'por', v.registrado_label,
    'desde', v.criado_em, 'valido_ate', v.valido_ate, 'revogado_em', v.revogado_em, 'motivo', v.motivo,
    'vigente', v.revogado_em is null and v.valido_ate >= iara.hoje_local())
$$;

create or replace function api.familia_vinculo_situacao(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_g uuid := nullif(p ->> 'guardian_id', '')::uuid;
  g iara.guardians;
  v_num text;
begin
  perform iara.require_perm('guardians.read');
  if v_g is null or not iara.can_access_guardian(v_g) then
    raise exception 'Responsável não encontrado.' using errcode = 'P0002';
  end if;
  select * into g from iara.guardians where id = v_g;
  select numero_e164 into v_num from iara.whatsapp_channels order by ativo desc, created_at limit 1;
  return jsonb_build_object(
    'numero_cadastro', iara.mask_phone(coalesce(g.whatsapp_phone, g.primary_phone)),
    'vinculo', (select iara.familia_vinculo_json(v) from iara.familia_vinculos v
                where v.guardian_id = v_g and v.revogado_em is null and v.valido_ate >= iara.hoje_local() order by v.criado_em desc limit 1),
    'historico', coalesce((select jsonb_agg(iara.familia_vinculo_json(v) order by v.criado_em desc)
                           from (select * from iara.familia_vinculos where guardian_id = v_g order by criado_em desc limit 5) v), '[]'::jsonb),
    'troca_pendente', (select jsonb_build_object('novo', iara.mask_phone(iara.fmt_tel(t.telefone_novo)), 'pedido_em', t.pedido_em,
                                                 'confirmado_em', t.confirmado_em, 'libera_em', t.libera_em)
                       from iara.familia_trocas_numero t where t.guardian_id = v_g and t.aplicado_em is null and t.cancelado_em is null
                       order by t.pedido_em desc limit 1),
    'canal', iara.fmt_tel(v_num),
    'pode_vincular', iara.has_perm('guardians.write'),
    'demo', iara.demo_mode());
end $$;

create or replace function api.familia_vinculo_qr(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_g uuid := nullif(p ->> 'guardian_id', '')::uuid;
  v_doc text := upper(btrim(coalesce(p ->> 'documento_tipo', '')));
  v_token text := iara.familia_token_novo();
  v_num text;
  v_ate timestamptz := now() + interval '10 minutes';
  g iara.guardians;
begin
  perform iara.require_perm('guardians.write');
  if v_g is null or not iara.can_access_guardian(v_g) then
    raise exception 'Responsável não encontrado.' using errcode = 'P0002';
  end if;
  if coalesce((p ->> 'documento_conferido')::boolean, false) is not true then
    raise exception 'Confira um documento com foto do responsável antes de gerar o QR.' using errcode = '22023';
  end if;
  if v_doc not in ('RG', 'CIN', 'CNH', 'CTPS', 'PASSAPORTE', 'CRNM', 'OUTRO') then
    raise exception 'Informe qual documento com foto foi conferido.' using errcode = '22023';
  end if;
  select numero_e164 into v_num from iara.whatsapp_channels order by ativo desc, created_at limit 1;
  if v_num is null then
    raise exception 'O WhatsApp da IARA ainda não está configurado.' using errcode = '55006';
  end if;
  if iara.taxa(array['qr:' || iara.current_user_id()::text], array[30], array[3600]) is not null then
    raise exception 'Muitos QR gerados em pouco tempo. Aguarde alguns minutos.' using errcode = '55006';
  end if;
  select * into g from iara.guardians where id = v_g;
  insert into iara.familia_qr (guardian_id, token_hash, documento_tipo, unit_id, criado_por, registrado_label, expira_em, is_demo)
  values (v_g, iara.familia_hash('qr:' || v_token), v_doc, iara.my_unit(), iara.current_user_id(), iara.my_label(), v_ate, iara.demo_mode());
  perform iara.audit_event('FAMILIA_QR_GERADO', 'guardian', v_g::text, iara.my_unit(),
    format('QR de vínculo do WhatsApp gerado para %s (documento conferido: %s).', g.full_name, v_doc));
  return jsonb_build_object('token', v_token, 'texto', 'VINCULAR ' || v_token,
    'link', 'https://wa.me/' || regexp_replace(v_num, '[^0-9]', '', 'g') || '?text=VINCULAR%20' || v_token,
    'numero', iara.fmt_tel(v_num), 'expira_em', v_ate, 'responsavel', g.full_name);
end $$;

create or replace function api.familia_vinculo_revogar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_g uuid := nullif(p ->> 'guardian_id', '')::uuid;
  v_motivo text := nullif(btrim(coalesce(p ->> 'motivo', '')), '');
  v_n integer;
begin
  perform iara.require_perm('guardians.write');
  if v_g is null or not iara.can_access_guardian(v_g) then
    raise exception 'Responsável não encontrado.' using errcode = 'P0002';
  end if;
  if v_motivo is null then
    raise exception 'Informe o motivo.' using errcode = '22023';
  end if;
  update iara.familia_vinculos set revogado_em = now(), motivo = left(v_motivo, 300)
  where guardian_id = v_g and revogado_em is null;
  get diagnostics v_n = row_count;
  -- conversas abertas desse responsável voltam a ser calculadas na próxima mensagem
  update iara.conversations set identity_level = least(identity_level, 1) where guardian_id = v_g and identity_level = 2;
  perform iara.audit_event('FAMILIA_VINCULO_REVOGADO', 'guardian', v_g::text, iara.my_unit(), format('Vínculo do WhatsApp revogado: %s', left(v_motivo, 200)));
  return api.familia_vinculo_situacao(jsonb_build_object('guardian_id', v_g)) || jsonb_build_object('revogados', v_n);
end $$;

-- o responsável aponta o WhatsApp para o QR: a mensagem "VINCULAR <código>" chega aqui
create or replace function iara.familia_vinculo_qr_usar(p_contact uuid, p_token text) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  ct iara.whatsapp_contacts;
  q iara.familia_qr;
  g iara.guardians;
  v_ate date := make_date(extract(year from iara.hoje_local())::int + 1, 3, 31);
  v_antigo text;
begin
  select * into ct from iara.whatsapp_contacts where id = p_contact;
  if ct.id is null or ct.telefone_e164 !~ '^\+55[0-9]{10,11}$' then
    return jsonb_build_object('ok', false, 'mensagem', 'Não consegui ler o número deste WhatsApp. Peça ajuda à secretaria da escola.');
  end if;
  if iara.taxa(array['vincular:' || ct.telefone_e164], array[10], array[3600]) is not null then
    return jsonb_build_object('ok', false, 'mensagem', 'Muitas tentativas seguidas. Tente de novo daqui a pouco, com um QR novo.');
  end if;
  select * into q from iara.familia_qr where token_hash = iara.familia_hash('qr:' || upper(btrim(coalesce(p_token, '')))) for update;
  if q.id is null or q.usado_em is not null then
    return jsonb_build_object('ok', false, 'mensagem', 'Este QR não vale mais. Peça à secretaria da escola para gerar outro.');
  end if;
  if q.expira_em < now() then
    update iara.familia_qr set usado_em = now(), usado_telefone = ct.telefone_e164, resultado = 'VENCIDO' where id = q.id;
    return jsonb_build_object('ok', false, 'mensagem', 'Este QR venceu (vale 10 minutos). Peça à secretaria da escola para gerar outro.');
  end if;
  select * into g from iara.guardians where id = q.guardian_id;
  -- cada responsável vincula o próprio número
  if exists (select 1 from iara.guardians o where o.id <> g.id
             and (iara.tel_chave(o.whatsapp_phone) = iara.tel_chave(ct.telefone_e164) or iara.tel_chave(o.primary_phone) = iara.tel_chave(ct.telefone_e164)))
     or exists (select 1 from iara.familia_vinculos v where v.guardian_id <> g.id and v.revogado_em is null
                and iara.tel_chave(v.telefone_e164) = iara.tel_chave(ct.telefone_e164)) then
    update iara.familia_qr set usado_em = now(), usado_telefone = ct.telefone_e164, resultado = 'NUMERO_DE_OUTRO' where id = q.id;
    return jsonb_build_object('ok', false, 'mensagem',
      'Este número já está no cadastro de outro responsável. Cada responsável precisa vincular o próprio WhatsApp. Fale com a secretaria da escola.');
  end if;
  update iara.familia_qr set usado_em = now(), usado_telefone = ct.telefone_e164, resultado = 'VINCULADO' where id = q.id;
  update iara.familia_vinculos set revogado_em = now(), motivo = 'Substituído por novo vínculo na escola'
  where guardian_id = g.id and revogado_em is null;
  insert into iara.familia_vinculos (guardian_id, telefone_e164, documento_tipo, unit_id, registrado_por, registrado_label, valido_ate, is_demo)
  values (g.id, ct.telefone_e164, q.documento_tipo, q.unit_id, q.criado_por, q.registrado_label, v_ate, iara.demo_mode());
  update iara.familia_trocas_numero set cancelado_em = now(), motivo = 'Número vinculado na escola'
  where guardian_id = g.id and aplicado_em is null and cancelado_em is null;
  -- o número conferido na escola passa a ser o WhatsApp do cadastro (na demonstração os telefones do cadastro ficam fictícios)
  if not iara.demo_mode() and iara.tel_chave(g.whatsapp_phone) is distinct from iara.tel_chave(ct.telefone_e164) then
    v_antigo := iara.tel_e164(coalesce(g.whatsapp_phone, g.primary_phone));
    update iara.guardians set whatsapp_phone = iara.fmt_tel(ct.telefone_e164), preferred_contact_channel = 'WHATSAPP' where id = g.id;
    if v_antigo is not null and iara.tel_chave(v_antigo) <> iara.tel_chave(ct.telefone_e164) then
      perform iara.familia_enviar(v_antigo, format(
        '*IARA Educa · Secretaria de Educação de Maringá*%sO WhatsApp do seu cadastro escolar foi trocado na secretaria da escola em %s. Se você não reconhece, procure a escola.',
        E'\n', to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM "às" HH24:MI')));
    end if;
  end if;
  update iara.whatsapp_contacts set guardian_id = g.id where id = ct.id;
  update iara.app_users set guardian_id = g.id where id = ct.app_user_id;
  if ct.conversation_id is not null then
    update iara.conversations set guardian_id = g.id, identity_verified = true, identity_level = 2 where id = ct.conversation_id;
  end if;
  perform iara.audit_event('FAMILIA_VINCULO_QR', 'guardian', g.id::text, q.unit_id,
    format('WhatsApp de %s vinculado na escola (documento conferido: %s; por %s), válido até %s.',
           g.full_name, q.documento_tipo, coalesce(q.registrado_label, 'secretaria'), to_char(v_ate, 'DD/MM/YYYY')));
  return jsonb_build_object('ok', true, 'nome', split_part(g.full_name, ' ', 1), 'valido_ate', v_ate);
end $$;

-- 10. Troca de número pela conversa ------------------------------------------------------------------------------------------
create or replace function iara.familia_meu_contato() returns iara.whatsapp_contacts
language sql stable security definer set search_path = iara, public
as $$ select * from iara.whatsapp_contacts where app_user_id = iara.current_user_id() order by ultima_em desc limit 1 $$;

create or replace function api.familia_troca_pedir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  ct iara.whatsapp_contacts := iara.familia_meu_contato();
  v_cpf text := regexp_replace(coalesce(p ->> 'cpf', ''), '[^0-9]', '', 'g');
  g iara.guardians;
  v_antigo text;
  v_troca uuid;
  v_cod uuid;
  v_generico text := 'Se este CPF estiver no cadastro de uma criança da rede com outro número, acabei de mandar um código para o número antigo. Digite aqui o código que chegou lá (vale 30 minutos). Se você não tem mais o número antigo, a secretaria da escola faz a troca na hora, com um documento com foto.';
begin
  if iara.demo_mode() then
    return jsonb_build_object('ok', false, 'demo', true, 'mensagem',
      'Na demonstração, a troca de número é mostrada pela secretaria da escola, com o QR de vínculo.');
  end if;
  if ct.id is null or ct.telefone_e164 !~ '^\+55[0-9]{10,11}$' then
    raise exception 'A troca de número é pedida pelo WhatsApp do número novo.' using errcode = '22023';
  end if;
  if length(v_cpf) <> 11 then
    raise exception 'Informe os 11 números do CPF do responsável.' using errcode = '22023';
  end if;
  if iara.taxa(array['troca:' || ct.telefone_e164, 'trocacpf:' || md5(v_cpf)], array[3, 3], array[86400, 86400]) is not null then
    return jsonb_build_object('ok', false, 'mensagem', 'Já houve pedidos demais de troca hoje. Tente amanhã ou procure a secretaria da escola.');
  end if;
  select * into g from iara.guardians where iara.digitos(cpf) = v_cpf order by updated_at desc limit 1;
  v_antigo := iara.tel_e164(coalesce(g.whatsapp_phone, g.primary_phone));
  if g.id is not null and v_antigo is not null and iara.tel_chave(v_antigo) <> iara.tel_chave(ct.telefone_e164)
     -- contestada pelo número antigo nas últimas 24 h: nada de novo código
     and not exists (select 1 from iara.familia_trocas_numero t where t.guardian_id = g.id and t.cancelado_em > now() - interval '24 hours'
                     and t.motivo like 'Contestada%') then
    update iara.familia_trocas_numero set cancelado_em = now(), motivo = 'Substituída por novo pedido'
    where guardian_id = g.id and confirmado_em is null and cancelado_em is null;
    insert into iara.familia_trocas_numero (guardian_id, telefone_antigo, telefone_novo, is_demo)
    values (g.id, v_antigo, ct.telefone_e164, false) returning id into v_troca;
    v_cod := iara.familia_codigo_emitir(g.id, v_antigo, 'TROCAR_NUMERO', v_troca::text, ct.conversation_id, 30, format(
      '*IARA Educa · Secretaria de Educação de Maringá*%sPediram para trocar o WhatsApp do seu cadastro escolar para %s. Se foi você, digite no número novo o código *{codigo}* (vale 30 minutos).%sSe não foi você, responda aqui: *NÃO FUI EU*. A Educação nunca pede este código por telefone.',
      E'\n', iara.mask_phone(iara.fmt_tel(ct.telefone_e164)), E'\n\n'));
    update iara.familia_trocas_numero set codigo_id = v_cod where id = v_troca;
    perform iara.audit_event('FAMILIA_TROCA_PEDIDA', 'guardian', g.id::text, null,
      format('Pedido de troca do WhatsApp de %s; código enviado ao número antigo.', g.full_name));
  end if;
  return jsonb_build_object('ok', true, 'mensagem', v_generico);
end $$;

create or replace function api.familia_troca_confirmar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  ct iara.whatsapp_contacts := iara.familia_meu_contato();
  t iara.familia_trocas_numero;
  g iara.guardians;
  r jsonb;
  o record;
begin
  if ct.id is null then
    raise exception 'A troca de número é confirmada pelo WhatsApp do número novo.' using errcode = '22023';
  end if;
  select * into t from iara.familia_trocas_numero
  where iara.tel_chave(telefone_novo) = iara.tel_chave(ct.telefone_e164) and confirmado_em is null and cancelado_em is null
    and pedido_em > now() - interval '1 hour'
  order by pedido_em desc limit 1 for update;
  if t.id is null or t.codigo_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'SEM_PEDIDO',
      'mensagem', 'Não há pedido de troca em andamento para este número. Se quiser, comece de novo: diga "troquei de número".');
  end if;
  r := iara.familia_codigo_conferir(t.codigo_id, p ->> 'codigo');
  if not (r ->> 'ok')::boolean then
    if r ->> 'motivo' in ('BLOQUEADO', 'EXPIRADO', 'INVALIDO') then
      update iara.familia_trocas_numero set cancelado_em = now(), motivo = 'Código ' || lower(r ->> 'motivo') where id = t.id;
    end if;
    return r || jsonb_build_object('mensagem', case r ->> 'motivo'
      when 'ERRADO' then format('O código não confere. Restam %s tentativas.', r ->> 'restantes')
      when 'BLOQUEADO' then 'O código foi bloqueado depois de 5 tentativas. Para trocar o número, procure a secretaria da escola com um documento com foto.'
      when 'EXPIRADO' then 'O código venceu (vale 30 minutos). Se quiser, peça de novo: diga "troquei de número".'
      else 'Este código não vale mais. Se quiser, peça de novo: diga "troquei de número".' end);
  end if;
  update iara.familia_trocas_numero set confirmado_em = now(), libera_em = now() + interval '48 hours' where id = t.id returning * into t;
  select * into g from iara.guardians where id = t.guardian_id;
  perform iara.familia_enviar(t.telefone_antigo, format(
    '*IARA Educa · Secretaria de Educação de Maringá*%sO WhatsApp do seu cadastro escolar vai mudar para %s em 48 horas. Se não foi você, responda aqui: *NÃO FUI EU*, ou procure a escola.',
    E'\n', iara.mask_phone(iara.fmt_tel(t.telefone_novo))), t.id);
  -- os outros responsáveis das mesmas crianças também ficam sabendo
  for o in select distinct iara.tel_e164(coalesce(g2.whatsapp_phone, g2.primary_phone)) as tel
           from iara.student_guardians sg1
           join iara.student_guardians sg2 on sg2.student_id = sg1.student_id and sg2.guardian_id <> sg1.guardian_id and sg2.end_date is null
           join iara.guardians g2 on g2.id = sg2.guardian_id
           where sg1.guardian_id = t.guardian_id and sg1.end_date is null loop
    if o.tel is not null and iara.tel_chave(o.tel) <> iara.tel_chave(t.telefone_novo) then
      perform iara.familia_enviar(o.tel, format(
        '*IARA Educa · Secretaria de Educação de Maringá*%sAviso: o WhatsApp de %s no cadastro escolar vai mudar em 48 horas. Se você não reconhece este pedido, procure a escola.',
        E'\n', split_part(g.full_name, ' ', 1)), t.id);
    end if;
  end loop;
  perform iara.audit_event('FAMILIA_TROCA_CONFIRMADA', 'guardian', t.guardian_id::text, null,
    format('Troca do WhatsApp de %s confirmada pelo número antigo; vale a partir de %s.', g.full_name,
           to_char(t.libera_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')));
  return jsonb_build_object('ok', true, 'libera_em', t.libera_em, 'mensagem', format(
    'Pronto. A troca vale a partir de %s, depois de avisarmos o número antigo e os outros responsáveis. Até lá, este número recebe só informações gerais.',
    to_char(t.libera_em at time zone 'America/Sao_Paulo', 'DD/MM "às" HH24:MI')));
end $$;

create or replace function api.familia_troca_contestar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  ct iara.whatsapp_contacts := iara.familia_meu_contato();
  t record;
  v_n integer := 0;
begin
  if ct.id is null then
    return jsonb_build_object('ok', false, 'canceladas', 0);
  end if;
  for t in update iara.familia_trocas_numero set cancelado_em = now(), motivo = 'Contestada pelo número antigo'
           where iara.tel_chave(telefone_antigo) = iara.tel_chave(ct.telefone_e164) and aplicado_em is null and cancelado_em is null
           returning id, guardian_id, codigo_id loop
    if t.codigo_id is not null then
      update iara.familia_codigos set bloqueado_em = coalesce(bloqueado_em, now()) where id = t.codigo_id and usado_em is null;
      perform iara.familia_apagar_codigo(t.codigo_id);
    end if;
    perform iara.audit_event('FAMILIA_TROCA_CONTESTADA', 'guardian', t.guardian_id::text, null,
      'Pedido de troca do WhatsApp cancelado pelo número antigo ("não fui eu").');
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'canceladas', v_n, 'mensagem', case when v_n > 0
    then 'Pedido de troca cancelado. O seu número continua no cadastro. Por segurança, novos pedidos para este cadastro ficam parados por 24 horas. Se achar necessário, avise a escola.'
    else 'Não há pedido de troca em andamento para o seu número.' end);
end $$;

-- 11. Limpeza da apresentação: o que foi feito ao vivo na demonstração sai junto ---------------------------------------------
create or replace function iara.demo_purge_acesso_familias(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_v integer;
  v_q integer;
  v_c integer;
begin
  delete from iara.familia_vinculos where is_demo and criado_em >= coalesce(p_desde, '-infinity'::timestamptz);
  get diagnostics v_v = row_count;
  delete from iara.familia_qr where is_demo and criado_em >= coalesce(p_desde, '-infinity'::timestamptz);
  get diagnostics v_q = row_count;
  delete from iara.familia_codigos where is_demo and criado_em >= coalesce(p_desde, '-infinity'::timestamptz);
  get diagnostics v_c = row_count;
  delete from iara.familia_trocas_numero where is_demo and pedido_em >= coalesce(p_desde, '-infinity'::timestamptz);
  return jsonb_build_object('vinculos', v_v, 'qr', v_q, 'codigos', v_c);
end $$;

create or replace function api.demo_apresentacao_limpar(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r jsonb;
begin
  perform iara.require_perm('demo.manage');
  perform iara.exigir_demo();
  r := iara.demo_purge_session_data(null, null);
  r := r || jsonb_build_object('vida_escolar', iara.demo_purge_sprint1(null), 'pedagogico', iara.demo_purge_sprint2(null),
                               'transporte_almoxarifado', iara.demo_purge_sprint3(null), 'busca_ativa', iara.demo_purge_busca_ativa(null),
                               'ocorrencias', iara.demo_purge_ocorrencias(null), 'gestao', iara.demo_purge_gestao(null),
                               'sprint4', iara.demo_purge_sprint4(null), 'sprint5', iara.demo_purge_sprint5(null),
                               'reunioes', iara.demo_purge_reunioes(null),
                               'uniformes', iara.demo_purge_uniformes(null), 'apoio', iara.demo_purge_apoio(null),
                               'pendencias', iara.demo_purge_pendencias(null),
                               'acesso_familias', iara.demo_purge_acesso_familias(null),
                               'arquivos', iara.demo_limpar_arquivos_vivos(null));
  return jsonb_build_object('ok', true, 'resultado', r, 'situacao', api.demo_apresentacao_situacao('{}'::jsonb));
end $$;

revoke all on function iara.tel_chave(text), iara.tel_e164(text), iara.familia_hash(text), iara.familia_codigo_novo(), iara.familia_token_novo(),
  iara.familia_enviar(text, text, uuid), iara.familia_apagar_codigo(uuid),
  iara.familia_codigo_emitir(uuid, text, text, text, uuid, integer, text), iara.familia_codigo_conferir(uuid, text),
  iara.familia_identificar(text), iara.familia_trocas_aplicar(text), iara.familia_aplicar_identidade(uuid),
  iara.familia_vinculo_json(iara.familia_vinculos), iara.familia_vinculo_qr_usar(uuid, text), iara.familia_meu_contato(),
  iara.demo_purge_acesso_familias(timestamptz) from public;

commit;
