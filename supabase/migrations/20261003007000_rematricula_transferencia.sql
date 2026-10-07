-- IARA Educa — 070 · Rematrícula do ano seguinte e transferência entre unidades da rede (Sprint 5)
-- Rematrícula: a SEDUC gera a previsão de 2027 para cada aluno — continuidade na mesma unidade, transição (do CMEI para a escola de
-- 1º ano mais próxima) ou conclusão do 5º ano (encaminhado ao 6º ano na rede estadual) —, com a série pela data de corte de 31 de março
-- (Res. CNE/CEB nº 2/2018) e o resultado do ano (quem vai ao conselho fica “aguardando o resultado”). A família confirma, troca o turno,
-- avisa que não renova ou pede outra escola (portal e IARA); a escola confirma no balcão. Projeção de vagas de 2027 por unidade, série e
-- turno: o que sobra vai para a fila on-line; o que falta pede turma nova ou remanejamento.
-- Transferência entre unidades: a família ou a escola pede; se a unidade de destino tem vaga na série e no turno e NINGUÉM espera na fila
-- dela para a série, o destino aceita e a matrícula muda na hora; senão, a orientação é a fila de transferência (IN nº 025/2025).
begin;

insert into iara.permissions (code, description, is_sensitive) values
  ('rematricula.read', 'Consultar a rematrícula e a projeção de vagas do ano seguinte', false),
  ('rematricula.unidade', 'Confirmar a rematrícula no balcão da unidade', false),
  ('rematricula.manage', 'Gerar a rematrícula da rede e acompanhar a projeção de vagas', false),
  ('transferencia.write', 'Pedir e responder transferências entre unidades da rede', false)
on conflict (code) do update set description = excluded.description;
insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('DIRETOR_UNIDADE', 'rematricula.read'), ('DIRETOR_UNIDADE', 'rematricula.unidade'), ('SECRETARIA_ESCOLAR', 'rematricula.read'), ('SECRETARIA_ESCOLAR', 'rematricula.unidade'),
  ('SECRETARIO', 'rematricula.read'), ('SECRETARIO', 'rematricula.manage'), ('SUPERINTENDENCIA', 'rematricula.read'), ('SUPERINTENDENCIA', 'rematricula.manage'),
  ('ANALISTA_CENTRAL', 'rematricula.read'), ('ANALISTA_CENTRAL', 'rematricula.manage'), ('GERENCIA_EI', 'rematricula.read'), ('ATENDIMENTO', 'rematricula.read'),
  ('DIRETOR_UNIDADE', 'transferencia.write'), ('SECRETARIA_ESCOLAR', 'transferencia.write'), ('ANALISTA_CENTRAL', 'transferencia.write')
) v(r, p)
on conflict do nothing;

-- 1. Rematrícula ---------------------------------------------------------------------------------------------------------------------
create table if not exists iara.rematriculas (
  id uuid primary key default gen_random_uuid(),
  ano smallint not null,
  student_id uuid not null references iara.students(id) on delete cascade,
  unit_origem integer,
  class_origem uuid,
  grade_origem text,
  grade_destino text,
  unit_destino integer,
  turno_destino text,
  tipo text not null check (tipo in ('CONTINUIDADE', 'TRANSICAO', 'CONCLUSAO')),
  situacao text not null default 'PENDENTE' check (situacao in ('PENDENTE', 'AGUARDANDO_RESULTADO', 'CONFIRMADA', 'NAO_RENOVADA', 'OUTRA_ESCOLA', 'CONCLUINTE')),
  distancia_m integer,
  motivo text,
  confirmada_em timestamptz,
  confirmada_por text,
  canal text,
  gerada_em timestamptz not null default now(),
  is_demo boolean not null default false,
  unique (ano, student_id)
);
create index if not exists rematriculas_destino_idx on iara.rematriculas (ano, unit_destino, grade_destino);
create index if not exists rematriculas_origem_idx on iara.rematriculas (ano, unit_origem);
alter table iara.rematriculas enable row level security;

create or replace function iara.proxima_serie(p_grade text, p_nascimento date, p_ano integer) returns text
language sql immutable as $$
  -- data de corte: idade completa até 31 de março do ano da matrícula (Res. CNE/CEB nº 2/2018)
  select case p_grade
    when 'CRECHE' then case when age(make_date(p_ano, 3, 31), p_nascimento) >= interval '4 years' then 'PRE' else 'CRECHE' end
    when 'PRE' then case when age(make_date(p_ano, 3, 31), p_nascimento) >= interval '6 years' then 'EF1' else 'PRE' end
    when 'EF1' then 'EF2' when 'EF2' then 'EF3' when 'EF3' then 'EF4' when 'EF4' then 'EF5' when 'EF5' then 'EF6_ESTADUAL'
    else p_grade end
$$;

-- gera (ou refaz as não confirmadas) a rematrícula do ano seguinte para todos os alunos ativos
create or replace function iara.rematricula_gerar(p_ano integer default null) returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ano integer := coalesce(p_ano, extract(year from iara.hoje_local())::int + 1);
  n integer;
