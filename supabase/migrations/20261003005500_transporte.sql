-- IARA Educa — 055 · Sprint 3: transporte escolar
-- Rota planejada (escola, turno, pontos com horário, veículo, motorista e monitor) separada da execução diária (viagem de ida e de
-- volta: situação, atraso, veículo usado, substituição, alunos transportados). Frota com documentação (CNH, curso de transporte
-- escolar — CTB art. 138 — e vistoria). Ocorrências com providência. Cenário do v1.3 “veículo não executa a rota”: a viagem não
-- realizada abre ocorrência, avisa as famílias da rota e abona a falta dos alunos naquele dia. Posição do veículo: sem GPS
-- integrado, é simulada pelo horário planejado e marcada como simulada (nunca dado antigo como posição atual). A família vê só a
-- rota do próprio filho: o ponto dele, o horário e o veículo — nunca os outros pontos nem as outras crianças.
-- Dados de demonstração fictícios (is_demo); placas com prefixo DMO. Critérios oficiais na Q-23.
begin;

insert into iara.organizational_roles (code, tenant_id, name, short_name, description, scope_type, stage_filter, question, org_unit, is_persona, sort) values
  ('TRANSPORTE', 1, 'Transporte escolar · SEDUC', 'Transporte', 'Rotas, pontos e horários, frota e documentação, viagens do dia, ocorrências e alunos aguardando transporte.',
   'NETWORK', null, 'Cada aluno chegou à escola hoje?', 'Gerência de Transporte Escolar', true, 16)
on conflict (code) do update set name = excluded.name, short_name = excluded.short_name, description = excluded.description,
  scope_type = excluded.scope_type, question = excluded.question, org_unit = excluded.org_unit, is_persona = excluded.is_persona, sort = excluded.sort;

insert into iara.permissions (code, description, is_sensitive) values
  ('transporte.read', 'Consultar rotas, alunos transportados, viagens e ocorrências (a unidade só as suas rotas)', true),
  ('transporte.manage', 'Gerir rotas, frota, alunos transportados e registrar a execução das viagens', true)
on conflict (code) do update set description = excluded.description, is_sensitive = excluded.is_sensitive;
insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('TRANSPORTE', 'units.read'), ('TRANSPORTE', 'classes.read'), ('TRANSPORTE', 'config.read'), ('TRANSPORTE', 'kpi.network'),
  ('TRANSPORTE', 'transporte.read'), ('TRANSPORTE', 'transporte.manage'), ('TRANSPORTE', 'mural.publish'),
  ('DIRETOR_UNIDADE', 'transporte.read'), ('SECRETARIA_ESCOLAR', 'transporte.read'),
  ('SECRETARIO', 'transporte.read'), ('SUPERINTENDENCIA', 'transporte.read'), ('SUPERINTENDENCIA', 'transporte.manage'), ('GERENCIA_EI', 'transporte.read')
) v(r, p)
on conflict do nothing;

-- 1. Tabelas -------------------------------------------------------------------------------------------------------------------
create table if not exists iara.transporte_veiculos (
  id uuid primary key default gen_random_uuid(),
  placa text not null unique,
  tipo text not null check (tipo in ('VAN', 'MICRO', 'ONIBUS')),
  capacidade smallint not null check (capacidade > 0),
  acessivel boolean not null default false,
  ano smallint,
  operador text not null,
  situacao text not null default 'ATIVO' check (situacao in ('ATIVO', 'RESERVA', 'MANUTENCAO', 'INATIVO')),
  vistoria_validade date,
  is_demo boolean not null default true
);
create table if not exists iara.transporte_motoristas (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  cnh_categoria text not null default 'D',
  cnh_validade date,
  curso_validade date,
  operador text not null,
  situacao text not null default 'ATIVO' check (situacao in ('ATIVO', 'RESERVA', 'AFASTADO', 'INATIVO')),
  is_demo boolean not null default true
);
create table if not exists iara.transporte_rotas (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nome text not null,
  unit_id integer not null references iara.education_units(id),
  turno text not null check (turno in ('MANHA', 'TARDE', 'NOITE')),
  veiculo_id uuid references iara.transporte_veiculos(id) on delete set null,
  motorista_id uuid references iara.transporte_motoristas(id) on delete set null,
  monitor_nome text,
  chegada_ida time not null,
  saida_volta time not null,
  km numeric(6, 1),
  situacao text not null default 'ATIVA' check (situacao in ('ATIVA', 'SUSPENSA', 'ENCERRADA')),
  is_demo boolean not null default true
);
create index if not exists transporte_rotas_unit_idx on iara.transporte_rotas (unit_id);
create table if not exists iara.transporte_pontos (
  id uuid primary key default gen_random_uuid(),
  rota_id uuid not null references iara.transporte_rotas(id) on delete cascade,
  ordem smallint not null,
  nome text not null,
  lat double precision not null,
  lng double precision not null,
  horario_ida time not null,
  horario_volta time not null,
  is_demo boolean not null default true,
  unique (rota_id, ordem)
);
create table if not exists iara.transporte_alunos (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references iara.students(id) on delete cascade,
  rota_id uuid not null references iara.transporte_rotas(id) on delete cascade,
  ponto_id uuid references iara.transporte_pontos(id) on delete set null,
  motivo text not null check (motivo in ('DISTANCIA', 'ZONA_RURAL', 'DEFICIENCIA', 'OUTRO')),
  observacao text,
  inicio date not null default current_date,
  fim date,
  incluido_por_label text,
  is_demo boolean not null default true
);
create unique index if not exists transporte_alunos_ativo on iara.transporte_alunos (student_id) where fim is null;
create index if not exists transporte_alunos_rota_idx on iara.transporte_alunos (rota_id) where fim is null;
create table if not exists iara.transporte_viagens (
  id uuid primary key default gen_random_uuid(),
  rota_id uuid not null references iara.transporte_rotas(id) on delete cascade,
  data date not null,
  sentido text not null check (sentido in ('IDA', 'VOLTA')),
  situacao text not null check (situacao in ('EM_ANDAMENTO', 'CONCLUIDA', 'NAO_REALIZADA')),
  atraso_min smallint not null default 0,
  motivo text,
  veiculo_id uuid references iara.transporte_veiculos(id) on delete set null,
  motorista_id uuid references iara.transporte_motoristas(id) on delete set null,
  substituicao boolean not null default false,
  alunos_previstos smallint,
  alunos_transportados smallint,
  registrado_por_label text,
  registrado_em timestamptz not null default now(),
  is_demo boolean not null default true,
  unique (rota_id, data, sentido)
);
create index if not exists transporte_viagens_data_idx on iara.transporte_viagens (data);
create table if not exists iara.transporte_embarques (
  rota_id uuid not null references iara.transporte_rotas(id) on delete cascade,
  data date not null,
  sentido text not null check (sentido in ('IDA', 'VOLTA')),
  student_id uuid not null references iara.students(id) on delete cascade,
  embarcou boolean not null,
  registrado_em timestamptz not null default now(),
  registrado_por_label text,
  is_demo boolean not null default false,
  primary key (rota_id, data, sentido, student_id)
);
create table if not exists iara.transporte_ocorrencias (
  id uuid primary key default gen_random_uuid(),
  rota_id uuid not null references iara.transporte_rotas(id) on delete cascade,
  data date not null,
  sentido text check (sentido in ('IDA', 'VOLTA')),
  tipo text not null check (tipo in ('ATRASO', 'QUEBRA', 'SUBSTITUICAO', 'ROTA_NAO_EXECUTADA', 'ACIDENTE', 'ALUNO_NAO_EMBARCOU', 'COMPORTAMENTO', 'OUTRO')),
  student_id uuid references iara.students(id) on delete set null,
  descricao text not null,
  providencia text,
  familias_avisadas boolean not null default false,
  situacao text not null default 'ABERTA' check (situacao in ('ABERTA', 'RESOLVIDA')),
  registrada_por_label text,
  created_at timestamptz not null default now(),
  resolvida_em timestamptz,
  is_demo boolean not null default true
);
create index if not exists transporte_ocorrencias_rota_idx on iara.transporte_ocorrencias (rota_id, data desc);
create table if not exists iara.transporte_avisos (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references iara.students(id) on delete cascade,
  data date not null,
  sentido text not null default 'AMBOS' check (sentido in ('IDA', 'VOLTA', 'AMBOS')),
  motivo text,
  enviado_por_guardian uuid references iara.guardians(id) on delete set null,
  canal text not null default 'PORTAL',
  created_at timestamptz not null default now(),
  is_demo boolean not null default false,
  unique (student_id, data)
);
-- falta abonada porque o transporte não foi realizado (a chamada respeita, mesmo lançada depois)
create table if not exists iara.transporte_abonos (
  student_id uuid not null references iara.students(id) on delete cascade,
  data date not null,
  rota_id uuid references iara.transporte_rotas(id) on delete cascade,
  motivo text not null,
  created_at timestamptz not null default now(),
  is_demo boolean not null default true,
  primary key (student_id, data)
);

