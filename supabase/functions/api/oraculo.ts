// Oráculo do Prefeito (só o perfil Prefeito): pergunta por texto ou áudio → números consolidados do município.
// As ferramentas são as consultas agregadas do banco (api.oraculo_dados e api.oraculo_unidades), com a permissão conferida lá.
// Com ANTHROPIC_API_KEY nos segredos da função, o Claude Opus 5.5 escolhe e combina as consultas e escreve a resposta;
// sem a chave (ou se a chamada falhar), o próprio banco responde por regras (api.oraculo_perguntar).
// As mesmas ferramentas ficam disponíveis como servidor MCP (JSON-RPC 2.0 em POST /mcp), autenticado pela sessão do Prefeito.
import { mapDbError } from "./db.ts";
import { audioDisponivel, transcrever } from "./whatsapp.ts";

const CHAVE = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const MODELO = Deno.env.get("ORACULO_MODELO") || "claude-opus-5-5";
export const claudeDisponivel = () => CHAVE.length > 0;

type Api = (fn: string, args: unknown) => Promise<unknown>;
type Bloco = { type: string; id?: string; name?: string; input?: unknown; text?: string };
type Consulta = { topico?: string; recorte?: string; numeros?: unknown[] };

const TOPICOS = ["visao_geral", "matriculas", "fila", "vagas", "creche", "frequencia", "ocorrencias", "profissionais", "transporte",
  "alfabetizacao", "busca_ativa", "unidades", "cadastros"];

export const FERRAMENTAS = [
  {
    name: "numeros_do_municipio",
    description: "Números consolidados da rede municipal de educação sobre um tópico, na cidade toda, numa unidade (CMEI ou escola) " +
      "ou numa região (área de ponderação do IBGE). Tópicos: visao_geral (resumo), matriculas, fila (fila de espera por vaga), vagas, " +
      "creche, frequencia (presença dos últimos 30 dias, alertas e busca ativa), ocorrencias (últimos 90 dias), profissionais, " +
      "transporte (escolar), alfabetizacao (sondagens do ano), busca_ativa, unidades, cadastros (completude dos cadastros). " +
      "Devolve só números agregados, nunca nomes nem contatos.",
    input_schema: {
      type: "object",
      properties: {
        topico: { type: "string", enum: TOPICOS, description: "Assunto da consulta." },
        unidade: { type: "string", description: "Nome ou id de uma unidade. Omita para a cidade toda." },
        regiao: { type: "string", description: "Região: 'AP 017', o id ou o nome de um bairro dela. Omita para a cidade toda." },
      },
      required: ["topico"],
    },
  },
  {
    name: "unidades_do_municipio",
    description: "Nomes das unidades (CMEIs e escolas, com a região de cada uma) e das regiões do município, com busca opcional por " +
      "parte do nome. Use para achar a unidade ou a região citada antes de pedir os números.",
    input_schema: { type: "object", properties: { busca: { type: "string", description: "Parte do nome (opcional)." } } },
  },
];
const FUNCAO: Record<string, string> = { numeros_do_municipio: "oraculo_dados", unidades_do_municipio: "oraculo_unidades" };

const SISTEMA = `Você é o Oráculo do Prefeito no IARA Educa, a plataforma da Secretaria Municipal de Educação de Maringá (PR).
O Prefeito pergunta, por texto ou por áudio, sobre a rede municipal de educação; responda com os números das ferramentas.

- Use apenas números que as ferramentas devolverem. Se faltar o dado, diga o que existe e o que não existe.
- Quando a pergunta citar uma unidade ou região e você não tiver certeza do nome, consulte unidades_do_municipio antes.
- Para comparar unidades ou regiões, consulte cada uma.
- Responda em português do Brasil, em até 5 frases curtas, como para ser lido no celular ou ouvido em voz alta: o número principal
  primeiro, depois o contexto (recorte e período). Números no padrão brasileiro (1.234; 93,4%). Sem tabelas nem markdown.
- O Oráculo só trata de números consolidados. Se pedirem nome, telefone ou dado de uma pessoa, explique que isso não está no
  Oráculo e que o detalhe fica com a Secretaria, na unidade, com os registros de acesso.
- Este é o ambiente de demonstração: os dados são fictícios (as matrículas oficiais são do Censo Escolar 2025).`;

