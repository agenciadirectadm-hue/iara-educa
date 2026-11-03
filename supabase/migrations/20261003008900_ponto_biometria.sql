-- IARA Educa — 089 · Ponto dos profissionais com a biometria do próprio aparelho (WebAuthn / FIDO2)
-- O(a) profissional cadastra a biometria do celular ou do computador (digital, rosto ou o bloqueio de tela) e bate o ponto
-- com ela. A biometria nunca sai do aparelho: o IARA guarda só a chave pública da credencial, e o gateway confere a
-- assinatura de cada marcação contra um desafio de uso único (5 min). A marcação leva o local quando o aparelho permite:
-- longe da unidade ela fica sinalizada, não bloqueada. Espelho do mês, justificativas, painel da direção (presença do dia,
-- abonos, ajustes manuais auditados) e fechamento do mês.
-- As funções iara.ponto_gateway_* só rodam pelo gateway (como sistema), depois da verificação da biometria: o navegador não
-- as alcança, e api.* não tem como marcar ponto sem ela.
-- LGPD: nenhum dado biométrico passa pelo IARA; a localização é usada só para a distância até a unidade na marcação.
-- Demonstração: marcações fictícias da rede desde o mês passado, completadas aos poucos até o momento atual.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

insert into iara.permissions (code, description, is_sensitive) values
  ('ponto.registrar', 'Bater o próprio ponto com a biometria do aparelho e ver o próprio espelho', false),
  ('ponto.gerir', 'Acompanhar o ponto da equipe: presença do dia, justificativas, ajustes e fechamento do mês', true)
on conflict (code) do update set description = excluded.description;
insert into iara.role_permissions (role_code, permission_code) values
  ('PROFESSOR', 'ponto.registrar'), ('PROFESSOR_AEE', 'ponto.registrar'),
  ('DIRETOR_UNIDADE', 'ponto.gerir'), ('SECRETARIA_ESCOLAR', 'ponto.gerir'), ('SECRETARIO', 'ponto.gerir'), ('SUPERINTENDENCIA', 'ponto.gerir')
on conflict do nothing;

update iara.tenants set settings = settings || jsonb_build_object('ponto_raio_m', 300, 'ponto_tolerancia_min', 10)
where id = 1 and not settings ? 'ponto_raio_m';

-- 1. Tabelas -----------------------------------------------------------------------------------------------------------------------
create table if not exists iara.ponto_credenciais (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references iara.staff(id) on delete cascade,
  credencial text not null unique,          -- id da credencial WebAuthn (base64url)
  chave_publica text not null,              -- chave pública COSE (base64url); a biometria fica no aparelho
  contador bigint not null default 0,
  transportes text[] not null default '{}',
  rp_id text not null,                      -- domínio do cadastro: a credencial só vale nele
  aparelho text,
  criada_em timestamptz not null default now(),
  ultimo_uso_em timestamptz,
  revogada_em timestamptz,
  is_demo boolean not null default true
);
create index if not exists ponto_credenciais_staff_idx on iara.ponto_credenciais (staff_id) where revogada_em is null;

create table if not exists iara.ponto_desafios (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references iara.app_users(id) on delete cascade,
  staff_id uuid not null references iara.staff(id) on delete cascade,
  tipo text not null check (tipo in ('CADASTRO', 'MARCACAO')),
  desafio text not null,
  rp_id text not null,
  criado_em timestamptz not null default now(),
  expira_em timestamptz not null default now() + interval '5 minutes',
  usado_em timestamptz
);
create index if not exists ponto_desafios_user_idx on iara.ponto_desafios (user_id, tipo, criado_em desc);

create table if not exists iara.ponto_marcacoes (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references iara.staff(id) on delete cascade,
  unit_id integer references iara.education_units(id),
  marcada_em timestamptz not null default now(),
  data date not null,                        -- dia em Maringá
  tipo text not null check (tipo in ('ENTRADA', 'SAIDA')),
  metodo text not null check (metodo in ('BIOMETRIA_APARELHO', 'AJUSTE_DIRECAO')),
  credencial_id uuid references iara.ponto_credenciais(id) on delete set null,
  lat double precision,
  lng double precision,
  precisao_m integer,
  distancia_m integer,
  fora_da_unidade boolean not null default false,
  motivo text,
  registrada_por_label text,
  is_demo boolean not null default true
);
create unique index if not exists ponto_marcacoes_unica on iara.ponto_marcacoes (staff_id, marcada_em);
create index if not exists ponto_marcacoes_staff_dia_idx on iara.ponto_marcacoes (staff_id, data);
create index if not exists ponto_marcacoes_unit_dia_idx on iara.ponto_marcacoes (unit_id, data);

create table if not exists iara.ponto_justificativas (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references iara.staff(id) on delete cascade,
  unit_id integer references iara.education_units(id),
  data date not null,
  tipo text not null check (tipo in ('ESQUECIMENTO', 'ATESTADO', 'SERVICO_EXTERNO', 'FORMACAO', 'OUTRO')),
  descricao text not null,
  situacao text not null default 'PENDENTE' check (situacao in ('PENDENTE', 'ABONADA', 'RECUSADA')),
  enviada_em timestamptz not null default now(),
  tratada_por_label text,
  tratada_em timestamptz,
  observacao text,
  is_demo boolean not null default true,
  unique (staff_id, data)
);
create index if not exists ponto_justificativas_unit_idx on iara.ponto_justificativas (unit_id, situacao);

create table if not exists iara.ponto_fechamentos (
  unit_id integer not null references iara.education_units(id) on delete cascade,
  mes date not null,                         -- primeiro dia do mês
  fechado_por_label text not null,
  fechado_em timestamptz not null default now(),
  resumo jsonb not null default '{}'::jsonb,
  primary key (unit_id, mes)
);