alter table iara.transporte_veiculos enable row level security;
alter table iara.transporte_motoristas enable row level security;
alter table iara.transporte_rotas enable row level security;
alter table iara.transporte_pontos enable row level security;
alter table iara.transporte_alunos enable row level security;
alter table iara.transporte_viagens enable row level security;
alter table iara.transporte_embarques enable row level security;
alter table iara.transporte_ocorrencias enable row level security;
alter table iara.transporte_avisos enable row level security;
alter table iara.transporte_abonos enable row level security;

create or replace function iara.falta_abono_transporte() returns trigger
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_motivo text;
begin
  if new.tipo = 'FALTA' then
    select a.motivo into v_motivo from iara.transporte_abonos a join iara.frequencia_registros r on r.id = new.registro_id
    where a.student_id = new.student_id and a.data = r.data;
    if v_motivo is not null then
      new.tipo := 'FALTA_JUSTIFICADA';
      new.justificativa := v_motivo;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists falta_abono_transporte on iara.frequencia_faltas;
create trigger falta_abono_transporte before insert on iara.frequencia_faltas for each row execute function iara.falta_abono_transporte();

-- 2. Apoios -------------------------------------------------------------------------------------------------------------------
create or replace function iara.hoje_local() returns date language sql stable as $$ select (now() at time zone 'America/Sao_Paulo')::date $$;
create or replace function iara.agora_local() returns time language sql stable as $$ select (now() at time zone 'America/Sao_Paulo')::time $$;
create or replace function iara.km_entre(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision) returns double precision
language sql immutable as $$ select sqrt(power((lat2 - lat1) * 111.2, 2) + power((lng2 - lng1) * 102.0, 2)) $$;

create or replace function iara.rota_acesso(p_rota uuid) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select iara.has_perm('transporte.read') and exists (select 1 from iara.transporte_rotas r where r.id = p_rota
    and (iara.my_scope() = 'NETWORK' or iara.can_access_unit(r.unit_id)))
$$;

-- estado da viagem de hoje: o registrado vale; sem registro, a simulação pelo horário planejado (marcada como simulada)
create or replace function iara.transporte_estado(p_rota uuid, p_sentido text) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  r iara.transporte_rotas;
  v iara.transporte_viagens;
  u record;
  v_hoje date := iara.hoje_local();
  v_now time := iara.agora_local();
  v_atraso integer;
  h integer;
  pts record;
  t time[] := '{}';
  la double precision[] := '{}';
  lo double precision[] := '{}';
  nm text[] := '{}';
  n integer;
  i integer;
  f double precision;
begin
  select * into r from iara.transporte_rotas where id = p_rota;
  if r.id is null then return null; end if;
  select lat, lng, short_name into u from iara.education_units where id = r.unit_id;
  if not iara.dia_letivo(v_hoje, r.unit_id) then return jsonb_build_object('sentido', p_sentido, 'situacao', 'SEM_AULA'); end if;
  select * into v from iara.transporte_viagens where rota_id = r.id and data = v_hoje and sentido = p_sentido;
  if v.id is not null and v.situacao = 'NAO_REALIZADA' then
    return jsonb_build_object('sentido', p_sentido, 'situacao', 'NAO_REALIZADA', 'motivo', v.motivo, 'registrada', true);
  end if;
  h := abs(hashtext(r.id::text || v_hoje::text || p_sentido)) % 100;
  v_atraso := coalesce(v.atraso_min, case when h < 80 then h % 5 when h < 95 then 6 + h % 9 else 15 + h % 16 end);
  if p_sentido = 'IDA' then
    for pts in select * from iara.transporte_pontos where rota_id = r.id order by ordem loop
      t := t || (pts.horario_ida + make_interval(mins => v_atraso)); la := la || pts.lat; lo := lo || pts.lng; nm := nm || pts.nome;
    end loop;
    t := t || (r.chegada_ida + make_interval(mins => v_atraso)); la := la || u.lat; lo := lo || u.lng; nm := nm || u.short_name;
  else
    t := t || (r.saida_volta + make_interval(mins => v_atraso)); la := la || u.lat; lo := lo || u.lng; nm := nm || u.short_name;
    for pts in select * from iara.transporte_pontos where rota_id = r.id order by ordem desc loop
      t := t || (pts.horario_volta + make_interval(mins => v_atraso)); la := la || pts.lat; lo := lo || pts.lng; nm := nm || pts.nome;
    end loop;
  end if;
  n := cardinality(t);
  if v.id is not null and v.situacao = 'CONCLUIDA' or v_now >= t[n] then
    return jsonb_build_object('sentido', p_sentido, 'situacao', 'CONCLUIDA', 'atraso_min', v_atraso, 'inicio', t[1], 'fim', t[n],
      'registrada', v.id is not null, 'simulada', v.id is null, 'substituicao', coalesce(v.substituicao, false));
  end if;
  if v_now < t[1] - interval '15 minutes' and v.id is null then
    return jsonb_build_object('sentido', p_sentido, 'situacao', 'PREVISTA', 'atraso_min', 0, 'inicio', t[1] - make_interval(mins => v_atraso), 'fim', t[n] - make_interval(mins => v_atraso));
  end if;
  if v_now < t[1] then
    i := 1; f := 0;
  else
    i := 1;
    while i < n and v_now >= t[i + 1] loop i := i + 1; end loop;
    f := extract(epoch from (v_now - t[i])) / greatest(extract(epoch from (t[i + 1] - t[i])), 1);
  end if;
  return jsonb_build_object('sentido', p_sentido, 'situacao', 'EM_ANDAMENTO', 'atraso_min', v_atraso, 'inicio', t[1], 'fim', t[n],
    'registrada', v.id is not null, 'simulada', true, 'substituicao', coalesce(v.substituicao, false),
    'posicao', jsonb_build_object('lat', la[i] + (la[i + 1] - la[i]) * f, 'lng', lo[i] + (lo[i + 1] - lo[i]) * f,
                                  'atualizado_em', now(), 'fonte', 'Simulada pelo horário planejado (sem GPS integrado)'),
    'proximo', jsonb_build_object('nome', nm[i + 1], 'previsto', t[i + 1]));
end $$;

create or replace function iara.rota_resumo(r iara.transporte_rotas) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', r.id, 'codigo', r.codigo, 'nome', r.nome, 'unit_id', r.unit_id, 'unidade', u.short_name, 'turno', r.turno,
    'situacao', r.situacao, 'km', r.km, 'chegada_ida', r.chegada_ida, 'saida_volta', r.saida_volta, 'monitor', r.monitor_nome,
    'veiculo', (select jsonb_build_object('id', v.id, 'placa', v.placa, 'tipo', v.tipo, 'capacidade', v.capacidade, 'acessivel', v.acessivel, 'situacao', v.situacao)
                from iara.transporte_veiculos v where v.id = r.veiculo_id),
    'motorista', (select jsonb_build_object('id', m.id, 'nome', m.nome) from iara.transporte_motoristas m where m.id = r.motorista_id),
    'alunos', (select count(*) from iara.transporte_alunos a where a.rota_id = r.id and a.fim is null),
    'pontos', (select count(*) from iara.transporte_pontos p where p.rota_id = r.id),
    'is_demo', r.is_demo)
  from iara.education_units u where u.id = r.unit_id
$$;

