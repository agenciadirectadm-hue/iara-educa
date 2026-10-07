-- IARA Educa — 062 · Ocorrências: 1ª e 2ª instância, visibilidade para a família, modelos de resposta e indicadores
-- Professores e famílias registram. A unidade trata em 1ª instância; a Secretaria (SEDUC) trata em 2ª instância quando a unidade
-- encaminha ou quando a família pede a análise, e acompanha a rede. Todos consultam dentro do seu escopo; a família vê o registro,
-- as comunicações e a solução — nunca as tratativas internas. Respostas à família saem de modelos editáveis (versionados).
-- Violência contra criança: classificação pela Lei 13.431/2017 (art. 4º) e Lei 13.185/2015 (intimidação sistemática); suspeita de
-- violência sexual, autoprovocada ou grave abre a comunicação obrigatória ao Conselho Tutelar (ECA, arts. 13 e 245; Lei 13.431/2017,
-- art. 13; Lei 13.819/2019), pelo mesmo fluxo de aprovação e envio da busca ativa. Registro sigiloso não aparece para a família.
-- Indicadores: solução e prazos, turmas, idade, assuntos e tipos de violência, com a leitura “amplo / localizado / reincidente / isolado”
-- para separar o que pede formação e conscientização do que é caso isolado.
begin;

insert into iara.permissions (code, description, is_sensitive) values
  ('ocorrencias.seduc', 'Tratar ocorrências em 2ª instância (Secretaria) e acompanhar a rede', true),
  ('ocorrencias.modelos', 'Editar os modelos de resposta às famílias nas ocorrências', false)
on conflict (code) do update set description = excluded.description, is_sensitive = excluded.is_sensitive;
insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('SECRETARIO', 'ocorrencias.seduc'), ('SUPERINTENDENCIA', 'ocorrencias.seduc'), ('GERENCIA_EI', 'ocorrencias.seduc'),
  ('SECRETARIO', 'ocorrencias.modelos'), ('SUPERINTENDENCIA', 'ocorrencias.modelos'),
  ('PROFESSOR_AEE', 'ocorrencias.read'), ('PROFESSOR_AEE', 'ocorrencias.write'), ('ATENDIMENTO', 'ocorrencias.read')
) v(r, p)
on conflict do nothing;

-- 1. Estrutura ----------------------------------------------------------------------------------------------------------------------
alter table iara.ocorrencias
  add column if not exists instancia text not null default 'UNIDADE' check (instancia in ('UNIDADE', 'SECRETARIA')),
  add column if not exists violencia text[] not null default '{}',
  add column if not exists sigilosa boolean not null default false,
  add column if not exists prazo date,
  add column if not exists encaminhada_seduc_em timestamptz,
  add column if not exists encaminhada_por_label text,
  add column if not exists motivo_seduc text,
  add column if not exists pedido_familia boolean not null default false,
  add column if not exists solucao text,
  add column if not exists solucao_em timestamptz,
  add column if not exists solucao_por_label text,
  add column if not exists comunicada_em timestamptz,
  add column if not exists alterada_em timestamptz,
  add column if not exists demo_padrao boolean not null default false;
alter table iara.ocorrencias drop constraint if exists ocorrencias_violencia_valida;
alter table iara.ocorrencias add constraint ocorrencias_violencia_valida
  check (violencia <@ array['FISICA', 'PSICOLOGICA', 'SEXUAL', 'INSTITUCIONAL', 'PATRIMONIAL', 'BULLYING', 'CYBERBULLYING', 'DISCRIMINACAO', 'AUTOLESAO']::text[]);
create index if not exists ocorrencias_instancia_idx on iara.ocorrencias (instancia, situacao);

alter table iara.ocorrencia_eventos
  add column if not exists interno boolean not null default false,
  add column if not exists tipo text not null default 'COMENTARIO'
    check (tipo in ('COMENTARIO', 'NOTA_INTERNA', 'SITUACAO', 'COMUNICACAO', 'ENCAMINHADA_SEDUC', 'PEDIDO_REVISAO', 'DEVOLVIDA_UNIDADE', 'SOLUCAO', 'CLASSIFICACAO'));

alter table iara.encaminhamentos add column if not exists ocorrencia_id uuid references iara.ocorrencias(id) on delete set null;

-- modelos de resposta: cada alteração é uma nova versão; a versão mais alta de cada código é a vigente (ativo = false: excluído)
create table if not exists iara.ocorrencia_modelos (
  id uuid primary key default gen_random_uuid(),
  codigo text not null,
  momento text not null check (momento in ('RECEBIMENTO', 'ANDAMENTO', 'SOLUCAO', 'ENCAMINHADA_SEDUC', 'DEVOLUTIVA_SEDUC')),
  tipos text[] not null default '{}',
  titulo text not null,
  texto text not null,
  ativo boolean not null default true,
  versao integer not null default 1,
  alterado_por_label text,
  alterado_em timestamptz not null default now(),
  unique (codigo, versao)
);
alter table iara.ocorrencia_modelos enable row level security;

insert into iara.ocorrencia_modelos (codigo, momento, tipos, titulo, texto, alterado_por_label, alterado_em) values
  ('RECEBIMENTO', 'RECEBIMENTO', '{}', 'Recebemos o seu relato',
   'Olá! A {unidade} recebeu o seu relato sobre {aluno}, de {data}. A direção vai analisar e responder até {prazo}. Você acompanha pelo portal e pela IARA.',
   'SEDUC (modelo inicial — validar)', '2026-10-01'),
  ('SOLUCAO_PADRAO', 'SOLUCAO', '{}', 'Solução — padrão',
   'Olá! Sobre o registro de {data} envolvendo {aluno}: {solucao} Se quiser conversar, a direção da {unidade} está à disposição. Se não concordar, você pode pedir a análise da Secretaria Municipal de Educação pelo portal ou pela IARA.',
   'SEDUC (modelo inicial — validar)', '2026-10-01'),
  ('SOLUCAO_CONVIVENCIA', 'SOLUCAO', '{CONFLITO,BULLYING,COMPORTAMENTO}', 'Solução — convivência e respeito',
   'Olá! Sobre o registro de {data} envolvendo {aluno}: {solucao} Por respeito à privacidade, não informamos dados de outras crianças. A escola segue acompanhando a convivência da turma; se algo se repetir, avise por aqui. Se não concordar, você pode pedir a análise da Secretaria Municipal de Educação.',
   'SEDUC (modelo inicial — validar)', '2026-10-01'),
  ('SOLUCAO_ACIDENTE', 'SOLUCAO', '{ACIDENTE,SAUDE}', 'Solução — acidente ou saúde',
   'Olá! Sobre o que aconteceu com {aluno} em {data}: {solucao} Qualquer sinal diferente em casa, avise a escola por aqui.',
   'SEDUC (modelo inicial — validar)', '2026-10-01'),
  ('ENCAMINHADA_SEDUC', 'ENCAMINHADA_SEDUC', '{}', 'Encaminhada à Secretaria',
   'Olá! O registro de {data} sobre {aluno} foi encaminhado à Secretaria Municipal de Educação para análise em segunda instância. A resposta está prevista até {prazo}.',
   'SEDUC (modelo inicial — validar)', '2026-10-01'),
  ('DEVOLUTIVA_SEDUC', 'DEVOLUTIVA_SEDUC', '{}', 'Resposta da Secretaria',
   'Olá! A Secretaria Municipal de Educação analisou o registro de {data} sobre {aluno}: {solucao} A {unidade} acompanha a partir daqui.',
   'SEDUC (modelo inicial — validar)', '2026-10-01')
on conflict (codigo, versao) do nothing;

-- 2. Regras -------------------------------------------------------------------------------------------------------------------------
-- prazos de resposta (dias corridos; proposta a validar pela SEDUC — ajustáveis em settings.ocorrencia_prazos)
create or replace function iara.ocorrencia_prazo(p_grav text, p_instancia text, p_de timestamptz default now()) returns date
language sql stable security definer set search_path = iara, public
as $$
  select (p_de at time zone 'America/Sao_Paulo')::date + coalesce(
    (nullif(iara.setting('ocorrencia_prazos'), '')::jsonb ->> case when p_instancia = 'SECRETARIA' then 'SECRETARIA' else p_grav end)::int,
    case when p_instancia = 'SECRETARIA' then 10 when p_grav = 'GRAVE' then 2 when p_grav = 'MODERADA' then 5 else 10 end)
$$;

-- violência que exige comunicação ao Conselho Tutelar (a direção confere e aprova; nada sai sem validação humana)
create or replace function iara.ocorrencia_exige_ct(o iara.ocorrencias) returns boolean
language sql immutable as $$
  select o.violencia && array['SEXUAL', 'AUTOLESAO']::text[]
      or (o.gravidade = 'GRAVE' and o.violencia && array['FISICA', 'PSICOLOGICA', 'INSTITUCIONAL']::text[])
$$;

