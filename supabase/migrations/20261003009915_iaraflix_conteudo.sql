-- IARA Educa — 099.15 · IARAFLIX: conteúdo inicial e demonstração
-- 16 trilhas: "Primeiros passos" (todos os servidores) e uma para cada perfil, tiradas dos 15 roteiros de treinamento do plano de implantação.
-- Cada bloco do roteiro vira uma aula curta (o vídeo é gravado depois pela Equipe IARA Educa e publicado em IARAFLIX > Gestão). Enquanto o vídeo
-- não chega, a aula mostra o que cobre e a prática, e a pessoa marca como estudada. Perguntas de fixação no fim de cada trilha.
-- O conteúdo entra uma vez só (on conflict do nothing): o que a gestão editar não é sobrescrito se esta migração rodar de novo.
-- Demonstração: adesão gerada para os professores, educadores, AEE e apoio do cadastro fictício (painel de adesão), apagada e refeita aqui.
-- Gerado por um script a partir de docs/iara-educa-implantacao (ROTEIROS); depois disso, o conteúdo é mantido pela tela de gestão.
begin;

insert into iara.iaraflix_trilhas (id, ordem, titulo, publico, objetivo, perfis, obrigatoria, staff_roles, saber, carga_horaria) values
  ('primeiros-passos', 0, 'Primeiros passos no IARA Educa', 'Todos os servidores, antes da trilha do próprio perfil', 'Entrar, se localizar e usar a plataforma com segurança, antes da trilha do seu perfil.', array['*']::text[], true, array['PROFESSOR', 'EDUCADOR', 'AEE', 'APOIO']::text[], array['Entrar e achar o que precisa', 'Ver e cumprir as suas pendências', 'Saber o que a IARA faz pelas famílias', 'Proteger os dados de alunos e famílias']::text[], 2.0)
on conflict (id) do nothing;
insert into iara.iaraflix_aulas (id, trilha_id, ordem, titulo, resumo, pratica) values
  ('443f9a28-e0e9-def5-0878-aa8b7a75df24', 'primeiros-passos', 1, 'Boas-vindas ao IARAFLIX', 'Como funciona a sua trilha: aulas curtas, de 3 a 5 minutos, a prática no ambiente de treinamento, perguntas no fim e o certificado com código de verificação.', 'Abrir a sua trilha e ver as aulas que faltam.'),
  ('dc82ab74-2dcd-5326-495b-c8037bbf7c0f', 'primeiros-passos', 2, 'Entrar e se localizar', 'Entrada com o login da Prefeitura, o menu por assunto, a barra do celular, a busca e a troca de unidade para quem tem dois vínculos.', 'No ambiente de treinamento, achar a sua unidade pelo menu e pela busca.'),
  ('68104aba-0a90-331e-4381-ddd7a060a430', 'primeiros-passos', 3, 'Pendências: o que eu tenho a cumprir', 'A central reúne validações, conferências e procedimentos com prazo. O que atrasa fica em vermelho e aparece para a chefia.', 'Abrir Pendências e concluir uma tarefa de exemplo.'),
  ('3547c946-da75-ce85-8a9d-e6c286c396f4', 'primeiros-passos', 4, 'A IARA e as famílias', 'O que a IARA resolve sozinha pelo WhatsApp, quando passa a conversa para uma pessoa e como a família confirma o número na escola.', 'Ver no ambiente de treinamento uma conversa atendida pela IARA e outra passada para a unidade.'),
  ('71d4ae35-d96c-34d9-01ae-454ee06533e9', 'primeiros-passos', 5, 'Sigilo e proteção de dados', 'A LGPD na prática: senha pessoal, nada de foto da tela, nada de dados em grupos de WhatsApp, e cada acesso registrado na auditoria.', null),
  ('e6f28bc9-cac0-b796-5038-172cff1d2175', 'primeiros-passos', 6, 'Ajuda e suporte', 'Onde pedir ajuda: o multiplicador da unidade, a Ajuda do portal e o suporte técnico, com protocolo e prazo.', 'Abrir um chamado de teste no Suporte técnico.')
on conflict (id) do nothing;
insert into iara.iaraflix_perguntas (id, trilha_id, ordem, enunciado, opcoes, correta, explicacao) values
  ('efa43903-9547-fb79-dde0-598b03cb6b83', 'primeiros-passos', 1, 'Você precisa sair do computador por alguns minutos. O que fazer?', array['Deixar a tela aberta: ninguém vai mexer', 'Sair da conta ou bloquear a tela', 'Pedir a um colega para continuar na sua conta']::text[], 1, 'Tudo o que é feito na sua conta fica registrado em seu nome na auditoria. Saia ou bloqueie a tela, sempre.'),
  ('69f7d30c-1185-7ed9-2d2e-46eabdfdb52c', 'primeiros-passos', 2, 'Um colega esqueceu a senha e pede a sua para lançar a chamada. O que fazer?', array['Emprestar só hoje', 'Não emprestar e indicar o suporte para recuperar o acesso dele', 'Fazer a chamada por ele na sua conta']::text[], 1, 'A senha é pessoal e intransferível. O suporte recupera o acesso do colega no mesmo dia.'),
  ('a859575f-7c0c-ee9e-d3ed-7a14e5054b98', 'primeiros-passos', 3, 'Posso fotografar a tela com dados de alunos para mandar num grupo de WhatsApp?', array['Sim, se o grupo for só de servidores', 'Não: dados de alunos e famílias não saem da plataforma', 'Sim, se eu apagar depois']::text[], 1, 'Pela LGPD, dado de criança e de família só circula dentro da plataforma, onde cada acesso é registrado.'),
  ('e4e3c056-47e6-32a4-5b88-3ad76c5633ed', 'primeiros-passos', 4, 'Onde você vê o que tem a cumprir, com prazo?', array['Em Pendências', 'No Mural', 'Na Ajuda']::text[], 0, 'A Central de pendências reúne o que cada servidor tem a cumprir. O que atrasa fica em vermelho e aparece para a chefia.'),
  ('13275a16-41af-447e-b110-7c1c03aa3063', 'primeiros-passos', 5, 'A IARA não sabe responder a uma pergunta de uma família. O que ela faz?', array['Dá a resposta mais provável', 'Diz que não tem a informação naquele momento e indica quem pode confirmar', 'Encerra a conversa']::text[], 1, 'A IARA não inventa: quando não tem o dado, diz isso e indica quem confirma (a escola ou a SEDUC, conforme o assunto).')
on conflict (id) do nothing;

insert into iara.iaraflix_trilhas (id, ordem, titulo, publico, objetivo, perfis, obrigatoria, staff_roles, saber, carga_horaria) values
  ('central-de-vagas', 1, 'Central de Vagas', 'Equipe da Central de Vagas', 'Operar a fila pela IN nº 025/2025 e conferir a ordem com a lista oficial durante o paralelo (27/01 a 10/02).', array['ANALISTA_CENTRAL']::text[], true, '{}'::text[], array['Explicar a pontuação de uma criança pela IN 025', 'Ofertar vaga e acompanhar as 72 h', 'Conferir a ordem com a lista oficial e explicar divergências', 'Registrar recusa e transferência']::text[], 3.0)
