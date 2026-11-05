-- IARA Educa — 097 · Oráculo abrangente: catálogo de indicadores de todos os módulos
-- O Oráculo passa a cobrir toda a operação: atendimento, vagas e ofertas, rematrícula e transferências, ausências, ocorrências por
-- tipo, proteção, desempenho, AEE, ponto, transporte, merenda e nutrição, almoxarifado e patrimônio, manutenção, biblioteca,
-- comunicação, qualidade dos dados e território. Cada indicador é uma consulta agregada (uma linha, um número) escrita aqui na
-- migração: nada vindo de fora vira SQL. Parâmetros de toda consulta: $1 = unidades do recorte, $2 = é a cidade inteira, $3 = hoje.
-- Sigilo: indicador que conta pessoas mostra 1 ou 2 como "menos de 3".
-- Após aplicar: reaplicar 20261003009900_privilegios.sql.
begin;

create table if not exists iara.oraculo_temas (
  tema text primary key,
  rotulo text not null,
  palavras text,                 -- palavras da pergunta que levam ao tema (regex sobre o texto normalizado)
  ordem smallint not null default 0
);
create table if not exists iara.oraculo_indicadores (
  chave text primary key,
  tema text not null references iara.oraculo_temas(tema) on delete cascade,
  rotulo text not null,
  consulta text not null,
  pessoas boolean not null default false,
  sufixo text,
  casas smallint not null default 0,
  palavras text,                 -- palavras que levam direto a este indicador
  palavras_ranking text,         -- palavras que o escolhem em "qual unidade tem mais…"
  pior text not null default 'maior' check (pior in ('maior', 'menor')),
  ordem smallint not null default 0
);
alter table iara.oraculo_temas enable row level security;
alter table iara.oraculo_indicadores enable row level security;

delete from iara.oraculo_indicadores;
delete from iara.oraculo_temas;

insert into iara.oraculo_temas (tema, rotulo, palavras, ordem) values
  ('rede', 'Rede e turmas', '\mocupac|\mlotad|\msuperlot|\msalas?\M', 1),
  ('atendimento', 'Atendimento às famílias', '\mprotocolo|\matendimento|\mreclama|\msolicitac|\mwhatsapp|\mconversa', 2),
  ('ofertas', 'Ofertas de vaga', '\moferta|\mbloquead|\msem atendimento', 3),
  ('rematricula', 'Rematrícula e transferências', '\mrematricul|\mrenov|\mtransferenc', 4),
  ('ausencias', 'Ausências e contato com as famílias', '\mausencia|\mesclarecimento|\minjustific|\mafastamento', 5),
  ('ocorrencias_tipo', 'Ocorrências por tipo', '\mbullying|\macidente|\melogio|\mconflito|\mbriga|\mpertence|\mindisciplina', 6),
  ('protecao', 'Proteção à criança', '\mconselho tutelar|\mencaminhament|\mrede de protecao|\mrede de apoio|\mguarda\M|\mmedida protetiva', 7),
  ('desempenho', 'Desempenho escolar', '\mnotas?\M|\mdesempenho|\mboletim|\mreprov|\maprov|\mrecuperacao|\mconselhos? de classe|\mresultado|\mintervencao|\maprendizagem', 8),
  ('aee', 'Educação especial (AEE)', '\maee\M|\meducacao especial|\minclus|\mdeficien|\msala de recursos|\matendimento especializado', 9),
  ('ponto', 'Ponto dos profissionais', '\mponto\M|\mmarcac|\mmarcaram|\mlicenca|\mafastad', 10),
  ('transporte_det', 'Frota e viagens', '\mvistoria|\mveiculo|\mfrota|\matraso|\mrota nao|\mrotas nao|\mnao executad', 11),
  ('nutricao', 'Merenda e nutrição', '\mmerenda|\mrefeic|\mcardapio|\mnutric|\maliment|\mobesid|\msobrepeso|\mdesnutri|\mbaixo peso|\mimc\M|\malergi|\mrestric', 12),
  ('almoxarifado', 'Almoxarifado e patrimônio', '\malmoxarif|\mestoque|\mmateria(l|is)\M|\mpedidos? de|\mpatrimonio|\minventario|\mvencendo|\mcompras?\M|\muniforme', 13),
  ('manutencao', 'Manutenção e infraestrutura', '\mmanutenc|\mreforma|\mobras?\M|\minfraestrutura|\mpredio|\mtelhado|\mbanheiro|\meletric|\mhidraul|\mgoteira', 14),
  ('biblioteca', 'Biblioteca', '\mbibliotec|\mlivros?\M|\memprestim', 15),
  ('comunicacao', 'Comunicação e eventos', '\mmural|\mcomunicado|\meventos?\M|\mcertificado|\mformacoes?\M', 16),
  ('qualidade', 'Qualidade dos dados e suporte', '\mqualidade d|\mpendencias? de dado|\msuporte', 17),
  ('territorio', 'Território (Censo)', '\mcenso|\mmoradores|\mpopulacao|\mhabitantes|\mdomicilios?\M', 18),
  ('base', 'Principais números', null, 90);

