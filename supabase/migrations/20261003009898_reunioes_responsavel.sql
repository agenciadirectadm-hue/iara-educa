-- IARA Educa — 098.98 · Registro de reunião com o responsável, para assuntos que podem ser pauta do Conselho Tutelar, da Defensoria e do Ministério Público.
-- Pedido de Rob (05/11/2026): na ficha do aluno, resumo do assunto, soluções propostas, posição da escola e posição do responsável.
-- O registro vai a professor, direção, secretaria escolar, secretário e superintendência e fica à disposição do controle externo.
-- O responsável valida ou se manifesta. Sem resposta: avisos em D+1, D+2 e D+3, e depois a preparação do envio aos três órgãos.
-- Proteção da criança: quando enviar ao responsável aumenta o risco, a escola registra sem envio, com justificativa; nesse caso não há aviso nenhum.
-- O registro fica no prontuário do aluno e do responsável, com visão de professor para cima (professor só da própria turma).
-- Assunto de proteção, registro sem envio, órgão indicado ou prazo vencido geram uma ocorrência sigilosa ao Secretário Municipal, para envio às autoridades.
-- O envio aos órgãos é confirmado por uma pessoa (Secretário ou Superintendência), com o protocolo, como nas comunicações legais da Busca ativa.
-- Os textos dos avisos ficam em tabela, para a revisão jurídica não depender de mudança no código.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

insert into iara.permissions (code, description, is_sensitive) values
  ('reunioes.read', 'Ler registros de reunião com o responsável', true),
  ('reunioes.write', 'Registrar reunião com o responsável', true),
  ('reunioes.enviar', 'Confirmar o envio do registro de reunião aos órgãos externos', true)
on conflict (code) do nothing;
insert into iara.role_permissions (role_code, permission_code) values
  ('PROFESSOR', 'reunioes.read'), ('PROFESSOR', 'reunioes.write'), ('PROFESSOR_AEE', 'reunioes.read'),
  ('DIRETOR_UNIDADE', 'reunioes.read'), ('DIRETOR_UNIDADE', 'reunioes.write'),
  ('SECRETARIA_ESCOLAR', 'reunioes.read'), ('SECRETARIA_ESCOLAR', 'reunioes.write'),
  ('GERENCIA_EI', 'reunioes.read'), ('PREFEITO', 'reunioes.read'),
  ('SECRETARIO', 'reunioes.read'), ('SECRETARIO', 'reunioes.enviar'),
  ('SUPERINTENDENCIA', 'reunioes.read'), ('SUPERINTENDENCIA', 'reunioes.enviar')
on conflict do nothing;
-- o envio às autoridades é do(a) Secretário(a) e da Superintendência
delete from iara.role_permissions where role_code = 'DIRETOR_UNIDADE' and permission_code = 'reunioes.enviar';

create table if not exists iara.reunioes_responsavel (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references iara.students(id) on delete cascade,
  unit_id integer not null,
  class_id uuid,
  guardian_id uuid not null references iara.guardians(id) on delete cascade,
  ocorrencia_id uuid references iara.ocorrencias(id) on delete set null,
  realizada_em timestamptz not null,
  participantes text,
  tema text not null check (tema in ('VIOLENCIA_DOMESTICA', 'VIOLENCIA_SEXUAL', 'NEGLIGENCIA', 'TRABALHO_INFANTIL', 'AUTOLESAO',
                                      'INFREQUENCIA', 'DIREITO_EDUCACAO', 'CONFLITO_FAMILIAR', 'OUTRO')),
  orgaos text[] not null default '{}',
  resumo text not null,
  solucoes text not null,
  posicao_escola text not null,
  posicao_responsavel text not null,
  envia_responsavel boolean not null,
  motivo_sem_envio text,
  situacao text not null check (situacao in ('AGUARDANDO', 'ACEITA', 'MANIFESTADA', 'PRAZO_VENCIDO', 'SEM_ENVIO')),
  enviada_em timestamptz,
  ultimo_aviso smallint not null default -1,
  resposta_em timestamptz,
  resposta_canal text,
  manifestacao text,
  registrada_por_label text,
  created_at timestamptz not null default now(),
  is_demo boolean not null default false
);
alter table iara.reunioes_responsavel add column if not exists ocorrencia_seduc_id uuid references iara.ocorrencias(id) on delete set null;
create index if not exists reunioes_responsavel_guardian_idx on iara.reunioes_responsavel (guardian_id, realizada_em desc);
create index if not exists reunioes_responsavel_aluno_idx on iara.reunioes_responsavel (student_id, realizada_em desc);
create index if not exists reunioes_responsavel_unidade_idx on iara.reunioes_responsavel (unit_id, realizada_em desc);
create index if not exists reunioes_responsavel_situacao_idx on iara.reunioes_responsavel (situacao) where situacao = 'AGUARDANDO';

create table if not exists iara.reuniao_destinos (
  reuniao_id uuid not null references iara.reunioes_responsavel(id) on delete cascade,
  papel text not null check (papel in ('PROFESSOR', 'DIRETOR_UNIDADE', 'SECRETARIA_ESCOLAR', 'SECRETARIO', 'SUPERINTENDENCIA')),
  lido_em timestamptz,
  lido_por_label text,
  primary key (reuniao_id, papel)
);

create table if not exists iara.reuniao_eventos (
  id uuid primary key default gen_random_uuid(),
  reuniao_id uuid not null references iara.reunioes_responsavel(id) on delete cascade,
  tipo text not null check (tipo in ('REGISTRO', 'AVISO', 'ACEITE', 'MANIFESTACAO', 'ORGAOS_PREPARADOS', 'ENVIO_ORGAO', 'ORGAOS_CANCELADOS', 'CONSULTA_EXTERNA')),
  dia smallint,
  titulo text,
  texto text not null,
  em timestamptz not null default now(),
  autor_label text
);
create unique index if not exists reuniao_eventos_aviso_uq on iara.reuniao_eventos (reuniao_id, dia) where tipo = 'AVISO';
create index if not exists reuniao_eventos_reuniao_idx on iara.reuniao_eventos (reuniao_id, em);

create table if not exists iara.reuniao_envios_orgaos (
  id uuid primary key default gen_random_uuid(),
  reuniao_id uuid not null references iara.reunioes_responsavel(id) on delete cascade,
  orgao text not null check (orgao in ('CONSELHO_TUTELAR', 'DEFENSORIA', 'MINISTERIO_PUBLICO')),
  motivo text not null check (motivo in ('PROTECAO', 'INDICADO', 'SEM_VALIDACAO')),
  situacao text not null default 'AGUARDANDO_ENVIO' check (situacao in ('AGUARDANDO_ENVIO', 'ENVIADO', 'CANCELADO')),
  preparado_em timestamptz not null default now(),
  enviado_em timestamptz,
  enviado_por_label text,
  protocolo text,
  unique (reuniao_id, orgao)
);

create table if not exists iara.reuniao_avisos_modelo (
  dia smallint primary key check (dia between 0 and 3),
  titulo text not null,
  texto text not null
);
insert into iara.reuniao_avisos_modelo (dia, titulo, texto) values
  (0, 'Registro de reunião para sua validação',
   '{responsavel}, a {unidade} registrou a reunião de {data} sobre {aluno}. Leia o resumo e responda: confirme o registro ou faça a sua manifestação. Você responde pelo portal da família ou por aqui, com a IARA.'),
  (1, 'O registro da reunião segue disponível',
   '{responsavel}, o registro da reunião de {data} sobre {aluno} continua disponível no portal da família e por aqui, com a IARA. A sua validação é importante: ela confirma que o que foi conversado com a escola está registrado corretamente e garante o seu direito de acrescentar a sua posição.'),
  (2, 'Atenção: validação pendente',
   '{responsavel}, o registro da reunião de {data} sobre {aluno} ainda não foi validado. A validação é necessária para o acompanhamento da criança. Se ela não ocorrer, o registro será enviado ao Conselho Tutelar, para as providências cabíveis. Responda o quanto antes: você pode confirmar ou se manifestar.'),
  (3, 'ÚLTIMO AVISO antes do envio aos órgãos de proteção',
   '{responsavel}, este é o ÚLTIMO AVISO. O registro da reunião de {data} sobre {aluno} segue sem validação. Os pais e responsáveis têm o dever legal de zelar pela criança e acompanhar a sua educação (Constituição Federal, arts. 205 e 227; ECA, arts. 4º e 22). O descumprimento desses deveres pode resultar nas medidas e na multa previstas nos arts. 129 e 249 do ECA. Sem resposta até o fim de hoje, o registro será enviado ao Conselho Tutelar, à Defensoria Pública e ao Ministério Público, para as providências legais. Responder não significa concordar: você pode registrar a sua manifestação.')
