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
- Em todos os casos a família recebe protocolo, equipe responsável e prazo. A caixa da IARA mostra *quem resolve os pedidos*
  (alçada da demanda), as conversas concluídas sem servidor e as execuções da própria IARA.

**Início da conversa pelo WhatsApp** — QR code, número e link de conversa no portal da família (início, cadastro,
Minha família, chat da IARA), na tela de entrada, na Ajuda, na página pública `#/whatsapp` e no cartaz A4 para imprimir
(`#/whatsapp/cartaz`), com "Compartilhar com a família" para os demais responsáveis. Enquanto a SEDUC não define o número
oficial, o número exibido é de demonstração e o QR code/link abrem a conversa simulada da IARA (nunca um `wa.me` para
número fictício). Para ativar o número oficial, sem novo deploy:
`update iara.tenants set settings = settings || '{"iara_whatsapp_numero": "55449XXXXXXXX"}' where id = 1;` — a partir daí o
QR code e o link viram `https://wa.me/<número>?text=<mensagem>` (mensagem em `iara_whatsapp_mensagem`).

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
`supabase/tests/prioridade_laudo.sql` e `supabase/tests/vida_familia.sql` (os três últimos rodam numa transação revertida e não
deixam resíduo na demonstração; para ver o resultado completo, use `SQL_OUT_LIMIT=200000`).
Conversa da IARA pelo gateway publicado, sem chaves: `node scripts/teste-iara.mjs nova` (família recém-chegada) ou
`node scripts/teste-iara.mjs maria` (família já cadastrada) — cria dados de demonstração.

Limpeza do que visitantes e testes criaram pelo app (famílias, crianças, protocolos, conversas, ofertas, matrículas,
notificações) — o que as sessões alteraram no cenário gerado volta ao valor original pela trilha de auditoria, que não é
tocada: `SUPABASE_ACCESS_TOKEN=... node scripts/sql.mjs -e "select iara.demo_purge_session_data()"`.
O botão "Reiniciar demonstração" faz o mesmo só para a família da Maria.

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
