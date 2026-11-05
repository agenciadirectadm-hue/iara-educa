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
  "alfabetizacao", "busca_ativa", "unidades", "cadastros", "bolsa_familia",
  // temas do catálogo (ver indicadores_disponiveis)
  "rede", "atendimento", "ofertas", "rematricula", "ausencias", "ocorrencias_tipo", "protecao", "desempenho", "aee", "ponto", "transporte_det",
  "nutricao", "almoxarifado", "manutencao", "biblioteca", "comunicacao", "qualidade", "territorio", "base"];

export const FERRAMENTAS = [
  {
    name: "numeros_do_municipio",
    description: "Números consolidados da rede municipal de educação sobre um tópico, na cidade toda, numa unidade (CMEI ou escola) " +
      "ou numa região (área de ponderação do IBGE). Tópicos: visao_geral (resumo), matriculas, fila (fila de espera por vaga), vagas, " +
      "creche, frequencia (presença dos últimos 30 dias, alertas e busca ativa), ocorrencias (últimos 90 dias), profissionais, " +
      "transporte (escolar), alfabetizacao (sondagens do ano), busca_ativa, unidades, cadastros (completude dos cadastros), " +
      "bolsa_familia (alunos em famílias do Bolsa Família; deixaram de receber = abaixo da frequência mínima em ao menos um período " +
      "do ano; têm recebido assiduamente = sempre dentro do mínimo). " +
      "Devolve só números agregados, nunca nomes nem contatos.",
    input_schema: {
      type: "object",
      properties: {
        topico: { type: "string", enum: TOPICOS, description: "Assunto da consulta." },
        indicadores: { type: "array", items: { type: "string" }, description: "Em vez do tópico: as chaves de indicadores específicos (ver indicadores_disponiveis)." },
        unidade: { type: "string", description: "Nome ou id de uma unidade. Omita para a cidade toda." },
        regiao: { type: "string", description: "Região: 'AP 017', o id ou o nome de um bairro dela. Omita para a cidade toda." },
      },
    },
  },
  {
    name: "unidades_do_municipio",
    description: "Nomes das unidades (CMEIs e escolas, com a região de cada uma) e das regiões do município, com busca opcional por " +
      "parte do nome. Use para achar a unidade ou a região citada antes de pedir os números.",
    input_schema: { type: "object", properties: { busca: { type: "string", description: "Parte do nome (opcional)." } } },
  },
  {
    name: "indicadores_disponiveis",
    description: "Tudo o que o Oráculo sabe: os temas (atendimento, ofertas de vaga, rematrícula, ausências, ocorrências por tipo, proteção, desempenho, " +
      "AEE, ponto, frota, merenda e nutrição, almoxarifado, manutenção, biblioteca, comunicação, qualidade, Censo) e a chave de cada indicador.",
    input_schema: { type: "object", properties: {} },
  },
  {
    name: "situacoes_pontuais",
    description: "O que pede atenção agora na rede: chamados de manutenção que afetam a segurança, ocorrências graves recentes, protocolos vencidos, " +
      "ofertas de vaga vencendo, transporte que não passou, turmas sem chamada, estoque e agenda da semana. Sem nome de pessoa.",
    input_schema: {
      type: "object",
      properties: {
        unidade: { type: "string", description: "Nome ou id de uma unidade. Omita para a cidade toda." },
        regiao: { type: "string", description: "Região: 'AP 017', o id ou o nome de um bairro dela. Omita para a cidade toda." },
        dias: { type: "integer", description: "Quantos dias olhar para trás (padrão: 7)." },
      },
    },
  },
  {
    name: "comparar_unidades",
    description: "Compara unidades ou regiões num indicador: \"qual escola tem mais ocorrências\", \"quais regiões têm menos vagas\". " +
      "Use a chave de indicadores_disponiveis; os principais são base.matriculas, base.fila, base.fila_creche, base.vagas, base.ocorrencias, " +
      "base.presenca, base.alertas, base.busca, base.profissionais, base.transportados.",
    input_schema: {
      type: "object",
      properties: {
        indicador: { type: "string", description: "Chave do indicador." },
        por: { type: "string", enum: ["unidade", "regiao"], description: "Comparar unidades (padrão) ou regiões." },
        ordem: { type: "string", enum: ["maior", "menor"], description: "Maiores ou menores valores primeiro." },
        limite: { type: "integer", description: "Quantos mostrar (padrão: 5; máximo: 30)." },
        tipo: { type: "string", enum: ["CMEI", "ESCOLA"], description: "Só CMEIs ou só escolas (opcional)." },
      },
      required: ["indicador"],
    },
  },
  {
    name: "contar_por_nome",
    description: "Quantas pessoas têm um nome no cadastro (primeiro nome ou sobrenome). Só a contagem, uma palavra por vez; menos de 3 fica em sigilo. " +
      "Serve para estatística de nomes, não para achar uma pessoa.",
    input_schema: {
      type: "object",
      properties: {
        nome: { type: "string", description: "Uma palavra, por exemplo Silvio." },
        quem: { type: "string", enum: ["ALUNOS", "PROFISSIONAIS", "RESPONSAVEIS"], description: "Padrão: ALUNOS." },
        unidade: { type: "string", description: "Nome ou id de uma unidade (opcional)." },
        regiao: { type: "string", description: "Região (opcional)." },
      },
      required: ["nome"],
    },
  },
  {
    name: "detalhar",
    description: "Abre um assunto: por motivo, tipo, situação, etapa, tempo de espera, mês, região e o que mais houver. É a ferramenta para \"por quê\", " +
      "\"quais os motivos\", \"me fale mais\", \"quais os principais\" e para perfil dos alunos (sexo, idade, raça ou cor) e dos profissionais (cargo, vínculo, formação). " +
      "Sem o parâmetro detalhe, traz os números do assunto, todos os detalhes e, na cidade, as regiões onde mais pesa. Itens de 1 ou 2 pessoas vêm juntos em \"Outros\".",
    input_schema: {
      type: "object",
      properties: {
        assunto: { type: "string", enum: ["encaminhamentos","busca_ativa","ocorrencias","faltas","fila","ofertas","vagas","rematricula","transferencias","aee","ponto","profissionais","transporte","suporte","manutencao","almoxarifado","merenda","desempenho","alfabetizacao","biblioteca","atendimento","comunicacao","documentos","matriculas"], description: "O assunto." },
        detalhe: { type: "string", description: "Só este detalhe (chave vista em indicadores_disponiveis, como enc.motivo). Opcional." },
        limite: { type: "integer", description: "Quantos itens por detalhe (padrão: 8; máximo: 30)." },
        unidade: { type: "string", description: "Nome ou id de uma unidade. Omita para a cidade toda." },
        regiao: { type: "string", description: "Região: 'AP 017', o id ou o nome de um bairro dela. Omita para a cidade toda." },
      },
      required: ["assunto"],
    },
  },
  {
    name: "numero_no_periodo",
    description: "Um número num período: \"quantas crianças faltaram ontem\", \"ocorrências desta semana\", \"chamados abertos neste mês\". Se o período ainda não tem " +
      "registro (a chamada de hoje, por exemplo), avisa com sem_registro e traz o último dia que tem: diga isso, não diga que foi zero.",
    input_schema: {
      type: "object",
      properties: {
        fatos: { type: "array", items: { type: "string", enum: ["faltas","presenca","ocorrencias","refeicoes","chamados","protocolos","viagens_perdidas","viagens_atraso","ponto","matriculas","encaminhamentos","alertas","busca_ativa","ofertas"] }, description: "O que contar." },
        periodo: { type: "string", description: "hoje, ontem, anteontem, semana, semana_passada, mes, mes_passado, ano ou ultimos_N (por exemplo ultimos_15)." },
        de: { type: "string", description: "Em vez do período: data inicial (AAAA-MM-DD)." },
        ate: { type: "string", description: "Data final (AAAA-MM-DD). Padrão: hoje." },
        unidade: { type: "string", description: "Nome ou id de uma unidade. Omita para a cidade toda." },
        regiao: { type: "string", description: "Região: 'AP 017', o id ou o nome de um bairro dela. Omita para a cidade toda." },
      },
      required: ["fatos"],
    },
  },
  {
    name: "cardapio_do_dia",
    description: "O cardápio publicado de um dia, por faixa (creche, pré-escola e ensino fundamental) e por refeição. É o mesmo em toda a rede. Em dia sem aula, avisa e traz o próximo dia com aula.",
    input_schema: { type: "object", properties: { data: { type: "string", description: "AAAA-MM-DD. Padrão: hoje." } } },
  },
  {
    name: "calendario_da_rede",
    description: "Próximos eventos do calendário: feriados, recessos, fim de bimestre, reuniões, fim do ano letivo. Da rede e, numa unidade ou região, também os dela.",
    input_schema: {
      type: "object",
      properties: {
        dias: { type: "integer", description: "Quantos dias olhar à frente (padrão: 90)." },
        tipo: { type: "string", description: "Só um tipo, por exemplo FERIADO. Opcional." },
        unidade: { type: "string", description: "Nome ou id de uma unidade. Opcional." },
        regiao: { type: "string", description: "Região. Opcional." },
      },
    },
  },
];
const FUNCAO: Record<string, string> = {
  numeros_do_municipio: "oraculo_dados", unidades_do_municipio: "oraculo_unidades", indicadores_disponiveis: "oraculo_indicadores",
  situacoes_pontuais: "oraculo_situacoes", comparar_unidades: "oraculo_ranking", contar_por_nome: "oraculo_nomes",
  detalhar: "oraculo_detalhar", numero_no_periodo: "oraculo_periodo", cardapio_do_dia: "oraculo_cardapio", calendario_da_rede: "oraculo_calendario",
};

