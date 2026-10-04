-- IARA Educa — 007 · Dados de referência configuráveis (tenant, hierarquia, perfis, permissões, regras, serviços)
-- Conteúdos marcados "DEMO" são parametrizações de referência para demonstração e devem ser validados pela SEDUC.
begin;

alter table iara.territories drop constraint territories_kind_check;
alter table iara.territories add constraint territories_kind_check check (kind in ('MUNICIPIO', 'MACRORREGIAO', 'BAIRRO', 'DISTRITO'));
alter table iara.education_units add column influence_area extensions.geography(MultiPolygon, 4326);

insert into iara.tenants (id, name, state, ibge_code, settings) values
(1, 'Maringá', 'PR', '4115200', jsonb_build_object(
  'school_year', 2026,
  'age_cutoff', '03-31',
  'default_radius_m', 2000,
  'offer_hours', 48,
  'city_center', jsonb_build_array(-23.4253, -51.9386),
  'demo_mode', true,
  'network_name', 'Rede Municipal de Ensino de Maringá',
  'secretariat', 'Secretaria Municipal de Educação — SEDUC',
  'official_reference_date', '03/10/2026'
));

insert into iara.education_stages (id, tenant_id, code, name, short_name, color, sort) values
(1, 1, 'EI', 'Educação Infantil', 'Infantil', '#A846E8', 1),
(2, 1, 'EF', 'Ensino Fundamental — Anos Iniciais', 'Fundamental', '#1594D2', 2),
(3, 1, 'EJA', 'Educação de Jovens e Adultos', 'EJA', '#00A983', 3),
(4, 1, 'EE', 'Educação Especial (agregado)', 'Ed. Especial', '#F2B640', 4),
(5, 1, 'AC', 'Atividades Complementares', 'Complementares', '#697586', 5);

insert into iara.grade_levels (id, tenant_id, stage_id, code, name, short_name, census_label, min_age_months, max_age_months, reference_capacity, sort) values
(1, 1, 1, 'CRECHE', 'Creche', 'Creche', 'Creche', 4, 47, 20, 1),
(2, 1, 1, 'PRE', 'Pré-escola', 'Pré', 'Pré-escola', 48, 71, 25, 2),
(3, 1, 2, 'EF1', '1º ano', '1º ano', '1º ano', 72, 83, 30, 3),
(4, 1, 2, 'EF2', '2º ano', '2º ano', '2º ano', 84, 95, 30, 4),
(5, 1, 2, 'EF3', '3º ano', '3º ano', '3º ano', 96, 107, 30, 5),
(6, 1, 2, 'EF4', '4º ano', '4º ano', '4º ano', 108, 119, 30, 6),
(7, 1, 2, 'EF5', '5º ano', '5º ano', '5º ano', 120, 131, 30, 7),
(8, 1, 3, 'EJA_AI', 'EJA — Anos Iniciais', 'EJA', 'Fundamental - anos iniciais', 180, 1200, 25, 8);

-- ---------------------------------------------------------------------------
-- Perfis (estrutura SEDUC Maringá) — configuráveis
-- ---------------------------------------------------------------------------
insert into iara.organizational_roles (code, tenant_id, name, short_name, description, scope_type, stage_filter, question, org_unit, is_persona, sort) values
('PREFEITO', 1, 'Prefeito(a)', 'Prefeito', 'Visão estratégica e agregada da cidade inteira, sem dados pessoais.', 'AGGREGATE', null, 'Onde precisamos investir?', 'Gabinete do Prefeito', true, 1),
('SECRETARIO', 1, 'Secretário(a) Municipal de Educação', 'Secretária', 'Opera e planeja a rede: demanda x oferta, gargalos, expansão e auditoria executiva.', 'NETWORK', null, 'Onde está o gargalo?', 'Secretaria Municipal de Educação', true, 2),
('SUPERINTENDENCIA', 1, 'Superintendência', 'Superintendência', 'Metas, desempenho operacional, SLAs e qualidade de atualização dos dados.', 'NETWORK', null, 'Metas e prazos estão sendo cumpridos?', 'Superintendência', true, 3),
('ANALISTA_CENTRAL', 1, 'Analista · Central de Vagas', 'Central de Vagas', 'Fila de atendimentos, busca inteligente de vaga, fila e ofertas.', 'NETWORK', null, 'Qual vaga posso oferecer agora?', 'Diretoria de Gestão Educacional · Central de Vagas', true, 4),
('GERENCIA_EI', 1, 'Gerência de Educação Infantil', 'Ger. Infantil', 'Visão automaticamente filtrada para CMEIs, creche e pré-escola.', 'NETWORK', 'EI', 'Como está a demanda por creche e pré-escola?', 'Diretoria de Ensino · Gerência de Educação Infantil', true, 5),
('DIRETOR_UNIDADE', 1, 'Diretor(a) de Escola/CMEI', 'Direção', 'Somente a própria unidade: turmas, vagas, fila local, equipe e pendências.', 'UNIT', null, 'Como está minha unidade?', 'Direção de unidade escolar', true, 6),
('SECRETARIA_ESCOLAR', 1, 'Secretaria Escolar/CMEI', 'Secretaria Escolar', 'Matrícula, documentos, transferências e atualização cadastral da unidade.', 'UNIT', null, 'O que falta para concluir esta matrícula?', 'Chefia de Secretaria de Escola/CMEI', true, 7),
('ATENDIMENTO', 1, 'Atendimento ao Cidadão', 'Atendimento', 'Acesso controlado ao necessário para o atendimento; sem dados pedagógicos sensíveis.', 'NETWORK', null, 'Como resolvo o pedido desta família agora?', 'Central de Atendimento', true, 8),
('INOVACAO', 1, 'Diretoria de Inovação Educacional', 'Inovação', 'Qualidade de dados, integrações, uso da plataforma e analytics.', 'NETWORK', null, 'Os dados estão completos e confiáveis?', 'Diretoria de Inovação Educacional', true, 9),
('CIDADAO', 1, 'Cidadão / Responsável', 'Responsável', 'Portal da família: vagas, protocolos, fila, ofertas e dados da criança.', 'GUARDIAN', null, 'Onde meu filho será atendido e o que preciso fazer?', 'Portal do Cidadão', true, 10);

