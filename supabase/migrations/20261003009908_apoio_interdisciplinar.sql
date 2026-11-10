-- IARA Educa — 099.08 · Apoio pedagógico interdisciplinar, dentro do AEE
-- As oito áreas publicadas pela SEDUC (portal da Prefeitura, Educação → Apoio Pedagógico Interdisciplinar): orientação educacional,
-- acompanhamento pedagógico (psicopedagogia), assessoria da educação especial e inclusão (SRM, professor de apoio, estimulação essencial,
-- escola bilíngue para surdos), formação em educação especial, psicologia escolar, fonoaudiologia escolar, deficiência visual e
-- altas habilidades/superdotação. Contato oficial da gerência: (44) 3221-6936 · seduc_apoiopedagogico@maringa.pr.gov.br.
-- Fluxo (decisão de Rob, 10/11/2026):
--   • a unidade (direção, secretaria escolar ou AEE) faz o encaminhamento formal à gerência;
--   • a família conhece os serviços e pede avaliação pelo portal ou pela IARA; o pedido vai para a unidade analisar e encaminhar;
--   • a gerência distribui ao profissional da área; o profissional registra triagem, atendimentos e encaminhamentos;
--   • o registro técnico é sigiloso (códigos de ética do CFP e do CFFa): só o autor e a chefia veem. A escola vê o encaminhamento,
--     a situação e as orientações que o profissional liberar; a família vê o andamento e as orientações liberadas para ela, com ciência.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

-- 1. Perfis e permissões ------------------------------------------------------------------------------------------------------------
insert into iara.organizational_roles (code, tenant_id, name, short_name, description, scope_type, stage_filter, question, org_unit, is_persona, sort) values
  ('GERENCIA_APOIO', 1, 'Gerência de Educação Especial e Apoio Interdisciplinar', 'Gerência de apoio',
   'Encaminhamentos das unidades e pedidos das famílias por área, distribuição aos profissionais, tempo de espera e orientações.',
   'NETWORK', null, 'Algum caso está esperando demais?', 'Gerência de Educação Especial e Apoio Pedagógico Interdisciplinar', true, 18),
  ('APOIO_INTERDISCIPLINAR', 1, 'Equipe de apoio · psicologia, fono e psicopedagogia', 'Apoio interdisciplinar',
   'Casos atribuídos, triagens, atendimentos, registro técnico sigiloso e orientações à escola e à família.',
   'NETWORK', null, 'Quem eu atendo hoje?', 'Gerência de Educação Especial e Apoio Pedagógico Interdisciplinar', true, 19)
on conflict (code) do update set name = excluded.name, short_name = excluded.short_name, description = excluded.description,
  scope_type = excluded.scope_type, question = excluded.question, org_unit = excluded.org_unit, is_persona = excluded.is_persona, sort = excluded.sort;

insert into iara.permissions (code, description, is_sensitive) values
  ('apoio.read', 'Ver os encaminhamentos ao apoio interdisciplinar e as orientações liberadas (sem o registro técnico)', true),
  ('apoio.encaminhar', 'Encaminhar aluno ao apoio interdisciplinar e analisar os pedidos das famílias', true),
  ('apoio.atender', 'Registrar triagem, atendimentos e orientações (profissional do apoio interdisciplinar)', true),
  ('apoio.gerir', 'Distribuir casos aos profissionais e acompanhar a fila do apoio interdisciplinar', true),
  ('apoio.chefia', 'Chefia do apoio interdisciplinar: vê o registro técnico de toda a equipe', true)
on conflict (code) do update set description = excluded.description;
insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('GERENCIA_APOIO', 'units.read'), ('GERENCIA_APOIO', 'config.read'), ('GERENCIA_APOIO', 'students.read'), ('GERENCIA_APOIO', 'aee.read'),
  ('GERENCIA_APOIO', 'apoio.read'), ('GERENCIA_APOIO', 'apoio.atender'), ('GERENCIA_APOIO', 'apoio.gerir'), ('GERENCIA_APOIO', 'apoio.chefia'), ('GERENCIA_APOIO', 'apoio.encaminhar'),
  -- o profissional não lê a ficha de toda a rede: vê os alunos pelos casos atribuídos (api.apoio_caso)
  ('APOIO_INTERDISCIPLINAR', 'units.read'), ('APOIO_INTERDISCIPLINAR', 'config.read'),
  ('APOIO_INTERDISCIPLINAR', 'apoio.read'), ('APOIO_INTERDISCIPLINAR', 'apoio.atender'),
  ('SECRETARIO', 'apoio.read'), ('SECRETARIO', 'apoio.gerir'), ('SUPERINTENDENCIA', 'apoio.read'), ('SUPERINTENDENCIA', 'apoio.gerir'),
  ('DIRETOR_UNIDADE', 'apoio.read'), ('DIRETOR_UNIDADE', 'apoio.encaminhar'),
  ('SECRETARIA_ESCOLAR', 'apoio.read'), ('SECRETARIA_ESCOLAR', 'apoio.encaminhar'),
  ('PROFESSOR_AEE', 'apoio.read'), ('PROFESSOR_AEE', 'apoio.encaminhar'),
  ('GERENCIA_EI', 'apoio.read')
) v(r, p)
on conflict do nothing;
-- o perfil de profissional e de gerência também lê a ficha dos alunos que atende (escopo pela função de acesso abaixo)