create table if not exists iara.ponto_demo_estado (
  id smallint primary key default 1 check (id = 1),
  ultimo_dia date,
  atualizado_em timestamptz
);

alter table iara.ponto_credenciais enable row level security;
alter table iara.ponto_desafios enable row level security;
alter table iara.ponto_marcacoes enable row level security;
alter table iara.ponto_justificativas enable row level security;
alter table iara.ponto_fechamentos enable row level security;
alter table iara.ponto_demo_estado enable row level security;

-- 2. Regras -------------------------------------------------------------------------------------------------------------------------
-- dia de trabalho: segunda a sexta, menos feriados da rede (o recesso escolar é dia de trabalho)
create or replace function iara.ponto_dia_util(p_dia date) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select extract(isodow from p_dia) between 1 and 5
     and not exists (select 1 from iara.calendario_eventos e where e.tipo = 'FERIADO' and e.abrangencia = 'REDE' and p_dia between e.inicio and e.fim)
$$;

-- jornada prevista (proposta a validar com a SEDUC): 40 h ou turma integral → manhã e tarde; menos que isso → um turno,
-- o da turma do(a) profissional (manhã se não houver turma), com carga semanal ÷ 5 por dia
create or replace function iara.ponto_jornada(p_staff uuid) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_carga integer;
  v_turno text;
  v_ini time;
  v_min integer;
begin
  select coalesce(carga_horaria_semanal, 20) into v_carga from iara.staff where id = p_staff;
  select c.shift into v_turno from iara.class_staff cs join iara.classes c on c.id = cs.class_id
  where cs.staff_id = p_staff and cs.end_date is null order by cs.is_primary desc, c.shift limit 1;
  if coalesce(v_carga, 20) >= 40 or v_turno = 'INTEGRAL' then
    return '{"periodos": [["07:30", "11:30"], ["13:00", "17:00"]], "minutos": 480}'::jsonb;
  end if;
  v_ini := case when v_turno = 'TARDE' then time '13:00' else time '07:30' end;
  v_min := least(greatest(coalesce(v_carga, 20), 10), 39) * 12;
  return jsonb_build_object('periodos', jsonb_build_array(jsonb_build_array(to_char(v_ini, 'HH24:MI'), to_char(v_ini + make_interval(mins => v_min), 'HH24:MI'))),
                            'minutos', v_min);
end $$;

create or replace function iara.ponto_mes_fechado(p_unit integer, p_dia date) returns boolean
language sql stable security definer set search_path = iara, public
as $$ select exists (select 1 from iara.ponto_fechamentos where unit_id = p_unit and mes = date_trunc('month', p_dia)::date) $$;

-- o dia de um(a) profissional: marcações, minutos trabalhados (pares entrada → saída), atraso na primeira entrada, situação
create or replace function iara.ponto_dia(p_staff uuid, p_dia date, p_jornada jsonb default null) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  j jsonb := coalesce(p_jornada, iara.ponto_jornada(p_staff));
  v_hoje date := iara.hoje_local();
  v_util boolean := iara.ponto_dia_util(p_dia);
  v_tol integer := coalesce(nullif(iara.setting('ponto_tolerancia_min'), '')::int, 10);
  v_prev timestamptz := (p_dia + (j -> 'periodos' -> 0 ->> 0)::time) at time zone 'America/Sao_Paulo';
  v_n integer := 0;
  v_min integer := 0;
  v_ini timestamptz;
  v_atraso integer;
  v_fora boolean := false;
  v_marcas jsonb := '[]';
  m record;
  v_jid uuid; v_jtipo text; v_jdesc text; v_jsit text; v_jobs text;
  v_sit text;
begin
  for m in select * from iara.ponto_marcacoes where staff_id = p_staff and data = p_dia order by marcada_em loop
    v_n := v_n + 1;
    if v_n = 1 then v_atraso := greatest(0, floor(extract(epoch from m.marcada_em - v_prev) / 60))::int; end if;
    if m.tipo = 'ENTRADA' then
      v_ini := m.marcada_em;
    elsif v_ini is not null then
      v_min := v_min + floor(extract(epoch from m.marcada_em - v_ini) / 60)::int;
      v_ini := null;
    end if;
    v_fora := v_fora or m.fora_da_unidade;
    v_marcas := v_marcas || jsonb_build_object('id', m.id, 'hora', to_char(m.marcada_em at time zone 'America/Sao_Paulo', 'HH24:MI'), 'tipo', m.tipo,
      'metodo', m.metodo, 'fora', m.fora_da_unidade, 'distancia_m', m.distancia_m, 'motivo', m.motivo);
  end loop;
  -- hoje, com entrada em aberto: conta até agora
  if v_ini is not null and p_dia = v_hoje then v_min := v_min + floor(extract(epoch from now() - v_ini) / 60)::int; end if;
  select id, tipo, descricao, situacao, observacao into v_jid, v_jtipo, v_jdesc, v_jsit, v_jobs
  from iara.ponto_justificativas where staff_id = p_staff and data = p_dia;
  v_sit := case
    when not v_util and v_n = 0 then 'NAO_UTIL'
    when v_jsit = 'ABONADA' then 'ABONADO'
    when v_n = 0 and p_dia < v_hoje then 'FALTA'
    when v_n = 0 then 'AGUARDANDO'
    when v_n % 2 = 1 and p_dia < v_hoje then 'INCOMPLETO'
    when v_n % 2 = 1 then 'TRABALHANDO'
    when v_util and v_atraso > v_tol then 'ATRASO'
    else 'OK' end;
  return jsonb_build_object('data', p_dia, 'util', v_util, 'marcacoes', v_marcas, 'minutos', v_min,
    'previstos', case when v_util then (j ->> 'minutos')::int else 0 end, 'atraso_min', case when v_util and v_atraso > v_tol then v_atraso end,
    'fora', v_fora, 'situacao', v_sit,
    'justificativa', case when v_jid is not null then jsonb_build_object('id', v_jid, 'tipo', v_jtipo, 'descricao', v_jdesc, 'situacao', v_jsit, 'observacao', v_jobs) end);
