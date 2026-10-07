-- IARA Educa — 050 · Ocorrências, agenda escolar e restrição alimentar na ficha do aluno; buscas com mais filtros
-- Ocorrência: registrada pela escola (professor, direção, secretaria) ou pela família; a família dá ciência do que a
-- escola registrou e as duas partes comentam até o encerramento. Agenda escolar: recados, tarefas, lembretes e bilhetes
-- da turma ou de um aluno, com ciência da família; a família também manda bilhete para a escola. Portal e IARA.
-- Dados de demonstração fictícios (is_demo), com limpeza por módulo e rotina diária.
begin;

insert into iara.permissions (code, description, is_sensitive) values
  ('ocorrencias.read', 'Consultar ocorrências dos alunos (registradas pela escola ou pela família)', true),
  ('ocorrencias.write', 'Registrar e acompanhar ocorrências dos alunos', true),
  ('agenda.write', 'Publicar na agenda escolar da turma ou do aluno', false)
on conflict (code) do update set description = excluded.description, is_sensitive = excluded.is_sensitive;
insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('PROFESSOR', 'ocorrencias.read'), ('PROFESSOR', 'ocorrencias.write'), ('PROFESSOR', 'agenda.write'),
  ('DIRETOR_UNIDADE', 'ocorrencias.read'), ('DIRETOR_UNIDADE', 'ocorrencias.write'), ('DIRETOR_UNIDADE', 'agenda.write'),
  ('SECRETARIA_ESCOLAR', 'ocorrencias.read'), ('SECRETARIA_ESCOLAR', 'ocorrencias.write'), ('SECRETARIA_ESCOLAR', 'agenda.write'),
  ('SECRETARIO', 'ocorrencias.read'), ('SUPERINTENDENCIA', 'ocorrencias.read'), ('GERENCIA_EI', 'ocorrencias.read')
) v(r, p)
on conflict do nothing;

-- 1. Tabelas --------------------------------------------------------------------------------------------------------------------
create table if not exists iara.ocorrencias (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references iara.students(id) on delete cascade,
  unit_id integer references iara.education_units(id),
  class_id uuid references iara.classes(id) on delete set null,
  origem text not null check (origem in ('ESCOLA', 'FAMILIA')),
  tipo text not null check (tipo in ('COMPORTAMENTO', 'CONFLITO', 'ACIDENTE', 'SAUDE', 'BULLYING', 'PERTENCES', 'ATRASO_SAIDA',
                                     'PEDAGOGICA', 'ELOGIO', 'OUTRO')),
  gravidade text not null default 'LEVE' check (gravidade in ('LEVE', 'MODERADA', 'GRAVE')),
  ocorrida_em timestamptz not null default now(),
  local text,
  descricao text not null,
  providencias text,
  situacao text not null default 'ABERTA' check (situacao in ('ABERTA', 'EM_ACOMPANHAMENTO', 'ENCERRADA')),
  registrada_por_label text,
  registrada_por_guardian uuid references iara.guardians(id) on delete set null,
  ciencia_familia_em timestamptz,
  created_at timestamptz not null default now(),
  is_demo boolean not null default true
);
create index if not exists ocorrencias_student_idx on iara.ocorrencias (student_id, ocorrida_em desc);
create index if not exists ocorrencias_unit_idx on iara.ocorrencias (unit_id, situacao);

create table if not exists iara.ocorrencia_eventos (
  id uuid primary key default gen_random_uuid(),
  ocorrencia_id uuid not null references iara.ocorrencias(id) on delete cascade,
  origem text not null check (origem in ('ESCOLA', 'FAMILIA')),
  texto text not null,
  situacao text,
  autor_label text,
  created_at timestamptz not null default now(),
  is_demo boolean not null default true
);
create index if not exists ocorrencia_eventos_idx on iara.ocorrencia_eventos (ocorrencia_id, created_at);

create table if not exists iara.agenda_escolar (
  id uuid primary key default gen_random_uuid(),
  unit_id integer references iara.education_units(id),
  class_id uuid not null references iara.classes(id) on delete cascade,
  student_id uuid references iara.students(id) on delete cascade,
  origem text not null default 'ESCOLA' check (origem in ('ESCOLA', 'FAMILIA')),
  tipo text not null check (tipo in ('RECADO', 'TAREFA', 'LEMBRETE', 'MATERIAL', 'EVENTO', 'BILHETE')),
  titulo text,
  texto text not null,
  data date not null default current_date,
  exige_ciencia boolean not null default false,
  autor_label text,
  autor_guardian uuid references iara.guardians(id) on delete set null,
  ciencias_demo integer not null default 0,
  created_at timestamptz not null default now(),
  is_demo boolean not null default true
);
create index if not exists agenda_class_idx on iara.agenda_escolar (class_id, data desc);
create index if not exists agenda_student_idx on iara.agenda_escolar (student_id) where student_id is not null;

create table if not exists iara.agenda_ciencia (
  agenda_id uuid not null references iara.agenda_escolar(id) on delete cascade,
  student_id uuid not null references iara.students(id) on delete cascade,
  guardian_id uuid references iara.guardians(id) on delete set null,
  ciente_em timestamptz not null default now(),
  is_demo boolean not null default false,
  primary key (agenda_id, student_id)
);

alter table iara.ocorrencias enable row level security;
alter table iara.ocorrencia_eventos enable row level security;
alter table iara.agenda_escolar enable row level security;
alter table iara.agenda_ciencia enable row level security;

-- 2. Acesso e formatos ------------------------------------------------------------------------------------------------------------
-- gestão com escopo no aluno, ou o professor de uma turma em que o aluno está
create or replace function iara.aluno_acesso(p_student uuid, p_perm text) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select iara.has_perm(p_perm) and (
    (iara.my_role() <> 'PROFESSOR' and iara.can_access_student(p_student))
    or exists (select 1 from iara.enrollments e where e.student_id = p_student and e.status = 'ACTIVE' and e.class_id = any (iara.minhas_turmas())))
$$;

create or replace function iara.ocorrencia_json(o iara.ocorrencias, p_eventos boolean default true) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', o.id, 'student_id', o.student_id, 'aluno', s.full_name, 'primeiro_nome', split_part(s.full_name, ' ', 1),
    'turma', c.class_name, 'class_id', o.class_id, 'unidade', u.short_name, 'unit_id', o.unit_id, 'origem', o.origem, 'tipo', o.tipo,
    'gravidade', o.gravidade, 'ocorrida_em', o.ocorrida_em, 'local', o.local, 'descricao', o.descricao, 'providencias', o.providencias,
    'situacao', o.situacao, 'registrada_por', o.registrada_por_label, 'ciencia_familia_em', o.ciencia_familia_em,
    'aguarda_ciencia', o.origem = 'ESCOLA' and o.ciencia_familia_em is null and o.tipo <> 'ELOGIO' or (o.origem = 'ESCOLA' and o.tipo = 'ELOGIO' and o.ciencia_familia_em is null),
    'is_demo', o.is_demo,
    'eventos', case when p_eventos then (select coalesce(jsonb_agg(jsonb_build_object('origem', e.origem, 'texto', e.texto, 'situacao', e.situacao,
                 'autor', e.autor_label, 'em', e.created_at) order by e.created_at), '[]') from iara.ocorrencia_eventos e where e.ocorrencia_id = o.id) end)
  from iara.students s left join iara.classes c on c.id = o.class_id left join iara.education_units u on u.id = o.unit_id
  where s.id = o.student_id
$$;

-- 3. Ocorrências: escola ------------------------------------------------------------------------------------------------------------
create or replace function api.ocorrencias_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_prof boolean := iara.my_role() = 'PROFESSOR';
  v_busca text := nullif(iara.norm(btrim(coalesce(p ->> 'busca', ''))), '');