-- 3. Painel, rota, frota e alunos sem rota -----------------------------------------------------------------------------------------
create or replace function api.transporte_painel(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_hoje date := iara.hoje_local();
begin
  if not (iara.has_perm('transporte.read') or iara.has_perm('kpi.network')) then raise exception 'Sem permissão.' using errcode = '42501'; end if;
  return (with rr as (select r from iara.transporte_rotas r where r.situacao = 'ATIVA' and (v_unit is null or r.unit_id = v_unit)),
    est as (select (x.r).id id, iara.transporte_estado((x.r).id, case when iara.agora_local() < (x.r).saida_volta - interval '20 minutes' then 'IDA' else 'VOLTA' end) e from rr x),
    vg as (select v.* from iara.transporte_viagens v join rr x on (x.r).id = v.rota_id where v.data >= v_hoje - 30 and v.data < v_hoje)
    select jsonb_build_object(
      'unidade', (select name from iara.education_units where id = v_unit),
      'rotas', (select count(*) from rr),
      'alunos', (select count(*) from iara.transporte_alunos a join rr x on (x.r).id = a.rota_id where a.fim is null),
      'sem_rota', (select count(*) from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
                   where s.transport_need and (v_unit is null or e.unit_id = v_unit)
                     and not exists (select 1 from iara.transporte_alunos a where a.student_id = s.id and a.fim is null)),
      'hoje', jsonb_build_object('em_andamento', (select count(*) from est where e ->> 'situacao' = 'EM_ANDAMENTO'),
                                 'concluidas', (select count(*) from est where e ->> 'situacao' = 'CONCLUIDA'),
                                 'previstas', (select count(*) from est where e ->> 'situacao' = 'PREVISTA'),
                                 'atrasadas', (select count(*) from est where (e ->> 'atraso_min')::int >= 10),
                                 'nao_realizadas', (select count(*) from est where e ->> 'situacao' = 'NAO_REALIZADA')),
      'pontualidade_30d', (select round(100.0 * count(*) filter (where situacao = 'CONCLUIDA' and atraso_min < 10) / nullif(count(*), 0), 1) from vg),
      'nao_realizadas_30d', (select count(*) from vg where situacao = 'NAO_REALIZADA'),
      'substituicoes_30d', (select count(*) from vg where substituicao),
      'ocorrencias_abertas', (select count(*) from iara.transporte_ocorrencias o join rr x on (x.r).id = o.rota_id where o.situacao = 'ABERTA'),
      'frota', case when v_unit is null then jsonb_build_object(
          'veiculos', (select count(*) from iara.transporte_veiculos where situacao <> 'INATIVO'),
          'reserva', (select count(*) from iara.transporte_veiculos where situacao = 'RESERVA'),
          'manutencao', (select count(*) from iara.transporte_veiculos where situacao = 'MANUTENCAO'),
          'docs_vencidas', (select count(*) from iara.transporte_veiculos where situacao <> 'INATIVO' and vistoria_validade < v_hoje)
                         + (select count(*) from iara.transporte_motoristas where situacao <> 'INATIVO' and (cnh_validade < v_hoje or curso_validade < v_hoje)),
          'docs_vencendo', (select count(*) from iara.transporte_veiculos where situacao <> 'INATIVO' and vistoria_validade between v_hoje and v_hoje + 30)
                         + (select count(*) from iara.transporte_motoristas where situacao <> 'INATIVO'
                            and (cnh_validade between v_hoje and v_hoje + 30 or curso_validade between v_hoje and v_hoje + 30))) end,
      'pode_gerir', iara.has_perm('transporte.manage'),
      'lista', case when iara.has_perm('transporte.read') then (select coalesce(jsonb_agg(iara.rota_resumo(x.r) || jsonb_build_object('hoje', est.e)
                 order by (est.e ->> 'situacao') = 'NAO_REALIZADA' desc, coalesce((est.e ->> 'atraso_min')::int, 0) desc, (x.r).codigo), '[]')
               from rr x join est on est.id = (x.r).id) end));
end $$;

create or replace function api.transporte_rota(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  r iara.transporte_rotas;
  u record;
  v_hoje date := iara.hoje_local();
begin
  select * into r from iara.transporte_rotas where id = (p ->> 'id')::uuid;
  if r.id is null or not iara.rota_acesso(r.id) then raise exception 'Rota não encontrada ou fora do seu escopo.' using errcode = 'P0002'; end if;
  select lat, lng, name, short_name into u from iara.education_units where id = r.unit_id;
  return iara.rota_resumo(r) || coalesce(iara.rota_trajeto_json(r.id), '{}') || jsonb_build_object(
    'escola', jsonb_build_object('nome', u.name, 'lat', u.lat, 'lng', u.lng),
    'pode_gerir', iara.has_perm('transporte.manage'),
    'hoje', jsonb_build_object('ida', iara.transporte_estado(r.id, 'IDA'), 'volta', iara.transporte_estado(r.id, 'VOLTA')),
    'pontos', (select coalesce(jsonb_agg(jsonb_build_object('id', p2.id, 'ordem', p2.ordem, 'nome', p2.nome, 'lat', p2.lat, 'lng', p2.lng,
        'horario_ida', p2.horario_ida, 'horario_volta', p2.horario_volta,
        'alunos', (select count(*) from iara.transporte_alunos a where a.ponto_id = p2.id and a.fim is null)) order by p2.ordem), '[]')
      from iara.transporte_pontos p2 where p2.rota_id = r.id),
    'alunos_rota', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'student_id', s.id, 'nome', s.full_name, 'turma', c.class_name, 'aee', s.aee_status,
        'ponto', pt.nome, 'ponto_ordem', pt.ordem, 'motivo', a.motivo, 'desde', a.inicio,
        'aviso_hoje', (select jsonb_build_object('sentido', av.sentido, 'motivo', av.motivo) from iara.transporte_avisos av where av.student_id = s.id and av.data = v_hoje))
        order by pt.ordem, s.full_name), '[]')
      from iara.transporte_alunos a join iara.students s on s.id = a.student_id left join iara.transporte_pontos pt on pt.id = a.ponto_id
      left join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' left join iara.classes c on c.id = e.class_id
      where a.rota_id = r.id and a.fim is null),
    'viagens', (select coalesce(jsonb_agg(jsonb_build_object('data', v.data, 'sentido', v.sentido, 'situacao', v.situacao, 'atraso_min', v.atraso_min, 'motivo', v.motivo,
        'substituicao', v.substituicao, 'veiculo', (select placa from iara.transporte_veiculos where id = v.veiculo_id),
        'previstos', v.alunos_previstos, 'transportados', v.alunos_transportados) order by v.data desc, v.sentido), '[]')
      from (select * from iara.transporte_viagens where rota_id = r.id order by data desc limit 40) v),
    'ocorrencias', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'data', o.data, 'sentido', o.sentido, 'tipo', o.tipo, 'descricao', o.descricao,
        'providencia', o.providencia, 'situacao', o.situacao, 'aluno', (select full_name from iara.students where id = o.student_id),
        'familias_avisadas', o.familias_avisadas, 'por', o.registrada_por_label) order by o.data desc, o.created_at desc), '[]')
      from (select * from iara.transporte_ocorrencias where rota_id = r.id order by data desc, created_at desc limit 30) o),
    'pontualidade_30d', (select round(100.0 * count(*) filter (where situacao = 'CONCLUIDA' and atraso_min < 10) / nullif(count(*), 0), 1)
                         from iara.transporte_viagens where rota_id = r.id and data >= v_hoje - 30 and data < v_hoje),
    'reservas', case when iara.has_perm('transporte.manage') then (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'placa', v.placa, 'tipo', v.tipo, 'capacidade', v.capacidade) order by v.capacidade), '[]')
                  from iara.transporte_veiculos v where v.situacao = 'RESERVA') end);
end $$;

create or replace function api.transporte_frota(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_hoje date := iara.hoje_local();
begin
  perform iara.require_perm('transporte.manage');
  return jsonb_build_object(
    'veiculos', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'placa', v.placa, 'tipo', v.tipo, 'capacidade', v.capacidade, 'acessivel', v.acessivel,
        'ano', v.ano, 'operador', v.operador, 'situacao', v.situacao, 'vistoria_validade', v.vistoria_validade,
        'doc', case when v.vistoria_validade < v_hoje then 'VENCIDA' when v.vistoria_validade <= v_hoje + 30 then 'VENCENDO' else 'OK' end,
        'rota', (select codigo from iara.transporte_rotas where veiculo_id = v.id and situacao = 'ATIVA' limit 1), 'is_demo', v.is_demo)
        order by (v.vistoria_validade < v_hoje) desc, v.situacao, v.placa), '[]') from iara.transporte_veiculos v where v.situacao <> 'INATIVO'),
    'motoristas', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'nome', m.nome, 'cnh_categoria', m.cnh_categoria, 'cnh_validade', m.cnh_validade,
        'curso_validade', m.curso_validade, 'operador', m.operador, 'situacao', m.situacao,
        'doc', case when m.cnh_validade < v_hoje or m.curso_validade < v_hoje then 'VENCIDA'
                    when m.cnh_validade <= v_hoje + 30 or m.curso_validade <= v_hoje + 30 then 'VENCENDO' else 'OK' end,
        'rota', (select codigo from iara.transporte_rotas where motorista_id = m.id and situacao = 'ATIVA' limit 1), 'is_demo', m.is_demo)
        order by (m.cnh_validade < v_hoje or m.curso_validade < v_hoje) desc, m.situacao, m.nome), '[]') from iara.transporte_motoristas m where m.situacao <> 'INATIVO'));
end $$;

