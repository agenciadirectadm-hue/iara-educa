-- IARA Educa — 071 · Ensalamento: salas físicas e turmas por turno (Sprint 5)
-- Cada unidade cadastra as salas (tipo, capacidade, área e acessibilidade) e cada turma ocupa uma sala no seu turno. O sistema aponta
-- sala ocupada duas vezes no mesmo turno, turma maior que a sala, aluno com deficiência física em sala sem acessibilidade e as salas
-- livres por turno — cruzadas com a fila de espera da unidade, para mostrar onde dá para abrir turma. Área de referência proposta:
-- 1,2 m² por aluno no fundamental e 1,5 m² na educação infantil (a validar com a SEDUC).
begin;

insert into iara.permissions (code, description, is_sensitive) values
  ('ensalamento.read', 'Consultar salas, ocupação por turno e salas livres', false),
  ('ensalamento.manage', 'Cadastrar salas e distribuir as turmas nas salas', false)
on conflict (code) do update set description = excluded.description;
insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('DIRETOR_UNIDADE', 'ensalamento.read'), ('DIRETOR_UNIDADE', 'ensalamento.manage'), ('SECRETARIA_ESCOLAR', 'ensalamento.read'), ('SECRETARIA_ESCOLAR', 'ensalamento.manage'),
  ('SECRETARIO', 'ensalamento.read'), ('SUPERINTENDENCIA', 'ensalamento.read'), ('GERENCIA_EI', 'ensalamento.read'), ('ANALISTA_CENTRAL', 'ensalamento.read')
) v(r, p)
on conflict do nothing;

create table if not exists iara.salas (
  id uuid primary key default gen_random_uuid(),
  unit_id integer not null references iara.education_units(id),
  nome text not null,
  tipo text not null default 'SALA_AULA' check (tipo in ('SALA_AULA', 'LABORATORIO', 'BIBLIOTECA', 'SALA_RECURSOS', 'BRINQUEDOTECA', 'QUADRA', 'REFEITORIO', 'OUTRO')),
  capacidade integer not null check (capacidade between 1 and 200),
  area_m2 numeric(6, 1),
  acessivel boolean not null default true,
  andar text,
  observacao text,
  ativa boolean not null default true,
  criado_em timestamptz not null default now(),
  alterado_em timestamptz,
  is_demo boolean not null default false,
  unique (unit_id, nome)
);
alter table iara.salas enable row level security;
alter table iara.classes add column if not exists sala_id uuid references iara.salas(id) on delete set null;
alter table iara.classes add column if not exists sala_demo_id uuid;   -- sala original da demonstração (a limpeza devolve)

create or replace function iara.turnos_conflitam(a text, b text) returns boolean
language sql immutable as $$ select a = b or a = 'INTEGRAL' and b in ('MANHA', 'TARDE') or b = 'INTEGRAL' and a in ('MANHA', 'TARDE') $$;

create or replace function iara.m2_por_aluno(p_grade text) returns numeric
language sql immutable as $$ select case when p_grade in ('CRECHE', 'PRE') then 1.5 else 1.2 end $$;

-- turma com aluno com deficiência física (para conferir a acessibilidade da sala)
create or replace function iara.turma_precisa_acessibilidade(p_class uuid) returns boolean
language sql stable security definer set search_path = iara, public
as $$ select exists (select 1 from iara.enrollments e join iara.student_sensitive ss on ss.student_id = e.student_id
                     where e.class_id = p_class and e.status = 'ACTIVE' and ss.special_education_need ilike '%física%') $$;