-- 2. Tabelas ------------------------------------------------------------------------------------------------------------------------
create table if not exists iara.apoio_areas (
  codigo text primary key,
  nome text not null,
  resumo text not null,
  servicos text[] not null default '{}',
  publico text,
  profissional text,
  pode_pedir boolean not null default true,
  palavras text,
  ordem smallint not null default 0,
  fonte text not null default 'OFICIAL'
);
create table if not exists iara.apoio_profissionais (
  staff_id uuid primary key references iara.staff(id) on delete cascade,
  area_codigo text not null references iara.apoio_areas(codigo),
  registro_conselho text,
  ativo boolean not null default true,
  is_demo boolean not null default false
);
create sequence if not exists iara.apoio_caso_seq;
create table if not exists iara.apoio_casos (
  id uuid primary key default gen_random_uuid(),
  numero text not null unique default ('API-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('iara.apoio_caso_seq')::text, 5, '0')),
  student_id uuid not null references iara.students(id) on delete cascade,
  unit_id integer references iara.education_units(id),
  area_codigo text not null references iara.apoio_areas(codigo),
  origem text not null check (origem in ('UNIDADE', 'FAMILIA', 'AEE', 'CONSELHO_CLASSE', 'GERENCIA')),
  motivo text not null,
  analise_unidade text,
  solicitado_por_label text,
  solicitado_guardian uuid references iara.guardians(id) on delete set null,
  situacao text not null check (situacao in ('PEDIDO_FAMILIA', 'ENCAMINHADO', 'EM_TRIAGEM', 'EM_ATENDIMENTO', 'AGUARDANDO_REDE', 'CONCLUIDO', 'NAO_ACEITO', 'ARQUIVADO')),
  prioridade text not null default 'NORMAL' check (prioridade in ('NORMAL', 'ALTA')),
  profissional_staff uuid references iara.staff(id) on delete set null,
  encaminhado_em timestamptz,
  atribuido_em timestamptz,
  primeiro_atendimento_em timestamptz,
  concluido_em timestamptz,
  conclusao text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_demo boolean not null default false
);
create index if not exists apoio_casos_aluno_idx on iara.apoio_casos (student_id);
create index if not exists apoio_casos_sit_idx on iara.apoio_casos (situacao, area_codigo);
create index if not exists apoio_casos_prof_idx on iara.apoio_casos (profissional_staff) where situacao in ('EM_TRIAGEM', 'EM_ATENDIMENTO', 'AGUARDANDO_REDE');
create table if not exists iara.apoio_registros (
  id uuid primary key default gen_random_uuid(),
  caso_id uuid not null references iara.apoio_casos(id) on delete cascade,
  staff_id uuid references iara.staff(id) on delete set null,
  autor_label text,
  data date not null default current_date,
  tipo text not null check (tipo in ('TRIAGEM', 'AVALIACAO', 'ATENDIMENTO', 'ORIENTACAO_FAMILIA', 'ORIENTACAO_ESCOLA', 'REUNIAO', 'ENCAMINHAMENTO_EXTERNO', 'DEVOLUTIVA')),
  presenca text check (presenca in ('PRESENTE', 'FALTOU')),
  registro_tecnico text,
  orientacao_escola text,
  orientacao_familia text,
  familia_ciente_em timestamptz,
  familia_ciente_canal text,
  created_at timestamptz not null default now(),
  is_demo boolean not null default false
);
create index if not exists apoio_registros_caso_idx on iara.apoio_registros (caso_id, data desc);
alter table iara.apoio_areas enable row level security;
alter table iara.apoio_profissionais enable row level security;
alter table iara.apoio_casos enable row level security;
alter table iara.apoio_registros enable row level security;

-- 3. As oito áreas (texto do portal da Prefeitura, resumido) -------------------------------------------------------------------------
insert into iara.apoio_areas (codigo, nome, resumo, servicos, publico, profissional, pode_pedir, palavras, ordem) values
  ('ORIENTACAO_EDUCACIONAL', 'Orientação educacional',
   'Acompanha o ensino e a aprendizagem em todas as unidades: orienta professores nas intervenções, media conflitos, orienta famílias e encaminha casos a outros serviços.',
   array['Orientação aos professores (defasagem, dificuldades de aprendizagem, deficiência)', 'Mediação de conflitos na escola', 'Orientação às famílias e reuniões', 'Encaminhamento a outras políticas e serviços'],
   'Educação Infantil e Ensino Fundamental', 'Orientador(a) educacional', true, 'orientac|conflito|comportamento|briga|adapta', 1),
  ('ACOMPANHAMENTO_PEDAGOGICO', 'Acompanhamento pedagógico (psicopedagogia)',
   'Ajuda o aluno a superar dificuldades de aprendizagem — dislexia, disortografia, disgrafia, discalculia, TDAH, DDA ou dificuldades gerais — com pedagogos especialistas em psicopedagogia.',
   array['Atendimento a dificuldades específicas e gerais de aprendizagem', 'Raciocínio lógico e compreensão dos conteúdos'],
   'Ensino Fundamental', 'Pedagogo(a) com especialização em psicopedagogia', true, 'psicopedag|dislex|discalc|disgraf|disortograf|tdah|dda|deficit de atencao|dificuldade (de|para) aprend|nao aprende|nao consegue (ler|escrever)', 2),
  ('EDUCACAO_ESPECIAL', 'Educação especial e inclusão',
   'Atendimento educacional especializado: salas de recursos multifuncionais, professor de apoio em sala, estimulação essencial (0 a 3 anos com atraso no desenvolvimento) e a escola municipal bilíngue para surdos.',
   array['Sala de Recursos Multifuncional (SRM)', 'Professor(a) de apoio em sala de aula', 'Estimulação essencial (0 a 3 anos)', 'Escola municipal bilíngue para surdos'],
   'Alunos com deficiência, TEA e atraso no desenvolvimento', 'Professor(a) do AEE e da estimulação essencial', true, 'estimulac|atraso no desenvolvimento|surd|libras|professora? de apoio|sala de recurso', 3),
  ('FORMACAO', 'Formação em educação especial',
   'Formação continuada de professores, coordenadores, gestores e equipes: legislação inclusiva, deficiências e transtornos, tecnologias assistivas, PAEE, PEI e práticas colaborativas.',
   array['Educação inclusiva e legislação', 'Deficiências, transtornos e estratégias de ensino', 'Recursos acessíveis e tecnologia assistiva', 'Elaboração do PAEE e do PEI', 'Planejamento integrado sala comum e AEE'],
   'Servidores da área pedagógica', 'Formador(a) em educação especial', false, 'formac|capacitac|curso', 4),
  ('PSICOLOGIA', 'Psicologia escolar e educacional',
   'Apoia todas as modalidades (Educação Infantil, Fundamental, Educação Especial, Ampliação da Jornada e EJA): acompanha a aprendizagem, forma equipes, atende famílias, media conflitos e articula a rede (Conselho Tutelar, Ministério Público, APAE).',
   array['Acompanhamento do processo de ensino e aprendizagem', 'Atendimento às famílias', 'Mediação de conflitos', 'Articulação com a rede de proteção'],
   'Todas as modalidades', 'Psicólogo(a) escolar', true, 'psicolog|ansiedade|ansios|emocional|tristeza|luto|comportamento', 5),
  ('FONOAUDIOLOGIA', 'Fonoaudiologia escolar',
   'Audição, linguagem oral e escrita: triagens, orientação a professores e famílias, assessoria para adaptar atividades e encaminhamento aos serviços de saúde.',
   array['Triagem fonoaudiológica (audição e linguagem)', 'Orientação a professores e famílias', 'Encaminhamento aos serviços de saúde', 'Assessoria aos professores'],
   'Educação Infantil e Ensino Fundamental', 'Fonoaudiólogo(a)', true, 'fono|fala|gaguej|troca letras|troca as letras|nao fala|audic|escuta|linguagem', 6),
  ('DEFICIENCIA_VISUAL', 'Deficiência visual',
   'Braille, tecnologias assistivas (reglete, sorobã, ampliadores, leitores de tela), estimulação sensorial, orientação e mobilidade e adaptação de materiais, com orientação à família e à equipe.',
   array['Ensino do Braille', 'Tecnologia assistiva', 'Orientação e mobilidade', 'Adaptação de materiais'],
   'Alunos cegos ou com baixa visão', 'Professor(a) do AEE para deficiência visual', true, 'cego|cegueira|baixa visao|braille|enxerga', 7),
  ('ALTAS_HABILIDADES', 'Altas habilidades/superdotação',
   'Triagem em sala (observação, instrumentos, entrevistas com família e professores) e, com indícios, avaliação e acompanhamento multiprofissional: enriquecimento curricular, mentorias, flexibilização e orientação à família.',
   array['Triagem educacional', 'Enriquecimento curricular e desafios', 'Atendimento individual ou em pequenos grupos', 'Flexibilização e aceleração quando cabível', 'Orientação à família'],
   'Ensino Fundamental', 'Equipe multiprofissional de AH/SD', true, 'altas habilidades|superdot|muito inteligente|aprende muito rapido|adiantad', 8)
on conflict (codigo) do update set nome = excluded.nome, resumo = excluded.resumo, servicos = excluded.servicos, publico = excluded.publico,
  profissional = excluded.profissional, pode_pedir = excluded.pode_pedir, palavras = excluded.palavras, ordem = excluded.ordem;

-- 4. Acesso --------------------------------------------------------------------------------------------------------------------------
create or replace function iara.apoio_situacao_rotulo(p text) returns text
language sql immutable
as $$
  select case p when 'PEDIDO_FAMILIA' then 'Pedido da família (a escola analisa)' when 'ENCAMINHADO' then 'Encaminhado à gerência'
    when 'EM_TRIAGEM' then 'Em triagem' when 'EM_ATENDIMENTO' then 'Em atendimento' when 'AGUARDANDO_REDE' then 'Aguardando a rede (saúde ou proteção)'
    when 'CONCLUIDO' then 'Concluído' when 'NAO_ACEITO' then 'Não encaminhado' when 'ARQUIVADO' then 'Arquivado' else p end
$$;

-- vê o caso: a unidade do aluno, o AEE da unidade, o profissional atribuído, a gerência e a SEDUC
create or replace function iara.apoio_pode_ver(c iara.apoio_casos) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select iara.has_perm('apoio.read') and (
    iara.has_perm('apoio.gerir')
    or (iara.my_scope() = 'UNIT' and c.unit_id = iara.my_unit())
    or (iara.has_perm('apoio.atender') and (c.profissional_staff = (select staff_id from iara.app_users where id = iara.current_user_id())
                                            or c.area_codigo = (select ap.area_codigo from iara.apoio_profissionais ap join iara.app_users au on au.staff_id = ap.staff_id
                                                                where au.id = iara.current_user_id()) and c.profissional_staff is null)))
$$;

-- o registro técnico: só o autor e a chefia
create or replace function iara.apoio_ve_tecnico(r iara.apoio_registros) returns boolean
language sql stable security definer set search_path = iara, public
as $$ select iara.has_perm('apoio.chefia') or (r.staff_id is not null and r.staff_id = (select staff_id from iara.app_users where id = iara.current_user_id())) $$;

create or replace function iara.apoio_caso_json(c iara.apoio_casos, p_detalhe boolean default false) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', c.id, 'numero', c.numero, 'student_id', c.student_id, 'aluno', s.full_name, 'unit_id', c.unit_id, 'unidade', u.short_name,
      'area', c.area_codigo, 'area_nome', a.nome, 'origem', c.origem, 'motivo', c.motivo, 'analise_unidade', c.analise_unidade, 'solicitado_por', c.solicitado_por_label,
      'situacao', c.situacao, 'situacao_rotulo', iara.apoio_situacao_rotulo(c.situacao), 'prioridade', c.prioridade,
      'profissional', st.full_name, 'profissional_id', c.profissional_staff, 'encaminhado_em', c.encaminhado_em, 'atribuido_em', c.atribuido_em,
      'primeiro_atendimento_em', c.primeiro_atendimento_em, 'concluido_em', c.concluido_em, 'conclusao', c.conclusao, 'created_at', c.created_at,
      'dias_espera', case when c.situacao in ('ENCAMINHADO', 'PEDIDO_FAMILIA') then (iara.hoje_local() - coalesce(c.encaminhado_em, c.created_at)::date) end,
      'etapa', (select g.short_name from iara.enrollments e join iara.classes cl on cl.id = e.class_id join iara.grade_levels g on g.id = cl.grade_level_id
                where e.student_id = c.student_id and e.status = 'ACTIVE' limit 1),
      'n_registros', (select count(*) from iara.apoio_registros r where r.caso_id = c.id), 'is_demo', c.is_demo)
    || case when p_detalhe then jsonb_build_object(
      'registros', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'data', r.data, 'tipo', r.tipo, 'presenca', r.presenca, 'autor', r.autor_label,
                      'registro_tecnico', case when iara.apoio_ve_tecnico(r) then r.registro_tecnico end, 'tem_tecnico', r.registro_tecnico is not null,
                      'orientacao_escola', r.orientacao_escola, 'orientacao_familia', r.orientacao_familia, 'familia_ciente_em', r.familia_ciente_em,
                      'created_at', r.created_at) order by r.data desc, r.created_at desc), '[]') from iara.apoio_registros r where r.caso_id = c.id),
      'aee', (select jsonb_build_object('modalidade', pl.modalidade, 'situacao', pl.situacao) from iara.aee_planos pl where pl.student_id = c.student_id and pl.situacao in ('ATIVO', 'EM_REVISAO') limit 1),
      'outros', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'numero', o.numero, 'area_nome', oa.nome, 'situacao_rotulo', iara.apoio_situacao_rotulo(o.situacao),
                   'created_at', o.created_at) order by o.created_at desc), '[]')
                 from iara.apoio_casos o join iara.apoio_areas oa on oa.codigo = o.area_codigo where o.student_id = c.student_id and o.id <> c.id and iara.apoio_pode_ver(o)),
      'pode_atender', iara.has_perm('apoio.atender') and (c.profissional_staff = (select staff_id from iara.app_users where id = iara.current_user_id()) or iara.has_perm('apoio.chefia')),
      'pode_atribuir', iara.has_perm('apoio.gerir'),
      'pode_analisar', iara.has_perm('apoio.encaminhar') and iara.my_scope() = 'UNIT' and c.unit_id = iara.my_unit() and c.situacao = 'PEDIDO_FAMILIA') else '{}'::jsonb end
  from iara.students s, iara.apoio_areas a, iara.education_units u
  left join iara.staff st on st.id = c.profissional_staff
  where s.id = c.student_id and a.codigo = c.area_codigo and u.id = c.unit_id