-- alunos que precisam de transporte e não têm rota, com a rota sugerida (mesma escola e turno) e o ponto mais próximo
create or replace function api.transporte_sem_rota(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
begin
  perform iara.require_perm('transporte.read');
  return (select coalesce(jsonb_agg(jsonb_build_object('student_id', x.id, 'nome', x.full_name, 'unidade', x.unidade, 'unit_id', x.unit_id, 'turma', x.class_name,
      'turno', x.shift, 'aee', x.aee_status, 'km_escola', round(x.km::numeric, 1), 'situacao', x.school_transport_status,
      'sugestao', (select jsonb_build_object('rota_id', r.id, 'codigo', r.codigo, 'vagas', v.capacidade - (select count(*) from iara.transporte_alunos a where a.rota_id = r.id and a.fim is null),
                     'ponto_id', pt.id, 'ponto', pt.nome, 'km_ponto', round(iara.km_entre(x.lat, x.lng, pt.lat, pt.lng)::numeric, 2))
                   from iara.transporte_rotas r join iara.transporte_veiculos v on v.id = r.veiculo_id
                   cross join lateral (select * from iara.transporte_pontos p2 where p2.rota_id = r.id order by iara.km_entre(x.lat, x.lng, p2.lat, p2.lng) limit 1) pt
                   where r.unit_id = x.unit_id and r.turno = x.shift and r.situacao = 'ATIVA'
                   order by iara.km_entre(x.lat, x.lng, pt.lat, pt.lng) limit 1))
      order by x.unidade, x.full_name), '[]')
    from (select s.id, s.full_name, s.aee_status, s.school_transport_status, e.unit_id, u.short_name unidade, c.class_name, c.shift,
                 extensions.st_y(a.location::extensions.geometry) lat, extensions.st_x(a.location::extensions.geometry) lng, iara.km_entre(extensions.st_y(a.location::extensions.geometry), extensions.st_x(a.location::extensions.geometry), u.lat, u.lng) km
          from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
          join iara.classes c on c.id = e.class_id join iara.education_units u on u.id = e.unit_id left join iara.addresses a on a.id = s.address_id
          where s.transport_need and (v_unit is null or e.unit_id = v_unit) and iara.can_access_unit(e.unit_id)
            and not exists (select 1 from iara.transporte_alunos t where t.student_id = s.id and t.fim is null)) x);
end $$;

create or replace function api.transporte_aluno_incluir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  r iara.transporte_rotas;
  v_ponto uuid := nullif(p ->> 'ponto_id', '')::uuid;
  v_motivo text := coalesce(nullif(p ->> 'motivo', ''), 'DISTANCIA');
  v_cap integer;
  v_n integer;
  a iara.transporte_alunos;
begin
  perform iara.require_perm('transporte.manage');
  select * into r from iara.transporte_rotas where id = (p ->> 'rota_id')::uuid and situacao = 'ATIVA';
  if r.id is null then raise exception 'Rota não encontrada.' using errcode = 'P0002'; end if;
  if not exists (select 1 from iara.enrollments e join iara.classes c on c.id = e.class_id where e.student_id = v_student and e.status = 'ACTIVE'
                 and e.unit_id = r.unit_id and c.shift = r.turno) then
    raise exception 'A rota atende outra escola ou outro turno.' using errcode = '22023';
  end if;
  if v_motivo not in ('DISTANCIA', 'ZONA_RURAL', 'DEFICIENCIA', 'OUTRO') then raise exception 'Motivo inválido.' using errcode = '22023'; end if;
  if v_ponto is null or not exists (select 1 from iara.transporte_pontos where id = v_ponto and rota_id = r.id) then raise exception 'Escolha o ponto de embarque da rota.' using errcode = '22023'; end if;
  select capacidade into v_cap from iara.transporte_veiculos where id = r.veiculo_id;
  select count(*) into v_n from iara.transporte_alunos where rota_id = r.id and fim is null;
  if v_n >= coalesce(v_cap, 0) then raise exception 'O veículo da rota está lotado (% lugares).', v_cap using errcode = '22023'; end if;
  update iara.transporte_alunos set fim = current_date where student_id = v_student and fim is null;
  insert into iara.transporte_alunos (student_id, rota_id, ponto_id, motivo, observacao, incluido_por_label, is_demo)
  values (v_student, r.id, v_ponto, v_motivo, nullif(btrim(coalesce(p ->> 'observacao', '')), ''), iara.my_label(), false) returning * into a;
  update iara.students set transport_need = true, school_transport_status = 'ATENDIDO' where id = v_student;
  perform iara.avisar_familia(v_student, 'TRANSPORTE_INCLUIDO', 'Transporte escolar liberado',
    format('A criança foi incluída na rota %s. Ponto de embarque: %s, às %s. Veja em Vida escolar → Transporte ou pergunte à IARA.',
           r.codigo, (select nome from iara.transporte_pontos where id = v_ponto), (select to_char(horario_ida, 'HH24:MI') from iara.transporte_pontos where id = v_ponto)));
  perform iara.audit_event('TRANSPORTE_ALUNO_INCLUIDO', 'student', v_student::text, r.unit_id, 'Aluno incluído na rota ' || r.codigo || '.');
  return jsonb_build_object('ok', true, 'id', a.id);
end $$;

create or replace function api.transporte_aluno_remover(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  a iara.transporte_alunos;
begin
  perform iara.require_perm('transporte.manage');
  if length(btrim(coalesce(p ->> 'motivo', ''))) < 5 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
  update iara.transporte_alunos set fim = current_date, observacao = coalesce(observacao || ' · ', '') || 'Saída: ' || btrim(p ->> 'motivo')
  where id = (p ->> 'id')::uuid and fim is null returning * into a;
  if a.id is null then raise exception 'Vínculo não encontrado.' using errcode = 'P0002'; end if;
  update iara.students set school_transport_status = 'ENCERRADO' where id = a.student_id;
  perform iara.audit_event('TRANSPORTE_ALUNO_REMOVIDO', 'student', a.student_id::text, null, 'Aluno retirado da rota: ' || left(btrim(p ->> 'motivo'), 120) || '.');
  return jsonb_build_object('ok', true);
end $$;

-- 4. Execução do dia: viagem, embarque e ocorrência ------------------------------------------------------------------------------
create or replace function api.transporte_viagem_registrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r iara.transporte_rotas;
  v_data date := coalesce(nullif(p ->> 'data', '')::date, iara.hoje_local());
  v_sentido text := p ->> 'sentido';
  v_sit text := p ->> 'situacao';
  v_atraso integer := greatest(coalesce(nullif(p ->> 'atraso_min', '')::int, 0), 0);
  v_motivo text := nullif(btrim(coalesce(p ->> 'motivo', '')), '');
  v_sub uuid := nullif(p ->> 'veiculo_substituto_id', '')::uuid;
  v iara.transporte_viagens;
  v_prev integer;
  x record;
  v_avisadas integer := 0;
begin
  perform iara.require_perm('transporte.manage');
  select * into r from iara.transporte_rotas where id = (p ->> 'rota_id')::uuid;
  if r.id is null then raise exception 'Rota não encontrada.' using errcode = 'P0002'; end if;
  if v_sentido not in ('IDA', 'VOLTA') or v_sit not in ('EM_ANDAMENTO', 'CONCLUIDA', 'NAO_REALIZADA') then raise exception 'Sentido ou situação inválida.' using errcode = '22023'; end if;
  if v_data > iara.hoje_local() or v_data < iara.hoje_local() - 7 then raise exception 'Data fora do período (até 7 dias atrás).' using errcode = '22023'; end if;
  if v_sit = 'NAO_REALIZADA' and coalesce(length(v_motivo), 0) < 5 then raise exception 'Informe o motivo da viagem não realizada.' using errcode = '22023'; end if;
  if v_atraso >= 10 and v_motivo is null then raise exception 'Informe o motivo do atraso.' using errcode = '22023'; end if;
  if v_sub is not null and not exists (select 1 from iara.transporte_veiculos where id = v_sub and situacao in ('RESERVA', 'ATIVO')) then raise exception 'Veículo substituto inválido.' using errcode = '22023'; end if;
  select count(*) into v_prev from iara.transporte_alunos where rota_id = r.id and fim is null;
  insert into iara.transporte_viagens (rota_id, data, sentido, situacao, atraso_min, motivo, veiculo_id, motorista_id, substituicao, alunos_previstos,
                                       alunos_transportados, registrado_por_label, is_demo)
  values (r.id, v_data, v_sentido, v_sit, case when v_sit = 'NAO_REALIZADA' then 0 else v_atraso end, v_motivo, coalesce(v_sub, r.veiculo_id), r.motorista_id,
          v_sub is not null, v_prev,
          case when v_sit = 'NAO_REALIZADA' then 0 else (select count(*) from iara.transporte_embarques where rota_id = r.id and data = v_data and sentido = v_sentido and embarcou) end,
          iara.my_label(), false)
  on conflict (rota_id, data, sentido) do update set situacao = excluded.situacao, atraso_min = excluded.atraso_min, motivo = excluded.motivo,
    veiculo_id = excluded.veiculo_id, substituicao = excluded.substituicao, alunos_transportados = excluded.alunos_transportados,
    registrado_por_label = excluded.registrado_por_label, registrado_em = now(), is_demo = false
  returning * into v;

  -- cenário do v1.3: a rota não executada é incidente registrado, famílias avisadas e falta abonada (ida)
  if v_sit = 'NAO_REALIZADA' or v_atraso >= 15 or v_sub is not null then
    for x in select a.student_id from iara.transporte_alunos a where a.rota_id = r.id and a.fim is null loop
      perform iara.avisar_familia(x.student_id, case when v_sit = 'NAO_REALIZADA' then 'TRANSPORTE_NAO_REALIZADO' else 'TRANSPORTE_ATRASO' end,
        case when v_sit = 'NAO_REALIZADA' then 'Transporte escolar não vai passar' else 'Transporte escolar atrasado' end,
        case when v_sit = 'NAO_REALIZADA' then format('A %s da rota %s não será realizada hoje (%s). %s', lower(v_sentido), r.codigo, v_motivo,
                  case when v_sentido = 'IDA' then 'A falta de hoje fica abonada.' else 'A escola organiza a saída com as famílias.' end)
             else format('A %s da rota %s está com cerca de %s min de atraso%s.', lower(v_sentido), r.codigo, v_atraso,
                  coalesce(' (' || v_motivo || ')', '')) end);
      v_avisadas := v_avisadas + 1;
      if v_sit = 'NAO_REALIZADA' and v_sentido = 'IDA' then
        insert into iara.transporte_abonos (student_id, data, rota_id, motivo, is_demo)
        values (x.student_id, v_data, r.id, format('Transporte escolar não realizado (rota %s)', r.codigo), false) on conflict do nothing;
        update iara.frequencia_faltas f set tipo = 'FALTA_JUSTIFICADA', justificativa = format('Transporte escolar não realizado (rota %s)', r.codigo)
        from iara.frequencia_registros fr where fr.id = f.registro_id and f.student_id = x.student_id and fr.data = v_data and f.tipo = 'FALTA';
      end if;
    end loop;
    insert into iara.transporte_ocorrencias (rota_id, data, sentido, tipo, descricao, providencia, familias_avisadas, situacao, registrada_por_label, is_demo)
    values (r.id, v_data, v_sentido,
            case when v_sit = 'NAO_REALIZADA' then 'ROTA_NAO_EXECUTADA' when v_sub is not null then 'SUBSTITUICAO' else 'ATRASO' end,
            coalesce(v_motivo, 'Atraso na rota'),
            case when v_sit = 'NAO_REALIZADA' then format('%s família(s) avisada(s)%s; escola informada.', v_avisadas, case when v_sentido = 'IDA' then ', falta abonada' else '' end)
                 when v_sub is not null then 'Veículo reserva ' || (select placa from iara.transporte_veiculos where id = v_sub) || ' em operação; famílias avisadas.'
                 else format('%s família(s) avisada(s).', v_avisadas) end,
            true, case when v_sit = 'NAO_REALIZADA' then 'ABERTA' else 'RESOLVIDA' end, iara.my_label(), false);
  end if;
  perform iara.audit_event('TRANSPORTE_VIAGEM', 'transporte_rota', r.id::text, r.unit_id,
    format('Viagem %s %s da rota %s: %s%s.', lower(v_sentido), to_char(v_data, 'DD/MM'), r.codigo, lower(replace(v_sit, '_', ' ')),
           case when v_atraso > 0 and v_sit <> 'NAO_REALIZADA' then format(' (%s min de atraso)', v_atraso) else '' end));
  return jsonb_build_object('ok', true, 'familias_avisadas', v_avisadas, 'estado', iara.transporte_estado(r.id, v_sentido));
end $$;

-- lista de embarque do dia (monitor): quem faltou na chamada ou avisou que não vai já aparece marcado
create or replace function api.transporte_embarque(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  r iara.transporte_rotas;
  v_sentido text := coalesce(nullif(p ->> 'sentido', ''), 'IDA');
  v_hoje date := iara.hoje_local();
begin
  select * into r from iara.transporte_rotas where id = (p ->> 'rota_id')::uuid;
  if r.id is null or not iara.rota_acesso(r.id) then raise exception 'Rota não encontrada.' using errcode = 'P0002'; end if;
  return iara.rota_resumo(r) || jsonb_build_object('sentido', v_sentido, 'data', v_hoje, 'pode_registrar', iara.has_perm('transporte.manage'),
    'estado', iara.transporte_estado(r.id, v_sentido),
    'alunos', (select coalesce(jsonb_agg(jsonb_build_object('student_id', s.id, 'nome', s.full_name, 'turma', c.class_name, 'aee', s.aee_status,
        'ponto', pt.nome, 'ordem', pt.ordem, 'horario', case when v_sentido = 'IDA' then pt.horario_ida else pt.horario_volta end,
        'aviso', (select coalesce(av.motivo, 'Família avisou') from iara.transporte_avisos av where av.student_id = s.id and av.data = v_hoje and av.sentido in ('AMBOS', v_sentido)),
        'faltou', exists (select 1 from iara.frequencia_faltas f join iara.frequencia_registros fr on fr.id = f.registro_id where f.student_id = s.id and fr.data = v_hoje),
        'embarcou', (select em.embarcou from iara.transporte_embarques em where em.rota_id = r.id and em.data = v_hoje and em.sentido = v_sentido and em.student_id = s.id))
        order by case when v_sentido = 'IDA' then pt.ordem else -pt.ordem end, s.full_name), '[]')
      from iara.transporte_alunos a join iara.students s on s.id = a.student_id left join iara.transporte_pontos pt on pt.id = a.ponto_id
      left join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' left join iara.classes c on c.id = e.class_id
      where a.rota_id = r.id and a.fim is null));
end $$;

create or replace function api.transporte_embarque_registrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r iara.transporte_rotas;
  v_sentido text := coalesce(nullif(p ->> 'sentido', ''), 'IDA');
  v_n integer := 0;
  x record;
begin
  perform iara.require_perm('transporte.manage');
  select * into r from iara.transporte_rotas where id = (p ->> 'rota_id')::uuid;
  if r.id is null then raise exception 'Rota não encontrada.' using errcode = 'P0002'; end if;
  for x in select (value ->> 'student_id')::uuid sid, (value ->> 'embarcou')::boolean emb from jsonb_array_elements(coalesce(p -> 'registros', '[]')) loop
    if not exists (select 1 from iara.transporte_alunos where rota_id = r.id and student_id = x.sid and fim is null) then raise exception 'Há aluno que não é desta rota.' using errcode = '22023'; end if;
    insert into iara.transporte_embarques (rota_id, data, sentido, student_id, embarcou, registrado_por_label)
    values (r.id, iara.hoje_local(), v_sentido, x.sid, x.emb, iara.my_label())
    on conflict (rota_id, data, sentido, student_id) do update set embarcou = excluded.embarcou, registrado_em = now(), registrado_por_label = excluded.registrado_por_label;
    v_n := v_n + 1;
  end loop;
  perform iara.audit_event('TRANSPORTE_EMBARQUE', 'transporte_rota', r.id::text, r.unit_id, format('Lista de embarque (%s) registrada: %s aluno(s).', lower(v_sentido), v_n));
  return api.transporte_embarque(jsonb_build_object('rota_id', r.id, 'sentido', v_sentido));
end $$;

create or replace function api.transporte_ocorrencia_registrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r iara.transporte_rotas;
  v_tipo text := p ->> 'tipo';
  v_student uuid := nullif(p ->> 'student_id', '')::uuid;
  o iara.transporte_ocorrencias;
begin
  select * into r from iara.transporte_rotas where id = (p ->> 'rota_id')::uuid;
  if r.id is null or not iara.rota_acesso(r.id) then raise exception 'Rota não encontrada.' using errcode = 'P0002'; end if;
  if v_tipo not in ('ATRASO', 'QUEBRA', 'SUBSTITUICAO', 'ROTA_NAO_EXECUTADA', 'ACIDENTE', 'ALUNO_NAO_EMBARCOU', 'COMPORTAMENTO', 'OUTRO') then raise exception 'Tipo inválido.' using errcode = '22023'; end if;
  if length(btrim(coalesce(p ->> 'descricao', ''))) < 10 then raise exception 'Descreva o que aconteceu (pelo menos 10 caracteres).' using errcode = '22023'; end if;
  if v_student is not null and not exists (select 1 from iara.transporte_alunos where rota_id = r.id and student_id = v_student) then raise exception 'Aluno não é desta rota.' using errcode = '22023'; end if;
  insert into iara.transporte_ocorrencias (rota_id, data, sentido, tipo, student_id, descricao, providencia, registrada_por_label, is_demo)
  values (r.id, coalesce(nullif(p ->> 'data', '')::date, iara.hoje_local()), nullif(p ->> 'sentido', ''), v_tipo, v_student, btrim(p ->> 'descricao'),
          nullif(btrim(coalesce(p ->> 'providencia', '')), ''), iara.my_label(), false) returning * into o;
  if v_student is not null and v_tipo in ('ALUNO_NAO_EMBARCOU', 'ACIDENTE', 'COMPORTAMENTO') then
    perform iara.avisar_familia(v_student, 'TRANSPORTE_OCORRENCIA', 'Ocorrência no transporte escolar', 'Houve um registro no transporte da criança: ' || left(btrim(p ->> 'descricao'), 200));
    update iara.transporte_ocorrencias set familias_avisadas = true where id = o.id;
  end if;
  perform iara.audit_event('TRANSPORTE_OCORRENCIA', 'transporte_rota', r.id::text, r.unit_id, 'Ocorrência de transporte: ' || lower(v_tipo) || '.');
  return jsonb_build_object('ok', true, 'id', o.id);
end $$;

create or replace function api.transporte_ocorrencia_resolver(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  o iara.transporte_ocorrencias;
begin
  perform iara.require_perm('transporte.manage');
  if length(btrim(coalesce(p ->> 'providencia', ''))) < 10 then raise exception 'Registre a providência.' using errcode = '22023'; end if;
  update iara.transporte_ocorrencias set situacao = 'RESOLVIDA', resolvida_em = now(), providencia = btrim(p ->> 'providencia')
  where id = (p ->> 'id')::uuid and situacao = 'ABERTA' returning * into o;
  if o.id is null then raise exception 'Ocorrência não encontrada ou já resolvida.' using errcode = 'P0002'; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function api.transporte_ocorrencias(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
begin
  perform iara.require_perm('transporte.read');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'data', o.data, 'sentido', o.sentido, 'tipo', o.tipo, 'descricao', o.descricao, 'providencia', o.providencia,
      'situacao', o.situacao, 'rota_id', r.id, 'rota', r.codigo, 'unidade', u.short_name, 'aluno', (select full_name from iara.students where id = o.student_id),
      'familias_avisadas', o.familias_avisadas, 'is_demo', o.is_demo) order by o.situacao = 'ABERTA' desc, o.data desc, o.created_at desc), '[]')
    from (select o2.* from iara.transporte_ocorrencias o2 join iara.transporte_rotas r2 on r2.id = o2.rota_id
          where (v_unit is null or r2.unit_id = v_unit) and iara.can_access_unit(r2.unit_id)
            and (nullif(p ->> 'situacao', '') is null or o2.situacao = p ->> 'situacao')
          order by o2.situacao = 'ABERTA' desc, o2.data desc limit 200) o
    join iara.transporte_rotas r on r.id = o.rota_id join iara.education_units u on u.id = r.unit_id);
end $$;

-- 5. Família ----------------------------------------------------------------------------------------------------------------------
create or replace function api.familia_transporte(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_hoje date := iara.hoje_local();
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(x.j order by x.nome), '[]') from (
    select s.full_name nome, jsonb_build_object('student_id', s.id, 'primeiro_nome', split_part(s.full_name, ' ', 1),
      'transporte_pedido', s.transport_need, 'situacao', s.school_transport_status,
      'rota', case when a.id is not null then jsonb_build_object('id', r.id, 'codigo', r.codigo, 'nome', r.nome, 'turno', r.turno, 'escola', u.short_name,
          'escola_lat', u.lat, 'escola_lng', u.lng, 'chegada_escola', r.chegada_ida, 'saida_escola', r.saida_volta,
          'veiculo', (select jsonb_build_object('tipo', v.tipo, 'placa', v.placa, 'acessivel', v.acessivel) from iara.transporte_veiculos v where v.id = r.veiculo_id),
          'motorista', (select split_part(m.nome, ' ', 1) from iara.transporte_motoristas m where m.id = r.motorista_id),
          'monitor', split_part(r.monitor_nome, ' ', 1),
          'meu_ponto', (select jsonb_build_object('nome', pt.nome, 'lat', pt.lat, 'lng', pt.lng, 'horario_ida', pt.horario_ida, 'horario_volta', pt.horario_volta)
                        from iara.transporte_pontos pt where pt.id = a.ponto_id),
          'hoje', jsonb_build_object('ida', iara.transporte_estado(r.id, 'IDA'), 'volta', iara.transporte_estado(r.id, 'VOLTA')),
          'avisos', (select coalesce(jsonb_agg(jsonb_build_object('data', av.data, 'sentido', av.sentido, 'motivo', av.motivo) order by av.data), '[]')
                     from iara.transporte_avisos av where av.student_id = s.id and av.data >= v_hoje),
          'recentes', (select coalesce(jsonb_agg(jsonb_build_object('data', o.data, 'sentido', o.sentido, 'tipo', o.tipo, 'descricao', o.descricao, 'providencia', o.providencia)
                         order by o.data desc), '[]')
                       from (select * from iara.transporte_ocorrencias o2 where o2.rota_id = r.id and o2.data >= v_hoje - 15
                               and (o2.tipo in ('ATRASO', 'QUEBRA', 'SUBSTITUICAO', 'ROTA_NAO_EXECUTADA') or o2.student_id = s.id)
                             order by o2.data desc limit 5) o)) end) j
    from iara.students s
    left join iara.transporte_alunos a on a.student_id = s.id and a.fim is null
    left join iara.transporte_rotas r on r.id = a.rota_id left join iara.education_units u on u.id = r.unit_id
    where s.id in (select iara.my_student_ids()) and (a.id is not null or s.transport_need)) x);
