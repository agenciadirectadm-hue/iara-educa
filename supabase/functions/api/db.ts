// Conexão com o Postgres e execução no contexto do usuário (mesma semântica do PostgREST):
// cada requisição roda numa transação com `set local role` e `request.jwt.claims`,
// de modo que a RLS e as permissões do banco decidem o que cada perfil pode ver e fazer.
import postgres from "npm:postgres@3.4.5";

const DB_URL = Deno.env.get("SUPABASE_DB_URL");
if (!DB_URL) throw new Error("SUPABASE_DB_URL ausente no ambiente da função.");

export const sql = postgres(DB_URL, {
  prepare: false,
  max: 4,
  idle_timeout: 20,
  connect_timeout: 10,
  onnotice: () => {},
});

export type RequestMeta = { rid: string; ip: string; ua: string };
export type Tx = postgres.TransactionSql<Record<string, unknown>>;

export async function withUser<T>(userId: string | null, meta: RequestMeta, fn: (tx: Tx) => Promise<T>): Promise<T> {
  return await sql.begin(async (tx) => {
    await tx.unsafe(userId ? "set local role authenticated" : "set local role anon");
    const claims = JSON.stringify(userId ? { sub: userId, role: "authenticated" } : { role: "anon" });
    await tx`select set_config('request.jwt.claims', ${claims}, true),
                    set_config('iara.request_id', ${meta.rid}, true),
                    set_config('iara.ip', ${meta.ip}, true),
                    set_config('iara.ua', ${meta.ua}, true)`;
    return await fn(tx as unknown as Tx);
  }) as T;
}

/** Executa como o sistema (owner), mas registrando o usuário nas claims para auditoria. */
export async function asSystem<T>(userId: string | null, meta: RequestMeta, fn: (tx: Tx) => Promise<T>): Promise<T> {
  return await sql.begin(async (tx) => {
    const claims = JSON.stringify(userId ? { sub: userId, role: "authenticated" } : { role: "service" });
    await tx`select set_config('request.jwt.claims', ${claims}, true),
                    set_config('iara.request_id', ${meta.rid}, true),
                    set_config('iara.ip', ${meta.ip}, true),
                    set_config('iara.ua', ${meta.ua}, true)`;
    return await fn(tx as unknown as Tx);
  }) as T;
}

/** Guarda rotas calculadas no cache e atualiza as inscrições da fila com aquela casa e unidade. */
export const gravarRotas = (userId: string | null, meta: RequestMeta) => (itens: unknown[]) =>
  asSystem(userId, meta, (tx) => tx`select iara.rotas_gravar(${sql.json({ itens } as never)}::jsonb) as n`).then(() => undefined);

/** Interruptor demo_mode do município (tenants.settings), lido a cada minuto no máximo. */
let demoCache: { em: number; v: boolean } | null = null;
export async function modoDemo(): Promise<boolean> {
  if (!demoCache || Date.now() - demoCache.em > 60_000) {
    const r = await sql`select coalesce((iara.setting('demo_mode'))::boolean, false) as d`;
    demoCache = { em: Date.now(), v: r[0]?.d === true };
  }
  return demoCache.v;
}

let apiFunctions: Set<string> | null = null;
let loadedAt = 0;

export async function isApiFunction(name: string): Promise<boolean> {
  if (!/^[a-z][a-z0-9_]{1,62}$/.test(name)) return false;
  if (!apiFunctions || Date.now() - loadedAt > 5 * 60_000 || !apiFunctions.has(name)) {
    const rows = await sql`select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'api'`;
    apiFunctions = new Set(rows.map((r) => r.proname as string));
    loadedAt = Date.now();
  }
  return apiFunctions.has(name);
}

/** Chama api.<fn>(p jsonb) no contexto do usuário. O nome já foi validado contra o catálogo do schema api. */
export async function callApi(userId: string | null, meta: RequestMeta, fn: string, args: unknown): Promise<unknown> {
  if (!(await isApiFunction(fn))) {
    const err = new Error("Função desconhecida.") as Error & { code?: string };
    err.code = "P0002";
    throw err;
  }
  const rows = await withUser(userId, meta, (tx) => tx.unsafe(`select api.${fn}($1::jsonb) as r`, [sql.json((args ?? {}) as never) as never]));
  return (rows as unknown as { r: unknown }[])[0]?.r ?? null;
}

export function mapDbError(e: unknown): { status: number; message: string; code?: string } {
  const err = e as { code?: string; message?: string };
  const code = err?.code;
  const message = err?.message ?? "Erro inesperado.";
  if (code === "42501") return { status: 403, message, code };
  if (code === "28000") return { status: 401, message, code };
  if (code === "P0002") return { status: 404, message, code };
  if (["22023", "23505", "55006", "P0001", "22P02", "22007", "22008", "23503", "23514"].includes(code ?? "")) {
    return { status: 422, message, code };
  }
  console.error("db_error", code, message);
  return { status: 500, message: "Não foi possível concluir a operação agora. Tente novamente em instantes.", code };
}