create or replace function iara.ocorrencia_render(p_texto text, o iara.ocorrencias, p_solucao text default null) returns text
language sql stable security definer set search_path = iara, public
as $$
  select replace(replace(replace(replace(replace(p_texto,
           '{aluno}', split_part(s.full_name, ' ', 1)),
           '{unidade}', coalesce(u.short_name, 'escola')),
           '{data}', to_char(o.ocorrida_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY')),
           '{prazo}', coalesce(to_char(o.prazo, 'DD/MM/YYYY'), 'os próximos dias')),
           '{solucao}', coalesce(nullif(btrim(coalesce(p_solucao, o.solucao, '')), ''), '(descreva a solução)'))
  from iara.students s left join iara.education_units u on u.id = o.unit_id
  where s.id = o.student_id
$$;

create or replace function iara.ocorrencia_modelo_vigente(p_momento text, p_tipo text) returns iara.ocorrencia_modelos
language sql stable security definer set search_path = iara, public
as $$
  select m.* from iara.ocorrencia_modelos m
  where m.momento = p_momento and m.ativo and m.versao = (select max(versao) from iara.ocorrencia_modelos x where x.codigo = m.codigo)
    and (m.tipos = '{}' or p_tipo = any (m.tipos))
  order by cardinality(m.tipos) = 0, m.codigo limit 1
$$;

-- comunicação à família: notificação no portal + WhatsApp (se a família tiver o canal vinculado). Registro sigiloso não notifica.
create or replace function iara.ocorrencia_notificar(o iara.ocorrencias, p_titulo text, p_texto text) returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  g record;
  v_notif uuid;
  n integer := 0;
begin
  if o.sigilosa then return 0; end if;
  for g in select sg.guardian_id from iara.student_guardians sg
           where sg.student_id = o.student_id and sg.end_date is null and coalesce(sg.can_receive_notifications, true) loop
    insert into iara.notifications (tenant_id, guardian_id, student_id, channel, event_type, title, body, status)
    values (1, g.guardian_id, o.student_id, 'PORTAL', 'OCORRENCIA', p_titulo, p_texto, 'ENVIADA')
    returning id into v_notif;
    insert into iara.whatsapp_outbox (channel_id, contact_id, telefone_e164, jid, texto, origem, ref_id)
    select w.channel_id, w.id, w.telefone_e164, w.jid, p_texto, 'NOTIFICACAO', v_notif
    from iara.whatsapp_contacts w join iara.whatsapp_channels ch on ch.id = w.channel_id
    where w.guardian_id = g.guardian_id and ch.ativo order by w.ultima_em desc limit 1;
    n := n + 1;
  end loop;
  return n;
end $$;

-- comunicação obrigatória ao Conselho Tutelar: prepara o expediente (aguardando aprovação) e a tarefa urgente da direção.
-- Não avisa a família: em suspeita de violência a família pode estar envolvida.
create or replace function iara.ocorrencia_comunicar_ct(p_ocorrencia uuid, p_autor text default null) returns uuid
language plpgsql security definer set search_path = iara, public
as $$
declare
  o iara.ocorrencias;
  v_enc uuid;
  v_fund text;
begin
  select * into o from iara.ocorrencias where id = p_ocorrencia;
  if o.id is null then return null; end if;
  select id into v_enc from iara.encaminhamentos where ocorrencia_id = o.id and tipo = 'CONSELHO_TUTELAR' and situacao <> 'CANCELADO' limit 1;
  if v_enc is not null then return v_enc; end if;
  v_fund := case when o.violencia && array['SEXUAL'] then 'Suspeita ou relato de violência sexual — ECA, art. 13; Lei 13.431/2017, art. 13'
                 when o.violencia && array['AUTOLESAO'] then 'Suspeita de violência autoprovocada — Lei 13.819/2019, art. 6º; ECA, art. 13'
                 else 'Suspeita de violência contra criança — ECA, arts. 13 e 245; Lei 13.431/2017, art. 13' end;
  insert into iara.encaminhamentos (caso_id, student_id, unit_id, tipo, orgao_id, servico, necessidade, fundamento, obrigatorio, conteudo,
                                    comunicar_familia, criado_por_label, ocorrencia_id, is_demo)
  values ((select k.id from iara.busca_ativa_casos k where k.student_id = o.student_id and k.situacao <> 'ENCERRADO' limit 1),
          o.student_id, o.unit_id, 'CONSELHO_TUTELAR',
          (select og.id from iara.orgaos_destinatarios og join iara.education_units u on u.id = o.unit_id
           where og.tipo = 'CONSELHO_TUTELAR' and og.ativo and og.verificado and (u.macro_territory_id = any (og.territorio_ids) or og.territorio_ids = '{}')
           order by og.territorio_ids = '{}' limit 1),
          'Comunicação de ocorrência', 'Ocorrência registrada na escola com indício de violência.', v_fund, true,
          iara.ba_expediente(o.student_id, null, v_fund) - 'ausencias' - 'motivos' - 'contatos'
            || jsonb_build_object('ocorrencia', jsonb_build_object('data', o.ocorrida_em, 'assunto', o.tipo, 'violencia', to_jsonb(o.violencia),
                                  'gravidade', o.gravidade, 'local', o.local, 'relato', o.descricao, 'providencias', o.providencias)),
          false, coalesce(p_autor, iara.my_label(), 'IARA (regra automática)'), o.id, o.is_demo)
  returning id into v_enc;
  insert into iara.frequencia_tarefas (student_id, unit_id, tipo, prioridade, destino, descricao, prazo, obrigatoria, chave, is_demo)
  values (o.student_id, o.unit_id, 'NOTIFICAR_CT', 'URGENTE', 'DIRECAO',
          'Comunicação obrigatória ao Conselho Tutelar (ocorrência com indício de violência): conferir o expediente, aprovar e enviar pelo canal oficial. Não avisar a família antes da avaliação.',
          iara.hoje_local(), true, 'ct:' || v_enc, o.is_demo)
  on conflict (chave) do nothing;
  insert into iara.ocorrencia_eventos (ocorrencia_id, origem, tipo, interno, texto, autor_label, is_demo)
  values (o.id, 'ESCOLA', 'NOTA_INTERNA', true, 'Comunicação ao Conselho Tutelar preparada (' || v_fund || '), aguardando a aprovação da direção.',
          coalesce(p_autor, iara.my_label(), 'IARA (regra automática)'), o.is_demo);
  return v_enc;
end $$;

-- 3. JSON e consultas ------------------------------------------------------------------------------------------------------------
drop function if exists iara.ocorrencia_json(iara.ocorrencias, boolean);
create or replace function iara.ocorrencia_json(o iara.ocorrencias, p_eventos boolean default true, p_familia boolean default false) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', o.id, 'student_id', o.student_id, 'aluno', s.full_name, 'primeiro_nome', split_part(s.full_name, ' ', 1),
    'turma', c.class_name, 'class_id', o.class_id, 'unidade', u.short_name, 'unit_id', o.unit_id, 'origem', o.origem, 'tipo', o.tipo,
    'gravidade', o.gravidade, 'ocorrida_em', o.ocorrida_em, 'local', o.local, 'descricao', o.descricao, 'providencias', o.providencias,
    'situacao', o.situacao, 'registrada_por', o.registrada_por_label, 'ciencia_familia_em', o.ciencia_familia_em,
    'aguarda_ciencia', o.origem = 'ESCOLA' and o.ciencia_familia_em is null,
    'instancia', o.instancia, 'pedido_familia', o.pedido_familia, 'encaminhada_seduc_em', o.encaminhada_seduc_em,
    'prazo', o.prazo, 'vencida', o.situacao <> 'ENCERRADA' and o.prazo < iara.hoje_local(),
    'solucao', o.solucao, 'solucao_em', o.solucao_em, 'comunicada_em', o.comunicada_em, 'is_demo', o.is_demo)
  || case when p_familia then '{}'::jsonb else jsonb_build_object('violencia', to_jsonb(o.violencia), 'sigilosa', o.sigilosa,
       'motivo_seduc', o.motivo_seduc, 'encaminhada_por', o.encaminhada_por_label, 'solucao_por', o.solucao_por_label,
       'idade', extract(year from age((o.ocorrida_em at time zone 'America/Sao_Paulo')::date, s.birth_date))::int) end
  || jsonb_build_object('eventos', case when p_eventos then (
       select coalesce(jsonb_agg(jsonb_build_object('origem', e.origem, 'tipo', e.tipo, 'interno', e.interno, 'texto', e.texto, 'situacao', e.situacao,
                'autor', e.autor_label, 'em', e.created_at) order by e.created_at), '[]')
       from iara.ocorrencia_eventos e where e.ocorrencia_id = o.id and (not p_familia or not e.interno)) end)
  from iara.students s left join iara.classes c on c.id = o.class_id left join iara.education_units u on u.id = o.unit_id
  where s.id = o.student_id
$$;

-- família: só o que é dela e não é sigiloso (o relato que ela mesma fez continua visível para ela)
create or replace function iara.ocorrencia_visivel_familia(o iara.ocorrencias) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select coalesce(iara.my_guardian() is not null and o.student_id in (select iara.my_student_ids())
     and (not o.sigilosa or coalesce(o.registrada_por_guardian = iara.my_guardian(), false)), false)
$$;

create or replace function api.ocorrencias_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_prof boolean := iara.my_role() in ('PROFESSOR', 'PROFESSOR_AEE');
  v_busca text := nullif(iara.norm(btrim(coalesce(p ->> 'busca', ''))), '');
  v_hoje date := iara.hoje_local();
begin
  perform iara.require_perm('ocorrencias.read');
  return (with base as (
      select o.* from iara.ocorrencias o
      where (v_unit is null or o.unit_id = v_unit)
        and (not v_prof or o.class_id = any (iara.minhas_turmas()))
        and (nullif(p ->> 'class_id', '') is null or o.class_id = (p ->> 'class_id')::uuid)
        and (nullif(p ->> 'tipo', '') is null or o.tipo = p ->> 'tipo')
        and (nullif(p ->> 'origem', '') is null or o.origem = p ->> 'origem')
        and (nullif(p ->> 'instancia', '') is null or o.instancia = p ->> 'instancia')
        and (nullif(p ->> 'violencia', '') is null or (p ->> 'violencia' = 'QUALQUER' and o.violencia <> '{}') or (p ->> 'violencia') = any (o.violencia))
        and (not coalesce((p ->> 'vencidas')::boolean, false) or (o.situacao <> 'ENCERRADA' and o.prazo < v_hoje))
        and (v_busca is null or exists (select 1 from iara.students s where s.id = o.student_id and iara.norm(s.full_name) like '%' || v_busca || '%')))
    select jsonb_build_object(
      'contagem', (select jsonb_build_object('ABERTA', count(*) filter (where situacao = 'ABERTA'), 'EM_ACOMPANHAMENTO', count(*) filter (where situacao = 'EM_ACOMPANHAMENTO'),
                   'ENCERRADA', count(*) filter (where situacao = 'ENCERRADA'), 'FAMILIA', count(*) filter (where origem = 'FAMILIA' and situacao <> 'ENCERRADA'),
                   'sem_ciencia', count(*) filter (where origem = 'ESCOLA' and ciencia_familia_em is null and situacao <> 'ENCERRADA'),
                   'SECRETARIA', count(*) filter (where instancia = 'SECRETARIA' and situacao <> 'ENCERRADA'),
                   'vencidas', count(*) filter (where situacao <> 'ENCERRADA' and prazo < v_hoje),
                   'violencia', count(*) filter (where violencia <> '{}' and situacao <> 'ENCERRADA')) from base),
      'pode_registrar', iara.has_perm('ocorrencias.write'),
      'pode_seduc', iara.has_perm('ocorrencias.seduc'),
      'pode_modelos', iara.has_perm('ocorrencias.modelos'),
      'itens', (select coalesce(jsonb_agg(iara.ocorrencia_json(o, false) order by (o.situacao = 'ENCERRADA'), o.ocorrida_em desc), '[]')
                from (select * from base b
                      where nullif(p ->> 'situacao', '') is null or (p ->> 'situacao' = 'PENDENTES' and b.situacao <> 'ENCERRADA') or b.situacao = p ->> 'situacao'
                      order by (b.situacao = 'ENCERRADA'), b.ocorrida_em desc limit 300) o)));
end $$;

create or replace function api.ocorrencia_detalhe(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  o iara.ocorrencias;
  v_fam boolean;
  v_unid boolean;
  v_seduc boolean;
  v_gestor boolean;
begin
  select * into o from iara.ocorrencias where id = (p ->> 'id')::uuid;
  if o.id is null then raise exception 'Ocorrência não encontrada.' using errcode = 'P0002'; end if;
  v_fam := iara.ocorrencia_visivel_familia(o);
  if not (v_fam or iara.aluno_acesso(o.student_id, 'ocorrencias.read')) then
    raise exception 'Ocorrência não encontrada.' using errcode = 'P0002';
  end if;
  v_unid := not v_fam and iara.aluno_acesso(o.student_id, 'ocorrencias.write');
  v_seduc := not v_fam and iara.has_perm('ocorrencias.seduc') and iara.can_access_student(o.student_id);
  v_gestor := v_unid and iara.my_role() not in ('PROFESSOR', 'PROFESSOR_AEE');
  if v_fam then
    return iara.ocorrencia_json(o, true, true) || jsonb_build_object(
      'pode_comentar', true, 'pode_dar_ciencia', o.origem = 'ESCOLA' and o.ciencia_familia_em is null,
      'pode_pedir_revisao', o.instancia = 'UNIDADE' and not o.pedido_familia and (o.situacao = 'ENCERRADA' or o.prazo < iara.hoje_local()));
  end if;
  return iara.ocorrencia_json(o, true, false) || jsonb_build_object(
    'pode_atualizar', v_unid or v_seduc,
    'pode_comentar', v_unid or v_seduc,
    'pode_dar_ciencia', false,
    'pode_solucionar', o.situacao <> 'ENCERRADA' and ((o.instancia = 'UNIDADE' and (v_gestor or (v_unid and o.gravidade = 'LEVE' and o.origem = 'ESCOLA')))
                                                       or (o.instancia = 'SECRETARIA' and v_seduc)),
    'pode_encaminhar_seduc', o.situacao <> 'ENCERRADA' and o.instancia = 'UNIDADE' and v_gestor,
    'pode_devolver', o.situacao <> 'ENCERRADA' and o.instancia = 'SECRETARIA' and v_seduc,
    'pode_classificar', v_unid or v_seduc,
    'exige_ct', iara.ocorrencia_exige_ct(o),
    'pode_comunicar_ct', (v_gestor or v_seduc) and o.violencia <> '{}',
    'encaminhamentos', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'tipo', e.tipo, 'situacao', e.situacao, 'fundamento', e.fundamento,
                          'orgao', og.nome, 'protocolo', e.protocolo, 'criado_em', e.created_at) order by e.created_at), '[]')
                        from iara.encaminhamentos e left join iara.orgaos_destinatarios og on og.id = e.orgao_id where e.ocorrencia_id = o.id),
    'modelos', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'codigo', m.codigo, 'titulo', m.titulo, 'momento', m.momento,
                  'texto', m.texto) order by cardinality(m.tipos) = 0, m.titulo), '[]')
                from iara.ocorrencia_modelos m
                where m.ativo and m.versao = (select max(versao) from iara.ocorrencia_modelos x where x.codigo = m.codigo)
                  and m.momento in ('SOLUCAO', 'DEVOLUTIVA_SEDUC', 'ANDAMENTO') and (m.tipos = '{}' or o.tipo = any (m.tipos))),
    'previa', jsonb_build_object('aluno', split_part((select full_name from iara.students where id = o.student_id), ' ', 1),
                                 'unidade', (select short_name from iara.education_units where id = o.unit_id),
                                 'data', to_char(o.ocorrida_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'),
                                 'prazo', to_char(o.prazo, 'DD/MM/YYYY')));