begin
  delete from iara.rematriculas where ano = v_ano and situacao in ('PENDENTE', 'AGUARDANDO_RESULTADO', 'CONCLUINTE');
  insert into iara.rematriculas (ano, student_id, unit_origem, class_origem, grade_origem, grade_destino, unit_destino, turno_destino, tipo, situacao, distancia_m, is_demo)
  select v_ano, z.student_id, z.unit_id, z.class_id, z.grade, z.destino,
         case when z.destino = 'EF6_ESTADUAL' then null when z.mesma then z.unit_id else z.perto end,
         case when z.destino = 'EF6_ESTADUAL' then null
              else coalesce((select c2.shift from iara.classes c2 join iara.grade_levels g2 on g2.id = c2.grade_level_id
                             where c2.unit_id = case when z.mesma then z.unit_id else z.perto end and g2.code = z.destino and c2.status = 'ATIVA'
                             order by (c2.shift = z.shift) desc limit 1), z.shift) end,
         case when z.destino = 'EF6_ESTADUAL' then 'CONCLUSAO' when z.mesma then 'CONTINUIDADE' else 'TRANSICAO' end,
         case when z.destino = 'EF6_ESTADUAL' then 'CONCLUINTE'
              when z.grade like 'EF%' and (iara.situacao_calculada(z.student_id, 2026::smallint) ->> 'situacao') = 'CONSELHO' then 'AGUARDANDO_RESULTADO'
              else 'PENDENTE' end,
         case when not z.mesma and z.perto is not null then round(iara.km_entre(z.lat, z.lng, (select lat from iara.education_units where id = z.perto), (select lng from iara.education_units where id = z.perto)) * 1000) end,
         z.is_demo
  from (select e.student_id, e.unit_id, e.class_id, gl.code grade, c.shift, iara.proxima_serie(gl.code, s.birth_date, v_ano) destino, s.is_demo,
               extensions.st_y(a.location::extensions.geometry) lat, extensions.st_x(a.location::extensions.geometry) lng,
               exists (select 1 from iara.classes c2 join iara.grade_levels g2 on g2.id = c2.grade_level_id where c2.unit_id = e.unit_id and c2.status = 'ATIVA'
                       and g2.code = iara.proxima_serie(gl.code, s.birth_date, v_ano)) mesma,
               (select u.id from iara.education_units u where u.status = 'ATIVA'
                  and exists (select 1 from iara.classes c3 join iara.grade_levels g3 on g3.id = c3.grade_level_id where c3.unit_id = u.id and c3.status = 'ATIVA'
                              and g3.code = iara.proxima_serie(gl.code, s.birth_date, v_ano))
                order by iara.km_entre(coalesce(extensions.st_y(a.location::extensions.geometry), uo.lat), coalesce(extensions.st_x(a.location::extensions.geometry), uo.lng), u.lat, u.lng) limit 1) perto
        from iara.enrollments e join iara.students s on s.id = e.student_id join iara.classes c on c.id = e.class_id
        join iara.grade_levels gl on gl.id = c.grade_level_id join iara.education_units uo on uo.id = e.unit_id
        left join iara.addresses a on a.id = s.address_id
        where e.status = 'ACTIVE' and gl.code not like 'EJA%'
          and not exists (select 1 from iara.rematriculas r where r.ano = v_ano and r.student_id = e.student_id)) z
  on conflict (ano, student_id) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function iara.rematricula_json(r iara.rematriculas) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select to_jsonb(r) - 'class_origem' || jsonb_build_object('aluno', s.full_name, 'primeiro_nome', split_part(s.full_name, ' ', 1),
    'serie_origem', (select name from iara.grade_levels where code = r.grade_origem), 'turma_origem', (select class_name from iara.classes where id = r.class_origem),
    'serie_destino', case when r.grade_destino = 'EF6_ESTADUAL' then '6º ano (rede estadual)' else (select name from iara.grade_levels where code = r.grade_destino) end,
    'unidade_origem', (select short_name from iara.education_units where id = r.unit_origem), 'unidade_destino', (select short_name from iara.education_units where id = r.unit_destino),
    'turnos_destino', (select coalesce(jsonb_agg(distinct c.shift), '[]') from iara.classes c join iara.grade_levels g on g.id = c.grade_level_id
                       where c.unit_id = r.unit_destino and g.code = r.grade_destino and c.status = 'ATIVA'),
    'prazo', coalesce(nullif(iara.setting('rematricula_prazo'), ''), '2026-11-27'))
  from iara.students s where s.id = r.student_id
$$;

