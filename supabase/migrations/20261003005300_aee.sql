-- IARA Educa — 053 · Sprint 2: atendimento educacional especializado (AEE) estruturado
-- Plano de AEE por aluno (PAEE): avaliação inicial, objetivos, recursos de acessibilidade, onde e quando é o atendimento
-- (sala de recursos na própria escola, em escola-polo, itinerante ou domiciliar), orientações para a sala de aula e revisão.
-- Atendimentos registrados pelo(a) professor(a) do AEE (presença e atividade). Quem vê o quê:
--   · professor(a) do AEE e gestão da unidade: plano completo (com a necessidade, dado sensível);
--   · professor(a) regente: só as orientações para a sala e os recursos — nunca o diagnóstico nem o laudo;
--   · família: o plano em linguagem simples, os dias do atendimento e a presença, com "Estou ciente".
-- Perfil novo de demonstração: Professor(a) do AEE (atende alunos da própria escola e das escolas que a sala de recursos cobre).
-- Planos e atendimentos de demonstração são fictícios (is_demo). Q-16 define o modelo oficial do PAEE na rede.
begin;

insert into iara.organizational_roles (code, tenant_id, name, short_name, description, scope_type, stage_filter, question, org_unit, is_persona, sort) values
  ('PROFESSOR_AEE', 1, 'Professor(a) do AEE', 'Professor(a) do AEE', 'Sala de recursos: meus alunos, plano de AEE de cada um, atendimentos do dia e orientações para os regentes.',
   'UNIT', null, 'Cada aluno com deficiência tem plano e está sendo atendido?', 'Unidade escolar · sala de recursos', true, 14)
on conflict (code) do update set name = excluded.name, short_name = excluded.short_name, description = excluded.description,
  scope_type = excluded.scope_type, question = excluded.question, org_unit = excluded.org_unit, is_persona = excluded.is_persona;

insert into iara.permissions (code, description, is_sensitive) values
  ('aee.read', 'Consultar planos de AEE completos (inclui a necessidade educacional — dado sensível)', true),
  ('aee.write', 'Elaborar e revisar planos de AEE e registrar atendimentos', true),
  ('aee.orientacoes', 'Ver as orientações de sala e os recursos dos alunos com AEE das próprias turmas (sem diagnóstico)', false)
on conflict (code) do update set description = excluded.description, is_sensitive = excluded.is_sensitive;
insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('PROFESSOR_AEE', 'units.read'), ('PROFESSOR_AEE', 'classes.read'), ('PROFESSOR_AEE', 'config.read'), ('PROFESSOR_AEE', 'aee.read'),
  ('PROFESSOR_AEE', 'aee.write'), ('PROFESSOR_AEE', 'aee.orientacoes'),
  ('PROFESSOR', 'aee.orientacoes'),
  ('DIRETOR_UNIDADE', 'aee.read'), ('DIRETOR_UNIDADE', 'aee.write'), ('DIRETOR_UNIDADE', 'aee.orientacoes'),
  ('SECRETARIA_ESCOLAR', 'aee.read'), ('SECRETARIA_ESCOLAR', 'aee.orientacoes'),
  ('SUPERINTENDENCIA', 'aee.read')
) v(r, p)
on conflict do nothing;

-- 1. Tabelas -------------------------------------------------------------------------------------------------------------------
create table if not exists iara.aee_planos (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references iara.students(id) on delete cascade,
  unit_id integer references iara.education_units(id),
  profissional_id uuid references iara.staff(id) on delete set null,
  modalidade text not null check (modalidade in ('SRM_PROPRIA', 'SRM_POLO', 'ITINERANTE', 'DOMICILIAR')),
  local_unit_id integer references iara.education_units(id),
  dias text[] not null default '{}' check (dias <@ array['SEG', 'TER', 'QUA', 'QUI', 'SEX']),
  turno text check (turno in ('MANHA', 'TARDE', 'NOITE')),
  duracao_min smallint not null default 50 check (duracao_min between 20 and 240),
  avaliacao_inicial text,
  objetivos text not null,
  recursos text[] not null default '{}',
  orientacoes_sala text,
  articulacao_familia text,
  inicio date not null default current_date,
  revisar_em date not null,
  situacao text not null default 'EM_ELABORACAO' check (situacao in ('EM_ELABORACAO', 'ATIVO', 'EM_REVISAO', 'ENCERRADO')),
  motivo_encerramento text,
  familia_ciente_em timestamptz,
  familia_ciente_label text,
  criado_por_label text,
  created_at timestamptz not null default now(),
  alterado_em timestamptz,
  is_demo boolean not null default true
);
create index if not exists aee_planos_student_idx on iara.aee_planos (student_id, situacao);
create index if not exists aee_planos_prof_idx on iara.aee_planos (profissional_id) where situacao <> 'ENCERRADO';
create unique index if not exists aee_planos_um_vigente on iara.aee_planos (student_id) where situacao <> 'ENCERRADO';

create table if not exists iara.aee_atendimentos (
  id uuid primary key default gen_random_uuid(),
  plano_id uuid not null references iara.aee_planos(id) on delete cascade,
  student_id uuid not null references iara.students(id) on delete cascade,
  data date not null,
  presenca text not null check (presenca in ('PRESENTE', 'FALTA', 'FALTA_JUSTIFICADA', 'CANCELADO')),
  atividade text,
  observacao text,
  registrado_por_label text,
  registrado_em timestamptz not null default now(),
  is_demo boolean not null default true,
  unique (plano_id, data)
);
create index if not exists aee_atend_student_idx on iara.aee_atendimentos (student_id, data desc);

alter table iara.aee_planos enable row level security;
alter table iara.aee_atendimentos enable row level security;

-- 2. Acesso ---------------------------------------------------------------------------------------------------------------------
create or replace function iara.meu_staff() returns uuid
language sql stable security definer set search_path = iara, public
as $$ select staff_id from iara.app_users where id = iara.current_user_id() $$;