insert into iara.permissions (code, description, is_sensitive) values
('units.read', 'Consultar unidades e dados públicos', false),
('kpi.network', 'Indicadores agregados da rede', false),
('quality.read', 'Painel de qualidade de dados', false),
('classes.read', 'Consultar turmas (capacidade, ocupação, vagas)', false),
('students.read', 'Consultar ficha do aluno', true),
('students.read_sensitive', 'Consultar AEE, saúde, laudos e restrições', true),
('students.write', 'Cadastrar/atualizar aluno', true),
('guardians.read', 'Consultar responsáveis', true),
('guardians.read_contacts', 'Ver contatos completos (sem máscara)', true),
('guardians.write', 'Cadastrar/atualizar responsável', true),
('cases.read', 'Consultar atendimentos/protocolos', true),
('cases.write', 'Abrir e movimentar atendimentos', true),
('cases.assign', 'Atribuir atendimentos', false),
('queue.read', 'Consultar fila de espera', true),
('queue.manage', 'Inserir/ajustar entradas na fila', true),
('queue.recalculate', 'Recalcular fila pelas regras vigentes', false),
('offers.create', 'Registrar oferta de vaga', true),
('offers.respond', 'Registrar resposta da família a uma oferta', true),
('offers.respond_own', 'Responder às próprias ofertas (cidadão)', true),
('enrollment.confirm', 'Confirmar matrícula', true),
('vacancy.block', 'Bloquear/desbloquear vagas com justificativa', false),
('documents.manage', 'Receber e validar documentos', true),
('documents.submit_own', 'Enviar documentos (cidadão)', true),
('cases.write_own', 'Abrir protocolo próprio (cidadão)', true),
('audit.read', 'Consultar trilha de auditoria', true),
('reports.export', 'Exportar relatórios (auditado)', true),
('conversations.read', 'Consultar conversas da IARA', true),
('conversations.takeover', 'Assumir/devolver conversas', true),
('config.read', 'Consultar regras e configurações', false),
('rules.manage', 'Validar e versionar regras', false),
('classes.open', 'Aprovar abertura de turmas / cenários de expansão', false);