end $$;

-- profissional da sessão (perfil com ponto.registrar ligado a um cadastro de profissional)
create or replace function iara.ponto_meu_staff() returns uuid
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v uuid;
begin
  perform iara.require_perm('ponto.registrar');
  select staff_id into v from iara.app_users where id = iara.current_user_id();
  if v is null then
    raise exception 'Este perfil não está ligado ao cadastro de um(a) profissional.' using errcode = '22023';
  end if;
  return v;
end $$;

-- unidade que a gestão pode ver: a própria (perfil de unidade) ou a escolhida (perfil da rede)
create or replace function iara.ponto_unidade_gestao(p_unit integer) returns integer
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else coalesce(p_unit, (iara.setting('demo_unit_maria'))::int) end;
begin
  perform iara.require_perm('ponto.gerir');
  if v is null or not iara.can_access_unit(v) then
    raise exception 'Unidade fora do seu acesso.' using errcode = '42501';
  end if;
  return v;
end $$;

-- 3. Demonstração ------------------------------------------------------------------------------------------------------------------
-- marcações fictícias, determinísticas por profissional e dia: ~4% de faltas, ~8% de atrasos, ~2% de saída esquecida e
-- ~3% de entradas longe da unidade; só até o momento atual. Quem cadastrou a biometria bate o próprio ponto (fica de fora).
create or replace function iara.ponto_demo_gerar(p_de date, p_ate date) returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_n integer;
begin
  with js as (
    select s.id, s.unit_id, u.lat, u.lng, iara.ponto_jornada(s.id) j
    from iara.staff s join iara.education_units u on u.id = s.unit_id
    where coalesce(s.situacao, 'ATIVO') = 'ATIVO'
      and not exists (select 1 from iara.ponto_credenciais c where c.staff_id = s.id and c.revogada_em is null)),
  dias as (select d::date dia from generate_series(p_de, p_ate, interval '1 day') d where iara.ponto_dia_util(d::date)),
  base as (
    select js.*, dias.dia, abs(hashtext(js.id::text || dias.dia::text)) h, jsonb_array_length(js.j -> 'periodos') np
    from js cross join dias),
  marcas as (
    select b.id, b.unit_id, b.lat, b.lng, b.dia, x.tipo, b.h,
           ((b.dia + (per.p ->> (case when x.tipo = 'ENTRADA' then 0 else 1 end))::time) at time zone 'America/Sao_Paulo')
             + make_interval(mins => case when x.tipo = 'ENTRADA'
                                          then case when b.h % 100 between 6 and 13 then 12 + (b.h / 7) % 29 else (b.h / 11) % 16 - 12 end
                                          else (b.h / 13) % 16 end,
                             secs => (b.h / 17) % 60 + per.k) as ts,
           x.tipo = 'ENTRADA' and per.k = 1 and b.h % 100 between 14 and 16 as fora
    from base b
    cross join lateral jsonb_array_elements(b.j -> 'periodos') with ordinality per(p, k)
    cross join (values ('ENTRADA'), ('SAIDA')) x(tipo)
    where b.h % 100 >= 4                                                          -- faltas
      and not (x.tipo = 'SAIDA' and per.k = b.np and b.h % 100 between 4 and 5))  -- saída esquecida
  insert into iara.ponto_marcacoes (staff_id, unit_id, marcada_em, data, tipo, metodo, lat, lng, precisao_m, distancia_m, fora_da_unidade, is_demo)
  select id, unit_id, ts, dia, tipo, 'BIOMETRIA_APARELHO', lat, lng, 10 + h % 40,
         case when fora then 420 + h % 900 else 5 + h % 110 end, fora, true
  from marcas where ts <= now()
  on conflict (staff_id, marcada_em) do nothing;
  get diagnostics v_n = row_count;

  -- justificativas: metade das faltas com atestado e as saídas esquecidas; depois de 7 dias a direção já tratou
  insert into iara.ponto_justificativas (staff_id, unit_id, data, tipo, descricao, situacao, enviada_em, tratada_por_label, tratada_em, is_demo)
  select s.id, s.unit_id, d.dia,
         case when abs(hashtext(s.id::text || d.dia::text)) % 100 < 2 then 'ATESTADO' else 'ESQUECIMENTO' end,
         case when abs(hashtext(s.id::text || d.dia::text)) % 100 < 2 then 'Atestado médico de um dia (demonstração).' else 'Esqueci de registrar a saída (demonstração).' end,
         case when d.dia < iara.hoje_local() - 7 then 'ABONADA' else 'PENDENTE' end,
         (d.dia + time '18:00') at time zone 'America/Sao_Paulo',
         case when d.dia < iara.hoje_local() - 7 then 'Direção da unidade (demonstração)' end,
         case when d.dia < iara.hoje_local() - 7 then (d.dia + 2 + time '10:00') at time zone 'America/Sao_Paulo' end, true
  from iara.staff s
  cross join (select g::date dia from generate_series(p_de, least(p_ate, iara.hoje_local() - 1), interval '1 day') g) d
  where s.unit_id is not null and coalesce(s.situacao, 'ATIVO') = 'ATIVO' and iara.ponto_dia_util(d.dia)
    and abs(hashtext(s.id::text || d.dia::text)) % 100 in (0, 1, 4, 5)
    and not exists (select 1 from iara.ponto_credenciais c where c.staff_id = s.id and c.revogada_em is null)
  on conflict (staff_id, data) do nothing;
  return v_n;