begin
  perform iara.require_perm('ocorrencias.read');
  return (with base as (
      select o.* from iara.ocorrencias o
      where (v_unit is null or o.unit_id = v_unit)
        and (not v_prof or o.class_id = any (iara.minhas_turmas()))
        and (nullif(p ->> 'class_id', '') is null or o.class_id = (p ->> 'class_id')::uuid)
        and (nullif(p ->> 'tipo', '') is null or o.tipo = p ->> 'tipo')
        and (nullif(p ->> 'origem', '') is null or o.origem = p ->> 'origem')
        and (v_busca is null or exists (select 1 from iara.students s where s.id = o.student_id and iara.norm(s.full_name) like '%' || v_busca || '%')))
    select jsonb_build_object(
      'contagem', (select jsonb_build_object('ABERTA', count(*) filter (where situacao = 'ABERTA'), 'EM_ACOMPANHAMENTO', count(*) filter (where situacao = 'EM_ACOMPANHAMENTO'),
                   'ENCERRADA', count(*) filter (where situacao = 'ENCERRADA'), 'FAMILIA', count(*) filter (where origem = 'FAMILIA' and situacao <> 'ENCERRADA'),
                   'sem_ciencia', count(*) filter (where origem = 'ESCOLA' and ciencia_familia_em is null and situacao <> 'ENCERRADA')) from base),
      'pode_registrar', iara.has_perm('ocorrencias.write'),
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
begin
  select * into o from iara.ocorrencias where id = (p ->> 'id')::uuid;
  if o.id is null then raise exception 'Ocorrência não encontrada.' using errcode = 'P0002'; end if;
  v_fam := iara.my_guardian() is not null and o.student_id in (select iara.my_student_ids());
  if not (v_fam or iara.aluno_acesso(o.student_id, 'ocorrencias.read')) then
    raise exception 'Ocorrência não encontrada.' using errcode = 'P0002';
  end if;
  return iara.ocorrencia_json(o, true) || jsonb_build_object(
    'pode_atualizar', not v_fam and iara.aluno_acesso(o.student_id, 'ocorrencias.write'),
    'pode_comentar', v_fam or iara.aluno_acesso(o.student_id, 'ocorrencias.write'),
    'pode_dar_ciencia', v_fam and o.origem = 'ESCOLA' and o.ciencia_familia_em is null);
end $$;

-- registro pela escola (professor da turma, direção, secretaria) ou pela família (só dos próprios filhos)
create or replace function api.ocorrencia_registrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_fam boolean := iara.my_guardian() is not null;
  v_tipo text := coalesce(nullif(p ->> 'tipo', ''), 'OUTRO');
  v_grav text := coalesce(nullif(p ->> 'gravidade', ''), case when v_tipo in ('BULLYING') then 'MODERADA' else 'LEVE' end);
  v_desc text := btrim(coalesce(p ->> 'descricao', ''));
  e record;
  o iara.ocorrencias;
begin
  if v_fam then
    if not (v_student in (select iara.my_student_ids())) then raise exception 'Criança não vinculada a você.' using errcode = '42501'; end if;
  elsif not iara.aluno_acesso(v_student, 'ocorrencias.write') then
    raise exception 'Sem permissão para registrar ocorrência deste aluno.' using errcode = '42501';
  end if;
  if v_tipo not in ('COMPORTAMENTO', 'CONFLITO', 'ACIDENTE', 'SAUDE', 'BULLYING', 'PERTENCES', 'ATRASO_SAIDA', 'PEDAGOGICA', 'ELOGIO', 'OUTRO')
     or v_grav not in ('LEVE', 'MODERADA', 'GRAVE') then
    raise exception 'Tipo ou gravidade inválidos.' using errcode = '22023';
  end if;
  if length(v_desc) not between 10 and 2000 then raise exception 'Conte o que aconteceu (de 10 a 2.000 caracteres).' using errcode = '22023'; end if;
  select en.unit_id, en.class_id into e from iara.enrollments en where en.student_id = v_student and en.status = 'ACTIVE' limit 1;
  if e.unit_id is null then raise exception 'O aluno não tem matrícula ativa.' using errcode = '22023'; end if;
  insert into iara.ocorrencias (student_id, unit_id, class_id, origem, tipo, gravidade, ocorrida_em, local, descricao, providencias, situacao,
                                registrada_por_label, registrada_por_guardian, is_demo)
  values (v_student, e.unit_id, e.class_id, case when v_fam then 'FAMILIA' else 'ESCOLA' end, v_tipo, v_grav,
          coalesce(nullif(p ->> 'ocorrida_em', '')::timestamptz, now()), nullif(btrim(coalesce(p ->> 'local', '')), ''), v_desc,
          case when v_fam then null else nullif(btrim(coalesce(p ->> 'providencias', '')), '') end,
          case when not v_fam and coalesce((p ->> 'encerrar')::boolean, false) then 'ENCERRADA' else 'ABERTA' end,
          iara.my_label(), case when v_fam then iara.my_guardian() end, false)
  returning * into o;
  perform iara.audit_event('OCORRENCIA_REGISTRADA', 'student', v_student::text, e.unit_id,
    format('Ocorrência (%s, %s) registrada pela %s.', lower(v_tipo), lower(v_grav), case when v_fam then 'família' else 'escola' end));
  return iara.ocorrencia_json(o, true) || jsonb_build_object('mensagem', case when v_fam
    then 'Registrado. A direção da escola recebe agora e responde por aqui; acompanhe na Vida escolar.'
    else 'Registrado. A família vê no portal e pela IARA e pode dar ciência.' end);
end $$;

-- acompanhamento: a escola muda a situação e registra providências; a família comenta
create or replace function api.ocorrencia_atualizar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  o iara.ocorrencias;
  v_fam boolean;
  v_txt text := btrim(coalesce(p ->> 'texto', ''));
  v_sit text := nullif(p ->> 'situacao', '');
begin
  select * into o from iara.ocorrencias where id = (p ->> 'id')::uuid for update;
  if o.id is null then raise exception 'Ocorrência não encontrada.' using errcode = 'P0002'; end if;
  v_fam := iara.my_guardian() is not null and o.student_id in (select iara.my_student_ids());
  if not v_fam and not iara.aluno_acesso(o.student_id, 'ocorrencias.write') then
    raise exception 'Sem permissão para esta ocorrência.' using errcode = '42501';
  end if;
  if v_fam then v_sit := null; end if;
  if v_sit is not null and v_sit not in ('ABERTA', 'EM_ACOMPANHAMENTO', 'ENCERRADA') then raise exception 'Situação inválida.' using errcode = '22023'; end if;
  if length(v_txt) < 3 and v_sit is null then raise exception 'Escreva o comentário ou a providência.' using errcode = '22023'; end if;
  if length(v_txt) > 2000 then raise exception 'Texto longo demais (máximo de 2.000 caracteres).' using errcode = '22023'; end if;
  insert into iara.ocorrencia_eventos (ocorrencia_id, origem, texto, situacao, autor_label, is_demo)
  values (o.id, case when v_fam then 'FAMILIA' else 'ESCOLA' end, coalesce(nullif(v_txt, ''), 'Situação alterada.'), v_sit, iara.my_label(), false);
  if v_sit is not null or (not v_fam and v_txt <> '') then
    update iara.ocorrencias set situacao = coalesce(v_sit, situacao),
           providencias = case when not v_fam and v_txt <> '' then coalesce(providencias || E'\n', '') || v_txt else providencias end
    where id = o.id;
  end if;
  perform iara.audit_event('OCORRENCIA_ACOMPANHADA', 'student', o.student_id::text, o.unit_id,
    format('Ocorrência acompanhada pela %s%s.', case when v_fam then 'família' else 'escola' end, case when v_sit is not null then ' (' || lower(v_sit) || ')' else '' end));
  return api.ocorrencia_detalhe(jsonb_build_object('id', o.id));
end $$;

-- 4. Ocorrências: família ------------------------------------------------------------------------------------------------------------
create or replace function api.familia_ocorrencias(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_lista jsonb;
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(iara.ocorrencia_json(o, true) order by (o.situacao = 'ENCERRADA'), o.ocorrida_em desc), '[]') into v_lista
  from (select * from iara.ocorrencias where student_id in (select iara.my_student_ids()) order by ocorrida_em desc limit 60) o;
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
  if o.id is null or iara.my_guardian() is null or not (o.student_id in (select iara.my_student_ids())) then
    raise exception 'Ocorrência não encontrada.' using errcode = 'P0002';
  end if;
  update iara.ocorrencias set ciencia_familia_em = coalesce(ciencia_familia_em, now()) where id = o.id;
  perform iara.audit_event('OCORRENCIA_CIENCIA', 'student', o.student_id::text, o.unit_id, 'Família deu ciência de uma ocorrência registrada pela escola.');
  return jsonb_build_object('ok', true);
end $$;

-- 5. Agenda escolar ---------------------------------------------------------------------------------------------------------------
create or replace function iara.agenda_json(a iara.agenda_escolar, p_student uuid default null) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', a.id, 'class_id', a.class_id, 'turma', (select class_name from iara.classes where id = a.class_id),
    'student_id', a.student_id, 'aluno', (select full_name from iara.students where id = a.student_id), 'origem', a.origem, 'tipo', a.tipo,
    'titulo', a.titulo, 'texto', a.texto, 'data', a.data, 'exige_ciencia', a.exige_ciencia, 'autor', a.autor_label, 'criado_em', a.created_at,
    'is_demo', a.is_demo,
    'destinatarios', case when a.student_id is not null then 1 else (select count(*) from iara.enrollments e where e.class_id = a.class_id and e.status = 'ACTIVE') end,
    'ciencias', a.ciencias_demo + (select count(*) from iara.agenda_ciencia c where c.agenda_id = a.id),
    'ciente', case when p_student is not null then exists (select 1 from iara.agenda_ciencia c where c.agenda_id = a.id and c.student_id = p_student) end)
$$;

create or replace function api.agenda_turma(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  c iara.classes;
begin
  select * into c from iara.classes where id = (p ->> 'class_id')::uuid;
  if c.id is null or not iara.turma_acesso(c.id, 'classes.read') then raise exception 'Turma não encontrada ou fora do seu escopo.' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'turma', jsonb_build_object('id', c.id, 'nome', c.class_name, 'turno', c.shift, 'unidade', (select name from iara.education_units where id = c.unit_id)),
    'pode_publicar', iara.turma_acesso(c.id, 'agenda.write'),
    'pode_ocorrencia', iara.turma_acesso(c.id, 'ocorrencias.write'),
    'alunos', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'nome', coalesce(s.social_name, s.full_name)) order by s.full_name), '[]')
               from iara.enrollments e join iara.students s on s.id = e.student_id where e.class_id = c.id and e.status = 'ACTIVE'),
    'itens', (select coalesce(jsonb_agg(iara.agenda_json(a) order by a.data desc, a.created_at desc), '[]')
              from (select * from iara.agenda_escolar a where a.class_id = c.id
                      and a.data between coalesce(nullif(p ->> 'de', '')::date, current_date - 30) and coalesce(nullif(p ->> 'ate', '')::date, current_date + 30)
                    order by a.data desc, a.created_at desc limit 200) a));