$$;

-- 5. Família (portal e IARA) ------------------------------------------------------------------------------------------------------------
create or replace function api.apoio_areas(p jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('areas', (select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'nome', nome, 'resumo', resumo, 'servicos', servicos, 'publico', publico,
              'profissional', profissional, 'pode_pedir', pode_pedir) order by ordem), '[]') from iara.apoio_areas),
    'contato', jsonb_build_object('telefone', '(44) 3221-6936', 'email', 'seduc_apoiopedagogico@maringa.pr.gov.br',
              'fonte', 'https://www.maringa.pr.gov.br/portal/19/educacao/post/698'))
$$;

create or replace function api.familia_apoio(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_ids uuid[];
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  select array_agg(x) into v_ids from iara.my_student_ids() x;
  return api.apoio_areas('{}'::jsonb) || jsonb_build_object(
    'filhos', (select coalesce(jsonb_agg(jsonb_build_object('student_id', s.id, 'primeiro_nome', split_part(s.full_name, ' ', 1), 'unidade', u.short_name) order by s.full_name), '[]')
               from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' left join iara.education_units u on u.id = e.unit_id
               where s.id = any (v_ids)),
    'casos', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'numero', c.numero, 'student_id', c.student_id, 'primeiro_nome', split_part(s.full_name, ' ', 1),
                'area', a.nome, 'situacao', c.situacao, 'situacao_rotulo', iara.apoio_situacao_rotulo(c.situacao), 'created_at', c.created_at,
                'encaminhado_em', c.encaminhado_em, 'profissional', case when c.situacao in ('EM_TRIAGEM', 'EM_ATENDIMENTO', 'AGUARDANDO_REDE', 'CONCLUIDO') then st.full_name end,
                'profissional_funcao', case when c.profissional_staff is not null then a.profissional end,
                'resposta_unidade', case when c.situacao = 'NAO_ACEITO' then c.analise_unidade end, 'conclusao', case when c.situacao = 'CONCLUIDO' then c.conclusao end,
                'orientacoes', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'data', r.data, 'texto', r.orientacao_familia, 'autor', r.autor_label,
                                  'enviado_em', r.created_at, 'ciente_em', r.familia_ciente_em) order by r.created_at desc), '[]')
                                from iara.apoio_registros r where r.caso_id = c.id and r.orientacao_familia is not null)) order by c.created_at desc), '[]')
              from iara.apoio_casos c join iara.students s on s.id = c.student_id join iara.apoio_areas a on a.codigo = c.area_codigo
              left join iara.staff st on st.id = c.profissional_staff
              where c.student_id = any (v_ids) and c.situacao <> 'ARQUIVADO'),
    'pendentes_ciencia', (select count(*) from iara.apoio_registros r join iara.apoio_casos c on c.id = r.caso_id
                          where c.student_id = any (v_ids) and r.orientacao_familia is not null and r.familia_ciente_em is null));
