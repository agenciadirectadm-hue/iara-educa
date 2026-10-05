// Distâncias por ROTA (a pé e de carro) — além da linha reta, calculada no banco.
// Motor: OSRM sobre o OpenStreetMap, que cobre qualquer município. Configurável por implantação:
//   ROTAS_OSRM_A_PE  / ROTAS_OSRM_CARRO   servidor OSRM de cada perfil
//   padrão: servidores públicos da FOSSGIS (routing.openstreetmap.de) — gratuitos, para uso leve e demonstração.
//   Produção: um OSRM (ou Valhalla/GraphHopper com a mesma API) do município, do consórcio ou do estado, com o
//   recorte do OpenStreetMap da região — as coordenadas das casas não saem da rede pública.
// Só coordenadas vão para o motor de rotas — nunca nome, CPF ou endereço escrito.
//
// Limites do servidor público (medidos em 05/10/2026): a matriz (`table`) responde a uma consulta a cada ~10 s por
// endereço de origem, aceita URLs de até ~8 mil caracteres (~320 pontos) e até 10 mil células (origens × destinos);
// a rota (`route`) responde sem espera. Por isso: o lote da fila usa poucas matrizes grandes; as telas usam rotas
// avulsas, algumas em paralelo.

export type Modo = 'A_PE' | 'CARRO';
export type Ponto = { lat: number; lng: number };
export type Trecho = { distancia_m: number | null; duracao_s: number | null };

const BASE: Record<Modo, string> = {
  A_PE: (Deno.env.get('ROTAS_OSRM_A_PE') ?? 'https://routing.openstreetmap.de/routed-foot').replace(/\/$/, ''),
  CARRO: (Deno.env.get('ROTAS_OSRM_CARRO') ?? 'https://routing.openstreetmap.de/routed-car').replace(/\/$/, ''),
};
export const PROVEDOR = Deno.env.get('ROTAS_OSRM_A_PE') ? 'OSRM (servidor próprio)' : 'OSRM · OpenStreetMap (FOSSGIS)';
const UA = 'IARA-Educa/1.0 (+https://agenciadirectadm-hue.github.io/iara-educa/)';
/** Tamanho máximo do caminho da consulta de matriz (o servidor recusa URLs maiores com 414). */
const MAX_URL = Number(Deno.env.get('ROTAS_MAX_URL') ?? 7800);
/** Células por matriz (origens × destinos) — `max-table-size` do OSRM ao quadrado; 100² no servidor público. */
const MAX_CELULAS = Number(Deno.env.get('ROTAS_MAX_CELULAS') ?? 10_000);
/** Rotas avulsas simultâneas (educação com o servidor público). */
const PARALELO = 3;

// matrizes: uma por vez (o servidor público enfileira as demais de qualquer forma)
let fila: Promise<unknown> = Promise.resolve();
function emOrdem<T>(fn: () => Promise<T>): Promise<T> {
  const p = fila.then(fn, fn);
  fila = p.then(() => undefined, () => undefined);
  return p;
}

async function emParalelo<T, R>(itens: T[], n: number, fn: (x: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(itens.length);
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(n, itens.length) }, async () => {
    while (i < itens.length) {
      const k = i++;
      out[k] = await fn(itens[k]);
    }
  }));
  return out;
}

const coord = (p: Ponto) => `${p.lng.toFixed(5)},${p.lat.toFixed(5)}`;

async function osrm(modo: Modo, caminho: string, tempo = 20_000): Promise<any> {
  const r = await fetch(`${BASE[modo]}/${caminho}`, { headers: { 'User-Agent': UA }, signal: AbortSignal.timeout(tempo) });
  const j = await r.json().catch(() => null);
  // NoRoute / NoSegment: o motor respondeu, mas não há caminho (ex.: ponto fora da malha) — não é falha do serviço
  if (j && (j.code === 'NoRoute' || j.code === 'NoSegment')) return j;
  if (!r.ok || !j || (j.code && j.code !== 'Ok')) throw new Error(`rotas ${modo}: ${r.status} ${j?.code ?? ''} ${j?.message ?? ''}`.trim());
  return j;
}

const caminhoMatriz = (origens: Ponto[], destinos: Ponto[]) =>
  `table/v1/driving/${[...origens, ...destinos].map(coord).join(';')}?sources=${origens.map((_, i) => i).join(';')}` +
  `&destinations=${destinos.map((_, k) => origens.length + k).join(';')}&annotations=distance,duration`;