insert into iara.role_permissions (role_code, permission_code)
select r, p from (values
  ('PREFEITO', 'units.read'), ('PREFEITO', 'kpi.network'), ('PREFEITO', 'quality.read'),

  ('SECRETARIO', 'units.read'), ('SECRETARIO', 'kpi.network'), ('SECRETARIO', 'quality.read'), ('SECRETARIO', 'classes.read'),
  ('SECRETARIO', 'students.read'), ('SECRETARIO', 'guardians.read'), ('SECRETARIO', 'cases.read'), ('SECRETARIO', 'cases.write'),
  ('SECRETARIO', 'cases.assign'), ('SECRETARIO', 'queue.read'), ('SECRETARIO', 'queue.manage'), ('SECRETARIO', 'queue.recalculate'),
  ('SECRETARIO', 'offers.create'), ('SECRETARIO', 'offers.respond'), ('SECRETARIO', 'enrollment.confirm'), ('SECRETARIO', 'vacancy.block'),
  ('SECRETARIO', 'documents.manage'), ('SECRETARIO', 'audit.read'), ('SECRETARIO', 'reports.export'), ('SECRETARIO', 'conversations.read'),
  ('SECRETARIO', 'conversations.takeover'), ('SECRETARIO', 'config.read'), ('SECRETARIO', 'rules.manage'), ('SECRETARIO', 'classes.open'),

  ('SUPERINTENDENCIA', 'units.read'), ('SUPERINTENDENCIA', 'kpi.network'), ('SUPERINTENDENCIA', 'quality.read'), ('SUPERINTENDENCIA', 'classes.read'),
  ('SUPERINTENDENCIA', 'students.read'), ('SUPERINTENDENCIA', 'guardians.read'), ('SUPERINTENDENCIA', 'cases.read'), ('SUPERINTENDENCIA', 'cases.assign'),
  ('SUPERINTENDENCIA', 'queue.read'), ('SUPERINTENDENCIA', 'audit.read'), ('SUPERINTENDENCIA', 'reports.export'), ('SUPERINTENDENCIA', 'conversations.read'),
  ('SUPERINTENDENCIA', 'config.read'),

  ('ANALISTA_CENTRAL', 'units.read'), ('ANALISTA_CENTRAL', 'kpi.network'), ('ANALISTA_CENTRAL', 'quality.read'), ('ANALISTA_CENTRAL', 'classes.read'),
  ('ANALISTA_CENTRAL', 'students.read'), ('ANALISTA_CENTRAL', 'students.write'), ('ANALISTA_CENTRAL', 'guardians.read'), ('ANALISTA_CENTRAL', 'guardians.read_contacts'),
  ('ANALISTA_CENTRAL', 'guardians.write'), ('ANALISTA_CENTRAL', 'cases.read'), ('ANALISTA_CENTRAL', 'cases.write'), ('ANALISTA_CENTRAL', 'cases.assign'),
  ('ANALISTA_CENTRAL', 'queue.read'), ('ANALISTA_CENTRAL', 'queue.manage'), ('ANALISTA_CENTRAL', 'queue.recalculate'), ('ANALISTA_CENTRAL', 'offers.create'),
  ('ANALISTA_CENTRAL', 'offers.respond'), ('ANALISTA_CENTRAL', 'enrollment.confirm'), ('ANALISTA_CENTRAL', 'documents.manage'), ('ANALISTA_CENTRAL', 'audit.read'),
  ('ANALISTA_CENTRAL', 'reports.export'), ('ANALISTA_CENTRAL', 'conversations.read'), ('ANALISTA_CENTRAL', 'conversations.takeover'), ('ANALISTA_CENTRAL', 'config.read'),

  ('GERENCIA_EI', 'units.read'), ('GERENCIA_EI', 'kpi.network'), ('GERENCIA_EI', 'quality.read'), ('GERENCIA_EI', 'classes.read'),
  ('GERENCIA_EI', 'students.read'), ('GERENCIA_EI', 'guardians.read'), ('GERENCIA_EI', 'cases.read'), ('GERENCIA_EI', 'queue.read'),
  ('GERENCIA_EI', 'audit.read'), ('GERENCIA_EI', 'reports.export'), ('GERENCIA_EI', 'config.read'),

  ('DIRETOR_UNIDADE', 'units.read'), ('DIRETOR_UNIDADE', 'classes.read'), ('DIRETOR_UNIDADE', 'students.read'), ('DIRETOR_UNIDADE', 'students.read_sensitive'),
  ('DIRETOR_UNIDADE', 'students.write'), ('DIRETOR_UNIDADE', 'guardians.read'), ('DIRETOR_UNIDADE', 'guardians.read_contacts'), ('DIRETOR_UNIDADE', 'cases.read'),
  ('DIRETOR_UNIDADE', 'cases.write'), ('DIRETOR_UNIDADE', 'queue.read'), ('DIRETOR_UNIDADE', 'enrollment.confirm'), ('DIRETOR_UNIDADE', 'vacancy.block'),
  ('DIRETOR_UNIDADE', 'documents.manage'), ('DIRETOR_UNIDADE', 'audit.read'), ('DIRETOR_UNIDADE', 'reports.export'), ('DIRETOR_UNIDADE', 'conversations.read'),
  ('DIRETOR_UNIDADE', 'config.read'),

  ('SECRETARIA_ESCOLAR', 'units.read'), ('SECRETARIA_ESCOLAR', 'classes.read'), ('SECRETARIA_ESCOLAR', 'students.read'), ('SECRETARIA_ESCOLAR', 'students.read_sensitive'),
  ('SECRETARIA_ESCOLAR', 'students.write'), ('SECRETARIA_ESCOLAR', 'guardians.read'), ('SECRETARIA_ESCOLAR', 'guardians.read_contacts'), ('SECRETARIA_ESCOLAR', 'guardians.write'),
  ('SECRETARIA_ESCOLAR', 'cases.read'), ('SECRETARIA_ESCOLAR', 'cases.write'), ('SECRETARIA_ESCOLAR', 'queue.read'), ('SECRETARIA_ESCOLAR', 'enrollment.confirm'),
  ('SECRETARIA_ESCOLAR', 'documents.manage'), ('SECRETARIA_ESCOLAR', 'config.read'),

  ('ATENDIMENTO', 'units.read'), ('ATENDIMENTO', 'students.read'), ('ATENDIMENTO', 'students.write'), ('ATENDIMENTO', 'guardians.read'),
  ('ATENDIMENTO', 'guardians.read_contacts'), ('ATENDIMENTO', 'guardians.write'), ('ATENDIMENTO', 'cases.read'), ('ATENDIMENTO', 'cases.write'),
  ('ATENDIMENTO', 'queue.read'), ('ATENDIMENTO', 'conversations.read'), ('ATENDIMENTO', 'conversations.takeover'), ('ATENDIMENTO', 'config.read'),

  ('INOVACAO', 'units.read'), ('INOVACAO', 'kpi.network'), ('INOVACAO', 'quality.read'), ('INOVACAO', 'classes.read'),
  ('INOVACAO', 'audit.read'), ('INOVACAO', 'reports.export'), ('INOVACAO', 'config.read'),

  ('CIDADAO', 'units.read'), ('CIDADAO', 'offers.respond_own'), ('CIDADAO', 'documents.submit_own'), ('CIDADAO', 'cases.write_own')
) v(r, p);

