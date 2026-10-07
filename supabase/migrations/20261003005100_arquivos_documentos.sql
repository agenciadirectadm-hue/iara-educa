-- IARA Educa — 051 · Arquivos (documentos em PDF e fotos), validação pela área responsável, alterações cadastrais
-- pedidas pela família, inclusão/alteração/exclusão de alunos, responsáveis e profissionais, e materiais.
-- Arquivos ficam num bucket PRIVADO do Storage; só o gateway (chave de serviço) lê e grava, depois de o banco autorizar
-- (api.arquivo_autorizar / api.arquivo_acesso) e registrar (api.arquivo_confirmar). Documento só em PDF; foto (JPEG/PNG)
-- só para foto do aluno ou do servidor. O que a família envia entra pendente; a área responsável valida ou recusa com
-- motivo e orientação de como proceder, e a família é avisada no portal e pela IARA.
begin;

-- 1. Bucket privado ---------------------------------------------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('iara-arquivos', 'iara-arquivos', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- 2. Permissões ------------------------------------------------------------------------------------------------------------------
insert into iara.permissions (code, description, is_sensitive) values
  ('pessoal.write', 'Incluir, alterar e desligar servidores (a unidade só os seus)', true),
  ('materiais.read', 'Consultar materiais, estoque e patrimônio', false),
  ('materiais.write', 'Incluir, movimentar, alterar e excluir materiais', false)
on conflict (code) do update set description = excluded.description, is_sensitive = excluded.is_sensitive;
insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('SECRETARIO', 'pessoal.write'), ('SUPERINTENDENCIA', 'pessoal.write'), ('GERENCIA_EI', 'pessoal.write'), ('DIRETOR_UNIDADE', 'pessoal.write'),
  ('DIRETOR_UNIDADE', 'materiais.read'), ('DIRETOR_UNIDADE', 'materiais.write'), ('SECRETARIA_ESCOLAR', 'materiais.read'), ('SECRETARIA_ESCOLAR', 'materiais.write'),
  ('SECRETARIO', 'materiais.read'), ('SECRETARIO', 'materiais.write'), ('SUPERINTENDENCIA', 'materiais.read'), ('SUPERINTENDENCIA', 'materiais.write'),
  ('GERENCIA_EI', 'materiais.read'), ('NUTRICAO', 'materiais.read'), ('NUTRICAO', 'materiais.write'), ('MANUTENCAO', 'materiais.read'),
  ('MANUTENCAO', 'materiais.write'), ('INOVACAO', 'materiais.read'), ('PREFEITO', 'materiais.read')
) v(r, p)
on conflict do nothing;

-- 3. Tabelas ---------------------------------------------------------------------------------------------------------------------
create table if not exists iara.arquivos (
  id uuid primary key default gen_random_uuid(),
  bucket text not null default 'iara-arquivos',
  caminho text not null unique,
  finalidade text not null check (finalidade in ('DOCUMENTO', 'FOTO_ALUNO', 'FOTO_SERVIDOR', 'CONVERSA')),
  mime text not null check (mime in ('application/pdf', 'image/jpeg', 'image/png')),
  tamanho integer not null check (tamanho > 0 and tamanho <= 10485760),
  sha256 text not null,
  nome_original text,
  student_id uuid references iara.students(id) on delete cascade,
  staff_id uuid references iara.staff(id) on delete cascade,
  enviado_por_user uuid,
  enviado_por_guardian uuid references iara.guardians(id) on delete set null,
  origem text not null default 'PORTAL' check (origem in ('PORTAL', 'IARA', 'WHATSAPP', 'UNIDADE', 'SEDUC')),
  created_at timestamptz not null default now(),
  is_demo boolean not null default false
);
create index if not exists arquivos_student_idx on iara.arquivos (student_id);
-- arquivos a apagar do Storage (o gateway remove na rotina e esvazia a fila)
create table if not exists iara.arquivos_descartar (
  caminho text primary key,
  bucket text not null default 'iara-arquivos',
  motivo text,
  created_at timestamptz not null default now()
);

alter table iara.documents add column if not exists arquivo_id uuid references iara.arquivos(id) on delete set null;
alter table iara.documents add column if not exists origem text;
alter table iara.documents add column if not exists enviado_por_guardian uuid references iara.guardians(id) on delete set null;
alter table iara.documents add column if not exists motivo_recusa text;
alter table iara.documents add column if not exists orientacao text;
alter table iara.documents add column if not exists validado_por_label text;
alter table iara.documents add column if not exists decidido_em timestamptz;
alter table iara.students add column if not exists foto_arquivo_id uuid references iara.arquivos(id) on delete set null;
alter table iara.staff add column if not exists foto_arquivo_id uuid references iara.arquivos(id) on delete set null;

create table if not exists iara.alteracoes_cadastrais (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references iara.students(id) on delete cascade,
  guardian_id uuid references iara.guardians(id) on delete cascade,
  tipo text not null check (tipo in ('FOTO', 'ENDERECO', 'DADOS')),
  campos jsonb not null default '{}',
  anteriores jsonb not null default '{}',
  arquivo_id uuid references iara.arquivos(id) on delete set null,
  situacao text not null default 'PENDENTE' check (situacao in ('PENDENTE', 'APROVADA', 'RECUSADA')),
  aplicada boolean not null default false,
  area text not null default 'UNIDADE' check (area in ('UNIDADE', 'CENTRAL')),
  unit_id integer references iara.education_units(id),
  motivo_recusa text,
  orientacao text,
  solicitado_por_guardian uuid references iara.guardians(id) on delete set null,
  solicitado_label text,
  origem text not null default 'PORTAL',
  decidido_por_label text,
  decidido_em timestamptz,
  created_at timestamptz not null default now(),
  is_demo boolean not null default false
);
create index if not exists alteracoes_pend_idx on iara.alteracoes_cadastrais (situacao, unit_id);

create table if not exists iara.materiais (
  id uuid primary key default gen_random_uuid(),
  unit_id integer references iara.education_units(id),
  codigo text,
  nome text not null,
  categoria text not null check (categoria in ('PEDAGOGICO', 'LIMPEZA', 'ESCRITORIO', 'ALIMENTO', 'UNIFORME', 'EQUIPAMENTO', 'MOBILIARIO', 'OUTRO')),
  unidade_medida text not null default 'unidade',
  quantidade numeric(12, 2) not null default 0 check (quantidade >= 0),
  minimo numeric(12, 2) not null default 0,
  patrimonio text,
  estado text check (estado in ('NOVO', 'BOM', 'REGULAR', 'RUIM', 'INSERVIVEL')),
  localizacao text,
  observacao text,
  ativo boolean not null default true,
  atualizado_por_label text,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  is_demo boolean not null default false
);
create index if not exists materiais_unit_idx on iara.materiais (unit_id, categoria);
create table if not exists iara.materiais_movimentos (
  id uuid primary key default gen_random_uuid(),
  material_id uuid not null references iara.materiais(id) on delete cascade,
  tipo text not null check (tipo in ('ENTRADA', 'SAIDA', 'AJUSTE')),
  quantidade numeric(12, 2) not null,
  saldo numeric(12, 2) not null,
  motivo text,
  autor_label text,
  created_at timestamptz not null default now(),
  is_demo boolean not null default false
);

alter table iara.arquivos enable row level security;
alter table iara.arquivos_descartar enable row level security;
alter table iara.alteracoes_cadastrais enable row level security;
alter table iara.materiais enable row level security;
alter table iara.materiais_movimentos enable row level security;

-- 4. Arquivos: autorização, registro e acesso --------------------------------------------------------------------------------------
-- quem decide os documentos e as alterações do aluno: a unidade onde estuda ou, sem matrícula, a Central de Vagas
create or replace function iara.aluno_area(p_student uuid, out area text, out unit_id integer)
language sql stable security definer set search_path = iara, public
as $$
  select case when e.unit_id is not null then 'UNIDADE' else 'CENTRAL' end, e.unit_id
  from (select 1) x left join lateral (select en.unit_id from iara.enrollments en where en.student_id = p_student and en.status = 'ACTIVE' limit 1) e on true
$$;

create or replace function iara.pode_validar_aluno(p_student uuid) returns boolean
language sql stable security definer set search_path = iara, public
as $$ select (iara.has_perm('documents.manage') or iara.has_perm('students.write')) and iara.can_access_student(p_student) $$;

-- limites por finalidade: documento só em PDF; foto só JPEG/PNG; anexo de conversa (IARA) aceita os dois
create or replace function iara.arquivo_regras(p_finalidade text) returns jsonb
language sql immutable as $$
  select case p_finalidade
    when 'DOCUMENTO' then jsonb_build_object('tipos', jsonb_build_array('application/pdf'), 'max_bytes', 10485760)
    when 'CONVERSA' then jsonb_build_object('tipos', jsonb_build_array('application/pdf', 'image/jpeg', 'image/png'), 'max_bytes', 10485760)
    else jsonb_build_object('tipos', jsonb_build_array('image/jpeg', 'image/png'), 'max_bytes', 5242880) end
$$;

