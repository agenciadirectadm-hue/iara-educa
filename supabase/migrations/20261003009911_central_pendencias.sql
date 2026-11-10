-- IARA Educa — 099.11 · Central de pendências
-- Cada servidor abre o sistema e vê o que tem de cumprir: validações, conferências, aprovações, prazos e procedimentos.
--   • origem: AUTOMATICA (gerada a partir dos módulos e fechada sozinha quando se resolve no módulo), ATRIBUIDA (tarefa com prazo
--     dada pela chefia) e ROTINA (procedimento periódico com lista de conferência, cadastrado pela SEDUC ou pela direção);
--   • quem acompanha: na unidade, a direção acompanha a secretaria escolar, os professores e o AEE; na SEDUC, cada chefia acompanha
--     o seu setor pelo organograma (iara.org_setores); a Superintendência alcança diretorias, gerências e unidades; o Secretário, tudo;
--     a Gerência de Educação Infantil acompanha também os CMEIs;
--   • atraso: a pendência fica em vermelho para o servidor e entra na lista de atrasadas da chefia; nada sai por WhatsApp;
--   • estatísticas: Prefeito só agregado (unidade, região, área, tipo e mapa); Secretário e Superintendência podem descer até a pessoa.
-- A pendência pertence a um "posto": a pessoa (staff) quando se sabe quem é, ou o papel na unidade/setor (ex.: secretaria escolar
-- da E.M. X), quando quem cumpre é quem estiver no posto.
begin;

-- 1. Permissões ------------------------------------------------------------------------------------------------------------------------
insert into iara.permissions (code, description, is_sensitive) values
  ('pend.read', 'Ver e cumprir as próprias pendências (validações, conferências, procedimentos e tarefas)', false),
  ('pend.equipe', 'Acompanhar as pendências da equipe (chefia da unidade ou do setor no organograma)', false),
  ('pend.atribuir', 'Atribuir tarefa com prazo a alguém da equipe, cobrar, cancelar e devolver', false),
  ('pend.rotinas', 'Cadastrar procedimentos periódicos com lista de conferência', false),
  ('pend.estatisticas', 'Ver estatísticas e mapa das pendências da rede (agregadas)', false),
  ('pend.nomes', 'Ver o nome dos servidores nas estatísticas de pendências', true)
on conflict (code) do update set description = excluded.description, is_sensitive = excluded.is_sensitive;

insert into iara.role_permissions (role_code, permission_code)
select v.r, v.p from (values
  ('SECRETARIO', 'pend.read'), ('SECRETARIO', 'pend.equipe'), ('SECRETARIO', 'pend.atribuir'), ('SECRETARIO', 'pend.rotinas'),
  ('SECRETARIO', 'pend.estatisticas'), ('SECRETARIO', 'pend.nomes'),
  ('SUPERINTENDENCIA', 'pend.read'), ('SUPERINTENDENCIA', 'pend.equipe'), ('SUPERINTENDENCIA', 'pend.atribuir'), ('SUPERINTENDENCIA', 'pend.rotinas'),
  ('SUPERINTENDENCIA', 'pend.estatisticas'), ('SUPERINTENDENCIA', 'pend.nomes'),
  ('PREFEITO', 'pend.estatisticas'),
  ('GERENCIA_EI', 'pend.read'), ('GERENCIA_EI', 'pend.equipe'), ('GERENCIA_EI', 'pend.atribuir'),
  ('GERENCIA_APOIO', 'pend.read'), ('GERENCIA_APOIO', 'pend.equipe'), ('GERENCIA_APOIO', 'pend.atribuir'),
  ('DIRETOR_UNIDADE', 'pend.read'), ('DIRETOR_UNIDADE', 'pend.equipe'), ('DIRETOR_UNIDADE', 'pend.atribuir'), ('DIRETOR_UNIDADE', 'pend.rotinas'),
  ('SECRETARIA_ESCOLAR', 'pend.read'), ('PROFESSOR', 'pend.read'), ('PROFESSOR_AEE', 'pend.read'),
  ('ANALISTA_CENTRAL', 'pend.read'), ('ATENDIMENTO', 'pend.read'), ('INOVACAO', 'pend.read'),
  ('NUTRICAO', 'pend.read'), ('MANUTENCAO', 'pend.read'), ('TRANSPORTE', 'pend.read'), ('ALMOXARIFADO', 'pend.read'),
  ('APOIO_INTERDISCIPLINAR', 'pend.read')
) v(r, p)
where exists (select 1 from iara.organizational_roles o where o.code = v.r)
on conflict do nothing;

-- 2. Papéis: a que setor cada perfil pertence e quem é chefia ---------------------------------------------------------------------------
create table if not exists iara.pend_papeis (
  role_code text primary key references iara.organizational_roles(code) on delete cascade,
  rotulo text not null,
  setor_sigla text not null,
  na_unidade boolean not null default false,
  chefia boolean not null default false,
  ordem smallint not null default 0
);
alter table iara.pend_papeis enable row level security;

insert into iara.pend_papeis (role_code, rotulo, setor_sigla, na_unidade, chefia, ordem)
select v.* from (values
  ('SECRETARIO', 'Secretário(a) de Educação', 'SEDUC', false, true, 1),
  ('SUPERINTENDENCIA', 'Superintendência', 'SUP', false, true, 2),
  ('GERENCIA_EI', 'Gerência de Educação Infantil', 'GEI', false, true, 3),
  ('GERENCIA_APOIO', 'Gerência de Educação Especial e Apoio', 'GEE', false, true, 4),
  ('ANALISTA_CENTRAL', 'Central de Vagas', 'CV', false, false, 5),
  ('ATENDIMENTO', 'Central de Atendimento', 'CA', false, false, 6),
  ('INOVACAO', 'Diretoria de Inovação', 'DINOV', false, false, 7),
  ('NUTRICAO', 'Merenda e nutrição', 'GME', false, false, 8),
  ('TRANSPORTE', 'Transporte escolar', 'GTE', false, false, 9),
  ('ALMOXARIFADO', 'Almoxarifado', 'GSA', false, false, 10),
  ('MANUTENCAO', 'Manutenção', 'DMAN', false, false, 11),
  ('APOIO_INTERDISCIPLINAR', 'Apoio interdisciplinar', 'GEE', false, false, 12),
  ('DIRETOR_UNIDADE', 'Direção', 'UNID', true, true, 20),
  ('SECRETARIA_ESCOLAR', 'Secretaria escolar', 'UNID', true, false, 21),
  ('PROFESSOR', 'Professor(a)', 'UNID', true, false, 22),
  ('PROFESSOR_AEE', 'Professor(a) do AEE', 'UNID', true, false, 23)
) v(role_code, rotulo, setor_sigla, na_unidade, chefia, ordem)
where exists (select 1 from iara.organizational_roles o where o.code = v.role_code)
on conflict (role_code) do update set rotulo = excluded.rotulo, setor_sigla = excluded.setor_sigla, na_unidade = excluded.na_unidade,
  chefia = excluded.chefia, ordem = excluded.ordem;

-- 3. Catálogo de tipos ------------------------------------------------------------------------------------------------------------------
create table if not exists iara.pend_tipos (
  codigo text primary key,
  modulo text not null,
  titulo text not null,
  papel text references iara.organizational_roles(code),
  procedimento text not null,
  prazo_regra text,
  rota text,
  origem text not null default 'AUTOMATICA' check (origem in ('AUTOMATICA', 'ATRIBUIDA', 'ROTINA')),
  ativo boolean not null default true,
  ordem smallint not null default 0
);
alter table iara.pend_tipos enable row level security;

insert into iara.pend_tipos (codigo, modulo, titulo, papel, procedimento, prazo_regra, rota, origem, ordem) values
  ('TAREFA', 'Tarefas da chefia', 'Tarefa atribuída pela chefia', null, 'Cumpra o que a chefia pediu e marque como concluída, com uma nota se precisar.', 'Dado pela chefia.', null, 'ATRIBUIDA', 900),
  ('PROCEDIMENTO', 'Procedimentos periódicos', 'Procedimento periódico', null, 'Siga a lista de conferência, marque cada item e conclua.', 'Contado do início do período.', null, 'ROTINA', 901)
on conflict (codigo) do update set modulo = excluded.modulo, titulo = excluded.titulo, procedimento = excluded.procedimento,
  prazo_regra = excluded.prazo_regra, origem = excluded.origem, ordem = excluded.ordem;

-- 4. Procedimentos periódicos ----------------------------------------------------------------------------------------------------------
create table if not exists iara.pend_rotinas (
  id uuid primary key default gen_random_uuid(),
  titulo text not null check (length(btrim(titulo)) between 5 and 140),
  procedimento text not null check (length(btrim(procedimento)) between 10 and 2000),
  checklist text[] not null default '{}',
  papel text not null references iara.organizational_roles(code),
  alvo text not null check (alvo in ('TODAS', 'CMEI', 'ESCOLA', 'UNIDADE', 'SETOR')),
  unit_id integer references iara.education_units(id),
  periodicidade text not null check (periodicidade in ('SEMANAL', 'QUINZENAL', 'MENSAL', 'BIMESTRAL', 'SEMESTRAL', 'ANUAL')),
  dia smallint not null default 1 check (dia between 1 and 28),
  prazo_dias smallint not null default 5 check (prazo_dias between 1 and 60),
  inicio date not null default current_date,
  ativo boolean not null default true,
  criada_por uuid,
  criada_por_label text,
  criada_em timestamptz not null default now(),
  atualizada_em timestamptz not null default now(),
  is_demo boolean not null default false,
  check (alvo <> 'UNIDADE' or unit_id is not null)
);
alter table iara.pend_rotinas enable row level security;

-- 5. Pendências ------------------------------------------------------------------------------------------------------------------------
create table if not exists iara.pendencias (
  id uuid primary key default gen_random_uuid(),
  origem text not null check (origem in ('AUTOMATICA', 'ATRIBUIDA', 'ROTINA')),
  tipo text not null references iara.pend_tipos(codigo),
  chave text not null,
  titulo text not null,
  detalhe text,
  quantidade integer,
  papel text not null references iara.organizational_roles(code),
  unit_id integer references iara.education_units(id),
  setor_id uuid references iara.org_setores(id),
  staff_id uuid references iara.staff(id) on delete set null,
  prazo timestamptz,
  rota text,
  checklist jsonb,
  situacao text not null default 'ABERTA' check (situacao in ('ABERTA', 'CONCLUIDA', 'CANCELADA')),
  criada_em timestamptz not null default now(),
  concluida_em timestamptz,
  concluida_por uuid,
  concluida_por_label text,
  conclusao text,
  atribuida_por uuid,
  atribuida_por_label text,
  rotina_id uuid references iara.pend_rotinas(id) on delete set null,
  ref_id text,
  is_demo boolean not null default false,
  posto text generated always as (
    case when staff_id is not null then 'P:' || staff_id::text
         else 'R:' || papel || ':' || coalesce(unit_id::text, '') || ':' || coalesce(setor_id::text, '') end) stored
);
-- automática: uma aberta por chave (se voltar depois de resolvida, é um novo episódio); tarefa e procedimento: chave única
create unique index if not exists pendencias_auto_aberta_uq on iara.pendencias (chave) where origem = 'AUTOMATICA' and situacao = 'ABERTA';
create unique index if not exists pendencias_manual_uq on iara.pendencias (chave) where origem <> 'AUTOMATICA';
create index if not exists pendencias_abertas_idx on iara.pendencias (papel, unit_id) where situacao = 'ABERTA';
create index if not exists pendencias_posto_idx on iara.pendencias (posto, situacao);
create index if not exists pendencias_staff_idx on iara.pendencias (staff_id) where staff_id is not null;
create index if not exists pendencias_setor_idx on iara.pendencias (setor_id, situacao);
create index if not exists pendencias_unit_idx on iara.pendencias (unit_id, situacao);
create index if not exists pendencias_concluida_idx on iara.pendencias (concluida_em) where situacao = 'CONCLUIDA';
create index if not exists pendencias_criada_idx on iara.pendencias (criada_em);
alter table iara.pendencias enable row level security;

create table if not exists iara.pend_eventos (
  id uuid primary key default gen_random_uuid(),
  pendencia_id uuid not null references iara.pendencias(id) on delete cascade,
  tipo text not null check (tipo in ('CRIADA', 'COBRADA', 'ITEM', 'CONCLUIDA', 'DEVOLVIDA', 'CANCELADA')),
  texto text,
  autor uuid,
  autor_label text,
  em timestamptz not null default clock_timestamp(),
  is_demo boolean not null default false
);
create index if not exists pend_eventos_pend_idx on iara.pend_eventos (pendencia_id, em);
alter table iara.pend_eventos alter column em set default clock_timestamp();  -- a ordem vale também dentro da mesma transação
alter table iara.pend_eventos enable row level security;

create table if not exists iara.pend_sinc (
  escopo text primary key,
  em timestamptz not null default now(),
  resultado jsonb
);
alter table iara.pend_sinc enable row level security;

-- estatísticas da rede já calculadas (5 minutos)
create table if not exists iara.pend_estat_cache (
  chave text primary key,
  em timestamptz not null default now(),
  resultado jsonb not null
);
alter table iara.pend_estat_cache enable row level security;

-- 6. Quem sou eu e o que alcanço ---------------------------------------------------------------------------------------------------------
create or replace function iara.pend_setor(p_sigla text) returns uuid
language sql stable security definer set search_path = iara, public
as $$ select id from iara.org_setores where sigla = p_sigla $$;

-- setores abaixo (inclusive) de um setor
create or replace function iara.pend_subarvore(p_setor uuid) returns uuid[]
language sql stable security definer set search_path = iara, public
as $$
  with recursive t as (select id from iara.org_setores where id = p_setor
                       union all select s.id from iara.org_setores s join t on s.superior_id = t.id)
  select coalesce(array_agg(id), '{}') from t
$$;

-- contexto do usuário logado: papel, unidade, pessoa, setor, se é chefia e os setores que alcança
create or replace function iara.pend_eu(out papel text, out unit_id integer, out staff_id uuid, out setor_id uuid, out chefia boolean,
                                        out alcance uuid[], out tudo boolean, out cmeis boolean, out nome text, out na_unidade boolean)
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  u iara.app_users;
  pp iara.pend_papeis;
begin
  select * into u from iara.app_users where id = iara.current_user_id();
  if not found then return; end if;
  papel := u.role_code; unit_id := u.unit_id; staff_id := u.staff_id; nome := u.display_name;
  select * into pp from iara.pend_papeis where role_code = u.role_code;
  chefia := coalesce(pp.chefia, false);
  na_unidade := coalesce(pp.na_unidade, false);
  setor_id := coalesce((select v.setor_id from iara.org_vinculos v where v.staff_id = u.staff_id and v.fim is null and u.staff_id is not null
                        order by v.chefia desc, v.inicio limit 1), iara.pend_setor(pp.setor_sigla));
  tudo := u.role_code = 'SECRETARIO';
  cmeis := u.role_code = 'GERENCIA_EI';
  alcance := case when chefia and not coalesce(pp.na_unidade, false) then iara.pend_subarvore(setor_id) else '{}'::uuid[] end;
end $$;

-- a pendência é minha? (sem security definer nem search_path, para o planejador embutir na consulta)
create or replace function iara.pend_minha(p_staff uuid, p_papel text, p_unit integer, e_papel text, e_unit integer, e_staff uuid, e_na_unidade boolean) returns boolean
language sql stable as $$
  select coalesce((p_staff is not null and p_staff = e_staff), false)
      or coalesce((p_staff is null and p_papel = e_papel and (not e_na_unidade or p_unit = e_unit)), false)
$$;

-- a chefia alcança a pendência? (unidade para a direção; setores do organograma para a SEDUC; CMEIs para a Gerência de Educação Infantil)
create or replace function iara.pend_alcanca(p_unit integer, p_setor uuid, e_papel text, e_unit integer, e_alcance uuid[], e_tudo boolean, e_cmeis boolean) returns boolean
language sql stable as $$
  select coalesce(e_tudo, false)
      or coalesce(e_papel = 'DIRETOR_UNIDADE' and p_unit = e_unit, false)
      or coalesce(p_setor = any (e_alcance), false)
      or coalesce(e_cmeis and p_unit is not null and exists (select 1 from iara.education_units u where u.id = p_unit and u.unit_type = 'CMEI'), false)
$$;

-- rótulo do posto: a pessoa, quando se sabe; senão o papel na unidade ou no setor
create or replace function iara.pend_posto_rotulo(p_papel text, p_unit integer, p_setor uuid, p_staff uuid) returns text
language sql stable security definer set search_path = iara, public as $$
  select case
    when p_staff is not null then (select s.full_name from iara.staff s where s.id = p_staff)
    when p_unit is not null then coalesce((select rotulo from iara.pend_papeis where role_code = p_papel), p_papel)
    else coalesce((select rotulo from iara.pend_papeis where role_code = p_papel), (select nome from iara.org_setores where id = p_setor), p_papel) end
$$;

create or replace function iara.pend_papel_rotulo(p_papel text) returns text
language sql stable security definer set search_path = iara, public as $$
  select coalesce((select rotulo from iara.pend_papeis where role_code = p_papel), (select name from iara.organizational_roles where code = p_papel), p_papel)
$$;

-- decompõe a chave do posto em papel/unidade/setor/pessoa
create or replace function iara.pend_posto_partes(p_posto text, out papel text, out unit_id integer, out setor_id uuid, out staff_id uuid)
language plpgsql stable security definer set search_path = iara, public as $$
declare
  a text[];
  s iara.staff;
begin
  if p_posto like 'P:%' then
    select * into s from iara.staff where id = nullif(substr(p_posto, 3), '')::uuid;
    if not found then raise exception 'Pessoa não encontrada.' using errcode = '22023'; end if;
    staff_id := s.id; unit_id := s.unit_id;
    papel := case when exists (select 1 from iara.apoio_profissionais ap where ap.staff_id = s.id and ap.ativo) then 'APOIO_INTERDISCIPLINAR'
                  when s.role = 'AEE' then 'PROFESSOR_AEE' else 'PROFESSOR' end;
    setor_id := coalesce((select v.setor_id from iara.org_vinculos v where v.staff_id = s.id and v.fim is null order by v.chefia desc limit 1),
                         case when s.role = 'AEE' then iara.pend_setor('GEE-EEI') else iara.pend_setor('UNID') end);
    if papel = 'APOIO_INTERDISCIPLINAR' then unit_id := null; end if;
  elsif p_posto like 'R:%' then
    a := string_to_array(substr(p_posto, 3), ':');
    papel := a[1]; unit_id := nullif(a[2], '')::int; setor_id := nullif(a[3], '')::uuid;
    if not exists (select 1 from iara.pend_papeis where role_code = papel) then raise exception 'Posto desconhecido.' using errcode = '22023'; end if;
  else
    raise exception 'Posto desconhecido.' using errcode = '22023';
  end if;