async function executar(api: Api, nome: string, entrada: unknown): Promise<unknown> {
  const fn = FUNCAO[nome];
  if (!fn) throw new Error("Ferramenta desconhecida.");
  return await api(fn, entrada ?? {});
}

async function comClaude(api: Api, pergunta: string): Promise<{ resposta: string; consultas: Consulta[]; ferramentas: unknown[] }> {
  // carregado só quando há chave: sem ela o pacote nem entra na memória da função
  const { default: Anthropic } = await import("npm:@anthropic-ai/sdk@0.137.0");
  const client = new Anthropic({ apiKey: CHAVE, timeout: 60_000, maxRetries: 1 });
  const messages: { role: "user" | "assistant"; content: unknown }[] = [{ role: "user", content: pergunta }];
  const consultas: Consulta[] = [];
  const ferramentas: unknown[] = [];
  for (let volta = 0; volta < 6; volta++) {
    // fallbacks "default": se o modelo recusar, a própria API refaz o pedido no modelo indicado pela Anthropic
    const r = (await client.beta.messages.create({
      model: MODELO, max_tokens: 8000, system: SISTEMA, tools: FERRAMENTAS, messages,
      betas: ["server-side-fallback-2026-07-01"], fallbacks: "default",
    } as never)) as unknown as { stop_reason: string; content: Bloco[] };
    const texto = r.content.filter((b) => b.type === "text").map((b) => b.text ?? "").join("\n").trim();
    if (r.stop_reason === "refusal") {
      return { resposta: "Não consigo responder a essa pergunta. O Oráculo traz números consolidados da rede: matrículas, fila, vagas, frequência, ocorrências, profissionais, transporte e alfabetização.", consultas, ferramentas };
    }
    if (r.stop_reason !== "tool_use") return { resposta: texto || "Não encontrei uma resposta.", consultas, ferramentas };

    messages.push({ role: "assistant", content: r.content });
    const resultados: unknown[] = [];
    for (const b of r.content) {
      if (b.type !== "tool_use") continue;
      try {
        const saida = await executar(api, b.name ?? "", b.input);
        ferramentas.push({ ferramenta: b.name, entrada: b.input });
        if (b.name === "numeros_do_municipio") consultas.push(saida as Consulta);
        resultados.push({ type: "tool_result", tool_use_id: b.id, content: JSON.stringify(saida) });
      } catch (e) {
        resultados.push({ type: "tool_result", tool_use_id: b.id, content: mapDbError(e).message, is_error: true });
      }
    }
    messages.push({ role: "user", content: resultados });
  }
  throw new Error("o Claude não concluiu a resposta em 6 voltas");
}