-- confere quem pode enviar e para onde; devolve o prefixo do caminho no bucket
create or replace function iara.arquivo_checar(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_fin text := p ->> 'finalidade';
  v_student uuid := nullif(p ->> 'student_id', '')::uuid;
  v_staff uuid := nullif(p ->> 'staff_id', '')::uuid;
  v_fam boolean := iara.my_guardian() is not null;
  v_prefixo text;
begin
  if v_fin not in ('DOCUMENTO', 'FOTO_ALUNO', 'FOTO_SERVIDOR', 'CONVERSA') then raise exception 'Finalidade inválida.' using errcode = '22023'; end if;
  if v_fin in ('DOCUMENTO', 'FOTO_ALUNO') then
    if v_student is null then raise exception 'Informe o aluno.' using errcode = '22023'; end if;
    if v_fam then
      if not (v_student in (select iara.my_student_ids())) then raise exception 'Criança não vinculada a você.' using errcode = '42501'; end if;
    elsif not ((iara.has_perm('documents.manage') or iara.has_perm('students.write')) and iara.can_access_student(v_student)) then
      raise exception 'Sem permissão para enviar arquivos deste aluno.' using errcode = '42501';
    end if;
    if v_fin = 'DOCUMENTO' and coalesce(p ->> 'doc_type', '') not in ('CERTIDAO', 'CPF', 'RG', 'COMPROVANTE_ENDERECO', 'CARTAO_SUS', 'VACINACAO',
        'CADUNICO', 'DECLARACAO_TRABALHO', 'LAUDO', 'GUARDA', 'DECISAO_JUDICIAL', 'TRANSFERENCIA') then
      raise exception 'Tipo de documento inválido.' using errcode = '22023';
    end if;
    v_prefixo := 'alunos/' || v_student || case when v_fin = 'DOCUMENTO' then '/documentos' else '/fotos' end;
  elsif v_fin = 'FOTO_SERVIDOR' then
    if v_staff is null then raise exception 'Informe o servidor.' using errcode = '22023'; end if;
    if not (v_staff = (select staff_id from iara.app_users where id = iara.current_user_id())
            or (iara.has_perm('pessoal.write') and iara.can_access_unit((select unit_id from iara.staff where id = v_staff)))) then
      raise exception 'Sem permissão para a foto deste servidor.' using errcode = '42501';
    end if;
    v_prefixo := 'servidores/' || v_staff || '/fotos';
  else
    if not v_fam then raise exception 'Anexo de conversa é para as famílias.' using errcode = '42501'; end if;
    v_prefixo := 'conversas/' || iara.my_guardian();
  end if;
  return iara.arquivo_regras(v_fin) || jsonb_build_object('bucket', 'iara-arquivos', 'prefixo', v_prefixo);
end $$;

create or replace function api.arquivo_autorizar(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  return iara.arquivo_checar(p);
end $$;

-- documento recebido (portal, IARA, WhatsApp ou balcão) entra na ficha; o da família fica aguardando a validação
create or replace function iara.documento_receber(p_student uuid, p_tipo text, p_arquivo uuid, p_nome text, p_origem text) returns iara.documents
language plpgsql security definer set search_path = iara, public
as $$
declare
  d iara.documents;
  v_fam boolean := iara.my_guardian() is not null;
  v_status text := case when v_fam then 'RECEBIDO' else 'VALIDADO' end;
begin
  select * into d from iara.documents where student_id = p_student and doc_type = p_tipo order by created_at desc limit 1 for update;
  if d.id is not null and d.status <> 'VALIDADO' then
    update iara.documents set arquivo_id = p_arquivo, file_name = left(coalesce(p_nome, file_name), 200), status = v_status, received_at = now(),
           validated_at = case when v_status = 'VALIDADO' then now() end, origem = p_origem,
           enviado_por_guardian = case when v_fam then iara.my_guardian() end, motivo_recusa = null, orientacao = null,
           validado_por_label = case when v_status = 'VALIDADO' then iara.my_label() end, decidido_em = case when v_status = 'VALIDADO' then now() end,
           updated_at = now()
    where id = d.id returning * into d;
  else
    insert into iara.documents (tenant_id, student_id, doc_type, status, file_name, received_at, validated_at, arquivo_id, origem,
                                enviado_por_guardian, validado_por_label, decidido_em, is_sensitive, is_demo)
    values (1, p_student, p_tipo, v_status, left(p_nome, 200), now(), case when v_status = 'VALIDADO' then now() end, p_arquivo, p_origem,
            case when v_fam then iara.my_guardian() end, case when v_status = 'VALIDADO' then iara.my_label() end,
            case when v_status = 'VALIDADO' then now() end, p_tipo in ('LAUDO', 'CARTAO_SUS', 'DECISAO_JUDICIAL', 'GUARDA'), false)
    returning * into d;
  end if;
  perform iara.audit_event('DOCUMENTO_RECEBIDO', 'student', p_student::text, null,
    format('Documento %s recebido (%s)%s.', p_tipo, lower(p_origem), case when v_fam then ', aguardando validação' else ', conferido pela unidade' end));
  return d;
end $$;

-- foto enviada pela família: fica pendente até a área validar; enviada pela unidade: entra na hora
create or replace function iara.foto_aluno_receber(p_student uuid, p_arquivo uuid, p_origem text) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_area record;
  v_id uuid;
begin
  if iara.my_guardian() is null then
    update iara.students set foto_arquivo_id = p_arquivo where id = p_student;
    perform iara.audit_event('FOTO_ALUNO', 'student', p_student::text, null, 'Foto do aluno atualizada pela unidade.');
    return jsonb_build_object('ok', true, 'aplicada', true, 'mensagem', 'Foto atualizada na ficha.');
  end if;
  select * into v_area from iara.aluno_area(p_student);
  update iara.alteracoes_cadastrais set situacao = 'RECUSADA', motivo_recusa = 'Substituída por uma foto mais nova.', decidido_em = now()
  where student_id = p_student and tipo = 'FOTO' and situacao = 'PENDENTE';
  insert into iara.alteracoes_cadastrais (student_id, tipo, arquivo_id, area, unit_id, solicitado_por_guardian, solicitado_label, origem, anteriores)
  values (p_student, 'FOTO', p_arquivo, v_area.area, v_area.unit_id, iara.my_guardian(), iara.my_label(), p_origem,
          jsonb_build_object('foto_arquivo_id', (select foto_arquivo_id from iara.students where id = p_student)))
  returning id into v_id;
  perform iara.audit_event('ALTERACAO_SOLICITADA', 'student', p_student::text, v_area.unit_id, 'Família enviou nova foto da criança (aguardando validação).');
  return jsonb_build_object('ok', true, 'aplicada', false, 'alteracao_id', v_id,
    'mensagem', case when v_area.area = 'UNIDADE' then 'Foto enviada. A secretaria da escola confere e ela entra na ficha.' else 'Foto enviada. A Central de Vagas confere e ela entra na ficha.' end);
end $$;

create or replace function api.arquivo_confirmar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r jsonb := iara.arquivo_checar(p);
  v_fin text := p ->> 'finalidade';
  v_caminho text := p ->> 'caminho';
  v_mime text := p ->> 'mime';
  v_origem text := coalesce(nullif(p ->> 'origem', ''), case when iara.my_guardian() is not null then 'PORTAL' else 'UNIDADE' end);
  a iara.arquivos;
  d iara.documents;
  v_out jsonb;
begin
  if v_caminho is null or not starts_with(v_caminho, r ->> 'prefixo') or v_caminho ~ '\.\.' then
    raise exception 'Caminho do arquivo inválido.' using errcode = '22023';
  end if;
  if not (r -> 'tipos') ? v_mime or (p ->> 'tamanho')::int > (r ->> 'max_bytes')::int then
    raise exception 'Tipo ou tamanho de arquivo não aceito.' using errcode = '22023';
  end if;
  if v_origem not in ('PORTAL', 'IARA', 'WHATSAPP', 'UNIDADE', 'SEDUC') then v_origem := 'PORTAL'; end if;
  insert into iara.arquivos (caminho, finalidade, mime, tamanho, sha256, nome_original, student_id, staff_id, enviado_por_user, enviado_por_guardian, origem)
  values (v_caminho, v_fin, v_mime, (p ->> 'tamanho')::int, p ->> 'sha256', left(p ->> 'nome', 200), nullif(p ->> 'student_id', '')::uuid,
          nullif(p ->> 'staff_id', '')::uuid, iara.current_user_id(), iara.my_guardian(), v_origem)
  returning * into a;
  if v_fin = 'DOCUMENTO' then
    d := iara.documento_receber(a.student_id, p ->> 'doc_type', a.id, a.nome_original, v_origem);
    v_out := jsonb_build_object('ok', true, 'documento_id', d.id, 'status', d.status,
      'mensagem', case when d.status = 'RECEBIDO' then 'Documento recebido. A área responsável confere e você é avisado(a) aqui e pela IARA.' else 'Documento anexado e conferido.' end);
  elsif v_fin = 'FOTO_ALUNO' then
    v_out := iara.foto_aluno_receber(a.student_id, a.id, v_origem);
  elsif v_fin = 'FOTO_SERVIDOR' then
    update iara.staff set foto_arquivo_id = a.id where id = a.staff_id;
    perform iara.audit_event('FOTO_SERVIDOR', 'staff', a.staff_id::text, null, 'Foto do servidor atualizada.');
    v_out := jsonb_build_object('ok', true, 'aplicada', true, 'mensagem', 'Foto atualizada.');
  else
    v_out := jsonb_build_object('ok', true, 'mensagem', 'Arquivo recebido.');
  end if;
  return v_out || jsonb_build_object('arquivo_id', a.id);
end $$;

-- anexo recebido na conversa (IARA no portal ou WhatsApp) vira documento ou foto da criança escolhida
create or replace function api.arquivo_destinar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  a iara.arquivos;
  v_student uuid := (p ->> 'student_id')::uuid;
  d iara.documents;
begin
  select * into a from iara.arquivos where id = (p ->> 'arquivo_id')::uuid for update;
  if a.id is null or a.finalidade <> 'CONVERSA' or a.enviado_por_guardian is distinct from iara.my_guardian() then
    raise exception 'Arquivo não encontrado.' using errcode = 'P0002';
  end if;
  if not (v_student in (select iara.my_student_ids())) then raise exception 'Criança não vinculada a você.' using errcode = '42501'; end if;
  if p ->> 'destino' = 'FOTO' then
    if a.mime = 'application/pdf' then raise exception 'A foto precisa ser uma imagem (JPEG ou PNG).' using errcode = '22023'; end if;
    update iara.arquivos set finalidade = 'FOTO_ALUNO', student_id = v_student where id = a.id;
    return iara.foto_aluno_receber(v_student, a.id, a.origem);
  end if;
  if a.mime <> 'application/pdf' then
    raise exception 'Documento só em PDF. Foto (imagem) é aceita apenas como foto da criança.' using errcode = '22023';
  end if;
  if coalesce(p ->> 'doc_type', '') not in ('CERTIDAO', 'CPF', 'RG', 'COMPROVANTE_ENDERECO', 'CARTAO_SUS', 'VACINACAO', 'CADUNICO',
      'DECLARACAO_TRABALHO', 'LAUDO', 'GUARDA', 'DECISAO_JUDICIAL', 'TRANSFERENCIA') then
    raise exception 'Tipo de documento inválido.' using errcode = '22023';
  end if;
  update iara.arquivos set finalidade = 'DOCUMENTO', student_id = v_student where id = a.id;
  d := iara.documento_receber(v_student, p ->> 'doc_type', a.id, a.nome_original, a.origem);
  return jsonb_build_object('ok', true, 'documento_id', d.id, 'status', d.status,
    'mensagem', 'Documento recebido. A área responsável confere e você é avisado(a) aqui.');
end $$;

-- quem pode abrir o arquivo (família do aluno, gestão com escopo; documento exige permissão de documentos ou de alunos)
create or replace function api.arquivo_acesso(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  a iara.arquivos;
  v_ok boolean := false;
begin
  select * into a from iara.arquivos where id = (p ->> 'id')::uuid;
  if a.id is null then raise exception 'Arquivo não encontrado.' using errcode = 'P0002'; end if;
  if iara.my_guardian() is not null then
    v_ok := a.enviado_por_guardian = iara.my_guardian() or a.student_id in (select iara.my_student_ids());
  elsif a.student_id is not null then
    v_ok := (a.finalidade = 'FOTO_ALUNO' and ((iara.has_perm('students.read') and iara.can_access_student(a.student_id)) or iara.aluno_acesso(a.student_id, 'ocorrencias.read')))
         or ((iara.has_perm('documents.manage') or iara.has_perm('students.read')) and iara.can_access_student(a.student_id));
  elsif a.staff_id is not null then
    v_ok := a.staff_id = (select staff_id from iara.app_users where id = iara.current_user_id())
         or (iara.has_perm('pessoal.read') and iara.can_access_unit((select unit_id from iara.staff where id = a.staff_id)));
  end if;
  if not v_ok then raise exception 'Arquivo fora do seu escopo.' using errcode = '42501'; end if;
  if a.finalidade = 'DOCUMENTO' then
    perform iara.audit_event('DOCUMENTO_ABERTO', 'student', a.student_id::text, null, 'Arquivo de documento aberto.');
  end if;
  return jsonb_build_object('bucket', a.bucket, 'caminho', a.caminho, 'mime', a.mime, 'nome', coalesce(a.nome_original, 'arquivo'), 'tamanho', a.tamanho);
end $$;

-- 5. Documentos: ficha, decisão e o que a família vê ------------------------------------------------------------------------------
create or replace function iara.documento_json(d iara.documents) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', d.id, 'tipo', d.doc_type, 'status', d.status, 'arquivo_id', d.arquivo_id, 'nome', d.file_name,
    'mime', (select mime from iara.arquivos where id = d.arquivo_id), 'recebido_em', d.received_at, 'origem', d.origem,
    'enviado_pela_familia', d.enviado_por_guardian is not null, 'motivo_recusa', d.motivo_recusa, 'orientacao', d.orientacao,
    'validado_por', d.validado_por_label, 'decidido_em', coalesce(d.decidido_em, d.validated_at), 'is_demo', d.is_demo)
$$;

create or replace function api.aluno_documentos(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_fam boolean := iara.my_guardian() is not null;
begin
  if not ((v_fam and v_student in (select iara.my_student_ids()))
          or ((iara.has_perm('students.read') or iara.has_perm('documents.manage')) and iara.can_access_student(v_student))) then
    raise exception 'Aluno fora do seu escopo.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'documentos', (select coalesce(jsonb_agg(iara.documento_json(d) order by d.doc_type), '[]')
                   from (select distinct on (doc_type) * from iara.documents where student_id = v_student order by doc_type, created_at desc) d),
    'foto_arquivo_id', (select foto_arquivo_id from iara.students where id = v_student),
    'pode_enviar', v_fam or ((iara.has_perm('documents.manage') or iara.has_perm('students.write')) and iara.can_access_student(v_student)),
    'pode_validar', not v_fam and iara.pode_validar_aluno(v_student),
    'alteracoes', (select coalesce(jsonb_agg(iara.alteracao_json(a) order by a.created_at desc), '[]')
                   from (select * from iara.alteracoes_cadastrais where student_id = v_student order by created_at desc limit 20) a));
end $$;

create or replace function iara.avisar_familia(p_student uuid, p_evento text, p_titulo text, p_texto text) returns void
language sql security definer set search_path = iara, public
as $$
  insert into iara.notifications (tenant_id, guardian_id, student_id, channel, event_type, title, body, status)
  select 1, sg.guardian_id, p_student, 'PORTAL', p_evento, p_titulo, p_texto, 'ENVIADA'
  from iara.student_guardians sg where sg.student_id = p_student and sg.end_date is null and coalesce(sg.can_receive_notifications, true)
$$;

create or replace function api.documento_decidir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  d iara.documents;
  v_ok boolean := coalesce((p ->> 'aprovar')::boolean, false);
  v_motivo text := btrim(coalesce(p ->> 'motivo', ''));
  v_orient text := btrim(coalesce(p ->> 'orientacao', ''));
  v_nome text;
  v_tipo text;
begin
  select * into d from iara.documents where id = (p ->> 'id')::uuid for update;
  if d.id is null or not iara.pode_validar_aluno(d.student_id) then raise exception 'Documento não encontrado ou fora do seu escopo.' using errcode = 'P0002'; end if;
  if not v_ok and (length(v_motivo) < 5 or length(v_orient) < 10) then
    raise exception 'Para recusar, informe o motivo e como a família deve proceder.' using errcode = '22023';
  end if;
  update iara.documents set status = case when v_ok then 'VALIDADO' else 'REJEITADO' end,
         validated_at = case when v_ok then now() end, validated_by = iara.current_user_id(), validado_por_label = iara.my_label(), decidido_em = now(),
         motivo_recusa = case when v_ok then null else v_motivo end, orientacao = case when v_ok then null else v_orient end, updated_at = now()
  where id = d.id;
  select split_part(full_name, ' ', 1) into v_nome from iara.students where id = d.student_id;
  v_tipo := case d.doc_type when 'CERTIDAO' then 'Certidão de nascimento' when 'COMPROVANTE_ENDERECO' then 'Comprovante de endereço'
    when 'CARTAO_SUS' then 'Cartão SUS' when 'VACINACAO' then 'Carteira de vacinação' when 'CADUNICO' then 'Comprovante do CadÚnico'
    when 'DECLARACAO_TRABALHO' then 'Declaração de trabalho' when 'TRANSFERENCIA' then 'Declaração de transferência' when 'GUARDA' then 'Termo de guarda'
    when 'DECISAO_JUDICIAL' then 'Decisão judicial' when 'LAUDO' then 'Laudo' else d.doc_type end;
  if d.enviado_por_guardian is not null or not v_ok then
    perform iara.avisar_familia(d.student_id, case when v_ok then 'DOCUMENTO_VALIDADO' else 'DOCUMENTO_RECUSADO' end,
      case when v_ok then v_tipo || ' de ' || v_nome || ' validado(a) ✅' else v_tipo || ' de ' || v_nome || ': precisa reenviar' end,
      case when v_ok then 'A área responsável conferiu o documento. Não precisa fazer mais nada.'
           else 'Motivo: ' || v_motivo || '. Como proceder: ' || v_orient end);
  end if;
  perform iara.audit_event('DOCUMENTO_DECIDIDO', 'student', d.student_id::text, null,
    format('Documento %s %s.', d.doc_type, case when v_ok then 'validado' else 'recusado: ' || left(v_motivo, 120) end));
  return jsonb_build_object('ok', true);
end $$;

-- 6. Alterações cadastrais pedidas pela família ----------------------------------------------------------------------------------
create or replace function iara.alteracao_json(a iara.alteracoes_cadastrais) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', a.id, 'student_id', a.student_id, 'aluno', s.full_name, 'primeiro_nome', split_part(s.full_name, ' ', 1),
    'tipo', a.tipo, 'campos', a.campos, 'anteriores', a.anteriores, 'arquivo_id', a.arquivo_id, 'situacao', a.situacao, 'aplicada', a.aplicada,
    'area', a.area, 'unidade', (select short_name from iara.education_units where id = a.unit_id), 'motivo_recusa', a.motivo_recusa,
    'orientacao', a.orientacao, 'solicitado_por', a.solicitado_label, 'origem', a.origem, 'criado_em', a.created_at,
    'decidido_por', a.decidido_por_label, 'decidido_em', a.decidido_em, 'is_demo', a.is_demo)
  from (select 1) x left join iara.students s on s.id = a.student_id
