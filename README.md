# IARA Educa — SEDUC Maringá

Plataforma municipal de gestão educacional da **Secretaria Municipal de Educação de Maringá (SEDUC)**: unidades e território,
turmas e vagas, fila de espera, ofertas e matrícula, atendimento ao cidadão e a **IARA**, agente de atendimento via WhatsApp/portal.
Feita primeiro para o celular: interativa, clicável e com visões diferentes para cada perfil.

> **Ambiente de demonstração.** A base oficial (118 unidades, 1.359 turmas, 31.497 matrículas — Censo Escolar 2025/INEP e
> Consulta Escolas SEED-PR 2026) é real. A camada operacional (capacidades, vagas, fila, protocolos, conversas e pessoas) é
> **fictícia** e identificada como DEMO em todas as telas, até a integração com os sistemas da SEDUC.

## O que tem

| Perfil | Pergunta que a tela responde | Destaques |
|---|---|---|
| Prefeito(a) | Onde precisamos investir? | Mapa coroplético por região, déficit de creche, projeção (cenário), distância casa-escola |
| Secretário(a) / Superintendência / Gerência EI | Onde está o gargalo? | Demanda × oferta por faixa, fila por categoria, funil de ofertas, SLA por equipe |
| Analista da Central de Vagas | Qual vaga posso oferecer agora? | Busca inteligente de vaga, fila com critérios, oferta transacional, caixa da IARA |
| Direção / Secretaria escolar | Como está minha unidade? / O que falta para a matrícula? | Turmas com ocupação, checklist de documentos, confirmação de matrícula |
| Inovação | A base está confiável? | Qualidade de dados, auditoria, indicadores |
| Cidadão / Responsável | Onde meu filho será atendido e o que preciso fazer? | Chat com a IARA (WhatsApp simulado), Minha família, protocolos, unidades próximas |
| Família recém-chegada a Maringá | Como garanto a vaga das crianças? | Cadastro da família, inclusão das crianças e inscrição na fila por transferência de outro município |
| Controle externo · MP e Defensoria | A fila está sendo cumprida, com critérios claros? | Ordem conferida, exceções com justificativa, vagas paradas com fila, prazos, fila pública anonimizada, consulta de caso só por protocolo (registrada) |

**Fluxo completo validado ponta a ponta:** a Central de Vagas oferta a vaga ao 1º da fila → a família aceita pela IARA →
a secretaria escolar valida os documentos → a matrícula é confirmada. Tudo auditado.

### IARA resolutiva: WhatsApp e portal com o mesmo resultado
O munícipe não precisa abrir o portal: tudo o que a família faz em **Minha família** a IARA faz na conversa do WhatsApp,
com as mesmas funções, regras e protocolos — experiências diferentes, mesmo resultado.

- **A IARA resolve na hora** (protocolo encerrado como *resolvido pela IARA*): cadastro da família, chegada de outra cidade
  (transferência externa), nova criança ou novo responsável, mudança de endereço (a fila é recalculada e a família vê o impacto),
  atualização de dados e declarações, inscrição e desistência da fila, posição, ofertas, documentos e dúvidas.
- **Só o que exige decisão humana é encaminhado**, pela **alçada** de cada serviço (`service_catalog.resolution_level`):
  - **Unidade** (secretaria da escola/CMEI onde a criança está matriculada): troca de turno, declarações, matrícula,
    alteração de responsável, documentos;
  - **SEDUC** (equipe responsável): transporte escolar, educação integral, AEE, alimentação especial, recursos e reclamações;
    responsável que não é pai nem mãe vai para a Central de Vagas conferir a guarda.
- Em todos os casos a família recebe protocolo, equipe responsável e prazo. A tela **Conversas** mostra *quem resolve os pedidos*
  (alçada da demanda), as conversas concluídas sem servidor e as execuções da própria IARA.

