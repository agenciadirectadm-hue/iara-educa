-- IARA Educa — 099.05 · Uniformes e kits escolares
-- Rotina completa, do pedido de tamanho à retirada na unidade, para os 118 CMEIs e escolas:
--   • catálogo oficial: Kit Escolar 2025/2026 (12 kits por etapa, documento da SEDUC no portal da Prefeitura) e Uniforme Escolar 2026
--     (4 camisetas — 2 regatas e 2 de manga curta —, 2 shorts-saia ou bermudas, 2 calças, 2 jaquetas, blusa de lã, papete até o Infantil 3
--     e 2 pares de meias a partir do Infantil 4); grade de tamanhos usual, editável pela SEDUC quando tiver a do contrato;
--   • o responsável informa os tamanhos e escolhe o modelo (shorts-saia ou bermuda), pelo portal ou pela IARA: o sistema não deduz pelo sexo;
--   • necessidades por aluno: entrega anual, aluno novo no meio do ano, troca de tamanho, reposição (perda ou dano) e material adaptado (AEE);
--   • estoque na SEDUC e nas unidades (catálogo, lotes e pedidos do almoxarifado): a SEDUC gera a remessa de cada unidade por etapa e tamanho;
--     a unidade recebe e o material fica disponível; cada retirada dá baixa no estoque da unidade;
--   • aviso à família com data e hora, código de retirada (e QR) e “Estou ciente”; depois da ciência, vai para o histórico;
--   • retirada só pelo responsável ou por pessoa autorizada a buscar a criança (Guarda e restrições), com código ou documento; fica na ficha do aluno;
--   • disparo em lotes pela ponte do WhatsApp da IARA, das 8h às 19h, com intervalo entre mensagens; na demonstração, só números autorizados recebem.
-- Estatísticas, mapas e visões externas: migração 099.06. Demonstração: 099.07.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

-- 0. Permissões ----------------------------------------------------------------------------------------------------------------------
insert into iara.permissions (code, description, is_sensitive) values
  ('uk.read', 'Ver uniformes e kits escolares (unidade ou rede): tamanhos, necessidades, avisos e retiradas', false),
  ('uk.unidade', 'Operar uniformes e kits na unidade: registrar retirada, tamanhos, trocas, reposições e liberar material', false),
  ('uk.manage', 'Gerir uniformes e kits na SEDUC: campanhas, composição, grade de tamanhos, remessas e disparos', false),
  ('uk.estatisticas', 'Ver estatísticas e mapas agregados de uniformes e kits (sem nomes)', false),
  ('uk.adaptado', 'Pedir material escolar adaptado para aluno do AEE', false)
on conflict (code) do update set description = excluded.description;
insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('SECRETARIO', 'uk.read'), ('SECRETARIO', 'uk.manage'), ('SECRETARIO', 'uk.estatisticas'),
  ('SUPERINTENDENCIA', 'uk.read'), ('SUPERINTENDENCIA', 'uk.manage'), ('SUPERINTENDENCIA', 'uk.estatisticas'),
  ('ALMOXARIFADO', 'uk.read'), ('ALMOXARIFADO', 'uk.manage'), ('ALMOXARIFADO', 'uk.estatisticas'),
  ('GERENCIA_EI', 'uk.read'), ('GERENCIA_EI', 'uk.estatisticas'),
  ('INOVACAO', 'uk.read'), ('INOVACAO', 'uk.estatisticas'),
  ('PREFEITO', 'uk.estatisticas'), ('CONTROLE_EXTERNO', 'uk.estatisticas'),
  ('DIRETOR_UNIDADE', 'uk.read'), ('DIRETOR_UNIDADE', 'uk.unidade'),
  ('SECRETARIA_ESCOLAR', 'uk.read'), ('SECRETARIA_ESCOLAR', 'uk.unidade'),
  ('ANALISTA_CENTRAL', 'uk.read'), ('ATENDIMENTO', 'uk.read'),
  ('PROFESSOR_AEE', 'uk.read'), ('PROFESSOR_AEE', 'uk.adaptado')
) v(r, p)
on conflict do nothing;

-- 1. Tabelas ------------------------------------------------------------------------------------------------------------------------
-- grade de tamanhos: ROUPA (parte de cima e de baixo), CALCADO (papete) e MEIA (faixa pelo número do calçado)
create table if not exists iara.uk_grades (
  grade text not null check (grade in ('ROUPA', 'CALCADO', 'MEIA')),
  tamanho text not null,
  ordem smallint not null,
  calcado_min smallint,
  calcado_max smallint,
  ativo boolean not null default true,
  primary key (grade, tamanho)
);

-- peças do uniforme e kits (cada kit com a composição oficial em uk_kit_itens)
create table if not exists iara.uk_itens (
  codigo text primary key,
  tipo text not null check (tipo in ('UNIFORME', 'KIT')),
  nome text not null,
  descricao text,
  medida text check (medida in ('SUPERIOR', 'INFERIOR', 'CALCADO', 'MEIA')),
  modelo text check (modelo in ('SHORTS_SAIA', 'BERMUDA')),
  quantidade smallint not null default 1 check (quantidade > 0),
  etapas text[] not null,
  so_ampliacao boolean not null default false,
  valor_referencia numeric(10, 2),
  valor_demo boolean not null default false,
  ordem smallint not null default 0,
  ativo boolean not null default true,
  fonte text not null default 'OFICIAL' check (fonte in ('OFICIAL', 'A_VALIDAR', 'DEMONSTRACAO'))
);
create table if not exists iara.uk_kit_itens (
  kit_codigo text not null references iara.uk_itens(codigo) on delete cascade,
  ordem smallint not null,
  item text not null,
  quantidade numeric(8, 2) not null,
  unidade text not null,
  especificacao text,
  primary key (kit_codigo, ordem)
);

create table if not exists iara.uk_parametros (
  chave text primary key,
  valor jsonb not null,
  descricao text
);

-- campanha do ano letivo: coleta de tamanhos → separação (remessas) → entrega → encerrada
create table if not exists iara.uk_campanhas (
  id uuid primary key default gen_random_uuid(),
  ano smallint not null unique,
  nome text not null,
  coleta_inicio date,
  coleta_fim date,
  entrega_inicio date,
  entrega_fim date,
  prazo_retirada_dias smallint not null default 30 check (prazo_retirada_dias between 3 and 180),
  inclui_uniforme boolean not null default true,
  inclui_kit boolean not null default true,
  situacao text not null default 'PLANEJAMENTO' check (situacao in ('PLANEJAMENTO', 'COLETA_TAMANHOS', 'SEPARACAO', 'ENTREGA', 'ENCERRADA')),
  observacao text,
  gerada_em timestamptz,
  atualizado_por_label text,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  is_demo boolean not null default false
);

-- alunos da Ampliação da Jornada Escolar (contraturno) — recebem também o kit da Ampliação; a turma em período integral também conta
create table if not exists iara.ampliacao_jornada (
  student_id uuid not null references iara.students(id) on delete cascade,
  ano smallint not null,
  unit_id integer references iara.education_units(id),
  ativo boolean not null default true,
  origem text not null default 'UNIDADE',
  created_at timestamptz not null default now(),
  is_demo boolean not null default false,
  primary key (student_id, ano)
);

-- tamanhos do uniforme por aluno e ano (informados pela família, pela unidade ou estimados pela idade para o planejamento da compra)
create table if not exists iara.uk_tamanhos (
  student_id uuid not null references iara.students(id) on delete cascade,
  ano smallint not null,
  superior text,
  inferior text,
  calcado smallint check (calcado between 14 and 46),
  modelo_inferior text check (modelo_inferior in ('SHORTS_SAIA', 'BERMUDA')),
  canal text not null check (canal in ('PORTAL', 'WHATSAPP', 'UNIDADE', 'ESTIMATIVA')),
  guardian_id uuid references iara.guardians(id) on delete set null,
  informado_por_label text,
  informado_em timestamptz not null default now(),
  is_demo boolean not null default false,
  primary key (student_id, ano)
);

-- código de retirada do aluno no ano (o mesmo para uniforme e kit)
create table if not exists iara.uk_codigos (
  student_id uuid not null references iara.students(id) on delete cascade,
  ano smallint not null,
  codigo text not null,
  created_at timestamptz not null default now(),
  primary key (student_id, ano),
  unique (ano, codigo)
);

create table if not exists iara.uk_necessidades (
  id uuid primary key default gen_random_uuid(),
  campanha_id uuid references iara.uk_campanhas(id) on delete set null,
  ano smallint not null,
  student_id uuid not null references iara.students(id) on delete cascade,
  unit_id integer references iara.education_units(id),
  etapa text,
  ampliacao boolean not null default false,
  tipo text not null check (tipo in ('ANUAL', 'ALUNO_NOVO', 'TROCA_TAMANHO', 'REPOSICAO', 'ADAPTADO')),
  conteudo text not null check (conteudo in ('UNIFORME', 'KIT', 'ADAPTADO')),
  itens jsonb not null default '[]',
  motivo text,
  origem text not null default 'SISTEMA' check (origem in ('SISTEMA', 'UNIDADE', 'FAMILIA', 'AEE', 'SEDUC')),
  solicitante_label text,
  situacao text not null check (situacao in ('AGUARDANDO_TAMANHO', 'AGUARDANDO_DECISAO', 'AGUARDANDO_MATERIAL', 'DISPONIVEL', 'RETIRADA', 'PARCIAL',
                                             'CANCELADA', 'NEGADA')),
  decisao_motivo text,
  decidido_por_label text,
  decidido_em timestamptz,
  pedido_id uuid references iara.pedidos(id) on delete set null,
  disponivel_em timestamptz,
  prazo_retirada date,
  retirada_em timestamptz,
  retirada_por_nome text,
  retirada_por_parentesco text,
  retirada_por_guardian uuid references iara.guardians(id) on delete set null,
  retirada_documento text,
  codigo_conferido boolean,
  registrado_por_label text,
  entregue jsonb,
  observacao text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_demo boolean not null default false
);
create index if not exists uk_nec_aluno_idx on iara.uk_necessidades (student_id, ano);
create index if not exists uk_nec_unit_idx on iara.uk_necessidades (unit_id, ano, situacao);
create index if not exists uk_nec_pedido_idx on iara.uk_necessidades (pedido_id) where pedido_id is not null;
create unique index if not exists uk_nec_anual_uq on iara.uk_necessidades (ano, student_id, conteudo) where tipo in ('ANUAL', 'ALUNO_NOVO') and situacao not in ('CANCELADA', 'NEGADA');

-- disparos em lote (o pedido da SEDUC ou da unidade)
create table if not exists iara.uk_disparos (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('TAMANHO', 'RETIRADA', 'LEMBRETE_RETIRADA')),
  ano smallint not null,
  filtro jsonb not null default '{}',
  total integer not null default 0,
  criado_por_label text,
  created_at timestamptz not null default now(),
  is_demo boolean not null default false
);

-- avisos à família (portal e IARA) — também a fila de envio pelo WhatsApp, em lotes
create table if not exists iara.uk_avisos (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references iara.students(id) on delete cascade,
  guardian_id uuid references iara.guardians(id) on delete set null,
  unit_id integer references iara.education_units(id),
  ano smallint not null,
  tipo text not null check (tipo in ('TAMANHO', 'RETIRADA', 'LEMBRETE_RETIRADA', 'RETIRADA_REGISTRADA', 'DECISAO')),
  necessidade_ids uuid[] not null default '{}',
  disparo_id uuid references iara.uk_disparos(id) on delete set null,
  titulo text not null,
  texto text not null,
  enviado_em timestamptz not null default now(),
  whatsapp_status text not null default 'AGENDADO' check (whatsapp_status in ('AGENDADO', 'ENVIADO', 'SIMULADO', 'SEM_WHATSAPP', 'NAO_ENVIAR')),
  agendado_para timestamptz,
  whatsapp_em timestamptz,
  ciente_em timestamptz,
  ciente_canal text,
  ciente_por uuid,
  is_demo boolean not null default false
);
create index if not exists uk_avisos_aluno_idx on iara.uk_avisos (student_id, enviado_em desc);
create index if not exists uk_avisos_fila_idx on iara.uk_avisos (agendado_para) where whatsapp_status = 'AGENDADO';

alter table iara.uk_grades enable row level security;
alter table iara.uk_itens enable row level security;
alter table iara.uk_kit_itens enable row level security;
alter table iara.uk_parametros enable row level security;
alter table iara.uk_campanhas enable row level security;
alter table iara.ampliacao_jornada enable row level security;
alter table iara.uk_tamanhos enable row level security;
alter table iara.uk_codigos enable row level security;
alter table iara.uk_necessidades enable row level security;
alter table iara.uk_disparos enable row level security;
alter table iara.uk_avisos enable row level security;

-- 2. Catálogo oficial e parâmetros ----------------------------------------------------------------------------------------------------
insert into iara.uk_parametros (chave, valor, descricao) values
  ('intervalo_segundos', '20', 'Intervalo entre mensagens do disparo em lotes pelo WhatsApp da IARA (segundos)'),
  ('horario_inicio', '8', 'Hora em que os disparos começam'),
  ('horario_fim', '19', 'Hora em que os disparos param'),
  ('lembrete_dias', '7', 'Dias antes do fim do prazo em que sai o lembrete de retirada'),
  ('tutelar_dias', '15', 'Dias depois do prazo de retirada vencido em que o caso aparece ao Conselho Tutelar (por código)')
on conflict (chave) do nothing;

insert into iara.uk_grades (grade, tamanho, ordem, calcado_min, calcado_max) values
  ('ROUPA', '1', 1, null, null), ('ROUPA', '2', 2, null, null), ('ROUPA', '4', 3, null, null), ('ROUPA', '6', 4, null, null),
  ('ROUPA', '8', 5, null, null), ('ROUPA', '10', 6, null, null), ('ROUPA', '12', 7, null, null), ('ROUPA', '14', 8, null, null),
  ('ROUPA', '16', 9, null, null), ('ROUPA', 'P', 10, null, null), ('ROUPA', 'M', 11, null, null), ('ROUPA', 'G', 12, null, null),
  ('ROUPA', 'GG', 13, null, null),
  ('MEIA', '16-19', 1, 16, 19), ('MEIA', '20-23', 2, 20, 23), ('MEIA', '24-27', 3, 24, 27), ('MEIA', '28-31', 4, 28, 31),
  ('MEIA', '32-35', 5, 32, 35), ('MEIA', '36-39', 6, 36, 39), ('MEIA', '40-43', 7, 40, 43)
on conflict (grade, tamanho) do nothing;
insert into iara.uk_grades (grade, tamanho, ordem)
select 'CALCADO', n::text, (n - 15)::smallint from generate_series(16, 36) n
on conflict (grade, tamanho) do nothing;

-- Uniforme Escolar 2026 (portal da Prefeitura, Educação → Uniforme)
insert into iara.uk_itens (codigo, tipo, nome, descricao, medida, modelo, quantidade, etapas, ordem, fonte) values
  ('UNI-REG', 'UNIFORME', 'Camiseta regata', '2 regatas', 'SUPERIOR', null, 2,
   array['INF0', 'INF1', 'INF2', 'INF3', 'INF4', 'INF5', 'EF1', 'EF2', 'EF3', 'EF4', 'EF5'], 1, 'OFICIAL'),
  ('UNI-MC', 'UNIFORME', 'Camiseta de manga curta', '2 de manga curta', 'SUPERIOR', null, 2,
   array['INF0', 'INF1', 'INF2', 'INF3', 'INF4', 'INF5', 'EF1', 'EF2', 'EF3', 'EF4', 'EF5'], 2, 'OFICIAL'),
  ('UNI-SHS', 'UNIFORME', 'Shorts-saia', 'Modelo feminino (a família escolhe o modelo)', 'INFERIOR', 'SHORTS_SAIA', 2,
   array['INF0', 'INF1', 'INF2', 'INF3', 'INF4', 'INF5', 'EF1', 'EF2', 'EF3', 'EF4', 'EF5'], 3, 'OFICIAL'),
  ('UNI-BER', 'UNIFORME', 'Bermuda', 'Modelo masculino (a família escolhe o modelo)', 'INFERIOR', 'BERMUDA', 2,
   array['INF0', 'INF1', 'INF2', 'INF3', 'INF4', 'INF5', 'EF1', 'EF2', 'EF3', 'EF4', 'EF5'], 4, 'OFICIAL'),
  ('UNI-CAL', 'UNIFORME', 'Calça', null, 'INFERIOR', null, 2,
   array['INF0', 'INF1', 'INF2', 'INF3', 'INF4', 'INF5', 'EF1', 'EF2', 'EF3', 'EF4', 'EF5'], 5, 'OFICIAL'),
  ('UNI-JAQ', 'UNIFORME', 'Jaqueta', null, 'SUPERIOR', null, 2,
   array['INF0', 'INF1', 'INF2', 'INF3', 'INF4', 'INF5', 'EF1', 'EF2', 'EF3', 'EF4', 'EF5'], 6, 'OFICIAL'),
  ('UNI-LA', 'UNIFORME', 'Blusa de lã', null, 'SUPERIOR', null, 1,
   array['INF0', 'INF1', 'INF2', 'INF3', 'INF4', 'INF5', 'EF1', 'EF2', 'EF3', 'EF4', 'EF5'], 7, 'OFICIAL'),
  ('UNI-PAP', 'UNIFORME', 'Sandália papete', 'Até o Infantil 3', 'CALCADO', null, 1,
   array['INF0', 'INF1', 'INF2', 'INF3'], 8, 'OFICIAL'),
  ('UNI-MEI', 'UNIFORME', 'Meias (par)', 'A partir do Infantil 4', 'MEIA', null, 2,
   array['INF4', 'INF5', 'EF1', 'EF2', 'EF3', 'EF4', 'EF5'], 9, 'OFICIAL')
on conflict (codigo) do update set nome = excluded.nome, descricao = excluded.descricao, medida = excluded.medida, modelo = excluded.modelo,
  quantidade = excluded.quantidade, etapas = excluded.etapas, ordem = excluded.ordem, fonte = excluded.fonte;

-- Kit Escolar 2025 e 2026 (anexo “Composição do Kit Escolar 2025 e 2026.pdf”, portal da Prefeitura, Educação → Kit Escolar)
insert into iara.uk_itens (codigo, tipo, nome, descricao, medida, modelo, quantidade, etapas, so_ampliacao, ordem, fonte) values
  ('KIT-INF01', 'KIT', 'Kit escolar Infantil 0 e 1', 'Título no documento oficial: KIT INFANTIL 0 E 1', null, null, 1, array['INF0', 'INF1'], false, 100, 'OFICIAL'),
  ('KIT-INF2', 'KIT', 'Kit escolar Infantil 2', 'Título no documento oficial: KIT INFANTIL 2', null, null, 1, array['INF2'], false, 101, 'OFICIAL'),
  ('KIT-INF3', 'KIT', 'Kit escolar Infantil 3', 'Título no documento oficial: KIT INFANTIL 3', null, null, 1, array['INF3'], false, 102, 'OFICIAL'),
  ('KIT-INF4', 'KIT', 'Kit escolar Infantil 4', 'Título no documento oficial: KIT INFANTIL 4', null, null, 1, array['INF4'], false, 103, 'OFICIAL'),
  ('KIT-INF5', 'KIT', 'Kit escolar Infantil 5', 'Título no documento oficial: KIT INFANTIL 5', null, null, 1, array['INF5'], false, 104, 'OFICIAL'),
  ('KIT-EF1', 'KIT', 'Kit escolar 1º ano', 'Título no documento oficial: KIT FUNDAMENTAL 1.º ANO', null, null, 1, array['EF1'], false, 105, 'OFICIAL'),
  ('KIT-EF2', 'KIT', 'Kit escolar 2º ano', 'Título no documento oficial: KIT FUNDAMENTAL 2.º ANO', null, null, 1, array['EF2'], false, 106, 'OFICIAL'),
  ('KIT-EF34', 'KIT', 'Kit escolar 3º e 4º anos', 'Título no documento oficial: KIT FUNDAMENTAL 3.º e 4.º ANOS', null, null, 1, array['EF3', 'EF4'], false, 107, 'OFICIAL'),
  ('KIT-EF5', 'KIT', 'Kit escolar 5º ano', 'Título no documento oficial: KIT FUNDAMENTAL 5.º ANO', null, null, 1, array['EF5'], false, 108, 'OFICIAL'),
  ('KIT-EJA', 'KIT', 'Kit escolar EJA', 'Título no documento oficial: KIT EDUCAÇÃO DE JOVENS E ADULTOS (EJA)', null, null, 1, array['EJA'], false, 109, 'OFICIAL'),
  ('KIT-AJE1', 'KIT', 'Kit da Ampliação de Jornada 1º ano', 'Título no documento oficial: KIT AMPLIAÇÃO E JORNADA ESCOLAR 1.º ANO', null, null, 1, array['EF1'], true, 110, 'OFICIAL'),
  ('KIT-AJE25', 'KIT', 'Kit da Ampliação de Jornada 2º ao 5º ano', 'Título no documento oficial: KIT AMPLIAÇÃO DE JORNADA ESCOLAR 2.º, 3.º, 4.º E 5.º ANOS', null, null, 1, array['EF2', 'EF3', 'EF4', 'EF5'], true, 111, 'OFICIAL')