/** Matriz origens × destinos (distância em metros e tempo em segundos), pela malha viária do perfil. */
export async function matriz(modo: Modo, origens: Ponto[], destinos: Ponto[]): Promise<Trecho[][]> {
  const j = await emOrdem(() => osrm(modo, caminhoMatriz(origens, destinos), 60_000));
  return origens.map((_, i) => destinos.map((_, k) => ({
    distancia_m: j.distances?.[i]?.[k] == null ? null : Math.round(j.distances[i][k]),
    duracao_s: j.durations?.[i]?.[k] == null ? null : Math.round(j.durations[i][k]),
  })));
}

/** Rota de uma origem a um destino; com `tracado`, traz a linha do caminho (para desenhar no mapa). */
export async function rota(modo: Modo, origem: Ponto, destino: Ponto, tracado = true, tempo = 20_000): Promise<Trecho & { geometria: [number, number][] | null }> {
  const j = await osrm(modo, `route/v1/driving/${coord(origem)};${coord(destino)}?` + (tracado ? 'overview=full&geometries=geojson' : 'overview=false'), tempo);
  const r = j.routes?.[0];
  if (!r) return { distancia_m: null, duracao_s: null, geometria: null };
  return {
    distancia_m: Math.round(r.distance), duracao_s: Math.round(r.duration),
    geometria: tracado ? (r.geometry?.coordinates ?? []).map((c: number[]) => [Number(c[0].toFixed(5)), Number(c[1].toFixed(5))]) : null,
  };
}

type Api = (fn: string, args: unknown) => Promise<any>;
type Gravar = (itens: unknown[]) => Promise<void>;
const MODOS: Modo[] = ['A_PE', 'CARRO'];
const CHAVE: Record<Modo, 'a_pe' | 'carro'> = { A_PE: 'a_pe', CARRO: 'carro' };

/**
 * POST /rotas — as três medidas (linha reta, a pé, de carro) de um ponto às unidades indicadas ou às mais próximas.
 * O que ainda não está no cache é calculado no motor de rotas e guardado; com `geometria_unidade`, traz o traçado das
 * duas rotas até aquela unidade, e com `geometrias_modo` (A_PE | CARRO), o traçado dessa rota até cada unidade da lista. Cada chamada tem prazo (`prazo_ms`, padrão 10 s): o que não
 * couber volta com `parcial: true` e a tela pede de novo — a linha reta sempre vem, e falha do motor não impede a resposta.
 */
export async function distanciasComRotas(api: Api, gravar: Gravar, corpo: Record<string, unknown>) {
  const pedido = {
    lat: corpo?.lat, lng: corpo?.lng, unidades: corpo?.unidades, proximas: corpo?.proximas, faixa_id: corpo?.faixa_id,
    geometria_unidade: corpo?.geometria_unidade, geometrias_modo: corpo?.geometrias_modo,
  };
  const prazo = Date.now() + Math.min(Math.max(Number(corpo?.prazo_ms) || 10_000, 3_000), 25_000);
  let d = await api('distancias', pedido);
  const origem = { lat: Number(d.origem.lat), lng: Number(d.origem.lng) };
  const alvo = Number(corpo?.geometria_unidade) || null;
  const tarefas: { u: any; modo: Modo; tracado: boolean }[] = [];
  for (const u of d.unidades as any[]) {
    for (const modo of MODOS) {
      // traçado: as duas rotas até a unidade em foco e/ou a rota escolhida (seletor do mapa) até todas as unidades da lista
      const tracado = !u[CHAVE[modo]]?.sem_rota &&
        ((u.id === alvo && !d.rotas?.[modo]) || (modo === d.trajetos_modo && !d.trajetos?.[String(u.id)]));
      if (u[CHAVE[modo]] && !tracado) continue;
      tarefas.push({ u, modo, tracado });
    }
  }
  tarefas.sort((a, b) => Number(b.tracado) - Number(a.tracado)); // o traçado do mapa primeiro
  let erro: string | null = null;
  let adiadas = 0;
  const restante = () => prazo - Date.now();
  const calcular = async (t: (typeof tarefas)[number]) => {
    const r = await rota(t.modo, origem, { lat: Number(t.u.lat), lng: Number(t.u.lng) }, t.tracado, Math.min(8_000, Math.max(restante(), 1_000)));
    return { ...origem, unit_id: t.u.id, modo: t.modo, ...r, provedor: PROVEDOR };
  };
  const falhas: (typeof tarefas)[number][] = [];
  const itens: unknown[] = (await emParalelo(tarefas, PARALELO, async (t) => {
    if (restante() < 1_500) {
      adiadas++;
      return null;
    }
    try {
      return await calcular(t);
    } catch {
      falhas.push(t);
      return null;
    }
  })).filter(Boolean);
  // o servidor público às vezes recusa ou segura consultas em sequência: o que falhou é refeito uma a uma, se houver prazo
  if (falhas.length && restante() > 2_500) await new Promise((r) => setTimeout(r, 700));
  for (const t of falhas) {
    if (restante() < 1_500) {
      adiadas++;
      continue;
    }
    try {
      itens.push(await calcular(t));
    } catch (e) {
      erro = (e as Error).message;
      adiadas++;
      console.warn('rotas', t.modo, t.u.id, erro);
    }
  }
  if (itens.length) {
    await gravar(itens);
    d = await api('distancias', pedido);
  }
  return { ...d, provedor: PROVEDOR, motor_indisponivel: erro, parcial: adiadas > 0 };
}