end $$;

create or replace function api.agenda_publicar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.classes;
  v_student uuid := nullif(p ->> 'student_id', '')::uuid;
  v_tipo text := coalesce(nullif(p ->> 'tipo', ''), case when v_student is null then 'RECADO' else 'BILHETE' end);
  v_txt text := btrim(coalesce(p ->> 'texto', ''));
  a iara.agenda_escolar;
begin
  select * into c from iara.classes where id = (p ->> 'class_id')::uuid;
  if c.id is null or not iara.turma_acesso(c.id, 'agenda.write') then raise exception 'Sem permissão para a agenda desta turma.' using errcode = '42501'; end if;
  if v_student is not null and not exists (select 1 from iara.enrollments e where e.class_id = c.id and e.student_id = v_student and e.status = 'ACTIVE') then
    raise exception 'O aluno não é desta turma.' using errcode = '22023';
  end if;
  if v_tipo not in ('RECADO', 'TAREFA', 'LEMBRETE', 'MATERIAL', 'EVENTO', 'BILHETE') then raise exception 'Tipo inválido.' using errcode = '22023'; end if;
  if length(v_txt) not between 3 and 2000 or length(coalesce(p ->> 'titulo', '')) > 120 then
    raise exception 'Escreva o recado (até 2.000 caracteres; título até 120).' using errcode = '22023';
  end if;
  insert into iara.agenda_escolar (unit_id, class_id, student_id, origem, tipo, titulo, texto, data, exige_ciencia, autor_label, is_demo)
  values (c.unit_id, c.id, v_student, 'ESCOLA', v_tipo, nullif(btrim(coalesce(p ->> 'titulo', '')), ''), v_txt,
          coalesce(nullif(p ->> 'data', '')::date, current_date), coalesce((p ->> 'exige_ciencia')::boolean, false), iara.my_label(), false)
  returning * into a;
  perform iara.audit_event('AGENDA_PUBLICADA', 'class', c.id::text, c.unit_id,
    format('Agenda: %s publicado(a) para %s.', lower(v_tipo), case when v_student is null then 'a turma ' || c.class_name else 'um aluno' end));
  return iara.agenda_json(a);
end $$;

create or replace function api.familia_agenda(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_lista jsonb;
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(iara.agenda_json(a, k.student_id) || jsonb_build_object('filho', k.primeiro_nome, 'filho_id', k.student_id)
                            order by a.data desc, a.created_at desc), '[]') into v_lista
  from (select s.id student_id, split_part(s.full_name, ' ', 1) primeiro_nome, e.class_id
        from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
        where s.id in (select iara.my_student_ids())) k
  join lateral (select * from iara.agenda_escolar a where a.class_id = k.class_id and (a.student_id is null or a.student_id = k.student_id)
                  and a.data between current_date - coalesce(nullif(p ->> 'dias', '')::int, 21) and current_date + 30
                order by a.data desc, a.created_at desc limit 40) a on true;
  return jsonb_build_object('itens', v_lista,
    'aguardando_ciencia', (select count(*) from jsonb_array_elements(v_lista) x where (x ->> 'exige_ciencia')::boolean and not (x ->> 'ciente')::boolean and x ->> 'origem' = 'ESCOLA'),
    'hoje', (select count(*) from jsonb_array_elements(v_lista) x where (x ->> 'data')::date = current_date));
end $$;

create or replace function api.familia_agenda_ciente(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  a iara.agenda_escolar;
  v_student uuid := (p ->> 'student_id')::uuid;
begin
  select * into a from iara.agenda_escolar where id = (p ->> 'id')::uuid;
  if a.id is null or iara.my_guardian() is null or not (v_student in (select iara.my_student_ids()))
     or not exists (select 1 from iara.enrollments e where e.student_id = v_student and e.class_id = a.class_id and e.status = 'ACTIVE')
     or (a.student_id is not null and a.student_id <> v_student) then
    raise exception 'Recado não encontrado.' using errcode = 'P0002';
  end if;
  insert into iara.agenda_ciencia (agenda_id, student_id, guardian_id) values (a.id, v_student, iara.my_guardian()) on conflict do nothing;
  return jsonb_build_object('ok', true);
end $$;

-- bilhete da família para a escola (professora e direção da turma)
create or replace function api.familia_agenda_enviar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_txt text := btrim(coalesce(p ->> 'texto', ''));
  e record;
  a iara.agenda_escolar;
begin
  if iara.my_guardian() is null or not (v_student in (select iara.my_student_ids())) then raise exception 'Criança não vinculada a você.' using errcode = '42501'; end if;
  if length(v_txt) not between 3 and 1000 then raise exception 'Escreva o bilhete (até 1.000 caracteres).' using errcode = '22023'; end if;
  select en.unit_id, en.class_id into e from iara.enrollments en where en.student_id = v_student and en.status = 'ACTIVE' limit 1;
  if e.class_id is null then raise exception 'A criança não tem matrícula ativa.' using errcode = '22023'; end if;
  insert into iara.agenda_escolar (unit_id, class_id, student_id, origem, tipo, texto, data, autor_label, autor_guardian, is_demo)
  values (e.unit_id, e.class_id, v_student, 'FAMILIA', 'BILHETE', v_txt, current_date, iara.my_label(), iara.my_guardian(), false)
  returning * into a;
  perform iara.audit_event('AGENDA_BILHETE_FAMILIA', 'student', v_student::text, e.unit_id, 'Bilhete da família na agenda escolar.');
  return iara.agenda_json(a, v_student) || jsonb_build_object('mensagem', 'Bilhete entregue na agenda da turma: a professora e a direção veem agora.');
end $$;

-- 6. Ficha do aluno: alimentação, ocorrências e agenda ----------------------------------------------------------------------------
create or replace function api.aluno_vida_escolar(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_class uuid;
begin
  if not ((iara.has_perm('students.read') and iara.can_access_student(v_student)) or iara.aluno_acesso(v_student, 'ocorrencias.read')) then
    raise exception 'Aluno fora do seu escopo.' using errcode = '42501';
  end if;
  select class_id into v_class from iara.enrollments where student_id = v_student and status = 'ACTIVE' limit 1;
  return jsonb_build_object(
    'restricoes', (select coalesce(jsonb_agg(jsonb_build_object('id', ar.id, 'codigo', ra.codigo, 'descricao', ra.descricao, 'motivo', ra.motivo,
         'orientacao', ra.orientacao_cozinha, 'detalhe', ar.detalhe, 'situacao', ar.situacao, 'origem', ar.origem, 'informada_em', ar.created_at,
         'validada_por', ar.validada_por_label, 'validada_em', ar.validada_em, 'exige_laudo', ra.exige_laudo, 'is_demo', ar.is_demo)
         order by (ar.situacao = 'RECUSADA'), ra.ordem), '[]')
       from iara.aluno_restricoes ar join iara.restricoes_alimentares ra on ra.codigo = ar.restricao_codigo
       where ar.student_id = v_student and (ar.fim is null or ar.fim >= current_date)),
    'ocorrencias', (select coalesce(jsonb_agg(iara.ocorrencia_json(o, true) order by (o.situacao = 'ENCERRADA'), o.ocorrida_em desc), '[]')
       from (select * from iara.ocorrencias where student_id = v_student order by ocorrida_em desc limit 50) o),
    'agenda', (select coalesce(jsonb_agg(iara.agenda_json(a, v_student) order by a.data desc, a.created_at desc), '[]')
       from (select * from iara.agenda_escolar a where a.class_id = v_class and (a.student_id is null or a.student_id = v_student)
               and a.data between current_date - 30 and current_date + 30 order by a.data desc, a.created_at desc limit 40) a),
    'class_id', v_class,
    'pode_ocorrencia', iara.aluno_acesso(v_student, 'ocorrencias.write'),
    'pode_agenda', v_class is not null and iara.turma_acesso(v_class, 'agenda.write'),
    'pode_restricao', iara.has_perm('students.write') and iara.can_access_student(v_student),
    'catalogo_restricoes', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'descricao', descricao, 'motivo', motivo, 'exige_laudo', exige_laudo) order by ordem)
                            from iara.restricoes_alimentares));