-- plano completo: gestão da unidade (escopo do aluno) ou o(a) professor(a) do AEE (alunos da própria escola ou que atende)
create or replace function iara.aee_acesso(p_student uuid, p_perm text default 'aee.read') returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select iara.has_perm(p_perm) and iara.my_role() <> 'PROFESSOR' and (
    iara.can_access_student(p_student)
    or (iara.my_role() = 'PROFESSOR_AEE' and exists (select 1 from iara.aee_planos pl where pl.student_id = p_student
                                                     and pl.profissional_id = iara.meu_staff() and pl.situacao <> 'ENCERRADO')))
$$;

create or replace function iara.aee_recurso_rotulo(p text) returns text
language sql immutable as $$
  select case p when 'COMUNICACAO_ALTERNATIVA' then 'Comunicação alternativa (pranchas, figuras)' when 'LIBRAS' then 'Libras (intérprete/instrutor)'
    when 'BRAILLE' then 'Braille e soroban' when 'AMPLIACAO' then 'Material ampliado e lupa' when 'TECNOLOGIA_ASSISTIVA' then 'Tecnologia assistiva'
    when 'MOBILIARIO_ADAPTADO' then 'Mobiliário adaptado e acessibilidade física' when 'MEDIADOR' then 'Profissional de apoio (mediador)'
    when 'ENRIQUECIMENTO' then 'Enriquecimento curricular' when 'MATERIAL_CONCRETO' then 'Material concreto e jogos'
    when 'ROTINA_VISUAL' then 'Rotina visual e antecipação' when 'TEMPO_ESTENDIDO' then 'Tempo estendido nas atividades' else p end
$$;

create or replace function iara.aee_plano_json(pl iara.aee_planos, p_nivel text) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  -- p_nivel: COMPLETO (AEE e gestão), SALA (professor regente), FAMILIA
  select jsonb_build_object('id', pl.id, 'student_id', pl.student_id, 'situacao', pl.situacao, 'modalidade', pl.modalidade,
      'profissional', st.full_name, 'profissional_id', pl.profissional_id, 'local', lu.short_name, 'local_unit_id', pl.local_unit_id,
      'dias', to_jsonb(pl.dias), 'turno', pl.turno, 'duracao_min', pl.duracao_min,
      'recursos', (select coalesce(jsonb_agg(jsonb_build_object('codigo', r, 'rotulo', iara.aee_recurso_rotulo(r))), '[]') from unnest(pl.recursos) r),
      'orientacoes_sala', pl.orientacoes_sala, 'inicio', pl.inicio, 'revisar_em', pl.revisar_em,
      'revisao_vencida', pl.situacao = 'ATIVO' and pl.revisar_em < current_date, 'is_demo', pl.is_demo)
    || case when p_nivel in ('COMPLETO', 'FAMILIA') then jsonb_build_object('objetivos', pl.objetivos, 'articulacao_familia', pl.articulacao_familia,
         'familia_ciente_em', pl.familia_ciente_em, 'familia_ciente_label', pl.familia_ciente_label) else '{}' end
    || case when p_nivel = 'COMPLETO' then jsonb_build_object('avaliacao_inicial', pl.avaliacao_inicial, 'motivo_encerramento', pl.motivo_encerramento,
         'criado_por', pl.criado_por_label, 'criado_em', pl.created_at, 'alterado_em', pl.alterado_em) else '{}' end
  from (select 1) x left join iara.staff st on st.id = pl.profissional_id left join iara.education_units lu on lu.id = pl.local_unit_id
$$;

create or replace function iara.aee_presenca(p_student uuid, p_dias integer default 60) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('previstos', count(*) filter (where presenca <> 'CANCELADO'), 'presencas', count(*) filter (where presenca = 'PRESENTE'),
    'faltas', count(*) filter (where presenca in ('FALTA', 'FALTA_JUSTIFICADA')),
    'percentual', case when count(*) filter (where presenca <> 'CANCELADO') > 0
      then round(100.0 * count(*) filter (where presenca = 'PRESENTE') / count(*) filter (where presenca <> 'CANCELADO'), 0) end,
    'ultimo', max(data))
  from iara.aee_atendimentos where student_id = p_student and data >= current_date - p_dias
$$;

-- 3. Listas, plano e painel -----------------------------------------------------------------------------------------------------------
create or replace function api.aee_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_aee boolean := iara.my_role() = 'PROFESSOR_AEE';
  v_eu uuid := iara.meu_staff();
  v_unit integer := case when iara.my_scope() = 'UNIT' and not v_aee then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_sit text := nullif(p ->> 'situacao', '');
  v_q text := iara.norm(nullif(btrim(coalesce(p ->> 'q', '')), ''));
  v_dow text := (array['DOM', 'SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SAB'])[extract(dow from current_date)::int + 1];
