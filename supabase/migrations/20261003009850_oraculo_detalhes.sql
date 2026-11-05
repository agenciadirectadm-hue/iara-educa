-- IARA Educa — 098.5 · Oráculo que explica: detalhes por motivo, tipo e situação; números por período; cardápio; calendário.
-- O Oráculo respondia só com contagens soltas. Agora "me fale mais", "quais os motivos", "faltaram ontem" e "cardápio de hoje" têm
-- resposta própria, nas regras, na página e no MCP.
-- oraculo_detalhes: cada linha é uma consulta agregada (nome, valor) escrita aqui na migração; nada vindo de fora vira SQL.
--   Parâmetros: $1 = unidades do recorte, $2 = é a cidade inteira, $3 = hoje.
-- oraculo_fatos: um número num período. Parâmetros: $1 = unidades, $2 = de, $3 = até, $4 = é a cidade inteira.
-- Sigilo: em detalhe de pessoas, item de 1 ou 2 entra em "Outros (menos de 3 cada)", sem o nome da categoria e sem percentual; o total
-- some se esse resto for de 1 ou 2. Texto digitado por funcionário ou família só aparece agregado de 3 para cima (o que torna um relato
-- único invisível), e o motivo de encaminhamento nunca sai de texto livre: é classificado por tipo e fundamento.
-- Valores de referência da OMS não são digitados aqui (decisão da 067): sem a tabela importada, o Oráculo diz o que falta.
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

-- 1. Código → português --------------------------------------------------------------------------------------------------------
create or replace function iara.oraculo_rotulo(p text) returns text
language sql immutable as $$
  select case when p is null then 'Não informado' else coalesce(
    '{"SAUDE":"Saúde","CONSULTA":"Consulta médica","DIFICULDADE_FAMILIAR":"Dificuldade familiar","RECUSA":"Recusa da família","ESTA_NA_ESCOLA":"Diz que estava na escola",
      "SEM_RESPOSTA":"Família ainda não respondeu","OUTRO":"Outro","OUTROS":"Outros","TRANSPORTE":"Transporte",
      "AGUARDANDO_APROVACAO":"Aguardando aprovação","APROVADO":"Aprovado, a enviar","ENVIADO":"Enviado, sem retorno","RECEBIDO":"Recebido pelo órgão","CANCELADO":"Cancelado",
      "MOTIVO_INFORMADO":"Motivo informado","AGUARDANDO_ESCLARECIMENTO":"Aguardando esclarecimento","JUSTIFICATIVA_ACEITA":"Justificativa aceita",
      "JUSTIFICATIVA_EM_ANALISE":"Justificativa em análise","INJUSTIFICADA":"Injustificada","AFASTAMENTO":"Afastamento",
      "FREQUENCIA_BAIXA":"Frequência baixa","AUSENCIA_CONSECUTIVA":"Faltas seguidas",
      "PERSISTENCIA":"Faltas persistentes","CONTATOS_SEM_SUCESSO":"Contatos sem sucesso","RISCO":"Risco identificado","RETORNOU":"Voltou às aulas",
      "EM_ACOMPANHAMENTO":"Em acompanhamento","ABERTO":"Aberto","ABERTA":"Aberta","ENCERRADA":"Encerrada","ENCERRADO":"Encerrado",
      "EF":"Ensino fundamental","PRE":"Pré-escola","CRECHE":"Creche",
      "BULLYING":"Bullying","CYBERBULLYING":"Cyberbullying","PSICOLOGICA":"Psicológica","FISICA":"Física","DISCRIMINACAO":"Discriminação","SEXUAL":"Sexual",
      "ACIDENTE":"Acidente","PERTENCES":"Pertences","CONFLITO":"Conflito","COMPORTAMENTO":"Comportamento","ELOGIO":"Elogio","PEDAGOGICA":"Pedagógica","ATRASO_SAIDA":"Atraso na saída",
      "LEVE":"Leve","MODERADA":"Moderada","GRAVE":"Grave","ESCOLA":"Escola","FAMILIA":"Família","CMEI":"CMEI",
      "SEM_ATENDIMENTO":"Sem atendimento hoje","AGUARDA_TRANSFERENCIA":"Aguarda transferência","PARCIAL_PARA_INTEGRAL":"Quer passar do parcial ao integral",
      "UNIDADE_PREFERENCIAL":"Quer a unidade preferida","RECUSOU_OFERTA":"Recusou uma oferta","DEMANDA_FUTURA":"Demanda futura",
      "TERRITORIO":"Mora no território da unidade","CADUNICO":"Família no CadÚnico","MAE_SOLO":"Mãe solo","IRMAO_NA_UNIDADE":"Irmão na unidade","PCD_TEA_AEE":"Deficiência, TEA ou AEE","VULNERABILIDADE":"Vulnerabilidade",
      "SEM_PREFERENCIA":"Sem preferência","MANHA":"Manhã","TARDE":"Tarde","NOITE":"Noite","INTEGRAL":"Integral",
      "ENROLLED":"Matriculou","ACCEPTED":"Aceitou","DECLINED":"Recusou","EXPIRED":"Venceu sem resposta","OFFERED":"Aguardando resposta",
      "CONFIRMADA":"Confirmada","PENDENTE":"Pendente","CONCLUINTE":"Concluinte","AGUARDANDO_RESULTADO":"Aguardando resultado","NAO_RENOVADA":"Não renovada","OUTRA_ESCOLA":"Quer outra escola",
      "PERTO_DO_TRABALHO":"Perto do trabalho","MUDANCA_ENDERECO":"Mudança de endereço","IRMAOS":"Irmãos na escola","FILA":"Na fila","AGUARDANDO_DESTINO":"Aguardando a escola de destino","RECUSADA":"Recusada",
      "ATIVO":"Ativo","LICENCA":"Licença","AFASTADO":"Afastado","ESQUECIMENTO":"Esquecimento","ATESTADO":"Atestado","ABONADA":"Abonada",
      "ATRASO":"Atraso","SUBSTITUICAO":"Substituição","ROTA_NAO_EXECUTADA":"Rota não executada","DISTANCIA":"Distância","ZONA_RURAL":"Zona rural","DEFICIENCIA":"Deficiência",
      "VAN":"Van","MICRO":"Micro-ônibus","ONIBUS":"Ônibus",
      "ELETRICA":"Elétrica","HIDRAULICA":"Hidráulica","PLAYGROUND":"Parquinho","CLIMATIZACAO":"Climatização","MARCENARIA":"Marcenaria","SERRALHERIA":"Serralheria","JARDINAGEM":"Jardinagem",
      "INFORMATICA":"Informática","ACESSIBILIDADE":"Acessibilidade","TELHADO":"Telhado","PINTURA":"Pintura",
      "URGENTE":"Urgente","ALTA":"Alta","MEDIA":"Média","BAIXA":"Baixa","NORMAL":"Normal",
      "TRIAGEM":"Triagem","VISTORIA":"Vistoria","ORCAMENTO":"Orçamento","AGUARDANDO_EXECUCAO":"Aguardando execução","EM_EXECUCAO":"Em execução","CONCLUIDO":"Concluído","VALIDADO":"Validado",
      "ALIMENTO":"Alimentos","PEDAGOGICO":"Pedagógico","LIMPEZA":"Limpeza","EQUIPAMENTO":"Equipamentos","ESCRITORIO":"Escritório","UNIFORME":"Uniforme","MOBILIARIO":"Mobiliário",
      "RECEBIDO_PARCIAL":"Recebido em parte","EM_TRANSPORTE":"Em transporte","RECUSADO":"Recusado",
      "DESJEJUM":"Desjejum","ALMOCO":"Almoço","LANCHE":"Lanche","JANTAR":"Jantar",
      "NOTAS":"Notas","FREQUENCIA":"Frequência","ALFABETIZACAO":"Alfabetização","PROGRESSAO":"Progressão","APROVADO_CONSELHO":"Aprovado em conselho",
      "PRE_SILABICO":"Pré-silábico","SILABICO_SEM_VALOR":"Silábico sem valor sonoro","SILABICO_COM_VALOR":"Silábico com valor sonoro","SILABICO_ALFABETICO":"Silábico-alfabético","ALFABETICO":"Alfabético",
      "DIAGNOSTICA":"Sondagem diagnóstica","B1":"1º bimestre","B2":"2º bimestre","B3":"3º bimestre","B4":"4º bimestre",
      "EM_ELABORACAO":"Em elaboração","EM_REVISAO":"Em revisão","SRM_PROPRIA":"Sala de recursos na própria unidade","SRM_POLO":"Sala de recursos polo","ITINERANTE":"Itinerante",
      "LITERATURA_INFANTIL":"Literatura infantil","INFANTOJUVENIL":"Infantojuvenil","CONTOS_FABULAS":"Contos e fábulas","INFORMATIVO":"Informativo","POESIA":"Poesia",
      "PNLD":"PNLD","DOACAO":"Doação","COMPRA":"Compra",
      "SOLICITACAO_VAGA":"Solicitação de vaga","TRANSFERENCIA":"Transferência","DUVIDA":"Dúvida","DOCUMENTO":"Documento","ATUALIZACAO_CADASTRAL":"Atualização cadastral","ALIMENTACAO":"Alimentação",
      "TROCA_TURNO":"Troca de turno","AEE":"AEE","RECLAMACAO":"Reclamação","MATRICULA":"Matrícula",
      "WEB":"Site","WHATSAPP":"WhatsApp","PRESENCIAL":"Presencial","TELEFONE":"Telefone","EMAIL":"E-mail",
      "NOVO":"Novo","EM_ANALISE":"Em análise","AGUARDANDO_DOCUMENTOS":"Aguardando documentos","AGUARDANDO_FAMILIA":"Aguardando a família","VAGA_OFERTADA":"Vaga ofertada","VAGA_ENCONTRADA":"Vaga encontrada","RECURSO":"Recurso",
      "IMPRESSORA":"Impressora","REDE_INTERNET":"Rede e internet","DADOS_CADASTRO":"Dados de cadastro","SISTEMA_IARA":"Sistema IARA","ACESSO_SENHA":"Acesso e senha","MELHORIA":"Melhoria","RESOLVIDO":"Resolvido","EM_ATENDIMENTO":"Em atendimento",
      "AVISO":"Aviso","EVENTO":"Evento","CAMPANHA":"Campanha","COMUNICADO":"Comunicado","MOSTRA":"Mostra","FEIRA":"Feira","FORMACAO":"Formação",
      "CERTIDAO":"Certidão","COMPROVANTE_ENDERECO":"Comprovante de endereço","CARTAO_SUS":"Cartão SUS","VACINACAO":"Vacinação","CPF":"CPF","LAUDO":"Laudo",
      "BRANCA":"Branca","PARDA":"Parda","PRETA":"Preta","AMARELA":"Amarela","INDIGENA":"Indígena","NAO_DECLARADA":"Não declarada"}'::jsonb ->> p,
    upper(left(p, 1)) || lower(replace(substr(p, 2), '_', ' '))) end
$$;

-- 2. Catálogos -------------------------------------------------------------------------------------------------------------------
create table if not exists iara.oraculo_assuntos (
  assunto text primary key,
  tema text not null,            -- tópico devolvido: um tema do catálogo ou um dos assuntos antigos (fila, frequencia...)
  rotulo text not null,
  palavras text not null,        -- palavras da pergunta que levam ao assunto (regex sobre o texto normalizado)
  indicadores text[] not null default '{}',  -- números do aprofundamento; vazio = todos os do tema
  ranking text,                  -- indicador de "onde mais pesa"
  ordem smallint not null default 0
);
create table if not exists iara.oraculo_detalhes (
  chave text primary key,
  assunto text not null references iara.oraculo_assuntos(assunto) on delete cascade,
  rotulo text not null,
  pede text,                     -- palavras que pedem este detalhe específico
  consulta text not null,
  pessoas boolean not null default false,
  mostra_pct boolean not null default true,
  ordem_fixa boolean not null default false,
  casas smallint not null default 0,
  sufixo text,
  ordem smallint not null default 0
);
create table if not exists iara.oraculo_fatos (
  chave text primary key,
  rotulo text not null,
  palavras text not null,
  consulta text not null,
  ultima text,                   -- último dia com registro; se existe, período vazio não é zero: é "ainda sem registro"
  pessoas boolean not null default false,
  casas smallint not null default 0,
  sufixo text,
  ordem smallint not null default 0
);
alter table iara.oraculo_assuntos enable row level security;
alter table iara.oraculo_detalhes enable row level security;
alter table iara.oraculo_fatos enable row level security;
alter table iara.oraculo_indicadores add column if not exists sem_dado text;

