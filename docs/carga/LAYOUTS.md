# IARA Educa — layouts dos arquivos de carga

CSV em UTF-8 (ou Windows-1252), separador `;` ou `,`, uma linha de cabeçalho com os nomes abaixo.
Datas: AAAA-MM-DD ou DD/MM/AAAA. Sim/não: S ou N. Códigos (chaves) estáveis: não mudam de uma carga para outra.
Ordem de envio: UNIDADES → TURMAS → SERVIDORES → RESPONSAVEIS → ALUNOS → VINCULOS → MATRICULAS → FILA.

## UNIDADES

| Campo | Tipo | Obrigatório | Descrição | Exemplo |
|---|---|---|---|---|
| `codigo_unidade` (chave) | texto | sim | Código estável da unidade no sistema oficial da SEDUC (não muda de um ano para outro) | SEDUC-0042 |
| `codigo_inep` | texto | não | Código INEP da unidade (8 dígitos) | 41100123 |
| `nome` | texto | sim | Nome oficial da unidade | CMEI Galdino de Andrade |
| `nome_curto` | texto | não | Nome curto para listas e mapas | Galdino de Andrade |
| `tipo` | lista: CMEI, ESCOLA | sim | Natureza da unidade (conveniadas e a Secretaria entram na etapa P1) | CMEI |
| `logradouro` | texto | não | Rua/avenida | Rua das Flores |
| `numero` | texto | não | Número | 120 |
| `bairro` | texto | não | Bairro | Zona 7 |
| `cep` | cep | não | CEP (8 dígitos) | 87020-000 |
| `lat` | coordenada | sim | Latitude (graus decimais) | -23.4210 |
| `lng` | coordenada | sim | Longitude (graus decimais) | -51.9331 |
| `telefone` | telefone | não | Telefone da unidade | (44) 3222-0000 |
| `diretor` | texto | não | Nome da direção | Ana Souza |
| `situacao` | lista: ATIVA, A_VALIDAR, SEM_TURMAS | não | Situação da unidade (padrão: ATIVA) | ATIVA |

## TURMAS

| Campo | Tipo | Obrigatório | Descrição | Exemplo |
|---|---|---|---|---|
| `codigo_turma` (chave) | texto | sim | Código estável da turma na fonte oficial | T2026-0042-PREA |
| `codigo_unidade` | texto | sim | Unidade da turma (código da fonte ou código INEP) | SEDUC-0042 |
| `ano_letivo` | inteiro | sim | Ano letivo | 2026 |
| `serie` | lista: CRECHE, PRE, EF1, EF2, EF3, EF4, EF5, EJA_AI | sim | Série/faixa | PRE |
| `nome` | texto | sim | Nome da turma | Pré-escola A |
| `turno` | lista: MANHA, TARDE, NOITE, INTEGRAL | sim | Turno | TARDE |
| `sala` | texto | não | Sala física | Sala 04 |
| `capacidade_autorizada` | inteiro | sim | Capacidade autorizada (vagas) | 24 |
| `situacao` | lista: ATIVA, EM_REORGANIZACAO, ENCERRADA | não | Situação (padrão: ATIVA) | ATIVA |

## SERVIDORES

| Campo | Tipo | Obrigatório | Descrição | Exemplo |
|---|---|---|---|---|
| `matricula_funcional` (chave) | texto | sim | Matrícula funcional (RH) | 123456 |
| `nome` | texto | sim | Nome completo | Daniela Nunes Andrade |
| `codigo_unidade` | texto | não | Unidade de lotação (código da fonte ou INEP) | SEDUC-0042 |
| `funcao` | lista: PROFESSOR, EDUCADOR, AUXILIAR, APOIO, AEE, ESTAGIARIO, SUBSTITUTO | sim | Função | PROFESSOR |
| `vinculo` | texto | não | Tipo de vínculo (efetivo, PSS...) | Efetivo |

## RESPONSAVEIS