insert into iara.oraculo_indicadores (chave, tema, rotulo, consulta, pessoas, sufixo, casas, palavras, palavras_ranking, pior, ordem) values
-- rede
('rede.ocupacao', 'rede', 'Ocupação das turmas', $q$select round(100.0 * sum(active_enrollments_count) / nullif(sum(authorized_capacity), 0), 1) from iara.classes where status = 'ATIVA' and unit_id = any ($1)$q$, false, '%', 1, null, '\mocupac|\mlotad|\msuperlot', 'maior', 1),
('rede.turmas', 'rede', 'Turmas ativas', $q$select count(*) from iara.classes where status = 'ATIVA' and unit_id = any ($1)$q$, false, null, 0, null, '\mturmas?\M', 'maior', 2),
('rede.integral', 'rede', 'Turmas em tempo integral', $q$select count(*) from iara.classes where status = 'ATIVA' and shift = 'INTEGRAL' and unit_id = any ($1)$q$, false, null, 0, '\mintegral', '\mintegral', 'maior', 3),
('rede.salas', 'rede', 'Salas em uso', $q$select count(*) from iara.salas where ativa and unit_id = any ($1)$q$, false, null, 0, null, '\msalas?\M', 'maior', 4),
-- atendimento
('atend.abertos', 'atendimento', 'Protocolos em aberto', $q$select count(*) from iara.service_cases where status not in ('ENCERRADO', 'MATRICULA_CONCLUIDA') and (unit_id = any ($1) or $2)$q$, false, null, 0, null, '\mprotocolo|\matendimento', 'maior', 1),
('atend.vencidos', 'atendimento', 'Protocolos com prazo vencido', $q$select count(*) from iara.service_cases where status not in ('ENCERRADO', 'MATRICULA_CONCLUIDA') and sla_due_at < now() and (unit_id = any ($1) or $2)$q$, false, null, 0, '\mvencid|\matrasad', '\mvencid|\matrasad', 'maior', 2),
('atend.urgentes', 'atendimento', 'Protocolos urgentes ou de alta prioridade', $q$select count(*) from iara.service_cases where status not in ('ENCERRADO', 'MATRICULA_CONCLUIDA') and priority in ('ALTA', 'URGENTE') and (unit_id = any ($1) or $2)$q$, false, null, 0, null, null, 'maior', 3),
('atend.reclamacoes', 'atendimento', 'Reclamações em aberto', $q$select count(*) from iara.service_cases where status not in ('ENCERRADO', 'MATRICULA_CONCLUIDA') and case_type = 'RECLAMACAO' and (unit_id = any ($1) or $2)$q$, false, null, 0, '\mreclama', '\mreclama', 'maior', 4),
('atend.tempo', 'atendimento', 'Tempo médio de resolução (120 dias)', $q$select round(avg(extract(epoch from closed_at - opened_at) / 86400)::numeric, 1) from iara.service_cases where closed_at >= now() - interval '120 days' and (unit_id = any ($1) or $2)$q$, false, ' dias', 1, '\mtempo medio|\mquanto tempo|\mdemora', null, 'maior', 5),
('atend.humano', 'atendimento', 'Famílias aguardando atendimento humano', $q$select count(*) from iara.conversations where state = 'HUMAN_PENDING' and (unit_id = any ($1) or $2)$q$, false, null, 0, '\mwhatsapp|\mconversa', null, 'maior', 6),
-- ofertas
('oferta.abertas', 'ofertas', 'Ofertas de vaga aguardando resposta', $q$select count(*) from iara.vacancy_offers where status = 'OFFERED' and unit_id = any ($1)$q$, false, null, 0, null, '\moferta', 'maior', 1),
('oferta.vencendo', 'ofertas', 'Ofertas que vencem em 24 horas', $q$select count(*) from iara.vacancy_offers where status = 'OFFERED' and expires_at < now() + interval '1 day' and unit_id = any ($1)$q$, false, null, 0, '\mvenc', null, 'maior', 2),
('oferta.recusadas', 'ofertas', 'Ofertas recusadas (90 dias)', $q$select count(*) from iara.vacancy_offers where status = 'DECLINED' and offered_at >= now() - interval '90 days' and unit_id = any ($1)$q$, false, null, 0, '\mrecusad', null, 'maior', 3),
('oferta.bloqueadas', 'ofertas', 'Vagas bloqueadas', $q$select coalesce(sum(blocked_seats_count), 0) from iara.classes where status = 'ATIVA' and unit_id = any ($1)$q$, false, null, 0, '\mbloquead', '\mbloquead', 'maior', 4),
('oferta.sem_atendimento', 'ofertas', 'Crianças na fila sem nenhum atendimento', $q$select count(*) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED') and demand_category = 'SEM_ATENDIMENTO' and preferred_unit_id = any ($1)$q$, true, null, 0, '\msem atendimento', null, 'maior', 5),
-- rematrícula e transferências
('remat.pendentes', 'rematricula', 'Rematrículas pendentes', $q$select count(*) from iara.rematriculas where situacao = 'PENDENTE' and unit_origem = any ($1) and ano = (select max(ano) from iara.rematriculas)$q$, true, null, 0, null, '\mrematricul', 'maior', 1),
('remat.confirmadas', 'rematricula', 'Rematrículas confirmadas', $q$select count(*) from iara.rematriculas where situacao = 'CONFIRMADA' and unit_origem = any ($1) and ano = (select max(ano) from iara.rematriculas)$q$, true, null, 0, null, null, 'maior', 2),
('remat.nao_renovadas', 'rematricula', 'Não renovaram', $q$select count(*) from iara.rematriculas where situacao = 'NAO_RENOVADA' and unit_origem = any ($1) and ano = (select max(ano) from iara.rematriculas)$q$, true, null, 0, '\mnao renov', null, 'maior', 3),
('remat.outra_escola', 'rematricula', 'Foram para outra escola', $q$select count(*) from iara.rematriculas where situacao = 'OUTRA_ESCOLA' and unit_origem = any ($1) and ano = (select max(ano) from iara.rematriculas)$q$, true, null, 0, null, null, 'maior', 4),
('remat.transferencias', 'rematricula', 'Transferências em andamento', $q$select count(*) from iara.transferencias where situacao in ('FILA', 'AGUARDANDO_DESTINO') and (unit_origem = any ($1) or unit_destino = any ($1))$q$, true, null, 0, '\mtransferenc', '\mtransferenc', 'maior', 5),
-- ausências
('aus.aguardando', 'ausencias', 'Ausências aguardando esclarecimento da família', $q$select count(*) from iara.frequencia_ausencias where situacao = 'AGUARDANDO_ESCLARECIMENTO' and unit_id = any ($1)$q$, false, null, 0, '\mesclarecimento', '\mesclarecimento', 'maior', 1),
('aus.injustificadas', 'ausencias', 'Ausências injustificadas', $q$select count(*) from iara.frequencia_ausencias where situacao = 'INJUSTIFICADA' and unit_id = any ($1)$q$, false, null, 0, '\minjustific', '\minjustific', 'maior', 2),
('aus.risco', 'ausencias', 'Ausências marcadas como risco', $q$select count(*) from iara.frequencia_ausencias where risco and situacao not in ('JUSTIFICATIVA_ACEITA', 'AFASTAMENTO') and unit_id = any ($1)$q$, false, null, 0, null, null, 'maior', 3),
('aus.afastados', 'ausencias', 'Alunos afastados agora (médico ou legal)', $q$select count(*) from iara.frequencia_afastamentos a join iara.enrollments e on e.student_id = a.student_id and e.status = 'ACTIVE' where a.inicio <= $3 and coalesce(a.fim, $3) >= $3 and e.unit_id = any ($1)$q$, true, null, 0, '\mafastamento', null, 'maior', 4),
('aus.contato_falha', 'ausencias', 'Avisos às famílias que falharam', $q$select count(*) from iara.frequencia_contatos where status = 'FALHA' and unit_id = any ($1)$q$, false, null, 0, '\maviso|\mcontato', null, 'maior', 5),
-- ocorrências por tipo (90 dias)
('ocor.bullying', 'ocorrencias_tipo', 'Bullying (90 dias)', $q$select count(*) from iara.ocorrencias where tipo = 'BULLYING' and ocorrida_em >= now() - interval '90 days' and unit_id = any ($1)$q$, false, null, 0, '\mbullying', '\mbullying', 'maior', 1),
('ocor.acidente', 'ocorrencias_tipo', 'Acidentes (90 dias)', $q$select count(*) from iara.ocorrencias where tipo = 'ACIDENTE' and ocorrida_em >= now() - interval '90 days' and unit_id = any ($1)$q$, false, null, 0, '\macidente', '\macidente', 'maior', 2),
('ocor.conflito', 'ocorrencias_tipo', 'Conflitos (90 dias)', $q$select count(*) from iara.ocorrencias where tipo = 'CONFLITO' and ocorrida_em >= now() - interval '90 days' and unit_id = any ($1)$q$, false, null, 0, '\mconflito|\mbriga', '\mconflito|\mbriga', 'maior', 3),
('ocor.comportamento', 'ocorrencias_tipo', 'Comportamento (90 dias)', $q$select count(*) from iara.ocorrencias where tipo = 'COMPORTAMENTO' and ocorrida_em >= now() - interval '90 days' and unit_id = any ($1)$q$, false, null, 0, '\mindisciplina|\mcomportamento', null, 'maior', 4),
('ocor.saude', 'ocorrencias_tipo', 'Saúde (90 dias)', $q$select count(*) from iara.ocorrencias where tipo = 'SAUDE' and ocorrida_em >= now() - interval '90 days' and unit_id = any ($1)$q$, false, null, 0, null, null, 'maior', 5),
('ocor.elogios', 'ocorrencias_tipo', 'Elogios (90 dias)', $q$select count(*) from iara.ocorrencias where tipo = 'ELOGIO' and ocorrida_em >= now() - interval '90 days' and unit_id = any ($1)$q$, false, null, 0, '\melogio', '\melogio', 'maior', 6),
-- proteção
('prot.ct_aguardando', 'protecao', 'Encaminhamentos ao Conselho Tutelar aguardando aprovação', $q$select count(*) from iara.encaminhamentos where tipo = 'CONSELHO_TUTELAR' and situacao = 'AGUARDANDO_APROVACAO' and unit_id = any ($1)$q$, true, null, 0, null, '\mconselho tutelar', 'maior', 1),
('prot.ct_sem_retorno', 'protecao', 'Encaminhamentos enviados, sem retorno', $q$select count(*) from iara.encaminhamentos where situacao = 'ENVIADO' and retorno_em is null and unit_id = any ($1)$q$, true, null, 0, '\mretorno', null, 'maior', 2),
('prot.rede_apoio', 'protecao', 'Encaminhamentos à rede de apoio', $q$select count(*) from iara.encaminhamentos where tipo = 'REDE_APOIO' and unit_id = any ($1)$q$, true, null, 0, '\mrede de apoio', null, 'maior', 3),
('prot.guarda', 'protecao', 'Restrições de guarda ativas', $q$select count(*) from iara.guarda_restricoes where situacao = 'ATIVA' and unit_id = any ($1)$q$, true, null, 0, '\mguarda\M|\mmedida protetiva', null, 'maior', 4),
-- desempenho
('des.media', 'desempenho', 'Média das notas no ano', $q$select round(avg(n.nota), 1) from iara.notas n join iara.classes c on c.id = n.class_id where n.ano = extract(year from $3)::int and c.unit_id = any ($1)$q$, false, null, 1, '\mmedia', '\mnotas?\M|\mdesempenho|\mmedia', 'menor', 1),
('des.abaixo6', 'desempenho', 'Notas abaixo de 6', $q$select round(100.0 * count(*) filter (where n.nota < 6) / nullif(count(*), 0), 1) from iara.notas n join iara.classes c on c.id = n.class_id where n.ano = extract(year from $3)::int and c.unit_id = any ($1)$q$, false, '%', 1, '\mabaixo de 6|\mnotas baixas', null, 'maior', 2),
('des.intervencao', 'desempenho', 'Planos de intervenção ativos', $q$select count(*) from iara.planos_intervencao where situacao = 'ATIVO' and unit_id = any ($1)$q$, true, null, 0, '\mintervencao', '\mintervencao', 'maior', 3),
('des.aprov_conselho', 'desempenho', 'Aprovados pelo conselho (último ano fechado)', $q$select count(*) from iara.resultados_finais where situacao = 'APROVADO_CONSELHO' and unit_id = any ($1) and ano = (select max(ano) from iara.resultados_finais)$q$, true, null, 0, '\mconselhos? de classe', null, 'maior', 4),
('des.conselhos', 'desempenho', 'Conselhos de classe concluídos no ano', $q$select count(*) from iara.conselhos_classe where situacao = 'CONCLUIDO' and ano = extract(year from $3)::int and unit_id = any ($1)$q$, false, null, 0, null, null, 'maior', 5),
-- AEE
('aee.ativos', 'aee', 'Alunos com plano de AEE ativo', $q$select count(*) from iara.aee_planos where situacao = 'ATIVO' and unit_id = any ($1)$q$, true, null, 0, null, '\maee\M|\meducacao especial|\minclus|\mdeficien', 'maior', 1),
('aee.elaboracao', 'aee', 'Planos de AEE em elaboração', $q$select count(*) from iara.aee_planos where situacao = 'EM_ELABORACAO' and unit_id = any ($1)$q$, true, null, 0, null, null, 'maior', 2),
('aee.revisao', 'aee', 'Planos de AEE em revisão', $q$select count(*) from iara.aee_planos where situacao = 'EM_REVISAO' and unit_id = any ($1)$q$, true, null, 0, null, null, 'maior', 3),
('aee.atend30', 'aee', 'Atendimentos de AEE (30 dias)', $q$select count(*) from iara.aee_atendimentos a join iara.aee_planos p on p.id = a.plano_id where a.data >= $3 - 30 and p.unit_id = any ($1)$q$, false, null, 0, null, null, 'maior', 4),
-- ponto
('ponto.marcaram', 'ponto', 'Profissionais que marcaram o ponto hoje', $q$select case when exists (select 1 from iara.ponto_marcacoes where data = $3) then (select count(distinct staff_id) from iara.ponto_marcacoes where data = $3 and unit_id = any ($1)) end$q$, true, null, 0, '\mmarcaram|\mbateram', null, 'menor', 1),
('ponto.licenca', 'ponto', 'Profissionais em licença ou afastados', $q$select count(*) from iara.staff where situacao in ('LICENCA', 'AFASTADO') and unit_id = any ($1)$q$, true, null, 0, '\mlicenca|\mafastad', '\mlicenca|\mafastad', 'maior', 2),
('ponto.fora7', 'ponto', 'Marcações longe da unidade (7 dias)', $q$select count(*) from iara.ponto_marcacoes where fora_da_unidade and data >= $3 - 7 and unit_id = any ($1)$q$, false, null, 0, '\mlonge|\mfora da unidade', null, 'maior', 3),
('ponto.justificativas', 'ponto', 'Justificativas de ponto aguardando a direção', $q$select count(*) from iara.ponto_justificativas where situacao = 'PENDENTE' and unit_id = any ($1)$q$, true, null, 0, '\mjustificativas? de ponto', null, 'maior', 4),
-- transporte
('frota.veiculos', 'transporte_det', 'Veículos em operação', $q$select case when $2 then (select count(*) from iara.transporte_veiculos where situacao = 'ATIVO') end$q$, false, null, 0, '\mveiculo|\mfrota', null, 'maior', 1),
('frota.vistoria', 'transporte_det', 'Veículos com vistoria vencida', $q$select case when $2 then (select count(*) from iara.transporte_veiculos where situacao <> 'MANUTENCAO' and vistoria_validade < $3) end$q$, false, null, 0, '\mvistoria', null, 'maior', 2),
('frota.atrasos', 'transporte_det', 'Atrasos do transporte (30 dias)', $q$select count(*) from iara.transporte_ocorrencias o join iara.transporte_rotas r on r.id = o.rota_id where o.tipo = 'ATRASO' and o.data >= $3 - 30 and r.unit_id = any ($1)$q$, false, null, 0, '\matraso', '\matraso', 'maior', 3),
('frota.nao_executadas', 'transporte_det', 'Rotas não executadas (30 dias)', $q$select count(*) from iara.transporte_ocorrencias o join iara.transporte_rotas r on r.id = o.rota_id where o.tipo = 'ROTA_NAO_EXECUTADA' and o.data >= $3 - 30 and r.unit_id = any ($1)$q$, false, null, 0, '\mnao executad|\mrotas? nao', '\mnao executad', 'maior', 4),
-- merenda e nutrição
('nut.refeicoes7', 'nutricao', 'Refeições servidas (7 dias)', $q$select coalesce(sum(quantidade), 0) from iara.refeicoes_servidas where data >= $3 - 7 and unit_id = any ($1)$q$, false, null, 0, '\mrefeic', '\mmerenda|\mrefeic', 'maior', 1),
('nut.adaptadas30', 'nutricao', 'Refeições adaptadas (30 dias)', $q$select coalesce(sum(adaptadas), 0) from iara.refeicoes_servidas where data >= $3 - 30 and unit_id = any ($1)$q$, false, null, 0, '\madaptad', null, 'maior', 2),
('nut.restricoes', 'nutricao', 'Alunos com restrição alimentar validada', $q$select count(distinct r.student_id) from iara.aluno_restricoes r join iara.enrollments e on e.student_id = r.student_id and e.status = 'ACTIVE' where r.situacao = 'VALIDADA' and e.unit_id = any ($1)$q$, true, null, 0, '\mrestric|\malergi', '\mrestric|\malergi', 'maior', 3),
('nut.restricoes_ag', 'nutricao', 'Restrições alimentares aguardando validação', $q$select count(distinct r.student_id) from iara.aluno_restricoes r join iara.enrollments e on e.student_id = r.student_id and e.status = 'ACTIVE' where r.situacao = 'INFORMADA' and e.unit_id = any ($1)$q$, true, null, 0, null, null, 'maior', 4),
('nut.excesso', 'nutricao', 'Crianças com excesso de peso (última medida)', $q$select case when count(zscore) > 0 then count(*) filter (where zscore > 2) end from (select distinct on (student_id) zscore from iara.antropometria where unit_id = any ($1) order by student_id, data desc) q$q$, true, null, 0, '\mobesid|\msobrepeso|\mexcesso de peso', '\mobesid|\msobrepeso|\mexcesso de peso', 'maior', 5),
('nut.medidas', 'nutricao', 'Crianças com peso e altura medidos', $q$select count(distinct student_id) from iara.antropometria where unit_id = any ($1)$q$, true, null, 0, '\mmedid[ao]s?\M|\mantropometr|\mpeso e altura', null, 'maior', 7),
('nut.imc', 'nutricao', 'IMC médio (última medida)', $q$select round(avg(imc), 1) from (select distinct on (student_id) imc from iara.antropometria where unit_id = any ($1) order by student_id, data desc) q$q$, false, null, 1, '\mimc\M', null, 'maior', 8),
('nut.baixo', 'nutricao', 'Crianças com baixo peso (última medida)', $q$select case when count(zscore) > 0 then count(*) filter (where zscore < -2) end from (select distinct on (student_id) zscore from iara.antropometria where unit_id = any ($1) order by student_id, data desc) q$q$, true, null, 0, '\mdesnutri|\mbaixo peso|\mmagreza', '\mdesnutri|\mbaixo peso', 'maior', 6),
-- almoxarifado e patrimônio
('alm.abaixo', 'almoxarifado', 'Itens abaixo do estoque mínimo', $q$select count(*) from iara.materiais where ativo and quantidade < minimo and unit_id = any ($1)$q$, false, null, 0, '\mabaixo do minimo|\mfalta de', '\mestoque|\mmateria(l|is)\M', 'maior', 1),
('alm.pedidos', 'almoxarifado', 'Pedidos em andamento', $q$select count(*) from iara.pedidos where situacao in ('ENVIADO', 'APROVADO', 'EM_TRANSPORTE') and unit_id = any ($1)$q$, false, null, 0, '\mpedidos?\M|\mcompras?\M', '\mpedidos?\M', 'maior', 2),
('alm.vencendo', 'almoxarifado', 'Lotes que vencem em 15 dias', $q$select count(*) from iara.estoque_lotes l join iara.materiais m on m.id = l.material_id where l.quantidade > 0 and l.validade between $3 and $3 + 15 and m.unit_id = any ($1)$q$, false, null, 0, '\mvencendo|\mvalidade', null, 'maior', 3),
('alm.vencidos', 'almoxarifado', 'Lotes vencidos com saldo', $q$select count(*) from iara.estoque_lotes l join iara.materiais m on m.id = l.material_id where l.quantidade > 0 and l.validade < $3 and m.unit_id = any ($1)$q$, false, null, 0, '\mvencidos?\M', null, 'maior', 4),
('alm.inventarios', 'almoxarifado', 'Inventários em aberto', $q$select count(*) from iara.inventarios where situacao = 'ABERTO' and unit_id = any ($1)$q$, false, null, 0, '\minventario', null, 'maior', 5),
('alm.baixas', 'almoxarifado', 'Baixas de patrimônio solicitadas', $q$select count(*) from iara.patrimonio_eventos where tipo = 'BAIXA_SOLICITADA' and origem_unit = any ($1)$q$, false, null, 0, '\mpatrimonio', null, 'maior', 6),
-- manutenção
('man.abertos', 'manutencao', 'Chamados de manutenção em aberto', $q$select count(*) from iara.manutencao_chamados where situacao not in ('VALIDADO', 'CONCLUIDO', 'CANCELADO') and unit_id = any ($1)$q$, false, null, 0, '\mchamados? de manutenc', '\mmanutenc|\mchamado|\mreforma|\mobras?\M', 'maior', 1),
('man.urgentes', 'manutencao', 'Chamados urgentes', $q$select count(*) from iara.manutencao_chamados where situacao not in ('VALIDADO', 'CONCLUIDO', 'CANCELADO') and prioridade = 'URGENTE' and unit_id = any ($1)$q$, false, null, 0, null, null, 'maior', 2),
('man.seguranca', 'manutencao', 'Chamados que afetam a segurança', $q$select count(*) from iara.manutencao_chamados where situacao not in ('VALIDADO', 'CONCLUIDO', 'CANCELADO') and afeta_seguranca and unit_id = any ($1)$q$, false, null, 0, '\mseguranca', null, 'maior', 3),
('man.vencidos', 'manutencao', 'Chamados com prazo vencido', $q$select count(*) from iara.manutencao_chamados where situacao not in ('VALIDADO', 'CONCLUIDO', 'CANCELADO') and prazo < now() and unit_id = any ($1)$q$, false, null, 0, null, null, 'maior', 4),
('man.custo', 'manutencao', 'Custo de manutenção no ano (R$)', $q$select coalesce(sum(custo_final), 0) from iara.manutencao_chamados where extract(year from aberto_em) = extract(year from $3) and unit_id = any ($1)$q$, false, null, 0, '\mcusto|\mgasto', '\mcusto|\mgasto', 'maior', 5),
-- biblioteca
('bib.abertos', 'biblioteca', 'Livros emprestados agora', $q$select count(*) from iara.biblioteca_emprestimos where devolvido_em is null and unit_id = any ($1)$q$, false, null, 0, null, '\mbibliotec|\mlivros?\M|\memprestim', 'maior', 1),
('bib.atrasados', 'biblioteca', 'Empréstimos em atraso', $q$select count(*) from iara.biblioteca_emprestimos where devolvido_em is null and prevista < $3 and unit_id = any ($1)$q$, false, null, 0, '\matrasados?\M', null, 'maior', 2),
('bib.mes', 'biblioteca', 'Empréstimos (30 dias)', $q$select count(*) from iara.biblioteca_emprestimos where retirada_em >= $3 - 30 and unit_id = any ($1)$q$, false, null, 0, null, null, 'maior', 3),
-- comunicação e eventos
('com.mural', 'comunicacao', 'Publicações no mural (30 dias)', $q$select count(*) from iara.mural_publicacoes where situacao = 'PUBLICADO' and publicado_em >= $3 - 30 and (unit_id = any ($1) or $2)$q$, false, null, 0, '\mmural|\mcomunicado', null, 'maior', 1),
('com.inscricoes', 'comunicacao', 'Eventos com inscrições abertas', $q$select count(*) from iara.eventos where situacao = 'INSCRICOES' and (unit_id = any ($1) or $2)$q$, false, null, 0, null, null, 'maior', 2),
('com.eventos', 'comunicacao', 'Eventos concluídos no ano', $q$select count(*) from iara.eventos where situacao = 'CONCLUIDO' and extract(year from inicio) = extract(year from $3) and (unit_id = any ($1) or $2)$q$, false, null, 0, null, null, 'maior', 3),
('com.certificados', 'comunicacao', 'Certificados emitidos', $q$select count(*) from iara.evento_participantes p join iara.eventos e on e.id = p.evento_id where p.certificado_emitido_em is not null and (e.unit_id = any ($1) or $2)$q$, false, null, 0, '\mcertificado', null, 'maior', 4),
-- qualidade e suporte
('qual.pendencias', 'qualidade', 'Pendências de qualidade dos dados', $q$select count(*) from iara.data_quality_issues where status = 'ABERTA' and (unit_id = any ($1) or $2)$q$, false, null, 0, '\mqualidade d|\mpendencias? de dado', null, 'maior', 1),
('qual.suporte', 'qualidade', 'Chamados de suporte técnico em aberto', $q$select count(*) from iara.suporte_chamados where situacao in ('ABERTO', 'EM_ATENDIMENTO', 'AGUARDANDO_SOLICITANTE') and (unit_id = any ($1) or $2)$q$, false, null, 0, '\msuporte', null, 'maior', 2),
-- território (só a cidade: o Censo vem por área, não por unidade)
('ter.moradores', 'territorio', 'Moradores (Censo 2022)', $q$select case when $2 then (select sum(pessoas) from iara.setores_censitarios) end$q$, false, null, 0, '\mmoradores|\mpopulacao|\mhabitantes', null, 'maior', 1),
('ter.domicilios', 'territorio', 'Domicílios (Censo 2022)', $q$select case when $2 then (select sum(domicilios) from iara.setores_censitarios) end$q$, false, null, 0, '\mdomicilios?\M', null, 'maior', 2),
('ter.criancas', 'territorio', 'Crianças de 0 a 4 anos (Censo 2022)', $q$select case when $2 then (select sum(criancas_0a4) from iara.setores_censitarios) end$q$, false, null, 0, '\mcriancas de 0', null, 'maior', 3),
-- principais números, para comparar unidades e regiões ("qual escola tem mais…")
('base.matriculas', 'base', 'Alunos matriculados', $q$select count(*) from iara.enrollments where status = 'ACTIVE' and unit_id = any ($1)$q$, false, null, 0, null, '\malunos?\M|\mmatricul|\mestudantes?\M', 'maior', 1),
('base.fila', 'base', 'Crianças na fila de espera', $q$select count(*) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED') and preferred_unit_id = any ($1)$q$, true, null, 0, null, '\mfila|\mespera', 'maior', 2),
('base.fila_creche', 'base', 'Crianças na fila da creche', $q$select count(*) from iara.waiting_list_entries where status in ('WAITING', 'OFFERED') and grade_level_id = 1 and preferred_unit_id = any ($1)$q$, true, null, 0, null, '\mcreche', 'maior', 3),
('base.vagas', 'base', 'Vagas que podem ser oferecidas', $q$select coalesce(sum(offerable_vacancies_count), 0) from iara.classes where unit_id = any ($1)$q$, false, null, 0, null, '\mvagas?\M', 'maior', 4),
('base.ocorrencias', 'base', 'Ocorrências (90 dias)', $q$select count(*) from iara.ocorrencias where ocorrida_em >= now() - interval '90 days' and tipo <> 'ELOGIO' and unit_id = any ($1)$q$, false, null, 0, null, '\mocorrenc|\mviolenc', 'maior', 5),
('base.presenca', 'base', 'Presença nos últimos 30 dias', $q$with reg as (select r.id, r.class_id from iara.frequencia_registros r join iara.classes c on c.id = r.class_id where r.data >= $3 - 30 and c.unit_id = any ($1)), m as (select e.class_id, count(*) n from iara.enrollments e where e.status = 'ACTIVE' and e.unit_id = any ($1) group by 1), p as (select sum(m.n) n from reg join m on m.class_id = reg.class_id), f as (select count(*) n from iara.frequencia_faltas fa join reg on reg.id = fa.registro_id) select round(100.0 - 100.0 * f.n / nullif(p.n, 0), 1) from p, f$q$, false, '%', 1, null, '\mpresenc|\mfrequenc|\mfaltas?\M', 'menor', 6),
('base.alertas', 'base', 'Alunos em alerta de frequência', $q$select count(*) from iara.frequencia_alertas where situacao <> 'RESOLVIDO' and unit_id = any ($1)$q$, true, null, 0, null, '\malerta', 'maior', 7),
('base.busca', 'base', 'Casos de busca ativa abertos', $q$select count(*) from iara.busca_ativa_casos where situacao in ('ABERTO', 'EM_ACOMPANHAMENTO') and unit_id = any ($1)$q$, true, null, 0, null, '\mbusca ativa|\mevasao|\mabandono', 'maior', 8),
('base.profissionais', 'base', 'Profissionais', $q$select count(*) from iara.staff where unit_id = any ($1)$q$, false, null, 0, null, '\mprofessor|\mprofission|\mservidor|\meducador', 'maior', 9),
('base.transportados', 'base', 'Alunos no transporte escolar', $q$select count(*) from iara.transporte_alunos ta join iara.transporte_rotas r on r.id = ta.rota_id where ta.fim is null and r.unit_id = any ($1)$q$, true, null, 0, null, '\mtransporte|\monibus', 'maior', 10);

-- valor de um indicador num recorte. A consulta vem só do catálogo acima (nunca de quem pergunta).
create or replace function iara.oraculo_valor(p_consulta text, p_units integer[], p_cidade boolean) returns numeric
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v numeric;
begin
  execute 'select (' || p_consulta || ')::numeric' into v using p_units, p_cidade, iara.hoje_local();
  return v;
end $$;

-- um número pronto para mostrar: rótulo, valor e sigilo (indicador de pessoas com 1 ou 2 vira "menos de 3")
create or replace function iara.oraculo_numero(i iara.oraculo_indicadores, p_units integer[], p_cidade boolean) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v numeric := iara.oraculo_valor(i.consulta, p_units, p_cidade);
begin
  if i.pessoas and v between 1 and 2 then
    return jsonb_build_object('chave', i.chave, 'rotulo', i.rotulo, 'valor', null, 'sigilo', true);
  end if;
  return jsonb_build_object('chave', i.chave, 'rotulo', i.rotulo, 'valor', v) || case when i.sufixo is not null then jsonb_build_object('sufixo', i.sufixo) else '{}'::jsonb end
         || case when i.casas > 0 then jsonb_build_object('casas', i.casas) else '{}'::jsonb end;
end $$;

-- recorte da consulta: unidades, se é a cidade inteira e o nome
create or replace function iara.oraculo_recorte_de(p_unit integer, p_area integer, out unidades integer[], out cidade boolean, out nome text)
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if p_unit is not null then
    unidades := array[p_unit]; cidade := false;
    select short_name into nome from iara.education_units where id = p_unit;
  elsif p_area is not null then
    unidades := array(select id from iara.education_units where macro_territory_id = p_area); cidade := false;
    select name into nome from iara.territories where id = p_area;
  else
    unidades := array(select id from iara.education_units); cidade := true; nome := 'Maringá';
  end if;
end $$;

-- os números de um tema do catálogo (ou de uma lista de indicadores), no mesmo formato de iara.oraculo_numeros
create or replace function iara.oraculo_tema_numeros(p_tema text, p_chaves text[], p_unit integer, p_area integer) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  rc record := iara.oraculo_recorte_de(p_unit, p_area);
  i iara.oraculo_indicadores;
  n jsonb := '[]';
  x jsonb;
begin
  for i in select * from iara.oraculo_indicadores
           where (p_chaves is not null and chave = any (p_chaves)) or (p_chaves is null and tema = p_tema) order by ordem loop
    x := iara.oraculo_numero(i, rc.unidades, rc.cidade);
    -- indicador só da cidade pedido numa unidade: não entra
    if x ->> 'valor' is not null or (x ->> 'sigilo') is not null then n := n || x; end if;
  end loop;
  return jsonb_build_object('topico', coalesce(p_tema, (select tema from iara.oraculo_indicadores where chave = p_chaves[1])), 'recorte', rc.nome,
    'unidade', p_unit, 'area', p_area, 'numeros', n,
    'nota', 'Dados da demonstração do IARA Educa. Só números agregados; contagens de 1 ou 2 pessoas aparecem como "menos de 3".');
end $$;

-- unidade e região a partir de parâmetros da ferramenta (id, nome ou "AP 017")
create or replace function iara.oraculo_args(p jsonb, out p_unit integer, out p_area integer)
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  if coalesce(p ->> 'unidade', '') ~ '^\d+$' then
    p_unit := (p ->> 'unidade')::int;
  elsif coalesce(p ->> 'unidade', '') <> '' then
    p_unit := (iara.oraculo_recorte(p ->> 'unidade') ->> 'unidade')::int;
  end if;
  if coalesce(p ->> 'regiao', '') ~ '^\d+$' then
    p_area := (p ->> 'regiao')::int;
  elsif coalesce(p ->> 'regiao', '') <> '' then
    p_area := coalesce((iara.oraculo_recorte(p ->> 'regiao') ->> 'area')::int,
                       (select id from iara.territories where kind = 'AREA_PONDERACAO' and iara.norm(name) like '%' || iara.norm(p ->> 'regiao') || '%' limit 1));
  end if;
end $$;

-- ferramenta do Oráculo e do MCP: um tópico (os de sempre ou um tema do catálogo) ou uma lista de indicadores
create or replace function api.oraculo_dados(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  a record := iara.oraculo_args(p);
  v_top text := coalesce(nullif(p ->> 'topico', ''), 'visao_geral');
  v_ind text[] := array(select jsonb_array_elements_text(case when jsonb_typeof(p -> 'indicadores') = 'array' then p -> 'indicadores' else '[]' end));
begin
  perform iara.require_perm('oraculo.prefeito');
  if cardinality(v_ind) > 0 then
    return iara.oraculo_tema_numeros(null, v_ind, a.p_unit, a.p_area);
  end if;
  if exists (select 1 from iara.oraculo_temas where tema = v_top) then
    return iara.oraculo_tema_numeros(v_top, null, a.p_unit, a.p_area);
  end if;
  return iara.oraculo_numeros(v_top, a.p_unit, a.p_area);
end $$;

-- o que o Oráculo sabe: temas e indicadores
create or replace function api.oraculo_indicadores(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('oraculo.prefeito');
  return (select coalesce(jsonb_agg(jsonb_build_object('tema', t.tema, 'nome', t.rotulo,
            'indicadores', (select jsonb_agg(jsonb_build_object('chave', i.chave, 'rotulo', i.rotulo) order by i.ordem) from iara.oraculo_indicadores i where i.tema = t.tema)) order by t.ordem), '[]')
          from iara.oraculo_temas t);
end $$;

-- "qual unidade tem mais…": indicador por unidade ou região. Indicador de pessoas: só valores de 3 ou mais.
create or replace function iara.oraculo_ranking_lista(p_chave text, p_por text, p_ordem text, p_limite integer, p_tipo text default null) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  i iara.oraculo_indicadores;
  v_desc boolean;
  r record;
  v numeric;
  itens jsonb := '[]';
begin
  select * into i from iara.oraculo_indicadores where chave = p_chave;
  if i.chave is null then raise exception 'Indicador desconhecido: %', p_chave using errcode = '22023'; end if;
  v_desc := coalesce(nullif(p_ordem, ''), i.pior) = 'maior';
  for r in
    select u.short_name nome, array[u.id] unidades from iara.education_units u
    where coalesce(p_por, 'unidade') = 'unidade' and (p_tipo is null or u.unit_type = p_tipo)
    union all
    select t.name, array(select u.id from iara.education_units u where u.macro_territory_id = t.id and (p_tipo is null or u.unit_type = p_tipo))
    from iara.territories t where p_por = 'regiao' and t.kind = 'AREA_PONDERACAO'
  loop
    continue when cardinality(r.unidades) = 0;
    v := iara.oraculo_valor(i.consulta, r.unidades, false);
    continue when v is null or (i.pessoas and v < 3);
    itens := itens || jsonb_build_object('nome', r.nome, 'valor', v);
  end loop;
  return jsonb_build_object('indicador', i.chave, 'rotulo', i.rotulo, 'sufixo', i.sufixo, 'casas', i.casas, 'por', coalesce(p_por, 'unidade'),
    'ordem', case when v_desc then 'maior' else 'menor' end,
    'lista', (select coalesce(jsonb_agg(x order by case when v_desc then -(x ->> 'valor')::numeric else (x ->> 'valor')::numeric end, x ->> 'nome'), '[]')
              from (select x from jsonb_array_elements(itens) x order by case when v_desc then -(x ->> 'valor')::numeric else (x ->> 'valor')::numeric end, x ->> 'nome' limit greatest(least(coalesce(p_limite, 5), 30), 1)) q));
end $$;

create or replace function api.oraculo_ranking(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
begin
  perform iara.require_perm('oraculo.prefeito');
  return iara.oraculo_ranking_lista(p ->> 'indicador', nullif(p ->> 'por', ''), nullif(p ->> 'ordem', ''), nullif(p ->> 'limite', '')::int, nullif(p ->> 'tipo', ''));
end $$;

-- estatística de nomes: quantas pessoas têm esse nome (primeiro nome ou sobrenome). Só a contagem, um nome por vez, e menos de 3 fica em
-- sigilo: dá para saber quantos Silvios há na rede, não para achar uma pessoa.
create or replace function iara.oraculo_contar_nome(p_nome text, p_quem text, p_units integer[], p_cidade boolean) returns integer
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  v text := '\m' || iara.oraculo_palavras(p_nome) || '\M';
  n integer;
begin
  if p_quem = 'PROFISSIONAIS' then
    select count(*) into n from iara.staff s where iara.norm(s.full_name) ~ v and (p_cidade or s.unit_id = any (p_units));
  elsif p_quem = 'RESPONSAVEIS' then
    select count(distinct g.id) into n from iara.guardians g
    join iara.student_guardians sg on sg.guardian_id = g.id and sg.end_date is null
    join iara.enrollments e on e.student_id = sg.student_id and e.status = 'ACTIVE'
    where iara.norm(g.full_name) ~ v and (p_cidade or e.unit_id = any (p_units));
  else
    select count(distinct st.id) into n from iara.students st
    join iara.enrollments e on e.student_id = st.id and e.status = 'ACTIVE'
    where iara.norm(st.full_name) ~ v and (p_cidade or e.unit_id = any (p_units));
  end if;
  return n;
end $$;

-- p: nome (uma palavra), quem? (ALUNOS | PROFISSIONAIS | RESPONSAVEIS), unidade?, regiao?
create or replace function api.oraculo_nomes(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = iara, public
as $$
declare
  a record := iara.oraculo_args(p);
  rc record := iara.oraculo_recorte_de(a.p_unit, a.p_area);
  v_nome text := iara.oraculo_palavras(p ->> 'nome');
  v_quem text := upper(coalesce(nullif(p ->> 'quem', ''), 'ALUNOS'));
  n integer;
begin
  perform iara.require_perm('oraculo.prefeito');
  if v_nome !~ '^[a-z]{3,}$' then
    raise exception 'Informe um nome por vez, só uma palavra (ex.: Silvio): o Oráculo conta nomes, não procura pessoas.' using errcode = '22023';
  end if;
  if v_quem not in ('ALUNOS', 'PROFISSIONAIS', 'RESPONSAVEIS') then
    raise exception 'Escolha alunos, profissionais ou responsáveis.' using errcode = '22023';
  end if;
  n := iara.oraculo_contar_nome(v_nome, v_quem, rc.unidades, rc.cidade);
  return jsonb_build_object('nome', p ->> 'nome', 'quem', v_quem, 'recorte', rc.nome, 'total', case when n between 1 and 2 then null else n end,
                            'sigilo', n between 1 and 2,
                            'nota', 'Pessoas com esse nome no cadastro (primeiro nome ou sobrenome). Só a contagem; menos de 3 fica em sigilo.');
end $$;

insert into iara.classificacao_dados (tabela, coluna, nivel, categoria, finalidade, protecao) values
  ('oraculo_indicadores', 'consulta', 'INTERNO', 'gestão', 'consultas agregadas do Oráculo do Prefeito', 'escritas na migração; nunca recebem texto de quem pergunta')
on conflict (tabela, coluna) do nothing;

revoke all on function iara.oraculo_valor(text, integer[], boolean), iara.oraculo_numero(iara.oraculo_indicadores, integer[], boolean),
  iara.oraculo_recorte_de(integer, integer), iara.oraculo_tema_numeros(text, text[], integer, integer), iara.oraculo_args(jsonb),
  iara.oraculo_ranking_lista(text, text, text, integer, text), iara.oraculo_contar_nome(text, text, integer[], boolean) from public;

commit;
