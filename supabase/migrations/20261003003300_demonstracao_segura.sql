-- IARA Educa — 033 · Demonstração segura para apresentações (Fase 1 do documento de estrutura, itens 1 e 5)
-- 1. WhatsApp de teste: lista opcional de números autorizados (interruptor no painel do canal). Fora da lista, a IARA
--    responde no máximo um aviso a cada 6 h e não cria contato, conversa nem família.
-- 2. Precisão do endereço junto da distância: o critério "até 2 km" registra a precisão do ponto da casa e avisa quando
--    ela é aproximada (ajuste 6.3-4 do documento do portal).
begin;

-- 1. Números autorizados ---------------------------------------------------------------------------------------
create table if not exists iara.whatsapp_avisos_bloqueio (
  channel_id uuid not null references iara.whatsapp_channels(id) on delete cascade,
  telefone_e164 text not null,
  primeiro_em timestamptz not null default now(),
  ultimo_aviso_em timestamptz not null default now(),
  tentativas integer not null default 1,
  primary key (channel_id, telefone_e164)
);
alter table iara.whatsapp_avisos_bloqueio enable row level security;

-- triagem de cada mensagem que chega: o número pode conversar? se não pode, avisa agora (no máximo 1 vez a cada 6 h)?
create or replace function iara.whatsapp_triagem(p_canal uuid, p_telefone text) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_digits text := regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g');
  v_settings jsonb := coalesce((select settings from iara.tenants where id = 1), '{}'::jsonb);
  v_restrito boolean := coalesce((v_settings ->> 'whatsapp_somente_autorizados')::boolean, false);
  v_ok boolean;
  v_avisar boolean := false;
  v_ultimo timestamptz;
begin
  v_ok := not v_restrito or exists (
    select 1 from jsonb_array_elements_text(coalesce(v_settings -> 'whatsapp_autorizados', '[]'::jsonb)) x
    where regexp_replace(x, '[^0-9]', '', 'g') = v_digits);
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
  return jsonb_build_object('autorizado', v_ok, 'avisar', coalesce(v_avisar, false),
                            'demo', coalesce((v_settings ->> 'demo_mode')::boolean, false));
end $$;
revoke all on function iara.whatsapp_triagem(uuid, text) from public;

create or replace function api.whatsapp_canal(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_settings jsonb := coalesce((select settings from iara.tenants where id = 1), '{}'::jsonb);
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
      'demo_mode', coalesce((v_settings ->> 'demo_mode')::boolean, false),
      'somente_autorizados', coalesce((v_settings ->> 'whatsapp_somente_autorizados')::boolean, false),
      -- a lista completa só para quem gerencia o canal; os demais veem a quantidade
      'autorizados', case when v_gerencia then coalesce(v_settings -> 'whatsapp_autorizados', '[]'::jsonb) else null end,
      'autorizados_qtd', jsonb_array_length(coalesce(v_settings -> 'whatsapp_autorizados', '[]'::jsonb)),
      'bloqueados_24h', (select count(*) from iara.whatsapp_avisos_bloqueio b where b.channel_id = c.id and b.ultimo_aviso_em > now() - interval '24 hours'),
      'contatos', (select count(*) from iara.whatsapp_contacts w where w.channel_id = c.id),
      'familias_vinculadas', (select count(*) from iara.whatsapp_contacts w where w.channel_id = c.id and w.guardian_id is not null),
      'mensagens_24h', (select count(*) from iara.whatsapp_inbound i where i.channel_id = c.id and i.received_at > now() - interval '24 hours'),
      'saida_pendente', (select count(*) from iara.whatsapp_outbox o where o.channel_id = c.id and o.status in ('PENDENTE', 'ENVIANDO', 'ERRO')),
      'enviadas_24h', (select count(*) from iara.whatsapp_outbox o where o.channel_id = c.id and o.status = 'ENVIADA' and o.enviada_em > now() - interval '24 hours'))
    from iara.whatsapp_channels c order by c.created_at limit 1);
end $$;