create or replace function api.ensalamento(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
begin
  perform iara.require_perm('ensalamento.read');
  if v_unit is null then
    -- rede: salas de aula livres por turno × fila de espera da unidade
    return jsonb_build_object('unit_id', null, 'unidades', (select coalesce(jsonb_agg(z order by (z ->> 'oportunidade')::boolean desc, (z ->> 'fila')::int desc), '[]') from (
      select jsonb_build_object('unit_id', u.id, 'unidade', u.short_name, 'salas', count(s.id),
        'livres_manha', count(s.id) filter (where not exists (select 1 from iara.classes c where c.sala_id = s.id and c.status = 'ATIVA' and iara.turnos_conflitam(c.shift, 'MANHA'))),
        'livres_tarde', count(s.id) filter (where not exists (select 1 from iara.classes c where c.sala_id = s.id and c.status = 'ATIVA' and iara.turnos_conflitam(c.shift, 'TARDE'))),
        'fila', (select count(*) from iara.waiting_list_entries w where w.preferred_unit_id = u.id and w.status = 'WAITING'),
        'acima', (select count(*) from iara.classes c join iara.salas s2 on s2.id = c.sala_id where c.unit_id = u.id and c.status = 'ATIVA' and c.active_enrollments_count > s2.capacidade),
        'oportunidade', (count(s.id) filter (where not exists (select 1 from iara.classes c where c.sala_id = s.id and c.status = 'ATIVA' and iara.turnos_conflitam(c.shift, 'MANHA')))
                         + count(s.id) filter (where not exists (select 1 from iara.classes c where c.sala_id = s.id and c.status = 'ATIVA' and iara.turnos_conflitam(c.shift, 'TARDE')))) > 0
                        and (select count(*) from iara.waiting_list_entries w where w.preferred_unit_id = u.id and w.status = 'WAITING') >= 10) z
      from iara.education_units u left join iara.salas s on s.unit_id = u.id and s.ativa and s.tipo = 'SALA_AULA'
      where u.status = 'ATIVA' and iara.can_access_unit(u.id) group by u.id, u.short_name) q(z)));
  end if;
  if not iara.can_access_unit(v_unit) then raise exception 'Unidade fora do seu escopo.' using errcode = '42501'; end if;
  return jsonb_build_object('unit_id', v_unit, 'unidade', (select short_name from iara.education_units where id = v_unit),
    'pode_editar', iara.has_perm('ensalamento.manage') and iara.my_scope() = 'UNIT',
    'salas', (select coalesce(jsonb_agg(to_jsonb(s) || jsonb_build_object(
                 'ocupacao', (select coalesce(jsonb_agg(jsonb_build_object('class_id', c.id, 'turma', c.class_name, 'turno', c.shift, 'alunos', c.active_enrollments_count,
                                 'capacidade_turma', c.authorized_capacity, 'acima', c.active_enrollments_count > s.capacidade,
                                 'acessibilidade', iara.turma_precisa_acessibilidade(c.id) and not s.acessivel) order by c.shift), '[]')
                              from iara.classes c where c.sala_id = s.id and c.status = 'ATIVA'),
                 'livre_manha', not exists (select 1 from iara.classes c where c.sala_id = s.id and c.status = 'ATIVA' and iara.turnos_conflitam(c.shift, 'MANHA')),
                 'livre_tarde', not exists (select 1 from iara.classes c where c.sala_id = s.id and c.status = 'ATIVA' and iara.turnos_conflitam(c.shift, 'TARDE')),
                 'capacidade_area', case when s.area_m2 is not null then floor(s.area_m2 / 1.2) end) order by s.tipo <> 'SALA_AULA', s.nome), '[]')
              from iara.salas s where s.unit_id = v_unit and (s.ativa or coalesce((p ->> 'inativas')::boolean, false))),
    'sem_sala', (select coalesce(jsonb_agg(jsonb_build_object('class_id', c.id, 'turma', c.class_name, 'turno', c.shift, 'alunos', c.active_enrollments_count) order by c.class_name), '[]')
                 from iara.classes c where c.unit_id = v_unit and c.status = 'ATIVA' and c.sala_id is null),
    'conflitos', (select coalesce(jsonb_agg(jsonb_build_object('sala', s.nome, 'turmas', z.turmas) order by s.nome), '[]') from (
                   select c1.sala_id, jsonb_agg(distinct c1.class_name) turmas from iara.classes c1 join iara.classes c2 on c2.sala_id = c1.sala_id and c2.id <> c1.id
                   and c2.status = 'ATIVA' and iara.turnos_conflitam(c1.shift, c2.shift) where c1.unit_id = v_unit and c1.status = 'ATIVA' group by 1) z join iara.salas s on s.id = z.sala_id),
    'fila', (select count(*) from iara.waiting_list_entries w where w.preferred_unit_id = v_unit and w.status = 'WAITING'),
    'referencia', 'Proposta a validar: 1,2 m² por aluno no fundamental e 1,5 m² na educação infantil.');
end $$;

create or replace function api.sala_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_unit integer := iara.my_unit();
  s iara.salas;
begin
  perform iara.require_perm('ensalamento.manage');
  if iara.my_scope() <> 'UNIT' then raise exception 'As salas são cadastradas pela unidade.' using errcode = '42501'; end if;
  if coalesce((p ->> 'excluir')::boolean, false) then
    select * into s from iara.salas where id = (p ->> 'id')::uuid and unit_id = v_unit;
    if s.id is null then raise exception 'Sala não encontrada.' using errcode = 'P0002'; end if;
    if exists (select 1 from iara.classes where sala_id = s.id and status = 'ATIVA') then raise exception 'Há turma nesta sala: mude a turma de sala antes.' using errcode = '22023'; end if;
    update iara.salas set ativa = false, alterado_em = now() where id = s.id;
    return jsonb_build_object('ok', true);
  end if;
  if length(btrim(coalesce(p ->> 'nome', ''))) < 2 then raise exception 'Dê um nome à sala (ex.: Sala 07).' using errcode = '22023'; end if;
  if coalesce((p ->> 'capacidade')::int, 0) not between 1 and 200 then raise exception 'Capacidade de 1 a 200 pessoas.' using errcode = '22023'; end if;
  if nullif(p ->> 'id', '') is null then
    insert into iara.salas (unit_id, nome, tipo, capacidade, area_m2, acessivel, andar, observacao)
    values (v_unit, btrim(p ->> 'nome'), coalesce(nullif(p ->> 'tipo', ''), 'SALA_AULA'), (p ->> 'capacidade')::int, nullif(p ->> 'area_m2', '')::numeric,
            coalesce((p ->> 'acessivel')::boolean, true), nullif(btrim(coalesce(p ->> 'andar', '')), ''), nullif(btrim(coalesce(p ->> 'observacao', '')), ''))
    returning * into s;
  else
    update iara.salas set nome = btrim(p ->> 'nome'), tipo = coalesce(nullif(p ->> 'tipo', ''), tipo), capacidade = (p ->> 'capacidade')::int,
           area_m2 = nullif(p ->> 'area_m2', '')::numeric, acessivel = coalesce((p ->> 'acessivel')::boolean, acessivel),
           andar = nullif(btrim(coalesce(p ->> 'andar', '')), ''), observacao = nullif(btrim(coalesce(p ->> 'observacao', '')), ''), ativa = true, alterado_em = now()
    where id = (p ->> 'id')::uuid and unit_id = v_unit returning * into s;
    if s.id is null then raise exception 'Sala não encontrada.' using errcode = 'P0002'; end if;
  end if;
  return to_jsonb(s);
exception when unique_violation then
  raise exception 'Já existe uma sala com este nome na unidade.' using errcode = '22023';
end $$;

-- turma na sala: sem choque de turno, sem turma maior que a sala e com acessibilidade quando a turma precisa
create or replace function api.turma_sala(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.classes;
  s iara.salas;
  v_outra text;
begin
  perform iara.require_perm('ensalamento.manage');
  select * into c from iara.classes where id = (p ->> 'class_id')::uuid and unit_id = iara.my_unit() and status = 'ATIVA' for update;
  if c.id is null then raise exception 'Turma não encontrada na unidade.' using errcode = 'P0002'; end if;
  if nullif(p ->> 'sala_id', '') is null then
    update iara.classes set sala_id = null, room_label = null where id = c.id;
    return api.ensalamento('{}'::jsonb);
  end if;
  select * into s from iara.salas where id = (p ->> 'sala_id')::uuid and unit_id = c.unit_id and ativa;
  if s.id is null then raise exception 'Sala não encontrada.' using errcode = 'P0002'; end if;
  if s.tipo not in ('SALA_AULA', 'BRINQUEDOTECA', 'SALA_RECURSOS') then raise exception 'Este espaço não é sala de aula.' using errcode = '22023'; end if;
  select string_agg(x.class_name, ', ') into v_outra from iara.classes x where x.sala_id = s.id and x.id <> c.id and x.status = 'ATIVA' and iara.turnos_conflitam(x.shift, c.shift);
  if v_outra is not null then raise exception 'A sala já está ocupada neste turno (%).', v_outra using errcode = '22023'; end if;
  if c.active_enrollments_count > s.capacidade then raise exception 'A turma tem % alunos e a sala comporta %.', c.active_enrollments_count, s.capacidade using errcode = '22023'; end if;
  if iara.turma_precisa_acessibilidade(c.id) and not s.acessivel then
    raise exception 'A turma tem aluno com deficiência física: escolha uma sala acessível.' using errcode = '22023';
  end if;
  update iara.classes set sala_id = s.id, room_label = s.nome where id = c.id;
  perform iara.audit_event('ENSALAMENTO', 'class', c.id::text, c.unit_id, format('Turma %s na %s.', c.class_name, s.nome));
  return api.ensalamento('{}'::jsonb);
end $$;

-- demonstração: as salas vêm dos rótulos das turmas; capacidade e área plausíveis; alguns espaços de apoio
create or replace function iara.demo_gerar_salas() returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  update iara.classes set sala_id = null where sala_id in (select id from iara.salas where is_demo);
  update iara.classes c set room_label = (select nome from iara.salas s where s.id = c.sala_demo_id) where c.sala_demo_id is not null and c.room_label is null;
  delete from iara.salas where is_demo;
  insert into iara.salas (unit_id, nome, tipo, capacidade, area_m2, acessivel, andar, is_demo)
  select z.unit_id, z.room_label, 'SALA_AULA', z.cap + case when abs(hashtext(z.unit_id || z.room_label || 'menor')) % 100 < 5 then -4 else abs(hashtext(z.unit_id || z.room_label)) % 5 end,
         round(((z.cap + abs(hashtext(z.unit_id || z.room_label)) % 5) * case when z.ei then 1.5 else 1.25 end + abs(hashtext(z.room_label || z.unit_id)) % 6)::numeric, 1),
         abs(hashtext(z.unit_id || z.room_label || 'ac')) % 100 < 78, case when abs(hashtext(z.unit_id || z.room_label)) % 100 < 20 then '1º andar' else 'Térreo' end, true
  from (select c.unit_id, c.room_label, max(c.authorized_capacity) cap, bool_or(g.code in ('CRECHE', 'PRE')) ei
        from iara.classes c join iara.grade_levels g on g.id = c.grade_level_id where c.status = 'ATIVA' and c.room_label is not null group by 1, 2) z;
  insert into iara.salas (unit_id, nome, tipo, capacidade, area_m2, acessivel, is_demo)
  select u.id, e.nome, e.tipo, e.cap, e.cap * 1.6, true, true
  from iara.education_units u cross join (values ('Biblioteca', 'BIBLIOTECA', 30), ('Sala de recursos multifuncionais', 'SALA_RECURSOS', 10), ('Refeitório', 'REFEITORIO', 120),
                                                 ('Quadra', 'QUADRA', 60), ('Brinquedoteca', 'BRINQUEDOTECA', 20), ('Sala 09', 'SALA_AULA', 30)) e(nome, tipo, cap)
  where u.status = 'ATIVA' and ((e.tipo = 'SALA_RECURSOS' and u.has_aee) or (e.tipo = 'BRINQUEDOTECA' and u.unit_type = 'CMEI') or (e.tipo = 'QUADRA' and u.unit_type <> 'CMEI')
                                or e.tipo in ('BIBLIOTECA', 'REFEITORIO') or (e.nome = 'Sala 09' and abs(hashtext(u.id::text || 's9')) % 100 < 30))
  on conflict (unit_id, nome) do nothing;
  update iara.classes c set sala_id = s.id, sala_demo_id = s.id from iara.salas s where s.unit_id = c.unit_id and s.nome = c.room_label and c.status = 'ATIVA';
  get diagnostics n = row_count;
  perform set_config('iara.skip_audit', 'off', true);
  return n;
end $$;

create or replace function iara.demo_purge_salas(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  d timestamptz := coalesce(p_desde, '-infinity'::timestamptz);
  n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  update iara.classes set sala_id = null where sala_id in (select id from iara.salas where not is_demo and criado_em >= d);
  delete from iara.salas where not is_demo and criado_em >= d; get diagnostics n = row_count;
  if exists (select 1 from iara.salas where is_demo and alterado_em >= d) or exists (select 1 from iara.classes where sala_demo_id is not null and sala_id is distinct from sala_demo_id) then
    perform iara.demo_gerar_salas();
  end if;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('salas', n);
end $$;

revoke all on function iara.demo_gerar_salas(), iara.demo_purge_salas(timestamptz) from public;

select iara.demo_gerar_salas() where iara.demo_mode();

commit;