begin
  perform iara.require_perm('aee.read');
  if iara.my_role() = 'PROFESSOR' then raise exception 'Use as orientações das suas turmas.' using errcode = '42501'; end if;
  if not v_aee and v_unit is null and v_q is null then raise exception 'Escolha a unidade ou busque pelo nome.' using errcode = '22023'; end if;
  return (with base as (
      select s.id, s.full_name, e.unit_id, e.class_id, ss.special_education_need nec,
             (select pl from iara.aee_planos pl where pl.student_id = s.id order by (pl.situacao <> 'ENCERRADO') desc, pl.created_at desc limit 1) pl
      from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
      left join iara.student_sensitive ss on ss.student_id = s.id
      where s.aee_status
        and (case when v_aee then (e.unit_id = iara.my_unit() or exists (select 1 from iara.aee_planos x where x.student_id = s.id and x.profissional_id = v_eu and x.situacao <> 'ENCERRADO'))
                  else (v_unit is null or e.unit_id = v_unit) and iara.can_access_unit(e.unit_id) end)
        and (v_q is null or iara.norm(s.full_name) like '%' || v_q || '%')),
    b as (select base.*, (base.pl).situacao sit, (base.pl).revisar_em rev, (base.pl).profissional_id prof, (base.pl).dias dias from base),
    f as (select * from b where v_sit is null
            or (v_sit = 'SEM_PLANO' and (sit is null or sit = 'ENCERRADO'))
            or (v_sit = 'REVISAO_VENCIDA' and sit = 'ATIVO' and rev < current_date)
            or (v_sit = 'MEUS' and prof = v_eu)
            or sit = v_sit)
    select jsonb_build_object(
      'unidade', (select name from iara.education_units where id = coalesce(v_unit, case when v_aee then iara.my_unit() end)),
      'professor_aee', v_aee, 'pode_editar', iara.has_perm('aee.write'), 'dia', v_dow,
      'contagem', jsonb_build_object('total', (select count(*) from b), 'sem_plano', (select count(*) from b where sit is null or sit = 'ENCERRADO'),
        'ativos', (select count(*) from b where sit = 'ATIVO'), 'elaboracao', (select count(*) from b where sit = 'EM_ELABORACAO'),
        'revisao', (select count(*) from b where sit = 'EM_REVISAO'), 'vencidas', (select count(*) from b where sit = 'ATIVO' and rev < current_date),
        'meus', (select count(*) from b where prof = v_eu)),
      'hoje', case when v_aee then (select coalesce(jsonb_agg(jsonb_build_object('student_id', b.id, 'aluno', b.full_name, 'plano_id', (b.pl).id,
            'turno', (b.pl).turno, 'local', (select short_name from iara.education_units where id = (b.pl).local_unit_id), 'modalidade', (b.pl).modalidade,
            'registro', (select a.presenca from iara.aee_atendimentos a where a.plano_id = (b.pl).id and a.data = current_date)) order by (b.pl).turno, b.full_name), '[]')
          from b where prof = v_eu and sit in ('ATIVO', 'EM_REVISAO') and v_dow = any (dias)) end,
      'itens', (select coalesce(jsonb_agg(jsonb_build_object('student_id', f.id, 'aluno', f.full_name, 'necessidade', f.nec,
            'unidade', u.short_name, 'turma', c.class_name, 'serie', gl.short_name,
            'plano', case when f.pl is not null then jsonb_build_object('id', (f.pl).id, 'situacao', f.sit, 'modalidade', (f.pl).modalidade,
              'profissional', (select full_name from iara.staff where id = f.prof), 'meu', f.prof = v_eu, 'dias', to_jsonb(f.dias), 'turno', (f.pl).turno,
              'revisar_em', f.rev, 'revisao_vencida', f.sit = 'ATIVO' and f.rev < current_date, 'ciente', (f.pl).familia_ciente_em is not null) end,
            'mediador', (select st.full_name from iara.mediacoes md join iara.staff st on st.id = md.staff_id where md.student_id = f.id and (md.fim is null or md.fim >= current_date) limit 1),
            'presenca', iara.aee_presenca(f.id, 30) ->> 'percentual')
          order by (f.sit is null or f.sit = 'ENCERRADO') desc, f.sit = 'ATIVO' and f.rev < current_date desc, f.full_name), '[]')
        from (select * from f order by full_name limit 400) f join iara.education_units u on u.id = f.unit_id
        left join iara.classes c on c.id = f.class_id left join iara.grade_levels gl on gl.id = c.grade_level_id)));
end $$;

create or replace function api.aee_plano(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  s iara.students;
  e record;
  pl iara.aee_planos;
begin
  if not iara.aee_acesso(v_student) then raise exception 'Aluno fora do seu escopo de AEE.' using errcode = '42501'; end if;
  select * into s from iara.students where id = v_student;
  select en.unit_id, en.class_id, c.class_name, c.shift, gl.short_name serie, u.name unidade, u.lat, u.lng into e
  from iara.enrollments en join iara.classes c on c.id = en.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
  join iara.education_units u on u.id = en.unit_id where en.student_id = v_student and en.status = 'ACTIVE' limit 1;
  select * into pl from iara.aee_planos where student_id = v_student order by (situacao <> 'ENCERRADO') desc, created_at desc limit 1;
  perform iara.audit_event('AEE_PLANO_CONSULTA', 'student', v_student::text, e.unit_id, 'Plano de AEE consultado.');
  return jsonb_build_object(
    'aluno', jsonb_build_object('id', s.id, 'nome', s.full_name, 'nome_social', s.social_name, 'nascimento', s.birth_date, 'idade', iara.age_text(s.birth_date),
      'foto_arquivo_id', s.foto_arquivo_id, 'unidade', e.unidade, 'unit_id', e.unit_id, 'turma', e.class_name, 'class_id', e.class_id, 'serie', e.serie, 'turno', e.shift),
    'necessidade', (select to_jsonb(x) - 'student_id' - 'legal_notes' from iara.student_sensitive x where x.student_id = v_student),
    'mediador', (select jsonb_build_object('nome', st.full_name, 'desde', md.inicio) from iara.mediacoes md join iara.staff st on st.id = md.staff_id
                 where md.student_id = v_student and (md.fim is null or md.fim >= current_date) limit 1),
    'plano', case when pl.id is not null then iara.aee_plano_json(pl, 'COMPLETO') end,
    'historico', (select coalesce(jsonb_agg(jsonb_build_object('id', h.id, 'situacao', h.situacao, 'inicio', h.inicio, 'motivo_encerramento', h.motivo_encerramento) order by h.created_at desc), '[]')
                  from iara.aee_planos h where h.student_id = v_student and h.id is distinct from pl.id),
    'presenca', iara.aee_presenca(v_student, 60),
    'atendimentos', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'data', a.data, 'presenca', a.presenca, 'atividade', a.atividade,
        'observacao', a.observacao, 'por', a.registrado_por_label) order by a.data desc), '[]')
      from (select * from iara.aee_atendimentos where student_id = v_student order by data desc limit 30) a),
    'profissionais', (select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'nome', z.full_name, 'unidade', z.short_name, 'unit_id', z.unit_id, 'km', z.km) order by z.km), '[]')
      from (select st.id, st.full_name, u.short_name, st.unit_id,
                   round((sqrt(power((u.lat - e.lat) * 111.0, 2) + power((u.lng - e.lng) * 102.0, 2)))::numeric, 1) km
            from iara.staff st join iara.education_units u on u.id = st.unit_id
            where st.role = 'AEE' and coalesce(st.situacao, 'ATIVO') = 'ATIVO' order by km nulls last limit 6) z),
    'pode_editar', iara.aee_acesso(v_student, 'aee.write'));
end $$;

