-- IARA Educa — 045 · Cardápio e nutrição (Sprint 1, módulo 3; item 45 da seção 12 do documento de estrutura)
-- As 17 categorias de restrição alimentar dos prints (descrição original preservada) com o motivo separado — os rótulos
-- misturavam motivos (seção 12.2 do documento do portal). Cardápio semanal por faixa, substituição automática pelo que a
-- restrição exclui, lista da cozinha só com a instrução de preparo (nunca o laudo) e refeições servidas pela presença do dia.
-- Não é recomendação clínica: a validação de cada restrição é da nutrição.
begin;

create table if not exists iara.restricoes_alimentares (
  codigo text primary key,
  descricao text not null,
  motivo text not null check (motivo in ('ALERGIA', 'INTOLERANCIA', 'DOENCA', 'RELIGIOSO', 'OPCAO')),
  exige_laudo boolean not null,
  exclui text[] not null,
  orientacao_cozinha text not null,
  ordem smallint not null
);
insert into iara.restricoes_alimentares (codigo, descricao, motivo, exige_laudo, exclui, orientacao_cozinha, ordem) values
  ('COLORAU', 'Alergia a colorau', 'ALERGIA', true, '{colorau}', 'Preparar sem colorau (urucum); temperar à parte.', 1),
  ('CORANTES', 'Alergia a corantes', 'ALERGIA', true, '{corante,colorau}', 'Sem corantes artificiais nem colorau; conferir rótulos.', 2),
  ('FRUTA_LAUDO', 'Alergia a fruta (especificada no laudo)', 'ALERGIA', true, '{}', 'Não servir a fruta indicada; oferecer outra fruta da época.', 3),
  ('OLEO_SOJA', 'Alergia a óleo de soja', 'ALERGIA', true, '{oleo_soja}', 'Preparar com outro óleo (girassol/milho) em panela separada.', 4),
  ('OVO_TOTAL', 'Alergia a ovo (não pode consumir de nenhuma forma)', 'ALERGIA', true, '{ovo,ovo_processado}', 'Nenhum preparo com ovo, nem assados e massas com ovo.', 5),
  ('OVO_IN_NATURA', 'Alergia a ovo in natura (pode consumir em alimentos assados e processados)', 'ALERGIA', true, '{ovo}', 'Sem ovo cozido, mexido ou frito; bolos e pães assados liberados.', 6),
  ('APLV', 'Alergia à proteína do leite de vaca (APLV)', 'ALERGIA', true, '{leite,lactose,derivado_leite}', 'Nenhum leite ou derivado (inclusive manteiga e queijo); utensílios separados.', 7),
  ('SOJA', 'Alergia à soja', 'ALERGIA', true, '{soja}', 'Sem soja e derivados (proteína texturizada, molho shoyu).', 8),
  ('DIABETES', 'Diabetes', 'DOENCA', true, '{acucar}', 'Sem açúcar adicionado; frutas em porção orientada; nada de bolo doce.', 9),
  ('DISLIPIDEMIA', 'Dislipidemias (alterações no perfil lipídico, como colesterol alto)', 'DOENCA', true, '{fritura,embutido}', 'Sem frituras nem embutidos; carnes magras assadas ou cozidas.', 10),
  ('CELIACA', 'Doença celíaca / intolerância ao glúten (pão de trigo, massas, bolos, biscoitos)', 'DOENCA', true, '{gluten}', 'Sem trigo, aveia, cevada e centeio; evitar contaminação cruzada (utensílios separados).', 11),
  ('LACTOSE', 'Intolerância à lactose', 'INTOLERANCIA', true, '{lactose}', 'Leite e derivados sem lactose; manteiga em pequena quantidade conforme orientação.', 12),
  ('PORCO_ADVENTISTA', 'Restrição à carne de porco (adventista/alérgico)', 'RELIGIOSO', false, '{porco}', 'Sem carne de porco nem banha; servir outra proteína.', 13),
  ('PORCO_RELIGIAO', 'Restrição à carne de porco (crenças religiosas/alérgico)', 'RELIGIOSO', false, '{porco}', 'Sem carne de porco nem banha; servir outra proteína.', 14),
  ('PORCO_OPCAO', 'Restrição à carne de porco (opção pessoal/alérgico)', 'OPCAO', false, '{porco}', 'Sem carne de porco; servir outra proteína.', 15),
  ('VEGANO', 'Vegano (não come nenhum tipo de proteína animal — carne, ovo e leite)', 'OPCAO', false,
   '{carne,frango,peixe,porco,ovo,ovo_processado,leite,lactose,derivado_leite,mel}', 'Proteína vegetal (feijões, lentilha, grão-de-bico); sem leite, ovo e mel.', 16),
  ('VEGETARIANO', 'Vegetariano (não come carnes em geral, mas pode ovo e leite)', 'OPCAO', false, '{carne,frango,peixe,porco}', 'Sem carnes; ovo, leite e proteína vegetal liberados.', 17)
