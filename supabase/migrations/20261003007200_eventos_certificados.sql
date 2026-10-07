-- IARA Educa — 072 · Eventos formativos e certificados (Sprint 5)
-- Formações de servidores, oficinas, palestras, feiras, mostras e olimpíadas da rede ou da unidade: inscrições (servidores e alunos),
-- presença e conclusão. Quem atinge a frequência mínima (75%, ajustável por evento) recebe certificado com código e QR, conferido
-- publicamente na mesma página “Verificar declaração”. A família vê os eventos e os certificados do filho (portal e IARA).
begin;

insert into iara.permissions (code, description, is_sensitive) values
  ('eventos.read', 'Consultar eventos formativos e certificados', false),
  ('eventos.manage', 'Organizar eventos, inscrições, presença e certificados', false)
on conflict (code) do update set description = excluded.description;
insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('SECRETARIO', 'eventos.read'), ('SECRETARIO', 'eventos.manage'), ('SUPERINTENDENCIA', 'eventos.read'), ('SUPERINTENDENCIA', 'eventos.manage'),
  ('GERENCIA_EI', 'eventos.read'), ('GERENCIA_EI', 'eventos.manage'), ('INOVACAO', 'eventos.read'), ('INOVACAO', 'eventos.manage'),
  ('DIRETOR_UNIDADE', 'eventos.read'), ('DIRETOR_UNIDADE', 'eventos.manage'), ('SECRETARIA_ESCOLAR', 'eventos.read'), ('SECRETARIA_ESCOLAR', 'eventos.manage'),
  ('PROFESSOR', 'eventos.read'), ('PROFESSOR_AEE', 'eventos.read'), ('NUTRICAO', 'eventos.read'), ('TRANSPORTE', 'eventos.read'), ('ALMOXARIFADO', 'eventos.read')
) v(r, p)
on conflict do nothing;

create table if not exists iara.eventos (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  tipo text not null check (tipo in ('FORMACAO', 'OFICINA', 'PALESTRA', 'FEIRA', 'MOSTRA', 'OLIMPIADA', 'CAMPANHA', 'OUTRO')),
  publico text not null check (publico in ('SERVIDORES', 'ALUNOS', 'TODOS')),
  unit_id integer references iara.education_units(id),   -- nulo: evento da rede
  inicio date not null,
  fim date not null,
  local text,
  carga_horaria numeric(5, 1) not null check (carga_horaria > 0 and carga_horaria <= 400),
  vagas integer,
  frequencia_minima numeric(5, 1) not null default 75,
  descricao text,
  organizador_label text,
  situacao text not null default 'INSCRICOES' check (situacao in ('INSCRICOES', 'EM_ANDAMENTO', 'CONCLUIDO', 'CANCELADO')),
  concluido_em timestamptz,
  criado_em timestamptz not null default now(),
  alterado_em timestamptz,
  is_demo boolean not null default false,
  check (fim >= inicio)
);
create table if not exists iara.evento_participantes (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null references iara.eventos(id) on delete cascade,
  staff_id uuid references iara.staff(id) on delete cascade,
  student_id uuid references iara.students(id) on delete cascade,
  nome text not null,
  funcao text not null default 'PARTICIPANTE' check (funcao in ('PARTICIPANTE', 'PALESTRANTE', 'ORGANIZACAO', 'PREMIADO')),
  presenca_pct numeric(5, 1),
  certificado_codigo text unique,
  certificado_emitido_em timestamptz,
  certificado_hash text,
  inscrito_em timestamptz not null default now(),
  is_demo boolean not null default false,
  check ((staff_id is not null) <> (student_id is not null))
);
create unique index if not exists evento_participante_staff on iara.evento_participantes (evento_id, staff_id) where staff_id is not null;
create unique index if not exists evento_participante_aluno on iara.evento_participantes (evento_id, student_id) where student_id is not null;
alter table iara.eventos enable row level security;
alter table iara.evento_participantes enable row level security;

create or replace function iara.evento_pode_gerir(e iara.eventos) returns boolean
language sql stable security definer set search_path = iara, public
as $$ select iara.has_perm('eventos.manage') and ((e.unit_id is null and iara.my_scope() <> 'UNIT') or (e.unit_id is not null and iara.my_scope() = 'UNIT' and e.unit_id = iara.my_unit())
                                                  or (e.unit_id is not null and iara.my_scope() <> 'UNIT')) $$;

