// Localização de endereço para o cadastro de alunos e responsáveis.
//   CEP → logradouro e bairro (ViaCEP)
//   endereço → coordenada (OpenStreetMap/Nominatim, ou o serviço configurado em GEOCODER_URL)
// Só o endereço sai para o serviço externo — nunca nome, CPF ou qualquer outro dado da pessoa.
// O ponto sempre pode ser conferido e ajustado no mapa pelo servidor (precisão "PONTO_NO_MAPA").

const VIACEP = "https://viacep.com.br/ws";
const GEOCODER = (Deno.env.get("GEOCODER_URL") ?? "https://nominatim.openstreetmap.org").replace(/\/$/, "");
const UA = "IARA-Educa/1.0 (+https://agenciadirectadm-hue.github.io/iara-educa/)";
// Maringá e distritos (Iguatemi, Floriano), com folga — o geocodificador não devolve pontos fora daqui
const VIEWBOX = "-52.20,-23.20,-51.75,-23.65";

export type Candidato = { lat: number; lng: number; precisao: "ENDERECO" | "LOGRADOURO"; fonte: string; rotulo: string };
type Cep = { cep: string; logradouro: string | null; bairro: string | null; cidade: string; uf: string; ibge: string | null };

const cache = new Map<string, { em: number; valor: unknown }>();
const DIA = 86_400_000;
function lembrar<T>(chave: string, valor: T): T {
  if (cache.size > 800) cache.delete(cache.keys().next().value as string);
  cache.set(chave, { em: Date.now(), valor });
  return valor;
}
function lembrado<T>(chave: string): T | undefined {
  const c = cache.get(chave);
  return c && Date.now() - c.em < DIA ? (c.valor as T) : undefined;
}

// política de uso do Nominatim: no máximo uma consulta por segundo
let fila: Promise<unknown> = Promise.resolve();
function umPorSegundo<T>(fn: () => Promise<T>): Promise<T> {
  const p = fila.then(fn, fn);
  const espera = () => new Promise((r) => setTimeout(r, 1100));
  fila = p.then(espera, espera);
  return p;
}

async function buscarCep(cep: string): Promise<Cep | { erro: string }> {
  const d = cep.replace(/\D/g, "");
  if (d.length !== 8) return { erro: "CEP inválido: são 8 dígitos." };
  const c = lembrado<Cep | { erro: string }>("cep:" + d);
  if (c) return c;
  try {
    const r = await fetch(`${VIACEP}/${d}/json/`, { signal: AbortSignal.timeout(6000) });
    const j = await r.json();
    if (!r.ok || j?.erro) return lembrar("cep:" + d, { erro: "CEP não encontrado." });
    return lembrar("cep:" + d, {
      cep: j.cep, logradouro: j.logradouro || null, bairro: j.bairro || null, cidade: j.localidade, uf: j.uf, ibge: j.ibge || null,
    });
  } catch {
    return { erro: "A consulta de CEP está indisponível agora. Preencha o endereço e marque o ponto no mapa." };
  }
}

async function nominatim(params: Record<string, string>): Promise<Candidato[]> {
  const qs = new URLSearchParams({ format: "jsonv2", limit: "3", countrycodes: "br", addressdetails: "1", viewbox: VIEWBOX, bounded: "1", ...params });
  const itens = await umPorSegundo(async () => {
    const r = await fetch(`${GEOCODER}/search?${qs}`, {
      headers: { "User-Agent": UA, "Accept-Language": "pt-BR" }, signal: AbortSignal.timeout(8000),
    });
    if (!r.ok) throw new Error(`geocodificador respondeu ${r.status}`);
    return (await r.json()) as Array<{ lat: string; lon: string; display_name: string; address?: { house_number?: string } }>;
  });
  return (itens ?? []).map((i) => ({
    lat: Number(i.lat), lng: Number(i.lon), precisao: i.address?.house_number ? "ENDERECO" : "LOGRADOURO",
    fonte: "OpenStreetMap", rotulo: i.display_name,
  }));
}

let ultimoErro: string | null = null;
// recusa do serviço (403/429: o OpenStreetMap não atende servidores em nuvem compartilhada) → pausa de 1 h;
// nesse intervalo o navegador consulta o mapa diretamente
let pausadoAte = 0;

async function geocodificar(q: { logradouro: string; numero?: string; bairro?: string; cidade: string; cep?: string }): Promise<Candidato[]> {
  const rua = [q.numero, q.logradouro].filter(Boolean).join(" ").trim();
  const chave = `geo:${rua}|${q.bairro ?? ""}|${q.cidade}`.toLowerCase();
  const c = lembrado<Candidato[]>(chave);
  if (c) return c;
  if (Date.now() < pausadoAte) {
    ultimoErro = "serviço de mapa recusou consultas do servidor (pausa temporária)";
    return [];
  }
  try {
    let out = await nominatim({ street: rua, city: q.cidade, state: "Paraná" });
    if (!out.length) {
      out = await nominatim({ q: [rua, q.bairro, `${q.cidade}, PR`].filter(Boolean).join(", ") });
    }
    ultimoErro = null;
    return lembrar(chave, out);
  } catch (e) {
    ultimoErro = (e as Error).message;
    if (/ 40[13]| 429/.test(ultimoErro)) pausadoAte = Date.now() + 3_600_000;
    console.error("geocodificar", ultimoErro);
    return [];
  }
}

/** POST /geo/localizar { cep?, logradouro?, numero?, bairro?, cidade? } */
export async function localizarEndereco(body: Record<string, unknown>) {
  const texto = (v: unknown) => (typeof v === "string" ? v.trim().slice(0, 160) : "");
  let cep: Cep | null = null;
  let cepErro: string | null = null;
  if (texto(body.cep)) {
    const r = await buscarCep(texto(body.cep));
    if ("erro" in r) cepErro = r.erro;
    else cep = r;
  }
  const logradouro = texto(body.logradouro) || cep?.logradouro || "";
  const bairro = texto(body.bairro) || cep?.bairro || "";
  const cidade = texto(body.cidade) || cep?.cidade || "Maringá";
  const candidatos = logradouro
    ? await geocodificar({ logradouro, numero: texto(body.numero), bairro, cidade, cep: cep?.cep })
    : [];
  return {
    cep, cep_erro: cepErro, candidatos,
    fora_de_maringa: cep ? cep.cidade.toLowerCase() !== "maringá" : false,
    geocodificador: ultimoErro ? "indisponivel" : "ok",
    geocodificador_erro: ultimoErro,
    aviso: logradouro && !candidatos.length
      ? "Não encontramos este endereço no mapa. Use o centro do bairro ou toque no mapa para marcar a casa."
      : null,
  };
}
