-- IARA Educa — 042 · Sprint 1 (base): perfis novos de demonstração e permissões dos módulos
-- Módulos do sprint: pessoal (funcionários e professores), frequência, nutrição e cardápio, manutenção, mural e calendário.
-- Perfis novos: Professor(a) (uma unidade, as próprias turmas), Nutrição (rede) e Infraestrutura/Manutenção (rede).
-- Os dados destes módulos na demonstração são de exemplo (is_demo) e saem com iara.demo_limpar_sprint1(); na produção
-- as tabelas nascem vazias e recebem dados oficiais.
begin;

alter table iara.app_users add column if not exists staff_id uuid references iara.staff(id) on delete set null;

insert into iara.organizational_roles (code, tenant_id, name, short_name, description, scope_type, stage_filter, question, org_unit, is_persona, sort) values
  ('PROFESSOR', 1, 'Professor(a) regente', 'Professor(a)', 'Minhas turmas: chamada do dia, frequência dos alunos, horário e o mural da escola.',
   'UNIT', null, 'Quem está na sala hoje?', 'Unidade escolar', true, 13),
  ('NUTRICAO', 1, 'Nutrição escolar · SEDUC', 'Nutrição', 'Cardápios, restrições alimentares validadas, lista da cozinha e refeições servidas na rede.',
   'NETWORK', null, 'Cada criança está comendo o que pode?', 'Gerência da Merenda Escolar', true, 14),
  ('MANUTENCAO', 1, 'Infraestrutura e manutenção · SEDUC', 'Manutenção', 'Chamados das unidades: triagem, vistoria, orçamento, execução e validação pela escola.',
   'NETWORK', null, 'O que está quebrado e quem está resolvendo?', 'Diretoria de Infraestrutura', true, 15)
on conflict (code) do update set name = excluded.name, short_name = excluded.short_name, description = excluded.description,
  scope_type = excluded.scope_type, question = excluded.question, org_unit = excluded.org_unit, is_persona = excluded.is_persona, sort = excluded.sort;

insert into iara.permissions (code, description, is_sensitive) values
  ('pessoal.read', 'Consultar cadastro funcional, lotação, horários e carga horária dos servidores', true),
  ('frequencia.read', 'Consultar a frequência dos alunos', true),
  ('frequencia.write', 'Registrar a chamada e as faltas', true),
  ('frequencia.acompanhar', 'Tratar alertas de ausência e justificativas de falta', true),
  ('nutricao.read', 'Painel da nutrição: cardápios, restrições (contagens) e refeições servidas', false),
  ('nutricao.manage', 'Publicar cardápios e validar restrições alimentares', true),
  ('cozinha.read', 'Lista da cozinha: crianças com restrição e a instrução de preparo (sem laudo)', true),
  ('manutencao.read', 'Consultar chamados de manutenção e obras', false),
  ('manutencao.open', 'Abrir e validar chamados de manutenção da própria unidade', false),
  ('manutencao.manage', 'Triar, vistoriar, orçar e executar chamados de manutenção', false),
  ('mural.publish', 'Publicar no mural e no calendário (rede ou unidade, conforme o perfil)', false)
on conflict (code) do update set description = excluded.description, is_sensitive = excluded.is_sensitive;

insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('PROFESSOR', 'units.read'), ('PROFESSOR', 'classes.read'), ('PROFESSOR', 'config.read'), ('PROFESSOR', 'frequencia.read'), ('PROFESSOR', 'frequencia.write'),
  ('NUTRICAO', 'units.read'), ('NUTRICAO', 'classes.read'), ('NUTRICAO', 'config.read'), ('NUTRICAO', 'kpi.network'), ('NUTRICAO', 'nutricao.read'),
  ('NUTRICAO', 'nutricao.manage'), ('NUTRICAO', 'cozinha.read'), ('NUTRICAO', 'mural.publish'),
  ('MANUTENCAO', 'units.read'), ('MANUTENCAO', 'config.read'), ('MANUTENCAO', 'kpi.network'), ('MANUTENCAO', 'manutencao.read'), ('MANUTENCAO', 'manutencao.manage'),
  ('DIRETOR_UNIDADE', 'pessoal.read'), ('DIRETOR_UNIDADE', 'frequencia.read'), ('DIRETOR_UNIDADE', 'frequencia.write'), ('DIRETOR_UNIDADE', 'frequencia.acompanhar'),
  ('DIRETOR_UNIDADE', 'cozinha.read'), ('DIRETOR_UNIDADE', 'nutricao.read'), ('DIRETOR_UNIDADE', 'manutencao.read'), ('DIRETOR_UNIDADE', 'manutencao.open'),
  ('DIRETOR_UNIDADE', 'mural.publish'),
  ('SECRETARIA_ESCOLAR', 'pessoal.read'), ('SECRETARIA_ESCOLAR', 'frequencia.read'), ('SECRETARIA_ESCOLAR', 'frequencia.write'),
  ('SECRETARIA_ESCOLAR', 'frequencia.acompanhar'), ('SECRETARIA_ESCOLAR', 'cozinha.read'), ('SECRETARIA_ESCOLAR', 'manutencao.read'),
  ('SECRETARIA_ESCOLAR', 'manutencao.open'), ('SECRETARIA_ESCOLAR', 'mural.publish'),
  ('SECRETARIO', 'pessoal.read'), ('SECRETARIO', 'frequencia.read'), ('SECRETARIO', 'frequencia.acompanhar'), ('SECRETARIO', 'nutricao.read'),
  ('SECRETARIO', 'manutencao.read'), ('SECRETARIO', 'manutencao.manage'), ('SECRETARIO', 'mural.publish'),
  ('SUPERINTENDENCIA', 'pessoal.read'), ('SUPERINTENDENCIA', 'frequencia.read'), ('SUPERINTENDENCIA', 'frequencia.acompanhar'),
  ('SUPERINTENDENCIA', 'nutricao.read'), ('SUPERINTENDENCIA', 'manutencao.read'), ('SUPERINTENDENCIA', 'manutencao.manage'), ('SUPERINTENDENCIA', 'mural.publish'),
  ('GERENCIA_EI', 'pessoal.read'), ('GERENCIA_EI', 'frequencia.read'), ('GERENCIA_EI', 'nutricao.read'), ('GERENCIA_EI', 'manutencao.read'),
  ('GERENCIA_EI', 'mural.publish'),
  ('INOVACAO', 'pessoal.read'), ('INOVACAO', 'frequencia.read'), ('INOVACAO', 'nutricao.read'), ('INOVACAO', 'manutencao.read'),
  ('PREFEITO', 'nutricao.read'), ('PREFEITO', 'manutencao.read')
) v(r, p)
on conflict do nothing;

-- turmas do professor da sessão (vínculo vigente em class_staff)
create or replace function iara.minhas_turmas() returns uuid[]
language sql stable security definer set search_path = iara, public
as $$
  select coalesce(array_agg(cs.class_id), '{}') from iara.class_staff cs
  join iara.app_users u on u.staff_id = cs.staff_id
  where u.id = iara.current_user_id() and (cs.end_date is null or cs.end_date >= current_date)
$$;

-- sessão de demonstração: o Professor(a) recebe um regente da unidade escolhida (com as turmas dele)
create or replace function iara.session_create(p_persona text, p_unit integer, p_token_hash text, p_user_agent text)
returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r iara.organizational_roles;
  v_user uuid := gen_random_uuid();
  v_unit integer;
  v_guardian uuid;
  v_staff uuid;
  v_staff_name text;
  v_label text;
  v_unit_name text;
  v_suffix text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4));