on conflict (dia) do nothing;

alter table iara.reunioes_responsavel enable row level security;
alter table iara.reuniao_destinos enable row level security;
alter table iara.reuniao_eventos enable row level security;
alter table iara.reuniao_envios_orgaos enable row level security;
alter table iara.reuniao_avisos_modelo enable row level security;

create or replace function iara.reuniao_codigo(p uuid) returns text
language sql immutable as $$ select 'R-' || upper(substr(md5('iara-reuniao:' || p::text), 1, 6)) $$;

create or replace function iara.reuniao_tema_rotulo(p text) returns text
language sql immutable as $$
  select case p
    when 'VIOLENCIA_DOMESTICA' then 'Violência doméstica'
    when 'VIOLENCIA_SEXUAL' then 'Suspeita de violência sexual'
    when 'NEGLIGENCIA' then 'Negligência ou abandono'
    when 'TRABALHO_INFANTIL' then 'Trabalho infantil'
    when 'AUTOLESAO' then 'Risco de autolesão'
    when 'INFREQUENCIA' then 'Infrequência ou abandono escolar'
    when 'DIREITO_EDUCACAO' then 'Direito à educação'
    when 'CONFLITO_FAMILIAR' then 'Conflito familiar ou de guarda'
    else 'Outro assunto' end
$$;

-- assuntos em que a comunicação ao Conselho Tutelar não espera os avisos (ECA, art. 13)
create or replace function iara.reuniao_tema_protecao(p text) returns boolean
language sql immutable as $$ select p in ('VIOLENCIA_DOMESTICA', 'VIOLENCIA_SEXUAL', 'NEGLIGENCIA', 'TRABALHO_INFANTIL', 'AUTOLESAO') $$;

create or replace function iara.reuniao_acesso(r iara.reunioes_responsavel) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select iara.has_perm('reunioes.read') and case
    when iara.my_role() in ('PROFESSOR', 'PROFESSOR_AEE') then r.class_id = any (iara.minhas_turmas())
      or exists (select 1 from iara.enrollments e where e.student_id = r.student_id and e.status = 'ACTIVE' and e.class_id = any (iara.minhas_turmas()))
    when iara.my_role() = 'PREFEITO' or iara.my_scope() = 'NETWORK' then true
    when iara.my_scope() = 'UNIT' then r.unit_id = iara.my_unit()
    else false end
$$;

create or replace function iara.reuniao_json(r iara.reunioes_responsavel, p_completo boolean default false) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object(
    'id', r.id, 'codigo', iara.reuniao_codigo(r.id), 'student_id', r.student_id, 'aluno', s.full_name, 'unit_id', r.unit_id, 'unidade', u.short_name,
    'tema', r.tema, 'tema_rotulo', iara.reuniao_tema_rotulo(r.tema), 'realizada_em', r.realizada_em, 'situacao', r.situacao, 'ultimo_aviso', r.ultimo_aviso,
    'envia_responsavel', r.envia_responsavel, 'orgaos', to_jsonb(r.orgaos), 'responsavel', g.full_name, 'registrada_por', r.registrada_por_label,
    'envios_pendentes', (select count(*) from iara.reuniao_envios_orgaos e where e.reuniao_id = r.id and e.situacao = 'AGUARDANDO_ENVIO'),
    'nao_lida', coalesce((select d.lido_em is null from iara.reuniao_destinos d where d.reuniao_id = r.id and d.papel = iara.my_role()), false),
    'is_demo', r.is_demo)
  || case when p_completo then jsonb_build_object(
    'participantes', r.participantes, 'resumo', r.resumo, 'solucoes', r.solucoes, 'posicao_escola', r.posicao_escola, 'posicao_responsavel', r.posicao_responsavel,
    'motivo_sem_envio', r.motivo_sem_envio, 'enviada_em', r.enviada_em, 'resposta_em', r.resposta_em, 'resposta_canal', r.resposta_canal, 'manifestacao', r.manifestacao,
    'ocorrencia_id', r.ocorrencia_id, 'ocorrencia_seduc_id', r.ocorrencia_seduc_id, 'parentesco', (select sg.relationship from iara.student_guardians sg where sg.student_id = r.student_id and sg.guardian_id = r.guardian_id limit 1),
    'destinos', (select coalesce(jsonb_agg(jsonb_build_object('papel', d.papel, 'lido_em', d.lido_em, 'lido_por', d.lido_por_label)
                   order by array_position(array['PROFESSOR', 'DIRETOR_UNIDADE', 'SECRETARIA_ESCOLAR', 'SECRETARIO', 'SUPERINTENDENCIA'], d.papel)), '[]')
                 from iara.reuniao_destinos d where d.reuniao_id = r.id),
    'eventos', (select coalesce(jsonb_agg(jsonb_build_object('tipo', e.tipo, 'dia', e.dia, 'titulo', e.titulo, 'texto', e.texto, 'em', e.em, 'autor', e.autor_label) order by e.em), '[]')
                from iara.reuniao_eventos e where e.reuniao_id = r.id),
    'envios', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'orgao', e.orgao, 'motivo', e.motivo, 'situacao', e.situacao, 'preparado_em', e.preparado_em,
                 'enviado_em', e.enviado_em, 'enviado_por', e.enviado_por_label, 'protocolo', e.protocolo)
                 order by array_position(array['CONSELHO_TUTELAR', 'DEFENSORIA', 'MINISTERIO_PUBLICO'], e.orgao)), '[]')
               from iara.reuniao_envios_orgaos e where e.reuniao_id = r.id)
  ) else '{}'::jsonb end
  from iara.students s left join iara.education_units u on u.id = r.unit_id left join iara.guardians g on g.id = r.guardian_id
  where s.id = r.student_id
$$;