end $$;

-- a secretaria registra a restrição trazida pela família no balcão (a nutrição valida)
create or replace function api.aluno_restricao_registrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  r iara.restricoes_alimentares;
begin
  if not (iara.has_perm('students.write') and iara.can_access_student(v_student)) then
    raise exception 'Sem permissão para registrar restrição deste aluno.' using errcode = '42501';
  end if;
  select * into r from iara.restricoes_alimentares where codigo = p ->> 'codigo';
  if r.codigo is null then raise exception 'Restrição desconhecida.' using errcode = '22023'; end if;
  if exists (select 1 from iara.aluno_restricoes where student_id = v_student and restricao_codigo = r.codigo and situacao <> 'RECUSADA') then
    raise exception 'Essa restrição já está registrada.' using errcode = '22023';
  end if;
  insert into iara.aluno_restricoes (student_id, restricao_codigo, detalhe, situacao, origem, observacao, is_demo)
  values (v_student, r.codigo, nullif(btrim(coalesce(p ->> 'detalhe', '')), ''), 'INFORMADA', 'UNIDADE',
          case when coalesce((p ->> 'laudo_entregue')::boolean, false) then 'Laudo entregue na secretaria da unidade.' end, false);
  perform iara.audit_event('RESTRICAO_INFORMADA', 'student', v_student::text, null, 'Restrição alimentar registrada pela unidade: ' || r.descricao || '.');
  return jsonb_build_object('ok', true, 'mensagem', 'Registrada. A nutrição valida e a cozinha passa a receber a instrução de preparo.');
end $$;

-- 7. Buscas: alunos e profissionais com mais filtros ------------------------------------------------------------------------------
create or replace function api.alunos_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, extensions, public
as $$
declare
  v_scope text := iara.my_scope();
  v_unit integer := iara.my_unit();
  v_q text := nullif(btrim(iara.norm(coalesce(p ->> 'q', ''))), '');
  v_dig text := iara.digitos(p ->> 'q');
  v_sit text := nullif(p ->> 'situacao', '');
  v_un integer := nullif(p ->> 'unidade_id', '')::int;
  v_terr integer := nullif(p ->> 'territorio_id', '')::int;
  v_pend boolean := coalesce((p ->> 'pendentes')::boolean, false);
  v_item text := nullif(p ->> 'pendencia', '');
  v_ordem text := coalesce(nullif(p ->> 'ordem', ''), 'nome');
  v_sexo text := nullif(p ->> 'sexo', '');
  v_idmin integer := nullif(p ->> 'idade_min', '')::int;
  v_idmax integer := nullif(p ->> 'idade_max', '')::int;
  v_serie smallint := nullif(p ->> 'serie_id', '')::smallint;
  v_turno text := nullif(p ->> 'turno', '');
  v_turma uuid := nullif(p ->> 'turma_id', '')::uuid;
  v_restr text := nullif(p ->> 'restricao', '');
  v_ocor text := nullif(p ->> 'ocorrencias', '');
  v_aee boolean := coalesce((p ->> 'aee')::boolean, false);
  v_lim integer := least(greatest(coalesce(nullif(p ->> 'limite', '')::int, 40), 1), 100);
  v_off integer := greatest(coalesce(nullif(p ->> 'offset', '')::int, 0), 0);
  v jsonb;
