// Cliente do gateway IARA Educa. O navegador não guarda chaves do Supabase — apenas um token de sessão opaco.
export const API_URL: string =
  (import.meta.env.VITE_API_URL as string | undefined) ?? 'https://fqpjbyhewzngutbyydig.supabase.co/functions/v1/api';

export class ApiError extends Error {
  status: number;
  code?: string;
  constructor(message: string, status: number, code?: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

let token: string | null = null;
let expiredHandler: (() => void) | null = null;

export function setApiToken(t: string | null) {
  token = t;
}
export function onSessionExpired(cb: () => void) {
  expiredHandler = cb;
}

async function request<T>(path: string, init: RequestInit): Promise<T> {
  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, {
      ...init,
      headers: { 'content-type': 'application/json', ...(token ? { 'x-iara-session': token } : {}), ...(init.headers ?? {}) },
    });
  } catch {
    throw new ApiError('Sem conexão com o servidor. Verifique a internet e tente novamente.', 0, 'OFFLINE');
  }
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    if (res.status === 401 && (data as { code?: string })?.code === 'SESSION_EXPIRED') expiredHandler?.();
    throw new ApiError((data as { error?: string })?.error ?? 'Falha de comunicação.', res.status, (data as { code?: string })?.code);
  }
  return data as T;
}

export function rpc<T = any>(fn: string, args: object = {}): Promise<T> {
  return request<T>(`/rpc/${fn}`, { method: 'POST', body: JSON.stringify(args) });
}

export function createSession(persona: string, unitId?: number | null) {
  return request<{ token: string; me: any }>('/session', { method: 'POST', body: JSON.stringify({ persona, unit_id: unitId ?? null }) });
}

export function endSession() {
  return request<{ ok: boolean }>('/session', { method: 'DELETE' }).catch(() => ({ ok: false }));
}

export function iaraMessage(conversationId: string, text: string, action?: string | null) {
  return request<any>('/iara/message', { method: 'POST', body: JSON.stringify({ conversation_id: conversationId, text, action: action ?? null }) });
}