end $$;

create or replace function api.familia_apoio_pedir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_area text := p ->> 'area';
  v_motivo text := nullif(btrim(coalesce(p ->> 'motivo', '')), '');
  v_unit integer;
  c iara.apoio_casos;
begin
  if iara.my_guardian() is null or v_student is null or v_student not in (select iara.my_student_ids()) then
    raise exception 'Criança não encontrada na sua família.' using errcode = 'P0002'; end if;
  if not exists (select 1 from iara.apoio_areas where codigo = v_area and pode_pedir) then raise exception 'Escolha a área do apoio.' using errcode = '22023'; end if;
  if coalesce(length(v_motivo), 0) < 10 then raise exception 'Conte em poucas palavras o que você tem percebido (pelo menos 10 letras).' using errcode = '22023'; end if;
  select unit_id into v_unit from iara.enrollments where student_id = v_student and status = 'ACTIVE' limit 1;
  if v_unit is null then raise exception 'O apoio interdisciplinar atende alunos matriculados na rede.' using errcode = '22023'; end if;
  if exists (select 1 from iara.apoio_casos where student_id = v_student and area_codigo = v_area and situacao in ('PEDIDO_FAMILIA', 'ENCAMINHADO', 'EM_TRIAGEM', 'EM_ATENDIMENTO', 'AGUARDANDO_REDE')) then
    raise exception 'Já existe um pedido desta área em andamento para esta criança. Acompanhe por aqui.' using errcode = '22023'; end if;
  insert into iara.apoio_casos (student_id, unit_id, area_codigo, origem, motivo, solicitado_por_label, solicitado_guardian, situacao)
  values (v_student, v_unit, v_area, 'FAMILIA', v_motivo, iara.my_label(), iara.my_guardian(), 'PEDIDO_FAMILIA')
  returning * into c;
  perform iara.audit_event('APOIO_PEDIDO_FAMILIA', 'apoio_caso', c.id::text, v_unit, format('Família pediu apoio (%s): %s.', (select nome from iara.apoio_areas where codigo = v_area), c.numero));
  return jsonb_build_object('ok', true, 'id', c.id, 'numero', c.numero,
    'mensagem', format('Pedido %s registrado. A escola analisa com a família e, se for o caso, encaminha à gerência do apoio interdisciplinar. Você acompanha por aqui.', c.numero));
