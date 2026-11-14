-- IARA Educa — 099.20 · Oráculo do Prefeito: a base inteira, cruzável
-- Decisão de Rob (14/11/2026): o Oráculo liga todos os dados do IARA e chega a dados pontuais ("qual escola tem o menor Ideb, quais os
-- problemas dela, o absenteísmo dos servidores, quem é a diretora"), com nomes de alunos, responsáveis e servidores quando o Prefeito pede.
-- Ficam fora: saúde, deficiência, laudos, casos de proteção, documentos, contatos e endereços das famílias, credenciais e conversas.
--
-- Como funciona
--  • O papel oraculo_leitor (sem login) só lê, e só as colunas liberadas pelas regras abaixo (concessão por coluna: não cria dependência que
--    impeça migrações futuras de mudar as tabelas). iara.oraculo_base_conceder() refaz as concessões; o 20261003009900_privilegios.sql a chama,
--    então tabela e coluna novas seguem as mesmas regras depois de cada migração.
--  • api.oraculo_catalogo: o mapa da base (tabelas, colunas liberadas, ligações) para o Claude achar onde está cada informação.
--  • api.oraculo_consulta: SELECT escrito pelo Claude, registrado na auditoria (quem, para quê e a consulta), executado numa transação só de
--    leitura, pelo oraculo_leitor, com até 200 linhas. Só o perfil Prefeito (oraculo.prefeito).
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

-- 1. O papel que só lê ----------------------------------------------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'oraculo_leitor') then
    create role oraculo_leitor nologin bypassrls;
  end if;
end $$;
grant oraculo_leitor to postgres;
grant usage on schema iara to oraculo_leitor;
grant usage on schema extensions to oraculo_leitor;
grant execute on function iara.norm(text), iara.f_unaccent(text) to oraculo_leitor;

create schema if not exists oraculo_exec;
revoke all on schema oraculo_exec from public;
grant usage, create on schema oraculo_exec to oraculo_leitor;

-- 2. O que entra ----------------------------------------------------------------------------------------------------------------------
-- tabelas inteiras fora: saúde, deficiência, proteção, sigilo profissional, conversas, credenciais, rastros técnicos e configuração interna
create or replace function iara.oraculo_base_fora() returns text[]
language sql immutable
as $$ select array[
  -- saúde, deficiência, laudos, proteção da criança, sigilo profissional
  'student_sensitive', 'aluno_restricoes', 'antropometria', 'aee_atendimentos', 'aee_planos', 'mediacoes', 'apoio_casos', 'apoio_registros',
  'encaminhamentos', 'guarda_restricoes', 'frequencia_afastamentos', 'reunioes_responsavel', 'reuniao_eventos', 'reuniao_destinos',
  'reuniao_envios_orgaos', 'household_members',
  -- conversas e mensagens com as famílias
  'messages', 'conversations', 'notifications', 'handoff_tasks', 'tool_executions', 'case_events',
  'whatsapp_avisos_bloqueio', 'whatsapp_channels', 'whatsapp_contacts', 'whatsapp_inbound', 'whatsapp_outbox',
  -- credenciais, códigos e acessos
  'app_sessions', 'familia_codigos', 'familia_qr', 'familia_trocas_numero', 'familia_vinculos', 'uk_codigos', 'declaracoes',
  'ponto_credenciais', 'ponto_desafios', 'oraculo_chaves', 'sim_acesso', 'sim_liberacoes', 'sim_tentativas', 'suporte_anydesk',
  -- rastros técnicos e configuração interna
  'audit_log', 'audit_chain_head', 'gestao_hist', 'eventos_seguranca', 'limites_taxa', 'arquivos', 'arquivos_descartar', 'import_batches',
  'rotas_cache', 'pend_estat_cache', 'pend_sinc', 'bolsa_familia_cache', 'feature_flags', 'ponto_demo_estado', 'demo_metrics', 'demo_quadro_extra',
  'oraculo_perguntas', 'oraculo_indicadores', 'oraculo_detalhes', 'oraculo_fatos', 'oraculo_assuntos', 'oraculo_temas', 'oraculo_base_descricoes',
  'sim_agentes', 'sim_municipios', 'sim_parametros', 'classificacao_dados', 'iaraflix_progresso', 'tenants'
]::text[] $$;