begin
  if not coalesce((iara.setting('demo_mode'))::boolean, false) then
    raise exception 'Seleção de perfil disponível apenas no modo demonstração.' using errcode = '42501';
  end if;
  select * into r from iara.organizational_roles where code = p_persona and is_persona;
  if not found then
    raise exception 'Perfil desconhecido: %', p_persona using errcode = '22023';
  end if;
  if r.scope_type = 'UNIT' then
    v_unit := coalesce(p_unit, (iara.setting('demo_unit_maria'))::int);
    select name into v_unit_name from iara.education_units where id = v_unit;
    if v_unit_name is null then
      raise exception 'Unidade inválida.' using errcode = '22023';
    end if;
  elsif r.scope_type = 'GUARDIAN' and r.code = 'CIDADAO' then  -- CIDADAO_NOVO começa sem cadastro (faz pela IARA ou portal)
    v_guardian := (iara.setting('demo_guardian_maria'))::uuid;
  end if;
  if r.code = 'PROFESSOR' then
    select s.id, s.full_name into v_staff, v_staff_name
    from iara.class_staff cs join iara.classes c on c.id = cs.class_id join iara.staff s on s.id = cs.staff_id
    where c.unit_id = v_unit and c.status = 'ATIVA' and cs.role_type = 'REGENTE'
    order by c.class_name, s.full_name limit 1;
    if v_staff is null then
      raise exception 'Esta unidade não tem turma com professor(a) regente cadastrado(a).' using errcode = '22023';
    end if;
  end if;
  v_label := case r.code
    when 'PREFEITO' then 'Gabinete do Prefeito'
    when 'SECRETARIO' then 'Secretaria Municipal de Educação'
    when 'SUPERINTENDENCIA' then 'Superintendência da SEDUC'
    when 'ANALISTA_CENTRAL' then 'Analista · Central de Vagas'
    when 'GERENCIA_EI' then 'Gerência de Educação Infantil'
    when 'DIRETOR_UNIDADE' then 'Direção · ' || v_unit_name
    when 'SECRETARIA_ESCOLAR' then 'Secretaria escolar · ' || v_unit_name
    when 'PROFESSOR' then v_staff_name || ' · ' || v_unit_name
    when 'ATENDIMENTO' then 'Atendimento ao Cidadão'
    when 'INOVACAO' then 'Diretoria de Inovação Educacional'
    when 'NUTRICAO' then 'Nutrição escolar · SEDUC'
    when 'MANUTENCAO' then 'Infraestrutura · SEDUC'
    when 'CIDADAO' then (select full_name from iara.guardians where id = v_guardian)
    else r.name end || ' (demo #' || v_suffix || ')';

  insert into iara.app_users (id, tenant_id, display_name, role_code, unit_id, guardian_id, staff_id, auth_provider, is_demo, last_seen_at)
  values (v_user, 1, v_label, r.code, v_unit, v_guardian, v_staff, 'DEMO', true, now());
  insert into iara.app_sessions (token_hash, user_id, expires_at, user_agent)
  values (p_token_hash, v_user, now() + interval '12 hours', left(p_user_agent, 300));

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  perform iara.audit_event('LOGIN_DEMO', 'app_user', v_user::text, v_unit, 'Sessão de demonstração iniciada: ' || r.name);
  return jsonb_build_object('user_id', v_user, 'role', r.code);
end $$;

create or replace function api.me(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare v jsonb;
begin
  select jsonb_build_object(
    'user_id', u.id, 'display_name', u.display_name, 'role', r.code, 'role_name', r.name, 'role_short', r.short_name,
    'scope', r.scope_type, 'stage_filter', r.stage_filter, 'question', r.question, 'org_unit', r.org_unit, 'is_demo', u.is_demo,
    'unit', (select jsonb_build_object('id', x.id, 'name', x.name, 'short_name', x.short_name, 'type', x.unit_type, 'lat', x.lat, 'lng', x.lng)
             from iara.education_units x where x.id = u.unit_id),
    'guardian', (select jsonb_build_object('id', g.id, 'name', g.full_name) from iara.guardians g where g.id = u.guardian_id),
    'staff', (select jsonb_build_object('id', s.id, 'name', s.full_name, 'role', s.role) from iara.staff s where s.id = u.staff_id),
    'turmas', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.class_name, 'shift', c.shift,
                 'grade', (select short_name from iara.grade_levels gl where gl.id = c.grade_level_id)) order by c.class_name), '[]'::jsonb)
               from iara.classes c where u.staff_id is not null and c.id = any (iara.minhas_turmas())),
    'permissions', (select coalesce(jsonb_agg(permission_code order by permission_code), '[]'::jsonb) from iara.role_permissions where role_code = u.role_code))
  into v
  from iara.app_users u join iara.organizational_roles r on r.code = u.role_code
  where u.id = iara.current_user_id();
  if v is null then
    raise exception 'Sessão expirada. Escolha um perfil novamente.' using errcode = '28000';
  end if;
  return v;
end $$;

commit;
