// Arquivos (documentos em PDF e fotos): o banco autoriza e registra; o gateway confere o conteúdo e guarda no Storage.
// O bucket é privado e só a chave de serviço (aqui no servidor) lê e grava: o navegador nunca recebe link direto.
// Conferências: tipo real pelos primeiros bytes (não pela extensão), tamanho, e fotos sem metadados (EXIF/GPS, XMP, IPTC,
// comentários) — foto de criança não sai com a localização de casa.
import { asSystem, callApi, type RequestMeta } from "./db.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const CHAVE_SERVICO = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
export const ARQUIVO_MAX_BYTES = 10 * 1024 * 1024;

const EXT: Record<string, string> = { "application/pdf": "pdf", "image/jpeg": "jpg", "image/png": "png" };

/** Tipo pelo conteúdo: PDF (%PDF-), JPEG (FF D8 FF) ou PNG (assinatura de 8 bytes). Qualquer outra coisa é recusada. */
export function tipoReal(b: Uint8Array): string | null {
  if (b.length > 5 && b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46 && b[4] === 0x2d) return "application/pdf";
  if (b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "image/jpeg";
  const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (b.length > 8 && png.every((v, i) => b[i] === v)) return "image/png";
  return null;
}

/** JPEG sem APP1 (EXIF/XMP), APP12, APP13 (IPTC) e comentários; PNG sem blocos de texto, data e EXIF. */
export function semMetadados(b: Uint8Array, mime: string): Uint8Array {
  try {
    if (mime === "image/jpeg") {
      const out: number[] = [0xff, 0xd8];
      let i = 2;
      while (i + 3 < b.length) {
        if (b[i] !== 0xff) return b; // estrutura inesperada: devolve como veio (o tipo já foi conferido)
        const m = b[i + 1];
        if (m === 0xda) { for (let j = i; j < b.length; j++) out.push(b[j]); return new Uint8Array(out); }
        if (m === 0xd8 || m === 0x01 || (m >= 0xd0 && m <= 0xd7)) { out.push(0xff, m); i += 2; continue; }
        const len = (b[i + 2] << 8) | b[i + 3];
        const fim = i + 2 + len;
        if (![0xe1, 0xec, 0xed, 0xfe].includes(m)) for (let j = i; j < fim && j < b.length; j++) out.push(b[j]);
        i = fim;
      }
      return b;
    }
    if (mime === "image/png") {
      const fora = new Set(["tEXt", "iTXt", "zTXt", "eXIf", "tIME"]);
      const partes: Uint8Array[] = [b.slice(0, 8)];
      let i = 8;
      while (i + 12 <= b.length) {
        const len = ((b[i] << 24) >>> 0) + (b[i + 1] << 16) + (b[i + 2] << 8) + b[i + 3];
        const tipo = String.fromCharCode(b[i + 4], b[i + 5], b[i + 6], b[i + 7]);
        const fim = i + 12 + len;
        if (!fora.has(tipo)) partes.push(b.slice(i, fim));
        i = fim;
        if (tipo === "IEND") break;
      }
      const total = partes.reduce((s, p) => s + p.length, 0);
      const out = new Uint8Array(total);
      let k = 0;
      for (const p of partes) { out.set(p, k); k += p.length; }
      return out;
    }
  } catch { /* em dúvida, guarda o original (o tipo já foi conferido) */ }
  return b;
}

async function sha256(b: Uint8Array): Promise<string> {
  const h = new Uint8Array(await crypto.subtle.digest("SHA-256", b));
  return Array.from(h).map((x) => x.toString(16).padStart(2, "0")).join("");
}

function exigirStorage() {
  if (!SUPABASE_URL || !CHAVE_SERVICO) throw Object.assign(new Error("Armazenamento de arquivos indisponível."), { code: "P0001" });
}
const cab = () => ({ Authorization: `Bearer ${CHAVE_SERVICO}`, apikey: CHAVE_SERVICO });
const url = (bucket: string, caminho: string) => `${SUPABASE_URL}/storage/v1/object/${bucket}/${caminho.split("/").map(encodeURIComponent).join("/")}`;

async function enviarStorage(bucket: string, caminho: string, bytes: Uint8Array, mime: string) {
  exigirStorage();
  const r = await fetch(url(bucket, caminho), { method: "POST", headers: { ...cab(), "content-type": mime, "x-upsert": "false" }, body: bytes });
  if (!r.ok) throw new Error(`Falha ao guardar o arquivo (${r.status}).`);
}

export async function removerStorage(bucket: string, caminhos: string[]) {
  if (!caminhos.length) return;
  exigirStorage();
  const r = await fetch(`${SUPABASE_URL}/storage/v1/object/${bucket}`, {
    method: "DELETE", headers: { ...cab(), "content-type": "application/json" }, body: JSON.stringify({ prefixes: caminhos }),
  });
  if (!r.ok) throw new Error(`Falha ao apagar arquivos (${r.status}).`);
}

export type Envio = {
  finalidade: string; student_id?: string | null; staff_id?: string | null; doc_type?: string | null; origem?: string | null; nome?: string | null;
};

/** Autoriza no banco, confere o conteúdo, guarda no Storage e registra (desfaz o arquivo se o registro falhar). */
export async function guardarArquivo(userId: string, meta: RequestMeta, bruto: Uint8Array, envio: Envio): Promise<Record<string, unknown>> {
  if (!bruto.length) throw Object.assign(new Error("Arquivo vazio."), { code: "22023" });
  if (bruto.length > ARQUIVO_MAX_BYTES) throw Object.assign(new Error("Arquivo maior que 10 MB."), { code: "22023" });
  const mime = tipoReal(bruto);
  if (!mime) throw Object.assign(new Error("Formato não aceito: documento em PDF; foto em JPEG ou PNG."), { code: "22023" });
  const params = { finalidade: envio.finalidade, student_id: envio.student_id ?? null, staff_id: envio.staff_id ?? null, doc_type: envio.doc_type ?? null };
  const regra = (await callApi(userId, meta, "arquivo_autorizar", params)) as { tipos: string[]; max_bytes: number; bucket: string; prefixo: string };
  if (!regra.tipos.includes(mime)) {
    throw Object.assign(new Error(envio.finalidade === "DOCUMENTO" ? "Documento só em PDF." : "Foto só em JPEG ou PNG."), { code: "22023" });
  }
  const bytes = mime === "application/pdf" ? bruto : semMetadados(bruto, mime);
  if (bytes.length > regra.max_bytes) throw Object.assign(new Error(`Arquivo maior que ${Math.round(regra.max_bytes / 1048576)} MB.`), { code: "22023" });
  const caminho = `${regra.prefixo}/${crypto.randomUUID()}.${EXT[mime]}`;
  await enviarStorage(regra.bucket, caminho, bytes, mime);
  try {
    return (await callApi(userId, meta, "arquivo_confirmar", {
      ...params, caminho, mime, tamanho: bytes.length, sha256: await sha256(bytes), nome: (envio.nome ?? "").slice(0, 200) || null, origem: envio.origem ?? null,
    })) as Record<string, unknown>;
  } catch (e) {
    await removerStorage(regra.bucket, [caminho]).catch(() => {});
    throw e;
  }
}

/** Lê o arquivo depois de o banco conferir o escopo de quem pede (e registrar a abertura de documento). */
export async function lerArquivo(userId: string, meta: RequestMeta, id: string): Promise<{ corpo: ReadableStream<Uint8Array> | null; mime: string; nome: string }> {
  const a = (await callApi(userId, meta, "arquivo_acesso", { id })) as { bucket: string; caminho: string; mime: string; nome: string };
  exigirStorage();
  const r = await fetch(url(a.bucket, a.caminho), { headers: cab() });
  if (!r.ok) throw Object.assign(new Error("Arquivo indisponível."), { code: "P0002" });
  return { corpo: r.body, mime: a.mime, nome: a.nome };
}

/** Rotina: apaga do Storage o que foi para a fila de descarte (fotos recusadas, limpeza da demonstração). */
export async function descartarArquivos(meta: RequestMeta) {
  if (!SUPABASE_URL || !CHAVE_SERVICO) return;
  const fila = ((await asSystem(null, meta, (tx) => tx`select iara.arquivos_para_descartar(100) as f`))[0]?.f ?? []) as { caminho: string; bucket: string }[];
  if (!fila.length) return;
  const porBucket = new Map<string, string[]>();
  for (const f of fila) porBucket.set(f.bucket, [...(porBucket.get(f.bucket) ?? []), f.caminho]);
  for (const [bucket, caminhos] of porBucket) {
    await removerStorage(bucket, caminhos);
    await asSystem(null, meta, (tx) => tx`select iara.arquivos_descartados(${caminhos}::text[]) as n`);
  }
}