end $$;

create or replace function api.familia_transporte_avisar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_data date := coalesce(nullif(p ->> 'data', '')::date, iara.hoje_local());
  v_sentido text := coalesce(nullif(p ->> 'sentido', ''), 'AMBOS');
begin
  if iara.my_guardian() is null or v_student not in (select iara.my_student_ids()) then raise exception 'Criança fora do seu cadastro.' using errcode = '42501'; end if;
  if not exists (select 1 from iara.transporte_alunos where student_id = v_student and fim is null) then raise exception 'A criança não usa o transporte escolar.' using errcode = '22023'; end if;
  if v_data < iara.hoje_local() or v_data > iara.hoje_local() + 30 then raise exception 'Escolha uma data de hoje até 30 dias.' using errcode = '22023'; end if;
  if v_sentido not in ('IDA', 'VOLTA', 'AMBOS') then raise exception 'Sentido inválido.' using errcode = '22023'; end if;
  insert into iara.transporte_avisos (student_id, data, sentido, motivo, enviado_por_guardian, canal)
  values (v_student, v_data, v_sentido, nullif(btrim(coalesce(p ->> 'motivo', '')), ''), iara.my_guardian(), coalesce(nullif(p ->> 'canal', ''), 'PORTAL'))
  on conflict (student_id, data) do update set sentido = excluded.sentido, motivo = excluded.motivo, created_at = now();
  return jsonb_build_object('ok', true, 'mensagem', format('Aviso registrado: a criança não vai usar o transporte em %s (%s). O monitor vê na lista de embarque.',
    to_char(v_data, 'DD/MM'), case v_sentido when 'IDA' then 'ida' when 'VOLTA' then 'volta' else 'ida e volta' end));