on conflict (codigo) do update set descricao = excluded.descricao, motivo = excluded.motivo, exige_laudo = excluded.exige_laudo,
  exclui = excluded.exclui, orientacao_cozinha = excluded.orientacao_cozinha, ordem = excluded.ordem;

create table if not exists iara.aluno_restricoes (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references iara.students(id) on delete cascade,
  restricao_codigo text not null references iara.restricoes_alimentares(codigo),
  detalhe text,
  inicio date not null default current_date,
  fim date,
  situacao text not null default 'INFORMADA' check (situacao in ('INFORMADA', 'VALIDADA', 'RECUSADA')),
  validada_por_label text,
  validada_em timestamptz,
  observacao text,
  origem text not null default 'FAMILIA' check (origem in ('FAMILIA', 'UNIDADE', 'CARGA', 'DEMO')),
  is_demo boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists aluno_restricoes_student_idx on iara.aluno_restricoes (student_id);

create table if not exists iara.preparacoes (
  codigo text primary key,
  nome text not null,
  grupo text not null check (grupo in ('BEBIDA', 'PANIFICADO', 'FRUTA', 'BASE', 'PRINCIPAL', 'ACOMPANHAMENTO')),
  tags text[] not null default '{}',
  substituta boolean not null default false
);
insert into iara.preparacoes (codigo, nome, grupo, tags, substituta) values
  ('LEITE_CACAU', 'Leite com cacau', 'BEBIDA', '{leite,lactose}', false),
  ('VITAMINA_BANANA', 'Vitamina de banana com leite', 'BEBIDA', '{leite,lactose,banana}', false),
  ('IOGURTE', 'Iogurte natural', 'BEBIDA', '{leite,lactose,derivado_leite}', false),
  ('SUCO_LARANJA', 'Suco natural de laranja', 'BEBIDA', '{laranja}', false),
  ('CHA_ERVA_DOCE', 'Chá de erva-doce', 'BEBIDA', '{}', true),
  ('BEBIDA_ARROZ', 'Bebida vegetal de arroz', 'BEBIDA', '{}', true),
  ('LEITE_SEM_LACTOSE', 'Leite sem lactose com cacau', 'BEBIDA', '{leite}', true),
  ('MINGAU_AVEIA', 'Mingau de aveia', 'PANIFICADO', '{leite,lactose,gluten,acucar}', false),
  ('PAO_MANTEIGA', 'Pão integral com manteiga', 'PANIFICADO', '{gluten,derivado_leite}', false),
  ('PAO_QUEIJO', 'Pão de queijo', 'PANIFICADO', '{ovo_processado,leite,lactose,derivado_leite}', false),
  ('BOLO_CENOURA', 'Bolo de cenoura', 'PANIFICADO', '{gluten,ovo_processado,leite,lactose,acucar,oleo_soja}', false),
  ('BISCOITO_POLVILHO', 'Biscoito de polvilho', 'PANIFICADO', '{ovo_processado,oleo_soja}', false),
  ('TAPIOCA_FRANGO', 'Tapioca com frango desfiado', 'PANIFICADO', '{frango}', false),
  ('PAO_SEM_GLUTEN', 'Pão sem glúten com azeite', 'PANIFICADO', '{}', true),
  ('TAPIOCA_BANANA', 'Tapioca com banana e canela', 'PANIFICADO', '{banana}', true),
  ('CUSCUZ_MILHO', 'Cuscuz de milho', 'PANIFICADO', '{}', true),
  ('FRUTA_BANANA', 'Banana', 'FRUTA', '{banana}', false),
  ('FRUTA_MACA', 'Maçã', 'FRUTA', '{maca}', false),
  ('FRUTA_MAMAO', 'Mamão', 'FRUTA', '{mamao}', false),
  ('FRUTA_MELANCIA', 'Melancia', 'FRUTA', '{melancia}', false),
  ('FRUTA_LARANJA', 'Laranja', 'FRUTA', '{laranja}', false),
  ('FRUTA_PERA', 'Pera', 'FRUTA', '{pera}', true),
  ('ARROZ_FEIJAO', 'Arroz e feijão', 'BASE', '{}', false),
  ('FRANGO_ENSOPADO', 'Frango ensopado com legumes', 'PRINCIPAL', '{frango,colorau}', false),
  ('CARNE_MOIDA', 'Carne moída com abóbora', 'PRINCIPAL', '{carne}', false),
  ('PEIXE_ASSADO', 'Peixe assado com batatas', 'PRINCIPAL', '{peixe}', false),
  ('OMELETE', 'Omelete de legumes', 'PRINCIPAL', '{ovo,leite,lactose}', false),
  ('MACARRAO_BOLONHESA', 'Macarrão à bolonhesa', 'PRINCIPAL', '{gluten,carne,colorau,ovo_processado}', false),
  ('POLENTA_MOLHO', 'Polenta com molho de carne', 'PRINCIPAL', '{carne,colorau}', false),
  ('RISOTO_FRANGO', 'Risoto de frango', 'PRINCIPAL', '{frango,derivado_leite,lactose}', false),
  ('LOMBO_SUINO', 'Lombo suíno assado', 'PRINCIPAL', '{porco}', false),
  ('ESTROGONOFE', 'Estrogonofe de frango', 'PRINCIPAL', '{frango,leite,lactose,derivado_leite}', false),
  ('FRANGO_GRELHADO', 'Frango grelhado com legumes', 'PRINCIPAL', '{frango}', true),
  ('LENTILHA', 'Lentilha com legumes', 'PRINCIPAL', '{}', true),
  ('GRAO_DE_BICO', 'Grão-de-bico ensopado', 'PRINCIPAL', '{}', true),
  ('SALADA_FOLHAS', 'Salada de folhas', 'ACOMPANHAMENTO', '{}', false),
  ('LEGUMES_REFOGADOS', 'Legumes refogados', 'ACOMPANHAMENTO', '{oleo_soja}', false),
  ('PURE_BATATA', 'Purê de batata', 'ACOMPANHAMENTO', '{leite,lactose,derivado_leite}', false),
  ('BETERRABA', 'Salada de beterraba ralada', 'ACOMPANHAMENTO', '{}', false),
  ('LEGUMES_COZIDOS', 'Legumes cozidos no vapor', 'ACOMPANHAMENTO', '{}', true)
on conflict (codigo) do update set nome = excluded.nome, grupo = excluded.grupo, tags = excluded.tags, substituta = excluded.substituta;

create table if not exists iara.cardapios (
  id uuid primary key default gen_random_uuid(),
  faixa text not null check (faixa in ('CRECHE', 'PRE', 'EF')),
  semana_inicio date not null,
  situacao text not null default 'PUBLICADO' check (situacao in ('RASCUNHO', 'PUBLICADO')),
  responsavel_label text,
  publicado_em timestamptz,
  is_demo boolean not null default true,
  unique (faixa, semana_inicio)
);
create table if not exists iara.cardapio_itens (
  cardapio_id uuid not null references iara.cardapios(id) on delete cascade,
  dia_semana smallint not null check (dia_semana between 1 and 5),
  refeicao text not null check (refeicao in ('DESJEJUM', 'ALMOCO', 'LANCHE', 'JANTAR')),
  ordem smallint not null,
  preparacao_codigo text not null references iara.preparacoes(codigo),
  primary key (cardapio_id, dia_semana, refeicao, ordem)
);

create table if not exists iara.refeicoes_servidas (
  unit_id integer not null references iara.education_units(id),
  data date not null,
  refeicao text not null check (refeicao in ('DESJEJUM', 'ALMOCO', 'LANCHE', 'JANTAR')),
  quantidade integer not null,
  adaptadas integer not null default 0,
  registrado_label text,
  is_demo boolean not null default true,
  primary key (unit_id, data, refeicao)
);

alter table iara.restricoes_alimentares enable row level security;
alter table iara.aluno_restricoes enable row level security;
alter table iara.preparacoes enable row level security;
alter table iara.cardapios enable row level security;
alter table iara.cardapio_itens enable row level security;
alter table iara.refeicoes_servidas enable row level security;

-- faixa do cardápio pela série; refeições pelo turno
create or replace function iara.faixa_cardapio(p_grade_code text) returns text
language sql immutable as $$ select case when p_grade_code in ('CRECHE', 'PRE') then p_grade_code else 'EF' end $$;
-- CMEI parcial: manhã = desjejum e almoço, tarde = lanche e jantar; fundamental parcial = merenda (lanche); noite = jantar
drop function if exists iara.refeicoes_do_turno(text);
create or replace function iara.refeicoes_do_turno(p_shift text, p_faixa text) returns text[]
language sql immutable as $$
  select case when p_shift = 'NOITE' then array['JANTAR']
              when p_shift = 'INTEGRAL' and p_faixa = 'EF' then array['DESJEJUM', 'ALMOCO', 'LANCHE']
              when p_shift = 'INTEGRAL' then array['DESJEJUM', 'ALMOCO', 'LANCHE', 'JANTAR']
              when p_faixa = 'EF' then array['LANCHE']
              when p_shift = 'MANHA' then array['DESJEJUM', 'ALMOCO'] else array['LANCHE', 'JANTAR'] end
$$;

-- o que a restrição do aluno exclui (a fruta do laudo entra pelo detalhe)
create or replace function iara.exclusoes(p_codigo text, p_detalhe text) returns text[]
language sql stable as $$
  select r.exclui || case when p_codigo = 'FRUTA_LAUDO' and p_detalhe is not null then array[lower(p_detalhe)] else '{}' end
  from iara.restricoes_alimentares r where r.codigo = p_codigo
$$;

-- substituto: preparação do mesmo grupo sem nenhum ingrediente excluído (prefere as marcadas como substitutas)
create or replace function iara.substituto(p_prep text, p_exclui text[]) returns text
language sql stable as $$
  select case when not (p.tags && p_exclui) then p.codigo
              else (select s.codigo from iara.preparacoes s where s.grupo = p.grupo and not (s.tags && p_exclui)
                    order by s.substituta desc, md5(s.codigo || p.codigo) limit 1) end
  from iara.preparacoes p where p.codigo = p_prep
$$;

-- cardápio da semana de uma faixa, já com a troca para uma lista de exclusões (vazia = cardápio geral)
create or replace function iara.cardapio_semana_json(p_faixa text, p_semana date, p_exclui text[] default '{}', p_refeicoes text[] default null)
returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('faixa', c.faixa, 'semana_inicio', c.semana_inicio, 'responsavel', c.responsavel_label,
    'dias', (select coalesce(jsonb_agg(jsonb_build_object('dia', d.dia, 'data', c.semana_inicio + d.dia - 1, 'refeicoes', d.refs) order by d.dia), '[]')
      from (select i.dia_semana dia, jsonb_agg(jsonb_build_object('refeicao', i.refeicao, 'itens', i.itens)
                   order by array_position(array['DESJEJUM', 'ALMOCO', 'LANCHE', 'JANTAR'], i.refeicao)) refs
            from (select it.dia_semana, it.refeicao, jsonb_agg(jsonb_build_object(
                    'nome', p.nome, 'troca', case when iara.substituto(p.codigo, p_exclui) is distinct from p.codigo
                                                  then (select nome from iara.preparacoes where codigo = iara.substituto(p.codigo, p_exclui)) end)
                    order by it.ordem) itens
                  from iara.cardapio_itens it join iara.preparacoes p on p.codigo = it.preparacao_codigo
                  where it.cardapio_id = c.id and (p_refeicoes is null or it.refeicao = any (p_refeicoes))
                  group by it.dia_semana, it.refeicao) i
            group by i.dia_semana) d))
  from iara.cardapios c where c.faixa = p_faixa and c.semana_inicio = p_semana and c.situacao = 'PUBLICADO'
$$;

-- 2. Gerador da demonstração ------------------------------------------------------------------------------------------------------
-- cardápios publicados de 02/02 até 3 semanas à frente de p_ate; só cria as semanas que faltam (rotina diária)
create or replace function iara.demo_gerar_cardapios(p_ate date default current_date) returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_semana date;
  v_id uuid;
  v_k integer;
  v_n integer := 0;
  f text;
begin
  -- ciclo de 4 semanas (cardápio de demonstração assinado pela nutrição)
  for v_semana in select generate_series(date '2026-02-02', (date_trunc('week', p_ate) + interval '21 days')::date, interval '7 days')::date loop
    foreach f in array array['CRECHE', 'PRE', 'EF'] loop
      continue when exists (select 1 from iara.cardapios where faixa = f and semana_inicio = v_semana);
      insert into iara.cardapios (faixa, semana_inicio, situacao, responsavel_label, publicado_em, is_demo)
      values (f, v_semana, 'PUBLICADO', 'Nutricionista responsável técnica (demonstração)', v_semana - 5, true) returning id into v_id;
      v_n := v_n + 1;
      v_k := ((v_semana - date '2026-02-02') / 7) % 4;
      insert into iara.cardapio_itens (cardapio_id, dia_semana, refeicao, ordem, preparacao_codigo)
      select v_id, d, r.refeicao, r.ordem, r.prep
      from generate_series(1, 5) d
      cross join lateral (values
        ('DESJEJUM', 1, (array['LEITE_CACAU', 'IOGURTE', 'VITAMINA_BANANA', 'LEITE_CACAU', 'SUCO_LARANJA'])[1 + (d + v_k) % 5]),
        ('DESJEJUM', 2, (array['PAO_MANTEIGA', 'BISCOITO_POLVILHO', 'MINGAU_AVEIA', 'PAO_QUEIJO', 'BOLO_CENOURA'])[1 + (d + v_k * 2) % 5]),
        ('ALMOCO', 1, 'ARROZ_FEIJAO'),
        ('ALMOCO', 2, (array['FRANGO_ENSOPADO', 'CARNE_MOIDA', 'PEIXE_ASSADO', 'MACARRAO_BOLONHESA', 'RISOTO_FRANGO', 'LOMBO_SUINO', 'ESTROGONOFE', 'POLENTA_MOLHO', 'OMELETE'])[1 + (d * 2 + v_k * 3) % 9]),
        ('ALMOCO', 3, (array['SALADA_FOLHAS', 'LEGUMES_REFOGADOS', 'BETERRABA', 'PURE_BATATA'])[1 + (d + v_k) % 4]),
        ('ALMOCO', 4, (array['FRUTA_MELANCIA', 'FRUTA_LARANJA', 'FRUTA_MAMAO', 'FRUTA_BANANA', 'FRUTA_MACA'])[1 + (d + v_k) % 5]),
        ('LANCHE', 1, (array['SUCO_LARANJA', 'LEITE_CACAU', 'CHA_ERVA_DOCE', 'IOGURTE', 'VITAMINA_BANANA'])[1 + (d + v_k + 2) % 5]),
        ('LANCHE', 2, (array['BOLO_CENOURA', 'TAPIOCA_FRANGO', 'PAO_QUEIJO', 'FRUTA_MACA', 'BISCOITO_POLVILHO'])[1 + (d + v_k + 1) % 5]),
        ('JANTAR', 1, 'ARROZ_FEIJAO'),
        ('JANTAR', 2, (array['CARNE_MOIDA', 'FRANGO_ENSOPADO', 'OMELETE', 'POLENTA_MOLHO', 'PEIXE_ASSADO'])[1 + (d + v_k * 2 + 3) % 5]),
        ('JANTAR', 3, (array['LEGUMES_COZIDOS', 'SALADA_FOLHAS', 'BETERRABA'])[1 + (d + v_k) % 3])) r(refeicao, ordem, prep);
    end loop;
  end loop;
  return v_n;
end $$;

create or replace function iara.demo_gerar_nutricao() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.cardapios where is_demo;
  perform iara.demo_gerar_cardapios(current_date);

  -- restrições: cerca de 3% dos alunos, com prevalência de demonstração; 70% validadas pela nutrição, 25% aguardando
  delete from iara.aluno_restricoes where is_demo;
  insert into iara.aluno_restricoes (student_id, restricao_codigo, detalhe, inicio, situacao, validada_por_label, validada_em, origem, is_demo)
  select e.student_id, x.cod,
         case when x.cod = 'FRUTA_LAUDO' then (array['banana', 'maca', 'mamao', 'laranja'])[1 + x.h % 4] end,
         date '2026-02-02' + (x.h % 120),
         case when x.h % 20 < 14 then 'VALIDADA' when x.h % 20 < 19 then 'INFORMADA' else 'RECUSADA' end,
         case when x.h % 20 < 14 then 'Nutrição escolar (demonstração)' end,
         case when x.h % 20 < 14 then now() - make_interval(days => x.h % 200) end,
         'DEMO', true
  from iara.enrollments e
  cross join lateral (select abs(('x' || substr(md5(e.student_id::text || 'nut'), 1, 8))::bit(32)::int) h) hh
  cross join lateral (select hh.h, case
      when hh.h % 1000 < 5 then 'APLV' when hh.h % 1000 < 13 then 'LACTOSE' when hh.h % 1000 < 15 then 'CELIACA'
      when hh.h % 1000 < 17 then 'DIABETES' when hh.h % 1000 < 20 then 'OVO_TOTAL' when hh.h % 1000 < 22 then 'OVO_IN_NATURA'
      when hh.h % 1000 < 26 then 'VEGETARIANO' when hh.h % 1000 < 27 then 'VEGANO' when hh.h % 1000 < 29 then 'PORCO_ADVENTISTA'
      when hh.h % 1000 < 30 then 'PORCO_RELIGIAO' when hh.h % 1000 < 31 then 'PORCO_OPCAO' when hh.h % 1000 < 32 then 'CORANTES'
      when hh.h % 1000 < 33 then 'COLORAU' when hh.h % 1000 < 34 then 'OLEO_SOJA' when hh.h % 1000 < 35 then 'SOJA'
      when hh.h % 1000 < 36 then 'DISLIPIDEMIA' when hh.h % 1000 < 38 then 'FRUTA_LAUDO' end cod) x
  where e.status = 'ACTIVE' and x.cod is not null;
  perform set_config('iara.skip_audit', 'off', true);
  return jsonb_build_object('cardapios', (select count(*) from iara.cardapios where is_demo),
    'restricoes', (select jsonb_object_agg(situacao, n) from (select situacao, count(*) n from iara.aluno_restricoes where is_demo group by 1) z));
end $$;

-- refeições servidas por unidade e dia, pela presença registrada na chamada (gerado mês a mês)
create or replace function iara.demo_gerar_refeicoes_periodo(p_de date, p_ate date) returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_n integer;
begin
  perform set_config('iara.skip_audit', 'on', true);
  delete from iara.refeicoes_servidas where is_demo and data between p_de and p_ate;
  create temp table if not exists tmp_matric (class_id uuid primary key, n integer, adapt integer) on commit drop;
  truncate tmp_matric;
  insert into tmp_matric
  select e.class_id, count(*), count(*) filter (where exists (select 1 from iara.aluno_restricoes ar where ar.student_id = e.student_id and ar.situacao = 'VALIDADA'))
  from iara.enrollments e where e.status = 'ACTIVE' group by e.class_id;
  insert into iara.refeicoes_servidas (unit_id, data, refeicao, quantidade, adaptadas, registrado_label, is_demo)
  select c.unit_id, r.data, m.refeicao,
         sum(greatest(t.n - (select count(*) from iara.frequencia_faltas f where f.registro_id = r.id), 0)
             * (0.93 + (abs(hashtext(r.id::text || m.refeicao)) % 7) / 100.0))::int,  -- nem todo presente come em toda refeição
         sum(t.adapt)::int, 'Cozinha da unidade (demonstração)', true
  from iara.frequencia_registros r join iara.classes c on c.id = r.class_id join tmp_matric t on t.class_id = c.id
  join iara.grade_levels gl on gl.id = c.grade_level_id
  cross join lateral unnest(iara.refeicoes_do_turno(c.shift, iara.faixa_cardapio(gl.code))) m(refeicao)
  where r.data between p_de and p_ate
  group by c.unit_id, r.data, m.refeicao
  on conflict (unit_id, data, refeicao) do update set quantidade = excluded.quantidade, adaptadas = excluded.adaptadas;
  get diagnostics v_n = row_count;
  perform set_config('iara.skip_audit', 'off', true);
  return v_n;
end $$;

-- 3. Consultas --------------------------------------------------------------------------------------------------------------------
-- cardápio público da semana (as três faixas)
create or replace function api.cardapio(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_semana date := date_trunc('week', coalesce(nullif(p ->> 'data', '')::date, current_date))::date;
begin
  if extract(isodow from current_date) >= 6 and nullif(p ->> 'data', '') is null then v_semana := v_semana + 7; end if;
  return jsonb_build_object('semana_inicio', v_semana,
    'faixas', (select coalesce(jsonb_agg(iara.cardapio_semana_json(f, v_semana) order by o), '[]')
               from unnest(array['CRECHE', 'PRE', 'EF']) with ordinality u(f, o) where iara.cardapio_semana_json(f, v_semana) is not null),
    'restricoes', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'descricao', descricao, 'motivo', motivo, 'exige_laudo', exige_laudo) order by ordem)
                   from iara.restricoes_alimentares));