on conflict (id) do nothing;
insert into iara.iaraflix_aulas (id, trilha_id, ordem, titulo, resumo, pratica) values
  ('d53af15b-5ca1-6e3d-eeec-bbb2e2da208f', 'central-de-vagas', 1, 'Boas-vindas à trilha', 'O que muda na Central; onda 1 na SEDUC em 27/01; fila oficial em 11/02; sigilo dos dados das crianças', null),
  ('6fa6d385-9dc7-2546-cdd0-05c795288cec', 'central-de-vagas', 2, 'Fila pela IN 025', 'Critérios e pontos (irmão 55, CadÚnico 25, até 2 km 15, mãe solo 5); distância em linha reta, a pé e de carro; extrato de pontos', 'Abrir a Fila, achar o Davi (1º, 95 pontos) e explicar o extrato'),
  ('3d3b40ae-9e90-298e-74c8-d480f8ae2d51', 'central-de-vagas', 3, 'Laudos e prioridades', 'PCD, TEA, TGD e altas habilidades sob análise; oferta fora da ordem só com laudo validado e justificativa registrada', 'Validar um laudo fictício em Validações'),
  ('89ba18d9-7ff9-f87a-0672-058309185eb8', 'central-de-vagas', 4, 'Ofertas e matrículas', 'Ofertar vaga, prazo de 72 h, recusa com motivo, perda de prazo e reserva liberada; Recusas de vaga', 'Ofertar a última vaga de uma turma e registrar uma recusa'),
  ('fd8c1bd8-812b-95f9-495b-51859cc8c6b6', 'central-de-vagas', 5, 'Conferência da ordem', 'Fila em paralelo: comparar todo dia a ordem da IARA com a lista oficial e explicar cada divergência', 'Montar o relatório de conferência com uma divergência de exemplo'),
  ('69e1838f-8409-0f94-06cc-7be5f45f2ab0', 'central-de-vagas', 6, 'Famílias que pedem vaga', 'Conversas e Atendimentos da Central; alçadas; transferência para a unidade', 'Assumir uma conversa de família pedindo vaga e concluir o protocolo'),
  ('239786a3-df70-b234-77bd-e4885a2b3068', 'central-de-vagas', 7, 'Rematrícula, transferência e ensalamento', 'Transferência com vaga (muda na hora) e sem vaga (entra na fila); salas e turmas', 'Fazer uma transferência com vaga e outra sem vaga'),
  ('8f258361-6661-c2c8-090a-e0098f8f7d96', 'central-de-vagas', 8, 'Controle externo e trilha', 'O que MP e Defensoria veem; consulta de caso com motivo; auditoria', 'Consultar um caso pelo protocolo')
on conflict (id) do nothing;
insert into iara.iaraflix_perguntas (id, trilha_id, ordem, enunciado, opcoes, correta, explicacao) values
  ('b1ec9f0a-62aa-5a62-5f2c-07600c9746ca', 'central-de-vagas', 1, 'Pela IN nº 025/2025, quantos pontos vale ter irmão na mesma unidade?', array['15', '25', '55']::text[], 2, 'Irmão na mesma unidade vale 55; CadÚnico, 25; até 2 km, 15; mãe solo, 5.'),
  ('470a9ee1-ff77-1508-f12d-85722db958d8', 'central-de-vagas', 2, 'Qual é o prazo para a família responder a uma oferta de vaga?', array['24 horas', '72 horas', '7 dias']::text[], 1, 'São 72 horas (Anexo II da IN 025). Sem resposta no prazo, a vaga volta e a fila anda.'),
  ('7ceb9bda-4450-3169-c2ec-df1ec336f22a', 'central-de-vagas', 3, 'Uma criança com laudo de TEA pode receber a vaga fora da ordem quando...', array['a família pede', 'o laudo foi validado e a justificativa foi registrada', 'a direção autoriza por telefone']::text[], 1, 'A prioridade fica sob análise até o laudo ser validado; a oferta fora da ordem exige justificativa e fica na auditoria.')
on conflict (id) do nothing;

insert into iara.iaraflix_trilhas (id, ordem, titulo, publico, objetivo, perfis, obrigatoria, staff_roles, saber, carga_horaria) values
  ('ti-da-prefeitura', 2, 'TI da Prefeitura', 'Equipe de TI da Prefeitura', 'Administrar contas e acessos e saber agir em incidente, backup e canal oficial.', array['INOVACAO']::text[], true, '{}'::text[], array['Criar e revogar contas', 'Acionar o plano de incidente', 'Saber quando chamar a Equipe (2º e 3º nível)']::text[], 2.0)
on conflict (id) do nothing;
insert into iara.iaraflix_aulas (id, trilha_id, ordem, titulo, resumo, pratica) values
  ('32c45f69-40a7-3393-f4ad-d715cd8f7b44', 'ti-da-prefeitura', 1, 'Boas-vindas à trilha', 'Ambientes (oficial, homologação e treinamento); o que é da Prefeitura e o que é da Equipe', null),
  ('a5de8069-a398-9059-d0ce-adac0ebf83ff', 'ti-da-prefeitura', 2, 'Arquitetura e segurança', 'Hospedagem no Brasil, permissões por perfil, auditoria encadeada, testes de segurança', 'Ver a trilha íntegra na Auditoria'),
  ('1f8efacb-bb2e-7f68-8897-b0fa81f13bc0', 'ti-da-prefeitura', 3, 'Contas e acessos', 'Login da Prefeitura com dupla verificação; entrada, mudança e desligamento no mesmo dia; revisão trimestral', 'Desativar uma conta de teste e ver a sessão cair'),
  ('b37db3aa-f02d-eff1-90b5-522b9dfe6f05', 'ti-da-prefeitura', 4, 'Backup e incidentes', 'Backup diário cifrado, restauração, plano de incidente e comunicação à ANPD em 3 dias úteis', 'Exercício de mesa curto'),
  ('93968b92-77f1-aec9-86a8-2b79d289390b', 'ti-da-prefeitura', 5, 'WhatsApp oficial e domínio', 'Conta comercial da Meta da Prefeitura, modelos de mensagem, domínio e certificados', null)
on conflict (id) do nothing;
insert into iara.iaraflix_perguntas (id, trilha_id, ordem, enunciado, opcoes, correta, explicacao) values
  ('1740285f-710b-0cf2-0ec9-970f0d6d3d82', 'ti-da-prefeitura', 1, 'Um servidor foi desligado hoje. Quando a conta dele deve ser desativada?', array['No mesmo dia', 'No fim do mês', 'Na próxima revisão trimestral']::text[], 0, 'O ciclo de vida da conta acompanha o RH: desligou, a conta cai no mesmo dia.'),
  ('48122900-3b3f-b7b6-b5c7-7d602ee76608', 'ti-da-prefeitura', 2, 'Num incidente com dados pessoais, em quanto tempo a comunicação à ANPD deve ser feita?', array['24 horas', '3 dias úteis', '30 dias']::text[], 1, 'O plano de incidente prevê a comunicação à ANPD em até 3 dias úteis.'),
  ('9760489e-41fd-21e6-8544-d551f9d6c96b', 'ti-da-prefeitura', 3, 'Onde ficam os dados da plataforma?', array['Em servidores no Brasil', 'Nos Estados Unidos', 'No computador da SEDUC']::text[], 0, 'A hospedagem fica no Brasil (São Paulo), com backup diário cifrado.')
on conflict (id) do nothing;

insert into iara.iaraflix_trilhas (id, ordem, titulo, publico, objetivo, perfis, obrigatoria, staff_roles, saber, carga_horaria) values
  ('atendimento-conversas', 3, 'Atendimento das conversas', 'Equipe da SEDUC que responde as filas do WhatsApp', 'Assumir as conversas que a IARA passa para pessoa e resolver ou encaminhar dentro do prazo.', array['ATENDIMENTO', 'ANALISTA_CENTRAL']::text[], true, '{}'::text[], array['Assumir e transferir conversas no prazo', 'Concluir protocolos com evidência', 'Orientar sobre número do cadastro e troca de número']::text[], 2.0)
on conflict (id) do nothing;
insert into iara.iaraflix_aulas (id, trilha_id, ordem, titulo, resumo, pratica) values
  ('04bcbad8-0009-1cfb-5064-4e9da00f7876', 'atendimento-conversas', 1, 'Boas-vindas à trilha', 'Quando a IARA passa a conversa para uma pessoa', null),
  ('d51b22ce-1998-b572-cd90-451e8ff6cfa8', 'atendimento-conversas', 2, 'Conversas', 'Lista no estilo do WhatsApp, quem atende, assumir, responder, transferir para a unidade ou o setor, prazos e atrasadas', 'Assumir, responder e transferir uma conversa'),
  ('234fb74d-6ab9-8714-8e18-ec618ea97a83', 'atendimento-conversas', 3, 'Atendimentos e protocolos', 'Protocolo, prazo, alçada, linha do tempo e encerramento com evidência', 'Concluir um protocolo'),
  ('fdd6c2ff-e3d9-a9c8-0fe4-0fba1a9ad9ee', 'atendimento-conversas', 4, 'Identidade das famílias', 'Número do cadastro, número confirmado na escola, troca de número, "NÃO FUI EU"; nunca pedir código ou senha', 'Orientar uma família que trocou de número'),
  ('f2f6ee14-e33b-5b77-dbd2-2095a5ea2db7', 'atendimento-conversas', 5, 'Tom e proteção', 'Linguagem simples; suspeita de violência vai para registro sigiloso; o que não escrever no chat', null)