begin
  perform iara.require_perm('students.read');
  if v_scope is null or v_scope not in ('NETWORK', 'UNIT') then
    raise exception 'O cadastro de alunos é da Secretaria e das unidades.' using errcode = '42501';
  end if;
  if v_dig is not null and length(v_dig) < 4 then v_dig := null; end if;
  with base as materialized (
    select s.id, s.full_name, s.social_name, s.birth_date, s.gender, s.status, s.student_registry_number, s.avatar_seed, s.aee_status,
           s.updated_at, s.is_demo, a.neighborhood, a.territory_id, a.geocode_precision,
           mat.unit_id as mat_unit, mat.unit_name, mat.class_name, mat.class_id, mat.grade_level_id, mat.shift,
           iara.aluno_pendencias(s, r.student_id is not null) as pend
    from iara.students s
    left join iara.addresses a on a.id = s.address_id
    left join (select distinct sg.student_id from iara.student_guardians sg where sg.end_date is null) r on r.student_id = s.id
    left join (select distinct on (e.student_id) e.student_id, e.unit_id, u.short_name as unit_name, c.class_name, c.id as class_id,
                      c.grade_level_id, c.shift
               from iara.enrollments e join iara.education_units u on u.id = e.unit_id join iara.classes c on c.id = e.class_id
               where e.status = 'ACTIVE' order by e.student_id, e.enrollment_date desc) mat on mat.student_id = s.id
    where (v_scope = 'NETWORK' or s.id in (select iara.unidade_alunos(v_unit)))
      and (v_q is null
           or iara.norm(s.full_name) like '%' || v_q || '%'
           or iara.norm(coalesce(s.social_name, '')) like '%' || v_q || '%'
           or (v_dig is not null and (s.student_registry_number = v_dig or iara.digitos(s.cpf) = v_dig or s.inep_id = v_dig)))
  ),
  filt as (
    select b.* from base b
    where (v_sit is null or b.status = v_sit)
      and (v_un is null or b.mat_unit = v_un)
      and (v_terr is null or b.territory_id = v_terr)
      and (not v_pend or cardinality(b.pend) > 0)
      and (v_item is null or v_item = any (b.pend))
      and (v_sexo is null or b.gender = v_sexo)
      and (v_idmin is null or b.birth_date <= (current_date - make_interval(years => v_idmin))::date)
      and (v_idmax is null or b.birth_date > (current_date - make_interval(years => v_idmax + 1))::date)
      and (v_serie is null or b.grade_level_id = v_serie)
      and (v_turno is null or b.shift = v_turno)
      and (v_turma is null or b.class_id = v_turma)
      and (not v_aee or b.aee_status)
      and (v_restr is null or exists (select 1 from iara.aluno_restricoes ar where ar.student_id = b.id and ar.situacao <> 'RECUSADA'
                                        and (v_restr = 'QUALQUER' or ar.restricao_codigo = v_restr)))
      and (v_ocor is null or exists (select 1 from iara.ocorrencias o where o.student_id = b.id
                                       and (v_ocor = 'QUALQUER' or (v_ocor = 'ABERTAS' and o.situacao <> 'ENCERRADA')
                                            or (v_ocor = 'FAMILIA' and o.origem = 'FAMILIA'))))
  ),
  pagina as (
    select f.*, row_number() over (order by
             case when v_ordem = 'pendencias' then -cardinality(f.pend) else 0 end,
             case when v_ordem = 'recentes' then -extract(epoch from f.updated_at) else 0 end,
             case when v_ordem = 'idade' then f.birth_date end desc,
             iara.norm(f.full_name), f.id) as ord
    from filt f
    order by ord
    limit v_lim offset v_off
  )
  select jsonb_build_object(
    'escopo', v_scope,
    'unidade', (select u.name from iara.education_units u where u.id = v_unit),
    'pode_editar', iara.has_perm('students.write'),
    'total', (select count(*) from filt),
    'contagem', (select jsonb_build_object('todos', count(*), 'completos', count(*) filter (where cardinality(pend) = 0),
        'pendentes', count(*) filter (where cardinality(pend) > 0),
        'MATRICULADO', count(*) filter (where status = 'MATRICULADO'), 'AGUARDANDO_VAGA', count(*) filter (where status = 'AGUARDANDO_VAGA'),
        'SEM_VINCULO', count(*) filter (where status = 'SEM_VINCULO'), 'TRANSFERENCIA', count(*) filter (where status = 'TRANSFERENCIA'),
        'INATIVO', count(*) filter (where status = 'INATIVO'),
        'aproximada', count(*) filter (where iara.endereco_aproximado(geocode_precision))) from base),
    'pendencias_frequentes', (select coalesce(jsonb_agg(jsonb_build_object('item', z.item, 'n', z.n) order by z.n desc, z.item), '[]'::jsonb)
                              from (select unnest(pend) as item, count(*) as n from base group by 1) z),
    'turmas', case when coalesce(v_un, case when v_scope = 'UNIT' then v_unit end) is not null then
                (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.class_name, 'turno', c.shift) order by c.class_name), '[]')
                 from iara.classes c where c.unit_id = coalesce(v_un, v_unit) and c.status = 'ATIVA') end,
    'itens', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', g.id, 'nome', g.full_name, 'nome_social', g.social_name, 'nascimento', g.birth_date, 'idade', iara.age_text(g.birth_date),
        'sexo', g.gender, 'situacao', g.status, 'registro', g.student_registry_number, 'avatar_seed', g.avatar_seed,
        'unidade', case when g.mat_unit is not null then jsonb_build_object('id', g.mat_unit, 'nome', g.unit_name, 'turma', g.class_name, 'turma_id', g.class_id) end,
        'bairro', g.neighborhood, 'territorio', (select t.name from iara.territories t where t.id = g.territory_id),
        'localizacao_aproximada', iara.endereco_aproximado(g.geocode_precision),
        'pendencias', to_jsonb(g.pend), 'completo_pct', round(100.0 * (7 - cardinality(g.pend)) / 7),
        'aee', g.aee_status, 'ficticio', g.is_demo,
        'restricoes', (select coalesce(jsonb_agg(split_part(ra.descricao, ' (', 1) order by ra.ordem), '[]')
                       from iara.aluno_restricoes ar join iara.restricoes_alimentares ra on ra.codigo = ar.restricao_codigo
                       where ar.student_id = g.id and ar.situacao <> 'RECUSADA'),
        'ocorrencias_abertas', (select count(*) from iara.ocorrencias o where o.student_id = g.id and o.situacao <> 'ENCERRADA'),
        'responsavel', (select jsonb_build_object('id', gg.id, 'nome', gg.full_name, 'parentesco', sg.relationship)
                        from iara.student_guardians sg join iara.guardians gg on gg.id = sg.guardian_id
                        where sg.student_id = g.id and sg.end_date is null order by sg.is_primary desc, sg.relationship limit 1))
      order by g.ord), '[]'::jsonb) from pagina g)
  ) into v;
  return v;
end $$;

create or replace function api.pessoal_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := iara.pessoal_escopo(nullif(p ->> 'unit_id', '')::int);
  v_q text := nullif(iara.norm(btrim(coalesce(p ->> 'q', ''))), '');
  v_funcao text := nullif(p ->> 'funcao', '');
  v_sit text := nullif(p ->> 'situacao', '');
  v_vinc text := nullif(p ->> 'vinculo', '');
  v_area text := nullif(p ->> 'area', '');
  v_carga text := nullif(p ->> 'carga', '');
  v_regiao integer := nullif(p ->> 'regiao_id', '')::int;
  v_ord text := coalesce(nullif(p ->> 'ordem', ''), 'nome');
  v_lim integer := least(greatest(coalesce(nullif(p ->> 'limite', '')::int, 100), 1), 300);
  v_off integer := greatest(coalesce(nullif(p ->> 'offset', '')::int, 0), 0);
begin
  perform iara.require_perm('pessoal.read');
  return (with base as materialized (
      select c.*, u.short_name unidade, u.macro_territory_id regiao_id
      from iara.v_carga_servidor c left join iara.education_units u on u.id = c.unit_id
      where (v_unit is null or c.unit_id = v_unit)),
    filt as (
      select b.* from base b
      where (v_funcao is null or b.role = v_funcao)
        and (v_sit is null or b.situacao = v_sit)
        and (v_vinc is null or b.bond = v_vinc)
        and (v_area is null or b.area_atuacao = v_area)
        and (v_regiao is null or b.regiao_id = v_regiao)
        and (v_carga is null or (v_carga = 'EXCESSO' and b.disponivel < 0) or (v_carga = 'LIVRE' and b.disponivel > 0 and b.atribuidas > 0)
             or (v_carga = 'SEM_TURMA' and b.atribuidas = 0) or (v_carga = 'COMPLETA' and b.disponivel = 0 and b.capacidade > 0))
        and (v_q is null or iara.norm(b.full_name) like '%' || v_q || '%' or b.matricula_funcional = btrim(p ->> 'q')
             or iara.norm(coalesce(b.cargo, '')) like '%' || v_q || '%'))
    select jsonb_build_object(
      'unidade', (select jsonb_build_object('id', id, 'name', name) from iara.education_units where id = v_unit),
      'total', (select count(*) from filt),
      'totais', (select coalesce(jsonb_object_agg(role, n), '{}') from (select role, count(*) n from base group by 1) z),
      'situacao', (select coalesce(jsonb_object_agg(situacao, n), '{}') from (select situacao, count(*) n from base group by 1) z),
      'opcoes', jsonb_build_object(
        'vinculos', (select coalesce(jsonb_agg(distinct bond), '[]') from base where bond is not null),
        'areas', (select coalesce(jsonb_agg(distinct area_atuacao), '[]') from base where area_atuacao is not null),
        'regioes', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'nome', t.name) order by t.name), '[]')
                    from iara.territories t where t.kind = 'MACRORREGIAO')),
      'itens', (select coalesce(jsonb_agg(jsonb_build_object('id', c.staff_id, 'nome', c.full_name, 'matricula', c.matricula_funcional, 'funcao', c.role,
                  'cargo', c.cargo, 'area', c.area_atuacao, 'vinculo', c.bond, 'ch', c.ch, 'capacidade', c.capacidade, 'atribuidas', c.atribuidas,
                  'disponivel', c.disponivel, 'turmas', c.turmas, 'situacao', c.situacao, 'unidade', c.unidade, 'unit_id', c.unit_id)
                  order by c.ord), '[]')
                from (select f.*, row_number() over (order by case when v_ord = 'saldo' then f.disponivel end, case when v_ord = 'unidade' then f.unidade end,
                                                     iara.norm(f.full_name), f.staff_id) ord
                      from filt f order by ord limit v_lim offset v_off) c)));
end $$;