**Conversas no estilo do WhatsApp** (`#/iara`, menu **Conversas**) — **uma conversa por linha** (contato, com quem está,
última mensagem, protocolo, espera/hora e não lidas); ao abrir uma, ela aparece ao lado (no celular, em tela cheia).
**Atendimento humano = borda vermelha no avatar** (o selo pequeno diz se está aguardando ou em atendimento; roxo = IARA);
a espera fica em vermelho acima do limite. Simulação não é escrita: uma **bandeirinha discreta** sinaliza (vale para
todo o sistema — o selo "demonstração" virou bandeirinha). Quando a IARA passa para humano, a
conversa vai para o **responsável pela alçada**: a secretaria da unidade da criança (protocolo de alçada da unidade ou criança
matriculada) ou a equipe da SEDUC (Central de Vagas, Atendimento ao Cidadão, Ouvidoria…), e a IARA diz à família para onde foi.
- **Unidade** (Direção e Secretaria Escolar): vê só as conversas da própria unidade, assume, responde (a resposta chega no
  WhatsApp da família) e devolve à IARA ou à Secretaria, com motivo.
- **Secretaria** (Atendimento, Central de Vagas, Secretário): vê todas, com faixa de controle (com a IA, aguardando, com
  humano, esperando há mais de 30 min, nas unidades, na SEDUC) e o quadro **Controle por unidade** — aguardando, em
  atendimento, atrasadas, maior espera e tempo médio da 1ª resposta de cada unidade e equipe; transfere para qualquer
  unidade ou equipe. Tudo na auditoria (`CONVERSA_ENCAMINHADA`). API: `api.conversas_lista`, `api.conversas_controle`,
  `api.conversation_transfer`; regras em `supabase/migrations/20261003002800_conversas_unidades.sql`.

**Cadastro 360º de alunos e responsáveis** (menus **Alunos** e **Responsáveis**; arquitetura mestra, cap. 11 e 12) — cada
criança e cada responsável com ficha completa, editável por quem tem permissão e auditada:
- **Aluno:** nome e nome social, nascimento (com a faixa da regra de corte), sexo, cor/raça, nacionalidade e naturalidade (ou país
  de nascimento), certidão de nascimento, CPF, NIS, Cartão SUS, código INEP, filiação, endereço, AEE/acessibilidade/transporte,
  dados sensíveis (saúde, laudo, restrições, observações legais — só perfis com permissão; cada acesso é auditado) e uso de imagem.
- **Responsável:** documentos (CPF, RG, NIS), estado civil, escolaridade, idioma, contatos e canal preferido, trabalho e renda
  (faixa calculada pelo salário mínimo), CadÚnico, benefícios, mãe solo, acessibilidade, consentimentos e **composição familiar**
  (pessoas da casa sem cadastro próprio; renda por pessoa).
- **Vínculos** (cap. 12.1): parentesco, principal, quem pode buscar, quem recebe avisos e situação legal; encerrar não apaga
  (fica no histórico, com motivo) e a criança nunca fica sem responsável.
- **Dados geográficos:** CEP → rua e bairro (ViaCEP); endereço → ponto no mapa (OpenStreetMap; quando o serviço recusa o
  servidor em nuvem, o navegador consulta direto); o servidor confere/ajusta o ponto tocando no mapa. Cada endereço guarda
  precisão e fonte, zona, ponto de referência, território (macrorregião/distrito pelo polígono) e mostra o bairro de referência
  e as unidades mais próximas com vagas na faixa da criança. Só o endereço sai do sistema — nunca nome ou CPF.
- **Pendências:** cada ficha mostra o % completo e o que falta (aluno: 7 itens do Censo/matrícula; responsável: 5); as listas
  (um registro por linha, em colunas; em tela estreita rolam de lado com o nome fixo) filtram por situação, unidade,
  território e pendência. Mudança de endereço do responsável leva junto as crianças que moram
  com ele e recalcula a fila. Unidade vê só os seus alunos (e os que ela cadastrou); CPF e contatos mascarados conforme o perfil.