end $$;

-- turmas de um(a) professor(a) numa unidade: regência e componentes do horário
create or replace function iara.pend_turmas(p_staff uuid, p_unit integer) returns text
language sql stable security definer set search_path = iara, public as $$
  select string_agg(distinct n, ', ' order by n) from (
    select c.class_name n from iara.class_staff cs join iara.classes c on c.id = cs.class_id
    where cs.staff_id = p_staff and c.unit_id = p_unit and c.status = 'ATIVA' and (cs.end_date is null or cs.end_date >= current_date)
    union
    select c.class_name from iara.horarios_turma h join iara.classes c on c.id = h.class_id
    where h.staff_id = p_staff and c.unit_id = p_unit and c.status = 'ATIVA') z
$$;

-- 7. JSON de uma pendência ------------------------------------------------------------------------------------------------------------
create or replace function iara.pend_json(p iara.pendencias) returns jsonb
language sql stable security definer set search_path = iara, public as $$
  select jsonb_build_object(
    'id', p.id, 'origem', p.origem, 'tipo', p.tipo, 'modulo', t.modulo, 'titulo', p.titulo, 'detalhe', p.detalhe, 'quantidade', p.quantidade,
    'prazo', p.prazo, 'situacao', p.situacao, 'rota', p.rota, 'checklist', p.checklist,
    'atrasada', p.situacao = 'ABERTA' and p.prazo is not null and p.prazo < now(),
    'dias_atraso', case when p.situacao = 'ABERTA' and p.prazo < now() then greatest(1, (iara.hoje_local() - (p.prazo at time zone 'America/Sao_Paulo')::date)) end,
    'vence_hoje', p.situacao = 'ABERTA' and p.prazo >= now() and (p.prazo at time zone 'America/Sao_Paulo')::date = iara.hoje_local(),
    'no_prazo', case when p.situacao = 'CONCLUIDA' and p.prazo is not null then p.concluida_em <= p.prazo end,
    'criada_em', p.criada_em, 'concluida_em', p.concluida_em, 'concluida_por', p.concluida_por_label, 'conclusao', p.conclusao,
    'atribuida_por', p.atribuida_por_label,
    'procedimento', coalesce((select r.procedimento from iara.pend_rotinas r where r.id = p.rotina_id), t.procedimento),
    'prazo_regra', t.prazo_regra,
    'posto', p.posto, 'responsavel', iara.pend_posto_rotulo(p.papel, p.unit_id, p.setor_id, p.staff_id), 'papel', iara.pend_papel_rotulo(p.papel),
    'unidade', (select u.short_name from iara.education_units u where u.id = p.unit_id),
    'setor', (select s.nome from iara.org_setores s where s.id = p.setor_id and s.sigla <> 'UNID'),
    'ultima_cobranca', (select jsonb_build_object('texto', e.texto, 'autor', e.autor_label, 'em', e.em) from iara.pend_eventos e
                        where e.pendencia_id = p.id and e.tipo in ('COBRADA', 'DEVOLVIDA') order by e.em desc limit 1),
    'simulado', p.is_demo)
  from iara.pend_tipos t where t.codigo = p.tipo
$$;

-- 8. Procedimentos periódicos: início do período vigente ----------------------------------------------------------------------------------
create or replace function iara.pend_periodo_inicio(p_per text, p_dia smallint, p_inicio date, p_ref date) returns date
language plpgsql immutable as $$
declare
  v_meses integer;
  k integer;
  v date;
  v_base date;
begin
  if p_per in ('SEMANAL', 'QUINZENAL') then
    v_meses := case p_per when 'SEMANAL' then 7 else 14 end;   -- aqui, dias do ciclo
    v_base := date_trunc('week', p_inicio)::date;               -- segunda-feira da semana de início
    v := v_base + ((p_ref - v_base) / v_meses) * v_meses + (least(p_dia, 5) - 1);
    if v > p_ref then v := v - v_meses; end if;
    return v;
  end if;
  v_meses := case p_per when 'MENSAL' then 1 when 'BIMESTRAL' then 2 when 'SEMESTRAL' then 6 else 12 end;
  v_base := date_trunc('month', p_inicio)::date;
  k := ((extract(year from p_ref)::int * 12 + extract(month from p_ref)::int) - (extract(year from v_base)::int * 12 + extract(month from v_base)::int));
  v := (v_base + make_interval(months => (floor(k::numeric / v_meses) * v_meses)::int))::date + (p_dia - 1);
  if v > p_ref then v := (v - make_interval(months => v_meses))::date; end if;
  return v;
end $$;

create or replace function iara.pend_periodo_proximo(p_per text, p_dia smallint, p_inicio date, p_ref date) returns date
language sql immutable as $$
  select case when p_per = 'SEMANAL' then iara.pend_periodo_inicio(p_per, p_dia, p_inicio, p_ref) + 7
              when p_per = 'QUINZENAL' then iara.pend_periodo_inicio(p_per, p_dia, p_inicio, p_ref) + 14
              else (iara.pend_periodo_inicio(p_per, p_dia, p_inicio, p_ref)
                    + make_interval(months => case p_per when 'MENSAL' then 1 when 'BIMESTRAL' then 2 when 'SEMESTRAL' then 6 else 12 end))::date end
$$;

create or replace function iara.pend_periodo_rotulo(p_per text) returns text
language sql immutable as $$
  select case p_per when 'SEMANAL' then 'toda semana' when 'QUINZENAL' then 'a cada 15 dias' when 'MENSAL' then 'todo mês'
                    when 'BIMESTRAL' then 'a cada bimestre' when 'SEMESTRAL' then 'a cada semestre' else 'todo ano' end
$$;

-- gera as pendências do período vigente (ou do período que contém p_ref), uma por posto alvo; idempotente pela chave
drop function if exists iara.pend_rotinas_gerar(uuid);
create or replace function iara.pend_rotinas_gerar(p_rotina uuid default null, p_ref date default null) returns integer
language plpgsql security definer set search_path = iara, public as $$
declare
  r iara.pend_rotinas;
  v_ini date;
  v_prazo timestamptz;
  n integer := 0;
  m integer;
  v_check jsonb;
  pp iara.pend_papeis;
begin
  for r in select * from iara.pend_rotinas where ativo and inicio <= coalesce(p_ref, iara.hoje_local()) and (p_rotina is null or id = p_rotina) loop
    v_ini := iara.pend_periodo_inicio(r.periodicidade, r.dia, r.inicio, coalesce(p_ref, iara.hoje_local()));
    continue when v_ini < r.inicio;
    v_prazo := ((v_ini + r.prazo_dias)::timestamp + time '18:00') at time zone 'America/Sao_Paulo';
    v_check := (select coalesce(jsonb_agg(jsonb_build_object('item', x, 'feito', false)), '[]'::jsonb) from unnest(r.checklist) x);
    select * into pp from iara.pend_papeis where role_code = r.papel;
    if coalesce(pp.na_unidade, false) then
      with alvo as (
        select u.id from iara.education_units u
        where u.status = 'ATIVA'
          and case r.alvo when 'UNIDADE' then u.id = r.unit_id when 'CMEI' then u.unit_type = 'CMEI' when 'ESCOLA' then u.unit_type = 'ESCOLA' else true end),
      postos as (
        -- professores: um por regente; AEE: um por professor(a) do AEE; demais: um por unidade
        select a.id unit_id, s.staff_id from alvo a
        cross join lateral (
          select distinct cs.staff_id from iara.class_staff cs join iara.classes c on c.id = cs.class_id
          where r.papel = 'PROFESSOR' and c.unit_id = a.id and c.status = 'ATIVA' and cs.role_type = 'REGENTE' and (cs.end_date is null or cs.end_date >= current_date)
          union
          select st.id from iara.staff st where r.papel = 'PROFESSOR_AEE' and st.unit_id = a.id and st.role = 'AEE' and st.situacao = 'ATIVO'
          union all
          select null::uuid where r.papel not in ('PROFESSOR', 'PROFESSOR_AEE')) s)
      insert into iara.pendencias (origem, tipo, chave, titulo, detalhe, papel, unit_id, setor_id, staff_id, prazo, checklist, rotina_id, criada_em, is_demo)
      select 'ROTINA', 'PROCEDIMENTO', format('ROT:%s:%s:%s:%s', r.id, v_ini, p.unit_id, coalesce(p.staff_id::text, '')),
             r.titulo, format('Período que começou em %s (%s).', to_char(v_ini, 'DD/MM/YYYY'), iara.pend_periodo_rotulo(r.periodicidade)),
             r.papel, p.unit_id, case when r.papel = 'PROFESSOR_AEE' then iara.pend_setor('GEE-EEI') else iara.pend_setor('UNID') end, p.staff_id,
             v_prazo, v_check, r.id, greatest(r.criada_em, (v_ini::timestamp + time '07:00') at time zone 'America/Sao_Paulo'), r.is_demo
      from postos p
      on conflict (chave) where origem <> 'AUTOMATICA' do nothing;
    else
      insert into iara.pendencias (origem, tipo, chave, titulo, detalhe, papel, setor_id, prazo, checklist, rotina_id, criada_em, is_demo)
      values ('ROTINA', 'PROCEDIMENTO', format('ROT:%s:%s:setor', r.id, v_ini), r.titulo,
              format('Período que começou em %s (%s).', to_char(v_ini, 'DD/MM/YYYY'), iara.pend_periodo_rotulo(r.periodicidade)),
              r.papel, iara.pend_setor(pp.setor_sigla), v_prazo, v_check, r.id,
              greatest(r.criada_em, (v_ini::timestamp + time '07:00') at time zone 'America/Sao_Paulo'), r.is_demo)
      on conflict (chave) where origem <> 'AUTOMATICA' do nothing;
    end if;
    get diagnostics m = row_count;
    n := n + m;
  end loop;
  return n;
end $$;

-- 9. Pendências automáticas: o que os módulos já deixam esperando alguém ------------------------------------------------------------------
-- Prazos marcados "referência da demonstração" não estão em norma da rede: a SEDUC valida (pend_tipos.prazo_regra).
insert into iara.pend_tipos (codigo, modulo, titulo, papel, procedimento, prazo_regra, rota, ordem) values
  ('VALIDAR_DOCUMENTOS', 'Matrícula e cadastro', 'Validar documentos e alterações enviados pelas famílias', 'SECRETARIA_ESCOLAR',
   'Abra Validações, confira cada documento ou alteração enviada pela família e aceite, ou recuse com a orientação do que corrigir.',
   '3 dias após o envio mais antigo (referência da demonstração, a validar pela SEDUC).', '/validacoes', 10),
  ('VALIDAR_CENTRAL', 'Matrícula e cadastro', 'Validar documentos de quem ainda não está matriculado', 'ANALISTA_CENTRAL',
   'Abra Validações, confira cada documento ou alteração enviada pela família e aceite, ou recuse com a orientação do que corrigir.',
   '3 dias após o envio mais antigo (referência da demonstração, a validar pela SEDUC).', '/validacoes', 11),
  ('CONFIRMAR_MATRICULA', 'Matrícula e cadastro', 'Confirmar matrículas aceitas pelas famílias', 'SECRETARIA_ESCOLAR',
   'A família aceitou a vaga. Confira os documentos obrigatórios e confirme a matrícula em Matrículas e ofertas.',
   '3 dias após o aceite (referência da demonstração, a validar pela SEDUC).', '/ofertas', 12),
  ('PRONTO_OFERTAR', 'Matrícula e cadastro', 'Ofertar vagas a quem está em 1º lugar na fila', 'ANALISTA_CENTRAL',
   'Há vaga livre e criança em 1º lugar na fila da mesma unidade e série: oferte a vaga (a família tem 72 horas para responder, IN 025).',
   'Sem prazo próprio; a fila espera enquanto a vaga não é ofertada.', '/fila', 13),
  ('TRANSFERENCIA_RESPONDER', 'Matrícula e cadastro', 'Responder pedidos de transferência', 'SECRETARIA_ESCOLAR',
   'Aceite (escolhendo a turma) ou recuse cada pedido de transferência recebido pela unidade.',
   '3 dias após o pedido (referência da demonstração, a validar pela SEDUC).', '/rematricula?aba=transferencias', 14),
  ('REMATRICULA_ACOMPANHAR', 'Matrícula e cadastro', 'Acompanhar rematrículas sem resposta', 'SECRETARIA_ESCOLAR',
   'Contate as famílias que ainda não confirmaram a rematrícula e registre a resposta.', 'Prazo de rematrícula da rede.', '/rematricula', 15),
  ('CADASTRO_INCOMPLETO', 'Matrícula e cadastro', 'Completar cadastros de alunos', 'SECRETARIA_ESCOLAR',
   'Complete sexo, cor/raça, naturalidade, filiação, certidão ou CPF, endereço e responsável dos alunos da unidade.',
   'Sem prazo; conta para a qualidade do Censo Escolar.', '/alunos?pendentes=1', 16),
  ('PROTOCOLOS_UNIDADE', 'Atendimento', 'Responder protocolos encaminhados à unidade', 'SECRETARIA_ESCOLAR',
   'Responda os protocolos que a Central ou a IARA encaminharam à secretaria da unidade.', 'Prazo do serviço no catálogo (SLA).', '/atendimentos', 20),
  ('CONVERSAS_UNIDADE', 'Atendimento', 'Atender famílias que pediram atendimento humano', 'SECRETARIA_ESCOLAR',
   'Assuma a conversa em Conversas e responda à família.', '30 minutos após o pedido de atendimento humano.', '/iara', 21),
  ('PROTOCOLOS_REDE', 'Atendimento', 'Responder protocolos do setor', null,
   'Responda os protocolos encaminhados ao setor; os vencidos primeiro.', 'Prazo do serviço no catálogo (SLA).', '/atendimentos', 22),
  ('CONVERSAS_REDE', 'Atendimento', 'Atender conversas encaminhadas ao setor', null,
   'Assuma a conversa em Conversas e responda à família.', '30 minutos após o pedido de atendimento humano.', '/iara', 23),
  ('CHAMADA', 'Frequência e busca ativa', 'Lançar a chamada', 'PROFESSOR',
   'Abra a turma e registre a presença de cada aluno.', 'No mesmo dia, até as 18h (referência da demonstração, a validar pela SEDUC).', null, 30),
  ('JUSTIFICATIVAS_FALTA', 'Frequência e busca ativa', 'Avaliar justificativas de falta', 'SECRETARIA_ESCOLAR',
   'Aceite ou recuse as justificativas de falta enviadas pelas famílias.', '3 dias após o envio (referência da demonstração, a validar pela SEDUC).',
   '/frequencia?aba=justificativas', 31),
  ('ALERTAS_FREQUENCIA', 'Frequência e busca ativa', 'Tratar alertas de frequência', 'DIRETOR_UNIDADE',
   'Veja os alunos com faltas seguidas ou frequência baixa e registre a ação da escola.', '5 dias após o alerta (referência da demonstração, a validar pela SEDUC).',
   '/frequencia?aba=alertas', 32),
  ('BUSCA_ATIVA_SECRETARIA', 'Frequência e busca ativa', 'Cumprir tarefas da busca ativa', 'SECRETARIA_ESCOLAR',
   'Cumpra as tarefas abertas pela busca ativa (ligar, conferir telefone, envio alternativo) e registre o resultado.',
   'Prazo de cada tarefa, pela regra da busca ativa.', '/busca-ativa?painel=TAREFAS', 33),
  ('BUSCA_ATIVA_EQUIPE', 'Frequência e busca ativa', 'Cumprir tarefas da busca ativa (direção e equipe pedagógica)', 'DIRETOR_UNIDADE',
   'Cumpra as tarefas abertas pela busca ativa (reunião com a família, avaliação de risco, apoio do setor) e registre o resultado.',
   'Prazo de cada tarefa, pela regra da busca ativa.', '/busca-ativa?painel=TAREFAS', 34),
  ('ENCAMINHAMENTOS_APROVAR', 'Proteção e ocorrências', 'Aprovar encaminhamentos à rede de proteção', 'DIRETOR_UNIDADE',
   'Revise e aprove os encaminhamentos ao Conselho Tutelar e à rede de apoio.', '1 dia após a criação (referência da demonstração, a validar pela SEDUC).',
   '/busca-ativa?painel=ENCAMINHAMENTOS', 40),
  ('ENCAMINHAMENTOS_ENVIAR', 'Proteção e ocorrências', 'Enviar encaminhamentos aprovados', 'SECRETARIA_ESCOLAR',
   'Envie os encaminhamentos aprovados pelo canal do órgão e registre o protocolo.', '1 dia após a aprovação (referência da demonstração, a validar pela SEDUC).',
   '/busca-ativa?painel=ENCAMINHAMENTOS', 41),
  ('OCORRENCIA_UNIDADE', 'Proteção e ocorrências', 'Tratar ocorrência', 'DIRETOR_UNIDADE',
   'Registre as providências e solucione a ocorrência, ou encaminhe à SEDUC.', 'Grave: 2 dias; moderada: 5; leve: 10 (regra da rede).', '/ocorrencias', 42),
  ('OCORRENCIA_SEDUC', 'Proteção e ocorrências', 'Tratar ocorrência em 2ª instância', 'SUPERINTENDENCIA',
   'Analise a ocorrência encaminhada pela unidade ou pela família e registre a decisão.', '10 dias na 2ª instância (regra da rede).', '/ocorrencias?instancia=SECRETARIA', 43),
  ('REUNIAO_ENVIO', 'Proteção e ocorrências', 'Enviar registros de reunião aos órgãos', 'SECRETARIO',
   'Envie ao Conselho Tutelar, à Defensoria ou ao Ministério Público os registros de reunião com prazo vencido.',
   '2 dias após o preparo do envio (referência da demonstração, a validar pela SEDUC).', '/reunioes', 44),
  ('AULAS_REGISTRAR', 'Pedagógico', 'Registrar o conteúdo das aulas', 'PROFESSOR',
   'Registre no diário o conteúdo de cada aula dada.', '2 dias após a aula; o sistema aceita até 15 (referência da demonstração, a validar pela SEDUC).', null, 50),
  ('PLANOS_REAVALIAR', 'Pedagógico', 'Reavaliar planos de intervenção', 'PROFESSOR',
   'Reavalie os planos de intervenção dos alunos em risco e registre o resultado.', 'Data de reavaliação de cada plano.', null, 51),
  ('AEE_PLANOS', 'AEE e apoio', 'Concluir planos de AEE', 'PROFESSOR_AEE',
   'Conclua os planos de AEE em elaboração ou revisão.', '30 dias após o início (referência da demonstração, a validar pela SEDUC).', '/aee', 60),
  ('AEE_REVISAO', 'AEE e apoio', 'Revisar planos de AEE vencidos', 'PROFESSOR_AEE',
   'Revise os planos de AEE com a data de revisão vencida.', 'Data de revisão de cada plano.', '/aee', 61),
  ('APOIO_PEDIDOS', 'AEE e apoio', 'Analisar pedidos de apoio das famílias', 'DIRETOR_UNIDADE',
   'Analise o pedido da família e encaminhe ao apoio interdisciplinar, ou registre por que não.', '7 dias após o pedido (referência da demonstração, a validar pela SEDUC).',
   '/apoio?situacao=PEDIDO_FAMILIA', 62),
  ('APOIO_ATRIBUIR', 'AEE e apoio', 'Atribuir profissional aos casos encaminhados', 'GERENCIA_APOIO',
   'Distribua os casos encaminhados pelas escolas aos profissionais da área.', '30 dias após o encaminhamento.', '/apoio?situacao=ENCAMINHADO', 63),
  ('APOIO_TRIAGEM', 'AEE e apoio', 'Concluir a triagem dos casos', 'APOIO_INTERDISCIPLINAR',
   'Faça a triagem, registre a orientação à escola e à família e passe o caso para atendimento.', '15 dias após a atribuição (referência da demonstração, a validar pela SEDUC).',
   '/apoio', 64),
  ('UK_DECIDIR', 'Uniformes e kits', 'Decidir trocas e reposições de uniforme', 'SECRETARIA_ESCOLAR',
   'Aprove ou negue os pedidos de troca de tamanho e de reposição feitos pelas famílias.', '5 dias após o pedido (referência da demonstração, a validar pela SEDUC).',
   '/uniformes?aba=pedidos', 70),
  ('UK_VENCIDAS', 'Uniformes e kits', 'Contatar famílias com retirada vencida', 'SECRETARIA_ESCOLAR',
   'Ligue para as famílias que não retiraram uniforme e kit no prazo. Depois de 15 dias, a lista vai ao Conselho Tutelar.',
   '15 dias após o vencimento da retirada.', '/uniformes?aba=alunos', 71),
  ('UK_ADAPTADO', 'Uniformes e kits', 'Decidir pedidos de material adaptado', 'ALMOXARIFADO',
   'Decida os pedidos de material escolar adaptado para alunos do AEE.', '10 dias após o pedido (referência da demonstração, a validar pela SEDUC).',
   '/uniformes?aba=pedidos', 72),
  ('MANUTENCAO_VALIDAR', 'Materiais e manutenção', 'Validar serviço de manutenção', 'DIRETOR_UNIDADE',
   'Confira o serviço concluído e valide, ou reabra o chamado.', '5 dias após a conclusão (referência da demonstração, a validar pela SEDUC).', null, 80),
  ('MANUTENCAO_ATENDER', 'Materiais e manutenção', 'Atender chamado de manutenção', 'MANUTENCAO',
   'Avance o chamado (triagem, vistoria, orçamento, execução) até a conclusão.', 'Urgente 24 h, alta 3 dias, média 10, baixa 30 (regra do sistema).', null, 81),
  ('PEDIDO_RECEBER', 'Materiais e manutenção', 'Receber e conferir pedido', 'SECRETARIA_ESCOLAR',
   'Confira os itens entregues e registre o recebimento, ou a divergência.', 'Dia seguinte à previsão de entrega.', '/materiais?aba=pedidos', 82),
  ('PEDIDOS_DECIDIR', 'Materiais e manutenção', 'Decidir pedidos de material', 'ALMOXARIFADO',
   'Aprove ou recuse os pedidos de material das unidades.', '2 dias após o pedido (referência da demonstração, a validar pela SEDUC).', '/materiais?aba=pedidos', 83),
  ('PEDIDOS_DESPACHAR', 'Materiais e manutenção', 'Despachar pedidos aprovados', 'ALMOXARIFADO',
   'Separe e despache os pedidos aprovados.', '3 dias após a aprovação (referência da demonstração, a validar pela SEDUC).', '/materiais?aba=pedidos', 84),
  ('PONTO_JUSTIFICATIVAS', 'Pessoal', 'Tratar justificativas de ponto', 'DIRETOR_UNIDADE',
   'Aceite ou recuse as justificativas de ponto da equipe; o mês só fecha sem justificativa pendente.',
   '3 dias após o envio (referência da demonstração, a validar pela SEDUC).', '/ponto/equipe', 90),
  ('RESTRICOES_VALIDAR', 'Merenda', 'Validar restrições alimentares', 'NUTRICAO',
   'Valide as restrições alimentares informadas pelas unidades e famílias, com o laudo.', '5 dias após o registro (referência da demonstração, a validar pela SEDUC).',
   '/nutricao', 100),
  ('FROTA_DOCUMENTOS', 'Transporte', 'Renovar documentos da frota', 'TRANSPORTE',
   'Providencie a vistoria dos veículos e a renovação de CNH e curso dos motoristas antes do vencimento.', 'Data de validade de cada documento.', '/transporte', 110),
  ('SUPORTE_ATENDER', 'Suporte técnico', 'Atender chamados de suporte', 'INOVACAO',
   'Atenda os chamados de suporte técnico das unidades e da SEDUC.', 'Urgente 4 h, alta 1 dia, normal 3, baixa 5 (regra do sistema).', '/suporte', 120)