create or replace function api.aee_plano_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id uuid := nullif(p ->> 'id', '')::uuid;
  v_student uuid := (p ->> 'student_id')::uuid;
  v_sit text := coalesce(nullif(p ->> 'situacao', ''), 'EM_ELABORACAO');
  v_dias text[] := array(select jsonb_array_elements_text(coalesce(p -> 'dias', '[]')));
  v_rec text[] := array(select jsonb_array_elements_text(coalesce(p -> 'recursos', '[]')));
  v_prof uuid := nullif(p ->> 'profissional_id', '')::uuid;
  v_mod text := coalesce(nullif(p ->> 'modalidade', ''), 'SRM_PROPRIA');
  v_unit integer;
  v_local integer;
  old iara.aee_planos;
  pl iara.aee_planos;
  v_avisar boolean;
begin
  if not iara.aee_acesso(v_student, 'aee.write') then raise exception 'Sem permissão para o plano de AEE deste aluno.' using errcode = '42501'; end if;
  if not exists (select 1 from iara.students where id = v_student and aee_status) then
    raise exception 'O aluno não tem indicação de AEE no cadastro. Registre a necessidade na ficha antes do plano.' using errcode = '22023';
  end if;
  if v_sit not in ('EM_ELABORACAO', 'ATIVO', 'EM_REVISAO', 'ENCERRADO') then raise exception 'Situação inválida.' using errcode = '22023'; end if;
  if v_mod not in ('SRM_PROPRIA', 'SRM_POLO', 'ITINERANTE', 'DOMICILIAR') then raise exception 'Modalidade inválida.' using errcode = '22023'; end if;
  if not v_dias <@ array['SEG', 'TER', 'QUA', 'QUI', 'SEX'] then raise exception 'Dias inválidos.' using errcode = '22023'; end if;
  if not v_rec <@ array['COMUNICACAO_ALTERNATIVA', 'LIBRAS', 'BRAILLE', 'AMPLIACAO', 'TECNOLOGIA_ASSISTIVA', 'MOBILIARIO_ADAPTADO', 'MEDIADOR',
                        'ENRIQUECIMENTO', 'MATERIAL_CONCRETO', 'ROTINA_VISUAL', 'TEMPO_ESTENDIDO'] then
    raise exception 'Recurso inválido.' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p ->> 'objetivos', ''))) < 20 then raise exception 'Descreva os objetivos do atendimento (pelo menos 20 caracteres).' using errcode = '22023'; end if;
  if v_sit = 'ATIVO' then
    if cardinality(v_dias) = 0 or v_prof is null then raise exception 'Para ativar, informe o(a) professor(a) do AEE e os dias do atendimento.' using errcode = '22023'; end if;
    if length(btrim(coalesce(p ->> 'orientacoes_sala', ''))) < 20 then
      raise exception 'Para ativar, escreva as orientações para a sala de aula (o regente vê só isto).' using errcode = '22023';
    end if;
  end if;
  if v_sit = 'ENCERRADO' and length(btrim(coalesce(p ->> 'motivo_encerramento', ''))) < 10 then raise exception 'Informe o motivo do encerramento.' using errcode = '22023'; end if;
  if v_prof is not null and not exists (select 1 from iara.staff where id = v_prof and role = 'AEE') then raise exception 'Profissional não é do AEE.' using errcode = '22023'; end if;
  select unit_id into v_unit from iara.enrollments where student_id = v_student and status = 'ACTIVE' limit 1;
  -- onde acontece: na escola do aluno (sala própria ou professor itinerante), na escola-polo do professor, ou em casa
  v_local := case v_mod when 'SRM_POLO' then coalesce((select unit_id from iara.staff where id = v_prof), v_unit) when 'DOMICILIAR' then null else v_unit end;

  if v_id is null then
    if exists (select 1 from iara.aee_planos where student_id = v_student and situacao <> 'ENCERRADO') then
      raise exception 'Este aluno já tem um plano vigente: abra e revise o plano atual.' using errcode = '23505';
    end if;
    insert into iara.aee_planos (student_id, unit_id, profissional_id, modalidade, local_unit_id, dias, turno, duracao_min, avaliacao_inicial, objetivos, recursos,
                                 orientacoes_sala, articulacao_familia, inicio, revisar_em, situacao, motivo_encerramento, criado_por_label, is_demo)
    values (v_student, v_unit, v_prof, v_mod, v_local, v_dias, nullif(p ->> 'turno', ''), coalesce(nullif(p ->> 'duracao_min', '')::smallint, 50),
            nullif(btrim(p ->> 'avaliacao_inicial'), ''), btrim(p ->> 'objetivos'), v_rec, nullif(btrim(p ->> 'orientacoes_sala'), ''),
            nullif(btrim(p ->> 'articulacao_familia'), ''), coalesce(nullif(p ->> 'inicio', '')::date, current_date),
            coalesce(nullif(p ->> 'revisar_em', '')::date, current_date + 180), v_sit, nullif(btrim(p ->> 'motivo_encerramento'), ''), iara.my_label(), false)
    returning * into pl;
    v_avisar := v_sit = 'ATIVO';
  else
    select * into old from iara.aee_planos where id = v_id and student_id = v_student for update;
    if old.id is null then raise exception 'Plano não encontrado.' using errcode = 'P0002'; end if;
    if old.situacao = 'ENCERRADO' then raise exception 'Plano encerrado não se altera: abra um novo.' using errcode = '22023'; end if;
    update iara.aee_planos set profissional_id = v_prof, modalidade = v_mod, local_unit_id = v_local, dias = v_dias, turno = nullif(p ->> 'turno', ''),
           duracao_min = coalesce(nullif(p ->> 'duracao_min', '')::smallint, duracao_min), avaliacao_inicial = nullif(btrim(p ->> 'avaliacao_inicial'), ''),
           objetivos = btrim(p ->> 'objetivos'), recursos = v_rec, orientacoes_sala = nullif(btrim(p ->> 'orientacoes_sala'), ''),
           articulacao_familia = nullif(btrim(p ->> 'articulacao_familia'), ''), revisar_em = coalesce(nullif(p ->> 'revisar_em', '')::date, revisar_em),
           situacao = v_sit, motivo_encerramento = nullif(btrim(p ->> 'motivo_encerramento'), ''), alterado_em = now(),
           familia_ciente_em = case when v_sit = 'ATIVO' and (old.situacao <> 'ATIVO' or old.objetivos <> btrim(p ->> 'objetivos') or old.dias <> v_dias)
                                    then null else familia_ciente_em end
    where id = v_id returning * into pl;
    v_avisar := v_sit = 'ATIVO' and (old.situacao <> 'ATIVO' or old.objetivos <> pl.objetivos or old.dias <> pl.dias);
  end if;
  if v_avisar then
    perform iara.avisar_familia(v_student, 'AEE_PLANO', 'Plano do atendimento especializado',
      'O plano de AEE da criança foi ' || case when v_id is null or old.situacao <> 'ATIVO' then 'definido' else 'atualizado' end
      || '. Veja os dias do atendimento e os objetivos em Vida escolar → AEE e confirme que está ciente.');
  end if;
  perform iara.audit_event('AEE_PLANO_SALVO', 'student', v_student::text, v_unit, 'Plano de AEE ' || lower(replace(v_sit, '_', ' ')) || '.');
  return iara.aee_plano_json(pl, 'COMPLETO');