end $$;

-- completa a demonstração até agora (no máximo a cada 10 minutos): os dias que faltam e o dia de hoje até o momento
create or replace function iara.ponto_demo_completar() returns void
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ult date;
  v_em timestamptz;
  v_hoje date := iara.hoje_local();
begin
  if not iara.demo_mode() then return; end if;
  select ultimo_dia, atualizado_em into v_ult, v_em from iara.ponto_demo_estado where id = 1 for update;
  if v_em is not null and v_em > now() - interval '10 minutes' then return; end if;
  perform iara.ponto_demo_gerar(greatest(coalesce(v_ult, v_hoje - 40), v_hoje - 40), v_hoje);
  insert into iara.ponto_demo_estado (id, ultimo_dia, atualizado_em) values (1, v_hoje - 1, now())
  on conflict (id) do update set ultimo_dia = excluded.ultimo_dia, atualizado_em = excluded.atualizado_em;
end $$;

-- 4. Gateway (só depois da verificação da biometria; executado como sistema, com o usuário nas claims) -------------------------------
-- guarda o desafio e devolve o(a) profissional e as credenciais dele(a) neste domínio. p: tipo, desafio, rp_id
create or replace function iara.ponto_gateway_desafio(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_staff uuid := iara.ponto_meu_staff();
  v_creds jsonb;
begin
  if coalesce(p ->> 'tipo', '') not in ('CADASTRO', 'MARCACAO') or length(coalesce(p ->> 'desafio', '')) < 16 or coalesce(p ->> 'rp_id', '') = '' then
    raise exception 'Pedido de biometria inválido.' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', credencial, 'transports', transportes)), '[]') into v_creds
  from iara.ponto_credenciais where staff_id = v_staff and revogada_em is null and rp_id = p ->> 'rp_id';
  if p ->> 'tipo' = 'MARCACAO' and jsonb_array_length(v_creds) = 0 then
    raise exception 'Cadastre a biometria deste aparelho antes de bater o ponto.' using errcode = '22023';
  end if;
  delete from iara.ponto_desafios where user_id = iara.current_user_id() and (usado_em is not null or expira_em < now());
  insert into iara.ponto_desafios (user_id, staff_id, tipo, desafio, rp_id)
  values (iara.current_user_id(), v_staff, p ->> 'tipo', p ->> 'desafio', p ->> 'rp_id');
  return jsonb_build_object('staff_id', v_staff, 'nome', (select full_name from iara.staff where id = v_staff), 'credenciais', v_creds);
end $$;

-- consome o desafio mais recente (uso único, 5 min) e, na marcação, devolve a chave pública da credencial usada.
-- p: tipo, rp_id, credencial?
create or replace function iara.ponto_gateway_conferir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_staff uuid := iara.ponto_meu_staff();
  v_desafio text;
  c iara.ponto_credenciais;
begin
  update iara.ponto_desafios set usado_em = now()
  where id = (select id from iara.ponto_desafios where user_id = iara.current_user_id() and tipo = p ->> 'tipo' and rp_id = p ->> 'rp_id'
              and usado_em is null and expira_em > now() order by criado_em desc limit 1)
  returning desafio into v_desafio;
  if v_desafio is null then
    raise exception 'O pedido de biometria expirou. Tente de novo.' using errcode = '22023';
  end if;
  if p ->> 'tipo' = 'CADASTRO' then
    return jsonb_build_object('desafio', v_desafio);
  end if;
  select * into c from iara.ponto_credenciais
  where credencial = p ->> 'credencial' and staff_id = v_staff and revogada_em is null and rp_id = p ->> 'rp_id';
  if c.id is null then
    raise exception 'Esta biometria não está cadastrada para você neste aparelho.' using errcode = '22023';
  end if;
  return jsonb_build_object('desafio', v_desafio, 'credencial', jsonb_build_object('id', c.credencial, 'chave_publica', c.chave_publica,
    'contador', c.contador, 'transportes', c.transportes));
end $$;

-- cadastro conferido pelo gateway. p: credencial, chave_publica, contador, transportes, rp_id, aparelho
create or replace function iara.ponto_gateway_cadastrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_staff uuid := iara.ponto_meu_staff();
  v_id uuid;
  v_unit integer := (select unit_id from iara.staff where id = v_staff);
begin
  insert into iara.ponto_credenciais (staff_id, credencial, chave_publica, contador, transportes, rp_id, aparelho, is_demo)
  values (v_staff, p ->> 'credencial', p ->> 'chave_publica', coalesce((p ->> 'contador')::bigint, 0),
          coalesce(array(select jsonb_array_elements_text(p -> 'transportes')), '{}'), p ->> 'rp_id', left(coalesce(p ->> 'aparelho', ''), 120), iara.demo_mode())
  returning id into v_id;
  -- a partir de agora o ponto deste(a) profissional é o de verdade: sai a marcação fictícia de hoje
  delete from iara.ponto_marcacoes where staff_id = v_staff and data = iara.hoje_local() and is_demo and credencial_id is null and metodo = 'BIOMETRIA_APARELHO';
  perform iara.audit_event('PONTO_BIOMETRIA_CADASTRO', 'ponto_credencial', v_id::text, v_unit, 'Biometria do aparelho cadastrada para o ponto');
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- marcação conferida pelo gateway. p: credencial, contador, lat?, lng?, precisao?
create or replace function iara.ponto_gateway_marcar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_staff uuid := iara.ponto_meu_staff();
  c iara.ponto_credenciais;
  s iara.staff;
  u iara.education_units;
  v_hoje date := iara.hoje_local();
  v_ultima timestamptz;
  v_tipo text;
  v_lat double precision := nullif(p ->> 'lat', '')::double precision;
  v_lng double precision := nullif(p ->> 'lng', '')::double precision;
  v_dist integer;
  v_raio integer := coalesce(nullif(iara.setting('ponto_raio_m'), '')::int, 300);
  v_id uuid;
begin
  select * into c from iara.ponto_credenciais where credencial = p ->> 'credencial' and staff_id = v_staff and revogada_em is null;
  if c.id is null then
    raise exception 'Biometria não cadastrada.' using errcode = '22023';
  end if;
  select * into s from iara.staff where id = v_staff;
  select * into u from iara.education_units where id = s.unit_id;
  select max(marcada_em) into v_ultima from iara.ponto_marcacoes where staff_id = v_staff and data = v_hoje;
  if v_ultima is not null and v_ultima > now() - interval '2 minutes' then
    return jsonb_build_object('repetida', true, 'aviso', 'Sua marcação já foi registrada há instantes.', 'dia', iara.ponto_dia(v_staff, v_hoje));
  end if;
  v_tipo := case when (select count(*) from iara.ponto_marcacoes where staff_id = v_staff and data = v_hoje) % 2 = 0 then 'ENTRADA' else 'SAIDA' end;
  if v_lat between -90 and 90 and v_lng between -180 and 180 and u.id is not null then
    v_dist := round(extensions.st_distance(u.location, iara.point(v_lat, v_lng)))::int;
  end if;
  update iara.ponto_credenciais set contador = greatest(contador, coalesce((p ->> 'contador')::bigint, 0)), ultimo_uso_em = now() where id = c.id;
  insert into iara.ponto_marcacoes (staff_id, unit_id, marcada_em, data, tipo, metodo, credencial_id, lat, lng, precisao_m, distancia_m, fora_da_unidade,
                                    registrada_por_label, is_demo)
  values (v_staff, s.unit_id, now(), v_hoje, v_tipo, 'BIOMETRIA_APARELHO', c.id, round(v_lat::numeric, 5), round(v_lng::numeric, 5),
          nullif(p ->> 'precisao', '')::numeric::int, v_dist, coalesce(v_dist > v_raio, false), s.full_name, iara.demo_mode())
  returning id into v_id;
  perform iara.audit_event('PONTO_MARCACAO', 'ponto_marcacao', v_id::text, s.unit_id,
    'Ponto: ' || lower(v_tipo) || ' com a biometria do aparelho' || case when v_dist > v_raio then ' (longe da unidade: ' || v_dist || ' m)' else '' end);
  return jsonb_build_object('tipo', v_tipo, 'hora', to_char(now() at time zone 'America/Sao_Paulo', 'HH24:MI'), 'distancia_m', v_dist,
    'fora', coalesce(v_dist > v_raio, false), 'sem_local', v_dist is null, 'raio_m', v_raio, 'dia', iara.ponto_dia(v_staff, v_hoje));
end $$;

-- 5. API do(a) profissional --------------------------------------------------------------------------------------------------------
create or replace function api.ponto_eu(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_staff uuid := iara.ponto_meu_staff();
  s iara.staff;
  u iara.education_units;
  j jsonb := iara.ponto_jornada(v_staff);
  v_hoje date := iara.hoje_local();
begin
  perform iara.ponto_demo_completar();
  select * into s from iara.staff where id = v_staff;
  select * into u from iara.education_units where id = s.unit_id;
  return jsonb_build_object(
    'profissional', jsonb_build_object('nome', s.full_name, 'funcao', s.role, 'cargo', s.cargo, 'carga', s.carga_horaria_semanal),
    'unidade', jsonb_build_object('id', u.id, 'nome', u.short_name, 'lat', u.lat, 'lng', u.lng),
    'jornada', j, 'raio_m', coalesce(nullif(iara.setting('ponto_raio_m'), '')::int, 300),
    'hoje', iara.ponto_dia(v_staff, v_hoje, j),
    'proxima', case when (select count(*) from iara.ponto_marcacoes where staff_id = v_staff and data = v_hoje) % 2 = 0 then 'ENTRADA' else 'SAIDA' end,
    'credenciais', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'aparelho', aparelho, 'rp_id', rp_id, 'criada_em', criada_em,
                       'ultimo_uso_em', ultimo_uso_em) order by criada_em desc), '[]')
                    from iara.ponto_credenciais where staff_id = v_staff and revogada_em is null));