-- 8. Demonstração -----------------------------------------------------------------------------------------------------------------
create or replace function iara.demo_gerar_ocorrencias() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ana uuid := nullif(iara.setting('demo_student_ana'), '')::uuid;
  v_maria uuid := nullif(iara.setting('demo_guardian_maria'), '')::uuid;
  v_id uuid;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.ocorrencias where is_demo;
  insert into iara.ocorrencias (student_id, unit_id, class_id, origem, tipo, gravidade, ocorrida_em, local, descricao, providencias, situacao,
                                registrada_por_label, ciencia_familia_em, created_at, is_demo)
  select x.student_id, x.unit_id, x.class_id, x.origem, t.tipo, t.grav, x.quando, t.local, t.descr,
         case when x.origem = 'ESCOLA' then t.prov end,
         case when x.quando < now() - interval '20 days' or x.h % 10 < 4 then 'ENCERRADA' when x.h % 10 < 7 then 'EM_ACOMPANHAMENTO' else 'ABERTA' end,
         case when x.origem = 'ESCOLA' then (array['Professora da turma (demonstração)', 'Direção da unidade (demonstração)', 'Secretaria escolar (demonstração)'])[1 + x.h % 3]
              else 'Família (demonstração)' end,
         case when x.origem = 'ESCOLA' and (x.quando < now() - interval '3 days' and x.h % 100 < 85) then x.quando + interval '6 hours' end,
         x.quando, true
  from (select e.student_id, e.unit_id, e.class_id, abs(hashtext(e.student_id::text || 'ocor')) h,
               case when abs(hashtext(e.student_id::text || 'ocor')) % 5 = 0 then 'FAMILIA' else 'ESCOLA' end origem,
               (date '2026-02-09' + (abs(hashtext(e.student_id::text || 'ocq')) % greatest(current_date - date '2026-02-09', 1)))
                 + make_interval(hours => 11 + abs(hashtext(e.student_id::text)) % 8, mins => abs(hashtext(e.student_id::text)) % 60) quando
        from iara.enrollments e where e.status = 'ACTIVE' and e.student_id is distinct from v_ana
          and abs(hashtext(e.student_id::text || 'ocor')) % 1000 < 40) x
  cross join lateral (select * from (values
      ('ESCOLA', 'COMPORTAMENTO', 'LEVE', 'Sala de aula', 'Recusou-se a participar da atividade e saiu da sala sem autorização.', 'Conversa com a criança e com a coordenação pedagógica.'),
      ('ESCOLA', 'CONFLITO', 'MODERADA', 'Pátio', 'Desentendimento com um colega no recreio, com empurrões.', 'Mediação entre as crianças; as duas famílias foram avisadas.'),
      ('ESCOLA', 'ACIDENTE', 'LEVE', 'Parque', 'Caiu no parque e ralou o joelho.', 'Limpeza e curativo; acompanhado(a) até o fim do turno.'),
      ('ESCOLA', 'SAUDE', 'MODERADA', 'Sala de aula', 'Apresentou febre durante a aula.', 'Família avisada por telefone e buscou a criança.'),
      ('ESCOLA', 'PERTENCES', 'LEVE', 'Pátio', 'Perdeu a blusa do uniforme no intervalo.', 'Busca nos achados e perdidos da secretaria.'),
      ('ESCOLA', 'ATRASO_SAIDA', 'LEVE', 'Portão', 'Saída antecipada com a avó, autorizada pela família por telefone.', 'Registro na portaria.'),
      ('ESCOLA', 'PEDAGOGICA', 'LEVE', 'Sala de aula', 'Dificuldade para acompanhar a leitura nas últimas semanas.', 'Encaminhamento ao reforço e conversa com a família na reunião.'),
      ('ESCOLA', 'ELOGIO', 'LEVE', 'Sala de aula', 'Ajudou um colega novo a se enturmar. Parabéns!', null),
      ('FAMILIA', 'BULLYING', 'MODERADA', null, 'A criança contou que colegas colocam apelidos nela no recreio.', null),
      ('FAMILIA', 'ACIDENTE', 'LEVE', null, 'Chegou em casa com um arranhão no braço e não recebemos aviso.', null),
      ('FAMILIA', 'SAUDE', 'LEVE', null, 'Voltou com dor de barriga; pedimos atenção ao lanche desta semana.', null),
      ('FAMILIA', 'OUTRO', 'LEVE', null, 'Não recebemos o bilhete da autorização do passeio.', null)) v(org, tipo, grav, local, descr, prov)
    where v.org = x.origem offset (x.h / 7) % case when x.origem = 'ESCOLA' then 8 else 4 end limit 1) t;

  -- acompanhamento: a escola responde o que a família relatou; a família comenta parte do que a escola registrou
  insert into iara.ocorrencia_eventos (ocorrencia_id, origem, texto, situacao, autor_label, created_at, is_demo)
  select o.id, 'ESCOLA', case o.tipo when 'BULLYING' then 'Conversamos com a turma sobre respeito e a coordenação acompanha o recreio.'
                                    when 'ACIDENTE' then 'Verificamos com a professora: foi no parque; reforçamos o aviso à família nestes casos.'
                                    when 'SAUDE' then 'A nutrição conferiu o lanche; seguimos observando.'
                                    else 'Recebido. A secretaria reenviou o bilhete pela agenda.' end,
         o.situacao, 'Direção da unidade (demonstração)', o.ocorrida_em + interval '1 day', true
  from iara.ocorrencias o where o.is_demo and o.origem = 'FAMILIA' and o.situacao <> 'ABERTA';
  insert into iara.ocorrencia_eventos (ocorrencia_id, origem, texto, autor_label, created_at, is_demo)
  select o.id, 'FAMILIA', 'Obrigada pelo aviso. Vamos conversar com ela(e) em casa também.', 'Família (demonstração)', o.ciencia_familia_em + interval '1 hour', true
  from iara.ocorrencias o where o.is_demo and o.origem = 'ESCOLA' and o.ciencia_familia_em is not null and abs(hashtext(o.id::text)) % 3 = 0;

  -- a Ana (cenário da apresentação): um registro da escola esperando a ciência e um relato antigo da família, já encerrado
  if v_ana is not null then
    insert into iara.ocorrencias (student_id, unit_id, class_id, origem, tipo, gravidade, ocorrida_em, local, descricao, providencias, situacao,
                                  registrada_por_label, registrada_por_guardian, created_at, is_demo)
    select v_ana, e.unit_id, e.class_id, v.org, v.tipo, 'LEVE', v.quando, v.local, v.descr, v.prov, v.sit, v.autor,
           case when v.org = 'FAMILIA' then v_maria end, v.quando, true
    from iara.enrollments e
    cross join (values
      ('ESCOLA', 'ACIDENTE', ((current_date - 1) + time '15:20') at time zone 'America/Sao_Paulo', 'Parque', 'A Ana tropeçou no escorregador e ralou o joelho direito. Chorou um pouco e logo voltou a brincar.',
       'Limpeza com soro e curativo; ficou sob observação até a saída.', 'ABERTA', 'Professora da turma (demonstração)'),
      ('FAMILIA', 'OUTRO', ((current_date - 40) + time '19:10') at time zone 'America/Sao_Paulo', null, 'A Ana voltou para casa sem a mochila de roupas reserva.',
       null, 'ENCERRADA', 'Maria (demonstração)')) v(org, tipo, quando, local, descr, prov, sit, autor)
    where e.student_id = v_ana and e.status = 'ACTIVE';
    select id into v_id from iara.ocorrencias where is_demo and student_id = v_ana and origem = 'FAMILIA' limit 1;
    if v_id is not null then
      insert into iara.ocorrencia_eventos (ocorrencia_id, origem, texto, situacao, autor_label, created_at, is_demo)
      values (v_id, 'ESCOLA', 'A mochila ficou no cabide da sala; a professora entregou no dia seguinte.', 'ENCERRADA', 'Direção da unidade (demonstração)',
              ((current_date - 39) + time '09:00') at time zone 'America/Sao_Paulo', true);
    end if;
  end if;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('ocorrencias', (select count(*) from iara.ocorrencias where is_demo),
    'eventos', (select count(*) from iara.ocorrencia_eventos where is_demo));
end $$;