on conflict (id) do nothing;
insert into iara.iaraflix_perguntas (id, trilha_id, ordem, enunciado, opcoes, correta, explicacao) values
  ('a8eb461d-0643-6fc4-d4b4-6195bdf1d075', 'atendimento-conversas', 1, 'Uma família trocou de número e quer continuar a conversa. O que você nunca deve pedir?', array['O nome da criança', 'O código ou a senha que a família recebeu', 'A unidade onde a criança estuda']::text[], 1, 'Código e senha são só da família. A troca de número é feita na escola ou pelo número antigo.'),
  ('b44611b7-4fa8-09a1-ca32-d807454c709f', 'atendimento-conversas', 2, 'Na conversa aparece suspeita de violência contra a criança. O que fazer?', array['Pedir detalhes pelo chat', 'Levar para o registro sigiloso, pelo protocolo de proteção', 'Encerrar a conversa']::text[], 1, 'Suspeita de violência sai do chat e vai para o registro sigiloso, com o encaminhamento previsto.'),
  ('5b2c3987-213c-b091-8e0c-db78340a7b33', 'atendimento-conversas', 3, 'A dúvida é da escola, e não da SEDUC. O que fazer com a conversa?', array['Transferir para a unidade responsável', 'Responder qualquer coisa para fechar', 'Pedir que a família ligue']::text[], 0, 'Cada assunto tem a sua alçada. A transferência leva o histórico e o prazo continua contando.')
on conflict (id) do nothing;

insert into iara.iaraflix_trilhas (id, ordem, titulo, publico, objetivo, perfis, obrigatoria, staff_roles, saber, carga_horaria) values
  ('suporte-1-nivel', 4, 'Suporte da SEDUC (1º nível)', 'Equipe de suporte de 1º nível', 'Resolver as dúvidas e os problemas de acesso mais comuns e encaminhar o resto para a Equipe.', array['ATENDIMENTO', 'INOVACAO']::text[], false, '{}'::text[], array['Resolver problemas de acesso e de vínculo do WhatsApp', 'Classificar e escalar chamados', 'Agir certo diante de um incidente de segurança']::text[], 3.0)
on conflict (id) do nothing;
insert into iara.iaraflix_aulas (id, trilha_id, ordem, titulo, resumo, pratica) values
  ('af6d72d3-d5e8-bd7e-f330-4c03355f9b7c', 'suporte-1-nivel', 1, 'Boas-vindas à trilha', 'O papel do 1º nível, horário, canais e o que vai para a Equipe', null),
  ('39ffd635-b0e7-7f42-dfe3-79d4db6ad29c', 'suporte-1-nivel', 2, 'Perfis e permissões', 'O que cada perfil vê; escopo da unidade; por que alguém "não enxerga" um aluno (vínculo, guarda e restrições)', 'Entrar em quatro perfis do ambiente de treinamento e comparar'),
  ('531e55cf-da62-b4c8-45b5-ec344fda3a68', 'suporte-1-nivel', 3, 'Contas e primeiro acesso', 'Login, dupla verificação, termo de responsabilidade, troca de unidade, conta desativada', 'Resolver cinco chamados típicos de acesso'),
  ('75756329-7d1b-bd84-9e6e-c76383dadb77', 'suporte-1-nivel', 4, 'Famílias e WhatsApp', 'Níveis de acesso, QR na secretaria, troca de número, "não encontrei este número"', 'Gerar um QR de vínculo e atender uma troca de número'),
  ('4c578c5b-3aa0-70c2-dc0c-4d9b12f4f2dd', 'suporte-1-nivel', 5, 'Suporte técnico', 'Abrir e classificar protocolo, prioridade e prazo, acesso remoto só com código, quando escalar', 'Fazer a triagem de dez chamados'),
  ('d35f9092-377d-a263-f6ed-1fc8a847ca84', 'suporte-1-nivel', 6, 'Erros comuns por perfil', 'Chamada que não salvou, nota fora do bimestre, documento recusado, oferta vencida', 'Seguir o roteiro de diagnóstico'),
  ('9ded8b45-253c-755e-ef60-08ad645c0684', 'suporte-1-nivel', 7, 'Segurança e LGPD', 'Suspeita de vazamento, senha compartilhada, pedido de dados, auditoria', 'O que fazer diante de uma senha compartilhada'),
  ('3c1d199e-1f01-7ee9-8816-e3aa7a6e74c4', 'suporte-1-nivel', 8, 'Plantão do dia 1', 'Escala de 03 e 04/02 e plano de volta (chamada em papel)', null)
on conflict (id) do nothing;
insert into iara.iaraflix_perguntas (id, trilha_id, ordem, enunciado, opcoes, correta, explicacao) values
  ('8ba285cc-9426-6178-f2fc-e0f974ef010d', 'suporte-1-nivel', 1, 'Uma professora "não enxerga" um aluno. Qual é a causa mais provável?', array['Falha do sistema', 'O aluno não está na turma dela ou há restrição de acesso', 'Internet lenta']::text[], 1, 'Cada perfil vê só o seu escopo. Confira o vínculo com a turma e as restrições antes de escalar.'),
  ('986ded99-f8e9-ead7-376c-9a7bf3caa2c0', 'suporte-1-nivel', 2, 'Para acessar o computador de um servidor a distância, o suporte...', array['usa a senha do servidor', 'entra só com o código da sessão, com o servidor presente', 'pede a senha pelo WhatsApp']::text[], 1, 'Acesso remoto só com código e com a pessoa acompanhando. Senha nunca.'),
  ('3edb0a4e-1712-dd08-788c-90ea60e06637', 'suporte-1-nivel', 3, 'Um servidor conta que emprestou a senha a um colega. O que orientar?', array['Nada, foi um colega', 'Trocar a senha na hora e registrar o ocorrido', 'Desativar a conta do colega']::text[], 1, 'Senha compartilhada é incidente de segurança: troca imediata e registro.')
on conflict (id) do nothing;

insert into iara.iaraflix_trilhas (id, ordem, titulo, publico, objetivo, perfis, obrigatoria, staff_roles, saber, carga_horaria) values
  ('gestao-seduc', 5, 'Secretário, Superintendência e gerências', 'Gestão da SEDUC', 'Acompanhar a rede pelos painéis e pelas pendências e mudar regras com segurança.', array['SECRETARIO', 'SUPERINTENDENCIA', 'GERENCIA_EI', 'GERENCIA_APOIO']::text[], true, '{}'::text[], array['Acompanhar as pendências de cada setor', 'Ler os painéis da rede e das unidades', 'Alterar regras e catálogo com registro']::text[], 2.0)
on conflict (id) do nothing;
insert into iara.iaraflix_aulas (id, trilha_id, ordem, titulo, resumo, pratica) values
  ('0f3aefe4-883c-7a59-1894-beef2e91b257', 'gestao-seduc', 1, 'Boas-vindas à trilha', 'O que esta trilha cobre e o que você vai conseguir fazer ao final: acompanhar as pendências de cada setor; ler os painéis da rede e das unidades; alterar regras e catálogo com registro.', null),
  ('b35fcf05-487c-b0a2-9b2f-b71639fb8f8c', 'gestao-seduc', 2, 'Início, unidades e mapas', 'Visão da rede e de cada unidade', 'Achar uma unidade com fila e sala livre'),
  ('2497d96d-d1b6-9850-451a-d144bf0d2ca9', 'gestao-seduc', 3, 'Pendências', 'O que cada servidor tem a cumprir; atrasadas por setor; acompanhamento pelo organograma', 'Atribuir uma tarefa com prazo a um setor'),
  ('d91b9d96-f8b7-2179-ecab-14f1a93c15d6', 'gestao-seduc', 4, 'Atendimento e fila', 'Conversas e protocolos da rede, fila, recusas e o painel do controle externo', null),
  ('3bf7ec91-7514-d009-b00e-c5b27764de6d', 'gestao-seduc', 5, 'Gestão da rede', 'Organograma, catálogo de serviços, critérios (mudança vira versão com justificativa e não retroage), jornada e matriz', 'Simular a alteração de um critério, sem aplicar'),
  ('7073dccc-ee24-3a5c-565a-bdd42c48fa5b', 'gestao-seduc', 6, 'Auditoria, qualidade e indicadores', 'A trilha de auditoria encadeada, a qualidade dos dados de cada unidade e os indicadores da rede.', null)