on conflict (codigo) do update set nome = excluded.nome, descricao = excluded.descricao, etapas = excluded.etapas, so_ampliacao = excluded.so_ampliacao, ordem = excluded.ordem, fonte = excluded.fonte;

delete from iara.uk_kit_itens where kit_codigo like 'KIT-%';
insert into iara.uk_kit_itens (kit_codigo, ordem, item, quantidade, unidade, especificacao) values
  ('KIT-INF01', 1, 'Bloco de desenho A3, 20 folhas', 2, 'un', '297 x 420 mm, 20 folhas lisas brancas de 140 a 180 g/m²'),
  ('KIT-INF01', 2, 'Giz em gel, 12 cores', 1, 'emb', '12 cores, retrátil, aquarelável, mín. 12 cm, em estojo'),
  ('KIT-INF01', 3, 'Giz em gel tons de pele, 6 cores', 1, 'emb', '6 tons de pele, retrátil, aquarelável, mín. 12 cm'),
  ('KIT-INF01', 4, 'Pasta escolar polionda A3, azul', 1, 'un', 'A3, lombo de 25 a 35 mm, cor azul'),
  ('KIT-INF2', 1, 'Bloco de desenho A3, 20 folhas', 2, 'un', '297 x 420 mm, 20 folhas lisas brancas de 140 a 180 g/m²'),
  ('KIT-INF2', 2, 'Caneta hidrográfica jumbo, 12 cores', 1, 'emb', 'Big/jumbo, 12 cores, mín. 120 mm, traço de 1 a 4 mm, lavável, tampa antiasfixiante'),
  ('KIT-INF2', 3, 'Giz em gel, 12 cores', 1, 'emb', '12 cores, retrátil, aquarelável, mín. 12 cm, em estojo'),
  ('KIT-INF2', 4, 'Giz em gel tons de pele, 6 cores', 1, 'emb', '6 tons de pele, retrátil, aquarelável, mín. 12 cm'),
  ('KIT-INF2', 5, 'Pasta escolar polionda A3, azul', 1, 'un', 'A3, lombo de 25 a 35 mm, cor azul'),
  ('KIT-INF2', 6, 'Pincel broxa nº 0', 1, 'un', 'Redondo, cerdas sintéticas, cabo curto de madeira'),
  ('KIT-INF2', 7, 'Massa de modelar, 12 cores', 2, 'conj', 'Conjunto com 12 cores, mín. 180 g, atóxica'),
  ('KIT-INF2', 8, 'Cola branca líquida, 90 g', 2, 'un', 'PVA, 90 a 110 g, tampa de rosca, ensacada individualmente'),
  ('KIT-INF3', 1, 'Bloco de desenho A3, 20 folhas', 3, 'un', '297 x 420 mm, 20 folhas lisas brancas de 140 a 180 g/m²'),
  ('KIT-INF3', 2, 'Cola branca líquida, 90 g', 2, 'un', 'PVA, 90 a 110 g, tampa de rosca, ensacada individualmente'),
  ('KIT-INF3', 3, 'Cola colorida com glitter, 6 cores', 1, 'cx', 'Caixa com 6 potes de mín. 23 g, efeito relevo, lavável'),
  ('KIT-INF3', 4, 'Tesoura escolar sem ponta', 1, 'un', 'Inox, ponta arredondada, 120 a 140 mm'),
  ('KIT-INF3', 5, 'Caneta hidrográfica jumbo, 12 cores', 1, 'emb', 'Big/jumbo, 12 cores, mín. 120 mm, traço de 1 a 4 mm, lavável, tampa antiasfixiante'),
  ('KIT-INF3', 6, 'Caneta hidrográfica tons de pele, 12 cores', 1, 'estojo', 'Estojo com 12 tons de pele, traço de 1 a 3 mm, lavável'),
  ('KIT-INF3', 7, 'Giz de cera jumbo, 12 cores', 2, 'estojo', 'Estojo com 12 cores, tipo estaca, mín. 9 cm, mín. 95 g'),
  ('KIT-INF3', 8, 'Giz em gel, 12 cores', 1, 'emb', '12 cores, retrátil, aquarelável, mín. 12 cm, em estojo'),
  ('KIT-INF3', 9, 'Borracha branca nº 40', 2, 'un', 'Macia, de 30 x 20 x 8 mm a 33 x 23 x 10 mm'),
  ('KIT-INF3', 10, 'Apontador duplo com depósito', 2, 'un', 'Dois furos (lápis jumbo e normal), lâmina inox'),
  ('KIT-INF3', 11, 'Lápis de cor jumbo, 12 cores', 1, 'cx', 'Caixa com 12, triangular, mín. 120 mm, com apontador'),
  ('KIT-INF3', 12, 'Lápis grafite jumbo, conjunto de 3 com apontador', 3, 'conj', 'Conjunto com 3 lápis triangulares (mín. 120 mm) e 1 apontador'),
  ('KIT-INF3', 13, 'Lápis de cor tons de pele, 6 a 12 cores', 1, 'cx', 'Caixa com 6 a 12 tons de pele, grafite de 3 a 6 mm'),
  ('KIT-INF3', 14, 'Pincel chato nº 24', 1, 'un', 'Cerdas sintéticas macias, cabo longo de madeira'),
  ('KIT-INF3', 15, 'Pincel chato nº 22', 1, 'un', 'Cerdas sintéticas macias, cabo longo de madeira'),
  ('KIT-INF3', 16, 'Pincel broxa nº 0', 1, 'un', 'Redondo, cerdas sintéticas, cabo curto de madeira'),
  ('KIT-INF3', 17, 'Massa de modelar, 12 cores', 2, 'conj', 'Conjunto com 12 cores, mín. 180 g, atóxica'),
  ('KIT-INF3', 18, 'Massa de EVA para modelar, 5 cores', 1, 'un', '5 cores, 50 g no total (10 g por cor), atóxica'),
  ('KIT-INF3', 19, 'Slime (geleca), 2 potes', 1, 'kit', 'Kit com 2 potes de 110 a 155 g, cores variadas'),
  ('KIT-INF3', 20, 'Pasta escolar polionda A3, azul', 1, 'un', 'A3, lombo de 25 a 35 mm, cor azul'),
  ('KIT-INF4', 1, 'Apontador com depósito', 2, 'un', 'Furo de 8 mm, lâmina inox, depósito plástico'),
  ('KIT-INF4', 2, 'Borracha branca nº 40', 6, 'un', 'Macia, de 30 x 20 x 8 mm a 33 x 23 x 10 mm'),
  ('KIT-INF4', 3, 'Cola branca líquida, 90 g', 3, 'un', 'PVA, 90 a 110 g, tampa de rosca, ensacada individualmente'),
  ('KIT-INF4', 4, 'Cola colorida, 6 cores', 1, 'cx', 'Caixa com 6 potes de mín. 23 g, efeito relevo, lavável'),
  ('KIT-INF4', 5, 'Cola colorida com glitter, 6 cores', 1, 'cx', 'Caixa com 6 potes de mín. 23 g, efeito relevo, lavável'),
  ('KIT-INF4', 6, 'Tesoura escolar sem ponta', 1, 'un', 'Inox, ponta arredondada, 120 a 140 mm'),
  ('KIT-INF4', 7, 'Caderno de desenho espiral, 50 folhas', 2, 'un', 'Capa dura, sem margem, mín. 50 folhas de 150 g/m², mín. 297 x 210 mm'),
  ('KIT-INF4', 8, 'Caneta hidrográfica jumbo, 12 cores', 2, 'emb', 'Big/jumbo, 12 cores, mín. 120 mm, traço de 1 a 4 mm, lavável, tampa antiasfixiante'),
  ('KIT-INF4', 9, 'Caneta hidrográfica tons de pele, 12 cores', 2, 'estojo', 'Estojo com 12 tons de pele, traço de 1 a 3 mm, lavável'),
  ('KIT-INF4', 10, 'Giz de cera jumbo, 12 cores', 1, 'estojo', 'Estojo com 12 cores, tipo estaca, mín. 9 cm, mín. 95 g'),
  ('KIT-INF4', 11, 'Lápis de cor jumbo, 12 cores', 3, 'cx', 'Caixa com 12, triangular, mín. 120 mm, com apontador'),
  ('KIT-INF4', 12, 'Lápis grafite jumbo, conjunto de 3 com apontador', 6, 'conj', 'Conjunto com 3 lápis triangulares (mín. 120 mm) e 1 apontador'),
  ('KIT-INF4', 13, 'Lápis de cor tons de pele, 6 a 12 cores', 2, 'cx', 'Caixa com 6 a 12 tons de pele, grafite de 3 a 6 mm'),
  ('KIT-INF4', 14, 'Pasta escolar polionda A3, azul', 1, 'un', 'A3, lombo de 25 a 35 mm, cor azul'),
  ('KIT-INF4', 15, 'Pincel chato nº 4', 1, 'un', 'Cerdas sintéticas macias, cabo longo de madeira'),
  ('KIT-INF4', 16, 'Pincel chato nº 24', 1, 'un', 'Cerdas sintéticas macias, cabo longo de madeira'),
  ('KIT-INF4', 17, 'Pincel chato nº 18', 1, 'un', 'Cerdas sintéticas macias, cabo longo de madeira'),
  ('KIT-INF4', 18, 'Régua geométrica', 1, 'un', 'Poliestireno, escala em cm e mm, mín. 2 mm x 90 mm x 22 cm'),
  ('KIT-INF4', 19, 'Régua 30 cm cristal', 1, 'un', 'Poliestireno cristal, escala em mm, mín. 310 x 35 x 3 mm'),
  ('KIT-INF4', 20, 'Slime (geleca), 2 potes', 1, 'kit', 'Kit com 2 potes de 110 a 155 g, cores variadas'),
  ('KIT-INF4', 21, 'Massa de modelar, 12 cores', 4, 'conj', 'Conjunto com 12 cores, mín. 180 g, atóxica'),
  ('KIT-INF4', 22, 'Massa de EVA para modelar, 5 cores', 2, 'un', '5 cores, 50 g no total (10 g por cor), atóxica'),
  ('KIT-INF4', 23, 'Bloco de desenho A3, 20 folhas', 1, 'un', '297 x 420 mm, 20 folhas lisas brancas de 140 a 180 g/m²'),
  ('KIT-INF5', 1, 'Apontador com depósito', 2, 'un', 'Furo de 8 mm, lâmina inox, depósito plástico'),
  ('KIT-INF5', 2, 'Borracha branca nº 40', 6, 'un', 'Macia, de 30 x 20 x 8 mm a 33 x 23 x 10 mm'),
  ('KIT-INF5', 3, 'Caderno de desenho espiral, 50 folhas', 2, 'un', 'Capa dura, sem margem, mín. 50 folhas de 150 g/m², mín. 297 x 210 mm'),
  ('KIT-INF5', 4, 'Caneta hidrográfica jumbo, 12 cores', 2, 'emb', 'Big/jumbo, 12 cores, mín. 120 mm, traço de 1 a 4 mm, lavável, tampa antiasfixiante'),
  ('KIT-INF5', 5, 'Cola branca líquida, 90 g', 3, 'un', 'PVA, 90 a 110 g, tampa de rosca, ensacada individualmente'),
  ('KIT-INF5', 6, 'Cola colorida, 6 cores', 1, 'cx', 'Caixa com 6 potes de mín. 23 g, efeito relevo, lavável'),
  ('KIT-INF5', 7, 'Cola colorida com glitter, 6 cores', 1, 'cx', 'Caixa com 6 potes de mín. 23 g, efeito relevo, lavável'),
  ('KIT-INF5', 8, 'Giz de cera jumbo, 12 cores', 1, 'estojo', 'Estojo com 12 cores, tipo estaca, mín. 9 cm, mín. 95 g'),
  ('KIT-INF5', 9, 'Lápis de cor jumbo, 12 cores', 3, 'cx', 'Caixa com 12, triangular, mín. 120 mm, com apontador'),
  ('KIT-INF5', 10, 'Lápis grafite HB nº 2', 3, 'un', 'Triangular ou sextavado, apontado'),
  ('KIT-INF5', 11, 'Lápis grafite jumbo, conjunto de 3 com apontador', 6, 'conj', 'Conjunto com 3 lápis triangulares (mín. 120 mm) e 1 apontador'),
  ('KIT-INF5', 12, 'Massa de modelar, 12 cores', 4, 'conj', 'Conjunto com 12 cores, mín. 180 g, atóxica'),
  ('KIT-INF5', 13, 'Massa de EVA para modelar, 5 cores', 2, 'un', '5 cores, 50 g no total (10 g por cor), atóxica'),
  ('KIT-INF5', 14, 'Pasta escolar polionda A3, azul', 1, 'un', 'A3, lombo de 25 a 35 mm, cor azul'),
  ('KIT-INF5', 15, 'Pincel chato nº 4', 1, 'un', 'Cerdas sintéticas macias, cabo longo de madeira'),
  ('KIT-INF5', 16, 'Pincel chato nº 24', 1, 'un', 'Cerdas sintéticas macias, cabo longo de madeira'),
  ('KIT-INF5', 17, 'Régua 30 cm cristal', 1, 'un', 'Poliestireno cristal, escala em mm, mín. 310 x 35 x 3 mm'),
  ('KIT-INF5', 18, 'Tesoura escolar sem ponta', 1, 'un', 'Inox, ponta arredondada, 120 a 140 mm'),
  ('KIT-INF5', 19, 'Pincel chato nº 18', 1, 'un', 'Cerdas sintéticas macias, cabo longo de madeira'),
  ('KIT-INF5', 20, 'Caderno de linguagem pauta larga, 48 folhas', 1, 'un', 'Brochurão 1 matéria, pauta de 14 mm, capa dura, mín. 48 folhas, mín. 200 x 275 mm'),
  ('KIT-INF5', 21, 'Lápis de cor tons de pele, 6 a 12 cores', 2, 'cx', 'Caixa com 6 a 12 tons de pele, grafite de 3 a 6 mm'),
  ('KIT-INF5', 22, 'Slime (geleca), 2 potes', 1, 'kit', 'Kit com 2 potes de 110 a 155 g, cores variadas'),
  ('KIT-INF5', 23, 'Régua geométrica', 1, 'un', 'Poliestireno, escala em cm e mm, mín. 2 mm x 90 mm x 22 cm'),
  ('KIT-INF5', 24, 'Caneta hidrográfica tons de pele, 12 cores', 2, 'estojo', 'Estojo com 12 tons de pele, traço de 1 a 3 mm, lavável'),
  ('KIT-INF5', 25, 'Bloco de desenho A3, 20 folhas', 1, 'un', '297 x 420 mm, 20 folhas lisas brancas de 140 a 180 g/m²'),
  ('KIT-EF1', 1, 'Apontador com depósito', 2, 'un', 'Furo de 8 mm, lâmina inox, depósito plástico'),
  ('KIT-EF1', 2, 'Borracha branca nº 20', 4, 'un', 'Macia, de 40 x 27 x 8 mm a 43 x 30 x 11 mm'),
  ('KIT-EF1', 3, 'Caderno de cartografia espiral, 96 folhas', 1, 'un', 'Margem milimetrada, capa dura, mín. 96 folhas de 75 g/m², mín. 275 x 200 mm'),
  ('KIT-EF1', 4, 'Caderno de linguagem brochurão, 48 folhas', 2, 'un', '1 matéria, pautado, capa dura, mín. 48 folhas de 63 g/m², mín. 200 x 275 mm'),
  ('KIT-EF1', 5, 'Caderno de linguagem brochurão, 96 folhas', 3, 'un', '1 matéria, pautado, capa dura, mín. 96 folhas de 63 g/m², mín. 200 x 275 mm'),
  ('KIT-EF1', 6, 'Caderno quadriculado ¼, 48 folhas', 1, 'un', 'Brochura pequena, quadrícula de 10 x 10 mm, capa flexível, mín. 48 folhas'),
  ('KIT-EF1', 7, 'Caneta hidrográfica, 12 cores', 1, 'conj', 'Conjunto com 12 cores, ponta protegida (vaivém), traço de 1 a 3 mm, lavável'),
  ('KIT-EF1', 8, 'Cola branca líquida, 90 g', 3, 'un', 'PVA, 90 a 110 g, tampa de rosca, ensacada individualmente'),
  ('KIT-EF1', 9, 'Giz de cera, 12 cores', 1, 'estojo', 'Estojo com 12 cores, tipo estaca, mín. 10 cm, mín. 48 g'),
  ('KIT-EF1', 10, 'Lápis de cor grande, 12 cores', 2, 'cx', 'Caixa com 12, triangular ou sextavado, mina mín. 3 mm'),
  ('KIT-EF1', 11, 'Lápis de cor jumbo, 12 cores', 1, 'cx', 'Caixa com 12, triangular, mín. 120 mm, com apontador'),
  ('KIT-EF1', 12, 'Lápis grafite HB nº 2', 7, 'un', 'Triangular ou sextavado, apontado'),
  ('KIT-EF1', 13, 'Lápis grafite jumbo, conjunto de 3 com apontador', 1, 'conj', 'Conjunto com 3 lápis triangulares (mín. 120 mm) e 1 apontador'),
  ('KIT-EF1', 14, 'Massa de modelar, 12 cores', 1, 'conj', 'Conjunto com 12 cores, mín. 180 g, atóxica'),
  ('KIT-EF1', 15, 'Massa de EVA para modelar, 5 cores', 1, 'un', '5 cores, 50 g no total (10 g por cor), atóxica'),
  ('KIT-EF1', 16, 'Pasta com aba e elástico ofício, azul', 1, 'un', 'Polipropileno, 335 x 235 mm, cor azul'),
  ('KIT-EF1', 17, 'Régua 30 cm cristal', 2, 'un', 'Poliestireno cristal, escala em mm, mín. 310 x 35 x 3 mm'),
  ('KIT-EF1', 18, 'Tesoura escolar sem ponta', 2, 'un', 'Inox, ponta arredondada, 120 a 140 mm'),
  ('KIT-EF2', 1, 'Apontador com depósito', 2, 'un', 'Furo de 8 mm, lâmina inox, depósito plástico'),
  ('KIT-EF2', 2, 'Borracha branca nº 20', 6, 'un', 'Macia, de 40 x 27 x 8 mm a 43 x 30 x 11 mm'),
  ('KIT-EF2', 3, 'Caderno de cartografia espiral, 96 folhas', 1, 'un', 'Margem milimetrada, capa dura, mín. 96 folhas de 75 g/m², mín. 275 x 200 mm'),
  ('KIT-EF2', 4, 'Caderno de linguagem brochurão, 48 folhas', 2, 'un', '1 matéria, pautado, capa dura, mín. 48 folhas de 63 g/m², mín. 200 x 275 mm'),
  ('KIT-EF2', 5, 'Caderno de linguagem brochurão, 96 folhas', 3, 'un', '1 matéria, pautado, capa dura, mín. 96 folhas de 63 g/m², mín. 200 x 275 mm'),
  ('KIT-EF2', 6, 'Caderno quadriculado ¼, 48 folhas', 1, 'un', 'Brochura pequena, quadrícula de 10 x 10 mm, capa flexível, mín. 48 folhas'),
  ('KIT-EF2', 7, 'Caneta hidrográfica, 12 cores', 1, 'conj', 'Conjunto com 12 cores, ponta protegida (vaivém), traço de 1 a 3 mm, lavável'),
  ('KIT-EF2', 8, 'Cola branca líquida, 90 g', 3, 'un', 'PVA, 90 a 110 g, tampa de rosca, ensacada individualmente'),
  ('KIT-EF2', 9, 'Giz de cera, 12 cores', 1, 'estojo', 'Estojo com 12 cores, tipo estaca, mín. 10 cm, mín. 48 g'),
  ('KIT-EF2', 10, 'Lápis de cor grande, 12 cores', 3, 'cx', 'Caixa com 12, triangular ou sextavado, mina mín. 3 mm'),
  ('KIT-EF2', 11, 'Lápis grafite HB nº 2', 8, 'un', 'Triangular ou sextavado, apontado'),
  ('KIT-EF2', 12, 'Massa de modelar, 12 cores', 1, 'conj', 'Conjunto com 12 cores, mín. 180 g, atóxica'),
  ('KIT-EF2', 13, 'Pasta com aba e elástico ofício, azul', 1, 'un', 'Polipropileno, 335 x 235 mm, cor azul'),
  ('KIT-EF2', 14, 'Régua 30 cm cristal', 2, 'un', 'Poliestireno cristal, escala em mm, mín. 310 x 35 x 3 mm'),
  ('KIT-EF2', 15, 'Tesoura escolar sem ponta', 2, 'un', 'Inox, ponta arredondada, 120 a 140 mm'),
  ('KIT-EF2', 16, 'Caderno de caligrafia ¼, 40 folhas', 1, 'un', 'Brochura de 20 x 14 cm, pautado, mín. 40 folhas, 2 grampos'),
  ('KIT-EF2', 17, 'Massa de EVA para modelar, 5 cores', 1, 'un', '5 cores, 50 g no total (10 g por cor), atóxica'),
  ('KIT-EF34', 1, 'Apontador com depósito', 2, 'un', 'Furo de 8 mm, lâmina inox, depósito plástico'),
  ('KIT-EF34', 2, 'Borracha branca nº 20', 6, 'un', 'Macia, de 40 x 27 x 8 mm a 43 x 30 x 11 mm'),
  ('KIT-EF34', 3, 'Caderno de caligrafia ¼, 40 folhas', 1, 'un', 'Brochura de 20 x 14 cm, pautado, mín. 40 folhas, 2 grampos'),
  ('KIT-EF34', 4, 'Caderno de cartografia espiral, 96 folhas', 1, 'un', 'Margem milimetrada, capa dura, mín. 96 folhas de 75 g/m², mín. 275 x 200 mm'),
  ('KIT-EF34', 5, 'Caderno de linguagem brochurão, 48 folhas', 3, 'un', '1 matéria, pautado, capa dura, mín. 48 folhas de 63 g/m², mín. 200 x 275 mm'),
  ('KIT-EF34', 6, 'Caderno de linguagem brochurão, 96 folhas', 4, 'un', '1 matéria, pautado, capa dura, mín. 96 folhas de 63 g/m², mín. 200 x 275 mm'),
  ('KIT-EF34', 7, 'Caderno quadriculado ¼, 48 folhas', 1, 'un', 'Brochura pequena, quadrícula de 10 x 10 mm, capa flexível, mín. 48 folhas'),
  ('KIT-EF34', 8, 'Caneta hidrográfica, 12 cores', 1, 'conj', 'Conjunto com 12 cores, ponta protegida (vaivém), traço de 1 a 3 mm, lavável'),
  ('KIT-EF34', 9, 'Marca-texto, kit com 2 (amarelo e laranja)', 1, 'kit', '1 amarela e 1 laranja, ponta chanfrada, tinta fluorescente'),
  ('KIT-EF34', 10, 'Cola branca líquida, 90 g', 3, 'un', 'PVA, 90 a 110 g, tampa de rosca, ensacada individualmente'),
  ('KIT-EF34', 11, 'Lápis de cor grande, 12 cores', 2, 'cx', 'Caixa com 12, triangular ou sextavado, mina mín. 3 mm'),
  ('KIT-EF34', 12, 'Lápis grafite HB nº 2', 8, 'un', 'Triangular ou sextavado, apontado'),
  ('KIT-EF34', 13, 'Pasta com aba e elástico ofício, azul', 1, 'un', 'Polipropileno, 335 x 235 mm, cor azul'),
  ('KIT-EF34', 14, 'Régua 30 cm cristal', 2, 'un', 'Poliestireno cristal, escala em mm, mín. 310 x 35 x 3 mm'),
  ('KIT-EF34', 15, 'Régua geométrica', 1, 'un', 'Poliestireno, escala em cm e mm, mín. 2 mm x 90 mm x 22 cm'),
  ('KIT-EF34', 16, 'Tesoura escolar sem ponta', 2, 'un', 'Inox, ponta arredondada, 120 a 140 mm'),
  ('KIT-EF34', 17, 'Massa de EVA para modelar, 5 cores', 1, 'un', '5 cores, 50 g no total (10 g por cor), atóxica'),
  ('KIT-EF5', 1, 'Apontador com depósito', 2, 'un', 'Furo de 8 mm, lâmina inox, depósito plástico'),
  ('KIT-EF5', 2, 'Borracha branca nº 20', 6, 'un', 'Macia, de 40 x 27 x 8 mm a 43 x 30 x 11 mm'),
  ('KIT-EF5', 3, 'Caderno de cartografia espiral, 96 folhas', 1, 'un', 'Margem milimetrada, capa dura, mín. 96 folhas de 75 g/m², mín. 275 x 200 mm'),
  ('KIT-EF5', 4, 'Caderno de linguagem brochurão, 48 folhas', 3, 'un', '1 matéria, pautado, capa dura, mín. 48 folhas de 63 g/m², mín. 200 x 275 mm'),
  ('KIT-EF5', 5, 'Caderno de linguagem brochurão, 96 folhas', 4, 'un', '1 matéria, pautado, capa dura, mín. 96 folhas de 63 g/m², mín. 200 x 275 mm'),
  ('KIT-EF5', 6, 'Caderno quadriculado ¼, 48 folhas', 1, 'un', 'Brochura pequena, quadrícula de 10 x 10 mm, capa flexível, mín. 48 folhas'),
  ('KIT-EF5', 7, 'Canetas esferográficas, kit com 4', 1, 'kit', '2 azuis, 1 vermelha e 1 preta, ponta 1,0 mm, corpo transparente'),
  ('KIT-EF5', 8, 'Marca-texto, kit com 2 (amarelo e laranja)', 1, 'kit', '1 amarela e 1 laranja, ponta chanfrada, tinta fluorescente'),
  ('KIT-EF5', 9, 'Cola branca líquida, 90 g', 3, 'un', 'PVA, 90 a 110 g, tampa de rosca, ensacada individualmente'),
  ('KIT-EF5', 10, 'Lápis de cor grande, 12 cores', 2, 'cx', 'Caixa com 12, triangular ou sextavado, mina mín. 3 mm'),
  ('KIT-EF5', 11, 'Lápis grafite HB nº 2', 8, 'un', 'Triangular ou sextavado, apontado'),
  ('KIT-EF5', 12, 'Pasta com aba e elástico ofício, azul', 1, 'un', 'Polipropileno, 335 x 235 mm, cor azul'),
  ('KIT-EF5', 13, 'Régua 30 cm cristal', 2, 'un', 'Poliestireno cristal, escala em mm, mín. 310 x 35 x 3 mm'),
  ('KIT-EF5', 14, 'Régua geométrica', 1, 'un', 'Poliestireno, escala em cm e mm, mín. 2 mm x 90 mm x 22 cm'),
  ('KIT-EF5', 15, 'Tesoura escolar sem ponta', 2, 'un', 'Inox, ponta arredondada, 120 a 140 mm'),
  ('KIT-EF5', 16, 'Caneta hidrográfica, 12 cores', 1, 'conj', 'Conjunto com 12 cores, ponta protegida (vaivém), traço de 1 a 3 mm, lavável'),
  ('KIT-EF5', 17, 'Massa de EVA para modelar, 5 cores', 1, 'un', '5 cores, 50 g no total (10 g por cor), atóxica'),
  ('KIT-EJA', 1, 'Apontador com depósito', 2, 'un', 'Furo de 8 mm, lâmina inox, depósito plástico'),
  ('KIT-EJA', 2, 'Borracha branca nº 20', 4, 'un', 'Macia, de 40 x 27 x 8 mm a 43 x 30 x 11 mm'),
  ('KIT-EJA', 3, 'Caderno de caligrafia ¼, 40 folhas', 1, 'un', 'Brochura de 20 x 14 cm, pautado, mín. 40 folhas, 2 grampos'),
  ('KIT-EJA', 4, 'Caderno de linguagem brochurão, 48 folhas', 3, 'un', '1 matéria, pautado, capa dura, mín. 48 folhas de 63 g/m², mín. 200 x 275 mm'),
  ('KIT-EJA', 5, 'Caderno de linguagem brochurão, 96 folhas', 2, 'un', '1 matéria, pautado, capa dura, mín. 96 folhas de 63 g/m², mín. 200 x 275 mm'),
  ('KIT-EJA', 6, 'Canetas esferográficas, kit com 4', 1, 'kit', '2 azuis, 1 vermelha e 1 preta, ponta 1,0 mm, corpo transparente'),
  ('KIT-EJA', 7, 'Marca-texto, kit com 2 (amarelo e laranja)', 1, 'kit', '1 amarela e 1 laranja, ponta chanfrada, tinta fluorescente'),
  ('KIT-EJA', 8, 'Cola branca líquida, 90 g', 2, 'un', 'PVA, 90 a 110 g, tampa de rosca, ensacada individualmente'),
  ('KIT-EJA', 9, 'Lápis de cor grande, 12 cores', 2, 'cx', 'Caixa com 12, triangular ou sextavado, mina mín. 3 mm'),
  ('KIT-EJA', 10, 'Lápis grafite HB nº 2', 8, 'un', 'Triangular ou sextavado, apontado'),
  ('KIT-EJA', 11, 'Régua 30 cm cristal', 1, 'un', 'Poliestireno cristal, escala em mm, mín. 310 x 35 x 3 mm'),
  ('KIT-EJA', 12, 'Régua geométrica', 1, 'un', 'Poliestireno, escala em cm e mm, mín. 2 mm x 90 mm x 22 cm'),
  ('KIT-EJA', 13, 'Tesoura multiuso', 1, 'un', 'Cabo de polipropileno, lâmina inox, 14 a 17 cm'),
  ('KIT-EJA', 14, 'Pasta com aba e elástico ofício, preta', 2, 'un', 'Polipropileno, 335 x 235 mm, cor preta'),
  ('KIT-AJE1', 1, 'Apontador com depósito', 2, 'un', 'Furo de 8 mm, lâmina inox, depósito plástico'),
  ('KIT-AJE1', 2, 'Bloco de desenho A3, 20 folhas', 1, 'un', '297 x 420 mm, 20 folhas lisas brancas de 140 a 180 g/m²'),
  ('KIT-AJE1', 3, 'Borracha branca nº 40', 3, 'un', 'Macia, de 30 x 20 x 8 mm a 33 x 23 x 10 mm'),
  ('KIT-AJE1', 4, 'Caderno de cartografia espiral, 96 folhas', 1, 'un', 'Margem milimetrada, capa dura, mín. 96 folhas de 75 g/m², mín. 275 x 200 mm'),
  ('KIT-AJE1', 5, 'Caderno de linguagem brochurão, 48 folhas', 1, 'un', '1 matéria, pautado, capa dura, mín. 48 folhas de 63 g/m², mín. 200 x 275 mm'),
  ('KIT-AJE1', 6, 'Caderno de linguagem brochurão, 96 folhas', 1, 'un', '1 matéria, pautado, capa dura, mín. 96 folhas de 63 g/m², mín. 200 x 275 mm'),
  ('KIT-AJE1', 7, 'Cola em bastão, 10 g', 1, 'un', '9 a 10 g, lavável, atóxica'),
  ('KIT-AJE1', 8, 'Cola branca líquida, 90 g', 2, 'un', 'PVA, 90 a 110 g, tampa de rosca, ensacada individualmente'),
  ('KIT-AJE1', 9, 'Giz de cera, 12 cores', 1, 'estojo', 'Estojo com 12 cores, tipo estaca, mín. 10 cm, mín. 48 g'),
  ('KIT-AJE1', 10, 'Lápis de cor grande, 12 cores', 1, 'cx', 'Caixa com 12, triangular ou sextavado, mina mín. 3 mm'),
  ('KIT-AJE1', 11, 'Lápis de cor jumbo, 12 cores', 1, 'cx', 'Caixa com 12, triangular, mín. 120 mm, com apontador'),
  ('KIT-AJE1', 12, 'Lápis grafite HB nº 2', 4, 'un', 'Triangular ou sextavado, apontado'),
  ('KIT-AJE1', 13, 'Lápis grafite jumbo, conjunto de 3 com apontador', 1, 'conj', 'Conjunto com 3 lápis triangulares (mín. 120 mm) e 1 apontador'),
  ('KIT-AJE1', 14, 'Massa de modelar, 12 cores', 1, 'conj', 'Conjunto com 12 cores, mín. 180 g, atóxica'),
  ('KIT-AJE1', 15, 'Régua 30 cm cristal', 1, 'un', 'Poliestireno cristal, escala em mm, mín. 310 x 35 x 3 mm'),
  ('KIT-AJE1', 16, 'Slime (geleca), 2 potes', 1, 'kit', 'Kit com 2 potes de 110 a 155 g, cores variadas'),
  ('KIT-AJE1', 17, 'Tesoura escolar sem ponta', 1, 'un', 'Inox, ponta arredondada, 120 a 140 mm'),
  ('KIT-AJE1', 18, 'Massa de EVA para modelar, 5 cores', 1, 'un', '5 cores, 50 g no total (10 g por cor), atóxica'),
  ('KIT-AJE25', 1, 'Apontador com depósito', 2, 'un', 'Furo de 8 mm, lâmina inox, depósito plástico'),
  ('KIT-AJE25', 2, 'Bloco de desenho A3, 20 folhas', 1, 'un', '297 x 420 mm, 20 folhas lisas brancas de 140 a 180 g/m²'),
  ('KIT-AJE25', 3, 'Borracha branca nº 40', 4, 'un', 'Macia, de 30 x 20 x 8 mm a 33 x 23 x 10 mm'),
  ('KIT-AJE25', 4, 'Caderno de cartografia espiral, 96 folhas', 1, 'un', 'Margem milimetrada, capa dura, mín. 96 folhas de 75 g/m², mín. 275 x 200 mm'),
  ('KIT-AJE25', 5, 'Caderno de linguagem brochurão, 48 folhas', 1, 'un', '1 matéria, pautado, capa dura, mín. 48 folhas de 63 g/m², mín. 200 x 275 mm'),
  ('KIT-AJE25', 6, 'Caderno de linguagem brochurão, 96 folhas', 1, 'un', '1 matéria, pautado, capa dura, mín. 96 folhas de 63 g/m², mín. 200 x 275 mm'),
  ('KIT-AJE25', 7, 'Caderno quadriculado ¼, 48 folhas', 1, 'un', 'Brochura pequena, quadrícula de 10 x 10 mm, capa flexível, mín. 48 folhas'),
  ('KIT-AJE25', 8, 'Cola em bastão, 10 g', 2, 'un', '9 a 10 g, lavável, atóxica'),
  ('KIT-AJE25', 9, 'Cola branca líquida, 90 g', 2, 'un', 'PVA, 90 a 110 g, tampa de rosca, ensacada individualmente'),
  ('KIT-AJE25', 10, 'Giz de cera, 12 cores', 1, 'estojo', 'Estojo com 12 cores, tipo estaca, mín. 10 cm, mín. 48 g'),
  ('KIT-AJE25', 11, 'Lápis de cor grande, 12 cores', 2, 'cx', 'Caixa com 12, triangular ou sextavado, mina mín. 3 mm'),
  ('KIT-AJE25', 12, 'Lápis grafite HB nº 2', 4, 'un', 'Triangular ou sextavado, apontado'),
  ('KIT-AJE25', 13, 'Massa de modelar, 12 cores', 1, 'conj', 'Conjunto com 12 cores, mín. 180 g, atóxica'),
  ('KIT-AJE25', 14, 'Régua 30 cm cristal', 2, 'un', 'Poliestireno cristal, escala em mm, mín. 310 x 35 x 3 mm'),
  ('KIT-AJE25', 15, 'Slime (geleca), 2 potes', 1, 'kit', 'Kit com 2 potes de 110 a 155 g, cores variadas'),
  ('KIT-AJE25', 16, 'Tesoura escolar sem ponta', 1, 'un', 'Inox, ponta arredondada, 120 a 140 mm'),
  ('KIT-AJE25', 17, 'Massa de EVA para modelar, 5 cores', 1, 'un', '5 cores, 50 g no total (10 g por cor), atóxica');

