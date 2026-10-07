-- IARA Educa — 047 · Mural de avisos, confirmação de leitura e enquetes (Sprint 1, módulo 5; item 47 da seção 12)
-- A SEDUC publica para a rede; a unidade publica para as suas famílias. A família lê no portal ou pela IARA, confirma a ciência
-- quando o aviso pede e responde às enquetes. O calendário (044) recebe o evento quando a publicação tem data.
-- Leituras de demonstração ficam em contadores (leituras_demo), para não criar milhares de linhas fictícias por família.
begin;

create table if not exists iara.mural_publicacoes (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('AVISO', 'COMUNICADO', 'EVENTO', 'ENQUETE', 'CAMPANHA')),
  titulo text not null,
  texto text not null,
  unit_id integer references iara.education_units(id) on delete cascade,
  publico text not null default 'FAMILIAS' check (publico in ('FAMILIAS', 'PROFISSIONAIS', 'TODOS')),
  faixas text[],
  exige_confirmacao boolean not null default false,
  enquete_opcoes text[],
  data_evento date,
  publicado_em timestamptz not null default now(),
  expira_em date,
  fixado boolean not null default false,
  autor_label text,
  situacao text not null default 'PUBLICADO' check (situacao in ('PUBLICADO', 'ARQUIVADO')),
  destinatarios integer not null default 0,
  leituras_demo integer not null default 0,
  confirmacoes_demo integer not null default 0,
  votos_demo integer[],
  calendario_evento_id uuid references iara.calendario_eventos(id) on delete set null,
  is_demo boolean not null default true
);
create index if not exists mural_publicacoes_unit_idx on iara.mural_publicacoes (unit_id, publicado_em desc);

create table if not exists iara.mural_leituras (
  publicacao_id uuid not null references iara.mural_publicacoes(id) on delete cascade,
  guardian_id uuid not null references iara.guardians(id) on delete cascade,
  lido_em timestamptz not null default now(),
  confirmado_em timestamptz,
  is_demo boolean not null default false,
  primary key (publicacao_id, guardian_id)
);
create table if not exists iara.mural_enquete_respostas (
  publicacao_id uuid not null references iara.mural_publicacoes(id) on delete cascade,
  guardian_id uuid not null references iara.guardians(id) on delete cascade,
  opcao smallint not null,
  respondido_em timestamptz not null default now(),
  is_demo boolean not null default false,
  primary key (publicacao_id, guardian_id)
);
alter table iara.mural_publicacoes enable row level security;
alter table iara.mural_leituras enable row level security;
alter table iara.mural_enquete_respostas enable row level security;

-- famílias alcançadas por uma publicação (responsáveis de alunos ativos da unidade ou da rede, na faixa)
create or replace function iara.mural_contar_destinatarios(p_unit integer, p_faixas text[]) returns integer
language sql stable security definer set search_path = iara, public
as $$
  select count(distinct sg.guardian_id)::int
  from iara.enrollments e join iara.student_guardians sg on sg.student_id = e.student_id and sg.end_date is null
  join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
  where e.status = 'ACTIVE' and (p_unit is null or e.unit_id = p_unit)
    and (p_faixas is null or iara.faixa_cardapio(gl.code) = any (p_faixas))
$$;

-- publicações que a família logada enxerga, com os filhos a que se referem
create or replace function iara.mural_da_familia() returns table (publicacao_id uuid, filhos text)
language sql stable security definer set search_path = iara, public
as $$
  with f as (select e.unit_id, iara.faixa_cardapio(gl.code) faixa, split_part(s.full_name, ' ', 1) nome
             from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
             join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
             where s.id in (select iara.my_student_ids()))
  select m.id, string_agg(distinct f.nome, ', ')
  from iara.mural_publicacoes m join f on (m.unit_id is null or m.unit_id = f.unit_id) and (m.faixas is null or f.faixa = any (m.faixas))
  where m.situacao = 'PUBLICADO' and m.publico in ('FAMILIAS', 'TODOS') and m.publicado_em <= now()
    and (m.expira_em is null or m.expira_em >= current_date)
  group by m.id
$$;