-- tabelas em que o texto livre é da operação (chamado, cardápio, evento), não de pessoa
create or replace function iara.oraculo_base_texto_livre() returns text[]
language sql immutable
as $$ select array[
  'calendario_eventos', 'eventos', 'mural_publicacoes', 'knowledge_articles', 'service_catalog', 'iaraflix_trilhas', 'iaraflix_aulas',
  'iaraflix_perguntas', 'videos_familia', 'manutencao_chamados', 'manutencao_eventos', 'materiais', 'materiais_movimentos', 'patrimonio_eventos',
  'patrimonio_transferencias', 'suporte_chamados', 'inventarios', 'inventario_itens', 'data_quality_issues', 'frequencia_parametros',
  'frequencia_modelos', 'jornada_padrao', 'rules', 'pend_tipos', 'pend_rotinas', 'uk_campanhas', 'uk_itens', 'uk_kit_itens', 'org_setores',
  'org_funcoes', 'orgaos_destinatarios', 'restricoes_alimentares', 'preparacoes', 'biblioteca_titulos', 'aulas_registros', 'apoio_areas',
  'publicos_modelos', 'ocorrencia_modelos', 'reuniao_avisos_modelo', 'oferta_motivos_recusa', 'salas', 'permissions', 'organizational_roles',
  'matriz_curricular', 'territories', 'setores_censitarios', 'ideb_escolas', 'education_units', 'unit_offers', 'unit_grade_stats', 'unit_shift_stats'
]::text[] $$;

-- uma coluna entra se a classificação de dados e o nome dela não indicarem saúde, proteção, documento, contato, credencial ou texto de pessoa
create or replace function iara.oraculo_base_coluna_liberada(p_tabela text, p_coluna text) returns boolean
language sql stable
as $$
  select case
    -- exceções pontuais: o aluno da ocorrência (pode ser caso de proteção) e a posição de quem bateu o ponto
    when (p_tabela, p_coluna) in (('ocorrencias', 'student_id'), ('ponto_marcacoes', 'lat'), ('ponto_marcacoes', 'lng'), ('ponto_marcacoes', 'precisao_m')) then false
    when c.nivel = 'SENSIVEL' then false
    -- contato institucional (da escola, do setor, do órgão) entra
    when p_tabela in ('education_units', 'org_setores', 'orgaos_destinatarios') and c.nivel is null then true
    when c.categoria ~*'(saúde|deficiência|proteção|judicial|processual|documento|contato|localização|socioeconômico|composição familiar|vida familiar|consentimento|credencial|código|whatsapp|acesso remoto|texto livre|relato|orientação|comunicação|registro técnico|medida do corpo|comportamento|opinião|resposta à família|anotação|nota de conclusão|motivo|resultado do uso|servidor que gerou|pedido a que|expediente|racial|religiosa|elegibilidade|critérios|desenvolvimento)' then false
    when p_coluna ~* '(senha|hash|token|segredo|secret|credencial|telefone|phone|whatsapp|e164|email|laudo|diagnost|medic|alerg|atestado|ip_address|user_agent|payload)'
      or p_coluna ~* '(^|_)(cpf|rg|nis|cid|jid|sus_card|chave|settings|context|before_json|after_json|ata|participantes)(_|$)' then false
    when p_coluna ~* '^(observacao|observacoes|descricao|texto|resumo|notes|body|message|summary|conteudo|justificativa|motivo_texto|relato|manifestacao|posicao_escola|posicao_responsavel|solucoes|detalhe|details|resolution_notes|description|resposta)$'
      and not p_tabela = any (iara.oraculo_base_texto_livre()) then false
    else true end
  from (select 1) x left join iara.classificacao_dados c on c.tabela = p_tabela and c.coluna = p_coluna
$$;

-- refaz as concessões (revogar a tabela revoga também as colunas)
create or replace function iara.oraculo_base_conceder() returns jsonb
language plpgsql
set search_path = iara, public
as $$
declare
  t record;
  v_cols text[];
  n_t integer := 0;
  n_c integer := 0;