-- agenda de demonstração: em cerca de 40% dos dias letivos cada turma tem um registro (idempotente: o mesmo dia não repete)
create or replace function iara.demo_gerar_agenda_periodo(p_de date, p_ate date) returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  insert into iara.agenda_escolar (unit_id, class_id, origem, tipo, titulo, texto, data, exige_ciencia, autor_label, ciencias_demo, created_at, is_demo)
  select c.unit_id, c.id, 'ESCOLA', t.tipo, t.titulo, t.texto, d::date, t.tipo in ('RECADO', 'EVENTO') and x.h % 2 = 0,
         case when iara.faixa_cardapio(gl.code) = 'EF' then 'Professor(a) da turma (demonstração)' else 'Professora regente (demonstração)' end,
         case when t.tipo in ('RECADO', 'EVENTO') and x.h % 2 = 0 then
           round(x.n * least(0.92, case when d::date < current_date then 0.62 + (x.h % 25) / 100.0 else 0.18 + (x.h % 30) / 100.0 end))::int else 0 end,
         d::date - interval '1 day' + interval '17 hours', true
  from iara.classes c join iara.grade_levels gl on gl.id = c.grade_level_id
  cross join generate_series(p_de, p_ate, interval '1 day') d
  cross join lateral (select abs(hashtext(c.id::text || d::date::text || 'ag')) h,
                             (select count(*) from iara.enrollments e where e.class_id = c.id and e.status = 'ACTIVE') n) x
  cross join lateral (select * from (values
      ('INF', 'MATERIAL', 'Muda de roupa', 'Mandar uma muda de roupa extra identificada na mochila.'),
      ('INF', 'RECADO', 'Contação de histórias', 'Amanhã teremos contação de histórias: se quiser, mande o livro preferido da criança.'),
      ('INF', 'MATERIAL', 'Higiene', 'Enviar escova e creme dental identificados com o nome.'),
      ('INF', 'LEMBRETE', 'Protetor solar', 'Teremos atividade no pátio: protetor solar e boné na mochila.'),
      ('INF', 'EVENTO', 'Dia do brinquedo', 'Sexta é o dia do brinquedo: a criança pode trazer um brinquedo (sem peças pequenas).'),
      ('INF', 'TAREFA', 'Desenho da família', 'Fazer em casa um desenho da família e trazer na segunda-feira.'),
      ('EF', 'TAREFA', 'Matemática', 'Livro de Matemática, página 45, exercícios 1 a 5.'),
      ('EF', 'TAREFA', 'Leitura', 'Ler o capítulo 3 do livro da biblioteca e contar a história em casa.'),
      ('EF', 'TAREFA', 'Pesquisa', 'Pesquisar uma lenda do Paraná com a família e trazer escrita no caderno.'),
      ('EF', 'RECADO', 'Avaliação', 'Avaliação de Língua Portuguesa na quinta-feira: revisar o caderno.'),
      ('EF', 'MATERIAL', 'Material', 'Trazer régua, cola e tesoura sem ponta.'),
      ('EF', 'LEMBRETE', 'Biblioteca', 'Devolver o livro da biblioteca até sexta-feira.'),
      ('EF', 'EVENTO', 'Feira de ciências', 'Feira de ciências da escola na próxima semana: as famílias estão convidadas.')) v(fx, tipo, titulo, texto)
    where v.fx = case when iara.faixa_cardapio(gl.code) = 'EF' then 'EF' else 'INF' end
    offset (x.h / 11) % case when iara.faixa_cardapio(gl.code) = 'EF' then 7 else 6 end limit 1) t
  where c.status = 'ATIVA' and iara.dia_letivo(d::date, c.unit_id) and x.h % 100 < 40
    and not exists (select 1 from iara.agenda_escolar a where a.class_id = c.id and a.data = d::date and a.is_demo and a.student_id is null);
  get diagnostics v_n = row_count;
  perform set_config('iara.skip_audit', 'off', true);
  return v_n;
end $$;

create or replace function iara.demo_gerar_agenda() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ana uuid := nullif(iara.setting('demo_student_ana'), '')::uuid;
  v_n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.agenda_escolar where is_demo;
  v_n := iara.demo_gerar_agenda_periodo(current_date - 21, current_date + 7);
  -- a turma da Ana: passeio com autorização (pede ciência) e um bilhete individual da professora
  if v_ana is not null then
    insert into iara.agenda_escolar (unit_id, class_id, student_id, origem, tipo, titulo, texto, data, exige_ciencia, autor_label, ciencias_demo, created_at, is_demo)
    select e.unit_id, e.class_id, v.aluno, 'ESCOLA', v.tipo, v.titulo, v.texto, v.dia, v.ciencia, 'Professora regente (demonstração)', v.ciencias, v.criado, true
    from iara.enrollments e
    cross join lateral (values
      (null::uuid, 'EVENTO', 'Passeio ao Parque do Ingá', 'Na sexta-feira a turma visita o Parque do Ingá, das 13h30 às 16h. Mande boné, garrafinha e roupa confortável. Confirme a ciência para autorizar.',
       current_date + 2, true, 11, now() - interval '20 hours'),
      (v_ana, 'BILHETE', null, 'A Ana participou muito da contação de histórias e recontou a história para os colegas. Que orgulho!',
       current_date - 1, false, 0, now() - interval '1 day')) v(aluno, tipo, titulo, texto, dia, ciencia, ciencias, criado)
    where e.student_id = v_ana and e.status = 'ACTIVE';
  end if;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('agenda', (select count(*) from iara.agenda_escolar where is_demo), 'periodo', v_n);
end $$;

-- 9. Limpeza, lançamentos ao vivo e rotina diária (redefinidas com os módulos novos) ------------------------------------------------
create or replace function iara.demo_limpar_modulo(p_modulo text) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v jsonb := '{}'::jsonb;
  n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  case p_modulo
    when 'mural' then
      delete from iara.mural_leituras where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('mural_leituras', n);
      delete from iara.mural_enquete_respostas where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('mural_enquete_respostas', n);
      delete from iara.mural_publicacoes where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('mural_publicacoes', n);
    when 'manutencao' then
      delete from iara.manutencao_chamados where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('manutencao_chamados', n);
      delete from iara.manutencao_eventos where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('manutencao_eventos', n);
    when 'nutricao' then
      delete from iara.refeicoes_servidas where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('refeicoes_servidas', n);
      delete from iara.aluno_restricoes where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('aluno_restricoes', n);
      delete from iara.cardapios where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('cardapios', n);
    when 'frequencia' then
      delete from iara.frequencia_alertas where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('frequencia_alertas', n);
      delete from iara.frequencia_justificativas where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('frequencia_justificativas', n);
      delete from iara.frequencia_faltas where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('frequencia_faltas', n);
      delete from iara.frequencia_registros r where r.is_demo and not exists (select 1 from iara.frequencia_faltas f where f.registro_id = r.id);
      get diagnostics n = row_count; v := v || jsonb_build_object('frequencia_registros', n);
    when 'calendario' then
      delete from iara.calendario_eventos where is_demo and fonte <> 'LEI'; get diagnostics n = row_count; v := v || jsonb_build_object('calendario_eventos', n);
    when 'pessoal' then
      delete from iara.horarios_turma where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('horarios_turma', n);
      delete from iara.mediacoes where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('mediacoes', n);
      delete from iara.staff_formacoes where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('staff_formacoes', n);
      delete from iara.staff_lotacoes where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('staff_lotacoes', n);
      update iara.staff set matricula_funcional = null, cargo = null, carga_horaria_semanal = null, data_admissao = null,
             escolaridade = null, formacao = null, area_atuacao = null
      where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('staff_ficha_limpa', n);
    when 'ocorrencias' then
      delete from iara.ocorrencia_eventos where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('ocorrencia_eventos', n);
      delete from iara.ocorrencias where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('ocorrencias', n);
    when 'agenda' then
      delete from iara.agenda_ciencia where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('agenda_ciencia', n);
      delete from iara.agenda_escolar where is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('agenda_escolar', n);
    else
      raise exception 'Módulo desconhecido: % (mural, manutencao, nutricao, frequencia, calendario, pessoal, ocorrencias, agenda).', p_modulo using errcode = '22023';
  end case;
  perform set_config('iara.skip_audit', 'off', true);
  perform iara.audit_event('DEMO_LIMPEZA_MODULO', 'demo', p_modulo, null,
    'Dados de demonstração do módulo ' || p_modulo || ' apagados: ' || v::text || '.');
  return jsonb_build_object('modulo', p_modulo, 'apagados', v);
end $$;

