// IARA Educa — gateway da API (Edge Function `api`).
// O front-end não guarda nenhuma chave do Supabase: fala apenas com este gateway.
// Rotas:
//   GET    /health
//   POST   /session          { persona, unit_id? }     → cria sessão de demonstração (token opaco)
//   DELETE /session                                     → encerra a sessão
//   POST   /rpc/:fn          { ...args }               → executa api.<fn>(args) com RLS do perfil
//   POST   /iara/message     { conversation_id, text, action? } → agente IARA (WhatsApp simulado / portal)
//   POST   /geo/localizar    { cep?, logradouro?, ... } → CEP e coordenada do endereço do cadastro (ver geo.ts)
//   POST   /rotas            { lat, lng, unidades?|proximas?, geometria_unidade? } → linha reta, a pé e de carro (ver rotas.ts)
//   POST   /rotas/fila       { unidades? }             → rotas da fila ativa em lote (Secretaria)
//   GET    /rotas/status                               → situação do motor de rotas
//   *      /whatsapp/...                               → ponte do WhatsApp real (ver whatsapp.ts)
import { asSystem, callApi, gravarRotas, mapDbError, modoDemo, sql, type RequestMeta } from "./db.ts";
import { Agent, type ConvSnapshot } from "./iara.ts";
import { audioDisponivel, handleWhatsApp } from "./whatsapp.ts";
import { localizarEndereco } from "./geo.ts";
import { ARQUIVO_MAX_BYTES, descartarArquivos, guardarArquivo, lerArquivo } from "./arquivos.ts";
import { PROVEDOR, distanciasComPrazo, distanciasComRotas, rota, rotasDaFila } from "./rotas.ts";

// CORS restrito (SEC-AT-03): só o portal publicado, o ambiente local e os domínios de CORS_ORIGINS (produção).
// A ponte do WhatsApp fala de servidor para servidor (sem Origin) e não depende disto.
const ORIGENS = new Set(["https://agenciadirectadm-hue.github.io",
  ...(Deno.env.get("CORS_ORIGINS") ?? "").split(",").map((s) => s.trim()).filter(Boolean)]);
const LOCAL = /^http:\/\/(localhost|127\.0\.0\.1)(:\d{2,5})?$/;
function cors(req: Request): Record<string, string> {
  const o = req.headers.get("origin");
  return {
    ...(o && (ORIGENS.has(o) || LOCAL.test(o)) ? { "Access-Control-Allow-Origin": o } : {}),
    "Vary": "Origin",
    "Access-Control-Allow-Headers": "content-type, x-iara-session, x-request-id",
    "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
    "Access-Control-Max-Age": "86400",
  };
}
const SEGURANCA = { "x-content-type-options": "nosniff", "referrer-policy": "no-referrer", "cache-control": "no-store" };
type Json = (data: unknown, status?: number, extra?: Record<string, string>) => Response;
const jsonPara = (req: Request): Json => (data, status = 200, extra = {}) =>
  new Response(JSON.stringify(data), { status, headers: { ...cors(req), ...SEGURANCA, "content-type": "application/json; charset=utf-8", ...extra } });

// IP do cliente: a Cloudflare na frente do Supabase preenche cf-connecting-ip (forjar esse cabeçalho é recusado na borda;
// x-forwarded-for enviado pelo cliente é substituído) — conferido em 07/10/2026
function ipDe(req: Request): string {
  return (req.headers.get("cf-connecting-ip") ?? req.headers.get("x-real-ip") ?? (req.headers.get("x-forwarded-for") ?? "").split(",")[0]).trim() || "desconhecido";
}