on conflict (id) do nothing;
insert into iara.iaraflix_perguntas (id, trilha_id, ordem, enunciado, opcoes, correta, explicacao) values
  ('acaa485b-a6f3-6bc9-62a2-b2f05dbded6b', 'gestao-seduc', 1, 'Mudar um critério de pontuação da fila...', array['vale na hora para todas as inscrições antigas', 'vira uma nova versão, com justificativa, e não retroage', 'não deixa registro']::text[], 1, 'Toda mudança de regra vira versão, com justificativa e data, e não altera o que já foi decidido.'),
  ('36efaccd-c846-c9a8-d964-b08c6a201ab4', 'gestao-seduc', 2, 'Antes de aplicar a mudança de um critério, o recomendado é...', array['simular o efeito na fila', 'aplicar e ver o que acontece', 'pedir que a TI mude direto no banco']::text[], 0, 'A simulação mostra quem sobe e quem desce antes de qualquer mudança valer.'),
  ('aed5e8e3-58cd-cbaa-0c26-6ae37b33a4e2', 'gestao-seduc', 3, 'Onde você acompanha as tarefas atrasadas de cada setor?', array['Em Pendências', 'No Mural', 'No Calendário']::text[], 0, 'Pendências mostra o atrasado por setor, seguindo o organograma.')
on conflict (id) do nothing;

insert into iara.iaraflix_trilhas (id, ordem, titulo, publico, objetivo, perfis, obrigatoria, staff_roles, saber, carga_horaria) values
  ('prefeito', 6, 'Prefeito e Gabinete', 'Prefeito e Gabinete', 'Acompanhar a educação da cidade em números, sem nomes de pessoas.', array['PREFEITO']::text[], true, '{}'::text[], array['Consultar os números da rede', 'Usar os mapas de calor', 'Perguntar ao Oráculo', 'Enviar comunicados pelos Públicos do Prefeito']::text[], 2.0)
on conflict (id) do nothing;
insert into iara.iaraflix_aulas (id, trilha_id, ordem, titulo, resumo, pratica) values
  ('3058fc88-9d21-cb7e-fb1d-5a09fc38c99e', 'prefeito', 1, 'Visão do prefeito', 'Números da rede e o que é sempre agregado', null),
  ('802df311-608a-a0db-0782-b70636fa9501', 'prefeito', 2, 'Mapas de calor', 'Transporte, frequência, ocorrências, alfabetização e cadastros', null),
  ('0858efbb-7e46-2603-60d7-205f07848b65', 'prefeito', 3, 'Oráculo', 'Perguntas em linguagem natural; resposta com número, comparação e sugestão', 'Perguntar "como está a frequência na região norte?"'),
  ('d298663e-cd11-4729-d3ed-2c7492784bbb', 'prefeito', 4, 'Públicos do Prefeito', 'Montar um público com os filtros do IARA, ver só a contagem e enviar comunicado pelo WhatsApp oficial, com auditoria e sem exportar contatos', 'Montar o público "responsáveis da região norte", sem enviar'),
  ('76107c5d-2693-495c-114f-386812540182', 'prefeito', 5, 'Pendências da rede', 'Estatísticas das pendências por unidade e por região, sem nomes.', null)
on conflict (id) do nothing;
insert into iara.iaraflix_perguntas (id, trilha_id, ordem, enunciado, opcoes, correta, explicacao) values
  ('39352824-2b44-91df-ddaa-e9b12490d5db', 'prefeito', 1, 'O que o perfil do Prefeito mostra sobre as pessoas?', array['Nomes e contatos', 'Só números agregados, sem nomes', 'Os laudos']::text[], 1, 'O Prefeito vê a cidade em números: unidade, região, área e tipo, nunca a pessoa.'),
  ('1ddee6a4-98f6-17d2-c605-03e84f5daeef', 'prefeito', 2, 'Nos Públicos do Prefeito, ao montar um público você vê...', array['a lista de telefones', 'só a contagem; o envio sai pelo WhatsApp oficial, com registro', 'os endereços das famílias']::text[], 1, 'Os contatos não são exportados. O envio é feito pela plataforma e fica na auditoria.'),
  ('78b47cef-5839-0a90-c9b1-66e2d8573bf7', 'prefeito', 3, 'O Oráculo responde...', array['com número, comparação e sugestão', 'só com uma tabela', 'com os nomes das crianças']::text[], 0, 'A resposta vem pronta para decidir: o número, com o que comparar e o que fazer.')
on conflict (id) do nothing;

insert into iara.iaraflix_trilhas (id, ordem, titulo, publico, objetivo, perfis, obrigatoria, staff_roles, saber, carga_horaria) values
  ('nutricao', 7, 'Nutrição', 'Gerência de nutrição, nutricionistas e um responsável pela cozinha de cada unidade', 'Publicar cardápios, validar restrições e orientar a cozinha sem expor laudos.', array['NUTRICAO']::text[], true, '{}'::text[], array['Publicar o cardápio', 'Validar restrições', 'Usar a lista da cozinha']::text[], 2.0)
on conflict (id) do nothing;
insert into iara.iaraflix_aulas (id, trilha_id, ordem, titulo, resumo, pratica) values
  ('c585cb04-0576-23a8-5f57-7e85690c597b', 'nutricao', 1, 'Boas-vindas à trilha', 'O que esta trilha cobre e o que você vai conseguir fazer ao final: publicar o cardápio; validar restrições; usar a lista da cozinha.', null),
  ('2fb6e6e8-a25a-2945-384b-64000c6a5363', 'nutricao', 2, 'Cardápios', 'Cardápio semanal por faixa e troca automática pelas restrições', 'Montar o cardápio de uma semana'),
  ('956dd597-b31b-4030-e30c-74e8b7f49e41', 'nutricao', 3, 'Restrições alimentares', 'As 17 categorias, o motivo, a validação pela nutrição e a instrução de preparo', 'Validar uma restrição informada pela família'),
  ('18bb9e9b-f7d3-6c49-328c-b787f1ad5233', 'nutricao', 4, 'Cozinha', 'Para o responsável da cozinha: a lista do dia com a instrução de preparo, nunca o laudo', 'Abrir a lista da cozinha de uma unidade'),
  ('dabc3bb8-6bb3-8533-5a63-900dd71069a6', 'nutricao', 5, 'Peso e medidas', 'Classificação só com a tabela oficial da OMS importada pela nutricionista', null),
  ('ae5a22d3-ae08-5a7a-6932-8746c0d4eb4a', 'nutricao', 6, 'Alimentos e pedidos', 'Estoque por lote e validade e pedidos', null)
on conflict (id) do nothing;
insert into iara.iaraflix_perguntas (id, trilha_id, ordem, enunciado, opcoes, correta, explicacao) values
  ('5d5f8604-a2c3-4f17-bb3f-7778b764fa0d', 'nutricao', 1, 'O que a cozinha vê sobre a restrição alimentar de uma criança?', array['O laudo', 'A instrução de preparo, nunca o laudo', 'Nada']::text[], 1, 'A cozinha precisa saber o que fazer, não o diagnóstico. O laudo fica com a nutrição.'),
  ('15b12bb7-668f-d659-fb78-0ee94a6a54e8', 'nutricao', 2, 'Uma família informou uma restrição alimentar. Quem valida?', array['A cozinha', 'A nutrição', 'O professor']::text[], 1, 'A nutrição valida a restrição e define a instrução de preparo.'),
  ('bb85a13b-2f4a-4239-dd86-d3654204ca21', 'nutricao', 3, 'A classificação de peso e medidas usa...', array['a tabela oficial da OMS importada pela nutricionista', 'uma tabela qualquer da internet', 'a avaliação da professora']::text[], 0, 'Só a tabela oficial da OMS, importada pela nutricionista, classifica peso e medidas.')
on conflict (id) do nothing;

insert into iara.iaraflix_trilhas (id, ordem, titulo, publico, objetivo, perfis, obrigatoria, staff_roles, saber, carga_horaria) values
  ('transporte', 8, 'Transporte escolar', 'Gerência de transporte e monitores', 'Acompanhar as viagens do dia e agir quando uma rota não acontece.', array['TRANSPORTE']::text[], true, '{}'::text[], array['Acompanhar as viagens do dia', 'Incluir aluno em rota', 'Registrar ocorrência de rota']::text[], 2.0)
