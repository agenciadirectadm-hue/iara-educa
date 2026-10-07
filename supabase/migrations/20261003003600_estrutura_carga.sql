-- IARA Educa — 036 · Estrutura de carga dos dados reais (seção 9 do documento de estrutura; itens 21 a 23)
-- Os dados reais entram SEMPRE por este caminho, nunca por SQL avulso:
--   receber (arquivo → área de preparação, com hash) → validar → conciliar → promover (repetível) → [reverter]
-- · schema `carga` isolado: sem acesso pela API (só o operador de carga, pela API de gerenciamento);
-- · cada registro guarda os dados de origem, erros, avisos, o que foi feito (criado/atualizado) e o valor anterior;
-- · a correspondência código da fonte ↔ identificador interno mantém o MESMO id a cada nova carga (OPS-01);
-- · promover duas vezes não duplica; reverter desfaz o lote (na ordem inversa das dependências);
-- · lotes de ensaio (arquivos fictícios) só podem ser promovidos dentro de carga.ensaiar(), que reverte tudo.
-- Ordem dos domínios: UNIDADES → TURMAS → SERVIDORES → RESPONSAVEIS → ALUNOS → VINCULOS → MATRICULAS → FILA.
begin;

create schema if not exists carga;
revoke all on schema carga from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then execute 'revoke all on schema carga from anon, authenticated'; end if;
end $$;

-- 1. Tabelas ------------------------------------------------------------------------------------------------------
create table if not exists carga.dominios (
  codigo text primary key,
  ordem smallint not null,
  nome text not null,
  depende_de text[] not null default '{}',
  tabela text not null
);

create table if not exists carga.layouts (
  dominio text not null references carga.dominios(codigo),
  ordem smallint not null,
  campo text not null,
  tipo text not null check (tipo in ('texto', 'inteiro', 'decimal', 'data', 'data_hora', 'sim_nao', 'cpf', 'nis', 'cep', 'email', 'telefone', 'lista', 'coordenada')),
  obrigatorio boolean not null default false,
  chave boolean not null default false,
  valores text[],
  descricao text not null,
  exemplo text,
  primary key (dominio, campo)
);

create table if not exists carga.lotes (
  id bigserial primary key,
  codigo text not null unique,
  dominio text not null references carga.dominios(codigo),
  arquivo text not null,
  hash_sha256 text,
  origem text not null,
  data_referencia date not null,
  responsavel text not null,
  ensaio boolean not null default false,
  situacao text not null default 'RECEBIDO'
    check (situacao in ('RECEBIDO', 'VALIDADO', 'COM_ERROS', 'PROMOVIDO', 'REVERTIDO', 'DESCARTADO')),
  linhas integer not null default 0,
  linhas_ok integer,
  linhas_aviso integer,
  linhas_erro integer,
  conciliacao jsonb,
  resultado jsonb,
  recebido_em timestamptz not null default now(),
  validado_em timestamptz,
  promovido_em timestamptz,
  revertido_em timestamptz,
  observacoes text
);

create table if not exists carga.registros (
  lote_id bigint not null references carga.lotes(id) on delete cascade,
  linha integer not null,
  chave text,
  dados jsonb not null,
  situacao text not null default 'PENDENTE' check (situacao in ('PENDENTE', 'OK', 'AVISO', 'ERRO', 'PROMOVIDO', 'REVERTIDO')),
  erros jsonb not null default '[]'::jsonb,
  avisos jsonb not null default '[]'::jsonb,
  acao text check (acao in ('CRIADO', 'ATUALIZADO')),
  destino_id text,
  antes jsonb,
  primary key (lote_id, linha)
);
create index if not exists registros_chave_idx on carga.registros (lote_id, chave);