create or replace function iara.evento_json(e iara.eventos, p_detalhe boolean default false) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select to_jsonb(e) || jsonb_build_object('unidade', coalesce((select short_name from iara.education_units where id = e.unit_id), 'Rede municipal'),
    'inscritos', (select count(*) from iara.evento_participantes p where p.evento_id = e.id),
    'certificados', (select count(*) from iara.evento_participantes p where p.evento_id = e.id and p.certificado_codigo is not null),
    'pode_gerir', iara.evento_pode_gerir(e))
  || case when p_detalhe then jsonb_build_object('participantes', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nome', p.nome, 'funcao', p.funcao,
          'tipo', case when p.staff_id is not null then 'SERVIDOR' else 'ALUNO' end, 'presenca', p.presenca_pct, 'certificado', p.certificado_codigo,
          'vinculo', coalesce((select st.cargo from iara.staff st where st.id = p.staff_id), (select c.class_name || ' · ' || u.short_name from iara.enrollments en join iara.classes c on c.id = en.class_id
                     join iara.education_units u on u.id = en.unit_id where en.student_id = p.student_id and en.status = 'ACTIVE' limit 1))) order by p.nome), '[]')
       from iara.evento_participantes p where p.evento_id = e.id)) else '{}'::jsonb end
$$;

create or replace function api.eventos_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
begin
  perform iara.require_perm('eventos.read');
  return jsonb_build_object('pode_criar', iara.has_perm('eventos.manage'),
    'resumo', (select jsonb_build_object('abertos', count(*) filter (where situacao in ('INSCRICOES', 'EM_ANDAMENTO')), 'concluidos', count(*) filter (where situacao = 'CONCLUIDO'),
                 'certificados', (select count(*) from iara.evento_participantes p join iara.eventos e2 on e2.id = p.evento_id where p.certificado_codigo is not null
                                  and (v_unit is null or e2.unit_id = v_unit or e2.unit_id is null)),
                 'horas', (select coalesce(sum(e2.carga_horaria), 0) from iara.evento_participantes p join iara.eventos e2 on e2.id = p.evento_id
                           where p.certificado_codigo is not null and p.staff_id is not null and (v_unit is null or e2.unit_id = v_unit or e2.unit_id is null)))
               from iara.eventos e where v_unit is null or e.unit_id = v_unit or e.unit_id is null),
    'itens', (select coalesce(jsonb_agg(iara.evento_json(e) order by (e.situacao in ('CONCLUIDO', 'CANCELADO')), e.inicio desc), '[]')
              from iara.eventos e where (v_unit is null or e.unit_id = v_unit or e.unit_id is null)
                and (nullif(p ->> 'situacao', '') is null or e.situacao = p ->> 'situacao') and (nullif(p ->> 'publico', '') is null or e.publico = p ->> 'publico')));
end $$;