- API: `api.alunos_lista`, `api.responsaveis_lista`, `api.aluno_cadastro`, `api.aluno_salvar`, `api.responsavel_cadastro`,
  `api.responsavel_salvar`, `api.vinculo_salvar`, `api.vinculo_encerrar`, `api.domicilio_salvar`, `api.localizar_ponto` e a
  rota do gateway `POST /geo/localizar`; regras em `supabase/migrations/20261003003000_cadastro_pessoas.sql`. A base fictícia
  tem os campos novos preenchidos (documentos fictícios com dígito verificador propositalmente inválido).

**WhatsApp de verdade** — a pasta [`whatsapp-ponte/`](whatsapp-ponte/README.md) liga um número ao agente (ponte Baileys →
gateway `/whatsapp/...` → o mesmo agente do portal, com as opções em lista numerada). O número registrado é o chip da
IARA Saúde, **+55 44 99774-8259**: cada sistema tem a sua ponte e liga-se um de cada vez (`npm run whatsapp` liga a da
Educação; `Ctrl+C` desliga). O painel **WhatsApp da IARA** (Secretário/Inovação) mostra a ponte e tem o interruptor; com o
canal ligado, o QR code do portal passa a abrir esse WhatsApp. Resposta de servidor na Caixa da IARA e avisos de oferta
saem pela fila de saída. A IARA também **ouve áudios** (Whisper na Groq, como na IARA Saúde) depois de gravar a chave com
`scripts\guardar-chave-groq.ps1`. Teste sem celular: `node whatsapp-ponte/simular.mjs --ligar +5544900001234 "oi" "2"`.

**Início da conversa pelo WhatsApp** — QR code, número e link de conversa no portal da família (início, cadastro,
Minha família, chat da IARA), na tela de entrada, na Ajuda, na página pública `#/whatsapp` e no cartaz A4 para imprimir
(`#/whatsapp/cartaz`), com "Compartilhar com a família" para os demais responsáveis. Enquanto a SEDUC não define o número
oficial, o número exibido é de demonstração e o QR code/link abrem a conversa simulada da IARA (nunca um `wa.me` para
número fictício). Para ativar o número oficial, sem novo deploy:
`update iara.tenants set settings = settings || '{"iara_whatsapp_numero": "55449XXXXXXXX"}' where id = 1;` — a partir daí o
QR code e o link viram `https://wa.me/<número>?text=<mensagem>` (mensagem em `iara_whatsapp_mensagem`).

### Controle externo: Ministério Público e Defensoria Pública
Perfil próprio, **somente leitura e sem dados pessoais** (escopo agregado, permissão `controle.read`), para quem fiscaliza o
direito à vaga — a mesma visão fica disponível para o(a) Secretário(a) e a Superintendência ("o que o controle externo vê").

- **Painel** (`#/inicio` do perfil, `#/controle` para a Secretaria): ordem conferida em cada fila (posição registrada = posição
  calculada pela regra), crianças aguardando e tempo de espera por faixa, **vagas ofertáveis paradas em filas com crianças**,
  ofertas × ordem da fila em 12 meses (ao 1º da fila, em outra unidade, fora da ordem por laudo), aceites, recusas, ofertas
  expiradas (silêncio não é aceite), protocolos com prazo vencido, saldo por região, as três medidas de distância e a
  **trilha de governança** (mudanças de regra, exceções, recálculos e as próprias consultas do controle externo).
- **Exceções à ordem** vêm da auditoria imutável, com a justificativa registrada pela equipe — CIDs, CPFs e nomes são ocultados.
- **Fila pública** (`#/controle/fila`): cada inscrição pelo **código público** (pseudônimo, ex.: `F-3A9C1B`), com posição,
  pontos, critérios, entrada, espera, as três distâncias e a conferência da ordem; exporta CSV (até 5 mil linhas) para análise própria.