end $$;

create or replace function api.familia_apoio_ciente(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r iara.apoio_registros;
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  update iara.apoio_registros x set familia_ciente_em = coalesce(familia_ciente_em, now()),
         familia_ciente_canal = coalesce(familia_ciente_canal, case when p ->> 'canal' = 'WHATSAPP' then 'WHATSAPP' else 'PORTAL' end)
  from iara.apoio_casos c
  where x.id = (p ->> 'id')::uuid and c.id = x.caso_id and c.student_id in (select iara.my_student_ids()) and x.orientacao_familia is not null
  returning x.* into r;
  if r.id is null then raise exception 'Orientação não encontrada.' using errcode = 'P0002'; end if;
  perform iara.audit_event('APOIO_CIENCIA', 'apoio_registro', r.id::text, null, 'Ciência da família numa orientação do apoio interdisciplinar.');
  return jsonb_build_object('ok', true, 'ciente_em', r.familia_ciente_em);
end $$;

-- 6. Escola, gerência e profissionais ----------------------------------------------------------------------------------------------------
create or replace function api.apoio_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_area text := nullif(p ->> 'area', '');
  v_sit text := nullif(p ->> 'situacao', '');
  v_busca text := nullif(iara.norm(btrim(coalesce(p ->> 'busca', ''))), '');
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_meu uuid := (select staff_id from iara.app_users where id = iara.current_user_id());
  v_meus boolean := coalesce((p ->> 'meus')::boolean, iara.has_perm('apoio.atender') and not iara.has_perm('apoio.gerir'));
begin
  perform iara.require_perm('apoio.read');
  return (with base as (
      select c from iara.apoio_casos c
      where iara.apoio_pode_ver(c) and (v_unit is null or c.unit_id = v_unit) and c.situacao <> 'ARQUIVADO')
    select jsonb_build_object(
      'contagem', (select coalesce(jsonb_object_agg(s, n), '{}') from (select (b.c).situacao s, count(*) n from base b group by 1) z),
      'por_area', (select coalesce(jsonb_agg(jsonb_build_object('area', a.codigo, 'nome', a.nome, 'abertos', z.abertos, 'sem_profissional', z.sem_prof,
                     'espera_media', z.espera, 'espera_maxima', z.maxima, 'concluidos_90', z.concl) order by a.ordem), '[]')
                   from iara.apoio_areas a left join lateral (
                     select count(*) filter (where (b.c).situacao in ('ENCAMINHADO', 'EM_TRIAGEM', 'EM_ATENDIMENTO', 'AGUARDANDO_REDE')) abertos,
                            count(*) filter (where (b.c).situacao = 'ENCAMINHADO') sem_prof,
                            round(avg(iara.hoje_local() - coalesce((b.c).encaminhado_em, (b.c).created_at)::date) filter (where (b.c).situacao = 'ENCAMINHADO')) espera,
                            max(iara.hoje_local() - coalesce((b.c).encaminhado_em, (b.c).created_at)::date) filter (where (b.c).situacao = 'ENCAMINHADO') maxima,
                            count(*) filter (where (b.c).situacao = 'CONCLUIDO' and (b.c).concluido_em > now() - interval '90 days') concl
                     from base b where (b.c).area_codigo = a.codigo) z on true where a.codigo <> 'FORMACAO'),
      'pedidos_familia', (select count(*) from base b where (b.c).situacao = 'PEDIDO_FAMILIA'),
      'atrasados', (select count(*) from base b where (b.c).situacao = 'ENCAMINHADO' and coalesce((b.c).encaminhado_em, (b.c).created_at) < now() - interval '30 days'),
      'meus_abertos', (select count(*) from base b where (b.c).profissional_staff = v_meu and (b.c).situacao in ('EM_TRIAGEM', 'EM_ATENDIMENTO', 'AGUARDANDO_REDE')),
      'pode_encaminhar', iara.has_perm('apoio.encaminhar') and iara.my_scope() = 'UNIT',
      'pode_atribuir', iara.has_perm('apoio.gerir'), 'atende', iara.has_perm('apoio.atender'),
      'minha_area', (select ap.area_codigo from iara.apoio_profissionais ap where ap.staff_id = v_meu),
      'eu', (select full_name from iara.staff where id = v_meu),
      'contato', jsonb_build_object('telefone', '(44) 3221-6936', 'email', 'seduc_apoiopedagogico@maringa.pr.gov.br'),
      'itens', (select coalesce(jsonb_agg(iara.apoio_caso_json(x.c) order by x.ord), '[]') from (
          select b.c, row_number() over (order by case (b.c).situacao when 'PEDIDO_FAMILIA' then 0 when 'ENCAMINHADO' then 1 when 'EM_TRIAGEM' then 2
                                                   when 'EM_ATENDIMENTO' then 3 when 'AGUARDANDO_REDE' then 4 else 5 end,
                                                   (b.c).prioridade = 'ALTA' desc, coalesce((b.c).encaminhado_em, (b.c).created_at)) ord
          from base b join iara.students s on s.id = (b.c).student_id
          where (v_area is null or (b.c).area_codigo = v_area)
            and (v_sit is null or (b.c).situacao = v_sit or (v_sit = 'ABERTOS' and (b.c).situacao not in ('CONCLUIDO', 'NAO_ACEITO')))
            and (not v_meus or (b.c).profissional_staff = v_meu or ((b.c).profissional_staff is null and v_sit is null and false))
            and (v_busca is null or iara.norm(s.full_name) like '%' || v_busca || '%' or (b.c).numero ilike '%' || v_busca || '%')
          order by ord limit 400) x)));
end $$;

create or replace function api.apoio_caso(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  c iara.apoio_casos;
begin
  perform iara.require_perm('apoio.read');
  select * into c from iara.apoio_casos where id = (p ->> 'id')::uuid;
  if c.id is null or not iara.apoio_pode_ver(c) then raise exception 'Caso não encontrado.' using errcode = 'P0002'; end if;
  return iara.apoio_caso_json(c, true) || jsonb_build_object(
    'profissionais', case when iara.has_perm('apoio.gerir') then (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.full_name, 'area', ap.area_codigo,
        'abertos', (select count(*) from iara.apoio_casos x where x.profissional_staff = s.id and x.situacao in ('EM_TRIAGEM', 'EM_ATENDIMENTO', 'AGUARDANDO_REDE')))
        order by ap.area_codigo <> c.area_codigo, s.full_name), '[]') from iara.apoio_profissionais ap join iara.staff s on s.id = ap.staff_id where ap.ativo) end);