create or replace function api.evento_detalhe(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  e iara.eventos;
begin
  perform iara.require_perm('eventos.read');
  select * into e from iara.eventos where id = (p ->> 'id')::uuid;
  if e.id is null or (e.unit_id is not null and not iara.can_access_unit(e.unit_id)) then raise exception 'Evento não encontrado.' using errcode = 'P0002'; end if;
  return iara.evento_json(e, true);
end $$;

create or replace function api.evento_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  e iara.eventos;
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
begin
  perform iara.require_perm('eventos.manage');
  if length(btrim(coalesce(p ->> 'titulo', ''))) < 5 then raise exception 'Dê um título ao evento.' using errcode = '22023'; end if;
  if coalesce((p ->> 'carga_horaria')::numeric, 0) not between 0.5 and 400 then raise exception 'Carga horária de 0,5 a 400 horas.' using errcode = '22023'; end if;
  if (p ->> 'fim')::date < (p ->> 'inicio')::date then raise exception 'O fim não pode ser antes do início.' using errcode = '22023'; end if;
  if nullif(p ->> 'id', '') is null then
    insert into iara.eventos (titulo, tipo, publico, unit_id, inicio, fim, local, carga_horaria, vagas, frequencia_minima, descricao, organizador_label)
    values (btrim(p ->> 'titulo'), coalesce(nullif(p ->> 'tipo', ''), 'FORMACAO'), coalesce(nullif(p ->> 'publico', ''), 'SERVIDORES'), v_unit, (p ->> 'inicio')::date, (p ->> 'fim')::date,
            nullif(btrim(coalesce(p ->> 'local', '')), ''), (p ->> 'carga_horaria')::numeric, nullif(p ->> 'vagas', '')::int,
            coalesce(nullif(p ->> 'frequencia_minima', '')::numeric, 75), nullif(btrim(coalesce(p ->> 'descricao', '')), ''), iara.my_label())
    returning * into e;
  else
    select * into e from iara.eventos where id = (p ->> 'id')::uuid for update;
    if e.id is null or not iara.evento_pode_gerir(e) then raise exception 'Evento não encontrado.' using errcode = 'P0002'; end if;
    if e.situacao = 'CONCLUIDO' then raise exception 'Evento concluído (certificados emitidos) não muda.' using errcode = '22023'; end if;
    update iara.eventos set titulo = btrim(p ->> 'titulo'), tipo = coalesce(nullif(p ->> 'tipo', ''), tipo), publico = coalesce(nullif(p ->> 'publico', ''), publico),
           inicio = (p ->> 'inicio')::date, fim = (p ->> 'fim')::date, local = nullif(btrim(coalesce(p ->> 'local', '')), ''), carga_horaria = (p ->> 'carga_horaria')::numeric,
           vagas = nullif(p ->> 'vagas', '')::int, frequencia_minima = coalesce(nullif(p ->> 'frequencia_minima', '')::numeric, frequencia_minima),
           descricao = nullif(btrim(coalesce(p ->> 'descricao', '')), ''), situacao = case when coalesce((p ->> 'cancelar')::boolean, false) then 'CANCELADO' else situacao end, alterado_em = now()
    where id = e.id returning * into e;
  end if;
  perform iara.audit_event('EVENTO', 'evento', e.id::text, e.unit_id, format('Evento “%s” salvo.', e.titulo));
  return iara.evento_json(e, true);
end $$;

-- inscrições: servidores (pela busca) ou alunos (individualmente ou a turma inteira); presença; conclusão com certificados
create or replace function api.evento_participantes(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  e iara.eventos;
  v_acao text := upper(coalesce(p ->> 'acao', ''));
  x jsonb;
  v_n integer := 0;
begin
  select * into e from iara.eventos where id = (p ->> 'evento_id')::uuid for update;
  if e.id is null or not iara.evento_pode_gerir(e) then raise exception 'Evento não encontrado ou fora da sua gestão.' using errcode = '42501'; end if;
  if e.situacao in ('CONCLUIDO', 'CANCELADO') then raise exception 'Evento encerrado.' using errcode = '22023'; end if;
  if v_acao = 'INSCREVER' then
    if nullif(p ->> 'staff_id', '') is not null then
      if e.publico = 'ALUNOS' then raise exception 'Evento para alunos.' using errcode = '22023'; end if;
      insert into iara.evento_participantes (evento_id, staff_id, nome, funcao)
      select e.id, st.id, st.full_name, coalesce(nullif(p ->> 'funcao', ''), 'PARTICIPANTE') from iara.staff st where st.id = (p ->> 'staff_id')::uuid
      on conflict do nothing;
      get diagnostics v_n = row_count;
    elsif nullif(p ->> 'class_id', '') is not null or nullif(p ->> 'student_id', '') is not null then
      if e.publico = 'SERVIDORES' then raise exception 'Evento para servidores.' using errcode = '22023'; end if;
      insert into iara.evento_participantes (evento_id, student_id, nome, funcao)
      select e.id, s.id, s.full_name, coalesce(nullif(p ->> 'funcao', ''), 'PARTICIPANTE')
      from iara.enrollments en join iara.students s on s.id = en.student_id
      where en.status = 'ACTIVE' and (en.class_id = nullif(p ->> 'class_id', '')::uuid or en.student_id = nullif(p ->> 'student_id', '')::uuid)
        and (e.unit_id is null or en.unit_id = e.unit_id) and iara.can_access_student(s.id)
      on conflict do nothing;
      get diagnostics v_n = row_count;
    else
      raise exception 'Escolha o servidor, o aluno ou a turma.' using errcode = '22023';
    end if;
    if e.vagas is not null and (select count(*) from iara.evento_participantes where evento_id = e.id and funcao = 'PARTICIPANTE') > e.vagas then
      raise exception 'Vagas esgotadas (% vagas).', e.vagas using errcode = '22023';
    end if;
  elsif v_acao = 'REMOVER' then
    delete from iara.evento_participantes where id = (p ->> 'id')::uuid and evento_id = e.id;
  elsif v_acao = 'PRESENCA' then
    for x in select * from jsonb_array_elements(coalesce(p -> 'itens', '[]')) loop
      if coalesce((x ->> 'presenca')::numeric, -1) not between 0 and 100 then raise exception 'Presença de 0 a 100%%.' using errcode = '22023'; end if;
      update iara.evento_participantes set presenca_pct = (x ->> 'presenca')::numeric, funcao = coalesce(nullif(x ->> 'funcao', ''), funcao) where id = (x ->> 'id')::uuid and evento_id = e.id;
      v_n := v_n + 1;
    end loop;
    update iara.eventos set situacao = 'EM_ANDAMENTO', alterado_em = now() where id = e.id and situacao = 'INSCRICOES';
  elsif v_acao = 'CONCLUIR' then
    if e.fim > iara.hoje_local() then raise exception 'O evento ainda não terminou.' using errcode = '22023'; end if;
    if exists (select 1 from iara.evento_participantes where evento_id = e.id and presenca_pct is null and funcao = 'PARTICIPANTE') then
      raise exception 'Registre a presença de todos os participantes antes de concluir.' using errcode = '22023';
    end if;
    update iara.evento_participantes ep set certificado_codigo = iara.declaracao_codigo(), certificado_emitido_em = now(),
           certificado_hash = encode(sha256(convert_to(ep.id::text || ep.nome || e.titulo || e.carga_horaria::text, 'UTF8')), 'hex')
    where ep.evento_id = e.id and ep.certificado_codigo is null and (ep.funcao <> 'PARTICIPANTE' or ep.presenca_pct >= e.frequencia_minima);
    get diagnostics v_n = row_count;
    update iara.eventos set situacao = 'CONCLUIDO', concluido_em = now(), alterado_em = now() where id = e.id;
    insert into iara.notifications (tenant_id, guardian_id, student_id, channel, event_type, title, body, status)
    select 1, sg.guardian_id, ep.student_id, 'PORTAL', 'CERTIFICADO', 'Certificado disponível',
           format('%s recebeu certificado de participação em “%s”. Veja em Vida escolar.', split_part(ep.nome, ' ', 1), e.titulo), 'ENVIADA'
    from iara.evento_participantes ep join iara.student_guardians sg on sg.student_id = ep.student_id and sg.end_date is null and sg.is_primary
    where ep.evento_id = e.id and ep.certificado_codigo is not null and ep.certificado_emitido_em >= now() - interval '1 minute';
    perform iara.audit_event('EVENTO', 'evento', e.id::text, e.unit_id, format('Evento “%s” concluído: %s certificado(s).', e.titulo, v_n));
  else
    raise exception 'Ação inválida.' using errcode = '22023';
  end if;
  return iara.evento_json((select x2 from iara.eventos x2 where x2.id = e.id), true) || jsonb_build_object('afetados', v_n);
end $$;

-- busca de servidores e turmas para as inscrições (quem organiza o evento)
create or replace function api.evento_busca(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  e iara.eventos;
  v_q text := iara.norm(btrim(coalesce(p ->> 'q', '')));
begin
  select * into e from iara.eventos where id = (p ->> 'evento_id')::uuid;
  if e.id is null or not iara.evento_pode_gerir(e) then raise exception 'Evento fora da sua gestão.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'servidores', case when e.publico <> 'ALUNOS' and length(v_q) >= 3 then (select coalesce(jsonb_agg(jsonb_build_object('id', st.id, 'nome', st.full_name, 'cargo', coalesce(st.cargo, st.role),
                    'unidade', u.short_name)), '[]') from (select * from iara.staff st where iara.norm(st.full_name) like '%' || v_q || '%'
                    and (e.unit_id is null or st.unit_id = e.unit_id) order by st.full_name limit 15) st left join iara.education_units u on u.id = st.unit_id) else '[]'::jsonb end,
    'turmas', case when e.publico <> 'SERVIDORES' and e.unit_id is not null then (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'turma', c.class_name, 'alunos', c.active_enrollments_count)
                    order by c.class_name), '[]') from iara.classes c where c.unit_id = e.unit_id and c.status = 'ATIVA') else '[]'::jsonb end);