on conflict (codigo) do update set modulo = excluded.modulo, titulo = excluded.titulo, papel = excluded.papel, procedimento = excluded.procedimento,
  prazo_regra = excluded.prazo_regra, rota = excluded.rota, ordem = excluded.ordem;

-- prazo às 18h do dia (horário de Brasília)
create or replace function iara.pend_dia(p_dia date) returns timestamptz
language sql stable as $$ select ((p_dia::timestamp + time '18:00') at time zone 'America/Sao_Paulo') $$;

create or replace function iara.pend_ate(p_ts timestamptz, p_dias integer) returns timestamptz
language sql stable as $$ select iara.pend_dia((p_ts at time zone 'America/Sao_Paulo')::date + p_dias) $$;

-- equipe do protocolo/conversa → papel e setor
create or replace function iara.pend_time(p_team text, out papel text, out setor text, out rotulo text)
language sql immutable as $$
  select case p_team when 'CENTRAL_VAGAS' then 'ANALISTA_CENTRAL' when 'TRANSPORTE' then 'TRANSPORTE' when 'ALIMENTACAO' then 'NUTRICAO'
                     when 'AEE' then 'GERENCIA_APOIO' else 'ATENDIMENTO' end,
         case p_team when 'CENTRAL_VAGAS' then 'CV' when 'TRANSPORTE' then 'GTE' when 'ALIMENTACAO' then 'GME' when 'AEE' then 'GEE'
                     when 'OUVIDORIA' then 'OUV' when 'INTEGRAL' then 'GINT' else 'CA' end,
         case p_team when 'CENTRAL_VAGAS' then 'Central de Vagas' when 'TRANSPORTE' then 'Transporte escolar' when 'ALIMENTACAO' then 'Alimentação escolar'
                     when 'AEE' then 'Educação especial' when 'OUVIDORIA' then 'Ouvidoria' when 'INTEGRAL' then 'Educação integral'
                     when 'GESTAO' then 'Gestão' else 'Central de Atendimento' end
$$;

-- área do apoio → núcleo do organograma
create or replace function iara.pend_nucleo_apoio(p_area text) returns uuid
language sql stable security definer set search_path = iara, public as $$
  select iara.pend_setor(case p_area when 'ORIENTACAO_EDUCACIONAL' then 'GEE-OE' when 'ACOMPANHAMENTO_PEDAGOGICO' then 'GEE-AP'
    when 'EDUCACAO_ESPECIAL' then 'GEE-EEI' when 'FORMACAO' then 'GEE-FOR' when 'PSICOLOGIA' then 'GEE-PSI' when 'FONOAUDIOLOGIA' then 'GEE-FONO'
    when 'DEFICIENCIA_VISUAL' then 'GEE-DV' when 'ALTAS_HABILIDADES' then 'GEE-AHSD' else 'GEE' end)
$$;

-- professor(a) regente de cada turma ativa (o principal, se houver mais de um)
create or replace function iara.pend_regentes(p_unit integer) returns table (class_id uuid, unit_id integer, class_name text, staff_id uuid)
language sql stable security definer set search_path = iara, public as $$
  select distinct on (c.id) c.id, c.unit_id, c.class_name, cs.staff_id
  from iara.classes c join iara.class_staff cs on cs.class_id = c.id
  where c.status = 'ATIVA' and cs.role_type = 'REGENTE' and (cs.end_date is null or cs.end_date >= current_date) and (p_unit is null or c.unit_id = p_unit)
  order by c.id, cs.is_primary desc, cs.start_date
$$;

create or replace function iara.pend_fontes(p_unit integer default null)
returns table (chave text, tipo text, titulo text, detalhe text, quantidade integer, papel text, unit_id integer, setor_id uuid, staff_id uuid,
               prazo timestamptz, rota text, ref_id text, desde timestamptz)
language plpgsql stable security definer set search_path = iara, public as $$
declare
  v_unid uuid := iara.pend_setor('UNID');
  v_eei uuid := iara.pend_setor('GEE-EEI');
  v_hoje date := iara.hoje_local();
  v_agora_local timestamp := now() at time zone 'America/Sao_Paulo';
  v_remat date := coalesce(nullif(iara.setting('rematricula_prazo'), '')::date, make_date(extract(year from iara.hoje_local())::int, 11, 27));
  v_rede boolean := p_unit is null;