on conflict (id) do nothing;
insert into iara.iaraflix_aulas (id, trilha_id, ordem, titulo, resumo, pratica) values
  ('075f9edf-af72-b444-d0e1-9552ccb0d561', 'transporte', 1, 'Boas-vindas à trilha', 'O que esta trilha cobre e o que você vai conseguir fazer ao final: acompanhar as viagens do dia; incluir aluno em rota; registrar ocorrência de rota.', null),
  ('2a5fd415-34c2-663d-736b-df82563625a3', 'transporte', 2, 'Transporte hoje', 'Viagens do dia, atrasos e veículo reserva', 'Registrar um atraso e uma troca de veículo'),
  ('a1a62dd3-b98b-309f-e61b-ac986a1af304', 'transporte', 3, 'Rotas e alunos', 'Rotas, pontos e alunos aguardando rota com sugestão', 'Incluir um aluno numa rota (a família é avisada)'),
  ('450ebf57-0b3a-bcd9-c4e4-d38a677557a5', 'transporte', 4, 'Lista de embarque', 'Para os monitores: quem faltou ou avisou que não vai', 'Conferir o embarque de uma rota'),
  ('e4c4af2b-33a7-98a9-14f4-32aeaf708e43', 'transporte', 5, 'Ocorrências', 'Viagem não realizada: famílias avisadas e falta abonada', 'Registrar uma viagem não realizada'),
  ('289c8df3-ac22-2795-4704-f570b0a0fd0e', 'transporte', 6, 'Frota, motoristas e mapa', 'Vistoria, CNH e curso vencendo; Mapa das rotas', null)
on conflict (id) do nothing;
insert into iara.iaraflix_perguntas (id, trilha_id, ordem, enunciado, opcoes, correta, explicacao) values
  ('7d1dec8b-0b40-47cd-4f45-5bd5f98372ee', 'transporte', 1, 'Uma viagem não aconteceu. O que acontece ao registrar a ocorrência?', array['Nada', 'As famílias são avisadas e a falta dos alunos é abonada', 'O motorista é multado']::text[], 1, 'A viagem não realizada avisa as famílias e abona a falta de quem dependia da rota.'),
  ('4495e020-623f-cbf6-a3e2-41e29d9b6c35', 'transporte', 2, 'Ao incluir um aluno numa rota...', array['a família é avisada', 'ninguém é avisado', 'a escola precisa ligar para a família']::text[], 0, 'A inclusão na rota gera o aviso à família automaticamente.'),
  ('cb4f9d27-d0ed-8a84-fd11-024054f29b00', 'transporte', 3, 'Onde o monitor confere quem faltou ou avisou que não vai?', array['Na lista de embarque', 'No Mural', 'Em Pendências']::text[], 0, 'A lista de embarque mostra quem embarca, quem faltou e quem avisou.')
on conflict (id) do nothing;

insert into iara.iaraflix_trilhas (id, ordem, titulo, publico, objetivo, perfis, obrigatoria, staff_roles, saber, carga_horaria) values
  ('almoxarifado-infra', 9, 'Almoxarifado e infraestrutura', 'Almoxarifado central e infraestrutura', 'Atender os pedidos das escolas, controlar estoque e tratar os chamados de manutenção.', array['ALMOXARIFADO', 'MANUTENCAO']::text[], true, '{}'::text[], array['Atender um pedido de ponta a ponta', 'Controlar validade e lotes', 'Tratar chamados de manutenção']::text[], 2.0)
on conflict (id) do nothing;
insert into iara.iaraflix_aulas (id, trilha_id, ordem, titulo, resumo, pratica) values
  ('c5df0550-4f5d-d9dd-a30e-42d618de0e69', 'almoxarifado-infra', 1, 'Boas-vindas à trilha', 'O que esta trilha cobre e o que você vai conseguir fazer ao final: atender um pedido de ponta a ponta; controlar validade e lotes; tratar chamados de manutenção.', null),
  ('2dcf746f-54c0-3003-060c-bd910b1674f9', 'almoxarifado-infra', 2, 'Estoque e pedidos', 'Pedido da escola, aprovação, remessa e recebimento; divergência explicada; lotes e validade', 'Aprovar um pedido com ajuste e despachar a remessa'),
  ('51aa3b53-6050-0229-4dea-bbac44d5f6f1', 'almoxarifado-infra', 3, 'Uniformes e kits', 'Grade, remessa por unidade e tamanho, retirada com código', 'Registrar uma retirada'),
  ('ec2c9be9-779d-65fb-9082-b3e49497f03c', 'almoxarifado-infra', 4, 'Manutenção', 'Chamado da escola, triagem, vistoria, orçamento, execução e validação pela unidade', 'Triar e programar um chamado urgente'),
  ('b747ff46-8eeb-dd23-e51b-704fe3daeb4f', 'almoxarifado-infra', 5, 'Patrimônio', 'Transferência com aceite, baixa com laudo e inventário', null)
on conflict (id) do nothing;
insert into iara.iaraflix_perguntas (id, trilha_id, ordem, enunciado, opcoes, correta, explicacao) values
  ('6a75009c-ca45-69aa-0c10-064a85a433d0', 'almoxarifado-infra', 1, 'A retirada de uniformes e kits pela família é feita...', array['com código', 'com assinatura em papel', 'sem registro']::text[], 0, 'A retirada é confirmada com o código da família e fica registrada.'),
  ('52817eae-1158-6f8a-0cc0-35e949bb079b', 'almoxarifado-infra', 2, 'A remessa chegou diferente do pedido aprovado. O que fazer?', array['Ignorar', 'Registrar a divergência, com a explicação', 'Cancelar o pedido']::text[], 1, 'Divergência registrada e explicada mantém o estoque confiável.'),
  ('e6168200-da17-a948-e347-d4f78ee26f29', 'almoxarifado-infra', 3, 'Um chamado de manutenção termina quando...', array['a equipe executa o serviço', 'a unidade valida o serviço', 'o orçamento é aprovado']::text[], 1, 'O chamado só fecha com a validação da unidade.')
on conflict (id) do nothing;

insert into iara.iaraflix_trilhas (id, ordem, titulo, publico, objetivo, perfis, obrigatoria, staff_roles, saber, carga_horaria) values
  ('orgaos-externos', 10, 'Órgãos externos', 'MP, Defensoria, Tribunal de Contas, conselhos, Conselho Tutelar e Câmara', 'Consultar só o que cabe a cada órgão, sempre com registro.', array['CONTROLE_EXTERNO', 'TRIBUNAL_CONTAS', 'CONSELHOS', 'CONSELHO_TUTELAR', 'CAMARA']::text[], true, '{}'::text[], array['Usar o painel do órgão', 'Consultar caso com motivo']::text[], 1.5)
on conflict (id) do nothing;
insert into iara.iaraflix_aulas (id, trilha_id, ordem, titulo, resumo, pratica) values
  ('ee8ed53c-9461-33e4-f2bf-ac0592713def', 'orgaos-externos', 1, 'O que cada órgão vê', 'Painel do órgão e limites de acesso', null),
  ('4b02fdaa-6e60-18a8-4a83-9a1e2fc2ff0e', 'orgaos-externos', 2, 'Painel e fila pública', 'Código público da criança, ordem e critérios', 'Achar uma inscrição pelo código público'),
  ('c18f7074-b65f-1087-2551-e4293892d93e', 'orgaos-externos', 3, 'Consulta de caso', 'Com protocolo e motivo, sempre registrada na trilha', 'Consultar um caso de exemplo'),
  ('ee93aaa2-0c82-b8fc-9462-3496b16f151e', 'orgaos-externos', 4, 'Termo de responsabilidade', 'O termo de responsabilidade e o ofício de acesso do órgão.', null)