end $$;

-- a unidade encaminha um aluno (ou responde ao pedido da família: encaminha ou explica por que não)
create or replace function api.apoio_encaminhar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.apoio_casos;
  v_student uuid := nullif(p ->> 'student_id', '')::uuid;
  v_area text := p ->> 'area';
  v_motivo text := nullif(btrim(coalesce(p ->> 'motivo', '')), '');
  v_aceitar boolean := coalesce((p ->> 'aceitar')::boolean, true);
begin
  perform iara.require_perm('apoio.encaminhar');
  if nullif(p ->> 'id', '') is not null then
    -- resposta ao pedido da família
    select * into c from iara.apoio_casos where id = (p ->> 'id')::uuid for update;
    if c.id is null or iara.my_scope() <> 'UNIT' or c.unit_id <> iara.my_unit() then raise exception 'Pedido não encontrado.' using errcode = 'P0002'; end if;
    if c.situacao <> 'PEDIDO_FAMILIA' then raise exception 'Este pedido já foi analisado.' using errcode = '22023'; end if;
    if coalesce(length(v_motivo), 0) < 10 then raise exception 'Registre a análise da escola (pelo menos 10 letras).' using errcode = '22023'; end if;
    update iara.apoio_casos set situacao = case when v_aceitar then 'ENCAMINHADO' else 'NAO_ACEITO' end, analise_unidade = v_motivo,
           encaminhado_em = case when v_aceitar then now() end, area_codigo = coalesce(nullif(v_area, ''), area_codigo),
           prioridade = case when p ->> 'prioridade' = 'ALTA' then 'ALTA' else prioridade end, updated_at = now()
    where id = c.id returning * into c;
    perform iara.audit_event('APOIO_ANALISE', 'apoio_caso', c.id::text, c.unit_id, format('Pedido da família %s %s.', c.numero, case when v_aceitar then 'encaminhado à gerência' else 'não encaminhado' end));
    return iara.apoio_caso_json(c, true);
  end if;
  if v_student is null or not iara.can_access_student(v_student) then raise exception 'Aluno não encontrado.' using errcode = 'P0002'; end if;
  if not exists (select 1 from iara.apoio_areas where codigo = v_area and codigo <> 'FORMACAO') then raise exception 'Escolha a área.' using errcode = '22023'; end if;
  if coalesce(length(v_motivo), 0) < 20 then raise exception 'Descreva o que a escola observou e o que já tentou (pelo menos 20 letras).' using errcode = '22023'; end if;
  if exists (select 1 from iara.apoio_casos where student_id = v_student and area_codigo = v_area and situacao in ('ENCAMINHADO', 'EM_TRIAGEM', 'EM_ATENDIMENTO', 'AGUARDANDO_REDE')) then
    raise exception 'Este aluno já tem um encaminhamento desta área em andamento.' using errcode = '22023'; end if;
  insert into iara.apoio_casos (student_id, unit_id, area_codigo, origem, motivo, solicitado_por_label, situacao, prioridade, encaminhado_em)
  values (v_student, (select unit_id from iara.enrollments where student_id = v_student and status = 'ACTIVE' limit 1), v_area,
          case when iara.my_role() = 'PROFESSOR_AEE' then 'AEE' else 'UNIDADE' end, v_motivo, iara.my_label(), 'ENCAMINHADO',
          case when p ->> 'prioridade' = 'ALTA' then 'ALTA' else 'NORMAL' end, now())
  returning * into c;
  perform iara.audit_event('APOIO_ENCAMINHAMENTO', 'apoio_caso', c.id::text, c.unit_id, format('Encaminhamento %s ao apoio interdisciplinar (%s).', c.numero, (select nome from iara.apoio_areas where codigo = v_area)));
  return iara.apoio_caso_json(c, true);
end $$;

create or replace function api.apoio_atribuir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.apoio_casos;
  v_staff uuid := (p ->> 'staff_id')::uuid;
begin
  perform iara.require_perm('apoio.gerir');
  if not exists (select 1 from iara.apoio_profissionais where staff_id = v_staff and ativo) then raise exception 'Escolha um profissional da equipe.' using errcode = '22023'; end if;
  update iara.apoio_casos set profissional_staff = v_staff, atribuido_em = now(),
         situacao = case when situacao = 'ENCAMINHADO' then 'EM_TRIAGEM' else situacao end,
         area_codigo = coalesce(nullif(p ->> 'area', ''), area_codigo), updated_at = now()
  where id = (p ->> 'id')::uuid and situacao in ('ENCAMINHADO', 'EM_TRIAGEM', 'EM_ATENDIMENTO', 'AGUARDANDO_REDE')
  returning * into c;
  if c.id is null then raise exception 'Caso não encontrado ou já encerrado.' using errcode = 'P0002'; end if;
  perform iara.audit_event('APOIO_ATRIBUICAO', 'apoio_caso', c.id::text, c.unit_id, format('Caso %s atribuído a %s.', c.numero, (select full_name from iara.staff where id = v_staff)));
  return iara.apoio_caso_json(c, true);
end $$;

-- o profissional registra (técnico sigiloso; orientações liberadas à escola e à família)
create or replace function api.apoio_registrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.apoio_casos;
  v_staff uuid := (select staff_id from iara.app_users where id = iara.current_user_id());
  v_tipo text := p ->> 'tipo';
  r iara.apoio_registros;
  v_nova text := nullif(p ->> 'situacao', '');
