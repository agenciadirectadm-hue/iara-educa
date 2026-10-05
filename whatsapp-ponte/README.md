# Ponte do WhatsApp — IARA Educa

Liga um número de WhatsApp ao agente da IARA Educa. A ponte só carrega texto entre o WhatsApp e o gateway
(`/whatsapp/...` na Edge Function `api`); toda regra fica no gateway e no banco, com o **mesmo agente do portal**.

```
cidadão → WhatsApp → ponte (Baileys) → POST /whatsapp/entrada → agente IARA → respostas → ponte → cidadão
                                         POST /whatsapp/saida   → resposta de servidor, aviso de oferta → ponte → cidadão
```

## Número compartilhado com a IARA Saúde

O chip **+55 44 99774-8259** atende a IARA Saúde e a IARA Educa. Cada sistema tem a **sua** ponte — um aparelho
conectado próprio no mesmo WhatsApp —, então trocar não exige parear de novo:

1. Pare a ponte da IARA Saúde (`Ctrl+C` na janela dela).
2. Aqui: `npm run ligar` → liga o canal da Educação e conecta.
3. Para voltar: `Ctrl+C` aqui (desliga o canal da Educação) e ligue a ponte da Saúde.

Com as duas ligadas, as duas responderiam às mesmas pessoas. Mensagens que chegaram antes de esta ponte subir
(período em que a outra IARA estava ligada) são ignoradas, para não responder em dobro.

## Primeira vez

```bash
cd whatsapp-ponte
npm install
npm run configurar      # cria o .env e gera o segredo da ponte; mostra o hash para o banco
npm run ligar           # mostra o QR de pareamento (também em http://localhost:5299)
```

No celular do chip: **WhatsApp → Aparelhos conectados → Conectar aparelho** e leia o QR. É um aparelho a mais —
o da IARA Saúde continua pareado.

`npm run configurar` imprime o `update iara.whatsapp_channels set segredo_hash = ...` a rodar no banco (uma vez,
ou a cada `npm run configurar -- --novo`, que troca o segredo).

## Comandos

| Comando | O que faz |
|---|---|
| `npm run ligar` | conecta e **liga** o canal; `Ctrl+C` desliga e encerra |
| `npm run conectar` | só conecta; quem manda é o interruptor do painel (**WhatsApp da IARA**) |
| `npm run parar` (ou `npm run whatsapp:parar` na raiz) | desliga o canal e encerra a ponte — use quando ela roda sem janela |
| `node simular.mjs --ligar +5544900001234 "oi" "2"` | testa sem celular: mostra o que a IARA responderia (nada é enviado) |
| `node simular.mjs --ligar +5544900001234 --audio fala.ogg` | testa a escuta com um arquivo de áudio |

No painel (perfil Secretário ou Inovação): **Mais → WhatsApp da IARA** mostra a situação da ponte e tem o
botão Ligar/Desligar. Com o canal ligado, o QR code e o link do portal da família passam a abrir este WhatsApp.

## O que a conversa faz

- As opções da IARA viram lista numerada; a pessoa responde `1`, `2`... ou escreve a opção.
- Cada telefone vira um contato com usuário próprio; quem faz o cadastro pela conversa fica com o número do
  WhatsApp como contato da família (a posse do aparelho vale como verificação).
- Servidor que assume a conversa na **Caixa da IARA** responde pelo painel e a mensagem sai pelo WhatsApp.
- Avisos (oferta de vaga, matrícula…) das famílias que já conversaram pelo WhatsApp saem pela fila de saída.
- **Áudio:** a IARA ouve — transcrição com Whisper (large-v3, na Groq, em português), a mesma da IARA Saúde. Ela mostra o que
  entendeu ("🎧 Ouvi: …") e responde ao que foi dito; o texto ouvido fica na conversa para a equipe. Dá para responder às opções
  falando ("dois", "opção três"). Configure a chave uma vez, sem ela aparecer na tela (na raiz do projeto):
  `powershell -ExecutionPolicy Bypass -File scripts\guardar-chave-groq.ps1`. Sem a chave, a IARA avisa com sinceridade que ainda não ouve.
- Anexos: documentos são conferidos na unidade.

## Segurança e cuidados

- `.env` (segredo da ponte) e `.wa-sessao-educa/` (sessão do aparelho — vale o mesmo que o celular) **nunca** vão
  para o git. O banco guarda só o hash do segredo.
- Conexão não oficial (WhatsApp Web/Baileys) pode ser bloqueada pelo WhatsApp sem aviso. Para a operação da
  Prefeitura, migrar para a **API oficial da Meta** — só a ponte muda; gateway e agente continuam os mesmos.
- Mensagens reais trazem dados pessoais reais (LGPD). Limpar depois de testes:
  `select iara.demo_purge_session_data('WHATSAPP');`