on conflict (id) do nothing;
insert into iara.iaraflix_perguntas (id, trilha_id, ordem, enunciado, opcoes, correta, explicacao) values
  ('3fc7718b-0196-41f5-1394-862230cb1684', 'orgaos-externos', 1, 'Para consultar um caso, é preciso...', array['só o nome da criança', 'o protocolo e o motivo; a consulta fica registrada', 'ligar para a SEDUC']::text[], 1, 'Toda consulta de caso exige protocolo e motivo e entra na trilha de auditoria.'),
  ('53e5b8b1-62c4-af14-065d-a538f9553a3c', 'orgaos-externos', 2, 'Na fila pública, a criança aparece...', array['pelo nome completo', 'por um código público, sem dados pessoais', 'pelo CPF']::text[], 1, 'A fila pública mostra a ordem e os critérios sem expor a criança.'),
  ('92c11222-b716-9a8e-074a-4efe9176f366', 'orgaos-externos', 3, 'O acesso do órgão é concedido...', array['por ofício do órgão, com nome, cargo e termo assinado', 'por pedido no WhatsApp', 'a qualquer pessoa do órgão']::text[], 0, 'O acesso é nominal, por ofício, com termo de responsabilidade.')
on conflict (id) do nothing;

insert into iara.iaraflix_trilhas (id, ordem, titulo, publico, objetivo, perfis, obrigatoria, staff_roles, saber, carga_horaria) values
  ('multiplicadores', 11, 'Multiplicadores da unidade', 'Uma pessoa de cada unidade, em geral da secretaria ou da coordenação, que ajuda os colegas', 'Ser o primeiro apoio dos colegas na unidade, sem usar a conta de ninguém.', array['DIRETOR_UNIDADE', 'SECRETARIA_ESCOLAR', 'PROFESSOR']::text[], false, '{}'::text[], array['Ajudar colegas na chamada e no diário', 'Gerar o QR de vínculo', 'Conduzir a chamada de teste de 03/02']::text[], 2.5)
on conflict (id) do nothing;
insert into iara.iaraflix_aulas (id, trilha_id, ordem, titulo, resumo, pratica) values
  ('bdf6ff1c-e486-0e34-b3a0-f4295d858d4f', 'multiplicadores', 1, 'Boas-vindas à trilha', 'O papel do multiplicador e o calendário até 04/02', null),
  ('84ca8f08-6d08-8857-9b3f-21a0b76b1fff', 'multiplicadores', 2, 'A plataforma na unidade', 'O que cada perfil da unidade faz', null),
  ('81e45624-9835-64e0-1320-c3a7d046d131', 'multiplicadores', 3, 'Chamada e diário', 'Como o professor faz e como ajudar no dia 1', 'Fazer uma chamada e registrar uma aula'),
  ('8083c52b-964c-8948-64b9-ce885678d2ac', 'multiplicadores', 4, 'Matrícula e vínculo pelo QR', 'O caminho da secretaria e o QR do WhatsApp', 'Gerar um QR de vínculo'),
  ('5191169a-eeea-16fd-bdfb-bc536264b14f', 'multiplicadores', 5, 'Conversas e pendências da unidade', 'Como a unidade atende as conversas que a IARA passa para uma pessoa e onde cada colega vê as próprias pendências.', null),
  ('f5070335-f162-5d67-a680-08ff6a37f2e6', 'multiplicadores', 6, 'Ajudar sem expor dados', 'Não usar a senha do colega, não fotografar a tela, sigilo de AEE e de ocorrências', null),
  ('de4ea51c-04c1-6543-ece8-35a14c73602c', 'multiplicadores', 7, 'Dia 1', 'Chamada de teste em 03/02, plantão, plano de volta e como acionar o suporte', null)
on conflict (id) do nothing;
insert into iara.iaraflix_perguntas (id, trilha_id, ordem, enunciado, opcoes, correta, explicacao) values
  ('3bc10497-8013-262f-2187-b0083900c1cf', 'multiplicadores', 1, 'Um colega esqueceu a senha no primeiro dia. Como o multiplicador ajuda?', array['Empresta a própria conta', 'Aciona o suporte para recuperar o acesso do colega', 'Faz a chamada por ele']::text[], 1, 'O multiplicador orienta e aciona o suporte, mas nunca usa nem empresta conta.'),
  ('77ec0142-1e2f-e021-dea6-7c712b40a49c', 'multiplicadores', 2, 'Posso fotografar a tela para tirar uma dúvida com o suporte?', array['Sim, sempre', 'Não: descreva o problema ou abra um chamado, sem expor dados', 'Só se for de um aluno']::text[], 1, 'Foto de tela com dados de alunos é vazamento. O chamado de suporte basta.'),
  ('1f8e4e19-b917-80d4-e04c-67c552f9f53e', 'multiplicadores', 3, 'Quem gera o QR que confirma o WhatsApp da família?', array['A secretaria da escola, com o documento conferido', 'A própria família, sozinha', 'O professor']::text[], 0, 'O QR de vínculo é gerado pela secretaria depois de conferir o documento do responsável.')
on conflict (id) do nothing;

insert into iara.iaraflix_trilhas (id, ordem, titulo, publico, objetivo, perfis, obrigatoria, staff_roles, saber, carga_horaria) values
  ('diretores', 12, 'Diretores', 'Diretores das unidades da rede', 'Preparar cada diretor para conduzir a unidade na virada e acompanhar a equipe pelas pendências.', array['DIRETOR_UNIDADE']::text[], true, '{}'::text[], array['Acompanhar as pendências da equipe', 'Tratar ocorrências e busca ativa', 'Preparar a unidade para o dia 1']::text[], 2.5)
on conflict (id) do nothing;
insert into iara.iaraflix_aulas (id, trilha_id, ordem, titulo, resumo, pratica) values
  ('c93b4900-f1a7-5674-1dea-32124ee2b92f', 'diretores', 1, 'Boas-vindas com o Secretário', 'Por que a mudança e o papel do diretor', null),
  ('0c58c7ed-3de8-aacb-e7e0-125f1c34a2a6', 'diretores', 2, 'O que muda e quando', 'Onda 1 na rede em 01/02, vida escolar em 04/02, fila oficial em 11/02, ondas 3 e 4 em 18/02', null),
  ('f6194003-8f0a-3cc0-157b-023266ecabf7', 'diretores', 3, 'Minha unidade e pendências', 'Painel da unidade, pendências da equipe, atrasadas e cobrança', 'No celular: abrir as pendências da unidade'),
  ('a682e5ad-35ad-24c9-2bfe-cc3ee6be88e5', 'diretores', 4, 'Famílias', 'Conversas da unidade e prazos; vínculo pelo QR feito pela secretaria; bilhete e cartaz às famílias em 02/02', null),
  ('8ae13f1f-1149-dd65-7117-bafa806cc5a3', 'diretores', 5, 'Vida escolar sob a direção', 'Frequência e busca ativa, ocorrências em 1ª instância, reuniões com responsáveis, guarda e restrições', 'Acompanhar um alerta de faltas seguidas'),
  ('496b4a5b-24c7-9697-9070-874157dad894', 'diretores', 6, 'Dados e responsabilidade', 'O que o diretor vê, sigilo, termo de responsabilidade, desligamentos avisados ao RH', null),
  ('8ffff24c-ba8f-96e0-8d47-e9ef4c35c120', 'diretores', 7, 'Dia 1 e plantão', 'Multiplicador, chamada de teste em 03/02, plano de volta e suporte', null)
on conflict (id) do nothing;
insert into iara.iaraflix_perguntas (id, trilha_id, ordem, enunciado, opcoes, correta, explicacao) values
  ('39838e6f-3ebf-e492-269c-d7f6094cc35b', 'diretores', 1, 'Onde o diretor acompanha o que a equipe tem a cumprir?', array['Em Pendências da unidade', 'No Mural', 'No Mapa']::text[], 0, 'As pendências da unidade mostram o que cada pessoa da equipe tem a cumprir e o que atrasou.'),
  ('5837e373-da61-3aa6-5ca8-305f9f56b51c', 'diretores', 2, 'Quem trata uma ocorrência em 1ª instância?', array['A direção da unidade', 'O Prefeito', 'A família']::text[], 0, 'A ocorrência começa na unidade; só sobe se precisar.'),
  ('165a85b3-39f2-7d17-78bc-3c097a43e202', 'diretores', 3, 'Um servidor da unidade foi desligado. O que o diretor faz?', array['Avisa o RH, para a conta ser desativada no mesmo dia', 'Deixa a conta ativa até o fim do mês', 'Nada']::text[], 0, 'Conta de quem saiu é desativada no mesmo dia: o diretor avisa o RH.')