-- ---------------------------------------------------------------------------
-- Motor de regras — versão 2026.01 (parametrização de referência DEMO)
-- ---------------------------------------------------------------------------
insert into iara.rules (tenant_id, rule_code, version, name, description, rule_type, condition, weight, source, justification, valid_from, test_reference, sort) values
(1, 'ELIM_UNIDADE_ATIVA', '2026.01', 'Unidade em funcionamento', 'Unidades com situação operacional a validar não entram no ranking nem recebem ofertas.', 'ELIMINATORIA', '{}', 0,
   'Parametrização de referência (DEMO) — validar com a SEDUC', 'Evita oferta em unidade sem turmas confirmadas.', date '2026-01-01', 'busca: unidade A_VALIDAR é excluída', 1),
(1, 'ELIM_ETAPA_SERIE', '2026.01', 'Atende a faixa/série', 'A unidade precisa ter turma ativa da série/faixa determinada pela data de nascimento.', 'ELIMINATORIA', '{}', 0,
   'Parametrização de referência (DEMO) — validar com a SEDUC', 'Compatibilidade pedagógica obrigatória.', date '2026-01-01', 'busca: CMEI não aparece para 1º ano', 2),
(1, 'ELIM_TURNO', '2026.01', 'Turno compatível', 'Quando o turno for obrigatório, exclui unidades sem turma naquele turno.', 'ELIMINATORIA', '{"when":"turno_obrigatorio"}', 0,
   'Parametrização de referência (DEMO) — validar com a SEDUC', 'Respeita restrição informada pela família.', date '2026-01-01', 'busca: turno obrigatório filtra turmas', 3),
(1, 'VAGA_OFERTAVEL', '2026.01', 'Vaga ofertável', 'Pontua unidades com vaga ofertável (capacidade − matrículas − bloqueios − reservas).', 'PONTUACAO_UNIDADE', '{}', 100,
   'Parametrização de referência (DEMO) — validar com a SEDUC', 'Vaga física bloqueada ou reservada não é ofertável.', date '2026-01-01', 'cálculo de vagas ofertáveis', 10),
(1, 'TERRITORIO_2KM', '2026.01', 'Território prioritário (até 2 km)', 'Residência a até 2 km da unidade. Usada na prioridade da fila e no ranking de unidades.', 'PRIORIDADE_FILA', '{"max_m":2000}', 80,
   'Parametrização de referência (DEMO) — validar com a norma municipal', 'Proximidade casa-escola reduz deslocamento.', date '2026-01-01', 'territorialidade: ST_DWithin 2000 m', 11),
(1, 'DISTANCIA', '2026.01', 'Distância casa-escola', 'Desconta pontos por quilômetro de distância (linha reta).', 'PONTUACAO_UNIDADE', '{"per":"km"}', -10,
   'Parametrização de referência (DEMO) — validar com a SEDUC', 'Desempata unidades com vaga pela proximidade.', date '2026-01-01', 'ranking: unidade mais próxima primeiro', 12),