end $$;

-- 6. Demonstração -------------------------------------------------------------------------------------------------------------------
-- rotas por escola e turno a partir dos endereços dos alunos que precisam de transporte (até 26 por rota, por setor),
-- pontos agrupados por quadra (~400 m), ordem pelo vizinho mais próximo partindo do mais distante, horários de trás para frente
drop function if exists iara.demo_gerar_transporte();
create or replace function iara.demo_gerar_transporte() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ana uuid := nullif(iara.setting('demo_student_ana'), '')::uuid;
  rr record;
  v_rota uuid;
  v_seq integer := 0;
  v_ids uuid[];
  v_lat double precision[];
  v_lng double precision[];
  v_nome text[];
  v_ord integer[];
  v_used boolean[];
  v_n integer;
  v_cur integer;
  v_best integer;
  v_bd double precision;
  d double precision;
  i integer;
  k integer;
  v_t time;
  v_tv time;
  v_km double precision;
  v_veic uuid;
  v_mot uuid;
  v_key text;
  v_g integer;
  v_cnt integer;
  v_a0 double precision;
  nomes text[] := array['Adriano', 'Aparecida', 'Carlos', 'Cleusa', 'Edson', 'Elaine', 'Gilmar', 'Ivone', 'Jair', 'Joana', 'Luiz', 'Márcia', 'Nelson', 'Odete',
                        'Paulo', 'Rosângela', 'Sérgio', 'Sônia', 'Valdir', 'Vera', 'Wilson', 'Zilda', 'Roberto', 'Neusa'];
  sobren text[] := array['Alves', 'Barbosa', 'Cardoso', 'Dias', 'Ferreira', 'Gomes', 'Lima', 'Martins', 'Nogueira', 'Oliveira', 'Pereira', 'Ribeiro', 'Santos', 'Souza', 'Teixeira', 'Vieira'];
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.transporte_abonos where is_demo;
  delete from iara.transporte_ocorrencias where is_demo;
  delete from iara.transporte_viagens where is_demo;
  delete from iara.transporte_alunos where is_demo;
  delete from iara.transporte_rotas where is_demo;
  delete from iara.transporte_veiculos where is_demo;
  delete from iara.transporte_motoristas where is_demo;
  if v_ana is not null then update iara.students set transport_need = true where id = v_ana; end if;

  create temp table tmp_tr on commit drop as
  select s.id student_id, e.unit_id, c.shift, s.aee_status, extensions.st_y(a.location::extensions.geometry) lat, extensions.st_x(a.location::extensions.geometry) lng, coalesce(a.street, 'Rua sem nome') street,
         u.lat ulat, u.lng ulng, atan2(extensions.st_y(a.location::extensions.geometry) - u.lat, extensions.st_x(a.location::extensions.geometry) - u.lng) ang,
         abs(hashtext(s.id::text || 'tr')) % 100 h
  from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' join iara.classes c on c.id = e.class_id
  join iara.education_units u on u.id = e.unit_id join iara.addresses a on a.id = s.address_id
  where s.transport_need and a.location is not null and c.shift in ('MANHA', 'TARDE', 'NOITE');
  -- cerca de 7% aguardando rota (a lista “sem rota” da gerência), nunca a Ana
  delete from tmp_tr where h >= 93 and student_id is distinct from v_ana;
  alter table tmp_tr add column grupo integer;
  -- agrupamento: varredura pelo ângulo em volta da escola; nova rota a cada 14 alunos ou quando o leque passa de 150°
  -- (evita um veículo dando a volta inteira na escola)
  v_key := ''; v_g := 0;
  for rr in select student_id, unit_id || ':' || shift k, ang from tmp_tr order by unit_id, shift, ang loop
    if rr.k <> v_key then v_key := rr.k; v_a0 := rr.ang; v_cnt := 0; v_g := 0;
    elsif v_cnt >= 14 or rr.ang - v_a0 > radians(150) then v_a0 := rr.ang; v_cnt := 0; v_g := v_g + 1; end if;
    v_cnt := v_cnt + 1;
    update tmp_tr set grupo = v_g where student_id = rr.student_id;
  end loop;

  for rr in select unit_id, shift, grupo, min(ulat) ulat, min(ulng) ulng, count(*) n,
                   bool_or(exists (select 1 from iara.student_sensitive ss where ss.student_id = t.student_id and ss.special_education_need ilike '%física%')) cadeirante,
                   bool_or(aee_status) aee
            from tmp_tr t group by 1, 2, 3 order by 1, 2, 3 loop
    v_seq := v_seq + 1;
    -- veículo e motorista da rota
    insert into iara.transporte_veiculos (placa, tipo, capacidade, acessivel, ano, operador, situacao, vistoria_validade, is_demo)
    values ('DMO' || (v_seq % 10)::text || chr(65 + (v_seq * 7) % 26) || lpad(((v_seq * 37) % 100)::text, 2, '0'),
            case when rr.n <= 13 then 'VAN' when rr.n <= 22 then 'MICRO' else 'ONIBUS' end,
            case when rr.n <= 13 then 15 when rr.n <= 22 then 25 else 44 end,
            rr.cadeirante or v_seq % 3 = 0, 2015 + v_seq % 10, case when v_seq % 3 = 0 then 'Frota própria (SEDUC)' else 'Transportadora Exemplo Ltda. (demonstração)' end,
            'ATIVO', case when v_seq % 29 = 0 then current_date - 12 when v_seq % 17 = 0 then current_date + 18 else date '2027-03-31' - (v_seq % 60) end, true)
    returning id into v_veic;
    insert into iara.transporte_motoristas (nome, cnh_categoria, cnh_validade, curso_validade, operador, situacao, is_demo)
    values (nomes[1 + v_seq % 24] || ' ' || sobren[1 + (v_seq * 5) % 16] || ' ' || sobren[1 + (v_seq * 11) % 16], 'D',
            case when v_seq % 31 = 0 then current_date - 5 else date '2028-06-30' + (v_seq * 13) % 700 end,
            case when v_seq % 23 = 0 then current_date + 20 else date '2027-11-30' + (v_seq * 7) % 500 end,
            case when v_seq % 3 = 0 then 'Frota própria (SEDUC)' else 'Transportadora Exemplo Ltda. (demonstração)' end, 'ATIVO', true)
    returning id into v_mot;
    insert into iara.transporte_rotas (codigo, nome, unit_id, turno, veiculo_id, motorista_id, monitor_nome, chegada_ida, saida_volta, situacao, is_demo)
    values ('R-' || lpad(v_seq::text, 3, '0'), '', rr.unit_id, rr.shift, v_veic, v_mot,
            case when rr.aee or exists (select 1 from tmp_tr t join iara.enrollments e on e.student_id = t.student_id and e.status = 'ACTIVE'
                                         join iara.classes c on c.id = e.class_id join iara.grade_levels g on g.id = c.grade_level_id
                                         where t.unit_id = rr.unit_id and t.shift = rr.shift and t.grupo = rr.grupo and g.code in ('CRECHE', 'PRE'))
                 then nomes[1 + (v_seq * 3) % 24] || ' ' || sobren[1 + (v_seq * 9) % 16] end,
            case rr.shift when 'MANHA' then time '07:15' when 'TARDE' then time '12:45' else time '18:45' end,
            case rr.shift when 'MANHA' then time '11:35' when 'TARDE' then time '17:35' else time '22:05' end, 'ATIVA', true)
    returning id into v_rota;
    -- pontos: centro de cada quadra (~400 m)
    select array_agg(q.lat order by q.k), array_agg(q.lng order by q.k), array_agg(q.street order by q.k), count(*)
    into v_lat, v_lng, v_nome, v_n
    from (select round(lat / 0.004)::text || ':' || round(lng / 0.004)::text k, avg(lat) lat, avg(lng) lng, min(street) street
          from tmp_tr where unit_id = rr.unit_id and shift = rr.shift and grupo = rr.grupo group by 1) q;
    -- ordem: começa no mais distante da escola e segue o vizinho mais próximo
    v_used := array_fill(false, array[v_n]);
    v_ord := '{}';
    v_cur := 1; v_bd := -1;
    for i in 1..v_n loop
      d := iara.km_entre(v_lat[i], v_lng[i], rr.ulat, rr.ulng);
      if d > v_bd then v_bd := d; v_cur := i; end if;
    end loop;
    for k in 1..v_n loop
      v_ord := v_ord || v_cur; v_used[v_cur] := true;
      v_best := null; v_bd := 1e9;
      for i in 1..v_n loop
        if not v_used[i] then
          d := iara.km_entre(v_lat[v_cur], v_lng[v_cur], v_lat[i], v_lng[i]);
          if d < v_bd then v_bd := d; v_best := i; end if;
        end if;
      end loop;
      exit when v_best is null;
      v_cur := v_best;
    end loop;
    -- horários: de trás para frente a partir da chegada (22 km/h, fator 1,35 de ruas, 1,5 min por parada)
    v_km := iara.km_entre(v_lat[v_ord[v_n]], v_lng[v_ord[v_n]], rr.ulat, rr.ulng) * 1.35;
    v_t := (select chegada_ida from iara.transporte_rotas where id = v_rota) - make_interval(secs => round(v_km / 22 * 3600 + 90)::int);
    v_tv := (select saida_volta from iara.transporte_rotas where id = v_rota) + make_interval(secs => round(v_km / 22 * 3600 + 90)::int);
    for k in reverse v_n..1 loop
      insert into iara.transporte_pontos (rota_id, ordem, nome, lat, lng, horario_ida, horario_volta, is_demo)
      values (v_rota, k, v_nome[v_ord[k]] || ' (ponto ' || k || ')', v_lat[v_ord[k]], v_lng[v_ord[k]], date_trunc('minute', v_t)::time, date_trunc('minute', v_tv)::time, true);
      if k > 1 then
        d := iara.km_entre(v_lat[v_ord[k - 1]], v_lng[v_ord[k - 1]], v_lat[v_ord[k]], v_lng[v_ord[k]]) * 1.35;
        v_km := v_km + d;
        v_t := v_t - make_interval(secs => round(d / 22 * 3600 + 90)::int);
        v_tv := v_tv + make_interval(secs => round(d / 22 * 3600 + 90)::int);
      end if;
    end loop;
    update iara.transporte_rotas set km = round(v_km::numeric, 1),
           nome = (select short_name from iara.education_units where id = rr.unit_id) || ' · ' || lower(case rr.shift when 'MANHA' then 'manhã' else rr.shift end)
                  || case when (select count(*) from tmp_tr where unit_id = rr.unit_id and shift = rr.shift) > 26 then ' · setor ' || (rr.grupo + 1) else '' end
    where id = v_rota;
    -- alunos no ponto mais próximo
    insert into iara.transporte_alunos (student_id, rota_id, ponto_id, motivo, observacao, inicio, incluido_por_label, is_demo)
    select t.student_id, v_rota,
           (select p.id from iara.transporte_pontos p where p.rota_id = v_rota order by iara.km_entre(t.lat, t.lng, p.lat, p.lng) limit 1),
           case when t.student_id = v_ana then 'OUTRO' when t.aee_status and t.h % 3 = 0 then 'DEFICIENCIA'
                when iara.km_entre(t.lat, t.lng, t.ulat, t.ulng) > 2 then 'DISTANCIA' when t.h % 5 = 0 then 'ZONA_RURAL' else 'DISTANCIA' end,
           case when t.student_id = v_ana then 'Cenário da demonstração (família da Maria).' end,
           date '2026-02-09' + (t.h % 20), 'Gerência de Transporte (demonstração)', true
    from tmp_tr t where t.unit_id = rr.unit_id and t.shift = rr.shift and t.grupo = rr.grupo;
  end loop;
  update iara.students s set school_transport_status = case when exists (select 1 from iara.transporte_alunos a where a.student_id = s.id and a.fim is null) then 'ATENDIDO' else 'AGUARDANDO' end
  where s.transport_need;

  -- reserva: veículos e motoristas sem rota fixa
  insert into iara.transporte_veiculos (placa, tipo, capacidade, acessivel, ano, operador, situacao, vistoria_validade, is_demo)
  select 'DMO' || (90 + g)::text || 'R', case when g % 2 = 0 then 'MICRO' else 'ONIBUS' end, case when g % 2 = 0 then 25 else 44 end, g % 2 = 0, 2020 + g % 5,
         'Frota própria (SEDUC)', case when g = 7 then 'MANUTENCAO' else 'RESERVA' end, date '2027-02-28', true
  from generate_series(1, 8) g;
  insert into iara.transporte_motoristas (nome, cnh_validade, curso_validade, operador, situacao, is_demo)
  select nomes[1 + (g * 7) % 24] || ' ' || sobren[1 + (g * 3) % 16] || ' ' || sobren[1 + (g * 13) % 16], date '2029-01-31', date '2028-05-31', 'Frota própria (SEDUC)', 'RESERVA', true
  from generate_series(1, 6) g;

  perform iara.demo_gerar_viagens((iara.setting('ano_letivo_inicio'))::date + 0, iara.hoje_local() - 1);
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('rotas', (select count(*) from iara.transporte_rotas where is_demo), 'pontos', (select count(*) from iara.transporte_pontos where is_demo),
    'alunos', (select count(*) from iara.transporte_alunos where is_demo and fim is null), 'veiculos', (select count(*) from iara.transporte_veiculos where is_demo),
    'viagens', (select count(*) from iara.transporte_viagens where is_demo), 'ocorrencias', (select count(*) from iara.transporte_ocorrencias where is_demo),
    'sem_rota', (select count(*) from iara.students where transport_need and school_transport_status = 'AGUARDANDO'));