begin
  perform iara.require_perm('apoio.atender');
  select * into c from iara.apoio_casos where id = (p ->> 'caso_id')::uuid for update;
  if c.id is null or not (c.profissional_staff = v_staff or iara.has_perm('apoio.chefia')) then raise exception 'Caso não atribuído a você.' using errcode = '42501'; end if;
  if c.situacao in ('CONCLUIDO', 'NAO_ACEITO', 'ARQUIVADO') then raise exception 'Caso encerrado.' using errcode = '22023'; end if;
  if v_tipo not in ('TRIAGEM', 'AVALIACAO', 'ATENDIMENTO', 'ORIENTACAO_FAMILIA', 'ORIENTACAO_ESCOLA', 'REUNIAO', 'ENCAMINHAMENTO_EXTERNO', 'DEVOLUTIVA') then
    raise exception 'Tipo de registro inválido.' using errcode = '22023'; end if;
  if coalesce(btrim(p ->> 'registro_tecnico'), '') = '' and coalesce(btrim(p ->> 'orientacao_escola'), '') = '' and coalesce(btrim(p ->> 'orientacao_familia'), '') = '' then
    raise exception 'Escreva o registro técnico ou uma orientação.' using errcode = '22023'; end if;
  if v_nova is not null and v_nova not in ('EM_TRIAGEM', 'EM_ATENDIMENTO', 'AGUARDANDO_REDE') then raise exception 'Situação inválida.' using errcode = '22023'; end if;
  insert into iara.apoio_registros (caso_id, staff_id, autor_label, data, tipo, presenca, registro_tecnico, orientacao_escola, orientacao_familia)
  values (c.id, v_staff, coalesce((select full_name || ' · ' || coalesce((select a.profissional from iara.apoio_profissionais ap join iara.apoio_areas a on a.codigo = ap.area_codigo where ap.staff_id = v_staff), 'Apoio')
                                    from iara.staff where id = v_staff), iara.my_label()),
          coalesce(nullif(p ->> 'data', '')::date, iara.hoje_local()), v_tipo, nullif(p ->> 'presenca', ''),
          nullif(btrim(coalesce(p ->> 'registro_tecnico', '')), ''), nullif(btrim(coalesce(p ->> 'orientacao_escola', '')), ''), nullif(btrim(coalesce(p ->> 'orientacao_familia', '')), ''))
  returning * into r;
  update iara.apoio_casos set situacao = coalesce(v_nova, case when situacao = 'EM_TRIAGEM' and v_tipo in ('ATENDIMENTO', 'AVALIACAO') then 'EM_ATENDIMENTO'
                                                                when v_tipo = 'ENCAMINHAMENTO_EXTERNO' then 'AGUARDANDO_REDE' else situacao end),
         primeiro_atendimento_em = coalesce(primeiro_atendimento_em, case when coalesce(r.presenca, 'PRESENTE') = 'PRESENTE' then now() end), updated_at = now()
  where id = c.id returning * into c;
  if r.orientacao_familia is not null then
    insert into iara.notifications (tenant_id, guardian_id, student_id, channel, event_type, title, body, status)
    select 1, iara.uk_responsavel(c.student_id), c.student_id, 'WHATSAPP', 'APOIO_ORIENTACAO', 'Apoio interdisciplinar: nova orientação',
           format('Há uma orientação nova do(a) %s para %s. Veja e dê ciência em Vida escolar → Apoio, ou pergunte aqui “orientação do apoio”.',
                  lower((select profissional from iara.apoio_areas where codigo = c.area_codigo)), (select split_part(full_name, ' ', 1) from iara.students where id = c.student_id)),
           case when iara.demo_mode() then 'SIMULADA' else 'ENVIADA' end
    where iara.uk_responsavel(c.student_id) is not null;
  end if;
  -- trilha sem o conteúdo técnico
  perform iara.audit_event('APOIO_REGISTRO', 'apoio_caso', c.id::text, c.unit_id, format('Registro (%s) no caso %s.', lower(replace(v_tipo, '_', ' ')), c.numero));
  return iara.apoio_caso_json(c, true);
end $$;

create or replace function api.apoio_concluir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.apoio_casos;
  v_staff uuid := (select staff_id from iara.app_users where id = iara.current_user_id());
begin
  perform iara.require_perm('apoio.atender');
  if length(btrim(coalesce(p ->> 'conclusao', ''))) < 15 then raise exception 'Escreva a conclusão para a escola e a família (pelo menos 15 letras).' using errcode = '22023'; end if;
  update iara.apoio_casos set situacao = 'CONCLUIDO', concluido_em = now(), conclusao = btrim(p ->> 'conclusao'), updated_at = now()
  where id = (p ->> 'id')::uuid and (profissional_staff = v_staff or iara.has_perm('apoio.chefia')) and situacao in ('EM_TRIAGEM', 'EM_ATENDIMENTO', 'AGUARDANDO_REDE')
  returning * into c;
  if c.id is null then raise exception 'Caso não encontrado ou já encerrado.' using errcode = 'P0002'; end if;
  perform iara.audit_event('APOIO_CONCLUSAO', 'apoio_caso', c.id::text, c.unit_id, format('Caso %s concluído.', c.numero));
  return iara.apoio_caso_json(c, true);
end $$;

-- ficha do aluno (aba AEE/Inclusão): os casos, sem o registro técnico de outros profissionais
create or replace function api.apoio_aluno(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
begin
  perform iara.require_perm('apoio.read');
  return jsonb_build_object(
    'casos', (select coalesce(jsonb_agg(iara.apoio_caso_json(c, true) order by c.created_at desc), '[]') from iara.apoio_casos c where c.student_id = v_student and iara.apoio_pode_ver(c)),
    'pode_encaminhar', iara.has_perm('apoio.encaminhar') and iara.my_scope() = 'UNIT' and iara.can_access_student(v_student),
    'areas', (select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'nome', nome) order by ordem), '[]') from iara.apoio_areas where codigo <> 'FORMACAO'));
end $$;

-- 7. Ficha do aluno também para a equipe de apoio (alunos com caso dela) --------------------------------------------------------------
-- o acesso de linha usa my_student_ids(); a equipe de apoio (escopo de rede) já passa por rls_network com students.read