(1, 'IRMAO_NA_UNIDADE', '2026.01', 'Irmão(ã) na unidade', 'Irmão(ã) com matrícula ativa na unidade. Usada na prioridade da fila e no ranking.', 'PRIORIDADE_FILA', '{}', 60,
   'Parametrização de referência (DEMO) — validar com a norma municipal', 'Mantém irmãos na mesma unidade.', date '2026-01-01', 'fila: irmão matriculado soma 60', 13),
(1, 'AEE_UNIDADE', '2026.01', 'Unidade com AEE', 'Quando a criança precisa de AEE, pontua unidades com atendimento especializado confirmado.', 'PONTUACAO_UNIDADE', '{}', 20,
   'Parametrização de referência (DEMO) — validar com a SEDUC', 'Adequação ao atendimento especializado.', date '2026-01-01', 'ranking: AEE soma 20', 14),
(1, 'TURNO_PREFERIDO', '2026.01', 'Turno preferido disponível', 'Pontua unidades com turma no turno preferido.', 'PONTUACAO_UNIDADE', '{}', 15,
   'Parametrização de referência (DEMO) — validar com a SEDUC', 'Preferência declarada da família.', date '2026-01-01', 'ranking: turno soma 15', 15),
(1, 'FILA_PRESSAO', '2026.01', 'Crianças à frente na fila', 'Desconta 2 pontos por criança à frente na fila daquela unidade/faixa (máximo 20).', 'PONTUACAO_UNIDADE', '{"cap":20}', -2,
   'Parametrização de referência (DEMO) — validar com a SEDUC', 'A oferta sempre respeita a ordem da fila.', date '2026-01-01', 'ranking: fila reduz pontuação', 16),
(1, 'CADUNICO', '2026.01', 'Família no CadÚnico', 'Responsável com inscrição ativa no Cadastro Único.', 'PRIORIDADE_FILA', '{}', 40,
   'Parametrização de referência (DEMO) — validar com a norma municipal', 'Prioriza famílias em vulnerabilidade socioeconômica.', date '2026-01-01', 'fila: CadÚnico soma 40', 20),
(1, 'PCD_TEA_AEE', '2026.01', 'Criança com deficiência/TEA', 'Necessidade de AEE/inclusão registrada (detalhe com acesso restrito).', 'PRIORIDADE_FILA', '{}', 50,
   'Parametrização de referência (DEMO) — validar com a norma municipal', 'Garantia de inclusão.', date '2026-01-01', 'fila: AEE soma 50', 21),
(1, 'VULNERABILIDADE', '2026.01', 'Encaminhamento da rede de proteção', 'Encaminhamento formal (CRAS, CREAS, Conselho Tutelar) registrado por servidor.', 'PRIORIDADE_FILA', '{}', 70,
   'Parametrização de referência (DEMO) — validar com a norma municipal', 'Proteção integral da criança.', date '2026-01-01', 'fila: rede de proteção soma 70', 22),
(1, 'DATA_SOLICITACAO', '2026.01', 'Data da solicitação', 'Desempate: quem entrou antes na fila fica à frente.', 'DESEMPATE', '{}', 0,
   'Parametrização de referência (DEMO) — validar com a SEDUC', 'Ordem cronológica como critério final.', date '2026-01-01', 'fila: empate resolvido por data', 30),
(1, 'PRAZO_RESPOSTA_OFERTA', '2026.01', 'Prazo para responder à oferta', 'A família tem 48 horas para aceitar ou recusar a oferta.', 'PARAMETRO', '{"hours":48}', 0,
   'Parametrização de referência (DEMO) — validar com a SEDUC', 'Evita vaga parada.', date '2026-01-01', 'oferta: expires_at = offered_at + 48h', 40),
(1, 'RECUSA_OFERTA', '2026.01', 'Consequência da recusa', 'Na configuração de demonstração, a recusa devolve a criança à fila (categoria "recusou oferta") sem perda de pontuação.', 'PARAMETRO', '{"returns_to_queue":true,"keeps_priority":true}', 0,
   'Parametrização de referência (DEMO) — validar com a norma municipal', 'Consequências só conforme regra vigente.', date '2026-01-01', 'oferta: recusa volta à fila', 41),
(1, 'EXPIRACAO_OFERTA', '2026.01', 'Oferta expirada', 'Sem resposta no prazo, a oferta expira, a vaga é liberada e a criança volta à fila. Silêncio não é aceite nem desistência.', 'PARAMETRO', '{}', 0,
   'Parametrização de referência (DEMO) — validar com a SEDUC', 'Libera a vaga sem punir a família.', date '2026-01-01', 'oferta: expiração libera reserva', 42);