begin
  revoke select on all tables in schema iara from oraculo_leitor;
  for t in
    select c.oid, c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'iara' and c.relkind in ('r', 'p', 'v', 'm') and not (c.relname = any (iara.oraculo_base_fora()))
  loop
    v_cols := array(select a.attname::text from pg_attribute a
                    where a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped and iara.oraculo_base_coluna_liberada(t.relname, a.attname)
                    order by a.attnum);
    if cardinality(v_cols) > 0 then
      execute format('grant select (%s) on iara.%I to oraculo_leitor', (select string_agg(quote_ident(x), ', ') from unnest(v_cols) x), t.relname);
      n_t := n_t + 1;
      n_c := n_c + cardinality(v_cols);
    end if;
  end loop;
  return jsonb_build_object('tabelas', n_t, 'colunas', n_c);
end $$;

-- 3. O mapa: o que é cada tabela e como se liga ---------------------------------------------------------------------------------------
create table if not exists iara.oraculo_base_descricoes (
  tabela text primary key,
  descricao text not null,
  ordem integer not null default 100
);
alter table iara.oraculo_base_descricoes enable row level security;

insert into iara.oraculo_base_descricoes (tabela, descricao, ordem) values
('education_units', 'Unidades da rede (escolas e CMEIs): name, short_name, unit_type_label, endereço (address_line, neighborhood, postal_code), telefone (phone, poucos preenchidos), diretor(a) (director_name, director_source, director_status), código INEP (inep_code), região (macro_territory_id → territories.id), stages_text, offers_text, capacidade e matrículas do Censo, has_aee, lat, lng. Quase tudo se liga a ela por unit_id.', 1),
('ideb_escolas', 'Ideb do INEP por escola e edição (ano ímpar de 2005 a 2025): ideb, meta, aprovacao, nota_mat, nota_lp. Liga com education_units por ideb_escolas.inep = education_units.inep_code. Use a edição mais recente (max(ano)) com ideb não nulo.', 2),
('ideb_rede', 'Ideb da rede municipal (anos iniciais) por edição.', 3),
('territories', 'Regiões: kind = AREA_PONDERACAO (áreas de ponderação do IBGE, "AP 017") e bairros; name, code. education_units.macro_territory_id aponta para cá.', 4),
('students', 'Alunos: full_name, social_name, birth_date, gender, status, student_registry_number, inep_id, parent1_name e parent2_name (filiação). Turma e unidade atuais pela matrícula ativa (enrollments).', 10),
('enrollments', 'Matrículas: student_id, class_id, unit_id, school_year, status (ACTIVE), enrollment_date, entry_type, exit_type.', 11),
('classes', 'Turmas: unit_id, school_year, stage_id, grade_level_id (→ grade_levels), class_name, shift (turno), authorized_capacity, active_enrollments_count, offerable_vacancies_count.', 12),
('grade_levels', 'Anos e grupos (Infantil 0 a 5, 1º ao 5º ano, EJA): code, name, stage_id (→ education_stages).', 13),
('education_stages', 'Etapas de ensino (Educação Infantil, Ensino Fundamental, EJA).', 14),
('guardians', 'Responsáveis: full_name, social_name, gender, birth_date (contatos, documentos, endereço e renda não estão liberados). Ligação com os alunos em student_guardians.', 15),
('student_guardians', 'Quem é responsável por qual aluno: student_id, guardian_id, relationship, is_primary, can_pick_up.', 16),
('staff', 'Servidores do quadro da SEDUC: full_name, cargo, role, bond (vínculo), unit_id (lotação principal), matricula_funcional, data_admissao, escolaridade, formacao, carga_horaria_semanal, area_atuacao, situacao. Os diretores das escolas não estão aqui: estão em education_units.director_name. O IARA não tem telefone pessoal de servidor.', 20),
('staff_lotacoes', 'Histórico de lotação dos servidores: staff_id, unit_id, funcao, inicio, fim (fim nulo = lotação atual).', 21),
('staff_formacoes', 'Cursos e formações dos servidores: staff_id, titulo, tipo, instituicao, carga_horaria, concluido_em.', 22),
('ponto_marcacoes', 'Ponto eletrônico dos servidores: staff_id, unit_id, data, tipo (ENTRADA ou SAIDA), marcada_em, metodo, fora_da_unidade. Servidor sem ENTRADA num dia letivo (veja calendario_eventos e o fim de semana) esteve ausente; absenteísmo = dias sem ENTRADA ÷ dias letivos esperados.', 23),
('ponto_justificativas', 'Justificativas de ponto: staff_id, unit_id, data, tipo (ATESTADO ou ESQUECIMENTO), situacao, tratada_em.', 24),
('ponto_fechamentos', 'Fechamento mensal do ponto por unidade.', 25),
('class_staff', 'Professores de cada turma: class_id, staff_id, role_type, is_primary, hours_per_week.', 26),
('horarios_turma', 'Grade de aulas: class_id, dia_semana, aula, componente, staff_id.', 27),
('frequencia_registros', 'Chamadas: uma por turma e dia (class_id, data, registrado_em). Turma sem registro num dia letivo = chamada não feita.', 30),
('frequencia_faltas', 'Faltas lançadas nas chamadas: registro_id (→ frequencia_registros.id), student_id, tipo (FALTA ou FALTA_JUSTIFICADA). Frequência da turma no dia = 1 − faltas ÷ alunos ativos da turma.', 31),
('frequencia_alertas', 'Alertas de frequência (faltas consecutivas ou percentual baixo): student_id, class_id, unit_id, tipo, percentual, situacao, detectado_em.', 32),
('frequencia_ausencias', 'Ausências acompanhadas: student_id, unit_id, data, situacao, nivel, risco, respondido_em.', 33),
('busca_ativa_casos', 'Busca ativa (aluno faltoso acompanhado): student_id, unit_id, etapa, urgente, situacao, aberto_em, encerrado_em.', 34),
('notas', 'Notas por aluno, componente e bimestre: student_id, class_id, componente, ano, bimestre, nota, recuperacao.', 40),
('resultados_finais', 'Resultado do ano por aluno: situacao (aprovado, retido...), frequencia_pct, unit_id, turma, ano.', 41),
('alfabetizacao_sondagens', 'Sondagens de alfabetização: student_id, class_id, ano, ciclo, nivel, leitura, data.', 42),
('conselhos_classe', 'Conselhos de classe por turma e bimestre.', 43),
('waiting_list_entries', 'Fila de espera por vaga: student_id, preferred_unit_id (→ education_units), grade_level_id, status, priority_score, position, entered_at, distâncias até a unidade.', 50),
('vacancy_offers', 'Ofertas de vaga feitas à fila: student_id, unit_id, class_id, offered_at, expires_at, status, decline_code.', 51),
('rematriculas', 'Rematrícula do ano seguinte: student_id, unidade de origem e de destino, situacao, confirmada_em.', 52),
('transferencias', 'Pedidos de transferência entre unidades: student_id, unit_origem, unit_destino, situacao, criada_em.', 53),
('transporte_rotas', 'Rotas do transporte escolar: codigo, unit_id, turno, veiculo_id, motorista_id, km, situacao.', 60),
('transporte_viagens', 'Viagens do transporte escolar: rota_id, data, sentido, situacao (NAO_REALIZADA = não aconteceu), atraso_min, alunos_previstos, alunos_transportados.', 61),
('transporte_alunos', 'Alunos atendidos por rota: student_id, rota_id, inicio, fim.', 62),
('transporte_veiculos', 'Frota: placa, tipo, capacidade, acessivel, ano, operador, vistoria_validade.', 63),
('transporte_motoristas', 'Motoristas: nome, cnh_validade, curso_validade, operador, situacao.', 64),
('refeicoes_servidas', 'Merenda servida: unit_id, data, refeicao, quantidade, adaptadas.', 70),
('cardapios', 'Cardápios semanais por faixa: semana_inicio, situacao; itens em cardapio_itens (dia_semana, refeicao, preparacao_codigo → preparacoes).', 71),
('manutencao_chamados', 'Chamados de manutenção predial: unit_id, categoria, local, descricao, prioridade, afeta_seguranca, situacao, aberto_em, prazo, concluido_em, custo.', 80),
('materiais', 'Materiais e patrimônio por unidade: nome, categoria, quantidade, minimo, estado, situacao_patrimonio.', 81),
('pedidos', 'Pedidos ao almoxarifado: unit_id, situacao, prioridade, solicitado_em, recebido_em; itens em pedido_itens.', 82),
('ocorrencias', 'Ocorrências escolares por unidade e turma: tipo, gravidade, ocorrida_em, situacao, instancia (sem o aluno e sem a descrição: casos de proteção ficam fora).', 90),
('pendencias', 'Central de pendências: o que cada unidade ou servidor tem a cumprir (titulo, tipo, papel, unit_id, staff_id, prazo, situacao).', 91),
('calendario_eventos', 'Calendário da rede: feriados, recessos, eventos (inicio, fim, tipo, suspende_aulas, unit_id nulo = rede toda).', 92),
('uk_necessidades', 'Uniformes e kits por aluno: ano, conteudo (UNIFORME ou KIT), situacao (RETIRADA, DISPONIVEL...), prazo_retirada, retirada_em, retirada_por_nome.', 93),
('service_cases', 'Protocolos de atendimento às famílias: case_type, status, unit_id, opened_at, sla_due_at, closed_at.', 94),
('biblioteca_emprestimos', 'Empréstimos da biblioteca: unit_id, student_id, retirada_em, prevista, devolvido_em.', 95),
('salas', 'Salas das unidades: tipo, capacidade, area_m2, acessivel.', 96),
('iaraflix_participacoes', 'Treinamentos IARAFLIX feitos pelos servidores: staff_id, trilha_id, aulas_concluidas, concluida_em.', 97),
('setores_censitarios', 'Setores censitários do IBGE: pessoas, domicílios, crianças de 0 a 4 anos, bairro, área de ponderação.', 98),
('org_setores', 'Organograma da SEDUC: sigla, nome, competencias, email e telefone do setor.', 99)
on conflict (tabela) do update set descricao = excluded.descricao, ordem = excluded.ordem;

