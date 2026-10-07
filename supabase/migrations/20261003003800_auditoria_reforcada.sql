-- IARA Educa — 038 · Auditoria reforçada (Fase 2, item 15 do documento de estrutura; SEC-BKP-06 e SEC-DADOS-05)
-- 1. TRUNCATE bloqueado (antes só UPDATE e DELETE eram).
-- 2. Encadeamento por hash: cada registro guarda o hash do anterior e o próprio (SHA-256 do conteúdo + hash anterior).
--    Alterar, apagar ou inserir fora de ordem quebra a corrente e é detectado por iara.auditoria_verificar().
--    Os registros existentes foram encadeados nesta migração (só as colunas novas foram preenchidas; nada mudou no conteúdo).
-- 3. Dados sensíveis na trilha: fora do modo demonstração, CPF, NIS, RG, renda e os dados de saúde/laudo entram como
--    "sha256:…" (prova que mudou, sem revelar o valor). Na demonstração seguem em claro, porque a limpeza do cenário
--    restaura valores pela trilha.
begin;

-- 1. TRUNCATE --------------------------------------------------------------------------------------------------------------
drop trigger if exists audit_log_no_truncate on iara.audit_log;
create trigger audit_log_no_truncate before truncate on iara.audit_log
  for each statement execute function iara.audit_immutable();

-- 2. Corrente de hashes ---------------------------------------------------------------------------------------------------------
alter table iara.audit_log add column if not exists chain_seq bigint;
alter table iara.audit_log add column if not exists hash_anterior text;
alter table iara.audit_log add column if not exists hash text;

create table if not exists iara.audit_chain_head (
  id smallint primary key default 1 check (id = 1),
  seq bigint not null default 0,
  hash text not null default 'GENESIS'
);
alter table iara.audit_chain_head enable row level security;
insert into iara.audit_chain_head (id) values (1) on conflict do nothing;