end $$;

-- família: cardápio de cada filho, já com as trocas das restrições validadas — portal e IARA
create or replace function api.familia_cardapio(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_semana date := date_trunc('week', coalesce(nullif(p ->> 'data', '')::date, current_date))::date;
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  if extract(isodow from current_date) >= 6 and nullif(p ->> 'data', '') is null then v_semana := v_semana + 7; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('student_id', s.id, 'nome', s.full_name, 'primeiro_nome', split_part(s.full_name, ' ', 1),
            'unidade', u.short_name, 'turno', c.shift,
            'restricoes', (select coalesce(jsonb_agg(jsonb_build_object('descricao', ra.descricao, 'situacao', ar.situacao, 'detalhe', ar.detalhe)), '[]')
                           from iara.aluno_restricoes ar join iara.restricoes_alimentares ra on ra.codigo = ar.restricao_codigo
                           where ar.student_id = s.id and (ar.fim is null or ar.fim >= current_date)),
            'cardapio', iara.cardapio_semana_json(iara.faixa_cardapio(gl.code), v_semana,
                coalesce((select array_agg(distinct x) from iara.aluno_restricoes ar, unnest(iara.exclusoes(ar.restricao_codigo, ar.detalhe)) x
                          where ar.student_id = s.id and ar.situacao = 'VALIDADA' and (ar.fim is null or ar.fim >= current_date)), '{}'),
                iara.refeicoes_do_turno(c.shift, iara.faixa_cardapio(gl.code)))) order by s.full_name), '[]')
          from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
          join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
          join iara.education_units u on u.id = e.unit_id
          where s.id in (select iara.my_student_ids()));