end $$;

-- certificado completo (para imprimir): servidor da gestão, o próprio aluno pela família
create or replace function api.certificado_ver(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  ep iara.evento_participantes;
  e iara.eventos;
begin
  select * into ep from iara.evento_participantes where certificado_codigo = upper(btrim(coalesce(p ->> 'codigo', '')));
  if ep.id is null then raise exception 'Certificado não encontrado.' using errcode = 'P0002'; end if;
  select * into e from iara.eventos where id = ep.evento_id;
  if not ((iara.my_guardian() is not null and ep.student_id in (select iara.my_student_ids()))
          or (iara.my_guardian() is null and iara.has_perm('eventos.read') and (e.unit_id is null or iara.can_access_unit(e.unit_id)))) then
    raise exception 'Certificado não encontrado.' using errcode = 'P0002';
  end if;
  return jsonb_build_object('codigo', ep.certificado_codigo, 'nome', ep.nome, 'funcao', ep.funcao, 'evento', e.titulo, 'tipo', e.tipo, 'inicio', e.inicio, 'fim', e.fim,
    'carga_horaria', e.carga_horaria, 'presenca', ep.presenca_pct, 'local', e.local, 'unidade', coalesce((select name from iara.education_units where id = e.unit_id), 'Rede municipal de ensino'),
    'emitido_em', ep.certificado_emitido_em, 'hash', left(ep.certificado_hash, 16), 'is_demo', ep.is_demo);
end $$;

-- verificação pública: declarações e, agora, certificados (mesmo formato de código)
create or replace function api.declaracao_verificar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_cod text := upper(regexp_replace(coalesce(p ->> 'codigo', ''), '[^A-Za-z0-9]', '', 'g'));
  d iara.declaracoes;
  ep iara.evento_participantes;
  e iara.eventos;
begin
  if length(v_cod) <> 12 then return jsonb_build_object('encontrada', false, 'mensagem', 'O código tem 12 letras e números (ex.: ABCD-EFGH-JK23).'); end if;
  v_cod := substr(v_cod, 1, 4) || '-' || substr(v_cod, 5, 4) || '-' || substr(v_cod, 9, 4);
  update iara.declaracoes set verificacoes = verificacoes + 1, ultima_verificacao = now() where codigo = v_cod returning * into d;
  if d.id is not null then
    return jsonb_build_object('encontrada', true) || iara.declaracao_json(d, false)
      || jsonb_build_object('tipo_rotulo', d.conteudo ->> 'titulo', 'orgao', d.conteudo ->> 'orgao');
  end if;
  select * into ep from iara.evento_participantes where certificado_codigo = v_cod;
  if ep.id is not null then
    select * into e from iara.eventos where id = ep.evento_id;
    return jsonb_build_object('encontrada', true, 'codigo', v_cod, 'tipo', 'CERTIFICADO', 'tipo_rotulo', 'Certificado de participação', 'situacao', 'VALIDA',
      'aluno', iara.nome_abreviado(ep.nome), 'emitida_em', ep.certificado_emitido_em, 'valida_ate', null, 'hash', left(ep.certificado_hash, 16),
      'unidade', coalesce((select short_name from iara.education_units where id = e.unit_id), 'Rede municipal de ensino'),
      'resumo', format('%s — %s h (%s a %s).', e.titulo, replace(e.carga_horaria::text, '.', ','), to_char(e.inicio, 'DD/MM/YYYY'), to_char(e.fim, 'DD/MM/YYYY')),
      'orgao', 'Secretaria Municipal de Educação de Maringá', 'is_demo', ep.is_demo);
  end if;
  return jsonb_build_object('encontrada', false, 'mensagem', 'Nenhum documento com este código. Confira as letras e os números; se persistir, o documento não é autêntico.');
end $$;

create or replace function api.familia_eventos(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('student_id', s.id, 'primeiro_nome', split_part(s.full_name, ' ', 1),
      'eventos', (select coalesce(jsonb_agg(jsonb_build_object('titulo', e.titulo, 'tipo', e.tipo, 'inicio', e.inicio, 'fim', e.fim, 'carga_horaria', e.carga_horaria,
                    'situacao', e.situacao, 'funcao', ep.funcao, 'certificado', ep.certificado_codigo,
                    'unidade', coalesce((select short_name from iara.education_units where id = e.unit_id), 'Rede municipal')) order by e.inicio desc), '[]')
                  from iara.evento_participantes ep join iara.eventos e on e.id = ep.evento_id where ep.student_id = s.id and e.situacao <> 'CANCELADO'))
      order by s.full_name), '[]')
    from iara.students s where s.id in (select iara.my_student_ids()));
