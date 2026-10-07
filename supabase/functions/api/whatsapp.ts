// WhatsApp real — rotas da ponte (whatsapp-ponte/). O gateway é o mesmo do portal: cada telefone vira um contato
// com usuário próprio e conversa pelo MESMO agente; muda só a forma de mostrar as opções (lista numerada).
//   GET  /whatsapp/canal                       → situação do canal (ligado? número?)
//   POST /whatsapp/canal      { ativo }        → liga/desliga (a ponte liga ao subir e desliga ao parar)
//   POST /whatsapp/estado     { estado, conectado } → sinal de vida da ponte
//   POST /whatsapp/entrada    { de, jid, nome, texto, wa_id, ts, tipo } → respostas da IARA
//   POST /whatsapp/saida                       → lote da fila de saída (servidor respondendo, avisos)
//   POST /whatsapp/saida/confirmar { id, wa_id?, erro? }
// Autenticação: cabeçalho x-iara-canal com o segredo da ponte (o banco guarda só o hash).
import { asSystem, callApi, gravarRotas, sql, type RequestMeta } from "./db.ts";
import { distanciasComPrazo } from "./rotas.ts";
import { Agent, type ConvSnapshot, type QuickReply, type Reply } from "./iara.ts";

type Canal = { id: string; numero_e164: string; ativo: boolean; estado: string };

/** Transcrição de áudio: Whisper na Groq — a mesma da IARA Saúde. Sem a chave, a IARA avisa que ainda não ouve. */
const GROQ = Deno.env.get("GROQ_API_KEY") ?? "";
export const audioDisponivel = () => GROQ.length > 0;
type Json = (data: unknown, status?: number) => Response;

const norm = (s: string) => (s ?? "").toLowerCase().normalize("NFD").replace(/\p{Diacritic}/gu, "").replace(/\s+/g, " ").trim();

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function canalDaPonte(req: Request): Promise<Canal | null> {
  const segredo = req.headers.get("x-iara-canal") ?? "";
  if (segredo.length < 24) return null;
  const rows = await sql`select iara.whatsapp_canal_por_segredo(${await sha256(segredo)}) as c`;
  return (rows[0]?.c as Canal | null) ?? null;
}

/** Opções da IARA viram lista numerada: no WhatsApp a pessoa responde "1", "2"... ou escreve a opção. */
export function renderWhatsApp(replies: Reply[]): string[] {
  const lastWithOptions = replies.map((r) => (r.payload?.quick_replies?.length ?? 0) > 0).lastIndexOf(true);
  return replies.map((r, i) => {
    // negrito do portal (**x**) → negrito do WhatsApp (*x*)
    let t = (r.body ?? "").trim().replace(/\*\*(.+?)\*\*/g, "*$1*");
    for (const c of r.payload?.cards ?? []) {
      t += `\n\n*${c.title}*` + (c.badge && !c.title.includes(c.badge) ? ` · ${c.badge}` : "") + (c.subtitle ? `\n${c.subtitle}` : "");
      if (c.lines?.length) t += "\n" + c.lines.map((l) => `• ${l}`).join("\n");
    }
    const qr = r.payload?.quick_replies ?? [];
    if (qr.length) {
      t += i === lastWithOptions
        ? "\n\n" + qr.map((q, k) => `*${k + 1}.* ${q.label}`).join("\n") + "\n\n_Responda com o número da opção._"
        : "\n\n" + qr.map((q) => `• ${q.label}`).join("\n");
    }
    return t.trim();
  }).filter(Boolean);
}

const POR_EXTENSO: Record<string, number> = {
  um: 1, uma: 1, primeiro: 1, primeira: 1, dois: 2, duas: 2, segundo: 2, segunda: 2, tres: 3, terceiro: 3, terceira: 3,
  quatro: 4, quarto: 4, quarta: 4, cinco: 5, quinto: 5, quinta: 5, seis: 6, sete: 7, oito: 8, nove: 9, dez: 10,
};