const SISTEMA = `Você é o Oráculo do Prefeito no IARA Educa, a plataforma da Secretaria Municipal de Educação de Maringá (PR).
O Prefeito pergunta, por texto ou por áudio, sobre a rede municipal de educação; responda com os números das ferramentas.

- Use apenas números que as ferramentas devolverem. Se faltar o dado, diga o que existe e o que não existe.
- Quando a pergunta citar uma unidade ou região e você não tiver certeza do nome, consulte unidades_do_municipio antes.
- Para comparar unidades ou regiões, use comparar_unidades, com o limite que o Prefeito pedir (três escolas = limite 3). Para "o que está
  acontecendo", use situacoes_pontuais.
- Quando pedirem motivo, causa, tipo, perfil, "me fale mais" ou "quais os principais", use detalhar: não repita a contagem. Quando citarem um
  dia ou período (ontem, esta semana, mês passado), use numero_no_periodo: não responda com o número dos últimos 30 dias. Para o que tem na
  merenda, use cardapio_do_dia. Para datas e feriados, use calendario_da_rede.
- Se vier "faltando" ou "sem_registro", diga o motivo e o que existe; nunca transforme falta de dado em zero.
- Se o assunto não estiver em nenhuma ferramenta, veja indicadores_disponiveis: o Oráculo cobre quase toda a operação. Salários, folha e
  orçamento não estão no IARA Educa: diga isso.
- Responda em português do Brasil, como para ser lido no celular ou ouvido em voz alta: o número principal primeiro, depois o que explica
  esse número (os principais motivos, com percentual, e onde mais pesa) e o recorte e o período. Até 5 frases curtas numa pergunta simples;
  num pedido de detalhe, pode ir um pouco além. Números no padrão brasileiro (1.234; 93,4%). Sem tabelas nem markdown.
- O Oráculo só traz números e situações sem identificar pessoas. Contar quantos têm um nome é permitido (contar_por_nome); dizer
  quem são, ou dar telefone e endereço, não: explique que o detalhe fica com a Secretaria, na unidade, com os registros de acesso.
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

// títulos e dicas das ferramentas para o assistente: só leitura, dados do próprio IARA
const TITULO: Record<string, string> = {
  numeros_do_municipio: "Números da rede municipal", unidades_do_municipio: "Unidades e regiões", indicadores_disponiveis: "O que o Oráculo sabe",
  situacoes_pontuais: "Situações que pedem atenção", comparar_unidades: "Comparar unidades e regiões", contar_por_nome: "Contar pessoas por nome",
  detalhar: "Motivos, tipos e perfil de um assunto", numero_no_periodo: "Número em um dia ou período", cardapio_do_dia: "Cardápio do dia", calendario_da_rede: "Calendário da rede",
};

async function mcpUma(api: Api, m: Rpc): Promise<unknown | null> {
  // diagnóstico: só o método e a ferramenta (nunca a chave nem os argumentos)
  console.log("mcp", m?.method ?? "?", m?.method === "tools/call" ? String(m.params?.name ?? "") : "");
  if (m?.id === undefined || m?.id === null) return null; // notificação (ex.: notifications/initialized): não tem resposta
  const ok = (result: unknown) => ({ jsonrpc: "2.0", id: m.id, result });
  const falha = (code: number, message: string) => ({ jsonrpc: "2.0", id: m.id, error: { code, message } });
  switch (m.method) {
    case "initialize": {
      const pedida = String(m.params?.protocolVersion ?? "");
      return ok({
        protocolVersion: VERSOES.includes(pedida) ? pedida : VERSOES[0],
        capabilities: { tools: { listChanged: false }, resources: {}, prompts: {} },
        serverInfo: { name: "iara-educa-oraculo", title: "Oráculo do Prefeito · IARA Educa", version: "1.3.0" },
        instructions: "Oráculo do Prefeito de Maringá (IARA Educa): toda a operação da rede municipal de educação em números — matrículas, " +
          "fila, vagas, frequência, ocorrências, profissionais e ponto, transporte, merenda, almoxarifado, manutenção, biblioteca, desempenho, AEE, " +
          "proteção, atendimento, Bolsa Família e mais — na cidade, numa unidade ou numa região. Para qualquer pergunta sobre a educação no " +
          "município, consulte estas ferramentas: numeros_do_municipio (assuntos), detalhar (motivos, tipos, perfil, \"me fale mais\": não repita a contagem " +
          "quando pedirem o porquê), numero_no_periodo (ontem, esta semana, um mês), cardapio_do_dia, calendario_da_rede, situacoes_pontuais " +
          "(o que está acontecendo), comparar_unidades (qual tem mais ou menos), contar_por_nome (estatística de nomes) e indicadores_disponiveis " +
          "(tudo o que há). Se vier faltando ou sem_registro, diga o motivo: falta de dado não é zero. Só dados agregados: não há quem são as pessoas nem contatos.",
      });
    }
    case "ping":
      return ok({});
    // o Oráculo não tem recursos nem prompts, mas responde às listas (alguns clientes pedem ao conectar)
    case "resources/list":
      return ok({ resources: [] });
    case "resources/templates/list":
      return ok({ resourceTemplates: [] });
    case "prompts/list":
      return ok({ prompts: [] });
    case "tools/list":
      return ok({
        tools: FERRAMENTAS.map((f) => ({
          name: f.name, title: TITULO[f.name], description: f.description, inputSchema: f.input_schema,
          annotations: { title: TITULO[f.name], readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
        })),
      });
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
