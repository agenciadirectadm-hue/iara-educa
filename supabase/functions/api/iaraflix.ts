// IARAFLIX: vídeos de treinamento num bucket PRIVADO. O banco confere a sessão e o perfil; aqui o gateway assina links curtos do Storage.
// Assistir: link de leitura que vale 15 minutos (o navegador pede o vídeo por trechos direto ao Storage, para poder avançar e voltar).
// Enviar (só a gestão): link de envio assinado, o vídeo vai direto ao Storage; na confirmação o gateway lê os primeiros bytes e recusa o que não
// for MP4, WebM ou WebVTT de verdade (apaga o arquivo), antes de o banco publicar.
import { callApi, type RequestMeta } from "./db.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const CHAVE_SERVICO = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const VALIDADE_S = 15 * 60;

const cab = () => ({ Authorization: `Bearer ${CHAVE_SERVICO}`, apikey: CHAVE_SERVICO });
const caminhoUrl = (caminho: string) => caminho.split("/").map(encodeURIComponent).join("/");
const erro = (msg: string, code = "P0001") => Object.assign(new Error(msg), { code });

function exigirStorage() {
  if (!SUPABASE_URL || !CHAVE_SERVICO) throw erro("Armazenamento de vídeos indisponível.");
}

async function assinarLeitura(bucket: string, caminho: string): Promise<string> {
  const r = await fetch(`${SUPABASE_URL}/storage/v1/object/sign/${bucket}/${caminhoUrl(caminho)}`, {
    method: "POST", headers: { ...cab(), "content-type": "application/json" }, body: JSON.stringify({ expiresIn: VALIDADE_S }),
  });
  if (!r.ok) throw erro(`Vídeo indisponível (${r.status}).`, "P0002");
  const d = await r.json() as { signedURL?: string };
  if (!d.signedURL) throw erro("Vídeo indisponível.", "P0002");
  return `${SUPABASE_URL}/storage/v1${d.signedURL}`;
}

/** Link do vídeo (e da legenda) de uma aula, depois de o banco conferir que a aula é da trilha de quem pede. */
export async function assistir(userId: string, meta: RequestMeta, aulaId: string) {
  const a = (await callApi(userId, meta, "iaraflix_video_acesso", { id: aulaId })) as { bucket: string; video: string; legenda: string | null; mime: string };
  exigirStorage();
  const [video, legenda] = await Promise.all([assinarLeitura(a.bucket, a.video), a.legenda ? assinarLeitura(a.bucket, a.legenda) : Promise.resolve(null)]);
  return { video, legenda, mime: a.mime, expira_em: new Date(Date.now() + VALIDADE_S * 1000).toISOString() };
}

/** Envio: o banco autoriza (gestão do IARAFLIX, tipo e tamanho) e dá o caminho; o Storage assina o envio direto. */
export async function autorizarEnvio(userId: string, meta: RequestMeta, corpo: Record<string, unknown>) {
  const a = (await callApi(userId, meta, "iaraflix_envio_autorizar", corpo)) as { bucket: string; caminho: string; mime: string };
  exigirStorage();
  const r = await fetch(`${SUPABASE_URL}/storage/v1/object/upload/sign/${a.bucket}/${caminhoUrl(a.caminho)}`, { method: "POST", headers: cab() });
  if (!r.ok) throw erro(`Não foi possível preparar o envio (${r.status}).`);
  const d = await r.json() as { url?: string };
  if (!d.url) throw erro("Não foi possível preparar o envio.");
  return { caminho: a.caminho, mime: a.mime, url: `${SUPABASE_URL}/storage/v1${d.url}` };
}

function tipoReal(b: Uint8Array): string | null {
  if (b.length >= 12 && String.fromCharCode(b[4], b[5], b[6], b[7]) === "ftyp") return "video/mp4";
  if (b.length >= 4 && b[0] === 0x1a && b[1] === 0x45 && b[2] === 0xdf && b[3] === 0xa3) return "video/webm";
  const ini = b[0] === 0xef && b[1] === 0xbb && b[2] === 0xbf ? 3 : 0;
  if (new TextDecoder().decode(b.slice(ini, ini + 6)) === "WEBVTT") return "text/vtt";
  return null;
}