-- 8. LGPD ------------------------------------------------------------------------------------------------------------------------------
insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('apoio_casos', 'motivo', 'SENSIVEL', 'saúde e desenvolvimento da criança', 'encaminhamento ao apoio interdisciplinar', 'unidade do aluno, gerência e profissional atribuído'),
  ('apoio_casos', 'analise_unidade', 'SENSIVEL', 'saúde e desenvolvimento da criança', 'análise do pedido da família', 'unidade, gerência e família'),
  ('apoio_casos', 'conclusao', 'SENSIVEL', 'saúde e desenvolvimento da criança', 'devolutiva à escola e à família', 'unidade, gerência e família'),
  ('apoio_casos', 'solicitado_por_label', 'PESSOAL', 'autoria', 'rastreabilidade', 'só servidores'),
  ('apoio_registros', 'registro_tecnico', 'SENSIVEL', 'registro técnico (sigilo profissional CFP/CFFa)', 'acompanhamento do caso', 'só o autor e a chefia; a trilha não guarda o conteúdo'),
  ('apoio_registros', 'orientacao_escola', 'SENSIVEL', 'orientação pedagógica', 'apoio à escola', 'unidade, gerência e profissional'),
  ('apoio_registros', 'orientacao_familia', 'SENSIVEL', 'orientação à família', 'apoio à família', 'família, unidade, gerência e profissional'),
  ('apoio_registros', 'autor_label', 'PESSOAL', 'autoria', 'rastreabilidade', 'só servidores'),
  ('apoio_profissionais', 'registro_conselho', 'PESSOAL', 'registro profissional', 'identificação do profissional', 'gerência'),
  ('apoio_areas', 'resumo', 'PUBLICO', 'texto oficial', 'informação à família', null)
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

-- tabelas novas também entram na cobrança da classificação (uniformes, kits e apoio)
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
                         'ocorrencias', 'ocorrencia_eventos', 'agenda_escolar', 'agenda_ciencia',
                         'notas', 'pareceres', 'alfabetizacao_sondagens', 'planos_intervencao', 'aee_planos', 'aee_atendimentos', 'declaracoes',
                         'transporte_motoristas', 'transporte_rotas', 'transporte_pontos', 'transporte_alunos', 'transporte_viagens', 'transporte_embarques',
                         'transporte_ocorrencias', 'transporte_avisos', 'transporte_abonos', 'pedidos', 'pedido_itens', 'fornecedores',
                         'uk_tamanhos', 'uk_necessidades', 'uk_avisos', 'uk_codigos', 'uk_disparos', 'apoio_casos', 'apoio_registros', 'apoio_profissionais')
    and (c.column_name ~ '(name|cpf|nis|rg|phone|email|street|number|complement|postal|location|income|birth|race|sus|notes|body|payload|summary|description|details|allerg|medical|legal|need|telefone|nome|jid|flags|breakdown|relationship|marital|occupation|benefit|consent|context|label)'
         or c.column_name ~ '(^|_)(motivo|justificativa|atestado|detalhe|observacao|acao|descricao|formacao|escolaridade|matricula_funcional|data_admissao|opcao|restricao_codigo|providencias|providencia|texto|conteudo|objetivo|objetivos|resultado|atividade|avaliacao_inicial|orientacoes_sala|divergencia|lat|lng|tecnico|orientacao_escola|orientacao_familia|analise_unidade|conclusao|documento)$')
    and c.column_name not in ('contact_label', 'assigned_label', 'sender_label', 'subject', 'file_name_ext', 'registrado_label', 'produto_codigo', 'area_codigo')
    and not exists (select 1 from iara.classificacao_dados d where d.tabela = c.table_name and d.coluna = c.column_name)
$$;

-- 9. Oráculo --------------------------------------------------------------------------------------------------------------------------
insert into iara.oraculo_temas (tema, rotulo, palavras, ordem) values
  ('apoio', 'Apoio interdisciplinar (psicologia, fono, psicopedagogia)', '\mpsicolog|\mfonoaud|\mpsicopedag|\mapoio interdisciplinar|\morientac(ao|oes) educacional|\maltas habilidades|\msuperdot', 9)
on conflict (tema) do update set rotulo = excluded.rotulo, palavras = excluded.palavras;
insert into iara.oraculo_indicadores (chave, tema, rotulo, consulta, pessoas, sufixo, casas, palavras, palavras_ranking, pior, ordem) values
('api.abertos', 'apoio', 'Casos em aberto no apoio interdisciplinar',
 $q$select count(*) from iara.apoio_casos where situacao in ('ENCAMINHADO', 'EM_TRIAGEM', 'EM_ATENDIMENTO', 'AGUARDANDO_REDE') and unit_id = any ($1)$q$, true, null, 0, '\mabertos?\M|\mem atendimento', '\mcasos', 'maior', 1),
('api.espera', 'apoio', 'Encaminhados esperando profissional há mais de 30 dias',
 $q$select count(*) from iara.apoio_casos where situacao = 'ENCAMINHADO' and coalesce(encaminhado_em, created_at) < now() - interval '30 days' and unit_id = any ($1)$q$, true, null, 0, '\mespera|\mfila|\mesperando', '\mespera', 'maior', 2),
('api.pedidos', 'apoio', 'Pedidos das famílias aguardando a escola',
 $q$select count(*) from iara.apoio_casos where situacao = 'PEDIDO_FAMILIA' and unit_id = any ($1)$q$, true, null, 0, '\mpedidos? da familia|\mfamilias? pediram', null, 'maior', 3),
('api.concluidos', 'apoio', 'Casos concluídos nos últimos 90 dias',
 $q$select count(*) from iara.apoio_casos where situacao = 'CONCLUIDO' and concluido_em > now() - interval '90 days' and unit_id = any ($1)$q$, true, null, 0, '\mconcluid', null, 'menor', 4)
on conflict (chave) do update set tema = excluded.tema, rotulo = excluded.rotulo, consulta = excluded.consulta, pessoas = excluded.pessoas, sufixo = excluded.sufixo,
  casas = excluded.casas, palavras = excluded.palavras, palavras_ranking = excluded.palavras_ranking, pior = excluded.pior, ordem = excluded.ordem;

revoke all on function iara.apoio_pode_ver(iara.apoio_casos), iara.apoio_ve_tecnico(iara.apoio_registros), iara.apoio_caso_json(iara.apoio_casos, boolean) from public;

commit;