/** Distâncias para a IARA (mesmo cálculo do portal), com prazo curto: a conversa não fica esperando o motor. */
export function distanciasComPrazo(api: Api, gravar: Gravar, ms = 7000) {
  return (pedido: Record<string, unknown>) => distanciasComRotas(api, gravar, { ...pedido, prazo_ms: ms });
}

/**
 * POST /rotas/fila — calcula, em lote, as rotas (casa × unidade pretendida) da fila ativa que ainda faltam.
 * Empacota várias unidades e as casas de quem pede cada uma numa matriz grande (até o limite de URL do servidor);
 * cada chamada trabalha por até `tempo_s` segundos (padrão 100) — repita até `pendentes` = 0.
 */
export async function rotasDaFila(api: Api, gravar: Gravar, corpo: Record<string, unknown>) {
  const inicio = Date.now();
  const limite = Math.min(Math.max(Number(corpo?.tempo_s) || 100, 10), 130) * 1000;
  const p = await api('fila_rotas_pendentes', { unidades: 400 });
  let calculadas = 0;
  let consultas = 0;
  let erro: string | null = null;
  for (const modo of MODOS) {
    // pacotes: destinos (unidades) + origens (casas) cabendo numa URL; um grupo grande se divide em vários pacotes
    type Pacote = { destinos: Ponto[]; ids: number[]; origens: Ponto[]; pares: [number, number][] };
    const pacotes: Pacote[] = [];
    let atual: Pacote = { destinos: [], ids: [], origens: [], pares: [] };
    const cabe = (pk: Pacote) => pk.origens.length * pk.destinos.length <= MAX_CELULAS &&
      caminhoMatriz(pk.origens, pk.destinos).length + BASE[modo].length <= MAX_URL;
    for (const g of (p.grupos as any[]).filter((x) => x.modo === modo)) {
      const destino = { lat: Number(g.lat), lng: Number(g.lng) };
      for (const o of g.origens as any[]) {
        const origem = { lat: Number(o.lat), lng: Number(o.lng) };
        const tentativa = (pk: Pacote) => {
          let k = pk.ids.indexOf(g.unit_id);
          const novo: Pacote = { destinos: k < 0 ? [...pk.destinos, destino] : pk.destinos, ids: k < 0 ? [...pk.ids, g.unit_id] : pk.ids,
                                 origens: [...pk.origens, origem], pares: pk.pares };
          if (k < 0) k = novo.ids.length - 1;
          return { novo, k };
        };
        let { novo, k } = tentativa(atual);
        if (!cabe(novo)) {
          pacotes.push(atual);
          atual = { destinos: [], ids: [], origens: [], pares: [] };
          ({ novo, k } = tentativa(atual));
        }
        atual = { ...novo, pares: [...novo.pares, [novo.origens.length - 1, k]] };
      }
    }
    if (atual.origens.length) pacotes.push(atual);
    for (const pk of pacotes) {
      if (Date.now() - inicio > limite - 15_000) break;
      try {
        const m = await matriz(modo, pk.origens, pk.destinos);
        consultas++;
        await gravar(pk.pares.map(([i, k]) => ({ ...pk.origens[i], unit_id: pk.ids[k], modo, ...m[i][k], provedor: PROVEDOR })));
        calculadas += pk.pares.length;
      } catch (e) {
        erro = (e as Error).message;
        break;
      }
    }
    if (erro) break;
  }
  const depois = await api('fila_rotas_pendentes', { unidades: 1 });
  return { calculadas, consultas, pendentes: depois.pendentes, pares_total: depois.pares_total, provedor: PROVEDOR, erro, segundos: Math.round((Date.now() - inicio) / 1000) };
}