-- conteúdo canônico do registro (horário em UTC com microssegundos; JSON no formato normalizado do jsonb)
create or replace function iara.audit_conteudo(a iara.audit_log) returns text
language sql immutable as $$
  select concat_ws('|', a.id, a.chain_seq, a.tenant_id, to_char(a.occurred_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'),
                   a.user_id, a.actor_label, a.actor_role, a.action, a.entity_type, a.entity_id, a.unit_id, a.summary,
                   a.before_json::text, a.after_json::text, a.ip_address, a.user_agent, a.request_id)
$$;

create or replace function iara.audit_encadear() returns trigger
language plpgsql security definer set search_path = iara, extensions, public
as $$
declare
  h iara.audit_chain_head;
begin
  select * into h from iara.audit_chain_head where id = 1 for update;
  new.chain_seq := h.seq + 1;
  new.hash_anterior := h.hash;
  new.hash := encode(extensions.digest(h.hash || '|' || iara.audit_conteudo(new), 'sha256'), 'hex');
  update iara.audit_chain_head set seq = new.chain_seq, hash = new.hash where id = 1;
  return new;
end $$;

-- encadeia os registros que já existem (na ordem do id), uma única vez
do $$
declare
  a iara.audit_log;
  v_seq bigint := 0;
  v_hash text := 'GENESIS';
begin
  if exists (select 1 from iara.audit_log where hash is not null) then
    return;
  end if;
  alter table iara.audit_log disable trigger audit_log_no_update;
  for a in select * from iara.audit_log order by id loop
    v_seq := v_seq + 1;
    a.chain_seq := v_seq;
    a.hash_anterior := v_hash;
    v_hash := encode(extensions.digest(v_hash || '|' || iara.audit_conteudo(a), 'sha256'), 'hex');
    update iara.audit_log set chain_seq = v_seq, hash_anterior = a.hash_anterior, hash = v_hash where id = a.id;
  end loop;
  alter table iara.audit_log enable trigger audit_log_no_update;
  update iara.audit_chain_head set seq = v_seq, hash = v_hash where id = 1;
end $$;

drop trigger if exists audit_log_encadear on iara.audit_log;
create trigger audit_log_encadear before insert on iara.audit_log
  for each row execute function iara.audit_encadear();
create unique index if not exists audit_log_chain_seq_idx on iara.audit_log (chain_seq);

-- verificação: recalcula a corrente (por faixa, para trilhas grandes) e aponta a primeira quebra
create or replace function iara.auditoria_verificar(p_de bigint default 1, p_ate bigint default null) returns jsonb
language plpgsql stable security definer set search_path = iara, extensions, public
as $$
declare
  a iara.audit_log;
  v_ant text;
  v_n bigint := 0;
  v_calc text;
begin
  select hash into v_ant from iara.audit_log where chain_seq = p_de - 1;
  v_ant := coalesce(v_ant, case when p_de = 1 then 'GENESIS' end);
  for a in select * from iara.audit_log where chain_seq >= p_de and (p_ate is null or chain_seq <= p_ate) order by chain_seq loop
    v_calc := encode(extensions.digest(a.hash_anterior || '|' || iara.audit_conteudo(a), 'sha256'), 'hex');
    if a.hash_anterior is distinct from v_ant or a.hash is distinct from v_calc then
      return jsonb_build_object('integra', false, 'verificados', v_n, 'primeira_quebra', jsonb_build_object('seq', a.chain_seq, 'id', a.id,
        'motivo', case when a.hash_anterior is distinct from v_ant then 'corrente interrompida (registro removido ou inserido fora de ordem)'
                       else 'conteúdo alterado' end));
    end if;
    v_ant := a.hash;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('integra', true, 'verificados', v_n,
    'ultimo_seq', (select seq from iara.audit_chain_head where id = 1),
    'sem_corrente', (select count(*) from iara.audit_log where chain_seq is null));
end $$;
revoke all on function iara.auditoria_verificar(bigint, bigint) from public;

create or replace function api.auditoria_integridade(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('audit.read');
  return iara.auditoria_verificar(1, null) || jsonb_build_object('verificado_em', now());
end $$;

-- 3. Dados sensíveis na trilha -------------------------------------------------------------------------------------------------
create or replace function iara.audit_proteger(p_tabela text, j jsonb) returns jsonb
language plpgsql stable set search_path = iara, extensions, public
as $$
declare
  v_cols text[] := case p_tabela
    when 'student_sensitive' then array['special_education_need', 'medical_alerts', 'food_allergies', 'legal_notes']
    when 'students' then array['cpf', 'nis', 'sus_card', 'birth_certificate']
    when 'guardians' then array['cpf', 'nis', 'rg', 'family_income', 'monthly_income']
    else '{}'::text[] end;
  k text;
begin
  if j is null or cardinality(v_cols) = 0 or iara.demo_mode() then
    return j;
  end if;
  foreach k in array v_cols loop
    if j ? k and j -> k <> 'null'::jsonb then
      j := jsonb_set(j, array[k], to_jsonb('sha256:' || left(encode(extensions.digest(j ->> k, 'sha256'), 'hex'), 16)));
    end if;
  end loop;
  return j;
end $$;

create or replace function iara.audit_row() returns trigger
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_before jsonb;
  v_after jsonb;
  v_ignore text[] := array['updated_at'];
  v_changed text[];
  v_user uuid := iara.current_user_id();
  v_label text;
  v_role text;
  v_entity_id text;
  v_unit integer;
begin
  if coalesce(current_setting('iara.skip_audit', true), '') = 'on' then
    return coalesce(new, old);
  end if;
  if tg_nargs > 0 then
    v_ignore := v_ignore || string_to_array(tg_argv[0], ',');
  end if;
  if tg_op in ('UPDATE', 'DELETE') then v_before := to_jsonb(old); end if;
  if tg_op in ('INSERT', 'UPDATE') then v_after := to_jsonb(new); end if;

  if tg_op = 'UPDATE' then
    select coalesce(array_agg(k), '{}') into v_changed
    from jsonb_object_keys(v_after) k
    where not (k = any (v_ignore)) and (v_before -> k) is distinct from (v_after -> k);
    if cardinality(v_changed) = 0 then
      return new;
    end if;
    select jsonb_object_agg(k, v_before -> k) into v_before from unnest(v_changed) k;
    select jsonb_object_agg(k, v_after -> k) into v_after from unnest(v_changed) k;
  end if;

  v_entity_id := coalesce(to_jsonb(coalesce(new, old)) ->> 'id', to_jsonb(coalesce(new, old)) ->> 'student_id',
                          to_jsonb(coalesce(new, old)) ->> 'class_id');
  v_unit := coalesce((to_jsonb(coalesce(new, old)) ->> 'unit_id')::integer,
                     (to_jsonb(coalesce(new, old)) ->> 'preferred_unit_id')::integer);
  select display_name, role_code into v_label, v_role from iara.app_users where id = v_user;

  insert into iara.audit_log (user_id, actor_label, actor_role, action, entity_type, entity_id, unit_id,
                              before_json, after_json, ip_address, user_agent, request_id)
  values (v_user, coalesce(v_label, 'Sistema'), v_role, tg_op, tg_table_name, v_entity_id, v_unit,
          iara.audit_proteger(tg_table_name, v_before), iara.audit_proteger(tg_table_name, v_after),
          nullif(current_setting('iara.ip', true), ''), nullif(current_setting('iara.ua', true), ''),
          nullif(current_setting('iara.request_id', true), ''));
  return coalesce(new, old);
end $$;

commit;