create or replace function api.rematricula_painel(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_ano integer := coalesce(nullif(p ->> 'ano', '')::int, extract(year from iara.hoje_local())::int + 1);
  v_q text := nullif(iara.norm(btrim(coalesce(p ->> 'busca', ''))), '');
begin
  perform iara.require_perm('rematricula.read');
  if v_unit is not null and not iara.can_access_unit(v_unit) then raise exception 'Unidade fora do seu escopo.' using errcode = '42501'; end if;
  return (with base as (select * from iara.rematriculas r where r.ano = v_ano and (v_unit is null or r.unit_origem = v_unit or r.unit_destino = v_unit)),
               cap as (select c.unit_id, g.code grade, c.shift, sum(c.authorized_capacity) capacidade from iara.classes c join iara.grade_levels g on g.id = c.grade_level_id
                       where c.status = 'ATIVA' and (v_unit is null or c.unit_id = v_unit) group by 1, 2, 3),
               dem as (select unit_destino unit_id, grade_destino grade, turno_destino shift, count(*) n from base
                       where situacao in ('PENDENTE', 'AGUARDANDO_RESULTADO', 'CONFIRMADA') and unit_destino is not null and (v_unit is null or unit_destino = v_unit) group by 1, 2, 3)
    select jsonb_build_object('ano', v_ano, 'unit_id', v_unit, 'prazo', coalesce(nullif(iara.setting('rematricula_prazo'), ''), '2026-11-27'),
      'pode_gerar', iara.has_perm('rematricula.manage'), 'pode_confirmar', iara.has_perm('rematricula.unidade') and v_unit is not null,
      'resumo', (select jsonb_build_object('total', count(*) filter (where v_unit is null or unit_origem = v_unit),
                   'confirmadas', count(*) filter (where situacao = 'CONFIRMADA' and (v_unit is null or unit_origem = v_unit)),
                   'pendentes', count(*) filter (where situacao = 'PENDENTE' and (v_unit is null or unit_origem = v_unit)),
                   'aguardando_resultado', count(*) filter (where situacao = 'AGUARDANDO_RESULTADO' and (v_unit is null or unit_origem = v_unit)),
                   'nao_renovadas', count(*) filter (where situacao = 'NAO_RENOVADA' and (v_unit is null or unit_origem = v_unit)),
                   'outra_escola', count(*) filter (where situacao = 'OUTRA_ESCOLA' and (v_unit is null or unit_origem = v_unit)),
                   'concluintes', count(*) filter (where situacao = 'CONCLUINTE' and (v_unit is null or unit_origem = v_unit)),
                   'transicao', count(*) filter (where tipo = 'TRANSICAO' and (v_unit is null or unit_origem = v_unit)),
                   'chegam', count(*) filter (where v_unit is not null and unit_destino = v_unit and unit_origem <> v_unit)) from base),
      'projecao', (select coalesce(jsonb_agg(jsonb_build_object('unit_id', cap.unit_id, 'unidade', u.short_name, 'grade', cap.grade, 'serie', g.name, 'turno', cap.shift,
                      'capacidade', cap.capacidade, 'previstos', coalesce(dem.n, 0), 'saldo', cap.capacidade - coalesce(dem.n, 0),
                      'fila', (select count(*) from iara.waiting_list_entries w where w.preferred_unit_id = cap.unit_id and w.grade_level_id = g.id and w.status = 'WAITING'))
                    order by (cap.capacidade - coalesce(dem.n, 0)), u.short_name, g.code), '[]')
                   from cap left join dem on dem.unit_id = cap.unit_id and dem.grade = cap.grade and dem.shift = cap.shift
                   join iara.education_units u on u.id = cap.unit_id join iara.grade_levels g on g.code = cap.grade
                   where v_unit is not null or cap.capacidade - coalesce(dem.n, 0) < 0),
      'itens', case when v_unit is not null then (select coalesce(jsonb_agg(iara.rematricula_json(b) order by b.situacao <> 'PENDENTE', s.full_name), '[]') from (
                   select b2.* from base b2 join iara.students s2 on s2.id = b2.student_id
                   where b2.unit_origem = v_unit and (nullif(p ->> 'situacao', '') is null or b2.situacao = p ->> 'situacao')
                     and (v_q is null or iara.norm(s2.full_name) like '%' || v_q || '%') order by s2.full_name limit 400) b join iara.students s on s.id = b.student_id) end,
      'unidades', case when v_unit is null then (select coalesce(jsonb_agg(jsonb_build_object('unit_id', u.id, 'unidade', u.short_name, 'total', z.n, 'confirmadas', z.conf,
                       'pct', round(100.0 * z.conf / nullif(z.n - z.conc, 0))) order by round(100.0 * z.conf / nullif(z.n - z.conc, 0)) nulls first), '[]')
                   from (select unit_origem, count(*) n, count(*) filter (where situacao = 'CONFIRMADA') conf, count(*) filter (where situacao = 'CONCLUINTE') conc from base group by 1) z
                   join iara.education_units u on u.id = z.unit_origem) end));
end $$;

create or replace function api.rematricula_gerar(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  n integer;
begin
  perform iara.require_perm('rematricula.manage');
  if nullif(p ->> 'prazo', '') is not null then
    update iara.tenants set settings = settings || jsonb_build_object('rematricula_prazo', (p ->> 'prazo')::date::text) where id = 1;
  end if;
  n := iara.rematricula_gerar(nullif(p ->> 'ano', '')::int);
  perform iara.audit_event('REMATRICULA', 'rematriculas', coalesce(p ->> 'ano', 'proximo'), null, format('Rematrícula gerada: %s aluno(s) sem resposta atualizados.', n));
  return jsonb_build_object('gerados', n);
end $$;

-- resposta: família (portal/IARA) ou escola no balcão
create or replace function api.rematricula_responder(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r iara.rematriculas;
  v_fam boolean := iara.my_guardian() is not null;
  v_acao text := upper(coalesce(p ->> 'acao', ''));
begin
  select * into r from iara.rematriculas where id = (p ->> 'id')::uuid for update;
  if r.id is null or not ((v_fam and r.student_id in (select iara.my_student_ids()))
                          or (not v_fam and iara.has_perm('rematricula.unidade') and iara.my_scope() = 'UNIT' and r.unit_origem = iara.my_unit())) then
    raise exception 'Rematrícula não encontrada.' using errcode = 'P0002';
  end if;
  if r.situacao = 'CONCLUINTE' then raise exception 'Concluinte do 5º ano: a matrícula do 6º ano é feita na rede estadual.' using errcode = '22023'; end if;
  if v_acao = 'CONFIRMAR' then
    if r.situacao = 'AGUARDANDO_RESULTADO' and not v_fam then null; end if;
    if nullif(p ->> 'turno', '') is not null then
      if not exists (select 1 from iara.classes c join iara.grade_levels g on g.id = c.grade_level_id where c.unit_id = r.unit_destino and g.code = r.grade_destino
                     and c.status = 'ATIVA' and c.shift = p ->> 'turno') then
        raise exception 'A unidade não oferece este turno para a série.' using errcode = '22023';
      end if;
    end if;
    update iara.rematriculas set situacao = case when situacao = 'AGUARDANDO_RESULTADO' then situacao else 'CONFIRMADA' end,
           turno_destino = coalesce(nullif(p ->> 'turno', ''), turno_destino), confirmada_em = now(), confirmada_por = iara.my_label(),
           canal = case when v_fam then coalesce(nullif(upper(p ->> 'canal'), ''), 'PORTAL') else 'UNIDADE' end, motivo = null
    where id = r.id returning * into r;
  elsif v_acao in ('NAO_RENOVAR', 'OUTRA_ESCOLA') then
    if length(btrim(coalesce(p ->> 'motivo', ''))) < 5 then raise exception 'Conte o motivo (ex.: mudança de cidade, rede particular).' using errcode = '22023'; end if;
    update iara.rematriculas set situacao = case when v_acao = 'NAO_RENOVAR' then 'NAO_RENOVADA' else 'OUTRA_ESCOLA' end, motivo = btrim(p ->> 'motivo'),
           confirmada_em = now(), confirmada_por = iara.my_label(), canal = case when v_fam then coalesce(nullif(upper(p ->> 'canal'), ''), 'PORTAL') else 'UNIDADE' end
    where id = r.id returning * into r;
  else
    raise exception 'Ação inválida.' using errcode = '22023';
  end if;
  perform iara.audit_event('REMATRICULA', 'student', r.student_id::text, r.unit_origem, format('Rematrícula %s: %s (%s).', r.ano, lower(r.situacao), case when v_fam then 'família' else 'escola' end));
  return iara.rematricula_json(r) || jsonb_build_object('mensagem', case
    when r.situacao = 'CONFIRMADA' then format('Rematrícula confirmada: %s em %s, turno %s.', (iara.rematricula_json(r) ->> 'serie_destino'), (iara.rematricula_json(r) ->> 'unidade_destino'), lower(r.turno_destino))
    when r.situacao = 'AGUARDANDO_RESULTADO' then 'Recebido. A série de 2027 sai depois do conselho de classe final; a escola confirma com você.'
    when r.situacao = 'OUTRA_ESCOLA' then 'Registrado. Para outra escola da rede, faça o pedido de transferência (Vagas › transferência) ou fale com a IARA.'
    else 'Registrado: a vaga fica livre para a fila de espera de 2027.' end);
end $$;

create or replace function api.familia_rematricula(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(iara.rematricula_json(r) order by s.full_name), '[]')
          from iara.rematriculas r join iara.students s on s.id = r.student_id
          where r.student_id in (select iara.my_student_ids()) and r.ano = extract(year from iara.hoje_local())::int + 1);
end $$;

-- 2. Transferência entre unidades da rede -----------------------------------------------------------------------------------------
create table if not exists iara.transferencias (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references iara.students(id) on delete cascade,
  unit_origem integer not null,
  class_origem uuid,
  unit_destino integer not null,
  grade_code text not null,
  turno text not null,
  motivo_tipo text not null check (motivo_tipo in ('MUDANCA_ENDERECO', 'PERTO_DO_TRABALHO', 'IRMAOS', 'SAUDE', 'OUTRO')),
  motivo text,
  solicitante text not null check (solicitante in ('FAMILIA', 'ESCOLA', 'SEDUC')),
  solicitada_por_label text,
  situacao text not null check (situacao in ('AGUARDANDO_DESTINO', 'EFETIVADA', 'RECUSADA', 'FILA', 'CANCELADA')),
  vagas_no_pedido integer,
  fila_no_pedido integer,
  pendencias jsonb not null default '[]',
  class_destino uuid,
  resposta text,
  respondida_por_label text,
  criada_em timestamptz not null default now(),
  respondida_em timestamptz,
  enrollment_destino uuid,
  is_demo boolean not null default false
);
create unique index if not exists transferencia_aberta on iara.transferencias (student_id) where situacao = 'AGUARDANDO_DESTINO';
alter table iara.transferencias enable row level security;

create or replace function iara.transferencia_json(t iara.transferencias) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select to_jsonb(t) || jsonb_build_object('aluno', s.full_name, 'primeiro_nome', split_part(s.full_name, ' ', 1),
    'unidade_origem', (select short_name from iara.education_units where id = t.unit_origem), 'unidade_destino', (select short_name from iara.education_units where id = t.unit_destino),
    'serie', (select name from iara.grade_levels where code = t.grade_code), 'turma_destino', (select class_name from iara.classes where id = t.class_destino),
    'turmas_com_vaga', (select coalesce(jsonb_agg(jsonb_build_object('class_id', c.id, 'turma', c.class_name, 'vagas', c.offerable_vacancies_count) order by c.class_name), '[]')
                        from iara.classes c join iara.grade_levels g on g.id = c.grade_level_id
                        where c.unit_id = t.unit_destino and g.code = t.grade_code and c.shift = t.turno and c.status = 'ATIVA' and c.offerable_vacancies_count > 0))
  from iara.students s where s.id = t.student_id
$$;

create or replace function api.transferencia_solicitar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_fam boolean := iara.my_guardian() is not null;
  v_dest integer := (p ->> 'unit_destino')::int;
  e record;
  v_turno text;
  v_vagas integer;
  v_fila integer;
  v_pend jsonb := '[]';
  t iara.transferencias;
begin
  select en.unit_id, en.class_id, gl.code grade, c.shift, gl.id grade_id into e from iara.enrollments en join iara.classes c on c.id = en.class_id
  join iara.grade_levels gl on gl.id = c.grade_level_id where en.student_id = v_student and en.status = 'ACTIVE' limit 1;
  if e.unit_id is null then raise exception 'A criança não tem matrícula ativa na rede.' using errcode = '22023'; end if;
  if not ((v_fam and v_student in (select iara.my_student_ids()))
          or (not v_fam and iara.has_perm('transferencia.write') and (iara.my_scope() <> 'UNIT' or e.unit_id = iara.my_unit()))) then
    raise exception 'Aluno fora do seu acesso.' using errcode = '42501';
  end if;
  if v_dest = e.unit_id then raise exception 'A unidade de destino é a mesma da matrícula atual.' using errcode = '22023'; end if;
  if coalesce(p ->> 'motivo_tipo', '') not in ('MUDANCA_ENDERECO', 'PERTO_DO_TRABALHO', 'IRMAOS', 'SAUDE', 'OUTRO') then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
  v_turno := coalesce(nullif(p ->> 'turno', ''), e.shift);
  if not exists (select 1 from iara.classes c where c.unit_id = v_dest and c.grade_level_id = e.grade_id and c.shift = v_turno and c.status = 'ATIVA') then
    raise exception 'A unidade de destino não oferece esta série neste turno.' using errcode = '22023';
  end if;
  select coalesce(sum(c.offerable_vacancies_count), 0) into v_vagas from iara.classes c where c.unit_id = v_dest and c.grade_level_id = e.grade_id and c.shift = v_turno and c.status = 'ATIVA';
  select count(*) into v_fila from iara.waiting_list_entries w where w.preferred_unit_id = v_dest and w.grade_level_id = e.grade_id and w.status = 'WAITING';
  -- pendências na unidade de origem (informativas)
  select coalesce(jsonb_agg(x), '[]') into v_pend from (
    select format('Devolver %s livro(s) da biblioteca', count(*)) x from iara.biblioteca_emprestimos where student_id = v_student and devolvido_em is null having count(*) > 0
    union all select 'O transporte escolar da escola atual será encerrado' from iara.transporte_alunos where student_id = v_student and fim is null having count(*) > 0
    union all select 'Há acompanhamento de busca ativa em aberto (a escola de destino recebe o histórico)' from iara.busca_ativa_casos where student_id = v_student and situacao <> 'ENCERRADO' having count(*) > 0) z;
  insert into iara.transferencias (student_id, unit_origem, class_origem, unit_destino, grade_code, turno, motivo_tipo, motivo, solicitante, solicitada_por_label, situacao,
                                   vagas_no_pedido, fila_no_pedido, pendencias)
  values (v_student, e.unit_id, e.class_id, v_dest, e.grade, v_turno, p ->> 'motivo_tipo', nullif(btrim(coalesce(p ->> 'motivo', '')), ''),
          case when v_fam then 'FAMILIA' when iara.my_scope() = 'UNIT' then 'ESCOLA' else 'SEDUC' end, iara.my_label(),
          case when v_vagas > 0 and v_fila = 0 then 'AGUARDANDO_DESTINO' else 'FILA' end, v_vagas, v_fila, v_pend)
  returning * into t;
  perform iara.audit_event('TRANSFERENCIA', 'student', v_student::text, e.unit_id, format('Pedido de transferência para a unidade %s (%s).', v_dest, lower(t.situacao)));
  return iara.transferencia_json(t) || jsonb_build_object('mensagem', case when t.situacao = 'AGUARDANDO_DESTINO'
    then 'Pedido enviado: há vaga e ninguém na fila para a série. A unidade de destino confirma a turma e a matrícula muda na hora.'
    else format('Sem vaga livre%s na série e no turno: pela regra da fila (IN nº 025/2025), a transferência entra na fila de transferência da unidade. Faça a inscrição pela IARA ou em Vagas.',
                case when v_fila > 0 then format(' para quem chega (%s criança(s) na fila)', v_fila) else '' end) end);
exception when unique_violation then
  raise exception 'Já há um pedido de transferência em andamento para esta criança.' using errcode = '22023';
end $$;

-- o destino aceita (escolhe a turma com vaga) ou recusa; aceitar muda a matrícula na hora
create or replace function api.transferencia_responder(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  t iara.transferencias;
  c iara.classes;
  v_prev record;
  v_enr uuid := gen_random_uuid();
  v_before jsonb;
begin
  select * into t from iara.transferencias where id = (p ->> 'id')::uuid for update;
  if t.id is null then raise exception 'Pedido não encontrado.' using errcode = 'P0002'; end if;
  if coalesce((p ->> 'cancelar')::boolean, false) then
    if t.situacao <> 'AGUARDANDO_DESTINO' or not ((iara.my_guardian() is not null and t.student_id in (select iara.my_student_ids()))
         or (iara.has_perm('transferencia.write') and (iara.my_scope() <> 'UNIT' or iara.my_unit() = t.unit_origem))) then
      raise exception 'Só quem pediu (ou a escola de origem) cancela um pedido em andamento.' using errcode = '42501';
    end if;
    update iara.transferencias set situacao = 'CANCELADA', respondida_em = now(), respondida_por_label = iara.my_label(), resposta = nullif(btrim(coalesce(p ->> 'motivo', '')), '') where id = t.id;
    return jsonb_build_object('ok', true);
  end if;
  if not (iara.has_perm('transferencia.write') and iara.my_scope() = 'UNIT' and iara.my_unit() = t.unit_destino) then
    raise exception 'Só a unidade de destino responde ao pedido.' using errcode = '42501';
  end if;
  if t.situacao <> 'AGUARDANDO_DESTINO' then raise exception 'Este pedido não está aguardando a unidade.' using errcode = '22023'; end if;
  if not coalesce((p ->> 'aceitar')::boolean, false) then
    if length(btrim(coalesce(p ->> 'motivo', ''))) < 10 then raise exception 'Explique a recusa (mínimo de 10 caracteres).' using errcode = '22023'; end if;
    update iara.transferencias set situacao = 'RECUSADA', resposta = btrim(p ->> 'motivo'), respondida_em = now(), respondida_por_label = iara.my_label() where id = t.id returning * into t;
  else
    select * into c from iara.classes where id = (p ->> 'class_id')::uuid and unit_id = t.unit_destino and shift = t.turno for update;
    if c.id is null or (select code from iara.grade_levels where id = c.grade_level_id) <> t.grade_code then raise exception 'Escolha uma turma da série e do turno pedidos.' using errcode = '22023'; end if;
    if c.offerable_vacancies_count <= 0 then raise exception 'A turma não tem vaga ofertável.' using errcode = '22023'; end if;
    if exists (select 1 from iara.waiting_list_entries w where w.preferred_unit_id = t.unit_destino and w.grade_level_id = c.grade_level_id and w.status = 'WAITING') then
      raise exception 'Agora há crianças na fila para esta série: a vaga é da fila (IN nº 025/2025).' using errcode = '22023';
    end if;
    v_before := iara.class_snapshot(c.id);
    select e.id, e.class_id, e.unit_id into v_prev from iara.enrollments e where e.student_id = t.student_id and e.status = 'ACTIVE' limit 1;
    update iara.enrollments set status = 'TRANSFERRED', exit_type = 'TRANSFERENCIA_INTERNA', end_date = iara.hoje_local() where id = v_prev.id;
    insert into iara.enrollments (id, tenant_id, student_id, class_id, unit_id, school_year, status, enrollment_date, start_date, entry_type, previous_enrollment_id, created_by, is_demo)
    values (v_enr, 1, t.student_id, c.id, c.unit_id, iara.school_year(), 'ACTIVE', iara.hoje_local(), iara.hoje_local(), 'TRANSFERENCIA', v_prev.id, iara.current_user_id(), false);
    update iara.students set current_enrollment_id = v_enr where id = t.student_id;
    perform iara.recount_class(v_prev.class_id);
    perform iara.recount_class(c.id);
    insert into iara.vacancy_events (tenant_id, class_id, unit_id, event_type, quantity, reference, user_id, actor_label)
    values (1, v_prev.class_id, v_prev.unit_id, 'TRANSF_SAIDA', 1, 'Transferência ' || substr(t.id::text, 1, 8), iara.current_user_id(), iara.my_label()),
           (1, c.id, c.unit_id, 'TRANSF_ENTRADA', 1, 'Transferência ' || substr(t.id::text, 1, 8), iara.current_user_id(), iara.my_label());
    update iara.transporte_alunos set fim = iara.hoje_local() where student_id = t.student_id and fim is null;
    update iara.rematriculas set unit_origem = c.unit_id, class_origem = c.id where student_id = t.student_id and ano = extract(year from iara.hoje_local())::int + 1
      and situacao in ('PENDENTE', 'AGUARDANDO_RESULTADO');
    update iara.transferencias set situacao = 'EFETIVADA', class_destino = c.id, enrollment_destino = v_enr, respondida_em = now(), respondida_por_label = iara.my_label()
    where id = t.id returning * into t;
    insert into iara.notifications (tenant_id, guardian_id, student_id, channel, event_type, title, body, status)
    select 1, sg.guardian_id, t.student_id, 'PORTAL', 'TRANSFERENCIA', 'Transferência concluída',
           format('A transferência de %s foi concluída: agora na %s, turma %s.', (select split_part(full_name, ' ', 1) from iara.students where id = t.student_id),
                  (select name from iara.education_units where id = c.unit_id), c.class_name), 'ENVIADA'
    from iara.student_guardians sg where sg.student_id = t.student_id and sg.end_date is null and sg.is_primary;
    insert into iara.vacancy_events (tenant_id, class_id, unit_id, event_type, quantity, before_json, after_json, reference, user_id, actor_label)
    values (1, c.id, c.unit_id, 'MATRICULA', 1, v_before, iara.class_snapshot(c.id), 'Transferência ' || substr(t.id::text, 1, 8), iara.current_user_id(), iara.my_label());
  end if;
  perform iara.audit_event('TRANSFERENCIA', 'student', t.student_id::text, t.unit_destino, format('Transferência %s pela unidade de destino.', lower(t.situacao)));
  return iara.transferencia_json(t);
end $$;

create or replace function api.transferencias_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
begin
  if iara.my_guardian() is not null then
    return jsonb_build_object('itens', (select coalesce(jsonb_agg(iara.transferencia_json(t) order by t.criada_em desc), '[]') from iara.transferencias t where t.student_id in (select iara.my_student_ids())));
  end if;
  perform iara.require_perm('rematricula.read');
  return jsonb_build_object('unit_id', v_unit, 'pode_responder', iara.has_perm('transferencia.write') and iara.my_scope() = 'UNIT',
    'recebidas', (select coalesce(jsonb_agg(iara.transferencia_json(t) order by t.criada_em), '[]') from iara.transferencias t
                  where (v_unit is null or t.unit_destino = v_unit) and t.situacao = 'AGUARDANDO_DESTINO'),
    'enviadas', (select coalesce(jsonb_agg(iara.transferencia_json(t) order by t.criada_em desc), '[]') from (
                  select * from iara.transferencias t where (v_unit is null or t.unit_origem = v_unit) order by t.criada_em desc limit 200) t));
end $$;

-- 3. Demonstração ---------------------------------------------------------------------------------------------------------------
create or replace function iara.demo_gerar_rematricula() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ana uuid := nullif(iara.setting('demo_student_ana'), '')::uuid;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.rematriculas where is_demo or ano = extract(year from iara.hoje_local())::int + 1;
  delete from iara.transferencias where is_demo;
  update iara.tenants set settings = settings || jsonb_build_object('rematricula_prazo', '2026-11-27') where id = 1;
  perform iara.rematricula_gerar(null);
  update iara.rematriculas set is_demo = true where ano = extract(year from iara.hoje_local())::int + 1;
  -- respostas já recebidas (a Ana fica pendente para a família confirmar ao vivo)
  update iara.rematriculas r set situacao = case when h < 52 then 'CONFIRMADA' when h < 55 then 'NAO_RENOVADA' when h < 57 then 'OUTRA_ESCOLA' else r.situacao end,
         confirmada_em = case when h < 57 then now() - make_interval(days => 1 + h % 14) end,
         confirmada_por = case when h < 57 then (case when h % 3 = 0 then 'Secretaria escolar (demonstração)' else 'Família (demonstração)' end) end,
         canal = case when h < 57 then (array['PORTAL', 'IARA', 'UNIDADE'])[1 + h % 3] end,
         motivo = case when h between 52 and 54 then (array['Mudança para outra cidade', 'Matrícula em escola particular', 'Mudança para outro estado'])[1 + h % 3]
                       when h between 55 and 56 then 'Mudança de bairro: quer escola mais perto de casa' end
  from (select id, abs(hashtext(student_id::text || 'rem')) % 100 h from iara.rematriculas where is_demo and situacao = 'PENDENTE' and student_id is distinct from v_ana) z
  where z.id = r.id;
  -- transferências: aguardando o destino (vaga e fila vazia), na fila, recusadas
  insert into iara.transferencias (student_id, unit_origem, class_origem, unit_destino, grade_code, turno, motivo_tipo, motivo, solicitante, solicitada_por_label, situacao,
                                   vagas_no_pedido, fila_no_pedido, resposta, respondida_por_label, respondida_em, criada_em, is_demo)
  select z.student_id, z.unit_id, z.class_id, z.dest, z.grade, z.shift, (array['MUDANCA_ENDERECO', 'PERTO_DO_TRABALHO', 'IRMAOS'])[1 + z.h % 3],
         (array['Mudança para o bairro da escola nova', 'A mãe começou a trabalhar perto da escola', 'O irmão estuda na escola de destino'])[1 + z.h % 3],
         case when z.h % 2 = 0 then 'FAMILIA' else 'ESCOLA' end, case when z.h % 2 = 0 then 'Família (demonstração)' else 'Secretaria escolar (demonstração)' end,
         case when z.vagas > 0 and z.fila = 0 then (case when z.h % 7 = 0 then 'RECUSADA' else 'AGUARDANDO_DESTINO' end) else 'FILA' end, z.vagas, z.fila,
         case when z.vagas > 0 and z.fila = 0 and z.h % 7 = 0 then 'A turma do turno pedido está com a sala no limite de acessibilidade; sugerimos o outro turno.' end,
         case when z.vagas > 0 and z.fila = 0 and z.h % 7 = 0 then 'Direção da unidade (demonstração)' end,
         case when z.vagas > 0 and z.fila = 0 and z.h % 7 = 0 then now() - interval '1 day' end, now() - make_interval(days => 1 + z.h % 6), true
  from (select e.student_id, e.unit_id, e.class_id, gl.code grade, c.shift, abs(hashtext(e.student_id::text || 'tr')) h, d.id dest,
               (select coalesce(sum(c2.offerable_vacancies_count), 0) from iara.classes c2 where c2.unit_id = d.id and c2.grade_level_id = gl.id and c2.shift = c.shift and c2.status = 'ATIVA') vagas,
               (select count(*) from iara.waiting_list_entries w where w.preferred_unit_id = d.id and w.grade_level_id = gl.id and w.status = 'WAITING') fila
        from iara.enrollments e join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
        join lateral (select u.id from iara.education_units u where u.id <> e.unit_id and u.status = 'ATIVA'
                        and exists (select 1 from iara.classes c3 where c3.unit_id = u.id and c3.grade_level_id = gl.id and c3.shift = c.shift and c3.status = 'ATIVA')
                      order by abs(hashtext(u.id::text || e.student_id::text)) limit 1) d on true
        where e.status = 'ACTIVE' and e.student_id is distinct from v_ana and abs(hashtext(e.student_id::text || 'transf')) % 1000 < 2) z;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('rematriculas', (select count(*) from iara.rematriculas where is_demo),
    'confirmadas', (select count(*) from iara.rematriculas where is_demo and situacao = 'CONFIRMADA'),
    'transferencias', (select jsonb_object_agg(situacao, n) from (select situacao, count(*) n from iara.transferencias where is_demo group by 1) z));
end $$;

create or replace function iara.demo_purge_rematricula(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  d timestamptz := coalesce(p_desde, '-infinity'::timestamptz);
  x record;
  n integer := 0;
  v jsonb := '{}'::jsonb;
begin
  perform set_config('iara.skip_audit', 'on', true);
  -- transferências efetivadas ao vivo: a matrícula volta para a origem
  for x in select * from iara.transferencias where not is_demo and criada_em >= d and situacao = 'EFETIVADA' loop
    delete from iara.enrollments where id = x.enrollment_destino;
    update iara.enrollments set status = 'ACTIVE', exit_type = null, end_date = null where student_id = x.student_id and class_id = x.class_origem and status = 'TRANSFERRED';
    update iara.students s set current_enrollment_id = (select id from iara.enrollments e where e.student_id = x.student_id and e.status = 'ACTIVE' limit 1) where s.id = x.student_id;
    update iara.transporte_alunos set fim = null where student_id = x.student_id and fim >= d::date and is_demo;
    perform iara.recount_class(x.class_origem);
    perform iara.recount_class(x.class_destino);
    n := n + 1;
  end loop;
  delete from iara.vacancy_events where occurred_at >= d and reference like 'Transferência %';
  delete from iara.transferencias where not is_demo and criada_em >= d;
  v := v || jsonb_build_object('transferencias_desfeitas', n);
  delete from iara.notifications where created_at >= d and event_type = 'TRANSFERENCIA';
  if exists (select 1 from iara.rematriculas where is_demo and confirmada_em >= d and confirmada_por not like '%(demonstração)%')
     or exists (select 1 from iara.transferencias where is_demo and respondida_em >= d and respondida_por_label not like '%(demonstração)%') then
    v := v || jsonb_build_object('refeita', iara.demo_gerar_rematricula());
  end if;
  perform set_config('iara.skip_audit', 'off', true);
  return v;
end $$;

revoke all on function iara.rematricula_gerar(integer), iara.demo_gerar_rematricula(), iara.demo_purge_rematricula(timestamptz) from public;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('rematriculas', 'motivo', 'PESSOAL', 'vida familiar', 'rematrícula', 'unidade e SEDUC'),
  ('rematriculas', 'confirmada_por', 'PESSOAL', 'identificação', 'auditoria', null),
  ('transferencias', 'motivo', 'PESSOAL', 'vida familiar', 'transferência', 'unidades envolvidas e SEDUC'),
  ('transferencias', 'resposta', 'PESSOAL', 'decisão administrativa', 'transferência', 'unidades envolvidas, SEDUC e família'),
  ('transferencias', 'solicitada_por_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('transferencias', 'respondida_por_label', 'PESSOAL', 'identificação', 'auditoria', null)
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

select iara.demo_gerar_rematricula() where iara.demo_mode();

commit;