end $$;

-- família informa uma restrição (fica aguardando a validação da nutrição; as clínicas pedem laudo na unidade)
create or replace function api.familia_informar_restricao(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  r iara.restricoes_alimentares;
begin
  if iara.my_guardian() is null or not (v_student in (select iara.my_student_ids())) then
    raise exception 'Criança não vinculada a você.' using errcode = '42501';
  end if;
  select * into r from iara.restricoes_alimentares where codigo = p ->> 'codigo';
  if r.codigo is null then raise exception 'Restrição desconhecida.' using errcode = '22023'; end if;
  if exists (select 1 from iara.aluno_restricoes where student_id = v_student and restricao_codigo = r.codigo and situacao <> 'RECUSADA') then
    raise exception 'Essa restrição já está registrada.' using errcode = '22023';
  end if;
  insert into iara.aluno_restricoes (student_id, restricao_codigo, detalhe, situacao, origem, is_demo)
  values (v_student, r.codigo, nullif(btrim(coalesce(p ->> 'detalhe', '')), ''), 'INFORMADA', 'FAMILIA', false);
  perform iara.audit_event('RESTRICAO_INFORMADA', 'student', v_student::text, null, 'Restrição alimentar informada pela família: ' || r.descricao || '.');
  return jsonb_build_object('ok', true, 'mensagem', case when r.exige_laudo
    then 'Registrado. Leve o laudo à secretaria da unidade: a nutrição valida e a cozinha passa a preparar a refeição adequada.'
    else 'Registrado. A nutrição confere e a cozinha passa a preparar a refeição adequada.' end);
end $$;

create or replace function api.nutricao_painel(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_ult date := (select max(data) from iara.refeicoes_servidas where data < current_date);
begin
  perform iara.require_perm('nutricao.read');
  return jsonb_build_object(
    'unidade', (select jsonb_build_object('id', id, 'name', name) from iara.education_units where id = v_unit),
    'por_restricao', (select coalesce(jsonb_agg(jsonb_build_object('codigo', z.codigo, 'descricao', z.descricao, 'motivo', z.motivo,
         'validadas', z.validadas, 'aguardando', z.aguardando) order by z.ordem), '[]')
       from (select ra.codigo, ra.descricao, ra.motivo, ra.ordem, count(ar.id) filter (where ar.situacao = 'VALIDADA') validadas,
                    count(ar.id) filter (where ar.situacao = 'INFORMADA') aguardando
             from iara.restricoes_alimentares ra
             left join (select ar.* from iara.aluno_restricoes ar join iara.enrollments e on e.student_id = ar.student_id and e.status = 'ACTIVE'
                        where (v_unit is null or e.unit_id = v_unit) and (ar.fim is null or ar.fim >= current_date)) ar on ar.restricao_codigo = ra.codigo
             group by ra.codigo, ra.descricao, ra.motivo, ra.ordem) z),
    'ultimo_dia', v_ult,
    'refeicoes_ultimo_dia', (select coalesce(jsonb_object_agg(refeicao, q), '{}') from (select refeicao, sum(quantidade) q from iara.refeicoes_servidas
         where data = v_ult and (v_unit is null or unit_id = v_unit) group by 1) z),
    'refeicoes_mes', (select coalesce(sum(quantidade), 0) from iara.refeicoes_servidas where data >= date_trunc('month', current_date) and (v_unit is null or unit_id = v_unit)),
    'refeicoes_ano', (select coalesce(sum(quantidade), 0) from iara.refeicoes_servidas where (v_unit is null or unit_id = v_unit)),
    'adaptadas_ultimo_dia', (select coalesce(sum(adaptadas), 0) from iara.refeicoes_servidas where data = v_ult and (v_unit is null or unit_id = v_unit)),
    'por_dia', (select coalesce(jsonb_agg(jsonb_build_object('data', data, 'quantidade', q) order by data), '[]') from (
         select data, sum(quantidade) q from iara.refeicoes_servidas where data >= current_date - 30 and (v_unit is null or unit_id = v_unit) group by 1) z),
    'unidades_sem_registro', (select coalesce(jsonb_agg(u.short_name order by u.short_name), '[]') from iara.education_units u
         where u.status = 'ATIVA' and (v_unit is null or u.id = v_unit) and iara.dia_letivo(v_ult, u.id)
           and exists (select 1 from iara.classes c where c.unit_id = u.id and c.status = 'ATIVA')
           and not exists (select 1 from iara.refeicoes_servidas r where r.unit_id = u.id and r.data = v_ult)),
    'aguardando_validacao', (select coalesce(jsonb_agg(jsonb_build_object('id', ar.id, 'aluno', s.full_name, 'unidade', un.short_name, 'turma', c.class_name,
         'restricao', ra.descricao, 'detalhe', ar.detalhe, 'exige_laudo', ra.exige_laudo, 'informada_em', ar.created_at) order by ar.created_at), '[]')
       from (select ar.* from iara.aluno_restricoes ar where ar.situacao = 'INFORMADA' order by ar.created_at limit 200) ar
       join iara.restricoes_alimentares ra on ra.codigo = ar.restricao_codigo join iara.students s on s.id = ar.student_id
       join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' join iara.classes c on c.id = e.class_id
       join iara.education_units un on un.id = e.unit_id
       where (v_unit is null or e.unit_id = v_unit) and iara.has_perm('nutricao.manage')));
end $$;

create or replace function api.restricao_validar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  ar iara.aluno_restricoes;
begin
  perform iara.require_perm('nutricao.manage');
  select * into ar from iara.aluno_restricoes where id = (p ->> 'id')::uuid;
  if ar.id is null then raise exception 'Restrição não encontrada.' using errcode = 'P0002'; end if;
  update iara.aluno_restricoes set situacao = case when (p ->> 'validar')::boolean then 'VALIDADA' else 'RECUSADA' end,
         validada_por_label = iara.my_label(), validada_em = now(), observacao = nullif(btrim(coalesce(p ->> 'observacao', '')), '')
  where id = ar.id;
  perform iara.audit_event('RESTRICAO_VALIDADA', 'student', ar.student_id::text, null,
    format('Restrição alimentar %s pela nutrição.', case when (p ->> 'validar')::boolean then 'validada' else 'recusada' end));
  return jsonb_build_object('ok', true);
end $$;

-- lista da cozinha: crianças da unidade com restrição validada, presentes no dia, e a troca de cada refeição (sem laudo)
create or replace function api.cozinha_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_dia date := coalesce(nullif(p ->> 'data', '')::date, current_date);
  v_semana date := date_trunc('week', v_dia)::date;
  v_dow integer := extract(isodow from v_dia)::int;
begin
  perform iara.require_perm('cozinha.read');
  if v_unit is null then raise exception 'Escolha a unidade.' using errcode = '22023'; end if;
  return jsonb_build_object('unidade', (select name from iara.education_units where id = v_unit), 'data', v_dia,
    'dia_letivo', iara.dia_letivo(v_dia, v_unit),
    'criancas', (select coalesce(jsonb_agg(jsonb_build_object('aluno', split_part(s.full_name, ' ', 1) || ' ' || left(split_part(s.full_name, ' ', 2), 1) || '.',
        'turma', c.class_name, 'turno', c.shift, 'restricao', ra.descricao, 'detalhe', ar.detalhe, 'orientacao', ra.orientacao_cozinha,
        'ausente', exists (select 1 from iara.frequencia_faltas f join iara.frequencia_registros r on r.id = f.registro_id
                           where f.student_id = s.id and r.data = v_dia),
        'trocas', (select coalesce(jsonb_agg(jsonb_build_object('refeicao', it.refeicao, 'de', pr.nome,
                     'para', (select nome from iara.preparacoes where codigo = iara.substituto(pr.codigo, iara.exclusoes(ar.restricao_codigo, ar.detalhe))))
                     order by it.refeicao, it.ordem), '[]')
                   from iara.cardapios cd join iara.cardapio_itens it on it.cardapio_id = cd.id join iara.preparacoes pr on pr.codigo = it.preparacao_codigo
                   where cd.faixa = iara.faixa_cardapio(gl.code) and cd.semana_inicio = v_semana and it.dia_semana = v_dow
                     and it.refeicao = any (iara.refeicoes_do_turno(c.shift, iara.faixa_cardapio(gl.code)))
                     and pr.tags && iara.exclusoes(ar.restricao_codigo, ar.detalhe)))
        order by c.class_name, s.full_name), '[]')
      from iara.aluno_restricoes ar join iara.restricoes_alimentares ra on ra.codigo = ar.restricao_codigo
      join iara.students s on s.id = ar.student_id join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' and e.unit_id = v_unit
      join iara.classes c on c.id = e.class_id join iara.grade_levels gl on gl.id = c.grade_level_id
      where ar.situacao = 'VALIDADA' and (ar.fim is null or ar.fim >= v_dia)),
    'refeicoes', (select coalesce(jsonb_object_agg(refeicao, jsonb_build_object('quantidade', quantidade, 'adaptadas', adaptadas)), '{}')
                  from iara.refeicoes_servidas where unit_id = v_unit and data = v_dia));
end $$;

create or replace function api.refeicoes_registrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_dia date := coalesce(nullif(p ->> 'data', '')::date, current_date);
  x record;
begin
  perform iara.require_perm('cozinha.read');
  if v_unit is null or not iara.can_access_unit(v_unit) then raise exception 'Unidade fora do seu escopo.' using errcode = '42501'; end if;
  if v_dia > current_date then raise exception 'Não dá para registrar refeição de dia futuro.' using errcode = '22023'; end if;
  for x in select key refeicao, (value ->> 'quantidade')::int q, coalesce((value ->> 'adaptadas')::int, 0) a
           from jsonb_each(coalesce(p -> 'refeicoes', '{}'::jsonb)) loop
    if x.refeicao not in ('DESJEJUM', 'ALMOCO', 'LANCHE', 'JANTAR') or x.q < 0 or x.q > 5000 then
      raise exception 'Refeição ou quantidade inválida.' using errcode = '22023';
    end if;
    insert into iara.refeicoes_servidas (unit_id, data, refeicao, quantidade, adaptadas, registrado_label, is_demo)
    values (v_unit, v_dia, x.refeicao, x.q, x.a, iara.my_label(), false)
    on conflict (unit_id, data, refeicao) do update set quantidade = excluded.quantidade, adaptadas = excluded.adaptadas,
      registrado_label = excluded.registrado_label, is_demo = false;
  end loop;
  perform iara.audit_event('REFEICOES_REGISTRADAS', 'education_unit', v_unit::text, v_unit, 'Refeições servidas de ' || to_char(v_dia, 'DD/MM/YYYY') || ' registradas.');
  return api.cozinha_lista(jsonb_build_object('unit_id', v_unit, 'data', v_dia));
end $$;

revoke all on function iara.demo_gerar_nutricao(), iara.demo_gerar_cardapios(date), iara.demo_gerar_refeicoes_periodo(date, date) from public;
grant execute on function api.cardapio(jsonb) to anon;

commit;