| Campo | Tipo | Obrigatório | Descrição | Exemplo |
|---|---|---|---|---|
| `codigo_responsavel` (chave) | texto | sim | Código estável do responsável na fonte oficial | R-000123 |
| `nome` | texto | sim | Nome completo | Maria Santos Oliveira |
| `cpf` | cpf | não | CPF (inválido é descartado com aviso) | 123.456.789-09 |
| `nis` | nis | não | NIS/PIS (inválido é descartado com aviso) | 12345678919 |
| `rg` | texto | não | RG | 12.345.678-9 |
| `data_nascimento` | data | não | Data de nascimento (AAAA-MM-DD ou DD/MM/AAAA) | 15/04/1990 |
| `sexo` | lista: F, M | não | Sexo | F |
| `email` | email | não | E-mail | maria@exemplo.com |
| `telefone` | telefone | não | Telefone principal | (44) 99999-0000 |
| `whatsapp` | telefone | não | WhatsApp | (44) 99999-0000 |
| `estado_civil` | texto | não | Estado civil | Solteira |
| `escolaridade` | texto | não | Escolaridade | Médio completo |
| `ocupacao` | texto | não | Ocupação | Auxiliar administrativa |
| `renda_familiar` | decimal | não | Renda familiar mensal (R$) | 2500,00 |
| `cadunico` | sim_nao | não | Inscrição ativa no CadÚnico (S/N) | S |
| `mae_solo` | sim_nao | não | Mãe solo declarada (S/N) | N |
| `pessoas_domicilio` | inteiro | não | Pessoas no domicílio | 4 |
| `logradouro` | texto | não | Rua/avenida da residência | Rua das Flores |
| `numero` | texto | não | Número | 120 |
| `complemento` | texto | não | Complemento | Apto 2 |
| `bairro` | texto | não | Bairro | Zona 7 |
| `cep` | cep | não | CEP | 87020-000 |
| `lat` | coordenada | não | Latitude da residência (vazio: geocodificar depois) | -23.4210 |
| `lng` | coordenada | não | Longitude da residência | -51.9331 |

## ALUNOS

| Campo | Tipo | Obrigatório | Descrição | Exemplo |
|---|---|---|---|---|
| `codigo_aluno` (chave) | texto | sim | Registro permanente do aluno na fonte oficial (não muda entre anos) | A-2024-000123 |
| `nome` | texto | sim | Nome completo | Davi Santos Oliveira |
| `nome_social` | texto | não | Nome social |  |
| `data_nascimento` | data | sim | Data de nascimento | 2022-05-10 |
| `sexo` | lista: F, M | não | Sexo | M |
| `cor_raca` | lista: BRANCA, PRETA, PARDA, AMARELA, INDIGENA, NAO_DECLARADA | não | Cor/raça (declarada) | PARDA |
| `cpf` | cpf | não | CPF da criança |  |
| `nis` | nis | não | NIS da criança |  |
| `certidao_nascimento` | texto | não | Matrícula da certidão de nascimento |  |
| `cartao_sus` | texto | não | Cartão SUS |  |
| `codigo_inep_aluno` | texto | não | ID do aluno no Censo/INEP |  |
| `nacionalidade` | lista: BRASILEIRA, NATURALIZADA, ESTRANGEIRA | não | Nacionalidade | BRASILEIRA |
| `nome_mae` | texto | não | Filiação 1 | Maria Santos Oliveira |
| `nome_pai` | texto | não | Filiação 2 |  |
| `logradouro` | texto | não | Rua/avenida da residência | Rua das Flores |
| `numero` | texto | não | Número | 120 |
| `complemento` | texto | não | Complemento |  |
| `bairro` | texto | não | Bairro | Zona 7 |
| `cep` | cep | não | CEP | 87020-000 |
| `lat` | coordenada | não | Latitude da residência (vazio: geocodificar depois) | -23.4210 |
| `lng` | coordenada | não | Longitude da residência | -51.9331 |
| `transporte` | sim_nao | não | Usa ou precisa de transporte escolar (S/N) | N |
| `aee` | sim_nao | não | Atendimento educacional especializado (S/N) — o laudo entra em etapa própria, protegida | N |