end $$;

-- demonstração: formações da rede (servidores), feiras, mostras e olimpíadas nas escolas (alunos)
create or replace function iara.demo_gerar_eventos() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ana uuid := nullif(iara.setting('demo_student_ana'), '')::uuid;
  v_ana_class uuid := (select class_id from iara.enrollments where student_id = v_ana and status = 'ACTIVE' limit 1);
  ev record;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.eventos where is_demo;
  insert into iara.eventos (titulo, tipo, publico, unit_id, inicio, fim, local, carga_horaria, vagas, descricao, organizador_label, situacao, concluido_em, is_demo)
  values
    ('Formação: alfabetização no 1º e 2º ano', 'FORMACAO', 'SERVIDORES', null, date '2026-03-09', date '2026-06-15', 'Centro de Formação da SEDUC', 40, 300,
     'Encontros quinzenais sobre consciência fonológica, leitura e escrita.', 'Diretoria de Ensino (demonstração)', 'CONCLUIDO', now() - interval '110 days', true),
    ('Formação: educação inclusiva e AEE na sala comum', 'FORMACAO', 'SERVIDORES', null, date '2026-04-06', date '2026-08-31', 'Centro de Formação da SEDUC', 30, 250,
     'Planejamento acessível, mediação e trabalho com o professor do AEE.', 'Gerência de Educação Especial (demonstração)', 'CONCLUIDO', now() - interval '35 days', true),
    ('Oficina: primeiros socorros na escola', 'OFICINA', 'SERVIDORES', null, date '2026-08-12', date '2026-08-12', 'Auditório da SEDUC', 4, 120,
     'Lei Lucas (Lei nº 13.722/2018): noções de primeiros socorros para professores e funcionários.', 'Diretoria de Gestão Educacional (demonstração)', 'CONCLUIDO', now() - interval '50 days', true),
    ('Formação: busca ativa e frequência escolar', 'FORMACAO', 'SERVIDORES', null, iara.hoje_local() + 12, iara.hoje_local() + 26, 'On-line', 12, 400,
     'O fluxo de contato com as famílias, a rede de apoio e o Conselho Tutelar.', 'Superintendência (demonstração)', 'INSCRICOES', null, true),
    ('Olimpíada municipal de matemática', 'OLIMPIADA', 'ALUNOS', null, date '2026-09-15', date '2026-09-15', 'Escolas da rede', 3, null,
     'Prova para o 4º e o 5º ano; os destaques recebem certificado de premiação.', 'Diretoria de Ensino (demonstração)', 'CONCLUIDO', now() - interval '18 days', true);
  -- feira de ciências / mostra cultural em parte das escolas
  insert into iara.eventos (titulo, tipo, publico, unit_id, inicio, fim, local, carga_horaria, descricao, organizador_label, situacao, concluido_em, is_demo)
  select case when u.unit_type = 'CMEI' then 'Mostra cultural: brincadeiras e cantigas' else 'Feira de ciências da escola' end, case when u.unit_type = 'CMEI' then 'MOSTRA' else 'FEIRA' end,
         'ALUNOS', u.id, date '2026-09-24', date '2026-09-25', 'Pátio da unidade', 8, 'Trabalhos das turmas apresentados às famílias.', 'Direção da unidade (demonstração)',
         'CONCLUIDO', now() - interval '10 days', true
  from iara.education_units u where u.status = 'ATIVA' and abs(hashtext(u.id::text || 'feira')) % 100 < 45;
  -- servidores nas formações
  insert into iara.evento_participantes (evento_id, staff_id, nome, presenca_pct, inscrito_em, is_demo)
  select e.id, st.id, st.full_name, case when e.situacao = 'CONCLUIDO' then (array[100, 95, 90, 85, 80, 70, 60])[1 + abs(hashtext(st.id::text || e.id::text)) % 7] end, e.criado_em, true
  from iara.eventos e join iara.staff st on st.role in ('PROFESSOR', 'AEE', 'EDUCADOR') and abs(hashtext(st.id::text || e.titulo)) % 100 < case e.tipo when 'OFICINA' then 4 else 9 end
  where e.is_demo and e.publico = 'SERVIDORES';
  -- alunos: olimpíada (4º e 5º ano, parte das turmas) e feiras (turmas inteiras da unidade)
  insert into iara.evento_participantes (evento_id, student_id, nome, funcao, presenca_pct, is_demo)
  select e.id, s.id, s.full_name, case when abs(hashtext(s.id::text || 'olimp')) % 100 < 6 then 'PREMIADO' else 'PARTICIPANTE' end, 100, true
  from iara.eventos e join iara.enrollments en on en.status = 'ACTIVE' join iara.classes c on c.id = en.class_id join iara.grade_levels g on g.id = c.grade_level_id
  join iara.students s on s.id = en.student_id
  where e.is_demo and e.tipo = 'OLIMPIADA' and g.code in ('EF4', 'EF5') and abs(hashtext(c.id::text || 'olimp')) % 100 < 40;
  insert into iara.evento_participantes (evento_id, student_id, nome, presenca_pct, is_demo)
  select e.id, s.id, s.full_name, case when abs(hashtext(s.id::text || e.id::text)) % 100 < 92 then 100 else 0 end, true
  from iara.eventos e join iara.enrollments en on en.unit_id = e.unit_id and en.status = 'ACTIVE' join iara.students s on s.id = en.student_id
  where e.is_demo and e.tipo in ('FEIRA', 'MOSTRA') and (abs(hashtext(en.class_id::text || 'feira')) % 100 < 50 or en.class_id = v_ana_class);
  -- certificados dos eventos concluídos
  update iara.evento_participantes ep set certificado_codigo = iara.declaracao_codigo(), certificado_emitido_em = e.concluido_em,
         certificado_hash = encode(sha256(convert_to(ep.id::text || ep.nome || e.titulo || e.carga_horaria::text, 'UTF8')), 'hex')
  from iara.eventos e where e.id = ep.evento_id and e.is_demo and e.situacao = 'CONCLUIDO' and (ep.funcao <> 'PARTICIPANTE' or ep.presenca_pct >= e.frequencia_minima);
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('eventos', (select count(*) from iara.eventos where is_demo), 'participantes', (select count(*) from iara.evento_participantes where is_demo),
    'certificados', (select count(*) from iara.evento_participantes where is_demo and certificado_codigo is not null));
end $$;

create or replace function iara.demo_purge_eventos(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  d timestamptz := coalesce(p_desde, '-infinity'::timestamptz);
  n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.eventos where not is_demo and criado_em >= d; get diagnostics n = row_count;
  delete from iara.evento_participantes where not is_demo and inscrito_em >= d;
  delete from iara.notifications where created_at >= d and event_type = 'CERTIFICADO';
  if exists (select 1 from iara.eventos where is_demo and alterado_em >= d) then perform iara.demo_gerar_eventos(); end if;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('eventos', n);
end $$;

revoke all on function iara.demo_gerar_eventos(), iara.demo_purge_eventos(timestamptz) from public;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('evento_participantes', 'nome', 'PESSOAL', 'identificação', 'certificado', 'organização do evento; verificação pública só com nome abreviado'),
  ('eventos', 'organizador_label', 'PESSOAL', 'identificação', 'auditoria', null)
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

select iara.demo_gerar_eventos() where iara.demo_mode();

commit;
