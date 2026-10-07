-- IARA Educa — 039 · Lista de números autorizados do WhatsApp sai de tenants.settings (legível pelo perfil anônimo por
-- causa das funções públicas) e vai para a tabela do canal, que não tem leitura pública. Encontrado pelo teste
-- supabase/tests/autorizacao_cobertura.sql (E4). Defesa em profundidade: o schema iara não é exposto pela API de dados.
begin;

alter table iara.whatsapp_channels add column if not exists somente_autorizados boolean not null default false;
alter table iara.whatsapp_channels add column if not exists autorizados text[] not null default '{}';

-- migra o que já estiver gravado e limpa o tenant
update iara.whatsapp_channels c set
  somente_autorizados = coalesce((t.settings ->> 'whatsapp_somente_autorizados')::boolean, false),
  autorizados = coalesce((select array_agg(x) from jsonb_array_elements_text(t.settings -> 'whatsapp_autorizados') x), '{}')
from iara.tenants t where t.id = 1 and (t.settings ? 'whatsapp_autorizados' or t.settings ? 'whatsapp_somente_autorizados');
update iara.tenants set settings = settings - 'whatsapp_autorizados' - 'whatsapp_somente_autorizados' where id = 1;

create or replace function iara.whatsapp_triagem(p_canal uuid, p_telefone text) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_digits text := regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g');
  c iara.whatsapp_channels;
  v_ok boolean;
  v_avisar boolean := false;
  v_ultimo timestamptz;
begin
  select * into c from iara.whatsapp_channels where id = p_canal;
  v_ok := not coalesce(c.somente_autorizados, false)
          or exists (select 1 from unnest(c.autorizados) x where regexp_replace(x, '[^0-9]', '', 'g') = v_digits);
  if not v_ok then
    -- 1ª mensagem do número: avisa; depois, só se o último aviso tiver mais de 6 h
    insert into iara.whatsapp_avisos_bloqueio (channel_id, telefone_e164) values (p_canal, '+' || v_digits) on conflict do nothing;
    if found then
      v_avisar := true;
    else
      select ultimo_aviso_em into v_ultimo from iara.whatsapp_avisos_bloqueio
      where channel_id = p_canal and telefone_e164 = '+' || v_digits for update;
      v_avisar := v_ultimo < now() - interval '6 hours';
      update iara.whatsapp_avisos_bloqueio set tentativas = tentativas + 1,
             ultimo_aviso_em = case when v_avisar then now() else ultimo_aviso_em end
      where channel_id = p_canal and telefone_e164 = '+' || v_digits;
    end if;
  end if;
  return jsonb_build_object('autorizado', v_ok, 'avisar', coalesce(v_avisar, false), 'demo', iara.demo_mode());
end $$;
revoke all on function iara.whatsapp_triagem(uuid, text) from public;