end $$;

create or replace function api.familia_ocorrencias(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_lista jsonb;
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(iara.ocorrencia_json(o, true, true) || jsonb_build_object('pode_pedir_revisao',
           o.instancia = 'UNIDADE' and not o.pedido_familia and (o.situacao = 'ENCERRADA' or o.prazo < iara.hoje_local()))
         order by (o.situacao = 'ENCERRADA'), o.ocorrida_em desc), '[]') into v_lista
  from (select * from iara.ocorrencias x where x.student_id in (select iara.my_student_ids())
          and (not x.sigilosa or coalesce(x.registrada_por_guardian = iara.my_guardian(), false))
        order by x.ocorrida_em desc limit 60) o;
  return jsonb_build_object('ocorrencias', v_lista,
    'aguardando_ciencia', (select count(*) from jsonb_array_elements(v_lista) x where x ->> 'origem' = 'ESCOLA' and x ->> 'ciencia_familia_em' is null),
    'em_aberto', (select count(*) from jsonb_array_elements(v_lista) x where x ->> 'situacao' <> 'ENCERRADA'));
end $$;

create or replace function api.familia_ocorrencia_ciente(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  o iara.ocorrencias;
begin
  select * into o from iara.ocorrencias where id = (p ->> 'id')::uuid;
  if o.id is null or not iara.ocorrencia_visivel_familia(o) then
    raise exception 'Ocorrência não encontrada.' using errcode = 'P0002';
  end if;
  update iara.ocorrencias set ciencia_familia_em = coalesce(ciencia_familia_em, now()) where id = o.id;
  perform iara.audit_event('OCORRENCIA_CIENCIA', 'student', o.student_id::text, o.unit_id, 'Família deu ciência de uma ocorrência registrada pela escola.');
  return jsonb_build_object('ok', true);
end $$;

-- 4. Registro e tratamento ----------------------------------------------------------------------------------------------------------
create or replace function api.ocorrencia_registrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_fam boolean := iara.my_guardian() is not null;
  v_tipo text := coalesce(nullif(p ->> 'tipo', ''), 'OUTRO');
  v_grav text := coalesce(nullif(p ->> 'gravidade', ''), case when v_tipo in ('BULLYING') then 'MODERADA' else 'LEVE' end);
  v_desc text := btrim(coalesce(p ->> 'descricao', ''));
  v_prov text := nullif(btrim(coalesce(p ->> 'providencias', '')), '');
  v_viol text[] := coalesce((select array_agg(distinct x) from jsonb_array_elements_text(coalesce(p -> 'violencia', '[]')) x), '{}');
  v_enc boolean := coalesce((p ->> 'encerrar')::boolean, false);
  v_ct uuid;
  m iara.ocorrencia_modelos;
  e record;
  o iara.ocorrencias;
begin
  if v_fam then
    if not (v_student in (select iara.my_student_ids())) then raise exception 'Criança não vinculada a você.' using errcode = '42501'; end if;
    v_viol := '{}'; v_enc := false; v_prov := null;
  elsif not iara.aluno_acesso(v_student, 'ocorrencias.write') then
    raise exception 'Sem permissão para registrar ocorrência deste aluno.' using errcode = '42501';
  end if;
  if v_tipo not in ('COMPORTAMENTO', 'CONFLITO', 'ACIDENTE', 'SAUDE', 'BULLYING', 'PERTENCES', 'ATRASO_SAIDA', 'PEDAGOGICA', 'ELOGIO', 'OUTRO')
     or v_grav not in ('LEVE', 'MODERADA', 'GRAVE') then
    raise exception 'Tipo ou gravidade inválidos.' using errcode = '22023';
  end if;
  if not v_viol <@ array['FISICA', 'PSICOLOGICA', 'SEXUAL', 'INSTITUCIONAL', 'PATRIMONIAL', 'BULLYING', 'CYBERBULLYING', 'DISCRIMINACAO', 'AUTOLESAO']::text[] then
    raise exception 'Tipo de violência inválido.' using errcode = '22023';
  end if;
  if length(v_desc) not between 10 and 2000 then raise exception 'Conte o que aconteceu (de 10 a 2.000 caracteres).' using errcode = '22023'; end if;
  if v_enc and (v_viol <> '{}' or v_grav = 'GRAVE') then
    raise exception 'Ocorrência grave ou com violência não pode ser registrada já encerrada: ela precisa de tratamento.' using errcode = '22023';
  end if;
  select en.unit_id, en.class_id into e from iara.enrollments en where en.student_id = v_student and en.status = 'ACTIVE' limit 1;
  if e.unit_id is null then raise exception 'O aluno não tem matrícula ativa.' using errcode = '22023'; end if;
  insert into iara.ocorrencias (student_id, unit_id, class_id, origem, tipo, gravidade, ocorrida_em, local, descricao, providencias, situacao,
                                registrada_por_label, registrada_por_guardian, violencia, sigilosa, prazo, solucao, solucao_em, solucao_por_label, is_demo)
  values (v_student, e.unit_id, e.class_id, case when v_fam then 'FAMILIA' else 'ESCOLA' end, v_tipo, v_grav,
          coalesce(nullif(p ->> 'ocorrida_em', '')::timestamptz, now()), nullif(btrim(coalesce(p ->> 'local', '')), ''), v_desc, v_prov,
          case when v_enc then 'ENCERRADA' else 'ABERTA' end,
          iara.my_label(), case when v_fam then iara.my_guardian() end, v_viol,
          not v_fam and (coalesce((p ->> 'sigilosa')::boolean, false) or v_viol && array['SEXUAL']::text[]),
          iara.ocorrencia_prazo(v_grav, 'UNIDADE'),
          case when v_enc then coalesce(v_prov, 'Resolvido no momento pela escola.') end, case when v_enc then now() end, case when v_enc then iara.my_label() end,
          false)
  returning * into o;
  if v_fam then
    m := iara.ocorrencia_modelo_vigente('RECEBIMENTO', o.tipo);
    if m.id is not null then
      insert into iara.ocorrencia_eventos (ocorrencia_id, origem, tipo, interno, texto, autor_label, is_demo)
      values (o.id, 'ESCOLA', 'COMUNICACAO', false, iara.ocorrencia_render(m.texto, o), 'IARA (resposta automática)', false);
    end if;
  end if;
  if iara.ocorrencia_exige_ct(o) then v_ct := iara.ocorrencia_comunicar_ct(o.id); end if;
  perform iara.audit_event('OCORRENCIA_REGISTRADA', 'student', v_student::text, e.unit_id,
    format('Ocorrência (%s, %s) registrada pela %s.', lower(v_tipo), lower(v_grav), case when v_fam then 'família' else 'escola' end));
  return iara.ocorrencia_json(o, true, v_fam) || jsonb_build_object('comunicacao_ct', v_ct is not null, 'mensagem', case
    when v_fam then 'Registrado. A direção da escola recebe agora e responde até ' || to_char(o.prazo, 'DD/MM') || '; acompanhe na Vida escolar e pela IARA.'
    when v_ct is not null then 'Registrado. Indício de violência: a comunicação ao Conselho Tutelar foi preparada e aguarda a aprovação da direção (Busca ativa › Comunicações legais).'
    when o.sigilosa then 'Registrado como sigiloso: a família não vê este registro.'
    else 'Registrado. A família vê no portal e pela IARA e pode dar ciência.' end);
end $$;

-- tratamento: notas internas, mensagem à família, 2ª instância, solução com modelo, classificação e Conselho Tutelar
create or replace function api.ocorrencia_atualizar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  o iara.ocorrencias;
  v_fam boolean;
  v_unid boolean;
  v_seduc boolean;
  v_gestor boolean;
  v_txt text := btrim(coalesce(p ->> 'texto', ''));
  v_sit text := nullif(p ->> 'situacao', '');
  v_acao text;
  v_msg text;
  v_sol text;
  v_viol text[];
  m iara.ocorrencia_modelos;
  v_n integer;
begin
  select * into o from iara.ocorrencias where id = (p ->> 'id')::uuid for update;
  if o.id is null then raise exception 'Ocorrência não encontrada.' using errcode = 'P0002'; end if;
  v_fam := iara.ocorrencia_visivel_familia(o);
  v_unid := not v_fam and iara.aluno_acesso(o.student_id, 'ocorrencias.write');
  v_seduc := not v_fam and iara.has_perm('ocorrencias.seduc') and iara.can_access_student(o.student_id);
  v_gestor := v_unid and iara.my_role() not in ('PROFESSOR', 'PROFESSOR_AEE');
  if not (v_fam or v_unid or v_seduc) then raise exception 'Sem permissão para esta ocorrência.' using errcode = '42501'; end if;
  v_acao := upper(coalesce(nullif(p ->> 'acao', ''), case when v_fam then 'COMENTAR' when v_sit = 'ENCERRADA' then 'SOLUCIONAR'
                                                          when v_sit is not null and v_txt = '' then 'SITUACAO' else 'NOTA_INTERNA' end));
  if v_fam and v_acao not in ('COMENTAR', 'PEDIR_REVISAO') then raise exception 'Ação não permitida para a família.' using errcode = '42501'; end if;
  if length(v_txt) > 2000 then raise exception 'Texto longo demais (máximo de 2.000 caracteres).' using errcode = '22023'; end if;

  if v_acao = 'COMENTAR' then
    if length(v_txt) < 3 then raise exception 'Escreva a mensagem.' using errcode = '22023'; end if;
    insert into iara.ocorrencia_eventos (ocorrencia_id, origem, tipo, interno, texto, autor_label, is_demo)
    values (o.id, case when v_fam then 'FAMILIA' else 'ESCOLA' end, case when v_fam then 'COMENTARIO' else 'COMUNICACAO' end, false, v_txt, iara.my_label(), false);
    if not v_fam then
      perform iara.ocorrencia_notificar(o, 'Mensagem da escola sobre ' || split_part((select full_name from iara.students where id = o.student_id), ' ', 1), v_txt);
      update iara.ocorrencias set situacao = case when situacao = 'ABERTA' then 'EM_ACOMPANHAMENTO' else situacao end where id = o.id;
    end if;

  elsif v_acao in ('NOTA_INTERNA', 'SITUACAO') then
    if v_sit is not null and v_sit not in ('ABERTA', 'EM_ACOMPANHAMENTO') then
      raise exception 'Para encerrar, registre a solução que a família vai receber.' using errcode = '22023';
    end if;
    if length(v_txt) < 3 and v_sit is null then raise exception 'Escreva a nota interna.' using errcode = '22023'; end if;
    insert into iara.ocorrencia_eventos (ocorrencia_id, origem, tipo, interno, texto, situacao, autor_label, is_demo)
    values (o.id, 'ESCOLA', case when v_txt = '' then 'SITUACAO' else 'NOTA_INTERNA' end, true, coalesce(nullif(v_txt, ''), 'Situação alterada.'), v_sit, iara.my_label(), false);
    update iara.ocorrencias set situacao = coalesce(v_sit, case when situacao = 'ABERTA' then 'EM_ACOMPANHAMENTO' else situacao end) where id = o.id;

  elsif v_acao = 'ENCAMINHAR_SEDUC' then
    if not v_gestor or o.instancia <> 'UNIDADE' or o.situacao = 'ENCERRADA' then
      raise exception 'Só a equipe gestora da unidade encaminha à Secretaria uma ocorrência em aberto na 1ª instância.' using errcode = '42501';
    end if;
    if length(v_txt) < 10 then raise exception 'Explique o motivo do encaminhamento (mínimo de 10 caracteres).' using errcode = '22023'; end if;
    update iara.ocorrencias set instancia = 'SECRETARIA', encaminhada_seduc_em = now(), encaminhada_por_label = iara.my_label(), motivo_seduc = v_txt,
           situacao = 'EM_ACOMPANHAMENTO', prazo = iara.ocorrencia_prazo(gravidade, 'SECRETARIA')
    where id = o.id returning * into o;
    insert into iara.ocorrencia_eventos (ocorrencia_id, origem, tipo, interno, texto, autor_label, is_demo)
    values (o.id, 'ESCOLA', 'ENCAMINHADA_SEDUC', true, 'Encaminhada à Secretaria (2ª instância): ' || v_txt, iara.my_label(), false);
    m := iara.ocorrencia_modelo_vigente('ENCAMINHADA_SEDUC', o.tipo);
    if m.id is not null then
      v_msg := iara.ocorrencia_render(m.texto, o);
      insert into iara.ocorrencia_eventos (ocorrencia_id, origem, tipo, interno, texto, autor_label, is_demo)
      values (o.id, 'ESCOLA', 'COMUNICACAO', false, v_msg, iara.my_label(), false);
      perform iara.ocorrencia_notificar(o, 'Registro encaminhado à Secretaria de Educação', v_msg);
    end if;

  elsif v_acao = 'PEDIR_REVISAO' then
    if not v_fam or o.instancia <> 'UNIDADE' or o.pedido_familia or not (o.situacao = 'ENCERRADA' or o.prazo < iara.hoje_local()) then
      raise exception 'A análise da Secretaria pode ser pedida depois da resposta da escola ou quando o prazo dela vence.' using errcode = '22023';
    end if;
    if length(v_txt) < 10 then raise exception 'Conte por que você pede a análise da Secretaria (mínimo de 10 caracteres).' using errcode = '22023'; end if;
    update iara.ocorrencias set instancia = 'SECRETARIA', pedido_familia = true, encaminhada_seduc_em = now(), encaminhada_por_label = 'Família',
           motivo_seduc = v_txt, situacao = 'EM_ACOMPANHAMENTO', prazo = iara.ocorrencia_prazo(gravidade, 'SECRETARIA')
    where id = o.id returning * into o;
    insert into iara.ocorrencia_eventos (ocorrencia_id, origem, tipo, interno, texto, autor_label, is_demo)
    values (o.id, 'FAMILIA', 'PEDIDO_REVISAO', false, 'Pedido de análise pela Secretaria: ' || v_txt, iara.my_label(), false);
    m := iara.ocorrencia_modelo_vigente('ENCAMINHADA_SEDUC', o.tipo);
    if m.id is not null then
      insert into iara.ocorrencia_eventos (ocorrencia_id, origem, tipo, interno, texto, autor_label, is_demo)
      values (o.id, 'ESCOLA', 'COMUNICACAO', false, iara.ocorrencia_render(m.texto, o), 'IARA (resposta automática)', false);
    end if;

  elsif v_acao = 'DEVOLVER_UNIDADE' then
    if not v_seduc or o.instancia <> 'SECRETARIA' or o.situacao = 'ENCERRADA' then raise exception 'Só a Secretaria devolve uma ocorrência em 2ª instância.' using errcode = '42501'; end if;
    if o.pedido_familia then raise exception 'Pedido de análise da família: a Secretaria responde com a solução.' using errcode = '22023'; end if;
    if length(v_txt) < 10 then raise exception 'Escreva a orientação para a unidade (mínimo de 10 caracteres).' using errcode = '22023'; end if;
    update iara.ocorrencias set instancia = 'UNIDADE', prazo = iara.ocorrencia_prazo(gravidade, 'UNIDADE') where id = o.id;
    insert into iara.ocorrencia_eventos (ocorrencia_id, origem, tipo, interno, texto, autor_label, is_demo)
    values (o.id, 'ESCOLA', 'DEVOLVIDA_UNIDADE', true, 'Devolvida à unidade com orientação da Secretaria: ' || v_txt, iara.my_label(), false);

  elsif v_acao = 'SOLUCIONAR' then
    if o.situacao = 'ENCERRADA' then raise exception 'Esta ocorrência já está encerrada.' using errcode = '22023'; end if;
    if not ((o.instancia = 'UNIDADE' and (v_gestor or (v_unid and o.gravidade = 'LEVE' and o.origem = 'ESCOLA'))) or (o.instancia = 'SECRETARIA' and v_seduc)) then
      raise exception '%', case when o.instancia = 'SECRETARIA' then 'Em 2ª instância, quem responde é a Secretaria.' else 'A solução é registrada pela equipe gestora da unidade.' end
        using errcode = '42501';
    end if;
    -- solução (o que a família recebe como resultado) e mensagem (texto do modelo, editável); chamada antiga: o texto é a solução
    v_sol := btrim(coalesce(nullif(p ->> 'solucao', ''), v_txt));
    if length(v_sol) < 10 then raise exception 'Descreva a solução (mínimo de 10 caracteres).' using errcode = '22023'; end if;
    if exists (select 1 from iara.encaminhamentos k where k.ocorrencia_id = o.id and k.obrigatorio and k.situacao in ('AGUARDANDO_APROVACAO', 'APROVADO', 'FALHA_ENVIO')) then
      raise exception 'Conclua antes a comunicação obrigatória ao Conselho Tutelar (Busca ativa › Comunicações legais).' using errcode = '22023';
    end if;
    v_msg := case when nullif(p ->> 'solucao', '') is not null then nullif(v_txt, '') end;
    if v_msg is null then
      m := iara.ocorrencia_modelo_vigente(case when o.instancia = 'SECRETARIA' then 'DEVOLUTIVA_SEDUC' else 'SOLUCAO' end, o.tipo);
      v_msg := iara.ocorrencia_render(coalesce(m.texto, '{solucao}'), o, v_sol);
    end if;
    if v_msg like '%(descreva a solução)%' or v_msg ~ '\{[a-z]+\}' then raise exception 'A mensagem à família ainda tem campos do modelo para preencher.' using errcode = '22023'; end if;
    update iara.ocorrencias set situacao = 'ENCERRADA', solucao = v_sol, solucao_em = now(), solucao_por_label = iara.my_label(),
           comunicada_em = case when sigilosa then null else now() end
    where id = o.id returning * into o;
    insert into iara.ocorrencia_eventos (ocorrencia_id, origem, tipo, interno, texto, situacao, autor_label, is_demo)
    values (o.id, 'ESCOLA', 'SOLUCAO', o.sigilosa, v_msg, 'ENCERRADA', iara.my_label(), false);
    perform iara.ocorrencia_notificar(o, case when o.instancia = 'SECRETARIA' then 'Resposta da Secretaria de Educação' else 'Resposta da escola' end, v_msg);

  elsif v_acao = 'CLASSIFICAR' then
    if not (v_unid or v_seduc) then raise exception 'Sem permissão para classificar.' using errcode = '42501'; end if;
    v_viol := coalesce((select array_agg(distinct x) from jsonb_array_elements_text(coalesce(p -> 'violencia', to_jsonb(o.violencia))) x), '{}');
    if not v_viol <@ array['FISICA', 'PSICOLOGICA', 'SEXUAL', 'INSTITUCIONAL', 'PATRIMONIAL', 'BULLYING', 'CYBERBULLYING', 'DISCRIMINACAO', 'AUTOLESAO']::text[] then
      raise exception 'Tipo de violência inválido.' using errcode = '22023';
    end if;
    if coalesce(p ->> 'tipo', o.tipo) not in ('COMPORTAMENTO', 'CONFLITO', 'ACIDENTE', 'SAUDE', 'BULLYING', 'PERTENCES', 'ATRASO_SAIDA', 'PEDAGOGICA', 'ELOGIO', 'OUTRO')
       or coalesce(p ->> 'gravidade', o.gravidade) not in ('LEVE', 'MODERADA', 'GRAVE') then
      raise exception 'Tipo ou gravidade inválidos.' using errcode = '22023';
    end if;
    update iara.ocorrencias set tipo = coalesce(nullif(p ->> 'tipo', ''), tipo), gravidade = coalesce(nullif(p ->> 'gravidade', ''), gravidade), violencia = v_viol,
           sigilosa = coalesce((p ->> 'sigilosa')::boolean, sigilosa) or v_viol && array['SEXUAL']::text[]
    where id = o.id returning * into o;
    insert into iara.ocorrencia_eventos (ocorrencia_id, origem, tipo, interno, texto, autor_label, is_demo)
    values (o.id, 'ESCOLA', 'CLASSIFICACAO', true, format('Classificação: %s, %s%s%s.', lower(o.tipo), lower(o.gravidade),
              case when o.violencia <> '{}' then '; violência: ' || lower(array_to_string(o.violencia, ', ')) else '' end,
              case when o.sigilosa then '; sigilosa' else '' end) || coalesce(' ' || nullif(v_txt, ''), ''), iara.my_label(), false);
    if iara.ocorrencia_exige_ct(o) then perform iara.ocorrencia_comunicar_ct(o.id); end if;

  elsif v_acao = 'COMUNICAR_CT' then
    if not (v_gestor or v_seduc) then raise exception 'A comunicação ao Conselho Tutelar é preparada pela direção ou pela Secretaria.' using errcode = '42501'; end if;
    if o.violencia = '{}' then raise exception 'Classifique antes o tipo de violência.' using errcode = '22023'; end if;
    perform iara.ocorrencia_comunicar_ct(o.id);
  else
    raise exception 'Ação desconhecida.' using errcode = '22023';
  end if;

  update iara.ocorrencias set alterada_em = now() where id = o.id;
  perform iara.audit_event('OCORRENCIA_ACOMPANHADA', 'student', o.student_id::text, o.unit_id,
    format('Ocorrência: %s pela %s.', lower(replace(v_acao, '_', ' ')), case when v_fam then 'família' when v_seduc and not v_unid then 'Secretaria' else 'escola' end));
  return api.ocorrencia_detalhe(jsonb_build_object('id', o.id));
end $$;

-- 5. Modelos de resposta -------------------------------------------------------------------------------------------------------------
create or replace function api.ocorrencia_modelos(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('ocorrencias.read');
  return jsonb_build_object('pode_editar', iara.has_perm('ocorrencias.modelos'),
    'modelos', (select coalesce(jsonb_agg(to_jsonb(m) || jsonb_build_object('vigente', true) order by m.momento, m.titulo), '[]')
                from iara.ocorrencia_modelos m where m.versao = (select max(versao) from iara.ocorrencia_modelos x where x.codigo = m.codigo)
                  and (m.ativo or coalesce((p ->> 'excluidos')::boolean, false))),
    'historico', case when nullif(p ->> 'codigo', '') is not null then
                   (select coalesce(jsonb_agg(to_jsonb(m) order by m.versao desc), '[]') from iara.ocorrencia_modelos m where m.codigo = p ->> 'codigo') end,
    'campos', jsonb_build_array('{aluno}', '{unidade}', '{data}', '{prazo}', '{solucao}'));
end $$;

-- inclusão, alteração (nova versão) e exclusão (versão inativa); sem linguagem de ameaça ou de culpa
create or replace function api.ocorrencia_modelo_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_cod text := upper(regexp_replace(btrim(coalesce(p ->> 'codigo', '')), '[^A-Za-z0-9_]+', '_', 'g'));
  v_atual iara.ocorrencia_modelos;
  v_excluir boolean := coalesce((p ->> 'excluir')::boolean, false);
  v_texto text := btrim(coalesce(p ->> 'texto', ''));
  v_tipos text[] := coalesce((select array_agg(distinct x) from jsonb_array_elements_text(coalesce(p -> 'tipos', '[]')) x), '{}');
  m iara.ocorrencia_modelos;
begin
  perform iara.require_perm('ocorrencias.modelos');
  if v_cod = '' then v_cod := 'MODELO_' || upper(substr(md5(random()::text), 1, 6)); end if;
  select * into v_atual from iara.ocorrencia_modelos where codigo = v_cod order by versao desc limit 1;
  if v_excluir then
    if v_atual.id is null or not v_atual.ativo then raise exception 'Modelo não encontrado.' using errcode = 'P0002'; end if;
    if v_atual.codigo in ('RECEBIMENTO', 'SOLUCAO_PADRAO', 'ENCAMINHADA_SEDUC', 'DEVOLUTIVA_SEDUC') then
      raise exception 'Este modelo é usado nas respostas automáticas: altere o texto em vez de excluir.' using errcode = '22023';
    end if;
    insert into iara.ocorrencia_modelos (codigo, momento, tipos, titulo, texto, ativo, versao, alterado_por_label)
    values (v_atual.codigo, v_atual.momento, v_atual.tipos, v_atual.titulo, v_atual.texto, false, v_atual.versao + 1, iara.my_label())
    returning * into m;
  else
    if coalesce(p ->> 'momento', v_atual.momento) not in ('RECEBIMENTO', 'ANDAMENTO', 'SOLUCAO', 'ENCAMINHADA_SEDUC', 'DEVOLUTIVA_SEDUC') then
      raise exception 'Momento inválido.' using errcode = '22023';
    end if;
    if length(btrim(coalesce(p ->> 'titulo', ''))) < 3 then raise exception 'Dê um título ao modelo.' using errcode = '22023'; end if;
    if length(v_texto) not between 20 and 1500 then raise exception 'O texto deve ter de 20 a 1.500 caracteres.' using errcode = '22023'; end if;
    if iara.norm(v_texto) ~ '(sob pena|sera(o)? punid|processad|denunciad|policia|multa|culpa (e|da) famil|negligen)' then
      raise exception 'Evite linguagem de ameaça ou de culpa na resposta à família.' using errcode = '22023';
    end if;
    if v_texto ~ '\{' and exists (select 1 from regexp_matches(v_texto, '\{([a-z]+)\}', 'g') x where x[1] not in ('aluno', 'unidade', 'data', 'prazo', 'solucao')) then
      raise exception 'Campo desconhecido no texto. Use {aluno}, {unidade}, {data}, {prazo} ou {solucao}.' using errcode = '22023';
    end if;
    if not v_tipos <@ array['COMPORTAMENTO', 'CONFLITO', 'ACIDENTE', 'SAUDE', 'BULLYING', 'PERTENCES', 'ATRASO_SAIDA', 'PEDAGOGICA', 'ELOGIO', 'OUTRO']::text[] then
      raise exception 'Assunto inválido.' using errcode = '22023';
    end if;
    insert into iara.ocorrencia_modelos (codigo, momento, tipos, titulo, texto, ativo, versao, alterado_por_label)
    values (v_cod, coalesce(p ->> 'momento', v_atual.momento), v_tipos, btrim(p ->> 'titulo'), v_texto, true, coalesce(v_atual.versao, 0) + 1, iara.my_label())
    returning * into m;
  end if;
  perform iara.audit_event('OCORRENCIA_MODELO', 'ocorrencia_modelo', m.codigo, null,
    format('Modelo de resposta %s (versão %s)%s.', m.codigo, m.versao, case when v_excluir then ' excluído' else '' end));
  return to_jsonb(m);
end $$;

-- 6. Indicadores ---------------------------------------------------------------------------------------------------------------------
-- leitura de cada grupo (assunto ou tipo de violência): menos de 5 casos → isolado; poucos alunos concentram → reincidente;
-- uma turma concentra → localizado; espalhado por muitas turmas/unidades → amplo (formação e conscientização). Limiares: proposta.
create or replace function iara.ocorrencia_leitura(n bigint, alunos bigint, reinc bigint, turmas bigint, unidades bigint, top_turma bigint, p_rede boolean) returns text
language sql immutable as $$
  select case when n < 5 then 'ISOLADO'
              when reinc * 2 >= n then 'REINCIDENTE'
              when top_turma * 100 >= n * 40 then 'LOCALIZADO'
              when (p_rede and unidades >= 5) or (not p_rede and turmas >= 4) then 'AMPLO'
              else 'ISOLADO' end
$$;

create or replace function api.ocorrencias_indicadores(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_prof boolean := iara.my_role() in ('PROFESSOR', 'PROFESSOR_AEE');
  v_de date := coalesce(nullif(p ->> 'de', '')::date, nullif(iara.setting('ano_letivo_inicio'), '')::date, make_date(extract(year from iara.hoje_local())::int, 1, 1));
  v_ate date := coalesce(nullif(p ->> 'ate', '')::date, iara.hoje_local());
  v_hoje date := iara.hoje_local();
  v_rede boolean;
  v jsonb;
begin
  perform iara.require_perm('ocorrencias.read');
  v_rede := v_unit is null;
  with bx as materialized (
    select o.id, o.student_id, o.unit_id, o.class_id, c.class_name turma, gl.name serie, gl.code serie_code, u.short_name unidade, o.tipo, o.gravidade, o.origem,
           o.situacao, o.instancia, o.pedido_familia, o.violencia,
           extract(year from age((o.ocorrida_em at time zone 'America/Sao_Paulo')::date, s.birth_date))::int idade,
           case when o.solucao_em is not null then round(extract(epoch from o.solucao_em - o.ocorrida_em) / 86400.0, 1) end dias_solucao,
           case when o.situacao <> 'ENCERRADA' then v_hoje - (o.ocorrida_em at time zone 'America/Sao_Paulo')::date end dias_aberta,
           o.situacao <> 'ENCERRADA' and o.prazo < v_hoje vencida, date_trunc('month', o.ocorrida_em at time zone 'America/Sao_Paulo')::date mes
    from iara.ocorrencias o join iara.students s on s.id = o.student_id
    left join iara.classes c on c.id = o.class_id left join iara.grade_levels gl on gl.id = c.grade_level_id
    left join iara.education_units u on u.id = o.unit_id
    where o.tipo <> 'ELOGIO' and (v_unit is null or o.unit_id = v_unit) and (not v_prof or o.class_id = any (iara.minhas_turmas()))
      and (o.ocorrida_em at time zone 'America/Sao_Paulo')::date between v_de and v_ate),
  grupos as (
      select 'TIPO' dim, tipo chave, id, student_id, class_id, unit_id from bx
      union all select 'VIOLENCIA', unnest(violencia), id, student_id, class_id, unit_id from bx),
    g as (select dim, chave, count(*) n, count(distinct student_id) alunos, count(distinct class_id) turmas, count(distinct unit_id) unidades,
                 (select count(*) from (select student_id from grupos g2 where g2.dim = g1.dim and g2.chave = g1.chave group by 1 having count(*) >= 2) z) reinc_alunos,
                 (select coalesce(sum(c), 0) from (select count(*) c from grupos g2 where g2.dim = g1.dim and g2.chave = g1.chave group by student_id having count(*) >= 2) z) reinc,
                 (select max(c) from (select count(*) c from grupos g2 where g2.dim = g1.dim and g2.chave = g1.chave group by class_id) z) top_turma,
                 (select t.turma || ' · ' || t.unidade from bx t join grupos g2 on g2.id = t.id where g2.dim = g1.dim and g2.chave = g1.chave
                  group by t.class_id, t.turma, t.unidade order by count(*) desc limit 1) turma_top
          from grupos g1 group by dim, chave)
  select jsonb_build_object(
    'periodo', jsonb_build_object('de', v_de, 'ate', v_ate), 'rede', v_rede,
    'resumo', (select jsonb_build_object('total', count(*), 'abertas', count(*) filter (where situacao = 'ABERTA'),
                 'em_acompanhamento', count(*) filter (where situacao = 'EM_ACOMPANHAMENTO'), 'encerradas', count(*) filter (where situacao = 'ENCERRADA'),
                 'taxa_solucao', round(100.0 * count(*) filter (where situacao = 'ENCERRADA') / nullif(count(*), 0), 1),
                 'tempo_medio_dias', round(avg(dias_solucao), 1), 'vencidas', count(*) filter (where vencida),
                 'segunda_instancia', count(*) filter (where instancia = 'SECRETARIA'), 'pedidos_familia', count(*) filter (where pedido_familia),
                 'com_violencia', count(*) filter (where violencia <> '{}'), 'da_familia', count(*) filter (where origem = 'FAMILIA'),
                 'comunicacoes_ct', (select count(*) from iara.encaminhamentos e where e.ocorrencia_id in (select id from bx)))
               from bx),
    'aging', (select coalesce(jsonb_agg(jsonb_build_object('faixa', f, 'n', n) order by o), '[]') from (
                select case when dias_aberta <= 2 then 'até 2 dias' when dias_aberta <= 7 then '3 a 7 dias' when dias_aberta <= 15 then '8 a 15 dias' else 'mais de 15 dias' end f,
                       min(dias_aberta) o, count(*) n from bx where dias_aberta is not null group by 1) z),
    'por_tipo', (select coalesce(jsonb_agg(jsonb_build_object('tipo', tipo, 'n', n, 'encerradas', enc, 'tempo_medio_dias', tm) order by n desc), '[]') from (
                   select tipo, count(*) n, count(*) filter (where situacao = 'ENCERRADA') enc, round(avg(dias_solucao), 1) tm from bx group by 1) z),
    'por_violencia', (select coalesce(jsonb_agg(jsonb_build_object('violencia', tv, 'n', n, 'alunos', a, 'unidades', u) order by n desc), '[]') from (
                   select unnest(violencia) tv, count(*) n, count(distinct student_id) a, count(distinct unit_id) u from bx group by 1) z),
    'por_idade', (select coalesce(jsonb_agg(jsonb_build_object('faixa', f, 'n', n, 'violencia', nv) order by o), '[]') from (
                   select case when idade <= 3 then '0 a 3 anos' when idade <= 5 then '4 e 5 anos' when idade <= 8 then '6 a 8 anos' when idade <= 11 then '9 a 11 anos'
                               when idade <= 14 then '12 a 14 anos' else '15 anos ou mais' end f, min(idade) o, count(*) n, count(*) filter (where violencia <> '{}') nv
                   from bx where idade is not null group by 1) z),
    'por_serie', (select coalesce(jsonb_agg(jsonb_build_object('serie', serie, 'n', n, 'violencia', nv, 'por_mil', round(1000.0 * n / nullif(m, 0), 1)) order by code), '[]') from (
                   select t.serie, t.serie_code code, count(*) n, count(*) filter (where t.violencia <> '{}') nv,
                          (select count(*) from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
                           where e.status = 'ACTIVE' and gl.code = t.serie_code and (v_unit is null or e.unit_id = v_unit)) m
                   from bx t where t.serie is not null group by 1, 2) z),
    'turmas', (select coalesce(jsonb_agg(jsonb_build_object('class_id', class_id, 'turma', turma, 'unidade', unidade, 'n', n, 'violencia', nv, 'alunos', a,
                 'principal', principal) order by n desc), '[]') from (
                 select class_id, turma, unidade, count(*) n, count(*) filter (where violencia <> '{}') nv, count(distinct student_id) a,
                        mode() within group (order by tipo) principal
                 from bx where class_id is not null group by 1, 2, 3 order by count(*) desc limit 12) z),
    'unidades', case when v_rede then (select coalesce(jsonb_agg(jsonb_build_object('unit_id', unit_id, 'unidade', unidade, 'n', n, 'violencia', nv, 'abertas', ab,
                 'por_cem', round(100.0 * n / nullif(m, 0), 1)) order by n desc), '[]') from (
                 select t.unit_id, t.unidade, count(*) n, count(*) filter (where violencia <> '{}') nv, count(*) filter (where situacao <> 'ENCERRADA') ab,
                        (select count(*) from iara.enrollments e where e.status = 'ACTIVE' and e.unit_id = t.unit_id) m
                 from bx t group by 1, 2 order by count(*) desc limit 15) z) end,
    'por_mes', (select coalesce(jsonb_agg(jsonb_build_object('mes', mes, 'n', n, 'violencia', nv) order by mes), '[]') from (
                 select mes, count(*) n, count(*) filter (where violencia <> '{}') nv from bx group by 1) z),
    'reincidencia', (select jsonb_build_object('alunos_2', count(*) filter (where c >= 2), 'alunos_3', count(*) filter (where c >= 3))
                     from (select student_id, count(*) c from bx group by 1) z),
    'leitura', (select coalesce(jsonb_agg(jsonb_build_object('dim', dim, 'chave', chave, 'n', n, 'alunos', alunos, 'turmas', turmas, 'unidades', unidades,
                  'reincidentes', reinc_alunos, 'maior_turma', turma_top, 'maior_turma_pct', round(100.0 * top_turma / n),
                  'padrao', iara.ocorrencia_leitura(n, alunos, reinc::bigint, turmas, unidades, top_turma, v_rede)) order by dim desc, n desc), '[]')
                from g where chave not in ('PERTENCES', 'ATRASO_SAIDA', 'PEDAGOGICA', 'SAUDE', 'OUTRO')),
    -- focos: turma que concentra registros de convivência (4+ no período) e aluno com registros repetidos (3+)
    'focos', (select coalesce(jsonb_agg(f order by (f ->> 'padrao'), (f ->> 'n')::int desc), '[]') from (
                select jsonb_build_object('padrao', 'LOCALIZADO', 'class_id', class_id, 'turma', turma, 'unidade', unidade, 'n', count(*),
                         'violencia', count(*) filter (where violencia <> '{}'), 'principal', mode() within group (order by tipo)) f
                from bx where class_id is not null and tipo in ('COMPORTAMENTO', 'CONFLITO', 'BULLYING', 'ACIDENTE')
                group by class_id, turma, unidade having count(*) >= 4
                union all
                select jsonb_build_object('padrao', 'REINCIDENTE', 'student_id', student_id, 'turma', min(turma), 'unidade', min(unidade), 'n', count(*),
                         'violencia', count(*) filter (where violencia <> '{}'), 'principal', mode() within group (order by tipo))
                from bx group by student_id having count(*) >= 3
                order by 1 limit 30) z))
  into v;
  return v;
end $$;

-- 7. Demonstração: tratamento, instâncias, violência e padrões --------------------------------------------------------------------
create or replace function iara.demo_ocorrencias_padroes() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ana uuid := nullif(iara.setting('demo_student_ana'), '')::uuid;
  v_ana_unit integer := (select unit_id from iara.enrollments where student_id = v_ana and status = 'ACTIVE' limit 1);
  v_turma uuid;
  v_aluno uuid;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.encaminhamentos where is_demo and ocorrencia_id is not null;
  delete from iara.frequencia_tarefas t where t.is_demo and t.tipo = 'NOTIFICAR_CT' and not exists (select 1 from iara.encaminhamentos e where 'ct:' || e.id = t.chave);
  delete from iara.ocorrencias where is_demo and demo_padrao;
  delete from iara.ocorrencia_eventos e using iara.ocorrencias o where o.id = e.ocorrencia_id and o.is_demo and e.is_demo and e.tipo in ('COMUNICACAO', 'ENCAMINHADA_SEDUC', 'PEDIDO_REVISAO', 'DEVOLVIDA_UNIDADE');

  -- padrão amplo: intimidação entre 4º e 5º anos em várias unidades nas últimas semanas (pede formação e conscientização)
  insert into iara.ocorrencias (student_id, unit_id, class_id, origem, tipo, gravidade, ocorrida_em, local, descricao, providencias, situacao,
                                registrada_por_label, violencia, created_at, demo_padrao, is_demo)
  select x.student_id, x.unit_id, x.class_id, case when x.h % 3 = 0 then 'FAMILIA' else 'ESCOLA' end, 'BULLYING', 'MODERADA', x.quando,
         case when x.h % 4 = 0 then null else 'Pátio' end,
         (array['Colegas repetem apelidos ofensivos no recreio e excluem a criança das brincadeiras.',
                'Criaram um grupo de mensagens para zombar da criança e compartilharam uma foto dela.',
                'A criança relata que é empurrada na fila e chamada por apelidos todos os dias.',
                'Comentários ofensivos sobre a aparência da criança durante a aula de educação física.'])[1 + x.h % 4],
         case when x.h % 3 <> 0 then 'Conversa com as crianças envolvidas e com a coordenação; famílias avisadas.' end,
         case when x.quando < now() - interval '12 days' then 'ENCERRADA' when x.h % 2 = 0 then 'EM_ACOMPANHAMENTO' else 'ABERTA' end,
         case when x.h % 3 = 0 then 'Família (demonstração)' else 'Coordenação pedagógica (demonstração)' end,
         case when x.h % 4 = 1 then array['PSICOLOGICA', 'BULLYING', 'CYBERBULLYING'] when x.h % 7 = 0 then array['PSICOLOGICA', 'BULLYING', 'DISCRIMINACAO']
              else array['PSICOLOGICA', 'BULLYING'] end,
         x.quando, true, true
  from (select e.student_id, e.unit_id, e.class_id, abs(hashtext(e.student_id::text || 'pad')) h,
               ((iara.hoje_local() - 2 - abs(hashtext(e.student_id::text || 'pdq')) % 40) + time '10:30') at time zone 'America/Sao_Paulo' quando
        from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
        where e.status = 'ACTIVE' and gl.code in ('EF4', 'EF5') and e.student_id is distinct from v_ana
          and abs(hashtext(e.student_id::text || 'pad')) % 1000 < 6) x;

  -- foco localizado: brigas com agressão física numa turma de 3º ano (pede intervenção naquela turma)
  select c.id into v_turma from iara.classes c join iara.grade_levels gl on gl.id = c.grade_level_id
  where gl.code = 'EF3' and c.unit_id is distinct from v_ana_unit and (select count(*) from iara.enrollments e where e.class_id = c.id and e.status = 'ACTIVE') >= 20
  order by abs(hashtext(c.id::text)) limit 1;
  insert into iara.ocorrencias (student_id, unit_id, class_id, origem, tipo, gravidade, ocorrida_em, local, descricao, providencias, situacao,
                                registrada_por_label, violencia, created_at, demo_padrao, is_demo)
  select e.student_id, e.unit_id, e.class_id, 'ESCOLA', 'CONFLITO', case when k % 4 = 0 then 'GRAVE' else 'MODERADA' end,
         ((iara.hoje_local() - 1 - k * 3) + time '09:50') at time zone 'America/Sao_Paulo', 'Pátio',
         'Briga no intervalo com socos e empurrões entre colegas da turma.', 'Separação imediata, mediação e conversa com as famílias.',
         case when k > 4 then 'ENCERRADA' else 'EM_ACOMPANHAMENTO' end, 'Direção da unidade (demonstração)', array['FISICA'],
         ((iara.hoje_local() - 1 - k * 3) + time '09:50') at time zone 'America/Sao_Paulo', true, true
  from (select student_id, unit_id, class_id, row_number() over (order by abs(hashtext(student_id::text)))::int k
        from iara.enrollments where class_id = v_turma and status = 'ACTIVE') e
  where e.k <= 8;

  -- reincidente: um aluno com registros repetidos de comportamento agressivo (pede plano individual com a família)
  select e.student_id into v_aluno from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
  where e.status = 'ACTIVE' and gl.code = 'EF2' and e.unit_id is distinct from v_ana_unit and e.class_id is distinct from v_turma
  order by abs(hashtext(e.student_id::text || 'rei')) limit 1;
  insert into iara.ocorrencias (student_id, unit_id, class_id, origem, tipo, gravidade, ocorrida_em, local, descricao, providencias, situacao,
                                registrada_por_label, violencia, created_at, demo_padrao, is_demo)
  select e.student_id, e.unit_id, e.class_id, 'ESCOLA', 'COMPORTAMENTO', 'MODERADA', ((iara.hoje_local() - 2 - k * 9) + time '14:10') at time zone 'America/Sao_Paulo',
         'Sala de aula', 'Agrediu verbalmente colegas e a professora e jogou o material no chão.', 'Retirado da sala para acolhimento; família chamada para conversar.',
         case when k > 1 then 'ENCERRADA' else 'EM_ACOMPANHAMENTO' end, 'Professora da turma (demonstração)', array['PSICOLOGICA'],
         ((iara.hoje_local() - 2 - k * 9) + time '14:10') at time zone 'America/Sao_Paulo', true, true
  from iara.enrollments e cross join generate_series(0, 3) k where e.student_id = v_aluno and e.status = 'ACTIVE';

  -- classificação de violência nos registros gerais (determinística)
  update iara.ocorrencias set violencia = case
      when tipo = 'BULLYING' then case when abs(hashtext(id::text)) % 7 = 0 then array['PSICOLOGICA', 'BULLYING', 'CYBERBULLYING'] else array['PSICOLOGICA', 'BULLYING'] end
      when tipo = 'CONFLITO' and abs(hashtext(id::text)) % 10 < 6 then array['FISICA']
      when tipo = 'COMPORTAMENTO' and abs(hashtext(id::text)) % 100 < 8 then array['PSICOLOGICA']
      else '{}' end
  where is_demo and not demo_padrao;

  -- prazos, solução comunicada nas encerradas e eventos: tratativa da escola fica interna; a solução e as comunicações ficam visíveis
  update iara.ocorrencias o set prazo = iara.ocorrencia_prazo(o.gravidade, 'UNIDADE', o.ocorrida_em), instancia = 'UNIDADE', pedido_familia = false,
         encaminhada_seduc_em = null, encaminhada_por_label = null, motivo_seduc = null, alterada_em = null, sigilosa = false,
         solucao = case when o.situacao = 'ENCERRADA' then coalesce(
                     (select e.texto from iara.ocorrencia_eventos e where e.ocorrencia_id = o.id and e.origem = 'ESCOLA' and e.is_demo order by e.created_at desc limit 1),
                     o.providencias, case when o.tipo = 'ELOGIO' then 'Registro de reconhecimento.' else 'Situação resolvida pela escola; seguimos acompanhando.' end) end,
         solucao_em = case when o.situacao = 'ENCERRADA' then least(o.ocorrida_em + make_interval(hours => 20 + abs(hashtext(o.id::text)) % 70), now() - interval '1 hour') end,
         solucao_por_label = case when o.situacao = 'ENCERRADA' then 'Direção da unidade (demonstração)' end
  where o.is_demo;
  update iara.ocorrencias set comunicada_em = solucao_em where is_demo and situacao = 'ENCERRADA';
  update iara.ocorrencia_eventos e set tipo = case when o.situacao = 'ENCERRADA' then 'SOLUCAO' else 'NOTA_INTERNA' end, interno = o.situacao <> 'ENCERRADA'
  from iara.ocorrencias o where o.id = e.ocorrencia_id and o.is_demo and e.is_demo and e.origem = 'ESCOLA' and e.tipo in ('COMENTARIO', 'NOTA_INTERNA', 'SOLUCAO');
  -- recebimento automático para o que a família relatou
  insert into iara.ocorrencia_eventos (ocorrencia_id, origem, tipo, interno, texto, autor_label, created_at, is_demo)
  select o.id, 'ESCOLA', 'COMUNICACAO', false, iara.ocorrencia_render((iara.ocorrencia_modelo_vigente('RECEBIMENTO', o.tipo)).texto, o), 'IARA (resposta automática)',
         o.ocorrida_em + interval '2 minutes', true
  from iara.ocorrencias o where o.is_demo and o.origem = 'FAMILIA';
  -- 2ª instância: parte das moderadas/graves vai à Secretaria (pela unidade ou a pedido da família)
  update iara.ocorrencias o set instancia = 'SECRETARIA', situacao = 'EM_ACOMPANHAMENTO', encaminhada_seduc_em = least(o.ocorrida_em + interval '2 days', now() - interval '2 hours'),
         encaminhada_por_label = case when abs(hashtext(o.id::text)) % 3 = 0 then 'Família' else 'Direção da unidade (demonstração)' end,
         pedido_familia = abs(hashtext(o.id::text)) % 3 = 0,
         motivo_seduc = case when abs(hashtext(o.id::text)) % 3 = 0 then 'A situação continua acontecendo e não fomos chamados para conversar.'
                             else 'Situação recorrente na turma; a unidade pede o apoio da equipe multiprofissional da SEDUC.' end,
         prazo = iara.ocorrencia_prazo(o.gravidade, 'SECRETARIA', least(o.ocorrida_em + interval '2 days', now() - interval '2 hours'))
  where o.is_demo and o.situacao <> 'ENCERRADA' and o.gravidade <> 'LEVE' and o.student_id is distinct from v_ana and abs(hashtext(o.id::text || 'seduc')) % 100 < 22;
  insert into iara.ocorrencia_eventos (ocorrencia_id, origem, tipo, interno, texto, autor_label, created_at, is_demo)
  select o.id, case when o.pedido_familia then 'FAMILIA' else 'ESCOLA' end, case when o.pedido_familia then 'PEDIDO_REVISAO' else 'ENCAMINHADA_SEDUC' end,
         not o.pedido_familia, case when o.pedido_familia then 'Pedido de análise pela Secretaria: ' else 'Encaminhada à Secretaria (2ª instância): ' end || o.motivo_seduc,
         case when o.pedido_familia then 'Família (demonstração)' else o.encaminhada_por_label end, o.encaminhada_seduc_em, true
  from iara.ocorrencias o where o.is_demo and o.instancia = 'SECRETARIA';
  insert into iara.ocorrencia_eventos (ocorrencia_id, origem, tipo, interno, texto, autor_label, created_at, is_demo)
  select o.id, 'ESCOLA', 'COMUNICACAO', false, iara.ocorrencia_render((iara.ocorrencia_modelo_vigente('ENCAMINHADA_SEDUC', o.tipo)).texto, o),
         'IARA (resposta automática)', o.encaminhada_seduc_em + interval '1 minute', true
  from iara.ocorrencias o where o.is_demo and o.instancia = 'SECRETARIA';
  -- uma comunicação ao Conselho Tutelar preparada a partir de ocorrência grave (aguardando a aprovação da direção)
  perform iara.ocorrencia_comunicar_ct(o.id, 'IARA (regra automática)')
  from iara.ocorrencias o where o.is_demo and o.demo_padrao and o.gravidade = 'GRAVE' and o.situacao <> 'ENCERRADA';
  update iara.ocorrencia_eventos e set created_at = o.ocorrida_em + interval '30 minutes', is_demo = true
  from iara.ocorrencias o where o.id = e.ocorrencia_id and o.is_demo and e.tipo = 'NOTA_INTERNA' and e.texto like 'Comunicação ao Conselho Tutelar preparada%';
  update iara.encaminhamentos e set created_at = o.ocorrida_em + interval '30 minutes', is_demo = true
  from iara.ocorrencias o where o.id = e.ocorrencia_id and o.is_demo;
  update iara.frequencia_tarefas t set created_at = e.created_at, is_demo = true from iara.encaminhamentos e where t.chave = 'ct:' || e.id and e.is_demo and e.ocorrencia_id is not null;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('ocorrencias', (select count(*) from iara.ocorrencias where is_demo), 'padroes', (select count(*) from iara.ocorrencias where is_demo and demo_padrao),
    'segunda_instancia', (select count(*) from iara.ocorrencias where is_demo and instancia = 'SECRETARIA'),
    'violencia', (select count(*) from iara.ocorrencias where is_demo and violencia <> '{}'),
    'ct', (select count(*) from iara.encaminhamentos where is_demo and ocorrencia_id is not null));
end $$;

-- limpeza do que foi feito ao vivo: modelos alterados voltam à versão anterior; ocorrências da demonstração mexidas ao vivo são refeitas
create or replace function iara.demo_purge_ocorrencias(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  d timestamptz := coalesce(p_desde, '-infinity'::timestamptz);
  n integer;
  v jsonb := '{}'::jsonb;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.ocorrencia_modelos where alterado_em >= d and alterado_por_label not like 'SEDUC (modelo inicial%';
  get diagnostics n = row_count; v := v || jsonb_build_object('modelos', n);
  delete from iara.notifications where created_at >= d and event_type = 'OCORRENCIA';
  if exists (select 1 from iara.ocorrencias where is_demo and alterada_em >= d) then
    perform iara.demo_gerar_ocorrencias();
    v := v || jsonb_build_object('refeitas', iara.demo_ocorrencias_padroes());
  end if;
  perform set_config('iara.skip_audit', 'off', true);
  return v;
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
                               'ocorrencias', iara.demo_purge_ocorrencias(null), 'arquivos', iara.demo_limpar_arquivos_vivos(null));
  return jsonb_build_object('ok', true, 'resultado', r, 'situacao', api.demo_apresentacao_situacao('{}'::jsonb));
end $$;

revoke all on function iara.demo_ocorrencias_padroes(), iara.demo_purge_ocorrencias(timestamptz), iara.ocorrencia_comunicar_ct(uuid, text),
  iara.ocorrencia_notificar(iara.ocorrencias, text, text) from public;

-- classificação dos dados (inventário LGPD)
insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('ocorrencias', 'violencia', 'SENSIVEL', 'proteção da criança (Lei 13.431/2017)', 'tratamento e comunicação obrigatória', 'escola e SEDUC; nunca exibido à família'),
  ('ocorrencias', 'motivo_seduc', 'SENSIVEL', 'proteção da criança', '2ª instância', 'unidade e SEDUC'),
  ('ocorrencias', 'solucao', 'PESSOAL', 'resposta à família', 'tratamento da ocorrência', 'família do aluno, unidade e SEDUC'),
  ('ocorrencias', 'solucao_por_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('ocorrencias', 'encaminhada_por_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('ocorrencias', 'sigilosa', 'INTERNO', 'proteção da criança', 'oculta o registro da família', null),
  ('ocorrencia_eventos', 'tipo', 'INTERNO', 'operação', 'linha do tempo', null),
  ('ocorrencia_eventos', 'interno', 'INTERNO', 'operação', 'separa tratativa interna do que a família vê', null),
  ('ocorrencia_modelos', 'texto', 'PUBLICO', 'modelo de resposta (sem dado pessoal)', 'comunicação com a família', null),
  ('ocorrencia_modelos', 'alterado_por_label', 'PESSOAL', 'identificação', 'auditoria', null)
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

select iara.demo_ocorrencias_padroes() where iara.demo_mode();

commit;