end $$;

create or replace function api.aee_atendimento_registrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  pl iara.aee_planos;
  v_data date := coalesce(nullif(p ->> 'data', '')::date, current_date);
  v_pres text := p ->> 'presenca';
  a iara.aee_atendimentos;
begin
  select * into pl from iara.aee_planos where id = (p ->> 'plano_id')::uuid;
  if pl.id is null or not iara.aee_acesso(pl.student_id, 'aee.write') then raise exception 'Plano não encontrado ou fora do seu escopo.' using errcode = 'P0002'; end if;
  if pl.situacao not in ('ATIVO', 'EM_REVISAO') then raise exception 'O plano não está ativo.' using errcode = '22023'; end if;
  if v_pres not in ('PRESENTE', 'FALTA', 'FALTA_JUSTIFICADA', 'CANCELADO') then raise exception 'Presença inválida.' using errcode = '22023'; end if;
  if v_data > current_date or v_data < pl.inicio or v_data < current_date - 30 then raise exception 'Data fora do período (até 30 dias atrás, a partir do início do plano).' using errcode = '22023'; end if;
  if v_pres = 'PRESENTE' and length(btrim(coalesce(p ->> 'atividade', ''))) < 5 then raise exception 'Descreva a atividade do atendimento.' using errcode = '22023'; end if;
  insert into iara.aee_atendimentos (plano_id, student_id, data, presenca, atividade, observacao, registrado_por_label, is_demo)
  values (pl.id, pl.student_id, v_data, v_pres, nullif(btrim(p ->> 'atividade'), ''), nullif(btrim(p ->> 'observacao'), ''), iara.my_label(), false)
  on conflict (plano_id, data) do update set presenca = excluded.presenca, atividade = excluded.atividade, observacao = excluded.observacao,
    registrado_por_label = excluded.registrado_por_label, registrado_em = now(), is_demo = false
  returning * into a;
  perform iara.audit_event('AEE_ATENDIMENTO', 'student', pl.student_id::text, pl.unit_id, 'Atendimento de AEE registrado: ' || lower(v_pres) || '.');
  return jsonb_build_object('id', a.id, 'data', a.data, 'presenca', a.presenca, 'presenca_resumo', iara.aee_presenca(pl.student_id, 60));
end $$;

-- regente: alunos com AEE das próprias turmas, só orientações e recursos (sem diagnóstico)
create or replace function api.aee_orientacoes_turma(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_class uuid := (p ->> 'class_id')::uuid;
begin
  if not iara.turma_acesso(v_class, 'aee.orientacoes') then raise exception 'Turma fora do seu escopo.' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('student_id', s.id, 'aluno', coalesce(s.social_name, s.full_name),
      'plano', (select iara.aee_plano_json(pl, 'SALA') from iara.aee_planos pl where pl.student_id = s.id and pl.situacao in ('ATIVO', 'EM_REVISAO') limit 1),
      'mediador', (select st.full_name from iara.mediacoes md join iara.staff st on st.id = md.staff_id where md.student_id = s.id and (md.fim is null or md.fim >= current_date) limit 1))
      order by s.full_name), '[]')
    from iara.enrollments e join iara.students s on s.id = e.student_id where e.class_id = v_class and e.status = 'ACTIVE' and s.aee_status);
end $$;