-- 3. Regras -----------------------------------------------------------------------------------------------------------------------------
create or replace function iara.uk_param(p_chave text) returns jsonb
language sql stable security definer set search_path = iara, public
as $$ select valor from iara.uk_parametros where chave = p_chave $$;

create or replace function iara.uk_etapa_rotulo(p text) returns text
language sql immutable
as $$
  select case
    when p is null then null
    when p ~ '^INF[0-5]$' then 'Infantil ' || substr(p, 4)
    when p ~ '^EF[1-5]$' then substr(p, 3) || 'º ano'
    when p = 'EJA' then 'EJA'
    else p end
$$;

-- data de corte da idade (a mesma da matrícula: 31/03, ou o parâmetro age_cutoff)
create or replace function iara.uk_corte(p_ano integer) returns date
language sql stable security definer set search_path = iara, public
as $$
  select make_date(p_ano, coalesce(nullif(split_part(iara.setting('age_cutoff'), '-', 1), '')::int, 3),
                          coalesce(nullif(split_part(iara.setting('age_cutoff'), '-', 2), '')::int, 31))
$$;

-- etapa do aluno no ano: 1º ao 5º ano e EJA pela turma (o ano seguinte avança uma série; quem sai do 5º ano deixa a rede municipal);
-- educação infantil pela idade na data de corte (Infantil 0 a 5); quem completa 6 anos vai para o 1º ano
create or replace function iara.uk_etapa_aluno(p_student uuid, p_ano integer) returns text
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_grade text;
  v_birth date;
  v_ano_mat integer;
  v_meses integer;
  v_n integer;