delete from iara.oraculo_assuntos;
insert into iara.oraculo_assuntos (assunto, tema, rotulo, palavras, indicadores, ranking, ordem) values
  ('encaminhamentos', 'protecao', 'Encaminhamentos ao Conselho Tutelar e à rede de apoio', '\mencaminh|\mconselho tutelar\M|\mrede de apoio\M', '{prot.ct_aguardando,prot.ct_sem_retorno,prot.rede_apoio}', 'prot.ct_aguardando', 1),
  ('busca_ativa', 'busca_ativa', 'Busca ativa', '\mbusca ativa\M|\mevasao\M|\mabandono\M', '{}', 'base.busca', 2),
  ('ocorrencias', 'ocorrencias', 'Ocorrências', '\mocorrenc|\mviolenc|\mbrigas?\M|\mconflitos?\M', '{}', 'base.ocorrencias', 3),
  ('faltas', 'frequencia', 'Faltas e frequência', '\mfaltas?\M|\mfaltaram\M|\mausenc|\mfrequenc|\mpresenc|\m(criancas|alunos)( estao)? faltando\M|\mfaltam (as aulas|a aula|na escola)\M', '{}', 'base.presenca', 4),
  ('fila', 'fila', 'Fila de espera', '\mfila\M|\mfilas\M|\mespera\M|\mesperam\M|\mesperando\M|\maguardando vaga\M', '{}', 'base.fila', 5),
  ('ofertas', 'ofertas', 'Ofertas de vaga', '\mofertas?\M', '{}', null, 6),
  ('vagas', 'vagas', 'Vagas', '\mvagas?\M', '{}', 'base.vagas', 7),
  ('rematricula', 'rematricula', 'Rematrícula', '\mrematricul|\mrenov', '{}', 'remat.pendentes', 8),
  ('transferencias', 'rematricula', 'Transferências', '\mtransferenc', '{remat.transferencias}', null, 9),
  ('aee', 'aee', 'Educação especial (AEE)', '\maee\M|\meducacao especial\M|\mdeficienc|\minclus|\matendimento especializado\M|\macessibilidade\M', '{}', 'aee.ativos', 10),
  ('ponto', 'ponto', 'Ponto dos profissionais', '\mponto\M|\mjornada\M|\matestados?\M', '{}', null, 11),
  ('profissionais', 'profissionais', 'Profissionais da rede', '\mprofessor|\mprofissiona|\mservidor|\meducador|\mdocentes?\M|\mfuncionari|\mauxiliar', '{}', 'base.profissionais', 12),
  ('transporte', 'transporte', 'Transporte escolar', '\mtransporte\M|\monibus\M|\mvans?\M|\mmotorista|\mrotas?\M|\mviagens?\M', '{}', 'base.transportados', 13),
  ('suporte', 'qualidade', 'Suporte técnico', '\msuporte\M|\mimpressora|\mchamados? tecnico', '{qual.suporte}', null, 14),
  ('manutencao', 'manutencao', 'Manutenção das unidades', '\mmanutenc|\mchamados?\M|\mreparos?\M|\mconsertos?\M|\mreformas?\M', '{}', 'man.abertos', 15),
  ('almoxarifado', 'almoxarifado', 'Almoxarifado e estoque', '\malmoxarif|\mestoque|\mmateria(l|is)\M|\mpedidos?\M', '{}', 'alm.abaixo', 16),
  ('merenda', 'nutricao', 'Merenda e nutrição', '\mmerenda|\mrefeic|\malimentac|\mnutric|\malergi|\mrestric', '{}', null, 17),
  ('desempenho', 'desempenho', 'Desempenho escolar', '\mnotas?\M|\mdesempenho\M|\mmedias?\M|\maprendizagem\M|\maprovac|\mreprovac|\mplanos? de intervencao\M', '{}', 'des.media', 18),
  ('alfabetizacao', 'alfabetizacao', 'Alfabetização', '\malfabetiz|\mleitura\M|\mescrita\M|\msondagem|\mler e escrever\M', '{}', null, 19),
  ('biblioteca', 'biblioteca', 'Bibliotecas', '\mbibliotec|\mlivros?\M|\memprestim', '{}', null, 20),
  ('atendimento', 'atendimento', 'Atendimento às famílias', '\mprotocolos?\M|\matendimentos?\M|\mdemandas?\M|\mreclamac', '{}', 'atend.abertos', 21),
  ('comunicacao', 'comunicacao', 'Comunicação e eventos', '\mmural\M|\mcomunicad|\meventos?\M', '{}', null, 22),
  ('documentos', 'cadastros', 'Documentos dos alunos', '\mdocumentos?\M|\mdocumentacao\M', '{}', null, 23),
  ('matriculas', 'matriculas', 'Matrículas e perfil dos alunos', '\mmatricul|\malun[oa]s?\M|\mestudantes?\M|\mcriancas?\M|\mmeninos?\M|\mmeninas?\M', '{}', 'base.matriculas', 24);

-- 3. Detalhes -------------------------------------------------------------------------------------------------------------------
with dims(d, rx) as (values
  ('motivo', '\mmotivos?\M|\mpor que\M|\mporque\M|\mrazo(es|ao)\M|\mcausas?\M'),
  ('situacao', '\mpor situac|\msituacoes\M|\mstatus\M|\mandamento\M|\mem que (situacao|etapa|fase)\M|\metapas? do'),
  ('tipo', '\mtipos?\M|\mcategorias?\M|\mnatureza\M|\mquais problemas\M'),
  ('gravidade', '\mgravidade\M|\mpor gravidade\M'),
  ('mes', '\mmes a mes\M|\mevoluc|\mtendencia\M|\mpor mes\M|\mao longo\M|\maumentou\M|\mdiminuiu\M|\mhistorico\M|\mcresceu\M|\mcaiu\M'),
  ('tempo', '\mha quanto\M|\mquanto tempo\M|\mdemora|\mtempo de espera\M'),
  ('horas', '\mhoras\M|\mquantas faltas tinham\M'),
  ('etapa', '\mpor etapa|\metapas\M|\mpor serie\M|\mseries\M|\mpor ano\M'),
  ('turno', '\mpor turno|\mturnos\M'),
  ('canal', '\mcanais\M|\mpor canal\M|\mpor onde\M'),
  ('prioridade', '\mpor prioridade\M|\mprioridades\M|\mcriterios?\M'),
  ('origem', '\morigem\M|\mquem registrou\M|\mquem abriu\M|\mde onde\M'),
  ('cargo', '\mcargos?\M|\mpor funcao\M|\mfuncoes\M'),
  ('vinculo', '\mvinculos?\M|\mefetivos?\M|\mtemporarios?\M|\mpss\M|\mconcursados?\M'),
  ('escolaridade', '\mescolaridade\M|\mformacao\M|\mmestrado\M|\mespecializacao\M'),
  ('area', '\marea de atuacao\M|\mareas\M'),
  ('sexo', '\msexo\M|\mmeninos?\M|\mmeninas?\M|\mgenero\M'),
  ('idade', '\midades?\M|\mfaixa etaria\M|\manos de idade\M'),
  ('raca', '\mraca\M|\mcor\M|\metnia\M|\mnegr[oa]s?\M|\mpard[oa]s?\M|\mindigenas?\M'),
  ('componente', '\mcomponentes?\M|\mdisciplinas?\M|\mmaterias?\M|\mportugues\M|\mmatematica\M'),
  ('bimestre', '\mbimestres?\M'),
  ('resultado', '\mresultados?\M|\maprovac|\mreprovac|\maprovad|\mreprovad|\mprogressao\M'),
  ('nivel', '\mniveis\M|\mnivel\M|\mhipotes'),
  ('violencia', '\mtipos? de violencia\M|\mviolencias?\M'),
  ('titulos', '\mtitulos?\M|\mmais emprestad|\mmais lid|\mlivros mais\M'),
  ('genero', '\mgeneros?\M'),
  ('itens', '\mitens\M|\mquais materiais\M|\mquais produtos\M|\mo que falta\M|\mo que esta faltando\M'),
  ('refeicao', '\mpor refeicao\M|\mdesjejum\M|\malmoco\M|\mlanche\M|\mjantar\M'),
  ('restricao', '\mrestric|\malergi|\mintoleranc'),
  ('modalidade', '\mmodalidades?\M'),
  ('necessidade', '\mnecessidades?\M|\mcadeirante|\mbaixa visao\M|\mauditiv')
)
insert into iara.oraculo_detalhes (chave, assunto, rotulo, pede, consulta, pessoas, mostra_pct, ordem_fixa, casas, sufixo, ordem)
select v.chave, v.assunto, v.rotulo, (select string_agg(dims.rx, '|') from dims where dims.d = any (string_to_array(v.dim, ','))),
       v.consulta, v.pessoas, v.pct, v.fixa, v.casas, v.sufixo, v.ordem