create table if not exists carga.correspondencia (
  dominio text not null references carga.dominios(codigo),
  chave text not null,
  id_interno text not null,
  origem text,
  lote_id bigint references carga.lotes(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  primary key (dominio, chave)
);
create index if not exists correspondencia_id_idx on carga.correspondencia (dominio, id_interno);

-- 2. Domínios e dicionário de dados (layouts dos arquivos) -------------------------------------------------------------
insert into carga.dominios (codigo, ordem, nome, depende_de, tabela) values
  ('UNIDADES', 1, 'Unidades educacionais (escolas e CMEIs)', '{}', 'education_units'),
  ('TURMAS', 2, 'Turmas do ano letivo', '{UNIDADES}', 'classes'),
  ('SERVIDORES', 3, 'Servidores e lotação', '{UNIDADES}', 'staff'),
  ('RESPONSAVEIS', 4, 'Responsáveis (famílias)', '{}', 'guardians'),
  ('ALUNOS', 5, 'Alunos (registro permanente)', '{}', 'students'),
  ('VINCULOS', 6, 'Vínculos aluno–responsável', '{ALUNOS,RESPONSAVEIS}', 'student_guardians'),
  ('MATRICULAS', 7, 'Matrículas do ano letivo', '{ALUNOS,TURMAS}', 'enrollments'),
  ('FILA', 8, 'Fila de espera da Central de Vagas', '{ALUNOS,UNIDADES}', 'waiting_list_entries')
on conflict (codigo) do update set ordem = excluded.ordem, nome = excluded.nome, depende_de = excluded.depende_de, tabela = excluded.tabela;

delete from carga.layouts;
insert into carga.layouts (dominio, ordem, campo, tipo, obrigatorio, chave, valores, descricao, exemplo) values
  -- UNIDADES
  ('UNIDADES', 1, 'codigo_unidade', 'texto', true, true, null, 'Código estável da unidade no sistema oficial da SEDUC (não muda de um ano para outro)', 'SEDUC-0042'),
  ('UNIDADES', 2, 'codigo_inep', 'texto', false, false, null, 'Código INEP da unidade (8 dígitos)', '41100123'),
  ('UNIDADES', 3, 'nome', 'texto', true, false, null, 'Nome oficial da unidade', 'CMEI Galdino de Andrade'),
  ('UNIDADES', 4, 'nome_curto', 'texto', false, false, null, 'Nome curto para listas e mapas', 'Galdino de Andrade'),
  ('UNIDADES', 5, 'tipo', 'lista', true, false, '{CMEI,ESCOLA}', 'Natureza da unidade (conveniadas e a Secretaria entram na etapa P1)', 'CMEI'),
  ('UNIDADES', 6, 'logradouro', 'texto', false, false, null, 'Rua/avenida', 'Rua das Flores'),
  ('UNIDADES', 7, 'numero', 'texto', false, false, null, 'Número', '120'),
  ('UNIDADES', 8, 'bairro', 'texto', false, false, null, 'Bairro', 'Zona 7'),
  ('UNIDADES', 9, 'cep', 'cep', false, false, null, 'CEP (8 dígitos)', '87020-000'),
  ('UNIDADES', 10, 'lat', 'coordenada', true, false, null, 'Latitude (graus decimais)', '-23.4210'),
  ('UNIDADES', 11, 'lng', 'coordenada', true, false, null, 'Longitude (graus decimais)', '-51.9331'),
  ('UNIDADES', 12, 'telefone', 'telefone', false, false, null, 'Telefone da unidade', '(44) 3222-0000'),
  ('UNIDADES', 13, 'diretor', 'texto', false, false, null, 'Nome da direção', 'Ana Souza'),
  ('UNIDADES', 14, 'situacao', 'lista', false, false, '{ATIVA,A_VALIDAR,SEM_TURMAS}', 'Situação da unidade (padrão: ATIVA)', 'ATIVA'),
  -- TURMAS
  ('TURMAS', 1, 'codigo_turma', 'texto', true, true, null, 'Código estável da turma na fonte oficial', 'T2026-0042-PREA'),
  ('TURMAS', 2, 'codigo_unidade', 'texto', true, false, null, 'Unidade da turma (código da fonte ou código INEP)', 'SEDUC-0042'),
  ('TURMAS', 3, 'ano_letivo', 'inteiro', true, false, null, 'Ano letivo', '2026'),
  ('TURMAS', 4, 'serie', 'lista', true, false, '{CRECHE,PRE,EF1,EF2,EF3,EF4,EF5,EJA_AI}', 'Série/faixa', 'PRE'),
  ('TURMAS', 5, 'nome', 'texto', true, false, null, 'Nome da turma', 'Pré-escola A'),
  ('TURMAS', 6, 'turno', 'lista', true, false, '{MANHA,TARDE,NOITE,INTEGRAL}', 'Turno', 'TARDE'),
  ('TURMAS', 7, 'sala', 'texto', false, false, null, 'Sala física', 'Sala 04'),
  ('TURMAS', 8, 'capacidade_autorizada', 'inteiro', true, false, null, 'Capacidade autorizada (vagas)', '24'),
  ('TURMAS', 9, 'situacao', 'lista', false, false, '{ATIVA,EM_REORGANIZACAO,ENCERRADA}', 'Situação (padrão: ATIVA)', 'ATIVA'),
  -- SERVIDORES
  ('SERVIDORES', 1, 'matricula_funcional', 'texto', true, true, null, 'Matrícula funcional (RH)', '123456'),
  ('SERVIDORES', 2, 'nome', 'texto', true, false, null, 'Nome completo', 'Daniela Nunes Andrade'),
  ('SERVIDORES', 3, 'codigo_unidade', 'texto', false, false, null, 'Unidade de lotação (código da fonte ou INEP)', 'SEDUC-0042'),
  ('SERVIDORES', 4, 'funcao', 'lista', true, false, '{PROFESSOR,EDUCADOR,AUXILIAR,APOIO,AEE,ESTAGIARIO,SUBSTITUTO}', 'Função', 'PROFESSOR'),
  ('SERVIDORES', 5, 'vinculo', 'texto', false, false, null, 'Tipo de vínculo (efetivo, PSS...)', 'Efetivo'),
  -- RESPONSAVEIS
  ('RESPONSAVEIS', 1, 'codigo_responsavel', 'texto', true, true, null, 'Código estável do responsável na fonte oficial', 'R-000123'),
  ('RESPONSAVEIS', 2, 'nome', 'texto', true, false, null, 'Nome completo', 'Maria Santos Oliveira'),
  ('RESPONSAVEIS', 3, 'cpf', 'cpf', false, false, null, 'CPF (inválido é descartado com aviso)', '123.456.789-09'),
  ('RESPONSAVEIS', 4, 'nis', 'nis', false, false, null, 'NIS/PIS (inválido é descartado com aviso)', '12345678919'),
  ('RESPONSAVEIS', 5, 'rg', 'texto', false, false, null, 'RG', '12.345.678-9'),
  ('RESPONSAVEIS', 6, 'data_nascimento', 'data', false, false, null, 'Data de nascimento (AAAA-MM-DD ou DD/MM/AAAA)', '15/04/1990'),
  ('RESPONSAVEIS', 7, 'sexo', 'lista', false, false, '{F,M}', 'Sexo', 'F'),
  ('RESPONSAVEIS', 8, 'email', 'email', false, false, null, 'E-mail', 'maria@exemplo.com'),
  ('RESPONSAVEIS', 9, 'telefone', 'telefone', false, false, null, 'Telefone principal', '(44) 99999-0000'),
  ('RESPONSAVEIS', 10, 'whatsapp', 'telefone', false, false, null, 'WhatsApp', '(44) 99999-0000'),
  ('RESPONSAVEIS', 11, 'estado_civil', 'texto', false, false, null, 'Estado civil', 'Solteira'),
  ('RESPONSAVEIS', 12, 'escolaridade', 'texto', false, false, null, 'Escolaridade', 'Médio completo'),
  ('RESPONSAVEIS', 13, 'ocupacao', 'texto', false, false, null, 'Ocupação', 'Auxiliar administrativa'),
  ('RESPONSAVEIS', 14, 'renda_familiar', 'decimal', false, false, null, 'Renda familiar mensal (R$)', '2500,00'),
  ('RESPONSAVEIS', 15, 'cadunico', 'sim_nao', false, false, null, 'Inscrição ativa no CadÚnico (S/N)', 'S'),
  ('RESPONSAVEIS', 16, 'mae_solo', 'sim_nao', false, false, null, 'Mãe solo declarada (S/N)', 'N'),
  ('RESPONSAVEIS', 17, 'pessoas_domicilio', 'inteiro', false, false, null, 'Pessoas no domicílio', '4'),
  ('RESPONSAVEIS', 18, 'logradouro', 'texto', false, false, null, 'Rua/avenida da residência', 'Rua das Flores'),
  ('RESPONSAVEIS', 19, 'numero', 'texto', false, false, null, 'Número', '120'),
  ('RESPONSAVEIS', 20, 'complemento', 'texto', false, false, null, 'Complemento', 'Apto 2'),
  ('RESPONSAVEIS', 21, 'bairro', 'texto', false, false, null, 'Bairro', 'Zona 7'),
  ('RESPONSAVEIS', 22, 'cep', 'cep', false, false, null, 'CEP', '87020-000'),
  ('RESPONSAVEIS', 23, 'lat', 'coordenada', false, false, null, 'Latitude da residência (vazio: geocodificar depois)', '-23.4210'),
  ('RESPONSAVEIS', 24, 'lng', 'coordenada', false, false, null, 'Longitude da residência', '-51.9331'),
  -- ALUNOS
  ('ALUNOS', 1, 'codigo_aluno', 'texto', true, true, null, 'Registro permanente do aluno na fonte oficial (não muda entre anos)', 'A-2024-000123'),
  ('ALUNOS', 2, 'nome', 'texto', true, false, null, 'Nome completo', 'Davi Santos Oliveira'),
  ('ALUNOS', 3, 'nome_social', 'texto', false, false, null, 'Nome social', null),
  ('ALUNOS', 4, 'data_nascimento', 'data', true, false, null, 'Data de nascimento', '2022-05-10'),
  ('ALUNOS', 5, 'sexo', 'lista', false, false, '{F,M}', 'Sexo', 'M'),
  ('ALUNOS', 6, 'cor_raca', 'lista', false, false, '{BRANCA,PRETA,PARDA,AMARELA,INDIGENA,NAO_DECLARADA}', 'Cor/raça (declarada)', 'PARDA'),
  ('ALUNOS', 7, 'cpf', 'cpf', false, false, null, 'CPF da criança', null),
  ('ALUNOS', 8, 'nis', 'nis', false, false, null, 'NIS da criança', null),
  ('ALUNOS', 9, 'certidao_nascimento', 'texto', false, false, null, 'Matrícula da certidão de nascimento', null),
  ('ALUNOS', 10, 'cartao_sus', 'texto', false, false, null, 'Cartão SUS', null),
  ('ALUNOS', 11, 'codigo_inep_aluno', 'texto', false, false, null, 'ID do aluno no Censo/INEP', null),
  ('ALUNOS', 12, 'nacionalidade', 'lista', false, false, '{BRASILEIRA,NATURALIZADA,ESTRANGEIRA}', 'Nacionalidade', 'BRASILEIRA'),
  ('ALUNOS', 13, 'nome_mae', 'texto', false, false, null, 'Filiação 1', 'Maria Santos Oliveira'),
  ('ALUNOS', 14, 'nome_pai', 'texto', false, false, null, 'Filiação 2', null),
  ('ALUNOS', 15, 'logradouro', 'texto', false, false, null, 'Rua/avenida da residência', 'Rua das Flores'),
  ('ALUNOS', 16, 'numero', 'texto', false, false, null, 'Número', '120'),
  ('ALUNOS', 17, 'complemento', 'texto', false, false, null, 'Complemento', null),
  ('ALUNOS', 18, 'bairro', 'texto', false, false, null, 'Bairro', 'Zona 7'),
  ('ALUNOS', 19, 'cep', 'cep', false, false, null, 'CEP', '87020-000'),
  ('ALUNOS', 20, 'lat', 'coordenada', false, false, null, 'Latitude da residência (vazio: geocodificar depois)', '-23.4210'),
  ('ALUNOS', 21, 'lng', 'coordenada', false, false, null, 'Longitude da residência', '-51.9331'),
  ('ALUNOS', 22, 'transporte', 'sim_nao', false, false, null, 'Usa ou precisa de transporte escolar (S/N)', 'N'),
  ('ALUNOS', 23, 'aee', 'sim_nao', false, false, null, 'Atendimento educacional especializado (S/N) — o laudo entra em etapa própria, protegida', 'N'),
  -- VINCULOS
  ('VINCULOS', 1, 'codigo_aluno', 'texto', true, false, null, 'Aluno (código da fonte, já carregado)', 'A-2024-000123'),
  ('VINCULOS', 2, 'codigo_responsavel', 'texto', true, false, null, 'Responsável (código da fonte, já carregado)', 'R-000123'),
  ('VINCULOS', 3, 'parentesco', 'lista', true, false, '{MAE,PAI,AVO,TIA,TIO,IRMAO,PADRASTO,MADRASTA,TUTOR_LEGAL,OUTRO}', 'Parentesco', 'MAE'),
  ('VINCULOS', 4, 'principal', 'sim_nao', false, false, null, 'Responsável principal (S/N)', 'S'),
  ('VINCULOS', 5, 'pode_buscar', 'sim_nao', false, false, null, 'Pode buscar a criança (S/N)', 'S'),
  ('VINCULOS', 6, 'recebe_avisos', 'sim_nao', false, false, null, 'Recebe avisos (S/N)', 'S'),
  ('VINCULOS', 7, 'situacao_legal', 'lista', false, false, '{CONFIRMADO,DECLARADO}', 'Situação da autoridade legal (padrão: DECLARADO)', 'CONFIRMADO'),
  ('VINCULOS', 8, 'inicio', 'data', false, false, null, 'Início do vínculo', '2024-02-01'),
  ('VINCULOS', 9, 'fim', 'data', false, false, null, 'Fim do vínculo (vazio = vigente)', null),
  -- MATRICULAS
  ('MATRICULAS', 1, 'codigo_matricula', 'texto', true, true, null, 'Código da matrícula do ano na fonte oficial', 'M2026-000987'),
  ('MATRICULAS', 2, 'codigo_aluno', 'texto', true, false, null, 'Aluno (código da fonte, já carregado)', 'A-2024-000123'),
  ('MATRICULAS', 3, 'codigo_turma', 'texto', true, false, null, 'Turma (código da fonte, já carregada)', 'T2026-0042-PREA'),
  ('MATRICULAS', 4, 'ano_letivo', 'inteiro', true, false, null, 'Ano letivo', '2026'),
  ('MATRICULAS', 5, 'situacao', 'lista', true, false, '{ATIVA,PRE_MATRICULA,TRANSFERENCIA_PENDENTE,TRANSFERIDA,CANCELADA,CONCLUIDA,INATIVA}', 'Situação da matrícula', 'ATIVA'),
  ('MATRICULAS', 6, 'data_matricula', 'data', false, false, null, 'Data da matrícula', '2026-01-20'),
  ('MATRICULAS', 7, 'inicio', 'data', false, false, null, 'Início das aulas na turma', '2026-02-02'),
  ('MATRICULAS', 8, 'fim', 'data', false, false, null, 'Saída da turma', null),
  ('MATRICULAS', 9, 'tipo_entrada', 'lista', false, false, '{NOVA,RENOVACAO,TRANSFERENCIA,OFERTA_FILA}', 'Como entrou', 'RENOVACAO'),
  -- FILA
  ('FILA', 1, 'codigo_inscricao', 'texto', true, true, null, 'Código da inscrição na Central de Vagas', 'F-2026-004512'),
  ('FILA', 2, 'codigo_aluno', 'texto', true, false, null, 'Criança (código da fonte, já carregada)', 'A-2025-000456'),
  ('FILA', 3, 'codigo_unidade', 'texto', true, false, null, 'Unidade pretendida (código da fonte ou INEP)', 'SEDUC-0042'),
  ('FILA', 4, 'serie', 'lista', true, false, '{CRECHE,PRE,EF1,EF2,EF3,EF4,EF5,EJA_AI}', 'Série/faixa pretendida', 'CRECHE'),
  ('FILA', 5, 'turno_preferido', 'lista', false, false, '{MANHA,TARDE,INTEGRAL}', 'Turno preferido', 'INTEGRAL'),
  ('FILA', 6, 'integral', 'sim_nao', false, false, null, 'Pede período integral (S/N)', 'S'),
  ('FILA', 7, 'categoria', 'lista', false, false, '{SEM_ATENDIMENTO,AGUARDA_TRANSFERENCIA,PARCIAL_PARA_INTEGRAL,UNIDADE_PREFERENCIAL,RECUSOU_OFERTA,DEMANDA_FUTURA}', 'Categoria da demanda (padrão: SEM_ATENDIMENTO)', 'SEM_ATENDIMENTO'),
  ('FILA', 8, 'data_solicitacao', 'data_hora', true, false, null, 'Data e hora da solicitação — desempate da IN nº 025/2025', '2026-03-04 09:15'),
  ('FILA', 9, 'posicao_oficial', 'inteiro', false, false, null, 'Posição na lista oficial (para conferir a ordem)', '12'),
  ('FILA', 10, 'pontuacao_oficial', 'decimal', false, false, null, 'Pontuação na lista oficial (para conferir)', '40'),
  ('FILA', 11, 'situacao', 'lista', false, false, '{AGUARDANDO,SUSPENSA}', 'Situação (padrão: AGUARDANDO; ofertas em aberto entram em etapa própria)', 'AGUARDANDO');

-- 3. Conversores --------------------------------------------------------------------------------------------------------
create or replace function carga.txt(d jsonb, k text) returns text
language sql immutable as $$ select nullif(btrim(d ->> k), '') $$;

create or replace function carga.data(p text) returns date
language plpgsql stable as $$
begin
  if p is null or btrim(p) = '' then return null; end if;
  p := btrim(p);
  if p ~ '^\d{4}-\d{2}-\d{2}' then return to_date(left(p, 10), 'YYYY-MM-DD'); end if;
  if p ~ '^\d{2}/\d{2}/\d{4}' then return to_date(left(p, 10), 'DD/MM/YYYY'); end if;
  return null;
exception when others then
  return null;
end $$;

-- data e hora (desempate da fila): aceita só a data (00:00, horário de Brasília)
create or replace function carga.data_hora(p text) returns timestamptz
language plpgsql stable as $$
declare
  v_data date := carga.data(p);
  v_hora text := substring(btrim(coalesce(p, '')) from '\d{1,2}:\d{2}(:\d{2})?');
begin
  if v_data is null then return null; end if;
  return (v_data::text || ' ' || coalesce(v_hora, '00:00') || ' America/Sao_Paulo')::timestamptz;
exception when others then
  return null;
end $$;

create or replace function carga.sim(p text) returns boolean
language sql immutable as $$
  select case upper(translate(btrim(coalesce(p, '')), 'ãÃ', 'aA'))
           when 'S' then true when 'SIM' then true when '1' then true when 'TRUE' then true when 'X' then true
           when 'N' then false when 'NAO' then false when '0' then false when 'FALSE' then false
         end
$$;

-- número com vírgula decimal ("2.500,00") ou ponto ("2500.00")
create or replace function carga.num(p text) returns numeric
language plpgsql immutable as $$
begin
  if p is null or btrim(p) = '' then return null; end if;
  p := btrim(p);
  if p ~ ',' then p := replace(replace(p, '.', ''), ',', '.'); end if;
  return p::numeric;
exception when others then
  return null;
end $$;

create or replace function carga.coord(p text) returns double precision
language plpgsql immutable as $$
begin
  return nullif(replace(btrim(p), ',', '.'), '')::double precision;
exception when others then
  return null;
end $$;

-- código de série → nível (e etapa)
create or replace function carga.serie(p text) returns iara.grade_levels
language sql stable as $$ select * from iara.grade_levels where tenant_id = 1 and code = upper(btrim(p)) limit 1 $$;

alter table carga.registros add column if not exists limpo jsonb;

-- uma matrícula ativa por aluno e ano (a carga e o fluxo de oferta não podem criar duas)
create unique index if not exists enrollments_uma_ativa_por_ano on iara.enrollments (student_id, school_year) where status = 'ACTIVE';

-- 4. Referências --------------------------------------------------------------------------------------------------------
-- id interno de um código já carregado; UNIDADES aceita também o código INEP das unidades oficiais já existentes
create or replace function carga.ref(p_dominio text, p_chave text) returns text
language plpgsql stable as $$
declare
  v text;
begin
  if p_chave is null or btrim(p_chave) = '' then return null; end if;
  select id_interno into v from carga.correspondencia where dominio = p_dominio and chave = btrim(p_chave);
  if v is null and p_dominio = 'UNIDADES' then
    select id::text into v from iara.education_units where inep_code = btrim(p_chave) order by id limit 1;
  end if;
  return v;
end $$;

-- território (macrorregião/distrito) e bairro de um ponto
create or replace function carga.territorio(p_lat double precision, p_lng double precision, p_kinds text[]) returns integer
language sql stable as $$
  select t.id from iara.territories t
  where p_lat is not null and t.kind = any (p_kinds) and extensions.st_covers(t.geom, iara.point(p_lat, p_lng))
  order by array_position(p_kinds, t.kind) limit 1
$$;

-- 5. Receber ---------------------------------------------------------------------------------------------------------------
-- p: { lote, dominio, arquivo, hash, origem, data_referencia, responsavel, ensaio, observacoes, linhas: [ {coluna: valor} ] }
create or replace function carga.receber(p jsonb) returns jsonb
language plpgsql as $$
declare
  v_lote carga.lotes;
  v_dom text := upper(btrim(coalesce(p ->> 'dominio', '')));
  v_base integer;
  v_n integer;
begin
  if not exists (select 1 from carga.dominios where codigo = v_dom) then
    raise exception 'Domínio desconhecido: "%". Use: %.', v_dom, (select string_agg(codigo, ', ' order by ordem) from carga.dominios) using errcode = '22023';
  end if;
  if coalesce(p ->> 'lote', '') = '' then
    raise exception 'Informe o código do lote.' using errcode = '22023';
  end if;
  select * into v_lote from carga.lotes where codigo = p ->> 'lote';
  if not found then
    insert into carga.lotes (codigo, dominio, arquivo, hash_sha256, origem, data_referencia, responsavel, ensaio, observacoes)
    values (p ->> 'lote', v_dom, coalesce(nullif(p ->> 'arquivo', ''), '(sem nome)'), nullif(p ->> 'hash', ''),
            coalesce(nullif(p ->> 'origem', ''), 'não informada'), coalesce(carga.data(p ->> 'data_referencia'), current_date),
            coalesce(nullif(p ->> 'responsavel', ''), 'não informado'), coalesce((p ->> 'ensaio')::boolean, false), p ->> 'observacoes')
    returning * into v_lote;
  elsif v_lote.situacao <> 'RECEBIDO' then
    raise exception 'O lote % já está %: use outro código de lote para novas linhas.', v_lote.codigo, v_lote.situacao using errcode = '55006';
  elsif v_lote.dominio <> v_dom then
    raise exception 'O lote % é do domínio %.', v_lote.codigo, v_lote.dominio using errcode = '22023';
  end if;
  select coalesce(max(linha), 0) into v_base from carga.registros where lote_id = v_lote.id;
  -- cabeçalhos normalizados: minúsculas, sem acento, espaços e hífens viram _
  insert into carga.registros (lote_id, linha, dados)
  select v_lote.id, v_base + x.ord::int,
         (select coalesce(jsonb_object_agg(lower(regexp_replace(iara.f_unaccent(btrim(e.k)), '[\s-]+', '_', 'g')), e.v), '{}'::jsonb)
          from jsonb_each_text(x.obj) e(k, v))
  from jsonb_array_elements(coalesce(p -> 'linhas', '[]'::jsonb)) with ordinality as x(obj, ord);
  get diagnostics v_n = row_count;
  update carga.lotes set linhas = linhas + v_n where id = v_lote.id;
  return jsonb_build_object('lote', v_lote.codigo, 'dominio', v_dom, 'recebidas', v_n, 'total', v_base + v_n);
end $$;

-- 6. Validar -----------------------------------------------------------------------------------------------------------------
-- campos pelo dicionário: obrigatório, tipo e lista; opcional inválido é descartado com aviso (o registro segue)
create or replace function carga.validar_campos(p_dominio text, d jsonb, out erros jsonb, out avisos jsonb, out limpo jsonb)
language plpgsql stable as $$
declare
  l carga.layouts;
  v text;
  ok boolean;
  msg text;
begin
  erros := '[]'; avisos := '[]'; limpo := d;
  for l in select * from carga.layouts where dominio = p_dominio order by ordem loop
    v := carga.txt(d, l.campo);
    if v is null then
      if l.obrigatorio then erros := erros || to_jsonb(l.campo || ': obrigatório'); end if;
      continue;
    end if;
    ok := case l.tipo
      when 'inteiro' then v ~ '^-?\d+$'
      when 'decimal' then carga.num(v) is not null
      when 'data' then carga.data(v) is not null
      when 'data_hora' then carga.data_hora(v) is not null
      when 'sim_nao' then carga.sim(v) is not null
      when 'lista' then upper(btrim(v)) = any (l.valores)
      when 'coordenada' then carga.coord(v) is not null and abs(carga.coord(v)) <= 180
      when 'cpf' then iara.cpf_valido(v)
      when 'nis' then iara.nis_valido(v)
      when 'cep' then length(coalesce(iara.digitos(v), '')) = 8
      when 'email' then v ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
      when 'telefone' then length(coalesce(iara.digitos(v), '')) between 10 and 13
      else true end;
    if not ok then
      -- valores de documentos não vão para a mensagem (dado pessoal)
      msg := l.campo || ': valor inválido' ||
             case when l.tipo in ('cpf', 'nis', 'email', 'telefone', 'texto') then '' else ' "' || left(v, 30) || '"' end ||
             case when l.tipo = 'lista' then ' (use ' || array_to_string(l.valores, ', ') || ')' else '' end;
      if l.obrigatorio then
        erros := erros || to_jsonb(msg);
      else
        avisos := avisos || to_jsonb(msg || ' — descartado');
        limpo := limpo - l.campo;
      end if;
    end if;
  end loop;
end $$;

-- regras de cada domínio (referências, coerência, ponto em Maringá)
create or replace function carga.validar_registro(p_dom text, d jsonb, out chave text, out erros jsonb, out avisos jsonb, out limpo jsonb)
language plpgsql stable as $$
declare
  v_lat double precision := carga.coord(d ->> 'lat');
  v_lng double precision := carga.coord(d ->> 'lng');
  v_nasc date;
  v_ano integer;
  v_turma iara.classes;
  v_g iara.grade_levels;
  v_faixa jsonb;
  v_aluno uuid;
begin
  erros := '[]'; avisos := '[]'; limpo := d;
  chave := case p_dom
    when 'UNIDADES' then carga.txt(d, 'codigo_unidade')
    when 'TURMAS' then carga.txt(d, 'codigo_turma')
    when 'SERVIDORES' then carga.txt(d, 'matricula_funcional')
    when 'RESPONSAVEIS' then carga.txt(d, 'codigo_responsavel')
    when 'ALUNOS' then carga.txt(d, 'codigo_aluno')
    when 'VINCULOS' then carga.txt(d, 'codigo_aluno') || '|' || carga.txt(d, 'codigo_responsavel')
    when 'MATRICULAS' then carga.txt(d, 'codigo_matricula')
    when 'FILA' then carga.txt(d, 'codigo_inscricao') end;

  -- ponto da casa/unidade: lat e lng juntos e dentro de Maringá
  if (v_lat is null) <> (v_lng is null) then
    avisos := avisos || '"lat e lng precisam vir juntos — ponto descartado"';
    limpo := limpo - 'lat' - 'lng';
  elsif v_lat is not null and not iara.in_maringa(v_lat, v_lng) then
    if p_dom = 'UNIDADES' then erros := erros || '"ponto fora de Maringá"';
    else avisos := avisos || '"ponto fora de Maringá — descartado (geocodificar depois)"'; limpo := limpo - 'lat' - 'lng'; end if;
  end if;

  case p_dom
  when 'TURMAS' then
    if carga.ref('UNIDADES', carga.txt(d, 'codigo_unidade')) is null then
      erros := erros || to_jsonb('unidade ' || coalesce(carga.txt(d, 'codigo_unidade'), '?') || ' não encontrada (promova UNIDADES antes)');
    end if;
    v_ano := case when carga.txt(d, 'ano_letivo') ~ '^\d{1,4}$' then carga.txt(d, 'ano_letivo')::int end;
    if v_ano is not null and v_ano not between 2000 and 2100 then erros := erros || '"ano_letivo fora do intervalo"'; end if;
    if carga.num(carga.txt(d, 'capacidade_autorizada')) > 45 then avisos := avisos || '"capacidade acima de 45: confirme"'; end if;
  when 'SERVIDORES' then
    if carga.txt(d, 'codigo_unidade') is not null and carga.ref('UNIDADES', carga.txt(d, 'codigo_unidade')) is null then
      avisos := avisos || '"unidade de lotação não encontrada — lotação descartada"';
      limpo := limpo - 'codigo_unidade';
    end if;
  when 'ALUNOS' then
    v_nasc := carga.data(d ->> 'data_nascimento');
    if v_nasc > current_date then erros := erros || '"data_nascimento no futuro"';
    elsif v_nasc is not null then
      if v_nasc < current_date - interval '20 years' then avisos := avisos || '"aluno com mais de 20 anos: confirme (EJA?)"'; end if;
      v_faixa := iara.grade_for_birthdate(v_nasc, null);
      if not coalesce((v_faixa ->> 'ok')::boolean, false) and v_nasc > current_date - interval '15 years' then
        avisos := avisos || '"idade fora das faixas da rede municipal neste ano"';
      end if;
    end if;
  when 'RESPONSAVEIS' then
    v_nasc := carga.data(d ->> 'data_nascimento');
    if v_nasc > current_date - interval '14 years' then avisos := avisos || '"responsável com menos de 14 anos: confirme"'; end if;
  when 'VINCULOS' then
    if carga.ref('ALUNOS', carga.txt(d, 'codigo_aluno')) is null then
      erros := erros || to_jsonb('aluno ' || coalesce(carga.txt(d, 'codigo_aluno'), '?') || ' não encontrado (promova ALUNOS antes)');
    end if;
    if carga.ref('RESPONSAVEIS', carga.txt(d, 'codigo_responsavel')) is null then
      erros := erros || to_jsonb('responsável ' || coalesce(carga.txt(d, 'codigo_responsavel'), '?') || ' não encontrado (promova RESPONSAVEIS antes)');
    end if;
    if carga.data(d ->> 'fim') < carga.data(d ->> 'inicio') then erros := erros || '"fim do vínculo antes do início"'; end if;
  when 'MATRICULAS' then
    v_aluno := carga.ref('ALUNOS', carga.txt(d, 'codigo_aluno'))::uuid;
    if v_aluno is null then
      erros := erros || to_jsonb('aluno ' || coalesce(carga.txt(d, 'codigo_aluno'), '?') || ' não encontrado (promova ALUNOS antes)');
    end if;
    select * into v_turma from iara.classes where id = carga.ref('TURMAS', carga.txt(d, 'codigo_turma'))::uuid;
    if v_turma.id is null then
      erros := erros || to_jsonb('turma ' || coalesce(carga.txt(d, 'codigo_turma'), '?') || ' não encontrada (promova TURMAS antes)');
    elsif v_turma.school_year::text <> carga.txt(d, 'ano_letivo') then
      erros := erros || '"ano_letivo diferente do ano da turma"';
    elsif v_aluno is not null and upper(carga.txt(d, 'situacao')) = 'ATIVA' then
      select * into v_g from iara.grade_levels where id = v_turma.grade_level_id;
      v_faixa := iara.grade_for_birthdate((select birth_date from iara.students where id = v_aluno), v_turma.school_year);
      if v_faixa ->> 'grade_code' is not null and v_faixa ->> 'grade_code' <> v_g.code then
        avisos := avisos || to_jsonb('idade indica ' || (v_faixa ->> 'grade_code') || ', turma é ' || v_g.code || ' (retenção/avanço?)');
      end if;
    end if;
  when 'FILA' then
    v_aluno := carga.ref('ALUNOS', carga.txt(d, 'codigo_aluno'))::uuid;
    if v_aluno is null then
      erros := erros || to_jsonb('criança ' || coalesce(carga.txt(d, 'codigo_aluno'), '?') || ' não encontrada (promova ALUNOS antes)');
    elsif exists (select 1 from iara.enrollments e where e.student_id = v_aluno and e.status = 'ACTIVE') then
      avisos := avisos || '"criança já tem matrícula ativa (transferência?)"';
    end if;
    if carga.ref('UNIDADES', carga.txt(d, 'codigo_unidade')) is null then
      erros := erros || to_jsonb('unidade ' || coalesce(carga.txt(d, 'codigo_unidade'), '?') || ' não encontrada');
    end if;
  else
    null;
  end case;
end $$;

-- p: { lote, limite? } — valida os registros pendentes (em partes); ao terminar, conferências do arquivo inteiro e resumo
create or replace function carga.validar(p jsonb) returns jsonb
language plpgsql as $$
declare
  v_lote carga.lotes;
  rg carga.registros;
  c record;
  dr record;
  v_lim integer := least(greatest(coalesce((p ->> 'limite')::int, 5000), 1), 20000);
  v_feitos integer := 0;
  v_restam integer;
begin
  select * into v_lote from carga.lotes where codigo = p ->> 'lote' for update;
  if not found then raise exception 'Lote % não encontrado.', p ->> 'lote' using errcode = 'P0002'; end if;
  if v_lote.situacao not in ('RECEBIDO', 'VALIDADO', 'COM_ERROS') then
    raise exception 'O lote % está %: não pode ser validado de novo.', v_lote.codigo, v_lote.situacao using errcode = '55006';
  end if;
  if coalesce((p ->> 'refazer')::boolean, false) then
    update carga.registros set situacao = 'PENDENTE', erros = '[]', avisos = '[]', limpo = null, chave = null where lote_id = v_lote.id;
  end if;

  for rg in select * from carga.registros where lote_id = v_lote.id and situacao = 'PENDENTE' order by linha limit v_lim loop
    select * into c from carga.validar_campos(v_lote.dominio, rg.dados);
    select * into dr from carga.validar_registro(v_lote.dominio, c.limpo);
    update carga.registros set chave = dr.chave, limpo = dr.limpo, erros = c.erros || dr.erros, avisos = c.avisos || dr.avisos,
           situacao = case when jsonb_array_length(c.erros || dr.erros) > 0 then 'ERRO'
                           when jsonb_array_length(c.avisos || dr.avisos) > 0 then 'AVISO' else 'OK' end
    where lote_id = rg.lote_id and linha = rg.linha;
    v_feitos := v_feitos + 1;
  end loop;

  select count(*) into v_restam from carga.registros where lote_id = v_lote.id and situacao = 'PENDENTE';
  if v_restam > 0 then
    return jsonb_build_object('lote', v_lote.codigo, 'validados_agora', v_feitos, 'restam', v_restam);
  end if;

  -- conferências do arquivo inteiro: chave repetida (erro), mesma pessoa com chaves diferentes (aviso)
  update carga.registros r set erros = r.erros || to_jsonb('chave repetida no arquivo (primeira na linha ' || x.primeira || ')'), situacao = 'ERRO'
  from (select lote_id, linha, min(linha) over (partition by chave) primeira from carga.registros where lote_id = v_lote.id and chave is not null) x
  where r.lote_id = x.lote_id and r.linha = x.linha and x.linha <> x.primeira
    and not r.erros @> to_jsonb(array['chave repetida no arquivo (primeira na linha ' || x.primeira || ')']);
  if v_lote.dominio in ('ALUNOS', 'RESPONSAVEIS') then
    update carga.registros r set avisos = r.avisos || '"mesmo CPF de outro registro do arquivo: possível duplicidade"'::jsonb,
           situacao = case when r.situacao = 'OK' then 'AVISO' else r.situacao end
    from (select lote_id, linha from (select lote_id, linha, count(*) over (partition by iara.digitos(limpo ->> 'cpf')) n
                                      from carga.registros where lote_id = v_lote.id and iara.digitos(limpo ->> 'cpf') is not null) z where n > 1) x
    where r.lote_id = x.lote_id and r.linha = x.linha and not r.avisos @> '["mesmo CPF de outro registro do arquivo: possível duplicidade"]';
    update carga.registros r set avisos = r.avisos || '"CPF já cadastrado para outra pessoa: possível duplicidade"'::jsonb,
           situacao = case when r.situacao = 'OK' then 'AVISO' else r.situacao end
    where r.lote_id = v_lote.id and iara.digitos(r.limpo ->> 'cpf') is not null
      and not r.avisos @> '["CPF já cadastrado para outra pessoa: possível duplicidade"]'
      and exists (select 1 from (select id, cpf from iara.students where v_lote.dominio = 'ALUNOS'
                                 union all select id, cpf from iara.guardians where v_lote.dominio = 'RESPONSAVEIS') p
                  where iara.digitos(p.cpf) = iara.digitos(r.limpo ->> 'cpf')
                    and p.id::text is distinct from carga.ref(v_lote.dominio, r.chave));
  end if;
  if v_lote.dominio = 'ALUNOS' then
    update carga.registros r set avisos = r.avisos || '"mesmo nome, nascimento e mãe de outro registro: possível duplicidade"'::jsonb,
           situacao = case when r.situacao = 'OK' then 'AVISO' else r.situacao end
    from (select lote_id, linha from (select lote_id, linha,
            count(*) over (partition by lower(iara.f_unaccent(limpo ->> 'nome')), limpo ->> 'data_nascimento', lower(iara.f_unaccent(coalesce(limpo ->> 'nome_mae', '')))) n
          from carga.registros where lote_id = v_lote.id) z where n > 1) x
    where r.lote_id = x.lote_id and r.linha = x.linha and not r.avisos @> '["mesmo nome, nascimento e mãe de outro registro: possível duplicidade"]';
  end if;
  if v_lote.dominio = 'MATRICULAS' then
    update carga.registros r set erros = r.erros || '"mais de uma matrícula ATIVA do mesmo aluno no mesmo ano"'::jsonb, situacao = 'ERRO'
    from (select lote_id, linha from (select lote_id, linha, count(*) over (partition by limpo ->> 'codigo_aluno', limpo ->> 'ano_letivo') n
                                      from carga.registros where lote_id = v_lote.id and upper(limpo ->> 'situacao') = 'ATIVA') z where n > 1) x
    where r.lote_id = x.lote_id and r.linha = x.linha and not r.erros @> '["mais de uma matrícula ATIVA do mesmo aluno no mesmo ano"]';
  end if;

  update carga.lotes l set
    linhas_ok = (select count(*) from carga.registros where lote_id = l.id and situacao = 'OK'),
    linhas_aviso = (select count(*) from carga.registros where lote_id = l.id and situacao = 'AVISO'),
    linhas_erro = (select count(*) from carga.registros where lote_id = l.id and situacao = 'ERRO'),
    validado_em = now()
  where l.id = v_lote.id
  returning * into v_lote;
  update carga.lotes set situacao = case when v_lote.linhas_erro > 0 then 'COM_ERROS' else 'VALIDADO' end where id = v_lote.id
  returning * into v_lote;

  -- pendências da carga real aparecem no painel de Qualidade de dados (ensaio não polui o painel)
  delete from iara.data_quality_issues where source = 'carga:' || v_lote.codigo;
  if not v_lote.ensaio and (v_lote.linhas_erro > 0 or v_lote.linhas_aviso > 0) then
    insert into iara.data_quality_issues (tenant_id, issue_type, severity, title, description, source, action, status)
    values (1, 'CARGA', case when v_lote.linhas_erro > 0 then 'ALTA' else 'MEDIA' end,
            format('Carga %s (%s): %s erro(s) e %s aviso(s) em %s linha(s)', v_lote.codigo, v_lote.dominio, v_lote.linhas_erro, v_lote.linhas_aviso, v_lote.linhas),
            (select string_agg(m || ' (' || n || ')', '; ' order by n desc) from (
               select m, count(*) n from carga.registros r, jsonb_array_elements_text(r.erros || r.avisos) m
               where r.lote_id = v_lote.id group by m order by count(*) desc limit 8) z),
            'carga:' || v_lote.codigo,
            case when v_lote.linhas_erro > 0 then 'Corrigir na fonte e reenviar o arquivo; linhas com erro não entram.' else 'Conferir os avisos; o lote pode ser promovido.' end,
            'ABERTA');
  end if;

  return carga.resumo(v_lote.codigo);
end $$;

-- resumo de um lote: contagens e as mensagens mais frequentes (sem dados pessoais)
create or replace function carga.resumo(p_codigo text) returns jsonb
language sql stable as $$
  select jsonb_build_object('lote', l.codigo, 'dominio', l.dominio, 'situacao', l.situacao, 'ensaio', l.ensaio, 'arquivo', l.arquivo,
           'hash', left(l.hash_sha256, 16), 'origem', l.origem, 'data_referencia', l.data_referencia, 'responsavel', l.responsavel,
           'linhas', l.linhas, 'ok', l.linhas_ok, 'aviso', l.linhas_aviso, 'erro', l.linhas_erro,
           'promovidas', (select count(*) from carga.registros where lote_id = l.id and situacao = 'PROMOVIDO'),
           'mensagens', (select coalesce(jsonb_agg(jsonb_build_object('mensagem', m, 'linhas', n, 'tipo', t) order by n desc), '[]'::jsonb) from (
              select m, t, count(*) n from (
                select e.m, 'erro' t from carga.registros r, jsonb_array_elements_text(r.erros) e(m) where r.lote_id = l.id
                union all
                select a.m, 'aviso' from carga.registros r, jsonb_array_elements_text(r.avisos) a(m) where r.lote_id = l.id) u
              group by m, t order by count(*) desc limit 15) z),
           'conciliacao', l.conciliacao, 'resultado', l.resultado,
           'recebido_em', l.recebido_em, 'validado_em', l.validado_em, 'promovido_em', l.promovido_em, 'revertido_em', l.revertido_em)
  from carga.lotes l where l.codigo = p_codigo
$$;

-- 7. Promover ----------------------------------------------------------------------------------------------------------------
-- endereço novo da pessoa (o anterior fica intacto: reverter é só voltar o address_id)
create or replace function carga.endereco_novo(d jsonb, p_fonte text) returns uuid
language plpgsql as $$
declare
  v_id uuid;
  v_lat double precision := carga.coord(d ->> 'lat');
  v_lng double precision := carga.coord(d ->> 'lng');
begin
  if coalesce(carga.txt(d, 'logradouro'), carga.txt(d, 'bairro'), carga.txt(d, 'cep')) is null and v_lat is null then
    return null;
  end if;
  insert into iara.addresses (tenant_id, street, number, complement, neighborhood, postal_code, city, state, location,
                              geocode_precision, geocode_source, territory_id, is_demo, geocoded_at)
  values (1, coalesce(carga.txt(d, 'logradouro'), 'Endereço informado'), carga.txt(d, 'numero'), carga.txt(d, 'complemento'),
          carga.txt(d, 'bairro'), iara.digitos(carga.txt(d, 'cep')), 'Maringá', 'PR',
          case when v_lat is not null then iara.point(v_lat, v_lng) end,
          case when v_lat is not null then 'ENDERECO' else 'PENDENTE' end, 'Carga oficial: ' || p_fonte,
          carga.territorio(v_lat, v_lng, array['DISTRITO', 'MACRORREGIAO']), false, case when v_lat is not null then now() end)
  returning id into v_id;
  return v_id;
end $$;

-- cada domínio: (ação, id de destino, valor anterior). Campo vazio no arquivo não apaga o que já existe.
create or replace function carga.promover_registro(p_lote carga.lotes, d jsonb, out acao text, out destino text, out antes jsonb)
language plpgsql as $$
declare
  v_int integer;
  v_uuid uuid;
  v_unit integer;
  v_lat double precision := carga.coord(d ->> 'lat');
  v_lng double precision := carga.coord(d ->> 'lng');
  v_g iara.grade_levels;
  v_turma iara.classes;
  v_end uuid;
  v_aluno uuid;
  v_resp uuid;
  v_status text;
  v_terr integer;
  u iara.education_units;
  s iara.students;
  g iara.guardians;
  sg iara.student_guardians;
  e iara.enrollments;
begin
  case p_lote.dominio
  when 'UNIDADES' then
    v_int := carga.ref('UNIDADES', carga.txt(d, 'codigo_unidade'))::int;
    if v_int is null and carga.txt(d, 'codigo_inep') is not null then
      select id into v_int from iara.education_units where inep_code = carga.txt(d, 'codigo_inep') order by id limit 1;
    end if;
    select * into u from iara.education_units where id = v_int;
    if u.id is not null then
      antes := to_jsonb(u) - 'location' - 'influence_area';
      update iara.education_units set
        name = carga.txt(d, 'nome'), short_name = coalesce(carga.txt(d, 'nome_curto'), short_name),
        inep_code = coalesce(carga.txt(d, 'codigo_inep'), inep_code),
        unit_type = upper(carga.txt(d, 'tipo')), unit_type_label = case upper(carga.txt(d, 'tipo')) when 'CMEI' then 'CMEI' else 'Escola Municipal' end,
        status = coalesce(upper(carga.txt(d, 'situacao')), status),
        status_label = case coalesce(upper(carga.txt(d, 'situacao')), status) when 'ATIVA' then 'Ativa' when 'A_VALIDAR' then 'A validar' else 'Sem turmas' end,
        address_line = coalesce(nullif(concat_ws(', ', carga.txt(d, 'logradouro'), carga.txt(d, 'numero')), ''), address_line),
        neighborhood = coalesce(carga.txt(d, 'bairro'), neighborhood), postal_code = coalesce(iara.digitos(carga.txt(d, 'cep')), postal_code),
        phone = coalesce(carga.txt(d, 'telefone'), phone), director_name = coalesce(carga.txt(d, 'diretor'), director_name),
        lat = v_lat, lng = v_lng, location = iara.point(v_lat, v_lng), geo_precision = 'VALIDADO', geo_source = 'Carga oficial: ' || p_lote.origem,
        macro_territory_id = coalesce(carga.territorio(v_lat, v_lng, array['MACRORREGIAO', 'DISTRITO']), macro_territory_id),
        neighborhood_territory_id = coalesce(carga.territorio(v_lat, v_lng, array['BAIRRO']), neighborhood_territory_id),
        main_source = p_lote.origem, data_reference = p_lote.data_referencia::text, import_batch_id = p_lote.codigo, updated_at = now()
      where id = u.id;
      acao := 'ATUALIZADO'; destino := u.id::text;
    else
      select coalesce(max(id), 0) + 1 into v_int from iara.education_units;
      insert into iara.education_units (id, tenant_id, name, short_name, inep_code, unit_type, unit_type_label, status, status_label,
                                        address_line, neighborhood, postal_code, city, state, phone, director_name, location, lat, lng,
                                        geo_precision, geo_source, macro_territory_id, neighborhood_territory_id, main_source, data_reference,
                                        import_batch_id, confidence_status)
      values (v_int, 1, carga.txt(d, 'nome'), coalesce(carga.txt(d, 'nome_curto'), carga.txt(d, 'nome')), carga.txt(d, 'codigo_inep'),
              upper(carga.txt(d, 'tipo')), case upper(carga.txt(d, 'tipo')) when 'CMEI' then 'CMEI' else 'Escola Municipal' end,
              coalesce(upper(carga.txt(d, 'situacao')), 'ATIVA'),
              case coalesce(upper(carga.txt(d, 'situacao')), 'ATIVA') when 'ATIVA' then 'Ativa' when 'A_VALIDAR' then 'A validar' else 'Sem turmas' end,
              nullif(concat_ws(', ', carga.txt(d, 'logradouro'), carga.txt(d, 'numero')), ''), carga.txt(d, 'bairro'),
              iara.digitos(carga.txt(d, 'cep')), 'Maringá', 'PR', carga.txt(d, 'telefone'), carga.txt(d, 'diretor'),
              iara.point(v_lat, v_lng), v_lat, v_lng, 'VALIDADO', 'Carga oficial: ' || p_lote.origem,
              carga.territorio(v_lat, v_lng, array['MACRORREGIAO', 'DISTRITO']), carga.territorio(v_lat, v_lng, array['BAIRRO']),
              p_lote.origem, p_lote.data_referencia::text, p_lote.codigo, 'OFICIAL');
      acao := 'CRIADO'; destino := v_int::text;
    end if;

  when 'TURMAS' then
    v_unit := carga.ref('UNIDADES', carga.txt(d, 'codigo_unidade'))::int;
    v_g := carga.serie(carga.txt(d, 'serie'));
    v_uuid := carga.ref('TURMAS', carga.txt(d, 'codigo_turma'))::uuid;
    if v_uuid is null then
      select id into v_uuid from iara.classes
      where unit_id = v_unit and school_year = carga.txt(d, 'ano_letivo')::int and class_code = carga.txt(d, 'codigo_turma');
    end if;
    select * into v_turma from iara.classes where id = v_uuid;
    if v_turma.id is not null then
      antes := to_jsonb(v_turma);
      update iara.classes set unit_id = v_unit, school_year = carga.txt(d, 'ano_letivo')::int, stage_id = v_g.stage_id, grade_level_id = v_g.id,
             class_code = carga.txt(d, 'codigo_turma'), class_name = carga.txt(d, 'nome'), shift = upper(carga.txt(d, 'turno')),
             room_label = coalesce(carga.txt(d, 'sala'), room_label), authorized_capacity = carga.txt(d, 'capacidade_autorizada')::int,
             status = coalesce(upper(carga.txt(d, 'situacao')), status), source = p_lote.origem, source_updated_at = p_lote.data_referencia,
             confidence_status = 'OFICIAL', is_demo = false
      where id = v_turma.id;
      acao := 'ATUALIZADO'; destino := v_turma.id::text;
    else
      insert into iara.classes (tenant_id, school_year, unit_id, stage_id, grade_level_id, class_code, class_name, shift, room_label,
                                authorized_capacity, status, source, source_updated_at, confidence_status, is_demo)
      values (1, carga.txt(d, 'ano_letivo')::int, v_unit, v_g.stage_id, v_g.id, carga.txt(d, 'codigo_turma'), carga.txt(d, 'nome'),
              upper(carga.txt(d, 'turno')), carga.txt(d, 'sala'), carga.txt(d, 'capacidade_autorizada')::int,
              coalesce(upper(carga.txt(d, 'situacao')), 'ATIVA'), p_lote.origem, p_lote.data_referencia, 'OFICIAL', false)
      returning id into v_uuid;
      acao := 'CRIADO'; destino := v_uuid::text;
    end if;

  when 'SERVIDORES' then
    v_uuid := carga.ref('SERVIDORES', carga.txt(d, 'matricula_funcional'))::uuid;
    v_unit := carga.ref('UNIDADES', carga.txt(d, 'codigo_unidade'))::int;
    if v_uuid is not null then
      select to_jsonb(x) into antes from iara.staff x where id = v_uuid;
      update iara.staff set full_name = carga.txt(d, 'nome'), role = upper(carga.txt(d, 'funcao')), unit_id = coalesce(v_unit, unit_id),
             bond = coalesce(carga.txt(d, 'vinculo'), bond), is_demo = false
      where id = v_uuid;
      acao := 'ATUALIZADO'; destino := v_uuid::text;
    else
      insert into iara.staff (tenant_id, unit_id, full_name, role, bond, is_demo)
      values (1, v_unit, carga.txt(d, 'nome'), upper(carga.txt(d, 'funcao')), carga.txt(d, 'vinculo'), false)
      returning id into v_uuid;
      acao := 'CRIADO'; destino := v_uuid::text;
    end if;

  when 'RESPONSAVEIS' then
    v_uuid := carga.ref('RESPONSAVEIS', carga.txt(d, 'codigo_responsavel'))::uuid;
    v_end := carga.endereco_novo(d, p_lote.origem);
    select * into g from iara.guardians where id = v_uuid;
    if g.id is not null then
      antes := to_jsonb(g) || jsonb_build_object('_endereco_novo', v_end);
      update iara.guardians set full_name = carga.txt(d, 'nome'), cpf = coalesce(iara.fmt_cpf(carga.txt(d, 'cpf')), cpf),
             nis = coalesce(iara.digitos(carga.txt(d, 'nis')), nis), rg = coalesce(carga.txt(d, 'rg'), rg),
             birth_date = coalesce(carga.data(d ->> 'data_nascimento'), birth_date), gender = coalesce(upper(carga.txt(d, 'sexo')), gender),
             email = coalesce(lower(carga.txt(d, 'email')), email), primary_phone = coalesce(iara.fmt_tel(carga.txt(d, 'telefone')), primary_phone),
             whatsapp_phone = coalesce(iara.fmt_tel(carga.txt(d, 'whatsapp')), whatsapp_phone),
             marital_status = coalesce(carga.txt(d, 'estado_civil'), marital_status), education_level = coalesce(carga.txt(d, 'escolaridade'), education_level),
             occupation = coalesce(carga.txt(d, 'ocupacao'), occupation), family_income = coalesce(carga.num(carga.txt(d, 'renda_familiar')), family_income),
             cadunico_status = coalesce(carga.sim(carga.txt(d, 'cadunico')), cadunico_status),
             single_mother = coalesce(carga.sim(carga.txt(d, 'mae_solo')), single_mother),
             household_size = coalesce(carga.txt(d, 'pessoas_domicilio')::smallint, household_size),
             address_id = coalesce(v_end, address_id), is_demo = false, updated_at = now()
      where id = g.id;
      acao := 'ATUALIZADO'; destino := g.id::text;
    else
      insert into iara.guardians (tenant_id, full_name, cpf, nis, rg, birth_date, gender, email, primary_phone, whatsapp_phone, marital_status,
                                  education_level, occupation, family_income, cadunico_status, single_mother, household_size, address_id, is_demo)
      values (1, carga.txt(d, 'nome'), iara.fmt_cpf(carga.txt(d, 'cpf')), iara.digitos(carga.txt(d, 'nis')), carga.txt(d, 'rg'),
              carga.data(d ->> 'data_nascimento'), upper(carga.txt(d, 'sexo')), lower(carga.txt(d, 'email')),
              iara.fmt_tel(carga.txt(d, 'telefone')), iara.fmt_tel(carga.txt(d, 'whatsapp')), carga.txt(d, 'estado_civil'),
              carga.txt(d, 'escolaridade'), carga.txt(d, 'ocupacao'), carga.num(carga.txt(d, 'renda_familiar')),
              coalesce(carga.sim(carga.txt(d, 'cadunico')), false), coalesce(carga.sim(carga.txt(d, 'mae_solo')), false),
              carga.txt(d, 'pessoas_domicilio')::smallint, v_end, false)
      returning id into v_uuid;
      acao := 'CRIADO'; destino := v_uuid::text; antes := jsonb_build_object('_endereco_novo', v_end);
    end if;

  when 'ALUNOS' then
    v_uuid := carga.ref('ALUNOS', carga.txt(d, 'codigo_aluno'))::uuid;
    v_end := carga.endereco_novo(d, p_lote.origem);
    select * into s from iara.students where id = v_uuid;
    if s.id is not null then
      antes := to_jsonb(s) || jsonb_build_object('_endereco_novo', v_end);
      update iara.students set full_name = carga.txt(d, 'nome'), social_name = coalesce(carga.txt(d, 'nome_social'), social_name),
             birth_date = carga.data(d ->> 'data_nascimento'), gender = coalesce(upper(carga.txt(d, 'sexo')), gender),
             race_color = coalesce(upper(carga.txt(d, 'cor_raca')), race_color), cpf = coalesce(iara.fmt_cpf(carga.txt(d, 'cpf')), cpf),
             nis = coalesce(iara.digitos(carga.txt(d, 'nis')), nis), birth_certificate = coalesce(carga.txt(d, 'certidao_nascimento'), birth_certificate),
             sus_card = coalesce(carga.txt(d, 'cartao_sus'), sus_card), inep_id = coalesce(carga.txt(d, 'codigo_inep_aluno'), inep_id),
             nationality = coalesce(upper(carga.txt(d, 'nacionalidade')), nationality),
             parent1_name = coalesce(carga.txt(d, 'nome_mae'), parent1_name), parent2_name = coalesce(carga.txt(d, 'nome_pai'), parent2_name),
             transport_need = coalesce(carga.sim(carga.txt(d, 'transporte')), transport_need),
             aee_status = coalesce(carga.sim(carga.txt(d, 'aee')), aee_status), address_id = coalesce(v_end, address_id),
             is_demo = false, updated_at = now()
      where id = s.id;
      acao := 'ATUALIZADO'; destino := s.id::text;
    else
      insert into iara.students (tenant_id, full_name, social_name, birth_date, gender, student_registry_number, status, address_id,
                                 transport_need, aee_status, cpf, nis, birth_certificate, race_color, nationality, sus_card, inep_id,
                                 parent1_name, parent2_name, is_demo)
      values (1, carga.txt(d, 'nome'), carga.txt(d, 'nome_social'), carga.data(d ->> 'data_nascimento'), upper(carga.txt(d, 'sexo')),
              carga.txt(d, 'codigo_aluno'), 'SEM_VINCULO', v_end, coalesce(carga.sim(carga.txt(d, 'transporte')), false),
              coalesce(carga.sim(carga.txt(d, 'aee')), false), iara.fmt_cpf(carga.txt(d, 'cpf')), iara.digitos(carga.txt(d, 'nis')),
              carga.txt(d, 'certidao_nascimento'), upper(carga.txt(d, 'cor_raca')), coalesce(upper(carga.txt(d, 'nacionalidade')), 'BRASILEIRA'),
              carga.txt(d, 'cartao_sus'), carga.txt(d, 'codigo_inep_aluno'), carga.txt(d, 'nome_mae'), carga.txt(d, 'nome_pai'), false)
      returning id into v_uuid;
      acao := 'CRIADO'; destino := v_uuid::text; antes := jsonb_build_object('_endereco_novo', v_end);
    end if;

  when 'VINCULOS' then
    v_aluno := carga.ref('ALUNOS', carga.txt(d, 'codigo_aluno'))::uuid;
    v_resp := carga.ref('RESPONSAVEIS', carga.txt(d, 'codigo_responsavel'))::uuid;
    select * into sg from iara.student_guardians where student_id = v_aluno and guardian_id = v_resp;
    if sg.student_id is not null then
      antes := to_jsonb(sg);
      update iara.student_guardians set relationship = upper(carga.txt(d, 'parentesco')),
             is_primary = coalesce(carga.sim(carga.txt(d, 'principal')), is_primary),
             can_pick_up = coalesce(carga.sim(carga.txt(d, 'pode_buscar')), can_pick_up),
             can_receive_notifications = coalesce(carga.sim(carga.txt(d, 'recebe_avisos')), can_receive_notifications),
             legal_authority_status = coalesce(upper(carga.txt(d, 'situacao_legal')), legal_authority_status),
             start_date = coalesce(carga.data(d ->> 'inicio'), start_date), end_date = carga.data(d ->> 'fim')
      where student_id = v_aluno and guardian_id = v_resp;
      acao := 'ATUALIZADO';
    else
      insert into iara.student_guardians (student_id, guardian_id, relationship, is_primary, can_pick_up, can_receive_notifications,
                                          legal_authority_status, start_date, end_date)
      values (v_aluno, v_resp, upper(carga.txt(d, 'parentesco')), coalesce(carga.sim(carga.txt(d, 'principal')), false),
              coalesce(carga.sim(carga.txt(d, 'pode_buscar')), true), coalesce(carga.sim(carga.txt(d, 'recebe_avisos')), true),
              coalesce(upper(carga.txt(d, 'situacao_legal')), 'DECLARADO'), coalesce(carga.data(d ->> 'inicio'), current_date),
              carga.data(d ->> 'fim'));
      acao := 'CRIADO';
    end if;
    destino := v_aluno::text || ':' || v_resp::text;

  when 'MATRICULAS' then
    v_aluno := carga.ref('ALUNOS', carga.txt(d, 'codigo_aluno'))::uuid;
    select * into v_turma from iara.classes where id = carga.ref('TURMAS', carga.txt(d, 'codigo_turma'))::uuid;
    v_status := case upper(carga.txt(d, 'situacao'))
      when 'ATIVA' then 'ACTIVE' when 'PRE_MATRICULA' then 'PRE_ENROLLMENT' when 'TRANSFERENCIA_PENDENTE' then 'TRANSFER_PENDING'
      when 'TRANSFERIDA' then 'TRANSFERRED' when 'CANCELADA' then 'CANCELLED' when 'CONCLUIDA' then 'COMPLETED' else 'INACTIVE' end;
    v_uuid := carga.ref('MATRICULAS', carga.txt(d, 'codigo_matricula'))::uuid;
    select * into e from iara.enrollments where id = v_uuid;
    if e.id is not null then
      antes := to_jsonb(e) || jsonb_build_object('_aluno', (select to_jsonb(x) from iara.students x where id = v_aluno));
      update iara.enrollments set student_id = v_aluno, class_id = v_turma.id, unit_id = v_turma.unit_id, school_year = v_turma.school_year,
             status = v_status, enrollment_date = coalesce(carga.data(d ->> 'data_matricula'), enrollment_date),
             start_date = coalesce(carga.data(d ->> 'inicio'), start_date), end_date = carga.data(d ->> 'fim'),
             entry_type = coalesce(upper(carga.txt(d, 'tipo_entrada')), entry_type), is_demo = false
      where id = e.id;
      acao := 'ATUALIZADO'; destino := e.id::text;
    else
      antes := jsonb_build_object('_aluno', (select to_jsonb(x) from iara.students x where id = v_aluno));
      insert into iara.enrollments (tenant_id, student_id, class_id, unit_id, school_year, status, enrollment_date, start_date, end_date,
                                    entry_type, is_demo)
      values (1, v_aluno, v_turma.id, v_turma.unit_id, v_turma.school_year, v_status, coalesce(carga.data(d ->> 'data_matricula'), p_lote.data_referencia),
              carga.data(d ->> 'inicio'), carga.data(d ->> 'fim'), coalesce(upper(carga.txt(d, 'tipo_entrada')), 'NOVA'), false)
      returning id into v_uuid;
      acao := 'CRIADO'; destino := v_uuid::text;
    end if;
    if v_status = 'ACTIVE' then
      update iara.students set current_enrollment_id = destino::uuid, status = 'MATRICULADO' where id = v_aluno;
    end if;

  when 'FILA' then
    v_aluno := carga.ref('ALUNOS', carga.txt(d, 'codigo_aluno'))::uuid;
    v_unit := carga.ref('UNIDADES', carga.txt(d, 'codigo_unidade'))::int;
    v_g := carga.serie(carga.txt(d, 'serie'));
    select a.territory_id into v_terr from iara.students x join iara.addresses a on a.id = x.address_id where x.id = v_aluno;
    v_status := case upper(coalesce(carga.txt(d, 'situacao'), 'AGUARDANDO')) when 'SUSPENSA' then 'SUSPENDED' else 'WAITING' end;
    v_uuid := carga.ref('FILA', carga.txt(d, 'codigo_inscricao'))::uuid;
    if v_uuid is not null and exists (select 1 from iara.waiting_list_entries where id = v_uuid) then
      select to_jsonb(x) into antes from iara.waiting_list_entries x where id = v_uuid;
      update iara.waiting_list_entries set student_id = v_aluno, stage_id = v_g.stage_id, grade_level_id = v_g.id, preferred_unit_id = v_unit,
             territory_id = v_terr, preferred_shift = upper(carga.txt(d, 'turno_preferido')),
             full_time_requested = coalesce(carga.sim(carga.txt(d, 'integral')), false),
             demand_category = coalesce(upper(carga.txt(d, 'categoria')), 'SEM_ATENDIMENTO'), status = v_status,
             entered_at = carga.data_hora(d ->> 'data_solicitacao'), is_demo = false, updated_at = now()
      where id = v_uuid;
      acao := 'ATUALIZADO'; destino := v_uuid::text;
    else
      antes := jsonb_build_object('_aluno', (select to_jsonb(x) from iara.students x where id = v_aluno));
      insert into iara.waiting_list_entries (tenant_id, student_id, stage_id, grade_level_id, preferred_unit_id, territory_id, preferred_shift,
                                             full_time_requested, demand_category, status, entered_at, is_demo)
      values (1, v_aluno, v_g.stage_id, v_g.id, v_unit, v_terr, upper(carga.txt(d, 'turno_preferido')),
              coalesce(carga.sim(carga.txt(d, 'integral')), false), coalesce(upper(carga.txt(d, 'categoria')), 'SEM_ATENDIMENTO'),
              v_status, carga.data_hora(d ->> 'data_solicitacao'), false)
      returning id into v_uuid;
      acao := 'CRIADO'; destino := v_uuid::text;
    end if;
    perform iara.compute_queue_priority(v_uuid);
    update iara.students set status = 'AGUARDANDO_VAGA' where id = v_aluno and status in ('SEM_VINCULO');
  end case;
end $$;

-- p: { lote, limite?, parcial? } — promove em partes; lote com erro só com parcial=true (as linhas com erro ficam de fora)
create or replace function carga.promover(p jsonb) returns jsonb
language plpgsql as $$
declare
  v_lote carga.lotes;
  rg carga.registros;
  x record;
  v_lim integer := least(greatest(coalesce((p ->> 'limite')::int, 2000), 1), 20000);
  v_feitos integer := 0;
  v_restam integer;
  v_dep text;
begin
  select * into v_lote from carga.lotes where codigo = p ->> 'lote' for update;
  if not found then raise exception 'Lote % não encontrado.', p ->> 'lote' using errcode = 'P0002'; end if;
  if v_lote.ensaio and coalesce(current_setting('carga.ensaio', true), '') <> 'on' then
    raise exception 'Lote de ensaio: só pode ser promovido dentro de carga.ensaiar (que desfaz tudo ao final).' using errcode = '42501';
  end if;
  if v_lote.situacao = 'COM_ERROS' and not coalesce((p ->> 'parcial')::boolean, false) then
    raise exception 'O lote % tem % linha(s) com erro. Corrija e reenvie, ou promova só as linhas válidas com parcial=true.', v_lote.codigo, v_lote.linhas_erro using errcode = '55006';
  end if;
  if v_lote.situacao not in ('VALIDADO', 'COM_ERROS') then
    raise exception 'O lote % está %: valide antes de promover.', v_lote.codigo, v_lote.situacao using errcode = '55006';
  end if;

  -- unidades guardam de qual importação vieram (iara.import_batches)
  if v_lote.dominio = 'UNIDADES' then
    insert into iara.import_batches (id, source_file, description, row_counts)
    values (v_lote.codigo, v_lote.arquivo, format('Carga oficial %s · %s · referência %s', v_lote.dominio, v_lote.origem, v_lote.data_referencia),
            jsonb_build_object('linhas', v_lote.linhas))
    on conflict (id) do nothing;
  end if;
  -- a carga entra com um evento por lote (o detalhe linha a linha fica em carga.registros, com o valor anterior)
  perform set_config('iara.skip_audit', 'on', true);
  for rg in select * from carga.registros where lote_id = v_lote.id and situacao in ('OK', 'AVISO') order by linha limit v_lim loop
    select * into x from carga.promover_registro(v_lote, rg.limpo);
    update carga.registros set situacao = 'PROMOVIDO', acao = x.acao, destino_id = x.destino, antes = x.antes
    where lote_id = rg.lote_id and linha = rg.linha;
    -- a correspondência nova fica marcada com o lote que a criou (a reversão do lote a remove)
    if v_lote.dominio <> 'VINCULOS' then
      update carga.correspondencia set id_interno = x.destino, atualizado_em = now() where dominio = v_lote.dominio and chave = rg.chave;
      if not found then
        insert into carga.correspondencia (dominio, chave, id_interno, origem, lote_id) values (v_lote.dominio, rg.chave, x.destino, v_lote.origem, v_lote.id);
      end if;
    end if;
    v_feitos := v_feitos + 1;
  end loop;
  perform set_config('iara.skip_audit', 'off', true);

  select count(*) into v_restam from carga.registros where lote_id = v_lote.id and situacao in ('OK', 'AVISO');
  if v_restam > 0 then
    return jsonb_build_object('lote', v_lote.codigo, 'promovidas_agora', v_feitos, 'restam', v_restam);
  end if;

  -- fila: posições recalculadas pela IN 025 nas filas afetadas
  if v_lote.dominio = 'FILA' then
    for x in select distinct w.preferred_unit_id u, w.grade_level_id g from carga.registros r join iara.waiting_list_entries w on w.id = r.destino_id::uuid
             where r.lote_id = v_lote.id and r.situacao = 'PROMOVIDO' loop
      perform iara.recalculate_queue(x.u, x.g);
    end loop;
  end if;

  update carga.lotes set situacao = 'PROMOVIDO', promovido_em = now(),
         resultado = (select jsonb_build_object('criados', count(*) filter (where acao = 'CRIADO'), 'atualizados', count(*) filter (where acao = 'ATUALIZADO'),
                                                'fora', count(*) filter (where situacao = 'ERRO'))
                      from carga.registros where lote_id = v_lote.id)
  where id = v_lote.id returning * into v_lote;
  update carga.lotes set conciliacao = carga.conciliar(v_lote.codigo) where id = v_lote.id;
  update iara.data_quality_issues set status = 'RESOLVIDA' where source = 'carga:' || v_lote.codigo and severity <> 'ALTA';
  perform iara.audit_event('CARGA_PROMOVIDA', 'carga_lote', v_lote.codigo, null,
    format('Carga %s (%s) promovida: %s criado(s), %s atualizado(s); arquivo %s (sha256 %s), referência %s, responsável %s.',
           v_lote.codigo, v_lote.dominio, v_lote.resultado ->> 'criados', v_lote.resultado ->> 'atualizados', v_lote.arquivo,
           left(coalesce(v_lote.hash_sha256, 'não informado'), 16), v_lote.data_referencia, v_lote.responsavel));
  return carga.resumo(v_lote.codigo);
end $$;

-- 8. Conciliar ----------------------------------------------------------------------------------------------------------------
create or replace function carga.conciliar(p_codigo text) returns jsonb
language plpgsql stable as $$
declare
  v_lote carga.lotes;
  v jsonb;
begin
  select * into v_lote from carga.lotes where codigo = p_codigo;
  if not found then raise exception 'Lote % não encontrado.', p_codigo using errcode = 'P0002'; end if;
  v := jsonb_build_object('linhas', v_lote.linhas, 'validas', coalesce(v_lote.linhas_ok, 0) + coalesce(v_lote.linhas_aviso, 0),
                          'com_erro', v_lote.linhas_erro,
                          'novos', (select count(*) from carga.registros r where r.lote_id = v_lote.id and r.situacao <> 'ERRO'
                                     and coalesce(r.acao, case when carga.ref(v_lote.dominio, r.chave) is null then 'CRIADO' end) = 'CRIADO'),
                          'ja_existentes', (select count(*) from carga.registros r where r.lote_id = v_lote.id and r.situacao <> 'ERRO'
                                             and coalesce(r.acao, case when carga.ref(v_lote.dominio, r.chave) is not null then 'ATUALIZADO' end) = 'ATUALIZADO'));
  if v_lote.dominio in ('ALUNOS', 'RESPONSAVEIS') then
    v := v || jsonb_build_object(
      'com_cpf', (select count(*) from carga.registros where lote_id = v_lote.id and iara.digitos(limpo ->> 'cpf') is not null),
      'com_ponto', (select count(*) from carga.registros where lote_id = v_lote.id and carga.coord(limpo ->> 'lat') is not null),
      'sem_endereco', (select count(*) from carga.registros where lote_id = v_lote.id
                        and coalesce(limpo ->> 'logradouro', limpo ->> 'bairro', limpo ->> 'cep', limpo ->> 'lat') is null));
  elsif v_lote.dominio = 'TURMAS' then
    v := v || jsonb_build_object('por_unidade', (select coalesce(jsonb_agg(z order by z.unidade), '[]'::jsonb) from (
      select y.unidade, y.turmas, y.capacidade,
             (select census_classes from iara.education_units u where u.id::text = carga.ref('UNIDADES', y.unidade)) turmas_censo
      from (select limpo ->> 'codigo_unidade' unidade, count(*) turmas, sum(carga.num(limpo ->> 'capacidade_autorizada')) capacidade
            from carga.registros where lote_id = v_lote.id and situacao <> 'ERRO' group by 1) y) z));
  elsif v_lote.dominio = 'MATRICULAS' then
    v := v || jsonb_build_object('ativas_por_unidade', (select coalesce(jsonb_agg(z order by z.unidade_id), '[]'::jsonb) from (
      select t.unit_id unidade_id, count(*) ativas, max(u.census_enrollments) matriculas_censo,
             count(*) - coalesce(max(u.census_enrollments), 0) diferenca_censo
      from carga.registros r join iara.classes t on t.id = carga.ref('TURMAS', r.limpo ->> 'codigo_turma')::uuid
      join iara.education_units u on u.id = t.unit_id
      where r.lote_id = v_lote.id and r.situacao <> 'ERRO' and upper(r.limpo ->> 'situacao') = 'ATIVA' group by t.unit_id) z));
  elsif v_lote.dominio = 'FILA' then
    -- depois de promovida: a ordem calculada pela IN 025 confere com a lista oficial?
    v := v || (select jsonb_build_object(
      'com_posicao_oficial', count(*) filter (where (r.limpo ->> 'posicao_oficial') is not null),
      'mesma_posicao', count(*) filter (where w.position::text = r.limpo ->> 'posicao_oficial'),
      'mesma_pontuacao', count(*) filter (where carga.num(r.limpo ->> 'pontuacao_oficial') = w.priority_score),
      'divergencias', coalesce(jsonb_agg(jsonb_build_object('inscricao', r.chave, 'posicao_oficial', (r.limpo ->> 'posicao_oficial')::int,
                                 'posicao_calculada', w.position, 'pontos_oficiais', carga.num(r.limpo ->> 'pontuacao_oficial'),
                                 'pontos_calculados', w.priority_score) order by w.preferred_unit_id, w.position)
                       filter (where (r.limpo ->> 'posicao_oficial') is not null and w.position::text is distinct from r.limpo ->> 'posicao_oficial'), '[]'::jsonb))
      from carga.registros r join iara.waiting_list_entries w on w.id = r.destino_id::uuid
      where r.lote_id = v_lote.id and r.situacao = 'PROMOVIDO');
  end if;
  return v;
end $$;

-- 9. Reverter -----------------------------------------------------------------------------------------------------------------
-- devolve uma linha ao valor anterior (colunas geográficas ficam de fora; unidades recalculam o ponto pela lat/lng)
create or replace function carga.restaurar(p_tabela text, p_chaves text[], p_antes jsonb) returns void
language plpgsql as $$
declare
  v_set text;
  v_where text;
begin
  select string_agg(format('%I = r.%I', column_name, column_name), ', ') into v_set
  from information_schema.columns
  where table_schema = 'iara' and table_name = p_tabela and is_generated = 'NEVER' and data_type <> 'USER-DEFINED'
    and column_name <> all (p_chaves) and p_antes ? column_name;
  select string_agg(format('t.%I = r.%I', k, k), ' and ') into v_where from unnest(p_chaves) k;
  execute format('update iara.%I t set %s from jsonb_populate_record(null::iara.%I, $1) r where %s', p_tabela, v_set, p_tabela, v_where)
  using p_antes;
  if p_tabela = 'education_units' then
    update iara.education_units set location = iara.point(lat, lng) where id = (p_antes ->> 'id')::int;
  end if;
end $$;

create or replace function carga.reverter(p jsonb) returns jsonb
language plpgsql as $$
declare
  v_lote carga.lotes;
  rg carga.registros;
  v_tab text;
  v_end uuid;
  x record;
  v_n integer := 0;
  v_filas jsonb;
begin
  select * into v_lote from carga.lotes where codigo = p ->> 'lote' for update;
  if not found then raise exception 'Lote % não encontrado.', p ->> 'lote' using errcode = 'P0002'; end if;
  if v_lote.situacao <> 'PROMOVIDO' then
    raise exception 'Só um lote promovido pode ser revertido (o lote % está %).', v_lote.codigo, v_lote.situacao using errcode = '55006';
  end if;
  if v_lote.ensaio and coalesce(current_setting('carga.ensaio', true), '') <> 'on' then
    raise exception 'Lote de ensaio: use carga.ensaiar.' using errcode = '42501';
  end if;
  select tabela into v_tab from carga.dominios where codigo = v_lote.dominio;
  -- nada que dependa dos registros CRIADOS por este lote (várias chaves estrangeiras apagam em cascata: checagem explícita)
  if exists (
    select 1 from carga.registros rr where rr.lote_id = v_lote.id and rr.situacao = 'PROMOVIDO' and rr.acao = 'CRIADO' and (
      (v_lote.dominio = 'UNIDADES' and (exists (select 1 from iara.classes c where c.unit_id = rr.destino_id::int)
                                     or exists (select 1 from iara.staff s where s.unit_id = rr.destino_id::int)
                                     or exists (select 1 from iara.waiting_list_entries w where w.preferred_unit_id = rr.destino_id::int)))
      or (v_lote.dominio = 'TURMAS' and exists (select 1 from iara.enrollments e where e.class_id = rr.destino_id::uuid))
      or (v_lote.dominio = 'RESPONSAVEIS' and exists (select 1 from iara.student_guardians sg where sg.guardian_id = rr.destino_id::uuid))
      or (v_lote.dominio = 'ALUNOS' and (exists (select 1 from iara.student_guardians sg where sg.student_id = rr.destino_id::uuid)
                                      or exists (select 1 from iara.enrollments e where e.student_id = rr.destino_id::uuid)
                                      or exists (select 1 from iara.waiting_list_entries w where w.student_id = rr.destino_id::uuid)))
      or (v_lote.dominio = 'FILA' and exists (select 1 from iara.vacancy_offers o where o.waiting_list_entry_id = rr.destino_id::uuid))
    )) then
    raise exception 'Não dá para reverter %: há registros que dependem destes (de outros lotes ou do uso do sistema). Reverta antes os lotes posteriores (ordem: FILA, MATRICULAS, VINCULOS, ALUNOS, RESPONSAVEIS, SERVIDORES, TURMAS, UNIDADES).', v_lote.codigo
      using errcode = '23503';
  end if;
  -- filas afetadas (recalculadas depois de desfazer as inscrições)
  if v_lote.dominio = 'FILA' then
    select coalesce(jsonb_agg(distinct jsonb_build_array(w.preferred_unit_id, w.grade_level_id)), '[]'::jsonb) into v_filas
    from carga.registros r2 join iara.waiting_list_entries w on w.id = r2.destino_id::uuid
    where r2.lote_id = v_lote.id and r2.situacao = 'PROMOVIDO';
  end if;
  perform set_config('iara.skip_audit', 'on', true);
  begin
    for rg in select * from carga.registros where lote_id = v_lote.id and situacao = 'PROMOVIDO' order by linha desc loop
      if rg.acao = 'CRIADO' then
        if v_lote.dominio = 'VINCULOS' then
          delete from iara.student_guardians where student_id = split_part(rg.destino_id, ':', 1)::uuid and guardian_id = split_part(rg.destino_id, ':', 2)::uuid;
        elsif v_lote.dominio = 'UNIDADES' then
          delete from iara.education_units where id = rg.destino_id::int;
        else
          execute format('delete from iara.%I where id = $1::uuid', v_tab) using rg.destino_id;
        end if;
      else
        if v_lote.dominio = 'VINCULOS' then
          perform carga.restaurar(v_tab, array['student_id', 'guardian_id'], rg.antes);
        else
          perform carga.restaurar(v_tab, array['id'], rg.antes - '_endereco_novo' - '_aluno');
        end if;
      end if;
      -- endereço criado pela carga sai junto; aluno volta à situação de antes (matrícula/fila)
      v_end := nullif(rg.antes ->> '_endereco_novo', '')::uuid;
      if v_end is not null then
        delete from iara.addresses a where a.id = v_end
          and not exists (select 1 from iara.students s where s.address_id = a.id)
          and not exists (select 1 from iara.guardians g where g.address_id = a.id);
      end if;
      if rg.antes ? '_aluno' and rg.antes -> '_aluno' <> 'null'::jsonb then
        update iara.students set status = (rg.antes -> '_aluno' ->> 'status'),
               current_enrollment_id = nullif(rg.antes -> '_aluno' ->> 'current_enrollment_id', '')::uuid
        where id = (rg.antes -> '_aluno' ->> 'id')::uuid;
      end if;
      update carga.registros set situacao = 'REVERTIDO' where lote_id = rg.lote_id and linha = rg.linha;
      v_n := v_n + 1;
    end loop;
  exception when foreign_key_violation then
    raise exception 'Não dá para reverter %: outros lotes dependem destes registros. Reverta antes os lotes posteriores (ordem: FILA, MATRICULAS, VINCULOS, ALUNOS, RESPONSAVEIS, SERVIDORES, TURMAS, UNIDADES).', v_lote.codigo
      using errcode = '23503';
  end;
  delete from carga.correspondencia where lote_id = v_lote.id;
  if v_lote.dominio = 'FILA' then
    for x in select (f ->> 0)::int u, (f ->> 1)::smallint g from jsonb_array_elements(coalesce(v_filas, '[]'::jsonb)) f loop
      perform iara.recalculate_queue(x.u, x.g);
    end loop;
  end if;
  perform set_config('iara.skip_audit', 'off', true);
  update carga.lotes set situacao = 'REVERTIDO', revertido_em = now() where id = v_lote.id;
  perform iara.audit_event('CARGA_REVERTIDA', 'carga_lote', v_lote.codigo, null,
    format('Carga %s (%s) revertida: %s registro(s) desfeitos.', v_lote.codigo, v_lote.dominio, v_n));
  return carga.resumo(v_lote.codigo);
end $$;

-- descarta um lote que não foi promovido (ex.: arquivo errado)
create or replace function carga.descartar(p jsonb) returns jsonb
language plpgsql as $$
declare
  v_lote carga.lotes;
begin
  select * into v_lote from carga.lotes where codigo = p ->> 'lote' for update;
  if not found then raise exception 'Lote % não encontrado.', p ->> 'lote' using errcode = 'P0002'; end if;
  if v_lote.situacao in ('PROMOVIDO') then
    raise exception 'Lote promovido não se descarta: reverta antes.' using errcode = '55006';
  end if;
  delete from carga.registros where lote_id = v_lote.id;
  delete from iara.data_quality_issues where source = 'carga:' || v_lote.codigo;
  update carga.lotes set situacao = 'DESCARTADO', observacoes = coalesce(observacoes || ' · ', '') || coalesce(p ->> 'motivo', 'descartado') where id = v_lote.id;
  return jsonb_build_object('lote', v_lote.codigo, 'situacao', 'DESCARTADO');
end $$;

-- 10. Ensaio -------------------------------------------------------------------------------------------------------------------
-- valida e promove os lotes de ensaio na ordem dos domínios, concilia e DESFAZ tudo (o resultado volta na mensagem)
create or replace function carga.ensaiar(p jsonb) returns void
language plpgsql as $$
declare
  v_out jsonb := '[]';
  l carga.lotes;
  v jsonb;
begin
  perform set_config('carga.ensaio', 'on', true);
  for l in select lt.* from carga.lotes lt join carga.dominios d on d.codigo = lt.dominio
           where lt.codigo in (select jsonb_array_elements_text(p -> 'lotes')) and lt.ensaio order by d.ordem, lt.id loop
    v := carga.validar(jsonb_build_object('lote', l.codigo, 'limite', 20000));
    if (v ->> 'situacao') = 'VALIDADO' or ((v ->> 'situacao') = 'COM_ERROS' and coalesce((p ->> 'parcial')::boolean, true)) then
      v := carga.promover(jsonb_build_object('lote', l.codigo, 'limite', 20000, 'parcial', true));
    end if;
    v_out := v_out || jsonb_build_array(v - 'mensagens' || jsonb_build_object('mensagens', v -> 'mensagens'));
  end loop;
  raise exception 'ENSAIO: %', v_out;  -- desfaz tudo
end $$;

-- 11. Painel (sem dados pessoais): lotes e situação, para a Inovação/Secretaria ----------------------------------------------
create or replace function api.cargas_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, carga, public
as $$
begin
  perform iara.require_perm('quality.read');
  return jsonb_build_object(
    'dominios', (select jsonb_agg(jsonb_build_object('codigo', codigo, 'nome', nome, 'ordem', ordem, 'depende_de', depende_de,
                   'campos', (select count(*) from carga.layouts l where l.dominio = d.codigo),
                   'carregados', (select count(*) from carga.correspondencia c where c.dominio = d.codigo)) order by ordem) from carga.dominios d),
    'lotes', (select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'dominio', dominio, 'situacao', situacao, 'ensaio', ensaio,
                'arquivo', arquivo, 'origem', origem, 'data_referencia', data_referencia, 'responsavel', responsavel,
                'linhas', linhas, 'ok', linhas_ok, 'aviso', linhas_aviso, 'erro', linhas_erro, 'resultado', resultado,
                'recebido_em', recebido_em, 'promovido_em', promovido_em) order by id desc), '[]'::jsonb)
              from (select * from carga.lotes where situacao <> 'DESCARTADO' order by id desc limit 50) z));
end $$;

revoke all on all functions in schema carga from public;
revoke all on all tables in schema carga from public;

commit;