/** "2", "2.", "*2*", "dois", "opção 2" (inclusive falado num áudio) ou o texto da opção → a ação da última lista enviada. */
export function interpretar(texto: string, opcoes: QuickReply[]): { text: string; action: string | null } {
  const t = texto.trim();
  const limpo = norm(t).replace(/[.!?,;:*]+/g, "").replace(/^(a |o )?(opcao|numero|alternativa)\s+/, "").trim();
  const num = /^(\d{1,2})\s*[)-]?$/.exec(limpo)?.[1] ?? POR_EXTENSO[limpo];
  if (num && opcoes.length) {
    const q = opcoes[Number(num) - 1];
    if (q) return { text: q.label, action: q.action ?? null };
  }
  const igual = opcoes.find((q) => norm(q.label) === norm(t));
  if (igual) return { text: igual.label, action: igual.action ?? null };
  return { text: t, action: null };
}

/** A lista que vale para "1", "2"... é a da mensagem mais recente da IARA que tinha opções (a mesma numerada no texto). */
function listaVigente(replies: Reply[]): QuickReply[] {
  for (let i = replies.length - 1; i >= 0; i--) {
    const q = replies[i].payload?.quick_replies;
    if (q?.length) return q;
  }
  return [];
}

async function guardarOpcoes(contactId: string, userId: string, meta: RequestMeta, replies: Reply[]) {
  await asSystem(userId, meta, (tx) => tx`select iara.whatsapp_opcoes(${contactId}::uuid, ${sql.json(listaVigente(replies) as never)}::jsonb)`);
}

const SEM_AUDIO = "Recebi seu áudio, mas ainda não consigo ouvir. 🙏 Pode escrever em poucas palavras o que precisa?";
const AUDIO_NAO_ENTENDI = "Recebi seu áudio, mas não consegui entender direito. 🙏 Pode repetir com calma ou escrever em poucas palavras?";

const EXT_AUDIO: Record<string, string> = {
  "audio/ogg": "ogg", "audio/opus": "ogg", "audio/mpeg": "mp3", "audio/mp4": "m4a", "audio/m4a": "m4a", "audio/x-m4a": "m4a",
  "audio/aac": "m4a", "audio/wav": "wav", "audio/x-wav": "wav", "audio/webm": "webm", "audio/flac": "flac", "audio/amr": "amr",
};
/** Frases que o Whisper "ouve" em áudio vazio ou só com ruído — não são o que a pessoa disse. */
const ALUCINACAO = /amara\.org|legendas? pela comunidade|obrigad[oa] por assistir|inscreva-se no canal|^\W*$/i;

async function transcrever(base64: string, tipo: string): Promise<string | null> {
  if (!GROQ || !base64 || base64.length > 12_000_000) return null;
  try {
    const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
    const form = new FormData();
    form.append("file", new Blob([bytes], { type: tipo || "audio/ogg" }), "audio." + (EXT_AUDIO[tipo] ?? "ogg"));
    form.append("model", "whisper-large-v3");
    form.append("language", "pt"); // fixado: sem isso o Whisper às vezes decide que um áudio curto é espanhol
    form.append("temperature", "0");
    form.append("response_format", "json");
    const r = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
      method: "POST", headers: { authorization: `Bearer ${GROQ}` }, body: form, signal: AbortSignal.timeout(25_000),
    });
    if (!r.ok) {
      console.error("transcrição falhou:", r.status, (await r.text()).slice(0, 200));
      return null;
    }
    const texto = String(((await r.json()) as { text?: string }).text ?? "").trim();
    return texto && !ALUCINACAO.test(texto) ? texto.slice(0, 2000) : null;
  } catch (e) {
    console.error("transcrição:", String(e).slice(0, 200));
    return null;
  }
}
const SEM_MIDIA = "Recebi o arquivo, obrigado! Por aqui eu ainda não consigo abrir anexos — os documentos são conferidos na unidade. Como posso ajudar?";
const AVISO_DEMO = "🚩 *Demonstração da IARA Educa* (Secretaria Municipal de Educação de Maringá). As famílias e os dados deste atendimento são fictícios. Por favor, *não envie dados reais* (CPF, endereço, documentos ou fotos).";
const FORA_DA_LISTA = "Olá! Neste momento este número está reservado a uma demonstração da IARA Educa (Secretaria Municipal de Educação de Maringá) e não atende ao público. Para assuntos da Educação, procure a unidade do seu filho ou a SEDUC. Se você procura a IARA Saúde, tente novamente mais tarde.";