from (values
-- encaminhamentos: motivo classificado por tipo e fundamento; "servico" e "necessidade" são digitáveis e nunca aparecem como texto
('enc.motivo', 'encaminhamentos', 'Por motivo', 'motivo', $q$select case when tipo = 'REDE_APOIO' then 'Apoio social (CRAS e rede de apoio)' when fundamento ilike '%LDB%' then 'Excesso de faltas (mais de 30% do limite da lei)' when fundamento ilike '%viol%ncia%' then 'Suspeita de violência contra a criança' else 'Outros motivos' end, count(*) from iara.encaminhamentos where situacao <> 'CANCELADO' and unit_id = any ($1) group by 1$q$, true, true, false, 0, null::text, 1),
('enc.faltas', 'encaminhamentos', 'Motivo das faltas de quem foi encaminhado', 'motivo', $q$select iara.oraculo_rotulo(coalesce(a.motivo, 'SEM_RESPOSTA')), count(*) from iara.frequencia_ausencias a where a.unit_id = any ($1) and a.student_id in (select e.student_id from iara.encaminhamentos e where e.tipo = 'CONSELHO_TUTELAR' and e.unit_id = any ($1)) group by 1$q$, true, true, false, 0, null, 2),
('enc.situacao', 'encaminhamentos', 'Em que situação estão', 'situacao', $q$select iara.oraculo_rotulo(situacao), count(*) from iara.encaminhamentos where situacao <> 'CANCELADO' and unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 3),
('enc.espera', 'encaminhamentos', 'Há quanto tempo aguardam aprovação', 'tempo', $q$select case when d <= 7 then 'Até 7 dias' when d <= 30 then 'De 8 a 30 dias' when d <= 60 then 'De 31 a 60 dias' else 'Mais de 60 dias' end, count(*) from (select $3 - created_at::date d from iara.encaminhamentos where situacao = 'AGUARDANDO_APROVACAO' and unit_id = any ($1)) q group by 1 order by min(d)$q$, true, true, true, 0, null, 4),
('enc.horas', 'encaminhamentos', 'Horas de falta de quem foi notificado', 'horas', $q$select case when h < 80 then 'Até 79 horas' when h < 100 then 'De 80 a 99 horas' when h < 120 then 'De 100 a 119 horas' else '120 horas ou mais' end, count(*) from (select substring(necessidade from 'Ausências: ([0-9]+) h')::int h from iara.encaminhamentos where tipo = 'CONSELHO_TUTELAR' and unit_id = any ($1)) q where h is not null group by 1 order by min(h)$q$, true, true, true, 0, null, 5),
('enc.mes', 'encaminhamentos', 'Criados por mês', 'mes', $q$select to_char(m, 'MM/YYYY'), n from (select date_trunc('month', created_at) m, count(*) n from iara.encaminhamentos where unit_id = any ($1) and created_at >= date_trunc('month', $3::timestamp) - interval '5 months' group by 1 order by 1) q$q$, true, false, true, 0, null, 6),
-- busca ativa
('ba.origem', 'busca_ativa', 'Por que o caso foi aberto', 'motivo,origem', $q$select iara.oraculo_rotulo(origem), count(*) from iara.busca_ativa_casos where unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 1),
('ba.situacao', 'busca_ativa', 'Em que situação estão', 'situacao', $q$select iara.oraculo_rotulo(situacao), count(*) from iara.busca_ativa_casos where unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 2),
('ba.etapa', 'busca_ativa', 'Por etapa', 'etapa', $q$select iara.oraculo_rotulo(etapa), count(*) from iara.busca_ativa_casos where unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 3),
-- ocorrências (sigilosas só na cidade)
('oc.tipo', 'ocorrencias', 'Por tipo (90 dias, sem elogios)', 'tipo,motivo', $q$select iara.oraculo_rotulo(tipo), count(*) from iara.ocorrencias where ocorrida_em >= now() - interval '90 days' and tipo <> 'ELOGIO' and unit_id = any ($1) and ($2 or not coalesce(sigilosa, false)) group by 1$q$, false, true, false, 0, null, 1),
('oc.gravidade', 'ocorrencias', 'Por gravidade (90 dias)', 'gravidade', $q$select iara.oraculo_rotulo(gravidade), count(*) from iara.ocorrencias where ocorrida_em >= now() - interval '90 days' and tipo <> 'ELOGIO' and unit_id = any ($1) and ($2 or not coalesce(sigilosa, false)) group by gravidade order by array_position(array['GRAVE', 'MODERADA', 'LEVE'], gravidade)$q$, false, true, true, 0, null, 2),
('oc.situacao', 'ocorrencias', 'Em que situação estão (90 dias)', 'situacao', $q$select iara.oraculo_rotulo(situacao), count(*) from iara.ocorrencias where ocorrida_em >= now() - interval '90 days' and tipo <> 'ELOGIO' and unit_id = any ($1) and ($2 or not coalesce(sigilosa, false)) group by 1$q$, false, true, false, 0, null, 3),
('oc.origem', 'ocorrencias', 'Quem registrou (90 dias)', 'origem', $q$select iara.oraculo_rotulo(origem), count(*) from iara.ocorrencias where ocorrida_em >= now() - interval '90 days' and tipo <> 'ELOGIO' and unit_id = any ($1) and ($2 or not coalesce(sigilosa, false)) group by 1$q$, false, true, false, 0, null, 4),
('oc.violencia', 'ocorrencias', 'Tipos de violência registrados (no ano)', 'violencia', $q$select iara.oraculo_rotulo(v), count(*) from iara.ocorrencias o cross join lateral unnest(o.violencia) v where o.ocorrida_em >= date_trunc('year', $3::timestamp) and o.unit_id = any ($1) and ($2 or not coalesce(o.sigilosa, false)) group by 1$q$, true, true, false, 0, null, 5),
('oc.mes', 'ocorrencias', 'Por mês', 'mes', $q$select to_char(m, 'MM/YYYY'), n from (select date_trunc('month', ocorrida_em) m, count(*) n from iara.ocorrencias where tipo <> 'ELOGIO' and unit_id = any ($1) and ($2 or not coalesce(sigilosa, false)) and ocorrida_em >= date_trunc('month', $3::timestamp) - interval '5 months' group by 1 order by 1) q$q$, false, false, true, 0, null, 6),
-- faltas
('fal.motivo', 'faltas', 'Motivo das ausências (90 dias)', 'motivo', $q$select iara.oraculo_rotulo(coalesce(motivo, 'SEM_RESPOSTA')), count(*) from iara.frequencia_ausencias where data >= $3 - 90 and unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 1),
('fal.situacao', 'faltas', 'Em que situação estão (90 dias)', 'situacao', $q$select iara.oraculo_rotulo(situacao), count(*) from iara.frequencia_ausencias where data >= $3 - 90 and unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 2),
('fal.etapa', 'faltas', 'Por etapa (90 dias)', 'etapa', $q$select iara.oraculo_rotulo(etapa), count(*) from iara.frequencia_ausencias where data >= $3 - 90 and unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 3),
('fal.alertas', 'faltas', 'Alertas de frequência em aberto', 'tipo', $q$select iara.oraculo_rotulo(tipo), count(*) from iara.frequencia_alertas where situacao <> 'RESOLVIDO' and unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 4),
('fal.mes', 'faltas', 'Ausências por mês', 'mes', $q$select to_char(m, 'MM/YYYY'), n from (select date_trunc('month', data) m, count(*) n from iara.frequencia_ausencias where unit_id = any ($1) and data >= (date_trunc('month', $3::timestamp) - interval '5 months')::date group by 1 order by 1) q$q$, true, false, true, 0, null, 5),
-- fila
('fila.etapa', 'fila', 'Por etapa', 'etapa', $q$select g.name, count(*) from iara.waiting_list_entries w join iara.grade_levels g on g.id = w.grade_level_id where w.status in ('WAITING', 'OFFERED') and w.preferred_unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 1),
('fila.categoria', 'fila', 'Situação de quem espera', 'tipo,motivo', $q$select iara.oraculo_rotulo(demand_category), count(*) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED') and preferred_unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 2),
('fila.tempo', 'fila', 'Há quanto tempo esperam', 'tempo', $q$select case when d <= 30 then 'Até 30 dias' when d <= 90 then 'De 31 a 90 dias' when d <= 180 then 'De 91 a 180 dias' else 'Mais de 180 dias' end, count(*) from (select $3 - entered_at::date d from iara.waiting_list_entries where status in ('WAITING', 'OFFERED') and preferred_unit_id = any ($1)) q group by 1 order by min(d)$q$, true, true, true, 0, null, 3),
('fila.prioridade', 'fila', 'Critérios de prioridade', 'prioridade', $q$select iara.oraculo_rotulo(f), count(*) from iara.waiting_list_entries w cross join lateral unnest(w.priority_flags) f where w.status in ('WAITING', 'OFFERED') and w.preferred_unit_id = any ($1) group by 1$q$, true, false, false, 0, null, 4),
('fila.turno', 'fila', 'Turno pedido', 'turno', $q$select iara.oraculo_rotulo(coalesce(preferred_shift, 'SEM_PREFERENCIA')), count(*) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED') and preferred_unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 5),
-- ofertas
('of.status', 'ofertas', 'O que aconteceu com as ofertas', 'situacao', $q$select iara.oraculo_rotulo(status), count(*) from iara.vacancy_offers where unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 1),
('of.recusa', 'ofertas', 'Por que recusaram', 'motivo', $q$select decline_reason, count(*) from iara.vacancy_offers where decline_reason is not null and unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 2),
-- vagas
('vag.etapa', 'vagas', 'Vagas por etapa', 'etapa', $q$select g.name, sum(c.offerable_vacancies_count) from iara.classes c join iara.grade_levels g on g.id = c.grade_level_id where c.status = 'ATIVA' and c.unit_id = any ($1) group by 1$q$, false, true, false, 0, null, 1),
('vag.turno', 'vagas', 'Vagas por turno', 'turno', $q$select iara.oraculo_rotulo(shift), sum(offerable_vacancies_count) from iara.classes where status = 'ATIVA' and unit_id = any ($1) group by 1$q$, false, true, false, 0, null, 2),
('vag.tipo', 'vagas', 'Vagas por tipo de unidade', 'tipo', $q$select u.unit_type_label, sum(c.offerable_vacancies_count) from iara.classes c join iara.education_units u on u.id = c.unit_id where c.status = 'ATIVA' and c.unit_id = any ($1) group by 1$q$, false, true, false, 0, null, 3),
-- rematrícula e transferências
('rem.situacao', 'rematricula', 'Em que situação estão', 'situacao', $q$select iara.oraculo_rotulo(situacao), count(*) from iara.rematriculas where unit_origem = any ($1) and ano = (select max(ano) from iara.rematriculas) group by 1$q$, true, true, false, 0, null, 1),
('rem.motivo', 'rematricula', 'Por que não renovaram', 'motivo', $q$select motivo, count(*) from iara.rematriculas where motivo is not null and unit_origem = any ($1) and ano = (select max(ano) from iara.rematriculas) group by 1$q$, true, true, false, 0, null, 2),
('tra.motivo', 'transferencias', 'Por motivo', 'motivo', $q$select iara.oraculo_rotulo(motivo_tipo), count(*) from iara.transferencias where unit_origem = any ($1) group by 1$q$, true, true, false, 0, null, 1),
('tra.situacao', 'transferencias', 'Em que situação estão', 'situacao', $q$select iara.oraculo_rotulo(situacao), count(*) from iara.transferencias where unit_origem = any ($1) group by 1$q$, true, true, false, 0, null, 2),
-- AEE
('aee.situacao', 'aee', 'Planos por situação', 'situacao', $q$select iara.oraculo_rotulo(situacao), count(*) from iara.aee_planos where unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 1),
('aee.modalidade', 'aee', 'Planos por modalidade', 'modalidade,tipo', $q$select iara.oraculo_rotulo(modalidade), count(*) from iara.aee_planos where unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 2),
('aee.necessidades', 'aee', 'Necessidades de acessibilidade', 'necessidade', $q$select s.accessibility_needs, count(distinct s.id) from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' where s.accessibility_needs is not null and e.unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 3),
-- ponto
('pon.tipo', 'ponto', 'Justificativas por tipo (30 dias)', 'tipo,motivo', $q$select iara.oraculo_rotulo(tipo), count(*) from iara.ponto_justificativas where data >= $3 - 30 and unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 1),
('pon.situacao', 'ponto', 'Justificativas por situação (30 dias)', 'situacao', $q$select iara.oraculo_rotulo(situacao), count(*) from iara.ponto_justificativas where data >= $3 - 30 and unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 2),
-- profissionais
('pro.cargo', 'profissionais', 'Por cargo', 'cargo', $q$select coalesce(cargo, 'Não informado'), count(*) from iara.staff where unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 1),
('pro.situacao', 'profissionais', 'Por situação', 'situacao', $q$select iara.oraculo_rotulo(situacao), count(*) from iara.staff where unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 2),
('pro.vinculo', 'profissionais', 'Por vínculo', 'vinculo', $q$select coalesce(bond, 'Não informado'), count(*) from iara.staff where unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 3),
('pro.escolaridade', 'profissionais', 'Por escolaridade', 'escolaridade', $q$select coalesce(escolaridade, 'Não informado'), count(*) from iara.staff where unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 4),
('pro.area', 'profissionais', 'Por área de atuação', 'area', $q$select coalesce(area_atuacao, 'Não informado'), count(*) from iara.staff where unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 5),
-- transporte
('tr.ocor', 'transporte', 'Ocorrências por tipo (90 dias)', 'tipo', $q$select iara.oraculo_rotulo(o.tipo), count(*) from iara.transporte_ocorrencias o join iara.transporte_rotas r on r.id = o.rota_id where o.data >= $3 - 90 and r.unit_id = any ($1) group by 1$q$, false, true, false, 0, null, 1),
('tr.motivo', 'transporte', 'Motivos de atraso ou de viagem perdida (30 dias)', 'motivo', $q$select v.motivo, count(*) from iara.transporte_viagens v join iara.transporte_rotas r on r.id = v.rota_id where v.data >= $3 - 30 and v.motivo is not null and r.unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 2),
('tr.alunos', 'transporte', 'Por que os alunos usam o transporte', 'necessidade', $q$select iara.oraculo_rotulo(a.motivo), count(*) from iara.transporte_alunos a join iara.transporte_rotas r on r.id = a.rota_id where a.encerrado_em is null and r.unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 3),
('tr.veiculos', 'transporte', 'Veículos por tipo', 'tipo', $q$select iara.oraculo_rotulo(tipo), count(*) from iara.transporte_veiculos where $2 or id in (select veiculo_id from iara.transporte_rotas where unit_id = any ($1)) group by 1$q$, false, true, false, 0, null, 4),
('tr.turno', 'transporte', 'Rotas por turno', 'turno', $q$select iara.oraculo_rotulo(turno), count(*) from iara.transporte_rotas where situacao = 'ATIVA' and unit_id = any ($1) group by 1$q$, false, true, false, 0, null, 5),
-- suporte
('sup.categoria', 'suporte', 'Chamados por categoria', 'tipo,motivo', $q$select iara.oraculo_rotulo(categoria), count(*) from iara.suporte_chamados where $2 or unit_id = any ($1) group by 1$q$, false, true, false, 0, null, 1),
('sup.situacao', 'suporte', 'Chamados por situação', 'situacao', $q$select iara.oraculo_rotulo(situacao), count(*) from iara.suporte_chamados where $2 or unit_id = any ($1) group by 1$q$, false, true, false, 0, null, 2),
-- manutenção
('man.categoria', 'manutencao', 'Chamados abertos por categoria', 'tipo,motivo', $q$select iara.oraculo_rotulo(categoria), count(*) from iara.manutencao_chamados where situacao not in ('VALIDADO', 'CONCLUIDO', 'CANCELADO') and unit_id = any ($1) group by 1$q$, false, true, false, 0, null, 1),
('man.prioridade', 'manutencao', 'Chamados abertos por prioridade', 'prioridade', $q$select iara.oraculo_rotulo(prioridade), count(*) from iara.manutencao_chamados where situacao not in ('VALIDADO', 'CONCLUIDO', 'CANCELADO') and unit_id = any ($1) group by prioridade order by array_position(array['URGENTE', 'ALTA', 'MEDIA', 'BAIXA'], prioridade)$q$, false, true, true, 0, null, 2),
('man.situacao', 'manutencao', 'Chamados abertos por etapa', 'situacao', $q$select iara.oraculo_rotulo(situacao), count(*) from iara.manutencao_chamados where situacao not in ('VALIDADO', 'CONCLUIDO', 'CANCELADO') and unit_id = any ($1) group by 1$q$, false, true, false, 0, null, 3),
('man.custo', 'manutencao', 'Custo no ano por categoria (R$)', null, $q$select iara.oraculo_rotulo(categoria), coalesce(sum(custo_final), 0) from iara.manutencao_chamados where extract(year from aberto_em) = extract(year from $3) and unit_id = any ($1) group by 1$q$, false, true, false, 0, null, 4),
-- almoxarifado
('alm.categoria', 'almoxarifado', 'Itens abaixo do mínimo por categoria', 'tipo', $q$select iara.oraculo_rotulo(categoria), count(*) from iara.materiais where ativo and quantidade < minimo and unit_id = any ($1) group by 1$q$, false, true, false, 0, null, 1),
('alm.itens', 'almoxarifado', 'Itens mais em falta', 'itens', $q$select nome, count(*) from iara.materiais where ativo and quantidade < minimo and unit_id = any ($1) group by 1$q$, false, false, false, 0, null, 2),
('alm.pedidos', 'almoxarifado', 'Pedidos por situação', 'situacao', $q$select iara.oraculo_rotulo(situacao), count(*) from iara.pedidos where unit_id = any ($1) group by 1$q$, false, true, false, 0, null, 3),
-- merenda
('mer.refeicao', 'merenda', 'Refeições servidas nos últimos 7 dias', 'refeicao', $q$select iara.oraculo_rotulo(refeicao), sum(quantidade) from iara.refeicoes_servidas where data >= $3 - 6 and unit_id = any ($1) group by 1$q$, false, true, false, 0, null, 1),
('mer.restricoes', 'merenda', 'Restrições alimentares validadas', 'restricao,tipo', $q$select ra.descricao, count(distinct ar.student_id) from iara.aluno_restricoes ar join iara.restricoes_alimentares ra on ra.codigo = ar.restricao_codigo join iara.enrollments e on e.student_id = ar.student_id and e.status = 'ACTIVE' where ar.situacao = 'VALIDADA' and e.unit_id = any ($1) group by 1$q$, true, false, false, 0, null, 2),
-- desempenho
('des.componente', 'desempenho', 'Média por componente no ano', 'componente', $q$select n.componente, round(avg(n.nota), 1) from iara.notas n join iara.classes c on c.id = n.class_id where n.ano = extract(year from $3)::int and c.unit_id = any ($1) group by 1$q$, false, false, false, 1, null, 1),
('des.bimestre', 'desempenho', 'Média por bimestre', 'bimestre', $q$select n.bimestre || 'º bimestre', round(avg(n.nota), 1) from iara.notas n join iara.classes c on c.id = n.class_id where n.ano = extract(year from $3)::int and c.unit_id = any ($1) group by n.bimestre order by n.bimestre$q$, false, false, true, 1, null, 2),
('des.resultado', 'desempenho', 'Resultado final do último ano fechado', 'resultado', $q$select iara.oraculo_rotulo(situacao), count(*) from iara.resultados_finais where unit_id = any ($1) and ano = (select max(ano) from iara.resultados_finais) group by 1$q$, true, true, false, 0, null, 3),
('des.planos', 'desempenho', 'Planos de intervenção ativos, por motivo', 'motivo', $q$select iara.oraculo_rotulo(m), count(*) from iara.planos_intervencao p cross join lateral unnest(p.motivos) m where p.situacao = 'ATIVO' and p.unit_id = any ($1) group by 1$q$, true, false, false, 0, null, 4),
-- alfabetização
('alf.nivel', 'alfabetizacao', 'Nível das crianças na última sondagem', 'nivel', $q$select iara.oraculo_rotulo(s.nivel), count(*) from iara.alfabetizacao_sondagens s join iara.classes c on c.id = s.class_id where s.ano = extract(year from $3)::int and c.unit_id = any ($1) and s.ciclo = (select x.ciclo from iara.alfabetizacao_sondagens x where x.ano = extract(year from $3)::int group by x.ciclo order by array_position(array['DIAGNOSTICA', 'B1', 'B2', 'B3', 'B4'], x.ciclo) desc nulls last limit 1) group by s.nivel order by array_position(array['PRE_SILABICO', 'SILABICO_SEM_VALOR', 'SILABICO_COM_VALOR', 'SILABICO_ALFABETICO', 'ALFABETICO'], s.nivel)$q$, true, true, true, 0, null, 1),
('alf.evolucao', 'alfabetizacao', 'Crianças no nível alfabético, a cada sondagem', 'mes', $q$select iara.oraculo_rotulo(s.ciclo), round(100.0 * count(*) filter (where s.nivel = 'ALFABETICO') / count(*), 1) from iara.alfabetizacao_sondagens s join iara.classes c on c.id = s.class_id where s.ano = extract(year from $3)::int and c.unit_id = any ($1) group by s.ciclo order by array_position(array['DIAGNOSTICA', 'B1', 'B2', 'B3', 'B4'], s.ciclo)$q$, false, false, true, 1, '%', 2),
-- biblioteca
('bib.titulos', 'biblioteca', 'Títulos mais emprestados (12 meses)', 'titulos', $q$select t.titulo, count(*) from iara.biblioteca_emprestimos e join iara.biblioteca_exemplares x on x.id = e.exemplar_id join iara.biblioteca_titulos t on t.id = x.titulo_id where e.unit_id = any ($1) and e.retirada_em >= now() - interval '1 year' group by 1$q$, false, false, false, 0, null, 1),
('bib.genero', 'biblioteca', 'Empréstimos por gênero (12 meses)', 'genero,tipo', $q$select iara.oraculo_rotulo(t.genero), count(*) from iara.biblioteca_emprestimos e join iara.biblioteca_exemplares x on x.id = e.exemplar_id join iara.biblioteca_titulos t on t.id = x.titulo_id where e.unit_id = any ($1) and e.retirada_em >= now() - interval '1 year' group by 1$q$, false, true, false, 0, null, 2),
('bib.acervo', 'biblioteca', 'Acervo por origem', 'origem', $q$select iara.oraculo_rotulo(origem), count(*) from iara.biblioteca_exemplares where unit_id = any ($1) group by 1$q$, false, true, false, 0, null, 3),
-- atendimento
('ate.tipo', 'atendimento', 'Protocolos por assunto (12 meses)', 'tipo,motivo', $q$select iara.oraculo_rotulo(case_type), count(*) from iara.service_cases where ($2 or unit_id = any ($1)) and opened_at >= now() - interval '1 year' group by 1$q$, false, true, false, 0, null, 1),
('ate.canal', 'atendimento', 'Por onde as famílias procuram (12 meses)', 'canal', $q$select iara.oraculo_rotulo(channel), count(*) from iara.service_cases where ($2 or unit_id = any ($1)) and opened_at >= now() - interval '1 year' group by 1$q$, false, true, false, 0, null, 2),
('ate.situacao', 'atendimento', 'Protocolos abertos por situação', 'situacao', $q$select iara.oraculo_rotulo(status), count(*) from iara.service_cases where status not in ('ENCERRADO', 'MATRICULA_CONCLUIDA') and ($2 or unit_id = any ($1)) group by 1$q$, false, true, false, 0, null, 3),
('ate.prioridade', 'atendimento', 'Protocolos abertos por prioridade', 'prioridade', $q$select iara.oraculo_rotulo(priority), count(*) from iara.service_cases where status not in ('ENCERRADO', 'MATRICULA_CONCLUIDA') and ($2 or unit_id = any ($1)) group by priority order by array_position(array['URGENTE', 'ALTA', 'NORMAL', 'BAIXA'], priority)$q$, false, true, true, 0, null, 4),
-- comunicação
('com.mural', 'comunicacao', 'Publicações do mural por tipo', 'tipo', $q$select iara.oraculo_rotulo(tipo), count(*) from iara.mural_publicacoes where situacao = 'PUBLICADO' and ($2 or unit_id = any ($1)) group by 1$q$, false, true, false, 0, null, 1),
('com.eventos', 'comunicacao', 'Eventos por tipo', 'tipo', $q$select iara.oraculo_rotulo(tipo), count(*) from iara.eventos where $2 or unit_id = any ($1) group by 1$q$, false, true, false, 0, null, 2),
-- documentos
('doc.situacao', 'documentos', 'Documentos por situação', 'situacao', $q$select iara.oraculo_rotulo(d.status), count(*) from iara.documents d join iara.enrollments e on e.student_id = d.student_id and e.status = 'ACTIVE' where e.unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 1),
('doc.pendentes', 'documentos', 'Documentos pendentes por tipo', 'tipo', $q$select iara.oraculo_rotulo(d.doc_type), count(*) from iara.documents d join iara.enrollments e on e.student_id = d.student_id and e.status = 'ACTIVE' where d.status = 'PENDENTE' and e.unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 2),
-- matrículas e perfil
('mat.etapa', 'matriculas', 'Alunos por etapa', 'etapa', $q$select g.name, sum(c.active_enrollments_count) from iara.classes c join iara.grade_levels g on g.id = c.grade_level_id where c.status = 'ATIVA' and c.unit_id = any ($1) group by 1$q$, false, true, false, 0, null, 1),
('mat.turno', 'matriculas', 'Alunos por turno', 'turno', $q$select iara.oraculo_rotulo(shift), sum(active_enrollments_count) from iara.classes where status = 'ATIVA' and unit_id = any ($1) group by 1$q$, false, true, false, 0, null, 2),
('mat.tipo', 'matriculas', 'Alunos por tipo de unidade', 'tipo', $q$select u.unit_type_label, sum(c.active_enrollments_count) from iara.classes c join iara.education_units u on u.id = c.unit_id where c.status = 'ATIVA' and c.unit_id = any ($1) group by 1$q$, false, true, false, 0, null, 3),
('mat.sexo', 'matriculas', 'Meninos e meninas', 'sexo', $q$select case s.gender when 'M' then 'Meninos' when 'F' then 'Meninas' else 'Não informado' end, count(distinct s.id) from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' where e.unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 4),
('mat.idade', 'matriculas', 'Alunos por idade', 'idade', $q$select case when i <= 3 then 'Até 3 anos' when i <= 5 then '4 e 5 anos' when i <= 10 then '6 a 10 anos' when i <= 14 then '11 a 14 anos' else '15 anos ou mais' end, count(*) from (select distinct s.id, extract(year from age($3, s.birth_date))::int i from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' where e.unit_id = any ($1) and s.birth_date is not null) q group by 1 order by min(i)$q$, true, true, true, 0, null, 5),
('mat.raca', 'matriculas', 'Alunos por raça ou cor (autodeclarada)', 'raca', $q$select iara.oraculo_rotulo(coalesce(s.race_color, 'NAO_DECLARADA')), count(distinct s.id) from iara.students s join iara.enrollments e on e.student_id = s.id and e.status = 'ACTIVE' where e.unit_id = any ($1) group by 1$q$, true, true, false, 0, null, 6)
) v(chave, assunto, rotulo, dim, consulta, pessoas, pct, fixa, casas, sufixo, ordem);

-- 4. Números por período --------------------------------------------------------------------------------------------------------
delete from iara.oraculo_fatos;
insert into iara.oraculo_fatos (chave, rotulo, palavras, consulta, ultima, pessoas, casas, sufixo, ordem) values
('faltas', 'Faltas registradas', '\mfaltaram\M|\mfaltou\M|\mfaltas?\M|\mausenc|\mausentes?\M',
  $q$select count(*) from iara.frequencia_registros r join iara.classes c on c.id = r.class_id join iara.frequencia_faltas f on f.registro_id = r.id where r.data between $2 and $3 and c.unit_id = any ($1)$q$,
  $q$select max(r.data) from iara.frequencia_registros r join iara.classes c on c.id = r.class_id where r.data <= $3 and c.unit_id = any ($1)$q$, true, 0, null, 1),
('presenca', 'Presença', '\mfaltaram\M|\mfaltou\M|\mfaltas?\M|\mausenc|\mausentes?\M|\mpresenc|\mpresentes?\M|\mfrequenc|\mcompareceram\M',
  $q$with reg as (select r.id, r.class_id from iara.frequencia_registros r join iara.classes c on c.id = r.class_id where r.data between $2 and $3 and c.unit_id = any ($1)), m as (select e.class_id, count(*) n from iara.enrollments e where e.status = 'ACTIVE' and e.unit_id = any ($1) group by 1), p as (select sum(m.n) n from reg join m on m.class_id = reg.class_id), f as (select count(*) n from iara.frequencia_faltas fa join reg on reg.id = fa.registro_id) select round(100.0 - 100.0 * f.n / nullif(p.n, 0), 1) from p, f$q$,
  $q$select max(r.data) from iara.frequencia_registros r join iara.classes c on c.id = r.class_id where r.data <= $3 and c.unit_id = any ($1)$q$, false, 1, '%', 2),
('ocorrencias', 'Ocorrências registradas (sem elogios)', '\mocorrenc|\mbrigas?\M|\mbullying\M|\mviolenc',
  $q$select count(*) from iara.ocorrencias where (ocorrida_em at time zone 'America/Sao_Paulo')::date between $2 and $3 and tipo <> 'ELOGIO' and unit_id = any ($1) and ($4 or not coalesce(sigilosa, false))$q$, null, false, 0, null, 3),
('refeicoes', 'Refeições servidas', '\mrefeic|\mmerenda\M',
  $q$select coalesce(sum(quantidade), 0) from iara.refeicoes_servidas where data between $2 and $3 and unit_id = any ($1)$q$,
  $q$select max(data) from iara.refeicoes_servidas where data <= $3 and unit_id = any ($1)$q$, false, 0, null, 4),
('chamados', 'Chamados de manutenção abertos', '\mchamados?\M|\mmanutenc',
  $q$select count(*) from iara.manutencao_chamados where (aberto_em at time zone 'America/Sao_Paulo')::date between $2 and $3 and unit_id = any ($1)$q$, null, false, 0, null, 5),
('protocolos', 'Protocolos abertos', '\mprotocolos?\M|\matendimentos?\M|\mdemandas?\M',
  $q$select count(*) from iara.service_cases where (opened_at at time zone 'America/Sao_Paulo')::date between $2 and $3 and ($4 or unit_id = any ($1))$q$, null, false, 0, null, 6),
('viagens_perdidas', 'Viagens não realizadas', '\mviagens?\M|\mtransporte\M|\monibus\M|\mvans?\M',
  $q$select count(*) from iara.transporte_viagens v join iara.transporte_rotas r on r.id = v.rota_id where v.data between $2 and $3 and v.situacao = 'NAO_REALIZADA' and r.unit_id = any ($1)$q$,
  $q$select max(v.data) from iara.transporte_viagens v join iara.transporte_rotas r on r.id = v.rota_id where v.data <= $3 and r.unit_id = any ($1)$q$, false, 0, null, 7),
('viagens_atraso', 'Viagens com atraso', '\mviagens?\M|\mtransporte\M|\monibus\M|\mvans?\M|\matrasos?\M',
  $q$select count(*) from iara.transporte_viagens v join iara.transporte_rotas r on r.id = v.rota_id where v.data between $2 and $3 and coalesce(v.atraso_min, 0) > 0 and r.unit_id = any ($1)$q$,
  $q$select max(v.data) from iara.transporte_viagens v join iara.transporte_rotas r on r.id = v.rota_id where v.data <= $3 and r.unit_id = any ($1)$q$, false, 0, null, 8),
('ponto', 'Profissionais que marcaram o ponto', '\mmarcaram\M|\mbateram\M|\mponto\M',
  $q$select count(distinct staff_id) from iara.ponto_marcacoes where data between $2 and $3 and unit_id = any ($1)$q$,
  $q$select max(data) from iara.ponto_marcacoes where data <= $3 and unit_id = any ($1)$q$, true, 0, null, 9),
('matriculas', 'Matrículas novas', '\mmatricul',
  $q$select count(*) from iara.enrollments where enrollment_date between $2 and $3 and unit_id = any ($1)$q$, null, true, 0, null, 10),
('encaminhamentos', 'Encaminhamentos criados', '\mencaminh|\mconselho tutelar\M',
  $q$select count(*) from iara.encaminhamentos where (created_at at time zone 'America/Sao_Paulo')::date between $2 and $3 and unit_id = any ($1)$q$, null, true, 0, null, 11),
('alertas', 'Alertas de frequência novos', '\malertas?\M',
  $q$select count(*) from iara.frequencia_alertas where (detectado_em at time zone 'America/Sao_Paulo')::date between $2 and $3 and unit_id = any ($1)$q$, null, true, 0, null, 12),
('busca_ativa', 'Casos de busca ativa abertos', '\mbusca ativa\M',
  $q$select count(*) from iara.busca_ativa_casos where (aberto_em at time zone 'America/Sao_Paulo')::date between $2 and $3 and unit_id = any ($1)$q$, null, true, 0, null, 13),
('ofertas', 'Ofertas de vaga feitas', '\mofertas?\M',
  $q$select count(*) from iara.vacancy_offers where (offered_at at time zone 'America/Sao_Paulo')::date between $2 and $3 and unit_id = any ($1)$q$, null, true, 0, null, 14);

-- 5. Peso: dizer o motivo real em vez de "não disponível"; as medidas continuam respondendo ---------------------------------------
insert into iara.oraculo_indicadores (chave, tema, rotulo, consulta, pessoas, sufixo, casas, palavras, palavras_ranking, pior, ordem) values
('nut.normal', 'nutricao', 'Crianças com peso normal (última medida)', $q$select case when count(zscore) > 0 then count(*) filter (where zscore between -2 and 1) end from (select distinct on (student_id) zscore from iara.antropometria where unit_id = any ($1) order by student_id, data desc) q$q$, true, null, 0, null, null, 'menor', 9)
on conflict (chave) do update set rotulo = excluded.rotulo, consulta = excluded.consulta, pessoas = excluded.pessoas, ordem = excluded.ordem;

update iara.oraculo_indicadores set palavras = v.palavras from (values
  ('nut.excesso', '\mobesid|\mobes[oa]s?\M|\msobrepeso|\mexcesso de peso|\macima do peso'),
  ('nut.baixo', '\mdesnutri|\mbaixo peso|\mabaixo do peso|\mpeso baixo|\mmagreza|\mmagr[oa]s?\M'),
  ('nut.normal', '(?<!abaixo do )(?<!acima do )\mpeso normal\M|\meutrofi|\mpeso adequado\M|\mpeso ideal\M'),
  ('nut.medidas', '\mobesid|\mobes[oa]s?\M|\msobrepeso|\mexcesso de peso|\macima do peso|\mdesnutri|\mbaixo peso|\mabaixo do peso|\mpeso baixo|\mmagreza|\mmagr[oa]s?\M|\mpeso\M|\mmedid[ao]s?\M|\mantropometr'),
  ('nut.imc', '\mobesid|\mobes[oa]s?\M|\msobrepeso|\mexcesso de peso|\macima do peso|\mdesnutri|\mbaixo peso|\mabaixo do peso|\mpeso baixo|\mmagreza|\mmagr[oa]s?\M|\mpeso\M|\mimc\M')
) v(chave, palavras) where iara.oraculo_indicadores.chave = v.chave;
update iara.oraculo_indicadores set palavras = '\mcusto|\mgast' where chave = 'man.custo';
update iara.oraculo_indicadores set sem_dado = 'A classificação pelo IMC para a idade depende da tabela oficial da OMS, que a nutricionista responsável precisa importar no sistema.'
where chave in ('nut.excesso', 'nut.baixo', 'nut.normal');

-- os números de um tema: agora dizem também o que falta e por quê
create or replace function iara.oraculo_tema_numeros(p_tema text, p_chaves text[], p_unit integer, p_area integer) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  rc record := iara.oraculo_recorte_de(p_unit, p_area);
  i iara.oraculo_indicadores;
  n jsonb := '[]';
  f jsonb := '[]';
  x jsonb;
begin
  for i in select * from iara.oraculo_indicadores
           where (p_chaves is not null and chave = any (p_chaves)) or (p_chaves is null and tema = p_tema) order by ordem loop
    x := iara.oraculo_numero(i, rc.unidades, rc.cidade);
    if x ->> 'valor' is not null or (x ->> 'sigilo') is not null then
      n := n || x;
    elsif i.sem_dado is not null then
      f := f || jsonb_build_object('chave', i.chave, 'rotulo', i.rotulo, 'motivo', i.sem_dado);
    end if;
  end loop;
  return jsonb_build_object('topico', coalesce(p_tema, (select tema from iara.oraculo_indicadores where chave = p_chaves[1])), 'recorte', rc.nome,
    'unidade', p_unit, 'area', p_area, 'numeros', n, 'faltando', f,
    'nota', 'Dados da demonstração do IARA Educa. Só números agregados; contagens de 1 ou 2 pessoas aparecem como "menos de 3".');
end $$;

-- 6. Funções de leitura ---------------------------------------------------------------------------------------------------------
-- um detalhe com o sigilo aplicado
create or replace function iara.oraculo_detalhe_lista(p_chave text, p_units integer[], p_cidade boolean, p_limite integer default 8) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  d iara.oraculo_detalhes;
  x record;
  v_itens jsonb := '[]';
  v_total numeric := 0;
  v_sigilo numeric := 0;
  v_resto numeric := 0;
  v_outros numeric;
  v_lim integer := greatest(least(coalesce(p_limite, 8), 30), 1);
begin
  select * into d from iara.oraculo_detalhes where chave = p_chave;
  if d.chave is null then raise exception 'Detalhe desconhecido: %', p_chave using errcode = '22023'; end if;
  if d.casas > 0 then v_lim := 30; end if;  -- média ou percentual: vão todas, porque não se somam num "Demais"
  for x in execute 'select q.nome::text nome, q.valor::numeric valor from (' || d.consulta || ') q(nome, valor) where q.valor is not null and q.valor <> 0 and q.nome is not null'
                   || case when d.ordem_fixa then '' else ' order by q.valor desc, q.nome' end
           using p_units, p_cidade, iara.hoje_local() loop
    v_total := v_total + x.valor;
    if d.pessoas and x.valor between 1 and 2 then
      v_sigilo := v_sigilo + x.valor;
    elsif jsonb_array_length(v_itens) < v_lim then
      v_itens := v_itens || jsonb_build_object('nome', x.nome, 'valor', x.valor);
    elsif d.mostra_pct then
      v_resto := v_resto + x.valor;
    end if;
  end loop;
  v_outros := v_sigilo + v_resto;
  if d.mostra_pct and v_total > 0 then
    select jsonb_agg(i || jsonb_build_object('pct', round(100 * (i ->> 'valor')::numeric / v_total, 1)) order by o) into v_itens
    from jsonb_array_elements(v_itens) with ordinality t(i, o);
  end if;
  return jsonb_build_object('chave', d.chave, 'rotulo', d.rotulo, 'casas', d.casas, 'sufixo', d.sufixo, 'itens', coalesce(v_itens, '[]'::jsonb),
    'total', case when d.mostra_pct and not (d.pessoas and v_outros between 1 and 2) then v_total end)
    || case when v_outros > 0 then jsonb_build_object('outros', jsonb_build_object(
         'nome', case when v_sigilo > 0 and v_resto = 0 then 'Outros (menos de 3 cada)' else 'Demais' end,
         'valor', case when d.pessoas and v_outros between 1 and 2 then null else v_outros end)) else '{}'::jsonb end;
end $$;

create or replace function iara.oraculo_detalhe_texto(x jsonb) returns text
language plpgsql immutable set search_path = iara, public
as $$
declare
  v text;
  v_casas integer := coalesce((x ->> 'casas')::int, 0);
begin
  select string_agg('• ' || (i ->> 'nome') || ': ' || iara.num_br((i ->> 'valor')::numeric, v_casas) || coalesce(x ->> 'sufixo', '')
                    || case when i ->> 'pct' is null then ''
                            when (i ->> 'pct')::numeric < 1 then ' (menos de 1%)'
                            else ' (' || iara.num_br((i ->> 'pct')::numeric, 0) || '%)' end, E'\n' order by o) into v
  from jsonb_array_elements(x -> 'itens') with ordinality t(i, o);
  if x ? 'outros' then
    v := coalesce(v || E'\n', '') || '• ' || (x -> 'outros' ->> 'nome')
         || case when x -> 'outros' ->> 'valor' is not null then ': ' || iara.num_br((x -> 'outros' ->> 'valor')::numeric, v_casas) else '' end;
  end if;
  if v is null then return (x ->> 'rotulo') || ': sem registros neste recorte.'; end if;
  return case when x ->> 'total' is null then x ->> 'rotulo'
              when x ->> 'rotulo' like '%)' then left(x ->> 'rotulo', -1) || '; total: ' || iara.num_br((x ->> 'total')::numeric, v_casas) || ')'
              else (x ->> 'rotulo') || ' (total: ' || iara.num_br((x ->> 'total')::numeric, v_casas) || ')' end || ':' || E'\n' || v;
end $$;

create or replace function iara.oraculo_numero_texto(x jsonb) returns text
language sql immutable set search_path = iara, public as $$
  select (x ->> 'rotulo') || ': ' || case when (x ->> 'sigilo')::boolean then 'menos de 3'
    else iara.num_br((x ->> 'valor')::numeric, coalesce((x ->> 'casas')::int, 0)) || coalesce(x ->> 'sufixo', '') end
$$;

-- aprofundar um assunto: números, detalhes e onde mais pesa
create or replace function iara.oraculo_aprofundar(p_assunto text, p_unit integer, p_area integer, p_limite integer default 4, p_chaves text[] default null, p_numeros boolean default true) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  a iara.oraculo_assuntos;
  rc record := iara.oraculo_recorte_de(p_unit, p_area);
  n jsonb := '{}';
  d iara.oraculo_detalhes;
  det jsonb := '[]';
  x jsonb;
  v_onde jsonb;
begin
  select * into a from iara.oraculo_assuntos where assunto = p_assunto;
  if a.assunto is null then raise exception 'Assunto desconhecido: %', p_assunto using errcode = '22023'; end if;
  if p_numeros then
    if cardinality(a.indicadores) > 0 then
      n := iara.oraculo_tema_numeros(null, a.indicadores, p_unit, p_area);
    elsif exists (select 1 from iara.oraculo_temas where tema = a.tema) then
      n := iara.oraculo_tema_numeros(a.tema, null, p_unit, p_area);
    else
      n := iara.oraculo_numeros(a.tema, p_unit, p_area);
    end if;
    if a.ranking is not null and rc.cidade then
      v_onde := iara.oraculo_ranking_lista(a.ranking, 'regiao', null, 3);
    end if;
  end if;
  for d in select * from iara.oraculo_detalhes where assunto = p_assunto and (p_chaves is null or chave = any (p_chaves)) order by ordem loop
    x := iara.oraculo_detalhe_lista(d.chave, rc.unidades, rc.cidade, p_limite);
    if jsonb_array_length(x -> 'itens') > 0 or x ? 'outros' then det := det || x; end if;
  end loop;
  return jsonb_build_object('assunto', a.assunto, 'topico', a.tema, 'rotulo', a.rotulo, 'recorte', rc.nome, 'unidade', p_unit, 'area', p_area,
    'numeros', coalesce(n -> 'numeros', '[]'::jsonb), 'faltando', coalesce(n -> 'faltando', '[]'::jsonb), 'detalhes', det, 'onde', v_onde,
    'nota', 'Só números agregados; contagens de 1 ou 2 pessoas não aparecem separadas.');
end $$;

create or replace function iara.oraculo_aprofundar_texto(x jsonb) returns text
language plpgsql immutable set search_path = iara, public
as $$
declare
  v text := (x ->> 'rotulo') || ', em ' || (x ->> 'recorte') || ':';
  i jsonb;
  v_falta text;
  v_mot text;
begin
  for i in select * from jsonb_array_elements(coalesce(x -> 'numeros', '[]')) loop
    v := v || E'\n• ' || iara.oraculo_numero_texto(i);
  end loop;
  for i in select * from jsonb_array_elements(coalesce(x -> 'detalhes', '[]')) loop
    v := v || E'\n\n' || iara.oraculo_detalhe_texto(i);
  end loop;
  if jsonb_array_length(coalesce(x -> 'faltando', '[]')) > 0 then
    select string_agg(distinct f ->> 'motivo', ' ') into v_mot from jsonb_array_elements(x -> 'faltando') f;
    v := v || E'\n\nAinda sem resposta sobre baixo peso e obesidade: ' || v_mot;
  end if;
  if jsonb_array_length(coalesce(x -> 'onde' -> 'lista', '[]')) > 0 then
    select string_agg((o ->> 'nome') || ': ' || iara.num_br((o ->> 'valor')::numeric, coalesce((x -> 'onde' ->> 'casas')::int, 0)) || coalesce(x -> 'onde' ->> 'sufixo', ''), '; ') into v_falta
    from jsonb_array_elements(x -> 'onde' -> 'lista') o;
    v := v || E'\n\nRegiões com os ' || case when x -> 'onde' ->> 'ordem' = 'maior' then 'maiores' else 'menores' end
         || ' números em “' || (x -> 'onde' ->> 'rotulo') || '”: ' || v_falta || '.';
  end if;
  return v;
end $$;

-- período pedido
create or replace function iara.oraculo_periodo_da_pergunta(p_w text) returns text
language sql immutable as $$
  select case
    when p_w ~ ' anteontem ' then 'anteontem'
    when p_w ~ ' ontem ' then 'ontem'
    when p_w ~ ' hoje ' then 'hoje'
    when p_w ~ ' ultimos [0-9]{1,3} dias ' then 'ultimos_' || (regexp_match(p_w, ' ultimos ([0-9]{1,3}) dias '))[1]
    when p_w ~ ' semana passada ' then 'semana_passada'
    when p_w ~ ' (esta|nesta|essa|nessa|desta|dessa) semana ' then 'semana'
    when p_w ~ ' mes passado ' then 'mes_passado'
    when p_w ~ ' (este|neste|esse|nesse|deste|desse) mes ' then 'mes'
    when p_w ~ ' (este|neste|esse|nesse|deste|desse) ano ' then 'ano'
  end
$$;

create or replace function iara.oraculo_periodo_datas(p_codigo text, p_hoje date, out de date, out ate date, out rotulo text)
language plpgsql immutable as $$
declare
  v_seg date := date_trunc('week', p_hoje::timestamp)::date;
  v_n integer;
begin
  case
    when p_codigo = 'hoje' then de := p_hoje; ate := p_hoje; rotulo := 'Hoje';
    when p_codigo = 'ontem' then de := p_hoje - 1; ate := p_hoje - 1; rotulo := 'Ontem';
    when p_codigo = 'anteontem' then de := p_hoje - 2; ate := p_hoje - 2; rotulo := 'Anteontem';
    when p_codigo = 'semana' then de := v_seg; ate := p_hoje; rotulo := 'Nesta semana';
    when p_codigo = 'semana_passada' then de := v_seg - 7; ate := v_seg - 1; rotulo := 'Na semana passada';
    when p_codigo = 'mes' then de := date_trunc('month', p_hoje::timestamp)::date; ate := p_hoje; rotulo := 'Neste mês';
    when p_codigo = 'mes_passado' then de := (date_trunc('month', p_hoje::timestamp) - interval '1 month')::date; ate := date_trunc('month', p_hoje::timestamp)::date - 1; rotulo := 'No mês passado';
    when p_codigo = 'ano' then de := date_trunc('year', p_hoje::timestamp)::date; ate := p_hoje; rotulo := 'Neste ano';
    when p_codigo ~ '^ultimos_[0-9]{1,3}$' then
      v_n := greatest(least(split_part(p_codigo, '_', 2)::int, 366), 1);
      de := p_hoje - v_n + 1; ate := p_hoje; rotulo := 'Nos últimos ' || v_n || ' dias';
    else raise exception 'Período desconhecido: %. Use hoje, ontem, anteontem, semana, semana_passada, mes, mes_passado, ano ou ultimos_N.', p_codigo using errcode = '22023';
  end case;
  rotulo := rotulo || ' (' || to_char(de, 'DD/MM') || case when ate <> de then ' a ' || to_char(ate, 'DD/MM') else '' end || ')';
end $$;

-- um fato no período. Com "ultima": período sem nenhum registro não é zero, e o número mostrado é o do último dia que tem registro
create or replace function iara.oraculo_fato_valor(p_chave text, p_units integer[], p_cidade boolean, p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  f iara.oraculo_fatos;
  v numeric;
  v_ult date;
  v_sem boolean := false;
begin
  select * into f from iara.oraculo_fatos where chave = p_chave;
  if f.chave is null then raise exception 'Fato desconhecido: %', p_chave using errcode = '22023'; end if;
  if f.ultima is not null then
    execute 'select (' || f.ultima || ')::date' into v_ult using p_units, p_de, p_ate, p_cidade;
    if v_ult is null then
      return jsonb_build_object('chave', f.chave, 'rotulo', f.rotulo, 'valor', null, 'sem_registro', true);
    end if;
    v_sem := v_ult < p_de;
  end if;
  execute 'select (' || f.consulta || ')::numeric' into v
    using p_units, case when v_sem then v_ult else p_de end, case when v_sem then v_ult else p_ate end, p_cidade;
  return jsonb_build_object('chave', f.chave, 'rotulo', f.rotulo, 'casas', f.casas, 'sufixo', f.sufixo)
    || case when f.pessoas and v between 1 and 2 then jsonb_build_object('valor', null, 'sigilo', true) else jsonb_build_object('valor', v) end
    || case when v_sem then jsonb_build_object('sem_registro', true, 'ultimo_dia', v_ult) else '{}'::jsonb end;
end $$;

create or replace function iara.oraculo_fato_texto(x jsonb) returns text
language plpgsql immutable set search_path = iara, public
as $$
declare
  v_val text := case when (x ->> 'sigilo')::boolean then 'menos de 3'
                     when x ->> 'valor' is null then null
                     else iara.num_br((x ->> 'valor')::numeric, coalesce((x ->> 'casas')::int, 0)) || coalesce(x ->> 'sufixo', '') end;
begin
  if (x ->> 'sem_registro')::boolean and x ->> 'ultimo_dia' is null then
    return (x ->> 'rotulo') || ': sem registro no período.';
  elsif (x ->> 'sem_registro')::boolean then
    return (x ->> 'rotulo') || ': ainda sem registro neste período; no último dia com registro (' || to_char((x ->> 'ultimo_dia')::date, 'DD/MM') || '), ' || coalesce(v_val, '—');
  end if;
  return (x ->> 'rotulo') || ': ' || coalesce(v_val, '—');
end $$;

-- dia pedido no cardápio
create or replace function iara.oraculo_data_da_pergunta(p_w text, p_hoje date) returns date
language plpgsql immutable as $$
declare
  v_seg date := date_trunc('week', p_hoje::timestamp)::date;
  v_d integer := case when p_w ~ ' segunda ' then 0 when p_w ~ ' terca ' then 1 when p_w ~ ' quarta ' then 2 when p_w ~ ' quinta ' then 3 when p_w ~ ' sexta ' then 4 end;
begin
  if p_w ~ ' anteontem ' then return p_hoje - 2; end if;
  if p_w ~ ' ontem ' then return p_hoje - 1; end if;
  if p_w ~ ' amanha ' then return p_hoje + 1; end if;
  if v_d is not null then return v_seg + v_d + case when p_w ~ ' (proxima|que vem) ' then 7 else 0 end; end if;
  return p_hoje;
end $$;

create or replace function iara.oraculo_dia_semana(d date) returns text
language sql immutable as $$
  select (array['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'])[extract(isodow from d)::int] || ', ' || to_char(d, 'DD/MM')
$$;

-- o cardápio publicado de um dia, por faixa. Sem aula (fim de semana ou feriado da rede): avisa e traz o próximo dia com aula
create or replace function iara.oraculo_cardapio_dia(p_data date) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v_d date := p_data;
  v_aviso text;
  v_motivo text;
  n integer := 0;
begin
  loop
    v_motivo := case when extract(isodow from v_d) in (6, 7) then 'fim de semana'
                     else (select e.titulo from iara.calendario_eventos e where e.abrangencia = 'REDE' and e.suspende_aulas and v_d between e.inicio and coalesce(e.fim, e.inicio) limit 1) end;
    exit when v_motivo is null or n > 15;
    if v_aviso is null then v_aviso := iara.oraculo_dia_semana(p_data) || ' não tem aula na rede (' || v_motivo || ').'; end if;
    v_d := v_d + 1;
    n := n + 1;
  end loop;
  return jsonb_build_object('pedido', p_data, 'data', v_d, 'dia', iara.oraculo_dia_semana(v_d), 'aviso', v_aviso,
    'faixas', (select coalesce(jsonb_agg(jsonb_build_object('faixa', c.faixa, 'rotulo', iara.oraculo_rotulo(c.faixa),
        'refeicoes', (select coalesce(jsonb_agg(jsonb_build_object('refeicao', iara.oraculo_rotulo(r.refeicao), 'itens', r.itens)
                        order by array_position(array['DESJEJUM', 'ALMOCO', 'LANCHE', 'JANTAR'], r.refeicao)), '[]')
                      from (select it.refeicao, jsonb_agg(p.nome order by it.ordem) itens
                            from iara.cardapio_itens it join iara.preparacoes p on p.codigo = it.preparacao_codigo
                            where it.cardapio_id = c.id and it.dia_semana = extract(isodow from v_d)::int group by it.refeicao) r))
        order by array_position(array['CRECHE', 'PRE', 'EF'], c.faixa)), '[]')
      from iara.cardapios c where c.semana_inicio = date_trunc('week', v_d::timestamp)::date and c.situacao = 'PUBLICADO'),
    'nota', 'O cardápio é o mesmo em toda a rede, por faixa. Quem tem restrição alimentar validada recebe a substituição na própria unidade.');
end $$;

create or replace function iara.oraculo_cardapio_texto(x jsonb, p_hoje date) returns text
language plpgsql immutable set search_path = iara, public
as $$
declare
  v text;
  g record;
  r jsonb;
  v_dia date := (x ->> 'data')::date;
  v_tem boolean := false;
begin
  v := coalesce((x ->> 'aviso') || ' O próximo cardápio é o de ' || (x ->> 'dia') || ':',
      'Cardápio ' || case when v_dia = p_hoje then 'de hoje' when v_dia = p_hoje + 1 then 'de amanhã' when v_dia = p_hoje - 1 then 'de ontem' else 'do dia' end
      || ' (' || (x ->> 'dia') || '), igual em toda a rede:');
  for g in select string_agg(t.f ->> 'rotulo', ', ' order by t.o) rotulos, t.f -> 'refeicoes' refeicoes
           from jsonb_array_elements(x -> 'faixas') with ordinality t(f, o)
           where jsonb_array_length(t.f -> 'refeicoes') > 0 group by t.f -> 'refeicoes' order by min(t.o) loop
    v_tem := true;
    v := v || E'\n\n' || g.rotulos;
    for r in select * from jsonb_array_elements(g.refeicoes) loop
      v := v || E'\n• ' || (r ->> 'refeicao') || ': ' || (select string_agg(lower(i), ', ') from jsonb_array_elements_text(r -> 'itens') i);
    end loop;
  end loop;
  if not v_tem then return 'Não há cardápio publicado para ' || (x ->> 'dia') || '.'; end if;
  return v;
end $$;

-- calendário: eventos da rede e, num recorte, os das unidades dele
create or replace function iara.oraculo_calendario_lista(p_units integer[], p_cidade boolean, p_dias integer, p_tipo text default null) returns jsonb
language sql stable security definer set search_path = iara, public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('titulo', q.titulo, 'tipo', q.tipo, 'inicio', q.inicio, 'fim', q.fim, 'sem_aula', q.suspende_aulas, 'dia', iara.oraculo_dia_semana(q.inicio)) order by q.inicio, q.titulo), '[]')
  from (select e.* from iara.calendario_eventos e
        where coalesce(e.fim, e.inicio) >= iara.hoje_local() and e.inicio <= iara.hoje_local() + greatest(least(coalesce(p_dias, 90), 400), 1)
          and (p_tipo is null or e.tipo = p_tipo)
          and (e.abrangencia = 'REDE' or (not p_cidade and e.unit_id = any (p_units)))
        order by e.inicio, e.titulo limit 15) q
$$;

-- 7. Ferramentas (página e MCP) ---------------------------------------------------------------------------------------------------
-- p: assunto (sem ele: a lista do que dá para detalhar), detalhe? (chave), unidade?, regiao?, limite?
create or replace function api.oraculo_detalhar(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  a record := iara.oraculo_args(p);
  v_chaves text[] := case when jsonb_typeof(p -> 'detalhes') = 'array' then array(select jsonb_array_elements_text(p -> 'detalhes'))
                          when nullif(p ->> 'detalhe', '') is not null then array[p ->> 'detalhe'] end;
begin
  perform iara.require_perm('oraculo.prefeito');
  if nullif(p ->> 'assunto', '') is null then
    return jsonb_build_object('assuntos', (select coalesce(jsonb_agg(jsonb_build_object('assunto', s.assunto, 'rotulo', s.rotulo,
        'detalhes', (select coalesce(jsonb_agg(jsonb_build_object('chave', d.chave, 'rotulo', d.rotulo) order by d.ordem), '[]') from iara.oraculo_detalhes d where d.assunto = s.assunto)) order by s.ordem), '[]')
      from iara.oraculo_assuntos s));
  end if;
  return iara.oraculo_aprofundar(p ->> 'assunto', a.p_unit, a.p_area, coalesce(nullif(p ->> 'limite', '')::int, 8), v_chaves);
end $$;

-- p: fato (ou fatos[]; sem nenhum: a lista), periodo? (hoje, ontem, anteontem, semana, semana_passada, mes, mes_passado, ano, ultimos_N) ou de e ate, unidade?, regiao?
create or replace function api.oraculo_periodo(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  a record := iara.oraculo_args(p);
  rc record := iara.oraculo_recorte_de(a.p_unit, a.p_area);
  v_hoje date := iara.hoje_local();
  v_fatos text[] := case when jsonb_typeof(p -> 'fatos') = 'array' then array(select jsonb_array_elements_text(p -> 'fatos'))
                         when nullif(p ->> 'fato', '') is not null then array[p ->> 'fato'] end;
  pd record;
  v_de date := nullif(p ->> 'de', '')::date;
  v_ate date := coalesce(nullif(p ->> 'ate', '')::date, v_hoje);
  v_rot text;
begin
  perform iara.require_perm('oraculo.prefeito');
  if v_fatos is null then
    return jsonb_build_object('fatos', (select coalesce(jsonb_agg(jsonb_build_object('chave', f.chave, 'rotulo', f.rotulo) order by f.ordem), '[]') from iara.oraculo_fatos f),
                              'periodos', jsonb_build_array('hoje', 'ontem', 'anteontem', 'semana', 'semana_passada', 'mes', 'mes_passado', 'ano', 'ultimos_7'));
  end if;
  if v_de is null then
    pd := iara.oraculo_periodo_datas(coalesce(nullif(p ->> 'periodo', ''), 'hoje'), v_hoje);
    v_de := pd.de; v_ate := pd.ate; v_rot := pd.rotulo;
  else
    if v_ate < v_de or v_ate - v_de > 366 then raise exception 'Período inválido: até 366 dias.' using errcode = '22023'; end if;
    v_rot := 'De ' || to_char(v_de, 'DD/MM/YYYY') || ' a ' || to_char(v_ate, 'DD/MM/YYYY');
  end if;
  return jsonb_build_object('recorte', rc.nome, 'periodo', v_rot, 'de', v_de, 'ate', v_ate,
    'fatos', (select coalesce(jsonb_agg(iara.oraculo_fato_valor(c, rc.unidades, rc.cidade, v_de, v_ate)), '[]') from unnest(v_fatos) c));
end $$;

-- p: data? (AAAA-MM-DD; padrão: hoje)
create or replace function api.oraculo_cardapio(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('oraculo.prefeito');
  return iara.oraculo_cardapio_dia(coalesce(nullif(p ->> 'data', '')::date, iara.hoje_local()));
end $$;

-- p: dias? (padrão: 90), tipo?, unidade?, regiao?
create or replace function api.oraculo_calendario(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  a record := iara.oraculo_args(p);
  rc record := iara.oraculo_recorte_de(a.p_unit, a.p_area);
begin
  perform iara.require_perm('oraculo.prefeito');
  return jsonb_build_object('recorte', rc.nome, 'eventos', iara.oraculo_calendario_lista(rc.unidades, rc.cidade, nullif(p ->> 'dias', '')::int, nullif(p ->> 'tipo', '')));
end $$;

-- o que o Oráculo sabe: temas e indicadores, assuntos com detalhes, e números por período
create or replace function api.oraculo_indicadores(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('oraculo.prefeito');
  return jsonb_build_object(
    'temas', (select coalesce(jsonb_agg(jsonb_build_object('tema', t.tema, 'nome', t.rotulo,
        'indicadores', (select jsonb_agg(jsonb_build_object('chave', i.chave, 'rotulo', i.rotulo) order by i.ordem) from iara.oraculo_indicadores i where i.tema = t.tema)) order by t.ordem), '[]')
      from iara.oraculo_temas t),
    'assuntos', (select coalesce(jsonb_agg(jsonb_build_object('assunto', s.assunto, 'rotulo', s.rotulo,
        'detalhes', (select coalesce(jsonb_agg(jsonb_build_object('chave', d.chave, 'rotulo', d.rotulo) order by d.ordem), '[]') from iara.oraculo_detalhes d where d.assunto = s.assunto)) order by s.ordem), '[]')
      from iara.oraculo_assuntos s),
    'fatos_por_periodo', (select coalesce(jsonb_agg(jsonb_build_object('chave', f.chave, 'rotulo', f.rotulo) order by f.ordem), '[]') from iara.oraculo_fatos f));
end $$;

-- 8. Roteador (sem a chave da Anthropic) ------------------------------------------------------------------------------------------
create or replace function iara.oraculo_limite_da_pergunta(p_w text) returns integer
language sql immutable as $$
  select greatest(least(coalesce(
    (select case m[1] when 'dois' then 2 when 'duas' then 2 when 'tres' then 3 when 'quatro' then 4 when 'cinco' then 5 when 'seis' then 6
                      when 'sete' then 7 when 'oito' then 8 when 'nove' then 9 when 'dez' then 10 else m[1]::int end
     from regexp_match(p_w, ' (?:top )?([0-9]{1,2}|dois|duas|tres|quatro|cinco|seis|sete|oito|nove|dez) (?:primeir[oa]s |maiores |menores |piores |melhores )?(?:unidades|escolas|cmeis|regioes|bairros) ') m),
    case when p_w ~ ' quais ' then 5 else 3 end), 30), 1)
$$;

create or replace function api.oraculo_perguntar(p jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_perg text := btrim(coalesce(p ->> 'pergunta', ''));
  v_w text := ' ' || iara.oraculo_palavras(p ->> 'pergunta') || ' ';
  v_rec jsonb := iara.oraculo_recorte(p ->> 'pergunta');
  v_unit integer := (v_rec ->> 'unidade')::int;
  v_area integer := (v_rec ->> 'area')::int;
  rc record := iara.oraculo_recorte_de(v_unit, v_area);
  v_hoje date := iara.hoje_local();
  v_exemplos constant text := 'Pergunte, por exemplo: “Quais os motivos dos encaminhamentos?”, “Qual o cardápio de hoje?”, “Quantas crianças faltaram ontem?”, “Qual escola tem mais ocorrências?” ou “O que está acontecendo na rede?”.';
  v_aprofundar constant text := ' (fale|falar|fala|conte|contar|detalhe|detalhes|detalhar|detalhado|explique|explica|explicar|aprofunde|aprofundar|analise|analisa|analisar|entender|como esta|como estao|como anda|como andam|como vai|como vao|panorama|resumo|balanco|mais sobre|saber mais) ';
  v_bolsa constant text := 'bolsa|beneficio|condicionalidade|sistema presenca|cadunico';
  a iara.oraculo_assuntos;
  pd record;
  v_cod text;
  v_nome text;
  v_quem text;
  v_chaves text[];
  v_tema text;
  v_ord text;
  v_tipo text;
  v_por text;
  v_alvo text;
  v_topico text;
  v_conhecido boolean;
  v_aviso text;
  n integer;
  r jsonb := '{}';
  x jsonb;
  v_partes text[] := '{}';
  v_notas boolean := false;
  v_texto text;
  v_fora boolean := false;
  v_ferr jsonb := '[]';
begin
  perform iara.require_perm('oraculo.prefeito');
  if length(v_perg) < 3 then
    raise exception 'Faça uma pergunta.' using errcode = '22023';
  end if;
  v_nome := (regexp_match(v_w, ' (?:se chamam?|com o nome de|com o nome|de nome|(?:alunos?|criancas?|estudantes?|professor(?:es|as?)?|pessoas?|profissionais|responsaveis) chamad[oa]s?) +([a-z]{3,}) '))[1];

  -- dado de pessoa: fora do Oráculo
  if v_w ~ ' (telefone|telefones|celular|whatsapp d[aeo]|endereco|enderecos|cpf|rg|nis|email|e mail) ' and v_w ~ ' (d[aeo]s?|alun[oa]s?|famili[as]+|responsave[il]s?|mae|pai) '
     and v_w !~ ' (quantos|quantas) ' or v_w ~ ' (quem (e|sao|foi|foram)|lista de nomes|nomes d[aeo]s?|quais os nomes|me diga o nome) ' then
    v_texto := 'Dados de uma pessoa (nome, telefone, endereço, documentos) não ficam no Oráculo: ele traz números, nunca quem são as pessoas. '
               || 'O detalhe de um caso fica com a Secretaria e com a unidade, com registro de acesso. ' || v_exemplos;
    v_fora := true;

  -- estatística de nomes: só a contagem, com sigilo
  elsif v_nome is not null then
    v_quem := case when v_w ~ ' (professor\w*|profissiona\w*|servidor\w*|educador\w*|funcionari\w*) ' then 'PROFISSIONAIS'
                   when v_w ~ ' (responsave\w*|maes?|pais?|familias?) ' then 'RESPONSAVEIS' else 'ALUNOS' end;
    n := iara.oraculo_contar_nome(v_nome, v_quem, rc.unidades, rc.cidade);
    v_texto := 'Em ' || rc.nome || ': '
               || case when n = 0 then case v_quem when 'PROFISSIONAIS' then 'nenhum profissional' when 'RESPONSAVEIS' then 'nenhum responsável' else 'nenhum aluno' end
                       else case when n between 1 and 2 then 'menos de 3' else iara.num_br(n) end
                            || case v_quem when 'PROFISSIONAIS' then ' profissionais' when 'RESPONSAVEIS' then ' responsáveis' else ' alunos' end end
               || ' com “' || initcap(v_nome) || '” no nome (primeiro nome ou sobrenome). Só a contagem: o Oráculo não mostra quem são.';
    v_topico := 'nomes';
    v_ferr := jsonb_build_array(jsonb_build_object('nomes', v_quem));
    r := jsonb_build_object('topico', v_topico, 'recorte', rc.nome, 'unidade', v_unit, 'area', v_area, 'numeros', '[]'::jsonb);

  -- o que o IARA Educa não guarda: dizer isso, em vez de responder outro número
  elsif v_w ~ ' (salarios?|salarial|salariais|remuneracao|folha de pagamento|orcamentos?|licitac\w+|receitas?|despesas?|fundeb|verbas?) ' then
    v_texto := 'Salários, folha de pagamento, orçamento e licitações não estão no IARA Educa: esses dados ficam nos sistemas de gestão da Prefeitura. '
               || 'O Oráculo responde o que a rede registra aqui. ' || v_exemplos;
    v_fora := true;

  -- cardápio: o que vai no prato, não a contagem de refeições
  elsif v_w ~ ' cardapios? '
        or (v_w ~ ' o que (tem|teve|vai ter|e servido|foi servido|sera servido|servem|serviram|vao servir|comem|comeram|vao comer) '
            and v_w ~ ' (merenda|almoco|lanche|jantar|desjejum|comida|comer|comem|comeram|servido|servem|serviram|servir) ') then
    x := iara.oraculo_cardapio_dia(iara.oraculo_data_da_pergunta(v_w, v_hoje));
    v_texto := iara.oraculo_cardapio_texto(x, v_hoje);
    v_topico := 'cardapio';
    v_ferr := jsonb_build_array(jsonb_build_object('cardapio', x ->> 'data'));
    r := jsonb_build_object('topico', v_topico, 'recorte', 'Maringá', 'unidade', null, 'area', null, 'numeros', '[]'::jsonb);

  -- calendário
  elsif v_w !~ ' (quantos|quantas) ' and v_w ~ ' (calendario|feriados?|recesso|recessos|ferias|letivos?|proximos? eventos?|reuniao de pais|reunioes de pais|conselho de classe|conselhos de classe|fim do bimestre|fim de bimestre|quando termina|quando acaba|quando comeca|quando voltam?|ponto facultativo) ' then
    v_tipo := case when v_w ~ ' feriados? ' then 'FERIADO' end;
    x := iara.oraculo_calendario_lista(rc.unidades, rc.cidade, case when v_tipo is not null or v_w ~ ' (letivos?|ferias|recessos?|termina|acaba) ' then 400 else 90 end, v_tipo);
    v_topico := 'calendario';
    v_ferr := jsonb_build_array(jsonb_build_object('calendario', coalesce(v_tipo, 'todos')));
    r := jsonb_build_object('topico', v_topico, 'recorte', rc.nome, 'unidade', v_unit, 'area', v_area, 'numeros', '[]'::jsonb);
    if jsonb_array_length(x) = 0 then
      v_texto := 'Não há ' || case when v_tipo is not null then 'feriado' else 'evento' end || ' no calendário para os próximos dias.';
    else
      select string_agg('• ' || (e ->> 'dia') || ': ' || (e ->> 'titulo') || case when (e ->> 'sem_aula')::boolean then ' (sem aula)' else '' end, E'\n' order by o) into v_texto
      from jsonb_array_elements(x) with ordinality t(e, o);
      v_texto := case when v_tipo is not null then 'Próximos feriados:' else 'Próximos eventos do calendário' || case when rc.cidade then ' da rede:' else ', em ' || rc.nome || ':' end end || E'\n' || v_texto;
    end if;
  end if;

  -- um número num período: "faltaram ontem", "ocorrências desta semana"
  if v_texto is null and v_w !~ ' (venc\w*) ' then
    v_cod := iara.oraculo_periodo_da_pergunta(v_w);
    if v_cod is not null then
      v_chaves := array(select f.chave from iara.oraculo_fatos f where v_w ~ f.palavras order by f.ordem limit 3);
      if cardinality(v_chaves) > 0 then
        pd := iara.oraculo_periodo_datas(v_cod, v_hoje);
        v_partes := array(select iara.oraculo_fato_texto(iara.oraculo_fato_valor(c, rc.unidades, rc.cidade, pd.de, pd.ate)) from unnest(v_chaves) c);
        v_notas := exists (select 1 from unnest(v_partes) t where t like '%sem registro%');
        v_texto := pd.rotulo || ', em ' || rc.nome
                   || case when v_notas or cardinality(v_partes) >= 3 then E':\n• ' || array_to_string(v_partes, E'\n• ')
                           else ' — ' || array_to_string(v_partes, '; ') || '.' end;
        v_topico := 'periodo';
        v_ferr := jsonb_build_array(jsonb_build_object('periodo', v_cod, 'fatos', v_chaves));
        r := jsonb_build_object('topico', v_topico, 'recorte', rc.nome, 'unidade', v_unit, 'area', v_area, 'numeros', '[]'::jsonb);
      end if;
    end if;
  end if;

  -- comparação: o indicador cujas palavras aparecem na pergunta, com a quantidade pedida
  if v_texto is null and v_w ~ ' (qual|quais|onde|ranking) ' and v_w ~ ' (mais|menos|maior|maiores|menor|menores|pior|piores|melhor|melhores) '
     and (v_w ~ ' (unidades?|escolas?|cmeis?|regioes|regiao|bairros?) ' or v_w ~ ' onde ') then
    select chave, pior into v_tema, v_ord from iara.oraculo_indicadores where palavras_ranking is not null and v_w ~ palavras_ranking
    order by (tema = 'base'), ordem limit 1;
    if v_tema is not null then
      v_ord := case when v_w ~ ' (menos|menor|menores) ' then 'menor' when v_w ~ ' (mais|maior|maiores) ' then 'maior'
                    when v_w ~ ' (melhor|melhores) ' then case when v_ord = 'maior' then 'menor' else 'maior' end
                    else v_ord end;
      v_tipo := case when v_w ~ ' cmeis? ' then 'CMEI' when v_w ~ ' escolas? ' then 'ESCOLA' end;
      v_por := case when v_w ~ ' (regioes|regiao|bairros?) ' then 'regiao' else 'unidade' end;
      x := iara.oraculo_ranking_lista(v_tema, v_por, v_ord, iara.oraculo_limite_da_pergunta(v_w), v_tipo);
      n := jsonb_array_length(x -> 'lista');
      if n > 0 then
        v_alvo := case when v_por = 'regiao' then case when n = 1 then 'a região' else 'as ' || n || ' regiões' end
                       when v_tipo = 'CMEI' then case when n = 1 then 'o CMEI' else 'os ' || n || ' CMEIs' end
                       when v_tipo = 'ESCOLA' then case when n = 1 then 'a escola' else 'as ' || n || ' escolas' end
                       else case when n = 1 then 'a unidade' else 'as ' || n || ' unidades' end end;
        select string_agg(o || '. ' || (i ->> 'nome') || ': ' || iara.num_br((i ->> 'valor')::numeric, coalesce((x ->> 'casas')::int, 0)) || coalesce(x ->> 'sufixo', ''), E'\n' order by o) into v_texto
        from jsonb_array_elements(x -> 'lista') with ordinality t(i, o);
        v_texto := (x ->> 'rotulo') || ': ' || v_alvo || ' com os ' || case when x ->> 'ordem' = 'maior' then 'maiores' else 'menores' end || ' números:' || E'\n' || v_texto;
      else
        v_texto := (x ->> 'rotulo') || ': nenhuma comparação a mostrar (valores pequenos ficam em sigilo).';
      end if;
      v_topico := 'ranking';
      v_ferr := jsonb_build_array(jsonb_build_object('ranking', v_tema, 'por', v_por, 'limite', n));
      r := jsonb_build_object('topico', v_topico, 'recorte', rc.nome, 'unidade', v_unit, 'area', v_area, 'numeros', '[]'::jsonb);
    end if;
  end if;

  -- assunto: um recorte pedido (motivo, tipo, situação...), o aprofundamento ou "os principais"
  if v_texto is null and v_w !~ v_bolsa then
    select * into a from iara.oraculo_assuntos s where v_w ~ s.palavras order by s.ordem limit 1;
    if a.assunto is not null then
      v_chaves := array(select d.chave from iara.oraculo_detalhes d where d.assunto = a.assunto and d.pede is not null and v_w ~ d.pede order by d.ordem limit 3);
      if v_w ~ ' por (regiao|regioes|bairro|bairros|escola|escolas|unidade|unidades) ' and a.ranking is not null then
        v_por := case when v_w ~ ' por (regiao|regioes|bairro|bairros) ' then 'regiao' else 'unidade' end;
        x := iara.oraculo_ranking_lista(a.ranking, v_por, null, 5);
        select string_agg(o || '. ' || (i ->> 'nome') || ': ' || iara.num_br((i ->> 'valor')::numeric, coalesce((x ->> 'casas')::int, 0)) || coalesce(x ->> 'sufixo', ''), E'\n' order by o) into v_texto
        from jsonb_array_elements(x -> 'lista') with ordinality t(i, o);
        v_texto := (x ->> 'rotulo') || ', ' || case when x ->> 'ordem' = 'maior' then 'os maiores' else 'os menores' end || ' por ' || case when v_por = 'regiao' then 'região' else 'unidade' end || ':' || E'\n' || coalesce(v_texto, 'nada a mostrar (valores pequenos ficam em sigilo).');
        v_ferr := jsonb_build_array(jsonb_build_object('ranking', a.ranking, 'por', v_por));
        r := jsonb_build_object('topico', a.tema, 'recorte', rc.nome, 'unidade', v_unit, 'area', v_area, 'numeros', '[]'::jsonb);
      elsif cardinality(v_chaves) = 0 and v_w ~ v_aprofundar then
        -- aprofundar: números, até 4 itens por detalhe e onde mais pesa
        x := iara.oraculo_aprofundar(a.assunto, v_unit, v_area, 4);
        v_texto := iara.oraculo_aprofundar_texto(x);
        v_ferr := jsonb_build_array(jsonb_build_object('aprofundar', a.assunto, 'unidade', v_unit, 'area', v_area));
        r := jsonb_build_object('topico', a.tema, 'recorte', rc.nome, 'unidade', v_unit, 'area', v_area, 'numeros', x -> 'numeros');
      else
        if cardinality(v_chaves) = 0 and v_w ~ ' (principais|principal|maiores|mais comuns?|mais frequentes?|o que mais) ' and v_w !~ ' (quantos|quantas) ' then
          v_chaves := array(select d.chave from iara.oraculo_detalhes d where d.assunto = a.assunto order by d.ordem limit 1);
        end if;
        if cardinality(v_chaves) > 0 then
          x := iara.oraculo_aprofundar(a.assunto, v_unit, v_area, 8, v_chaves, false);
          v_texto := a.rotulo || ', em ' || rc.nome || ':';
          if jsonb_array_length(x -> 'detalhes') = 0 then
            v_texto := v_texto || ' sem registros neste recorte.';
          else
            select v_texto || E'\n' || string_agg(iara.oraculo_detalhe_texto(d), E'\n\n' order by o) into v_texto
            from jsonb_array_elements(x -> 'detalhes') with ordinality t(d, o);
          end if;
          v_ferr := jsonb_build_array(jsonb_build_object('detalhes', v_chaves, 'unidade', v_unit, 'area', v_area));
          r := jsonb_build_object('topico', a.tema, 'recorte', rc.nome, 'unidade', v_unit, 'area', v_area, 'numeros', '[]'::jsonb);
        end if;
      end if;
      if v_texto is not null then v_topico := a.tema; end if;
    end if;
  end if;

  -- panorama: "como está a rede" (ou uma unidade ou região): os números e o que pede atenção
  if v_texto is null and v_w !~ v_bolsa and v_w ~ ' (como esta|como estao|como vai|como vao|como anda|como andam|panorama|resumo|balanco|visao geral|fale|conte) '
     and (v_w ~ ' (rede|cidade|educacao|municipio|maringa|geral|tudo) ' or v_unit is not null or v_area is not null) then
    r := iara.oraculo_numeros('visao_geral', v_unit, v_area);
    r := jsonb_set(r, '{numeros}', coalesce((select jsonb_agg(i order by o) from jsonb_array_elements(r -> 'numeros') with ordinality t(i, o) where v_unit is null or i ->> 'rotulo' <> 'Unidades'), '[]'::jsonb)
                                   || coalesce(iara.oraculo_tema_numeros(null, array['base.presenca'], v_unit, v_area) -> 'numeros', '[]'::jsonb));
    v_topico := 'panorama';
    r := r || jsonb_build_object('topico', v_topico);
    select string_agg(iara.oraculo_numero_texto(i), '; ' order by o) into v_texto from jsonb_array_elements(r -> 'numeros') with ordinality t(i, o);
    v_texto := 'Em ' || rc.nome || ': ' || coalesce(v_texto, 'sem números neste recorte') || '.';
    x := iara.oraculo_situacoes_lista(rc.unidades, rc.cidade, 7);
    if jsonb_array_length(x) = 0 then
      v_texto := v_texto || E'\n\nNada pedindo atenção neste momento.';
    else
      select v_texto || E'\n\nO que pede atenção agora:\n' || string_agg('• ' || coalesce((i ->> 'unidade') || ': ', '') || (i ->> 'texto') || ' (' || lower(i ->> 'area') || ')', E'\n') into v_texto
      from (select i from jsonb_array_elements(x) i limit 8) q;
      v_texto := v_texto || case when jsonb_array_length(x) > 8 then E'\n…e mais ' || (jsonb_array_length(x) - 8) || ' item(ns). Pergunte “O que está acontecendo na rede?” para ver a lista.' else '' end;
    end if;
    v_ferr := jsonb_build_array(jsonb_build_object('topico', 'panorama', 'unidade', v_unit, 'area', v_area));
  end if;

  if v_texto is null then
    -- indicadores específicos; se não houver, o tema inteiro
    v_chaves := array(select chave from iara.oraculo_indicadores where palavras is not null and v_w ~ palavras order by ordem limit 6);
    if cardinality(v_chaves) > 0 then
      r := iara.oraculo_tema_numeros(null, v_chaves, v_unit, v_area);
    else
      select tema into v_tema from iara.oraculo_temas where palavras is not null and v_w ~ palavras order by ordem limit 1;
      if v_tema is not null then r := iara.oraculo_tema_numeros(v_tema, null, v_unit, v_area); end if;
    end if;
    if r ? 'numeros' then
      v_topico := r ->> 'topico';
      v_ferr := jsonb_build_array(jsonb_build_object('topico', v_topico, 'unidade', v_unit, 'area', v_area));
    end if;
  end if;

  if v_texto is null and v_topico is null and v_w ~ ' (acontec\w*|problemas?|urgenc\w*|urgentes?|criticos?|criticas?|prioridades?|novidades?) ' then
    x := iara.oraculo_situacoes_lista(rc.unidades, rc.cidade, 7);
    v_topico := 'situacoes';
  end if;

  if v_texto is null and v_topico is null then
    -- sobrou palavra que o Oráculo não conhece? Então "quantas crianças usam óculos" não vira o total de matrículas.
    v_conhecido := v_unit is not null or v_area is not null or btrim(regexp_replace(v_w,
      ' (?:quantos|quantas|quanto|qual|quais|que|alun[oa]s?|criancas?|estudantes?|temos|tem|ha|ja|existem|estao|esta|sao|e|matriculad[oa]s?|na|no|nas|nos|da|do|das|dos|de|em|a|o|as|os|um|uma|ao|com|para|por|favor|rede|cidade|maringa|municipio|municipal|publicas?|escolas?|cmeis?|unidades?|hoje|agora|atualmente|total|numero|todo|todas|todos|ola|oi|bom|boa|dia|me|diga|fale|conte|sobre|prefeito|prefeita|geral|resumo|panorama|como|visao|lista|nossa|nossas|nosso|nossos|educacao|ensino|quer|quero|queria|gostaria|saber|pode|poderia|informar|preciso|possui|possuem|tivemos|o que)(?= )',
      ' ', 'g')) = '';
    v_topico := case
      when v_w ~ v_bolsa then 'bolsa_familia'
      when v_w ~ 'creche|bercario' then 'creche'
      when v_w ~ 'fila|espera|aguard' then 'fila'
      when v_w ~ 'vaga' then 'vagas'
      when v_w ~ 'frequenc|presenc|falta|ausen' then 'frequencia'
      when v_w ~ 'ocorrenc|violenc' then 'ocorrencias'
      when v_w ~ 'professor|profissiona|servidor|educador|auxiliar|docente|funcionari' then 'profissionais'
      when v_w ~ 'transporte|onibus|rota|van|motorista' then 'transporte'
      when v_w ~ 'alfabetiz|leitura|escrita|sondagem|ler e escrever' then 'alfabetizacao'
      when v_w ~ 'busca ativa|evasao|abandono' then 'busca_ativa'
      when v_w ~ 'cadastr|documento' then 'cadastros'
      when v_w ~ 'matricul' then 'matriculas'
      when v_w ~ 'aluno|estudante|crianca' and v_conhecido then 'matriculas'
      when v_w ~ 'unidade|escola|cmei' and v_conhecido then 'unidades'
      when v_w ~ ' (hoje|agora|alertas?|pendencias?|situacao|situacoes) ' and v_conhecido then 'situacoes'
      when v_w ~ 'geral|resumo|panorama|como esta|rede' and v_conhecido then 'visao_geral'
    end;
    if v_topico = 'situacoes' then
      x := iara.oraculo_situacoes_lista(rc.unidades, rc.cidade, 7);
    elsif v_topico is not null then
      r := iara.oraculo_numeros(v_topico, v_unit, v_area);
      v_ferr := jsonb_build_array(jsonb_build_object('topico', v_topico, 'unidade', v_unit, 'area', v_area));
    end if;
  end if;

  if v_texto is null and v_topico = 'situacoes' then
    r := jsonb_build_object('topico', 'situacoes', 'recorte', rc.nome, 'unidade', v_unit, 'area', v_area, 'numeros', '[]'::jsonb, 'situacoes', x);
    v_ferr := jsonb_build_array(jsonb_build_object('topico', 'situacoes', 'unidade', v_unit, 'area', v_area));
    if jsonb_array_length(x) = 0 then
      v_texto := 'Em ' || rc.nome || ': nada pedindo atenção neste momento.';
    else
      select string_agg('• ' || coalesce((i ->> 'unidade') || ': ', '') || (i ->> 'texto') || ' (' || lower(i ->> 'area') || ')', E'\n') into v_texto
      from (select i from jsonb_array_elements(x) i limit 12) q;
      v_texto := 'Em ' || rc.nome || ', o que pede atenção agora:' || E'\n' || v_texto
                 || case when jsonb_array_length(x) > 12 then E'\n…e mais ' || (jsonb_array_length(x) - 12) || ' item(ns).' else '' end;
    end if;
  end if;

  if v_texto is null and v_topico is null then
    -- sem assunto conhecido: avisa e dá o resumo
    v_fora := true;
    r := iara.oraculo_numeros('visao_geral', v_unit, v_area);
    v_ferr := jsonb_build_array(jsonb_build_object('topico', 'visao_geral', 'unidade', v_unit, 'area', v_area));
  end if;

  if v_texto is null then
    v_partes := array(select iara.oraculo_numero_texto(i) from jsonb_array_elements(r -> 'numeros') with ordinality t(i, o) order by o);
    if jsonb_array_length(coalesce(r -> 'faltando', '[]')) > 0 then
      -- o que foi pedido depende de um dado que ainda não existe: diz o porquê e mostra o que há
      select string_agg(distinct f ->> 'rotulo', ' e ') || ': ainda não dá para responder. ' || string_agg(distinct f ->> 'motivo', ' ') into v_aviso
      from jsonb_array_elements(r -> 'faltando') f;
    end if;
    v_texto := case
      when v_aviso is not null and cardinality(v_partes) > 0 then v_aviso || E'\n\nO que existe hoje em ' || (r ->> 'recorte') || ' — ' || array_to_string(v_partes, '; ') || '.'
      when v_aviso is not null then v_aviso
      when cardinality(v_partes) = 0 then 'Em ' || (r ->> 'recorte') || ' — esse número não está disponível neste recorte (alguns só existem para a cidade inteira; outros dependem de dados ainda não lançados).'
      when cardinality(v_partes) >= 3 then
        case when v_fora then 'Não achei na pergunta um assunto que o Oráculo conheça. Segue o resumo da rede.' || E'\n' else '' end
        || 'Em ' || (r ->> 'recorte') || E':\n• ' || array_to_string(v_partes, E'\n• ')
        || case when v_fora then E'\n\n' || v_exemplos else '' end
      else
        case when v_fora then 'Não achei na pergunta um assunto que o Oráculo conheça. Segue o resumo da rede. ' else '' end
        || 'Em ' || (r ->> 'recorte') || ' — ' || array_to_string(v_partes, '; ') || '.'
        || case when v_fora then ' ' || v_exemplos else '' end
    end;
  end if;

  insert into iara.oraculo_perguntas (user_id, pergunta, canal, modo, resposta, ferramentas, is_demo)
  values (iara.current_user_id(), v_perg, coalesce(nullif(p ->> 'canal', ''), 'TEXTO'), 'REGRAS', v_texto, v_ferr, iara.demo_mode());
  return (case when r ? 'numeros' then r else jsonb_build_object('topico', null, 'recorte', rc.nome, 'numeros', '[]'::jsonb) end)
         || jsonb_build_object('pergunta', v_perg, 'resposta', v_texto, 'modo', 'REGRAS', 'fora', v_fora);
end $$;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('oraculo_detalhes', 'consulta', 'INTERNO', 'gestão', 'detalhes agregados do Oráculo do Prefeito', 'escritas na migração; nunca recebem texto de quem pergunta'),
  ('oraculo_fatos', 'consulta', 'INTERNO', 'gestão', 'números por período do Oráculo do Prefeito', 'escritas na migração; nunca recebem texto de quem pergunta')
on conflict (tabela, coluna) do nothing;

commit;