end $$;

-- execução diária fictícia (ida e volta): quase sempre no horário; às vezes atraso, troca de veículo ou viagem não realizada
create or replace function iara.demo_gerar_viagens(p_de date, p_ate date) returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  create temp table tmp_vg on commit drop as
  select r.id rota_id, r.unit_id, r.codigo, r.veiculo_id, r.motorista_id, d::date data, s.sentido,
         abs(hashtext(r.id::text || d::date::text || s.sentido)) % 1000 h,
         (select count(*) from iara.transporte_alunos a where a.rota_id = r.id and a.inicio <= d::date and (a.fim is null or a.fim > d::date)) previstos
  from iara.transporte_rotas r cross join generate_series(greatest(p_de, (iara.setting('ano_letivo_inicio'))::date), p_ate, interval '1 day') d
  cross join (values ('IDA'), ('VOLTA')) s(sentido)
  where r.is_demo and r.situacao = 'ATIVA' and iara.dia_letivo(d::date, r.unit_id)
    and not exists (select 1 from iara.transporte_viagens v where v.rota_id = r.id and v.data = d::date and v.sentido = s.sentido);
  insert into iara.transporte_viagens (rota_id, data, sentido, situacao, atraso_min, motivo, veiculo_id, motorista_id, substituicao, alunos_previstos,
                                       alunos_transportados, registrado_por_label, registrado_em, is_demo)
  select t.rota_id, t.data, t.sentido, case when t.h < 5 then 'NAO_REALIZADA' else 'CONCLUIDA' end,
         case when t.h < 5 then 0 when t.h < 14 then 15 + t.h % 20 when t.h < 60 then 10 + t.h % 21 else t.h % 6 end,
         case when t.h < 5 then (array['Pane mecânica sem veículo reserva disponível a tempo', 'Motorista afastado sem substituto', 'Estrada rural interditada pela chuva'])[1 + t.h % 3]
              when t.h < 14 then 'Pane no veículo da rota; seguiu com o veículo reserva'
              when t.h < 60 then (array['Trânsito intenso', 'Chuva forte', 'Obra na via', 'Aluno atrasado no ponto'])[1 + t.h % 4] end,
         case when t.h between 5 and 13 then (select id from iara.transporte_veiculos where is_demo and situacao = 'RESERVA' order by placa offset (t.h % 6) limit 1) else t.veiculo_id end,
         t.motorista_id, t.h between 5 and 13, t.previstos,
         case when t.h < 5 then 0 else greatest(t.previstos - (select count(*) from iara.transporte_alunos a join iara.frequencia_faltas f on f.student_id = a.student_id
                                                     join iara.frequencia_registros fr on fr.id = f.registro_id and fr.data = t.data
                                                     where a.rota_id = t.rota_id and a.fim is null), 0) end,
         'Monitor da rota (demonstração)', t.data + case when t.sentido = 'IDA' then interval '8 hours' else interval '18 hours' end, true
  from tmp_vg t;
  get diagnostics v_n = row_count;
  -- ocorrências das viagens com problema
  insert into iara.transporte_ocorrencias (rota_id, data, sentido, tipo, descricao, providencia, familias_avisadas, situacao, registrada_por_label, created_at, resolvida_em, is_demo)
  select t.rota_id, t.data, t.sentido, case when t.h < 5 then 'ROTA_NAO_EXECUTADA' when t.h < 14 then 'SUBSTITUICAO' else 'ATRASO' end,
         case when t.h < 5 then (array['Pane mecânica sem veículo reserva disponível a tempo', 'Motorista afastado sem substituto', 'Estrada rural interditada pela chuva'])[1 + t.h % 3]
              when t.h < 14 then 'Pane no veículo da rota antes da saída' else 'Atraso de ' || (15 + t.h % 20) || ' min: trânsito e chuva' end,
         case when t.h < 5 then 'Famílias avisadas pela IARA; falta abonada; escola informada; veículo encaminhado à oficina.'
              when t.h < 14 then 'Veículo reserva enviado; famílias avisadas do atraso.' else 'Famílias avisadas pela IARA.' end,
         true, 'RESOLVIDA', 'Gerência de Transporte (demonstração)', t.data + interval '9 hours', t.data + interval '15 hours', true
  from tmp_vg t where t.h < 30;
  -- falta abonada quando a ida não aconteceu
  insert into iara.transporte_abonos (student_id, data, rota_id, motivo, is_demo)
  select a.student_id, t.data, t.rota_id, 'Transporte escolar não realizado (rota ' || t.codigo || ')', true
  from tmp_vg t join iara.transporte_alunos a on a.rota_id = t.rota_id and a.fim is null
  where t.h < 5 and t.sentido = 'IDA'
  on conflict do nothing;
  update iara.frequencia_faltas f set tipo = 'FALTA_JUSTIFICADA', justificativa = ab.motivo
  from iara.transporte_abonos ab, iara.frequencia_registros fr
  where fr.id = f.registro_id and ab.student_id = f.student_id and ab.data = fr.data and f.tipo = 'FALTA' and ab.data between p_de and p_ate;
  perform set_config('iara.skip_audit', 'off', true);
  return v_n;