- **Consulta de caso** (`#/controle/caso`): só com o **protocolo informado pela família** e o motivo (atendimento da Defensoria,
  procedimento do MP, Conselho Tutelar) — mostra situação, posição, critérios, quem está à frente (por código, sem identificação),
  ofertas, documentos (só a situação) e a linha do tempo. **Cada consulta, inclusive de protocolo inexistente, fica na auditoria.**
- **Simulação da medida da distância** liberada para o controle externo (exemplos por código público, sem nomes); trocar a medida
  continua sendo decisão do(a) Secretário(a), com justificativa.
- Teste: `supabase/tests/controle_externo.sql` (11 passos, revertido).

### Distância casa–unidade: linha reta, a pé e de carro
Pedido do Ministério Público e da Defensoria: a proximidade não pode se basear só na linha reta. A IARA Educa calcula e mostra
as **três medidas** — e o modelo vale para qualquer município.

- **Toda tela em que se procura ou se pede uma vaga** (busca de vaga, unidades próximas no mapa, endereço do cadastro,
  ficha da criança, inscrição na fila e portal da família) tem o seletor **Linha reta (padrão) · A pé · De carro**: no mapa,
  a reta pontilhada vira o caminho pelas ruas até cada unidade numerada, e as listas destacam a medida escolhida (com o tempo).
- **A pé:** trajeto mais curto pelas ruas, calçadas e caminhos de pedestres (tempo a 5 km/h). **De carro:** trajeto mais
  rápido respeitando a mão de direção (tempo sem trânsito). **Linha reta:** a menor distância no mapa, sem considerar ruas.
- **O critério "até 2 km" (IN nº 025/2025, +15 pontos) usa uma medida** — parâmetro público da regra `TERRITORIO_2KM`
  (`condition.medida` = `LINHA_RETA` | `A_PE` | `CARRO`; padrão: linha reta, como na redação da IN). As três ficam registradas
  em cada inscrição (`dist_reta_m`, `dist_pe_m`, `dist_carro_m`) e no extrato da pontuação que a família vê (portal e WhatsApp).
- **Transparência e decisão:** `#/regras#distancia` explica a metodologia, mostra quantas crianças atendem o critério por cada
  medida e quanto o caminho real é maior que a linha reta; a Secretaria **simula** o impacto de trocar a medida (quem perde os
  pontos, quem muda de posição) e o(a) Secretário(a) **troca** a medida com justificativa registrada na auditoria — todas as
  filas são recalculadas. Casa nova ainda sem rota: vale a linha reta, provisoriamente, e o gateway calcula a rota em segundo plano.
- **Motor de rotas:** OSRM sobre o OpenStreetMap (`supabase/functions/api/rotas.ts`). Padrão: servidores públicos da FOSSGIS,
  para uso leve e demonstração (limites medidos: matriz = 1 consulta a cada ~10 s e até 10 mil células; rota avulsa sem espera).
  **Em produção ou em outro município:** um servidor OSRM próprio com o recorte do OpenStreetMap do estado (ex.: Geofabrik),
  informado nos segredos da função `api`: `ROTAS_OSRM_A_PE` e `ROTAS_OSRM_CARRO` (opcionais: `ROTAS_MAX_URL`,
  `ROTAS_MAX_CELULAS`). Só coordenadas vão ao motor de rotas — nunca nome, CPF ou endereço escrito.
- **Fila inteira em lote:** `POST /rotas/fila` (botão "Calcular rotas pendentes" em `#/regras`, perfis da Secretaria) — as
  1.294 inscrições ativas da demonstração foram calculadas em 10 consultas (91 s). Rotas ficam em cache (`iara.rotas_cache`).

### Princípios aplicados
- **Dado oficial prevalece; nada é inventado** — lacunas aparecem como `PENDENTE SEDUC`. Cada número tem selo de origem
  (oficial, público, calculado, demonstração, projetado, pendente) que explica de onde vem.
- **Regras determinísticas, versionadas e auditáveis** — `vagas físicas = capacidade − matrículas`;
  `ofertáveis = físicas − bloqueadas − reservadas`.