async function entrada(canal: Canal, body: Record<string, unknown>, meta: RequestMeta, json: Json): Promise<Response> {
  if (!canal.ativo) return json({ ativo: false, respostas: [] });
  const tel = String(body.de ?? "");
  const waId = String(body.wa_id ?? "").slice(0, 200);
  const tipo = String(body.tipo ?? "texto");
  const texto = String(body.texto ?? "").slice(0, 2000);
  if (!waId) return json({ error: "wa_id obrigatório." }, 422);

  const nova = await asSystem(null, meta, (tx) => tx`select iara.whatsapp_registrar_entrada(${canal.id}::uuid, ${waId}) as n`);
  if (!nova[0]?.n) return json({ ativo: true, duplicada: true, respostas: [] });

  // lista de números autorizados (interruptor do painel): fora dela não há contato, conversa nem cadastro — só um aviso a cada 6 h
  const triagem = (await asSystem(null, meta, (tx) => tx`select iara.whatsapp_triagem(${canal.id}::uuid, ${tel}) as t`))[0]?.t as
    { autorizado: boolean; avisar: boolean; demo: boolean } | undefined;
  if (triagem && !triagem.autorizado) return json({ ativo: true, bloqueado: true, respostas: triagem.avisar ? [FORA_DA_LISTA] : [] });

  const contato = (await asSystem(null, meta, (tx) =>
    tx`select iara.whatsapp_contato(${canal.id}::uuid, ${tel}, ${String(body.nome ?? "")}, ${String(body.jid ?? "")}) as c`))[0]?.c as {
      contact_id: string; user_id: string; conversation_id: string | null;
    };
  const userId = contato.user_id;
  const conv = (await callApi(userId, meta, "iara_conversation", { channel: "WHATSAPP" })) as { id?: string; conversation?: { id: string } };
  const convId = conv?.conversation?.id ?? conv?.id;
  if (!convId) throw new Error("Conversa não encontrada para o contato.");
  const vinc = (await asSystem(userId, meta, (tx) => tx`select iara.whatsapp_vincular(${contato.contact_id}::uuid, ${convId}::uuid) as r`))[0]?.r as { nova: boolean };

  // áudio: a IARA ouve (transcrição) e responde ao que foi dito; o texto ouvido fica na conversa para a equipe
  const ouvido = tipo === "audio" ? await transcrever(String(body.audio_base64 ?? ""), String(body.audio_tipo ?? "audio/ogg")) : null;
  const extra = tipo === "audio" ? { audio: true, transcricao: ouvido, segundos: Number(body.audio_segundos ?? 0) || null } : {};
  const recebido = tipo === "audio" ? (ouvido ? `🎤 ${ouvido}` : "[áudio]") : tipo === "midia" ? (texto || "[arquivo]") : texto;
  if (!recebido.trim()) return json({ ativo: true, respostas: [] });

  // conversa nova: registra a 1ª mensagem e responde com a saudação (o menu já vem nela)
  if (vinc?.nova) {
    await callApi(userId, meta, "iara_send", { conversation_id: convId, body: recebido, payload: { canal: "whatsapp", wa_id: waId, ...extra } });
    const saud = ((await asSystem(userId, meta, (tx) => tx`select iara.whatsapp_saudacao(${convId}::uuid) as r`))[0]?.r ?? []) as Reply[];
    await guardarOpcoes(contato.contact_id, userId, meta, saud);
    // demonstração: o primeiro contato já avisa que os dados são fictícios e pede para não mandar dados reais
    return json({ ativo: true, nova: true, respostas: [...(triagem?.demo ? [AVISO_DEMO] : []), ...renderWhatsApp(saud)] });
  }

  const opcoes = ((await sql`select iara.whatsapp_contato_opcoes(${contato.contact_id}::uuid) as o`)[0]?.o ?? []) as QuickReply[];
  const { text, action } = tipo === "texto" || ouvido ? interpretar(ouvido ?? texto, opcoes) : { text: recebido, action: null };
  const snap = (await callApi(userId, meta, "iara_send", {
    conversation_id: convId, body: ouvido ? recebido : (text || action), payload: { canal: "whatsapp", wa_id: waId, ...extra, ...(action ? { action } : {}) },
  })) as ConvSnapshot;

  // servidor no atendimento: a IARA não responde (a resposta humana sai pela fila de saída)
  if (snap.state === "HUMAN_ACTIVE" || snap.state === "HUMAN_PENDING") return json({ ativo: true, humano: true, respostas: [] });

  const chamar = (fn: string, args: unknown) => callApi(userId, meta, fn, args);
  const agent = new Agent(chamar, snap, distanciasComPrazo(chamar, gravarRotas(userId, meta)), { demo: triagem?.demo === true });
  if (tipo === "audio" && !ouvido) agent.messages.push({ body: audioDisponivel() ? AUDIO_NAO_ENTENDI : SEM_AUDIO });
  else if (tipo === "midia" && !texto.trim()) agent.messages.push({ body: SEM_MIDIA });
  else {
    if (ouvido) agent.messages.push({ body: `🎧 Ouvi: “${ouvido.length > 280 ? ouvido.slice(0, 280) + "…" : ouvido}”` });
    await agent.handle(text, action);
  }
  await asSystem(userId, meta, (tx) =>
    tx`select iara.agent_reply(${convId}::uuid, ${sql.json(agent.messages as never)}::jsonb,
                               ${sql.json({ ...agent.patch, context: agent.ctx } as never)}::jsonb, ${sql.json(agent.tools as never)}::jsonb) as r`);
  await asSystem(userId, meta, (tx) => tx`select iara.whatsapp_pos_turno(${contato.contact_id}::uuid) as r`);
  await guardarOpcoes(contato.contact_id, userId, meta, agent.messages);
  return json({ ativo: true, respostas: renderWhatsApp(agent.messages) });
}