// Limites (SEC-AT-01), contados no banco (vale para todas as instâncias). Janela fixa: [chave, máximo, segundos].
function limitesPara(path: string, ip: string, token: string | null): [string, number, number][] {
  const l: [string, number, number][] = [];
  if (path.startsWith("/whatsapp/")) return l; // ponte autenticada por segredo; o limite é por telefone (whatsapp.ts)
  l.push([`ip:${ip}`, 3000, 300]);
  if (token) l.push([`sessao:${token.slice(0, 16)}`, 900, 60]);
  if (path === "/session") l.push([`nova-sessao:${ip}`, 40, 600]);
  if (path === "/iara/message") l.push([`iara:${ip}`, 120, 60]);
  if (path === "/arquivo") l.push([`envio:${ip}`, 60, 600]);
  if (path.startsWith("/rotas") || path === "/geo/localizar") l.push([`rotas:${ip}`, 120, 60]);
  return l;
}
// pré-limite por instância, em memória (barato, antes de tocar no banco): segura rajadas de um mesmo IP
const rajadas = new Map<string, number[]>();
function rajada(ip: string, max = 40, janelaMs = 10_000): boolean {
  const agora = Date.now();
  const h = (rajadas.get(ip) ?? []).filter((t) => agora - t < janelaMs);
  h.push(agora);
  rajadas.set(ip, h);
  if (rajadas.size > 5000) rajadas.clear();
  return h.length > max;
}

async function excedeu(limites: [string, number, number][]): Promise<string | null> {
  if (!limites.length) return null;
  try {
    const r = await sql`select iara.taxa(${limites.map((x) => x[0])}::text[], ${limites.map((x) => x[1])}::int[], ${limites.map((x) => x[2])}::int[]) as k`;
    return (r[0]?.k as string | null) ?? null;
  } catch (e) {
    console.error("limite", (e as Error).message); // falha do contador não derruba o atendimento
    return null;
  }
}

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function newToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

let statusRotas: { em: number; valor: unknown } | null = null;

// Rotinas periódicas: expiração de ofertas e atualização temporal do modo demonstração
let lastHousekeeping = 0;
let housekeepingRunning: Promise<void> | null = null;
function housekeeping(meta: RequestMeta) {
  if (housekeepingRunning || Date.now() - lastHousekeeping < 5 * 60_000) return housekeepingRunning;
  lastHousekeeping = Date.now();
  housekeepingRunning = asSystem(null, meta, (tx) => tx`select iara.housekeeping() as r`)
    .then(() => descartarArquivos(meta).catch((e) => console.error("descarte de arquivos", e?.message)))
    .then(() => undefined)
    .catch((e) => console.error("housekeeping", e?.message))
    .finally(() => {
      housekeepingRunning = null;
    });
  return housekeepingRunning;
}

// Rotas que faltam na fila (inscrição nova, mudança de endereço — por qualquer canal): calculadas em segundo plano,
// no máximo a cada 2 min por instância; com o critério medido pela rota, a fila se reordena sozinha.
let ultimaRotas = 0;
let rotasRodando = false;
function rotasPendentes(meta: RequestMeta) {
  if (rotasRodando || Date.now() - ultimaRotas < 2 * 60_000) return;
  ultimaRotas = Date.now();
  rotasRodando = true;
  const pendentes = (_fn: string, a: unknown) =>
    asSystem(null, meta, (tx) => tx`select iara.rotas_pendentes(${sql.json((a ?? {}) as never)}::jsonb) as r`).then((r) => r[0]?.r);
  const job = rotasDaFila(pendentes, gravarRotas(null, meta), { tempo_s: 40 })
    .then((r) => { if (r.calculadas || r.erro) console.log("rotas pendentes", JSON.stringify(r)); })
    .catch((e) => console.error("rotas pendentes", e?.message))
    .finally(() => { rotasRodando = false; });
  (globalThis as unknown as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } }).EdgeRuntime?.waitUntil?.(job);
}