begin
  -- ===== Secretaria escolar =====
  return query
  with d as (
    select a.unit_id, doc.received_at em from iara.documents doc cross join lateral iara.aluno_area(doc.student_id) a
    where doc.status = 'RECEBIDO' and doc.student_id is not null and a.area = 'UNIDADE'
    union all
    select ac.unit_id, ac.created_at from iara.alteracoes_cadastrais ac where ac.situacao = 'PENDENTE' and ac.area = 'UNIDADE')
  select 'DOC:' || d.unit_id, 'VALIDAR_DOCUMENTOS', 'Validar documentos e alterações enviados pelas famílias',
         format('%s envio(s) esperando conferência; o mais antigo chegou em %s.', count(*), to_char(min(d.em) at time zone 'America/Sao_Paulo', 'DD/MM')),
         count(*)::int, 'SECRETARIA_ESCOLAR', d.unit_id, v_unid, null::uuid, iara.pend_ate(min(d.em), 3), '/validacoes', null::text, min(d.em)
  from d where d.unit_id is not null and (v_rede or d.unit_id = p_unit) group by d.unit_id;

  return query
  select 'MAT:' || o.unit_id, 'CONFIRMAR_MATRICULA', 'Confirmar matrículas aceitas pelas famílias',
         format('%s vaga(s) aceita(s) esperando a conferência dos documentos e a confirmação da matrícula.', count(*)),
         count(*)::int, 'SECRETARIA_ESCOLAR', o.unit_id, v_unid, null::uuid, iara.pend_ate(min(coalesce(o.accepted_at, o.updated_at)), 3), '/ofertas', null::text,
         min(coalesce(o.accepted_at, o.updated_at))
  from iara.vacancy_offers o where o.status = 'ACCEPTED' and (v_rede or o.unit_id = p_unit) group by o.unit_id;

  return query
  select 'TRF:' || t.unit_destino, 'TRANSFERENCIA_RESPONDER', 'Responder pedidos de transferência',
         format('%s pedido(s) de transferência para a unidade esperando resposta.', count(*)),
         count(*)::int, 'SECRETARIA_ESCOLAR', t.unit_destino, v_unid, null::uuid, iara.pend_ate(min(t.criada_em), 3), '/rematricula?aba=transferencias', null::text, min(t.criada_em)
  from iara.transferencias t where t.situacao = 'AGUARDANDO_DESTINO' and t.unit_destino is not null and (v_rede or t.unit_destino = p_unit) group by t.unit_destino;

  return query
  select 'REM:' || r.unit_origem, 'REMATRICULA_ACOMPANHAR', 'Acompanhar rematrículas sem resposta',
         format('%s aluno(s) ainda sem confirmação de rematrícula; o prazo da rede termina em %s.', count(*), to_char(v_remat, 'DD/MM')),
         count(*)::int, 'SECRETARIA_ESCOLAR', r.unit_origem, v_unid, null::uuid, iara.pend_dia(v_remat), '/rematricula', null::text, min(r.gerada_em)
  from iara.rematriculas r where r.situacao = 'PENDENTE' and r.unit_origem is not null and (v_rede or r.unit_origem = p_unit) group by r.unit_origem;

  return query
  select 'CAD:' || e.unit_id, 'CADASTRO_INCOMPLETO', 'Completar cadastros de alunos',
         format('%s aluno(s) com o cadastro incompleto.', count(*)), count(*)::int, 'SECRETARIA_ESCOLAR', e.unit_id, v_unid, null::uuid,
         null::timestamptz, '/alunos?pendentes=1', null::text, null::timestamptz
  from iara.enrollments e join iara.students s on s.id = e.student_id
  where e.status = 'ACTIVE' and (v_rede or e.unit_id = p_unit)
    and cardinality(iara.aluno_pendencias(s, exists (select 1 from iara.student_guardians sg where sg.student_id = s.id and sg.end_date is null))) > 0
  group by e.unit_id;

  return query
  select 'PRU:' || c.unit_id, 'PROTOCOLOS_UNIDADE', 'Responder protocolos encaminhados à unidade',
         format('%s protocolo(s) em aberto; %s com prazo vencido.', count(*), count(*) filter (where c.sla_due_at < now())),
         count(*)::int, 'SECRETARIA_ESCOLAR', c.unit_id, v_unid, null::uuid, min(c.sla_due_at), '/atendimentos', null::text, min(c.opened_at)
  from iara.service_cases c
  where c.status not in ('ENCERRADO', 'MATRICULA_CONCLUIDA', 'NAO_ATENDIDO') and c.assigned_team = 'SECRETARIA_ESCOLAR' and c.unit_id is not null
    and (v_rede or c.unit_id = p_unit)
  group by c.unit_id;

  return query
  select 'CVU:' || c.unit_id, 'CONVERSAS_UNIDADE', 'Atender famílias que pediram atendimento humano',
         format('%s conversa(s) esperando a secretaria.', count(*)), count(*)::int, 'SECRETARIA_ESCOLAR', c.unit_id, v_unid, null::uuid,
         min(coalesce(c.handoff_at, c.updated_at)) + interval '30 minutes', '/iara', null::text, min(coalesce(c.handoff_at, c.updated_at))
  from iara.conversations c
  where c.state = 'HUMAN_PENDING' and c.unit_id is not null and coalesce(c.team, 'SECRETARIA_ESCOLAR') = 'SECRETARIA_ESCOLAR' and (v_rede or c.unit_id = p_unit)
  group by c.unit_id;

  return query
  select 'JUS:' || e.unit_id, 'JUSTIFICATIVAS_FALTA', 'Avaliar justificativas de falta',
         format('%s justificativa(s) enviada(s) pelas famílias.', count(*)), count(*)::int, 'SECRETARIA_ESCOLAR', e.unit_id, v_unid, null::uuid,
         iara.pend_ate(min(j.created_at), 3), '/frequencia?aba=justificativas', null::text, min(j.created_at)
  from iara.frequencia_justificativas j join iara.enrollments e on e.student_id = j.student_id and e.status = 'ACTIVE'
  where j.situacao = 'ENVIADA' and (v_rede or e.unit_id = p_unit)
  group by e.unit_id;

  return query
  select 'BA:' || pp || ':' || t.unit_id, case when pp = 'SECRETARIA_ESCOLAR' then 'BUSCA_ATIVA_SECRETARIA' else 'BUSCA_ATIVA_EQUIPE' end,
         'Cumprir tarefas da busca ativa',
         format('%s tarefa(s) em aberto (%s).', count(*), string_agg(distinct lower(replace(t.tipo, '_', ' ')), ', ')),
         count(*)::int, pp, t.unit_id, v_unid, null::uuid, iara.pend_dia(min(t.prazo)), '/busca-ativa?painel=TAREFAS', null::text, min(t.created_at)
  from iara.frequencia_tarefas t
  cross join lateral (select case when t.destino = 'SECRETARIA_UNIDADE' then 'SECRETARIA_ESCOLAR' else 'DIRETOR_UNIDADE' end pp) x
  where t.situacao = 'ABERTA' and t.destino in ('SECRETARIA_UNIDADE', 'DIRECAO', 'EQUIPE_PEDAGOGICA') and t.unit_id is not null and (v_rede or t.unit_id = p_unit)
  group by pp, t.unit_id;

  return query
  select 'ENV:' || e.unit_id, 'ENCAMINHAMENTOS_ENVIAR', 'Enviar encaminhamentos aprovados',
         format('%s encaminhamento(s) aprovado(s) esperando o envio ao órgão.', count(*)), count(*)::int, 'SECRETARIA_ESCOLAR', e.unit_id, v_unid, null::uuid,
         iara.pend_ate(min(coalesce(e.aprovado_em, e.created_at)), 1), '/busca-ativa?painel=ENCAMINHAMENTOS', null::text, min(coalesce(e.aprovado_em, e.created_at))
  from iara.encaminhamentos e where e.situacao in ('APROVADO', 'FALHA_ENVIO') and e.unit_id is not null and (v_rede or e.unit_id = p_unit)
  group by e.unit_id;

  return query
  select 'UKD:' || n.unit_id, 'UK_DECIDIR', 'Decidir trocas e reposições de uniforme',
         format('%s pedido(s) das famílias (%s troca(s), %s reposição(ões)).', count(*), count(*) filter (where n.tipo = 'TROCA_TAMANHO'), count(*) filter (where n.tipo = 'REPOSICAO')),
         count(*)::int, 'SECRETARIA_ESCOLAR', n.unit_id, v_unid, null::uuid, iara.pend_ate(min(n.created_at), 5), '/uniformes?aba=pedidos', null::text, min(n.created_at)
  from iara.uk_necessidades n where n.situacao = 'AGUARDANDO_DECISAO' and n.tipo in ('TROCA_TAMANHO', 'REPOSICAO') and (v_rede or n.unit_id = p_unit)
  group by n.unit_id;

  return query
  select 'UKV:' || n.unit_id, 'UK_VENCIDAS', 'Contatar famílias com retirada vencida',
         format('%s aluno(s) com uniforme ou kit liberado e não retirado no prazo.', count(distinct n.student_id)),
         count(distinct n.student_id)::int, 'SECRETARIA_ESCOLAR', n.unit_id, v_unid, null::uuid, iara.pend_dia(min(n.prazo_retirada) + 15), '/uniformes?aba=alunos', null::text,
         iara.pend_dia(min(n.prazo_retirada))
  from iara.uk_necessidades n where n.situacao = 'DISPONIVEL' and n.prazo_retirada < v_hoje and (v_rede or n.unit_id = p_unit)
  group by n.unit_id;

  return query
  select 'PED:' || p.id, 'PEDIDO_RECEBER', 'Receber e conferir o pedido ' || p.numero,
         format('Despachado em %s; previsão de entrega %s.', to_char(p.despachado_em at time zone 'America/Sao_Paulo', 'DD/MM'), coalesce(to_char(p.previsao_entrega, 'DD/MM'), 'não informada')),
         null::int, 'SECRETARIA_ESCOLAR', p.unit_id, v_unid, null::uuid,
         iara.pend_dia(coalesce(p.previsao_entrega, (p.despachado_em at time zone 'America/Sao_Paulo')::date + 3) + 1), '/materiais?aba=pedidos', p.id::text, p.despachado_em
  from iara.pedidos p where p.situacao = 'EM_TRANSPORTE' and p.unit_id is not null and (v_rede or p.unit_id = p_unit);

  -- ===== Direção =====
  return query
  select 'ALF:' || a.unit_id, 'ALERTAS_FREQUENCIA', 'Tratar alertas de frequência',
         format('%s aluno(s) com faltas seguidas ou frequência baixa sem ação registrada.', count(*)), count(*)::int, 'DIRETOR_UNIDADE', a.unit_id, v_unid, null::uuid,
         iara.pend_ate(min(a.detectado_em), 5), '/frequencia?aba=alertas', null::text, min(a.detectado_em)
  from iara.frequencia_alertas a where a.situacao = 'ABERTO' and a.unit_id is not null and (v_rede or a.unit_id = p_unit)
  group by a.unit_id;

  return query
  select 'ENA:' || e.unit_id, 'ENCAMINHAMENTOS_APROVAR', 'Aprovar encaminhamentos à rede de proteção',
         format('%s encaminhamento(s) esperando aprovação (%s obrigatório(s)).', count(*), count(*) filter (where e.obrigatorio)), count(*)::int, 'DIRETOR_UNIDADE', e.unit_id, v_unid, null::uuid,
         iara.pend_ate(min(e.created_at), 1), '/busca-ativa?painel=ENCAMINHAMENTOS', null::text, min(e.created_at)
  from iara.encaminhamentos e where e.situacao = 'AGUARDANDO_APROVACAO' and e.unit_id is not null and (v_rede or e.unit_id = p_unit)
  group by e.unit_id;

  return query
  select 'OCO:' || o.id, 'OCORRENCIA_UNIDADE',
         case when o.sigilosa then 'Ocorrência sigilosa de ' else format('Ocorrência %s de ', lower(coalesce(o.gravidade, ''))) end || to_char(o.ocorrida_em at time zone 'America/Sao_Paulo', 'DD/MM'),
         case when o.sigilosa then 'Detalhes só na tela de ocorrências.' else lower(replace(coalesce(o.tipo, ''), '_', ' ')) end,
         null::int, 'DIRETOR_UNIDADE', o.unit_id, v_unid, null::uuid, iara.pend_dia(coalesce(o.prazo, (o.created_at at time zone 'America/Sao_Paulo')::date + 10)),
         '/ocorrencias', o.id::text, o.created_at
  from iara.ocorrencias o
  where o.situacao in ('ABERTA', 'EM_ACOMPANHAMENTO') and o.instancia = 'UNIDADE' and o.unit_id is not null and (v_rede or o.unit_id = p_unit);

  return query
  select 'PON:' || j.unit_id, 'PONTO_JUSTIFICATIVAS', 'Tratar justificativas de ponto',
         format('%s justificativa(s) de ponto da equipe esperando decisão.', count(*)), count(*)::int, 'DIRETOR_UNIDADE', j.unit_id, v_unid, null::uuid,
         iara.pend_ate(min(j.enviada_em), 3), '/ponto/equipe', null::text, min(j.enviada_em)
  from iara.ponto_justificativas j where j.situacao = 'PENDENTE' and j.unit_id is not null and (v_rede or j.unit_id = p_unit)
  group by j.unit_id;

  return query
  select 'APF:' || c.unit_id, 'APOIO_PEDIDOS', 'Analisar pedidos de apoio das famílias',
         format('%s pedido(s) de avaliação feitos pelas famílias.', count(*)), count(*)::int, 'DIRETOR_UNIDADE', c.unit_id, v_unid, null::uuid,
         iara.pend_ate(min(c.created_at), 7), '/apoio?situacao=PEDIDO_FAMILIA', null::text, min(c.created_at)
  from iara.apoio_casos c where c.situacao = 'PEDIDO_FAMILIA' and c.unit_id is not null and (v_rede or c.unit_id = p_unit)
  group by c.unit_id;

  return query
  select 'MNV:' || m.id, 'MANUTENCAO_VALIDAR', 'Validar o serviço do chamado ' || m.protocolo,
         format('%s · %s · concluído em %s.', lower(replace(coalesce(m.categoria, ''), '_', ' ')), coalesce(m.local, ''), to_char(m.concluido_em at time zone 'America/Sao_Paulo', 'DD/MM')),
         null::int, 'DIRETOR_UNIDADE', m.unit_id, v_unid, null::uuid, iara.pend_ate(coalesce(m.concluido_em, now()), 5), '/manutencao/' || m.id, m.id::text, m.concluido_em
  from iara.manutencao_chamados m where m.situacao = 'CONCLUIDO' and m.unit_id is not null and (v_rede or m.unit_id = p_unit);

  -- ===== Professores (pessoa) =====
  return query
  with dias as (
    select u.id unit_id, d::date dia, row_number() over (partition by u.id order by d desc) n
    from iara.education_units u cross join generate_series(v_hoje - 10, v_hoje, interval '1 day') d
    where u.status = 'ATIVA' and (v_rede or u.id = p_unit) and iara.dia_letivo(d::date, u.id)
      and (d::date < v_hoje or v_agora_local::time >= time '07:00'))
  select 'CHAMADA:' || r.class_id || ':' || dd.dia, 'CHAMADA',
         format('Lançar a chamada — %s (%s)', r.class_name, case when dd.dia = v_hoje then 'hoje' else to_char(dd.dia, 'DD/MM') end),
         null::text, null::int, 'PROFESSOR', r.unit_id, v_unid, r.staff_id, iara.pend_dia(dd.dia), '/turmas/' || r.class_id || '/chamada', r.class_id::text,
         ((dd.dia::timestamp + time '07:00') at time zone 'America/Sao_Paulo')
  from iara.pend_regentes(p_unit) r join dias dd on dd.unit_id = r.unit_id and dd.n <= 4
  where not exists (select 1 from iara.frequencia_registros f where f.class_id = r.class_id and f.data = dd.dia);

  return query
  with prev as (
    select c.id class_id, c.unit_id, c.class_name, ap.data, ap.aula, ap.staff_id
    from iara.classes c cross join lateral iara.aulas_previstas(c.id, v_hoje - 14, v_hoje - 1) ap
    where c.status = 'ATIVA' and (v_rede or c.unit_id = p_unit) and ap.staff_id is not null),
  falta as (
    select prev.* from prev where not exists (select 1 from iara.aulas_registros r where r.class_id = prev.class_id and r.data = prev.data and r.aula = prev.aula))
  select 'AULAS:' || f.staff_id || ':' || f.class_id, 'AULAS_REGISTRAR', 'Registrar o conteúdo das aulas — ' || min(f.class_name),
         format('%s aula(s) sem registro nos últimos 14 dias; a mais antiga em %s.', count(*), to_char(min(f.data), 'DD/MM')),
         count(*)::int, 'PROFESSOR', min(f.unit_id), v_unid, f.staff_id, iara.pend_dia(min(f.data) + 2), '/turmas/' || f.class_id || '/diario', f.class_id::text,
         ((min(f.data)::timestamp + time '18:00') at time zone 'America/Sao_Paulo')
  from falta f group by f.staff_id, f.class_id;

  return query
  select 'PLA:' || p.class_id, 'PLANOS_REAVALIAR', 'Reavaliar planos de intervenção — ' || min(r.class_name),
         format('%s plano(s) com a reavaliação vencida ou nos próximos 7 dias.', count(*)), count(*)::int, 'PROFESSOR', min(r.unit_id), v_unid, min(r.staff_id::text)::uuid,
         iara.pend_dia(min(p.reavaliar_em)), '/turmas/' || p.class_id || '/avaliacao', p.class_id::text, null::timestamptz
  from iara.planos_intervencao p join iara.pend_regentes(p_unit) r on r.class_id = p.class_id
  where p.situacao = 'ATIVO' and p.reavaliar_em < v_hoje + 7
  group by p.class_id;

  -- ===== AEE (pessoa) =====
  return query
  select 'AEP:' || a.profissional_id, 'AEE_PLANOS', 'Concluir planos de AEE',
         format('%s plano(s) em elaboração ou revisão.', count(*)), count(*)::int, 'PROFESSOR_AEE', min(s.unit_id), v_eei, a.profissional_id,
         iara.pend_ate(min(a.created_at), 30), '/aee', null::text, min(a.created_at)
  from iara.aee_planos a join iara.staff s on s.id = a.profissional_id
  where a.situacao in ('EM_ELABORACAO', 'EM_REVISAO') and (v_rede or s.unit_id = p_unit)
  group by a.profissional_id;

  return query
  select 'AER:' || a.profissional_id, 'AEE_REVISAO', 'Revisar planos de AEE vencidos',
         format('%s plano(s) com a data de revisão vencida.', count(*)), count(*)::int, 'PROFESSOR_AEE', min(s.unit_id), v_eei, a.profissional_id,
         iara.pend_dia(min(a.revisar_em)), '/aee', null::text, null::timestamptz
  from iara.aee_planos a join iara.staff s on s.id = a.profissional_id
  where a.situacao = 'ATIVO' and a.revisar_em < v_hoje and (v_rede or s.unit_id = p_unit)
  group by a.profissional_id;

  if not v_rede then return; end if;

  -- ===== SEDUC (sem unidade: a chefia acompanha pelo setor) =====
  return query
  with d as (
    select doc.received_at em from iara.documents doc cross join lateral iara.aluno_area(doc.student_id) a
    where doc.status = 'RECEBIDO' and doc.student_id is not null and a.area = 'CENTRAL'
    union all
    select ac.created_at from iara.alteracoes_cadastrais ac where ac.situacao = 'PENDENTE' and ac.area = 'CENTRAL')
  select 'DOCC', 'VALIDAR_CENTRAL', 'Validar documentos de quem ainda não está matriculado',
         format('%s envio(s) esperando conferência na Central.', count(*)), count(*)::int, 'ANALISTA_CENTRAL', null::int, iara.pend_setor('CV'), null::uuid,
         iara.pend_ate(min(d.em), 3), '/validacoes', null::text, min(d.em)
  from d having count(*) > 0;

  return query
  select 'OFERTAR', 'PRONTO_OFERTAR', 'Ofertar vagas a quem está em 1º lugar na fila',
         format('%s criança(s) em 1º lugar com vaga livre na unidade e série pedidas.', count(*)), count(*)::int, 'ANALISTA_CENTRAL', null::int, iara.pend_setor('CV'), null::uuid,
         null::timestamptz, '/fila', null::text, null::timestamptz
  from iara.waiting_list_entries w
  where w.status = 'WAITING' and w.position = 1
    and exists (select 1 from iara.classes c where c.unit_id = w.preferred_unit_id and c.grade_level_id = w.grade_level_id and c.offerable_vacancies_count > 0)
  having count(*) > 0;

  return query
  select 'PRR:' || coalesce(c.assigned_team, 'ATENDIMENTO'), 'PROTOCOLOS_REDE', 'Responder protocolos — ' || (iara.pend_time(c.assigned_team)).rotulo,
         format('%s protocolo(s) em aberto; %s com prazo vencido.', count(*), count(*) filter (where c.sla_due_at < now())),
         count(*)::int, (iara.pend_time(c.assigned_team)).papel, null::int, iara.pend_setor((iara.pend_time(c.assigned_team)).setor), null::uuid,
         min(c.sla_due_at), '/atendimentos', null::text, min(c.opened_at)
  from iara.service_cases c
  where c.status not in ('ENCERRADO', 'MATRICULA_CONCLUIDA', 'NAO_ATENDIDO') and coalesce(c.assigned_team, '') <> 'SECRETARIA_ESCOLAR'
  group by c.assigned_team;

  return query
  select 'CVR:' || c.team, 'CONVERSAS_REDE', 'Atender conversas — ' || (iara.pend_time(c.team)).rotulo,
         format('%s conversa(s) esperando o setor.', count(*)), count(*)::int, (iara.pend_time(c.team)).papel, null::int, iara.pend_setor((iara.pend_time(c.team)).setor), null::uuid,
         min(coalesce(c.handoff_at, c.updated_at)) + interval '30 minutes', '/iara', null::text, min(coalesce(c.handoff_at, c.updated_at))
  from iara.conversations c where c.state = 'HUMAN_PENDING' and c.team is not null and c.team <> 'SECRETARIA_ESCOLAR'
  group by c.team;

  return query
  select 'OCS:' || o.id, 'OCORRENCIA_SEDUC',
         case when o.sigilosa then 'Ocorrência sigilosa de ' else format('Ocorrência %s de ', lower(coalesce(o.gravidade, ''))) end || to_char(o.ocorrida_em at time zone 'America/Sao_Paulo', 'DD/MM'),
         (select u.short_name from iara.education_units u where u.id = o.unit_id) || case when o.sigilosa then ' · detalhes só na tela de ocorrências.' else ' · ' || lower(replace(coalesce(o.tipo, ''), '_', ' ')) end,
         null::int, 'SUPERINTENDENCIA', null::int, iara.pend_setor('SUP'), null::uuid,
         iara.pend_dia(coalesce(o.prazo, (coalesce(o.encaminhada_seduc_em, o.created_at) at time zone 'America/Sao_Paulo')::date + 10)), '/ocorrencias?instancia=SECRETARIA', o.id::text,
         coalesce(o.encaminhada_seduc_em, o.created_at)
  from iara.ocorrencias o where o.situacao in ('ABERTA', 'EM_ACOMPANHAMENTO') and o.instancia = 'SECRETARIA';

  return query
  select 'REO', 'REUNIAO_ENVIO', 'Enviar registros de reunião aos órgãos',
         format('%s envio(s) preparado(s) esperando o Secretário.', count(*)), count(*)::int, 'SECRETARIO', null::int, iara.pend_setor('SEDUC'), null::uuid,
         iara.pend_ate(min(r.preparado_em), 2), '/reunioes', null::text, min(r.preparado_em)
  from iara.reuniao_envios_orgaos r where r.situacao = 'AGUARDANDO_ENVIO' having count(*) > 0;

  return query
  select 'APA:' || c.area_codigo, 'APOIO_ATRIBUIR', 'Atribuir profissional — ' || coalesce(min(a.nome), c.area_codigo),
         format('%s caso(s) encaminhado(s) sem profissional; o mais antigo espera há %s dia(s).', count(*), v_hoje - min((coalesce(c.encaminhado_em, c.created_at) at time zone 'America/Sao_Paulo')::date)),
         count(*)::int, 'GERENCIA_APOIO', null::int, iara.pend_nucleo_apoio(c.area_codigo), null::uuid,
         iara.pend_ate(min(coalesce(c.encaminhado_em, c.created_at)), 30), '/apoio?situacao=ENCAMINHADO&area=' || c.area_codigo, null::text, min(coalesce(c.encaminhado_em, c.created_at))
  from iara.apoio_casos c left join iara.apoio_areas a on a.codigo = c.area_codigo
  where c.situacao = 'ENCAMINHADO' group by c.area_codigo;

  return query
  select 'APT:' || c.profissional_staff, 'APOIO_TRIAGEM', 'Concluir a triagem dos casos',
         format('%s caso(s) em triagem.', count(*)), count(*)::int, 'APOIO_INTERDISCIPLINAR', null::int,
         coalesce((select v.setor_id from iara.org_vinculos v where v.staff_id = c.profissional_staff and v.fim is null order by v.chefia desc limit 1), iara.pend_setor('GEE')),
         c.profissional_staff, iara.pend_ate(min(coalesce(c.atribuido_em, c.created_at)), 15), '/apoio', null::text, min(coalesce(c.atribuido_em, c.created_at))
  from iara.apoio_casos c where c.situacao = 'EM_TRIAGEM' and c.profissional_staff is not null group by c.profissional_staff;

  return query
  select 'MNA:' || m.id, 'MANUTENCAO_ATENDER', 'Chamado ' || m.protocolo || ' — ' || lower(replace(coalesce(m.categoria, ''), '_', ' ')),
         format('%s · %s · %s.', (select u.short_name from iara.education_units u where u.id = m.unit_id), lower(coalesce(m.prioridade, '')), lower(replace(m.situacao, '_', ' '))),
         null::int, 'MANUTENCAO', null::int, iara.pend_setor('DMAN'), null::uuid, m.prazo, '/manutencao/' || m.id, m.id::text, m.aberto_em
  from iara.manutencao_chamados m
  where m.situacao in ('ABERTO', 'TRIAGEM', 'VISTORIA', 'ORCAMENTO', 'AGUARDANDO_EXECUCAO', 'EM_EXECUCAO', 'REABERTO');

  return query
  select 'PDD', 'PEDIDOS_DECIDIR', 'Decidir pedidos de material', format('%s pedido(s) das unidades esperando aprovação.', count(*)), count(*)::int,
         'ALMOXARIFADO', null::int, iara.pend_setor('GSA'), null::uuid, iara.pend_ate(min(p.solicitado_em), 2), '/materiais?aba=pedidos', null::text, min(p.solicitado_em)
  from iara.pedidos p where p.situacao = 'ENVIADO' having count(*) > 0;

  return query
  select 'PDS', 'PEDIDOS_DESPACHAR', 'Despachar pedidos aprovados', format('%s pedido(s) aprovado(s) esperando o despacho.', count(*)), count(*)::int,
         'ALMOXARIFADO', null::int, iara.pend_setor('GSA'), null::uuid, iara.pend_ate(min(coalesce(p.decidido_em, p.solicitado_em)), 3), '/materiais?aba=pedidos', null::text,
         min(coalesce(p.decidido_em, p.solicitado_em))
  from iara.pedidos p where p.situacao = 'APROVADO' having count(*) > 0;

  return query
  select 'UKA', 'UK_ADAPTADO', 'Decidir pedidos de material adaptado', format('%s pedido(s) de material adaptado para alunos do AEE.', count(*)), count(*)::int,
         'ALMOXARIFADO', null::int, iara.pend_setor('GSA'), null::uuid, iara.pend_ate(min(n.created_at), 10), '/uniformes?aba=pedidos', null::text, min(n.created_at)
  from iara.uk_necessidades n where n.situacao = 'AGUARDANDO_DECISAO' and n.tipo = 'ADAPTADO' having count(*) > 0;

  return query
  select 'RES', 'RESTRICOES_VALIDAR', 'Validar restrições alimentares', format('%s restrição(ões) informada(s) esperando validação.', count(*)), count(*)::int,
         'NUTRICAO', null::int, iara.pend_setor('GME'), null::uuid, iara.pend_ate(min(r.created_at), 5), '/nutricao', null::text, min(r.created_at)
  from iara.aluno_restricoes r where r.situacao = 'INFORMADA' having count(*) > 0;

  return query
  with docs as (
    select vistoria_validade validade, 'vistoria' k from iara.transporte_veiculos where vistoria_validade < v_hoje + 30 and coalesce(situacao, 'ATIVO') not in ('INATIVO', 'BAIXADO')
    union all select cnh_validade, 'CNH' from iara.transporte_motoristas where cnh_validade < v_hoje + 30 and coalesce(situacao, 'ATIVO') not in ('INATIVO', 'DESLIGADO')
    union all select curso_validade, 'curso' from iara.transporte_motoristas where curso_validade < v_hoje + 30 and coalesce(situacao, 'ATIVO') not in ('INATIVO', 'DESLIGADO'))
  select 'FROTA', 'FROTA_DOCUMENTOS', 'Renovar documentos da frota',
         format('%s documento(s) vencido(s) ou vencendo em 30 dias: %s vistoria(s), %s CNH, %s curso(s).', count(*), count(*) filter (where k = 'vistoria'),
                count(*) filter (where k = 'CNH'), count(*) filter (where k = 'curso')),
         count(*)::int, 'TRANSPORTE', null::int, iara.pend_setor('GTE'), null::uuid, iara.pend_dia(min(validade)), '/transporte', null::text, null::timestamptz
  from docs having count(*) > 0;

  return query
  select 'SUP', 'SUPORTE_ATENDER', 'Atender chamados de suporte', format('%s chamado(s) em aberto; %s com prazo vencido.', count(*), count(*) filter (where s.prazo < now())),
         count(*)::int, 'INOVACAO', null::int, iara.pend_setor('DINOV'), null::uuid, min(s.prazo), '/suporte', null::text, min(s.created_at)
  from iara.suporte_chamados s where s.situacao in ('ABERTO', 'EM_ATENDIMENTO') having count(*) > 0;