-- ---------------------------------------------------------------------------
-- Catálogo de serviços (DEMO — validar com a SEDUC)
-- ---------------------------------------------------------------------------
insert into iara.service_catalog (code, tenant_id, name, description, requirements, required_documents, sector, sla_days, actions, source, sort) values
('SOLICITACAO_VAGA', 1, 'Solicitação de vaga', 'Pedido de vaga na rede municipal (creche, pré-escola, 1º ao 5º ano, EJA).', 'Criança residente em Maringá; responsável identificado.', '{CERTIDAO,COMPROVANTE_ENDERECO,CPF}', 'Central de Vagas', 10, '{buscar_vaga,inserir_fila,ofertar}', 'Catálogo de serviços — DEMO', 1),
('MATRICULA', 1, 'Matrícula', 'Efetivação da matrícula após aceite de oferta.', 'Oferta aceita e documentos validados.', '{CERTIDAO,CPF,COMPROVANTE_ENDERECO,CARTAO_SUS,VACINACAO}', 'Secretaria Escolar', 5, '{validar_documentos,confirmar_matricula}', 'Catálogo de serviços — DEMO', 2),
('TRANSFERENCIA', 1, 'Transferência entre unidades', 'Mudança de unidade para aluno já atendido (não conta como criança sem atendimento).', 'Matrícula ativa na rede.', '{COMPROVANTE_ENDERECO}', 'Central de Vagas', 15, '{buscar_vaga,inserir_fila}', 'Catálogo de serviços — DEMO', 3),
('TROCA_TURNO', 1, 'Troca de turno', 'Mudança de turno na mesma unidade.', 'Matrícula ativa.', '{}', 'Secretaria Escolar', 10, '{analisar_turma}', 'Catálogo de serviços — DEMO', 4),
('INTEGRAL', 1, 'Educação integral', 'Pedido de passagem de período parcial para integral.', 'Matrícula ativa.', '{DECLARACAO_TRABALHO}', 'Gerência de Educação Integral', 15, '{inserir_fila}', 'Catálogo de serviços — DEMO', 5),
('ATUALIZACAO_CADASTRAL', 1, 'Atualização cadastral', 'Telefone, endereço e dados do responsável/aluno.', 'Identidade e vínculo verificados.', '{}', 'Secretaria Escolar', 3, '{atualizar_dados}', 'Catálogo de serviços — DEMO', 6),
('DOCUMENTO', 1, 'Declarações e documentos', 'Declaração de matrícula, histórico e outros documentos escolares.', 'Matrícula na rede.', '{}', 'Gerência de Documentação Escolar', 5, '{emitir_documento}', 'Catálogo de serviços — DEMO', 7),
('TRANSPORTE', 1, 'Transporte escolar', 'Solicitação ou dúvida sobre transporte escolar.', 'Critérios de elegibilidade do município.', '{COMPROVANTE_ENDERECO}', 'Gerência de Transporte Escolar', 10, '{encaminhar}', 'Catálogo de serviços — DEMO', 8),
('AEE', 1, 'AEE / inclusão', 'Atendimento educacional especializado e apoio à inclusão.', 'Encaminhamento por fluxo seguro; documentos sensíveis com acesso restrito.', '{LAUDO}', 'Gerência de Apoio Pedagógico Interdisciplinar', 15, '{encaminhar}', 'Catálogo de serviços — DEMO', 9),
('ALIMENTACAO', 1, 'Alimentação escolar', 'Cardápio, restrições e alergias alimentares.', 'Restrições de saúde exigem documento.', '{}', 'Gerência da Merenda Escolar', 10, '{encaminhar}', 'Catálogo de serviços — DEMO', 10),
('RECLAMACAO', 1, 'Reclamação ou sugestão', 'Manifestação encaminhada à ouvidoria/setor responsável.', null, '{}', 'Ouvidoria', 15, '{encaminhar}', 'Catálogo de serviços — DEMO', 11),
('DUVIDA', 1, 'Dúvida / informação', 'Orientação sobre serviços da SEDUC.', null, '{}', 'Atendimento ao Cidadão', 2, '{orientar}', 'Catálogo de serviços — DEMO', 12),
('RECURSO', 1, 'Recurso sobre classificação', 'Contestação de critério ou posição na fila — análise humana.', 'Protocolo de vaga existente.', '{}', 'Diretoria de Gestão Educacional', 15, '{analise_humana}', 'Catálogo de serviços — DEMO', 13),
('MUDANCA_ENDERECO', 1, 'Mudança de endereço', 'Atualiza território; não transfere automaticamente — sugere opções.', 'Comprovante do novo endereço.', '{COMPROVANTE_ENDERECO}', 'Central de Vagas', 5, '{atualizar_endereco,sugerir_opcoes}', 'Catálogo de serviços — DEMO', 14),
('DESISTENCIA', 1, 'Desistência', 'Saída da fila ou desistência de vaga.', 'Confirmação explícita do responsável.', '{}', 'Central de Vagas', 3, '{cancelar_fila}', 'Catálogo de serviços — DEMO', 15),
('ALTERACAO_RESPONSAVEL', 1, 'Alteração de responsável', 'Mudança de responsável legal — sempre com análise humana.', 'Documento de guarda quando aplicável.', '{GUARDA}', 'Secretaria Escolar', 10, '{analise_humana}', 'Catálogo de serviços — DEMO', 16);