on conflict (id) do nothing;

insert into iara.iaraflix_trilhas (id, ordem, titulo, publico, objetivo, perfis, obrigatoria, staff_roles, saber, carga_horaria) values
  ('secretaria-escolar', 13, 'Secretaria escolar', 'Secretarias escolares das unidades', 'Cuidar do cadastro, das matrículas, dos documentos e das conversas da unidade.', array['SECRETARIA_ESCOLAR']::text[], true, '{}'::text[], array['Manter o cadastro completo', 'Validar documentos', 'Gerar o QR de vínculo', 'Atender as conversas da unidade']::text[], 3.5)
on conflict (id) do nothing;
insert into iara.iaraflix_aulas (id, trilha_id, ordem, titulo, resumo, pratica) values
  ('02864fd6-0bc5-dd6b-78a9-667ab8d6f7a4', 'secretaria-escolar', 1, 'Boas-vindas à trilha', 'O que esta trilha cobre e o que você vai conseguir fazer ao final: manter o cadastro completo; validar documentos; gerar o QR de vínculo; atender as conversas da unidade.', null),
  ('2bff0946-63f2-0a8c-16d4-fdb3b5ee7534', 'secretaria-escolar', 2, 'Cadastro do aluno e do responsável', 'Ficha completa, pendências, vínculos e endereço', 'Completar a ficha de um aluno'),
  ('45d5cfff-c3c7-05bf-b724-9fb4c2b87fca', 'secretaria-escolar', 3, 'Documentos e validações', 'Documentos enviados pela família; validar ou recusar com motivo e orientação', 'Validar um documento e recusar outro'),
  ('a52cf094-a70a-0cf1-718b-7652362e94cd', 'secretaria-escolar', 4, 'WhatsApp confirmado na escola', 'QR com documento conferido, troca de número e revogação', 'Gerar o QR para um colega'),
  ('59fecd4c-3949-1304-cc4c-3868b9dbb527', 'secretaria-escolar', 5, 'Matrículas e ofertas', 'Oferta da Central, matrícula, rematrícula e transferência', 'Confirmar uma matrícula'),
  ('af369051-86cf-d2fe-af79-c9415d468f43', 'secretaria-escolar', 6, 'Conversas da unidade', 'Filas do WhatsApp da secretaria: assumir, responder, transferir, prazos', 'Atender a Maria pela fila de conversas'),
  ('6ef14e25-dd19-a432-ead9-fe7dd3887e67', 'secretaria-escolar', 7, 'Declarações e verificação', 'Declaração de matrícula, frequência e fila com código e QR', 'Emitir uma declaração e verificá-la'),
  ('aa14a4c3-b18c-a44d-48f2-41b6287d893f', 'secretaria-escolar', 8, 'Frequência e justificativas', 'Justificativas da família, alertas e busca ativa', null),
  ('3f65cfd8-0ccf-da4e-721b-6490bc1d94b7', 'secretaria-escolar', 9, 'Guarda e restrições', 'Quem pode buscar a criança, alerta na ficha e sigilo', null),
  ('b844cf7d-bd38-5bd2-d619-374dd601cee7', 'secretaria-escolar', 10, 'Pendências e dia 1', 'Pendências da secretaria; piloto em 29/01 e rede em 01/02', null)
on conflict (id) do nothing;
insert into iara.iaraflix_perguntas (id, trilha_id, ordem, enunciado, opcoes, correta, explicacao) values
  ('ab0e512b-6788-d405-9848-05d5e06fcbea', 'secretaria-escolar', 1, 'Ao recusar um documento enviado pela família, a secretaria...', array['só recusa', 'informa o motivo e orienta como enviar de novo', 'apaga sem avisar']::text[], 1, 'A família recebe o motivo e a orientação pelo portal e pela IARA.'),
  ('d8fe1041-2e34-3afe-da0d-3a7fbf5d4e08', 'secretaria-escolar', 2, 'O QR que confirma o WhatsApp da família é gerado...', array['depois de conferir o documento do responsável', 'para qualquer pessoa que pedir', 'por telefone']::text[], 0, 'O QR só sai com o documento conferido na secretaria.'),
  ('29458abb-14ec-ca5d-ed24-a33b6964c745', 'secretaria-escolar', 3, 'Como alguém confere se uma declaração emitida é verdadeira?', array['Pelo código ou pelo QR, na página Verificar documento', 'Ligando para a escola', 'Não tem como']::text[], 0, 'Toda declaração tem código e QR, conferidos na página pública de verificação.')
on conflict (id) do nothing;

insert into iara.iaraflix_trilhas (id, ordem, titulo, publico, objetivo, perfis, obrigatoria, staff_roles, saber, carga_horaria) values
  ('professores', 14, 'Professores', 'Professores e educadores da rede', 'Fazer a chamada, registrar as aulas e falar com as famílias a partir do primeiro dia de aula.', array['PROFESSOR']::text[], true, array['PROFESSOR', 'EDUCADOR']::text[], array['Fazer a chamada do dia', 'Registrar a aula no diário', 'Mandar recado e registrar ocorrência']::text[], 2.5)
on conflict (id) do nothing;
insert into iara.iaraflix_aulas (id, trilha_id, ordem, titulo, resumo, pratica) values
  ('777eacc1-1ca3-d1e7-c54a-f6d48f061ec3', 'professores', 1, 'Boas-vindas à trilha', 'O que muda em 04/02 e onde pedir ajuda (multiplicador e suporte)', null),
  ('39f48d81-ba41-e141-b895-440a5389d293', 'professores', 2, 'Entrar e se localizar', 'Login, Minhas turmas e Pendências', null),
  ('ff38ecd6-eaf5-9e58-d526-6d9be76930ab', 'professores', 3, 'Chamada do dia', 'Tocar em quem faltou, corrigir, justificativas da família, alerta de faltas seguidas', 'Fazer a chamada da turma no celular'),
  ('49962665-49c9-c299-ef9c-37ab86102748', 'professores', 4, 'Diário de classe', 'Registrar a aula (conteúdo, habilidade da BNCC, tarefa) e ver as aulas sem registro', 'Registrar a aula de hoje'),
  ('baa32b67-e9c0-399b-1343-c0780be1e0d0', 'professores', 5, 'Notas, pareceres e alfabetização', 'Notas por bimestre, pareceres na educação infantil e sondagem do 1º e 2º ano', null),
  ('9ad744a7-e9c6-0fab-6598-9c1d633d4eaa', 'professores', 6, 'Agenda, mural, ocorrências e reuniões', 'Recado à família com ciência, ocorrência com gravidade, reunião com o responsável', 'Mandar um recado à família da Ana Luísa'),
  ('ee2b71ae-d6be-9437-470d-f72c562729ad', 'professores', 7, 'Dados e sigilo', 'Não fotografar a tela; no AEE, o professor regente vê as orientações e os recursos, nunca o diagnóstico.', null)
on conflict (id) do nothing;
insert into iara.iaraflix_perguntas (id, trilha_id, ordem, enunciado, opcoes, correta, explicacao) values
  ('3a3cb94d-01dc-0169-5eea-480a84083a85', 'professores', 1, 'Na chamada do dia, você...', array['toca em quem faltou', 'marca um por um quem veio', 'entrega a lista em papel']::text[], 0, 'Todos começam presentes: basta tocar em quem faltou.'),
  ('4fe9fba5-3e5c-eb30-9833-ec350d454857', 'professores', 2, 'No diário de classe, o que você registra?', array['O conteúdo, a habilidade da BNCC e a tarefa', 'Só a presença', 'Só a nota']::text[], 0, 'O registro da aula leva o conteúdo, a habilidade da BNCC e a tarefa de casa.'),
  ('30c72fd6-6e75-6f87-4919-05f4d7478246', 'professores', 3, 'Sobre um aluno do AEE, o professor regente vê...', array['o diagnóstico completo', 'as orientações e os recursos, nunca o diagnóstico', 'nada']::text[], 1, 'O regente recebe o que precisa para a sala; o diagnóstico fica protegido.')
on conflict (id) do nothing;