end $$;

-- quando foi resolvida no módulo: o registro do próprio módulo, se houver (senão, agora)
create or replace function iara.pend_resolvida_em(p iara.pendencias) returns timestamptz
language sql stable security definer set search_path = iara, public as $$
  select least(now(), greatest(p.criada_em, coalesce(case p.tipo
    when 'CHAMADA' then (select f.registrado_em from iara.frequencia_registros f where f.class_id = p.ref_id::uuid and f.data = split_part(p.chave, ':', 3)::date)
    when 'OCORRENCIA_UNIDADE' then (select coalesce(o.solucao_em, o.encaminhada_seduc_em, o.alterada_em) from iara.ocorrencias o where o.id = p.ref_id::uuid)
    when 'OCORRENCIA_SEDUC' then (select coalesce(o.solucao_em, o.alterada_em) from iara.ocorrencias o where o.id = p.ref_id::uuid)
    when 'MANUTENCAO_ATENDER' then (select m.concluido_em from iara.manutencao_chamados m where m.id = p.ref_id::uuid)
    when 'MANUTENCAO_VALIDAR' then (select m.validado_em from iara.manutencao_chamados m where m.id = p.ref_id::uuid)
    when 'PEDIDO_RECEBER' then (select pe.recebido_em from iara.pedidos pe where pe.id = p.ref_id::uuid)
  end, now())))
$$;

-- histórico: reconstrói, a partir dos registros dos módulos, as pendências por item já resolvidas nos últimos dias
-- (chamadas, ocorrências, chamados de manutenção e recebimento de pedidos). Serve à implantação: as estatísticas nascem com passado.
create or replace function iara.pend_historico_reconstruir(p_dias integer default 84) returns jsonb
language plpgsql security definer set search_path = iara, public as $$
declare
  v_de timestamptz := now() - make_interval(days => p_dias);
  v_unid uuid := iara.pend_setor('UNID');
  n1 integer; n2 integer; n3 integer; n4 integer; n5 integer;
begin
  insert into iara.pendencias (origem, tipo, chave, titulo, papel, unit_id, setor_id, staff_id, prazo, rota, ref_id, situacao, criada_em, concluida_em, concluida_por_label, is_demo)
  select 'AUTOMATICA', 'CHAMADA', 'CHAMADA:' || f.class_id || ':' || f.data, format('Lançar a chamada — %s (%s)', r.class_name, to_char(f.data, 'DD/MM')),
         'PROFESSOR', r.unit_id, v_unid, r.staff_id, iara.pend_dia(f.data), '/turmas/' || f.class_id || '/chamada', f.class_id::text, 'CONCLUIDA',
         least((f.data::timestamp + time '07:00') at time zone 'America/Sao_Paulo', f.registrado_em - interval '10 minutes'), f.registrado_em,
         coalesce(f.registrado_label, 'Resolvida no módulo'), iara.demo_mode()
  from iara.frequencia_registros f join iara.pend_regentes(null) r on r.class_id = f.class_id
  where f.registrado_em > v_de and f.data < iara.hoje_local()
    and not exists (select 1 from iara.pendencias q where q.chave = 'CHAMADA:' || f.class_id || ':' || f.data);
  get diagnostics n1 = row_count;

  insert into iara.pendencias (origem, tipo, chave, titulo, detalhe, papel, unit_id, setor_id, prazo, rota, ref_id, situacao, criada_em, concluida_em, concluida_por_label, is_demo)
  select 'AUTOMATICA', case when o.instancia = 'SECRETARIA' then 'OCORRENCIA_SEDUC' else 'OCORRENCIA_UNIDADE' end,
         case when o.instancia = 'SECRETARIA' then 'OCS:' else 'OCO:' end || o.id,
         case when o.sigilosa then 'Ocorrência sigilosa de ' else format('Ocorrência %s de ', lower(coalesce(o.gravidade, ''))) end || to_char(o.ocorrida_em at time zone 'America/Sao_Paulo', 'DD/MM'),
         case when o.sigilosa then 'Detalhes só na tela de ocorrências.' else lower(replace(coalesce(o.tipo, ''), '_', ' ')) end,
         case when o.instancia = 'SECRETARIA' then 'SUPERINTENDENCIA' else 'DIRETOR_UNIDADE' end,
         case when o.instancia = 'SECRETARIA' then null else o.unit_id end, case when o.instancia = 'SECRETARIA' then iara.pend_setor('SUP') else v_unid end,
         iara.pend_dia(coalesce(o.prazo, (o.created_at at time zone 'America/Sao_Paulo')::date + 10)), '/ocorrencias', o.id::text, 'CONCLUIDA',
         o.created_at, greatest(o.created_at, o.solucao_em), coalesce(o.solucao_por_label, 'Resolvida no módulo'), iara.demo_mode()
  from iara.ocorrencias o
  where o.solucao_em > v_de and o.unit_id is not null
    and not exists (select 1 from iara.pendencias q where q.chave in ('OCO:' || o.id, 'OCS:' || o.id));
  get diagnostics n2 = row_count;

  insert into iara.pendencias (origem, tipo, chave, titulo, detalhe, papel, setor_id, prazo, rota, ref_id, situacao, criada_em, concluida_em, concluida_por_label, is_demo)
  select 'AUTOMATICA', 'MANUTENCAO_ATENDER', 'MNA:' || m.id, 'Chamado ' || m.protocolo || ' — ' || lower(replace(coalesce(m.categoria, ''), '_', ' ')),
         (select u.short_name from iara.education_units u where u.id = m.unit_id) || ' · ' || lower(coalesce(m.prioridade, '')),
         'MANUTENCAO', iara.pend_setor('DMAN'), m.prazo, '/manutencao/' || m.id, m.id::text, 'CONCLUIDA', m.aberto_em, greatest(m.aberto_em, m.concluido_em),
         coalesce(m.responsavel_label, 'Resolvida no módulo'), iara.demo_mode()
  from iara.manutencao_chamados m
  where m.concluido_em > v_de and not exists (select 1 from iara.pendencias q where q.chave = 'MNA:' || m.id);
  get diagnostics n3 = row_count;

  insert into iara.pendencias (origem, tipo, chave, titulo, papel, unit_id, setor_id, prazo, rota, ref_id, situacao, criada_em, concluida_em, concluida_por_label, is_demo)
  select 'AUTOMATICA', 'MANUTENCAO_VALIDAR', 'MNV:' || m.id, 'Validar o serviço do chamado ' || m.protocolo, 'DIRETOR_UNIDADE', m.unit_id, v_unid,
         iara.pend_ate(m.concluido_em, 5), '/manutencao/' || m.id, m.id::text, 'CONCLUIDA', m.concluido_em, greatest(m.concluido_em, m.validado_em), 'Resolvida no módulo', iara.demo_mode()
  from iara.manutencao_chamados m
  where m.validado_em > v_de and m.concluido_em is not null and m.unit_id is not null and not exists (select 1 from iara.pendencias q where q.chave = 'MNV:' || m.id);
  get diagnostics n4 = row_count;

  insert into iara.pendencias (origem, tipo, chave, titulo, papel, unit_id, setor_id, prazo, rota, ref_id, situacao, criada_em, concluida_em, concluida_por_label, is_demo)
  select 'AUTOMATICA', 'PEDIDO_RECEBER', 'PED:' || pe.id, 'Receber e conferir o pedido ' || pe.numero, 'SECRETARIA_ESCOLAR', pe.unit_id, v_unid,
         iara.pend_dia(coalesce(pe.previsao_entrega, (pe.despachado_em at time zone 'America/Sao_Paulo')::date + 3) + 1), '/materiais?aba=pedidos', pe.id::text, 'CONCLUIDA',
         coalesce(pe.despachado_em, pe.recebido_em), pe.recebido_em, coalesce(pe.conferido_por_label, 'Resolvida no módulo'), iara.demo_mode()
  from iara.pedidos pe
  where pe.recebido_em > v_de and pe.unit_id is not null and not exists (select 1 from iara.pendencias q where q.chave = 'PED:' || pe.id);
  get diagnostics n5 = row_count;
  return jsonb_build_object('chamadas', n1, 'ocorrencias', n2, 'manutencao', n3, 'validacoes', n4, 'pedidos', n5);
end $$;

-- 10. Sincronização: abre o que apareceu, atualiza o que mudou e fecha o que foi resolvido no módulo -------------------------------------
create or replace function iara.pend_sincronizar(p_unit integer default null) returns jsonb
language plpgsql security definer set search_path = iara, public as $$
declare
  v_escopo text := coalesce(p_unit::text, '*');
  v jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtext('iara.pend_sinc:' || v_escopo)) then
    return jsonb_build_object('ocupado', true);
  end if;
  with atual as materialized (
    select distinct on (f.chave) f.* from iara.pend_fontes(p_unit) f
    join iara.pend_tipos t on t.codigo = f.tipo and t.ativo
    order by f.chave),
  upd as (
    update iara.pendencias p set titulo = a.titulo, detalhe = a.detalhe, quantidade = a.quantidade, prazo = a.prazo, rota = a.rota,
                                 staff_id = a.staff_id, setor_id = a.setor_id
    from atual a
    where p.chave = a.chave and p.origem = 'AUTOMATICA' and p.situacao = 'ABERTA'
      and (p.titulo, p.detalhe, p.quantidade, p.prazo, p.rota, p.staff_id, p.setor_id)
          is distinct from (a.titulo, a.detalhe, a.quantidade, a.prazo, a.rota, a.staff_id, a.setor_id)
    returning 1),
  ins as (
    insert into iara.pendencias (origem, tipo, chave, titulo, detalhe, quantidade, papel, unit_id, setor_id, staff_id, prazo, rota, ref_id, criada_em, is_demo)
    select 'AUTOMATICA', a.tipo, a.chave, a.titulo, a.detalhe, a.quantidade, a.papel, a.unit_id, a.setor_id, a.staff_id, a.prazo, a.rota, a.ref_id,
           least(now(), coalesce(a.desde, now())), iara.demo_mode()
    from atual a
    where not exists (select 1 from iara.pendencias p where p.chave = a.chave and p.origem = 'AUTOMATICA' and p.situacao = 'ABERTA')
    returning 1),
  fech as (
    update iara.pendencias p set situacao = 'CONCLUIDA', concluida_em = iara.pend_resolvida_em(p), concluida_por_label = 'Resolvida no módulo'
    where p.origem = 'AUTOMATICA' and p.situacao = 'ABERTA' and (p_unit is null or p.unit_id = p_unit)
      and not exists (select 1 from atual a where a.chave = p.chave)
    returning 1)
  select jsonb_build_object('atualizadas', (select count(*) from upd), 'novas', (select count(*) from ins), 'resolvidas', (select count(*) from fech),
                            'em', now()) into v;
  insert into iara.pend_sinc (escopo, em, resultado) values (v_escopo, now(), v)
  on conflict (escopo) do update set em = excluded.em, resultado = excluded.resultado;
  return v;
end $$;

-- sincroniza a unidade do usuário se a última passada tiver mais de 2 minutos; a rede inteira fica com a rotina (a cada 10)
create or replace function iara.pend_sincronizar_se_preciso(p_unit integer) returns void
language plpgsql security definer set search_path = iara, public as $$
declare
  v_rede timestamptz := coalesce((select em from iara.pend_sinc where escopo = '*'), '-infinity');
begin
  if p_unit is null then
    if v_rede < now() - interval '15 minutes' then perform iara.pend_sincronizar(null); end if;
  elsif v_rede < now() - interval '2 minutes'
        and coalesce((select em from iara.pend_sinc where escopo = p_unit::text), '-infinity') < now() - interval '2 minutes' then
    perform iara.pend_sincronizar(p_unit);
  end if;
end $$;

create or replace function iara.pend_rotina() returns jsonb
language plpgsql security definer set search_path = iara, public as $$
declare
  n integer;
  v jsonb;
begin
  n := iara.pend_rotinas_gerar(null);
  v := jsonb_build_object('procedimentos', n, 'sincronizacao', iara.pend_sincronizar(null));
  -- estatísticas de abertura prontas para o Prefeito (sem nomes) e para a SEDUC (com nomes)
  perform iara.pend_estat_calcular(30, null, null, false);
  perform iara.pend_estat_calcular(30, null, null, true);
  return v;
end $$;

