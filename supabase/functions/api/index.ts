// IARA Educa — gateway da API (Edge Function `api`).
// O front-end não guarda nenhuma chave do Supabase: fala apenas com este gateway.
// Rotas:
//   GET    /health
//   POST   /session          { persona, unit_id? }     → cria sessão de demonstração (token opaco)
//   DELETE /session                                     → encerra a sessão
//   POST   /rpc/:fn          { ...args }               → executa api.<fn>(args) com RLS do perfil
//   POST   /iara/message     { conversation_id, text, action? } → agente IARA (WhatsApp simulado / portal)
//   POST   /geo/localizar    { cep?, logradouro?, ... } → CEP e coordenada do endereço do cadastro (ver geo.ts)
//   *      /whatsapp/...                               → ponte do WhatsApp real (ver whatsapp.ts)
import { asSystem, callApi, mapDbError, sql, type RequestMeta } from "./db.ts";
import { Agent, type ConvSnapshot } from "./iara.ts";
import { audioDisponivel, handleWhatsApp } from "./whatsapp.ts";
import { localizarEndereco } from "./geo.ts";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-iara-session, x-request-id",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

const json = (data: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(data), { status, headers: { ...CORS, "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...extra } });

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function newToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// Limite simples por IP para criação de sessões (proteção do ambiente de demonstração)
const sessionHits = new Map<string, number[]>();
function rateLimited(ip: string, max = 40, windowMs = 10 * 60_000): boolean {
  const now = Date.now();
  const hits = (sessionHits.get(ip) ?? []).filter((t) => now - t < windowMs);
  hits.push(now);
  sessionHits.set(ip, hits);
  return hits.length > max;
}

// Rotinas periódicas: expiração de ofertas e atualização temporal do modo demonstração
let lastHousekeeping = 0;
let housekeepingRunning: Promise<void> | null = null;
function housekeeping(meta: RequestMeta) {
  if (housekeepingRunning || Date.now() - lastHousekeeping < 5 * 60_000) return housekeepingRunning;
  lastHousekeeping = Date.now();
  housekeepingRunning = asSystem(null, meta, (tx) => tx`select iara.housekeeping() as r`)
    .then(() => undefined)
    .catch((e) => console.error("housekeeping", e?.message))
    .finally(() => {
      housekeepingRunning = null;
    });
  return housekeepingRunning;
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
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  const url = new URL(req.url);
  const path = url.pathname.replace(/^.*?\/api(?=\/|$)/, "") || "/";
  const meta: RequestMeta = {
    rid: req.headers.get("x-request-id") ?? crypto.randomUUID(),
    ip: (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "desconhecido",
    ua: (req.headers.get("user-agent") ?? "").slice(0, 300),
  };

  try {
    if (path === "/health") {
      const rows = await sql`select now() as now, iara.rule_version() as rules`;
      return json({ ok: true, ...rows[0], audio: audioDisponivel() });
    }

    const hk = housekeeping(meta);
    if (hk && path.startsWith("/rpc/dashboard")) await hk;

    if (path === "/session" && req.method === "POST") {
      if (rateLimited(meta.ip)) return json({ error: "Muitas sessões criadas a partir deste endereço. Aguarde alguns minutos." }, 429);
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

      const agent = new Agent((fn, args) => callApi(userId, meta, fn, args), snap);
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

    const wa = await handleWhatsApp(path, req, meta, json);
    if (wa) return wa;

    return json({ error: "Rota não encontrada." }, 404);
  } catch (e) {
    const mapped = mapDbError(e);
    return json({ error: mapped.message, code: mapped.code }, mapped.status);
  }
});