export async function handleWhatsApp(path: string, req: Request, meta: RequestMeta, json: Json): Promise<Response | null> {
  if (!path.startsWith("/whatsapp/")) return null;
  const canal = await canalDaPonte(req);
  if (!canal) return json({ error: "Ponte não autorizada." }, 401);
  const body = req.method === "POST" ? ((await req.json().catch(() => ({}))) as Record<string, unknown>) : {};

  if (path === "/whatsapp/canal" && req.method === "GET") return json(canal);
  if (path === "/whatsapp/canal" && req.method === "POST") {
    if (typeof body.ativo !== "boolean") return json({ error: "Informe ativo: true ou false." }, 422);
    const r = await asSystem(null, meta, (tx) => tx`select iara.whatsapp_canal_ligar(${canal.id}::uuid, ${body.ativo as boolean}, ${"ponte do WhatsApp"}) as r`);
    return json(r[0]?.r ?? {});
  }
  if (path === "/whatsapp/estado" && req.method === "POST") {
    const r = await asSystem(null, meta, (tx) =>
      tx`select iara.whatsapp_canal_estado(${canal.id}::uuid, ${String(body.estado ?? "CONECTADO")}, ${body.conectado === true}) as r`);
    return json(r[0]?.r ?? {});
  }
  if (path === "/whatsapp/entrada" && req.method === "POST") return await entrada(canal, body, meta, json);
  if (path === "/whatsapp/saida" && req.method === "POST") {
    if (!canal.ativo) return json({ ativo: false, itens: [] });
    const r = await asSystem(null, meta, (tx) => tx`select iara.whatsapp_saida_proximas(${canal.id}::uuid, ${10}) as r`);
    return json({ ativo: true, itens: r[0]?.r ?? [] });
  }
  if (path === "/whatsapp/saida/confirmar" && req.method === "POST") {
    await asSystem(null, meta, (tx) =>
      tx`select iara.whatsapp_saida_confirmar(${canal.id}::uuid, ${String(body.id ?? "")}::uuid, ${body.wa_id ? String(body.wa_id) : null},
                                              ${body.erro ? String(body.erro) : null})`);
    return json({ ok: true });
  }
  return json({ error: "Rota do WhatsApp não encontrada." }, 404);
}