end $$;

-- espelho do mês (p: mes 'AAAA-MM', staff_id? — o de outra pessoa só para a gestão da unidade)
create or replace function api.ponto_espelho(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_staff uuid;
  s iara.staff;
  v_mes date := coalesce(to_date(nullif(p ->> 'mes', ''), 'YYYY-MM'), date_trunc('month', iara.hoje_local())::date);
  v_fim date := least((v_mes + interval '1 month - 1 day')::date, iara.hoje_local());
  j jsonb;
  v_dias jsonb := '[]';
  d jsonb;
  v_dia date;
  t_min integer := 0; t_prev integer := 0; t_faltas integer := 0; t_atrasos integer := 0; t_incomp integer := 0; t_trab integer := 0; t_abon integer := 0;
begin
  if nullif(p ->> 'staff_id', '') is not null then
    v_staff := (p ->> 'staff_id')::uuid;
    select * into s from iara.staff where id = v_staff;
    if s.id is null then raise exception 'Profissional não encontrado(a).' using errcode = 'P0002'; end if;
    perform iara.ponto_unidade_gestao(s.unit_id);
    if iara.my_scope() = 'UNIT' and s.unit_id <> iara.my_unit() then raise exception 'Profissional de outra unidade.' using errcode = '42501'; end if;
  else
    v_staff := iara.ponto_meu_staff();
    select * into s from iara.staff where id = v_staff;
  end if;
  perform iara.ponto_demo_completar();
  j := iara.ponto_jornada(v_staff);
  if v_mes > iara.hoje_local() then v_fim := v_mes - 1; end if;
  for v_dia in select g::date from generate_series(v_mes, v_fim, interval '1 day') g loop
    d := iara.ponto_dia(v_staff, v_dia, j);
    v_dias := v_dias || d;
    t_min := t_min + (d ->> 'minutos')::int;
    t_prev := t_prev + case when d ->> 'situacao' in ('ABONADO', 'AGUARDANDO', 'TRABALHANDO') then 0 else (d ->> 'previstos')::int end;
    t_faltas := t_faltas + (d ->> 'situacao' = 'FALTA')::int;
    t_atrasos := t_atrasos + (d ->> 'situacao' = 'ATRASO')::int;
    t_incomp := t_incomp + (d ->> 'situacao' = 'INCOMPLETO')::int;
    t_abon := t_abon + (d ->> 'situacao' = 'ABONADO')::int;
    t_trab := t_trab + (jsonb_array_length(d -> 'marcacoes') > 0)::int;
  end loop;
  return jsonb_build_object('profissional', jsonb_build_object('id', s.id, 'nome', s.full_name, 'funcao', s.role, 'carga', s.carga_horaria_semanal),
    'unidade', (select short_name from iara.education_units where id = s.unit_id), 'mes', to_char(v_mes, 'YYYY-MM'), 'jornada', j,
    'dias', v_dias, 'fechado', iara.ponto_mes_fechado(s.unit_id, v_mes),
    'totais', jsonb_build_object('minutos', t_min, 'previstos', t_prev, 'saldo', t_min - t_prev, 'dias_trabalhados', t_trab,
                                 'faltas', t_faltas, 'atrasos', t_atrasos, 'incompletos', t_incomp, 'abonados', t_abon));
end $$;

-- justificativa de um dia (p: data, tipo, descricao): esquecimento, atestado, serviço externo, formação
create or replace function api.ponto_justificar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_staff uuid := iara.ponto_meu_staff();
  v_unit integer := (select unit_id from iara.staff where id = v_staff);
  v_dia date := nullif(p ->> 'data', '')::date;
  v_id uuid;
begin
  if v_dia is null or v_dia > iara.hoje_local() or v_dia < date_trunc('month', iara.hoje_local())::date - interval '1 month' then
    raise exception 'Escolha um dia deste mês ou do mês passado.' using errcode = '22023';
  end if;
  if coalesce(p ->> 'tipo', '') not in ('ESQUECIMENTO', 'ATESTADO', 'SERVICO_EXTERNO', 'FORMACAO', 'OUTRO') then
    raise exception 'Escolha o motivo.' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p ->> 'descricao', ''))) < 5 then
    raise exception 'Conte em poucas palavras o que houve.' using errcode = '22023';
  end if;
  if iara.ponto_mes_fechado(v_unit, v_dia) then
    raise exception 'O ponto deste mês já foi fechado pela direção.' using errcode = '55006';
  end if;
  insert into iara.ponto_justificativas (staff_id, unit_id, data, tipo, descricao, is_demo)
  values (v_staff, v_unit, v_dia, p ->> 'tipo', left(btrim(p ->> 'descricao'), 500), iara.demo_mode())
  on conflict (staff_id, data) do update set tipo = excluded.tipo, descricao = excluded.descricao, situacao = 'PENDENTE', enviada_em = now(),
    tratada_por_label = null, tratada_em = null, observacao = null
    where iara.ponto_justificativas.situacao <> 'ABONADA'
  returning id into v_id;
  if v_id is null then
    raise exception 'Este dia já foi abonado.' using errcode = '22023';
  end if;
  perform iara.audit_event('PONTO_JUSTIFICATIVA', 'ponto_justificativa', v_id::text, v_unit, 'Justificativa de ponto enviada (' || to_char(v_dia, 'DD/MM') || ')');
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- tira uma biometria cadastrada (aparelho perdido ou trocado): a própria ou, pela gestão, a de alguém da unidade
create or replace function api.ponto_revogar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.ponto_credenciais;
  v_unit integer;