create or replace function api.aee_painel(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_det boolean := iara.has_perm('aee.read');
begin
  if not (v_det or iara.has_perm('kpi.network')) then raise exception 'Sem permissão.' using errcode = '42501'; end if;
  if iara.my_role() in ('PROFESSOR', 'PROFESSOR_AEE') then raise exception 'Use a lista de alunos do AEE.' using errcode = '42501'; end if;
  return (with al as (
      select s.id, e.unit_id, ss.special_education_need nec,
             (select pl from iara.aee_planos pl where pl.student_id = s.id and pl.situacao <> 'ENCERRADO' limit 1) pl
      from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
      left join iara.student_sensitive ss on ss.student_id = s.id
      where s.aee_status and (v_unit is null or e.unit_id = v_unit)),
    at as (select a.* from iara.aee_atendimentos a join al on al.id = a.student_id where a.data >= current_date - 30)
    select jsonb_build_object('unidade', (select name from iara.education_units where id = v_unit),
      'alunos', (select count(*) from al),
      'com_plano_ativo', (select count(*) from al where (pl).situacao = 'ATIVO'),
      'em_elaboracao', (select count(*) from al where (pl).situacao = 'EM_ELABORACAO'),
      'em_revisao', (select count(*) from al where (pl).situacao = 'EM_REVISAO'),
      'sem_plano', (select count(*) from al where pl is null),
      'revisao_vencida', (select count(*) from al where (pl).situacao = 'ATIVO' and (pl).revisar_em < current_date),
      'sem_ciencia', (select count(*) from al where (pl).situacao = 'ATIVO' and (pl).familia_ciente_em is null),
      'com_mediador', (select count(*) from al where exists (select 1 from iara.mediacoes md where md.student_id = al.id and (md.fim is null or md.fim >= current_date))),
      'presenca_30d', (select round(100.0 * count(*) filter (where presenca = 'PRESENTE') / nullif(count(*) filter (where presenca <> 'CANCELADO'), 0), 1) from at),
      'atendimentos_30d', (select count(*) from at where presenca = 'PRESENTE'),
      'por_necessidade', (select coalesce(jsonb_agg(jsonb_build_object('necessidade', coalesce(nec, 'Não informada'), 'alunos', q, 'com_plano', cp) order by q desc), '[]')
                          from (select nec, count(*) q, count(*) filter (where (pl).situacao = 'ATIVO') cp from al group by 1) z),
      'por_modalidade', (select coalesce(jsonb_object_agg(m, q), '{}') from (select (pl).modalidade m, count(*) q from al where pl is not null group by 1) z),
      'professores', (select coalesce(jsonb_agg(jsonb_build_object('nome', st.full_name, 'unidade', u.short_name, 'alunos', q) order by q desc), '[]')
                      from (select (pl).profissional_id pid, count(*) q from al where (pl).profissional_id is not null group by 1) z
                      join iara.staff st on st.id = z.pid join iara.education_units u on u.id = st.unit_id),
      'por_unidade', case when v_unit is null then (select coalesce(jsonb_agg(jsonb_build_object('unit_id', z.unit_id, 'unidade', u.short_name, 'alunos', q, 'sem_plano', sp, 'vencidas', vc)
                       order by sp desc, vc desc), '[]')
                      from (select unit_id, count(*) q, count(*) filter (where pl is null) sp, count(*) filter (where (pl).situacao = 'ATIVO' and (pl).revisar_em < current_date) vc
                            from al group by 1) z join iara.education_units u on u.id = z.unit_id) end,
      'detalhe', v_det));
end $$;

-- 4. Família ----------------------------------------------------------------------------------------------------------------------
create or replace function api.familia_aee(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('student_id', s.id, 'primeiro_nome', split_part(s.full_name, ' ', 1),
      'plano', iara.aee_plano_json(pl, 'FAMILIA'),
      'presenca', iara.aee_presenca(s.id, 60),
      'atendimentos', (select coalesce(jsonb_agg(jsonb_build_object('data', a.data, 'presenca', a.presenca, 'atividade', a.atividade) order by a.data desc), '[]')
                       from (select * from iara.aee_atendimentos where plano_id = pl.id order by data desc limit 8) a))
      order by s.full_name), '[]')
    from iara.aee_planos pl join iara.students s on s.id = pl.student_id
    where pl.student_id in (select iara.my_student_ids()) and pl.situacao in ('ATIVO', 'EM_REVISAO'));
end $$;