-- ---------------------------------------------------------------------------
-- Base de conhecimento (conteúdo de demonstração; aprovação SEDUC pendente)
-- ---------------------------------------------------------------------------
insert into iara.knowledge_articles (tenant_id, service_code, title, body, keywords, audience, source, owner_sector, version, approved_at, valid_from, review_due, status) values
(1, 'SOLICITACAO_VAGA', 'Como solicitar uma vaga',
 'Você pode pedir vaga pelo portal, pelo WhatsApp da IARA ou presencialmente. Informamos a faixa da criança pela data de nascimento (data de corte 31/03), mostramos as unidades que atendem perto do seu endereço e registramos o protocolo. Se não houver vaga ofertável, a criança entra na fila com critérios transparentes.',
 '{vaga,creche,matricula,pedir,solicitar,cmei,escola}', 'PUBLICO', 'Conteúdo de demonstração — aprovação SEDUC pendente', 'Central de Vagas', '1.0', date '2026-09-01', date '2026-01-01', date '2026-12-31', 'PUBLICADO'),
(1, 'MATRICULA', 'Documentos para a matrícula',
 'Na configuração de demonstração: certidão de nascimento, CPF da criança e do responsável, comprovante de endereço, cartão SUS e carteira de vacinação. A lista oficial deve ser confirmada pela SEDUC.',
 '{documento,documentos,certidao,comprovante,vacina,sus,matricula}', 'PUBLICO', 'Conteúdo de demonstração — aprovação SEDUC pendente', 'Secretaria Escolar', '1.0', date '2026-09-01', date '2026-01-01', date '2026-12-31', 'PUBLICADO'),
(1, 'SOLICITACAO_VAGA', 'Como funciona a fila de espera',
 'A posição é calculada por regras públicas e versionadas: território (até 2 km), irmão na unidade, CadÚnico, deficiência/TEA e encaminhamento da rede de proteção. Em caso de empate, vale a data da solicitação. Você vê seus critérios aplicados, nunca dados de outras crianças.',
 '{fila,posicao,criterio,criterios,espera,prioridade}', 'PUBLICO', 'Conteúdo de demonstração — aprovação SEDUC pendente', 'Central de Vagas', '1.0', date '2026-09-01', date '2026-01-01', date '2026-12-31', 'PUBLICADO'),
(1, 'SOLICITACAO_VAGA', 'Recebi uma oferta de vaga. E agora?',
 'A oferta informa unidade, turma, turno e prazo de resposta (48 horas na configuração de demonstração). Aceitar a oferta não é a matrícula: depois do aceite, a unidade confere os documentos e confirma a matrícula. Se recusar, a criança volta para a fila conforme a regra vigente.',
 '{oferta,aceitar,recusar,prazo,resposta}', 'PUBLICO', 'Conteúdo de demonstração — aprovação SEDUC pendente', 'Central de Vagas', '1.0', date '2026-09-01', date '2026-01-01', date '2026-12-31', 'PUBLICADO'),
(1, 'TRANSFERENCIA', 'Transferência entre unidades',
 'Para quem já estuda na rede e precisa mudar de unidade (mudança de endereço, turno, irmão). O pedido é analisado pela Central de Vagas e não substitui a matrícula atual até a confirmação da nova vaga.',
 '{transferencia,mudar,trocar,unidade,escola}', 'PUBLICO', 'Conteúdo de demonstração — aprovação SEDUC pendente', 'Central de Vagas', '1.0', date '2026-09-01', date '2026-01-01', date '2026-12-31', 'PUBLICADO'),
(1, 'TRANSPORTE', 'Transporte escolar',
 'O transporte segue critérios de elegibilidade do município (distância e situação do aluno). A IARA registra o pedido e encaminha à Gerência de Transporte Escolar.',
 '{transporte,onibus,van,rota}', 'PUBLICO', 'Conteúdo de demonstração — aprovação SEDUC pendente', 'Gerência de Transporte Escolar', '1.0', date '2026-09-01', date '2026-01-01', date '2026-12-31', 'PUBLICADO'),
