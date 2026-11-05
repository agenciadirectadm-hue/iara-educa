-- IARA Educa — 098.6 · Demonstração coerente: o perfil Professor(a) abre a professora da filha da Maria.
-- Na unidade da família da demonstração (CMEI Galdino de Andrade), o perfil abria o primeiro regente em ordem alfabética, da Creche A,
-- enquanto a Ana Luísa estuda na Pré-escola A: a chamada, a agenda e os recados da conversa com a Maria não apareciam para quem abria.
-- Agora, se a unidade tem uma turma com filho(a) da família da demonstração, abre o(a) regente dessa turma; nas outras, segue a ordem de antes.
-- Só muda quem a sessão de demonstração escolhe: nenhum dado é alterado. Só funciona em modo demonstração, como sempre.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

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
    where c.unit_id = v_unit and c.status = 'ATIVA' and cs.role_type = 'REGENTE' and (cs.end_date is null or cs.end_date >= current_date)
    order by exists (select 1 from iara.enrollments e join iara.student_guardians sg on sg.student_id = e.student_id and sg.end_date is null
                     where e.class_id = c.id and e.status = 'ACTIVE' and sg.guardian_id = (iara.setting('demo_guardian_maria'))::uuid) desc,
             c.class_name, s.full_name limit 1;
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

commit;