begin
  select * into c from iara.ponto_credenciais where id = nullif(p ->> 'id', '')::uuid and revogada_em is null;
  if c.id is null then raise exception 'Biometria não encontrada.' using errcode = 'P0002'; end if;
  v_unit := (select unit_id from iara.staff where id = c.staff_id);
  if not (iara.has_perm('ponto.registrar') and c.staff_id = (select staff_id from iara.app_users where id = iara.current_user_id())) then
    perform iara.ponto_unidade_gestao(v_unit);
    if iara.my_scope() = 'UNIT' and v_unit <> iara.my_unit() then raise exception 'Profissional de outra unidade.' using errcode = '42501'; end if;
  end if;
  update iara.ponto_credenciais set revogada_em = now() where id = c.id;
  perform iara.audit_event('PONTO_BIOMETRIA_REVOGADA', 'ponto_credencial', c.id::text, v_unit, 'Biometria do aparelho retirada do ponto');
  return jsonb_build_object('ok', true);
end $$;

-- 6. API da gestão -----------------------------------------------------------------------------------------------------------------
-- presença do dia na unidade (p: unit_id? para a rede, data?)
create or replace function api.ponto_painel(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_unit integer := iara.ponto_unidade_gestao(nullif(p ->> 'unit_id', '')::int);
  v_dia date := least(coalesce(nullif(p ->> 'data', '')::date, iara.hoje_local()), iara.hoje_local());
  v_equipe jsonb;
begin
  perform iara.ponto_demo_completar();
  select coalesce(jsonb_agg(x order by x ->> 'nome'), '[]') into v_equipe from (
    select jsonb_build_object('staff_id', s.id, 'nome', s.full_name, 'funcao', s.role, 'cargo', s.cargo,
             'biometria', exists (select 1 from iara.ponto_credenciais c where c.staff_id = s.id and c.revogada_em is null))
           || (iara.ponto_dia(s.id, v_dia) - 'data') x
    from iara.staff s where s.unit_id = v_unit and coalesce(s.situacao, 'ATIVO') = 'ATIVO') q;
  return jsonb_build_object(
    'unidade', (select jsonb_build_object('id', id, 'nome', short_name) from iara.education_units where id = v_unit),
    'data', v_dia, 'util', iara.ponto_dia_util(v_dia), 'equipe', v_equipe,
    'contagens', jsonb_build_object(
      'equipe', jsonb_array_length(v_equipe),
      'presentes', (select count(*) from jsonb_array_elements(v_equipe) e where jsonb_array_length(e -> 'marcacoes') > 0),
      'trabalhando', (select count(*) from jsonb_array_elements(v_equipe) e where e ->> 'situacao' = 'TRABALHANDO'),
      'ausentes', (select count(*) from jsonb_array_elements(v_equipe) e where e ->> 'situacao' in ('FALTA', 'AGUARDANDO')),
      'atrasos', (select count(*) from jsonb_array_elements(v_equipe) e where e ->> 'atraso_min' is not null),
      'fora', (select count(*) from jsonb_array_elements(v_equipe) e where (e ->> 'fora')::boolean),
      'incompletos', (select count(*) from jsonb_array_elements(v_equipe) e where e ->> 'situacao' = 'INCOMPLETO')),
    'pendencias', (select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'staff_id', j.staff_id, 'nome', s.full_name, 'data', j.data, 'tipo', j.tipo,
                     'descricao', j.descricao, 'enviada_em', j.enviada_em) order by j.data desc), '[]')
                   from iara.ponto_justificativas j join iara.staff s on s.id = j.staff_id where j.unit_id = v_unit and j.situacao = 'PENDENTE'),
    'fechamentos', (select coalesce(jsonb_agg(jsonb_build_object('mes', to_char(mes, 'YYYY-MM'), 'fechado_em', fechado_em, 'por', fechado_por_label)
                      order by mes desc), '[]') from iara.ponto_fechamentos where unit_id = v_unit),
    'demonstracao', iara.demo_mode());