(1, 'AEE', 'Inclusão e AEE',
 'Crianças com deficiência ou TEA têm prioridade nos critérios da fila e podem precisar de atendimento educacional especializado. Laudos e documentos sensíveis são enviados por fluxo seguro e têm acesso restrito.',
 '{aee,inclusao,deficiencia,tea,autismo,laudo}', 'PUBLICO', 'Conteúdo de demonstração — aprovação SEDUC pendente', 'Gerência de Apoio Pedagógico Interdisciplinar', '1.0', date '2026-09-01', date '2026-01-01', date '2026-12-31', 'PUBLICADO'),
(1, 'DUVIDA', 'Etapas atendidas pela rede municipal',
 'A rede municipal de Maringá atende Educação Infantil (creche e pré-escola nos CMEIs e algumas escolas), Ensino Fundamental — anos iniciais (1º ao 5º ano) e EJA em escolas selecionadas. Os anos finais do Ensino Fundamental são ofertados pela rede estadual.',
 '{etapas,creche,pre,fundamental,eja,anos}', 'PUBLICO', 'Base IARA Educa (Censo Escolar 2025 / SEED-PR) — revisar com a SEDUC', 'Diretoria de Ensino', '1.0', date '2026-09-01', date '2026-01-01', date '2026-12-31', 'PUBLICADO'),
(1, 'DUVIDA', 'Calendário e prazos',
 'Datas de matrícula, rematrícula e calendário letivo devem ser consultadas nos comunicados oficiais da SEDUC. A IARA não informa prazos sem fonte oficial vigente.',
 '{calendario,prazo,data,quando,rematricula}', 'PUBLICO', 'Conteúdo de demonstração — aprovação SEDUC pendente', 'Diretoria de Ensino', '1.0', date '2026-09-01', date '2026-01-01', date '2026-12-31', 'PUBLICADO'),
(1, 'INTEGRAL', 'Educação integral',
 'O pedido de passagem do período parcial para o integral entra em fila própria (categoria "parcial para integral") e não conta como criança sem atendimento.',
 '{integral,periodo,parcial}', 'PUBLICO', 'Conteúdo de demonstração — aprovação SEDUC pendente', 'Gerência de Educação Integral', '1.0', date '2026-09-01', date '2026-01-01', date '2026-12-31', 'PUBLICADO'),
(1, 'RECURSO', 'Recurso sobre a posição na fila (rascunho)',
 'Texto em revisão pelo setor responsável.', '{recurso,contestar}', 'PUBLICO', 'Conteúdo de demonstração — em revisão', 'Diretoria de Gestão Educacional', '0.3', null, date '2026-01-01', date '2026-10-31', 'REVISAO');

insert into iara.feature_flags (code, tenant_id, enabled, description) values
('DEMO_MODE', 1, true, 'Modo demonstração: dados pessoais fictícios, perfis selecionáveis e mensagens simuladas.'),
('AI_ASSISTANT', 1, false, 'Modelo de linguagem para conversa livre (desligado: IARA usa roteiro determinístico).'),
('WHATSAPP', 1, true, 'Canal WhatsApp — no demo, apenas simulador (nenhuma mensagem real é enviada).'),
('LIVE_VACANCIES', 1, true, 'Vagas operacionais por turma (no demo: camada fictícia calibrada; integração SEDUC pendente).'),
('PUBLIC_QUEUE_POSITION', 1, true, 'Responsável vê a posição e os critérios aplicados da própria criança.'),
('TRANSPORT_MODULE', 1, false, 'Módulo de transporte escolar (rotas/veículos) — fase futura.'),
('MERENDA_MODULE', 1, false, 'Módulo de merenda escolar — fase futura.'),
('PREDICTIVE_ANALYTICS', 1, true, 'Projeções rotuladas como "Projetado/Cenário", nunca misturadas a fatos.');

insert into iara.demo_metrics (key, tenant_id, label, value, source, note) values
('availableVacancies', 1, 'Vagas disponíveis', 2348, 'DEMO / validar com SEDUC', 'Valor de composição visual do protótipo; a camada operacional demo foi calibrada para partir deste total.'),
('waitingList', 1, 'Fila de espera', 1276, 'DEMO / validar com SEDUC', 'Valor de composição visual do protótipo; a fila demo foi calibrada para partir deste total.'),
('openProtocols', 1, 'Protocolos abertos', 802, 'DEMO / validar com SEDUC', 'Valor de composição visual do protótipo; os protocolos demo foram calibrados para partir deste total.');

commit;