- **Fila pela norma oficial** — [IN nº 025/2025-SEDUC, Anexo I](http://www3.maringa.pr.gov.br/sistema/arquivos/5e336fc8c680.pdf)
  (regras versão 2026.02): irmão(ã) matriculado(a) na mesma unidade **55**, família de baixa renda no CadÚnico **25**,
  reside até 2 km da unidade **15**, filho(a) de mãe solo **5** — máximo 100; empate pela data da solicitação.
  PCD, TEA, TGD e/ou altas habilidades/superdotação têm **prioridade sob análise** mediante laudo médico com CID, fora da soma:
  a Central de Vagas só oferta fora da ordem com laudo validado e justificativa, registrada na auditoria.
  Simulador de pontuação e histórico de versões em `/regras`.
- **Aceite não é matrícula; silêncio não é aceite.** Ofertas reservam a vaga por **72 h** — prazo do Anexo II da
  IN nº 025/2025 para efetivar a matrícula após a contemplação — e expiram sozinhas.
- **Tudo clicável**, alvos de toque ≥ 44 px, alternativa em lista para mapas e gráficos, respeito a "reduzir movimento".

## Arquitetura

```
Navegador (React 19 · PWA)  ──HTTPS──▶  Edge Function `api` (Deno, gateway/BFF)  ──SQL──▶  Postgres 17 + PostGIS
  token de sessão opaco                   sessão → papel + claims por requisição         schema `iara` (domínio, não exposto)
  nenhuma chave no cliente                 whitelist de funções · agente IARA             schema `api`  (funções JSON)
                                                                                         RLS (RBAC + ABAC) · auditoria imutável
```

- **Banco (Supabase):** schema `iara` com o domínio (unidades, territórios, turmas, alunos, responsáveis, matrículas, fila,
  ofertas, protocolos, documentos, conversas, regras, auditoria). Leituras via funções `api.*` *security invoker* sob RLS;
  escritas *security definer* com `iara.require_perm(...)`. Trilha de auditoria imutável (append-only) com antes/depois.
- **Gateway (`supabase/functions/api`):** sessões de demonstração com token opaco (hash SHA-256 guardado), `set local role`
  + `request.jwt.claims` por requisição, rotinas periódicas (expiração de ofertas, atualização temporal da demo).
- **IARA (`supabase/functions/api/iara.ts`):** agente determinístico — intenção, preenchimento de dados, verificação de
  identidade (simulada), ferramentas = funções do próprio sistema com as permissões do cidadão, encaminhamento para humano
  com resumo e pausa do bot até a devolução. Nunca afirma sucesso antes da confirmação do backend.
- **Frontend (`src/`):** Vite 8, React 19, React Router 8 (hash), TanStack Query 5, Motion, MapLibre GL + OpenFreeMap,
  Tailwind CSS 4, TypeScript 7, PWA. Mascote IARA (ipê-roxo) com animações.

## Rodando localmente

```bash
npm install
npm run dev          # http://localhost:5173
npm run build        # typecheck + build de produção em dist/ (base relativa: funciona em qualquer subcaminho)
```

**Publicado:** https://agenciadirectadm-hue.github.io/iara-educa/ (GitHub Pages, atualizado a cada push na `main`
pelo workflow `.github/workflows/pages.yml`).

O frontend usa o gateway publicado por padrão (`https://fqpjbyhewzngutbyydig.supabase.co/functions/v1/api`).
Para outro ambiente, defina `VITE_API_URL` (veja `.env.example`).

### Banco e gateway (manutenção)

Os scripts usam a API de gerenciamento do Supabase com um **token pessoal** passado só pela variável de ambiente
(nunca gravado em arquivo):

```bash
SUPABASE_ACCESS_TOKEN=... node scripts/sql.mjs supabase/migrations/<arquivo>.sql   # aplica SQL
SUPABASE_ACCESS_TOKEN=... node scripts/sql.mjs -e "select iara.demo_generate()"   # recria a base de demonstração (~25 s)
SUPABASE_ACCESS_TOKEN=... node scripts/deploy-function.mjs api                     # publica o gateway
```