begin
  select g.code, s.birth_date, e.school_year into v_grade, v_birth, v_ano_mat
  from iara.students s
  join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
  join iara.classes c on c.id = e.class_id
  join iara.grade_levels g on g.id = c.grade_level_id
  where s.id = p_student
  order by e.school_year desc limit 1;
  if v_grade is null then return null; end if;
  if v_grade = 'EJA_AI' then return 'EJA'; end if;
  if v_grade ~ '^EF[1-5]$' then
    v_n := substr(v_grade, 3)::int + (p_ano - v_ano_mat);
    return case when v_n between 1 and 5 then 'EF' || v_n end;
  end if;
  v_meses := (extract(year from age(iara.uk_corte(p_ano), v_birth)) * 12 + extract(month from age(iara.uk_corte(p_ano), v_birth)))::int;
  if v_meses >= 72 then return 'EF1'; end if;
  return 'INF' || greatest(0, least(5, v_meses / 12));
end $$;

-- a mesma regra para a rede inteira, numa consulta só (a geração da campanha e a rotina de hora em hora usam esta)
create or replace function iara.uk_etapas(p_ano integer) returns table (student_id uuid, unit_id integer, etapa text, ampliacao boolean)
language sql stable security definer set search_path = iara, public
as $$
  with corte as (select iara.uk_corte(p_ano) d),
  m as (
    select distinct on (e.student_id) e.student_id, e.unit_id, e.school_year, g.code, s.birth_date, c.shift
    from iara.enrollments e join iara.students s on s.id = e.student_id
    join iara.classes c on c.id = e.class_id join iara.grade_levels g on g.id = c.grade_level_id
    where e.status = 'ACTIVE'
    order by e.student_id, e.school_year desc)
  select m.student_id, m.unit_id,
         case when m.code = 'EJA_AI' then 'EJA'
              when m.code ~ '^EF[1-5]$' then case when substr(m.code, 3)::int + (p_ano - m.school_year) between 1 and 5 then 'EF' || (substr(m.code, 3)::int + (p_ano - m.school_year)) end
              when x.meses >= 72 then 'EF1'
              else 'INF' || greatest(0, least(5, x.meses / 12)) end,
         (m.shift = 'INTEGRAL' and m.school_year = p_ano) or exists (select 1 from iara.ampliacao_jornada a where a.student_id = m.student_id and a.ano = p_ano and a.ativo)
  from m cross join corte
  cross join lateral (select (extract(year from age(corte.d, m.birth_date)) * 12 + extract(month from age(corte.d, m.birth_date)))::int meses) x
$$;

create or replace function iara.uk_ampliacao(p_student uuid, p_ano integer) returns boolean
language sql stable security definer set search_path = iara, public
as $$
  select exists (select 1 from iara.ampliacao_jornada a where a.student_id = p_student and a.ano = p_ano and a.ativo)
      or exists (select 1 from iara.enrollments e join iara.classes c on c.id = e.class_id
                 where e.student_id = p_student and e.status = 'ACTIVE' and e.school_year = p_ano and c.shift = 'INTEGRAL')
$$;

-- tamanho sugerido pela idade (só uma sugestão para a família e a estimativa da compra; quem decide é a família)
create or replace function iara.uk_sugestao_meses(p_meses integer) returns jsonb
language sql immutable
as $$
  select case when p_meses is null then null else jsonb_build_object(
    'superior', r.t, 'inferior', r.t,
    'calcado', case when p_meses < 12 then 17 when p_meses < 24 then 20 when p_meses < 36 then 22 when p_meses < 48 then 24
                    when p_meses < 60 then 26 when p_meses < 72 then 27 when p_meses < 84 then 29 when p_meses < 96 then 30
                    when p_meses < 108 then 31 when p_meses < 120 then 32 when p_meses < 132 then 33 when p_meses < 144 then 34 else 36 end) end
  from (select case when p_meses < 12 then '1' when p_meses < 24 then '2' when p_meses < 48 then '4' when p_meses < 72 then '6'
                    when p_meses < 96 then '8' when p_meses < 120 then '10' when p_meses < 144 then '12' when p_meses < 168 then '14'
                    when p_meses < 216 then 'P' else 'M' end t) r
$$;

create or replace function iara.uk_sugestao(p_student uuid, p_ano integer) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select iara.uk_sugestao_meses((extract(year from age(make_date(p_ano, 2, 15), birth_date)) * 12 + extract(month from age(make_date(p_ano, 2, 15), birth_date)))::int)
  from iara.students where id = p_student
$$;

create or replace function iara.uk_meia(p_calcado integer) returns text
language sql stable security definer set search_path = iara, public
as $$ select tamanho from iara.uk_grades where grade = 'MEIA' and ativo and p_calcado between calcado_min and calcado_max order by ordem limit 1 $$;

-- produto do almoxarifado para a peça e o tamanho: o estoque da SEDUC e das unidades usa o catálogo único
create or replace function iara.uk_produto_codigo(p_item text, p_tamanho text) returns text
language sql immutable as $$ select p_item || coalesce('-T' || upper(regexp_replace(p_tamanho, '[^0-9A-Za-z]+', '', 'g')), '') $$;

-- garante no catálogo do almoxarifado um produto por peça e tamanho da grade, e um por kit
create or replace function iara.uk_produtos_garantir() returns integer
language plpgsql security definer set search_path = iara, public
as $$
declare
  n integer;
begin
  insert into iara.produtos (codigo, nome, categoria, unidade_medida, duravel, is_demo)
  select iara.uk_produto_codigo(i.codigo, g.tamanho), i.nome || ' — tam. ' || g.tamanho, 'UNIFORME',
         case when i.medida in ('MEIA', 'CALCADO') then 'par' else 'peça' end, false, false
  from iara.uk_itens i join iara.uk_grades g on g.grade = case i.medida when 'CALCADO' then 'CALCADO' when 'MEIA' then 'MEIA' else 'ROUPA' end
  where i.tipo = 'UNIFORME'
  union all
  select codigo, nome, 'PEDAGOGICO', 'kit', false, false from iara.uk_itens where tipo = 'KIT'
  on conflict (codigo) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function iara.uk_produto(p_item text, p_tamanho text) returns text
language plpgsql security definer set search_path = iara, public
as $$
declare
  it iara.uk_itens;
  v_cod text := iara.uk_produto_codigo(p_item, p_tamanho);
begin
  if not exists (select 1 from iara.produtos where codigo = v_cod) then
    select * into it from iara.uk_itens where codigo = p_item;
    if it.codigo is null then raise exception 'Item desconhecido: %.', p_item using errcode = '22023'; end if;
    insert into iara.produtos (codigo, nome, categoria, unidade_medida, duravel, is_demo)
    values (v_cod, it.nome || coalesce(' — tam. ' || p_tamanho, ''), case when it.tipo = 'KIT' then 'PEDAGOGICO' else 'UNIFORME' end,
            case when it.tipo = 'KIT' then 'kit' when it.medida in ('MEIA', 'CALCADO') then 'par' else 'peça' end, false, false)
    on conflict (codigo) do nothing;
  end if;
  return v_cod;
end $$;

-- itens de uma necessidade (uniforme pelo tamanho informado; kit pela etapa e pela Ampliação de Jornada); sem tamanho: null
create or replace function iara.uk_itens_json(p_conteudo text, p_etapa text, p_amp boolean, p_sup text, p_inf text, p_calc integer, p_modelo text) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select case when p_etapa is null then '[]'::jsonb
              when p_conteudo = 'UNIFORME' and (p_sup is null or p_inf is null or p_calc is null) then null
              else coalesce(jsonb_agg(jsonb_build_object('item', i.codigo, 'nome', i.nome, 'quantidade', i.quantidade, 'tamanho', z.tam,
                                                         'produto', iara.uk_produto_codigo(i.codigo, z.tam)) order by i.ordem), '[]'::jsonb) end
  from iara.uk_itens i
  cross join lateral (select case i.medida when 'SUPERIOR' then p_sup when 'INFERIOR' then p_inf when 'CALCADO' then p_calc::text
                                           when 'MEIA' then iara.uk_meia(p_calc) end tam) z
  where i.ativo and i.tipo = p_conteudo and p_etapa = any (i.etapas) and (not i.so_ampliacao or coalesce(p_amp, false))
    and (i.modelo is null or i.modelo = p_modelo)
$$;

create or replace function iara.uk_montar_itens(p_conteudo text, p_etapa text, p_ampliacao boolean, t iara.uk_tamanhos) returns jsonb
language sql stable security definer set search_path = iara, public
as $$ select iara.uk_itens_json(p_conteudo, p_etapa, p_ampliacao, t.superior, t.inferior, t.calcado, t.modelo_inferior) $$;

create or replace function iara.uk_codigo(p_student uuid, p_ano integer) returns text
language plpgsql security definer set search_path = iara, public
as $$
declare
  v text;
  i integer := 0;
begin
  select codigo into v from iara.uk_codigos where student_id = p_student and ano = p_ano;
  if v is not null then return v; end if;
  loop
    v := lpad((floor(random() * 1000000))::int::text, 6, '0');
    begin
      insert into iara.uk_codigos (student_id, ano, codigo) values (p_student, p_ano, v);
      return v;
    exception when unique_violation then
      i := i + 1;
      if i > 20 then raise; end if;
    end;
  end loop;
end $$;

create or replace function iara.uk_parentesco(p text) returns text
language sql immutable
as $$
  select case upper(coalesce(p, '')) when 'MAE' then 'Mãe' when 'PAI' then 'Pai' when 'AVO' then 'Avó ou avô' when 'AVOA' then 'Avó' when 'TIA' then 'Tia ou tio'
    when 'TIO' then 'Tio' when 'IRMAO' then 'Irmão ou irmã' when 'IRMA' then 'Irmã' when 'MADRASTA' then 'Madrasta' when 'PADRASTO' then 'Padrasto'
    when 'TUTOR' then 'Tutor(a)' when 'GUARDIAO' then 'Guardião(ã)' when '' then 'Responsável' else initcap(lower(replace(p, '_', ' '))) end
$$;

-- quem pode retirar: responsáveis com permissão de buscar a criança, sem proibição vigente, mais as pessoas autorizadas em Guarda e restrições
create or replace function iara.uk_autorizados(p_student uuid) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select coalesce(jsonb_agg(x order by x ->> 'ordem', x ->> 'nome'), '[]') from (
    select jsonb_build_object('tipo', 'RESPONSAVEL', 'guardian_id', g.id, 'nome', g.full_name, 'parentesco', iara.uk_parentesco(sg.relationship),
             'documento', iara.mascara_doc(g.cpf), 'principal', sg.is_primary, 'ordem', case when sg.is_primary then '0' else '1' end) x
    from iara.student_guardians sg join iara.guardians g on g.id = sg.guardian_id
    where sg.student_id = p_student and sg.end_date is null and sg.can_pick_up
      and not exists (select 1 from iara.guarda_restricoes r where r.student_id = p_student and r.guardian_id = g.id and iara.guarda_ativa(r)
                      and (r.efeito_retirada = 'NAO_PODE' or r.tipo = 'PROIBICAO_RETIRADA'))
    union all
    select jsonb_build_object('tipo', 'AUTORIZADO', 'autorizacao_id', r.id, 'nome', r.pessoa_nome, 'parentesco', 'Pessoa autorizada',
             'documento', null, 'principal', false, 'ordem', '2')
    from iara.guarda_restricoes r
    where r.student_id = p_student and r.tipo = 'AUTORIZACAO_RETIRADA' and r.efeito_retirada = 'PODE' and iara.guarda_ativa(r) and r.pessoa_nome is not null
    union all
    select jsonb_build_object('tipo', 'PROPRIO', 'nome', s.full_name, 'parentesco', 'O(a) próprio(a) estudante (EJA)', 'principal', false, 'ordem', '3')
    from iara.students s where s.id = p_student and iara.uk_etapa_aluno(s.id, iara.school_year()) = 'EJA'
  ) z
$$;

create or replace function iara.uk_responsavel(p_student uuid) returns uuid
language sql stable security definer set search_path = iara, public
as $$
  select sg.guardian_id from iara.student_guardians sg
  where sg.student_id = p_student and sg.end_date is null and coalesce(sg.can_receive_notifications, true)
    and not exists (select 1 from iara.guarda_restricoes r where r.student_id = sg.student_id and r.guardian_id = sg.guardian_id and iara.guarda_ativa(r)
                    and (r.bloquear_portal or r.tipo in ('MEDIDA_PROTETIVA', 'PROIBICAO_CONTATO')))
  order by sg.is_primary desc nulls last, sg.start_date nulls last limit 1
$$;

create or replace function iara.uk_conteudo_rotulo(p text) returns text
language sql immutable as $$ select case p when 'UNIFORME' then 'uniforme' when 'KIT' then 'kit escolar' when 'ADAPTADO' then 'material adaptado' else lower(p) end $$;

-- 4. Avisos e disparo em lotes ----------------------------------------------------------------------------------------------------------
-- cria o aviso (aparece na hora no portal e na IARA) e o coloca na fila do WhatsApp, espaçado pelo intervalo dos lotes
create or replace function iara.uk_aviso_criar(p_student uuid, p_tipo text, p_titulo text, p_texto text, p_ano integer, p_unit integer,
                                               p_necessidades uuid[] default '{}', p_disparo uuid default null) returns uuid
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_id uuid;
  v_int integer := coalesce((iara.uk_param('intervalo_segundos'))::int, 20);
  v_base timestamptz;
begin
  select greatest(now(), coalesce(max(agendado_para), now())) into v_base from iara.uk_avisos where whatsapp_status = 'AGENDADO';
  insert into iara.uk_avisos (student_id, guardian_id, unit_id, ano, tipo, necessidade_ids, disparo_id, titulo, texto, whatsapp_status, agendado_para)
  values (p_student, iara.uk_responsavel(p_student), p_unit, p_ano, p_tipo, coalesce(p_necessidades, '{}'), p_disparo, p_titulo, p_texto,
          'AGENDADO', v_base + make_interval(secs => v_int))
  returning id into v_id;
  return v_id;
end $$;

-- envia os avisos vencidos da fila: um lote por minuto (60 / intervalo), só das 8h às 19h. Portal sempre; WhatsApp pela ponte quando
-- o responsável já tem contato no canal; sem contato, na demonstração fica registrado como simulado
create or replace function iara.uk_envios_processar() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_int integer := greatest(coalesce((iara.uk_param('intervalo_segundos'))::int, 20), 1);
  v_ini integer := coalesce((iara.uk_param('horario_inicio'))::int, 8);
  v_fim integer := coalesce((iara.uk_param('horario_fim'))::int, 19);
  v_hora integer := extract(hour from iara.agora_local());
  a iara.uk_avisos;
  v_notif uuid;
  v_out uuid;
  n integer := 0;
begin
  if v_hora < v_ini or v_hora >= v_fim then
    return jsonb_build_object('fora_do_horario', true);
  end if;
  for a in select * from iara.uk_avisos where whatsapp_status = 'AGENDADO' and agendado_para <= now()
           order by agendado_para limit greatest(60 / v_int, 1) for update skip locked loop
    v_out := null;
    if a.guardian_id is not null then
      insert into iara.notifications (tenant_id, guardian_id, student_id, channel, event_type, title, body, status)
      values (1, a.guardian_id, a.student_id, 'PORTAL', 'UNIFORME_' || a.tipo, a.titulo, a.texto, 'ENVIADA') returning id into v_notif;
      insert into iara.whatsapp_outbox (channel_id, contact_id, telefone_e164, jid, texto, origem, ref_id)
      select w.channel_id, w.id, w.telefone_e164, w.jid, '*' || a.titulo || '*' || E'\n' || a.texto, 'NOTIFICACAO', v_notif
      from iara.whatsapp_contacts w join iara.whatsapp_channels ch on ch.id = w.channel_id
      where w.guardian_id = a.guardian_id and ch.ativo order by w.ultima_em desc limit 1
      returning id into v_out;
    end if;
    update iara.uk_avisos set whatsapp_status = case when v_out is not null then 'ENVIADO' when iara.demo_mode() then 'SIMULADO' else 'SEM_WHATSAPP' end,
           whatsapp_em = now() where id = a.id;
    n := n + 1;
  end loop;
  return jsonb_build_object('enviados', n);
end $$;

-- texto do aviso de retirada (o mesmo no portal, na IARA e no WhatsApp)
create or replace function iara.uk_texto_retirada(p_student uuid, p_ano integer, p_conteudos text[], p_prazo date) returns text
language sql volatile security definer set search_path = iara, public
as $$
  select format('%s de %s: disponível para retirada %s até %s. Código de retirada: %s (ou documento com foto). Pode retirar o responsável ou a pessoa autorizada a buscar a criança no cadastro.',
    initcap(array_to_string(array(select iara.uk_conteudo_rotulo(c) from unnest(p_conteudos) c), ' e ')), split_part(s.full_name, ' ', 1),
    coalesce('no(a) ' || u.short_name, 'na unidade'), to_char(p_prazo, 'DD/MM/YYYY'),
    regexp_replace(iara.uk_codigo(p_student, p_ano), '^(\d{3})(\d{3})$', '\1 \2'))
  from iara.students s
  left join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
  left join iara.education_units u on u.id = e.unit_id
  where s.id = p_student limit 1
$$;

-- libera para retirada (unidade com o material na mão): prazo, código e aviso à família — um aviso por aluno
create or replace function iara.uk_liberar(p_ids uuid[]) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  x record;
  c iara.uk_campanhas;
  v_prazo date;
  n integer := 0;
  a integer := 0;
begin
  for x in select n.student_id, n.ano, n.unit_id, array_agg(n.id) ids, array_agg(distinct n.conteudo) conteudos, min(n.campanha_id::text)::uuid campanha
           from iara.uk_necessidades n where n.id = any (p_ids) and n.situacao = 'AGUARDANDO_MATERIAL'
           group by n.student_id, n.ano, n.unit_id loop
    select * into c from iara.uk_campanhas where id = x.campanha or (x.campanha is null and ano = x.ano) limit 1;
    v_prazo := iara.hoje_local() + coalesce(c.prazo_retirada_dias, 30);
    update iara.uk_necessidades set situacao = 'DISPONIVEL', disponivel_em = now(), prazo_retirada = v_prazo, updated_at = now() where id = any (x.ids);
    perform iara.uk_codigo(x.student_id, x.ano);
    perform iara.uk_aviso_criar(x.student_id, 'RETIRADA', 'Uniforme e kit escolar: pode retirar',
                                iara.uk_texto_retirada(x.student_id, x.ano, x.conteudos, v_prazo), x.ano, x.unit_id, x.ids);
    n := n + cardinality(x.ids);
    a := a + 1;
  end loop;
  return jsonb_build_object('liberadas', n, 'avisos', a);
end $$;

-- 5. Geração das necessidades da campanha (idempotente; roda de hora em hora) --------------------------------------------------------------
-- cria a necessidade anual de quem ainda não tem; depois da separação, quem chega vira “aluno novo”; acompanha mudança de unidade e etapa
create or replace function iara.uk_gerar(p_campanha uuid) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.uk_campanhas;
  v_tipo text;
  n_novas integer := 0;
  n_mov integer := 0;
  n_itens integer := 0;