-- 4. A execução: SELECT pelo oraculo_leitor -------------------------------------------------------------------------------------------
create or replace function oraculo_exec.executar(p_sql text, p_lim integer) returns jsonb
language plpgsql security definer
set search_path = iara, extensions, pg_catalog, pg_temp
as $$
declare
  r jsonb;
begin
  execute format('select coalesce(jsonb_agg(to_jsonb(q)), ''[]''::jsonb) from (select * from (%s) as consulta limit %s) q', p_sql, p_lim) into r;
  return r;
end $$;
alter function oraculo_exec.executar(text, integer) owner to oraculo_leitor;
revoke all on function oraculo_exec.executar(text, integer) from public;
grant execute on function oraculo_exec.executar(text, integer) to postgres;

-- 5. A API do Oráculo -----------------------------------------------------------------------------------------------------------------
-- p: busca (palavras) | tabela (uma tabela em detalhe) | nada (a lista de tabelas)
create or replace function api.oraculo_catalogo(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_tab text := nullif(btrim(coalesce(p ->> 'tabela', '')), '');
  v_pal text[] := array(select w from unnest(string_to_array(iara.norm(coalesce(p ->> 'busca', '')), ' ')) w where length(w) >= 3);
  v_ligacoes constant text := 'Ligações usuais: unit_id, preferred_unit_id, unit_origem e unit_destino → education_units.id; student_id → students.id; '
    || 'staff_id → staff.id; class_id → classes.id; guardian_id → guardians.id; grade_level_id → grade_levels.id; rota_id → transporte_rotas.id; '
    || 'macro_territory_id e territory_id → territories.id; ideb_escolas.inep → education_units.inep_code.';
  v_regras constant text := 'Só leitura. Liste as colunas (SELECT * não funciona). Saúde, deficiência, laudos, casos de proteção, documentos, contatos '
    || 'e endereços das famílias, credenciais e conversas não estão liberados.';
begin
  perform iara.require_perm('oraculo.prefeito');
  if v_tab is not null then
    return (
      with t as (select c.oid, c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'iara' and c.relname = v_tab)
      select case when not exists (select 1 from t) then jsonb_build_object('erro', 'Tabela não encontrada: ' || v_tab)
        else (select jsonb_build_object(
          'tabela', t.relname,
          'descricao', (select d.descricao from iara.oraculo_base_descricoes d where d.tabela = t.relname),
          'linhas_aprox', (select greatest(c.reltuples, 0)::bigint from pg_class c where c.oid = t.oid),
          'colunas', (select coalesce(jsonb_agg(jsonb_build_object('coluna', a.attname, 'tipo', format_type(a.atttypid, a.atttypmod)) order by a.attnum), '[]')
                      from pg_attribute a where a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped and has_column_privilege('oraculo_leitor', t.oid, a.attnum, 'SELECT')),
          'aponta_para', (select coalesce(jsonb_agg(distinct (select a.attname from pg_attribute a where a.attrelid = k.conrelid and a.attnum = k.conkey[1])
                                                    || ' → ' || k.confrelid::regclass::text), '[]')
                          from pg_constraint k where k.conrelid = t.oid and k.contype = 'f'),
          'apontada_por', (select coalesce(jsonb_agg(distinct k.conrelid::regclass::text || '.' || (select a.attname from pg_attribute a where a.attrelid = k.conrelid and a.attnum = k.conkey[1])), '[]')
                           from pg_constraint k where k.confrelid = t.oid and k.contype = 'f'),
          'regras', v_regras, 'ligacoes', v_ligacoes) from t) end);
  end if;

  return (
    with tabs as (
      select c.oid, c.relname::text tabela, greatest(c.reltuples, 0)::bigint linhas, d.descricao, coalesce(d.ordem, 100) ordem,
             array(select a.attname::text from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                   and has_column_privilege('oraculo_leitor', c.oid, a.attnum, 'SELECT') order by a.attnum) cols
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      left join iara.oraculo_base_descricoes d on d.tabela = c.relname
      where n.nspname = 'iara' and c.relkind in ('r', 'p', 'v', 'm')
    ), liberadas as (select * from tabs where cardinality(cols) > 0),
    achadas as (
      select l.*, (select count(*) from unnest(v_pal) w where iara.norm(l.tabela || ' ' || coalesce(l.descricao, '') || ' ' || array_to_string(l.cols, ' ')) like '%' || w || '%') acertos
      from liberadas l
    )
    select case when cardinality(v_pal) = 0 then
      jsonb_build_object('tabelas', (select jsonb_agg(jsonb_build_object('tabela', tabela, 'linhas_aprox', linhas) || case when descricao is not null then jsonb_build_object('descricao', descricao) else '{}'::jsonb end
                                                       order by ordem, tabela) from liberadas),
                         'como_usar', 'Para ver as colunas de uma tabela, chame de novo com tabela; para procurar, com busca.', 'regras', v_regras, 'ligacoes', v_ligacoes)
    else
      jsonb_build_object('tabelas', coalesce((select jsonb_agg(jsonb_build_object('tabela', tabela, 'descricao', descricao, 'linhas_aprox', linhas, 'colunas', array_to_string(cols, ', '))
                                                              order by acertos desc, ordem, tabela)
                                              from (select * from achadas where acertos > 0 order by acertos desc, ordem, tabela limit 12) a), '[]'::jsonb),
                         'regras', v_regras, 'ligacoes', v_ligacoes)
    end);
end $$;

-- p: sql (SELECT ou WITH), finalidade (o que o Prefeito perguntou)
create or replace function api.oraculo_consulta(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_sql text := btrim(coalesce(p ->> 'sql', ''));
  v_fim text := left(btrim(coalesce(p ->> 'finalidade', '')), 300);
  v_lim constant integer := 200;
  r jsonb;
  v_out jsonb := '[]'::jsonb;
  v_tam integer := 0;
  v_item jsonb;
  v_trunc boolean := false;
begin
  perform iara.require_perm('oraculo.prefeito');
  v_sql := btrim(regexp_replace(v_sql, ';\s*$', ''));
  if v_sql = '' then return jsonb_build_object('erro', 'Escreva a consulta (SELECT ou WITH).'); end if;
  if length(v_sql) > 8000 then return jsonb_build_object('erro', 'Consulta longa demais: divida em partes.'); end if;
  if v_sql !~* '^(select|with)\M' then return jsonb_build_object('erro', 'A consulta precisa começar com SELECT ou WITH.'); end if;
  if position(';' in v_sql) > 0 then return jsonb_build_object('erro', 'Uma consulta por vez, sem ponto e vírgula.'); end if;
  if v_sql ~* '\m(insert|update|delete|merge|truncate|drop|alter|create|grant|revoke|copy|call|vacuum|lock|listen|notify|unlisten|refresh|prepare|execute|deallocate|discard|cluster|reindex|checkpoint)\M'
     or v_sql ~* '(pg_sleep|set_config|pg_read|pg_ls_|lo_import|lo_export|lo_get|pg_terminate|pg_cancel|pg_advisory|dblink|pg_notify|query_to_xml|pg_stat_file)' then
    return jsonb_build_object('erro', 'O Oráculo só lê: use apenas SELECT.');
  end if;

  -- registro: quem consultou, para quê e o quê (antes de passar a transação a só leitura)
  perform iara.audit_event('ORACULO_CONSULTA', 'oraculo_consulta', null, null,
                           left(coalesce(nullif(v_fim, ''), 'Consulta do Oráculo') || E'\n' || v_sql, 3000));
  perform set_config('transaction_read_only', 'on', true);

  begin
    r := oraculo_exec.executar(v_sql, v_lim + 1);
  exception when others then
    return jsonb_build_object('erro', sqlerrm,
      'dica', case when sqlstate = '42501' then 'Essa tabela ou coluna não está liberada para o Oráculo (veja catalogo_da_base com a tabela).'
                   when sqlstate in ('42703', '42P01') then 'Confira o nome da tabela e das colunas em catalogo_da_base.'
                   else 'Corrija a consulta e tente de novo.' end);
  end;

  if jsonb_array_length(r) > v_lim then v_trunc := true; end if;
  for v_item in select e.value from jsonb_array_elements(r) with ordinality e(value, n) where e.n <= v_lim order by e.n loop
    v_tam := v_tam + length(v_item::text);
    if v_tam > 60000 and jsonb_array_length(v_out) > 0 then v_trunc := true; exit; end if;
    v_out := v_out || jsonb_build_array(v_item);
  end loop;
  return jsonb_build_object('linhas', v_out, 'quantidade', jsonb_array_length(v_out), 'truncado', v_trunc)
    || case when v_trunc then jsonb_build_object('aviso', 'Resultado cortado: agregue no SQL (count, sum, group by) ou filtre mais.') else '{}'::jsonb end;
end $$;

-- 6. Unidades com endereço, telefone e diretor(a) -----------------------------------------------------------------------------------
create or replace function api.oraculo_unidades(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_b text := iara.norm(coalesce(p ->> 'busca', ''));
begin
  perform iara.require_perm('oraculo.prefeito');
  return jsonb_build_object(
    'unidades', (select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'nome', u.short_name, 'nome_completo', u.name, 'tipo', u.unit_type_label, 'regiao', t.name,
                                                            'endereco', nullif(concat_ws(', ', u.address_line, u.neighborhood, nullif(u.postal_code, '')), ''),
                                                            'telefone', u.phone, 'diretor', u.director_name, 'inep', u.inep_code, 'etapas', u.stages_text)
                                           order by u.short_name), '[]')
                 from (select * from iara.education_units where v_b = '' or iara.norm(short_name || ' ' || name) like '%' || v_b || '%' order by short_name limit 60) u
                 left join iara.territories t on t.id = u.macro_territory_id),
    'regioes', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'nome', t.name) order by t.sort), '[]')
                from iara.territories t where t.kind = 'AREA_PONDERACAO' and (v_b = '' or iara.norm(t.name) like '%' || v_b || '%')),
    'total_unidades', (select count(*) from iara.education_units));
end $$;

revoke all on function iara.oraculo_base_fora(), iara.oraculo_base_texto_livre(), iara.oraculo_base_coluna_liberada(text, text),
  iara.oraculo_base_conceder() from public;

select iara.oraculo_base_conceder();

commit;