end $$;

-- abona ou recusa uma justificativa (p: id, decisao ABONAR|RECUSAR, observacao?)
create or replace function api.ponto_tratar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  j iara.ponto_justificativas;
begin
  select * into j from iara.ponto_justificativas where id = nullif(p ->> 'id', '')::uuid;
  if j.id is null then raise exception 'Justificativa não encontrada.' using errcode = 'P0002'; end if;
  perform iara.ponto_unidade_gestao(j.unit_id);
  if iara.my_scope() = 'UNIT' and j.unit_id <> iara.my_unit() then raise exception 'Justificativa de outra unidade.' using errcode = '42501'; end if;
  if coalesce(p ->> 'decisao', '') not in ('ABONAR', 'RECUSAR') then raise exception 'Escolha abonar ou recusar.' using errcode = '22023'; end if;
  if iara.ponto_mes_fechado(j.unit_id, j.data) then raise exception 'O ponto deste mês já foi fechado.' using errcode = '55006'; end if;
  update iara.ponto_justificativas set situacao = case when p ->> 'decisao' = 'ABONAR' then 'ABONADA' else 'RECUSADA' end,
    tratada_por_label = (select display_name from iara.app_users where id = iara.current_user_id()), tratada_em = now(),
    observacao = nullif(left(btrim(coalesce(p ->> 'observacao', '')), 300), '')
  where id = j.id;
  perform iara.audit_event(case when p ->> 'decisao' = 'ABONAR' then 'PONTO_ABONO' else 'PONTO_RECUSA' end, 'ponto_justificativa', j.id::text, j.unit_id,
    'Justificativa de ponto ' || case when p ->> 'decisao' = 'ABONAR' then 'abonada' else 'recusada' end || ' (' || to_char(j.data, 'DD/MM') || ')');
  return jsonb_build_object('ok', true);
end $$;

-- marcação lançada pela gestão (esquecimento comprovado, aparelho sem biometria), sempre com motivo e auditoria.
-- p: staff_id, data, hora 'HH:MI', tipo ENTRADA|SAIDA, motivo
create or replace function api.ponto_ajustar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  s iara.staff;
  v_dia date := nullif(p ->> 'data', '')::date;
  v_ts timestamptz;
  v_id uuid;