/** POST /oraculo { pergunta } ou { audio_base64, audio_tipo } */
export async function perguntarOraculo(api: Api, corpo: Record<string, unknown>): Promise<Record<string, unknown>> {
  // a permissão é conferida no banco antes de qualquer custo (transcrição, Claude)
  await api("oraculo_historico", {});
  let pergunta = String(corpo.pergunta ?? "").trim().slice(0, 1000);
  let canal = "TEXTO";
  let transcricao: string | null = null;
  if (corpo.audio_base64) {
    if (!audioDisponivel()) return { error: "O áudio ainda não está ligado neste ambiente. Escreva a pergunta.", status: 503 };
    // o navegador grava "audio/webm;codecs=opus": o tipo vai sem os parâmetros
    transcricao = await transcrever(String(corpo.audio_base64), String(corpo.audio_tipo ?? "audio/webm").split(";")[0].trim());
    if (!transcricao) return { error: "Não consegui entender o áudio. Tente de novo, falando perto do microfone, ou escreva a pergunta.", status: 422 };
    pergunta = transcricao.slice(0, 1000);
    canal = "AUDIO";
  }
  if (pergunta.length < 3) return { error: "Faça uma pergunta.", status: 422 };

  let aviso: string | null = null;
  if (claudeDisponivel()) {
    try {
      const c = await comClaude(api, pergunta);
      await api("oraculo_registrar", { pergunta, canal, resposta: c.resposta, ferramentas: c.ferramentas });
      return { pergunta, canal, transcricao, modo: "CLAUDE", modelo: MODELO, resposta: c.resposta, consultas: c.consultas };
    } catch (e) {
      console.error("oráculo (Claude):", String(e).slice(0, 300));
      aviso = "O Claude não respondeu agora; a resposta veio das regras do IARA.";
    }
  }
  const r = (await api("oraculo_perguntar", { pergunta, canal })) as Record<string, unknown>;
  return { pergunta, canal, transcricao, modo: "REGRAS", resposta: r.resposta, aviso,
    consultas: [{ topico: r.topico, recorte: r.recorte, numeros: r.numeros }] };
}

/** GET /oraculo: modo disponível e últimas perguntas do próprio Prefeito */
export async function statusOraculo(api: Api): Promise<Record<string, unknown>> {
  const historico = await api("oraculo_historico", {});
  return { claude: claudeDisponivel(), modelo: claudeDisponivel() ? MODELO : null, audio: audioDisponivel(), historico };
}

// ---------------------------------------------------------------------------------------------------------------------------
// Servidor MCP (Model Context Protocol) — transporte HTTP só com respostas JSON, sem estado entre chamadas
const VERSOES = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"];
type Rpc = { jsonrpc?: string; id?: string | number | null; method?: string; params?: Record<string, unknown> };

async function mcpUma(api: Api, m: Rpc): Promise<unknown | null> {
  if (m?.id === undefined || m?.id === null) return null; // notificação (ex.: notifications/initialized): não tem resposta
  const ok = (result: unknown) => ({ jsonrpc: "2.0", id: m.id, result });
  const falha = (code: number, message: string) => ({ jsonrpc: "2.0", id: m.id, error: { code, message } });
  switch (m.method) {
    case "initialize": {
      const pedida = String(m.params?.protocolVersion ?? "");
      return ok({
        protocolVersion: VERSOES.includes(pedida) ? pedida : VERSOES[0],
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "iara-educa-oraculo", version: "1.0.0" },
        instructions: "Números consolidados da rede municipal de educação de Maringá (perfil Prefeito). Só dados agregados.",
      });
    }
    case "ping":
      return ok({});
    case "tools/list":
      return ok({ tools: FERRAMENTAS.map((f) => ({ name: f.name, description: f.description, inputSchema: f.input_schema })) });
    case "tools/call": {
      const nome = String(m.params?.name ?? "");
      if (!FUNCAO[nome]) return falha(-32602, `Ferramenta desconhecida: ${nome}`);
      try {
        const saida = await executar(api, nome, m.params?.arguments ?? {});
        return ok({ content: [{ type: "text", text: JSON.stringify(saida) }], isError: false });
      } catch (e) {
        return ok({ content: [{ type: "text", text: mapDbError(e).message }], isError: true });
      }
    }
    default:
      return falha(-32601, `Método não suportado: ${m.method}`);
  }
}

/** POST /mcp: uma mensagem JSON-RPC ou um lote; null quando só havia notificações (HTTP 202) */
export async function mcp(api: Api, corpo: unknown): Promise<unknown | null> {
  if (!Array.isArray(corpo)) return await mcpUma(api, corpo as Rpc);
  const respostas = [];
  for (const m of corpo) {
    const r = await mcpUma(api, m as Rpc);
    if (r) respostas.push(r);
  }
  return respostas.length ? respostas : null;
}