insert into iara.iaraflix_trilhas (id, ordem, titulo, publico, objetivo, perfis, obrigatoria, staff_roles, saber, carga_horaria) values
  ('aee-apoio', 15, 'AEE e apoio interdisciplinar', 'Professores do AEE e equipe de apoio interdisciplinar', 'Conduzir o plano de AEE e os casos de apoio, protegendo os dados de saúde.', array['PROFESSOR_AEE', 'APOIO_INTERDISCIPLINAR', 'GERENCIA_APOIO']::text[], true, array['AEE', 'APOIO']::text[], array['Montar e revisar o plano de AEE', 'Registrar atendimentos', 'Guardar o sigilo dos registros técnicos']::text[], 2.0)
on conflict (id) do nothing;
insert into iara.iaraflix_aulas (id, trilha_id, ordem, titulo, resumo, pratica) values
  ('65bbd665-fb8d-f006-ad98-58455d26ccd3', 'aee-apoio', 1, 'Boas-vindas à trilha', 'O que esta trilha cobre e o que você vai conseguir fazer ao final: montar e revisar o plano de AEE; registrar atendimentos; guardar o sigilo dos registros técnicos.', null),
  ('611206ff-74f1-115e-ed84-7dfd030cf50c', 'aee-apoio', 2, 'Meus alunos e plano de AEE', 'Avaliação inicial, objetivos, recursos, orientações para a sala e revisão', 'Completar um plano de AEE'),
  ('19c4aa58-0fc0-c809-35ba-fbb2bf94210b', 'aee-apoio', 3, 'Atendimentos', 'Presença em um toque; sala de recursos, itinerante e domiciliar', 'Registrar um atendimento'),
  ('84d62f18-f62d-61a0-7dec-268856871219', 'aee-apoio', 4, 'Família e professor regente', 'Ciência da família; o regente vê só as orientações e os recursos', null),
  ('2f32346d-f1e1-17ad-c4e2-97650457a5e3', 'aee-apoio', 5, 'Apoio interdisciplinar', 'Encaminhamento da escola, pedido da família, análise e registro técnico sigiloso (só autor e chefia)', 'Registrar um caso de apoio')
on conflict (id) do nothing;
insert into iara.iaraflix_perguntas (id, trilha_id, ordem, enunciado, opcoes, correta, explicacao) values
  ('e4914617-1c40-b7c0-d9d6-7083babadce8', 'aee-apoio', 1, 'O registro técnico do apoio interdisciplinar é visto por...', array['toda a escola', 'só o autor e a chefia', 'a família e o professor']::text[], 1, 'O registro técnico é sigiloso: só o autor e a chefia.'),
  ('1872c45a-3542-58c5-50d6-eb0d36cab9e4', 'aee-apoio', 2, 'O plano de AEE começa pela...', array['avaliação inicial', 'nota do bimestre', 'lista de material']::text[], 0, 'A avaliação inicial orienta os objetivos, os recursos e as orientações para a sala.'),
  ('e4c3d122-028c-cfea-336e-6957e9e1717d', 'aee-apoio', 3, 'Como se registra a presença no atendimento do AEE?', array['Em um toque', 'No papel', 'Pelo diretor']::text[], 0, 'A presença do atendimento é registrada em um toque.')
on conflict (id) do nothing;

-- Demonstração ----------------------------------------------------------------------------------------------------------------------
-- adesão fictícia: parte dos professores, educadores, AEE e apoio do cadastro de demonstração já concluiu ou está fazendo a trilha.
-- A taxa varia por unidade, para o painel mostrar quem precisa de atenção. Só roda com o modo demonstração ligado.
create or replace function iara.demo_gerar_iaraflix() returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_n integer;
begin
  perform iara.exigir_demo();
  perform setseed(0.1411);
  delete from iara.iaraflix_participacoes where is_demo and user_id is null;
  with base as (
    select st.id, st.full_name, st.role, st.unit_id, t.id trilha_id,
           (select count(*) from iara.iaraflix_aulas a where a.trilha_id = t.id and a.situacao = 'PUBLICADA') total,
           (select count(*) from iara.iaraflix_perguntas q where q.trilha_id = t.id) nq,
           random() r, random() r2, random() r3,
           case when t.id = 'primeiros-passos' then 0.62 else 0.37 end + ((coalesce(st.unit_id, 0) * 37) % 41 - 20) / 100.0 lim_c
    from iara.staff st
    join iara.iaraflix_trilhas t on st.role = any (t.staff_roles) and t.situacao = 'PUBLICADA'
    where st.is_demo and coalesce(st.situacao, 'ATIVO') = 'ATIVO'),
  sorteio as (
    select b.*, b.r < b.lim_c concluiu, now() - interval '1 day' * (3 + floor(b.r2 * 27)) inicio
    from base b where b.r < b.lim_c + 0.26 and b.total > 0)
  insert into iara.iaraflix_participacoes (trilha_id, staff_id, nome, role_code, unit_id, aulas_concluidas, iniciada_em, concluida_em,
                                          tentativas, acertos, perguntas, certificado_codigo, certificado_hash, is_demo)
  select s.trilha_id, s.id, s.full_name,
         case s.role when 'AEE' then 'PROFESSOR_AEE' when 'APOIO' then 'APOIO_INTERDISCIPLINAR' else 'PROFESSOR' end, s.unit_id,
         case when s.concluiu then s.total else greatest(1, least(s.total - 1, floor(s.r3 * s.total)))::integer end,
         s.inicio,
         case when s.concluiu then s.inicio + (now() - s.inicio) * (0.2 + 0.8 * s.r3) end,
         case when s.concluiu then 1 + (s.r2 < 0.3)::integer else 0 end,
         case when s.concluiu then s.nq end, case when s.concluiu then s.nq end,
         case when s.concluiu then iara.declaracao_codigo() end,
         case when s.concluiu then encode(sha256(convert_to(s.id::text || s.trilha_id || 'demo', 'UTF8')), 'hex') end,
         true
  from sorteio s;
  get diagnostics v_n = row_count;
  return jsonb_build_object('participacoes', v_n);
end $$;

-- o que as sessões de demonstração (personas) assistiram e concluíram; a adesão gerada fica
create or replace function iara.demo_purge_iaraflix(p_desde timestamptz default null) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  v_a integer;
  v_p integer;
begin
  delete from iara.iaraflix_progresso pr using iara.app_users u
  where u.id = pr.user_id and u.auth_provider = 'DEMO' and pr.atualizado_em >= coalesce(p_desde, '-infinity'::timestamptz);
  get diagnostics v_a = row_count;
  delete from iara.iaraflix_participacoes pa using iara.app_users u
  where u.id = pa.user_id and u.auth_provider = 'DEMO' and pa.iniciada_em >= coalesce(p_desde, '-infinity'::timestamptz);
  get diagnostics v_p = row_count;
  return jsonb_build_object('aulas', v_a, 'participacoes', v_p);
end $$;

create or replace function api.demo_apresentacao_limpar(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = iara, public
as $$
declare
  r jsonb;
begin
  perform iara.require_perm('demo.manage');
  perform iara.exigir_demo();
  r := iara.demo_purge_session_data(null, null);
  r := r || jsonb_build_object('vida_escolar', iara.demo_purge_sprint1(null), 'pedagogico', iara.demo_purge_sprint2(null),
                               'transporte_almoxarifado', iara.demo_purge_sprint3(null), 'busca_ativa', iara.demo_purge_busca_ativa(null),
                               'ocorrencias', iara.demo_purge_ocorrencias(null), 'gestao', iara.demo_purge_gestao(null),
                               'sprint4', iara.demo_purge_sprint4(null), 'sprint5', iara.demo_purge_sprint5(null),
                               'reunioes', iara.demo_purge_reunioes(null),
                               'uniformes', iara.demo_purge_uniformes(null), 'apoio', iara.demo_purge_apoio(null),
                               'pendencias', iara.demo_purge_pendencias(null),
                               'acesso_familias', iara.demo_purge_acesso_familias(null),
                               'iaraflix', iara.demo_purge_iaraflix(null),
                               'arquivos', iara.demo_limpar_arquivos_vivos(null));
  return jsonb_build_object('ok', true, 'resultado', r, 'situacao', api.demo_apresentacao_situacao('{}'::jsonb));
end $$;

revoke all on function iara.demo_gerar_iaraflix(), iara.demo_purge_iaraflix(timestamptz) from public;

do $$ begin
  if iara.demo_mode() then perform iara.demo_gerar_iaraflix(); end if;
end $$;

commit;