Ordem de aplicação: `supabase/migrations/*` (em ordem) → `supabase/seed/10_dados_publicos.sql` → `19`/`20`/`21`/`22` (funções de demo)
→ `select iara.demo_generate();` → **sempre por último** `supabase/migrations/20261003009900_privilegios.sql` (idempotente; reaplicar
após criar funções novas). Testes: `supabase/tests/rls_smoke.sql`, `supabase/tests/jornada_e2e.sql`,
`supabase/tests/prioridade_laudo.sql`, `supabase/tests/vida_familia.sql`, `supabase/tests/conversas_unidades.sql`,
`supabase/tests/cadastro_pessoas.sql`, `supabase/tests/distancias_rota.sql` e `supabase/tests/controle_externo.sql` (os sete
últimos rodam numa transação revertida e não deixam resíduo na demonstração;
para ver o resultado completo, use `SQL_OUT_LIMIT=200000`).
Conversa da IARA pelo gateway publicado, sem chaves: `node scripts/teste-iara.mjs nova` (família recém-chegada) ou
`node scripts/teste-iara.mjs maria` (família já cadastrada) — cria dados de demonstração.

Limpeza do que visitantes e testes criaram pelo app (famílias, crianças, protocolos, conversas, ofertas, matrículas,
notificações) — o que as sessões alteraram no cenário gerado volta ao valor original pela trilha de auditoria, que não é
tocada: `SUPABASE_ACCESS_TOKEN=... node scripts/sql.mjs -e "select iara.demo_purge_session_data()"`.
Para limpar só o que uma sessão específica fez (ex.: um teste), sem tocar no resto:
`select iara.demo_purge_session_data(null, array['<id do usuário da sessão>']::uuid[])`.
O botão "Reiniciar demonstração" faz o mesmo só para a família da Maria.

Relógio da demonstração: a cada 6 h o gateway desloca os registros fictícios para manter o cenário atual
(`iara.demo_timeshift`, um de cada vez — trava na linha do tenant). O que foi criado ao vivo (visitantes, testes, WhatsApp)
não é deslocado. Cada deslocamento fica na auditoria (`DEMO_TIMESHIFT`), e a limpeza usa essa soma para restaurar valores.

## Estrutura

```
src/
  app/            casca (navegação por perfil, barra inferior mobile, trilho lateral desktop)
  components/     UI, mapa (MapLibre), gráficos SVG clicáveis, chat, mascote, oferta, matrícula
  pages/          telas (início por perfil, mapa, unidades, turmas, alunos, atendimentos, busca de vaga, fila,
                  ofertas, IARA, conversas, protocolos, indicadores, auditoria, qualidade, regras, ajuda)
  lib/            cliente do gateway, sessão, formatação, rótulos
supabase/
  migrations/     esquema, regras de negócio, RLS, APIs, privilégios
  functions/api/  gateway + agente IARA
  seed/           dados públicos (118 unidades, territórios) e geradores da camada de demonstração
  tests/          RLS e jornada ponta a ponta em SQL
scripts/          SQL/deploy via API de gerenciamento, gerador do seed público, tratamento do mascote
```

## Limitações conhecidas desta versão
- Camada operacional fictícia: capacidades autorizadas, fila, protocolos e pessoas aguardam extração oficial da SEDUC.
- Autenticação real (gov.br/SSO da Prefeitura) não implementada — a entrada é por seleção de perfil de demonstração.
- WhatsApp é simulado (nenhuma mensagem real é enviada); a verificação de identidade usa código simulado.
- A pontuação da fila e o prazo de 72 h seguem a IN nº 025/2025; ordenação das unidades na busca, desempate, matriz de
  alçadas e prazos de atendimento por serviço são parametrização de referência, a validar com a SEDUC.

---
Desenvolvido para a SEDUC Maringá. Dados pessoais exibidos na demonstração são fictícios.