create or replace function api.whatsapp_canal(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_gerencia boolean := iara.has_perm('channels.manage');
begin
  if not (iara.has_perm('conversations.read') or v_gerencia) then
    raise exception 'Sem permissão para ver o canal do WhatsApp.' using errcode = '42501';
  end if;
  return (
    select jsonb_build_object('id', c.id, 'numero', c.numero_e164, 'numero_formatado', iara.fmt_tel(c.numero_e164), 'nome', c.nome,
      'provedor', c.provedor, 'ativo', c.ativo, 'estado', c.estado,
      'online', c.conectado and c.ultimo_sinal_em > now() - interval '3 minutes',
      'ultimo_sinal_em', c.ultimo_sinal_em, 'pareado_em', c.pareado_em, 'ligado_em', c.ligado_em, 'desligado_em', c.desligado_em,
      'alterado_por', c.alterado_por, 'compartilhado_com', c.compartilhado_com, 'observacoes', c.observacoes,
      'ponte_configurada', c.segredo_hash is not null, 'pode_gerenciar', v_gerencia,
      'demo_mode', iara.demo_mode(),
      'somente_autorizados', c.somente_autorizados,
      -- a lista completa só para quem gerencia o canal; os demais veem a quantidade
      'autorizados', case when v_gerencia then to_jsonb(c.autorizados) else null end,
      'autorizados_qtd', cardinality(c.autorizados),
      'bloqueados_24h', (select count(*) from iara.whatsapp_avisos_bloqueio b where b.channel_id = c.id and b.ultimo_aviso_em > now() - interval '24 hours'),
      'contatos', (select count(*) from iara.whatsapp_contacts w where w.channel_id = c.id),
      'familias_vinculadas', (select count(*) from iara.whatsapp_contacts w where w.channel_id = c.id and w.guardian_id is not null),
      'mensagens_24h', (select count(*) from iara.whatsapp_inbound i where i.channel_id = c.id and i.received_at > now() - interval '24 hours'),
      'saida_pendente', (select count(*) from iara.whatsapp_outbox o where o.channel_id = c.id and o.status in ('PENDENTE', 'ENVIANDO', 'ERRO')),
      'enviadas_24h', (select count(*) from iara.whatsapp_outbox o where o.channel_id = c.id and o.status = 'ENVIADA' and o.enviada_em > now() - interval '24 hours'))
    from iara.whatsapp_channels c order by c.created_at limit 1);
end $$;

create or replace function api.whatsapp_autorizados_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_lista text[];
  v_bad text;
  v_on boolean := coalesce((p ->> 'somente_autorizados')::boolean, false);
begin
  perform iara.require_perm('channels.manage');
  select array_agg(distinct d order by d) into v_lista
  from (select regexp_replace(x, '[^0-9]', '', 'g') as d from jsonb_array_elements_text(coalesce(p -> 'numeros', '[]'::jsonb)) x) z
  where d <> '';
  v_lista := coalesce(v_lista, '{}');
  select d into v_bad from unnest(v_lista) d where length(d) < 12 or length(d) > 15 limit 1;
  if v_bad is not null then
    raise exception 'Número inválido: %. Use o formato com país e DDD, por exemplo 55 44 99999-0000.', v_bad using errcode = '22023';
  end if;
  if cardinality(v_lista) > 200 then
    raise exception 'No máximo 200 números autorizados.' using errcode = '22023';
  end if;
  if v_on and cardinality(v_lista) = 0 then
    raise exception 'Inclua ao menos um número antes de ligar a lista.' using errcode = '22023';
  end if;
  update iara.whatsapp_channels set somente_autorizados = v_on, autorizados = v_lista, updated_at = now()
  where id = (select id from iara.whatsapp_channels order by created_at limit 1);
  perform iara.audit_event('WHATSAPP_AUTORIZADOS', 'whatsapp_channel', null, null,
    format('Lista de números autorizados do WhatsApp %s, com %s número(s).', case when v_on then 'LIGADA' else 'DESLIGADA' end, cardinality(v_lista)));
  return api.whatsapp_canal('{}'::jsonb);
end $$;

-- a rotina de apresentação lê o estado da lista no canal
create or replace function api.demo_apresentacao_situacao(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_users uuid[];
  v_davi uuid := nullif(iara.setting('demo_student_davi'), '')::uuid;
  w iara.waiting_list_entries;
  v_ultima timestamptz;
begin
  perform iara.require_perm('demo.manage');
  perform iara.exigir_demo();
  v_users := iara.demo_session_users(null);
  select * into w from iara.waiting_list_entries where student_id = v_davi and status in ('WAITING', 'OFFERED') order by entered_at limit 1;
  select max(occurred_at) into v_ultima from iara.audit_log where action = 'DEMO_PURGE';
  return jsonb_build_object(
    'demo_mode', true,
    'davi', jsonb_build_object('posicao', w.position, 'pontos', w.priority_score, 'situacao', w.status),
    'davi_ok', w.position = 1 and w.priority_score = 95,
    'criado_por_visitas', jsonb_build_object(
      'familias', (select count(*) from iara.guardians g where g.created_by = any (v_users)),
      'criancas', (select count(*) from iara.students s where s.created_by = any (v_users)),
      'protocolos', (select count(*) from iara.service_cases c where c.created_by = any (v_users)),
      'conversas_whatsapp', (select count(*) from iara.whatsapp_contacts)),
    'ultima_limpeza', v_ultima,
    'whatsapp', (select jsonb_build_object('ligado', c.ativo, 'online', c.conectado and c.ultimo_sinal_em > now() - interval '3 minutes',
                                           'somente_autorizados', c.somente_autorizados)
                 from iara.whatsapp_channels c order by c.created_at limit 1)
  );
end $$;

commit;