end $$;

revoke all on function iara.demo_gerar_transporte(), iara.demo_gerar_viagens(date, date), iara.falta_abono_transporte() from public;

-- 7. Classificação --------------------------------------------------------------------------------------------------------------
insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('transporte_pontos', 'nome', 'PESSOAL', 'localização aproximada', 'ponto de embarque', 'gerência e unidade; família vê só o próprio ponto'),
  ('transporte_pontos', 'lat', 'PESSOAL', 'localização aproximada', 'ponto de embarque', 'gerência e unidade; família vê só o próprio ponto'),
  ('transporte_pontos', 'lng', 'PESSOAL', 'localização aproximada', 'ponto de embarque', 'gerência e unidade; família vê só o próprio ponto'),
  ('transporte_alunos', 'observacao', 'PESSOAL', 'serviço', 'transporte escolar', 'gerência e unidade'),
  ('transporte_alunos', 'incluido_por_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('transporte_motoristas', 'nome', 'PESSOAL', 'identificação de servidor/terceirizado', 'operação do transporte', 'família vê só o primeiro nome'),
  ('transporte_rotas', 'monitor_nome', 'PESSOAL', 'identificação de servidor/terceirizado', 'operação do transporte', 'família vê só o primeiro nome'),
  ('transporte_ocorrencias', 'descricao', 'PESSOAL', 'ocorrência', 'acompanhamento do transporte', 'gerência e unidade; família só as da rota (gerais) e as do filho'),
  ('transporte_ocorrencias', 'providencia', 'PESSOAL', 'ocorrência', 'acompanhamento do transporte', 'gerência e unidade'),
  ('transporte_ocorrencias', 'registrada_por_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('transporte_avisos', 'motivo', 'PESSOAL', 'texto livre', 'aviso da família', 'gerência, unidade e família'),
  ('transporte_viagens', 'motivo', 'INTERNO', 'operação', 'execução da viagem', null),
  ('transporte_viagens', 'registrado_por_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('transporte_embarques', 'registrado_por_label', 'PESSOAL', 'identificação', 'auditoria', null),
  ('transporte_abonos', 'motivo', 'INTERNO', 'operação', 'abono de falta', null)
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

commit;