create or replace function api.familia_aee_ciente(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  pl iara.aee_planos;
begin
  select * into pl from iara.aee_planos where id = (p ->> 'plano_id')::uuid;
  if pl.id is null or iara.my_guardian() is null or pl.student_id not in (select iara.my_student_ids()) then raise exception 'Plano não encontrado.' using errcode = 'P0002'; end if;
  update iara.aee_planos set familia_ciente_em = coalesce(familia_ciente_em, now()),
         familia_ciente_label = coalesce(familia_ciente_label, (select full_name from iara.guardians where id = iara.my_guardian()))
  where id = pl.id;
  perform iara.audit_event('AEE_CIENCIA_FAMILIA', 'student', pl.student_id::text, pl.unit_id, 'Família ciente do plano de AEE.');
  return jsonb_build_object('ok', true);
end $$;

-- 5. Sessão de demonstração: o(a) Professor(a) do AEE é quem atende a unidade escolhida -------------------------------------------
create or replace function iara.aee_professor_da_unidade(p_unit integer) returns uuid
language sql stable security definer set search_path = iara, public
as $$
  select coalesce(
    (select pl.profissional_id from iara.aee_planos pl where pl.unit_id = p_unit and pl.situacao <> 'ENCERRADO' and pl.profissional_id is not null
     group by 1 order by count(*) desc limit 1),
    (select st.id from iara.staff st join iara.education_units u on u.id = st.unit_id, iara.education_units x
     where x.id = p_unit and st.role = 'AEE' order by power(u.lat - x.lat, 2) + power(u.lng - x.lng, 2) nulls last limit 1))
$$;

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
  elsif r.code = 'PROFESSOR_AEE' then
    -- a sala de recursos pode ficar em outra escola (polo): a sessão fica na unidade do(a) professor(a) e vê os alunos que atende
    v_staff := iara.aee_professor_da_unidade(v_unit);
    if v_staff is null then
      raise exception 'Nenhum(a) professor(a) do AEE cadastrado(a) na rede.' using errcode = '22023';
    end if;
    select s.full_name, s.unit_id, u.name into v_staff_name, v_unit, v_unit_name
    from iara.staff s join iara.education_units u on u.id = s.unit_id where s.id = v_staff;
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
    when 'PROFESSOR_AEE' then v_staff_name || ' · AEE · ' || v_unit_name
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

-- 6. Demonstração -------------------------------------------------------------------------------------------------------------------
-- cerca de 88% dos alunos com AEE têm plano; o(a) professor(a) é o(a) da sala de recursos mais próxima
drop function if exists iara.demo_gerar_aee(uuid[]);
create or replace function iara.demo_gerar_aee(p_students uuid[] default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ini date := (iara.setting('ano_letivo_inicio'))::date;
begin
  perform set_config('iara.skip_audit', 'on', true);
  if p_students is null then
    delete from iara.aee_atendimentos where is_demo;
    delete from iara.aee_planos where is_demo;
  end if;
  create temp table tmp_aee on commit drop as
  select s.id student_id, e.unit_id, c.shift, gl.code grade, coalesce(ss.special_education_need, '') nec,
         abs(hashtext(s.id::text || 'aee')) % 100 h,
         (select st.id from iara.staff st join iara.education_units u on u.id = st.unit_id where st.role = 'AEE' and st.is_demo
          order by (st.unit_id = e.unit_id) desc, power(u.lat - eu.lat, 2) + power(u.lng - eu.lng, 2) nulls last limit 1) prof
  from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
  join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id join iara.education_units eu on eu.id = e.unit_id
  left join iara.student_sensitive ss on ss.student_id = s.id
  where s.aee_status and (p_students is null or s.id = any (p_students))
    and not exists (select 1 from iara.aee_planos x where x.student_id = s.id and x.situacao <> 'ENCERRADO');

  insert into iara.aee_planos (student_id, unit_id, profissional_id, modalidade, local_unit_id, dias, turno, duracao_min, avaliacao_inicial, objetivos,
                               recursos, orientacoes_sala, articulacao_familia, inicio, revisar_em, situacao, familia_ciente_em, familia_ciente_label,
                               criado_por_label, created_at, is_demo)
  select t.student_id, t.unit_id, t.prof, t.modal, case t.modal when 'SRM_POLO' then (select unit_id from iara.staff where id = t.prof) when 'DOMICILIAR' then null else t.unit_id end,
         case when t.modal = 'ITINERANTE' then array[(array['SEG', 'TER', 'QUA', 'QUI', 'SEX'])[1 + t.h % 5]]
              else case t.h % 5 when 0 then array['SEG', 'QUA'] when 1 then array['TER', 'QUI'] when 2 then array['QUA', 'SEX'] when 3 then array['SEG', 'QUI'] else array['TER', 'SEX'] end end,
         case when t.modal = 'ITINERANTE' then t.shift when t.shift = 'MANHA' then 'TARDE' else 'MANHA' end,
         case when t.modal = 'ITINERANTE' then 60 else 50 end,
         t.aval, t.obj, t.rec, t.ori,
         'Devolutiva bimestral à família; caderno de comunicação casa–escola; orientações para a rotina em casa.',
         t.ini, case when t.h < 8 then current_date - (t.h + 3) when t.h between 72 and 79 then current_date - (t.h - 70) else greatest(t.ini + 60, date '2026-12-07' + t.h % 5) end,
         case when t.h between 80 and 89 then 'EM_ELABORACAO' when t.h between 72 and 79 then 'EM_REVISAO' else 'ATIVO' end,
         case when t.h < 72 and t.h % 4 <> 0 then t.ini::timestamptz + interval '6 days 14 hours' end,
         case when t.h < 72 and t.h % 4 <> 0 then 'Responsável (demonstração)' end,
         'Professor(a) do AEE (demonstração)', t.ini::timestamptz + interval '9 hours', true
  from (select t0.*,
          case when t0.grade in ('CRECHE', 'PRE') and not exists (select 1 from iara.staff st where st.unit_id = t0.unit_id and st.role = 'AEE') then 'ITINERANTE'
               when exists (select 1 from iara.staff st where st.unit_id = t0.unit_id and st.role = 'AEE') then 'SRM_PROPRIA'
               when t0.h % 37 = 0 then 'DOMICILIAR' else 'SRM_POLO' end modal,
          case when t0.h between 80 and 89 then current_date - (t0.h % 20) else greatest(v_ini + 28, v_ini + 28 + (t0.h % 60)) end ini,
          case when t0.nec ilike '%visual%' then 'Usa o resíduo visual para leitura com fonte ampliada; boa memória auditiva; desloca-se com autonomia em ambientes conhecidos.'
               when t0.nec ilike '%auditiva%' then 'Comunica-se por Libras em construção e leitura labial; interage bem em duplas; precisa de apoio visual para instruções.'
               when t0.nec ilike '%física%' then 'Usa cadeira de rodas; preserva a comunicação oral; precisa de adaptação de mobiliário e de apoio na escrita (preensão).'
               when t0.nec ilike '%intelectual%' then 'Aprende melhor com material concreto e repetição; atenção curta; reconhece letras do nome e conta até 10.'
               when t0.nec ilike '%TEA%' then 'Rotina previsível ajuda muito; sensível a barulho; comunica-se melhor com apoio visual; interesse forte por números e animais.'
               when t0.nec ilike '%altas habilidades%' then 'Raciocínio lógico e vocabulário acima do esperado para a idade; perde o interesse em tarefas repetitivas.'
               else 'Em avaliação pedagógica; observa-se atraso na linguagem e na coordenação motora fina.' end aval,
          case when t0.nec ilike '%visual%' then 'Desenvolver a leitura e a escrita com material ampliado e recursos ópticos; orientação e mobilidade na escola.'
               when t0.nec ilike '%auditiva%' then 'Ampliar o vocabulário em Libras e o português escrito como segunda língua; participação nas atividades orais com apoio visual.'
               when t0.nec ilike '%física%' then 'Garantir a participação em todas as atividades com acessibilidade física e tecnologia assistiva para a escrita.'
               when t0.nec ilike '%intelectual%' then 'Avançar na alfabetização e no raciocínio matemático com material concreto; ganhar autonomia nas rotinas.'
               when t0.nec ilike '%TEA%' then 'Ampliar a comunicação funcional e a participação nas atividades coletivas; antecipar mudanças com rotina visual.'
               when t0.nec ilike '%altas habilidades%' then 'Enriquecimento curricular com projetos de investigação; desenvolvimento socioemocional no trabalho em grupo.'
               else 'Estimular a linguagem oral e a coordenação motora; acompanhar a investigação com a família e a saúde.' end obj,
          case when t0.nec ilike '%visual%' then array['AMPLIACAO', 'TECNOLOGIA_ASSISTIVA', 'TEMPO_ESTENDIDO']
               when t0.nec ilike '%auditiva%' then array['LIBRAS', 'ROTINA_VISUAL']
               when t0.nec ilike '%física%' then array['MOBILIARIO_ADAPTADO', 'TECNOLOGIA_ASSISTIVA', 'MEDIADOR']
               when t0.nec ilike '%intelectual%' then array['MATERIAL_CONCRETO', 'TEMPO_ESTENDIDO']
               when t0.nec ilike '%TEA%nível 2%' then array['COMUNICACAO_ALTERNATIVA', 'ROTINA_VISUAL', 'MEDIADOR']
               when t0.nec ilike '%TEA%' then array['ROTINA_VISUAL', 'MATERIAL_CONCRETO']
               when t0.nec ilike '%altas habilidades%' then array['ENRIQUECIMENTO']
               else array['MATERIAL_CONCRETO', 'ROTINA_VISUAL'] end rec,
          case when t0.nec ilike '%visual%' then 'Sentar na primeira fileira, longe da claridade da janela; escrever no quadro com letra grande e contraste; entregar as atividades em fonte 24; ler em voz alta o que estiver no quadro.'
               when t0.nec ilike '%auditiva%' then 'Falar de frente para a turma, sem cobrir a boca; usar imagens e escrever as instruções no quadro; conferir se entendeu a tarefa; posicionar perto do(a) professor(a).'
               when t0.nec ilike '%física%' then 'Manter os corredores livres para a cadeira; mesa na altura adaptada; permitir respostas orais ou com o tablet; planejar a educação física com adaptação.'
               when t0.nec ilike '%intelectual%' then 'Dar uma instrução por vez, com exemplo; usar material concreto em matemática; atividades com menos itens e mais tempo; elogiar cada avanço.'
               when t0.nec ilike '%TEA%' then 'Antecipar a rotina do dia com o quadro de figuras; avisar antes de mudanças; oferecer um canto calmo quando houver barulho; usar frases curtas e diretas.'
               when t0.nec ilike '%altas habilidades%' then 'Oferecer desafios extras e projetos quando terminar antes; evitar repetição de exercícios já dominados; valorizar as perguntas.'
               else 'Rotina estável, comandos curtos com gestos; atividades de recorte, encaixe e pintura para a coordenação.' end ori
        from tmp_aee t0) t
  where t.prof is not null and t.h < 88;  -- os demais ficam sem plano (o painel mostra a pendência); na restauração, também

  -- atendimentos: dos dias de atendimento, do início do plano até ontem (presença ~88%; alguns cancelados)
  insert into iara.aee_atendimentos (plano_id, student_id, data, presenca, atividade, observacao, registrado_por_label, registrado_em, is_demo)
  select pl.id, pl.student_id, d::date,
         case when abs(hashtext(pl.id::text || d::date)) % 100 < 86 then 'PRESENTE' when abs(hashtext(pl.id::text || d::date)) % 100 < 93 then 'FALTA'
              when abs(hashtext(pl.id::text || d::date)) % 100 < 98 then 'FALTA_JUSTIFICADA' else 'CANCELADO' end,
         case when abs(hashtext(pl.id::text || d::date)) % 100 < 86 then
           (case when 'AMPLIACAO' = any (pl.recursos) then array['Leitura com lupa e texto ampliado', 'Jogo de memória com alto contraste', 'Escrita no caderno de pauta ampliada']
                 when 'LIBRAS' = any (pl.recursos) then array['Vocabulário em Libras: família e escola', 'Leitura de imagens e escrita de palavras', 'Jogo de sinais e datilologia']
                 when 'MOBILIARIO_ADAPTADO' = any (pl.recursos) then array['Escrita com engrossador de lápis', 'Atividade no tablet com acionador', 'Jogo de encaixe para preensão']
                 when 'ENRIQUECIMENTO' = any (pl.recursos) then array['Projeto de investigação: o ciclo da água', 'Desafios de lógica e xadrez', 'Robótica com sucata']
                 when 'COMUNICACAO_ALTERNATIVA' = any (pl.recursos) then array['Prancha de comunicação: pedidos e escolhas', 'Rotina visual do dia', 'História com apoio de figuras']
                 else array['Jogo de alfabeto móvel', 'Material dourado: quantidades até 20', 'Sequência lógica com figuras'] end)[1 + abs(hashtext(pl.id::text || d::date || 'a')) % 3] end,
         case when abs(hashtext(pl.id::text || d::date || 'o')) % 9 = 0 then 'Participou bem; avançou em relação à semana anterior.' end,
         'Professor(a) do AEE (demonstração)', d::date + interval '17 hours', true
  from iara.aee_planos pl cross join generate_series(pl.inicio, current_date - 1, interval '1 day') d
  where pl.is_demo and pl.situacao in ('ATIVO', 'EM_REVISAO') and (p_students is null or pl.student_id = any (p_students))
    and (array['DOM', 'SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SAB'])[extract(dow from d)::int + 1] = any (pl.dias)
    and iara.dia_letivo(d::date, pl.unit_id)
  on conflict (plano_id, data) do nothing;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('planos', (select count(*) from iara.aee_planos where is_demo), 'atendimentos', (select count(*) from iara.aee_atendimentos where is_demo));
end $$;

revoke all on function iara.demo_gerar_aee(uuid[]), iara.aee_professor_da_unidade(integer) from public;

-- itinerante acontece na escola do aluno; domiciliar, em casa
update iara.aee_planos set local_unit_id = case modalidade when 'SRM_POLO' then local_unit_id when 'DOMICILIAR' then null else unit_id end
where local_unit_id is distinct from case modalidade when 'SRM_POLO' then local_unit_id when 'DOMICILIAR' then null else unit_id end;

-- 7. Classificação --------------------------------------------------------------------------------------------------------------
insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('aee_planos', 'avaliacao_inicial', 'SENSIVEL', 'saúde/deficiência (art. 11)', 'plano de AEE', 'aee.read; regente não vê'),
  ('aee_planos', 'objetivos', 'SENSIVEL', 'saúde/deficiência (art. 11)', 'plano de AEE', 'aee.read e família'),
  ('aee_planos', 'orientacoes_sala', 'PESSOAL', 'acessibilidade', 'orientar o regente (sem diagnóstico)', 'aee.orientacoes nas próprias turmas'),
  ('aee_planos', 'articulacao_familia', 'PESSOAL', 'acompanhamento', 'plano de AEE', 'aee.read e família'),
  ('aee_planos', 'motivo_encerramento', 'SENSIVEL', 'saúde/deficiência (art. 11)', 'plano de AEE', 'aee.read'),
  ('aee_planos', 'familia_ciente_label', 'PESSOAL', 'identificação', 'ciência da família', null),
  ('aee_planos', 'criado_por_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('aee_atendimentos', 'atividade', 'SENSIVEL', 'saúde/deficiência (art. 11)', 'registro do atendimento', 'aee.read e família'),
  ('aee_atendimentos', 'observacao', 'SENSIVEL', 'saúde/deficiência (art. 11)', 'registro do atendimento', 'aee.read'),
  ('aee_atendimentos', 'registrado_por_label', 'PESSOAL', 'identificação', 'auditoria', null)
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

commit;