create or replace function iara.mural_json(m iara.mural_publicacoes) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', m.id, 'tipo', m.tipo, 'titulo', m.titulo, 'texto', m.texto, 'unit_id', m.unit_id,
    'unidade', (select short_name from iara.education_units where id = m.unit_id), 'publico', m.publico, 'faixas', m.faixas,
    'exige_confirmacao', m.exige_confirmacao, 'opcoes', m.enquete_opcoes, 'data_evento', m.data_evento,
    'publicado_em', m.publicado_em, 'expira_em', m.expira_em, 'fixado', m.fixado, 'autor', m.autor_label, 'situacao', m.situacao)
$$;

create or replace function iara.mural_votos(m iara.mural_publicacoes) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select case when m.enquete_opcoes is null then null else
    (select jsonb_agg(jsonb_build_object('opcao', o.txt, 'votos', coalesce(m.votos_demo[o.i], 0)
             + (select count(*) from iara.mural_enquete_respostas r where r.publicacao_id = m.id and r.opcao = o.i)) order by o.i)
     from unnest(m.enquete_opcoes) with ordinality o(txt, i)) end
$$;

-- 1. Servidores: feed, publicar, arquivar --------------------------------------------------------------------------------------------
create or replace function api.mural_feed(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_arq boolean := coalesce((p ->> 'arquivados')::boolean, false);
  v_pode boolean := iara.has_perm('mural.publish');
begin
  if iara.current_user_id() is null or iara.my_guardian() is not null then
    raise exception 'Mural dos servidores.' using errcode = '42501';
  end if;
  return jsonb_build_object('pode_publicar', v_pode, 'escopo', case when iara.my_scope() = 'UNIT' then 'UNIDADE' else 'REDE' end,
    'publicacoes', (select coalesce(jsonb_agg(iara.mural_json(m) || jsonb_build_object(
        'destinatarios', m.destinatarios,
        'leituras', m.leituras_demo + (select count(*) from iara.mural_leituras l where l.publicacao_id = m.id),
        'confirmacoes', m.confirmacoes_demo + (select count(*) from iara.mural_leituras l where l.publicacao_id = m.id and l.confirmado_em is not null),
        'votos', iara.mural_votos(m),
        'pode_editar', v_pode and (iara.my_scope() <> 'UNIT' or m.unit_id = iara.my_unit()))
      order by m.fixado desc, m.publicado_em desc), '[]')
      from (select * from iara.mural_publicacoes m
            where (m.situacao = 'PUBLICADO' or v_arq) and m.publicado_em <= now()
              and (m.unit_id is null or v_unit is null or m.unit_id = v_unit)
              and (iara.my_scope() <> 'UNIT' or m.unit_id is null or m.unit_id = iara.my_unit())
            order by m.fixado desc, m.publicado_em desc limit 120) m));
end $$;

create or replace function api.mural_publicar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_unit integer;
  v_tipo text := coalesce(nullif(p ->> 'tipo', ''), 'AVISO');
  v_publico text := coalesce(nullif(p ->> 'publico', ''), 'FAMILIAS');
  v_titulo text := btrim(coalesce(p ->> 'titulo', ''));
  v_texto text := btrim(coalesce(p ->> 'texto', ''));
  v_opcoes text[];
  v_faixas text[];
  v_data date := nullif(p ->> 'data_evento', '')::date;
  m iara.mural_publicacoes;
  v_cal uuid;
begin
  perform iara.require_perm('mural.publish');
  if iara.my_scope() = 'UNIT' then
    v_unit := iara.my_unit();
  elsif iara.my_scope() = 'NETWORK' then
    v_unit := nullif(p ->> 'unit_id', '')::int;
  else
    raise exception 'Perfil sem escopo para publicar.' using errcode = '42501';
  end if;
  if v_tipo not in ('AVISO', 'COMUNICADO', 'EVENTO', 'ENQUETE', 'CAMPANHA') or v_publico not in ('FAMILIAS', 'PROFISSIONAIS', 'TODOS') then
    raise exception 'Tipo ou público inválido.' using errcode = '22023';
  end if;
  if length(v_titulo) not between 5 and 120 or length(v_texto) not between 10 and 4000 then
    raise exception 'Título (5 a 120 caracteres) e texto (10 a 4.000) obrigatórios.' using errcode = '22023';
  end if;
  select array_agg(btrim(x)) filter (where btrim(x) <> '') into v_opcoes from jsonb_array_elements_text(coalesce(p -> 'opcoes', '[]')) x;
  if v_tipo = 'ENQUETE' and coalesce(array_length(v_opcoes, 1), 0) not between 2 and 6 then
    raise exception 'A enquete precisa de 2 a 6 opções.' using errcode = '22023';
  end if;
  if v_tipo = 'ENQUETE' and v_publico = 'PROFISSIONAIS' then raise exception 'Enquete é para as famílias.' using errcode = '22023'; end if;
  select array_agg(x) filter (where x in ('CRECHE', 'PRE', 'EF')) into v_faixas from jsonb_array_elements_text(coalesce(p -> 'faixas', '[]')) x;
  if v_data is not null and v_data < current_date then raise exception 'A data do evento já passou.' using errcode = '22023'; end if;
  if v_data is not null then
    insert into iara.calendario_eventos (titulo, tipo, inicio, fim, abrangencia, unit_id, publico, descricao, fonte, criado_por_label, is_demo)
    values (v_titulo, case when coalesce((p ->> 'reuniao_pais')::boolean, false) then 'REUNIAO_PAIS' else 'EVENTO' end, v_data, v_data,
            case when v_unit is null then 'REDE' else 'UNIDADE' end, v_unit, v_publico, left(v_texto, 300), 'MURAL', iara.my_label(), false)
    returning id into v_cal;
  end if;
  insert into iara.mural_publicacoes (tipo, titulo, texto, unit_id, publico, faixas, exige_confirmacao, enquete_opcoes, data_evento,
                                      expira_em, fixado, autor_label, destinatarios, calendario_evento_id, is_demo)
  values (v_tipo, v_titulo, v_texto, v_unit, v_publico, v_faixas, coalesce((p ->> 'exige_confirmacao')::boolean, false),
          case when v_tipo = 'ENQUETE' then v_opcoes end, v_data, nullif(p ->> 'expira_em', '')::date,
          coalesce((p ->> 'fixado')::boolean, false), iara.my_label(),
          case when v_publico = 'PROFISSIONAIS' then 0 else iara.mural_contar_destinatarios(v_unit, v_faixas) end, v_cal, false)
  returning * into m;
  perform iara.audit_event('MURAL_PUBLICADO', 'mural', m.id::text, v_unit, 'Publicação no mural: ' || left(v_titulo, 80) || '.');
  return iara.mural_json(m) || jsonb_build_object('destinatarios', m.destinatarios);
end $$;

create or replace function api.mural_arquivar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  m iara.mural_publicacoes;
begin
  perform iara.require_perm('mural.publish');
  select * into m from iara.mural_publicacoes where id = (p ->> 'id')::uuid;
  if m.id is null or (iara.my_scope() = 'UNIT' and m.unit_id is distinct from iara.my_unit()) or iara.my_scope() not in ('UNIT', 'NETWORK') then
    raise exception 'Publicação fora do seu escopo.' using errcode = '42501';
  end if;
  update iara.mural_publicacoes set situacao = case when situacao = 'ARQUIVADO' then 'PUBLICADO' else 'ARQUIVADO' end where id = m.id returning * into m;
  perform iara.audit_event('MURAL_SITUACAO', 'mural', m.id::text, m.unit_id, 'Publicação ' || lower(m.situacao) || ': ' || left(m.titulo, 80) || '.');
  return jsonb_build_object('ok', true, 'situacao', m.situacao);
end $$;

-- 2. Família: avisos, ciência e enquete (portal e IARA) ------------------------------------------------------------------------------
create or replace function api.familia_avisos(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_g uuid := iara.my_guardian();
  v_lista jsonb;
begin
  if v_g is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(iara.mural_json(m) || jsonb_build_object('filhos', f.filhos,
           'lido', l.lido_em is not null, 'confirmado', l.confirmado_em is not null, 'minha_resposta', r.opcao,
           'votos', case when r.opcao is not null then iara.mural_votos(m) end)
         order by (l.lido_em is null) desc, m.fixado desc, m.publicado_em desc), '[]')
  into v_lista
  from iara.mural_da_familia() f join iara.mural_publicacoes m on m.id = f.publicacao_id
  left join iara.mural_leituras l on l.publicacao_id = m.id and l.guardian_id = v_g
  left join iara.mural_enquete_respostas r on r.publicacao_id = m.id and r.guardian_id = v_g
  where coalesce((p ->> 'nao_lidos')::boolean, false) is false or l.lido_em is null
     or (m.exige_confirmacao and l.confirmado_em is null) or (m.tipo = 'ENQUETE' and r.opcao is null);
  return jsonb_build_object('avisos', v_lista,
    'nao_lidos', (select count(*) from jsonb_array_elements(v_lista) a where not (a ->> 'lido')::boolean),
    'pendentes_confirmacao', (select count(*) from jsonb_array_elements(v_lista) a where (a ->> 'exige_confirmacao')::boolean and not (a ->> 'confirmado')::boolean),
    'enquetes_abertas', (select count(*) from jsonb_array_elements(v_lista) a where a ->> 'tipo' = 'ENQUETE' and a ->> 'minha_resposta' is null));
end $$;

create or replace function api.familia_aviso_ler(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_g uuid := iara.my_guardian();
  v_id uuid := (p ->> 'id')::uuid;
  v_conf boolean := coalesce((p ->> 'confirmar')::boolean, false);
begin
  if v_g is null or not exists (select 1 from iara.mural_da_familia() f where f.publicacao_id = v_id) then
    raise exception 'Aviso não encontrado.' using errcode = 'P0002';
  end if;
  insert into iara.mural_leituras (publicacao_id, guardian_id, lido_em, confirmado_em)
  values (v_id, v_g, now(), case when v_conf then now() end)
  on conflict (publicacao_id, guardian_id) do update set confirmado_em = coalesce(iara.mural_leituras.confirmado_em, excluded.confirmado_em);
  if v_conf then
    perform iara.audit_event('MURAL_CIENCIA', 'mural', v_id::text, null, 'Ciência de aviso confirmada pela família.');
  end if;
  return jsonb_build_object('ok', true, 'confirmado', v_conf);
end $$;

create or replace function api.familia_enquete_responder(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_g uuid := iara.my_guardian();
  m iara.mural_publicacoes;
  v_op smallint := (p ->> 'opcao')::smallint;
begin
  select * into m from iara.mural_publicacoes where id = (p ->> 'id')::uuid;
  if v_g is null or m.id is null or not exists (select 1 from iara.mural_da_familia() f where f.publicacao_id = m.id) then
    raise exception 'Enquete não encontrada.' using errcode = 'P0002';
  end if;
  if m.tipo <> 'ENQUETE' or v_op is null or v_op not between 1 and coalesce(array_length(m.enquete_opcoes, 1), 0) then
    raise exception 'Opção inválida.' using errcode = '22023';
  end if;
  insert into iara.mural_enquete_respostas (publicacao_id, guardian_id, opcao) values (m.id, v_g, v_op)
  on conflict (publicacao_id, guardian_id) do update set opcao = excluded.opcao, respondido_em = now();
  insert into iara.mural_leituras (publicacao_id, guardian_id) values (m.id, v_g) on conflict do nothing;
  return jsonb_build_object('ok', true, 'opcao', m.enquete_opcoes[v_op], 'votos', iara.mural_votos(m));
end $$;

-- 3. Gerador da demonstração -------------------------------------------------------------------------------------------------------
create or replace function iara.demo_gerar_mural() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_rede integer;
  v_ana_g uuid;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.mural_publicacoes where is_demo;
  v_rede := iara.mural_contar_destinatarios(null, null);

  insert into iara.mural_publicacoes (tipo, titulo, texto, publico, faixas, exige_confirmacao, enquete_opcoes, data_evento, publicado_em,
                                      expira_em, fixado, autor_label, destinatarios, is_demo)
  select v.tipo, v.titulo, v.texto, v.publico, v.faixas, v.conf, v.opcoes, v.data_ev, v.pub::timestamptz + interval '10 hours', v.expira, v.fixado,
         'SEDUC Maringá · Comunicação (demonstração)',
         case when v.publico = 'PROFISSIONAIS' then 0 else iara.mural_contar_destinatarios(null, v.faixas) end, true
  from (values
    ('COMUNICADO', 'Rematrícula 2027: confirme a vaga do seu filho',
     'De 3 a 20 de novembro, confirme pelo portal ou pela IARA no WhatsApp se a criança continua na rede em 2027. Quem não confirmar no prazo é procurado pela unidade.',
     'FAMILIAS', null::text[], true, null::text[], null::date, date '2026-10-05', date '2026-11-20', true),
    ('ENQUETE', 'Qual o melhor horário para a reunião de pais?',
     'Queremos que mais famílias participem das reuniões do próximo ano. Escolha o horário que funciona melhor para você.',
     'FAMILIAS', null, false, array['Manhã (8h)', 'Fim da tarde (17h30)', 'Noite (19h)', 'Sábado de manhã'], null, date '2026-09-28', date '2026-10-31', false),
    ('EVENTO', 'Semana da Criança: programação nas unidades',
     'De 13 a 16 de outubro, brincadeiras, contação de histórias e lanche especial em todas as escolas e CMEIs. Segunda-feira (12) é feriado.',
     'TODOS', null, false, null, date '2026-10-13', date '2026-10-02', date '2026-10-16', false),
    ('CAMPANHA', 'Caderneta de vacinação em dia',
     'A Secretaria de Saúde vai às unidades conferir a caderneta. Mande a caderneta (ou foto dela) na mochila na semana indicada pela escola.',
     'FAMILIAS', null, false, null, null, date '2026-09-15', null, false),
    ('CAMPANHA', 'Outubro Rosa: cuidado com quem cuida',
     'Mães, avós e profissionais da rede: as unidades básicas de saúde ampliaram o horário para exames preventivos em outubro.',
     'TODOS', null, false, null, null, date '2026-10-01', date '2026-10-31', false),
    ('COMUNICADO', 'Calendário do 4º bimestre',
     'O 4º bimestre vai de 13 de outubro a 17 de dezembro. Feriados: 2/11 (Finados), 20/11 (Consciência Negra). As reuniões de pais acontecem em dezembro.',
     'TODOS', null, false, null, null, date '2026-10-06', null, false),
    ('AVISO', 'Formação continuada: inscrições abertas',
     'Inscrições para as turmas de novembro (alfabetização, educação inclusiva e mediação de conflitos) até 23/10 pela chefia imediata.',
     'PROFISSIONAIS', null, false, null, null, date '2026-09-21', date '2026-10-23', false),
    ('AVISO', 'Cardápio de outubro: frutas da estação',
     'O cardápio de outubro traz mais frutas da época e o lanche sem açúcar adicionado. Restrição alimentar? Informe no portal ou pela IARA e leve o laudo à secretaria.',
     'FAMILIAS', array['CRECHE', 'PRE'], false, null, null, date '2026-09-30', null, false),
    ('CAMPANHA', 'Setembro Amarelo: falar é a melhor solução',
     'Rodas de conversa com as turmas do 4º e 5º ano e material de apoio para as famílias. Procure a equipe pedagógica se precisar.',
     'TODOS', array['EF'], false, null, null, date '2026-09-01', date '2026-09-30', false),
    ('EVENTO', 'Jogos Escolares de Maringá 2026',
     'As escolas inscritas recebem a tabela dos jogos. Autorização de saída das crianças enviada pela unidade.',
     'TODOS', array['EF'], false, null, date '2026-10-26', date '2026-09-18', date '2026-10-30', false),
    ('AVISO', 'Calor: garrafinha de água todos os dias',
     'Com as temperaturas altas, mande a garrafinha identificada com o nome da criança. Os bebedouros foram revisados.',
     'FAMILIAS', null, false, null, null, date '2026-10-06', date '2026-12-17', false)
  ) v(tipo, titulo, texto, publico, faixas, conf, opcoes, data_ev, pub, expira, fixado);

  -- por unidade: reunião de pais do 3º bimestre (com ciência) e um aviso da própria escola
  insert into iara.mural_publicacoes (tipo, titulo, texto, unit_id, publico, exige_confirmacao, data_evento, publicado_em, expira_em,
                                      autor_label, destinatarios, is_demo)
  select 'EVENTO', 'Reunião de pais e responsáveis — 3º bimestre',
         'Dia ' || to_char(date '2026-10-19' + (u.id % 4), 'DD/MM') || ', às 18h30, na unidade. Entrega dos pareceres e conversa com os professores. Confirme a ciência.',
         u.id, 'FAMILIAS', true, date '2026-10-19' + (u.id % 4), date '2026-10-05' + (u.id % 3) + interval '9 hours', date '2026-10-19' + (u.id % 4),
         'Direção da unidade (demonstração)', iara.mural_contar_destinatarios(u.id, null), true
  from iara.education_units u where u.status = 'ATIVA' and exists (select 1 from iara.classes c where c.unit_id = u.id and c.status = 'ATIVA');
  insert into iara.mural_publicacoes (tipo, titulo, texto, unit_id, publico, exige_confirmacao, publicado_em, autor_label, destinatarios, is_demo)
  select 'AVISO', a.titulo, a.texto, u.id, 'FAMILIAS', false, date '2026-09-10' + (u.id % 25) + interval '8 hours',
         'Direção da unidade (demonstração)', iara.mural_contar_destinatarios(u.id, null), true
  from iara.education_units u
  cross join lateral (select * from (values
    ('Horário de entrada e saída', 'Lembrete: o portão abre 15 minutos antes do início das aulas e fecha 10 minutos depois. Atrasos frequentes são comunicados à família.'),
    ('Achados e perdidos', 'Casacos e garrafinhas esquecidos estão na secretaria. Marque o nome da criança nos objetos.'),
    ('Mostra cultural da unidade', 'As turmas vão apresentar os trabalhos do semestre. Data e horário serão confirmados pela professora.'),
    ('Atualize o telefone de contato', 'Mudou de número? Atualize pelo portal ou pela IARA para não perder os avisos da escola.')) v(titulo, texto)
    offset u.id % 4 limit 1) a
  where u.status = 'ATIVA' and exists (select 1 from iara.classes c where c.unit_id = u.id and c.status = 'ATIVA');

  -- leituras e votos de demonstração (contadores): quanto mais antiga a publicação, mais famílias leram
  update iara.mural_publicacoes m set
    leituras_demo = round(m.destinatarios * least(0.92, 0.35 + 0.04 * greatest(0, current_date - m.publicado_em::date)
                    + (abs(hashtext(m.id::text)) % 15) / 100.0))::int,
    confirmacoes_demo = case when m.exige_confirmacao then round(m.destinatarios * least(0.85, 0.25 + 0.035 * greatest(0, current_date - m.publicado_em::date)
                    + (abs(hashtext(m.id::text)) % 12) / 100.0))::int else 0 end,
    votos_demo = case when m.enquete_opcoes is not null then array[round(m.destinatarios * 0.06)::int, round(m.destinatarios * 0.19)::int,
                                                                   round(m.destinatarios * 0.13)::int, round(m.destinatarios * 0.05)::int] end
  where m.is_demo and m.publico <> 'PROFISSIONAIS';

  -- a família da Ana já leu parte dos avisos (os mais novos aparecem como não lidos na apresentação)
  v_ana_g := (select sg.guardian_id from iara.student_guardians sg where sg.student_id = (iara.setting('demo_student_ana'))::uuid
              order by sg.is_primary desc limit 1);
  delete from iara.mural_leituras where is_demo;
  delete from iara.mural_enquete_respostas where is_demo;
  if v_ana_g is not null then
    insert into iara.mural_leituras (publicacao_id, guardian_id, lido_em, confirmado_em, is_demo)
    select m.id, v_ana_g, m.publicado_em + interval '5 hours', case when m.exige_confirmacao then m.publicado_em + interval '5 hours' end, true
    from iara.mural_publicacoes m
    where m.is_demo and m.publicado_em < now() - interval '6 days' and m.publico <> 'PROFISSIONAIS' and m.tipo <> 'ENQUETE'
      and (m.unit_id is null or m.unit_id in (select e.unit_id from iara.enrollments e join iara.student_guardians sg on sg.student_id = e.student_id
                                              where sg.guardian_id = v_ana_g and e.status = 'ACTIVE'));
  end if;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('publicacoes', (select count(*) from iara.mural_publicacoes where is_demo), 'familias_rede', v_rede,
    'leituras_ana', (select count(*) from iara.mural_leituras where is_demo));
end $$;

revoke all on function iara.demo_gerar_mural(), iara.mural_contar_destinatarios(integer, text[]), iara.mural_da_familia() from public;

commit;