begin
  select * into c from iara.uk_campanhas where id = p_campanha;
  if c.id is null or c.situacao in ('PLANEJAMENTO', 'ENCERRADA') then return jsonb_build_object('ok', false); end if;
  v_tipo := case when c.gerada_em is not null and c.situacao in ('SEPARACAO', 'ENTREGA') then 'ALUNO_NOVO' else 'ANUAL' end;

  perform iara.uk_produtos_garantir();
  with al as (
    select * from iara.uk_etapas(c.ano)
  ), cont as (
    select al.*, k.conteudo from al
    cross join lateral (values ('UNIFORME'), ('KIT')) k(conteudo)
    where al.etapa is not null
      and (k.conteudo = 'KIT' and c.inclui_kit or k.conteudo = 'UNIFORME' and c.inclui_uniforme and al.etapa <> 'EJA')
  ), ins as (
    insert into iara.uk_necessidades (campanha_id, ano, student_id, unit_id, etapa, ampliacao, tipo, conteudo, itens, situacao, origem, is_demo)
    select c.id, c.ano, cont.student_id, cont.unit_id, cont.etapa, cont.ampliacao, v_tipo, cont.conteudo,
           coalesce(iara.uk_montar_itens(cont.conteudo, cont.etapa, cont.ampliacao, t), '[]'),
           case when cont.conteudo = 'UNIFORME' and t.student_id is null then 'AGUARDANDO_TAMANHO' else 'AGUARDANDO_MATERIAL' end, 'SISTEMA', c.is_demo
    from cont left join iara.uk_tamanhos t on t.student_id = cont.student_id and t.ano = c.ano
    where not exists (select 1 from iara.uk_necessidades n where n.ano = c.ano and n.student_id = cont.student_id and n.conteudo = cont.conteudo
                      and n.tipo in ('ANUAL', 'ALUNO_NOVO') and n.situacao not in ('CANCELADA', 'NEGADA'))
    on conflict do nothing
    returning 1
  )
  select count(*) into n_novas from ins;

  -- rematrícula e transferência: necessidade em aberto acompanha a unidade e a etapa da matrícula ativa
  with mov as (
    update iara.uk_necessidades n set unit_id = e.unit_id, etapa = coalesce(e.etapa, n.etapa), updated_at = now()
    from iara.uk_etapas(c.ano) e
    where n.campanha_id = c.id and e.student_id = n.student_id and n.unit_id is distinct from e.unit_id
      and n.situacao in ('AGUARDANDO_TAMANHO', 'AGUARDANDO_MATERIAL')
    returning 1)
  select count(*) into n_mov from mov;

  -- quem informou o tamanho depois: monta os itens
  with t as (
    update iara.uk_necessidades n set itens = iara.uk_montar_itens('UNIFORME', n.etapa, n.ampliacao, tm), situacao = 'AGUARDANDO_MATERIAL', updated_at = now()
    from iara.uk_tamanhos tm
    where n.campanha_id = c.id and n.conteudo = 'UNIFORME' and n.situacao = 'AGUARDANDO_TAMANHO' and tm.student_id = n.student_id and tm.ano = n.ano
      and iara.uk_montar_itens('UNIFORME', n.etapa, n.ampliacao, tm) is not null
    returning 1)
  select count(*) into n_itens from t;

  update iara.uk_campanhas set gerada_em = coalesce(gerada_em, now()) where id = c.id;
  return jsonb_build_object('ok', true, 'novas', n_novas, 'tipo', v_tipo, 'mudaram_de_unidade', n_mov, 'tamanhos_aplicados', n_itens);
end $$;

-- grava o tamanho (família, unidade ou estimativa) e atualiza as necessidades do uniforme daquele ano
create or replace function iara.uk_tamanho_gravar(p_student uuid, p_ano integer, p jsonb, p_canal text) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  t iara.uk_tamanhos;
  v_etapa text := iara.uk_etapa_aluno(p_student, p_ano);
  v_sup text := nullif(btrim(coalesce(p ->> 'superior', '')), '');
  v_inf text := nullif(btrim(coalesce(p ->> 'inferior', '')), '');
  v_calc integer := nullif(regexp_replace(coalesce(p ->> 'calcado', ''), '\D', '', 'g'), '')::int;
  v_mod text := nullif(p ->> 'modelo', '');
begin
  if v_etapa is null then raise exception 'Não há matrícula ativa para o uniforme de %.', p_ano using errcode = '22023'; end if;
  if v_etapa = 'EJA' then raise exception 'A EJA não recebe uniforme; o kit escolar não depende de tamanho.' using errcode = '22023'; end if;
  if v_sup is null or not exists (select 1 from iara.uk_grades where grade = 'ROUPA' and tamanho = upper(v_sup) and ativo) then
    raise exception 'Escolha o tamanho da parte de cima (camisetas, jaqueta e blusa).' using errcode = '22023'; end if;
  if v_inf is null or not exists (select 1 from iara.uk_grades where grade = 'ROUPA' and tamanho = upper(v_inf) and ativo) then
    raise exception 'Escolha o tamanho da parte de baixo (calça e shorts-saia ou bermuda).' using errcode = '22023'; end if;
  if v_calc is null or not exists (select 1 from iara.uk_grades where grade = 'CALCADO' and tamanho = v_calc::text and ativo) then
    raise exception 'Informe o número do calçado (de 16 a 36).' using errcode = '22023'; end if;
  if v_mod is null or v_mod not in ('SHORTS_SAIA', 'BERMUDA') then
    raise exception 'Escolha o modelo: shorts-saia ou bermuda.' using errcode = '22023'; end if;
  insert into iara.uk_tamanhos (student_id, ano, superior, inferior, calcado, modelo_inferior, canal, guardian_id, informado_por_label, informado_em)
  values (p_student, p_ano, upper(v_sup), upper(v_inf), v_calc, v_mod, p_canal, case when p_canal in ('PORTAL', 'WHATSAPP') then iara.my_guardian() end,
          iara.my_label(), now())
  on conflict (student_id, ano) do update set superior = excluded.superior, inferior = excluded.inferior, calcado = excluded.calcado,
    modelo_inferior = excluded.modelo_inferior, canal = excluded.canal, guardian_id = excluded.guardian_id, informado_por_label = excluded.informado_por_label,
    informado_em = now()
  returning * into t;
  -- necessidade do uniforme ainda não entregue: refaz os itens com o tamanho novo
  update iara.uk_necessidades n set itens = coalesce(iara.uk_montar_itens('UNIFORME', n.etapa, n.ampliacao, t), n.itens),
         situacao = case when n.situacao = 'AGUARDANDO_TAMANHO' then 'AGUARDANDO_MATERIAL' else n.situacao end, updated_at = now()
  where n.student_id = p_student and n.ano = p_ano and n.conteudo = 'UNIFORME' and n.tipo in ('ANUAL', 'ALUNO_NOVO')
    and n.situacao in ('AGUARDANDO_TAMANHO', 'AGUARDANDO_MATERIAL') and n.pedido_id is null;
  perform iara.audit_event('UNIFORME_TAMANHO', 'student', p_student::text, (select unit_id from iara.enrollments where student_id = p_student and status = 'ACTIVE' limit 1),
                           format('Tamanhos do uniforme %s informados (%s): cima %s, baixo %s, calçado %s, %s.', p_ano, lower(p_canal), t.superior, t.inferior, t.calcado,
                                  case t.modelo_inferior when 'SHORTS_SAIA' then 'shorts-saia' else 'bermuda' end));
  return jsonb_build_object('ok', true, 'superior', t.superior, 'inferior', t.inferior, 'calcado', t.calcado, 'meia', iara.uk_meia(t.calcado), 'modelo', t.modelo_inferior);
end $$;

-- 6. JSON ----------------------------------------------------------------------------------------------------------------------------------
create or replace function iara.uk_situacao_rotulo(p text) returns text
language sql immutable
as $$
  select case p when 'AGUARDANDO_TAMANHO' then 'Aguardando o tamanho' when 'AGUARDANDO_DECISAO' then 'Aguardando decisão'
    when 'AGUARDANDO_MATERIAL' then 'Aguardando o material' when 'DISPONIVEL' then 'Pode retirar' when 'RETIRADA' then 'Retirado'
    when 'PARCIAL' then 'Retirado em parte' when 'CANCELADA' then 'Cancelado' when 'NEGADA' then 'Não aprovado' else p end
$$;

create or replace function iara.uk_tipo_rotulo(p text) returns text
language sql immutable
as $$
  select case p when 'ANUAL' then 'Entrega anual' when 'ALUNO_NOVO' then 'Aluno novo' when 'TROCA_TAMANHO' then 'Troca de tamanho'
    when 'REPOSICAO' then 'Reposição' when 'ADAPTADO' then 'Material adaptado' else p end
$$;

create or replace function iara.uk_nec_json(n iara.uk_necessidades, p_familia boolean default false) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('id', n.id, 'ano', n.ano, 'tipo', n.tipo, 'tipo_rotulo', iara.uk_tipo_rotulo(n.tipo), 'conteudo', n.conteudo,
      'etapa', n.etapa, 'etapa_rotulo', iara.uk_etapa_rotulo(n.etapa), 'ampliacao', n.ampliacao, 'itens', n.itens, 'situacao', n.situacao,
      'situacao_rotulo', iara.uk_situacao_rotulo(n.situacao), 'motivo', n.motivo, 'origem', n.origem, 'decisao_motivo', n.decisao_motivo,
      'disponivel_em', n.disponivel_em, 'prazo_retirada', n.prazo_retirada,
      'vencida', n.situacao = 'DISPONIVEL' and n.prazo_retirada < iara.hoje_local(),
      'retirada_em', n.retirada_em, 'retirada_por', n.retirada_por_nome, 'retirada_parentesco', n.retirada_por_parentesco,
      'unidade', (select short_name from iara.education_units where id = n.unit_id), 'unit_id', n.unit_id, 'created_at', n.created_at,
      'codigo', case when n.situacao = 'DISPONIVEL' then (select regexp_replace(codigo, '^(\d{3})(\d{3})$', '\1 \2') from iara.uk_codigos where student_id = n.student_id and ano = n.ano) end,
      'is_demo', n.is_demo)
    || case when p_familia then '{}'::jsonb else jsonb_build_object(
      'solicitante', n.solicitante_label, 'decidido_por', n.decidido_por_label, 'decidido_em', n.decidido_em, 'retirada_documento', n.retirada_documento,
      'codigo_conferido', n.codigo_conferido, 'registrado_por', n.registrado_por_label, 'entregue', n.entregue, 'observacao', n.observacao,
      'pedido', (select numero from iara.pedidos where id = n.pedido_id)) end
$$;

create or replace function iara.uk_aviso_json(a iara.uk_avisos) returns jsonb
language sql stable
as $$
  select jsonb_build_object('id', a.id, 'student_id', a.student_id, 'tipo', a.tipo, 'titulo', a.titulo, 'texto', a.texto, 'enviado_em', a.enviado_em,
    'whatsapp', a.whatsapp_status, 'whatsapp_em', a.whatsapp_em, 'agendado_para', a.agendado_para, 'ciente_em', a.ciente_em, 'ciente_canal', a.ciente_canal,
    'ano', a.ano, 'is_demo', a.is_demo)
$$;

create or replace function iara.uk_campanha_json(c iara.uk_campanhas) returns jsonb
language sql stable
as $$
  select jsonb_build_object('id', c.id, 'ano', c.ano, 'nome', c.nome, 'coleta_inicio', c.coleta_inicio, 'coleta_fim', c.coleta_fim,
    'entrega_inicio', c.entrega_inicio, 'entrega_fim', c.entrega_fim, 'prazo_retirada_dias', c.prazo_retirada_dias, 'inclui_uniforme', c.inclui_uniforme,
    'inclui_kit', c.inclui_kit, 'situacao', c.situacao, 'observacao', c.observacao, 'gerada_em', c.gerada_em,
    'coleta_aberta', c.situacao = 'COLETA_TAMANHOS' or (c.situacao in ('SEPARACAO', 'ENTREGA') and c.coleta_fim >= iara.hoje_local()), 'is_demo', c.is_demo)
$$;

-- o aluno no ano: tamanhos, sugestão, necessidades e o código (para a ficha e para a família)
create or replace function iara.uk_aluno_ano(p_student uuid, p_ano integer, p_familia boolean) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select jsonb_build_object('ano', p_ano, 'etapa', iara.uk_etapa_aluno(p_student, p_ano), 'etapa_rotulo', iara.uk_etapa_rotulo(iara.uk_etapa_aluno(p_student, p_ano)),
      'ampliacao', iara.uk_ampliacao(p_student, p_ano),
      'tamanhos', (select jsonb_build_object('superior', t.superior, 'inferior', t.inferior, 'calcado', t.calcado, 'meia', iara.uk_meia(t.calcado),
                     'modelo', t.modelo_inferior, 'canal', t.canal, 'informado_em', t.informado_em, 'informado_por', case when p_familia then null else t.informado_por_label end)
                   from iara.uk_tamanhos t where t.student_id = p_student and t.ano = p_ano and t.canal <> 'ESTIMATIVA'),
      'sugestao', iara.uk_sugestao(p_student, p_ano),
      'necessidades', (select coalesce(jsonb_agg(iara.uk_nec_json(n, p_familia) order by n.conteudo desc, n.created_at), '[]')
                       from iara.uk_necessidades n where n.student_id = p_student and n.ano = p_ano))
$$;

