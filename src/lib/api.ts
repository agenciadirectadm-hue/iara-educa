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
/** Token da sessão para chamadas que não são JSON (envio e leitura de arquivos). */
export function apiToken() {
  return token;
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

/** CEP (ViaCEP) e coordenada do endereço do cadastro — só o endereço sai do sistema, nunca dados da pessoa. */
export function geoLocalizar(body: { cep?: string; logradouro?: string; numero?: string; bairro?: string; cidade?: string }) {
  return request<{
    cep: { cep: string; logradouro: string | null; bairro: string | null; cidade: string; uf: string } | null;
    cep_erro: string | null;
    candidatos: { lat: number; lng: number; precisao: string; fonte: string; rotulo: string }[];
    fora_de_maringa: boolean;
    geocodificador: 'ok' | 'indisponivel';
    aviso: string | null;
  }>('/geo/localizar', { method: 'POST', body: JSON.stringify(body) });
}

/** Trecho de rota guardado no cache (a pé ou de carro); `sem_rota` quando o motor não achou caminho. */
export type TrechoRota = { distancia_m: number; duracao_s: number; calculado_em: string; provedor: string; sem_rota?: undefined } | { sem_rota: true } | null;
export type MedidaDistancia = 'LINHA_RETA' | 'A_PE' | 'CARRO';
export type DistanciaUnidade = {
  id: number; nome: string; curto: string; tipo: string; lat: number; lng: number; vagas?: number | null;
  linha_reta_m: number; a_pe: TrechoRota; carro: TrechoRota;
};
export type Distancias = {
  origem: { lat: number; lng: number };
  criterio: { medida: MedidaDistancia; limite_m: number; regra: string; versao: string };
  unidades: DistanciaUnidade[];
  rotas: { A_PE?: [number, number][]; CARRO?: [number, number][] } | null;
  /** traçado da rota escolhida no seletor (a pé ou de carro) até cada unidade da lista, por id da unidade */
  trajetos_modo?: 'A_PE' | 'CARRO' | null;
  trajetos?: Record<string, [number, number][]> | null;
  provedor?: string;
  motor_indisponivel?: string | null;
  /** o prazo da chamada acabou antes de todas as rotas: pedir de novo completa o restante */
  parcial?: boolean;
};
export type PedidoDistancias = {
  lat: number; lng: number; unidades?: number[]; proximas?: number; faixa_id?: number | null; geometria_unidade?: number | null;
  geometrias_modo?: 'A_PE' | 'CARRO' | null;
};

/** Linha reta, a pé e de carro de um ponto às unidades; calcula no motor de rotas o que ainda não está guardado. */
export function rotasCalcular(body: PedidoDistancias) {
  return request<Distancias>('/rotas', { method: 'POST', body: JSON.stringify(body) });
}

/** Rotas da fila ativa em lote (casa × unidade pretendida) — repetir até `pendentes` = 0. */
export function rotasFila(tempoS = 100) {
  return request<{ calculadas: number; consultas: number; pendentes: number; pares_total: number; provedor: string; erro: string | null; segundos: number }>(
    '/rotas/fila', { method: 'POST', body: JSON.stringify({ tempo_s: tempoS }) });
}

/** Situação do motor de rotas (uma rota de teste em cada perfil). */
export function rotasStatus() {
  return request<{ provedor: string; a_pe: { ok: boolean; ms: number; erro?: string }; carro: { ok: boolean; ms: number; erro?: string } }>('/rotas/status', { method: 'GET' });
}