$$;

-- campos que a família pode pedir para alterar (aplicados só depois da validação)
create or replace function api.familia_alterar_aluno(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  s iara.students;
  v_campos jsonb := '{}';
  v_ant jsonb := '{}';
  k text;
  v text;
  v_area record;
  v_id uuid;
  v_permitidos text[] := array['social_name', 'cpf', 'nis', 'sus_card', 'birth_certificate', 'race_color', 'nationality', 'birth_city', 'birth_state'];
begin
  if iara.my_guardian() is null or not (v_student in (select iara.my_student_ids())) then
    raise exception 'Criança não vinculada a você.' using errcode = '42501';
  end if;
  select * into s from iara.students where id = v_student;
  for k, v in select key, nullif(btrim(value), '') from jsonb_each_text(coalesce(p -> 'campos', '{}')) loop
    continue when not (k = any (v_permitidos));
    if k = 'race_color' and v is not null and v not in ('BRANCA', 'PRETA', 'PARDA', 'AMARELA', 'INDIGENA', 'NAO_DECLARADA') then
      raise exception 'Cor/raça inválida.' using errcode = '22023';
    end if;
    if k = 'nationality' and v is not null and v not in ('BRASILEIRA', 'NATURALIZADA', 'ESTRANGEIRA') then raise exception 'Nacionalidade inválida.' using errcode = '22023'; end if;
    if length(coalesce(v, '')) > 120 then raise exception 'Valor longo demais.' using errcode = '22023'; end if;
    if v is distinct from (to_jsonb(s) ->> k) then
      v_campos := v_campos || jsonb_build_object(k, v);
      v_ant := v_ant || jsonb_build_object(k, to_jsonb(s) -> k);
    end if;
  end loop;
  if v_campos = '{}'::jsonb then raise exception 'Nada mudou em relação ao cadastro.' using errcode = '22023'; end if;
  select * into v_area from iara.aluno_area(v_student);
  insert into iara.alteracoes_cadastrais (student_id, tipo, campos, anteriores, area, unit_id, solicitado_por_guardian, solicitado_label, origem)
  values (v_student, 'DADOS', v_campos, v_ant, v_area.area, v_area.unit_id, iara.my_guardian(), iara.my_label(), coalesce(nullif(p ->> 'origem', ''), 'PORTAL'))
  returning id into v_id;
  perform iara.audit_event('ALTERACAO_SOLICITADA', 'student', v_student::text, v_area.unit_id,
    'Família pediu alteração de dados da criança: ' || (select string_agg(key, ', ') from jsonb_object_keys(v_campos) key) || '.');
  return jsonb_build_object('ok', true, 'alteracao_id', v_id,
    'mensagem', case when v_area.area = 'UNIDADE' then 'Pedido enviado à secretaria da escola. Os dados mudam na ficha depois da conferência; você é avisado(a) aqui e pela IARA.'
                     else 'Pedido enviado à Central de Vagas. Os dados mudam na ficha depois da conferência; você é avisado(a) aqui e pela IARA.' end);
end $$;

-- mudança de endereço feita pela família (portal ou IARA) já vale para a fila; a área confere o comprovante
create or replace function iara.alteracao_endereco_familia() returns trigger
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_area record;
begin
  if iara.my_guardian() is null or new.address_id is not distinct from old.address_id then return new; end if;
  select * into v_area from iara.aluno_area(new.id);
  insert into iara.alteracoes_cadastrais (student_id, tipo, campos, anteriores, situacao, aplicada, area, unit_id, solicitado_por_guardian, solicitado_label, origem)
  values (new.id, 'ENDERECO',
          (select jsonb_build_object('address_id', a.id, 'endereco', concat_ws(', ', nullif(a.street, ''), nullif(a.number, ''), a.neighborhood)) from iara.addresses a where a.id = new.address_id),
          (select jsonb_build_object('address_id', a.id, 'endereco', concat_ws(', ', nullif(a.street, ''), nullif(a.number, ''), a.neighborhood)) from iara.addresses a where a.id = old.address_id),
          'PENDENTE', true, v_area.area, v_area.unit_id, iara.my_guardian(), iara.my_label(),
          case when exists (select 1 from iara.whatsapp_contacts w where w.guardian_id = iara.my_guardian()) then 'IARA' else 'PORTAL' end);
  return new;
end $$;
drop trigger if exists alteracao_endereco_familia on iara.students;
create trigger alteracao_endereco_familia after update of address_id on iara.students for each row execute function iara.alteracao_endereco_familia();

create or replace function api.alteracao_decidir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  a iara.alteracoes_cadastrais;
  v_ok boolean := coalesce((p ->> 'aprovar')::boolean, false);
  v_motivo text := btrim(coalesce(p ->> 'motivo', ''));
  v_orient text := btrim(coalesce(p ->> 'orientacao', ''));
  v_nome text;
begin
  select * into a from iara.alteracoes_cadastrais where id = (p ->> 'id')::uuid for update;
  if a.id is null or a.situacao <> 'PENDENTE' or not iara.pode_validar_aluno(a.student_id) then
    raise exception 'Pedido não encontrado, já decidido ou fora do seu escopo.' using errcode = 'P0002';
  end if;
  if not v_ok and (length(v_motivo) < 5 or length(v_orient) < 10) then
    raise exception 'Para recusar, informe o motivo e como a família deve proceder.' using errcode = '22023';
  end if;
  if v_ok and a.tipo = 'DADOS' then
    update iara.students s set
      social_name = case when a.campos ? 'social_name' then a.campos ->> 'social_name' else s.social_name end,
      cpf = case when a.campos ? 'cpf' then a.campos ->> 'cpf' else s.cpf end,
      nis = case when a.campos ? 'nis' then a.campos ->> 'nis' else s.nis end,
      sus_card = case when a.campos ? 'sus_card' then a.campos ->> 'sus_card' else s.sus_card end,
      birth_certificate = case when a.campos ? 'birth_certificate' then a.campos ->> 'birth_certificate' else s.birth_certificate end,
      race_color = case when a.campos ? 'race_color' then a.campos ->> 'race_color' else s.race_color end,
      nationality = case when a.campos ? 'nationality' then coalesce(a.campos ->> 'nationality', s.nationality) else s.nationality end,
      birth_city = case when a.campos ? 'birth_city' then a.campos ->> 'birth_city' else s.birth_city end,
      birth_state = case when a.campos ? 'birth_state' then a.campos ->> 'birth_state' else s.birth_state end,
      updated_at = now()
    where s.id = a.student_id;
  elsif v_ok and a.tipo = 'FOTO' then
    update iara.students set foto_arquivo_id = a.arquivo_id where id = a.student_id;
  elsif not v_ok and a.tipo = 'FOTO' and a.arquivo_id is not null then
    insert into iara.arquivos_descartar (caminho, bucket, motivo) select caminho, bucket, 'Foto recusada' from iara.arquivos where id = a.arquivo_id
    on conflict do nothing;
  end if;
  update iara.alteracoes_cadastrais set situacao = case when v_ok then 'APROVADA' else 'RECUSADA' end, aplicada = aplicada or v_ok,
         motivo_recusa = case when v_ok then null else v_motivo end, orientacao = case when v_ok then null else v_orient end,
         decidido_por_label = iara.my_label(), decidido_em = now()
  where id = a.id;
  select split_part(full_name, ' ', 1) into v_nome from iara.students where id = a.student_id;
  perform iara.avisar_familia(a.student_id, case when v_ok then 'ALTERACAO_APROVADA' else 'ALTERACAO_RECUSADA' end,
    case a.tipo when 'FOTO' then 'Foto de ' when 'ENDERECO' then 'Endereço de ' else 'Dados de ' end || v_nome || case when v_ok then ': conferido ✅' else ': precisa de ajuste' end,
    case when v_ok then case a.tipo when 'FOTO' then 'A nova foto já está na ficha.' when 'ENDERECO' then 'O novo endereço foi conferido.' else 'Os dados já estão atualizados na ficha.' end
         else 'Motivo: ' || v_motivo || '. Como proceder: ' || v_orient end);
  perform iara.audit_event('ALTERACAO_DECIDIDA', 'student', a.student_id::text, a.unit_id,
    format('Alteração cadastral (%s) %s.', lower(a.tipo), case when v_ok then 'aprovada' else 'recusada: ' || left(v_motivo, 120) end));
  return jsonb_build_object('ok', true);
end $$;

-- fila da área responsável: documentos recebidos e alterações pendentes do seu escopo
create or replace function api.validacoes_pendentes(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_area text := nullif(p ->> 'area', '');
begin
  if not (iara.has_perm('documents.manage') or iara.has_perm('students.write')) or iara.my_scope() not in ('UNIT', 'NETWORK') then
    raise exception 'Fila de validação da secretaria escolar e da Central de Vagas.' using errcode = '42501';
  end if;
  return (with docs as (
      select d as doc, d.id, d.student_id, d.received_at, (iara.aluno_area(d.student_id)).area area, (iara.aluno_area(d.student_id)).unit_id un
      from iara.documents d where d.status = 'RECEBIDO'),
    alts as (select * from iara.alteracoes_cadastrais where situacao = 'PENDENTE')
    select jsonb_build_object(
      'documentos', (select coalesce(jsonb_agg(iara.documento_json(x.doc) || jsonb_build_object('student_id', x.student_id,
                       'aluno', (select full_name from iara.students where id = x.student_id), 'area', x.area,
                       'unidade', (select short_name from iara.education_units where id = x.un)) order by x.received_at), '[]')
                     from (select * from docs where (v_unit is null or un = v_unit) and (v_area is null or area = v_area)
                             and (iara.my_scope() <> 'UNIT' or un = iara.my_unit()) order by received_at limit 200) x),
      'alteracoes', (select coalesce(jsonb_agg(iara.alteracao_json(a) order by a.created_at), '[]')
                     from (select * from alts where (v_unit is null or unit_id = v_unit) and (v_area is null or area = v_area)
                             and (iara.my_scope() <> 'UNIT' or unit_id = iara.my_unit()) order by created_at limit 200) a),
      'contagem', jsonb_build_object(
        'documentos', (select count(*) from docs where (v_unit is null or un = v_unit) and (iara.my_scope() <> 'UNIT' or un = iara.my_unit())),
        'alteracoes', (select count(*) from alts where (v_unit is null or unit_id = v_unit) and (iara.my_scope() <> 'UNIT' or unit_id = iara.my_unit())))));
end $$;

-- família: foto, documentos e pedidos de cada criança (portal e IARA)
create or replace function api.familia_documentos(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  return jsonb_build_object('criancas', (select coalesce(jsonb_agg(jsonb_build_object(
      'student_id', s.id, 'nome', s.full_name, 'primeiro_nome', split_part(s.full_name, ' ', 1), 'foto_arquivo_id', s.foto_arquivo_id,
      'foto_pendente', exists (select 1 from iara.alteracoes_cadastrais a where a.student_id = s.id and a.tipo = 'FOTO' and a.situacao = 'PENDENTE'),
      'dados', jsonb_build_object('social_name', s.social_name, 'cpf', iara.mascara_doc(s.cpf), 'nis', iara.mascara_doc(s.nis), 'sus_card', iara.mascara_doc(s.sus_card),
                                  'birth_certificate', iara.mascara_doc(s.birth_certificate), 'race_color', s.race_color, 'nationality', s.nationality,
                                  'birth_city', s.birth_city, 'birth_state', s.birth_state),
      'area', (iara.aluno_area(s.id)).area,
      'documentos', (select coalesce(jsonb_agg(iara.documento_json(d) order by d.doc_type), '[]')
                     from (select distinct on (doc_type) * from iara.documents where student_id = s.id order by doc_type, created_at desc) d),
      'alteracoes', (select coalesce(jsonb_agg(iara.alteracao_json(a) order by a.created_at desc), '[]')
                     from (select * from iara.alteracoes_cadastrais where student_id = s.id order by created_at desc limit 10) a))
      order by s.full_name), '[]')
    from iara.students s where s.id in (select iara.my_student_ids())),
    'pendencias', (select count(*) from iara.documents d where d.student_id in (select iara.my_student_ids()) and d.status in ('PENDENTE', 'REJEITADO')),
    'avisos', (select coalesce(jsonb_agg(jsonb_build_object('titulo', n.title, 'texto', n.body, 'em', n.created_at) order by n.created_at desc), '[]')
               from (select * from iara.notifications where guardian_id = iara.my_guardian()
                       and event_type in ('DOCUMENTO_RECUSADO', 'DOCUMENTO_VALIDADO', 'ALTERACAO_APROVADA', 'ALTERACAO_RECUSADA')
                     order by created_at desc limit 10) n));
end $$;

-- mostra só o final dos números de documento para a família (ex.: •••••6789)
create or replace function iara.mascara_doc(p text) returns text
language sql immutable as $$ select case when p is null or btrim(p) = '' then null else '•••••' || right(regexp_replace(p, '\D', '', 'g'), 4) end $$;

-- 7. Exclusões (alunos, responsáveis, profissionais) e cadastro de profissionais ----------------------------------------------------
create or replace function api.aluno_excluir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id uuid := (p ->> 'id')::uuid;
  v_motivo text := btrim(coalesce(p ->> 'motivo', ''));
  v_hist boolean;
  s iara.students;
begin
  perform iara.require_perm('students.write');
  select * into s from iara.students where id = v_id;
  if s.id is null or not iara.can_access_student(v_id) then raise exception 'Aluno não encontrado ou fora do seu escopo.' using errcode = 'P0002'; end if;
  if length(v_motivo) < 5 then raise exception 'Informe o motivo da exclusão.' using errcode = '22023'; end if;
  if v_id::text in (iara.setting('demo_student_ana'), iara.setting('demo_student_davi')) then
    raise exception 'Este aluno é o cenário da apresentação e não pode ser excluído.' using errcode = '42501';
  end if;
  v_hist := exists (select 1 from iara.enrollments where student_id = v_id) or exists (select 1 from iara.waiting_list_entries where student_id = v_id)
         or exists (select 1 from iara.service_cases where student_id = v_id) or exists (select 1 from iara.frequencia_faltas where student_id = v_id)
         or exists (select 1 from iara.ocorrencias where student_id = v_id) or exists (select 1 from iara.documents where student_id = v_id and status <> 'PENDENTE');
  if v_hist then
    -- com histórico escolar o cadastro não some: fica inativo, com o motivo na trilha
    update iara.students set status = 'INATIVO', updated_at = now() where id = v_id;
    perform iara.audit_event('ALUNO_INATIVADO', 'student', v_id::text, null, 'Cadastro inativado (tem histórico): ' || left(v_motivo, 200) || '.');
    return jsonb_build_object('ok', true, 'excluido', false, 'mensagem', 'O aluno tem histórico (matrícula, fila, frequência ou documentos): o cadastro foi inativado, não apagado.');
  end if;
  begin
    delete from iara.students where id = v_id;
  exception when foreign_key_violation then
    update iara.students set status = 'INATIVO', updated_at = now() where id = v_id;
    perform iara.audit_event('ALUNO_INATIVADO', 'student', v_id::text, null, 'Cadastro inativado (há registros vinculados): ' || left(v_motivo, 200) || '.');
    return jsonb_build_object('ok', true, 'excluido', false, 'mensagem', 'Há registros vinculados ao aluno: o cadastro foi inativado, não apagado.');
  end;
  perform iara.audit_event('ALUNO_EXCLUIDO', 'student', v_id::text, null, 'Cadastro excluído (sem histórico): ' || left(v_motivo, 200) || '.');
  return jsonb_build_object('ok', true, 'excluido', true, 'mensagem', 'Cadastro excluído.');
end $$;

create or replace function api.responsavel_excluir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id uuid := (p ->> 'id')::uuid;
  v_motivo text := btrim(coalesce(p ->> 'motivo', ''));
begin
  if not (iara.has_perm('guardians.write') or iara.has_perm('students.write')) then raise exception 'Sem permissão.' using errcode = '42501'; end if;
  if not exists (select 1 from iara.guardians where id = v_id) then raise exception 'Responsável não encontrado.' using errcode = 'P0002'; end if;
  if iara.my_scope() = 'UNIT' and not exists (select 1 from iara.student_guardians sg where sg.guardian_id = v_id and sg.student_id in (select iara.unidade_alunos(iara.my_unit())))
     and exists (select 1 from iara.student_guardians where guardian_id = v_id) then
    raise exception 'Responsável fora do seu escopo.' using errcode = '42501';
  end if;
  if length(v_motivo) < 5 then raise exception 'Informe o motivo da exclusão.' using errcode = '22023'; end if;
  if v_id::text in (iara.setting('demo_guardian_maria'), iara.setting('demo_guardian_jorge')) then
    raise exception 'Este responsável é o cenário da apresentação e não pode ser excluído.' using errcode = '42501';
  end if;
  if exists (select 1 from iara.student_guardians where guardian_id = v_id and end_date is null) then
    raise exception 'O responsável ainda está vinculado a uma criança. Encerre o vínculo na ficha da criança antes de excluir.' using errcode = '22023';
  end if;
  if exists (select 1 from iara.service_cases where guardian_id = v_id) or exists (select 1 from iara.app_users where guardian_id = v_id) then
    raise exception 'O responsável tem atendimentos ou acesso ao portal; o cadastro é mantido para a trilha. Atualize os dados em vez de excluir.' using errcode = '22023';
  end if;
  begin
    delete from iara.guardians where id = v_id;
  exception when foreign_key_violation then
    raise exception 'O responsável tem registros vinculados (fila, avisos ou documentos); o cadastro é mantido. Atualize os dados em vez de excluir.' using errcode = '22023';
  end;
  perform iara.audit_event('RESPONSAVEL_EXCLUIDO', 'guardian', v_id::text, null, 'Cadastro de responsável excluído: ' || left(v_motivo, 200) || '.');
  return jsonb_build_object('ok', true, 'mensagem', 'Cadastro excluído.');
end $$;

create or replace function api.pessoal_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id uuid := nullif(p ->> 'id', '')::uuid;
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_nome text := btrim(coalesce(p ->> 'nome', ''));
  v_role text := coalesce(nullif(p ->> 'funcao', ''), 'PROFESSOR');
  v_sit text := coalesce(nullif(p ->> 'situacao', ''), 'ATIVO');
  v_ch integer := nullif(p ->> 'ch', '')::int;
  s iara.staff;
begin
  perform iara.require_perm('pessoal.write');
  if length(v_nome) < 5 then raise exception 'Informe o nome completo.' using errcode = '22023'; end if;
  if v_role not in ('PROFESSOR', 'EDUCADOR', 'AUXILIAR', 'APOIO', 'AEE', 'ESTAGIARIO', 'SUBSTITUTO') then raise exception 'Função inválida.' using errcode = '22023'; end if;
  if v_sit not in ('ATIVO', 'LICENCA', 'AFASTADO', 'DESLIGADO') then raise exception 'Situação inválida.' using errcode = '22023'; end if;
  if v_ch is not null and v_ch not in (20, 30, 40) then raise exception 'Jornada deve ser 20, 30 ou 40 horas.' using errcode = '22023'; end if;
  if v_unit is null or not iara.can_access_unit(v_unit) then raise exception 'Unidade fora do seu escopo.' using errcode = '42501'; end if;
  if nullif(p ->> 'matricula', '') is not null and exists (select 1 from iara.staff where matricula_funcional = p ->> 'matricula' and id is distinct from v_id) then
    raise exception 'Já existe servidor com esta matrícula funcional.' using errcode = '23505';
  end if;
  if v_id is not null then
    select * into s from iara.staff where id = v_id for update;
    if s.id is null or not iara.can_access_unit(s.unit_id) then raise exception 'Servidor fora do seu escopo.' using errcode = '42501'; end if;
    if s.unit_id is distinct from v_unit then
      update iara.staff_lotacoes set fim = current_date where staff_id = s.id and fim is null;
      insert into iara.staff_lotacoes (staff_id, unit_id, funcao, inicio, motivo, is_demo) values (s.id, v_unit, v_role, current_date, 'Remoção registrada no cadastro', false);
    end if;
    update iara.staff set full_name = v_nome, role = v_role, unit_id = v_unit, bond = nullif(p ->> 'vinculo', ''), matricula_funcional = nullif(p ->> 'matricula', ''),
           cargo = nullif(p ->> 'cargo', ''), carga_horaria_semanal = v_ch, data_admissao = nullif(p ->> 'admissao', '')::date,
           escolaridade = nullif(p ->> 'escolaridade', ''), formacao = nullif(p ->> 'formacao', ''), area_atuacao = nullif(p ->> 'area', ''), situacao = v_sit
    where id = s.id returning * into s;
    perform iara.audit_event('SERVIDOR_ALTERADO', 'staff', s.id::text, v_unit, 'Cadastro do servidor alterado.');
  else
    insert into iara.staff (tenant_id, unit_id, full_name, role, bond, matricula_funcional, cargo, carga_horaria_semanal, data_admissao, escolaridade, formacao,
                            area_atuacao, situacao, is_demo)
    values (1, v_unit, v_nome, v_role, nullif(p ->> 'vinculo', ''), nullif(p ->> 'matricula', ''), nullif(p ->> 'cargo', ''), v_ch,
            nullif(p ->> 'admissao', '')::date, nullif(p ->> 'escolaridade', ''), nullif(p ->> 'formacao', ''), nullif(p ->> 'area', ''), v_sit, false)
    returning * into s;
    insert into iara.staff_lotacoes (staff_id, unit_id, funcao, inicio, motivo, is_demo) values (s.id, v_unit, v_role, current_date, 'Inclusão no cadastro', false);
    perform iara.audit_event('SERVIDOR_INCLUIDO', 'staff', s.id::text, v_unit, 'Servidor incluído no cadastro.');
  end if;
  return jsonb_build_object('ok', true, 'id', s.id);
end $$;

create or replace function api.pessoal_excluir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  s iara.staff;
  v_motivo text := btrim(coalesce(p ->> 'motivo', ''));
  v_hist boolean;
begin
  perform iara.require_perm('pessoal.write');
  select * into s from iara.staff where id = (p ->> 'id')::uuid for update;
  if s.id is null or not iara.can_access_unit(s.unit_id) then raise exception 'Servidor fora do seu escopo.' using errcode = '42501'; end if;
  if length(v_motivo) < 5 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
  if exists (select 1 from iara.app_users where staff_id = s.id) then
    raise exception 'O servidor tem acesso ao sistema; desligue-o (situação Desligado) em vez de excluir.' using errcode = '22023';
  end if;
  v_hist := exists (select 1 from iara.class_staff where staff_id = s.id) or exists (select 1 from iara.horarios_turma where staff_id = s.id)
         or exists (select 1 from iara.mediacoes where staff_id = s.id) or s.is_demo;
  if v_hist then
    -- com turmas ou horário: desliga, libera as aulas e encerra a lotação; a ficha fica para o histórico
    update iara.horarios_turma set staff_id = null where staff_id = s.id;
    delete from iara.class_staff where staff_id = s.id;
    update iara.mediacoes set fim = current_date where staff_id = s.id and fim is null;
    update iara.staff_lotacoes set fim = current_date where staff_id = s.id and fim is null;
    update iara.staff set situacao = 'DESLIGADO' where id = s.id;
    perform iara.audit_event('SERVIDOR_DESLIGADO', 'staff', s.id::text, s.unit_id, 'Servidor desligado; aulas liberadas: ' || left(v_motivo, 200) || '.');
    return jsonb_build_object('ok', true, 'excluido', false, 'mensagem', 'Servidor desligado: as aulas dele voltaram para a lista de aulas sem professor.');
  end if;
  begin
    delete from iara.staff where id = s.id;
  exception when foreign_key_violation then
    update iara.staff set situacao = 'DESLIGADO' where id = s.id;
    perform iara.audit_event('SERVIDOR_DESLIGADO', 'staff', s.id::text, s.unit_id, 'Servidor desligado (há registros vinculados): ' || left(v_motivo, 200) || '.');
    return jsonb_build_object('ok', true, 'excluido', false, 'mensagem', 'Há registros vinculados ao servidor: ele foi desligado, não apagado.');
  end;
  perform iara.audit_event('SERVIDOR_EXCLUIDO', 'staff', s.id::text, s.unit_id, 'Cadastro excluído (sem histórico): ' || left(v_motivo, 200) || '.');
  return jsonb_build_object('ok', true, 'excluido', true, 'mensagem', 'Cadastro excluído.');
end $$;

-- 8. Materiais ------------------------------------------------------------------------------------------------------------------
create or replace function iara.material_json(m iara.materiais) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', m.id, 'unit_id', m.unit_id, 'unidade', coalesce((select short_name from iara.education_units where id = m.unit_id), 'Almoxarifado central (SEDUC)'),
    'codigo', m.codigo, 'nome', m.nome, 'categoria', m.categoria, 'unidade_medida', m.unidade_medida, 'quantidade', m.quantidade, 'minimo', m.minimo,
    'abaixo_minimo', m.quantidade < m.minimo, 'patrimonio', m.patrimonio, 'estado', m.estado, 'localizacao', m.localizacao, 'observacao', m.observacao,
    'ativo', m.ativo, 'atualizado_por', m.atualizado_por_label, 'atualizado_em', m.updated_at, 'is_demo', m.is_demo)
$$;

create or replace function api.materiais_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_scope text := iara.my_scope();
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_central boolean := coalesce((p ->> 'central')::boolean, false);
  v_q text := nullif(iara.norm(btrim(coalesce(p ->> 'busca', ''))), '');
  v_lim integer := least(greatest(coalesce(nullif(p ->> 'limite', '')::int, 60), 1), 200);
  v_off integer := greatest(coalesce(nullif(p ->> 'offset', '')::int, 0), 0);
begin
  perform iara.require_perm('materiais.read');
  return (with base as (
      select m as mat, m.quantidade, m.minimo, m.categoria, m.nome from iara.materiais m
      where (coalesce((p ->> 'inativos')::boolean, false) or m.ativo)
        and (case when v_scope = 'UNIT' then m.unit_id = v_unit when v_central then m.unit_id is null when v_unit is not null then m.unit_id = v_unit else true end)
        and (nullif(p ->> 'categoria', '') is null or m.categoria = p ->> 'categoria')
        and (not coalesce((p ->> 'abaixo_minimo')::boolean, false) or m.quantidade < m.minimo)
        and (v_q is null or iara.norm(m.nome) like '%' || v_q || '%' or m.codigo = btrim(p ->> 'busca') or m.patrimonio = btrim(p ->> 'busca')))
    select jsonb_build_object(
      'total', (select count(*) from base),
      'abaixo_minimo', (select count(*) from base where quantidade < minimo),
      'por_categoria', (select coalesce(jsonb_object_agg(categoria, n), '{}') from (select categoria, count(*) n from base group by 1) z),
      'pode_editar', iara.has_perm('materiais.write'),
      'itens', (select coalesce(jsonb_agg(iara.material_json(x.mat) order by x.ord), '[]')
                from (select b.mat, row_number() over (order by (b.quantidade < b.minimo) desc, b.categoria, iara.norm(b.nome)) ord
                      from base b order by ord limit v_lim offset v_off) x)));
end $$;

create or replace function api.material_detalhe(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  m iara.materiais;
begin
  perform iara.require_perm('materiais.read');
  select * into m from iara.materiais where id = (p ->> 'id')::uuid;
  if m.id is null or (iara.my_scope() = 'UNIT' and m.unit_id is distinct from iara.my_unit()) then raise exception 'Material não encontrado.' using errcode = 'P0002'; end if;
  return iara.material_json(m) || jsonb_build_object('movimentos', (select coalesce(jsonb_agg(jsonb_build_object('tipo', v.tipo, 'quantidade', v.quantidade,
           'saldo', v.saldo, 'motivo', v.motivo, 'autor', v.autor_label, 'em', v.created_at) order by v.created_at desc), '[]')
         from (select * from iara.materiais_movimentos where material_id = m.id order by created_at desc limit 50) v));
end $$;

create or replace function api.material_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id uuid := nullif(p ->> 'id', '')::uuid;
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_nome text := btrim(coalesce(p ->> 'nome', ''));
  v_cat text := coalesce(nullif(p ->> 'categoria', ''), 'OUTRO');
  m iara.materiais;
begin
  perform iara.require_perm('materiais.write');
  if iara.my_scope() not in ('UNIT', 'NETWORK') then raise exception 'Sem escopo para materiais.' using errcode = '42501'; end if;
  if length(v_nome) < 3 then raise exception 'Informe o nome do material.' using errcode = '22023'; end if;
  if v_cat not in ('PEDAGOGICO', 'LIMPEZA', 'ESCRITORIO', 'ALIMENTO', 'UNIFORME', 'EQUIPAMENTO', 'MOBILIARIO', 'OUTRO') then raise exception 'Categoria inválida.' using errcode = '22023'; end if;
  if nullif(p ->> 'estado', '') is not null and p ->> 'estado' not in ('NOVO', 'BOM', 'REGULAR', 'RUIM', 'INSERVIVEL') then raise exception 'Estado inválido.' using errcode = '22023'; end if;
  if coalesce(nullif(p ->> 'minimo', '')::numeric, 0) < 0 then raise exception 'Mínimo não pode ser negativo.' using errcode = '22023'; end if;
  if v_id is null then
    insert into iara.materiais (unit_id, codigo, nome, categoria, unidade_medida, quantidade, minimo, patrimonio, estado, localizacao, observacao, atualizado_por_label)
    values (v_unit, nullif(btrim(coalesce(p ->> 'codigo', '')), ''), v_nome, v_cat, coalesce(nullif(p ->> 'unidade_medida', ''), 'unidade'),
            greatest(coalesce(nullif(p ->> 'quantidade', '')::numeric, 0), 0), coalesce(nullif(p ->> 'minimo', '')::numeric, 0),
            nullif(btrim(coalesce(p ->> 'patrimonio', '')), ''), nullif(p ->> 'estado', ''), nullif(btrim(coalesce(p ->> 'localizacao', '')), ''),
            nullif(btrim(coalesce(p ->> 'observacao', '')), ''), iara.my_label())
    returning * into m;
    if m.quantidade > 0 then
      insert into iara.materiais_movimentos (material_id, tipo, quantidade, saldo, motivo, autor_label) values (m.id, 'ENTRADA', m.quantidade, m.quantidade, 'Cadastro inicial', iara.my_label());
    end if;
    perform iara.audit_event('MATERIAL_INCLUIDO', 'material', m.id::text, v_unit, 'Material incluído: ' || left(v_nome, 80) || '.');
  else
    select * into m from iara.materiais where id = v_id for update;
    if m.id is null or (iara.my_scope() = 'UNIT' and m.unit_id is distinct from iara.my_unit()) then raise exception 'Material fora do seu escopo.' using errcode = '42501'; end if;
    update iara.materiais set nome = v_nome, codigo = nullif(btrim(coalesce(p ->> 'codigo', '')), ''), categoria = v_cat,
           unidade_medida = coalesce(nullif(p ->> 'unidade_medida', ''), unidade_medida), minimo = coalesce(nullif(p ->> 'minimo', '')::numeric, minimo),
           patrimonio = nullif(btrim(coalesce(p ->> 'patrimonio', '')), ''), estado = nullif(p ->> 'estado', ''),
           localizacao = nullif(btrim(coalesce(p ->> 'localizacao', '')), ''), observacao = nullif(btrim(coalesce(p ->> 'observacao', '')), ''),
           unit_id = case when iara.my_scope() = 'UNIT' then unit_id else v_unit end, atualizado_por_label = iara.my_label(), updated_at = now()
    where id = m.id returning * into m;
    perform iara.audit_event('MATERIAL_ALTERADO', 'material', m.id::text, m.unit_id, 'Material alterado: ' || left(v_nome, 80) || '.');
  end if;
  return iara.material_json(m);
end $$;

create or replace function api.material_movimentar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  m iara.materiais;
  v_tipo text := p ->> 'tipo';
  v_q numeric := nullif(p ->> 'quantidade', '')::numeric;
  v_saldo numeric;
begin
  perform iara.require_perm('materiais.write');
  select * into m from iara.materiais where id = (p ->> 'id')::uuid for update;
  if m.id is null or (iara.my_scope() = 'UNIT' and m.unit_id is distinct from iara.my_unit()) then raise exception 'Material fora do seu escopo.' using errcode = '42501'; end if;
  if v_tipo not in ('ENTRADA', 'SAIDA', 'AJUSTE') or v_q is null or v_q < 0 or (v_tipo <> 'AJUSTE' and v_q = 0) then
    raise exception 'Movimento inválido.' using errcode = '22023';
  end if;
  v_saldo := case v_tipo when 'ENTRADA' then m.quantidade + v_q when 'SAIDA' then m.quantidade - v_q else v_q end;
  if v_saldo < 0 then raise exception 'Saída maior que o estoque (% %).', m.quantidade, m.unidade_medida using errcode = '22023'; end if;
  if v_tipo = 'AJUSTE' and length(btrim(coalesce(p ->> 'motivo', ''))) < 5 then raise exception 'Ajuste de inventário pede o motivo.' using errcode = '22023'; end if;
  update iara.materiais set quantidade = v_saldo, atualizado_por_label = iara.my_label(), updated_at = now() where id = m.id;
  insert into iara.materiais_movimentos (material_id, tipo, quantidade, saldo, motivo, autor_label)
  values (m.id, v_tipo, case when v_tipo = 'AJUSTE' then v_saldo - m.quantidade else v_q end, v_saldo, nullif(btrim(coalesce(p ->> 'motivo', '')), ''), iara.my_label());
  return api.material_detalhe(jsonb_build_object('id', m.id));
end $$;

create or replace function api.material_excluir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  m iara.materiais;
  v_motivo text := btrim(coalesce(p ->> 'motivo', ''));
begin
  perform iara.require_perm('materiais.write');
  select * into m from iara.materiais where id = (p ->> 'id')::uuid for update;
  if m.id is null or (iara.my_scope() = 'UNIT' and m.unit_id is distinct from iara.my_unit()) then raise exception 'Material fora do seu escopo.' using errcode = '42501'; end if;
  if length(v_motivo) < 5 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
  if exists (select 1 from iara.materiais_movimentos where material_id = m.id and motivo is distinct from 'Cadastro inicial') or m.patrimonio is not null then
    update iara.materiais set ativo = false, observacao = coalesce(observacao || ' · ', '') || 'Baixa: ' || v_motivo, atualizado_por_label = iara.my_label(), updated_at = now()
    where id = m.id;
    perform iara.audit_event('MATERIAL_BAIXA', 'material', m.id::text, m.unit_id, 'Baixa de material: ' || left(v_motivo, 120) || '.');
    return jsonb_build_object('ok', true, 'excluido', false, 'mensagem', 'O material tem movimentação ou patrimônio: foi dado baixa (fica no histórico).');
  end if;
  perform iara.audit_event('MATERIAL_EXCLUIDO', 'material', m.id::text, m.unit_id, 'Material excluído: ' || left(v_motivo, 120) || '.');
  delete from iara.materiais where id = m.id;
  return jsonb_build_object('ok', true, 'excluido', true, 'mensagem', 'Material excluído.');
end $$;

-- 9. Demonstração ---------------------------------------------------------------------------------------------------------------
create or replace function iara.demo_gerar_materiais() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.materiais where is_demo;
  insert into iara.materiais (unit_id, codigo, nome, categoria, unidade_medida, quantidade, minimo, patrimonio, estado, localizacao, atualizado_por_label, is_demo)
  select u.id, t.cod, t.nome, t.cat, t.um,
         greatest(0, round(t.base * (0.2 + (abs(hashtext(u.id::text || t.cod)) % 160) / 100.0))),
         t.minimo, case when t.cat in ('EQUIPAMENTO', 'MOBILIARIO') then 'PMM-' || lpad((abs(hashtext(u.id::text || t.cod)) % 900000 + 100000)::text, 6, '0') end,
         case when t.cat in ('EQUIPAMENTO', 'MOBILIARIO') then (array['NOVO', 'BOM', 'BOM', 'REGULAR', 'RUIM'])[1 + abs(hashtext(t.cod || u.id::text)) % 5] end,
         t.local, 'Secretaria da unidade (demonstração)', true
  from iara.education_units u
  cross join (values
    ('PED-001', 'Papel sulfite A4 (resma)', 'PEDAGOGICO', 'resma', 40, 10, 'Almoxarifado'),
    ('PED-002', 'Lápis de cor (caixa com 12)', 'PEDAGOGICO', 'caixa', 60, 15, 'Almoxarifado'),
    ('PED-003', 'Massinha de modelar', 'PEDAGOGICO', 'pote', 80, 20, 'Almoxarifado'),
    ('PED-004', 'Cola escolar 90 g', 'PEDAGOGICO', 'unidade', 70, 20, 'Almoxarifado'),
    ('PED-005', 'Livro de literatura infantil', 'PEDAGOGICO', 'unidade', 120, 0, 'Biblioteca'),
    ('LIM-001', 'Detergente neutro 5 L', 'LIMPEZA', 'galão', 12, 4, 'Depósito de limpeza'),
    ('LIM-002', 'Papel higiênico (fardo)', 'LIMPEZA', 'fardo', 20, 6, 'Depósito de limpeza'),
    ('LIM-003', 'Sabonete líquido 5 L', 'LIMPEZA', 'galão', 10, 3, 'Depósito de limpeza'),
    ('ESC-001', 'Caneta azul (caixa com 50)', 'ESCRITORIO', 'caixa', 6, 2, 'Secretaria'),
    ('ESC-002', 'Toner da impressora', 'ESCRITORIO', 'unidade', 4, 1, 'Secretaria'),
    ('UNI-001', 'Camiseta do uniforme (tam. 6)', 'UNIFORME', 'unidade', 40, 10, 'Secretaria'),
    ('UNI-002', 'Agasalho do uniforme (tam. 8)', 'UNIFORME', 'unidade', 30, 8, 'Secretaria'),
    ('EQP-001', 'Notebook da secretaria', 'EQUIPAMENTO', 'unidade', 2, 0, 'Secretaria'),
    ('EQP-002', 'Projetor multimídia', 'EQUIPAMENTO', 'unidade', 1, 0, 'Sala de recursos'),
    ('EQP-003', 'Geladeira da cozinha', 'EQUIPAMENTO', 'unidade', 1, 0, 'Cozinha'),
    ('MOB-001', 'Conjunto mesa e cadeira infantil', 'MOBILIARIO', 'conjunto', 120, 0, 'Salas de aula'),
    ('MOB-002', 'Armário de aço', 'MOBILIARIO', 'unidade', 8, 0, 'Salas de aula')) t(cod, nome, cat, um, base, minimo, local)
  where u.status = 'ATIVA' and exists (select 1 from iara.classes c where c.unit_id = u.id and c.status = 'ATIVA');
  -- almoxarifado central da SEDUC
  insert into iara.materiais (unit_id, codigo, nome, categoria, unidade_medida, quantidade, minimo, localizacao, atualizado_por_label, is_demo)
  values (null, 'PED-001', 'Papel sulfite A4 (resma)', 'PEDAGOGICO', 'resma', 1800, 500, 'Almoxarifado central', 'Almoxarifado SEDUC (demonstração)', true),
         (null, 'LIM-002', 'Papel higiênico (fardo)', 'LIMPEZA', 'fardo', 420, 600, 'Almoxarifado central', 'Almoxarifado SEDUC (demonstração)', true),
         (null, 'UNI-001', 'Camiseta do uniforme (tam. 6)', 'UNIFORME', 'unidade', 2600, 1000, 'Almoxarifado central', 'Almoxarifado SEDUC (demonstração)', true),
         (null, 'ALI-001', 'Arroz tipo 1 (5 kg)', 'ALIMENTO', 'pacote', 950, 400, 'Almoxarifado da alimentação', 'Almoxarifado SEDUC (demonstração)', true),
         (null, 'ALI-002', 'Feijão carioca (1 kg)', 'ALIMENTO', 'pacote', 300, 500, 'Almoxarifado da alimentação', 'Almoxarifado SEDUC (demonstração)', true);
  insert into iara.materiais_movimentos (material_id, tipo, quantidade, saldo, motivo, autor_label, created_at, is_demo)
  select m.id, 'ENTRADA', m.quantidade, m.quantidade, 'Cadastro inicial', m.atualizado_por_label, now() - interval '60 days', true
  from iara.materiais m where m.is_demo and m.quantidade > 0;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('materiais', (select count(*) from iara.materiais where is_demo),
    'abaixo_minimo', (select count(*) from iara.materiais where is_demo and quantidade < minimo));
end $$;

-- pedidos de alteração de demonstração (sem arquivo): dados da criança e endereço a conferir na unidade da apresentação e na rede
create or replace function iara.demo_gerar_alteracoes() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_unit integer := nullif(iara.setting('demo_unit_maria'), '')::int;
  v_ana uuid := nullif(iara.setting('demo_student_ana'), '')::uuid;
begin
  delete from iara.alteracoes_cadastrais where is_demo;
  insert into iara.alteracoes_cadastrais (student_id, tipo, campos, anteriores, situacao, aplicada, area, unit_id, solicitado_label, origem, created_at, is_demo)
  select e.student_id, case when x.h % 3 = 0 then 'ENDERECO' else 'DADOS' end,
         case when x.h % 3 = 0 then jsonb_build_object('endereco', 'Rua das Palmeiras, ' || (x.h % 900 + 10) || ', ' || coalesce(a.neighborhood, 'Zona 7'))
              when x.h % 3 = 1 then jsonb_build_object('sus_card', '7' || lpad((x.h % 100000000)::text, 14, '0'))
              else jsonb_build_object('nis', '2' || lpad((x.h % 1000000000)::text, 10, '0')) end,
         case when x.h % 3 = 0 then jsonb_build_object('endereco', concat_ws(', ', nullif(a.street, ''), nullif(a.number, ''), a.neighborhood))
              when x.h % 3 = 1 then jsonb_build_object('sus_card', s.sus_card) else jsonb_build_object('nis', s.nis) end,
         'PENDENTE', x.h % 3 = 0, 'UNIDADE', e.unit_id, 'Família (demonstração)', (array['PORTAL', 'IARA'])[1 + x.h % 2],
         now() - make_interval(hours => 2 + x.h % 70), true
  from iara.enrollments e join iara.students s on s.id = e.student_id left join iara.addresses a on a.id = s.address_id
  cross join lateral (select abs(hashtext(e.student_id::text || 'alt')) h) x
  where e.status = 'ACTIVE' and e.student_id is distinct from v_ana
    and (case when e.unit_id = v_unit then x.h % 100 < 4 else x.h % 1000 < 3 end);
  return jsonb_build_object('alteracoes', (select count(*) from iara.alteracoes_cadastrais where is_demo));
end $$;

-- limpeza: módulos novos e lançamentos ao vivo (arquivos vão para a fila de descarte do Storage)
create or replace function iara.demo_limpar_arquivos_vivos(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  d timestamptz := coalesce(p_desde, '-infinity'::timestamptz);
  v jsonb := '{}';
  n integer;
begin
  if not iara.demo_mode() then raise exception 'Limpeza disponível apenas no modo demonstração.' using errcode = '42501'; end if;
  insert into iara.arquivos_descartar (caminho, bucket, motivo)
  select caminho, bucket, 'Limpeza da demonstração' from iara.arquivos where not is_demo and created_at >= d on conflict do nothing;
  get diagnostics n = row_count; v := v || jsonb_build_object('arquivos_descartar', n);
  update iara.students set foto_arquivo_id = null where foto_arquivo_id in (select id from iara.arquivos where not is_demo and created_at >= d);
  update iara.staff set foto_arquivo_id = null where foto_arquivo_id in (select id from iara.arquivos where not is_demo and created_at >= d);
  delete from iara.documents where not is_demo and created_at >= d and arquivo_id is not null; get diagnostics n = row_count; v := v || jsonb_build_object('documentos', n);
  update iara.documents set arquivo_id = null, status = 'PENDENTE', origem = null, enviado_por_guardian = null, motivo_recusa = null, orientacao = null,
         validado_por_label = null, decidido_em = null
  where is_demo and arquivo_id in (select id from iara.arquivos where not is_demo and created_at >= d);
  delete from iara.alteracoes_cadastrais where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('alteracoes', n);
  delete from iara.arquivos where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('arquivos', n);
  delete from iara.materiais where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('materiais', n);
  delete from iara.materiais_movimentos where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('materiais_movimentos', n);
  delete from iara.notifications where created_at >= d and event_type in ('DOCUMENTO_RECUSADO', 'DOCUMENTO_VALIDADO', 'ALTERACAO_APROVADA', 'ALTERACAO_RECUSADA');
  get diagnostics n = row_count; v := v || jsonb_build_object('avisos', n);
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
  r := r || jsonb_build_object('vida_escolar', iara.demo_purge_sprint1(null), 'arquivos', iara.demo_limpar_arquivos_vivos(null));
  return jsonb_build_object('ok', true, 'resultado', r, 'situacao', api.demo_apresentacao_situacao('{}'::jsonb));
end $$;

-- o gateway apaga do Storage o que está na fila de descarte (housekeeping)
create or replace function iara.arquivos_para_descartar(p_lim integer default 100) returns jsonb
language sql stable security definer set search_path = iara, public
as $$ select coalesce(jsonb_agg(jsonb_build_object('caminho', caminho, 'bucket', bucket)), '[]') from (select * from iara.arquivos_descartar order by created_at limit p_lim) z $$;
create or replace function iara.arquivos_descartados(p_caminhos text[]) returns integer
language sql security definer set search_path = iara, public
as $$ with d as (delete from iara.arquivos_descartar where caminho = any (p_caminhos) returning 1) select count(*)::int from d $$;

revoke all on function iara.demo_gerar_materiais(), iara.demo_gerar_alteracoes(), iara.demo_limpar_arquivos_vivos(timestamptz),
  iara.arquivos_para_descartar(integer), iara.arquivos_descartados(text[]), iara.documento_receber(uuid, text, uuid, text, text),
  iara.foto_aluno_receber(uuid, uuid, text) from public;

-- 10. Classificação --------------------------------------------------------------------------------------------------------------
insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('arquivos', 'nome_original', 'PESSOAL', 'documento', 'identificar o arquivo enviado', 'bucket privado; acesso pelo gateway com escopo e trilha'),
  ('documents', 'validado_por_label', 'PESSOAL', 'identificação', 'auditoria (quem decidiu)', null),
  ('alteracoes_cadastrais', 'solicitado_label', 'PESSOAL', 'identificação', 'auditoria (quem pediu)', null),
  ('alteracoes_cadastrais', 'decidido_por_label', 'PESSOAL', 'identificação', 'auditoria (quem decidiu)', null),
  ('alteracoes_cadastrais', 'campos', 'SENSIVEL', 'documento/identificação da criança', 'alteração cadastral pedida pela família', 'só a área responsável e a família'),
  ('alteracoes_cadastrais', 'anteriores', 'SENSIVEL', 'documento/identificação da criança', 'trilha do valor anterior', 'só a área responsável e a família')
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

-- 11. Ficha do servidor com foto e o que o perfil pode fazer nela (redefinida de 043)
create or replace function api.pessoal_ficha(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  s iara.staff;
  c record;
begin
  select * into s from iara.staff where id = (p ->> 'id')::uuid;
  if s.id is null then raise exception 'Servidor não encontrado.' using errcode = 'P0002'; end if;
  -- o próprio servidor vê a sua ficha; a gestão, conforme a permissão e o escopo
  if not (s.id = (select staff_id from iara.app_users where id = iara.current_user_id())
          or (iara.has_perm('pessoal.read') and iara.can_access_unit(s.unit_id))) then
    raise exception 'Servidor fora do seu escopo.' using errcode = '42501';
  end if;
  select * into c from iara.v_carga_servidor where staff_id = s.id;
  return jsonb_build_object(
    'id', s.id, 'nome', s.full_name, 'matricula', s.matricula_funcional, 'funcao', s.role, 'cargo', s.cargo, 'vinculo', s.bond,
    'ch', s.carga_horaria_semanal, 'admissao', s.data_admissao, 'escolaridade', s.escolaridade, 'formacao', s.formacao,
    'area', s.area_atuacao, 'situacao', s.situacao, 'is_demo', s.is_demo, 'unit_id', s.unit_id, 'foto_arquivo_id', s.foto_arquivo_id,
    'proprio', s.id = (select staff_id from iara.app_users where id = iara.current_user_id()),
    'pode_editar', iara.has_perm('pessoal.write') and iara.can_access_unit(s.unit_id),
    'unidade', (select jsonb_build_object('id', id, 'name', name) from iara.education_units where id = s.unit_id),
    'carga', jsonb_build_object('capacidade', c.capacidade, 'atribuidas', c.atribuidas, 'disponivel', c.disponivel, 'turmas', c.turmas),
    'lotacoes', (select coalesce(jsonb_agg(jsonb_build_object('unidade', u.name, 'funcao', l.funcao, 'inicio', l.inicio, 'fim', l.fim, 'motivo', l.motivo)
                  order by l.inicio desc), '[]') from iara.staff_lotacoes l left join iara.education_units u on u.id = l.unit_id where l.staff_id = s.id),
    'formacoes', (select coalesce(jsonb_agg(jsonb_build_object('titulo', f.titulo, 'tipo', f.tipo, 'instituicao', f.instituicao,
                  'carga_horaria', f.carga_horaria, 'concluido_em', f.concluido_em) order by f.concluido_em desc), '[]')
                  from iara.staff_formacoes f where f.staff_id = s.id),
    'turmas', (select coalesce(jsonb_agg(jsonb_build_object('id', cl.id, 'nome', cl.class_name, 'turno', cl.shift, 'papel', cs.role_type,
                 'aulas', cs.hours_per_week, 'serie', gl.short_name) order by cl.class_name), '[]')
               from iara.class_staff cs join iara.classes cl on cl.id = cs.class_id join iara.grade_levels gl on gl.id = cl.grade_level_id
               where cs.staff_id = s.id),
    'horario', (select coalesce(jsonb_agg(jsonb_build_object('dia', h.dia_semana, 'aula', h.aula, 'hora', iara.aula_horario(cl.shift, h.aula),
                  'turno', iara.turno_base(cl.shift), 'turma', cl.class_name, 'componente', h.componente) order by iara.turno_base(cl.shift), h.dia_semana, h.aula), '[]')
                from iara.horarios_turma h join iara.classes cl on cl.id = h.class_id where h.staff_id = s.id),
    'mediacoes', (select coalesce(jsonb_agg(jsonb_build_object('aluno', split_part(st.full_name, ' ', 1), 'turma', cl.class_name)), '[]')
                  from iara.mediacoes m join iara.students st on st.id = m.student_id left join iara.classes cl on cl.id = m.class_id
                  where m.staff_id = s.id and (m.fim is null or m.fim >= current_date)));
end $$;


commit;