-- liga/desliga a lista e grava os números (E.164, só dígitos); auditado sem expor os números
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
  update iara.tenants set settings = settings || jsonb_build_object('whatsapp_somente_autorizados', v_on, 'whatsapp_autorizados', to_jsonb(v_lista))
  where id = 1;
  perform iara.audit_event('WHATSAPP_AUTORIZADOS', 'whatsapp_channel', null, null,
    format('Lista de números autorizados do WhatsApp %s, com %s número(s).', case when v_on then 'LIGADA' else 'DESLIGADA' end, cardinality(v_lista)));
  return api.whatsapp_canal('{}'::jsonb);
end $$;

update iara.feature_flags set description = 'Canal WhatsApp: na demonstração, ponte de teste (Baileys) ligada só em apresentações; quem conversa com ela recebe respostas de verdade. Produção: API oficial com número próprio.'
where code = 'WHATSAPP';

-- 2. Precisão do endereço no critério de proximidade --------------------------------------------------------------
create or replace function iara.compute_queue_priority(p_entry uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'iara', 'extensions', 'public'
AS $function$
declare
  w iara.waiting_list_entries;
  v_dist integer;
  v_reta integer;
  v_pe integer;
  v_carro integer;
  v_lat double precision;
  v_lng double precision;
  v_medida text;
  v_provisoria boolean := false;
  v_sibling boolean;
  v_cadunico boolean;
  v_single_mother boolean;
  v_aee boolean;
  v_laudo text;
  v_vuln boolean;
  v_breakdown jsonb := '[]'::jsonb;
  v_score numeric := 0;
  v_flags text[] := '{}';
  r iara.rules;
  v_max_m integer;
  v_precisao text;
begin
  select * into w from iara.waiting_list_entries where id = p_entry;
  if not found then return; end if;

  select st_y(a.location::geometry), st_x(a.location::geometry), round(st_distance(a.location, u.location))::int, a.geocode_precision
  into v_lat, v_lng, v_reta, v_precisao
  from iara.students s join iara.addresses a on a.id = s.address_id
  join iara.education_units u on u.id = w.preferred_unit_id
  where s.id = w.student_id;
  if v_lat is not null then
    select max(c.distancia_m) filter (where c.modo = 'A_PE' and not c.sem_rota), max(c.distancia_m) filter (where c.modo = 'CARRO' and not c.sem_rota)
    into v_pe, v_carro
    from iara.rotas_cache c
    where c.origem_lat = iara.c5(v_lat) and c.origem_lng = iara.c5(v_lng) and c.unit_id = w.preferred_unit_id;
  end if;

  select exists (
    select 1 from iara.student_guardians sg1
    join iara.student_guardians sg2 on sg2.guardian_id = sg1.guardian_id and sg2.student_id <> sg1.student_id
    join iara.enrollments e on e.student_id = sg2.student_id and e.status = 'ACTIVE' and e.unit_id = w.preferred_unit_id
    where sg1.student_id = w.student_id) into v_sibling;

  select coalesce(bool_or(g.cadunico_status), false), coalesce(bool_or(g.single_mother), false)
    into v_cadunico, v_single_mother
  from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
  where sg.student_id = w.student_id;

  select coalesce(aee_status, false) into v_aee from iara.students where id = w.student_id;
  select d.status into v_laudo from iara.documents d
  where d.student_id = w.student_id and d.doc_type = 'LAUDO' order by d.created_at desc limit 1;
  v_vuln := 'VULNERABILIDADE' = any (w.priority_flags);

  -- Critérios de pontuação, na ordem do Anexo I
  r := iara.rule('IRMAO_NA_UNIDADE');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', v_sibling,
      'evidence', case when v_sibling then 'Irmão(ã) com matrícula ativa na unidade pretendida' else 'Sem irmão(ã) matriculado(a) na unidade' end);
    if v_sibling then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'IRMAO_NA_UNIDADE'); end if;
  end if;

  r := iara.rule('CADUNICO');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', v_cadunico,
      'evidence', case when v_cadunico then 'Responsável com inscrição ativa no CadÚnico' else 'Sem inscrição no CadÚnico informada' end);
    if v_cadunico then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'CADUNICO'); end if;
  end if;

  -- proximidade: a medida (linha reta, a pé ou de carro) é parâmetro da regra; as três ficam registradas
  r := iara.rule('TERRITORIO_2KM');
  if r.id is not null then
    v_max_m := coalesce((r.condition ->> 'max_m')::int, 2000);
    v_medida := coalesce(nullif(r.condition ->> 'medida', ''), 'LINHA_RETA');
    v_dist := case v_medida when 'A_PE' then v_pe when 'CARRO' then v_carro else v_reta end;
    if v_dist is null and v_reta is not null and v_medida <> 'LINHA_RETA' then
      v_dist := v_reta;
      v_provisoria := true;
    end if;
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', coalesce(v_dist <= v_max_m, false), 'medida', v_medida, 'provisoria', v_provisoria, 'max_m', v_max_m,
      'distancias', jsonb_build_object('linha_reta_m', v_reta, 'a_pe_m', v_pe, 'carro_m', v_carro),
      'precisao_endereco', v_precisao, 'endereco_aproximado', v_reta is not null and iara.endereco_aproximado(v_precisao),
      'evidence', case when v_dist is null then 'Endereço sem geocodificação — critério não verificado'
                       else format('Residência a %s km da unidade pretendida (%s)%s', replace(round(v_dist / 1000.0, 1)::text, '.', ','),
                                   case when v_provisoria then 'em linha reta' else iara.medida_rotulo(v_medida) end,
                                   case when v_provisoria then format(' — rota %s ainda não calculada: vale a linha reta, provisoriamente',
                                                                      case v_medida when 'A_PE' then 'a pé' else 'de carro' end)
                                        else '' end)
                            || case when iara.endereco_aproximado(v_precisao)
                                    then ' · localização do endereço aproximada: confira o ponto no cadastro' else '' end end);
    if coalesce(v_dist <= v_max_m, false) then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'TERRITORIO'); end if;
  end if;

  r := iara.rule('MAE_SOLO');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', v_single_mother,
      'evidence', case when v_single_mother then 'Responsável declarou ser mãe solo' else 'Sem declaração de mãe solo' end);
    if v_single_mother then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'MAE_SOLO'); end if;
  end if;

  -- Critério de prioridade: sob análise, mediante laudo — fora da soma de pontos
  r := iara.rule('PCD_TEA_AEE');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', v_aee, 'analysis', r.rule_type = 'PRIORIDADE_ANALISE', 'laudo_status', coalesce(v_laudo, 'NAO_ENVIADO'),
      'evidence', case when not v_aee then 'Sem indicação de deficiência, TEA, TGD ou altas habilidades/superdotação'
                       when v_laudo = 'VALIDADO' then 'Laudo médico com CID validado — prioridade sob análise da Central de Vagas (não soma pontos)'
                       when v_laudo = 'RECEBIDO' then 'Laudo recebido, aguardando validação — prioridade sob análise (não soma pontos)'
                       else 'Indicação registrada; laudo médico com CID pendente — prioridade sob análise (não soma pontos)' end);
    if v_aee then
      v_flags := array_append(v_flags, 'PCD_TEA_AEE');
      if r.rule_type <> 'PRIORIDADE_ANALISE' then v_score := v_score + r.weight; end if;
    end if;
  end if;

  -- Regra anterior (2026.01), inativa na versão 2026.02: só conta se for reativada
  r := iara.rule('VULNERABILIDADE');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', r.weight, 'version', r.version,
      'applied', v_vuln, 'evidence', case when v_vuln then 'Encaminhamento da rede de proteção registrado' else 'Sem encaminhamento da rede de proteção' end);
    if v_vuln then v_score := v_score + r.weight; v_flags := array_append(v_flags, 'VULNERABILIDADE'); end if;
  end if;

  -- Desempate
  r := iara.rule('DATA_SOLICITACAO');
  if r.id is not null then
    v_breakdown := v_breakdown || jsonb_build_object('code', r.rule_code, 'name', r.name, 'weight', 0, 'version', r.version,
      'applied', true, 'evidence', format('Desempate pela data de entrada: %s', to_char(w.entered_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')));
  end if;

  update iara.waiting_list_entries set
    priority_score = v_score,
    score_breakdown = v_breakdown,
    home_distance_m = v_dist,
    dist_reta_m = v_reta,
    dist_pe_m = v_pe,
    dist_carro_m = v_carro,
    dist_medida = v_medida,
    priority_flags = v_flags,
    rule_version = iara.rule_version(),
    last_recalculated_at = now()
  where id = p_entry;
end $function$;

select iara.recalcular_filas();

commit;