## VINCULOS

| Campo | Tipo | Obrigatório | Descrição | Exemplo |
|---|---|---|---|---|
| `codigo_aluno` | texto | sim | Aluno (código da fonte, já carregado) | A-2024-000123 |
| `codigo_responsavel` | texto | sim | Responsável (código da fonte, já carregado) | R-000123 |
| `parentesco` | lista: MAE, PAI, AVO, TIA, TIO, IRMAO, PADRASTO, MADRASTA, TUTOR_LEGAL, OUTRO | sim | Parentesco | MAE |
| `principal` | sim_nao | não | Responsável principal (S/N) | S |
| `pode_buscar` | sim_nao | não | Pode buscar a criança (S/N) | S |
| `recebe_avisos` | sim_nao | não | Recebe avisos (S/N) | S |
| `situacao_legal` | lista: CONFIRMADO, DECLARADO | não | Situação da autoridade legal (padrão: DECLARADO) | CONFIRMADO |
| `inicio` | data | não | Início do vínculo | 2024-02-01 |
| `fim` | data | não | Fim do vínculo (vazio = vigente) |  |

## MATRICULAS

| Campo | Tipo | Obrigatório | Descrição | Exemplo |
|---|---|---|---|---|
| `codigo_matricula` (chave) | texto | sim | Código da matrícula do ano na fonte oficial | M2026-000987 |
| `codigo_aluno` | texto | sim | Aluno (código da fonte, já carregado) | A-2024-000123 |
| `codigo_turma` | texto | sim | Turma (código da fonte, já carregada) | T2026-0042-PREA |
| `ano_letivo` | inteiro | sim | Ano letivo | 2026 |
| `situacao` | lista: ATIVA, PRE_MATRICULA, TRANSFERENCIA_PENDENTE, TRANSFERIDA, CANCELADA, CONCLUIDA, INATIVA | sim | Situação da matrícula | ATIVA |
| `data_matricula` | data | não | Data da matrícula | 2026-01-20 |
| `inicio` | data | não | Início das aulas na turma | 2026-02-02 |
| `fim` | data | não | Saída da turma |  |
| `tipo_entrada` | lista: NOVA, RENOVACAO, TRANSFERENCIA, OFERTA_FILA | não | Como entrou | RENOVACAO |

## FILA

| Campo | Tipo | Obrigatório | Descrição | Exemplo |
|---|---|---|---|---|
| `codigo_inscricao` (chave) | texto | sim | Código da inscrição na Central de Vagas | F-2026-004512 |
| `codigo_aluno` | texto | sim | Criança (código da fonte, já carregada) | A-2025-000456 |
| `codigo_unidade` | texto | sim | Unidade pretendida (código da fonte ou INEP) | SEDUC-0042 |
| `serie` | lista: CRECHE, PRE, EF1, EF2, EF3, EF4, EF5, EJA_AI | sim | Série/faixa pretendida | CRECHE |
| `turno_preferido` | lista: MANHA, TARDE, INTEGRAL | não | Turno preferido | INTEGRAL |
| `integral` | sim_nao | não | Pede período integral (S/N) | S |
| `categoria` | lista: SEM_ATENDIMENTO, AGUARDA_TRANSFERENCIA, PARCIAL_PARA_INTEGRAL, UNIDADE_PREFERENCIAL, RECUSOU_OFERTA, DEMANDA_FUTURA | não | Categoria da demanda (padrão: SEM_ATENDIMENTO) | SEM_ATENDIMENTO |
| `data_solicitacao` | data_hora | sim | Data e hora da solicitação — desempate da IN nº 025/2025 | 2026-03-04 09:15 |
| `posicao_oficial` | inteiro | não | Posição na lista oficial (para conferir a ordem) | 12 |
| `pontuacao_oficial` | decimal | não | Pontuação na lista oficial (para conferir) | 40 |
| `situacao` | lista: AGUARDANDO, SUSPENSA | não | Situação (padrão: AGUARDANDO; ofertas em aberto entram em etapa própria) | AGUARDANDO |