create or replace function iara.demo_limpar_sprint1() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  return jsonb_build_array(iara.demo_limpar_modulo('agenda'), iara.demo_limpar_modulo('ocorrencias'), iara.demo_limpar_modulo('mural'),
                           iara.demo_limpar_modulo('manutencao'), iara.demo_limpar_modulo('nutricao'), iara.demo_limpar_modulo('frequencia'),
                           iara.demo_limpar_modulo('calendario'), iara.demo_limpar_modulo('pessoal'));
end $$;

create or replace function iara.demo_purge_sprint1(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v jsonb := '{}'::jsonb;
  n integer;
  d timestamptz := coalesce(p_desde, '-infinity'::timestamptz);
begin
  if not iara.demo_mode() then
    raise exception 'Limpeza disponível apenas no modo demonstração.' using errcode = '42501';
  end if;
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.mural_enquete_respostas where not is_demo and respondido_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('enquete_respostas', n);
  delete from iara.mural_leituras where not is_demo and lido_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('mural_leituras', n);
  delete from iara.calendario_eventos where not is_demo and fonte = 'MURAL' and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('calendario_eventos', n);
  delete from iara.mural_publicacoes where not is_demo and publicado_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('mural_publicacoes', n);
  delete from iara.manutencao_chamados where not is_demo and aberto_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('manutencao_chamados', n);
  delete from iara.manutencao_eventos where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('manutencao_eventos', n);
  delete from iara.aluno_restricoes where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('aluno_restricoes', n);
  delete from iara.frequencia_justificativas where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('frequencia_justificativas', n);
  delete from iara.frequencia_registros where not is_demo and registrado_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('frequencia_registros', n);
  delete from iara.ocorrencia_eventos where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('ocorrencia_eventos', n);
  delete from iara.ocorrencias where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('ocorrencias', n);
  update iara.ocorrencias set ciencia_familia_em = null where is_demo and ciencia_familia_em >= d and ciencia_familia_em > created_at + interval '7 hours'
    and student_id = nullif(iara.setting('demo_student_ana'), '')::uuid;
  delete from iara.agenda_ciencia where not is_demo and ciente_em >= d; get diagnostics n = row_count; v := v || jsonb_build_object('agenda_ciencia', n);
  delete from iara.agenda_escolar where not is_demo and created_at >= d; get diagnostics n = row_count; v := v || jsonb_build_object('agenda_escolar', n);
  if p_desde is null then
    delete from iara.refeicoes_servidas where not is_demo; get diagnostics n = row_count; v := v || jsonb_build_object('refeicoes_servidas', n);
  end if;
  perform set_config('iara.skip_audit', 'off', true);
  perform iara.audit_event('DEMO_LIMPEZA_SPRINT1', 'demo', 'sprint1', null, 'Lançamentos ao vivo da demonstração apagados: ' || v::text || '.');
  return v;
end $$;

create or replace function iara.demo_rotina_diaria() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ult date;
  v_ate date;
  v_ref date;
  v_base date;
  v_out jsonb := '{}'::jsonb;
  d integer;
begin
  if not iara.demo_mode() or coalesce(iara.setting('demo_rotina_dia'), '') = current_date::text then
    return null;
  end if;
  if not pg_try_advisory_xact_lock(hashtext('iara.demo_rotina_diaria')) then return null; end if;

  -- chamada: do último dia gerado (completa as turmas que ficaram sem chamada) até ontem, 7 dias por vez
  v_ult := (select max(data) from iara.frequencia_registros where is_demo);
  if v_ult is not null and v_ult < current_date - 1 then
    v_ate := least(current_date - 1, v_ult + 7);
    v_out := v_out || jsonb_build_object('frequencia', iara.demo_gerar_frequencia_periodo(v_ult, v_ate, false),
                                         'alertas', iara.frequencia_detectar_alertas(null));
    v_ref := (select max(data) from iara.refeicoes_servidas where is_demo);
    if v_ref is not null then
      v_out := v_out || jsonb_build_object('refeicoes', iara.demo_gerar_refeicoes_periodo(v_ref, v_ate));
    end if;
  end if;

  v_out := v_out || jsonb_build_object('cardapios', iara.demo_gerar_cardapios(current_date));
  -- agenda das turmas para a próxima semana (o mesmo dia nunca repete)
  if exists (select 1 from iara.agenda_escolar where is_demo) then
    v_out := v_out || jsonb_build_object('agenda', iara.demo_gerar_agenda_periodo(current_date, current_date + 7));
  end if;

  -- manutenção: as datas acompanham o calendário (prazos, atrasos e concluídos dos últimos 30 dias continuam coerentes)
  v_base := nullif(iara.setting('demo_manutencao_base'), '')::date;
  d := current_date - v_base;
  if d > 0 then
    perform set_config('iara.skip_audit', 'on', true);
    update iara.manutencao_chamados set aberto_em = aberto_em + make_interval(days => d), prazo = prazo + make_interval(days => d),
           concluido_em = concluido_em + make_interval(days => d), validado_em = validado_em + make_interval(days => d)
    where is_demo;
    update iara.manutencao_eventos set created_at = created_at + make_interval(days => d) where is_demo;
    v_out := v_out || jsonb_build_object('manutencao_dias', d);
  end if;

  perform set_config('iara.skip_audit', 'on', true);
  update iara.tenants set settings = settings || jsonb_build_object('demo_rotina_dia', current_date::text)
         || case when d > 0 then jsonb_build_object('demo_manutencao_base', current_date) else '{}'::jsonb end
  where id = 1;
  perform set_config('iara.skip_audit', 'off', true);
  return v_out;
end $$;

revoke all on function iara.demo_gerar_ocorrencias(), iara.demo_gerar_agenda_periodo(date, date), iara.demo_gerar_agenda(),
  iara.demo_limpar_modulo(text), iara.demo_limpar_sprint1(), iara.demo_purge_sprint1(timestamptz), iara.demo_rotina_diaria() from public;

-- 10. Classificação dos dados novos -------------------------------------------------------------------------------------------------
insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('ocorrencias', 'descricao', 'SENSIVEL', 'comportamento/saúde da criança (art. 14)', 'acompanhamento escolar e proteção', 'escopo família/unidade/professor da turma; Secretaria por permissão'),
  ('ocorrencias', 'providencias', 'SENSIVEL', 'comportamento/saúde da criança (art. 14)', 'acompanhamento escolar e proteção', 'escopo família/unidade'),
  ('ocorrencias', 'local', 'INTERNO', 'contexto', 'acompanhamento escolar', null),
  ('ocorrencias', 'registrada_por_label', 'PESSOAL', 'identificação', 'auditoria (quem registrou)', null),
  ('ocorrencia_eventos', 'texto', 'SENSIVEL', 'comportamento/saúde da criança (art. 14)', 'acompanhamento entre escola e família', 'escopo família/unidade'),
  ('ocorrencia_eventos', 'autor_label', 'PESSOAL', 'identificação', 'auditoria (quem escreveu)', null),
  ('agenda_escolar', 'texto', 'PESSOAL', 'texto livre', 'comunicação escola–família', 'turma inteira ou só a família do aluno'),
  ('agenda_escolar', 'titulo', 'INTERNO', 'texto livre', 'comunicação escola–família', null),
  ('agenda_escolar', 'autor_label', 'PESSOAL', 'identificação', 'auditoria (quem escreveu)', null)
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade,
  protecao = excluded.protecao;

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
                         'ocorrencias', 'ocorrencia_eventos', 'agenda_escolar', 'agenda_ciencia')
    and (c.column_name ~ '(name|cpf|nis|rg|phone|email|street|number|complement|postal|location|income|birth|race|sus|notes|body|payload|summary|description|details|allerg|medical|legal|need|telefone|nome|jid|flags|breakdown|relationship|marital|occupation|benefit|consent|context|label)'
         or c.column_name ~ '(^|_)(motivo|justificativa|atestado|detalhe|observacao|acao|descricao|formacao|escolaridade|matricula_funcional|data_admissao|opcao|restricao_codigo|providencias|texto)$')
    and c.column_name not in ('contact_label', 'assigned_label', 'sender_label', 'subject', 'file_name_ext', 'registrado_label')
    and not exists (select 1 from iara.classificacao_dados d where d.tabela = c.table_name and d.coluna = c.column_name)
$$;

commit;