-- 11. Minhas pendências --------------------------------------------------------------------------------------------------------------------
create or replace function api.pend_minhas(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public as $$
declare
  e record;
  v_sit text := coalesce(nullif(p ->> 'situacao', ''), 'ABERTAS');
  v_mod text := nullif(p ->> 'modulo', '');
  v jsonb;
begin
  perform iara.require_perm('pend.read');
  select * into e from iara.pend_eu();
  perform iara.pend_sincronizar_se_preciso(case when e.na_unidade then e.unit_id end);
  with minhas as materialized (
    select p.* from iara.pendencias p
    where iara.pend_minha(p.staff_id, p.papel, p.unit_id, e.papel, e.unit_id, e.staff_id, e.na_unidade)
      and (p.situacao = 'ABERTA' or p.concluida_em > now() - interval '30 days')),
  abertas as (select * from minhas where situacao = 'ABERTA')
  select jsonb_build_object(
    'eu', jsonb_build_object('nome', e.nome, 'papel', iara.pend_papel_rotulo(e.papel), 'chefia', e.chefia,
                             'unidade', (select short_name from iara.education_units where id = e.unit_id)),
    'resumo', jsonb_build_object(
      'abertas', (select count(*) from abertas),
      'atrasadas', (select count(*) from abertas where prazo < now()),
      'hoje', (select count(*) from abertas where prazo >= now() and (prazo at time zone 'America/Sao_Paulo')::date = iara.hoje_local()),
      'semana', (select count(*) from abertas where prazo >= now() and prazo < now() + interval '7 days'),
      'concluidas_7', (select count(*) from minhas where situacao = 'CONCLUIDA' and concluida_em > now() - interval '7 days'),
      'no_prazo_30', (select round(100.0 * count(*) filter (where concluida_em <= prazo) / nullif(count(*), 0)) from minhas
                      where situacao = 'CONCLUIDA' and prazo is not null)),
    'por_modulo', (select coalesce(jsonb_agg(jsonb_build_object('modulo', modulo, 'abertas', n, 'atrasadas', a) order by a desc, n desc), '[]')
                   from (select t.modulo, count(*) n, count(*) filter (where m.prazo < now()) a from abertas m join iara.pend_tipos t on t.codigo = m.tipo group by t.modulo) z),
    'itens', (select coalesce(jsonb_agg(iara.pend_json(m) order by
                 case when m.situacao <> 'ABERTA' then 2 when m.prazo < now() then 0 else 1 end, m.prazo nulls last, m.concluida_em desc nulls last, m.criada_em), '[]')
              from (select m.* from minhas m join iara.pend_tipos t on t.codigo = m.tipo
                    where (v_mod is null or t.modulo = v_mod)
                      and case v_sit when 'ATRASADAS' then m.situacao = 'ABERTA' and m.prazo < now()
                                     when 'CONCLUIDAS' then m.situacao <> 'ABERTA'
                                     else m.situacao = 'ABERTA' end
                    order by m.prazo nulls last limit 300) m),
    'sincronizado_em', (select max(em) from iara.pend_sinc where escopo in ('*', coalesce(e.unit_id::text, '*'))))
  into v;
  return v;
end $$;

-- contador leve para o menu e o início (não sincroniza)
create or replace function api.pend_contador(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public as $$
declare
  e record;
begin
  perform iara.require_perm('pend.read');
  select * into e from iara.pend_eu();
  return (select jsonb_build_object('abertas', count(*), 'atrasadas', count(*) filter (where prazo < now()),
                                    'hoje', count(*) filter (where prazo >= now() and (prazo at time zone 'America/Sao_Paulo')::date = iara.hoje_local()),
                                    'equipe_atrasadas', case when iara.has_perm('pend.equipe') then (
                                       select count(*) from iara.pendencias q where q.situacao = 'ABERTA' and q.prazo < now()
                                         and iara.pend_alcanca(q.unit_id, q.setor_id, e.papel, e.unit_id, e.alcance, e.tudo, e.cmeis)
                                         and not iara.pend_minha(q.staff_id, q.papel, q.unit_id, e.papel, e.unit_id, e.staff_id, e.na_unidade)) end)
          from iara.pendencias p
          where p.situacao = 'ABERTA' and iara.pend_minha(p.staff_id, p.papel, p.unit_id, e.papel, e.unit_id, e.staff_id, e.na_unidade));
end $$;

-- uma pendência (minha ou da equipe), com o histórico
create or replace function api.pend_item(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public as $$
declare
  e record;
  x iara.pendencias;
  v_minha boolean;
  v_chefia boolean;
begin
  perform iara.require_perm('pend.read');
  select * into e from iara.pend_eu();
  select * into x from iara.pendencias where id = nullif(p ->> 'id', '')::uuid;
  if not found then raise exception 'Pendência não encontrada.' using errcode = 'P0002'; end if;
  v_minha := iara.pend_minha(x.staff_id, x.papel, x.unit_id, e.papel, e.unit_id, e.staff_id, e.na_unidade);
  v_chefia := iara.has_perm('pend.equipe') and iara.pend_alcanca(x.unit_id, x.setor_id, e.papel, e.unit_id, e.alcance, e.tudo, e.cmeis);
  if not v_minha and not v_chefia then raise exception 'Esta pendência não é sua nem da sua equipe.' using errcode = '42501'; end if;
  return iara.pend_json(x) || jsonb_build_object(
    'minha', v_minha,
    'pode_concluir', v_minha and x.situacao = 'ABERTA' and x.origem <> 'AUTOMATICA',
    'pode_cobrar', v_chefia and not v_minha and x.situacao = 'ABERTA',
    'pode_cancelar', v_chefia and iara.has_perm('pend.atribuir') and x.situacao = 'ABERTA' and x.origem <> 'AUTOMATICA',
    'pode_devolver', v_chefia and iara.has_perm('pend.atribuir') and x.situacao = 'CONCLUIDA' and x.origem <> 'AUTOMATICA',
    'eventos', (select coalesce(jsonb_agg(jsonb_build_object('tipo', ev.tipo, 'texto', ev.texto, 'autor', ev.autor_label, 'em', ev.em) order by ev.em), '[]')
                from iara.pend_eventos ev where ev.pendencia_id = x.id));
end $$;

-- marca ou desmarca um item da lista de conferência
create or replace function api.pend_checklist(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public as $$
declare
  e record;
  x iara.pendencias;
  v_i integer := (p ->> 'indice')::int;
  v_feito boolean := coalesce((p ->> 'feito')::boolean, true);
begin
  perform iara.require_perm('pend.read');
  select * into e from iara.pend_eu();
  select * into x from iara.pendencias where id = nullif(p ->> 'id', '')::uuid for update;
  if not found or not iara.pend_minha(x.staff_id, x.papel, x.unit_id, e.papel, e.unit_id, e.staff_id, e.na_unidade) then
    raise exception 'Esta pendência não é sua.' using errcode = '42501'; end if;
  if x.situacao <> 'ABERTA' then raise exception 'A pendência já foi encerrada.' using errcode = '22023'; end if;
  if x.checklist is null or v_i is null or v_i < 0 or v_i >= jsonb_array_length(x.checklist) then
    raise exception 'Item da lista não encontrado.' using errcode = '22023'; end if;
  update iara.pendencias set checklist = jsonb_set(checklist, array[v_i::text],
           (checklist -> v_i) || jsonb_build_object('feito', v_feito, 'em', case when v_feito then now() end, 'por', case when v_feito then iara.my_label() end))
  where id = x.id returning * into x;
  insert into iara.pend_eventos (pendencia_id, tipo, texto, autor, autor_label, is_demo)
  values (x.id, 'ITEM', format('%s: %s', case when v_feito then 'Feito' else 'Desmarcado' end, x.checklist -> v_i ->> 'item'), iara.current_user_id(), iara.my_label(), iara.demo_mode());
  return iara.pend_json(x);
end $$;

-- conclui tarefa ou procedimento (as automáticas se fecham quando se resolve no módulo)
create or replace function api.pend_concluir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public as $$
declare
  e record;
  x iara.pendencias;
  v_nota text := nullif(btrim(coalesce(p ->> 'nota', '')), '');
begin
  perform iara.require_perm('pend.read');
  select * into e from iara.pend_eu();
  select * into x from iara.pendencias where id = nullif(p ->> 'id', '')::uuid for update;
  if not found or not iara.pend_minha(x.staff_id, x.papel, x.unit_id, e.papel, e.unit_id, e.staff_id, e.na_unidade) then
    raise exception 'Esta pendência não é sua.' using errcode = '42501'; end if;
  if x.situacao <> 'ABERTA' then raise exception 'A pendência já foi encerrada.' using errcode = '22023'; end if;
  if x.origem = 'AUTOMATICA' then
    raise exception 'Esta pendência se resolve na própria tela (%). Ela sai daqui sozinha quando estiver resolvida.', coalesce(x.rota, 'do módulo') using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(coalesce(x.checklist, '[]')) i where not coalesce((i ->> 'feito')::boolean, false)) then
    raise exception 'Marque todos os itens da lista de conferência antes de concluir.' using errcode = '22023';
  end if;
  if length(v_nota) > 1000 then raise exception 'A nota pode ter até 1.000 caracteres.' using errcode = '22023'; end if;
  update iara.pendencias set situacao = 'CONCLUIDA', concluida_em = now(), concluida_por = iara.current_user_id(), concluida_por_label = iara.my_label(),
                             conclusao = v_nota
  where id = x.id returning * into x;
  insert into iara.pend_eventos (pendencia_id, tipo, texto, autor, autor_label, is_demo)
  values (x.id, 'CONCLUIDA', v_nota, iara.current_user_id(), iara.my_label(), iara.demo_mode());
  perform iara.audit_event('PENDENCIA_CONCLUIDA', 'pendencia', x.id::text, x.unit_id, format('Concluiu "%s"%s', x.titulo, case when x.prazo < now() then ' (fora do prazo)' else '' end));
  return iara.pend_json(x);
end $$;

-- 12. Chefia: acompanhar a equipe -----------------------------------------------------------------------------------------------------------
-- nível 1 (rede): unidades e setores ao alcance; nível 2 (grupo): pessoas e postos de uma unidade/setor; nível 3 (posto): as pendências
create or replace function api.pend_equipe(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public as $$
declare
  e record;
  v_grupo text := nullif(p ->> 'grupo', '');
  v_posto text := nullif(p ->> 'posto', '');
  v_filtro text := coalesce(nullif(p ->> 'filtro', ''), 'TODOS');
  v_busca text := nullif(btrim(coalesce(p ->> 'busca', '')), '');
  v_unit integer;
  v_setor uuid;
  v jsonb;
  pp record;
begin
  perform iara.require_perm('pend.equipe');
  select * into e from iara.pend_eu();
  if e.papel = 'DIRETOR_UNIDADE' and v_grupo is null then v_grupo := 'U:' || e.unit_id; end if;
  if v_grupo like 'U:%' then v_unit := substr(v_grupo, 3)::int;
  elsif v_grupo like 'S:%' then v_setor := substr(v_grupo, 3)::uuid; end if;
  if v_posto is null and v_grupo is null and e.na_unidade then v_grupo := 'U:' || e.unit_id; v_unit := e.unit_id; end if;
  perform iara.pend_sincronizar_se_preciso(v_unit);

  if v_posto is not null then
    select * into pp from iara.pend_posto_partes(v_posto);
    if not iara.pend_alcanca(pp.unit_id, pp.setor_id, e.papel, e.unit_id, e.alcance, e.tudo, e.cmeis)
       and not exists (select 1 from iara.pendencias q where q.posto = v_posto
                       and iara.pend_alcanca(q.unit_id, q.setor_id, e.papel, e.unit_id, e.alcance, e.tudo, e.cmeis)) then
      raise exception 'Este posto não é da sua equipe.' using errcode = '42501'; end if;
    select jsonb_build_object('nivel', 'posto', 'posto', v_posto,
      'nome', iara.pend_posto_rotulo(pp.papel, pp.unit_id, pp.setor_id, pp.staff_id), 'papel', iara.pend_papel_rotulo(pp.papel),
      'unidade', (select short_name from iara.education_units where id = pp.unit_id),
      'grupo', case when pp.unit_id is not null then 'U:' || pp.unit_id else 'S:' || pp.setor_id end,
      'itens', (select coalesce(jsonb_agg(iara.pend_json(q) order by case when q.situacao <> 'ABERTA' then 2 when q.prazo < now() then 0 else 1 end,
                                         q.prazo nulls last, q.concluida_em desc nulls last), '[]')
                from (select * from iara.pendencias q where q.posto = v_posto
                        and iara.pend_alcanca(q.unit_id, q.setor_id, e.papel, e.unit_id, e.alcance, e.tudo, e.cmeis)
                        and (q.situacao = 'ABERTA' or q.concluida_em > now() - interval '30 days')
                      order by q.situacao, q.prazo nulls last limit 300) q))
    into v;
    return v;
  end if;

  if v_grupo is not null then
    if v_unit is not null and not iara.pend_alcanca(v_unit, iara.pend_setor('UNID'), e.papel, e.unit_id, e.alcance, e.tudo, e.cmeis) then
      raise exception 'Esta unidade não é da sua equipe.' using errcode = '42501'; end if;
    if v_setor is not null and not iara.pend_alcanca(null, v_setor, e.papel, e.unit_id, e.alcance, e.tudo, e.cmeis) then
      raise exception 'Este setor não é da sua equipe.' using errcode = '42501'; end if;
    with base as materialized (
      select q.* from iara.pendencias q
      where (case when v_unit is not null then q.unit_id = v_unit else q.unit_id is null and q.setor_id = v_setor end)
        and iara.pend_alcanca(q.unit_id, q.setor_id, e.papel, e.unit_id, e.alcance, e.tudo, e.cmeis)
        and (q.situacao = 'ABERTA' or q.concluida_em > now() - interval '30 days')),
    g as (
      select posto, min(papel) papel, min(unit_id) unit_id, (array_agg(setor_id))[1] setor_id, (array_agg(staff_id))[1] staff_id,
             count(*) filter (where situacao = 'ABERTA') abertas,
             count(*) filter (where situacao = 'ABERTA' and prazo < now()) atrasadas,
             count(*) filter (where situacao = 'ABERTA' and prazo >= now() and (prazo at time zone 'America/Sao_Paulo')::date = iara.hoje_local()) hoje,
             count(*) filter (where situacao = 'CONCLUIDA') concluidas,
             round(100.0 * count(*) filter (where situacao = 'CONCLUIDA' and concluida_em <= prazo) / nullif(count(*) filter (where situacao = 'CONCLUIDA' and prazo is not null), 0)) no_prazo,
             max(iara.hoje_local() - (criada_em at time zone 'America/Sao_Paulo')::date) filter (where situacao = 'ABERTA') mais_antiga
      from base group by posto)
    select jsonb_build_object('nivel', 'grupo', 'grupo', v_grupo,
      'nome', coalesce((select name from iara.education_units where id = v_unit), (select nome from iara.org_setores where id = v_setor)),
      'pode_atribuir', iara.has_perm('pend.atribuir'),
      'resumo', jsonb_build_object('abertas', coalesce(sum(abertas), 0), 'atrasadas', coalesce(sum(atrasadas), 0), 'hoje', coalesce(sum(hoje), 0),
                                   'concluidas_30', coalesce(sum(concluidas), 0), 'postos', count(*)),
      'postos', coalesce(jsonb_agg(jsonb_build_object('posto', posto, 'nome', iara.pend_posto_rotulo(papel, unit_id, setor_id, staff_id),
                          'papel', iara.pend_papel_rotulo(papel), 'pessoa', staff_id is not null,
                          'turmas', case when papel = 'PROFESSOR' and staff_id is not null then iara.pend_turmas(g.staff_id, g.unit_id) end,
                          'abertas', abertas, 'atrasadas', atrasadas, 'hoje', hoje, 'concluidas_30', concluidas, 'no_prazo', no_prazo, 'mais_antiga', mais_antiga)
                 order by (select ordem from iara.pend_papeis where role_code = papel), atrasadas desc, abertas desc, iara.pend_posto_rotulo(papel, unit_id, setor_id, staff_id)), '[]'))
    into v from g
    where v_busca is null or iara.pend_posto_rotulo(papel, unit_id, setor_id, staff_id) ilike '%' || v_busca || '%';
    return v;
  end if;

  -- nível rede: unidades e setores ao alcance
  perform iara.pend_sincronizar_se_preciso(null);
  with base as materialized (
    select q.unit_id, q.setor_id, q.situacao, q.prazo, q.criada_em, q.concluida_em
    from iara.pendencias q
    where (q.situacao = 'ABERTA' or q.concluida_em > now() - interval '30 days')
      and iara.pend_alcanca(q.unit_id, q.setor_id, e.papel, e.unit_id, e.alcance, e.tudo, e.cmeis)
      and not iara.pend_minha(q.staff_id, q.papel, q.unit_id, e.papel, e.unit_id, e.staff_id, e.na_unidade)),
  g as (
    select case when unit_id is not null then 'U:' || unit_id else 'S:' || setor_id end grupo, min(unit_id) unit_id, (array_agg(setor_id))[1] setor_id,
           count(*) filter (where situacao = 'ABERTA') abertas,
           count(*) filter (where situacao = 'ABERTA' and prazo < now()) atrasadas,
           count(*) filter (where situacao = 'ABERTA' and prazo >= now() and (prazo at time zone 'America/Sao_Paulo')::date = iara.hoje_local()) hoje,
           count(*) filter (where situacao = 'CONCLUIDA') concluidas,
           round(100.0 * count(*) filter (where situacao = 'CONCLUIDA' and concluida_em <= prazo) / nullif(count(*) filter (where situacao = 'CONCLUIDA' and prazo is not null), 0)) no_prazo,
           max(iara.hoje_local() - (criada_em at time zone 'America/Sao_Paulo')::date) filter (where situacao = 'ABERTA') mais_antiga
    from base group by 1),
  r as (
    select g.*, coalesce(u.short_name, s.nome) nome, case when u.id is not null then u.unit_type else 'SETOR' end tipo, t.name regiao
    from g left join iara.education_units u on u.id = g.unit_id left join iara.org_setores s on s.id = g.setor_id and g.unit_id is null
    left join iara.territories t on t.id = u.macro_territory_id)
  select jsonb_build_object('nivel', 'rede',
    'resumo', jsonb_build_object('abertas', coalesce(sum(abertas), 0), 'atrasadas', coalesce(sum(atrasadas), 0), 'hoje', coalesce(sum(hoje), 0),
                                 'concluidas_30', coalesce(sum(concluidas), 0)),
    'grupos', coalesce(jsonb_agg(jsonb_build_object('grupo', grupo, 'nome', nome, 'tipo', tipo, 'regiao', regiao, 'abertas', abertas, 'atrasadas', atrasadas,
                                 'hoje', hoje, 'concluidas_30', concluidas, 'no_prazo', no_prazo, 'mais_antiga', mais_antiga)
               order by (tipo = 'SETOR') desc, atrasadas desc, abertas desc, nome), '[]'))
  into v from r
  where (v_filtro = 'TODOS' or (v_filtro = 'SETORES' and tipo = 'SETOR') or (v_filtro = tipo))
    and (v_busca is null or nome ilike '%' || v_busca || '%');
  return v;
end $$;

-- postos de uma unidade ou setor a quem a chefia pode atribuir tarefa
create or replace function api.pend_postos(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public as $$
declare
  e record;
  v_grupo text := nullif(p ->> 'grupo', '');
  v_unit integer;
  v_setor uuid;
begin
  perform iara.require_perm('pend.atribuir');
  select * into e from iara.pend_eu();
  if v_grupo is null and e.na_unidade then v_grupo := 'U:' || e.unit_id; end if;
  if v_grupo like 'U:%' then v_unit := substr(v_grupo, 3)::int; elsif v_grupo like 'S:%' then v_setor := substr(v_grupo, 3)::uuid; end if;
  if v_unit is not null then
    if not iara.pend_alcanca(v_unit, iara.pend_setor('UNID'), e.papel, e.unit_id, e.alcance, e.tudo, e.cmeis) then
      raise exception 'Esta unidade não é da sua equipe.' using errcode = '42501'; end if;
    return jsonb_build_object('postos', (
      select coalesce(jsonb_agg(x order by x ->> 'ordem', x ->> 'nome'), '[]') from (
        select jsonb_build_object('posto', 'R:' || pp.role_code || ':' || v_unit || ':' || iara.pend_setor('UNID'), 'nome', pp.rotulo, 'papel', pp.rotulo, 'ordem', '0' || pp.ordem) x
        from iara.pend_papeis pp where pp.na_unidade and pp.role_code not in ('PROFESSOR', 'PROFESSOR_AEE') and not (pp.role_code = e.papel and e.unit_id = v_unit)
        union all
        select jsonb_build_object('posto', 'P:' || s.id, 'nome', s.full_name, 'papel', case when s.role = 'AEE' then 'Professor(a) do AEE' else 'Professor(a)' end,
                                  'turmas', iara.pend_turmas(s.id, v_unit), 'ordem', '1')
        from iara.staff s
        where s.situacao = 'ATIVO'
          and ((s.role = 'AEE' and s.unit_id = v_unit) or exists (select 1 from iara.class_staff cs join iara.classes c on c.id = cs.class_id
                                         where cs.staff_id = s.id and c.unit_id = v_unit and c.status = 'ATIVA' and (cs.end_date is null or cs.end_date >= current_date))
                                     or exists (select 1 from iara.horarios_turma h join iara.classes c on c.id = h.class_id where h.staff_id = s.id and c.unit_id = v_unit and c.status = 'ATIVA'))
      ) z));
  end if;
  if v_setor is null or not iara.pend_alcanca(null, v_setor, e.papel, e.unit_id, e.alcance, e.tudo, e.cmeis) then
    raise exception 'Escolha uma unidade ou um setor da sua equipe.' using errcode = '22023'; end if;
  return jsonb_build_object('postos', (
    select coalesce(jsonb_agg(x order by x ->> 'ordem', x ->> 'nome'), '[]') from (
      select jsonb_build_object('posto', 'R:' || pp.role_code || '::' || v_setor, 'nome', pp.rotulo, 'papel', pp.rotulo, 'ordem', '0') x
      from iara.pend_papeis pp where not pp.na_unidade and iara.pend_setor(pp.setor_sigla) = v_setor and pp.role_code <> e.papel
      union all
      select jsonb_build_object('posto', 'P:' || v.staff_id, 'nome', v.pessoa_nome, 'papel', v.funcao, 'ordem', '1')
      from iara.org_vinculos v where v.setor_id = v_setor and v.fim is null and v.staff_id is not null and v.staff_id is distinct from e.staff_id
    ) z));
end $$;

-- atribui uma tarefa com prazo
create or replace function api.pend_atribuir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public as $$
declare
  e record;
  pp record;
  v_titulo text := btrim(coalesce(p ->> 'titulo', ''));
  v_detalhe text := nullif(btrim(coalesce(p ->> 'detalhe', '')), '');
  v_prazo date := nullif(p ->> 'prazo', '')::date;
  v_check jsonb;
  v_grupo_unit integer;
  x iara.pendencias;
begin
  perform iara.require_perm('pend.atribuir');
  select * into e from iara.pend_eu();
  select * into pp from iara.pend_posto_partes(p ->> 'posto');
  -- professor(a) que dá aula em mais de uma unidade: a tarefa fica na unidade de quem atribuiu (ou do grupo aberto)
  if pp.staff_id is not null and pp.papel = 'PROFESSOR' then
    v_grupo_unit := coalesce(case when p ->> 'grupo' like 'U:%' then substr(p ->> 'grupo', 3)::int end, case when e.na_unidade then e.unit_id end);
    if v_grupo_unit is not null and iara.pend_turmas(pp.staff_id, v_grupo_unit) is not null then pp.unit_id := v_grupo_unit; end if;
  end if;
  if not iara.pend_alcanca(pp.unit_id, pp.setor_id, e.papel, e.unit_id, e.alcance, e.tudo, e.cmeis) then
    raise exception 'Você só pode atribuir tarefas à sua equipe.' using errcode = '42501'; end if;
  if length(v_titulo) < 5 or length(v_titulo) > 140 then raise exception 'Escreva o que deve ser feito (de 5 a 140 caracteres).' using errcode = '22023'; end if;
  if length(v_detalhe) > 2000 then raise exception 'As orientações podem ter até 2.000 caracteres.' using errcode = '22023'; end if;
  if v_prazo is null or v_prazo < iara.hoje_local() or v_prazo > iara.hoje_local() + 180 then
    raise exception 'Informe um prazo entre hoje e os próximos 180 dias.' using errcode = '22023'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('item', btrim(i), 'feito', false)) filter (where btrim(i) <> ''), '[]'::jsonb) into v_check
  from jsonb_array_elements_text(coalesce(p -> 'checklist', '[]')) i;
  if jsonb_array_length(v_check) > 20 then raise exception 'A lista de conferência pode ter até 20 itens.' using errcode = '22023'; end if;
  insert into iara.pendencias (origem, tipo, chave, titulo, detalhe, papel, unit_id, setor_id, staff_id, prazo, checklist, atribuida_por, atribuida_por_label, is_demo)
  values ('ATRIBUIDA', 'TAREFA', 'TAR:' || gen_random_uuid(), v_titulo, v_detalhe, pp.papel, pp.unit_id, pp.setor_id, pp.staff_id,
          ((v_prazo::timestamp + time '18:00') at time zone 'America/Sao_Paulo'), nullif(v_check, '[]'::jsonb), iara.current_user_id(), iara.my_label(), iara.demo_mode())
  returning * into x;
  insert into iara.pend_eventos (pendencia_id, tipo, texto, autor, autor_label, is_demo)
  values (x.id, 'CRIADA', v_detalhe, iara.current_user_id(), iara.my_label(), iara.demo_mode());
  perform iara.audit_event('PENDENCIA_ATRIBUIDA', 'pendencia', x.id::text, x.unit_id,
                           format('Atribuiu "%s" a %s, prazo %s', x.titulo, iara.pend_posto_rotulo(x.papel, x.unit_id, x.setor_id, x.staff_id), to_char(v_prazo, 'DD/MM/YYYY')));
  return iara.pend_json(x);
end $$;

-- cobrar, cancelar ou devolver (chefia)
create or replace function api.pend_chefia_acao(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public as $$
declare
  e record;
  x iara.pendencias;
  v_acao text := upper(coalesce(p ->> 'acao', ''));
  v_texto text := nullif(btrim(coalesce(p ->> 'texto', '')), '');
begin
  perform iara.require_perm('pend.equipe');
  select * into e from iara.pend_eu();
  select * into x from iara.pendencias where id = nullif(p ->> 'id', '')::uuid for update;
  if not found or not iara.pend_alcanca(x.unit_id, x.setor_id, e.papel, e.unit_id, e.alcance, e.tudo, e.cmeis) then
    raise exception 'Esta pendência não é da sua equipe.' using errcode = '42501'; end if;
  if length(v_texto) > 1000 then raise exception 'A mensagem pode ter até 1.000 caracteres.' using errcode = '22023'; end if;
  if v_acao = 'COBRAR' then
    if x.situacao <> 'ABERTA' then raise exception 'A pendência já foi encerrada.' using errcode = '22023'; end if;
    insert into iara.pend_eventos (pendencia_id, tipo, texto, autor, autor_label, is_demo)
    values (x.id, 'COBRADA', coalesce(v_texto, 'A chefia pediu prioridade.'), iara.current_user_id(), iara.my_label(), iara.demo_mode());
  elsif v_acao in ('CANCELAR', 'DEVOLVER') then
    perform iara.require_perm('pend.atribuir');
    if x.origem = 'AUTOMATICA' then raise exception 'Pendências automáticas se encerram quando se resolve no módulo.' using errcode = '22023'; end if;
    if v_texto is null or length(v_texto) < 5 then raise exception 'Explique o motivo em poucas palavras.' using errcode = '22023'; end if;
    if v_acao = 'CANCELAR' then
      if x.situacao <> 'ABERTA' then raise exception 'A pendência já foi encerrada.' using errcode = '22023'; end if;
      update iara.pendencias set situacao = 'CANCELADA', concluida_em = now(), concluida_por = iara.current_user_id(), concluida_por_label = iara.my_label(), conclusao = v_texto
      where id = x.id returning * into x;
      insert into iara.pend_eventos (pendencia_id, tipo, texto, autor, autor_label, is_demo) values (x.id, 'CANCELADA', v_texto, iara.current_user_id(), iara.my_label(), iara.demo_mode());
    else
      if x.situacao <> 'CONCLUIDA' then raise exception 'Só se devolve o que foi concluído.' using errcode = '22023'; end if;
      update iara.pendencias set situacao = 'ABERTA', concluida_em = null, concluida_por = null, concluida_por_label = null, conclusao = null,
                                 prazo = greatest(prazo, now() + interval '2 days'),
                                 checklist = (select jsonb_agg(i || jsonb_build_object('feito', false, 'em', null, 'por', null)) from jsonb_array_elements(checklist) i)
      where id = x.id returning * into x;
      insert into iara.pend_eventos (pendencia_id, tipo, texto, autor, autor_label, is_demo) values (x.id, 'DEVOLVIDA', v_texto, iara.current_user_id(), iara.my_label(), iara.demo_mode());
    end if;
    perform iara.audit_event('PENDENCIA_' || v_acao, 'pendencia', x.id::text, x.unit_id, format('%s "%s": %s', initcap(lower(v_acao)), x.titulo, v_texto));
  else
    raise exception 'Ação desconhecida.' using errcode = '22023';
  end if;
  return iara.pend_json(x);
end $$;

-- 13. Procedimentos periódicos (SEDUC e direção) ------------------------------------------------------------------------------------------
create or replace function api.pend_rotinas(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public as $$
declare
  e record;
  v_tipo text;
begin
  perform iara.require_perm('pend.rotinas');
  select * into e from iara.pend_eu();
  select unit_type into v_tipo from iara.education_units where id = e.unit_id;
  -- na unidade: os da própria unidade (editáveis) e os da rede que valem para ela (só leitura), com os números da unidade
  return jsonb_build_object(
    'escopo', case when e.na_unidade then 'UNIDADE' else 'REDE' end,
    'unidade', (select name from iara.education_units where id = e.unit_id and e.na_unidade),
    'papeis', (select coalesce(jsonb_agg(jsonb_build_object('papel', role_code, 'rotulo', rotulo, 'na_unidade', na_unidade) order by ordem), '[]')
               from iara.pend_papeis where na_unidade or not e.na_unidade),
    'rotinas', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', r.id, 'titulo', r.titulo, 'procedimento', r.procedimento, 'checklist', to_jsonb(r.checklist), 'papel', r.papel, 'papel_rotulo', iara.pend_papel_rotulo(r.papel),
        'alvo', r.alvo, 'unidade', (select short_name from iara.education_units where id = r.unit_id), 'periodicidade', r.periodicidade,
        'periodo_rotulo', iara.pend_periodo_rotulo(r.periodicidade), 'dia', r.dia, 'prazo_dias', r.prazo_dias, 'inicio', r.inicio, 'ativo', r.ativo,
        'criada_por', r.criada_por_label, 'simulado', r.is_demo, 'editavel', not e.na_unidade or r.alvo = 'UNIDADE',
        'proximo', case when r.inicio > iara.hoje_local() then r.inicio else iara.pend_periodo_proximo(r.periodicidade, r.dia, r.inicio, iara.hoje_local()) end,
        'abertas', (select count(*) from iara.pendencias q where q.rotina_id = r.id and q.situacao = 'ABERTA' and (not e.na_unidade or q.unit_id = e.unit_id)),
        'atrasadas', (select count(*) from iara.pendencias q where q.rotina_id = r.id and q.situacao = 'ABERTA' and q.prazo < now() and (not e.na_unidade or q.unit_id = e.unit_id)),
        'concluidas', (select count(*) from iara.pendencias q where q.rotina_id = r.id and q.situacao = 'CONCLUIDA' and (not e.na_unidade or q.unit_id = e.unit_id)),
        'no_prazo', (select round(100.0 * count(*) filter (where q.concluida_em <= q.prazo) / nullif(count(*), 0)) from iara.pendencias q
                     where q.rotina_id = r.id and q.situacao = 'CONCLUIDA' and (not e.na_unidade or q.unit_id = e.unit_id)))
        order by (not e.na_unidade or r.alvo = 'UNIDADE') desc, r.ativo desc, r.titulo), '[]')
      from iara.pend_rotinas r
      where not e.na_unidade or (r.alvo = 'UNIDADE' and r.unit_id = e.unit_id)
         or (r.ativo and r.alvo in ('TODAS', 'CMEI', 'ESCOLA') and (r.alvo = 'TODAS' or r.alvo = v_tipo)
             and exists (select 1 from iara.pend_papeis pp where pp.role_code = r.papel and pp.na_unidade))));
end $$;

create or replace function api.pend_rotina_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public as $$
declare
  e record;
  r iara.pend_rotinas;
  v_id uuid := nullif(p ->> 'id', '')::uuid;
  v_papel text := p ->> 'papel';
  v_alvo text := upper(coalesce(nullif(p ->> 'alvo', ''), 'TODAS'));
  v_unit integer := nullif(p ->> 'unit_id', '')::int;
  v_check text[];
  pp iara.pend_papeis;
  n integer;
begin
  perform iara.require_perm('pend.rotinas');
  select * into e from iara.pend_eu();
  select * into pp from iara.pend_papeis where role_code = v_papel;
  if not found then raise exception 'Escolha quem cumpre o procedimento.' using errcode = '22023'; end if;
  if e.na_unidade then
    -- direção: só procedimentos da própria unidade, para a equipe da unidade
    if not pp.na_unidade then raise exception 'A direção cadastra procedimentos para a equipe da unidade.' using errcode = '42501'; end if;
    v_alvo := 'UNIDADE'; v_unit := e.unit_id;
  elsif pp.na_unidade then
    if v_alvo not in ('TODAS', 'CMEI', 'ESCOLA', 'UNIDADE') then raise exception 'Escolha as unidades.' using errcode = '22023'; end if;
    if v_alvo = 'UNIDADE' and not exists (select 1 from iara.education_units where id = v_unit) then raise exception 'Escolha a unidade.' using errcode = '22023'; end if;
  else
    v_alvo := 'SETOR'; v_unit := null;
  end if;
  if v_alvo <> 'UNIDADE' then v_unit := null; end if;
  select coalesce(array_agg(btrim(i)) filter (where btrim(i) <> ''), '{}') into v_check from jsonb_array_elements_text(coalesce(p -> 'checklist', '[]')) i;
  if cardinality(v_check) > 20 then raise exception 'A lista de conferência pode ter até 20 itens.' using errcode = '22023'; end if;
  if v_id is not null then
    select * into r from iara.pend_rotinas where id = v_id for update;
    if not found then raise exception 'Procedimento não encontrado.' using errcode = 'P0002'; end if;
    if e.na_unidade and (r.alvo <> 'UNIDADE' or r.unit_id is distinct from e.unit_id) then
      raise exception 'Este procedimento não é da sua unidade.' using errcode = '42501'; end if;
    update iara.pend_rotinas set titulo = btrim(p ->> 'titulo'), procedimento = btrim(p ->> 'procedimento'), checklist = v_check, papel = v_papel,
      alvo = v_alvo, unit_id = v_unit, periodicidade = upper(p ->> 'periodicidade'), dia = coalesce(nullif(p ->> 'dia', '')::smallint, 1),
      prazo_dias = coalesce(nullif(p ->> 'prazo_dias', '')::smallint, 5), ativo = coalesce((p ->> 'ativo')::boolean, true), atualizada_em = now()
    where id = v_id returning * into r;
    -- as abertas do período acompanham o texto novo; as encerradas ficam como foram
    update iara.pendencias set titulo = r.titulo where rotina_id = r.id and situacao = 'ABERTA';
    if not r.ativo then
      update iara.pendencias set situacao = 'CANCELADA', concluida_em = now(), concluida_por_label = iara.my_label(), conclusao = 'Procedimento desativado.'
      where rotina_id = r.id and situacao = 'ABERTA';
    end if;
  else
    insert into iara.pend_rotinas (titulo, procedimento, checklist, papel, alvo, unit_id, periodicidade, dia, prazo_dias, inicio, criada_por, criada_por_label, is_demo)
    values (btrim(p ->> 'titulo'), btrim(p ->> 'procedimento'), v_check, v_papel, v_alvo, v_unit, upper(p ->> 'periodicidade'),
            coalesce(nullif(p ->> 'dia', '')::smallint, 1), coalesce(nullif(p ->> 'prazo_dias', '')::smallint, 5),
            coalesce(nullif(p ->> 'inicio', '')::date, iara.hoje_local()), iara.current_user_id(), iara.my_label(), iara.demo_mode())
    returning * into r;
  end if;
  n := iara.pend_rotinas_gerar(r.id);
  perform iara.audit_event('PROCEDIMENTO_SALVO', 'pend_rotina', r.id::text, r.unit_id,
                           format('Procedimento "%s" (%s, %s)%s', r.titulo, iara.pend_papel_rotulo(r.papel), iara.pend_periodo_rotulo(r.periodicidade), case when r.ativo then '' else ' desativado' end));
  return jsonb_build_object('ok', true, 'id', r.id, 'geradas', n);
exception when check_violation then
  raise exception 'Confira o título (5 a 140 caracteres), o procedimento (10 a 2.000), o dia (1 a 28) e o prazo (1 a 60 dias).' using errcode = '22023';
end $$;

-- 14. Estatísticas (Prefeito sem nomes; Secretário e Superintendência descem até a pessoa) ----------------------------------------------
create or replace function iara.pend_estat_calcular(p_dias integer, p_regiao text, p_tipo text, p_nomes boolean) returns jsonb
language plpgsql security definer set search_path = iara, public as $$
declare
  v_dias integer := p_dias;
  v_regiao text := p_regiao;
  v_tipo text := p_tipo;
  v_nomes boolean := p_nomes;
  v jsonb;
begin
  with base as materialized (
    select q.tipo, q.origem, q.papel, q.unit_id, q.setor_id, q.staff_id, q.posto, q.situacao, q.prazo, q.criada_em, q.concluida_em,
           t.modulo, t.titulo tipo_titulo, u.short_name unidade, u.unit_type, tr.name regiao,
           (q.situacao = 'ABERTA' and q.prazo < now()) atrasada,
           (q.situacao = 'CONCLUIDA' and q.concluida_em > now() - make_interval(days => v_dias)) conc,
           (q.situacao = 'CONCLUIDA' and q.concluida_em > now() - make_interval(days => v_dias) and q.prazo is not null) conc_prazo,
           (q.situacao = 'CONCLUIDA' and q.concluida_em > now() - make_interval(days => v_dias) and q.concluida_em <= q.prazo) conc_no_prazo
    from iara.pendencias q join iara.pend_tipos t on t.codigo = q.tipo
    left join iara.education_units u on u.id = q.unit_id
    left join iara.territories tr on tr.id = u.macro_territory_id
    where q.situacao <> 'CANCELADA'
      and (q.situacao = 'ABERTA' or q.concluida_em > now() - make_interval(days => greatest(v_dias, 84)))
      and (v_regiao is null or tr.name = v_regiao)
      and (v_tipo is null or (v_tipo = 'SEDUC' and q.unit_id is null) or u.unit_type = v_tipo)),
  ab as (select * from base where situacao = 'ABERTA')
  select jsonb_build_object(
    'dias', v_dias, 'nomes', v_nomes,
    'regioes', (select coalesce(jsonb_agg(name order by name), '[]') from (select distinct t.name from iara.territories t
                 join iara.education_units u on u.macro_territory_id = t.id where t.name is not null) z),
    'totais', jsonb_build_object(
      'abertas', (select count(*) from ab),
      'atrasadas', (select count(*) from ab where atrasada),
      'atrasadas_7', (select count(*) from ab where prazo < now() - interval '7 days'),
      'hoje', (select count(*) from ab where prazo >= now() and (prazo at time zone 'America/Sao_Paulo')::date = iara.hoje_local()),
      'postos_com_atraso', (select count(distinct posto) from ab where atrasada),
      'concluidas', (select count(*) from base where conc),
      'no_prazo', (select round(100.0 * count(*) filter (where conc_no_prazo) / nullif(count(*) filter (where conc_prazo), 0)) from base),
      'tempo_medio', (select round((avg(extract(epoch from concluida_em - criada_em)) / 86400.0)::numeric, 1) from base where conc),
      'criadas', (select count(*) from base where criada_em > now() - make_interval(days => v_dias))),
    'por_origem', (select coalesce(jsonb_agg(jsonb_build_object('origem', origem, 'abertas', a, 'atrasadas', at, 'concluidas', c, 'no_prazo', np) order by origem), '[]')
                   from (select origem, count(*) filter (where situacao = 'ABERTA') a, count(*) filter (where atrasada) at, count(*) filter (where conc) c,
                                round(100.0 * count(*) filter (where conc_no_prazo) / nullif(count(*) filter (where conc_prazo), 0)) np
                         from base group by origem) z),
    'por_modulo', (select coalesce(jsonb_agg(jsonb_build_object('modulo', modulo, 'abertas', a, 'atrasadas', at, 'concluidas', c, 'no_prazo', np, 'tempo_medio', tm)
                                    order by at desc, a desc), '[]')
                   from (select modulo, count(*) filter (where situacao = 'ABERTA') a, count(*) filter (where atrasada) at, count(*) filter (where conc) c,
                                round(100.0 * count(*) filter (where conc_no_prazo) / nullif(count(*) filter (where conc_prazo), 0)) np,
                                round((avg(extract(epoch from concluida_em - criada_em)) filter (where conc) / 86400.0)::numeric, 1) tm
                         from base group by modulo) z),
    'por_tipo', (select coalesce(jsonb_agg(jsonb_build_object('tipo', tipo, 'titulo', tipo_titulo, 'modulo', modulo, 'papel', iara.pend_papel_rotulo(papel),
                                  'abertas', a, 'atrasadas', at, 'concluidas', c, 'no_prazo', np) order by at desc, a desc), '[]')
                 from (select tipo, tipo_titulo, modulo, min(papel) papel, count(*) filter (where situacao = 'ABERTA') a, count(*) filter (where atrasada) at,
                              count(*) filter (where conc) c, round(100.0 * count(*) filter (where conc_no_prazo) / nullif(count(*) filter (where conc_prazo), 0)) np
                       from base group by tipo, tipo_titulo, modulo order by count(*) filter (where atrasada) desc, count(*) filter (where situacao = 'ABERTA') desc limit 20) z),
    'por_papel', (select coalesce(jsonb_agg(jsonb_build_object('papel', iara.pend_papel_rotulo(papel), 'abertas', a, 'atrasadas', at, 'postos', ps, 'no_prazo', np)
                                   order by at desc, a desc), '[]')
                  from (select papel, count(*) filter (where situacao = 'ABERTA') a, count(*) filter (where atrasada) at,
                               count(distinct posto) filter (where situacao = 'ABERTA') ps,
                               round(100.0 * count(*) filter (where conc_no_prazo) / nullif(count(*) filter (where conc_prazo), 0)) np
                        from base group by papel) z),
    'por_regiao', (select coalesce(jsonb_agg(jsonb_build_object('regiao', regiao, 'unidades', un, 'abertas', a, 'atrasadas', at, 'no_prazo', np) order by at desc), '[]')
                   from (select coalesce(regiao, 'Sem região') regiao, count(distinct unit_id) un, count(*) filter (where situacao = 'ABERTA') a,
                                count(*) filter (where atrasada) at, round(100.0 * count(*) filter (where conc_no_prazo) / nullif(count(*) filter (where conc_prazo), 0)) np
                         from base where unit_id is not null group by 1) z),
    'por_unidade', (select coalesce(jsonb_agg(jsonb_build_object('grupo', 'U:' || unit_id, 'nome', unidade, 'tipo', unit_type, 'regiao', regiao,
                                     'abertas', a, 'atrasadas', at, 'no_prazo', np) order by at desc, a desc), '[]')
                    from (select unit_id, unidade, unit_type, regiao, count(*) filter (where situacao = 'ABERTA') a, count(*) filter (where atrasada) at,
                                 round(100.0 * count(*) filter (where conc_no_prazo) / nullif(count(*) filter (where conc_prazo), 0)) np
                          from base where unit_id is not null group by 1, 2, 3, 4
                          order by count(*) filter (where atrasada) desc, count(*) filter (where situacao = 'ABERTA') desc limit 20) z),
    'setores', (select coalesce(jsonb_agg(jsonb_build_object('grupo', 'S:' || setor_id, 'nome', nome, 'abertas', a, 'atrasadas', at, 'no_prazo', np) order by at desc, a desc), '[]')
                from (select b.setor_id, s.nome, count(*) filter (where b.situacao = 'ABERTA') a, count(*) filter (where b.atrasada) at,
                             round(100.0 * count(*) filter (where b.conc_no_prazo) / nullif(count(*) filter (where b.conc_prazo), 0)) np
                      from base b join iara.org_setores s on s.id = b.setor_id where b.unit_id is null group by 1, 2) z),
    -- semana a semana numa passada só: novas e concluídas agrupadas pela semana; atrasadas no fim de cada semana por faixa de tempo
    'evolucao', (select coalesce(jsonb_agg(jsonb_build_object('semana', wk.ini, 'criadas', coalesce(cri.n, 0), 'concluidas', coalesce(con.n, 0),
                                                              'no_prazo', con.np, 'atrasadas', coalesce(atr.n, 0)) order by wk.ini), '[]')
                 from (select ini, least(now(), ((ini + 7)::timestamp at time zone 'America/Sao_Paulo')) fim
                       from (select (date_trunc('week', now() at time zone 'America/Sao_Paulo')::date - 7 * g) ini from generate_series(0, 11) g) s) wk
                 left join (select date_trunc('week', criada_em at time zone 'America/Sao_Paulo')::date ini, count(*) n from base group by 1) cri on cri.ini = wk.ini
                 left join (select date_trunc('week', concluida_em at time zone 'America/Sao_Paulo')::date ini, count(*) n,
                                   round(100.0 * count(*) filter (where concluida_em <= prazo) / nullif(count(*) filter (where prazo is not null), 0)) np
                            from base where situacao = 'CONCLUIDA' group by 1) con on con.ini = wk.ini
                 left join lateral (select count(*) n from base b
                                    where b.prazo < wk.fim and b.criada_em < wk.fim and (b.concluida_em is null or b.concluida_em > wk.fim)) atr on true),
    'pessoas', case when v_nomes then (
                 select coalesce(jsonb_agg(jsonb_build_object('posto', posto, 'grupo', case when unit_id is not null then 'U:' || unit_id else 'S:' || setor_id end,
                                  'nome', iara.pend_posto_rotulo(papel, unit_id, setor_id, staff_id), 'papel', iara.pend_papel_rotulo(papel),
                                  'unidade', unidade, 'abertas', a, 'atrasadas', at) order by at desc, a desc), '[]')
                 from (select posto, min(papel) papel, min(unit_id) unit_id, (array_agg(setor_id))[1] setor_id, (array_agg(staff_id))[1] staff_id, min(unidade) unidade,
                              count(*) a, count(*) filter (where atrasada) at
                       from ab group by posto having count(*) filter (where atrasada) > 0
                       order by count(*) filter (where atrasada) desc, count(*) desc limit 15) z) end)
  into v;
  insert into iara.pend_estat_cache (chave, em, resultado) values (concat_ws('|', v_dias, v_regiao, v_tipo, v_nomes), now(), v)
  on conflict (chave) do update set em = excluded.em, resultado = excluded.resultado;
  return v;
end $$;

-- os números da rede valem por 10 minutos (por filtro e por visão com ou sem nomes); a rotina deixa os de abertura prontos
create or replace function api.pend_estatisticas(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public as $$
declare
  v_dias integer := least(greatest(coalesce(nullif(p ->> 'dias', '')::int, 30), 7), 180);
  v_regiao text := nullif(p ->> 'regiao', '');
  v_tipo text := nullif(p ->> 'tipo', '');
  v_nomes boolean := iara.has_perm('pend.nomes');
  v jsonb;
  v_em timestamptz;
begin
  perform iara.require_perm('pend.estatisticas');
  select resultado, em into v, v_em from iara.pend_estat_cache
  where chave = concat_ws('|', v_dias, v_regiao, v_tipo, v_nomes) and em > now() - interval '10 minutes';
  if v is null then
    perform iara.pend_sincronizar_se_preciso(null);
    v := iara.pend_estat_calcular(v_dias, v_regiao, v_tipo, v_nomes);
    v_em := now();
  end if;
  return v || jsonb_build_object('pode_detalhar', iara.has_perm('pend.equipe'), 'calculado_em', v_em);
end $$;

-- mapa: pendências atrasadas e cumprimento do prazo por unidade (sem nomes)
create or replace function api.pend_mapa(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public as $$
declare
  v_camada text := coalesce(nullif(p ->> 'camada', ''), 'pend_atrasadas');
  v_verde constant text := '#16A34A';
  v_amarelo constant text := '#EAB308';
  v_vermelho constant text := '#DC2626';
  v_pontos jsonb;
  v_rank jsonb;
  v_leg jsonb;
  v_res jsonb;
  v_dados jsonb;
begin
  perform iara.require_perm('pend.estatisticas');
  if v_camada not in ('pend_atrasadas', 'pend_prazo') then raise exception 'Mapa desconhecido.' using errcode = '22023'; end if;
  select coalesce(jsonb_agg(to_jsonb(z)), '[]') into v_dados from (
    select u.id unit_id, u.short_name nome, u.lat, u.lng,
           count(*) filter (where q.situacao = 'ABERTA') abertas, count(*) filter (where q.situacao = 'ABERTA' and q.prazo < now()) atrasadas,
           count(*) filter (where q.situacao = 'CONCLUIDA' and q.prazo is not null) concl,
           round(100.0 * count(*) filter (where q.situacao = 'CONCLUIDA' and q.concluida_em <= q.prazo) / nullif(count(*) filter (where q.situacao = 'CONCLUIDA' and q.prazo is not null), 0)) no_prazo
    from iara.education_units u
    join iara.pendencias q on q.unit_id = u.id and q.situacao <> 'CANCELADA' and (q.situacao = 'ABERTA' or q.concluida_em > now() - interval '30 days')
    where u.lat is not null
    group by u.id, u.short_name, u.lat, u.lng) z;
  if v_camada = 'pend_atrasadas' then
    select coalesce(jsonb_agg(jsonb_build_object('lat', lat, 'lng', lng, 'valor', atrasadas,
             'titulo', format('%s: %s pendência(s) atrasada(s) de %s em aberto', nome, atrasadas, abertas),
             'cor', case when atrasadas = 0 then v_verde when atrasadas <= 3 then v_amarelo else v_vermelho end)), '[]') into v_pontos from jsonb_to_recordset(v_dados) as m(unit_id integer, nome text, lat double precision, lng double precision, abertas bigint, atrasadas bigint, concl bigint, no_prazo numeric);
    select coalesce(jsonb_agg(jsonb_build_object('nome', nome, 'valor', atrasadas, 'sufixo', case when atrasadas = 1 then ' atrasada' else ' atrasadas' end,
             'detalhe', format('%s em aberto', abertas)) order by atrasadas desc), '[]') into v_rank
    from (select * from jsonb_to_recordset(v_dados) as m(unit_id integer, nome text, lat double precision, lng double precision, abertas bigint, atrasadas bigint, concl bigint, no_prazo numeric) where atrasadas > 0 order by atrasadas desc, abertas desc limit 10) z;
    v_leg := jsonb_build_array(jsonb_build_object('cor', v_vermelho, 'rotulo', 'Mais de 3 atrasadas'), jsonb_build_object('cor', v_amarelo, 'rotulo', '1 a 3 atrasadas'),
                               jsonb_build_object('cor', v_verde, 'rotulo', 'Nenhuma atrasada'));
    select jsonb_build_array(jsonb_build_object('rotulo', 'Atrasadas nas unidades', 'valor', coalesce(sum(atrasadas), 0)),
                             jsonb_build_object('rotulo', 'Unidades com atraso', 'valor', count(*) filter (where atrasadas > 0)),
                             jsonb_build_object('rotulo', 'Em aberto', 'valor', coalesce(sum(abertas), 0))) into v_res from jsonb_to_recordset(v_dados) as m(unit_id integer, nome text, lat double precision, lng double precision, abertas bigint, atrasadas bigint, concl bigint, no_prazo numeric);
  else
    select coalesce(jsonb_agg(jsonb_build_object('lat', lat, 'lng', lng, 'valor', no_prazo,
             'titulo', format('%s: %s%% concluídas no prazo nos últimos 30 dias (%s concluídas)', nome, coalesce(no_prazo, 0), concl),
             'cor', case when no_prazo >= 90 then v_verde when no_prazo >= 70 then v_amarelo else v_vermelho end)), '[]') into v_pontos
    from jsonb_to_recordset(v_dados) as m(unit_id integer, nome text, lat double precision, lng double precision, abertas bigint, atrasadas bigint, concl bigint, no_prazo numeric) where concl > 0;
    select coalesce(jsonb_agg(jsonb_build_object('nome', nome, 'valor', no_prazo, 'sufixo', '%', 'detalhe', format('%s concluídas', concl)) order by no_prazo, concl desc), '[]') into v_rank
    from (select * from jsonb_to_recordset(v_dados) as m(unit_id integer, nome text, lat double precision, lng double precision, abertas bigint, atrasadas bigint, concl bigint, no_prazo numeric) where concl >= 5 order by no_prazo, concl desc limit 10) z;
    v_leg := jsonb_build_array(jsonb_build_object('cor', v_vermelho, 'rotulo', 'Abaixo de 70% no prazo'), jsonb_build_object('cor', v_amarelo, 'rotulo', '70% a 89%'),
                               jsonb_build_object('cor', v_verde, 'rotulo', '90% ou mais no prazo'));
    select jsonb_build_array(jsonb_build_object('rotulo', 'No prazo na rede', 'valor', round(sum(no_prazo * concl) / nullif(sum(concl) filter (where no_prazo is not null), 0)), 'sufixo', '%'),
                             jsonb_build_object('rotulo', 'Concluídas (30 dias)', 'valor', coalesce(sum(concl), 0))) into v_res from jsonb_to_recordset(v_dados) as m(unit_id integer, nome text, lat double precision, lng double precision, abertas bigint, atrasadas bigint, concl bigint, no_prazo numeric);
  end if;
  return jsonb_build_object('modo', 'taxa', 'sufixo', case when v_camada = 'pend_prazo' then '%' else '' end, 'max', null, 'pontos', v_pontos,
    'legenda', v_leg, 'resumo', v_res,
    'ranking', jsonb_build_object('titulo', case when v_camada = 'pend_prazo' then 'Unidades que menos cumprem o prazo' else 'Unidades com mais pendências atrasadas' end, 'itens', v_rank),
    'nota', 'Pendências das unidades (secretaria escolar, direção, professores e AEE), sem nomes.');
end $$;

-- 15. Oráculo do Prefeito ----------------------------------------------------------------------------------------------------------------
insert into iara.oraculo_temas (tema, rotulo, palavras, ordem) values
  ('pendencias', 'Pendências dos servidores (prazos e procedimentos)', '\mpendenc|\mprocedimentos?\M|\mtarefas? (da|das|dos) (servidor|escola|equipe)|\mem atraso|\matrasad|\mcumprimento (de|do) prazo', 15)
on conflict (tema) do update set rotulo = excluded.rotulo, palavras = excluded.palavras;
insert into iara.oraculo_indicadores (chave, tema, rotulo, consulta, pessoas, sufixo, casas, palavras, palavras_ranking, pior, ordem) values
('pend.abertas', 'pendencias', 'Pendências em aberto dos servidores',
 $q$select count(*) from iara.pendencias where situacao = 'ABERTA' and (unit_id = any ($1) or $2)$q$, false, null, 0, '\mabertas?\M|\mem aberto', '\mpendenc', 'maior', 1),
('pend.atrasadas', 'pendencias', 'Pendências com prazo vencido',
 $q$select count(*) from iara.pendencias where situacao = 'ABERTA' and prazo < now() and (unit_id = any ($1) or $2)$q$, false, null, 0, '\matrasad|\mvencid|\mfora do prazo', '\matrasad|\mvencid', 'maior', 2),
('pend.no_prazo', 'pendencias', 'Pendências concluídas no prazo nos últimos 30 dias',
 $q$select round(100.0 * count(*) filter (where concluida_em <= prazo) / nullif(count(*), 0), 1) from iara.pendencias where situacao = 'CONCLUIDA' and prazo is not null and concluida_em > now() - interval '30 days' and (unit_id = any ($1) or $2)$q$, false, '%', 1, '\mno prazo|\mcumpr', '\mprazo', 'menor', 3),
('pend.tempo', 'pendencias', 'Tempo médio para resolver uma pendência (dias, últimos 30 dias)',
 $q$select round((avg(extract(epoch from concluida_em - criada_em)) / 86400.0)::numeric, 1) from iara.pendencias where situacao = 'CONCLUIDA' and concluida_em > now() - interval '30 days' and (unit_id = any ($1) or $2)$q$, false, ' dias', 1, '\mtempo|\mdemora|\mquantos dias', null, 'maior', 4)
on conflict (chave) do update set tema = excluded.tema, rotulo = excluded.rotulo, consulta = excluded.consulta, pessoas = excluded.pessoas, sufixo = excluded.sufixo,
  casas = excluded.casas, palavras = excluded.palavras, palavras_ranking = excluded.palavras_ranking, pior = excluded.pior, ordem = excluded.ordem;

-- 16. LGPD -------------------------------------------------------------------------------------------------------------------------------
insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('pendencias', 'detalhe', 'INTERNO', 'descrição da tarefa (pode citar quantidade de alunos, sem nomes)', 'cumprimento de procedimentos', 'o responsável e a chefia'),
  ('pendencias', 'conclusao', 'INTERNO', 'nota de conclusão do servidor', 'rastreabilidade', 'o responsável e a chefia'),
  ('pendencias', 'concluida_por_label', 'PESSOAL', 'autoria', 'rastreabilidade', 'o responsável e a chefia'),
  ('pendencias', 'atribuida_por_label', 'PESSOAL', 'autoria', 'rastreabilidade', 'o responsável e a chefia'),
  ('pend_eventos', 'texto', 'INTERNO', 'cobrança, devolução ou nota', 'acompanhamento pela chefia', 'o responsável e a chefia'),
  ('pend_eventos', 'autor_label', 'PESSOAL', 'autoria', 'rastreabilidade', 'o responsável e a chefia'),
  ('pend_rotinas', 'criada_por_label', 'PESSOAL', 'autoria', 'rastreabilidade', 'SEDUC e direção')
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

-- 17. Rotina: procedimentos do dia e sincronização a cada 10 minutos ------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('iara-pendencias', '*/10 * * * *', $c$select iara.pend_rotina()$c$);
  end if;
end $$;

revoke all on function iara.pend_eu(), iara.pend_subarvore(uuid), iara.pend_setor(text), iara.pend_posto_partes(text), iara.pend_json(iara.pendencias),
  iara.pend_rotinas_gerar(uuid, date), iara.pend_resolvida_em(iara.pendencias), iara.pend_historico_reconstruir(integer), iara.pend_fontes(integer), iara.pend_sincronizar(integer), iara.pend_sincronizar_se_preciso(integer), iara.pend_rotina(),
  iara.pend_posto_rotulo(text, integer, uuid, uuid), iara.pend_papel_rotulo(text), iara.pend_turmas(uuid, integer), iara.pend_estat_calcular(integer, text, text, boolean) from public;

commit;