-- 7. Família (portal e IARA: as mesmas funções) ----------------------------------------------------------------------------------------------
create or replace function api.familia_uniformes(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_ids uuid[];
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  select array_agg(x) into v_ids from iara.my_student_ids() x;
  return jsonb_build_object(
    'campanhas', (select coalesce(jsonb_agg(iara.uk_campanha_json(c) order by c.ano desc), '[]') from iara.uk_campanhas c
                  where c.situacao <> 'PLANEJAMENTO' and c.ano >= iara.school_year() - 1),
    'grade', (select jsonb_object_agg(g, t) from (select grade g, jsonb_agg(tamanho order by ordem) t from iara.uk_grades where ativo group by grade) z),
    'filhos', (select coalesce(jsonb_agg(jsonb_build_object('student_id', s.id, 'nome', s.full_name, 'primeiro_nome', split_part(s.full_name, ' ', 1),
                 'unidade', u.short_name, 'anos', (select coalesce(jsonb_agg(iara.uk_aluno_ano(s.id, c.ano, true) order by c.ano desc), '[]')
                                                   from iara.uk_campanhas c where c.situacao <> 'PLANEJAMENTO' and c.ano >= iara.school_year() - 1),
                 'autorizados', (select coalesce(jsonb_agg(a - 'documento' - 'guardian_id' - 'autorizacao_id'), '[]') from jsonb_array_elements(iara.uk_autorizados(s.id)) a))
                 order by s.full_name), '[]')
               from iara.students s
               join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE'
               left join iara.education_units u on u.id = e.unit_id
               where s.id = any (v_ids)),
    'avisos', (select coalesce(jsonb_agg(iara.uk_aviso_json(a) || jsonb_build_object('primeiro_nome', split_part(s.full_name, ' ', 1)) order by a.enviado_em desc), '[]')
               from iara.uk_avisos a join iara.students s on s.id = a.student_id where a.student_id = any (v_ids) and a.ciente_em is null),
    'historico', (select coalesce(jsonb_agg(iara.uk_aviso_json(a) || jsonb_build_object('primeiro_nome', split_part(s.full_name, ' ', 1)) order by a.ciente_em desc), '[]')
                  from (select * from iara.uk_avisos where student_id = any (v_ids) and ciente_em is not null order by ciente_em desc limit 40) a
                  join iara.students s on s.id = a.student_id),
    'pendentes_ciencia', (select count(*) from iara.uk_avisos where student_id = any (v_ids) and ciente_em is null),
    'pendentes_tamanho', (select count(distinct n.student_id) from iara.uk_necessidades n join iara.uk_campanhas c on c.id = n.campanha_id
                          where n.student_id = any (v_ids) and n.situacao = 'AGUARDANDO_TAMANHO' and c.situacao in ('COLETA_TAMANHOS', 'SEPARACAO', 'ENTREGA')),
    'pode_retirar', (select coalesce(jsonb_agg(distinct n.student_id), '[]') from iara.uk_necessidades n where n.student_id = any (v_ids) and n.situacao = 'DISPONIVEL'));
end $$;

create or replace function api.familia_uniformes_tamanhos(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_ano integer := coalesce(nullif(p ->> 'ano', '')::int, (select ano from iara.uk_campanhas where situacao in ('COLETA_TAMANHOS', 'SEPARACAO', 'ENTREGA') order by ano desc limit 1),
                            iara.school_year());
  c iara.uk_campanhas;
begin
  if iara.my_guardian() is null or v_student is null or v_student not in (select iara.my_student_ids()) then
    raise exception 'Criança não encontrada na sua família.' using errcode = 'P0002'; end if;
  select * into c from iara.uk_campanhas where ano = v_ano;
  if c.id is null or c.situacao in ('PLANEJAMENTO', 'ENCERRADA') then
    raise exception 'A coleta de tamanhos do uniforme de % não está aberta.', v_ano using errcode = '22023'; end if;
  if exists (select 1 from iara.uk_necessidades where student_id = v_student and ano = v_ano and conteudo = 'UNIFORME' and tipo in ('ANUAL', 'ALUNO_NOVO')
             and (pedido_id is not null or situacao in ('DISPONIVEL', 'RETIRADA', 'PARCIAL'))) then
    raise exception 'O uniforme de % já foi separado com os tamanhos anteriores. Se não servir, peça a troca de tamanho.', v_ano using errcode = '22023'; end if;
  return iara.uk_tamanho_gravar(v_student, v_ano, p, case when p ->> 'canal' = 'WHATSAPP' then 'WHATSAPP' else 'PORTAL' end);
end $$;

create or replace function api.familia_uniformes_ciente(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  a iara.uk_avisos;
begin
  if iara.my_guardian() is null then raise exception 'Disponível para responsáveis.' using errcode = '42501'; end if;
  update iara.uk_avisos set ciente_em = coalesce(ciente_em, now()), ciente_canal = coalesce(ciente_canal, case when p ->> 'canal' = 'WHATSAPP' then 'WHATSAPP' else 'PORTAL' end),
         ciente_por = coalesce(ciente_por, iara.my_guardian())
  where id = (p ->> 'id')::uuid and student_id in (select iara.my_student_ids())
  returning * into a;
  if a.id is null then raise exception 'Aviso não encontrado.' using errcode = 'P0002'; end if;
  perform iara.audit_event('UNIFORME_CIENCIA', 'uk_aviso', a.id::text, a.unit_id, format('Ciência do aviso “%s”.', a.titulo));
  return jsonb_build_object('ok', true, 'ciente_em', a.ciente_em);
end $$;

-- troca de tamanho ou reposição pedida pela família: vai para a unidade decidir
create or replace function api.familia_uniformes_pedir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_tipo text := p ->> 'tipo';
  v_cont text := coalesce(nullif(p ->> 'conteudo', ''), 'UNIFORME');
  v_motivo text := nullif(btrim(coalesce(p ->> 'motivo', '')), '');
  v_unit integer;
  n iara.uk_necessidades;
begin
  if iara.my_guardian() is null or v_student is null or v_student not in (select iara.my_student_ids()) then
    raise exception 'Criança não encontrada na sua família.' using errcode = 'P0002'; end if;
  if v_tipo not in ('TROCA_TAMANHO', 'REPOSICAO') then raise exception 'Escolha: troca de tamanho ou reposição.' using errcode = '22023'; end if;
  if v_cont not in ('UNIFORME', 'KIT') or (v_tipo = 'TROCA_TAMANHO' and v_cont <> 'UNIFORME') then raise exception 'Troca de tamanho vale para o uniforme.' using errcode = '22023'; end if;
  if coalesce(length(v_motivo), 0) < 5 then raise exception 'Conte em poucas palavras o que aconteceu (peças e motivo).' using errcode = '22023'; end if;
  select unit_id into v_unit from iara.enrollments where student_id = v_student and status = 'ACTIVE' limit 1;
  if v_unit is null then raise exception 'Sem matrícula ativa.' using errcode = '22023'; end if;
  -- um pedido igual ainda sem resposta da unidade basta; depois de decidido, a família pode pedir outra peça
  if exists (select 1 from iara.uk_necessidades where student_id = v_student and tipo = v_tipo and conteudo = v_cont and situacao = 'AGUARDANDO_DECISAO') then
    raise exception 'Já há um pedido igual esperando a resposta da unidade. Acompanhe por aqui.' using errcode = '22023'; end if;
  insert into iara.uk_necessidades (ano, student_id, unit_id, etapa, ampliacao, tipo, conteudo, itens, motivo, origem, solicitante_label, situacao)
  values (iara.school_year(), v_student, v_unit, iara.uk_etapa_aluno(v_student, iara.school_year()), iara.uk_ampliacao(v_student, iara.school_year()),
          v_tipo, v_cont, coalesce(p -> 'itens', '[]'), v_motivo, 'FAMILIA', iara.my_label(), 'AGUARDANDO_DECISAO')
  returning * into n;
  perform iara.audit_event('UNIFORME_PEDIDO', 'uk_necessidade', n.id::text, v_unit, format('%s pedida pela família (%s).', iara.uk_tipo_rotulo(v_tipo), iara.uk_conteudo_rotulo(v_cont)));
  return jsonb_build_object('ok', true, 'id', n.id,
    'mensagem', format('Pedido de %s registrado. A unidade analisa e você recebe a resposta aqui e no WhatsApp.', lower(iara.uk_tipo_rotulo(v_tipo))));
end $$;

-- 8. Unidade (direção e secretaria escolar) ---------------------------------------------------------------------------------------------------
create or replace function iara.uk_unit_do_pedido(p jsonb) returns integer
language sql stable security definer set search_path = iara, public
as $$ select case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end $$;

create or replace function api.uk_unidade(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_unit integer := iara.uk_unit_do_pedido(p);
  v_ano integer := coalesce(nullif(p ->> 'ano', '')::int, (select max(ano) from iara.uk_campanhas where situacao in ('SEPARACAO', 'ENTREGA')),
                            (select max(ano) from iara.uk_campanhas where situacao <> 'PLANEJAMENTO'), iara.school_year());
  v_busca text := nullif(iara.norm(btrim(coalesce(p ->> 'busca', ''))), '');
  v_sit text := nullif(p ->> 'situacao', '');
  v_etapa text := nullif(p ->> 'etapa', '');
begin
  perform iara.require_perm('uk.read');
  if v_unit is null or not iara.can_access_unit(v_unit) then raise exception 'Escolha a unidade.' using errcode = '22023'; end if;
  return (with al as (
      select s.id, s.full_name, c.class_name, c.id class_id,
             (select n from iara.uk_necessidades n where n.student_id = s.id and n.ano = v_ano and n.conteudo = 'UNIFORME' and n.tipo in ('ANUAL', 'ALUNO_NOVO')
              and n.situacao not in ('CANCELADA', 'NEGADA') limit 1) uni,
             (select n from iara.uk_necessidades n where n.student_id = s.id and n.ano = v_ano and n.conteudo = 'KIT' and n.tipo in ('ANUAL', 'ALUNO_NOVO')
              and n.situacao not in ('CANCELADA', 'NEGADA') limit 1) kit,
             (select t from iara.uk_tamanhos t where t.student_id = s.id and t.ano = v_ano) tam,
             (select a from iara.uk_avisos a where a.student_id = s.id and a.ano = v_ano and a.tipo in ('RETIRADA', 'LEMBRETE_RETIRADA') order by a.enviado_em desc limit 1) av
      from iara.enrollments e join iara.students s on s.id = e.student_id join iara.classes c on c.id = e.class_id
      where e.unit_id = v_unit and e.status = 'ACTIVE'),
    lin as (
      select al.*, coalesce((al.uni).etapa, (al.kit).etapa) etapa from al)
    select jsonb_build_object(
      'ano', v_ano, 'unit_id', v_unit, 'unidade', (select short_name from iara.education_units where id = v_unit),
      'campanha', (select iara.uk_campanha_json(c) from iara.uk_campanhas c where c.ano = v_ano),
      'anos', (select coalesce(jsonb_agg(ano order by ano desc), '[]') from iara.uk_campanhas where situacao <> 'PLANEJAMENTO'),
      'pode_operar', iara.has_perm('uk.unidade') and iara.my_scope() = 'UNIT',
      'contagem', jsonb_build_object(
        'alunos', (select count(*) from lin),
        'sem_tamanho', (select count(*) from lin where (lin.uni).situacao = 'AGUARDANDO_TAMANHO'),
        'aguardando_material', (select count(*) from iara.uk_necessidades n where n.unit_id = v_unit and n.ano = v_ano and n.situacao = 'AGUARDANDO_MATERIAL'),
        'disponiveis', (select count(*) from iara.uk_necessidades n where n.unit_id = v_unit and n.ano = v_ano and n.situacao = 'DISPONIVEL'),
        'vencidas', (select count(*) from iara.uk_necessidades n where n.unit_id = v_unit and n.ano = v_ano and n.situacao = 'DISPONIVEL' and n.prazo_retirada < iara.hoje_local()),
        'retiradas', (select count(*) from iara.uk_necessidades n where n.unit_id = v_unit and n.ano = v_ano and n.situacao in ('RETIRADA', 'PARCIAL')),
        'pedidos', (select count(*) from iara.uk_necessidades n where n.unit_id = v_unit and n.situacao = 'AGUARDANDO_DECISAO')),
      'por_etapa', (select coalesce(jsonb_agg(jsonb_build_object('etapa', etapa, 'rotulo', iara.uk_etapa_rotulo(etapa), 'alunos', n, 'sem_tamanho', st,
                       'aguardando', ag, 'disponiveis', di, 'retiradas', re) order by etapa), '[]') from (
                      select lin.etapa, count(*) n, count(*) filter (where (lin.uni).situacao = 'AGUARDANDO_TAMANHO') st,
                             count(*) filter (where 'AGUARDANDO_MATERIAL' in ((lin.uni).situacao, (lin.kit).situacao)) ag,
                             count(*) filter (where 'DISPONIVEL' in ((lin.uni).situacao, (lin.kit).situacao)) di,
                             count(*) filter (where coalesce((lin.uni).situacao, 'RETIRADA') = 'RETIRADA' and coalesce((lin.kit).situacao, 'RETIRADA') = 'RETIRADA'
                                              and (lin.uni).id is not null or (lin.kit).id is not null and (lin.kit).situacao = 'RETIRADA' and (lin.uni).id is null) re
                      from lin where lin.etapa is not null group by lin.etapa) z),
      'turmas', (select coalesce(jsonb_agg(jsonb_build_object('id', class_id, 'nome', class_name) order by class_name), '[]') from (select distinct class_id, class_name from lin) z),
      'alunos', (select coalesce(jsonb_agg(x order by x ->> 'turma', x ->> 'nome'), '[]') from (
        select jsonb_build_object('student_id', lin.id, 'nome', lin.full_name, 'turma', lin.class_name, 'class_id', lin.class_id, 'etapa', lin.etapa,
               'etapa_rotulo', iara.uk_etapa_rotulo(lin.etapa),
               'tamanhos', case when (lin.tam).student_id is not null then jsonb_build_object('superior', (lin.tam).superior, 'inferior', (lin.tam).inferior,
                             'calcado', (lin.tam).calcado, 'modelo', (lin.tam).modelo_inferior, 'canal', (lin.tam).canal) end,
               'uniforme', case when (lin.uni).id is not null then jsonb_build_object('id', (lin.uni).id, 'situacao', (lin.uni).situacao,
                             'rotulo', iara.uk_situacao_rotulo((lin.uni).situacao), 'retirada_em', (lin.uni).retirada_em, 'retirada_por', (lin.uni).retirada_por_nome,
                             'prazo', (lin.uni).prazo_retirada) end,
               'kit', case when (lin.kit).id is not null then jsonb_build_object('id', (lin.kit).id, 'situacao', (lin.kit).situacao,
                             'rotulo', iara.uk_situacao_rotulo((lin.kit).situacao), 'retirada_em', (lin.kit).retirada_em, 'retirada_por', (lin.kit).retirada_por_nome,
                             'prazo', (lin.kit).prazo_retirada, 'ampliacao', (lin.kit).ampliacao) end,
               'aviso', case when (lin.av).id is not null then jsonb_build_object('enviado_em', (lin.av).enviado_em, 'whatsapp', (lin.av).whatsapp_status,
                             'ciente_em', (lin.av).ciente_em) end) x
        from lin
        where (v_busca is null or iara.norm(lin.full_name) like '%' || v_busca || '%')
          and (v_etapa is null or lin.etapa = v_etapa)
          and (v_sit is null or v_sit in ((lin.uni).situacao, (lin.kit).situacao)
               or (v_sit = 'VENCIDA' and ('DISPONIVEL' in ((lin.uni).situacao, (lin.kit).situacao)) and least((lin.uni).prazo_retirada, (lin.kit).prazo_retirada) < iara.hoje_local()))
        limit 1500) q)));
end $$;

-- ficha do aluno: aba Uniforme e kit
create or replace function api.uk_aluno(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
begin
  perform iara.require_perm('uk.read');
  if v_student is null or not iara.can_access_student(v_student) then raise exception 'Aluno não encontrado.' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'anos', (select coalesce(jsonb_agg(iara.uk_aluno_ano(v_student, a.ano, false) order by a.ano desc), '[]')
             from (select ano from iara.uk_campanhas where situacao <> 'PLANEJAMENTO' union select ano from iara.uk_necessidades where student_id = v_student) a),
    'avisos', (select coalesce(jsonb_agg(iara.uk_aviso_json(a) order by a.enviado_em desc), '[]') from iara.uk_avisos a where a.student_id = v_student),
    'autorizados', iara.uk_autorizados(v_student),
    'codigo', (select jsonb_object_agg(ano, regexp_replace(codigo, '^(\d{3})(\d{3})$', '\1 \2')) from iara.uk_codigos where student_id = v_student),
    'pode_operar', iara.has_perm('uk.unidade') and iara.my_scope() = 'UNIT',
    'pode_adaptado', iara.has_perm('uk.adaptado') or iara.has_perm('uk.unidade'),
    'grade', (select jsonb_object_agg(g, t) from (select grade g, jsonb_agg(tamanho order by ordem) t from iara.uk_grades where ativo group by grade) z));
end $$;

-- conferência do código na retirada: quem é, o que está liberado e quem pode retirar
create or replace function api.uk_codigo_conferir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_cod text := regexp_replace(coalesce(p ->> 'codigo', ''), '\D', '', 'g');
  v_student uuid := nullif(p ->> 'student_id', '')::uuid;
  v_ano integer;
  s iara.students;
begin
  perform iara.require_perm('uk.unidade');
  if v_student is null then
    if length(v_cod) <> 6 then raise exception 'O código tem 6 números.' using errcode = '22023'; end if;
    select student_id, ano into v_student, v_ano from iara.uk_codigos where codigo = v_cod order by ano desc limit 1;
    if v_student is null then
      perform iara.audit_event('UNIFORME_CODIGO_INVALIDO', 'uk_codigo', null, iara.my_unit(), 'Código de retirada não encontrado.');
      raise exception 'Código não encontrado. Confira os números ou procure pelo nome do aluno.' using errcode = 'P0002';
    end if;
  end if;
  select * into s from iara.students where id = v_student;
  if s.id is null or not iara.can_access_student(s.id) or not exists (select 1 from iara.enrollments e where e.student_id = s.id and e.status = 'ACTIVE' and e.unit_id = iara.my_unit()) then
    raise exception 'Este aluno não está matriculado nesta unidade.' using errcode = 'P0002'; end if;
  return jsonb_build_object('student_id', s.id, 'nome', s.full_name, 'codigo_ok', v_ano is not null,
    'turma', (select c.class_name from iara.enrollments e join iara.classes c on c.id = e.class_id where e.student_id = s.id and e.status = 'ACTIVE' limit 1),
    'disponiveis', (select coalesce(jsonb_agg(iara.uk_nec_json(n) order by n.conteudo desc), '[]') from iara.uk_necessidades n
                    where n.student_id = s.id and n.situacao = 'DISPONIVEL' and n.unit_id = iara.my_unit()),
    'outras', (select coalesce(jsonb_agg(iara.uk_nec_json(n) order by n.ano desc, n.conteudo desc), '[]') from iara.uk_necessidades n
               where n.student_id = s.id and n.situacao in ('AGUARDANDO_TAMANHO', 'AGUARDANDO_MATERIAL', 'AGUARDANDO_DECISAO')),
    'autorizados', iara.uk_autorizados(s.id),
    'alerta_guarda', exists (select 1 from iara.guarda_restricoes r where r.student_id = s.id and iara.guarda_ativa(r) and r.efeito_retirada = 'NAO_PODE'));
end $$;

-- registro da retirada: data, hora, quem retirou (responsável ou autorizado), código ou documento; baixa no estoque da unidade
create or replace function api.uk_retirada_registrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_quem jsonb := p -> 'quem';
  v_aut jsonb;
  v_cod text := regexp_replace(coalesce(p ->> 'codigo', ''), '\D', '', 'g');
  v_doc text := nullif(btrim(coalesce(p ->> 'documento', '')), '');
  v_ok_cod boolean;
  n iara.uk_necessidades;
  it jsonb;
  m iara.materiais;
  v_baixas jsonb;
  v_falta jsonb := coalesce(p -> 'faltando', '[]');
  v_ids uuid[] := '{}';
  v_conteudos text[] := '{}';
  v_ano integer;
  v_unit integer := iara.my_unit();
begin
  perform iara.require_perm('uk.unidade');
  if iara.my_scope() <> 'UNIT' then raise exception 'A retirada é registrada pela unidade.' using errcode = '42501'; end if;
  if jsonb_array_length(coalesce(p -> 'ids', '[]')) = 0 then raise exception 'Marque o que está sendo entregue.' using errcode = '22023'; end if;
  -- quem retira tem de estar na lista de autorizados
  select a into v_aut from jsonb_array_elements(iara.uk_autorizados(v_student)) a
  where (a ->> 'tipo' = 'RESPONSAVEL' and a ->> 'guardian_id' = v_quem ->> 'guardian_id')
     or (a ->> 'tipo' = 'AUTORIZADO' and a ->> 'autorizacao_id' = v_quem ->> 'autorizacao_id')
     or (a ->> 'tipo' = 'PROPRIO' and coalesce((v_quem ->> 'proprio')::boolean, false))
  limit 1;
  if v_aut is null then
    raise exception 'Só o responsável ou a pessoa autorizada a buscar a criança pode retirar. Para incluir alguém, use Guarda e restrições.' using errcode = '22023'; end if;
  v_ok_cod := v_cod <> '' and exists (select 1 from iara.uk_codigos where student_id = v_student and codigo = v_cod);
  if v_cod <> '' and not v_ok_cod then raise exception 'O código não confere com este aluno.' using errcode = '22023'; end if;
  if not v_ok_cod and coalesce(length(v_doc), 0) < 3 then raise exception 'Sem o código, confira um documento com foto e anote os últimos números.' using errcode = '22023'; end if;

  for n in select * from iara.uk_necessidades where id in (select (x)::uuid from jsonb_array_elements_text(p -> 'ids') x) for update loop
    if n.student_id <> v_student or n.unit_id <> v_unit or n.situacao not in ('DISPONIVEL', 'AGUARDANDO_MATERIAL', 'PARCIAL') then
      raise exception 'Item fora da lista de retirada deste aluno.' using errcode = '22023'; end if;
    v_baixas := '[]';
    for it in select * from jsonb_array_elements(n.itens) loop
      if exists (select 1 from jsonb_array_elements(v_falta) f where f ->> 'id' = n.id::text and f ->> 'item' = it ->> 'item') then
        v_baixas := v_baixas || (it || jsonb_build_object('entregue', false));
        continue;
      end if;
      select * into m from iara.materiais where unit_id = v_unit and codigo = it ->> 'produto' and ativo order by created_at limit 1;
      if m.id is not null and m.quantidade >= (it ->> 'quantidade')::numeric then
        perform iara.estoque_baixar(m.id, (it ->> 'quantidade')::numeric, format('Retirada %s — %s', iara.uk_conteudo_rotulo(n.conteudo), iara.codigo_publico(v_student)));
        v_baixas := v_baixas || (it || jsonb_build_object('entregue', true, 'baixa', true));
      else
        v_baixas := v_baixas || (it || jsonb_build_object('entregue', true, 'baixa', false));
      end if;
    end loop;
    update iara.uk_necessidades set
      situacao = case when exists (select 1 from jsonb_array_elements(v_baixas) b where not (b ->> 'entregue')::boolean) then 'PARCIAL' else 'RETIRADA' end,
      retirada_em = now(), retirada_por_nome = v_aut ->> 'nome', retirada_por_parentesco = v_aut ->> 'parentesco',
      retirada_por_guardian = nullif(v_aut ->> 'guardian_id', '')::uuid, retirada_documento = case when v_ok_cod then null else '…' || right(v_doc, 4) end,
      codigo_conferido = v_ok_cod, registrado_por_label = iara.my_label(), entregue = v_baixas,
      observacao = coalesce(nullif(btrim(coalesce(p ->> 'observacao', '')), ''), observacao), updated_at = now()
    where id = n.id;
    v_ids := v_ids || n.id;
    v_conteudos := v_conteudos || n.conteudo;
    v_ano := n.ano;
  end loop;
  if cardinality(v_ids) = 0 then raise exception 'Nada a registrar.' using errcode = '22023'; end if;
  -- a família recebe a confirmação (protege contra retirada indevida)
  perform iara.uk_aviso_criar(v_student, 'RETIRADA_REGISTRADA', 'Retirada registrada',
    format('%s de %s retirado(s) em %s por %s (%s), no(a) %s.', initcap(array_to_string(array(select distinct iara.uk_conteudo_rotulo(c) from unnest(v_conteudos) c), ' e ')),
           (select split_part(full_name, ' ', 1) from iara.students where id = v_student), to_char(iara.agora_local(), 'DD/MM/YYYY "às" HH24:MI'),
           v_aut ->> 'nome', lower(v_aut ->> 'parentesco'), (select short_name from iara.education_units where id = v_unit)),
    v_ano, v_unit, v_ids);
  -- avisos de retirada deste aluno saem do quadro de pendência da unidade (a família ainda dá ciência)
  perform iara.audit_event('UNIFORME_RETIRADA', 'student', v_student::text, v_unit,
    format('Retirada de %s registrada: %s (%s), %s.', array_to_string(array(select distinct iara.uk_conteudo_rotulo(c) from unnest(v_conteudos) c), ' e '),
           v_aut ->> 'nome', v_aut ->> 'parentesco', case when v_ok_cod then 'código conferido' else 'documento conferido' end));
  return jsonb_build_object('ok', true, 'registradas', cardinality(v_ids), 'retirada_por', v_aut ->> 'nome', 'em', now());
end $$;

-- libera para retirada por etapa, turma ou seleção (o material já está na unidade)
create or replace function api.uk_disponibilizar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_unit integer := iara.my_unit();
  v_ano integer := coalesce(nullif(p ->> 'ano', '')::int, (select max(ano) from iara.uk_campanhas where situacao in ('SEPARACAO', 'ENTREGA')), iara.school_year());
  v_ids uuid[];
  v_sem integer;
  r jsonb;
begin
  perform iara.require_perm('uk.unidade');
  if iara.my_scope() <> 'UNIT' then raise exception 'A liberação é feita pela unidade.' using errcode = '42501'; end if;
  select array_agg(n.id) into v_ids from iara.uk_necessidades n
  left join iara.enrollments e on e.student_id = n.student_id and e.status = 'ACTIVE'
  where n.unit_id = v_unit and n.ano = v_ano and n.situacao = 'AGUARDANDO_MATERIAL'
    and (nullif(p ->> 'conteudo', '') is null or n.conteudo = p ->> 'conteudo')
    and (nullif(p ->> 'etapa', '') is null or n.etapa = p ->> 'etapa')
    and (nullif(p ->> 'class_id', '') is null or e.class_id = (p ->> 'class_id')::uuid)
    and (p -> 'ids' is null or n.id in (select (x)::uuid from jsonb_array_elements_text(p -> 'ids') x));
  select count(*) into v_sem from iara.uk_necessidades n
  left join iara.enrollments e on e.student_id = n.student_id and e.status = 'ACTIVE'
  where n.unit_id = v_unit and n.ano = v_ano and n.situacao = 'AGUARDANDO_TAMANHO'
    and (nullif(p ->> 'etapa', '') is null or n.etapa = p ->> 'etapa')
    and (nullif(p ->> 'class_id', '') is null or e.class_id = (p ->> 'class_id')::uuid);
  if v_ids is null then
    return jsonb_build_object('liberadas', 0, 'avisos', 0, 'sem_tamanho', v_sem);
  end if;
  r := iara.uk_liberar(v_ids);
  perform iara.audit_event('UNIFORME_LIBERADO', 'education_unit', v_unit::text, v_unit,
    format('%s item(ns) liberado(s) para retirada%s%s; %s aviso(s) às famílias.', r ->> 'liberadas', coalesce(' · ' || iara.uk_etapa_rotulo(nullif(p ->> 'etapa', '')), ''),
           coalesce(' · ' || lower(iara.uk_conteudo_rotulo(nullif(p ->> 'conteudo', ''))), ''), r ->> 'avisos'));
  return r || jsonb_build_object('sem_tamanho', v_sem);
end $$;

-- a unidade informa o tamanho pela família (na secretaria, por telefone)
create or replace function api.uk_tamanhos_registrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_ano integer := coalesce(nullif(p ->> 'ano', '')::int, (select max(ano) from iara.uk_campanhas where situacao in ('COLETA_TAMANHOS', 'SEPARACAO', 'ENTREGA')), iara.school_year());
begin
  perform iara.require_perm('uk.unidade');
  if v_student is null or not iara.can_access_student(v_student) then raise exception 'Aluno não encontrado.' using errcode = 'P0002'; end if;
  return iara.uk_tamanho_gravar(v_student, v_ano, p, 'UNIDADE');
end $$;

-- a unidade (ou o AEE) registra uma necessidade: aluno novo, troca, reposição, material adaptado
create or replace function api.uk_necessidade_registrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_student uuid := (p ->> 'student_id')::uuid;
  v_tipo text := p ->> 'tipo';
  v_cont text := case when p ->> 'tipo' = 'ADAPTADO' then 'ADAPTADO' else coalesce(nullif(p ->> 'conteudo', ''), 'UNIFORME') end;
  v_motivo text := nullif(btrim(coalesce(p ->> 'motivo', '')), '');
  v_unit integer;
  v_etapa text;
  v_amp boolean;
  t iara.uk_tamanhos;
  n iara.uk_necessidades;
  v_aee boolean := iara.has_perm('uk.adaptado') and not iara.has_perm('uk.unidade');
begin
  if v_aee then perform iara.require_perm('uk.adaptado'); else perform iara.require_perm('uk.unidade'); end if;
  if v_student is null or not iara.can_access_student(v_student) then raise exception 'Aluno não encontrado.' using errcode = 'P0002'; end if;
  if v_tipo not in ('ALUNO_NOVO', 'TROCA_TAMANHO', 'REPOSICAO', 'ADAPTADO') or (v_aee and v_tipo <> 'ADAPTADO') then
    raise exception 'Tipo de necessidade inválido.' using errcode = '22023'; end if;
  if v_tipo <> 'ALUNO_NOVO' and coalesce(length(v_motivo), 0) < 5 then raise exception 'Descreva o motivo e as peças.' using errcode = '22023'; end if;
  if v_tipo = 'ADAPTADO' and jsonb_array_length(coalesce(p -> 'itens', '[]')) = 0 then raise exception 'Inclua pelo menos um material adaptado.' using errcode = '22023'; end if;
  select unit_id into v_unit from iara.enrollments where student_id = v_student and status = 'ACTIVE' limit 1;
  v_etapa := iara.uk_etapa_aluno(v_student, iara.school_year());
  v_amp := iara.uk_ampliacao(v_student, iara.school_year());
  select * into t from iara.uk_tamanhos where student_id = v_student and ano = iara.school_year();
  insert into iara.uk_necessidades (campanha_id, ano, student_id, unit_id, etapa, ampliacao, tipo, conteudo, itens, motivo, origem, solicitante_label, situacao)
  values ((select id from iara.uk_campanhas where ano = iara.school_year()), iara.school_year(), v_student, v_unit, v_etapa, v_amp, v_tipo, v_cont,
          case when v_tipo = 'ALUNO_NOVO' then coalesce(iara.uk_montar_itens(v_cont, v_etapa, v_amp, t), '[]')
               else (select coalesce(jsonb_agg(case when jsonb_typeof(x) = 'string' then jsonb_build_object('nome', x #>> '{}', 'quantidade', 1) else x end), '[]')
                     from jsonb_array_elements(coalesce(p -> 'itens', '[]')) x) end,
          v_motivo, case when v_aee then 'AEE' else 'UNIDADE' end, iara.my_label(),
          case when v_tipo = 'ALUNO_NOVO' and v_cont = 'UNIFORME' and t.student_id is null then 'AGUARDANDO_TAMANHO'
               when v_tipo = 'ALUNO_NOVO' then 'AGUARDANDO_MATERIAL'
               when v_tipo = 'ADAPTADO' then 'AGUARDANDO_DECISAO'
               else 'AGUARDANDO_MATERIAL' end)
  returning * into n;
  perform iara.audit_event('UNIFORME_NECESSIDADE', 'uk_necessidade', n.id::text, v_unit, format('%s registrada (%s).', iara.uk_tipo_rotulo(v_tipo), iara.uk_conteudo_rotulo(v_cont)));
  return iara.uk_nec_json(n);
end $$;

-- decisão: trocas e reposições pedidas pela família (unidade); material adaptado (SEDUC)
create or replace function api.uk_necessidade_decidir(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  n iara.uk_necessidades;
  v_aprovar boolean := coalesce((p ->> 'aprovar')::boolean, false);
  v_motivo text := nullif(btrim(coalesce(p ->> 'motivo', '')), '');
begin
  select * into n from iara.uk_necessidades where id = (p ->> 'id')::uuid for update;
  if n.id is null then raise exception 'Pedido não encontrado.' using errcode = 'P0002'; end if;
  if n.conteudo = 'ADAPTADO' then perform iara.require_perm('uk.manage');
  else
    perform iara.require_perm('uk.unidade');
    if iara.my_scope() <> 'UNIT' or n.unit_id <> iara.my_unit() then raise exception 'Pedido de outra unidade.' using errcode = '42501'; end if;
  end if;
  if n.situacao <> 'AGUARDANDO_DECISAO' then raise exception 'Este pedido já foi decidido.' using errcode = '22023'; end if;
  if not v_aprovar and coalesce(length(v_motivo), 0) < 10 then raise exception 'Explique à família por que não foi aprovado.' using errcode = '22023'; end if;
  update iara.uk_necessidades set situacao = case when v_aprovar then 'AGUARDANDO_MATERIAL' else 'NEGADA' end, decisao_motivo = v_motivo,
         decidido_por_label = iara.my_label(), decidido_em = now(), itens = coalesce(p -> 'itens', itens), updated_at = now()
  where id = n.id returning * into n;
  if n.origem = 'FAMILIA' or n.conteudo = 'ADAPTADO' then
    perform iara.uk_aviso_criar(n.student_id, 'DECISAO', format('%s: %s', iara.uk_tipo_rotulo(n.tipo), case when v_aprovar then 'aprovada' else 'não aprovada' end),
      case when v_aprovar then format('O pedido de %s de %s foi aprovado. Avisaremos quando puder retirar.', lower(iara.uk_tipo_rotulo(n.tipo)),
                                      (select split_part(full_name, ' ', 1) from iara.students where id = n.student_id))
           else format('O pedido de %s de %s não foi aprovado: %s', lower(iara.uk_tipo_rotulo(n.tipo)), (select split_part(full_name, ' ', 1) from iara.students where id = n.student_id), v_motivo) end,
      n.ano, n.unit_id, array[n.id]);
  end if;
  perform iara.audit_event('UNIFORME_DECISAO', 'uk_necessidade', n.id::text, n.unit_id, format('%s %s.', iara.uk_tipo_rotulo(n.tipo), case when v_aprovar then 'aprovada' else 'negada' end));
  return iara.uk_nec_json(n);
end $$;

-- pedidos aguardando decisão (unidade: trocas e reposições; SEDUC: material adaptado da rede)
create or replace function api.uk_pedidos_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('uk.read');
  return (select coalesce(jsonb_agg(iara.uk_nec_json(n) || jsonb_build_object('aluno', s.full_name, 'student_id', s.id) order by n.created_at), '[]')
          from iara.uk_necessidades n join iara.students s on s.id = n.student_id
          where n.tipo in ('TROCA_TAMANHO', 'REPOSICAO', 'ADAPTADO', 'ALUNO_NOVO')
            and (case when nullif(p ->> 'situacao', '') is null then n.situacao in ('AGUARDANDO_DECISAO', 'AGUARDANDO_MATERIAL', 'AGUARDANDO_TAMANHO', 'DISPONIVEL')
                      else n.situacao = p ->> 'situacao' end)
            and iara.can_access_unit(n.unit_id)
            and (iara.my_scope() <> 'UNIT' or n.unit_id = iara.my_unit())
            and (iara.my_scope() = 'UNIT' or nullif(p ->> 'unit_id', '') is null or n.unit_id = (p ->> 'unit_id')::int)
          limit 500);
end $$;

-- 9. SEDUC: campanhas, catálogo, grade, demanda, remessas e disparos -----------------------------------------------------------------------
create or replace function api.uk_campanhas(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('uk.read');
  return (select coalesce(jsonb_agg(iara.uk_campanha_json(c) || jsonb_build_object(
            'alunos', (select count(distinct student_id) from iara.uk_necessidades where campanha_id = c.id),
            'sem_tamanho', (select count(*) from iara.uk_necessidades where campanha_id = c.id and situacao = 'AGUARDANDO_TAMANHO'),
            'retiradas', (select count(*) from iara.uk_necessidades where campanha_id = c.id and situacao in ('RETIRADA', 'PARCIAL')),
            'necessidades', (select count(*) from iara.uk_necessidades where campanha_id = c.id and situacao not in ('CANCELADA', 'NEGADA')))
          order by c.ano desc), '[]') from iara.uk_campanhas c);
end $$;

create or replace function api.uk_campanha_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c iara.uk_campanhas;
  v_ano integer := (p ->> 'ano')::int;
  r jsonb := null;
begin
  perform iara.require_perm('uk.manage');
  if v_ano is null or v_ano < 2024 or v_ano > 2100 then raise exception 'Informe o ano letivo.' using errcode = '22023'; end if;
  if coalesce(p ->> 'situacao', 'PLANEJAMENTO') not in ('PLANEJAMENTO', 'COLETA_TAMANHOS', 'SEPARACAO', 'ENTREGA', 'ENCERRADA') then
    raise exception 'Situação inválida.' using errcode = '22023'; end if;
  insert into iara.uk_campanhas (ano, nome, coleta_inicio, coleta_fim, entrega_inicio, entrega_fim, prazo_retirada_dias, inclui_uniforme, inclui_kit, situacao, observacao, atualizado_por_label)
  values (v_ano, coalesce(nullif(btrim(p ->> 'nome'), ''), format('Uniformes e kits %s', v_ano)), nullif(p ->> 'coleta_inicio', '')::date, nullif(p ->> 'coleta_fim', '')::date,
          nullif(p ->> 'entrega_inicio', '')::date, nullif(p ->> 'entrega_fim', '')::date, coalesce(nullif(p ->> 'prazo_retirada_dias', '')::int, 30),
          coalesce((p ->> 'inclui_uniforme')::boolean, true), coalesce((p ->> 'inclui_kit')::boolean, true), coalesce(p ->> 'situacao', 'PLANEJAMENTO'),
          nullif(btrim(coalesce(p ->> 'observacao', '')), ''), iara.my_label())
  on conflict (ano) do update set nome = excluded.nome, coleta_inicio = excluded.coleta_inicio, coleta_fim = excluded.coleta_fim,
    entrega_inicio = excluded.entrega_inicio, entrega_fim = excluded.entrega_fim, prazo_retirada_dias = excluded.prazo_retirada_dias,
    inclui_uniforme = excluded.inclui_uniforme, inclui_kit = excluded.inclui_kit, situacao = excluded.situacao, observacao = excluded.observacao,
    atualizado_por_label = excluded.atualizado_por_label, updated_at = now()
  returning * into c;
  if c.coleta_fim < c.coleta_inicio or c.entrega_fim < c.entrega_inicio then raise exception 'Confira as datas (fim antes do início).' using errcode = '22023'; end if;
  if c.situacao not in ('PLANEJAMENTO', 'ENCERRADA') then r := iara.uk_gerar(c.id); end if;
  perform iara.audit_event('UNIFORME_CAMPANHA', 'uk_campanha', c.id::text, null, format('Campanha %s: %s.', c.ano, lower(replace(c.situacao, '_', ' '))));
  return iara.uk_campanha_json(c) || jsonb_build_object('geracao', r);
end $$;

create or replace function api.uk_catalogo(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if not (iara.has_perm('uk.read') or iara.has_perm('uk.estatisticas')) then perform iara.require_perm('uk.read'); end if;
  return jsonb_build_object(
    'itens', (select coalesce(jsonb_agg(jsonb_build_object('codigo', i.codigo, 'tipo', i.tipo, 'nome', i.nome, 'descricao', i.descricao, 'medida', i.medida,
               'modelo', i.modelo, 'quantidade', i.quantidade, 'etapas', i.etapas, 'etapas_rotulo', (select string_agg(iara.uk_etapa_rotulo(e), ', ') from unnest(i.etapas) e),
               'so_ampliacao', i.so_ampliacao, 'valor_referencia', i.valor_referencia, 'valor_demo', i.valor_demo, 'ativo', i.ativo, 'fonte', i.fonte,
               'composicao', (select coalesce(jsonb_agg(jsonb_build_object('item', k.item, 'quantidade', k.quantidade, 'unidade', k.unidade, 'especificacao', k.especificacao)
                              order by k.ordem), '[]') from iara.uk_kit_itens k where k.kit_codigo = i.codigo))
               order by i.tipo desc, i.ordem), '[]') from iara.uk_itens i),
    'grade', (select coalesce(jsonb_agg(jsonb_build_object('grade', grade, 'tamanho', tamanho, 'ordem', ordem, 'calcado_min', calcado_min, 'calcado_max', calcado_max,
               'ativo', ativo) order by grade, ordem), '[]') from iara.uk_grades),
    'parametros', (select jsonb_object_agg(chave, valor) from iara.uk_parametros),
    'fontes', jsonb_build_array(
      jsonb_build_object('rotulo', 'Kit Escolar 2025 e 2026 (composição oficial)', 'url', 'https://www.maringa.pr.gov.br/portal/19/educacao/post/754'),
      jsonb_build_object('rotulo', 'Uniforme Escolar 2026', 'url', 'https://www.maringa.pr.gov.br/portal/19/educacao/post/782')),
    'pode_gerir', iara.has_perm('uk.manage'));
end $$;

create or replace function api.uk_grade_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_grade text := p ->> 'grade';
  x jsonb;
  i integer := 0;
begin
  perform iara.require_perm('uk.manage');
  if v_grade not in ('ROUPA', 'CALCADO', 'MEIA') then raise exception 'Grade inválida.' using errcode = '22023'; end if;
  if jsonb_array_length(coalesce(p -> 'tamanhos', '[]')) < 2 then raise exception 'A grade precisa de pelo menos dois tamanhos.' using errcode = '22023'; end if;
  update iara.uk_grades set ativo = false where grade = v_grade;
  for x in select * from jsonb_array_elements(p -> 'tamanhos') loop
    i := i + 1;
    insert into iara.uk_grades (grade, tamanho, ordem, calcado_min, calcado_max, ativo)
    values (v_grade, upper(btrim(coalesce(x ->> 'tamanho', x #>> '{}'))), i, nullif(x ->> 'calcado_min', '')::smallint, nullif(x ->> 'calcado_max', '')::smallint, true)
    on conflict (grade, tamanho) do update set ordem = excluded.ordem, calcado_min = coalesce(excluded.calcado_min, iara.uk_grades.calcado_min),
      calcado_max = coalesce(excluded.calcado_max, iara.uk_grades.calcado_max), ativo = true;
  end loop;
  perform iara.uk_produtos_garantir();
  perform iara.audit_event('UNIFORME_GRADE', 'uk_grade', v_grade, null, format('Grade %s atualizada (%s tamanhos).', lower(v_grade), i));
  return api.uk_catalogo('{}'::jsonb);
end $$;

create or replace function api.uk_item_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('uk.manage');
  update iara.uk_itens set
    quantidade = coalesce(nullif(p ->> 'quantidade', '')::smallint, quantidade),
    valor_referencia = case when p ? 'valor_referencia' then nullif(p ->> 'valor_referencia', '')::numeric end,
    valor_demo = case when p ? 'valor_referencia' then false else valor_demo end,
    ativo = coalesce((p ->> 'ativo')::boolean, ativo)
  where codigo = p ->> 'codigo';
  if not found then raise exception 'Item não encontrado.' using errcode = 'P0002'; end if;
  perform iara.audit_event('UNIFORME_ITEM', 'uk_item', p ->> 'codigo', null, format('Item %s atualizado.', p ->> 'codigo'));
  return api.uk_catalogo('{}'::jsonb);
end $$;

-- demanda por peça e tamanho (informado pela família, pela unidade e estimado pela idade de quem ainda não informou) — base da compra
create or replace function api.uk_demanda(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_ano integer := coalesce(nullif(p ->> 'ano', '')::int, (select max(ano) from iara.uk_campanhas where situacao <> 'ENCERRADA'), iara.school_year());
  v_unit integer := nullif(p ->> 'unit_id', '')::int;
begin
  if not (iara.has_perm('uk.manage') or iara.has_perm('uk.estatisticas')) then perform iara.require_perm('uk.manage'); end if;
  return (with nec as (
      select n.*, t.student_id tem, coalesce(t.superior, (iara.uk_sugestao(n.student_id, n.ano)) ->> 'superior') sup,
             coalesce(t.inferior, (iara.uk_sugestao(n.student_id, n.ano)) ->> 'inferior') inf,
             coalesce(t.calcado, ((iara.uk_sugestao(n.student_id, n.ano)) ->> 'calcado')::int) calc,
             t.modelo_inferior modelo
      from iara.uk_necessidades n left join iara.uk_tamanhos t on t.student_id = n.student_id and t.ano = n.ano and t.canal <> 'ESTIMATIVA'
      where n.ano = v_ano and n.tipo in ('ANUAL', 'ALUNO_NOVO') and n.situacao not in ('CANCELADA', 'NEGADA') and (v_unit is null or n.unit_id = v_unit)),
    pecas as (
      select i.codigo, i.nome, i.ordem, i.medida,
             case i.medida when 'SUPERIOR' then nec.sup when 'INFERIOR' then nec.inf when 'CALCADO' then nec.calc::text when 'MEIA' then iara.uk_meia(nec.calc) end tamanho,
             i.quantidade, nec.tem is not null informado, i.modelo, nec.modelo modelo_aluno
      from nec join iara.uk_itens i on i.tipo = 'UNIFORME' and i.ativo and nec.etapa = any (i.etapas)
      where nec.conteudo = 'UNIFORME'),
    pecas_ok as (
      -- sem a escolha do modelo, metade vai para cada modelo (estimativa)
      select codigo, nome, ordem, tamanho, informado,
             case when modelo is null then quantidade::numeric when modelo_aluno is null then quantidade / 2.0 when modelo = modelo_aluno then quantidade::numeric else 0 end q
      from pecas)
    select jsonb_build_object('ano', v_ano,
      'uniforme', (select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'nome', nome, 'total', total, 'informado', inf, 'estimado', total - inf,
                     'tamanhos', tams) order by ordem), '[]') from (
                     select codigo, nome, ordem, round(sum(q)) total, round(sum(q) filter (where informado)) inf,
                            jsonb_agg(jsonb_build_object('tamanho', tamanho, 'quantidade', qt, 'informado', qi) order by g.ordem) tams
                     from (select codigo, nome, ordem, tamanho, sum(q) q, sum(q) filter (where informado) qi_raw from pecas_ok where q > 0 group by 1, 2, 3, 4) x
                     cross join lateral (select round(x.q) qt, round(coalesce(x.qi_raw, 0)) qi) z
                     left join iara.uk_grades g on g.tamanho = x.tamanho and g.grade = case when x.codigo = 'UNI-PAP' then 'CALCADO' when x.codigo = 'UNI-MEI' then 'MEIA' else 'ROUPA' end
                     group by codigo, nome, ordem, (select 1)) y),
      'kits', (select coalesce(jsonb_agg(jsonb_build_object('codigo', i.codigo, 'nome', i.nome, 'total', k.n, 'valor_referencia', i.valor_referencia) order by i.ordem), '[]')
               from (select it ->> 'item' codigo, count(*) n from nec, jsonb_array_elements(nec.itens) it where nec.conteudo = 'KIT' group by 1) k
               join iara.uk_itens i on i.codigo = k.codigo),
      'alunos', (select count(distinct student_id) from nec),
      'informados', (select count(distinct student_id) from nec where conteudo = 'UNIFORME' and tem is not null),
      'sem_tamanho', (select count(distinct student_id) from nec where conteudo = 'UNIFORME' and tem is null),
      'nota', 'Total = informado pela família ou pela unidade + estimado pela idade de quem ainda não informou. Sem a escolha do modelo, metade vai para shorts-saia e metade para bermuda.'));
end $$;

-- remessas: um pedido por unidade (aprovado pela SEDUC) com as peças por tamanho e os kits; o almoxarifado despacha e a unidade recebe
create or replace function api.uk_remessas_gerar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_ano integer := (p ->> 'ano')::int;
  v_cont text := coalesce(nullif(p ->> 'conteudo', ''), 'UNIFORME');
  v_estimar boolean := coalesce((p ->> 'estimar_faltantes')::boolean, false);
  u record;
  pe iara.pedidos;
  n_ped integer := 0;
  n_est integer := 0;
  n_nec integer := 0;
begin
  perform iara.require_perm('uk.manage');
  if v_cont not in ('UNIFORME', 'KIT') then raise exception 'Escolha uniforme ou kit.' using errcode = '22023'; end if;
  if not exists (select 1 from iara.uk_campanhas where ano = v_ano and situacao in ('COLETA_TAMANHOS', 'SEPARACAO', 'ENTREGA')) then
    raise exception 'A campanha de % não está em coleta, separação ou entrega.', v_ano using errcode = '22023'; end if;
  perform iara.uk_produtos_garantir();
  if v_estimar and v_cont = 'UNIFORME' then
    -- quem não informou até aqui recebe o tamanho estimado pela idade (fica marcado como estimativa; a família pode pedir troca)
    insert into iara.uk_tamanhos (student_id, ano, superior, inferior, calcado, modelo_inferior, canal, informado_por_label)
    select n.student_id, n.ano, s ->> 'superior', s ->> 'inferior', (s ->> 'calcado')::int, null, 'ESTIMATIVA', 'Estimativa pela idade'
    from iara.uk_necessidades n cross join lateral (select iara.uk_sugestao(n.student_id, n.ano) s) z
    where n.ano = v_ano and n.conteudo = 'UNIFORME' and n.situacao = 'AGUARDANDO_TAMANHO'
      and (p -> 'unit_ids' is null or n.unit_id in (select (x)::int from jsonb_array_elements_text(p -> 'unit_ids') x))
    on conflict do nothing;
    get diagnostics n_est = row_count;
    -- sem modelo escolhido: a calça vai, e o shorts-saia ou a bermuda fica para a troca na unidade
    update iara.uk_necessidades n set itens = iara.uk_montar_itens('UNIFORME', n.etapa, n.ampliacao, t), situacao = 'AGUARDANDO_MATERIAL', updated_at = now()
    from iara.uk_tamanhos t
    where t.student_id = n.student_id and t.ano = n.ano and t.canal = 'ESTIMATIVA' and n.ano = v_ano and n.conteudo = 'UNIFORME' and n.situacao = 'AGUARDANDO_TAMANHO';
  end if;
  for u in select n.unit_id, array_agg(n.id) ids from iara.uk_necessidades n
           where n.ano = v_ano and n.conteudo = v_cont and n.situacao = 'AGUARDANDO_MATERIAL' and n.pedido_id is null and n.unit_id is not null
             and jsonb_array_length(n.itens) > 0
             and (p -> 'unit_ids' is null or n.unit_id in (select (x)::int from jsonb_array_elements_text(p -> 'unit_ids') x))
           group by n.unit_id loop
    insert into iara.pedidos (unit_id, origem, situacao, prioridade, justificativa, solicitado_por_label, decidido_por_label, decidido_em)
    values (u.unit_id, 'ALMOXARIFADO', 'APROVADO', 'NORMAL', format('Uniformes e kits %s — remessa de %s por etapa e tamanho (%s aluno(s)).', v_ano, iara.uk_conteudo_rotulo(v_cont), cardinality(u.ids)),
            iara.my_label(), iara.my_label(), now())
    returning * into pe;
    insert into iara.pedido_itens (pedido_id, produto_codigo, quantidade_pedida, quantidade_aprovada)
    select pe.id, it ->> 'produto', sum((it ->> 'quantidade')::numeric), sum((it ->> 'quantidade')::numeric)
    from iara.uk_necessidades n, jsonb_array_elements(n.itens) it
    where n.id = any (u.ids) and it ->> 'produto' is not null group by it ->> 'produto';
    update iara.uk_necessidades set pedido_id = pe.id, updated_at = now() where id = any (u.ids);
    n_ped := n_ped + 1;
    n_nec := n_nec + cardinality(u.ids);
  end loop;
  update iara.uk_campanhas set situacao = 'SEPARACAO', updated_at = now() where ano = v_ano and situacao = 'COLETA_TAMANHOS' and n_ped > 0;
  perform iara.audit_event('UNIFORME_REMESSA', 'uk_campanha', v_ano::text, null,
    format('%s remessa(s) de %s geradas para %s aluno(s)%s.', n_ped, iara.uk_conteudo_rotulo(v_cont), n_nec, case when n_est > 0 then format(' (%s com tamanho estimado)', n_est) else '' end));
  return jsonb_build_object('pedidos', n_ped, 'necessidades', n_nec, 'estimados', n_est);
end $$;

-- quando a unidade confere e recebe a remessa, o material fica disponível e a família é avisada
create or replace function iara.tg_uk_pedido_recebido() returns trigger
language plpgsql security definer set search_path = iara, public
as $$
begin
  if new.situacao = 'RECEBIDO' and old.situacao = 'EM_TRANSPORTE' then
    perform iara.uk_liberar(array(select id from iara.uk_necessidades where pedido_id = new.id and situacao = 'AGUARDANDO_MATERIAL'));
  end if;
  return null;
end $$;
drop trigger if exists uk_pedido_recebido on iara.pedidos;
create trigger uk_pedido_recebido after update of situacao on iara.pedidos
  for each row execute function iara.tg_uk_pedido_recebido();

-- disparo em lotes: pedido de tamanho ou lembrete de retirada, por rede, unidade ou etapa
create or replace function api.uk_disparo_criar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_tipo text := p ->> 'tipo';
  v_ano integer := (p ->> 'ano')::int;
  v_unit integer := case when iara.my_scope() = 'UNIT' then iara.my_unit() else nullif(p ->> 'unit_id', '')::int end;
  v_etapa text := nullif(p ->> 'etapa', '');
  c iara.uk_campanhas;
  d iara.uk_disparos;
  x record;
  n integer := 0;
  v_int integer := coalesce((iara.uk_param('intervalo_segundos'))::int, 20);
begin
  if not (iara.has_perm('uk.manage') or iara.has_perm('uk.unidade')) then perform iara.require_perm('uk.manage'); end if;
  if iara.my_scope() = 'UNIT' and not iara.has_perm('uk.unidade') then raise exception 'Sem permissão.' using errcode = '42501'; end if;
  if v_tipo not in ('TAMANHO', 'LEMBRETE_RETIRADA') then raise exception 'Escolha: pedido de tamanho ou lembrete de retirada.' using errcode = '22023'; end if;
  select * into c from iara.uk_campanhas where ano = v_ano;
  if c.id is null then raise exception 'Campanha não encontrada.' using errcode = 'P0002'; end if;
  if v_tipo = 'TAMANHO' and not (c.situacao = 'COLETA_TAMANHOS' or (c.situacao in ('SEPARACAO', 'ENTREGA') and c.coleta_fim >= iara.hoje_local())) then
    raise exception 'A coleta de tamanhos de % não está aberta.', v_ano using errcode = '22023'; end if;
  insert into iara.uk_disparos (tipo, ano, filtro, criado_por_label) values (v_tipo, v_ano, jsonb_build_object('unit_id', v_unit, 'etapa', v_etapa), iara.my_label())
  returning * into d;
  for x in select distinct on (n.student_id) n.student_id, n.unit_id, n.prazo_retirada, s.full_name
           from iara.uk_necessidades n join iara.students s on s.id = n.student_id
           where n.ano = v_ano and (v_unit is null or n.unit_id = v_unit) and (v_etapa is null or n.etapa = v_etapa)
             and case v_tipo when 'TAMANHO' then n.situacao = 'AGUARDANDO_TAMANHO' else n.situacao = 'DISPONIVEL' end
             -- não repete: quem recebeu o mesmo aviso nas últimas 48 h fica fora
             and not exists (select 1 from iara.uk_avisos a where a.student_id = n.student_id and a.tipo = v_tipo and a.enviado_em > now() - interval '48 hours')
           order by n.student_id loop
    perform iara.uk_aviso_criar(x.student_id, v_tipo,
      case v_tipo when 'TAMANHO' then format('Uniforme %s: informe os tamanhos', v_ano) else 'Lembrete: uniforme e kit esperando retirada' end,
      case v_tipo
        when 'TAMANHO' then format('Informe os tamanhos do uniforme %s de %s até %s: parte de cima, parte de baixo, número do calçado e o modelo (shorts-saia ou bermuda). Responda aqui com “tamanho do uniforme” ou pelo portal (Vida escolar → Uniforme e kit).',
                                   v_ano, split_part(x.full_name, ' ', 1), coalesce(to_char(c.coleta_fim, 'DD/MM/YYYY'), 'o fim da coleta'))
        else format('O material de %s está esperando na unidade até %s. Leve o código de retirada (pergunte aqui “código do uniforme”) ou documento com foto.',
                    split_part(x.full_name, ' ', 1), to_char(x.prazo_retirada, 'DD/MM/YYYY')) end,
      v_ano, x.unit_id, '{}', d.id);
    n := n + 1;
  end loop;
  update iara.uk_disparos set total = n where id = d.id;
  perform iara.audit_event('UNIFORME_DISPARO', 'uk_disparo', d.id::text, v_unit, format('Disparo “%s” %s: %s família(s).', lower(replace(v_tipo, '_', ' ')), v_ano, n));
  return jsonb_build_object('ok', true, 'id', d.id, 'total', n, 'intervalo_segundos', v_int,
    'previsao_horas', round(n * v_int / 3600.0, 1));
end $$;

create or replace function api.uk_disparos(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('uk.read');
  return jsonb_build_object(
    'fila', jsonb_build_object('agendados', (select count(*) from iara.uk_avisos where whatsapp_status = 'AGENDADO'),
             'ultimo_previsto', (select max(agendado_para) from iara.uk_avisos where whatsapp_status = 'AGENDADO'),
             'enviados_24h', (select count(*) from iara.uk_avisos where whatsapp_status in ('ENVIADO', 'SIMULADO') and whatsapp_em > now() - interval '24 hours')),
    'parametros', (select jsonb_object_agg(chave, valor) from iara.uk_parametros where chave in ('intervalo_segundos', 'horario_inicio', 'horario_fim')),
    'disparos', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'tipo', d.tipo, 'ano', d.ano, 'total', d.total, 'criado_por', d.criado_por_label, 'criado_em', d.created_at,
                   'unidade', (select short_name from iara.education_units where id = (d.filtro ->> 'unit_id')::int), 'etapa', iara.uk_etapa_rotulo(d.filtro ->> 'etapa'),
                   'enviados', (select count(*) from iara.uk_avisos a where a.disparo_id = d.id and a.whatsapp_status = 'ENVIADO'),
                   'simulados', (select count(*) from iara.uk_avisos a where a.disparo_id = d.id and a.whatsapp_status = 'SIMULADO'),
                   'sem_whatsapp', (select count(*) from iara.uk_avisos a where a.disparo_id = d.id and a.whatsapp_status = 'SEM_WHATSAPP'),
                   'na_fila', (select count(*) from iara.uk_avisos a where a.disparo_id = d.id and a.whatsapp_status = 'AGENDADO'),
                   'cientes', (select count(*) from iara.uk_avisos a where a.disparo_id = d.id and a.ciente_em is not null)) order by d.created_at desc), '[]')
                 from (select * from iara.uk_disparos where iara.my_scope() <> 'UNIT' or (filtro ->> 'unit_id')::int = iara.my_unit() order by created_at desc limit 30) d));
end $$;

-- rotina de hora em hora: alunos novos, unidade/etapa das necessidades, lembrete antes do fim do prazo
create or replace function iara.uk_rotina() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  c record;
  v jsonb := '{}';
  x record;
  v_dias integer := coalesce((iara.uk_param('lembrete_dias'))::int, 7);
  n integer := 0;
begin
  for c in select id, ano from iara.uk_campanhas where situacao in ('COLETA_TAMANHOS', 'SEPARACAO', 'ENTREGA') loop
    v := v || jsonb_build_object(c.ano::text, iara.uk_gerar(c.id));
  end loop;
  -- lembrete automático, uma vez, quando faltam poucos dias para o fim do prazo
  for x in select distinct on (n.student_id) n.student_id, n.ano, n.unit_id, n.prazo_retirada
           from iara.uk_necessidades n
           where n.situacao = 'DISPONIVEL' and n.prazo_retirada between iara.hoje_local() and iara.hoje_local() + v_dias
             and not exists (select 1 from iara.uk_avisos a where a.student_id = n.student_id and a.ano = n.ano and a.tipo = 'LEMBRETE_RETIRADA'
                             and a.enviado_em > n.disponivel_em)
           order by n.student_id loop
    perform iara.uk_aviso_criar(x.student_id, 'LEMBRETE_RETIRADA', 'Lembrete: uniforme e kit esperando retirada',
      format('Faltam poucos dias: o material de %s fica na unidade até %s. Leve o código de retirada ou documento com foto.',
             (select split_part(full_name, ' ', 1) from iara.students where id = x.student_id), to_char(x.prazo_retirada, 'DD/MM/YYYY')),
      x.ano, x.unit_id);
    n := n + 1;
  end loop;
  return v || jsonb_build_object('lembretes', n);
end $$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('iara-uniformes-envios', '* * * * *', $c$select iara.uk_envios_processar()$c$);
    perform cron.schedule('iara-uniformes-rotina', '23 * * * *', $c$select iara.uk_rotina()$c$);
  end if;
end $$;

-- 10. LGPD: classificação das colunas pessoais ---------------------------------------------------------------------------------------
insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('uk_tamanhos', 'superior', 'PESSOAL', 'medida do corpo', 'compra e entrega do uniforme', 'acesso pela unidade, SEDUC e família'),
  ('uk_tamanhos', 'inferior', 'PESSOAL', 'medida do corpo', 'compra e entrega do uniforme', 'acesso pela unidade, SEDUC e família'),
  ('uk_tamanhos', 'calcado', 'PESSOAL', 'medida do corpo', 'compra e entrega do uniforme', 'acesso pela unidade, SEDUC e família'),
  ('uk_tamanhos', 'informado_por_label', 'PESSOAL', 'autoria', 'rastreabilidade', 'só servidores'),
  ('uk_necessidades', 'motivo', 'PESSOAL', 'relato da família ou da unidade', 'decidir troca, reposição ou material adaptado', 'unidade e SEDUC'),
  ('uk_necessidades', 'decisao_motivo', 'PESSOAL', 'decisão administrativa', 'resposta à família', 'unidade, SEDUC e família'),
  ('uk_necessidades', 'retirada_por_nome', 'PESSOAL', 'identificação de quem retirou', 'comprovar a entrega', 'unidade, SEDUC e família'),
  ('uk_necessidades', 'retirada_por_parentesco', 'PESSOAL', 'vínculo com a criança', 'comprovar a entrega', 'unidade, SEDUC e família'),
  ('uk_necessidades', 'retirada_documento', 'PESSOAL', 'documento (só os últimos números)', 'comprovar a entrega sem código', 'unidade e SEDUC'),
  ('uk_necessidades', 'registrado_por_label', 'PESSOAL', 'autoria', 'rastreabilidade', 'só servidores'),
  ('uk_necessidades', 'solicitante_label', 'PESSOAL', 'autoria', 'rastreabilidade', 'só servidores'),
  ('uk_necessidades', 'decidido_por_label', 'PESSOAL', 'autoria', 'rastreabilidade', 'só servidores'),
  ('uk_necessidades', 'conteudo', 'INTERNO', 'tipo de material', 'uniforme, kit ou material adaptado', null),
  ('uk_necessidades', 'observacao', 'PESSOAL', 'anotação da unidade', 'entrega', 'unidade e SEDUC'),
  ('uk_avisos', 'texto', 'PESSOAL', 'comunicação à família', 'avisar tamanho e retirada', 'família, unidade e SEDUC'),
  ('uk_avisos', 'titulo', 'INTERNO', 'comunicação à família', 'avisar tamanho e retirada', null),
  ('uk_codigos', 'codigo', 'PESSOAL', 'credencial de retirada', 'conferir quem retira', 'família e unidade; tentativas inválidas auditadas'),
  ('uk_campanhas', 'observacao', 'INTERNO', 'planejamento', 'campanha', null),
  ('uk_kit_itens', 'especificacao', 'PUBLICO', 'composição oficial', 'transparência', null),
  ('uk_itens', 'descricao', 'PUBLICO', 'composição oficial', 'transparência', null),
  ('uk_parametros', 'descricao', 'INTERNO', 'parâmetro', 'operação', null),
  ('uk_disparos', 'criado_por_label', 'PESSOAL', 'autoria', 'rastreabilidade', 'só servidores')
on conflict (tabela, coluna) do update set nivel = excluded.nivel, categoria = excluded.categoria, finalidade = excluded.finalidade, protecao = excluded.protecao;

select iara.uk_produtos_garantir();

revoke all on function iara.uk_envios_processar(), iara.uk_rotina(), iara.uk_gerar(uuid), iara.uk_liberar(uuid[]),
  iara.uk_aviso_criar(uuid, text, text, text, integer, integer, uuid[], uuid), iara.uk_tamanho_gravar(uuid, integer, jsonb, text) from public;

commit;