async function apagar(bucket: string, caminho: string) {
  await fetch(`${SUPABASE_URL}/storage/v1/object/${bucket}`, {
    method: "DELETE", headers: { ...cab(), "content-type": "application/json" }, body: JSON.stringify({ prefixes: [caminho] }),
  }).catch(() => {});
}

/** Confere o arquivo enviado pelos primeiros bytes e pelo tamanho real; se não for do tipo esperado, apaga. */
async function conferirEnviado(caminho: string, esperado: string[]): Promise<{ mime: string; total: number }> {
  const bucket = "iara-treinamento";
  const r = await fetch(`${SUPABASE_URL}/storage/v1/object/${bucket}/${caminhoUrl(caminho)}`, { headers: { ...cab(), Range: "bytes=0-63" } });
  if (!r.ok) throw erro("O arquivo não chegou ao armazenamento. Envie de novo.", "P0002");
  const inicio = new Uint8Array(await r.arrayBuffer()).slice(0, 64);
  const total = Number((r.headers.get("content-range") ?? "").split("/")[1] ?? r.headers.get("content-length") ?? 0);
  const mime = tipoReal(inicio);
  if (!mime || !esperado.includes(mime)) {
    await apagar(bucket, caminho);
    throw erro(esperado[0] === "text/vtt" ? "A legenda deve estar em WebVTT (.vtt)." : "O arquivo não é um vídeo MP4 ou WebM.", "22023");
  }
  return { mime, total };
}

/** Confirmação do envio: confere o conteúdo pelos primeiros bytes e o tamanho real; só então o banco publica. */
export async function confirmarEnvio(userId: string, meta: RequestMeta, corpo: Record<string, unknown>) {
  exigirStorage();
  const caminho = String(corpo.caminho ?? "");
  if (!/^aulas\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.(mp4|webm|vtt)$/.test(caminho)) throw erro("Caminho do arquivo inválido.", "22023");
  const { mime, total } = await conferirEnviado(caminho, String(corpo.tipo ?? "").toUpperCase() === "LEGENDA" ? ["text/vtt"] : ["video/mp4", "video/webm"]);
  try {
    return await callApi(userId, meta, "iaraflix_envio_confirmar", { ...corpo, caminho, mime, bytes: total || null });
  } catch (e) {
    await apagar("iara-treinamento", caminho);
    throw e;
  }
}

// ---------------------------------------------------------------- vídeos da SEDUC para as famílias (conteúdo público)

/** Link do arquivo de um vídeo publicado para as famílias: vale sem login (o banco só libera o que está publicado). */
export async function assistirFamilia(userId: string | null, meta: RequestMeta, id: string) {
  const a = (await callApi(userId, meta, "videos_familia_acesso", { id })) as { bucket: string; video: string; mime: string };
  exigirStorage();
  return { video: await assinarLeitura(a.bucket, a.video), mime: a.mime, expira_em: new Date(Date.now() + VALIDADE_S * 1000).toISOString() };
}

export async function autorizarEnvioFamilia(userId: string, meta: RequestMeta, corpo: Record<string, unknown>) {
  const a = (await callApi(userId, meta, "videos_familia_envio_autorizar", corpo)) as { bucket: string; caminho: string; mime: string };
  exigirStorage();
  const r = await fetch(`${SUPABASE_URL}/storage/v1/object/upload/sign/${a.bucket}/${caminhoUrl(a.caminho)}`, { method: "POST", headers: cab() });
  if (!r.ok) throw erro(`Não foi possível preparar o envio (${r.status}).`);
  const d = await r.json() as { url?: string };
  if (!d.url) throw erro("Não foi possível preparar o envio.");
  return { caminho: a.caminho, mime: a.mime, url: `${SUPABASE_URL}/storage/v1${d.url}` };
}

export async function confirmarEnvioFamilia(userId: string, meta: RequestMeta, corpo: Record<string, unknown>) {
  exigirStorage();
  const caminho = String(corpo.caminho ?? "");
  if (!/^familias\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.(mp4|webm)$/.test(caminho)) throw erro("Caminho do arquivo inválido.", "22023");
  const { mime, total } = await conferirEnviado(caminho, ["video/mp4", "video/webm"]);
  try {
    return await callApi(userId, meta, "videos_familia_envio_confirmar", { ...corpo, caminho, mime, bytes: total || null });
  } catch (e) {
    await apagar("iara-treinamento", caminho);
    throw e;
  }
}