-- texto do aviso do dia, com os dados da reunião
create or replace function iara.reuniao_aviso_texto(r iara.reunioes_responsavel, p_dia integer) returns text
language sql stable security definer set search_path = iara, public
as $$
  select replace(replace(replace(replace(m.texto,
    '{responsavel}', (select split_part(g.full_name, ' ', 1) from iara.guardians g where g.id = r.guardian_id)),
    '{aluno}', (select split_part(s.full_name, ' ', 1) from iara.students s where s.id = r.student_id)),
    '{unidade}', (select u.short_name from iara.education_units u where u.id = r.unit_id)),
    '{data}', to_char(r.realizada_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'))
  from iara.reuniao_avisos_modelo m where m.dia = p_dia
$$;

-- grava o aviso na linha do tempo e entrega ao responsável: portal e, quando há canal, WhatsApp (gatilho de saída das notificações)
create or replace function iara.reuniao_enviar_aviso(p_id uuid, p_dia integer, p_canal text default 'WHATSAPP') returns void
language plpgsql security definer set search_path = iara, public
as $$
declare
  r iara.reunioes_responsavel;
  v_texto text;
  v_titulo text;
begin
  select * into r from iara.reunioes_responsavel where id = p_id;
  v_texto := iara.reuniao_aviso_texto(r, p_dia);
  select titulo into v_titulo from iara.reuniao_avisos_modelo where dia = p_dia;
  insert into iara.reuniao_eventos (reuniao_id, tipo, dia, titulo, texto, autor_label)
  values (r.id, 'AVISO', p_dia, v_titulo, v_texto, 'IARA (aviso automático)')
  on conflict (reuniao_id, dia) where tipo = 'AVISO' do nothing;
  if not found then return; end if;
  insert into iara.notifications (tenant_id, guardian_id, student_id, channel, event_type, title, body, status)
  values (1, r.guardian_id, r.student_id, p_canal, 'REUNIAO_AVISO', v_titulo, v_texto, 'ENVIADA');
  update iara.reunioes_responsavel set ultimo_aviso = greatest(ultimo_aviso, p_dia::smallint) where id = r.id;
end $$;

create or replace function iara.reuniao_preparar_orgaos(p_id uuid, p_orgaos text[], p_motivo text) returns void
language plpgsql security definer set search_path = iara, public
as $$
begin
  insert into iara.reuniao_envios_orgaos (reuniao_id, orgao, motivo)
  select p_id, o, p_motivo from unnest(p_orgaos) o
  on conflict (reuniao_id, orgao) do update set situacao = 'AGUARDANDO_ENVIO', motivo = excluded.motivo, preparado_em = now()
    where iara.reuniao_envios_orgaos.situacao = 'CANCELADO';
end $$;

-- Ocorrência sigilosa ao Secretário Municipal, na 2ª instância, para envio às autoridades competentes. Entra direto, sem passar por
-- api.ocorrencia_registrar, para não duplicar a comunicação de Conselho Tutelar da Busca ativa. O prazo é o dia seguinte: o assunto é urgente.
create or replace function iara.reuniao_gerar_ocorrencia_seduc(p_id uuid, p_motivo text, p_autor text default null) returns uuid
language plpgsql security definer set search_path = iara, public
as $$
declare
  r iara.reunioes_responsavel;
  v_autor text;
  v_oc uuid;
begin
  select * into r from iara.reunioes_responsavel where id = p_id;
  if r.id is null then return null; end if;
  if r.ocorrencia_seduc_id is not null then return r.ocorrencia_seduc_id; end if;
  v_autor := coalesce(p_autor, iara.my_label(), 'IARA (regra automática)');
  insert into iara.ocorrencias (student_id, unit_id, class_id, origem, tipo, gravidade, ocorrida_em, descricao, providencias, situacao, registrada_por_label,
                                violencia, sigilosa, instancia, prazo, encaminhada_seduc_em, encaminhada_por_label, motivo_seduc, is_demo)
  values (r.student_id, r.unit_id, r.class_id, 'ESCOLA', 'OUTRO', 'GRAVE', r.realizada_em,
          format('Registro de reunião %s. Assunto: %s. %s', iara.reuniao_codigo(r.id), iara.reuniao_tema_rotulo(r.tema), left(r.resumo, 1500)),
          'Enviar às autoridades competentes e registrar o protocolo no registro de reunião.', 'EM_ACOMPANHAMENTO', v_autor,
          case r.tema when 'VIOLENCIA_SEXUAL' then array['SEXUAL'] when 'AUTOLESAO' then array['AUTOLESAO'] else '{}'::text[] end,
          true, 'SECRETARIA', iara.hoje_local() + 1, now(), v_autor, p_motivo, r.is_demo)
  returning id into v_oc;
  insert into iara.ocorrencia_eventos (ocorrencia_id, origem, tipo, interno, texto, autor_label, is_demo)
  values (v_oc, 'ESCOLA', 'ENCAMINHADA_SEDUC', true, format('Gerada pelo registro de reunião %s, para envio às autoridades competentes: %s', iara.reuniao_codigo(r.id), p_motivo), v_autor, r.is_demo);
  update iara.reunioes_responsavel set ocorrencia_seduc_id = v_oc where id = r.id;
  return v_oc;
end $$;

-- A régua de uma reunião: D+1, D+2 e D+3 em dias corridos; no dia seguinte ao último aviso, prepara o envio aos três órgãos.
-- p_forcar: entrega fora do horário (usado pelo avanço de dia da apresentação).
create or replace function iara.reuniao_processar(p_id uuid, p_forcar boolean default false) returns text
language plpgsql security definer set search_path = iara, public
as $$
declare
  r iara.reunioes_responsavel;
  v_hoje date := iara.hoje_local();
  v_dias integer;
  v_prox integer;
  v_hora integer := extract(hour from iara.agora_local());
  v_ult_data date;
begin
  select * into r from iara.reunioes_responsavel where id = p_id for update;
  if r.id is null or r.situacao <> 'AGUARDANDO' or not r.envia_responsavel or r.enviada_em is null then return 'sem_acao'; end if;
  v_dias := v_hoje - (r.enviada_em at time zone 'America/Sao_Paulo')::date;
  if v_dias < 1 then return 'sem_acao'; end if;
  v_prox := least(v_dias, 3);
  if v_prox > r.ultimo_aviso then
    if not p_forcar and (v_hora < 8 or v_hora >= 19) then return 'fora_do_horario'; end if;
    perform iara.reuniao_enviar_aviso(r.id, v_prox, case when r.is_demo then 'PORTAL' else 'WHATSAPP' end);
    return 'aviso_' || v_prox;
  end if;
  select (max(em) at time zone 'America/Sao_Paulo')::date into v_ult_data from iara.reuniao_eventos where reuniao_id = r.id and tipo = 'AVISO' and dia = 3;
  if v_dias >= 4 and r.ultimo_aviso >= 3 and v_ult_data < v_hoje then
    update iara.reunioes_responsavel set situacao = 'PRAZO_VENCIDO' where id = r.id;
    perform iara.reuniao_preparar_orgaos(r.id, array['CONSELHO_TUTELAR', 'DEFENSORIA', 'MINISTERIO_PUBLICO'], 'SEM_VALIDACAO');
    insert into iara.reuniao_eventos (reuniao_id, tipo, texto, autor_label)
    values (r.id, 'ORGAOS_PREPARADOS', 'Sem validação depois do último aviso. Envio preparado ao Conselho Tutelar, à Defensoria Pública e ao Ministério Público: aguarda a confirmação do(a) Secretário(a) Municipal.', 'IARA (regra automática)');
    perform iara.reuniao_gerar_ocorrencia_seduc(r.id, 'Responsável não validou o registro depois do último aviso.', 'IARA (regra automática)');
    perform iara.audit_event('REUNIAO_PRAZO_VENCIDO', 'student', r.student_id::text, r.unit_id, 'Registro de reunião sem validação: envio aos órgãos externos preparado.');
    return 'prazo_vencido';
  end if;
  return 'sem_acao';
end $$;

create or replace function iara.reunioes_rotina() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  x record;
  v jsonb := '{}'::jsonb;
  v_res text;
begin
  for x in select id from iara.reunioes_responsavel where situacao = 'AGUARDANDO' and envia_responsavel and not is_demo loop
    v_res := iara.reuniao_processar(x.id);
    v := v || jsonb_build_object(v_res, coalesce((v ->> v_res)::int, 0) + 1);
  end loop;
  return v;
end $$;

-- ===================================================================== Escola e Secretaria
create or replace function api.reuniao_registrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_guardian uuid := nullif(p ->> 'guardian_id', '')::uuid;
  v_tema text := coalesce(nullif(p ->> 'tema', ''), 'OUTRO');
  v_orgaos text[] := coalesce((select array_agg(distinct x) from jsonb_array_elements_text(coalesce(p -> 'orgaos', '[]')) x), '{}');
  v_resumo text := btrim(coalesce(p ->> 'resumo', ''));
  v_solucoes text := btrim(coalesce(p ->> 'solucoes', ''));
  v_escola text := btrim(coalesce(p ->> 'posicao_escola', ''));
  v_resp text := btrim(coalesce(p ->> 'posicao_responsavel', ''));
  v_motivo text := nullif(btrim(coalesce(p ->> 'motivo_sem_envio', '')), '');
  v_envia boolean := (p ->> 'envia_responsavel')::boolean;
  v_quando timestamptz := coalesce(nullif(p ->> 'realizada_em', '')::timestamptz, now());
  v_ocorrencia uuid := nullif(p ->> 'ocorrencia_id', '')::uuid;
  e record;
  r iara.reunioes_responsavel;
begin
  if not iara.aluno_acesso(v_student, 'reunioes.write') then
    raise exception 'Sem permissão para registrar reunião deste aluno.' using errcode = '42501';
  end if;
  select en.unit_id, en.class_id into e from iara.enrollments en where en.student_id = v_student and en.status = 'ACTIVE' limit 1;
  if e.unit_id is null then raise exception 'O aluno não tem matrícula ativa.' using errcode = '22023'; end if;
  if not exists (select 1 from iara.student_guardians sg where sg.student_id = v_student and sg.guardian_id = v_guardian and sg.end_date is null) then
    raise exception 'Escolha um responsável vinculado a este aluno.' using errcode = '22023';
  end if;
  if iara.reuniao_tema_rotulo(v_tema) = 'Outro assunto' and v_tema <> 'OUTRO' then raise exception 'Assunto inválido.' using errcode = '22023'; end if;
  if not v_orgaos <@ array['CONSELHO_TUTELAR', 'DEFENSORIA', 'MINISTERIO_PUBLICO']::text[] then raise exception 'Órgão inválido.' using errcode = '22023'; end if;
  if v_quando > now() + interval '5 minutes' then raise exception 'A data da reunião não pode estar no futuro.' using errcode = '22023'; end if;
  if length(v_resumo) not between 20 and 4000 then raise exception 'Resuma o assunto tratado (de 20 a 4.000 caracteres).' using errcode = '22023'; end if;
  if length(v_solucoes) not between 10 and 4000 then raise exception 'Informe as soluções propostas (de 10 a 4.000 caracteres).' using errcode = '22023'; end if;
  if length(v_escola) not between 10 and 4000 then raise exception 'Informe a posição da escola (de 10 a 4.000 caracteres).' using errcode = '22023'; end if;
  if length(v_resp) not between 5 and 4000 then raise exception 'Informe a posição do responsável (de 5 a 4.000 caracteres).' using errcode = '22023'; end if;
  if v_ocorrencia is not null and not exists (select 1 from iara.ocorrencias o where o.id = v_ocorrencia and o.student_id = v_student) then
    raise exception 'Ocorrência não encontrada para este aluno.' using errcode = '22023';
  end if;

  -- suspeita de violência sexual: sigilosa, como nas ocorrências; nunca vai à família
  if v_tema = 'VIOLENCIA_SEXUAL' then
    v_envia := false;
    v_motivo := coalesce(v_motivo, 'Suspeita de violência sexual: registro sigiloso, não enviado à família.');
  end if;
  if v_envia is null then raise exception 'Diga se o registro pode ser enviado ao responsável.' using errcode = '22023'; end if;
  if not v_envia and length(coalesce(v_motivo, '')) < 10 then
    raise exception 'Explique por que o registro não será enviado ao responsável (mínimo de 10 caracteres).' using errcode = '22023';
  end if;
  -- ordem judicial ou medida de proteção sobre este responsável: não envia
  if v_envia and exists (select 1 from iara.guarda_restricoes g where g.student_id = v_student and g.guardian_id = v_guardian and iara.guarda_ativa(g)
                           and (g.bloquear_portal or g.tipo in ('MEDIDA_PROTETIVA', 'PROIBICAO_CONTATO'))) then
    raise exception 'Há restrição judicial ou de guarda sobre este responsável: registre sem envio e explique o motivo.' using errcode = '22023';
  end if;
  -- o Conselho Tutelar entra sempre que há risco à criança: a comunicação não espera os avisos
  if iara.reuniao_tema_protecao(v_tema) or not v_envia then
    v_orgaos := (select array_agg(distinct x) from unnest(v_orgaos || array['CONSELHO_TUTELAR']) x);
  end if;

  insert into iara.reunioes_responsavel (student_id, unit_id, class_id, guardian_id, ocorrencia_id, realizada_em, participantes, tema, orgaos, resumo, solucoes,
                                         posicao_escola, posicao_responsavel, envia_responsavel, motivo_sem_envio, situacao, enviada_em, registrada_por_label, is_demo)
  values (v_student, e.unit_id, e.class_id, v_guardian, v_ocorrencia, v_quando, nullif(btrim(coalesce(p ->> 'participantes', '')), ''), v_tema, v_orgaos, v_resumo, v_solucoes,
          v_escola, v_resp, v_envia, case when not v_envia then v_motivo end, case when v_envia then 'AGUARDANDO' else 'SEM_ENVIO' end,
          case when v_envia then now() end, iara.my_label(), false)
  returning * into r;

  insert into iara.reuniao_destinos (reuniao_id, papel)
  select r.id, x from unnest(array['PROFESSOR', 'DIRETOR_UNIDADE', 'SECRETARIA_ESCOLAR', 'SECRETARIO', 'SUPERINTENDENCIA']) x;
  update iara.reuniao_destinos set lido_em = now(), lido_por_label = iara.my_label() where reuniao_id = r.id and papel = iara.my_role();
  insert into iara.reuniao_eventos (reuniao_id, tipo, texto, autor_label)
  values (r.id, 'REGISTRO', 'Reunião registrada e encaminhada a professor(a), direção, secretaria escolar, secretário(a) e superintendência.', iara.my_label());

  if cardinality(v_orgaos) > 0 then
    perform iara.reuniao_preparar_orgaos(r.id, v_orgaos, case when iara.reuniao_tema_protecao(v_tema) or not v_envia then 'PROTECAO' else 'INDICADO' end);
    insert into iara.reuniao_eventos (reuniao_id, tipo, texto, autor_label)
    values (r.id, 'ORGAOS_PREPARADOS', 'Envio preparado aos órgãos indicados: aguarda a confirmação do(a) Secretário(a) Municipal.', 'IARA (regra automática)');
  end if;
  if iara.reuniao_tema_protecao(v_tema) or not v_envia or cardinality(v_orgaos) > 0 then
    perform iara.reuniao_gerar_ocorrencia_seduc(r.id, case
      when iara.reuniao_tema_protecao(v_tema) then 'Assunto de proteção à criança: ' || iara.reuniao_tema_rotulo(v_tema) || '.'
      when not v_envia then 'Registro sem envio ao responsável, por risco.'
      else 'Escola indicou o acompanhamento de órgãos externos.' end);
    insert into iara.reuniao_eventos (reuniao_id, tipo, texto, autor_label)
    values (r.id, 'ORGAOS_PREPARADOS', 'Ocorrência urgente aberta para o(a) Secretário(a) Municipal, para envio às autoridades competentes.', 'IARA (regra automática)');
  end if;
  if v_envia then perform iara.reuniao_enviar_aviso(r.id, 0); end if;
  perform iara.audit_event('REUNIAO_REGISTRADA', 'student', v_student::text, e.unit_id, format('Reunião com o responsável registrada (%s).', iara.reuniao_tema_rotulo(v_tema)));
  select * into r from iara.reunioes_responsavel where id = r.id;
  return iara.reuniao_json(r, true) || jsonb_build_object('mensagem', case
    when not v_envia then 'Registrado sem envio ao responsável. A ocorrência urgente foi para o(a) Secretário(a) Municipal, que confirma o envio às autoridades.'
    when r.ocorrencia_seduc_id is not null then 'Registrado e enviado ao responsável para validação. A ocorrência urgente foi para o(a) Secretário(a) Municipal, que confirma o envio às autoridades.'
    else 'Registrado e enviado ao responsável para validação. Sem resposta, os avisos seguem em D+1, D+2 e D+3.' end);
end $$;

create or replace function api.reunioes_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_student uuid := nullif(p ->> 'student_id', '')::uuid;
  v_guardian uuid := nullif(p ->> 'guardian_id', '')::uuid;
  v_situacao text := nullif(p ->> 'situacao', '');
begin
  perform iara.require_perm('reunioes.read');
  if v_guardian is not null and not iara.can_access_guardian(v_guardian) then
    raise exception 'Responsável fora do seu acesso.' using errcode = '42501';
  end if;
  return (with base as (
      select r.* from iara.reunioes_responsavel r
      where iara.reuniao_acesso(r) and (v_student is null or r.student_id = v_student) and (v_guardian is null or r.guardian_id = v_guardian))
    select jsonb_build_object(
      'pode_registrar', iara.has_perm('reunioes.write'),
      'contagem', (select jsonb_build_object('total', count(*),
          'aguardando', count(*) filter (where situacao = 'AGUARDANDO'),
          'respondidas', count(*) filter (where situacao in ('ACEITA', 'MANIFESTADA')),
          'sem_envio', count(*) filter (where situacao = 'SEM_ENVIO'),
          'prazo_vencido', count(*) filter (where situacao = 'PRAZO_VENCIDO'),
          'envios_pendentes', (select count(*) from iara.reuniao_envios_orgaos e where e.reuniao_id in (select id from base) and e.situacao = 'AGUARDANDO_ENVIO'))
        from base),
      'itens', (select coalesce(jsonb_agg(iara.reuniao_json(x) order by x.realizada_em desc), '[]')
                from (select * from base b where v_situacao is null or b.situacao = v_situacao
                      or (v_situacao = 'RESPONDIDAS' and b.situacao in ('ACEITA', 'MANIFESTADA'))
                      or (v_situacao = 'ENVIO_PENDENTE' and exists (select 1 from iara.reuniao_envios_orgaos e where e.reuniao_id = b.id and e.situacao = 'AGUARDANDO_ENVIO'))
                      order by b.realizada_em desc limit 300) x)));
end $$;

create or replace function api.reuniao_detalhe(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r iara.reunioes_responsavel;
begin
  select * into r from iara.reunioes_responsavel where id = (p ->> 'id')::uuid;
  if r.id is null or not iara.reuniao_acesso(r) then raise exception 'Registro não encontrado.' using errcode = 'P0002'; end if;
  update iara.reuniao_destinos set lido_em = now(), lido_por_label = iara.my_label() where reuniao_id = r.id and papel = iara.my_role() and lido_em is null;
  return iara.reuniao_json(r, true) || jsonb_build_object(
    'pode_enviar_orgao', iara.has_perm('reunioes.enviar'),
    'pode_avancar_dia', iara.demo_mode() and iara.has_perm('reunioes.write') and r.situacao = 'AGUARDANDO');
end $$;

-- confirma, com o protocolo, que o registro foi enviado ao órgão
create or replace function api.reuniao_envio_orgao(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  en iara.reuniao_envios_orgaos;
  r iara.reunioes_responsavel;
  v_prot text := btrim(coalesce(p ->> 'protocolo', ''));
begin
  perform iara.require_perm('reunioes.enviar');
  select * into en from iara.reuniao_envios_orgaos where id = (p ->> 'id')::uuid for update;
  if en.id is null then raise exception 'Envio não encontrado.' using errcode = 'P0002'; end if;
  select * into r from iara.reunioes_responsavel where id = en.reuniao_id;
  if not iara.reuniao_acesso(r) then raise exception 'Envio não encontrado.' using errcode = 'P0002'; end if;
  if en.situacao <> 'AGUARDANDO_ENVIO' then raise exception 'Este envio não está pendente.' using errcode = '22023'; end if;
  if length(v_prot) < 3 then raise exception 'Informe o protocolo ou o número do envio.' using errcode = '22023'; end if;
  update iara.reuniao_envios_orgaos set situacao = 'ENVIADO', enviado_em = now(), enviado_por_label = iara.my_label(), protocolo = v_prot where id = en.id;
  insert into iara.reuniao_eventos (reuniao_id, tipo, texto, autor_label)
  values (r.id, 'ENVIO_ORGAO', format('Registro enviado: %s. Protocolo %s.',
    case en.orgao when 'CONSELHO_TUTELAR' then 'Conselho Tutelar' when 'DEFENSORIA' then 'Defensoria Pública' else 'Ministério Público' end, v_prot), iara.my_label());
  if r.ocorrencia_seduc_id is not null then
    insert into iara.ocorrencia_eventos (ocorrencia_id, origem, tipo, interno, texto, autor_label, is_demo)
    values (r.ocorrencia_seduc_id, 'ESCOLA', 'NOTA_INTERNA', true, format('Registro de reunião %s enviado a %s. Protocolo %s.', iara.reuniao_codigo(r.id),
      case en.orgao when 'CONSELHO_TUTELAR' then 'Conselho Tutelar' when 'DEFENSORIA' then 'Defensoria Pública' else 'Ministério Público' end, v_prot), iara.my_label(), r.is_demo);
  end if;
  perform iara.audit_event('REUNIAO_ENVIO_ORGAO', 'student', r.student_id::text, r.unit_id, format('Registro de reunião enviado a %s.', en.orgao));
  return jsonb_build_object('ok', true);
end $$;

-- só na apresentação: avança um dia na régua de avisos do registro, sem esperar o calendário
create or replace function api.reuniao_demo_avancar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r iara.reunioes_responsavel;
  v_res text;
begin
  perform iara.exigir_demo();
  perform iara.require_perm('reunioes.write');
  select * into r from iara.reunioes_responsavel where id = (p ->> 'id')::uuid;
  if r.id is null or not iara.reuniao_acesso(r) then raise exception 'Registro não encontrado.' using errcode = 'P0002'; end if;
  if r.situacao <> 'AGUARDANDO' then raise exception 'Este registro não está aguardando o responsável.' using errcode = '22023'; end if;
  update iara.reunioes_responsavel set enviada_em = enviada_em - interval '1 day' where id = r.id;
  update iara.reuniao_eventos set em = em - interval '1 day' where reuniao_id = r.id;
  v_res := iara.reuniao_processar(r.id, true);
  return jsonb_build_object('ok', true, 'resultado', v_res);
end $$;

-- ===================================================================== Família
create or replace function api.familia_reunioes(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_g uuid := iara.my_guardian();
begin
  if v_g is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  return (with base as (
      select r.* from iara.reunioes_responsavel r
      where r.guardian_id = v_g and r.envia_responsavel and r.student_id in (select iara.my_student_ids()))
    select jsonb_build_object(
      'aguardando', (select count(*) from base where situacao in ('AGUARDANDO', 'PRAZO_VENCIDO')),
      'reunioes', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', b.id, 'codigo', iara.reuniao_codigo(b.id), 'aluno', split_part(s.full_name, ' ', 1), 'unidade', u.short_name, 'tema_rotulo', iara.reuniao_tema_rotulo(b.tema),
          'realizada_em', b.realizada_em, 'resumo', b.resumo, 'solucoes', b.solucoes, 'posicao_escola', b.posicao_escola, 'posicao_responsavel', b.posicao_responsavel,
          'situacao', b.situacao, 'pode_responder', b.situacao in ('AGUARDANDO', 'PRAZO_VENCIDO'), 'resposta_em', b.resposta_em, 'manifestacao', b.manifestacao,
          'avisos', (select coalesce(jsonb_agg(jsonb_build_object('dia', e.dia, 'titulo', e.titulo, 'texto', e.texto, 'em', e.em) order by e.dia), '[]')
                     from iara.reuniao_eventos e where e.reuniao_id = b.id and e.tipo = 'AVISO'))
          order by (b.situacao in ('AGUARDANDO', 'PRAZO_VENCIDO')) desc, b.realizada_em desc), '[]')
        from base b join iara.students s on s.id = b.student_id left join iara.education_units u on u.id = b.unit_id)));
end $$;

create or replace function api.familia_reuniao_responder(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r iara.reunioes_responsavel;
  v_acao text := upper(coalesce(p ->> 'acao', ''));
  v_texto text := btrim(coalesce(p ->> 'texto', ''));
  v_canal text := coalesce(nullif(p ->> 'canal', ''), 'PORTAL');
  v_g uuid := iara.my_guardian();
begin
  if v_g is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  select * into r from iara.reunioes_responsavel where id = (p ->> 'id')::uuid for update;
  if r.id is null or r.guardian_id <> v_g or not r.envia_responsavel or not (r.student_id in (select iara.my_student_ids())) then
    raise exception 'Registro não encontrado.' using errcode = 'P0002';
  end if;
  if r.situacao not in ('AGUARDANDO', 'PRAZO_VENCIDO') then raise exception 'Este registro já foi respondido.' using errcode = '22023'; end if;
  if v_acao = 'ACEITAR' then
    update iara.reunioes_responsavel set situacao = 'ACEITA', resposta_em = now(), resposta_canal = v_canal where id = r.id;
    insert into iara.reuniao_eventos (reuniao_id, tipo, texto, autor_label)
    values (r.id, 'ACEITE', 'O responsável confirmou o registro da reunião.', iara.my_label());
  elsif v_acao = 'MANIFESTAR' then
    if length(v_texto) not between 10 and 4000 then raise exception 'Escreva a sua manifestação (de 10 a 4.000 caracteres).' using errcode = '22023'; end if;
    update iara.reunioes_responsavel set situacao = 'MANIFESTADA', resposta_em = now(), resposta_canal = v_canal, manifestacao = v_texto where id = r.id;
    insert into iara.reuniao_eventos (reuniao_id, tipo, texto, autor_label)
    values (r.id, 'MANIFESTACAO', v_texto, iara.my_label());
  else
    raise exception 'Resposta inválida.' using errcode = '22023';
  end if;
  -- respondeu antes do envio: o que estava preparado por falta de validação não segue; o que é de proteção ou foi indicado pela escola continua
  update iara.reuniao_envios_orgaos set situacao = 'CANCELADO' where reuniao_id = r.id and motivo = 'SEM_VALIDACAO' and situacao = 'AGUARDANDO_ENVIO';
  if found then
    insert into iara.reuniao_eventos (reuniao_id, tipo, texto, autor_label)
    values (r.id, 'ORGAOS_CANCELADOS', 'O responsável respondeu antes do envio: o envio preparado por falta de validação foi cancelado.', 'IARA (regra automática)');
  end if;
  perform iara.audit_event('REUNIAO_RESPOSTA', 'student', r.student_id::text, r.unit_id,
    case when v_acao = 'ACEITAR' then 'Responsável confirmou o registro de reunião.' else 'Responsável registrou manifestação sobre o registro de reunião.' end);
  return jsonb_build_object('ok', true, 'mensagem', case when v_acao = 'ACEITAR'
    then 'Registro confirmado. A escola já pode ver a sua validação.'
    else 'Manifestação registrada. Ela fica junto do registro, e a escola e os órgãos de acompanhamento podem ler.' end);
end $$;

-- Relato de possível violência feito à IARA: vira na hora ocorrência urgente e sigilosa com o(a) Secretário(a) e prepara a comunicação obrigatória
-- ao Conselho Tutelar. Não fica visível para nenhum responsável, nem para quem relatou: o celular pode estar nas mãos de quem agride.
create or replace function api.familia_relato_protecao(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_g uuid := iara.my_guardian();
  v_texto text := left(btrim(coalesce(p ->> 'texto', '')), 2000);
  e record;
  v_oc uuid;
  v_filhos text;
  v_motivo text := 'Relato de possível violência recebido pela IARA.';
begin
  if v_g is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  select en.student_id, en.unit_id, en.class_id into e from iara.enrollments en
  where en.status = 'ACTIVE' and en.student_id in (select iara.my_student_ids()) order by en.student_id limit 1;
  if e.student_id is null then return jsonb_build_object('ok', false); end if;
  select string_agg(split_part(s.full_name, ' ', 1), ', ') into v_filhos from iara.students s where s.id in (select iara.my_student_ids());
  -- o mesmo responsável, no mesmo dia: soma ao registro que já está aberto
  select o.id into v_oc from iara.ocorrencias o
  where o.student_id = e.student_id and o.instancia = 'SECRETARIA' and o.sigilosa and o.motivo_seduc = v_motivo and o.situacao <> 'ENCERRADA'
    and (o.created_at at time zone 'America/Sao_Paulo')::date = iara.hoje_local() limit 1;
  if v_oc is not null then
    insert into iara.ocorrencia_eventos (ocorrencia_id, origem, tipo, interno, texto, autor_label, is_demo)
    values (v_oc, 'FAMILIA', 'NOTA_INTERNA', true, 'Novo relato na conversa: ' || v_texto, 'IARA (conversa com o responsável)', false);
    return jsonb_build_object('ok', true, 'id', v_oc);
  end if;
  insert into iara.ocorrencias (student_id, unit_id, class_id, origem, tipo, gravidade, descricao, providencias, situacao, registrada_por_label, sigilosa, instancia, prazo,
                                encaminhada_seduc_em, encaminhada_por_label, motivo_seduc, is_demo)
  values (e.student_id, e.unit_id, e.class_id, 'FAMILIA', 'OUTRO', 'GRAVE',
          format('Relato de possível violência recebido pela IARA, de %s. Crianças vinculadas: %s. Relato: %s', coalesce(iara.my_label(), 'responsável'), v_filhos, v_texto),
          'Atendimento humano acionado. Enviar às autoridades competentes. Não contatar a família sem avaliar o risco.', 'EM_ACOMPANHAMENTO',
          'IARA (conversa com o responsável)', true, 'SECRETARIA', iara.hoje_local() + 1, now(), 'IARA (regra automática)', v_motivo, false)
  returning id into v_oc;
  insert into iara.ocorrencia_eventos (ocorrencia_id, origem, tipo, interno, texto, autor_label, is_demo)
  values (v_oc, 'ESCOLA', 'ENCAMINHADA_SEDUC', true, 'Aberta com urgência pela IARA, para o(a) Secretário(a) Municipal, para envio às autoridades competentes.', 'IARA (regra automática)', false);
  perform iara.ocorrencia_comunicar_ct(v_oc, 'IARA (regra automática)');
  perform iara.audit_event('OCORRENCIA_REGISTRADA', 'student', e.student_id::text, e.unit_id, 'Relato de possível violência recebido pela IARA: ocorrência urgente e sigilosa aberta.');
  return jsonb_build_object('ok', true, 'id', v_oc);
end $$;

-- ===================================================================== Controle externo (Ministério Público, Defensoria e Conselho Tutelar)
-- A lista não identifica a criança. Para abrir, o motivo da consulta é obrigatório e fica na auditoria, como na consulta de protocolo.
create or replace function api.controle_reunioes(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_situacao text := nullif(p ->> 'situacao', '');
  v_orgao text := nullif(p ->> 'orgao', '');
begin
  perform iara.require_perm('controle.read');
  return (with base as (
      select r.* from iara.reunioes_responsavel r
      where (v_orgao is null or v_orgao = any (r.orgaos) or exists (select 1 from iara.reuniao_envios_orgaos e where e.reuniao_id = r.id and e.orgao = v_orgao and e.situacao <> 'CANCELADO')))
    select jsonb_build_object(
      'contagem', (select jsonb_build_object('total', count(*), 'aguardando', count(*) filter (where situacao = 'AGUARDANDO'),
          'respondidas', count(*) filter (where situacao in ('ACEITA', 'MANIFESTADA')), 'sem_envio', count(*) filter (where situacao = 'SEM_ENVIO'),
          'prazo_vencido', count(*) filter (where situacao = 'PRAZO_VENCIDO')) from base),
      'itens', (select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'codigo', iara.reuniao_codigo(b.id), 'unidade', u.short_name, 'tema_rotulo', iara.reuniao_tema_rotulo(b.tema),
            'realizada_em', b.realizada_em, 'situacao', b.situacao, 'ultimo_aviso', b.ultimo_aviso, 'envia_responsavel', b.envia_responsavel, 'is_demo', b.is_demo,
            'envios', (select coalesce(jsonb_agg(jsonb_build_object('orgao', e.orgao, 'situacao', e.situacao)), '[]') from iara.reuniao_envios_orgaos e where e.reuniao_id = b.id and e.situacao <> 'CANCELADO'))
          order by b.realizada_em desc), '[]')
        from (select * from base x where v_situacao is null or x.situacao = v_situacao or (v_situacao = 'RESPONDIDAS' and x.situacao in ('ACEITA', 'MANIFESTADA'))
              order by x.realizada_em desc limit 300) b left join iara.education_units u on u.id = b.unit_id)));
end $$;

create or replace function api.controle_reuniao(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r iara.reunioes_responsavel;
  v_motivo text := nullif(btrim(coalesce(p ->> 'motivo', '')), '');
begin
  perform iara.require_perm('controle.read');
  if v_motivo is null or length(v_motivo) < 10 then
    raise exception 'Registre o motivo da consulta (ex.: atendimento da Defensoria nº …, procedimento do MP nº …).' using errcode = '22023';
  end if;
  select * into r from iara.reunioes_responsavel where id = (p ->> 'id')::uuid;
  if r.id is null then raise exception 'Registro não encontrado.' using errcode = 'P0002'; end if;
  insert into iara.reuniao_eventos (reuniao_id, tipo, texto, autor_label) values (r.id, 'CONSULTA_EXTERNA', 'Consulta do controle externo. Motivo: ' || v_motivo, iara.my_label());
  perform iara.audit_event('CONTROLE_CONSULTA', 'student', r.student_id::text, r.unit_id, format('Controle externo consultou o registro de reunião %s. Motivo: %s', iara.reuniao_codigo(r.id), v_motivo));
  return iara.reuniao_json(r, true) || jsonb_build_object('consultado_em', now(), 'motivo', v_motivo);
end $$;

-- ===================================================================== Demonstração
-- Um registro em cada etapa, na unidade da Maria. Os dados são fictícios e a régua automática não mexe neles:
-- eles só avançam pelo botão de avanço de dia.
create or replace function iara.demo_gerar_reunioes() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_maria uuid := (iara.setting('demo_guardian_maria'))::uuid;
  v_unit integer := (iara.setting('demo_unit_maria'))::int;
  v_ana uuid;
  v_ana_turma uuid;
  a record;
  v_i integer := 0;
  v_id uuid;
  v_agora timestamptz := now();
  v_dias integer;
  v_situacao text;
  v_tema text;
  v_resumo text; v_sol text; v_esc text; v_resp text; v_mot text; v_man text;
  v_envia boolean;
  v_ult integer;
  d integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.notifications where event_type = 'REUNIAO_AVISO' and student_id in (select student_id from iara.reunioes_responsavel where is_demo);
  delete from iara.ocorrencias where id in (select ocorrencia_seduc_id from iara.reunioes_responsavel where is_demo and ocorrencia_seduc_id is not null);
  delete from iara.reunioes_responsavel where is_demo;
  select sg.student_id, e.class_id into v_ana, v_ana_turma from iara.student_guardians sg join iara.enrollments e on e.student_id = sg.student_id and e.status = 'ACTIVE'
  where sg.guardian_id = v_maria limit 1;
  if v_ana is null then return jsonb_build_object('gerados', 0); end if;

  for a in
    (select v_ana sid, v_maria gid, 0 ordem)
    union all
    (select x.student_id, x.guardian_id, 1 from (
       select distinct on (e.student_id) e.student_id, sg.guardian_id, e.class_id, s.full_name
       from iara.enrollments e join iara.students s on s.id = e.student_id
       join iara.student_guardians sg on sg.student_id = e.student_id and sg.end_date is null and sg.is_primary
       where e.unit_id = v_unit and e.status = 'ACTIVE' and e.student_id <> v_ana and sg.guardian_id <> v_maria
       order by e.student_id) x
     order by (x.class_id = v_ana_turma) desc, x.full_name limit 7)
    order by ordem
  loop
    v_i := v_i + 1;
    v_envia := true; v_mot := null; v_man := null; v_ult := 0; v_situacao := 'AGUARDANDO'; v_dias := 0;
    case v_i
      when 1 then
        v_tema := 'INFREQUENCIA'; v_dias := 0;
        v_resumo := 'Reunião sobre as faltas das últimas semanas e o efeito delas na rotina e na adaptação da criança à turma.';
        v_sol := 'Combinar o horário de chegada com a família, avisar a escola pelo portal quando houver falta e rever a situação em 30 dias.';
        v_esc := 'A escola reforça que a presença é importante nesta idade e se coloca à disposição para ajustar o acolhimento.';
        v_resp := 'A responsável relatou dificuldade de transporte em alguns dias e se comprometeu a avisar com antecedência.';
      when 2 then
        v_tema := 'VIOLENCIA_DOMESTICA'; v_dias := 2; v_situacao := 'SEM_ENVIO'; v_envia := false; v_ult := -1;
        v_resumo := 'A responsável procurou a escola e relatou situação de violência doméstica na residência, com reflexos no comportamento da criança.';
        v_sol := 'Acompanhamento pela orientação da escola, comunicação ao Conselho Tutelar e encaminhamento da família à rede de proteção.';
        v_esc := 'A escola comunicou que tem o dever de informar o Conselho Tutelar e que seguirá acompanhando a criança com atenção diária.';
        v_resp := 'A responsável confirmou o relato, concordou com o acompanhamento e pediu orientação sobre a rede de proteção.';
        v_mot := 'A responsável pediu que nada fosse enviado ao celular, porque outra pessoa da casa tem acesso ao aparelho.';
      when 3 then
        v_tema := 'INFREQUENCIA'; v_dias := 1; v_ult := 1;
        v_resumo := 'Reunião sobre faltas sem justificativa nos últimos 30 dias, depois de tentativas de contato pela Busca ativa.';
        v_sol := 'Plano de retorno com acompanhamento semanal e atendimento da família pela equipe pedagógica.';
        v_esc := 'A escola propôs o plano de retorno e informou que o limite de faltas sem justificativa é acompanhado pela rede.';
        v_resp := 'O responsável relatou mudança na rotina de trabalho e pediu prazo para reorganizar os horários.';
      when 4 then
        v_tema := 'NEGLIGENCIA'; v_dias := 2; v_ult := 2;
        v_resumo := 'Reunião sobre sinais de falta de cuidados básicos observados pela equipe, como higiene e alimentação.';
        v_sol := 'Encaminhamento ao CRAS, acompanhamento pela orientação da escola e nova conversa em 15 dias.';
        v_esc := 'A escola explicou o que observou, ofereceu apoio e informou que o Conselho Tutelar será comunicado.';
        v_resp := 'A responsável disse que passa por dificuldade financeira e aceitou o encaminhamento ao CRAS.';
      when 5 then
        v_tema := 'DIREITO_EDUCACAO'; v_dias := 3; v_ult := 3;
        v_resumo := 'Reunião sobre a recusa da família em manter a criança no atendimento educacional indicado pela equipe.';
        v_sol := 'Apresentar o plano de atendimento e agendar a conversa da família com a equipe de inclusão.';
        v_esc := 'A escola entende que o atendimento é um direito da criança e pediu que a família reconsidere.';
        v_resp := 'O responsável disse que vai pensar e pediu mais informações antes de decidir.';
      when 6 then
        v_tema := 'INFREQUENCIA'; v_dias := 5; v_ult := 3; v_situacao := 'PRAZO_VENCIDO';
        v_resumo := 'Reunião sobre infrequência prolongada, com risco de abandono escolar.';
        v_sol := 'Plano de retorno gradual e acompanhamento pela Busca ativa.';
        v_esc := 'A escola propôs o plano de retorno e alertou sobre as consequências do abandono escolar.';
        v_resp := 'O responsável disse que a criança voltaria na semana seguinte, o que não ocorreu.';
      when 7 then
        v_tema := 'CONFLITO_FAMILIAR'; v_dias := 4; v_ult := 1; v_situacao := 'ACEITA';
        v_resumo := 'Reunião sobre quem pode retirar a criança na saída, depois de desencontro entre os responsáveis.';
        v_sol := 'Atualizar a lista de autorizados e registrar a guarda vigente na secretaria da escola.';
        v_esc := 'A escola só entrega a criança às pessoas autorizadas na ficha.';
        v_resp := 'A responsável concordou e vai levar o documento da guarda à secretaria.';
      else
        v_tema := 'OUTRO'; v_dias := 3; v_ult := 1; v_situacao := 'MANIFESTADA';
        v_resumo := 'Reunião sobre a mudança de turma proposta pela escola para a criança, por causa de conflitos recorrentes.';
        v_sol := 'Período de observação de 30 dias na turma atual, com acompanhamento da orientação.';
        v_esc := 'A escola entende que a mudança de turma pode ser necessária se os conflitos continuarem.';
        v_resp := 'O responsável pediu que a criança continue na turma atual.';
        v_man := 'O registro não menciona que pedi uma nova reunião com a direção antes de qualquer mudança de turma. Peço que isso conste.';
    end case;

    insert into iara.reunioes_responsavel (student_id, unit_id, class_id, guardian_id, realizada_em, participantes, tema, orgaos, resumo, solucoes, posicao_escola, posicao_responsavel,
        envia_responsavel, motivo_sem_envio, situacao, enviada_em, ultimo_aviso, resposta_em, resposta_canal, manifestacao, registrada_por_label, is_demo, created_at)
    select a.sid, e.unit_id, e.class_id, a.gid, v_agora - make_interval(days => v_dias, hours => 1), 'Direção, orientação e responsável', v_tema,
           case when v_tema = 'VIOLENCIA_DOMESTICA' then array['CONSELHO_TUTELAR', 'MINISTERIO_PUBLICO'] when iara.reuniao_tema_protecao(v_tema) then array['CONSELHO_TUTELAR'] else '{}'::text[] end, v_resumo, v_sol, v_esc, v_resp,
           v_envia, v_mot, v_situacao, case when v_envia then v_agora - make_interval(days => v_dias) end, v_ult,
           case when v_situacao in ('ACEITA', 'MANIFESTADA') then v_agora - make_interval(days => v_dias - 1) end,
           case when v_situacao in ('ACEITA', 'MANIFESTADA') then 'PORTAL' end, v_man, 'Direção da escola', true, v_agora - make_interval(days => v_dias)
    from iara.enrollments e where e.student_id = a.sid and e.status = 'ACTIVE' limit 1
    returning id into v_id;

    insert into iara.reuniao_destinos (reuniao_id, papel, lido_em, lido_por_label)
    select v_id, x, case when v_dias > 0 and x in ('DIRETOR_UNIDADE', 'SECRETARIA_ESCOLAR') then v_agora - make_interval(days => v_dias) + interval '2 hours' end,
           case when v_dias > 0 and x in ('DIRETOR_UNIDADE', 'SECRETARIA_ESCOLAR') then 'Equipe da escola' end
    from unnest(array['PROFESSOR', 'DIRETOR_UNIDADE', 'SECRETARIA_ESCOLAR', 'SECRETARIO', 'SUPERINTENDENCIA']) x;
    insert into iara.reuniao_eventos (reuniao_id, tipo, texto, autor_label, em)
    values (v_id, 'REGISTRO', 'Reunião registrada e encaminhada a professor(a), direção, secretaria escolar, secretário(a) e superintendência.', 'Direção da escola', v_agora - make_interval(days => v_dias));

    if v_envia then
      for d in 0 .. v_ult loop
        insert into iara.reuniao_eventos (reuniao_id, tipo, dia, titulo, texto, autor_label, em)
        select v_id, 'AVISO', d, m.titulo, iara.reuniao_aviso_texto(rr, d), 'IARA (aviso automático)', v_agora - make_interval(days => v_dias - d)
        from iara.reuniao_avisos_modelo m, iara.reunioes_responsavel rr where m.dia = d and rr.id = v_id;
      end loop;
    end if;
    if v_situacao = 'ACEITA' then
      insert into iara.reuniao_eventos (reuniao_id, tipo, texto, autor_label, em) values (v_id, 'ACEITE', 'O responsável confirmou o registro da reunião.', 'Responsável', v_agora - make_interval(days => v_dias - 1));
    elsif v_situacao = 'MANIFESTADA' then
      insert into iara.reuniao_eventos (reuniao_id, tipo, texto, autor_label, em) values (v_id, 'MANIFESTACAO', v_man, 'Responsável', v_agora - make_interval(days => v_dias - 1));
    end if;
    if iara.reuniao_tema_protecao(v_tema) then
      insert into iara.reuniao_envios_orgaos (reuniao_id, orgao, motivo, situacao, preparado_em, enviado_em, enviado_por_label, protocolo)
      values (v_id, 'CONSELHO_TUTELAR', 'PROTECAO', 'ENVIADO', v_agora - make_interval(days => v_dias), v_agora - make_interval(days => v_dias) + interval '3 hours', 'Gabinete da Secretaria', 'CT-2026-' || lpad((1400 + v_i)::text, 4, '0'));
      insert into iara.reuniao_eventos (reuniao_id, tipo, texto, autor_label, em)
      values (v_id, 'ENVIO_ORGAO', 'Registro enviado: Conselho Tutelar. Protocolo CT-2026-' || lpad((1400 + v_i)::text, 4, '0') || '.', 'Gabinete da Secretaria', v_agora - make_interval(days => v_dias) + interval '3 hours');
    end if;
    if v_tema = 'VIOLENCIA_DOMESTICA' then
      insert into iara.reuniao_envios_orgaos (reuniao_id, orgao, motivo, preparado_em) values (v_id, 'MINISTERIO_PUBLICO', 'INDICADO', v_agora - make_interval(days => v_dias));
    end if;
    if v_situacao = 'PRAZO_VENCIDO' then
      perform iara.reuniao_preparar_orgaos(v_id, array['CONSELHO_TUTELAR', 'DEFENSORIA', 'MINISTERIO_PUBLICO'], 'SEM_VALIDACAO');
      insert into iara.reuniao_eventos (reuniao_id, tipo, texto, autor_label, em)
      values (v_id, 'ORGAOS_PREPARADOS', 'Sem validação depois do último aviso. Envio preparado ao Conselho Tutelar, à Defensoria Pública e ao Ministério Público: aguarda a confirmação do(a) Secretário(a) Municipal.', 'IARA (regra automática)', v_agora - interval '1 day');
    end if;
    if iara.reuniao_tema_protecao(v_tema) or not v_envia or v_situacao = 'PRAZO_VENCIDO' then
      perform iara.reuniao_gerar_ocorrencia_seduc(v_id, case when iara.reuniao_tema_protecao(v_tema) then 'Assunto de proteção à criança: ' || iara.reuniao_tema_rotulo(v_tema) || '.'
                                                             else 'Responsável não validou o registro depois do último aviso.' end, 'IARA (regra automática)');
    end if;
  end loop;

  -- a Maria vê o aviso no portal
  insert into iara.notifications (tenant_id, guardian_id, student_id, channel, event_type, title, body, status, created_at)
  select 1, r.guardian_id, r.student_id, 'PORTAL', 'REUNIAO_AVISO', m.titulo, iara.reuniao_aviso_texto(r, 0), 'SIMULADA', r.enviada_em
  from iara.reunioes_responsavel r join iara.reuniao_avisos_modelo m on m.dia = 0 where r.is_demo and r.student_id = v_ana;
  return jsonb_build_object('gerados', v_i);
end $$;

-- a limpeza da apresentação apaga o que foi registrado ao vivo e devolve os registros de demonstração à etapa original
create or replace function iara.demo_purge_reunioes(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.notifications where event_type = 'REUNIAO_AVISO' and created_at >= coalesce(p_desde, '-infinity'::timestamptz)
    and student_id in (select student_id from iara.reunioes_responsavel where not is_demo);
  delete from iara.ocorrencias where id in (select ocorrencia_seduc_id from iara.reunioes_responsavel where not is_demo and ocorrencia_seduc_id is not null and created_at >= coalesce(p_desde, '-infinity'::timestamptz));
  delete from iara.reunioes_responsavel where not is_demo and created_at >= coalesce(p_desde, '-infinity'::timestamptz);
  get diagnostics n = row_count;
  return jsonb_build_object('registros_ao_vivo', n, 'demonstracao', iara.demo_gerar_reunioes());
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
                               'arquivos', iara.demo_limpar_arquivos_vivos(null));
  return jsonb_build_object('ok', true, 'resultado', r, 'situacao', api.demo_apresentacao_situacao('{}'::jsonb));
end $$;

revoke all on function iara.demo_gerar_reunioes(), iara.demo_purge_reunioes(timestamptz), iara.reunioes_rotina(), iara.reuniao_processar(uuid, boolean),
  iara.reuniao_gerar_ocorrencia_seduc(uuid, text, text),
  iara.reuniao_enviar_aviso(uuid, integer, text), iara.reuniao_preparar_orgaos(uuid, text[], text) from public;

-- a régua roda a cada hora; os avisos só saem das 8h às 19h
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('iara-reunioes-avisos', '12 * * * *', $c$select iara.reunioes_rotina()$c$);
  end if;
end $$;

select iara.demo_gerar_reunioes();

commit;