async function resolveUser(req: Request): Promise<{ userId: string | null; expired: boolean }> {
  const token = req.headers.get("x-iara-session");
  if (!token) return { userId: null, expired: false };
  const hash = await sha256(token);
  const rows = await sql`select iara.session_resolve(${hash}) as uid`;
  const uid = (rows[0]?.uid as string | null) ?? null;
  return { userId: uid, expired: !uid };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(req) });
  const json = jsonPara(req);
  const url = new URL(req.url);
  const path = url.pathname.replace(/^.*?\/api(?=\/|$)/, "") || "/";
  const meta: RequestMeta = {
    rid: (req.headers.get("x-request-id") ?? crypto.randomUUID()).slice(0, 80),
    ip: ipDe(req),
    ua: (req.headers.get("user-agent") ?? "").slice(0, 300),
  };

  // tamanho do corpo (SEC-AT-02): 1 MB; a entrada do WhatsApp aceita áudio (até 16 MB)
  const limiteCorpo = path === "/whatsapp/entrada" ? 16_000_000 : path === "/arquivo" ? ARQUIVO_MAX_BYTES + 4096 : 1_000_000;
  if (Number(req.headers.get("content-length") ?? "0") > limiteCorpo) {
    // o proxy da plataforma só devolve a resposta depois que o corpo é lido: descarta sem guardar
    try { for await (const _ of req.body ?? []) { /* descarta */ } } catch { /* conexão encerrada */ }
    return json({ error: "Conteúdo grande demais." }, 413);
  }

  try {
    if (path !== "/health") {
      if (!path.startsWith("/whatsapp/") && rajada(meta.ip)) {
        return json({ error: "Muitas requisições em pouco tempo. Aguarde um instante e tente de novo.", code: "RATE_LIMIT" }, 429, { "retry-after": "10" });
      }
      const k = await excedeu(limitesPara(path, meta.ip, req.headers.get("x-iara-session")));
      if (k) return json({ error: "Muitas requisições em pouco tempo. Aguarde um instante e tente de novo.", code: "RATE_LIMIT" }, 429, { "retry-after": "60" });
    }

    if (path === "/health") {
      const rows = await sql`select now() as now, iara.rule_version() as rules`;
      return json({ ok: true, ...rows[0], audio: audioDisponivel() });
    }

    const hk = housekeeping(meta);
    rotasPendentes(meta);
    if (hk && path.startsWith("/rpc/dashboard")) await hk;

    if (path === "/session" && req.method === "POST") {
      const body = await req.json().catch(() => ({}));
      const persona = String(body?.persona ?? "");
      const unitId = body?.unit_id != null ? Number(body.unit_id) : null;
      const token = newToken();
      const hash = await sha256(token);
      const created = await asSystem(null, meta, (tx) => tx`select iara.session_create(${persona}, ${unitId}, ${hash}, ${meta.ua}) as r`);
      const userId = (created[0]?.r as { user_id: string }).user_id;
      const me = await callApi(userId, meta, "me", {});
      return json({ token, me });
    }

    if (path === "/session" && req.method === "DELETE") {
      const token = req.headers.get("x-iara-session");
      if (token) await sql`select iara.session_revoke(${await sha256(token)})`;
      return json({ ok: true });
    }

    // arquivos: envio (PDF ou foto) e leitura, sempre com a sessão e o escopo conferidos no banco
    if (path === "/arquivo" && req.method === "POST") {
      const { userId, expired } = await resolveUser(req);
      if (!userId || expired) return json({ error: "Sua sessão expirou. Entre novamente.", code: "SESSION_EXPIRED" }, 401);
      const q = url.searchParams;
      const bytes = new Uint8Array(await req.arrayBuffer());
      if (bytes.length > ARQUIVO_MAX_BYTES) return json({ error: "Arquivo maior que 10 MB." }, 413);
      const r = await guardarArquivo(userId, meta, bytes, {
        finalidade: q.get("finalidade") ?? "", student_id: q.get("student_id"), staff_id: q.get("staff_id"), doc_type: q.get("doc_type"),
        origem: q.get("origem"), nome: q.get("nome"),
      });
      return json(r);
    }
    const arq = path.match(/^\/arquivo\/([0-9a-f-]{36})$/);
    if (arq && req.method === "GET") {
      const { userId, expired } = await resolveUser(req);
      if (!userId || expired) return json({ error: "Sua sessão expirou. Entre novamente.", code: "SESSION_EXPIRED" }, 401);
      const a = await lerArquivo(userId, meta, arq[1]);
      return new Response(a.corpo, {
        headers: {
          ...cors(req), "content-type": a.mime, "content-disposition": `inline; filename*=UTF-8''${encodeURIComponent(a.nome)}`,
          "cache-control": "private, max-age=300", "x-content-type-options": "nosniff", "referrer-policy": "no-referrer",
        },
      });
    }

    if (path.startsWith("/rpc/") && req.method === "POST") {
      const fn = path.slice(5);
      const { userId, expired } = await resolveUser(req);
      if (expired) return json({ error: "Sua sessão expirou. Escolha um perfil novamente.", code: "SESSION_EXPIRED" }, 401);
      const args = await req.json().catch(() => ({}));
      const result = await callApi(userId, meta, fn, args);
      return json(result ?? {});
    }

    if (path === "/iara/message" && req.method === "POST") {
      const { userId, expired } = await resolveUser(req);
      if (!userId || expired) return json({ error: "Sessão necessária para conversar com a IARA.", code: "SESSION_EXPIRED" }, 401);
      const body = await req.json().catch(() => ({}));
      const text = String(body?.text ?? "").slice(0, 2000);
      const action = body?.action ? String(body.action).slice(0, 200) : null;
      if (!text.trim() && !action) return json({ error: "Mensagem vazia." }, 422);

      const snap = (await callApi(userId, meta, "iara_send", {
        conversation_id: body?.conversation_id, body: text || action, payload: action ? { action } : {},
      })) as ConvSnapshot;

      // Atendimento humano ativo ou pendente: a IARA não responde (evita disputa com o servidor)
      if (snap.state === "HUMAN_ACTIVE" || snap.state === "HUMAN_PENDING") {
        const conv = (await callApi(userId, meta, "conversation_detail", { id: snap.conversation_id })) as object;
        return json({ ...conv, bot_paused: true });
      }

      const chamar = (fn: string, args: unknown) => callApi(userId, meta, fn, args);
      const agent = new Agent(chamar, snap, distanciasComPrazo(chamar, gravarRotas(userId, meta)), { demo: await modoDemo() });
      await agent.handle(text, action);
      const saved = await asSystem(userId, meta, (tx) =>
        tx`select iara.agent_reply(${snap.conversation_id}::uuid, ${sql.json(agent.messages as never)}::jsonb,
                                   ${sql.json({ ...agent.patch, context: agent.ctx } as never)}::jsonb, ${sql.json(agent.tools as never)}::jsonb) as r`);
      return json(saved[0]?.r ?? {});
    }

    // localização de endereço do cadastro (CEP e geocodificação); só o endereço sai para o serviço externo
    if (path === "/geo/localizar" && req.method === "POST") {
      const { userId, expired } = await resolveUser(req);
      if (!userId || expired) return json({ error: "Sessão necessária.", code: "SESSION_EXPIRED" }, 401);
      const body = await req.json().catch(() => ({}));
      return json(await localizarEndereco(body ?? {}));
    }

    // distâncias: linha reta (banco) + rotas a pé e de carro (motor OSRM), guardadas no cache
    if ((path === "/rotas" || path === "/rotas/fila") && req.method === "POST") {
      const { userId, expired } = await resolveUser(req);
      if (!userId || expired) return json({ error: "Sessão necessária.", code: "SESSION_EXPIRED" }, 401);
      const corpo = await req.json().catch(() => ({}));
      const api = (fn: string, a: unknown) => callApi(userId, meta, fn, a);
      const gravar = gravarRotas(userId, meta);
      return json(path === "/rotas" ? await distanciasComRotas(api, gravar, corpo ?? {}) : await rotasDaFila(api, gravar, corpo ?? {}));
    }

    // situação do motor de rotas (a pé e de carro): uma rota mínima em cada perfil, guardada por 10 min
    if (path === "/rotas/status" && req.method === "GET") {
      if (!statusRotas || Date.now() - statusRotas.em > 600_000) {
        const a = { lat: -23.4254, lng: -51.9617 }, b = { lat: -23.4051, lng: -51.9387 };
        const teste = async (modo: "A_PE" | "CARRO") => {
          const t0 = Date.now();
          try { const r = await rota(modo, a, b); return { ok: r.distancia_m != null, distancia_m: r.distancia_m, ms: Date.now() - t0 }; }
          catch (e) { return { ok: false, erro: (e as Error).message, ms: Date.now() - t0 }; }
        };
        statusRotas = { em: Date.now(), valor: { provedor: PROVEDOR, a_pe: await teste("A_PE"), carro: await teste("CARRO") } };
      }
      return json(statusRotas.valor);
    }

    const wa = await handleWhatsApp(path, req, meta, json);
    if (wa) return wa;

    return json({ error: "Rota não encontrada." }, 404);
  } catch (e) {
    const mapped = mapDbError(e);
    return json({ error: mapped.message, code: mapped.code }, mapped.status);
  }
});