begin
  select * into s from iara.staff where id = nullif(p ->> 'staff_id', '')::uuid;
  if s.id is null then raise exception 'Profissional não encontrado(a).' using errcode = 'P0002'; end if;
  perform iara.ponto_unidade_gestao(s.unit_id);
  if iara.my_scope() = 'UNIT' and s.unit_id <> iara.my_unit() then raise exception 'Profissional de outra unidade.' using errcode = '42501'; end if;
  if v_dia is null or v_dia > iara.hoje_local() or v_dia < iara.hoje_local() - 62 then raise exception 'Escolha um dia dos últimos dois meses.' using errcode = '22023'; end if;
  if coalesce(p ->> 'hora', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Informe a hora (HH:MM).' using errcode = '22023'; end if;
  if coalesce(p ->> 'tipo', '') not in ('ENTRADA', 'SAIDA') then raise exception 'Escolha entrada ou saída.' using errcode = '22023'; end if;
  if length(btrim(coalesce(p ->> 'motivo', ''))) < 10 then raise exception 'Explique o motivo do ajuste (ao menos 10 letras).' using errcode = '22023'; end if;
  if iara.ponto_mes_fechado(s.unit_id, v_dia) then raise exception 'O ponto deste mês já foi fechado.' using errcode = '55006'; end if;
  v_ts := (v_dia + (p ->> 'hora')::time) at time zone 'America/Sao_Paulo';
  if v_ts > now() then raise exception 'A hora ainda não chegou.' using errcode = '22023'; end if;
  insert into iara.ponto_marcacoes (staff_id, unit_id, marcada_em, data, tipo, metodo, motivo, registrada_por_label, is_demo)
  values (s.id, s.unit_id, v_ts, v_dia, p ->> 'tipo', 'AJUSTE_DIRECAO', left(btrim(p ->> 'motivo'), 300),
          (select display_name from iara.app_users where id = iara.current_user_id()), iara.demo_mode())
  on conflict (staff_id, marcada_em) do nothing
  returning id into v_id;
  if v_id is null then raise exception 'Já existe marcação neste horário.' using errcode = '23505'; end if;
  perform iara.audit_event('PONTO_AJUSTE', 'ponto_marcacao', v_id::text, s.unit_id,
    'Ajuste de ponto: ' || lower(p ->> 'tipo') || ' às ' || (p ->> 'hora') || ' de ' || to_char(v_dia, 'DD/MM'), jsonb_build_object('motivo', p ->> 'motivo'));
  return jsonb_build_object('ok', true, 'id', v_id, 'dia', iara.ponto_dia(s.id, v_dia));
end $$;

-- fecha um mês que já acabou (p: mes 'AAAA-MM', unit_id? para a rede): depois disso, sem ajustes nem abonos naquele mês
create or replace function api.ponto_fechar_mes(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_unit integer := iara.ponto_unidade_gestao(nullif(p ->> 'unit_id', '')::int);
  v_mes date := to_date(nullif(p ->> 'mes', ''), 'YYYY-MM');
  v_pend integer;
  v_resumo jsonb;
begin
  if v_mes is null or v_mes >= date_trunc('month', iara.hoje_local())::date then
    raise exception 'Só dá para fechar um mês que já terminou.' using errcode = '22023';
  end if;
  if iara.ponto_mes_fechado(v_unit, v_mes) then raise exception 'Este mês já está fechado.' using errcode = '23505'; end if;
  select count(*) into v_pend from iara.ponto_justificativas
  where unit_id = v_unit and situacao = 'PENDENTE' and date_trunc('month', data) = v_mes;
  if v_pend > 0 then
    raise exception 'Há % justificativa(s) pendente(s) neste mês. Trate antes de fechar.', v_pend using errcode = '22023';
  end if;
  select jsonb_build_object('marcacoes', count(*), 'ajustes', count(*) filter (where metodo = 'AJUSTE_DIRECAO'),
           'fora_da_unidade', count(*) filter (where fora_da_unidade), 'profissionais', count(distinct staff_id)) into v_resumo
  from iara.ponto_marcacoes where unit_id = v_unit and date_trunc('month', data) = v_mes;
  v_resumo := v_resumo || jsonb_build_object('abonos', (select count(*) from iara.ponto_justificativas where unit_id = v_unit and situacao = 'ABONADA' and date_trunc('month', data) = v_mes));
  insert into iara.ponto_fechamentos (unit_id, mes, fechado_por_label, resumo)
  values (v_unit, v_mes, (select display_name from iara.app_users where id = iara.current_user_id()), v_resumo);
  perform iara.audit_event('PONTO_FECHAMENTO', 'ponto_fechamento', v_unit || ':' || to_char(v_mes, 'YYYY-MM'), v_unit, 'Ponto do mês fechado: ' || to_char(v_mes, 'MM/YYYY'), v_resumo);
  return jsonb_build_object('ok', true, 'resumo', v_resumo);
end $$;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('ponto_marcacoes', 'lat', 'PESSOAL', 'localização', 'distância até a unidade no momento da marcação do ponto', 'só a gestão da unidade vê a distância; coordenada com 5 casas'),
  ('ponto_credenciais', 'chave_publica', 'INTERNO', 'credencial', 'conferir a biometria do aparelho no ponto (WebAuthn)', 'só a chave pública: a biometria nunca sai do aparelho')
on conflict (tabela, coluna) do nothing;

revoke all on function iara.ponto_dia_util(date), iara.ponto_jornada(uuid), iara.ponto_mes_fechado(integer, date), iara.ponto_dia(uuid, date, jsonb),
  iara.ponto_meu_staff(), iara.ponto_unidade_gestao(integer), iara.ponto_demo_gerar(date, date), iara.ponto_demo_completar(),
  iara.ponto_gateway_desafio(jsonb), iara.ponto_gateway_conferir(jsonb), iara.ponto_gateway_cadastrar(jsonb), iara.ponto_gateway_marcar(jsonb) from public;

-- demonstração: do primeiro dia do mês passado até agora
select iara.ponto_demo_gerar((date_trunc('month', iara.hoje_local()) - interval '1 month')::date, iara.hoje_local());
insert into iara.ponto_demo_estado (id, ultimo_dia, atualizado_em) values (1, iara.hoje_local() - 1, now())
on conflict (id) do update set ultimo_dia = excluded.ultimo_dia, atualizado_em = excluded.atualizado_em;

commit;
